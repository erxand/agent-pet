import Foundation

package struct ClaudeSessionRecord: Codable {
    package static let busyStatus = "busy"
    private static let millisecondsPerSecond: Double = 1000

    package let pid: Int32
    package let sessionId: String
    package let cwd: String?
    package let name: String?
    package let tmux: String?
    package var status: String? = nil
    package var statusUpdatedAt: Double? = nil

    package func wentBusy(since moment: TimeInterval) -> Bool {
        guard status == ClaudeSessionRecord.busyStatus, let statusUpdatedAt else { return false }
        return statusUpdatedAt / ClaudeSessionRecord.millisecondsPerSecond >= moment
    }
}

extension ClaudeSessionRecord {
    private enum CodingKeys: String, CodingKey {
        case pid
        case sessionId
        case cwd
        case name
        case tmux
        case status
        case statusUpdatedAt
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pid = try container.decode(Int32.self, forKey: .pid)
        sessionId = try container.decode(String.self, forKey: .sessionId)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        tmux = try container.decodeIfPresent(String.self, forKey: .tmux)
        status = try? container.decodeIfPresent(String.self, forKey: .status)
        statusUpdatedAt = try? container.decodeIfPresent(Double.self, forKey: .statusUpdatedAt)
    }
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
