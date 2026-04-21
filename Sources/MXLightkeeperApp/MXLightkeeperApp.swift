import SwiftUI

@main
struct MXLightkeeperApp: App {
  @State private var model = AppModel()

  var body: some Scene {
    MenuBarExtra {
      MenuBarContentView(model: model)
    } label: {
      MenuBarIcon(status: model.status)
    }
    .menuBarExtraStyle(.window)
  }
}
