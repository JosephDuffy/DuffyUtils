import Foundation

package enum Severity: String, CaseIterable, Comparable, Sendable {
    case error
    case warning
    case ok
    case neutral

    package static func < (lhs: Severity, rhs: Severity) -> Bool {
        return lhs.priority < rhs.priority
    }

    package var label: String {
        switch self {
        case .error:
            "ERROR"
        case .warning:
            "WARN"
        case .ok:
            "OK"
        case .neutral:
            "INFO"
        }
    }

    private var priority: Int {
        switch self {
        case .error: 0
        case .warning: 1
        case .neutral: 2
        case .ok: 3
        }
    }
}

package struct JiraCredentials: Sendable {
    package let email: String
    package let token: String

    package static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> JiraCredentials {
        guard let email = environment["JIRA_EMAIL"], !email.isEmpty else {
            throw AppError("Missing JIRA_EMAIL environment variable")
        }

        if let token = environment["JIRA_API_TOKEN"], !token.isEmpty {
            return JiraCredentials(email: email, token: token)
        }

        throw AppError("Missing JIRA_API_TOKEN environment variable. An API key can be created at https://id.atlassian.com/manage-profile/security/api-tokens.")
    }
}

package struct JiraUser: Decodable, Sendable {
    package let accountId: String
    package let displayName: String?
}

package struct SearchResponse: Decodable, Sendable {
    package let issues: [JiraIssue]
    package let isLast: Bool?
    package let nextPageToken: String?
}

package struct JiraIssue: Decodable, Sendable {
    package let id: String
    package let key: String
    package let fields: IssueFields
}

package struct IssueFields: Decodable, Sendable {
    package let summary: String
    package let status: JiraStatus
    package let assignee: JiraUser?
    package let extraFields: [String: JiraFieldValue]

    enum CodingKeys: String, CodingKey {
        case summary
        case status
        case assignee
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        status = try container.decode(JiraStatus.self, forKey: .status)
        assignee = try container.decodeIfPresent(JiraUser.self, forKey: .assignee)

        let dynamicContainer = try decoder.container(keyedBy: DynamicCodingKey.self)
        let extraFieldIDs = decoder.userInfo[.extraFieldIDs] as? [String] ?? []
        extraFields = try Dictionary(
            uniqueKeysWithValues: extraFieldIDs.compactMap { fieldID in
                guard let key = DynamicCodingKey(stringValue: fieldID),
                      let value = try dynamicContainer.decodeIfPresent(JiraFieldValue.self, forKey: key) else {
                    return nil
                }

                return (fieldID, value)
            },
        )
    }
}

package struct JiraStatus: Decodable, Sendable {
    package let name: String
}

package struct JiraField: Decodable, Sendable {
    package let id: String
    package let name: String
}

package struct CommentsResponse: Decodable, Sendable {
    package let comments: [JiraComment]
    package let startAt: Int?
    package let maxResults: Int?
    package let total: Int?
    package let isLast: Bool?
}

package struct JiraComment: Decodable, Sendable {
    package let id: String
    package let author: JiraUser
    package let created: String
    package let updated: String?
    package let parentId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case created
        case updated
        case parentId
        case parentID
        case parent
        case parentCommentId
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(JiraUser.self, forKey: .author)
        created = try container.decode(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)

        if let parentId = try decodeStringOrNumberIfPresent(container, forKey: .parentId) {
            self.parentId = parentId
        } else if let parentId = try decodeStringOrNumberIfPresent(container, forKey: .parentID) {
            self.parentId = parentId
        } else if let parentId = try decodeStringOrNumberIfPresent(container, forKey: .parentCommentId) {
            self.parentId = parentId
        } else if let parent = try container.decodeIfPresent(JiraFieldValue.self, forKey: .parent) {
            self.parentId = parent.idValue
        } else {
            self.parentId = nil
        }
    }

    package var isReply: Bool {
        parentId != nil
    }
}

package struct DynamicCodingKey: CodingKey {
    package let stringValue: String
    package let intValue: Int?

    package init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    package init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

package enum JiraFieldValue: Decodable, Sendable {
    case string(String)
    case user(JiraUser)
    case array([JiraFieldValue])
    case object([String: JiraFieldValue])
    case number(Double)
    case bool(Bool)
    case null

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let user = try? container.decode(JiraUser.self) {
            self = .user(user)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JiraFieldValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JiraFieldValue].self) {
            self = .object(object)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else {
            self = .null
        }
    }

    package var displayValue: String {
        switch self {
        case .string(let value):
            value
        case .user(let user):
            user.displayName ?? user.accountId
        case .array(let values):
            values
                .map(\.displayValue)
                .filter { !$0.isEmpty && $0 != "-" }
                .joined(separator: ", ")
        case .object(let object):
            object.displayValue
        case .number(let value):
            String(format: "%.0f", value)
        case .bool(let value):
            value ? "true" : "false"
        case .null:
            "-"
        }
    }

    package var idValue: String? {
        switch self {
        case .string(let value):
            value
        case .number(let value):
            String(format: "%.0f", value)
        case .object(let object):
            object.idValue
        default:
            nil
        }
    }
}

extension CodingUserInfoKey {
    static var extraFieldIDs: CodingUserInfoKey {
        guard let key = CodingUserInfoKey(rawValue: "extraFieldIDs") else {
            preconditionFailure("Unable to create CodingUserInfoKey.extraFieldIDs")
        }

        return key
    }
}

extension [String: JiraFieldValue] {
    fileprivate var displayValue: String {
        if case .string(let value)? = self["displayName"] {
            return value
        }
        if case .string(let value)? = self["value"] {
            return value
        }
        if case .string(let value)? = self["name"] {
            return value
        }
        if case .string(let value)? = self["accountId"] {
            return value
        }
        return "-"
    }

    fileprivate var idValue: String? {
        if case .string(let value)? = self["id"] {
            return value
        }
        if case .number(let value)? = self["id"] {
            return String(format: "%.0f", value)
        }
        return nil
    }
}

package func decodeStringOrNumberIfPresent<K: CodingKey>(
    _ container: KeyedDecodingContainer<K>,
    forKey key: K,
) throws -> String? {
    if let value = try? container.decodeIfPresent(String.self, forKey: key) {
        return value
    }

    if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
        return String(value)
    }

    if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
        return String(format: "%.0f", value)
    }

    return nil
}
