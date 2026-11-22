import Foundation

/// The clock of the runner. Tests can replace it.
public protocol RunnerClock: Sendable {
    /// Monotonic time in seconds.
    func now() -> Double
    func sleep(until deadline: Double)
}

public struct SystemRunnerClock: RunnerClock {
    private let origin = ContinuousClock.now

    public init() {}

    public func now() -> Double {
        let elapsed = ContinuousClock.now - origin
        return Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) * 1e-18
    }

    public func sleep(until deadline: Double) {
        let interval = deadline - now()
        if interval > 0 {
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

/// The outer loop. It calls `step` at 50 Hz on its own thread.
///
/// Pause and rate are functions of the runner, not of the core:
/// - During a pause the runner does not call `step`. Thus the simulation time stops
///   and the step number continues without a gap after the pause.
/// - `rate` changes the frequency of the calls.
public final class SimRunner: @unchecked Sendable {
    // `@unchecked Sendable`: the mutable properties below are read and written only with `condition` locked.
    private let core: any SimCoreProtocol
    private let clock: any RunnerClock
    private let onSnapshot: (@Sendable (Snapshot) -> Void)?
    private let condition = NSCondition()

    private var thread: Thread?
    private var paused = false
    private var stopRequested = false
    private var resetRequested = false
    private var currentRate: Double

    /// `onSnapshot` is called on the runner thread after each step.
    public init(
        core: any SimCoreProtocol,
        rate: Double = 1,
        clock: any RunnerClock = SystemRunnerClock(),
        onSnapshot: (@Sendable (Snapshot) -> Void)? = nil
    ) {
        self.core = core
        self.currentRate = rate
        self.clock = clock
        self.onSnapshot = onSnapshot
    }

    deinit {
        // The thread keeps a strong reference to the runner. Thus the thread is not alive here.
    }

    public var rate: Double {
        get { locked { currentRate } }
        set { locked { currentRate = newValue } }
    }

    public var isPaused: Bool { locked { paused } }
    public var isRunning: Bool { locked { thread != nil } }

    /// Starts the runner thread. Does nothing if the runner is started.
    public func start() {
        condition.lock()
        defer { condition.unlock() }
        guard thread == nil else { return }
        stopRequested = false
        resetRequested = true
        let thread = Thread { [self] in loop() }
        thread.name = "SimRunner"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    public func pause() {
        locked { paused = true }
    }

    public func resume() {
        condition.lock()
        paused = false
        resetRequested = true
        condition.broadcast()
        condition.unlock()
    }

    /// Stops the runner thread and waits for its end.
    public func stop() {
        condition.lock()
        defer { condition.unlock() }
        guard let thread else { return }
        stopRequested = true
        condition.broadcast()
        // A call from `onSnapshot` is on the runner thread. It cannot wait for itself.
        guard Thread.current !== thread else { return }
        while self.thread != nil {
            condition.wait()
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        condition.lock()
        defer { condition.unlock() }
        return body()
    }

    private func loop() {
        var scheduler = RunnerScheduler()
        while true {
            condition.lock()
            while paused && !stopRequested {
                condition.wait()
            }
            if stopRequested {
                thread = nil
                condition.broadcast()
                condition.unlock()
                return
            }
            if resetRequested {
                scheduler.reset()
                resetRequested = false
            }
            scheduler.rate = currentRate
            condition.unlock()

            let due = scheduler.stepsDue(now: clock.now())
            for _ in 0..<due {
                let snapshot = core.step()
                onSnapshot?(snapshot)
            }
            if let deadline = scheduler.nextDeadline {
                clock.sleep(until: deadline)
            }
        }
    }
}
