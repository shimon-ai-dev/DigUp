import AppKit
import Foundation
import Testing
@testable import DigUpKit
@testable import DigUpApp

@MainActor struct LocalizationUITests {
    @Test func menuActionsIgnoreTranslatedTitles() {
        let menu = NSMenu()
        var paused = 0, resumed = 0
        let pause = ActionMenuItem("暂停索引", id: .pauseIndexing) { paused += 1 }
        let resume = ActionMenuItem("继续索引", id: .resumeIndexing) { resumed += 1 }
        menu.addItem(pause)
        menu.addItem(resume)
        MenuActionID.pauseIndexing.perform(in: menu)
        MenuActionID.resumeIndexing.perform(in: menu)
        #expect(paused == 1 && resumed == 1)
        #expect(pause.identifier?.rawValue == "pauseIndexing")
    }
    @Test func hotkeySpecsStayStable() throws {
        let combo = try #require(KeyCombo("cmd+shift+space"))
        #expect(combo.spec == "shift+cmd+space")
        #expect(combo.caps.last == "Space")
        let equivalent = try #require(combo.menuEquivalent)
        #expect(equivalent.0 == " ")
        #expect(equivalent.1 == [.command, .shift])
    }
    @Test func resultContentIsVerbatim() {
        let path = "/synthetic/100%「合同」.md", content = "100% «合同» 原文"
        let hit = SearchHit(path: path, kind: .doc, score: 1, z: nil, cosine: nil, keywordRank: 1,
                            segment: .chunk, segmentID: 1, loc: nil, locEnd: nil, excerpt: content,
                            modified: 0, size: 100, info: [:])
        let row = ResultRow(hit)
        #expect(row.id == path)
        #expect(row.name == "100%「合同」.md")
        #expect(row.title == "\u{200E}100%「合同」.md")
        #expect(row.excerpt == content)
    }
    @Test func menuAndSearchResourcesCovered() {
        let keys = ["menu.pause", "menu.resume", "menu.settings", "search.placeholder.panel",
                    "search.empty.title", "search.weaker.expand", "preview.playFrom", "result.openAt"]
        for language in ["en", "zh-Hans"] {
            let l = Localization(bundle: Localization.current.bundle, preferredLanguages: [language],
                                 formattingLocale: Locale(identifier: "en_US"))
            for key in keys { #expect(l.text(key, fallback: "__MISSING__") != "__MISSING__") }
        }
    }

}
