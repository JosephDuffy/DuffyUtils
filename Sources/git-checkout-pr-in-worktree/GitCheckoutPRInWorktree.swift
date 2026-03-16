import ArgumentParser
import DuffyUtilsInternals
import Foundation
import Subprocess

@main
struct GitCheckoutPRInWorktree: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "git-checkout-pr-in-worktree",
            abstract: "Create or open a worktree for a GitHub pull request.",
            discussion: """
            Fetches a GitHub pull request and creates a new worktree for it, or opens an existing worktree if one already exists.
            
            This command uses the 'gh' CLI to query pull request information and then creates a worktree based on the PR's branch.
            
            The worktree prefix can be configured via 'duffyutils.pr-worktree-prefix' git config value, which takes precedence over
            'duffyutils.worktree-prefix'. If neither is set, it defaults to the directory name of the main repo.
            
            Example: git config set duffyutils.pr-worktree-prefix myproject-pr
            
            By default it is assumed that branches include a prefix, such as 'feature/' or 'bugfix/', which are stripped from the name 
            of the worktree. The goal here is to reduce the otherwise lengthy folder names.
            """
        )
    }

    @Argument(help: "The pull request number to create a worktree for.")
    public var prNumber: Int

    @Option(help: "Specify the app to open the worktree in. Omit or pass an empty string to disable opening. Falls back to 'duffyutils.open-new-worktrees-with' if not provided.")
    public var openIn: String?

    @Option(help: "The prefix to use for the worktree. Reads from 'duffyutils.pr-worktree-prefix', then 'duffyutils.worktree-prefix' if not specified.")
    public var repoPrefix: String?

    @Flag(
        inversion: .prefixedNo,
        help: "If set, the name of the worktree will not include anything before the first `/` from the branch name."
    )
    public var stripBranchPrefix: Bool = true

    @Flag
    public var verbose = false

    @GitConfigValue(name: "duffyutils.pr-worktree-prefix")
    private var prWorktreePrefix: String?

    @GitConfigValue(name: "duffyutils.worktree-prefix")
    private var worktreePrefix: String?

    @GitConfigValue(name: "duffyutils.open-new-worktrees-with")
    private var openInGitConfig: String?

    public func run() async throws {
        // Query the PR information using gh CLI
        let prInfoResult = try await Subprocess.run(
            .name("gh"),
            arguments: [
                "pr", "view", String(prNumber),
                "--json", "headRefName,headRepository,headRepositoryOwner",
            ],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard prInfoResult.terminationStatus.isSuccess, let prInfoJSON = prInfoResult.standardOutput else {
            if let output = prInfoResult.standardOutput {
                print(output)
            }
            if let standardError = prInfoResult.standardError {
                printError(standardError)
            }
            printError("Failed to get PR information for PR #\(prNumber)")
            throw ExitCode(1)
        }

        if verbose {
            printError("PR info JSON: \(prInfoJSON)")
        }

        // Parse the JSON to get the branch name
        guard
            let jsonData = prInfoJSON.data(using: .utf8),
            let prInfo = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
            let branchName = prInfo["headRefName"] as? String
        else {
            printError("Failed to parse PR branch name from: \(prInfoJSON)")
            throw ExitCode(1)
        }

        if verbose {
            printError("PR branch name: \(branchName)")
        }

        // Determine the prefix
        let prefix: String

        if let repoPrefix {
            prefix = repoPrefix
        } else if let prWorktreePrefix = try await prWorktreePrefix {
            prefix = prWorktreePrefix
        } else if let worktreePrefix = try await worktreePrefix {
            prefix = worktreePrefix
        } else {
            if verbose {
                printError("No prefix option provided and no worktree prefix defined in the config; using the name of the folder the git common directory is in.")
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
                printError("Failed to determine root git directory")
                throw ExitCode(1)
            }
            let expectedSuffix = "/.git\n"
            if !output.hasSuffix(expectedSuffix) {
                printError("Root git directory does not have expected '\(expectedSuffix)' suffix: '\(output)'")
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

        let worktreeName = "\(prefix)pr-\(prNumber)-\(worktreeSuffix)"

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

        // Check if worktree already exists
        let listWorktreesResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "worktree", "list",
                "--porcelain",
            ],
            output: .string(limit: 65536),
            error: .string(limit: 4096)
        )

        guard listWorktreesResult.terminationStatus.isSuccess, let worktreeList = listWorktreesResult.standardOutput else {
            if let standardError = listWorktreesResult.standardError {
                printError(standardError)
            }
            printError("Failed to list existing worktrees")
            throw ExitCode(1)
        }

        let worktreeExists = worktreeList.contains(repoPath.path())

        if worktreeExists {
            printError("Worktree already exists at \"\(repoPath.path())\"")
        } else {
            let localBranchName = "pr/\(prNumber)/\(worktreeSuffix)"
            let remotePRRef = "refs/remotes/origin/pr/\(prNumber)"

            // Fetch the PR head without changing the current worktree state.
            printError("Fetching PR #\(prNumber)...")
            let fetchResult = try await Subprocess.run(
                .name("git"),
                arguments: [
                    "fetch", "origin",
                    "+refs/pull/\(prNumber)/head:\(remotePRRef)",
                ],
                output: .standardOutput,
                error: .standardError
            )

            guard fetchResult.terminationStatus.isSuccess else {
                printError("Failed to fetch PR #\(prNumber)")
                throw ExitCode(1)
            }

            // Determine whether the local PR branch already exists.
            let branchExistsResult = try await Subprocess.run(
                .name("git"),
                arguments: [
                    "show-ref",
                    "--verify",
                    "--quiet",
                    "refs/heads/\(localBranchName)",
                ],
                output: .standardOutput,
                error: .string(limit: 4096)
            )

            let localBranchExists = branchExistsResult.terminationStatus.isSuccess

            // Create the worktree
            printError("Creating new worktree at \"\(repoPath.path())\" for PR #\(prNumber) (\(branchName)) on branch \"\(localBranchName)\"")

            let createWorktreeArguments: [String]
            if localBranchExists {
                createWorktreeArguments = [
                    "worktree", "add",
                    repoPath.path(),
                    localBranchName,
                ]
            } else {
                createWorktreeArguments = [
                    "worktree", "add",
                    "-b", localBranchName,
                    repoPath.path(),
                    remotePRRef,
                ]
            }

            let createWorktreeResult = try await Subprocess.run(
                .name("git"),
                arguments: Arguments(createWorktreeArguments),
                output: .standardOutput,
                error: .standardError
            )

            guard createWorktreeResult.terminationStatus.isSuccess else {
                printError("Failed to create worktree")
                throw ExitCode(1)
            }
        }

        // Open the worktree if requested
        let openIn: String?
        if let openInOption = self.openIn {
            openIn = openInOption
        } else {
            openIn = try await openInGitConfig
        }

        if let openIn, !openIn.isEmpty {
            if verbose {
                printError("Opening worktree in \(openIn)")
            }

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

        print("Worktree ready at \(repoPath.path())")
    }
}
