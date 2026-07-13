import Foundation
import JiraToolsCore
import JiraToolsStaleTickets

public struct StaleTicketsTableRow: Identifiable {
    public let report: StaleTicketsReport
    public let extraFieldValues: [String: String]
    public let extraFieldsDisplay: String

    public var id: String {
        report.issue.key
    }

    public var severityRank: Int {
        switch report.severity {
        case .error:
            0
        case .warning:
            1
        case .neutral:
            2
        case .ok:
            3
        }
    }

    public var severityLabel: String {
        switch report.severity {
        case .error:
            "Error"
        case .warning:
            "Warning"
        case .neutral:
            "Info"
        case .ok:
            "OK"
        }
    }

    public var key: String {
        report.issue.key
    }

    public var status: String {
        report.issue.fields.status.name
    }

    public var assignee: String {
        report.issue.fields.assignee?.displayName ?? "Unassigned"
    }

    public var summary: String {
        report.issue.fields.summary
    }

    public var currentUserCommentDate: Date {
        report.latestCurrentUserCommentDate ?? .distantPast
    }

    public var assigneeCommentDate: Date {
        report.latestAssigneeCommentDate ?? .distantPast
    }

    public var latestCommentDate: Date {
        report.latestCommentDate ?? .distantPast
    }

    public var latestReplyDate: Date {
        report.latestReplyDate ?? .distantPast
    }

    public init(report: StaleTicketsReport, extraFields: [JiraField]) {
        self.report = report
        extraFieldValues = Dictionary(
            uniqueKeysWithValues: extraFields.map { field in
                (field.id, report.issue.fields.extraFields[field.id]?.displayValue ?? "—")
            },
        )
        extraFieldsDisplay = extraFields
            .map { field in
                "\(field.name): \(report.issue.fields.extraFields[field.id]?.displayValue ?? "—")"
            }
            .joined(separator: "\n")
    }

    public func extraFieldValue(for fieldID: String) -> String {
        extraFieldValues[fieldID] ?? "—"
    }
}
