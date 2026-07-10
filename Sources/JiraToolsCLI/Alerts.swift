import ArgumentParser
import Foundation
import JiraToolsCore
import JiraToolsStaleTickets

enum AlertMode: String, ExpressibleByArgument, Sendable {
    case notification
    case sound
    case both
    case none
}

func sendAlert(for reports: [StaleTicketsReport], mode: AlertMode) {
    guard mode != .none else {
        return
    }

    let worst = reports.map(\.severity).min() ?? .warning
    let keys = reports.map(\.issue.key).joined(separator: ", ")
    let title = "Jira tickets need attention"
    let message = "\(reports.count) ticket(s): \(keys) (\(worst.label))"

    if mode == .notification || mode == .both {
        runProcess("/usr/bin/osascript", arguments: [
            "-e",
            "display notification \(appleScriptLiteral(message)) with title \(appleScriptLiteral(title))",
        ])
    }

    if mode == .sound || mode == .both {
        runProcess("/usr/bin/afplay", arguments: ["/System/Library/Sounds/Glass.aiff"])
    }
}

func runProcess(_ executable: String, arguments: [String]) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    try? process.run()
}

func appleScriptLiteral(_ value: String) -> String {
    "\"" + value
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        + "\""
}
