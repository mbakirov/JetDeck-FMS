import SimCoreContract

/// The state bus. All simulation state is in this structure.
///
/// Rule: one module writes one section. A module gets its section as `inout`
/// and the full state as a read-only value. See `SimModule`.
public struct SimState: Sendable, Equatable {
    public var world = WorldState()
    public var sensors = SensorsState()
    public var fms = FMSState()
    public var autoFlight = AutoFlightState()
    public var fbw = FBWState()
    public var aircraft = AircraftState()
    public var warnings = WarningsState()
    public var displays = DisplaysState()

    // Sections that have no module in E01. The epics E10 and E11 define their owners.
    public var controls: ControlsState = .blank
    public var scenario: ScenarioStatus = .blank

    public init() {}
}

extension SimState {
    /// Makes the output of the step from the state sections.
    public func makeSnapshot(context: StepContext) -> Snapshot {
        Snapshot(
            schemaVersion: contractSchemaVersion,
            step: context.step,
            simTimeSeconds: context.simTimeSeconds,
            utcSecondsOfDay: (context.initial.utcStartSecondsOfDay + Int(context.simTimeSeconds)) % 86_400,
            pfd: displays.pfd,
            nd: displays.nd,
            ewd: displays.ewd,
            mcdu: displays.mcdu,
            fcu: displays.fcu,
            controls: controls,
            audio: warnings.audio,
            scenario: scenario
        )
    }
}
