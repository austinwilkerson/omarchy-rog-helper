#!/usr/bin/env bash
# Optional integration check: requires a running Wayland desktop and Omarchy.
set -euo pipefail
plugin_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
shell_dir="${OMARCHY_PATH:-/usr/share/omarchy}/shell"
mkdir -p "$plugin_dir/work"
check_dir="$(mktemp -d "$plugin_dir/work/qml-check-XXXXXX")"
trap 'rm -rf -- "$check_dir"' EXIT
ln -s "$shell_dir/Commons" "$check_dir/Commons"
ln -s "$shell_dir/Ui" "$check_dir/Ui"
mkdir -p "$check_dir/Plugin"
cp "$plugin_dir/Panel.qml" "$check_dir/Plugin/Panel.qml"
cat > "$check_dir/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons as Commons
import "Plugin" as Plugin

ShellRoot {
    Plugin.Panel { id: panel }
    Timer {
        interval: 700
        running: true
        onTriggered: {
            if (panel.fg !== Commons.Color.popups.text) throw new Error("Popup foreground mismatch")
            var colors = Object.assign({}, Commons.Color.shellValues)
            colors["popups.text"] = "#123456"
            Commons.Color.shellValues = colors
            Qt.callLater(function() {
                if (String(panel.fg) !== "#123456") throw new Error("Theme change did not reach plugin")
                console.log("ROG_THEME_REACTIVE_OK")
                Qt.quit()
            })
        }
    }
}
QML
timeout 15 quickshell -p "$check_dir" --no-duplicate > "$check_dir/check.log" 2>&1
cat "$check_dir/check.log"
rg -q 'ROG_THEME_REACTIVE_OK' "$check_dir/check.log"
if rg -q 'TypeError|ReferenceError|Unable to assign|Failed to load configuration' "$check_dir/check.log"; then
    exit 1
fi
