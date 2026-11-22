import Kernel
import SimCoreContract
import Testing
import AutoFlight

@Test func writesOnlyItsSection() {
    #expect(AutoFlightModule.sectionKeyPath == \SimState.autoFlight)
}

@Test func stubDoesNotChangeTheState() {
    let initial = InitialConditions(
        scenarioID: "test", settings: CoreSettings(radioHeightCallouts: []),
        utcStartSecondsOfDay: 0, seed: 0
    )
    var state = SimState()
    var module = AutoFlightModule()
    module.run(on: &state, context: StepContext(step: 1, events: InputEvent.samples, initial: initial))
    #expect(state == SimState())
}
