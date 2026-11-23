import ARINC424
import Foundation
import Kernel

/// The record of one point and its data.
enum FixPayload: Sendable {
    case airport(AirportRecord)
    case runway(RunwayRecord)
    case localizer(LocalizerRecord)
    case vhf(VHFNavaidRecord)
    case ndb(NDBRecord)
    case waypoint(WaypointRecord)
}

/// A point of the source file. The source line identifies it.
struct FixSource: Sendable {
    var line: Int
    /// ARINC 424 code of the record, for example `PC`, `EA`, `D`.
    var code: String
    var kind: NavFixKind
    var ident: String
    var region: String
    var airport: String?
    var position: ARINC424Coordinate
    var navaidType: NavaidType?
    var payload: FixPayload
}

/// All points of the source file and the resolution of references to them.
struct FixCatalog {
    private(set) var sources: [Int: FixSource] = [:]
    /// code → identifier → source lines in file order.
    private var index: [String: [String: [Int]]] = [:]

    init(_ content: CIFPContent) {
        for r in content.airports {
            add(FixSource(line: r.line, code: "PA", kind: .airport, ident: r.ident, region: r.region, airport: r.ident,
                          position: r.position, payload: .airport(r)))
        }
        for r in content.runways {
            add(FixSource(line: r.line, code: "PG", kind: .runway, ident: r.ident, region: r.airportRegion, airport: r.airport,
                          position: r.threshold, payload: .runway(r)))
        }
        for r in content.localizers {
            add(FixSource(line: r.line, code: "PI", kind: .localizer, ident: r.ident, region: r.airportRegion, airport: r.airport,
                          position: r.localizerPosition, payload: .localizer(r)))
        }
        for r in content.vhfNavaids {
            add(FixSource(line: r.line, code: "D", kind: .vhfNavaid, ident: r.ident, region: r.region, airport: r.airport,
                          position: r.position, navaidType: Self.vhfType(r.navaidClass), payload: .vhf(r)))
        }
        for r in content.enrouteNDBs {
            add(FixSource(line: r.line, code: "DB", kind: .ndb, ident: r.ident, region: r.region, airport: nil,
                          position: r.position, navaidType: Self.ndbType(r.navaidClass), payload: .ndb(r)))
        }
        for r in content.terminalNDBs {
            add(FixSource(line: r.line, code: "PN", kind: .ndb, ident: r.ident, region: r.region, airport: r.airport,
                          position: r.position, navaidType: Self.ndbType(r.navaidClass), payload: .ndb(r)))
        }
        for r in content.enrouteWaypoints {
            add(FixSource(line: r.line, code: "EA", kind: .waypoint, ident: r.ident, region: r.region, airport: nil,
                          position: r.position, payload: .waypoint(r)))
        }
        for r in content.terminalWaypoints {
            add(FixSource(line: r.line, code: "PC", kind: .waypoint, ident: r.ident, region: r.region, airport: r.airport,
                          position: r.position, payload: .waypoint(r)))
        }
    }

    private mutating func add(_ source: FixSource) {
        sources[source.line] = source
        index[source.code, default: [:]][source.ident, default: []].append(source.line)
    }

    /// The source line of the referenced point, or nil. `airport` is the airport of the procedure, if any.
    func resolve(_ reference: FixReference, airport: String?) -> Int? {
        let candidates = (index[reference.code]?[reference.ident] ?? []).compactMap { sources[$0] }
        if candidates.isEmpty { return nil }
        switch reference.code {
        case "PG", "PI":
            // A runway or a localizer of the same airport. The region is the region of the airport.
            return candidates.first { $0.airport == airport }?.line
        case "PA":
            return candidates.first { $0.region == reference.region }?.line ?? candidates.first?.line
        case "PC", "PN", "D":
            let inRegion = candidates.filter { $0.region == reference.region }
            // Priority: the same airport, then an en route point, then a point of another airport.
            return inRegion.first { $0.airport != nil && $0.airport == airport }?.line
                ?? inRegion.first { $0.airport == nil }?.line
                ?? inRegion.first?.line
        default:
            return candidates.first { $0.region == reference.region }?.line
        }
    }

    static func vhfType(_ navaidClass: String) -> NavaidType {
        let c = Array(navaidClass)
        let first = c.count > 0 ? c[0] : " "
        let second = c.count > 1 ? c[1] : " "
        switch (first, second) {
        case (_, "I"): return .ilsDme
        case ("V", "D"): return .vorDme
        case ("V", "T"), ("V", "M"): return .vortac
        case ("V", _): return .vor
        case (_, "T"), (_, "M"): return .tacan
        default: return .dme
        }
    }

    static func ndbType(_ navaidClass: String) -> NavaidType {
        let c = Array(navaidClass)
        let second = c.count > 1 ? c[1] : " "
        return "IMOC".contains(second) ? .locator : .ndb
    }
}
