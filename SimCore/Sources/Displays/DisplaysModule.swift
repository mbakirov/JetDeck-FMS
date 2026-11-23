import Kernel
import SimCoreContract

/// Displays module. It is a stub in E01. It writes only the `displays` section.
public struct DisplaysModule: SimModule {
    public static var section: WritableKeyPath<SimState, DisplaysState> { \.displays }

    /// The navigation database. It does not change while the engine exists.
    public let navData: any NavDatabase

    public init(navData: any NavDatabase = EmptyNavDatabase()) {
        self.navData = navData
    }

    public mutating func step(_ section: inout DisplaysState, reading state: SimState, context: StepContext) {
    }
}
