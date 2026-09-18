import CoreGraphics
import Testing
@testable import IdentityFlowCapture

/// Deterministic synthetic luma planes. No camera or real document is involved.
private enum Fixture {
    static let width = 120
    static let height = 90

    /// Alternating blocks give strong high-frequency content, standing in for a sharp frame.
    static func checkerboard(block: Int = 6) -> [UInt8] {
        (0..<(width * height)).map { index in
            let x = index % width, y = index / width
            return ((x / block) + (y / block)) % 2 == 0 ? 0 : 255
        }
    }

    static func flat(_ value: UInt8 = 128) -> [UInt8] {
        Array(repeating: value, count: width * height)
    }

    /// Box blur, which is what defocus does to high-frequency detail.
    static func blurred(_ source: [UInt8], radius: Int) -> [UInt8] {
        var output = source
        for y in 0..<height {
            for x in 0..<width {
                var total = 0, count = 0
                for dy in -radius...radius {
                    for dx in -radius...radius {
                        let sx = x + dx, sy = y + dy
                        guard sx >= 0, sx < width, sy >= 0, sy < height else { continue }
                        total += Int(source[sy * width + sx])
                        count += 1
                    }
                }
                output[y * width + x] = UInt8(total / max(1, count))
            }
        }
        return output
    }

    static func score(_ luma: [UInt8], region: CGRect? = nil) -> Double {
        luma.withUnsafeBufferPointer { buffer in
            SharpnessScore.score(luma: buffer.baseAddress!, width: width, height: height,
                                 rowBytes: width, region: region)
        }
    }
}

@Test func sharpnessSeparatesFocusedFromDefocusedFrames() {
    let sharp = Fixture.score(Fixture.checkerboard())
    let blurred = Fixture.score(Fixture.blurred(Fixture.checkerboard(), radius: 4))
    #expect(sharp > blurred)
    #expect(sharp >= RectangleGuidanceTracker.minimumSharpness)
    #expect(blurred < RectangleGuidanceTracker.minimumSharpness,
            "A heavily defocused frame must fall below the advisory threshold")
}

@Test func sharpnessIsZeroForFlatOrUnmeasurableInput() {
    #expect(Fixture.score(Fixture.flat()) == 0)
    // Degenerate geometry must not trap or divide by zero.
    #expect(Fixture.score(Fixture.checkerboard(), region: .null) == 0)
    #expect(Fixture.score(Fixture.checkerboard(), region: CGRect(x: 0.5, y: 0.5, width: 0, height: 0)) == 0)
}

@Test func sharpnessScoresOnlyTheRequestedRegion() {
    // Sharp detail on the left half, flat on the right. Scoring the correct half must differ.
    var split = Fixture.flat()
    let checker = Fixture.checkerboard()
    for y in 0..<Fixture.height {
        for x in 0..<(Fixture.width / 2) {
            split[y * Fixture.width + x] = checker[y * Fixture.width + x]
        }
    }
    let left = Fixture.score(split, region: CGRect(x: 0.05, y: 0.1, width: 0.35, height: 0.8))
    let right = Fixture.score(split, region: CGRect(x: 0.6, y: 0.1, width: 0.35, height: 0.8))
    #expect(left > right)
    #expect(right == 0, "A flat region must not inherit sharpness from elsewhere in the frame")
}

@Test func guidanceReportsBlurOnlyWhenFramingIsOtherwiseAcceptable() {
    var tracker = RectangleGuidanceTracker()
    let framed = CGRect(x: 0.12, y: 0.2, width: 0.76, height: 0.48)
    let blurry = RectangleGuidanceTracker.minimumSharpness - 0.1

    #expect(tracker.update(framed, sharpness: blurry).phase == .tooBlurry)
    // Framing problems still take precedence: telling someone to hold still is useless when the
    // card is not even in frame.
    #expect(tracker.update(CGRect(x: 0.3, y: 0.3, width: 0.3, height: 0.3),
                           sharpness: blurry).phase == .moveCloser)
    #expect(tracker.update(nil, sharpness: blurry).phase == .searching)
}

@Test func focusRecoveryReachesReadyWithoutRestartingStability() {
    var tracker = RectangleGuidanceTracker()
    let framed = CGRect(x: 0.12, y: 0.2, width: 0.76, height: 0.48)
    let blurry = RectangleGuidanceTracker.minimumSharpness - 0.1
    let sharp = 0.9

    // Steady but out of focus for three frames.
    #expect(tracker.update(framed, sharpness: blurry).phase == .tooBlurry)
    #expect(tracker.update(framed, sharpness: blurry).phase == .tooBlurry)
    #expect(tracker.update(framed, sharpness: blurry).phase == .tooBlurry)
    // Focus lands: readiness is immediate because stability kept accumulating.
    #expect(tracker.update(framed, sharpness: sharp).phase == .ready)
}

@Test func guidanceWithoutASharpnessMeasurementBehavesAsBefore() {
    var tracker = RectangleGuidanceTracker()
    let framed = CGRect(x: 0.12, y: 0.2, width: 0.76, height: 0.48)
    #expect(tracker.update(framed).phase == .holdSteady)
    #expect(tracker.update(framed).phase == .holdSteady)
    #expect(tracker.update(framed).phase == .ready)
    #expect(tracker.update(framed).sharpness == nil)
}
