import Foundation

enum TranscriptCompletionScanner {
    static let statusSearchWindowByteCount = 2 * 1024
    static let maximumTaskIdByteCount = 64

    private static let taskIdOpeningTag = Data("<task-id>".utf8)
    private static let taskIdClosingTag = Data("</task-id>".utf8)
    private static let statusOpeningTag = Data("<status>".utf8)
    private static let lineFeedByte = UInt8(ascii: "\n")
    private static let taskIdCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))

    static func completedTaskIds(in bytes: Data) -> [String] {
        var completedIds: [String] = []
        var searchStart = bytes.startIndex
        while let openingRange = bytes.range(of: taskIdOpeningTag, in: searchStart..<bytes.endIndex) {
            searchStart = openingRange.upperBound
            guard let taskIdMatch = taskId(in: bytes, startingAt: openingRange.upperBound) else { continue }
            if hasStatus(in: bytes, after: taskIdMatch.closingTagEnd) {
                completedIds.append(taskIdMatch.taskId)
            }
            searchStart = taskIdMatch.closingTagEnd
        }
        return completedIds
    }

    static func completeLineByteCount(in bytes: Data) -> Int? {
        guard let lastLineFeedIndex = bytes.lastIndex(of: lineFeedByte) else { return nil }
        return bytes.distance(from: bytes.startIndex, to: lastLineFeedIndex) + 1
    }

    private static func taskId(in bytes: Data, startingAt idStart: Data.Index) -> (taskId: String, closingTagEnd: Data.Index)? {
        let searchEnd = min(bytes.endIndex, idStart + maximumTaskIdByteCount + taskIdClosingTag.count)
        guard let closingRange = bytes.range(of: taskIdClosingTag, in: idStart..<searchEnd) else { return nil }
        guard let candidate = String(data: bytes[idStart..<closingRange.lowerBound], encoding: .utf8),
              !candidate.isEmpty,
              candidate.unicodeScalars.allSatisfy({ scalar in taskIdCharacters.contains(scalar) }) else {
            return nil
        }
        return (candidate, closingRange.upperBound)
    }

    private static func hasStatus(in bytes: Data, after windowStart: Data.Index) -> Bool {
        let windowLimit = min(bytes.endIndex, windowStart + statusSearchWindowByteCount)
        let nextTaskIdStart = bytes.range(of: taskIdOpeningTag, in: windowStart..<windowLimit)?.lowerBound
        let windowEnd = nextTaskIdStart ?? windowLimit
        return bytes.range(of: statusOpeningTag, in: windowStart..<windowEnd) != nil
    }
}
