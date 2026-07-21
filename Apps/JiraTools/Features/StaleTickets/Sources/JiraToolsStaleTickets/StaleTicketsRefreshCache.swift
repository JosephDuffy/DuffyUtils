import Foundation
import JiraAPI

struct StaleTicketsCommentFacts: Sendable {
    let comments: [JiraComment]
    let latestTopLevelCommentDate: Date?
    let latestReplyDate: Date?
    let latestTopLevelCommentDateByAuthor: [String: Date]

    init(comments: [JiraComment]) {
        self.comments = comments
        let topLevelComments = comments.filter { !$0.isReply }
        let replies = comments.filter(\.isReply)
        latestTopLevelCommentDate = topLevelComments.compactMap { parseJiraDate($0.created) }.max()
        latestReplyDate = replies.compactMap { parseJiraDate($0.created) }.max()
        latestTopLevelCommentDateByAuthor = topLevelComments.reduce(into: [:]) { dates, comment in
            guard let date = parseJiraDate(comment.created) else {
                return
            }

            dates[comment.author.accountId] = max(dates[comment.author.accountId] ?? .distantPast, date)
        }
    }
}

public actor StaleTicketsRefreshCache {
    private struct IssueKey: Hashable, Sendable {
        let baseURL: URL
        let issueID: String
    }

    private struct CachedCommentFacts: Sendable {
        let updated: String
        let facts: StaleTicketsCommentFacts
    }

    private struct ExtraFieldsKey: Hashable, Sendable {
        let baseURL: URL
        let configuredFields: [String]
    }

    private var commentFactsByIssue: [IssueKey: CachedCommentFacts] = [:]
    private var currentUsersByBaseURL: [URL: JiraUser] = [:]
    private var extraFieldsByConfiguration: [ExtraFieldsKey: [JiraField]] = [:]

    public init() {}

    func commentFacts(
        for issue: JiraIssue,
        baseURL: URL,
    ) -> StaleTicketsCommentFacts? {
        guard let updated = issue.fields.updated,
              let cachedFacts = commentFactsByIssue[IssueKey(baseURL: baseURL, issueID: issue.id)],
              cachedFacts.updated == updated else {
            return nil
        }

        return cachedFacts.facts
    }

    func storeCommentFacts(
        _ facts: StaleTicketsCommentFacts,
        for issue: JiraIssue,
        baseURL: URL,
    ) {
        guard let updated = issue.fields.updated else {
            return
        }

        commentFactsByIssue[IssueKey(baseURL: baseURL, issueID: issue.id)] = CachedCommentFacts(
            updated: updated,
            facts: facts,
        )
    }

    func pruneCommentFacts(
        for issueIDs: Set<String>,
        baseURL: URL,
    ) {
        commentFactsByIssue = commentFactsByIssue.filter { key, _ in
            key.baseURL != baseURL || issueIDs.contains(key.issueID)
        }
    }

    func currentUser(for baseURL: URL) -> JiraUser? {
        currentUsersByBaseURL[baseURL]
    }

    func storeCurrentUser(
        _ user: JiraUser,
        for baseURL: URL,
    ) {
        currentUsersByBaseURL[baseURL] = user
    }

    func extraFields(
        configuredFields: [String],
        baseURL: URL,
    ) -> [JiraField]? {
        extraFieldsByConfiguration[ExtraFieldsKey(
            baseURL: baseURL,
            configuredFields: configuredFields,
        )]
    }

    func storeExtraFields(
        _ fields: [JiraField],
        configuredFields: [String],
        baseURL: URL,
    ) {
        extraFieldsByConfiguration[ExtraFieldsKey(
            baseURL: baseURL,
            configuredFields: configuredFields,
        )] = fields
    }
}
