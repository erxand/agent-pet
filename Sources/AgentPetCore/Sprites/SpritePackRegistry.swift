import Foundation

package final class SpritePackRegistry {
    private var loader: SpritePackLoader
    private let fallbackSheet: SpriteSheet
    private let reportFailure: (String) -> Void

    private var sheetsByPackName: [String: SpriteSheet] = [:]
    private var packDirectoryStateByPackName: [String: PackDirectoryState] = [:]
    private var reportedDirectoryIssues: Set<String> = []

    private struct PackDirectoryState: Equatable {
        let path: String
        let modification: Date?
    }

    package init(
        loader: SpritePackLoader = SpritePackLoader(),
        fallbackSheet: SpriteSheet = SpriteSheet.claude8Bit,
        reportFailure: @escaping (String) -> Void = SpritePackRegistry.writeToStandardError
    ) {
        self.loader = loader
        self.fallbackSheet = fallbackSheet
        self.reportFailure = reportFailure
    }

    package func sheet(forPackNamed packName: String?) -> SpriteSheet {
        let resolvedName = packName ?? SpritePackLoader.defaultPackName
        return sheetsByPackName[resolvedName] ?? fallbackSheet
    }

    /// Rescans every pack folder and reloads the packs whose directory moved or changed. Pass a
    /// loader when the configuration changed, so new `spriteDirectories` take effect at once.
    package func reloadChangedPacks(using replacementLoader: SpritePackLoader? = nil) -> Bool {
        if let replacementLoader { loader = replacementLoader }
        reportNewDirectoryIssues()
        var anythingChanged = false
        var seenPackNames: Set<String> = []
        for (packName, packDirectory) in loader.packDirectoriesByName() {
            seenPackNames.insert(packName)
            let currentState = PackDirectoryState(
                path: packDirectory.standardizedFileURL.path,
                modification: SpritePackLoader.modification(of: packDirectory)
            )
            if packDirectoryStateByPackName[packName] == currentState { continue }
            packDirectoryStateByPackName[packName] = currentState
            applyOutcome(loader.load(packNamed: packName), packName: packName)
            anythingChanged = true
        }
        for knownPackName in Set(sheetsByPackName.keys).union(packDirectoryStateByPackName.keys)
        where !seenPackNames.contains(knownPackName) {
            if sheetsByPackName.removeValue(forKey: knownPackName) != nil { anythingChanged = true }
            packDirectoryStateByPackName.removeValue(forKey: knownPackName)
        }
        return anythingChanged
    }

    private func reportNewDirectoryIssues() {
        let currentIssues = loader.directoryIssues()
        for issue in currentIssues where !reportedDirectoryIssues.contains(issue) {
            reportFailure(issue)
        }
        reportedDirectoryIssues = Set(currentIssues)
    }

    private func applyOutcome(_ outcome: SpritePackLoader.LoadOutcome, packName: String) {
        switch outcome {
        case .loaded(let pack):
            sheetsByPackName[packName] = pack.sheet
            if let unknownAccentName = pack.unknownAccentName {
                reportFailure("agent-pet: sprite pack \(packName) accent \(unknownAccentName) is not an accent color, ignored")
            }
        case .failed(let reason):
            sheetsByPackName.removeValue(forKey: packName)
            reportFailure("agent-pet: sprite pack \(packName) not loaded, \(reason)")
        }
    }

    package static func writeToStandardError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
