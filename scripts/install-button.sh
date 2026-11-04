#!/usr/bin/env bash
set -euo pipefail
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_dir="$config_dir/omarchy/plugins/rog-helper"
[[ -f "$plugin_dir/button_listener.py" && -f "$plugin_dir/scripts/70-rog-helper-button.rules" ]] || {
  echo 'Install ROG Helper before setting up its button service.' >&2
  exit 1
}
[[ "$(cat /sys/class/dmi/id/product_name)" == *GZ302EA* ]] || { echo 'Only GZ302EA button mapping has been verified.' >&2; exit 1; }
# No group membership, sudo policy or Hyprland input changes.
sudo install -m 644 "$plugin_dir/scripts/70-rog-helper-button.rules" /etc/udev/rules.d/70-rog-helper-button.rules
sudo udevadm control --reload-rules
sudo udevadm trigger --subsystem-match=input --action=change
mkdir -p "$config_dir/systemd/user"
python3 - "$plugin_dir" "$config_dir/systemd/user" <<'PYTHON'
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
Path(sys.argv[2]).joinpath('rog-helper-button.service').write_text(unit)
PYTHON
systemctl --user daemon-reload
systemctl --user enable rog-helper-button.service
systemctl --user restart rog-helper-button.service
