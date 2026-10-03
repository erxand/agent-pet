import Foundation

package struct PetSessionStore {
    private static let temporaryFileExtension = "tmp"
    private static let pathSeparator = "/"
    private static let pathSeparatorReplacement = "_"

    private let directory: URL
    private let fileManager = FileManager.default

    package init(directory: URL = PetPaths.sessionsDirectory) {
        self.directory = directory
    }

    package func list() -> [PetSession] {
        guard let entries = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return entries
            .filter { entryURL in entryURL.pathExtension == PetPaths.sessionRecordFileExtension }
            .compactMap { entryURL in decode(at: entryURL) }
    }

    package func hasRecord(sessionId: String) -> Bool {
        fileManager.fileExists(atPath: recordURL(for: sessionId).path)
    }

    package func load(sessionId: String) -> PetSession? {
        decode(at: recordURL(for: sessionId))
    }

    package func withLockedRecord<Outcome>(
        sessionId: String,
        transform: (inout PetSession?) -> Outcome
    ) -> Outcome {
        guard let lock = PetRecordLock(lockFileURL: lockURL(for: sessionId)) else {
            return applyTransform(sessionId: sessionId, transform: transform)
        }
        lock.acquireExclusively()
        defer { lock.release() }
        return applyTransform(sessionId: sessionId, transform: transform)
    }

    private func applyTransform<Outcome>(
        sessionId: String,
        transform: (inout PetSession?) -> Outcome
    ) -> Outcome {
        let existing = load(sessionId: sessionId)
        var updated = existing
        let outcome = transform(&updated)
        if let updated {
            if updated != existing { save(updated) }
        } else if existing != nil {
            delete(sessionId: sessionId)
        }
        return outcome
    }

    package func save(_ session: PetSession) {
        PetPaths.createStateDirectoriesIfNeeded()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let payload = try? encoder.encode(session) else { return }

        let temporaryURL = directory.appendingPathComponent(
            "\(fileStem(for: session.sessionId)).\(PetSessionStore.temporaryFileExtension)"
        )
        do {
            try payload.write(to: temporaryURL)
        } catch {
            return
        }

        let destinationURL = recordURL(for: session.sessionId)
        if rename(temporaryURL.path, destinationURL.path) != 0 {
            try? fileManager.removeItem(at: temporaryURL)
        }
    }

    package func delete(sessionId: String) {
        try? fileManager.removeItem(at: recordURL(for: sessionId))
        try? fileManager.removeItem(at: lockURL(for: sessionId))
    }

    private func decode(at fileURL: URL) -> PetSession? {
        guard let payload = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(PetSession.self, from: payload)
    }

    private func recordURL(for sessionId: String) -> URL {
        directory.appendingPathComponent(
            "\(fileStem(for: sessionId)).\(PetPaths.sessionRecordFileExtension)"
        )
    }

    private func lockURL(for sessionId: String) -> URL {
        directory.appendingPathComponent(
            "\(fileStem(for: sessionId)).\(PetPaths.sessionLockFileExtension)"
        )
    }

    private func fileStem(for sessionId: String) -> String {
        sessionId.replacingOccurrences(
            of: PetSessionStore.pathSeparator,
            with: PetSessionStore.pathSeparatorReplacement
        )
    }
}
