import Foundation

package enum DemoMode: Equatable {
    case play
    case snapshot(URL)
}

package struct DemoRequest {
    package let scenes: [DemoScene]
    package let speed: Double
    package let mode: DemoMode
    package let waitsForUser: Bool
}

enum DemoCommand {
    private static let defaultSpeed: Double = 1
    private static let listNameColumnWidth = 12

    static func run(flags: ParsedFlags, runDemo: (DemoRequest) -> Int32) -> Int32 {
        let scenes: [DemoScene]
        if let sceneName = flags.value(for: .scene) {
            guard let name = DemoSceneName(rawValue: sceneName), let scene = DemoScript.scene(named: name) else {
                return CommandFeedback.reportUnknownScene(sceneName)
            }
            scenes = [scene]
        } else {
            scenes = DemoScript.scenes
        }
        if flags.isPresent(.list) {
            printList(scenes)
            return ExitCode.success
        }
        var speed = defaultSpeed
        if let rawSpeed = flags.value(for: .speed) {
            guard let parsedSpeed = Double(rawSpeed), parsedSpeed > 0, parsedSpeed.isFinite else {
                return CommandFeedback.reportInvalidSpeed(rawSpeed)
            }
            speed = parsedSpeed
        }
        if flags.isPresent(.dryRun) {
            return runTranscript(scenes: scenes, speed: speed)
        }
        if let snapshotPath = flags.value(for: .snapshot) {
            let directory = URL(fileURLWithPath: (snapshotPath as NSString).expandingTildeInPath, isDirectory: true)
            return runDemo(DemoRequest(scenes: scenes, speed: speed, mode: .snapshot(directory), waitsForUser: false))
        }
        return runDemo(DemoRequest(scenes: scenes, speed: speed, mode: .play, waitsForUser: !flags.isPresent(.auto)))
    }

    static func reportOverlayUnavailable(_ request: DemoRequest) -> Int32 {
        CommandFeedback.reportDemoUnavailable()
    }

    private static func runTranscript(scenes: [DemoScene], speed: Double) -> Int32 {
        let stage = DemoTranscriptStage(write: writeLine)
        let runner = DemoRunner(scenes: scenes, stage: stage)
        var exitCode: Int32?
        let playback = DemoPlayback(
            runner: runner,
            stage: stage,
            speed: speed,
            reportStop: writeLine,
            onFinish: { finishedExitCode in exitCode = finishedExitCode }
        )
        playback.start()
        while exitCode == nil {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(DemoPlayback.idleWaitInSeconds))
        }
        return exitCode ?? ExitCode.success
    }

    private static func writeLine(_ line: String) {
        print(line)
        fflush(stdout)
    }

    private static func printList(_ scenes: [DemoScene]) {
        for scene in scenes {
            let paddedName = scene.name.rawValue.padding(toLength: listNameColumnWidth, withPad: " ", startingAt: 0)
            let duration = String(format: "%4.1f s", scene.durationInSeconds)
            let advance = scene.holdOffsetInSeconds == nil ? "auto " : "space"
            print("\(paddedName)\(duration)  \(advance)  \(summary(of: scene))")
        }
        print(String(format: "total %.1f s with --auto. Without it, a scene marked space waits for the space bar.", scenes.reduce(0) { total, scene in total + scene.durationInSeconds }))
    }

    private static func summary(of scene: DemoScene) -> String {
        if let caption = scene.caption { return caption }
        for step in scene.steps {
            if case .showTitle(let titleCard) = step.action { return titleCard.title }
        }
        return scene.name.rawValue
    }
}
