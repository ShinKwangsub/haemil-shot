# BendShot 규칙 (광섭이 2026-10-27 확정한 v3, 원문 docs/bend-laws/law-draft-v3.md).
# 이 파일은 광섭의 것이다. AI 는 고치지 않는다. 증명은 PROOF.bend 에 쓴다.
# 관문: `~/.bend/bin/bend PROOF.bend` 가 ALL PROOFS CHECK 여야 한다.
#
# 증명으로 지키지 않고 구조·검사로 지키는 것 (규칙 6·7·12, 보관 30개, 저장 파일 왕복):
#   - 원본 그림과 화면 그림은 core 상태(Ui)에 없다. 셸이 원본을 들고, 화면·내보내기는
#     언제나 (원본, Hist.live) 에서 새로 만든다. 그래서 원본은 바뀔 수 없고, 화면을 따로
#     고쳐 들고 있다가 어긋날 수도 없다. verify.py 가 Ui 에 그림이 없음을 확인한다.
#   - 편집기는 원본 파일에 쓰지 않는다. 캡처는 최근 30개까지 보관하고 넘치면 오래된 것부터
#     지운다. 기록 파일은 저장했다 다시 읽으면 같다. 모두 verify.py 검사.

import Base
import ./core.bend as C

# ---------------------------------------------------------------------------
# 값 읽기 (구현 쪽이 바꿔 치기 못 하게 여기서 정의한다)
# ---------------------------------------------------------------------------

def Spec.hist(ui: C.Ui) -> C.Hist:
  match ui:
    case C.Ui{h, _, _, _, _, _, _}:
      h

def Spec.tool(ui: C.Ui) -> C.Tool:
  match ui:
    case C.Ui{_, t, _, _, _, _, _}:
      t

def Spec.color(ui: C.Ui) -> C.Color:
  match ui:
    case C.Ui{_, _, c, _, _, _, _}:
      c

def Spec.drag(ui: C.Ui) -> C.Drag:
  match ui:
    case C.Ui{_, _, _, d, _, _, _}:
      d

def Spec.dirty(ui: C.Ui) -> Bool:
  match ui:
    case C.Ui{_, _, _, _, d, _, _}:
      d

def Out.save(o: C.Out) -> Maybe<&2, C.Hist>:
  match o:
    case C.Out{s, _, _, _, _}:
      s

def Out.copy(o: C.Out) -> Maybe<&2, List<&2, C.Op>>:
  match o:
    case C.Out{_, c, _, _, _}:
      c

def Out.quit(o: C.Out) -> Bool:
  match o:
    case C.Out{_, _, q, _, _}:
      q

def Out.open(o: C.Out) -> Maybe<&2, U32>:
  match o:
    case C.Out{_, _, _, op, _}:
      op

def Out.delete(o: C.Out) -> Maybe<&2, U32>:
  match o:
    case C.Out{_, _, _, _, d}:
      d

# ---------------------------------------------------------------------------
# 기준 모형: 상태들을 한 줄로 늘어놓고 손가락으로 현재를 가리킨다
# ---------------------------------------------------------------------------

type Edit is Data:
  ECommit{op: C.Op}
  EUndo{}
  ERedo{}

type Ref is Data:
  Ref{all: List<&2, C.Op>, cur: Nat}

# 기록을 기준 모형으로 읽기: 살아 있는 것(오래된 것부터) 뒤에 다시 실행할 것들, 손가락은 살아 있는 개수.
def Ref.of(h: C.Hist) -> Ref:
  match h:
    case C.Hist{+done, redo}:
      Ref{List.append(&2, C.Op, List.reverse(&2, C.Op, done), redo), List.length(&2, C.Op, done)}

def Ref.live(r: Ref) -> List<&2, C.Op>:
  match r:
    case Ref{all, cur}:
      List.take(&2, C.Op, all, cur)

def Ref.redo(all: List<&2, C.Op>, cur: Nat, room: Bool) -> Ref:
  match room:
    case True{}:
      Ref{all, 1n+cur}
    case False{}:
      Ref{all, cur}

def Ref.step(r: Ref, e: Edit) -> Ref:
  match r e:
    case Ref{all, +cur} ECommit{op}:
      Ref{List.append(&2, C.Op, List.take(&2, C.Op, all, cur), [op]), 1n+cur}
    case Ref{all, 0n} EUndo{}:
      Ref{all, 0n}
    case Ref{all, 1n+p} EUndo{}:
      Ref{all, p}
    case Ref{+all, +cur} ERedo{}:
      Ref.redo(all, cur, Nat.is_lt(cur, List.length(&2, C.Op, all)))

def Ref.run(es: List<&2, Edit>, r: Ref) -> Ref:
  match es:
    case []:
      r
    case e <> rest:
      Ref.run(rest, Ref.step(r, e))

def Hist.edit(h: C.Hist, e: Edit) -> C.Hist:
  match e:
    case ECommit{op}:
      C.Hist.commit(h, op)
    case EUndo{}:
      C.Hist.undo(h)
    case ERedo{}:
      C.Hist.redo(h)

def Hist.run(es: List<&2, Edit>, h: C.Hist) -> C.Hist:
  match es:
    case []:
      h
    case e <> rest:
      Hist.run(rest, Hist.edit(h, e))

# ---------------------------------------------------------------------------
# 의도 표: 행동 한 칸이 무엇을 바꾸는지 사람이 정한 표
# ---------------------------------------------------------------------------

# 기록이 어떻게 바뀌는가. 끌기 중 떼기(빈 것이 아니면)는 그 도구·색·경로의 Op 하나를 확정,
# 되돌리기·다시 실행은 그대로, 나머지는 기록을 바꾸지 않는다.
def Spec.next_hist(ui: C.Ui, a: C.Act) -> C.Hist:
  match ui a:
    case C.Ui{h, t, c, C.Dragging{path}, _, _, _} C.ARelease{x, y, False{}}:
      C.Hist.commit(h, C.Op.make(t, c, C.Pt{x, y} <> path))
    case C.Ui{h, _, _, _, _, _, _} C.AUndo{}:
      C.Hist.undo(h)
    case C.Ui{h, _, _, _, _, _, _} C.ARedo{}:
      C.Hist.redo(h)
    case C.Ui{h, _, _, _, _, _, _} _:
      h

# 기록을 바꾸는 행동인가 (자동 저장 대상).
def Spec.edits(ui: C.Ui, a: C.Act) -> Bool:
  match ui a:
    case C.Ui{_, _, _, C.Dragging{_}, _, _, _} C.ARelease{_, _, False{}}:
      True{}
    case _ C.AUndo{}:
      True{}
    case _ C.ARedo{}:
      True{}
    case _ _:
      False{}

# 끌기가 어떻게 되는가. 누르면 시작, 끌면 점이 쌓이고, 떼기·도구·색·되돌리기·다시 실행·
# 복사·캡처 바꾸기·지우기는 끌기를 끝낸다(기록 상태와 상관없이).
def Spec.next_drag(ui: C.Ui, a: C.Act) -> C.Drag:
  match ui a:
    case C.Ui{_, _, _, C.Idle{}, _, _, _} C.APress{x, y}:
      C.Dragging{[C.Pt{x, y}]}
    case C.Ui{_, _, _, C.Dragging{path}, _, _, _} C.AMove{x, y}:
      C.Dragging{C.Pt{x, y} <> path}
    case _ C.ARelease{_, _, _}:
      C.Idle{}
    case _ C.APick{_}:
      C.Idle{}
    case _ C.AColor{_}:
      C.Idle{}
    case _ C.AUndo{}:
      C.Idle{}
    case _ C.ARedo{}:
      C.Idle{}
    case _ C.ACopy{}:
      C.Idle{}
    case _ C.AOpen{_}:
      C.Idle{}
    case _ C.ADelete{_}:
      C.Idle{}
    case C.Ui{_, _, _, d, _, _, _} _:
      d

# 닫기 명령을 낼 수 있는 행동: Esc 누름, 창 닫기 단추, 복사 성공.
def Spec.may_quit(a: C.Act) -> Bool:
  match a:
    case C.AEscDown{}:
      True{}
    case C.AClose{}:
      True{}
    case C.ACopied{}:
      True{}
    case _:
      False{}

# Esc 경고 대기를 푸는 다른 키 행동.
def Spec.is_key(a: C.Act) -> Bool:
  match a:
    case C.APick{_}:
      True{}
    case C.AColor{_}:
      True{}
    case C.AUndo{}:
      True{}
    case C.ARedo{}:
      True{}
    case C.AOtherKey{}:
      True{}
    case _:
      False{}

def Spec.is_copy(a: C.Act) -> Bool:
  match a:
    case C.ACopy{}:
      True{}
    case _:
      False{}

def Spec.is_pick(a: C.Act) -> Bool:
  match a:
    case C.APick{_}:
      True{}
    case _:
      False{}

def Spec.is_color(a: C.Act) -> Bool:
  match a:
    case C.AColor{_}:
      True{}
    case _:
      False{}

def Spec.is_open(a: C.Act) -> Bool:
  match a:
    case C.AOpen{_}:
      True{}
    case _:
      False{}

def Spec.is_delete(a: C.Act) -> Bool:
  match a:
    case C.ADelete{_}:
      True{}
    case _:
      False{}

# ---------------------------------------------------------------------------
# 규칙 1. 시간선
# 어떤 편집 목록이든, 실제로 그리고 내보내는 데 쓰는 살아 있는 Op = 기준 모형에서 손가락까지의 Op.
# 확정은 손가락 뒤를 자르고 붙인 뒤 손가락을 옮기고, 되돌리기는 한 칸 뒤, 다시 실행은 한 칸 앞,
# 양 끝에서는 멈춘다.
# ---------------------------------------------------------------------------

law timeline:
  for +es: List<&2, Edit>
  for +h: C.Hist
  {C.Hist.live(Hist.run(es, h)) == Ref.live(Ref.run(es, Ref.of(h))) : List<&2, C.Op>}

# ---------------------------------------------------------------------------
# 규칙 2·3. 한 통로, 의도대로
# 기록은 확정·되돌리기·다시 실행으로만, 의도 표대로 바뀐다. 끌기도 의도 표대로 움직인다.
# ---------------------------------------------------------------------------

law hist_by_table:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.hist(C.Ui.step(ui, a)) == Spec.next_hist(ui, a) : C.Hist}

law drag_by_table:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.drag(C.Ui.step(ui, a)) == Spec.next_drag(ui, a) : C.Drag}

# 도구는 도구 고르기로만, 색은 색 고르기로만 바뀐다.
law pick_sets_tool:
  for +ui: C.Ui
  for +t: C.Tool
  {Spec.tool(C.Ui.step(ui, C.APick{t})) == t : C.Tool}

law tool_kept:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.is_pick(a) == False{} : Bool} -> {Spec.tool(C.Ui.step(ui, a)) == Spec.tool(ui) : C.Tool}

law color_sets_color:
  for +ui: C.Ui
  for +c: C.Color
  {Spec.color(C.Ui.step(ui, C.AColor{c})) == c : C.Color}

law color_kept:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.is_color(a) == False{} : Bool} -> {Spec.color(C.Ui.step(ui, a)) == Spec.color(ui) : C.Color}

# ---------------------------------------------------------------------------
# 규칙 4. Enter 면 반드시 복사, Enter 가 아니면 복사 없음
# 복사 명령에 실린 것은 그 순간 살아 있는 Op 전부(끌던 것은 들어가지 않는다).
# ---------------------------------------------------------------------------

law copy_on_enter:
  for +ui: C.Ui
  {Out.copy(C.Ui.out(ui, C.ACopy{})) == Some{C.Hist.live(Spec.hist(ui))} : Maybe<&2, List<&2, C.Op>>}

law no_copy_otherwise:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.is_copy(a) == False{} : Bool} -> {Out.copy(C.Ui.out(ui, a)) == None{} : Maybe<&2, List<&2, C.Op>>}

# ---------------------------------------------------------------------------
# 규칙 5. 닫기는 정해진 때에만, 그때는 반드시
# 창 닫기 단추와 복사 성공은 바로 닫는다. 편집한 게 없으면 Esc 한 번에 닫는다.
# 편집한 게 있으면 첫 Esc 는 닫지 않고, 떼었다가 다른 키 없이 다시 누르면 닫는다
# (마우스 움직임은 상관없고, 누른 채 자동 반복은 두 번으로 치지 않는다).
# 복사가 실패하면 상태도 창도 그대로다.
# ---------------------------------------------------------------------------

law quit_only_when:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.may_quit(a) == False{} : Bool} -> {Out.quit(C.Ui.out(ui, a)) == False{} : Bool}

law close_button_quits:
  for +ui: C.Ui
  {Out.quit(C.Ui.out(ui, C.AClose{})) == True{} : Bool}

law copied_quits:
  for +ui: C.Ui
  {Out.quit(C.Ui.out(ui, C.ACopied{})) == True{} : Bool}

law copy_failed_keeps:
  for +ui: C.Ui
  {C.Ui.step(ui, C.ACopyFailed{}) == ui : C.Ui}

law esc_clean_quits:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  for +ar: Bool
  {Out.quit(C.Ui.out(C.Ui{h, t, c, d, False{}, False{}, ar}, C.AEscDown{})) == True{} : Bool}

law esc_dirty_first_warns:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  {Out.quit(C.Ui.out(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{})) == False{} : Bool}

law esc_dirty_twice_quits:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  ui1 = C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{})
  ui2 = C.Ui.step(ui1, C.AEscUp{})
  {Out.quit(C.Ui.out(ui2, C.AEscDown{})) == True{} : Bool}

law esc_dirty_twice_with_move_quits:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  for +x: U32
  for +y: U32
  ui1 = C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{})
  ui2 = C.Ui.step(ui1, C.AEscUp{})
  ui3 = C.Ui.step(ui2, C.AMove{x, y})
  {Out.quit(C.Ui.out(ui3, C.AEscDown{})) == True{} : Bool}

law esc_repeat_not_twice:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  ui1 = C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{})
  {Out.quit(C.Ui.out(ui1, C.AEscDown{})) == False{} : Bool}

law esc_other_key_resets:
  for +h: C.Hist
  for +t: C.Tool
  for +c: C.Color
  for +d: C.Drag
  for +k: C.Act
  {Spec.is_key(k) == True{} : Bool} -> {Out.quit(C.Ui.out(C.Ui.step(C.Ui.step(C.Ui.step(C.Ui{h, t, c, d, True{}, False{}, False{}}, C.AEscDown{}), C.AEscUp{}), k), C.AEscDown{})) == False{} : Bool}

# 기록을 바꾸면 "편집한 게 있음" 이 된다.
law edit_makes_dirty:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.edits(ui, a) == True{} : Bool} -> {Spec.dirty(C.Ui.step(ui, a)) == True{} : Bool}

# ---------------------------------------------------------------------------
# 규칙 10. 자동 저장
# 기록을 바꾸는 모든 행동(확정·되돌리기·다시 실행) 에는 그 뒤 기록 전체를 실은 저장 명령이 나오고,
# 기록을 바꾸지 않는 행동에는 나오지 않는다.
# ---------------------------------------------------------------------------

law autosave:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.edits(ui, a) == True{} : Bool} -> {Out.save(C.Ui.out(ui, a)) == Some{Spec.next_hist(ui, a)} : Maybe<&2, C.Hist>}

law no_save_otherwise:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.edits(ui, a) == False{} : Bool} -> {Out.save(C.Ui.out(ui, a)) == None{} : Maybe<&2, C.Hist>}

# ---------------------------------------------------------------------------
# 규칙 11. 캡처 바꾸기·지우기
# 목록에서 고르면 그 캡처를 여는 명령만 나오고(기록은 규칙 2 에 따라 그대로), 연 캡처는 저장된 기록
# 그대로 시작한다. 지우기 명령은 지우기 행동에서만, 그 캡처에 대해서만 나온다.
# ---------------------------------------------------------------------------

law open_on_pick:
  for +ui: C.Ui
  for +id: U32
  {Out.open(C.Ui.out(ui, C.AOpen{id})) == Some{id} : Maybe<&2, U32>}

law no_open_otherwise:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.is_open(a) == False{} : Bool} -> {Out.open(C.Ui.out(ui, a)) == None{} : Maybe<&2, U32>}

law delete_on_delete:
  for +ui: C.Ui
  for +id: U32
  {Out.delete(C.Ui.out(ui, C.ADelete{id})) == Some{id} : Maybe<&2, U32>}

law no_delete_otherwise:
  for +ui: C.Ui
  for +a: C.Act
  {Spec.is_delete(a) == False{} : Bool} -> {Out.delete(C.Ui.out(ui, a)) == None{} : Maybe<&2, U32>}

law open_starts_clean:
  for +h: C.Hist
  {(Spec.hist(C.Ui.open(h)), Spec.drag(C.Ui.open(h)), Spec.dirty(C.Ui.open(h))) == (h, C.Idle{}, False{}) : C.Hist & C.Drag & Bool}

# ---------------------------------------------------------------------------
# 규칙 8. 키 표 (계산으로 확인)
# Enter 누름 → 복사, Esc 누름·뗌 → Esc, Z·ㅋ → 되돌리기, Y·ㅛ → 다시 실행, 1·2·3 → 도구,
# Enter 뗌 → 아무 일 없음, 그 밖의 글자 누름 → 다른 키. (도구·색이 늘면 광섭 확인 뒤 줄을 더한다.)
# 2026-10-27 광섭 확인으로 더함: 4 → 펜, 5 → 형광펜, 6 → 직선, 7 → 화살표, 8 → 원 (key_table_tools).
# 2026-10-27 광섭 확인으로 더함: 9 → 지우개 (key_table_eraser).
# ---------------------------------------------------------------------------

law key_table:
  {(C.Key.act(13, True{}), C.Key.act(27, True{}), C.Key.act(27, False{}),
    C.Key.act(122, True{}), C.Key.act(12619, True{}), C.Key.act(121, True{}), C.Key.act(12635, True{}),
    C.Key.act(49, True{}), C.Key.act(50, True{}), C.Key.act(51, True{}),
    C.Key.act(13, False{}), C.Key.act(97, True{}))
   == (C.ACopy{}, C.AEscDown{}, C.AEscUp{},
    C.AUndo{}, C.AUndo{}, C.ARedo{}, C.ARedo{},
    C.APick{C.TBox{}}, C.APick{C.TMosaic{}}, C.APick{C.TCrop{}},
    C.ANone{}, C.AOtherKey{})
   : C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act & C.Act}

law key_table_tools:
  {(C.Key.act(52, True{}), C.Key.act(53, True{}), C.Key.act(54, True{}), C.Key.act(55, True{}), C.Key.act(56, True{}))
   == (C.APick{C.TPen{}}, C.APick{C.THigh{}}, C.APick{C.TLine{}}, C.APick{C.TArrow{}}, C.APick{C.TEllipse{}})
   : C.Act & C.Act & C.Act & C.Act & C.Act}

law key_table_eraser:
  {C.Key.act(57, True{}) == C.APick{C.TErase{}} : C.Act}

# ---------------------------------------------------------------------------
# 규칙 9. 캡처 결과 판정 (계산으로 확인)
# 정상 종료 + 파일 있음 = 완료, 정상 종료 + 파일 없음 = 취소, 시간 초과·출력 초과는 권한 문제가
# 아니다, 비정상 종료 + 화면 관련 오류 = 권한 문제, 그 밖의 비정상 종료 = 실패.
# ---------------------------------------------------------------------------

law capture_verdicts:
  {(C.Cap.verdict(C.ROk{""}, True{}), C.Cap.verdict(C.ROk{""}, False{}),
    C.Cap.verdict(C.RFail{60, "Operation timed out"}, False{}),
    C.Cap.verdict(C.RFail{27, "File too large"}, False{}),
    C.Cap.verdict(C.RExit{1, "could not create image from display\n"}, False{}),
    C.Cap.verdict(C.RExit{1, "unknown error"}, False{}))
   == (C.VDone{}, C.VCancel{}, C.VTimeout{}, C.VTooLong{}, C.VPermission{}, C.VFailed{})
   : C.Verdict & C.Verdict & C.Verdict & C.Verdict & C.Verdict & C.Verdict}

# ---------------------------------------------------------------------------
# 규칙 13. 빠른 길 = 규칙의 길 (2026-10-27 광섭 확인으로 더함)
# 셸은 속도 때문에 필요한 몫만 복사한 상태(Ui.peek)로 명령을 계산한다. 그 명령은 어떤 상태·행동에서든
# 규칙들이 다루는 Ui.out 과 같다. 그래서 위 규칙들이 실제 프로그램이 내는 명령에도 그대로 성립한다.
# ---------------------------------------------------------------------------

law peek_out:
  for +ui: C.Ui
  for +a: C.Act
  {C.Ui.out(C.Ui.peek(ui, a), a) == C.Ui.out(ui, a) : C.Out}

# ---------------------------------------------------------------------------
# 규칙 14. 그린 것 만들기 (2026-10-27 광섭 확인으로 더함)
# 그린 것 하나는 받은 도구·색·경로를 그대로 담는다. 의도 표(Spec.next_hist)가 이 함수를 믿으므로,
# 이 함수가 도구나 색을 바꿔 치면 다른 규칙이 통과해도 틀린 그림이 된다.
# ---------------------------------------------------------------------------

law op_make:
  for +t: C.Tool
  for +c: C.Color
  for +p: List<&2, C.Pt>
  {C.Op.make(t, c, p) == C.Op{t, c, p} : C.Op}
