import ArgumentParser
import DuffyUtilsFoundation
import Foundation
import Subprocess

public enum GitConfigValue {
    public static func getValue(
        name: String,
        location: GitConfigValueLocation = .default
    ) async throws -> String? {
        var arguments = [
            "config",
            "--get", name,
        ]
        switch location {
        case .default:
            break
        case .system:
            arguments += ["--system"]
        case .global:
            arguments += ["--global"]
        case .local:
            arguments += ["--local"]
        case .worktree:
            arguments += ["--worktree"]
        }
        let result = try await Subprocess.run(
            .name("git"),
            arguments: Arguments(arguments),
            output: .string(limit: 4096)
        )

        if result.terminationStatus == .exited(1) {
            // No value set.
            return nil
        }

        guard result.terminationStatus.isSuccess else {
            switch result.terminationStatus {
            case .exited(let code):
                throw GitConfigValueProcessTerminatedError(code: code)
            case .unhandledException(let code):
                throw GitConfigValueProcessTerminatedError(code: code)
            }
        }

        guard let output = result.standardOutput else {
            throw GitConfigValueNoStandardOutputError()
        }

        if output.last?.isNewline == true {
            return String(output.dropLast())
        } else {
            return output
        }
    }
}

struct GitConfigValueProcessTerminatedError: LocalizedError {
    let code: TerminationStatus.Code

    var errorDescription: String? {
        "git process terminated with code: \(code)."
    }
}

struct GitConfigValueNoStandardOutputError: LocalizedError {
    var errorDescription: String? {
        "The git process did not produce a value UTF-8 standard output."
    }
}
