import Foundation
import DigUpLocalizationResources

/// Immutable app-only localization. File contents and helper protocol values never pass through this table.
nonisolated struct Localization: Sendable {
    let bundle: Bundle
    let language: String
    let formattingLocale: Locale
    private let selected: [String: String]
    private let english: [String: String]
    private let selectedPlurals: [String: [String: String]]
    private let englishPlurals: [String: [String: String]]

    static let current: Localization = {
        // Bundle.module is intentionally used only outside a packaged app. A missing packaged resource is an error.
        let resources: Bundle
        do { resources = try resourceBundle(appBundle: .main) }
        catch { fatalError("DigUp Test localization resources are missing: \(error)") }
        return Localization(bundle: resources, preferredLanguages: Locale.preferredLanguages, formattingLocale: .current)
    }()

    init(bundle: Bundle, preferredLanguages: [String], formattingLocale: Locale) {
        self.bundle = bundle
        self.formattingLocale = formattingLocale
        language = Bundle.preferredLocalizations(from: ["en", "zh-Hans"], forPreferences: preferredLanguages).first ?? "en"
        selected = Self.readTable(bundle: bundle, language: language)
        english = Self.readTable(bundle: bundle, language: "en")
        selectedPlurals = Self.readPlurals(bundle: bundle, language: language)
        englishPlurals = Self.readPlurals(bundle: bundle, language: "en")
    }

    func text(_ key: String, fallback: String) -> String { selected[key] ?? english[key] ?? fallback }
    func format(_ key: String, fallback: String, _ arguments: CVarArg...) -> String {
        String(format: text(key, fallback: fallback), locale: formattingLocale, arguments: arguments)
    }
    /// Exactly the plural rules of the supported languages: English one/other and Simplified Chinese other.
    /// Raw Int selects the form; locale formatting happens only after selection.
    func count(_ key: String, _ value: Int, one: String, other: String) -> String {
        let forms: [String: String]
        let selectedLanguage: String
        if let entry = selectedPlurals[key] { forms = entry; selectedLanguage = language }
        else { forms = englishPlurals[key] ?? [:]; selectedLanguage = "en" }
        let form = selectedLanguage == "en" && value == 1 ? "one" : "other"
        let template = forms[form] ?? forms["other"] ?? (value == 1 ? one : other)
        return String(format: template, locale: formattingLocale, arguments: [Int64(value)])
    }
    func resultsCount(_ count: Int) -> String {
        self.count("count.results", count, one: "%lld result", other: "%lld results")
    }

    func filesCount(_ value: Int) -> String {
        count("count.files", value, one: "%lld file", other: "%lld files")
    }
    func weakerCount(_ value: Int) -> String {
        count("count.weaker", value, one: "%lld weaker match", other: "%lld weaker matches")
    }
    func resultsSummary(_ strong: Int, weaker: Int, code: Bool = false) -> String {
        let total = resultsCount(strong)
        let scope = code ? format("search.results.code", fallback: "%@ in your code", total) : total
        return weaker > 0 ? format("search.results.withWeaker", fallback: "%@ · %@", scope, weakerCount(weaker)) : scope
    }

    /// Display percentage preserves the original floor behavior; locale controls spacing and number syntax.
    func percent(_ fraction: Double) -> String {
        (floor(max(0, fraction) * 100) / 100).formatted(.percent.precision(.fractionLength(0)).locale(formattingLocale))
    }
    func indexingProgress(done: Int, total: Int) -> String {
        format("status.indexing", fallback: "Indexing %@ · %lld of %lld", percent(total > 0 ? Double(done) / Double(total) : 0), Int64(done), Int64(total))
    }
    func indexingCodeProgress(done: Int, total: Int) -> String {
        format("status.indexing.code", fallback: "Indexing code %@ · %lld of %lld", percent(total > 0 ? Double(done) / Double(total) : 0), Int64(done), Int64(total))
    }
    func waitingFiles(_ value: Int, reason: String?) -> String {
        if let reason {
            let waiting = count("count.waiting", value, one: "%lld file waiting", other: "%lld files waiting")
            return format("status.waiting.reason", fallback: "%@ · %@", waiting, reason)
        }
        return count("count.waiting.index", value, one: "%lld file waiting to be indexed", other: "%lld files waiting to be indexed")
    }
    func durationEstimate(_ seconds: Double) -> String {
        switch seconds {
        case ..<90: return format("duration.seconds", fallback: "%lld s", Int64(seconds.rounded()))
        case ..<5400: return format("duration.minutes", fallback: "%lld min", Int64((seconds / 60).rounded()))
        default: return format("duration.hours", fallback: "%.1f h", seconds / 3600)
        }
    }
    /// Only for the app-owned data-directory validation boundary; unknown errors retain their diagnostic.
    func originalDataRejection() -> String {
        text("error.originalData", fallback: "DigUp Test cannot use the original DigUp data directory; choose separate testing data paths")
    }
    func downloadFailure(_ original: String) -> String {
        format("error.download.context", fallback: "Download failed: %@", original)
    }

    static let resourceBundleName = AppLocalizationResources.bundleName
    static func resourceBundle(appBundle: Bundle) throws -> Bundle {
        if appBundle.bundleURL.pathExtension.lowercased() == "app" || appBundle.infoDictionary?["CFBundlePackageType"] as? String == "APPL" {
            guard let url = appBundle.resourceURL?.appendingPathComponent(resourceBundleName),
                  let found = Bundle(url: url),
                  FileManager.default.fileExists(atPath: url.appendingPathComponent("en.lproj/Localizable.strings").path)
            else { throw CocoaError(.fileNoSuchFile) }
            return found
        }
        return AppLocalizationResources.bundle
    }

    private static func propertyList(bundle: Bundle, language: String, ext: String) -> [String: Any] {
        let url = bundle.bundleURL.appendingPathComponent(language + ".lproj/Localizable." + ext)
        guard let data = try? Data(contentsOf: url),
              let value = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return value
    }
    private static func readTable(bundle: Bundle, language: String) -> [String: String] {
        propertyList(bundle: bundle, language: language, ext: "strings").compactMapValues { $0 as? String }
    }
    private static func readPlurals(bundle: Bundle, language: String) -> [String: [String: String]] {
        propertyList(bundle: bundle, language: language, ext: "stringsdict").compactMapValues { raw in
            guard let entry = raw as? [String: Any], let n = entry["n"] as? [String: String],
                  n["NSStringFormatSpecTypeKey"] == "NSStringPluralRuleType",
                  n["NSStringFormatValueTypeKey"] == "lld" else { return nil }
            return n
        }
    }
}
