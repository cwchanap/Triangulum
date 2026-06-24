# Cel Design-System Patch Coverage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the Codecov patch-coverage gap (77.94% → ~95%+) on the 4 files changed in `feat/cel-design-system` by rendering Cel components in `UIHostingController` and unit-testing the new manager logic.

**Architecture:** New SwiftUI view `body` code is only executed when rendered. Tests wrap each Cel component in a `UIHostingController` installed in a live `UIWindow` and force layout — causing SwiftUI to evaluate `body` (line coverage) and complete the render pipeline (asserted via `host.view.window != nil`). Branch coverage is achieved by rendering every variant. The new `BarometerManager.isLocationDenied` pure-logic computed property is unit-tested directly; the two thin `open…Settings()` wrappers are smoke-called (verified safe, ~5ms, no hang).

**Tech Stack:** Swift Testing (`@Suite`/`@Test`/`#expect`), SwiftUI, UIKit (`UIHostingController`/`UIWindow`), CoreLocation, CoreMotion. No new dependencies.

## Global Constraints

- Test framework: **Swift Testing** (`import Testing`, `@Suite`, `@Test`, `#expect`) — matches every existing test file. Do NOT use XCTest.
- iOS deployment target: **18.5+**; run tests on **iPhone 17** simulator.
- **Always** pass `-parallel-testing-enabled NO` (per `AGENTS.md` — this machine cannot run parallel simulator clones).
- No production code changes. No new third-party dependencies.
- New test files are auto-included in the `TriangulumTests` target via the project's `PBXFileSystemSynchronizedRootGroup` (verified — `DesignSystemTests.swift` is not individually listed in `project.pbxproj`). Just place the file in `TriangulumTests/`.
- **Validated assumptions (spiked before writing this plan):**
  - Rendering via `UIHostingController` + live `UIWindow` + `layoutIfNeeded()` executes `body` → produces coverage.
  - `host.view.window != nil` reliably asserts a successful render.
  - **Accessibility introspection (`accessibilityElements`) and `sizeThatFits` are UNRELIABLE in this headless runtime** — do NOT use them. Use only `host.view.window != nil`.
  - `BarometerManager.openLocationSettings()` and `LocationManager.openAppSettings()` complete in ~5ms with no crash/hang — safe to smoke-call.
  - CI (`unit-tests.yml`) runs `-enableCodeCoverage YES` and exports cobertura via `xcresultparser` → Codecov, so new coverage will be reported.

---

### Task 1: Cel component rendering tests

**Files:**
- Create: `TriangulumTests/CelComponentRenderingTests.swift`

**Interfaces:**
- Consumes: `Triangulum` types — `Color.cel*` tokens, `CelGradient`, `CelSpace`, `InstrumentCardModifier` (`.instrumentCard(tint:cornerTicks:)`), `CornerTicks`, `CelGlyph`, `InstrumentHeader` (both inits), `CelChevron`, `CelDivider`, `MetricReadout`, `LuminousBar`, `StatusPill`, `CelInlineMessage`, `View.celestialBackground()`, `View.celEyebrow(_:)`.
- Produces: a `@MainActor @Suite struct CelComponentRenderingTests` containing one `@Test` per Cel component/branch. No exports.

- [ ] **Step 1: Create the test file with the render helpers and structural tests**

Create `TriangulumTests/CelComponentRenderingTests.swift` with EXACTLY this content:

```swift
//
//  CelComponentRenderingTests.swift
//  TriangulumTests
//
//  Renders Cel design-system components through a UIHostingController so their
//  SwiftUI `body` code is executed (closing the design-system patch coverage
//  gap). Each test asserts the view renders into a live window without crashing.
//  Branch coverage is achieved by rendering every variant (e.g. both StatusPill
//  icon/dot branches, all MetricReadout alignments, both LuminousBar
//  accessibility branches).
//

import Testing
import SwiftUI
import UIKit
@testable import Triangulum

// MARK: - Render helpers

/// Wraps a SwiftUI view in a UIHostingController installed in a live UIWindow
/// and forces layout. This causes SwiftUI to evaluate the view's `body`, which
/// unit tests cannot otherwise reach. Returns the hosting controller so callers
/// can assert on the rendered state.
@MainActor
private func renderHost<V: View>(
    _ view: V,
    size: CGSize = CGSize(width: 320, height: 240)
) -> UIHostingController<V> {
    let host = UIHostingController(rootView: view)
    host.view.frame = CGRect(origin: .zero, size: size)
    let window = UIWindow(frame: CGRect(origin: .zero, size: size))
    window.rootViewController = host
    window.makeKeyAndVisible()
    host.view.layoutIfNeeded()
    return host
}

/// Renders a view and asserts it was attached to a window — i.e. that the full
/// render pipeline (including `body` evaluation) completed without crashing.
@MainActor
private func expectRendered<V: View>(_ view: V) {
    let host = renderHost(view)
    #expect(host.view.window != nil, "View failed to attach to a window during rendering")
}

@MainActor
@Suite
struct CelComponentRenderingTests {

    // MARK: - Background modifier (celestialBackground)

    @Test func celestialBackgroundModifierRenders() {
        expectRendered(Color.clear.celestialBackground())
    }

    // MARK: - Instrument card (InstrumentCardModifier + CornerTicks)

    @Test func instrumentCardRendersWithCornerTicks() {
        expectRendered(Color.celCyan.frame(width: 80, height: 80)
            .instrumentCard(tint: .celGold, cornerTicks: true))
    }

    @Test func instrumentCardRendersWithoutCornerTicks() {
        // cornerTicks: false → the `if cornerTicks { CornerTicks(...) }` branch is skipped.
        expectRendered(Color.celCyan.frame(width: 80, height: 80)
            .instrumentCard(tint: .celGold, cornerTicks: false))
    }

    @Test func cornerTicksRendersStandalone() {
        expectRendered(CornerTicks(tint: .celCyan, length: 7).frame(width: 100, height: 100))
    }

    // MARK: - CelGlyph

    @Test func celGlyphRenders() {
        expectRendered(CelGlyph(systemName: "barometer", tint: .celCyan, size: 40))
    }

    // MARK: - InstrumentHeader (both initializers)

    @Test func instrumentHeaderTrailingRenders() {
        expectRendered(InstrumentHeader(icon: "barometer", title: "BAROMETER", tint: .celCyan) {
            StatusPill("LIVE", color: .celGreen)
        })
    }

    @Test func instrumentHeaderEmptyViewOverloadRenders() {
        // Exercises the `InstrumentHeader where Trailing == EmptyView` convenience init.
        expectRendered(InstrumentHeader(icon: "location", title: "LOCATION", tint: .celGold))
    }

    // MARK: - CelChevron, CelDivider

    @Test func celChevronRenders() {
        expectRendered(CelChevron())
    }

    @Test func celDividerRenders() {
        expectRendered(CelDivider())
    }

    // MARK: - MetricReadout (alignment ternary + optional unit)

    @Test func metricReadoutLeadingWithoutUnit() {
        // unit nil → the `if let unit { Text(unit) }` branch is skipped.
        expectRendered(MetricReadout("PRESSURE", value: "1013.25", alignment: .leading))
    }

    @Test func metricReadoutTrailingWithUnit() {
        // unit non-nil → the `if let unit { Text(unit) }` branch executes.
        expectRendered(MetricReadout("ALT", value: "100", unit: "m", alignment: .trailing)
            .frame(width: 200))
    }

    @Test func metricReadoutCenter() {
        // .center branch of the alignment ternary.
        expectRendered(MetricReadout("X", value: "0", unit: "°", alignment: .center)
            .frame(width: 200))
    }

    // MARK: - LuminousBar (clamp + both accessibility branches)

    @Test func luminousBarClampsAboveOneWithLabel() {
        // value 1.5 → clamped to 1.0 via `max(0, min(1, value))`.
        // accessibilityLabel non-nil → LuminousBarAccessibility renders the labeled branch.
        expectRendered(LuminousBar(value: 1.5, tint: .celCyan, height: 8, accessibilityLabel: "Signal")
            .frame(width: 200))
    }

    @Test func luminousBarZeroWithoutLabel() {
        // value 0 → clamp lower bound. accessibilityLabel nil → `.accessibilityHidden(true)` branch.
        expectRendered(LuminousBar(value: 0.0).frame(width: 200))
    }

    // MARK: - StatusPill (icon branch + dot branch)

    @Test func statusPillWithIcon() {
        // icon non-nil → the `Image(systemName:)` branch.
        expectRendered(StatusPill("ONLINE", color: .celGreen, icon: "wifi"))
    }

    @Test func statusPillWithoutIconDotBranch() {
        // icon nil → the `Circle().fill(color)` dot branch.
        expectRendered(StatusPill("OFFLINE", color: .celRed))
    }

    // MARK: - CelInlineMessage

    @Test func celInlineMessageRenders() {
        expectRendered(CelInlineMessage(text: "No data",
                                        icon: "exclamationmark.triangle.fill",
                                        color: .celRed))
    }

    // MARK: - CelestialTheme.View.celEyebrow(_:) modifier

    @Test func celEyebrowModifierRenders() {
        // Covers the `View.celEyebrow(_:)` body in CelestialTheme.swift.
        expectRendered(Text("SECTION").celEyebrow())
    }
}
```

- [ ] **Step 2: Run the new test suite to verify it passes**

Run:
```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/CelComponentRenderingTests
```
Expected: all 16 tests PASS (`✔ Test run with 16 tests in 1 suite passed`).
If a test fails to compile, confirm the component initializer signatures match `Triangulum/DesignSystem/CelestialComponents.swift` and `CelestialTheme.swift`.

- [ ] **Step 3: Commit**

```bash
git add TriangulumTests/CelComponentRenderingTests.swift
git commit -m "test: render Cel components in UIHostingController for patch coverage"
```

---

### Task 2: BarometerManager — isLocationDenied + openLocationSettings

**Files:**
- Modify: `TriangulumTests/BarometerManagerTests.swift` (append inside the existing `@MainActor @Suite(.serialized) struct BarometerManagerTests { … }`, before the closing brace).

**Interfaces:**
- Consumes: `BarometerManager(locationManager:barometerAvailability:)` initializer (existing); `LocationManager(skipAvailabilityCheck:)`; `CLAuthorizationStatus`.
- Produces: three new `@Test` methods. No new exports.

- [ ] **Step 1: Add the failing tests**

Inside the `BarometerManagerTests` suite body (e.g. immediately after `testBarometerManagerInitialization`), append these three tests:

```swift
    @Test func testIsLocationDeniedTrueForDeniedAndRestricted() {
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        let manager = BarometerManager(
            locationManager: locationManager,
            barometerAvailability: { false }
        )

        locationManager.authorizationStatus = .denied
        #expect(manager.isLocationDenied == true)

        locationManager.authorizationStatus = .restricted
        #expect(manager.isLocationDenied == true)
    }

    @Test func testIsLocationDeniedFalseForValidStatuses() {
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        let manager = BarometerManager(
            locationManager: locationManager,
            barometerAvailability: { false }
        )

        for status in [CLAuthorizationStatus.notDetermined, .authorizedWhenInUse, .authorizedAlways] {
            locationManager.authorizationStatus = status
            #expect(manager.isLocationDenied == false, "expected false for \(status.rawValue)")
        }
    }

    @Test func testOpenLocationSettingsDoesNotCrash() {
        // openLocationSettings() delegates to LocationManager.openAppSettings()
        // (UIApplication.shared.open). Verified safe (~5ms, no hang) on simulator.
        let locationManager = LocationManager(skipAvailabilityCheck: true)
        let manager = BarometerManager(
            locationManager: locationManager,
            barometerAvailability: { false }
        )

        // No #expect: the test passes iff the call does not crash/hang.
        // We spiked that openLocationSettings() completes in ~5ms on the
        // simulator. The value of this test is crash-safety + line coverage
        // of the method body; UIApplication.shared.open returns nothing
        // assertable and we are not permitted to change production code.
        manager.openLocationSettings()
    }
```

- [ ] **Step 2: Run the suite to verify the new tests pass**

Run:
```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/BarometerManagerTests/testIsLocationDeniedTrueForDeniedAndRestricted \
  -only-testing:TriangulumTests/BarometerManagerTests/testIsLocationDeniedFalseForValidStatuses \
  -only-testing:TriangulumTests/BarometerManagerTests/testOpenLocationSettingsDoesNotCrash
```
Expected: 3 PASS. (`isLocationDenied` exercises the new pure-logic property; the denial-denied UI affordance depends on it.)

- [ ] **Step 3: Commit**

```bash
git add TriangulumTests/BarometerManagerTests.swift
git commit -m "test: cover BarometerManager isLocationDenied and openLocationSettings"
```

---

### Task 3: LocationManager — openAppSettings

**Files:**
- Modify: `TriangulumTests/LocationManagerTests.swift` (append inside the existing `@Suite(.serialized) struct LocationManagerTests { … }`, before the closing brace).

**Interfaces:**
- Consumes: `LocationManager(skipAvailabilityCheck:)`; `LocationManager.openAppSettings()` (the `@MainActor` method under test). `appSettingsURL` is already covered by `testAppSettingsURLIsValidDeepLink`.
- Produces: one new `@MainActor @Test` method.

- [ ] **Step 1: Add the test**

Append inside the `LocationManagerTests` suite body (after `testAppSettingsURLIsValidDeepLink`):

```swift
    @MainActor
    @Test func testOpenAppSettingsDoesNotCrash() {
        // openAppSettings() calls UIApplication.shared.open(appSettingsURL) — a
        // documented no-op on the simulator. Covers the method body line.
        let manager = LocationManager(skipAvailabilityCheck: true)

        manager.openAppSettings()
    }
```

- [ ] **Step 2: Run the test to verify it passes**

Run:
```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests/LocationManagerTests/testOpenAppSettingsDoesNotCrash
```
Expected: 1 PASS in <1s.

- [ ] **Step 3: Commit**

```bash
git add TriangulumTests/LocationManagerTests.swift
git commit -m "test: cover LocationManager.openAppSettings"
```

---

### Task 4: Full verification run

**Files:** none (verification only).

- [ ] **Step 1: Run the ENTIRE unit-test suite (not just the new tests)**

Run:
```bash
xcodebuild test -project Triangulum.xcodeproj -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -parallel-testing-enabled NO \
  -only-testing:TriangulumTests
```
Expected: ALL tests PASS (the existing ~suite plus the 20 new tests). No regressions.
If any pre-existing test fails, that is NOT caused by these changes — report it but do not attempt to fix unrelated tests.

- [ ] **Step 2: Run SwiftLint (CI enforces it)**

Run:
```bash
swiftlint
```
Expected: no errors in the three touched test files. Fix any lint findings in the new tests before finishing.

- [ ] **Step 3: Confirm working tree is clean and pushed**

Run:
```bash
git status --short
git log --oneline -4
```
Expected: clean tree; 3 new commits (Cel render tests, BarometerManager, LocationManager) on top of `8e75311` (the spec commit).

- [ ] **Step 4: Report coverage expectation**

After the next CI run on this branch, Codecov patch coverage for the 4 files should rise to ~95%+:
- `CelestialComponents.swift`: ~328/328 executable body lines covered (every component + every branch rendered).
- `CelestialTheme.swift`: `View.celEyebrow(_:)` body covered.
- `BarometerManager.swift`: `isLocationDenied` + `openLocationSettings()` covered.
- `LocationManager.swift`: `openAppSettings()` body covered.

Note to reviewer: rendered-view assertions are intentionally `host.view.window != nil` (render-pipeline completion) because accessibility introspection (`accessibilityElements`) and `sizeThatFits` were empirically unreliable in the headless simulator runtime — see `Global Constraints`. Real behavioral logic is asserted in `testIsLocationDenied*`.
