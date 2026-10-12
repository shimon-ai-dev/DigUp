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
        guard let original = resolved(originalURL)?.path,
              let canonical = resolved(directory) else { return true }
        let requested = canonical.path.lowercased()
        let protected = original.lowercased()
        return requested == protected || requested.hasPrefix(protected + "/")
    }

    // Resolve one filesystem component at a time, including dangling links.
    // Foundation's standardization may map /private/var back to /var on macOS;
    // recursively standardizing /var's destination then falsely looks like a loop.
    // Keep physical components intact and handle ".." only after any symlink.
    private static func resolved(_ url: URL) -> URL? {
        var pending = url.path.split(separator: "/").map(String.init)
        var components: [String] = []
        var links = 0
        while !pending.isEmpty {
            let component = pending.removeFirst()
            if component == "." { continue }
            if component == ".." {
                if !components.isEmpty { components.removeLast() }
                continue
            }
            let candidate = "/" + (components + [component]).joined(separator: "/")
            if let link = try? FileManager.default.destinationOfSymbolicLink(atPath: candidate) {
                links += 1
                guard links <= 32 else { return nil }
                if link.hasPrefix("/") { components.removeAll() }
                pending = link.split(separator: "/").map(String.init) + pending
            } else {
                components.append(component)
            }
        }
        return URL(fileURLWithPath: "/" + components.joined(separator: "/"))
    }

    public static func validateDataDirectory(_ directory: URL) throws {
        if isOriginalDataDirectory(directory) {
            throw WorkerError.failed("DigUp Test cannot use the original DigUp data directory; choose separate testing data paths")
        }
    }

    public static func validateIndexDirectory(_ directory: URL) throws { try validateDataDirectory(directory) }
}
