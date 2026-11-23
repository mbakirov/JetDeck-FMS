import Foundation

/// The record types that this module reads.
public enum RecordKind: String, Sendable, CaseIterable, Comparable, Codable {
    case airport = "PA"
    case runway = "PG"
    case localizer = "PI"
    case terminalWaypoint = "PC"
    case terminalNDB = "PN"
    case sid = "PD"
    case star = "PE"
    case approach = "PF"
    case vhfNavaid = "D"
    case enrouteNDB = "DB"
    case enrouteWaypoint = "EA"
    case airway = "ER"

    public static func < (lhs: RecordKind, rhs: RecordKind) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Column of the continuation record number.
    var continuationColumn: Int {
        switch self {
        case .sid, .star, .approach, .airway: 39
        default: 22
        }
    }
}

/// The class of a line in a CIFP file.
public enum LineClass: Sendable, Equatable {
    /// A header line (`HDR01` ... `HDR05`).
    case header
    /// A primary record of a type that this module reads.
    case primary(RecordKind)
    /// A continuation record of a type that this module reads. The module does not read continuation records.
    case continuation(RecordKind)
    /// A record of a type that this module does not read, for example airspace or MSA.
    /// The code is the section and the subsection, for example `UC` or `PS`.
    case other(code: String)
}

extension ARINC424Line {
    /// Section and subsection, for example `PA`, `D`, `DB`, `UC`.
    /// For sections P and H the subsection is in column 13, except PN (terminal NDB), where it is in column 6.
    public var code: String {
        let section = character(5)
        var subsection = character(6)
        if (section == "P" || section == "H"), subsection == " " {
            subsection = character(13)
        }
        return subsection == " " ? String(section) : String([section, subsection])
    }

    public var lineClass: LineClass {
        if byte(1) == 0x48, raw(1...3) == "HDR" { return .header }
        let code = self.code
        guard let kind = RecordKind(rawValue: code) else { return .other(code: code) }
        // 0 means "a primary record without continuation", 1 means "a primary record with continuation".
        let number = byte(kind.continuationColumn)
        return number == 0x30 || number == 0x31 ? .primary(kind) : .continuation(kind)
    }
}
