# iPhone simulation samples

Open `IdentityFlowSamples.xcodeproj` in Xcode. Choose **UIKitSample** or **SwiftUISample**, select an iPhone simulator, and press **Run** (⌘R). The project references the SDK package two directories above; keep this folder inside the repository. No account, backend or camera permission is needed for Simulator. Keep Xcode’s normal signing enabled: the Keychain needs the simulated app identity. Do not build this integration with `CODE_SIGNING_ALLOWED=NO`; the unsigned build failed storage initialization in validation.

Select an outcome, accept the sample disclosure and tap **Start simulation**. Review the synthetic front and back cards and tap **Use this image** for each. **Retake** replaces the current preview and increments its take number. Only confirmed images enter encrypted storage; neither side uploads until both are confirmed. Provider simulation takes approximately four seconds in addition to review time. The session expires after 60 seconds, including review time. Try **Cancel simulation** while it runs. Inactivity immediately closes the vault gate, conceals the screen and cancels the sample's task; this is a demo policy, not the production reconciliation feature. Synthetic JPEGs are normalized and encrypted locally and cleared before a normal result is displayed. If deletion fails, the app shows Retry cleanup and blocks another run until recovery succeeds.

Both sample hosts use the same UIKit orchestration screen; the SwiftUI sample wraps that whole demo screen with `UIViewControllerRepresentable`. The SDK now also provides `CameraReviewView` as a single-side SwiftUI wrapper over its shared UIKit camera/review controller. Every provider outcome remains simulated, including pending: no remote verification continues after the demo closes.

The generated Xcode project is committed, so XcodeGen is not required to run. After editing `project.yml`, regenerate from the repository root with:

```sh
xcodegen generate --spec Examples/iOS/project.yml
```

Choose UIKitSample and press ⌘U for the UI tests. They exercise consent gating, the four outcomes, front/back review, retake, cancellation during review, and background/foreground followed by another run. The apps target iOS 16 and Swift 6. A physical device requires your own signing team. Live camera capture is available as both the standalone hardware test and integrated front/back simulation described below; Simulator defaults to generated cards. The scheme also runs injected-camera component tests without requesting camera access.

## Live camera hardware test

Choose UIKitSample and a physical iPhone in Xcode. Select your development team under Signing & Capabilities, then Run. Tap **Test live camera** (scroll down if needed), allow camera access, and photograph a printed test card. Tap **Take photo**, **Retake**, then **Use this image**. Confirmation returns to the sample and discards the image. Nothing is saved or uploaded. Cancellation or leaving the app also ends capture. This separate test does not validate encrypted storage or connect the camera to verification.

If Camera access is denied or later revoked, the sample shows **Open Camera Settings**. Enable Camera, return to the app, and wait for the enabled message; capture starts only after you explicitly tap the camera action again.

### Integrated front/back camera simulation

Choose **Live camera** under Capture input, select Approve, accept the local demo disclosure, and tap **Start simulation**. Use a printed test card, not a real ID. Photograph the front, review or Retake, then **Use this image**. Repeat for the back. Finish within three minutes. The result should say **Simulated approval. No identity was verified.** Confirmed photos are temporarily encrypted on-device and cleaned up at the end; transfers and results remain local simulations.

Repeat with **Cancel capture**, and with locking/unlocking during front review or back capture. Expect cancellation and then a successful fresh run. **Test live camera** remains a separate single-image discard test. Simulator users should choose **Generated cards**.

### Review a manual crop

In Live camera, place the printed test card within the guide. The outline follows a locally detected rectangle when available: yellow and the status text request positioning or stability; green means three stable observations were seen. Detection is advisory and never validates a card or disables the manual shutter. Take a photo, then adjust Left, Top, Right and Bottom crop-edge sliders until all card corners remain inside the outline. Scroll if needed. Tap **Preview crop**, inspect the result, then **Use this image** or **Retake**. Repeat for the back. Locking the phone during editing must cancel and clear the session.

For accessibility checks, enable VoiceOver and the largest Dynamic Type size. Guidance is available in status text and the preview's spoken value rather than color alone. Each crop slider announces its edge and percentage inset; the screen remains vertically scrollable.
