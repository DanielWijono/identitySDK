// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "IdentityFlowSimulation",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../..")],
    targets: [.executableTarget(name: "Simulation", dependencies: [
        .product(name: "IdentityFlowCore", package: "IdentitySDK"),
        .product(name: "IdentityFlowDemoSupport", package: "IdentitySDK")
    ], path: "Sources")]
)
