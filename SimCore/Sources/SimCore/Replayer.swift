import Foundation

/// Replays a flight recording without UI.
public enum Replayer {
    /// Runs all steps of the recording. Calls `onSnapshot` after each step.
    /// Returns the engine after the last step.
    @discardableResult
    public static func run(
        _ recording: FlightRecording,
        onSnapshot: (Snapshot) throws -> Void = { _ in }
    ) throws -> SimEngine {
        guard recording.schemaVersion == contractSchemaVersion else {
            throw RecordingError.schemaVersionMismatch(found: recording.schemaVersion, expected: contractSchemaVersion)
        }
        let engine = SimEngine(initial: recording.initial)
        var next = recording.events.startIndex
        var step: UInt64 = 0
        while step < recording.stepCount {
            step += 1
            while next < recording.events.endIndex, recording.events[next].step == step {
                engine.send(recording.events[next].event)
                next += 1
            }
            try onSnapshot(engine.step())
        }
        guard next == recording.events.endIndex else {
            throw RecordingError.malformed("event at step \(recording.events[next].step) is out of order or after the last step")
        }
        return engine
    }

    /// Replays the recording and returns snapshots as JSON lines (one snapshot on each line).
    /// The output has each step that is a multiple of `every`, and the last step.
    public static func snapshotsJSONL(_ recording: FlightRecording, every: UInt64 = 50) throws -> Data {
        let encoder = SimCoreJSON.makeEncoder()
        let interval = max(every, 1)
        var output = Data()
        try run(recording) { snapshot in
            if snapshot.step % interval == 0 || snapshot.step == recording.stepCount {
                output.append(try encoder.encode(snapshot))
                output.append(0x0A)
            }
        }
        return output
    }
}
