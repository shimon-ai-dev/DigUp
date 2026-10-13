import DigUpKit
import Foundation
import Testing
@testable import DigUpApp

@Suite struct AppSettingsDefaultsTests {
    /// A private persistent domain, never the host test process or an installed app's preferences.
    private func isolatedDefaults() throws -> (String, UserDefaults) {
        let suite = AppIdentity.bundleIdentifier + ".settings-tests." + UUID().uuidString
        return (suite, try #require(UserDefaults(suiteName: suite)))
    }

    @Test func ownBundleDefaultUsesStandardAndPreservesPreferences() throws {
        let (suite, standard) = try isolatedDefaults()
        defer { standard.removePersistentDomain(forName: suite) }
        standard.set("persisted-hotkey", forKey: "hotkey")
        let resolved = try AppSettings.resolveDefaults(requestedSuite: nil,
            bundleIdentifier: AppIdentity.bundleIdentifier, standard: standard)
        #expect(resolved === standard)
        #expect(resolved.string(forKey: "hotkey") == "persisted-hotkey")
        resolved.set(true, forKey: "onboarded")
        #expect(standard.bool(forKey: "onboarded"))
    }

    @Test func explicitOwnBundleSuiteUsesStandard() throws {
        let (suite, standard) = try isolatedDefaults()
        defer { standard.removePersistentDomain(forName: suite) }
        let resolved = try AppSettings.resolveDefaults(requestedSuite: AppIdentity.bundleIdentifier,
            bundleIdentifier: AppIdentity.bundleIdentifier, standard: standard)
        #expect(resolved === standard)
    }

    @Test func independentCustomSuitePreservesReadsAndWrites() throws {
        let (suite, custom) = try isolatedDefaults()
        defer { custom.removePersistentDomain(forName: suite) }
        custom.set("custom-hotkey", forKey: "hotkey")
        let (standardSuite, standard) = try isolatedDefaults()
        defer { standard.removePersistentDomain(forName: standardSuite) }
        standard.set("host-hotkey", forKey: "hotkey")
        let resolved = try AppSettings.resolveDefaults(requestedSuite: suite,
            bundleIdentifier: AppIdentity.bundleIdentifier, standard: standard)
        #expect(resolved !== standard)
        #expect(resolved.string(forKey: "hotkey") == "custom-hotkey")
        resolved.set(["/synthetic/test"], forKey: "roots")
        #expect(custom.stringArray(forKey: "roots") == ["/synthetic/test"])
        #expect(standard.string(forKey: "hotkey") == "host-hotkey")
        #expect(standard.object(forKey: "roots") == nil)
    }

    @Test func suiteErrorRetainsRejectedDomainAndRecovery() {
        let error = AppSettingsDefaultsError(suite: UserDefaults.globalDomain)
        #expect(error.localizedDescription.contains(UserDefaults.globalDomain))
        #expect(!error.localizedDescription.isEmpty)
    }

    @Test(arguments: ["", "   ", UserDefaults.globalDomain, UserDefaults.argumentDomain,
                      UserDefaults.registrationDomain, "com.abdurrahim.DigUp", "COM.ABDURRAHIM.DIGUP",
                      "com.abdurrahim.DigUp.dev", "invalid\0suite"])
    func invalidOrOriginalSuiteFailsClosed(suite: String) throws {
        let (privateSuite, standard) = try isolatedDefaults()
        defer { standard.removePersistentDomain(forName: privateSuite) }
        #expect(throws: AppSettingsDefaultsError.self) {
            try AppSettings.resolveDefaults(requestedSuite: suite,
                bundleIdentifier: AppIdentity.bundleIdentifier, standard: standard)
        }
        #expect((standard.persistentDomain(forName: privateSuite) ?? [:]).isEmpty)
    }
}
