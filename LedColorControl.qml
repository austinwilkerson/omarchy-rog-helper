import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import qs.Commons as Commons
import qs.Ui

Column {
    id: root
    property string target: ""
    property string currentColor: "#4488ff"
    property string fontFamily: Commons.Style.font.family
    property string mode: "custom"
    property string gestureTarget: ""
    property string themeRoot: Quickshell.env("HOME") + "/.local/state/omarchy/current"
    property var themePalette: ({})
    property string themeKeyboardColor: ""
    property bool followKeyboardTheme: false
    property string followedRole: ""
    readonly property color fg: Commons.Color.popups.text
    readonly property string shownColor: /^#[0-9a-fA-F]{6}$/.test(currentColor) ? currentColor.toLowerCase() : "#4488ff"
    readonly property var swatches: ["#ff0000","#dc1644","#ff5000","#ff8655","#ff9500","#ffd800","#ffff00","#9aff00","#00e000","#00ee88","#88ffdd","#008b8b","#00eeee","#00b9ed","#168fff","#4868df","#1800ff","#100080","#550080","#9324df","#800080","#f000ef","#ff1493","#ff69b4","#ee82ee","#40dfce","#a52a2a","#ffffff"]
    signal applyColor(string target, string color)
    signal applyThemeRole(string target, string role)
    spacing: Commons.Style.space(12)
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    function loadThemePalette(raw) {
        var colors = {}
        for (const line of raw.split("\n")) {
            const match = /^\s*(accent|foreground|red|color[147])\s*=\s*["']?(#[0-9a-fA-F]{6})\b/.exec(line)
            if (match) colors[match[1]] = match[2]
        }
        themePalette = {
            accent: colors.accent || colors.color4,
            foreground: colors.foreground || colors.color7,
            urgent: colors.red || colors.color1
        }
    }

    FileView {
        id: themeColors
        path: root.themeRoot + "/theme/colors.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.loadThemePalette(text())
        onFileChanged: reload()
    }
    FileView {
        id: keyboardColorFile
        path: root.themeRoot + "/theme/keyboard.rgb"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const value = text().trim().replace(/^#/, "")
            root.themeKeyboardColor = /^[0-9a-fA-F]{6}$/.test(value) ? "#" + value.toLowerCase() : ""
        }
        onLoadFailed: root.themeKeyboardColor = ""
        onFileChanged: reload()
    }
    FileView {
        path: root.themeRoot + "/theme.generation"
        watchChanges: true
        printErrors: false
        // Omarchy replaces the theme directory, then updates this stable file.
        onFileChanged: {
            reload()
            themeColors.reload()
            keyboardColorFile.reload()
        }
    }

    function hexOf(value) {
        var c = typeof value === "string" ? Qt.color(value) : value
        return "#" + [c.r, c.g, c.b].map(v => Math.max(0,Math.min(255,Math.round(v*255))).toString(16).padStart(2,"0")).join("")
    }
    function choose(color) {
        if (!enabled || !target || !/^#[0-9a-fA-F]{6}$/.test(color)) return
        applyColor(target, color.toLowerCase())
    }
    function commitPicker(color) {
        // A zone switch during a gesture must not send the old gesture to the new zone.
        if (gestureTarget === target) choose(color)
    }
    onTargetChanged: Qt.callLater(function() {
        picker.sync(Qt.color(root.shownColor))
        hex.text = root.shownColor
    })
    component ThemeColorButton: Button {
        required property color themeColor
        property string themeRole: ""
        iconText: "●"
        foreground: themeColor
        accent: themeColor
        fontFamily: root.fontFamily
        selected: root.followedRole ? root.followedRole === themeRole : root.shownColor === root.hexOf(themeColor)
        bordered: true
        color: Qt.tint(Commons.Color.popups.background, Qt.alpha(themeColor, selected ? 0.28 : hot ? 0.22 : 0.15))
        onClicked: {
            if (!root.enabled) return
            if (root.followKeyboardTheme && themeRole && root.target)
                root.applyThemeRole(root.target, themeRole)
            else
                root.choose(root.hexOf(themeColor))
        }
    }
    Row {
        width: parent.width
        spacing: Commons.Style.space(8)
        Repeater {
            model: ["accent", "foreground", "urgent"]
            ThemeColorButton {
                required property string modelData
                themeRole: modelData
                themeColor: root.themePalette[modelData] ||
                    (modelData === "accent" ? Commons.Color.accent : modelData === "foreground" ? Commons.Color.foreground : Commons.Color.urgent)
                text: strings.t(modelData)
            }
        }
    }
    ThemeColorButton {
        width: Math.min(implicitWidth, root.width)
        visible: root.themeKeyboardColor !== ""
        themeColor: root.themeKeyboardColor || root.fg
        text: strings.t("themeKeyboardColor")
    }
    ButtonGroup {
        width: parent.width
        foreground: root.fg
        fontFamily: root.fontFamily
        options: [{value:"custom",label:strings.t("custom")},{value:"swatches",label:strings.t("swatches")}]
        value: root.mode
        onChanged: value => root.mode = value
    }
    Column {
        width: parent.width
        visible: root.mode === "custom"
        spacing: Commons.Style.space(10)
        ColorPicker {
            id: picker
            width: parent.width
            value: root.shownColor
            onEditingStarted: root.gestureTarget = root.target
            onPicked: color => root.commitPicker(color)
        }
        Text {
            textFormat: Text.PlainText
            text: strings.t("hex")
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Commons.Style.font.caption
        }
        Row {
            width: parent.width
            spacing: Commons.Style.space(8)
            Controls.TextField {
                id: hex
                width: Math.max(100, parent.width - apply.implicitWidth - parent.spacing)
                text: root.shownColor
                color: root.fg
                font.family: root.fontFamily
                validator: RegularExpressionValidator { regularExpression: /#[0-9a-fA-F]{6}/ }
                onAccepted: if (acceptableInput) root.choose(text)
            }
            Button {
                id: apply
                text: strings.t("apply")
                foreground: root.fg
                fontFamily: root.fontFamily
                bordered: true
                enabled: hex.acceptableInput
                onClicked: root.choose(hex.text)
            }
        }
    }
    Grid {
        visible: root.mode === "swatches"
        width: parent.width
        columns: 7
        spacing: Commons.Style.space(8)
        Repeater {
            model: root.swatches
            Rectangle {
                required property string modelData
                width: (parent.width - parent.spacing * 6) / 7
                height: width
                radius: width / 2
                color: modelData
                border.width: root.shownColor === modelData ? 2 : 0
                border.color: root.fg
                activeFocusOnTab: true
                Keys.onSpacePressed: root.choose(modelData)
                Keys.onReturnPressed: root.choose(modelData)
                TapHandler { onTapped: root.choose(modelData) }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
            }
        }
    }
}
