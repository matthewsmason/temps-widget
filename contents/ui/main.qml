import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.ksysguard.sensors as Sensors
import org.kde.plasma.plasma5support as P5Support
import QtCore

PlasmoidItem {
    id: root

    // ---- Settings (Configure Temps…; changes apply live) ----
    readonly property var cfg: Plasmoid.configuration
    readonly property int sampleMs: Math.max(1, Math.min(10, cfg.updateSeconds || 2)) * 1000
    readonly property int maxSamples: 24 * 3600 * 1000 / sampleMs   // keep the last 24 hours
    readonly property var devices: [
        { key: "cpu", label: "CPU", warn: cfg.cpuWarn, hot: cfg.cpuHot },
        { key: "gpu", label: "GPU", warn: cfg.gpuWarn, hot: cfg.gpuHot },
    ]

    // ---- Colors: custom from settings, otherwise tuned for dark or light Plasma themes ----
    readonly property bool darkTheme: Kirigami.ColorUtils.brightnessForColor(Kirigami.Theme.backgroundColor) === Kirigami.ColorUtils.Dark
    readonly property color cpuColor: cfg.cpuColor ? cfg.cpuColor : (darkTheme ? "#6cb8ff" : "#1f74d1")
    readonly property color gpuColor: cfg.gpuColor ? cfg.gpuColor : (darkTheme ? "#7ee08f" : "#1e9a3c")
    readonly property color warnColor: darkTheme ? "#ffb347" : "#c77700"
    readonly property color hotColor: darkTheme ? "#ff5f5f" : "#d22f2f"

    function deviceColor(key) { return key === "cpu" ? cpuColor : gpuColor }
    function device(key) { return devices[key === "cpu" ? 0 : 1] }
    function levelColor(key, value) {
        const d = device(key)
        if (value >= d.hot) return hotColor
        if (value >= d.warn) return warnColor
        return deviceColor(key)
    }
    function duration(secs) {
        secs = Math.floor(secs)
        if (secs < 60) return secs + "s"
        if (secs < 3600) return Math.floor(secs / 60) + "m " + String(secs % 60).padStart(2, "0") + "s"
        return Math.floor(secs / 3600) + "h " + String(Math.floor(secs % 3600 / 60)).padStart(2, "0") + "m"
    }

    // ---- Live values ----
    Sensors.Sensor { id: cpuSensor; sensorId: "cpu/all/maximumTemperature"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: gpuSensor; sensorId: "gpu/gpu0/temperature"; updateRateLimit: root.sampleMs }
    // Usage (%): live in the cards, and recorded with the temps for the graphs' dotted lines
    Sensors.Sensor { id: cpuUseSensor; sensorId: "cpu/all/usage"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: gpuUseSensor; sensorId: "gpu/gpu0/usage"; updateRateLimit: root.sampleMs }
    // GPU hotspot (amdgpu "junction", the hottest point on the die; the edge temp above runs well below it)
    // and board power in watts ("power1" = PPT; plain "power" never reads on this card): recorded, shown live on the GPU card and in hover readouts
    Sensors.Sensor { id: gpuHotSensor; sensorId: "gpu/gpu0/temp2"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: gpuPowerSensor; sensorId: "gpu/gpu0/power1"; updateRateLimit: root.sampleMs }

    // ---- Model names ----
    // GPU name comes from ksystemstats, e.g. "Navi 48 [...] (Navi 48 XTX [Sapphire Pulse Radeon RX 9070 XT])":
    // the bracketed board name inside the last parentheses is the friendly one.
    Sensors.Sensor { id: gpuNameSensor; sensorId: "gpu/gpu0/name" }
    readonly property string gpuModel: {
        const s = String(gpuNameSensor.value ?? "")
        const paren = s.match(/\(([^()]*)\)\s*$/)
        const inner = paren ? paren[1] : s
        const bracket = inner.match(/\[([^\]]+)\]/)
        return (bracket ? bracket[1] : inner).replace(/\bRadeon\s+/, "").trim()   // "Sapphire Pulse RX 9070 XT"
    }
    // ksystemstats only names CPU cores ("Core 1"), so read the model once from /proc/cpuinfo
    property string cpuModelRaw: ""
    readonly property string cpuModel: cpuModelRaw
        .replace(/\((R|TM)\)/g, "").replace(/\s+\d+-Core Processor$/, "").replace(/\s+Processor$/, "").trim()
    P5Support.DataSource {
        engine: "executable"
        readonly property string cmd: "awk -F': ' '/^model name/{print $2; exit}' /proc/cpuinfo"
        Component.onCompleted: connectSource(cmd)
        onNewData: (source, data) => {
            root.cpuModelRaw = (data.stdout || "").trim()
            disconnectSource(source)   // one-shot
        }
    }

    function valid(v) { return typeof v === "number" && v > 0 }
    readonly property var cpuNow: valid(cpuSensor.value) ? Math.round(cpuSensor.value) : null
    readonly property var gpuNow: valid(gpuSensor.value) ? Math.round(gpuSensor.value) : null
    // Whole percent as text; a near-idle 0.4% reads "<1" rather than a "0" that looks broken
    function usage(v) {
        if (typeof v !== "number" || v < 0) return null
        return v > 0 && v < 0.5 ? "<1" : String(Math.round(Math.min(100, v)))
    }
    readonly property var cpuUse: demo ? "31" : usage(cpuUseSensor.value)
    readonly property var gpuUse: demo ? "87" : usage(gpuUseSensor.value)

    // ---- Pump and fan speeds (rpm), live only ----
    // From the motherboard's NCT6799 fan chip (needs the nct6775 driver; without it these read nothing and the
    // row hides). Headers found by testing on 2026-10-13: fan7 = AIO pump, fan1 + fan2 = radiator fans,
    // fan6 = chipset fan (on the motherboard). GPU fan from amdgpu (0 rpm = its idle fan-stop).
    readonly property string fanChip: "lmsensors/nct6799-isa-0290/"
    Sensors.Sensor { id: pumpSensor; sensorId: root.fanChip + "fan7"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: radFan1Sensor; sensorId: root.fanChip + "fan1"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: radFan2Sensor; sensorId: root.fanChip + "fan2"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: chipsetFanSensor; sensorId: root.fanChip + "fan6"; updateRateLimit: root.sampleMs }
    Sensors.Sensor { id: gpuFanSensor; sensorId: "gpu/gpu0/fan1"; updateRateLimit: root.sampleMs }
    function rpm(sensor) { return typeof sensor.value === "number" && sensor.value >= 0 ? Math.round(sensor.value) : null }
    readonly property var pumpRpm: demo ? 2750 : rpm(pumpSensor)
    readonly property var radiatorRpm: {
        if (demo) return 760
        const a = rpm(radFan1Sensor), b = rpm(radFan2Sensor)
        return a === null ? b : b === null ? a : Math.round((a + b) / 2)
    }
    readonly property var chipsetFanRpm: demo ? 2080 : rpm(chipsetFanSensor)
    readonly property var gpuFanRpm: demo ? 0 : rpm(gpuFanSensor)
    // Recorded as whole percent (null = no reading)
    function usageNum(v) { return typeof v === "number" && v >= 0 ? Math.round(Math.min(100, v)) : null }
    readonly property var cpuUseNow: usageNum(cpuUseSensor.value)
    readonly property var gpuUseNow: usageNum(gpuUseSensor.value)
    readonly property var gpuHotNow: demo ? 74 : valid(gpuHotSensor.value) ? Math.round(gpuHotSensor.value) : null
    readonly property var gpuPowerNow: demo ? 212 : typeof gpuPowerSensor.value === "number" && gpuPowerSensor.value >= 0
        ? Math.round(gpuPowerSensor.value) : null
    // Hotspot runs ~15-25° above edge; amdgpu throttles near 110° (its limit is 115°)
    readonly property int hotspotWarn: 95
    readonly property int hotspotHot: 105
    function hotspotColor(v) { return v >= hotspotHot ? hotColor : v >= hotspotWarn ? warnColor : deviceColor("gpu") }

    // ---- Temperature history (plain JS arrays; `revision` tells views to redraw) ----
    property var times: []
    property var cpuTemps: []
    property var gpuTemps: []
    property var cpuUses: []            // utilization %, same indexes as times
    property var gpuUses: []
    property var gpuHots: []            // GPU hotspot °C and power W, same indexes as times
    property var gpuPowers: []
    property int revision: 0
    // Where the graph's data starts: its oldest kept sample (at most 24 hours ago), or now when it's empty
    readonly property double recordingSince: { revision; return times.length ? times[0] : Date.now() }
    property var stats: freshStats()
    property double lastSample: 0

    function freshStats() {
        const s = () => ({ low: null, high: null, highAt: 0, warnSecs: 0, hotSecs: 0, hotRun: 0, hotLongest: 0 })
        return { cpu: s(), gpu: s() }
    }
    function track(key, value, now, dt) {
        const s = stats[key], d = device(key)
        if (value === null) { s.hotRun = 0; return }
        if (s.low === null || value < s.low) s.low = value
        if (s.high === null || value > s.high) { s.high = value; s.highAt = now }
        if (value >= d.warn) s.warnSecs += dt
        if (value >= d.hot) {
            s.hotSecs += dt
            s.hotRun += dt
            s.hotLongest = Math.max(s.hotLongest, s.hotRun)
        } else {
            s.hotRun = 0
        }
    }
    // Recompute the low/high/time-at-red cards from the stored samples (used after loading history)
    function rebuildStats() {
        stats = freshStats()
        for (let i = 0; i < times.length; i++) {
            let dt = i ? (times[i] - times[i - 1]) / 1000 : 0
            if (dt > 3 * sampleMs / 1000) dt = 0
            track("cpu", cpuTemps[i], times[i], dt)
            track("gpu", gpuTemps[i], times[i], dt)
        }
    }

    // Readings that come too soon after the last one are skipped. Shouldn't happen any more: sampleClock
    // below paces samples by the wall clock (see there), so this is only a safety net.
    property int earlySkips: 0
    function sample() {
        const now = Date.now()
        if (lastSample && now - lastSample < sampleMs * 0.75 && now >= lastSample) {
            if (earlySkips++ % 100 === 0) console.warn("Temps: sample timer fired early,", now - lastSample, "ms after the last one; skips so far:", earlySkips)
            return
        }
        let dt = lastSample ? (now - lastSample) / 1000 : 0
        if (dt > 3 * sampleMs / 1000) dt = 0   // woke from suspend: don't count the gap
        lastSample = now
        if (cpuNow === null && gpuNow === null) return
        times.push(now)
        cpuTemps.push(cpuNow)
        gpuTemps.push(gpuNow)
        cpuUses.push(cpuUseNow)
        gpuUses.push(gpuUseNow)
        gpuHots.push(gpuHotNow)
        gpuPowers.push(gpuPowerNow)
        trimHistory()
        track("cpu", cpuNow, now, dt)
        track("gpu", gpuNow, now, dt)
        if (currentGame) {
            accumulate(currentGame.cpu, "cpu", cpuNow, dt, cpuUseNow)
            accumulate(currentGame.gpu, "gpu", gpuNow, dt, gpuUseNow, gpuHotNow, gpuPowerNow)
            addToCurve(currentGame, now, cpuNow, gpuNow, cpuUseNow, gpuUseNow, gpuHotNow, gpuPowerNow)
        }
        revision++
    }
    function trimHistory() {
        const cutoff = Date.now() - 24 * 3600 * 1000
        let drop = Math.max(0, times.length - maxSamples)
        while (drop < times.length && times[drop] < cutoff) drop++
        if (!drop) return
        for (const a of [times, cpuTemps, gpuTemps, cpuUses, gpuUses, gpuHots, gpuPowers]) a.splice(0, drop)
        // The cards' low/high/time-hot cover only what's still in the graph. Once a day has been recorded,
        // samples drop every tick, so recount at most once a minute (a full recount is ~43k samples)
        const now = Date.now()
        if (now - lastStatsRebuild > 60000) { rebuildStats(); lastStatsRebuild = now }
    }
    property double lastStatsRebuild: 0

    // ---- Game sessions ----
    // currentGame: { appid, name, icon, hero, header, start, cpu: acc, gpu: acc,
    //                curve: [[cpuMax, gpuMax, cpuUseAvg, gpuUseAvg, cpuUseN, gpuUseN, hotspotMax, powerAvg, powerN] per minute] }
    // acc = { sum, n, peak, hotSecs, useSum, useN } (use* = utilization %; missing in saves from before
    // 2026-10-13, see backfillUse). The GPU's also has hotSum/hotN/hotPeak (hotspot °C) and powSum/powN/powPeak (W),
    // missing in sessions from before they were recorded. Objects are mutated in place, so views must also depend on `revision`.
    property var currentGame: null
    property int gameMisses: 0
    property double firstMissAt: 0
    property var pendingResume: null    // in-progress session from games.json, waiting for the first game poll

    function newAcc() { return { sum: 0, n: 0, peak: null, hotSecs: 0 } }
    function accumulate(acc, key, value, dt, use, hot, power) {
        if (use !== null && use !== undefined) { acc.useSum = (acc.useSum ?? 0) + use; acc.useN = (acc.useN ?? 0) + 1 }
        for (const [f, v] of [["hot", hot], ["pow", power]]) {
            if (v === null || v === undefined) continue
            acc[f + "Sum"] = (acc[f + "Sum"] ?? 0) + v; acc[f + "N"] = (acc[f + "N"] ?? 0) + 1
            if (acc[f + "Peak"] === undefined || acc[f + "Peak"] === null || v > acc[f + "Peak"]) acc[f + "Peak"] = v
        }
        if (value === null) return
        acc.sum += value; acc.n++
        if (acc.peak === null || value > acc.peak) acc.peak = value
        if (value >= device(key).hot) acc.hotSecs += dt
    }
    function average(acc) { return acc && acc.n ? Math.round(acc.sum / acc.n) : null }
    function averageUse(acc) { return acc && acc.useN ? acc.useSum / acc.useN : null }
    function averageOf(acc, f) { return acc && acc[f + "N"] ? Math.round(acc[f + "Sum"] / acc[f + "N"]) : null }
    // "Hotspot avg 78° peak 91° · 214 W" for a GPU acc ("" when the session has neither)
    function gpuExtraLine(acc, muted) {
        const hAvg = averageOf(acc, "hot"), pAvg = averageOf(acc, "pow")
        if (hAvg === null && pAvg === null) return ""
        let s = `<font color="${muted}">Hotspot</font>`
        if (hAvg !== null)
            s += `&nbsp;&nbsp;<font color="${muted}">avg</font> <font color="${hotspotColor(hAvg)}"><b>${hAvg}°</b></font>`
                + `&nbsp;&nbsp;<font color="${muted}">peak</font> <font color="${hotspotColor(acc.hotPeak)}"><b>${acc.hotPeak}°</b></font>`
        else s += " --"
        if (pAvg !== null) s += `&nbsp;&nbsp;<font color="${muted}">·</font> <b>${pAvg} W</b> <font color="${muted}">avg</font>`
        return s
    }
    // "  · 23% used" for the end of a card's CPU/GPU stat line ("" when the session has no usage)
    function useSuffix(acc, muted) {
        const use = usage(averageUse(acc))
        return use === null ? "" : `&nbsp;&nbsp;<font color="${muted}">·</font> <b>${use}%</b> <font color="${muted}">used</font>`
    }
    // Sessions saved before usage had its own sums: rebuild them from the curve's per-minute averages
    // (a minute counts as 30 samples, so they weigh right against newer sessions). Fills game totals too.
    function backfillUse(log) {
        for (const appid in log) {
            const e = log[appid]
            for (const s of e.sessionLog || []) {
                for (const [k, key] of [[2, "cpu"], [3, "gpu"]]) {
                    if (s[key].useN !== undefined) continue
                    const v = curveFromString(s.curve).map(p => p[k]).filter(x => x !== null)
                    s[key].useSum = v.reduce((a, b) => a + b, 0) * 30
                    s[key].useN = v.length * 30
                    e[key].useSum = (e[key].useSum ?? 0) + s[key].useSum
                    e[key].useN = (e[key].useN ?? 0) + s[key].useN
                }
            }
        }
    }
    // One point per minute of play, keeping each minute's peak temperature and average usage
    function addToCurve(g, now, c, gp, cu, gu, hot, power) {
        const idx = Math.floor((now - g.start) / 60000)
        while (g.curve.length <= idx) g.curve.push([null, null, null, null, 0, 0, null, null, 0])
        const p = g.curve[idx]
        if (c !== null && (p[0] === null || c > p[0])) p[0] = c
        if (gp !== null && (p[1] === null || gp > p[1])) p[1] = gp
        if (hot !== null && hot !== undefined && (p[6] === null || hot > p[6])) p[6] = hot
        // averages: [value index, count index]
        for (const [k, nk, v] of [[2, 4, cu], [3, 5, gu], [7, 8, power]]) {
            if (v === null || v === undefined) continue
            const n = p[nk] || (p[k] === null ? 0 : 1)   // a point loaded from disk counts as one sample
            p[k] = ((p[k] ?? 0) * n + v) / (n + 1)
            p[nk] = n + 1
        }
    }
    // Curves are saved as "cpu,gpu,cpuUse,gpuUse,hotspot,power;…" (blank = no reading) so games.json stays
    // readable. Older sessions have just "cpu,gpu" or "cpu,gpu,cpuUse,gpuUse".
    function curveToString(curve) {
        const f = v => v === null || v === undefined ? "" : Math.round(v)
        return (curve || []).map(p => {
            const out = [f(p[0]), f(p[1]), f(p[2]), f(p[3])]
            if (p[6] !== null && p[6] !== undefined || p[7] !== null && p[7] !== undefined) out.push(f(p[6]), f(p[7]))
            return out.join(",")
        }).join(";")
    }
    function curveFromString(s) {
        if (!s) return []
        return s.split(";").map(p => {
            const v = p.split(",").map(v => v === "" ? null : Number(v))
            return [v[0] ?? null, v[1] ?? null, v[2] ?? null, v[3] ?? null, 0, 0, v[4] ?? null, v[5] ?? null, 0]
        })
    }

    // Sessions shorter than this are dropped when the game closes (test windows: temps-min-session=<seconds>)
    readonly property double testMinSessionSecs: Number((Qt.application.arguments.find(a => String(a).startsWith("temps-min-session=")) || "=-1").split("=")[1])
    readonly property double minSessionMs: testMinSessionSecs >= 0 ? testMinSessionSecs * 1000
        : Math.max(0, cfg.minSessionMinutes ?? 5) * 60000
    function longEnough(g, end) { return end - g.start >= minSessionMs }

    function startGame(appid, name, icon, hero, when, header) {
        currentGame = { appid: appid, name: name, icon: icon, hero: hero, header: header || "",
                        start: when, cpu: newAcc(), gpu: newAcc(), curve: [] }
        saveGameLog()
        revision++
    }
    function endGame(when) {
        if (!currentGame) return
        const g = currentGame
        currentGame = null
        // Too short to keep: forget it, but remember it a while in case the game is relaunched (see rejoinSession)
        if (longEnough(g, when)) { foldSession(gameLog, g, when); recentShort = null }
        else recentShort = { appid: g.appid, end: when, game: g }
        saveGameLog()
        revision++
    }

    // Relaunching the game you just closed (within rejoinMs, nothing else played since) continues that session
    // instead of starting a new one. The break counts toward the session's length.
    // Test window: `temps-rejoin=<seconds>` shortens the window
    readonly property double rejoinMs: Number((Qt.application.arguments.find(a => String(a).startsWith("temps-rejoin=")) || "=600").split("=")[1]) * 1000
    property var recentShort: null      // { appid, end, game }: last session too short to save, kept in memory only
    function rejoinSession(appid, name, icon, hero, header, now) {
        let g = null
        const last = lastSession   // most recent saved session of any game
        if (recentShort && recentShort.appid === appid && now - recentShort.end < rejoinMs
                && (!last || last.end <= recentShort.end)) {
            g = recentShort.game
        } else if (last && last.appid === appid && now - last.end < rejoinMs
                   && !(recentShort && recentShort.end > last.end)) {
            const s = gameLog[appid].sessionLog.find(x => x.start === last.start)
            g = { start: s.start, cpu: Object.assign({}, s.cpu), gpu: Object.assign({}, s.gpu), curve: curveFromString(s.curve) }
            deleteSession(appid, s.start)   // it's open again; it gets saved back when the game closes
        }
        recentShort = null
        if (!g) return false
        currentGame = Object.assign(g, { appid: appid, name: name, icon: icon, hero: hero, header: header })
        saveGameLog()
        revision++
        return true
    }

    // ---- Saved game log ----
    // gameLog: { appid: { appid, name, icon, hero, header, sessions, totalSecs, longestSecs, lastPlayed,
    //                     cpu: acc, gpu: acc, sessionLog: [{ start, end, cpu: acc, gpu: acc, curve: "…" }] } }
    property var gameLog: ({})

    function foldSession(log, g, end) {
        const e = log[g.appid] || {
            appid: g.appid, sessions: 0, totalSecs: 0, longestSecs: 0, lastPlayed: 0,
            cpu: newAcc(), gpu: newAcc(),
        }
        // Refresh name/art each time in case Steam's cache moved them
        e.name = g.name; e.icon = g.icon; e.hero = g.hero; e.header = g.header || e.header || ""
        const secs = Math.max(0, (end - g.start) / 1000)
        e.sessions++
        e.totalSecs += secs
        e.longestSecs = Math.max(e.longestSecs, secs)
        e.lastPlayed = end
        for (const key of ["cpu", "gpu"]) {
            const a = e[key], b = g[key]
            a.sum += b.sum; a.n += b.n; a.hotSecs += b.hotSecs
            for (const f of ["use", "hot", "pow"]) {
                if (b[f + "N"] === undefined) continue
                a[f + "Sum"] = (a[f + "Sum"] ?? 0) + b[f + "Sum"]; a[f + "N"] = (a[f + "N"] ?? 0) + b[f + "N"]
            }
            for (const f of ["hotPeak", "powPeak"])
                if (b[f] !== undefined && b[f] !== null && (a[f] === undefined || a[f] === null || b[f] > a[f])) a[f] = b[f]
            if (b.peak !== null && (a.peak === null || b.peak > a.peak)) a.peak = b.peak
        }
        e.sessionLog = (e.sessionLog || []).concat([{
            start: g.start, end: end,
            cpu: Object.assign({}, g.cpu), gpu: Object.assign({}, g.gpu),
            curve: curveToString(g.curve),
        }])   // kept forever (a 2-hour session is ~3 KB)
        log[g.appid] = e
    }

    // Remove one finished session (matched by start time) and take it out of the game's totals.
    // Peak and longest are rebuilt from the sessions still logged; sessions from before the log existed
    // (or trimmed by the old 100-per-game cap) only live in the totals, so their records can't be rebuilt.
    function deleteSession(appid, start) {
        const e = gameLog[appid]
        const i = e ? (e.sessionLog || []).findIndex(s => s.start === start) : -1
        if (i < 0) return
        const s = e.sessionLog.splice(i, 1)[0]
        const secs = Math.max(0, (s.end - s.start) / 1000)
        e.sessions = Math.max(0, e.sessions - 1)
        e.totalSecs = Math.max(0, e.totalSecs - secs)
        for (const key of ["cpu", "gpu"]) {
            const a = e[key], b = s[key]
            a.sum = Math.max(0, a.sum - b.sum); a.n = Math.max(0, a.n - b.n); a.hotSecs = Math.max(0, a.hotSecs - b.hotSecs)
            for (const f of ["use", "hot", "pow"]) {
                if (b[f + "N"] === undefined) continue
                a[f + "Sum"] = Math.max(0, (a[f + "Sum"] ?? 0) - b[f + "Sum"]); a[f + "N"] = Math.max(0, (a[f + "N"] ?? 0) - b[f + "N"])
            }
            for (const f of ["hotPeak", "powPeak"])
                if (b[f] !== undefined && b[f] !== null && b[f] >= (a[f] ?? -Infinity)) {
                    const left = e.sessionLog.map(x => x[key][f]).filter(v => v !== undefined && v !== null)
                    if (left.length) a[f] = Math.max(...left); else delete a[f]
                }
            if (b.peak !== null && b.peak >= (a.peak ?? -Infinity))
                a.peak = e.sessionLog.reduce((m, x) => x[key].peak !== null && (m === null || x[key].peak > m) ? x[key].peak : m, null)
        }
        if (secs >= e.longestSecs)
            e.longestSecs = e.sessionLog.reduce((m, x) => Math.max(m, (x.end - x.start) / 1000), 0)
        if (e.sessionLog.length) e.lastPlayed = Math.max(...e.sessionLog.map(x => x.end))
        if (e.sessions === 0) delete gameLog[appid]
        saveGameLog()
        revision++
    }

    // Cards for the games page: saved totals plus the game in progress, most recent first
    function gameLogView() {
        revision
        const merged = JSON.parse(JSON.stringify(gameLog))
        if (currentGame) {
            foldSession(merged, currentGame, Date.now())
            merged[currentGame.appid].playing = true
        }
        return Object.values(merged).sort((a, b) => ((b.playing ? 1 : 0) - (a.playing ? 1 : 0)) || b.lastPlayed - a.lastPlayed)
    }
    // One game's sessions for its history page, newest first (the one in progress included)
    function sessionsFor(appid) {
        revision
        const e = gameLogView().find(g => g.appid === appid)
        if (!e) return { game: null, sessions: [] }
        const list = (e.sessionLog || []).map(s => Object.assign({}, s, { curve: curveFromString(s.curve) }))
        if (e.playing && list.length) list[list.length - 1].playing = true
        return { game: e, sessions: list.reverse() }
    }
    // Most recent finished session, for the strip at the top of the popup
    readonly property var lastSession: {
        revision
        let best = null, bestGame = null
        for (const appid in gameLog) {
            const e = gameLog[appid], s = e.sessionLog && e.sessionLog[e.sessionLog.length - 1]
            if (s && (!best || s.end > best.end)) { best = s; bestGame = e }
        }
        if (!best) return null
        return { appid: bestGame.appid, name: bestGame.name, icon: bestGame.icon, hero: bestGame.hero,
                 start: best.start, end: best.end, cpu: best.cpu, gpu: best.gpu }
    }
    // Spans for the graph: saved sessions in the last day plus the one in progress
    function gameSpans() {
        const cutoff = Date.now() - 24 * 3600 * 1000, spans = []
        for (const appid in gameLog)
            for (const s of gameLog[appid].sessionLog || [])
                if (s.end > cutoff) spans.push({ name: gameLog[appid].name, start: s.start, end: s.end })
        if (currentGame) spans.push({ name: currentGame.name, start: currentGame.start, end: Date.now() })
        return spans
    }

    // steamgame.sh prints "appid\tname\ticon\thero\theader" while a Steam game runs, nothing otherwise
    function onGamePoll(line) {
        if (!logLoaded) return
        const appid = line ? line.split("\t")[0] : ""
        if (pendingResume) {
            // A panel restart mid-game: pick the same session back up instead of starting a new one
            const g = pendingResume
            pendingResume = null
            if (appid === g.appid && Date.now() - (g.lastSeen || g.start) < 10 * 60 * 1000) {
                delete g.lastSeen
                g.curve = curveFromString(g.curve)
                currentGame = g
                gameMisses = 0
                revision++
                return
            }
            // The game was closed while Plasma was down (e.g. a reboot): it ended when last seen
            g.curve = curveFromString(g.curve)
            if (longEnough(g, g.lastSeen || g.start)) foldSession(gameLog, g, g.lastSeen || g.start)
            saveGameLog()
            revision++
        }
        if (!line) {
            // Two empty polls in a row (~10s) before ending, so a hiccup doesn't split a session;
            // the session ends when the game was first seen gone, not after the wait
            if (!currentGame) return
            if (gameMisses++ === 0) firstMissAt = Date.now()
            if (gameMisses >= 2) endGame(firstMissAt)
            return
        }
        gameMisses = 0
        const [, name, icon, hero, header] = line.split("\t")
        if (currentGame && currentGame.appid === appid) return
        if (currentGame) endGame(Date.now())
        if (!rejoinSession(appid, name, icon || "", hero || "", header || "", Date.now()))
            startGame(appid, name, icon || "", hero || "", Date.now(), header || "")
    }

    P5Support.DataSource {
        id: gameSource
        engine: "executable"
        interval: 5000
        // `temps-fake-games` (test window only) watches for fake games instead of real Steam ones
        readonly property string cmd: (Qt.application.arguments.indexOf("temps-fake-games") >= 0 ? "TEMPS_FAKE_GAMES=1 " : "")
            + "bash '" + decodeURIComponent(Qt.resolvedUrl("../code/steamgame.sh").toString().replace(/^file:\/\//, "")) + "'"
        connectedSources: root.demo ? [] : [cmd]
        onNewData: (source, data) => root.onGamePoll((data.stdout || "").trim())
    }

    // ---- Process log: which apps used the CPU, sampled every 5s, last 24 hours ----
    // topapps.py prints {"t", "total", "top": [[name, pct, icon], …]} with % of the whole CPU.
    // Stored compactly: procNames = [[name, icon], …]; each sample = { t, total, top: [[nameIndex, pct], …] }.
    readonly property int procMs: 5000
    property var procSamples: []
    property var procNames: []
    property var procNameIndex: ({})
    property int procRevision: 0
    property bool procsLoaded: false

    function procName(name, icon) {
        const key = name + "\u0000" + icon
        if (!(key in procNameIndex)) { procNameIndex[key] = procNames.length; procNames.push([name, icon]) }
        return procNameIndex[key]
    }
    function onProcData(text) {
        let d = null
        try { d = JSON.parse(text) } catch (e) { return }
        if (!d || !d.top) return   // first call (baseline) or after a suspend
        procSamples.push({ t: d.t, total: d.total, top: d.top.map(x => [procName(x[0], x[2] || ""), x[1]]) })
        trimProcs()
        procRevision++
    }
    function trimProcs() {
        const cutoff = Date.now() - 24 * 3600 * 1000
        let drop = 0
        while (drop < procSamples.length && procSamples[drop].t < cutoff) drop++
        if (drop) procSamples.splice(0, drop)
    }
    // The sample covering time t (each covers the 5s before its timestamp), as
    // { t, total, top: [{ name, icon, pct }] }, or null if nothing was recorded then
    function procsAt(t) {
        procRevision
        const ps = procSamples
        let lo = 0, hi = ps.length
        while (lo < hi) { const mid = (lo + hi) >> 1; if (ps[mid].t < t) lo = mid + 1; else hi = mid }
        const s = ps[lo]
        if (!s || s.t - t > 2 * procMs) return null
        return { t: s.t, total: s.total, top: s.top.map(([i, pct]) => ({ name: procNames[i][0], icon: procNames[i][1], pct: pct })) }
    }
    readonly property var procsNow: {
        procRevision
        const last = procSamples[procSamples.length - 1]
        return last && Date.now() - last.t < 3 * procMs ? procsAt(last.t) : null
    }

    P5Support.DataSource {
        engine: "executable"
        interval: root.procMs
        // Test windows keep their own baseline file so they don't disturb the panel's numbers
        readonly property string cmd: "python3 -I '" + decodeURIComponent(Qt.resolvedUrl("../code/topapps.py").toString().replace(/^file:\/\//, ""))
            + "' \"${XDG_RUNTIME_DIR:-/tmp}/temps-topapps" + (root.testMode ? "-test" : "") + ".json\""
        connectedSources: root.demo ? [] : [cmd]
        onNewData: (source, data) => root.onProcData((data.stdout || "").trim())
    }

    // ---- Files in ~/.local/share/temperature-monitor ----
    // games.json:   { version: 2, games: gameLog, inProgress: currentGame + lastSeen }  (pretty-printed)
    // history.json: { version: 1, segments: [{ start, step, cpu: [...], gpu: [...], cpuUse: [...], gpuUse: [...] }] }
    //               (last 24h of the graph; usage arrays are missing from older saves)
    // procs.json:   { version: 1, start, names: [[name, icon]…], samples: [[secs after start, total, i, pct, i, pct…]…] }
    // Test windows (any temps-* argument) use ~/.local/share/temperature-monitor-test so they can't touch the real files.
    readonly property bool testMode: Qt.application.arguments.some(a => String(a).startsWith("temps-"))
    readonly property string dataDir: decodeURIComponent(StandardPaths.writableLocation(StandardPaths.GenericDataLocation)
        .toString().replace(/^file:\/\//, "")) + (testMode ? "/temperature-monitor-test" : "/temperature-monitor")
    property bool logLoaded: false
    property bool historyLoaded: false
    property int fileSeq: 0
    property var writeQueue: []         // [{ name, chunks, next }]; one shell command per chunk, run in order

    // Steam's portrait library poster for a game (backdrop of its sessions page). Not part of the saved art:
    // it sits in its own hash-named folder, so it's looked up on first use. appid → path ("" = none cached)
    property var capsules: ({})
    property var capsuleLookups: ({})   // appids already asked for (plain object: no bindings depend on it)
    function capsuleFor(appid) {
        if (capsules[appid] !== undefined) return capsules[appid]
        if (/^[0-9]+$/.test(appid) && !capsuleLookups[appid]) {
            capsuleLookups[appid] = true
            const cache = `"$HOME/.local/share/Steam/appcache/librarycache/${appid}"`
            fileIO.connectSource(`f=$(find ${cache} -maxdepth 2 -name library_capsule.jpg 2>/dev/null | head -1); `
                + `[ -z "$f" ] && f=$(find ${cache} -maxdepth 2 -name library_600x900.jpg 2>/dev/null | head -1); echo "$f" # capsule ${appid}`)
        }
        return ""
    }
    function onCapsuleFound(appid, path) {
        const c = Object.assign({}, capsules)
        c[appid] = path
        capsules = c
    }
    function shellQuote(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'" }
    function asciiJson(value, indent) {
        // \uXXXX escapes keep it pure ASCII, so names like "HELLDIVERS™ 2" survive base64 through the shell
        return JSON.stringify(value, null, indent)
            .replace(/[\u007f-￿]/g, c => "\\u" + c.charCodeAt(0).toString(16).padStart(4, "0"))
    }

    // Writes go through the shell as base64. Linux caps one argument at 128 KB, so big files are sent in
    // 96 KB pieces appended to a temp file, which is then renamed over the real one (never half-written).
    function base64Chunks(text) {
        const b64 = Qt.btoa(text), chunks = []
        for (let i = 0; i < b64.length; i += 96000) chunks.push(b64.slice(i, i + 96000))
        if (!chunks.length) chunks.push("")
        return chunks
    }
    property bool shuttingDown: false
    function writeFile(name, text) {
        if (shuttingDown) { writeFileDetached(name, text); return }
        const chunks = base64Chunks(text)
        // A newer save replaces one of the same file that hasn't started yet
        const waiting = writeQueue.findIndex((j, i) => i > 0 && j.name === name)
        if (waiting > 0) writeQueue[waiting].chunks = chunks
        else writeQueue.push({ name: name, chunks: chunks, next: 0 })
        if (writeQueue.length === 1) writeNextChunk()
    }
    function writeNextChunk() {
        const job = writeQueue[0]
        if (!job) return
        const dir = shellQuote(dataDir), tmp = `${dir}/${job.name}.tmp`
        const last = job.next === job.chunks.length - 1
        fileIO.connectSource(`mkdir -p ${dir} && printf %s '${job.chunks[job.next]}' | base64 -d ${job.next ? ">>" : ">"} ${tmp}`
            + (last ? ` && mv -f ${tmp} ${dir}/${job.name}` : "") + ` # write ${++fileSeq}`)
    }
    // At shutdown the queue never gets to run past its first command, so every piece is written at once by its
    // own process. Each one, after writing its piece, checks whether all pieces are there; whichever finishes
    // last joins them and renames over the real file. Nothing waits around, which matters because systemd kills
    // everything left in Plasma's cgroup when it stops (setsid doesn't escape that). If pieces race, each joins
    // into its own temp file and the rename is atomic; a failed join leaves the old file alone.
    // Base64 needs no quoting; paths are double-quoted inside the single-quoted script (no quotes in the folder).
    function writeFileDetached(name, text) {
        const chunks = base64Chunks(text)
        const base = `${dataDir}/.${name}.${Date.now()}`
        const parts = chunks.map((c, i) => `"${base}.${i}"`).join(" ")
        chunks.forEach((c, i) => fileIO.connectSource(`mkdir -p "${dataDir}" && setsid -f sh -c '`
            + `printf %s ${c} | base64 -d > "${base}.${i}.tmp" && mv -f "${base}.${i}.tmp" "${base}.${i}" || exit;`
            + ` for f in ${parts}; do [ -f "$f" ] || exit 0; done;`
            + ` cat ${parts} > "${base}.join${i}" && mv -f "${base}.join${i}" "${dataDir}/${name}" && rm -f ${parts};`
            + ` rm -f "${base}.join${i}"' # shutdown ${name} ${i}`))
    }
    function onChunkWritten(ok, stderr) {
        const job = writeQueue[0]
        if (!job) return
        if (!ok) console.warn("Temps: writing", job.name, "failed:", stderr)
        job.next++
        if (!ok || job.next >= job.chunks.length) writeQueue.shift()
        writeNextChunk()
    }

    function loadFiles() {
        const dir = shellQuote(dataDir)
        // Pieces from a shutdown save that was cut short are useless now (the real files are intact)
        fileIO.connectSource(`find ${dir} -maxdepth 1 -name '.*.json.*' -mmin +1 -delete 2>/dev/null; true # sweep`)
        fileIO.connectSource(`mkdir -p ${dir} && cat ${dir}/games.json 2>/dev/null; true # load games`)
        fileIO.connectSource(`cat ${dir}/history.json 2>/dev/null; true # load history`)
        fileIO.connectSource(`cat ${dir}/procs.json 2>/dev/null; true # load procs`)
    }
    function onGamesLoaded(text) {
        let doc = null
        try { doc = text ? JSON.parse(text) : null } catch (e) { console.warn("Temps: games.json unreadable:", e) }
        if (doc) {
            gameLog = doc.games || {}
            backfillUse(gameLog)
            pendingResume = doc.inProgress || null   // resumed or closed out on the first game poll
        } else {
            // First run with the file: bring over anything saved by the older settings-file version
            try { gameLog = JSON.parse(cfg.gameLog || "{}") } catch (e) { gameLog = {} }
        }
        logLoaded = true
        if (!text) saveGameLog()
        if (!testMode && cfg.gameLog && cfg.gameLog !== "{}") cfg.gameLog = "{}"
        revision++
    }
    function saveGameLog() {
        if (demo || !logLoaded) return
        const inProgress = currentGame
            ? Object.assign({}, currentGame, { lastSeen: Date.now(), curve: curveToString(currentGame.curve) })
            : null
        writeFile("games.json", asciiJson({ version: 2, games: gameLog, inProgress: inProgress }, 2))
    }

    function onHistoryLoaded(text) {
        let doc = null
        try { doc = text ? JSON.parse(text) : null } catch (e) { console.warn("Temps: history.json unreadable:", e) }
        const t = [], c = [], g = [], cu = [], gu = [], gh = [], gw = []
        for (const seg of (doc && doc.segments) || []) {
            for (let i = 0; i < seg.cpu.length; i++) {
                t.push(seg.start + i * seg.step); c.push(seg.cpu[i]); g.push(seg.gpu[i])
                // Segments saved before usage was recorded have no usage arrays
                cu.push(seg.cpuUse ? seg.cpuUse[i] ?? null : null); gu.push(seg.gpuUse ? seg.gpuUse[i] ?? null : null)
                gh.push(seg.gpuHot ? seg.gpuHot[i] ?? null : null); gw.push(seg.gpuPower ? seg.gpuPower[i] ?? null : null)
            }
        }
        // Saved samples are older than anything recorded since startup, so they go in front
        const first = times.length ? times[0] : Infinity
        const keep = t.findIndex(x => x >= first)
        const n = keep < 0 ? t.length : keep
        times = t.slice(0, n).concat(times)
        cpuTemps = c.slice(0, n).concat(cpuTemps)
        gpuTemps = g.slice(0, n).concat(gpuTemps)
        cpuUses = cu.slice(0, n).concat(cpuUses)
        gpuUses = gu.slice(0, n).concat(gpuUses)
        gpuHots = gh.slice(0, n).concat(gpuHots)
        gpuPowers = gw.slice(0, n).concat(gpuPowers)
        trimHistory()
        rebuildStats()
        historyLoaded = true
        revision++
    }
    function saveHistory() {
        if (demo || !historyLoaded || !times.length) return
        // Runs of evenly spaced samples become one segment (loaded back as start + i * step); anything that
        // would put a sample more than a second from its real time (a gap, a late or early timer, drift) starts another
        const segments = []
        let seg = null
        for (let i = 0; i < times.length; i++) {
            if (!seg || Math.abs(times[i] - (seg.start + seg.cpu.length * seg.step)) > Math.min(1000, seg.step / 2)) {
                seg = { start: times[i], step: sampleMs, cpu: [], gpu: [], cpuUse: [], gpuUse: [], gpuHot: [], gpuPower: [] }
                segments.push(seg)
            }
            seg.cpu.push(cpuTemps[i]); seg.gpu.push(gpuTemps[i])
            seg.cpuUse.push(cpuUses[i]); seg.gpuUse.push(gpuUses[i])
            seg.gpuHot.push(gpuHots[i] ?? null); seg.gpuPower.push(gpuPowers[i] ?? null)
        }
        writeFile("history.json", asciiJson({ version: 1, segments: segments }))
    }

    function onProcsLoaded(text) {
        let doc = null
        try { doc = text ? JSON.parse(text) : null } catch (e) { console.warn("Temps: procs.json unreadable:", e) }
        const loaded = []
        if (doc && doc.samples) {
            // Saved name indexes are remapped through procName, which also rebuilds the lookup table
            const ids = (doc.names || []).map(([n, i]) => procName(n, i))
            for (const row of doc.samples) {
                const top = []
                for (let k = 2; k + 1 < row.length; k += 2) top.push([ids[row[k]], row[k + 1]])
                loaded.push({ t: doc.start + row[0] * 1000, total: row[1], top: top })
            }
        }
        const first = procSamples.length ? procSamples[0].t : Infinity
        procSamples = loaded.filter(s => s.t < first).concat(procSamples)
        trimProcs()
        procsLoaded = true
        procRevision++
    }
    function saveProcs() {
        if (demo || !procsLoaded || !procSamples.length) return
        // Only names still in use are saved, renumbered in order
        const used = {}, names = []
        const remap = i => { if (!(i in used)) { used[i] = names.length; names.push(procNames[i]) } return used[i] }
        const start = procSamples[0].t
        const samples = procSamples.map(s => {
            const row = [Math.round((s.t - start) / 1000), s.total]
            for (const [i, pct] of s.top) row.push(remap(i), pct)
            return row
        })
        writeFile("procs.json", asciiJson({ version: 1, start: start, names: names, samples: samples }))
    }

    P5Support.DataSource {
        id: fileIO
        engine: "executable"
        onNewData: (source, data) => {
            if (source.endsWith("# load games")) root.onGamesLoaded((data.stdout || "").trim())
            else if (source.endsWith("# load history")) root.onHistoryLoaded((data.stdout || "").trim())
            else if (source.endsWith("# load procs")) root.onProcsLoaded((data.stdout || "").trim())
            else if (source.includes("# capsule ")) root.onCapsuleFound(source.split("# capsule ")[1], (data.stdout || "").trim())
            else if (source.includes("# shutdown ") || source.endsWith("# sweep")) { /* nothing to track */ }
            else root.onChunkWritten(!data["exit code"], data.stderr)
            disconnectSource(source)
        }
    }
    // Checkpoint the game in progress once a minute, and the graph every 5 minutes
    // (test windows can shorten both with temps-save-every=<ms>)
    readonly property int testSaveMs: Number((Qt.application.arguments.find(a => String(a).startsWith("temps-save-every=")) || "=0").split("=")[1])
    Timer {
        interval: root.testSaveMs || 60000
        repeat: true
        running: root.currentGame !== null && !root.demo
        onTriggered: root.saveGameLog()
    }
    Timer {
        interval: root.testSaveMs || 5 * 60000
        repeat: true
        running: !root.demo
        onTriggered: { root.saveHistory(); root.saveProcs() }
    }
    // Plasma shutting down (logout, reboot, panel restart): save what we can. A game in progress stays
    // "in progress" so it can be resumed if it's still running when Plasma comes back.
    Component.onDestruction: {
        if (demo) return
        shuttingDown = true
        saveHistory()
        saveProcs()
        if (currentGame) saveGameLog()
    }

    // ---- Clear Data… (from the settings page) ----
    // The settings dialog can't call into the widget, so it writes clearRequest = "games,history:<ms>".
    // Only fresh, newer requests count, so re-applying the dialog or a restart never clears twice.
    property double lastClearHandled: 0
    readonly property string clearRequest: cfg.clearRequest || ""
    onClearRequestChanged: {
        const [what, stamp] = clearRequest.split(":")
        const t = Number(stamp)
        if (!t || t <= lastClearHandled || Date.now() - t > 60000) return
        lastClearHandled = t
        clearData(what.split(","))
    }
    function clearData(parts) {
        const now = Date.now()
        if (parts.includes("games")) {
            gameLog = {}
            pendingResume = null
            // A game that's running keeps being tracked, as a new session starting now
            if (currentGame) Object.assign(currentGame, { start: now, cpu: newAcc(), gpu: newAcc(), curve: [] })
            saveGameLog()
        }
        if (parts.includes("history")) {
            times = []; cpuTemps = []; gpuTemps = []; cpuUses = []; gpuUses = []; gpuHots = []; gpuPowers = []
            stats = freshStats()
            lastSample = 0
            // Written through the same queue as other saves, so an earlier save can't land after it
            if (!demo) writeFile("history.json", asciiJson({ version: 1, segments: [] }))
            procSamples = []; procNames = []; procNameIndex = {}
            procRevision++
            if (!demo) writeFile("procs.json", asciiJson({ version: 1, start: now, names: [], samples: [] }))
        }
        revision++
    }

    // ---- Test hooks ----
    // `plasmawindowed blog.matthewmason.temps temps-demo` fills 3h of fake gaming history
    // Demo art paths (resolved by the same rules as steamgame.sh, hardcoded for the test data)
    function demoArt(appid) {
        const c = "/home/matthewm/.local/share/Steam/appcache/librarycache/" + appid + "/"
        const art = {
            "504230": ["04cb7aa0b497a3962e6b1655b7fd81a2cc95d18b.jpg", "library_hero_blur.jpg", "library_header.jpg"],
            "2073850": ["9532db560dca3b4982f4af3f5981b6b2ce2a6909.jpg", "f145688cf8e5b9e7b17cc4430b489a27fd5b21e5/library_hero_blur.jpg",
                        "983d4bbb62fa8acb3c038c5685988a73a8d3f2ba/library_header.jpg"],
            "292000": ["", "", "ba33a8aef67d6a1e3b17b0f1689731334c1ec541/library_header.jpg"],
            "2379780": ["", "", "137bbd62c036ea008fef89cbf5d6ad884c2735cf/library_header.jpg"],
            "548430": ["", "", "d2656c23cfebf75bb9841e32d27ec6d3b0d13073/library_header.jpg"],
        }[appid]
        return { icon: art[0] ? c + art[0] : "", hero: art[1] ? c + art[1] : "", header: c + art[2] }
    }
    readonly property bool demo: Qt.application.arguments.indexOf("temps-demo") >= 0
    // `temps-full` opens the popup view with live data only (no fake history)
    readonly property bool showFull: demo || Qt.application.arguments.indexOf("temps-full") >= 0

    function seedDemo() {
        const end = Date.now(), span = 3 * 3600
        let seed = 7
        const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647
        const play = (appid, name, t) => { const a = demoArt(appid); startGame(appid, name, a.icon, a.hero, t, a.header) }
        // Older sessions with made-up curves, so the games and session pages have something to show
        const fakeSession = (appid, name, daysAgo, minutes, cpuBase, gpuBase) => {
            const start = end - daysAgo * 86400000
            play(appid, name, start)
            for (let m = 0; m < minutes; m++) {
                const ramp = Math.min(1, m / 6), c = Math.round(cpuBase * ramp + 50 * (1 - ramp) + rnd() * 6 - 3)
                const gp = Math.round(gpuBase * ramp + 40 * (1 - ramp) + rnd() * 4 - 2)
                const cu = Math.round((cpuBase - 40) * 0.8 * ramp + 5 + rnd() * 8), gu = Math.round(Math.min(99, (gpuBase - 30) * 2.4 * ramp + 3 + rnd() * 6))
                const gh = gp + Math.round(14 * ramp + 4 + rnd() * 3), gw = Math.round(30 + gu * 2.6 + rnd() * 10)
                for (let k = 0; k < 30; k++) { accumulate(currentGame.cpu, "cpu", c, 2, cu); accumulate(currentGame.gpu, "gpu", gp, 2, gu, gh, gw) }
                addToCurve(currentGame, start + m * 60000, c, gp, cu, gu, gh, gw)
            }
            endGame(start + minutes * 60000)
        }
        fakeSession("548430", "Deep Rock Galactic", 9, 80, 78, 67)
        fakeSession("548430", "Deep Rock Galactic", 8, 50, 76, 65)
        fakeSession("2379780", "Balatro", 5, 65, 52, 44)
        fakeSession("2379780", "Balatro", 3, 40, 51, 43)
        fakeSession("292000", "No More Room in Hell 2", 2, 90, 88, 70)
        fakeSession("292000", "No More Room in Hell 2", 1.2, 55, 83, 68)
        fakeSession("292000", "No More Room in Hell 2", 1, 75, 86, 69)
        fakeSession("2073850", "THE FINALS", 1.1, 110, 84, 66)
        for (let i = 0; i < span; i += 2) {
            if (i > 5000 && i < 5600) { lastSample = 0; continue }   // simulated suspend
            const t = end - (span - i) * 1000
            const g = 1 / (1 + Math.exp(-(i - 3600) / 120)) - 1 / (1 + Math.exp(-(i - 8400) / 120))
            const c = Math.min(95, Math.round(50 + g * (40 + 6 * Math.sin(i / 400)) + rnd() * 4 - 2))
            const gp = Math.round(40 + g * (31 + 4 * Math.sin(i / 700)) + rnd() * 2 - 1)
            const cu = Math.round(4 + g * (30 + 8 * Math.sin(i / 300)) + rnd() * 6)
            const gu = Math.round(Math.min(99, 2 + g * (88 + 6 * Math.sin(i / 500)) + rnd() * 4))
            const dt = lastSample ? 2 : 0
            lastSample = t
            const gh = gp + Math.round(4 + g * 14 + rnd() * 3), gw = Math.round(30 + gu * 2.6 + rnd() * 10)
            times.push(t); cpuTemps.push(c); gpuTemps.push(gp); cpuUses.push(cu); gpuUses.push(gu); gpuHots.push(gh); gpuPowers.push(gw)
            track("cpu", c, t, dt); track("gpu", gp, t, dt)
            if (i === 900) play("504230", "Celeste", t)
            if (i === 2400) endGame(t)
            if (i === 3300) play("2073850", "THE FINALS", t)
            if (currentGame) {
                accumulate(currentGame.cpu, "cpu", c, dt, cu); accumulate(currentGame.gpu, "gpu", gp, dt, gu, gh, gw)
                addToCurve(currentGame, t, c, gp, cu, gu, gh, gw)
            }
        }
        lastSample = 0
        // Fake process samples: a few steady apps, the game while it runs, one Steam update burst
        for (let i = 0; i < span; i += 5) {
            const t = end - (span - i) * 1000
            if (i > 5000 && i < 5600) continue
            const gaming = (i >= 900 && i < 2400) ? "Celeste" : i >= 3300 ? "THE FINALS" : ""
            const top = [["Zen Browser", 1.5 + rnd() * 3, "zen"], ["Discord", 0.6 + rnd() * 1.2, "discord"],
                         ["KWin", 0.4 + rnd() * (gaming ? 2 : 0.5), "kwin"], ["Plasma Shell", 0.2 + rnd() * 0.4, "plasmashell"],
                         ["PipeWire", 0.2 + rnd() * 0.3, "audio-card"], ["Kernel", 0.3 + rnd() * 0.6, "cpu"]]
            if (gaming) top.push([gaming, (gaming === "Celeste" ? 6 : 24) + rnd() * 8, "input-gaming"])
            if (i > 2600 && i < 2700) top.push(["Steam", 80 + rnd() * 15, "steam"])
            else top.push(["Steam", 0.3 + rnd() * 0.8, "steam"])
            top.sort((a, b) => b[1] - a[1])
            const total = top.reduce((sum, x) => sum + x[1], 0) + 1
            procSamples.push({ t: t, total: Math.round(total * 10) / 10,
                               top: top.slice(0, 5).map(x => [procName(x[0], x[2]), Math.round(x[1] * 10) / 10]) })
        }
        procRevision++
        revision++
    }

    Timer {
        // `temps-shutdown-test=<bytes>` (test window): write big.txt the shutdown way (several pieces), then quit
        readonly property int bytes: Number((Qt.application.arguments.find(a => String(a).startsWith("temps-shutdown-test=")) || "=0").split("=")[1])
        interval: 3000
        running: bytes > 0
        onTriggered: {
            let text = ""
            for (let i = 0; text.length < bytes; i++) text += `line ${i} of the shutdown write test\n`
            root.shuttingDown = true
            root.writeFile("big.txt", text)
            console.log("SHUTDOWN-TEST wrote", text.length, "bytes in", root.base64Chunks(text).length, "pieces")
            Qt.quit()
        }
    }
    Timer {
        // `temps-clear=games,history` (test window): send a clear request the way the settings page does
        readonly property string parts: (Qt.application.arguments.find(a => String(a).startsWith("temps-clear=")) || "=").split("=")[1]
        interval: 4000
        running: parts !== ""
        onTriggered: Plasmoid.configuration.clearRequest = parts + ":" + Date.now()
    }

    Component.onCompleted: {
        const shot = Qt.application.arguments.find(a => a.startsWith("temps-shot="))
        if (shot) shotTimer.path = shot.slice("temps-shot=".length)
        if (demo) {
            logLoaded = historyLoaded = procsLoaded = true   // demo seeds its own data; nothing is read or written
            seedDemo()
        } else {
            loadFiles()
        }
    }

    // Test hook: save a picture of just the popup (no screen capture needed)
    Timer {
        id: shotTimer
        property string path: ""
        interval: Number((Qt.application.arguments.find(a => a.startsWith("temps-wait=")) || "temps-wait=3000").slice(11))
        running: path !== ""
        onTriggered: {
            console.log("TOOLTIP:" + root.toolTipSubText)
            // temps-width=<gridUnits> / temps-height=<gridUnits>: squeeze the popup first, to check small layouts
            const w = Number((Qt.application.arguments.find(a => String(a).startsWith("temps-width=")) || "=0").split("=")[1])
            const h = Number((Qt.application.arguments.find(a => String(a).startsWith("temps-height=")) || "=0").split("=")[1])
            if (w || h) {
                const item = root.fullRepresentationItem
                item.anchors.fill = undefined
                if (w) item.width = Kirigami.Units.gridUnit * w
                if (h) item.height = Kirigami.Units.gridUnit * h
                Qt.callLater(() => Qt.callLater(() => item.grabToImage(r => r.saveToFile(path))))
            } else {
                root.fullRepresentationItem.grabToImage(r => r.saveToFile(path))
            }
        }
    }

    // Samples are paced by the wall clock, not by the Timer's interval. A QML Timer runs on Qt Quick's
    // animation clock, which ran ~1.4x fast while fullscreen games were up (2026-10-13 to 10-15: readings
    // every ~1.45s instead of 2s, half of them then skipped). So it only ticks often, and a sample is taken
    // each time Date.now() passes the next mark on a sampleMs grid; ticking fast or slow just moves a sample
    // by up to one tick.
    property double nextSampleAt: 0
    property double clockCheckAt: 0     // drift log: wall time and tick count at the start of the window
    property int clockTicks: 0
    Timer {
        id: sampleClock
        interval: 250
        running: true
        repeat: true
        onTriggered: root.clockTick()
    }
    function clockTick() {
        const now = Date.now()
        logClockDrift(now)
        if (!nextSampleAt || now < nextSampleAt - 2 * sampleMs) {   // first tick, or the clock was set back
            nextSampleAt = now + sampleMs
            return
        }
        if (now < nextSampleAt) return
        sample()
        // Stay on the grid; if we fell more than a whole step behind (suspend, a stall) start a new one
        nextSampleAt = now - nextSampleAt >= sampleMs ? now + sampleMs : nextSampleAt + sampleMs
    }
    // Once per 10 minutes, warn if the ticks came noticeably faster or slower than their interval
    function logClockDrift(now) {
        clockTicks++
        if (!clockCheckAt) { clockCheckAt = now; clockTicks = 0; return }
        const span = now - clockCheckAt
        if (span < 600000) return
        const ratio = clockTicks * sampleClock.interval / span
        if (ratio > 1.1 || ratio < 0.9)
            console.warn("Temps: QML timer ran at", ratio.toFixed(2) + "x wall-clock speed over the last", Math.round(span / 60000), "min")
        clockCheckAt = now; clockTicks = 0
    }

    // ---- Panel / tooltip ----
    preferredRepresentation: showFull ? fullRepresentation : compactRepresentation
    compactRepresentation: CompactRepresentation {}
    fullRepresentation: FullRepresentation {}

    // Minimal hover: "CPU 53°  ↓48° ↑55°" per line, colored, no title
    toolTipMainText: ""
    toolTipTextFormat: Text.StyledText
    toolTipSubText: {
        revision   // re-evaluate on each sample
        const font = (color, text, bold) => `<font color="${color}">${bold ? "<b>" + text + "</b>" : text}</font>`
        const deg = v => (v ?? "--") + "°"
        const row = (key, now) => {
            const s = stats[key]
            return font(deviceColor(key), device(key).label) + "&nbsp;&nbsp;"
                + font(levelColor(key, now ?? 0), deg(now), true) + "&nbsp;&nbsp;&nbsp;"
                + font(Qt.alpha(Kirigami.Theme.textColor, 0.6), "↓") + deg(s.low) + "&nbsp;"
                + font(Qt.alpha(Kirigami.Theme.textColor, 0.6), "↑") + font(levelColor(key, s.high ?? 0), deg(s.high))
        }
        return row("cpu", cpuNow) + "<br>" + row("gpu", gpuNow)
    }
}
