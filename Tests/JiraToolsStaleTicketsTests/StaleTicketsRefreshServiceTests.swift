import Foundation
import JiraToolsCore
@testable import JiraToolsStaleTickets
import JiraToolsStaleTicketsUI
import Testing

@Suite
struct StaleTicketsRefreshServiceTests {
    @Test
    func severityUsesInjectedDate() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let configuration = StaleTicketsConfiguration(
            warningDuration: .seconds(20 * 3_600),
            errorDuration: .seconds(24 * 3_600),
            okDuration: .seconds(4 * 3_600),
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

    @Test
    func draftPreservesThresholdDurations() throws {
        let configuration = StaleTicketsConfiguration(
            warningDuration: .seconds(20 * 3_600),
            errorDuration: .seconds(24 * 3_600),
            okDuration: .seconds(4 * 3_600),
            maxResults: 100,
            extraFields: [],
            deemphasizedStatuses: [],
            highlightedCommentSources: [.assignee],
            sort: .latestComment,
        )
        let draft = StaleTicketsConfigurationDraft(
            configuration: configuration,
            filterInput: "123",
            queryMode: .filter,
            baseURL: "https://example.atlassian.net",
            refreshInterval: 60,
        )

        #expect(draft.okDuration == configuration.okDuration)
        #expect(draft.warningDuration == configuration.warningDuration)
        #expect(draft.errorDuration == configuration.errorDuration)

        let validatedConfiguration = try draft.validatedConfiguration()
        #expect(validatedConfiguration.okDuration == configuration.okDuration)
        #expect(validatedConfiguration.warningDuration == configuration.warningDuration)
        #expect(validatedConfiguration.errorDuration == configuration.errorDuration)
    }
}
