import JiraToolsCore
import SwiftUI

struct JiraCredentialsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var coordinator: JiraToolsAppCoordinator
    @State private var email = ""
    @State private var siteURL = ""
    @State private var token = ""
    @State private var statusMessage: String?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("API token") {
                TextField("Jira site URL", text: $siteURL, prompt: Text("example.atlassian.net"))
                    .onSubmit {
                        _ = normalizedSiteURL()
                    }
                TextField("Email", text: $email)
                SecureField("API token", text: $token)
            }

            Section {
                if let statusMessage {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Button("Test Connection") {
                        testConnection()
                    }
                    .disabled(isTesting || !canSubmit)

                    Spacer()

                    if coordinator.hasCredentials {
                        Button("Remove Credentials", role: .destructive) {
                            removeCredentials()
                        }
                    }

                    Button("Save") {
                        saveCredentials()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 440, minHeight: 280)
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !siteURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !token.isEmpty
    }

    private func testConnection() {
        guard let url = normalizedSiteURL() else {
            statusMessage = "Enter a Jira site such as example.atlassian.net. HTTPS is added automatically."
            return
        }

        isTesting = true
        statusMessage = nil
        Task {
            do {
                let user = try await coordinator.verifyCredentials(
                    siteURL: url,
                    email: email,
                    token: token,
                )
                statusMessage = "Connected as \(user.displayName ?? user.accountId)."
            } catch {
                statusMessage = error.localizedDescription
            }
            isTesting = false
        }
    }

    private func saveCredentials() {
        guard let url = normalizedSiteURL() else {
            statusMessage = "Enter a Jira site such as example.atlassian.net. HTTPS is added automatically."
            return
        }

        do {
            try coordinator.saveCredentials(siteURL: url, email: email, token: token)
            token = ""
            dismiss()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func removeCredentials() {
        do {
            try coordinator.removeCredentials()
            email = ""
            siteURL = ""
            token = ""
            statusMessage = "Credentials removed."
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func normalizedSiteURL() -> URL? {
        guard let url = jiraURL(from: siteURL) else {
            return nil
        }

        siteURL = url.absoluteString
        return url
    }
}
