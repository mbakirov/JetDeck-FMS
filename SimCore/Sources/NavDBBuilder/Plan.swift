import ARINC424
import Foundation
import Kernel

/// The content of the database before it is written: the filter result, the points and the procedures with ids.
struct Plan {
    struct AirwayFix {
        var record: AirwayFixRecord
        var fixID: Int64?
        /// Continuous part of the airway, 1-based for each airway name (`airwaySegments`).
        var segment: Int
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
    /// Records of a fix at an area boundary that is also in the other area (same sequence, same fix). Not written.
    private(set) var airwayBoundaryDuplicates = 0
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

        // References of the airways and of the procedures of the kept airports. A referenced waypoint or navaid
        // of another airport is also written, so that the reference is resolved. An airport is never added.
        var airwayTarget: [Int: Int] = [:]
        for record in content.airwayFixes {
            let line = resolve(record.fix, airport: nil, context: "airway \(record.route) \(record.sequence)", line: record.line)
            if let line {
                included.insert(line)
                airwayTarget[record.line] = line
            }
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
        var routes: [String: [AirwayFixRecord]] = [:]
        var routeOrder: [String] = []
        for record in content.airwayFixes {
            if routes[record.route] == nil { routeOrder.append(record.route) }
            routes[record.route, default: []].append(record)
        }
        for route in routeOrder {
            let records = routes[route]!
            let segments = Self.airwaySegments(records)
            airwayBoundaryDuplicates += records.count - segments.count
            for (record, segment) in segments {
                airwayFixes.append(AirwayFix(record: record, fixID: airwayTarget[record.line].flatMap { fixID[$0] }, segment: segment))
            }
        }
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
        let code = reference.code.isEmpty ? "?" : reference.code
        guard let resolved = catalog.resolve(reference, airport: airport) else {
            unresolvedByCode[code, default: 0] += 1
            unresolved.append("\(context): \(reference.ident) \(reference.region) \(code) (line \(line))")
            return nil
        }
        // An airport that the filter rejected is not written: it would be an airport without runways in the
        // database. The reference stays unresolved (in the source data it is usually a typing error).
        if let source = catalog.sources[resolved], source.kind == .airport, !keptAirports.contains(source.ident) {
            unresolvedByCode[code, default: 0] += 1
            unresolved.append("\(context): \(reference.ident) \(reference.region) \(code) (line \(line)): the airport is not in the database")
            return nil
        }
        return resolved
    }

    /// Orders the fixes of one airway name and splits them into continuous segments.
    ///
    /// In CIFP one airway can be split between areas (`USA`, `CAN`, `PAC`, `LAM`): the fix at the boundary is in both
    /// areas with the same sequence number, and the sequence numbers continue. Other airways with the same name in
    /// different areas are different airways. Rules:
    /// - Areas that share a fix (same sequence number and identifier) are one chain. Other areas are separate chains.
    /// - In a chain the fixes are in sequence order. A shared fix is written once.
    /// - A segment ends at a fix with the end flag (column 41 of the description code is `E`), unless the same fix
    ///   in another area has no end flag. Chains are ordered by their first sequence number, then by area.
    static func airwaySegments(_ records: [AirwayFixRecord]) -> [(AirwayFixRecord, Int)] {
        func key(_ r: AirwayFixRecord) -> String { "\(r.sequence)|\(r.fix.ident)" }
        func isEnd(_ r: AirwayFixRecord) -> Bool {
            let c = Array(r.descriptionCode)
            return c.count > 1 && c[1] == "E"
        }
        var byArea: [String: [AirwayFixRecord]] = [:]
        for r in records { byArea[r.area, default: []].append(r) }
        let areas = byArea.keys.sorted()
        var keys: [String: Set<String>] = [:]
        for area in areas { keys[area] = Set(byArea[area]!.map(key)) }

        // Union of areas that share a fix.
        var parent = Dictionary(uniqueKeysWithValues: areas.map { ($0, $0) })
        func root(_ a: String) -> String {
            var a = a
            while parent[a]! != a { a = parent[a]! }
            return a
        }
        for (i, a) in areas.enumerated() {
            for b in areas[(i + 1)...] where !keys[a]!.isDisjoint(with: keys[b]!) {
                let ra = root(a), rb = root(b)
                if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
            }
        }
        var chains: [String: [AirwayFixRecord]] = [:]
        for area in areas { chains[root(area), default: []] += byArea[area]! }
        let ordered = chains.values.map { chain in
            // A copy without the end flag comes first, so that it is the copy that is written.
            chain.sorted { ($0.sequence, isEnd($0) ? 1 : 0, $0.area, $0.line) < ($1.sequence, isEnd($1) ? 1 : 0, $1.area, $1.line) }
        }.sorted { ($0[0].sequence, $0[0].area) < ($1[0].sequence, $1[0].area) }

        var result: [(AirwayFixRecord, Int)] = []
        var segment = 0
        for chain in ordered {
            segment += 1
            var previous: AirwayFixRecord?
            var previousEnds = false
            for r in chain {
                if let p = previous, p.sequence == r.sequence, p.fix.ident == r.fix.ident {
                    previousEnds = previousEnds && isEnd(r)
                    continue
                }
                if previous != nil, previousEnds { segment += 1 }
                result.append((r, segment))
                previous = r
                previousEnds = isEnd(r)
            }
        }
        return result
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
        written["airway_fix.boundaryDuplicates"] = airwayBoundaryDuplicates
        written["airway_segment"] = Set(airwayFixes.map { "\($0.record.route)|\($0.segment)" }).count
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
