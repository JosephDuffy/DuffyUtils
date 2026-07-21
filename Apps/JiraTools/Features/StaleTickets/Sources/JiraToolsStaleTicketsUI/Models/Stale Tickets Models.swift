import Foundation

public enum StaleTicketsTableSortColumn: Hashable, Sendable {
    case severity
    case key
    case status
    case assignee
    case currentUserComment
    case assigneeComment
    case latestComment
    case latestReply
    case summary
    case extraField(String)
    case extraFields
}

public struct StaleTicketsTableComparator: Codable, Hashable, Sendable, SortComparator {
    public var column: StaleTicketsTableSortColumn
    public var order: SortOrder

    public init(
        column: StaleTicketsTableSortColumn,
        order: SortOrder = .forward,
    ) {
        self.column = column
        self.order = order
    }

    public func compare(
        _ lhs: StaleTicketsTableRow,
        _ rhs: StaleTicketsTableRow,
    ) -> ComparisonResult {
        let result = switch column {
        case .severity:
            compare(lhs.severityRank, rhs.severityRank)
        case .key:
            compare(lhs.key, rhs.key)
        case .status:
            compare(lhs.status, rhs.status)
        case .assignee:
            compare(lhs.assignee, rhs.assignee)
        case .currentUserComment:
            compare(lhs.currentUserCommentDate, rhs.currentUserCommentDate)
        case .assigneeComment:
            compare(lhs.assigneeCommentDate, rhs.assigneeCommentDate)
        case .latestComment:
            compare(lhs.latestCommentDate, rhs.latestCommentDate)
        case .latestReply:
            compare(lhs.latestReplyDate, rhs.latestReplyDate)
        case .summary:
            compare(lhs.summary, rhs.summary)
        case .extraField(let fieldID):
            compare(lhs.extraFieldValue(for: fieldID), rhs.extraFieldValue(for: fieldID))
        case .extraFields:
            compare(lhs.extraFieldsDisplay, rhs.extraFieldsDisplay)
        }

        return order == .forward ? result : result.reversed
    }

    private func compare<Value: Comparable>(
        _ lhs: Value,
        _ rhs: Value,
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }
}

extension ComparisonResult {
    fileprivate var reversed: ComparisonResult {
        switch self {
        case .orderedAscending:
            .orderedDescending
        case .orderedDescending:
            .orderedAscending
        case .orderedSame:
            .orderedSame
        }
    }
}

extension StaleTicketsTableSortColumn: Codable {
    private enum CodingKeys: String, CodingKey {
        case fieldID
        case kind
    }

    private enum Kind: String, Codable {
        case severity
        case key
        case status
        case assignee
        case currentUserComment
        case assigneeComment
        case latestComment
        case latestReply
        case summary
        case extraField
        case extraFields
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        self = switch kind {
        case .severity: .severity
        case .key: .key
        case .status: .status
        case .assignee: .assignee
        case .currentUserComment: .currentUserComment
        case .assigneeComment: .assigneeComment
        case .latestComment: .latestComment
        case .latestReply: .latestReply
        case .summary: .summary
        case .extraField:
            .extraField(try container.decode(String.self, forKey: .fieldID))
        case .extraFields: .extraFields
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .severity:
            try container.encode(Kind.severity, forKey: .kind)
        case .key:
            try container.encode(Kind.key, forKey: .kind)
        case .status:
            try container.encode(Kind.status, forKey: .kind)
        case .assignee:
            try container.encode(Kind.assignee, forKey: .kind)
        case .currentUserComment:
            try container.encode(Kind.currentUserComment, forKey: .kind)
        case .assigneeComment:
            try container.encode(Kind.assigneeComment, forKey: .kind)
        case .latestComment:
            try container.encode(Kind.latestComment, forKey: .kind)
        case .latestReply:
            try container.encode(Kind.latestReply, forKey: .kind)
        case .summary:
            try container.encode(Kind.summary, forKey: .kind)
        case .extraField(let fieldID):
            try container.encode(Kind.extraField, forKey: .kind)
            try container.encode(fieldID, forKey: .fieldID)
        case .extraFields:
            try container.encode(Kind.extraFields, forKey: .kind)
        }
    }
}

public struct StaleTicketsTableSort: Codable, Sendable {
    public var comparators: [StaleTicketsTableComparator]

    public init(comparators: [StaleTicketsTableComparator] = [
        StaleTicketsTableComparator(column: .severity),
    ]) {
        self.comparators = comparators
    }

    private enum CodingKeys: String, CodingKey {
        case comparators
        case column
        case isAscending
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let comparators = try container.decodeIfPresent([StaleTicketsTableComparator].self, forKey: .comparators) {
            self.comparators = comparators
            return
        }

        let legacyColumn = try container.decodeIfPresent(String.self, forKey: .column) ?? "severity"
        let isAscending = try container.decodeIfPresent(Bool.self, forKey: .isAscending) ?? true
        self.comparators = [StaleTicketsTableComparator(
            column: StaleTicketsTableSortColumn(legacyValue: legacyColumn),
            order: isAscending ? .forward : .reverse,
        )]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(comparators, forKey: .comparators)
    }
}

private extension StaleTicketsTableSortColumn {
    init(legacyValue: String) {
        self = switch legacyValue {
        case "key": .key
        case "status": .status
        case "assignee": .assignee
        case "currentUserComment": .currentUserComment
        case "assigneeComment": .assigneeComment
        case "latestComment": .latestComment
        case "latestReply": .latestReply
        case "summary": .summary
        default: .severity
        }
    }
}
