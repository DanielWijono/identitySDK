# ``IdentityFlowCapture``

Camera ownership, advisory framing guidance, and image normalization.

## Overview

``StillCamera`` owns its capture session, input and photo output inside one actor, so configuration
and start/stop never run on the main thread. Preview rendering uses `AVCaptureVideoPreviewLayer`
directly rather than copying frames, and a separate capped analysis path feeds Vision.

Guidance is **advisory everywhere**. ``CameraGuidance`` reports framing and focus state, the outline
turns green only when ready, and the manual shutter stays enabled in every state. Detection never
triggers the shutter, never defines the stored crop, and never asserts that a document is valid.

> Warning: ``CameraGuidance/sharpness`` is calibrated only against synthetic fixtures. Those
> saturate the metric, so the threshold may report ``CameraGuidance/Phase/tooBlurry`` for acceptable
> frames until it is measured on hardware. Treat it as a hint.

``ImageNormalizer`` is useful on its own. It applies EXIF orientation across all eight cases,
strips GPS and other metadata, bounds the longest edge without upscaling, flattens onto an opaque
background, and re-encodes to a size-capped JPEG. It never crops automatically or guesses at
document boundaries.

## Topics

### Capturing

- ``StillCamera``
- ``CameraDevice``
- ``CameraAuthorization``
- ``CameraEvent``
- ``CameraError``

### Guiding the user

- ``CameraGuidance``

### Preparing images

- ``ImageNormalizer``
- ``ImageNormalizationError``
