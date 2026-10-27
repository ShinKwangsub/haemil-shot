import Carbon
import Cocoa
import ServiceManagement
import UserNotifications

// Haemil Shot 메뉴 막대 앱: 단축키·알림·화면 기록 권한 안내. 편집기(Bend)는 번들 안 Helpers 의 자식 프로세스로 띄운다.
// 화면 기록 권한은 책임 프로세스(이 앱)에 묶이고 posix_spawn 자식에게 이어지므로 이 앱 하나만 권한을 받으면 된다 (dist/NOTES.md).
let editor = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Haemil Shot Editor.app/Contents/MacOS/haemil-shot-editor")
// 편집기(Bend)와 같은 기준으로 HOME 환경 변수를 본다 (NSHomeDirectory 는 환경 변수를 무시해 가짜 HOME 검사가 실제 홈을 건드린다)
let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let captures = home + "/Library/Caches/BendShot/captures"
let devAgentPlist = home + "/Library/LaunchAgents/lab.bend.shotkeys.plist"

func log(_ m: String) { print(m); fflush(stdout) }

func spawn(_ args: [String]) -> Process? {
    let p = Process()
    p.executableURL = editor
    p.arguments = args
    do { try p.run(); return p } catch { log("편집기 실행 실패: \(error)"); return nil }
}

// 가장 최근 캡처: orig.png 바뀐 시각이 가장 늦은 폴더 (셸의 목록과 같은 기준: 소수 초, 같으면 이름이 큰 것).
// orig.png 가 없는 폴더(찍는 중, 취소)는 세지 않는다.
func newestCapture(_ root: String) -> (dir: String, at: Date)? {
    let fm = FileManager.default
    var best: (dir: String, at: Date)?
    for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
        let dir = root + "/" + name
        guard let at = (try? fm.attributesOfItem(atPath: dir + "/orig.png"))?[.modificationDate] as? Date else { continue }
        if best.map({ at > $0.at || (at == $0.at && dir > $0.dir) }) ?? true { best = (dir, at) }
    }
    return best
}

// 옛 개발용 LaunchAgent(lab.bend.shotkeys)가 같은 단축키를 잡고 있으면 내리고 plist 를 휴지통으로 옮긴다.
// 라벨이 아니라 plist 경로로 내리므로 HOME 안의 그 파일만 건드린다.
func retireDevAgent() {
    guard FileManager.default.fileExists(atPath: devAgentPlist) else { return }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    p.arguments = ["bootout", "gui/\(getuid())", devAgentPlist]
    try? p.run()
    p.waitUntilExit()
    do {
        try FileManager.default.trashItem(at: URL(fileURLWithPath: devAgentPlist), resultingItemURL: nil)
        log("옛 LaunchAgent 를 휴지통으로 옮김: \(devAgentPlist)")
    } catch { log("옛 LaunchAgent 정리 실패: \(error)") }
}

// 검사용: --newest <captures 폴더> 는 가장 최근 캡처 폴더를 찍고, --retire-dev-agent 는 옛 LaunchAgent 정리만 하고 끝난다
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--newest" {
    print(newestCapture(CommandLine.arguments[2])?.dir ?? "")
    exit(0)
}
if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--retire-dev-agent" {
    retireDevAgent()
    exit(0)
}

// 알림 클릭 → 그 캡처를 편집기로 연다
final class Clicks: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if r.actionIdentifier == UNNotificationDefaultActionIdentifier { _ = spawn(["--edit-last"]) }
        done()
    }
    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list])
    }
}
let clicks = Clicks()
let center = UNUserNotificationCenter.current()
center.delegate = clicks
center.requestAuthorization(options: [.alert]) { ok, err in
    log("알림 권한: \(ok ? "허용" : "거부") \(err.map { "오류 \($0)" } ?? "")")
}

// 썸네일은 그 캡처의 orig.png (thumb.bmp 는 BMP 라 알림 첨부가 받는 PNG·JPEG·GIF 가 아니다)
func notifyCaptured(_ png: String?) {
    let c = UNMutableNotificationContent()
    c.title = "Haemil Shot"
    c.body = "클립보드에 복사했습니다 · 눌러서 편집"
    // 첨부는 파일을 옮겨 가므로 원본 대신 임시 복사본을 준다
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory() + UUID().uuidString + ".png")
    do {
        guard let png = png else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.copyItem(atPath: png, toPath: tmp.path)
        c.attachments = [try UNNotificationAttachment(identifier: "capture", url: tmp)]
    } catch { log("썸네일 첨부 실패 (알림은 계속 띄움): \(error)") }
    center.add(UNNotificationRequest(identifier: UUID().uuidString, content: c, trigger: nil)) {
        log($0.map { "알림 실패: \($0)" } ?? "알림 띄움")
    }
}

// 캡처 프로세스가 끝날 때까지 기다렸다가 가장 최근 캡처가 새로 생긴 경우에만 알린다 (Esc 취소·권한 실패면 폴더가 지워져 조용히)
func capture(_ flag: String) {
    let before = newestCapture(captures)?.at
    DispatchQueue.global().async {
        guard let p = spawn([flag]) else { return }
        p.waitUntilExit()
        guard let after = newestCapture(captures), before.map({ after.at > $0 }) ?? true else { return }
        notifyCaptured(after.dir + "/orig.png")
    }
}

// 화면 기록 권한 안내 창: 권한이 없을 때만 뜨는 유일한 창. 로그인 항목·단축키 같은 나머지는 조용히 처리하고 기록만 남긴다.
var screenRequested = false
var accessWindow: NSWindow?

final class Button: NSObject {
    let run: () -> Void
    init(_ run: @escaping () -> Void) { self.run = run }
    @objc func go() { run() }
}
var buttonTargets: [Button] = []

func button(_ title: String, _ run: @escaping () -> Void) -> NSButton {
    let t = Button(run)
    buttonTargets.append(t)
    return NSButton(title: title, target: t, action: #selector(Button.go))
}

func showScreenAccessWindow() {
    if let w = accessWindow, w.isVisible { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
    buttonTargets = []
    let title = NSTextField(labelWithString: "화면 기록을 켜 주세요")
    title.font = .boldSystemFont(ofSize: 15)
    let body = NSTextField(wrappingLabelWithString: "캡처하려면 시스템 설정에서 Haemil Shot을 켜야 해요.")
    body.preferredMaxLayoutWidth = 320
    let settings = button("시스템 설정 열기") {
        if !screenRequested { screenRequested = true; _ = CGRequestScreenCaptureAccess() }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        accessWindow?.close()
    }
    settings.keyEquivalent = "\r"
    let later = button("나중에") { accessWindow?.close() }
    let buttons = NSStackView(views: [settings, later])
    buttons.spacing = 8
    let text = NSStackView(views: [title, body, buttons])
    text.orientation = .vertical
    text.alignment = .leading
    text.spacing = 10
    text.setCustomSpacing(16, after: body)
    let icon = NSImageView(image: NSApp.applicationIconImage)
    icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
    icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
    let row = NSStackView(views: [icon, text])
    row.alignment = .top
    row.spacing = 16
    row.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)

    let win = accessWindow ?? NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    win.title = "Haemil Shot"
    win.isReleasedWhenClosed = false
    win.contentView = row
    win.setContentSize(row.fittingSize)
    if accessWindow == nil { win.center() }
    accessWindow = win
    NSApp.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
}

// 로그인 시 자동 실행: /Applications 안에서만 조용히 등록한다. 결과는 기록만 하고 알리지 않는다 (백그라운드 항목 알림은 macOS 가 한다).
func registerLoginItem() {
    guard Bundle.main.bundlePath.hasPrefix("/Applications/") else { log("로그인 항목: /Applications 밖이라 등록하지 않음"); return }
    let svc = SMAppService.mainApp
    if svc.status == .notRegistered || svc.status == .notFound {
        do { try svc.register() } catch { log("로그인 항목 등록 실패: \(error)") }
    }
    log("로그인 항목 상태: \(svc.status.rawValue)")
}

// 캡처인데 권한이 없으면 실패할 캡처 대신 안내 창을 띄운다
func fire(_ flag: String) {
    if flag == "--edit-last" { _ = spawn([flag]) }
    else if CGPreflightScreenCaptureAccess() { capture(flag) }
    else { showScreenAccessWindow() }
}

// 디버그: --fire area|full|edit 한 번 실행, --notify-test 는 알림만 띄운다. 클릭을 받도록 60초 유지
let argv = CommandLine.arguments
var oneShot = false
if argv.count >= 2, argv[1] == "--fire" || argv[1] == "--notify-test" {
    oneShot = true
    if argv[1] == "--notify-test" { notifyCaptured(newestCapture(captures).map { $0.dir + "/orig.png" }) }
    else {
        let flags = ["area": "--area", "full": "--full", "edit": "--edit-last"]
        guard argv.count >= 3, let f = flags[argv[2]] else { fputs("알 수 없는 동작\n", stderr); exit(2) }
        if f == "--edit-last" { fire(f); exit(0) }
        capture(f)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 60) { exit(0) }
}

let keys: [(id: UInt32, name: String, what: String, code: Int, mods: Int, flag: String)] = [
    (1, "⌃⌥S", "영역 캡처", kVK_ANSI_S, controlKey | optionKey, "--area"),
    (2, "⌃⌥⇧S", "전체 화면 캡처", kVK_ANSI_S, controlKey | optionKey | shiftKey, "--full"),
    (3, "⌃⌥E", "마지막 캡처 편집", kVK_ANSI_E, controlKey | optionKey, "--edit-last"),
]

var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
    var hk = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                      nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
    if let k = keys.first(where: { $0.id == hk.id }) { fire(k.flag) }
    return noErr
}, 1, &spec, nil, nil)

if !oneShot {
    retireDevAgent()
    for k in keys {
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(UInt32(k.code), UInt32(k.mods), EventHotKeyID(signature: 0x42534b59, id: k.id),
                                     GetApplicationEventTarget(), 0, &ref)
        if st != noErr { log("단축키 \(k.name) 등록 실패 (다른 앱이 쓰는 중일 수 있음, 코드 \(st))") }
        else { log("단축키 \(k.name) 등록됨") }
    }
    registerLoginItem()
}

// 메뉴 막대 항목. 단축키는 표시만 한다 (실제 등록은 위 Carbon 핫키가 한다)
final class MenuActions: NSObject, NSMenuDelegate {
    @objc func run(_ item: NSMenuItem) {
        guard let k = keys.first(where: { $0.id == UInt32(item.tag) }) else { return }
        fire(k.flag)
    }
    @objc func screenAccess() { showScreenAccessWindow() }
    @objc func quit() { NSApp.terminate(nil) }
    // 메뉴를 열 때마다 권한을 다시 보고, 꺼져 있을 때만 "화면 기록 켜기…" 를 보인다
    func menuNeedsUpdate(_ menu: NSMenu) { screenItem.isHidden = CGPreflightScreenCaptureAccess() }
}
let menuActions = MenuActions()
var statusItem: NSStatusItem?
let screenItem = NSMenuItem(title: "화면 기록 켜기…", action: #selector(MenuActions.screenAccess), keyEquivalent: "")

if !oneShot {
    // 템플릿 이미지는 macOS 가 밝은/어두운 막대에 맞춰 칠한다. 1x·2x 를 같은 18pt 로 묶는다
    let icon = NSImage(size: NSSize(width: 18, height: 18))
    for name in ["MenuIcon", "MenuIcon@2x"] {
        guard let path = Bundle.main.path(forResource: name, ofType: "png"),
              let rep = NSBitmapImageRep(data: (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()) else { continue }
        rep.size = NSSize(width: 18, height: 18)
        icon.addRepresentation(rep)
    }
    icon.isTemplate = true

    let menu = NSMenu()
    menu.delegate = menuActions
    for k in keys {
        let item = NSMenuItem(title: k.what, action: #selector(MenuActions.run(_:)), keyEquivalent: "")
        item.target = menuActions
        item.tag = Int(k.id)
        item.keyEquivalent = k.name.contains("E") ? "e" : "s"
        item.keyEquivalentModifierMask = k.name.contains("⇧") ? [.control, .option, .shift] : [.control, .option]
        menu.addItem(item)
    }
    menu.addItem(.separator())
    screenItem.target = menuActions
    menu.addItem(screenItem)
    let quit = NSMenuItem(title: "Haemil Shot 종료", action: #selector(MenuActions.quit), keyEquivalent: "q")
    quit.target = menuActions
    menu.addItem(quit)

    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    statusItem?.button?.image = icon
    statusItem?.menu = menu
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
if !oneShot {
    // 창은 화면 기록 권한이 없을 때만 뜬다
    DispatchQueue.main.async { if !CGPreflightScreenCaptureAccess() { showScreenAccessWindow() } }
}
app.run()
