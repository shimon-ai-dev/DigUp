import DigUpKit
import Foundation
import Testing
@testable import DigUpApp

@Suite(.serialized) struct DataIsolationTests {
    // These tests target app-default aliases only on GitHub's fresh hosted runner.
    // They never replace a pre-existing data directory or start a download/UI.
    static let freshRunner = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        && !FileManager.default.fileExists(atPath: AppIdentity.supportDirectory.path)

    @Test(.enabled(if: freshRunner)) func unsafeDefaultAliasFailsBeforeAppDataIO() throws {
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp")
        let root = AppIdentity.supportDirectory
        #expect(!AppIdentity.isOriginalDataDirectory(AppIdentity.indexDirectory))
        try FileManager.default.createDirectory(at: root.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: original)
        defer { try? FileManager.default.removeItem(at: root) } // only the link created above
        #expect(throws: WorkerError.self) { _ = try AppSettings.load() }
        #expect(!FileManager.default.fileExists(atPath: original.path))
    }

    @MainActor @Test func modelDownloadRejectsOriginalDestinationWithoutStartingIO() {
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp/Models")
        let download = ModelDownload(folder: original)
        if case .failed = download.phase {} else { Issue.record("Unsafe original model destination was accepted") }
    }
}
