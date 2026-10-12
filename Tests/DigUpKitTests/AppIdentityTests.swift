import Foundation
import Testing
@testable import DigUpKit

@Suite struct AppIdentityTests {
    @Test func originalIndexPathAndItsSymlinkCannotBeOpened() throws {
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp/index.noindex")
        #expect(throws: WorkerError.self) { _ = try IndexStore(directory: original) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let link = temporary.appendingPathComponent("original-index-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        #expect(throws: (any Error).self) { _ = try IndexStore(directory: link) }
        #expect(AppIdentity.helperName == "digup-test")
        #expect(!AppIdentity.updatesEnabled)
    }
    @Test func temporaryDirectoriesAndSafeAliasesRemainUsable() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let target = temporary.appendingPathComponent("safe-index")
        let link = temporary.appendingPathComponent("safe-index-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        print("Data-path regression: temporary=\(temporary.path), standardized=\(temporary.standardizedFileURL.path), resolved=\(temporary.resolvingSymlinksInPath().path)")
        #expect(!AppIdentity.isOriginalDataDirectory(temporary))
        #expect(!AppIdentity.isOriginalDataDirectory(target))
        #expect(!AppIdentity.isOriginalDataDirectory(link))
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        _ = try IndexStore(directory: link)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent(IndexStore.mainFile).path))
    }
    @Test func relativeAliasesAndCyclesFailClosed() throws {
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp")
        let alias = temporary.appendingPathComponent("original")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        let relative = temporary.appendingPathComponent("relative")
        try FileManager.default.createSymbolicLink(atPath: relative.path, withDestinationPath: "original/Models")
        #expect(AppIdentity.isOriginalDataDirectory(relative.appendingPathComponent("future.gguf")))
        let cycle = temporary.appendingPathComponent("cycle")
        try FileManager.default.createSymbolicLink(atPath: cycle.path, withDestinationPath: "cycle")
        #expect(AppIdentity.isOriginalDataDirectory(cycle))
        #expect(throws: WorkerError.self) { _ = try IndexStore(directory: cycle) }
    }
}
