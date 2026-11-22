import Foundation
import Kernel
import NavDB
import NavDBBuilder
import SimCoreContract
import Testing
@testable import NavDBUpdate

/// Acceptance criterion: without network the application works with the bundled database.
@Test func bundledDatabaseWorksWithoutNetwork() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    StubURLProtocol.serve(server.manifestURL, .offline)
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())

    await #expect(throws: NavDBUpdateError.self) { try await updater.update() }
    let active = try store.openActive()
    #expect(active.source == .bundled)
    #expect(active.reader.info.cycle.ident == "2611")
    #expect(try active.reader.airport("KJFK") != nil)
}

/// Acceptance criterion: a new database is loaded and used without a new release.
@Test func newDatabaseIsInstalledAndUsed() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let before = try store.openActive().reader
    let server = TestServer()
    let manifest = try server.publish(databases.cycle2612, name: "navdb-2612.sqlite")
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())

    #expect(try await updater.update() == .installed(manifest.identity))
    let active = try store.openActive()
    #expect(active.source == .downloaded)
    #expect(active.reader.info.cycle.ident == "2612")
    #expect(active.reader.cycle?.effective.description == "2026-11-26")
    // The reader that was open before the update keeps working with the old data.
    #expect(before.info.cycle.ident == "2611")
    #expect(try before.airport("KJFK") != nil)
    // No temporary files are left.
    let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
    #expect(files == ["navdb.sqlite"])

    // The second check finds nothing new and does not download the file again.
    let downloads = StubURLProtocol.requestCount(host: server.host)
    #expect(try await updater.update() == .upToDate(manifest.identity))
    #expect(StubURLProtocol.requestCount(host: server.host) == downloads + 1)
}

/// Acceptance criterion: a file with a wrong checksum is rejected. The application keeps the previous database.
@Test func fileWithWrongChecksumIsRejected() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())
    // First a good update to 2612.
    let good = try server.publish(databases.cycle2612)
    #expect(try await updater.update() == .installed(good.identity))
    let installed = try Data(contentsOf: store.downloadedURL)

    // Then a "correction" of 2612 whose file was damaged on the way: one byte is changed.
    var body = try Data(contentsOf: URL(fileURLWithPath: databases.cycle2612))
    body[body.count / 2] ^= 0xFF
    try server.publish(databases.cycle2612, body: body) { $0.sourceSHA256 = String(repeating: "b", count: 64) }
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.checksumMismatch = error else { return false }
        return true
    }
    #expect(try Data(contentsOf: store.downloadedURL) == installed)
    #expect(try store.openActive().reader.info == good.identity)
    #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path) == ["navdb.sqlite"])
}

@Test func fileWithWrongSizeIsRejected() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    let body = try Data(contentsOf: URL(fileURLWithPath: databases.cycle2612)).dropLast(10)
    try server.publish(databases.cycle2612, body: Data(body))
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.sizeMismatch = error else { return false }
        return true
    }
    #expect(!FileManager.default.fileExists(atPath: store.downloadedURL.path))
    #expect(try store.openActive().source == .bundled)
}

@Test func validFileOfAnotherDatabaseIsRejected() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    // The manifest says 2612, but the file (with the right checksum) is the database of 2611.
    let manifest2612 = try NavDBManifest.make(databasePath: databases.cycle2612, url: "x")
    try server.publish(databases.cycle2611) { manifest in
        manifest.cycle = manifest2612.cycle
        manifest.effective = manifest2612.effective
        manifest.lastDay = manifest2612.lastDay
    }
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.identityMismatch = error else { return false }
        return true
    }
    #expect(try store.openActive().source == .bundled)
}

@Test func fileThatIsNotADatabaseIsRejected() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    let garbage = Data(repeating: 0x42, count: 4096)
    // The checksum in the manifest is the checksum of the garbage, so that the check of the content runs.
    let file = temporaryDirectory().appendingPathComponent("garbage")
    try garbage.write(to: file)
    let checksum = try fileSHA256(file)
    try server.publish(databases.cycle2612, body: garbage) { manifest in
        manifest.sizeBytes = garbage.count
        manifest.sha256 = checksum
    }
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.invalidDatabase = error else { return false }
        return true
    }
    #expect(try store.openActive().source == .bundled)
}

@Test func databaseForAnotherSchemaIsNotDownloaded() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    try server.publish(databases.cycle2612) { $0.schemaVersion = NavDBSchema.version + 1 }
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())
    await #expect(throws: NavDBUpdateError.unsupportedSchema(found: NavDBSchema.version + 1, supported: NavDBSchema.version)) {
        try await updater.update()
    }
    // Only the manifest was requested.
    #expect(StubURLProtocol.requestCount(host: server.host) == 1)
}

@Test func httpErrorAndBadManifest() async throws {
    let databases = SampleDatabases.shared
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory())
    let server = TestServer()
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: store, session: StubURLProtocol.session())

    StubURLProtocol.serve(server.manifestURL, .data(status: 404, body: Data()))
    await #expect(throws: NavDBUpdateError.network("HTTP 404 for \(server.manifestURL.absoluteString)")) {
        try await updater.update()
    }
    StubURLProtocol.serve(server.manifestURL, .data(status: 200, body: Data("not json".utf8)))
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.manifest = error else { return false }
        return true
    }
    try server.publish(databases.cycle2612) { $0.lastDay = $0.lastDay.adding(days: 1) }
    await #expect {
        try await updater.update()
    } throws: { error in
        guard case NavDBUpdateError.manifest = error else { return false }
        return true
    }
    #expect(try store.openActive().source == .bundled)
}

@Test func storeSelection() throws {
    let databases = SampleDatabases.shared
    // A downloaded database that is older than the bundled one is not used.
    let directory = temporaryDirectory()
    try FileManager.default.copyItem(atPath: databases.cycle2611, toPath: directory.appendingPathComponent("navdb.sqlite").path)
    let store = NavDBStore(bundledPath: databases.cycle2612, directory: directory)
    let active = try store.openActive()
    #expect(active.source == .bundled)
    #expect(active.reader.info.cycle.ident == "2612")
    #expect(active.rejected.count == 1)

    // A damaged download is skipped.
    let damaged = temporaryDirectory()
    try Data(repeating: 0, count: 100).write(to: damaged.appendingPathComponent("navdb.sqlite"))
    let second = try NavDBStore(bundledPath: databases.cycle2611, directory: damaged).openActive()
    #expect(second.source == .bundled)
    #expect(second.rejected.first?.hasPrefix("downloaded:") == true)

    // Without any database the store throws.
    #expect(throws: NavDataError.self) { try NavDBStore(bundledPath: nil, directory: temporaryDirectory()).openActive() }
}

@Test func bundledDatabaseFromANewerConverterReplacesTheDownload() throws {
    let databases = SampleDatabases.shared
    // The downloaded 2611 was made by an older converter. The new release bundles 2611 from the current one.
    let directory = temporaryDirectory()
    let downloaded = directory.appendingPathComponent("navdb.sqlite")
    try FileManager.default.copyItem(atPath: databases.cycle2611, toPath: downloaded.path)
    try SQLiteDatabase(path: downloaded.path, mode: .readWriteCreate)
        .execute("UPDATE meta SET value = '\(NavDBBuilder.version - 1)' WHERE key = 'builder_version'")
    let store = NavDBStore(bundledPath: databases.cycle2611, directory: directory)
    let active = try store.openActive()
    #expect(active.source == .bundled)
    #expect(active.reader.info.builderVersion == NavDBBuilder.version)
    #expect(active.rejected.count == 1)

    // A correction of the same cycle from the same converter (another source file) is kept.
    try FileManager.default.removeItem(at: downloaded)
    try FileManager.default.copyItem(atPath: databases.cycle2611, toPath: downloaded.path)
    try SQLiteDatabase(path: downloaded.path, mode: .readWriteCreate)
        .execute("UPDATE meta SET value = '\(String(repeating: "c", count: 64))' WHERE key = 'source_sha256'")
    #expect(try store.openActive().source == .downloaded)
}

@Test func bundledReplacesRule() {
    let a = NavDataIdentity(cycle: AIRACCycle(ident: "2611")!, schemaVersion: 2, builderVersion: 2, sourceSHA256: String(repeating: "a", count: 64))
    var b = a
    #expect(!NavDBStore.bundledReplaces(b, downloaded: a))
    b.sourceSHA256 = String(repeating: "b", count: 64)
    #expect(!NavDBStore.bundledReplaces(b, downloaded: a))
    b.builderVersion = 3
    #expect(NavDBStore.bundledReplaces(b, downloaded: a))
    b = a
    b.cycle = AIRACCycle(ident: "2612")!
    #expect(NavDBStore.bundledReplaces(b, downloaded: a))
    #expect(!NavDBStore.bundledReplaces(a, downloaded: b))
}

@Test func newerIdentity() {
    let a = NavDataIdentity(cycle: AIRACCycle(ident: "2611")!, schemaVersion: 1, builderVersion: 1, sourceSHA256: String(repeating: "a", count: 64))
    var b = a
    #expect(!NavDBUpdater.isNewer(b, than: a))
    b.cycle = AIRACCycle(ident: "2612")!
    #expect(NavDBUpdater.isNewer(b, than: a))
    #expect(!NavDBUpdater.isNewer(a, than: b))
    b = a
    b.builderVersion = 2
    #expect(NavDBUpdater.isNewer(b, than: a))
    b = a
    b.sourceSHA256 = String(repeating: "c", count: 64)
    #expect(NavDBUpdater.isNewer(b, than: a))
}

@Test func manifestFileAddress() throws {
    let manifest = try NavDBManifest.make(databasePath: SampleDatabases.shared.cycle2611, url: "navdb-2611.sqlite")
    let base = URL(string: "https://example.test/navdb/manifest.json")!
    #expect(try manifest.fileURL(relativeTo: base).absoluteString == "https://example.test/navdb/navdb-2611.sqlite")
    var absolute = manifest
    absolute.url = "https://cdn.example.test/a/b.sqlite"
    #expect(try absolute.fileURL(relativeTo: base).absoluteString == "https://cdn.example.test/a/b.sqlite")
    try manifest.validate()
    #expect(manifest.effective.description == "2026-10-29")
    #expect(manifest.lastDay.description == "2026-11-25")
    #expect(try NavDBManifest.decode(SimCoreJSON.encode(manifest)) == manifest)
}

@Test func noticesFromManifestAndPush() async throws {
    let databases = SampleDatabases.shared
    let notice = NavDataNotice(id: "2611-001", kind: .dataError, cycle: AIRACCycle(ident: "2611")!,
                               issued: CalendarDate(iso: "2026-11-02")!, title: "KJFK ILS 04L",
                               message: "The altitude at KRSTL is wrong. Use the chart.", airports: ["KJFK"])
    let server = TestServer()
    try server.publish(databases.cycle2611) { $0.notices = [notice] }
    let updater = NavDBUpdater(manifestURL: server.manifestURL, store: NavDBStore(bundledPath: databases.cycle2611, directory: temporaryDirectory()),
                               session: StubURLProtocol.session())
    _ = try await updater.update()
    #expect(await updater.notices == [notice])

    let payload = """
    {"aps": {"alert": {"title": "Navigation data", "body": "KJFK ILS 04L"}},
     "navdb": {"id": "2611-001", "kind": "dataError", "cycle": "2611", "issued": "2026-11-02",
               "title": "KJFK ILS 04L", "message": "The altitude at KRSTL is wrong. Use the chart.", "airports": ["KJFK"]}}
    """
    #expect(try NavDataPush.notice(fromPayload: Data(payload.utf8)) == notice)
    #expect(try NavDataPush.notice(fromPayload: Data(#"{"aps": {}}"#.utf8)) == nil)
    #expect(throws: (any Error).self) { try NavDataPush.notice(fromUserInfo: ["navdb": ["id": "x"]]) }
}
