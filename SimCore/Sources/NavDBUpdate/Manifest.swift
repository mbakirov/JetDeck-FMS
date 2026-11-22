import CryptoKit
import Foundation
import NavDB
import SimCoreContract

/// An error of the update of the navigation database. After any error the application keeps its database.
public enum NavDBUpdateError: Error, Sendable, Equatable, LocalizedError {
    case network(String)
    case manifest(String)
    /// The new database needs another version of the application.
    case unsupportedSchema(found: Int, supported: Int)
    case sizeMismatch(expected: Int, actual: Int)
    case checksumMismatch(expected: String, actual: String)
    /// The file has the right checksum but it is not a valid database.
    case invalidDatabase(String)
    /// The database is valid but it is not the database of the manifest.
    case identityMismatch(String)
    case file(String)

    public var errorDescription: String? {
        switch self {
        case .network(let reason): "Network error: \(reason)"
        case .manifest(let reason): "The manifest is not valid: \(reason)"
        case .unsupportedSchema(let found, let supported): "The new database has schema \(found). This version of the application supports schema \(supported)."
        case .sizeMismatch(let expected, let actual): "The file has \(actual) bytes, the manifest gives \(expected)."
        case .checksumMismatch: "The checksum of the file is not the checksum in the manifest."
        case .invalidDatabase(let reason): "The file is not a valid navigation database: \(reason)"
        case .identityMismatch(let reason): "The file is not the database of the manifest: \(reason)"
        case .file(let reason): "File error: \(reason)"
        }
    }
}

/// The manifest of a published database. The CI job writes it next to the database file.
///
/// ```json
/// {"format":1,"schemaVersion":2,"builderVersion":2,"cycle":"2611","effective":"2026-10-29","lastDay":"2026-11-25",
///  "url":"navdb-2611.sqlite","sizeBytes":22126592,"sha256":"…","sourceSHA256":"…","notices":[]}
/// ```
public struct NavDBManifest: Sendable, Codable, Equatable {
    /// Version of this manifest format.
    public static let currentFormat = 1

    public var format: Int
    public var schemaVersion: Int
    public var builderVersion: Int
    public var cycle: AIRACCycle
    public var effective: CalendarDate
    public var lastDay: CalendarDate
    /// Address of the database file. A relative address is relative to the address of the manifest.
    public var url: String
    public var sizeBytes: Int
    /// SHA-256 of the database file (hexadecimal, lower case).
    public var sha256: String
    /// SHA-256 of the source CIFP file. It is part of the identity of the database.
    public var sourceSHA256: String
    /// Notices about errors in the data of this or an earlier cycle.
    public var notices: [NavDataNotice]

    public init(format: Int = currentFormat, schemaVersion: Int, builderVersion: Int, cycle: AIRACCycle, url: String,
                sizeBytes: Int, sha256: String, sourceSHA256: String, notices: [NavDataNotice] = []) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.builderVersion = builderVersion
        self.cycle = cycle
        self.effective = cycle.effective
        self.lastDay = cycle.lastDay
        self.url = url
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.sourceSHA256 = sourceSHA256
        self.notices = notices
    }

    /// The manifest of a database file. The file is checked with `NavDatabaseReader`.
    public static func make(databasePath: String, url: String, notices: [NavDataNotice] = []) throws -> NavDBManifest {
        let reader = try NavDatabaseReader(path: databasePath)
        try reader.checkIntegrity()
        let identity = reader.info
        let file = URL(fileURLWithPath: databasePath)
        return NavDBManifest(schemaVersion: identity.schemaVersion, builderVersion: identity.builderVersion,
                             cycle: identity.cycle, url: url, sizeBytes: try fileSize(file), sha256: try fileSHA256(file),
                             sourceSHA256: identity.sourceSHA256, notices: notices)
    }

    /// The identity that the database of this manifest has.
    public var identity: NavDataIdentity {
        NavDataIdentity(cycle: cycle, schemaVersion: schemaVersion, builderVersion: builderVersion, sourceSHA256: sourceSHA256)
    }

    /// Checks the fields that do not need the file.
    public func validate() throws(NavDBUpdateError) {
        guard format == Self.currentFormat else { throw .manifest("format \(format) is not supported") }
        guard effective == cycle.effective, lastDay == cycle.lastDay else {
            throw .manifest("the dates \(effective) – \(lastDay) are not the dates of cycle \(cycle.ident)")
        }
        guard sizeBytes > 0 else { throw .manifest("the size is \(sizeBytes)") }
        guard Self.isHexSHA256(sha256), Self.isHexSHA256(sourceSHA256) else { throw .manifest("a SHA-256 value is not valid") }
        guard !url.isEmpty else { throw .manifest("the file address is empty") }
    }

    /// The address of the database file.
    public func fileURL(relativeTo manifestURL: URL) throws(NavDBUpdateError) -> URL {
        guard let resolved = URL(string: url, relativeTo: manifestURL)?.absoluteURL else {
            throw .manifest("the file address '\(url)' is not valid")
        }
        return resolved
    }

    static func isHexSHA256(_ text: String) -> Bool {
        text.count == 64 && text.allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    public static func decode(_ data: Data) throws(NavDBUpdateError) -> NavDBManifest {
        do {
            return try SimCoreJSON.decode(NavDBManifest.self, from: data)
        } catch {
            throw .manifest("cannot read the JSON: \(error)")
        }
    }
}

/// SHA-256 of a file. The file is read in parts, so the memory does not depend on the size.
public func fileSHA256(_ file: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
        hasher.update(data: chunk)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

func fileSize(_ file: URL) throws -> Int {
    (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
}
