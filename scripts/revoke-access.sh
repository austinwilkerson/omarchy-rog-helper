#!/usr/bin/env bash
# Called by the optional component removers. Clear cached udev tags and ACLs.
set -euo pipefail
component="${1:-}"
[[ "$component" == button || "$component" == lightbar ]] || exit 2
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
rule_name="70-rog-helper-${component}.rules"
subsystem=input
[[ "$component" != lightbar ]] || subsystem=hidraw
sudo rm -f "/etc/udev/rules.d/$rule_name"
# udev retains tags in its database. Apply a matching subtractive rule once.
cleanup_file="$(mktemp)"
trap 'rm -f "$cleanup_file"' EXIT
sed 's/TAG+="uaccess"/TAG-="uaccess"/' "$plugin_dir/scripts/$rule_name" > "$cleanup_file"
sudo install -Dm 644 "$cleanup_file" "/run/udev/rules.d/$rule_name"
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match="$subsystem" --action=change
sudo udevadm settle
sudo rm -f "/run/udev/rules.d/$rule_name"
sudo udevadm control --reload-rules
# Removing the tag does not remove an ACL already installed on the device node.
task_user_uid="$(id -u)"
while IFS= read -r device_node; do
    [[ -n "$device_node" ]] || continue
    sudo setfacl -x "u:$task_user_uid" "$device_node"
done < <(python3 - "$component" <<'PYTHON'
import glob,sys
from pathlib import Path
if 'GZ302EA' not in Path('/sys/class/dmi/id/product_name').read_text():
    raise SystemExit(0)
if sys.argv[1]=='button':
    for name in glob.glob('/sys/class/input/event*/device/name'):
        if Path(name).read_text().strip()=='Asus WMI hotkeys':
            print('/dev/input/'+Path(name).parents[1].name)
else:
    for node in glob.glob('/sys/class/hidraw/hidraw*'):
        try: info=Path(node+'/device/uevent').read_text()
        except OSError: continue
        if 'HID_ID=0003:00000B05:000018C6' in info:
            print('/dev/'+Path(node).name)
PYTHON
)
