import SwiftUI

struct JiraToolsNewToolAction {
    let perform: () -> Void
}

private struct JiraToolsNewToolActionKey: FocusedValueKey {
    typealias Value = JiraToolsNewToolAction
}

extension FocusedValues {
    var jiraToolsNewToolAction: JiraToolsNewToolAction? {
        get {
            self[JiraToolsNewToolActionKey.self]
        }
        set {
            self[JiraToolsNewToolActionKey.self] = newValue
        }
    }
}
