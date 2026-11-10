import QtQuick
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
// Qualify theme singletons to avoid QtQuick type-name collisions on newer Qt.
import qs.Commons as Commons
import qs.Ui

Panel {
    id: root
    moduleName: "rog-helper"
    ipcTarget: "rog-helper"
    manageIpc: false
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    property var report: ({devices: [], power: {profiles: []}, sensors: [], batteries: [], errors: []})
    property string actionError: ""
    property string statusError: ""
    readonly property string error: actionError || statusError
    property string notice: ""
    property int zone: 0
    property string page: "Lights"
    property string requestPhase: "idle"
    property var pendingAction: null
    readonly property bool busy: pendingAction !== null || requestPhase === "applying" || requestPhase === "confirming"
    readonly property var fnLock: report.fnlock || ({})
    readonly property var refreshRate: report.refresh || ({})
    readonly property var powerLimits: report.powerLimits || ({})
    readonly property var device: report.devices[zone] || null
    readonly property color fg: Commons.Color.popups.text
    readonly property string family: bar ? bar.fontFamily : Commons.Style.font.family
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

    function request(phase, args) {
        requestPhase = phase
        backend.command = ["python3", "-B", decodeURIComponent(String(Qt.resolvedUrl("backend.py")).replace(/^file:\/\//, ""))].concat(args)
        backend.running = true
    }
    function refresh() {
        if (requestPhase === "idle") request("reading", ["status"])
    }
    function act(args) {
        if (busy) return
        actionError = ""; statusError = ""; notice = ""
        if (requestPhase === "reading") pendingAction = args
        else request("applying", args)
    }
    function finishRequest(code, output, diagnostics) {
        if (requestPhase === "reading" && pendingAction !== null) {
            var args = pendingAction
            request("applying", args)
            pendingAction = null
            return
        }
        if (requestPhase === "applying") {
            try {
                var result = JSON.parse(output)
                if (code === 0 && result.ok) notice = result.message || "Applied"
                else actionError = result.error || diagnostics || "Could not apply hardware change"
            } catch (e) { actionError = diagnostics || "Action returned no result" }
            request("confirming", ["status"])
            return
        }
        try {
            var snapshot = JSON.parse(output)
            if (code !== 0 || !snapshot || !Array.isArray(snapshot.devices) || !Array.isArray(snapshot.batteries)
                || !snapshot.power || !Array.isArray(snapshot.power.profiles)) throw new Error()
            report = snapshot
            if (zone >= report.devices.length) zone = 0
            statusError = ""
        } catch (e) { statusError = diagnostics || "Could not read hardware status" }
        requestPhase = "idle"
    }
    onOpenedChanged: if (opened) refresh()
    Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }
    FileView {
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/rog-helper/fnlock/mode"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload()
            if (root.opened) root.refresh()
        }
    }
    Process {
        id: backend
        stdout: StdioCollector { id: response }
        stderr: StdioCollector { id: diagnostics }
        onExited: function(code) {
            var output = response.text
            var detail = diagnostics.text.trim()
            Qt.callLater(root.finishRequest, code, output, detail)
        }
    }
    BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰢮"
        tooltipText: "ROG Helper"
        onPressed: root.toggle()
    }
    component Label: Text {
        color: root.fg
        font.family: root.family
        font.pixelSize: Commons.Style.font.caption
        textFormat: Text.PlainText
    }
    component Section: PanelSectionHeader {
        foreground: root.fg
        fontFamily: root.family
    }
    component Choices: ButtonGroup {
        foreground: root.fg
        background: Commons.Color.popups.background
        accent: Commons.Color.accent
        fontFamily: root.family
        enabled: !root.busy
    }
    KeyboardPanel {
        id: popup
        anchorItem: button
        bar: root.bar
        owner: root
        open: root.opened
        focusTarget: content
        contentWidth: fittedContentWidth(Commons.Style.space(328))
        contentHeight: fittedContentHeight(body.implicitHeight, Commons.Style.space(660))
        Item {
            id: content
            anchors.fill: parent
            focus: true
            Keys.onEscapePressed: root.close()
            Flickable {
                anchors.fill: parent
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollBar.vertical: Controls.ScrollBar {}
                Column {
                    id: body
                    width: parent.width
                    spacing: Commons.Style.space(14)
                    PanelHero {
                        width: parent.width
                        title: "ROG Helper"
                        meta: root.report.model || "Detecting hardware…"
                        iconComponent: Component { Text { text: "󰢮"; color: root.fg; font.family: root.family; font.pixelSize: Commons.Style.font.display } }
                        foreground: root.fg
                        fontFamily: root.family
                        trailingControl: Component {
                            ToggleSwitch {
                                width: implicitWidth
                                height: implicitHeight
                                visible: root.page === "Lights" && !!root.device
                                enabled: root.device && root.device.available !== false
                                foreground: root.fg
                                checked: root.device ? root.device.brightness > 0 : false
                                busy: root.busy
                                onToggled: root.act(["brightness", root.device.path, checked ? "0" : "2"])
                            }
                        }
                    }
                    Choices {
                        width: parent.width
                        options: {
                            var pages = [{value:"Lights",label:"Lights"},{value:"Power",label:"Power"},{value:"Battery",label:"Battery"}]
                            if (root.fnLock.supported) pages.push({value:"Keyboard",label:"Keyboard"})
                            return pages
                        }
                        value: root.page
                        onChanged: function(value) { root.page = value }
                    }
                    Column {
                        width: parent.width
                        spacing: Commons.Style.space(12)
                        visible: root.page === "Lights"
                        Label { text: "Independent · Control zones separately"; opacity: 0.7 }
                        Section { text: "ZONE" }
                        Choices {
                            width: parent.width
                            options: root.report.devices.map(function(d,i) {return {value:String(i),label:d.name}})
                            value: String(root.zone)
                            onChanged: function(value) { root.zone = Number(value) }
                        }
                        Label { visible: !root.device; text: "No supported asusd lighting device detected."; width: parent.width; wrapMode: Text.WordWrap }
                        Section { text: "BRIGHTNESS"; visible: !!root.device }
                        Choices {
                            width: parent.width
                            visible: !!root.device
                            enabled: !root.busy && root.device && root.device.available !== false
                            options: root.device ? root.device.brightnessLevels.map(function(n) { return {value:String(n),label:["Off","Low","Med","High"][n] || String(n)} }) : []
                            value: root.device ? String(root.device.brightness) : ""
                            onChanged: function(value) { root.act(["brightness",root.device.path,value]) }
                        }
                        Section { text: "MODE"; visible: !!root.device }
                        Choices {
                            width: parent.width
                            visible: !!root.device
                            enabled: !root.busy && root.device && root.device.available !== false
                            options: root.device ? root.device.modes.map(function(m) {return {value:String(m.value),label:m.label}}) : []
                            value: root.device ? String(root.device.mode) : ""
                            onChanged: function(value) { root.act(["mode",root.device.path,value]) }
                        }
                        Section { text: "COLOR"; visible: !!root.device }
                        LedColorControl {
                            width: parent.width
                            visible: !!root.device
                            enabled: !root.busy && root.device && root.device.available !== false
                            target: root.device ? root.device.path : ""
                            currentColor: root.device ? root.device.color : "#4488ff"
                            followKeyboardTheme: !!root.device && root.device.name === "Keyboard"
                            followedRole: followKeyboardTheme ? root.report.keyboardThemeRole || "" : ""
                            fontFamily: root.family
                            onApplyColor: function(target, color) { root.act(["color", target, color]) }
                            onApplyThemeRole: function(target, role) { root.act(["keyboard-theme-role", target, role]) }
                        }
                        Label { width: parent.width; wrapMode: Text.WordWrap; opacity: 0.65; text: root.device && root.device.note ? root.device.note : "Modes reported by asusd · Changes persist through asusd" }
                    }
                    Column {
                        width: parent.width; spacing: Commons.Style.space(12)
                        visible: root.page === "Power"
                        Section { text: "PERFORMANCE PROFILE" }
                        Choices {
                            width: parent.width
                            options: root.report.power.profiles.map(function(p) {return {value:p,label:({"power-saver":"Quiet","balanced":"Balanced","performance":"Performance"})[p] || p}})
                            value: root.report.power.profile || ""
                            onChanged: function(value) { root.act(["profile",value]) }
                        }
                        Label { width: parent.width; wrapMode: Text.WordWrap; opacity: 0.65; text: "Uses power-profiles-daemon. asusd may select its configured profile when AC power changes." }
                        Column {
                            width: parent.width
                            spacing: Commons.Style.space(8)
                            visible: root.fnLock.supported === true
                            Section { text: strings.t("displayRefresh") }
                            Choices {
                                width: parent.width
                                enabled: !root.busy && (root.refreshRate.available === true || root.refreshRate.enabled === true)
                                options: [{value:"off",label:strings.t("refreshOff")},{value:"on",label:strings.t("refreshAuto")}]
                                value: root.refreshRate.enabled ? "on" : "off"
                                onChanged: function(value) { root.act(["auto-refresh",value]) }
                            }
                            Label {
                                width: parent.width
                                wrapMode: Text.WordWrap
                                opacity: 0.65
                                text: root.refreshRate.message || strings.t("refreshSummary").arg(root.refreshRate.rate || "—")
                            }
                        }
                        Section { visible: Object.keys(root.powerLimits).length > 0; text: strings.t("firmwarePowerLimits") }
                        Repeater {
                            model: ["PL1", "PL2", "PL3"].filter(key => root.powerLimits[key] !== undefined)
                            Label {
                                required property string modelData
                                text: strings.t("powerLimit." + modelData).arg(root.powerLimits[modelData])
                            }
                        }
                        Section { text: "TEMPERATURES + FANS" }
                        Repeater {
                            model: root.report.sensors
                            Label { required property var modelData; text: modelData.label + "   " + modelData.value + " " + modelData.unit }
                        }
                        Label { width: parent.width; wrapMode: Text.WordWrap; text: "Fan curves: firmware managed. Custom curve editing and power-limit tuning deferred pending validation. GPU switching: unavailable in this version."; opacity: 0.65 }
                    }
                    Column {
                        width: parent.width; spacing: Commons.Style.space(12)
                        visible: root.page === "Battery"
                        Section { text: "CHARGE LIMIT" }
                        Repeater {
                            model: root.report.batteries.filter(function(b) {return b.name.indexOf("BAT") === 0})
                            Column {
                                required property var modelData
                                width: parent.width; spacing: Commons.Style.space(12)
                                Label { text: modelData.name + " · " + modelData.capacity + "% · " + modelData.status }
                                Choices {
                                    width: parent.width
                                    enabled: !root.busy && modelData.limit !== null
                                    options: [{value:"60",label:"60%"},{value:"80",label:"80%"},{value:"100",label:"100%"}]
                                    value: modelData.limit || ""
                                    onChanged: function(value) { root.act(["charge",value]) }
                                }
                                Label { text: modelData.limit === null ? "Charge limit unsupported" : "Current charge limit: " + modelData.limit + "%" }
                                Button {
                                    visible: root.report.chargeOnce === true && modelData.limit !== null
                                    enabled: !root.busy && root.report.onBattery === false && Number(modelData.limit) < 100
                                    text: strings.t("chargeOnce")
                                    foreground: root.fg
                                    fontFamily: root.family
                                    focusable: true
                                    bordered: true
                                    onClicked: root.act(["charge-once"])
                                }
                                Label {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    visible: root.report.chargeOnce === true && modelData.limit !== null
                                    opacity: 0.65
                                    text: strings.t(root.report.onBattery === false ? "chargeOnceRestore" : "chargeOncePlugIn")
                                }
                                Label {
                                    visible: modelData.watts != null
                                    text: strings.t("batteryPower").arg(modelData.watts)
                                }
                                Label {
                                    width: parent.width
                                    wrapMode: Text.WordWrap
                                    visible: modelData.health != null
                                    text: modelData.fullWh != null
                                        ? strings.t("batteryCapacity").arg(modelData.fullWh).arg(modelData.designWh).arg(modelData.health)
                                        : strings.t("batteryHealth").arg(modelData.health)
                                }
                            }
                        }
                        Label { width: parent.width; wrapMode: Text.WordWrap; opacity: 0.65; text: "Saved by asusd. A lower limit stops further charging; it does not discharge the battery." }
                    }
                    Column {
                        width: parent.width
                        spacing: Commons.Style.space(12)
                        visible: root.page === "Keyboard"
                        Section { text: "SOFTWARE FN LOCK" }
                        Choices {
                            width: parent.width
                            enabled: !root.busy && root.fnLock.available === true
                            options: [{value:"function",label:"Function keys"},{value:"media",label:"Media keys"}]
                            value: root.fnLock.mode || ""
                            onChanged: function(value) { root.act(["fnlock",value]) }
                        }
                        Label {
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: root.fnLock.message || (root.fnLock.configured
                                ? "Fn+Esc switches modes on the detachable keyboard. The firmware and Esc LED are independent."
                                : "Optional setup is required. Run scripts/install-fnlock.sh from the installed ROG Helper folder.")
                        }
                    }
                    Label {
                        width: parent.width; wrapMode: Text.Wrap
                        visible: text !== ""
                        text: root.error || (root.report.errors || []).join("\n") || (root.busy ? "Applying…" : root.notice)
                        color: root.error ? Commons.Color.urgent : root.fg
                    }
                }
            }
        }
    }
}
