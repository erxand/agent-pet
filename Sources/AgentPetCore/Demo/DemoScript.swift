import Foundation

package enum DemoScript {
    package static let focusedKeyHint = "space: next   esc: quit"
    package static let unfocusedKeyHint = "click here, then press space"

    package static func keyHint(hasFocus: Bool) -> String {
        hasFocus ? focusedKeyHint : unfocusedKeyHint
    }

    private enum PackName {
        static let claude = SpritePackLoader.defaultPackName
        static let golem = "golem"
        static let hatchling = "hatchling"
    }

    private enum ActorId {
        static let refactor = "demo-refactor-41d2"
        static let migrate = "demo-migrate-93be"
        static let deploy = "demo-deploy-6e2b"
    }

    package static let cast: [DemoActor] = [
        DemoActor(sessionId: ActorId.refactor, nickname: "api refactor", sprite: PackName.claude, accent: .orange),
        DemoActor(sessionId: ActorId.migrate, nickname: "migrations", sprite: PackName.golem, accent: .green),
        DemoActor(sessionId: ActorId.deploy, nickname: "deploy", sprite: PackName.hatchling, accent: .cyan)
    ]

    package static let scenes: [DemoScene] = [
        DemoScene(
            name: .title,
            caption: nil,
            durationInSeconds: 6,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "agent-pet",
                    subtitle: "A small pet for each agent that waits for you.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 5.4, action: .hideTitle)
            ]
        ),
        DemoScene(
            name: .states,
            caption: "Your pets will appear when your agent is ready and waiting for you.",
            durationInSeconds: 9.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.4, action: .show(actorId: ActorId.refactor, mood: .ready, message: "Refactor done")),
                DemoStep(offsetInSeconds: 0.7, action: .show(actorId: ActorId.migrate, mood: .needsInput, message: "Run the migration?")),
                DemoStep(offsetInSeconds: 8.4, action: .hide(actorIds: [ActorId.refactor, ActorId.migrate]))
            ],
            holdOffsetInSeconds: 2.5,
            stateSlots: [
                DemoStateSlot(label: "Ready: turn done", actorId: ActorId.refactor),
                DemoStateSlot(label: "Needs your input", actorId: ActorId.migrate),
                DemoStateSlot(label: "Working: no pet", actorId: nil)
            ]
        ),
        DemoScene(
            name: .click,
            caption: "Clicking the pet brings the terminal tab to focus.",
            durationInSeconds: 6.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.deploy, mood: .ready, message: "Deployed")),
                DemoStep(offsetInSeconds: 1.4, action: .pointCursor(actorId: ActorId.deploy)),
                DemoStep(offsetInSeconds: 3.2, action: .click(actorId: ActorId.deploy)),
                DemoStep(offsetInSeconds: 3.7, action: .showTerminal(DemoTerminalCard(
                    title: "deploy",
                    accent: .cyan,
                    mascotSprite: PackName.claude,
                    productName: "Claude Code",
                    directory: "~/api",
                    userMessage: "Deploy the api to staging.",
                    reply: "Deployed. The health check passed.",
                    statusLine: "dir: ~/api \u{00B7} branch: main"
                ))),
                DemoStep(offsetInSeconds: 4.3, action: .hideCursor),
                DemoStep(offsetInSeconds: 6, action: .hideTerminal)
            ],
            holdOffsetInSeconds: 5
        ),
        DemoScene(
            name: .finale,
            caption: nil,
            durationInSeconds: 4,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "Configure things to your system",
                    subtitle: "Labels, sprites, colors, how a click focuses, and more. Read Configuration in the README.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 3.5, action: .hideTitle)
            ],
            holdOffsetInSeconds: 1
        )
    ]

    package static let extraScenes: [DemoScene] = [
        DemoScene(
            name: .space,
            caption: "With floatOverScreensaver on, pets drift over the screensaver, then land and walk home.",
            durationInSeconds: 15,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.4, action: .show(actorId: ActorId.refactor, mood: .ready, message: "Refactor done")),
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.migrate, mood: .needsInput, message: "Run the migration?")),
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.deploy, mood: .ready, message: "Deployed")),
                DemoStep(offsetInSeconds: 2, action: .showScreensaver),
                DemoStep(offsetInSeconds: 9, action: .hideScreensaver),
                DemoStep(offsetInSeconds: 14, action: .hide(actorIds: [ActorId.refactor, ActorId.migrate, ActorId.deploy]))
            ],
            holdOffsetInSeconds: 13.5
        )
    ]

    package static func scene(named name: DemoSceneName) -> DemoScene? {
        (scenes + extraScenes).first { scene in scene.name == name }
    }

    package static var totalDurationInSeconds: Double {
        scenes.reduce(0) { total, scene in total + scene.durationInSeconds }
    }
}
