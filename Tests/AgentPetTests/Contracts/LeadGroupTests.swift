import Foundation
import Testing
@testable import AgentPetCore

@Suite("a lead group: one pet that waits for every member and goes to the lead")
struct LeadGroupTests {
    private static let group = "ticket:ABC-1140"
    private static let dev = "dev-aaaa-1111"
    private static let review = "review-bbbb-2222"
    private static let test = "test-cccc-3333"

    private static func pane(_ sessionId: String) -> String {
        "pane:" + String(sessionId.prefix(while: { character in character != "-" }))
    }

    private static func label(_ sessionId: String) -> String {
        "ABC-1140 (" + String(sessionId.prefix(while: { character in character != "-" })).uppercased() + ")"
    }

    private var all: [String] { [LeadGroupTests.dev, LeadGroupTests.review, LeadGroupTests.test] }

    private func enroll(_ sandbox: Sandbox, _ sessionId: String, owner: Bool) throws {
        var arguments = [
            "on", "--session", sessionId,
            "--group", LeadGroupTests.group,
            "--group-mode", "lead",
            "--label", LeadGroupTests.label(sessionId),
            "--focus-target", LeadGroupTests.pane(sessionId),
            "--pid", String(getpid()),
            "--no-color-sync"
        ]
        if owner { arguments.append("--owner") }
        let run = try sandbox.run(arguments)
        #expect(run.exitStatus == 0)
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func hook(_ sandbox: Sandbox, _ event: String, _ sessionId: String, extra: [String: Any] = [:]) throws {
        try sandbox.hook(RecordFixtures.hookPayload(event, sessionId: sessionId, extra: extra))
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func records(_ sandbox: Sandbox, _ sessionIds: [String]) throws -> [PetSession] {
        try sessionIds.compactMap { sessionId in
            guard sandbox.exists(sandbox.recordURL(sessionId)) else { return nil }
            return try JSONDecoder().decode(PetSession.self, from: Data(contentsOf: sandbox.recordURL(sessionId)))
        }
    }

    private func plan(_ sandbox: Sandbox, _ sessionIds: [String]) throws -> [PetDisplayItem] {
        PetDisplayPlanner(grouping: SharedKeyGrouping(), disambiguatesLabels: true)
            .displayItems(records: try records(sandbox, sessionIds), claudeSessions: [:])
    }

    private func worktreeWindow() throws -> Sandbox {
        let sandbox = try Sandbox()
        try enroll(sandbox, LeadGroupTests.dev, owner: true)
        try enroll(sandbox, LeadGroupTests.review, owner: false)
        try enroll(sandbox, LeadGroupTests.test, owner: false)
        return sandbox
    }

    @Test func onStoresTheModeAndSharedClearsIt() throws {
        let sandbox = try Sandbox()
        try enroll(sandbox, LeadGroupTests.dev, owner: true)
        #expect(sandbox.record(LeadGroupTests.dev)?["groupMode"] as? String == "lead")
        try sandbox.run(["on", "--session", LeadGroupTests.dev, "--group-mode", "shared", "--no-color-sync"])
        #expect(sandbox.record(LeadGroupTests.dev)?["groupMode"] == nil)
        let refused = try sandbox.run(["on", "--session", LeadGroupTests.dev, "--group-mode", "boss"])
        #expect(refused.exitStatus == 2)
        #expect(refused.standardError.contains("unknown group mode boss"))
    }

    @Test func theLeadsReadyWaitsWhileAMemberWorks() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        try hook(sandbox, "Stop", LeadGroupTests.dev)
        #expect(try plan(sandbox, all).isEmpty)
        try hook(sandbox, "Stop", LeadGroupTests.review)
        #expect(try plan(sandbox, all).isEmpty)
    }

    @Test func everyoneReadyShowsOnePetLabelledByTheLeadThatClicksToTheLead() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        let items = try plan(sandbox, all)
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.mood == .ready)
        #expect(item.petKey == LeadGroupTests.group)
        #expect(item.label == "ABC-1140 (DEV)")
        #expect(item.bubbleCaption == nil)
        #expect(item.session.sessionId == LeadGroupTests.dev)
        #expect(item.focusRequest.sessionId == LeadGroupTests.dev)
        #expect(item.focusRequest.focusTarget == "pane:dev")
        #expect(Set(item.memberSessionIds) == Set(all))
    }

    @Test func hidingTheLeadsPaneHidesEveryReadyMember() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        try sandbox.run(["hide", "--focus-target", "pane:dev"])
        #expect(try records(sandbox, all).map { record in record.visible } == [false, false, false])
        #expect(try plan(sandbox, all).isEmpty)
    }

    @Test func hidingTheLeadsPaneLeavesAMembersQuestion() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        try hook(sandbox, "Stop", LeadGroupTests.dev)
        try hook(sandbox, "Stop", LeadGroupTests.test)
        try hook(sandbox, "Notification", LeadGroupTests.review, extra: ["notification_type": "permission_prompt"])
        try sandbox.run(["hide", "--focus-target", "pane:dev"])
        #expect(try records(sandbox, all).map { record in record.visible } == [false, true, false])
        let items = try plan(sandbox, all)
        #expect(items.map { item in item.focusRequest.sessionId } == [LeadGroupTests.review])
    }

    @Test func hidingAMembersPaneHidesOnlyThatMember() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        try sandbox.run(["hide", "--focus-target", "pane:review"])
        #expect(try records(sandbox, all).map { record in record.visible } == [true, false, true])
    }

    @Test func aMembersQuestionShowsAtOnceUnderItsOwnLabelAndClick() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        try hook(sandbox, "Notification", LeadGroupTests.review, extra: ["notification_type": "permission_prompt"])
        let items = try plan(sandbox, all)
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.mood == .needsInput)
        #expect(item.petKey == LeadGroupTests.group + "#" + LeadGroupTests.review)
        #expect(item.label == "ABC-1140 (REVIEW)")
        #expect(item.session.sessionId == LeadGroupTests.review)
        #expect(item.focusRequest.sessionId == LeadGroupTests.review)
        #expect(item.focusRequest.focusTarget == "pane:review")
        #expect(item.memberSessionIds == [LeadGroupTests.review])
    }

    @Test func aMembersQuestionStandsBesideTheLeadsReady() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        try hook(sandbox, "Stop", LeadGroupTests.dev)
        try hook(sandbox, "Stop", LeadGroupTests.test)
        try hook(sandbox, "Notification", LeadGroupTests.review, extra: ["notification_type": "permission_prompt"])
        #expect(try plan(sandbox, all).map { item in item.focusRequest.sessionId } == [LeadGroupTests.review])

        try hook(sandbox, "Stop", LeadGroupTests.review)
        try sandbox.run(["show", "--session", LeadGroupTests.review, "--mood", "needsInput"])
        let items = try plan(sandbox, all)
        #expect(items.map { item in item.focusRequest.sessionId } == [LeadGroupTests.dev, LeadGroupTests.review])
        #expect(items.map { item in item.mood } == [.ready, .needsInput])
        #expect(items.first?.memberSessionIds.contains(LeadGroupTests.review) == false)
    }

    @Test func theLeadsOwnQuestionGoesOnTheLeadsPet() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        try hook(sandbox, "Notification", LeadGroupTests.dev, extra: ["notification_type": "permission_prompt"])
        let items = try plan(sandbox, all)
        #expect(items.count == 1)
        #expect(items.first?.petKey == LeadGroupTests.group)
        #expect(items.first?.mood == .needsInput)
        #expect(items.first?.label == "ABC-1140 (DEV)")
    }

    @Test func withNoLiveLeadItIsAPlainGroupLabelledByTheWaitingMember() throws {
        let sandbox = try Sandbox()
        try enroll(sandbox, LeadGroupTests.review, owner: false)
        try enroll(sandbox, LeadGroupTests.test, owner: false)
        let pair = [LeadGroupTests.review, LeadGroupTests.test]
        for sessionId in pair { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in pair { try hook(sandbox, "Stop", sessionId) }
        let items = try plan(sandbox, pair)
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.label == "ABC-1140 (TEST)")
        #expect(item.focusRequest.sessionId == LeadGroupTests.test)
        #expect(item.session.sessionId == LeadGroupTests.review)
    }

    @Test func aGroupWithoutTheModeKeepsTodaysRules() throws {
        let sandbox = try worktreeWindow()
        for sessionId in all {
            try sandbox.run(["on", "--session", sessionId, "--group-mode", "shared", "--no-color-sync"])
        }
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        let item = try #require(try plan(sandbox, all).first)
        #expect(item.focusRequest.sessionId == LeadGroupTests.test)
        #expect(item.label == "ABC-1140 (DEV)")
        #expect(item.bubbleCaption == "ABC-1140 (TEST)")
        try sandbox.run(["hide", "--focus-target", "pane:dev"])
        #expect(try records(sandbox, all).map { record in record.visible } == [false, true, true])
    }
}

@Suite("a disambiguation hint names a clash inside one scope")
struct DisambiguationHintTests {
    private func pet(_ sessionId: String, label: String, hint: String? = nil, scope: String? = nil, updatedAt: Double) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: sessionId)
        session.visible = true
        session.label = label
        session.disambiguator = hint
        session.disambiguationScope = scope
        session.updatedAt = updatedAt
        session.pid = getpid()
        return session
    }

    private func labels(_ records: [PetSession], disambiguates: Bool = true) -> [String] {
        PetDisplayPlanner(grouping: SharedKeyGrouping(), disambiguatesLabels: disambiguates)
            .displayItems(records: records, claudeSessions: [:])
            .map { item in item.label }
    }

    @Test func sameScopeDistinctHintsShowTheHint() {
        let pets = [
            pet("aaaa-1111", label: "repo", hint: "T1", scope: "w1", updatedAt: 10),
            pet("bbbb-2222", label: "repo", hint: "T2", scope: "w1", updatedAt: 20)
        ]
        #expect(labels(pets) == ["repo T1", "repo T2"])
        #expect(labels(pets, disambiguates: false) == ["repo", "repo"])
    }

    @Test func aClashAcrossScopesKeepsTheSessionIdSuffix() {
        let pets = [
            pet("aaaa-1111", label: "repo", hint: "T1", scope: "w1", updatedAt: 10),
            pet("bbbb-2222", label: "repo", hint: "T1", scope: "w2", updatedAt: 20),
            pet("cccc-3333", label: "repo", hint: "T2", scope: "w1", updatedAt: 30)
        ]
        #expect(labels(pets) == ["repo T1", "repo 2222", "repo T2"])
    }

    @Test func aRepeatedOrMissingHintKeepsTheSessionIdSuffix() {
        let repeated = [
            pet("aaaa-1111", label: "repo", hint: "T1", scope: "w1", updatedAt: 10),
            pet("bbbb-2222", label: "repo", hint: "T1", scope: "w1", updatedAt: 20)
        ]
        #expect(labels(repeated) == ["repo 1111", "repo 2222"])
        let missing = [
            pet("aaaa-1111", label: "repo", hint: "T1", scope: "w1", updatedAt: 10),
            pet("bbbb-2222", label: "repo", scope: "w1", updatedAt: 20),
            pet("cccc-3333", label: "repo", updatedAt: 30)
        ]
        #expect(labels(missing) == ["repo T1", "repo 2222", "repo 3333"])
    }

    @Test func noClashShowsNoHint() {
        let pets = [
            pet("aaaa-1111", label: "repo", hint: "T1", scope: "w1", updatedAt: 10),
            pet("bbbb-2222", label: "other", hint: "T2", scope: "w1", updatedAt: 20)
        ]
        #expect(labels(pets) == ["repo", "other"])
    }

    @Test func onStoresTheHintAndItsScope() throws {
        let sandbox = try Sandbox()
        let run = try sandbox.run([
            "on", "--session", RecordFixtures.sessionId,
            "--disambiguator", "T3", "--disambiguation-scope", "win:1a2b", "--no-color-sync"
        ])
        #expect(run.exitStatus == 0)
        #expect(sandbox.record(RecordFixtures.sessionId)?["disambiguator"] as? String == "T3")
        #expect(sandbox.record(RecordFixtures.sessionId)?["disambiguationScope"] as? String == "win:1a2b")
    }
}
