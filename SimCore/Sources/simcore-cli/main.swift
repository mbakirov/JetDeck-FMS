import Foundation
import Kernel
import NavDB
import SimCore
import SnapshotDiff

// Command-line tool of the SimCore package: replay of recordings, comparison of snapshots, step timing.

let usage = """
usage:
  simcore-cli replay <recording.json> [--out <snapshots.jsonl>] [--every <N>] [--navdb <navdb.sqlite>]
  simcore-cli diff <expected.jsonl> <actual.jsonl> [--tolerance <X>]
  simcore-cli bench [--steps <N>] [--out <report.json>]
  simcore-cli gen-recording --out <recording.json> [--steps <N>] [--events <N>] [--seed <N>]
  simcore-cli golden-update <goldens directory> [--every <N>]
"""

struct CLIError: Error, CustomStringConvertible {
    var description: String
}

struct Arguments {
    var positional: [String] = []
    var options: [String: String] = [:]

    init(_ raw: [String]) throws {
        var index = 0
        while index < raw.count {
            let item = raw[index]
            if item.hasPrefix("--") {
                guard index + 1 < raw.count else { throw CLIError(description: "option \(item) needs a value") }
                options[String(item.dropFirst(2))] = raw[index + 1]
                index += 2
            } else {
                positional.append(item)
                index += 1
            }
        }
    }

    func number<T: LosslessStringConvertible>(_ name: String, default value: T) throws -> T {
        guard let text = options[name] else { return value }
        guard let parsed = T(text) else { throw CLIError(description: "option --\(name) has a bad value: \(text)") }
        return parsed
    }

    func positional(_ index: Int, _ name: String) throws -> String {
        guard index < positional.count else { throw CLIError(description: "missing argument: \(name)\n\(usage)") }
        return positional[index]
    }
}

func read(_ path: String) throws -> Data {
    try Data(contentsOf: URL(fileURLWithPath: path))
}

func write(_ data: Data, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

func replay(_ arguments: Arguments) throws {
    let recording = try FlightRecording.load(from: read(arguments.positional(0, "recording.json")))
    let every: UInt64 = try arguments.number("every", default: 50)
    let navData: any NavDatabase = try arguments.options["navdb"].map { try NavDatabaseReader(path: $0) } ?? EmptyNavDatabase()
    let output = try Replayer.snapshotsJSONL(recording, every: every, navData: navData)
    if let path = arguments.options["out"] {
        try write(output, to: path)
        print("Replayed \(recording.stepCount) steps, \(recording.events.count) events. Snapshots: \(path)")
    } else {
        FileHandle.standardOutput.write(output)
    }
}

func diff(_ arguments: Arguments) throws -> Int32 {
    let expected = try read(arguments.positional(0, "expected.jsonl"))
    let actual = try read(arguments.positional(1, "actual.jsonl"))
    let options = DiffOptions(defaultTolerance: try arguments.number("tolerance", default: 0.0))
    let differences = try SnapshotDiff.diffJSONL(expected: expected, actual: actual, options: options)
    print(SnapshotDiff.report(differences))
    return differences.isEmpty ? 0 : 1
}

func bench(_ arguments: Arguments) throws {
    let steps: UInt64 = try arguments.number("steps", default: 30_000)
    let path = arguments.options["out"] ?? "build/reports/step-timing.json"
    let recording = SyntheticRecording.make(steps: steps, eventCount: Int(steps / 100), seed: 1)
    let engine = SimEngine(initial: recording.initial)
    let clock = ContinuousClock()
    var micros: [Double] = []
    micros.reserveCapacity(Int(steps))
    var next = recording.events.startIndex
    for step in 1...max(steps, 1) {
        while next < recording.events.endIndex, recording.events[next].step == step {
            engine.send(recording.events[next].event)
            next += 1
        }
        let duration = clock.measure { engine.step() }
        micros.append(Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) * 1e-12)
    }
    micros.sort()
    func percentile(_ p: Double) -> Double {
        micros[min(micros.count - 1, Int((Double(micros.count) * p).rounded(.down)))]
    }
    func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
    let budget = simStepSeconds * 1e6
    let report: [String: Double] = [
        "steps": Double(micros.count),
        "budgetMicros": budget,
        "meanMicros": rounded(micros.reduce(0, +) / Double(micros.count)),
        "p50Micros": rounded(percentile(0.50)),
        "p99Micros": rounded(percentile(0.99)),
        "maxMicros": rounded(micros.last ?? 0),
    ]
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
    try write(try encoder.encode(report), to: path)
    let markdown = """
    ### SimCore step time

    | Steps | Mean | p50 | p99 | Max | Budget |
    |---|---|---|---|---|---|
    | \(micros.count) | \(report["meanMicros"]!) µs | \(report["p50Micros"]!) µs | \(report["p99Micros"]!) µs | \(report["maxMicros"]!) µs | \(Int(budget)) µs |

    """
    let markdownPath = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("md").path
    try write(Data(markdown.utf8), to: markdownPath)
    print(markdown)
    print("Report: \(path)")
}

func genRecording(_ arguments: Arguments) throws {
    guard let path = arguments.options["out"] else { throw CLIError(description: "missing option --out\n\(usage)") }
    let recording = SyntheticRecording.make(
        steps: try arguments.number("steps", default: 30_000),
        eventCount: try arguments.number("events", default: 300),
        seed: try arguments.number("seed", default: 1),
        scenarioID: URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
    )
    try write(try recording.encoded(), to: path)
    print("Recording: \(path) (\(recording.stepCount) steps, \(recording.events.count) events)")
}

func goldenUpdate(_ arguments: Arguments) throws {
    let root = URL(fileURLWithPath: try arguments.positional(0, "goldens directory"))
    let every: UInt64 = try arguments.number("every", default: 1000)
    let directories = try FileManager.default
        .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("recording.json").path) }
        .sorted { $0.path < $1.path }
    for directory in directories {
        let recording = try FlightRecording.load(from: Data(contentsOf: directory.appendingPathComponent("recording.json")))
        let output = try Replayer.snapshotsJSONL(recording, every: every)
        try output.write(to: directory.appendingPathComponent("snapshots.jsonl"))
        print("Updated \(directory.lastPathComponent): \(SnapshotDiff.lines(of: output).count) snapshots")
    }
    if directories.isEmpty {
        print("No recordings in \(root.path)")
    }
}

func main() -> Int32 {
    var raw = Array(CommandLine.arguments.dropFirst())
    guard !raw.isEmpty else {
        print(usage)
        return 2
    }
    let command = raw.removeFirst()
    do {
        let arguments = try Arguments(raw)
        switch command {
        case "replay": try replay(arguments)
        case "diff": return try diff(arguments)
        case "bench": try bench(arguments)
        case "gen-recording": try genRecording(arguments)
        case "golden-update": try goldenUpdate(arguments)
        default:
            print(usage)
            return 2
        }
        return 0
    } catch let error as LocalizedError {
        FileHandle.standardError.write(Data("error: \(error.errorDescription ?? String(describing: error))\n".utf8))
        return 1
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 1
    }
}

exit(main())
