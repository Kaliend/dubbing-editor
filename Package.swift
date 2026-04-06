// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DubbingEditor",
    defaultLocalization: "cs",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "DubbingEditor",
            targets: ["DubbingEditor"]
        )
    ],
    targets: [
        .executableTarget(
            name: "DubbingEditor",
            path: "Sources/DubbingEditor",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "DubbingEditorTests",
            dependencies: ["DubbingEditor"],
            path: "Tests/DubbingEditorTests"
        )
    ]
)
