import MXLightkeeperCore
import SwiftUI

struct MenuBarContentView: View {
  let model: AppModel

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var displayedStatus: AppStatus
  @State private var isShowingStatusText = true

  private let menuInset: CGFloat = 0
  private let outerVisualRadius: CGFloat = 23
  private let headerContentHeight: CGFloat = 60

  private var sectionCornerRadius: CGFloat {
    outerVisualRadius - menuInset
  }

  private var controlLayoutDirection: LayoutDirection {
    isRightToLeft ? .rightToLeft : .leftToRight
  }

  private var isRightToLeft: Bool {
    AppLanguage.usesRightToLeftLayout()
  }

  private var horizontalAlignment: HorizontalAlignment {
    isRightToLeft ? .trailing : .leading
  }

  private var contentAlignment: Alignment {
    isRightToLeft ? .trailing : .leading
  }

  private var topContentAlignment: Alignment {
    isRightToLeft ? .topTrailing : .topLeading
  }

  private var textAlignment: TextAlignment {
    isRightToLeft ? .trailing : .leading
  }

  private var batteryDateFormatter: RelativeDateTimeFormatter {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    formatter.locale = AppLanguage.effectiveLocale()
    return formatter
  }

  #if DEBUG
  @State private var isShowingDebugActions = false
  #endif

  init(model: AppModel) {
    self.model = model
    _displayedStatus = State(initialValue: model.status)
  }

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
    VStack(alignment: horizontalAlignment, spacing: 12) {
      mainPanel

      #if DEBUG
      debugSection
      #endif
    }
    .padding(menuInset)
    .frame(width: 320, alignment: contentAlignment)
  }

  private var mainPanel: some View {
    VStack(spacing: 0) {
      header

      panelDivider

      if model.activeMatch == nil {
        emptyState
      } else {
        infoRows
      }

      panelDivider

      footer
    }
    .frame(maxWidth: .infinity, alignment: contentAlignment)
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 12) {
      if isRightToLeft {
        Spacer(minLength: 0)
        headerTextBlock
        headerToggle
      } else {
        headerToggle
        headerTextBlock
        Spacer(minLength: 0)
      }
    }
    .environment(\.layoutDirection, .leftToRight)
    .frame(height: headerContentHeight)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var headerToggle: some View {
    Toggle(AppStrings.keepBacklightOnText, isOn: enabledBinding)
      .toggleStyle(.switch)
      .labelsHidden()
      .accessibilityLabel(Text(AppStrings.keepBacklightOnText))
      .environment(\.layoutDirection, controlLayoutDirection)
      .frame(minWidth: 40)
  }

  private var headerTextBlock: some View {
    VStack(alignment: horizontalAlignment, spacing: 4) {
      Text(AppStrings.appName)
        .font(.headline)
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: contentAlignment)

      HStack(alignment: .firstTextBaseline, spacing: 5) {
        if isRightToLeft {
          statusSubtitle

          if model.status == .degraded {
            statusWarningIcon
          }
        } else {
          if model.status == .degraded {
            statusWarningIcon
          }

          statusSubtitle
        }
      }
      .frame(maxWidth: .infinity, alignment: contentAlignment)
    }
    .animation(statusTransition, value: displayedStatus)
    .animation(statusTransition, value: model.status)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(AppStrings.appStatusAccessibility(model.status))
  }

  private var statusWarningIcon: some View {
    Image(systemName: "exclamationmark.triangle.fill")
      .font(.caption)
      .foregroundStyle(.orange)
  }

  private var emptyState: some View {
    HStack(alignment: .top, spacing: 12) {
      if isRightToLeft {
        Spacer(minLength: 0)
        emptyStateText
        emptyStateIcon
      } else {
        emptyStateIcon
        emptyStateText
        Spacer(minLength: 0)
      }
    }
    .environment(\.layoutDirection, .leftToRight)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var emptyStateIcon: some View {
    Image(systemName: "cable.connector.horizontal")
      .font(.title3)
      .foregroundStyle(.secondary)
      .frame(width: 28, height: 28)
  }

  private var emptyStateText: some View {
    VStack(alignment: horizontalAlignment, spacing: 2) {
      Text(AppStrings.noReceiverTitleText)
        .font(.footnote)
        .fontWeight(.medium)
        .foregroundStyle(.primary)
        .multilineTextAlignment(textAlignment)

      Text(AppStrings.noReceiverMessageText)
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(textAlignment)
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  private var infoRows: some View {
    VStack(alignment: horizontalAlignment, spacing: 12) {
      infoRow(
        icon: AnyView(infoIcon("antenna.radiowaves.left.and.right")),
        text: model.receiverLabel,
        accessibilityLabel: AppStrings.receiverAccessibility(model.receiverLabel)
      )

      if let keyboardLabel = model.keyboardLabel {
        infoRow(
          icon: AnyView(infoIcon("keyboard")),
          text: keyboardLabel,
          accessibilityLabel: AppStrings.keyboardAccessibility(keyboardLabel)
        )
      }

      if let batteryLabel = model.batteryLabel {
        infoRow(
          icon: AnyView(
            Image(systemName: batterySymbol)
              .foregroundStyle(batterySymbolColor)
              .frame(width: 16)
              .padding(.top, 1)
          ),
          text: batteryLabel,
          accessibilityLabel: AppStrings.batteryAccessibility(model.batteryAccessibilityLabel ?? batteryLabel),
          usesTabularNumbers: true
        )
        .help(batteryRefreshTooltip)
      }
    }
    .font(.footnote)
    .padding(.horizontal, 16)
    .padding(.vertical, 14)
  }

  private var statusSubtitle: some View {
    ZStack(alignment: .leading) {
      statusText(displayedStatus.localizedSubtitle)
        .hidden()
        .accessibilityHidden(true)

      statusText(model.status.localizedSubtitle)
        .hidden()
        .accessibilityHidden(true)

      if isShowingStatusText {
        statusText(displayedStatus.localizedSubtitle)
          .id(displayedStatus)
          .transition(statusTextTransition)
      }
    }
    .frame(maxWidth: .infinity, alignment: topContentAlignment)
    .clipped()
    .animation(statusTransition, value: isShowingStatusText)
    .task(id: model.status) {
      await updateDisplayedStatus(for: model.status)
    }
  }

  private func infoRow(
    icon: AnyView,
    text: String,
    accessibilityLabel: String,
    usesTabularNumbers: Bool = false
  ) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      if isRightToLeft {
        Spacer(minLength: 0)

        Text(text)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .multilineTextAlignment(textAlignment)
          .modifier(TabularNumbersModifier(isEnabled: usesTabularNumbers))

        icon
      } else {
        icon

        Text(text)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .truncationMode(.middle)
          .multilineTextAlignment(textAlignment)
          .modifier(TabularNumbersModifier(isEnabled: usesTabularNumbers))

        Spacer(minLength: 0)
      }
    }
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(accessibilityLabel)
  }

  private func statusText(_ value: String) -> some View {
    Text(value)
      .font(.subheadline)
      .foregroundStyle(.secondary)
      .lineLimit(2)
      .multilineTextAlignment(textAlignment)
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: contentAlignment)
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
    guard let date = model.batteryLastUpdatedAt else { return AppStrings.batteryStatusText }
    return AppStrings.batteryTooltip(relativeTime: batteryDateFormatter.localizedString(for: date, relativeTo: Date()))
  }

  private var statusTransition: Animation? {
    guard !reduceMotion else {
      return nil
    }

    return .easeOut(duration: 0.16)
  }

  private var statusTextTransition: AnyTransition {
    guard !reduceMotion else {
      return .identity
    }

    return .asymmetric(
      insertion: .modifier(
        active: StatusTextOffsetModifier(offset: 5),
        identity: StatusTextOffsetModifier(offset: 0)
      ),
      removal: .modifier(
        active: StatusTextOffsetModifier(offset: -5),
        identity: StatusTextOffsetModifier(offset: 0)
      )
    )
  }

  private var footer: some View {
    HStack(alignment: .center, spacing: 12) {
      if isRightToLeft {
        footerLaunchRow
        Spacer(minLength: 0)
        quitButton
      } else {
        quitButton
        Spacer(minLength: 0)
        footerLaunchRow
      }
    }
    .environment(\.layoutDirection, .leftToRight)
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
  }

  private var quitButton: some View {
    Button(action: model.quit) {
      Text(AppStrings.quitText)
    }
    .buttonStyle(.bordered)
    .controlSize(.small)
    .keyboardShortcut("q")
    .frame(minHeight: 40)
  }

  private var footerLaunchRow: some View {
    HStack(alignment: .center, spacing: 8) {
      if isRightToLeft {
        Toggle(AppStrings.launchAtLoginText, isOn: launchAtLoginBinding)
          .toggleStyle(.checkbox)
          .labelsHidden()
          .controlSize(.small)
          .environment(\.layoutDirection, controlLayoutDirection)

        Text(AppStrings.launchAtLoginText)
          .font(.footnote)
          .multilineTextAlignment(textAlignment)
      } else {
        Text(AppStrings.launchAtLoginText)
          .font(.footnote)
          .multilineTextAlignment(textAlignment)

        Toggle(AppStrings.launchAtLoginText, isOn: launchAtLoginBinding)
          .toggleStyle(.checkbox)
          .labelsHidden()
          .controlSize(.small)
      }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel(Text(AppStrings.launchAtLoginText))
  }

  private var panelDivider: some View {
    Rectangle()
      .fill(Color.primary.opacity(0.10))
      .frame(height: 0.5)
      .padding(.horizontal, 0)
  }

  #if DEBUG
  private var debugSection: some View {
    sectionCard(verticalPadding: 10) {
      DisclosureGroup("Developer", isExpanded: $isShowingDebugActions) {
        VStack(alignment: horizontalAlignment, spacing: 12) {
          VStack(alignment: horizontalAlignment, spacing: 6) {
            debugRow("Matchers", model.matcherSummary)
            debugRow("Device", model.receiverSummary)
            debugRow("Report", model.reportSummary)
          }

          HStack(spacing: 14) {
            Button("Refresh") { model.refreshReceivers() }
            Button("Pulse") { model.sendProofPulse() }
              .disabled(!model.canRunDebugAction)
            Button("Demo") { model.sendVisibleDemo() }
              .disabled(!model.canRunDebugAction)
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
    }
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

  private func sectionCard<Content: View>(
    verticalPadding: CGFloat,
    @ViewBuilder content: () -> Content
  ) -> some View {
    content()
      .frame(maxWidth: .infinity, alignment: contentAlignment)
      .padding(.horizontal, 16)
      .padding(.vertical, verticalPadding)
  }

  @MainActor
  private func updateDisplayedStatus(for newStatus: AppStatus) async {
    guard displayedStatus != newStatus else {
      isShowingStatusText = true
      return
    }

    guard !reduceMotion else {
      displayedStatus = newStatus
      isShowingStatusText = true
      return
    }

    isShowingStatusText = false
    do {
      try await Task.sleep(for: .milliseconds(150))
    } catch {
      return
    }

    guard !Task.isCancelled else {
      return
    }
    displayedStatus = newStatus
    isShowingStatusText = true
  }
}

private struct TabularNumbersModifier: ViewModifier {
  let isEnabled: Bool

  func body(content: Content) -> some View {
    if isEnabled {
      content.monospacedDigit()
    } else {
      content
    }
  }
}

private struct StatusTextOffsetModifier: ViewModifier {
  let offset: CGFloat

  func body(content: Content) -> some View {
    content.offset(y: offset)
  }
}
