import Foundation

enum TranscriptCompletionEvent: Equatable {
    case finished(String)
    case interim(String)
    /// A named teammate went idle. It carries the teammate's name, not its agent id: the tracked id
    /// of a teammate is `a<name>-<16 hex>`, see `TeammateAgentId`.
    case teammateIdle(String)

    var agentId: String {
        switch self {
        case .finished(let agentId), .interim(let agentId), .teammateIdle(let agentId):
            return agentId
        }
    }
}

/// A named teammate's agent id is `a`, its name, `-`, then 16 hex digits (`afixer-7-d035f68f1e116378`).
enum TeammateAgentId {
    private static let prefix = "a"
    private static let separator = "-"
    private static let suffixLength = 16
    private static let hexDigits = CharacterSet(charactersIn: "0123456789abcdef")

    static func belongs(_ agentId: String, toTeammateNamed name: String) -> Bool {
        let namePrefix = prefix + name + separator
        guard agentId.hasPrefix(namePrefix) else { return false }
        let suffix = agentId.dropFirst(namePrefix.count)
        return suffix.count == suffixLength && suffix.unicodeScalars.allSatisfy { scalar in hexDigits.contains(scalar) }
    }
}

struct TranscriptCompletionMatch {
    let byteOffset: Int
    let event: TranscriptCompletionEvent
}

private enum TaskNotificationNote {
    case noLiveBackgroundChildren
    case backgroundWorkStillRunning
    case unrecognized
    case absent
}

private struct IdentifierMatch {
    let identifier: String
    let terminatorEnd: Data.Index
}

enum TranscriptCompletionScanner {
    static let statusSearchWindowByteCount = 2 * 1024
    static let handBackSearchWindowByteCount = 400
    static let maximumTaskIdByteCount = 64
    static let interimNoteMarker = "stopped with background work of its own still running"
    static let finalNoteMarker = "stops with no live background children of its own"
    static let handBackMarker = "[Subagent hand-back]"
    static let teammateIdleMarker = "idle_notification"
    static let teammateIdleSearchWindowByteCount = 160

    private static let taskIdOpeningTag = Data("<task-id>".utf8)
    private static let taskIdClosingTag = Data("</task-id>".utf8)
    private static let statusOpeningTag = Data("<status>".utf8)
    private static let noteOpeningTag = Data("<note>".utf8)
    private static let noteClosingTag = Data("</note>".utf8)
    private static let agentMessageSenderPrefix = Data("agent-message from=".utf8)
    private static let escapedQuote = Data("\\\"".utf8)
    private static let rawQuote = Data("\"".utf8)
    private static let interimNoteMarkerBytes = Data(interimNoteMarker.utf8)
    private static let finalNoteMarkerBytes = Data(finalNoteMarker.utf8)
    private static let handBackMarkerBytes = Data(handBackMarker.utf8)
    private static let teammateIdleMarkerBytes = Data(teammateIdleMarker.utf8)
    private static let teammateSenderKeys = [Data("from\\\":\\\"".utf8), Data("from\":\"".utf8)]
    private static let teammateSenderTerminators = [Data("\\\"".utf8), Data("\"".utf8)]
    private static let lineFeedByte = UInt8(ascii: "\n")
    private static let taskIdCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    static func completionMatches(in bytes: Data) -> [TranscriptCompletionMatch] {
        (taskNotificationMatches(in: bytes) + handBackMatches(in: bytes) + teammateIdleMatches(in: bytes))
            .sorted { earlierMatch, laterMatch in earlierMatch.byteOffset < laterMatch.byteOffset }
    }

    static func completeLineByteCount(in bytes: Data) -> Int? {
        guard let lastLineFeedIndex = bytes.lastIndex(of: lineFeedByte) else { return nil }
        return bytes.distance(from: bytes.startIndex, to: lastLineFeedIndex) + 1
    }

    private static func taskNotificationMatches(in bytes: Data) -> [TranscriptCompletionMatch] {
        var matches: [TranscriptCompletionMatch] = []
        var searchStart = bytes.startIndex
        while let openingRange = bytes.range(of: taskIdOpeningTag, in: searchStart..<bytes.endIndex) {
            searchStart = openingRange.upperBound
            guard let taskIdMatch = identifier(
                in: bytes,
                startingAt: openingRange.upperBound,
                terminator: taskIdClosingTag
            ) else { continue }
            searchStart = taskIdMatch.terminatorEnd
            let window = searchWindow(
                in: bytes,
                from: taskIdMatch.terminatorEnd,
                byteCount: statusSearchWindowByteCount,
                stoppingAt: taskIdOpeningTag
            )
            guard let statusRange = bytes.range(of: statusOpeningTag, in: window) else { continue }
            let note = notificationNote(in: bytes, within: statusRange.upperBound..<window.upperBound)
            matches.append(TranscriptCompletionMatch(
                byteOffset: byteOffset(of: openingRange.lowerBound, in: bytes),
                event: event(for: note, agentId: taskIdMatch.identifier)
            ))
        }
        return matches
    }

    private static func handBackMatches(in bytes: Data) -> [TranscriptCompletionMatch] {
        var matches: [TranscriptCompletionMatch] = []
        var searchStart = bytes.startIndex
        while let senderRange = bytes.range(of: agentMessageSenderPrefix, in: searchStart..<bytes.endIndex) {
            searchStart = senderRange.upperBound
            guard let quote = openingQuote(in: bytes, at: senderRange.upperBound),
                  let senderMatch = identifier(
                    in: bytes,
                    startingAt: senderRange.upperBound + quote.count,
                    terminator: quote
                  ) else { continue }
            searchStart = senderMatch.terminatorEnd
            let window = searchWindow(
                in: bytes,
                from: senderMatch.terminatorEnd,
                byteCount: handBackSearchWindowByteCount,
                stoppingAt: agentMessageSenderPrefix
            )
            guard bytes.range(of: handBackMarkerBytes, in: window) != nil else { continue }
            matches.append(TranscriptCompletionMatch(
                byteOffset: byteOffset(of: senderRange.lowerBound, in: bytes),
                event: .finished(senderMatch.identifier)
            ))
        }
        return matches
    }

    /// `{"type":"idle_notification","from":"NAME",...}`, JSON-escaped inside the transcript line
    /// (`\"from\":\"NAME\"`) or raw. A teammate whose turn failed (a usage limit) sends this and no
    /// `SubagentStop`, so it is the one completion signal that always arrives.
    private static func teammateIdleMatches(in bytes: Data) -> [TranscriptCompletionMatch] {
        var matches: [TranscriptCompletionMatch] = []
        var searchStart = bytes.startIndex
        while let markerRange = bytes.range(of: teammateIdleMarkerBytes, in: searchStart..<bytes.endIndex) {
            searchStart = markerRange.upperBound
            let windowEnd = min(bytes.endIndex, markerRange.upperBound + teammateIdleSearchWindowByteCount)
            for (senderKey, terminator) in zip(teammateSenderKeys, teammateSenderTerminators) {
                guard let keyRange = bytes.range(of: senderKey, in: markerRange.upperBound..<windowEnd),
                      let senderMatch = identifier(in: bytes, startingAt: keyRange.upperBound, terminator: terminator) else {
                    continue
                }
                matches.append(TranscriptCompletionMatch(
                    byteOffset: byteOffset(of: markerRange.lowerBound, in: bytes),
                    event: .teammateIdle(senderMatch.identifier)
                ))
                break
            }
        }
        return matches
    }

    private static func openingQuote(in bytes: Data, at index: Data.Index) -> Data? {
        let remainder = bytes[index..<bytes.endIndex]
        if remainder.starts(with: escapedQuote) { return escapedQuote }
        if remainder.starts(with: rawQuote) { return rawQuote }
        return nil
    }

    private static func identifier(
        in bytes: Data,
        startingAt identifierStart: Data.Index,
        terminator: Data
    ) -> IdentifierMatch? {
        guard identifierStart <= bytes.endIndex else { return nil }
        let searchEnd = min(bytes.endIndex, identifierStart + maximumTaskIdByteCount + terminator.count)
        guard let terminatorRange = bytes.range(of: terminator, in: identifierStart..<searchEnd) else { return nil }
        guard let candidate = String(data: bytes[identifierStart..<terminatorRange.lowerBound], encoding: .utf8),
              !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({ scalar in taskIdCharacters.contains(scalar) }) else {
            return nil
        }
        return IdentifierMatch(identifier: candidate, terminatorEnd: terminatorRange.upperBound)
    }

    private static func searchWindow(
        in bytes: Data,
        from windowStart: Data.Index,
        byteCount: Int,
        stoppingAt boundary: Data
    ) -> Range<Data.Index> {
        let windowLimit = min(bytes.endIndex, windowStart + byteCount)
        let boundaryStart = bytes.range(of: boundary, in: windowStart..<windowLimit)?.lowerBound
        return windowStart..<(boundaryStart ?? windowLimit)
    }

    private static func notificationNote(in bytes: Data, within range: Range<Data.Index>) -> TaskNotificationNote {
        guard let noteOpeningRange = bytes.range(of: noteOpeningTag, in: range) else { return .absent }
        let noteEnd = bytes.range(of: noteClosingTag, in: noteOpeningRange.upperBound..<range.upperBound)?.lowerBound
            ?? range.upperBound
        let noteText = noteOpeningRange.upperBound..<noteEnd
        if bytes.range(of: interimNoteMarkerBytes, in: noteText) != nil { return .backgroundWorkStillRunning }
        if bytes.range(of: finalNoteMarkerBytes, in: noteText) != nil { return .noLiveBackgroundChildren }
        return .unrecognized
    }

    private static func event(for note: TaskNotificationNote, agentId: String) -> TranscriptCompletionEvent {
        switch note {
        case .backgroundWorkStillRunning:
            return .interim(agentId)
        case .noLiveBackgroundChildren, .unrecognized, .absent:
            return .finished(agentId)
        }
    }

    private static func byteOffset(of index: Data.Index, in bytes: Data) -> Int {
        bytes.distance(from: bytes.startIndex, to: index)
    }
}
