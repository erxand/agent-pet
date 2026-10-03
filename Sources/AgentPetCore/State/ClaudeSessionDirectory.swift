import Foundation

package struct ClaudeSessionRecord: Codable {
    package let pid: Int32
    package let sessionId: String
    package let cwd: String?
    package let name: String?
    package let tmux: String?
}

package struct ClaudeSessionDirectory {
    private let directory: URL
    private let fileManager = FileManager.default

    package init(directory: URL = PetPaths.claudeSessionsDirectory) {
        self.directory = directory
    }

    package func recordsBySessionId() -> [String: ClaudeSessionRecord] {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return [:]
        }
        var recordsBySessionId: [String: ClaudeSessionRecord] = [:]
        for entryURL in entries where entryURL.pathExtension == PetPaths.sessionRecordFileExtension {
            guard let payload = try? Data(contentsOf: entryURL),
                  let record = try? JSONDecoder().decode(ClaudeSessionRecord.self, from: payload) else { continue }
            recordsBySessionId[record.sessionId] = record
        }
        return recordsBySessionId
    }

    package func record(forSessionId sessionId: String) -> ClaudeSessionRecord? {
        recordsBySessionId()[sessionId]
    }
}
