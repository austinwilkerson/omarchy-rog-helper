#!/usr/bin/env bash
set -euo pipefail
source_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
target_dir="$HOME/.config/omarchy/plugins/rog-helper"
omarchy plugin validate "$source_dir"
if [[ -e "$target_dir" && "$source_dir" != "$target_dir" ]]; then
    backup_dir="$HOME/.local/state/rog-helper/backups/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    cp -a "$target_dir" "$backup_dir/plugin"
fi
if [[ "$source_dir" != "$target_dir" ]]; then
    mkdir -p "$target_dir"
    cp "$source_dir"/{Panel.qml,manifest.json,backend.py,button_listener.py,README.md,LICENSE,RESEARCH.md,VALIDATION.md,THIRD_PARTY_NOTICES.md} "$target_dir/"
    cp -r "$source_dir/scripts" "$target_dir/"
fi
mkdir -p "$HOME/.local/state/rog-helper/backups"
cp "$HOME/.config/omarchy/shell.json" "$HOME/.local/state/rog-helper/backups/shell-$(date +%Y%m%d-%H%M%S).json"
omarchy-shell shell rescanPlugins
# Discovery is asynchronous; allow the host's file watcher to settle.
for attempt in {1..20}; do
    if omarchy plugin list --json | python3 -c 'import json,sys; sys.exit(not any(x["id"]=="rog-helper" for x in json.load(sys.stdin)))'; then
        omarchy plugin enable rog-helper --section right
        exit 0
    fi
    sleep 0.2
done
echo 'Plugin discovery did not finish. Run omarchy-shell shell rescanPlugins and enable rog-helper after the shell is ready.' >&2
exit 1
