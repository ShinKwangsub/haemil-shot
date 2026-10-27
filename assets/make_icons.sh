#!/bin/sh
# icon.swift(시안 b)에서 앱 아이콘과 메뉴 막대 아이콘을 만든다. 결과물(.icns/.png)은 커밋하므로 아이콘을 바꿀 때만 돌린다.
set -e
cd "$(dirname "$0")"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
swiftc -O icon.swift -o "$TMP/icon"
SET="$TMP/AppIcon.iconset"
mkdir "$SET"
for s in 16 32 128 256 512; do
  "$TMP/icon" b $s "$SET/icon_${s}x${s}.png"
  "$TMP/icon" b $((s * 2)) "$SET/icon_${s}x${s}@2x.png"
done
iconutil -c icns "$SET" -o AppIcon.icns
"$TMP/icon" menu 18 MenuIcon.png
"$TMP/icon" menu 36 MenuIcon@2x.png
echo "생성: AppIcon.icns MenuIcon.png MenuIcon@2x.png"
