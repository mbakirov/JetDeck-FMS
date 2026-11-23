import Foundation
import Testing
@testable import SimCore

// MARK: RunnerScheduler (no threads, fake time)

@Test func schedulerRunsOneStepPerPeriod() {
    var scheduler = RunnerScheduler()
    #expect(scheduler.stepsDue(now: 0) == 0)          // first call sets the deadline
    #expect(scheduler.nextDeadline == 0.02)
    #expect(scheduler.stepsDue(now: 0.019) == 0)
    var total = 0
    for tick in 1...50 {
        total += scheduler.stepsDue(now: Double(tick) * 0.02 + 0.001)
    }
    #expect(total == 50)                               // 1 second gives 50 steps
}

@Test func schedulerCatchesUpAShortDelay() {
    var scheduler = RunnerScheduler()
    _ = scheduler.stepsDue(now: 0)
    // Deadline is 0.02. At 0.065 the steps of 0.02, 0.04 and 0.06 are due.
    #expect(scheduler.stepsDue(now: 0.065) == 3)
    #expect(abs(scheduler.nextDeadline! - 0.08) < 1e-9)
}

@Test func schedulerDropsALongDelay() {
    var scheduler = RunnerScheduler()
    _ = scheduler.stepsDue(now: 0)
    // 20 steps are late. The scheduler runs 5 and drops the others.
    #expect(scheduler.stepsDue(now: 0.41) == RunnerScheduler.maxCatchUpSteps)
    #expect(abs(scheduler.nextDeadline! - 0.43) < 1e-9)
    #expect(scheduler.stepsDue(now: 0.42) == 0)
    #expect(scheduler.stepsDue(now: 0.431) == 1)
}

@Test func schedulerRateChangesThePeriod() {
    var scheduler = RunnerScheduler(rate: 2)
    #expect(scheduler.period == 0.01)
    _ = scheduler.stepsDue(now: 0)
    var total = 0
    for tick in 1...100 {
        total += scheduler.stepsDue(now: Double(tick) * 0.01 + 0.001)
    }
    #expect(total == 100)                              // 1 second gives 100 steps at rate 2

    scheduler.rate = 0.5
    #expect(scheduler.period == 0.04)
}

@Test func schedulerResetDoesNotCatchUpThePause() {
    var scheduler = RunnerScheduler()
    _ = scheduler.stepsDue(now: 0)
    scheduler.reset()
    #expect(scheduler.stepsDue(now: 100) == 0)         // 100 s of pause give no steps
    #expect(scheduler.stepsDue(now: 100.021) == 1)
}

// MARK: SimRunner (real thread, real clock)

func waitUntil(timeout: Double = 5, _ condition: () -> Bool) -> Bool {
    let end = Date().addingTimeInterval(timeout)
    while Date() < end {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return condition()
}

/// Acceptance criterion: a pause stops the simulation time. After the pause the step number continues without a gap.
@Test func pauseStopsTimeAndStepNumbersHaveNoGap() {
    let engine = SimEngine(initial: testInitial)
    let steps = Log<UInt64>()
    let runner = SimRunner(core: engine, rate: 4) { steps.append($0.step) }

    runner.start()
    #expect(runner.isRunning)
    #expect(waitUntil { engine.latestSnapshot.step >= 10 })

    runner.pause()
    Thread.sleep(forTimeInterval: 0.05)                // a step in progress can end
    let paused = engine.latestSnapshot
    Thread.sleep(forTimeInterval: 0.2)
    #expect(runner.isPaused)
    #expect(engine.latestSnapshot.step == paused.step)
    #expect(engine.latestSnapshot.simTimeSeconds == paused.simTimeSeconds)

    runner.resume()
    #expect(waitUntil { engine.latestSnapshot.step >= paused.step + 10 })
    runner.stop()
    #expect(!runner.isRunning)

    let all = steps.all
    #expect(all.first == 1)
    #expect(all == Array(1...UInt64(all.count)))       // each step one time, no gap
    #expect(all.last == engine.latestSnapshot.step)

    // The pause is not caught up: the first steps after the pause do not come as a group of 5.
    let afterStop = engine.latestSnapshot.step
    Thread.sleep(forTimeInterval: 0.05)
    #expect(engine.latestSnapshot.step == afterStop)   // no steps after stop
}

@Test func runnerRunsNearRealTime() {
    let engine = SimEngine(initial: testInitial)
    let runner = SimRunner(core: engine)
    let clock = ContinuousClock()
    let start = clock.now
    runner.start()
    Thread.sleep(forTimeInterval: 0.5)
    runner.stop()
    // The limits use the measured time, not 0.5 s: a busy machine (CI) can sleep longer than asked.
    // The runner is near real time: not more steps than the time allows (+2 for the first and the last step),
    // and not less than half of them.
    let elapsed = clock.now - start
    let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
    let allowed = seconds / simStepSeconds
    let steps = Double(engine.latestSnapshot.step)
    #expect(steps >= allowed / 2 && steps <= allowed + 2, "steps: \(steps), time: \(seconds) s")
}

@Test func runnerCanStartAgainAfterStop() {
    let engine = SimEngine(initial: testInitial)
    let runner = SimRunner(core: engine, rate: 4)
    runner.start()
    #expect(waitUntil { engine.latestSnapshot.step >= 3 })
    runner.stop()
    let stopped = engine.latestSnapshot.step
    runner.start()
    #expect(waitUntil { engine.latestSnapshot.step >= stopped + 3 })
    runner.stop()
}

@Test func eventsSentWhileRunningAreApplied() {
    let engine = SimEngine(initial: testInitial)
    let runner = SimRunner(core: engine, rate: 4)
    runner.start()
    for event in InputEvent.samples {
        engine.send(event)
        Thread.sleep(forTimeInterval: 0.002)
    }
    #expect(waitUntil { engine.recording().events.count == InputEvent.samples.count })
    runner.stop()
    #expect(engine.recording().events.map(\.event) == InputEvent.samples)
}
