import Kernel
import SimCoreContract

/// FBW module. It is a stub in E01. It writes only the `fbw` section.
public struct FBWModule: SimModule {
    public static var section: WritableKeyPath<SimState, FBWState> { \.fbw }

    public init() {}

    public mutating func step(_ section: inout FBWState, reading state: SimState, context: StepContext) {
    }
}
