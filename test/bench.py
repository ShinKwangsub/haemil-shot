#!/usr/bin/env python3 -I
"""확정·되돌리기 속도 측정 (test/out/full.bmp 에 직접 넣는 5120×2880 배율 2 화면 캡처 BMP). --replay 가 찍는 SAVE ms 와 OPEN ms 를 읽는다.

실행: python3 -I test/bench.py [회수]   (SHOT 환경 변수로 다른 바이너리를 잰다)
A: 빈 기록에 펜 300점 하나 확정.  B: 섞인 Op 20개(펜 300점 5, 형광펜 300점 2 포함) + 지우개 2개 위에 펜 300점 확정, 그 뒤 되돌리기.
OPEN: 열 때 첫 프레임(그리기 + 창 그림 합성) 까지의 계산. A·B 를 번갈아 돌리고 중앙값을 낸다.
C (가짜 HOME, 캡처로 열기): A 와 같은 확정에 ops.txt·thumb.bmp 저장이 들어간다. OPEN 은 BENDSHOT_FRAME 으로 첫 프레임을 파일로
강제한 값이라 (게으른 계산이 실제로 돈다) 다른 캡처 29개가 있을 때와 없을 때를 같은 조건으로 비교한다.
"""
import os
import random
import shutil
import statistics
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SHOT = os.environ.get("SHOT", os.path.join(HERE, "..", "shot"))
FULL = os.path.join(HERE, "out", "full.bmp")
OUT = os.path.join(HERE, "out", "bench.bmp")
ENV = dict(os.environ, BENDSHOT_QUIET="1")
W, H = 2560, 1440  # 창(화면 픽셀) 크기


def wobble(n, x0, y0, seed):
    rnd = random.Random(seed)
    pts, x, y = [], x0, y0
    for _ in range(n):
        pts.append((x, y))
        x = min(max(x + rnd.randint(-4, 6), 0), W - 1)
        y = min(max(y + rnd.randint(-5, 5), 0), H - 1)
    return pts


def stroke(key, pts):
    mid = " ".join("move %d %d" % p for p in pts[1:-1])
    return "key %d down %d %d %s up %d %d" % ((key,) + pts[0] + (mid,) + pts[-1])


def saves(script, cap=None, env=ENV):
    """(SAVE ms 목록, OPEN ms). cap 이 있으면 --replay-cap 으로 그 캡처를 연다."""
    cmd = [SHOT, "--replay-cap", cap, OUT] if cap else [SHOT, "--replay", FULL, OUT]
    r = subprocess.run(cmd + script.split(), capture_output=True, text=True, env=env, timeout=600)
    assert r.returncode == 0, r.stderr[-300:]
    opens = [int(l.split()[1]) for l in r.stdout.splitlines() if l.startswith("OPEN ")]
    return [int(l.split()[1]) for l in r.stdout.splitlines() if l.startswith("SAVE ")], (opens[0] if opens else -1)


def fake_home(others):
    """full.bmp 를 orig.png 로 둔 캡처 FULL 과, 미리보기(sips 가 만든 꼴)가 있는 다른 캡처 others 개."""
    home = tempfile.mkdtemp(prefix="bendshot-bench-")
    caps = os.path.join(home, "Library", "Caches", "BendShot", "captures")
    d = os.path.join(caps, "FULL")
    os.makedirs(d)
    png = os.path.join(HERE, "out", "full.png")
    if not os.path.exists(png):
        subprocess.run(["/usr/bin/sips", "-s", "format", "png", FULL, "--out", png], capture_output=True, check=True)
    shutil.copy(png, os.path.join(d, "orig.png"))
    os.utime(os.path.join(d, "orig.png"), (1700000000,) * 2)
    thumb = os.path.join(HERE, "out", "full_thumb.bmp")
    subprocess.run(["/usr/bin/sips", "-Z", "192", "-s", "format", "bmp", png, "--out", thumb], capture_output=True, check=True)
    for i in range(others):
        o = os.path.join(caps, "C%02d" % i)
        os.makedirs(o)
        open(os.path.join(o, "orig.png"), "wb").close()
        os.utime(os.path.join(o, "orig.png"), (1700000000 - 10 * (i + 1),) * 2)
        shutil.copy(thumb, os.path.join(o, "thumb.bmp"))
    return home


def bench_cap(rounds, a):
    frame = os.path.join(HERE, "out", "bench_frame.bmp")
    rows = []
    for others, screen in ((29, "2560x1440"), (29, None), (0, "2560x1440")):
        home = fake_home(others)
        env = dict(ENV, HOME=home, BENDSHOT_FRAME=frame)
        if screen:
            env["BENDSHOT_SCREEN"] = screen
        try:
            ts, to = [], []
            for _ in range(rounds):
                sa, oa = saves(a, cap="FULL", env=env)
                ts.append(sa[0])
                to.append(oa)
            tiles = (720 - 272) // 128 if screen else (1440 - 272) // 128
            print("C 캡처로 열기: 다른 캡처 %d개, 칸 %d개 (d=%s) → 열기 첫 프레임(파일로 강제) %s ms, 펜 300점 확정+미리보기 저장 %s ms" % (others, tiles, "4" if screen else "2", to, ts))
            rows.append((others, tiles, statistics.median(to), statistics.median(ts)))
        finally:
            shutil.rmtree(home, ignore_errors=True)
    for others, tiles, o, t in rows:
        print("중앙값 C: 다른 캡처 %d개 칸 %d개 | 열기 첫 프레임 %d ms | 확정+미리보기 저장 %d ms" % (others, tiles, o, t))


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    pen = lambda seed: stroke(52, wobble(300, 200 + seed * 90, 300 + seed * 40, seed))
    a = pen(1)
    mixed = [pen(i) for i in range(2, 7)] + [stroke(53, wobble(300, 900 + i * 50, 700, i)) for i in range(7, 9)]
    mixed += [stroke(49, [(100 + i * 60, 100), (700 + i * 30, 900)]) for i in range(3)]
    mixed += [stroke(50, [(1500 + i * 100, 200), (2000, 600 + i * 100)]) for i in range(2)]
    mixed += [stroke(54, [(50, 1300 - i * 50), (2500, 1000 + i * 70)]) for i in range(3)]
    mixed += [stroke(55, [(2400, 100 + i * 200), (1200, 1300 - i * 100)]) for i in range(3)]
    mixed += [stroke(56, [(300 + i * 400, 200), (1400 + i * 300, 1200)]) for i in range(2)]
    assert len(mixed) == 20
    # 지우개 둘: 펜 무리를 가로지르는 것과 직선 무리를 가로지르는 것 (닿는 게 있어야 Op 가 된다)
    erasers = ["key 57 down 150 300 up 900 520", "key 57 down 100 1250 up 2500 1050"]
    b = " ".join(mixed + erasers + [pen(9), "key 122"])
    ta, tb, tu, te, to = [], [], [], [], []
    for _ in range(rounds):
        t0 = time.time()
        sa, oa = saves(a)
        wa = time.time() - t0
        t0 = time.time()
        sb, ob = saves(b)
        wb = time.time() - t0
        assert len(sb) == 24, "지우개가 닿는 게 없어 Op 가 안 됨: 저장 %d번" % len(sb)
        ta.append(sa[0])
        tb.append(sb[22])
        tu.append(sb[23])
        te.append(max(sb[20], sb[21]))
        to.append(ob)
        print("A 확정 %d ms (프로세스 %.1fs)  B 확정 %d ms, 되돌리기 %d ms, 지우개 확정 %s ms, 열기 %d ms (프로세스 %.1fs, Op 20개 쌓기 %s)" % (sa[0], wa, sb[22], sb[23], sb[20:22], ob, wb, sb[:20]))
    print("중앙값: 펜 300점 하나 확정 %d ms | Op 20개+지우개 2개 위 확정 %d ms | 되돌리기 %d ms | 지우개 확정 %d ms | 열기 첫 프레임 %d ms" % (statistics.median(ta), statistics.median(tb), statistics.median(tu), statistics.median(te), statistics.median(to)))
    bench_cap(rounds, a)


if __name__ == "__main__":
    main()
