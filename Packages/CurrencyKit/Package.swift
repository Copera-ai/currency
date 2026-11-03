// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "CurrencyKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "CurrencyKit", targets: ["CurrencyKit"]),
    ],
    targets: [
        .target(
            name: "CurrencyKit",
            resources: [.process("Resources")],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "CurrencyKitTests",
            dependencies: ["CurrencyKit"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
