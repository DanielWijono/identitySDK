# Still-image normalization

`IdentityFlowCapture` currently provides `ImageNormalizer`; it does not provide a camera. Both iOS samples normalize their generated synthetic JPEGs before passing them to the encrypted evidence source.

```swift
let image = try await ImageNormalizer.shared.normalize(encodedImageData)
// image.jpeg is sensitive plaintext. Return it to the vault adapter; do not write or log it.
```

The shared actor serializes normalization away from MainActor. The integrated flow requests images sequentially. Cancellation is checked before work and between decode/encode stages; Image I/O calls already executing are not preempted. Autoreleased intermediate objects are scoped to each operation. This is not a memory-wiping guarantee or a measured device memory budget.

The input must contain one JPEG, PNG or HEIC image. Encoded input is capped at 30 MB, source dimensions at 12,000 pixels per edge and total source area at 60 megapixels before raster decoding. Empty/unrecognized/truncated data is rejected; unsupported formats and excessive input have separate typed errors. Multi-image sources are rejected rather than choosing an arbitrary frame.

Image I/O downsamples from the source image (not an embedded thumbnail), applying EXIF rotation and mirroring. The longest output edge is at most 2,000 pixels; smaller images are not upscaled. The entire image is preserved: there is no automatic crop or document-boundary guess.

Pixels are drawn into a new sRGB bitmap, flattening alpha onto white, then written to a new JPEG at quality 0.85. No input metadata is copied: GPS, source EXIF/TIFF fields, source color profiles, thumbnails and auxiliary data do not transfer. The encoder can emit its own structural/color metadata. JPEG output is capped at 3,000,000 bytes. An oversized result throws `outputTooLarge`; there is no automatic loop lowering quality until text becomes unreadable. Future capture UI must offer recapture for this error.

Tests generate colored synthetic fixtures in memory. Coverage includes all eight EXIF orientation cases with pixel-position assertions, GPS/date/comment/artist removal, JPEG/PNG/HEIC input, dimension reduction without upscaling, invalid input, input/output limits and cancellation. These tests establish transformations, not document readability, camera quality or physical-device performance.

Remaining capture work: permission/lifecycle-safe camera ownership, manual shutter, document framing guidance, user crop/review/retake, image-quality guidance and accessibility/device measurements. Physical-iPhone storage lock/unlock validation remains outstanding before connecting real captures.

Apple references: [transformed thumbnails](https://developer.apple.com/documentation/imageio/kcgimagesourcecreatethumbnailwithtransform), [thumbnail creation](https://developer.apple.com/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)), [JPEG quality](https://developer.apple.com/documentation/imageio/kcgimagedestinationlossycompressionquality).
