import DuffyUtilsFoundation
import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

public struct GitConfigValueMacro: AccessorMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingAccessorsOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AccessorDeclSyntax] {
        var name: String?
        var location: GitConfigValueLocation = .default

        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                switch argument.label?.trimmed.text {
                case "name":
                    guard let expression = argument.expression.as(StringLiteralExprSyntax.self) else {
                        continue
                    }
                    name = expression.representedLiteralValue
                default:
                    break
                }
            }
        }

        guard let name else {
            throw HashableMacroDiagnosticMessage(
                id: "missing-parameter-name",
                message: "The name parameter was not provided",
                severity: .error
            )
        }

        return [
            AccessorDeclSyntax(
                accessorSpecifier: .keyword(.get),
                effectSpecifiers: AccessorEffectSpecifiersSyntax(
                    asyncSpecifier: .keyword(.async),
                    throwsSpecifier: .keyword(.throws)
                ),
                bodyBuilder: {
                    """
                    try await GitConfigValue.getValue(name: "\(raw: name)", location: .\(raw: location))
                    """
                }
            )
        ]
    }
}
