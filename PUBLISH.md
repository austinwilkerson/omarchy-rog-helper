# Marketplace submission

Title: **[Plugin]: ROG Helper**

Target: https://github.com/omacom/omarchy-plugin-marketplace

The owner authorized public GitHub publication and marketplace submission.
This package is original MIT source, and its preview contains only its own UI.
No reference screenshots, ROG marks, input captures, credentials or logs are
included. Source ownership and publication authorization are recorded in the
build conversation. Marketplace review remains independent and commit-specific.

Use the following issue body with the existing authenticated GitHub CLI after
pushing the validated commit. Follow the current marketplace SUBMISSION.md if
requirements change.

### Repository URL

https://github.com/austinwilkerson/omarchy-rog-helper

### Category

Hardware

### Tags

bar, quickshell, power-management

### Suggest a missing tag

_No response_

### Maintainer notes

Native Omarchy shell popup, initially tested on ASUS ROG Flow Z13 GZ302EA only.
Keyboard and battery use existing asusd/asusctl; profiles use power-profiles-daemon.
The GZ302EA rear lightbar uses optional one-shot z13ctl calls because asusd 6.4
accepted writes but did not light it. The owner verified keyboard changes,
rear-bar red/blue and physical ROG-button popup toggling. Profiles and battery
limits passed readback checks. Eight tests cover validation and backend routing.

Optional installers add model-specific uaccess rules and a user button-listener
service; no sudoers change, input-group membership, root daemon, shell source
patches or z13ctl tuning daemon. Existing Hyprland WMI suppression is preserved.
The listener accepts only verified scan 0xffff01 / KEY_PROG3 and ignores the
recurring phantom scan. Dependency versions, removal steps, control ownership,
last-applied rear-bar state and untested resume/reboot/other-model behavior are
documented. Custom fan curves, undervolting, TDP tuning and GPU switching are
not shipped. Please review the optional hardware/input permissions explicitly.

### Submission checklist

- [x] The repository is public and contains installation and removal instructions.
- [x] I have documented the plugin license and any external dependencies.
- [x] I confirm that I own or have permission to submit this plugin and its preview assets.
- [x] The plugin does not overwrite user configuration without explicit consent.
- [x] I understand that approval is for listing and is not a security review.
