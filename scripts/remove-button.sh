#!/usr/bin/env bash
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
systemctl --user disable --now rog-helper-button.service || true
rm -f "$HOME/.config/systemd/user/rog-helper-button.service"
systemctl --user daemon-reload
"$plugin_dir/scripts/revoke-access.sh" button
