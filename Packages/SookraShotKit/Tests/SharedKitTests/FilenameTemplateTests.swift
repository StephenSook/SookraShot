import Foundation
import Testing
@testable import SharedKit

@Suite struct FilenameTemplateTests {
    private var fixedDate: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 11
        components.hour = 9
        components.minute = 5
        components.second = 3
        components.calendar = Calendar(identifier: .gregorian)
        return components.date!
    }

    @Test func expandsAllDateTokens() {
        let template = FilenameTemplate(pattern: "Shot %y-%m-%d at %H.%M.%S")
        let name = template.filename(for: fixedDate, calendar: Calendar(identifier: .gregorian))
        #expect(name == "Shot 2026-07-11 at 09.05.03")
    }

    @Test func counterTokenExpandsWhenProvided() {
        let template = FilenameTemplate(pattern: "Shot %i")
        #expect(template.filename(for: fixedDate, counter: 42) == "Shot 42")
    }

    @Test func counterTokenRemovedWhenAbsent() {
        let template = FilenameTemplate(pattern: "Shot %i")
        #expect(template.filename(for: fixedDate) == "Shot")
    }

    @Test func defaultTemplateProducesReadableName() {
        let name = FilenameTemplate.default.filename(for: fixedDate, calendar: Calendar(identifier: .gregorian))
        #expect(name == "SookraShot 2026-07-11 at 09.05.03")
    }
}
