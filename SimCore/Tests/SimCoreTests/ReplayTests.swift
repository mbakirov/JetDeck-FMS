import Foundation
import Testing
@testable import SimCore

@Test func syntheticRecordingIsDeterministicAndValid() throws {
    let first = SyntheticRecording.make(steps: 5000, eventCount: 200, seed: 9)
    let second = SyntheticRecording.make(steps: 5000, eventCount: 200, seed: 9)
    #expect(first == second)
    #expect(first != SyntheticRecording.make(steps: 5000, eventCount: 200, seed: 10))
    #expect(first.events.count == 200)
    #expect(InputEvent.samples.allSatisfy { sample in first.events.contains { $0.event == sample } })
    #expect(try FlightRecording.load(from: first.encoded()) == first)
}

/// Acceptance criterion: two replays of one recording give the same snapshot at each step.
@Test func twoReplaysGiveTheSameSnapshots() throws {
    let recording = SyntheticRecording.make(steps: 5000, eventCount: 200, seed: 9)
    var first: [Snapshot] = []
    var second: [Snapshot] = []
    try Replayer.run(recording) { first.append($0) }
    try Replayer.run(recording) { second.append($0) }

    #expect(first.count == 5000)
    #expect(first.map(\.step) == Array(1...5000))
    #expect(first == second)
    // The bytes are equal too. The check of each 100th step keeps the test fast.
    for index in stride(from: 0, to: first.count, by: 100) {
        #expect(try SimCoreJSON.encode(first[index]) == SimCoreJSON.encode(second[index]))
    }
    #expect(try Replayer.snapshotsJSONL(recording) == Replayer.snapshotsJSONL(recording))
}

@Test func replayGivesTheSnapshotsOfTheOriginalFlight() throws {
    // The original flight: events are sent between steps, as the application does.
    let source = SyntheticRecording.make(steps: 2000, eventCount: 150, seed: 4)
    let engine = SimEngine(initial: source.initial)
    var original: [Snapshot] = []
    var next = 0
    for step in 1...UInt64(2000) {
        while next < source.events.count, source.events[next].step == step {
            engine.send(source.events[next].event)
            next += 1
        }
        original.append(engine.step())
    }

    // The recording goes through a file and is replayed.
    let recording = try FlightRecording.load(from: engine.recording().encoded())
    var replayed: [Snapshot] = []
    let replayEngine = try Replayer.run(recording) { replayed.append($0) }

    #expect(replayed == original)
    #expect(replayEngine.recording() == recording)
}

@Test func replayRejectsOtherContractVersion() {
    var recording = SyntheticRecording.make(steps: 10, eventCount: 2, seed: 1)
    recording.schemaVersion = contractSchemaVersion + 1
    #expect(throws: RecordingError.schemaVersionMismatch(found: contractSchemaVersion + 1, expected: contractSchemaVersion)) {
        try Replayer.run(recording)
    }
}

@Test func snapshotsJSONLHasEachNthStepAndTheLastStep() throws {
    let recording = SyntheticRecording.make(steps: 130, eventCount: 10, seed: 1)
    let data = try Replayer.snapshotsJSONL(recording, every: 50)
    let steps = try data.split(separator: 0x0A).map { try SimCoreJSON.decode(Snapshot.self, from: Data($0)).step }
    #expect(steps == [50, 100, 130])
}
