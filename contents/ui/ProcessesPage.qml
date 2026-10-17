import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The busiest apps, live — or at the moment under the mouse when hovering the graph.
// Same graph and range picker as the temperatures page, so a spike and its cause line up.
ColumnLayout {
    id: page

    property real sideMargin: 0
    property var ranges: []
    property int rangeIndex: 1
    property real minGraphHeight: 0
    signal rangePicked(int index)

    readonly property int rows: 5
    readonly property var hoverT: chart.hoverInfo ? chart.hoverInfo.t : null
    readonly property var shown: hoverT !== null ? root.procsAt(hoverT) : root.procsNow
    readonly property var apps: shown ? shown.top : []
    // Bars are relative to the busiest app, but never blow a near-idle 2% up into a full bar
    readonly property real barScale: Math.max(5, apps.length ? apps[0].pct : 0)

    function pct(v) { return v >= 10 ? Math.round(v) + "%" : v.toFixed(1) + "%" }
    function clockSecs(t) {
        const twelve = /a/i.test(Qt.locale().timeFormat(Locale.ShortFormat))
        return Qt.formatTime(new Date(t), twelve ? "h:mm:ss AP" : "HH:mm:ss")
    }

    spacing: Kirigami.Units.largeSpacing

    Rectangle {
        Layout.fillWidth: true
        Layout.topMargin: Kirigami.Units.smallSpacing
        Layout.leftMargin: page.sideMargin
        Layout.rightMargin: page.sideMargin
        implicitHeight: listCol.implicitHeight + Kirigami.Units.largeSpacing * 2
        radius: Kirigami.Units.cornerRadius * 2
        color: Qt.alpha(root.cpuColor, root.darkTheme ? 0.09 : 0.07)
        border.color: Qt.alpha(root.cpuColor, page.hoverT !== null ? 0.45 : 0.25)
        Behavior on border.color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

        ColumnLayout {
            id: listCol
            anchors.fill: parent
            anchors.margins: Kirigami.Units.largeSpacing
            // Extra side inset so icons and percentages don't hug the card's edges
            anchors.leftMargin: Kirigami.Units.gridUnit * 1.1
            anchors.rightMargin: Kirigami.Units.gridUnit * 1.1
            spacing: Kirigami.Units.smallSpacing

            // "● Now" live, or the hovered time; total CPU use on the right
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Rectangle {
                    width: 8; height: 8; radius: 4
                    // Green while live, grey while showing the past
                    color: page.hoverT !== null ? Qt.alpha(Kirigami.Theme.textColor, 0.5) : root.gpuColor
                }
                PlasmaComponents.Label {
                    text: page.hoverT !== null ? page.clockSecs(page.shown ? page.shown.t : page.hoverT) : "Now"
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Item { Layout.fillWidth: true }
                PlasmaComponents.Label {
                    visible: page.shown !== null
                    textFormat: Text.StyledText
                    text: page.shown ? `<font color="${Qt.alpha(Kirigami.Theme.textColor, 0.6)}">CPU use</font> <b>${page.pct(page.shown.total)}</b>` : ""
                    font.features: { "tnum": 1 }
                }
            }

            Item {
                Layout.fillWidth: true
                implicitHeight: rowsCol.implicitHeight

                // Always five rows, so names and bars change in place instead of the list jumping around
                Column {
                    id: rowsCol
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: page.rows

                        Item {
                            id: row
                            required property int index
                            readonly property var app: page.apps[index] || null
                            width: rowsCol.width
                            height: Kirigami.Units.gridUnit * 1.45

                            Kirigami.Icon {
                                id: appIcon
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: Kirigami.Units.iconSizes.small
                                height: width
                                source: row.app ? (row.app.icon || "application-x-executable") : ""
                                fallback: "application-x-executable"
                                opacity: row.app ? 1 : 0
                            }
                            PlasmaComponents.Label {
                                id: nameLabel
                                anchors.left: appIcon.right
                                anchors.leftMargin: Kirigami.Units.smallSpacing * 1.5
                                anchors.right: bar.left
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.app ? row.app.name : "—"
                                opacity: row.app ? 1 : 0.3
                                elide: Text.ElideRight
                            }
                            // Usage bar: track + fill
                            Rectangle {
                                id: bar
                                anchors.right: pctLabel.left
                                anchors.rightMargin: Kirigami.Units.largeSpacing
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.round(row.width * 0.36)
                                height: Math.round(Kirigami.Units.gridUnit * 0.4)
                                radius: height / 2
                                color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                                Rectangle {
                                    // Animate the share, not the pixel width, so resizing the popup doesn't animate
                                    property real share: row.app ? Math.min(1, row.app.pct / page.barScale) : 0
                                    Behavior on share { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                                    height: parent.height
                                    radius: parent.radius
                                    width: row.app ? Math.max(height, parent.width * share) : 0
                                    color: root.cpuColor
                                }
                            }
                            PlasmaComponents.Label {
                                id: pctLabel
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: Kirigami.Units.gridUnit * 2.6
                                horizontalAlignment: Text.AlignRight
                                text: row.app ? page.pct(row.app.pct) : ""
                                font.weight: Font.DemiBold
                                font.features: { "tnum": 1 }
                            }
                        }
                    }
                }

                // Nothing recorded for this moment (before the log existed, asleep, or still starting up)
                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    visible: page.shown === null
                    text: page.hoverT !== null ? "No process data for this time" : "Collecting process data…"
                    opacity: 0.6
                }
            }
        }
    }

    // Range picker, same as the temperatures page (hidden with the graph)
    RowLayout {
        visible: chart.visible
        Layout.fillWidth: true
        Layout.leftMargin: page.sideMargin
        Layout.rightMargin: page.sideMargin
        Item { Layout.fillWidth: true }
        Row {
            spacing: 2
            Repeater {
                model: page.ranges
                PlasmaComponents.ToolButton {
                    required property var modelData
                    required property int index
                    text: modelData.label
                    checkable: true
                    checked: page.rangeIndex === index
                    onClicked: page.rangePicked(index)
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
            id: chart
            anchors.fill: parent
            visible: graphArea.height >= page.minGraphHeight
            rangeMs: page.ranges.length ? page.ranges[page.rangeIndex].ms : 0
        }
    }

    PlasmaComponents.Label {
        visible: chart.visible
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        font: Kirigami.Theme.smallFont
        opacity: 0.55
        text: "Share of the whole CPU, sampled every 5 seconds · hover the graph to see what was running"
        wrapMode: Text.WordWrap
    }
}
