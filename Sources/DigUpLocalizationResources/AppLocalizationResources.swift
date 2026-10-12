import Foundation

/// SwiftPM's generated accessor must remain outside the app's default MainActor isolation.
/// This target contains only immutable resources and may be read from any executor.
public enum AppLocalizationResources {
    public static let bundle: Bundle = Bundle.module
    public static let bundleName = "DigUp_DigUpLocalizationResources.bundle"
}
