#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
[[ "$(cat /sys/class/dmi/id/product_name)" == *GZ302EA* ]] || { echo 'Only GZ302EA fallback has been verified.' >&2; exit 1; }
command -v z13ctl >/dev/null || { echo 'Install z13ctl first; see README.' >&2; exit 1; }
sudo install -m 644 "$plugin_dir/scripts/70-rog-helper-lightbar.rules" /etc/udev/rules.d/70-rog-helper-lightbar.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=hidraw --action=change
