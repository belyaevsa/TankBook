import Foundation
import Testing
@testable import TankbookCore

// RV.24: the language decision (docs/TASKS.md RV.24). The rule is pure:
// no stored preference -> follow the system; a stored one wins. Nothing is
// written at first launch, and removing the choice returns to "follow the
// system" as a state distinct from "the system language happens to be English".

@Suite("Language preference decision")
struct LanguagePreferenceTests {

    @Test("no stored preference follows the system")
    func noStoredPreferenceFollowsSystem() {
        #expect(LanguagePreference.resolve(storedLanguage: nil) == .followSystem)
    }

    @Test("an empty stored value follows the system")
    func emptyStoredValueFollowsSystem() {
        #expect(LanguagePreference.resolve(storedLanguage: "") == .followSystem)
    }

    @Test("a stored preference wins")
    func storedPreferenceWins() {
        #expect(LanguagePreference.resolve(storedLanguage: "ru") == .selected("ru"))
        #expect(LanguagePreference.resolve(storedLanguage: "en") == .selected("en"))
    }
}

@Suite("Language preference store")
struct LanguagePreferenceStoreTests {

    private struct TestStore {
        let store: LanguagePreferenceStore
        let defaults: UserDefaults
        let suite: String

        /// The raw persisted plist for the suite - the ground truth of what was
        /// written, unpolluted by the system's global domains (which is exactly
        /// what a plain `defaults.object(forKey:)` read would mix in for
        /// `AppleLanguages`).
        func persisted() -> [String: Any] {
            defaults.persistentDomain(forName: suite) ?? [:]
        }
    }

    private func makeStore() -> TestStore {
        let suite = "language-preference-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return TestStore(store: LanguagePreferenceStore(defaults: defaults),
                         defaults: defaults,
                         suite: suite)
    }

    @Test("a fresh store writes nothing to UserDefaults")
    func freshStoreWritesNothing() {
        let test = makeStore()
        #expect(test.store.selectedLanguage == nil)
        #expect(test.store.storedLanguage == nil)
        let persisted = test.persisted()
        #expect(persisted[LanguagePreference.appleLanguagesKey] == nil,
                "a fresh store must not write AppleLanguages - first launch follows the system")
        #expect(persisted[LanguagePreferenceStore.storedLanguageKey] == nil,
                "a fresh store must not write its own override key either")
    }

    @Test("selecting a language stores the choice and writes AppleLanguages")
    func selectingStoresAndWritesAppleLanguages() {
        let test = makeStore()
        test.store.select("ru")
        #expect(test.store.selectedLanguage == "ru")
        #expect(test.store.storedLanguage == "ru")
        let persisted = test.persisted()
        #expect(persisted[LanguagePreferenceStore.storedLanguageKey] as? String == "ru")
        #expect(persisted[LanguagePreference.appleLanguagesKey] as? [String] == ["ru"],
                "selecting writes AppleLanguages so iOS applies it on the next launch")
    }

    @Test("following the system removes both the choice and the AppleLanguages write")
    func followingSystemRemovesThePreference() {
        let test = makeStore()
        test.store.select("ru")
        test.store.followSystem()
        #expect(test.store.selectedLanguage == nil)
        let persisted = test.persisted()
        #expect(persisted[LanguagePreferenceStore.storedLanguageKey] == nil)
        #expect(persisted[LanguagePreference.appleLanguagesKey] == nil)
    }

    @Test("the choice persists across a fresh store instance")
    func choicePersistsAcrossInstances() {
        let test = makeStore()
        test.store.select("ru")
        let second = LanguagePreferenceStore(defaults: test.defaults)
        #expect(second.selectedLanguage == "ru")
    }
}
