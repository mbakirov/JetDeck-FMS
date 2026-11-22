import Foundation
import Kernel
import Synchronization
@testable import SimCore

let testInitial = InitialConditions(
    scenarioID: "test", settings: CoreSettings(radioHeightCallouts: [50, 40, 30, 20, 10]),
    utcStartSecondsOfDay: 3600, seed: 1
)

/// A list that is safe to change from any thread.
final class Log<Element: Sendable>: Sendable {
    private let items = Mutex<[Element]>([])

    func append(_ item: Element) {
        items.withLock { $0.append(item) }
    }

    var all: [Element] {
        items.withLock { $0 }
    }
}

struct SeenStep: Sendable, Equatable {
    var module: String
    var step: UInt64
    var events: [InputEvent]
}

/// Writes the data of each step to a log.
struct WorldSpy: SimModule {
    static var section: WritableKeyPath<SimState, WorldState> { \.world }
    let log: Log<SeenStep>

    mutating func step(_ section: inout WorldState, reading state: SimState, context: StepContext) {
        log.append(SeenStep(module: "World", step: context.step, events: context.events))
    }
}

struct DisplaysSpy: SimModule {
    static var section: WritableKeyPath<SimState, DisplaysState> { \.displays }
    let log: Log<SeenStep>

    mutating func step(_ section: inout DisplaysState, reading state: SimState, context: StepContext) {
        log.append(SeenStep(module: "Displays", step: context.step, events: context.events))
        // Makes the snapshot depend on the events. A replay test can then find a lost event.
        section.fcu.altitudeFt += context.events.count
    }
}
