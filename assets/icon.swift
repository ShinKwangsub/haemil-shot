// BendShot 아이콘 그리기: swift icon.swift <a|b|c|menu> <크기> <출력.png>
// 손으로 그린 그림 대신 이 스크립트가 원본이다 (모양·색을 바꾸면 다시 돌린다).
import AppKit

let args = CommandLine.arguments
let kind = args.count > 1 ? args[1] : "a"
let size = CGFloat(args.count > 2 ? Double(args[2])! : 1024)
let out = args.count > 3 ? args[3] : "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let k = size / 1024  // 1024 격자 기준 좌표를 크기에 맞춘다

func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
  // 위에서 아래로 재는 좌표로 쓰려고 뒤집는다
  NSRect(x: x * k, y: (1024 - y - h) * k, width: w * k, height: h * k)
}
func rr(_ r: NSRect, _ rad: CGFloat) -> NSBezierPath { NSBezierPath(roundedRect: r, xRadius: rad * k, yRadius: rad * k) }
func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> NSBezierPath { NSBezierPath(ovalIn: R(cx - r, cy - r, r * 2, r * 2)) }
func gray(_ v: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(calibratedWhite: v, alpha: a) }
func fill(_ p: NSBezierPath, _ c: NSColor) { c.setFill(); p.fill() }
func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat) { c.setStroke(); p.lineWidth = w * k; p.stroke() }
func grad(_ p: NSBezierPath, _ top: NSColor, _ bottom: NSColor) {
  NSGradient(starting: top, ending: bottom)!.draw(in: p, angle: -90)
}

// macOS 아이콘 격자: 824 정사각형, 모서리 185
let tile = rr(R(100, 100, 824, 824), 185)

switch kind {
case "a":
  // 검은 바탕 + 흰 선 카메라 (BendBack 과 같은 선 아이콘 계열)
  grad(tile, gray(0.20), gray(0.02))
  let w: CGFloat = 34
  stroke(rr(R(222, 372, 580, 360), 64), .white, w)          // 몸체
  stroke(rr(R(268, 318, 120, 54), 18), .white, w)           // 왼쪽 다이얼
  stroke(rr(R(612, 330, 150, 42), 14), .white, w)           // 오른쪽 윗면 단
  stroke(circle(512, 552, 128), .white, w)                  // 렌즈 바깥
  stroke(circle(512, 552, 62), .white, w)                   // 렌즈 안
  fill(circle(318, 452, 20), .white)                        // 작은 창
case "b":
  // 흰 바탕 + 검은 카메라 몸체
  grad(tile, gray(1.0), gray(0.86))
  fill(rr(R(262, 330, 130, 64), 20), gray(0.10))            // 다이얼 둘
  fill(rr(R(420, 340, 150, 54), 18), gray(0.10))
  fill(rr(R(196, 380, 632, 384), 70), gray(0.07))           // 몸체
  // 몸체 무늬(마름모 결)를 아주 옅게
  NSGraphicsContext.current?.saveGraphicsState()
  rr(R(196, 380, 632, 384), 70).addClip()
  let lines = NSBezierPath()
  var t: CGFloat = -400
  while t < 1400 { lines.move(to: NSPoint(x: t * k, y: 0)); lines.line(to: NSPoint(x: (t + 600) * k, y: 600 * k + 400 * k)); t += 22 }
  t = -400
  while t < 1400 { lines.move(to: NSPoint(x: (t + 600) * k, y: 0)); lines.line(to: NSPoint(x: t * k, y: 1000 * k)); t += 22 }
  stroke(lines, gray(1, 0.05), 2)
  NSGraphicsContext.current?.restoreGraphicsState()
  fill(circle(512, 574, 158), gray(0.16))                   // 렌즈 고리
  stroke(circle(512, 574, 158), gray(0.45), 6)
  fill(circle(512, 574, 112), gray(0.04))
  stroke(circle(512, 574, 112), gray(0.30), 4)
  grad(circle(512, 574, 64), NSColor(calibratedRed: 0.20, green: 0.24, blue: 0.36, alpha: 1), NSColor(calibratedRed: 0.02, green: 0.03, blue: 0.08, alpha: 1))
  fill(circle(486, 548, 18), gray(1, 0.75))                 // 유리 반사
  fill(rr(R(268, 430, 44, 30), 8), gray(0.30))              // 작은 창
case "c":
  // 타일 자체가 검은 카메라 앞면
  grad(tile, gray(0.17), gray(0.05))
  fill(rr(R(100, 100, 824, 160), 0), gray(0.02, 0.0))
  fill(rr(R(220, 92, 120, 50), 16), gray(0.12))             // 윗면 다이얼(타일 밖으로 살짝)
  fill(rr(R(380, 98, 160, 40), 14), gray(0.12))
  fill(circle(512, 560, 250), gray(0.82))                   // 은색 고리
  grad(circle(512, 560, 236), gray(0.95), gray(0.55))
  fill(circle(512, 560, 200), gray(0.06))
  stroke(circle(512, 560, 170), gray(0.25), 6)
  grad(circle(512, 560, 120), NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.32, alpha: 1), NSColor(calibratedRed: 0.01, green: 0.02, blue: 0.06, alpha: 1))
  fill(circle(476, 524, 30), gray(1, 0.7))
  fill(rr(R(196, 196, 70, 46), 10), gray(0.30))             // 작은 창
case "menu":
  // 메뉴 막대용 견본(검정만, macOS 가 밝기에 맞춰 칠한다). 18pt 에서 보이게 면으로 채우고 렌즈만 뚫는다
  fill(rr(R(250, 250, 230, 130), 36), .black)               // 다이얼 둘 (몸체와 겹쳐 한 덩어리)
  fill(rr(R(560, 270, 220, 110), 36), .black)
  fill(rr(R(80, 330, 864, 500), 110), .black)               // 몸체
  let ctx = NSGraphicsContext.current!
  ctx.compositingOperation = .clear
  fill(circle(512, 585, 210), .black)                       // 렌즈 고리 바깥을 뚫고
  ctx.compositingOperation = .sourceOver
  fill(circle(512, 585, 118), .black)                       // 안쪽은 다시 채워 고리만 남긴다
default:
  fatalError("모르는 종류: \(kind)")
}

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
