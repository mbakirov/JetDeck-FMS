import Kernel
import SimCoreContract

/// AutoFlight module. It is a stub in E01. It writes only the `autoFlight` section.
public struct AutoFlightModule: SimModule {
    public static var section: WritableKeyPath<SimState, AutoFlightState> { \.autoFlight }

    public init() {}

    public mutating func step(_ section: inout AutoFlightState, reading state: SimState, context: StepContext) {
    }
}
