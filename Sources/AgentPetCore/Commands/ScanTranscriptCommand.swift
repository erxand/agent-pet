import Foundation

enum ScanTranscriptCommand {
    private static let finishedKindName = "finished"
    private static let interimKindName = "interim"
    private static let fieldSeparator = " "

    static func run(flags: ParsedFlags) -> Int32 {
        guard let path = flags.value(for: .path) else {
            return CommandFeedback.reportMissingTranscriptPath()
        }
        do {
            let startOffset = try FlagParsing.byteOffset(in: flags)
            guard let bytes = readBytes(path: path, from: startOffset) else {
                return CommandFeedback.reportUnreadableTranscript(path)
            }
            for match in TranscriptCompletionScanner.completionMatches(in: bytes) {
                print(line(for: match, startOffset: startOffset))
            }
            return ExitCode.success
        } catch let failure as FlagParseFailure {
            return failure.report()
        } catch {
            return CommandFeedback.reportUsage()
        }
    }

    private static func readBytes(path: String, from startOffset: Int) -> Data? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(startOffset))
            return try handle.readToEnd() ?? Data()
        } catch {
            return nil
        }
    }

    private static func line(for match: TranscriptCompletionMatch, startOffset: Int) -> String {
        [
            String(startOffset + match.byteOffset),
            kindName(of: match.event),
            match.event.agentId
        ].joined(separator: fieldSeparator)
    }

    private static func kindName(of event: TranscriptCompletionEvent) -> String {
        switch event {
        case .finished:
            return finishedKindName
        case .interim:
            return interimKindName
        }
    }
}
