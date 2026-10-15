# ROG Helper for Omarchy

A compact native Omarchy shell popup for ASUS laptop controls. Initially tested
on **ROG Flow Z13 GZ302EA (2025)**, Omarchy 4.0.4, Hyprland 0.56.2,
Quickshell 0.3.1 and asusctl 6.4.0. This is an early community plugin, not a claim
of universal ROG support or G-Helper feature parity.

![ROG Helper Lights, Power and Battery panels](preview.png)

[Lights screenshot](docs/screenshots/lights.png) · [Power screenshot](docs/screenshots/power.png) · [Battery screenshot](docs/screenshots/battery.png)

## Controls

- **Lights:** independent keyboard and rear lightbar, off/low/medium/high,
  supported effects and RGB swatches. Keyboard state comes from asusd; the
  GZ302EA rear lightbar uses one-shot z13ctl calls, with last-applied state clearly
  labeled. No second RGB daemon is started.
- **Power:** available power-profiles-daemon profiles, temperature and fan RPM.
  Firmware controls the fan curves. No custom fan-curve editor, undervolting,
  direct power-limit writes or GPU switching in this version.
- **Battery:** 60%, 80% and 100% persistent charge limits through asusd.
- **Physical ROG button:** optional model-specific listener for the verified
  GZ302EA event. The listener ignores the recurring KEY_UNKNOWN firmware event.

The popup uses Omarchy's `Panel`, `KeyboardPanel`, `ButtonGroup`, `PanelHero`,
`Color` and `Style` APIs. It follows the active theme automatically and is a
layer-shell popup inside the existing shell process. It works with bar click,
Escape dismissal, Tab navigation and shell IPC.

## Dependencies

Install and configure dependencies through your distribution first:

- Omarchy 4 / Quickshell with the native plugin APIs above
- Python 3 (standard library only), systemd `busctl`
- `asusctl` / running `asusd` 6.4-compatible CLI and Aura D-Bus API
- `power-profiles-daemon` / `powerprofilesctl` for power profiles
- `z13ctl` 1.4.2-compatible CLI for the GZ302EA rear lightbar (optional; without
  it the rear-bar controls are disabled with an explanation)
- Optional button setup: systemd user services, udev, ACL tools (`setfacl`),
  sudo for one-time rule setup/removal

The plugin discovers Aura object paths and advertised modes/brightness at runtime;
it never assumes USB bus numbers. Other models are untested. Missing backends and
unsupported features are reported in the popup. An installed service can still
report support for a feature its firmware does not implement correctly; report
your exact model and versions before adding it to the tested list.

## Install

From the published repository, use Omarchy's plugin manager:

```sh
omarchy plugin add https://github.com/austinwilkerson/omarchy-rog-helper.git --enable
```

For a local checkout:

```sh
./scripts/install-local.sh
```

Click the bar icon, or run:

```sh
omarchy-shell shell toggle rog-helper
```

### Optional Z13 physical button

Only GZ302EA is accepted by this version. On the initial machine, pressing the
side ROG button produced `MSC_SCAN 0xffff01` and `KEY_PROG3` (202) on
**Asus WMI hotkeys**. Four physical presses were captured and the installed
listener was confirmed to toggle the popup by the owner.

```sh
~/.config/omarchy/plugins/rog-helper/scripts/install-button.sh
```

This explicitly installs `/etc/udev/rules.d/70-rog-helper-button.rules` and a
`rog-helper-button.service` user unit. The udev rule grants the active local seat
access to **only the matching model's WMI input device**; it does not add the
user to the input group. The listener runs as your user, never grabs a device,
records no input, ignores unrelated frames and invokes only the fixed shell
popup command. It reconnects when the input device changes.

On the initial machine that WMI source also emits scan `0xe9` / KEY_UNKNOWN
about every two seconds. Keep the existing Hyprland suppression:

```lua
hl.device({ name = "asus-wmi-hotkeys", enabled = false })
```

The installer does not change Hyprland. Reading evdev independently lets the
listener accept the verified button while the compositor continues to ignore
that noisy source. Do not re-enable it to use the popup. Other models need their
own coordinated event capture and verification; do not guess an event number.

### Optional GZ302EA rear lightbar

Visual testing found that asusd 6.4 reports a rear-bar device and accepts writes
without lighting it. For **GZ302EA only**, this plugin replaces that control path
with the existing [z13ctl](https://github.com/dahui/z13ctl) CLI. Install z13ctl from
its documented package/release process, then run:

```sh
~/.config/omarchy/plugins/rog-helper/scripts/install-lightbar.sh
```

The setup installs only a model/vendor/product-matched udev `uaccess` rule for the
rear-bar HID device. It does not run `z13ctl setup`, enable its daemon, modify
fans/TDP, or grant the entire input group access. The CLI invokes `--device
lightbar` explicitly, never a user-supplied hardware path.

On the initial machine the upstream v1.4.2 Linux amd64 archive was checked against
its published SHA-256 and the CLI installed at `/usr/local/bin/z13ctl`, with its
license under `/usr/local/share/licenses/z13ctl/`. No binary is bundled here.
A checksum confirms release consistency, not independent publisher identity.

Rear-bar state is **last successfully applied plugin state**, stored in
`$XDG_STATE_HOME/rog-helper/lightbar.json` (default `~/.local/state/rog-helper/`).
There is no authoritative firmware readback. Another tool or an asusd
startup/resume action may change physical state; reapply a control if needed.
The plugin does not poll-write settings or claim reboot/resume persistence.

## Control ownership and persistence

Power selection uses the already running power-profiles-daemon, also used by the
Omarchy power panel. asusd remains responsible for battery and keyboard lighting. The rear bar is
targeted through one-shot z13ctl calls on GZ302EA. Both
services were already installed on the initial machine; installation does not
change their configuration or enable a competing daemon. asusd may reapply its
configured AC/battery profile on a power transition. The popup states this and
refreshes actual state every five seconds while open. Closing it stops polling.

Avoid running another RGB or tuning utility that writes the same settings at
the same time. The installer does not stop other applications or change service
ownership. Nothing here bypasses service permissions, writes sysfs directly,
changes sudo policy or requires a reboot. The optional z13ctl backend handles its own
HID writes; this plugin does not implement hardware packets.

## Remove

Remove the optional listener **before removing its files**:

```sh
~/.config/omarchy/plugins/rog-helper/scripts/remove-button.sh
~/.config/omarchy/plugins/rog-helper/scripts/remove-lightbar.sh
omarchy plugin remove rog-helper
```

This removes the user service and both optional udev rules. z13ctl is an external
dependency and is not removed automatically. The battery and keyboard lighting
settings remain saved in asusd. Rear-bar state is left as last applied. Restore desired settings in the popup before
removing it, or use `asusctl`. Existing Hyprland hotkey suppression is preserved. To remove the manually
installed CLI on the initial machine, remove `/usr/local/bin/z13ctl` and
`/usr/local/share/licenses/z13ctl/` with sudo only if no other tool needs them.

## Validation and reporting

```sh
python3 -m unittest discover -s tests -v
omarchy plugin validate .
```

See [VALIDATION.md](VALIDATION.md) for the actual hardware results and limitations,
[RESEARCH.md](RESEARCH.md) for backend decisions and references, and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for dependency licenses.

Report model, kernel, Omarchy, asusctl versions, the failing control and its
error. Do not attach raw input captures, serial numbers or complete system logs.
Use a model-specific report; success on one Z13 does not establish other models.

## License

MIT. Independent of ASUS, Omarchy and G-Helper. No ASUS/ROG artwork is bundled.
