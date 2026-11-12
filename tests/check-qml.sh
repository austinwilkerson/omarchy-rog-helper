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
cat > "$check_dir/Plugin/backend.py" <<'PY'
import json
from pathlib import Path
import sys
import time

state = Path(__file__).with_name("state")
if sys.argv[1] == "status":
    if not state.exists():
        time.sleep(.25)
    print(json.dumps({"devices": [], "batteries": [], "power": {"profiles": []},
                      "value": state.read_text() if state.exists() else "old"}))
elif sys.argv[1] == "apply":
    state.write_text("new")
    print(json.dumps({"ok": True, "message": "Fixture applied"}))
else:
    print(json.dumps({"ok": False, "error": "Fixture failure"}))
    sys.exit(1)
PY
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
    property bool themeChecked: false
    property bool requestChecked: false
    function finishIfChecked() { if (themeChecked && requestChecked) Qt.quit() }
    Plugin.Panel {
        id: panel
        onReportChanged: if (report.value === "old") throw new Error("Pre-action status leaked")
    }
    Timer {
        property int step: 0
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (step === 0) {
                panel.refresh()
                panel.act(["apply"])
                panel.act(["duplicate"])
                if (!panel.busy || panel.requestPhase !== "reading") throw new Error("Action was not queued")
                step++
            } else if (!panel.busy && panel.requestPhase === "idle") {
                if (step === 1) {
                    if (panel.report.value !== "new" || panel.notice !== "Fixture applied" || panel.error)
                        throw new Error("Write did not get a fresh, successful readback: " + panel.error)
                    panel.act(["fail"])
                    step++
                } else if (step === 2) {
                    if (panel.report.value !== "new" || panel.error !== "Fixture failure")
                        throw new Error("Readback swallowed the action failure: " + panel.error)
                    panel.request("reading", ["invalid-status"])
                    panel.act(["duplicate"])
                    step++
                } else if (step === 3) {
                    if (panel.pendingAction !== null || panel.report.value !== "new"
                        || panel.statusError !== "Could not read hardware status" || panel.actionError)
                        throw new Error("Failed prerequisite read replayed an action or discarded the snapshot")
                    panel.refresh()
                    step++
                } else {
                    if (panel.error || panel.report.value !== "new")
                        throw new Error("Refresh did not recover after a failed read")
                    console.log("ROG_REQUEST_ORDERING_OK")
                    requestChecked = true
                    stop()
                    finishIfChecked()
                }
            }
        }
    }
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
            colors.gestureTarget = colors.target
            colors.target = "/test/keyboard"
            colors.target = "z13ctl:lightbar"
            colors.commitPicker("#ff0000")
            if (applied.length !== 1) throw new Error("Switching away and back revived an old gesture")
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
            themeChecked = true
            finishIfChecked()
        }
    }
}
QML
timeout 15 quickshell -p "$check_dir" --no-duplicate > "$check_dir/check.log" 2>&1 || { cat "$check_dir/check.log"; exit 1; }
cat "$check_dir/check.log"
rg -q 'ROG_COLOR_PICKER_AND_ZONE_ROUTING_OK' "$check_dir/check.log"
rg -q 'ROG_THEME_DIRECTORY_SWAP_OK' "$check_dir/check.log"
rg -q 'ROG_REQUEST_ORDERING_OK' "$check_dir/check.log"
if rg -q 'Error:|Unable to assign|Failed to load configuration' "$check_dir/check.log"; then
    exit 1
fi
