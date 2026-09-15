// swift-tools-version: 6.0
import PackageDescription

let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Yongkang",
    platforms: [.macOS(.v13)],
    products: [
        // For an app target to link. The Yongkang executable below is what make-app.sh bundles.
        .library(name: "YongkangUI", targets: ["YongkangUI"]),
        .executable(name: "shots", targets: ["Shots"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
    ],
    targets: [
        // Foundation only: the notebook, providers, git, review, prompts. If it needs
        // SwiftUI, it belongs in YongkangUI.
        .target(name: "YongkangCore", swiftSettings: v5),
        .target(name: "YongkangUI", dependencies: ["YongkangCore", "SwiftTerm"], swiftSettings: v5),
        .executableTarget(name: "Yongkang", dependencies: ["YongkangUI"], swiftSettings: v5),
        // Dev-only: `swift run shots <dir>` renders every screen offscreen. Never in the app.
        .executableTarget(name: "Shots", dependencies: ["YongkangCore", "YongkangUI"], swiftSettings: v5),
        .testTarget(
            name: "YongkangCoreTests",
            dependencies: ["YongkangCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: v5
        ),
        .testTarget(name: "YongkangUITests", dependencies: ["YongkangCore", "YongkangUI"], swiftSettings: v5),
    ]
)
