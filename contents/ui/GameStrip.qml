import QtQuick
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// The game you're playing (or last played) on its blurred Steam banner,
// with play time and that session's CPU/GPU averages and peaks.
// Clicking it opens that session (the one in progress, or the last one) on the game's page.
Rectangle {
    id: strip

    signal openSession(string appid, double start)

    readonly property bool playing: root.currentGame !== null
    readonly property var game: root.currentGame || root.lastSession

    visible: game !== null
    implicitHeight: Kirigami.Units.gridUnit * 3.4
    radius: Kirigami.Units.cornerRadius * 2
    clip: true
    color: Qt.alpha(Kirigami.Theme.textColor, 0.05)
    border.color: Qt.alpha(Kirigami.Theme.textColor, stripMouse.containsMouse ? 0.3 : 0.12)
    Behavior on border.color { ColorAnimation { duration: Kirigami.Units.shortDuration } }

    function clock(t) { return new Date(t).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) }
    function deg(v) { return v === null ? "--" : v + "°" }

    // Per-device line: "CPU avg 74° · peak 88° · 23% used · 2m at 95°+"
    function statLine(key) {
        root.revision
        if (!game) return ""
        const acc = game[key], dev = root.device(key)
        const muted = Qt.alpha(Kirigami.Theme.textColor, 0.6)
        const avg = root.average(acc)
        let s = `<font color="${root.deviceColor(key)}"><b>${dev.label}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">avg</font> <font color="${root.levelColor(key, avg ?? 0)}"><b>${deg(avg)}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">peak</font> <font color="${root.levelColor(key, acc.peak ?? 0)}"><b>${deg(acc.peak)}</b></font>`
            + root.useSuffix(acc, muted)
        if (acc.hotSecs >= 1 && strip.width >= Kirigami.Units.gridUnit * 30)
            s += `&nbsp;&nbsp;<font color="${root.hotColor}">${root.duration(acc.hotSecs)} at ${dev.hot}°+</font>`
        return s
    }

    // Banner art, softened so text stays readable
    Image {
        anchors.fill: parent
        source: strip.game && strip.game.hero ? "file://" + strip.game.hero : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        opacity: 0.55
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.88) }
            GradientStop { position: 0.6; color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.62) }
            GradientStop { position: 1.0; color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.45) }
        }
    }

    // Hover tint over the banner
    Rectangle {
        anchors.fill: parent
        color: Kirigami.Theme.textColor
        opacity: stripMouse.containsMouse ? 0.05 : 0
        Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: Kirigami.Units.largeSpacing
        spacing: Kirigami.Units.largeSpacing

        Image {
            Layout.preferredWidth: 32
            Layout.preferredHeight: 32
            source: strip.game && strip.game.icon ? "file://" + strip.game.icon : ""
            visible: source != ""
            asynchronous: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            PlasmaComponents.Label {
                Layout.fillWidth: true
                text: strip.game ? strip.game.name : ""
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            PlasmaComponents.Label {
                Layout.fillWidth: true
                font: Kirigami.Theme.smallFont
                textFormat: Text.StyledText
                elide: Text.ElideRight
                text: {
                    root.revision
                    const g = strip.game
                    if (!g) return ""
                    if (strip.playing)
                        return `<font color="${root.gpuColor}">●</font> Playing · ${root.duration((Date.now() - g.start) / 1000)}`
                    return `Last played · ${root.duration((g.end - g.start) / 1000)} · ended ${strip.clock(g.end)}`
                }
                opacity: 0.85
            }
        }

        ColumnLayout {
            spacing: 1
            Layout.alignment: Qt.AlignVCenter
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                textFormat: Text.StyledText
                font: Kirigami.Theme.smallFont
                text: strip.statLine("cpu")
            }
            PlasmaComponents.Label {
                Layout.alignment: Qt.AlignRight
                textFormat: Text.StyledText
                font: Kirigami.Theme.smallFont
                text: strip.statLine("gpu")
            }
        }
    }

    // Last child, so it sits above the labels: rich-text labels take hover events themselves
    // (for links), which kept the tint from showing while the cursor was over any text
    MouseArea {
        id: stripMouse
        anchors.fill: parent
        enabled: strip.game !== null
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: strip.openSession(strip.game.appid, strip.game.start)
    }
}
