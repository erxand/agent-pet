import Foundation
import Testing
import AgentPetCore
@testable import agent_pet

@Suite("every pet that goes away digs back down")
struct PetDiveTests {
    private static let tick = 1.0 / 30.0

    private struct DiveTrace {
        var progresses: [Double] = []
        var offsets: [Double] = []
        var ticks = 0

        // The overlay spreads the dive frames evenly over the progress, so a
        // frame is shown when some tick lands in its third.
        var framesShown: Set<Int> {
            Set(progresses.map { progress in min(2, Int(progress * 3)) })
        }
    }

    private func grounded() -> PetAnimator {
        let animator = PetAnimator()
        advance(animator, seconds: 1)
        #expect(animator.groundPhase == .grounded)
        return animator
    }

    private func advance(_ animator: PetAnimator, seconds: Double, step: Double = PetDiveTests.tick) {
        var remaining = seconds
        while remaining > 0 {
            animator.advance(elapsedSeconds: min(step, remaining), mood: .ready)
            remaining -= step
        }
    }

    private func traceDive(_ animator: PetAnimator, step: Double = PetDiveTests.tick) -> DiveTrace {
        var trace = DiveTrace()
        while !animator.isSubmerged && trace.ticks < 1000 {
            trace.progresses.append(animator.groundAnimationProgress)
            trace.offsets.append(animator.groundOffsetFraction)
            animator.advance(elapsedSeconds: step, mood: .ready)
            trace.ticks += 1
        }
        return trace
    }

    @Test func aGroundedPetPlaysEveryDiveFrame() {
        let animator = grounded()
        animator.requestDive()
        #expect(animator.isDiving)
        #expect(animator.animationName == .dive)
        let trace = traceDive(animator)
        #expect(trace.framesShown == [0, 1, 2])
        #expect(animator.isSubmerged)
        #expect(animator.groundOffsetFraction == 1)
    }

    @Test func aLateTickSlowsTheDiveInsteadOfSkippingIt() {
        let animator = grounded()
        animator.requestDive()
        // The main thread was busy for a whole second before the next tick.
        animator.advance(elapsedSeconds: 1, mood: .ready)
        #expect(!animator.isSubmerged)
        #expect(animator.groundAnimationProgress < 1.0 / 3.0)
        // Every tick is late from here on: still every frame, never a jump.
        let trace = traceDive(animator, step: 0.25)
        #expect(trace.framesShown == [0, 1, 2])
    }

    @Test func aPetHiddenMidEmergeStillPlaysEveryDiveFrame() {
        let animator = PetAnimator()
        advance(animator, seconds: 0.1)
        #expect(animator.groundPhase == .emerging)
        let heightWhenHidden = animator.groundOffsetFraction
        #expect(heightWhenHidden > 0 && heightWhenHidden < 1)

        animator.requestDive()
        #expect(animator.groundAnimationProgress == 0)
        #expect(animator.groundOffsetFraction == heightWhenHidden)
        let trace = traceDive(animator)
        #expect(trace.framesShown == [0, 1, 2])
        #expect(zip(trace.offsets, trace.offsets.dropFirst()).allSatisfy { earlier, later in later >= earlier })
        #expect(trace.offsets.first == heightWhenHidden)
    }

    @Test func aPetHiddenNearlyUpDivesFromWhereItIs() {
        let animator = PetAnimator()
        advance(animator, seconds: 0.4)
        #expect(animator.groundPhase == .emerging)
        let chromeWhenHidden = animator.chromeOpacity
        animator.requestDive()
        #expect(animator.chromeOpacity == chromeWhenHidden)
        animator.advance(elapsedSeconds: PetDiveTests.tick, mood: .ready)
        #expect(animator.chromeOpacity < chromeWhenHidden)
        #expect(traceDive(animator).framesShown == [0, 1, 2])
    }

    @Test func aPetWithNothingAboveGroundGoesStraightUnder() {
        let animator = PetAnimator()
        animator.requestDive()
        #expect(animator.isSubmerged)
    }

    @Test func showingAgainMidDiveComesBackUpFromTheSameHeight() {
        let animator = grounded()
        animator.requestDive()
        advance(animator, seconds: 0.3)
        let heightWhenShown = animator.groundOffsetFraction
        #expect(animator.isDiving)
        animator.requestEmerge()
        #expect(animator.groundPhase == .emerging)
        #expect(abs(animator.groundOffsetFraction - heightWhenShown) < 1e-9)
    }

    @Test func aStoppingDaemonWithNoPetsExitsAtOnce() throws {
        let sandbox = try Sandbox()
        let controller = PetOverlayController(
            configurationFile: sandbox.stateDirectory.appendingPathComponent("config.json"),
            store: PetSessionStore(directory: sandbox.sessionsDirectory),
            spritePackRegistry: SpritePackRegistry(
                loader: SpritePackLoader(
                    packsDirectory: sandbox.spritesDirectory,
                    extraDirectoryPaths: [],
                    homeDirectory: sandbox.home
                ),
                reportFailure: { _ in }
            )
        )
        var completions = 0
        controller.beginShutdown { completions += 1 }
        #expect(completions == 1)
        #expect(controller.isShuttingDown)
        controller.beginShutdown { completions += 1 }
        #expect(completions == 1)
    }
}
