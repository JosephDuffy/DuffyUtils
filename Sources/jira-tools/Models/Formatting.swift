import Foundation

let jiraDateFormatters: [DateFormatter] = {
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
        "yyyy-MM-dd'T'HH:mm:ssZ",
    ]

    return formats.map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter
    }
}()

func parseJiraDate(_ rawDate: String) -> Date? {
    for formatter in jiraDateFormatters {
        if let date = formatter.date(from: rawDate) {
            return date
        }
    }
    return nil
}

func formatAge(
    _ date: Date?,
    now: Date = Date(),
    missing: String = "never",
) -> String {
    guard let date else {
        return missing
    }

    let hours = max(0, now.timeIntervalSince(date) / 3600)
    if hours < 1 {
        return "\(Int(hours * 60))m ago"
    }

    if hours < 48 {
        return "\(String(format: "%.1f", hours))h ago"
    }

    return "\(String(format: "%.1f", hours / 24))d ago"
}

func formatHours(_ hours: TimeInterval) -> String {
    String(format: "%.1f", hours)
}

func formatDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "\(Int(seconds))s"
    }

    let minutes = seconds / 60
    if minutes < 60 {
        return "\(String(format: "%.1f", minutes))m"
    }

    return "\(String(format: "%.1f", seconds / 3600))h"
}
