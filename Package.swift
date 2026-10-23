// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeXMac",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeXMac", targets: ["DeXMac"]),
        .executable(name: "dex-self-test", targets: ["DeXCoreSelfTest"])
    ],
    targets: [
        .target(
            name: "DeXCore",
            path: "Sources/DeXCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DeXMac",
            dependencies: ["DeXCore"],
            path: "Sources/DeXMac",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DeXCoreSelfTest",
            dependencies: ["DeXCore"],
            path: "Sources/DeXCoreSelfTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
