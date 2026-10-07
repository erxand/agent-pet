import Foundation

package final class DemoTranscriptStage: DemoStage {
    private let write: (String) -> Void
    private var lastPetsLine: String?
    private var screensaverIsUp = false

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

    package func present(states: [DemoStateMark]) {
        guard !states.isEmpty else { return }
        write("states: " + states.map { mark in "\(mark.label) (\(mark.sprite ?? "no pet"))" }.joined(separator: ", "))
    }

    package func present(cursor: DemoCursorCue?) {
        guard let cursor else { return }
        write("cursor: \(cursor.pressed ? "clicks" : "moves to") \(cursor.targetSessionId)")
    }

    package func present(terminal: DemoTerminalCard?) {
        guard let terminal else { return }
        write("terminal: \(terminal.title), " + terminal.shownTexts.dropFirst().joined(separator: " | "))
    }

    package func present(screensaver isUp: Bool) {
        guard isUp != screensaverIsUp else { return }
        screensaverIsUp = isUp
        write(isUp
            ? "screensaver: up. A script runs agent-pet physics float and agent-pet input off: the pets drift and spin over it"
            : "screensaver: gone. The script runs agent-pet physics auto and agent-pet input auto: the pets fall, land and walk back to their lanes")
    }

    package func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) {
        let line = pets.isEmpty
            ? "pets: none"
            : "pets: " + pets.map { item in DemoTranscriptStage.describe(item) }.joined(separator: ", ")
        guard line != lastPetsLine else { return }
        lastPetsLine = line
        write(line)
    }

    package func advance(elapsedSeconds: Double, sceneProgress: Double) {}

    package func tearDown() {
        tearDownCount += 1
        write("teardown: all demo windows are closed. Nothing was written.")
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
