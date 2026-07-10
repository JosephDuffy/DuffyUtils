import JiraToolsCore
import SwiftUI

@main
struct JiraToolsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        Text("Hello, Jira Tools!")
            .frame(minWidth: 320, minHeight: 180)
    }
}
