import Foundation

enum DaemonProcessIdentifierFile {
    static func read() -> Int32? {
        guard let contents = try? String(contentsOf: PetPaths.daemonProcessIdentifierFile, encoding: .utf8) else {
            return nil
        }
        return Int32(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    static func write(processIdentifier: Int32) {
        PetPaths.createStateDirectoriesIfNeeded()
        let contents = "\(processIdentifier)\n"
        try? Data(contents.utf8).write(to: PetPaths.daemonProcessIdentifierFile)
    }
}
