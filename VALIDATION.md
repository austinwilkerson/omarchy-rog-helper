# Validation — 2026-10-15

Initial hardware only: ASUS ROG Flow Z13 **GZ302EA**, Linux/Omarchy desktop.
No other models tested. Version details and backend ownership: [RESEARCH.md](RESEARCH.md).

## Passed

- Omarchy manifest validation; plugin discovered, enabled and rendered in the
  running shell. Native layer-shell popup, not a standalone/tiled application.
- Current theme colors, fonts, native border/control styling, compact 7-column
  color grid and separate sections inspected in the running popup.
- Coordinated four physical button presses identified the real input source,
  scan and key. Owner confirmed installed filtered listener toggles correctly.
- Performance, balanced, power-saver: selected through powerprofilesctl and
  read back after each write.
- Both asusd Aura devices: low brightness, RGB green, Static/Breathe/Pulse
  changes read back through D-Bus. Service readback is not itself visual proof
  of light output; owner confirmation is tracked separately below.
- Battery limit 80%: written through asusctl, confirmed in kernel sysfs.
- Hardware test restores original profile, Aura effects, both brightness levels
  and original 100% charge limit in a finally block.
- Standard-library tests: verified button frame, phantom/release rejection,
  missing backend degradation, invalid paths/modes/colors/charge/profile
  rejection, effect serialization regression (mode and zone order).
- Existing `asus-wmi-hotkeys` disabled override preserved; `hyprctl configerrors`
  empty after installation. No Hyprland edit or reboot performed.

## Owner confirmation and remaining boundaries

- Owner confirmed keyboard color changes through asusd and physical rear-bar
  red/blue through z13ctl. The rear bar did not respond to the initial asusd
  path, so that path is replaced on GZ302EA; D-Bus-only results above are
  diagnostic history, not proof of rear-bar functionality.
- No suspend/resume, reboot persistence, battery transition or second-model
  verification yet. Persistence is delegated to existing asusd and the user
  service's normal startup behavior; these scenarios are not claimed tested.
- No custom fan-curve writes, undervolting, power-limit tuning or GPU switching
  shipped. Sensor readings and daemon capabilities do not prove these features.
- Theme values are reactive native shell bindings. No forced theme change was
  performed while the owner was working.
- GitHub publication and directory listing are separate from local validation;
  directory approval remains the maintainers' decision.

Final backend test suite: **8 tests passed**, including explicit rear-bar routing,
model gating and preserving last-successful state when z13ctl fails. The optional
button listener was removed and reinstalled to check installation/removal behavior.

Permission removal was checked on both device nodes. Removing udev rules/tags
alone retained the active ACL; the final remover explicitly revokes the current
user's ACL on the matching model-specific nodes. Empty user ACLs were confirmed
before reinstalling both optional components.

Final source was also validated after a clean Omarchy shell restart, including
the native header toggle. No plugin load or QML runtime errors were observed.
