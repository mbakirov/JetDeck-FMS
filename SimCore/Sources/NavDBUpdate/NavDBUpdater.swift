import Foundation
import Kernel
import NavDB
import SimCoreContract

/// Downloads a new navigation database without a new release of the application.
///
/// Order: manifest → compare with the active database → download to a temporary file → check and install
/// (`NavDBStore.install`). Any error leaves the active database as it was.
/// The address of the manifest is a parameter: the server is not selected yet.
public actor NavDBUpdater {
    public enum Result: Sendable, Equatable {
        /// The active database is the database of the manifest or a newer one.
        case upToDate(NavDataIdentity)
        /// The new database is installed. The next `NavDBStore.openActive` gives it.
        case installed(NavDataIdentity)
    }

    public let manifestURL: URL
    public let store: NavDBStore
    private let session: URLSession
    /// Notices of the last manifest that was read.
    public private(set) var notices: [NavDataNotice] = []

    public init(manifestURL: URL, store: NavDBStore, session: URLSession = .shared) {
        self.manifestURL = manifestURL
        self.store = store
        self.session = session
    }

    /// Reads and checks the manifest.
    public func fetchManifest() async throws(NavDBUpdateError) -> NavDBManifest {
        let data = try await get(manifestURL)
        let manifest = try NavDBManifest.decode(data)
        try manifest.validate()
        notices = manifest.notices
        return manifest
    }

    /// Installs the database of the manifest when it is newer than the active database.
    public func update() async throws(NavDBUpdateError) -> Result {
        let manifest = try await fetchManifest()
        guard manifest.schemaVersion == NavDBSchema.version else {
            throw .unsupportedSchema(found: manifest.schemaVersion, supported: NavDBSchema.version)
        }
        if let active = store.activeIdentity(), !Self.isNewer(manifest.identity, than: active) {
            return .upToDate(active)
        }
        let fileURL = try manifest.fileURL(relativeTo: manifestURL)
        let temporary = try await download(fileURL)
        try store.install(temporary, manifest: manifest)
        return .installed(manifest.identity)
    }

    /// A newer cycle, or the same cycle from a newer converter or another source file (a correction).
    static func isNewer(_ candidate: NavDataIdentity, than active: NavDataIdentity) -> Bool {
        if candidate.cycle != active.cycle { return candidate.cycle > active.cycle }
        if candidate.builderVersion != active.builderVersion { return candidate.builderVersion > active.builderVersion }
        return candidate.sourceSHA256 != active.sourceSHA256
    }

    private func get(_ url: URL) async throws(NavDBUpdateError) -> Data {
        do {
            let (data, response) = try await session.data(from: url)
            try Self.check(response, url)
            return data
        } catch let error as NavDBUpdateError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }
    }

    private func download(_ url: URL) async throws(NavDBUpdateError) -> URL {
        do {
            let (location, response) = try await session.download(from: url)
            try Self.check(response, url)
            // The system deletes `location` after this call. The file goes to the store directory.
            try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
            let temporary = store.directory.appendingPathComponent("download-\(UUID().uuidString).sqlite")
            try FileManager.default.moveItem(at: location, to: temporary)
            return temporary
        } catch let error as NavDBUpdateError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }
    }

    private static func check(_ response: URLResponse, _ url: URL) throws(NavDBUpdateError) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw .network("HTTP \(http.statusCode) for \(url.absoluteString)")
        }
    }
}
