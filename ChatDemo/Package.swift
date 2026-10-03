// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ChatDemo",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "ChatDemo", path: "Sources/ChatDemo")
    ]
)
