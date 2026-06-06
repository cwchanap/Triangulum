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

        state.applyZoomMultiplier(0.01, currentHeading: 180.0)

        #expect(state.frozenHeading == 91.0)
        #expect(state.zoom == ConstellationCameraState.minZoom)
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
    }

    @Test func zoomBoundsAreConsistentWithInitialZoom() {
        #expect(ConstellationCameraState.minZoom >= 0.0)
        #expect(ConstellationCameraState.maxZoom >= ConstellationCameraState.minZoom)
        #expect(ConstellationCameraState().zoom == ConstellationCameraState.minZoom)
    }
}
