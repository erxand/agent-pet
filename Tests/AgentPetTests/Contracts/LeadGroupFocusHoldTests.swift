import Foundation
import Testing
@testable import AgentPetCore

@Suite("a lead group holds back while any pane of its window is in front")
struct LeadGroupFocusHoldTests {
    private static let group = "ticket:NIST-1140:win1"
    private static let dev = "dev-aaaa-1111"
    private static let review = "review-bbbb-2222"
    private static let test = "test-cccc-3333"

    private static func pane(_ sessionId: String) -> String {
        "termie:" + String(sessionId.prefix(while: { character in character != "-" }))
    }

    private var all: [String] { [LeadGroupFocusHoldTests.dev, LeadGroupFocusHoldTests.review, LeadGroupFocusHoldTests.test] }

    private func enroll(_ sandbox: Sandbox, _ sessionId: String, owner: Bool, lead: Bool = true) throws {
        var arguments = [
            "on", "--session", sessionId,
            "--group", LeadGroupFocusHoldTests.group,
            "--focus-target", LeadGroupFocusHoldTests.pane(sessionId),
            "--pid", String(getpid()),
            "--no-color-sync"
        ]
        if lead { arguments += ["--group-mode", "lead"] }
        if owner { arguments.append("--owner") }
        try sandbox.run(arguments)
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func hook(_ sandbox: Sandbox, _ event: String, _ sessionId: String, extra: [String: Any] = [:]) throws {
        try sandbox.hook(RecordFixtures.hookPayload(event, sessionId: sessionId, extra: extra))
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func writeFocus(_ sandbox: Sandbox, _ target: String) throws {
        let payload: [String: Any] = ["focusTarget": target, "pid": Int(getpid())]
        try JSONSerialization.data(withJSONObject: payload)
            .write(to: sandbox.stateDirectory.appendingPathComponent("focus.json"))
    }

    private func record(_ sandbox: Sandbox, _ sessionId: String) throws -> PetSession {
        try JSONDecoder().decode(PetSession.self, from: Data(contentsOf: sandbox.recordURL(sessionId)))
    }

    private func worktreeWindow(lead: Bool = true) throws -> Sandbox {
        let sandbox = try Sandbox()
        try enroll(sandbox, LeadGroupFocusHoldTests.dev, owner: true, lead: lead)
        try enroll(sandbox, LeadGroupFocusHoldTests.review, owner: false, lead: lead)
        try enroll(sandbox, LeadGroupFocusHoldTests.test, owner: false, lead: lead)
        return sandbox
    }

    @Test func aMembersFinishIsHeldWhileTheLeadsPaneIsInFront() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Stop", LeadGroupFocusHoldTests.review)
        let review = try record(sandbox, LeadGroupFocusHoldTests.review)
        #expect(!review.visible)
        #expect(review.held == true)
    }

    @Test func theLeadsFinishIsHeldWhileAMembersPaneIsInFront() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:test")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.dev)
        try hook(sandbox, "Stop", LeadGroupFocusHoldTests.dev)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.dev).held == true)
    }

    @Test func aMembersQuestionIsNotHeldByAnotherPane() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Notification", LeadGroupFocusHoldTests.review, extra: ["notification_type": "permission_prompt"])
        let review = try record(sandbox, LeadGroupFocusHoldTests.review)
        #expect(review.visible)
        #expect(review.held == nil)
    }

    @Test func anotherWindowsPaneHoldsNothing() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:elsewhere")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Stop", LeadGroupFocusHoldTests.review)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).visible)
    }

    @Test func aPlainGroupHoldsOnlyByItsOwnPane() throws {
        let sandbox = try worktreeWindow(lead: false)
        try writeFocus(sandbox, "termie:dev")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Stop", LeadGroupFocusHoldTests.review)
        let review = try record(sandbox, LeadGroupFocusHoldTests.review)
        #expect(review.visible)
        #expect(review.held == nil)
    }

    @Test func leavingTheLeadsPaneInTimeReleasesTheHeldMembers() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        #expect(try all.map { sessionId in try record(sandbox, sessionId).held } == [true, true, true])
        try writeFocus(sandbox, "termie:elsewhere")
        try sandbox.run(["release", "--focus-target", "termie:dev", "--grace", "10"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [true, true, true])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).held } == [nil, nil, nil])
    }

    @Test func stayingPastTheGraceDropsEveryHold() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        Thread.sleep(forTimeInterval: 0.3)
        try writeFocus(sandbox, "termie:elsewhere")
        try sandbox.run(["release", "--focus-target", "termie:dev", "--grace", "0.2"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [false, false, false])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).held } == [nil, nil, nil])
    }

    @Test func hidingTheLeadDropsEveryMembersHold() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
        try sandbox.run(["hide", "--focus-target", "termie:dev"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).held } == [nil, nil, nil])
        try sandbox.run(["release", "--focus-target", "termie:dev", "--grace", "10"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [false, false, false])
    }

    private func finishAll(_ sandbox: Sandbox) throws {
        for sessionId in all { try hook(sandbox, "UserPromptSubmit", sessionId) }
        for sessionId in all { try hook(sandbox, "Stop", sessionId) }
    }

    @Test func leavingTheWindowFromAMembersPaneReleasesTheLeadsHold() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:test")
        try finishAll(sandbox)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.dev).held == true)
        try writeFocus(sandbox, "termie:elsewhere")
        try sandbox.run(["release", "--focus-target", "termie:test", "--grace", "10"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [true, true, true])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).held } == [nil, nil, nil])
    }

    @Test func leavingAWindowWhoseLeadIsGoneReleasesTheOthers() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:test")
        try finishAll(sandbox)
        try sandbox.run(["remove", "--session", LeadGroupFocusHoldTests.dev])
        try writeFocus(sandbox, "termie:elsewhere")
        try sandbox.run(["release", "--focus-target", "termie:test", "--grace", "10"])
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).visible)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).held == nil)
    }

    @Test func movingBetweenPanesOfTheWindowKeepsEveryHold() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:dev")
        try finishAll(sandbox)
        let heldAt = try all.map { sessionId in try record(sandbox, sessionId).heldAt }
        try writeFocus(sandbox, "termie:review")
        try sandbox.run(["release", "--focus-target", "termie:dev", "--grace", "10"])
        try sandbox.run(["hide", "--focus-target", "termie:review"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [false, false, false])
        #expect(try record(sandbox, LeadGroupFocusHoldTests.dev).held == true)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.test).held == true)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.dev).heldAt == heldAt[0])

        try writeFocus(sandbox, "termie:elsewhere")
        try sandbox.run(["release", "--focus-target", "termie:review", "--grace", "10"])
        #expect(try all.map { sessionId in try record(sandbox, sessionId).visible } == [true, false, true])
    }

    @Test func hidingTheLeadKeepsAMembersHeldQuestion() throws {
        let sandbox = try worktreeWindow()
        try writeFocus(sandbox, "termie:review")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Notification", LeadGroupFocusHoldTests.review, extra: ["notification_type": "permission_prompt"])
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).held == true)
        try sandbox.run(["hide", "--focus-target", "termie:dev"])
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).held == true)
    }

    @Test func aDeadMembersPaneHoldsNothing() throws {
        let sandbox = try worktreeWindow()
        var dead = try #require(sandbox.record(LeadGroupFocusHoldTests.test))
        dead["pid"] = 999_999
        try sandbox.writeRecord(dead)
        try writeFocus(sandbox, "termie:test")
        try hook(sandbox, "UserPromptSubmit", LeadGroupFocusHoldTests.review)
        try hook(sandbox, "Stop", LeadGroupFocusHoldTests.review)
        #expect(try record(sandbox, LeadGroupFocusHoldTests.review).visible)
    }

    @Test func capabilitiesNameTheHold() throws {
        let words = try Sandbox().run(["capabilities"]).standardOutput.split(separator: "\n").map { line in String(line) }
        #expect(words.contains("release-grace"))
        #expect(words.contains("focus-hold"))
        #expect(words.contains("lead-focus-hold"))
        #expect(words.contains("group-mode-lead"))
        #expect(words.contains("disambiguator"))
    }
}
