@_exported import SimCoreContract
import Aircraft
import AutoFlight
import Displays
import FBW
import FMS
import Kernel
import Sensors
import Synchronization
import Warnings
import World

/// The simulation core. It is the implementation of the facade `SimCoreProtocol`.
///
/// One step has a fixed order:
/// input, World, Sensors, FMS, AutoFlight, FBW, Aircraft, Warnings, Displays, snapshot.
///
/// The core has no pause and no rate. `SimRunner` controls the calls to `step`.
/// To restart a scenario, make a new `SimEngine`.
public final class SimEngine: SimCoreProtocol {
    private struct StepState: Sendable {
        var step: UInt64 = 0
        var state: SimState
        var modules: [any SimModule]
        var journal: [RecordedEvent] = []
    }

    public let initial: InitialConditions
    /// The navigation database of this engine. A new database needs a new engine.
    public let navData: any NavDatabase

    private let pending = Mutex<[InputEvent]>([])
    private let latest: Mutex<Snapshot>
    private let stepState: Mutex<StepState>

    /// `navData` is the navigation database. Without it the core has no navigation data (`EmptyNavDatabase`).
    public convenience init(initial: InitialConditions, navData: any NavDatabase = EmptyNavDatabase()) {
        self.init(initial: initial, modules: Self.standardModules(navData: navData), navData: navData)
    }

    /// Tests use this initialiser to replace the modules.
    init(initial: InitialConditions, modules: [any SimModule], navData: any NavDatabase = EmptyNavDatabase()) {
        self.initial = initial
        self.navData = navData
        self.latest = Mutex(Snapshot.initial(initial))
        self.stepState = Mutex(StepState(state: SimState(initial: initial), modules: modules))
    }

    /// The modules in the order of the step.
    static func standardModules(navData: any NavDatabase = EmptyNavDatabase()) -> [any SimModule] {
        [
            WorldModule(navData: navData),
            SensorsModule(),
            FMSModule(navData: navData),
            AutoFlightModule(),
            FBWModule(),
            AircraftModule(),
            WarningsModule(),
            DisplaysModule(navData: navData),
        ]
    }

    public func send(_ event: InputEvent) {
        pending.withLock { $0.append(event) }
    }

    @discardableResult
    public func step() -> Snapshot {
        let snapshot = stepState.withLock { s -> Snapshot in
            // Input: take all events that came before this point. Later events wait for the next step.
            let events = pending.withLock { queue in
                let taken = queue
                queue.removeAll(keepingCapacity: true)
                return taken
            }
            s.step += 1
            for event in events {
                s.journal.append(RecordedEvent(step: s.step, event: event))
            }
            let context = StepContext(step: s.step, events: events, initial: initial)
            for index in s.modules.indices {
                s.modules[index].run(on: &s.state, context: context)
            }
            return s.state.makeSnapshot(context: context)
        }
        latest.withLock { $0 = snapshot }
        return snapshot
    }

    public var latestSnapshot: Snapshot {
        latest.withLock { $0 }
    }

    /// The recording of the flight from step 0 to the last completed step.
    public func recording() -> FlightRecording {
        stepState.withLock { s in
            FlightRecording(initial: initial, stepCount: s.step, events: s.journal, navData: navData.identity)
        }
    }
}
