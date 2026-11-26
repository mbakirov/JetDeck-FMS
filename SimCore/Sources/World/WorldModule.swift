import Kernel
import SimCoreContract

/// World module. It writes only the `world` section.
public struct WorldModule: SimModule {
    public static var section: WritableKeyPath<SimState, WorldState> { \.world }

    private let navData: any NavDatabase

    public init(navData: any NavDatabase = EmptyNavDatabase()) {
        self.navData = navData
    }

    public mutating func step(_ section: inout WorldState, reading state: SimState, context: StepContext) {
    }
}
