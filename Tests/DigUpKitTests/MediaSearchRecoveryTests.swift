import Foundation
import Testing
@testable import DigUpKit

@Suite final class MediaSearchRecoveryTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-recovery-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: folder) }

    static func vector(_ cosine: Float, axis: Int = 1) -> [Float] {
        var vector = [Float](repeating: 0, count: Vectors.dimension)
        vector[0] = cosine
        vector[axis] = (1 - cosine * cosine).squareRoot()
        return vector
    }
    var query: [Float] { Self.vector(1) }

    @discardableResult func add(_ store: IndexStore, _ number: Int, cosine: Float,
                                kind: FileKind = .audio, body: String? = nil) throws -> Int64 {
        let id = try store.insert(Candidate(path: "/synthetic/item\(number).dat", kind: kind,
                                            size: 1, mtime: 1, inode: UInt64(number), device: 1))
        try store.addSegment(file: id, kind: kind == .audio ? .audio : kind == .video ? .frame : .chunk,
                             modality: kind == .audio ? .audio : kind == .video ? .image : .text,
                             loc: 4, locEnd: 6, text: body, vector: Self.vector(cosine))
        return id
    }

    @Test func sparseAudioRecoversSeparatedCandidateWithoutCallingItStrong() throws {
        let store = try IndexStore(directory: folder)
        for (n, cosine) in [Float(0.78), 0.56, 0.55, 0.52].enumerated() {
            try add(store, n + 1, cosine: cosine)
        }
        let searcher = try Searcher(store: store)
        let filters: [Set<FileKind>?] = [nil, [.audio]]
        for kinds in filters {
            let hits = try searcher.search("去超市买牛奶和鸡蛋", queryVector: query, kinds: kinds)
            #expect(hits.map(\.path) == ["/synthetic/item1.dat"])
            #expect(hits.first?.loc == 4)
            #expect(Searcher.strongCount(hits) == 0)
        }
    }

    @Test func recoveryNeverChangesExistingQualifyingOrder() throws {
        let store = try IndexStore(directory: folder)
        try add(store, 1, cosine: 0.9, kind: .doc, body: "exact budget lookup")
        for n in 2...24 { try add(store, n, cosine: 0.45 + Float(n % 5) * 0.05, kind: .doc) }
        try add(store, 25, cosine: 0.67)
        let searcher = try Searcher(store: store)
        let hits = try searcher.search("exact budget lookup", queryVector: query)
        #expect(hits.first?.path == "/synthetic/item1.dat")
        #expect(Searcher.strongCount(hits) == 1)
        #expect(hits.contains { $0.path == "/synthetic/item25.dat" })
        #expect(hits.last?.path == "/synthetic/item25.dat")
    }

    @Test func noSignalEmptyInputAndKindExclusionsRemainEmpty() throws {
        let store = try IndexStore(directory: folder)
        for n in 1...4 { try add(store, n, cosine: 0.4 + Float(n) / 100) }
        let searcher = try Searcher(store: store)
        #expect(try searcher.search("unrelated lunar geology", queryVector: query).isEmpty)
        #expect(try searcher.search("", queryVector: query).isEmpty)
        #expect(try searcher.search("unrelated lunar geology", queryVector: query, kinds: [.video]).isEmpty)
        #expect(try searcher.search("unrelated lunar geology", queryVector: nil).isEmpty)
        #expect(try searcher.search("unrelated lunar geology", queryVector: [Float](repeating: .nan, count: Vectors.dimension)).isEmpty)
    }

    @Test func unrelatedTightlyClusteredMediaAreNotSuggested() throws {
        let store = try IndexStore(directory: folder)
        for n in 1...4 { try add(store, n, cosine: 0.59 + Float(n) / 1000) }
        #expect(try Searcher(store: store).search("unrelated lunar geology", queryVector: query).isEmpty)
    }

    @Test func invalidStoredVectorDoesNotPoisonValidMedia() throws {
        let store = try IndexStore(directory: folder)
        for n in 1...4 { try add(store, n, cosine: n == 1 ? 0.78 : 0.4) }
        let id = try store.insert(Candidate(path: "/synthetic/corrupt.wav", kind: .audio,
                                            size: 1, mtime: 1, inode: 99, device: 1))
        try store.addSegment(file: id, kind: .audio, modality: .audio,
                             vector: [Float](repeating: .nan, count: Vectors.dimension))
        let hits = try Searcher(store: store).search("groceries for breakfast", queryVector: query)
        #expect(hits.first?.path == "/synthetic/item1.dat")
        #expect(hits.allSatisfy { $0.score.isFinite && $0.cosine?.isFinite == true })
    }
}
