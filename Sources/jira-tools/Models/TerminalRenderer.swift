import Darwin
import Foundation

struct RendererConfiguration {
    let location: ResolvedJiraLocation
    let tickets: TicketsConfiguration
    let watch: Bool
    let intervalSeconds: TimeInterval
    let noColor: Bool
}

struct TerminalRenderer {
    let configuration: RendererConfiguration

    var canReplaceOutput: Bool {
        configuration.watch || isatty(STDOUT_FILENO) == 1
    }

    func render(
        _ snapshot: RefreshSnapshot,
        replacingPreviousOutput: Bool = false,
    ) {
        let output = renderHeader(snapshot)
            + renderErrors(snapshot.errors)
            + renderReports(
                snapshot.reports,
                extraFields: snapshot.extraFields,
                status: snapshot.status,
                updatedAt: snapshot.updatedAt,
            )
            + "\u{001B}[0m"

        if configuration.watch || replacingPreviousOutput {
            writeToStandardOutput("\u{001B}[?25l\u{001B}[H\u{001B}[J" + output + "\u{001B}[?25h")
        } else {
            writeToStandardOutput(output)
        }
    }

    func restoreTerminalDisplay() {
        writeToStandardOutput("\u{001B}[0m\u{001B}[?25h")
    }

    private func renderHeader(_ snapshot: RefreshSnapshot) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        var lines = [
            "Jira stale comment watcher",
            "Site: \(configuration.location.baseURL.absoluteString)",
            "JQL: \(configuration.location.jql)",
            "User: \(snapshot.currentUserName)",
            "Status: \(statusText(snapshot.status, updatedAt: snapshot.updatedAt))",
            "Thresholds: ok <= \(formatHours(configuration.tickets.greenHours))h, warning >= \(formatHours(configuration.tickets.warningHours))h, error >= \(formatHours(configuration.tickets.errorHours))h",
            "Updated: \(formatter.string(from: snapshot.updatedAt))",
        ]

        if configuration.watch {
            lines.append("Watch: refreshing every \(formatDuration(configuration.intervalSeconds)); press R to refresh now.")
        }

        return lines.joined(separator: "\n") + "\n\n"
    }

    private func renderErrors(_ errors: [String]) -> String {
        guard !errors.isEmpty else {
            return ""
        }

        let lines = ["Errors:"] + errors.map { "  - \($0)" }
        return colorize(lines.joined(separator: "\n") + "\n\n", severity: .error)
    }

    private func renderReports(
        _ reports: [TicketReport],
        extraFields: [JiraField],
        status: RefreshStatus,
        updatedAt: Date,
    ) -> String {
        let rows = reports.map { report -> [String] in
            let issueURL = configuration.location.baseURL.appendingPathComponent("browse/\(report.issue.key)").absoluteString
            return [
                report.severity.label,
                report.issue.key,
                report.issue.fields.status.name,
                report.issue.fields.assignee?.displayName ?? "-",
            ] + extraFields.map { field in
                report.issue.fields.extraFields[field.id]?.displayValue ?? "-"
            } + [
                formatCommentAge(report.latestCurrentUserCommentDate, report: report, now: updatedAt),
                formatCommentAge(report.latestAssigneeCommentDate, report: report, now: updatedAt),
                formatCommentAge(report.latestCommentDate, report: report, now: updatedAt),
                formatCommentAge(report.latestReplyDate, report: report, now: updatedAt, missing: "none"),
                report.issue.fields.summary,
                issueURL,
                report.error ?? "",
            ]
        }

        let headers = [
            "Level",
            "Key",
            "Status",
            "Assignee",
        ] + extraFields.map(\.name) + [
            "Your top-level comment",
            "Assignee top-level comment",
            "Latest top-level comment",
            "Latest reply comment",
            "Title",
            "Link",
            "Error",
        ]
        let widths = columnWidths(
            headers: headers,
            rows: rows,
            extraFieldCount: extraFields.count,
        )
        var lines = [
            formattedRow(headers, widths: widths),
            formattedRow(widths.map { String(repeating: "-", count: $0) }, widths: widths),
        ]

        for (report, row) in zip(reports, rows) {
            lines.append(formattedReportRow(
                row,
                widths: widths,
                report: report,
                extraFieldCount: extraFields.count,
            ))
        }

        if reports.isEmpty {
            lines.append(emptyMessage(for: status))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func emptyMessage(for status: RefreshStatus) -> String {
        switch status {
        case .queryingFilter:
            "Querying filter..."
        case .checkingComments:
            "Filter loaded; checking comments..."
        case .complete:
            "No tickets matched the filter."
        case .failed:
            "No ticket data available."
        }
    }

    private func columnWidths(
        headers: [String],
        rows: [[String]],
        extraFieldCount: Int,
    ) -> [Int] {
        let maximums = (0..<headers.count).map { index -> Int in
            ([headers[index]] + rows.map { $0[index] }).map(\.count).max() ?? 0
        }

        return maximums.enumerated().map { index, width in
            if headers[index] == "Title" {
                return min(max(width, 20), 80)
            }
            if headers[index] == "Assignee" || (4..<(4 + extraFieldCount)).contains(index) {
                return min(max(width, 10), 28)
            }
            if headers[index] == "Error" {
                return min(width, 80)
            }
            return min(width, 120)
        }
    }

    private func formattedRow(_ values: [String], widths: [Int]) -> String {
        zip(values, widths)
            .map { paddedCell(value: $0.0, width: $0.1) }
            .joined(separator: "  ")
    }

    private func formattedReportRow(
        _ values: [String],
        widths: [Int],
        report: TicketReport,
        extraFieldCount: Int,
    ) -> String {
        let currentUserColumnIndex = 4 + extraFieldCount
        let assigneeColumnIndex = currentUserColumnIndex + 1
        let anyUserColumnIndex = currentUserColumnIndex + 2
        let errorColumnIndex = values.count - 1
        let highlightedColumnIndexes = [
            HighlightedCommentSource.currentUser: currentUserColumnIndex,
            HighlightedCommentSource.assignee: assigneeColumnIndex,
            HighlightedCommentSource.anyUser: anyUserColumnIndex,
        ]

        let row = zip(values, widths).enumerated()
            .map { index, pair in
                let cell = paddedCell(value: pair.0, width: pair.1)
                if !report.isDeemphasized,
                   let highlightedSource = highlightedColumnIndexes.first(where: { $0.value == index })?.key,
                   let severity = report.highlightSeverities[highlightedSource] {
                    return colorize(cell, severity: severity)
                }
                if index == errorColumnIndex && report.error != nil {
                    return colorize(cell, severity: .error)
                }
                return cell
            }
            .joined(separator: "  ")

        return report.isDeemphasized ? dim(row) : row
    }

    private func paddedCell(value: String, width: Int) -> String {
        let clipped = value.count > width ? String(value.prefix(max(0, width - 1))) + "…" : value
        return clipped.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private func colorize(_ text: String, severity: Severity) -> String {
        guard !configuration.noColor else {
            return text
        }

        switch severity {
        case .error:
            return "\u{001B}[31m\(text)\u{001B}[0m"
        case .warning:
            return "\u{001B}[33m\(text)\u{001B}[0m"
        case .ok:
            return "\u{001B}[32m\(text)\u{001B}[0m"
        case .neutral:
            return text
        }
    }

    private func dim(_ text: String) -> String {
        guard !configuration.noColor else {
            return text
        }

        return "\u{001B}[2m\(text)\u{001B}[0m"
    }

    private func formatCommentAge(
        _ date: Date?,
        report: TicketReport,
        now: Date,
        missing: String = "never",
    ) -> String {
        if report.areCommentsLoading {
            return "loading"
        }

        return formatAge(date, now: now, missing: missing)
    }

    private func statusText(
        _ status: RefreshStatus,
        updatedAt: Date,
    ) -> String {
        switch status {
        case .queryingFilter:
            "\(spinnerFrame(updatedAt)) querying filter"
        case .checkingComments(let completed, let total):
            "\(spinnerFrame(updatedAt)) checking comments \(completed)/\(total)"
        case .complete:
            "complete"
        case .failed:
            "failed"
        }
    }

    private func spinnerFrame(_ date: Date) -> String {
        let frames = ["-", "\\", "|", "/"]
        let index = Int(date.timeIntervalSince1970 * 10) % frames.count
        return frames[index]
    }
}

func writeToStandardOutput(_ output: String) {
    let bytes = Array(output.utf8)
    bytes.withUnsafeBytes { buffer in
        guard let baseAddress = buffer.baseAddress else {
            return
        }

        var written = 0
        while written < buffer.count {
            let result = write(STDOUT_FILENO, baseAddress.advanced(by: written), buffer.count - written)
            if result > 0 {
                written += result
            } else if errno == EINTR {
                continue
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                usleep(10_000)
            } else {
                break
            }
        }
    }
    fflush(stdout)
}
