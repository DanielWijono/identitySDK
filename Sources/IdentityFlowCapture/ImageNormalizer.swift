import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Why an image could not be normalized.
///
/// `outputTooLarge` is deliberate: there is no automatic quality-reduction loop, because silently
/// degrading an identity document until it fits would trade readability for convenience. Offer
/// recapture instead.
public enum ImageNormalizationError: Error, Sendable, Equatable {
    case invalidImage, unsupportedFormat, inputTooLarge, outputTooLarge, encodingFailed
}

/// Normalized image without source metadata. Contains sensitive plaintext; never log or persist it.
public struct NormalizedImage: Sendable {
    public let jpeg: Data
    public let width: Int
    public let height: Int
}

/// Serializes still-image normalization away from MainActor. Use shared for one operation at a time.
/// Supports explicit rectangular crops; does not judge readability or document authenticity.
public actor ImageNormalizer {
    public static let shared = ImageNormalizer()
    private let limits: Limits
    struct Limits: Sendable {
        var inputBytes = 30_000_000
        var inputPixels = 60_000_000
        var inputEdge = 12_000
        var outputEdge = 2_000
        var outputBytes = 3_000_000
    }
    public init() { limits = Limits() }
    init(limits: Limits) { self.limits = limits }

    /// Fixed JPEG quality of 0.85: exceeding the byte ceiling requests recapture, never a hidden
    /// sequence of quality reductions. Accepts one JPEG, PNG or HEIC image in memory.
    /// Optional crop uses unit coordinates from the upright image’s top-left corner, after
    /// orientation normalization and downsampling. Pixel bounds round outward; no upscaling.
    public func normalize(_ encoded: Data, crop: CGRect? = nil) throws -> NormalizedImage {
        try Task.checkCancellation()
        return try autoreleasepool {
            guard !encoded.isEmpty else { throw ImageNormalizationError.invalidImage }
            guard encoded.count <= limits.inputBytes else { throw ImageNormalizationError.inputTooLarge }
            guard let source = CGImageSourceCreateWithData(encoded as CFData,
                [kCGImageSourceShouldCache: false] as CFDictionary) else {
                throw ImageNormalizationError.invalidImage
            }
            guard let type = CGImageSourceGetType(source) else { throw ImageNormalizationError.invalidImage }
            guard [UTType.jpeg.identifier, UTType.png.identifier, UTType.heic.identifier].contains(type as String) else {
                throw ImageNormalizationError.unsupportedFormat
            }
            guard CGImageSourceGetCount(source) == 1, CGImageSourceGetStatus(source) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
                  let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
                throw ImageNormalizationError.invalidImage
            }
            let w = width.doubleValue, h = height.doubleValue
            guard w.isFinite, h.isFinite, w > 0, h > 0 else { throw ImageNormalizationError.invalidImage }
            guard w <= Double(limits.inputEdge), h <= Double(limits.inputEdge),
                  w * h <= Double(limits.inputPixels) else { throw ImageNormalizationError.inputTooLarge }
            if let orientation = properties[kCGImagePropertyOrientation] as? NSNumber {
                guard (1...8).contains(orientation.intValue) else { throw ImageNormalizationError.invalidImage }
            }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: min(limits.outputEdge, Int(max(w, h))),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
                  thumbnail.width > 0, thumbnail.height > 0,
                  max(thumbnail.width, thumbnail.height) <= limits.outputEdge else {
                throw ImageNormalizationError.invalidImage
            }
            try Task.checkCancellation()
            let selected: CGImage
            if let crop {
                guard crop.origin.x.isFinite, crop.origin.y.isFinite,
                      crop.width.isFinite, crop.height.isFinite,
                      crop.minX >= 0, crop.minY >= 0, crop.maxX <= 1, crop.maxY <= 1,
                      crop.width > 0, crop.height > 0 else { throw ImageNormalizationError.invalidImage }
                let region = CGRect(x: crop.minX * Double(thumbnail.width),
                                    y: crop.minY * Double(thumbnail.height),
                                    width: crop.width * Double(thumbnail.width),
                                    height: crop.height * Double(thumbnail.height)).integral
                guard let cropped = thumbnail.cropping(to: region) else { throw ImageNormalizationError.invalidImage }
                selected = cropped
            } else { selected = thumbnail }
            // Render only pixels into a fresh standard color space. No input EXIF/GPS/XMP,
            // embedded thumbnail, custom color profile, or auxiliary image is copied.
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: nil, width: selected.width, height: selected.height,
                                          bitsPerComponent: 8, bytesPerRow: selected.width * 4,
                                          space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                throw ImageNormalizationError.encodingFailed
            }
            let rect = CGRect(x: 0, y: 0, width: selected.width, height: selected.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(rect) // Flatten transparent inputs onto white.
            context.draw(selected, in: rect)
            guard let pixels = context.makeImage() else { throw ImageNormalizationError.encodingFailed }
            let output = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
                throw ImageNormalizationError.encodingFailed
            }
            CGImageDestinationAddImage(destination, pixels,
                [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else { throw ImageNormalizationError.encodingFailed }
            try Task.checkCancellation()
            guard output.length <= limits.outputBytes else { throw ImageNormalizationError.outputTooLarge }
            return NormalizedImage(jpeg: output as Data, width: pixels.width, height: pixels.height)
        }
    }
}
