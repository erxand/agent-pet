import Foundation

enum PacksCommand {
    private static let columnGap = "  "
    private static let affirmative = "yes"
    private static let negative = "no"
    private static let noAccent = "-"
    private static let notDownloadedMarker = "not downloaded"
    private static let nameColumnWidth = 12
    private static let accentColumnWidth = 8
    private static let reservedColumnWidth = 9
    private static let packHeader = "PACK"
    private static let accentHeader = "ACCENT"
    private static let reservedHeader = "RESERVED"
    private static let livePetsHeader = "PETS"
    private static let lineEnding = "\n"

    struct PackEntry: Encodable {
        let name: String
        let accent: String?
        let reserved: Bool
        let livePets: Int
        let downloaded: Bool

        enum CodingKeys: String, CodingKey {
            case name, accent, reserved, livePets, downloaded
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(accent, forKey: .accent)
            try container.encode(reserved, forKey: .reserved)
            try container.encode(livePets, forKey: .livePets)
            try container.encode(downloaded, forKey: .downloaded)
        }
    }

    struct PacksReport: Encodable {
        let packs: [PackEntry]
    }

    static func run(flags: ParsedFlags) -> Int32 {
        let contracts = AgentPetContracts.loaded()
        let entries = packEntries(contracts: contracts)
        if flags.isPresent(.json) {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let payload = try? encoder.encode(PacksReport(packs: entries)) else { return CommandFeedback.reportUsage() }
            FileHandle.standardOutput.write(payload)
            FileHandle.standardOutput.write(Data(lineEnding.utf8))
            return ExitCode.success
        }
        print(row(name: packHeader, accent: accentHeader, reserved: reservedHeader, livePets: livePetsHeader))
        for entry in entries {
            print(row(
                name: entry.name,
                accent: entry.accent ?? noAccent,
                reserved: entry.reserved ? affirmative : negative,
                livePets: entry.downloaded ? "\(entry.livePets)" : "\(entry.livePets)\(columnGap)\(notDownloadedMarker)"
            ))
        }
        return ExitCode.success
    }

    static func packEntries(contracts: AgentPetContracts) -> [PackEntry] {
        let reserved = Set(contracts.configuration.reservedSprites)
        var livePetsByPack: [String: Int] = [:]
        let livePets = LivePets.groups(
            records: PetSessionStore().list(),
            claudeSessions: contracts.sessionSource.recordsBySessionId()
        )
        for pet in livePets {
            livePetsByPack[pet.owner?.sprite ?? SpritePackLoader.defaultPackName, default: 0] += 1
        }
        let loader = contracts.spritePackLoader
        return loader.availablePackNames().map { packName in
            let outcome = loader.load(packNamed: packName)
            let downloaded: Bool
            if case .notDownloaded = outcome { downloaded = false } else { downloaded = true }
            return PackEntry(
                name: packName,
                accent: SpritePackAccent.accent(in: outcome, loader: loader)?.rawValue,
                reserved: reserved.contains(packName),
                livePets: livePetsByPack[packName] ?? 0,
                downloaded: downloaded
            )
        }
    }

    private static func row(name: String, accent: String, reserved: String, livePets: String) -> String {
        [
            padded(name, width: nameColumnWidth),
            padded(accent, width: accentColumnWidth),
            padded(reserved, width: reservedColumnWidth),
            livePets
        ].joined(separator: columnGap)
    }

    private static func padded(_ text: String, width: Int) -> String {
        String(text.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
