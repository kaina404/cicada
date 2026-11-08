import Foundation
import Testing
@testable import Cicada

struct InterfaceLanguageTests {
    @Test @MainActor func overridePersistsAndCanReturnToSystem() throws {
        let domain = "CicadaTests.InterfaceLanguage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let preference = InterfaceLanguagePreference(defaults: defaults, domain: domain)
        #expect(preference.choice == .system)
        #expect(!preference.needsRelaunch)
        for language in [InterfaceLanguage.english, .chinese] {
            preference.choice = language
            #expect(defaults.stringArray(forKey: "AppleLanguages") == [language.rawValue])
            #expect(preference.needsRelaunch)
            let reopened = InterfaceLanguagePreference(defaults: defaults, domain: domain)
            #expect(reopened.choice == language)
            #expect(!reopened.needsRelaunch)
        }
        preference.choice = .system
        #expect(defaults.persistentDomain(forName: domain)?["AppleLanguages"] == nil)
        #expect(!preference.needsRelaunch)
    }

    @Test @MainActor func existingOverrideIsRespectedAndChangingBackCancelsRelaunch() throws {
        let domain = "CicadaTests.InterfaceLanguage.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        defaults.set(["en"], forKey: "AppleLanguages")
        let preference = InterfaceLanguagePreference(defaults: defaults, domain: domain)
        #expect(preference.choice == .english)
        preference.choice = .chinese
        #expect(preference.needsRelaunch)
        preference.choice = .english
        #expect(!preference.needsRelaunch)
        defaults.set("translation", forKey: "subtitles")
        preference.choice = .system
        #expect(preference.needsRelaunch)
        #expect(defaults.string(forKey: "subtitles") == "translation")
    }
}
