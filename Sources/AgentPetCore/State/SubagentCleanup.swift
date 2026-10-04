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
        skippedByteCount: TranscriptTail.noBytes
    )

    let finishedTaskIds: Set<String>
    let interimTaskIds: Set<String>
    let skippedByteCount: Int

    init(finishedTaskIds: Set<String>, interimTaskIds: Set<String>, skippedByteCount: Int) {
        self.finishedTaskIds = finishedTaskIds
        self.interimTaskIds = interimTaskIds
        self.skippedByteCount = skippedByteCount
    }

    init(events: [TranscriptCompletionEvent], skippedByteCount: Int) {
        var finishedTaskIds: Set<String> = []
        var interimTaskIds: Set<String> = []
        for event in events {
            switch event {
            case .finished(let agentId):
                finishedTaskIds.insert(agentId)
            case .interim(let agentId):
                interimTaskIds.insert(agentId)
            }
        }
        self.init(finishedTaskIds: finishedTaskIds, interimTaskIds: interimTaskIds, skippedByteCount: skippedByteCount)
    }
}

enum SubagentCleanup {
    private static let secondsPerHour: TimeInterval = 60 * 60
    private static let maximumSubagentAgeInHours: TimeInterval = 3
    static let maximumSubagentAge: TimeInterval = maximumSubagentAgeInHours * secondsPerHour

    static func apply(to record: inout PetSession?, now: TimeInterval) -> SubagentCleanupOutcome {
        guard var session = record else { return .nothingFound }
        let transcriptScan = scanTranscript(of: &session)
        let completedSubagentIds = removeSubagents(withIds: transcriptScan.finishedTaskIds, from: &session)
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
