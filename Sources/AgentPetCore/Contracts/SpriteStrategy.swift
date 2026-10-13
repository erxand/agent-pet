import Foundation

package protocol SpriteStrategy {
    func spriteName(forNewSessionId sessionId: String, group: String?) -> String?
    func recordAssignment(of packName: String)
}

package struct LeastUsedSpriteStrategy: SpriteStrategy {
    package static let oldestShareDivisor = 2
    package static let minimumRotationPoolSize = 1

    private let sessionSource: SessionSource
    private let loader: SpritePackLoader
    private let reservedPackNames: Set<String>
    private let history: SpriteAssignmentHistory
    private let clock: () -> Date

    package init(
        sessionSource: SessionSource,
        loader: SpritePackLoader = SpritePackLoader(),
        reservedPackNames: [String] = [],
        history: SpriteAssignmentHistory = SpriteAssignmentHistory(),
        clock: @escaping () -> Date = Date.init
    ) {
        self.sessionSource = sessionSource
        self.loader = loader
        self.reservedPackNames = Set(reservedPackNames)
        self.history = history
        self.clock = clock
    }

    package func spriteName(forNewSessionId sessionId: String, group: String?) -> String? {
        let assignment = SpritePackAssignment.current(
            excludingSessionId: sessionId,
            sessionSource: sessionSource,
            loader: loader,
            reservedPackNames: reservedPackNames
        )
        if let group, let ownerSprite = assignment.spriteOfLivePet(petKey: group) {
            return ownerSprite
        }
        var generator = SystemRandomNumberGenerator()
        return LeastUsedSpriteStrategy.leastRecentlyAssignedPackName(
            among: assignment.leastUsedPackNames(),
            lastAssignedAtByPackName: history.lastAssignedAtByPackName(),
            now: clock(),
            using: &generator
        )
    }

    package func recordAssignment(of packName: String) {
        history.recordAssignment(of: packName, at: clock(), installedPackNames: loader.availablePackNames())
    }

    package static func leastRecentlyAssignedPackName<Generator: RandomNumberGenerator>(
        among candidates: [String],
        lastAssignedAtByPackName: [String: TimeInterval],
        now: Date,
        using generator: inout Generator
    ) -> String? {
        let shuffledCandidates = candidates.shuffled(using: &generator)
        let rotationCandidates = shuffledCandidates.enumerated().map { shuffledPosition, packName -> RotationCandidate in
            RotationCandidate(
                packName: packName,
                age: age(of: lastAssignedAtByPackName[packName], now: now),
                shuffledPosition: shuffledPosition
            )
        }
        let oldestFirst = rotationCandidates.sorted { first, second in first.isOlder(than: second) }
        let poolSize = max(minimumRotationPoolSize, oldestFirst.count / oldestShareDivisor)
        return oldestFirst.prefix(poolSize).randomElement(using: &generator)?.packName
    }

    private static func age(of lastAssignedAt: TimeInterval?, now: Date) -> TimeInterval {
        guard let lastAssignedAt else { return .infinity }
        return max(0, now.timeIntervalSince1970 - lastAssignedAt)
    }

    private struct RotationCandidate {
        let packName: String
        let age: TimeInterval
        let shuffledPosition: Int

        func isOlder(than other: RotationCandidate) -> Bool {
            guard age == other.age else { return age > other.age }
            return shuffledPosition < other.shuffledPosition
        }
    }
}
