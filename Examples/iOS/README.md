# iPhone simulation samples

Open `IdentityFlowSamples.xcodeproj` in Xcode. Choose **UIKitSample** or **SwiftUISample**, select an iPhone simulator, and press **Run** (⌘R). The project references the SDK package two directories above; keep this folder inside the repository. No account, backend, camera permission or signing team is needed for Simulator.

Select an outcome, accept the sample disclosure and tap **Start simulation**. The flow takes approximately four seconds. Try **Cancel simulation** while it runs. Backgrounding the app cancels the sample's task; this is a demo policy, not the production reconciliation feature. Synthetic evidence is cleared before a result is displayed.

Both hosts use the same UIKit screen; the SwiftUI host wraps it with `UIViewControllerRepresentable`. These are consumer examples, not the future SDK-owned capture/review UI. Every outcome is simulated, including pending: no remote verification continues after the demo closes.

The generated Xcode project is committed, so XcodeGen is not required to run. After editing `project.yml`, regenerate from the repository root with:

```sh
xcodegen generate --spec Examples/iOS/project.yml
```

Choose UIKitSample and press ⌘U for the UI tests. They exercise consent gating, the four outcomes, cancellation and restart availability. The apps target iOS 16 and Swift 6. A physical device requires your own signing team; camera functionality is not implemented.
