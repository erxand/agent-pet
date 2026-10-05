import Foundation
import Testing
@testable import AgentPetCore

@Suite("a pet comes up only once its session has stayed waiting")
struct SettleTests {
    private static let settleSeconds: TimeInterval = 1
    private static let waitingSince: TimeInterval = 1_000
    private static let millisecondsPerSecond: Double = 1000

    private let planner = PetDisplayPlanner(
        grouping: SharedKeyGrouping(),
        settleSeconds: SettleTests.settleSeconds,
        holdsWhileBusy: true
    )

    private func waiting(
        _ sessionId: String = "solo-1111",
        mood: PetMood = .ready,
        waitingSince: TimeInterval? = SettleTests.waitingSince
    ) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: sessionId)
        session.visible = true
        session.mood = mood
        session.waitingSince = waitingSince
        session.updatedAt = waitingSince ?? SettleTests.waitingSince
        session.pid = getpid()
        return session
    }

    private func claudeSession(
        _ sessionId: String = "solo-1111",
        status: String,
        writtenAt: TimeInterval
    ) -> [String: ClaudeSessionRecord] {
        var record = ClaudeSessionRecord(pid: getpid(), sessionId: sessionId, cwd: nil, name: nil, tmux: nil)
        record.status = status
        record.statusUpdatedAt = writtenAt * SettleTests.millisecondsPerSecond
        return [sessionId: record]
    }

    private func plan(
        _ records: [PetSession],
        at elapsed: TimeInterval,
        claudeSessions: [String: ClaudeSessionRecord] = [:],
        shownPetKeys: Set<String> = []
    ) -> [PetDisplayItem] {
        planner.displayItems(
            records: records,
            claudeSessions: claudeSessions,
            now: SettleTests.waitingSince + elapsed,
            shownPetKeys: shownPetKeys
        )
    }

    @Test func aReadyPetWaitsOutTheSettleDelay() {
        let ready = waiting()
        #expect(plan([ready], at: 0).isEmpty)
        #expect(plan([ready], at: 0.9).isEmpty)
        #expect(plan([ready], at: 1).map { item in item.petKey } == ["solo-1111"])
    }

    @Test func aNeedsInputPetSettlesToo() {
        let asking = waiting(mood: .needsInput)
        #expect(plan([asking], at: 0.5).isEmpty)
        #expect(plan([asking], at: 1).first?.mood == .needsInput)
    }

    @Test func aPetAlreadyUpStaysUpWhenItsSessionShowsAgain() {
        let ready = waiting()
        #expect(plan([ready], at: 0.1, shownPetKeys: ["solo-1111"]).count == 1)
    }

    @Test func aRecordWithoutWaitingSinceShowsAtOnce() {
        let legacy = waiting(waitingSince: nil)
        #expect(plan([legacy], at: 0).count == 1)
    }

    @Test func aZeroDelayShowsAtOnce() {
        let immediate = PetDisplayPlanner(grouping: SharedKeyGrouping())
        #expect(immediate.displayItems(records: [waiting()], claudeSessions: [:], now: SettleTests.waitingSince).count == 1)
    }

    @Test func theDeadlineIsWhenTheEarliestSettlingPetIsDue() {
        let early = waiting("early-1111")
        let late = waiting("late-2222", waitingSince: SettleTests.waitingSince + 0.4)
        var hidden = waiting("hidden-3333")
        hidden.visible = false
        let records = [late, early, hidden]
        #expect(planner.nextSettleDeadline(records: records, now: SettleTests.waitingSince) == SettleTests.waitingSince + 1)
        #expect(planner.nextSettleDeadline(records: records, now: SettleTests.waitingSince + 1) == SettleTests.waitingSince + 1.4)
        #expect(planner.nextSettleDeadline(records: records, now: SettleTests.waitingSince + 1.4) == nil)
    }

    @Test func aBangCommandAfterTheStopKeepsTheReadyPetDown() {
        let ready = waiting()
        let wentBusy = claudeSession(status: ClaudeSessionRecord.busyStatus, writtenAt: SettleTests.waitingSince + 0.05)
        #expect(plan([ready], at: 30, claudeSessions: wentBusy).isEmpty)
        #expect(plan([ready], at: 30, claudeSessions: wentBusy, shownPetKeys: ["solo-1111"]).isEmpty)

        let idleAgain = claudeSession(status: "idle", writtenAt: SettleTests.waitingSince + 5)
        #expect(plan([ready], at: 30, claudeSessions: idleAgain).count == 1)
    }

    @Test func aBusyWrittenBeforeTheStopIsStale() {
        let ready = waiting()
        let staleBusy = claudeSession(status: ClaudeSessionRecord.busyStatus, writtenAt: SettleTests.waitingSince - 4)
        #expect(plan([ready], at: 1, claudeSessions: staleBusy).count == 1)
    }

    @Test func aBusySessionDoesNotHideItsPermissionPrompt() {
        let asking = waiting(mood: .needsInput)
        let busy = claudeSession(status: ClaudeSessionRecord.busyStatus, writtenAt: SettleTests.waitingSince + 0.5)
        #expect(plan([asking], at: 1, claudeSessions: busy).first?.mood == .needsInput)
    }

    @Test func aMemberBusyWithABangCommandHoldsItsGroupsReady() {
        var finished = waiting("dev-1111")
        finished.group = "ticket"
        var bang = waiting("review-2222")
        bang.group = "ticket"
        let wentBusy = claudeSession("review-2222", status: ClaudeSessionRecord.busyStatus, writtenAt: SettleTests.waitingSince + 0.2)
        #expect(plan([finished, bang], at: 5, claudeSessions: wentBusy).isEmpty)
        #expect(plan([finished, bang], at: 5).count == 1)
    }

    @Test func withNoConfigABusySessionDoesNotHoldItsPetDown() {
        let upstream = AgentPetContracts(configuration: .defaults, focusCompletion: .waits).displayPlanner
        let wentBusy = claudeSession(status: ClaudeSessionRecord.busyStatus, writtenAt: SettleTests.waitingSince + 0.05)
        let items = upstream.displayItems(records: [waiting()], claudeSessions: wentBusy, now: SettleTests.waitingSince)
        #expect(items.count == 1)
        #expect(upstream.nextSettleDeadline(records: [waiting()], now: SettleTests.waitingSince) == nil)
    }

    @Test func claudeStatusFieldsDecodeAndABadOneLosesOnlyItself() throws {
        let written = #"{"pid":42,"sessionId":"s-1","status":"busy","statusUpdatedAt":1791141774090}"#
        let decoded = try JSONDecoder().decode(ClaudeSessionRecord.self, from: Data(written.utf8))
        #expect(decoded.wentBusy(since: 1_791_141_774.052))
        #expect(!decoded.wentBusy(since: 1_791_141_774.2))

        let odd = #"{"pid":42,"sessionId":"s-1","status":7,"statusUpdatedAt":"soon"}"#
        let lenient = try JSONDecoder().decode(ClaudeSessionRecord.self, from: Data(odd.utf8))
        #expect(lenient.sessionId == "s-1")
        #expect(!lenient.wentBusy(since: 0))
    }

    @Test func settleSecondsIsReadFromTheConfig() {
        #expect(AgentPetConfiguration.defaults.settleSeconds == 0)
        #expect(ConfigurationFile.parse(Data(#"{"settleSeconds":0.5}"#.utf8)).settleSeconds == 0.5)
        #expect(ConfigurationFile.parse(Data(#"{"settleSeconds":1}"#.utf8)).settleSeconds == 1)
        #expect(ConfigurationFile.parse(Data(#"{"settleSeconds":-2}"#.utf8)).settleSeconds == 0)
        #expect(ConfigurationFile.parse(Data(#"{"settleSeconds":"soon"}"#.utf8)).settleSeconds == 0)
    }

    @Test func holdWhileBusyIsOffUnlessTheConfigTurnsItOn() {
        #expect(!AgentPetConfiguration.defaults.holdsWhileBusy)
        #expect(ConfigurationFile.parse(Data(#"{"holdWhileBusy":true}"#.utf8)).holdsWhileBusy)
        #expect(!ConfigurationFile.parse(Data(#"{"holdWhileBusy":"yes"}"#.utf8)).holdsWhileBusy)
    }
}

@Suite("hooks stamp when a session starts waiting")
struct SettleHookTests {
    private func decodedRecord(_ sandbox: Sandbox) throws -> PetSession {
        let data = try Data(contentsOf: sandbox.recordURL(RecordFixtures.sessionId))
        return try JSONDecoder().decode(PetSession.self, from: data)
    }

    private func plan(_ record: PetSession, at moment: TimeInterval) -> [PetDisplayItem] {
        PetDisplayPlanner(grouping: SharedKeyGrouping(), settleSeconds: 1)
            .displayItems(records: [record], claudeSessions: [:], now: moment)
    }

    @Test func aStopFollowedQuicklyByAPromptNeverShowsThePet() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        let afterStop = try decodedRecord(sandbox)
        let waitingSince = try #require(afterStop.waitingSince)
        #expect(afterStop.visible)
        #expect(plan(afterStop, at: waitingSince + 0.2).isEmpty)

        try sandbox.hook(RecordFixtures.hookPayload("UserPromptSubmit"))
        let afterPrompt = try decodedRecord(sandbox)
        #expect(!afterPrompt.visible)
        #expect(afterPrompt.waitingSince == nil)
        #expect(plan(afterPrompt, at: waitingSince + 5).isEmpty)
    }

    @Test func aStopThatStaysShowsThePetAfterTheDelay() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("Stop"))
        let record = try decodedRecord(sandbox)
        let waitingSince = try #require(record.waitingSince)
        #expect(plan(record, at: waitingSince + 0.5).isEmpty)
        #expect(plan(record, at: waitingSince + 1).first?.mood == .ready)
    }

    @Test func aPermissionPromptStampsTheSameWay() throws {
        let sandbox = try Sandbox()
        try sandbox.writeRecord(RecordFixtures.enrolled())
        try sandbox.hook(RecordFixtures.hookPayload("Notification", extra: ["notification_type": "permission_prompt"]))
        let record = try decodedRecord(sandbox)
        let waitingSince = try #require(record.waitingSince)
        #expect(plan(record, at: waitingSince + 0.5).isEmpty)
        #expect(plan(record, at: waitingSince + 1).first?.mood == .needsInput)

        try sandbox.hook(RecordFixtures.hookPayload("PreToolUse", extra: ["tool_name": "Bash"]))
        #expect(try decodedRecord(sandbox).visible == false)
    }
}
