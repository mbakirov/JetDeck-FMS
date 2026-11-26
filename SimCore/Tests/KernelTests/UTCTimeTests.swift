import Kernel
import SimCoreContract
import Testing

@Test func dayNumberOfKnownDates() {
    #expect(UTCDate(year: 1970, month: 1, day: 1).dayNumber == 0)
    #expect(UTCDate(year: 2000, month: 3, day: 1).dayNumber == 11_017)
    #expect(UTCDate(year: 2026, month: 11, day: 26).dayNumber == 20_783)
    #expect(UTCDate(year: 1969, month: 12, day: 31).dayNumber == -1)
}

@Test func dayNumberRoundTrip() {
    for number in stride(from: -800_000, through: 800_000, by: 997) {
        #expect(UTCDate(dayNumber: number).dayNumber == number)
    }
}

@Test func datesThatDoNotExistCountForward() {
    #expect(UTCDate(year: 2026, month: 2, day: 30).normalized == UTCDate(year: 2026, month: 3, day: 2))
    #expect(UTCDate(year: 2028, month: 2, day: 30).normalized == UTCDate(year: 2028, month: 3, day: 1))
    #expect(UTCDate(year: 2026, month: 13, day: 1).normalized == UTCDate(year: 2027, month: 1, day: 1))
    #expect(UTCDate(year: 2026, month: 0, day: 31).normalized == UTCDate(year: 2025, month: 12, day: 31))
}

@Test func leapYears() {
    #expect(UTCDate.isLeapYear(2024))
    #expect(UTCDate.isLeapYear(2000))
    #expect(!UTCDate.isLeapYear(1900))
    #expect(!UTCDate.isLeapYear(2026))
    #expect(UTCDate(year: 2024, month: 12, day: 31).dayOfYear == 366)
    #expect(UTCDate(year: 2026, month: 12, day: 31).dayOfYear == 365)
    #expect(UTCDate(year: 2026, month: 1, day: 1).dayOfYear == 1)
}

@Test func timeCrossesMidnightAndTheEndOfTheYear() {
    let time = UTCTime(startDate: UTCDate(year: 2026, month: 12, day: 31), startSecondsOfDay: 86_390, elapsedSeconds: 15.5)
    #expect(time.date == UTCDate(year: 2027, month: 1, day: 1))
    #expect(time.secondsOfDay == 5)
    #expect(time.fraction == 0.5)
}

@Test func timeCrossesTheEndOfFebruaryInALeapYear() {
    let time = UTCTime(startDate: UTCDate(year: 2028, month: 2, day: 28), startSecondsOfDay: 86_000, elapsedSeconds: 86_400)
    #expect(time.date == UTCDate(year: 2028, month: 2, day: 29))
    #expect(time.secondsOfDay == 86_000)
}

@Test func timeOfAStepIsTheStartPlusTheSimulationTime() {
    let initial = InitialConditions(
        scenarioID: "t", settings: CoreSettings(radioHeightCallouts: []),
        utcStartDate: UTCDate(year: 2026, month: 3, day: 1), utcStartSecondsOfDay: 3600, seed: 0
    )
    let time = UTCTime(context: StepContext(step: 30_025, events: [], initial: initial))
    #expect(time.date == UTCDate(year: 2026, month: 3, day: 1))
    #expect(time.secondsOfDay == 4200)
    #expect(abs(time.fraction - 0.5) < 1e-9)
}

@Test func decimalYear() {
    #expect(UTCTime(date: UTCDate(year: 2025, month: 1, day: 1), secondsOfDay: 0, fraction: 0).decimalYear == 2025.0)
    let middle = UTCTime(date: UTCDate(year: 2027, month: 7, day: 2), secondsOfDay: 43_200, fraction: 0)
    #expect(abs(middle.decimalYear - 2027.5) < 1e-12)
}
