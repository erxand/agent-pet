import Foundation

package enum DemoScript {
    package static func clickCaption(petLabel: String) -> String {
        "In real use, the terminal tab for \(petLabel) comes to the front."
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
            durationInSeconds: 3,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "agent-pet",
                    subtitle: "A small pet for each agent that waits for you.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 2.4, action: .hideTitle)
            ]
        ),
        DemoScene(
            name: .climbOut,
            caption: "An agent finishes its turn. Its pet climbs out of the ground.",
            durationInSeconds: 4.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.refactor, mood: .ready, message: "Refactor done")),
                DemoStep(offsetInSeconds: 3.4, action: .hide(actorIds: [ActorId.refactor]))
            ]
        ),
        DemoScene(
            name: .needsInput,
            caption: "This agent needs your OK. Its pet stands still under a ! bubble.",
            durationInSeconds: 4.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.migrate, mood: .needsInput, message: "Run the migration?")),
                DemoStep(offsetInSeconds: 3.4, action: .hide(actorIds: [ActorId.migrate]))
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
            ]
        ),
        DemoScene(
            name: .click,
            caption: "Click a pet to go to its session. You can click this one.",
            durationInSeconds: 5.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.deploy, mood: .ready, message: "Deployed")),
                DemoStep(offsetInSeconds: 3.2, action: .click(actorId: ActorId.deploy))
            ]
        ),
        DemoScene(
            name: .dive,
            caption: "When you return to a session, its pet dives into the ground.",
            durationInSeconds: 3.5,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0.4, action: .show(actorId: ActorId.lint, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 0.7, action: .show(actorId: ActorId.ui, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.8, action: .hide(actorIds: [ActorId.lint])),
                DemoStep(offsetInSeconds: 2.7, action: .hide(actorIds: [ActorId.ui]))
            ]
        ),
        DemoScene(
            name: .finale,
            caption: nil,
            durationInSeconds: 4,
            labelPlacement: .pill,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "You can configure much more",
                    subtitle: "Labels, sprites, colors, groups and how a click focuses. Read Configuration in the README.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 3.5, action: .hideTitle)
            ]
        )
    ]

    package static func scene(named name: DemoSceneName) -> DemoScene? {
        scenes.first { scene in scene.name == name }
    }

    package static var totalDurationInSeconds: Double {
        scenes.reduce(0) { total, scene in total + scene.durationInSeconds }
    }
}
