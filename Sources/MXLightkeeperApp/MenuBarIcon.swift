import MXLightkeeperCore
import SwiftUI

struct MenuBarIcon: View {
  let status: AppStatus

  private var symbolName: String {
    switch status {
    case .active:
      return "light.max"
    case .waiting, .degraded, .disabled:
      return "light.min"
    }
  }

  private var tint: Color {
    status == .degraded ? .orange : .primary
  }

  private var accessibilityDescription: String {
    "MXLightkeeper, backlight \(status.title.lowercased())"
  }

  var body: some View {
    Image(systemName: symbolName)
      .symbolRenderingMode(.monochrome)
      .foregroundStyle(tint)
      .accessibilityLabel(accessibilityDescription)
  }
}
