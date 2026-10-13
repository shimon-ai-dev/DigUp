import DigUpKit
import Foundation

/// What to index, where the index and the model live, and the hotkey.
///
/// Saved in the test edition's dedicated defaults domain. Launch arguments override any of it without being
/// saved, which is how tests point the app at the testbed and never at real folders:
///
///     DigUp.app/Contents/MacOS/DigUp -roots ~/DigUpTestbed/real -indexDir <repo>/.dev/app-index \
///         -modelsDir <repo>/.dev/models -defaultsSuite io.github.xieshiqi147258.DigUp.ci.dev
///
/// `-roots` takes one folder, several joined with ":", or a plist array. `-defaultsSuite` keeps what the app saves
/// (onboarding's folders, a new hotkey) out of the real settings. With no roots the app indexes nothing and opens
/// onboarding: a fresh install never starts reading someone's home folder on its own.
nonisolated struct AppSettings: Sendable {
    var roots: [URL]
    /// Folders inside the roots that are never indexed.
    var excludedFolders: [URL]
    /// File extensions that are never indexed ("heic", "txt"), on top of what DigUp never reads anyway.
    var excludedTypes: [String]
    var indexDirectory: URL
    /// Where the model files are downloaded to and loaded from (the helpers get it as DIGUP_MODELS).
    var modelsDirectory: URL
    var hotkey: String
    /// On (the default), the big first pass of a folder (the backfill) runs on battery too; off, it waits for a
    /// charger. New files always index right away, and Low Power Mode or a hot Mac make the backfill wait either way.
    var indexOnBattery: Bool
    /// The query encoder (~0.25 GB) exits after this long without a query; the next panel open starts it again.
    var encoderIdleSeconds: Double
    /// Onboarding was finished (or closed after choosing folders); it doesn't open by itself again.
    var onboarded: Bool
    /// Code search: the folders whose code goes into the code index (none: code search is off), and the folders
    /// skipped in them (`FolderSelection`'s rule, as for `roots`). Searched with "code:" only.
    var codeRoots: [URL]
    var codeExcluded: [URL]
    /// The bundle id of the editor code results open in ("" for each file's default app); nil until one is chosen
    /// (`CodeEditor.chosen`).
    var codeEditor: String?
    /// The code index catches up once the code folders have been quiet this long (`-codeQuietSeconds`, default 60).
    var codeQuietSeconds: Double

    static let supportDirectory = AppIdentity.supportDirectory
    static let defaultIndexDirectory = AppIdentity.indexDirectory
    static let defaultHotkey = "cmd+shift+space"

    /// The battery switch, in onboarding and Settings.
    static let batteryTitle = Localization.current.text("settings.battery.title", fallback: "Index on battery power")
    static let batteryDetail = Localization.current.text("settings.battery.detail", fallback: "When it's off, a folder's first pass waits for a charger. New files always go in right away.")

    /// Where settings are saved. Reads see launch arguments first either way. (UserDefaults is thread-safe.)
    /// Cache a failure too: an invalid explicit suite must never switch to another app's preferences.
    nonisolated(unsafe) private static let savedDefaults: Result<UserDefaults, any Error> = Result {
        try resolveDefaults(requestedSuite: UserDefaults.standard.string(forKey: "defaultsSuite"),
                            bundleIdentifier: Bundle.main.bundleIdentifier, standard: .standard)
    }

    static var defaults: UserDefaults {
        get throws { try savedDefaults.get() }
    }

    static func resolveDefaults(requestedSuite: String?, bundleIdentifier: String?,
                                standard: UserDefaults) throws -> UserDefaults {
        let suite = requestedSuite ?? AppIdentity.bundleIdentifier
        let normalized = suite.lowercased()
        let reserved = [UserDefaults.globalDomain, UserDefaults.argumentDomain, UserDefaults.registrationDomain]
        guard !suite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !suite.contains("\0"),
              normalized != "com.abdurrahim.digup", !normalized.hasPrefix("com.abdurrahim.digup."),
              !reserved.contains(where: { $0.lowercased() == normalized }) else {
            throw AppSettingsDefaultsError(suite: suite)
        }
        // Foundation rejects the current app's own bundle ID as a suite. Standard already uses that domain.
        // Unbundled SwiftPM runs still use the explicit testing domain, not their host process's standard defaults.
        if suite == bundleIdentifier { return standard }
        guard let defaults = UserDefaults(suiteName: suite) else {
            throw AppSettingsDefaultsError(suite: suite)
        }
        return defaults
    }

    static func load() throws -> AppSettings {
        let defaults = try Self.defaults
        let requestedIndex = defaults.string(forKey: "indexDir").map(folderURL) ?? defaultIndexDirectory
        let requestedModels = defaults.string(forKey: "modelsDir").map(folderURL) ?? ModelFiles.installed
        try AppIdentity.validateDataDirectory(requestedIndex)
        try AppIdentity.validateDataDirectory(requestedModels)
        return AppSettings(
            roots: folders(defaults, "roots"),
            excludedFolders: folders(defaults, "excludedFolders"),
            excludedTypes: (defaults.stringArray(forKey: "excludedTypes")
                ?? defaults.string(forKey: "excludedTypes").map { [$0] } ?? [])
                .flatMap { IndexOptions.extensions($0) }.sorted(),
            indexDirectory: requestedIndex,
            modelsDirectory: requestedModels,
            hotkey: defaults.string(forKey: "hotkey") ?? defaultHotkey,
            indexOnBattery: defaults.object(forKey: "indexOnBattery") == nil || defaults.bool(forKey: "indexOnBattery"),
            encoderIdleSeconds: defaults.object(forKey: "encoderIdleSeconds") == nil
                ? 600 : max(1, defaults.double(forKey: "encoderIdleSeconds")),
            onboarded: defaults.bool(forKey: "onboarded"),
            codeRoots: folders(defaults, "codeRoots"),
            codeExcluded: folders(defaults, "codeExcludedFolders"),
            codeEditor: defaults.string(forKey: "codeEditor"),
            codeQuietSeconds: defaults.object(forKey: "codeQuietSeconds") == nil
                ? 60 : max(1, defaults.double(forKey: "codeQuietSeconds")))
    }

    /// A list of folders: a plist array, or paths joined with ":" (the form launch arguments use).
    private static func folders(_ defaults: UserDefaults, _ key: String) -> [URL] {
        let paths: [String]
        if let list = defaults.stringArray(forKey: key) {
            paths = list
        } else if let joined = defaults.string(forKey: key) {
            paths = joined.split(separator: ":").map(String.init)
        } else {
            paths = []
        }
        var seen = Set<String>()
        return paths.filter { !$0.isEmpty }.map(folderURL).filter { seen.insert($0.path).inserted }
    }

    static func save(roots: [URL]) {
        try? defaults.set(roots.map(\.path), forKey: "roots")
    }

    static func save(excludedFolders: [URL]) {
        try? defaults.set(excludedFolders.map(\.path), forKey: "excludedFolders")
    }

    static func save(excludedTypes: [String]) {
        try? defaults.set(excludedTypes, forKey: "excludedTypes")
    }

    static func save(hotkey: String) {
        try? defaults.set(hotkey, forKey: "hotkey")
    }

    static func save(indexOnBattery: Bool) {
        try? defaults.set(indexOnBattery, forKey: "indexOnBattery")
    }

    static func saveOnboarded() {
        try? defaults.set(true, forKey: "onboarded")
    }

    static func save(codeRoots: [URL], excluded: [URL]) {
        try? defaults.set(codeRoots.map(\.path), forKey: "codeRoots")
        try? defaults.set(excluded.map(\.path), forKey: "codeExcludedFolders")
    }

    static func save(codeEditor: String) {
        try? defaults.set(codeEditor, forKey: "codeEditor")
    }

    /// Expands "~" and resolves symlinks, so crawled paths match the paths FSEvents reports.
    static func folderURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath)
            .resolvingSymlinksInPath().standardizedFileURL
    }

    static func isFolder(_ url: URL) -> Bool {
        var isFolder: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
    }
}

/// "~/DigUpTestbed/real" instead of "/Users/…/DigUpTestbed/real".
nonisolated func tildePath(_ path: String) -> String {
    (path as NSString).abbreviatingWithTildeInPath
}

/// A configuration error, surfaced by load() before controllers or app data I/O start.
nonisolated struct AppSettingsDefaultsError: LocalizedError {
    let suite: String
    var errorDescription: String? {
        Localization.current.format("error.defaultsSuite", fallback:
            "Cannot use settings domain \"%@\". Omit -defaultsSuite or choose a separate testing domain.", suite)
    }
}
