# Reverse-Engineering Notes

How the Logitech MX Keys backlight control was pinned down for this port. Every claim below was verified on real hardware through the Unifying receiver's vendor-specific HID interface.

## Starting point

The original Windows [Backlighter](https://github.com/crsten/backlighter) utility targets the Logitech Unifying receiver at `0x046d:0xc52b`, matching the vendor usage page `0xFF00` / `65280`, and sends two 7-byte reports every 180 seconds:

- `off_signal = [0x10, 0x01, 0x0b, 0x1f, 0x00, 0x00, 0xff]`
- `on_signal  = [0x10, 0x01, 0x0b, 0x1f, 0x01, 0x00, 0xff]`

This works as a keep-alive nudge but is not the real on/off setter. The goal of this port was to find the actual backlight-control feature and talk to it directly.

## macOS access

- `system_profiler` and `ioreg` show the Logitech `USB Receiver` at `0x046d:0xc52b`.
- `hidutil list` exposes a vendor-specific HID device on usage page `0xFF00`, usage `1`.
- The vendor-specific interface has a 98-byte report descriptor with report IDs `0x10`, `0x11`, `0x20`, and `0x21`.
- `0x10` is a 6-byte output/input family; `0x11` is a 19-byte output/input family, both on usage page `0xFF00`.

IOHID can reach this interface on macOS without triggering Input Monitoring, provided the `IOHIDManager` is set up to match the specific vendor-specific interface rather than all HID devices.

## Passive capture

Watching the receiver's incoming reports while cross-referencing with another macOS utility toggling keyboard backlight produced `reportID 0x11` packets of length 20, clustered around `11 01 0b …`. Two state families were observed, matching the user-visible on / off transitions.

Sample packets captured around backlight changes:

- `11 01 0b 1c 00 00 00 …`
- `11 01 0b 0d 01 00 05 …`
- `11 01 0b 2e 08 07 04 …`
- `11 01 0b 1f 00 00 00 …`
- `11 01 0b 01 00 00 05 …`
- `11 01 0b 22 08 00 00 …`

A larger telemetry-like burst also appeared occasionally in the `11 01 08 36 …` family. Only HID traffic was observed; no third-party process code was inspected.

## Status-query decoding

Sending `10 01 0b 1f 01 00 ff` reliably elicits `reportID 0x11` state packets. The interesting suffix is `… 08 <level> <mode>`:

- `08 00 00` — backlight off / disabled
- `08 01 04` — backlight on, brightness level 1
- `08 06 04` — backlight on, brightness level 6
- `08 07 04` — backlight on, brightness level 7

So `10 01 0b 1f 01 00 ff` is a status query, not a setter.

## HID++ feature discovery

The `0x0b` byte in those packets is a runtime-discovered feature index, not a globally fixed opcode. HID++ root feature discovery works as follows:

- Root feature ID `0x0000` is fixed at feature index `0x00`.
- Root function `0x00` (`getFeatureID`) takes the target feature ID and returns its device-specific feature index.

A feature-discovery pass against this receiver resolved the following map:

- `Root (0x0000) -> 0x00`
- `FeatureSet (0x0001) -> 0x01`
- `DeviceInfo (0x0003) -> 0x02`
- `DeviceName (0x0005) -> 0x03`
- `BatteryStatus (0x1000) -> 0x07`
- `ReprogControlsV4 (0x1b04) -> 0x08`
- `ChangeHost (0x1814) -> 0x09`
- `Backlight2 (0x1982) -> 0x0b`

`Backlight (0x1981)` and `Backlight3 (0x1983)` are not present on this device. The `… 0b …` packets from earlier captures are HID++ calls to the real `BACKLIGHT2` feature.

## BACKLIGHT2 semantics

Solaar's public [`hidpp20.py`](https://github.com/pwr-Solaar/Solaar/blob/master/lib/logitech_receiver/hidpp20.py) documents `BACKLIGHT2 (0x1982)`:

- `feature_request(BACKLIGHT2, 0x00)` reads the current backlight struct.
- `feature_request(BACKLIGHT2, 0x10, data_bytes)` applies a full backlight struct.

Decoded layout:

- `enabled` (1 byte)
- `options` (1 byte)
- `supported` (1 byte)
- `effects` (2 bytes)
- `level` (1 byte)
- `dho` / `dhi` / `dpow` (three 2-byte durations)

For write requests, the payload is:

- `enabled`
- `options`
- `0xFF`
- `level` or `0`
- `dho`
- `dhi`
- `dpow`

Solaar also notes an MX Keys S-specific extension packet, which suggests some Logitech keyboards require more than the basic short form.

## What the shipping app uses

Writing `BACKLIGHT2.enabled = 0x00` or `0x01` through the structured `BACKLIGHT2` write flips the real keyboard backlight state immediately on the MX Keys target of this port. The keep-alive loop re-sends the `enabled = 1` struct every 180 seconds while preserving the user's existing brightness level and mode.

Replaying the legacy Backlighter raw pulse (`10 01 0b 1f 00 00 ff` then `10 01 0b 1f 01 00 ff`) does not visibly change the light when the keyboard is already on. It behaves like a transient nudge, not a real setter.

## Bolt note

A community report (Reddit) claimed the Windows matcher also worked for Bolt after changing `productId` to `0xc548`, keeping `vendorId 0x046d`, and using usage page `65280`. This is treated as a research lead, not proof. The `mxlightkeeper` CLI and menu bar app include a `--bolt` / experimental toggle for that matcher, but it is disabled by default until verified on real Bolt hardware.

## Other exposed features

Beyond `BACKLIGHT2`, the shipping app uses two additional HID++ features the MX Keys exposes:

- `DEVICE_NAME (0x0005)` — returns the keyboard model name as a string (e.g. `"MX Keys for Mac"`). Feature-set discovery resolves this to index `0x03` on the MX Keys. Read via `fn 0x00` (`getDeviceNameCount`) followed by `fn 0x01` (`getDeviceName`) in 14-byte chunks until the full length is retrieved.
- `BATTERY_STATUS (0x1000)` — returns three bytes: discharge level (`0–100`), next reportable level, and a power-status enum: `discharging`, `recharging`, `almost-full`, `charging-complete`, `wired-charging`, `critical`, `invalid-battery`, `thermal-error`. Feature-set discovery resolves this to index `0x07`. Read via `fn 0x00` (`getBatteryLevelStatus`).

Both are read every 60 seconds in a background task that runs regardless of the keep-alive toggle, and the same poll re-enumerates the receiver so unplug/replug is reflected in the UI.

## TCC and the vendor-specific interface

`IOHIDDeviceRegisterInputReportCallback` on the Logitech Unifying receiver's vendor-specific HID interface (usage page `0xFF00`) does **not** trigger macOS's Input Monitoring permission prompt. Verified empirically on macOS 26 by shipping a release build that registers the callback from the app's own process and observing no prompt.

Two things must be true for this to hold:

1. The `IOHIDManager` uses `IOHIDManagerSetDeviceMatchingMultiple` with an explicit match on `vendorID=0x046d`, `productID=0xc52b`, `usagePage=0xFF00`, `usage=1` — not `nil` (which would match all HID devices, including keyboards, and would trigger Input Monitoring).
2. The callback is registered on the specific matched device, not broadly on the manager.

With both in place, features like `DEVICE_NAME` and `BATTERY_STATUS` can be read from the shipping app without special entitlements or user permission grants.

## Discipline

- Only add newly verified receiver IDs, usage pages, descriptor details, or report observations here.
- Do not promote anecdotal community reports to "verified" without reproducing them.
