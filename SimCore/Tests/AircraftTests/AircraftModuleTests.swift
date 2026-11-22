import Kernel
import SimCoreContract
import Testing
import Aircraft

@Test func writesOnlyItsSection() {
    #expect(AircraftModule.sectionKeyPath == \SimState.aircraft)
}

@Test func stubDoesNotChangeTheState() {
    let initial = InitialConditions(
        scenarioID: "test", settings: CoreSettings(radioHeightCallouts: []),
        utcStartSecondsOfDay: 0, seed: 0
    )
    var state = SimState()
    var module = AircraftModule()
    module.run(on: &state, context: StepContext(step: 1, events: InputEvent.samples, initial: initial))
    #expect(state == SimState())
}
