import Darwin
import Foundation

package struct FileResidency {
    private static let simulatedPathSeparator: Character = ":"
    private static let datalessFlag = UInt32(SF_DATALESS)

    private let datalessCheck: (URL) -> Bool
    private let downloadRequest: (URL) -> Void

    package init(isDataless: @escaping (URL) -> Bool, requestDownload: @escaping (URL) -> Void = { _ in }) {
        datalessCheck = isDataless
        downloadRequest = requestDownload
    }

    package static let system = FileResidency(
        simulatedDatalessPaths: ProcessInfo.processInfo.environment[EnvironmentVariableName.simulatedDatalessPaths]
    )

    init(simulatedDatalessPaths: String?) {
        let simulatedPaths = Set(
            (simulatedDatalessPaths ?? "")
                .split(separator: FileResidency.simulatedPathSeparator)
                .map { path in FileResidency.normalizedPath(URL(fileURLWithPath: String(path))) }
        )
        self.init(
            isDataless: { fileURL in
                (!simulatedPaths.isEmpty && simulatedPaths.contains(FileResidency.normalizedPath(fileURL)))
                    || FileResidency.hasDatalessFlag(fileURL)
            },
            requestDownload: { fileURL in
                try? FileManager.default.startDownloadingUbiquitousItem(at: fileURL)
            }
        )
    }

    package func isDataless(_ fileURL: URL) -> Bool {
        datalessCheck(fileURL)
    }

    package func requestDownload(_ fileURLs: [URL]) {
        for fileURL in fileURLs {
            downloadRequest(fileURL)
        }
    }

    package static func hasDatalessFlag(_ fileURL: URL) -> Bool {
        var status = stat()
        guard lstat(fileURL.path, &status) == 0 else { return false }
        return status.st_flags & datalessFlag != 0
    }

    private static func normalizedPath(_ fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }
}
