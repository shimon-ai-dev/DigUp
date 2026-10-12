import DigUpKit
import Foundation
import Testing
@testable import DigUpApp

/// Exercise the actual app launch path with the real CLI under its packaged name.
/// CI supplies the freshly built helper at the test runner's bundle location;
/// no installed DigUp app or user's folders are used.
@Suite(.serialized) struct EstimateHelperTests {
    static let nativeHelper = ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true"
        ? ProcessInfo.processInfo.environment["DIGUP_TEST_HELPER"] : nil
    static let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/" + AppIdentity.helperName)

    @MainActor @Test(.enabled(if: nativeHelper != nil))
    func folderEstimatesLaunchTheIsolatedPackagedHelper() async throws {
        let manager = FileManager.default
        let source = try #require(Self.nativeHelper)
        let destination = Self.helper
        #expect(!manager.fileExists(atPath: destination.deletingLastPathComponent().appendingPathComponent("digup").path))
        try #require(!manager.fileExists(atPath: destination.path))
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.copyItem(at: URL(fileURLWithPath: source), to: destination)
        defer { try? manager.removeItem(at: destination) }
        let fixture = manager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DigUpEstimateTests-" + UUID().uuidString)
        try manager.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: fixture) }
        try Data("公开合成的租房合同资料".utf8).write(to: fixture.appendingPathComponent("租房合同.txt"))
        let results = EstimateResults()
        Estimates.run([fixture]) { results.values.append($0) }
        for _ in 0..<100 where results.values.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try #require(results.values.first, "The app must launch digup-test and finish the folder estimate")
        #expect(!result.failed && result.readable)
        #expect(result.files[.doc] == 1)
        #expect(result.folder == fixture.path)
    }

    @MainActor @Test(.enabled(if: nativeHelper != nil))
    func missingHelperReportsFailureInsteadOfLeavingAnEstimatePending() async throws {
        try #require(!FileManager.default.fileExists(atPath: Self.helper.path))
        let results = EstimateResults()
        let folder = URL(fileURLWithPath: "/synthetic-missing-helper-fixture")
        Estimates.run([folder]) { results.values.append($0) }
        for _ in 0..<20 where results.values.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        let result = try #require(results.values.first, "Launch failure must complete the pending estimate")
        #expect(result.failed)
        #expect(result.folder == folder.path)
    }
}

@MainActor private final class EstimateResults {
    var values: [FolderEstimate] = []
}
