import JiraToolsStaleTickets
import Testing
@testable import JiraToolsStaleTicketsUI

@Suite
struct StaleTicketsConfigurationDraftTests {
    @Test
    func preservesThresholdDurations() throws {
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
