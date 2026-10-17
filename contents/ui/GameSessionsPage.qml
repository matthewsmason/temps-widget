import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Controls as QQC2
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

// One game's sessions, newest first: when, how long, CPU/GPU averages and peaks, and a small graph.
PlasmaComponents.ScrollView {
    id: page

    property string appid: ""
    property real sideMargin: 0
    readonly property var info: root.sessionsFor(appid)
    readonly property var game: info.game
    readonly property var sessions: info.sessions
    readonly property color muted: Qt.alpha(Kirigami.Theme.textColor, 0.6)
    property bool testDeleteFired: false   // the delete test hook runs once per window (cards are rebuilt after a delete)

    // Opened from the strip on the temperatures page: scroll to that session and flash its card
    property double flashStart: 0
    function showSession(start) {
        flashStart = start
        flashTimer.restart()
        Qt.callLater(scrollToFlash)   // after the page has laid out this game's cards
    }
    function scrollToFlash() {
        const card = cards.itemAt(sessions.findIndex(s => s.start === flashStart))
        const flick = page.contentItem
        if (!card || !flick) return
        flick.contentY = Math.max(0, Math.min(card.y - Kirigami.Units.largeSpacing, flick.contentHeight - flick.height))
    }
    Timer { id: flashTimer; interval: 1600; onTriggered: page.flashStart = 0 }

    function deg(v) { return v === null || v === undefined ? "--" : v + "°" }
    function clock(t) { return new Date(t).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) }
    // "today", "yesterday", or "Oct 13" (with the year when it isn't this year)
    function shortDay(t) {
        const d = new Date(t), now = new Date()
        const midnight = x => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime()
        const days = Math.round((midnight(now) - midnight(d)) / 86400000)
        return days === 0 ? "today" : days === 1 ? "yesterday"
            : d.toLocaleDateString(Qt.locale(), d.getFullYear() === now.getFullYear() ? "MMM d" : "MMM d, yyyy")
    }
    function day(t) { return new Date(t).toLocaleDateString(Qt.locale(), "ddd, MMM d") }
    // "CPU  avg 74°  peak 95°  · 23% used  · 6m at 95°+"
    // "Max hotspot 92°  · Max power 312 W" ("" for sessions from before these were recorded)
    function gpuMaxLine(acc) {
        const parts = []
        if (acc.hotPeak !== undefined && acc.hotPeak !== null)
            parts.push(`<font color="${muted}">Max hotspot</font> <font color="${root.hotspotColor(acc.hotPeak)}"><b>${acc.hotPeak}°</b></font>`)
        if (acc.powPeak !== undefined && acc.powPeak !== null)
            parts.push(`<font color="${muted}">Max power</font> <b>${acc.powPeak} W</b>`)
        return parts.join(`&nbsp;&nbsp;<font color="${muted}">·</font> `)
    }
    function tempLine(s, key, roomy) {
        const acc = s[key], avg = root.average(acc), dev = root.device(key)
        let line = `<font color="${root.deviceColor(key)}"><b>${dev.label}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">avg</font> <font color="${root.levelColor(key, avg ?? 0)}"><b>${deg(avg)}</b></font>`
            + `&nbsp;&nbsp;<font color="${muted}">peak</font> <font color="${root.levelColor(key, acc.peak ?? 0)}"><b>${deg(acc.peak)}</b></font>`
            + root.useSuffix(acc, muted)
        if (acc.hotSecs >= 60 && roomy)
            line += `&nbsp;&nbsp;<font color="${root.hotColor}">${root.duration(acc.hotSecs)} at ${dev.hot}°+</font>`
        return line
    }

    // The game's Steam poster, stretched over the whole page, heavily blurred and dimmed, with a vignette
    // that fades it into the popup at every edge. A background, so it stays put while the cards scroll
    // over it. Falls back to the banner when no poster is cached.
    readonly property string capsule: root.capsuleFor(appid)
    background: Item {
        id: backdrop
        clip: true
        Image {
            id: poster
            // Centered on the page and only as wide as the poster's shape allows at the page's height
            // (plus a margin for the blur's soft edges), so its middle sits in the middle of the page
            // instead of being cropped to a band; the vignette blends its sides away.
            height: parent.height + 80
            width: Math.max(parent.width * 0.7, Math.min(parent.width + 80, height * (implicitWidth / Math.max(1, implicitHeight)) + 80))
            x: (parent.width - width) / 2
            y: -40
            source: page.capsule ? "file://" + page.capsule
                : page.game && page.game.hero ? "file://" + page.game.hero : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0.2   // dimmer since the All-time card shows the poster itself
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true; blur: 1.0; blurMax: 64
                brightness: -0.25
                maskEnabled: true
                maskSource: vignette
                // threshold 0.5 + spread 1 = a smooth 0→1 ramp over the mask's alpha (not a cutoff)
                maskThresholdMin: 0.5
                maskSpreadAtMin: 1
            }
        }
        // Vignette mask: an ellipse filling the page, opaque in the middle and clear at the edges.
        // Drawn as a circle and squashed to the page's shape (gradients here are only circular).
        Item {
            id: vignette
            width: poster.width
            height: poster.height
            visible: false
            layer.enabled: true
            Shape {
                readonly property real size: 200
                width: size; height: size
                transform: Scale { xScale: vignette.width / 200; yScale: vignette.height / 200 }
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeWidth: -1
                    fillGradient: RadialGradient {
                        centerX: 100; centerY: 100; centerRadius: 100
                        focalX: 100; focalY: 100
                        GradientStop { position: 0.0; color: "white" }
                        GradientStop { position: 0.6; color: "white" }
                        GradientStop { position: 1.0; color: "transparent" }
                    }
                    startX: 0; startY: 0
                    PathLine { x: 200; y: 0 }
                    PathLine { x: 200; y: 200 }
                    PathLine { x: 0; y: 200 }
                    PathLine { x: 0; y: 0 }
                }
            }
        }
    }

    contentWidth: availableWidth
    // Never scroll sideways: the content always fits the width, and an automatic horizontal bar
    // flickers on/off with the vertical one (a binding loop)
    PlasmaComponents.ScrollBar.horizontal.policy: PlasmaComponents.ScrollBar.AlwaysOff

    ColumnLayout {
        width: page.availableWidth
        spacing: Kirigami.Units.largeSpacing

        // All-time: every session of the game together. Averages are weighted by play time (from the game's
        // running totals, so they also cover sessions too old to have a card); "Highest" is the record peak.
        // Hotspot and power only count sessions recorded since 2026-10-13, and hide when there are none.
        Rectangle {
            id: overall
            visible: page.game !== null
            readonly property var g: page.game
            Layout.fillWidth: true
            Layout.leftMargin: page.sideMargin
            Layout.rightMargin: page.sideMargin
            Layout.topMargin: Kirigami.Units.smallSpacing
            implicitHeight: overallRow.implicitHeight + Kirigami.Units.largeSpacing * 2
            radius: Kirigami.Units.cornerRadius * 2
            color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.12)

            // [{ key, value (rich text), start (the session to jump to, if any) }]
            readonly property var records: {
                const list = page.sessions
                if (!g || !list.length) return []
                const end = s => s.playing ? Date.now() : s.end
                const muted = page.muted
                const when = s => ` <font color="${muted}">· ${page.shortDay(s.start)}</font>`
                const best = f => list.reduce((b, s) => f(s) !== null && (!b || f(s) > f(b)) ? s : b, null)
                const r = []
                const first = list[list.length - 1]
                r.push({ key: "First played", value: page.shortDay(first.start), start: first.start })
                r.push({ key: "Last played", value: list[0].playing ? "now" : page.shortDay(end(list[0])), start: list[0].start })
                const longest = best(s => end(s) - s.start)
                if (list.length > 1) r.push({ key: "Longest", value: `<b>${root.duration((end(longest) - longest.start) / 1000)}</b>` + when(longest), start: longest.start })
                const cpu = best(s => s.cpu.peak ?? null)
                if (cpu) r.push({ key: "Hottest CPU", value: `<font color="${root.levelColor("cpu", cpu.cpu.peak)}"><b>${cpu.cpu.peak}°</b></font>` + when(cpu), start: cpu.start })
                // GPU: by hotspot when sessions have it (the more telling number), else edge
                const hot = best(s => s.gpu.hotPeak ?? null)
                const gpu = hot || best(s => s.gpu.peak ?? null)
                if (gpu) r.push({ key: "Hottest GPU", value: hot
                    ? `<font color="${muted}">hotspot</font> <font color="${root.hotspotColor(hot.gpu.hotPeak)}"><b>${hot.gpu.hotPeak}°</b></font>` + when(hot)
                    : `<font color="${root.levelColor("gpu", gpu.gpu.peak)}"><b>${gpu.gpu.peak}°</b></font>` + when(gpu), start: gpu.start })
                return r
            }

            readonly property var rows: {
                if (!g) return []
                const r = []
                const deg = v => v === null || v === undefined ? "--" : v + "°"
                for (const key of ["cpu", "gpu"]) {
                    const acc = g[key], avg = root.average(acc), use = root.usage(root.averageUse(acc))
                    r.push({ label: root.device(key).label, dot: root.deviceColor(key),
                             avg: deg(avg), avgColor: root.levelColor(key, avg ?? 0),
                             peak: deg(acc.peak), peakColor: root.levelColor(key, acc.peak ?? 0),
                             use: use === null ? "--" : use + "%" })
                }
                const gpu = g.gpu, hAvg = root.averageOf(gpu, "hot"), pAvg = root.averageOf(gpu, "pow")
                if (hAvg !== null)
                    r.push({ label: "Hotspot", dot: root.deviceColor("gpu"), avg: hAvg + "°", avgColor: root.hotspotColor(hAvg),
                             peak: deg(gpu.hotPeak), peakColor: root.hotspotColor(gpu.hotPeak ?? 0), use: "" })
                if (pAvg !== null)
                    r.push({ label: "GPU power", dot: root.deviceColor("gpu"), avg: pAvg + " W", avgColor: Kirigami.Theme.textColor,
                             peak: (gpu.powPeak ?? "--") + " W", peakColor: Kirigami.Theme.textColor, use: "" })
                return r
            }

            RowLayout {
                id: overallRow
                anchors.fill: parent
                anchors.margins: Kirigami.Units.largeSpacing
                spacing: Kirigami.Units.largeSpacing * 1.5

                ColumnLayout {
                    id: overallCol
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: Kirigami.Units.smallSpacing

                    PlasmaComponents.Label {
                        text: "All-time"
                        font.weight: Font.Bold
                    }
                    PlasmaComponents.Label {
                        Layout.fillWidth: true
                        font: Kirigami.Theme.smallFont
                        textFormat: Text.StyledText
                        wrapMode: Text.WordWrap
                        text: !overall.g ? "" :
                            `<b>${overall.g.sessions}</b> session${overall.g.sessions === 1 ? "" : "s"}`
                            + ` <font color="${page.muted}">·</font> <b>${root.duration(overall.g.totalSecs)}</b> <font color="${page.muted}">total</font>`
                            + ` <font color="${page.muted}">· avg session</font> <b>${root.duration(overall.g.totalSecs / Math.max(1, overall.g.sessions))}</b>`
                            + ` <font color="${page.muted}">· longest</font> <b>${root.duration(overall.g.longestSecs)}</b>`
                    }

                    // The stats table, then the records: side by side when there's room (a wide popup), else stacked
                    GridLayout {
                        Layout.topMargin: 2
                        // side by side only when the table, the records AND the poster all fit (the poster got squeezed off the card otherwise)
                        // (worked out from the card's width, with ~6 gridUnits kept for the poster, so the choice can't feed back on itself)
                        columns: overall.width - Kirigami.Units.largeSpacing * 3.5 - Kirigami.Units.gridUnit * 6
                            >= tableGrid.implicitWidth + recordsGrid.implicitWidth + Kirigami.Units.gridUnit * 2 ? 2 : 1
                        columnSpacing: Kirigami.Units.gridUnit * 2
                        rowSpacing: Kirigami.Units.largeSpacing

                        GridLayout {
                            id: tableGrid
                            Layout.alignment: Qt.AlignTop
                            columns: 4
                            columnSpacing: Kirigami.Units.gridUnit * 1.5
                            rowSpacing: 1

                            // header
                            Item { implicitWidth: 1; implicitHeight: 1 }
                            Repeater {
                                model: ["Average", "Highest", "Usage"]
                                PlasmaComponents.Label {
                                    required property string modelData
                                    Layout.alignment: Qt.AlignRight
                                    text: modelData
                                    font: Kirigami.Theme.smallFont
                                    color: page.muted
                                }
                            }

                            // one row per stat: 4 cells each
                            Repeater {
                                model: overall.rows.length * 4
                                Item {
                                    id: cell
                                    required property int index
                                    readonly property var row: overall.rows[Math.floor(index / 4)]
                                    readonly property int col: index % 4
                                    implicitWidth: cellRow.implicitWidth
                                    implicitHeight: cellRow.implicitHeight
                                    Layout.alignment: col === 0 ? Qt.AlignLeft : Qt.AlignRight
                                    Row {
                                        id: cellRow
                                        spacing: 6
                                        Rectangle {
                                            visible: cell.col === 0
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: cell.row ? cell.row.dot : "transparent"
                                        }
                                        PlasmaComponents.Label {
                                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                                            font.weight: cell.col === 0 ? Font.Normal : Font.Bold
                                            font.features: { "tnum": 1 }
                                            text: !cell.row ? "" : [cell.row.label, cell.row.avg, cell.row.peak, cell.row.use][cell.col]
                                            color: !cell.row || cell.col === 0 || cell.col === 3 ? Kirigami.Theme.textColor
                                                : cell.col === 1 ? cell.row.avgColor : cell.row.peakColor
                                        }
                                    }
                                }
                            }
                        }

                        // Records: first/last played, longest and hottest sessions. Clicking one jumps to its card.
                        GridLayout {
                            id: recordsGrid
                            Layout.alignment: Qt.AlignTop
                            columns: 2
                            columnSpacing: Kirigami.Units.largeSpacing
                            rowSpacing: 1
                            Repeater {
                                model: overall.records.length * 2
                                PlasmaComponents.Label {
                                    id: recCell
                                    required property int index
                                    readonly property var rec: overall.records[Math.floor(index / 2)]
                                    readonly property bool isKey: index % 2 === 0
                                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                                    textFormat: Text.StyledText
                                    color: isKey ? page.muted : Kirigami.Theme.textColor
                                    text: !rec ? "" : isKey ? rec.key : rec.value
                                    // underline on hover when it leads to a session
                                    font.underline: !isKey && rec && rec.start !== undefined && recMouse.containsMouse
                                    // a child, so it sits above the rich text (which takes hover itself)
                                    MouseArea {
                                        id: recMouse
                                        anchors.fill: parent
                                        enabled: !recCell.isKey && recCell.rec && recCell.rec.start !== undefined
                                        hoverEnabled: true
                                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: page.showSession(recCell.rec.start)
                                    }
                                }
                            }
                        }
                    }
                }

                // The game's poster, like a library card
                Kirigami.ShadowedImage {
                    visible: page.capsule !== "" && status !== Image.Error
                    // as tall as the card's text, in the poster's 2:3 shape (but never more than a third of the card)
                    Layout.fillHeight: true
                    Layout.preferredWidth: Math.min(overallCol.implicitHeight * 2 / 3, overall.width / 3)
                    radius: Kirigami.Units.cornerRadius
                    color: Qt.alpha(Kirigami.Theme.textColor, 0.08)
                    source: page.capsule ? "file://" + page.capsule : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    mipmap: true
                }
            }
        }

        Repeater {
            id: cards
            // A count, not the array: sessions is rebuilt on every sample, and an array model would
            // recreate every card each time (new Canvases that never painted, lost hover/"Delete?")
            model: page.sessions.length

            Rectangle {
                id: card
                required property int index
                readonly property var s: page.sessions[index] || ({ start: 0, end: 0, curve: [], cpu: {}, gpu: {} })
                onSChanged: spark.requestPaint()
                readonly property double endTime: s.playing ? Date.now() : s.end

                Layout.fillWidth: true
                Layout.leftMargin: page.sideMargin
                Layout.rightMargin: page.sideMargin
                implicitHeight: col.implicitHeight + Kirigami.Units.largeSpacing * 2
                radius: Kirigami.Units.cornerRadius * 2
                color: Qt.alpha(Kirigami.Theme.textColor, s.playing ? 0.08 : 0.045)
                border.color: s.start === page.flashStart ? Kirigami.Theme.highlightColor
                    : s.playing ? Qt.alpha(root.gpuColor, 0.5) : Qt.alpha(Kirigami.Theme.textColor, 0.1)
                border.width: s.start === page.flashStart ? 2 : 1
                Behavior on border.color { ColorAnimation { duration: Kirigami.Units.longDuration * 2 } }

                // Delete: shown on hover; the first click asks ("Delete?"), a second click within 4s deletes
                property bool confirming: false
                HoverHandler { id: cardHover }   // a handler, so the rich-text labels can't swallow the hover
                Timer { id: confirmTimer; interval: 4000; onTriggered: card.confirming = false }

                ColumnLayout {
                    id: col
                    anchors.fill: parent
                    anchors.margins: Kirigami.Units.largeSpacing
                    spacing: 3

                    // Left: date + length, time span under it. Right: CPU and GPU, one line each.
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Kirigami.Units.largeSpacing

                        ColumnLayout {
                            spacing: 0
                            RowLayout {
                                spacing: Kirigami.Units.smallSpacing
                                PlasmaComponents.Label {
                                    text: page.day(card.s.start)
                                    font.weight: Font.Bold
                                }
                                PlasmaComponents.Label {
                                    text: "· " + root.duration((card.endTime - card.s.start) / 1000)
                                    font.weight: Font.DemiBold
                                    font.features: { "tnum": 1 }
                                    opacity: 0.85
                                }
                                PlasmaComponents.Label {
                                    visible: card.s.playing === true
                                    text: "● Playing"
                                    color: root.gpuColor
                                    font: Kirigami.Theme.smallFont
                                }
                                PlasmaComponents.ToolButton {
                                    id: deleteButton
                                    // Kept in the layout (opacity, not visible) so the header doesn't jump on hover
                                    visible: !card.s.playing
                                    opacity: cardHover.hovered || card.confirming ? 1 : 0
                                    enabled: opacity > 0
                                    Behavior on opacity { NumberAnimation { duration: Kirigami.Units.shortDuration } }
                                    Layout.preferredHeight: Kirigami.Units.iconSizes.small + Kirigami.Units.smallSpacing * 2
                                    icon.name: "edit-delete"
                                    icon.width: Kirigami.Units.iconSizes.small
                                    icon.height: Kirigami.Units.iconSizes.small
                                    icon.color: card.confirming ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
                                    text: card.confirming ? "Delete?" : ""
                                    display: card.confirming ? QQC2.AbstractButton.TextBesideIcon : QQC2.AbstractButton.IconOnly
                                    font: Kirigami.Theme.smallFont
                                    onClicked: {
                                        if (card.confirming) { confirmTimer.stop(); root.deleteSession(page.appid, card.s.start) }
                                        else { card.confirming = true; confirmTimer.restart() }
                                    }
                                    PlasmaComponents.ToolTip { text: card.confirming ? "Click again to delete this session" : "Delete this session" }
                                }
                            }
                            PlasmaComponents.Label {
                                text: page.clock(card.s.start) + " – " + (card.s.playing ? "now" : page.clock(card.s.end))
                                font: Kirigami.Theme.smallFont
                                opacity: 0.6
                            }
                        }

                        Item { Layout.fillWidth: true }

                        ColumnLayout {
                            spacing: 1
                            PlasmaComponents.Label {
                                Layout.alignment: Qt.AlignRight
                                textFormat: Text.StyledText
                                font: Kirigami.Theme.smallFont
                                text: page.tempLine(card.s, "cpu", card.width >= Kirigami.Units.gridUnit * 30)
                            }
                            PlasmaComponents.Label {
                                Layout.alignment: Qt.AlignRight
                                textFormat: Text.StyledText
                                font: Kirigami.Theme.smallFont
                                text: page.tempLine(card.s, "gpu", card.width >= Kirigami.Units.gridUnit * 30)
                            }
                            PlasmaComponents.Label {
                                Layout.alignment: Qt.AlignRight
                                visible: text !== ""
                                textFormat: Text.StyledText
                                font: Kirigami.Theme.smallFont
                                text: page.gpuMaxLine(card.s.gpu)
                            }
                        }
                    }

                    // Mini graph of the session, one point per minute; usage dotted (0–100% = full height)
                    Canvas {
                        id: spark
                        visible: card.s.curve.length > 1
                        Layout.fillWidth: true
                        Layout.preferredHeight: Kirigami.Units.gridUnit * 4.5
                        Layout.topMargin: 3
                        antialiasing: true
                        onWidthChanged: requestPaint()
                        onHeightChanged: requestPaint()
                        onAvailableChanged: requestPaint()

                        readonly property real pad: 6   // room for the peak dots
                        property real hoverX: -1

                        function rgba(c, a) {
                            return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`
                        }
                        // Vertical range shared by the drawing and the hover dots
                        function range() {
                            let lo = Infinity, hi = -Infinity
                            for (const p of card.s.curve) for (const v of [p[0], p[1]]) if (v !== null) { lo = Math.min(lo, v); hi = Math.max(hi, v) }
                            if (lo === Infinity) return null
                            return { lo: Math.floor((lo - 3) / 5) * 5, hi: Math.ceil((hi + 3) / 5) * 5 }
                        }
                        function px(i) { return i / (card.s.curve.length - 1) * width }
                        function py(v, r) { return pad + (r.hi - v) / (r.hi - r.lo) * (height - pad * 2) }
                        // a little headroom so 100% doesn't run along the top edge
                        function pyUse(pct) { return pad + 4 + (100 - pct) / 100 * (height - pad * 2 - 4) }

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const curve = card.s.curve, n = curve.length
                            if (n < 2) return
                            const r = range()
                            if (!r) return
                            const W = width, H = height
                            const x = i => px(i)
                            const y = v => py(v, r)

                            // faint midline for scale
                            ctx.strokeStyle = rgba(Kirigami.Theme.textColor, 0.08)
                            ctx.lineWidth = 1
                            ctx.beginPath(); ctx.moveTo(0, Math.round(H / 2) + 0.5); ctx.lineTo(W, Math.round(H / 2) + 0.5); ctx.stroke()

                            // Usage dots, under the temperature lines (sessions from before usage was recorded have none)
                            for (const [k, key] of [[3, "gpu"], [2, "cpu"]]) {
                                ctx.beginPath()
                                let prev = null, carry = 0
                                const dot = (dx, dy) => { ctx.moveTo(dx + 1.1, dy); ctx.arc(dx, dy, 1.1, 0, 2 * Math.PI) }
                                for (let i = 0; i < n; i++) {
                                    const v = curve[i][k]
                                    if (v === null) { prev = null; continue }
                                    const cur = [x(i), pyUse(v)]
                                    if (!prev) { dot(cur[0], cur[1]); carry = 0 }
                                    else {
                                        const ddx = cur[0] - prev[0], ddy = cur[1] - prev[1], len = Math.hypot(ddx, ddy)
                                        let s = 4.5 - carry
                                        for (; s <= len; s += 4.5) dot(prev[0] + ddx * s / len, prev[1] + ddy * s / len)
                                        carry = len - (s - 4.5)
                                    }
                                    prev = cur
                                }
                                ctx.fillStyle = rgba(root.deviceColor(key), 0.85)
                                ctx.fill()
                            }

                            for (const [k, key] of [[1, "gpu"], [0, "cpu"]]) {
                                const color = root.deviceColor(key)
                                // fill, one piece per unbroken run (a gap stays empty)
                                const g = ctx.createLinearGradient(0, 0, 0, H)
                                g.addColorStop(0, rgba(color, 0.18)); g.addColorStop(1, rgba(color, 0))
                                ctx.fillStyle = g
                                let runStart = -1
                                for (let i = 0; i <= n; i++) {
                                    const v = i < n ? curve[i][k] : null
                                    if (v !== null && runStart < 0) runStart = i
                                    if (v === null && runStart >= 0) {
                                        ctx.beginPath()
                                        ctx.moveTo(x(runStart), H)
                                        for (let j = runStart; j < i; j++) ctx.lineTo(x(j), y(curve[j][k]))
                                        ctx.lineTo(x(i - 1), H)
                                        ctx.closePath()
                                        ctx.fill()
                                        runStart = -1
                                    }
                                }
                                // line
                                ctx.beginPath()
                                let started = false
                                for (let i = 0; i < n; i++) {
                                    const v = curve[i][k]
                                    if (v === null) { started = false; continue }
                                    if (!started) { ctx.moveTo(x(i), y(v)); started = true } else ctx.lineTo(x(i), y(v))
                                }
                                ctx.strokeStyle = color
                                ctx.lineWidth = 2
                                ctx.lineJoin = "round"; ctx.lineCap = "round"
                                ctx.stroke()
                            }
                            // Peak dots (first time each line hit its high), colored like the peak number
                            for (const [k, key] of [[1, "gpu"], [0, "cpu"]]) {
                                let best = -1
                                for (let i = 0; i < n; i++)
                                    if (curve[i][k] !== null && (best < 0 || curve[i][k] > curve[best][k])) best = i
                                if (best < 0) continue
                                ctx.beginPath()
                                ctx.arc(Math.min(Math.max(x(best), 4), W - 4), y(curve[best][k]), 3.5, 0, 2 * Math.PI)
                                ctx.fillStyle = root.levelColor(key, curve[best][k])
                                ctx.fill()
                                ctx.lineWidth = 1.5
                                ctx.strokeStyle = Kirigami.Theme.backgroundColor
                                ctx.stroke()
                            }
                        }

                        // ---- Hover: crosshair, dots, and a readout (each point is that minute's peak) ----
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                            onPositionChanged: mouse => spark.hoverX = mouse.x
                            onExited: spark.hoverX = -1
                        }

                        readonly property var hoverInfo: {
                            root.revision
                            const n = card.s.curve.length
                            if (hoverX < 0 || n < 2) return null
                            const i = Math.max(0, Math.min(n - 1, Math.round(hoverX / width * (n - 1))))
                            const r = range()
                            if (!r) return null
                            const p = card.s.curve[i]
                            return { i: i, t: card.s.start + i * 60000, cpu: p[0], gpu: p[1], cpuUse: p[2], gpuUse: p[3],
                                     gpuHot: p[6], gpuPower: p[7] === null ? null : Math.round(p[7]), r: r }
                        }
                        function minutesIn(m) {
                            return m < 60 ? m + "m in" : Math.floor(m / 60) + "h " + String(m % 60).padStart(2, "0") + "m in"
                        }

                        Rectangle {
                            visible: spark.hoverInfo !== null
                            x: spark.hoverInfo ? Math.round(spark.px(spark.hoverInfo.i)) : 0
                            width: 1
                            height: spark.height
                            color: Kirigami.Theme.textColor
                            opacity: 0.35
                        }

                        Repeater {
                            model: ["cpu", "gpu"]
                            Rectangle {
                                required property string modelData
                                readonly property var v: spark.hoverInfo ? spark.hoverInfo[modelData + "Use"] : null
                                visible: v !== null && v !== undefined
                                width: 7; height: 7; radius: 3.5
                                x: visible ? spark.px(spark.hoverInfo.i) - 3.5 : 0
                                y: visible ? spark.pyUse(v) - 3.5 : 0
                                color: Kirigami.Theme.backgroundColor
                                border.color: root.deviceColor(modelData)
                                border.width: 2
                            }
                        }

                        Repeater {
                            model: ["cpu", "gpu"]
                            Rectangle {
                                required property string modelData
                                readonly property var v: spark.hoverInfo ? spark.hoverInfo[modelData] : null
                                visible: v !== null && v !== undefined
                                width: 9; height: 9; radius: 4.5
                                x: visible ? spark.px(spark.hoverInfo.i) - 4.5 : 0
                                y: visible ? spark.py(v, spark.hoverInfo.r) - 4.5 : 0
                                color: root.deviceColor(modelData)
                                border.color: Kirigami.Theme.backgroundColor
                                border.width: 2
                            }
                        }

                        // Readout, stacked like the main graph's: time, then one row per device (GPU adds power and hotspot).
                        // Plain Text only: rich-text labels take hover themselves and made the readout flicker.
                        Rectangle {
                            id: sparkBubble
                            visible: spark.hoverInfo !== null
                            readonly property real hx: spark.hoverInfo ? spark.px(spark.hoverInfo.i) : 0
                            readonly property color muted: Qt.alpha(Kirigami.Theme.textColor, 0.7)
                            readonly property real fontPx: Kirigami.Theme.smallFont.pixelSize > 0 ? Kirigami.Theme.smallFont.pixelSize
                                : Math.round(Kirigami.Theme.smallFont.pointSize * 4 / 3)
                            x: hx + width + 14 > spark.width ? Math.max(0, hx - width - 10) : hx + 10
                            y: 2
                            width: bubbleCol.implicitWidth + Kirigami.Units.largeSpacing * 1.5
                            height: bubbleCol.implicitHeight + Kirigami.Units.smallSpacing * 2.5
                            radius: Kirigami.Units.cornerRadius
                            color: Qt.alpha(Kirigami.Theme.backgroundColor, 0.94)
                            border.color: Qt.alpha(Kirigami.Theme.textColor, 0.15)

                            Column {
                                id: bubbleCol
                                anchors.centerIn: parent
                                spacing: 2
                                Text {
                                    text: spark.hoverInfo ? page.clock(spark.hoverInfo.t) + " · " + spark.minutesIn(spark.hoverInfo.i) : ""
                                    color: sparkBubble.muted
                                    font.pixelSize: sparkBubble.fontPx
                                }
                                Repeater {
                                    model: ["cpu", "gpu"]
                                    Row {
                                        id: devRow
                                        required property string modelData
                                        readonly property var info: spark.hoverInfo
                                        readonly property var v: info ? info[modelData] : null
                                        readonly property var u: info ? info[modelData + "Use"] : null
                                        readonly property var w: modelData === "gpu" && info ? info.gpuPower : null
                                        readonly property var h: modelData === "gpu" && info ? info.gpuHot : null
                                        function has(x) { return x !== null && x !== undefined }
                                        spacing: 5
                                        Rectangle {
                                            width: 8; height: 8; radius: 4
                                            anchors.verticalCenter: parent.verticalCenter
                                            color: root.deviceColor(devRow.modelData)
                                        }
                                        Text {
                                            text: root.device(devRow.modelData).label
                                            color: Kirigami.Theme.textColor
                                            font.pixelSize: sparkBubble.fontPx + 1
                                            width: sparkBubble.fontPx * 2.6
                                        }
                                        Text {
                                            text: devRow.has(devRow.v) ? devRow.v + "°C" : "--"
                                            color: devRow.has(devRow.v) ? root.levelColor(devRow.modelData, devRow.v) : Kirigami.Theme.textColor
                                            font.pixelSize: sparkBubble.fontPx + 1
                                            font.weight: Font.Bold
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            visible: devRow.has(devRow.u)
                                            text: visible ? "· " + root.usage(devRow.u) + "%" : ""
                                            color: sparkBubble.muted
                                            font.pixelSize: sparkBubble.fontPx + 1
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            visible: devRow.has(devRow.w)
                                            text: visible ? "· " + devRow.w + " W" : ""
                                            color: sparkBubble.muted
                                            font.pixelSize: sparkBubble.fontPx + 1
                                            font.features: { "tnum": 1 }
                                        }
                                        Text {
                                            visible: devRow.has(devRow.h)
                                            text: "· hotspot"
                                            color: sparkBubble.muted
                                            font.pixelSize: sparkBubble.fontPx + 1
                                        }
                                        Text {
                                            visible: devRow.has(devRow.h)
                                            text: visible ? devRow.h + "°" : ""
                                            color: visible ? root.hotspotColor(devRow.h) : Kirigami.Theme.textColor
                                            font.pixelSize: sparkBubble.fontPx + 1
                                            font.features: { "tnum": 1 }
                                        }
                                    }
                                }
                            }
                        }

                        // Test hooks (any test window; deletes go to the test folder): `temps-delete-ask` puts the first finished session into "Delete?",
                        // `temps-delete` deletes it (both clicks)
                        Timer {
                            interval: 1300
                            running: root.testMode && !page.testDeleteFired
                                && card.index === (page.sessions[0] && page.sessions[0].playing ? 1 : 0)
                                && Qt.application.arguments.some(a => a === "temps-delete-ask" || a === "temps-delete")
                            onTriggered: {
                                page.testDeleteFired = true
                                deleteButton.clicked()
                                if (Qt.application.arguments.indexOf("temps-delete") >= 0) deleteButton.clicked()
                            }
                        }

                        // Test hook: `temps-spark-hover=0.55` parks a fake cursor 55% across the newest session's graph
                        Timer {
                            interval: 1500
                            running: root.demo && card.index === 0
                            onTriggered: {
                                const h = Qt.application.arguments.find(a => String(a).startsWith("temps-spark-hover="))
                                if (h) spark.hoverX = Number(h.slice(18)) * spark.width
                            }
                        }
                    }
                }
            }
        }

        PlasmaComponents.Label {
            readonly property int missing: page.game ? page.game.sessions - page.sessions.length : 0
            visible: missing > 0
            Layout.fillWidth: true
            Layout.leftMargin: page.sideMargin
            Layout.rightMargin: page.sideMargin
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            font: Kirigami.Theme.smallFont
            opacity: 0.55
            text: `${missing} earlier session${missing === 1 ? "" : "s"} recorded before session history was added (included in the totals).`
        }

        Item { implicitHeight: Kirigami.Units.smallSpacing }
    }
}
