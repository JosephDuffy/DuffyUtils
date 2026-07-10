import ArgumentParser
import Foundation
import Subprocess

@main
struct ExportSignedApp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-signed-app",
        abstract: "Archive, notarise, and export a signed Jira Tools disk image.",
    )

    @Option(help: "The Developer ID Application signing identity.")
    var signingIdentity: String

    @Option(help: "The Apple Developer team identifier.")
    var teamID: String

    @Option(help: "The xcrun notarytool keychain profile to use.")
    var notaryProfile: String

    @Option(help: "The directory where release artifacts are written.")
    var outputDirectory = ".build/exports"

    @Flag(help: "Replace an existing exported disk image.")
    var replace = false

    mutating func run() async throws {
        guard signingIdentity.hasPrefix("Developer ID Application:") else {
            throw ValidationError("A Developer ID Application signing identity is required.")
        }

        let outputURL = URL(filePath: outputDirectory, directoryHint: .isDirectory)
        let archiveURL = outputURL.appendingPathComponent("JiraTools.xcarchive", isDirectory: true)
        let exportURL = outputURL.appendingPathComponent("JiraTools", isDirectory: true)
        let dmgURL = outputURL.appendingPathComponent("JiraTools.dmg", isDirectory: true)
        try prepareOutput(
            outputURL: outputURL,
            archiveURL: archiveURL,
            exportURL: exportURL,
            dmgURL: dmgURL,
        )

        try await run("xcodebuild", [
            "archive",
            "-project", "Apps/JiraTools/JiraTools.xcodeproj",
            "-scheme", "JiraToolsApp",
            "-configuration", "Release",
            "-archivePath", archiveURL.path(),
            "ARCHS=arm64 x86_64",
            "ONLY_ACTIVE_ARCH=NO",
            "DEVELOPMENT_TEAM=\(teamID)",
            "CODE_SIGN_STYLE=Manual",
            "CODE_SIGN_IDENTITY=\(signingIdentity)",
        ])
        try await run("xcodebuild", [
            "-exportArchive",
            "-archivePath", archiveURL.path(),
            "-exportPath", exportURL.path(),
            "-exportOptionsPlist", try exportOptionsPlist(at: outputURL).path(),
        ])

        let appURL = exportURL
            .appendingPathComponent("Jira Tools.app", isDirectory: true)
        try await run(
            "codesign",
            ["--verify", "--deep", "--strict", "--verbose=2", appURL.path(percentEncoded: false)]
        )
        try FileManager.default.createSymbolicLink(
            atPath: exportURL.appending(path: "Applications").path(),
            withDestinationPath: "/Applications",
        )
        try await run("hdiutil", [
            "create",
            "-volname", "Jira Tools",
            "-srcfolder", exportURL.path(),
            "-ov",
            "-format", "UDZO",
            dmgURL.path(),
        ])
        try await run("xcrun", [
            "notarytool",
            "submit",
            dmgURL.path(),
            "--keychain-profile", notaryProfile,
            "--wait",
        ])
        try await run("xcrun", ["stapler", "staple", dmgURL.path()])
        try await run("xcrun", ["stapler", "validate", dmgURL.path()])

        print("Exported notarised disk image to \(dmgURL.path())")
    }

    private func prepareOutput(
        outputURL: URL,
        archiveURL: URL,
        exportURL: URL,
        dmgURL: URL,
    ) throws {
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        for url in [archiveURL, exportURL, dmgURL]
        where FileManager.default.fileExists(atPath: url.path()) {
            guard replace else {
                throw ValidationError("Export output already exists: \(url.path()). Pass --replace to overwrite it.")
            }
            try FileManager.default.removeItem(at: url)
        }
    }

    private func exportOptionsPlist(at outputURL: URL) throws -> URL {
        let url = outputURL.appending(path: "JiraToolsExportOptions.plist", directoryHint: .notDirectory)
        let options: [String: Any] = [
            "destination": "export",
            "method": "developer-id",
            "signingStyle": "manual",
            "stripSwiftSymbols": true,
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: options,
            format: .xml,
            options: 0,
        )
        try data.write(to: url)
        return url
    }

    private func run(_ executable: String, _ arguments: [String]) async throws {
        let result = try await Subprocess.run(
            .name(executable),
            arguments: Arguments(arguments),
            output: .standardOutput,
            error: .standardError,
        )
        guard result.terminationStatus.isSuccess else {
            throw ExitCode(1)
        }
    }
}
