import Foundation
import Kernel
import Testing
@testable import SimCore

@Test func latestSnapshotBeforeFirstStepIsInitial() {
    let engine = SimEngine(initial: testInitial)
    #expect(engine.latestSnapshot == Snapshot.initial(testInitial))
}

@Test func stepIncrementsStepAndTime() {
    let engine = SimEngine(initial: testInitial)
    let first = engine.step()
    #expect(first.step == 1)
    #expect(first.simTimeSeconds == 0.02)
    for _ in 0..<49 { engine.step() }
    #expect(engine.latestSnapshot.step == 50)
    #expect(engine.latestSnapshot.simTimeSeconds == 1.0)
    #expect(engine.latestSnapshot.utcSecondsOfDay == 3601)
}

/// Acceptance criterion: an event sent between steps N and N+1 is applied in step N+1.
@Test func eventSentBetweenStepsIsAppliedInTheNextStep() {
    let log = Log<SeenStep>()
    let engine = SimEngine(initial: testInitial, modules: [WorldSpy(log: log)])

    for _ in 0..<3 { engine.step() }                 // steps 1...3
    engine.send(.fcu(.knobPulled(.altitude)))        // between steps 3 and 4
    engine.step()                                    // step 4
    engine.step()                                    // step 5

    let seen = log.all
    #expect(seen.map(\.step) == [1, 2, 3, 4, 5])
    #expect(seen[2].events == [])
    #expect(seen[3].events == [.fcu(.knobPulled(.altitude))])
    #expect(seen[4].events == [])
    #expect(engine.recording().events == [RecordedEvent(step: 4, event: .fcu(.knobPulled(.altitude)))])
}

@Test func eventsBeforeTheFirstStepAreAppliedInStepOne() {
    let log = Log<SeenStep>()
    let engine = SimEngine(initial: testInitial, modules: [WorldSpy(log: log)])
    engine.send(.mcdu(.clear))
    engine.step()
    #expect(log.all == [SeenStep(module: "World", step: 1, events: [.mcdu(.clear)])])
}

@Test func eventsKeepTheOrderOfSend() {
    let log = Log<SeenStep>()
    let engine = SimEngine(initial: testInitial, modules: [WorldSpy(log: log)])
    for event in InputEvent.samples { engine.send(event) }
    engine.step()
    #expect(log.all[0].events == InputEvent.samples)
}

@Test func modulesRunInTheGivenOrder() {
    let log = Log<SeenStep>()
    let engine = SimEngine(initial: testInitial, modules: [WorldSpy(log: log), DisplaysSpy(log: log)])
    engine.step()
    engine.step()
    #expect(log.all.map(\.module) == ["World", "Displays", "World", "Displays"])
}

@Test func standardStepOrder() {
    let modules = SimEngine.standardModules()
    #expect(modules.map { String(describing: type(of: $0)) } == [
        "WorldModule", "SensorsModule", "FMSModule", "AutoFlightModule",
        "FBWModule", "AircraftModule", "WarningsModule", "DisplaysModule",
    ])
}

@Test func eachSectionHasOneWriter() {
    let sections = SimEngine.standardModules().map { type(of: $0).sectionKeyPath }
    #expect(Set(sections).count == sections.count)
    #expect(sections == [
        \SimState.world, \SimState.sensors, \SimState.fms, \SimState.autoFlight,
        \SimState.fbw, \SimState.aircraft, \SimState.warnings, \SimState.displays,
    ])
}

@Test func moduleResultIsInTheSnapshot() {
    let engine = SimEngine(initial: testInitial, modules: [DisplaysSpy(log: Log())])
    engine.send(.mcdu(.dot))
    engine.send(.mcdu(.slash))
    #expect(engine.step().fcu.altitudeFt == 2)
    #expect(engine.step().fcu.altitudeFt == 2)
}

@Test func sendIsSafeFromManyThreads() async {
    let log = Log<SeenStep>()
    let engine = SimEngine(initial: testInitial, modules: [WorldSpy(log: log)])
    let senders = 8
    let perSender = 1000

    await withTaskGroup(of: Void.self) { group in
        for sender in 0..<senders {
            group.addTask {
                for index in 0..<perSender {
                    engine.send(.fcu(.knobTurned(.heading, clicks: sender * perSender + index)))
                }
            }
        }
        group.addTask {
            for _ in 0..<2000 { engine.step() }
        }
    }
    engine.step()   // applies the events that came after the last step of the task

    var clicks: [Int] = []
    for seen in log.all {
        for case .fcu(.knobTurned(.heading, let value)) in seen.events {
            clicks.append(value)
        }
    }
    #expect(clicks.count == senders * perSender)
    #expect(Set(clicks).count == senders * perSender)
    // The events of one sender keep their order.
    for sender in 0..<senders {
        let own = clicks.filter { $0 / perSender == sender }
        #expect(own == own.sorted())
    }
    #expect(engine.recording().events.count == senders * perSender)
}

/// Acceptance criterion: 30 000 steps (10 minutes of simulation time) without errors.
@Test func soak30000Steps() {
    let recording = SyntheticRecording.make(steps: 30_000, eventCount: 3000, seed: 3)
    let engine = SimEngine(initial: recording.initial)
    var next = 0
    var previous: UInt64 = 0
    for step in 1...UInt64(30_000) {
        while next < recording.events.count, recording.events[next].step == step {
            engine.send(recording.events[next].event)
            next += 1
        }
        let snapshot = engine.step()
        #expect(snapshot.step == previous + 1)
        previous = snapshot.step
    }
    #expect(engine.latestSnapshot.step == 30_000)
    #expect(engine.latestSnapshot.simTimeSeconds == 600.0)
    #expect(engine.latestSnapshot.utcSecondsOfDay == 12 * 3600 + 600)
    #expect(engine.recording() == recording)
}
