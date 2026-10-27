# Haemil Shot 배포 메모

## 화면 기록 권한은 책임 프로세스에 묶인다 (2026-10-27 시험)

질문: 바깥 메뉴 막대 앱(Haemil Shot.app)이 둥지 앱의 편집기·캡처 실행 파일을 `Process`(posix_spawn)로 띄우면,
화면 기록 권한을 바깥 앱 하나만 받아도 자식의 `screencapture` 가 되는가?

시험: 던져 버리는 `Outer.app`(Developer ID 서명, 번들 id `lab.bend.shot.tcctest`, 시스템 설정의 화면 기록 목록에 없음) 이
`Contents/Helpers/Inner.app/Contents/MacOS/inner` 를 `Process` 로 띄우고, inner 가 `screencapture -x -t png` 를 돌린다.
같은 번들을 두 가지로 실행했다.

| 실행 방식 | 바깥 `CGPreflightScreenCaptureAccess()` | 자식 `screencapture` |
|---|---|---|
| 셸(권한 있는 앱의 자손)에서 실행 파일을 직접 실행 | true | rc=0, 5120×2880 PNG 3.9 MB (진짜 화면) |
| `open Outer.app` (LaunchServices, 바깥 앱이 스스로 책임 프로세스) | false | rc=1 `could not create image from display`, 파일 없음 |

같은 바이너리인데 책임 프로세스 사슬만 달랐다. 권한은 바이너리가 아니라 책임 프로세스를 보고, posix_spawn 자식은 부모의 책임 프로세스를 잇는다.
그러므로 설치한 Haemil Shot.app 이 LaunchServices 로 뜨면 그 앱이 책임 프로세스이고, 그 앱이 `Process` 로 띄우는 편집기·캡처는 모두 그 권한을 쓴다.
편집기가 다른 캡처를 열려고 자기를 다시 띄울 때(`Launch.run`, `/bin/sh -c "$0 --edit ..." &`)도 자손이라 같은 권한을 잇는다.
`open`/LaunchServices 로 띄우면 새 프로세스가 스스로 책임 프로세스가 되어 권한이 끊기므로 쓰지 않는다.

둥지 앱의 독 표시: 편집기 프로세스를 바깥 번들 안 `Contents/Helpers/Haemil Shot Editor.app/Contents/MacOS/haemil-shot-editor` 로 띄우면
`lsappinfo` 가 `LSDisplayName="Haemil Shot"`, `CFBundleIdentifier=lab.bend.shot.editor` 로 보고한다 (둥지 번들의 이름·아이콘).

권한은 번들 id 만이 아니라 서명의 코드 요구 사항에도 묶인다. 임시 서명이나 자체 서명 인증서로 받은 권한은 Developer ID 로 서명한 앱에 이어지지 않는다 (같은 번들 id 라도 `CGPreflight` 가 false 였다).

## 짜임

```
Haemil Shot.app                      lab.bend.shot, LSUIElement, 메뉴 막대·단축키·알림·화면 기록 안내 (app/main.swift)
  Contents/MacOS/haemil-shot         universal (arm64 + x86_64)
  Contents/Resources/                AppIcon.icns, MenuIcon.png, MenuIcon@2x.png
  Contents/Helpers/Haemil Shot Editor.app   lab.bend.shot.editor, 독에 제 이름·아이콘 (shot.bend → C → clang)
    Contents/MacOS/haemil-shot-editor       universal
```

서명: Developer ID Application, `--options runtime`, 배포는 `--timestamp`. 안쪽(편집기) 먼저, 바깥 나중. 엔타이틀먼트 없음
(샌드박스 밖이라 Carbon 단축키·UNUserNotification·자식 프로세스·Metal 셰이더 컴파일이 hardened runtime 기본값으로 된다. 편집기 헤드리스 편집과 창 열기를 서명된 번들로 확인).

## 화면 기록 안내 (app/main.swift)

다 괜찮으면 창이 전혀 뜨지 않는다. 창은 하나뿐이다: 실행할 때 `CGPreflightScreenCaptureAccess()` 가 false 면 "화면 기록을 켜 주세요".
- "시스템 설정 열기": `CGRequestScreenCaptureAccess` 한 번 + 개인정보 설정의 화면 기록 패널을 열고 창을 닫는다. "나중에": 닫는다. 다시 시작 단추는 없다 (켜면 시스템 설정이 "종료 후 다시 열기" 를 내놓는다)
- 메뉴 "화면 기록 켜기…" 는 권한이 없을 때만 보인다 (`NSMenuDelegate.menuNeedsUpdate` 가 메뉴를 열 때마다 다시 본다). 같은 창을 연다
- 단축키·메뉴로 캡처하려는데 권한이 없으면 실패할 캡처 대신 같은 창을 띄운다 (마지막 캡처 편집은 권한이 필요 없다)
- 로그인 항목: `/Applications/` 안에서만 `SMAppService.mainApp.register()` 를 조용히 부른다. 밖이거나 오류거나 `requiresApproval` 이어도 기록만 한다 (백그라운드 항목 알림은 macOS 가 한다)
- 단축키 등록 실패도 기록만 한다
- 옛 개발용 LaunchAgent `~/Library/LaunchAgents/lab.bend.shotkeys.plist` 가 있으면 `launchctl bootout gui/<uid> <plist 경로>` 뒤 휴지통으로. 라벨이 아니라 경로로 내리므로 가짜 HOME 검사가 실제 에이전트에 닿지 않는다
- 창 확인: 번들 id 를 바꿔 임시 서명한 복사본을 `open -n --env HOME=<가짜 홈>` 으로 띄우면 권한이 없는 상태가 되어 창이 뜬다 (실제 TCC 는 건드리지 않는다)

## 빌드·배포

- `build.sh` 개발용 `shot` 실행 파일 (검사가 쓴다)
- `dist/build.sh [--release]` 앱 번들, `dist/release.sh` 공증·DMG → `dist/out/HaemilShot-<버전>.dmg`, `HaemilShot.dmg`, `SHA256SUMS`
- 버전은 `VERSION`
