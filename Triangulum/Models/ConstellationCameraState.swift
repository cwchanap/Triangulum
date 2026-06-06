import CoreGraphics
import Foundation

struct ConstellationCameraState: Equatable {
    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 3.0

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
        zoom = Self.minZoom
        pan = .zero
        isExploring = false
        frozenHeading = nil
    }

    func effectiveHeading(liveHeading: Double) -> Double {
        frozenHeading ?? liveHeading
    }

    private func clampedZoom(_ value: CGFloat) -> CGFloat {
        max(Self.minZoom, min(Self.maxZoom, value))
    }
}
