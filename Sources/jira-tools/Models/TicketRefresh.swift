import Foundation

struct TicketsConfiguration: Sendable {
    var warningHours: TimeInterval
    var errorHours: TimeInterval
    var greenHours: TimeInterval
    var maxResults: Int
    var extraFields: [String]
    var deemphasizedStatuses: [String]
    var highlightedCommentSources: Set<HighlightedCommentSource>
    var sort: TicketSort
}

struct RefreshSnapshot: Sendable {
    let reports: [TicketReport]
    let extraFields: [JiraField]
    let currentUserName: String
    let updatedAt: Date
    let errors: [String]
    let status: RefreshStatus

    func addingError(_ error: Error) -> RefreshSnapshot {
        RefreshSnapshot(
            reports: reports,
            extraFields: extraFields,
            currentUserName: currentUserName,
            updatedAt: updatedAt,
            errors: [String(describing: error)] + errors,
            status: .failed,
        )
    }
}

enum RefreshStatus: Sendable {
    case queryingFilter
    case checkingComments(completed: Int, total: Int)
    case complete
    case failed
}

struct TicketReport: Sendable {
    let issue: JiraIssue
    let latestCommentDate: Date?
    let latestReplyDate: Date?
    let latestCurrentUserCommentDate: Date?
    let latestAssigneeCommentDate: Date?
    let highlightSeverities: [HighlightedCommentSource: Severity]
    let severity: Severity
    let isDeemphasized: Bool
    let areCommentsLoading: Bool
    let error: String?
}

enum HighlightedCommentSource: String, CaseIterable, Sendable {
    case currentUser = "current-user"
    case anyUser = "any-user"
    case assignee
}

enum TicketSort: String, Sendable {
    case latestComment = "latest-comment"
    case currentUser = "current-user"
    case assignee
}

struct TicketState: Equatable, Sendable {
    let severity: Severity
    let latestCurrentUserCommentDate: Date?
    let latestAssigneeCommentDate: Date?
    let latestCommentDate: Date?
    let latestReplyDate: Date?
    let highlightSeverities: [HighlightedCommentSource: Severity]
    let areCommentsLoading: Bool
    let error: String?

    init(report: TicketReport) {
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

struct TicketRefreshService: Sendable {
    let credentials: JiraCredentials
    let location: ResolvedJiraLocation
    let configuration: TicketsConfiguration

    func refresh(progress: ((RefreshSnapshot) -> Void)? = nil) async throws -> RefreshSnapshot {
        var errors: [String] = []
        progress?(RefreshSnapshot(
            reports: [],
            extraFields: [],
            currentUserName: "unknown",
            updatedAt: Date(),
            errors: errors,
            status: .queryingFilter,
        ))

        let setupClient = JiraClient(
            baseURL: location.baseURL,
            credentials: credentials,
            extraFieldIDs: [],
        )
        let currentUser = try await setupClient.currentUser()
        let extraFields: [JiraField]

        do {
            extraFields = try await resolveJiraFields(
                configuration.extraFields,
                client: setupClient,
            )
        } catch {
            extraFields = []
            errors.append(String(describing: error))
        }

        let client = JiraClient(
            baseURL: location.baseURL,
            credentials: credentials,
            extraFieldIDs: extraFields.map(\.id),
        )
        var fields = [
            "summary",
            "status",
            "assignee",
        ]
        fields.append(contentsOf: extraFields.map(\.id))

        let issues = try await client.searchIssues(
            jql: location.jql,
            maxResults: configuration.maxResults,
            fields: fields,
        )
        var reportsByKey = Dictionary(
            uniqueKeysWithValues: issues.map { issue in
                (issue.key, loadingReport(for: issue))
            },
        )
        let extraFieldIDs = extraFields.map(\.id)

        progress?(snapshot(
            reports: Array(reportsByKey.values),
            extraFields: extraFields,
            currentUserName: currentUser.displayName ?? currentUser.accountId,
            errors: errors,
            status: .checkingComments(completed: 0, total: issues.count),
        ))

        await withTaskGroup(of: TicketReport.self) { group in
            for issue in issues {
                let location = location
                let credentials = credentials
                let configuration = configuration
                let currentUserAccountId = currentUser.accountId

                group.addTask {
                    let client = JiraClient(
                        baseURL: location.baseURL,
                        credentials: credentials,
                        extraFieldIDs: extraFieldIDs,
                    )
                    return await Self.report(
                        for: issue,
                        client: client,
                        currentUserAccountId: currentUserAccountId,
                        configuration: configuration,
                    )
                }
            }

            var completed = 0
            for await report in group {
                completed += 1
                reportsByKey[report.issue.key] = report
                progress?(snapshot(
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
        reports: [TicketReport],
        extraFields: [JiraField],
        currentUserName: String,
        errors: [String],
        status: RefreshStatus,
    ) -> RefreshSnapshot {
        RefreshSnapshot(
            reports: sortedReports(reports),
            extraFields: extraFields,
            currentUserName: currentUserName,
            updatedAt: Date(),
            errors: errors,
            status: status,
        )
    }

    private func loadingReport(for issue: JiraIssue) -> TicketReport {
        TicketReport(
            issue: issue,
            latestCommentDate: nil,
            latestReplyDate: nil,
            latestCurrentUserCommentDate: nil,
            latestAssigneeCommentDate: nil,
            highlightSeverities: [:],
            severity: .neutral,
            isDeemphasized: isDeemphasizedStatus(
                issue.fields.status.name,
                statuses: configuration.deemphasizedStatuses,
            ),
            areCommentsLoading: true,
            error: nil,
        )
    }

    private static func report(
        for issue: JiraIssue,
        client: JiraClient,
        currentUserAccountId: String,
        configuration: TicketsConfiguration,
    ) async -> TicketReport {
        do {
            let comments = try await client.comments(for: issue.key)
            return report(
                for: issue,
                comments: comments,
                currentUserAccountId: currentUserAccountId,
                configuration: configuration,
                error: nil,
            )
        } catch {
            return report(
                for: issue,
                comments: [],
                currentUserAccountId: currentUserAccountId,
                configuration: configuration,
                error: String(describing: error),
            )
        }
    }

    private static func report(
        for issue: JiraIssue,
        comments: [JiraComment],
        currentUserAccountId: String,
        configuration: TicketsConfiguration,
        error: String?,
    ) -> TicketReport {
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

                return (source, severity(for: commentDate, configuration: configuration))
            },
        )

        return TicketReport(
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

    private func sortedReports(_ reports: [TicketReport]) -> [TicketReport] {
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

    private func sortDate(for report: TicketReport) -> Date? {
        switch configuration.sort {
        case .latestComment:
            report.latestCommentDate
        case .currentUser:
            report.latestCurrentUserCommentDate
        case .assignee:
            report.latestAssigneeCommentDate
        }
    }
}

func resolveJiraFields(
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

        throw AppError("Could not find Jira field named '\(configuredField)'. Pass a customfield_XXXXX id if the field has a different name.")
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

func severity(
    for latestCommentDate: Date?,
    configuration: TicketsConfiguration,
) -> Severity {
    guard let latestCommentDate else {
        return .error
    }

    let ageHours = Date().timeIntervalSince(latestCommentDate) / 3600
    if ageHours >= configuration.errorHours {
        return .error
    }

    if ageHours >= configuration.warningHours {
        return .warning
    }

    if ageHours <= configuration.greenHours {
        return .ok
    }

    return .neutral
}

func isDeemphasizedStatus(
    _ status: String,
    statuses: [String],
) -> Bool {
    statuses.contains {
        $0.caseInsensitiveCompare(status) == .orderedSame
    }
}
