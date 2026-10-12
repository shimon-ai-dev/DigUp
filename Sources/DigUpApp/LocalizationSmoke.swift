import Foundation

/// A read-only packaged-resource probe. Runs before NSApplication, AppController, settings, helper or networking.
nonisolated enum LocalizationSmoke {
    static let permissionKeys = [
        "NSAppleEventsUsageDescription", "NSDesktopFolderUsageDescription",
        "NSDocumentsFolderUsageDescription", "NSDownloadsFolderUsageDescription",
        "NSRemovableVolumesUsageDescription",
    ]
    static func runIfRequested(arguments: [String]) -> Int32? {
        guard arguments.contains("--localization-smoke") else { return nil }
        do {
            let app = Bundle.main
            let resources = try Localization.resourceBundle(appBundle: app)
            let l = Localization(bundle: resources, preferredLanguages: Locale.preferredLanguages,
                                 formattingLocale: Locale(identifier: "en_US"))
            var permissions: [String: String] = [:]
            for key in permissionKeys {
                guard let value = app.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else {
                    throw NSError(domain: "LocalizationSmoke", code: 2,
                                  userInfo: [NSLocalizedDescriptionKey: "Missing permission purpose: " + key])
                }
                permissions[key] = value
            }
            let result: [String: Any] = [
                "language": l.language, "resourcePath": resources.bundleURL.path,
                "cancel": l.text("common.cancel", fallback: "Cancel"),
                "pause": l.text("menu.pause", fallback: "Pause Indexing"),
                "results": l.resultsCount(2), "permissions": permissions,
            ]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            FileHandle.standardOutput.write(data)
            FileHandle.standardOutput.write(Data([10]))
            return 0
        } catch {
            FileHandle.standardError.write(Data("Localization smoke failed: \(error)\n".utf8))
            return 2
        }
    }
}
