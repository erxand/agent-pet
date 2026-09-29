// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-pet",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "agent-pet",
            path: "Sources/agent-pet"
        )
    ]
)
