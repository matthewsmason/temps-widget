#!/usr/bin/env python3
"""Which apps used the CPU since the last call, as % of the whole CPU.

Prints one JSON line: {"t": ms, "total": pct, "top": [[name, pct, icon], ...]} (top 5), or {"t": ms} on the
first call, which only records a baseline. Usage: topapps.py <state-file>

CPU time comes from cgroups: systemd puts each app in its own one (app-steam@autostart.service,
app-discord-1532.scope, a Konsole tab's scope, ...) and the kernel keeps a running total per cgroup that
includes processes that have already exited, so short-lived helpers are counted too. Two kinds are split
further by process: Steam's (a running game lives inside it, under its `reaper SteamLaunch AppId=N`
process) and terminal tabs (show the command, not "Konsole"). Whatever no cgroup accounts for (kernel
threads, interrupts) is "Kernel".
"""
import json
import os
import re
import sys
import time

CG = "/sys/fs/cgroup"
HZ = os.sysconf("SC_CLK_TCK")
NCPU = os.cpu_count() or 1
HOME = os.path.expanduser("~")
TOP = 5

DESKTOP_DIRS = [
    HOME + "/.local/share/applications", "/usr/share/applications", "/usr/local/share/applications",
    HOME + "/.local/share/flatpak/exports/share/applications", "/var/lib/flatpak/exports/share/applications",
    HOME + "/.config/autostart", "/etc/xdg/autostart",
]
TERMINALS = {"org.kde.konsole", "konsole", "kitty", "alacritty", "foot", "org.wezfurlong.wezterm",
             "org.gnome.Terminal", "org.gnome.Ptyxis", "com.mitchellh.ghostty", "yakuake", "org.kde.yakuake"}
# Plasma session services and other well-known units: unit name → (name, icon)
UNITS = {
    "plasma-kwin_wayland": ("KWin", "kwin"),
    "plasma-plasmashell": ("Plasma Shell", "plasmashell"),
    "plasma-kded6": ("KDE Daemon", "preferences-system"),
    "plasma-ksystemstats": ("System Stats", "utilities-system-monitor"),
    "plasma-xdg-desktop-portal-kde": ("Desktop Portal", "preferences-system"),
    "pipewire": ("PipeWire", "audio-card"),
    "pipewire-pulse": ("PipeWire", "audio-card"),
    "wireplumber": ("PipeWire", "audio-card"),
    "xorg-xwayland": ("Xwayland", "xorg"),
}


def unescape(s):
    return re.sub(r"\\x([0-9a-fA-F]{2})", lambda m: chr(int(m.group(1), 16)), s)


def desktop_entry(app_id, cache):
    """Friendly name and icon for a desktop-file id, cached in the state file."""
    if app_id in cache:
        return cache[app_id]
    found = None
    for d in DESKTOP_DIRS:
        try:
            with open(f"{d}/{app_id}.desktop", encoding="utf-8", errors="replace") as f:
                name = icon = None
                in_entry = False
                for line in f:
                    line = line.strip()
                    if line.startswith("["):
                        in_entry = line == "[Desktop Entry]"
                    elif in_entry and line.startswith("Name=") and name is None:
                        name = line[5:]
                    elif in_entry and line.startswith("Icon=") and icon is None:
                        icon = line[5:]
                if name:
                    found = [name, icon or ""]
                    break
        except OSError:
            pass
    if not found:
        # "org.kde.foo" → "Foo", "polychromatic-autostart" → "Polychromatic"
        base = app_id.split(".")[-1].removesuffix("-autostart")
        found = [base[:1].upper() + base[1:], ""]
    cache[app_id] = found
    return found


def classify(path, cache):
    """cgroup path → (group key, name, icon, split) where split is None, "steam" or "terminal"."""
    leaf = path.rsplit("/", 1)[-1]
    # Konsole and friends: app-org.kde.konsole-48497.scope/tab(48505).scope
    parts = path.split("/")
    for p in reversed(parts):
        m = re.match(r"app-(?:flatpak-)?(.+?)(?:@[^/]*\.service|-\d+\.scope|\.service|\.scope)$", unescape(p))
        if m:
            app_id = re.sub(r"^dbus-:[\d.]+-", "", m.group(1))
            name, icon = desktop_entry(app_id, cache)
            split = "terminal" if app_id in TERMINALS else "steam" if app_id == "steam" else None
            return "app:" + app_id, name, icon, split
    unit = unescape(re.sub(r"\.(service|scope|slice)$", "", leaf))
    if unit in UNITS:
        name, icon = UNITS[unit]
        return "unit:" + name, name, icon, None
    if unit.startswith("plasma-"):
        unit = unit[7:]
    return "unit:" + unit, unit, "preferences-system" if "/system.slice/" in path else "system-run", None


def leaf_cgroups():
    """{path: usage_usec} for every cgroup with no children (processes only live in leaves)."""
    out = {}
    for root, dirs, files in os.walk(CG):
        if dirs or "cpu.stat" not in files or root == CG:
            continue
        try:
            with open(root + "/cpu.stat") as f:
                out[root[len(CG):]] = int(f.readline().split()[1])
        except (OSError, ValueError, IndexError):
            pass
    return out


def proc_stat(pid):
    """(comm, ppid, starttime, cpu ticks) or None."""
    try:
        with open(f"/proc/{pid}/stat") as f:
            s = f.read()
    except OSError:
        return None
    comm = s[s.index("(") + 1:s.rindex(")")]
    rest = s[s.rindex(")") + 2:].split()
    return comm, int(rest[1]), int(rest[19]), int(rest[11]) + int(rest[12])


def cgroup_pids(path):
    try:
        with open(CG + path + "/cgroup.procs") as f:
            return [int(x) for x in f.read().split()]
    except OSError:
        return []


def steam_game_name(appid, cache):
    key = "steam:" + appid
    if key in cache:
        return cache[key]
    steam = HOME + "/.local/share/Steam"
    libs = [steam]
    try:
        with open(steam + "/steamapps/libraryfolders.vdf", encoding="utf-8", errors="replace") as f:
            libs += re.findall(r'"path"\s*"([^"]*)"', f.read())
    except OSError:
        pass
    name = None
    for lib in libs:
        try:
            with open(f"{lib}/steamapps/appmanifest_{appid}.acf", encoding="utf-8", errors="replace") as f:
                m = re.search(r'"name"\s*"([^"]*)"', f.read())
                if m:
                    name = m.group(1)
                    break
        except OSError:
            pass
    cache[key] = name or f"Steam app {appid}"
    return cache[key]


def split_processes(path, kind, procs, prev_procs, prev_time, btime, cache):
    """Per-process breakdown of one cgroup: {(key, name, icon): ticks since last call}."""
    pids = cgroup_pids(path)
    info = {}
    for pid in pids:
        st = proc_stat(pid)
        if st:
            info[pid] = st
    # Steam: anything under a `reaper ... AppId=N` belongs to that game
    games = {}
    if kind == "steam":
        for pid, (comm, *_rest) in info.items():
            if comm == "reaper":
                try:
                    with open(f"/proc/{pid}/cmdline", "rb") as f:
                        m = re.search(rb"AppId=(\d+)", f.read())
                except OSError:
                    m = None
                if m and m.group(1) != b"0":
                    games[pid] = m.group(1).decode()
    out = {}
    for pid, (comm, ppid, start, ticks) in info.items():
        key = f"{pid}:{start}"
        procs[key] = ticks
        if key in prev_procs:
            delta = ticks - prev_procs[key]
        elif prev_time and btime + start / HZ > prev_time:
            delta = ticks   # started since the last call: all of its time is new
        else:
            delta = 0       # no baseline yet (first call)
        if delta <= 0:
            continue
        if kind == "steam":
            p, appid, seen = pid, None, 0
            while p > 1 and seen < 64:
                if p in games:
                    appid = games[p]
                    break
                p = info[p][1] if p in info else 1
                seen += 1
            if not appid:
                continue   # Steam's own processes stay in the Steam total
            g = ("game:" + appid, steam_game_name(appid, cache), "input-gaming")
        else:
            if comm in ("fish", "zsh", "bash", "sh", "dash"):
                continue   # an idle shell isn't interesting; it stays in the terminal's total
            g = ("cmd:" + comm, comm, "utilities-terminal")
        out[g] = out.get(g, 0) + delta
    return out


def main():
    state_path = sys.argv[1]
    now = time.time()
    try:
        with open(state_path) as f:
            prev = json.load(f)
    except (OSError, ValueError):
        prev = {}
    cache = prev.get("names", {})
    if len(cache) > 500:
        cache = {}

    with open("/proc/stat") as f:
        stat = f.read()
    cpu = [int(x) for x in stat.split("\n", 1)[0].split()[1:]]
    btime = int(re.search(r"^btime (\d+)", stat, re.M).group(1))
    busy_usec = (sum(cpu[:8]) - cpu[3] - cpu[4]) * 1_000_000 // HZ   # everything but idle and iowait

    cgroups = leaf_cgroups()
    prev_cg = prev.get("cgroups", {})
    prev_procs = prev.get("procs", {})
    procs = {}
    elapsed = now - prev.get("time", now)

    groups = {}   # key → [name, icon, usec]
    def add(key, name, icon, usec):
        g = groups.setdefault(key, [name, icon, 0])
        g[2] += usec

    accounted = 0
    for path, usage in cgroups.items():
        key, name, icon, split = classify(path, cache)
        # Split cgroups always record their processes, so the next call has a baseline
        parts = split_processes(path, split, procs, prev_procs, prev.get("time", 0), btime, cache) if split else {}
        if path not in prev_cg:
            continue
        delta = max(0, usage - prev_cg[path])
        accounted += delta
        if split:
            for (k, n, i), ticks in parts.items():
                usec = min(delta, ticks * 1_000_000 // HZ)
                add(k, n, i, usec)
                delta -= usec
        if delta > 0:
            add(key, name, icon or "", delta)
    if "busy" in prev:
        kernel = (busy_usec - prev["busy"]) - accounted
        if kernel > 0:
            add("kernel", "Kernel", "cpu", kernel)

    with open(state_path + ".tmp", "w") as f:
        json.dump({"time": now, "busy": busy_usec, "cgroups": cgroups, "procs": procs, "names": cache}, f)
    os.replace(state_path + ".tmp", state_path)

    t = int(now * 1000)
    # No baseline yet, or a long pause (suspend): the deltas would be meaningless
    if not prev or elapsed <= 0 or elapsed > 60:
        print(json.dumps({"t": t}))
        return
    scale = 100 / (elapsed * 1_000_000 * NCPU)
    total = (busy_usec - prev["busy"]) * scale
    top = sorted(groups.values(), key=lambda g: -g[2])[:TOP]
    print(json.dumps({
        "t": t,
        "total": round(max(0, total), 1),
        "top": [[name, round(usec * scale, 1), icon] for name, icon, usec in top if usec * scale >= 0.05],
    }, ensure_ascii=True))


if __name__ == "__main__":
    main()
