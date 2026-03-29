// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "RunClaude",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "RunClaude",
            path: "Sources/RunClaude",
            resources: [
                .copy("../../Resources/Info.plist"),
                .copy("custom")
            ]
        )
    ]
)
