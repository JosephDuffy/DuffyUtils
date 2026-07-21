import Foundation

private let jiraDateFormatters: [DateFormatter] = {
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

public func parseJiraDate(_ rawDate: String) -> Date? {
    for formatter in jiraDateFormatters {
        if let date = formatter.date(from: rawDate) {
            return date
        }
    }
    return nil
}
