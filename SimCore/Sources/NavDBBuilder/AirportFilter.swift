import ARINC424
import Foundation

/// The filter of airports that are suitable for the A320 (epic E02).
///
/// An airport passes when:
/// - the surface of its longest runway is hard (code `H` in the airport record; the runway record of
///   ARINC 424-18 has no surface field), and
/// - it has an ILS with a glide slope (category 1, 2 or 3) for a runway of `minimumRunwayFt` or more.
///   A localizer without a glide slope, LDA, SDF and IGS do not count.
public struct AirportFilter: Sendable {
    public var minimumRunwayFt: Int

    public init(minimumRunwayFt: Int = 5000) {
        self.minimumRunwayFt = minimumRunwayFt
    }

    public enum Rejection: String, Sendable, Codable, CaseIterable {
        case notHardSurface
        case noILS
        case ilsRunwayTooShort
    }

    /// Returns nil when the airport passes, otherwise the first reason of rejection.
    public func evaluate(_ airport: AirportRecord, runways: [RunwayRecord], localizers: [LocalizerRecord]) -> Rejection? {
        guard airport.longestRunwaySurface == "H" else { return .notHardSurface }
        let ils = localizers.filter(\.isILSWithGlideSlope)
        guard !ils.isEmpty else { return .noILS }
        let lengths = Dictionary(runways.map { ($0.ident, $0.lengthFt) }, uniquingKeysWith: max)
        let served = ils.contains { (lengths[$0.runway] ?? 0) >= minimumRunwayFt }
        return served ? nil : .ilsRunwayTooShort
    }
}
