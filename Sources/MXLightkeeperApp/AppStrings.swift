import Foundation
import MXLightkeeperCore
import SwiftUI

enum AppStrings {
  static let appName = LocalizedStringResource("app.name", defaultValue: "MXLightkeeper", bundle: .module)
  static let alphaSuffix = LocalizedStringResource("common.alpha_suffix", defaultValue: "(alpha)", bundle: .module)

  private static func localized(
    _ key: StaticString,
    defaultValue: String.LocalizationValue,
    locale: Locale? = nil,
    comment: StaticString = ""
  ) -> String {
    let resolvedLocale = locale ?? AppLanguage.effectiveLocale()

    return String(
      localized: key,
      defaultValue: defaultValue,
      bundle: AppLanguage.localizedBundle(locale: resolvedLocale),
      locale: resolvedLocale,
      comment: comment
    )
  }

  static func appStatusAccessibility(_ status: AppStatus) -> String {
    localized(
      "accessibility.app_status",
      defaultValue: "MXLightkeeper, \(status.localizedTitle), \(status.localizedSubtitle)",
      comment: "Accessibility label for the app header with title and status"
    )
  }

  static func menuBarIconAccessibility(_ status: AppStatus) -> String {
    localized(
      "accessibility.menu_bar_icon",
      defaultValue: "MXLightkeeper, backlight \(status.localizedTitle.lowercased())",
      comment: "Accessibility label for the menu bar icon"
    )
  }

  static func batteryTooltip(relativeTime: String) -> String {
    localized(
      "tooltip.battery_updated",
      defaultValue: "Updated \(relativeTime)",
      comment: "Tooltip showing when battery info was last refreshed"
    )
  }

  static func receiverAccessibility(_ label: String) -> String {
    localized(
      "accessibility.receiver_value",
      defaultValue: "Receiver, \(label)",
      comment: "Accessibility label for the receiver row"
    )
  }

  static func keyboardAccessibility(_ label: String) -> String {
    localized(
      "accessibility.keyboard_value",
      defaultValue: "Keyboard, \(label)",
      comment: "Accessibility label for the keyboard row"
    )
  }

  static func batteryAccessibility(_ label: String) -> String {
    localized(
      "accessibility.battery_value",
      defaultValue: "Battery, \(label)",
      comment: "Accessibility label for the battery row"
    )
  }

  static func receiverLabel(kind: String, isAlpha: Bool) -> String {
    let alphaText = isAlpha ? String(localized: alphaSuffix) : ""

    return localized(
      "receiver.label",
      defaultValue: "\(kind) receiver \(alphaText)",
      comment: "Receiver label shown in the menu"
    )
    .trimmingCharacters(in: .whitespaces)
  }

  static func keyboardLabel(name: String, isAlpha: Bool) -> String {
    guard isAlpha else { return name }

    return localized(
      "keyboard.label.alpha",
      defaultValue: "\(name) \(String(localized: alphaSuffix))",
      comment: "Keyboard label for alpha-supported keyboards"
    )
  }

  static func batteryChargingLabel(level: Int) -> String {
    localized(
      "battery.label.charging",
      defaultValue: "\(level)% · Charging",
      comment: "Battery label when charging"
    )
  }

  static func batteryPercentLabel(level: Int) -> String {
    localized(
      "battery.label.percent",
      defaultValue: "\(level)%",
      comment: "Battery percentage label"
    )
  }

  static func batteryAccessibilityCharging(level: Int) -> String {
    localized(
      "battery.accessibility.charging",
      defaultValue: "\(level) percent, charging",
      comment: "Accessibility battery label when charging"
    )
  }

  static func batteryAccessibilityPercent(level: Int) -> String {
    localized(
      "battery.accessibility.percent",
      defaultValue: "\(level) percent",
      comment: "Accessibility battery percentage label"
    )
  }

  static func statusSubtitle(_ status: AppStatus, locale: Locale? = nil) -> String {
    switch status {
    case .active:
      return localized("status.subtitle.active", defaultValue: "Will keep backlight on", locale: locale)
    case .disabled:
      return localized("status.subtitle.disabled", defaultValue: "Will let keyboard manage backlight automatically", locale: locale)
    case .waiting:
      return localized("status.subtitle.waiting", defaultValue: "Looking for a compatible receiver", locale: locale)
    case .degraded:
      return localized("status.subtitle.degraded", defaultValue: "Cannot find a compatible receiver", locale: locale)
    }
  }

  static func statusTitle(_ status: AppStatus, locale: Locale? = nil) -> String {
    switch status {
    case .disabled:
      return localized("status.title.disabled", defaultValue: "Off", locale: locale)
    case .waiting:
      return localized("status.title.waiting", defaultValue: "Waiting", locale: locale)
    case .active:
      return localized("status.title.active", defaultValue: "On", locale: locale)
    case .degraded:
      return localized("status.title.degraded", defaultValue: "Reconnecting", locale: locale)
    }
  }

  static var keepBacklightOnText: String {
    localized("toggle.keep_backlight_on", defaultValue: "Keep backlight on")
  }

  static var noReceiverTitleText: String {
    localized("empty.no_receiver.title", defaultValue: "No Logitech receiver detected")
  }

  static var noReceiverMessageText: String {
    localized("empty.no_receiver.message", defaultValue: "Plug in your Unifying receiver to get started.")
  }

  static var launchAtLoginText: String {
    localized("label.launch_at_login", defaultValue: "Launch at login")
  }

  static var quitText: String {
    localized("action.quit", defaultValue: "Quit")
  }

  static var batteryStatusText: String {
    localized("tooltip.battery_status", defaultValue: "Battery status")
  }

  static var noReceiverConnectedText: String {
    localized("receiver.none", defaultValue: "No receiver connected")
  }

  static var chargedText: String {
    localized("battery.charged", defaultValue: "Charged")
  }

  static var criticalText: String {
    localized("battery.critical", defaultValue: "Critical")
  }
}

extension AppStatus {
  var localizedTitle: String {
    AppStrings.statusTitle(self)
  }

  var localizedSubtitle: String {
    AppStrings.statusSubtitle(self)
  }
}
