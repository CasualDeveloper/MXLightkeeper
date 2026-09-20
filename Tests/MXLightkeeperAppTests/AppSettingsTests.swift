@testable import MXLightkeeperApp
import Foundation
import MXLightkeeperCore
import Testing

@MainActor
@Test func absentSettingsUseFirstInstallDefaults() throws {
  let (defaults, suiteName) = try makeIsolatedDefaults()
  defer { defaults.removePersistentDomain(forName: suiteName) }

  #expect(AppModel.loadSettings(from: defaults) == MXLightkeeperSettings())
}

@MainActor
@Test func partialSettingsPreserveDisabledIntent() throws {
  let (defaults, suiteName) = try makeIsolatedDefaults()
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(Data(#"{"isEnabled":false}"#.utf8), forKey: "mxlightkeeper.settings")

  #expect(
    AppModel.loadSettings(from: defaults)
      == MXLightkeeperSettings(isEnabled: false, launchAtLogin: false)
  )
}

@MainActor
@Test func missingEnabledIntentFailsClosed() throws {
  let (defaults, suiteName) = try makeIsolatedDefaults()
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(Data(#"{"launchAtLogin":true}"#.utf8), forKey: "mxlightkeeper.settings")

  #expect(
    AppModel.loadSettings(from: defaults)
      == MXLightkeeperSettings(isEnabled: false, launchAtLogin: true)
  )
}

@MainActor
@Test(
  arguments: [
    Data(#"{"isEnabled":"yes","launchAtLogin":true}"#.utf8),
    Data("not-json".utf8),
  ]
)
func invalidExistingSettingsFailClosed(data: Data) throws {
  let (defaults, suiteName) = try makeIsolatedDefaults()
  defer { defaults.removePersistentDomain(forName: suiteName) }
  defaults.set(data, forKey: "mxlightkeeper.settings")

  #expect(
    AppModel.loadSettings(from: defaults)
      == MXLightkeeperSettings(isEnabled: false, launchAtLogin: false)
  )
}

private func makeIsolatedDefaults() throws -> (UserDefaults, String) {
  let suiteName = "MXLightkeeperAppTests.\(UUID().uuidString)"
  return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
}
