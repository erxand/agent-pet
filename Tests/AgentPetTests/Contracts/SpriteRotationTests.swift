import Foundation
import Testing
@testable import AgentPetCore

@Suite("sprite rotation by assignment history")
struct SpriteRotationTests {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private let seeds: [UInt64] = Array(1...40)

    private func picks(
        among candidates: [String],
        history: [String: TimeInterval],
        seed: UInt64,
        count: Int = 1
    ) -> [String?] {
        var generator = SeededGenerator(seed: seed)
        return (0..<count).map { _ in
            LeastUsedSpriteStrategy.leastRecentlyAssignedPackName(
                among: candidates,
                lastAssignedAtByPackName: history,
                now: now,
                using: &generator
            )
        }
    }

    private func pickedAcrossSeeds(among candidates: [String], history: [String: TimeInterval]) -> Set<String> {
        Set(seeds.flatMap { seed in picks(among: candidates, history: history, seed: seed, count: 5) }.compactMap { pick in pick })
    }

    private func secondsAgo(_ seconds: TimeInterval) -> TimeInterval {
        now.timeIntervalSince1970 - seconds
    }

    @Test func aNeverAssignedPackBeatsEveryAssignedOne() {
        let history = ["golem": secondsAgo(86_400 * 30), "nimbus": secondsAgo(60)]
        let picked = pickedAcrossSeeds(among: ["golem", "nimbus", "seon", "tinowl"], history: history)
        #expect(picked == ["seon", "tinowl"])
    }

    @Test func thePickIsUniformAmongTheOldestHalf() {
        let history = [
            "astrocat": secondsAgo(600), "bumble": secondsAgo(500), "golem": secondsAgo(400),
            "nimbus": secondsAgo(300), "seon": secondsAgo(200), "tinowl": secondsAgo(100)
        ]
        let candidates = ["tinowl", "seon", "nimbus", "golem", "bumble", "astrocat"]
        #expect(pickedAcrossSeeds(among: candidates, history: history) == ["astrocat", "bumble", "golem"])

        let oddHistory = history.filter { entry in entry.key != "tinowl" }
        let oddCandidates = candidates.filter { packName in packName != "tinowl" }
        #expect(pickedAcrossSeeds(among: oddCandidates, history: oddHistory) == ["astrocat", "bumble"])
    }

    @Test func aSingleCandidateIsPickedHoweverRecentAndNoCandidateGivesNothing() {
        #expect(pickedAcrossSeeds(among: ["golem"], history: ["golem": now.timeIntervalSince1970]) == ["golem"])
        #expect(picks(among: [], history: [:], seed: 1) == [nil])
    }

    @Test func ofTwoCandidatesTheOlderIsAlwaysPicked() {
        let history = ["golem": secondsAgo(10), "nimbus": secondsAgo(20)]
        #expect(pickedAcrossSeeds(among: ["golem", "nimbus"], history: history) == ["nimbus"])
        #expect(pickedAcrossSeeds(among: ["golem", "nimbus"], history: ["golem": secondsAgo(10)]) == ["nimbus"])
    }

    @Test func tiedCandidatesAreAllReachable() {
        let candidates = ["golem", "nimbus", "seon", "tinowl"]
        #expect(pickedAcrossSeeds(among: candidates, history: [:]) == Set(candidates))
    }

    @Test func leastUsedStillWinsOverRecency() {
        let assignment = SpritePackAssignment(availablePackNames: ["golem", "nimbus"], packNamesInUse: ["golem"])
        let picked = pickedAcrossSeeds(among: assignment.leastUsedPackNames(), history: ["nimbus": secondsAgo(1)])
        #expect(picked == ["nimbus"])
    }

    @Test func everyRunOfTwelvePicksFromTwentyTwoPacksIsDistinct() {
        let packNames = (1...22).map { packNumber in "pack\(packNumber)" }
        let runLength = packNames.count - packNames.count / LeastUsedSpriteStrategy.oldestShareDivisor + 1
        #expect(runLength == 12)
        var sawRepeatJustPastTheRun = false
        for seed in seeds {
            var generator = SeededGenerator(seed: seed)
            var history: [String: TimeInterval] = [:]
            var sequence: [String] = []
            for step in 0..<66 {
                let clock = now.addingTimeInterval(TimeInterval(step))
                guard let picked = LeastUsedSpriteStrategy.leastRecentlyAssignedPackName(
                    among: packNames,
                    lastAssignedAtByPackName: history,
                    now: clock,
                    using: &generator
                ) else { break }
                history[picked] = clock.timeIntervalSince1970
                sequence.append(picked)
            }
            #expect(sequence.count == 66)
            for start in 0...(sequence.count - runLength) {
                #expect(Set(sequence[start..<(start + runLength)]).count == runLength)
            }
            for start in 0..<(sequence.count - runLength) where sequence[start] == sequence[start + runLength] {
                sawRepeatJustPastTheRun = true
            }
        }
        #expect(sawRepeatJustPastTheRun)
    }

    @Test func aMissingOrMalformedHistoryReadsAsEmpty() throws {
        let sandbox = try Sandbox()
        let history = SpriteAssignmentHistory(directory: sandbox.stateDirectory)
        #expect(history.lastAssignedAtByPackName().isEmpty)

        try "not json".write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        #expect(history.lastAssignedAtByPackName().isEmpty)
        try #"{"golem":"yesterday"}"#.write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        #expect(history.lastAssignedAtByPackName().isEmpty)
        try #"{"golem":1790000000.5}"#.write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        #expect(history.lastAssignedAtByPackName() == ["golem": 1_790_000_000.5])
    }

    @Test func onRecordsTheAssignedPackAndPrunesPacksNoLongerInstalled() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        try #"{"ghost":5,"golem":10}"#.write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        let before = Date().timeIntervalSince1970
        try sandbox.run(["on", "--session", "first-session", "--no-color-sync"])
        let after = Date().timeIntervalSince1970

        let assigned = try #require(sandbox.record("first-session")?["sprite"] as? String)
        #expect(assigned == "nimbus")
        let history = SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName()
        #expect(Set(history.keys) == ["golem", "nimbus"])
        #expect(history["golem"] == 10)
        let stamped = try #require(history["nimbus"])
        #expect(stamped >= before && stamped <= after)
        let written = try String(contentsOf: sandbox.historyFile, encoding: .utf8)
        let golemPosition = try #require(written.range(of: "golem")).lowerBound
        let nimbusPosition = try #require(written.range(of: "nimbus")).lowerBound
        #expect(golemPosition < nimbusPosition)
        #expect(sandbox.exists(sandbox.stateDirectory.appendingPathComponent(SpriteAssignmentHistory.lockFileName)))
    }

    @Test func aMalformedHistoryFileIsReplacedAndAnUnwritableOneNeverFailsOn() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try "{{{".write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        #expect(try sandbox.run(["on", "--session", "first-session", "--no-color-sync"]).exitStatus == 0)
        #expect(SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName().keys.sorted() == ["golem"])

        let blocked = try Sandbox()
        try blocked.installPack("golem")
        try FileManager.default.createDirectory(at: blocked.historyFile, withIntermediateDirectories: true)
        let run = try blocked.run(["on", "--session", "first-session", "--no-color-sync"])
        #expect(run.exitStatus == 0)
        #expect(run.standardOutput.contains("sprite golem, accent green"))
        #expect(blocked.record("first-session")?["sprite"] as? String == "golem")
    }

    @Test func anExplicitSpriteAReenrollmentAndAPreviewRecordNothing() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        try sandbox.run(["on", "--session", "chosen-session", "--sprite", "golem", "--no-color-sync"])
        #expect(!sandbox.exists(sandbox.historyFile))

        try sandbox.run(["preview", "--seconds", "0"])
        try sandbox.run(["preview", "--seconds", "0", "--sprite", "nimbus"])
        #expect(!sandbox.exists(sandbox.historyFile))

        try sandbox.run(["on", "--session", "picked-session", "--no-color-sync"])
        let firstHistory = SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName()
        #expect(firstHistory.count == 1)
        try sandbox.run(["on", "--session", "picked-session", "--no-color-sync"])
        #expect(SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName() == firstHistory)
    }

    @Test func aReservedPackIsNeverPickedEvenWhenItWasNeverAssigned() throws {
        let sandbox = try Sandbox()
        try "{\"reservedSprites\":[\"golem\"]}".write(
            to: sandbox.stateDirectory.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        for _ in 0..<3 {
            try sandbox.run(["on", "--session", "rotating-session", "--no-color-sync"])
            #expect(sandbox.record("rotating-session")?["sprite"] as? String == "nimbus")
            try sandbox.run(["remove", "--session", "rotating-session"])
        }
        #expect(SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName().keys.sorted() == ["nimbus"])
    }

    @Test func aLivePetOutweighsAnOlderAssignment() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let liveProcess = "\(getpid())"
        try sandbox.run(["on", "--session", "first-session", "--sprite", "golem", "--pid", liveProcess, "--no-color-sync"])
        try "{\"nimbus\":\(Date().timeIntervalSince1970)}".write(to: sandbox.historyFile, atomically: true, encoding: .utf8)
        try sandbox.run(["on", "--session", "second-session", "--pid", liveProcess, "--no-color-sync"])

        #expect(sandbox.record("second-session")?["sprite"] as? String == "nimbus")
    }

    @Test func oneSessionEnrollingAndRemovingTwentyTwoTimesRepeatsNoPackWithinTwelvePicks() throws {
        let sandbox = try Sandbox()
        let shippedPackNames = try Sandbox.shippedPackNames()
        #expect(shippedPackNames.count == 22)
        for packName in shippedPackNames { try sandbox.installPack(packName) }
        let runLength = 12

        var sequence: [String] = []
        for _ in 0..<shippedPackNames.count {
            try sandbox.run(["on", "--session", "rotating-session", "--no-color-sync"])
            sequence.append(try #require(sandbox.record("rotating-session")?["sprite"] as? String))
            try sandbox.run(["remove", "--session", "rotating-session"])
        }

        #expect(sequence.count == shippedPackNames.count)
        for start in 0...(sequence.count - runLength) {
            #expect(Set(sequence[start..<(start + runLength)]).count == runLength, "\(sequence)")
        }
        #expect(SpriteAssignmentHistory(directory: sandbox.stateDirectory).lastAssignedAtByPackName().count == Set(sequence).count)
    }

    @Test func packsShowsWhenEachPackWasLastAssigned() throws {
        let sandbox = try Sandbox()
        try sandbox.installPack("golem")
        try sandbox.installPack("nimbus")
        let threeHoursAgo = Date().timeIntervalSince1970 - 3 * 3_600 - 30
        try "{\"golem\":\(threeHoursAgo)}".write(to: sandbox.historyFile, atomically: true, encoding: .utf8)

        let table = try sandbox.run(["packs"]).standardOutput.split(separator: "\n")
        #expect(table[0].hasSuffix("LAST ASSIGNED"))
        #expect(table[1].hasPrefix("golem") && table[1].hasSuffix("3h ago"))
        #expect(table[2].hasPrefix("nimbus") && table[2].hasSuffix("never"))

        let report = try #require(
            try JSONSerialization.jsonObject(with: Data(sandbox.run(["packs", "--json"]).standardOutput.utf8)) as? [String: Any]
        )
        let packs = try #require(report["packs"] as? [[String: Any]])
        let reportedAssignment = try #require(packs[0]["lastAssignedAt"] as? Double)
        #expect(abs(reportedAssignment - threeHoursAgo) < 0.001)
        #expect(packs[1]["lastAssignedAt"] is NSNull)
    }

    @Test func lastAssignedTextUsesTheLargestWholeUnit() {
        #expect(PacksCommand.lastAssignedText(nil, now: now) == "never")
        #expect(PacksCommand.lastAssignedText(secondsAgo(5), now: now) == "5s ago")
        #expect(PacksCommand.lastAssignedText(secondsAgo(150), now: now) == "2m ago")
        #expect(PacksCommand.lastAssignedText(secondsAgo(3 * 3_600 + 59), now: now) == "3h ago")
        #expect(PacksCommand.lastAssignedText(secondsAgo(2 * 86_400), now: now) == "2d ago")
        #expect(PacksCommand.lastAssignedText(secondsAgo(-30), now: now) == "0s ago")
    }
}

extension Sandbox {
    var historyFile: URL { stateDirectory.appendingPathComponent(SpriteAssignmentHistory.fileName) }

    static func shippedPackNames() throws -> [String] {
        let spritesRoot = packageRoot.appendingPathComponent("sprites", isDirectory: true)
        return try FileManager.default.contentsOfDirectory(at: spritesRoot, includingPropertiesForKeys: [.isDirectoryKey])
            .filter { entryURL in (try? entryURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
            .map { entryURL in entryURL.lastPathComponent }
            .sorted()
    }
}
