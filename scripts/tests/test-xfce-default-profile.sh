#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
xml=ports/xfce/xfce4-panel/default.xml

grep -Fq 'name="position" type="string" value="p=6;x=0;y=0"' "$xml"
grep -Fq 'name="size" type="uint" value="26"' "$xml"
grep -Fq 'name="position" type="string" value="p=10;x=0;y=0"' "$xml"
grep -Fq 'name="length" type="uint" value="10"' "$xml"
grep -Fq 'name="size" type="uint" value="48"' "$xml"
grep -Fq 'name="plugin-6" type="string" value="power-manager-plugin"' "$xml"
for id in 11 12 13 14 15; do
    grep -Eq "name=\"plugin-$id\".*name=\"items\" type=\"array\".*value type=\"string\"" "$xml"
done

for spec in \
    bfs-terminal.desktop:org.xfce.terminal \
    bfs-files.desktop:org.xfce.thunar \
    bfs-image-viewer.desktop:org.xfce.ristretto \
    bfs-media-player.desktop:org.xfce.parole \
    bfs-disc-burner.desktop:stock_xfburn
do
    file=${spec%%:*}; icon=${spec#*:}
    grep -Fq "Icon=$icon" "ports/xfce/xfce4-panel/$file"
done

helper=ports/xfce/xfce4-panel/bfs-xfce-first-login
grep -Fq 'xrandr --query' "$helper"
grep -Fq 'monitor${output}' "$helper"
! grep -Fq 'monitorVirtual-1' "$helper"
grep -Fq '/usr/share/backgrounds/xfce/xfce-blue.jpg' "$helper"
grep -Fq -- '-n -a -t string -s "$file"' "$helper"
grep -Fq 'Any user-owned launcher directory is treated as customization' "$helper"

echo "XFCE default-profile regression: PASS"
