import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct DuffyUtilMacros: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        GitConfigValueMacro.self,
    ]
}
