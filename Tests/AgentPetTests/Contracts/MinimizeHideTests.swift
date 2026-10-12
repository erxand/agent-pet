import Foundation
import Testing
@testable import AgentPetCore

@Suite("a pet whose window is minimized stays down")
struct MinimizeHideTests {
    private static let session = "solo-aaaa-1111"
    private static let pane = "termie:12"
    private static let deadProcessIdentifier = 999_999

    private func enroll(_ sandbox: Sandbox, _ sessionId: String, pane: String, group: [String] = []) throws {
        try sandbox.run([
            "on", "--session", sessionId,
            "--focus-target", pane,
            "--pid", String(getpid()),
            "--no-color-sync"
        ] + group)
        Thread.sleep(forTimeInterval: 0.02)
    }

    private func hook(_ sandbox: Sandbox, _ event: String, _ sessionId: String, extra: [String: Any] = [:]) throws {
        try sandbox.hook(RecordFixtures.hookPayload(event, sessionId: sessionId, extra: extra))
    }

    private func turnOn(_ sandbox: Sandbox) throws {
        try Data(#"{"hideWhenWindowMinimized": true}"#.utf8).write(to: sandbox.stateDirectory.appendingPathComponent("config.json"))
    }

    private func writeMinimized(_ sandbox: Sandbox, _ panes: [String], pid: Int = Int(getpid())) throws {
        let windows: [[String: Any]] = panes.isEmpty ? [] : [["title": "✳ NIST-1025", "focusTargets": panes]]
        let payload: [String: Any] = ["pid": pid, "windows": windows]
        try JSONSerialization.data(withJSONObject: payload).write(to: sandbox.stateDirectory.appendingPathComponent("minimized.json"))
    }

    private func writeFocus(_ sandbox: Sandbox, _ target: String) throws {
        let payload: [String: Any] = ["focusTarget": target, "pid": Int(getpid())]
        try JSONSerialization.data(withJSONObject: payload).write(to: sandbox.stateDirectory.appendingPathComponent("focus.json"))
    }

    private func record(_ sandbox: Sandbox, _ sessionId: String = MinimizeHideTests.session) throws -> PetSession {
        try JSONDecoder().decode(PetSession.self, from: Data(contentsOf: sandbox.recordURL(sessionId)))
    }

    private func store(_ sandbox: Sandbox) -> PetSessionStore {
        PetSessionStore(directory: sandbox.sessionsDirectory)
    }

    private func minimizedSolo(_ sandbox: Sandbox, configured: Bool = true) throws {
        try enroll(sandbox, MinimizeHideTests.session, pane: MinimizeHideTests.pane)
        if configured { try turnOn(sandbox) }
        try writeMinimized(sandbox, [MinimizeHideTests.pane])
        try hook(sandbox, "UserPromptSubmit", MinimizeHideTests.session)
    }

    @Test func offTheFileChangesNothing() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox, configured: false)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        let solo = try record(sandbox)
        #expect(solo.visible)
        #expect(solo.heldByMinimize == nil)
        #expect(MinimizedWindows.current(configuration: .defaults, file: sandbox.stateDirectory.appendingPathComponent("minimized.json")) == .none)
    }

    @Test func aFinishIsHeldByMinimize() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session, extra: ["last_assistant_message": "done"])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == true)
        #expect(solo.held == nil)
        #expect(solo.mood == .ready)
        #expect(solo.message == "done")
        #expect(sandbox.hookLogLines().last?.contains("minimized=true") == true)
    }

    @Test func aQuestionIsHeldByMinimize() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Notification", MinimizeHideTests.session, extra: ["notification_type": "permission_prompt"])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == true)
        #expect(solo.mood == .needsInput)
    }

    @Test func theShowCommandIsHeldByMinimize() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try sandbox.run(["show", "--session", MinimizeHideTests.session, "--mood", "blocked"])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == true)
        #expect(solo.mood == .blocked)
    }

    @Test func aReleaseIntoAMinimizedWindowIsHeldByMinimize() throws {
        let sandbox = try Sandbox()
        try enroll(sandbox, MinimizeHideTests.session, pane: MinimizeHideTests.pane)
        try turnOn(sandbox)
        try writeFocus(sandbox, MinimizeHideTests.pane)
        try hook(sandbox, "UserPromptSubmit", MinimizeHideTests.session)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        #expect(try record(sandbox).held == true)
        try writeFocus(sandbox, "termie:elsewhere")
        try writeMinimized(sandbox, [MinimizeHideTests.pane])
        try sandbox.run(["release", "--focus-target", MinimizeHideTests.pane, "--grace", "3600"])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.held == nil)
        #expect(solo.heldByMinimize == true)
    }

    @Test func aReleaseLeavesTheMinimizeHoldAlone() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        try writeMinimized(sandbox, [])
        try sandbox.run(["release", "--focus-target", MinimizeHideTests.pane, "--grace", "0"])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == true)
    }

    @Test func aDeadWritersFileHoldsNothing() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try writeMinimized(sandbox, [MinimizeHideTests.pane], pid: MinimizeHideTests.deadProcessIdentifier)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        let solo = try record(sandbox)
        #expect(solo.visible)
        #expect(solo.heldByMinimize == nil)
    }

    @Test func anUnreadableFileHoldsNothing() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try Data("not json".utf8).write(to: sandbox.stateDirectory.appendingPathComponent("minimized.json"))
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        #expect(try record(sandbox).visible)
    }

    @Test func aPromptDropsTheMinimizeHold() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        try hook(sandbox, "UserPromptSubmit", MinimizeHideTests.session)
        #expect(try record(sandbox).heldByMinimize == nil)
    }

    @Test func aVisiblePetIsHeldWhenItsWindowIsMinimized() throws {
        let sandbox = try Sandbox()
        try enroll(sandbox, MinimizeHideTests.session, pane: MinimizeHideTests.pane)
        try hook(sandbox, "UserPromptSubmit", MinimizeHideTests.session)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        #expect(try record(sandbox).visible)
        let changes = MinimizeHold.apply(minimizedTargets: [MinimizeHideTests.pane], focusedTarget: nil, store: store(sandbox))
        #expect(changes.heldSessionIds == [MinimizeHideTests.session])
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == true)
    }

    @Test func restoringTheWindowBringsThePetUp() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        let waitingSince = try record(sandbox).waitingSince
        let changes = MinimizeHold.apply(minimizedTargets: [], focusedTarget: "termie:elsewhere", store: store(sandbox))
        #expect(changes.endedSessionIds == [MinimizeHideTests.session])
        let solo = try record(sandbox)
        #expect(solo.visible)
        #expect(solo.heldByMinimize == nil)
        #expect(solo.held == nil)
        #expect(solo.waitingSince == waitingSince)
    }

    @Test func restoringIntoTheFrontGetsTheInFrontHold() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        MinimizeHold.apply(minimizedTargets: [], focusedTarget: MinimizeHideTests.pane, store: store(sandbox))
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == nil)
        #expect(solo.held == true)
        #expect(solo.heldAt != nil)
    }

    @Test func restoringASessionBackAtWorkBringsNothingUp() throws {
        let sandbox = try Sandbox()
        try minimizedSolo(sandbox)
        try hook(sandbox, "Stop", MinimizeHideTests.session)
        try hook(sandbox, "SubagentStart", MinimizeHideTests.session, extra: ["agent_id": "a1"])
        var busy = try #require(sandbox.record(MinimizeHideTests.session))
        busy["heldByMinimize"] = true
        try sandbox.writeRecord(busy)
        MinimizeHold.apply(minimizedTargets: [], focusedTarget: nil, store: store(sandbox))
        let solo = try record(sandbox)
        #expect(!solo.visible)
        #expect(solo.heldByMinimize == nil)
        #expect(solo.held == nil)
    }

    @Test func aGroupPetGoesOnlyWhenEveryMemberItShowsForIsMinimized() throws {
        let sandbox = try Sandbox()
        let group = ["--group", "ticket:NIST-1025"]
        try enroll(sandbox, "dev-aaaa", pane: "termie:12", group: group)
        try enroll(sandbox, "review-bbbb", pane: "termie:13", group: group)
        try enroll(sandbox, "quiet-cccc", pane: "termie:14", group: group)
        for sessionId in ["dev-aaaa", "review-bbbb"] {
            try hook(sandbox, "Notification", sessionId, extra: ["notification_type": "permission_prompt"])
        }
        let members = ["dev-aaaa", "review-bbbb", "quiet-cccc"]
        let records = Dictionary(uniqueKeysWithValues: try members.map { sessionId in (sessionId, try record(sandbox, sessionId)) })
        #expect(!MinimizeHold.goesWithItsWindow(memberSessionIds: members, records: records, minimizedTargets: ["termie:12"]))
        #expect(MinimizeHold.goesWithItsWindow(memberSessionIds: members, records: records, minimizedTargets: ["termie:12", "termie:13"]))
        #expect(!MinimizeHold.goesWithItsWindow(memberSessionIds: ["quiet-cccc"], records: records, minimizedTargets: ["termie:14"]))

        MinimizeHold.apply(minimizedTargets: ["termie:12"], focusedTarget: nil, store: store(sandbox))
        #expect(try record(sandbox, "dev-aaaa").heldByMinimize == true)
        #expect(try record(sandbox, "review-bbbb").visible)
    }

    @Test func theFileNamesTheWindowHoldingATarget() throws {
        let sandbox = try Sandbox()
        try writeMinimized(sandbox, ["termie:12", "termie:13"])
        let minimized = MinimizedWindows.read(file: sandbox.stateDirectory.appendingPathComponent("minimized.json"))
        #expect(minimized.writerProcessIdentifier == getpid())
        #expect(minimized.window(holding: "termie:13")?.title == "✳ NIST-1025")
        #expect(minimized.window(holding: "termie:99") == nil)
        #expect(minimized.focusTargets == ["termie:12", "termie:13"])
    }

    @Test func theConfigKeyIsReadAndDefaultsOff() {
        #expect(!ConfigurationFile.parse(Data("{}".utf8)).hidesWhenWindowMinimized)
        #expect(ConfigurationFile.parse(Data(#"{"hideWhenWindowMinimized": true}"#.utf8)).hidesWhenWindowMinimized)
        #expect(!ConfigurationFile.parse(Data(#"{"hideWhenWindowMinimized": "yes"}"#.utf8)).hidesWhenWindowMinimized)
    }

    @Test func capabilitiesNameIt() throws {
        let words = try Sandbox().run(["capabilities"]).standardOutput.split(separator: "\n").map { line in String(line) }
        #expect(words.contains("minimize-hide"))
    }
}
