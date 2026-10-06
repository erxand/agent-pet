import CoreServices
import Foundation

package final class DirectoryChangeMonitor {
    package static let defaultLatencyInSeconds: TimeInterval = 0.05

    private let latencyInSeconds: TimeInterval
    private let queue = DispatchQueue(label: "agent-pet.directory-changes")
    private let lock = NSLock()
    private var changeReported = false
    private var stream: FSEventStreamRef?
    private(set) package var watchedPaths: [String] = []

    package init(latencyInSeconds: TimeInterval = DirectoryChangeMonitor.defaultLatencyInSeconds) {
        self.latencyInSeconds = latencyInSeconds
    }

    deinit {
        stopStream()
    }

    package var isWatching: Bool { stream != nil }

    package func watch(directories: [URL]) {
        let paths = Array(Set(directories.map { directory in directory.standardizedFileURL.path })).sorted()
        guard paths != watchedPaths || (stream == nil && !paths.isEmpty) else { return }
        stopStream()
        watchedPaths = paths
        guard !paths.isEmpty else { return }
        startStream(paths: paths)
    }

    package func consumeChange() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let reported = changeReported
        changeReported = false
        return reported
    }

    fileprivate func noteChange() {
        lock.lock()
        changeReported = true
        lock.unlock()
    }

    private func startStream(paths: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagWatchRoot
        )
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            directoryChangeCallback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latencyInSeconds,
            flags
        ) else { return }
        FSEventStreamSetDispatchQueue(created, queue)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return
        }
        stream = created
    }

    private func stopStream() {
        guard let running = stream else { return }
        FSEventStreamStop(running)
        FSEventStreamInvalidate(running)
        FSEventStreamRelease(running)
        stream = nil
    }
}

private func directoryChangeCallback(
    streamReference: ConstFSEventStreamRef,
    clientInfo: UnsafeMutableRawPointer?,
    eventCount: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIdentifiers: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientInfo, eventCount > 0 else { return }
    Unmanaged<DirectoryChangeMonitor>.fromOpaque(clientInfo).takeUnretainedValue().noteChange()
}

package struct RescanGate {
    package static let defaultFallbackIntervalInSeconds: TimeInterval = 5

    package let fallbackIntervalInSeconds: TimeInterval
    private var lastRescanAt: TimeInterval?

    package init(fallbackIntervalInSeconds: TimeInterval = RescanGate.defaultFallbackIntervalInSeconds) {
        self.fallbackIntervalInSeconds = fallbackIntervalInSeconds
    }

    package mutating func shouldRescan(changeReported: Bool, forced: Bool, now: TimeInterval) -> Bool {
        let due = lastRescanAt.map { lastRescan in now - lastRescan >= fallbackIntervalInSeconds } ?? true
        guard forced || changeReported || due else { return false }
        lastRescanAt = now
        return true
    }
}
