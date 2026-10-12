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

    @Test func settingsAndOnboardingCopyCovered() {
        let keys = [
            "settings.tab.general",
            "settings.tab.folders",
            "settings.tab.storage",
            "settings.shortcut.title",
            "settings.shortcut.detail",
            "settings.login.title",
            "settings.login.detail",
            "settings.update.auto",
            "settings.update.now",
            "settings.folders.empty",
            "settings.folders.title",
            "common.addFolders",
            "settings.folders.searchAgain",
            "settings.exclusions.empty",
            "settings.exclusions.folders",
            "common.skip",
            "settings.exclusions.addFolder",
            "settings.exclusions.types",
            "common.remove",
            "settings.extensions.title",
            "settings.extensions.example",
            "common.resume",
            "common.pause",
            "folder.disconnected",
            "folder.noAccess",
            "folder.allowSettings",
            "folder.kept",
            "folder.stopSearching",
            "storage.model",
            "storage.status",
            "storage.downloaded",
            "common.download",
            "storage.location",
            "storage.index",
            "storage.size",
            "storage.codeIndex",
            "storage.privacy",
            "code.folders.empty",
            "code.folders.title",
            "code.open.detail",
            "code.disable.button",
            "code.disable.confirm",
            "code.disable.action",
            "folders.code.window",
            "folders.add.window",
            "folders.add.title",
            "folders.chooseAnother",
            "common.cancel",
            "common.add",
            "folders.checkToAdd",
            "folders.looking",
            "folders.hideChildren",
            "folders.chooseChildren",
            "folders.inspectFailed",
            "folders.permissionDenied",
            "folders.noCode",
            "folders.empty",
            "folders.selectedEmpty",
            "settings.battery.title",
            "settings.battery.detail",
            "folders.picker.message",
            "folders.picker.choose",
            "code.defaultApp",
            "onboarding.window",
            "common.back",
            "onboarding.start",
            "common.continue",
            "common.done",
            "onboarding.checkCode",
            "onboarding.lookingCode",
            "onboarding.chooseOne",
            "onboarding.lookingFolders",
            "onboarding.modelReady",
            "common.retry",
            "onboarding.modelMissing",
            "onboarding.example.image",
            "onboarding.example.document",
            "onboarding.example.media",
            "onboarding.folders.title",
            "common.addFolder",
            "onboarding.fileTypes",
            "onboarding.skipSummary",
            "onboarding.skipTitle",
            "onboarding.code.title",
            "onboarding.code.enable",
            "onboarding.code.optIn",
            "code.openIn",
            "onboarding.shortcut.title",
            "onboarding.shortcut.detail",
            "onboarding.shortcut.ready",
            "onboarding.shortcuts.heading",
            "onboarding.tip.open",
            "onboarding.tip.reveal",
            "onboarding.tip.quickLook",
            "onboarding.tip.copy",
            "onboarding.ready.title",
            "onboarding.ready.menubar",
            "settings.update.detail",
            "settings.types.detail",
            "storage.privacy.detail",
            "settings.code.description",
            "settings.code.privacy",
            "folders.add.codeDetail",
            "folders.add.detail",
            "folders.code.note",
            "folders.estimate.laterHelp",
            "folders.estimate.codeHelp",
            "onboarding.privacy",
            "onboarding.folders.detail",
            "onboarding.permissions",
            "onboarding.code.detail"
        ]
        for language in ["en", "zh-Hans"] {
            let l = Localization(bundle: Localization.current.bundle, preferredLanguages: [language],
                                 formattingLocale: Locale(identifier: "en_US"))
            for key in keys { #expect(l.text(key, fallback: "__MISSING__") != "__MISSING__") }
        }
    }

}
