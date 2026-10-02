import Foundation

struct SubagentCleanupOutcome {
    static let nothingRemoved = SubagentCleanupOutcome(
        completedSubagentIds: [],
        expiredSubagents: [],
        skippedTranscriptByteCount: TranscriptTail.noBytes
    )

    let completedSubagentIds: [String]
    let expiredSubagents: [TrackedSubagent]
    let skippedTranscriptByteCount: Int

    var removedAnything: Bool {
        !completedSubagentIds.isEmpty || !expiredSubagents.isEmpty
    }
}

private struct TranscriptScanResult {
    static let unavailable = TranscriptScanResult(completedTaskIds: [], skippedByteCount: TranscriptTail.noBytes)

    let completedTaskIds: Set<String>
    let skippedByteCount: Int
}

enum SubagentCleanup {
    private static let secondsPerHour: TimeInterval = 60 * 60
    private static let maximumSubagentAgeInHours: TimeInterval = 3
    static let maximumSubagentAge: TimeInterval = maximumSubagentAgeInHours * secondsPerHour

    static func apply(to record: inout PetSession?, now: TimeInterval) -> SubagentCleanupOutcome {
        guard var session = record else { return .nothingRemoved }
        let transcriptScan = scanTranscript(of: &session)
        let completedSubagentIds = removeSubagents(withIds: transcriptScan.completedTaskIds, from: &session)
        let expiredSubagents = removeExpiredSubagents(from: &session, now: now)
        record = session
        return SubagentCleanupOutcome(
            completedSubagentIds: completedSubagentIds,
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
            completedTaskIds: Set(TranscriptCompletionScanner.completedTaskIds(in: tail.bytes)),
            skippedByteCount: tail.skippedByteCount
        )
    }

    private static func consumedByteCount(of tail: TranscriptTail) -> Int {
        if let completeLineByteCount = TranscriptCompletionScanner.completeLineByteCount(in: tail.bytes) {
            return completeLineByteCount
        }
        return tail.wasTruncated ? tail.bytes.count : TranscriptTail.noBytes
    }

    private static func removeSubagents(withIds completedIds: Set<String>, from session: inout PetSession) -> [String] {
        let removedIds = session.activeSubagents
            .map { trackedSubagent in trackedSubagent.id }
            .filter { trackedId in completedIds.contains(trackedId) }
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
