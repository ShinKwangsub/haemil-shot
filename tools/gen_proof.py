#!/usr/bin/env python3
# PROOF.bend 생성기 (python3 -I tools/gen_proof.py > PROOF.bend). 경우 나열(행동 18 × 끌기 2)을 손으로 쓰지 않으려고 둔다.
import sys

OP = "List<&2, C.Op>"
def Rv(xs, acc): return f"List.reverse.go(&2, C.Op, {xs}, {acc})"
def Ap(xs, ys): return f"List.append(&2, C.Op, {xs}, {ys})"
def Tk(xs, n): return f"List.take(&2, C.Op, {xs}, {n})"
def Ln(xs): return f"List.length(&2, C.Op, {xs})"

HEAD = f"""# BendShot 증명. `bend PROOF.bend` 가 ALL PROOFS CHECK 를 찍어야 한다.
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
    case False{{}}:
      Unit
    case True{{}}:
      Empty

def tf.go(e: {{False{{}} == True{{}} : Bool}}) -> disc(True{{}}):
  %e : disc(_)
  Unit{{}}

def tf(-P: Type, e: {{True{{}} == False{{}} : Bool}}) -> P:
  Empty.absurd(P, tf.go(Equal.sym(Bool, True{{}}, False{{}}, e)))

# ---------------------------------------------------------------------------
# 규칙 1 (시간선). 기록 Hist 와 기준 모형 Ref 는 편집 한 번마다 같이 움직인다 (sim).
# 목록 보조정리는 Base 의 List.reverse.go 누적 인자 모양을 그대로 따른다.
# ---------------------------------------------------------------------------

# 뒤집기 누적 인자 뒤에 붙이는 것은 먼저 붙이고 뒤집는 것과 같다.
def rev_go_app(xs: {OP}, acc: {OP}, ys: {OP})
  -> {{{Rv('xs', Ap('acc', 'ys'))} == {Ap(Rv('xs', 'acc'), 'ys')} : {OP}}}:
  match xs:
    case []:
      {{==}}
    case h <> t:
      rev_go_app(t, h <> acc, ys)

def add_succ(a: Nat, b: Nat) -> {{Nat.add(a, 1n+b) == 1n+Nat.add(a, b) : Nat}}:
  match a:
    case 0n:
      {{==}}
    case 1n+p:
      %add_succ(p, b) : {{1n+Nat.add(p, 1n+b) == 1n+_ : Nat}}
      {{==}}

def add_zero(a: Nat) -> {{Nat.add(a, 0n) == a : Nat}}:
  match a:
    case 0n:
      {{==}}
    case 1n+p:
      %add_zero(p) : {{1n+Nat.add(p, 0n) == 1n+_ : Nat}}
      {{==}}

def take_zero(xs: {OP}) -> {{[] == {Tk('xs', '0n')} : {OP}}}:
  match xs:
    case []:
      {{==}}
    case h <> t:
      {{==}}

# 뒤집은 목록의 앞 length(xs)+k 개 = 누적 인자의 앞 k 개만 남기고 뒤집은 것.
def take_rev(xs: {OP}, acc: {OP}, +k: Nat)
  -> {{{Rv('xs', Tk('acc', 'k'))} == {Tk(Rv('xs', 'acc'), f"Nat.add({Ln('xs')}, k)")} : {OP}}}:
  match xs:
    case []:
      {{==}}
    case h <> +t:
      %add_succ({Ln('t')}, k) : {{{Rv('t', f"h <> {Tk('acc', 'k')}")} == {Tk(Rv('t', 'h <> acc'), '_')} : {OP}}}
      take_rev(t, h <> acc, 1n+k)

def len_rev_go(xs: {OP}, +acc: {OP})
  -> {{Nat.add({Ln('xs')}, {Ln('acc')}) == {Ln(Rv('xs', 'acc'))} : Nat}}:
  match xs:
    case []:
      {{==}}
    case h <> +t:
      %len_rev_go(t, h <> acc) : {{1n+Nat.add({Ln('t')}, {Ln('acc')}) == _ : Nat}}
      %add_succ({Ln('t')}, {Ln('acc')}) : {{_ == Nat.add({Ln('t')}, 1n+{Ln('acc')}) : Nat}}
      {{==}}

def lt_add0(n: Nat) -> {{False{{}} == Nat.is_lt(n, Nat.add(n, 0n)) : Bool}}:
  match n:
    case 0n:
      {{==}}
    case 1n+p:
      lt_add0(p)

def lt_succ_add(n: Nat, m: Nat) -> {{True{{}} == Nat.is_lt(n, Nat.add(n, 1n+m)) : Bool}}:
  match n:
    case 0n:
      {{==}}
    case 1n+p:
      lt_succ_add(p, m)

# 편집 한 번: 기록을 기준 모형으로 읽은 것 = 기준 모형을 한 칸 움직인 것.
def sim(h: C.Hist, e: Laws.Edit) -> {{Laws.Ref.of(Laws.Hist.edit(h, e)) == Laws.Ref.step(Laws.Ref.of(h), e) : Laws.Ref}}:
  match h e:
    case C.Hist{{+done, +redo}} Laws.ECommit{{+op}}:
      %rev_go_app(done, [op], []) : {{Laws.Ref{{_, 1n+{Ln('done')}}} == Laws.Ref{{{Ap(Tk(Ap(Rv('done', '[]'), 'redo'), Ln('done')), '[op]')}, 1n+{Ln('done')}}} : Laws.Ref}}
      %rev_go_app(done, [], redo) : {{Laws.Ref{{{Rv('done', '[op]')}, 1n+{Ln('done')}}} == Laws.Ref{{{Ap(Tk('_', Ln('done')), '[op]')}, 1n+{Ln('done')}}} : Laws.Ref}}
      %add_zero({Ln('done')}) : {{Laws.Ref{{{Rv('done', '[op]')}, 1n+{Ln('done')}}} == Laws.Ref{{{Ap(Tk(Rv('done', 'redo'), '_'), '[op]')}, 1n+{Ln('done')}}} : Laws.Ref}}
      %take_rev(done, redo, 0n) : {{Laws.Ref{{{Rv('done', '[op]')}, 1n+{Ln('done')}}} == Laws.Ref{{{Ap('_', '[op]')}, 1n+{Ln('done')}}} : Laws.Ref}}
      %take_zero(redo) : {{Laws.Ref{{{Rv('done', '[op]')}, 1n+{Ln('done')}}} == Laws.Ref{{{Ap(Rv('done', '_'), '[op]')}, 1n+{Ln('done')}}} : Laws.Ref}}
      %rev_go_app(done, [], [op]) : {{Laws.Ref{{{Rv('done', '[op]')}, 1n+{Ln('done')}}} == Laws.Ref{{_, 1n+{Ln('done')}}} : Laws.Ref}}
      {{==}}
    case C.Hist{{[], redo}} Laws.EUndo{{}}:
      {{==}}
    case C.Hist{{+d <> +ds, +redo}} Laws.EUndo{{}}:
      %rev_go_app(ds, [], d <> redo) : {{Laws.Ref{{_, {Ln('ds')}}} == Laws.Ref{{{Ap(Rv('ds', '[d]'), 'redo')}, {Ln('ds')}}} : Laws.Ref}}
      %rev_go_app(ds, [d], redo) : {{Laws.Ref{{{Rv('ds', 'd <> redo')}, {Ln('ds')}}} == Laws.Ref{{_, {Ln('ds')}}} : Laws.Ref}}
      {{==}}
    case C.Hist{{+done, []}} Laws.ERedo{{}}:
      %rev_go_app(done, [], []) : {{Laws.Ref{{_, {Ln('done')}}} == Laws.Ref.redo(_, {Ln('done')}, Nat.is_lt({Ln('done')}, {Ln('_')})) : Laws.Ref}}
      %len_rev_go(done, []) : {{Laws.Ref{{{Rv('done', '[]')}, {Ln('done')}}} == Laws.Ref.redo({Rv('done', '[]')}, {Ln('done')}, Nat.is_lt({Ln('done')}, _)) : Laws.Ref}}
      %lt_add0({Ln('done')}) : {{Laws.Ref{{{Rv('done', '[]')}, {Ln('done')}}} == Laws.Ref.redo({Rv('done', '[]')}, {Ln('done')}, _) : Laws.Ref}}
      {{==}}
    case C.Hist{{+done, +r <> +rs}} Laws.ERedo{{}}:
      %rev_go_app(done, [r], rs) : {{Laws.Ref{{_, 1n+{Ln('done')}}} == Laws.Ref.redo({Ap(Rv('done', '[]'), 'r <> rs')}, {Ln('done')}, Nat.is_lt({Ln('done')}, {Ln(Ap(Rv('done', '[]'), 'r <> rs'))})) : Laws.Ref}}
      %rev_go_app(done, [], r <> rs) : {{Laws.Ref{{{Rv('done', 'r <> rs')}, 1n+{Ln('done')}}} == Laws.Ref.redo(_, {Ln('done')}, Nat.is_lt({Ln('done')}, {Ln('_')})) : Laws.Ref}}
      %len_rev_go(done, r <> rs) : {{Laws.Ref{{{Rv('done', 'r <> rs')}, 1n+{Ln('done')}}} == Laws.Ref.redo({Rv('done', 'r <> rs')}, {Ln('done')}, Nat.is_lt({Ln('done')}, _)) : Laws.Ref}}
      %lt_succ_add({Ln('done')}, {Ln('rs')}) : {{Laws.Ref{{{Rv('done', 'r <> rs')}, 1n+{Ln('done')}}} == Laws.Ref.redo({Rv('done', 'r <> rs')}, {Ln('done')}, _) : Laws.Ref}}
      {{==}}

def run_sim(+es: List<&2, Laws.Edit>, +h: C.Hist) -> {{Laws.Ref.of(Laws.Hist.run(es, h)) == Laws.Ref.run(es, Laws.Ref.of(h)) : Laws.Ref}}:
  match es:
    case []:
      {{==}}
    case e <> rest:
      %sim(h, e) : {{Laws.Ref.of(Laws.Hist.run(rest, Laws.Hist.edit(h, e))) == Laws.Ref.run(rest, _) : Laws.Ref}}
      run_sim(rest, Laws.Hist.edit(h, e))

# 살아 있는 Op = 기준 모형에서 손가락까지.
def live_of(h: C.Hist) -> {{C.Hist.live(h) == Laws.Ref.live(Laws.Ref.of(h)) : {OP}}}:
  match h:
    case C.Hist{{+done, +redo}}:
      %rev_go_app(done, [], redo) : {{{Rv('done', '[]')} == {Tk('_', Ln('done'))} : {OP}}}
      %add_zero({Ln('done')}) : {{{Rv('done', '[]')} == {Tk(Rv('done', 'redo'), '_')} : {OP}}}
      %take_rev(done, redo, 0n) : {{{Rv('done', '[]')} == _ : {OP}}}
      %take_zero(redo) : {{{Rv('done', '[]')} == {Rv('done', '_')} : {OP}}}
      {{==}}

def Laws.timeline(es, h):
  %run_sim(es, h) : {{C.Hist.live(Laws.Hist.run(es, h)) == Laws.Ref.live(_) : {OP}}}
  live_of(Laws.Hist.run(es, h))
"""

# 행동 패턴. ARelease 는 empty 를 Bool 두 값으로 나눈다 (Spec 표가 그 값을 본다).
ACTS = [
    "C.APick{t2}", "C.AColor{c2}", "C.APress{x, y}", "C.AMove{x, y}",
    "C.ARelease{x, y, False{}}", "C.ARelease{x, y, True{}}",
    "C.AUndo{}", "C.ARedo{}", "C.ACopy{}", "C.ACopied{}", "C.ACopyFailed{}",
    "C.AEscDown{}", "C.AEscUp{}", "C.AOtherKey{}", "C.AClose{}",
    "C.AOpen{id}", "C.ADelete{id}", "C.ANone{}",
]
DRAGS = ["C.Idle{}", "C.Dragging{path}"]
UI = "C.Ui{h, t, c, d, di, he, ar}"

def act_name(a):
    return a.split("{")[0].split(".")[1]

def table(name, goal, split_drag):
    """goal: 함수 (ui, a) -> 식. 모든 경우 {==}."""
    out = [f"def {name}(ui: C.Ui, a: C.Act) -> {goal('ui', 'a')}:", "  match ui a:"]
    for a in ACTS:
        if split_drag:
            for d in DRAGS:
                out.append(f"    case C.Ui{{h, t, c, {d}, di, he, ar}} {a}:")
                out.append("      {==}")
        else:
            out.append(f"    case {UI} {a}:")
            out.append("      {==}")
    return "\n".join(out) + "\n"

def law_direct(name, goal, refute, hyp=True):
    """가설 하나짜리 법칙. refute 에 든 행동은 가설이 True == False 가 되어 tf 로 닫는다."""
    params = "ui, a, e" if hyp else "ui, a"
    out = [f"def Laws.{name}({params}):", "  match ui a:"]
    for a in ACTS:
        out.append(f"    case {UI} {a}:")
        if act_name(a) in refute:
            out.append(f"      tf({goal(UI, a)}, e)")
        else:
            out.append("      {==}")
    return "\n".join(out) + "\n"

def law_ui(name, params="ui"):
    return f"""def Laws.{name}({params}):
  match ui:
    case {UI}:
      {{==}}
"""

parts = [HEAD]

parts.append("""
# ---------------------------------------------------------------------------
# 규칙 2·3. 기록과 끌기는 의도 표대로. 끌기 상태까지 쪼개야 Spec 표가 계산된다.
# ---------------------------------------------------------------------------
""")
def law_table_nohyp(name):
    out = [f"def Laws.{name}(ui, a):", "  match ui a:"]
    for a in ACTS:
        for d in DRAGS:
            out.append(f"    case C.Ui{{h, t, c, {d}, di, he, ar}} {a}:")
            out.append("      {==}")
    return "\n".join(out) + "\n"
parts.append(law_table_nohyp("hist_by_table"))
parts.append("\n")
parts.append(law_table_nohyp("drag_by_table"))

parts.append("""
# 도구·색은 고르기로만 바뀐다.
""")
parts.append(law_ui("pick_sets_tool", "ui, t"))
parts.append("\n")
parts.append(law_direct("tool_kept",
    lambda u, a: f"{{Laws.Spec.tool(C.Ui.step({u}, {a})) == Laws.Spec.tool({u}) : C.Tool}}",
    {"APick"}))
parts.append("\n")
parts.append(law_ui("color_sets_color", "ui, c"))
parts.append("\n")
parts.append(law_direct("color_kept",
    lambda u, a: f"{{Laws.Spec.color(C.Ui.step({u}, {a})) == Laws.Spec.color({u}) : C.Color}}",
    {"AColor"}))

parts.append("""
# ---------------------------------------------------------------------------
# 규칙 4·5. 복사와 닫기
# ---------------------------------------------------------------------------
""")
parts.append(law_ui("copy_on_enter"))
parts.append("\n")
parts.append(law_direct("no_copy_otherwise",
    lambda u, a: f"{{Laws.Out.copy(C.Ui.out({u}, {a})) == None{{}} : Maybe<&2, {OP}>}}",
    {"ACopy"}))
parts.append("\n")
parts.append(law_direct("quit_only_when",
    lambda u, a: f"{{Laws.Out.quit(C.Ui.out({u}, {a})) == False{{}} : Bool}}",
    {"AEscDown", "AClose", "ACopied"}))
parts.append("\n")
parts.append(law_ui("close_button_quits"))
parts.append("\n")
parts.append(law_ui("copied_quits"))
parts.append("\n")
parts.append(law_ui("copy_failed_keeps"))

Q = "Laws.Out.quit(C.Ui.out(C.Ui.step(C.Ui.step(C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{}), C.AEscUp{}), k), C.AEscDown{}))"
reset_cases = "\n".join(f"    case {a.replace('t2', 'kt').replace('c2', 'kc')}:\n      {{==}}" for a in ACTS)
parts.append(f"""
# Esc 기계: 깃발(dirty·held·armed)이 글자 값이라 모두 계산으로 닫힌다.
def Laws.esc_clean_quits(h, t, c, d, ar):
  {{==}}

def Laws.esc_dirty_first_warns(h, t, c, d):
  {{==}}

def Laws.esc_dirty_twice_quits(h, t, c, d):
  {{==}}

def Laws.esc_dirty_twice_with_move_quits(h, t, c, d, x, y):
  {{==}}

def Laws.esc_repeat_not_twice(h, t, c, d):
  {{==}}

# 다른 키 k 뒤의 닫기 값: k 가 키 행동이면 False, 아니면 제 값 그대로 (반사).
def reset_tbl(h: C.Hist, t: C.Tool, c: C.Color, d: C.Drag, k: C.Act) -> {{Bool.pick(Bool, Laws.Spec.is_key(k), False{{}}, {Q}) == {Q} : Bool}}:
  match k:
{reset_cases}

def Laws.esc_other_key_resets(h, t, c, d, k, e):
  %reset_tbl(h, t, c, d, k) : {{_ == False{{}} : Bool}}
  %Equal.sym(Bool, Laws.Spec.is_key(k), True{{}}, e) : {{Bool.pick(Bool, _, False{{}}, {Q}) == False{{}} : Bool}}
  {{==}}

# 편집하면 dirty: dirty 의 다음 값은 "편집했는가 or 전 값" 이라는 표를 먼저 세운다.
""")
parts.append(table("dirty_tbl",
    lambda u, a: f"{{Bool.or(Laws.Spec.edits({u}, {a}), Laws.Spec.dirty({u})) == Laws.Spec.dirty(C.Ui.step({u}, {a})) : Bool}}",
    True))
parts.append("""
def Laws.edit_makes_dirty(ui, a, e):
  %dirty_tbl(ui, a) : {_ == True{} : Bool}
  %Equal.sym(Bool, Laws.Spec.edits(ui, a), True{}, e) : {Bool.or(_, Laws.Spec.dirty(ui)) == True{} : Bool}
  {==}

# ---------------------------------------------------------------------------
# 규칙 10. 자동 저장: 저장 명령 = 편집했으면 Some{다음 기록}, 아니면 None 이라는 표.
# ---------------------------------------------------------------------------

def save_spec(+ui: C.Ui, +a: C.Act) -> Maybe<&2, C.Hist>:
  Bool.pick(Maybe<&2, C.Hist>, Laws.Spec.edits(ui, a), Some{Laws.Spec.next_hist(ui, a)}, None{})

""")
parts.append(table("save_tbl",
    lambda u, a: f"{{save_spec({u}, {a}) == Laws.Out.save(C.Ui.out({u}, {a})) : Maybe<&2, C.Hist>}}",
    True))
parts.append("""
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
""")
parts.append(law_ui("open_on_pick", "ui, id"))
parts.append("\n")
parts.append(law_direct("no_open_otherwise",
    lambda u, a: f"{{Laws.Out.open(C.Ui.out({u}, {a})) == None{{}} : Maybe<&2, U32>}}",
    {"AOpen"}))
parts.append("\n")
parts.append(law_ui("delete_on_delete", "ui, id"))
parts.append("\n")
parts.append(law_direct("no_delete_otherwise",
    lambda u, a: f"{{Laws.Out.delete(C.Ui.out({u}, {a})) == None{{}} : Maybe<&2, U32>}}",
    {"ADelete"}))
parts.append("""
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

def ops_copy(os: """ + OP + """) -> {os == C.Ops.copy(os) : """ + OP + """}:
  match os:
    case []:
      {==}
    case C.Op{t, c, +path} <> +rest:
      %pts_copy(path) : {C.Op{t, c, path} <> rest == C.Op{t, c, _} <> C.Ops.copy(rest) : """ + OP + """}
      %ops_copy(rest) : {C.Op{t, c, path} <> rest == C.Op{t, c, path} <> _ : """ + OP + """}
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

""")

def peek_rewrites(a):
    """행동 a 에서 Ui.peek 가 복사한 몫(_)을 원래 값으로 되돌리는 줄들. 되돌린 뒤의 목표를 그대로 적는다."""
    name = act_name(a)
    if name == "ARelease":
        empty = a.split(", ")[-1][:-1]
        rel = lambda h, d: f"C.Out{{C.Hist.save_release({h}, t, c, {d}, x, y, {empty}), None{{}}, False{{}}, None{{}}, None{{}}}}"
        return [f"      %hist_copy(h) : {{{rel('_', 'C.Drag.copy(d)')} == {rel('h', 'd')} : C.Out}}",
                f"      %drag_copy(d) : {{{rel('h', '_')} == {rel('h', 'd')} : C.Out}}"]
    out = {"AUndo": "C.Out{Some{C.Hist.undo(%s)}, None{}, False{}, None{}, None{}}",
           "ARedo": "C.Out{Some{C.Hist.redo(%s)}, None{}, False{}, None{}, None{}}",
           "ACopy": "C.Out{None{}, Some{C.Hist.live(%s)}, False{}, None{}, None{}}"}.get(name)
    return [f"      %hist_copy(h) : {{{out % '_'} == {out % 'h'} : C.Out}}"] if out else []

peek_out = ["def Shell.peek_out(ui: C.Ui, a: C.Act) -> {C.Ui.out(C.Ui.peek(ui, a), a) == C.Ui.out(ui, a) : C.Out}:",
            "  match ui a:"]
for a in ACTS:
    peek_out.append(f"    case C.Ui{{+h, t, c, +d, di, he, ar}} {a}:")
    peek_out.extend(peek_rewrites(a))
    peek_out.append("      {==}")
parts.append("\n".join(peek_out) + "\n")
parts.append("\n# 규칙 13: LAWS 의 peek_out 은 위 정리 그대로\ndef Laws.peek_out(ui, a):\n  Shell.peek_out(ui, a)\n")

sys.stdout.write("".join(parts))
