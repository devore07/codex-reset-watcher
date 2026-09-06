// swift-tools-version: 6.0

import PackageDescription

var products: [Product] = [
    .executable(name: "ClaudeUsageBridge", targets: ["ClaudeUsageBridge"])
]
var targets: [Target] = [
    .target(name: "ClaudeUsageCore"),
    .executableTarget(name: "ClaudeUsageBridge", dependencies: ["ClaudeUsageCore"]),
    .testTarget(name: "ClaudeUsageCoreTests", dependencies: ["ClaudeUsageCore"])
]
#if os(macOS)
products.append(.executable(name: "CodexResetWatcher", targets: ["CodexResetWatcher"]))
targets += [
    .executableTarget(name: "CodexResetWatcher", dependencies: ["ClaudeUsageCore"]),
    .testTarget(name: "CodexResetWatcherTests", dependencies: ["CodexResetWatcher", "ClaudeUsageCore"])
]
#endif

let package = Package(
    name: "CodexResetWatcher",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    targets: targets
)
