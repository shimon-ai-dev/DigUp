@preconcurrency import AVFoundation
import Foundation
import Testing
@testable import DigUpKit

@Suite(.serialized) final class MediaEmbeddingFailureTests {
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("DigUpTest-media-errors-\(UUID().uuidString)")
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

    @Test func truncatedBatchRetainsItsSuccessfulPrefix() throws {
        let embedder = MediaFailureEmbedder()
        embedder.reply = { _ in [Embedding(vector: FakeEmbedder.vector(for: "prefix"), error: nil)] }
        let (store, indexer, files) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        #expect(try store.counts().vectors == 1)
        #expect(try indexer.sync([files]).queued.count == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: FakeEmbedder.vector(for: "tail"), error: nil) } }
        #expect(try indexer.run()["done"] == 1)
        #expect(embedder.batchSizes == [3, 2])
        #expect(try store.counts().vectors == 3)
    }

    @Test func explicitRetryIsScopedAndKeepsAlreadySuccessfulWindows() throws {
        let embedder = MediaFailureEmbedder()
        embedder.reply = { paths in paths.enumerated().map { n, _ in
            Embedding(vector: n == 0 ? FakeEmbedder.vector(for: "good") : nil,
                      error: n == 0 ? nil : "persistent synthetic decoder failure")
        } }
        let (store, indexer, files) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        #expect(try indexer.sync([files]).queued.count == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: nil, error: "still failing") } }
        #expect(try indexer.run()["failed"] == 1)
        #expect(try indexer.sync([files]).queued.isEmpty)
        let outside = try store.insert(Candidate(path: "/outside/other.wav", kind: .audio,
                                                size: 1, mtime: 1, inode: 90, device: 1))
        try store.finish(outside, state: "failed")
        store.scope = [files.path]
        #expect(try store.retryFailedMedia() == 1)
        #expect(try store.counts().vectors == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: FakeEmbedder.vector(for: "finally recovered"), error: nil) } }
        #expect(try indexer.run()["done"] == 1)
        #expect(try store.counts().vectors == 3)
        #expect(embedder.batchSizes == [3, 2, 2])
        #expect(try store.files(under: ["/outside"]).first?.state == "failed")
    }

    @Test func excessResponsesFailClosedAndKeepWorkerErrorContext() throws {
        let embedder = MediaFailureEmbedder()
        embedder.reply = { paths in (0...paths.count).map { n in
            Embedding(vector: FakeEmbedder.vector(for: "response"), error: n == 0 ? "extra response context" : nil)
        } }
        let (store, indexer, _) = try setup(embedder)
        #expect(try indexer.run()["failed"] == 1)
        #expect(try store.counts().vectors == 0)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("response count mismatch") == true)
        #expect(detail?.contains("extra response context") == true)
    }

    @Test func excessImageResponsesKeepOriginalWorkerError() throws {
        let embedder = MediaFailureEmbedder()
        let (store, indexer, files) = try setup(embedder)
        try FileManager.default.removeItem(at: files.appendingPathComponent("public-synthetic-tone.wav"))
        let reference = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("LlamaRuntimeTests/Reference/photo.jpg")
        try FileManager.default.copyItem(at: reference, to: files.appendingPathComponent("public-synthetic-photo.jpg"))
        _ = try indexer.sync([files])
        embedder.reply = { _ in [Embedding(vector: FakeEmbedder.vector(for: "photo"), error: "synthetic excess photo context"),
                                Embedding(vector: FakeEmbedder.vector(for: "extra"), error: nil)] }
        #expect(try indexer.run()["failed"] == 1)
        #expect(try store.counts().vectors == 0)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("response count mismatch") == true)
        #expect(detail?.contains("synthetic excess photo context") == true)
    }

    @Test func videoFrameFailureKeepsSoundAndRetriesOnlyMissingFrames() async throws {
        let embedder = MediaFailureEmbedder()
        let (store, indexer, files) = try setup(embedder)
        let movie = files.appendingPathComponent("public-synthetic-video.mov")
        try await makeMovie(to: movie, sound: files.appendingPathComponent("public-synthetic-tone.wav"))
        try FileManager.default.removeItem(at: files.appendingPathComponent("public-synthetic-tone.wav"))
        _ = try indexer.sync([files])
        embedder.reply = { paths in paths.enumerated().map { n, path in
            path.hasSuffix(".jpg") && n == 0 ? Embedding(vector: nil, error: "synthetic frame decoder context")
                : Embedding(vector: FakeEmbedder.vector(for: path), error: nil)
        } }
        #expect(try indexer.run()["failed"] == 1)
        var audio = 0, frames = 0
        try store.db.query("SELECT kind, COUNT(*) FROM segments WHERE vec IS NOT NULL GROUP BY kind") {
            if $0.text(0) == "audio" { audio = Int($0.int(1)) }; if $0.text(0) == "frame" { frames = Int($0.int(1)) }
        }
        #expect(audio == 3)
        var detail: String?
        try store.db.query("SELECT detail FROM files") { detail = $0.text(0) }
        #expect(detail?.contains("synthetic frame decoder context") == true)
        #expect(try indexer.sync([files]).queued.count == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: FakeEmbedder.vector(for: "recovered frame"), error: nil) } }
        #expect(try indexer.run()["done"] == 1)
        #expect(try store.counts().vectors == audio + frames + 1)
        #expect(embedder.batchSizes.filter { $0 > 0 } == [3])
    }

    func makeMovie(to movie: URL, sound: URL) async throws {
        let silent = folder.appendingPathComponent("silent.mov")
        let writer = try AVAssetWriter(outputURL: silent, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 320,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 320,
        ])
        writer.add(input); #expect(writer.startWriting()); writer.startSession(atSourceTime: .zero)
        for n in 0...6 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            #expect(CVPixelBufferCreate(kCFAllocatorDefault, 320, 320, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
            let pixels = try #require(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            let base = try #require(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixels)
            for y in 0..<320 { for x in 0..<320 {
                let i = y * stride + x * 4
                base[i] = 255; base[i + 1] = y < 160 ? 255 : 0
                base[i + 2] = x < 160 ? 255 : 0; base[i + 3] = n % 2 == 0 ? 40 : 220
            } }
            CVPixelBufferUnlockBaseAddress(pixels, [])
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(seconds: Double(n), preferredTimescale: 600)))
        }
        input.markAsFinished(); await writer.finishWriting()
        #expect(writer.status == .completed)
        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: silent), audioAsset = AVURLAsset(url: sound)
        let range = CMTimeRange(start: .zero, duration: CMTime(seconds: 6, preferredTimescale: 600))
        let videoTracks = try await videoAsset.loadTracks(withMediaType: .video)
        let audioTracks = try await audioAsset.loadTracks(withMediaType: .audio)
        let videoTrack = try #require(videoTracks.first)
        let audioTrack = try #require(audioTracks.first)
        try composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: videoTrack, at: .zero)
        try composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)?
            .insertTimeRange(range, of: audioTrack, at: .zero)
        let exporter = try #require(AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough))
        if #available(macOS 15, *) {
            try await exporter.export(to: movie, as: .mov)
        } else {
            exporter.outputURL = movie; exporter.outputFileType = .mov
            await exporter.export()
            #expect(exporter.status == .completed)
        }
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
