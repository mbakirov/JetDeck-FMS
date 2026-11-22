import ARINC424
import Foundation
import Kernel

/// The content of the database before it is written: the filter result, the points and the procedures with ids.
struct Plan {
    struct AirwayFix {
        var record: AirwayFixRecord
        var fixID: Int64?
    }

    struct Leg {
        var record: ProcedureLegRecord
        var fixID: Int64?
        var navaidID: Int64?
        var centerID: Int64?
    }

    struct Route {
        var id: Int64 = 0
        var routeType: String
        var ident: String
        var role: NavTransitionRole
        var legs: [Leg] = []
    }

    struct Procedure {
        var id: Int64 = 0
        var airport: String
        var kind: NavProcedureKind
        var ident: String
        var approachType: String?
        var runway: String?
        var routes: [Route] = []
    }

    let content: CIFPContent
    let filter: AirportFilter
    let catalog: FixCatalog

    private(set) var keptAirports: Set<String> = []
    private(set) var rejected: [String: Int] = [:]
    private(set) var rejectedShortRunway: [String] = []
    /// Points to write, in the order of the source lines.
    private(set) var fixes: [FixSource] = []
    /// Source line → row id.
    private(set) var fixID: [Int: Int64] = [:]
    private(set) var airwayFixes: [AirwayFix] = []
    private(set) var procedures: [Procedure] = []
    private(set) var unresolved: [String] = []
    private(set) var unresolvedByCode: [String: Int] = [:]
    private(set) var duplicateLegs: [String] = []
    private(set) var pathTerminators: [String: Int] = [:]
    private(set) var approachTypes: [String: Int] = [:]
    private(set) var written: [String: Int] = [:]

    init(content: CIFPContent, filter: AirportFilter) {
        self.content = content
        self.filter = filter
        self.catalog = FixCatalog(content)
    }

    mutating func make() {
        selectAirports()

        // Points of the kept airports and all en route points.
        var included = Set<Int>()
        for (line, source) in catalog.sources {
            switch source.code {
            case "EA", "DB": included.insert(line)
            case "D": if source.airport == nil || keptAirports.contains(source.airport!) { included.insert(line) }
            default: if let airport = source.airport, keptAirports.contains(airport) { included.insert(line) }
            }
        }

        // References of the airways and of the procedures of the kept airports. A referenced point of another
        // airport is also written, so that the reference is resolved.
        var airwayLines: [(AirwayFixRecord, Int?)] = []
        for record in content.airwayFixes {
            let line = resolve(record.fix, airport: nil, context: "airway \(record.route) \(record.sequence)", line: record.line)
            if let line { included.insert(line) }
            airwayLines.append((record, line))
        }
        var legLines: [(ProcedureLegRecord, Int?, Int?, Int?)] = []
        for record in content.procedureLegs where keptAirports.contains(record.airport) {
            let context = "\(record.airport) \(record.kind.rawValue) \(record.procedure) \(record.routeType)\(record.transition.isEmpty ? "" : " " + record.transition) \(record.sequence)"
            let fix = record.fix.flatMap { resolve($0, airport: record.airport, context: context + " fix", line: record.line) }
            let navaid = record.recommendedNavaid.flatMap { resolve($0, airport: record.airport, context: context + " navaid", line: record.line) }
            let center = record.centerFix.flatMap { resolve($0, airport: record.airport, context: context + " center", line: record.line) }
            for line in [fix, navaid, center].compactMap({ $0 }) { included.insert(line) }
            legLines.append((record, fix, navaid, center))
        }

        // Ids follow the order of the source lines.
        for (offset, line) in included.sorted().enumerated() {
            fixID[line] = Int64(offset + 1)
            fixes.append(catalog.sources[line]!)
        }
        airwayFixes = airwayLines.map { AirwayFix(record: $0.0, fixID: $0.1.flatMap { fixID[$0] }) }
        buildProcedures(legLines)
        count()
    }

    private mutating func selectAirports() {
        var runways: [String: [RunwayRecord]] = [:]
        for r in content.runways { runways[r.airport, default: []].append(r) }
        var localizers: [String: [LocalizerRecord]] = [:]
        for r in content.localizers { localizers[r.airport, default: []].append(r) }
        for reason in AirportFilter.Rejection.allCases { rejected[reason.rawValue] = 0 }
        for airport in content.airports {
            if let reason = filter.evaluate(airport, runways: runways[airport.ident] ?? [], localizers: localizers[airport.ident] ?? []) {
                rejected[reason.rawValue, default: 0] += 1
                if reason == .ilsRunwayTooShort { rejectedShortRunway.append(airport.ident) }
            } else {
                keptAirports.insert(airport.ident)
            }
        }
        rejectedShortRunway.sort()
    }

    private mutating func resolve(_ reference: FixReference, airport: String?, context: String, line: Int) -> Int? {
        if let resolved = catalog.resolve(reference, airport: airport) { return resolved }
        let code = reference.code.isEmpty ? "?" : reference.code
        unresolvedByCode[code, default: 0] += 1
        unresolved.append("\(context): \(reference.ident) \(reference.region) \(code) (line \(line))")
        return nil
    }

    private mutating func buildProcedures(_ legs: [(ProcedureLegRecord, Int?, Int?, Int?)]) {
        var runwayIdents: [String: Set<String>] = [:]
        for r in content.runways { runwayIdents[r.airport, default: []].insert(r.ident) }
        var procedureIndex: [String: Int] = [:]
        var routeIndex: [String: Int] = [:]
        var sequences: [String: Set<Int>] = [:]
        for (record, fix, navaid, center) in legs {
            let procedureKey = "\(record.airport)|\(record.kind.rawValue)|\(record.procedure)"
            let p: Int
            if let existing = procedureIndex[procedureKey] {
                p = existing
            } else {
                p = procedures.count
                procedureIndex[procedureKey] = p
                // The runway is written only when the airport has it. Example: `R027` is not runway 02.
                let runway = record.kind == .approach ? Self.approachRunway(record.procedure) : nil
                procedures.append(Procedure(airport: record.airport, kind: Self.kind(record.kind), ident: record.procedure,
                                            runway: runway.flatMap { runwayIdents[record.airport]?.contains($0) == true ? $0 : nil }))
            }
            let routeKey = procedureKey + "|\(record.routeType)|\(record.transition)"
            let r: Int
            if let existing = routeIndex[routeKey] {
                r = existing
            } else {
                r = procedures[p].routes.count
                routeIndex[routeKey] = r
                procedures[p].routes.append(Route(routeType: String(record.routeType), ident: record.transition,
                                                  role: Self.role(record.kind, routeType: record.routeType)))
            }
            guard sequences[routeKey, default: []].insert(record.sequence).inserted else {
                duplicateLegs.append("\(routeKey) sequence \(record.sequence) (line \(record.line))")
                continue
            }
            procedures[p].routes[r].legs.append(Leg(record: record, fixID: fix.flatMap { fixID[$0] },
                                                    navaidID: navaid.flatMap { fixID[$0] },
                                                    centerID: center.flatMap { fixID[$0] }))
        }
        var nextRoute: Int64 = 1
        for p in procedures.indices {
            procedures[p].id = Int64(p + 1)
            for r in procedures[p].routes.indices {
                procedures[p].routes[r].id = nextRoute
                nextRoute += 1
            }
            if procedures[p].kind == .approach {
                procedures[p].approachType = procedures[p].routes.first { $0.role == .final }?.routeType
            }
        }
    }

    private mutating func count() {
        for source in fixes { written["fix.\(source.kind.rawValue)", default: 0] += 1 }
        written["fix"] = fixes.count
        written["airway_fix"] = airwayFixes.count
        written["procedure"] = procedures.count
        written["procedure_transition"] = procedures.reduce(0) { $0 + $1.routes.count }
        written["procedure_leg"] = procedures.reduce(0) { $0 + $1.routes.reduce(0) { $0 + $1.legs.count } }
        for kind in NavProcedureKind.allCases {
            written["procedure.\(kind.rawValue)"] = procedures.filter { $0.kind == kind }.count
        }
        for procedure in procedures {
            for route in procedure.routes {
                for leg in route.legs { pathTerminators[leg.record.pathTerminator, default: 0] += 1 }
            }
            if let type = procedure.approachType { approachTypes[type, default: 0] += 1 }
        }
    }

    static func kind(_ kind: ProcedureKind) -> NavProcedureKind {
        switch kind {
        case .sid: .sid
        case .star: .star
        case .approach: .approach
        }
    }

    /// The role of a route by its ARINC 424 route type (ARINC 424-18 section 5.7).
    static func role(_ kind: ProcedureKind, routeType: Character) -> NavTransitionRole {
        switch kind {
        case .sid:
            switch routeType {
            case "0", "1", "4", "F", "T": .runwayTransition
            case "3", "6", "S", "V": .enrouteTransition
            default: .common
            }
        case .star:
            switch routeType {
            case "1", "4", "7", "F": .enrouteTransition
            case "3", "6", "9", "S": .runwayTransition
            default: .common
            }
        case .approach:
            routeType == "A" ? .approachTransition : .final
        }
    }

    /// The runway of an approach from its identifier: `I04L` → `RW04L`, `R13LY` → `RW13L`, `VDM-A` → nil (circling).
    static func approachRunway(_ ident: String) -> String? {
        let c = Array(ident)
        guard c.count >= 3, c[1].isNumber, c[2].isNumber else { return nil }
        var runway = "RW" + String(c[1...2])
        if c.count > 3, "LCR".contains(c[3]) { runway.append(c[3]) }
        return runway
    }
}
