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

    @Test
    func cacheReusesFactsOnlyWhenTheIssueUpdateMarkerMatches() async throws {
        let cache = StaleTicketsRefreshCache()
        let baseURL = try #require(URL(string: "https://example.atlassian.net"))
        let originalIssue = try issue(updated: "2026-07-13T09:30:00.000+0000")
        let changedIssue = try issue(updated: "2026-07-13T10:30:00.000+0000")
        let comments = try JSONDecoder().decode([JiraComment].self, from: Data("""
        [
          {
            "id": "1",
            "author": { "accountId": "assignee" },
            "created": "2026-07-12T09:30:00.000+0000"
          },
          {
            "id": "2",
            "author": { "accountId": "other" },
            "created": "2026-07-13T09:30:00.000+0000",
            "parentId": "1"
          }
        ]
        """.utf8))

        await cache.storeCommentFacts(
            StaleTicketsCommentFacts(comments: comments),
            for: originalIssue,
            baseURL: baseURL,
        )

        let cachedFacts = await cache.commentFacts(for: originalIssue, baseURL: baseURL)
        let invalidatedFacts = await cache.commentFacts(for: changedIssue, baseURL: baseURL)

        #expect(cachedFacts?.latestTopLevelCommentDate == parseJiraDate("2026-07-12T09:30:00.000+0000"))
        #expect(cachedFacts?.latestReplyDate == parseJiraDate("2026-07-13T09:30:00.000+0000"))
        #expect(cachedFacts?.latestTopLevelCommentDateByAuthor["assignee"] == parseJiraDate("2026-07-12T09:30:00.000+0000"))
        #expect(invalidatedFacts == nil)

        await cache.pruneCommentFacts(for: [], baseURL: baseURL)
        let prunedFacts = await cache.commentFacts(for: originalIssue, baseURL: baseURL)
        #expect(prunedFacts == nil)
    }

    @Test
    func cacheRetainsRefreshMetadataForTheActiveSession() async throws {
        let cache = StaleTicketsRefreshCache()
        let baseURL = try #require(URL(string: "https://example.atlassian.net"))
        let user = try JSONDecoder().decode(JiraUser.self, from: Data("""
        { "accountId": "current-user", "displayName": "Current User" }
        """.utf8))
        let fields = [JiraField(id: "customfield_123", name: "Customer")]

        await cache.storeCurrentUser(user, for: baseURL)
        await cache.storeExtraFields(
            fields,
            configuredFields: ["Customer"],
            baseURL: baseURL,
        )

        let cachedUser = await cache.currentUser(for: baseURL)
        let cachedFields = await cache.extraFields(
            configuredFields: ["Customer"],
            baseURL: baseURL,
        )

        #expect(cachedUser?.accountId == "current-user")
        #expect(cachedFields?.map(\.id) == ["customfield_123"])
    }

    @Test
    func explicitCustomFieldIDDoesNotNeedFieldLookup() async throws {
        let client = JiraClient(
            baseURL: try #require(URL(string: "https://example.atlassian.net")),
            authorization: .oauth(accessToken: "token"),
            extraFieldIDs: [],
        )

        let fields = try await resolveJiraFields(["customfield_123"], client: client)

        #expect(fields.map(\.id) == ["customfield_123"])
        #expect(fields.map(\.name) == ["customfield_123"])
    }

    private func issue(updated: String) throws -> JiraIssue {
        try JSONDecoder().decode(JiraIssue.self, from: Data("""
        {
          "id": "10001",
          "key": "TEST-1",
          "fields": {
            "summary": "A ticket",
            "status": { "name": "Open" },
            "updated": "\(updated)"
          }
        }
        """.utf8))
    }
}
