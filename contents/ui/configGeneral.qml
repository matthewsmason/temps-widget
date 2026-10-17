import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import QtCore
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM
import org.kde.kquickcontrols as KQuickControls
import org.kde.plasma.plasmoid

// Settings → General: thresholds, colors, update rate, and where the game log lives.
KCM.SimpleKCM {
    id: page

    // Plasma binds each config entry to a cfg_<name> property (and its default to cfg_<name>Default)
    property alias cfg_cpuWarn: cpuWarn.value
    property alias cfg_cpuHot: cpuHot.value
    property alias cfg_gpuWarn: gpuWarn.value
    property alias cfg_gpuHot: gpuHot.value
    property alias cfg_updateSeconds: updateSeconds.value
    property alias cfg_showFans: showFans.checked
    property bool cfg_showFansDefault
    property alias cfg_minSessionMinutes: minSession.value
    property int cfg_minSessionMinutesDefault
    property string cfg_cpuColor
    property string cfg_gpuColor
    property string cfg_gameLog
    property string cfg_clearRequest
    property string cfg_clearRequestDefault
    property int cfg_cpuWarnDefault
    property int cfg_cpuHotDefault
    property int cfg_gpuWarnDefault
    property int cfg_gpuHotDefault
    property int cfg_updateSecondsDefault
    property string cfg_cpuColorDefault
    property string cfg_gpuColorDefault
    property string cfg_gameLogDefault

    // Automatic colors match the widget's (light/dark aware)
    readonly property bool darkTheme: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
    readonly property color autoCpu: darkTheme ? "#6cb8ff" : "#1f74d1"
    readonly property color autoGpu: darkTheme ? "#7ee08f" : "#1e9a3c"

    readonly property url folderUrl: StandardPaths.writableLocation(StandardPaths.GenericDataLocation) + "/temperature-monitor"
    readonly property string folderPath: decodeURIComponent(folderUrl.toString().replace(/^file:\/\//, ""))
    readonly property string homePath: decodeURIComponent(StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, ""))

    component TempSpin: QQC2.SpinBox {
        from: 40
        to: 110
        textFromValue: (value, locale) => value + "°C"
        valueFromText: (text, locale) => parseInt(text)
    }

    // Color button + reset-to-automatic, for one device
    component ColorRow: RowLayout {
        id: colorRow
        property string value
        property color automatic
        signal picked(string color)
        spacing: Kirigami.Units.smallSpacing
        KQuickControls.ColorButton {
            color: colorRow.value ? colorRow.value : colorRow.automatic
            showAlphaChannel: false
            onAccepted: color => colorRow.picked(color.toString())
        }
        QQC2.Label {
            text: colorRow.value ? "Custom" : "Automatic"
            opacity: 0.7
        }
        QQC2.ToolButton {
            visible: colorRow.value !== ""
            icon.name: "edit-undo"
            text: "Reset"
            onClicked: colorRow.picked("")
        }
    }

    Kirigami.FormLayout {
        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Thresholds"
        }
        RowLayout {
            Kirigami.FormData.label: "CPU orange / red:"
            TempSpin { id: cpuWarn; onValueModified: if (cpuHot.value < value) cpuHot.value = value }
            TempSpin { id: cpuHot; onValueModified: if (cpuWarn.value > value) cpuWarn.value = value }
        }
        RowLayout {
            Kirigami.FormData.label: "GPU orange / red:"
            TempSpin { id: gpuWarn; onValueModified: if (gpuHot.value < value) gpuHot.value = value }
            TempSpin { id: gpuHot; onValueModified: if (gpuWarn.value > value) gpuWarn.value = value }
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Colors"
        }
        ColorRow {
            Kirigami.FormData.label: "CPU:"
            value: page.cfg_cpuColor
            automatic: page.autoCpu
            onPicked: color => page.cfg_cpuColor = color
        }
        ColorRow {
            Kirigami.FormData.label: "GPU:"
            value: page.cfg_gpuColor
            automatic: page.autoGpu
            onPicked: color => page.cfg_gpuColor = color
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Show"
        }
        QQC2.CheckBox {
            id: showFans
            Kirigami.FormData.label: "Under the temperatures:"
            text: "Pump and fan speeds"
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Updates"
        }
        QQC2.SpinBox {
            id: updateSeconds
            Kirigami.FormData.label: "Read temperatures every:"
            from: 1
            to: 10
            textFromValue: (value, locale) => value === 1 ? "1 second" : value + " seconds"
            valueFromText: (text, locale) => parseInt(text)
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Games"
        }
        QQC2.SpinBox {
            id: minSession
            Kirigami.FormData.label: "Only log sessions longer than:"
            from: 0
            to: 60
            textFromValue: (value, locale) => value === 0 ? "Log every session" : value === 1 ? "1 minute" : value + " minutes"
            valueFromText: (text, locale) => parseInt(text) || 0
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Saved data"
        }
        RowLayout {
            Kirigami.FormData.label: "Folder:"
            spacing: Kirigami.Units.largeSpacing
            QQC2.Label {
                text: folderPath.startsWith(homePath) ? "~" + folderPath.slice(homePath.length) : folderPath
                font.family: "monospace"
                textFormat: Text.PlainText
            }
            QQC2.Button {
                text: "Open Folder"
                icon.name: "folder-open"
                onClicked: Qt.openUrlExternally(folderUrl)
            }
        }
        QQC2.Label {
            Layout.maximumWidth: Kirigami.Units.gridUnit * 24
            wrapMode: Text.WordWrap
            opacity: 0.7
            font: Kirigami.Theme.smallFont
            text: "games.json — every game and session, with play time and CPU/GPU averages and peaks. "
                + "history.json — the last 24 hours of the temperature graph, saved every 5 minutes. "
                + "procs.json — the busiest apps every 5 seconds over the same 24 hours."
        }

        Kirigami.Separator {
            Kirigami.FormData.isSection: true
            Kirigami.FormData.label: "Start fresh"
        }
        RowLayout {
            Kirigami.FormData.label: "Saved data:"
            spacing: Kirigami.Units.largeSpacing
            QQC2.Button {
                text: "Clear Data…"
                icon.name: "edit-clear-history"
                onClicked: clearDialog.open()
            }
            Kirigami.InlineMessage {
                id: clearedMessage
                Layout.fillWidth: true
                type: Kirigami.MessageType.Positive
                showCloseButton: true
            }
        }
    }

    property alias clearDialog: clearDialog   // for tests
    Kirigami.PromptDialog {
        id: clearDialog
        title: "Clear saved data?"
        subtitle: "This can't be undone."
        standardButtons: Kirigami.Dialog.NoButton
        customFooterActions: [
            Kirigami.Action {
                text: "Clear"
                icon.name: "edit-delete"
                enabled: clearGames.checked || clearGraph.checked
                onTriggered: {
                    const parts = [clearGames.checked ? "games" : "", clearGraph.checked ? "history" : ""].filter(p => p)
                    const request = parts.join(",") + ":" + Date.now()
                    // Straight to the live config so the widget acts now; mirror it into cfg_ so Apply doesn't resend
                    Plasmoid.configuration.clearRequest = request
                    page.cfg_clearRequest = request
                    clearedMessage.text = clearGames.checked && clearGraph.checked ? "Games, sessions, the graph and the process log were cleared."
                        : clearGames.checked ? "Games and sessions were cleared." : "The temperature graph and process log were cleared."
                    clearedMessage.visible = true
                    clearDialog.close()
                }
            },
            Kirigami.Action {
                text: "Cancel"
                icon.name: "dialog-cancel"
                onTriggered: clearDialog.close()
            }
        ]
        ColumnLayout {
            spacing: Kirigami.Units.smallSpacing
            QQC2.CheckBox {
                id: clearGames
                text: "Games and sessions"
                checked: true
            }
            QQC2.CheckBox {
                id: clearGraph
                text: "Temperature graph and process log (last 24 hours)"
                checked: true
            }
        }
    }
}
