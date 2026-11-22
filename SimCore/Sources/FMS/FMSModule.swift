import Kernel
import SimCoreContract

/// FMS module. It is a stub in E01. It writes only the `fms` section.
public struct FMSModule: SimModule {
    public static var section: WritableKeyPath<SimState, FMSState> { \.fms }

    public init() {}

    public mutating func step(_ section: inout FMSState, reading state: SimState, context: StepContext) {
    }
}
