import Foundation
import Testing
@testable import JiraToolsCore

@Suite
struct JiraToolsCoreTests {
    @Test
    func filterURLResolvesBaseURLAndJQL() throws {
        let location = try resolveJiraLocation(
            filterURL: URL(string: "https://example.atlassian.net/issues/?jql=project%20%3D%20TEST"),
            jql: nil,
            baseURL: nil,
        )

        #expect(location.baseURL == URL(string: "https://example.atlassian.net"))
        #expect(location.jql == "project = TEST")
    }

    @Test
    func filterURLResolvesFilterID() throws {
        let location = try resolveJiraLocation(
            filterURL: URL(string: "https://example.atlassian.net/issues/?filter=12345"),
            jql: nil,
            baseURL: nil,
        )

        #expect(location.jql == "filter = 12345")
    }

    @Test
    func jiraURLAddsHTTPSWhenTheSchemeIsOmitted() {
        #expect(jiraURL(from: "example.atlassian.net") == URL(string: "https://example.atlassian.net"))
    }

    @Test
    func jiraToolsErrorHasAUserFacingDescription() {
        let error = JiraToolsError("The Jira token was rejected.")

        #expect(error.localizedDescription == "The Jira token was rejected.")
    }

    @Test
    func issueDecodesUpdatedField() throws {
        let issue = try JSONDecoder().decode(JiraIssue.self, from: Data("""
        {
          "id": "10001",
          "key": "TEST-1",
          "fields": {
            "summary": "A ticket",
            "status": { "name": "Open" },
            "updated": "2026-07-13T09:30:00.000+0000"
          }
        }
        """.utf8))

        #expect(issue.fields.updated == "2026-07-13T09:30:00.000+0000")
    }
}
