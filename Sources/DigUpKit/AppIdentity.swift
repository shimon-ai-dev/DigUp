import Foundation

/// This fork's testing edition. App and helper share one identity and data policy.
public enum AppIdentity {
    public static let bundleIdentifier = "io.github.xieshiqi147258.DigUp.ci"
    public static let helperName = "digup-test"
    public static let helperIdentifier = bundleIdentifier + ".helper"
    public static let updatesEnabled = false
    public static let supportDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DigUpTest")
    public static let indexDirectory = supportDirectory.appendingPathComponent("index.noindex")
    public static let modelsDirectory = supportDirectory.appendingPathComponent("Models")

    public static func isOriginalDataDirectory(_ directory: URL) -> Bool {
        let original = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp").resolvingSymlinksInPath().standardizedFileURL.path
        let requested = directory.resolvingSymlinksInPath().standardizedFileURL.path.lowercased()
        let protected = original.lowercased()
        return requested == protected || requested.hasPrefix(protected + "/")
    }

    public static func validateIndexDirectory(_ directory: URL) throws {
        if isOriginalDataDirectory(directory) {
            throw WorkerError.failed("DigUp Test cannot open the original DigUp data directory; choose a separate index")
        }
    }
}
