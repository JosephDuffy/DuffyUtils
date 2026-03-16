import ArgumentParser
import DuffyUtilsInternals
import Foundation
import Subprocess

@main
struct GitNewBranchAndWorktreeAsyncParsableCommand: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            abstract: "Create a new branch and worktree.",
            discussion: """
            The location of the worktree, the name of the branch, and the source branch all follow conventions to provide consistency and automate common workflows.
            
            This script aims to be usable from any worktree within a git repo, namely by using git config values to store repo-wide values. Note the order that configuration values are read from: https://git-scm.com/docs/git-config#SCOPES
            
            The most important value to configure is 'duffyutils.worktree-starting-point'. This value determines the starting point for new worktrees. For my use cases I set this to `origin/develop`:
            
            $ git config set duffyutils.worktree-starting-point origin/develop
            
            By default it is assumed that branches include a prefix, such as 'feature/' or 'bugfix/', which are stripped from the name of the worktree. The goal here is to reduce the otherwise lengthy folder names. This stripping can be disabled 
            """,
        )
    }

    @Argument(help: "The name of the branch to create and checkout in the new worktree.")
    public var branchName: String

    @Option(help: "Specify the app to open the new worktree in. Omit or pass an empty string to disable opening. Falls back to 'duffyutils.open-new-worktrees-with' if not provided.")
    public var openIn: String?

    @Option(help: "The prefix to use for the new branch. Reads from the git config `duffyutils.worktree-prefix` if not specified, and defaults to the directory name of the main repo with a `-` appended.")
    public var repoPrefix: String?

    @Option(help: "The source branch to create the new branch from. If not specified falls back to the 'duffyutils.worktree-starting-point' git config value, otherwise the current branch is used.")
    public var sourceBranch: String?

    @Flag(
        inversion: .prefixedNo,
        help: "If set, the name of the worktree will not include anything before the first `/` from the branch name."
    )
    public var stripBranchPrefix: Bool = true

    @Flag
    public var verbose = false

    @GitConfigValue(name: "duffyutils.worktree-prefix")
    private var worktreePrefix: String?

    @GitConfigValue(name: "duffyutils.worktree-starting-point")
    private var worktreeStartingPoint: String?

    @GitConfigValue(name: "duffyutils.open-new-worktrees-with")
    private var openInGitConfig: String?

    public func run() async throws {
        let prefix: String

        if let repoPrefix {
            prefix = repoPrefix
        } else if let repoPrefix = try await worktreePrefix {
            prefix = repoPrefix
        } else {
            if verbose {
                printError("No --repoPrefix option provided and no worktree prefix defined in the config; using the name of the folder the git common directory is in.")
            }

            let result = try await Subprocess.run(
                .name("git"),
                arguments: [
                    "rev-parse",
                    "--path-format=absolute",
                    "--git-common-dir",
                ],
                output: .string(limit: 4096),
                error: .string(limit: 4096)
            )
            guard result.terminationStatus.isSuccess, let output = result.standardOutput else {
                if let output = result.standardOutput {
                    print(output)
                }
                if let standardError = result.standardError {
                    print(standardError)
                }
                print("Failed to determine root git directory")
                throw ExitCode(1)
            }
            let expectedSuffix = "/.git\n"
            if !output.hasSuffix(expectedSuffix) {
                print("Root git directory does not have expected '\(expectedSuffix)' suffix: '\(output)'")
                throw ExitCode(1)
            }
            prefix = String(String(output.dropLast(expectedSuffix.count)).split(separator: "/").last!)
        }

        let worktreeSuffix: String

        if stripBranchPrefix {
            worktreeSuffix = String(branchName.split(separator: "/", maxSplits: 2).last!)
        } else {
            worktreeSuffix = branchName
        }

        let worktreeName = "\(prefix)\(worktreeSuffix)"

        // Get the main worktree path to create new worktrees as siblings
        let mainWorktreeResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "rev-parse",
                "--path-format=absolute",
                "--git-common-dir",
            ],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard mainWorktreeResult.terminationStatus.isSuccess, let gitCommonDir = mainWorktreeResult.standardOutput else {
            if let output = mainWorktreeResult.standardOutput {
                print(output)
            }
            if let standardError = mainWorktreeResult.standardError {
                print(standardError)
            }
            printError("Failed to determine git common directory")
            throw ExitCode(1)
        }

        let trimmedGitCommonDir = gitCommonDir.trimmingCharacters(in: .whitespacesAndNewlines)

        // The git common dir ends with /.git, so the parent is the main worktree
        let mainWorktreeURL = URL(filePath: trimmedGitCommonDir).deletingLastPathComponent()

        // Create the new worktree as a sibling to the main worktree
        let repoPath = mainWorktreeURL.deletingLastPathComponent().appending(path: worktreeName)

        let startingPoint: String?

        if let sourceBranch {
            startingPoint = sourceBranch
        } else if let worktreeStartingPoint = try await worktreeStartingPoint {
            startingPoint = worktreeStartingPoint
        } else {
            startingPoint = nil
        }

        // TODO: Check if branch exists; create accordingly if so

        var arguments = [
            "worktree",
            "add",
            repoPath.path(),
            "-b", branchName,
            "--no-track",
        ]

        var message = "Creating new worktree at “\(repoPath.path())” with branch name “\(branchName)”."

        if let startingPoint {
            arguments.append(startingPoint)

            message += " Starting point will be “\(startingPoint)”."
        }

        printError(message)

        let createWorktreeResult = try await Subprocess.run(
            .name("git"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError
        )

        guard createWorktreeResult.terminationStatus.isSuccess else {
            throw ExitCode(1)
        }

        let openIn: String?
        if let openInOption = self.openIn {
            openIn = openInOption
        } else {
            openIn = try await openInGitConfig
        }
        if let openIn, !openIn.isEmpty {
            _ = try await Subprocess.run(
                .name("open"),
                arguments: [
                    "-a", openIn,
                    repoPath.path()
                ],
                output: .standardOutput,
                error: .standardError
            )
        }
    }
}
