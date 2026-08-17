#!/bin/bash
find . -type f -name "Pkgfile" -exec sh -c '
  for file; do
sed -i "s|^# Maintainer:.*|# Maintainer: Brian Madonna email bmadonnaster@gmail.com|" "$file"
    LINE_TO_ADD="# Add your top line text here"
    grep -qxF "$LINE_TO_ADD" "$file" || { temp=$(mktemp); echo "$LINE_TO_ADD" | cat - "$file" > "$temp" && mv "$temp" "$file"; }
  done
' sh {} +
