import Foundation
import JiraToolsCore
@testable import JiraToolsStaleTickets
import Testing

@Suite
struct StaleTicketsRefreshServiceTests {
    @Test
    func severityUsesInjectedDate() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let configuration = StaleTicketsConfiguration(
            warningHours: 20,
            errorHours: 24,
            greenHours: 4,
            maxResults: 100,
            extraFields: [],
            deemphasizedStatuses: [],
            highlightedCommentSources: [.assignee],
            sort: .latestComment,
        )

        #expect(severity(
            for: now.addingTimeInterval(-4 * 3600),
            configuration: configuration,
            now: now,
        ) == .ok)
        #expect(severity(
            for: now.addingTimeInterval(-20 * 3600),
            configuration: configuration,
            now: now,
        ) == .warning)
        #expect(severity(
            for: now.addingTimeInterval(-24 * 3600),
            configuration: configuration,
            now: now,
        ) == .error)
        #expect(severity(
            for: nil,
            configuration: configuration,
            now: now,
        ) == .error)
    }
}
