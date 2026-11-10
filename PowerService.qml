import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

Scope {
    id: root
    property bool autoRefresh: false
    readonly property string statePath: (Quickshell.env("XDG_STATE_HOME") ||
        Quickshell.env("HOME") + "/.local/state") + "/rog-helper/auto-refresh"

    function schedule() {
        if (autoRefresh) updateDelay.restart()
    }

    onAutoRefreshChanged: schedule()

    FileView {
        path: root.statePath
        printErrors: false
        watchChanges: true
        onLoaded: root.autoRefresh = text().trim() === "on"
        onLoadFailed: root.autoRefresh = false
        onFileChanged: reload()
    }
    Connections {
        target: UPower
        function onOnBatteryChanged() { root.schedule() }
    }
    Timer {
        // Recheck after resume or a compositor mode reset.
        interval: 30000
        running: root.autoRefresh
        repeat: true
        onTriggered: root.schedule()
    }
    Timer {
        id: updateDelay
        interval: 350
        onTriggered: {
            if (!root.autoRefresh) return
            if (syncProcess.running) restart()
            else syncProcess.running = true
        }
    }
    Process {
        id: syncProcess
        command: ["python3", "-B", decodeURIComponent(Qt.resolvedUrl("backend.py").toString().replace(/^file:\/\//, "")),
                  "refresh-sync"]
    }
}
