# MXLightkeeper

A macOS menu bar utility that periodically refreshes your Logitech MX Keys keyboard's backlight to help keep it on.

![MXLightkeeper menu bar preview showing the backlight toggle, receiver status, keyboard model, battery state, and launch-at-login option](HERO.png)

> Verified on MX Keys for Mac over a Logitech Unifying receiver. Bolt receivers and other MX Keys variants are enabled too, but stay labeled `(alpha)` until confirmed on real hardware.

## Why

The MX Keys switches off its own backlight after a short period of inactivity. When the keyboard is permanently plugged into power and used with a USB Unifying or Bolt receiver, that delay can be frustrating in a dark environment. MXLightkeeper periodically refreshes the backlight through the Logitech HID++ protocol while the app is running in your logged-in macOS session.

This is a macOS port of the Windows [Backlighter](https://github.com/crsten/backlighter) utility. Its keep-alive loop uses the legacy pulse pair; the companion CLI also provides structured HID++ `BACKLIGHT2` reads and setters.

## Install

Build the `.app` bundle:

```bash
chmod +x scripts/build-app-bundle.sh
scripts/build-app-bundle.sh
cp -R dist/MXLightkeeper.app /Applications/
```

Open it from `/Applications`, toggle **Keep backlight on**, and optionally enable **Launch at login**.

## Terminal tool

`mxlightkeeper` is a companion CLI for scripting or one-off control. The menu bar app and CLI both call the same `MXLightkeeperCore` engine rather than maintaining separate HID implementations.

```bash
swift build -c release --product mxlightkeeper
cp .build/release/mxlightkeeper /usr/local/bin/

mxlightkeeper read                 # print current BACKLIGHT2 state
mxlightkeeper on                   # turn backlight on
mxlightkeeper off                  # turn backlight off
mxlightkeeper manual --level 7     # set manual brightness 1-7
mxlightkeeper keep                 # run keep-alive loop until Ctrl-C
```

The keep-alive guard normally refuses to start `mxlightkeeper keep` when the app or another CLI keeper holds its lock. The current file-based guard has a concurrent-start race documented in the [system design](docs/system-design.md#what-current-feedback-proves).

The guard currently covers keep-alive loops only. Stop the keeper before one-shot writes such as `off` or `manual`. Turning off the app's **Keep backlight on** toggle stops refreshes; it does not send `mxlightkeeper off`.

## Requirements

- macOS 15+
- A Logitech Unifying (`0x046d:0xc52b`) or Bolt (`0x046d:0xc548`, alpha) receiver paired with an MX Keys family keyboard
- To build from source: Xcode 16.4+ / Swift 6+

Only "MX Keys for Mac" on Unifying has been end-to-end verified. Other MX Keys variants, Bolt receiver paths, and macOS 15 Sequoia support are enabled, but shown as `(alpha)` until confirmed on real hardware.

## How it works

The matched Logitech receiver exposes a vendor-specific HID interface on usage page `0xFF00`. Both frontends use the same core controller. Keep-alive sends the legacy `offSignal` / `onSignal` pulse pair with a 50 ms gap, immediately and then every 180 seconds. Structured CLI reads and setters use `BACKLIGHT2 (0x1982)`, currently at the reference hardware's fixed feature index `0x0b` and receiver slot `0x01`.

In parallel, every 60 seconds the app polls `DEVICE_NAME (0x0005)` and `BATTERY_STATUS (0x1000)` to show the keyboard model and charge state. The same poll re-enumerates receivers to notice unplug/replug. It runs regardless of whether the keep-alive toggle is on; CLI `keep` does not run this app polling loop.

The app follows the macOS system language and supports English, French, Spanish, German, Brazilian Portuguese, Simplified Chinese, Hindi, and Arabic, including RTL layout. It has no in-app language override.

Current status reflects receiver acquisition and keeper startup, not confirmation that the LEDs are lit; refresh errors are not yet surfaced. See the [system design](docs/system-design.md) for exact behavior and limitations, and the [protocol notes](docs/reverse-engineering.md) for hardware observations.

## Layout

- `Sources/MXLightkeeperCore/` — receiver matching, HID++ types, `BACKLIGHT2` codec, shared controller, exclusive keep-alive loop
- `Sources/MXLightkeeperApp/` — SwiftUI menu bar frontend
- `Sources/mxlightkeeper/` — terminal frontend over the shared core
- `Tests/MXLightkeeperCoreTests/` — unit tests for the core module
- `Packaging/` — `Info.plist` and pre-rendered `AppIcon.icns`
- `scripts/build-app-bundle.sh` — builds and signs the `.app` bundle

## Development

Start with [AGENTS.md](AGENTS.md) for task routing or the [development guide](docs/development.md) for checks and diagnosis. The [agent-operation plan](docs/plans/2026-09-16-agent-operation.md) specifies future observable outcomes, explicit targeting, and machine-readable CLI control. Proposed interfaces in that plan are not available commands.

## Permissions and security

MXLightkeeper talks to the Logitech receiver's vendor-specific HID interface only (usage page `0xFF00`, not a keyboard interface). It does not read keystrokes, request Accessibility or Input Monitoring, or make any network calls. It does query the keyboard for its model name, battery level, and charging state via HID++ — all of which are read on the same vendor-specific interface and do not trigger TCC prompts.

**First-time launch.** The released `.app` is ad-hoc signed, not notarized. If you build from source locally (`scripts/build-app-bundle.sh`) Gatekeeper is fine. If you downloaded a prebuilt `.app`, right-click -> **Open** the first time, or run:

```bash
xattr -dr com.apple.quarantine /Applications/MXLightkeeper.app
```

**Login items.** Enabling "Launch at login" shows a standard macOS notification and adds MXLightkeeper to **System Settings → General → Login Items**.

**Terminal tool.** All `mxlightkeeper` subcommands use the same shared core and operate on the receiver's vendor-specific HID interface (usage page `0xFF00`), which macOS does not classify as keyboard input. No TCC prompts are expected. `mxlightkeeper keep` also respects the single-owner keep-alive guard and refuses to start if another MXLightkeeper process already owns the loop.

## License

MIT — see [`LICENSE`](LICENSE).

## Support

If this saves you from staring at a dim keyboard, you can [buy me a coffee](https://ko-fi.com/casualdeveloper11).
