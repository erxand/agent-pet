import Foundation

final class SpritePackRegistry {
    private let loader: SpritePackLoader
    private let fallbackSheet: SpriteSheet
    private let reportFailure: (String) -> Void

    private var sheetsByPackName: [String: SpriteSheet] = [:]
    private var directoryModificationByPackName: [String: Date] = [:]

    init(
        loader: SpritePackLoader = SpritePackLoader(),
        fallbackSheet: SpriteSheet = SpriteSheet.claude8Bit,
        reportFailure: @escaping (String) -> Void = SpritePackRegistry.writeToStandardError
    ) {
        self.loader = loader
        self.fallbackSheet = fallbackSheet
        self.reportFailure = reportFailure
    }

    func sheet(forPackNamed packName: String?) -> SpriteSheet {
        let resolvedName = packName ?? SpritePackLoader.defaultPackName
        return sheetsByPackName[resolvedName] ?? fallbackSheet
    }

    func reloadChangedPacks() -> Bool {
        var anythingChanged = false
        var seenPackNames: Set<String> = []
        for packName in loader.availablePackNames() {
            seenPackNames.insert(packName)
            let currentModification = loader.directoryModification(forPackNamed: packName)
            if let knownModification = directoryModificationByPackName[packName],
               knownModification == currentModification {
                continue
            }
            if let currentModification {
                directoryModificationByPackName[packName] = currentModification
            } else {
                directoryModificationByPackName.removeValue(forKey: packName)
            }
            applyOutcome(loader.load(packNamed: packName), packName: packName)
            anythingChanged = true
        }
        for knownPackName in sheetsByPackName.keys where !seenPackNames.contains(knownPackName) {
            sheetsByPackName.removeValue(forKey: knownPackName)
            directoryModificationByPackName.removeValue(forKey: knownPackName)
            anythingChanged = true
        }
        return anythingChanged
    }

    private func applyOutcome(_ outcome: SpritePackLoader.LoadOutcome, packName: String) {
        switch outcome {
        case .loaded(let sheet):
            sheetsByPackName[packName] = sheet
        case .failed(let reason):
            sheetsByPackName.removeValue(forKey: packName)
            reportFailure("agent-pet: sprite pack \(packName) not loaded, \(reason)")
        }
    }

    static func writeToStandardError(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}
