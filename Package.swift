// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ClaudeUsageBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeUsageBar", targets: ["ClaudeUsageBar"]),
    ],
    targets: [
        .target(name: "UsageCore"),
        .executableTarget(name: "ClaudeUsageBar", dependencies: ["UsageCore"]),
        .testTarget(name: "UsageCoreTests", dependencies: ["UsageCore"]),
    ],
    swiftLanguageModes: [.v6]
)
