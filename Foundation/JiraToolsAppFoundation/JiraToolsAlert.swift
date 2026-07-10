import Foundation

public struct JiraToolsAlert: Equatable, Sendable {
    public let body: String
    public let title: String

    public init(
        title: String,
        body: String,
    ) {
        self.title = title
        self.body = body
    }
}

public enum JiraToolsAlertMode: String, CaseIterable, Codable, Sendable {
    case notification
    case sound
    case both
    case none
}
