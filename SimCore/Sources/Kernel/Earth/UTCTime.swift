import SimCoreContract

/// UTC time of the scenario: a date and the time from midnight.
///
/// The core does not use the system clock. The time is the start time of the scenario
/// plus the simulation time `step × 0.02 s`. The calendar is Gregorian, without leap seconds.
public struct UTCTime: Sendable, Equatable {
    public var date: UTCDate
    /// Whole seconds from midnight, 0..<86 400.
    public var secondsOfDay: Int
    /// Part of a second, 0..<1.
    public var fraction: Double

    public init(date: UTCDate, secondsOfDay: Int, fraction: Double) {
        self.date = date
        self.secondsOfDay = secondsOfDay
        self.fraction = fraction
    }

    /// The time `elapsedSeconds` after the start. `elapsedSeconds` must not be negative.
    /// A start time outside 0..<86 400 counts from midnight of the start date.
    public init(startDate: UTCDate, startSecondsOfDay: Int, elapsedSeconds: Double) {
        let whole = elapsedSeconds.rounded(.down)
        let total = startSecondsOfDay + Int(whole)
        date = startDate.adding(days: floorDiv(total, 86_400))
        secondsOfDay = floorMod(total, 86_400)
        fraction = elapsedSeconds - whole
    }

    /// The time at the end of the step of `context`.
    public init(context: StepContext) {
        self.init(
            startDate: context.initial.utcStartDate,
            startSecondsOfDay: context.initial.utcStartSecondsOfDay,
            elapsedSeconds: context.simTimeSeconds
        )
    }

    /// The year with its part, for example 2026.5 in the middle of 2026. The magnetic model uses it.
    public var decimalYear: Double {
        let date = date.normalized
        let days = Double(UTCDate.isLeapYear(date.year) ? 366 : 365)
        let dayPart = (Double(secondsOfDay) + fraction) / 86_400
        return Double(date.year) + (Double(date.dayOfYear - 1) + dayPart) / days
    }
}

extension UTCDate {
    public static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }

    /// Days from 1970-01-01. A date that does not exist counts forward:
    /// 30 February is 2 March (1 March in a leap year), month 13 is January of the next year.
    public var dayNumber: Int {
        // The algorithm "days_from_civil" of H. Hinnant. The year starts on 1 March.
        let y0 = year + floorDiv(month - 1, 12)
        let m = floorMod(month - 1, 12) + 1
        let y = m <= 2 ? y0 - 1 : y0
        let era = floorDiv(y, 400)
        let yearOfEra = y - era * 400
        let monthFromMarch = m > 2 ? m - 3 : m + 9
        let dayOfYear = (153 * monthFromMarch + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    /// The date of the day number (days from 1970-01-01).
    public init(dayNumber: Int) {
        // The algorithm "civil_from_days" of H. Hinnant.
        let z = dayNumber + 719_468
        let era = floorDiv(z, 146_097)
        let dayOfEra = z - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let monthFromMarch = (5 * dayOfYear + 2) / 153
        let day = dayOfYear - (153 * monthFromMarch + 2) / 5 + 1
        let month = monthFromMarch < 10 ? monthFromMarch + 3 : monthFromMarch - 9
        let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
        self.init(year: year, month: month, day: day)
    }

    /// The same date with a month and a day that exist.
    public var normalized: UTCDate { UTCDate(dayNumber: dayNumber) }

    public func adding(days: Int) -> UTCDate {
        UTCDate(dayNumber: dayNumber + days)
    }

    /// Day of the year: 1 for 1 January.
    public var dayOfYear: Int {
        let date = normalized
        return date.dayNumber - UTCDate(year: date.year, month: 1, day: 1).dayNumber + 1
    }
}
