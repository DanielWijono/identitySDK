# iPhone simulation samples

Open `IdentityFlowSamples.xcodeproj` in Xcode. Choose **UIKitSample** or **SwiftUISample**, select an iPhone simulator, and press **Run** (⌘R). The project references the SDK package two directories above; keep this folder inside the repository. No account, backend or camera permission is needed for Simulator. Keep Xcode’s normal signing enabled: the Keychain needs the simulated app identity. Do not build this integration with `CODE_SIGNING_ALLOWED=NO`; the unsigned build failed storage initialization in validation.

Select an outcome, accept the sample disclosure and tap **Start simulation**. The flow takes approximately four seconds. Try **Cancel simulation** while it runs. Inactivity immediately closes the vault gate, conceals the screen and cancels the sample's task; this is a demo policy, not the production reconciliation feature. Synthetic JPEGs are normalized and encrypted locally and cleared before a normal result is displayed. If deletion fails, the app shows Retry cleanup and blocks another run until recovery succeeds.

Both hosts use the same UIKit screen; the SwiftUI host wraps it with `UIViewControllerRepresentable`. These are consumer examples, not the future SDK-owned capture/review UI. Every outcome is simulated, including pending: no remote verification continues after the demo closes.

The generated Xcode project is committed, so XcodeGen is not required to run. After editing `project.yml`, regenerate from the repository root with:

```sh
xcodegen generate --spec Examples/iOS/project.yml
```

Choose UIKitSample and press ⌘U for the UI tests. They exercise consent gating, the four outcomes, cancellation, and background/foreground followed by another run. The apps target iOS 16 and Swift 6. A physical device requires your own signing team; camera functionality is not implemented.
