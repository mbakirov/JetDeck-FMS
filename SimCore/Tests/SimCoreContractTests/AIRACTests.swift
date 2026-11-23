import Foundation
import Testing
@testable import SimCoreContract

@Test func calendarDateRoundTrip() {
    for days in stride(from: -800_000, through: 800_000, by: 997) {
        let date = CalendarDate(daysSince1970: days)
        #expect(date.daysSince1970 == days)
        #expect(CalendarDate(year: date.year, month: date.month, day: date.day) == date)
    }
    #expect(CalendarDate(daysSince1970: 0).description == "1970-01-01")
    #expect(CalendarDate(year: 2024, month: 2, day: 29) != nil)
    #expect(CalendarDate(year: 2026, month: 2, day: 29) == nil)
    #expect(CalendarDate(year: 2100, month: 2, day: 29) == nil)
    #expect(CalendarDate(year: 2000, month: 2, day: 29) != nil)
    #expect(CalendarDate(iso: "2026-10-29")?.adding(days: 28).description == "2026-11-26")
    #expect(CalendarDate(iso: "2026-1-29") == nil)
}

@Test func airacCycles() throws {
    let cycle = try #require(AIRACCycle(ident: "2611"))
    #expect(cycle.effective.description == "2026-10-29")
    #expect(cycle.lastDay.description == "2026-11-25")
    #expect(cycle.next.ident == "2612")
    #expect(cycle.next.effective.description == "2026-11-26")
    #expect(cycle.previous.ident == "2610")
    #expect(AIRACCycle(containing: CalendarDate(iso: "2026-11-22")!) == cycle)
    #expect(AIRACCycle(containing: CalendarDate(iso: "2026-11-26")!).ident == "2612")
    #expect(AIRACCycle(ident: "2601")?.effective.description == "2026-01-22")
    // The next cycle after 2613 is 2701.
    #expect(AIRACCycle(ident: "2613")?.next.ident == "2701")
    // 2020 had 14 cycles, 2021 had 13.
    #expect(AIRACCycle(ident: "2014")?.effective.description == "2020-12-31")
    #expect(AIRACCycle(ident: "2114") == nil)
    #expect(AIRACCycle(ident: "2600") == nil)
    #expect(AIRACCycle(ident: "26AB") == nil)
    #expect(AIRACCycle(ident: "+611") == nil)
    #expect(AIRACCycle(ident: "-611") == nil)
    #expect(AIRACCycle(ident: " 611") == nil)
    #expect(AIRACCycle(ident: "２６１１") == nil)
    #expect(AIRACCycle(ident: "2601")! < cycle)
}

@Test func identityJSON() throws {
    let identity = NavDataIdentity(cycle: AIRACCycle(ident: "2611")!, schemaVersion: 1, builderVersion: 1,
                                   sourceSHA256: String(repeating: "a", count: 64))
    let data = try SimCoreJSON.encode(identity)
    #expect(String(decoding: data, as: UTF8.self).contains("\"cycle\":\"2611\""))
    #expect(try SimCoreJSON.decode(NavDataIdentity.self, from: data) == identity)
    #expect(throws: DecodingError.self) {
        try SimCoreJSON.decode(AIRACCycle.self, from: Data("\"2699\"".utf8))
    }
}
