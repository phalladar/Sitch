// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sitch",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "Sitch",
            path: "Sources/Sitch",
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
