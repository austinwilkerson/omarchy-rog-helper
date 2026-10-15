#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
[[ "$(cat /sys/class/dmi/id/product_name)" == *GZ302EA* ]] || { echo 'Only GZ302EA button mapping has been verified.' >&2; exit 1; }
# No group membership, sudo policy or Hyprland input changes.
sudo install -m 644 "$plugin_dir/scripts/70-rog-helper-button.rules" /etc/udev/rules.d/70-rog-helper-button.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input --action=change
mkdir -p "$HOME/.config/systemd/user"
python3 - "$plugin_dir" <<'PYTHON'
import sys
from pathlib import Path
# Quote systemd arguments; %% protects literal percent in expanded paths.
script=str(Path(sys.argv[1])/'button_listener.py').replace('\\','\\\\').replace('"','\\"').replace('%','%%')
unit='''[Unit]
Description=ROG Helper verified Z13 side-button listener
After=graphical-session.target
PartOf=graphical-session.target

[Service]
ExecStart=/usr/bin/python3 "SCRIPT"
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes

[Install]
WantedBy=graphical-session.target
'''.replace('SCRIPT',script)
Path.home().joinpath('.config/systemd/user/rog-helper-button.service').write_text(unit)
PYTHON
systemctl --user daemon-reload
systemctl --user enable --now rog-helper-button.service
