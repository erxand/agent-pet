import Foundation

enum DaemonLogFile {
    static func truncateIfOversized() {
        LogFileTruncation.truncateIfOversized(at: PetPaths.daemonLogFile)
    }

    static func writeStartupLine(processIdentifier: Int32, parentProcessIdentifier: Int32) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "agent-pet daemon started pid \(processIdentifier)"
            + " parent \(parentProcessIdentifier) at \(timestamp)\n"
        FileHandle.standardError.write(Data(line.utf8))
    }
}
