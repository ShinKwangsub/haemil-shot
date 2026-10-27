import Base
import ./core.bend as C

# 자료형
# ======
# 편집 상태 기계는 core.bend 의 C.Ui 하나다. 이 파일은 그 경계(이벤트 -> 행동, 명령 -> IO)와
# 그림 계산(원본 + 살아 있는 Op -> 화면·내보내기)과 보관(캡처 폴더, ops.txt)만 맡는다.

# 행 묶음을 x 방향으로 가른 이진 트리, 잎은 정사각형 Image. SPad 는 범위 전체가 그림 밖이라는 뜻이라
# 2^k 로 채우는 영역이 노드를 만들지 않는다.
type Strip is Data:
  SPad{}
  SLeaf{img: Image}
  SNode{l: Strip, r: Strip}

# 양 끝 포함. x0 > x1 또는 y0 > y1 이면 빈 영역.
type Rect is Data:
  Rect{x0: U32, y0: U32, x1: U32, y1: U32}

# k 는 2^k >= max(w, h) 인 최소 깊이, s 는 캡처 밀도(1 또는 2: 굵기·모자이크 블록의 단위), d 는 표시 배율
# (s·2^j, 창이 화면에 들도록 고른다: 화면 픽셀 하나 = 원본 d×d). hdr 는 원본 헤더 바이트: 저장할 때
# 그대로 써서 무편집 저장이 원본과 바이트까지 같다.
type Shape is Data:
  Shape{w: U32, h: U32, k: Nat, s: U32, d: U32, topdown: Bool, hdr: List<&2, U32>}

# 셸이 드는 그림. base 는 원본(편집기는 절대 바꾸지 않는다), full 은 살아 있는 Op 를 모두 칠한 전체
# 그림, view 는 화면용(배율 2 면 절반, 마지막 자르기 밖은 어둡게), crop 은 마지막 자르기 Op 의 영역.
# full·view·crop 은 기록이 바뀔 때마다 (base, 살아 있는 Op) 에서 다시 만든 캐시다.
type Doc is Data:
  Doc{sh: Shape, base: Image, full: Image, view: Image, crop: Maybe<&2, Rect>}

# 복사 명령이 가는 곳: 클립보드(창), 또는 파일(--edit·--replay). fail 이면 다음 복사 한 번을 실패시킨다.
type Sink is Data:
  SClip{}
  SFile{out: String, fail: Bool}

# 셸 상태. cap 은 연 캡처의 이름(자동 저장·미리보기가 가는 곳, 캡처를 연 경우만). title 은 마지막으로 붙인 제목.
# caps 는 오른쪽 패널의 캡처 목록 (창을 열 때 읽고, 지운 뒤 다시 읽는다).
type Shell is Data:
  Shell{doc: Doc, home: String, stamp: U32, cap: Maybe<&2, String>, sink: Sink, title: String, caps: Caps, lost: Bool}

# 루프에 들어오는 것: 창 이벤트, 바로 넣는 행동(--edit, 복사 결과), 복사 실패 예약(시험용).
type Input is Data:
  IEv{ev: Event}
  IAct{a: C.Act}
  IFail{}

# --edit-last 가 창을 열지, --replay-last 처럼 미리 적은 입력을 파일로 돌릴지.
type Mode is Data:
  MWin{}
  MRun{out: String, ins: List<&2, Input>}

# 이벤트가 오는 곳: 창, 또는 미리 적은 목록(--replay·--edit).
type Surface is Type:
  SWin{win: Window}
  SRun{}
  SDone{}

# 루프 한 바퀴의 상태.
def St() -> Type:
  Surface & Shell & C.Ui & List<&2, Input>

# 명령줄 토큰. 숫자로 읽히면 TNum 이라 해석기가 패턴만으로 인자 수와 형을 검사한다.
type Tok is Data:
  TNum{n: U32}
  TWord{s: String}

# 바이트와 비트
# ============

def Px.pack(b0: U32, b1: U32, b2: U32, b3: U32) -> U32:
  ((b0 .|. (b1 << 8n)) .|. ((b2 << 16n) .|. (b3 << 24n)) : U32)

def Px.bytes(+c: U32, acc: List<&2, U32>) -> List<&2, U32>:
  (c .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> ((c >> 16n) .&. 255 : U32) <> (c >> 24n : U32) <> acc

def Bytes.u32(at: Nat, bs: List<&2, U32>) -> U32:
  match at bs:
    case 0n b0 <> b1 <> b2 <> b3 <> _:
      Px.pack(b0, b1, b2, b3)
    case 1n+p _ <> t:
      Bytes.u32(p, t)
    case _ _:
      0

# 빌려 읽어 새로 짓는 바이트 목록. 한 목록을 두 소유자에게 넘기면 List 가 프로그램 전체에서 공유 상태가 된다.
def Bytes.copy(bs: List<&2, U32>) -> List<&2, U32>:
  match bs:
    case []:
      []
    case b <> rest:
      b <> Bytes.copy(rest)

def Rows.copy(rs: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match rs:
    case []:
      []
    case r <> rest:
      Bytes.copy(r) <> Rows.copy(rest)

def Bytes.le32(+v: U32) -> List<&2, U32>:
  Px.bytes(v, Nil{})

def Bits.tones(fuel: Nat, +x: U32, odd: Bool) -> Nat:
  match fuel odd:
    case 1n+f True{}:
      +y = (x >> 1n : U32)
      1n+Bits.tones(f, y, U32.is_eq((y .&. 1 : U32), 1))
    case _ _:
      0n

def Bits.ones(+x: U32) -> Nat:
  Bits.tones(32n, x, U32.is_eq((x .&. 1 : U32), 1))

def Shape.depth(fuel: Nat, +k: Nat, +m: U32, fits: Bool) -> Nat:
  match fuel fits:
    case _ True{}:
      k
    case 0n _:
      k
    case 1n+f False{}:
      Shape.depth(f, 1n+k, m, U32.is_le(m, (2 << k : U32)))

def U32.sat(+a: U32, +b: U32) -> U32:
  Bool.pick(U32, U32.is_ge(a, b), (a - b : U32), 0)

# 직사각형
# ========

def Rect.norm(+ax: U32, +ay: U32, +bx: U32, +by: U32) -> Rect:
  Rect{U32.min(ax, bx), U32.min(ay, by), U32.max(ax, bx), U32.max(ay, by)}

def Rect.clamp(r: Rect, +w: U32, +h: U32) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{U32.min(x0, (w - 1 : U32)), U32.min(y0, (h - 1 : U32)), U32.min(x1, (w - 1 : U32)), U32.min(y1, (h - 1 : U32))}

# 너무 작으면 빈 영역이 된다 (x0 > x1).
def Rect.inset(r: Rect, +t: U32) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{(x0 + t : U32), (y0 + t : U32), U32.sat(x1, t), U32.sat(y1, t)}

def Rect.div(r: Rect, +s: U32) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{(x0 / s : U32), (y0 / s : U32), (x1 / s : U32), (y1 / s : U32)}

# 화면 좌표 -> 원본 좌표. 끝점은 그 화면 픽셀이 덮는 마지막 원본 픽셀(x*s + s-1)까지 포함해야 끝 열·행에 닿는다.
def Rect.scale(r: Rect, +s: U32) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{(x0 * s : U32), (y0 * s : U32), ((x1 * s : U32) + (s - 1 : U32) : U32), ((y1 * s : U32) + (s - 1 : U32) : U32)}

def Rect.empty() -> Rect:
  Rect{1, 1, 0, 0}

def Rect.copy(r: Rect) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{x0, y0, x1, y1}

def Rect.square(+x: U32, +y: U32, +n: U32) -> Rect:
  Rect{x, y, ((x + n : U32) - 1 : U32), ((y + n : U32) - 1 : U32)}

# 빈 b 는 어느 것과도 겹치지 않는다.
def Rect.apart(a: Rect, b: Rect) -> Bool:
  match a b:
    case Rect{ax0, ay0, ax1, ay1} Rect{+bx0, +by0, +bx1, +by1}:
      U32.is_gt(bx0, bx1) || U32.is_gt(by0, by1) || U32.is_lt(ax1, bx0) || U32.is_lt(bx1, ax0) || U32.is_lt(ay1, by0) || U32.is_lt(by1, ay0)

def Rect.within(a: Rect, b: Rect) -> Bool:
  match a b:
    case Rect{ax0, ay0, ax1, ay1} Rect{bx0, by0, bx1, by1}:
      U32.is_le(bx0, ax0) && U32.is_le(ax1, bx1) && U32.is_le(by0, ay0) && U32.is_le(ay1, by1)

# 스트립 만들기 (BMP 행 -> 쿼드트리)
# ================================
# Bend 는 계산된 값을 match 할 수 없고 상호 재귀도 없어서, "왼쪽 결과를 받아 오른쪽을 잇는" 재귀 대신
# 왼쪽부터 훑으며 완성된 부분 트리를 스택에 쌓고 이진 카운터처럼 합친다. 조건 Bool 은 호출자가 계산해 넘긴다.

def Strip.leaf(s: Strip) -> Image:
  match s:
    case SLeaf{img}:
      img
    case _:
      Pix{0}

def Strip.pair(s: Strip) -> Image & Image:
  match s:
    case SNode{a, b}:
      (Strip.leaf(a), Strip.leaf(b))
    case _:
      (Pix{0}, Pix{0})

def Strip.quad(tp: Image & Image, bp: Image & Image) -> Image:
  (a, b) = tp
  (c, d) = bp
  Qua{a, b, c, d}

def Strip.node(l: Strip, r: Strip) -> Strip:
  match l r:
    case SPad{} SPad{}:
      SPad{}
    case a b:
      SNode{a, b}

# 위·아래 스트립을 세로로 합쳐 한 단계 얕은 스트립으로. bottom 은 d == 1 (잎 바로 위).
def Strip.zip(+d: Nat, bottom: Bool, t: Strip, b: Strip) -> Strip:
  match d bottom t b:
    case _ _ SPad{} SPad{}:
      SPad{}
    case _ True{} tt bb:
      SLeaf{Strip.quad(Strip.pair(tt), Strip.pair(bb))}
    case 1n+p False{} SNode{l1, r1} SNode{l2, r2}:
      Strip.node(Strip.zip(p, Nat.is_eq(p, 1n), l1, l2), Strip.zip(p, Nat.is_eq(p, 1n), r1, r2))
    case 1n+p False{} SNode{l1, r1} SPad{}:
      Strip.node(Strip.zip(p, Nat.is_eq(p, 1n), l1, SPad{}), Strip.zip(p, Nat.is_eq(p, 1n), r1, SPad{}))
    case 1n+p False{} SPad{} SNode{l2, r2}:
      Strip.node(Strip.zip(p, Nat.is_eq(p, 1n), SPad{}, l2), Strip.zip(p, Nat.is_eq(p, 1n), SPad{}, r2))
    case _ _ _ _:
      SPad{}

# m 은 방금 쌓은 x 의 끝자리 1 비트 수
def Row.merge(m: Nat, stack: List<Strip>) -> List<Strip>:
  match m stack:
    case 1n+q a <> b <> rest:
      Row.merge(q, Strip.node(b, a) <> rest)
    case _ s:
      s

def Row.scan(n: Nat, +x: U32, +w: U32, inside: Bool, bs: List<&2, U32>, stack: List<Strip>) -> List<Strip>:
  match n inside bs:
    case 0n _ _:
      stack
    case 1n+p True{} b0 <> b1 <> b2 <> b3 <> rest:
      Row.scan(p, (x + 1 : U32), w, U32.is_lt((x + 1 : U32), w), rest, Row.merge(Bits.ones(x), SLeaf{Pix{Px.pack(b0, b1, b2, b3)}} <> stack))
    case 1n+p _ rest:
      Row.scan(p, (x + 1 : U32), w, U32.is_lt((x + 1 : U32), w), rest, Row.merge(Bits.ones(x), SPad{} <> stack))

def Row.top(stack: List<Strip>) -> Strip:
  match stack:
    case s <> _:
      s
    case Nil{}:
      SPad{}

# 24비트 행: 픽셀당 3바이트, 알파는 255 로 채운다. 행 끝 채움 바이트는 2^k 픽셀 뒤라 읽히지 않는다.
def Row.scan24(n: Nat, +x: U32, +w: U32, inside: Bool, bs: List<&2, U32>, stack: List<Strip>) -> List<Strip>:
  match n inside bs:
    case 0n _ _:
      stack
    case 1n+p True{} b0 <> b1 <> b2 <> rest:
      Row.scan24(p, (x + 1 : U32), w, U32.is_lt((x + 1 : U32), w), rest, Row.merge(Bits.ones(x), SLeaf{Pix{Px.pack(b0, b1, b2, 255)}} <> stack))
    case 1n+p _ rest:
      Row.scan24(p, (x + 1 : U32), w, U32.is_lt((x + 1 : U32), w), rest, Row.merge(Bits.ones(x), SPad{} <> stack))

def Row.strip(k: Nat, +w: U32, +bpp: U32, bs: List<&2, U32>) -> Strip:
  match bpp:
    case 24:
      Row.top(Row.scan24(Nat.pow(2n, k), 0, w, U32.is_lt(0, w), bs, Nil{}))
    case _:
      Row.top(Row.scan(Nat.pow(2n, k), 0, w, U32.is_lt(0, w), bs, Nil{}))

# 파일 안의 한 행 바이트 수 (24비트는 4의 배수로 채움)
def Bmp.rb(+bpp: U32, +w: U32) -> U32:
  match bpp:
    case 24:
      ((((w * 3 : U32) + 3 : U32) / 4 : U32) * 4 : U32)
    case _:
      (w * 4 : U32)

def Build.merge(m: Nat, +d: Nat, stack: List<Strip>) -> List<Strip>:
  match m d stack:
    case 1n+q 1n+e a <> b <> rest:
      Build.merge(q, e, Strip.zip(1n+e, Nat.is_eq(e, 0n), b, a) <> rest)
    case _ _ s:
      s

def Build.scan(n: Nat, +y: U32, +k: Nat, rows: List<Strip>, stack: List<Strip>) -> List<Strip>:
  match n rows:
    case 0n _:
      stack
    case 1n+p r <> rest:
      Build.scan(p, (y + 1 : U32), k, rest, Build.merge(Bits.ones(y), k, r <> stack))
    case 1n+p Nil{}:
      Build.scan(p, (y + 1 : U32), k, Nil{}, Build.merge(Bits.ones(y), k, SPad{} <> stack))

def Build.image(+k: Nat, rows: List<Strip>) -> Image:
  Strip.leaf(Row.top(Build.scan(Nat.pow(2n, k), 0, k, rows, Nil{})))

# 그림 연산
# ========

def Image.chan(+c: U32, sh: Nat) -> U32:
  ((c >> sh) .&. 255 : U32)

def Image.color(i: Image) -> U32:
  match i:
    case Pix{c}:
      c
    case _:
      0

def Image.avg4(a: Image, b: Image, c: Image, d: Image) -> U32:
  +ca = Image.color(a)
  +cb = Image.color(b)
  +cc = Image.color(c)
  +cd = Image.color(d)
  +r = ((((Image.chan(ca, 16n) + Image.chan(cb, 16n) : U32) + (Image.chan(cc, 16n) + Image.chan(cd, 16n) : U32) : U32) >> 2n) : U32)
  +g = ((((Image.chan(ca, 8n) + Image.chan(cb, 8n) : U32) + (Image.chan(cc, 8n) + Image.chan(cd, 8n) : U32) : U32) >> 2n) : U32)
  +b = ((((Image.chan(ca, 0n) + Image.chan(cb, 0n) : U32) + (Image.chan(cc, 0n) + Image.chan(cd, 0n) : U32) : U32) >> 2n) : U32)
  (4278190080 .|. ((r << 16n) .|. ((g << 8n) .|. b)) : U32)

def Image.shrink(+d: Nat, img: Image) -> Image:
  match d img:
    case 1n Qua{tl, tr, bl, br}:
      Pix{Image.avg4(tl, tr, bl, br)}
    case 2n+p Qua{tl, tr, bl, br}:
      Qua{Image.shrink(1n+p, tl), Image.shrink(1n+p, tr), Image.shrink(1n+p, bl), Image.shrink(1n+p, br)}
    case _ i:
      i

# 위 lv 단계만 병렬로 가른다: 노드마다 갈라 쌓는 비용이 더 크다.
def Image.shrink.par(+lv: Nat, +d: Nat, img: Image) -> Image:
  match lv d img:
    case 1n+l 2n+p Qua{tl, tr, bl, br}:
      a b c e = Image.shrink.par(l, 1n+p, tl) Image.shrink.par(l, 1n+p, tr) Image.shrink.par(l, 1n+p, bl) Image.shrink.par(l, 1n+p, br)
      Qua{a, b, c, e}
    case _ dd i:
      Image.shrink(dd, i)

def Image.inside(+x: U32, +y: U32, +n: U32, +w: U32, +h: U32) -> U32:
  +cols = Bool.pick(U32, U32.is_lt(x, w), U32.min(n, (w - x : U32)), 0)
  +rows = Bool.pick(U32, U32.is_lt(y, h), U32.min(n, (h - y : U32)), 0)
  (cols * rows : U32)

def Image.sum4(a: U32 & U32 & U32 & U32, b: U32 & U32 & U32 & U32, c: U32 & U32 & U32 & U32, d: U32 & U32 & U32 & U32) -> U32 & U32 & U32 & U32:
  (ar, ag, ab, an) = a
  (br, bg, bb, bn) = b
  (cr, cg, cb, cn) = c
  (dr, dg, db, dn) = d
  (((ar + br : U32) + (cr + dr : U32) : U32), ((ag + bg : U32) + (cg + dg : U32) : U32), ((ab + bb : U32) + (cb + db : U32) : U32), ((an + bn : U32) + (cn + dn : U32) : U32))

# 그림 밖 채움은 평균에 세지 않는다.
def Image.sum(+d: Nat, img: Image, +x: U32, +y: U32, +w: U32, +h: U32) -> U32 & U32 & U32 & U32:
  match d img:
    case 1n+p Qua{tl, tr, bl, br}:
      +half = (1 << p : U32)
      Image.sum4(Image.sum(p, tl, x, y, w, h), Image.sum(p, tr, (x + half : U32), y, w, h), Image.sum(p, bl, x, (y + half : U32), w, h), Image.sum(p, br, (x + half : U32), (y + half : U32), w, h))
    case dd Pix{+c}:
      +n = Image.inside(x, y, (1 << dd : U32), w, h)
      ((n * Image.chan(c, 16n) : U32), (n * Image.chan(c, 8n) : U32), (n * Image.chan(c, 0n) : U32), n)
    case _ _:
      (0, 0, 0, 0)

def Image.avg(s: U32 & U32 & U32 & U32) -> U32:
  (r, g, b, n) = s
  +m = {n : U32}
  (4278190080 .|. (((r / m : U32) << 16n) .|. (((g / m : U32) << 8n) .|. (b / m : U32))) : U32)

# 그림 -> BMP 행
# =============

def Save.top(+p: Nat, +yr: U32) -> Bool:
  U32.is_lt(yr, ((1 << p : U32) >> 1n : U32))

# 정사각형 [x, x + n) 이 저장할 열 [xa, xb] 와 겹치지 않음
def Save.out(+x: U32, +n: U32, +xa: U32, +xb: U32) -> Bool:
  U32.is_gt(x, xb) || U32.is_le((x + n : U32), xa)

# 오른쪽 절반을 먼저 acc 에 붙여야 왼쪽 바이트가 앞에 온다.
def Save.row(+d: Nat, img: Image, +x: U32, +yr: U32, +xa: U32, +xb: U32, acc: List<&2, U32>, top: Bool, outside: Bool) -> List<&2, U32>:
  match d img top outside:
    case _ _ _ True{}:
      acc
    case 0n Pix{c} _ _:
      Px.bytes(c, acc)
    case 1n+p Pix{+c} _ _:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      Save.row(p, Pix{c}, x, yr, xa, xb, Save.row(p, Pix{c}, x2, yr, xa, xb, acc, True{}, Save.out(x2, half, xa, xb)), True{}, Save.out(x, half, xa, xb))
    case 1n+p Qua{tl, tr, bl, br} True{} _:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      Save.row(p, tl, x, yr, xa, xb, Save.row(p, tr, x2, yr, xa, xb, acc, Save.top(p, yr), Save.out(x2, half, xa, xb)), Save.top(p, yr), Save.out(x, half, xa, xb))
    case 1n+p Qua{tl, tr, bl, br} False{} _:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      +yr2 = (yr - half : U32)
      Save.row(p, bl, x, yr2, xa, xb, Save.row(p, br, x2, yr2, xa, xb, acc, Save.top(p, yr2), Save.out(x2, half, xa, xb)), Save.top(p, yr2), Save.out(x, half, xa, xb))
    case _ _ _ _:
      acc

def Save.rowbytes(+k: Nat, img: Image, +y: U32, +xa: U32, +xb: U32) -> List<&2, U32>:
  Save.row(k, img, 0, y, xa, xb, Nil{}, Save.top(k, y), Save.out(0, (1 << k : U32), xa, xb))


# 모양 읽기
# ========

def Shape.w(sh: Shape) -> U32:
  match sh:
    case Shape{w, _, _, _, _, _, _}:
      w

def Shape.h(sh: Shape) -> U32:
  match sh:
    case Shape{_, h, _, _, _, _, _}:
      h

def Shape.k(sh: Shape) -> Nat:
  match sh:
    case Shape{_, _, k, _, _, _, _}:
      k

def Shape.s(sh: Shape) -> U32:
  match sh:
    case Shape{_, _, _, s, _, _, _}:
      s

# 표시 배율 d = 2^j 의 j
def Shape.lg(+d: U32) -> Nat:
  Bits.ones((d - 1 : U32))

# 화면 그림의 깊이 (표시 배율 d 면 lg d 단계 얕다)
def Shape.vd(+k: Nat, +d: U32) -> Nat:
  Nat.sub(k, Shape.lg(d))

# 표시 배율 d 를 쓴 모양 (화면 크기를 안 뒤에 정한다)
def Shape.fit(sh: Shape, +d: U32) -> Shape:
  match sh:
    case Shape{w, h, k, s, _, td, hdr}:
      Shape{w, h, k, s, d, td, hdr}

# 화면 8px 블록 = 원본 2^(3 + log2 s)
def Shape.bd(+s: U32) -> Nat:
  match s:
    case 2:
      4n
    case _:
      3n

def Image.shrinks(+j: Nat, +k: Nat, img: Image) -> Image:
  match j:
    case 0n:
      img
    case 1n+p:
      Image.shrinks(p, Nat.sub(k, 1n), Image.shrink.par(3n, k, img))

def Shape.view(+k: Nat, +d: U32, full: Image) -> Image:
  Image.shrinks(Shape.lg(d), k, full)

# 자를 영역 밖 어둡게 (약 40%). 칠하기는 아래 칠하기 틀(PDim).

def Image.dim(+c: U32) -> U32:
  +r = ((Image.chan(c, 16n) * 102 : U32) >> 8n : U32)
  +g = ((Image.chan(c, 8n) * 102 : U32) >> 8n : U32)
  +b = ((Image.chan(c, 0n) * 102 : U32) >> 8n : U32)
  (4278190080 .|. ((r << 16n) .|. ((g << 8n) .|. b)) : U32)

def Dim.all(img: Image) -> Image:
  match img:
    case Pix{c}:
      Pix{Image.dim(c)}
    case Qua{tl, tr, bl, br}:
      Qua{Dim.all(tl), Dim.all(tr), Dim.all(bl), Dim.all(br)}

# Op 의 기하와 색
# =============

def Path.last(p: List<&2, C.Pt>, d: C.Pt) -> C.Pt:
  match p:
    case Nil{}:
      d
    case h <> t:
      Path.last(t, h)

def Rect.pt(+ax: U32, +ay: U32, p: C.Pt) -> Rect:
  match p:
    case C.Pt{bx, by}:
      Rect.norm(ax, ay, bx, by)

# 끌기 길의 양 끝(맨 앞 = 뗀 점, 맨 뒤 = 누른 점)으로 만든 직사각형.
def Op.rect(path: List<&2, C.Pt>) -> Rect:
  match path:
    case Nil{}:
      Rect{1, 1, 0, 0}
    case C.Pt{+x, +y} <> rest:
      Rect.pt(x, y, Path.last(rest, C.Pt{x, y}))

# 화면 픽셀 하나가 원본 s×s 를 덮는다. 누른 점은 그 픽셀의 첫 원본 픽셀, 뗀 점은 마지막 원본 픽셀로
# 들어오므로 거꾸로 끌면 둘이 바뀐다. 직사각형을 화면 픽셀 단위로 맞추면 어느 방향이든 같다.
def Rect.snap(r: Rect, +s: U32) -> Rect:
  match r:
    case Rect{x0, y0, x1, y1}:
      Rect{((x0 / s : U32) * s : U32), ((y0 / s : U32) * s : U32), (((x1 / s : U32) * s : U32) + (s - 1 : U32) : U32), (((y1 / s : U32) * s : U32) + (s - 1 : U32) : U32)}

def Op.area(path: List<&2, C.Pt>, +w: U32, +h: U32, +d: U32) -> Rect:
  Rect.clamp(Rect.snap(Op.rect(path), d), w, h)

def Color.px(c: C.Color) -> U32:
  match c:
    case C.CRed{}:
      4294916912
    case C.CYellow{}:
      4294954240
    case C.CGreen{}:
      4281653081
    case C.CBlue{}:
      4278221567
    case C.CBlack{}:
      4278190080
    case C.CWhite{}:
      4294967295

# 도구 번호 (제목의 [n], 단추 비교용)
def Tool.idx(t: C.Tool) -> U32:
  match t:
    case C.TBox{}:
      1
    case C.TMosaic{}:
      2
    case C.TCrop{}:
      3
    case C.TPen{}:
      4
    case C.THigh{}:
      5
    case C.TLine{}:
      6
    case C.TArrow{}:
      7
    case C.TEllipse{}:
      8
    case C.TErase{}:
      9


# 획: 펜·형광펜·직선·화살표·원
# ===========================
# 획 = 정수 좌표 선분 조각들을 반지름 r 로 부풀린 캡슐의 합집합. 픽셀 (x, y) 는 어느 조각에서든 거리가 r 이하면
# 덮인다. 조각은 체비쇼프 길이 64 이하로 잘라 두어 거리 비교(4·cross² ≤ R²·len2, R = 2r)가 32비트 정수 안에서
# 정확하다 (F32 를 쓰지 않으므로 파이썬 기준 구현과 바이트까지 같다). 음수는 U32 감싸기로 들고 다니며 맨 윗
# 비트로 부호를 읽는다. 원은 256각형이라 원도 조각 목록이다.

type Seg is Data:
  Seg{ax: U32, ay: U32, bx: U32, by: U32}

# 덮인 픽셀을 색으로 칠하거나(ISolid) 아래 색과 섞는다(IBlend, 형광펜 40%).
type Ink is Data:
  ISolid{c: U32}
  IBlend{c: U32}

def Blend.ch(+c: U32, +u: U32, +sh: Nat) -> U32:
  (((Image.chan(u, sh) * 3 : U32) + (Image.chan(c, sh) * 2 : U32) : U32) / 5 : U32)

def Blend.px(+c: U32, +u: U32) -> U32:
  (4278190080 .|. ((Blend.ch(c, u, 16n) << 16n) .|. ((Blend.ch(c, u, 8n) << 8n) .|. Blend.ch(c, u, 0n))) : U32)

def Blend.all(+c: U32, img: Image) -> Image:
  match img:
    case Pix{u}:
      Pix{Blend.px(c, u)}
    case Qua{tl, tr, bl, br}:
      Qua{Blend.all(c, tl), Blend.all(c, tr), Blend.all(c, bl), Blend.all(c, br)}

# 전부 덮인 칸: 칠하기는 한 픽셀로 줄고, 섞기는 잎마다 한 번 (한 Op 안에서 겹친 조각도 한 번만 섞인다).
def Ink.copy(ink: Ink) -> Ink:
  match ink:
    case ISolid{c}:
      ISolid{c}
    case IBlend{c}:
      IBlend{c}

def Ink.all(ink: Ink, img: Image) -> Image:
  match ink:
    case ISolid{c}:
      Pix{c}
    case IBlend{c}:
      Blend.all(c, img)

def U32.absdiff(+a: U32, +b: U32) -> U32:
  (U32.max(a, b) - U32.min(a, b) : U32)

def Lerp(+a: U32, +b: U32, +i: U32, +m: U32) -> U32:
  Bool.pick(U32, U32.is_ge(b, a), (a + (((b - a : U32) * i : U32) / m : U32) : U32), (a - (((a - b : U32) * i : U32) / m : U32) : U32))

def Seg.pieces(n: Nat, +i: U32, +m: U32, +ax: U32, +ay: U32, +bx: U32, +by: U32, +px: U32, +py: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +qx = Lerp(ax, bx, i, m)
      +qy = Lerp(ay, by, i, m)
      Seg.pieces(p, (i + 1 : U32), m, ax, ay, bx, by, qx, qy, Seg{px, py, qx, qy} <> acc)

def Seg.split.go(+ax: U32, +ay: U32, +bx: U32, +by: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  +m = U32.max(((U32.max(U32.absdiff(ax, bx), U32.absdiff(ay, by)) + 63 : U32) / 64 : U32), 1)
  Seg.pieces(U32.to_nat(m), 1, m, ax, ay, bx, by, ax, ay, acc)

# 선분을 체비쇼프 길이 64 이하의 조각 m 개로 (끝점은 정수로 내림). 내림이 방향을 타므로 (x, y) 가 작은 끝에서 시작해
# 어느 쪽에서 그어도 같은 조각이 나온다.
def Seg.split(+ax: U32, +ay: U32, +bx: U32, +by: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  +swap = U32.is_lt(bx, ax) || (U32.is_eq(bx, ax) && U32.is_lt(by, ay))
  Seg.split.go(Bool.pick(U32, swap, bx, ax), Bool.pick(U32, swap, by, ay), Bool.pick(U32, swap, ax, bx), Bool.pick(U32, swap, ay, by), acc)

# 조각 상자를 rc 만큼 넓힌 것이 정사각형 [x, x+n) 과 겹치는가 (거친 걸러내기).
def Seg.near(s: Seg, +x: U32, +y: U32, +n: U32, +rc: U32) -> Bool:
  match s:
    case Seg{+ax, +ay, +bx, +by}:
      U32.is_ge((U32.max(ax, bx) + rc : U32), x) && U32.is_le(U32.min(ax, bx), (((x + n : U32) + rc : U32) - 1 : U32)) && U32.is_ge((U32.max(ay, by) + rc : U32), y) && U32.is_le(U32.min(ay, by), (((y + n : U32) + rc : U32) - 1 : U32))

def Seg.copy(s: Seg) -> Seg:
  match s:
    case Seg{ax, ay, bx, by}:
      Seg{ax, ay, bx, by}

def Segs.keep(keep: Bool, s: Seg, rest: List<&2, Seg>) -> List<&2, Seg>:
  match keep:
    case True{}:
      Seg.copy(s) <> rest
    case False{}:
      rest

def Segs.near(segs: List<&2, Seg>, +x: U32, +y: U32, +n: U32, +rc: U32) -> List<&2, Seg>:
  match segs:
    case Nil{}:
      Nil{}
    case +s <> rest:
      Segs.keep(Seg.near(s, x, y, n, rc), s, Segs.near(rest, x, y, n, rc))

# 캡슐 판정 마무리: 내적이 음수면 A 쪽 끝, len2 를 넘으면 B 쪽 끝, 아니면 외적으로 수직 거리.
def Seg.hit.go(+apx: U32, +apy: U32, +bpx: U32, +bpy: U32, +abx: U32, +aby: U32, +len2: U32, +rr: U32, neg: Bool, past: Bool) -> Bool:
  match neg past:
    case True{} _:
      U32.is_le((4 * ((apx * apx : U32) + (apy * apy : U32) : U32) : U32), rr)
    case False{} True{}:
      U32.is_le((4 * ((bpx * bpx : U32) + (bpy * bpy : U32) : U32) : U32), rr)
    case False{} False{}:
      +cross = ((apx * aby : U32) - (apy * abx : U32) : U32)
      U32.is_le((4 * (cross * cross : U32) : U32), (rr * len2 : U32))

# 픽셀 (px, py) 가 조각 s 에서 r 이하인가 (rr = R², R = 2r).
def Seg.hit(s: Seg, +px: U32, +py: U32, +rr: U32) -> Bool:
  match s:
    case Seg{+ax, +ay, +bx, +by}:
      +abx = (bx - ax : U32)
      +aby = (by - ay : U32)
      +apx = (px - ax : U32)
      +apy = (py - ay : U32)
      +len2 = ((abx * abx : U32) + (aby * aby : U32) : U32)
      +dot = ((apx * abx : U32) + (apy * aby : U32) : U32)
      Seg.hit.go(apx, apy, (px - bx : U32), (py - by : U32), abx, aby, len2, rr, U32.is_ge(dot, 2147483648), U32.is_ge(dot, len2))

def Segs.hit(segs: List<&2, Seg>, +px: U32, +py: U32, +rr: U32, acc: Bool) -> Bool:
  match segs acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case s <> rest False{}:
      Segs.hit(rest, px, py, rr, Seg.hit(s, px, py, rr))

# 네 모서리가 한 조각의 캡슐 안이면 (볼록) 정사각형 전체가 그 안이다.
def Seg.covers(+s: Seg, +x: U32, +y: U32, +x2: U32, +y2: U32, +rr: U32) -> Bool:
  Seg.hit(s, x, y, rr) && Seg.hit(s, x2, y, rr) && Seg.hit(s, x, y2, rr) && Seg.hit(s, x2, y2, rr)

def Segs.cover(segs: List<&2, Seg>, +x: U32, +y: U32, +x2: U32, +y2: U32, +rr: U32, acc: Bool) -> Bool:
  match segs acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case s <> rest False{}:
      Segs.cover(rest, x, y, x2, y2, rr, Seg.covers(s, x, y, x2, y2, rr))

def Stroke.cover.big(small: Bool, segs: List<&2, Seg>, +x: U32, +y: U32, +n: U32, +rr: U32) -> Bool:
  match small:
    case False{}:
      False{}
    case True{}:
      Segs.cover(segs, x, y, ((x + n : U32) - 1 : U32), ((y + n : U32) - 1 : U32), rr, False{})

# 칸이 전부 덮였는가. 한 픽셀이면 그 픽셀 판정, 32 이하면 모서리 판정 (그보다 크면 거리 계산이 32비트를 넘을 수 있다).
def Stroke.cover(d: Nat, segs: List<&2, Seg>, +x: U32, +y: U32, +n: U32, +rr: U32) -> Bool:
  match d:
    case 0n:
      Segs.hit(segs, x, y, rr, False{})
    case 1n+p:
      Stroke.cover.big(Nat.is_le(p, 4n), segs, x, y, n, rr)

# 칠하기 틀
# ========
# 네 화가(네모 띠·모자이크·어둡게·획)가 쿼드트리 걷기 하나를 쓴다. 칸마다 Paint.step 이 그대로 둘지(부분 트리 공유),
# 통째로 바꿀지, 쪼개 내려갈지를 정하고, 바꿀 때만 Paint.fill 이 그림을 만든다.

type Painter is Data:
  PBox{outer: Rect, inner: Rect, color: U32}
  PMosaic{bd: Nat, rect: Rect, w: U32, h: U32}
  PDim{r: Rect}
  PStroke{rr: U32, rc: U32, ink: Ink, segs: List<&2, Seg>}

# 깊이 d 의 그림에서 (x, y) 를 덮는, n 단계 아래의 부분 트리. right·down 은 이 노드에서 오른쪽·아래 자식으로
# 갈지 (호출자가 반절 크기로 셈해 넘긴다: 상호 재귀 없이 가르기 위해).
def Image.sub(n: Nat, +d: Nat, img: Image, +x: U32, +y: U32, right: Bool, down: Bool) -> Image:
  match n d img right down:
    case 0n _ i _ _:
      i
    case _ _ Pix{c} _ _:
      Pix{c}
    case 1n+p 1n+e Qua{tl, tr, bl, br} False{} False{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      Image.sub(p, e, tl, x, y, U32.is_ge(x, h2), U32.is_ge(y, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} True{} False{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +x2 = (x - (1 << e : U32) : U32)
      Image.sub(p, e, tr, x2, y, U32.is_ge(x2, h2), U32.is_ge(y, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} False{} True{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +y2 = (y - (1 << e : U32) : U32)
      Image.sub(p, e, bl, x, y2, U32.is_ge(x, h2), U32.is_ge(y2, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} True{} True{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +x2 = (x - (1 << e : U32) : U32)
      +y2 = (y - (1 << e : U32) : U32)
      Image.sub(p, e, br, x2, y2, U32.is_ge(x2, h2), U32.is_ge(y2, h2))
    case _ _ i _ _:
      i

# Image.sub 와 같은 길을 내려가 색만 돌려준다 (그림을 빌려 읽기만 한다).
def Image.px(n: Nat, +d: Nat, img: Image, +x: U32, +y: U32, right: Bool, down: Bool) -> U32:
  match n d img right down:
    case 0n _ i _ _:
      Image.color(i)
    case _ _ Pix{c} _ _:
      c
    case 1n+p 1n+e Qua{tl, tr, bl, br} False{} False{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      Image.px(p, e, tl, x, y, U32.is_ge(x, h2), U32.is_ge(y, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} True{} False{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +x2 = (x - (1 << e : U32) : U32)
      Image.px(p, e, tr, x2, y, U32.is_ge(x2, h2), U32.is_ge(y, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} False{} True{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +y2 = (y - (1 << e : U32) : U32)
      Image.px(p, e, bl, x, y2, U32.is_ge(x, h2), U32.is_ge(y2, h2))
    case 1n+p 1n+e Qua{tl, tr, bl, br} True{} True{}:
      +h2 = ((1 << e : U32) >> 1n : U32)
      +x2 = (x - (1 << e : U32) : U32)
      +y2 = (y - (1 << e : U32) : U32)
      Image.px(p, e, br, x2, y2, U32.is_ge(x2, h2), U32.is_ge(y2, h2))
    case _ _ i _ _:
      Image.color(i)

def Image.at(+k: Nat, img: Image, +x: U32, +y: U32) -> U32:
  +half = ((1 << k : U32) >> 1n : U32)
  Image.px(k, k, img, x, y, U32.is_ge(x, half), U32.is_ge(y, half))

type Step is Data:
  SKeep{}
  SFill{p: Painter}
  SSplit{p: Painter}

def Step.of(skip: Bool, fill: Bool, p: Painter) -> Step:
  match skip fill:
    case True{} _:
      SKeep{}
    case False{} True{}:
      SFill{p}
    case False{} False{}:
      SSplit{p}

def Stroke.step(near: List<&2, Seg>, cover: Bool, +rr: U32, +rc: U32, ink: Ink) -> Step:
  match near cover:
    case Nil{} _:
      SKeep{}
    case ss True{}:
      SFill{PStroke{rr, rc, ink, ss}}
    case ss False{}:
      SSplit{PStroke{rr, rc, ink, ss}}

# 칸 [x, x+n) (깊이 d) 에서 할 일. 띠 = outer 안이면서 inner 밖. 모자이크는 블록 크기 이하면 평균 한 칸.
# 획은 가까운 조각만 추려 내려보낸다.
# p 는 빌려 읽기만 하고 아이 칸의 화가는 새로 짓는다: Paint.go 가 한 화가를 네 아이에게 나눠 주면
# 그 안의 조각 목록 때문에 List 가 프로그램 전체에서 공유 상태가 된다.
def Paint.step(p: Painter, +d: Nat, +x: U32, +y: U32, +n: U32) -> Step:
  match p:
    case PBox{+outer, +inner, color}:
      +sq = Rect.square(x, y, n)
      Step.of(Rect.apart(sq, outer) || Rect.within(sq, inner), Rect.within(sq, outer) && Rect.apart(sq, inner), PBox{Rect.copy(outer), Rect.copy(inner), color})
    case PMosaic{+bd, +rect, w, h}:
      Step.of(Rect.apart(Rect.square(x, y, n), rect), Nat.is_le(d, bd), PMosaic{bd, Rect.copy(rect), w, h})
    case PDim{+r}:
      +sq = Rect.square(x, y, n)
      Step.of(Rect.within(sq, r), Rect.apart(sq, r), PDim{Rect.copy(r)})
    case PStroke{+rr, +rc, ink, segs}:
      +near = Segs.near(segs, x, y, n, rc)
      Stroke.step(near, Stroke.cover(d, near, x, y, n, rr), rr, rc, Ink.copy(ink))

# 미리보기 화가는 픽셀마다 원본 미리보기를 가장 가까운 점으로 뽑는다 (dw×dh 로 줄여 (ox, oy) 에 놓는다).
def Paint.fill(p: Painter, +d: Nat, img: Image, +x: U32, +y: U32) -> Image:
  match p:
    case PBox{_, _, color}:
      Pix{color}
    case PMosaic{_, _, w, h}:
      Pix{Image.avg(Image.sum(d, img, x, y, w, h))}
    case PDim{_}:
      Dim.all(img)
    case PStroke{_, _, ink, _}:
      Ink.all(ink, img)

def Paint.go(+d: Nat, img: Image, +x: U32, +y: U32, step: Step) -> Image:
  match d img step:
    case _ i SKeep{}:
      i
    case _ i SFill{p}:
      Paint.fill(p, d, i, x, y)
    case 1n+p Pix{+c} SSplit{+st}:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      +y2 = (y + half : U32)
      Qua{Paint.go(p, Pix{c}, x, y, Paint.step(st, p, x, y, half)),
          Paint.go(p, Pix{c}, x2, y, Paint.step(st, p, x2, y, half)),
          Paint.go(p, Pix{c}, x, y2, Paint.step(st, p, x, y2, half)),
          Paint.go(p, Pix{c}, x2, y2, Paint.step(st, p, x2, y2, half))}
    case 1n+p Qua{tl, tr, bl, br} SSplit{+st}:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      +y2 = (y + half : U32)
      Qua{Paint.go(p, tl, x, y, Paint.step(st, p, x, y, half)),
          Paint.go(p, tr, x2, y, Paint.step(st, p, x2, y, half)),
          Paint.go(p, bl, x, y2, Paint.step(st, p, x, y2, half)),
          Paint.go(p, br, x2, y2, Paint.step(st, p, x2, y2, half))}
    case _ i _:
      i

def Paint.run(+k: Nat, img: Image, p: Painter) -> Image:
  Paint.go(k, img, 0, 0, Paint.step(p, k, 0, 0, (1 << k : U32)))

# rad = R = 지름(픽셀). 걸러내기 반지름 rc 는 R/2 올림.
def Stroke.draw(+k: Nat, img: Image, +rad: U32, ink: Ink, segs: List<&2, Seg>) -> Image:
  Paint.run(k, img, PStroke{(rad * rad : U32), ((rad + 1 : U32) / 2 : U32), ink, segs})

# 자를 영역은 원본 좌표라 표시 배율로 나눈다.
def Dim.view(+vd: Nat, +d: U32, view: Image, crop: Maybe<&2, Rect>) -> Image:
  match crop:
    case None{}:
      view
    case Some{r}:
      Paint.run(vd, view, PDim{Rect.div(r, d)})

# 길 (뗀 점이 앞) -> 꺾은선 조각. 누른 점(맨 뒤)에서 뗀 점까지 이어지고, 뗀 점의 점 하나가 늘 들어가 클릭만 해도 점이 찍힌다.
def Path.polyline.go(path: List<&2, C.Pt>, +px: U32, +py: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match path:
    case Nil{}:
      acc
    case C.Pt{+x, +y} <> rest:
      Path.polyline.go(rest, x, y, Seg.split(px, py, x, y, acc))

def Path.polyline(path: List<&2, C.Pt>) -> List<&2, Seg>:
  match path:
    case Nil{}:
      Nil{}
    case C.Pt{+x, +y} <> rest:
      Path.polyline.go(rest, x, y, [Seg{x, y, x, y}])

def Seg.to(a: C.Pt, +bx: U32, +by: U32) -> Seg:
  match a:
    case C.Pt{ax, ay}:
      Seg{ax, ay, bx, by}

# 누른 점 -> 뗀 점.
def Path.ends(path: List<&2, C.Pt>) -> Seg:
  match path:
    case Nil{}:
      Seg{0, 0, 0, 0}
    case C.Pt{+x, +y} <> rest:
      Seg.to(Path.last(rest, C.Pt{x, y}), x, y)

def Path.line(ends: Seg) -> List<&2, Seg>:
  match ends:
    case Seg{ax, ay, bx, by}:
      Seg.split(ax, ay, bx, by, Nil{})

def Isqrt.go(fuel: Nat, +n: U32, +x: U32, +y: U32, stop: Bool) -> U32:
  match fuel stop:
    case _ True{}:
      x
    case 0n _:
      y
    case 1n+f False{}:
      +z = ((y + (n / y : U32) : U32) / 2 : U32)
      Isqrt.go(f, n, y, z, U32.is_ge(z, y))

# 내림 제곱근 (뉴턴, 파이썬 math.isqrt 와 같다).
def U32.isqrt(+n: U32) -> U32:
  match n:
    case 0:
      0
    case _:
      +y = ((n + 1 : U32) / 2 : U32)
      Isqrt.go(40n, n, n, y, U32.is_ge(y, n))

# 화살표 머리 한 성분: 부호 있는 num (단위 벡터 성분 × 65536 × len) 을 L·num/(65536·len) 으로, 0 쪽으로 자른다.
def Arrow.off(+num: U32, +len: U32, +l: U32) -> U32:
  +neg = U32.is_ge(num, 2147483648)
  +mag = Bool.pick(U32, neg, (0 - num : U32), num)
  +e = (((mag / len : U32) * l : U32) / 65536 : U32)
  Bool.pick(U32, neg, (0 - e : U32), e)

# b - e (e 는 부호 있음) 를 [0, m-1] 로 잘라서.
def Arrow.pt(+b: U32, +e: U32, +m: U32) -> U32:
  +neg = U32.is_ge(e, 2147483648)
  +plus = U32.min((b + (0 - e : U32) : U32), (m - 1 : U32))
  +minus = Bool.pick(U32, U32.is_gt(e, b), 0, (b - e : U32))
  Bool.pick(U32, neg, plus, minus)

def Arrow.head.go(+bx: U32, +by: U32, +dx: U32, +dy: U32, +len: U32, +l: U32, +w: U32, +h: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match len:
    case 0:
      acc
    case _:
      +c = {56756 : U32}
      +sn = {32768 : U32}
      +e1x = Arrow.off(((dx * c : U32) - (dy * sn : U32) : U32), len, l)
      +e1y = Arrow.off(((dx * sn : U32) + (dy * c : U32) : U32), len, l)
      +e2x = Arrow.off(((dx * c : U32) + (dy * sn : U32) : U32), len, l)
      +e2y = Arrow.off(((dx * sn : U32) - (dy * c : U32) : U32), len, l)
      Seg.split(bx, by, Arrow.pt(bx, e1x, w), Arrow.pt(by, e1y, h), Seg.split(bx, by, Arrow.pt(bx, e2x, w), Arrow.pt(by, (0 - e2y : U32), h), acc))

# 머리: 끝점에서 축 반대쪽으로 ±30° (cos30·65536 = 56756, sin30·65536 = 32768), 길이 l. 머리 점은 그림 안으로 자른다.
def Arrow.head(ends: Seg, +l: U32, +w: U32, +h: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match ends:
    case Seg{+ax, +ay, +bx, +by}:
      +dx = (bx - ax : U32)
      +dy = (by - ay : U32)
      Arrow.head.go(bx, by, dx, dy, U32.isqrt(((dx * dx : U32) + (dy * dy : U32) : U32)), l, w, h, acc)

def Path.arrow(+ends: Seg, +l: U32, +w: U32, +h: U32) -> List<&2, Seg>:
  Arrow.head(ends, l, w, h, Path.line(ends))

# 256각형 꼭짓점표: (65536 + cos·65536, 65536 + sin·65536) 를 i = 0..255 로. verify.py 가 같은 식으로 다시 만들어 비교한다.
def Ell.tab() -> List<&2, U32>:
  [
   131072, 65536, 131052, 67144, 130993, 68752, 130894, 70357, 130756, 71960, 130579, 73558, 130363, 75152, 130107, 76740,
   129813, 78321, 129480, 79895, 129108, 81460, 128698, 83015, 128250, 84560, 127764, 86093, 127241, 87614, 126681, 89122,
   126083, 90616, 125450, 92094, 124780, 93556, 124074, 95002, 123334, 96429, 122558, 97839, 121748, 99228, 120904, 100598,
   120027, 101946, 119117, 103272, 118175, 104576, 117201, 105856, 116196, 107112, 115160, 108342, 114095, 109547, 113000, 110726,
   111877, 111877, 110726, 113000, 109547, 114095, 108342, 115160, 107112, 116196, 105856, 117201, 104576, 118175, 103272, 119117,
   101946, 120027, 100598, 120904, 99228, 121748, 97839, 122558, 96429, 123334, 95002, 124074, 93556, 124780, 92094, 125450,
   90616, 126083, 89122, 126681, 87614, 127241, 86093, 127764, 84560, 128250, 83015, 128698, 81460, 129108, 79895, 129480,
   78321, 129813, 76740, 130107, 75152, 130363, 73558, 130579, 71960, 130756, 70357, 130894, 68752, 130993, 67144, 131052,
   65536, 131072, 63928, 131052, 62320, 130993, 60715, 130894, 59112, 130756, 57514, 130579, 55920, 130363, 54332, 130107,
   52751, 129813, 51177, 129480, 49612, 129108, 48057, 128698, 46512, 128250, 44979, 127764, 43458, 127241, 41950, 126681,
   40456, 126083, 38978, 125450, 37516, 124780, 36070, 124074, 34643, 123334, 33233, 122558, 31844, 121748, 30474, 120904,
   29126, 120027, 27800, 119117, 26496, 118175, 25216, 117201, 23960, 116196, 22730, 115160, 21525, 114095, 20346, 113000,
   19195, 111877, 18072, 110726, 16977, 109547, 15912, 108342, 14876, 107112, 13871, 105856, 12897, 104576, 11955, 103272,
   11045, 101946, 10168, 100598, 9324, 99228, 8514, 97839, 7738, 96429, 6998, 95002, 6292, 93556, 5622, 92094,
   4989, 90616, 4391, 89122, 3831, 87614, 3308, 86093, 2822, 84560, 2374, 83015, 1964, 81460, 1592, 79895,
   1259, 78321, 965, 76740, 709, 75152, 493, 73558, 316, 71960, 178, 70357, 79, 68752, 20, 67144,
   0, 65536, 20, 63928, 79, 62320, 178, 60715, 316, 59112, 493, 57514, 709, 55920, 965, 54332,
   1259, 52751, 1592, 51177, 1964, 49612, 2374, 48057, 2822, 46512, 3308, 44979, 3831, 43458, 4391, 41950,
   4989, 40456, 5622, 38978, 6292, 37516, 6998, 36070, 7738, 34643, 8514, 33233, 9324, 31844, 10168, 30474,
   11045, 29126, 11955, 27800, 12897, 26496, 13871, 25216, 14876, 23960, 15912, 22730, 16977, 21525, 18072, 20346,
   19195, 19195, 20346, 18072, 21525, 16977, 22730, 15912, 23960, 14876, 25216, 13871, 26496, 12897, 27800, 11955,
   29126, 11045, 30474, 10168, 31844, 9324, 33233, 8514, 34643, 7738, 36070, 6998, 37516, 6292, 38978, 5622,
   40456, 4989, 41950, 4391, 43458, 3831, 44979, 3308, 46512, 2822, 48057, 2374, 49612, 1964, 51177, 1592,
   52751, 1259, 54332, 965, 55920, 709, 57514, 493, 59112, 316, 60715, 178, 62320, 79, 63928, 20,
   65536, 0, 67144, 20, 68752, 79, 70357, 178, 71960, 316, 73558, 493, 75152, 709, 76740, 965,
   78321, 1259, 79895, 1592, 81460, 1964, 83015, 2374, 84560, 2822, 86093, 3308, 87614, 3831, 89122, 4391,
   90616, 4989, 92094, 5622, 93556, 6292, 95002, 6998, 96429, 7738, 97839, 8514, 99228, 9324, 100598, 10168,
   101946, 11045, 103272, 11955, 104576, 12897, 105856, 13871, 107112, 14876, 108342, 15912, 109547, 16977, 110726, 18072,
   111877, 19195, 113000, 20346, 114095, 21525, 115160, 22730, 116196, 23960, 117201, 25216, 118175, 26496, 119117, 27800,
   120027, 29126, 120904, 30474, 121748, 31844, 122558, 33233, 123334, 34643, 124074, 36070, 124780, 37516, 125450, 38978,
   126083, 40456, 126681, 41950, 127241, 43458, 127764, 44979, 128250, 46512, 128698, 48057, 129108, 49612, 129480, 51177,
   129813, 52751, 130107, 54332, 130363, 55920, 130579, 57514, 130756, 59112, 130894, 60715, 130993, 62320, 131052, 63928
  ]

def Ell.vert(+x0: U32, +dx: U32, +c: U32) -> U32:
  (x0 + ((dx * c : U32) / 131072 : U32) : U32)

def Ell.segs(tab: List<&2, U32>, +x0: U32, +y0: U32, +dx: U32, +dy: U32, +px: U32, +py: U32, +fx: U32, +fy: U32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match tab:
    case c <> sn <> rest:
      +qx = Ell.vert(x0, dx, c)
      +qy = Ell.vert(y0, dy, sn)
      Ell.segs(rest, x0, y0, dx, dy, qx, qy, fx, fy, Seg.split(px, py, qx, qy, acc))
    case _:
      Seg.split(px, py, fx, fy, acc)

# 영역에 내접하는 타원 (첫 꼭짓점 = 오른쪽 가운데).
def Ellipse.segs(r: Rect) -> List<&2, Seg>:
  match r:
    case Rect{+x0, +y0, +x1, +y1}:
      +dx = (x1 - x0 : U32)
      +dy = (y1 - y0 : U32)
      +fx = x1
      +fy = (y0 + (dy / 2 : U32) : U32)
      Ell.segs(Ell.tab(), x0, y0, dx, dy, fx, fy, fx, fy, Nil{})

def Path.clamp(path: List<&2, C.Pt>, +w: U32, +h: U32) -> List<&2, C.Pt>:
  match path:
    case Nil{}:
      Nil{}
    case C.Pt{x, y} <> rest:
      C.Pt{U32.min(x, (w - 1 : U32)), U32.min(y, (h - 1 : U32))} <> Path.clamp(rest, w, h)

def Path.div(path: List<&2, C.Pt>, +s: U32) -> List<&2, C.Pt>:
  match path:
    case Nil{}:
      Nil{}
    case C.Pt{x, y} <> rest:
      C.Pt{(x / s : U32), (y / s : U32)} <> Path.div(rest, s)

# 굵기 (지름, 픽셀): 형광펜 16·s, 나머지 3·s.
def Tool.rad(t: C.Tool, +s: U32) -> U32:
  match t:
    case C.THigh{}:
      (16 * s : U32)
    case _:
      (3 * s : U32)

# 형광펜의 빨강은 노랑(0xFFFFD60A)으로 칠한다: 기본 색이 빨강인데 빨간 형광펜은 거의 안 쓴다. 다른 색은 고른 대로 섞는다.
def High.px(c: C.Color) -> U32:
  match c:
    case C.CRed{}:
      4294956554
    case _:
      Color.px(c)

def Tool.ink(t: C.Tool, c: C.Color) -> Ink:
  match t:
    case C.THigh{}:
      IBlend{High.px(c)}
    case _:
      ISolid{Color.px(c)}

# 도구마다 획 조각. rect 는 원에만 (상자처럼 맞춘 영역), s 는 화살표 머리 길이(14·s)에만 쓴다.
def Stroke.segs(t: C.Tool, path: List<&2, C.Pt>, rect: Rect, +s: U32, +w: U32, +h: U32) -> List<&2, Seg>:
  match t:
    case C.TLine{}:
      Path.line(Path.ends(path))
    case C.TArrow{}:
      Path.arrow(Path.ends(path), (14 * s : U32), w, h)
    case C.TEllipse{}:
      Ellipse.segs(rect)
    case _:
      Path.polyline(path)

# 지우개
# =====
# 지우개 Op 하나는 그 끈 길이 닿은, 그때 보이는 그린 것을 모두 지운다. 그리기 전에 기록을 순서대로 풀어
# 보이는 Op 만 남기므로 앞선 지우개·되돌리기와 저절로 맞물린다. 닿음 = 지우개 꺾은선 조각과 그린 것 조각 사이
# 거리가 (그린 것 굵기/2 + 화면 4px) 이하. 모자이크는 영역을 화면 4px 넓힌 직사각형에 조각이 닿을 때.
# 자르기는 지우지 않는다. 정수 기하라 파이썬 기준 없이 검사는 "무엇이 남는가" 로 한다.

type Target is Data:
  TSegs{rr: U32, rc: U32, segs: List<&2, Seg>}
  TArea{r: Rect}
  TNone{}

def U32.neg(+v: U32) -> Bool:
  U32.is_ge(v, 2147483648)

def U32.pos(+v: U32) -> Bool:
  U32.is_gt(v, 0) && U32.is_lt(v, 2147483648)

# (b - a) × (p - a), 부호는 U32 감싸기의 맨 윗 비트
def Cross(+ax: U32, +ay: U32, +bx: U32, +by: U32, +px: U32, +py: U32) -> U32:
  (((bx - ax : U32) * (py - ay : U32) : U32) - ((by - ay : U32) * (px - ax : U32) : U32) : U32)

# 조각이 직사각형에 닿는가: 상자가 겹치고, 네 모서리가 조각의 직선 한쪽에 모두 있지는 않다.
def Seg.meets(s: Seg, r: Rect) -> Bool:
  match s r:
    case Seg{+ax, +ay, +bx, +by} Rect{+x0, +y0, +x1, +y1}:
      +c1 = Cross(ax, ay, bx, by, x0, y0)
      +c2 = Cross(ax, ay, bx, by, x1, y0)
      +c3 = Cross(ax, ay, bx, by, x0, y1)
      +c4 = Cross(ax, ay, bx, by, x1, y1)
      Bool.not(Rect.apart(Rect.norm(ax, ay, bx, by), Rect{x0, y0, x1, y1})) && Bool.not((U32.pos(c1) && U32.pos(c2) && U32.pos(c3) && U32.pos(c4)) || (U32.neg(c1) && U32.neg(c2) && U32.neg(c3) && U32.neg(c4)))

# 두 조각이 제대로 교차하는가 (끝점이 닿는 경우는 캡슐 판정이 잡는다).
def Seg.crosses(+ax: U32, +ay: U32, +bx: U32, +by: U32, +cx: U32, +cy: U32, +dx: U32, +dy: U32) -> Bool:
  +d1 = Cross(ax, ay, bx, by, cx, cy)
  +d2 = Cross(ax, ay, bx, by, dx, dy)
  +d3 = Cross(cx, cy, dx, dy, ax, ay)
  +d4 = Cross(cx, cy, dx, dy, bx, by)
  ((U32.pos(d1) && U32.neg(d2)) || (U32.neg(d1) && U32.pos(d2))) && ((U32.pos(d3) && U32.neg(d4)) || (U32.neg(d3) && U32.pos(d4)))

# 두 조각 사이 거리가 r 이하 (rr = (2r)²): 어느 끝점이 상대 캡슐 안이거나 교차한다. 걸러낸 뒤라 좌표 차가 작아 32비트 안이다.
def Seg.close(e: Seg, t: Seg, +rr: U32) -> Bool:
  match e t:
    case Seg{+ax, +ay, +bx, +by} Seg{+cx, +cy, +dx, +dy}:
      Seg.hit(Seg{cx, cy, dx, dy}, ax, ay, rr) || Seg.hit(Seg{cx, cy, dx, dy}, bx, by, rr) || Seg.hit(Seg{ax, ay, bx, by}, cx, cy, rr) || Seg.hit(Seg{ax, ay, bx, by}, dx, dy, rr) || Seg.crosses(ax, ay, bx, by, cx, cy, dx, dy)

def Segs.close(ts: List<&2, Seg>, +e: Seg, +rr: U32, acc: Bool) -> Bool:
  match ts acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case t <> rest False{}:
      Segs.close(rest, e, rr, Seg.close(e, t, rr))

# 조각의 상자 (왼쪽 위와 한 변)
def Seg.box(e: Seg) -> U32 & U32 & U32:
  match e:
    case Seg{+ax, +ay, +bx, +by}:
      (U32.min(ax, bx), U32.min(ay, by), (U32.max(U32.absdiff(ax, bx), U32.absdiff(ay, by)) + 1 : U32))

def Target.seg(+e: Seg, +rr: U32, +rc: U32, ts: List<&2, Seg>, box: U32 & U32 & U32) -> Bool:
  (x, y, n) = box
  Segs.close(Segs.near(ts, x, y, n, rc), e, rr, False{})

def Target.segs(es: List<&2, Seg>, +rr: U32, +rc: U32, +ts: List<&2, Seg>, acc: Bool) -> Bool:
  match es acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case +e <> rest False{}:
      Target.segs(rest, rr, rc, ts, Target.seg(e, rr, rc, ts, Seg.box(e)))

def Target.area(es: List<&2, Seg>, +r: Rect, acc: Bool) -> Bool:
  match es acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case e <> rest False{}:
      Target.area(rest, r, Seg.meets(e, r))

def Segs.bbox.go(segs: List<&2, Seg>, +x0: U32, +y0: U32, +x1: U32, +y1: U32) -> Rect:
  match segs:
    case Nil{}:
      Rect{x0, y0, x1, y1}
    case Seg{+ax, +ay, +bx, +by} <> rest:
      Segs.bbox.go(rest, U32.min(x0, U32.min(ax, bx)), U32.min(y0, U32.min(ay, by)), U32.max(x1, U32.max(ax, bx)), U32.max(y1, U32.max(ay, by)))

def Segs.bbox(segs: List<&2, Seg>) -> Rect:
  Segs.bbox.go(segs, 4294967295, 4294967295, 0, 0)

def Rect.grow(r: Rect, +m: U32) -> Rect:
  match r:
    case Rect{+x0, +y0, +x1, +y1}:
      Rect{U32.sat(x0, m), U32.sat(y0, m), (x1 + m : U32), (y1 + m : U32)}

def Target.bbox(tg: Target) -> Rect:
  match tg:
    case TSegs{_, _, segs}:
      Segs.bbox(segs)
    case TArea{r}:
      r
    case TNone{}:
      Rect.empty()

# 상자부터 거르고(ebox 는 지우개 조각 상자를 넉넉히 넓힌 것) 조각끼리 잰다.
def Target.hit.go(tg: Target, es: List<&2, Seg>, apart: Bool) -> Bool:
  match tg apart:
    case _ True{}:
      False{}
    case TNone{} _:
      False{}
    case TArea{r} _:
      Target.area(es, r, False{})
    case TSegs{rr, rc, ts} _:
      Target.segs(es, rr, rc, ts, False{})

def Target.hit(+tg: Target, es: List<&2, Seg>, ebox: Rect) -> Bool:
  Target.hit.go(tg, es, Rect.apart(ebox, Target.bbox(tg)))

# 네모 띠 = 테두리 네 변 (굵기 6s 캡슐이 안쪽 3s 띠를 덮는다)
def Box.segs(r: Rect) -> List<&2, Seg>:
  match r:
    case Rect{+x0, +y0, +x1, +y1}:
      Seg.split(x0, y0, x1, y0, Seg.split(x1, y0, x1, y1, Seg.split(x1, y1, x0, y1, Seg.split(x0, y1, x0, y0, Nil{}))))

# 화면 4px 여유 (지름으로 8d). 거리 계산이 32비트 안에 들도록 64 까지만 (d ≥ 8 이면 화면이 아주 작은 때다).
def Erase.margin(+d: U32) -> U32:
  U32.min((8 * d : U32), 64)

def Target.of(+rad: U32, +d: U32, segs: List<&2, Seg>) -> Target:
  +rr = (rad + Erase.margin(d) : U32)
  TSegs{(rr * rr : U32), ((rr + 1 : U32) / 2 : U32), segs}

def Op.target(+t: C.Tool, +path: List<&2, C.Pt>, +w: U32, +h: U32, +s: U32, +d: U32) -> Target:
  match t:
    case C.TCrop{}:
      TNone{}
    case C.TErase{}:
      TNone{}
    case C.TMosaic{}:
      TArea{Rect.grow(Op.area(path, w, h, d), (Erase.margin(d) / 2 : U32))}
    case C.TBox{}:
      Target.of((6 * s : U32), d, Box.segs(Op.area(path, w, h, d)))
    case _:
      Target.of(Tool.rad(t, s), d, Stroke.segs(t, Path.clamp(path, w, h), Op.area(path, w, h, d), s, w, h))

def Erase.segs(path: List<&2, C.Pt>, +w: U32, +h: U32) -> List<&2, Seg>:
  Path.polyline(Path.clamp(path, w, h))

def Erase.cons(keep: Bool, op: C.Op, rest: List<&2, C.Op>) -> List<&2, C.Op>:
  match keep:
    case True{}:
      op <> rest
    case False{}:
      rest

# 보이는 Op (최근 것이 앞) 에서 지우개 길에 닿은 것을 뺀다.
def Erase.keep(vis: List<&2, C.Op>, +es: List<&2, Seg>, +ebox: Rect, +w: U32, +h: U32, +s: U32, +d: U32) -> List<&2, C.Op>:
  match vis:
    case Nil{}:
      Nil{}
    case C.Op{+t, c, +path} <> rest:
      Erase.cons(Bool.not(Target.hit(Op.target(t, path, w, h, s, d), es, ebox)), C.Op{t, c, path}, Erase.keep(rest, es, ebox, w, h, s, d))

def Erase.ebox(+es: List<&2, Seg>) -> Rect:
  Rect.grow(Segs.bbox(es), 128)

# 살아 있는 Op (오래된 것부터) -> 보이는 Op (오래된 것부터). vis 는 최근 것이 앞.
def Erase.resolve(ops: List<&2, C.Op>, vis: List<&2, C.Op>, +w: U32, +h: U32, +s: U32, +d: U32) -> List<&2, C.Op>:
  match ops:
    case Nil{}:
      List.reverse(&2, C.Op, vis)
    case C.Op{C.TErase{}, _, path} <> rest:
      +es = Erase.segs(path, w, h)
      Erase.resolve(rest, Erase.keep(vis, es, Erase.ebox(es), w, h, s, d), w, h, s, d)
    case op <> rest:
      Erase.resolve(rest, op <> vis, w, h, s, d)

def Erase.any(vis: List<&2, C.Op>, +es: List<&2, Seg>, +ebox: Rect, +w: U32, +h: U32, +s: U32, +d: U32, acc: Bool) -> Bool:
  match vis acc:
    case _ True{}:
      True{}
    case Nil{} False{}:
      False{}
    case C.Op{t, _, path} <> rest False{}:
      Erase.any(rest, es, ebox, w, h, s, d, Target.hit(Op.target(t, path, w, h, s, d), es, ebox))

# 경계용: 이 길로 지우면 보이는 것 가운데 닿는 게 있는가 (없으면 빈 떼기라 Op 가 안 된다).
def Erase.touches(live: List<&2, C.Op>, path: List<&2, C.Pt>, +w: U32, +h: U32, +s: U32, +d: U32) -> Bool:
  +es = Erase.segs(path, w, h)
  Erase.any(Erase.resolve(live, Nil{}, w, h, s, d), es, Erase.ebox(es), w, h, s, d, False{})

# 그리기: (원본, 살아 있는 Op 오래된 것부터) -> 전체 그림과 마지막 자르기
# ===================================================================

def Render.op(+w: U32, +h: U32, +k: Nat, +s: U32, +d: U32, img: Image, +tool: C.Tool, color: C.Color, +path: List<&2, C.Pt>) -> Image:
  match tool:
    case C.TBox{}:
      +r = Op.area(path, w, h, d)
      Paint.run(k, img, PBox{r, Rect.inset(r, (3 * s : U32)), Color.px(color)})
    case C.TMosaic{}:
      Paint.run(k, img, PMosaic{Shape.bd(s), Op.area(path, w, h, d), w, h})
    case C.TCrop{}:
      img
    case C.TErase{}:
      img
    case _:
      Stroke.draw(k, img, Tool.rad(tool, s), Tool.ink(tool, color), Stroke.segs(tool, Path.clamp(path, w, h), Op.area(path, w, h, d), s, w, h))

def Render.go(ops: List<&2, C.Op>, +w: U32, +h: U32, +k: Nat, +s: U32, +d: U32, img: Image, crop: Maybe<&2, Rect>) -> Image & Maybe<&2, Rect>:
  match ops:
    case Nil{}:
      (img, crop)
    case C.Op{C.TCrop{}, _, path} <> rest:
      Render.go(rest, w, h, k, s, d, img, Some{Op.area(path, w, h, d)})
    case C.Op{tool, color, path} <> rest:
      Render.go(rest, w, h, k, s, d, Render.op(w, h, k, s, d, img, tool, color, path), crop)

# 지우개를 먼저 풀어 보이는 Op 만 순서대로 칠한다 (모자이크는 제 아래 픽셀을 그대로 본다).
def Render.all(ops: List<&2, C.Op>, +w: U32, +h: U32, +k: Nat, +s: U32, +d: U32, img: Image) -> Image & Maybe<&2, Rect>:
  Render.go(Erase.resolve(ops, Nil{}, w, h, s, d), w, h, k, s, d, img, None{})

def Doc.build(sh: Shape, base: Image, +full: Image, +crop: Maybe<&2, Rect>) -> Doc:
  match sh:
    case Shape{w, h, +k, s, +d, td, hdr}:
      Doc{Shape{w, h, k, s, d, td, hdr}, base, full, Dim.view(Shape.vd(k, d), d, Shape.view(k, d, full), crop), crop}

def Doc.fin(sh: Shape, base: Image, r: Image & Maybe<&2, Rect>) -> Doc:
  (full, crop) = r
  Doc.build(sh, base, full, crop)

# 그림은 언제나 원본과 살아 있는 Op 에서 새로 만든다 (규칙 6·7).
def Doc.render(sh: Shape, base: Image, ops: List<&2, C.Op>) -> Doc:
  match sh:
    case Shape{+w, +h, +k, +s, +d, td, hdr}:
      +b = {base : Image}
      Doc.fin(Shape{w, h, k, s, d, td, hdr}, b, Render.all(ops, w, h, k, s, d, b))

def Doc.open(sh: Shape, base: Image, h: C.Hist) -> Doc:
  Doc.render(sh, base, C.Hist.live(h))

# BMP 읽기
# ========

# 파일 행 번호 <-> 그림 행 번호 (자기 자신이 역함수)
def Load.rowpos(topdown: Bool, +i: U32, +h: U32) -> U32:
  match topdown:
    case True{}:
      i
    case False{}:
      ((h - 1 : U32) - i : U32)

# 아래 행부터 읽어 앞에 붙이면 위에서부터의 순서가 된다. 읽기 결과를 매개변수로 받아야 머리에서 분해할 수 있다.
def Load.rows(n: Nat, fr: File & Result<&1, &1, U32 & String, List<&2, U32>>, +y: U32, +w: U32, +h: U32, +k: Nat, +td: Bool, +off: U32, +bpp: U32, acc: List<Strip>) -> IO(File & List<Strip>):
  match n fr:
    case _ Tuple{file, Fail{(code, msg)}}:
      IO.die(File & List<Strip>, code, "BMP 를 읽지 못했습니다: " ++ msg)
    case 0n Tuple{file, Done{bs}}:
      IO.pure(File & List<Strip>, (file, Row.strip(k, w, bpp, bs) <> acc))
    case 1n+p Tuple{file, Done{bs}}:
      +y2 = (y - 1 : U32)
      +rb = Bmp.rb(bpp, w)
      +pos = (off + (Load.rowpos(td, y2, h) * rb : U32) : U32)
      do IO<File & List<Strip>>:
        fr2 : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, pos, rb)
        Load.rows(p, fr2, y2, w, h, k, td, off, bpp, Row.strip(k, w, bpp, bs) <> acc)

def Load.start(file: File, sh: Shape, +off: U32, +bpp: U32) -> IO(File & List<Strip>):
  Shape{+w, +h, +k, _, _, +td, _} = sh
  +y = (h - 1 : U32)
  +rb = Bmp.rb(bpp, w)
  +pos = (off + (Load.rowpos(td, y, h) * rb : U32) : U32)
  do IO<File & List<Strip>>:
    fr : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, pos, rb)
    Load.rows(U32.to_nat(y), fr, y, w, h, k, td, off, bpp, Nil{})

def Load.finish(+sh: Shape, fl: File & List<Strip>) -> IO(Shape & Image):
  (file, rows) = fl
  do IO<Shape & Image>:
    File.close(file)
    return (sh, Build.image(Shape.k(sh), rows))

# 54바이트 BITMAPINFOHEADER, 32비트 BI_RGB, 행 순서(h 부호)는 원본대로
def Save.v3(+w: U32, +h: U32, +hraw: U32, +ppm: U32) -> List<&2, U32>:
  +size = ((w * h : U32) * 4 : U32)
  66 <> 77 <> Px.bytes((54 + size : U32), Px.bytes(0, Px.bytes(54, Px.bytes(40, Px.bytes(w, Px.bytes(hraw, Px.bytes(2097153, Px.bytes(0, Px.bytes(size, Px.bytes(ppm, Px.bytes(ppm, Px.bytes(0, Px.bytes(0, Nil{})))))))))))))

# 24비트 입력은 메모리에서 32비트가 되므로 저장용 헤더도 32비트로 바꿔 둔다.
def Bmp.hdr32(+bpp: U32, +w: U32, +h: U32, +hdr: List<&2, U32>) -> List<&2, U32>:
  match bpp:
    case 24:
      Save.v3(w, h, Bytes.u32(22n, hdr), Bytes.u32(38n, hdr))
    case _:
      hdr

def Load.body(fr: File & Result<&1, &1, U32 & String, List<&2, U32>>, sh: Shape, +off: U32, +bpp: U32) -> IO(Shape & Image):
  match fr sh:
    case (file, Fail{(code, msg)}) _:
      IO.die(Shape & Image, code, "BMP 헤더를 읽지 못했습니다: " ++ msg)
    case (file, Done{hdr}) Shape{+w, +h, k, s, d, td, _}:
      +sh2 = {Shape{w, h, k, s, d, td, Bmp.hdr32(bpp, w, h, hdr)} : Shape}
      do IO<Shape & Image>:
        fl : File & List<Strip> <- Load.start(file, sh2, off, bpp)
        Load.finish(sh2, fl)

def Bmp.signed(bs: List<&2, U32>) -> Bool:
  match bs:
    case 66 <> 77 <> _:
      True{}
    case _:
      False{}

# 검사 순서대로 첫 번째 어긋난 것만 알린다.
def Bmp.verdict(sig: Bool, hs: Bool, dims: Bool, small: Bool, bpp: Bool, comp: Bool, fits: Bool, ok: Shape & (U32 & U32)) -> Result<&1, &1, String, Shape & (U32 & U32)>:
  match sig hs dims small bpp comp fits:
    case False{} _ _ _ _ _ _:
      Fail{"BMP 파일이 아닙니다 (BM 서명이 없습니다)"}
    case _ False{} _ _ _ _ _:
      Fail{"BMP 헤더가 너무 짧거나 모르는 형식입니다"}
    case _ _ False{} _ _ _ _:
      Fail{"BMP 너비나 높이가 0 입니다"}
    case _ _ _ False{} _ _ _:
      Fail{"BMP 가 너무 큽니다 (한 변 16384 픽셀까지)"}
    case _ _ _ _ False{} _ _:
      Fail{"24비트나 32비트 BMP 만 지원합니다"}
    case _ _ _ _ _ False{} _:
      Fail{"압축된 BMP 는 지원하지 않습니다 (BI_RGB 또는 표준 마스크의 BI_BITFIELDS 만)"}
    case _ _ _ _ _ _ False{}:
      Fail{"BMP 파일이 잘려 있습니다 (픽셀 자료가 모자랍니다)"}
    case _ _ _ _ _ _ _:
      Done{ok}

# 헤더 앞 70바이트(V4 색 마스크까지)와 파일 크기만으로 모양을 정하는 순수 검사. 결과는 (모양, (자료 위치, bpp)).
def Bmp.header(+bs: List<&2, U32>, +size: U32) -> Result<&1, &1, String, Shape & (U32 & U32)>:
  +off = Bytes.u32(10n, bs)
  +hs = Bytes.u32(14n, bs)
  +w = Bytes.u32(18n, bs)
  +hraw = Bytes.u32(22n, bs)
  +bpp = (Bytes.u32(28n, bs) .&. 65535 : U32)
  +comp = Bytes.u32(30n, bs)
  +ppm = Bytes.u32(38n, bs)
  +neg = U32.is_ge(hraw, 2147483648)
  +h = Bool.pick(U32, neg, (0 - hraw : U32), hraw)
  +m = U32.max(w, h)
  +s = Bool.pick(U32, U32.is_gt(ppm, 4000), 2, 1)
  +k = Shape.depth(32n, 0n, m, U32.is_le(m, 1))
  +masks = U32.is_eq(Bytes.u32(54n, bs), 16711680) && U32.is_eq(Bytes.u32(58n, bs), 65280) && U32.is_eq(Bytes.u32(62n, bs), 255)
  +small = U32.is_le(w, 16384) && U32.is_le(h, 16384)
  +fits = U32.is_le(off, size) && U32.is_le((Bmp.rb(bpp, w) * h : U32), (size - off : U32))
  Bmp.verdict(Bmp.signed(bs), U32.is_ge(hs, 40), U32.is_gt(w, 0) && U32.is_gt(h, 0), small, U32.is_eq(bpp, 32) || U32.is_eq(bpp, 24), U32.is_eq(comp, 0) || (U32.is_eq(comp, 3) && masks), fits, (Shape{w, h, k, s, s, neg, Nil{}}, (off, bpp)))

def Load.checked(file: File, hd: Result<&1, &1, String, Shape & (U32 & U32)>) -> IO(Shape & Image):
  match hd:
    case Fail{msg}:
      IO.die(Shape & Image, 1, msg)
    case Done{(sh, (+off, bpp))}:
      do IO<Shape & Image>:
        fr : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, 0, off)
        Load.body(fr, sh, off, bpp)

def Load.head(fr: File & Result<&1, &1, U32 & String, List<&2, U32>>, +size: U32) -> IO(Shape & Image):
  match fr:
    case (file, Fail{(code, msg)}):
      IO.die(Shape & Image, code, "BMP 헤더를 읽지 못했습니다: " ++ msg)
    case (file, Done{bs}):
      Load.checked(file, Bmp.header(bs, size))

def Load.sized(fs: File & Result<&1, &1, U32 & String, U32>) -> IO(Shape & Image):
  match fs:
    case (file, Fail{(code, msg)}):
      IO.die(Shape & Image, code, "BMP 크기를 알 수 없습니다: " ++ msg)
    case (file, Done{size}):
      do IO<Shape & Image>:
        fr : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, 0, 70)
        Load.head(fr, size)

def Load.opened(+path: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Shape & Image):
  match opened:
    case Fail{(code, msg)}:
      IO.die(Shape & Image, code, "BMP 파일을 열지 못했습니다 (" ++ path ++ "): " ++ msg)
    case Done{file}:
      do IO<Shape & Image>:
        fs : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        Load.sized(fs)

def Load.open(+path: String) -> IO(Shape & Image):
  do IO<Shape & Image>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Load.opened(path, opened)

# BMP 쓰기
# ========
# 쓰기 실패는 죽지 않고 돌려준다: 창에서는 복사 실패로 알리고 편집을 이어 간다.

def Save.rows(n: Nat, fw: File & Result<&1, &1, U32 & String, Unit>, +i: U32, +img: Image, +xa: U32, +ya: U32, +w: U32, +h: U32, +k: Nat, +td: Bool) -> IO(Result<&1, &1, U32 & String, Unit>):
  match n fw:
    case _ Tuple{file, Fail{e}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        File.close(file)
        return Fail{e}
    case 0n Tuple{file, Done{_}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        File.close(file)
        return Done{Unit{}}
    case 1n+p Tuple{file, Done{_}}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        fw2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, Save.rowbytes(k, img, (ya + Load.rowpos(td, i, h) : U32), xa, ((xa + w : U32) - 1 : U32)))
        Save.rows(p, fw2, (i + 1 : U32), img, xa, ya, w, h, k, td)

def Save.zeros(n: Nat) -> List<&2, U32>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      0 <> Save.zeros(p)

# screencapture 가 쓰는 것과 같은 138바이트 V5 헤더 (BI_BITFIELDS, sRGB, 위에서부터의 행)
def Save.v5(+w: U32, +h: U32, +ppm: U32) -> List<&2, U32>:
  +size = ((w * h : U32) * 4 : U32)
  66 <> 77 <> Px.bytes((138 + size : U32), Px.bytes(0, Px.bytes(138, Px.bytes(124, Px.bytes(w, Px.bytes((0 - h : U32), Px.bytes(2097153, Px.bytes(3, Px.bytes(size, Px.bytes(ppm, Px.bytes(ppm, Px.bytes(0, Px.bytes(0, Px.bytes(16711680, Px.bytes(65280, Px.bytes(255, Px.bytes(4278190080, Px.bytes(1934772034, Save.zeros(64n)))))))))))))))))))

def Save.opened(opened: Result<&1, &1, U32 & String, File>, +k: Nat, img: Image, +xa: U32, +ya: U32, +w: U32, +h: U32, td: Bool, hdr: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match opened:
    case Fail{e}:
      IO.pure(Result<&1, &1, U32 & String, Unit>, Fail{e})
    case Done{file}:
      do IO<Result<&1, &1, U32 & String, Unit>>:
        fw : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, hdr)
        Save.rows(U32.to_nat(h), fw, 0, img, xa, ya, w, h, k, td)

def Save.go(path: String, +k: Nat, img: Image, +xa: U32, +ya: U32, +w: U32, +h: U32, td: Bool, hdr: List<&2, U32>) -> IO(Result<&1, &1, U32 & String, Unit>):
  do IO<Result<&1, &1, U32 & String, Unit>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "w")
    Save.opened(opened, k, img, xa, ya, w, h, td, hdr)

# 자를 영역이 없으면 원본 헤더와 행 순서를 그대로 써서 무편집 저장이 원본과 바이트까지 같다.
def Save.crop(path: String, +k: Nat, img: Image, +w: U32, +h: U32, +td: Bool, hdr: List<&2, U32>, crop: Maybe<&2, Rect>) -> IO(Result<&1, &1, U32 & String, Unit>):
  match crop:
    case None{}:
      Save.go(path, k, img, 0, 0, w, h, td, hdr)
    case Some{Rect{+x0, +y0, +x1, +y1}}:
      +cw = ((x1 - x0 : U32) + 1 : U32)
      +ch = ((y1 - y0 : U32) + 1 : U32)
      Save.go(path, k, img, x0, y0, cw, ch, True{}, Save.v5(cw, ch, Bytes.u32(38n, hdr)))

def Save.need(r: Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  match r:
    case Done{_}:
      IO.pure(Unit, Unit{})
    case Fail{(code, msg)}:
      IO.die(Unit, code, "BMP 를 쓰지 못했습니다: " ++ msg)

# 프로세스 결과, 클립보드, 알림
# ==========================

def Proc.ran(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> C.Ran:
  match r:
    case Fail{(code, msg)}:
      C.RFail{code, msg}
    case Done{(0, (out, _))}:
      C.ROk{out}
    case Done{(code, (_, err))}:
      C.RExit{code, err}

# Process.run 이 실행 실패로 돌려주는 errno 가운데 사용자에게 뜻이 있는 둘
def Proc.why(code: U32, msg: String) -> String:
  match code:
    case 60:
      "시간이 초과됐습니다"
    case 27:
      "출력이 너무 깁니다"
    case _:
      msg

def Cache.dir(home: String) -> String:
  home ++ "/Library/Caches/BendShot"

def Tmp.rm(path: String) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/rm", ["-f", path], "", 1024, 5000)
    IO.pure(Unit, Unit{})

def Notify.go(msg: String, quiet: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match quiet:
    case Done{_}:
      IO.pure(Unit, Unit{})
    case Fail{_}:
      do IO<Unit>:
        rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-e", "display notification \"" ++ msg ++ "\" with title \"BendShot\""], "", 65536, 60000)
        IO.pure(Unit, Unit{})

# BENDSHOT_QUIET 가 있으면 알림을 띄우지 않는다 (검사가 화면에 알림을 쏟지 않도록).
def Notify.show(msg: String) -> IO(Unit):
  do IO<Unit>:
    quiet : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDSHOT_QUIET")
    Notify.go(msg, quiet)

# 메뉴 막대 앱이 띄우면 stdout 을 아무도 안 보므로 알림으로도 띄운다.
def Shot.fail(+msg: String) -> IO(Unit):
  do IO<Unit>:
    IO.print_err(msg)
    Notify.show(msg)
    IO.exit(1)

def Proc.need(what: String, r: C.Ran) -> IO(Unit):
  match r:
    case C.ROk{_}:
      IO.pure(Unit, Unit{})
    case C.RExit{code, err}:
      Shot.fail(what ++ " 실패 (종료 코드 " ++ U32.show(code) ++ "): " ++ err)
    case C.RFail{code, msg}:
      Shot.fail(what ++ " 실패: " ++ Proc.why(code, msg))

# osascript 한 번에 클립보드 복사와 알림을 같이 한다 (프로세스 하나 덜 띄운다).
def Clip.send(png: String, +msg: String) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-e", "set the clipboard to (read (POSIX file \"" ++ png ++ "\") as «class PNGf»)", "-e", "display notification \"" ++ msg ++ "\" with title \"BendShot\""], "", 65536, 60000)
    Proc.need("클립보드 복사", Proc.ran(rc))
    IO.print(msg)

# 캡처 직후 경로용: 알림은 메뉴 막대 앱이 눌러서 편집할 수 있게 따로 띄운다.
def Clip.copy(png: String, +msg: String) -> IO(Unit):
  do IO<Unit>:
    rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-e", "set the clipboard to (read (POSIX file \"" ++ png ++ "\") as «class PNGf»)"], "", 65536, 60000)
    Proc.need("클립보드 복사", Proc.ran(rc))
    IO.print(msg)


# 명령줄 토큰
# ==========

def Tok.of(s: String, n: Maybe<&2, U32>) -> Tok:
  match n:
    case Some{v}:
      TNum{v}
    case None{}:
      TWord{s}

def Tok.show(t: Tok) -> String:
  match t:
    case TNum{n}:
      U32.show(n)
    case TWord{s}:
      s

def Tok.all(ss: List<String>) -> List<&2, Tok>:
  match ss:
    case +s <> rest:
      Tok.of(s, U32.read(s)) <> Tok.all(rest)
    case Nil{}:
      Nil{}

def Tok.words(ss: List<&2, String>) -> List<&2, Tok>:
  match ss:
    case +s <> rest:
      Tok.of(s, U32.read(s)) <> Tok.words(rest)
    case Nil{}:
      Nil{}

# 빈 줄은 토큰 없음 (String.split 은 빈 글자열을 빈 낱말 하나로 돌려준다).
def Line.toks(l: String) -> List<&2, Tok>:
  match l:
    case SNil{}:
      Nil{}
    case s:
      Tok.words(String.split(s, ' '))

def Lines.toks(ls: List<&2, String>) -> List<&2, List<&2, Tok>>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> rest:
      Line.toks(l) <> Lines.toks(rest)

# 기록 파일 ops.txt
# ===============
# 엄격한 줄 형식: "bendshot-ops 1" / "done N" / Op N 줄 / "redo M" / Op M 줄 / 빈 줄 하나.
# Op 줄 = 도구 색 점수 x y x y ... (점은 기억된 순서 그대로, 맨 앞이 뗀 점). 하나라도 어긋나면 전체를 거부한다.

def Tool.name(t: C.Tool) -> String:
  match t:
    case C.TBox{}:
      "box"
    case C.TMosaic{}:
      "mosaic"
    case C.TCrop{}:
      "crop"
    case C.TPen{}:
      "pen"
    case C.THigh{}:
      "high"
    case C.TLine{}:
      "line"
    case C.TArrow{}:
      "arrow"
    case C.TEllipse{}:
      "ellipse"
    case C.TErase{}:
      "erase"

def Tool.read(s: String) -> Maybe<&2, C.Tool>:
  match s:
    case "box":
      Some{C.TBox{}}
    case "mosaic":
      Some{C.TMosaic{}}
    case "crop":
      Some{C.TCrop{}}
    case "pen":
      Some{C.TPen{}}
    case "high":
      Some{C.THigh{}}
    case "line":
      Some{C.TLine{}}
    case "arrow":
      Some{C.TArrow{}}
    case "ellipse":
      Some{C.TEllipse{}}
    case "erase":
      Some{C.TErase{}}
    case _:
      None{}

def Color.name(c: C.Color) -> String:
  match c:
    case C.CRed{}:
      "red"
    case C.CYellow{}:
      "yellow"
    case C.CGreen{}:
      "green"
    case C.CBlue{}:
      "blue"
    case C.CBlack{}:
      "black"
    case C.CWhite{}:
      "white"

def Color.read(s: String) -> Maybe<&2, C.Color>:
  match s:
    case "red":
      Some{C.CRed{}}
    case "yellow":
      Some{C.CYellow{}}
    case "green":
      Some{C.CGreen{}}
    case "blue":
      Some{C.CBlue{}}
    case "black":
      Some{C.CBlack{}}
    case "white":
      Some{C.CWhite{}}
    case _:
      None{}

def Pts.text(ps: List<&2, C.Pt>) -> String:
  match ps:
    case Nil{}:
      "\n"
    case C.Pt{x, y} <> rest:
      " " ++ U32.show(x) ++ " " ++ U32.show(y) ++ Pts.text(rest)

def Op.text(op: C.Op) -> String:
  match op:
    case C.Op{t, c, +path}:
      Tool.name(t) ++ " " ++ Color.name(c) ++ " " ++ Nat.show(List.length(&2, C.Pt, path)) ++ Pts.text(path)

def Ops.text(ops: List<&2, C.Op>) -> String:
  match ops:
    case Nil{}:
      ""
    case op <> rest:
      Op.text(op) ++ Ops.text(rest)

def Hist.text(h: C.Hist) -> String:
  match h:
    case C.Hist{+done, +redo}:
      "bendshot-ops 1\ndone " ++ Nat.show(List.length(&2, C.Op, done)) ++ "\n" ++ Ops.text(done) ++ "redo " ++ Nat.show(List.length(&2, C.Op, redo)) ++ "\n" ++ Ops.text(redo)

def Pts.cons(+x: U32, +y: U32, rest: Maybe<&2, List<&2, C.Pt>>) -> Maybe<&2, List<&2, C.Pt>>:
  match rest:
    case Some{ps}:
      Some{C.Pt{x, y} <> ps}
    case None{}:
      None{}

# 정확히 n 쌍, 그 뒤에는 아무것도 없어야 한다.
def Pts.read(n: Nat, ts: List<&2, Tok>) -> Maybe<&2, List<&2, C.Pt>>:
  match n ts:
    case 0n Nil{}:
      Some{Nil{}}
    case 1n+p TNum{x} <> TNum{y} <> rest:
      Pts.cons(x, y, Pts.read(p, rest))
    case _ _:
      None{}

def Pts.read1(n: Nat, ts: List<&2, Tok>) -> Maybe<&2, List<&2, C.Pt>>:
  match n:
    case 0n:
      None{}
    case 1n+p:
      Pts.read(1n+p, ts)

def Op.read(t: Maybe<&2, C.Tool>, c: Maybe<&2, C.Color>, p: Maybe<&2, List<&2, C.Pt>>) -> Maybe<&2, C.Op>:
  match t c p:
    case Some{t2} Some{c2} Some{p2}:
      Some{C.Op{t2, c2, p2}}
    case _ _ _:
      None{}

def Op.line(l: List<&2, Tok>) -> Maybe<&2, C.Op>:
  match l:
    case TWord{t} <> TWord{c} <> TNum{n} <> pts:
      Op.read(Tool.read(t), Color.read(c), Pts.read1(U32.to_nat(n), pts))
    case _:
      None{}

def Line.num(l: List<&2, Tok>, +word: String) -> Maybe<&2, U32>:
  match l:
    case TWord{w} <> TNum{n} <> Nil{}:
      Bool.pick(Maybe<&2, U32>, String.eq(w, word), Some{n}, None{})
    case _:
      None{}

def Lines.op(ls: List<&2, List<&2, Tok>>) -> Maybe<&2, C.Op>:
  match ls:
    case Nil{}:
      None{}
    case l <> _:
      Op.line(l)

# cur 는 ls 의 첫 줄을 Op 로 읽은 것 (다음 줄은 재귀 호출의 인자에서 읽는다: 계산값은 match 할 수 없다).
def Ops.read(n: Nat, ls: List<&2, List<&2, Tok>>, cur: Maybe<&2, C.Op>, acc: List<&2, C.Op>) -> Result<&1, &1, String, List<&2, C.Op> & List<&2, List<&2, Tok>>>:
  match n ls cur:
    case 0n rest _:
      Done{(List.reverse(&2, C.Op, acc), rest)}
    case 1n+p _ <> +rest Some{o}:
      Ops.read(p, rest, Lines.op(rest), o <> acc)
    case 1n+p _ _:
      Fail{"Op 줄을 읽지 못했거나 모자랍니다"}

def Hist.read.redo(done: List<&2, C.Op>, r: Result<&1, &1, String, List<&2, C.Op> & List<&2, List<&2, Tok>>>) -> Result<&1, &1, String, C.Hist>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{(redo, Nil{} <> Nil{})}:
      Done{C.Hist{done, redo}}
    case Done{_}:
      Fail{"파일 끝이 어긋납니다"}

def Hist.read.count(done: List<&2, C.Op>, m: Maybe<&2, U32>, +rest: List<&2, List<&2, Tok>>) -> Result<&1, &1, String, C.Hist>:
  match m:
    case Some{n}:
      Hist.read.redo(done, Ops.read(U32.to_nat(n), rest, Lines.op(rest), Nil{}))
    case None{}:
      Fail{"redo 줄이 어긋납니다"}

def Hist.read.done(r: Result<&1, &1, String, List<&2, C.Op> & List<&2, List<&2, Tok>>>) -> Result<&1, &1, String, C.Hist>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{(done, l <> rest)}:
      Hist.read.count(done, Line.num(l, "redo"), rest)
    case Done{(_, Nil{})}:
      Fail{"redo 줄이 없습니다"}

def Hist.read.head(ok: Bool, n: Maybe<&2, U32>, +rest: List<&2, List<&2, Tok>>) -> Result<&1, &1, String, C.Hist>:
  match ok n:
    case True{} Some{k}:
      Hist.read.done(Ops.read(U32.to_nat(k), rest, Lines.op(rest), Nil{}))
    case _ _:
      Fail{"머리 줄이 어긋납니다"}

def Line.is(l: List<&2, Tok>, +word: String, +n: U32) -> Bool:
  match l:
    case TWord{w} <> TNum{k} <> Nil{}:
      String.eq(w, word) && U32.is_eq(k, n)
    case _:
      False{}

def Hist.read.lines(ls: List<&2, List<&2, Tok>>) -> Result<&1, &1, String, C.Hist>:
  match ls:
    case l1 <> l2 <> rest:
      Hist.read.head(Line.is(l1, "bendshot-ops", 1), Line.num(l2, "done"), rest)
    case _:
      Fail{"머리 줄이 없습니다"}

def Hist.parse(s: String) -> Result<&1, &1, String, C.Hist>:
  Hist.read.lines(Lines.toks(String.lines(s)))

# 기록 파일 읽고 쓰기
# ================

# 저장에 실패하면 알리고 False 를 돌려준다 (셸이 저장 못 한 편집을 지키려고 기억한다).
def Store.warn(what: String, +msg: String) -> IO(Bool):
  +line = {what ++ " 저장하지 못했습니다: " ++ msg : String}
  do IO<Bool>:
    IO.print_err(line)
    Notify.show(line)
    return False{}

def Store.moved(what: String, r: C.Ran) -> IO(Bool):
  match r:
    case C.ROk{_}:
      IO.pure(Bool, True{})
    case C.RExit{_, err}:
      Store.warn(what, err)
    case C.RFail{code, msg}:
      Store.warn(what, Proc.why(code, msg))

def Store.save.fin(what: String, tmp: String, path: String, fw: File & Result<&1, &1, U32 & String, Unit>) -> IO(Bool):
  match fw:
    case (file, Fail{(_, msg)}):
      do IO<Bool>:
        File.close(file)
        Store.warn(what, msg)
    case (file, Done{_}):
      do IO<Bool>:
        File.close(file)
        mv : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/mv", ["-f", tmp, path], "", 1024, 5000)
        Store.moved(what, Proc.ran(mv))

def Store.save.go(tmp: String, path: String, text: String, r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Fail{(_, msg)}:
      Store.warn("기록을", msg)
    case Done{file}:
      do IO<Bool>:
        fw : File & Result<&1, &1, U32 & String, Unit> <- File.write(file, text)
        Store.save.fin("기록을", tmp, path, fw)

# 임시 파일에 다 쓴 뒤 옮긴다: 도중에 죽어도 옛 기록이 남는다.
def Store.save(+path: String, text: String) -> IO(Bool):
  +tmp = path ++ ".tmp"
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(tmp, "w")
    Store.save.go(tmp, path, text, r)

def Store.load.read(fr: File & Result<&1, &1, U32 & String, String>) -> IO(Result<&1, &1, String, C.Hist>):
  match fr:
    case (file, Fail{(_, msg)}):
      do IO<Result<&1, &1, String, C.Hist>>:
        File.close(file)
        return Fail{msg}
    case (file, Done{text}):
      do IO<Result<&1, &1, String, C.Hist>>:
        File.close(file)
        return Hist.parse(text)

def Store.load.sized(fs: File & Result<&1, &1, U32 & String, U32>) -> IO(Result<&1, &1, String, C.Hist>):
  match fs:
    case (file, Fail{(_, msg)}):
      do IO<Result<&1, &1, String, C.Hist>>:
        File.close(file)
        return Fail{msg}
    case (file, Done{size}):
      do IO<Result<&1, &1, String, C.Hist>>:
        fr : File & Result<&1, &1, U32 & String, String> <- File.read(file, size)
        Store.load.read(fr)

def Store.load.go(r: Result<&1, &1, U32 & String, File>) -> IO(Result<&1, &1, String, C.Hist>):
  match r:
    case Fail{(2, _)}:
      IO.pure(Result<&1, &1, String, C.Hist>, Done{C.Hist{Nil{}, Nil{}}})
    case Fail{(_, msg)}:
      IO.pure(Result<&1, &1, String, C.Hist>, Fail{msg})
    case Done{file}:
      do IO<Result<&1, &1, String, C.Hist>>:
        fs : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        Store.load.sized(fs)

# 파일이 없을 때(ENOENT = 2)만 빈 기록. 권한·입출력 오류나 망가진 내용은 거부한다 (빈 기록으로 열면
# 다음 자동 저장이 진짜 기록을 덮어쓰므로 호출한 쪽이 멈춘다).
def Store.load(path: String) -> IO(Result<&1, &1, String, C.Hist>):
  do IO<Result<&1, &1, String, C.Hist>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Store.load.go(r)

# 캡처 보관
# ========
# ~/Library/Caches/BendShot/captures/<YYYYMMDD-HHMMSS-무작위>/ 에 orig.png (편집기는 쓰지 않는다) 와 ops.txt.

def Cap.root(home: String) -> String:
  Cache.dir(home) ++ "/captures"

def Cap.dir(home: String, id: String) -> String:
  Cap.root(home) ++ "/" ++ id

def Cap.ops(dir: String) -> String:
  dir ++ "/ops.txt"

def Lines.full(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case SNil{} <> rest:
      Lines.full(rest)
    case l <> rest:
      l <> Lines.full(rest)

# find 가 찍은 한 줄 "00001700000000.300000000 <경로>/<id>/orig.png" 에서 id (orig.png 바로 앞 칸) 를 꺼낸다.
def Cap.id.of(ps: List<&2, String>) -> String:
  match ps:
    case Nil{}:
      ""
    case id <> "orig.png" <> Nil{}:
      id
    case _ <> rest:
      Cap.id.of(rest)

def Cap.ids.map(ls: List<&2, String>) -> List<&2, String>:
  match ls:
    case Nil{}:
      Nil{}
    case l <> rest:
      Cap.id.of(String.split(l, '/')) <> Cap.ids.map(rest)

# 줄 앞의 바뀐 시각(0 을 채운 20자, 소수 9자리 초)이 문자열 순서 = 시각 순서라 줄째로 정렬하면 최근 것이 앞이다.
# 같은 초에 찍은 캡처도 소수 초로 갈리고, 시각까지 같으면 경로(폴더 이름)가 큰 것이 앞이다.
def Cap.ids.of(r: C.Ran) -> List<&2, String>:
  match r:
    case C.ROk{out}:
      Cap.ids.map(List.sort(~String, ~String.is_ge, Lines.full(String.lines(out))))
    case _:
      Nil{}

# 최근 것이 앞. 순서는 폴더 이름이 아니라 orig.png 의 바뀐 시각이다 (편집기는 orig.png 를 쓰지 않으니 캡처 시각).
# orig.png 가 없는 폴더(찍는 중, 실패)는 목록에 없어 지우지도 열지도 않는다. 폴더가 없으면 빈 목록.
def Cap.ids(home: String) -> IO(List<&2, String>):
  do IO<List<&2, String>>:
    ls : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/find", [Cap.root(home), "-mindepth", "2", "-maxdepth", "2", "-name", "orig.png", "-exec", "/usr/bin/stat", "-f", "%020.9Fm %N", "{}", "+"], "", 1048576, 5000)
    return Cap.ids.of(Proc.ran(ls))

# 새 캡처 이름: 벽시계 시각(YYYYMMDD-HHMMSS) + 무작위 꼬리. IO.now() 는 부팅 뒤 밀리초라 쓰지 않는다.
def Cap.newid.of(r: C.Ran, +rnd: U32) -> IO(String):
  match r:
    case C.ROk{out}:
      IO.pure(String, String.take(out, 15n) ++ "-" ++ U32.show(U32.mod(rnd, 10000)))
    case C.RExit{code, err}:
      IO.die(String, 1, "시각 읽기 (date) 실패 (종료 코드 " ++ U32.show(code) ++ "): " ++ err)
    case C.RFail{code, msg}:
      IO.die(String, 1, "시각 읽기 (date) 실패: " ++ Proc.why(code, msg))

def Cap.newid() -> IO(String):
  do IO<String>:
    d : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/date", ["+%Y%m%d-%H%M%S"], "", 1024, 5000)
    rnd : U32 <- IO.try(U32, IO.random_u32())
    Cap.newid.of(Proc.ran(d), rnd)

def Cap.paths(+home: String, ids: List<&2, String>) -> List<String>:
  match ids:
    case Nil{}:
      Nil{}
    case id <> rest:
      Cap.dir(home, id) <> Cap.paths(home, rest)

def Cap.rm(paths: List<String>) -> IO(Unit):
  match paths:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case p <> rest:
      do IO<Unit>:
        rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/rm", "-rf" <> p <> rest, "", 1024, 30000)
        IO.pure(Unit, Unit{})

# 최근 30개만 남긴다.
def Cap.prune(+home: String) -> IO(Unit):
  do IO<Unit>:
    ids : List<&2, String> <- Cap.ids(home)
    Cap.rm(Cap.paths(home, List.drop(&2, String, ids, 30n)))

def Cap.load.bmp(+bmp: String, hist: C.Hist, r: C.Ran) -> IO(Result<&1, &1, String, (Shape & Image) & C.Hist>):
  match r:
    case C.ROk{_}:
      do IO<Result<&1, &1, String, (Shape & Image) & C.Hist>>:
        loaded : Shape & Image <- Load.open(bmp)
        Tmp.rm(bmp)
        return Done{(loaded, hist)}
    case C.RExit{code, err}:
      IO.pure(Result<&1, &1, String, (Shape & Image) & C.Hist>, Fail{"PNG 를 BMP 로 바꾸기 (sips) 실패 (종료 코드 " ++ U32.show(code) ++ "): " ++ err})
    case C.RFail{code, msg}:
      IO.pure(Result<&1, &1, String, (Shape & Image) & C.Hist>, Fail{"PNG 를 BMP 로 바꾸기 (sips) 실패: " ++ Proc.why(code, msg)})

def Cap.load.go(+home: String, +stamp: U32, dir: String, h: Result<&1, &1, String, C.Hist>) -> IO(Result<&1, &1, String, (Shape & Image) & C.Hist>):
  match h:
    case Fail{m}:
      IO.pure(Result<&1, &1, String, (Shape & Image) & C.Hist>, Fail{"기록 파일을 읽지 못해 열지 않습니다 (ops.txt 는 그대로 둠): " ++ m})
    case Done{hist}:
      +bmp = Cache.dir(home) ++ "/edit-" ++ U32.show(stamp) ++ ".bmp"
      do IO<Result<&1, &1, String, (Shape & Image) & C.Hist>>:
        rs : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/sips", ["-s", "format", "bmp", dir ++ "/orig.png", "--out", bmp], "", 65536, 60000)
        Cap.load.bmp(bmp, hist, Proc.ran(rs))

# 캡처 하나를 연다: ops.txt -> 기록 (망가졌으면 그림을 열지 않는다), orig.png -> 임시 BMP -> 그림.
def Cap.load(home: String, stamp: U32, +dir: String) -> IO(Result<&1, &1, String, (Shape & Image) & C.Hist>):
  do IO<Result<&1, &1, String, (Shape & Image) & C.Hist>>:
    h : Result<&1, &1, String, C.Hist> <- Store.load(Cap.ops(dir))
    Cap.load.go(home, stamp, dir, h)

# 미리보기 (captures/<id>/thumb.bmp)
# ===============================
# 긴 변 192, 비율 유지, 32비트 V5 BMP. 자동 저장마다 그 순간의 내보내기(마지막 자르기 안)에서 다시 만든다.
# 규칙 (파이썬 기준 구현과 바이트까지 같다): 칸 (tx, ty) 의 원본 자리는 (x0 + tx·cw/tw, y0 + ty·ch/th),
# 그 자리를 덮는 2^b 정렬 블록(b 는 192·2^b ≤ 긴 변인 최대, 블록은 그림 안만) 의 채널 평균(내림).

def Thumb.side() -> U32:
  192

# 목록 한 칸의 상자 192×120 (16:10). 더 긴 미리보기는 상자에 맞춰 줄인다.
def Thumb.boxh() -> U32:
  120

def Thumb.size(+cw: U32, +ch: U32) -> U32 & U32:
  Bool.pick(U32 & U32, U32.is_ge(cw, ch), (192, U32.max(((ch * 192 : U32) / cw : U32), 1)), (U32.max(((cw * 192 : U32) / ch : U32), 1), 192))

# more 는 192·2^(b+1) ≤ long (호출자가 셈한다).
def Thumb.lg(fuel: Nat, +b: Nat, +long: U32, more: Bool) -> Nat:
  match fuel more:
    case 1n+f True{}:
      Thumb.lg(f, 1n+b, long, U32.is_le((384 << (1n+b) : U32), long))
    case _ _:
      b

def Thumb.px(+k: Nat, full: Image, +w: U32, +h: U32, +b: Nat, +x: U32, +y: U32) -> U32:
  +bb = (1 << b : U32)
  +bx = ((x / bb : U32) * bb : U32)
  +by = ((y / bb : U32) * bb : U32)
  +half = ((1 << k : U32) >> 1n : U32)
  Image.avg(Image.sum(b, Image.sub(Nat.sub(k, b), k, full, bx, by, U32.is_ge(bx, half), U32.is_ge(by, half)), bx, by, w, h))

# 한 행의 BGRA 바이트: 오른쪽 픽셀부터 앞에 붙여 왼쪽이 앞에 온다.
def Thumb.row(n: Nat, +tx: U32, +ty: U32, +k: Nat, +full: Image, +w: U32, +h: U32, +b: Nat, +x0: U32, +y0: U32, +cw: U32, +ch: U32, +tw: U32, +th: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Thumb.row(p, (tx - 1 : U32), ty, k, full, w, h, b, x0, y0, cw, ch, tw, th, Px.bytes(Thumb.px(k, full, w, h, b, (x0 + ((tx * cw : U32) / tw : U32) : U32), (y0 + ((ty * ch : U32) / th : U32) : U32)), acc))

def Thumb.rows(n: Nat, +ty: U32, +k: Nat, +full: Image, +w: U32, +h: U32, +b: Nat, +x0: U32, +y0: U32, +cw: U32, +ch: U32, +tw: U32, +th: U32, acc: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match n:
    case 0n:
      acc
    case 1n+p:
      Thumb.rows(p, (ty - 1 : U32), k, full, w, h, b, x0, y0, cw, ch, tw, th, Thumb.row(U32.to_nat(tw), (tw - 1 : U32), ty, k, full, w, h, b, x0, y0, cw, ch, tw, th, Nil{}) <> acc)

# 만든 미리보기: 너비, 높이, 위에서부터의 행 바이트.
type Made is Data:
  Made{tw: U32, th: U32, rows: List<&2, List<&2, U32>>}

def Thumb.make.go(+k: Nat, full: Image, +w: U32, +h: U32, +x0: U32, +y0: U32, +cw: U32, +ch: U32, size: U32 & U32) -> Made:
  (+tw, +th) = size
  +long = U32.max(cw, ch)
  +b = Thumb.lg(8n, 0n, long, U32.is_le(384, long))
  Made{tw, th, Thumb.rows(U32.to_nat(th), (th - 1 : U32), k, full, w, h, b, x0, y0, cw, ch, tw, th, Nil{})}

def Thumb.region(crop: Maybe<&2, Rect>, +w: U32, +h: U32) -> Rect:
  match crop:
    case None{}:
      Rect{0, 0, (w - 1 : U32), (h - 1 : U32)}
    case Some{r}:
      r

def Thumb.make(+k: Nat, full: Image, +w: U32, +h: U32, r: Rect) -> Made:
  match r:
    case Rect{+x0, +y0, x1, y1}:
      +cw = ((x1 - x0 : U32) + 1 : U32)
      +ch = ((y1 - y0 : U32) + 1 : U32)
      Thumb.make.go(k, full, w, h, x0, y0, cw, ch, Thumb.size(cw, ch))

def Thumb.put(rows: List<&2, List<&2, U32>>, fw: File & Result<&1, &1, U32 & String, Unit>) -> IO(File & Result<&1, &1, U32 & String, Unit>):
  match rows fw:
    case Nil{} f:
      IO.pure(File & Result<&1, &1, U32 & String, Unit>, f)
    case _ Tuple{file, Fail{e}}:
      IO.pure(File & Result<&1, &1, U32 & String, Unit>, (file, Fail{e}))
    case r <> rest Tuple{file, Done{_}}:
      do IO<File & Result<&1, &1, U32 & String, Unit>>:
        fw2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, r)
        Thumb.put(rest, fw2)

def Thumb.save.go(tmp: String, path: String, hdr: List<&2, U32>, rows: List<&2, List<&2, U32>>, r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Fail{(_, msg)}:
      Store.warn("미리보기를", msg)
    case Done{file}:
      do IO<Bool>:
        fw : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(file, hdr)
        fw2 : File & Result<&1, &1, U32 & String, Unit> <- Thumb.put(rows, fw)
        Store.save.fin("미리보기를", tmp, path, fw2)

# 임시 파일에 다 쓴 뒤 옮긴다 (기록 파일과 같다).
def Thumb.save(+path: String, hdr: List<&2, U32>, rows: List<&2, List<&2, U32>>) -> IO(Bool):
  +tmp = path ++ ".tmp"
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, File> <- File.open(tmp, "w")
    Thumb.save.go(tmp, path, hdr, rows, r)

def Thumb.strips(rows: List<&2, List<&2, U32>>, +tw: U32) -> List<Strip>:
  match rows:
    case Nil{}:
      Nil{}
    case r <> rest:
      Row.strip(8n, tw, 32, r) <> Thumb.strips(rest, tw)

# 캡처 목록 한 칸. 미리보기가 없는 캡처는 상자 크기의 회색 한 픽셀 (자리 표시).
type Tile is Data:
  Tile{id: String, tw: U32, th: U32, img: Image}

# 오른쪽 캡처 목록. ids 는 모든 캡처 이름(최근 것이 앞), cur 는 열린 캡처의 번호(목록에 없으면 None), off 는 첫 칸의 번호(스크롤),
# acc 는 아직 한 칸이 안 된 스크롤 거리(화면 픽셀, 음수가 아래), tiles 는 창에 보이는 칸 off 부터 창에 들어가는 만큼.
type Caps is Data:
  Caps{cur: Maybe<&2, U32>, off: U32, acc: F32, ids: List<&2, String>, tiles: List<&2, Tile>}

def Tile.gray() -> U32:
  4282664004

def Tile.of(id: String, r: Maybe<&1, Shape & Image>) -> Tile:
  match r:
    case None{}:
      Tile{id, Thumb.side(), Thumb.boxh(), Pix{Tile.gray()}}
    case Some{(Shape{w, h, _, _, _, _, _}, img)}:
      Tile{id, w, h, img}

def Thumb.load.ok(path: String, sane: Bool) -> IO(Maybe<&1, Shape & Image>):
  match sane:
    case False{}:
      IO.pure(Maybe<&1, Shape & Image>, None{})
    case True{}:
      do IO<Maybe<&1, Shape & Image>>:
        loaded : Shape & Image <- Load.open(path)
        return Some{loaded}

# 헤더가 맞고 크기가 미리보기답게 작을 때만 읽는다 (망가진 미리보기 하나가 편집기를 죽이지 않도록).
def Thumb.load.checked(path: String, hd: Result<&1, &1, String, Shape & (U32 & U32)>) -> IO(Maybe<&1, Shape & Image>):
  match hd:
    case Fail{_}:
      IO.pure(Maybe<&1, Shape & Image>, None{})
    case Done{(Shape{+w, +h, _, _, _, _, _}, _)}:
      Thumb.load.ok(path, U32.is_le(w, 1024) && U32.is_le(h, 1024))

def Thumb.load.head(path: String, +size: U32, fr: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(Maybe<&1, Shape & Image>):
  match fr:
    case (file, Fail{_}):
      do IO<Maybe<&1, Shape & Image>>:
        File.close(file)
        return None{}
    case (file, Done{bs}):
      do IO<Maybe<&1, Shape & Image>>:
        File.close(file)
        Thumb.load.checked(path, Bmp.header(bs, size))

def Thumb.load.sized(path: String, fs: File & Result<&1, &1, U32 & String, U32>) -> IO(Maybe<&1, Shape & Image>):
  match fs:
    case (file, Fail{_}):
      do IO<Maybe<&1, Shape & Image>>:
        File.close(file)
        return None{}
    case (file, Done{size}):
      do IO<Maybe<&1, Shape & Image>>:
        fr : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, 0, 70)
        Thumb.load.head(path, size, fr)

def Thumb.load.go(path: String, r: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&1, Shape & Image>):
  match r:
    case Fail{_}:
      IO.pure(Maybe<&1, Shape & Image>, None{})
    case Done{file}:
      do IO<Maybe<&1, Shape & Image>>:
        fs : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        Thumb.load.sized(path, fs)

# 없거나 읽을 수 없으면 None (자리 표시).
def Thumb.load(+path: String) -> IO(Maybe<&1, Shape & Image>):
  do IO<Maybe<&1, Shape & Image>>:
    r : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    Thumb.load.go(path, r)

def Tiles.load(+home: String, ids: List<&2, String>) -> IO(List<&2, Tile>):
  match ids:
    case Nil{}:
      IO.pure(List<&2, Tile>, Nil{})
    case +id <> rest:
      do IO<List<&2, Tile>>:
        r : Maybe<&1, Shape & Image> <- Thumb.load(Cap.dir(home, id) ++ "/thumb.bmp")
        ts : List<&2, Tile> <- Tiles.load(home, rest)
        return Tile.of(id, r) <> ts

def Caps.index(ids: List<&2, String>, cap: Maybe<&2, String>, +i: U32) -> Maybe<&2, U32>:
  match ids cap:
    case Nil{} _:
      None{}
    case _ None{}:
      None{}
    case id <> rest Some{+c}:
      Bool.pick(Maybe<&2, U32>, String.eq(id, c), Some{i}, Caps.index(rest, Some{c}, (i + 1 : U32)))

# 스크롤 위치의 한계: 마지막 칸이 창의 맨 아래 자리에 오는 곳 (칸이 창보다 적으면 0).
def Caps.clamp(+off: U32, fit: Nat, total: Nat) -> U32:
  U32.min(off, U32.from_nat(Nat.sub(total, fit)))

# 이름 목록을 빌려 읽고 이름은 복사하는 도우미. Base 의 List.drop·take·get 은 목록을 소유해서, 같은 목록을 Caps 에도 두면
# List 가 프로그램 전체에서 공유 상태가 된다.
def Chr.copy(ch: Char) -> Char:
  match ch:
    case Chr{c}:
      Chr{c}

def Str.copy(s: String) -> String:
  match s:
    case SNil{}:
      SNil{}
    case SCon{ch, rest}:
      SCon{Chr.copy(ch), Str.copy(rest)}

def Name.copy(n: Maybe<&2, String>) -> Maybe<&2, String>:
  match n:
    case None{}:
      None{}
    case Some{s}:
      Some{Str.copy(s)}

def Ids.take(n: Nat, ids: List<&2, String>) -> List<&2, String>:
  match n ids:
    case 1n+p id <> rest:
      Str.copy(id) <> Ids.take(p, rest)
    case _ _:
      []

def Ids.window(at: Nat, +n: Nat, ids: List<&2, String>) -> List<&2, String>:
  match at ids:
    case 0n xs:
      Ids.take(n, xs)
    case 1n+p Nil{}:
      []
    case 1n+p _ <> rest:
      Ids.window(p, n, rest)

def Ids.get(at: Nat, ids: List<&2, String>) -> Maybe<&2, String>:
  match at ids:
    case _ Nil{}:
      None{}
    case 0n id <> _:
      Some{Str.copy(id)}
    case 1n+p _ <> rest:
      Ids.get(p, rest)

# 보이는 칸(off 부터 fit 개)의 미리보기만 읽는다 (칸 하나 ≈ 3ms 라 30개를 다 읽으면 열기가 느려진다).
def Caps.window(+home: String, cur: Maybe<&2, U32>, +off: U32, acc: F32, +ids: List<&2, String>, fit: Nat) -> IO(Caps):
  do IO<Caps>:
    tiles : List<&2, Tile> <- Tiles.load(home, Ids.window(U32.to_nat(off), fit, ids))
    return Caps{cur, off, acc, ids, tiles}

def Caps.of(+home: String, cap: Maybe<&2, String>, +fit: Nat, +off: U32, +ids: List<&2, String>) -> IO(Caps):
  Caps.window(home, Caps.index(ids, cap, 0), Caps.clamp(off, fit, List.length(&2, String, ids)), 0.0, ids, fit)

# 목록을 읽는다. fit 은 창에 들어가는 칸 수, off 는 지키고 싶은 스크롤 위치 (한계 안으로 잘린다). cap 은 지금 연 캡처 (없으면 None).
def Caps.load(+home: String, cap: Maybe<&2, String>, fit: Nat, off: U32) -> IO(Caps):
  do IO<Caps>:
    ids : List<&2, String> <- Cap.ids(home)
    Caps.of(home, cap, fit, off, ids)

def Caps.is(cur: Maybe<&2, U32>, +i: U32) -> Bool:
  match cur:
    case None{}:
      False{}
    case Some{c}:
      U32.is_eq(c, i)

def Caps.current(caps: Caps, +i: U32) -> Bool:
  match caps:
    case Caps{cur, _, _, _, _}:
      Caps.is(cur, i)

def Caps.set.go(+c: U32, +off: U32, tiles: List<&2, Tile>, t: Tile, above: Bool) -> List<&2, Tile>:
  match above:
    case True{}:
      tiles
    case False{}:
      List.set(&2, Tile, tiles, U32.to_nat((c - off : U32)), t)

def Caps.set(caps: Caps, t: Tile) -> Caps:
  match caps:
    case Caps{None{}, off, acc, ids, tiles}:
      Caps{None{}, off, acc, ids, tiles}
    case Caps{Some{+c}, +off, acc, ids, tiles}:
      Caps{Some{c}, off, acc, ids, Caps.set.go(c, off, tiles, t, U32.is_lt(c, off))}

# 스크롤 한 칸 몫 (화면 픽셀). 트랙패드는 scrollingDeltaY 가 점 단위라 한 번 쓸기(≈100~200)가 두세 칸, 마우스 휠은 눈금 몇 개가 한 칸.
def Scroll.step() -> U32:
  64

# 스크롤 거리를 쌓아 한 칸 몫마다 off 를 옮긴다 (scrollingDeltaY 는 내용을 올릴 때 음수라 음수가 아래). 남은 거리는 acc 에.
# 돌려주는 Bool 은 off 가 바뀌었는가 (바뀌면 보이는 칸을 다시 읽는다).
def Caps.scroll(caps: Caps, fit: Nat, dy: F32) -> Caps & Bool:
  match caps:
    case Caps{cur, +off, acc, +ids, tiles}:
      +sum = F32.add(acc, dy)
      +down = F32.is_lt(sum, 0.0)
      +px = F32.to_u32(F32.abs(sum))
      +n = (px / Scroll.step() : U32)
      +rem = U32.to_f32(U32.mod(px, Scroll.step()))
      +off2 = Bool.pick(U32, down, Caps.clamp((off + n : U32), fit, List.length(&2, String, ids)), U32.sat(off, n))
      (Caps{cur, off2, Bool.pick(F32, down, F32.sub(0.0, rem), rem), ids, tiles}, Bool.not(U32.is_eq(off, off2)))

def Caps.moved.go(home: String, fit: Nat, changed: Bool, caps: Caps) -> IO(Caps):
  match changed caps:
    case False{} c:
      IO.pure(Caps, c)
    case True{} Caps{cur, off, acc, ids, _}:
      Caps.window(home, cur, off, acc, ids, fit)

def Caps.moved(home: String, fit: Nat, cb: Caps & Bool) -> IO(Caps):
  (caps, changed) = cb
  Caps.moved.go(home, fit, changed, caps)

# 포인터가 목록 위(over)일 때만 넘긴다.
def Caps.wheel(home: String, caps: Caps, +fit: Nat, over: Bool, dy: F32) -> IO(Caps):
  match over:
    case False{}:
      IO.pure(Caps, caps)
    case True{}:
      Caps.moved(home, fit, Caps.scroll(caps, fit, dy))

# 자동 저장 때: 미리보기 파일을 다시 쓰고 열린 캡처의 칸을 바꾼다.
def Thumb.update(id: String, +dir: String, caps: Caps, made: Made, +ppm: U32) -> IO(Caps):
  match made:
    case Made{+tw, +th, +rows}:
      do IO<Caps>:
        ok : Bool <- Thumb.save(dir ++ "/thumb.bmp", Save.v5(tw, th, ppm), Rows.copy(rows))
        return Caps.set(caps, Tile{id, tw, th, Build.image(8n, Thumb.strips(rows, tw))})

# 캡처 때 한 번: sips 가 orig.png 를 긴 변 192 로 줄인다 (약 0.1초, 클립보드 복사 뒤라 체감 지연은 없다).
def Thumb.sips(+dir: String) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/sips", ["-Z", "192", "-s", "format", "bmp", dir ++ "/orig.png", "--out", dir ++ "/thumb.bmp"], "", 65536, 30000)
    ok : Bool <- Store.moved("미리보기를", Proc.ran(r))
    IO.pure(Unit, Unit{})

# 창 맞추기와 오른쪽 패널
# ====================
# 창 = 뷰(원본 ÷ 표시 배율 d) + 오른쪽 패널. 화면 크기를 읽어 (뷰 + 패널) 이 화면에 들 때까지 d 를 2배씩 올린다.
# 패널의 단추는 표 하나(Button 목록) 로, 그리기와 누른 자리 판정이 같은 표를 읽는다.

def Panel.w() -> U32:
  224

# 패널 내용(도구 3×3 + 색 한 줄 + 캡처 목록 두 칸) 이 다 보이는 최소 창 높이
def Panel.minh() -> U32:
  528

# 캡처 목록: 색 단추 아래 y = 272 부터 칸(192×120) 을 8px 띄워 아래로. 창 높이에 들어가는 칸 수 (나머지는 스크롤로).
def Tiles.fit(+wh: U32) -> Nat:
  U32.to_nat((U32.sat(wh, 272) / 128 : U32))

def Panel.bg() -> U32:
  4281545523

def Fit.ceil(+n: U32, +d: U32) -> U32:
  (((n + d : U32) - 1 : U32) / d : U32)

# 창 깊이: 2^fk >= max(창 너비, 창 높이) 인 최소 fk (Window.frame 이 창 크기로 셈하는 깊이와 같다)
def Fit.depth(+a: U32, +b: U32) -> Nat:
  +m = U32.max(a, b)
  Shape.depth(32n, 0n, m, U32.is_le(m, 1))

def Fit.winh(+h: U32, +d: U32) -> U32:
  U32.max(Fit.ceil(h, d), Panel.minh())

# 제목 막대 몫 (점)
def Fit.title() -> U32:
  40

def Fit.ok(+w: U32, +h: U32, +d: U32, +sw: U32, +sh: U32) -> Bool:
  U32.is_le((Fit.ceil(w, d) + Panel.w() : U32), sw) && U32.is_le((Fit.winh(h, d) + Fit.title() : U32), sh)

def Fit.go(fuel: Nat, +w: U32, +h: U32, +d: U32, +sw: U32, +sh: U32, fits: Bool) -> U32:
  match fuel fits:
    case _ True{}:
      d
    case 0n _:
      d
    case 1n+f False{}:
      +d2 = (d * 2 : U32)
      Fit.go(f, w, h, d2, sw, sh, Fit.ok(w, h, d2, sw, sh))

# 표시 배율 d = s·2^j, 창이 화면에 드는 최소 j (화면을 모르면 d = s). 2^8 배까지만 줄인다.
def Fit.d(+w: U32, +h: U32, +s: U32, screen: Maybe<&1, U32 & U32>) -> U32:
  match screen:
    case None{}:
      s
    case Some{(+sw, +sh)}:
      Fit.go(8n, w, h, s, sw, sh, Fit.ok(w, h, s, sw, sh))

def Fit.shape(sh: Shape, screen: Maybe<&1, U32 & U32>) -> Shape:
  match sh:
    case Shape{+w, +h, k, +s, _, td, hdr}:
      Shape{w, h, k, s, Fit.d(w, h, s, screen), td, hdr}

# "WxH" 엄격 해석: 숫자 둘, 둘 다 0 이 아니어야 한다.
def Screen.pair(a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Maybe<&1, U32 & U32>:
  match a b:
    case Some{+sw} Some{+sh}:
      Bool.pick(Maybe<&1, U32 & U32>, U32.is_gt(sw, 0) && U32.is_gt(sh, 0), Some{(sw, sh)}, None{})
    case _ _:
      None{}

def Screen.parts(ps: List<&2, String>) -> Maybe<&1, U32 & U32>:
  match ps:
    case a <> b <> Nil{}:
      Screen.pair(U32.read(a), U32.read(b))
    case _:
      None{}

def Screen.parse(s: String) -> Maybe<&1, U32 & U32>:
  Screen.parts(String.split(String.trim(s), 'x'))

def Screen.fallback(why: String) -> IO(Maybe<&1, U32 & U32>):
  do IO<Maybe<&1, U32 & U32>>:
    IO.print_err("화면 크기를 읽지 못해 1440×900 으로 봅니다: " ++ why)
    return Some{(1440, 900)}

def Screen.checked(p: Maybe<&1, U32 & U32>, why: String) -> IO(Maybe<&1, U32 & U32>):
  match p:
    case Some{v}:
      IO.pure(Maybe<&1, U32 & U32>, Some{v})
    case None{}:
      Screen.fallback(why)

def Screen.got(r: C.Ran) -> IO(Maybe<&1, U32 & U32>):
  match r:
    case C.ROk{+out}:
      Screen.checked(Screen.parse(out), "osascript 출력 " ++ out)
    case C.RExit{code, err}:
      Screen.fallback("osascript 종료 코드 " ++ U32.show(code) ++ ": " ++ err)
    case C.RFail{code, msg}:
      Screen.fallback("osascript 실행 실패: " ++ Proc.why(code, msg))

# 주 화면의 쓸 수 있는 영역(메뉴 막대·독 제외, 점) 을 한 번 읽는다 (약 0.1초).
def Screen.detect() -> IO(Maybe<&1, U32 & U32>):
  do IO<Maybe<&1, U32 & U32>>:
    rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-l", "JavaScript", "-e", "ObjC.import('AppKit'); var f = $.NSScreen.mainScreen.visibleFrame; Math.floor(f.size.width) + 'x' + Math.floor(f.size.height)"], "", 1024, 5000)
    Screen.got(Proc.ran(rc))

# BENDSHOT_SCREEN=WxH 가 있으면 감지 대신 쓴다 (검사용). 창 없는 길(--replay·--edit)은 변수가 없으면 맞추지 않는다.
def Screen.env(win: Bool, r: Result<&1, &1, U32 & String, String>) -> IO(Maybe<&1, U32 & U32>):
  match win r:
    case _ Done{+s}:
      Screen.checked(Screen.parse(s), "BENDSHOT_SCREEN=" ++ s)
    case True{} Fail{_}:
      Screen.detect()
    case False{} Fail{_}:
      IO.pure(Maybe<&1, U32 & U32>, None{})

def Screen.size(win: Bool) -> IO(Maybe<&1, U32 & U32>):
  do IO<Maybe<&1, U32 & U32>>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDSHOT_SCREEN")
    Screen.env(win, r)

def Fill.rect(+fk: Nat, img: Image, r: Rect, +color: U32) -> Image:
  Paint.run(fk, img, PBox{r, Rect.empty(), color})

# 패널 단추 하나: 창 좌표의 자리와 누르면 나오는 행동. 그리기와 판정이 이 표 하나를 읽는다.
type Button is Data:
  Button{x: U32, y: U32, w: U32, h: U32, act: C.Act}

# 도구 단추 60×60, 3열 (간격 8), 색 단추 28×28 한 줄. 뷰 너비 vw 오른쪽에 놓는다.
def Panel.tool(+vw: U32, +i: U32, t: C.Tool) -> Button:
  Button{((vw + 16 : U32) + (U32.mod(i, 3) * 68 : U32) : U32), (16 + ((i / 3 : U32) * 68 : U32) : U32), 60, 60, C.APick{t}}

def Panel.color(+vw: U32, +i: U32, c: C.Color) -> Button:
  Button{((vw + 16 : U32) + (i * 32 : U32) : U32), 228, 28, 28, C.AColor{c}}

# 창의 row 번째 자리에 놓인 목록 i 번 칸과 그 오른쪽 위 × (24×24, 칸 위에 겹친다: 표에서 뒤에 오므로 위에 그려지고 판정도 이긴다).
# i 는 전체 목록의 번호 (= 스크롤 위치 + row).
def Panel.tile(+vw: U32, +row: U32, i: U32) -> Button:
  Button{(vw + 16 : U32), (272 + (row * 128 : U32) : U32), Thumb.side(), Thumb.boxh(), C.AOpen{i}}

def Panel.del(+vw: U32, +row: U32, i: U32) -> Button:
  Button{(vw + 180 : U32), (276 + (row * 128 : U32) : U32), 24, 24, C.ADelete{i}}

def Panel.list(n: Nat, +vw: U32, +row: U32, +i: U32) -> List<&2, Button>:
  match n:
    case 0n:
      Nil{}
    case 1n+p:
      Panel.tile(vw, row, i) <> Panel.del(vw, row, i) <> Panel.list(p, vw, (row + 1 : U32), (i + 1 : U32))

# n 은 보이는 칸 수, off 는 첫 칸의 번호.
def Panel.buttons(+vw: U32, n: Nat, off: U32) -> List<&2, Button>:
  Panel.tool(vw, 0, C.TBox{}) <> Panel.tool(vw, 1, C.TMosaic{}) <> Panel.tool(vw, 2, C.TCrop{}) <>
  Panel.tool(vw, 3, C.TPen{}) <> Panel.tool(vw, 4, C.THigh{}) <> Panel.tool(vw, 5, C.TLine{}) <>
  Panel.tool(vw, 6, C.TArrow{}) <> Panel.tool(vw, 7, C.TEllipse{}) <> Panel.tool(vw, 8, C.TErase{}) <>
  Panel.color(vw, 0, C.CRed{}) <> Panel.color(vw, 1, C.CYellow{}) <> Panel.color(vw, 2, C.CGreen{}) <>
  Panel.color(vw, 3, C.CBlue{}) <> Panel.color(vw, 4, C.CBlack{}) <> Panel.color(vw, 5, C.CWhite{}) <>
  Panel.list(n, vw, 0, off)

def Button.has(b: Button, +x: U32, +y: U32) -> Bool:
  match b:
    case Button{+bx, +by, bw, bh, _}:
      U32.is_ge(x, bx) && U32.is_lt(x, (bx + bw : U32)) && U32.is_ge(y, by) && U32.is_lt(y, (by + bh : U32))

def Button.act(b: Button) -> C.Act:
  match b:
    case Button{_, _, _, _, a}:
      a

# 누른 자리의 단추 행동, 없으면 ANone. 겹치면 표에서 뒤의 것(위에 그려진 것)이 이긴다.
def Panel.hit(bs: List<&2, Button>, +x: U32, +y: U32, found: C.Act) -> C.Act:
  match bs:
    case Nil{}:
      found
    case +b <> rest:
      Panel.hit(rest, x, y, Bool.pick(C.Act, Button.has(b, x, y), Button.act(b), found))

def Color.idx(c: C.Color) -> U32:
  match c:
    case C.CRed{}:
      1
    case C.CYellow{}:
      2
    case C.CGreen{}:
      3
    case C.CBlue{}:
      4
    case C.CBlack{}:
      5
    case C.CWhite{}:
      6

# 단추의 행동이 지금 도구·색·열린 캡처인가 (켜진 표시용).
def Act.current(a: C.Act, t: C.Tool, c: C.Color, caps: Caps) -> Bool:
  match a:
    case C.APick{t2}:
      U32.is_eq(Tool.idx(t2), Tool.idx(t))
    case C.AColor{c2}:
      U32.is_eq(Color.idx(c2), Color.idx(c))
    case C.AOpen{i}:
      Caps.current(caps, i)
    case _:
      False{}

def Icon.cell(+fk: Nat, img: Image, +x0: U32, +y0: U32, +i: U32) -> Image:
  +dark = U32.is_eq(((i + (i / 4 : U32) : U32) .&. 1 : U32), 1)
  Fill.rect(fk, img, Rect.square((x0 + (U32.mod(i, 4) * 8 : U32) : U32), (y0 + ((i / 4 : U32) * 8 : U32) : U32), 8), Bool.pick(U32, dark, 4283453520, 4290822336))

def Icon.checker(n: Nat, +fk: Nat, img: Image, +x0: U32, +y0: U32, +i: U32) -> Image:
  match n:
    case 0n:
      img
    case 1n+p:
      Icon.checker(p, fk, Icon.cell(fk, img, x0, y0, i), x0, y0, (i + 1 : U32))

def Icon.red() -> Ink:
  ISolid{Color.px(C.CRed{})}

# 단추 (bx, by) 안 32×32 자리에 도구 그림: 기존 화가들로 그린다.
def Icon.tool(+fk: Nat, img: Image, t: C.Tool, +bx: U32, +by: U32) -> Image:
  match t:
    case C.TBox{}:
      Paint.run(fk, img, PBox{Rect{(bx + 14 : U32), (by + 16 : U32), (bx + 45 : U32), (by + 43 : U32)}, Rect.inset(Rect{(bx + 14 : U32), (by + 16 : U32), (bx + 45 : U32), (by + 43 : U32)}, 3), Color.px(C.CRed{})})
    case C.TMosaic{}:
      Icon.checker(16n, fk, img, (bx + 14 : U32), (by + 14 : U32), 0)
    case C.TCrop{}:
      Stroke.draw(fk, img, 3, ISolid{4294967295}, [Seg{(bx + 24 : U32), (by + 14 : U32), (bx + 14 : U32), (by + 14 : U32)}, Seg{(bx + 14 : U32), (by + 14 : U32), (bx + 14 : U32), (by + 24 : U32)}, Seg{(bx + 35 : U32), (by + 45 : U32), (bx + 45 : U32), (by + 45 : U32)}, Seg{(bx + 45 : U32), (by + 45 : U32), (bx + 45 : U32), (by + 35 : U32)}])
    case C.TPen{}:
      Stroke.draw(fk, img, 3, Icon.red(), Path.polyline([C.Pt{(bx + 45 : U32), (by + 18 : U32)}, C.Pt{(bx + 35 : U32), (by + 42 : U32)}, C.Pt{(bx + 24 : U32), (by + 18 : U32)}, C.Pt{(bx + 14 : U32), (by + 42 : U32)}]))
    case C.THigh{}:
      Stroke.draw(fk, img, 14, IBlend{High.px(C.CRed{})}, Path.line(Seg{(bx + 14 : U32), (by + 30 : U32), (bx + 45 : U32), (by + 30 : U32)}))
    case C.TLine{}:
      Stroke.draw(fk, img, 3, Icon.red(), Path.line(Seg{(bx + 14 : U32), (by + 45 : U32), (bx + 45 : U32), (by + 14 : U32)}))
    case C.TArrow{}:
      Stroke.draw(fk, img, 3, Icon.red(), Path.arrow(Seg{(bx + 14 : U32), (by + 45 : U32), (bx + 45 : U32), (by + 14 : U32)}, 10, 65535, 65535))
    case C.TEllipse{}:
      Stroke.draw(fk, img, 3, Icon.red(), Ellipse.segs(Rect{(bx + 14 : U32), (by + 16 : U32), (bx + 45 : U32), (by + 43 : U32)}))
    case C.TErase{}:
      Stroke.draw(fk, img, 16, ISolid{4293959872}, Path.line(Seg{(bx + 20 : U32), (by + 38 : U32), (bx + 40 : U32), (by + 22 : U32)}))

# 미리보기 칸 칠하기: Paint.go 와 같은 쿼드트리 걷기지만 원본 미리보기 src(깊이 8)를 빌려 읽기만 한다.
# 화가에 넣으면 그리기가 Caps 를 통째로 소유하게 되어 List 가 공유 상태가 된다.
# 각 픽셀은 원본 미리보기를 가장 가까운 점으로 뽑는다 (dw×dh 로 줄여 (ox, oy) 에 놓는다).
def Thumb.out(+d: Nat, +x: U32, +y: U32, +ox: U32, +oy: U32, +dw: U32, +dh: U32) -> Bool:
  Rect.apart(Rect.square(x, y, (1 << d : U32)), Rect{ox, oy, ((ox + dw : U32) - 1 : U32), ((oy + dh : U32) - 1 : U32)})

def Thumb.go(+d: Nat, img: Image, +x: U32, +y: U32, out: Bool, +src: Image, +tw: U32, +th: U32, +ox: U32, +oy: U32, +dw: U32, +dh: U32) -> Image:
  match d img out:
    case _ i True{}:
      i
    case 0n _ False{}:
      Pix{Image.at(8n, src, (((x - ox : U32) * tw : U32) / dw : U32), (((y - oy : U32) * th : U32) / dh : U32))}
    case 1n+p Pix{+c} False{}:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      +y2 = (y + half : U32)
      Qua{Thumb.go(p, Pix{c}, x, y, Thumb.out(p, x, y, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, Pix{c}, x2, y, Thumb.out(p, x2, y, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, Pix{c}, x, y2, Thumb.out(p, x, y2, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, Pix{c}, x2, y2, Thumb.out(p, x2, y2, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh)}
    case 1n+p Qua{tl, tr, bl, br} False{}:
      +half = (1 << p : U32)
      +x2 = (x + half : U32)
      +y2 = (y + half : U32)
      Qua{Thumb.go(p, tl, x, y, Thumb.out(p, x, y, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, tr, x2, y, Thumb.out(p, x2, y, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, bl, x, y2, Thumb.out(p, x, y2, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh),
          Thumb.go(p, br, x2, y2, Thumb.out(p, x2, y2, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh)}
    case _ i _:
      i

# 칸: 회색 바탕 위에 미리보기를 상자(192×120) 에 맞춰 가운데에. 높이가 120 을 넘으면 비율대로 줄인다.
def Tile.draw.go(+fk: Nat, img: Image, +bx: U32, +by: U32, +tw: U32, +th: U32, src: Image, size: U32 & U32) -> Image:
  (+dw, +dh) = size
  +ox = (bx + ((192 - dw : U32) / 2 : U32) : U32)
  +oy = (by + ((120 - dh : U32) / 2 : U32) : U32)
  Thumb.go(fk, img, 0, 0, Thumb.out(fk, 0, 0, ox, oy, dw, dh), src, tw, th, ox, oy, dw, dh)

def Tile.draw(+fk: Nat, img: Image, +bx: U32, +by: U32, t: Tile) -> Image:
  match t:
    case Tile{_, +tw, +th, src}:
      Tile.draw.go(fk, Fill.rect(fk, img, Rect{bx, by, (bx + 191 : U32), (by + 119 : U32)}, Tile.gray()), bx, by, tw, th, src, Bool.pick(U32 & U32, U32.is_le(th, 120), (tw, th), (((tw * 120 : U32) / th : U32), 120)))

# 보이는 칸 목록에서 at 번째 칸을 그린다 (없으면 그대로). 목록은 빌려 읽기만 한다.
def Tiles.draw(at: Nat, tiles: List<&2, Tile>, +fk: Nat, img: Image, +bx: U32, +by: U32) -> Image:
  match at tiles:
    case _ Nil{}:
      img
    case 0n t <> _:
      Tile.draw(fk, img, bx, by, t)
    case 1n+p _ <> rest:
      Tiles.draw(p, rest, fk, img, bx, by)

def Caps.draw.tile.go(above: Bool, at: Nat, tiles: List<&2, Tile>, +fk: Nat, img: Image, +bx: U32, +by: U32) -> Image:
  match above:
    case True{}:
      img
    case False{}:
      Tiles.draw(at, tiles, fk, img, bx, by)

# 번호 i 의 칸 그림: 보이는 칸(off 부터) 안에 있을 때만.
def Caps.draw.tile(+fk: Nat, img: Image, +bx: U32, +by: U32, caps: Caps, +i: U32) -> Image:
  match caps:
    case Caps{_, +off, _, _, tiles}:
      Caps.draw.tile.go(U32.is_lt(i, off), U32.to_nat((i - off : U32)), tiles, fk, img, bx, by)

# × 단추: 어두운 네모 위에 흰 대각선 둘.
def Icon.x(+fk: Nat, img: Image, +bx: U32, +by: U32) -> Image:
  Stroke.draw(fk, Fill.rect(fk, img, Rect{bx, by, (bx + 23 : U32), (by + 23 : U32)}, 4280295456), 2, ISolid{4294967295}, Seg.split((bx + 7 : U32), (by + 7 : U32), (bx + 16 : U32), (by + 16 : U32), Seg.split((bx + 16 : U32), (by + 7 : U32), (bx + 7 : U32), (by + 16 : U32), Nil{})))

def Icon.draw(+fk: Nat, img: Image, a: C.Act, +bx: U32, +by: U32, caps: Caps) -> Image:
  match a:
    case C.APick{t}:
      Icon.tool(fk, img, t, bx, by)
    case C.AColor{c}:
      Fill.rect(fk, img, Rect{bx, by, (bx + 27 : U32), (by + 27 : U32)}, Color.px(c))
    case C.AOpen{i}:
      Caps.draw.tile(fk, img, bx, by, caps, i)
    case C.ADelete{i}:
      Icon.x(fk, img, bx, by)
    case _:
      img

# 도구 단추는 어두운 바탕 위에 그림, 켜진 것은 흰 테 3px.
def Button.ring(+fk: Nat, img: Image, +bx: U32, +by: U32, +bw: U32, +bh: U32, on: Bool) -> Image:
  match on:
    case False{}:
      img
    case True{}:
      +r = {Rect{(bx - 3 : U32), (by - 3 : U32), ((bx + bw : U32) + 2 : U32), ((by + bh : U32) + 2 : U32)} : Rect}
      Paint.run(fk, img, PBox{r, Rect.inset(r, 3), 4294967295})

def Button.base(+fk: Nat, img: Image, +bx: U32, +by: U32, +bw: U32, +bh: U32, tool: Bool) -> Image:
  match tool:
    case True{}:
      Fill.rect(fk, img, Rect{bx, by, ((bx + bw : U32) - 1 : U32), ((by + bh : U32) - 1 : U32)}, 4282664004)
    case False{}:
      img

def Button.draw(+fk: Nat, img: Image, b: Button, t: C.Tool, c: C.Color, +caps: Caps) -> Image:
  match b:
    case Button{+bx, +by, +bw, +bh, +a}:
      Button.ring(fk, Icon.draw(fk, Button.base(fk, img, bx, by, bw, bh, U32.is_eq(bw, 60)), a, bx, by, caps), bx, by, bw, bh, Act.current(a, t, c, caps))

def Buttons.draw(bs: List<&2, Button>, +fk: Nat, img: Image, +t: C.Tool, +c: C.Color, +caps: Caps) -> Image:
  match bs:
    case Nil{}:
      img
    case b <> rest:
      Buttons.draw(rest, fk, Button.draw(fk, img, b, t, c, caps), t, c, caps)

# 패널: 뷰 오른쪽과 (뷰가 패널보다 낮으면) 아래를 배경으로 채운 뒤 단추 표(도구·색·캡처 목록)를 그린다.
def Panel.draw(+fk: Nat, img: Image, +vw: U32, +vh: U32, +wh: U32, t: C.Tool, c: C.Color, caps: Caps) -> Image:
  match caps:
    case Caps{cur, +off, acc, ids, +tiles}:
      Buttons.draw(Panel.buttons(vw, List.length(&2, Tile, tiles), off), fk, Fill.rect(fk, Fill.rect(fk, img, Rect{vw, 0, ((vw + Panel.w() : U32) - 1 : U32), (wh - 1 : U32)}, Panel.bg()), Rect{0, vh, (vw - 1 : U32), (wh - 1 : U32)}, Panel.bg()), t, c, Caps{cur, off, acc, ids, tiles})

# 제목과 미리보기
# =============

def Title.mark(sel: Bool) -> String:
  match sel:
    case True{}:
      " ✓"
    case False{}:
      ""

def Color.kname(c: C.Color) -> String:
  match c:
    case C.CRed{}:
      "빨강"
    case C.CYellow{}:
      "노랑"
    case C.CGreen{}:
      "초록"
    case C.CBlue{}:
      "파랑"
    case C.CBlack{}:
      "검정"
    case C.CWhite{}:
      "흰색"

def Title.line(+i: U32, color: String) -> String:
  "Bend 캡처 · [1] 네모" ++ Title.mark(U32.is_eq(i, 1)) ++ "  [2] 모자이크" ++ Title.mark(U32.is_eq(i, 2)) ++ "  [3] 자르기" ++ Title.mark(U32.is_eq(i, 3)) ++ "  [4] 펜" ++ Title.mark(U32.is_eq(i, 4)) ++ "  [5] 형광펜" ++ Title.mark(U32.is_eq(i, 5)) ++ "  [6] 직선" ++ Title.mark(U32.is_eq(i, 6)) ++ "  [7] 화살표" ++ Title.mark(U32.is_eq(i, 7)) ++ "  [8] 원" ++ Title.mark(U32.is_eq(i, 8)) ++ "  [9] 지우개" ++ Title.mark(U32.is_eq(i, 9)) ++ "  색 " ++ color ++ "  Z 되돌리기  Y 다시 실행  Enter 복사  Esc 닫기"

def Title.tools(t: C.Tool, c: C.Color) -> String:
  Title.line(Tool.idx(t), Color.kname(c))

# lost: 마지막 자동 저장이 실패했다 (닫으면 저장 못 한 편집이 사라진다).
def Title.of(t: C.Tool, c: C.Color, armed: Bool, lost: Bool) -> String:
  match armed lost:
    case True{} True{}:
      "저장에 실패했습니다 · Esc 를 한 번 더 누르면 닫히고 저장 못 한 편집이 사라집니다 (Enter 는 복사)"
    case True{} False{}:
      "편집한 게 있습니다 · Esc 를 한 번 더 누르면 닫힙니다 (Enter 는 복사)"
    case False{} _:
      Title.tools(t, c)

# 처음 제목 (도구 = 빨간 네모, 경고 없음)
def Title.first() -> String:
  Title.of(C.TBox{}, C.CRed{}, False{}, False{})

# 복사하는 동안의 제목 (5K 캡처는 내보내기·PNG 변환·클립보드에 1~2초가 걸린다)
def Title.busy() -> String:
  "복사 중…"

# 화면에 필요한 핵심 상태 조각. 기록은 그대로 돌려주고, 끌던 길은 복사한다 (둘이 나눠 가지면 List 가 공유 상태가 된다).
def Ui.scene(ui: C.Ui) -> C.Ui & (C.Tool & C.Color & C.Drag & Bool):
  match ui:
    case C.Ui{h, +t, +c, +d, di, he, +ar}:
      (C.Ui{h, t, c, d, di, he, ar}, (t, c, C.Drag.copy(d), ar))

def Shot.outline(+vd: Nat, view: Image, +r: Rect, +t: U32, +color: U32) -> Image:
  Paint.run(vd, view, PBox{r, Rect.inset(r, t), color})

# 끌던 길은 원본 좌표라 표시 배율로 나눈다. 획 도구는 화면 배율의 획을 그대로 그린다.
def Preview.tool(+vd: Nat, +d: U32, +w: U32, +h: U32, view: Image, +t: C.Tool, c: C.Color, +path: List<&2, C.Pt>) -> Image:
  match t:
    case C.TBox{}:
      Shot.outline(vd, view, Rect.div(Op.rect(path), d), 3, Color.px(c))
    case C.TMosaic{}:
      Shot.outline(vd, view, Rect.div(Op.rect(path), d), 1, 4294967295)
    case C.TCrop{}:
      Shot.outline(vd, view, Rect.div(Op.rect(path), d), 2, 4294967295)
    case C.TErase{}:
      +vw = Fit.ceil(w, d)
      +vh = Fit.ceil(h, d)
      Stroke.draw(vd, view, 2, ISolid{4288256409}, Path.polyline(Path.clamp(Path.div(path, d), vw, vh)))
    case _:
      +vw = Fit.ceil(w, d)
      +vh = Fit.ceil(h, d)
      Stroke.draw(vd, view, Tool.rad(t, 1), Tool.ink(t, c), Stroke.segs(t, Path.clamp(Path.div(path, d), vw, vh), Rect.div(Op.rect(path), d), 1, vw, vh))

def Preview.of(+vd: Nat, +d: U32, +w: U32, +h: U32, view: Image, t: C.Tool, c: C.Color, dr: C.Drag) -> Image:
  match dr:
    case C.Idle{}:
      view
    case C.Dragging{path}:
      Preview.tool(vd, d, w, h, view, t, c, path)

# 창 그림 = 뷰(왼쪽 위) + 끌기 미리보기 + 오른쪽 패널. 창 깊이 fk 가 뷰 깊이보다 깊으면 왼쪽 위에 뷰를 두고 채운다.
def Frame.wrap(+n: Nat, img: Image) -> Image:
  match n:
    case 0n:
      img
    case 1n+p:
      Frame.wrap(p, Qua{img, Pix{Panel.bg()}, Pix{Panel.bg()}, Pix{Panel.bg()}})

def Shell.compose(sh: Shell, +t: C.Tool, +c: C.Color, dr: C.Drag) -> Shell & Image:
  match sh:
    case Shell{Doc{Shape{+w, +h, +k, s, +d, td, hdr}, base, full, +view, crop}, home, stamp, cap, sink, title, +caps, lost}:
      +vd = Shape.vd(k, d)
      +vw = Fit.ceil(w, d)
      +fk = Fit.depth((vw + Panel.w() : U32), Fit.winh(h, d))
      (Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, title, caps, lost}, Panel.draw(fk, Frame.wrap(Nat.sub(fk, vd), Preview.of(vd, d, w, h, view, t, c, dr)), vw, Fit.ceil(h, d), Fit.winh(h, d), t, c, caps))

# 원본 크기 w·h, 배율 s·d 와 목록의 보이는 칸 수·첫 칸 번호 (누른 자리 판정에 쓴다). Shape 를 통째로 돌려주면 헤더 목록이 공유된다.
def Shell.shape(sh: Shell) -> Shell & (U32 & U32 & U32 & U32 & Nat & U32):
  match sh:
    case Shell{Doc{Shape{+w, +h, k, +s, +d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, title, Caps{cur, +off, acc, ids, +tiles}, lost}:
      (Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, title, Caps{cur, off, acc, ids, tiles}, lost}, (w, h, s, d, List.length(&2, Tile, tiles), off))

# 복사 중 프레임: 보통 프레임 위에 창 너비의 노란 띠. 제목도 바꿔 두어 복사가 실패하면 Shot.fin 이 보통 제목으로 되돌린다.
def Shell.busy.go(sh: Shell, img: Image) -> Shell & Image:
  match sh:
    case Shell{Doc{Shape{+w, +h, k, s, +d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, _, caps, lost}:
      +ww = (Fit.ceil(w, d) + Panel.w() : U32)
      (Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, Title.busy(), caps, lost}, Fill.rect(Fit.depth(ww, Fit.winh(h, d)), img, Rect{0, 0, (ww - 1 : U32), 7}, Color.px(C.CYellow{})))

def Shell.busy.img(shi: Shell & Image) -> Shell & Image:
  (sh, img) = shi
  Shell.busy.go(sh, img)

def Shell.busy(sh: Shell, +t: C.Tool, +c: C.Color, dr: C.Drag) -> Shell & Image:
  Shell.busy.img(Shell.compose(sh, t, c, dr))

# 경계: 창 이벤트 -> 행동
# ====================
# 마우스는 화면 픽셀이라 원본 좌표로 바꾼다. 누른 점은 그 픽셀의 첫 원본 픽셀(x*d), 뗀 점은 마지막
# 원본 픽셀(x*d + d-1): 그래야 끝 열·행에 닿는다 (U1 버그 1). 빈 끌기(화면에서 너비나 높이 0)는 Op 가 안 된다.
# 뷰 밖(패널)에서 누르면 단추 판정, 끌다가 패널로 나가면 뷰 가장자리로 잘린다.

# 빈 끌기: 영역 도구(네모·모자이크·자르기·원)는 같은 열이거나 같은 행, 직선·화살표는 같은 화면 픽셀, 펜·형광펜은 없다(클릭 = 점).
def Tool.empty(t: C.Tool, +sx: Bool, +sy: Bool) -> Bool:
  match t:
    case C.TPen{}:
      False{}
    case C.THigh{}:
      False{}
    case C.TLine{}:
      sx && sy
    case C.TArrow{}:
      sx && sy
    case _:
      sx || sy

def Rel.pt(t: C.Tool, p: C.Pt, +x: U32, +y: U32, +d: U32) -> Bool:
  match p:
    case C.Pt{px, py}:
      Tool.empty(t, U32.is_eq((px / d : U32), x), U32.is_eq((py / d : U32), y))

# 빈 떼기: 지우개는 보이는 것에 닿지 않을 때, 나머지는 누른 점과 뗀 점의 화면 자리로 (Tool.empty).
# ui 를 빌려 읽기만 하려고 길과 기록은 복사해서 넘긴다 (지우개 떼기 때만 든다).
def Rel.empty(t: C.Tool, +ex: U32, +ey: U32, path: List<&2, C.Pt>, +x: U32, +y: U32, +d: U32, +w: U32, +h: U32, +s: U32, hist: C.Hist) -> Bool:
  match t:
    case C.TErase{}:
      Bool.not(Erase.touches(C.Hist.live(C.Hist.copy(hist)), C.Pt{ex, ey} <> C.Pts.copy(path), w, h, s, d))
    case _:
      Rel.pt(t, Path.last(path, C.Pt{ex, ey}), x, y, d)

def Drag.release(t: C.Tool, dr: C.Drag, +x: U32, +y: U32, +d: U32, +w: U32, +h: U32, +s: U32, hist: C.Hist) -> C.Act:
  match dr:
    case C.Idle{}:
      C.ARelease{(x * d : U32), (y * d : U32), True{}}
    case C.Dragging{path}:
      +ex = ((x * d : U32) + (d - 1 : U32) : U32)
      +ey = ((y * d : U32) + (d - 1 : U32) : U32)
      C.ARelease{ex, ey, Rel.empty(t, ex, ey, path, x, y, d, w, h, s, hist)}

def Ev.release(ui: C.Ui, +x: U32, +y: U32, +d: U32, +w: U32, +h: U32, +s: U32) -> C.Ui & C.Act:
  match ui:
    case C.Ui{+hi, +t, c, +dr, di, he, ar}:
      (C.Ui{hi, t, c, dr, di, he, ar}, Drag.release(t, dr, x, y, d, w, h, s, hi))

def Ev.clamp(+v: U32, +m: U32) -> U32:
  U32.min(v, (m - 1 : U32))

def Ev.press(+x: U32, +y: U32, +d: U32, +vw: U32, +vh: U32, inside: Bool, n: Nat, off: U32) -> C.Act:
  match inside:
    case True{}:
      C.APress{(x * d : U32), (Ev.clamp(y, vh) * d : U32)}
    case False{}:
      Panel.hit(Panel.buttons(vw, n, off), x, y, C.ANone{})

# n 은 목록의 보이는 칸 수, off 는 첫 칸의 번호 (단추 표를 만들 때 쓴다).
def Ev.act.go(ui: C.Ui, ev: Event, +vw: U32, +vh: U32, +d: U32, +w: U32, +h: U32, +s: U32, n: Nat, off: U32) -> C.Ui & C.Act:
  match ev:
    case Key{code, down}:
      (ui, C.Key.act(code, down))
    case Close{}:
      (ui, C.AClose{})
    case Mouse{+x, y, 0, True{}}:
      (ui, Ev.press(x, y, d, vw, vh, U32.is_lt(x, vw), n, off))
    case Move{x, y}:
      (ui, C.AMove{(Ev.clamp(x, vw) * d : U32), (Ev.clamp(y, vh) * d : U32)})
    case Mouse{x, y, 0, False{}}:
      Ev.release(ui, Ev.clamp(x, vw), Ev.clamp(y, vh), d, w, h, s)
    case _:
      (ui, C.ANone{})

def Ev.act(ui: C.Ui, ev: Event, shn: U32 & U32 & U32 & U32 & Nat & U32) -> C.Ui & C.Act:
  match shn:
    case (+w, +h, +s, +d, n, off):
      Ev.act.go(ui, ev, Fit.ceil(w, d), Fit.ceil(h, d), d, w, h, s, n, off)

def Inputs.evs(evs: List<Event>) -> List<&2, Input>:
  match evs:
    case Nil{}:
      Nil{}
    case ev <> rest:
      IEv{ev} <> Inputs.evs(rest)

# 복사
# ====

def Ran.result(what: String, r: C.Ran) -> Result<&1, &1, String, Unit>:
  match r:
    case C.ROk{_}:
      Done{Unit{}}
    case C.RExit{code, err}:
      Fail{what ++ " 실패 (종료 코드 " ++ U32.show(code) ++ "): " ++ err}
    case C.RFail{code, msg}:
      Fail{what ++ " 실패: " ++ Proc.why(code, msg)}

def Clip.png(+png: String, r: C.Ran) -> IO(Result<&1, &1, String, Unit>):
  match r:
    case C.ROk{_}:
      do IO<Result<&1, &1, String, Unit>>:
        rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-e", "set the clipboard to (read (POSIX file \"" ++ png ++ "\") as «class PNGf»)", "-e", "display notification \"편집본을 클립보드에 복사했습니다\" with title \"BendShot\""], "", 65536, 60000)
        Tmp.rm(png)
        return Ran.result("클립보드 복사", Proc.ran(rc))
    case other:
      IO.pure(Result<&1, &1, String, Unit>, Ran.result("PNG 변환 (sips)", other))

def Clip.bmp(+bmp: String, +png: String, saved: Result<&1, &1, U32 & String, Unit>) -> IO(Result<&1, &1, String, Unit>):
  match saved:
    case Fail{(_, msg)}:
      IO.pure(Result<&1, &1, String, Unit>, Fail{"편집본 BMP 저장 실패: " ++ msg})
    case Done{_}:
      do IO<Result<&1, &1, String, Unit>>:
        rs : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/sips", ["-s", "format", "png", bmp, "--out", png], "", 65536, 60000)
        Tmp.rm(bmp)
        Clip.png(png, Proc.ran(rs))

def Clip.done(r: Result<&1, &1, String, Unit>) -> IO(Bool):
  match r:
    case Done{_}:
      do IO<Bool>:
        IO.print("편집본을 클립보드에 복사했습니다")
        return True{}
    case Fail{+msg}:
      do IO<Bool>:
        IO.print_err("복사에 실패했습니다: " ++ msg)
        Notify.show("복사에 실패했습니다. 편집은 그대로 있습니다: " ++ msg)
        return False{}

# 내보내기(마지막 자르기로 자른 그림)를 복사 명령이 가리키는 곳으로. 성공 여부를 돌려준다.
def Copy.go(sink: Sink, +home: String, +stamp: U32, +k: Nat, img: Image, +w: U32, +h: U32, +td: Bool, hdr: List<&2, U32>, crop: Maybe<&2, Rect>) -> IO(Sink & Bool):
  match sink:
    case SFile{out, True{}}:
      do IO<Sink & Bool>:
        IO.print("복사 실패 (시험용 예약)")
        return (SFile{out, False{}}, False{})
    case SFile{+out, False{}}:
      do IO<Sink & Bool>:
        r : Result<&1, &1, U32 & String, Unit> <- Save.crop(out, k, img, w, h, td, hdr, crop)
        Save.need(r)
        return (SFile{out, False{}}, True{})
    case SClip{}:
      +dir = Cache.dir(home)
      +bmp = dir ++ "/edit-out-" ++ U32.show(stamp) ++ ".bmp"
      +png = dir ++ "/edit-out-" ++ U32.show(stamp) ++ ".png"
      do IO<Sink & Bool>:
        md : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/mkdir", ["-p", dir], "", 1024, 5000)
        saved : Result<&1, &1, U32 & String, Unit> <- Save.crop(bmp, k, img, w, h, td, hdr, crop)
        r : Result<&1, &1, String, Unit> <- Clip.bmp(bmp, png, saved)
        ok : Bool <- Clip.done(r)
        return (SClip{}, ok)

def Shell.copy.fin(sh: Shell, r: Sink & Bool) -> Shell & Bool:
  match sh:
    case Shell{doc, home, stamp, cap, _, title, caps, lost}:
      (sink, ok) = r
      (Shell{doc, home, stamp, cap, sink, title, caps, lost}, ok)

def Shell.copy.img(sh: Shell, +home: String, +stamp: U32, sink: Sink, +k: Nat, +w: U32, +h: U32, +td: Bool, +hdr: List<&2, U32>, r: Image & Maybe<&2, Rect>) -> IO(Shell & Bool):
  (img, crop) = r
  do IO<Shell & Bool>:
    res : Sink & Bool <- Copy.go(sink, home, stamp, k, img, w, h, td, hdr, crop)
    return Shell.copy.fin(sh, res)

# 내보내기는 복사 명령에 실린 살아 있는 Op 로 원본에서 새로 그린다 (화면 캐시에 기대지 않는다).
def Shell.copy(sh: Shell, ops: List<&2, C.Op>) -> IO(Shell & Bool):
  match sh:
    case Shell{Doc{Shape{+w, +h, +k, +s, +d, +td, +hdr}, +base, full, view, crop}, +home, +stamp, cap, sink, title, caps, lost}:
      Shell.copy.img(Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, SClip{}, title, caps, lost}, home, stamp, sink, k, w, h, td, Bytes.copy(hdr), Render.all(ops, w, h, k, s, d, base))

def Copy.act(ok: Bool) -> C.Act:
  match ok:
    case True{}:
      C.ACopied{}
    case False{}:
      C.ACopyFailed{}

# 자동 저장과 다시 그리기 (기록이 바뀐 행동마다)
# =====================================

# 캡처를 연 경우 ops.txt 와 thumb.bmp 를 다시 쓴다. 미리보기는 방금 그린 전체 그림(마지막 자르기 안)에서.
def Shell.saved.go(+home: String, stamp: U32, cap: Maybe<&2, String>, sink: Sink, title: String, caps: Caps, lost: Bool, text: String, doc: Doc) -> IO(Shell):
  match cap doc:
    case None{} d:
      IO.pure(Shell, Shell{d, home, stamp, None{}, sink, title, caps, lost})
    case Some{+id} Doc{Shape{+w, +h, +k, s, d, td, +hdr}, base, +full, view, +crop}:
      +dir = Cap.dir(home, id)
      do IO<Shell>:
        ok : Bool <- Store.save(Cap.ops(dir), text)
        caps2 : Caps <- Thumb.update(id, dir, caps, Thumb.make(k, full, w, h, Thumb.region(crop, w, h)), Bytes.u32(38n, hdr))
        return Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, Some{id}, sink, title, caps2, Bool.not(ok)}

def Shell.saved(sh: Shell, +h: C.Hist) -> IO(Shell):
  match sh:
    case Shell{Doc{s, base, _, _, _}, home, stamp, cap, sink, title, caps, lost}:
      Shell.saved.go(home, stamp, cap, sink, title, caps, lost, Hist.text(h), Doc.render(s, base, C.Hist.live(h)))

# 창 루프
# ======
# 핵심 상태 기계 하나(C.Ui)에 행동을 넣고 그 명령(Out)을 실행한다. 창과 --replay·--edit 가 같은 루프다.
# Bend 는 상호 재귀가 없어 루프 함수는 하나뿐이고, 보조 함수는 다음 상태(St)를 돌려준다.

def Surface.close(su: Surface) -> IO(Surface):
  match su:
    case SWin{win}:
      do IO<Surface>:
        Window.close(win)
        return SDone{}
    case other:
      IO.pure(Surface, SDone{})

def Surface.title(su: Surface, t: String) -> IO(Surface):
  match su:
    case SWin{win}:
      do IO<Surface>:
        w2 : Window <- Window.set_title(win, t)
        return SWin{w2}
    case SRun{}:
      do IO<Surface>:
        IO.print("TITLE " ++ t)
        return SRun{}
    case SDone{}:
      IO.pure(Surface, SDone{})

def Surface.busy.shown(next: Window & Image & List<Event>) -> Surface & List<&2, Input>:
  (win, _, evs) = next
  (SWin{win}, Inputs.evs(evs))

# 복사 전에 바쁜 프레임 하나를 보여 준다. 창이면 그동안 들어온 이벤트를 돌려준다 (버리지 않으려고).
def Surface.busy(su: Surface, img: Image) -> IO(Surface & List<&2, Input>):
  match su:
    case SWin{win}:
      do IO<Surface & List<&2, Input>>:
        w2 : Window <- Window.set_title(win, Title.busy())
        next : Window & Image & List<Event> <- Window.frame(w2, img)
        return Surface.busy.shown(next)
    case other:
      do IO<Surface & List<&2, Input>>:
        su2 : Surface <- Surface.title(other, Title.busy())
        return (su2, Nil{})

def Shell.retitle.go(su: Surface, sh: Shell, ui: C.Ui, ins: List<&2, Input>, new: String, same: Bool) -> IO(St):
  match same:
    case True{}:
      IO.pure(St, (su, sh, ui, ins))
    case False{}:
      do IO<St>:
        su2 : Surface <- Surface.title(su, new)
        return (su2, sh, ui, ins)

def Shell.retitle.sc(su: Surface, sh: Shell, ins: List<&2, Input>, usc: C.Ui & (C.Tool & C.Color & C.Drag & Bool)) -> IO(St):
  match sh:
    case Shell{doc, home, stamp, cap, sink, old, caps, +lost}:
      (ui, (t, c, _, ar)) = usc
      +new = Title.of(t, c, ar, lost)
      Shell.retitle.go(su, Shell{doc, home, stamp, cap, sink, new, caps, lost}, ui, ins, new, String.eq(old, new))

# 행동 하나가 끝날 때마다 제목을 맞춘다 (도구·Esc 경고가 바뀌면).
def Shot.fin(su: Surface, sh: Shell, ui: C.Ui, ins: List<&2, Input>) -> IO(St):
  Shell.retitle.sc(su, sh, ins, Ui.scene(ui))

def Act.run(+ui: C.Ui, +a: C.Act) -> C.Ui & C.Out:
  o = C.Ui.out(C.Ui.peek(ui, a), a)
  (C.Ui.step(ui, a), o)

# 복사 결과를 같은 상태 기계에 행동으로 넣는다: 성공이면 닫히고, 실패면 창과 편집이 그대로다.
def Shot.copied(su: Surface, ui: C.Ui, rest: List<&2, Input>, r: Shell & Bool) -> IO(St):
  (sh, ok) = r
  Shot.fin(su, sh, ui, IAct{Copy.act(ok)} <> rest)

def Shot.copy.go(ui: C.Ui, rest: List<&2, Input>, ops: List<&2, C.Op>, sh: Shell, sue: Surface & List<&2, Input>) -> IO(St):
  (su, evs) = sue
  do IO<St>:
    r : Shell & Bool <- Shell.copy(sh, ops)
    Shot.copied(su, ui, List.append(&2, Input, rest, evs), r)

def Shot.copy.img(su: Surface, ui: C.Ui, rest: List<&2, Input>, ops: List<&2, C.Op>, shi: Shell & Image) -> IO(St):
  (sh, img) = shi
  do IO<St>:
    sue : Surface & List<&2, Input> <- Surface.busy(su, img)
    Shot.copy.go(ui, rest, ops, sh, sue)

def Shot.copy.sc(su: Surface, sh: Shell, rest: List<&2, Input>, ops: List<&2, C.Op>, usc: C.Ui & (C.Tool & C.Color & C.Drag & Bool)) -> IO(St):
  (ui, (t, c, dr, _)) = usc
  Shot.copy.img(su, ui, rest, ops, Shell.busy(sh, t, c, dr))

# 복사: 먼저 "복사 중…" 제목과 바쁜 프레임을 보이고 (5K 는 1~2초 걸려 멈춘 듯 보였다) 그 다음 내보낸다.
def Shot.copy(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, ops: List<&2, C.Op>) -> IO(St):
  Shot.copy.sc(su, sh, rest, ops, Ui.scene(ui))

def Shell.home(sh: Shell) -> Shell & (String & U32):
  match sh:
    case Shell{doc, +home, +stamp, cap, sink, title, caps, lost}:
      (Shell{doc, home, stamp, cap, sink, title, caps, lost}, (home, stamp))

def Shell.fail(sh: Shell) -> Shell:
  match sh:
    case Shell{doc, home, stamp, cap, SFile{out, _}, title, caps, lost}:
      Shell{doc, home, stamp, cap, SFile{out, True{}}, title, caps, lost}
    case other:
      other

# 캡처 바꾸기·지우기 (오른쪽 목록의 칸과 × 단추)
# ========================================
# 바꾸기: 지금 기록은 이미 자동 저장돼 있으니(규칙 10·11) 고른 캡처를 새 프로세스·새 창으로 열고 이 창은 닫는다.
# 지우기: 캡처 폴더를 휴지통으로 옮긴다 (되살릴 수 있게). 지금 연 캡처면 창을 닫고, 아니면 목록을 다시 읽는다.

# 번호 i 의 캡처: 지금 연 것인가, 그 이름 (전체 목록 기준이라 스크롤로 안 보이는 칸도 된다).
def Shell.tile(sh: Shell, +i: U32) -> Shell & (Bool & Maybe<&2, String>):
  match sh:
    case Shell{doc, home, stamp, cap, sink, title, Caps{+cur, off, acc, +ids, tiles}, lost}:
      (Shell{doc, home, stamp, cap, sink, title, Caps{cur, off, acc, ids, tiles}, lost}, (Caps.is(cur, i), Ids.get(U32.to_nat(i), ids)))

def Launch.exe(args: List<String>) -> String:
  match args:
    case exe <> _:
      exe
    case Nil{}:
      "shot"

# 같은 실행 파일을 뒤에서 돌린다. 새 프로세스도 이 프로세스의 자식이라 책임 프로세스(Haemil Shot 앱)의 권한을 그대로 잇는다.
def Launch.run(+exe: String, id: String) -> IO(C.Ran):
  do IO<C.Ran>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/sh", ["-c", "\"$0\" --edit \"$1\" </dev/null >/dev/null 2>&1 &", exe, id], "", 4096, 20000)
    return Proc.ran(r)

def Launch.done(r: C.Ran) -> IO(Unit):
  match r:
    case C.ROk{_}:
      IO.pure(Unit, Unit{})
    case other:
      Proc.need("캡처 열기", other)

# 창이면 새 프로세스를 띄우고, 미리 적은 입력이면 EDIT 줄만 찍는다 (검사가 프로세스를 띄우지 않도록).
def Launch.args(win: Window, id: String, args: List<String>) -> IO(Surface):
  +exe = Launch.exe(args)
  do IO<Surface>:
    r : C.Ran <- Launch.run(exe, id)
    Launch.done(r)
    return SWin{win}

def Surface.launch(su: Surface, id: String) -> IO(Surface):
  match su:
    case SWin{win}:
      do IO<Surface>:
        args : List<String> <- IO.args()
        Launch.args(win, id, args)
    case SRun{}:
      do IO<Surface>:
        IO.print("EDIT " ++ id)
        return SRun{}
    case SDone{}:
      IO.pure(Surface, SDone{})

def Shell.lost(sh: Shell) -> Shell & Bool:
  match sh:
    case Shell{doc, home, stamp, cap, sink, title, caps, +lost}:
      (Shell{doc, home, stamp, cap, sink, title, caps, lost}, lost)

# 마지막 자동 저장이 실패했으면 바꾸지 않는다: 바꾸면 이 창이 닫혀 저장 못 한 편집이 사라진다.
# 다음 기록 변화가 기록 전체를 다시 저장하므로 그게 성공하면 다시 바꿀 수 있다.
def Shot.switch(su: Surface, ui: C.Ui, rest: List<&2, Input>, id: String, shl: Shell & Bool) -> IO(St):
  match shl:
    case Tuple{sh, True{}}:
      +msg = {"저장에 실패해서 다른 캡처로 바꾸지 않았습니다" : String}
      do IO<St>:
        IO.print_err(msg)
        Notify.show(msg)
        Shot.fin(su, sh, ui, rest)
    case Tuple{sh, False{}}:
      do IO<St>:
        su2 : Surface <- Surface.launch(su, id)
        su3 : Surface <- Surface.close(su2)
        return (su3, sh, ui, rest)

# 지금 연 캡처의 칸이거나 없는 번호면 아무 일 없다.
def Shot.pick.go(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, same: Bool, t: Maybe<&2, String>) -> IO(St):
  match same t:
    case False{} Some{id}:
      Shot.switch(su, ui, rest, id, Shell.lost(sh))
    case _ _:
      Shot.fin(su, sh, ui, rest)

def Shot.pick.tile(su: Surface, ui: C.Ui, rest: List<&2, Input>, sht: Shell & (Bool & Maybe<&2, String>)) -> IO(St):
  (sh, (same, t)) = sht
  Shot.pick.go(su, sh, ui, rest, same, t)

def Shot.pick(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, i: U32) -> IO(St):
  Shot.pick.tile(su, ui, rest, Shell.tile(sh, i))

def Trash.done(r: C.Ran) -> IO(Bool):
  match r:
    case C.ROk{_}:
      IO.pure(Bool, True{})
    case C.RExit{_, +err}:
      do IO<Bool>:
        IO.print_err("캡처를 휴지통으로 옮기지 못했습니다: " ++ err)
        Notify.show("캡처를 휴지통으로 옮기지 못했습니다: " ++ err)
        return False{}
    case C.RFail{code, msg}:
      +why = Proc.why(code, msg)
      do IO<Bool>:
        IO.print_err("캡처를 휴지통으로 옮기지 못했습니다: " ++ why)
        Notify.show("캡처를 휴지통으로 옮기지 못했습니다: " ++ why)
        return False{}

def Trash.mv(dir: String, dest: String) -> IO(Bool):
  do IO<Bool>:
    r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/mv", ["-f", dir, dest], "", 4096, 10000)
    Trash.done(Proc.ran(r))

# Finder 가 못 옮기면 (권한을 안 줬거나 Finder 가 없으면) ~/.Trash 로 직접 옮긴다.
def Trash.finder(+home: String, +stamp: U32, dir: String, id: String, r: C.Ran) -> IO(Bool):
  match r:
    case C.ROk{_}:
      IO.pure(Bool, True{})
    case _:
      Trash.mv(dir, home ++ "/.Trash/" ++ id ++ "-" ++ U32.show(stamp))

def Trash.go(+home: String, +stamp: U32, +dir: String, +id: String, t: Result<&1, &1, U32 & String, String>) -> IO(Bool):
  match t:
    case Done{+root}:
      do IO<Bool>:
        md : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/mkdir", ["-p", root], "", 1024, 5000)
        Trash.mv(dir, root ++ "/" ++ id)
    case Fail{_}:
      do IO<Bool>:
        r : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to delete POSIX file \"" ++ dir ++ "\""], "", 65536, 20000)
        Trash.finder(home, stamp, dir, id, Proc.ran(r))

# BENDSHOT_TRASH=<폴더> 가 있으면 (검사용) 거기로 옮기고, 없으면 Finder 로 맥 휴지통에 넣는다. 절대 rm -rf 하지 않는다.
def Trash.path(+home: String, stamp: U32, +dir: String, +id: String) -> IO(Bool):
  do IO<Bool>:
    t : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDSHOT_TRASH")
    Trash.go(home, stamp, dir, id, t)

def Trash.move(+home: String, stamp: U32, +id: String) -> IO(Bool):
  Trash.path(home, stamp, Cap.dir(home, id), id)

# 목록을 다시 읽는다 (지운 뒤).
# 목록을 다시 읽되 스크롤 위치는 지킨다 (한계는 Caps.load 가 다시 잰다).
def Shell.reload(sh: Shell) -> IO(Shell):
  match sh:
    case Shell{Doc{Shape{w, +h, k, s, +d, td, hdr}, base, full, view, crop}, +home, stamp, +cap, sink, title, Caps{_, off, _, _, _}, lost}:
      do IO<Shell>:
        caps : Caps <- Caps.load(home, Name.copy(cap), Tiles.fit(Fit.winh(h, d)), off)
        return Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, title, caps, lost}

def Shot.dropped(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, same: Bool, moved: Bool) -> IO(St):
  match same moved:
    case True{} True{}:
      do IO<St>:
        su2 : Surface <- Surface.close(su)
        return (su2, sh, ui, rest)
    case _ _:
      do IO<St>:
        sh2 : Shell <- Shell.reload(sh)
        Shot.fin(su, sh2, ui, rest)

def Shot.drop.go(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, env: String & U32, same: Bool, t: Maybe<&2, String>) -> IO(St):
  match env t:
    case _ None{}:
      Shot.fin(su, sh, ui, rest)
    case (home, stamp) Some{id}:
      do IO<St>:
        moved : Bool <- Trash.move(home, stamp, id)
        Shot.dropped(su, sh, ui, rest, same, moved)

def Shot.drop.tile(su: Surface, ui: C.Ui, rest: List<&2, Input>, env: String & U32, sht: Shell & (Bool & Maybe<&2, String>)) -> IO(St):
  (sh, (same, t)) = sht
  Shot.drop.go(su, sh, ui, rest, env, same, t)

def Shot.drop.env(su: Surface, ui: C.Ui, rest: List<&2, Input>, +i: U32, she: Shell & (String & U32)) -> IO(St):
  (sh, env) = she
  Shot.drop.tile(su, ui, rest, env, Shell.tile(sh, i))

def Shot.drop(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, i: U32) -> IO(St):
  Shot.drop.env(su, ui, rest, i, Shell.home(sh))

# 트랙패드·휠: 포인터가 오른쪽 목록 위(패널 열, 색 단추 아래)일 때 세로 거리로 목록을 넘긴다. 셸의 UI 상태라 핵심 상태 기계는 모른다.
def Shot.scroll(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, x: U32, y: U32, dy: F32) -> IO(St):
  match sh:
    case Shell{Doc{Shape{+w, +h, k, s, +d, td, hdr}, base, full, view, crop}, +home, stamp, cap, sink, title, caps, lost}:
      do IO<St>:
        caps2 : Caps <- Caps.wheel(home, caps, Tiles.fit(Fit.winh(h, d)), U32.is_ge(x, Fit.ceil(w, d)) && U32.is_ge(y, 272), dy)
        return (su, Shell{Doc{Shape{w, h, k, s, d, td, hdr}, base, full, view, crop}, home, stamp, cap, sink, title, caps2, lost}, ui, rest)

# 명령 실행
# ========

# 미리 적은 입력(--replay·--edit)일 때만 저장·다시 그리기에 걸린 밀리초를 찍는다 (성능 측정용).
def Shot.timed(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, ms: Nat) -> IO(St):
  match su:
    case SRun{}:
      do IO<St>:
        IO.print("SAVE " ++ Nat.show(ms) ++ " ms")
        Shot.fin(SRun{}, sh, ui, rest)
    case other:
      Shot.fin(other, sh, ui, rest)

def Shot.out(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, o: C.Out) -> IO(St):
  match o:
    case C.Out{Some{h}, _, _, _, _}:
      do IO<St>:
        t0 : Nat <- IO.now()
        sh2 : Shell <- Shell.saved(sh, h)
        t1 : Nat <- IO.now()
        Shot.timed(su, sh2, ui, rest, Nat.sub(t1, t0))
    case C.Out{_, Some{ops}, _, _, _}:
      Shot.copy(su, sh, ui, rest, ops)
    case C.Out{_, _, True{}, _, _}:
      do IO<St>:
        su2 : Surface <- Surface.close(su)
        return (su2, sh, ui, rest)
    case C.Out{_, _, _, Some{i}, _}:
      Shot.pick(su, sh, ui, rest, i)
    case C.Out{_, _, _, _, Some{i}}:
      Shot.drop(su, sh, ui, rest, i)
    case _:
      Shot.fin(su, sh, ui, rest)

def Shot.ran(su: Surface, sh: Shell, rest: List<&2, Input>, uo: C.Ui & C.Out) -> IO(St):
  (ui, o) = uo
  Shot.out(su, sh, ui, rest, o)

def Shot.act(su: Surface, sh: Shell, ui: C.Ui, rest: List<&2, Input>, a: C.Act) -> IO(St):
  Shot.ran(su, sh, rest, Act.run(ui, a))

def Shot.ev.act(su: Surface, sh: Shell, rest: List<&2, Input>, ua: C.Ui & C.Act) -> IO(St):
  (ui, a) = ua
  Shot.act(su, sh, ui, rest, a)

def Shot.ev(su: Surface, ui: C.Ui, ev: Event, rest: List<&2, Input>, shs: Shell & (U32 & U32 & U32 & U32 & Nat & U32)) -> IO(St):
  (sh, shn) = shs
  Shot.ev.act(su, sh, rest, Ev.act(ui, ev, shn))

def Shot.shown(sh: Shell, ui: C.Ui, next: Window & Image & List<Event>) -> IO(St):
  (win, _, evs) = next
  IO.pure(St, (SWin{win}, sh, ui, Inputs.evs(evs)))

def Shot.frame.img(win: Window, ui: C.Ui, shi: Shell & Image) -> IO(St):
  (sh, img) = shi
  do IO<St>:
    next : Window & Image & List<Event> <- Window.frame(win, img)
    Shot.shown(sh, ui, next)

def Shot.frame.sc(win: Window, sh: Shell, usc: C.Ui & (C.Tool & C.Color & C.Drag & Bool)) -> IO(St):
  (ui, (t, c, d, _)) = usc
  Shot.frame.img(win, ui, Shell.compose(sh, t, c, d))

# 넣을 것이 없으면 프레임 하나(뷰 + 끌기 미리보기)를 그리고 이벤트를 받는다.
def Shot.frame(win: Window, sh: Shell, ui: C.Ui) -> IO(St):
  Shot.frame.sc(win, sh, Ui.scene(ui))

# 첫 프레임까지 걸리는 계산(그리기 + 창 그림 합성)을 재려고 미리 적은 입력에서는 프레임 하나를 만들어 본다.
def Shot.run.frame.img(ui: C.Ui, shi: Shell & Image) -> Shell & C.Ui & Image:
  (sh, img) = shi
  (sh, ui, img)

def Shot.run.frame.sc(sh: Shell, usc: C.Ui & (C.Tool & C.Color & C.Drag & Bool)) -> Shell & C.Ui & Image:
  (ui, (t, c, dr, _)) = usc
  Shot.run.frame.img(ui, Shell.compose(sh, t, c, dr))

def Shot.run.frame(st: Shell & C.Ui) -> Shell & C.Ui & Image:
  (sh, ui) = st
  Shot.run.frame.sc(sh, Ui.scene(ui))

# BENDSHOT_FRAME=<경로.bmp> 가 있으면 첫 창 그림(뷰 + 패널)을 그 파일로 쓴다 (패널 모양 검사·확인용).
def Shot.run.dump(fr: Image, +fk: Nat, +ww: U32, +wh: U32, r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.pure(Unit, Unit{})
    case Done{path}:
      do IO<Unit>:
        saved : Result<&1, &1, U32 & String, Unit> <- Save.go(path, fk, fr, 0, 0, ww, wh, True{}, Save.v5(ww, wh, 2835))
        Save.need(saved)

def Shot.run.end.dump(r: Result<&1, &1, U32 & String, String>, sh: Shell, fr: Image) -> IO(Unit):
  match sh:
    case Shell{Doc{Shape{w, h, _, _, +d, _, _}, _, _, _, _}, _, _, _, _, _, _, _}:
      +ww = (Fit.ceil(w, d) + Panel.w() : U32)
      +wh = Fit.winh(h, d)
      Shot.run.dump(fr, Fit.depth(ww, wh), ww, wh, r)

def Shot.run.end.go(r: Result<&1, &1, U32 & String, String>, sti: Shell & C.Ui & Image) -> IO(Unit):
  (sh, ui, fr) = sti
  Shot.run.end.dump(r, sh, fr)

# 미리 적은 입력이 끝났을 때: BENDSHOT_FRAME_END=<경로.bmp> 가 있으면 마지막 창 그림을 그 파일로 쓴다 (스크롤 뒤 목록 검사용).
def Shot.run.end(sh: Shell, ui: C.Ui) -> IO(Unit):
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDSHOT_FRAME_END")
    Shot.run.end.go(r, Shot.run.frame((sh, ui)))

# 미리 적은 목록이 끝나면 창이 열린 채라 아무것도 쓰지 않는다 (SRun 에 Nil).
def Shot.loop(fuel: Nat, st: St) -> IO(Unit):
  match fuel st:
    case _ Tuple{SDone{}, _}:
      IO.pure(Unit, Unit{})
    case 0n Tuple{su, _}:
      do IO<Unit>:
        su2 : Surface <- Surface.close(su)
        IO.pure(Unit, Unit{})
    case 1n+f Tuple{SRun{}, Tuple{sh, Tuple{ui, Nil{}}}}:
      Shot.run.end(sh, ui)
    case 1n+f Tuple{SWin{win}, Tuple{sh, Tuple{ui, Nil{}}}}:
      do IO<Unit>:
        st2 : St <- Shot.frame(win, sh, ui)
        Shot.loop(f, st2)
    case 1n+f Tuple{su, Tuple{sh, Tuple{ui, IFail{} <> rest}}}:
      Shot.loop(f, (su, Shell.fail(sh), ui, rest))
    case 1n+f Tuple{su, Tuple{sh, Tuple{ui, IAct{a} <> rest}}}:
      do IO<Unit>:
        st2 : St <- Shot.act(su, sh, ui, rest, a)
        Shot.loop(f, st2)
    case 1n+f Tuple{su, Tuple{sh, Tuple{ui, IEv{Scroll{x, y, _, dy}} <> rest}}}:
      do IO<Unit>:
        st2 : St <- Shot.scroll(su, sh, ui, rest, x, y, dy)
        Shot.loop(f, st2)
    case 1n+f Tuple{su, Tuple{sh, Tuple{ui, IEv{ev} <> rest}}}:
      do IO<Unit>:
        st2 : St <- Shot.ev(su, ui, ev, rest, Shell.shape(sh))
        Shot.loop(f, st2)

# 시작
# ====

def Shot.env() -> IO(String & U32):
  do IO<String & U32>:
    home : String <- IO.try(String, IO.get_env("HOME"))
    stamp : U32 <- IO.try(U32, IO.random_u32())
    return (home, stamp)

def Shell.new(env: String & U32, loaded: Shape & Image, +h: C.Hist, cap: Maybe<&2, String>, sink: Sink, caps: Caps) -> Shell & C.Ui:
  (home, stamp) = env
  (s, base) = loaded
  (Shell{Doc.open(s, base, C.Hist.copy(h)), home, stamp, cap, sink, Title.first(), caps, False{}}, C.Ui.open(h))

# Window.open 은 제목을 Latin-1 로 읽어 한글이 깨지므로 창은 ASCII 제목으로 열고, 여기서 곧바로 UTF-8 제목을 건다.
# 미리 적은 입력은 같은 줄을 TITLE 로 찍는다.
def Shot.start(su: Surface, ins: List<&2, Input>, st: Shell & C.Ui) -> IO(Unit):
  (sh, ui) = st
  do IO<Unit>:
    su2 : Surface <- Surface.title(su, Title.first())
    Shot.loop(4294967295n, (su2, sh, ui, ins))

# OPEN 줄은 목록 읽기 + 첫 프레임 (+ BENDSHOT_FRAME 이 있으면 그 파일 쓰기: 그래야 게으른 그림이 실제로 계산된다).
def Shot.run.start(ins: List<&2, Input>, sti: Shell & C.Ui & Image, t0: Nat, +fk: Nat, +ww: U32, +wh: U32) -> IO(Unit):
  (sh, ui, fr) = sti
  do IO<Unit>:
    r : Result<&1, &1, U32 & String, String> <- IO.get_env("BENDSHOT_FRAME")
    Shot.run.dump(fr, fk, ww, wh, r)
    t1 : Nat <- IO.now()
    IO.print("OPEN " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")
    Shot.start(SRun{}, ins, (sh, ui))

# FIT 줄: 고른 표시 배율과 창 크기 (검사가 읽는다).
def Shot.run.fit(env: String & U32, sh: Shape, base: Image, h: C.Hist, +cap: Maybe<&2, String>, sink: Sink, ins: List<&2, Input>) -> IO(Unit):
  match env sh:
    case (+home, stamp) Shape{+w, +hh, k, sc, +d, td, hdr}:
      +ww = (Fit.ceil(w, d) + Panel.w() : U32)
      +wh = Fit.winh(hh, d)
      do IO<Unit>:
        IO.print("FIT " ++ U32.show(d) ++ " " ++ U32.show(ww) ++ " " ++ U32.show(wh))
        t0 : Nat <- IO.now()
        caps : Caps <- Caps.load(home, Name.copy(cap), Tiles.fit(wh), 0)
        sti : Shell & C.Ui & Image <- IO.pure(Shell & C.Ui & Image, Shot.run.frame(Shell.new((home, stamp), (Shape{w, hh, k, sc, d, td, hdr}, base), h, cap, sink, caps)))
        Shot.run.start(ins, sti, t0, Fit.depth(ww, wh), ww, wh)

def Shot.run.go(env: String & U32, loaded: Shape & Image, h: C.Hist, cap: Maybe<&2, String>, sink: Sink, ins: List<&2, Input>, screen: Maybe<&1, U32 & U32>) -> IO(Unit):
  (sh, base) = loaded
  Shot.run.fit(env, Fit.shape(sh, screen), base, h, cap, sink, ins)

def Shot.run(env: String & U32, loaded: Shape & Image, h: C.Hist, cap: Maybe<&2, String>, sink: Sink, ins: List<&2, Input>) -> IO(Unit):
  do IO<Unit>:
    screen : Maybe<&1, U32 & U32> <- Screen.size(False{})
    Shot.run.go(env, loaded, h, cap, sink, ins, screen)

def Shot.window.fit(env: String & U32, sh: Shape, base: Image, h: C.Hist, +cap: Maybe<&2, String>) -> IO(Unit):
  match env sh:
    case (+home, stamp) Shape{+w, +hh, k, sc, +d, td, hdr}:
      +wh = Fit.winh(hh, d)
      do IO<Unit>:
        caps : Caps <- Caps.load(home, Name.copy(cap), Tiles.fit(wh), 0)
        win : Window <- IO.try(Window, Window.open("BendShot", (Fit.ceil(w, d) + Panel.w() : U32), wh))
        Shot.start(SWin{win}, Nil{}, Shell.new((home, stamp), (Shape{w, hh, k, sc, d, td, hdr}, base), h, cap, SClip{}, caps))

def Shot.window.go(env: String & U32, loaded: Shape & Image, h: C.Hist, cap: Maybe<&2, String>, screen: Maybe<&1, U32 & U32>) -> IO(Unit):
  (sh, base) = loaded
  Shot.window.fit(env, Fit.shape(sh, screen), base, h, cap)

# 창은 화면 크기를 읽어 (뷰 + 패널) 이 들어오는 표시 배율로 연다.
def Shot.window(env: String & U32, loaded: Shape & Image, h: C.Hist, cap: Maybe<&2, String>) -> IO(Unit):
  do IO<Unit>:
    screen : Maybe<&1, U32 & U32> <- Screen.size(True{})
    Shot.window.go(env, loaded, h, cap, screen)

# 캡처 (--area, --full)
# ===================
# 창도 그림 해독도 없이 captures/<id>/orig.png 로 찍고 PNG 를 바로 클립보드로. 그 뒤 최근 30개만 남긴다.
# 메뉴 막대 앱은 가장 최근 captures/*/orig.png 의 바뀐 시각으로 새 캡처를 안다: 보관·지우기 밖에 사본을 두지 않는다.

# 실패했을 때 보일 말 (판정은 하지 않는다: 판정은 C.Cap.verdict 가 한다).
def Ran.why(r: C.Ran) -> C.Ran & String:
  match r:
    case C.ROk{out}:
      (C.ROk{out}, "")
    case C.RExit{code, +err}:
      (C.RExit{code, err}, "캡처에 실패했습니다: " ++ err)
    case C.RFail{+code, +msg}:
      (C.RFail{code, msg}, "캡처 실행 실패: " ++ Proc.why(code, msg))

# 셸은 규칙 9 가 증명한 C.Cap.verdict 의 판정대로만 움직인다.
def Shot.captured(+home: String, +dir: String, +orig: String, why: String, v: C.Verdict) -> IO(Unit):
  match v:
    case C.VDone{}:
      do IO<Unit>:
        Clip.copy(orig, "클립보드에 복사했습니다")
        Thumb.sips(dir)
        Cap.prune(home)
    case C.VCancel{}:
      do IO<Unit>:
        Cap.rm([dir])
        IO.print("캡처를 취소했습니다")
    case C.VPermission{}:
      do IO<Unit>:
        Cap.rm([dir])
        op : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/bin/open", ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"], "", 1024, 5000)
        Shot.fail("화면 기록 권한이 필요합니다. 설정에서 BendShot을 켜 주세요")
    case _:
      do IO<Unit>:
        Cap.rm([dir])
        Shot.fail(why)

def Shot.captured.go(+home: String, +dir: String, +orig: String, found: Bool, rw: C.Ran & String) -> IO(Unit):
  (ran, why) = rw
  Shot.captured(home, dir, orig, why, C.Cap.verdict(ran, found))

def File.found(r: Result<&1, &1, U32 & String, File>) -> IO(Bool):
  match r:
    case Done{file}:
      do IO<Bool>:
        File.close(file)
        return True{}
    case Fail{_}:
      IO.pure(Bool, False{})

def Shot.capture.args(full: Bool, tmp: String) -> List<String>:
  match full:
    case True{}:
      ["-x", "-m", "-t", "png", tmp]
    case False{}:
      ["-i", "-t", "png", tmp]

def Shot.capture.go(full: Bool, +home: String, id: String) -> IO(Unit):
  +dir = Cap.dir(home, id)
  +orig = dir ++ "/orig.png"
  do IO<Unit>:
    md : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/bin/mkdir", ["-p", dir], "", 1024, 5000)
    Proc.need("캐시 폴더 만들기", Proc.ran(md))
    rc : Result<&1, &1, U32 & String, U32 & (String & String)> <- Process.run("/usr/sbin/screencapture", Shot.capture.args(full, orig), "", 65536, 300000)
    opened : Result<&1, &1, U32 & String, File> <- File.open(orig, "r")
    found : Bool <- File.found(opened)
    Shot.captured.go(home, dir, orig, found, Ran.why(Proc.ran(rc)))

def Shot.capture(full: Bool) -> IO(Unit):
  do IO<Unit>:
    home : String <- IO.try(String, IO.get_env("HOME"))
    id : String <- Cap.newid()
    Shot.capture.go(full, home, id)

def Shot.newid() -> IO(Unit):
  do IO<Unit>:
    id : String <- Cap.newid()
    IO.print(id)

def Shot.prune() -> IO(Unit):
  do IO<Unit>:
    home : String <- IO.try(String, IO.get_env("HOME"))
    Cap.prune(home)

# 마지막 캡처 편집 (--edit-last, --replay-last)
# =========================================

def Shot.cap.loaded(env: String & U32, id: String, headless: Mode, r: Result<&1, &1, String, (Shape & Image) & C.Hist>) -> IO(Unit):
  match headless r:
    case _ Fail{m}:
      Shot.fail(m)
    case MWin{} Done{(loaded, h)}:
      Shot.window(env, loaded, h, Some{id})
    case MRun{out, ins} Done{(loaded, h)}:
      Shot.run(env, loaded, h, Some{id}, SFile{out, False{}}, ins)

def Shot.cap.found(env: String & U32, +id: String, headless: Mode, opened: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match env opened:
    case _ Fail{_}:
      Shot.fail("그런 캡처가 없습니다: " ++ id)
    case (+home, +stamp) Done{file}:
      do IO<Unit>:
        File.close(file)
        r : Result<&1, &1, String, (Shape & Image) & C.Hist> <- Cap.load(home, stamp, Cap.dir(home, id))
        Shot.cap.loaded((home, stamp), id, headless, r)

# 이름으로 캡처 하나를 연다 (--edit <id>, --replay-cap <id>). orig.png 가 없으면 그런 캡처가 없는 것.
def Shot.cap.go(env: String & U32, +id: String, headless: Mode) -> IO(Unit):
  (+home, stamp) = env
  do IO<Unit>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(Cap.dir(home, id) ++ "/orig.png", "r")
    Shot.cap.found((home, stamp), id, headless, opened)

def Shot.cap(id: String, headless: Mode) -> IO(Unit):
  do IO<Unit>:
    env : String & U32 <- Shot.env()
    Shot.cap.go(env, id, headless)

# --edit-last = --edit <가장 최근 캡처>
def Shot.last.go(env: String & U32, headless: Mode, ids: List<&2, String>) -> IO(Unit):
  match ids:
    case Nil{}:
      Shot.fail("편집할 캡처가 없습니다")
    case id <> _:
      Shot.cap.go(env, id, headless)

def Shot.last.ids(env: String & U32, headless: Mode) -> IO(Unit):
  (+home, stamp) = env
  do IO<Unit>:
    ids : List<&2, String> <- Cap.ids(home)
    Shot.last.go((home, stamp), headless, ids)

def Shot.last(headless: Mode) -> IO(Unit):
  do IO<Unit>:
    env : String & U32 <- Shot.env()
    Shot.last.ids(env, headless)

# 창 없이 편집 (--edit): 원본 좌표의 Op 목록을 같은 상태 기계에 행동으로 넣고, 끝에 복사(파일로)를 넣는다
# =================================================================================================

# 일부만 걸치면 잘라 쓰고(창과 같다), 전부 밖이면 거부한다 (가장자리 1픽셀 편집이 되는 것을 막는다).
def Edit.rect.go(+t: C.Tool, at: String, +a: U32, +b: U32, +c: U32, +d: U32, outside: Bool, xs: List<&2, Input>) -> Result<&1, &1, String, List<&2, Input>>:
  match outside:
    case True{}:
      Fail{"편집 영역이 그림 밖입니다: " ++ at}
    case False{}:
      Done{IAct{C.APick{t}} <> IAct{C.APress{a, b}} <> IAct{C.ARelease{c, d, Tool.empty(t, U32.is_eq(a, c), U32.is_eq(b, d))}} <> xs}

def Edit.rect(t: C.Tool, name: String, +a: U32, +b: U32, +c: U32, +d: U32, +w: U32, +h: U32, rest: Result<&1, &1, String, List<&2, Input>>) -> Result<&1, &1, String, List<&2, Input>>:
  match rest:
    case Fail{m}:
      Fail{m}
    case Done{xs}:
      Edit.rect.go(t, name ++ " " ++ U32.show(a) ++ " " ++ U32.show(b) ++ " " ++ U32.show(c) ++ " " ++ U32.show(d), a, b, c, d, U32.is_ge(U32.min(a, c), w) || U32.is_ge(U32.min(b, d), h), xs)

def Edit.cons(a: C.Act, rest: Result<&1, &1, String, List<&2, Input>>) -> Result<&1, &1, String, List<&2, Input>>:
  match rest:
    case Fail{m}:
      Fail{m}
    case Done{xs}:
      Done{IAct{a} <> xs}

def Edit.color(c: Maybe<&2, C.Color>, name: String, rest: Result<&1, &1, String, List<&2, Input>>) -> Result<&1, &1, String, List<&2, Input>>:
  match c:
    case Some{c2}:
      Edit.cons(C.AColor{c2}, rest)
    case None{}:
      Fail{"모르는 색: " ++ name ++ " (red|yellow|green|blue|black|white)"}

# 모르는 단어, 모자라는 인자, 숫자 아닌 인자는 거기서 멈춘다.
def Edit.inputs(ts: List<&2, Tok>, +w: U32, +h: U32) -> Result<&1, &1, String, List<&2, Input>>:
  match ts:
    case Nil{}:
      Done{[IAct{C.ACopy{}}]}
    case TWord{"undo"} <> rest:
      Edit.cons(C.AUndo{}, Edit.inputs(rest, w, h))
    case TWord{"redo"} <> rest:
      Edit.cons(C.ARedo{}, Edit.inputs(rest, w, h))
    case TWord{"color"} <> TWord{+c} <> rest:
      Edit.color(Color.read(c), c, Edit.inputs(rest, w, h))
    case TWord{"box"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TBox{}, "box", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"mosaic"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TMosaic{}, "mosaic", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"crop"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TCrop{}, "crop", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"pen"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TPen{}, "pen", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"high"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.THigh{}, "high", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"line"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TLine{}, "line", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"arrow"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TArrow{}, "arrow", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case TWord{"ellipse"} <> TNum{a} <> TNum{b} <> TNum{c} <> TNum{d} <> rest:
      Edit.rect(C.TEllipse{}, "ellipse", a, b, c, d, w, h, Edit.inputs(rest, w, h))
    case t <> _:
      Fail{"알 수 없는 편집 명령: " ++ Tok.show(t) ++ " (box|mosaic|crop|pen|high|line|arrow|ellipse x0 y0 x1 y1 | color 이름 | undo | redo)"}

def Shot.edit.run(env: String & U32, out: String, loaded: Shape & Image, ins: Result<&1, &1, String, List<&2, Input>>) -> IO(Unit):
  match ins:
    case Fail{m}:
      IO.die(Unit, 2, m)
    case Done{xs}:
      Shot.run(env, loaded, C.Hist{Nil{}, Nil{}}, None{}, SFile{out, False{}}, xs)

def Shot.edit.go(env: String & U32, out: String, toks: List<String>, loaded: Shape & Image) -> IO(Unit):
  match loaded:
    case (Shape{+w, +h, k, sc, d, td, hdr}, base):
      Shot.edit.run(env, out, (Shape{w, h, k, sc, d, td, hdr}, base), Edit.inputs(Tok.all(toks), w, h))

def Shot.edit(inp: String, out: String, toks: List<String>) -> IO(Unit):
  do IO<Unit>:
    env : String & U32 <- Shot.env()
    loaded : Shape & Image <- Load.open(inp)
    Shot.edit.go(env, out, toks, loaded)

# 창 없이 창 루프 재현 (--replay, --replay-last)
# ==========================================

def Replay.ok(i: Input, r: Result<&1, &1, String, List<&2, Input>>) -> Result<&1, &1, String, List<&2, Input>>:
  match r:
    case Done{xs}:
      Done{i <> xs}
    case Fail{m}:
      Fail{m}

# scroll 의 거리는 부호가 있어 (음수가 아래) 숫자 토큰이 아닌 낱말로도 온다.
def Replay.scroll(x: U32, y: U32, dy: Maybe<&2, F32>, rest: Result<&1, &1, String, List<&2, Input>>) -> Result<&1, &1, String, List<&2, Input>>:
  match dy:
    case None{}:
      Fail{"scroll 의 거리는 숫자여야 합니다 (예: scroll 200 300 -64)"}
    case Some{v}:
      Replay.ok(IEv{Scroll{x, y, 0.0, v}}, rest)

# 좌표는 화면(창) 픽셀. 앞 토큰이 틀리면 거기서 멈추므로 첫 번째 잘못된 토큰이 보고된다.
def Replay.parse(ts: List<&2, Tok>) -> Result<&1, &1, String, List<&2, Input>>:
  match ts:
    case Nil{}:
      Done{Nil{}}
    case TWord{"scroll"} <> TNum{x} <> TNum{y} <> TNum{n} <> rest:
      Replay.ok(IEv{Scroll{x, y, 0.0, U32.to_f32(n)}}, Replay.parse(rest))
    case TWord{"scroll"} <> TNum{x} <> TNum{y} <> TWord{s} <> rest:
      Replay.scroll(x, y, F32.read(s), Replay.parse(rest))
    case TWord{"down"} <> TNum{x} <> TNum{y} <> rest:
      Replay.ok(IEv{Mouse{x, y, 0, True{}}}, Replay.parse(rest))
    case TWord{"move"} <> TNum{x} <> TNum{y} <> rest:
      Replay.ok(IEv{Move{x, y}}, Replay.parse(rest))
    case TWord{"up"} <> TNum{x} <> TNum{y} <> rest:
      Replay.ok(IEv{Mouse{x, y, 0, False{}}}, Replay.parse(rest))
    case TWord{"key"} <> TNum{+c} <> rest:
      Replay.ok(IEv{Key{c, True{}}}, Replay.ok(IEv{Key{c, False{}}}, Replay.parse(rest)))
    case TWord{"keydown"} <> TNum{c} <> rest:
      Replay.ok(IEv{Key{c, True{}}}, Replay.parse(rest))
    case TWord{"keyup"} <> TNum{c} <> rest:
      Replay.ok(IEv{Key{c, False{}}}, Replay.parse(rest))
    case TWord{"close"} <> rest:
      Replay.ok(IEv{Close{}}, Replay.parse(rest))
    case TWord{"copyfail"} <> rest:
      Replay.ok(IFail{}, Replay.parse(rest))
    case TWord{"open"} <> TNum{i} <> rest:
      Replay.ok(IAct{C.AOpen{i}}, Replay.parse(rest))
    case TWord{"delete"} <> TNum{i} <> rest:
      Replay.ok(IAct{C.ADelete{i}}, Replay.parse(rest))
    case t <> _:
      Fail{"잘못된 replay 이벤트: " ++ Tok.show(t) ++ " (down|move|up X Y, scroll X Y DY, key|keydown|keyup CODE, close, copyfail, open|delete N)"}

def Shot.replay.go(inp: String, out: String, parsed: Result<&1, &1, String, List<&2, Input>>) -> IO(Unit):
  match parsed:
    case Fail{m}:
      IO.die(Unit, 2, m)
    case Done{ins}:
      do IO<Unit>:
        env : String & U32 <- Shot.env()
        loaded : Shape & Image <- Load.open(inp)
        Shot.run(env, loaded, C.Hist{Nil{}, Nil{}}, None{}, SFile{out, False{}}, ins)

def Shot.replay(inp: String, out: String, toks: List<String>) -> IO(Unit):
  Shot.replay.go(inp, out, Replay.parse(Tok.all(toks)))

def Shot.replay.last.go(out: String, parsed: Result<&1, &1, String, List<&2, Input>>) -> IO(Unit):
  match parsed:
    case Fail{m}:
      IO.die(Unit, 2, m)
    case Done{ins}:
      Shot.last(MRun{out, ins})

def Shot.replay.last(out: String, toks: List<String>) -> IO(Unit):
  Shot.replay.last.go(out, Replay.parse(Tok.all(toks)))

def Shot.replay.cap.go(id: String, out: String, parsed: Result<&1, &1, String, List<&2, Input>>) -> IO(Unit):
  match parsed:
    case Fail{m}:
      IO.die(Unit, 2, m)
    case Done{ins}:
      Shot.cap(id, MRun{out, ins})

# --replay-cap <id>: --edit <id> 의 창 없는 쌍 (검사용).
def Shot.replay.cap(id: String, out: String, toks: List<String>) -> IO(Unit):
  Shot.replay.cap.go(id, out, Replay.parse(Tok.all(toks)))

# BMP 파일을 바로 연다 (--open). 캡처 폴더가 없으니 기록은 저장되지 않는다 (시험·확인용).
def Shot.open(path: String) -> IO(Unit):
  do IO<Unit>:
    env : String & U32 <- Shot.env()
    loaded : Shape & Image <- Load.open(path)
    Shot.window(env, loaded, C.Hist{Nil{}, Nil{}}, None{})

def Shot.main(args: List<String>) -> IO(Unit):
  match args:
    case _ <> "--edit" <> id <> Nil{}:
      Shot.cap(id, MWin{})
    case _ <> "--edit" <> inp <> out <> ops:
      Shot.edit(inp, out, ops)
    case _ <> "--replay" <> inp <> out <> evs:
      Shot.replay(inp, out, evs)
    case _ <> "--replay-last" <> out <> evs:
      Shot.replay.last(out, evs)
    case _ <> "--replay-cap" <> id <> out <> evs:
      Shot.replay.cap(id, out, evs)
    case _ <> "--open" <> path <> _:
      Shot.open(path)
    case _ <> "--full" <> _:
      Shot.capture(True{})
    case _ <> "--edit-last" <> _:
      Shot.last(MWin{})
    case _ <> "--prune" <> _:
      Shot.prune()
    case _ <> "--new-capture-id" <> _:
      Shot.newid()
    case _ <> "--area" <> _:
      Shot.capture(False{})
    case _ <> Nil{}:
      Shot.capture(False{})
    case _:
      IO.die(Unit, 2, "사용법: shot [--area] | shot --full | shot --edit-last | shot --edit <캡처 이름> | shot --prune | shot --new-capture-id | shot --open <그림.bmp> | shot --edit <입력.bmp> <출력.bmp> [box|mosaic|crop|pen|high|line|arrow|ellipse x0 y0 x1 y1 | color 이름 | undo | redo]... | shot --replay <입력.bmp> <출력.bmp> [이벤트]... | shot --replay-last <출력.bmp> [이벤트]... | shot --replay-cap <캡처 이름> <출력.bmp> [이벤트]...   (이벤트: down|move|up X Y | scroll X Y 거리 | key|keydown|keyup 코드 | close | copyfail | open|delete N)")

# 옛 판은 캡처마다 원본을 last.png 로도 복사했다. 보관 한도·목록 지우기 밖이라 지운 캡처(모자이크로 가린
# 비밀)가 거기 남으므로, 어느 모드로 시작하든 있으면 한 번 휴지통으로 옮긴다 (목록 지우기와 같은 방법).
def Legacy.last.go(+home: String, +path: String, opened: Result<&1, &1, U32 & String, File>) -> IO(Unit):
  match opened:
    case Fail{_}:
      IO.pure(Unit, Unit{})
    case Done{file}:
      do IO<Unit>:
        File.close(file)
        stamp : U32 <- IO.try(U32, IO.random_u32())
        moved : Bool <- Trash.path(home, stamp, path, "last.png")
        IO.pure(Unit, Unit{})

def Legacy.last(r: Result<&1, &1, U32 & String, String>) -> IO(Unit):
  match r:
    case Fail{_}:
      IO.pure(Unit, Unit{})
    case Done{+home}:
      +path = Cache.dir(home) ++ "/last.png"
      do IO<Unit>:
        opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
        Legacy.last.go(home, path, opened)

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    home : Result<&1, &1, U32 & String, String> <- IO.get_env("HOME")
    Legacy.last(home)
    Shot.main(args)
