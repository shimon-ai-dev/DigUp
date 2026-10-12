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
        #expect(!AppIdentity.isOriginalDataDirectory(AppIdentity.indexDirectory))
        #expect(AppIdentity.helperName == "digup-test")
        #expect(!AppIdentity.updatesEnabled)
    }
}
