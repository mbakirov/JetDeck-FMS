import SimCoreContract

/// Data of one step that all modules can read.
public struct StepContext: Sendable, Equatable {
    /// Step number. The first step is 1.
    public var step: UInt64
    /// Input events that this step applies, in the order of `send`.
    public var events: [InputEvent]
    public var initial: InitialConditions

    public init(step: UInt64, events: [InputEvent], initial: InitialConditions) {
        self.step = step
        self.events = events
        self.initial = initial
    }

    /// Step length in seconds.
    public var dt: Double { simStepSeconds }

    /// Simulation time at the end of this step. It is a product, not a sum: there is no rounding drift.
    public var simTimeSeconds: Double { Double(step) * simStepSeconds }

    public var settings: CoreSettings { initial.settings }
    public var seed: UInt64 { initial.seed }
}
