#!/bin/bash
# Prints "appid<TAB>name<TAB>icon<TAB>heroBlur<TAB>header" for the Steam game that's running, or nothing.
# Steam starts every game under a process named exactly "reaper" with "SteamLaunch AppId=<id>".
# Tests set TEMPS_FAKE_GAMES=1 and use a process named "fake-reaper", so fake games
# never show up in (or get saved by) the real widget in the panel.
proc=reaper
[ -n "$TEMPS_FAKE_GAMES" ] && proc=fake-reaper
id=$(pgrep -a -x "$proc" | grep -o 'AppId=[0-9]*' | grep -v '^AppId=0$' | head -1 | cut -d= -f2)
[ -z "$id" ] && exit 0

steam="$HOME/.local/share/Steam"
name=""
while IFS= read -r lib; do
    f="$lib/steamapps/appmanifest_$id.acf"
    if [ -f "$f" ]; then
        name=$(grep -m1 '"name"' "$f" | cut -d'"' -f4)
        break
    fi
done < <(grep -o '"path"[[:space:]]*"[^"]*"' "$steam/steamapps/libraryfolders.vdf" 2>/dev/null | cut -d'"' -f4; echo "$steam")

# Library art: the 32px sidebar icon is a hash-named .jpg; newer caches nest other art one level down
cache="$steam/appcache/librarycache/$id"
icon=$(find "$cache" -maxdepth 1 -regextype egrep -regex '.*/[0-9a-f]{40}\.jpg' 2>/dev/null | head -1)
hero=$(find "$cache" -maxdepth 2 -name library_hero_blur.jpg 2>/dev/null | head -1)
header=$(find "$cache" -maxdepth 2 -name library_header.jpg 2>/dev/null | head -1)
[ -z "$header" ] && header=$(find "$cache" -maxdepth 2 -name header.jpg 2>/dev/null | head -1)

printf '%s\t%s\t%s\t%s\t%s\n' "$id" "${name:-Steam app $id}" "$icon" "$hero" "$header"
