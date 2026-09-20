@testable import MXLightkeeperApp
import Foundation
import Testing

@Test(arguments: [0, 100])
func batteryStringsFormatRepresentativeLevels(level: Int) {
  let locale = Locale(identifier: "en")

  #expect(!AppStrings.batteryChargingLabel(level: level, locale: locale).isEmpty)
  #expect(!AppStrings.batteryPercentLabel(level: level, locale: locale).isEmpty)
  #expect(!AppStrings.batteryAccessibilityCharging(level: level, locale: locale).isEmpty)
  #expect(!AppStrings.batteryAccessibilityPercent(level: level, locale: locale).isEmpty)
}

@Test func simplifiedChineseAccessibilityCatalogEscapesPercent() throws {
  #expect(try catalogValue(for: "battery.accessibility.charging", locale: "zh-Hans") == "%lld%%，正在充电")
  #expect(try catalogValue(for: "battery.accessibility.percent", locale: "zh-Hans") == "%lld%%")
}

@Test func alphaSuffixCatalogContainsArabicTranslation() throws {
  #expect(try catalogValue(for: "common.alpha_suffix", locale: "ar") == "(ألفا)")
}

@Test func alphaLabelsUseLocalizedSuffixHelper() {
  let locale = Locale(identifier: "en")

  #expect(AppStrings.receiverLabel(kind: "Logitech Bolt", isAlpha: true, locale: locale).contains("(alpha)"))
  #expect(AppStrings.keyboardLabel(name: "MX Keys S", isAlpha: true, locale: locale).contains("(alpha)"))
}

private struct StringCatalog: Decodable {
  let strings: [String: CatalogEntry]
}

private struct CatalogEntry: Decodable {
  let localizations: [String: CatalogLocalization]
}

private struct CatalogLocalization: Decodable {
  let stringUnit: CatalogStringUnit
}

private struct CatalogStringUnit: Decodable {
  let value: String
}

private func catalogValue(for key: String, locale: String) throws -> String {
  let repositoryRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
  let catalogURL = repositoryRoot
    .appendingPathComponent("Sources/MXLightkeeperApp/Resources/Localizable.xcstrings")
  let catalog = try JSONDecoder().decode(StringCatalog.self, from: Data(contentsOf: catalogURL))
  let entry = try #require(catalog.strings[key])
  let localization = try #require(entry.localizations[locale])

  return localization.stringUnit.value
}
