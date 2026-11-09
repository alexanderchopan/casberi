import Foundation
import Testing
@testable import Casberi

/// **A private send's steps, one model for Aztec and Railgun** (prd §1700w, §1700x).
///
/// What a wrong answer looks like on screen: a step drawn done that never
/// happened, seconds on the wrong row, a failure on a step it did not reach,
/// or a second engine's "checking" restarting the clock of a send the person
/// already tapped.
@MainActor
struct PrivateSendStepsTests {

    private func say(_ s: PrivateSendSteps, _ step: String, kind: String = "move", plan: PrivateSendSteps.Plan, extra: [String: Any] = [:]) {
        s.received(["step": step, "kind": kind].merging(extra) { $1 }, plan: plan)
    }

    @Test func aSendWalksItsPlanInOrder() throws {
        let s = PrivateSendSteps()
        let plan = PrivateSendSteps.Plan.send(.aztec)
        s.begin(.move, plan: plan)
        let started = try #require(s.run?.started)
        say(s, "checking", plan: plan)
        #expect(s.run?.started == started, "the engine's checking must not restart the tap's clock")
        #expect(s.run?.currentIndex == 0)
        say(s, "proving", plan: plan)
        #expect(s.run?.currentIndex == 1)
        say(s, "sent", plan: plan)
        #expect(s.run?.currentIndex == 2)
        #expect(s.run?.reachedNetwork == true)
        say(s, "done", plan: plan)
        let run = try #require(s.run)
        #expect(run.ok == true && !run.isRunning && run.total != nil)
        #expect(run.plan.steps.indices.allSatisfy { PrivateStepRows.phase($0, of: run) == .done })
    }

    @Test func aSkippedStepHasNoSecondsAndTheNextTakesTheClock() throws {
        let s = PrivateSendSteps()
        let plan = PrivateSendSteps.Plan.send(.aztec)
        s.begin(.move, plan: plan)
        say(s, "sent", plan: plan) // no proof was seen
        let run = try #require(s.run)
        #expect(run.currentIndex == 2)
        #expect(run.span(1).start == nil, "a step the engine never named has no start")
        #expect(run.span(0).end == run.at[.sent], "checking ends when the next step that happened began")
        #expect(PrivateStepRows.phase(1, of: run) == .done)
        #expect(PrivateStepRows.phase(2, of: run) == .now)
    }

    @Test func aFailureLandsOnTheStepItReachedWithItsReason() throws {
        let s = PrivateSendSteps()
        let plan = PrivateSendSteps.Plan.send(.aztec)
        s.begin(.move, plan: plan)
        say(s, "proving", plan: plan)
        say(s, "failed", plan: plan, extra: ["reason": "Aztec's node did not answer."])
        let run = try #require(s.run)
        #expect(run.ok == false && run.reachedNetwork == false)
        #expect(run.reason == "Aztec's node did not answer.")
        #expect(PrivateStepRows.phase(0, of: run) == .done)
        #expect(PrivateStepRows.phase(1, of: run) == .failed)
        #expect(PrivateStepRows.phase(2, of: run) == .next)
    }

    @Test func aSignedMoveInTakesSigningNotProving() throws {
        let s = PrivateSendSteps()
        let plan = PrivateSendSteps.Plan.signed(.ethereum)
        s.begin(.move, plan: plan)
        say(s, "proving", plan: plan) // not in this plan: ignored
        #expect(s.run?.currentIndex == 0)
        say(s, "signing", plan: plan)
        #expect(s.run?.currentIndex == 1)
        #expect(plan.steps.last?.done == PrivateSendSteps.Place.ethereum.sent)
    }

    @Test func anotherKindsStepsNeverMoveThisRun() throws {
        let s = PrivateSendSteps()
        let plan = PrivateSendSteps.Plan.send(.aztec)
        s.begin(.move, plan: plan)
        say(s, "proving", kind: "app", plan: plan)
        say(s, "done", kind: "app", plan: plan)
        #expect(s.run?.currentIndex == 0 && s.run?.isRunning == true)
    }
}
