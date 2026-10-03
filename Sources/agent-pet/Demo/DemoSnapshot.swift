import AgentPetCore
import AppKit

final class DemoBackdropView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DemoPalette.backdrop.setFill()
        bounds.fill()
    }
}

final class DemoCapturingStage: DemoStage {
    private(set) var pets: [PetDisplayItem] = []
    private(set) var labelPlacement: LabelPlacement = .pill
    private(set) var captions: [DemoCaption?] = []
    private(set) var states: [DemoStateMark] = []
    private(set) var cursor: DemoCursorCue?
    private(set) var terminal: DemoTerminalCard?

    var isSettled: Bool { true }
    func present(scene: DemoScene, number: Int, of sceneCount: Int) {}
    func present(title: DemoTitleCard?) {}
    func present(caption: DemoCaption?) { captions.append(caption) }
    func present(states: [DemoStateMark]) { self.states = states }
    func present(cursor: DemoCursorCue?) { self.cursor = cursor }
    func present(terminal: DemoTerminalCard?) { self.terminal = terminal }
    func advance(elapsedSeconds: Double, sceneProgress: Double) {}
    func tearDown() {}

    func present(pets: [PetDisplayItem], labelPlacement: LabelPlacement) {
        self.pets = pets
        self.labelPlacement = labelPlacement
    }
}

enum DemoSnapshot {
    private static let successExitCode: Int32 = 0
    private static let failureExitCode: Int32 = 1
    private static let margin: CGFloat = 24
    private static let captionProgress = 0.4
    private static let snapshotScreenWidth: CGFloat = 1440
    private static let lanesMomentInSeconds: Double = 2.5
    private static let statesMomentInSeconds: Double = 3
    private static let stateCellWidth: CGFloat = 288
    private static let stateLabelGap: CGFloat = 12
    private static let petGap: CGFloat = 48
    private static let clickMomentInSeconds: Double = 2
    private static let revealMomentInSeconds: Double = 4
    private static let cursorAimHeightFraction: CGFloat = 0.55

    private enum FileName {
        static let title = "title.png"
        static let caption = "caption.png"
        static let unfocusedCaption = "caption-unfocused.png"
        static let click = "click.png"
        static let stage = "stage.png"
        static let states = "states.png"
        static let terminal = "terminal.png"
    }

    static func formattedSeconds(_ seconds: Double) -> String {
        String(format: "%.0f", seconds)
    }

    static func write(scenes: [DemoScene], to directory: URL) -> Int32 {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("agent-pet: cannot create \(directory.path)\n".utf8))
            return failureExitCode
        }
        let spriteSheets = DemoSpriteSheets()
        let titleCard = firstTitleCard(in: scenes) ?? firstTitleCard(in: DemoScript.scenes)
        let captionScene = scenes.first { scene in scene.caption != nil } ?? DemoScript.scenes.first { scene in scene.caption != nil }

        var written: [URL] = []
        var expectedCount = 4
        if let titleCard {
            expectedCount += 1
            written.append(contentsOf: save(DemoTitleView(card: titleCard), named: FileName.title, in: directory))
        }
        if let captionScene, let captionText = captionScene.caption {
            let sceneNumber = (DemoScript.scenes.firstIndex { scene in scene.name == captionScene.name } ?? 0) + 1
            for (hasFocus, fileName) in [(true, FileName.caption), (false, FileName.unfocusedCaption)] {
                expectedCount += 1
                let view = DemoCaptionView(
                    caption: DemoCaption(
                        text: captionText,
                        sceneNumber: sceneNumber,
                        sceneCount: DemoScript.scenes.count,
                        accent: sceneAccent(captionScene)
                    ),
                    maximumWidth: snapshotScreenWidth
                )
                view.progress = captionProgress
                view.hasFocus = hasFocus
                written.append(contentsOf: save(view, named: fileName, in: directory))
            }
        }
        written.append(contentsOf: save(clickComposite(spriteSheets: spriteSheets), named: FileName.click, in: directory))
        written.append(contentsOf: save(stageComposite(spriteSheets: spriteSheets), named: FileName.stage, in: directory))
        written.append(contentsOf: save(statesComposite(spriteSheets: spriteSheets), named: FileName.states, in: directory))
        written.append(contentsOf: save(revealComposite(spriteSheets: spriteSheets), named: FileName.terminal, in: directory))

        for fileURL in written {
            print(fileURL.path)
        }
        return written.count == expectedCount ? successExitCode : failureExitCode
    }

    private static func firstTitleCard(in scenes: [DemoScene]) -> DemoTitleCard? {
        for scene in scenes {
            for step in scene.steps {
                if case .showTitle(let titleCard) = step.action { return titleCard }
            }
        }
        return nil
    }

    private static func petsAt(sceneNamed name: DemoSceneName, seconds: Double) -> DemoCapturingStage {
        let stage = DemoCapturingStage()
        guard let scene = DemoScript.scene(named: name) else { return stage }
        let runner = DemoRunner(scenes: [scene], stage: stage)
        runner.advance(byElapsedSeconds: seconds)
        return stage
    }

    private static func sceneAccent(_ scene: DemoScene) -> AccentColor? {
        let stage = DemoCapturingStage()
        let runner = DemoRunner(scenes: [scene], stage: stage)
        runner.start()
        return stage.captions.compactMap { caption in caption }.last?.accent
    }

    private static func petViews(
        from stage: DemoCapturingStage,
        spriteSheets: DemoSpriteSheets,
        diving: Bool = false
    ) -> [PetView] {
        stage.pets.map { item in
            let packName = item.session.sprite ?? SpritePackLoader.defaultPackName
            let sheet = spriteSheets.sheet(forPackNamed: packName)
            let appearance = PetAppearance(
                label: item.label,
                accent: item.session.resolvedAccent,
                mood: item.mood,
                message: item.message,
                bubbleCaption: item.bubbleCaption,
                labelPlacement: stage.labelPlacement,
                spriteSideLength: PetGeometry.spritePixelSideLength(frameSize: sheet.frameSize)
            )
            let view = PetView(sessionId: item.petKey, petAppearance: appearance)
            let diveFrame = sheet.dive.indices.contains(1) ? sheet.dive[1] : sheet.dive.first
            if let frame = diving ? (diveFrame ?? sheet.idle.first) : sheet.idle.first {
                view.update(
                    spriteImage: PixelRenderer.image(for: frame, palette: sheet.palette, scale: PetGeometry.spriteScale, facingLeft: false),
                    bubbleVerticalOffset: 0,
                    groundOffsetFraction: 0,
                    chromeOpacity: 1
                )
            }
            return view
        }
    }

    private static func stageComposite(spriteSheets: DemoSpriteSheets) -> NSView {
        let lanesScene = DemoScript.scene(named: .lanes)
        let caption = DemoCaptionView(
            caption: DemoCaption(
                text: lanesScene?.caption ?? "",
                sceneNumber: (DemoScript.scenes.firstIndex { scene in scene.name == .lanes } ?? 0) + 1,
                sceneCount: DemoScript.scenes.count,
                accent: lanesScene.flatMap { scene in sceneAccent(scene) }
            ),
            maximumWidth: snapshotScreenWidth
        )
        caption.progress = captionProgress
        let pets = petViews(from: petsAt(sceneNamed: .lanes, seconds: lanesMomentInSeconds), spriteSheets: spriteSheets)
        return composite(caption: caption, pets: pets)
    }

    private static func statesComposite(spriteSheets: DemoSpriteSheets) -> NSView {
        let stage = petsAt(sceneNamed: .states, seconds: statesMomentInSeconds)
        let scene = DemoScript.scene(named: .states)
        let caption = DemoCaptionView(
            caption: DemoCaption(
                text: scene?.caption ?? "",
                sceneNumber: (DemoScript.scenes.firstIndex { scene in scene.name == .states } ?? 0) + 1,
                sceneCount: DemoScript.scenes.count,
                accent: scene.flatMap { scene in sceneAccent(scene) }
            ),
            maximumWidth: snapshotScreenWidth
        )
        caption.progress = statesMomentInSeconds / (scene?.durationInSeconds ?? 1)
        var petViewsBySessionId: [String: PetView] = [:]
        for (item, view) in zip(stage.pets, petViews(from: stage, spriteSheets: spriteSheets)) {
            for sessionId in item.memberSessionIds { petViewsBySessionId[sessionId] = view }
        }
        let pixelSide = DemoStateLabelView.pixelSide(for: stage.states, laneSpacing: stateCellWidth)
        let defaultSide = PetGeometry.spritePixelSideLength(frameSize: spriteSheets.sheet(forPackNamed: SpritePackLoader.defaultPackName).frameSize)
        let petHeight = PetGeometry.totalHeight(spriteSideLength: defaultSide, labelPlacement: .pill)
        let labels = stage.states.map { mark in DemoStateLabelView(mark: mark, pixelSide: pixelSide) }
        let labelHeight = labels.map { label in label.preferredSize.height }.max() ?? 0
        let rowWidth = stateCellWidth * CGFloat(stage.states.count)
        let rowHeight = petHeight + stateLabelGap + labelHeight
        let width = max(caption.preferredSize.width, rowWidth) + margin * 2
        let height = margin * 3 + caption.preferredSize.height + rowHeight
        let backdrop = DemoBackdropView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        caption.setFrameOrigin(CGPoint(x: ((width - caption.preferredSize.width) / 2).rounded(), y: margin * 2 + rowHeight))
        backdrop.addSubview(caption)
        let rowLeft = ((width - rowWidth) / 2).rounded()
        for (slotIndex, mark) in stage.states.enumerated() {
            let centerX = rowLeft + stateCellWidth * (CGFloat(slotIndex) + 0.5)
            let label = labels[slotIndex]
            label.setFrameOrigin(CGPoint(x: (centerX - label.preferredSize.width / 2).rounded(), y: margin + petHeight + stateLabelGap))
            backdrop.addSubview(label)
            if let sessionId = mark.sessionId, let petView = petViewsBySessionId[sessionId] {
                petView.setFrameOrigin(CGPoint(x: (centerX - petView.preferredSize.width / 2).rounded(), y: margin))
                backdrop.addSubview(petView)
            } else {
                let spot = DemoEmptySpotView(sideLength: defaultSide)
                spot.setFrameOrigin(CGPoint(
                    x: (centerX - defaultSide / 2).rounded(),
                    y: margin + PetGeometry.spriteBaseline(labelPlacement: .pill)
                ))
                backdrop.addSubview(spot)
            }
        }
        return backdrop
    }

    private static func revealComposite(spriteSheets: DemoSpriteSheets) -> NSView {
        let shownStage = petsAt(sceneNamed: .click, seconds: clickMomentInSeconds)
        let revealStage = petsAt(sceneNamed: .click, seconds: revealMomentInSeconds)
        let scene = DemoScript.scene(named: .click)
        let caption = DemoCaptionView(
            caption: DemoCaption(
                text: scene?.caption ?? "",
                sceneNumber: (DemoScript.scenes.firstIndex { scene in scene.name == .click } ?? 0) + 1,
                sceneCount: DemoScript.scenes.count,
                accent: scene.flatMap { scene in sceneAccent(scene) }
            ),
            maximumWidth: snapshotScreenWidth
        )
        caption.progress = revealMomentInSeconds / (scene?.holdOffsetInSeconds ?? scene?.durationInSeconds ?? 1)
        let terminal = revealStage.terminal.map { card in DemoTerminalView(card: card) }
        let pets = petViews(from: shownStage, spriteSheets: spriteSheets, diving: true)
        let cursor = DemoCursorView()
        let terminalSize = terminal?.preferredSize ?? .zero
        let petsHeight = pets.map { view in view.preferredSize.height }.max() ?? 0
        let width = max(caption.preferredSize.width, terminalSize.width) + margin * 2
        let height = margin * 4 + caption.preferredSize.height + terminalSize.height + petsHeight
        let backdrop = DemoBackdropView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        if let terminal {
            terminal.setFrameOrigin(CGPoint(x: ((width - terminalSize.width) / 2).rounded(), y: margin * 3 + caption.preferredSize.height + petsHeight))
            backdrop.addSubview(terminal)
        }
        caption.setFrameOrigin(CGPoint(x: ((width - caption.preferredSize.width) / 2).rounded(), y: margin * 2 + petsHeight))
        backdrop.addSubview(caption)
        var aim = CGPoint(x: width / 2, y: margin + petsHeight / 2)
        if let pet = pets.first {
            pet.setFrameOrigin(CGPoint(x: ((width - pet.preferredSize.width) / 2).rounded(), y: margin))
            backdrop.addSubview(pet)
            let sheet = spriteSheets.sheet(forPackNamed: shownStage.pets.first?.session.sprite ?? SpritePackLoader.defaultPackName)
            let spriteSide = PetGeometry.spritePixelSideLength(frameSize: sheet.frameSize)
            aim = CGPoint(
                x: pet.frame.midX,
                y: margin + PetGeometry.spriteBaseline(labelPlacement: .pill) + spriteSide * cursorAimHeightFraction
            )
        }
        cursor.setFrameOrigin(CGPoint(x: aim.x.rounded(), y: (aim.y - cursor.bounds.height - DemoCursorView.pixelSide).rounded()))
        backdrop.addSubview(cursor)
        return backdrop
    }

    private static func clickComposite(spriteSheets: DemoSpriteSheets) -> NSView {
        let stage = petsAt(sceneNamed: .click, seconds: clickMomentInSeconds)
        let pets = petViews(from: stage, spriteSheets: spriteSheets, diving: true)
        let sceneNumber = (DemoScript.scenes.firstIndex { scene in scene.name == .click } ?? 0) + 1
        let pet = stage.pets.first
        let caption = DemoCaptionView(
            caption: DemoCaption(
                text: DemoScript.scene(named: .click)?.caption ?? "",
                sceneNumber: sceneNumber,
                sceneCount: DemoScript.scenes.count,
                accent: pet?.session.resolvedAccent
            ),
            maximumWidth: snapshotScreenWidth
        )
        caption.progress = clickMomentInSeconds / (DemoScript.scene(named: .click)?.durationInSeconds ?? 1)
        return composite(caption: caption, pets: pets)
    }

    private static func composite(caption: DemoCaptionView, pets: [PetView]) -> NSView {
        let petsWidth = pets.reduce(0) { total, view in total + view.preferredSize.width } + petGap * CGFloat(max(0, pets.count - 1))
        let petsHeight = pets.map { view in view.preferredSize.height }.max() ?? 0
        let width = max(caption.preferredSize.width, petsWidth) + margin * 2
        let height = margin * 3 + caption.preferredSize.height + petsHeight
        let backdrop = DemoBackdropView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        caption.setFrameOrigin(CGPoint(x: ((width - caption.preferredSize.width) / 2).rounded(), y: margin * 2 + petsHeight))
        backdrop.addSubview(caption)
        var cursor = ((width - petsWidth) / 2).rounded()
        for view in pets {
            view.setFrameOrigin(CGPoint(x: cursor, y: margin))
            backdrop.addSubview(view)
            cursor += view.preferredSize.width + petGap
        }
        return backdrop
    }

    private static func save(_ view: NSView, named fileName: String, in directory: URL) -> [URL] {
        let content: NSView
        if view is DemoBackdropView {
            content = view
        } else {
            let size = view.frame.size
            let backdrop = DemoBackdropView(frame: CGRect(x: 0, y: 0, width: size.width + margin * 2, height: size.height + margin * 2))
            view.setFrameOrigin(CGPoint(x: margin, y: margin))
            backdrop.addSubview(view)
            content = backdrop
        }
        guard let representation = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return [] }
        content.cacheDisplay(in: content.bounds, to: representation)
        guard let pngData = representation.representation(using: .png, properties: [:]) else { return [] }
        let fileURL = directory.appendingPathComponent(fileName)
        do {
            try pngData.write(to: fileURL)
        } catch {
            return []
        }
        return [fileURL]
    }
}
