import AppKit
import MXLightkeeperCore
import SwiftUI

struct MenuBarContentView: View {
  let model: AppModel

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

  #if DEBUG
  private var experimentalBoltBinding: Binding<Bool> {
    Binding(
      get: { model.experimentalBoltEnabled },
      set: { model.setExperimentalBoltEnabled($0) }
    )
  }
  #endif

  private var statusTint: Color {
    switch model.status {
    case .active:
      return .green
    case .waiting, .disabled:
      return .orange
    case .degraded:
      return .red
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      details

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
      StatusDot(tint: statusTint)

      VStack(alignment: .leading, spacing: 2) {
        Text(model.status.title)
          .font(.headline)
          .foregroundStyle(.primary)

        Text(model.status.subtitle)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .accessibilityElement(children: .combine)
      .accessibilityLabel("\(model.status.title), \(model.status.subtitle)")

      Spacer(minLength: 8)

      Toggle("Keep backlight on", isOn: enabledBinding)
        .toggleStyle(.switch)
        .labelsHidden()
        .accessibilityLabel("Keep backlight on")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var details: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let error = model.lastErrorMessage {
        Label {
          Text(error)
            .foregroundStyle(.primary)
        } icon: {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
        }
        .font(.footnote)
        .fixedSize(horizontal: false, vertical: true)
      }

      LabeledContent("Receiver") {
        Text(model.receiverLabel)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .font(.footnote)
      .foregroundStyle(.secondary)

      if let keyboardLabel = model.keyboardLabel {
        LabeledContent("Keyboard") {
          Text(keyboardLabel)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .truncationMode(.tail)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }

      if let batteryLabel = model.batteryLabel {
        LabeledContent("Battery") {
          Text(batteryLabel)
            .foregroundStyle(.primary)
            .monospacedDigit()
            .accessibilityLabel(model.batteryAccessibilityLabel ?? batteryLabel)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  #if DEBUG
  private var debugSection: some View {
    DisclosureGroup("Developer", isExpanded: $isShowingDebugActions) {
      VStack(alignment: .leading, spacing: 12) {
        Toggle("Experimental Bolt support", isOn: experimentalBoltBinding)
          .font(.footnote)

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
      Toggle("Launch at login", isOn: launchAtLoginBinding)
        .font(.footnote)

      Spacer(minLength: 8)

      Button("Quit") { model.quit() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .keyboardShortcut("q")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }
}

private struct StatusDot: View {
  let tint: Color

  var body: some View {
    Circle()
      .fill(tint)
      .frame(width: 10, height: 10)
      .frame(width: 28, height: 28)
      .accessibilityHidden(true)
  }
}
