import Foundation

/// The state of the core before the first step.
/// The same initial conditions and the same events always give the same snapshots.
public struct InitialConditions: Sendable, Codable, Equatable {
    public var scenarioID: String
    public var settings: CoreSettings
    /// UTC time at step 0, in seconds from midnight.
    public var utcStartSecondsOfDay: Int
    /// Seed for all random effects (wind, turbulence). The core has no other source of randomness.
    public var seed: UInt64

    public init(scenarioID: String, settings: CoreSettings, utcStartSecondsOfDay: Int, seed: UInt64) {
        self.scenarioID = scenarioID
        self.settings = settings
        self.utcStartSecondsOfDay = utcStartSecondsOfDay
        self.seed = seed
    }
}

/// A full flight recording: the initial conditions and all input events.
/// A replay of the recording gives the same snapshots as the original flight.
public struct FlightRecording: Sendable, Codable, Equatable {
    /// The value of `contractSchemaVersion` when the recording was made.
    public var schemaVersion: Int
    public var initial: InitialConditions
    /// Number of steps in the flight.
    public var stepCount: UInt64
    /// Events in the order of application. `step` is the step that applied the event (1 is the first step).
    public var events: [RecordedEvent]

    public init(
        schemaVersion: Int = contractSchemaVersion,
        initial: InitialConditions,
        stepCount: UInt64,
        events: [RecordedEvent]
    ) {
        self.schemaVersion = schemaVersion
        self.initial = initial
        self.stepCount = stepCount
        self.events = events
    }
}

public enum RecordingError: Error, Equatable, LocalizedError {
    case schemaVersionMismatch(found: Int, expected: Int)
    case malformed(String)

    public var errorDescription: String? {
        switch self {
        case .schemaVersionMismatch(let found, let expected):
            "Recording has contract version \(found). This build supports version \(expected). The recording cannot be replayed."
        case .malformed(let reason):
            "Recording is not valid: \(reason)"
        }
    }
}

extension FlightRecording {
    private struct Header: Decodable {
        var schemaVersion: Int
    }

    public func encoded() throws -> Data {
        try SimCoreJSON.encode(self)
    }

    /// Reads a recording. The contract version is checked before the other data.
    public static func load(from data: Data) throws(RecordingError) -> FlightRecording {
        let header: Header
        do {
            header = try SimCoreJSON.decode(Header.self, from: data)
        } catch {
            throw .malformed("the contract version is not readable")
        }
        guard header.schemaVersion == contractSchemaVersion else {
            throw .schemaVersionMismatch(found: header.schemaVersion, expected: contractSchemaVersion)
        }
        let recording: FlightRecording
        do {
            recording = try SimCoreJSON.decode(FlightRecording.self, from: data)
        } catch {
            throw .malformed(String(describing: error))
        }
        var previous: UInt64 = 1
        for item in recording.events {
            guard item.step >= previous, item.step <= recording.stepCount else {
                throw .malformed("event at step \(item.step) is out of order or after the last step \(recording.stepCount)")
            }
            previous = item.step
        }
        return recording
    }
}
