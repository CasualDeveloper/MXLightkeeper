import Foundation

enum AppLanguage {
  private static let supportedLanguageCodes = ["en", "fr", "es", "de", "pt-BR", "zh-Hans", "hi", "ar"]
  private static let fallbackLanguageCode = "en"

  static func effectiveLocale(globalPreferredLanguages: [String]? = nil) -> Locale {
    Locale(identifier: effectiveLanguageCode(globalPreferredLanguages: globalPreferredLanguages))
  }

  static func systemLocale(globalPreferredLanguages: [String]? = nil) -> Locale {
    effectiveLocale(globalPreferredLanguages: globalPreferredLanguages)
  }

  static func usesRightToLeftLayout(globalPreferredLanguages: [String]? = nil) -> Bool {
    Locale.Language(identifier: effectiveLanguageCode(globalPreferredLanguages: globalPreferredLanguages)).characterDirection == .rightToLeft
  }

  static func localizedBundle(
    locale: Locale? = nil,
    globalPreferredLanguages: [String]? = nil
  ) -> Bundle {
    let languageCode: String

    if let locale {
      languageCode = supportedLanguageCode(forPreferences: [locale.identifier])
    } else {
      languageCode = effectiveLanguageCode(globalPreferredLanguages: globalPreferredLanguages)
    }

    guard let bundlePath = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
      let localizedBundle = Bundle(path: bundlePath)
    else {
      return .module
    }

    return localizedBundle
  }

  static func effectiveLanguageCode(globalPreferredLanguages: [String]? = nil) -> String {
    let preferredLanguages = globalPreferredLanguages ?? systemPreferredLanguages()
    return supportedLanguageCode(forPreferences: preferredLanguages)
  }

  private static func systemPreferredLanguages() -> [String] {
    (CFPreferencesCopyAppValue(
      "AppleLanguages" as CFString,
      kCFPreferencesAnyApplication
    ) as? [String]) ?? Locale.preferredLanguages
  }

  private static func supportedLanguageCode(forPreferences preferredLanguages: [String]) -> String {
    if let resolvedLocalization = Bundle.preferredLocalizations(
      from: supportedLanguageCodes,
      forPreferences: preferredLanguages
    ).first {
      return resolvedLocalization
    }

    return fallbackLanguageCode
  }
}
