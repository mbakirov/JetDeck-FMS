import Foundation

/// Makes a recording with pseudo-random input events. Tests and reference recordings use it.
/// The same arguments always give the same recording.
public enum SyntheticRecording {
    public static func make(
        steps: UInt64,
        eventCount: Int,
        seed: UInt64,
        scenarioID: String = "synthetic"
    ) -> FlightRecording {
        var generator = SplitMix64(state: seed)
        let pool = InputEvent.samples
        var events: [RecordedEvent] = []
        if steps > 0 {
            // The first events cover all kinds of event. The other events are random.
            for index in 0..<eventCount {
                let event = index < pool.count ? pool[index] : pool[Int(generator.next() % UInt64(pool.count))]
                events.append(RecordedEvent(step: 1 + generator.next() % steps, event: event))
            }
        }
        // The sort is stable for equal steps because the index is part of the key.
        let ordered = events.enumerated()
            .sorted { ($0.element.step, $0.offset) < ($1.element.step, $1.offset) }
            .map(\.element)
        let initial = InitialConditions(
            scenarioID: scenarioID,
            settings: CoreSettings(radioHeightCallouts: [100, 50, 40, 30, 20, 10]),
            utcStartSecondsOfDay: 12 * 3600,
            seed: seed
        )
        return FlightRecording(initial: initial, stepCount: steps, events: ordered)
    }
}

/// A small deterministic random number generator.
struct SplitMix64 {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
