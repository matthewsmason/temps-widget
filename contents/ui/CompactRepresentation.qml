import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami

// The two numbers that sit in the panel. Clicking either opens the graph.
MouseArea {
    id: compact

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property real numberSize: Math.max(10, Math.min(height, Kirigami.Units.iconSizes.medium) * 0.5)

    Layout.minimumWidth: row.implicitWidth + Kirigami.Units.smallSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    onClicked: root.expanded = !root.expanded

    Rectangle {
        anchors.fill: parent
        radius: Kirigami.Units.cornerRadius
        color: Kirigami.Theme.highlightColor
        opacity: compact.containsMouse || root.expanded ? 0.18 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Math.round(compact.numberSize * 0.45)

        // Small game icon while a Steam game is running, so you can see it's tracking
        Image {
            visible: root.currentGame !== null && source != ""
            source: root.currentGame && root.currentGame.icon ? "file://" + root.currentGame.icon : ""
            Layout.preferredWidth: Math.round(compact.numberSize * 1.2)
            Layout.preferredHeight: Layout.preferredWidth
            Layout.alignment: Qt.AlignVCenter
            asynchronous: true
        }

        Repeater {
            model: ["cpu", "gpu"]
            Text {
                required property string modelData
                readonly property var value: modelData === "cpu" ? root.cpuNow : root.gpuNow
                text: value === null ? "--" : value
                color: root.levelColor(modelData, value ?? 0)
                font.pixelSize: compact.numberSize
                font.weight: Font.Bold
                font.features: { "tnum": 1 }   // fixed-width digits so the panel doesn't wiggle
                Behavior on color { ColorAnimation { duration: Kirigami.Units.longDuration } }
            }
        }
    }
}
