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
    property string error: ""
    property string notice: ""
    property int zone: 0
    property string page: "Lights"
    property bool busy: actionProc.running
    readonly property var device: report.devices[zone] || null
    readonly property color fg: Commons.Color.popups.text
    readonly property string family: bar ? bar.fontFamily : Commons.Style.font.family

    function refresh() { if (!stateProc.running) stateProc.running = true }
    function act(args) {
        if (busy) return
        error = ""; notice = ""
        actionProc.command = ["python3", Qt.resolvedUrl("backend.py").toString().replace("file://", "")].concat(args)
        actionProc.running = true
    }
    onOpenedChanged: if (opened) refresh()
    Timer { interval: 5000; running: root.opened; repeat: true; onTriggered: root.refresh() }
    Process {
        id: stateProc
        command: ["python3", Qt.resolvedUrl("backend.py").toString().replace("file://", ""), "status"]
        stdout: StdioCollector { onStreamFinished: {
            try { root.report = JSON.parse(text); if (root.zone >= root.report.devices.length) root.zone = 0 }
            catch (e) { root.error = "Could not read hardware status" }
        } }
        stderr: StdioCollector { onStreamFinished: if (text) root.error = text.trim() }
    }
    Process {
        id: actionProc
        stdout: StdioCollector { onStreamFinished: {
            try { var result = JSON.parse(text); if (!result.ok) root.error = result.error; else root.notice = "Applied" }
            catch (e) { root.error = "Action returned no result" }
        } }
        onExited: root.refresh()
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
                        options: [{value:"Lights",label:"Lights"},{value:"Power",label:"Power"},{value:"Battery",label:"Battery"}]
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
                            fontFamily: root.family
                            onApplyColor: function(target, color) { root.act(["color", target, color]) }
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
                            }
                        }
                        Label { width: parent.width; wrapMode: Text.WordWrap; opacity: 0.65; text: "Saved by asusd. A lower limit stops further charging; it does not discharge the battery." }
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
