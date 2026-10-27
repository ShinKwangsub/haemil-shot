#!/bin/zsh
# Haemil Shot.app (인텔·애플실리콘 겸용) 을 빌드하고 서명한다. 결과: dist/out/Haemil Shot.app
#   ./build.sh            개발용: 키체인에 Developer ID 가 있으면 그것으로, 없으면 임시 서명
#   ./build.sh --release  배포용: Developer ID 필수, 보안 타임스탬프 포함
# 짜임: 메뉴 막대 앱(app/main.swift) 이 바깥, Bend 편집기(shot.bend) 는 Contents/Helpers 안의 둥지 앱.
# 편집기는 바깥 앱의 자식 프로세스로 돌아 화면 기록 권한을 바깥 앱 하나만 받으면 된다 (NOTES.md).
set -e
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
RELEASE=$([[ "$1" == "--release" ]] && echo 1 || echo 0)
# 관문: 규칙(LAWS.bend)의 증명이 깨져 있으면 빌드하지 않는다
if ! ~/.bend/bin/bend PROOF.bend 2>&1 | grep -q "ALL PROOFS CHECK"; then
  echo "빌드 중단: bend PROOF.bend 가 ALL PROOFS CHECK 가 아닙니다" >&2
  exit 1
fi
B=dist/out/build
mkdir -p $B
~/.bend/bin/bend shot.bend -o $B/shot.c
# bend 가 맥에서 쓰는 옵션과 같다 (창·Metal 코드가 Objective-C, -fmodules 가 프레임워크를 링크). 아키텍처만 둘로 나눈다.
for arch in arm64 x86_64; do
  clang -x objective-c -fobjc-arc -fmodules -std=c11 -O3 -w -arch $arch -mmacosx-version-min=13.0 \
    $B/shot.c -lpthread -lm -o $B/editor-$arch
  swiftc -O -target $arch-apple-macos13.0 app/main.swift -o $B/app-$arch
done
APP="dist/out/Haemil Shot.app"
EDITOR="$APP/Contents/Helpers/Haemil Shot Editor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$EDITOR/Contents/MacOS" "$EDITOR/Contents/Resources"
lipo -create $B/app-arm64 $B/app-x86_64 -output "$APP/Contents/MacOS/haemil-shot"
lipo -create $B/editor-arm64 $B/editor-x86_64 -output "$EDITOR/Contents/MacOS/haemil-shot-editor"
cp assets/AppIcon.icns assets/MenuIcon.png assets/MenuIcon@2x.png "$APP/Contents/Resources/"
cp assets/AppIcon.icns "$EDITOR/Contents/Resources/"
cp LICENSE NOTICE "$APP/Contents/Resources/"
# 번들 id 는 lab.bend.shot 그대로 (화면 기록 권한이 id 에 묶인다). 둥지 앱은 독에 제 이름·아이콘으로 뜨도록 따로 둔다.
plist() {
  cat > "$1" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>$2</string>
<key>CFBundleName</key><string>Haemil Shot</string>
<key>CFBundleDisplayName</key><string>Haemil Shot</string>
<key>CFBundleExecutable</key><string>$3</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>ko</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>LSUIElement</key><$4/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Copyright © 2026 Kwangsub Shin. MIT License.</string>
</dict></plist>
PL
}
plist "$APP/Contents/Info.plist" lab.bend.shot haemil-shot true
plist "$EDITOR/Contents/Info.plist" lab.bend.shot.editor haemil-shot-editor false
ID=$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application[^"]*\)".*/\1/p' | head -n 1)
if [[ -n "$ID" ]]; then
  # 엔타이틀먼트 없음: 샌드박스 밖이고, 단축키·알림·자식 프로세스·Metal 은 hardened runtime 기본값으로 된다
  TS=$([[ $RELEASE == 1 ]] && echo --timestamp || echo --timestamp=none)
  codesign --force --options runtime $TS -s "$ID" "$EDITOR"
  codesign --force --options runtime $TS -s "$ID" "$APP"
elif [[ $RELEASE == 1 ]]; then
  echo "배포용 빌드에는 키체인의 Developer ID Application 인증서가 필요합니다" >&2
  exit 1
else
  echo "경고: Developer ID 가 없어 임시 서명합니다. 다시 빌드할 때마다 화면 기록 권한을 다시 줘야 합니다." >&2
  codesign --force -s - "$EDITOR"
  codesign --force -s - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "빌드 완료: $PWD/$APP ($VERSION)"
