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
        static let mossling = "mossling"
        static let nimbus = "nimbus"
        static let seon = "seon"
    }

    private enum ActorId {
        static let refactor = "demo-refactor-41d2"
        static let migrate = "demo-migrate-93be"
        static let tests = "demo-tests-0a17"
        static let docs = "demo-docs-5c88"
        static let api = "demo-api-e64f"
        static let deploy = "demo-deploy-6e2b"
        static let lint = "demo-lint-91fa"
        static let ui = "demo-ui-47c3"
    }

    package static let cast: [DemoActor] = [
        DemoActor(sessionId: ActorId.refactor, nickname: "api refactor", sprite: PackName.claude, accent: .orange),
        DemoActor(sessionId: ActorId.migrate, nickname: "migrations", sprite: PackName.golem, accent: .green),
        DemoActor(sessionId: ActorId.tests, nickname: "tests", sprite: PackName.hatchling, accent: .cyan),
        DemoActor(sessionId: ActorId.docs, nickname: "docs", sprite: PackName.mossling, accent: .red),
        DemoActor(sessionId: ActorId.api, nickname: "api", sprite: PackName.nimbus, accent: .blue),
        DemoActor(sessionId: ActorId.deploy, nickname: "deploy", sprite: PackName.hatchling, accent: .cyan),
        DemoActor(sessionId: ActorId.lint, nickname: "lint", sprite: PackName.nimbus, accent: .blue),
        DemoActor(sessionId: ActorId.ui, nickname: "ui", sprite: PackName.seon, accent: .yellow)
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
            name: .lanes,
            caption: "Three sessions show three pets. Each pet has its own lane.",
            durationInSeconds: 5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.4, action: .show(actorId: ActorId.tests, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.docs, mood: .needsInput, message: nil)),
                DemoStep(offsetInSeconds: 1.2, action: .show(actorId: ActorId.api, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 3.9, action: .hide(actorIds: [ActorId.tests, ActorId.docs, ActorId.api]))
            ],
            holdOffsetInSeconds: 2.5
        ),
        DemoScene(
            name: .click,
            caption: "In real use, a click brings the pet's terminal tab to the front.",
            durationInSeconds: 6.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.deploy, mood: .ready, message: "Deployed")),
                DemoStep(offsetInSeconds: 1.4, action: .pointCursor(actorId: ActorId.deploy)),
                DemoStep(offsetInSeconds: 3.2, action: .click(actorId: ActorId.deploy)),
                DemoStep(offsetInSeconds: 3.7, action: .showTerminal(DemoTerminalCard(
                    title: "deploy",
                    lines: [
                        "~/api $ claude",
                        "> Deploy the api to staging.",
                        "Deployed. The health check passed.",
                        ">"
                    ],
                    accent: .cyan
                ))),
                DemoStep(offsetInSeconds: 4.3, action: .hideCursor),
                DemoStep(offsetInSeconds: 6, action: .hideTerminal)
            ],
            holdOffsetInSeconds: 5
        ),
        DemoScene(
            name: .dive,
            caption: "When you return to a session, its pet dives into the ground.",
            durationInSeconds: 4,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.4, action: .show(actorId: ActorId.lint, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 0.7, action: .show(actorId: ActorId.ui, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.8, action: .hide(actorIds: [ActorId.lint])),
                DemoStep(offsetInSeconds: 3.0, action: .hide(actorIds: [ActorId.ui]))
            ],
            holdOffsetInSeconds: 2.9
        ),
        DemoScene(
            name: .finale,
            caption: nil,
            durationInSeconds: 4,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "You can configure much more",
                    subtitle: "Labels, sprites, colors, how a click focuses, and more. Read Configuration in the README.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 3.5, action: .hideTitle)
            ],
            holdOffsetInSeconds: 1
        )
    ]

    package static func scene(named name: DemoSceneName) -> DemoScene? {
        scenes.first { scene in scene.name == name }
    }

    package static var totalDurationInSeconds: Double {
        scenes.reduce(0) { total, scene in total + scene.durationInSeconds }
    }
}
