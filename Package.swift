// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "agent-pet",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .target(
            name: "AgentPetCore",
            path: "Sources/AgentPetCore"
        ),
        .executableTarget(
            name: "agent-pet",
            dependencies: ["AgentPetCore"],
            path: "Sources/agent-pet"
        ),
        .testTarget(
            name: "AgentPetTests",
            dependencies: ["AgentPetCore", "agent-pet"],
            path: "Tests/AgentPetTests"
        )
    ]
)
