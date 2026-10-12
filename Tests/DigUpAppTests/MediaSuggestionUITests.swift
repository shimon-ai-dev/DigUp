import Foundation
import Testing
@testable import DigUpKit
@testable import DigUpApp

@MainActor struct MediaSuggestionUITests {
    @Test func recoveryIsFoldedAndHasLocalizedAccessibleReason() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-suggestion-ui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try IndexStore(directory: directory)
        for (n, cosine) in [Float(0.78), 0.56, 0.55, 0.52].enumerated() {
            let id = try store.insert(Candidate(path: "/synthetic/clip\(n).wav", kind: .audio,
                                               size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
            var vector = [Float](repeating: 0, count: Vectors.dimension)
            vector[0] = cosine; vector[1] = (1 - cosine * cosine).squareRoot()
            try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 2, locEnd: 4, vector: vector)
        }
        var query = [Float](repeating: 0, count: Vectors.dimension); query[0] = 1
        let hits = try Searcher(store: store).search("去超市买牛奶和鸡蛋", queryVector: query)
        let results = ResultSet(hits, query: "去超市买牛奶和鸡蛋")
        #expect(results.groups.isEmpty && results.ranked.isEmpty)
        #expect(results.weaker.count == 1)
        let row = try #require(results.weaker.first)
        #expect(!row.matchedMeaning && !row.matchedWords)
        #expect(row.reason.contains("confidence") || row.reason.contains("可信度"))
        for language in ["en", "zh-Hans"] {
            let l = Localization(bundle: Localization.current.bundle, preferredLanguages: [language],
                                 formattingLocale: Locale(identifier: "en_US"))
            #expect(l.text("result.reason.suggestion", fallback: "__MISSING__") != "__MISSING__")
            #expect(l.text("search.suggestions.available", fallback: "__MISSING__") != "__MISSING__")
            #expect(l.text("settings.index.retryFailed", fallback: "__MISSING__") != "__MISSING__")
        }
    }
}
