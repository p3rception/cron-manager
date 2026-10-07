// swift-tools-version: 6.3
// Builds with Command Line Tools only. Run ./build.sh to produce dist/CronManager.app.
import PackageDescription

let package = Package(
    name: "CronManager",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(
            name: "CronManager",
            path: "CronManager",
            exclude: ["AppIcon.icns"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .defaultIsolation(MainActor.self),
            ]
        ),
    ]
)
