@testable import DigUpKit
import Foundation
import Testing
@testable import LlamaRuntime

/// Replays genuine full-model vectors from public macOS-generated speech. New queries are encoded by the pinned
/// text model, so four same-kind distractors and no-match controls can be checked without repeating media inference.
@Suite(.serialized) struct MediaRecoveryTests {
    struct Corpus: Decodable {
        struct Media: Decodable { let name: String; let vector: [Float] }
        struct Query: Decodable { let query: String; let expected: String; let vector: [Float] }
        let media: [Media]
        let queries: [Query]
    }
    static let textModelPresent = (try? LlamaModels.locate()) != nil
    static let helperPresent = ProcessInfo.processInfo.environment["DIGUP_TEST_HELPER"]
        .map { FileManager.default.isExecutableFile(atPath: $0) } ?? false
    static let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("MediaRecovery/public-audio-vectors.json")

    @Test func publicAudioReplayExposesPreviouslySuppressedAnswers() throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: Self.source))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-real-recovery-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try IndexStore(directory: directory)
        for (n, media) in corpus.media.enumerated() {
            let id = try store.insert(Candidate(path: "/public-synthetic/\(media.name)", kind: .audio,
                                               size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
            try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 0, locEnd: 6, vector: media.vector)
        }
        let searcher = try Searcher(store: store)
        let filters: [Set<FileKind>?] = [nil, [.audio]]
        for query in corpus.queries {
            for kinds in filters {
                let hits = try searcher.search(query.query, queryVector: query.vector, kinds: kinds)
                #expect(hits.first?.path == "/public-synthetic/\(query.expected)")
                #expect(Searcher.strongCount(hits) == 0)
                print("MEDIA_RECOVERY_REPLAY \(query.query): \(hits.first?.path ?? "empty") cosine=\(hits.first?.cosine ?? -1) z=\(hits.first?.z ?? -1)")
            }
        }
    }

    @Test(.enabled(if: textModelPresent && helperPresent)) func actualCLIJsonMarksRecoveredAudioAsLowConfidence() throws {
        guard let helper = ProcessInfo.processInfo.environment["DIGUP_TEST_HELPER"] else {
            throw CocoaError(.fileNoSuchFile)   // Acceptance CI must build the actual helper before running tests.
        }
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: Self.source))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-real-json-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try IndexStore(directory: directory)
        for (n, media) in corpus.media.enumerated() {
            let id = try store.insert(Candidate(path: "/public-synthetic/\(media.name)", kind: .audio,
                                               size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
            try store.addSegment(file: id, kind: .audio, modality: .audio, loc: 0, locEnd: 6, vector: media.vector)
        }
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: helper)
        process.arguments = ["search", "baking a chocolate cake", "--index", directory.path, "--kind", "audio", "--json"]
        process.environment = ProcessInfo.processInfo.environment
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let stderr = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, String(data: stderr, encoding: .utf8) ?? "CLI failed")
        let rows = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rows.first?["path"] as? String == "/public-synthetic/f004.wav")
        #expect(rows.first?["is_suggestion"] as? Bool == true)
        #expect(rows.first?["match_type"] as? String == "low_confidence_suggestion")
        #expect(rows.first?["segment"] as? String == "audio")
        #expect(rows.first?["loc"] as? Double == 0)
        #expect(rows.first?["loc_end"] as? Double == 6)
        print("MEDIA_RECOVERY_CLI_JSON real helper: low_confidence_suggestion, audio timestamp retained")
    }

    @Test func mixedCorpusKeepsRecoveredAudioBelowExistingMatches() throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: Self.source))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-real-mixed-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try IndexStore(directory: directory)
        for (n, media) in corpus.media.enumerated() {
            let id = try store.insert(Candidate(path: "/public-synthetic/\(media.name)", kind: .audio,
                                               size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
            try store.addSegment(file: id, kind: .audio, modality: .audio, vector: media.vector)
        }
        // Real same-kind speech distractors plus unrelated synthetic text/image vectors.
        // This exercises All-mode normalization across modalities without extra media inference.
        for n in 0..<8 {
            let kind: FileKind = n % 2 == 0 ? .doc : .image
            let id = try store.insert(Candidate(path: "/public-synthetic/distractor\(n)", kind: kind,
                                               size: 1, mtime: 1, inode: UInt64(n + 20), device: 1))
            var vector = [Float](repeating: 0, count: 768); vector[n + 50] = 1
            try store.addSegment(file: id, kind: kind == .doc ? .chunk : .image,
                                 modality: kind == .doc ? .text : .image, vector: vector)
        }
        let searcher = try Searcher(store: store)
        for query in corpus.queries {
            let hits = try searcher.search(query.query, queryVector: query.vector)
            #expect(hits.first?.path == "/public-synthetic/\(query.expected)")
            #expect(hits.allSatisfy { $0.kind == .audio })
            #expect(try searcher.search(query.query, queryVector: query.vector, kinds: [.image]).isEmpty)
        }
    }

    @Test(.enabled(if: textModelPresent)) func nativeNoMatchQueriesKeepPublicAudioEmpty() throws {
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: Self.source))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DigUpTest-real-negative-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try IndexStore(directory: directory)
        for (n, media) in corpus.media.enumerated() {
            let id = try store.insert(Candidate(path: "/public-synthetic/\(media.name)", kind: .audio,
                                               size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
            try store.addSegment(file: id, kind: .audio, modality: .audio, vector: media.vector)
        }
        let searcher = try Searcher(store: store)
        let embedder = try LlamaEmbedder(models: LlamaModels.locate(), textOnly: true)
        defer { embedder.close() }
        let queries = ["volcanic rocks on the lunar surface", "火山岩与月球表面的地质结构",
                       "a violin concerto played by a string orchestra", "弦乐团演奏小提琴协奏曲",
                       "replace a broken bicycle tire", "修补自行车轮胎"]
        // Preserve raw no-match scores, not only pass/fail, for empirical threshold review.
        for query in queries {
            let vector = try #require(embedder.embedTexts([Prompts.query(query)]).first)
            let raw = try searcher.search(query, queryVector: vector, zGate: -1_000_000, wordWeight: 0)
            print("MEDIA_RECOVERY_NEGATIVE \(query): \(raw.map { ($0.path as NSString).lastPathComponent + "=" + String(format: "%.4f", $0.cosine ?? -1) }.joined(separator: ","))")
            #expect(try searcher.search(query, queryVector: vector).isEmpty)
            #expect(try searcher.search(query, queryVector: vector, kinds: [.audio]).isEmpty)
        }
    }
}
