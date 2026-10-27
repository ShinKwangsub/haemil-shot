import Base

# BendShot 편집기 핵심 층. 숫자 판정(키 코드, 좌표 변환)과 그림 계산은 이 파일 밖에 있다.
# 원본 그림과 화면 그림은 이 층의 상태에 없다: 셸이 원본을 들고 있고, 화면·내보내기는
# 언제나 (원본, Hist.live) 에서 새로 만든다 (LAWS.bend 규칙 6·7 을 구조로 지킨다).
# 타입과 함수 모양은 LAWS.bend 가 기대는 약속이라 바꾸면 안 된다. 증명은 PROOF.bend 에 있다.

type Tool is Data:
  TBox{}
  TMosaic{}
  TCrop{}
  TPen{}
  THigh{}
  TLine{}
  TArrow{}
  TEllipse{}
  TErase{}

type Color is Data:
  CRed{}
  CYellow{}
  CGreen{}
  CBlue{}
  CBlack{}
  CWhite{}

type Pt is Data:
  Pt{x: U32, y: U32}

# 그린 것 하나. 내용은 Op.make 만 만든다 (지우개·자르기도 Op).
type Op is Data:
  Op{tool: Tool, color: Color, path: List<&2, Pt>}

# 기록: 살아 있는 Op 들(가장 최근이 앞)과 다시 실행할 수 있는 Op 들(바로 다음 것이 앞).
type Hist is Data:
  Hist{done: List<&2, Op>, redo: List<&2, Op>}

type Drag is Data:
  Idle{}
  Dragging{path: List<&2, Pt>}

# 경계가 키·마우스 이벤트를 바꾼 행동. 좌표는 이미 원본 해상도.
type Act is Data:
  APick{tool: Tool}
  AColor{color: Color}
  APress{x: U32, y: U32}
  AMove{x: U32, y: U32}
  ARelease{x: U32, y: U32, empty: Bool}
  AUndo{}
  ARedo{}
  ACopy{}
  ACopied{}
  ACopyFailed{}
  AEscDown{}
  AEscUp{}
  AOtherKey{}
  AClose{}
  AOpen{id: U32}
  ADelete{id: U32}
  ANone{}

type Ui is Data:
  Ui{hist: Hist, tool: Tool, color: Color, drag: Drag, dirty: Bool, held: Bool, armed: Bool}

# 한 행동이 셸에 시키는 일.
type Out is Data:
  Out{save: Maybe<&2, Hist>, copy: Maybe<&2, List<&2, Op>>, quit: Bool, open: Maybe<&2, U32>, delete: Maybe<&2, U32>}

def Op.make(tool: Tool, color: Color, path: List<&2, Pt>) -> Op:
  Op{tool, color, path}

# 살아 있는 Op, 오래된 것부터 (그리기 순서).
def Hist.live(h: Hist) -> List<&2, Op>:
  match h:
    case Hist{done, redo}:
      List.reverse(&2, Op, done)

def Hist.commit(h: Hist, op: Op) -> Hist:
  match h:
    case Hist{done, redo}:
      Hist{op <> done, []}

def Hist.undo(h: Hist) -> Hist:
  match h:
    case Hist{[], redo}:
      Hist{[], redo}
    case Hist{d <> ds, redo}:
      Hist{ds, d <> redo}

def Hist.redo(h: Hist) -> Hist:
  match h:
    case Hist{done, []}:
      Hist{done, []}
    case Hist{done, r <> rs}:
      Hist{r <> done, rs}

def Ui.open(h: Hist) -> Ui:
  Ui{h, TBox{}, CRed{}, Idle{}, False{}, False{}, False{}}

def Drag.press(d: Drag, x: U32, y: U32) -> Drag:
  match d:
    case Idle{}:
      Dragging{[Pt{x, y}]}
    case Dragging{path}:
      Dragging{path}

def Drag.move(d: Drag, x: U32, y: U32) -> Drag:
  match d:
    case Idle{}:
      Idle{}
    case Dragging{path}:
      Dragging{Pt{x, y} <> path}

# 떼기가 Op 를 확정하는가: 끌던 길이 있고 빈 끌기가 아닐 때.
def Drag.commits(d: Drag, empty: Bool) -> Bool:
  match d empty:
    case Dragging{path} False{}:
      True{}
    case _ _:
      False{}

def Hist.release(h: Hist, t: Tool, c: Color, d: Drag, x: U32, y: U32, empty: Bool) -> Hist:
  match d empty:
    case Dragging{path} False{}:
      Hist.commit(h, Op.make(t, c, Pt{x, y} <> path))
    case _ _:
      h

def Ui.step(ui: Ui, a: Act) -> Ui:
  match ui:
    case Ui{h, +t, +c, +d, di, he, ar}:
      match a:
        case APick{t2}:
          Ui{h, t2, c, Idle{}, di, he, False{}}
        case AColor{c2}:
          Ui{h, t, c2, Idle{}, di, he, False{}}
        case APress{x, y}:
          Ui{h, t, c, Drag.press(d, x, y), di, he, ar}
        case AMove{x, y}:
          Ui{h, t, c, Drag.move(d, x, y), di, he, ar}
        case ARelease{x, y, +empty}:
          di2 = Bool.or(Drag.commits(d, empty), di)
          Ui{Hist.release(h, t, c, d, x, y, empty), t, c, Idle{}, di2, he, ar}
        case AUndo{}:
          Ui{Hist.undo(h), t, c, Idle{}, True{}, he, False{}}
        case ARedo{}:
          Ui{Hist.redo(h), t, c, Idle{}, True{}, he, False{}}
        case ACopy{}:
          Ui{h, t, c, Idle{}, di, he, ar}
        case ACopied{}:
          Ui{h, t, c, d, di, he, ar}
        case ACopyFailed{}:
          Ui{h, t, c, d, di, he, ar}
        case AEscDown{}:
          Ui{h, t, c, d, di, True{}, Bool.or(Bool.not(he), ar)}
        case AEscUp{}:
          Ui{h, t, c, d, di, False{}, ar}
        case AOtherKey{}:
          Ui{h, t, c, d, di, he, False{}}
        case AClose{}:
          Ui{h, t, c, d, di, he, ar}
        case AOpen{id}:
          Ui{h, t, c, Idle{}, di, he, ar}
        case ADelete{id}:
          Ui{h, t, c, Idle{}, di, he, ar}
        case ANone{}:
          Ui{h, t, c, d, di, he, ar}

# Esc 누름이 닫는가: 누른 채 자동 반복은 무시, 편집이 있으면 경고(armed) 뒤 두 번째여야 닫는다.
def Esc.quits(di: Bool, he: Bool, ar: Bool) -> Bool:
  match he:
    case True{}:
      False{}
    case False{}:
      Bool.or(Bool.not(di), ar)

def Hist.save_release(h: Hist, t: Tool, c: Color, d: Drag, x: U32, y: U32, empty: Bool) -> Maybe<&2, Hist>:
  match d empty:
    case Dragging{path} False{}:
      Some{Hist.commit(h, Op.make(t, c, Pt{x, y} <> path))}
    case _ _:
      None{}

def Ui.out(ui: Ui, a: Act) -> Out:
  match ui:
    case Ui{h, t, c, d, di, he, ar}:
      match a:
        case ARelease{x, y, empty}:
          Out{Hist.save_release(h, t, c, d, x, y, empty), None{}, False{}, None{}, None{}}
        case AUndo{}:
          Out{Some{Hist.undo(h)}, None{}, False{}, None{}, None{}}
        case ARedo{}:
          Out{Some{Hist.redo(h)}, None{}, False{}, None{}, None{}}
        case ACopy{}:
          Out{None{}, Some{Hist.live(h)}, False{}, None{}, None{}}
        case ACopied{}:
          Out{None{}, None{}, True{}, None{}, None{}}
        case AEscDown{}:
          Out{None{}, None{}, Esc.quits(di, he, ar), None{}, None{}}
        case AClose{}:
          Out{None{}, None{}, True{}, None{}, None{}}
        case AOpen{id}:
          Out{None{}, None{}, False{}, Some{id}, None{}}
        case ADelete{id}:
          Out{None{}, None{}, False{}, None{}, Some{id}}
        case _:
          Out{None{}, None{}, False{}, None{}, None{}}

# 빌려 읽어 새로 짓는 복사. 같은 값을 두 소유자에게 넘기면 그 타입(기본 List 포함)이 프로그램 전체에서
# 공유 상태가 되어 그림 읽기·쓰기가 1.5배 느려진다.
def Pt.copy(p: Pt) -> Pt:
  match p:
    case Pt{x, y}:
      Pt{x, y}

def Pts.copy(ps: List<&2, Pt>) -> List<&2, Pt>:
  match ps:
    case []:
      []
    case p <> rest:
      Pt.copy(p) <> Pts.copy(rest)

def Op.copy(o: Op) -> Op:
  match o:
    case Op{t, c, path}:
      Op{t, c, Pts.copy(path)}

def Ops.copy(os: List<&2, Op>) -> List<&2, Op>:
  match os:
    case []:
      []
    case o <> rest:
      Op.copy(o) <> Ops.copy(rest)

def Hist.copy(h: Hist) -> Hist:
  match h:
    case Hist{done, redo}:
      Hist{Ops.copy(done), Ops.copy(redo)}

def Drag.copy(d: Drag) -> Drag:
  match d:
    case Idle{}:
      Idle{}
    case Dragging{path}:
      Dragging{Pts.copy(path)}

# Ui.out 이 행동 a 에서 읽는 몫만 복사한 Ui (ui 는 빌려 읽기만 한다). 셸은 Ui.step 에 ui 를, Ui.out 에 이것을 넘긴다.
# 기록은 떼기·되돌리기·다시 하기·복사만, 끌기는 떼기만 읽는다 (위 Ui.out 의 갈래와 같이 바꿀 것).
def Ui.peek(ui: Ui, a: Act) -> Ui:
  match ui:
    case Ui{h, t, c, d, di, he, ar}:
      match a:
        case ARelease{_, _, _}:
          Ui{Hist.copy(h), t, c, Drag.copy(d), di, he, ar}
        case AUndo{}:
          Ui{Hist.copy(h), t, c, Idle{}, di, he, ar}
        case ARedo{}:
          Ui{Hist.copy(h), t, c, Idle{}, di, he, ar}
        case ACopy{}:
          Ui{Hist.copy(h), t, c, Idle{}, di, he, ar}
        case _:
          Ui{Hist{[], []}, t, c, Idle{}, di, he, ar}

# 바깥 프로그램 실행 결과 (U1 의 shot.bend 에서 옮겨 올 타입).
type Ran is Data:
  ROk{out: String}
  RExit{code: U32, err: String}
  RFail{code: U32, msg: String}

# 캡처 결과 판정.
type Verdict is Data:
  VDone{}
  VCancel{}
  VPermission{}
  VTimeout{}
  VTooLong{}
  VFailed{}

def Cap.fail(timeout: Bool, too_long: Bool) -> Verdict:
  match timeout too_long:
    case True{} _:
      VTimeout{}
    case False{} True{}:
      VTooLong{}
    case False{} False{}:
      VFailed{}

def Cap.exit(display: Bool) -> Verdict:
  match display:
    case True{}:
      VPermission{}
    case False{}:
      VFailed{}

# 경계: 캡처 결과 판정 (file: 결과 파일이 생겼는가).
def Cap.verdict(r: Ran, file: Bool) -> Verdict:
  match r file:
    case ROk{out} True{}:
      VDone{}
    case ROk{out} False{}:
      VCancel{}
    case RFail{+code, msg} _:
      Cap.fail(U32.is_eq(code, 60), U32.is_eq(code, 27))
    case RExit{code, err} _:
      Cap.exit(String.contains(err, "display"))

def Key.up(esc: Bool) -> Act:
  match esc:
    case True{}:
      AEscUp{}
    case False{}:
      ANone{}

# 숫자 키 1~9 → 도구 (글자 값이라 여기서만 비교한다).
def Key.tool(code: U32) -> Maybe<&2, Tool>:
  match code:
    case 49:
      Some{TBox{}}
    case 50:
      Some{TMosaic{}}
    case 51:
      Some{TCrop{}}
    case 52:
      Some{TPen{}}
    case 53:
      Some{THigh{}}
    case 54:
      Some{TLine{}}
    case 55:
      Some{TArrow{}}
    case 56:
      Some{TEllipse{}}
    case 57:
      Some{TErase{}}
    case _:
      None{}

def Key.down(enter: Bool, esc: Bool, undo: Bool, redo: Bool, tool: Maybe<&2, Tool>) -> Act:
  match enter esc undo redo tool:
    case True{} _ _ _ _:
      ACopy{}
    case False{} True{} _ _ _:
      AEscDown{}
    case False{} False{} True{} _ _:
      AUndo{}
    case False{} False{} False{} True{} _:
      ARedo{}
    case False{} False{} False{} False{} Some{t}:
      APick{t}
    case False{} False{} False{} False{} None{}:
      AOtherKey{}

# 경계: 키 하나를 행동으로 (숫자 비교는 여기서만).
def Key.act(code: U32, down: Bool) -> Act:
  match down:
    case False{}:
      Key.up(U32.is_eq(code, 27))
    case True{}:
      +c = code
      Key.down(U32.is_eq(c, 13), U32.is_eq(c, 27),
        Bool.or(U32.is_eq(c, 122), U32.is_eq(c, 12619)),
        Bool.or(U32.is_eq(c, 121), U32.is_eq(c, 12635)),
        Key.tool(c))
