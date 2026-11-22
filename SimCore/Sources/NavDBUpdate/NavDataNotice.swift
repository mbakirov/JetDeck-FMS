import Foundation
import SimCoreContract

/// A notice to the users about the navigation data.
///
/// The FAA requires that a recipient of CIFP tells its users about errors in the data. The notices come by two ways:
/// - in the manifest (`NavDBManifest.notices`): the application reads them at each check for updates;
/// - in a push notification (APNs), key `navdb` of the payload. The connection to APNs is a later task (E12).
/// Both ways use this type, so the application shows them in the same way.
public struct NavDataNotice: Sendable, Codable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable {
        /// An error in the data. The text tells what is wrong and what to do.
        case dataError
        /// A new cycle is available for download.
        case newCycle
    }

    /// Unique identifier, for example `2611-001`. The application shows each notice once.
    public var id: String
    public var kind: Kind
    /// The cycle that the notice is about.
    public var cycle: AIRACCycle
    public var issued: CalendarDate
    public var title: String
    public var message: String
    /// Airports that the notice is about. Empty when it is about all data.
    public var airports: [String]

    public init(id: String, kind: Kind, cycle: AIRACCycle, issued: CalendarDate, title: String, message: String, airports: [String] = []) {
        self.id = id
        self.kind = kind
        self.cycle = cycle
        self.issued = issued
        self.title = title
        self.message = message
        self.airports = airports
    }
}

/// The payload of a push notification about the navigation data.
///
/// ```json
/// {"aps": {"alert": {"title": "…", "body": "…"}},
///  "navdb": {"id": "2611-001", "kind": "dataError", "cycle": "2611", "issued": "2026-11-02",
///            "title": "…", "message": "…", "airports": ["KJFK"]}}
/// ```
public enum NavDataPush {
    /// Key of the notice in the payload.
    public static let payloadKey = "navdb"

    /// Reads the notice from the JSON of a payload. Returns nil when the payload has no notice.
    public static func notice(fromPayload data: Data) throws -> NavDataNotice? {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return try notice(fromUserInfo: object)
    }

    /// Reads the notice from `userInfo` of a received notification. Returns nil when it has no notice.
    public static func notice(fromUserInfo userInfo: [AnyHashable: Any]) throws -> NavDataNotice? {
        guard let value = userInfo[payloadKey] else { return nil }
        let data = try JSONSerialization.data(withJSONObject: value)
        return try SimCoreJSON.decode(NavDataNotice.self, from: data)
    }
}
