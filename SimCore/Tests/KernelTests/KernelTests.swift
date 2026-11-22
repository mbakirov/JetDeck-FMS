import Kernel
import SimCoreContract
import Testing

let testInitial = InitialConditions(
    scenarioID: "test", settings: CoreSettings(radioHeightCallouts: [50]),
    utcStartSecondsOfDay: 86_390, seed: 42
)

/// A module that writes its section and tries to change another section through the read-only state.
struct WarningsSpy: SimModule {
    static var section: WritableKeyPath<SimState, WarningsState> { \.warnings }
    var calls = 0

    mutating func step(_ section: inout WarningsState, reading state: SimState, context: StepContext) {
        calls += 1
        section.audio.recentCues.append(AudioCue(seq: context.step, sound: .cChord))
        var copy = state
        copy.controls.masterWarningLit = true   // changes a local copy only
    }
}

@Test func moduleChangesOnlyItsSection() {
    var state = SimState()
    var module = WarningsSpy()
    module.run(on: &state, context: StepContext(step: 5, events: [], initial: testInitial))

    var expected = SimState()
    expected.warnings.audio.recentCues = [AudioCue(seq: 5, sound: .cChord)]
    #expect(state == expected)
    #expect(module.calls == 1)
    #expect(WarningsSpy.sectionKeyPath == \SimState.warnings)
}

@Test func moduleKeepsItsOwnStateBetweenSteps() {
    var state = SimState()
    var module: any SimModule = WarningsSpy()
    for step in 1...3 {
        module.run(on: &state, context: StepContext(step: UInt64(step), events: [], initial: testInitial))
    }
    #expect((module as? WarningsSpy)?.calls == 3)
    #expect(state.warnings.audio.recentCues.map(\.seq) == [1, 2, 3])
}

@Test func stepContextTime() {
    let context = StepContext(step: 30_000, events: [], initial: testInitial)
    #expect(context.dt == 0.02)
    #expect(context.simTimeSeconds == 600.0)
    #expect(context.seed == 42)
    #expect(context.settings.radioHeightCallouts == [50])
}

@Test func snapshotIsMadeFromSections() {
    var state = SimState()
    state.displays.fcu.altitudeFt = 3000
    state.warnings.audio.continuous = [.cChord]
    state.controls.gearLever = .down
    state.scenario.phase = .completed
    let snapshot = state.makeSnapshot(context: StepContext(step: 50, events: [], initial: testInitial))

    #expect(snapshot.schemaVersion == contractSchemaVersion)
    #expect(snapshot.step == 50)
    #expect(snapshot.simTimeSeconds == 1.0)
    #expect(snapshot.fcu.altitudeFt == 3000)
    #expect(snapshot.audio.continuous == [.cChord])
    #expect(snapshot.controls.gearLever == .down)
    #expect(snapshot.scenario.phase == .completed)
}

@Test func utcTimeWrapsAtMidnight() {
    let state = SimState()
    // Start is 10 s before midnight. 15 s later the time is 00:00:05.
    let snapshot = state.makeSnapshot(context: StepContext(step: 750, events: [], initial: testInitial))
    #expect(snapshot.utcSecondsOfDay == 5)
}
