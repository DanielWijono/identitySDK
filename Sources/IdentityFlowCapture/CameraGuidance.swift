import CoreGraphics

/// Advisory framing state produced from local rectangle observations.
/// It never blocks the manual shutter or claims that a document is valid.
public struct CameraGuidance: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case searching
        case moveCloser
        case keepInside
        case holdSteady
        /// Framing is acceptable but the frame looks defocused. Advisory only.
        case tooBlurry
        case ready
    }

    /// Upright, top-left-origin unit coordinates matching camera preview metadata coordinates.
    public let bounds: CGRect?
    public let phase: Phase
    /// Relative focus estimate in 0...1 for the detected region, or nil when not measured.
    /// Provisional and uncalibrated against physical capture; treat it as a hint, not a verdict.
    public let sharpness: Double?

    public init(bounds: CGRect?, phase: Phase, sharpness: Double? = nil) {
        self.bounds = bounds
        self.phase = phase
        self.sharpness = sharpness
    }
}

struct RectangleGuidanceTracker: Sendable {
    /// Provisional. Chosen so an obviously defocused frame scores below it on synthetic fixtures;
    /// it has not been calibrated against physical capture on a printed card.
    static let minimumSharpness = 0.35

    private(set) var previous: CGRect?
    private(set) var stableFrames = 0

    mutating func update(_ candidate: CGRect?, sharpness: Double? = nil) -> CameraGuidance {
        guard let candidate else {
            previous = nil
            stableFrames = 0
            return CameraGuidance(bounds: nil, phase: .searching, sharpness: sharpness)
        }
        let bounds = candidate.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            previous = nil
            stableFrames = 0
            return CameraGuidance(bounds: nil, phase: .searching, sharpness: sharpness)
        }

        defer { previous = bounds }
        guard bounds.width * bounds.height >= 0.18 else {
            stableFrames = 0
            return CameraGuidance(bounds: bounds, phase: .moveCloser, sharpness: sharpness)
        }
        let margin = 0.025
        guard bounds.minX >= margin, bounds.minY >= margin,
              bounds.maxX <= 1 - margin, bounds.maxY <= 1 - margin else {
            stableFrames = 0
            return CameraGuidance(bounds: bounds, phase: .keepInside, sharpness: sharpness)
        }

        if let previous, intersectionOverUnion(previous, bounds) >= 0.82 {
            stableFrames += 1
        } else {
            stableFrames = 1
        }
        // Framing is good, so focus is the remaining reason not to call the frame ready. Stability
        // still accumulates, so readiness appears immediately once focus lands.
        if let sharpness, sharpness < Self.minimumSharpness {
            return CameraGuidance(bounds: bounds, phase: .tooBlurry, sharpness: sharpness)
        }
        return CameraGuidance(bounds: bounds, phase: stableFrames >= 3 ? .ready : .holdSteady,
                              sharpness: sharpness)
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}
