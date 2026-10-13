import Foundation

enum PacksCommand {
    private static let columnGap = "  "
    private static let affirmative = "yes"
    private static let negative = "no"
    private static let noAccent = "-"
    private static let nameColumnWidth = 12
    private static let accentColumnWidth = 8
    private static let reservedColumnWidth = 9
    private static let livePetsColumnWidth = 4
    private static let packHeader = "PACK"
    private static let accentHeader = "ACCENT"
    private static let reservedHeader = "RESERVED"
    private static let livePetsHeader = "PETS"
    private static let lastAssignedHeader = "LAST ASSIGNED"
    private static let neverAssigned = "never"
    private static let agoSuffix = " ago"
    private static let lineEnding = "\n"
    private static let secondsPerMinute = 60
    private static let secondsPerHour = 60 * secondsPerMinute
    private static let secondsPerDay = 24 * secondsPerHour
    private static let smallestAgeUnit = (seconds: 1, suffix: "s")
    private static let ageUnits: [(seconds: Int, suffix: String)] = [
        (seconds: secondsPerDay, suffix: "d"),
        (seconds: secondsPerHour, suffix: "h"),
        (seconds: secondsPerMinute, suffix: "m"),
        smallestAgeUnit
    ]

    struct PackEntry: Encodable {
        let name: String
        let accent: String?
        let reserved: Bool
        let livePets: Int
        let lastAssignedAt: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case name, accent, reserved, livePets, lastAssignedAt
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(name, forKey: .name)
            try container.encode(accent, forKey: .accent)
            try container.encode(reserved, forKey: .reserved)
            try container.encode(livePets, forKey: .livePets)
            try container.encode(lastAssignedAt, forKey: .lastAssignedAt)
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
        print(row(
            name: packHeader,
            accent: accentHeader,
            reserved: reservedHeader,
            livePets: livePetsHeader,
            lastAssigned: lastAssignedHeader
        ))
        let now = Date()
        for entry in entries {
            print(row(
                name: entry.name,
                accent: entry.accent ?? noAccent,
                reserved: entry.reserved ? affirmative : negative,
                livePets: "\(entry.livePets)",
                lastAssigned: lastAssignedText(entry.lastAssignedAt, now: now)
            ))
        }
        return ExitCode.success
    }

    static func lastAssignedText(_ lastAssignedAt: TimeInterval?, now: Date) -> String {
        guard let lastAssignedAt else { return neverAssigned }
        let elapsedSeconds = Int(max(0, now.timeIntervalSince1970 - lastAssignedAt))
        let unit = ageUnits.first { unit in elapsedSeconds >= unit.seconds } ?? smallestAgeUnit
        return "\(elapsedSeconds / unit.seconds)\(unit.suffix)\(agoSuffix)"
    }

    static func packEntries(contracts: AgentPetContracts) -> [PackEntry] {
        let reserved = Set(contracts.configuration.reservedSprites)
        let lastAssignedAtByPackName = SpriteAssignmentHistory().lastAssignedAtByPackName()
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
            PackEntry(
                name: packName,
                accent: SpritePackAccent.accent(forPackNamed: packName, loader: loader)?.rawValue,
                reserved: reserved.contains(packName),
                livePets: livePetsByPack[packName] ?? 0,
                lastAssignedAt: lastAssignedAtByPackName[packName]
            )
        }
    }

    private static func row(name: String, accent: String, reserved: String, livePets: String, lastAssigned: String) -> String {
        [
            padded(name, width: nameColumnWidth),
            padded(accent, width: accentColumnWidth),
            padded(reserved, width: reservedColumnWidth),
            padded(livePets, width: livePetsColumnWidth),
            lastAssigned
        ].joined(separator: columnGap)
    }

    private static func padded(_ text: String, width: Int) -> String {
        String(text.prefix(width)).padding(toLength: width, withPad: " ", startingAt: 0)
    }
}
