import Foundation
import Testing
@testable import DigUpKit

/// Old audio/video indexing zipped partial replies, saved nil-vector rows, then incorrectly marked the file done.
/// Reconcile only deterministic missing-vector/count evidence, never guessed silence or duration-based tail gaps.
@Suite(.serialized) final class LegacyMediaRecoveryTests {
    let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DigUpTest-legacy-media-\(UUID().uuidString)")
    deinit { try? FileManager.default.removeItem(at: folder) }

    func store(_ name: String = IndexStore.mainFile) throws -> IndexStore {
        try IndexStore(directory: folder, file: name)
    }
    func file(_ store: IndexStore, _ name: String, kind: FileKind, inode: UInt64 = 1) throws -> Int64 {
        try store.insert(Candidate(path: name, kind: kind, size: 1, mtime: 1, inode: inode, device: 1))
    }
    func state(_ store: IndexStore, _ id: Int64) throws -> String? {
        var state: String?
        try store.db.query("SELECT state FROM files WHERE id = ?", [.int(id)]) { state = $0.text(0) }
        return state
    }

    @Test func unchangedLegacyNilAudioBecomesVisibleButWaitsForExplicitRetry() throws {
        let fixture = MediaEmbeddingFailureTests(), embedder = MediaFailureEmbedder()
        defer { withExtendedLifetime(fixture) {} }
        let (store, indexer, files) = try fixture.setup(embedder)
        let id = try #require(store.files(under: [files.path]).first?.id)
        let good = FakeEmbedder.vector(for: "already encoded")
        try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 0, locEnd: 2, vector: good)
        try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 2, locEnd: 4)
        try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 4, locEnd: 6, vector: good)
        try store.finish(id, state: "done", info: ["duration": "6.0"])
        var previous: [Int64] = []
        try store.db.query("SELECT id FROM segments WHERE file = ? AND vec IS NOT NULL", [.int(id)]) {
            previous.append($0.int(0))
        }
        #expect(try indexer.sync([files]).queued.isEmpty)
        #expect(try state(store, id) == "failed")
        #expect(try store.info(of: id)["media_legacy_incomplete"] == "1")
        var detail: String?
        try store.db.query("SELECT detail FROM files WHERE id = ?", [.int(id)]) { detail = $0.text(0) }
        #expect(detail?.contains("legacy") == true && detail?.contains("audio") == true)
        #expect(try indexer.sync([files]).queued.isEmpty)
        #expect(try indexer.run().isEmpty)
        #expect(try store.counts().vectors == 2)
        store.scope = [files.path]
        #expect(try store.retryFailedMedia() == 1)
        embedder.reply = { $0.map { _ in Embedding(vector: FakeEmbedder.vector(for: "recovered"), error: nil) } }
        #expect(try indexer.run()["done"] == 1)
        #expect(embedder.batchSizes == [1])
        #expect(try store.counts().vectors == 3)
        var retained: [Int64] = []
        try store.db.query("SELECT id FROM segments WHERE file = ? AND id IN (\(previous.map(String.init).joined(separator: ",")))", [.int(id)]) {
            retained.append($0.int(0))
        }
        #expect(retained == previous)
        #expect(try indexer.sync([files]).queued.isEmpty)
    }

    @Test func doneAudioWithoutAnyAudioRowsIsRetryable() throws {
        let store = try store()
        let id = try file(store, "/connected/empty.wav", kind: .audio)
        try store.finish(id, state: "done", info: ["duration": "6.0"])
        store.scope = ["/connected"]
        #expect(try store.retryFailedMedia() == 1)
        #expect(try state(store, id) == "pending")
        #expect(try store.info(of: id)["media_legacy_incomplete"] == "1")
        #expect(try store.retryFailedMedia() == 0)
    }

    @Test func nilVideoFrameAndDeclaredResponseGapsAreRetryableWithoutDroppingSound() throws {
        let store = try store()
        let nilFrame = try file(store, "/connected/nil-frame.mov", kind: .video)
        try store.addSegment(file: nilFrame, kind: .frame, modality: .image, loc: 0, locEnd: 6)
        try store.addSegment(file: nilFrame, kind: .audio, modality: .audio, loc: 0, locEnd: 6,
                             vector: FakeEmbedder.vector(for: "sound"))
        try store.finish(nilFrame, state: "done", info: ["frames": "1", "sound_windows": "1"])
        let missingFrame = try file(store, "/connected/missing-frame.mov", kind: .video, inode: 2)
        try store.addSegment(file: missingFrame, kind: .frame, modality: .image, loc: 0, locEnd: 6,
                             vector: FakeEmbedder.vector(for: "frame"))
        try store.finish(missingFrame, state: "done", info: ["frames": "2", "sound_windows": "0"])
        let missingSound = try file(store, "/connected/missing-sound.mov", kind: .video, inode: 3)
        try store.addSegment(file: missingSound, kind: .frame, modality: .image, loc: 0, locEnd: 6,
                             vector: FakeEmbedder.vector(for: "frame"))
        try store.finish(missingSound, state: "done", info: ["frames": "1", "sound_windows": "2"])
        store.scope = ["/connected"]
        #expect(try store.retryFailedMedia() == 3)
        #expect(try store.counts().vectors == 3)
        for id in [nilFrame, missingFrame, missingSound] {
            #expect(try state(store, id) == "pending")
            #expect(try store.info(of: id)["media_legacy_incomplete"] == "1")
        }
    }

    @Test func healthyAndExplicitlySilentMediaAreNotReindexedFromDuration() throws {
        let store = try store()
        let audio = try file(store, "/connected/sparse-speech.wav", kind: .audio)
        try store.addSegment(file: audio, kind: .audio, modality: .audio, loc: 0, locEnd: 30,
                             vector: FakeEmbedder.vector(for: "speech before silence"))
        try store.finish(audio, state: "done", info: ["duration": "90.0"])
        let video = try file(store, "/connected/silent-video.mov", kind: .video, inode: 2)
        try store.addSegment(file: video, kind: .frame, modality: .image, loc: 0, locEnd: 90,
                             vector: FakeEmbedder.vector(for: "frame"))
        try store.finish(video, state: "done", info: ["frames": "1", "sound_windows": "0", "duration": "90.0"])
        let silent = try file(store, "/connected/silent.wav", kind: .audio, inode: 3)
        try store.finish(silent, state: "skipped", detail: "silent or too short")
        let explicitZero = try file(store, "/connected/declared-zero.wav", kind: .audio, inode: 4)
        try store.finish(explicitZero, state: "done", info: ["sound_windows": "0", "duration": "90.0"])
        store.scope = ["/connected"]
        #expect(try store.retryFailedMedia() == 0)
        #expect(try state(store, audio) == "done" && state(store, video) == "done")
        #expect(try state(store, silent) == "skipped" && state(store, explicitZero) == "done")
        #expect(try store.counts().vectors == 2)
    }

    @Test func reconciliationStaysWithinConnectedSelectedScope() throws {
        let store = try store()
        let selected = try file(store, "/connected/missing.wav", kind: .audio)
        let disconnected = try file(store, "/disconnected/missing.wav", kind: .audio, inode: 2)
        let unselected = try file(store, "/unselected/missing.wav", kind: .audio, inode: 3)
        for id in [selected, disconnected, unselected] { try store.finish(id, state: "done", info: ["duration": "6.0"]) }
        store.scope = []
        #expect(try store.retryFailedMedia() == 0)
        store.scope = ["/connected"]
        #expect(try store.retryFailedMedia() == 1)
        #expect(try state(store, disconnected) == "done" && state(store, unselected) == "done")
        #expect(try store.info(of: disconnected)["media_legacy_incomplete"] == nil)
    }

    @Test func legacyRepairCannotTargetCodeIndexOrOriginalAppData() throws {
        let store = try store(IndexStore.codeFile)
        let id = try file(store, "/connected/missing.wav", kind: .audio)
        try store.finish(id, state: "done", info: ["duration": "6.0"])
        #expect(try store.retryFailedMedia() == 0)
        #expect(try state(store, id) == "done")
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp")
        #expect(throws: WorkerError.self) { _ = try IndexStore(directory: original) }
    }
}
