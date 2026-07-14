// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tomatoro",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Tomatoro",
            path: "Sources/Tomatoro"
        )
    ]
)
