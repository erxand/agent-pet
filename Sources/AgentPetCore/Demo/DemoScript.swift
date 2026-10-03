import Foundation

package enum DemoScript {
    package static func clickCaption(petLabel: String) -> String {
        "In real use, the terminal tab for \(petLabel) comes to the front."
    }

    private static let ticketGroup = "NIST-1025"

    private enum PackName {
        static let claude = SpritePackLoader.defaultPackName
        static let golem = "golem"
        static let hatchling = "hatchling"
        static let mossling = "mossling"
        static let nimbus = "nimbus"
        static let seon = "seon"
        static let tinowl = "tinowl"
    }

    private enum ActorId {
        static let refactor = "demo-refactor-41d2"
        static let migrate = "demo-migrate-93be"
        static let tests = "demo-tests-0a17"
        static let docs = "demo-docs-5c88"
        static let api = "demo-api-e64f"
        static let billing = "demo-billing-2b90"
        static let infra = "demo-infra-7d31"
        static let ticketDev = "demo-dev-1025"
        static let ticketReview = "demo-review-1025"
        static let ticketQa = "demo-qa-1025"
        static let firstServer = "demo-server-7f3a"
        static let secondServer = "demo-server-c21e"
        static let search = "demo-search-88a0"
        static let auth = "demo-auth-3f19"
        static let mobile = "demo-mobile-c4d7"
        static let lead = "demo-lead-0001"
        static let deploy = "demo-deploy-6e2b"
        static let lint = "demo-lint-91fa"
        static let ui = "demo-ui-47c3"
        static let data = "demo-data-d05e"
    }

    package static let cast: [DemoActor] = [
        DemoActor(sessionId: ActorId.refactor, nickname: "api refactor", sprite: PackName.claude, accent: .orange),
        DemoActor(sessionId: ActorId.migrate, nickname: "migrations", sprite: PackName.golem, accent: .green),
        DemoActor(sessionId: ActorId.tests, nickname: "tests", sprite: PackName.hatchling, accent: .cyan),
        DemoActor(sessionId: ActorId.docs, nickname: "docs", sprite: PackName.mossling, accent: .red),
        DemoActor(sessionId: ActorId.api, nickname: "api", sprite: PackName.nimbus, accent: .blue),
        DemoActor(sessionId: ActorId.billing, nickname: "billing", sprite: PackName.seon, accent: .yellow),
        DemoActor(sessionId: ActorId.infra, nickname: "infra", sprite: PackName.tinowl, accent: .purple),
        DemoActor(sessionId: ActorId.ticketDev, nickname: ticketGroup, sprite: PackName.golem, accent: .green, group: ticketGroup, isOwner: true),
        DemoActor(sessionId: ActorId.ticketReview, nickname: "review", sprite: PackName.golem, accent: .green, group: ticketGroup),
        DemoActor(sessionId: ActorId.ticketQa, nickname: "qa", sprite: PackName.golem, accent: .green, group: ticketGroup),
        DemoActor(sessionId: ActorId.firstServer, nickname: "server", sprite: PackName.nimbus, accent: .blue),
        DemoActor(sessionId: ActorId.secondServer, nickname: "server", sprite: PackName.mossling, accent: .red),
        DemoActor(sessionId: ActorId.search, nickname: "search", sprite: PackName.golem, accent: .green),
        DemoActor(sessionId: ActorId.auth, nickname: "auth", sprite: PackName.seon, accent: .yellow),
        DemoActor(sessionId: ActorId.mobile, nickname: "mobile", sprite: PackName.tinowl, accent: .purple),
        DemoActor(sessionId: ActorId.lead, nickname: "lead", sprite: PackName.claude, accent: .orange),
        DemoActor(sessionId: ActorId.deploy, nickname: "deploy", sprite: PackName.hatchling, accent: .cyan),
        DemoActor(sessionId: ActorId.lint, nickname: "lint", sprite: PackName.nimbus, accent: .blue),
        DemoActor(sessionId: ActorId.ui, nickname: "ui", sprite: PackName.seon, accent: .yellow),
        DemoActor(sessionId: ActorId.data, nickname: "data", sprite: PackName.mossling, accent: .red)
    ]

    package static let scenes: [DemoScene] = [
        DemoScene(
            name: .title,
            caption: nil,
            durationInSeconds: 4.5,
            labelPlacement: .pill,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "agent-pet",
                    subtitle: "A small pet for each agent that waits for you.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 3.8, action: .hideTitle)
            ]
        ),
        DemoScene(
            name: .climbOut,
            caption: "An agent finishes its turn. Its pet climbs out of the ground.",
            durationInSeconds: 6,
            labelPlacement: .pill,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.refactor, mood: .ready, message: "Refactor done")),
                DemoStep(offsetInSeconds: 4.9, action: .hide(actorIds: [ActorId.refactor]))
            ]
        ),
        DemoScene(
            name: .needsInput,
            caption: "This agent needs your OK. Its pet stands still under a ! bubble.",
            durationInSeconds: 6,
            labelPlacement: .pill,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.migrate, mood: .needsInput, message: "Run the migration?")),
                DemoStep(offsetInSeconds: 4.9, action: .hide(actorIds: [ActorId.migrate]))
            ]
        ),
        DemoScene(
            name: .lanes,
            caption: "Five sessions show five pets. Each pet has its own lane.",
            durationInSeconds: 8,
            labelPlacement: .pill,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.tests, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.2, action: .show(actorId: ActorId.docs, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.8, action: .show(actorId: ActorId.api, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 2.4, action: .show(actorId: ActorId.billing, mood: .needsInput, message: nil)),
                DemoStep(offsetInSeconds: 3.0, action: .show(actorId: ActorId.infra, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 6.8, action: .hide(actorIds: [
                    ActorId.tests, ActorId.docs, ActorId.api, ActorId.billing, ActorId.infra
                ]))
            ]
        ),
        DemoScene(
            name: .group,
            caption: "Three agents on one ticket share one pet. Its bubble shows who waits.",
            durationInSeconds: 9,
            labelPlacement: .nametag,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.ticketReview, mood: .ready, message: "Review done")),
                DemoStep(offsetInSeconds: 4.2, action: .show(actorId: ActorId.ticketQa, mood: .needsInput, message: "Allow the browser?")),
                DemoStep(offsetInSeconds: 7.8, action: .hide(actorIds: [ActorId.ticketReview, ActorId.ticketQa]))
            ]
        ),
        DemoScene(
            name: .nametags,
            caption: "Two tabs have one name. Each tag adds the end of its session ID.",
            durationInSeconds: 6.5,
            labelPlacement: .nametag,
            disambiguatesLabels: true,
            steps: [
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.firstServer, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.6, action: .show(actorId: ActorId.secondServer, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 5.4, action: .hide(actorIds: [ActorId.firstServer, ActorId.secondServer]))
            ]
        ),
        DemoScene(
            name: .reserved,
            caption: "A random pick never uses a reserved sprite. Ask for it by name.",
            durationInSeconds: 6.5,
            labelPlacement: .nametag,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.6, action: .show(actorId: ActorId.search, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.1, action: .show(actorId: ActorId.auth, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.6, action: .show(actorId: ActorId.mobile, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 2.8, action: .show(actorId: ActorId.lead, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 5.4, action: .hide(actorIds: [
                    ActorId.search, ActorId.auth, ActorId.mobile, ActorId.lead
                ]))
            ]
        ),
        DemoScene(
            name: .click,
            caption: "Click a pet to go to its session. You can click this one.",
            durationInSeconds: 8,
            labelPlacement: .nametag,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.8, action: .show(actorId: ActorId.deploy, mood: .ready, message: "Deployed")),
                DemoStep(offsetInSeconds: 4.5, action: .click(actorId: ActorId.deploy))
            ]
        ),
        DemoScene(
            name: .dive,
            caption: "When you return to your desk, the pets dive into the ground.",
            durationInSeconds: 6,
            labelPlacement: .nametag,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0.5, action: .show(actorId: ActorId.lint, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 0.9, action: .show(actorId: ActorId.ui, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 1.3, action: .show(actorId: ActorId.data, mood: .ready, message: nil)),
                DemoStep(offsetInSeconds: 3.6, action: .hide(actorIds: [ActorId.lint, ActorId.ui, ActorId.data]))
            ]
        ),
        DemoScene(
            name: .finale,
            caption: nil,
            durationInSeconds: 5,
            labelPlacement: .nametag,
            disambiguatesLabels: false,
            steps: [
                DemoStep(offsetInSeconds: 0, action: .showTitle(DemoTitleCard(
                    title: "End of the tour",
                    subtitle: "To play one scene again, run agent-pet demo --scene NAME.",
                    accent: .orange
                ))),
                DemoStep(offsetInSeconds: 4.4, action: .hideTitle)
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
