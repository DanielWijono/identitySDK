import CoreGraphics

/// Local focus estimate from the variance of the discrete Laplacian of the luma plane.
///
/// Blur removes high-frequency detail, so a defocused frame has a much flatter Laplacian than a
/// sharp one. This is a relative indicator of focus on *this* camera and scene, not an absolute
/// readability measure: it cannot tell a sharp photograph of an unreadable card from a blurry
/// photograph of a clear one, and it is deliberately never allowed to block the shutter.
enum SharpnessScore {
    /// Laplacian variance mapped to roughly 0...1. The reference is provisional and uncalibrated
    /// against physical capture; see Docs/Camera-Capture.md.
    static let referenceVariance = 400.0

    /// Sample every other pixel. At preview resolution this keeps the estimate stable while
    /// quartering the work, which matters because this runs on the shared analysis queue.
    private static let stride = 2

    /// - Parameters:
    ///   - luma: 8-bit luma plane.
    ///   - region: upright unit rectangle to score, normally the detected card. Scoring the whole
    ///     frame would let a busy background mask a defocused document.
    /// - Returns: 0 for a flat or unmeasurable region, approaching 1 for a sharp one.
    static func score(luma: UnsafePointer<UInt8>, width: Int, height: Int, rowBytes: Int,
                      region: CGRect? = nil) -> Double {
        guard width > 2, height > 2, rowBytes >= width else { return 0 }

        var minX = 1, minY = 1, maxX = width - 2, maxY = height - 2
        if let region {
            let clamped = region.standardized.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            guard !clamped.isNull else { return 0 }
            minX = max(1, Int(clamped.minX * Double(width)))
            minY = max(1, Int(clamped.minY * Double(height)))
            maxX = min(width - 2, Int(clamped.maxX * Double(width)))
            maxY = min(height - 2, Int(clamped.maxY * Double(height)))
        }
        guard maxX > minX, maxY > minY else { return 0 }

        var sum = 0.0
        var sumOfSquares = 0.0
        var count = 0
        var y = minY
        while y <= maxY {
            var x = minX
            let row = luma + y * rowBytes
            let above = luma + (y - 1) * rowBytes
            let below = luma + (y + 1) * rowBytes
            while x <= maxX {
                // Four-neighbour Laplacian kernel.
                let value = -4.0 * Double(row[x])
                    + Double(row[x - 1]) + Double(row[x + 1])
                    + Double(above[x]) + Double(below[x])
                sum += value
                sumOfSquares += value * value
                count += 1
                x += stride
            }
            y += stride
        }
        guard count > 1 else { return 0 }

        let mean = sum / Double(count)
        let variance = max(0, sumOfSquares / Double(count) - mean * mean)
        return min(1.0, variance / referenceVariance)
    }
}
