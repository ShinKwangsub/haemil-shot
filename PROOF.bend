# BendShot 증명. `bend PROOF.bend` 가 ALL PROOFS CHECK 를 찍어야 한다.
# 법칙은 LAWS.bend (광섭의 것), 구현은 core.bend. Spec 표는 왼쪽 인자부터 쪼개므로
# 행동 18 가지 × 끌기 상태 2 가지를 그대로 늘어놓은 표 증명이 많다.
import Base
import ./core.bend as C
import ./LAWS.bend as Laws

# ---------------------------------------------------------------------------
# 반박 도구: 가설이 True == False 로 계산되면 그 가지는 성립하지 않는다.
# ---------------------------------------------------------------------------

def disc(b: Bool) -> Data:
  match b:
    case False{}:
      Unit
    case True{}:
      Empty

def tf.go(e: {False{} == True{} : Bool}) -> disc(True{}):
  %e : disc(_)
  Unit{}

def tf(-P: Type, e: {True{} == False{} : Bool}) -> P:
  Empty.absurd(P, tf.go(Equal.sym(Bool, True{}, False{}, e)))

# ---------------------------------------------------------------------------
# 규칙 1 (시간선). 기록 Hist 와 기준 모형 Ref 는 편집 한 번마다 같이 움직인다 (sim).
# 목록 보조정리는 Base 의 List.reverse.go 누적 인자 모양을 그대로 따른다.
# ---------------------------------------------------------------------------

# 뒤집기 누적 인자 뒤에 붙이는 것은 먼저 붙이고 뒤집는 것과 같다.
def rev_go_app(xs: List<&2, C.Op>, acc: List<&2, C.Op>, ys: List<&2, C.Op>)
  -> {List.reverse.go(&2, C.Op, xs, List.append(&2, C.Op, acc, ys)) == List.append(&2, C.Op, List.reverse.go(&2, C.Op, xs, acc), ys) : List<&2, C.Op>}:
  match xs:
    case []:
      {==}
    case h <> t:
      rev_go_app(t, h <> acc, ys)

def add_succ(a: Nat, b: Nat) -> {Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_succ(p, b) : {1n+Nat.add(p, 1n+b) == 1n+_ : Nat}
      {==}

def add_zero(a: Nat) -> {Nat.add(a, 0n) == a : Nat}:
  match a:
    case 0n:
      {==}
    case 1n+p:
      %add_zero(p) : {1n+Nat.add(p, 0n) == 1n+_ : Nat}
      {==}

def take_zero(xs: List<&2, C.Op>) -> {[] == List.take(&2, C.Op, xs, 0n) : List<&2, C.Op>}:
  match xs:
    case []:
      {==}
    case h <> t:
      {==}

# 뒤집은 목록의 앞 length(xs)+k 개 = 누적 인자의 앞 k 개만 남기고 뒤집은 것.
def take_rev(xs: List<&2, C.Op>, acc: List<&2, C.Op>, +k: Nat)
  -> {List.reverse.go(&2, C.Op, xs, List.take(&2, C.Op, acc, k)) == List.take(&2, C.Op, List.reverse.go(&2, C.Op, xs, acc), Nat.add(List.length(&2, C.Op, xs), k)) : List<&2, C.Op>}:
  match xs:
    case []:
      {==}
    case h <> +t:
      %add_succ(List.length(&2, C.Op, t), k) : {List.reverse.go(&2, C.Op, t, h <> List.take(&2, C.Op, acc, k)) == List.take(&2, C.Op, List.reverse.go(&2, C.Op, t, h <> acc), _) : List<&2, C.Op>}
      take_rev(t, h <> acc, 1n+k)

def len_rev_go(xs: List<&2, C.Op>, +acc: List<&2, C.Op>)
  -> {Nat.add(List.length(&2, C.Op, xs), List.length(&2, C.Op, acc)) == List.length(&2, C.Op, List.reverse.go(&2, C.Op, xs, acc)) : Nat}:
  match xs:
    case []:
      {==}
    case h <> +t:
      %len_rev_go(t, h <> acc) : {1n+Nat.add(List.length(&2, C.Op, t), List.length(&2, C.Op, acc)) == _ : Nat}
      %add_succ(List.length(&2, C.Op, t), List.length(&2, C.Op, acc)) : {_ == Nat.add(List.length(&2, C.Op, t), 1n+List.length(&2, C.Op, acc)) : Nat}
      {==}

def lt_add0(n: Nat) -> {False{} == Nat.is_lt(n, Nat.add(n, 0n)) : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      lt_add0(p)

def lt_succ_add(n: Nat, m: Nat) -> {True{} == Nat.is_lt(n, Nat.add(n, 1n+m)) : Bool}:
  match n:
    case 0n:
      {==}
    case 1n+p:
      lt_succ_add(p, m)

# 편집 한 번: 기록을 기준 모형으로 읽은 것 = 기준 모형을 한 칸 움직인 것.
def sim(h: C.Hist, e: Laws.Edit) -> {Laws.Ref.of(Laws.Hist.edit(h, e)) == Laws.Ref.step(Laws.Ref.of(h), e) : Laws.Ref}:
  match h e:
    case C.Hist{+done, +redo} Laws.ECommit{+op}:
      %rev_go_app(done, [op], []) : {Laws.Ref{_, 1n+List.length(&2, C.Op, done)} == Laws.Ref{List.append(&2, C.Op, List.take(&2, C.Op, List.append(&2, C.Op, List.reverse.go(&2, C.Op, done, []), redo), List.length(&2, C.Op, done)), [op]), 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      %rev_go_app(done, [], redo) : {Laws.Ref{List.reverse.go(&2, C.Op, done, [op]), 1n+List.length(&2, C.Op, done)} == Laws.Ref{List.append(&2, C.Op, List.take(&2, C.Op, _, List.length(&2, C.Op, done)), [op]), 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      %add_zero(List.length(&2, C.Op, done)) : {Laws.Ref{List.reverse.go(&2, C.Op, done, [op]), 1n+List.length(&2, C.Op, done)} == Laws.Ref{List.append(&2, C.Op, List.take(&2, C.Op, List.reverse.go(&2, C.Op, done, redo), _), [op]), 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      %take_rev(done, redo, 0n) : {Laws.Ref{List.reverse.go(&2, C.Op, done, [op]), 1n+List.length(&2, C.Op, done)} == Laws.Ref{List.append(&2, C.Op, _, [op]), 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      %take_zero(redo) : {Laws.Ref{List.reverse.go(&2, C.Op, done, [op]), 1n+List.length(&2, C.Op, done)} == Laws.Ref{List.append(&2, C.Op, List.reverse.go(&2, C.Op, done, _), [op]), 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      %rev_go_app(done, [], [op]) : {Laws.Ref{List.reverse.go(&2, C.Op, done, [op]), 1n+List.length(&2, C.Op, done)} == Laws.Ref{_, 1n+List.length(&2, C.Op, done)} : Laws.Ref}
      {==}
    case C.Hist{[], redo} Laws.EUndo{}:
      {==}
    case C.Hist{+d <> +ds, +redo} Laws.EUndo{}:
      %rev_go_app(ds, [], d <> redo) : {Laws.Ref{_, List.length(&2, C.Op, ds)} == Laws.Ref{List.append(&2, C.Op, List.reverse.go(&2, C.Op, ds, [d]), redo), List.length(&2, C.Op, ds)} : Laws.Ref}
      %rev_go_app(ds, [d], redo) : {Laws.Ref{List.reverse.go(&2, C.Op, ds, d <> redo), List.length(&2, C.Op, ds)} == Laws.Ref{_, List.length(&2, C.Op, ds)} : Laws.Ref}
      {==}
    case C.Hist{+done, []} Laws.ERedo{}:
      %rev_go_app(done, [], []) : {Laws.Ref{_, List.length(&2, C.Op, done)} == Laws.Ref.redo(_, List.length(&2, C.Op, done), Nat.is_lt(List.length(&2, C.Op, done), List.length(&2, C.Op, _))) : Laws.Ref}
      %len_rev_go(done, []) : {Laws.Ref{List.reverse.go(&2, C.Op, done, []), List.length(&2, C.Op, done)} == Laws.Ref.redo(List.reverse.go(&2, C.Op, done, []), List.length(&2, C.Op, done), Nat.is_lt(List.length(&2, C.Op, done), _)) : Laws.Ref}
      %lt_add0(List.length(&2, C.Op, done)) : {Laws.Ref{List.reverse.go(&2, C.Op, done, []), List.length(&2, C.Op, done)} == Laws.Ref.redo(List.reverse.go(&2, C.Op, done, []), List.length(&2, C.Op, done), _) : Laws.Ref}
      {==}
    case C.Hist{+done, +r <> +rs} Laws.ERedo{}:
      %rev_go_app(done, [r], rs) : {Laws.Ref{_, 1n+List.length(&2, C.Op, done)} == Laws.Ref.redo(List.append(&2, C.Op, List.reverse.go(&2, C.Op, done, []), r <> rs), List.length(&2, C.Op, done), Nat.is_lt(List.length(&2, C.Op, done), List.length(&2, C.Op, List.append(&2, C.Op, List.reverse.go(&2, C.Op, done, []), r <> rs)))) : Laws.Ref}
      %rev_go_app(done, [], r <> rs) : {Laws.Ref{List.reverse.go(&2, C.Op, done, r <> rs), 1n+List.length(&2, C.Op, done)} == Laws.Ref.redo(_, List.length(&2, C.Op, done), Nat.is_lt(List.length(&2, C.Op, done), List.length(&2, C.Op, _))) : Laws.Ref}
      %len_rev_go(done, r <> rs) : {Laws.Ref{List.reverse.go(&2, C.Op, done, r <> rs), 1n+List.length(&2, C.Op, done)} == Laws.Ref.redo(List.reverse.go(&2, C.Op, done, r <> rs), List.length(&2, C.Op, done), Nat.is_lt(List.length(&2, C.Op, done), _)) : Laws.Ref}
      %lt_succ_add(List.length(&2, C.Op, done), List.length(&2, C.Op, rs)) : {Laws.Ref{List.reverse.go(&2, C.Op, done, r <> rs), 1n+List.length(&2, C.Op, done)} == Laws.Ref.redo(List.reverse.go(&2, C.Op, done, r <> rs), List.length(&2, C.Op, done), _) : Laws.Ref}
      {==}

def run_sim(+es: List<&2, Laws.Edit>, +h: C.Hist) -> {Laws.Ref.of(Laws.Hist.run(es, h)) == Laws.Ref.run(es, Laws.Ref.of(h)) : Laws.Ref}:
  match es:
    case []:
      {==}
    case e <> rest:
      %sim(h, e) : {Laws.Ref.of(Laws.Hist.run(rest, Laws.Hist.edit(h, e))) == Laws.Ref.run(rest, _) : Laws.Ref}
      run_sim(rest, Laws.Hist.edit(h, e))

# 살아 있는 Op = 기준 모형에서 손가락까지.
def live_of(h: C.Hist) -> {C.Hist.live(h) == Laws.Ref.live(Laws.Ref.of(h)) : List<&2, C.Op>}:
  match h:
    case C.Hist{+done, +redo}:
      %rev_go_app(done, [], redo) : {List.reverse.go(&2, C.Op, done, []) == List.take(&2, C.Op, _, List.length(&2, C.Op, done)) : List<&2, C.Op>}
      %add_zero(List.length(&2, C.Op, done)) : {List.reverse.go(&2, C.Op, done, []) == List.take(&2, C.Op, List.reverse.go(&2, C.Op, done, redo), _) : List<&2, C.Op>}
      %take_rev(done, redo, 0n) : {List.reverse.go(&2, C.Op, done, []) == _ : List<&2, C.Op>}
      %take_zero(redo) : {List.reverse.go(&2, C.Op, done, []) == List.reverse.go(&2, C.Op, done, _) : List<&2, C.Op>}
      {==}

def Laws.timeline(es, h):
  %run_sim(es, h) : {C.Hist.live(Laws.Hist.run(es, h)) == Laws.Ref.live(_) : List<&2, C.Op>}
  live_of(Laws.Hist.run(es, h))

# ---------------------------------------------------------------------------
# 규칙 2·3. 기록과 끌기는 의도 표대로. 끌기 상태까지 쪼개야 Spec 표가 계산된다.
# ---------------------------------------------------------------------------
def Laws.hist_by_table(ui, a):
  match ui a:
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ANone{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ANone{}:
      {==}

def Laws.drag_by_table(ui, a):
  match ui a:
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ANone{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ANone{}:
      {==}

# 도구·색은 고르기로만 바뀐다.
def Laws.pick_sets_tool(ui, t):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.tool_kept(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      tf({Laws.Spec.tool(C.Ui.step(C.Ui{h, t, c, d, di, he, ar}, C.APick{t2})) == Laws.Spec.tool(C.Ui{h, t, c, d, di, he, ar}) : C.Tool}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

def Laws.color_sets_color(ui, c):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.color_kept(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      tf({Laws.Spec.color(C.Ui.step(C.Ui{h, t, c, d, di, he, ar}, C.AColor{c2})) == Laws.Spec.color(C.Ui{h, t, c, d, di, he, ar}) : C.Color}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

# ---------------------------------------------------------------------------
# 규칙 4·5. 복사와 닫기
# ---------------------------------------------------------------------------
def Laws.copy_on_enter(ui):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.no_copy_otherwise(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      tf({Laws.Out.copy(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.ACopy{})) == None{} : Maybe<&2, List<&2, C.Op>>}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

def Laws.quit_only_when(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      tf({Laws.Out.quit(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.ACopied{})) == False{} : Bool}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      tf({Laws.Out.quit(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.AEscDown{})) == False{} : Bool}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      tf({Laws.Out.quit(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.AClose{})) == False{} : Bool}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

def Laws.close_button_quits(ui):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.copied_quits(ui):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.copy_failed_keeps(ui):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

# Esc 기계: 깃발(dirty·held·armed)이 글자 값이라 모두 계산으로 닫힌다.
def Laws.esc_clean_quits(h, t, c, d, ar):
  {==}

def Laws.esc_dirty_first_warns(h, t, c, d):
  {==}

def Laws.esc_dirty_twice_quits(h, t, c, d):
  {==}

def Laws.esc_dirty_twice_with_move_quits(h, t, c, d, x, y):
  {==}

def Laws.esc_repeat_not_twice(h, t, c, d):
  {==}

# 다른 키 k 뒤의 닫기 값: k 가 키 행동이면 False, 아니면 제 값 그대로 (반사).
def reset_tbl(h: C.Hist, t: C.Tool, c: C.Color, d: C.Drag, k: C.Act) -> {Bool.pick(Bool, Laws.Spec.is_key(k), False{}, Laws.Out.quit(C.Ui.out(C.Ui.step(C.Ui.step(C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{}), C.AEscUp{}), k), C.AEscDown{}))) == Laws.Out.quit(C.Ui.out(C.Ui.step(C.Ui.step(C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{}), C.AEscUp{}), k), C.AEscDown{})) : Bool}:
  match k:
    case C.APick{kt}:
      {==}
    case C.AColor{kc}:
      {==}
    case C.APress{x, y}:
      {==}
    case C.AMove{x, y}:
      {==}
    case C.ARelease{x, y, False{}}:
      {==}
    case C.ARelease{x, y, True{}}:
      {==}
    case C.AUndo{}:
      {==}
    case C.ARedo{}:
      {==}
    case C.ACopy{}:
      {==}
    case C.ACopied{}:
      {==}
    case C.ACopyFailed{}:
      {==}
    case C.AEscDown{}:
      {==}
    case C.AEscUp{}:
      {==}
    case C.AOtherKey{}:
      {==}
    case C.AClose{}:
      {==}
    case C.AOpen{id}:
      {==}
    case C.ADelete{id}:
      {==}
    case C.ANone{}:
      {==}

def Laws.esc_other_key_resets(h, t, c, d, k, e):
  %reset_tbl(h, t, c, d, k) : {_ == False{} : Bool}
  %Equal.sym(Bool, Laws.Spec.is_key(k), True{}, e) : {Bool.pick(Bool, _, False{}, Laws.Out.quit(C.Ui.out(C.Ui.step(C.Ui.step(C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{}), C.AEscUp{}), k), C.AEscDown{}))) == False{} : Bool}
  {==}

# 편집하면 dirty: dirty 의 다음 값은 "편집했는가 or 전 값" 이라는 표를 먼저 세운다.
def dirty_tbl(ui: C.Ui, a: C.Act) -> {Bool.or(Laws.Spec.edits(ui, a), Laws.Spec.dirty(ui)) == Laws.Spec.dirty(C.Ui.step(ui, a)) : Bool}:
  match ui a:
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ANone{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ANone{}:
      {==}

def Laws.edit_makes_dirty(ui, a, e):
  %dirty_tbl(ui, a) : {_ == True{} : Bool}
  %Equal.sym(Bool, Laws.Spec.edits(ui, a), True{}, e) : {Bool.or(_, Laws.Spec.dirty(ui)) == True{} : Bool}
  {==}

# ---------------------------------------------------------------------------
# 규칙 10. 자동 저장: 저장 명령 = 편집했으면 Some{다음 기록}, 아니면 None 이라는 표.
# ---------------------------------------------------------------------------

def save_spec(+ui: C.Ui, +a: C.Act) -> Maybe<&2, C.Hist>:
  Bool.pick(Maybe<&2, C.Hist>, Laws.Spec.edits(ui, a), Some{Laws.Spec.next_hist(ui, a)}, None{})

def save_tbl(ui: C.Ui, a: C.Act) -> {save_spec(ui, a) == Laws.Out.save(C.Ui.out(ui, a)) : Maybe<&2, C.Hist>}:
  match ui a:
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, C.Idle{}, di, he, ar} C.ANone{}:
      {==}
    case C.Ui{h, t, c, C.Dragging{path}, di, he, ar} C.ANone{}:
      {==}

def Laws.autosave(ui, a, e):
  %save_tbl(ui, a) : {_ == Some{Laws.Spec.next_hist(ui, a)} : Maybe<&2, C.Hist>}
  %Equal.sym(Bool, Laws.Spec.edits(ui, a), True{}, e) : {Bool.pick(Maybe<&2, C.Hist>, _, Some{Laws.Spec.next_hist(ui, a)}, None{}) == Some{Laws.Spec.next_hist(ui, a)} : Maybe<&2, C.Hist>}
  {==}

def Laws.no_save_otherwise(ui, a, e):
  %save_tbl(ui, a) : {_ == None{} : Maybe<&2, C.Hist>}
  %Equal.sym(Bool, Laws.Spec.edits(ui, a), False{}, e) : {Bool.pick(Maybe<&2, C.Hist>, _, Some{Laws.Spec.next_hist(ui, a)}, None{}) == None{} : Maybe<&2, C.Hist>}
  {==}

# ---------------------------------------------------------------------------
# 규칙 11. 캡처 바꾸기·지우기
# ---------------------------------------------------------------------------
def Laws.open_on_pick(ui, id):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.no_open_otherwise(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      tf({Laws.Out.open(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.AOpen{id})) == None{} : Maybe<&2, U32>}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

def Laws.delete_on_delete(ui, id):
  match ui:
    case C.Ui{h, t, c, d, di, he, ar}:
      {==}

def Laws.no_delete_otherwise(ui, a, e):
  match ui a:
    case C.Ui{h, t, c, d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, False{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARelease{x, y, True{}}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AUndo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ARedo{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopy{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{h, t, c, d, di, he, ar} C.ADelete{id}:
      tf({Laws.Out.delete(C.Ui.out(C.Ui{h, t, c, d, di, he, ar}, C.ADelete{id})) == None{} : Maybe<&2, U32>}, e)
    case C.Ui{h, t, c, d, di, he, ar} C.ANone{}:
      {==}

def Laws.open_starts_clean(h):
  {==}

# ---------------------------------------------------------------------------
# 규칙 8·9. 키 표와 캡처 판정: 글자 값이라 계산으로 닫힌다.
# ---------------------------------------------------------------------------

def Laws.key_table():
  {==}

def Laws.key_table_tools():
  {==}

def Laws.key_table_eraser():
  {==}

def Laws.op_make(t, c, p):
  {==}

def Laws.capture_verdicts():
  {==}

# ---------------------------------------------------------------------------
# 셸의 빠른 길. 셸은 Ui.out 에 ui 대신 Ui.peek(ui, a) 를 넘긴다 (shot.bend Act.run). 위 법칙은 모두
# Ui.out(ui, a) 에 관한 것이라, 두 값이 같아야 법칙이 셸에 닿는다. 복사는 항등이고 peek 는 Ui.out 이 읽는
# 몫만 복사하므로 같다. verify.py 가 이 정리의 이름과 셸의 호출 모양을 함께 지킨다.
# ---------------------------------------------------------------------------

def pts_copy(ps: List<&2, C.Pt>) -> {ps == C.Pts.copy(ps) : List<&2, C.Pt>}:
  match ps:
    case []:
      {==}
    case C.Pt{x, y} <> +rest:
      %pts_copy(rest) : {C.Pt{x, y} <> rest == C.Pt{x, y} <> _ : List<&2, C.Pt>}
      {==}

def ops_copy(os: List<&2, C.Op>) -> {os == C.Ops.copy(os) : List<&2, C.Op>}:
  match os:
    case []:
      {==}
    case C.Op{t, c, +path} <> +rest:
      %pts_copy(path) : {C.Op{t, c, path} <> rest == C.Op{t, c, _} <> C.Ops.copy(rest) : List<&2, C.Op>}
      %ops_copy(rest) : {C.Op{t, c, path} <> rest == C.Op{t, c, path} <> _ : List<&2, C.Op>}
      {==}

def hist_copy(h: C.Hist) -> {h == C.Hist.copy(h) : C.Hist}:
  match h:
    case C.Hist{+done, +redo}:
      %ops_copy(done) : {C.Hist{done, redo} == C.Hist{_, C.Ops.copy(redo)} : C.Hist}
      %ops_copy(redo) : {C.Hist{done, redo} == C.Hist{done, _} : C.Hist}
      {==}

def drag_copy(d: C.Drag) -> {d == C.Drag.copy(d) : C.Drag}:
  match d:
    case C.Idle{}:
      {==}
    case C.Dragging{+path}:
      %pts_copy(path) : {C.Dragging{path} == C.Dragging{_} : C.Drag}
      {==}

def Shell.peek_out(ui: C.Ui, a: C.Act) -> {C.Ui.out(C.Ui.peek(ui, a), a) == C.Ui.out(ui, a) : C.Out}:
  match ui a:
    case C.Ui{+h, t, c, +d, di, he, ar} C.APick{t2}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AColor{c2}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.APress{x, y}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AMove{x, y}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ARelease{x, y, False{}}:
      %hist_copy(h) : {C.Out{C.Hist.save_release(_, t, c, C.Drag.copy(d), x, y, False{}), None{}, False{}, None{}, None{}} == C.Out{C.Hist.save_release(h, t, c, d, x, y, False{}), None{}, False{}, None{}, None{}} : C.Out}
      %drag_copy(d) : {C.Out{C.Hist.save_release(h, t, c, _, x, y, False{}), None{}, False{}, None{}, None{}} == C.Out{C.Hist.save_release(h, t, c, d, x, y, False{}), None{}, False{}, None{}, None{}} : C.Out}
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ARelease{x, y, True{}}:
      %hist_copy(h) : {C.Out{C.Hist.save_release(_, t, c, C.Drag.copy(d), x, y, True{}), None{}, False{}, None{}, None{}} == C.Out{C.Hist.save_release(h, t, c, d, x, y, True{}), None{}, False{}, None{}, None{}} : C.Out}
      %drag_copy(d) : {C.Out{C.Hist.save_release(h, t, c, _, x, y, True{}), None{}, False{}, None{}, None{}} == C.Out{C.Hist.save_release(h, t, c, d, x, y, True{}), None{}, False{}, None{}, None{}} : C.Out}
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AUndo{}:
      %hist_copy(h) : {C.Out{Some{C.Hist.undo(_)}, None{}, False{}, None{}, None{}} == C.Out{Some{C.Hist.undo(h)}, None{}, False{}, None{}, None{}} : C.Out}
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ARedo{}:
      %hist_copy(h) : {C.Out{Some{C.Hist.redo(_)}, None{}, False{}, None{}, None{}} == C.Out{Some{C.Hist.redo(h)}, None{}, False{}, None{}, None{}} : C.Out}
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ACopy{}:
      %hist_copy(h) : {C.Out{None{}, Some{C.Hist.live(_)}, False{}, None{}, None{}} == C.Out{None{}, Some{C.Hist.live(h)}, False{}, None{}, None{}} : C.Out}
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ACopied{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ACopyFailed{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AEscDown{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AEscUp{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AOtherKey{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AClose{}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.AOpen{id}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ADelete{id}:
      {==}
    case C.Ui{+h, t, c, +d, di, he, ar} C.ANone{}:
      {==}

# 규칙 13: LAWS 의 peek_out 은 위 정리 그대로
def Laws.peek_out(ui, a):
  Shell.peek_out(ui, a)
