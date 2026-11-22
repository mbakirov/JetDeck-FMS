import Foundation
import SimCore
import SnapshotDiff
import Testing

/// Tolerances for the comparison with reference snapshots.
/// The stubs of E01 need an exact comparison. Add fields here when a module gets floating-point physics.
let goldenOptions = DiffOptions(defaultTolerance: 0, tolerances: [:])

func goldenDirectories() throws -> [URL] {
    let root = try #require(Bundle.module.url(forResource: "Goldens", withExtension: nil))
    return try FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("recording.json").path) }
        .sorted { $0.path < $1.path }
}

@Test func thereIsAtLeastOneReferenceRecording() throws {
    #expect(try !goldenDirectories().isEmpty)
}

/// Replays each reference recording and compares the snapshots with the reference file.
/// To make new reference files after an intended change: `make golden-update`.
@Test func replayMatchesReferenceSnapshots() throws {
    for directory in try goldenDirectories() {
        let name = directory.lastPathComponent
        let recording = try FlightRecording.load(from: Data(contentsOf: directory.appendingPathComponent("recording.json")))
        let golden = SnapshotDiff.lines(of: try Data(contentsOf: directory.appendingPathComponent("snapshots.jsonl")))
        try #require(!golden.isEmpty, "\(name): no reference snapshots")

        var expectedByStep: [UInt64: Data] = [:]
        for line in golden {
            let step = try SimCoreJSON.decode(Snapshot.self, from: line).step
            expectedByStep[step] = line
        }
        #expect(expectedByStep[recording.stepCount] != nil, "\(name): the last step is not in the reference file")

        var failures: [StepDifferences] = []
        var compared = 0
        let encoder = SimCoreJSON.makeEncoder()
        try Replayer.run(recording) { snapshot in
            guard let expected = expectedByStep[snapshot.step] else { return }
            compared += 1
            let differences = try SnapshotDiff.diff(
                expectedJSON: expected, actualJSON: encoder.encode(snapshot), options: goldenOptions
            )
            if !differences.isEmpty {
                failures.append(StepDifferences(step: snapshot.step, differences: differences))
            }
        }
        #expect(compared == expectedByStep.count, "\(name): reference steps that the replay did not reach")
        #expect(failures.isEmpty, "\(name):\n\(SnapshotDiff.report(failures))")
    }
}
