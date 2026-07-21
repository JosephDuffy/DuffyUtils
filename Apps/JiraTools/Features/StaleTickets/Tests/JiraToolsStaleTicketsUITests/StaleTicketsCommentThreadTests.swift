import Foundation
import JiraAPI
@testable import JiraToolsStaleTicketsUI
import Testing

@Suite
struct StaleTicketsCommentThreadTests {
    @Test
    func ordersThreadsChronologicallyAndRetainsOrphanReplies() throws {
        let comments = try JSONDecoder().decode([JiraComment].self, from: Data("""
        [
          {
            "id": "reply",
            "author": { "accountId": "author" },
            "created": "2026-07-13T11:00:00.000+0000",
            "parentId": "parent"
          },
          {
            "id": "later",
            "author": { "accountId": "author" },
            "created": "2026-07-13T12:00:00.000+0000"
          },
          {
            "id": "orphan",
            "author": { "accountId": "author" },
            "created": "2026-07-13T10:00:00.000+0000",
            "parentId": "missing"
          },
          {
            "id": "parent",
            "author": { "accountId": "author" },
            "created": "2026-07-13T09:00:00.000+0000"
          }
        ]
        """.utf8))

        let threads = StaleTicketsCommentThread.make(from: comments)

        #expect(threads.map(\.comment.id) == ["parent", "orphan", "later"])
        #expect(threads[0].replies.map(\.comment.id) == ["reply"])
        #expect(threads.flatMap(\.replies).map(\.comment.id) == ["reply"])
    }

    @Test
    func retainsCommentsWhenParentRelationshipsContainCycles() throws {
        let comments = try JSONDecoder().decode([JiraComment].self, from: Data("""
        [
          {
            "id": "one",
            "author": { "accountId": "author" },
            "created": "2026-07-13T09:00:00.000+0000",
            "parentId": "two"
          },
          {
            "id": "two",
            "author": { "accountId": "author" },
            "created": "2026-07-13T10:00:00.000+0000",
            "parentId": "one"
          }
        ]
        """.utf8))

        let threads = StaleTicketsCommentThread.make(from: comments)

        let renderedCommentIDs = threads.flatMap { thread in
            [thread.comment.id] + thread.replies.map(\.comment.id)
        }
        #expect(Set(renderedCommentIDs) == Set(["one", "two"]))
    }
}
