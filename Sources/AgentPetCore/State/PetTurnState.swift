import Foundation

package struct PetRecordSnapshot {
    package let visible: Bool
    package let held: Bool
    package let activeSubagentCount: Int

    init(record: PetSession?) {
        visible = record?.visible ?? false
        held = record?.held == true
        activeSubagentCount = record?.activeSubagents.count ?? 0
    }
}

struct PetHookResult {
    let snapshot: PetRecordSnapshot
    let cleanup: SubagentCleanupOutcome

    init(record: PetSession?, cleanup: SubagentCleanupOutcome = .nothingFound) {
        snapshot = PetRecordSnapshot(record: record)
        self.cleanup = cleanup
    }

    init(snapshot: PetRecordSnapshot) {
        self.snapshot = snapshot
        cleanup = .nothingFound
    }
}

enum SubagentIdentity {
    case reported(String)
    case unreported(fingerprint: String?)
}

/// Why a session's record is ending, from the `reason` of a `SessionEnd` payload.
enum SessionEndReason: String {
    case clear
    case resume
    case logout
    case promptInputExit = "prompt_input_exit"
    case other

    /// The process goes on under a new session id, which the `SessionStart` that follows hands the pet to.
    var continuesInSameProcess: Bool {
        switch self {
        case .clear, .resume:
            return true
        case .logout, .promptInputExit, .other:
            return false
        }
    }
}

package enum PetTurnState {
    /// Shows the pet unconditionally: the `show` command, which a person or an integration asked for.
    @discardableResult
    static func show(sessionId: String, mood: PetMood?, message: String?) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markVisible(&record, mood: mood, message: message)
            return PetRecordSnapshot(record: record)
        }
    }

    /// Shows the pet for a hook, unless its pane is the one in front: then it is held back until the
    /// user leaves that pane (`release`), because he is already looking at it.
    @discardableResult
    static func showUnlessInFront(sessionId: String, mood: PetMood, message: String?) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markVisibleUnlessInFront(&record, mood: mood, message: message, focusedTarget: FocusedTarget.current())
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func showUnlessSubagentsActive(
        sessionId: String,
        mood: PetMood,
        message: String?
    ) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let cleanup = SubagentCleanup.apply(to: &record, now: Date().timeIntervalSince1970)
            if record?.activeSubagents.isEmpty == false {
                markHidden(&record)
            } else {
                markDone(&record)
                markVisibleUnlessInFront(
                    &record,
                    mood: mood,
                    message: message,
                    focusedTarget: FocusedTarget.current()
                )
            }
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    /// A prompt, or a tool call, means the session is working again. A tool call from a subagent
    /// (`keepsNeedsInput`) leaves a `needsInput` pet up: another subagent may still be waiting on
    /// a permission prompt, and nothing the first one does answers it.
    @discardableResult
    static func hideAndMarkWorking(sessionId: String, keepsNeedsInput: Bool = false) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markWorking(&record)
            if !(keepsNeedsInput && record?.visible == true && record?.mood == .needsInput) {
                markHidden(&record)
            }
            return PetRecordSnapshot(record: record)
        }
    }

    /// The session sat at its prompt long enough for Claude Code to say so: whatever turn it was in
    /// is over, even one an interrupt ended without a `Stop`. Never shows anything.
    @discardableResult
    static func markIdle(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markDone(&record)
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    package static func hide(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            markHidden(&record)
            return PetRecordSnapshot(record: record)
        }
    }

    /// The user left the pane a pet was held back for. It comes up after all when the session still
    /// wants him (enabled, not working, not already up) and, with a `grace`, when he left within
    /// that many seconds of the hold: staying longer counts as having seen it. Otherwise the hold
    /// is just dropped, so the pet stays down for the rest of that turn.
    @discardableResult
    static func release(sessionId: String, grace: TimeInterval? = nil) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record, session.held == true else { return PetRecordSnapshot(record: record) }
            let now = Date().timeIntervalSince1970
            let leftInTime = grace.map { seconds in now - (session.heldAt ?? 0) < seconds } ?? true
            session.held = nil
            session.heldAt = nil
            if leftInTime && session.enabled && !session.isWorking && !session.visible {
                session.visible = true
                session.waitingSince = session.waitingSince ?? now
                session.updatedAt = now
            }
            record = session
            return PetRecordSnapshot(record: record)
        }
    }

    @discardableResult
    static func remove(sessionId: String) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            record = nil
            return PetRecordSnapshot(record: record)
        }
    }

    /// `SessionEnd`: the record goes, except when the same Claude process carries on under a new
    /// session id (`/clear`, `/resume`). Then the pet dives and the record waits for the
    /// `SessionStart` that hands it over (`PetSessionHandover`).
    @discardableResult
    static func end(sessionId: String, reason: SessionEndReason?) -> PetRecordSnapshot {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            // Only a record that names its process can be handed over (`PetSessionHandover`), so a
            // record with no pid (the plain `/pet` flow) goes, as it always did.
            if reason?.continuesInSameProcess == true, record?.pid != nil {
                markDone(&record)
                markHidden(&record)
            } else {
                record = nil
            }
            return PetRecordSnapshot(record: record)
        }
    }

    static func snapshot(sessionId: String) -> PetRecordSnapshot {
        PetRecordSnapshot(record: PetSessionStore().load(sessionId: sessionId))
    }

    private static func markVisible(_ record: inout PetSession?, mood: PetMood?, message: String?) {
        guard var session = record, session.enabled else { return }
        let now = Date().timeIntervalSince1970
        session.visible = true
        session.held = nil
        session.heldAt = nil
        session.mood = mood ?? session.mood
        session.message = message
        session.waitingSince = now
        session.updatedAt = now
        record = session
    }

    private static func markVisibleUnlessInFront(
        _ record: inout PetSession?,
        mood: PetMood,
        message: String?,
        focusedTarget: String?
    ) {
        guard var session = record, session.enabled else { return }
        guard FocusedTarget.isInFront(session, focusedTarget: focusedTarget) else {
            markVisible(&record, mood: mood, message: message)
            return
        }
        let now = Date().timeIntervalSince1970
        session.visible = false
        if session.held != true { session.heldAt = now }
        session.held = true
        session.mood = mood
        session.message = message
        session.waitingSince = now
        session.updatedAt = now
        record = session
    }

    private static func markWorking(_ record: inout PetSession?) {
        guard var session = record, session.busy != true else { return }
        session.busy = true
        record = session
    }

    private static func markDone(_ record: inout PetSession?) {
        guard var session = record, session.busy != nil else { return }
        session.busy = nil
        record = session
    }

    private static func markHidden(_ record: inout PetSession?) {
        guard var session = record, session.visible || session.held != nil else { return }
        if session.visible {
            session.visible = false
            session.updatedAt = Date().timeIntervalSince1970
        }
        session.held = nil
        session.heldAt = nil
        session.waitingSince = nil
        record = session
    }
}

enum PetTranscriptTracking {
    static func recordTranscriptPath(sessionId: String, transcriptPath: String) {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            guard var session = record, session.transcriptPath != transcriptPath else { return }
            session.transcriptPath = transcriptPath
            session.transcriptScanOffset = PetSession.initialTranscriptScanOffset
            record = session
        }
    }
}

enum PetSubagentTracking {
    private static let unknownAgentIdPrefix = "unknown-"

    @discardableResult
    static func recordStartAndHide(sessionId: String, identity: SubagentIdentity) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let now = Date().timeIntervalSince1970
            let cleanup = SubagentCleanup.apply(to: &record, now: now)
            guard var session = record else { return PetHookResult(record: record, cleanup: cleanup) }
            session.busy = true
            guard HookEventDeduplication.claim(identity: identity, in: &session, now: now) else {
                session.visible = false
                session.held = nil
                session.heldAt = nil
                record = session
                return PetHookResult(record: record, cleanup: cleanup)
            }
            let agentId = startingAgentId(identity: identity, session: session)
            if let existingIndex = session.activeSubagents.firstIndex(where: { trackedSubagent in
                trackedSubagent.id == agentId
            }) {
                session.activeSubagents[existingIndex].startedAt = now
            } else {
                session.activeSubagents.append(TrackedSubagent(id: agentId, startedAt: now))
            }
            session.visible = false
            session.held = nil
            session.heldAt = nil
            session.updatedAt = now
            record = session
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    @discardableResult
    static func recordStop(sessionId: String, identity: SubagentIdentity) -> PetHookResult {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record in
            let now = Date().timeIntervalSince1970
            let cleanup = SubagentCleanup.apply(to: &record, now: now)
            if var session = record,
               HookEventDeduplication.claim(identity: identity, in: &session, now: now),
               let agentId = stoppingAgentId(identity: identity, session: session),
               isTracking(agentId, in: session) {
                session.activeSubagents.removeAll { trackedSubagent in trackedSubagent.id == agentId }
                session.updatedAt = now
                record = session
            }
            return PetHookResult(record: record, cleanup: cleanup)
        }
    }

    static func clear(sessionId: String) -> Int? {
        PetSessionStore().withLockedRecord(sessionId: sessionId) { record -> Int? in
            guard var session = record else { return nil }
            let droppedCount = session.activeSubagents.count
            guard !session.activeSubagents.isEmpty else { return droppedCount }
            session.activeSubagents = []
            session.updatedAt = Date().timeIntervalSince1970
            record = session
            return droppedCount
        }
    }

    private static func isTracking(_ agentId: String, in session: PetSession) -> Bool {
        session.activeSubagents.contains { trackedSubagent in trackedSubagent.id == agentId }
    }

    private static func startingAgentId(identity: SubagentIdentity, session: PetSession) -> String {
        switch identity {
        case .reported(let agentId):
            return agentId
        case .unreported:
            return nextUnknownAgentId(session: session)
        }
    }

    private static func stoppingAgentId(identity: SubagentIdentity, session: PetSession) -> String? {
        switch identity {
        case .reported(let agentId):
            return agentId
        case .unreported:
            return session.activeSubagents.last { trackedSubagent in
                trackedSubagent.id.hasPrefix(unknownAgentIdPrefix)
            }?.id
        }
    }

    private static func nextUnknownAgentId(session: PetSession) -> String {
        var candidateNumber = 1
        var candidateId = unknownAgentIdPrefix + String(candidateNumber)
        while isTracking(candidateId, in: session) {
            candidateNumber += 1
            candidateId = unknownAgentIdPrefix + String(candidateNumber)
        }
        return candidateId
    }
}
