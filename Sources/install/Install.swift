import ArgumentParser
import Foundation
import Subprocess

@main
struct Install: AsyncParsableCommand {
    @Option(help: "Specify the directory to install the tools to.")
    public var directory: String = "/usr/local/bin"

    public func run() async throws {
        let executablesResult = try await Subprocess.run(
            .name("swift"),
            arguments: [
                "package",
                "show-executables",
                "--format", "json",
            ],
            output: .data(limit: 4096)
        )
        let executablesJSONData = executablesResult.standardOutput

        let decoder = JSONDecoder()
        let packageExecutables = try decoder.decode(
            [PackageExecutable].self,
            from: executablesJSONData
        )
        let localPackageExecutables = packageExecutables
            // Remove package executables from dependencies and the install tool itself.
            .filter { $0.package == nil && $0.name != "install" }
            .map(\.name)

        for localPackageExecutable in localPackageExecutables {
            printStdErr("Found local package executable: \(localPackageExecutable)")
            let buildResult = try await Subprocess.run(
                .name("swift"),
                arguments: [
                    "build",
                    "--product", localPackageExecutable,
                    "--configuration", "release",
                ],
                output: .standardError
            )

            if !buildResult.terminationStatus.isSuccess {
                printStdErr("Failed to build \(localPackageExecutable)")
                throw ExitCode(1)
            }

            printStdErr("Getting bin path")

            let showBinPathResult = try await Subprocess.run(
                .name("swift"),
                arguments: [
                    "build",
                    "--product", localPackageExecutable,
                    "--configuration", "release",
                    "--show-bin-path",
                ],
                output: .string(limit: 4096)
            )
            guard let binPath = showBinPathResult.standardOutput?.trimmingCharacters(in: .whitespacesAndNewlines) else {
                printStdErr("Failed to get binary path for \(localPackageExecutable)")
                throw ExitCode(1)
            }
            let copyResult = try await Subprocess.run(
                .name("sudo"),
                arguments: [
                    "cp",
                    "\(binPath)/\(localPackageExecutable)",
                    "\(directory)/\(localPackageExecutable)",
                ],
                output: .standardError
            )
            if copyResult.terminationStatus.isSuccess {
                printStdErr("Installed '\(localPackageExecutable)' to \(directory)/\(localPackageExecutable)")
            } else {
                printStdErr("Failed to install '\(localPackageExecutable)' to \(directory)/\(localPackageExecutable)")
                throw ExitCode(1)
            }
        }
    }
}

func printStdErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

struct PackageExecutable: Decodable {
    let name: String
    let package: String?
}
