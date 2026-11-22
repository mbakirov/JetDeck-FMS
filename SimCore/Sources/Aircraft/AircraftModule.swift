import Kernel
import SimCoreContract

/// Aircraft module. It is a stub in E01. It writes only the `aircraft` section.
public struct AircraftModule: SimModule {
    public static var section: WritableKeyPath<SimState, AircraftState> { \.aircraft }

    public init() {}

    public mutating func step(_ section: inout AircraftState, reading state: SimState, context: StepContext) {
    }
}
