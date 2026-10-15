# Research and implementation decisions

Inspected 2026-10-15, with local source checkouts retained under the development
workspace's ignored `work/references/` directory (not distributed).

| Reference | Finding and decision |
| --- | --- |
| https://g-helper.com/ and https://github.com/seerge/g-helper | Windows control scope and compact UI inspiration. GPL-3.0 code not copied. No feature parity claim. |
| https://github.com/utajum/g-helper-linux and https://g-helper-linux.elevatech.xyz/ | Unofficial Linux standalone application with wider hardware scope and direct hardware backends. Research reference; not installed or embedded because this task needs a native shell popup and existing service ownership. GPL-3.0 source not copied. |
| https://github.com/randallyash/omarchy-z13-power | Existing GZ302 power-oriented plugin, GPL-3.0-or-later. Broad TDP/fan/undervolt scope depends on additional tooling. No code copied or tuning presets adopted. |
| https://github.com/davydotcom/omarchy-z13flow-plugin | MIT native lights popup closely matches the supplied screenshot. Uses z13ctl. Layout informed this original implementation; no ROG artwork or code vendored. Use the already active asusd instead of competing HID ownership. |
| https://asus-linux.org/ | Established ASUS Linux service/backend project. Local installed asusctl 6.4 API and live D-Bus introspection are authoritative for this build. Old web examples use older CLI syntax. |
| https://wiki.archlinux.org/title/Asusctl | Requested reference, but web retrieval returned an anti-bot page. Not used as implementation authority. |
| https://www.reddit.com/r/linux_gaming/comments/1r9en2s/ghelper_for_linux_a_gaming_tool_for_gaming/ | Community discussion used for discovery only, not technical claims. |

## Local capabilities and ownership

- Model: ROG Flow Z13 GZ302EA. Omarchy 4.0.4-1; Hyprland 0.56.2;
  Quickshell 0.3.1-1; asusctl 6.4.0-2; power-profiles-daemon 0.30-1.
- asusd already active, with keyboard 1a30 and rear lightbar 18c6 Aura objects.
  Both report brightness 0–3 and modes 0, 1, 10. Aura effects serialize as
  `(mode, zone, color1, color2, speed, direction)` in this API version.
- Battery BAT0 exposes `charge_control_end_threshold`; asusctl saves its limit.
- PPD exposes performance/balanced/power-saver using amd_pstate and
  platform_profile. The ASUS configuration also changes profiles on AC events;
  use PPD for user selection and disclose AC behavior instead of silently
  changing either daemon's configuration.
- asusctl can read custom fan curve support on this device. Existing CPU/GPU
  custom curves are disabled; firmware manages fans. First release exposes RPM
  and temperatures, deferring edits until curve behavior receives separate
  validation. Power-limit firmware attributes exist, but existence alone is not
  sufficient evidence to ship a power/undervolt tuning UI.
- No dGPU/MUX switching backend is used in this version. Initial device has an
  AMD integrated GPU. Do not advertise NVIDIA or universal ROG support.
- No OpenRGB, G-Helper Linux, root daemon or permanent sudo permission added.
  asusd continues owning keyboard and battery writes. Rear-bar exception below.

## Physical button

Coordinated 25-second capture of only built-in input sources recorded four
presses: every press used Asus WMI hotkeys, MSC_SCAN 16776961 (`0xffff01`),
KEY_PROG3 202 press/release. The recurring phantom scan is 233 (`0xe9`),
KEY_UNKNOWN 240. No ASUS USB/N-KEY button event was observed during that test.
The compositor's existing disabled WMI rule is preserved. An optional user
listener requires both the verified scan and press in one SYN_REPORT frame,
debounces at 400ms and ignores phantom events without forwarding input.

## Shell implementation

Read installed `plugins.md`, `hyprland.md`, shell plugin README, Panel,
KeyboardPanel, PanelHero, ButtonGroup, ToggleSwitch, Color/Style and installed
plugin examples. All packaged `/usr/share/omarchy` files inspected read-only.
User files installed only under `.config/omarchy/plugins/rog-helper`, plus the
optional listener unit and narrowly matched udev rule. No Hyprland edit needed.

## Publication process

The former HANCORE-linux marketplace repository redirects to
https://github.com/omacom/omarchy-plugin-marketplace. Read its current
`SUBMISSION.md`, submission issue template and README. Required: public GitHub
repository, root manifest/README/license, globally unique ID, install/remove
instructions, category and 1–3 permitted tags, ownership checklist. A submission
issue initiates exact-commit compatibility/security checks. Only directory
maintainers can approve listing; submitting is not equivalent to acceptance.

## Rear-bar validation changed the backend decision

The owner confirmed keyboard RGB worked, but the rear bar stayed dark despite
successful D-Bus readbacks and asusd power flags being enabled. The z13ctl
protocol documentation identifies a Z13 dynamic-lighting activation packet and
zone-1 addressing that the tested asusd path did not visibly apply. Do not
interpret accepted D-Bus settings as physical feature verification.

A targeted upstream z13ctl **v1.4.2** CLI test lit the rear bar. The owner then
confirmed red followed by blue matched the requested physical colors. The
release archive SHA-256 was checked against upstream `checksums.txt` before
execution. The standalone binary is installed separately with its Apache-2.0
license; no z13ctl source is copied into the plugin. Only GZ302EA rear-bar actions
use the explicit `--device lightbar` one-shot path. No z13ctl daemon, broad setup
rules or fan/TDP operations are used. State is last applied, not readback, and
resume/reboot persistence is not claimed. asusd may still initialize that device
at startup/resume; no background competing writer was enabled.
