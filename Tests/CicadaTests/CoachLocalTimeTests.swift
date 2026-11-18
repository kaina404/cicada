import Foundation
import Testing
@testable import Cicada

struct CoachLocalTimeTests {
    private func at(_ hour: Int, _ minute: Int = 5) -> (Date, Calendar) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return (calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: hour, minute: minute))!, calendar)
    }

    @Test func greetingFollowsTheLocalHour() {
        let (afternoon, cal) = at(13)
        #expect(CoachPrompt.localTime(afternoon, calendar: cal, language: .english).contains("13:05"))
        #expect(CoachPrompt.localTime(afternoon, calendar: cal, language: .english).contains("Good afternoon"))
        #expect(CoachPrompt.localTime(at(9).0, calendar: cal, language: .english).contains("Good morning"))
        #expect(CoachPrompt.localTime(at(20).0, calendar: cal, language: .english).contains("Good evening"))
        #expect(CoachPrompt.localTime(at(9).0, calendar: cal, language: .chinese).contains("早上好"))
    }
}
