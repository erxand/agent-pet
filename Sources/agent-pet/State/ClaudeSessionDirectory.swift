import Foundation

struct ClaudeSessionRecord: Codable {
    let pid: Int32
    let sessionId: String
    let cwd: String?
    let name: String?
    let tmux: String?
}

struct ClaudeSessionDirectory {
    private let directory: URL
    private let fileManager = FileManager.default

    init(directory: URL = PetPaths.claudeSessionsDirectory) {
        self.directory = directory
    }

    func recordsBySessionId() -> [String: ClaudeSessionRecord] {
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

    func record(forSessionId sessionId: String) -> ClaudeSessionRecord? {
        recordsBySessionId()[sessionId]
    }
}
