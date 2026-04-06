// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DubbingEditor",
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
            path: "Sources/DubbingEditor"
        ),
        .testTarget(
            name: "DubbingEditorTests",
            dependencies: ["DubbingEditor"],
            path: "Tests/DubbingEditorTests"
        )
    ]
)
