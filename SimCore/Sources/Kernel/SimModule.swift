import SimCoreContract

/// A simulation module. It writes one section of the state bus.
///
/// The module gets its section as `inout` and the full state as a read-only value.
/// Thus a module cannot change the section of another module.
///
/// Determinism rules for all modules: no system clock, no random numbers without
/// `context.seed`, no result that depends on the order of a `Set` or a `Dictionary`.
public protocol SimModule: Sendable {
    associatedtype Section: Sendable

    /// The section that this module writes.
    static var section: WritableKeyPath<SimState, Section> { get }

    /// `state` is the state before this module runs in this step.
    /// It has the results of the modules that are earlier in the step order.
    mutating func step(_ section: inout Section, reading state: SimState, context: StepContext)
}

extension SimModule {
    /// The section key path without its value type.
    public static var sectionKeyPath: AnyKeyPath { section }

    /// Runs the module on the state bus.
    public mutating func run(on state: inout SimState, context: StepContext) {
        var section = state[keyPath: Self.section]
        step(&section, reading: state, context: context)
        state[keyPath: Self.section] = section
    }
}
