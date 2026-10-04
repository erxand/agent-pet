import Foundation
import Testing
@testable import AgentPetCore

@Suite("display planning and color sync")
struct DisplayAndColorTests {
    private func session(_ sessionId: String, visible: Bool = true, enabled: Bool = true, updatedAt: Double, pid: Int32? = getpid()) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: sessionId)
        session.visible = visible
        session.enabled = enabled
        session.updatedAt = updatedAt
        session.pid = pid
        return session
    }

    @Test func onlyEnabledVisibleLiveSessionsShowOldestFirstOnePetEach() {
        var labelled = session("labelled", updatedAt: 30)
        labelled.label = "my label"
        let records = [
            labelled,
            session("first", updatedAt: 10, pid: nil),
            session("hidden", visible: false, updatedAt: 5),
            session("disabled", enabled: false, updatedAt: 6),
            session("dead", updatedAt: 7, pid: 999_999)
        ]
        let claudeSessions = [
            "first": ClaudeSessionRecord(pid: getpid(), sessionId: "first", cwd: "/work/repo", name: nil, tmux: "work:@1.%2")
        ]
        let items = PetDisplayPlanner(grouping: OnePetPerSessionGrouping())
            .displayItems(records: records, claudeSessions: claudeSessions)

        #expect(items.map { item in item.petKey } == ["first", "labelled"])
        #expect(items.map { item in item.label } == ["repo", "my label"])
        #expect(items.first?.focusRequest.tmuxTarget?.rawValue == "work:@1.%2")
        #expect(items.first?.focusRequest.processIdentifier == getpid())
        #expect(items.first?.focusRequest.group == "first")
    }

    @Test func tmuxColorSyncTypesIntoClaudeCodePanesOnly() {
        let tmux = RecordingTmux()
        var claudeSession = PetSession.newlyEnrolled(sessionId: "color")
        claudeSession.tmuxTarget = "work:@3.%7"
        var piSession = claudeSession
        piSession.agent = .pi
        let untargeted = PetSession.newlyEnrolled(sessionId: "no-target")
        let colorSync = TmuxPromptBarColorSync(tmux: tmux)
        colorSync.applyAccent(.cyan, to: claudeSession)
        colorSync.applyAccent(.cyan, to: piSession)
        colorSync.applyAccent(.cyan, to: untargeted)
        colorSync.resetColor(of: claudeSession)

        #expect(tmux.calls == [
            ["send-keys", "-t", "work:@3.%7", "-l", "/color cyan"],
            ["send-keys", "-t", "work:@3.%7", "Enter"],
            ["send-keys", "-t", "work:@3.%7", "-l", "/color default"],
            ["send-keys", "-t", "work:@3.%7", "Enter"]
        ])
    }
}
