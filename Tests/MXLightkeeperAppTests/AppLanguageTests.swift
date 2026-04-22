@testable import MXLightkeeperApp
import Foundation
import Testing

@Test func effectiveLocaleMatchesSystemLanguagePreferences() {
  #expect(AppLanguage.effectiveLocale(globalPreferredLanguages: ["pt-BR"]).identifier == "pt-BR")
  #expect(AppLanguage.effectiveLocale(globalPreferredLanguages: ["zh"]).identifier == "zh-Hans")
}

@Test func systemLocaleFallsBackToFirstSupportedSystemLanguage() {
  #expect(AppLanguage.systemLocale(globalPreferredLanguages: ["it", "fr", "de"]).identifier == "fr")
  #expect(AppLanguage.systemLocale(globalPreferredLanguages: ["ar"]).identifier == "ar")
}

@Test func supportedLanguageResolutionCoversLocalizedStatusSubtitleLanguages() {
  let supportedLanguages = ["en", "fr", "es", "de", "pt-BR", "zh-Hans", "hi", "ar"]

  #expect(Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: ["de"]).first == "de")
  #expect(Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: ["fr"]).first == "fr")
  #expect(Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: ["zh"]).first == "zh-Hans")
  #expect(Bundle.preferredLocalizations(from: supportedLanguages, forPreferences: ["ar"]).first == "ar")
}

@Test func rtlLayoutFollowsSystemLanguage() {
  #expect(AppLanguage.usesRightToLeftLayout(globalPreferredLanguages: ["ar"]))
  #expect(!AppLanguage.usesRightToLeftLayout(globalPreferredLanguages: ["en"]))
}
