import ArgumentParser
import Foundation
import Subprocess

@main
struct ExportSignedCommand: AsyncParsableCommand {
    private static let commandName = "export-signed-command"
    private static let developerIDApplicationIdentityPrefix = "Developer ID Application:"
    private static let architectures = ["arm64", "x86_64"]

    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: commandName,
            abstract: "Export a signed and notarised release build of a local command.",
            discussion: """
            Builds one of this package's executable products.

            The command signs the binary with a Developer ID Application identity.
            It writes a zip archive and submits it for notarisation.

            Create a notarytool profile first with:

                xcrun notarytool store-credentials <profile-name>

            The resulting zip is the file to share with another Mac.
            """
        )
    }

    @Argument(help: "The local executable product to export.")
    public var product: String

    @Option(help: "The Developer ID Application signing identity to pass to codesign.")
    public var signingIdentity: String

    @Option(
        help: "The xcrun notarytool keychain profile to use when submitting the zip."
    )
    public var notaryProfile: String

    @Option(help: "The directory to write the signed binary and notarised zip to.")
    public var outputDirectory: String = ".build/exports"

    @Flag(help: "Replace an existing exported binary or zip.")
    public var replace = false

    @Flag(help: "Print each export step before it runs.")
    public var verbose = false

    public func run() async throws {
        guard signingIdentity.hasPrefix(Self.developerIDApplicationIdentityPrefix) else {
            printStdErr("The signing identity must be a Developer ID Application certificate.")
            printStdErr(
                "Apple Development and Apple Distribution certificates cannot be notarised."
            )
            throw ExitCode(1)
        }

        let localProducts = try await localExecutableProducts()
        guard localProducts.contains(product) else {
            printStdErr("Unknown local executable product: \(product)")
            printStdErr("Available products: \(localProducts.sorted().joined(separator: ", "))")
            throw ExitCode(1)
        }

        let outputDirectoryURL = resolvedDirectoryURL(from: outputDirectory)
        let exportDirectoryURL = outputDirectoryURL.appending(
            path: product,
            directoryHint: .isDirectory,
        )
        let exportBinaryURL = exportDirectoryURL.appending(
            path: product,
            directoryHint: .notDirectory,
        )
        let exportZipURL = outputDirectoryURL.appending(
            path: "\(product).zip",
            directoryHint: .notDirectory,
        )

        try prepareOutputDirectory(
            outputDirectoryURL,
            exportDirectoryURL: exportDirectoryURL,
            exportZipURL: exportZipURL,
        )

        let releaseBinaryURLs = try await releaseBinaryURLs(for: product)
        try await createUniversalBinary(
            from: releaseBinaryURLs,
            at: exportBinaryURL,
        )
        try await copySwiftRuntimeLibraries(
            for: exportBinaryURL,
            to: exportDirectoryURL,
        )

        try await signSwiftRuntimeLibraries(in: exportDirectoryURL)
        try await sign(binaryURL: exportBinaryURL)
        try await verifySignature(binaryURL: exportBinaryURL)
        try await createZip(
            exportDirectoryURL: exportDirectoryURL,
            zipURL: exportZipURL,
        )
        try await notarise(zipURL: exportZipURL)

        print("Exported notarised command archive to \(exportZipURL.path())")
    }

    private func localExecutableProducts() async throws -> Set<String> {
        let arguments = [
            "package",
            "show-executables",
            "--format", "json",
        ]
        logCommand("swift", arguments)

        let executablesResult = try await Subprocess.run(
            .name("swift"),
            arguments: Arguments(arguments),
            output: .data(limit: 4096),
            error: .standardError,
        )

        guard executablesResult.terminationStatus.isSuccess else {
            printStdErr("Failed to list package executables")
            throw ExitCode(1)
        }

        let packageExecutables = try JSONDecoder().decode(
            [PackageExecutable].self,
            from: executablesResult.standardOutput,
        )

        let productNames = packageExecutables
            .filter { $0.package == nil }
            .filter { $0.name != "install" && $0.name != Self.commandName }
            .map(\.name)

        return Set(productNames)
    }

    private func prepareOutputDirectory(
        _ outputDirectoryURL: URL,
        exportDirectoryURL: URL,
        exportZipURL: URL,
    ) throws {
        try FileManager.default.createDirectory(
            at: outputDirectoryURL,
            withIntermediateDirectories: true,
        )

        for url in [exportDirectoryURL, exportZipURL]
        where FileManager.default.fileExists(atPath: url.path()) {
            guard replace else {
                printStdErr("Export output already exists: \(url.path())")
                printStdErr("Pass --replace to overwrite existing export files.")
                throw ExitCode(1)
            }

            try FileManager.default.removeItem(at: url)
        }

        try FileManager.default.createDirectory(
            at: exportDirectoryURL,
            withIntermediateDirectories: true,
        )
    }

    private func releaseBinaryURLs(for product: String) async throws -> [URL] {
        var binaryURLs: [URL] = []
        for architecture in Self.architectures {
            try await build(product: product, architecture: architecture)
            binaryURLs.append(
                try await releaseBinaryURL(
                    for: product,
                    architecture: architecture,
                )
            )
        }

        return binaryURLs
    }

    private func build(product: String, architecture: String) async throws {
        let arguments = releaseBuildArguments(
            product: product,
            architecture: architecture,
        )
        logCommand("swift", arguments)

        let buildResult = try await Subprocess.run(
            .name("swift"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard buildResult.terminationStatus.isSuccess else {
            printStdErr("Failed to build \(product) for \(architecture)")
            throw ExitCode(1)
        }
    }

    private func releaseBinaryURL(
        for product: String,
        architecture: String,
    ) async throws -> URL {
        let arguments = releaseBuildArguments(
            product: product,
            architecture: architecture,
            showBinPath: true,
        )
        logCommand("swift", arguments)

        let showBinPathResult = try await Subprocess.run(
            .name("swift"),
            arguments: Arguments(arguments),
            output: .string(limit: 4096),
            error: .standardError,
        )

        let binPath = showBinPathResult.standardOutput?.trimmingCharacters(
            in: .whitespacesAndNewlines,
        )
        guard
            showBinPathResult.terminationStatus.isSuccess,
            let binPath,
            !binPath.isEmpty
        else {
            printStdErr("Failed to get the release binary path for \(architecture)")
            throw ExitCode(1)
        }

        return URL(filePath: binPath, directoryHint: .isDirectory).appending(
            path: product,
            directoryHint: .notDirectory,
        )
    }

    private func releaseBuildArguments(
        product: String,
        architecture: String,
        showBinPath: Bool = false,
    ) -> [String] {
        var arguments = [
            "build",
            "--product", product,
            "--configuration", "release",
            "--arch", architecture,
            "--jobs", "4",
            // Avoid a Swift compiler stall while optimising ArgumentParser as one module.
            "-Xswiftc", "-no-whole-module-optimization",
        ]
        if showBinPath {
            arguments.append("--show-bin-path")
        }

        return arguments
    }

    private func createUniversalBinary(
        from binaryURLs: [URL],
        at outputURL: URL,
    ) async throws {
        let arguments = [
            "-create",
        ] + binaryURLs.map(\.path) + [
            "-output", outputURL.path(),
        ]
        logCommand("lipo", arguments)

        let lipoResult = try await Subprocess.run(
            .name("lipo"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard lipoResult.terminationStatus.isSuccess else {
            printStdErr("Failed to create a universal binary")
            throw ExitCode(1)
        }
    }

    private func copySwiftRuntimeLibraries(
        for binaryURL: URL,
        to exportDirectoryURL: URL,
    ) async throws {
        let arguments = [
            "swift-stdlib-tool",
            "--copy",
            "--platform", "macosx",
            "--scan-executable", binaryURL.path(),
            "--destination", exportDirectoryURL.path(),
        ]
        logCommand("xcrun", arguments)

        let copyResult = try await Subprocess.run(
            .name("xcrun"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard copyResult.terminationStatus.isSuccess else {
            printStdErr("Failed to copy Swift runtime libraries")
            throw ExitCode(1)
        }
    }

    private func signSwiftRuntimeLibraries(in exportDirectoryURL: URL) async throws {
        let runtimeLibraryURLs = try FileManager.default.contentsOfDirectory(
            at: exportDirectoryURL,
            includingPropertiesForKeys: nil,
        )
        .filter { $0.pathExtension == "dylib" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for runtimeLibraryURL in runtimeLibraryURLs {
            try await sign(binaryURL: runtimeLibraryURL)
            try await verifySignature(binaryURL: runtimeLibraryURL)
        }
    }

    private func sign(binaryURL: URL) async throws {
        let arguments = [
            "--force",
            "--options", "runtime",
            "--sign", signingIdentity,
            "--timestamp",
            binaryURL.path(),
        ]
        logCommand("codesign", arguments)

        let signResult = try await Subprocess.run(
            .name("codesign"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard signResult.terminationStatus.isSuccess else {
            printStdErr("Failed to sign \(binaryURL.path())")
            throw ExitCode(1)
        }
    }

    private func verifySignature(binaryURL: URL) async throws {
        let arguments = [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            binaryURL.path(),
        ]
        logCommand("codesign", arguments)

        let verifyResult = try await Subprocess.run(
            .name("codesign"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard verifyResult.terminationStatus.isSuccess else {
            printStdErr("Failed to verify signature for \(binaryURL.path())")
            throw ExitCode(1)
        }
    }

    private func createZip(exportDirectoryURL: URL, zipURL: URL) async throws {
        let arguments = [
            "-c",
            "-k",
            "--keepParent",
            exportDirectoryURL.path(),
            zipURL.path(),
        ]
        logCommand("ditto", arguments)

        let zipResult = try await Subprocess.run(
            .name("ditto"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard zipResult.terminationStatus.isSuccess else {
            printStdErr("Failed to create zip at \(zipURL.path())")
            throw ExitCode(1)
        }
    }

    private func notarise(zipURL: URL) async throws {
        let arguments = [
            "notarytool",
            "submit",
            zipURL.path(),
            "--keychain-profile", notaryProfile,
            "--wait",
        ]
        logCommand("xcrun", arguments)

        let notariseResult = try await Subprocess.run(
            .name("xcrun"),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )

        guard notariseResult.terminationStatus.isSuccess else {
            printStdErr("Failed to notarise \(zipURL.path())")
            throw ExitCode(1)
        }
    }

    private func logCommand(_ name: String, _ arguments: [String]) {
        if verbose {
            printStdErr("+ \(name) \(arguments.joined(separator: " "))")
        }
    }

    private func resolvedDirectoryURL(from path: String) -> URL {
        if path.hasPrefix("/") {
            return URL(filePath: path, directoryHint: .isDirectory)
        }

        return URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory,
        )
        .appending(
            path: path,
            directoryHint: .isDirectory,
        )
    }
}

private func printStdErr(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

private struct PackageExecutable: Decodable {
    let name: String
    let package: String?
}
