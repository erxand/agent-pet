import Foundation

struct SpritePackAssignment {
    private let availablePackNames: [String]
    private let packNamesInUse: [String]

    init(availablePackNames: [String], packNamesInUse: [String]) {
        self.availablePackNames = availablePackNames
        self.packNamesInUse = packNamesInUse
    }

    static func current(excludingSessionId sessionId: String) -> SpritePackAssignment {
        let claudeSessions = ClaudeSessionDirectory().recordsBySessionId()
        let packNamesInUse = PetSessionStore().list()
            .filter { session in
                session.sessionId != sessionId
                    && session.enabled
                    && ProcessLiveness.isAlive(session: session, claudeSession: claudeSessions[session.sessionId])
            }
            .compactMap { session in session.sprite }
        return SpritePackAssignment(
            availablePackNames: SpritePackLoader().availablePackNames(),
            packNamesInUse: packNamesInUse
        )
    }

    func pickLeastUsedPackName() -> String? {
        var generator = SystemRandomNumberGenerator()
        return pickLeastUsedPackName(using: &generator)
    }

    func pickLeastUsedPackName<Generator: RandomNumberGenerator>(using generator: inout Generator) -> String? {
        guard !availablePackNames.isEmpty else { return nil }
        var usageCountByPackName: [String: Int] = [:]
        for packName in packNamesInUse {
            usageCountByPackName[packName, default: 0] += 1
        }
        let lowestUsageCount = availablePackNames
            .map { packName in usageCountByPackName[packName] ?? 0 }
            .min() ?? 0
        let leastUsedPackNames = availablePackNames.filter { packName in
            (usageCountByPackName[packName] ?? 0) == lowestUsageCount
        }
        return leastUsedPackNames.randomElement(using: &generator)
    }
}
