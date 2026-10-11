// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Sub2APIWidgetCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Sub2APIWidgetCore", targets: ["Sub2APIWidgetCore"])
    ],
    targets: [
        .target(
            name: "Sub2APIWidgetCore",
            path: "Sub2APIWidget/Shared",
            sources: [
                "Constants.swift",
                "Models.swift",
                "SnapshotBuilder.swift",
                "Sub2APIDecoding.swift",
                "URLRouting.swift",
                // These used to be excluded, which meant CI never compiled the
                // highest-risk modules. They are pure Foundation/Security/WidgetKit
                // and build cleanly on macOS, so keep them under test.
                "AppIntents.swift",
                "KeychainStore.swift",
                "MetricFormatters.swift",
                "Poller.swift",
                "SafeMessage.swift",
                "SnapshotStore.swift",
                "Sub2APIClient.swift"
            ]
        ),
        .testTarget(
            name: "Sub2APIWidgetCoreTests",
            dependencies: ["Sub2APIWidgetCore"],
            path: "Sub2APIWidgetTests"
        )
    ]
)
