import JiraToolsCore
import SwiftUI

struct StaleTicketsCommentBodyView: View {
    let commentBody: JiraCommentBody

    var body: some View {
        blocks(commentBody.content)
            .textSelection(.enabled)
    }

    private func blocks(_ nodes: [JiraCommentBodyNode]) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(nodes.indices), id: \.self) { index in
                    block(nodes[index])
                }
            },
        )
    }

    private func block(_ node: JiraCommentBodyNode) -> AnyView {
        switch node.type {
        case "paragraph":
            AnyView(Text(inlineText(node.content)))
        case "heading":
            AnyView(
                Text(inlineText(node.content))
                    .font(.headline),
            )
        case "bulletList":
            list(node.content, marker: { _ in "•" })
        case "orderedList":
            list(node.content, marker: { "\($0 + 1)." })
        case "listItem":
            blocks(node.content)
        case "blockquote":
            AnyView(
                HStack(alignment: .top, spacing: 8) {
                    Rectangle()
                        .fill(.secondary)
                        .frame(width: 3)
                    blocks(node.content)
                },
            )
        case "codeBlock":
            AnyView(
                Text(verbatim: plainText(in: node.content))
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4)),
            )
        case "rule":
            AnyView(Divider())
        default:
            if node.content.contains(where: isBlockNode) {
                blocks(node.content)
            } else {
                AnyView(Text(inlineText([node])))
            }
        }
    }

    private func list(
        _ items: [JiraCommentBodyNode],
        marker: @escaping (Int) -> String,
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.indices), id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Text(marker(index))
                            .frame(minWidth: 16, alignment: .trailing)
                        blocks(items[index].content)
                    }
                }
            },
        )
    }

    private func inlineText(_ nodes: [JiraCommentBodyNode]) -> AttributedString {
        nodes.reduce(into: AttributedString()) { result, node in
            result += attributedText(for: node)
        }
    }

    private func attributedText(for node: JiraCommentBodyNode) -> AttributedString {
        switch node.type {
        case "hardBreak":
            return AttributedString("\n")
        case "text", "mention", "emoji":
            return markedText(
                node.text
                    ?? node.attributes["text"]?.stringValue
                    ?? node.attributes["shortName"]?.stringValue
                    ?? "",
                marks: node.marks,
            )
        default:
            var result = markedText(node.text ?? "", marks: node.marks)
            result += inlineText(node.content)
            return result
        }
    }

    private func markedText(
        _ value: String,
        marks: [JiraCommentBodyMark],
    ) -> AttributedString {
        var result = AttributedString(value)
        var presentationIntent: InlinePresentationIntent = []

        for mark in marks {
            switch mark.type {
            case "strong":
                presentationIntent.insert(.stronglyEmphasized)
            case "em":
                presentationIntent.insert(.emphasized)
            case "code":
                presentationIntent.insert(.code)
            case "link":
                if let href = mark.attributes["href"]?.stringValue,
                   let url = URL(string: href) {
                    result.link = url
                }
            default:
                break
            }
        }

        result.inlinePresentationIntent = presentationIntent

        return result
    }

    private func plainText(in nodes: [JiraCommentBodyNode]) -> String {
        nodes.map { node in
            let text = node.text
                ?? node.attributes["text"]?.stringValue
                ?? node.attributes["shortName"]?.stringValue
                ?? ""
            return text + plainText(in: node.content)
        }
        .joined()
    }

    private func isBlockNode(_ node: JiraCommentBodyNode) -> Bool {
        switch node.type {
        case "paragraph", "heading", "bulletList", "orderedList", "listItem", "blockquote", "codeBlock", "rule":
            true
        default:
            false
        }
    }
}

private extension JiraCommentBodyValue {
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }
}
