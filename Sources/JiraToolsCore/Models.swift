import Foundation

public enum Severity: String, CaseIterable, Codable, Comparable, Sendable {
    case error
    case warning
    case ok
    case neutral

    public static func < (lhs: Severity, rhs: Severity) -> Bool {
        return lhs.priority < rhs.priority
    }

    public var label: String {
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

public enum JiraAuthorization: Sendable {
    case apiToken(email: String, token: String)
    case oauth(accessToken: String)

    var headerValue: String {
        return switch self {
        case .apiToken(let email, let token):
            "Basic " + Data("\(email):\(token)".utf8).base64EncodedString()
        case .oauth(let accessToken):
            "Bearer \(accessToken)"
        }
    }
}

public struct JiraUser: Decodable, Sendable {
    public let accountId: String
    public let displayName: String?
}

public struct SearchResponse: Decodable, Sendable {
    public let issues: [JiraIssue]
    public let isLast: Bool?
    public let nextPageToken: String?
}

public struct JiraIssue: Decodable, Sendable {
    public let id: String
    public let key: String
    public let fields: JiraIssueFields
}

public struct JiraIssueFields: Decodable, Sendable {
    public let summary: String
    public let status: JiraStatus
    public let assignee: JiraUser?
    public let updated: String?
    public let extraFields: [String: JiraFieldValue]

    enum CodingKeys: String, CodingKey {
        case summary
        case status
        case assignee
        case updated
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        status = try container.decode(JiraStatus.self, forKey: .status)
        assignee = try container.decodeIfPresent(JiraUser.self, forKey: .assignee)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)

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

public struct JiraStatus: Decodable, Sendable {
    public let name: String
}

public struct JiraField: Decodable, Sendable {
    public let id: String
    public let name: String

    public init(
        id: String,
        name: String,
    ) {
        self.id = id
        self.name = name
    }
}

public struct CommentsResponse: Decodable, Sendable {
    public let comments: [JiraComment]
    public let startAt: Int?
    public let maxResults: Int?
    public let total: Int?
    public let isLast: Bool?
}

public struct JiraComment: Decodable, Sendable {
    public let id: String
    public let author: JiraUser
    public let created: String
    public let updated: String?
    public let parentId: String?

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

    public init(from decoder: Decoder) throws {
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

    public var isReply: Bool {
        parentId != nil
    }
}

struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}

public enum JiraFieldValue: Decodable, Sendable {
    case string(String)
    case user(JiraUser)
    case array([JiraFieldValue])
    case object([String: JiraFieldValue])
    case number(Double)
    case bool(Bool)
    case null

    public init(from decoder: Decoder) throws {
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

    public var displayValue: String {
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

    public var idValue: String? {
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

func decodeStringOrNumberIfPresent<K: CodingKey>(
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
