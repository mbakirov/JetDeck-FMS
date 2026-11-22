import Foundation

/// Calculates when the runner must call `step`. It has no thread and no clock.
///
/// Rules:
/// - The period is `simStepSeconds / rate`.
/// - If the runner is late, it runs the missed steps, but not more than `maxCatchUpSteps`.
/// - If more steps are missed, the scheduler drops them. The simulation becomes slower than real time.
public struct RunnerScheduler: Sendable, Equatable {
    public static let maxCatchUpSteps = 5

    /// 1 is real time, 2 is two times faster.
    public var rate: Double
    /// Time of the next step, in seconds of the runner clock. nil before the first call.
    public private(set) var nextDeadline: Double?

    public init(rate: Double = 1) {
        self.rate = rate
    }

    public var period: Double {
        simStepSeconds / max(rate, 0.001)
    }

    /// Call this after a pause. The time of the pause is not caught up.
    public mutating func reset() {
        nextDeadline = nil
    }

    /// Returns the number of steps to run now and moves the deadline.
    public mutating func stepsDue(now: Double) -> Int {
        guard let deadline = nextDeadline else {
            nextDeadline = now + period
            return 0
        }
        guard now >= deadline else { return 0 }
        let due = Int(((now - deadline) / period).rounded(.down)) + 1
        if due > Self.maxCatchUpSteps {
            nextDeadline = now + period
            return Self.maxCatchUpSteps
        }
        nextDeadline = deadline + Double(due) * period
        return due
    }
}
