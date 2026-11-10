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
mkdir -p "$check_dir/current/theme" "$check_dir/next-theme"
printf 'accent = "#385bab"\nforeground = "#c4d5ed"\nred = "#ee3366"\n' > "$check_dir/current/theme/colors.toml"
printf '#FF00FF\n' > "$check_dir/current/theme/keyboard.rgb"
printf 'color4 = "#88aa44"\ncolor7 = "#ffeecc"\ncolor1 = "#cc5522"\n' > "$check_dir/next-theme/colors.toml"
printf '1\n' > "$check_dir/current/theme.generation"
cat > "$check_dir/swap-theme" <<'SH'
set -eu
cd "$1"
mv current/theme previous-theme
mv next-theme current/theme
printf '2\n' > current/theme.generation
SH
cat > "$check_dir/shell.qml" <<'QML'
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import "Plugin" as Plugin

ShellRoot {
    property var applied: []
    property var appliedRoles: []
    property int pickerCommits: 0
    Plugin.Panel { id: panel }
    Plugin.LedColorControl {
        id: colors
        width: 350
        target: "/test/keyboard"
        currentColor: "#112233"
        themeRoot: Qt.resolvedUrl("current").toString().replace(/^file:\/\//, "")
        onApplyColor: function(target, color) { applied.push([target, color]) }
        onApplyThemeRole: function(target, role) { appliedRoles.push([target, role]) }
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
                colors.enabled = true
                if (colors.themePalette.accent !== "#385bab") throw new Error("Initial theme file did not load")
                var keyboardPreset = colors.children.find(item => "themeColor" in item)
                if (!keyboardPreset.visible || String(keyboardPreset.themeColor) !== "#ff00ff")
                    throw new Error("Dedicated keyboard color did not load")
                keyboardPreset.clicked()
                if (applied[2][0] !== "z13ctl:lightbar" || applied[2][1] !== "#ff00ff")
                    throw new Error("Dedicated keyboard color did not reach the selected zone")
                swap.running = true
            })
        }
    }
    Process {
        id: swap
        command: ["sh", Qt.resolvedUrl("swap-theme").toString().replace(/^file:\/\//, ""),
            Qt.resolvedUrl(".").toString().replace(/^file:\/\//, "")]
        onExited: function(code) {
            if (code !== 0) throw new Error("Fixture theme swap failed")
            checkSwap.start()
        }
    }
    Timer {
        id: checkSwap
        interval: 400
        onTriggered: {
            var keyboardPreset = colors.children.find(item => "themeColor" in item)
            if (keyboardPreset.visible) throw new Error("Dedicated preset persisted after switching to a theme without it")
            var buttons = colors.children[0].children.filter(item => "themeColor" in item)
            var expected = ["#88aa44", "#ffeecc", "#cc5522"]
            if (buttons.length !== 3) throw new Error("Missing theme presets")
            for (var i = 0; i < buttons.length; i++) {
                if (String(buttons[i].themeColor) !== expected[i]) throw new Error("Preset did not follow theme swap")
                buttons[i].clicked()
                if (applied[3 + i][0] !== "z13ctl:lightbar" || applied[3 + i][1] !== expected[i])
                    throw new Error("Preset applied the wrong zone or color after theme swap")
            }
            colors.target = "/test/keyboard"
            colors.followKeyboardTheme = true
            buttons[1].clicked()
            if (appliedRoles.length !== 1 || appliedRoles[0][0] !== "/test/keyboard" || appliedRoles[0][1] !== "foreground")
                throw new Error("Keyboard Text preset did not send its theme role")
            console.log("ROG_THEME_DIRECTORY_SWAP_OK")
            Qt.quit()
        }
    }
}
QML
timeout 15 quickshell -p "$check_dir" --no-duplicate > "$check_dir/check.log" 2>&1
cat "$check_dir/check.log"
rg -q 'ROG_COLOR_PICKER_AND_ZONE_ROUTING_OK' "$check_dir/check.log"
rg -q 'ROG_THEME_DIRECTORY_SWAP_OK' "$check_dir/check.log"
if rg -q 'TypeError|ReferenceError|Unable to assign|Failed to load configuration' "$check_dir/check.log"; then
    exit 1
fi
