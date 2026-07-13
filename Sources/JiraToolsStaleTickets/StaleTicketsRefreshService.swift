import Foundation
import JiraToolsCore

public struct StaleTicketsConfiguration: Codable, Sendable {
    public var warningDuration: Duration
    public var errorDuration: Duration
    public var okDuration: Duration
    public var maxResults: Int
    public var extraFields: [String]
    public var deemphasizedStatuses: [String]
    public var highlightedCommentSources: Set<HighlightedCommentSource>
    public var sort: TicketSort

    public init(
        warningDuration: Duration,
        errorDuration: Duration,
        okDuration: Duration,
        maxResults: Int,
        extraFields: [String],
        deemphasizedStatuses: [String],
        highlightedCommentSources: Set<HighlightedCommentSource>,
        sort: TicketSort,
    ) {
        self.warningDuration = warningDuration
        self.errorDuration = errorDuration
        self.okDuration = okDuration
        self.maxResults = maxResults
        self.extraFields = extraFields
        self.deemphasizedStatuses = deemphasizedStatuses
        self.highlightedCommentSources = highlightedCommentSources
        self.sort = sort
    }
}

public struct StaleTicketsSnapshot: Sendable {
    public let reports: [StaleTicketsReport]
    public let extraFields: [JiraField]
    public let currentUserName: String
    public let updatedAt: Date
    public let errors: [String]
    public let status: StaleTicketsRefreshStatus

    public init(
        reports: [StaleTicketsReport],
        extraFields: [JiraField],
        currentUserName: String,
        updatedAt: Date,
        errors: [String],
        status: StaleTicketsRefreshStatus,
    ) {
        self.reports = reports
        self.extraFields = extraFields
        self.currentUserName = currentUserName
        self.updatedAt = updatedAt
        self.errors = errors
        self.status = status
    }

    public func addingError(_ error: Error) -> StaleTicketsSnapshot {
        StaleTicketsSnapshot(
            reports: reports,
            extraFields: extraFields,
            currentUserName: currentUserName,
            updatedAt: updatedAt,
            errors: [String(describing: error)] + errors,
            status: .failed,
        )
    }
}

public enum StaleTicketsRefreshStatus: Sendable {
    case queryingFilter
    case checkingComments(completed: Int, total: Int)
    case complete
    case failed
}

public struct StaleTicketsReport: Sendable {
    public let issue: JiraIssue
    public let latestCommentDate: Date?
    public let latestReplyDate: Date?
    public let latestCurrentUserCommentDate: Date?
    public let latestAssigneeCommentDate: Date?
    public let highlightSeverities: [HighlightedCommentSource: Severity]
    public let severity: Severity
    public let isDeemphasized: Bool
    public let areCommentsLoading: Bool
    public let error: String?
}

public enum HighlightedCommentSource: String, CaseIterable, Codable, Sendable {
    case currentUser = "current-user"
    case anyUser = "any-user"
    case assignee
}

public enum TicketSort: String, Codable, Sendable {
    case latestComment = "latest-comment"
    case currentUser = "current-user"
    case assignee
}

public struct StaleTicketState: Equatable, Sendable {
    public let severity: Severity
    public let latestCurrentUserCommentDate: Date?
    public let latestAssigneeCommentDate: Date?
    public let latestCommentDate: Date?
    public let latestReplyDate: Date?
    public let highlightSeverities: [HighlightedCommentSource: Severity]
    public let areCommentsLoading: Bool
    public let error: String?

    public init(report: StaleTicketsReport) {
        severity = report.severity
        latestCurrentUserCommentDate = report.latestCurrentUserCommentDate
        latestAssigneeCommentDate = report.latestAssigneeCommentDate
        latestCommentDate = report.latestCommentDate
        latestReplyDate = report.latestReplyDate
        highlightSeverities = report.highlightSeverities
        areCommentsLoading = report.areCommentsLoading
        error = report.error
    }
}

public struct StaleTicketsRequest: Sendable {
    public let authorization: JiraAuthorization
    public let location: ResolvedJiraLocation
    public let configuration: StaleTicketsConfiguration

    public init(
        authorization: JiraAuthorization,
        location: ResolvedJiraLocation,
        configuration: StaleTicketsConfiguration,
    ) {
        self.authorization = authorization
        self.location = location
        self.configuration = configuration
    }
}

public struct StaleTicketsRefreshService: Sendable {
    public let request: StaleTicketsRequest
    private let now: @Sendable () -> Date
    private let session: URLSession

    public init(
        request: StaleTicketsRequest,
        now: @escaping @Sendable () -> Date = { Date() },
        session: URLSession = .shared,
    ) {
        self.request = request
        self.now = now
        self.session = session
    }

    public func refresh() -> AsyncThrowingStream<StaleTicketsSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let snapshot = try await refresh { snapshot in
                        continuation.yield(snapshot)
                    }
                    continuation.yield(snapshot)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func refresh(
        progress: @escaping (StaleTicketsSnapshot) -> Void = { _ in },
    ) async throws -> StaleTicketsSnapshot {
        var errors: [String] = []
        progress(StaleTicketsSnapshot(
            reports: [],
            extraFields: [],
            currentUserName: "unknown",
            updatedAt: now(),
            errors: errors,
            status: .queryingFilter,
        ))

        let setupClient = JiraClient(
            baseURL: request.location.baseURL,
            authorization: request.authorization,
            extraFieldIDs: [],
            session: session,
        )
        let currentUser = try await setupClient.currentUser()
        let extraFields: [JiraField]

        do {
            extraFields = try await resolveJiraFields(
                request.configuration.extraFields,
                client: setupClient,
            )
        } catch {
            extraFields = []
            errors.append(String(describing: error))
        }

        let client = JiraClient(
            baseURL: request.location.baseURL,
            authorization: request.authorization,
            extraFieldIDs: extraFields.map(\.id),
            session: session,
        )
        var fields = [
            "summary",
            "status",
            "assignee",
        ]
        fields.append(contentsOf: extraFields.map(\.id))

        let issues = try await client.searchIssues(
            jql: request.location.jql,
            maxResults: request.configuration.maxResults,
            fields: fields,
        )
        var reportsByKey = Dictionary(
            uniqueKeysWithValues: issues.map { issue in
                (issue.key, loadingReport(for: issue))
            },
        )
        let extraFieldIDs = extraFields.map(\.id)

        progress(snapshot(
            reports: Array(reportsByKey.values),
            extraFields: extraFields,
            currentUserName: currentUser.displayName ?? currentUser.accountId,
            errors: errors,
            status: .checkingComments(completed: 0, total: issues.count),
        ))

        await withTaskGroup(of: StaleTicketsReport.self) { group in
            for issue in issues {
                let request = request
                let currentUserAccountId = currentUser.accountId
                let session = session
                let now = now

                group.addTask {
                    let client = JiraClient(
                        baseURL: request.location.baseURL,
                        authorization: request.authorization,
                        extraFieldIDs: extraFieldIDs,
                        session: session,
                    )
                    return await Self.report(
                        for: issue,
                        client: client,
                        currentUserAccountId: currentUserAccountId,
                        configuration: request.configuration,
                        now: now(),
                    )
                }
            }

            var completed = 0
            for await report in group {
                completed += 1
                reportsByKey[report.issue.key] = report
                progress(snapshot(
                    reports: Array(reportsByKey.values),
                    extraFields: extraFields,
                    currentUserName: currentUser.displayName ?? currentUser.accountId,
                    errors: errors,
                    status: .checkingComments(completed: completed, total: issues.count),
                ))
            }
        }

        return snapshot(
            reports: Array(reportsByKey.values),
            extraFields: extraFields,
            currentUserName: currentUser.displayName ?? currentUser.accountId,
            errors: errors,
            status: .complete,
        )
    }

    private func snapshot(
        reports: [StaleTicketsReport],
        extraFields: [JiraField],
        currentUserName: String,
        errors: [String],
        status: StaleTicketsRefreshStatus,
    ) -> StaleTicketsSnapshot {
        StaleTicketsSnapshot(
            reports: sortedReports(reports),
            extraFields: extraFields,
            currentUserName: currentUserName,
            updatedAt: now(),
            errors: errors,
            status: status,
        )
    }

    private func loadingReport(for issue: JiraIssue) -> StaleTicketsReport {
        StaleTicketsReport(
            issue: issue,
            latestCommentDate: nil,
            latestReplyDate: nil,
            latestCurrentUserCommentDate: nil,
            latestAssigneeCommentDate: nil,
            highlightSeverities: [:],
            severity: .neutral,
            isDeemphasized: isDeemphasizedStatus(
                issue.fields.status.name,
                statuses: request.configuration.deemphasizedStatuses,
            ),
            areCommentsLoading: true,
            error: nil,
        )
    }

    private static func report(
        for issue: JiraIssue,
        client: JiraClient,
        currentUserAccountId: String,
        configuration: StaleTicketsConfiguration,
        now: Date,
    ) async -> StaleTicketsReport {
        do {
            let comments = try await client.comments(for: issue.key)
            return report(
                for: issue,
                comments: comments,
                currentUserAccountId: currentUserAccountId,
                configuration: configuration,
                error: nil,
                now: now,
            )
        } catch {
            return report(
                for: issue,
                comments: [],
                currentUserAccountId: currentUserAccountId,
                configuration: configuration,
                error: String(describing: error),
                now: now,
            )
        }
    }

    private static func report(
        for issue: JiraIssue,
        comments: [JiraComment],
        currentUserAccountId: String,
        configuration: StaleTicketsConfiguration,
        error: String?,
        now: Date,
    ) -> StaleTicketsReport {
        let topLevelComments = comments.filter { !$0.isReply }
        let replies = comments.filter(\.isReply)
        let latestTopLevelCommentDate = topLevelComments.compactMap { parseJiraDate($0.created) }.max()
        let latestReplyDate = replies.compactMap { parseJiraDate($0.created) }.max()
        let latestCurrentUserCommentDate = topLevelComments
            .filter { $0.author.accountId == currentUserAccountId }
            .compactMap { parseJiraDate($0.created) }
            .max()
        let assigneeAccountId = issue.fields.assignee?.accountId
        let latestAssigneeCommentDate = latestCommentDate(
            in: topLevelComments,
            by: assigneeAccountId,
        )
        let highlightSeverities = Dictionary(
            uniqueKeysWithValues: configuration.highlightedCommentSources.map { source in
                let commentDate = switch source {
                case .currentUser:
                    latestCurrentUserCommentDate
                case .anyUser:
                    latestTopLevelCommentDate
                case .assignee:
                    latestAssigneeCommentDate
                }

                return (source, severity(for: commentDate, configuration: configuration, now: now))
            },
        )

        return StaleTicketsReport(
            issue: issue,
            latestCommentDate: latestTopLevelCommentDate,
            latestReplyDate: latestReplyDate,
            latestCurrentUserCommentDate: latestCurrentUserCommentDate,
            latestAssigneeCommentDate: latestAssigneeCommentDate,
            highlightSeverities: highlightSeverities,
            severity: highlightSeverities.values.min() ?? .neutral,
            isDeemphasized: isDeemphasizedStatus(
                issue.fields.status.name,
                statuses: configuration.deemphasizedStatuses,
            ),
            areCommentsLoading: false,
            error: error,
        )
    }

    private func sortedReports(_ reports: [StaleTicketsReport]) -> [StaleTicketsReport] {
        reports.sorted {
            switch (sortDate(for: $0), sortDate(for: $1)) {
            case let (lhs?, rhs?):
                lhs < rhs
            case (_?, nil):
                true
            case (nil, _?):
                false
            case (nil, nil):
                $0.issue.key < $1.issue.key
            }
        }
    }

    private func sortDate(for report: StaleTicketsReport) -> Date? {
        switch request.configuration.sort {
        case .latestComment:
            report.latestCommentDate
        case .currentUser:
            report.latestCurrentUserCommentDate
        case .assignee:
            report.latestAssigneeCommentDate
        }
    }
}

public func resolveJiraFields(
    _ configuredFields: [String],
    client: JiraClient,
) async throws -> [JiraField] {
    guard !configuredFields.isEmpty else {
        return []
    }

    let fields = try await client.fields()
    return try configuredFields.map { configuredField in
        if let exactIDMatch = fields.first(where: { $0.id == configuredField }) {
            return exactIDMatch
        }

        if configuredField.hasPrefix("customfield_") {
            return JiraField(id: configuredField, name: configuredField)
        }

        if let exactNameMatch = fields.first(where: { $0.name == configuredField }) {
            return exactNameMatch
        }

        if let caseInsensitiveNameMatch = fields.first(where: { $0.name.caseInsensitiveCompare(configuredField) == .orderedSame }) {
            return caseInsensitiveNameMatch
        }

        throw JiraToolsError("Could not find Jira field named '\(configuredField)'. Pass a customfield_XXXXX id if the field has a different name.")
    }
}

func latestCommentDate(
    in comments: [JiraComment],
    by accountId: String?,
) -> Date? {
    guard let accountId else {
        return nil
    }

    return comments
        .filter { $0.author.accountId == accountId }
        .compactMap { parseJiraDate($0.created) }
        .max()
}

public func severity(
    for latestCommentDate: Date?,
    configuration: StaleTicketsConfiguration,
    now: Date,
) -> Severity {
    guard let latestCommentDate else {
        return .error
    }

    let commentAge = Duration.seconds(now.timeIntervalSince(latestCommentDate))
    if commentAge >= configuration.errorDuration {
        return .error
    }

    if commentAge >= configuration.warningDuration {
        return .warning
    }

    if commentAge <= configuration.okDuration {
        return .ok
    }

    return .neutral
}

public func isDeemphasizedStatus(
    _ status: String,
    statuses: [String],
) -> Bool {
    statuses.contains {
        $0.caseInsensitiveCompare(status) == .orderedSame
    }
}
