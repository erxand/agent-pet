import Foundation

enum LogFileTruncation {
    private static let maximumSizeInBytes: UInt64 = 1_048_576

    static func truncateIfOversized(at fileURL: URL) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let sizeInBytes = attributes[.size] as? UInt64,
              sizeInBytes > maximumSizeInBytes,
              let logHandle = FileHandle(forWritingAtPath: fileURL.path) else {
            return
        }
        try? logHandle.truncate(atOffset: 0)
        try? logHandle.close()
    }
}
