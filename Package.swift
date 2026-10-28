// swift-tools-version: 6.0
import PackageDescription

let swift5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Notinhas",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "NotinhasCore", swiftSettings: swift5),
        .executableTarget(name: "Notinhas", dependencies: ["NotinhasCore"], swiftSettings: swift5),
        .testTarget(name: "NotinhasCoreTests", dependencies: ["NotinhasCore"], swiftSettings: swift5),
    ]
)
