import Foundation
import Kernel
import NavDB
import SimCoreContract

/// The timing of the ND map query `fixes(near:radiusNM:kinds:)`.
public struct NavDBBenchReport: Sendable, Codable, Equatable {
    public struct Center: Sendable, Codable, Equatable {
        public var name: String
        public var fixes: Int
        public var p50Microseconds: Double
        public var p99Microseconds: Double
        public var maxMicroseconds: Double
    }

    public var cycle: String
    public var radiusNM: Double
    public var repeatCount: Int
    public var centers: [Center]
    /// Over all centers and repeats.
    public var p50Microseconds: Double
    public var p99Microseconds: Double
    public var maxMicroseconds: Double

    public var summary: String {
        var lines = ["ND query, radius \(radiusNM) NM, \(repeatCount) repeats, AIRAC \(cycle)"]
        for c in centers {
            lines.append("  \(c.name.padding(toLength: 6, withPad: " ", startingAt: 0)) \(String(format: "%6d", c.fixes)) fixes  p50 \(format(c.p50Microseconds))  p99 \(format(c.p99Microseconds))  max \(format(c.maxMicroseconds))")
        }
        lines.append("  all    p50 \(format(p50Microseconds))  p99 \(format(p99Microseconds))  max \(format(maxMicroseconds))")
        return lines.joined(separator: "\n")
    }

    private func format(_ microseconds: Double) -> String {
        String(format: "%8.0f µs", microseconds)
    }
}

public enum NavDBBench {
    /// Centers of the measurement: dense and sparse areas, Alaska, Hawaii, Caribbean, and a point near 180°.
    public static let defaultCenters: [(name: String, point: GeoPoint)] = [
        ("KJFK", GeoPoint(latDeg: 40.6399, lonDeg: -73.7787)),
        ("KORD", GeoPoint(latDeg: 41.9786, lonDeg: -87.9048)),
        ("KATL", GeoPoint(latDeg: 33.6367, lonDeg: -84.4281)),
        ("KDEN", GeoPoint(latDeg: 39.8617, lonDeg: -104.6731)),
        ("KLAX", GeoPoint(latDeg: 33.9425, lonDeg: -118.4081)),
        ("KSEA", GeoPoint(latDeg: 47.4490, lonDeg: -122.3093)),
        ("PANC", GeoPoint(latDeg: 61.1741, lonDeg: -149.9981)),
        ("PHNL", GeoPoint(latDeg: 21.3187, lonDeg: -157.9225)),
        ("TJSJ", GeoPoint(latDeg: 18.4394, lonDeg: -66.0021)),
        ("PASY", GeoPoint(latDeg: 52.7123, lonDeg: 174.1136)),
    ]

    /// Runs the query `repeatCount` times for each center, after one run that is not measured.
    public static func run(_ database: NavDatabaseReader, radiusNM: Double = 320, repeatCount: Int = 50,
                           centers: [(name: String, point: GeoPoint)] = defaultCenters) throws(NavDataError) -> NavDBBenchReport {
        let clock = ContinuousClock()
        var all: [Double] = []
        var results: [NavDBBenchReport.Center] = []
        for center in centers {
            let count = try database.fixes(near: center.point, radiusNM: radiusNM, kinds: []).count
            var times: [Double] = []
            for _ in 0..<repeatCount {
                let start = clock.now
                _ = try database.fixes(near: center.point, radiusNM: radiusNM, kinds: [])
                times.append(microseconds(clock.now - start))
            }
            times.sort()
            all += times
            results.append(.init(name: center.name, fixes: count, p50Microseconds: percentile(times, 0.5),
                                 p99Microseconds: percentile(times, 0.99), maxMicroseconds: times.last ?? 0))
        }
        all.sort()
        return NavDBBenchReport(cycle: database.info.cycle.ident, radiusNM: radiusNM, repeatCount: repeatCount, centers: results,
                                p50Microseconds: percentile(all, 0.5), p99Microseconds: percentile(all, 0.99),
                                maxMicroseconds: all.last ?? 0)
    }

    static func microseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000_000 + Double(parts.attoseconds) / 1_000_000_000_000
    }

    static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
        return sorted[index]
    }
}
