// A row of tools, each with its tip in one layer (tool_node, tip_node): the hand gone along them, from one to the next,
// the next's tip shown at once in place of the one before (TipLayer's handoff), its ground going from where that one's
// was drawn, as wide, to its own place beside its tool, its words with it, whole all the way (no fading in), one tip's
// ground drawn at a time; at its place, as one shown there by the hand resting on its tool, before tip_settled_ms; the
// same going right to left; the hand come to the row afresh, as ever (after tip_delay_ms, faded in).

///|
/// The tools' labels, their words of different lengths (their tips as wide as they are).
let roving_labels : Array[String] = ["复制", "在新窗口打开这个文件", "下载"]

///|
/// A moment well into a tip's way from the one before, short of its end; how far apart the moments its speed is read at
/// are.
let tip_glide_mid_ms : Double = 50.0

///|
let tip_hand_step_ms : Double = 4.0

///|
/// Three tools side by side, each with its tip below it in one layer over all of the window. The Tester.
fn roving_tips_tester() -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=600.0, h=300.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(r) {
      r.row(Is(true)).padding(Is((200.0, 40.0, 0.0, 0.0))) |> ignore
      for label in roving_labels {
        r.box(fn(b) {
          tool_node(
            b,
            fn() { { icon: "copy", label, on: false, disabled: false } },
            fn() { page_viewer_ink() },
            Is(tool_side / 2.0),
            fn() {  },
            tip=tips,
          )
          |> ignore
        })
        |> ignore
      }
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  t
}

///|
/// The tips shown (not hidden), by their words.
fn roving_shown(t : @ui.Tester) -> Array[String] {
  t.semantics().filter(fn(s) { s.role == Tooltip && !s.hidden }).map(fn(s) { s.label })
}

///|
/// The liquid-glass tooltip grounds drawn (or solid fallback rects of colour `ink`): where each is.
fn roving_grounds(t : @ui.Tester, ink : Int64) -> Array[(Double, Double, Double, Double)] {
  let glass = t.drawn_glass().filter(fn(g) { g.4 == 6 }).map(fn(g) { (g.0, g.1, g.2, g.3) })
  if !glass.is_empty() {
    glass
  } else {
    t.drawn_rects().filter(fn(r) { r.4 == ink }).map(fn(r) { (r.0, r.1, r.2, r.3) })
  }
}

///|
/// Tool `k`'s middle.
fn roving_tool_at(t : @ui.Tester, k : Int) -> (Double, Double) raise {
  let b = t.get(Button, label=roving_labels[k])
  (b.rect.0 + b.rect.2 / 2.0, b.rect.1 + b.rect.3 / 2.0)
}

///|
/// Tool `k`'s tip rested on from a row none of whose tips showed: its rect and its ground's colour (or 1L for liquid glass).
fn roving_cold(k : Int) -> ((Double, Double, Double, Double), Int64) raise {
  let t = roving_tips_tester()
  let (x, y) = roving_tool_at(t, k)
  t.move_to(x, y)
  t.run_for(tip_delay_ms + tip_settled_ms)
  let tip = t.get(Tooltip, label=roving_labels[k]).rect
  let has_glass = t.drawn_glass().iter().any(fn(g) { g.4 == 6 && (g.0, g.1, g.2, g.3) == tip })
  let ink = if has_glass {
    1L
  } else {
    match t.drawn_rects().filter(fn(r) { (r.0, r.1, r.2, r.3) == tip }).get(0) {
      Some(r) => r.4
      None => 0L
    }
  }
  (tip, ink)
}

///|
fn roving_between(a : Double, b : Double, v : Double) -> Bool {
  (v > a && v < b) || (v < a && v > b)
}

///|
/// The hand along the row in `order` (rested on the first till its tip showed): at each tool, its tip at once in place of
/// the one before, from where that one's ground was, whole; on its way half through; at its place before tip_settled_ms.
fn roving_sweep(order : Array[Int]) -> Unit raise {
  // (each shown from a row none of whose showed, first: a Tester reads the frame of the one made last)
  let cold = [roving_cold(0), roving_cold(1), roving_cold(2)]
  let t = roving_tips_tester()
  let first = order[0]
  let (x, y) = roving_tool_at(t, first)
  t.move_to(x, y)
  t.run_for(tip_delay_ms + tip_settled_ms)
  let (_, ink) = cold[first]
  assert_true(ink != 0L, msg="a tip's ground found")
  let mut was = t.get(Tooltip, label=roving_labels[first]).rect
  assert_eq(roving_grounds(t, ink), [was], msg="the first shown, where it is")
  for i in 1..<order.length() {
    let k = order[i]
    let (x, y) = roving_tool_at(t, k)
    t.move_to(x, y)
    // (at once, from where the one before was: one ground, as wide as that one's)
    assert_eq(roving_shown(t), [roving_labels[k]], msg="\{k}: at once, alone")
    assert_eq(roving_grounds(t, ink), [was], msg="\{k}: its ground where the one before was: \{Repr(roving_grounds(t, ink))} / \{Repr(was)}")
    t.run_for(tip_glide_mid_ms)
    let (to, _) = cold[k]
    let mid = roving_grounds(t, ink)
    assert_eq(mid.length(), 1, msg="\{k}: one ground on its way: \{Repr(mid)}")
    let m = mid[0]
    assert_true(
      roving_between(was.0 + was.2 / 2.0, to.0 + to.2 / 2.0, m.0 + m.2 / 2.0),
      msg="\{k}: on its way across: \{Repr(m)} from \{Repr(was)} to \{Repr(to)}",
    )
    assert_true(roving_between(was.2, to.2, m.2), msg="\{k}: as wide as between: \{Repr(m)}")
    assert_eq(roving_shown(t), [roving_labels[k]], msg="\{k}: whole on its way")
    t.run_for(tip_settled_ms - tip_glide_mid_ms)
    assert_eq(t.get(Tooltip, label=roving_labels[k]).rect, to, msg="\{k}: at its place, as one rested on")
    assert_eq(roving_grounds(t, ink), [to], msg="\{k}: its ground at its place")
    was = to
  }
}

///|
test "tips of a row of tools, the hand along it left to right: each at once from where the one before was, at its place before tip_settled_ms" {
  roving_sweep([0, 1, 2])
}

///|
test "tips of a row of tools, the hand along it right to left: each at once from where the one before was, at its place before tip_settled_ms" {
  roving_sweep([2, 1, 0])
}

///|
test "tips of a row of tools, the hand on to a third while the second's goes: from where that one is on its way, as fast as it went, at the third's place before tip_settled_ms" {
  let (_, ink) = roving_cold(0)
  let (to, _) = roving_cold(2)
  let t = roving_tips_tester()
  let (x, y) = roving_tool_at(t, 0)
  t.move_to(x, y)
  t.run_for(tip_delay_ms + tip_settled_ms)
  let (x, y) = roving_tool_at(t, 1)
  t.move_to(x, y)
  let mid = fn(g : Array[(Double, Double, Double, Double)]) { g[0].0 + g[0].2 / 2.0 }
  t.run_for(tip_glide_mid_ms - tip_hand_step_ms)
  let before = mid(roving_grounds(t, ink))
  t.run_for(tip_hand_step_ms)
  let on_way = roving_grounds(t, ink)
  let (x, y) = roving_tool_at(t, 2)
  t.move_to(x, y)
  assert_eq(roving_grounds(t, ink), on_way, msg="the third's from where the second's was on its way: \{Repr(roving_grounds(t, ink))} / \{Repr(on_way)}")
  assert_eq(roving_shown(t), [roving_labels[2]], msg="the third's alone")
  t.run_for(tip_hand_step_ms)
  let after = mid(roving_grounds(t, ink))
  // (as fast just after as just before, the same way: the speed it had taken on)
  let (v0, v1) = (mid(on_way) - before, after - mid(on_way))
  assert_true(v0 > 0.0 && v1 > 0.0, msg="on across all along: \{before} \{mid(on_way)} \{after}")
  assert_true(v1 / v0 > 0.5 && v1 / v0 < 2.0, msg="as fast where it turned: \{v0} then \{v1}")
  t.run_for(tip_settled_ms - tip_hand_step_ms)
  assert_eq(roving_grounds(t, ink), [to], msg="at the third's place")
}

///|
test "tips of a row of tools, the hand come to it afresh (no tip of it shown a while): after tip_delay_ms, faded in, not from anywhere" {
  let (to, ink) = roving_cold(1)
  let t = roving_tips_tester()
  let (x, y) = roving_tool_at(t, 0)
  t.move_to(x, y)
  t.run_for(tip_delay_ms + tip_settled_ms)
  t.leave()
  t.run_for(@headless.tooltip_skip_ms + tip_settled_ms)
  let (x, y) = roving_tool_at(t, 1)
  t.move_to(x, y)
  t.run_for(tip_delay_ms - tip_short_ms)
  assert_eq(roving_shown(t), [], msg="not yet")
  t.run_for(tip_short_ms + tip_settled_ms)
  assert_eq(roving_grounds(t, ink), [to], msg="where one rested on is")
}
