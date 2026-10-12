import Foundation
import Testing
@testable import DigUpApp

struct LocalizedStatusTests {
    func loc(_ language: String, region: String = "en_US") -> Localization {
        Localization(bundle: Localization.current.bundle, preferredLanguages: [language],
                     formattingLocale: Locale(identifier: region))
    }
    @Test func pluralCountsAndReorderedParameters() {
        let en = loc("en"), zh = loc("zh-Hans")
        #expect(en.waitingFiles(0, reason: nil) == "0 files waiting to be indexed")
        #expect(en.waitingFiles(1, reason: nil) == "1 file waiting to be indexed")
        #expect(en.waitingFiles(2, reason: "Power") == "2 files waiting · Power")
        #expect(zh.waitingFiles(2, reason: "电源") == "2 个文件等待处理 · 电源")
        #expect(zh.indexingProgress(done: 1, total: 2).contains("1"))
        #expect(zh.indexingProgress(done: 1, total: 2).contains("2"))
        #expect(zh.format("status.progress.fraction", fallback: "%1$lld of %2$lld", Int64(1), Int64(2)) == "共 2 个，已处理 1 个")
        for count in [0, 1, 2, 12345] {
            let rendered = String(format: "%lld", locale: en.formattingLocale, Int64(count))
            #expect(en.filesCount(count).contains(rendered))
            #expect(en.filesCount(count).hasSuffix(count == 1 ? "file" : "files"))
        }
    }
    @Test func languageAndRegionAreIndependent() {
        let zh = loc("zh-Hans", region: "de_DE")
        #expect(zh.language == "zh-Hans")
        #expect(zh.durationEstimate(5400) == "1,5 小时")
        #expect(zh.durationEstimate(60) == "60 秒")
        #expect(loc("en").durationEstimate(120) == "2 min")
        #expect(zh.indexingProgress(done: 1, total: 2).hasPrefix("正在索引"))
    }
    @Test func knownErrorsHaveLocalizedContext() {
        let zh = loc("zh-Hans")
        #expect(zh.text("error.index.open", fallback: "Can't open the index") == "无法打开索引")
        let raw = "Synthetic failure: 100% /tmp/「合同」"
        #expect(zh.downloadFailure(raw) == "下载失败：" + raw)
    }
}
