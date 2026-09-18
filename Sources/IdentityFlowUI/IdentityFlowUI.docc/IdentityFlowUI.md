# ``IdentityFlowUI``

Capture, review, crop and front/back orchestration.

## Overview

``DocumentCaptureCoordinator`` drives one confirmed capture per side and conforms to
`ConfirmedImageCapture`, so it can be handed straight to `VaultEvidenceSource`. It exists because
the sequencing is subtle enough that integrators should not have to rebuild it: a single checked
continuation bridges the callback-based review screen into async code, and a generation identifier
rotates on every teardown so a callback from a dismissed screen cannot resolve a later side.

Two behaviours are load-bearing:

- The capture screen's own cancel invokes the host's cancellation handler and **does not** resolve
  the pending capture. The client cancels first and its cleanup resolves the capture, so the
  client's terminal reservation always wins the race.
- ``DocumentCaptureCoordinator/hidePreview()`` is synchronous. Inactivity and protected-data loss
  must clear preview pixels before the app yields, even though camera shutdown completes
  asynchronously.

Presentation is injected through ``DocumentCapturePresenter``. ``ChildCapturePresenter`` embeds each
side below a host privacy cover; a SwiftUI host can implement the protocol instead.

Camera permission is **not** handled here. Complete preflight with `CameraAuthorization` before
presenting anything; these components never request access implicitly.

## Topics

### Front and back orchestration

- ``DocumentCaptureCoordinator``
- ``DocumentCapturePresenter``
- ``ChildCapturePresenter``

### Single-side capture

- ``CameraReviewViewController``
- ``CameraReviewView``
