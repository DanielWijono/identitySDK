// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IdentityFlow",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "IdentityFlowCore", targets: ["IdentityFlowCore"]),
        .library(name: "IdentityFlowDemoSupport", targets: ["IdentityFlowDemoSupport"])
    ],
    targets: [
        .target(name: "IdentityFlowCore"),
        .target(name: "IdentityFlowDemoSupport", dependencies: ["IdentityFlowCore"]),
        .testTarget(name: "IdentityFlowCoreTests", dependencies: ["IdentityFlowCore", "IdentityFlowDemoSupport"])
    ],
    swiftLanguageModes: [.v6]
)
