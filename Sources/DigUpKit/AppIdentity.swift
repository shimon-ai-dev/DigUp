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
        let originalURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DigUp")
        let original = (resolved(originalURL) ?? originalURL).path
        guard let canonical = resolved(directory) else { return true }
        let requested = canonical.path.lowercased()
        let protected = original.lowercased()
        return requested == protected || requested.hasPrefix(protected + "/")
    }

    // Foundation may leave a dangling symlink unresolved. Resolve its destination
    // lexically too, without opening any files or creating the missing target.
    private static func resolved(_ url: URL, depth: Int = 0) -> URL? {
        guard depth < 32 else { return nil }
        let canonical = url.standardizedFileURL
        var ancestor = canonical, suffix: [String] = []
        while ancestor.path != "/" {
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: ancestor.path) {
                var destination = link.hasPrefix("/") ? URL(fileURLWithPath: link)
                    : ancestor.deletingLastPathComponent().appendingPathComponent(link)
                for component in suffix.reversed() { destination.appendPathComponent(component) }
                return resolved(destination, depth: depth + 1)
            }
            suffix.append(ancestor.lastPathComponent)
            ancestor.deleteLastPathComponent()
        }
        return canonical.resolvingSymlinksInPath().standardizedFileURL
    }

    public static func validateDataDirectory(_ directory: URL) throws {
        if isOriginalDataDirectory(directory) {
            throw WorkerError.failed("DigUp Test cannot use the original DigUp data directory; choose separate testing data paths")
        }
    }

    public static func validateIndexDirectory(_ directory: URL) throws { try validateDataDirectory(directory) }
}
