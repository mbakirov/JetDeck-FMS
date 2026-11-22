import Kernel
import SimCoreContract

/// FMS module. It is a stub in E01. It writes only the `fms` section.
public struct FMSModule: SimModule {
    public static var section: WritableKeyPath<SimState, FMSState> { \.fms }

    /// The navigation database. It does not change while the engine exists.
    public let navData: any NavDatabase

    public init(navData: any NavDatabase = EmptyNavDatabase()) {
        self.navData = navData
    }

    public mutating func step(_ section: inout FMSState, reading state: SimState, context: StepContext) {
    }
}
