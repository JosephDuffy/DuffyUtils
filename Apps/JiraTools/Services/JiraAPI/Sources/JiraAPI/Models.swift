import Foundation

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
    public let body: JiraCommentBody?

    enum CodingKeys: String, CodingKey {
        case id
        case author
        case created
        case updated
        case parentId
        case parentID
        case parent
        case parentCommentId
        case body
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        author = try container.decode(JiraUser.self, forKey: .author)
        created = try container.decode(String.self, forKey: .created)
        updated = try container.decodeIfPresent(String.self, forKey: .updated)
        body = try? container.decodeIfPresent(JiraCommentBody.self, forKey: .body)

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

public struct JiraCommentBody: Decodable, Sendable {
    public let type: String
    public let version: Int?
    public let content: [JiraCommentBodyNode]
    public let attributes: [String: JiraCommentBodyValue]

    private enum CodingKeys: String, CodingKey {
        case type
        case version
        case content
        case attributes = "attrs"
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            type = "unknown"
            version = nil
            content = []
            attributes = [:]
            return
        }

        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        version = try? container.decodeIfPresent(Int.self, forKey: .version)
        content = (try? container.decode([JiraCommentBodyNode].self, forKey: .content)) ?? []
        attributes = (try? container.decode([String: JiraCommentBodyValue].self, forKey: .attributes)) ?? [:]
    }
}

public struct JiraCommentBodyNode: Decodable, Sendable {
    public let type: String
    public let text: String?
    public let attributes: [String: JiraCommentBodyValue]
    public let marks: [JiraCommentBodyMark]
    public let content: [JiraCommentBodyNode]

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case attributes = "attrs"
        case marks
        case content
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            type = "unknown"
            text = nil
            attributes = [:]
            marks = []
            content = []
            return
        }

        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        text = try? container.decodeIfPresent(String.self, forKey: .text)
        attributes = (try? container.decode([String: JiraCommentBodyValue].self, forKey: .attributes)) ?? [:]
        marks = (try? container.decode([JiraCommentBodyMark].self, forKey: .marks)) ?? []
        content = (try? container.decode([JiraCommentBodyNode].self, forKey: .content)) ?? []
    }
}

public struct JiraCommentBodyMark: Decodable, Sendable {
    public let type: String
    public let attributes: [String: JiraCommentBodyValue]

    private enum CodingKeys: String, CodingKey {
        case type
        case attributes = "attrs"
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            type = "unknown"
            attributes = [:]
            return
        }

        type = (try? container.decode(String.self, forKey: .type)) ?? "unknown"
        attributes = (try? container.decode([String: JiraCommentBodyValue].self, forKey: .attributes)) ?? [:]
    }
}

public indirect enum JiraCommentBodyValue: Decodable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JiraCommentBodyValue])
    case object([String: JiraCommentBodyValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JiraCommentBodyValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JiraCommentBodyValue].self) {
            self = .object(object)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else {
            self = .null
        }
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
