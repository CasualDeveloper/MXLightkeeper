import AppKit
import MXLightkeeperCore
import SwiftUI

struct MenuBarContentView: View {
  let model: AppModel

  private static let batteryDateFormatter: RelativeDateTimeFormatter = {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter
  }()

  #if DEBUG
  @State private var isShowingDebugActions = false
  #endif

  private var enabledBinding: Binding<Bool> {
    Binding(
      get: { model.isEnabled },
      set: { model.setEnabled($0) }
    )
  }

  private var launchAtLoginBinding: Binding<Bool> {
    Binding(
      get: { model.launchAtLogin },
      set: { model.setLaunchAtLogin($0) }
    )
  }



  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()

      if model.activeMatch == nil {
        emptyState
      } else {
        infoRows
      }

      #if DEBUG
      Divider()
      debugSection
      #endif

      Divider()
      footer
    }
    .frame(width: 320)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      Toggle("Keep backlight on", isOn: enabledBinding)
        .toggleStyle(.switch)
        .labelsHidden()
        .accessibilityLabel("Keep backlight on")

      VStack(alignment: .leading, spacing: 3) {
        Text("MXLightkeeper")
          .font(.headline)
          .foregroundStyle(.primary)

        HStack(alignment: .top, spacing: 5) {
          if model.status == .degraded {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.caption)
              .foregroundStyle(.orange)
              .padding(.top, 2)
          }
          Text(model.status.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("MXLightkeeper, \(model.status.title), \(model.status.subtitle)")

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var emptyState: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "cable.connector.horizontal")
        .font(.title3)
        .foregroundStyle(.secondary)
        .frame(width: 28, height: 28)

      VStack(alignment: .leading, spacing: 2) {
        Text("No Logitech receiver detected")
          .font(.footnote)
          .foregroundStyle(.primary)
        Text("Plug in your Unifying receiver to get started.")
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var infoRows: some View {
    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
      GridRow {
        infoIcon("antenna.radiowaves.left.and.right")
        Text(model.receiverLabel)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Receiver, \(model.receiverLabel)")

      if let keyboardLabel = model.keyboardLabel {
        GridRow {
          infoIcon("keyboard")
          Text(keyboardLabel)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Keyboard, \(keyboardLabel)")
      }

      if let batteryLabel = model.batteryLabel {
        GridRow {
          Image(systemName: batterySymbol)
            .foregroundStyle(batterySymbolColor)
            .frame(width: 16)
          Text(batteryLabel)
            .foregroundStyle(.primary)
            .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery, \(model.batteryAccessibilityLabel ?? batteryLabel)")
        .help(batteryRefreshTooltip)
      }
    }
    .font(.footnote)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private func infoIcon(_ name: String) -> some View {
    Image(systemName: name)
      .foregroundStyle(.secondary)
      .frame(width: 16)
  }

  private var batterySymbol: String {
    guard let battery = model.batteryStatus else { return "battery.0percent" }

    switch battery.powerStatus {
    case .recharging, .almostFull, .wiredCharging, .chargingComplete:
      return "battery.100percent.bolt"
    default:
      break
    }

    let level = battery.dischargeLevel
    switch level {
    case 88...: return "battery.100percent"
    case 63...87: return "battery.75percent"
    case 38...62: return "battery.50percent"
    case 13...37: return "battery.25percent"
    default: return "battery.0percent"
    }
  }

  private var batterySymbolColor: Color {
    guard let battery = model.batteryStatus else { return .primary }

    switch battery.powerStatus {
    case .critical:
      return .red
    case .recharging, .almostFull, .wiredCharging, .chargingComplete:
      return .green
    case .discharging:
      return battery.dischargeLevel < 20 ? .orange : .primary
    default:
      return .primary
    }
  }

  private var batteryRefreshTooltip: String {
    guard let date = model.batteryLastUpdatedAt else { return "Battery status" }
    return "Updated \(Self.batteryDateFormatter.localizedString(for: date, relativeTo: Date()))"
  }

  #if DEBUG
  private var debugSection: some View {
    DisclosureGroup("Developer", isExpanded: $isShowingDebugActions) {
      VStack(alignment: .leading, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          debugRow("Matchers", model.matcherSummary)
          debugRow("Device", model.receiverSummary)
          debugRow("Report", model.reportSummary)
        }

        HStack(spacing: 14) {
          Button("Refresh") { model.refreshReceivers() }
          Button("Pulse") { model.sendProofPulse() }
          Button("Demo") { model.sendVisibleDemo() }
          Button("Probe") { model.sendOnOnlyProbe() }
            .disabled(!model.canRunDebugAction)
        }
        .buttonStyle(.link)
        .font(.footnote)

        if model.isRunningDebugAction {
          HStack(spacing: 6) {
            ProgressView()
              .controlSize(.mini)
            Text("Running…")
          }
          .font(.footnote)
          .foregroundStyle(.secondary)
        }
      }
      .padding(.top, 10)
    }
    .font(.footnote.weight(.medium))
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
  }

  private func debugRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      Text(label)
        .foregroundStyle(.secondary)
        .frame(width: 72, alignment: .trailing)
      Text(value)
        .font(.footnote.monospacedDigit())
        .lineLimit(1)
        .truncationMode(.tail)
    }
    .font(.footnote)
  }
  #endif

  private var footer: some View {
    HStack(alignment: .center, spacing: 12) {
      Button("Quit") { model.quit() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("q")

      Spacer(minLength: 8)

      HStack(spacing: 6) {
        Text("Launch at login")
          .font(.footnote)
        Toggle("Launch at login", isOn: launchAtLoginBinding)
          .toggleStyle(.checkbox)
          .labelsHidden()
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("Launch at login")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}
