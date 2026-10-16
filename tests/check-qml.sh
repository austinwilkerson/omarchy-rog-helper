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
cp "$plugin_dir/Panel.qml" "$plugin_dir/ColorPicker.qml" "$plugin_dir/LedColorControl.qml" "$check_dir/Plugin/"
cp -r "$plugin_dir/i18n" "$check_dir/Plugin/"
cat > "$check_dir/shell.qml" <<'QML'
import QtQuick
import Quickshell
import qs.Commons as Commons
import "Plugin" as Plugin

ShellRoot {
    property var applied: []
    property int pickerCommits: 0
    Plugin.Panel { id: panel }
    Plugin.LedColorControl {
        id: colors
        width: 350
        target: "/test/keyboard"
        currentColor: "#112233"
        onApplyColor: function(target, color) { applied.push([target, color]) }
    }
    Plugin.ColorPicker {
        id: picker
        width: 350
        value: "#00ff00"
        onPicked: pickerCommits++
    }
    Timer {
        interval: 700
        running: true
        onTriggered: {
            if (panel.fg !== Commons.Color.popups.text) throw new Error("Popup foreground mismatch")
            colors.choose("#AABBCC")
            if (applied.length !== 1 || applied[0][0] !== "/test/keyboard" || applied[0][1] !== "#aabbcc") throw new Error("Keyboard custom color routing failed")
            colors.gestureTarget = colors.target
            colors.target = "z13ctl:lightbar"
            colors.commitPicker("#ff0000")
            if (applied.length !== 1) throw new Error("Old gesture reached new zone")
            Commons.Color.accent = "#abcdef"
            colors.choose(colors.hexOf(Commons.Color.accent))
            if (applied.length !== 2 || applied[1][0] !== "z13ctl:lightbar" || applied[1][1] !== "#abcdef") throw new Error("Theme lightbar routing failed")
            if (colors.hexOf(Qt.rgba(.2,.4,.6,.2)) !== "#336699") throw new Error("Theme RGB conversion failed")
            colors.choose("<img src=bad>")
            colors.enabled = false
            colors.choose("#ffffff")
            if (applied.length !== 2) throw new Error("Invalid or disabled color action")
            picker.sync(Qt.color("#00ff00"))
            if (Math.abs(picker.hue - 1/3) > .01 || String(picker.selectedColor) !== "#00ff00") throw new Error("Picker color mismatch")
            picker.select(100,50)
            if (pickerCommits !== 0) throw new Error("Picker committed before release")
            picker.commit()
            if (pickerCommits !== 1) throw new Error("Picker release did not commit")
            var palette = Object.assign({}, Commons.Color.shellValues)
            palette["popups.text"] = "#123456"
            Commons.Color.shellValues = palette
            Qt.callLater(function() {
                if (String(panel.fg) !== "#123456") throw new Error("Theme change did not reach plugin")
                console.log("ROG_THEME_REACTIVE_OK")
                console.log("ROG_COLOR_PICKER_AND_ZONE_ROUTING_OK")
                Qt.quit()
            })
        }
    }
}
QML
timeout 15 quickshell -p "$check_dir" --no-duplicate > "$check_dir/check.log" 2>&1
cat "$check_dir/check.log"
rg -q 'ROG_COLOR_PICKER_AND_ZONE_ROUTING_OK' "$check_dir/check.log"
if rg -q 'TypeError|ReferenceError|Unable to assign|Failed to load configuration' "$check_dir/check.log"; then
    exit 1
fi
