import CoreGraphics
import Foundation

struct ConstellationCameraState: Equatable {
    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 3.0

    /// Pans whose total displacement is below this are treated as no-ops: they
    /// neither accumulate nor freeze the live heading. Filters incidental/jitter
    /// touches so a stray 1pt drag can't strand the user in "exploring" mode.
    static let panMoveThreshold: CGFloat = 1.0

    /// Pinch scale deviations from 1.0 below this are treated as jitter and do
    /// not freeze the live heading. Keeps a stray micro-pinch from stranding the
    /// user in "exploring" mode before the gesture commits.
    static let pinchMoveThreshold: CGFloat = 0.05

    private(set) var zoom: CGFloat = 1.0
    private(set) var pan: CGSize = .zero
    private(set) var frozenHeading: Double?

    /// True once a meaningful gesture has frozen the live heading.
    /// Derived from `frozenHeading` so the two can never drift apart.
    var isExploring: Bool { frozenHeading != nil }

    mutating func beginExploring(currentHeading: Double) {
        guard frozenHeading == nil else { return }
        frozenHeading = currentHeading
    }

    /// Called from the live gesture-change path to freeze the heading the moment
    /// an in-flight drag becomes meaningful — before it commits — so the sky
    /// stops following the compass mid-gesture. Sub-threshold jitter is ignored.
    mutating func beginExploringIfNeeded(translation: CGSize, currentHeading: Double) {
        guard max(abs(translation.width), abs(translation.height)) >= Self.panMoveThreshold else { return }
        beginExploring(currentHeading: currentHeading)
    }

    /// Called from the live gesture-change path to freeze the heading the moment
    /// an in-flight pinch becomes meaningful — before it commits — so the sky
    /// stops following the compass mid-gesture. Sub-threshold jitter is ignored.
    mutating func beginExploringIfNeeded(livePinch: CGFloat, currentHeading: Double) {
        guard abs(livePinch - 1.0) >= Self.pinchMoveThreshold else { return }
        beginExploring(currentHeading: currentHeading)
    }

    mutating func applyZoomMultiplier(_ multiplier: CGFloat, currentHeading: Double) {
        let targetZoom = clampedZoom(zoom * multiplier)
        guard targetZoom != zoom else { return }
        beginExploring(currentHeading: currentHeading)
        zoom = targetZoom
    }

    mutating func applyPan(_ translation: CGSize, currentHeading: Double) {
        // Ignore sub-threshold drags entirely: no pan, no freeze.
        guard max(abs(translation.width), abs(translation.height)) >= Self.panMoveThreshold else { return }
        beginExploring(currentHeading: currentHeading)
        pan.width += translation.width
        pan.height += translation.height
    }

    mutating func recenter() {
        zoom = Self.minZoom
        pan = .zero
        frozenHeading = nil
    }

    func effectiveHeading(liveHeading: Double) -> Double {
        frozenHeading ?? liveHeading
    }

    /// Zoom to render given a live (in-flight) pinch scale, clamped to bounds.
    /// Centralises the clamp so the view and the commit path share one rule.
    func renderedZoom(livePinch: CGFloat) -> CGFloat {
        clampedZoom(zoom * livePinch)
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        max(Self.minZoom, min(Self.maxZoom, value))
    }
}
