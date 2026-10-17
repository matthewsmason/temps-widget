import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

// The popup: a stat card per device, a time-range picker, and the shared graph.
PlasmaExtras.Representation {
    id: full

    Layout.preferredWidth: Kirigami.Units.gridUnit * (testWidth || 36)
    // Grow when the game strip shows, so the graph keeps its height
    Layout.preferredHeight: Kirigami.Units.gridUnit * (root.currentGame || root.lastSession ? 30 : 26)
    // In the test window, force the real popup size so snapshots match what the panel shows
    // Test hook: temps-width=<gridUnits> fixes the width so narrow layouts can be checked
    readonly property real testWidth: Number((Qt.application.arguments.find(a => String(a).startsWith("temps-width=")) || "=0").split("=")[1])
    Layout.minimumWidth: testWidth ? Kirigami.Units.gridUnit * testWidth
        : root.demo ? Layout.preferredWidth : Kirigami.Units.gridUnit * 28   // narrowest where every page still fits
    Layout.maximumWidth: testWidth ? Kirigami.Units.gridUnit * testWidth : -1
    Layout.minimumHeight: root.demo ? Layout.preferredHeight : Kirigami.Units.gridUnit * 18

    readonly property var ranges: [
        { label: "3 min", ms: 3 * 60000 },    // matches the Stream Deck key's graph
        { label: "10 min", ms: 10 * 60000 },
        { label: "1 hour", ms: 3600000 },
        { label: "6 hours", ms: 6 * 3600000 },
        { label: "24 hours", ms: 0 },   // everything kept: the graph holds the last 24 hours
    ]
    // Inset that lines the cards up with the graph: its temperature labels on the left,
    // the end of its gridlines on the right (TempChart.padR)
    readonly property real sideMargin: Kirigami.Units.gridUnit * 0.8
    // Below this height the graph is too squished to read, so it (and its range picker) is hidden
    readonly property real minGraphHeight: Kirigami.Units.gridUnit * 7
    property int rangeIndex: Qt.application.arguments.indexOf("temps-session") >= 0 ? 4 : 2   // 24 hours / 1 hour

    // Pages: "temps" (graph) → "games" (Activity: the process log card, then one card per game)
    //        → "game" (that game's sessions) or "procs" (busiest apps over time)
    // Test args: temps-games, temps-game=<appid>, temps-procs
    readonly property string gameArg: (Qt.application.arguments.find(a => String(a).startsWith("temps-game=")) || "").slice(11)
    property string page: gameArg ? "game" : Qt.application.arguments.indexOf("temps-procs") >= 0 ? "procs"
        : Qt.application.arguments.indexOf("temps-games") >= 0 ? "games" : "temps"
    property string selectedAppid: gameArg
    property string procsBackTo: "games"  // Processes: from Activity, or from a card's "% used" on "temps"
    // Coming back to the popup later starts on the temperatures page
    Connections {
        target: root
        function onExpandedChanged() { if (!root.expanded && !root.demo) full.page = "temps" }
    }

    header: PlasmaExtras.PlasmoidHeading {
        RowLayout {
            anchors.fill: parent
            // Same inset as the cards and graph below, so the title lines up with them
            anchors.leftMargin: full.sideMargin
            anchors.rightMargin: full.sideMargin
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.ToolButton {
                id: backButton
                visible: full.page !== "temps"
                icon.name: "go-previous"
                readonly property string target: full.page === "game" ? "games" : full.page === "procs" ? full.procsBackTo : "temps"
                onClicked: full.page = target
                PlasmaComponents.ToolTip { text: backButton.target === "temps" ? "Back to temperatures" : "Back to activity" }
            }
            PlasmaExtras.Heading {
                Layout.fillWidth: true
                level: 1
                text: full.page === "games" ? "Activity"
                    : full.page === "procs" ? "Processes"
                    : full.page === "game" ? (sessionsPage.game ? sessionsPage.game.name : "Game")
                    : "Temperatures"
                elide: Text.ElideRight
            }
        }
    }

    contentItem: StackLayout {
        currentIndex: ({ temps: 0, games: 1, game: 2, procs: 3 })[full.page] ?? 0

    ColumnLayout {
        spacing: Kirigami.Units.largeSpacing

        GameStrip {
            id: gameStrip
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.leftMargin: full.sideMargin
            Layout.rightMargin: full.sideMargin
            onOpenSession: (appid, start) => {
                full.selectedAppid = appid
                full.page = "game"   // Back from a game's page always goes to Activity, wherever it was opened from
                sessionsPage.showSession(start)
            }
            // Test hook (with temps-demo): `temps-strip-click` ends the demo game, then clicks the "Last played" strip;
            // `temps-strip-click=playing` clicks it while the game is still running
            Timer {
                readonly property string arg: Qt.application.arguments.find(a => String(a).startsWith("temps-strip-click")) || ""
                interval: 1200
                running: root.demo && arg !== ""
                onTriggered: {
                    if (root.currentGame && arg !== "temps-strip-click=playing") root.endGame(Date.now())
                    Qt.callLater(() => gameStrip.openSession(gameStrip.game.appid, gameStrip.game.start))
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: false   // the cards fill this row's height, but the row itself stays at its natural size
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.leftMargin: full.sideMargin
            Layout.rightMargin: full.sideMargin
            spacing: Kirigami.Units.largeSpacing

            Repeater {
                model: ["cpu", "gpu"]

                // One card per device
                Rectangle {
                    id: card
                    required property string modelData
                    readonly property var dev: root.device(modelData)
                    // Copy on each sample: returning the same object would look "unchanged" to QML and never refresh
                    readonly property var s: { root.revision; return Object.assign({}, root.stats[modelData]) }
                    readonly property var now: modelData === "cpu" ? root.cpuNow : root.gpuNow
                    readonly property var use: modelData === "cpu" ? root.cpuUse : root.gpuUse

                    Layout.fillWidth: true
                    Layout.fillHeight: true   // both cards as tall as the taller one (the GPU's has an extra line)
                    Layout.preferredWidth: 1
                    implicitHeight: cardCol.implicitHeight + Kirigami.Units.largeSpacing * 2
                    radius: Kirigami.Units.cornerRadius * 2
                    color: Qt.alpha(root.deviceColor(modelData), root.darkTheme ? 0.09 : 0.07)
                    border.color: Qt.alpha(root.deviceColor(modelData), 0.25)

                    ColumnLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing

                    // Header: ● CPU  AMD Ryzen 7 9800X3D, centered; the model name elides if the card is too narrow
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: root.deviceColor(card.modelData)
                        }
                        PlasmaComponents.Label {
                            text: card.dev.label
                            font.weight: Font.DemiBold
                            color: root.deviceColor(card.modelData)
                        }
                        PlasmaComponents.Label {
                            id: modelLabel
                            // Natural width, but never more than what's left of the card after the dot and "CPU"
                            Layout.maximumWidth: Math.max(0, cardCol.width - modelLabel.x)
                            text: card.modelData === "cpu" ? root.cpuModel : root.gpuModel
                            opacity: 0.7
                            elide: Text.ElideRight
                        }
                    }

                    // Number + stats centered as one group. Both parts get fixed widths (sized for the widest
                    // likely text), so the group doesn't drift as values change and both cards match.
                    // Stats as a table pinned to the right edge (values right-aligned under the header's end);
                    // the big number is centered in the space that's left. The ° hangs off the digits and
                    // isn't counted when centering.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.gridUnit

                        ColumnLayout {
                            Layout.fillWidth: true
                            // A layout is otherwise capped at its widest child; let it take all the spare room
                            Layout.maximumWidth: Number.POSITIVE_INFINITY
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 0
                            PlasmaComponents.Label {
                                id: bigTemp
                                Layout.alignment: Qt.AlignHCenter
                                text: card.now === null ? "--" : card.now
                                font.pixelSize: Kirigami.Units.gridUnit * 2.1
                                font.weight: Font.Bold
                                font.features: { "tnum": 1 }
                                color: root.levelColor(card.modelData, card.now ?? 0)
                                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
                                PlasmaComponents.Label {
                                    visible: card.now !== null
                                    x: parent.width
                                    text: "°"
                                    font: parent.font
                                    color: parent.color
                                }
                            }
                            // "23% used" under the temperature; clicking it opens the Processes page
                            PlasmaComponents.Label {
                                Layout.alignment: Qt.AlignHCenter
                                textFormat: Text.StyledText
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                text: card.use === null ? "" : `<b>${card.use.replace("<", "&lt;")}%</b> <font color="${Qt.alpha(Kirigami.Theme.textColor, 0.6)}">used</font>`
                                // Flat-button frame on hover, like Plasma's tool buttons
                                Rectangle {
                                    z: -1
                                    anchors.fill: parent
                                    anchors.leftMargin: -Kirigami.Units.smallSpacing * 1.5
                                    anchors.rightMargin: -Kirigami.Units.smallSpacing * 1.5
                                    anchors.topMargin: -2
                                    anchors.bottomMargin: -2
                                    radius: Kirigami.Units.cornerRadius
                                    color: Qt.alpha(Kirigami.Theme.textColor, useMouse.pressed ? 0.12 : 0.06)
                                    border.color: Qt.alpha(Kirigami.Theme.highlightColor, 0.8)
                                    opacity: useMouse.containsMouse ? 1 : 0
                                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                                }
                                // A child, so it sits above the label (rich-text labels take hover themselves)
                                MouseArea {
                                    id: useMouse
                                    anchors.fill: parent
                                    anchors.margins: -Kirigami.Units.smallSpacing
                                    enabled: card.use !== null
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: { full.procsBackTo = "temps"; full.page = "procs" }
                                    // Test hook: `temps-use-click` (with temps-demo) clicks the CPU card's "% used"
                                    Timer {
                                        interval: 1200
                                        running: root.demo && card.modelData === "cpu"
                                            && Qt.application.arguments.indexOf("temps-use-click") >= 0
                                        onTriggered: useMouse.clicked(null)
                                    }
                                    PlasmaComponents.ToolTip {
                                        text: "Show which apps are using the CPU"
                                        visible: useMouse.containsMouse
                                    }
                                }
                            }
                            // GPU only: board power and hotspot (the die's hottest point), live
                            PlasmaComponents.Label {
                                readonly property bool show: card.modelData === "gpu" && (root.gpuPowerNow !== null || root.gpuHotNow !== null)
                                visible: show
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 2
                                textFormat: Text.StyledText
                                font.pointSize: Kirigami.Theme.smallFont.pointSize
                                readonly property color muted: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                                text: !show ? "" : (root.gpuPowerNow !== null ? `<b>${root.gpuPowerNow}</b> <font color="${muted}">W</font>` : "")
                                    + (root.gpuPowerNow !== null && root.gpuHotNow !== null ? ` <font color="${muted}">·</font> ` : "")
                                    + (root.gpuHotNow !== null ? `<font color="${muted}">hotspot</font> <font color="${root.hotspotColor(root.gpuHotNow)}"><b>${root.gpuHotNow}°</b></font>` : "")
                            }
                        }

                        GridLayout {
                            Layout.fillWidth: false
                            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            // Breathing room from the card's edge, so the values don't hug it
                            Layout.rightMargin: Kirigami.Units.gridUnit * 1.1
                            columns: 2
                            columnSpacing: Kirigami.Units.gridUnit
                            rowSpacing: 1

                            component Key: PlasmaComponents.Label {
                                opacity: 0.65
                                font: Kirigami.Theme.smallFont
                                Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                            }
                            component Val: PlasmaComponents.Label {
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                                Layout.fillWidth: false
                                Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                            }

                            Key { text: "Low" }
                            Val { text: card.s.low === null ? "--" : card.s.low + "°" }
                            Key { text: "High" }
                            Val {
                                // No "at 2:02 AM" after it: at some widths it spilled out of the card (the graph shows when)
                                text: card.s.high === null ? "--" : card.s.high + "°"
                                color: root.levelColor(card.modelData, card.s.high ?? 0)
                            }
                            Key { text: `At ${card.dev.hot}°+` }
                            Val {
                                text: root.duration(card.s.hotSecs)
                                color: card.s.hotSecs >= 1 ? root.hotColor : Kirigami.Theme.textColor
                            }
                            Key { text: "Longest" }
                            Val {
                                text: root.duration(card.s.hotLongest)
                                color: card.s.hotLongest >= 1 ? root.hotColor : Kirigami.Theme.textColor
                            }
                        }
                    }
                    }
                }
            }
        }

        // Pump and fan speeds, live, centered under the cards (hidden when the fan chip can't be read,
        // e.g. nct6775 not loaded)
        PlasmaComponents.Label {
            readonly property var parts: {
                const muted = Qt.alpha(Kirigami.Theme.textColor, 0.6)
                const n = v => `<b>${Number(v).toLocaleString(Qt.locale(), "f", 0)}</b> <font color="${muted}">rpm</font>`
                const out = []
                // Turned off in settings: only a stopped pump still shows (it's a warning, not a reading)
                if (!(root.cfg.showFans ?? true))
                    return root.pumpRpm !== null && root.pumpRpm < 300 ? [`<font color="${root.hotColor}"><b>Pump stopped</b></font>`] : []
                // A stopped pump on a running PC is worth shouting about
                if (root.pumpRpm !== null)
                    out.push(root.pumpRpm < 300 ? `<font color="${root.hotColor}"><b>Pump stopped</b></font>`
                                                : `<font color="${muted}">Pump</font> ${n(root.pumpRpm)}`)
                if (root.radiatorRpm !== null) out.push(`<font color="${muted}">Radiator</font> ${n(root.radiatorRpm)}`)
                if (root.caseFanRpm !== null) out.push(`<font color="${muted}">Case</font> ${n(root.caseFanRpm)}`)
                if (root.chipsetFanRpm !== null) out.push(`<font color="${muted}">Chipset</font> ${n(root.chipsetFanRpm)}`)
                if (root.gpuFanRpm !== null)
                    out.push(`<font color="${muted}">GPU fan</font> ` + (root.gpuFanRpm === 0 ? "<b>off</b>" : n(root.gpuFanRpm)))
                return out
            }
            visible: parts.length > 0 && (root.pumpRpm !== null || root.radiatorRpm !== null || root.caseFanRpm !== null || root.chipsetFanRpm !== null)
            Layout.fillWidth: true
            Layout.leftMargin: full.sideMargin
            Layout.rightMargin: full.sideMargin
            horizontalAlignment: Text.AlignHCenter
            textFormat: Text.StyledText
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            font.features: { "tnum": 1 }
            wrapMode: Text.WordWrap
            text: parts.join(`&nbsp;&nbsp;<font color="${Qt.alpha(Kirigami.Theme.textColor, 0.35)}">·</font>&nbsp;&nbsp;`)
        }

        // Activity button on the left, segmented range picker on the right
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: full.sideMargin
            Layout.rightMargin: full.sideMargin
            // An outlined button (unlike the flat range picker) so it reads as something to click.
            // Own background because this Plasma theme draws buttons without a visible edge.
            PlasmaComponents.ToolButton {
                id: gamesButton
                icon.name: "utilities-system-monitor"
                text: "Activity"
                // Only Tab gives it focus; otherwise opening the popup draws it highlighted like a selected range
                focusPolicy: Qt.TabFocus
                onClicked: full.page = "games"
                leftPadding: Kirigami.Units.largeSpacing
                rightPadding: Kirigami.Units.largeSpacing * 1.5
                topPadding: Kirigami.Units.smallSpacing * 1.5
                bottomPadding: Kirigami.Units.smallSpacing * 1.5
                background: Rectangle {
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.alpha(Kirigami.Theme.textColor, gamesButton.down ? 0.16 : gamesButton.hovered ? 0.10 : 0.04)
                    border.width: 1
                    border.color: Qt.alpha(Kirigami.Theme.textColor, gamesButton.hovered ? 0.45 : 0.25)
                    Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }
                }
            }
            Item { Layout.fillWidth: true }
            Row {
                visible: mainChart.visible
                spacing: 2
                Repeater {
                    model: full.ranges
                    PlasmaComponents.ToolButton {
                        required property var modelData
                        required property int index
                        text: modelData.label
                        checkable: true
                        checked: full.rangeIndex === index
                        onClicked: full.rangeIndex = index
                    }
                }
            }
        }

        // Takes whatever height is left; the graph only shows when that's enough
        Item {
            id: graphArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            TempChart {
                id: mainChart
                anchors.fill: parent
                visible: graphArea.height >= full.minGraphHeight
                rangeMs: full.ranges[full.rangeIndex].ms
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font: Kirigami.Theme.smallFont
            opacity: 0.55
            text: {
                const d = new Date(root.recordingSince), today = new Date()
                const time = d.toLocaleTimeString(Qt.locale(), Locale.ShortFormat)
                const yesterday = new Date(today.getFullYear(), today.getMonth(), today.getDate() - 1)
                const day = d.toDateString() === today.toDateString() ? ""
                    : d.toDateString() === yesterday.toDateString() ? "yesterday " : d.toLocaleDateString(Qt.locale(), "MMM d") + " "
                return `Recording since ${day}${time} · keeps the last 24 hours`
            }
            wrapMode: Text.WordWrap
        }
    }

    GamesPage {
        sideMargin: full.sideMargin
        onOpenGame: appid => { full.selectedAppid = appid; full.page = "game" }
        onOpenProcesses: { full.procsBackTo = "games"; full.page = "procs" }
    }

    GameSessionsPage {
        id: sessionsPage
        sideMargin: full.sideMargin
        appid: full.selectedAppid
        // Deleting a game's last session removes the game: leave its (now empty) page
        // (not before the log has loaded: the temps-game= test hook opens this page at startup)
        property bool hadGame: false
        onGameChanged: {
            if (game) hadGame = true
            else if (hadGame && full.page === "game") full.page = "games"
        }
    }

    ProcessesPage {
        sideMargin: full.sideMargin
        minGraphHeight: full.minGraphHeight
        ranges: full.ranges
        rangeIndex: full.rangeIndex
        onRangePicked: index => full.rangeIndex = index
    }
    }
}
