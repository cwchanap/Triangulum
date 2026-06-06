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
        #expect(state.zoom == ConstellationCameraState.minZoom)
        #expect(state.pan == .zero)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 128.0)
    }

    @Test func zoomStaysWithinBoundsAndStartsExploration() {
        var state = ConstellationCameraState()

        state.applyZoomMultiplier(10.0, currentHeading: 91.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 91.0)
        #expect(state.zoom == ConstellationCameraState.maxZoom)
        // Rendered heading must ignore the live compass once exploring.
        #expect(state.effectiveHeading(liveHeading: 200.0) == 91.0)

        state.applyZoomMultiplier(0.01, currentHeading: 180.0)

        #expect(state.frozenHeading == 91.0)
        #expect(state.zoom == ConstellationCameraState.minZoom)
        #expect(state.effectiveHeading(liveHeading: 180.0) == 91.0)
    }

    @Test func noOpZoomAtBoundDoesNotStartExploration() {
        var state = ConstellationCameraState()

        // Zoom-out at minZoom clamps back to minZoom: must not freeze heading.
        state.applyZoomMultiplier(1.0 / 1.15, currentHeading: 42.0)

        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)
        #expect(state.zoom == ConstellationCameraState.minZoom)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 128.0)

        // Same guard applies at the upper bound.
        state.applyZoomMultiplier(10.0, currentHeading: 7.0)
        #expect(state.zoom == ConstellationCameraState.maxZoom)
        #expect(state.frozenHeading == 7.0)

        state.applyZoomMultiplier(1.15, currentHeading: 99.0)

        #expect(state.zoom == ConstellationCameraState.maxZoom)
        #expect(state.frozenHeading == 7.0)
    }

    @Test func panAccumulatesAndStartsExploration() {
        var state = ConstellationCameraState()

        state.applyPan(CGSize(width: 10.0, height: 4.0), currentHeading: 270.0)
        state.applyPan(CGSize(width: -2.0, height: 8.0), currentHeading: 12.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 270.0)
        #expect(state.pan == CGSize(width: 8.0, height: 12.0))
        // Live heading must be ignored once a real pan froze it.
        #expect(state.effectiveHeading(liveHeading: 12.0) == 270.0)
    }

    // MARK: - Regression: incidental gestures must not strand the user in "exploring"

    @Test func subThresholdPanDoesNotFreezeHeading() {
        var state = ConstellationCameraState()

        // A sub-threshold drag (stray 0.5pt touch) is a no-op: no pan, no freeze.
        state.applyPan(CGSize(width: 0.5, height: 0.0), currentHeading: 42.0)

        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)
        #expect(state.pan == .zero)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 128.0)

        // Exactly at threshold still counts as intentional movement.
        let t = ConstellationCameraState.panMoveThreshold
        state.applyPan(CGSize(width: t, height: 0.0), currentHeading: 60.0)
        #expect(state.isExploring)
        #expect(state.frozenHeading == 60.0)
    }

    @Test func noOpPinchDoesNotFreezeHeading() {
        var state = ConstellationCameraState()

        // A pinch that resolves to a 1.0 multiplier (no net zoom) must not freeze.
        state.applyZoomMultiplier(1.0, currentHeading: 42.0)

        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)
        #expect(state.zoom == ConstellationCameraState.minZoom)
        #expect(state.effectiveHeading(liveHeading: 128.0) == 128.0)
    }

    // MARK: - Live gesture freeze (exploration begins mid-gesture, before commit)

    @Test func livePinchFreezesHeadingWhenMeaningful() {
        var state = ConstellationCameraState()

        // Sub-threshold pinch (jitter) must not freeze.
        state.beginExploringIfNeeded(livePinch: 1.0 + ConstellationCameraState.pinchMoveThreshold / 2.0, currentHeading: 42.0)
        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)

        // Crossing the threshold freezes at the heading active when it became meaningful.
        state.beginExploringIfNeeded(livePinch: 1.0 + ConstellationCameraState.pinchMoveThreshold, currentHeading: 91.0)
        #expect(state.isExploring)
        #expect(state.frozenHeading == 91.0)

        // Subsequent live changes keep the first frozen heading (idempotent).
        state.beginExploringIfNeeded(livePinch: 2.5, currentHeading: 200.0)
        #expect(state.frozenHeading == 91.0)
    }

    @Test func livePinchInwardAlsoFreezes() {
        var state = ConstellationCameraState()

        // Pinching in (livePinch < 1.0) is equally meaningful.
        state.beginExploringIfNeeded(livePinch: 1.0 - ConstellationCameraState.pinchMoveThreshold, currentHeading: 55.0)

        #expect(state.isExploring)
        #expect(state.frozenHeading == 55.0)
    }

    @Test func livePinchResetToOneDoesNotFreeze() {
        var state = ConstellationCameraState()

        // A gesture resolving back to 1.0 before any meaningful move must not freeze.
        // This mirrors the @GestureState reset when the gesture ends at neutral.
        state.beginExploringIfNeeded(livePinch: 1.0, currentHeading: 42.0)

        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)
    }

    @Test func livePanFreezesHeadingWhenMeaningful() {
        var state = ConstellationCameraState()

        // Sub-threshold drag must not freeze.
        state.beginExploringIfNeeded(translation: CGSize(width: ConstellationCameraState.panMoveThreshold / 2.0, height: 0), currentHeading: 42.0)
        #expect(!state.isExploring)
        #expect(state.frozenHeading == nil)

        // At/above threshold freezes.
        state.beginExploringIfNeeded(translation: CGSize(width: ConstellationCameraState.panMoveThreshold, height: 0), currentHeading: 270.0)
        #expect(state.isExploring)
        #expect(state.frozenHeading == 270.0)

        // Idempotent: first frozen heading wins.
        state.beginExploringIfNeeded(translation: CGSize(width: 50, height: 50), currentHeading: 12.0)
        #expect(state.frozenHeading == 270.0)
    }

    @Test func liveFreezePersistsAcrossGestureCommit() {
        var state = ConstellationCameraState()

        // Live freeze fires first during the gesture...
        state.beginExploringIfNeeded(translation: CGSize(width: 30, height: 0), currentHeading: 180.0)
        #expect(state.frozenHeading == 180.0)

        // ...then the gesture commits; the heading must not change.
        state.applyPan(CGSize(width: 30, height: 0), currentHeading: 5.0)
        #expect(state.frozenHeading == 180.0)
        #expect(state.effectiveHeading(liveHeading: 5.0) == 180.0)
    }

    // MARK: - Bounds & rendering

    @Test func zoomBoundsAreConsistentWithInitialZoom() {
        // Bounds must give a usable range — equal bounds would permanently freeze zoom.
        #expect(ConstellationCameraState.minZoom >= 0.0)
        #expect(ConstellationCameraState.maxZoom > ConstellationCameraState.minZoom)
        #expect(ConstellationCameraState().zoom == ConstellationCameraState.minZoom)
    }

    @Test func renderedZoomClampsLivePinchToBounds() {
        var state = ConstellationCameraState()

        // Committed zoom sits at min; a wild live pinch value still renders in-bounds.
        #expect(state.renderedZoom(livePinch: 0.1) == ConstellationCameraState.minZoom)

        state.applyZoomMultiplier(2.0, currentHeading: 10.0)
        // 2.0 * 99 clamps to maxZoom, not beyond.
        #expect(state.renderedZoom(livePinch: 99.0) == ConstellationCameraState.maxZoom)
        // Normal in-flight pinch renders the product.
        #expect(state.renderedZoom(livePinch: 1.5) == 3.0)
    }
}
