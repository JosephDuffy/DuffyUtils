import ArgumentParser
import DuffyUtilsInternals
import Foundation
import Subprocess

@main
struct GitRemoveCurrentWorktreeAndBranch: AsyncParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "git-remove-current-worktree-and-branch",
            abstract: "Remove the current worktree and its associated branch.",
            discussion: """
            Safely removes the current worktree and deletes its associated branch.
            
            This command performs several safety checks before removal:
            - Ensures you are in a worktree (not the main repository)
            - Checks for uncommitted changes
            - Checks for unpushed commits
            
            Use --force to bypass these checks and remove anyway.
            
            After successful removal, the command prints the path to the main worktree so you can easily switch back.
            """
        )
    }

    @Flag(help: "Force removal even if there are uncommitted or unpushed changes.")
    public var force = false

    @Flag
    public var verbose = false

    public func run() async throws {
        // Get the current worktree path
        let currentPathResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "rev-parse",
                "--path-format=absolute",
                "--git-dir",
            ],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard currentPathResult.terminationStatus.isSuccess, let gitDir = currentPathResult.standardOutput else {
            if let standardError = currentPathResult.standardError {
                printError(standardError)
            }
            printError("Failed to determine current git directory")
            throw ExitCode(1)
        }

        let trimmedGitDir = gitDir.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if we're in a worktree (not the main repo)
        // In a worktree, .git is a file, not a directory, or the path contains .git/worktrees/
        if !trimmedGitDir.contains("/.git/worktrees/") {
            printError("You are in the main repository, not a worktree.")
            printError("This command can only be used from within a worktree.")
            throw ExitCode(1)
        }

        if verbose {
            printError("Git directory: \(trimmedGitDir)")
        }

        // Get the current worktree path
        let worktreePathResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "rev-parse",
                "--show-toplevel",
            ],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard worktreePathResult.terminationStatus.isSuccess, let worktreePath = worktreePathResult.standardOutput else {
            if let standardError = worktreePathResult.standardError {
                printError(standardError)
            }
            printError("Failed to determine worktree path")
            throw ExitCode(1)
        }

        let trimmedWorktreePath = worktreePath.trimmingCharacters(in: .whitespacesAndNewlines)

        if verbose {
            printError("Worktree path: \(trimmedWorktreePath)")
        }

        // Get the current branch name
        let branchResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "branch",
                "--show-current",
            ],
            output: .string(limit: 4096),
            error: .string(limit: 4096)
        )

        guard branchResult.terminationStatus.isSuccess, let branchName = branchResult.standardOutput else {
            if let standardError = branchResult.standardError {
                printError(standardError)
            }
            printError("Failed to get current branch name")
            throw ExitCode(1)
        }

        let trimmedBranchName = branchName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedBranchName.isEmpty {
            printError("Not currently on a branch (detached HEAD state)")
            throw ExitCode(1)
        }

        if verbose {
            printError("Current branch: \(trimmedBranchName)")
        }

        if !force {
            // Check for uncommitted changes
            let statusResult = try await Subprocess.run(
                .name("git"),
                arguments: [
                    "status",
                    "--porcelain",
                ],
                output: .string(limit: 65536),
                error: .string(limit: 4096)
            )

            guard statusResult.terminationStatus.isSuccess else {
                if let standardError = statusResult.standardError {
                    printError(standardError)
                }
                printError("Failed to check git status")
                throw ExitCode(1)
            }

            if let statusOutput = statusResult.standardOutput, !statusOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                printError("The worktree has uncommitted changes:")
                print(statusOutput)
                printError("\nUse --force to remove anyway.")
                throw ExitCode(1)
            }

            // Check for unpushed commits
            // First, check if the branch has an upstream
            let upstreamResult = try await Subprocess.run(
                .name("git"),
                arguments: [
                    "rev-parse",
                    "--abbrev-ref",
                    "\(trimmedBranchName)@{upstream}",
                ],
                output: .string(limit: 4096),
                error: .string(limit: 4096)
            )

            if upstreamResult.terminationStatus.isSuccess {
                // Branch has an upstream, check for unpushed commits
                let unpushedResult = try await Subprocess.run(
                    .name("git"),
                    arguments: [
                        "log",
                        "\(trimmedBranchName)@{upstream}..\(trimmedBranchName)",
                        "--oneline",
                    ],
                    output: .string(limit: 65536),
                    error: .string(limit: 4096)
                )

                guard unpushedResult.terminationStatus.isSuccess else {
                    if let standardError = unpushedResult.standardError {
                        printError(standardError)
                    }
                    printError("Failed to check for unpushed commits")
                    throw ExitCode(1)
                }

                if let unpushedOutput = unpushedResult.standardOutput, !unpushedOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    printError("The branch has unpushed commits:")
                    print(unpushedOutput)
                    printError("\nUse --force to remove anyway.")
                    throw ExitCode(1)
                }
            } else if verbose {
                printError("Branch has no upstream, skipping unpushed commits check")
            }
        }

        // Get the main worktree path before we remove this one
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
            if let standardError = mainWorktreeResult.standardError {
                printError(standardError)
            }
            printError("Failed to determine git common directory")
            throw ExitCode(1)
        }

        let trimmedGitCommonDir = gitCommonDir.trimmingCharacters(in: .whitespacesAndNewlines)
        let mainWorktreePath = URL(filePath: trimmedGitCommonDir).deletingLastPathComponent().path()

        if verbose {
            printError("Main worktree path: \(mainWorktreePath)")
        }

        // Change to a different directory (parent of worktree) so we can remove it
        let parentDir = URL(filePath: trimmedWorktreePath).deletingLastPathComponent().path()
        FileManager.default.changeCurrentDirectoryPath(parentDir)

        // Remove the worktree
        printError("Removing worktree at \(trimmedWorktreePath)...")
        let removeWorktreeResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "-C", mainWorktreePath,
                "worktree", "remove",
                trimmedWorktreePath,
            ],
            output: .standardOutput,
            error: .standardError
        )

        guard removeWorktreeResult.terminationStatus.isSuccess else {
            printError("Failed to remove worktree")
            throw ExitCode(1)
        }

        // Delete the branch
        printError("Deleting branch \(trimmedBranchName)...")
        let deleteBranchResult = try await Subprocess.run(
            .name("git"),
            arguments: [
                "-C", mainWorktreePath,
                "branch",
                "-D",
                trimmedBranchName,
            ],
            output: .standardOutput,
            error: .standardError
        )

        guard deleteBranchResult.terminationStatus.isSuccess else {
            printError("Failed to delete branch")
            throw ExitCode(1)
        }

        print("Successfully removed worktree and branch '\(trimmedBranchName)'")
        print("\nYou can return to the main worktree at:")
        print("  \(mainWorktreePath)")
    }
}
