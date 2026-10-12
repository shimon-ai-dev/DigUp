import Foundation
import Testing
@testable import DigUpKit

@Suite final class MediaEmbeddingFailureTests {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-media-errors-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: folder) }

    func setup(_ embedder: MediaFailureEmbedder) throws -> (IndexStore, Indexer, URL) {
        let files = folder.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appendingPathComponent("public-synthetic-tone.wav")
        var data = Data()
        func word<T: FixedWidthInteger>(_ n: T) { var v = n.littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        let count = 16_000 * 6
        text("RIFF"); word(UInt32(36 + count * 2)); text("WAVEfmt "); word(UInt32(16))
        word(UInt16(1)); word(UInt16(1)); word(UInt32(16_000)); word(UInt32(32_000)); word(UInt16(2)); word(UInt16(16))
        text("data"); word(UInt32(count * 2))
        for n in 0..<count { word(Int16(sin(Double(n) * 2 * .pi * 440 / 16_000) * 8_000)) }
        try data.write(to: url)
        let store = try IndexStore(directory: folder.appendingPathComponent("index"))
        var options = IndexOptions(); options.audioWindow = 2; options.audioHop = 2
        let indexer = try Indexer(store: store, options: options, makeEmbedder: { embedder })
        _ = try indexer.sync([files])
        return (store, indexer, files)
    }

    @Test func partialAudioFailurePreservesGoodWindowsAndOriginalError() throws {
        let embedder = MediaFailureEmbedder()
        embedder.reply = { paths in paths.enumerated().map { n, _ in
            n == 1 ? Embedding(vector: nil, error: "decode failed: synthetic 100% context")
                : Embedding(vector: FakeEmbedder.vector(for: "window\(n)"), error: nil)
        } }
        let (store, indexer, files) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        #expect(try store.counts().vectors == 2)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("decode failed: synthetic 100% context") == true)
        #expect(detail?.contains("2") == true)
        // Unchanged failure gets one automatic retry, preserving valid windows and avoiding duplicates.
        #expect(try indexer.sync([files]).queued.count == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: FakeEmbedder.vector(for: "recovered"), error: nil) } }
        #expect(try indexer.run()["done"] == 1)
        #expect(embedder.batchSizes == [3, 1])
        #expect(try store.counts().vectors == 3)
        #expect(try indexer.sync([files]).queued.isEmpty)
    }

    @Test func missingResponsesAndNilVectorsAreFailedAndRetryIsBounded() throws {
        let embedder = MediaFailureEmbedder(); embedder.reply = { _ in [] }
        let (store, indexer, files) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("response") == true)
        #expect(try indexer.sync([files]).queued.count == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: nil, error: nil) } }
        #expect(try indexer.run()["failed"] == 1)
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("vector") == true)
        #expect(try indexer.sync([files]).queued.isEmpty)
        #expect(try indexer.run().isEmpty)
        #expect(try store.counts().vectors == 0)
    }

    @Test func errorWithVectorAndMalformedVectorCannotBeMarkedDone() throws {
        let embedder = MediaFailureEmbedder()
        embedder.reply = { paths in paths.enumerated().map { n, _ in
            Embedding(vector: n == 0 ? FakeEmbedder.vector(for: "conflicted")
                : n == 1 ? [.nan] : [Float](repeating: 0, count: Vectors.dimension),
                      error: n == 0 ? "model rejected this window" : nil)
        } }
        let (store, indexer, _) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        #expect(try store.counts().vectors == 0)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("model rejected this window") == true)
    }
}

final class MediaFailureEmbedder: Embedder {
    let info = FakeEmbedder().info
    var reply: ([String]) -> [Embedding] = { $0.map { _ in Embedding(vector: nil, error: nil) } }
    var batchSizes: [Int] = []
    func embedTexts(_ texts: [String]) throws -> [[Float]] { texts.map(FakeEmbedder.vector(for:)) }
    func embedImages(_ paths: [String], budget: Int) throws -> [Embedding] { reply(paths) }
    func embedAudio(_ paths: [String]) throws -> [Embedding] { batchSizes.append(paths.count); return reply(paths) }
    func close() {}
}
