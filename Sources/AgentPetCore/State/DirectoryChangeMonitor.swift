import CoreServices
import Foundation

package struct DirectoryChange: Equatable {
    package let path: String
    package let requiresRescan: Bool

    package init(path: String, requiresRescan: Bool) {
        self.path = path
        self.requiresRescan = requiresRescan
    }
}

package final class DirectoryChangeMonitor {
    package static let defaultLatencyInSeconds: TimeInterval = 0.05

    private let latencyInSeconds: TimeInterval
    private let sink: DirectoryChangeSink
    private let queue = DispatchQueue(label: "agent-pet.directory-changes")
    private var stream: FSEventStreamRef?
    private(set) package var watchedPaths: [String] = []

    package init(latencyInSeconds: TimeInterval = DirectoryChangeMonitor.defaultLatencyInSeconds, recordsPaths: Bool = false) {
        self.latencyInSeconds = latencyInSeconds
        sink = DirectoryChangeSink(recordsPaths: recordsPaths)
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
        sink.consumeChange()
    }

    package func consumeChanges() -> [DirectoryChange] {
        sink.consumeChanges()
    }

    package func noteChange(_ noted: [DirectoryChange]) {
        sink.noteChange(noted)
    }

    package func runOnCallbackQueue(_ work: @escaping () -> Void) {
        queue.async(execute: work)
    }

    private func startStream(paths: [String]) {
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(sink).toOpaque(),
            retain: retainChangeSink,
            release: releaseChangeSink,
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

private final class DirectoryChangeSink {
    let recordsPaths: Bool
    private let lock = NSLock()
    private var changeReported = false
    private var changes: [DirectoryChange] = []

    init(recordsPaths: Bool) {
        self.recordsPaths = recordsPaths
    }

    func consumeChange() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let reported = changeReported
        changeReported = false
        return reported
    }

    func consumeChanges() -> [DirectoryChange] {
        lock.lock()
        defer { lock.unlock() }
        let consumed = changes
        changes = []
        return consumed
    }

    func noteChange(_ noted: [DirectoryChange]) {
        lock.lock()
        changeReported = true
        if recordsPaths { changes += noted }
        lock.unlock()
    }
}

private func retainChangeSink(_ info: UnsafeRawPointer?) -> UnsafeRawPointer? {
    guard let info else { return nil }
    _ = Unmanaged<DirectoryChangeSink>.fromOpaque(info).retain()
    return info
}

private func releaseChangeSink(_ info: UnsafeRawPointer?) {
    guard let info else { return }
    Unmanaged<DirectoryChangeSink>.fromOpaque(info).release()
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
    let sink = Unmanaged<DirectoryChangeSink>.fromOpaque(clientInfo).takeUnretainedValue()
    guard sink.recordsPaths else {
        sink.noteChange([])
        return
    }
    let pathPointers = eventPaths.assumingMemoryBound(to: UnsafePointer<CChar>.self)
    let rescanFlags = FSEventStreamEventFlags(
        kFSEventStreamEventFlagMustScanSubDirs | kFSEventStreamEventFlagUserDropped | kFSEventStreamEventFlagKernelDropped
    )
    sink.noteChange((0..<eventCount).map { index in
        DirectoryChange(path: String(cString: pathPointers[index]), requiresRescan: eventFlags[index] & rescanFlags != 0)
    })
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
