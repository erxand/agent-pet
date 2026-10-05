import Foundation
import Testing
@testable import AgentPetCore

@Suite("pets that hold several sessions")
struct GroupingTests {
    private func member(
        _ sessionId: String,
        group: String? = nil,
        visible: Bool = false,
        mood: PetMood = .ready,
        updatedAt: Double,
        enrolledAt: Double? = nil,
        owner: Bool = false,
        pid: Int32? = getpid()
    ) -> PetSession {
        var session = PetSession.newlyEnrolled(sessionId: sessionId)
        session.group = group
        session.visible = visible
        session.mood = mood
        session.updatedAt = updatedAt
        session.enrolledAt = enrolledAt
        session.owner = owner ? true : nil
        session.pid = pid
        return session
    }

    private func plan(_ records: [PetSession], claudeSessions: [String: ClaudeSessionRecord] = [:], disambiguates: Bool = false) -> [PetDisplayItem] {
        PetDisplayPlanner(grouping: SharedKeyGrouping(), disambiguatesLabels: disambiguates)
            .displayItems(records: records, claudeSessions: claudeSessions)
    }

    @Test func aGroupIsVisibleWhenAnyLiveMemberWaits() {
        var owner = member("owner-1111", group: "dev", updatedAt: 10, enrolledAt: 1)
        owner.label = "Dev System"
        let quiet = plan([owner, member("helper-2222", group: "dev", updatedAt: 20, enrolledAt: 2)])
        #expect(quiet.isEmpty)

        let waiting = plan([owner, member("helper-2222", group: "dev", visible: true, updatedAt: 20, enrolledAt: 2)])
        #expect(waiting.count == 1)
        #expect(waiting.first?.petKey == "dev")
        #expect(waiting.first?.label == "Dev System")
        #expect(waiting.first?.session.sessionId == "owner-1111")
        #expect(waiting.first?.memberSessionIds.sorted() == ["helper-2222", "owner-1111"])
        #expect(waiting.first?.focusRequest.group == "dev")

        let deadWaiter = plan([owner, member("helper-2222", group: "dev", visible: true, updatedAt: 20, enrolledAt: 2, pid: 999_999)])
        #expect(deadWaiter.isEmpty)
    }

    @Test func needsInputBeatsBlockedBeatsReady() {
        let records = [
            member("a-aaaa", group: "g", visible: true, mood: .ready, updatedAt: 30, enrolledAt: 1),
            member("b-bbbb", group: "g", visible: true, mood: .needsInput, updatedAt: 10, enrolledAt: 2),
            member("c-cccc", group: "g", visible: true, mood: .blocked, updatedAt: 20, enrolledAt: 3)
        ]
        #expect(plan(records).first?.mood == .needsInput)
        #expect(plan(Array(records.prefix(1)) + [records[2]]).first?.mood == .blocked)
        #expect(plan(Array(records.prefix(1))).first?.mood == .ready)
    }

    @Test func clickFocusesTheMostRecentlyUpdatedWaitingMemberElseTheOwner() {
        let owner = member("owner-1111", group: "g", updatedAt: 50, enrolledAt: 1)
        var older = member("older-2222", group: "g", visible: true, updatedAt: 10, enrolledAt: 2)
        older.message = "older message"
        var newer = member("newer-3333", group: "g", visible: true, updatedAt: 40, enrolledAt: 3)
        newer.message = "newer message"
        newer.focusTarget = "pane-newer"
        let item = plan([owner, older, newer]).first
        #expect(item?.focusRequest.sessionId == "newer-3333")
        #expect(item?.focusRequest.focusTarget == "pane-newer")
        #expect(item?.message == "newer message")

        var waitingOwner = owner
        waitingOwner.visible = true
        let ownerOnly = plan([waitingOwner, member("other-4444", group: "g", updatedAt: 60, enrolledAt: 2)]).first
        #expect(ownerOnly?.focusRequest.sessionId == "owner-1111")
        #expect(PetGroup(key: "g", members: [owner]).focusMember?.sessionId == "owner-1111")
    }

    @Test func theOwnerIsTheFlaggedMemberElseTheFirstEnrolledLiveMember() {
        let first = member("first-1111", group: "g", visible: true, updatedAt: 90, enrolledAt: 5)
        let second = member("second-2222", group: "g", updatedAt: 10, enrolledAt: 6)
        #expect(plan([first, second]).first?.session.sessionId == "first-1111")

        let flagged = member("flagged-3333", group: "g", updatedAt: 5, enrolledAt: 9, owner: true)
        #expect(plan([first, second, flagged]).first?.session.sessionId == "flagged-3333")

        let deadFlagged = member("flagged-3333", group: "g", updatedAt: 5, enrolledAt: 9, owner: true, pid: 999_999)
        #expect(plan([first, second, deadFlagged]).first?.session.sessionId == "first-1111")

        let deadFirst = member("first-1111", group: "g", updatedAt: 90, enrolledAt: 5, pid: 999_999)
        let waitingSecond = member("second-2222", group: "g", visible: true, updatedAt: 10, enrolledAt: 6)
        #expect(plan([deadFirst, waitingSecond]).first?.session.sessionId == "second-2222")
    }

    @Test func theSpriteAndAccentComeFromTheOwner() {
        var owner = member("owner-1111", group: "g", updatedAt: 10, enrolledAt: 1, owner: true)
        owner.sprite = "golem"
        owner.accent = .green
        var helper = member("helper-2222", group: "g", visible: true, updatedAt: 20, enrolledAt: 2)
        helper.sprite = "nimbus"
        helper.accent = .blue
        let item = plan([owner, helper]).first
        #expect(item?.session.sprite == "golem")
        #expect(item?.session.resolvedAccent == .green)
    }

    @Test func theBubbleNamesTheWaitingMemberOnlyWhenTheGroupHasSeveral() {
        let owner = member("owner-1111", group: "g", updatedAt: 10, enrolledAt: 1)
        var labelled = member("helper-2222", group: "g", visible: true, updatedAt: 20, enrolledAt: 2)
        labelled.label = "reviewer"
        #expect(plan([owner, labelled]).first?.bubbleCaption == "reviewer")

        let unlabelled = member("helper-abcd", group: "g", visible: true, updatedAt: 20, enrolledAt: 2)
        #expect(plan([owner, unlabelled]).first?.bubbleCaption == "#abcd")

        let named = member("helper-abcd", group: "g", visible: true, updatedAt: 20, enrolledAt: 2)
        let claudeSessions = ["helper-abcd": ClaudeSessionRecord(pid: getpid(), sessionId: "helper-abcd", cwd: "/w/repo", name: "fix tests", tmux: nil)]
        #expect(plan([owner, named], claudeSessions: claudeSessions).first?.bubbleCaption == "fix tests")

        let alone = member("alone-1111", group: "solo", visible: true, updatedAt: 20, enrolledAt: 2)
        #expect(plan([alone]).first?.bubbleCaption == nil)
    }

    @Test func subagentTrackingStaysPerSession() {
        var owner = member("owner-1111", group: "g", visible: true, mood: .needsInput, updatedAt: 10, enrolledAt: 1)
        owner.activeSubagents = [TrackedSubagent(id: "agent-one", startedAt: 1)]
        let helper = member("helper-2222", group: "g", updatedAt: 20, enrolledAt: 2)
        let item = plan([owner, helper]).first
        #expect(item?.session.activeSubagents.map { tracked in tracked.id } == ["agent-one"])
        #expect(helper.activeSubagents.isEmpty)
    }

    @Test func ungroupedRecordsPlanExactlyAsOnePetPerSession() {
        var labelled = member("labelled", visible: true, mood: .needsInput, updatedAt: 30)
        labelled.label = "my label"
        labelled.message = "hello"
        let records = [
            labelled,
            member("first", visible: true, updatedAt: 10, pid: nil),
            member("hidden", updatedAt: 5),
            member("dead", visible: true, updatedAt: 7, pid: 999_999)
        ]
        let claudeSessions = [
            "first": ClaudeSessionRecord(pid: getpid(), sessionId: "first", cwd: "/work/repo", name: nil, tmux: "work:@1.%2")
        ]
        let shared = PetDisplayPlanner(grouping: SharedKeyGrouping()).displayItems(records: records, claudeSessions: claudeSessions)
        let perSession = PetDisplayPlanner(grouping: OnePetPerSessionGrouping()).displayItems(records: records, claudeSessions: claudeSessions)
        #expect(shared.map { item in item.petKey } == ["first", "labelled"])
        #expect(shared.map { item in item.petKey } == perSession.map { item in item.petKey })
        #expect(shared.map { item in item.label } == perSession.map { item in item.label })
        #expect(shared.map { item in item.focusRequest } == perSession.map { item in item.focusRequest })
        #expect(shared.map { item in item.mood } == [.ready, .needsInput])
        #expect(shared.map { item in item.message } == [nil, "hello"])
        #expect(shared.allSatisfy { item in item.bubbleCaption == nil && item.memberSessionIds == [item.petKey] })
    }

    @Test func duplicateLabelsGainTheLastFourOfTheirSessionIdWhenAsked() {
        var left = member("aaaa-1111", visible: true, updatedAt: 10)
        left.label = "repo"
        var right = member("bbbb-2222", visible: true, updatedAt: 20)
        right.label = "repo"
        var other = member("cccc-3333", visible: true, updatedAt: 30)
        other.label = "other"
        #expect(plan([left, right, other]).map { item in item.label } == ["repo", "repo", "other"])
        #expect(plan([left, right, other], disambiguates: true).map { item in item.label } == ["repo 1111", "repo 2222", "other"])

        var hiddenRight = right
        hiddenRight.visible = false
        #expect(plan([left, hiddenRight, other], disambiguates: true).map { item in item.label } == ["repo", "other"])

        var longLeft = left
        longLeft.label = String(repeating: "x", count: 40)
        var longRight = right
        longRight.label = String(repeating: "x", count: 30)
        let longLabels = plan([longLeft, longRight], disambiguates: true).map { item in item.label }
        #expect(longLabels.allSatisfy { label in label.count == PetLabel.displayCharacterLimit })
        #expect(longLabels.map { label in String(label.suffix(4)) } == ["1111", "2222"])
    }

    @Test func groupedPetsDisambiguateByTheirOwner() {
        var ownerA = member("owner-aaaa", group: "a", visible: true, updatedAt: 10, enrolledAt: 1)
        ownerA.label = "repo"
        var ownerB = member("owner-bbbb", group: "b", updatedAt: 20, enrolledAt: 1)
        ownerB.label = "repo"
        let waitingB = member("helper-cccc", group: "b", visible: true, updatedAt: 30, enrolledAt: 2)
        #expect(plan([ownerA, ownerB, waitingB], disambiguates: true).map { item in item.label } == ["repo aaaa", "repo bbbb"])
    }
}

@Suite("pixel nametag font")
struct PixelFontTests {
    @Test func rendersUppercaseDigitsAndCommonPunctuation() throws {
        let rows = try #require(PixelFont.rows(for: "Ab-1"))
        #expect(rows.count == PixelFont.glyphHeight)
        #expect(rows.allSatisfy { row in row.count == PixelFont.width(of: "Ab-1") })
        #expect(rows[0] == ".#." + "." + "##." + "." + "..." + "." + ".#.")
        #expect(PixelFont.canRender("NIST-1025 a1b2"))
    }

    @Test func refusesCharactersItHasNoGlyphFor() {
        #expect(PixelFont.rows(for: "caf\u{e9}") == nil)
        #expect(!PixelFont.canRender("\u{1F431}"))
        #expect(PixelFont.width(of: "") == 0)
    }
}
