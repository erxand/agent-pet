import Foundation
import Testing
@testable import AgentPetCore

@Suite("every shipped sprite pack loads")
struct ShippedPackTests {
    private let sprites = Sandbox.packageRoot.appendingPathComponent("sprites", isDirectory: true)

    private var shippedPackNames: [String] {
        SpritePackLoader(packsDirectory: sprites, extraDirectoryPaths: []).availablePackNames()
    }

    @Test func theRepoShipsTwentyTwoPacks() {
        #expect(shippedPackNames.count == 22)
        for name in ["astrocat", "bookwyrm", "bopkin", "bumble", "cactling", "dapperfox", "docturtle",
                     "gecklet", "hermy", "rangermot", "raven", "scruff", "skyhop", "tapeling"] {
            #expect(shippedPackNames.contains(name), "\(name)")
        }
    }

    @Test func eachPackLoadsWithItsOwnNameAndAnAccent() throws {
        let loader = SpritePackLoader(packsDirectory: sprites, extraDirectoryPaths: [])
        for name in shippedPackNames {
            let manifestURL = sprites.appendingPathComponent(name).appendingPathComponent(SpritePackLoader.manifestFileName)
            let manifest = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
            #expect(manifest["name"] as? String == name)
            switch loader.load(packNamed: name) {
            case .loaded(let pack):
                #expect(pack.unknownAccentName == nil, "\(name)")
                #expect(pack.ownAccent != nil, "\(name)")
            case .failed(let reason):
                Issue.record("\(name) did not load: \(reason)")
            case .notDownloaded(let paths):
                Issue.record("\(name) is not downloaded: \(paths)")
            }
        }
    }
}
