import Foundation
import SimCoreContract

/// One field that is different in two snapshots.
public struct SnapshotDifference: Sendable, Equatable, CustomStringConvertible {
    /// Example: `pfd.speed.casKt` or `ewd.engines[1].n1Percent`.
    public var path: String
    public var expected: String
    public var actual: String

    public init(path: String, expected: String, actual: String) {
        self.path = path
        self.expected = expected
        self.actual = actual
    }

    public var description: String {
        "\(path): expected \(expected), actual \(actual)"
    }
}

public struct DiffOptions: Sendable {
    /// Permitted absolute difference for numbers. 0 is an exact comparison.
    public var defaultTolerance: Double
    /// Permitted difference for specified fields. The key is a path without array indexes.
    /// Example: `["pfd.speed.casKt": 0.01, "ewd.engines.n1Percent": 0.05]`.
    public var tolerances: [String: Double]

    public init(defaultTolerance: Double = 0, tolerances: [String: Double] = [:]) {
        self.defaultTolerance = defaultTolerance
        self.tolerances = tolerances
    }

    public static let exact = DiffOptions()

    func tolerance(forKey key: String) -> Double {
        tolerances[key] ?? defaultTolerance
    }
}

/// The differences of one step.
public struct StepDifferences: Sendable, Equatable {
    /// nil if the step number is not known.
    public var step: UInt64?
    public var differences: [SnapshotDifference]

    public init(step: UInt64?, differences: [SnapshotDifference]) {
        self.step = step
        self.differences = differences
    }
}

public enum SnapshotDiff {
    static let absent = "<absent>"

    public static func diff(
        expected: Snapshot, actual: Snapshot, options: DiffOptions = .exact
    ) throws -> [SnapshotDifference] {
        try diff(expectedJSON: SimCoreJSON.encode(expected), actualJSON: SimCoreJSON.encode(actual), options: options)
    }

    public static func diff(
        expectedJSON: Data, actualJSON: Data, options: DiffOptions = .exact
    ) throws -> [SnapshotDifference] {
        let decoder = JSONDecoder()
        let expected = try decoder.decode(JSONValue.self, from: expectedJSON)
        let actual = try decoder.decode(JSONValue.self, from: actualJSON)
        return diff(expected: expected, actual: actual, options: options)
    }

    public static func diff(
        expected: JSONValue, actual: JSONValue, options: DiffOptions = .exact
    ) -> [SnapshotDifference] {
        var result: [SnapshotDifference] = []
        walk(expected, actual, path: "", key: "", options: options, into: &result)
        return result
    }

    /// Compares two files of JSON lines. Each line is one snapshot.
    public static func diffJSONL(
        expected: Data, actual: Data, options: DiffOptions = .exact
    ) throws -> [StepDifferences] {
        let expectedLines = lines(of: expected)
        let actualLines = lines(of: actual)
        var result: [StepDifferences] = []
        if expectedLines.count != actualLines.count {
            result.append(StepDifferences(step: nil, differences: [
                SnapshotDifference(
                    path: "<number of snapshots>",
                    expected: String(expectedLines.count), actual: String(actualLines.count)
                ),
            ]))
        }
        let decoder = JSONDecoder()
        for (expectedLine, actualLine) in zip(expectedLines, actualLines) where expectedLine != actualLine {
            let expectedValue = try decoder.decode(JSONValue.self, from: expectedLine)
            let actualValue = try decoder.decode(JSONValue.self, from: actualLine)
            let differences = diff(expected: expectedValue, actual: actualValue, options: options)
            if !differences.isEmpty {
                result.append(StepDifferences(step: stepNumber(of: expectedValue), differences: differences))
            }
        }
        return result
    }

    /// A report that a person can read.
    public static func report(_ steps: [StepDifferences], limit: Int = 50) -> String {
        guard !steps.isEmpty else { return "No differences." }
        var lines: [String] = []
        var count = 0
        for item in steps {
            for difference in item.differences {
                count += 1
                if lines.count < limit {
                    let step = item.step.map { "step \($0)" } ?? "file"
                    lines.append("\(step): \(difference)")
                }
            }
        }
        if count > limit {
            lines.append("... and \(count - limit) more differences")
        }
        lines.append("\(count) differences in \(steps.count) snapshots.")
        return lines.joined(separator: "\n")
    }

    public static func stepNumber(of snapshot: JSONValue) -> UInt64? {
        guard case .object(let fields) = snapshot, case .number(let step)? = fields["step"], step >= 0 else {
            return nil
        }
        return UInt64(step)
    }

    public static func lines(of data: Data) -> [Data] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).map { Data($0) }
    }

    private static func walk(
        _ expected: JSONValue, _ actual: JSONValue,
        path: String, key: String, options: DiffOptions,
        into result: inout [SnapshotDifference]
    ) {
        switch (expected, actual) {
        case (.number(let a), .number(let b)):
            if a != b, !(abs(a - b) <= options.tolerance(forKey: key)) {
                result.append(SnapshotDifference(path: path, expected: expected.summary, actual: actual.summary))
            }
        case (.object(let a), .object(let b)):
            for name in Set(a.keys).union(b.keys).sorted() {
                let childPath = path.isEmpty ? name : "\(path).\(name)"
                let childKey = key.isEmpty ? name : "\(key).\(name)"
                switch (a[name], b[name]) {
                case (let x?, let y?):
                    walk(x, y, path: childPath, key: childKey, options: options, into: &result)
                case (let x?, nil):
                    result.append(SnapshotDifference(path: childPath, expected: x.summary, actual: absent))
                case (nil, let y?):
                    result.append(SnapshotDifference(path: childPath, expected: absent, actual: y.summary))
                case (nil, nil):
                    break
                }
            }
        case (.array(let a), .array(let b)):
            if a.count != b.count {
                result.append(SnapshotDifference(
                    path: path + ".count", expected: String(a.count), actual: String(b.count)
                ))
            }
            for (index, pair) in zip(a, b).enumerated() {
                walk(pair.0, pair.1, path: "\(path)[\(index)]", key: key, options: options, into: &result)
            }
        default:
            if expected != actual {
                result.append(SnapshotDifference(path: path, expected: expected.summary, actual: actual.summary))
            }
        }
    }
}
