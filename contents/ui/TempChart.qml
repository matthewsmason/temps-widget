import QtQuick
import org.kde.kirigami as Kirigami

// One chart, two smooth lines (CPU + GPU), temperature over time, plus each device's utilization as a
// dotted line in the same color (0% at the bottom, 100% just under the top label row).
// Beneath the plot, a thin "heat strip" per device marks when it was in its orange/red zone.
Item {
    id: chart

    property double rangeMs: 0          // 0 = everything kept (the last 24 hours)
    property var plot: null             // last computed layout, shared with the hover overlay
    property real hoverX: -1

    readonly property real padL: Kirigami.Units.gridUnit * 2.2
    readonly property real padR: Kirigami.Units.gridUnit * 0.8
    readonly property real padT: Kirigami.Units.gridUnit * 1.1
    readonly property real stripH: Math.round(Kirigami.Units.gridUnit * 0.35)
    readonly property real stripRow: fontPx + 6
    readonly property real padB: fontPx + 14 + stripRow * 2
    readonly property real fontPx: Math.round(Kirigami.Units.gridUnit * 0.62)
    readonly property real plotW: width - padL - padR
    readonly property real plotH: height - padT - padB

    function rgba(c, a) {
        return `rgba(${Math.round(c.r * 255)},${Math.round(c.g * 255)},${Math.round(c.b * 255)},${a})`
    }
    function clock(t) { return new Date(t).toLocaleTimeString(Qt.locale(), Locale.ShortFormat) }
    // Same 12h/24h convention as the user's locale, with seconds
    function clockSecs(t) {
        const twelve = /a/i.test(Qt.locale().timeFormat(Locale.ShortFormat))
        return Qt.formatTime(new Date(t), twelve ? "h:mm:ss AP" : "HH:mm:ss")
    }

    // Lower-bound binary search over the sorted sample times
    function firstIndexAtOrAfter(t) {
        const ts = root.times
        let lo = 0, hi = ts.length
        while (lo < hi) { const mid = (lo + hi) >> 1; if (ts[mid] < t) lo = mid + 1; else hi = mid }
        return lo
    }

    function compute() {
        const ts = root.times, n = ts.length
        if (n < 2 || plotW <= 0) return null
        const t1 = ts[n - 1]
        const t0 = rangeMs > 0 ? Math.max(ts[0], t1 - rangeMs) : ts[0]
        const a = firstIndexAtOrAfter(t0)
        const gapMs = 3 * root.sampleMs
        const maxPts = Math.max(20, Math.floor(plotW / 2.5))
        const step = Math.max(1, Math.ceil((n - a) / maxPts))
        const out = { t0: t0, t1: Math.max(t1, t0 + 60000), series: {}, use: {}, zones: {}, bucketMs: (step + 1) * root.sampleMs }
        let lo = Infinity, hi = -Infinity

        for (const key of ["cpu", "gpu"]) {
            const vals = key === "cpu" ? root.cpuTemps : root.gpuTemps
            const uses = key === "cpu" ? root.cpuUses : root.gpuUses
            const d = root.device(key)
            const pts = [], usePts = [], zones = []
            let runStart = a
            // Downsample within gap-free runs; each point keeps its bucket's peak so spikes survive
            for (let k = a + 1; k <= n; k++) {
                if (k < n && ts[k] - ts[k - 1] <= gapMs) continue
                if (pts.length) pts.push(null)
                if (usePts.length) usePts.push(null)
                for (let i = runStart; i < k; i += step) {
                    let best = -1, useSum = 0, useN = 0
                    for (let j = i; j < Math.min(k, i + step); j++) {
                        if (vals[j] !== null && (best < 0 || vals[j] > vals[best])) best = j
                        if (uses[j] !== null && uses[j] !== undefined) { useSum += uses[j]; useN++ }
                    }
                    if (best >= 0) {
                        pts.push([ts[best], vals[best]])
                        lo = Math.min(lo, vals[best]); hi = Math.max(hi, vals[best])
                    }
                    // Usage jumps around a lot, so it's averaged over the bucket instead of peaked
                    if (useN) usePts.push([ts[Math.min(k - 1, i + (step >> 1))], useSum / useN])
                }
                runStart = k
            }
            // Zone segments from raw samples (exact, not downsampled)
            let cur = null
            for (let i = a; i < n; i++) {
                const v = vals[i]
                const level = v === null ? 0 : v >= d.hot ? 2 : v >= d.warn ? 1 : 0
                const contiguous = i > a && ts[i] - ts[i - 1] <= gapMs
                if (cur && cur.level === level && contiguous) { cur.end = ts[i] + root.sampleMs; continue }
                if (cur && cur.level > 0) zones.push(cur)
                cur = { start: ts[i], end: ts[i] + root.sampleMs, level: level }
            }
            if (cur && cur.level > 0) zones.push(cur)
            out.series[key] = pts
            out.use[key] = usePts
            out.zones[key] = zones
        }
        if (lo === Infinity) return null

        // Y axis: round to tens with breathing room; pull in a device's red line if the data gets near it
        let yMin = Math.floor((lo - 4) / 10) * 10, yMax = Math.ceil((hi + 6) / 10) * 10
        for (const key of ["cpu", "gpu"]) {
            const pts = out.series[key].filter(p => p), d = root.device(key)
            const peak = pts.reduce((m, p) => Math.max(m, p[1]), -Infinity)
            if (peak >= d.hot - 10) yMax = Math.max(yMax, Math.ceil((d.hot + 5) / 10) * 10)
        }
        if (yMax - yMin < 30) yMin = yMax - 30
        out.yMin = yMin; out.yMax = yMax
        return out
    }

    function tx(t) { return padL + (t - plot.t0) / (plot.t1 - plot.t0) * plotW }
    function ty(v) { return padT + (plot.yMax - v) / (plot.yMax - plot.yMin) * plotH }
    // 100% sits one label row below the top, clear of the plot edge and the game-name labels
    readonly property real useTop: fontPx + 8
    function tyUse(pct) { return padT + useTop + (100 - pct) / 100 * (plotH - useTop) }

    function niceTimeStep(spanMs) {
        const min = 60000
        const steps = [1, 2, 5, 10, 15, 30, 60, 120, 180, 360, 720].map(m => m * min)
        const target = spanMs / Math.max(2, Math.floor(plotW / (Kirigami.Units.gridUnit * 5)))
        return steps.find(s => s >= target) || steps[steps.length - 1]
    }

    // Monotone cubic (Fritsch–Carlson): smooth like the weather widget, but never overshoots a real peak
    function tracePath(ctx, run) {
        const n = run.length
        ctx.moveTo(run[0][0], run[0][1])
        if (n === 1) { ctx.lineTo(run[0][0] + 0.1, run[0][1]); return }
        const dl = [], m = new Array(n).fill(0)
        for (let i = 0; i < n - 1; i++) dl.push((run[i + 1][1] - run[i][1]) / ((run[i + 1][0] - run[i][0]) || 1))
        for (let i = 1; i < n - 1; i++) m[i] = dl[i - 1] * dl[i] <= 0 ? 0 : 2 / (1 / dl[i - 1] + 1 / dl[i])
        m[0] = dl[0]; m[n - 1] = dl[n - 2]
        for (let i = 0; i < n - 1; i++) {
            const h = (run[i + 1][0] - run[i][0]) / 3
            ctx.bezierCurveTo(run[i][0] + h, run[i][1] + m[i] * h,
                              run[i + 1][0] - h, run[i + 1][1] - m[i + 1] * h,
                              run[i + 1][0], run[i + 1][1])
        }
    }

    function runsOf(pts, yOf) {
        const runs = [[]], y = yOf || ty
        for (const p of pts) p ? runs[runs.length - 1].push([tx(p[0]), y(p[1])]) : runs.push([])
        return runs.filter(r => r.length)
    }

    // Round dots every `gap` px along a polyline (drawn by hand; Qt's canvas setLineDash is unreliable)
    function dotsAlong(ctx, run, gap, r) {
        let carry = 0
        const dot = (x, y) => { ctx.moveTo(x + r, y); ctx.arc(x, y, r, 0, 2 * Math.PI) }
        dot(run[0][0], run[0][1])
        for (let i = 1; i < run.length; i++) {
            const x0 = run[i - 1][0], y0 = run[i - 1][1], dx = run[i][0] - x0, dy = run[i][1] - y0
            const len = Math.hypot(dx, dy)
            let s = gap - carry
            for (; s <= len; s += gap) dot(x0 + dx * s / len, y0 + dy * s / len)
            carry = len - (s - gap)
        }
    }

    function nearest(pts, t) {
        let best = null
        for (const p of pts) if (p && (!best || Math.abs(p[0] - t) < Math.abs(best[0] - t))) best = p
        return best
    }

    Connections {
        target: root
        function onRevisionChanged() { if (root.expanded || root.demo) canvas.requestPaint() }
        function onExpandedChanged() { if (root.expanded) canvas.requestPaint() }
        function onDarkThemeChanged() { canvas.requestPaint() }
    }
    onRangeMsChanged: canvas.requestPaint()

    // Test hook: `temps-hover=0.6` parks a fake cursor 60% across the plot
    Timer {
        interval: 1500
        running: root.demo || root.testMode   // any test window, live data too
        onTriggered: {
            const h = Qt.application.arguments.find(a => a.startsWith("temps-hover="))
            if (h) chart.hoverX = chart.padL + Number(h.slice(12)) * chart.plotW
        }
    }
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            chart.plot = chart.compute()
            const d = chart.plot
            const fg = Kirigami.Theme.textColor
            ctx.font = `${chart.fontPx}px sans-serif`

            if (!d) {
                ctx.fillStyle = chart.rgba(fg, 0.6)
                ctx.textAlign = "center"
                ctx.fillText("Collecting readings…", width / 2, height / 2)
                return
            }
            const L = chart.padL, R = width - chart.padR, T = chart.padT, B = chart.padT + chart.plotH

            // Game sessions: a soft band behind everything, labeled with the game's name
            ctx.textAlign = "left"
            ctx.textBaseline = "top"
            for (const g of root.gameSpans()) {
                const xa = Math.max(L, chart.tx(g.start)), xb = Math.min(R, chart.tx(g.end))
                if (xb <= xa) continue
                ctx.fillStyle = chart.rgba(fg, root.darkTheme ? 0.055 : 0.045)
                ctx.fillRect(xa, T, xb - xa, B - T)
                if (xb - xa > 60) {
                    ctx.fillStyle = chart.rgba(fg, 0.5)
                    ctx.fillText(g.name, xa + 5, T + 4, xb - xa - 10)
                }
            }

            // Horizontal grid + temperature labels
            const yStep = d.yMax - d.yMin > 90 ? 20 : 10
            ctx.lineWidth = 1
            ctx.textAlign = "right"
            ctx.textBaseline = "middle"
            for (let v = d.yMin; v <= d.yMax; v += yStep) {
                const yy = Math.round(chart.ty(v)) + 0.5
                ctx.strokeStyle = chart.rgba(fg, 0.09)
                ctx.beginPath(); ctx.moveTo(L, yy); ctx.lineTo(R, yy); ctx.stroke()
                ctx.fillStyle = chart.rgba(fg, 0.55)
                ctx.fillText(v + "°", L - 6, yy)
            }

            // Time ticks, aligned to round clock times
            const stepMs = chart.niceTimeStep(d.t1 - d.t0)
            const offset = new Date(d.t0).getTimezoneOffset() * 60000
            ctx.textAlign = "center"
            ctx.textBaseline = "top"
            for (let t = Math.ceil((d.t0 - offset) / stepMs) * stepMs + offset; t <= d.t1; t += stepMs) {
                const xx = Math.round(chart.tx(t)) + 0.5
                ctx.strokeStyle = chart.rgba(fg, 0.06)
                ctx.beginPath(); ctx.moveTo(xx, T); ctx.lineTo(xx, B); ctx.stroke()
                ctx.fillStyle = chart.rgba(fg, 0.55)
                ctx.fillText(chart.clock(t), Math.min(Math.max(xx, L + 20), R - 20), B + 6)
            }


            // Soft gradient fills first, then both lines on top so neither color muddies the other
            ctx.save()
            ctx.beginPath(); ctx.rect(L, T - 8, R - L, B - T + 8); ctx.clip()
            for (const key of ["gpu", "cpu"]) {
                const color = root.deviceColor(key)
                for (const run of chart.runsOf(d.series[key])) {
                    const g = ctx.createLinearGradient(0, T, 0, B)
                    g.addColorStop(0, chart.rgba(color, root.darkTheme ? 0.20 : 0.16))
                    g.addColorStop(1, chart.rgba(color, 0))
                    ctx.beginPath()
                    chart.tracePath(ctx, run)
                    ctx.lineTo(run[run.length - 1][0], B); ctx.lineTo(run[0][0], B); ctx.closePath()
                    ctx.fillStyle = g
                    ctx.fill()
                }
            }
            // Each device's red line, only when it's on screen
            ctx.textAlign = "right"
            ctx.textBaseline = "bottom"
            let lastLabelY = -Infinity
            for (const key of ["cpu", "gpu"].sort((a, b) => root.device(b).hot - root.device(a).hot)) {
                const dev = root.device(key)
                if (dev.hot > d.yMax || dev.hot < d.yMin) continue
                const yy = Math.round(chart.ty(dev.hot)) + 0.5
                ctx.strokeStyle = chart.rgba(root.hotColor, 0.8)
                // Dashes drawn by hand: Qt's canvas setLineDash only applies to the first stroke here
                ctx.beginPath()
                for (let xx = L; xx < R; xx += 9) { ctx.moveTo(xx, yy); ctx.lineTo(Math.min(xx + 6, R), yy) }
                ctx.stroke()
                const below = yy - lastLabelY < chart.fontPx + 4
                ctx.textBaseline = below ? "top" : "bottom"
                ctx.fillStyle = chart.rgba(root.hotColor, 0.85)
                ctx.fillText(`${dev.label} limit ${dev.hot}°`, R - 2, below ? yy + 3 : yy - 3)
                lastLabelY = yy
            }
            // Utilization: dotted, under the temperature lines
            for (const key of ["gpu", "cpu"]) {
                ctx.beginPath()
                for (const run of chart.runsOf(d.use[key], chart.tyUse)) chart.dotsAlong(ctx, run, 5, 1.2)
                ctx.fillStyle = chart.rgba(root.deviceColor(key), 0.85)
                ctx.fill()
            }
            for (const key of ["gpu", "cpu"]) {
                for (const run of chart.runsOf(d.series[key])) {
                    ctx.beginPath()
                    chart.tracePath(ctx, run)
                    ctx.strokeStyle = root.deviceColor(key)
                    ctx.lineWidth = 2.5
                    ctx.lineJoin = "round"; ctx.lineCap = "round"
                    ctx.stroke()
                }
            }
            ctx.restore()

            // Peak markers (value and time are already in the cards above)
            for (const key of ["cpu", "gpu"]) {
                const pts = d.series[key].filter(p => p)
                if (!pts.length) continue
                const pk = pts.reduce((m, p) => p[1] > m[1] ? p : m)
                const px = chart.tx(pk[0]), py = chart.ty(pk[1]), c = root.levelColor(key, pk[1])
                ctx.beginPath(); ctx.arc(px, py, 4.5, 0, 2 * Math.PI)
                ctx.fillStyle = c; ctx.fill()
                ctx.lineWidth = 2; ctx.strokeStyle = Kirigami.Theme.backgroundColor; ctx.stroke()
            }

            // Heat strips: when each device was orange / red
            ctx.font = `${chart.fontPx}px sans-serif`
            ctx.textAlign = "right"
            ctx.textBaseline = "middle"
            const stripTop = B + chart.fontPx + 12
            ;["cpu", "gpu"].forEach((key, i) => {
                const sy = stripTop + i * chart.stripRow + (chart.stripRow - chart.stripH) / 2
                ctx.fillStyle = chart.rgba(fg, 0.08)
                ctx.fillRect(L, sy, R - L, chart.stripH)
                for (const z of d.zones[key]) {
                    const xa = Math.max(L, chart.tx(z.start)), xb = Math.min(R, chart.tx(z.end))
                    ctx.fillStyle = z.level === 2 ? root.hotColor : root.warnColor
                    ctx.fillRect(xa, sy, Math.max(1.5, xb - xa), chart.stripH)
                }
                ctx.fillStyle = root.deviceColor(key)
                ctx.fillText(root.device(key).label, L - 6, sy + chart.stripH / 2)
            })
        }
    }

    // ---- Hover: crosshair, dots, and a readout bubble ----
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onPositionChanged: mouse => chart.hoverX = mouse.x
        onExited: chart.hoverX = -1
    }

    readonly property var hoverInfo: {
        root.revision
        if (hoverX < padL || hoverX > width - padR || !plot) return null
        const t = plot.t0 + (hoverX - padL) / plotW * (plot.t1 - plot.t0)
        const c = nearest(plot.series.cpu, t), g = nearest(plot.series.gpu, t)
        const ref = c || g
        if (!ref) return null
        const cu = nearest(plot.use.cpu, ref[0]), gu = nearest(plot.use.gpu, ref[0])
        // Only a usage point from the same moment (a gap in usage readings shows as no value)
        const near = p => p && Math.abs(p[0] - ref[0]) <= plot.bucketMs ? p[1] : null
        // GPU hotspot and power: the raw sample behind the GPU point (binary search; points keep exact sample times)
        let gpuHot = null, gpuPower = null
        if (g) {
            const ts = root.times
            let lo = 0, hi = ts.length - 1
            while (lo < hi) { const mid = (lo + hi) >> 1; if (ts[mid] < g[0]) lo = mid + 1; else hi = mid }
            if (ts[lo] === g[0]) { gpuHot = root.gpuHots[lo] ?? null; gpuPower = root.gpuPowers[lo] ?? null }
        }
        return { t: ref[0], cpu: c ? c[1] : null, gpu: g ? g[1] : null,
                 cpuUse: near(cu), gpuUse: near(gu), gpuHot: gpuHot, gpuPower: gpuPower }
    }

    Rectangle {
        visible: chart.hoverInfo !== null
        x: chart.hoverInfo ? Math.round(chart.tx(chart.hoverInfo.t)) : 0
        y: chart.padT
        width: 1
        height: chart.plotH
        color: Kirigami.Theme.textColor
        opacity: 0.35
    }

    Repeater {
        model: ["cpu", "gpu"]
        Rectangle {
            required property string modelData
            readonly property var v: chart.hoverInfo ? chart.hoverInfo[modelData] : null
            visible: v !== null && v !== undefined
            width: 9; height: 9; radius: 4.5
            x: visible ? chart.tx(chart.hoverInfo.t) - 4.5 : 0
            y: visible ? chart.ty(v) - 4.5 : 0
            color: root.deviceColor(modelData)
            border.color: Kirigami.Theme.backgroundColor
            border.width: 2
        }
    }

    Repeater {
        model: ["cpu", "gpu"]
        Rectangle {
            required property string modelData
            readonly property var v: chart.hoverInfo ? chart.hoverInfo[modelData + "Use"] : null
            visible: v !== null && v !== undefined
            width: 7; height: 7; radius: 3.5
            x: visible ? chart.tx(chart.hoverInfo.t) - 3.5 : 0
            y: visible ? chart.tyUse(v) - 3.5 : 0
            color: Kirigami.Theme.backgroundColor
            border.color: root.deviceColor(modelData)
            border.width: 2
        }
    }

    Rectangle {
        id: bubble
        visible: chart.hoverInfo !== null
        readonly property real hx: chart.hoverInfo ? chart.tx(chart.hoverInfo.t) : 0
        x: hx + width + 14 > chart.width - chart.padR ? hx - width - 10 : hx + 10
        y: chart.padT + 4
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
                text: chart.hoverInfo ? chart.clockSecs(chart.hoverInfo.t) : ""
                color: Qt.alpha(Kirigami.Theme.textColor, 0.7)
                font.pixelSize: chart.fontPx
            }
            Repeater {
                model: ["cpu", "gpu"]
                Row {
                    required property string modelData
                    readonly property var v: chart.hoverInfo ? chart.hoverInfo[modelData] : null
                    spacing: 6
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.deviceColor(modelData)
                    }
                    Text {
                        text: root.device(modelData).label
                        color: Kirigami.Theme.textColor
                        font.pixelSize: chart.fontPx + 1
                        width: chart.fontPx * 2.6
                    }
                    Text {
                        text: v === null || v === undefined ? "--" : v + "°C"
                        color: v === null || v === undefined ? Kirigami.Theme.textColor : root.levelColor(modelData, v)
                        font.pixelSize: chart.fontPx + 1
                        font.weight: Font.Bold
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        readonly property var u: chart.hoverInfo ? chart.hoverInfo[modelData + "Use"] : null
                        visible: u !== null && u !== undefined
                        text: visible ? "· " + root.usage(u) + "%" : ""
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.7)
                        font.pixelSize: chart.fontPx + 1
                        font.features: { "tnum": 1 }
                    }
                    // GPU only: power, then hotspot
                    Text {
                        readonly property var w: modelData === "gpu" && chart.hoverInfo ? chart.hoverInfo.gpuPower : null
                        visible: w !== null && w !== undefined
                        text: visible ? "· " + w + " W" : ""
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.7)
                        font.pixelSize: chart.fontPx + 1
                        font.features: { "tnum": 1 }
                    }
                    Text {
                        readonly property var h: modelData === "gpu" && chart.hoverInfo ? chart.hoverInfo.gpuHot : null
                        visible: h !== null && h !== undefined
                        textFormat: Text.StyledText
                        text: visible ? `<font color="${Qt.alpha(Kirigami.Theme.textColor, 0.7)}">· hotspot</font> <font color="${root.hotspotColor(h)}">${h}°</font>` : ""
                        color: Kirigami.Theme.textColor
                        font.pixelSize: chart.fontPx + 1
                        font.features: { "tnum": 1 }
                    }
                }
            }
        }
    }
}
