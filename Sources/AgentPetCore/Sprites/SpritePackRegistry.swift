import Foundation

package final class SpritePackRegistry {
    private var loader: SpritePackLoader
    private let fallbackSheet: SpriteSheet
    private let reportFailure: (String) -> Void

    private var sheetsByPackName: [String: SpriteSheet] = [:]
    private var accentInksByPackName: [String: AccentInks] = [:]
    private var ownAccentByPackName: [String: AccentColor] = [:]
    private var tintedSheets: [TintedSheetKey: SpriteSheet] = [:]
    private var packDirectoryStateByPackName: [String: PackDirectoryState] = [:]
    private var reportedDirectoryIssues: Set<String> = []
    private var undownloadedPackNames: Set<String> = []
    private var pendingPackDirectoryByName: [String: URL] = [:]
    private var requestedRootPaths: Set<String> = []

    private struct TintedSheetKey: Hashable {
        let packName: String
        let accent: AccentColor
    }

    package struct SessionSheet {
        package let sheet: SpriteSheet
        package let tint: AccentColor?
    }

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

    package func ownAccent(forPackNamed packName: String?) -> AccentColor? {
        ownAccentByPackName[packName ?? SpritePackLoader.defaultPackName]
    }

    package func sheet(forPackNamed packName: String?, chosenAccent: AccentColor?) -> SessionSheet {
        let resolvedName = packName ?? SpritePackLoader.defaultPackName
        let baseSheet = sheet(forPackNamed: resolvedName)
        guard let accentInks = accentInksByPackName[resolvedName],
              let tint = SpriteAccentTint.tint(chosenAccent: chosenAccent, accentInks: accentInks) else {
            return SessionSheet(sheet: baseSheet, tint: nil)
        }
        let key = TintedSheetKey(packName: resolvedName, accent: tint)
        if let cached = tintedSheets[key] { return SessionSheet(sheet: cached, tint: tint) }
        let tinted = SpriteAccentTint.tinted(baseSheet, inks: accentInks, accent: tint)
        tintedSheets[key] = tinted
        return SessionSheet(sheet: tinted, tint: tint)
    }

    package func reloadChangedPacks(using replacementLoader: SpritePackLoader? = nil) -> Bool {
        if let replacementLoader { loader = replacementLoader }
        let scan = loader.scan()
        reportNewDirectoryIssues(scan.issues)
        requestNewRootDownloads(scan.undownloadedRoots)
        let undownloadedRootPrefixes = scan.undownloadedRoots.map { rootURL in rootURL.standardizedFileURL.path + "/" }
        var anythingChanged = false
        var seenPackNames: Set<String> = []
        for (packName, packDirectory) in scan.directoryByPackName {
            seenPackNames.insert(packName)
            let currentState = PackDirectoryState(
                path: packDirectory.standardizedFileURL.path,
                modification: SpritePackLoader.modification(of: packDirectory)
            )
            if packDirectoryStateByPackName[packName] == currentState { continue }
            let outcome = loader.load(packDirectory: packDirectory)
            if case .notDownloaded(let undownloaded) = outcome {
                noteNotDownloaded(packName: packName, undownloaded: undownloaded)
                pendingPackDirectoryByName[packName] = packDirectory
                continue
            }
            undownloadedPackNames.remove(packName)
            pendingPackDirectoryByName.removeValue(forKey: packName)
            packDirectoryStateByPackName[packName] = currentState
            applyOutcome(outcome, packName: packName)
            anythingChanged = true
        }
        for knownPackName in Set(sheetsByPackName.keys).union(packDirectoryStateByPackName.keys)
        where !seenPackNames.contains(knownPackName) {
            let knownPath = packDirectoryStateByPackName[knownPackName]?.path ?? ""
            if undownloadedRootPrefixes.contains(where: { prefix in knownPath.hasPrefix(prefix) }) { continue }
            if sheetsByPackName.removeValue(forKey: knownPackName) != nil { anythingChanged = true }
            forgetTints(forPackNamed: knownPackName)
            packDirectoryStateByPackName.removeValue(forKey: knownPackName)
        }
        undownloadedPackNames.formIntersection(seenPackNames)
        pendingPackDirectoryByName = pendingPackDirectoryByName.filter { packName, _ in seenPackNames.contains(packName) }
        return anythingChanged
    }

    package var hasPendingDownloads: Bool {
        !pendingPackDirectoryByName.isEmpty || !requestedRootPaths.isEmpty
    }

    package func pendingDownloadBecameLocal() -> Bool {
        let rootBecameLocal = requestedRootPaths.contains { rootPath in
            !loader.residency.isDataless(URL(fileURLWithPath: rootPath, isDirectory: true))
        }
        guard !rootBecameLocal else { return true }
        return pendingPackDirectoryByName.values.contains { packDirectory in
            loader.undownloadedFiles(inPackDirectory: packDirectory).isEmpty
        }
    }

    private func noteNotDownloaded(packName: String, undownloaded: [URL]) {
        guard undownloadedPackNames.insert(packName).inserted else { return }
        reportFailure("agent-pet: sprite pack \(packName) is not downloaded yet, skipped until its files are local")
        loader.residency.requestDownload(undownloaded)
    }

    private func requestNewRootDownloads(_ undownloadedRoots: [URL]) {
        let currentPaths = Set(undownloadedRoots.map { rootURL in rootURL.standardizedFileURL.path })
        let newRoots = undownloadedRoots.filter { rootURL in !requestedRootPaths.contains(rootURL.standardizedFileURL.path) }
        loader.residency.requestDownload(newRoots)
        requestedRootPaths = currentPaths
    }

    private func reportNewDirectoryIssues(_ currentIssues: [String]) {
        for issue in currentIssues where !reportedDirectoryIssues.contains(issue) {
            reportFailure(issue)
        }
        reportedDirectoryIssues = Set(currentIssues)
    }

    private func forgetTints(forPackNamed packName: String) {
        accentInksByPackName.removeValue(forKey: packName)
        ownAccentByPackName.removeValue(forKey: packName)
        tintedSheets = tintedSheets.filter { key, _ in key.packName != packName }
    }

    private func applyOutcome(_ outcome: SpritePackLoader.LoadOutcome, packName: String) {
        forgetTints(forPackNamed: packName)
        switch outcome {
        case .loaded(let pack):
            sheetsByPackName[packName] = pack.sheet
            accentInksByPackName[packName] = pack.accentInks
            ownAccentByPackName[packName] = pack.ownAccent
            if let unknownAccentName = pack.unknownAccentName {
                reportFailure("agent-pet: sprite pack \(packName) accent \(unknownAccentName) is not an accent color, ignored")
            }
        case .failed(let reason):
            sheetsByPackName.removeValue(forKey: packName)
            reportFailure("agent-pet: sprite pack \(packName) not loaded, \(reason)")
        case .notDownloaded:
            break
        }
    }

    package static func writeToStandardError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
