import Foundation
import Testing
@testable import JiraAPI

@Suite
struct JiraAPITests {
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

    @Test
    func commentDecodesRichBodyAndPreservesUnknownNodes() throws {
        let comment = try JSONDecoder().decode(JiraComment.self, from: Data("""
        {
          "id": "1",
          "author": { "accountId": "author" },
          "created": "2026-07-13T09:30:00.000+0000",
          "body": {
            "type": "doc",
            "version": 1,
            "content": [
              {
                "type": "paragraph",
                "content": [
                  {
                    "type": "text",
                    "text": "Read the guide",
                    "marks": [
                      { "type": "strong" },
                      { "type": "link", "attrs": { "href": "https://example.com" } }
                    ]
                  }
                ]
              },
              {
                "type": "futureNode",
                "attrs": { "metadata": { "source": "future" } },
                "content": [
                  { "type": "text", "text": "Still available" }
                ]
              }
            ]
          }
        }
        """.utf8))

        let body = try #require(comment.body)
        #expect(body.type == "doc")
        #expect(body.version == 1)
        #expect(body.content[0].content[0].marks.map(\.type) == ["strong", "link"])
        #expect(body.content[0].content[0].marks[1].attributes["href"]?.stringValue == "https://example.com")
        #expect(body.content[1].type == "futureNode")
        #expect(body.content[1].attributes["metadata"]?.objectValue?["source"]?.stringValue == "future")
        #expect(body.content[1].content[0].text == "Still available")
    }

    @Test
    func commentAllowsMissingAndNullBodies() throws {
        let comments = try JSONDecoder().decode([JiraComment].self, from: Data("""
        [
          {
            "id": "1",
            "author": { "accountId": "author" },
            "created": "2026-07-13T09:30:00.000+0000"
          },
          {
            "id": "2",
            "author": { "accountId": "author" },
            "created": "2026-07-13T09:30:00.000+0000",
            "body": null
          }
        ]
        """.utf8))

        #expect(comments.allSatisfy { $0.body == nil })
    }
}

private extension JiraCommentBodyValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }

    var objectValue: [String: JiraCommentBodyValue]? {
        guard case .object(let value) = self else {
            return nil
        }

        return value
    }
}
