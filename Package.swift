// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IdentityFlow",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "IdentityFlowUI", targets: ["IdentityFlowUI"]),
        .library(name: "IdentityFlowCapture", targets: ["IdentityFlowCapture"]),
        .library(name: "IdentityFlowSecurity", targets: ["IdentityFlowSecurity"]),
        .library(name: "IdentityFlowCore", targets: ["IdentityFlowCore"]),
        .library(name: "IdentityFlowHTTP", targets: ["IdentityFlowHTTP"]),
        .library(name: "IdentityFlowDemoService", targets: ["IdentityFlowDemoService"]),
        .library(name: "IdentityFlowDemoSupport", targets: ["IdentityFlowDemoSupport"])
    ],
    targets: [
        .target(name: "IdentityFlowUI", dependencies: ["IdentityFlowCapture", "IdentityFlowCore"]),
        .target(name: "IdentityFlowCapture"),
        .testTarget(name: "IdentityFlowCaptureTests", dependencies: ["IdentityFlowCapture"]),
        .target(name: "IdentityFlowCore"),
        .target(name: "IdentityFlowSecurity", dependencies: ["IdentityFlowCore"]),
        .testTarget(name: "IdentityFlowSecurityTests", dependencies: ["IdentityFlowSecurity", "IdentityFlowCore"]),
        .target(name: "IdentityFlowHTTP", dependencies: ["IdentityFlowCore"]),
        .target(name: "IdentityFlowDemoService", dependencies: ["IdentityFlowCore", "IdentityFlowHTTP"]),
        .testTarget(name: "IdentityFlowHTTPTests", dependencies: ["IdentityFlowHTTP", "IdentityFlowDemoService", "IdentityFlowCore"]),
        .target(name: "IdentityFlowDemoSupport", dependencies: ["IdentityFlowCore"]),
        .testTarget(name: "IdentityFlowCoreTests", dependencies: ["IdentityFlowCore", "IdentityFlowDemoSupport"])
    ],
    swiftLanguageModes: [.v6]
)
