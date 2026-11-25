// Home's chats as a board (sfpages' board_node, sfbase's board.mbt) over the made-up board (sffixture's board_fixture):
// the rail's 对话 ↔ 看板 (小屏: Home's 列表 ↔ 看板), a draft written and started, a card's chat opened beside the board and its decision made (its card on to
// 进行中), a done chat archived, how it is grouped; 大屏 1440 × 900 and 小屏 390 × 844, every step held to the audit.

///|
/// The board's app over `mode` in a window `w` × `h` (`platform`: 2 a phone's), at rest (`corners_held`: the
/// Tester's).
fn board_at(mode : String, w : Double, h : Double, platform? : Int = 0, corners_held? : Bool = true) -> (@ui.Tester, Source) {
  new_run()
  let src = fixture(mode)
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform~, corners_held~)
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
/// The audit's faults made in the board's own files. (Not what is under the phone's bottom bar where its glass takes
/// presses, as it does once the bar has been told again: Home's list's rows are so too, the bar's. Nor the edge of the
/// chat beside the board where it reaches over that chat's page (sfpages' board_beside_edge, half over each side as a
/// side panel's edge is: the framework's edge a press takes where it is drawn, as experimental_wbtest leaves out the
/// pane's).)
fn board_faults(t : @ui.Tester) -> Array[String] {
  t
  .audit()
  .filter(fn(f) {
    (f.contains("board_node") || f.contains("sfdesk/board")) &&
    !f.contains("sfapp/bar.mbt") &&
    // (the edge of the chat beside the board, half over each side as a side panel's is: board_beside_faults')
    !f.contains("ui/src/controls/edge_node.mbt:37, in what was asked for at stillfail/src/sfpages/board_node.mbt:")
  })
}

///|
/// Where words `w` are drawn (their first), if they are.
fn board_words_at(t : @ui.Tester, w : String) -> (Double, Double, Double, Double)? {
  for x in t.words() {
    if x.0 == w {
      return Some((x.1, x.2, x.3, x.4))
    }
  }
  None
}

///|
/// A tap on words `w`, settled.
fn board_tap_words(t : @ui.Tester, w : String) -> Unit raise {
  guard board_words_at(t, w) is Some((x, y, ww, h)) else { fail("no \{w} drawn") }
  t.tap(x + ww / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
}

///|
/// 显示 in the wide board's bar (its words what the board is grouped by, where that is not by state) pressed: its panel
/// open, settled.
fn board_display_open(t : @ui.Tester) -> Unit raise {
  for w in ["显示", "按机器", "按成员"] {
    if t.query(Button, label=w) is Some(_) {
      t.click(Button, label=w)
      t.run_for(@ui.move_most_ms)
      return
    }
  }
  fail("no 显示 in the board's bar")
}

///|
/// The wide board grouped as `w` says (按状态, 按机器, 按成员) in 显示's panel, the panel closed again after.
fn board_group_by(t : @ui.Tester, w : String) -> Unit raise {
  board_display_open(t)
  t.click(Radio, label=w)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
}

///|
/// The column the chat titled `title` stands in now (the board's by state).
fn board_lane_now(src : Source, title : String) -> String {
  for i in @sfbase.board_items(src, "ws1") {
    if i.title == title {
      return @sfbase.board_lane_of(i)
    }
  }
  ""
}

///|
/// The rail's place `label` (its key at the window's left), where it is.
fn board_rail_rect(t : @ui.Tester, label : String) -> (Double, Double, Double, Double)? {
  for n in t.all(Button, label~) {
    if n.rect.0 < 60.0 {
      return Some(n.rect)
    }
  }
  None
}

///|
/// The rail's place `label` pressed, settled.
fn board_rail_press(t : @ui.Tester, label : String) -> Unit raise {
  guard board_rail_rect(t, label) is Some((x, y, w, h)) else { fail("no \{label} in the rail") }
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
}

///|
/// An edge taken at `x`, `y` and dragged across to `to` as a hand does, a move a frame, let go there, settled.
fn board_edge_drag(t : @ui.Tester, x : Double, y : Double, to : Double) -> Unit {
  t.press_at(x, y)
  for i in 1..=6 {
    t.move_to(x + (to - x) * i.to_double() / 6.0, y)
    t.run_for(@ui.frame_period_default)
  }
  t.release(to, y)
  t.run_for(@ui.move_most_ms)
}

///|
/// What the prefs' `sidebars` keep under `key`, as the core has it now ("" none).
fn board_sidebars_said(src : Source, key : String) -> String {
  @signals.untracked(fn() { text(field(src.topic("prefs", {}).get().value, "sidebars"), key) })
}

///|
test "大屏: the board in place of the list, its five columns; the rail's 对话 back to the list and 看板 to it again, neither moving, the chat open as it was left" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  for f in board_faults(t) { println(f) }
  for w in ["待派发", "等你处理", "进行中", "待收口", "监控中", "整理发布清单", "盯着 CI，绿了告诉我"] {
    assert_true(board_words_at(t, w) is Some(_), msg="\{w} on the board")
  }
  assert_eq(board_faults(t), [])
  // (看板 right under 对话 in the rail, lit; no 列表 in the board's bar)
  guard board_rail_rect(t, "对话") is Some(chats_at) else { fail("no 对话 in the rail") }
  guard board_rail_rect(t, "看板") is Some(board_at_) else { fail("no 看板 in the rail") }
  assert_true(board_at_.1 > chats_at.1 && board_at_.1 - chats_at.1 < 50.0, msg="看板 under 对话")
  assert_eq(@sfdesk.lit_place(), "board")
  assert_true(t.query(Button, label="列表") is None)
  // 对话: the sidebar's list again, the board gone; the rail's places where they were
  board_rail_press(t, "对话")
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(board_words_at(t, "待派发") is None)
  assert_eq(@sfdesk.lit_place(), "chats")
  assert_eq(board_rail_rect(t, "对话"), Some(chats_at))
  assert_eq(board_rail_rect(t, "看板"), Some(board_at_))
  // (kept as the core keeps it: the list again)
  assert_true(@sffixture.board_prefs["boardViews"].get("ws1") is None)
  assert_eq(board_faults(t), [])
  // a chat open beside the list, 看板 and 对话 again: the board, then that chat beside the list as it was
  let open = @signals.untracked(fn() { app.nav.top() })
  assert_true(open is Chat(_) || open is NewChat, msg="a chat open beside the list")
  board_rail_press(t, "看板")
  assert_true(@sfbase.board_on_of(src, "ws1"))
  assert_true(@sffixture.board_prefs["boardViews"].get("ws1") is Some(String("board")))
  assert_true(board_words_at(t, "待派发") is Some(_))
  assert_eq(board_rail_rect(t, "对话"), Some(chats_at))
  assert_eq(board_rail_rect(t, "看板"), Some(board_at_))
  assert_eq(board_faults(t), [])
  board_rail_press(t, "对话")
  assert_true(@signals.untracked(fn() { app.nav.top() }) == open, msg="the chat open as it was left")
  assert_true(board_words_at(t, "待派发") is None)
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a draft written in 待派发 and started goes on to 进行中 as its chat" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("把发布说明翻成英文")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "把发布说明翻成英文") is Some(_))
  assert_eq(board_faults(t), [])
  // (its 开始 pressed: its chat's card in 进行中, flying on from where its draft's was, one card all along)
  guard board_words_at(t, "把发布说明翻成英文") is Some((x, y, _, _)) else { fail("no draft") }
  guard t.all(Button, label="开始").iter().find_first(fn(n) { n.rect.0 > x && (n.rect.1 - y).abs() < 40.0 }) is Some(go) else {
    fail("no 开始 on its card")
  }
  t.tap(go.rect.0 + go.rect.2 / 2.0, go.rect.1 + go.rect.3 / 2.0)
  for _ in [0, 1, 2, 3, 4, 5] {
    t.run_for(@ui.frame_period_default)
    // (one card all along, from where its draft's was on to 进行中: never two)
    assert_true(board_words_n(t, "把发布说明翻成英文") <= 1, msg="its card twice")
  }
  t.run_for(@ui.move_most_ms)
  assert_eq(board_lane_now(src, "把发布说明翻成英文"), "run")
  assert_true(board_words_at(t, "正在读取仓库与分析改动点…") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a card pressed opens its chat beside the board; its decision made, the card goes on to 进行中" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  assert_eq(board_lane_now(src, "整理发布清单"), "wait")
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  assert_true(t.query(Button, label="全屏打开") is Some(_))
  assert_eq(board_faults(t), [])
  board_tap_words(t, "一起换")
  assert_eq(board_lane_now(src, "整理发布清单"), "run")
  assert_true(board_words_at(t, "正在按你的决定更新截图与清单…") is Some(_))
  assert_eq(board_faults(t), [])
  // × closes what is beside it
  t.click(Button, label="关闭")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is None)
}

///|
test "大屏 Mac: ⌘W closes the chat selected on the board before the window, even with its composer focused" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  assert_false(@ui.view_action("window.close_panel"))
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  t.click(TextField, label="发消息")
  // Other modifiers leave the selected chat alone.
  t.key(@ui.key_of_char('w'), mods=@ui.mod_cmd | @ui.mod_shift_key)
  assert_true(@sfbase.board_pick.get() is Some(_))
  t.key(@ui.key_of_char('w'), mods=@ui.mod_cmd)
  assert_true(@sfbase.board_pick.get() is None)
  assert_true(t.window_acts().is_empty())
  t.run_for(@ui.move_most_ms)
  assert_false(@ui.view_action("window.close_panel"))
  assert_true(t.query(Button, label="全屏打开") is None)
  assert_eq(board_faults(t), [])
}

///|
test "大屏: words in a chat opened beside the board can be picked, copied and quoted" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("board")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="给设置页加一个深色模式开关")
  t.run_for(@ui.move_most_ms)
  guard t.run_rects("做完了：开关") is [(x, y, w, h), ..] else { fail("the message's words are not drawn") }
  t.drag(x + 1.0, y + h / 2.0, x + w - 1.0, y + h / 2.0)
  t.frame()
  let selected = t.ctx().selected_text()
  assert_true(selected != "", msg="the message's words were not picked")
  assert_true("做完了：开关和三处颜色都改好了，已合进 main（a3f9c21）。".contains(selected), msg=selected)
  assert_eq(t.picking().map(fn(p) { p.text }), Some(selected))
  t.key(@ui.key_code_copy, mods=@ui.mod_cmd)
  assert_eq(t.clipboard(), selected)
  guard t.words().filter(fn(word) { word.0 == "引用" }) is [(_, qx, qy, qw, qh, _), ..] else {
    fail("no 引用 over what was picked")
  }
  t.tap(qx + qw / 2.0, qy + qh / 2.0)
  let quoted = named(calls, "composer.quote")
  assert_eq(quoted.length(), 1)
  assert_eq(text(field(Some(quoted[0].params), "quote"), "text"), selected.trim(chars=" \n\t").to_owned())
  assert_eq(board_faults(t), [])
}

///|
test "大屏 Mac: a board chat kept behind another page is not closed by ⌘W" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  // (a page other than a chat: a chat opened from the board puts the list back in its place, the board's chat closed,
  // sfapp's open_where)
  @sfbase.open_page(Files)
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() == Files)
  assert_false(@ui.view_action("window.close_panel"))
  assert_true(@sfbase.board_pick.get() is Some(_))
}

///|
test "大屏 Mac: a board chat without room to show leaves ⌘W to the window, and takes it again when shown" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  t.resize(1000.0, 900.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  assert_false(@ui.view_action("window.close_panel"))
  t.resize(1440.0, 900.0)
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_of_char('w'), mods=@ui.mod_cmd)
  assert_true(@sfbase.board_pick.get() is None)
}

///|
test "大屏 on another platform: ⌘W does not close a board chat" {
  let (t, _) = board_at("board", 1440.0, 900.0, platform=3)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_of_char('w'), mods=@ui.mod_cmd)
  assert_true(@sfbase.board_pick.get() is Some(_))
}

///|
test "大屏: a done chat's 归档 takes it off the board, 撤销 said; grouped by station and by person" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  let keys = t.all(Button, label="归档")
  assert_eq(keys.length(), 3)
  let (x, y, w, h) = keys[0].rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.all(Button, label="归档").length(), 2)
  assert_true(@sfbase.toast_words().has_prefix("已归档"))
  board_group_by(t, "按机器")
  assert_true(board_words_at(t, "Willow") is Some(_))
  assert_eq(board_faults(t), [])
  board_group_by(t, "按成员")
  assert_true(board_words_at(t, "林（我）") is Some(_))
  assert_eq(board_faults(t), [])
  ignore(src)
}

///|
test "小屏: the board under Home's bar, a column at a time by its chips, a card opening its chat" {
  let (t, _) = board_at("board", 390.0, 844.0, platform=2)
  assert_true(board_words_at(t, "整理发布清单") is Some(_))
  assert_eq(board_faults(t), [])
  t.click(Tab, label="进行中 3")
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "首页的列表改成按天分组") is Some(_))
  assert_true(board_words_at(t, "整理发布清单") is None)
  assert_eq(board_faults(t), [])
  t.click(Button, label="首页的列表改成按天分组")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Chat(_))
}

///|
test "大屏 1280: a card of the fourth column opened, its column brought whole beside the chat; a draft's 开始 starts it" {
  let (t, src) = board_at("board", 1280.0, 800.0)
  t.click(Button, label="给设置页加一个深色模式开关")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  // (its title whole, left of the chat beside the board)
  guard board_words_at(t, "给设置页加一个深色模式开关") is Some((x, _, w, _)) else { fail("its card not drawn") }
  assert_true(x >= 0.0 && x + w <= 1280.0 - 460.0, msg="its title at \{x}+\{w}")
  assert_eq(board_faults(t), [])
  t.click(Button, label="关闭")
  t.run_for(@ui.move_most_ms)
  // (新待办 brings 待派发 back into sight, its line open; Escape puts that away)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.board_adding.get())
  let starts = t.all(Button, label="开始")
  assert_eq(starts.length(), 2)
  let (sx, sy, sw, sh) = starts[0].rect
  t.tap(sx + sw / 2.0, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_lane_now(src, "给导出加上按月份筛选"), "run")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: opening and closing a 待收口 chat keeps the board's column widths, and moving focus leaves it where it is" {
  let (t, _) = board_at("board", 1280.0, 800.0)
  let title = "给设置页加一个深色模式开关"
  let (before_x, _, before_w, _) = t.get(Button, label=title).rect
  t.click(Button, label=title)
  let (opening_x, _, opening_w, _) = t.get(Button, label=title).rect
  assert_true((opening_x - before_x).abs() < 1.0 && (opening_w - before_w).abs() < 1.0, msg="board jumped as the chat opened")
  t.run_for(@ui.move_most_ms)
  let (open_x, _, open_w, _) = t.get(Button, label=title).rect
  assert_true((open_w - before_w).abs() < 1.0, msg="column width changed from \{before_w} to \{open_w}")
  assert_true(open_x >= 0.0 && open_x + open_w <= 1280.0 - 460.0, msg="selected card outside the board")
  assert_eq(edge_divider_faults(t), [], msg="a line between the chat and the board at rest")
  // (the board's room: short of the chat by its edge's reach over the board, handle_out (4), then the board's margin)
  let nearest_x = before_x.min(1280.0 - 460.0 - @sf.handle_out - 16.0 - before_w)
  assert_true((open_x - nearest_x).abs() < 1.0, msg="board scrolled farther than needed: \{open_x}, expected \{nearest_x}")
  t.click(TextField, label="发消息")
  t.run_for(@ui.move_most_ms)
  let (focused_x, _, focused_w, _) = t.get(Button, label=title).rect
  assert_true((focused_x - open_x).abs() < 1.0 && (focused_w - open_w).abs() < 1.0, msg="board moved as focus changed")
  t.click(Button, label="关闭")
  let (closing_x, _, closing_w, _) = t.get(Button, label=title).rect
  assert_true((closing_x - open_x).abs() < 1.0 && (closing_w - open_w).abs() < 1.0, msg="board jumped as the chat closed")
  t.run_for(@ui.move_most_ms)
  let (_, _, closed_w, _) = t.get(Button, label=title).rect
  assert_true((closed_w - before_w).abs() < 1.0, msg="column width changed on close")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a card already fitting beside its chat opens without moving the board" {
  let (t, _) = board_at("board", 1280.0, 800.0)
  let title = "整理发布清单"
  let (x, _, w, _) = t.get(Button, label=title).rect
  t.click(Button, label=title)
  t.run_for(@ui.move_most_ms)
  let (after_x, _, after_w, _) = t.get(Button, label=title).rect
  assert_true((after_x - x).abs() < 1.0 && (after_w - w).abs() < 1.0, msg="a visible column moved as its chat opened")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: closing a 待收口 chat while the board is moving reverses from its current place" {
  let (t, _) = board_at("board", 1280.0, 800.0)
  let title = "给设置页加一个深色模式开关"
  t.click(Button, label=title)
  t.run_for(@ui.move_most_ms / 4.0)
  let (before_x, _, before_w, _) = t.get(Button, label=title).rect
  t.click(Button, label=title)
  let (after_x, _, after_w, _) = t.get(Button, label=title).rect
  assert_true((after_x - before_x).abs() < 1.0 && (after_w - before_w).abs() < 1.0, msg="board jumped when the chat was closed on its way in")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is None)
  assert_eq(board_faults(t), [])
}

///|
test "中屏 760: the board in the tape's page panel, its bar that panel's bar's, all of it there, no 列表 in it" {
  let (t, _) = board_at("board", 760.0, 800.0)
  // (the tape holds, the board the page's panel's: brought over as the app starts on a workspace that shows it)
  assert_true(@sfdesk.wide.tape.get())
  assert_true(@sfdesk.wide.tape_at.get() is Page)
  assert_eq(@sfdesk.lit_place(), "board")
  for w in ["显示", "新待办", "待派发"] {
    assert_true(board_words_at(t, w) is Some(_), msg="\{w} on the board")
  }
  assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
  assert_true(t.query(Button, label="列表") is None)
  assert_eq(board_faults(t), [])
}

///|
/// The tape's sidebar brought over by a press on what shows of it at the window's left, settled.
fn board_side_over(t : @ui.Tester) -> Unit {
  t.tap(8.0, 400.0)
  t.run_for(@ui.move_most_ms)
}

///|
test "中屏 760: on the tape the rail's 看板 brings the board's panel over, 对话 the list beside the chat open as 看板 was pressed, the rail where it is" {
  // (the rail on the tape stands off its sidebar's corner, a fault known on every screen with the rail there and
  // nothing moving: corners_known_wbtest's corners_tape_rail; the board's own held by board_faults)
  let (t, src) = board_at("board", 760.0, 800.0, corners_held=false)
  assert_true(@sfdesk.wide.tape_at.get() is Page)
  for w in ["显示", "新待办"] {
    assert_true(board_words_at(t, w) is Some(_), msg="\{w} on the board")
  }
  assert_eq(board_faults(t), [])
  // the sidebar over: 看板 lit in the rail, right under 对话, beside the chats' list
  board_side_over(t)
  assert_true(@sfdesk.wide.tape_at.get() is Side)
  guard board_rail_rect(t, "对话") is Some(chats_at) else { fail("no 对话 in the rail") }
  guard board_rail_rect(t, "看板") is Some(board_at_) else { fail("no 看板 in the rail") }
  assert_true(board_at_.1 > chats_at.1 && board_at_.1 - chats_at.1 < 50.0, msg="看板 under 对话")
  // 对话: the list, the sidebar in use; the rail where it was
  board_rail_press(t, "对话")
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(@sfdesk.wide.tape_at.get() is Side)
  assert_eq(board_rail_rect(t, "对话"), Some(chats_at))
  assert_eq(board_rail_rect(t, "看板"), Some(board_at_))
  // a chat of the list open, 看板: the board's panel over; back to the sidebar, 对话: that chat beside the list
  // (as its row in the list opens it: open_where's)
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  open_page(Chat(chat))
  t.run_for(@ui.move_most_ms)
  let open = @signals.untracked(fn() { app.nav.top() })
  assert_true(open is Chat(_), msg="the chat open")
  if @sfdesk.wide.tape_at.get() != Side {
    board_side_over(t)
  }
  board_rail_press(t, "看板")
  assert_true(@sfbase.board_on_of(src, "ws1"))
  assert_true(@sfdesk.wide.tape_at.get() is Page)
  assert_true(board_words_at(t, "待派发") is Some(_))
  assert_eq(board_faults(t), [])
  board_side_over(t)
  assert_eq(board_rail_rect(t, "对话"), Some(chats_at))
  assert_eq(board_rail_rect(t, "看板"), Some(board_at_))
  board_rail_press(t, "对话")
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(@signals.untracked(fn() { app.nav.top() }) == open, msg="the chat open as it was left")
  assert_eq(board_faults(t), [])
}

///|
/// The drafts of ws1 as the made-up core keeps them (its `boardDrafts` topic): each one's words.
fn board_kept_drafts() -> Array[String] {
  match @sffixture.board_prefs["boardDrafts"].get("ws1") {
    Some(Array(a)) => a.map(fn(d) { text(Some(d), "title") })
    _ => []
  }
}

///|
test "⌘N on the board writes a 待派发 draft, including when grouped by station or a chat is open beside it" {
  for w in [760.0, 1440.0] {
    let (t, src) = board_at("board", w, 900.0)
    if w == 1440.0 {
      board_group_by(t, "按机器")
    }
    t.ctx().blur()
    t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    assert_true(app.nav.top() is Home, msg="\{w}: stays on the board")
    assert_true(@sfbase.board_on_of(src, "ws1"), msg="\{w}: board still chosen")
    assert_eq(@signals.untracked(fn() { @sfbase.board_group_of(src, "ws1") }), "state")
    t.type_text("用快捷键")
    // A second shortcut returns to the unfinished line without clearing it.
    t.ctx().blur()
    t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
    t.run_for(@ui.move_most_ms)
    t.type_text("新建待办")
    t.enter()
    t.run_for(@ui.move_most_ms)
    assert_eq(board_kept_drafts()[0], "用快捷键新建待办", msg="\{w}: saved in 待派发")
    assert_eq(board_faults(t), [])
  }
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  t.type_text("查看对话时的新待办")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts()[0], "查看对话时的新待办")
  assert_true(@sfbase.board_pick.get() is Some(_))
}

///|
test "the new action on 小屏 brings 待派发 into view; on the list it still opens a new chat" {
  let (t, src) = board_at("board", 390.0, 844.0, platform=2)
  @settings.ask_action("chat.new")
  t.run_for(@ui.move_most_ms)
  assert_true(app.nav.top() is Home)
  assert_true(@sfbase.board_on_of(src, "ws1"))
  assert_eq(@sfbase.board_lane.get(), "draft")
  t.type_text("小屏上的待办")
  // (the screen's keyboard's Enter a new line, as in a chat's composer: 添加 adds it)
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts()[0], "小屏上的待办")
  let (t, src) = board_at("board-list", 1440.0, 900.0)
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(app.nav.top() is NewChat)
}

///|
test "待派发: a pasted picture is kept with an image-only task and sent after a refused start" {
  new_run()
  let sent : Array[Json] = []
  let base = fixture("board")
  let src : Source = { ..base, call: fn(name, params, done) {
    if name == "chat.send" { sent.push(params) }
    (base.call)(name, params, done)
  } }
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  // (⌘ let go after pasting, as the host says it: held, 添加 is 派发)
  t.hold_mods(0)
  // (its picture over its words, what is under it moved down for it)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="移除 image.png") is Some(_))
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  let drafts = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })
  assert_eq(drafts[0].title, "")
  assert_eq(drafts[0].files.map(fn(f) { f.name }), ["image.png"])
  // Read the saved board again, then fail creation: the task and its file must still be there.
  @sfbase.board_reset()
  @sffixture.board_create_refused.val = "不能开始"
  let (x1, y1, w1, h1) = t.all(Button, label="开始")[0].rect
  t.tap(x1 + w1 / 2.0, y1 + h1 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })[0].files.length(), 1)
  let file_key = @sfbase.board_file_key("ws1", drafts[0].id)
  assert_eq(@sffixture.fix_composers.get(file_key).unwrap_or([]).length(), 1)
  assert_eq(sent.length(), 0)
  @sffixture.board_create_refused.val = ""
  let (x2, y2, w2, h2) = t.all(Button, label="开始")[0].rect
  t.tap(x2 + w2 / 2.0, y2 + h2 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0]), "text"), "")
  assert_eq(items(Some(sent[0]), "attachments").length() + items(Some(sent[0]), "uploads").length(), 1)
  assert_eq(board_faults(t), [])
}

///|
test "待派发: a task carrying a picture pasted here goes to another station chosen in its panel, its picture with it" {
  new_run()
  let sent : Array[Json] = []
  let base = fixture("board")
  let src : Source = { ..base, call: fn(name, params, done) {
    if name == "chat.send" { sent.push(params) }
    (base.call)(name, params, done)
  } }
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("换台机器跑")
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  t.hold_mods(0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  let before = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })[0]
  assert_eq((before.title, before.station, before.files.length()), ("换台机器跑", "ws1/st1", 1))
  // (its panel: where it runs a choice of the workspace's stations, not its own alone, lined up with its words)
  t.click(Button, label="换台机器跑")
  t.run_for(@ui.move_most_ms)
  draft_panel_lined_up(t, "Willow", "pasted")
  let (x, y, w, h) = t.get(Button, label="在哪台机器上运行: Willow").rect
  t.tap(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  t.click(MenuItemRadio, label="Maple")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="完成")
  t.run_for(@ui.move_most_ms)
  let after = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })[0]
  assert_eq((after.id, after.station, after.station_name, after.files.length()), (before.id, "ws1/st2", "Maple", 1))
  // (started, its chat made on the station chosen, its picture sent with its words)
  let (x2, y2, w2, h2) = t.all(Button, label="开始")[0].rect
  t.tap(x2 + w2 / 2.0, y2 + h2 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0]), "station"), "ws1/st2")
  assert_eq(items(Some(sent[0]), "attachments").length() + items(Some(sent[0]), "uploads").length(), 1)
  assert_eq(board_faults(t), [])
}

///|
/// In the open draft panel (its title 编辑待办, a picture among what it carries, it runs on `station`): its picture
/// starts where its title's words do, and so does the mark of where it runs (its name one mark and a chooser's gap
/// past them); under the picture, where it runs and on what are one row of choosers, the model's after the station's.
fn draft_panel_lined_up(t : @ui.Tester, station : String, at : String) -> Unit raise {
  guard board_words_at(t, "编辑待办") is Some((x0, y0, _, _)) else { fail("\{at}: no panel title") }
  // (the first under its title: the cards' under the panel are above it or further down)
  let tiles = t
    .drawn_instances()
    .filter(fn(i) { i[5] == 4.0 && (i[2] - 56.0).abs() < 0.5 && (i[3] - 56.0).abs() < 0.5 && i[1] > y0 })
  tiles.sort_by_key(fn(i) { i[1] })
  guard tiles is [tile, ..] else { fail("\{at}: no picture in the panel: \{Repr(t.drawn_images())}") }
  assert_true((tile[0] - x0).abs() < 0.5, msg="\{at}: picture at \{tile[0]}, title's words at \{x0}")
  let under = tile[1] + tile[3]
  let row = t.words().filter(fn(w) { w.2 > under })
  let names = row.filter(fn(w) { w.0 == station })
  names.sort_by_key(fn(w) { w.2 })
  guard names is [(_, nx, ny, nw, nh, _), ..] else { fail("\{at}: no \{station} under the picture: \{Repr(row)}") }
  // (its mark 14 and a chooser's gap 6 before its name: station_choice_node's `chooser`)
  assert_true((nx - 20.0 - x0).abs() < 0.5, msg="\{at}: \{station}'s mark at \{nx - 20.0}, title's words at \{x0}")
  let beside = row.filter(fn(w) { w.1 > nx + nw && (w.2 + w.4 / 2.0 - (ny + nh / 2.0)).abs() < 1.0 })
  assert_true(beside.length() > 0, msg="\{at}: nothing of the model's on \{station}'s line: \{Repr(row)}")
}

///|
test "待派发: a draft's panel lines its words, its picture and where it runs up at one start, where and on what one row, on 大屏 and 小屏" {
  for (w, h, platform) in [(1440.0, 900.0, 0), (390.0, 844.0, 2)] {
    let (t, src) = board_at("board", w, h, platform~)
    // (a picture it carries that this device kept, none of it in the composer here: kept to its own station, its
    // choice what it is, nothing to press)
    let still = "mem:test/board-lined-up"
    @ui.add_image(still, @pixels.png(2, 2, FixedArray::make(16, b'\x60')))
    @sfbase.writing_picture_put("board-lined", still)
    @sfbase.board_draft_add(src, "ws1", "带图的待办", "ws1/st1", "Willow", files=[{ id: "board-lined", name: "截图.png" }])
    |> ignore
    t.run_for(@ui.move_most_ms)
    if platform == 2 {
      t.click(Tab, label="待派发 3")
      t.run_for(@ui.move_most_ms)
    }
    t.click(Button, label="带图的待办")
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Button, label="在哪台机器上运行: Willow") is None)
    draft_panel_lined_up(t, "Willow", "\{w}")
    assert_eq(board_faults(t), [])
  }
}

///|
test "待派发: removing a pasted picture leaves the words and sends no file" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("只保留文字")
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  // (⌘ let go after pasting, as the host says it: held, 添加 is 派发)
  t.hold_mods(0)
  // (its picture over its words, what is under it moved down for it)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="移除 image.png")
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  let draft = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })[0]
  assert_eq((draft.title, draft.files.length()), ("只保留文字", 0))
  assert_eq(board_faults(t), [])
}

///|
/// The entry's words and 添加, where they are (the field by what it asks, 要做什么？).
fn board_entry_at(t : @ui.Tester) -> ((Double, Double, Double, Double), (Double, Double, Double, Double)) raise {
  guard t.query(TextField, label="要做什么？") is Some(f) else { fail("no field in 待派发") }
  guard t.query(Button, label="添加") is Some(a) else { fail("no 添加 in 待派发") }
  (f.rect, a.rect)
}

///|
test "待派发: a pasted picture's strip comes over the words, the last one removed takes it away; the words and 添加 as they were" {
  for screen in [(1440.0, 900.0, 0), (390.0, 844.0, 2)] {
    let (w, h, platform) = screen
    let (t, _) = board_at("board", w, h, platform~)
    if platform == 2 {
      t.click(Tab, label="待派发 2")
      t.run_for(@ui.move_most_ms)
      t.click(TextField, label="要做什么？")
    } else {
      t.click(Button, label="新待办")
    }
    t.run_for(@ui.move_most_ms)
    t.type_text("看一下这张图")
    t.run_for(@ui.move_most_ms)
    // (nothing over the words while it has no picture: no hint, no room kept)
    let (words0, add0) = board_entry_at(t)
    assert_true(board_words_at(t, "可粘贴图片") is None)
    t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
    t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
    // (⌘ let go after pasting, as the host says it: held, 添加 is 派发)
    t.hold_mods(0)
    t.run_for(@ui.move_most_ms)
    // (its picture over the words, the words and 添加 gone down together by its room, no further apart)
    guard t.query(Button, label="移除 image.png") is Some(x) else { fail("no picture over the words at \{w}") }
    let (words1, add1) = board_entry_at(t)
    assert_true(x.rect.1 + x.rect.3 <= words1.1)
    assert_true(words1.1 > words0.1)
    assert_eq((words1.0, words1.2, words1.3), (words0.0, words0.2, words0.3))
    assert_eq((add1.0, add1.1 - words1.1), (add0.0, add0.1 - words0.1))
    // (the last one removed: its strip gone, the words and 添加 where they were before it came)
    t.click(Button, label="移除 image.png")
    t.run_for(@ui.move_most_ms)
    assert_true(t.query(Button, label="移除 image.png") is None)
    assert_eq(board_entry_at(t), (words0, add0))
    assert_true(t.query(TextField, label="要做什么？") is Some(_))
    assert_eq(board_faults(t), [])
  }
}

///|
test "小屏: a picture pasted with words is kept in 待派发" {
  let (t, src) = board_at("board", 390.0, 844.0, platform=2)
  t.click(Tab, label="待派发 2")
  t.run_for(@ui.move_most_ms)
  t.click(TextField, label="要做什么？")
  t.type_text("检查图片")
  t.clipboard_gives_png(@pixels.png(2, 2, FixedArray::make(16, b'\xff')))
  t.key(@ui.key_of_char('v'), mods=@ui.mod_cmd)
  // (its picture over its words, what is under it moved down for it)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="添加")
  t.run_for(@ui.move_most_ms)
  let draft = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") })[0]
  assert_eq(draft.title, "检查图片")
  assert_eq(draft.files.map(fn(f) { f.name }), ["image.png"])
  assert_eq(board_faults(t), [])
}

///|
test "大屏: what the board is kept as, the core's prefs: its grouping and a draft written kept there, shown so as the app starts again" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  board_group_by(t, "按机器")
  assert_true(@sffixture.board_prefs["boardGroups"].get("ws1") is Some(String("station")))
  board_group_by(t, "按状态")
  assert_true(@sffixture.board_prefs["boardGroups"].get("ws1") is None)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("周五前把发布说明定稿")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts(), ["周五前把发布说明定稿", "给导出加上按月份筛选", "看一下 Android 冷启动为什么慢了 300ms"])
  board_group_by(t, "按成员")
  // (the app started again: nothing of what was chosen here, all of it read of the core's prefs)
  @sfbase.board_reset()
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_on_of(src, "ws1"))
  assert_eq(@signals.untracked(fn() { @sfbase.board_group_of(src, "ws1") }), "person")
  assert_eq(@signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") }).map(fn(d) { d.title }), board_kept_drafts())
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a draft started becomes its chat by the core's own way, newChat.create under its key then chat.send of its words, its card the chat's all along" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  let starts = t.all(Button, label="开始")
  let (sx, sy, sw, sh) = starts[0].rect
  t.tap(sx + sw / 2.0, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  // (its draft let go of as its chat is made: the core's pending chat keeps it)
  assert_eq(board_kept_drafts(), ["看一下 Android 冷启动为什么慢了 300ms"])
  // (made with what was picked for the draft: its own model control's)
  assert_eq(@sffixture.board_created_of.get("new:board-seed-1"), Some("board:new:board-seed-1"))
  let made = @sfbase.board_items(src, "ws1").filter(fn(i) { i.client_key == "new:board-seed-1" })
  assert_eq(made.map(fn(i) { (i.title, @sfbase.board_lane_of(i)) }), [("给导出加上按月份筛选", "run")])
  assert_true(board_words_at(t, "正在读取仓库与分析改动点…") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a draft its station will not start goes back to 待派发 whole, why said" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  @sffixture.board_create_refused.val = "Willow 上还没有可用的模型，先在机器上添加一个。"
  let starts = t.all(Button, label="开始")
  let (sx, sy, sw, sh) = starts[0].rect
  t.tap(sx + sw / 2.0, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.toast_words(), "Willow 上还没有可用的模型，先在机器上添加一个。")
  assert_eq(@signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1") }).length(), 2)
  assert_eq(board_kept_drafts().length(), 2)
  assert_true(board_words_at(t, "给导出加上按月份筛选") is Some(_))
  assert_eq(t.all(Button, label="开始").length(), 2)
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a draft no longer wanted deleted from its menu; a card dragged goes nowhere, nothing put up to take it" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  guard board_words_at(t, "给导出加上按月份筛选") is Some((x, y, _, _)) else { fail("no draft") }
  t.right_click(x + 10.0, y + 6.0)
  t.run_for(@ui.move_most_ms)
  board_tap_words(t, "删除")
  assert_eq(board_kept_drafts(), ["看一下 Android 冷启动为什么慢了 300ms"])
  assert_true(board_words_at(t, "给导出加上按月份筛选") is None)
  assert_eq(board_faults(t), [])
  // (dragged across the board and let go at its foot: nothing follows the pointer, nothing at the foot, nothing done)
  guard board_words_at(t, "看一下 Android 冷启动为什么慢了 300ms") is Some((x, y, _, _)) else { fail("no draft") }
  t.press_at(x + 10.0, y + 6.0)
  t.move_to(x + 200.0, y + 200.0)
  t.move_to(700.0, 860.0)
  t.run_for(@ui.move_most_ms)
  t.draw()
  assert_eq(board_words_n(t, "看一下 Android 冷启动为什么慢了 300ms"), 1)
  assert_true(board_words_at(t, "拖到这里删除") is None)
  assert_true(board_words_at(t, "拖到这里归档") is None)
  t.release(700.0, 860.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts(), ["看一下 Android 冷启动为什么慢了 300ms"])
  assert_eq(board_faults(t), [])
}

///|
test "the board kept as shown: 小屏, 中屏 and 大屏 start on it, all it reads declared as the workspace comes in view and read" {
  let faults : Array[String] = []
  for s in [("小屏", 390.0, 844.0, 2), ("中屏", 760.0, 820.0, 0), ("大屏", 1280.0, 820.0, 0)] {
    let (name, w, h, platform) = s
    new_run()
    let heard : Array[String] = []
    let base = fixture("board")
    let src = { ..round_trip_again(base, 0.0, heard=fn(x) { heard.push(x) }, late=fn(_, _) { 60.0 }), reads_ahead: fn() { true } }
    let t = switch_screen(src, w, h, platform, 60.0)
    if board_words_at(t, "待派发") is None {
      faults.push("\{name}: not on the board")
    }
    let unread = @sfbase.declared_unread()
    if unread.length() > 0 {
      faults.push("\{name}: declared and read by none at rest: " + unread.join(", "))
    }
    let again = asked_again(heard)
    if again.length() > 0 {
      faults.push("\{name}: let go of and asked again as it opened: " + again.join(", "))
    }
    // (its audit is board_at's, each screen's: this core's bar over Home's foot is the harness's, the list's as well)
  }
  assert_eq(faults, [])
}

///|
test "大屏: a draft's chat archived is gone from the board, its draft's card not back in its place" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  let starts = t.all(Button, label="开始")
  let (sx, sy, sw, sh) = starts[0].rect
  t.tap(sx + sw / 2.0, sy + sh / 2.0)
  t.run_for(@ui.move_most_ms)
  let made = @signals.untracked(fn() { @sfbase.board_items(src, "ws1") }).filter(fn(i) { i.client_key == "new:board-seed-1" })
  assert_eq(made.length(), 1)
  // (archived as a chat's row is: chat_row's archive_row)
  let i = made[0]
  let params : Map[String, Json] = {
    "station": Json::string(i.station),
    "session": Json::string(i.session),
    "archived": Json::boolean(true),
  }
  match i.thread {
    Some(th) => params["thread"] = Json::number(th)
    None => ()
  }
  (src.call)("chat.archive", Json::object(params), @sfbase.answer_unread)
  t.run_for(@ui.move_most_ms)
  let left = @signals.untracked(fn() { @sfbase.board_items(src, "ws1") })
  assert_eq(left.filter(fn(i) { i.client_key == "new:board-seed-1" || i.id == "new:board-seed-1" }).length(), 0)
  assert_true(board_words_at(t, "给导出加上按月份筛选") is None)
  assert_true(board_words_at(t, "正在派发…") is None)
  assert_eq(board_faults(t), [])
}

///|
/// The board's app on a phone over `mode` in a window `w` × `h`, the system's words at `scale`, at rest: the workspace
/// shown named `name` where one is said, Home's list catching up where `syncing` (fix_with_syncing).
fn board_bar_at(
  mode : String,
  w : Double,
  h : Double,
  scale? : Double = 1.0,
  name? : String = "",
  syncing? : Bool = false,
) -> (@ui.Tester, Source) {
  new_run()
  let base = fixture(mode)
  let src : Source = {
    ..base,
    topic_read: fn(topic, params) {
      let got = base.topic(topic, params).get().snapshot()
      match (topic, got.value) {
        ("workspaces", Some(v)) if name != "" =>
          { ..got, value: Some(@json.parse(v.stringify().replace(old="星火工作室", new=name)) catch { _ => v }) }
        ("chats", Some(v)) if syncing => { ..got, value: Some(@sffixture.fix_with_syncing(v)) }
        // (实验性功能's 对话列表看板视图 on, its key on Home's bar, in a mode not the board's: experimental_wbtest.mbt has it off)
        ("prefs", Some(Object(m))) => {
          let m = m.copy()
          m["experimental"] = { "board": true }
          // (and on, as the core says it: features.ts featuresOf)
          m["features"] = { "board": true }
          { ..got, value: Some(Json::object(m)) }
        }
        _ => got
      }
    },
  }
  open_fixture_over(mode, src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w~, h~, platform=2)
  if scale != 1.0 {
    t.set_font_scale(scale)
  }
  t.run_for(@ui.move_most_ms)
  (t, src)
}

///|
/// The audit's faults made in Home's bar (home_node.mbt's home_top_bar_node) or the board's own files.
fn board_bar_faults(t : @ui.Tester) -> Array[String] {
  board_faults(t) + t.audit().filter(fn(f) { f.contains("sfapp/home_node.mbt") })
}

///|
test "小屏: 筛选 and 看板 their own keys on Home's bar, at 390 and at 360 with words at 1.3 and a long workspace's name; on the board 筛选 and 列表, 列表 back" {
  for at in [(390.0, 844.0, 1.0, ""), (360.0, 740.0, 1.3, ""), (360.0, 740.0, 1.3, "星火工作室北京研发中心团队")] {
    let (w, h, scale, name) = at
    let (t, src) = board_bar_at("board-list", w, h, scale~, name~)
    assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
    assert_true(t.query(Button, label="看板") is Some(_))
    assert_eq(t.squeeze_faults(), [])
    assert_eq(t.words_over_now(), [])
    assert_eq(board_bar_faults(t), [])
    t.click(Button, label="看板")
    t.run_for(@ui.move_most_ms)
    assert_true(@sfbase.board_on_of(src, "ws1"))
    assert_true(board_words_at(t, "整理发布清单") is Some(_))
    assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
    assert_true(t.query(Button, label="列表") is Some(_))
    assert_true(t.query(Button, label="看板") is None)
    assert_eq(t.squeeze_faults(), [])
    assert_eq(t.words_over_now(), [])
    assert_eq(board_bar_faults(t), [])
    t.click(Button, label="列表")
    t.run_for(@ui.move_most_ms)
    assert_false(@sfbase.board_on_of(src, "ws1"))
    assert_true(t.query(Button, label="看板") is Some(_))
    assert_eq(board_bar_faults(t), [])
  }
}

///|
test "小屏 360: Home's bar crowded: the stations' releases leave first, then 看板 beside catching up; 筛选 and catching up stay, nothing over anything" {
  for scale in [1.0, 1.3] {
    // (the stations' releases alone beside them: they leave, 看板 stays; 320px exercises crowded dropping now that
    // buttons sit 2pt apart inside the liquid glass pill instead of 10pt bare)
    let (t, _) = board_bar_at("home-station-updates", 320.0, 740.0, scale~)
    assert_true(t.query(Button, label="看板") is Some(_))
    assert_true(t.query(Button, label="2 台 station 有新版本") is None)
    assert_eq(t.squeeze_faults(), [])
    assert_eq(t.words_over_now(), [])
    assert_eq(board_bar_faults(t), [])
    // (catching up as well: 看板 leaves too, catching up stays)
    let (t, _) = board_bar_at("home-station-updates", 320.0, 740.0, scale~, syncing=true)
    assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
    assert_true(t.query(Button, label="看板") is None)
    assert_true(t.query(Button, label="2 台 station 有新版本") is None)
    assert_true(t.semantics().iter().any(fn(n) { n.label == "正在同步 · 还剩 12 个对话" }))
    assert_eq(t.squeeze_faults(), [])
    assert_eq(t.words_over_now(), [])
    assert_eq(board_bar_faults(t), [])
  }
  // (at 390 the room for the stations' releases beside 看板)
  let (t, _) = board_bar_at("home-station-updates", 390.0, 844.0)
  assert_true(t.query(Button, label="2 台 station 有新版本") is Some(_))
  assert_true(t.query(Button, label="看板") is Some(_))
}

///|
/// The words of the menu open (its items, as a screen reader reads them: a sheet's on 小屏, a menu's beside what opened
/// it on 大屏).
fn board_menu_said(t : @ui.Tester) -> Array[String] {
  let out = []
  for n in t.semantics() {
    if n.role is (MenuItem | MenuItemCheckbox | MenuItemRadio) {
      out.push(n.label)
    } else if n.role is Dialog {
      for w in n.label.split(" ") {
        out.push(w.to_owned())
      }
    }
  }
  out
}

///|
test "小屏: the board's filter narrows it to 我参与的 and back to 全部会话, its menu no 监控中 and no 看板; 已隐藏 the list's" {
  let (t, src) = board_bar_at("board-list", 390.0, 844.0)
  t.click(Button, label="看板")
  t.run_for(@ui.move_most_ms)
  let all = @sfbase.board_items(src, "ws1").length()
  t.click(Button, label="筛选会话：全部")
  t.run_for(@ui.move_most_ms)
  let said = board_menu_said(t)
  assert_true(said.contains("全部会话"))
  assert_true(said.contains("我参与的"))
  assert_true(said.contains("已隐藏"))
  assert_true(said.contains("已归档"))
  assert_false(said.contains("监控中"))
  assert_false(said.contains("看板"))
  board_tap_words(t, "我参与的")
  assert_eq(filter_of(src, "ws1"), "mine")
  assert_true(@sfbase.board_on_of(src, "ws1"))
  let mine = @sfbase.board_items(src, "ws1").length()
  assert_true(mine > 0 && mine < all)
  assert_true(t.query(Button, label="筛选会话：我参与的") is Some(_))
  assert_eq(board_bar_faults(t), [])
  t.click(Button, label="筛选会话：我参与的")
  t.run_for(@ui.move_most_ms)
  board_tap_words(t, "全部会话")
  assert_eq(@sfbase.board_items(src, "ws1").length(), all)
  t.click(Button, label="筛选会话：全部")
  t.run_for(@ui.move_most_ms)
  board_tap_words(t, "已隐藏")
  assert_eq(filter_of(src, "ws1"), "hidden")
  assert_false(@sfbase.board_on_of(src, "ws1"))
}

///|
test "小屏: the list's 监控中 taken onto the board as its 监控中 column, the board narrowed to all of them" {
  let (t, src) = board_bar_at("board-list", 390.0, 844.0)
  t.click(Button, label="筛选会话：全部")
  t.run_for(@ui.move_most_ms)
  board_tap_words(t, "监控中")
  assert_eq(filter_of(src, "ws1"), "watching")
  t.click(Button, label="看板")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.board_lane.get(), "watch")
  assert_eq(filter_of(src, "ws1"), "all")
  assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
}

///|
test "大屏: the chat beside the board as wide as its edge is dragged, the columns laid out again, kept in the prefs; pressed twice its own width again" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  let edge = fn() { t.query(Separator, label="调整侧栏宽度").map(fn(n) { n.rect }).unwrap_or((0.0, 0.0, 0.0, 0.0)) }
  let mid = fn(r : (Double, Double, Double, Double)) { (r.0 + r.2 / 2.0, r.1 + r.3 / 2.0) }
  // (how wide the chat is: from where it starts, handle_out into its edge, to the window's end)
  let wide = fn() { (1440.0 - edge().0 - @sf.handle_out).round().to_int() }
  let (x0, y0) = mid(edge())
  // (no line between it and the board at rest: edge_divider_wbtest.mbt; its own width, 460 from the window's end)
  assert_eq(edge_divider_faults(t), [])
  assert_eq(wide(), 460)
  assert_eq(board_faults(t), [])
  // dragged 160 further in: 620 wide, kept so
  board_edge_drag(t, x0, y0, x0 - 160.0)
  t.run_for(@ui.move_most_ms)
  let (x1, _) = mid(edge())
  assert_eq(wide(), 620)
  assert_eq(board_sidebars_said(src, "\nboardChat"), "620")
  assert_true(board_words_at(t, "整理发布清单") is Some((cx, _, cw, _)) && cx + cw <= x1, msg="its card left of it")
  assert_eq(board_faults(t), [])
  // dragged far out: no narrower than 360
  board_edge_drag(t, x1, y0, 1400.0)
  t.run_for(@ui.move_most_ms)
  let (x2, _) = mid(edge())
  assert_eq(wide(), 360)
  assert_eq(board_sidebars_said(src, "\nboardChat"), "360")
  assert_eq(board_faults(t), [])
  // pressed twice: its own width again, nothing kept
  t.tap(x2, y0)
  t.tap(x2, y0)
  t.run_for(@ui.move_most_ms)
  assert_eq(wide(), 460)
  assert_eq(board_sidebars_said(src, "\nboardChat"), "")
  assert_true(@sfbase.board_pick.get() is Some(_), msg="still open")
  assert_eq(board_faults(t), [])
}

///|
/// A finger across the narrow board's track at `y` from `x0` by `dx`, in `steps` moves input_step_ms apart, let go
/// (`up`) or held there.
fn board_swipe(t : @ui.Tester, x0 : Double, y : Double, dx : Double, steps : Int, up? : Bool = true) -> Unit {
  t.touch(0, x0, y)
  for i in 1..=steps {
    t.advance(@ui.input_step_ms)
    t.touch(1, x0 + dx * i.to_double() / steps.to_double(), y)
  }
  if up {
    t.touch(2, x0 + dx, y)
    t.run_for(@ui.move_most_ms)
  }
}

///|
test "小屏: the board's columns swiped across, in the hand and let go on the next, back, or back where they were short of it; a finger down them scrolls, no card lifted" {
  let (t, _) = board_at("board", 390.0, 844.0, platform=2)
  assert_eq(@sfbase.board_lane.get(), "wait")
  let y = 500.0
  // (in the hand: the column chosen and the next moved with it, as far as the finger has gone)
  board_swipe(t, 300.0, y, -120.0, 6, up=false)
  t.draw()
  let run_x = board_words_at(t, "首页的列表改成按天分组").map(fn(r) { r.0 })
  assert_true(run_x is Some(x) && x > 200.0 && x < 390.0)
  t.touch(2, 180.0, y)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.board_lane.get(), "run")
  assert_true(board_words_at(t, "首页的列表改成按天分组").map(fn(r) { r.0 < 60.0 }).unwrap_or(false))
  assert_eq(board_faults(t), [])
  // (back by a swipe the other way)
  board_swipe(t, 100.0, y, 160.0, 6)
  assert_eq(@sfbase.board_lane.get(), "wait")
  // (short of the share and slow: back where it was)
  board_swipe(t, 300.0, y, -50.0, 12)
  assert_eq(@sfbase.board_lane.get(), "wait")
  // (short of the share as far as it went, let go still going: landing past it from its speed, the next; then back)
  board_swipe(t, 300.0, y, -60.0, 12)
  assert_eq(@sfbase.board_lane.get(), "run")
  board_swipe(t, 100.0, y, 160.0, 6)
  assert_eq(@sfbase.board_lane.get(), "wait")
  // (down the column: it scrolls, no card in the hand, no place to let one go)
  t.touch(0, 200.0, 700.0)
  for i in 1..=6 {
    t.advance(@ui.input_step_ms)
    t.touch(1, 200.0, 700.0 - 40.0 * i.to_double())
  }
  t.touch(2, 200.0, 460.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.board_lane.get(), "wait")
  assert_eq(board_faults(t), [])
}

///|
test "小屏: a draft's card held long offers 立即派发 and 删除; not dragged" {
  let (t, _) = board_at("board", 390.0, 844.0, platform=2)
  t.click(Tab, label="待派发 2")
  t.run_for(@ui.move_most_ms)
  guard t.semantics().iter().find_first(fn(n) { n.role is Button && n.rect.1 > 200.0 && n.rect.2 > 300.0 }) is Some(card) else {
    fail("no draft's card")
  }
  let (x, y) = (card.rect.0 + 40.0, card.rect.1 + 20.0)
  t.touch(0, x, y)
  t.advance(@ui.long_press_ms + @ui.input_step_ms)
  t.draw()
  t.touch(2, x, y)
  t.run_for(@ui.move_most_ms)
  let said = board_menu_said(t)
  assert_true(said.contains("立即派发"))
  assert_true(said.contains("删除"))
}

///|
test "大屏: the board's bar's filter narrows it to 我参与的, saying so on itself, and back" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  let all = @sfbase.board_items(src, "ws1").length()
  t.click(Button, label="筛选会话：全部")
  t.run_for(@ui.move_most_ms)
  assert_false(board_menu_said(t).contains("监控中"))
  board_tap_words(t, "我参与的")
  assert_eq(filter_of(src, "ws1"), "mine")
  assert_true(@sfbase.board_on_of(src, "ws1"))
  assert_true(@sfbase.board_items(src, "ws1").length() < all)
  // (narrowed: the key says so in words, and opens the same menu)
  assert_true(t.query(Button, label="筛选会话：全部") is None)
  // (the bar's, at its end: the list's own filter, folded into the sidebar, says so as well)
  guard t.all(Button, label="我参与的").filter(fn(b) { b.rect.0 > 720.0 }) is [b] else { fail("no 我参与的 in the board's bar") }
  let (bx, by, bw, bh) = b.rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_faults(t), [])
  board_tap_words(t, "全部会话")
  assert_eq(filter_of(src, "ws1"), "all")
  assert_true(t.query(Button, label="筛选会话：全部") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
test "大屏: 显示's panel: how it is grouped and its empty columns, the board behind it changing at once, audit clean" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  board_display_open(t)
  for w in ["分组方式", "按状态", "按机器", "按成员", "显示空列"] {
    assert_true(board_words_at(t, w) is Some(_), msg="\{w} in 显示's panel")
  }
  assert_true(t.query(Radio, label="看板") is None)
  assert_true(t.query(Radio, label="列表") is None)
  assert_eq(board_faults(t), [])
  // grouped by station from it: the board behind it so at once, the panel left open, 显示 saying 按机器
  t.click(Radio, label="按机器")
  t.run_for(@ui.move_most_ms)
  assert_eq(@signals.untracked(fn() { @sfbase.board_group_of(src, "ws1") }), "station")
  assert_true(board_words_at(t, "Willow") is Some(_))
  assert_true(board_words_at(t, "分组方式") is Some(_), msg="the panel left open")
  assert_eq(board_faults(t), [])
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "分组方式") is None)
  assert_true(t.query(Button, label="按机器") is Some(_))
  assert_true(t.query(Button, label="显示") is None)
  // back by state: 显示 again
  board_group_by(t, "按状态")
  assert_true(t.query(Button, label="显示") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
test "大屏: 显示空列 off leaves the empty columns out, kept in the core's prefs; 新待办 brings 待派发 in while a draft is written" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  // 待派发 emptied: both drafts started
  for _ in 0..<2 {
    let (sx, sy, sw, sh) = t.all(Button, label="开始")[0].rect
    t.tap(sx + sw / 2.0, sy + sh / 2.0)
    t.run_for(@ui.move_most_ms)
  }
  assert_eq(board_kept_drafts(), [])
  assert_true(board_words_at(t, "待派发") is Some(_), msg="empty, shown")
  board_display_open(t)
  t.click(Switch, label="显示空列")
  t.run_for(@ui.move_most_ms)
  assert_false(@signals.untracked(fn() { @sfbase.board_show_empty_of(src, "ws1") }))
  assert_true(@sffixture.board_prefs["boardShowEmpty"].get("ws1") is Some(False))
  assert_true(board_words_at(t, "待派发") is None, msg="empty, left out")
  assert_true(board_words_at(t, "进行中") is Some(_))
  assert_eq(board_faults(t), [])
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  // (显示 on a ground of its own: the board not as it starts)
  assert_true(t.query(Button, label="显示") is Some(_))
  // ⌘N: 待派发 in while its line is open, out again as it is closed
  t.key(@ui.key_of_char('n'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "待派发") is Some(_))
  assert_eq(board_faults(t), [])
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "待派发") is None)
  // (the app started again: read of the core's prefs)
  @sfbase.board_reset()
  t.run_for(@ui.move_most_ms)
  assert_false(@signals.untracked(fn() { @sfbase.board_show_empty_of(src, "ws1") }))
  // shown again
  board_display_open(t)
  t.click(Switch, label="显示空列")
  t.run_for(@ui.move_most_ms)
  assert_true(@sffixture.board_prefs["boardShowEmpty"].get("ws1") is None)
  assert_true(board_words_at(t, "待派发") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
test "大屏, a Mac's window (its buttons in the app's top row): the board's bar's start left empty, dragging the window, all it holds at its end" {
  let t = wide_tester([], mode="board", w=1440.0, h=900.0, window_inset=true)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_faults(t), [])
  let (lx, ly, _, lh) = t.get(Button, label="筛选会话：全部").rect
  let (gx, _, gw, _) = t.get(Button, label="新待办").rect
  let y = ly + lh / 2.0
  // (all of it at the bar's end: its filter past the middle of the window, 新待办 last, clear of its corner)
  assert_true(lx > 720.0, msg="筛选 at \{lx}")
  assert_true(gx > lx && gx + gw <= 1440.0 - 12.0, msg="新待办 ends at \{gx + gw}")
  // (the bar before them: nothing there but the bar, dragging the window)
  assert_true(t.drags_window_at(lx / 2.0, y), msg="the bar's empty part")
  assert_false(t.drags_window_at(lx + 4.0, y), msg="筛选")
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_eq(board_faults(t), [])
}

///|
test "大屏: each card where the core says its chat stands: one an agent leads under its leader, a colleague's card at work, a watch woken watching, 待收口's unread first; 归档已读 puts away those read alone" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  // (led by another chat's agent: under it, its leader's card saying so, not a card of its own)
  let led = @sfbase.chat_item({ "id": "c16", "title": "执行：状态与通知编码", "opener": { "session": "s-c11", "led": true } })
  assert_false(@sfbase.board_card_own(led))
  assert_true(@sfbase.board_card_own(@sfbase.chat_item({ "id": "c17", "opener": { "session": "s-c11" } })))
  assert_eq(board_lane_now(src, "首页的列表改成按天分组"), "run")
  assert_true(board_words_at(t, "1 个子会话进行中") is Some(_))
  // (a card 周 decides: at work for the viewer; a watch its watch woke: watching all the same)
  assert_eq(board_lane_now(src, "补一下部署文档"), "run")
  assert_eq(board_lane_now(src, "盯着 CI，绿了告诉我"), "watch")
  // (待收口: the result not read over those read)
  let top = fn(w : String) { board_words_at(t, w).map(fn(r) { r.1 }).unwrap_or(-1.0) }
  assert_true(top("给设置页加一个深色模式开关") >= 0.0 && top("给设置页加一个深色模式开关") < top("Slack 里问的报销流程"))
  assert_eq(board_faults(t), [])
  // (only what the viewer started: Ana's, read too, is not theirs to take off the workspace's lists)
  t.click(Button, label="归档已读 (1)")
  t.run_for(@ui.move_most_ms)
  // (one toast for the press, its 撤销 the whole press's)
  assert_true(board_words_at(t, "已归档 1 个已读的对话") is Some(_))
  assert_true(board_words_at(t, "给设置页加一个深色模式开关") is Some(_))
  assert_true(board_words_at(t, "Slack 里问的报销流程") is Some(_))
  assert_true(board_words_at(t, "把旧的截图都换成新的") is None)
  assert_true(t.query(Button, label="归档已读 (1)") is None)
  assert_eq(board_faults(t), [])
}

///|
/// The narrow board over board-many (a busy workspace's: two figures a column) on a phone's window, at rest.
fn board_many_at() -> (@ui.Tester, Source) {
  board_at("board-many", 390.0, 844.0, platform=2)
}

///|
/// The rect a screen reader is told card or chip `label` (of `role`) has, if it is there.
fn board_rect_of(t : @ui.Tester, role : @ui.Role, label : String) -> (Double, Double, Double, Double)? {
  for n in t.semantics() {
    if n.role == role && n.label == label {
      return Some(n.rect)
    }
  }
  None
}

///|
test "小屏: the board reaches the window's foot, its cards passing under the bottom bar; scrolled to its end, its last card at rest over that bar" {
  let (t, _) = board_many_at()
  let h = 844.0
  let foot = nav_foot() + bar_room_at(390.0)
  assert_true(foot > 40.0, msg="the bottom bar covers \{foot}")
  // (a card's words drawn under the bottom bar's top, cut by nothing short of the window's foot: the column not cut
  // in the air over that bar)
  let under = t.glyph_clips().filter(fn(g) { g.0.1 > h - foot && g.0.1 < h - 8.0 })
  assert_true(under.length() > 0, msg="no words under the bottom bar")
  assert_true(under.iter().all(fn(g) { g.1.3 >= h - 0.5 }), msg="words under the bottom bar cut short of the window's foot")
  // (scrolled down to its end: its last card whole, at rest over the bottom bar, as close over it as Home's list's
  // last row)
  for _ in 0..<6 {
    t.wheel(200.0, 500.0, 900.0)
    t.run_for(@ui.move_most_ms)
  }
  guard board_rect_of(t, Button, "安卓冷启动又慢了") is Some((_, y, _, ch)) else { fail("no last card") }
  assert_true(y + ch <= h - foot + 0.5, msg="the last card's foot \{y + ch} under the bottom bar's top \{h - foot}")
  assert_true(y + ch >= h - foot - 24.0, msg="the last card's foot \{y + ch} far over the bottom bar's top \{h - foot}")
  // (a card passing under the bar's glass at its top is under it, not drawn over its chips: a press there is the bar's,
  // as the hit test has it)
  assert_eq(board_faults(t), [])
}

///|
test "小屏: 待收口 says how many it has read and puts them away from its top, the result not read kept" {
  let (t, _) = board_at("board", 390.0, 844.0, platform=2)
  t.click(Tab, label="待收口 3")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.board_lane.get(), "done")
  assert_true(board_words_at(t, "1 项可归档") is Some(_))
  assert_eq(board_faults(t), [])
  t.click(Button, label="归档已读")
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "1 项可归档") is None)
  assert_true(board_words_at(t, "Slack 里问的报销流程") is Some(_))
  assert_true(board_words_at(t, "给设置页加一个深色模式开关") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
/// The wide board's columns' lists that reach its foot (the clips of words drawn within `h`'s last 200 points, taller
/// than 300).
fn board_wide_lists(t : @ui.Tester, h : Double) -> Array[(Double, Double, Double, Double)] {
  let out : Array[(Double, Double, Double, Double)] = []
  for g in t.glyph_clips() {
    let c = g.1
    if g.0.1 > h - 200.0 && c.3 - c.1 > 300.0 && !out.contains(c) {
      out.push(c)
    }
  }
  out
}

///|
/// The wide board over board-many in a window `w` × `h`: each column's list reaching the foot of the panel or the window
/// (within `h` by less than the page's margin), not cut in the air over it; each that scrolls, scrolled to its end, its
/// last card at rest the page's margin over that foot, as far as from the sides.
fn board_wide_foot_holds(w : Double, h : Double) -> Unit raise {
  let (t, _) = board_at("board-many", w, h)
  let lists = board_wide_lists(t, h)
  assert_true(lists.length() > 0, msg="no column's cards near the foot")
  let mut scrolled = 0
  for c in lists {
    let (x0, _, x1, y1) = c
    assert_true(y1 > h - 16.0, msg="a column cut at \{y1}, the page's margin or more over the foot \{h}")
    for _ in 0..<12 {
      t.wheel((x0 + x1) / 2.0, y1 - 100.0, 900.0)
      t.run_for(@ui.move_most_ms)
    }
    let mut last = 0.0
    for n in t.semantics() {
      if n.role == Button && n.rect.0 >= x0 - 1.0 && n.rect.0 + n.rect.2 <= x1 + 1.0 && n.rect.2 > 150.0 {
        if n.rect.1 + n.rect.3 > last {
          last = n.rect.1 + n.rect.3
        }
      }
    }
    if last > y1 - 40.0 {
      scrolled += 1
      assert_true((last - (y1 - 16.0)).abs() < 0.5, msg="the last card's foot \{last}, not 16 over the foot \{y1}")
    }
  }
  assert_true(scrolled > 0, msg="no column scrolled to its end")
  assert_eq(board_faults(t), [])
}

///|
/// How many times words `w` are drawn.
fn board_words_n(t : @ui.Tester, w : String) -> Int {
  t.words().filter(fn(x) { x.0 == w }).length()
}

///|
test "小屏: 待处理 lists what waits for the viewer read or not, and 全部已读 takes only what was unread" {
  let (t, _) = board_at("board", 390.0, 844.0, platform=2)
  t.click(Button, label="待处理")
  t.run_for(@ui.move_most_ms)
  // (夜里的构建又失败了 asks them and was looked at: listed as 整理发布清单, not read yet, is; each beside its card)
  assert_eq(board_words_n(t, "夜里的构建又失败了"), 2)
  assert_eq(board_words_n(t, "整理发布清单"), 2)
  let done_before = board_words_n(t, "给设置页加一个深色模式开关")
  board_tap_words(t, "全部已读")
  assert_eq(board_words_n(t, "给设置页加一个深色模式开关"), done_before - 1)
  assert_eq(board_words_n(t, "夜里的构建又失败了"), 2)
  assert_eq(board_words_n(t, "整理发布清单"), 2)
}

///|
test "中屏 760 and 大屏 1440: the board's columns reach the foot, not cut in the air over it; scrolled to its end, a column's last card 16 over that foot" {
  board_wide_foot_holds(760.0, 800.0)
  board_wide_foot_holds(1440.0, 900.0)
}

///|
test "小屏: the board's chips on Home's bar, two figures each; swiped to 监控中, its chip brought whole into sight within the page's margins" {
  let (t, _) = board_many_at()
  for w in ["待派发 2", "等你处理 10", "进行中 28", "待收口 25", "监控中 6"] {
    assert_true(board_rect_of(t, Tab, w) is Some(_), msg="no chip \{w}")
  }
  // (on the bar's glass, its top bar's keys over it: the chips under them, the cards under the chips)
  guard board_rect_of(t, Tab, "等你处理 10") is Some((_, cy, _, chh)) else { fail("no chip") }
  guard board_rect_of(t, Button, "整理发布清单") is Some((_, ty, _, _)) else { fail("no card") }
  assert_true(ty > cy + chh, msg="the first card under the chips")
  // (swiped across, a column at a time, to the last)
  for _ in 0..<3 {
    board_swipe(t, 330.0, 500.0, -200.0, 6)
  }
  assert_eq(@sfbase.board_lane.get(), "watch")
  guard board_rect_of(t, Tab, "监控中 6") is Some((x, _, w, _)) else { fail("no 监控中") }
  assert_true(x >= 16.0 - 0.5 && x + w <= 390.0 - 16.0 + 0.5, msg="监控中 6 at \{x}, \{w} wide: not whole within the margins")
  // (and back to the first by its chip: in sight again)
  t.click(Tab, label="待派发 2")
  t.run_for(@ui.move_most_ms)
  guard board_rect_of(t, Tab, "待派发 2") is Some((x, _, w, _)) else { fail("no 待派发") }
  assert_true(x >= 16.0 - 0.5 && x + w <= 390.0 - 16.0 + 0.5, msg="待派发 2 at \{x}: not whole within the margins")
  assert_eq(board_faults(t), [])
}

///|
test "小屏: a card on a station with no mark of its own says its name where its title begins, nothing before it" {
  let (t, _) = board_many_at()
  guard board_words_at(t, "Farview 替换 agent 浏览器") is Some((tx, ty, _, _)) else { fail("no title") }
  let names = t.words().filter(fn(w) { w.0 == "tokyo-mac-studio-0" && w.2 > ty })
  guard names.get(0) is Some(n) else { fail("no station's name") }
  assert_eq(n.1, tx)
  assert_eq(t.line_start_faults().filter(fn(f) { f.contains("board_node") }), [])
  assert_eq(t.first_line_faults().filter(fn(f) { f.contains("board_node") }), [])
}

///|
test "小屏: a card's faces asked for their pictures, as a row's; an agent's subagents one mark, no key twice" {
  new_run()
  let asked : Array[String] = []
  let base = fixture("board-many")
  let src : Source = {
    ..base,
    picture: fn(url, stint) {
      asked.push(url)
      (base.picture)(url, stint)
    },
  }
  open_fixture_over("board-many", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  assert_true(asked.contains("https://example.com/faces/board-z.png"), msg="asked: \{Repr(asked)}")
  // (its picture drawn in the face's place: the only pictures the narrow board shows)
  assert_true(t.drawn_images().length() > 0, msg="the face's picture not drawn")
  guard board_rect_of(t, Button, "station W10-2：清退 src/store 剩余 16 处 TS Step 代码并加固门禁") is Some((x, y, w, h)) else {
    fail("no card")
  }
  let marks = t
    .semantics()
    .filter(fn(n) {
      n.role is Image && n.label.has_prefix("anthropic") && n.rect.0 >= x && n.rect.1 >= y && n.rect.0 < x + w && n.rect.1 < y + h
    })
  assert_eq(marks.length(), 1)
  assert_eq(board_faults(t), [])
}

///|
test "小屏 and 大屏: a chat's card held long, or right clicked, offers the chat's menu, each of its items the board's to do" {
  let (t, _) = board_many_at()
  guard board_rect_of(t, Button, "夜里的构建又失败了") is Some((x, y, _, _)) else { fail("no card") }
  t.touch(0, x + 40.0, y + 20.0)
  t.advance(@ui.long_press_ms + @ui.input_step_ms)
  t.draw()
  t.touch(2, x + 40.0, y + 20.0)
  t.run_for(@ui.move_most_ms)
  let said = board_menu_said(t)
  for w in ["重命名", "归档"] {
    assert_true(said.contains(w), msg="\{w} not in \{Repr(said)}")
  }
  assert_true(app.nav.top() is Home)
  // (大屏: right clicked at the pointer)
  let (t, _) = board_at("board", 1440.0, 900.0)
  guard board_words_at(t, "夜里的构建又失败了") is Some((x, y, _, _)) else { fail("no card") }
  t.right_click(x + 10.0, y + 6.0)
  t.run_for(@ui.move_most_ms)
  let said = board_menu_said(t)
  for w in ["重命名", "归档"] {
    assert_true(said.contains(w), msg="\{w} not in \{Repr(said)}")
  }
  // (重命名 asked over the page, whatever the input: the card shows no title of a row's to be its field)
  board_tap_words(t, "重命名")
  assert_true(t.semantics().iter().any(fn(n) { n.role is Dialog }), msg="重命名 asked nowhere")
}

///|
test "大屏: a right click across a waiting chat's card opens its menu when its whole row comes back" {
  new_run()
  let base = fixture("board")
  let src = round_trip_again(base, 0.0, late=fn(name, _) { if name == "chatRow" { 150.0 } else { 0.0 } })
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  for title in ["整理发布清单", "夜里的构建又失败了"] {
    guard board_rect_of(t, Button, title) is Some((x, y, w, h)) else { fail("no card: \{title}") }
    for at in [(0.15, 0.2), (0.5, 0.2), (0.85, 0.2), (0.15, 0.5), (0.5, 0.5), (0.85, 0.5), (0.15, 0.8), (0.5, 0.8), (0.85, 0.8)] {
      t.right_click(x + w * at.0, y + h * at.1)
      t.run_for(150.0 + @ui.move_most_ms)
      assert_true(board_menu_said(t).contains("重命名"), msg="\{title} at \{Repr(at)}: \{Repr(board_menu_said(t))}")
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
    }
  }
  assert_eq(board_faults(t), [])
}

///|
test "大屏: right clicking a busy board's waiting cards, including after scrolling, opens their menus" {
  new_run()
  let base = fixture("board-many")
  let src = round_trip_again(base, 0.0, late=fn(name, _) { if name == "chatRow" { 150.0 } else { 0.0 } })
  open_fixture_over("board-many", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  for title in ["整理发布清单", "夜里的构建又失败了", "迁移数据库的演练", "station W10-2：清退 src/store 剩余 16 处 TS Step 代码并加固门禁"] {
    guard board_rect_of(t, Button, title) is Some((x, y, w, h)) else { fail("no card: \{title}") }
    t.right_click(x + w / 2.0, y + h / 2.0)
    t.run_for(150.0 + @ui.move_most_ms)
    assert_true(board_menu_said(t).contains("重命名"), msg="\{title}: \{Repr(board_menu_said(t))}")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
  }
  guard board_rect_of(t, Button, "整理发布清单") is Some((x, y, w, _)) else { fail("no waiting column") }
  t.wheel(x + w / 2.0, y + 20.0, 900.0)
  t.run_for(@ui.move_most_ms)
  guard board_rect_of(t, Button, "安卓冷启动又慢了") is Some((x, y, w, h)) else { fail("no last card") }
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(150.0 + @ui.move_most_ms)
  assert_true(board_menu_said(t).contains("重命名"), msg="scrolled: \{Repr(board_menu_said(t))}")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: waiting cards still offer their menu while a chat is open beside the board and the pointer has rested on them" {
  new_run()
  let base = fixture("board")
  let src = round_trip_again(base, 0.0, late=fn(name, _) { if name == "chatRow" { 150.0 } else { 0.0 } })
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  for title in ["整理发布清单", "夜里的构建又失败了"] {
    guard board_rect_of(t, Button, title) is Some((x, y, w, h)) else { fail("no card: \{title}") }
    for at in [(0.2, 0.5), (0.8, 0.8)] {
      let px = x + w * at.0
      let py = y + h * at.1
      t.move_to(px, py)
      t.run_for(@sf.tip_delay_ms + @ui.move_most_ms)
      t.right_click(px, py)
      t.run_for(150.0 + @ui.move_most_ms)
      assert_true(board_menu_said(t).contains("重命名"), msg="\{title} at \{Repr(at)}: \{Repr(board_menu_said(t))}")
      t.key(@ui.key_escape)
      t.run_for(@ui.move_most_ms)
    }
  }
  assert_eq(board_faults(t), [])
}

///|
test "大屏: right clicking a second waiting card while the first menu is open opens the second card's menu" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  guard board_rect_of(t, Button, "整理发布清单") is Some((x, y, w, h)) else { fail("no first card") }
  guard board_rect_of(t, Button, "迁移数据库的演练") is Some((x2, y2, w2, h2)) else { fail("no second card") }
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(board_menu_said(t).contains("重命名"))
  let first = @sf.last_presented()
  t.right_click(x2 + w2 * 0.2, y2 + h2 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.last_presented() > first, msg="the second card's menu was not opened")
  board_tap_words(t, "重命名")
  assert_eq(t.get(TextField).value, "迁移数据库的演练")
}

///|
test "大屏: menus keep switching across repeated right clicks on waiting cards" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  guard board_rect_of(t, Button, "整理发布清单") is Some((x, y, w, h)) else { fail("no first card") }
  guard board_rect_of(t, Button, "迁移数据库的演练") is Some((x2, y2, w2, h2)) else { fail("no second card") }
  for i, point in [
    (x + w * 0.8, y + h / 2.0),
    (x2 + w2 * 0.2, y2 + h2 / 2.0),
    (x + w * 0.2, y + h / 2.0),
    (x2 + w2 * 0.1, y2 + h2 / 2.0),
    (x + w * 0.1, y + h / 2.0),
  ] {
    let previous = @sf.last_presented()
    t.right_click(point.0, point.1)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.last_presented() > previous, msg="right click \{i + 1} did not open a menu")
    assert_true(board_menu_said(t).contains("重命名"), msg="right click \{i + 1} has no chat menu")
  }
  board_tap_words(t, "重命名")
  assert_eq(t.get(TextField).value, "整理发布清单")
}

///|
test "大屏: right clicking one waiting card repeatedly outside its menu opens it again" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  guard board_rect_of(t, Button, "整理发布清单") is Some((x, y, w, h)) else { fail("no card") }
  for i, fraction in [0.8, 0.4, 0.1] {
    let previous = @sf.last_presented()
    t.right_click(x + w * fraction, y + h / 2.0)
    t.run_for(@ui.move_most_ms)
    assert_true(@sf.last_presented() > previous, msg="right click \{i + 1} did not open a menu")
    assert_true(board_menu_said(t).contains("重命名"), msg="right click \{i + 1} has no chat menu")
  }
  board_tap_words(t, "重命名")
  assert_eq(t.get(TextField).value, "整理发布清单")
}

///|
/// A card lifted for its menu as it is drawn (its raised ground, wider than a card at rest of 小屏's, 358, by a
/// hundredth and more, narrower than the window) and where among what is drawn; None where none is.
fn board_lifted_card(t : @ui.Tester) -> ((Double, Double, Double, Double), Int)? {
  let raised = @sf.theme().p.raised
  for i, r in t.drawn_rects() {
    if r.4 == raised && r.2 > 358.0 * 1.02 && r.2 < 385.0 {
      return Some(((r.0, r.1, r.2, r.3), i))
    }
  }
  None
}

///|
/// Where among what is drawn the menu's scrim is (a ground over the whole window, seen through), and the top of the
/// sheet a menu is in (what is drawn after `after` across the window's width, under its top).
fn board_scrim_sheet(t : @ui.Tester, w : Double, h : Double, after : Int) -> (Int?, Double) {
  let mut scrim : Int? = None
  let mut top = h
  for i, r in t.drawn_rects() {
    if scrim is None && r.0 <= 0.5 && r.1 <= 0.5 && r.2 >= w && r.3 >= h && (r.4 & 0xFFL) < 0xFFL {
      scrim = Some(i)
    }
    if i > after && r.0 <= 0.5 && r.2 >= w - 0.5 && r.1 > 100.0 && r.1 < top {
      top = r.1
    }
  }
  (scrim, top)
}

///|
/// A long press of a finger at (x, y), let go once its menu is up, settled.
fn board_long_press(t : @ui.Tester, x : Double, y : Double) -> Unit {
  t.touch(0, x, y)
  t.advance(@ui.long_press_ms + @ui.input_step_ms)
  t.draw()
  t.touch(2, x, y)
  t.run_for(@ui.move_most_ms)
}

///|
/// Card `card` held by a finger for its menu and lifted: drawn larger, over the scrim, clear of the sheet over it.
fn board_lifted_over(t : @ui.Tester, what : String) -> (Double, Double, Double, Double) raise {
  guard board_lifted_card(t) is Some((r, at)) else { fail("\{what}: no card lifted") }
  let (scrim, top) = board_scrim_sheet(t, 390.0, 844.0, at)
  assert_true(scrim is Some(s) && s < at, msg="\{what}: scrim \{Repr(scrim)}, card \{at}")
  assert_true(r.1 + r.3 <= top - 12.0 + 0.5, msg="\{what}: its foot \{r.1 + r.3} under the sheet's top \{top} less 12")
  r
}

///|
test "小屏: a card held by a finger lifts over its menu's scrim, clear of its sheet, a step further in too, back down as it closes; a draft's too; a right click lifts none, a mouse's button held opens nothing" {
  let (t, _) = board_many_at()
  let name = "Farview 替换 agent 浏览器"
  guard board_rect_of(t, Button, name) is Some(laid) else { fail("no card") }
  assert_true(board_lifted_card(t) is None)
  board_long_press(t, laid.0 + 40.0, laid.1 + 20.0)
  let up = board_lifted_over(t, "held")
  assert_true(up.2 > 358.0 * 1.02, msg="drawn \{up.2} wide")
  // (lower on the screen than the sheet lets it be: brought up over it)
  assert_true(up.1 + up.3 < laid.1 + laid.3, msg="its foot \{up.1 + up.3} from \{laid.1 + laid.3}")
  assert_eq(board_faults(t), [])
  // (a step further in, 分享: lifted still, over the sheet that takes the menu's place)
  board_tap_words(t, "分享")
  board_lifted_over(t, "分享") |> ignore
  @sf.close_presented_of(@sf.last_presented())
  // (back down on its spring from the moment the menu went)
  t.run_for(@ui.move_most_ms + @motion.tactile_bounce.duration(1.0, 0.0, 0.0))
  assert_true(!@sf.presented_drawn())
  assert_true(board_lifted_card(t) is None, msg="still lifted")
  assert_eq(board_rect_of(t, Button, name), Some(laid))
  assert_eq(board_faults(t), [])
  // (a draft's card in 待派发, held so: lifted the same)
  t.click(Tab, label="待派发 2")
  t.run_for(@ui.move_most_ms)
  guard board_rect_of(t, Button, "给导出加上按月份筛选") is Some(d) else { fail("no draft's card") }
  board_long_press(t, d.0 + 40.0, d.1 + 20.0)
  assert_true(board_menu_said(t).contains("立即派发"))
  board_lifted_over(t, "a draft's") |> ignore
  assert_eq(board_faults(t), [])
  // (大屏: right clicked, its menu at the pointer, the card where it lies, as large)
  let (t, _) = board_at("board-many", 1440.0, 900.0)
  guard board_rect_of(t, Button, "夜里的构建又失败了") is Some(r) else { fail("no card") }
  t.right_click(r.0 + 40.0, r.1 + 20.0)
  t.run_for(@ui.move_most_ms)
  assert_true(board_menu_said(t).contains("重命名"))
  assert_eq(board_rect_of(t, Button, "夜里的构建又失败了"), Some(r))
  let raised = @sf.theme().p.raised
  assert_true(
    !t.drawn_rects().iter().any(fn(d) { d.4 == raised && (d.2 - r.2).abs() < 40.0 && d.2 > r.2 + 1.0 }),
    msg="a card drawn lifted",
  )
  assert_eq(board_faults(t), [])
  // (a mouse's button held on a card as long as a finger's hold: a press as long as any, waiting to be dragged; no
  // menu, nothing lifted)
  let (t, _) = board_at("board-many", 1440.0, 900.0)
  t.host_says_finger(Some(false))
  guard board_rect_of(t, Button, "夜里的构建又失败了") is Some(r) else { fail("no card") }
  t.touch(0, r.0 + 40.0, r.1 + 20.0)
  t.advance(@ui.long_press_ms + @ui.input_step_ms)
  t.draw()
  assert_true(!@sf.presented_drawn(), msg="a menu up: \{Repr(board_menu_said(t))}")
  assert_eq(board_rect_of(t, Button, "夜里的构建又失败了"), Some(r))
  t.touch(3, r.0 + 40.0, r.1 + 20.0)
  t.run_for(@ui.move_most_ms)
  assert_true(!@sf.presented_drawn())
  assert_eq(board_faults(t), [])
}

///|
/// The icon drawn inside the button named `label` for a screen reader.
fn board_button_icon(t : @ui.Tester, label : String) -> String {
  guard t.query(Button, label~) is Some(button) && @ui.view_tree() is Some(tree) else { return "" }
  let (x, y, w, h) = button.rect
  for d in tree.drawn() {
    let name = tree.drawn_name(d.id)
    if name.has_prefix("/icon/") && d.x >= x && d.y >= y && d.x + d.w <= x + w && d.y + d.h <= y + h {
      return name
    }
  }
  ""
}

///|
test "大屏: the add icon becomes a send arrow with command held and starts the written task" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("检查发布说明")
  assert_true(t.query(Button, label="添加") is Some(_))
  assert_eq(board_button_icon(t, "添加"), "/icon/plus/")
  assert_true(board_words_at(t, "添加") is None)
  t.hold_mods(@ui.mod_cmd)
  t.draw()
  assert_true(t.query(Button, label="派发") is Some(_))
  assert_eq(board_button_icon(t, "派发"), "/icon/arrow-up/")
  assert_true(board_words_at(t, "派发") is None)
  t.hold_mods(0)
  t.draw()
  assert_true(t.query(Button, label="添加") is Some(_))
  assert_eq(board_button_icon(t, "添加"), "/icon/plus/")
  t.hold_mods(@ui.mod_cmd)
  t.draw()
  t.click(Button, label="派发")
  t.run_for(@ui.move_most_ms)
  assert_eq(board_lane_now(src, "检查发布说明"), "run")
  assert_eq(board_kept_drafts(), ["给导出加上按月份筛选", "看一下 Android 冷启动为什么慢了 300ms"])
  assert_eq(board_faults(t), [])
}

///|
test "大屏: a chat put in the pane's place from the board (⌘N, 待处理's, ⌘K's) shows the list again, 对话 lit, the board not kept as Home" {
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let pages : Array[Page] = [NewChat, Chat(chat)]
  for p in pages {
    let (t, src) = board_at("board", 1440.0, 900.0)
    open_page(p)
    t.run_for(@ui.move_most_ms)
    assert_false(@sfbase.board_on_of(src, "ws1"))
    assert_eq(@sfdesk.lit_place(), "chats")
    assert_true(board_words_at(t, "待派发") is None)
    // (closed: Home's list, not the board)
    app.nav.pop() |> ignore
    t.run_for(@ui.move_most_ms)
    assert_false(@sfbase.board_on_now(src))
    assert_eq(board_faults(t), [])
  }
}

///|
test "大屏: words written in 待派发 kept as the board makes way for the list or a chat, there again as 看板 is pressed" {
  let chat : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("作为文件")
  t.run_for(@ui.move_most_ms)
  // (对话: the list again, the board gone)
  board_rail_press(t, "对话")
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(t.query(TextField, label="要做什么？") is None)
  // (看板 again: its line open on what was written, nothing added)
  board_rail_press(t, "看板")
  assert_true(@sfbase.board_adding.get())
  assert_eq(t.field_words(), "作为文件")
  assert_false(board_kept_drafts().contains("作为文件"))
  // (a chat put in the board's place: the words kept for the board to come back to)
  open_page(Chat(chat))
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.board_on_of(src, "ws1"))
  assert_true(@sfbase.board_writing_kept(src, "ws1"))
  assert_false(board_kept_drafts().contains("作为文件"))
}

///|
test "大屏: 待派发's line put away by Escape is empty as it opens again; once added, empty for the next" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("留待稍后")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_true(board_kept_drafts().contains("留待稍后"))
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.board_writing_kept(src, "ws1"))
  assert_eq(t.field_words(), "")
  t.type_text("现在执行")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.board_writing_kept(src, "ws1"))
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  assert_eq(t.field_words(), "")
  assert_eq(board_faults(t), [])
}


///|
test "大屏: 看板 taken out of the rail from its menu, kept so; 侧边条恢复默认 puts it back right under 对话" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.host_says_finger(Some(false))
  assert_true(@sfdesk.rail_items(src, "ws1").contains("board"))
  guard board_rail_rect(t, "看板") is Some((x, y, w, h)) else { fail("no 看板 in the rail") }
  t.right_click(x + w / 2.0, y + h / 2.0)
  t.run_for(@motion.pop_ms)
  t.tap_text("从侧边条移除看板")
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.rail_items(src, "ws1").contains("board"))
  assert_eq(board_sidebars_said(src, "ws1\nboardRail"), "closed")
  // (自定义侧边条 offers it again among the lists, as it does any place taken out)
  guard board_rail_rect(t, "对话") is Some((dx, dy, dw, dh)) else { fail("no 对话 in the rail") }
  let words_before = board_words_n(t, "看板")
  t.right_click(dx + dw / 2.0, dy + dh / 2.0)
  t.run_for(@motion.pop_ms)
  t.tap_text("自定义侧边条")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfdesk.wide.editing.get())
  assert_true(board_words_n(t, "看板") > words_before, msg="看板 offered in 自定义侧边条")
  t.key(@ui.key_escape)
  t.run_for(@ui.move_most_ms)
  assert_false(@sfdesk.wide.editing.get())
  // (the rail's menu: 侧边条恢复默认, the rail changed)
  guard board_rail_rect(t, "对话") is Some((cx, cy, cw, ch)) else { fail("no 对话 in the rail") }
  t.right_click(cx + cw / 2.0, cy + ch / 2.0)
  t.run_for(@motion.pop_ms)
  t.tap_text("侧边条恢复默认")
  t.run_for(@ui.move_most_ms)
  let items = @sfdesk.rail_items(src, "ws1")
  match (items.search_by(fn(i) { i == "chats" }), items.search_by(fn(i) { i == "board" })) {
    (Some(c), Some(b)) => assert_eq(b, c + 1)
    _ => fail("对话 and 看板 in the rail: " + items.join(","))
  }
  assert_eq(board_sidebars_said(src, "ws1\nboardRail"), "")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: the columns gone sideways to their end, the chat beside narrowed by its edge: none left empty at their end" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="整理发布清单")
  t.run_for(@ui.move_most_ms)
  let edge = fn() { t.query(Separator, label="调整侧栏宽度").map(fn(n) { n.rect }).unwrap_or((0.0, 0.0, 0.0, 0.0)) }
  // wider (640): two columns showing, the board gone sideways to its last
  let (ex, ey, ew, eh) = edge()
  board_edge_drag(t, ex + ew / 2.0, ey + eh / 2.0, ex + ew / 2.0 - 180.0)
  t.run_for(@ui.move_most_ms)
  t.wheel_with(300.0, 600.0, 4000.0, 0.0, 0)
  t.run_for(@ui.move_most_ms)
  // narrower (360): the last column's end where the board's room ends, no further in
  let (fx, fy, fw, fh) = edge()
  board_edge_drag(t, fx + fw / 2.0, fy + fh / 2.0, 1400.0)
  t.run_for(@ui.move_most_ms)
  let (gx, _, _, _) = edge()
  guard t.query(Button, label="盯着 CI，绿了告诉我") is Some(card) else { fail("监控中's card not shown") }
  let end = card.rect.0 + card.rect.2
  assert_true(end >= gx - 40.0, msg="the last column ends at \{end}, the board's room at \{gx}")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: Enter adds a draft, command Enter dispatches it; a refused dispatch keeps its words" {
  let (t, src) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("留待稍后")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_true(board_kept_drafts().contains("留待稍后"))
  assert_eq(board_lane_now(src, "留待稍后"), "")
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("现在执行")
  t.hold_mods(@ui.mod_cmd)
  t.key(@ui.key_code_enter, mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_lane_now(src, "现在执行"), "run")
  assert_false(board_kept_drafts().contains("现在执行"))
  t.hold_mods(0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("暂时无法启动")
  @sffixture.board_create_refused.val = "机器上没有可用的模型。"
  t.hold_mods(@ui.mod_cmd)
  t.key(@ui.key_code_enter, mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.toast_words(), "机器上没有可用的模型。")
  assert_true(board_kept_drafts().contains("暂时无法启动"))
  assert_eq(board_faults(t), [])
}

///|
test "大屏: Ctrl Enter dispatches with a Windows keyboard" {
  let (t, src) = board_at("board", 1440.0, 900.0, platform=3)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  t.type_text("立即检查")
  t.hold_mods(@ui.mod_ctrl)
  t.draw()
  assert_true(t.query(Button, label="派发") is Some(_))
  t.key(@ui.key_code_enter, mods=@ui.mod_ctrl)
  t.run_for(@ui.move_most_ms)
  assert_eq(board_lane_now(src, "立即检查"), "run")
  assert_false(board_kept_drafts().contains("立即检查"))
  assert_eq(board_faults(t), [])
}


///|
test "待派发: pressing a draft opens its panel on 大屏 and 小屏: its words kept as it closes, its identity and destination kept, 派发 starts it" {
  for (w, h, platform) in [(1440.0, 900.0, 0), (390.0, 844.0, 2)] {
    let (t, src) = board_at("board", w, h, platform~)
    if platform == 2 {
      t.click(Tab, label="待派发 2")
      t.run_for(@ui.move_most_ms)
    }
    let before = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1")[0] })
    t.click(Button, label=before.title)
    t.run_for(@ui.move_most_ms)
    assert_eq(t.focused().map(fn(f) { (f.role, f.value) }), Some((TextField, before.title)))
    // (where it runs, and on what, in its panel)
    assert_true(board_words_at(t, "编辑待办") is Some(_))
    assert_eq(board_faults(t), [])
    t.type_text("，包括 CSV")
    t.click(Button, label="完成")
    t.run_for(@ui.move_most_ms)
    let after = @signals.untracked(fn() { @sfbase.board_drafts_of(src, "ws1")[0] })
    assert_eq((after.id, after.station, after.station_name), (before.id, before.station, before.station_name))
    assert_eq(after.title, before.title + "，包括 CSV")
    assert_eq(board_kept_drafts()[0], after.title)
    // (closed by Escape: what was written kept as well)
    t.click(Button, label=after.title)
    t.run_for(@ui.move_most_ms)
    t.type_text(" 文件")
    t.key(@ui.key_escape)
    t.run_for(@ui.move_most_ms)
    let edited = after.title + " 文件"
    assert_eq(board_kept_drafts()[0], edited)
    assert_eq(board_faults(t), [])
    // (派发 from its panel: its chat made)
    t.click(Button, label=edited)
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="派发")
    t.run_for(@ui.move_most_ms)
    assert_eq(board_lane_now(src, edited), "run")
  }
}

///|
test "大屏: Enter in a draft's panel keeps its words; emptied, with nothing carried, the words it had are kept" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="给导出加上按月份筛选")
  t.run_for(@ui.move_most_ms)
  t.type_text("，并导出 CSV")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts()[0], "给导出加上按月份筛选，并导出 CSV")
  t.click(Button, label=board_kept_drafts()[0])
  t.run_for(@ui.move_most_ms)
  t.key(@ui.key_of_char('a'), mods=@ui.mod_cmd)
  t.type_text(" ")
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq(board_kept_drafts()[0], "给导出加上按月份筛选，并导出 CSV")
  assert_eq(board_faults(t), [])
}

///|
test "大屏: the new task's card holds its words and send alone, no ＋ and no station in it" {
  let (t, _) = board_at("board", 1440.0, 900.0)
  t.click(Button, label="新待办")
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="发送文件") is None)
  assert_true(t.query(Button, label="在哪台机器上运行: Willow") is None)
  assert_true(t.query(Button, label="添加") is Some(_))
  assert_eq(board_faults(t), [])
}

///|
/// Whether the chat beside the board is its page made as nodes, by the message `words` it shows (whole, as no card's
/// line says it): drawn by a node of its messages' (sfpages' chat_page_node, chat_body_node) and no old view's list
/// under it, its composer sfpages' composer_node's (its field's words, the cursor in it or not); the old page the
/// other way round.
fn board_beside_made_nodes(t : @ui.Tester, words : String, at : String) -> Bool raise {
  let said = t.sources_of(words)
  let by_nodes = said.contains("sfpages/chat_page_node.mbt") || said.contains("sfpages/chat_body_node.mbt")
  let old_rows = t.old_list_row_boxes().iter().any(fn(rows) { !rows.is_empty() })
  assert_true(by_nodes != old_rows, msg="\{at}: its message drawn by nodes \{by_nodes}, an old list's rows \{old_rows}")
  // (its field's words: 发消息 with the cursor in it, 按空格输入 without)
  let composed = ["发消息", "按空格输入"].iter().any(fn(w) { t.sources_of(w).contains("sfpages/composer_node.mbt") })
  assert_eq(composed, by_nodes, msg="\{at}: its composer made as nodes \{composed}")
  by_nodes
}

///|
test "大屏: the chat beside the board made as nodes, its composer too; words sent from it, another card's chat in its place" {
  new_run()
  let calls : Array[Made] = []
  let base = fixture("board")
  let src : Source = {
    ..base,
    call: fn(name, params, done) {
      calls.push({ name, params, bytes: None, done })
      (base.call)(name, params, done)
    },
  }
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0, platform=0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="给设置页加一个深色模式开关")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.board_pick.get() is Some(_))
  let c4_last = "做完了：开关和三处颜色都改好了，已合进 main（a3f9c21）。"
  assert_true(board_beside_made_nodes(t, c4_last, "opened"), msg="opened: the page made as nodes")
  assert_eq(board_faults(t), [])
  assert_eq(t.audit().filter(fn(f) { f.contains("sfdesk/board_beside_node") }), [])
  // words written in its composer and sent, by its chat
  t.tap_text("发消息")
  t.type_text("再加一个跟随系统")
  tap_send(t)
  let sent = named(calls, "chat.send")
  assert_eq(sent.length(), 1)
  assert_eq(text(Some(sent[0].params), "text"), "再加一个跟随系统")
  assert_eq(text(Some(sent[0].params), "station"), "ws1/st1")
  t.run_for(@ui.move_most_ms)
  assert_true(board_words_at(t, "再加一个跟随系统") is Some(_), msg="what was sent in its list")
  assert_eq(board_faults(t), [])
  // another card pressed: its chat in its place at once, the one before let go
  t.click(Button, label="Slack 里问的报销流程")
  t.run_for(@ui.move_most_ms)
  let c7_last = "做完了：三个步骤整理成了一页文档，放在共享盘的「行政」里。"
  assert_true(board_beside_made_nodes(t, c7_last, "another"), msg="another: the page made as nodes")
  assert_false(t.sources_of(c4_last).contains("sfpages/chat_body_node.mbt"), msg="the chat before let go")
  assert_eq(board_faults(t), [])
}

///|
test "待派发: a draft's picture the device reads late comes to its tile, and a video picked here stands on a video's black with its play mark" {
  new_run()
  let base = fixture("board")
  let answer : Ref[((Result[(Json, Bytes?), Json]) -> Unit)?] = Ref(None)
  let src : Source = {
    ..base,
    // (no bytes of the picture here: the device's kept one, read as composer.picture answers, late)
    draft_picture: fn(key, id) {
      base.images.get("", "draft\u{1}" + key + "\u{1}" + id, "mem:test/board-restored", fn(_, done) { answer.val = Some(done) })
    },
  }
  open_fixture_over("board", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1440.0, h=900.0)
  t.run_for(@ui.move_most_ms)
  // (the video's still drawn here, as one picked here keeps it; a few bytes, as a test's pictures are)
  let still = "mem:test/board-still"
  @ui.add_image(still, @pixels.png(2, 2, FixedArray::make(16, b'\x30')))
  @sfbase.writing_picture_put("board-vid", still)
  @sfbase.board_draft_add(src, "ws1", "带图和视频的待办", "ws1/st1", "Willow", files=[
    { id: "board-img", name: "恢复.png" },
    { id: "board-vid", name: "录屏.mp4" },
  ])
  |> ignore
  t.run_for(@ui.move_most_ms)
  assert_true(answer.val is Some(_), msg="the device's kept picture was not asked")
  assert_eq(t.locate("img:mem:test/board-restored").length(), 0)
  (answer.val.unwrap())(Ok((Json::object({}), Some(@pixels.png(2, 2, FixedArray::make(16, b'\xff'))))))
  t.run_for(@ui.move_most_ms + @ui.image_fade_ms)
  assert_true(t.locate("img:mem:test/board-restored").length() > 0, msg="the restored picture did not come to its tile")
  // (the video's tile: its still on a video's black, that black composited into the still as its matte and cut once
  // with it, never drawn apart under it where its rounded edge would show through as a rim; its play mark over it)
  guard t.locate("img:" + still).get(0) is Some((vx, vy)) else { fail("the video's still is not drawn") }
  let grounds = t.drawn_rects().filter(fn(r) { vx >= r.0 && vx <= r.0 + r.2 && vy >= r.1 && vy <= r.1 + r.3 }).map(fn(r) { r.4 })
  assert_false(grounds.contains(0x000000FFL), msg="\{Repr(grounds)}")
  let stills = t
    .drawn_instances()
    .filter(fn(i) {
      i[5] == 4.0 &&
      (i[2] - 56.0).abs() < 0.5 &&
      (i[3] - 56.0).abs() < 0.5 &&
      vx >= i[0] &&
      vx <= i[0] + i[2] &&
      vy >= i[1] &&
      vy <= i[1] + i[3]
    })
  guard stills is [s, ..] else { fail("no 56×56 still at \{vx},\{vy}: \{Repr(t.drawn_images())}") }
  assert_true(s[22] == 1.0 && s[21] == 1.0 && s[8] == 0.0 && s[9] == 0.0 && s[10] == 0.0, msg="\{Repr(s)}")
  let marks = t.locate("icon:play-mark").filter(fn(p) { (p.0 - vx).abs() < 28.0 && (p.1 - vy).abs() < 28.0 })
  assert_true(marks.length() > 0, msg="no play mark on the video's tile: \{Repr(t.locate("icon:play-mark"))} at \{vx},\{vy}")
}
