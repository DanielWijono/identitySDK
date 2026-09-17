import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import Testing
@testable import IdentityFlowCapture

private func fixture(width: Int = 160, height: Int = 100, orientation: Int = 1,
                     format: UTType = .jpeg, metadata: Bool = false) throws -> Data {
    let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    let colors: [CGColor] = [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                             CGColor(red: 0, green: 1, blue: 0, alpha: 1),
                             CGColor(red: 0, green: 0, blue: 1, alpha: 1),
                             CGColor(red: 1, green: 1, blue: 0, alpha: 1)]
    for i in 0..<4 {
        context.setFillColor(colors[i])
        // CGContext uses a bottom-left drawing origin; fixture labels use top-left ordering.
        context.fill(CGRect(x: (i % 2) * width / 2, y: (1 - i / 2) * height / 2, width: width / 2, height: height / 2))
    }
    let image = try #require(context.makeImage())
    let bytes = NSMutableData()
    let destination = try #require(CGImageDestinationCreateWithData(bytes, format.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
    if metadata {
        properties[kCGImagePropertyGPSDictionary] = [kCGImagePropertyGPSLatitude: 1.234,
            kCGImagePropertyGPSLatitudeRef: "N", kCGImagePropertyGPSLongitude: 5.678,
            kCGImagePropertyGPSLongitudeRef: "E"] as [CFString: Any]
        properties[kCGImagePropertyExifDictionary] = [kCGImagePropertyExifUserComment: "SYNTHETIC-PRIVATE-MARKER",
            kCGImagePropertyExifDateTimeOriginal: "2000:01:01 00:00:00"] as [CFString: Any]
        properties[kCGImagePropertyTIFFDictionary] = [kCGImagePropertyTIFFArtist: "SYNTHETIC-ARTIST"]
    }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return bytes as Data
}

private func properties(_ data: Data) throws -> [CFString: Any] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
}

private func quadrants(_ data: Data) throws -> [Int] {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
        bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
    return (0..<4).map { quadrant in
        let x = image.width * (quadrant % 2 == 0 ? 1 : 3) / 4
        let y = image.height * (quadrant / 2 == 0 ? 1 : 3) / 4
        let offset = (y * image.width + x) * 4
        let r = pixels[offset] > 128, g = pixels[offset + 1] > 128, b = pixels[offset + 2] > 128
        if r && g { return 3 }
        if r { return 0 }
        if g { return 1 }
        if b { return 2 }
        return -1
    }
}

@Test(arguments: 1...8)
func appliesAllEXIFOrientations(orientation: Int) async throws {
    let input = try fixture(orientation: orientation)
    #expect(try quadrants(input) == [0, 1, 2, 3]) // Independent raw-pixel fixture sanity check.
    let result = try await ImageNormalizer().normalize(input)
    #expect(result.width == (orientation >= 5 ? 100 : 160))
    #expect(result.height == (orientation >= 5 ? 160 : 100))
    let expected = [[0, 1, 2, 3], [1, 0, 3, 2], [3, 2, 1, 0], [2, 3, 0, 1],
                    [0, 2, 1, 3], [2, 0, 3, 1], [3, 1, 2, 0], [1, 3, 0, 2]]
    let actual = try quadrants(result.jpeg)
    #expect(actual == expected[orientation - 1])
    let outputProperties = try properties(result.jpeg)
    #expect((outputProperties[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
}

@Test func stripsSensitiveMetadataInsteadOfCopyingSource() async throws {
    let input = try fixture(metadata: true)
    #expect(try properties(input)[kCGImagePropertyGPSDictionary] != nil)
    let output = try await ImageNormalizer().normalize(input)
    let result = try properties(output.jpeg)
    #expect(result[kCGImagePropertyGPSDictionary] == nil)
    let exif = result[kCGImagePropertyExifDictionary] as? [CFString: Any]
    let tiff = result[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    #expect(exif?[kCGImagePropertyExifUserComment] == nil)
    #expect(exif?[kCGImagePropertyExifDateTimeOriginal] == nil)
    #expect(tiff?[kCGImagePropertyTIFFArtist] == nil)
    #expect(output.jpeg.range(of: Data("SYNTHETIC-PRIVATE-MARKER".utf8)) == nil)
}

@Test func boundsDimensionsWithoutUpscaling() async throws {
    let normalizer = ImageNormalizer()
    let large = try await normalizer.normalize(fixture(width: 3000, height: 1500))
    #expect(large.width == 2000 && large.height == 1000)
    #expect(large.jpeg.count <= 3_000_000)
    let small = try await normalizer.normalize(fixture(width: 80, height: 40))
    #expect(small.width == 80 && small.height == 40)
}

@Test func rejectsInvalidAndUnsupportedInputs() async throws {
    let normalizer = ImageNormalizer()
    await #expect(throws: ImageNormalizationError.invalidImage) { try await normalizer.normalize(Data()) }
    await #expect(throws: ImageNormalizationError.invalidImage) { try await normalizer.normalize(Data("not an image".utf8)) }
    let gif = try fixture(format: .gif)
    await #expect(throws: ImageNormalizationError.unsupportedFormat) { try await normalizer.normalize(gif) }
    let truncated = try fixture().prefix(40)
    await #expect(throws: ImageNormalizationError.invalidImage) { try await normalizer.normalize(Data(truncated)) }
}

@Test func rejectsOversizeInputsAndOutputs() async throws {
    let input = try fixture()
    var limits = ImageNormalizer.Limits()
    limits.inputBytes = input.count - 1
    let byteLimited = ImageNormalizer(limits: limits)
    await #expect(throws: ImageNormalizationError.inputTooLarge) { try await byteLimited.normalize(input) }
    limits = .init()
    limits.inputPixels = 100
    let pixelLimited = ImageNormalizer(limits: limits)
    await #expect(throws: ImageNormalizationError.inputTooLarge) { try await pixelLimited.normalize(input) }
    limits = .init()
    limits.outputBytes = 100
    let outputLimited = ImageNormalizer(limits: limits)
    await #expect(throws: ImageNormalizationError.outputTooLarge) { try await outputLimited.normalize(input) }
}

@Test(arguments: [UTType.png, UTType.heic])
func convertsSupportedFormatsAndChecksCancellation(format: UTType) async throws {
    let input = try fixture(format: format)
    let result = try await ImageNormalizer().normalize(input)
    let source = try #require(CGImageSourceCreateWithData(result.jpeg as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await ImageNormalizer().normalize(input)
    }
    await #expect(throws: CancellationError.self) { try await task.value }
}

@Test(arguments: 1...8)
func cropUsesUprightTopLeftCoordinates(orientation: Int) async throws {
    let input = try fixture(orientation: orientation, metadata: true)
    let result = try await ImageNormalizer().normalize(input, crop: CGRect(x: 0, y: 0, width: 0.5, height: 0.5))
    #expect(result.width == (orientation >= 5 ? 50 : 80))
    #expect(result.height == (orientation >= 5 ? 80 : 50))
    let expected = [0, 1, 3, 2, 0, 2, 3, 1][orientation - 1]
    #expect(try quadrants(result.jpeg) == Array(repeating: expected, count: 4))
    #expect(try properties(result.jpeg)[kCGImagePropertyGPSDictionary] == nil)
}

@Test func rejectsInvalidCropBounds() async throws {
    let input = try fixture()
    for rect in [CGRect(x: -0.1, y: 0, width: 0.5, height: 0.5),
                 CGRect(x: 0.8, y: 0, width: 0.5, height: 0.5),
                 CGRect(x: 0, y: 0, width: 0, height: 1),
                 CGRect(x: 0, y: 0, width: CGFloat.nan, height: 1)] {
        await #expect(throws: ImageNormalizationError.invalidImage) {
            try await ImageNormalizer().normalize(input, crop: rect)
        }
    }
}
