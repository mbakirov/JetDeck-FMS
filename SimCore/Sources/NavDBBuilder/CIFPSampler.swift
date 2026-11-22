import ARINC424
import Foundation

/// Makes a small CIFP file for tests from a full file.
///
/// The sample has the header, all records of the given airports (section P, with skipped types such as MSA),
/// the en route waypoints and navaids that their procedures reference, the airways with the most of these
/// fixes (with all their fixes), and a few records of other skipped types. The lines keep the original text.
/// Only the record count in HDR01 is changed to the count of the sample.
public enum CIFPSampler {
    public static func extract(from data: Data, airports: [String], airwayLimit: Int = 4,
                               skippedTypesPerCode: Int = 3) throws(ARINC424Error) -> Data {
        let lines = CIFPFile.lines(in: data).lines
        let headerCount = lines.prefix { $0.lineClass == .header }.count
        let wanted = Set(airports)
        var selected = Set<Int>()
        var references = Set<String>()
        var skippedPerCode: [String: Int] = [:]

        for (offset, line) in lines.enumerated().dropFirst(headerCount) {
            if line.character(5) == "P", wanted.contains(line.text(7...10)) {
                selected.insert(offset)
                if case .primary(let kind) = line.lineClass, [.sid, .star, .approach].contains(kind),
                   let leg = try? ProcedureLegRecord(line) {
                    for reference in [leg.fix, leg.recommendedNavaid, leg.centerFix].compactMap({ $0 }) {
                        references.insert(key(reference.code, reference.ident, reference.region))
                    }
                }
            } else if case .other(let code) = line.lineClass, !code.hasPrefix("P") {
                if skippedPerCode[code, default: 0] < skippedTypesPerCode {
                    skippedPerCode[code, default: 0] += 1
                    selected.insert(offset)
                }
            }
        }

        // Airways with the most fixes that the procedures reference. All fixes of these airways are added.
        var airwayFixes: [String: [Int]] = [:]
        var airwayHits: [String: Int] = [:]
        for (offset, line) in lines.enumerated().dropFirst(headerCount) where line.code == "ER" {
            let route = line.text(14...18)
            airwayFixes[route, default: []].append(offset)
            if references.contains(airwayFixKey(line)) {
                airwayHits[route, default: 0] += 1
            }
        }
        let airways = airwayHits.filter { $0.value >= 2 }.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(airwayLimit)
        for (route, _) in airways {
            for offset in airwayFixes[route] ?? [] {
                selected.insert(offset)
                references.insert(airwayFixKey(lines[offset]))
            }
        }

        // En route fixes that the procedures and the airways reference.
        for (offset, line) in lines.enumerated().dropFirst(headerCount) {
            let code = line.code
            guard code == "EA" || code == "D" || code == "DB" else { continue }
            if references.contains(key(code, line.text(14...(code == "EA" ? 18 : 17)), line.text(20...21))) {
                selected.insert(offset)
            }
        }

        var output = Data()
        for (offset, line) in lines.prefix(headerCount).enumerated() {
            var bytes = line.bytes
            if offset == 0 {
                // Record count in HDR01, columns 29-35.
                let count = Array(String(format: "%07d", selected.count).utf8)
                bytes.replaceSubrange(28..<35, with: count)
            }
            output.append(contentsOf: bytes)
            output.append(contentsOf: [0x0D, 0x0A])
        }
        for offset in selected.sorted() {
            output.append(contentsOf: lines[offset].bytes)
            output.append(contentsOf: [0x0D, 0x0A])
        }
        return output
    }

    private static func airwayFixKey(_ line: ARINC424Line) -> String {
        let code = line.character(38) == " " ? String(line.character(37)) : line.raw(37...38)
        return key(code, line.text(30...34), line.text(35...36))
    }

    private static func key(_ code: String, _ ident: String, _ region: String) -> String {
        "\(code)|\(ident)|\(region)"
    }
}
