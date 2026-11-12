# Validation — 2026-10-15

Initial hardware only: ASUS ROG Flow Z13 **GZ302EA**, Linux/Omarchy desktop.
No other models tested. Version details and backend ownership: [RESEARCH.md](RESEARCH.md).

## Runtime state audit

| Workflow | Owner | States and transition rules |
| --- | --- | --- |
| Popup and controls | [Panel.qml](Panel.qml) | Opening starts a status read and periodic polling. Page and lighting-zone selection choose which controls consume the snapshot. |
| Hardware requests | [Panel.qml](Panel.qml) | Idle → reading or applying. A write arriving during a read queues once and supersedes that read. Every write enters confirming before controls unlock. Action failures and status failures have separate lifetimes. |
| Color entry | [LedColorControl.qml](LedColorControl.qml), [ColorPicker.qml](ColorPicker.qml) | Custom and Swatches share the selected zone. A picker gesture commits once on release. Changing the zone invalidates the gesture. |
| Keyboard color source | [backend.py](backend.py) | Manual color clears the saved theme role. Following a role reapplies its current color after Omarchy's theme hook. The dedicated theme preset remains a distinct role. |
| Rear lightbar | [backend.py](backend.py) | Availability depends on the model, access and z13ctl. The last applied setting advances after z13ctl succeeds under the lightbar lock. |
| Function/media keys | [fnlock.py](fnlock.py), [fnlock.lua](fnlock.lua) | Setup and attachment determine availability. Changes serialize, verify the bindings and roll back on failure. Startup and hotplug restore the saved mode. |
| Optional display refresh | [PowerService.qml](PowerService.qml), [power_state.py](power_state.py) | Disabled or enabled. Power changes and periodic checks coalesce before applying a supported internal display mode. The backend checks the persisted policy under lock. |
| Battery limit and power profile | [backend.py](backend.py) | The relevant system services own the persistent limit and profile. asusd owns the temporary 100% charge and restores the normal limit on AC disconnect. |
| Optional side button | [button_listener.py](button_listener.py) | Discover → read a complete input frame → toggle on the matching press. Disconnect returns to discovery. |

`bash tests/check-qml.sh` uses a fake hardware backend to reproduce a write
queued during a read, a duplicate click, a successful readback and an action
failure followed by successful readback. It also tests zone changes during a
color gesture.

For 0.3.1 on Omarchy Stable 4.5, the installed panel code queued a keyboard
brightness change behind an in-flight read and confirmed the new hardware
level. A second request restored the original level, which was confirmed
independently through the backend.

## Passed

For 0.3.2, the backend tests cover bounded saved-state and explicit clipboard
reads, including cancellation of an idle clipboard helper. The QML fixture
checks that a failed prerequisite read discards a queued action, preserves the
last good snapshot, and allows a later refresh. A temporary XDG configuration
with stub service and access commands verified custom-path unit removal and
cleanup routing.

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

## 0.1.1 — Edge theme compatibility

On Omarchy Edge with Qt 6.12 / Quickshell 0.3.2, unqualified `Color` references
failed to resolve the Omarchy singleton. Theme and style references now use the
explicit `Commons` namespace, consistent with the installed shell components.
An isolated Wayland instance loaded the complete panel without color binding
errors and verified that an in-memory popup text-color change updates the panel.
This check does not change desktop theme files or restart the running shell.
The original stable hardware results above remain the hardware validation scope.

After the Edge upgrade completed and the desktop shell restarted, the installed
0.1.1 popup was opened and visually inspected with the active theme. Header,
text, button fills, borders and swatches rendered correctly. The restarted
shell's logs contained no ROG Helper QML errors. Read-only backend checks found
both lighting zones, all three power profiles and four sensor readings without
errors. The button listener remained active and Hyprland reported no config
errors. No additional hardware-setting changes or reboot were performed.

## 0.1.4 — Stable 4.5 compatibility

Verified on 2026-11-05 with Omarchy channel `stable`, package `4.5.0-3`,
Hyprland 0.56.2 and Quickshell 0.3.2 on the same GZ302EA. All eight backend
tests and the isolated panel/theme/picker/zone-routing fixture pass. Read-only
backend checks report both lighting zones, power profiles, sensors and the
battery charge limit without backend errors. The installed button service is
active. This compatibility update does not change hardware settings or expand
the physical hardware validation scope above.

## 0.2.0 — Software Fn Lock

Local checks on the GZ302EA with Omarchy Stable 4.5.0-3 and Hyprland 0.56.2:

- Generated and compiled media keymaps for US with Omarchy's Compose options
  and German `nodeadkeys` with `compose:caps`. The German test checks the
  original letter and Compose definitions alongside the remapped keys.
- Migrated the existing Media keys mode. Both Z13 keyboard interfaces reported
  the generated keymap and Hyprland reported one Fn+Esc binding.
- Selected Function keys and toggled back through the installed backend.
  Both interfaces reported the matching live map and saved state each time.
  A Hyprland reload reapplied Media keys without configuration errors.
- Reran setup, removed it and compared the restored input and bindings files
  to the original backups byte for byte. Reinstalled and confirmed the saved
  mode, WMI suppression and active side-button service.
- Backend tests cover failed live changes and config reload rollback.
  The existing Quickshell theme and color checks pass.

The owner confirmed the guided physical test of Fn+Esc, the panel selector,
F6 screenshot capture, F9 Display and F11 keyboard backlight in Media keys mode.
In follow-up use, the owner reported that the media keys were working and
confirmed dictation with F9 in Function keys mode. They also reported access
to the mode selector from the side-button popup.

The owner detached and reattached the Z13 keyboard and confirmed that its
lighting and media keys returned as expected. Super worked without the old
scratchpad behavior, and the selected mode survived a reboot. The installed
backend reported an active Media keys map, exactly one Fn+Esc binding, and no
backend or Hyprland configuration errors after reboot. The RK68 Plus was
unavailable for a physical check. The configuration and keymap are scoped to
the two verified Z13 keyboard interfaces.

On 2026-11-11, the owner tested both keyboards together on Shammah. The Z13's
F2 and F3 controlled volume in Media keys mode. The Bluetooth RK68 Plus
controlled volume after enabling its media layer with Fn+Left Ctrl and
continued to do so after the Z13 switched to Function keys mode. The owner
also confirmed that Z13 F9 dictation worked in Function keys mode. Hyprland
reported the standard English (US) keymap on the RK68 Plus throughout.

## 0.3.0 — Theme, battery and display controls

The panel fixture replaces the active theme directory, confirms that Accent,
Text and Alert update, and checks the dedicated keyboard preset appears only
when supplied. Backend coverage verifies that a remembered keyboard role
is applied after the stock keyboard color and that a manual choice clears it.

On Shammah, the internal display switched between 60 Hz and 180 Hz at
2560×1600. Resolution, scale, position, transform and color management matched
the original values. The original 180 Hz rate was restored. The isolated
Quickshell service test stayed idle until opt-in and reacted when the preference
file first appeared.

Read-only checks found battery power, full and design capacity, and the three
firmware power limits. The live one-shot test started at an 80% charge cap,
raised it to 100% with AC connected, and verified that asusd 6.5.0 restored
80% after the owner unplugged the charger.
