import DigUpKit
import Foundation
import Testing
@testable import LlamaRuntime

@Suite struct NativeTextBudgetTests {
    static let textModelPresent = (try? LlamaModels.locate()) != nil

    @Test(.enabled(if: textModelPresent)) func oversizedTextNeverSilentlyDropsItsTail() throws {
        let embedder = try LlamaEmbedder(models: LlamaModels.locate(), textOnly: true)
        defer { embedder.close() }
        // Synthetic unspaced Han is far beyond the query encoder's 512-token context.
        #expect(throws: (any Error).self) {
            _ = try embedder.embedTexts([String(repeating: "租房合同", count: 1500) + "尾部标记"])
        }
    }
}
