import SwiftUI

@main
struct MXLightkeeperApp: App {
  @State private var model: AppModel

  private var appLocale: Locale {
    AppLanguage.effectiveLocale()
  }

  init() {
    _model = State(initialValue: AppModel())
  }

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: model)
        .environment(\.locale, appLocale)
    } label: {
      MenuBarIcon(status: model.status)
        .environment(\.locale, appLocale)
    }
    .menuBarExtraStyle(.window)
  }
}
