import AppKit
import Foundation
import Testing
@testable import DigUpKit

@Suite final class ChineseSearchTests {
    let folder: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = caches.appendingPathComponent("DigUpChineseTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    deinit { try? FileManager.default.removeItem(at: folder) }

    @discardableResult
    func add(_ store: IndexStore, path: String, body: String? = nil, inode: UInt64 = 1) throws -> Int64 {
        let id = try store.insert(Candidate(path: path, kind: .doc, size: 1, mtime: 1, inode: inode, device: 1))
        if let body { try store.addSegment(file: id, kind: .chunk, modality: .text, loc: 1, text: body) }
        return id
    }

    @Test func chineseLexicalEvalOnPublicSyntheticCorpus() throws {
        // Each case has its own index, so a keyword-only R@1 has one unambiguous answer.
        let cases: [(query: String, name: String, body: String?)] = [
            ("租房", "notes.txt", "这是一份关于租房费用的公开合成记录"),
            ("发票", "notes.txt", "本月发票金额已记录在公开合成表格中"),
            ("预算", "notes.txt", "年度预算安排来自公开合成资料"),
            ("北京", "notes.txt", "我们计划乘坐高铁前往北京游览"),
            ("高铁", "notes.txt", "乘坐高铁前往南方旅行"),
            ("苹果", "notes.txt", "桌上放着新鲜苹果和香蕉"),
            ("𠮷野", "notes.txt", "公开合成记录中的𠮷野家店铺"),
            ("合同", "年度租赁合同扫描备份.pdf", nil),
            ("voice", "myVoiceMemo2026.txt", nil),
            ("payment error", "notes.txt", "A payment error appeared on the synthetic receipt."),
        ]
        var correct = 0
        for (index, item) in cases.enumerated() {
            let store = try IndexStore(directory: folder.appendingPathComponent("eval-\(index)"))
            let path = "/synthetic/\(item.name)"
            try add(store, path: path, body: item.body)
            let hits = try Searcher(store: store, loadVectors: false).search(item.query, queryVector: nil)
            if hits.first?.path == path { correct += 1 }
            #expect(hits.first?.path == path, "Keyword-only synthetic case: \(item.query)")
        }
        print("CHINESE_LEXICAL_EVAL keyword-only R@1: \(correct)/\(cases.count); no model inference")
    }

    @Test func chinesePhrasesAreContiguousAndHighlightedAsWritten() throws {
        let store = try IndexStore(directory: folder.appendingPathComponent("phrases"))
        try add(store, path: "/synthetic/good.txt", body: "租房合同已经签署", inode: 1)
        try add(store, path: "/synthetic/bad.txt", body: "租赁住房合同", inode: 2)
        let hits = try Searcher(store: store, loadVectors: false).search("租房", queryVector: nil)
        #expect(hits.map(\.path) == ["/synthetic/good.txt"])
        #expect(hits.first?.excerpt?.contains("«租房»合同") == true)
        #expect(Landmark.find(page: 2, texts: ["公开资料", "这份租房合同已签署"], words: ["合同"]) == "合同")
        #expect(SearchText.matches(of: "day", in: "Sunday day").map { String("Sunday day"[$0]) } == ["day"])
    }

    @Test func filenameInteriorMatchingDoesNotScanFoldersOrBodies() throws {
        let store = try IndexStore(directory: folder.appendingPathComponent("filenames"))
        let id = try add(store, path: "/synthetic/myVoiceMemo.txt", inode: 1)
        try add(store, path: "/synthetic/myVoiceMemo/ordinary.txt", body: "invoicevoicecode", inode: 2)
        var searcher = try Searcher(store: store, loadVectors: false)
        #expect(try searcher.search("voice", queryVector: nil).map(\.path) == ["/synthetic/myVoiceMemo.txt"])
        #expect(try searcher.search("vo", queryVector: nil).isEmpty) // Latin interior fallback requires >= 3.
        #expect(try searcher.search("voice", queryVector: nil, kinds: [.image]).isEmpty)
        try store.move(id, to: "/synthetic/renamed.txt")
        searcher = try Searcher(store: store, loadVectors: false)
        #expect(try searcher.search("voice", queryVector: nil).isEmpty)
        try store.delete(id)
        #expect(try Searcher(store: store, loadVectors: false).search("renamed", queryVector: nil).isEmpty)
    }

    @Test func chineseChunksRetainOverlapWithoutWhitespace() {
        let text = String(repeating: "甲", count: 499) + "租房合同" + String(repeating: "乙", count: 1100) + "尾部标记"
        let chunks = DocExtractor.chunks(text, size: 500, overlap: 100, limit: 100)
        #expect(chunks.count > 2)
        #expect(chunks.allSatisfy { $0.count <= 500 })
        #expect(chunks[1].prefix(100) == chunks[0].suffix(100))
        #expect(chunks.contains { $0.contains("租房合同") }) // phrase spans the first hard boundary.
        #expect(chunks.last?.hasSuffix("尾部标记") == true)
    }

    @Test func hanPhrasesDoNotBridgeSourceSeparatorsOrChooseTheWrongPage() throws {
        let store = try IndexStore(directory: folder.appendingPathComponent("separators"))
        let id = try add(store, path: "/synthetic/pages.pdf")
        try store.addSegment(file: id, kind: .page, modality: .text, loc: 1, text: "租，房 租。房 租\n房")
        let searcher = try Searcher(store: store, loadVectors: false)
        #expect(try searcher.search("租房", queryVector: nil).isEmpty)
        try store.addSegment(file: id, kind: .page, modality: .text, loc: 2, text: "租房合同已经签署")
        let hits = try Searcher(store: store, loadVectors: false).search("租房", queryVector: nil)
        #expect(hits.first?.loc == 2)
        #expect(hits.first?.excerpt?.contains("«租房»") == true)
    }

    @Test func filenameKindConstraintIsAppliedBeforeTheCandidateCap() throws {
        let store = try IndexStore(directory: folder.appendingPathComponent("many-filenames"))
        for number in 1...110 {
            try add(store, path: "/synthetic/myVoiceMemo\(number).txt", inode: UInt64(number))
        }
        let path = "/synthetic/myVoiceMemoImage.png"
        try store.insert(Candidate(path: path, kind: .image, size: 1, mtime: 1, inode: 200, device: 1))
        let hits = try Searcher(store: store, loadVectors: false).search("voice", queryVector: nil, kinds: [.image])
        #expect(hits.map(\.path) == [path])
    }

    @Test func schemaFiveKeepsStoredTextSearchableAfterUpgrade() throws {
        let directory = folder.appendingPathComponent("migration")
        var store: IndexStore? = try IndexStore(directory: directory)
        let id = try add(store!, path: "/synthetic/年度合同备份.txt", body: "连续中文租房记录", inode: 1)
        // Model the old unsplit word representation, retaining its original text.
        try store!.db.run("UPDATE fts SET name = '年度合同备份.txt' WHERE rowid IN (SELECT id FROM segments WHERE kind = 'name')")
        try store!.db.run("UPDATE fts SET body = '连续中文租房记录', original = NULL WHERE rowid IN (SELECT id FROM segments WHERE kind = 'chunk')")
        try store!.finish(id, state: "done", detail: nil)
        try store!.db.execute("PRAGMA user_version = 5")
        store = nil
        let reopened = try IndexStore(directory: directory)
        let searcher = try Searcher(store: reopened, loadVectors: false)
        #expect(try searcher.search("租房", queryVector: nil).map(\.path) == ["/synthetic/年度合同备份.txt"])
        #expect(try searcher.search("合同", queryVector: nil).map(\.path) == ["/synthetic/年度合同备份.txt"])
    }

    @Test func pdfTailIsEmbeddedAndKeepsTheOriginalPageNumber() throws {
        let files = folder.appendingPathComponent("files")
        try FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let url = files.appendingPathComponent("synthetic-long-page.pdf")
        var box = CGRect(x: 0, y: 0, width: 1600, height: 6000)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        let long = String(repeating: "这是一段公开合成的中文资料。", count: 600) + "尾部检索标记"
        for text in [String(repeating: "First synthetic page. ", count: 20), long] {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            (text as NSString).draw(in: CGRect(x: 60, y: 60, width: 1480, height: 5800),
                                    withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        context.closePDF()
        let store = try IndexStore(directory: folder.appendingPathComponent("pdf-index"))
        let embedder = FakeEmbedder()
        let indexer = try Indexer(store: store, options: IndexOptions(), makeEmbedder: { embedder })
        _ = try indexer.sync([files])
        #expect(try indexer.run()["done"] == 1)
        #expect(embedder.textInputs.contains { $0.contains("尾部检索标记") })
        let hits = try Searcher(store: store, loadVectors: false).search("标记", queryVector: nil)
        #expect(hits.first?.path == url.path)
        #expect(hits.first?.loc == 2)
    }

    @Test func testingModelDirectoryIsSeparateFromTheOriginalApp() {
        #expect(ModelFiles.installed.path.contains("/DigUpTest/Models"))
        #expect(!ModelFiles.installed.path.contains("/DigUp/Models"))
    }
}
