// A composer's floating capsule covers the messages scrolled beneath it. A press in that capsule must not start a
// selection in those messages (and the selection's edge scrolling), while the messages remain selectable beside it.

///|
/// The pointer held in the composer's padding, long enough for selection edge scrolling to be visible.
let cover_mouse_hold_ms : Double = 500.0

///|
/// How far apart a finger's moves come as it pulls the messages: a frame's at 60 Hz.
let cover_drag_step_ms : Double = 16.0

///|
fn composer_cover_tester(pointing? : @ui.Pointing = Mouse, platform? : Int = 0) -> @ui.Tester {
  new_run()
  let src = fixture("chat")
  let r : ChatRef = { station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" }
  let keys : Array[Int] = Array::makei(40, fn(i) { i })
  @sf.set_words(fill)
  let t = @ui.Tester::new(
    fn(c) {
      let _ = @sf.begin(c)
      c.mouse_drags_lists(pointing is Finger)
      @sf.presented(c)
    },
    tree=fn(root) {
      @ui.set_tree_theme(@sf.ui_theme_now)
      let popup = root.box(fn(v) { v.over(Is(true)) |> ignore })
      let tips = @sf.TipLayer::new(fn() { Some(popup) })
      root.box(fn(page) {
        page.width(Is(Some(600.0))).height(Is(Some(500.0))) |> ignore
        @ui.words_picked(page)
        page.scrolls_window(
          @view.Scroll::new(),
          fn() { keys },
          fn(row, i) {
            row.height(Is(Some(40.0))).width(Is(Some(600.0))) |> ignore
            row
            .box(fn(w) {
              w
              .words_runs(
                Is([@ui.plain("Message \{i} words behind the floating composer for this test")]),
              )
              |> ignore
            })
            |> ignore
          },
          foot=fn(f) {
            f.box(fn(pad) {
              @sf.style_node(pad, fn() { @ui.css("w=Full p=S4") })
              @sfpages.chat_composer_node(pad, src, r, shows=fn() { true }, tips~)
            })
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    },
    w=600.0,
    h=500.0,
    platform~,
    pointing~,
  )
  t.draw()
  t.ctx().blur()
  t.run_for(@sfpages.let_go_ms + @ui.move_most_ms)
  t
}

///|
fn composer_cover_glass_box(t : @ui.Tester) -> (Double, Double, Double, Double) {
  match @sfpages.composer_node_shown(t.time()) {
    Some(r) => r
    None => {
      let g = t.drawn_glass()[0]
      (g.0, g.1, g.2, g.3)
    }
  }
}

///|
/// A point in the composer line's empty backdrop beside the field (`under` hit area).
fn composer_cover_line_hit(t : @ui.Tester) -> (Double, Double) {
  let (gx, gy, gw, gh) = composer_cover_glass_box(t)
  (gx + gw - 70.0, gy + gh / 2.0)
}

///|
test "composer over messages: pressing its capsule does not pick or scroll words under it" {
  let t = composer_cover_tester()
  // Its top padding is over a message and above the field's own hit target.
  let (gx, top, gw, _) = composer_cover_glass_box(t)
  let x = gx + gw / 2.0
  let y = top + 4.0
  let before = t.list_offset()
  t.press_at(x, y)
  t.move_to(x + 80.0, y)
  t.run_for(cover_mouse_hold_ms)
  assert_eq(t.ctx().selected_text(), "")
  assert_eq(t.list_offset(), before)
  t.release(x + 80.0, y)
}

///|
test "composer over messages: its backdrop takes the focus and clears a selection; uncovered words and the wheel still work" {
  let t = composer_cover_tester()
  t.drag(1.0, 55.0, 300.0, 55.0)
  t.frame()
  assert_true(t.ctx().selected_text() != "")
  let (gx, top, gw, _) = composer_cover_glass_box(t)
  // Pressing its top padding still does not select underlying words, and wheeling over it scrolls the list.
  let (lx, ly) = composer_cover_line_hit(t)
  t.tap(lx, ly)
  assert_eq(t.ctx().selected_text(), "")
  assert_true(composer_focused())
  let before = t.list_offset()
  t.wheel(gx + gw / 2.0, top + 4.0, 160.0)
  t.run_for(@ui.wheel_ease_ms)
  assert_true(t.list_offset() > before)
}

///|
test "composer over messages: a finger held on its padding does not select behind it, and tapping its line takes the field" {
  let t = composer_cover_tester(pointing=Finger, platform=2)
  let (gx, top, gw, _) = composer_cover_glass_box(t)
  let x = gx + gw / 2.0
  let y = top + 4.0
  let before = t.list_offset()
  t.touch(0, x, y)
  t.run_for(@ui.long_press_ms * 2.0)
  assert_eq(t.ctx().selected_text(), "")
  t.touch(2, x, y)
  t.draw()
  assert_eq(t.list_offset(), before)
  let (lx, ly) = composer_cover_line_hit(t)
  t.touch(0, lx, ly)
  t.run_for(@ui.long_press_ms * 2.0)
  assert_eq(t.ctx().selected_text(), "")
  t.touch(2, lx, ly)
  t.draw()
  assert_true(t.ime().0)
  assert_eq(t.list_offset(), before)
}

///|
test "composer over messages: clicking inside its field clears a previous message selection" {
  let t = composer_cover_tester()
  t.drag(1.0, 55.0, 300.0, 55.0)
  t.frame()
  assert_true(t.ctx().selected_text() != "")
  let (x, y, _, h) = t.rect_of("按空格输入").unwrap()
  t.tap(x + 100.0, y + h / 2.0)
  assert_true(composer_focused())
  assert_eq(t.ctx().selected_text(), "")
}

///|
test "composer adaptive glass keeps its backdrop fade as it expands with keyboard and mouse" {
  let t = composer_cover_tester()
  let glass_of = fn() -> (Double, Int, Bool) {
    let (gx, gy, gw, gh) = composer_cover_glass_box(t)
    let hit = t.drawn_instances().iter().find_first(fn(a) {
      a[5] == 6.0 && (a[0] - gx).abs() < 2.0 && (a[1] - gy).abs() < 2.0 && (a[2] - gw).abs() < 2.0 && (a[3] - gh).abs() < 2.0
    })
    match hit {
      Some(a) => (a[7], (a[11] * 255.0).round().to_int(), a[14] < -0.5)
      None => (-1.0, -1, false)
    }
  }
  assert_eq(glass_of(), (2.1, 0x67, true))
  let has_backdrop = fn() {
    let (gx, gy, gw, gh) = composer_cover_glass_box(t)
    t.drawn_instances().iter().any(fn(a) {
      a[5] == 0.0 && a[53] > 0.0 && (a[11] * 255.0).round().to_int() == 0xFE && a[0] <= gx && a[2] >= gw &&
      a[1] < gy && a[1] + a[3] > gy + gh / 2.0
    })
  }
  assert_true(has_backdrop(), msg="expected a fade behind the compact composer")
  // Focusing expands the composer into the 40% (0x67), blur=4.0 adaptive glass recipe (#8086 + Wave 7)
  let (lx, ly) = composer_cover_line_hit(t)
  t.tap(lx, ly)
  t.run_for(@ui.move_most_ms)
  assert_true(composer_focused())
  assert_eq(glass_of(), (4.0, 0x67, true))
  assert_true(has_backdrop(), msg="expected a fade behind the expanded composer")
}

///|
test "the messages fade behind the composer only while the soft keyboard is up, eased in and out" {
  let t = composer_cover_tester(pointing=Finger, platform=2)
  // (the keyboard's fade: the page's ground, nearly opaque, reaching over the composer's glass from above it)
  let backdrop = fn() {
    let (gx, gy, gw, gh) = composer_cover_glass_box(t)
    t.drawn_instances().filter(fn(a) {
      a[5] == 0.0 && a[53] > 0.0 && (a[11] * 255.0).round().to_int() == 0xFE && a[0] <= gx && a[2] >= gw &&
      a[1] < gy && a[1] + a[3] > gy + gh / 2.0
    })
  }
  assert_eq(backdrop().length(), 0, msg="none with the keyboard down")
  t.set_ime_inset(300.0)
  t.run_for(@ui.move_most_ms)
  guard backdrop() is [_, ..] else { fail("no fade behind the composer with the keyboard up") }
  t.set_ime_inset(0.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(backdrop().length(), 0, msg="gone as the keyboard goes")
}

///|
test "composer over messages on Android: the messages pulled past their top stretch, the composer drawn where it rests" {
  let t = composer_cover_tester(pointing=Finger, platform=2)
  let glass = fn() {
    t.drawn_glass().map(fn(g) { (g.0, g.1, g.2, g.3) })
  }
  let rest_glass = glass()
  assert_true(rest_glass.length() > 0, msg="no glass drawn")
  let (gx, top, gw, gh) = composer_cover_glass_box(t)
  // (what is read of the messages above the composer, and of the composer within its glass at rest)
  let messages = fn() { t.glyphs_seen().filter(fn(r) { r.3 <= top }) }
  let composer = fn() {
    t.glyphs_seen().filter(fn(r) { r.0 >= gx && r.2 <= gx + gw && r.1 >= top && r.3 <= top + gh })
  }
  let rest_messages = messages()
  let rest_composer = composer()
  assert_true(rest_composer.length() > 0, msg="no words read in the composer")
  // (a finger pulls the messages down from their top, past the slop, and holds them there)
  t.touch(0, 300.0, 150.0)
  for k in 1..=10 {
    t.advance(cover_drag_step_ms)
    t.touch(1, 300.0, 150.0 + 16.0 * k.to_double())
    t.draw()
  }
  assert_true(messages() != rest_messages, msg="the messages not stretched")
  assert_eq(glass(), rest_glass, msg="the composer's glass moved: \{Repr(glass())}, at rest \{Repr(rest_glass)}")
  assert_eq(
    composer(),
    rest_composer,
    msg="the composer's words moved: \{Repr(composer())}, at rest \{Repr(rest_composer)}",
  )
  t.touch(2, 300.0, 310.0)
  t.draw()
}
