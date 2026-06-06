# Constellation Map UX Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redesign constellation map navigation so heading-follow pauses during manual pan or zoom and recovers through a clear recenter action.

**Architecture:** Add a small value-type camera helper that owns zoom, pan, exploration state, and effective heading. `ConstellationMapView` keeps rendering responsibilities but delegates orientation state transitions to the helper, making behavior unit-testable without Canvas pixel assertions.

**Tech Stack:** Swift, SwiftUI, Swift Testing, CoreGraphics, existing Xcode project `Triangulum.xcodeproj`.

---

## File Structure

- Create `Triangulum/Models/ConstellationCameraState.swift`: value type for camera state transitions and effective heading.
- Create `TriangulumTests/ConstellationCameraStateTests.swift`: focused Swift Testing coverage for exploration, frozen heading, zoom bounds, and recenter behavior.
- Modify `Triangulum/Views/ConstellationMapView.swift`: replace local `zoom` and `pan` state with `ConstellationCameraState`, update gestures, footer controls, menu, status chip, and drawing heading flow.

## Task 1: Camera State Helper

**Files:**
- Create: `Triangulum/Models/ConstellationCameraState.swift`
- Create: `TriangulumTests/ConstellationCameraStateTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `TriangulumTests/ConstellationCameraStateTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Triangulum

struct ConstellationCameraStateTests {
    @Test func startingExplorationCapturesHeadingOnce() {
        var state = ConstellationCameraState()

        state.beginExploring(currentHeading: 42.0)
        state.beginExploring(currentHeading: 128.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 42.0)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 42.0)
    }

    @Test func recenterResetsCameraAndReturnsToLiveHeading() {
        var state = ConstellationCameraState()
        state.beginExploring(currentHeading: 42.0)
        state.applyPan(CGSize(width: 24.0, height: -12.0), currentHeading: 42.0)
        state.applyZoomMultiplier(2.0, currentHeading: 42.0)

        state.recenter()

        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)
        #expect(state.zoom == 1.0)
        #expect(state.pan == .zero)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 128.0)
    }

    @Test func zoomStaysWithinBoundsAndStartsExploration() {
        var state = ConstellationCameraState()

        state.applyZoomMultiplier(10.0, currentHeading: 91.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 91.0)
        #expect(state.zoom == 3.0)

        state.applyZoomMultiplier(0.01, currentHeading: 180.0)

        #expect(state.frozenHeading == 91.0)
        #expect(state.zoom == 1.0)
    }

    @Test func panAccumulatesAndStartsExploration() {
        var state = ConstellationCameraState()

        state.applyPan(CGSize(width: 10.0, height: 4.0), currentHeading: 270.0)
        state.applyPan(CGSize(width: -2.0, height: 8.0), currentHeading: 12.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 270.0)
        #expect(state.pan == CGSize(width: 8.0, height: 12.0))
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:

```bash
# Use any available simulator. To list destinations:
#   xcodebuild -showdestinations -project Triangulum.xcodeproj -scheme Triangulum
# Or substitute a specific simulator UDID via:
#   xcrun simctl list devices available | grep "iPhone"
xcodebuild test \
  -project Triangulum.xcodeproj \
  -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:TriangulumTests/ConstellationCameraStateTests
```

Expected: FAIL because `ConstellationCameraState` does not exist.

- [ ] **Step 3: Implement the minimal camera helper**

Create `Triangulum/Models/ConstellationCameraState.swift`:

```swift
import CoreGraphics
import Foundation

struct ConstellationCameraState: Equatable {
    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 3.0

    var zoom: CGFloat = 1.0
    var pan: CGSize = .zero
    private(set) var isExploring = false
    private(set) var frozenHeading: Double?

    mutating func beginExploring(currentHeading: Double) {
        guard !isExploring else { return }
        isExploring = true
        frozenHeading = currentHeading
    }

    mutating func applyZoomMultiplier(_ multiplier: CGFloat, currentHeading: Double) {
        beginExploring(currentHeading: currentHeading)
        zoom = clampedZoom(zoom * multiplier)
    }

    mutating func applyPan(_ translation: CGSize, currentHeading: Double) {
        beginExploring(currentHeading: currentHeading)
        pan.width += translation.width
        pan.height += translation.height
    }

    mutating func recenter() {
        zoom = 1.0
        pan = .zero
        isExploring = false
        frozenHeading = nil
    }

    func effectiveHeading(liveHeading: Double) -> Double {
        frozenHeading ?? liveHeading
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        max(minZoom, min(maxZoom, value))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:

```bash
# See Step 2 for destination selection guidance.
xcodebuild test \
  -project Triangulum.xcodeproj \
  -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:TriangulumTests/ConstellationCameraStateTests
```

Expected: PASS for `ConstellationCameraStateTests`.

- [ ] **Step 5: Commit**

```bash
git add Triangulum/Models/ConstellationCameraState.swift TriangulumTests/ConstellationCameraStateTests.swift
git commit -m "Add constellation camera state"
```

## Task 2: Wire Camera State Into Constellation View

**Files:**
- Modify: `Triangulum/Views/ConstellationMapView.swift`
- Test: `TriangulumTests/ConstellationCameraStateTests.swift`

- [ ] **Step 1: Update view state and gesture usage**

In `ConstellationMapView`, replace:

```swift
@AppStorage("skySnapNorth") private var skySnapNorth = true
@State private var zoom: CGFloat = 1.0
@GestureState private var pinch: CGFloat = 1.0
@State private var pan: CGSize = .zero
@GestureState private var drag: CGSize = .zero
```

with:

```swift
@State private var camera = ConstellationCameraState()
@GestureState private var pinch: CGFloat = 1.0
@GestureState private var drag: CGSize = .zero
```

In the `TimelineView` block, replace current zoom and pan derivation with:

```swift
let currentZoom = max(min(camera.zoom * pinch, 3.0), 1.0)
let currentPan = CGSize(
    width: camera.pan.width + drag.width,
    height: camera.pan.height + drag.height
)
let effectiveHeading = camera.effectiveHeading(liveHeading: locationManager.heading)
```

Update gesture endings:

```swift
.onEnded { value in
    camera.applyZoomMultiplier(value, currentHeading: locationManager.heading)
}
```

```swift
.onEnded { value in
    camera.applyPan(value.translation, currentHeading: locationManager.heading)
}
```

Update double tap:

```swift
.onEnded { withAnimation(.easeInOut) { camera.recenter() } }
```

Pass `effectiveHeading` to `drawSky`.

- [ ] **Step 2: Update `drawSky` signature and internal heading flow**

Change `drawSky` to:

```swift
private func drawSky(
    context: inout GraphicsContext,
    size: CGSize,
    current: Date,
    zoom: CGFloat,
    pan: CGSize,
    effectiveHeading: Double
) {
```

Inside `drawSky`, use:

```swift
let headingRad = effectiveHeading * .pi / 180.0
```

Update `PlanetRenderer.draw`, `SatelliteRenderer.draw`, `drawSunAndMoon`, `drawRingsAndCardinals`, and `drawStarsAndConstellations` call sites to use `effectiveHeading` instead of `locationManager.heading` or `skySnapNorth`.

Change `drawSunAndMoon` signature to:

```swift
private func drawSunAndMoon(
    context: inout GraphicsContext,
    center: CGPoint,
    radius: CGFloat,
    observer: Observer,
    current: Date,
    effectiveHeading: Double,
    pan: CGSize
) {
```

Inside `drawSunAndMoon`, compute:

```swift
let headingRad = effectiveHeading * .pi / 180.0
let azOffsetRad = Double(pan.width) / Double(radius) * (Double.pi / 2.0)
let altOffsetDeg = -Double(pan.height) / Double(radius) * 90.0
```

Use those values for both Sun and Moon.

- [ ] **Step 3: Update footer controls and menu**

Replace footer zoom control actions with:

```swift
Button { withAnimation(.easeInOut) { camera.applyZoomMultiplier(1.0 / 1.15, currentHeading: locationManager.heading) } } label: {
    Image(systemName: "minus.circle").foregroundColor(nightVisionMode ? .red : .white)
}
Button { withAnimation(.easeInOut) { camera.applyZoomMultiplier(1.15, currentHeading: locationManager.heading) } } label: {
    Image(systemName: "plus.circle").foregroundColor(nightVisionMode ? .red : .white)
}
Button { withAnimation(.easeInOut) { camera.recenter() } } label: {
    Image(systemName: "location.north.circle").foregroundColor(nightVisionMode ? .red : .white)
}
```

Remove this menu item:

```swift
Toggle("Snap North", isOn: $skySnapNorth)
```

- [ ] **Step 4: Add orientation status chip**

Add this view near the top-leading overlay inside the `ZStack`:

```swift
orientationStatus(heading: effectiveHeading, isExploring: camera.isExploring)
    .padding([.top, .leading], 12)
    .allowsHitTesting(false)
```

Add this helper to `ConstellationMapView`:

```swift
private func orientationStatus(heading: Double, isExploring: Bool) -> some View {
    let label = isExploring ? "Exploring" : "Live Heading"
    return Text("\(label) \(Int(heading.rounded()))°")
        .font(.caption2.weight(.semibold))
        .foregroundColor(nightVisionMode ? .red : .white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((nightVisionMode ? Color.black : Color.black.opacity(0.55)))
        .clipShape(Capsule())
}
```

- [ ] **Step 5: Build to verify SwiftUI wiring**

Run:

```bash
xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run focused tests again**

Run:

```bash
# See Task 1 Step 2 for destination selection guidance.
xcodebuild test \
  -project Triangulum.xcodeproj \
  -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:TriangulumTests/ConstellationCameraStateTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add Triangulum/Views/ConstellationMapView.swift
git commit -m "Pause constellation heading during exploration"
```

## Task 3: Final Verification

**Files:**
- Verify: `Triangulum/Models/ConstellationCameraState.swift`
- Verify: `Triangulum/Views/ConstellationMapView.swift`
- Verify: `TriangulumTests/ConstellationCameraStateTests.swift`

- [ ] **Step 1: Run focused tests**

```bash
# See Task 1 Step 2 for destination selection guidance.
xcodebuild test \
  -project Triangulum.xcodeproj \
  -scheme Triangulum \
  -destination 'platform=iOS Simulator,name=iPhone 15,OS=latest' \
  -only-testing:TriangulumTests/ConstellationCameraStateTests
```

Expected: PASS.

- [ ] **Step 2: Run Debug build**

```bash
xcodebuild -project Triangulum.xcodeproj -scheme Triangulum -configuration Debug
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Inspect final diff**

```bash
git status --short
git diff --stat HEAD
```

Expected: no unstaged production/test changes if all implementation commits were made.

## Self-Review

Spec coverage:

- Heading-follow default: Task 2 removes `Snap North` and always derives live heading from `locationManager.heading`.
- Temporary pause during pan/zoom: Task 1 adds `beginExploring`, `applyPan`, and `applyZoomMultiplier`; Task 2 wires gestures and controls through them.
- Recenter recovery: Task 1 tests `recenter`; Task 2 wires double tap and footer recenter to it.
- Status chip: Task 2 adds `orientationStatus`.
- Tests: Task 1 adds focused Swift Testing coverage; Task 3 verifies tests and build.

Placeholder scan: no TBD, TODO, "similar to", or unspecified implementation steps remain.

Type consistency: `ConstellationCameraState`, `camera`, `beginExploring`, `applyPan`, `applyZoomMultiplier`, `recenter`, and `effectiveHeading` are named consistently across tasks.
