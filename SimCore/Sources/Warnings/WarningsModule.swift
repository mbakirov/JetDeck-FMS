import Kernel
import SimCoreContract

/// Warnings module. It is a stub in E01. It writes only the `warnings` section.
public struct WarningsModule: SimModule {
    public static var section: WritableKeyPath<SimState, WarningsState> { \.warnings }

    public init() {}

    public mutating func step(_ section: inout WarningsState, reading state: SimState, context: StepContext) {
    }
}
