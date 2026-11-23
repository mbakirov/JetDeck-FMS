import Foundation
import NavDB
import NavDBBuilder
import Synchronization
@testable import NavDBUpdate

let sampleURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Fixtures/CIFP-sample-2611.txt")

/// Databases of the test sample: cycle 2611 (the sample) and 2612 (the same records with the header of 2612).
/// They are made once for all tests.
struct SampleDatabases: Sendable {
    let directory: URL
    let cycle2611: String
    let cycle2612: String

    static let shared: SampleDatabases = {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-update-tests-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = try! String(contentsOf: sampleURL, encoding: .utf8)
        let path2611 = directory.appendingPathComponent("navdb-2611.sqlite").path
        _ = try! NavDBBuilder.build(cifp: Data(text.utf8), sourceFileName: "sample", output: path2611)
        let text2612 = text
            .replacingOccurrences(of: "001P013200026732611", with: "001P013200026732612")
            .replacingOccurrences(of: "VOLUME 2611  EFFECTIVE 29 OCT 2026", with: "VOLUME 2612  EFFECTIVE 26 NOV 2026")
        let path2612 = directory.appendingPathComponent("navdb-2612.sqlite").path
        _ = try! NavDBBuilder.build(cifp: Data(text2612.utf8), sourceFileName: "sample", output: path2612)
        return SampleDatabases(directory: directory, cycle2611: path2611, cycle2612: path2612)
    }()
}

/// A new empty directory for one test.
func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("navdb-store-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// A test server inside URLSession. Each test uses its own host, so tests can run at the same time.
final class StubURLProtocol: URLProtocol {
    enum Response: Sendable {
        case data(status: Int, body: Data)
        case offline
    }

    static let responses = Mutex<[String: Response]>([:])
    static let requests = Mutex<[String]>([])

    static func serve(_ url: URL, _ response: Response) {
        responses.withLock { $0[url.absoluteString] = response }
    }

    static func requestCount(host: String) -> Int {
        requests.withLock { $0.filter { $0.contains(host) }.count }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.requests.withLock { $0.append(url.absoluteString) }
        switch Self.responses.withLock({ $0[url.absoluteString] }) {
        case .data(let status, let body)?:
            let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .offline, nil:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// A server with a manifest and a database file.
struct TestServer {
    let host = "navdb-\(UUID().uuidString.lowercased()).test"
    var manifestURL: URL { URL(string: "https://\(host)/navdb/manifest.json")! }

    func fileURL(_ name: String) -> URL {
        URL(string: "https://\(host)/navdb/\(name)")!
    }

    /// Publishes a database with its manifest. `change` can change the manifest before it is published.
    @discardableResult
    func publish(_ path: String, name: String = "navdb.sqlite", body: Data? = nil,
                 change: (inout NavDBManifest) -> Void = { _ in }) throws -> NavDBManifest {
        var manifest = try NavDBManifest.make(databasePath: path, url: name)
        change(&manifest)
        StubURLProtocol.serve(manifestURL, .data(status: 200, body: try JSONEncoder().encode(manifest)))
        StubURLProtocol.serve(fileURL(name), .data(status: 200, body: try body ?? Data(contentsOf: URL(fileURLWithPath: path))))
        return manifest
    }
}
