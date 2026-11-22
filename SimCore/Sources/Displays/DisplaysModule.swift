import Kernel
import SimCoreContract

/// Displays module. It is a stub in E01. It writes only the `displays` section.
public struct DisplaysModule: SimModule {
    public static var section: WritableKeyPath<SimState, DisplaysState> { \.displays }

    public init() {}

    public mutating func step(_ section: inout DisplaysState, reading state: SimState, context: StepContext) {
    }
}
