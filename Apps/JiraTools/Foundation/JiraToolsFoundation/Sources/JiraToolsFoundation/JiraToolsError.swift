import Foundation

public struct JiraToolsError: CustomStringConvertible, Error, LocalizedError, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? {
        description
    }
}
