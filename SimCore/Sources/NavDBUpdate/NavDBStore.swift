import Foundation
import Kernel
import NavDB
import SimCoreContract

/// The database that the application uses now, and where it came from.
public struct ActiveNavDatabase: Sendable {
    public enum Source: String, Sendable {
        /// The database in the application bundle. It works without network.
        case bundled
        /// A database that the application downloaded.
        case downloaded
    }

    public var reader: NavDatabaseReader
    public var source: Source
    /// Databases that the store did not use, with the reason. For the log.
    public var rejected: [String]
}

/// The files of the navigation database on the device.
///
/// - The bundled database is read only. It is the fallback when there is no network or no valid download.
/// - The downloaded database is `<directory>/navdb.sqlite`. Only `install` changes it, with an atomic replace.
///
/// A new database is used from the next `openActive` call. The application calls it when it starts a scenario
/// and gives the reader to a new `SimEngine`. A running engine keeps its reader and its file.
public struct NavDBStore: Sendable {
    public let bundledPath: String?
    public let directory: URL

    public init(bundledPath: String?, directory: URL) {
        self.bundledPath = bundledPath
        self.directory = directory
    }

    public var downloadedURL: URL { directory.appendingPathComponent("navdb.sqlite") }

    /// Opens the database to use: the downloaded one when it is valid and not older than the bundled one,
    /// otherwise the bundled one.
    public func openActive() throws(NavDataError) -> ActiveNavDatabase {
        var rejected: [String] = []
        var downloaded: NavDatabaseReader?
        if FileManager.default.fileExists(atPath: downloadedURL.path) {
            do {
                downloaded = try NavDatabaseReader(path: downloadedURL.path)
            } catch {
                rejected.append("downloaded: \(error.localizedDescription)")
            }
        }
        var bundled: NavDatabaseReader?
        if let bundledPath {
            do {
                bundled = try NavDatabaseReader(path: bundledPath)
            } catch {
                rejected.append("bundled: \(error.localizedDescription)")
            }
        }
        switch (downloaded, bundled) {
        case let (d?, b?):
            if d.info.cycle >= b.info.cycle {
                return ActiveNavDatabase(reader: d, source: .downloaded, rejected: rejected)
            }
            rejected.append("downloaded: cycle \(d.info.cycle.ident) is older than the bundled cycle \(b.info.cycle.ident)")
            return ActiveNavDatabase(reader: b, source: .bundled, rejected: rejected)
        case let (d?, nil):
            return ActiveNavDatabase(reader: d, source: .downloaded, rejected: rejected)
        case let (nil, b?):
            return ActiveNavDatabase(reader: b, source: .bundled, rejected: rejected)
        case (nil, nil):
            throw .storage("no valid navigation database: \(rejected.joined(separator: "; "))")
        }
    }

    /// Identity of the database that `openActive` gives now, or nil.
    public func activeIdentity() -> NavDataIdentity? {
        try? openActive().reader.info
    }

    /// Checks a downloaded file and makes it the downloaded database. The check:
    /// size and SHA-256 as in the manifest, the reader opens it (schema version, table meta), SQLite `quick_check`,
    /// and the identity in the file is the identity of the manifest.
    /// When a check fails, the file is deleted and the old database stays.
    public func install(_ file: URL, manifest: NavDBManifest) throws(NavDBUpdateError) {
        defer { try? FileManager.default.removeItem(at: file) }
        let size: Int
        let checksum: String
        do {
            size = try fileSize(file)
            checksum = try fileSHA256(file)
        } catch {
            throw .file("cannot read the downloaded file: \(error.localizedDescription)")
        }
        guard size == manifest.sizeBytes else { throw .sizeMismatch(expected: manifest.sizeBytes, actual: size) }
        guard checksum == manifest.sha256 else { throw .checksumMismatch(expected: manifest.sha256, actual: checksum) }
        do {
            let reader = try NavDatabaseReader(path: file.path)
            try reader.checkIntegrity()
            guard reader.info == manifest.identity else {
                throw NavDBUpdateError.identityMismatch("file \(reader.info), manifest \(manifest.identity)")
            }
        } catch let error as NavDBUpdateError {
            throw error
        } catch let error as NavDataError {
            throw .invalidDatabase(error.localizedDescription)
        } catch {
            throw .invalidDatabase(String(describing: error))
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: downloadedURL.path) {
                // Atomic: a reader of the old file keeps its open file. A new reader opens the new file.
                _ = try FileManager.default.replaceItemAt(downloadedURL, withItemAt: file)
            } else {
                try FileManager.default.moveItem(at: file, to: downloadedURL)
            }
        } catch {
            throw .file("cannot replace the database: \(error.localizedDescription)")
        }
    }
}
