import Foundation
import NavDB
import NavDBBuilder
import NavDBUpdate
import SimCoreContract

// Command-line tool of the navigation database: conversion of CIFP, checks, timing, manifest, test samples.

let usage = """
usage:
  navdb-cli convert --cifp <FAACIFP18> --out <navdb.sqlite> [--report <report.json>]
  navdb-cli verify --cifp <FAACIFP18> --db <navdb.sqlite> [--report <verify.json>] [--sample <N>]
  navdb-cli bench --db <navdb.sqlite> [--radius <NM>] [--repeat <N>] [--out <report.json>] [--max-p99-ms <ms>]
  navdb-cli manifest --db <navdb.sqlite> --url <file URL in the manifest> --out <manifest.json> [--notices <notices.json>]
  navdb-cli extract-sample --cifp <FAACIFP18> --airports <K1,K2,...> --out <sample file>
"""

struct CLIError: Error, CustomStringConvertible {
    var description: String
}

struct Arguments {
    var command: String
    var options: [String: String] = [:]

    init(_ raw: [String]) throws {
        guard let first = raw.first else { throw CLIError(description: usage) }
        command = first
        var index = 1
        while index < raw.count {
            let item = raw[index]
            guard item.hasPrefix("--"), index + 1 < raw.count else {
                throw CLIError(description: "unexpected argument \(item)\n\(usage)")
            }
            options[String(item.dropFirst(2))] = raw[index + 1]
            index += 2
        }
    }

    func required(_ name: String) throws -> String {
        guard let value = options[name] else { throw CLIError(description: "missing option --\(name)\n\(usage)") }
        return value
    }

    func number<T: LosslessStringConvertible>(_ name: String, default value: T) throws -> T {
        guard let text = options[name] else { return value }
        guard let parsed = T(text) else { throw CLIError(description: "option --\(name) has a bad value: \(text)") }
        return parsed
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

func writeJSON<T: Encodable>(_ value: T, to path: String) throws {
    let encoder = SimCoreJSON.makeEncoder()
    encoder.outputFormatting.insert(.prettyPrinted)
    try write(encoder.encode(value), to: path)
}

func convert(_ arguments: Arguments) throws -> Int32 {
    let cifpPath = try arguments.required("cifp")
    let output = try arguments.required("out")
    try FileManager.default.createDirectory(at: URL(fileURLWithPath: output).deletingLastPathComponent(), withIntermediateDirectories: true)
    let report = try NavDBBuilder.build(cifp: read(cifpPath), sourceFileName: URL(fileURLWithPath: cifpPath).lastPathComponent,
                                        output: output)
    if let path = arguments.options["report"] {
        try writeJSON(report, to: path)
    }
    print(report.summary)
    if report.errorCount > 0 {
        print("first errors:\n  " + report.errors.prefix(20).joined(separator: "\n  "))
        return 1
    }
    return 0
}

func verify(_ arguments: Arguments) throws -> Int32 {
    let reader = try NavDatabaseReader(path: arguments.required("db"))
    try reader.checkIntegrity()
    let report = try NavDBVerifier.verify(cifp: read(arguments.required("cifp")), database: reader,
                                          sampleSize: try arguments.number("sample", default: 20))
    if let path = arguments.options["report"] {
        try writeJSON(report, to: path)
    }
    print(report.summary)
    if !report.passed {
        let problems = report.airportMismatches.prefix(20) + report.routeMismatches.prefix(20) + report.valueMismatches.prefix(20)
        print("first problems:\n  " + problems.joined(separator: "\n  "))
    }
    return report.passed ? 0 : 1
}

func bench(_ arguments: Arguments) throws -> Int32 {
    let reader = try NavDatabaseReader(path: arguments.required("db"))
    let report = try NavDBBench.run(reader, radiusNM: try arguments.number("radius", default: 320.0),
                                    repeatCount: try arguments.number("repeat", default: 50))
    if let path = arguments.options["out"] {
        try writeJSON(report, to: path)
    }
    print(report.summary)
    if let limit = arguments.options["max-p99-ms"].flatMap(Double.init), report.p99Microseconds > limit * 1000 {
        print("FAILED: p99 \(Int(report.p99Microseconds)) µs is above the threshold \(limit) ms")
        return 1
    }
    return 0
}

func manifest(_ arguments: Arguments) throws -> Int32 {
    var notices: [NavDataNotice] = []
    if let path = arguments.options["notices"] {
        notices = try SimCoreJSON.decode([NavDataNotice].self, from: read(path))
    }
    let manifest = try NavDBManifest.make(databasePath: arguments.required("db"), url: arguments.required("url"), notices: notices)
    try manifest.validate()
    try writeJSON(manifest, to: arguments.required("out"))
    print("manifest: AIRAC \(manifest.cycle.ident) (\(manifest.effective) – \(manifest.lastDay)), \(manifest.url), \(manifest.sizeBytes) bytes, SHA-256 \(manifest.sha256), \(notices.count) notices")
    return 0
}

func extractSample(_ arguments: Arguments) throws -> Int32 {
    let airports = try arguments.required("airports").split(separator: ",").map(String.init)
    let sample = try CIFPSampler.extract(from: read(arguments.required("cifp")), airports: airports)
    try write(sample, to: arguments.required("out"))
    print("sample: \(sample.count / (132 + 2)) lines, airports \(airports.joined(separator: " "))")
    return 0
}

func main() -> Int32 {
    do {
        let arguments = try Arguments(Array(CommandLine.arguments.dropFirst()))
        switch arguments.command {
        case "convert": return try convert(arguments)
        case "verify": return try verify(arguments)
        case "bench": return try bench(arguments)
        case "manifest": return try manifest(arguments)
        case "extract-sample": return try extractSample(arguments)
        default: throw CLIError(description: "unknown command \(arguments.command)\n\(usage)")
        }
    } catch {
        FileHandle.standardError.write(Data("error: \(error)\n".utf8))
        return 2
    }
}

exit(main())
