import Foundation
import SimCoreContract
import SnapshotDiff
import Testing

let testInitial = InitialConditions(
    scenarioID: "test", settings: CoreSettings(radioHeightCallouts: []), utcStartSecondsOfDay: 0, seed: 0
)

func base() -> Snapshot {
    var snapshot = Snapshot.initial(testInitial)
    snapshot.step = 10
    snapshot.pfd.speed.casKt = 140
    snapshot.ewd.engines[1].n1Percent = 55
    return snapshot
}

@Test func equalSnapshotsHaveNoDifferences() throws {
    #expect(try SnapshotDiff.diff(expected: base(), actual: base()).isEmpty)
}

@Test func oneChangedFieldGivesOnePath() throws {
    var actual = base()
    actual.pfd.speed.casKt = 141.5
    let differences = try SnapshotDiff.diff(expected: base(), actual: actual)
    #expect(differences == [SnapshotDifference(path: "pfd.speed.casKt", expected: "140", actual: "141.5")])
    #expect(differences[0].description == "pfd.speed.casKt: expected 140, actual 141.5")
}

@Test func toleranceAppliesToNumbers() throws {
    var actual = base()
    actual.pfd.speed.casKt = 140.004
    actual.ewd.engines[1].n1Percent = 55.04
    #expect(try SnapshotDiff.diff(expected: base(), actual: actual).count == 2)
    #expect(try SnapshotDiff.diff(expected: base(), actual: actual, options: DiffOptions(defaultTolerance: 0.05)).isEmpty)

    // A tolerance for one field. The key has no array index.
    let options = DiffOptions(tolerances: ["ewd.engines.n1Percent": 0.05])
    #expect(try SnapshotDiff.diff(expected: base(), actual: actual, options: options).map(\.path) == ["pfd.speed.casKt"])
}

@Test func toleranceDoesNotApplyToTextAndFlags() throws {
    var actual = base()
    actual.controls.gearLever = .down
    actual.controls.masterWarningLit = true
    let differences = try SnapshotDiff.diff(expected: base(), actual: actual, options: DiffOptions(defaultTolerance: 1000))
    #expect(differences.map(\.path) == ["controls.gearLever", "controls.masterWarningLit"])
}

@Test func absentAndAddedFieldsAreReported() throws {
    var actual = base()
    actual.pfd.speed.casKt = nil
    actual.pfd.pitchDeg = 3
    let differences = try SnapshotDiff.diff(expected: base(), actual: actual)
    #expect(differences == [
        SnapshotDifference(path: "pfd.pitchDeg", expected: "<absent>", actual: "3"),
        SnapshotDifference(path: "pfd.speed.casKt", expected: "140", actual: "<absent>"),
    ])
}

@Test func arraysOfDifferentLengthAreReported() throws {
    var actual = base()
    actual.pfd.flags = [TextLine(text: "CHECK ALT", color: .amber)]
    actual.ewd.engines[1].n1Percent = 56
    let differences = try SnapshotDiff.diff(expected: base(), actual: actual)
    #expect(differences == [
        SnapshotDifference(path: "ewd.engines[1].n1Percent", expected: "55", actual: "56"),
        SnapshotDifference(path: "pfd.flags.count", expected: "0", actual: "1"),
    ])
}

@Test func jsonLinesComparison() throws {
    func file(_ snapshots: [Snapshot]) throws -> Data {
        var data = Data()
        for snapshot in snapshots {
            data.append(try SimCoreJSON.encode(snapshot))
            data.append(0x0A)
        }
        return data
    }
    var second = base()
    second.step = 20
    var changed = second
    changed.fcu.altitudeFt = 5000

    #expect(try SnapshotDiff.diffJSONL(expected: file([base(), second]), actual: file([base(), second])).isEmpty)

    let differences = try SnapshotDiff.diffJSONL(expected: file([base(), second]), actual: file([base(), changed]))
    #expect(differences == [StepDifferences(step: 20, differences: [
        SnapshotDifference(path: "fcu.altitudeFt", expected: "0", actual: "5000"),
    ])])
    let report = SnapshotDiff.report(differences)
    #expect(report.contains("step 20: fcu.altitudeFt: expected 0, actual 5000"))

    let shorter = try SnapshotDiff.diffJSONL(expected: file([base(), second]), actual: file([base()]))
    #expect(shorter.first?.differences.first?.path == "<number of snapshots>")
    #expect(SnapshotDiff.report([]) == "No differences.")
}
