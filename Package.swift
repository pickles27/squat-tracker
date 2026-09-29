// swift-tools-version: 6.0
// Builds and tests the app's platform-independent core (models, 5/3/1 engine,
// scheduling, streaks, export, OAuth helpers) with `swift test`.
// The iOS app itself is built from Squats.xcodeproj, which compiles the same files.
import PackageDescription

let package = Package(
    name: "SquatsCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(name: "SquatsCore", path: "Squats/Core"),
        .testTarget(name: "SquatsCoreTests", dependencies: ["SquatsCore"], path: "SquatsCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
