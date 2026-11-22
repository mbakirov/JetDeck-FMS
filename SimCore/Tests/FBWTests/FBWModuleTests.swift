import Kernel
import SimCoreContract
import Testing
import FBW

@Test func writesOnlyItsSection() {
    #expect(FBWModule.sectionKeyPath == \SimState.fbw)
}

@Test func stubDoesNotChangeTheState() {
    let initial = InitialConditions(
        scenarioID: "test", settings: CoreSettings(radioHeightCallouts: []),
        utcStartSecondsOfDay: 0, seed: 0
    )
    var state = SimState()
    var module = FBWModule()
    module.run(on: &state, context: StepContext(step: 1, events: InputEvent.samples, initial: initial))
    #expect(state == SimState())
}
