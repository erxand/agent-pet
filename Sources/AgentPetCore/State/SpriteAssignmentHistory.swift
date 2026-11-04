import Foundation

package struct SpriteAssignmentHistory {
    package static let fileName = "sprite-history.json"
    package static let lockFileName = "sprite-history.lock"
    private static let temporaryFileExtension = "tmp"

    private let fileURL: URL
    private let lockFileURL: URL
    private let fileManager = FileManager.default

    package init(directory: URL = PetPaths.stateDirectory) {
        fileURL = directory.appendingPathComponent(SpriteAssignmentHistory.fileName, isDirectory: false)
        lockFileURL = directory.appendingPathComponent(SpriteAssignmentHistory.lockFileName, isDirectory: false)
    }

    package func lastAssignedAtByPackName() -> [String: TimeInterval] {
        guard let payload = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: TimeInterval].self, from: payload) else {
            return [:]
        }
        return decoded.filter { entry in entry.value.isFinite }
    }

    package func recordAssignment(of packName: String, at assignedAt: Date, installedPackNames: [String]) {
        guard let lock = PetRecordLock(lockFileURL: lockFileURL) else { return }
        lock.acquireExclusively()
        defer { lock.release() }
        let installed = Set(installedPackNames)
        var history = lastAssignedAtByPackName().filter { entry in installed.contains(entry.key) }
        history[packName] = assignedAt.timeIntervalSince1970
        write(history)
    }

    private func write(_ history: [String: TimeInterval]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let payload = try? encoder.encode(history) else { return }
        let temporaryURL = fileURL.appendingPathExtension(SpriteAssignmentHistory.temporaryFileExtension)
        do {
            try payload.write(to: temporaryURL)
        } catch {
            return
        }
        if rename(temporaryURL.path, fileURL.path) != 0 {
            try? fileManager.removeItem(at: temporaryURL)
        }
    }
}
