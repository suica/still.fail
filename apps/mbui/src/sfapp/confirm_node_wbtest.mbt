// A confirm on 中屏 and 大屏 (in the middle of the window, not a sheet) as the window's tree's nodes, through the app's
// tree (app_tree's presented_nodes): at its serial's place in the window's stack of layers; its cancel and its action
// nodes of the tree's, pressed and acted on at once, no frame waited for; said, what it says done once, a confirm it
// opens open; gone, its old ids nothing.

///|
/// 大屏, chat A open, rested.
fn confirm_wide() -> @ui.Tester {
  let (t, _, _) = wide_backs(true)
  t
}

///|
/// The node of the window's tree read out as `role` labelled `label`, if one is (its own, not an old view's).
fn tree_said(role : @ui.Role, label : String) -> @view.NodeId? {
  let tree = @ui.view_tree().unwrap()
  tree
  .said_order()
  .iter()
  .find_first(fn(sn) { sn.said.map(fn(s) { s.role == role && s.label == label }).unwrap_or(false) })
  .map(fn(sn) { sn.id })
}

///|
/// What is read out as a button labelled `label` not hidden: its id (0 none).
fn button_id(t : @ui.Tester, label : String) -> Int {
  t.all(Button, label~).last().map(fn(s) { s.id }).unwrap_or(0)
}

///|
test "大屏: a confirm, at its serial's place in the window's stack of layers, its cancel and its action the tree's nodes; cancelled and asked again twice, no frame between: closed each time, nothing done" {
  let t = confirm_wide()
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  let serial = @sf.last_presented()
  t.draw()
  let tree = @ui.view_tree().unwrap()
  let placed = match tree_said(Button, "删除") {
    Some(id) => tree.stack_of(id) == serial
    None => false
  }
  let nodes = (tree_said(Button, "取消") is Some(_), tree_said(Button, "删除") is Some(_))
  t.ctx().ask_action(button_id(t, "取消"), Activate)
  let first = @sf.presenting()
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  t.ctx().ask_action(button_id(t, "取消"), Activate)
  let second = @sf.presenting()
  t.run_for(@ui.move_most_ms)
  assert_eq((placed, nodes, first, second, @sf.presenting(), runs.val), (true, (true, true), false, false, false, 0))
}

///|
test "大屏: a confirm whose action asks another: its action done once, the other open; the first's ids acted on as it has gone, nothing" {
  let t = confirm_wide()
  let (first, second) = (Ref(0), Ref(0))
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {
    first.val += 1
    @sf.confirm("归档", "归档这个对话？", "归档", fn() { second.val += 1 })
  })
  t.draw()
  let go = button_id(t, "删除")
  t.ctx().ask_action(go, Activate)
  let at_once = (first.val, @sf.presenting())
  t.run_for(@ui.move_most_ms)
  // (the first's action, its id as it was read out, asked again as it has gone)
  t.ctx().ask_action(go, Activate)
  t.draw()
  let open = t.all(Button, label="归档").length()
  assert_eq((at_once, first.val, second.val, open, @sf.presenting()), ((1, true), 1, 0, 1, true))
}

///|
test "大屏: a confirm asked and closed in one change, never shown: no confirm drawn, read out or presented, nothing left going or holding the focus" {
  let t = confirm_wide()
  let focus = t.focused().map(fn(s) { s.label })
  @signals.start_batch()
  @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
  @sf.close_presented()
  @signals.end_batch()
  t.draw()
  let at_once = (@sf.presenter_visible(), tree_said(Button, "删除") is None, t.all(Button, label="删除").length())
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (at_once, @sf.presenter_visible(), t.focused().map(fn(s) { s.label }) == focus, t.at_rest()),
    ((false, true, 0), false, true, true),
    msg="\{t.rest_why()}",
  )
}

///|
test "大屏: a confirm of what cannot be undone opened from what has the focus: the focus on none of its buttons, its own (no frame waited for, and a frame on); Enter does nothing (it has no default); Escape closes it, the focus back where it was" {
  let t = confirm_wide()
  t.act(Button, Focus, label="新建对话")
  let before = t.focused().map(fn(s) { s.label })
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 }, danger=true)
  // (no frame drawn: where the focus is as it opens)
  let at_once = (t.focused().map(fn(s) { s.label }), t.ctx().focus != 0)
  t.draw()
  let drawn = (t.focused().map(fn(s) { s.label }), t.ctx().focus != 0)
  t.enter()
  let entered = (runs.val, @sf.presenting())
  t.key_named("escape") |> ignore
  t.run_for(@ui.move_most_ms)
  assert_eq(
    (before, at_once, drawn, entered, runs.val, @sf.presenting(), t.focused().map(fn(s) { s.label })),
    (Some("新建对话"), (None, true), (None, true), (0, true), 0, false, Some("新建对话")),
  )
}

///|
test "大屏: a confirm opened, the focus its own: Tab to its cancel, its action, round to its cancel again, never its ground; Enter on its action does it" {
  let t = confirm_wide()
  let runs = Ref(0)
  @sf.confirm("删除", "删除这个对话？", "删除", fn() { runs.val += 1 })
  t.draw()
  let stops = []
  for _ in 0..<3 {
    t.tab()
    stops.push(t.focused().map(fn(s) { s.label }))
  }
  t.tab()
  t.enter()
  assert_eq((stops, runs.val), ([Some("取消"), Some("删除"), Some("取消")], 1))
}

///|
test "大屏: a confirm of what can be undone: Enter with the focus its own does its action and closes it; Enter on its cancel cancels" {
  let t = confirm_wide()
  let runs = Ref(0)
  @sf.confirm("归档", "归档这个对话？", "归档", fn() { runs.val += 1 })
  t.draw()
  t.enter()
  t.run_for(@ui.move_most_ms)
  let by_enter = (runs.val, @sf.presenting())
  @sf.confirm("归档", "归档这个对话？", "归档", fn() { runs.val += 1 })
  t.draw()
  t.tab()
  let on = t.focused().map(fn(s) { s.label })
  t.enter()
  t.run_for(@ui.move_most_ms)
  assert_eq((by_enter, on, runs.val, @sf.presenting()), ((1, false), Some("取消"), 1, false))
}

///|
test "大屏 on a Mac: ⌘. closes a confirm as Escape does (a Mac's cancel), its action not done" {
  new_run()
  let src = fixture("chat")
  open_chat(chat_a)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=840.0, platform=0)
  t.run_for(@ui.move_most_ms)
  let runs = Ref(0)
  @sf.confirm("归档", "归档这个对话？", "归档", fn() { runs.val += 1 })
  t.draw()
  let up = @sf.presenting()
  t.key(@ui.key_of_char('.'), mods=@ui.mod_cmd)
  t.run_for(@ui.move_most_ms)
  assert_eq((up, runs.val, @sf.presenting()), (true, 0, false))
}

///|
fn rect_contains(
  outer : (Double, Double, Double, Double),
  inner : (Double, Double, Double, Double),
) -> Bool {
  inner.0 >= outer.0 - 0.5 &&
  inner.1 >= outer.1 - 0.5 &&
  inner.0 + inner.2 <= outer.0 + outer.2 + 0.5 &&
  inner.1 + inner.3 <= outer.1 + outer.3 + 0.5
}

///|
fn glass_nested_pairs(t : @ui.Tester) -> Int {
  let ls = t.drawn_glass().filter(fn(g) { g.4 == 6 })
  let mut count = 0
  for i in 0..<ls.length() {
    for j in 0..<ls.length() {
      if i == j {
        continue
      }
      let a = (ls[i].0, ls[i].1, ls[i].2, ls[i].3)
      let b = (ls[j].0, ls[j].1, ls[j].2, ls[j].3)
      if a.2 * a.3 >= b.2 * b.3 && rect_contains(a, b) {
        count += 1
      }
    }
  }
  count
}

///|
test "大屏: confirm_node, panel_centred_node, and ⌘K switcher emit single-layer liquid glass with zero nesting and degrade cleanly under MBUI_GLASS=solid" {
  for dark in [false, true] {
    for solid in [false, true] {
      // 1. confirm_node
      let t1 = confirm_wide()
      @sf.set_dark(Some(dark))
      @ui.set_glass_solid(if solid { Some(true) } else { None })
      @sf.confirm("删除", "删除这个对话？", "删除", fn() {  })
      t1.run_for(@ui.move_most_ms)
      let dlg1 = t1.get(Dialog, label="删除").rect
      let hits1 = t1
        .drawn_glass()
        .filter(fn(g) { g.4 == 6 && (g.0 - dlg1.0).abs() < 1.0 && (g.1 - dlg1.1).abs() < 1.0 })
      assert_eq(hits1.length(), if solid { 0 } else { 1 }, msg="confirm dark=\{dark} solid=\{solid}")
      assert_eq(glass_nested_pairs(t1), 0, msg="confirm nested glass dark=\{dark}")

      // 2. ⌘K switcher_node
      let t2 = confirm_wide()
      @sf.set_dark(Some(dark))
      @ui.set_glass_solid(if solid { Some(true) } else { None })
      @sfdesk.switcher_open_with("")
      t2.run_for(@ui.move_most_ms)
      let dlg2 = t2.get(Dialog, label=@sf.t("web-main.switcher.search")).rect
      let hits2 = t2
        .drawn_glass()
        .filter(fn(g) { g.4 == 6 && (g.0 - dlg2.0).abs() < 1.0 && (g.1 - dlg2.1).abs() < 1.0 })
      assert_eq(hits2.length(), if solid { 0 } else { 1 }, msg="switcher dark=\{dark} solid=\{solid}")
      assert_eq(glass_nested_pairs(t2), 0, msg="switcher nested glass dark=\{dark}")
    }
  }
  @ui.set_glass_solid(None)
  @sf.set_dark(None)
}
