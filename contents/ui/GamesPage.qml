import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// Activity: the process log card on top, then every game you've played (saved across reboots), most recent first.
PlasmaComponents.ScrollView {
    id: page

    property real sideMargin: 0
    signal openGame(string appid)   // a card was clicked: show that game's sessions
    signal openProcesses()
    readonly property var games: root.gameLogView()

    function deg(v) { return v === null || v === undefined ? "--" : v + "°" }
    function lastPlayedText(g) {
        if (g.playing) return ""
        const d = new Date(g.lastPlayed), today = new Date()
        // Calendar-day difference (QML's JS can't parse toDateString() back, so build midnights directly)
        const midnight = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
        const days = Math.round((midnight(today) - midnight(d)) / 86400000)
        const when = days === 0 ? "today" : days === 1 ? "yesterday" : days < 7 ? days + " days ago"
            : d.toLocaleDateString(Qt.locale(), "MMM d")
        return ` · last played ${when}`
    }
    // "CPU  avg 74°  peak 95°  · 23% used"
    function tempLine(g, key) {
        const acc = g[key], avg = acc.n ? Math.round(acc.sum / acc.n) : null
        const muted = Qt.alpha(Kirigami.Theme.textColor, 0.6)
        return `<font color="${root.deviceColor(key)}"><b>${root.device(key).label}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">avg</font> <font color="${root.levelColor(key, avg ?? 0)}"><b>${deg(avg)}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">peak</font> <font color="${root.levelColor(key, acc.peak ?? 0)}"><b>${deg(acc.peak)}</b></font>`
            + root.useSuffix(acc, muted)
    }

    contentWidth: availableWidth
    // Never scroll sideways: the content always fits the width, and an automatic horizontal bar
    // flickers on/off with the vertical one (a binding loop)
    PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

    ColumnLayout {
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing

        // Process log: always first
        Rectangle {
            id: procCard
            readonly property var now: root.procsNow
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.smallSpacing
            Layout.leftMargin: page.sideMargin
            Layout.rightMargin: page.sideMargin
            implicitHeight: procRow.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius * 2
            color: Qt.alpha(root.cpuColor, procMouse.containsMouse ? 0.15 : root.darkTheme ? 0.09 : 0.07)
            border.color: Qt.alpha(root.cpuColor, procMouse.containsMouse ? 0.45 : 0.25)
            Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

            MouseArea {
                id: procMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: page.openProcesses()
            }

            RowLayout {
                id: procRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing

                Kirigami.Icon {
                    source: "utilities-system-monitor"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.medium
                    Layout.preferredHeight: Kirigami.Units.iconSizes.medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    PlasmaComponents.Label {
                        text: "Process Log"
                        font.weight: Font.Bold
                    }
                    // "Now: Steam 12% · Zen 4% · Discord 1%"
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        font: Kirigami.Theme.smallFont
                        textFormat: Text.StyledText
                        elide: Text.ElideRight
                        readonly property color muted: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                        text: !procCard.now ? `<font color="${muted}">Collecting process data…</font>`
                            : `<font color="${muted}">Now:</font> ` + procCard.now.top.slice(0, 3)
                                .map(a => `${a.name} <b>${a.pct >= 10 ? Math.round(a.pct) : a.pct.toFixed(1)}%</b>`)
                                .join(` <font color="${muted}">·</font> `)
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        font: Kirigami.Theme.smallFont
                        opacity: 0.6
                        elide: Text.ElideRight
                        text: "Which apps used the CPU, over the last 24 hours"
                    }
                }
                Kirigami.Icon {
                    source: "go-next-symbolic"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                    opacity: procMouse.containsMouse ? 0.9 : 0.4
                }
            }
        }

        PlasmaComponents.Label {
            Layout.leftMargin: page.sideMargin
            Layout.topMargin: Kirigami.Units.smallSpacing
            text: "Games"
            font.weight: Font.DemiBold
            opacity: 0.7
        }

        PlasmaComponents.Label {
            visible: page.games.length === 0
            Layout.fillWidth: true
            Layout.topMargin: Kirigami.Units.gridUnit * 2
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            opacity: 0.6
            text: "No games logged yet.\nLaunch a game from Steam and it'll show up here."
        }

        Repeater {
            model: page.games

            Rectangle {
                id: card
                required property var modelData
                readonly property var g: modelData

                Layout.fillWidth: true
                Layout.leftMargin: page.sideMargin
                Layout.rightMargin: page.sideMargin
                implicitHeight: cardRow.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius * 2
                color: Qt.alpha(Kirigami.Theme.textColor, cardMouse.containsMouse ? 0.09 : g.playing ? 0.08 : 0.045)
                border.color: g.playing ? Qt.alpha(root.gpuColor, 0.5) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
                Behavior on color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

                MouseArea {
                    id: cardMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: page.openGame(card.g.appid)
                }

                RowLayout {
                    id: cardRow
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.largeSpacing

                    // Steam's wide library banner (460×215), with rounded corners
                    Item {
                        Layout.preferredWidth: Math.min(Math.round(Kirigami.Units.gridUnit * 4.4 * 460 / 215), Math.round(card.width * 0.3))
                        Layout.preferredHeight: Math.round(Layout.preferredWidth * 215 / 460)
                        Layout.alignment: Qt.AlignVCenter
                        Kirigami.ShadowedImage {
                            anchors.fill: parent
                            radius: Kirigami.Units.cornerRadius
                            color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                            source: card.g.header ? "file://" + card.g.header
                                  : card.g.icon ? "file://" + card.g.icon : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            mipmap: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            PlasmaComponents.Label {
                                Layout.fillWidth: true
                                text: card.g.name
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                            }
                            PlasmaComponents.Label {
                                visible: card.g.playing === true
                                text: "● Playing"
                                color: root.gpuColor
                                font: Kirigami.Theme.smallFont
                            }
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            font: Kirigami.Theme.smallFont
                            opacity: 0.65
                            elide: Text.ElideRight
                            text: `${card.g.sessions} session${card.g.sessions === 1 ? "" : "s"}`
                                + ` · ${root.duration(card.g.totalSecs)} total` + page.lastPlayedText(card.g)
                        }
                        Item { implicitHeight: 2 }
                        // One line per device: with usage added, both side by side no longer fit
                        Repeater {
                            model: ["cpu", "gpu"]
                            PlasmaComponents.Label {
                                required property string modelData
                                Layout.fillWidth: true
                                textFormat: Text.StyledText
                                font: Kirigami.Theme.smallFont
                                elide: Text.ElideRight
                                text: page.tempLine(card.g, modelData)
                            }
                        }
                        PlasmaComponents.Label {
                            Layout.fillWidth: true
                            visible: text !== ""
                            textFormat: Text.StyledText
                            font: Kirigami.Theme.smallFont
                            elide: Text.ElideRight
                            text: root.gpuExtraLine(card.g.gpu, Qt.alpha(Kirigami.Theme.textColor, 0.6))
                        }
                        PlasmaComponents.Label {
                            textFormat: Text.StyledText
                            font: Kirigami.Theme.smallFont
                            readonly property color muted: Qt.alpha(Kirigami.Theme.textColor, 0.6)
                            text: `<font color="${muted}">Avg session</font> <b>${root.duration(card.g.totalSecs / Math.max(1, card.g.sessions))}</b>`
                                + `&nbsp;&nbsp;&nbsp;&nbsp;<font color="${muted}">Longest</font> <b>${root.duration(card.g.longestSecs)}</b>`
                        }
                    }

                    Kirigami.Icon {
                        source: "go-next-symbolic"
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        opacity: cardMouse.containsMouse ? 0.9 : 0.4
                    }
                }
            }
        }

        Item { implicitHeight: Kirigami.Units.smallSpacing }
    }
}
