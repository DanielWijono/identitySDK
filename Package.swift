// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IdentityFlow",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "IdentityFlowCapture", targets: ["IdentityFlowCapture"]),
        .library(name: "IdentityFlowSecurity", targets: ["IdentityFlowSecurity"]),
        .library(name: "IdentityFlowCore", targets: ["IdentityFlowCore"]),
        .library(name: "IdentityFlowDemoSupport", targets: ["IdentityFlowDemoSupport"])
    ],
    targets: [
        .target(name: "IdentityFlowCapture"),
        .testTarget(name: "IdentityFlowCaptureTests", dependencies: ["IdentityFlowCapture"]),
        .target(name: "IdentityFlowCore"),
        .target(name: "IdentityFlowSecurity", dependencies: ["IdentityFlowCore"]),
        .testTarget(name: "IdentityFlowSecurityTests", dependencies: ["IdentityFlowSecurity", "IdentityFlowCore"]),
        .target(name: "IdentityFlowDemoSupport", dependencies: ["IdentityFlowCore"]),
        .testTarget(name: "IdentityFlowCoreTests", dependencies: ["IdentityFlowCore", "IdentityFlowDemoSupport"])
    ],
    swiftLanguageModes: [.v6]
)
