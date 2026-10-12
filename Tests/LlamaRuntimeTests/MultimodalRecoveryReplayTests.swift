@testable import DigUpKit
import Foundation
import Testing

/// Compatibility replay of prior full-model photo, screenshot, video, long-audio and Chinese-speech probes.
/// Preserves their real text distractors, exact single-query vectors and segment locations; no new media inference.
struct MultimodalRecoveryReplayTests {
    struct Corpus: Decodable {
        struct Segment: Decodable {
            let kind: String; let modality: String; let loc: Double?; let loc_end: Double?
            let excerpt: String?; let text: String?; let vector: Data?
        }
        struct File: Decodable { let name: String; let kind: FileKind; let segments: [Segment] }
        struct Query: Decodable {
            let id: String; let query: String; let phase: String; let kind: FileKind; let expected: String
            let vector: Data; let segment: String; let loc: Double?; let loc_end: Double?
            let original_cosine: Double; let original_z: Double; let original_strong: Bool
        }
        let baseline: [File]; let phases: [String: [File]]; let queries: [Query]
    }

    @Test func priorStrongMultimodalHitsAndLocationsRemainUnchanged() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("MediaRecovery/public-multimodal-vectors.json")
        let corpus = try JSONDecoder().decode(Corpus.self, from: Data(contentsOf: source))
        #expect(corpus.baseline.count == 22 && corpus.queries.count == 12)
        #expect(corpus.queries.filter(\.original_strong).count == 10)
        for (phase, files) in corpus.phases {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("DigUpTest-multimodal-replay-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let store = try IndexStore(directory: directory)
            for (n, file) in (corpus.baseline + files).enumerated() {
                let id = try store.insert(Candidate(path: "/public-synthetic/\(file.name)", kind: file.kind,
                                                   size: 1, mtime: 1, inode: UInt64(n + 1), device: 1))
                for segment in file.segments {
                    let kind = try #require(SegmentKind(rawValue: segment.kind))
                    let modality = try #require(Modality(rawValue: segment.modality))
                    var vector: [Float]?
                    if let data = segment.vector {
                        try #require(Vectors.validHalf(data))
                        vector = data.withUnsafeBytes { bytes in
                            (0..<768).map { Float(bytes.loadUnaligned(fromByteOffset: $0 * 2, as: Float16.self)) }
                        }
                    }
                    try store.addSegment(file: id, kind: kind, modality: modality, loc: segment.loc,
                                         locEnd: segment.loc_end, excerpt: segment.excerpt,
                                         text: segment.text, vector: vector)
                }
            }
            let searcher = try Searcher(store: store)
            for query in corpus.queries where query.phase == phase {
                try #require(query.vector.count == 768 * 4)
                let vector = query.vector.withUnsafeBytes { bytes in
                    (0..<768).map { bytes.loadUnaligned(fromByteOffset: $0 * 4, as: Float.self) }
                }
                try #require(Vectors.valid(vector))
                let filtered = try searcher.search(query.query, queryVector: vector, kinds: [query.kind])
                let all = try searcher.search(query.query, queryVector: vector)
                let target = "/public-synthetic/\(query.expected)"
                if query.original_strong {
                    let hit = try #require(filtered.first)
                    #expect(hit.path == target && !hit.isSuggestion)
                    #expect(abs((hit.cosine ?? -1) - query.original_cosine) < 0.000001)
                    #expect(abs((hit.z ?? -1) - query.original_z) < 0.00001)
                    #expect(hit.segment.rawValue == query.segment && hit.loc == query.loc && hit.locEnd == query.loc_end)
                    let allHit = try #require(all.first { $0.path == target })
                    #expect(!allHit.isSuggestion && allHit.segment == hit.segment)
                    #expect(allHit.loc == hit.loc && allHit.locEnd == hit.locEnd)
                } else if query.id == "zh-chinese-speech-shopping" {
                    let hit = try #require(filtered.first)
                    #expect(hit.path == target && hit.isSuggestion)
                    #expect(hit.segment == .audio && hit.loc == query.loc && hit.locEnd == query.loc_end)
                    #expect(all.first { $0.path == target }?.isSuggestion == true)
                } else {
                    // The English query's Chinese-speech cosine (~0.594) is below the empirical safeguard.
                    #expect(query.id == "en-chinese-speech-shopping" && filtered.isEmpty)
                    #expect(!all.contains { $0.path == target })
                }
                print("MEDIA_MULTIMODAL_REPLAY \(query.id): original_strong=\(query.original_strong) filtered=\(filtered.first?.path ?? "empty") suggestion=\(filtered.first?.isSuggestion ?? false)")
            }
        }
    }
}
