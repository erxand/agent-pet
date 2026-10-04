import Foundation
import Testing
@testable import AgentPetCore

@Suite("a group is ready only when every member is done")
struct GroupReadyRuleTests {
    private func member(
        _ sessionId: String,
        group: String? = "ticket",
        visible: Bool = false,
        mood: PetMood = .ready,
        busy: Bool? = nil,
        subagents: [String] = [],
        updatedAt: Double,
        enrolledAt: Double? = nil
    ) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: sessionId)
        session.group = group
        session.visible = visible
        session.mood = mood
        session.busy = busy
        session.activeSubagents = subagents.map { agentId in TrackedSubagent(id: agentId, startedAt: 1) }
        session.updatedAt = updatedAt
        session.enrolledAt = enrolledAt ?? updatedAt
        session.pid = getpid()
        return session
    }

    private func plan(_ records: [PetSession]) -> [PetDisplayItem] {
        PetDisplayPlanner(grouping: SharedKeyGrouping()).displayItems(records: records, claudeSessions: [:])
    }

    @Test func readyStaysHiddenWhileAnotherMemberWorks() {
        let finished = member("dev-1111", visible: true, updatedAt: 20, enrolledAt: 1)
        let working = member("review-2222", busy: true, updatedAt: 10, enrolledAt: 2)
        #expect(plan([finished, working]).isEmpty)
    }

    @Test func readyShowsOnceEveryMemberIsDone() {
        let finished = member("dev-1111", visible: true, updatedAt: 20, enrolledAt: 1)
        let alsoFinished = member("review-2222", visible: true, updatedAt: 30, enrolledAt: 2)
        let item = plan([finished, alsoFinished]).first
        #expect(item?.mood == .ready)
        #expect(item?.focusRequest.sessionId == "review-2222")

        let idle = member("review-2222", updatedAt: 30, enrolledAt: 2)
        #expect(plan([finished, idle]).first?.focusRequest.sessionId == "dev-1111")
    }

    @Test func needsInputShowsWhileOthersWorkAndNamesThatMember() {
        let heldReady = member("dev-1111", visible: true, updatedAt: 50, enrolledAt: 1)
        var asking = member("review-2222", visible: true, mood: .needsInput, busy: true, updatedAt: 20, enrolledAt: 2)
        asking.label = "reviewer"
        let working = member("qa-3333", busy: true, updatedAt: 60, enrolledAt: 3)
        let item = plan([heldReady, asking, working]).first
        #expect(item?.mood == .needsInput)
        #expect(item?.bubbleCaption == "reviewer")
        #expect(item?.focusRequest.sessionId == "review-2222")
        #expect(item?.session.sessionId == "dev-1111")
    }

    @Test func aDismissedMemberCountsAsDone() {
        let dismissed = member("dev-1111", visible: false, updatedAt: 20, enrolledAt: 1)
        let finished = member("review-2222", visible: true, updatedAt: 30, enrolledAt: 2)
        #expect(plan([dismissed, finished]).first?.mood == .ready)

        let everyoneDismissed = member("review-2222", visible: false, updatedAt: 30, enrolledAt: 2)
        #expect(plan([dismissed, everyoneDismissed]).isEmpty)
    }

    @Test func subagentsOfAnyMemberKeepReadyHidden() {
        let finished = member("dev-1111", visible: true, updatedAt: 20, enrolledAt: 1)
        let delegating = member("review-2222", subagents: ["agent-one"], updatedAt: 10, enrolledAt: 2)
        #expect(plan([finished, delegating]).isEmpty)

        let finishedWithSubagents = member("dev-1111", visible: true, subagents: ["agent-two"], updatedAt: 20, enrolledAt: 1)
        let quiet = member("review-2222", updatedAt: 10, enrolledAt: 2)
        #expect(plan([finishedWithSubagents, quiet]).isEmpty)
    }

    @Test func aDeadMemberDoesNotHoldTheGroup() {
        let finished = member("dev-1111", visible: true, updatedAt: 20, enrolledAt: 1)
        var deadWorker = member("review-2222", busy: true, updatedAt: 10, enrolledAt: 2)
        deadWorker.pid = 999_999
        #expect(plan([finished, deadWorker]).first?.mood == .ready)
    }

    @Test func recordsWrittenBeforeBusyExistedDecodeAsNotBusy() throws {
        let legacy = """
        {"sessionId":"old-1111","enabled":true,"visible":true,"mood":"ready","agent":"claude-code",\
        "group":"ticket","activeSubagents":[],"transcriptScanOffset":0,"updatedAt":10}
        """
        let decoded = try JSONDecoder().decode(PetSession.self, from: Data(legacy.utf8))
        #expect(decoded.busy == nil)
        #expect(!decoded.isWorking)

        var live = decoded
        live.pid = getpid()
        let quiet = member("new-2222", updatedAt: 5, enrolledAt: 2)
        #expect(plan([live, quiet]).first?.mood == .ready)
    }

    @Test func aNotBusyRecordWritesNoBusyKey() throws {
        let data = try JSONEncoder().encode(PetSession.newlyEnrolled(sessionId: "fresh"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["busy"] == nil)
    }

    @Test func anUngroupedSessionShowsExactlyAsBefore() {
        let busyButVisible = member("solo-1111", group: nil, visible: true, busy: true, subagents: ["agent-one"], updatedAt: 10)
        #expect(plan([busyButVisible]).map { item in item.petKey } == ["solo-1111"])

        let working = member("solo-2222", group: nil, busy: true, updatedAt: 20)
        let shared = plan([busyButVisible, working])
        let perSession = PetDisplayPlanner(grouping: OnePetPerSessionGrouping())
            .displayItems(records: [busyButVisible, working], claudeSessions: [:])
        #expect(shared.map { item in item.petKey } == ["solo-1111"])
        #expect(shared.map { item in item.petKey } == perSession.map { item in item.petKey })
    }
}

@Suite("hooks keep a per-session busy flag")
struct BusyHookTests {
    private func busy(_ sandbox: Sandbox) -> Bool? {
        sandbox.record(RecordFixtures.sessionId)?["busy"] as? Bool
    }

    @Test func promptAndToolUseMarkBusyAndStopClearsIt() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        try sandbox.hook(RecordFixtures.hookPayload("UserPromptSubmit"))
        #expect(busy(sandbox) == true)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)

        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        #expect(busy(sandbox) == nil)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)

        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["tool_name": "Bash"]))
        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["tool_name": "Bash"]))
        #expect(busy(sandbox) == true)
    }

    @Test func aStopWithSubagentsLeftStaysBusy() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("SubagentStart", extra: ["agent_id": "agent-one"]))
        #expect(busy(sandbox) == true)

        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        #expect(busy(sandbox) == true)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)

        try sandbox.hook(RecordFixtures.hookPayload("SubagentStop", extra: ["agent_id": "agent-one"]))
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        #expect(busy(sandbox) == nil)
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == true)
    }

    @Test func dismissingClearsOnlyVisibility() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true, extra: ["busy": true]))
        try sandbox.run(["hide", "--session", RecordFixtures.sessionId])
        #expect(sandbox.record(RecordFixtures.sessionId)?["visible"] as? Bool == false)
        #expect(busy(sandbox) == true)

        try sandbox.writeRecord(RecordFixtures.enrolled(visible: true))
        try sandbox.run(["hide", "--session", RecordFixtures.sessionId])
        #expect(busy(sandbox) == nil)
    }
}
