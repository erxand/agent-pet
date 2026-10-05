import Foundation

struct SpritePackAssignment {
    private let availablePackNames: [String]
    private let packNamesInUse: [String]
    private let spriteByPetKey: [String: String]

    init(availablePackNames: [String], packNamesInUse: [String], spriteByPetKey: [String: String] = [:]) {
        self.availablePackNames = availablePackNames
        self.packNamesInUse = packNamesInUse
        self.spriteByPetKey = spriteByPetKey
    }

    static func current(
        excludingSessionId sessionId: String,
        sessionSource: SessionSource,
        loader: SpritePackLoader,
        reservedPackNames: Set<String> = []
    ) -> SpritePackAssignment {
        let livePets = LivePets.groups(
            records: PetSessionStore().list().filter { session in session.sessionId != sessionId },
            claudeSessions: sessionSource.recordsBySessionId()
        )
        var spriteByPetKey: [String: String] = [:]
        for pet in livePets {
            if let sprite = pet.owner?.sprite { spriteByPetKey[pet.key] = sprite }
        }
        return SpritePackAssignment(
            availablePackNames: loader.availablePackNames().filter { packName in !reservedPackNames.contains(packName) },
            packNamesInUse: livePets.compactMap { pet in pet.owner?.sprite },
            spriteByPetKey: spriteByPetKey
        )
    }

    func spriteOfLivePet(petKey: String) -> String? {
        spriteByPetKey[petKey]
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
