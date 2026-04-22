import MXLightkeeperCore
import SwiftUI

struct MenuBarIcon: View {
  let status: AppStatus

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var symbolName: String {
    switch status {
    case .active:
      return "light.max"
    case .waiting, .degraded, .disabled:
      return "light.min"
    }
  }

  private var tint: Color {
    switch status {
    case .degraded:
      return .orange
    case .active, .waiting, .disabled:
      return .primary
    }
  }

  private var accessibilityDescription: String {
    AppStrings.menuBarIconAccessibility(status)
  }

  var body: some View {
    Image(systemName: symbolName)
      .symbolRenderingMode(.monochrome)
      .contentTransition(.symbolEffect(.replace))
    .foregroundStyle(tint)
    .animation(iconTransition, value: status)
    .accessibilityLabel(accessibilityDescription)
  }

  private var iconTransition: Animation? {
    guard !reduceMotion else {
      return nil
    }

    return .easeOut(duration: 0.18)
  }
}
