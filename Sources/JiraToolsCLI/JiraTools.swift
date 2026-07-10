import ArgumentParser

@main
struct JiraTools: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "jira-tools",
            abstract: "Tools for interacting with Jira.",
            subcommands: [StaleTicketsCommand.self],
        )
    }
}
