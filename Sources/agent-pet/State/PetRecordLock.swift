import Foundation

struct PetRecordLock {
    private static let filePermissions: mode_t = 0o644

    private let fileDescriptor: Int32

    init?(lockFileURL: URL) {
        PetPaths.createStateDirectoriesIfNeeded()
        let openedDescriptor = open(lockFileURL.path, O_CREAT | O_RDWR, PetRecordLock.filePermissions)
        guard openedDescriptor >= 0 else { return nil }
        fileDescriptor = openedDescriptor
    }

    func acquireExclusively() {
        while flock(fileDescriptor, LOCK_EX) != 0 && errno == EINTR {
            continue
        }
    }

    func release() {
        flock(fileDescriptor, LOCK_UN)
        close(fileDescriptor)
    }
}
