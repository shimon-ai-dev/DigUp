import Foundation
import Testing
@testable import DigUpApp

struct LocalizationTests {
    func loc(_ language: String, region: String = "en_US") -> Localization {
        Localization(bundle: Localization.current.bundle, preferredLanguages: [language], formattingLocale: Locale(identifier: region))
    }
    @Test func languageSelectionAndFallback() {
        #expect(loc("zh-Hans-CN").language == "zh-Hans")
        #expect(loc("en").language == "en")
        #expect(loc("ja").language == "en")
        #expect(loc("zh-Hans").text("common.cancel", fallback: "Cancel") == "取消")
        #expect(loc("ja").text("common.cancel", fallback: "Cancel") == "Cancel")
        #expect(loc("zh-Hans").text("missing.key", fallback: "Safe English") == "Safe English")
    }
    @Test func missingTranslationFallsBackPerKey() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: root) }
        for lang in ["en", "zh-Hans"] {
            let d = root.appendingPathComponent(lang + ".lproj")
            try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            let value = lang == "en" ? "\"test.key\" = \"English table\";" : "\"another.key\" = \"中文\";"
            try value.write(to: d.appendingPathComponent("Localizable.strings"), atomically: true, encoding: .utf8)
        }
        let b = try #require(Bundle(url: root))
        let l = Localization(bundle: b, preferredLanguages: ["zh-Hans"], formattingLocale: Locale(identifier: "en_US"))
        #expect(l.text("test.key", fallback: "Fallback") == "English table")
    }
    @Test func pluralCountsAndUntrustedArguments() {
        #expect(loc("en").resultsCount(1) == "1 result")
        #expect(loc("en").resultsCount(2) == "2 results")
        #expect(loc("en").resultsCount(0) == "0 results")
        #expect(loc("zh-Hans").resultsCount(2) == "2 个结果")
        let name = "100%「合同」.md"
        #expect(loc("zh-Hans").format("test.unknown", fallback: "%@", name) == name)
    }
    @Test(arguments: ["app", "APP", "bundle"])
    func packagedAppMissingResourcesDoesNotFallBackToBuildDirectory(suffix: String) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + suffix)
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "synthetic.localization.missing", "CFBundlePackageType": "APPL"], format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let app = try #require(Bundle(url: root))
        #expect(throws: (any Error).self) { try Localization.resourceBundle(appBundle: app) }
    }

}
