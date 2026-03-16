import ArgumentParser
import DuffyUtilsInternals
import Foundation
import RegexBuilder
import Subprocess

@main
struct OpenInJiraAsyncParsableCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "open-in-jira",
            abstract: "Open the Jira ticket for the current git branch.",
            discussion: """
            Parses the current git branch name to extract a Jira ticket ID and opens it in your browser.

            The branch name should contain a Jira ticket ID in the format 'ABC-123' where 'ABC' is the project key
            and '123' is the ticket number. The ticket ID can appear anywhere in the branch name, such as:
            - feature/ABC-123_feature-name
            - bugfix/ABC-123-some-description
            - ABC-123

            The Jira domain is configured via the 'duffyutils.jira-domain' git config value or the --jira-domain option.
            Example: git config set --worktree duffyutils.jira-domain company.atlassian.net
            """
        )
    }

    @Option(help: "The Jira domain to use (e.g., 'company.atlassian.net'). Falls back to 'duffyutils.jira-domain' git config value if not provided.")
    public var jiraDomain: String?

    @Flag(help: "Print the Jira URL without opening it in the browser.")
    public var parseOnly = false

    @Flag
    public var verbose = false

    @GitConfigValue(name: "duffyutils.jira-domain")
    private var jiraDomainConfig: String?

    public func run() async throws {
        // Get the current branch name
        let branchResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "branch",
                "--show-current",
            ],
            output: .string(limit: 4096),
            error: .standardError,
        )

        guard branchResult.terminationStatus.isSuccess, let branchName = branchResult.standardOutput else {
            if let output = branchResult.standardOutput {
                print(output)
            }
            printError("Failed to get current branch name")
            throw ExitCode(1)
        }

        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)

        if verbose {
            printError("Current branch: \(trimmedBranchName)")
        }

        // Parse the Jira ticket ID from the branch name
        guard let ticketId = extractJiraTicketId(from: trimmedBranchName) else {
            printError("Could not find a Jira ticket ID in branch name: \(trimmedBranchName)")
            printError("Expected format: <prefix>/<PROJECT>-<number><separator><description>")
            printError("Examples: feature/ABC-123_feature-name, bugfix/PROJ-456-fix-bug")
            throw ExitCode(1)
        }

        if verbose {
            printError("Found Jira ticket ID: \(ticketId)")
        }

        // Get the Jira domain
        let domain: String
        if let jiraDomain {
            domain = jiraDomain
        } else if let jiraDomainConfig = try await jiraDomainConfig {
            domain = jiraDomainConfig
        } else {
            printError("No Jira domain specified. Please provide --jira-domain or set 'duffyutils.jira-domain' in git config.")
            printError("Example: git config set duffyutils.jira-domain company.atlassian.net")
            throw ExitCode(1)
        }

        // Construct the Jira URL
        let jiraUrl = "https://\(domain)/browse/\(ticketId)"

        if parseOnly {
            print(jiraUrl)
            return
        }

        if verbose {
            printError("Opening: \(jiraUrl)")
        }

        // Open the URL in the default browser
        let openResult = try await Subprocess.run(
            .name("open"),
            arguments: [jiraUrl],
            output: .standardOutput,
            error: .standardError
        )

        guard openResult.terminationStatus.isSuccess else {
            printError("Failed to open URL: \(jiraUrl)")
            throw ExitCode(1)
        }

        print("Opened \(ticketId) in Jira")
    }

    /// Extracts a Jira ticket ID from a branch name.
    /// Looks for a pattern like "ABC-123" where ABC is the project key (letters, possibly with numbers)
    /// and 123 is the ticket number (digits).
    private func extractJiraTicketId(from branchName: String) -> String? {
        // Pattern: one or more uppercase letters, optionally followed by uppercase letters or digits,
        // then a hyphen, then one or more digits
        let pattern = Regex {
            OneOrMore(CharacterClass.generalCategory(.uppercaseLetter))
            ZeroOrMore(CharacterClass.generalCategory(.uppercaseLetter).union(.digit))
            "-"
            OneOrMore(.digit)
        }

        guard let match = branchName.firstMatch(of: pattern) else {
            return nil
        }

        return String(match.0)
    }
}
