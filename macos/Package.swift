// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ClaudeGeiger",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "GeigerCore"),
        .executableTarget(name: "ClaudeGeiger", dependencies: ["GeigerCore"]),
        .executableTarget(name: "GeigerCoreTests", dependencies: ["GeigerCore"]),
    ]
)
