import Kernel
import SimCoreContract

/// Sensors module. It is a stub in E01. It writes only the `sensors` section.
public struct SensorsModule: SimModule {
    public static var section: WritableKeyPath<SimState, SensorsState> { \.sensors }

    public init() {}

    public mutating func step(_ section: inout SensorsState, reading state: SimState, context: StepContext) {
    }
}
