#!/usr/bin/env python3 -I
"""BendShot 검사: 증명 관문, 규칙 파일 불변, 픽셀 기준 구현 비교, 창 루프 재현, 보관·자동 저장.

실행: python3 -I test/verify.py   (./build.sh 로 만든 ./shot 이 빌드되어 있어야 한다. 캡처(--area/--full)는 절대 돌리지 않는다)
"""
import os
import struct
import subprocess
import sys
import re
import shutil
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SHOT = os.environ.get("SHOT", os.path.join(HERE, "..", "shot"))  # 옛 바이너리로 돌려 검사가 잡는지 볼 때 바꾼다
OUT = os.path.join(HERE, "out")
BEND = os.path.expanduser("~/.bend/bin/bend")
# HOME 도 가짜로: shot 은 시작마다 ~/Library/Caches/BendShot 을 보므로 (옛 last.png 옮기기) 실제 캐시에 닿지 않게 한다
FAKE_HOME = tempfile.mkdtemp(prefix="bendshot-home-")
ENV = dict(os.environ, BENDSHOT_QUIET="1", HOME=FAKE_HOME)
# shot.bend 의 Color.px 와 같은 값, BGRA 순서
COLORS = {"red": (0x30, 0x3B, 0xFF, 0xFF), "yellow": (0x00, 0xCD, 0xFF, 0xFF), "green": (0x59, 0xD7, 0x34, 0xFF),
          "blue": (0xFF, 0x7A, 0x00, 0xFF), "black": (0x00, 0x00, 0x00, 0xFF), "white": (0xFF, 0xFF, 0xFF, 0xFF)}
RED = COLORS["red"]
YELLOW = (0x0A, 0xD6, 0xFF)  # 형광펜의 빨강은 이 노랑(0xFFFFD60A)으로 칠한다
STROKE_KEYS = {"pen": 52, "high": 53, "line": 54, "arrow": 55, "ellipse": 56, "erase": 57}

failures = 0


def report(name, ok, detail=""):
    global failures
    print(("PASS" if ok else "FAIL") + " " + name + ((" " + detail) if detail else ""))
    if not ok:
        failures += 1


class Bmp:
    """32비트 BMP. rows 는 위에서부터의 행, 각 행은 BGRA 바이트열."""

    def __init__(self, data):
        self.off = struct.unpack_from("<I", data, 10)[0]
        self.w = struct.unpack_from("<i", data, 18)[0]
        hraw = struct.unpack_from("<i", data, 22)[0]
        self.topdown = hraw < 0
        self.h = -hraw if hraw < 0 else hraw
        assert struct.unpack_from("<H", data, 28)[0] == 32
        ppm = struct.unpack_from("<i", data, 38)[0]
        self.s = 2 if ppm > 4000 else 1
        self.d = self.s  # 표시 배율 (창 맞추기로 커질 수 있다: 검사가 직접 놓는다)
        self.ppm = ppm
        self.hdr = data[: self.off]
        self.crop = None
        rb = 4 * self.w
        rows = [bytearray(data[self.off + i * rb : self.off + (i + 1) * rb]) for i in range(self.h)]
        self.rows = rows if self.topdown else rows[::-1]

    def tobytes(self):
        """자른 영역이 있으면 screencapture 와 같은 138바이트 V5 헤더로 그 영역만 (위에서부터) 쓴다."""
        if self.crop is None:
            rows = self.rows if self.topdown else self.rows[::-1]
            return self.hdr + b"".join(bytes(r) for r in rows)
        lx, ly, hx, hy = self.crop
        w, h = hx - lx + 1, hy - ly + 1
        hdr = b"BM" + struct.pack("<IHHI", 138 + 4 * w * h, 0, 0, 138)
        hdr += struct.pack("<IiiHHIIiiII", 124, w, -h, 1, 32, 3, 4 * w * h, self.ppm, self.ppm, 0, 0)
        hdr += struct.pack("<IIII", 0xFF0000, 0xFF00, 0xFF, 0xFF000000) + b"BGRs" + bytes(64)
        return hdr + b"".join(bytes(self.rows[y][4 * lx : 4 * (hx + 1)]) for y in range(ly, hy + 1))

    def crop_(self, x0, y0, x1, y1):
        if x0 == x1 or y0 == y1:
            return
        self.crop = self.norm(x0, y0, x1, y1)

    def copy(self):
        c = Bmp.__new__(Bmp)
        c.__dict__.update(self.__dict__)
        c.rows = [bytearray(r) for r in self.rows]
        return c

    def norm(self, x0, y0, x1, y1):
        """화면 픽셀 하나가 원본 d×d 를 덮으므로 영역을 화면 픽셀 단위로 맞춘다 (shot 의 Rect.snap 과 같다)."""
        s = self.d
        lx, hx = sorted((x0, x1))
        ly, hy = sorted((y0, y1))
        lx, ly = lx // s * s, ly // s * s
        hx, hy = hx // s * s + s - 1, hy // s * s + s - 1
        clamp = lambda v, m: min(v, m - 1)
        return clamp(lx, self.w), clamp(ly, self.h), clamp(hx, self.w), clamp(hy, self.h)

    def box(self, x0, y0, x1, y1, color="red"):
        if x0 == x1 or y0 == y1:
            return
        lx, ly, hx, hy = self.norm(x0, y0, x1, y1)
        t = 3 * self.s
        ix0, iy0, ix1, iy1 = lx + t, ly + t, hx - t, hy - t
        for y in range(ly, hy + 1):
            row = self.rows[y]
            for x in range(lx, hx + 1):
                if ix0 <= x <= ix1 and iy0 <= y <= iy1:
                    continue
                row[4 * x : 4 * x + 4] = COLORS[color]

    def stroke(self, tool, pts, color="red"):
        """pts 는 원본 좌표, 누른 점부터 뗀 점까지 시간 순서."""
        s, w, h = self.s, self.w, self.h
        cpts = [(min(x, w - 1), min(y, h - 1)) for x, y in pts]
        rad = 16 * s if tool == "high" else 3 * s
        if tool in ("pen", "high"):
            segs = polyline(cpts)
        elif tool == "line":
            segs = pieces(*cpts[0], *cpts[-1])
        elif tool == "arrow":
            segs = pieces(*cpts[0], *cpts[-1]) + arrow_head(*cpts[0], *cpts[-1], 14 * s, w, h)
        else:
            segs = ellipse_segs(*self.norm(*pts[0], *pts[-1]))
        blend = YELLOW if color == "red" else COLORS[color][:3]
        for x, y in stroke_cover(segs, rad, w, h):
            row = self.rows[y]
            if tool == "high":
                row[4 * x : 4 * x + 4] = bytes([(row[4 * x + i] * 3 + blend[i] * 2) // 5 for i in range(3)] + [255])
            else:
                row[4 * x : 4 * x + 4] = COLORS[color]

    def mosaic(self, x0, y0, x1, y1):
        if x0 == x1 or y0 == y1:
            return
        lx, ly, hx, hy = self.norm(x0, y0, x1, y1)
        B = 8 * self.s
        src = [bytes(r) for r in self.rows]
        for by in range(ly // B * B, hy + 1, B):
            for bx in range(lx // B * B, hx + 1, B):
                sums = [0, 0, 0]
                n = 0
                for y in range(by, min(by + B, self.h)):
                    for x in range(bx, min(bx + B, self.w)):
                        p = src[y][4 * x : 4 * x + 3]
                        sums[0] += p[0]
                        sums[1] += p[1]
                        sums[2] += p[2]
                        n += 1
                avg = bytes([sums[0] // n, sums[1] // n, sums[2] // n, 255])
                for y in range(by, min(by + B, self.h)):
                    for x in range(bx, min(bx + B, self.w)):
                        self.rows[y][4 * x : 4 * x + 4] = avg


# 획 기하 기준 구현 (shot.bend 의 Seg.* 와 같은 정수 식. 정수만 쓰므로 결과가 바이트까지 같아야 한다: 허용 오차 0)
# ---------------------------------------------------------------------------------------------

def pieces(ax, ay, bx, by):
    """선분을 체비쇼프 길이 64 이하의 조각으로 (끝점은 정수 내림, (x, y) 가 작은 끝에서 시작해 방향과 무관). 거리 비교가 32비트 안에 들게 하는 규칙."""
    if (bx, by) < (ax, ay):
        ax, ay, bx, by = bx, by, ax, ay
    m = max((max(abs(bx - ax), abs(by - ay)) + 63) // 64, 1)
    lerp = lambda a, b, i: a + (b - a) * i // m if b >= a else a - (a - b) * i // m
    out, px, py = [], ax, ay
    for i in range(1, m + 1):
        qx, qy = lerp(ax, bx, i), lerp(ay, by, i)
        out.append((px, py, qx, qy))
        px, py = qx, qy
    return out


def seg_hit(seg, px, py, rr):
    """픽셀 (px, py) 가 조각의 캡슐(반지름 r, rr = (2r)²) 안인가."""
    ax, ay, bx, by = seg
    abx, aby, apx, apy = bx - ax, by - ay, px - ax, py - ay
    len2 = abx * abx + aby * aby
    dot = apx * abx + apy * aby
    if dot < 0:
        return 4 * (apx * apx + apy * apy) <= rr
    if dot >= len2:
        return 4 * ((px - bx) ** 2 + (py - by) ** 2) <= rr
    cross = apx * aby - apy * abx
    return 4 * cross * cross <= rr * len2


def stroke_cover(segs, rad, w, h):
    """조각들의 캡슐 합집합에 든 그림 안 픽셀 집합 (한 픽셀은 한 번만: 겹친 조각도 한 번만 칠해진다)."""
    rr, rc = rad * rad, (rad + 1) // 2
    cover = set()
    for seg in segs:
        ax, ay, bx, by = seg
        for y in range(max(min(ay, by) - rc, 0), min(max(ay, by) + rc, h - 1) + 1):
            for x in range(max(min(ax, bx) - rc, 0), min(max(ax, bx) + rc, w - 1) + 1):
                if (x, y) not in cover and seg_hit(seg, x, y, rr):
                    cover.add((x, y))
    return cover


def polyline(pts):
    segs = [(pts[-1][0], pts[-1][1], pts[-1][0], pts[-1][1])]  # 뗀 점의 점 하나: 클릭만 해도 점
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        segs += pieces(ax, ay, bx, by)
    return segs


def isqrt(n):
    import math
    return math.isqrt(n)


def arrow_head(ax, ay, bx, by, l, w, h):
    """끝점에서 축 반대쪽 ±30° 로 길이 l 의 두 획. 고정소수점 (cos30·65536 = 56756, sin30·65536 = 32768), 0 쪽으로 자름."""
    dx, dy = bx - ax, by - ay
    ln = isqrt(dx * dx + dy * dy)
    if ln == 0:
        return []
    tdiv = lambda a, b: -(-a // b) if a < 0 else a // b
    off = lambda num: tdiv(tdiv(num, ln) * l, 65536)
    clamp = lambda v, m: max(0, min(v, m - 1))
    c, sn = 56756, 32768
    e1x, e1y = off(dx * c - dy * sn), off(dx * sn + dy * c)
    e2x, e2y = off(dx * c + dy * sn), off(dx * sn - dy * c)
    return pieces(bx, by, clamp(bx - e1x, w), clamp(by - e1y, h)) + pieces(bx, by, clamp(bx - e2x, w), clamp(by + e2y, h))


def ell_table():
    import math
    t = []
    for i in range(256):
        a = 2 * math.pi * i / 256
        t += [65536 + round(math.cos(a) * 65536), 65536 + round(math.sin(a) * 65536)]
    return t


def ellipse_segs(lx, ly, hx, hy):
    """영역에 내접하는 256각형 (꼭짓점 = x0 + dx·(65536 + cos·65536) / 131072)."""
    t = ell_table()
    dx, dy = hx - lx, hy - ly
    verts = [(lx + dx * t[2 * i] // 131072, ly + dy * t[2 * i + 1] // 131072) for i in range(256)]
    px, py = hx, ly + dy // 2
    segs = []
    for qx, qy in verts + [(px, py)]:
        segs += pieces(px, py, qx, qy)
        px, py = qx, qy
    return segs


def synth_bytes(w=333, h=217, ppm=2835, bpp=32):
    """양수 높이(아래 행부터 저장)의 BI_RGB BMP, 알려진 무늬. ppm > 4000 이면 shot 이 배율 2 로 본다."""
    rows = []
    for y in range(h):
        row = bytearray()
        for x in range(w):
            row += bytes([(y * 5) & 255, (x ^ y) & 255, (x * 7 + y * 3) & 255] + ([255] if bpp == 32 else []))
        row += bytes(-len(row) % 4)
        rows.append(bytes(row))
    body = b"".join(rows[::-1])
    hdr = b"BM" + struct.pack("<IHHI", 54 + len(body), 0, 0, 54)
    hdr += struct.pack("<IiiHHIIiiII", 40, w, h, 1, bpp, 0, len(body), ppm, ppm, 0, 0)
    return hdr + body


def synth(path, **kw):
    with open(path, "wb") as f:
        f.write(synth_bytes(**kw))


def synth_fast(path, w, h, ppm):
    """큰 그림을 빨리 만든다 (행마다 한 색, 32비트, 아래 행부터). 창 맞추기 검사용."""
    body = b"".join(bytes([(y * 5) & 255, (y * 3) & 255, (y * 7) & 255, 255]) * w for y in range(h))
    hdr = b"BM" + struct.pack("<IHHI", 54 + len(body), 0, 0, 54)
    hdr += struct.pack("<IiiHHIIiiII", 40, w, h, 1, 32, 0, len(body), ppm, ppm, 0, 0)
    with open(path, "wb") as f:
        f.write(hdr + body)


def run_shot(mode, inp, out, args, timeout=60):
    """out 을 지우고 shot 을 돌린다. (성공 여부, 걸린 시간, 결과) 를 돌려준다."""
    if os.path.exists(out):
        os.remove(out)
    t0 = time.time()
    try:
        cmd = [SHOT, mode] + ([inp] if inp is not None else []) + [out] + [str(a) for a in args]
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=ENV)
    except subprocess.TimeoutExpired:
        return False, timeout, None
    dt = time.time() - t0
    return r.returncode == 0, dt, r


def expect(ref, inp, out, ops, name, mode="--edit"):
    """ops 를 기준 구현과 shot 양쪽에 적용해 결과 바이트를 비교한다."""
    ok, dt, r = run_shot(mode, inp, out, ops)
    if not ok or not os.path.exists(out):
        report(name, False, "shot 이 실패하거나 결과를 쓰지 않음" + ("" if r is None else " " + (r.stdout + r.stderr).strip()[-200:]))
        return
    got = open(out, "rb").read()
    want = ref.tobytes()
    if got == want:
        if ref.crop is not None:
            # 자른 결과를 sips 가 그대로 읽는지 (편집본을 PNG 로 바꾸는 길)
            r = subprocess.run(["/usr/bin/sips", "-g", "pixelWidth", "-g", "pixelHeight", out], capture_output=True, text=True)
            dims = [int(l.split()[-1]) for l in r.stdout.splitlines() if "pixel" in l]
            if dims != [ref.crop[2] - ref.crop[0] + 1, ref.crop[3] - ref.crop[1] + 1]:
                report(name, False, "sips 가 읽은 크기 %s" % dims)
                return
        report(name, True, "%.2fs" % dt)
        return
    g, r = Bmp(got), Bmp(want)
    if (g.w, g.h, g.topdown) != (r.w, r.h, r.topdown):
        report(name, False, "크기 %dx%d(topdown=%s), 기대 %dx%d(topdown=%s)" % (g.w, g.h, g.topdown, r.w, r.h, r.topdown))
        return
    if g.hdr != r.hdr:
        report(name, False, "헤더 다름: %s / %s" % (g.hdr.hex(), r.hdr.hex()))
        return
    diff = [(x, y) for y in range(r.h) for x in range(r.w) if g.rows[y][4 * x : 4 * x + 4] != r.rows[y][4 * x : 4 * x + 4]]
    report(name, False, "픽셀 %d 개 다름, 첫 번째 %s" % (len(diff), diff[:3]))


def apply_ops(src, ops):
    """살아 있는 Op 목록(done)과 다시 실행할 목록(redo)을 그대로 흉내 내고, 결과는 원본에 done 을 차례로 칠한 것."""
    done, redo = [], []
    color = "red"
    i = 0
    while i < len(ops):
        if ops[i] == "undo":
            if done:
                redo.append(done.pop())
            i += 1
        elif ops[i] == "redo":
            if redo:
                done.append(redo.pop())
            i += 1
        elif ops[i] == "color":
            color = ops[i + 1]
            i += 2
        else:
            done.append((ops[i], list(map(int, ops[i + 1 : i + 5])), color))
            redo = []
            i += 5
    img = src.copy()
    for name, args, color in done:
        if name in ("box",):
            img.box(*args, color=color)
        elif name in STROKE_KEYS:
            img.stroke(name, [tuple(args[:2]), tuple(args[2:])], color=color)
        else:
            getattr(img, name if name != "crop" else "crop_")(*args)
    return img


def cases(inp, tag, big=False):
    src = Bmp(open(inp, "rb").read())
    w, h = src.w, src.h
    print("== %s %dx%d s=%d" % (tag, w, h, src.s))
    expect(src.copy(), inp, os.path.join(OUT, tag + "_rt.bmp"), [], tag + " 무편집 왕복")
    if big:
        return
    tests = [
        ("box", ["box", 10, 20, w - 130, h - 60]),
        ("box 거꾸로 끌기", ["box", w - 130, h - 60, 10, 20]),
        ("box 띠보다 작은 네모", ["box", 10, 10, 14, 13]),
        ("box 넓이 0 무시", ["box", 5, 5, 5, 50]),
        ("mosaic", ["mosaic", 50, 40, w - 40, h - 20]),
        ("mosaic 가장자리 블록", ["mosaic", w - 90, h - 70, w - 1, h - 1]),
        ("mosaic 좌표 넘침", ["mosaic", w - 30, h - 30, w + 50, h + 50]),
        ("box 뒤 mosaic", ["box", 20, 20, 300, 150, "mosaic", 100, 60, 250, 200]),
        ("undo 하나 = 무편집", ["box", 20, 20, 300, 150, "undo"]),
        ("두 번 편집 뒤 undo = 첫 편집", ["box", 20, 20, 300, 150, "mosaic", 100, 60, 250, 200, "undo"]),
        ("빈 undo 무시", ["undo", "box", 10, 20, 200, 150]),
        ("crop", ["crop", 30, 40, w - 50, h - 20]),
        ("crop 거꾸로 끌기", ["crop", w - 50, h - 20, 30, 40]),
        ("crop 가장자리 넘침", ["crop", w - 100, h - 80, w + 50, h + 50]),
        ("crop 넓이 0 무시", ["crop", 5, 5, 5, 50]),
        ("crop 뒤 box (전체 그림에 그림)", ["crop", 30, 40, w - 50, h - 20, "box", 10, 10, w - 10, h - 10]),
        ("box 뒤 crop", ["box", 20, 20, 300, 150, "crop", 100, 60, 250, 140]),
        ("crop 두 번 = 마지막 crop", ["crop", 10, 10, 200, 150, "crop", 50, 50, 120, 100]),
        ("crop 뒤 undo = 무편집", ["crop", 30, 40, w - 50, h - 20, "undo"]),
        ("box, crop 뒤 undo = box 만", ["box", 20, 20, 300, 150, "crop", 100, 60, 250, 140, "undo"]),
        ("undo 뒤 redo = 편집 그대로", ["box", 20, 20, 300, 150, "mosaic", 100, 60, 250, 200, "undo", "redo"]),
        ("undo 둘 뒤 redo 하나", ["box", 20, 20, 300, 150, "mosaic", 100, 60, 250, 200, "undo", "undo", "redo"]),
        ("undo 뒤 새 편집이면 redo 없음", ["box", 20, 20, 300, 150, "undo", "mosaic", 100, 60, 250, 200, "redo"]),
        ("빈 redo 무시", ["redo", "box", 10, 20, 200, 150]),
    ]
    noop = {"box 넓이 0 무시", "undo 하나 = 무편집", "crop 넓이 0 무시", "crop 뒤 undo = 무편집"}
    for name, ops in tests:
        ref = apply_ops(src.copy(), [str(o) for o in ops])
        # 기준 결과가 원본과 달라야 "아무것도 안 하는" 구현이 통과하지 못한다
        changed = ref.tobytes() != src.tobytes()
        if changed != (name not in noop):
            # 실제 화면 캡처는 그 자리가 한 색이면 편집해도 그대로라 판정할 수 없다
            assert tag != "synth", "기준 구현이 %s 에서 그림을 바꾸지 않았다" % name
            print("SKIP %s %s (그 영역이 한 색이라 판정 불가)" % (tag, name))
            continue
        expect(ref, inp, os.path.join(OUT, tag + "_edit.bmp"), ops, tag + " " + name)


def expect_error(mode, inp, args, name, timeout=10):
    """shot 이 몇 초 안에 0 아닌 코드로 끝나고 한국어 메시지를 내며 결과 파일을 쓰지 않아야 한다."""
    out = os.path.join(OUT, "err_out.bmp")
    ok, dt, r = run_shot(mode, inp, out, args, timeout=timeout)
    if r is None:
        report(name, False, "%d초 안에 끝나지 않음" % timeout)
    elif ok or os.path.exists(out):
        report(name, False, "실패해야 하는데 코드 %d, 결과 파일 %s" % (r.returncode, "있음" if os.path.exists(out) else "없음"))
    elif not re.search("[가-힣]", r.stderr + r.stdout):
        report(name, False, "한국어 메시지가 없음: %r" % (r.stderr + r.stdout)[:120])
    else:
        report(name, True, "%.2fs %s" % (dt, (r.stderr + r.stdout).strip().splitlines()[0][:60]))


def replay_cases(inp):
    """창 루프와 같은 상태 기계를 --replay 로 돌린다. 좌표는 화면 픽셀이라 배율 2 변환까지 검사한다."""
    src = Bmp(open(inp, "rb").read())
    w, h, s = src.w, src.h, src.s
    W, H = (w + s - 1) // s, (h + s - 1) // s  # 창 크기 = 화면 픽셀 수
    print("== replay %dx%d s=%d 창 %dx%d" % (w, h, s, W, H))
    assert s == 2, "replay 검사는 배율 2 그림이어야 끝 좌표 변환을 잡는다"
    out = os.path.join(OUT, "replay.bmp")
    out2 = os.path.join(OUT, "replay_edit.bmp")
    e = lambda x: x * s + s - 1  # 화면 픽셀의 마지막 원본 픽셀
    box = ["box", 10, 20, e(20), e(30)]
    tests = [
        ("crop 끝까지 끌기 = 전체 그림", "key 51 down 0 0 move 3 3 up %d %d key 13" % (W - 1, H - 1), ["crop", 0, 0, w - 1, h - 1]),
        ("box", "down 5 10 move 7 7 up 20 30 key 13", box),
        ("box 거꾸로 끌기", "down 20 30 up 5 10 key 13", box),
        ("키 2 mosaic", "key 50 down 5 10 up 40 50 key 13", ["mosaic", 10, 20, e(40), e(50)]),
        ("키 3 crop 뒤 키 1 box", "key 51 down 10 10 up 100 80 key 49 down 20 20 up 60 60 key 13", ["crop", 20, 20, e(100), e(80), "box", 40, 40, e(60), e(60)]),
        ("z 되돌리기 = 무편집", "down 5 10 up 20 30 key 122 key 13", []),
        ("ㅋ(12619) 되돌리기 = 무편집", "down 5 10 up 20 30 key 12619 key 13", []),
        ("y 다시 실행", "down 5 10 up 20 30 key 122 key 121 key 13", box),
        ("ㅛ(12635) 다시 실행", "down 5 10 up 20 30 key 122 key 12635 key 13", box),
        ("끌기 도중 Enter 는 확정된 것만", "down 5 10 up 20 30 down 40 40 move 60 60 key 13", box),
        ("끌기 도중 되돌리기는 끌기를 버림", "down 5 10 up 20 30 down 40 40 key 122 up 60 60 key 13", []),
        ("넓이 0 끌기 무시", "down 5 5 up 5 20 key 13", []),
        ("Shift 눌렀다 떼도 그대로", "keydown 65592 keyup 65592 keydown 65596 keyup 65596 key 13", []),
        ("편집 뒤 Esc 한 번은 닫지 않음 (Enter 가 복사)", "down 5 10 up 20 30 key 27 key 13", box),
        ("편집 뒤 Esc 누른 채 반복은 두 번이 아님", "down 5 10 up 20 30 keydown 27 keydown 27 keydown 27 keyup 27 key 13", box),
        ("Esc 사이에 다른 키면 다시 경고", "down 5 10 up 20 30 key 27 key 49 key 27 key 13", box),
        ("Esc 사이에 마우스 움직임은 상관없음", "down 5 10 up 20 30 key 27 move 50 50 key 13", box),
        ("복사 실패면 창이 남고 다음 Enter 가 복사", "down 5 10 up 20 30 copyfail key 13 key 13", box),
    ]
    for name, script, ops in tests:
        ref = apply_ops(src, [str(o) for o in ops])
        expect(ref, inp, out, script.split(), "replay " + name, mode="--replay")
        # 같은 편집을 --edit 로 해도 바이트까지 같아야 한다 (창과 창 없는 길이 한 코드)
        if ops and os.path.exists(out):
            run_shot("--edit", inp, out2, ops)
            report("replay " + name + " = --edit", os.path.exists(out2) and open(out, "rb").read() == open(out2, "rb").read())
    nowrite = [
        ("close 는 쓰지 않음", "down 5 10 up 20 30 close key 13"),
        ("편집 없으면 Esc 한 번에 닫힘", "key 27 key 13"),
        ("편집 뒤 Esc 두 번이면 닫힘", "down 5 10 up 20 30 key 27 key 27 key 13"),
        ("되돌려서 처음과 같아도 Esc 는 두 번", "down 5 10 up 20 30 key 122 key 27 key 27 key 13"),
        ("이벤트가 끝나면 쓰지 않음", "down 5 10 up 20 30"),
    ]
    for name, script in nowrite:
        ok, dt, r = run_shot("--replay", inp, out, script.split())
        report("replay " + name, ok and not os.path.exists(out))
    names = ["네모", "모자이크", "자르기", "펜", "형광펜", "직선", "화살표", "원", "지우개"]
    ok, dt, r = run_shot("--replay", inp, out, "key 50 key 51 key 52 key 53 key 54 key 55 key 56 key 57 key 49".split())
    titles = [l for l in (r.stdout if r else "").splitlines() if l.startswith("TITLE ")]
    marks = [[n for n in names if "] " + n + " ✓" in t] for t in titles]
    report("replay 도구 키 1~9 마다 TITLE 에 그 도구만 ✓ (처음 제목은 네모)", ok and marks == [[n] for n in [names[0]] + names[1:] + [names[0]]], str(marks))
    report("replay 첫 TITLE 은 한국어 도구 안내 그대로 (색 빨강)", bool(titles) and titles[0] == TITLE0, repr(titles[:1]))
    ok, dt, r = run_shot("--replay", inp, out, "down 5 10 up 20 30 key 27 key 49".split())
    titles = [l for l in (r.stdout if r else "").splitlines() if l.startswith("TITLE ")]
    report("replay 첫 Esc 는 제목으로 경고, 다른 키면 풀림", ok and len(titles) == 3 and "한 번 더" in titles[1] and "한 번 더" not in titles[2], str(titles))
    ok, dt, r = run_shot("--replay", inp, out, "down 5 10 up 20 30 copyfail key 13".split())
    report("replay 복사 실패를 알림", ok and not os.path.exists(out) and "복사 실패" in (r.stdout + r.stderr))
    lines = (r.stdout if r else "").splitlines()
    titles = [l for l in lines if l.startswith("TITLE ")]
    report("replay 복사 전에 TITLE 복사 중… (복사 실패 줄보다 앞), 실패 뒤 보통 제목으로 되돌림", ok and titles == [TITLE0, BUSY, TITLE0] and lines.index(BUSY) < lines.index("복사 실패 (시험용 예약)"), str(titles))
    ok, dt, r = run_shot("--replay", inp, out, "down 5 10 up 20 30 key 13".split())
    titles = [l for l in (r.stdout if r else "").splitlines() if l.startswith("TITLE ")]
    report("replay 복사 성공도 TITLE 복사 중… 을 한 번 찍고 결과를 씀", ok and os.path.exists(out) and titles.count(BUSY) == 1, str(titles))
    for name, script in [("숫자 아닌 좌표", "down 1 2 up 3 x"), ("모르는 이벤트", "frob"), ("인자 모자람", "down 1")]:
        expect_error("--replay", inp, script.split(), "replay 거부: " + name)


def wobble(n, x0, y0, w, h, seed):
    """n 개의 점을 지나는 구불구불한 길 (화면 좌표, 그림 안)."""
    import random
    rnd = random.Random(seed)
    pts, x, y = [], x0, y0
    for i in range(n):
        pts.append((x, y))
        x = min(max(x + rnd.randint(-4, 6), 0), w - 1)
        y = min(max(y + rnd.randint(-5, 5), 0), h - 1)
    return pts


def stroke_cases(inp):
    """새 도구 5개를 --replay (누름·끌기·뗌) 로 돌려 파이썬 기준 구현과 바이트까지 비교한다 (정수 기하라 허용 오차 0)."""
    src = Bmp(open(inp, "rb").read())
    w, h, s = src.w, src.h, src.s
    W, H = (w + s - 1) // s, (h + s - 1) // s
    print("== 획 도구 replay %dx%d s=%d" % (w, h, s))
    out = os.path.join(OUT, "stroke.bmp")

    def script(tool, pts):
        mid = " ".join("move %d %d" % p for p in pts[1:-1])
        return ("key %d down %d %d %s up %d %d" % ((STROKE_KEYS[tool],) + pts[0] + (mid,) + pts[-1])).replace("  ", " ")

    def enter(scr):
        return (scr + " key 13").split()

    def full(pts):
        # 창 밖(패널 쪽) 좌표는 경계가 뷰 가장자리로 자른 뒤 원본으로 바꾼다
        cl = lambda p: (min(p[0], W - 1), min(p[1], H - 1))
        return [(x * s, y * s) for x, y in map(cl, pts[:-1])] + [(cl(pts[-1])[0] * s + s - 1, cl(pts[-1])[1] * s + s - 1)]

    tests = [
        ("pen 5점", "pen", [(10, 10), (30, 40), (60, 20), (90, 60), (120, 30)]),
        ("pen 300점", "pen", wobble(300, 20, 30, W, H, 1)),
        ("pen 클릭 = 점", "pen", [(5, 5), (5, 5)]),
        ("pen 그림 밖으로 (좌표 넘침은 가장자리로)", "pen", [(W - 20, H - 10), (W + 30, H + 20), (W - 5, H - 40)]),
        ("high 5점", "high", [(20, 80), (60, 90), (100, 70), (150, 85), (120, 60)]),
        ("high 300점 (스스로 겹침)", "high", wobble(300, 40, 50, W, H, 2)),
        ("high 자기 교차는 한 번만 섞임", "high", [(20, 20), (120, 90), (120, 20), (20, 90)]),
        ("line", "line", [(10, 100), (150, 100)]),
        ("line 비스듬히 거꾸로", "line", [(150, 20), (10, 90)]),
        ("line 세로", "line", [(70, 5), (70, H - 5)]),
        ("arrow", "arrow", [(20, 50), (150, 10)]),
        ("arrow 거꾸로", "arrow", [(150, 10), (20, 50)]),
        ("arrow 짧은 것 (머리가 축보다 김)", "arrow", [(50, 50), (54, 53)]),
        ("arrow 머리가 그림 밖으로 (잘림)", "arrow", [(60, 60), (W - 1, 2)]),
        ("ellipse", "ellipse", [(100, 30), (160, 90)]),
        ("ellipse 거꾸로 끌기", "ellipse", [(160, 90), (100, 30)]),
        ("ellipse 납작한 것", "ellipse", [(10, 10), (150, 14)]),
        ("ellipse 그림 전체", "ellipse", [(0, 0), (W - 1, H - 1)]),
    ]
    for name, tool, pts in tests:
        ref = src.copy()
        ref.stroke(tool, full(pts))
        assert ref.tobytes() != src.tobytes(), "기준 구현이 %s 에서 그림을 바꾸지 않았다" % name
        expect(ref, inp, out, enter(script(tool, pts)), "획 %s" % name, mode="--replay")
    # 기준 구현 자체 점검: 교차점이 노랑과 한 번 섞인 값인지 (두 번 섞이면 더 노랗다)
    ref = src.copy()
    ref.stroke("high", full([(20, 20), (120, 90), (120, 20), (20, 90)]))
    cx, cy = 70 * s, 55 * s
    under = src.rows[cy][4 * cx : 4 * cx + 3]
    once = bytes([(under[i] * 3 + YELLOW[i] * 2) // 5 for i in range(3)])
    report("기준 형광펜: 교차점 (%d, %d) 은 한 번 섞인 값" % (cx, cy), bytes(ref.rows[cy][4 * cx : 4 * cx + 3]) == once)
    ref = src.copy()
    for tool, pts in [("pen", [(10, 10), (30, 40), (60, 20)]), ("line", [(10, 100), (150, 100)])]:
        ref.stroke(tool, full(pts))
    combo = " ".join([script("pen", [(10, 10), (30, 40), (60, 20)]), script("line", [(10, 100), (150, 100)]), script("ellipse", [(100, 30), (160, 90)]), "key 122", script("arrow", [(20, 50), (150, 10)]), "key 122", "key 121", "key 122"])
    expect(ref, inp, out, enter(combo), "획 undo·redo: pen, line, ellipse, undo, arrow, undo, redo, undo = pen + line", mode="--replay")
    for name, scr in [("line 제자리 클릭 무시", "key 54 down 5 5 up 5 5"), ("arrow 제자리 클릭 무시", "key 55 down 9 9 up 9 9"), ("ellipse 넓이 0 무시", "key 56 down 5 5 up 5 20"), ("ellipse 높이 0 무시", "key 56 down 5 5 up 40 5")]:
        ok, dt, r = run_shot("--replay", inp, out, (scr + " key 13").split())
        saves = [l for l in (r.stdout if r else "").splitlines() if l.startswith("SAVE ")]
        report("획 " + name + " (Op 없음, 저장 없음, 그림 그대로)", ok and not saves and os.path.exists(out) and open(out, "rb").read() == src.tobytes(), str(saves))
    ok, dt, r = run_shot("--replay", inp, out, "key 54 down 5 5 move 9 9 up 5 5 key 13".split())
    saves = [l for l in (r.stdout if r else "").splitlines() if l.startswith("SAVE ")]
    report("획 line 은 움직였어도 뗀 곳이 누른 곳이면 무시", ok and not saves and open(out, "rb").read() == src.tobytes())


PANEL_W, PANEL_MIN_H, TITLE_H = 224, 528, 40
PANEL_BG = (0x33, 0x33, 0x33, 0xFF)  # shot.bend 의 Panel.bg
TILE_BG = (0x44, 0x44, 0x44, 0xFF)  # shot.bend 의 Tile.gray (목록 칸 바탕·자리 표시)
BUSY = "TITLE 복사 중…"  # Enter 로 복사하는 동안의 제목 (끝나면 보통 제목으로 돌아온다)
TITLE0 = "TITLE Bend 캡처 · [1] 네모 ✓  [2] 모자이크  [3] 자르기  [4] 펜  [5] 형광펜  [6] 직선  [7] 화살표  [8] 원  [9] 지우개  색 빨강  Z 되돌리기  Y 다시 실행  Enter 복사  Esc 닫기"


TOOLS = ["box", "mosaic", "crop", "pen", "high", "line", "arrow", "ellipse", "erase"]
TOOL_KNAMES = dict(zip(TOOLS, ["네모", "모자이크", "자르기", "펜", "형광펜", "직선", "화살표", "원", "지우개"]))
COLOR_KNAMES = {"red": "빨강", "yellow": "노랑", "green": "초록", "blue": "파랑", "black": "검정", "white": "흰색"}


def panel_buttons(vw):
    """shot.bend 의 Panel.buttons 와 같은 표: (x, y, w, h, 행동). 도구 60×60 3열 간격 8, 색 28×28 한 줄."""
    bs = [(vw + 16 + (i % 3) * 68, 16 + (i // 3) * 68, 60, 60, ("tool", name)) for i, name in enumerate(TOOLS)]
    bs += [(vw + 16 + i * 32, 228, 28, 28, ("color", name)) for i, name in enumerate(COLORS)]
    return bs


def panel_cases(inp):
    """오른쪽 패널: 단추 표대로 눌러 도구·색이 바뀌는지 (TITLE), 빈 자리는 아무 일 없는지, 창 그림에 단추가 그려지는지."""
    src = Bmp(open(inp, "rb").read())
    w, h, s = src.w, src.h, src.s
    vw, vh = (w + s - 1) // s, (h + s - 1) // s
    print("== 패널 %dx%d s=%d 뷰 %dx%d 창 %dx%d" % (w, h, s, vw, vh, vw + PANEL_W, max(vh, PANEL_MIN_H)))
    out = os.path.join(OUT, "panel.bmp")
    bs = panel_buttons(vw)
    center = lambda b: (b[0] + b[2] // 2, b[1] + b[3] // 2)
    click = lambda x, y: "down %d %d up %d %d" % (x, y, x, y)

    def titles_of(script, env=ENV):
        ok, dt, r = run_shot("--replay", inp, out, script.split())
        return ok, [l for l in (r.stdout if r else "").splitlines() if l.startswith("TITLE ")]

    tools = [b for b in bs if b[4][0] == "tool"]
    script = " ".join(click(*center(b)) for b in tools[1:] + tools[:1])
    ok, titles = titles_of(script)
    marks = [[n for n in TOOL_KNAMES.values() if "] " + n + " ✓" in t] for t in titles]
    report("패널 도구 단추 9개를 차례로 누르면 TITLE 에 그 도구만 ✓", ok and marks == [[TOOL_KNAMES["box"]]] + [[TOOL_KNAMES[b[4][1]]] for b in tools[1:] + tools[:1]], str(marks))
    colors = [b for b in bs if b[4][0] == "color"]
    script = " ".join(click(*center(b)) for b in colors[1:] + colors[:1])
    ok, titles = titles_of(script)
    names = [[n for n in COLOR_KNAMES.values() if "색 " + n in t] for t in titles]
    report("패널 색 단추 6개를 차례로 누르면 TITLE 의 색 이름이 바뀜", ok and names == [["빨강"]] + [[COLOR_KNAMES[b[4][1]]] for b in colors[1:] + colors[:1]], str(names))
    pen = tools[3]
    ok, titles = titles_of(" ".join([click(pen[0], pen[1]), click(tools[0][0], tools[0][1]), click(pen[0] + 59, pen[1] + 59), click(tools[0][0], tools[0][1]), click(pen[0] + 60, pen[1]), click(pen[0], pen[1] + 60)]))
    marks = [[n for n in TOOL_KNAMES.values() if "] " + n + " ✓" in t] for t in titles]
    report("단추 가장자리 (x, y)·(x+59, y+59) 는 맞고 (x+60, y)·(x, y+60) 은 빗나감 (표 그대로)", ok and marks == [["네모"], ["펜"], ["네모"], ["펜"], ["네모"]], str(marks))
    ok, titles = titles_of(" ".join([click(vw + 5, 5), click(vw + 100, 265), click(vw + PANEL_W - 1, PANEL_MIN_H - 1), click(vw + 10, 300), "key 13"]))
    report("빈 패널 자리를 눌러도 아무 일 없음 (TITLE 그대로, Op 없음)", ok and all(t in (TITLE0, BUSY) for t in titles) and os.path.exists(out) and open(out, "rb").read() == src.tobytes(), str(titles))
    blue = [b for b in colors if b[4][1] == "blue"][0]
    e = lambda v: v * s + s - 1
    ref = src.copy()
    ref.box(10, 20, e(60), e(50), color="blue")
    expect(ref, inp, out, (click(*center(blue)) + " down 5 10 up 60 50 key 13").split(), "패널에서 파랑을 고르고 그린 네모는 파랑", mode="--replay")
    ref = src.copy()
    ref.stroke("pen", [(10, 10), (e(40), e(30))], color="green")
    green = [b for b in colors if b[4][1] == "green"][0]
    expect(ref, inp, out, (click(*center(green)) + " " + click(*center(pen)) + " down 5 5 up 40 30 key 13").split(), "패널에서 초록과 펜을 고르고 그린 획은 초록 펜", mode="--replay")
    # 끌기 도중 단추를 누르면 끌기가 버려진다 (APick/AColor 는 끌기를 끝낸다)
    ok, dt, r = run_shot("--replay", inp, out, ("down 5 10 move 20 20 " + click(*center(blue)) + " key 13").split())
    saves = [l for l in (r.stdout if r else "").splitlines() if l.startswith("SAVE ")]
    report("끌기 도중 패널 단추를 누르면 끌던 것은 버려짐 (Op 없음)", ok and not saves and open(out, "rb").read() == src.tobytes())
    # 창 그림: 단추 자리의 색 (색 단추는 그 색으로 채워지고, 도구 단추 바탕은 패널보다 밝다)
    frame = os.path.join(OUT, "panel_frame.bmp")
    if os.path.exists(frame):
        os.remove(frame)
    r = subprocess.run([SHOT, "--replay", inp, out, "key", "13"], capture_output=True, text=True, env=dict(ENV, BENDSHOT_FRAME=frame), timeout=120)
    fr = Bmp(open(frame, "rb").read()) if os.path.exists(frame) else None
    px = lambda x, y: tuple(fr.rows[y][4 * x : 4 * x + 4])
    report("BENDSHOT_FRAME 이 창 크기(뷰 + 패널)의 그림을 씀", fr is not None and (fr.w, fr.h) == (vw + PANEL_W, max(vh, PANEL_MIN_H)), str((fr.w, fr.h) if fr else r.stderr[-80:]))
    if fr is not None:
        report("창 그림의 색 단추는 표의 자리에 그 색으로", all(px(*center(b)) == COLORS[b[4][1]] for b in colors) and px(vw + 16 + 28, 228 + 14) != COLORS["red"])
        bg = px(vw + 5, 5)
        report("도구 단추 바탕은 패널 바탕과 다르고, 단추 사이는 패널 바탕", px(tools[1][0] + 3, tools[1][1] + 3) != bg and px(tools[1][0] - 4, tools[1][1] + 30) == bg and px(5, vh + 5) == bg)
        report("켜진 도구(네모)만 흰 테", px(tools[0][0] - 2, tools[0][1] + 30) == COLORS["white"] and px(tools[1][0] - 2, tools[1][1] + 30) == bg)
        report("뷰 자리는 원본을 줄인 그림 (왼쪽 위 픽셀이 패널 바탕이 아님)", px(0, 0) != bg and px(vw - 1, vh - 1) != bg)


def erase_cases(inp):
    """지우개(키 9): 끈 길이 닿은 보이는 Op 만 지운다. 기준은 남는 Op 를 파이썬 기준 구현으로 그린 것 (바이트 같음)."""
    src = Bmp(open(inp, "rb").read())
    w, h, s = src.w, src.h, src.s
    print("== 지우개 %dx%d s=%d" % (w, h, s))
    out = os.path.join(OUT, "erase.bmp")
    e = lambda v: v * s + s - 1
    drag = lambda tool, a, b: "key %d down %d %d up %d %d" % (STROKE_KEYS.get(tool, {"box": 49, "mosaic": 50, "crop": 51}.get(tool)), a[0], a[1], b[0], b[1])
    pen_a = ("pen", (10, 10), (60, 10))
    pen_b = ("pen", (10, 60), (60, 60))
    line_c = ("line", (80, 20), (150, 20))
    box_d = ("box", (90, 40), (150, 90))
    ell_e = ("ellipse", (20, 80), (70, 105))

    def ref_of(keep):
        img = src.copy()
        for tool, a, b in keep:
            if tool == "box":
                img.box(a[0] * s, a[1] * s, e(b[0]), e(b[1]))
            elif tool == "mosaic":
                img.mosaic(a[0] * s, a[1] * s, e(b[0]), e(b[1]))
            elif tool == "crop":
                img.crop_(a[0] * s, a[1] * s, e(b[0]), e(b[1]))
            else:
                img.stroke(tool, [(a[0] * s, a[1] * s), (e(b[0]), e(b[1]))])
        return img

    def run(name, script, keep, want_saves=None):
        ref = ref_of(keep)
        ok, dt, r = run_shot("--replay", inp, out, (script + " key 13").split())
        saves = [l for l in (r.stdout if r else "").splitlines() if l.startswith("SAVE ")]
        if want_saves is not None and len(saves) != want_saves:
            report("지우개 " + name, False, "저장 %d번, 기대 %d번" % (len(saves), want_saves))
            return
        if not ok or not os.path.exists(out):
            report("지우개 " + name, False, "shot 실패 " + (r.stderr if r else "")[-120:])
            return
        got = open(out, "rb").read()
        if got == ref.tobytes():
            report("지우개 " + name, True, "%.2fs" % dt)
        else:
            g = Bmp(got)
            diff = [(x, y) for y in range(ref.h) for x in range(ref.w) if g.rows[y][4 * x : 4 * x + 4] != ref.rows[y][4 * x : 4 * x + 4]]
            report("지우개 " + name, False, "픽셀 %d 개 다름, 첫 번째 %s" % (len(diff), diff[:3]))

    two = drag(*pen_a) + " " + drag(*pen_b)
    across_a = "key 57 down 30 3 up 30 17"
    run("두 획 중 위쪽 하나만 (가로질러)", two + " " + across_a, [pen_b], 3)
    run("닿는 게 없으면 Op 없음 (저장 없음)", two + " key 57 down 30 30 up 60 35", [pen_a, pen_b], 2)
    many = " ".join([drag(*pen_a), drag(*line_c), drag(*box_d), drag(*ell_e)])
    run("한 번에 여러 개 (펜·직선·네모 띠), 원은 남음", many + " key 57 down 5 12 move 100 18 up 100 60", [ell_e], 5)
    run("되돌리기로 지운 것이 돌아옴", two + " " + across_a + " key 122", [pen_a, pen_b], 4)
    run("다시 실행으로 다시 지워짐", two + " " + across_a + " key 122 key 121", [pen_b], 5)
    run("앞선 지우개를 되돌린 뒤 다른 것을 지움 (옛 지우개는 버려짐)", two + " " + across_a + " key 122 key 57 down 30 53 up 30 67", [pen_a], 5)
    run("자르기는 지우지 않음 (안의 펜만 지워지고 자르기는 남음)", drag("crop", (5, 5), (100, 80)) + " " + drag(*pen_a) + " " + across_a, [("crop", (5, 5), (100, 80))], 3)
    run("모자이크는 영역 안을 지나면 지워짐", drag("mosaic", (20, 20), (80, 70)) + " " + drag(*pen_b) + " key 57 down 50 40 up 55 45", [pen_b], 3)
    run("모자이크 영역 밖 (여유 4px 넘게) 은 닿지 않음", drag("mosaic", (20, 20), (80, 70)) + " key 57 down 90 40 up 95 45", [("mosaic", (20, 20), (80, 70))], 1)
    run("형광펜은 덮은 띠 안을 지나면 지워짐", drag("high", (10, 40), (100, 40)) + " key 57 down 50 44 up 52 45", [], 2)
    run("가는 직선 옆 4px 는 닿음 (굵기/2 + 4px)", drag(*line_c) + " key 57 down 90 24 up 140 24", [], 2)
    run("가는 직선 옆 12px 는 닿지 않음", drag(*line_c) + " key 57 down 90 32 up 140 32", [line_c], 1)
    run("지우개 클릭(한 점) 도 닿으면 지움", two + " key 57 down 30 10 up 30 10", [pen_b], 3)
    run("지운 뒤 같은 자리에 새로 그리면 새 것은 남음", two + " " + across_a + " " + drag(*pen_a), [pen_b, pen_a], 4)
    run("두 지우개: 첫 지우개가 지운 것은 둘째 지우개와 무관", two + " " + across_a + " key 57 down 30 53 up 30 67", [], 4)
    ok, dt, r = run_shot("--replay", inp, out, (two + " " + across_a + " key 13").split())
    ok2, dt2, r2 = run_shot("--replay", inp, out, (two + " " + across_a).split())
    report("지우개 끌기 도중 Enter 없이 끝나도 쓰지 않음 (Enter 는 확정된 것만 복사)", ok2 and not os.path.exists(out))


def color_cases(inp):
    """색 고르기(--edit color 이름): 네모·펜·직선·화살표·원을 색마다 기준 구현과 바이트까지 비교, 형광펜은 빨강→노랑, 그 밖은 그 색을 섞는다."""
    src = Bmp(open(inp, "rb").read())
    w, h = src.w, src.h
    print("== 색 %dx%d s=%d" % (w, h, src.s))
    out = os.path.join(OUT, "color.bmp")
    shapes = [("box", [10, 20, 120, 90]), ("pen", [10, 10, 90, 60]), ("line", [10, 100, 150, 100]), ("arrow", [20, 50, 150, 10]), ("ellipse", [100, 30, 160, 90])]
    for color in COLORS:
        for tool, args in shapes:
            ops = ["color", color, tool] + args
            ref = apply_ops(src, [str(o) for o in ops])
            assert ref.tobytes() != src.tobytes()
            expect(ref, inp, out, ops, "색 %s %s" % (color, tool))
    for color, want in [("red", "노랑(기본 빨강은 노랑으로)"), ("blue", "파랑 섞기"), ("green", "초록 섞기")]:
        ops = ["color", color, "high", 20, 80, 150, 85]
        ref = apply_ops(src, [str(o) for o in ops])
        expect(ref, inp, out, ops, "형광펜 %s → %s" % (color, want))
    ref = apply_ops(src, "color blue box 10 20 120 90 color green pen 10 10 90 60 undo redo".split())
    expect(ref, inp, out, "color blue box 10 20 120 90 color green pen 10 10 90 60 undo redo".split(), "색은 Op 에 실려 되돌리기·다시 실행 뒤에도 그대로")
    expect_error("--edit", inp, ["color", "pink", "box", 1, 1, 50, 50], "거부: 모르는 색")
    ok, dt, r = run_shot("--replay", inp, out, "key 53 key 13".split())
    titles = [l for l in (r.stdout if r else "").splitlines() if l.startswith("TITLE ")]
    report("제목에 현재 색 이름 (색 빨강)", ok and all("색 빨강" in t for t in titles if t != BUSY) and len(titles) >= 2, str(titles[-1:]))


def fit_cases():
    """창 맞추기: BENDSHOT_SCREEN 으로 화면 크기를 흉내 내어 고른 표시 배율 d 와 창 크기(FIT 줄), d=4 의 마우스 변환을 검사한다."""
    print("== 창 맞추기 (BENDSHOT_SCREEN)")
    big = os.path.join(OUT, "fit_5120.bmp")
    mid = os.path.join(OUT, "fit_2400.bmp")
    small = os.path.join(OUT, "fit_600.bmp")
    synth_fast(big, 5120, 2880, 5669)
    synth_fast(mid, 2400, 1600, 5669)
    synth_fast(small, 600, 400, 2835)
    out = os.path.join(OUT, "fit.bmp")
    cases = [
        ("5120x2880 s=2, 화면 2560x1440 → d=4 (2560+패널이 안 들어감), 창 1504x720", big, "2560x1440", "FIT 4 1504 720"),
        ("2400x1600 s=2, 화면 2560x1440 → d=2, 창 1424x800", mid, "2560x1440", "FIT 2 1424 800"),
        ("600x400 s=1, 화면 2560x1440 → d=1, 창 824x528 (패널 최소 높이 528)", small, "2560x1440", "FIT 1 824 528"),
        ("2400x1600 s=2, 화면 1280x800 → 너비 때문에 d=4, 창 824x528", mid, "1280x800", "FIT 4 824 528"),
        ("2400x1600 s=2, 화면 2000x700 → 높이(+제목 40) 때문에 d=4", mid, "2000x700", "FIT 4 824 528"),
        ("100x50 s=1 → 창 높이는 패널 최소 528 (목록 두 칸)", None, "2560x1440", "FIT 1 324 528"),
        ("BENDSHOT_SCREEN 없음 → 맞추지 않음 (d=s)", mid, None, "FIT 2 1424 800"),
    ]
    tiny = os.path.join(OUT, "fit_100.bmp")
    synth_fast(tiny, 100, 50, 2835)
    for name, inp, screen, want in cases:
        env = dict(ENV)
        if screen:
            env["BENDSHOT_SCREEN"] = screen
        r = subprocess.run([SHOT, "--replay", inp or tiny, out, "key", "13"], capture_output=True, text=True, env=env, timeout=120)
        fit = [l for l in r.stdout.splitlines() if l.startswith("FIT ")]
        report("창 맞추기 " + name, r.returncode == 0 and fit == [want], str(fit or r.stderr[-80:]))
    env = dict(ENV, BENDSHOT_SCREEN="abc")
    r = subprocess.run([SHOT, "--replay", tiny, out, "key", "13"], capture_output=True, text=True, env=env, timeout=120)
    report("BENDSHOT_SCREEN 이 어긋나면 한국어 경고와 1440×900 으로", r.returncode == 0 and "1440" in r.stderr and re.search("[가-힣]", r.stderr) is not None and "FIT 1 324 528" in r.stdout, r.stderr.strip()[:60])
    # d=4 의 마우스 변환: 뗀 점 (599, 399) 은 원본 (2399, 1599) 이어야 자르기가 그림 전체가 된다
    src = Bmp(open(mid, "rb").read())
    src.d = 4
    ref = src.copy()
    ref.crop_(0, 0, 2399, 1599)
    env = dict(ENV, BENDSHOT_SCREEN="1280x800")
    if os.path.exists(out):
        os.remove(out)
    r = subprocess.run([SHOT, "--replay", mid, out, "key", "51", "down", "0", "0", "up", "599", "399", "key", "13"], capture_output=True, text=True, env=env, timeout=120)
    got = open(out, "rb").read() if os.path.exists(out) else b""
    report("d=4 에서 창 끝 픽셀(599, 399) 까지 자르기 = 그림 전체 (2400x1600)", r.returncode == 0 and got == ref.tobytes(), "%d 바이트, 기대 %d" % (len(got), len(ref.tobytes())))
    ref = src.copy()
    ref.box(1 * 4, 2 * 4, 599 * 4 + 3, 399 * 4 + 3)
    r = subprocess.run([SHOT, "--replay", mid, out, "down", "1", "2", "up", "599", "399", "key", "13"], capture_output=True, text=True, env=env, timeout=120)
    got = open(out, "rb").read() if os.path.exists(out) else b""
    report("d=4 에서 네모 (1,2)→(599,399) 는 원본 (4,8)→(2399,1599) 띠 (d 단위로 맞춤)", r.returncode == 0 and got == ref.tobytes())
    # 패널에서 누르면 그림에 아무 일도 없다 (빈 패널 = ANone)
    r = subprocess.run([SHOT, "--replay", small, out, "down", "610", "300", "up", "610", "300", "key", "13"], capture_output=True, text=True, env=dict(ENV, BENDSHOT_SCREEN="2560x1440"), timeout=120)
    saves = [l for l in r.stdout.splitlines() if l.startswith("SAVE ")]
    report("빈 패널 자리를 눌러도 Op 없음 (저장 없음, 그림 그대로)", r.returncode == 0 and not saves and open(out, "rb").read() == open(small, "rb").read())
    # 그림에서 시작한 끌기가 패널로 나가면 점이 그림 가장자리로 잘린다
    src = Bmp(open(small, "rb").read())
    ref = src.copy()
    ref.box(10, 10, 599, 399)
    r = subprocess.run([SHOT, "--replay", small, out, "down", "10", "10", "move", "700", "399", "up", "800", "399", "key", "13"], capture_output=True, text=True, env=dict(ENV, BENDSHOT_SCREEN="2560x1440"), timeout=120)
    report("그림에서 시작해 패널로 나간 끌기는 그림 가장자리(599, 399)에서 뗀 것", r.returncode == 0 and os.path.exists(out) and open(out, "rb").read() == ref.tobytes())
    for f in (big, mid):
        os.remove(f)


# 공유 상태(봉인 대상) 생성자로 남아도 되는 것: 글자열·Bool·그림. 성능을 재어 정한 집합이다.
HOT_OK = {"Chr", "SCon", "SNil", "WCon", "True", "False", "Pix", "Qua"}


def hot_cases(shot_dir):
    """생성된 C 의 CID_T 표에서 뜨거운(공유 상태라 만들 때마다 봉인하는) 생성자를 읽는다. 봉인은 타입 이름 단위라서,
    목록을 품은 값 하나를 두 소유자에게 넘기면(같은 변수를 두 번 소유로 쓰면) 기본 List 전체가 뜨거워지고
    BMP 바이트 목록 수천만 칸이 모두 느린 길을 탄다."""
    with tempfile.TemporaryDirectory(prefix="bendshot-hot-") as d:
        c = os.path.join(d, "shot.c")
        r = subprocess.run([BEND, "shot.bend", "-o", c], cwd=shot_dir, capture_output=True, text=True, timeout=600)
        src = open(c, encoding="utf-8").read() if r.returncode == 0 and os.path.exists(c) else ""
    names = {int(i): k for k, i in re.findall(r"#define CID_(\w+) (\d+)\n", src)}
    m = re.search(r"CID_T\[\] = \{(.*?)\};", src, re.S)
    ent = re.findall(r"\{ (\d+), (\d+), (\d+) \}", m.group(1)) if m else []
    hot = {names[i] for i, e in enumerate(ent) if e[1] == "1" and i in names}
    report("생성된 C 를 읽음 (뜨거운 생성자 표)", bool(ent), (r.stderr or r.stdout)[-120:] if not ent else "%d 개" % len(hot))
    report("목록이 공유 상태가 아님 (List 의 Con·Nil 이 뜨겁지 않음)", bool(ent) and not hot & {"Con", "Nil"},
           "목록이 공유 상태가 되면 그림 읽기·쓰기가 1.5배 느려진다. 같은 값을 두 소유자에게 넘기는 곳을 "
           "빌려 읽기 → 소유 순서로 바꾸거나 복사하라" if hot & {"Con", "Nil"} else "")
    report("뜨거운 생성자가 허용 목록 안", bool(ent) and hot <= HOT_OK,
           "새로 뜨거워짐: %s. 성능을 재 보고 괜찮을 때만 HOT_OK 에 넣는다" % sorted(hot - HOT_OK)[:12] if hot - HOT_OK else "")


# 셸은 속도 때문에 Ui.out 에 Ui.peek(ui, a) 를 넘긴다. LAWS.bend 의 법칙은 Ui.out(ui, a) 에 관한 것이라
# 이 정리가 PROOF.bend 에 있어야 법칙이 셸에 닿는다 (gen_proof.py 가 만든다).
PEEK_OUT = "def Shell.peek_out(ui: C.Ui, a: C.Act) -> {C.Ui.out(C.Ui.peek(ui, a), a) == C.Ui.out(ui, a) : C.Out}:"


def gate_cases():
    """증명 관문, 규칙 파일 불변, 핵심 상태에 그림 없음."""
    print("== 관문")
    shot_dir = os.path.join(HERE, "..")
    if os.path.exists(BEND):
        r = subprocess.run([BEND, "PROOF.bend"], cwd=shot_dir, capture_output=True, text=True, timeout=600)
        report("증명 관문 bend PROOF.bend = ALL PROOFS CHECK", "ALL PROOFS CHECK" in r.stdout + r.stderr, (r.stdout + r.stderr).strip().splitlines()[-1][:80] if (r.stdout + r.stderr).strip() else "")
    else:
        print("SKIP 증명 관문 (bend 가 없음)")
    if subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], cwd=shot_dir, capture_output=True).returncode == 0:
        r = subprocess.run(["git", "diff", "--quiet", "HEAD", "--", "LAWS.bend"], cwd=shot_dir, capture_output=True)
        report("LAWS.bend 가 HEAD 와 같음 (광섭의 파일, AI 는 고치지 않는다)", r.returncode == 0)
    else:
        print("SKIP LAWS.bend 불변 (git 저장소가 아님)")
    core = open(os.path.join(shot_dir, "core.bend"), encoding="utf-8").read()
    m = re.search(r"^type Ui is Data:\n((?:  .*\n)+)", core, re.M)
    report("core.bend 의 type Ui 에 Image 가 없음 (규칙 6·7 을 구조로)", m is not None and "Image" not in m.group(1))
    if os.path.exists(BEND):
        hot_cases(shot_dir)
    shell = open(os.path.join(shot_dir, "shot.bend"), encoding="utf-8").read()
    proof = open(os.path.join(shot_dir, "PROOF.bend"), encoding="utf-8").read()
    outs = re.findall(r"C\.Ui\.out\((?:C\.Ui\.peek\()?", shell)
    ok = PEEK_OUT in proof and bool(outs) and all(o.endswith("C.Ui.peek(") for o in outs)
    report("셸의 C.Ui.out 호출이 모두 C.Ui.peek 를 거치고 PROOF.bend 가 Shell.peek_out 을 증명함", ok,
           "" if ok else "셸이 쓰는 빠른 길(Ui.peek)이 규칙의 Ui.out 과 같다는 증명이 빠졌습니다")
    # 캡처는 검사에서 돌리지 않으므로 (클립보드·실제 캐시) 규칙 9 가 셸에 닿는지는 구조로 본다
    ok = re.search(r'"/bin/cp"[^\n]*last\.png', shell) is None
    report("셸이 last.png 사본을 쓰지 않음 (지운 캡처의 원본이 보관 밖에 남지 않게)", ok)
    ok = "C.Cap.verdict(ran, found)" in shell and '"display"' not in shell
    report("셸의 캡처 판정은 규칙 9 의 C.Cap.verdict 하나 (셸이 따로 고르는 판정 없음)", ok,
           "" if ok else "셸이 screencapture 결과를 C.Cap.verdict 없이 직접 판정합니다")
    shipped = ["shot.bend", "core.bend", "app/main.swift", "build.sh", "dist/build.sh", "dist/release.sh"]
    bad = [f for f in shipped if "/Users/" in open(os.path.join(shot_dir, f), encoding="utf-8").read()]
    report("배포되는 소스에 사용자 폴더 고정 경로 없음 (번들 경로는 Bundle.main, 캐시는 HOME 에서)", not bad, ", ".join(bad))
    m = re.search(r"^def Ell.tab\(\) -> List<&2, U32>:\n  \[\n((?:   .*\n)+)  \]", shell, re.M)
    tab = [int(v) for v in re.findall(r"\d+", m.group(1))] if m else None
    report("shot.bend 의 원 256각형 표 = 기준 구현의 표", tab == ell_table(), "%s개" % (len(tab) if tab else None))


def png_from_bmp(bmp, png):
    r = subprocess.run(["/usr/bin/sips", "-s", "format", "png", bmp, "--out", png], capture_output=True, text=True)
    assert r.returncode == 0, r.stderr


def storage_cases(inp):
    """가짜 HOME 에 캡처 폴더를 만들어 자동 저장·다시 열기·망가진 기록·보관 한도를 검사한다."""
    print("== 보관 (가짜 HOME)")
    home = tempfile.mkdtemp(prefix="bendshot-home-")
    try:
        caps = os.path.join(home, "Library", "Caches", "BendShot", "captures")
        cap = os.path.join(caps, "1000000000001")
        os.makedirs(cap)
        orig = os.path.join(cap, "orig.png")
        png_from_bmp(inp, orig)
        orig_bytes = open(orig, "rb").read()
        base = os.path.join(OUT, "store_base.bmp")
        r = subprocess.run(["/usr/bin/sips", "-s", "format", "bmp", orig, "--out", base], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        env = dict(ENV, HOME=home)

        def last(out, script):
            if os.path.exists(out):
                os.remove(out)
            return subprocess.run([SHOT, "--replay-last", out] + script.split(), capture_output=True, text=True, timeout=120, env=env)

        ops = os.path.join(cap, "ops.txt")
        out_a = os.path.join(OUT, "store_a.bmp")
        r = last(out_a, "down 5 10 up 20 30 key 50 down 30 30 up 60 60 key 122")
        text = open(ops, encoding="utf-8").read() if os.path.exists(ops) else ""
        lines = text.splitlines()
        report("편집마다 ops.txt 자동 저장 (Enter 없이 끝나도 남음)", r.returncode == 0 and len(lines) == 5 and lines[0] == "bendshot-ops 1" and lines[1] == "done 1" and lines[2].startswith("box red 2 ") and lines[3] == "redo 1" and lines[4].startswith("mosaic red 2 "), repr(text[:120]))
        report("자동 저장은 임시 파일을 남기지 않음", not os.path.exists(ops + ".tmp"))
        r = last(out_a, "key 13")
        out_b = os.path.join(OUT, "store_b.bmp")
        r2 = subprocess.run([SHOT, "--replay", base, out_b, "down", "5", "10", "up", "20", "30", "key", "13"], capture_output=True, text=True, env=ENV)
        report("다시 열면 저장된 기록 그대로 (내보내기 바이트 같음)", r.returncode == 0 and os.path.exists(out_a) and open(out_a, "rb").read() == open(out_b, "rb").read())
        report("Enter(복사) 뒤에도 orig.png 바이트 그대로", open(orig, "rb").read() == orig_bytes)
        r = last(out_a, "key 121 key 13")
        r2 = subprocess.run([SHOT, "--replay", base, out_b, "down", "5", "10", "up", "20", "30", "key", "50", "down", "30", "30", "up", "60", "60", "key", "13"], capture_output=True, text=True, env=ENV)
        report("다시 실행 목록도 파일에 남아 다시 열고 Y 가 됨", r.returncode == 0 and os.path.exists(out_a) and open(out_a, "rb").read() == open(out_b, "rb").read())
        saved = open(ops, "rb").read()
        r = last(out_a, "key 13")
        report("기록 파일 왕복: 다시 열고 그대로 복사해도 파일이 같음", open(ops, "rb").read() == saved)
        strokes = "key 52 down 5 5 move 9 12 move 20 7 up 30 30 key 53 down 40 40 move 60 42 up 80 40 key 54 down 10 60 up 90 61 key 55 down 90 10 up 20 50 key 56 down 100 20 up 150 70 key 122"
        r = last(out_a, strokes)
        text = open(ops, encoding="utf-8").read()
        lines = text.splitlines()
        report("새 도구 5개가 ops.txt 에 저장됨 (최근 것부터: arrow, line, high, pen 4점 살아 있고 ellipse 는 다시 실행 목록)", r.returncode == 0 and lines[1] == "done 6" and lines[2].startswith("arrow red 2 ") and lines[3].startswith("line red 2 ") and lines[4].startswith("high red 3 ") and lines[5].startswith("pen red 4 ") and lines[8] == "redo 1" and lines[9].startswith("ellipse red 2 "), repr(text[:200]))
        saved = open(ops, "rb").read()
        r = last(out_a, "key 121 key 13")
        r2 = subprocess.run([SHOT, "--replay", base, out_b] + ("down 5 10 up 20 30 key 50 down 30 30 up 60 60 " + strokes + " key 121 key 13").split(), capture_output=True, text=True, env=ENV)
        report("새 도구 기록을 다시 열어 Y 뒤 복사 = 같은 이벤트를 처음부터 돌린 것 (내보내기 바이트 같음)", r.returncode == 0 and r2.returncode == 0 and os.path.exists(out_a) and open(out_a, "rb").read() == open(out_b, "rb").read())
        r = last(out_a, "key 122 key 13")
        report("새 도구 기록 파일 왕복: 되돌려 처음 상태로 돌아오면 파일이 같음", open(ops, "rb").read() == saved)
        for name, bad in [("머리 줄 아님", b"hello\n"), ("개수 안 맞음", b"bendshot-ops 1\ndone 2\nbox red 2 1 1 2 2\nredo 0\n"), ("모르는 도구", b"bendshot-ops 1\ndone 1\nfrob red 2 1 1 2 2\nredo 0\n"), ("점 수 어긋남", b"bendshot-ops 1\ndone 1\nbox red 2 1 1 2\nredo 0\n"), ("빈 파일", b"")]:
            open(ops, "wb").write(bad)
            r = last(out_a, "down 5 10 up 20 30 key 13")
            report("망가진 ops.txt 거부, 그대로 둠: " + name, r.returncode != 0 and not os.path.exists(out_a) and open(ops, "rb").read() == bad and re.search("[가-힣]", r.stderr + r.stdout) is not None, (r.stderr + r.stdout).strip()[:60])
        # 파일이 없을 때만 빈 기록이다. 읽을 수 없는 기록을 빈 기록으로 열면 다음 자동 저장이 진짜 기록을 덮어쓴다.
        open(ops, "wb").write(saved)
        os.chmod(ops, 0)
        try:
            r = last(out_a, "down 5 10 up 20 30 key 13")
        finally:
            os.chmod(ops, 0o644)
        report("읽을 수 없는 ops.txt (권한 없음) 는 빈 기록으로 열지 않고 거부, 그대로 둠", r.returncode != 0 and not os.path.exists(out_a) and open(ops, "rb").read() == saved and "열지 않습니다" in r.stderr + r.stdout, (r.stderr + r.stdout).strip()[:60])
        os.remove(ops)
        r = last(out_a, "key 13")
        r2 = subprocess.run([SHOT, "--replay", base, out_b, "key", "13"], capture_output=True, text=True, env=ENV)
        report("ops.txt 없으면 빈 기록으로 열림", r.returncode == 0 and os.path.exists(out_a) and open(out_a, "rb").read() == open(out_b, "rb").read())
        # 이름 순서와 orig.png 바뀐 시각 순서를 거꾸로 놓는다: 이름이 큰 것일수록 오래된 캡처. cap(이름 1)이 가장 최근.
        t0 = 1700000000
        os.utime(orig, (t0 + 1000, t0 + 1000))
        for i in range(2, 36):
            d = os.path.join(caps, "1%012d" % i)
            os.makedirs(d)
            open(os.path.join(d, "orig.png"), "wb").close()
            os.utime(os.path.join(d, "orig.png"), (t0 + (40 - i) * 10,) * 2)
        os.makedirs(os.path.join(caps, "noorig"))
        r = subprocess.run([SHOT, "--prune"], capture_output=True, text=True, env=env)
        left = sorted(os.listdir(caps))
        report("보관 한도: 이름이 아니라 orig.png 바뀐 시각이 가장 오래된 것부터 지워 30개만 남김 (이름이 작을수록 최근)", r.returncode == 0 and [d for d in left if d != "noorig"] == ["1%012d" % i for i in range(1, 31)], "%d개 남음 %s" % (len(left), left[:3]))
        report("orig.png 없는 폴더(찍는 중)는 세지도 지우지도 않음", "noorig" in left)
        os.rmdir(os.path.join(caps, "noorig"))
        bad = os.path.join(caps, "9999999999999")
        os.makedirs(bad)
        open(os.path.join(bad, "orig.png"), "wb").close()
        os.utime(os.path.join(bad, "orig.png"), (t0 + 5000,) * 2)
        r = last(out_a, "key 13")
        report("--replay-last 는 이름이 아니라 orig.png 가 가장 최근인 캡처를 엶 (읽을 수 없는 그림은 한국어 오류)", r.returncode != 0 and "열지 못했습니다" in r.stderr + r.stdout, (r.stderr + r.stdout).strip()[:60])
        shutil.rmtree(bad)
        r = last(out_a, "key 13")
        report("가장 최근(이름은 가장 작은) 캡처가 열림", r.returncode == 0 and os.path.exists(out_a))
        for _ in range(3):
            r = subprocess.run([SHOT, "--new-capture-id"], capture_output=True, text=True, env=env)
            report("새 캡처 이름은 벽시계 시각-무작위 꼴", r.returncode == 0 and re.fullmatch(r"\d{8}-\d{6}-\d+\n?", r.stdout) is not None and time.strftime("%Y%m%d") in (r.stdout[:8], time.strftime("%Y%m%d", time.localtime(time.time() - 5))), repr(r.stdout))
        shutil.rmtree(caps)
        r = last(out_a, "key 13")
        report("캡처가 없으면 한국어 오류", r.returncode != 0 and "캡처가 없습니다" in r.stderr + r.stdout)
    finally:
        shutil.rmtree(home, ignore_errors=True)


def order_cases(inp):
    """같은 초에 찍은 두 캡처: orig.png 바뀐 시각을 소수 초까지 비교해야 최근 것이 앞이다 (이름 순서는 거꾸로 놓는다)."""
    print("== 같은 초의 캡처 순서 (가짜 HOME)")
    home = tempfile.mkdtemp(prefix="bendshot-home-")
    try:
        caps = os.path.join(home, "Library", "Caches", "BendShot", "captures")
        for cid in ("A1", "A2"):
            os.makedirs(os.path.join(caps, cid))
        png_from_bmp(inp, os.path.join(caps, "A1", "orig.png"))
        open(os.path.join(caps, "A2", "orig.png"), "wb").close()  # 열면 오류가 나는 그림
        t0 = 1700000000
        os.utime(os.path.join(caps, "A1", "orig.png"), (t0 + 0.3,) * 2)
        os.utime(os.path.join(caps, "A2", "orig.png"), (t0,) * 2)
        out = os.path.join(OUT, "order.bmp")
        if os.path.exists(out):
            os.remove(out)
        r = subprocess.run([SHOT, "--replay-last", out, "key", "13"], capture_output=True, text=True, timeout=120, env=dict(ENV, HOME=home))
        report("같은 초 안에서 0.3초 늦은 캡처(이름은 더 작은 A1)가 가장 최근 (--replay-last 가 엶)", r.returncode == 0 and os.path.exists(out), (r.stderr + r.stdout).strip()[:60])
    finally:
        shutil.rmtree(home, ignore_errors=True)


def legacy_cases():
    """옛 판의 last.png 는 보관·지우기 밖에 남은 원본 사본이다: 어느 모드로 시작하든 한 번 휴지통으로 옮긴다."""
    print("== 옛 last.png (가짜 HOME)")
    home = tempfile.mkdtemp(prefix="bendshot-home-")
    try:
        cache = os.path.join(home, "Library", "Caches", "BendShot")
        trash = os.path.join(home, "trash")
        os.makedirs(cache)
        last = os.path.join(cache, "last.png")
        open(last, "wb").write(b"secret")
        env = dict(ENV, HOME=home, BENDSHOT_TRASH=trash)
        r = subprocess.run([SHOT, "--prune"], capture_output=True, text=True, timeout=60, env=env)
        moved = os.path.exists(os.path.join(trash, "last.png")) and open(os.path.join(trash, "last.png"), "rb").read() == b"secret"
        report("시작할 때 옛 last.png 를 휴지통 폴더로 옮김 (--prune)", r.returncode == 0 and not os.path.exists(last) and moved, (r.stderr + r.stdout).strip()[:60])
        r = subprocess.run([SHOT, "--new-capture-id"], capture_output=True, text=True, timeout=60, env=env)
        report("last.png 가 없으면 아무 일 없음 (휴지통 폴더 그대로)", r.returncode == 0 and os.path.isdir(trash) and os.listdir(trash) == ["last.png"])
    finally:
        shutil.rmtree(home, ignore_errors=True)


def helper_cases():
    """메뉴 막대 앱(app/main.swift)의 '새 캡처가 생겼나' 판단: 가장 최근 captures/*/orig.png (소수 초, 같으면 이름이 큰 것).
    main.swift 를 임시로 컴파일해 --newest 로 본다. 옛 LaunchAgent 정리(--retire-dev-agent)는 가짜 HOME 의 plist(라벨 .test)로 본다."""
    print("== 메뉴 막대 앱 가장 최근 캡처")
    swiftc = shutil.which("swiftc")
    if swiftc is None:
        print("SKIP 도우미 가장 최근 캡처 (swiftc 가 없음)")
        return
    with tempfile.TemporaryDirectory(prefix="bendshot-keys-") as d:
        exe = os.path.join(d, "keys")
        r = subprocess.run([swiftc, os.path.join(HERE, "..", "app", "main.swift"), "-o", exe], capture_output=True, text=True, timeout=300)
        report("메뉴 막대 앱 main.swift 컴파일", r.returncode == 0, r.stderr.strip()[-120:])
        if r.returncode != 0:
            return
        root = os.path.join(d, "captures")
        t0 = 1700000000
        for cid, t, name in [("B1", t0 + 0.3, "orig.png"), ("B2", t0, "orig.png"), ("B3", t0 + 9, "thumb.bmp")]:
            os.makedirs(os.path.join(root, cid))
            p = os.path.join(root, cid, name)
            open(p, "wb").close()
            os.utime(p, (t,) * 2)
        def newest():
            try:
                return subprocess.run([exe, "--newest", root], capture_output=True, text=True, timeout=20).stdout.strip()
            except subprocess.TimeoutExpired:
                return "20초 안에 끝나지 않음 (--newest 를 모름)"
        got = newest()
        report("같은 초 안에서 0.3초 늦은 orig.png 가 가장 최근 (orig.png 없는 폴더는 세지 않음)", got == os.path.join(root, "B1"), got)
        os.utime(os.path.join(root, "B2", "orig.png"), (t0 + 0.3,) * 2)
        got = newest()
        report("시각까지 같으면 이름이 큰 것 (셸의 목록 순서와 같음)", got == os.path.join(root, "B2"), got)
        shutil.rmtree(root)
        report("캡처 폴더가 없으면 빈 줄", newest() == "")
        # 라벨을 .test 로 두면 launchctl bootout 이 실제 에이전트(lab.bend.shotkeys)에 닿지 않는다 (plist 경로로 내린다)
        agents = os.path.join(d, "home", "Library", "LaunchAgents")
        os.makedirs(agents)
        plist = os.path.join(agents, "lab.bend.shotkeys.plist")
        open(plist, "w").write('<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
                               '<plist version="1.0"><dict><key>Label</key><string>lab.bend.shotkeys.test</string></dict></plist>')
        r = subprocess.run([exe, "--retire-dev-agent"], env=dict(os.environ, HOME=os.path.join(d, "home")), capture_output=True, text=True, timeout=30)
        report("옛 LaunchAgent plist 를 가짜 HOME 에서 치움 (휴지통으로)", r.returncode == 0 and not os.path.exists(plist), r.stdout.strip()[-100:])
        r = subprocess.run([exe, "--retire-dev-agent"], env=dict(os.environ, HOME=os.path.join(d, "home")), capture_output=True, text=True, timeout=30)
        report("plist 가 없으면 아무 일 없음", r.returncode == 0 and r.stdout == "")


def v5_header(w, h, ppm):
    """screencapture 와 같은 138바이트 V5 헤더 (32비트 BI_BITFIELDS, 위에서부터의 행)."""
    hdr = b"BM" + struct.pack("<IHHI", 138 + 4 * w * h, 0, 0, 138)
    hdr += struct.pack("<IiiHHIIiiII", 124, w, -h, 1, 32, 3, 4 * w * h, ppm, ppm, 0, 0)
    return hdr + struct.pack("<IIII", 0xFF0000, 0xFF00, 0xFF, 0xFF000000) + b"BGRs" + bytes(64)


def thumb_ref(img):
    """미리보기 기준 구현 (shot.bend 의 Thumb.*): 내보내기(마지막 자르기 안)를 긴 변 192 로. 칸 (tx, ty) 의 원본 자리
    (x0 + tx·cw/tw, y0 + ty·ch/th) 를 덮는 2^b 정렬 블록(192·2^b ≤ 긴 변인 최대 b, 블록은 그림 안만) 의 채널 평균(내림)."""
    w, h = img.w, img.h
    x0, y0, x1, y1 = img.crop if img.crop else (0, 0, w - 1, h - 1)
    cw, ch = x1 - x0 + 1, y1 - y0 + 1
    if cw >= ch:
        tw, th = 192, max(ch * 192 // cw, 1)
    else:
        tw, th = max(cw * 192 // ch, 1), 192
    long = max(cw, ch)
    b = 0
    while b < 8 and (192 << (b + 1)) <= long:
        b += 1
    B = 1 << b
    rows = []
    for ty in range(th):
        row = bytearray()
        sy = y0 + ty * ch // th
        for tx in range(tw):
            sx = x0 + tx * cw // tw
            bx, by = sx // B * B, sy // B * B
            sums, n = [0, 0, 0], 0
            for y in range(by, min(by + B, h)):
                r = img.rows[y]
                for x in range(bx, min(bx + B, w)):
                    sums[0] += r[4 * x]
                    sums[1] += r[4 * x + 1]
                    sums[2] += r[4 * x + 2]
                    n += 1
            row += bytes([sums[0] // n, sums[1] // n, sums[2] // n, 255])
        rows.append(bytes(row))
    return v5_header(tw, th, img.ppm) + b"".join(rows)


def tile_ref(thumb):
    """목록 칸(192×120) 기준 구현: 회색 바탕, 미리보기를 높이 120 에 맞춰(비율대로) 줄여 가운데에, 가장 가까운 점으로."""
    tw, th = (thumb.w, thumb.h) if thumb else (192, 120)
    dw, dh = (tw, th) if th <= 120 else (tw * 120 // th, 120)
    ox, oy = (192 - dw) // 2, (120 - dh) // 2
    rows = []
    for y in range(120):
        row = bytearray(bytes(TILE_BG) * 192)
        for x in range(192):
            if thumb and ox <= x < ox + dw and oy <= y < oy + dh:
                sx, sy = (x - ox) * tw // dw, (y - oy) * th // dh
                row[4 * x : 4 * x + 4] = thumb.rows[sy][4 * sx : 4 * sx + 4]
        if 4 <= y < 28:
            row[4 * 164 : 4 * 188] = bytes(TILE_BG) * 24  # × 단추 자리는 비교에서 뺀다 (tile_at 과 같다)
        rows.append(bytes(row))
    return rows


def tile_at(frame, vw, i):
    """창 그림에서 i 번 칸의 픽셀 행 (× 단추 24×24 자리는 바탕으로 덮어 비교에서 뺀다)."""
    bx, by = vw + 16, 272 + i * 128
    rows = []
    for y in range(120):
        row = bytearray(frame.rows[by + y][4 * bx : 4 * (bx + 192)])
        if y < 28 and y >= 4:
            row[4 * 164 : 4 * 188] = bytes(TILE_BG) * 24
        rows.append(bytes(row))
    return rows


def list_cases(inp):
    """오른쪽 캡처 목록 (가짜 HOME): 미리보기 파일 = 기준 구현, 칸 그리기, 칸·× 누르기 (열기 = EDIT 줄과 닫힘, 지우기 = 휴지통 폴더로), --replay-cap."""
    print("== 캡처 목록 (가짜 HOME)")
    src = Bmp(open(inp, "rb").read())
    w, h, s = src.w, src.h, src.s
    vw = (w + s - 1) // s
    assert max((h + s - 1) // s, PANEL_MIN_H) == 528, "두 칸이 들어가는 창이어야 한다"
    home = tempfile.mkdtemp(prefix="bendshot-home-")
    trash = os.path.join(home, "trash")
    out = os.path.join(OUT, "list.bmp")
    frame = os.path.join(OUT, "list_frame.bmp")
    env = dict(ENV, HOME=home, BENDSHOT_TRASH=trash, BENDSHOT_FRAME=frame)
    try:
        caps = os.path.join(home, "Library", "Caches", "BendShot", "captures")
        ids = ["A", "B", "C"]  # A 가 가장 최근 (orig.png 바뀐 시각)
        t0 = 1700000000
        for i, cid in enumerate(ids):
            d = os.path.join(caps, cid)
            os.makedirs(d)
            png_from_bmp(inp, os.path.join(d, "orig.png"))
            os.utime(os.path.join(d, "orig.png"), (t0 - i * 100,) * 2)
        base24 = os.path.join(OUT, "list_base24.bmp")
        r = subprocess.run(["/usr/bin/sips", "-s", "format", "bmp", os.path.join(caps, "A", "orig.png"), "--out", base24], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        # sips 의 BMP 는 24비트라, shot 이 읽어 32비트로 쓴 것(무편집 왕복)을 기준 원본으로 쓴다
        ok, dt, r = run_shot("--edit", base24, os.path.join(OUT, "list_base.bmp"), [])
        assert ok
        base = Bmp(open(os.path.join(OUT, "list_base.bmp"), "rb").read())
        # B 만 캡처 때 sips 가 만든 꼴의 미리보기를 가진다 (A 는 자리 표시, 편집하면 생긴다)
        r = subprocess.run(["/usr/bin/sips", "-Z", "192", "-s", "format", "bmp", os.path.join(caps, "B", "orig.png"), "--out", os.path.join(caps, "B", "thumb.bmp")], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        ok, dt, r = run_shot("--edit", os.path.join(caps, "B", "thumb.bmp"), os.path.join(OUT, "list_thumb_b.bmp"), [])
        assert ok
        thumb_b = Bmp(open(os.path.join(OUT, "list_thumb_b.bmp"), "rb").read())  # 24비트라 32비트 왕복본으로 비교

        def run(cid, script):
            for f in (out, frame):
                if os.path.exists(f):
                    os.remove(f)
            r = subprocess.run([SHOT, "--replay-cap", cid, out] + script.split(), capture_output=True, text=True, timeout=120, env=env)
            return r, [l for l in r.stdout.splitlines() if l.startswith("EDIT ")]

        e = lambda v: v * s + s - 1
        click = lambda x, y: "down %d %d up %d %d" % (x, y, x, y)
        tile = lambda i: (vw + 16 + 96, 272 + i * 128 + 60)
        xbtn = lambda i: (vw + 180 + 12, 276 + i * 128 + 12)
        r, edits = run("A", "down 5 10 up 20 30 key 13")
        thumb = os.path.join(caps, "A", "thumb.bmp")
        ref = apply_ops(base, ["box", "10", "20", str(e(20)), str(e(30))])
        report("자동 저장마다 thumb.bmp = 내보내기를 긴 변 192 로 줄인 것 (기준 구현과 바이트 같음)", r.returncode == 0 and os.path.exists(thumb) and open(thumb, "rb").read() == thumb_ref(ref), "%d 바이트" % (os.path.getsize(thumb) if os.path.exists(thumb) else -1))
        report("미리보기도 임시 파일을 남기지 않음", not os.path.exists(thumb + ".tmp"))
        fr = Bmp(open(frame, "rb").read()) if os.path.exists(frame) else None
        px = lambda x, y: tuple(fr.rows[y][4 * x : 4 * x + 4])
        report("창 그림: 열 때 미리보기가 없던 열린 캡처(A) 칸은 회색 자리 표시 + 흰 테", fr is not None and tile_at(fr, vw, 0) == tile_ref(None) and px(vw + 14, 272 + 60) == COLORS["white"] and px(vw + 14, 272 + 128 + 60) == PANEL_BG)
        report("창 그림: 둘째 칸은 B 의 thumb.bmp 를 상자에 맞춰 줄여 가운데에 (기준 구현과 같음)", fr is not None and tile_at(fr, vw, 1) == tile_ref(thumb_b), "thumb %dx%d" % (thumb_b.w, thumb_b.h))
        report("창 그림: × 단추는 칸 오른쪽 위 (어두운 바탕, 가운데 흰 획)", fr is not None and px(vw + 181, 277) == (0x20, 0x20, 0x20, 0xFF) and px(vw + 180 + 12, 276 + 12) == COLORS["white"])
        r, edits = run("A", "key 51 down 10 10 up 100 80 key 13")
        ref = apply_ops(base, ["box", "10", "20", str(e(20)), str(e(30)), "crop", "20", "20", str(e(100)), str(e(80))])
        report("자르기 뒤 미리보기는 자른 영역만 (앞선 편집 위에)", r.returncode == 0 and open(thumb, "rb").read() == thumb_ref(ref))
        r, edits = run("A", click(*tile(1)) + " key 13")
        report("둘째 칸(B)을 누르면 EDIT B 를 찍고 창이 닫힘 (그 뒤 Enter 는 무시, 쓰지 않음)", r.returncode == 0 and edits == ["EDIT B"] and not os.path.exists(out), str(edits))
        r, edits = run("A", click(*tile(0)) + " key 13")
        report("열린 캡처(A)의 칸을 눌러도 아무 일 없음 (Enter 가 복사)", r.returncode == 0 and edits == [] and os.path.exists(out))
        r, edits = run("A", "open 0 open 7 open 1 key 13")
        report("open 토큰: 열린 캡처·없는 번호는 무시, 1 은 EDIT B", r.returncode == 0 and edits == ["EDIT B"] and not os.path.exists(out), str(edits))
        # 자동 저장이 실패한 채로 다른 캡처로 바꾸면 이 창이 닫혀 저장 못 한 편집이 사라진다
        adir = os.path.join(caps, "A")
        os.chmod(adir, 0o555)
        try:
            r, edits = run("A", "down 40 40 up 60 60 open 1 key 13")
            copied = os.path.exists(out)
            r2, _ = run("A", "down 40 40 up 60 60 key 27")
            r3, _ = run("A", "down 40 40 up 60 60 key 27 key 27 key 13")
            closed = not os.path.exists(out)
        finally:
            os.chmod(adir, 0o755)
        report("자동 저장이 실패하면 다른 캡처로 바꾸지 않고 알림 (창이 남아 Enter 가 복사)", r.returncode == 0 and edits == [] and copied and "저장에 실패해서 다른 캡처로 바꾸지 않았습니다" in r.stderr, str(edits) + r.stderr.strip()[-60:])
        titles = [l for l in r2.stdout.splitlines() if l.startswith("TITLE ")]
        report("자동 저장이 실패했으면 첫 Esc 경고 제목이 저장 실패를 말함", r2.returncode == 0 and len(titles) == 2 and "저장에 실패" in titles[1], str(titles[1:]))
        report("자동 저장이 실패해도 Esc 두 번은 닫음 (사용자가 닫기를 고름)", r3.returncode == 0 and closed)
        r, edits = run("A", click(*xbtn(1)) + " open 1 key 13")
        report("둘째 칸의 × 는 B 를 휴지통 폴더로 옮기고 나머지는 그대로, 목록을 다시 읽어 1 번은 이제 C", r.returncode == 0 and sorted(os.listdir(caps)) == ["A", "C"] and os.listdir(trash) == ["B"] and edits == ["EDIT C"], str((sorted(os.listdir(caps)), edits)))
        report("휴지통으로 옮긴 캡처는 파일이 그대로 (orig.png, thumb.bmp)", sorted(os.listdir(os.path.join(trash, "B"))) == ["orig.png", "thumb.bmp"])
        r, edits = run("A", click(*xbtn(0)) + " down 5 10 up 20 30 key 13")
        saves = [l for l in r.stdout.splitlines() if l.startswith("SAVE ")]
        report("열린 캡처(A)의 × 는 A 를 휴지통으로 옮기고 창을 닫음 (그 뒤 편집·저장 없음)", r.returncode == 0 and sorted(os.listdir(trash)) == ["A", "B"] and os.listdir(caps) == ["C"] and not saves and not os.path.exists(out), str(saves))
        r, edits = run("C", "down 5 10 up 20 30 key 53 down 30 30 up 60 60 key 13")
        r2 = subprocess.run([SHOT, "--replay", os.path.join(OUT, "list_base.bmp"), os.path.join(OUT, "list_b.bmp")] + "down 5 10 up 20 30 key 53 down 30 30 up 60 60 key 13".split(), capture_output=True, text=True, env=ENV)
        report("--replay-cap <id> 는 그 캡처를 열어 편집 (내보내기 = 같은 이벤트를 원본에 돌린 것)", r.returncode == 0 and r2.returncode == 0 and open(out, "rb").read() == open(os.path.join(OUT, "list_b.bmp"), "rb").read())
        r, edits = run("C", "key 13")
        report("--replay-cap 으로 다시 열면 저장된 기록 그대로", r.returncode == 0 and open(out, "rb").read() == open(os.path.join(OUT, "list_b.bmp"), "rb").read())
        r, edits = run("ZZZ", "key 13")
        report("없는 캡처 이름은 한국어 오류", r.returncode != 0 and "그런 캡처가 없습니다" in r.stderr + r.stdout and not os.path.exists(out), (r.stderr + r.stdout).strip()[:60])
        # 블록 평균 (긴 변 1000 → 4×4 블록) 과 세로 긴 그림 (높이가 긴 변)
        big = os.path.join(OUT, "list_big.bmp")
        synth(big, w=1000, h=600, ppm=2835)
        tall = os.path.join(OUT, "list_tall.bmp")
        synth(tall, w=300, h=500, ppm=2835)
        shutil.rmtree(caps)
        for cid, bmp in (("D", big), ("E", tall)):
            d = os.path.join(caps, cid)
            os.makedirs(d)
            png_from_bmp(bmp, os.path.join(d, "orig.png"))
        r, edits = run("D", "down 5 10 up 200 150 key 13")
        ref = apply_ops(Bmp(open(big, "rb").read()), ["box", "5", "10", "200", "150"])
        thumb = os.path.join(caps, "D", "thumb.bmp")
        report("긴 변 1000 의 미리보기는 4×4 블록 평균 (기준 구현과 바이트 같음)", r.returncode == 0 and open(thumb, "rb").read() == thumb_ref(ref))
        r, edits = run("E", "key 50 down 20 20 up 120 300 key 13")
        ref = apply_ops(Bmp(open(tall, "rb").read()), ["mosaic", "20", "20", "120", "300"])
        thumb = os.path.join(caps, "E", "thumb.bmp")
        fr = Bmp(open(frame, "rb").read())
        got = Bmp(open(thumb, "rb").read()) if os.path.exists(thumb) else None
        report("세로로 긴 그림은 높이가 192 (115×192), 기준 구현과 바이트 같음", r.returncode == 0 and got is not None and (got.w, got.h) == (115, 192) and open(thumb, "rb").read() == thumb_ref(ref), str((got.w, got.h) if got else None))
        # 칸 수: 창 높이 800 (334×1600 s=2) 이면 네 칸, 네 번째 칸은 네 번째 캡처. 캡처 10개 (T0 이 가장 최근), 나머지는 스크롤로
        shutil.rmtree(caps)
        tall2 = os.path.join(OUT, "list_tall2.bmp")
        synth_fast(tall2, 334, 1600, 5669)
        for i in range(10):
            d = os.path.join(caps, "T%d" % i)
            os.makedirs(d)
            png_from_bmp(tall2, os.path.join(d, "orig.png"))
            os.utime(os.path.join(d, "orig.png"), (t0 - i * 100,) * 2)
        r, edits = run("T0", click(vw + 16 + 96, 272 + 3 * 128 + 60) + " key 13")
        fit = [l for l in r.stdout.splitlines() if l.startswith("FIT ")]
        report("창 높이 800 이면 네 칸: 네 번째 칸을 누르면 EDIT T3", r.returncode == 0 and fit == ["FIT 2 391 800"] and edits == ["EDIT T3"], str((fit, edits)))
        r, edits = run("T0", "open 4 key 13")
        r2, edits2 = run("T0", "open 10 key 13")
        report("open 의 번호는 전체 목록 기준: 보이지 않는 다섯 번째(open 4)는 EDIT T4, 없는 번호(open 10)는 무시", r.returncode == 0 and edits == ["EDIT T4"] and r2.returncode == 0 and edits2 == [] and os.path.exists(out), str((edits, edits2)))
        fr = Bmp(open(frame, "rb").read())
        report("네 칸이 모두 자리 표시 회색 (미리보기 없음), 첫 칸만 흰 테", all(tile_at(fr, vw, i) == tile_ref(None) for i in range(4)) and tuple(fr.rows[272 + 60][4 * (vw + 14) : 4 * (vw + 14) + 4]) == COLORS["white"] and tuple(fr.rows[272 + 128 + 60][4 * (vw + 14) : 4 * (vw + 14) + 4]) == PANEL_BG)
        # 스크롤: 목록 위(패널 열, y ≥ 272)에서 쌓인 거리 64px 마다 한 칸, 음수가 아래. 번호는 전체 목록 기준이라 칸 누르기로 확인한다
        sc = lambda dy, x=vw + 100, y=400: "scroll %d %d %s" % (x, y, dy)
        r, edits = run("T0", sc(-64) + " " + click(*tile(0)) + " key 13")
        report("목록 위에서 64px 아래로 넘기면 첫 칸이 T1 (EDIT T1)", r.returncode == 0 and edits == ["EDIT T1"], str(edits))
        r, edits = run("T0", sc(-32) + " " + sc(-31) + " " + click(*tile(1)) + " key 13")
        r2, edits2 = run("T0", sc(-32) + " " + sc(-31) + " " + sc(-1) + " " + click(*tile(1)) + " key 13")
        report("거리는 쌓인다: 32+31 은 아직 그대로(둘째 칸 T1), 1 을 더하면 한 칸(둘째 칸 T2)", r.returncode == 0 and edits == ["EDIT T1"] and r2.returncode == 0 and edits2 == ["EDIT T2"], str((edits, edits2)))
        r, edits = run("T0", sc(-100000) + " " + click(*tile(3)) + " key 13")
        r2, edits2 = run("T0", sc(-100000) + " " + click(*tile(0)) + " key 13")
        report("아래 한계: 마지막 칸이 맨 아래 자리 (넷째 칸 T9, 첫 칸 T6)", r.returncode == 0 and edits == ["EDIT T9"] and r2.returncode == 0 and edits2 == ["EDIT T6"], str((edits, edits2)))
        r, edits = run("T0", sc(-128) + " " + sc(100000) + " " + click(*tile(1)) + " key 13")
        report("위 한계: 두 칸 내려갔다 크게 올리면 처음 자리 (둘째 칸 T1)", r.returncode == 0 and edits == ["EDIT T1"], str(edits))
        r, edits = run("T0", sc(-64, 5, 5) + " " + sc(-64, vw + 100, 100) + " " + click(*tile(1)) + " key 13")
        report("뷰 위나 도구 단추 위의 스크롤은 목록을 안 넘김 (둘째 칸 그대로 T1)", r.returncode == 0 and edits == ["EDIT T1"], str(edits))
        r, edits = run("T0", sc(-64) + " " + click(*xbtn(0)) + " " + click(*tile(0)) + " key 13")
        report("한 칸 넘긴 뒤 첫 칸의 × 는 T1 을 휴지통으로, 자리는 그대로라 첫 칸이 T2", r.returncode == 0 and sorted(os.listdir(trash)) == ["A", "B", "T1"] and edits == ["EDIT T2"], str((sorted(os.listdir(trash)), edits)))
        r, edits = run("T0", sc(-100000) + " " + click(*xbtn(3)) + " " + click(*tile(3)) + " key 13")
        report("맨 아래에서 마지막 칸(T9)을 지우면 자리가 한계 안으로 줄어 넷째 칸이 T8", r.returncode == 0 and "T9" in os.listdir(trash) and edits == ["EDIT T8"], str((sorted(os.listdir(trash)), edits)))
        # 창 그림도 같은 자리: T3 만 미리보기를 주고 한 칸 넘기면 셋째 칸(T3)에 그 그림, 첫 칸은 회색 자리 표시, 흰 테(T0)는 안 보인다
        r = subprocess.run(["/usr/bin/sips", "-Z", "192", "-s", "format", "bmp", os.path.join(caps, "T3", "orig.png"), "--out", os.path.join(caps, "T3", "thumb.bmp")], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        ok, dt, r = run_shot("--edit", os.path.join(caps, "T3", "thumb.bmp"), os.path.join(OUT, "list_thumb_t3.bmp"), [])
        assert ok
        thumb_t3 = Bmp(open(os.path.join(OUT, "list_thumb_t3.bmp"), "rb").read())
        end = os.path.join(OUT, "list_frame_end.bmp")
        if os.path.exists(end):
            os.remove(end)
        r = subprocess.run([SHOT, "--replay-cap", "T0", out, "scroll", str(vw + 100), "400", "-64"], capture_output=True, text=True, timeout=120, env=dict(env, BENDSHOT_FRAME_END=end))
        fr = Bmp(open(end, "rb").read()) if os.path.exists(end) else None
        report("BENDSHOT_FRAME_END: 한 칸 넘긴 마지막 창 그림은 둘째 칸이 T3 의 미리보기, 첫 칸은 회색, 흰 테 없음", fr is not None and tile_at(fr, vw, 1) == tile_ref(thumb_t3) and tile_at(fr, vw, 0) == tile_ref(None) and all(tuple(fr.rows[272 + i * 128 + 60][4 * (vw + 14) : 4 * (vw + 14) + 4]) == PANEL_BG for i in range(4)), r.stderr[-80:] if fr is None else "")
        r = subprocess.run([SHOT, "--replay-cap", "T0", out, "scroll", str(vw + 100), "400", "abc"], capture_output=True, text=True, timeout=120, env=env)
        report("scroll 의 거리가 숫자가 아니면 한국어 오류", r.returncode != 0 and "scroll 의 거리" in r.stderr + r.stdout, (r.stderr + r.stdout).strip()[:60])
    finally:
        shutil.rmtree(home, ignore_errors=True)


def malformed_cases(good):
    """헤더가 어긋난 BMP 는 몇 초 안에 한국어 메시지로 거부해야 한다 (h=0 은 예전에 40억 번 돌았다)."""
    print("== 잘못된 BMP")
    patch = lambda off, fmt, v: good[:off] + struct.pack(fmt, v) + good[off + struct.calcsize(fmt):]
    bad = [
        ("높이 0", patch(22, "<i", 0)),
        ("너비 0", patch(18, "<i", 0)),
        ("잘린 픽셀 자료", good[:-100]),
        ("서명 아님", b"XX" + good[2:]),
        ("16비트", patch(28, "<H", 16)),
        ("압축 RLE", patch(30, "<I", 1)),
        ("헤더 12바이트", patch(14, "<I", 12)),
        ("자료 위치가 파일 밖", patch(10, "<I", len(good) + 1)),
    ]
    path = os.path.join(OUT, "bad.bmp")
    for name, data in bad:
        open(path, "wb").write(data)
        expect_error("--edit", path, [], "잘못된 BMP 거부: " + name)
    # 24비트(알파 없는 PNG 를 sips 가 바꾼 꼴)는 32비트로 읽어 54바이트 헤더로 쓴다
    open(path, "wb").write(synth_bytes(w=37, h=11, bpp=24))
    want = synth_bytes(w=37, h=11, bpp=32)
    out = os.path.join(OUT, "bad_out.bmp")
    ok, dt, r = run_shot("--edit", path, out, [])
    report("24비트 BMP 를 32비트로 읽음", ok and os.path.exists(out) and open(out, "rb").read() == want)


def parser_cases(inp):
    src = Bmp(open(inp, "rb").read())
    w, h = src.w, src.h
    print("== --edit 명령 거부")
    for name, ops in [("숫자 아닌 인자", ["box", 1, 1, "abc", 2]), ("모르는 명령", ["frob", 1, 2, 3, 4]), ("인자 모자람", ["box", 1, 2, 3]),
                      ("crop 전부 그림 밖", ["crop", w + 10, h + 10, w + 20, h + 20]), ("box 전부 그림 밖", ["box", w, 0, w + 5, 5])]:
        expect_error("--edit", inp, ops, "거부: " + name)


def live_capture(path, rect):
    """실제 화면 캡처. 화면 기록 권한이 없거나 화면이 없으면 건너뛴다."""
    r = subprocess.run(["/usr/sbin/screencapture", "-x", "-t", "bmp", "-R", rect, path], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.exists(path):
        print("SKIP 실제 화면 캡처 %s (%s)" % (rect, r.stderr.strip() or "코드 %d" % r.returncode))
        return False
    return True


def main():
    os.makedirs(OUT, exist_ok=True)
    gate_cases()
    synth_path = os.path.join(OUT, "synth.bmp")
    synth(synth_path)
    synth2_path = os.path.join(OUT, "synth2.bmp")
    synth(synth2_path, w=334, h=218, ppm=5669)  # 짝수 크기여야 마지막 화면 픽셀이 원본 두 열을 덮어 끝 좌표 변환을 잡는다
    # 기준 구현 자체 점검: 알려진 무늬에서 box 가 띠 안팎을 가르는지
    s = Bmp(open(synth_path, "rb").read())
    s.box(10, 10, 20, 20)
    assert tuple(s.rows[10][40:44]) == RED and tuple(s.rows[15][60:64]) != RED, "기준 box 가 띠를 잘못 가른다"
    cases(synth_path, "synth")
    cases(synth2_path, "synth2")
    replay_cases(synth2_path)
    stroke_cases(synth_path)
    stroke_cases(synth2_path)
    storage_cases(synth2_path)
    order_cases(synth2_path)
    legacy_cases()
    helper_cases()
    list_cases(synth2_path)
    color_cases(synth_path)
    panel_cases(synth2_path)
    erase_cases(synth2_path)
    fit_cases()
    malformed_cases(open(synth_path, "rb").read())
    parser_cases(synth_path)
    cap300 = os.path.join(OUT, "cap300.bmp")
    cap1200 = os.path.join(OUT, "cap1200.bmp")
    if live_capture(cap300, "0,0,300,200"):
        cases(cap300, "cap300")
    if live_capture(cap1200, "0,0,1200,800"):
        cases(cap1200, "cap1200", big=True)
    shutil.rmtree(FAKE_HOME, ignore_errors=True)
    print("실패 %d 개" % failures)
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
