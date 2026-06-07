// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TranscriptionApp",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "TranscriptionApp"
        )
    ]
)
