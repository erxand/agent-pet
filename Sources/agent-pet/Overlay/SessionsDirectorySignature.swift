import Foundation

struct SessionsDirectorySignature: Equatable {
    private struct FileMarker: Equatable {
        let fileName: String
        let modificationTimeInterval: Double
        let byteCount: Int
    }

    private let directoryModification: Date?
    private let fileMarkers: [FileMarker]

    static func current(directory: URL) -> SessionsDirectorySignature {
        let fileManager = FileManager.default
        let directoryAttributes = try? fileManager.attributesOfItem(atPath: directory.path)
        let directoryModification = directoryAttributes?[.modificationDate] as? Date

        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        ) else {
            return SessionsDirectorySignature(directoryModification: directoryModification, fileMarkers: [])
        }

        let markers = entries
            .filter { entryURL in entryURL.pathExtension == PetPaths.sessionRecordFileExtension }
            .map { entryURL in marker(for: entryURL) }
            .sorted { leftMarker, rightMarker in leftMarker.fileName < rightMarker.fileName }

        return SessionsDirectorySignature(directoryModification: directoryModification, fileMarkers: markers)
    }

    private static func marker(for entryURL: URL) -> FileMarker {
        let values = try? entryURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return FileMarker(
            fileName: entryURL.lastPathComponent,
            modificationTimeInterval: values?.contentModificationDate?.timeIntervalSince1970 ?? 0,
            byteCount: values?.fileSize ?? 0
        )
    }
}
