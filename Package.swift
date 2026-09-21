// swift-tools-version: 6.0
import PackageDescription

// Swift 6 mode turns data races into compile errors. Core went first because it is the half
// with the actors and the I/O; the SwiftUI targets followed.
//
// `ExistentialAny` costs almost nothing here — a handful of `any Error` — and makes the one
// place that really does box a protocol, `any AgentProvider`, say so.
let v6: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Yongkang",
    platforms: [.macOS(.v14)],
    products: [
        // What App/Yongkang.xcodeproj links. The app itself is built there, not by SwiftPM.
        .library(name: "YongkangUI", targets: ["YongkangUI"]),
        .executable(name: "shots", targets: ["Shots"]),
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        // The in-app updater (docs/release.md). 2.9 is the first to render Markdown release notes.
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        // Foundation only: the notebook, providers, git, review, prompts. If it needs
        // SwiftUI, it belongs in YongkangUI.
        .target(name: "YongkangCore", swiftSettings: v6),
        .target(
            name: "YongkangUI",
            dependencies: ["YongkangCore", "SwiftTerm", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: v6),
        // Dev-only: `swift run shots <dir>` renders every screen offscreen. Never in the app.
        .executableTarget(name: "Shots", dependencies: ["YongkangCore", "YongkangUI"], swiftSettings: v6),
        .testTarget(
            name: "YongkangCoreTests",
            dependencies: ["YongkangCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: v6
        ),
        .testTarget(name: "YongkangUITests", dependencies: ["YongkangCore", "YongkangUI"], swiftSettings: v6),
    ]
)
