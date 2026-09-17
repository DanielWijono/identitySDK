import CoreGraphics

/// Advisory framing state produced from local rectangle observations.
/// It never blocks the manual shutter or claims that a document is valid.
public struct CameraGuidance: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case searching
        case moveCloser
        case keepInside
        case holdSteady
        case ready
    }

    /// Upright, top-left-origin unit coordinates matching camera preview metadata coordinates.
    public let bounds: CGRect?
    public let phase: Phase

    public init(bounds: CGRect?, phase: Phase) {
        self.bounds = bounds
        self.phase = phase
    }
}

struct RectangleGuidanceTracker: Sendable {
    private(set) var previous: CGRect?
    private(set) var stableFrames = 0

    mutating func update(_ candidate: CGRect?) -> CameraGuidance {
        guard let candidate else {
            previous = nil
            stableFrames = 0
            return CameraGuidance(bounds: nil, phase: .searching)
        }
        let bounds = candidate.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !bounds.isNull, bounds.width > 0, bounds.height > 0 else {
            previous = nil
            stableFrames = 0
            return CameraGuidance(bounds: nil, phase: .searching)
        }

        defer { previous = bounds }
        guard bounds.width * bounds.height >= 0.18 else {
            stableFrames = 0
            return CameraGuidance(bounds: bounds, phase: .moveCloser)
        }
        let margin = 0.025
        guard bounds.minX >= margin, bounds.minY >= margin,
              bounds.maxX <= 1 - margin, bounds.maxY <= 1 - margin else {
            stableFrames = 0
            return CameraGuidance(bounds: bounds, phase: .keepInside)
        }

        if let previous, intersectionOverUnion(previous, bounds) >= 0.82 {
            stableFrames += 1
        } else {
            stableFrames = 1
        }
        return CameraGuidance(bounds: bounds, phase: stableFrames >= 3 ? .ready : .holdSteady)
    }

    private func intersectionOverUnion(_ lhs: CGRect, _ rhs: CGRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = lhs.width * lhs.height + rhs.width * rhs.height - intersectionArea
        return unionArea > 0 ? intersectionArea / unionArea : 0
    }
}
