import Foundation

enum DaemonLogFile {
    private static let maximumSizeInBytes: UInt64 = 1_048_576

    static func truncateIfOversized() {
        let logPath = PetPaths.daemonLogFile.path
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: logPath),
              let sizeInBytes = attributes[.size] as? UInt64,
              sizeInBytes > maximumSizeInBytes,
              let logHandle = FileHandle(forWritingAtPath: logPath) else {
            return
        }
        try? logHandle.truncate(atOffset: 0)
        try? logHandle.close()
    }

    static func writeStartupLine(processIdentifier: Int32, parentProcessIdentifier: Int32) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "agent-pet daemon started pid \(processIdentifier)"
            + " parent \(parentProcessIdentifier) at \(timestamp)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
