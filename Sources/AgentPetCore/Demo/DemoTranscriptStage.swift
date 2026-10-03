import Foundation

package final class DemoTranscriptStage: DemoStage {
    private let write: (String) -> Void
    private var lastPetsLine: String?

    package private(set) var tearDownCount = 0

    package init(write: @escaping (String) -> Void) {
        self.write = write
    }

    package var isSettled: Bool { true }

    package func present(scene: DemoScene, number: Int, of sceneCount: Int) {
        write("scene \(number)/\(sceneCount) \(scene.name.rawValue), \(DemoTranscriptStage.seconds(scene.durationInSeconds)) s")
    }

    package func present(title: DemoTitleCard?) {
        guard let title else { return }
        write("title: \(title.title), \(title.subtitle)")
    }

    package func present(caption: DemoCaption?) {
        guard let caption else { return }
        write("caption: \(caption.text)")
    }

    package func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) {
        let line = pets.isEmpty
            ? "pets: none"
            : "pets: " + pets.map { item in DemoTranscriptStage.describe(item) }.joined(separator: ", ")
        guard line != lastPetsLine else { return }
        lastPetsLine = line
        write(line)
    }

    package func present(toast: DemoToast) {
        write("toast: \(toast.title) \(toast.body)")
    }

    package func advance(elapsedSeconds: Double, sceneProgress: Double) {}

    package func tearDown() {
        tearDownCount += 1
        write("teardown: every demo window closed, nothing written")
    }

    private static func describe(_ item: PetDisplayItem) -> String {
        var parts = [item.session.sprite ?? SpritePackLoader.defaultPackName, item.mood.rawValue]
        if let bubbleCaption = item.bubbleCaption {
            parts.append("bubble \(bubbleCaption)")
        }
        if item.memberSessionIds.count > 1 {
            parts.append("\(item.memberSessionIds.count) members")
        }
        return "\(item.label) (\(parts.joined(separator: " ")))"
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
