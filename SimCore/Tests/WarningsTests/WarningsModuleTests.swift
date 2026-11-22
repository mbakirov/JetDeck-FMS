import Kernel
import SimCoreContract
import Testing
import Warnings

@Test func writesOnlyItsSection() {
    #expect(WarningsModule.sectionKeyPath == \SimState.warnings)
}

@Test func stubDoesNotChangeTheState() {
    let initial = InitialConditions(
        scenarioID: "test", settings: CoreSettings(radioHeightCallouts: []),
        utcStartSecondsOfDay: 0, seed: 0
    )
    var state = SimState()
    var module = WarningsModule()
    module.run(on: &state, context: StepContext(step: 1, events: InputEvent.samples, initial: initial))
    #expect(state == SimState())
}
