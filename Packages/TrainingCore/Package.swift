// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrainingCore",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "TrainingCore", targets: ["TrainingCore"]),
    ],
    targets: [
        .target(
            name: "TrainingCore",
            resources: [.copy("Resources/plan.schema.json"), .copy("Resources/ai-analysis.schema.json")]
        ),
        .testTarget(
            name: "TrainingCoreTests",
            dependencies: ["TrainingCore"],
            resources: [.copy("Fixtures/samplePlan.json")]
        ),
    ]
)
