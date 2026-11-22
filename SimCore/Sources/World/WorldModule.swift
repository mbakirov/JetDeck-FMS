import Kernel
import SimCoreContract

/// World module. It is a stub in E01. It writes only the `world` section.
public struct WorldModule: SimModule {
    public static var section: WritableKeyPath<SimState, WorldState> { \.world }

    public init() {}

    public mutating func step(_ section: inout WorldState, reading state: SimState, context: StepContext) {
    }
}
