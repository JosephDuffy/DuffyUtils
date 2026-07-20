import JiraToolsCore

struct StaleTicketsCommentThreadNode: Identifiable {
    let id: String
    let comment: JiraComment
    let replies: [StaleTicketsCommentThreadNode]
}

enum StaleTicketsCommentThread {
    static func make(from comments: [JiraComment]) -> [StaleTicketsCommentThreadNode] {
        let entries = comments.enumerated().map { index, comment in
            Entry(index: index, comment: comment)
        }
        let firstIndexByID = entries.reduce(into: [String: Int]()) { indexes, entry in
            indexes[entry.comment.id] = indexes[entry.comment.id] ?? entry.index
        }

        var parentIndexByIndex = [Int: Int]()
        for entry in entries {
            guard let parentID = entry.comment.parentId,
                  let parentIndex = firstIndexByID[parentID],
                  parentIndex != entry.index else {
                continue
            }

            parentIndexByIndex[entry.index] = parentIndex
        }

        for entry in entries where containsCycle(startingAt: entry.index, parents: parentIndexByIndex) {
            parentIndexByIndex[entry.index] = nil
        }

        var replyIndexesByParent = [Int: [Int]]()
        for (replyIndex, parentIndex) in parentIndexByIndex {
            replyIndexesByParent[parentIndex, default: []].append(replyIndex)
        }

        let rootIndexes = entries
            .map(\.index)
            .filter { parentIndexByIndex[$0] == nil }
        let sortedRootIndexes = sorted(rootIndexes, using: entries)

        func node(for index: Int) -> StaleTicketsCommentThreadNode {
            let replyIndexes = sorted(replyIndexesByParent[index] ?? [], using: entries)
            return StaleTicketsCommentThreadNode(
                id: "\(entries[index].comment.id)-\(index)",
                comment: entries[index].comment,
                replies: replyIndexes.map(node(for:)),
            )
        }

        return sortedRootIndexes.map(node(for:))
    }

    private static func containsCycle(
        startingAt index: Int,
        parents: [Int: Int],
    ) -> Bool {
        var visited = Set<Int>()
        var currentIndex: Int? = index

        while let index = currentIndex {
            guard visited.insert(index).inserted else {
                return true
            }

            currentIndex = parents[index]
        }

        return false
    }

    private static func sorted(
        _ indexes: [Int],
        using entries: [Entry],
    ) -> [Int] {
        indexes.sorted { lhs, rhs in
            let lhsDate = parseJiraDate(entries[lhs].comment.created)
            let rhsDate = parseJiraDate(entries[rhs].comment.created)

            switch (lhsDate, rhsDate) {
            case let (lhsDate?, rhsDate?):
                if lhsDate != rhsDate {
                    return lhsDate < rhsDate
                }
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                break
            }

            return lhs < rhs
        }
    }

    private struct Entry {
        let index: Int
        let comment: JiraComment
    }
}
