# Cel Design-System Patch Coverage

**Date:** 2026-06-24
**Branch:** `feat/cel-design-system`
**Status:** Approved

## Problem

Codecov reports patch coverage at **77.94%** (77 changed lines missing coverage)
on the `feat/cel-design-system` branch (merge-base `46532af`). The gap is
concentrated in newly-added SwiftUI component `body` code, which only executes
when a view is rendered.

| File | Patch | Missing | Root cause |
|------|-------|---------|------------|
| `Triangulum/DesignSystem/CelestialComponents.swift` | +328 (new) | 68 | SwiftUI `body` of `InstrumentCardModifier`, `CornerTicks`, `CelGlyph`, `InstrumentHeader`, `MetricReadout`, `LuminousBar`, `LuminousBarAccessibility`, `StatusPill`, `CelInlineMessage`, `CelChevron`, `CelDivider`, `celestialBackground()` |
| `Triangulum/DesignSystem/CelestialTheme.swift` | +117 (new) | 2 | `View.celEyebrow(_:)` modifier body |
| `Triangulum/Managers/BarometerManager.swift` | +16 | 5 | new `isLocationDenied` (pure logic) + `openLocationSettings()` (delegating wrapper) |
| `Triangulum/Managers/LocationManager.swift` | +26 | 2 | new `openAppSettings()` body (`UIApplication.shared.open`) |

## Goal

Raise patch coverage from **77.94% → ~95%+** without adding dependencies or
modifying production code. Tests must assert real behavior, not exist solely to
inflate coverage.

## Non-goals

- Adding `swift-snapshot-testing` or any SPM dependency.
- Refactoring production Cel components to extract logic purely for coverage.
- Whole-file (non-patch) coverage improvements outside the 4 changed files.

## Constraints

- Test style: **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`),
  matching all existing test files.
- No new third-party dependencies (single-developer Xcode project).
- iOS 18.5+ deployment target; run on iPhone 17 simulator with
  `-parallel-testing-enabled NO` (per `AGENTS.md`).
- Render-based tests must be `@MainActor` (UIHostingController is main-thread).

## Design

### Approach

Render Cel components through `UIHostingController` in unit tests. Installing the
hosted view in a `UIWindow` and forcing layout causes SwiftUI to evaluate each
component's `body` (line coverage) and produces a real accessibility tree
(behavioral assertions). This avoids a snapshot-testing dependency while still
exercising the rendered view code path.

Rejected alternatives:
- **Snapshot testing** — highest fidelity + visual regression, but adds an SPM
  dependency, reference-image management, and iOS-version flakiness. Disproportionate
  for a coverage gap.
- **Construction + logic extraction only** — covers inits but not `body`; would not
  meaningfully close the 68-line gap without refactoring production code for coverage.

### Component 1 — Cel rendering tests

New file: `TriangulumTests/CelComponentRenderingTests.swift`.

Shared `@MainActor` helper:

```swift
@MainActor
func render<V: View>(_ view: V, size: CGSize = CGSize(width: 320, height: 240)) -> UIHostingController<V> {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow()
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return host
}
```

Installing in a `UIWindow` + `makeKeyAndVisible()` + `layoutIfNeeded()` ensures
`body` evaluates (required for Canvas/TimelineView-based views and for reliable
accessibility tree generation).

Each test renders the component and asserts on rendered output / accessibility:

- `InstrumentCardModifier` — render via `.instrumentCard(tint:cornerTicks:)` for
  `cornerTicks: true` and `cornerTicks: false`.
- `CornerTicks` — render; assert `view.allowsHitTesting == false`.
- `CelGlyph` — render with varying `tint`/`size`; assert the element is marked
  accessibility-hidden.
- `InstrumentHeader` — render both initializers (trailing-closure form and the
  `Trailing == EmptyView` convenience init).
- `MetricReadout` — render with and without `unit`; cover `.leading`,
  `.trailing`, `.center` alignment (exercises the ternary frame mapping).
- `LuminousBar` — render with `value` `0`, `0.5`, `1.5` (clamp branch); render
  once with `accessibilityLabel` set and once `nil` to cover both branches of
  `LuminousBarAccessibility`; assert the `"… percent"` accessibility value.
- `StatusPill` — render with `icon` (Image branch) and without icon (Circle dot
  branch); assert merged `accessibilityLabel == text`.
- `CelInlineMessage`, `CelChevron`, `CelDivider` — render smoke (body execution).
- `celestialBackground()` modifier — render a host view with the modifier applied.
- `CelestialTheme` `View.celEyebrow(_:)` — render `Text("X").celEyebrow()` to
  execute the modifier body (covers the 2 theme lines).

### Component 2 — BarometerManager (extend `BarometerManagerTests.swift`)

- `isLocationDenied` — pure logic. Set `locationManager.authorizationStatus` to each
  value and assert: `true` for `.denied`, `.restricted`; `false` for `.notDetermined`,
  `.authorizedWhenInUse`, `.authorizedAlways`.
- `openLocationSettings()` — `@MainActor` smoke-call; assert it does not throw
  (covers the delegating line that calls `locationManager.openAppSettings()`).

### Component 3 — LocationManager (extend `LocationManagerTests.swift`)

- `openAppSettings()` — `@MainActor` smoke-call on the simulator; assert no crash.
  `appSettingsURL` is already covered by `testAppSettingsURLIsValidDeepLink`.

## Verification

1. `xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
   -destination 'platform=iOS Simulator,name=iPhone 17' \
   -parallel-testing-enabled NO`
2. Confirm all new tests pass and Codecov patch coverage for the 4 files is
   ~95%+ on the next report.

## Risk & mitigation

- **Risk:** `UIHostingController` body evaluation may not mark every nested line
  (e.g. `@ViewBuilder` branching) as covered without an active layout pass.
  **Mitigation:** `makeKeyAndVisible()` + `layoutIfNeeded()` on a real `UIWindow`;
  if any line remains uncovered, add a targeted assertion that forces the branch.
- **Risk:** `UIApplication.shared.open` on simulator behaves unpredictably.
  **Mitigation:** It is a documented no-op / `false` return off-device and does
  not crash; the test only asserts non-crashing execution.
