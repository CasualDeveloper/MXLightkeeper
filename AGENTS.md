# Working on MXLightkeeper

MXLightkeeper is a local macOS menu bar app and CLI over one HID core. Start with the relevant route below; generated builds and historical hardware notes are not the runtime specification.

## Find the owner

- Behavior, state, module boundaries, or a surprising status: [system design](docs/system-design.md).
- Commands, verification, hardware diagnosis, localization, or packaging: [development guide](docs/development.md).
- Agent-facing control improvements: [implementation plan](docs/plans/2026-09-16-agent-operation.md). Its proposed interfaces are not available commands.
- Packet semantics or hardware support evidence: [reverse-engineering notes](docs/reverse-engineering.md), then the relevant source.
- Installation and user-facing usage: [README](README.md).

## Preserve these contracts

- Both frontends use `MXLightkeeperCore`. Keep HID bytes and ownership out of the UI and CLI parser.
- Preserve the current legacy pulse keep-alive until replacement behavior is demonstrated on hardware. Structured `BACKLIGHT2` setters and the keep-alive loop are different paths.
- Distinguish enabled intent, a running task, accepted report transmission, and visible light. Current `.active` proves both pulse reports returned transport success, not physical illumination.
- Match the specific vendor HID interface. Keep unverified devices labeled alpha; compiling or decoding a fixture does not validate hardware support.
- Preserve system-language-only behavior, whole-string localization, manual RTL row ordering, and the native `MenuBarExtra` window surface. The accepted UI constraints live in the system design.

## Work and verification

Inspect the live diff before editing. Use the [verification routes](docs/development.md#verification) for the changed boundary. Hardware commands and launching the app can immediately affect a connected keyboard; build and test commands do not require one.

When a change teaches something durable, update its existing owner: a test for reproducible behavior, current docs for contracts, or the hardware notes for a scoped observation. Keep completed-work history in Git. Do not duplicate it in a task journal or depend on a machine-local memory link.
