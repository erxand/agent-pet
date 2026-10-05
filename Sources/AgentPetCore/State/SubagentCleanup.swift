import Foundation

struct SubagentCleanupOutcome {
    static let nothingFound = SubagentCleanupOutcome(
        completedSubagentIds: [],
        interimSubagentIds: [],
        expiredSubagents: [],
        skippedTranscriptByteCount: TranscriptTail.noBytes
    )

    let completedSubagentIds: [String]
    let interimSubagentIds: [String]
    let expiredSubagents: [TrackedSubagent]
    let skippedTranscriptByteCount: Int

    var foundAnything: Bool {
        !completedSubagentIds.isEmpty || !interimSubagentIds.isEmpty || !expiredSubagents.isEmpty
    }
}

private struct TranscriptScanResult {
    static let unavailable = TranscriptScanResult(
        finishedTaskIds: [],
        interimTaskIds: [],
        idleTeammates: [:],
        skippedByteCount: TranscriptTail.noBytes
    )

    let finishedTaskIds: Set<String>
    let interimTaskIds: Set<String>
    /// Each idle teammate's name and when it last went idle; nil when a notification carried no time.
    let idleTeammates: [String: TimeInterval?]
    let skippedByteCount: Int

    init(finishedTaskIds: Set<String>, interimTaskIds: Set<String>, idleTeammates: [String: TimeInterval?], skippedByteCount: Int) {
        self.finishedTaskIds = finishedTaskIds
        self.interimTaskIds = interimTaskIds
        self.idleTeammates = idleTeammates
        self.skippedByteCount = skippedByteCount
    }

    init(events: [TranscriptCompletionEvent], skippedByteCount: Int) {
        var finishedTaskIds: Set<String> = []
        var interimTaskIds: Set<String> = []
        var idleTeammates: [String: TimeInterval?] = [:]
        for event in events {
            switch event {
            case .finished(let agentId):
                finishedTaskIds.insert(agentId)
            case .interim(let agentId):
                interimTaskIds.insert(agentId)
            case .teammateIdle(let name, let idleAt):
                idleTeammates[name] = TranscriptScanResult.later(idleTeammates[name], idleAt)
            }
        }
        self.init(
            finishedTaskIds: finishedTaskIds,
            interimTaskIds: interimTaskIds,
            idleTeammates: idleTeammates,
            skippedByteCount: skippedByteCount
        )
    }

    /// An untimed notification outranks a timed one, since it may be the latest.
    private static func later(_ known: TimeInterval??, _ seen: TimeInterval?) -> TimeInterval? {
        guard let known else { return seen }
        guard let knownTime = known, let seenTime = seen else { return nil }
        return max(knownTime, seenTime)
    }

    /// A teammate is finished by an idle notification of its name sent after it started. An earlier
    /// teammate of the same name going idle says nothing about one spawned since.
    func finishedIds(among trackedSubagents: [TrackedSubagent]) -> Set<String> {
        var finished = finishedTaskIds
        for trackedSubagent in trackedSubagents {
            let wentIdle = idleTeammates.contains { name, idleAt in
                guard TeammateAgentId.belongs(trackedSubagent.id, toTeammateNamed: name) else { return false }
                guard let idleAt else { return true }
                return idleAt >= trackedSubagent.startedAt
            }
            if wentIdle { finished.insert(trackedSubagent.id) }
        }
        return finished
    }
}

enum SubagentCleanup {
    private static let secondsPerHour: TimeInterval = 60 * 60
    private static let maximumSubagentAgeInHours: TimeInterval = 3
    static let maximumSubagentAge: TimeInterval = maximumSubagentAgeInHours * secondsPerHour

    static func apply(to record: inout PetSession?, now: TimeInterval) -> SubagentCleanupOutcome {
        guard var session = record else { return .nothingFound }
        let transcriptScan = scanTranscript(of: &session)
        let finishedIds = transcriptScan.finishedIds(among: session.activeSubagents)
        let completedSubagentIds = removeSubagents(withIds: finishedIds, from: &session)
        let interimSubagentIds = trackedSubagentIds(in: session, matching: transcriptScan.interimTaskIds)
        let expiredSubagents = removeExpiredSubagents(from: &session, now: now)
        record = session
        return SubagentCleanupOutcome(
            completedSubagentIds: completedSubagentIds,
            interimSubagentIds: interimSubagentIds,
            expiredSubagents: expiredSubagents,
            skippedTranscriptByteCount: transcriptScan.skippedByteCount
        )
    }

    private static func scanTranscript(of session: inout PetSession) -> TranscriptScanResult {
        guard let transcriptPath = session.transcriptPath,
              let tail = TranscriptTailReader.readUnscannedTail(
                path: transcriptPath,
                scannedOffset: session.transcriptScanOffset
              ) else {
            return .unavailable
        }
        session.transcriptScanOffset = tail.readStartOffset + consumedByteCount(of: tail)
        return TranscriptScanResult(
            events: TranscriptCompletionScanner.completionMatches(in: tail.bytes).map { match in match.event },
            skippedByteCount: tail.skippedByteCount
        )
    }

    private static func consumedByteCount(of tail: TranscriptTail) -> Int {
        if let completeLineByteCount = TranscriptCompletionScanner.completeLineByteCount(in: tail.bytes) {
            return completeLineByteCount
        }
        return tail.wasTruncated ? tail.bytes.count : TranscriptTail.noBytes
    }

    private static func trackedSubagentIds(in session: PetSession, matching candidateIds: Set<String>) -> [String] {
        session.activeSubagents
            .map { trackedSubagent in trackedSubagent.id }
            .filter { trackedId in candidateIds.contains(trackedId) }
    }

    private static func removeSubagents(withIds completedIds: Set<String>, from session: inout PetSession) -> [String] {
        let removedIds = trackedSubagentIds(in: session, matching: completedIds)
        session.activeSubagents.removeAll { trackedSubagent in completedIds.contains(trackedSubagent.id) }
        return removedIds
    }

    private static func removeExpiredSubagents(from session: inout PetSession, now: TimeInterval) -> [TrackedSubagent] {
        let expired = session.activeSubagents.filter { trackedSubagent in
            isExpired(trackedSubagent, now: now)
        }
        session.activeSubagents.removeAll { trackedSubagent in
            isExpired(trackedSubagent, now: now)
        }
        return expired
    }

    private static func isExpired(_ trackedSubagent: TrackedSubagent, now: TimeInterval) -> Bool {
        now - trackedSubagent.startedAt > maximumSubagentAge
    }
}
