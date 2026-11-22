// A menu that is not modal (menu_node's `modal` false: a submenu's, beside the row that opened it): what is under it its
// own, a press outside it closing it and going on to what it lands on, a press on what opened it not; the arrow key back
// toward what opened it closing it. A modal menu takes a primary press outside, and hands a secondary press on after it
// closes.

///|
/// A window with a button 开 that opens a menu at its Right (`modal` or not), and a button 下面 under it, each counting its
/// presses (`under`), the menu's closings unchosen counted in `cancels`.
fn side_menu_tester(
  modal : Bool,
  open : @signals.Signal[Bool],
  cancels : Ref[Int],
  under : Ref[Int],
  leave_open? : Bool = false,
  solid? : Bool = false,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, platform=0)
  @ui.set_glass_solid(if solid { Some(true) } else { None })
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((100.0, 100.0, 0.0, 0.0))).gap(Is(40.0)) |> ignore
    let opener = root.box(fn(o) {
      o
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .on_press(fn() { open.set(true) })
      .says(Is(Some(@view.said(Button, label="开"))))
      |> ignore
    })
    root.box(fn(u) {
      u
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .on_press(fn() { under.val += 1 })
      .on_menu(fn(_) { under.val += 1 })
      .says(Is(Some(@view.said(Button, label="下面"))))
      |> ignore
    })
    |> ignore
    root.box(fn(l) {
      l.over(Is(true)) |> ignore
      menu_node(
        l,
        fn() { open.get() },
        fn(_) { opener },
        fn() { [Some(menu_item_of("一", fn() {  })), Some(menu_item_of("二", fn() {  }))] },
        "",
        Start,
        8.0,
        false,
        false,
        fn(_) { open.set(false) },
        fn() {
          cancels.val += 1
          if !leave_open {
            open.set(false)
          }
        },
        side=Right,
        modal~,
      )
    })
    |> ignore
  })
  t.draw()
  open.set(true)
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// The middle of the button `label` (开 or 下面), where side_menu_tester lays it out: 100 in, 100 down, 120 by 36, 40
/// apart (by where it is, not by what is read out: a modal menu hides what is under it from that).
fn side_button(label : String) -> (Double, Double) {
  if label == "开" {
    (160.0, 118.0)
  } else {
    (160.0, 194.0)
  }
}

///|
test "a menu not modal: a press outside its panel closes it as it goes down, and what it lands on is pressed; modal, the press its own" {
  for modal in [false, true] {
    let open = @signals.signal(false)
    let (cancels, under) = (Ref(0), Ref(0))
    let t = side_menu_tester(modal, open, cancels, under)
    assert_true(t.query(Menu) is Some(_), msg="modal \{modal}: open")
    let (x, y) = side_button("下面")
    t.tap(x, y)
    t.run_for(@ui.move_most_ms)
    assert_eq((cancels.val, under.val, t.query(Menu) is None), (1, if modal { 0 } else { 1 }, true), msg="modal \{modal}")
  }
}

///|
test "a modal menu: a secondary press inside leaves it open; outside closes it and goes to what is under it" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under)
  let (x, y, w, h) = t.rect_of("一").unwrap()
  t.right_click(x + w / 2.0, y + h / 2.0)
  assert_eq((cancels.val, under.val, t.query(Menu) is Some(_)), (0, 0, true))
  let (x, y) = side_button("下面")
  t.right_click(x, y)
  assert_eq((cancels.val, under.val, t.query(Menu) is None), (1, 1, true))
}

///|
test "a modal menu that stays open does not send its secondary press through" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under, leave_open=true)
  let (x, y) = side_button("下面")
  t.right_click(x, y)
  assert_eq((cancels.val, under.val, t.query(Menu) is Some(_)), (1, 0, true))
}

///|
test "a menu not modal: a press on what opened it leaves it open" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(false, open, cancels, under)
  let (x, y) = side_button("开")
  t.tap(x, y)
  t.run_for(@ui.move_most_ms)
  assert_eq((cancels.val, t.query(Menu) is Some(_)), (0, true))
}

///|
test "a menu not modal at its opener's Right: Left (back toward it) closes it; modal, Left closes nothing" {
  for modal in [false, true] {
    let open = @signals.signal(false)
    let (cancels, under) = (Ref(0), Ref(0))
    let t = side_menu_tester(modal, open, cancels, under)
    t.key(@ui.key_code_left)
    t.run_for(@ui.move_most_ms)
    assert_eq((cancels.val, t.query(Menu) is None), if modal { (0, false) } else { (1, true) }, msg="modal \{modal}")
  }
}

///|
/// How opaque the words `w` are drawn now (-1: not drawn).
fn side_words_alpha(t : @ui.Tester, w : String) -> Double {
  match t.words().filter(fn(x) { x.0 == w }) {
    [x, ..] => x.5
    [] => -1.0
  }
}

///|
test "a menu closed draws back into what opened it over pop_out_ms, nothing of it in the way from the moment it closes: a press under it is what it lands on's at once" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under)
  assert_eq(side_words_alpha(t, "一"), 1.0)
  t.key(@ui.key_escape)
  // (closed: not read out, not modal, nothing of it pressed, though still drawn)
  let (x, y) = side_button("下面")
  t.tap(x, y)
  assert_eq((cancels.val, under.val, t.query(Menu) is None), (1, 1, true))
  t.run_for(@motion.pop_out_ms / 2.0)
  let half = side_words_alpha(t, "一")
  assert_true(half > 0.0 && half < 1.0, msg="drawn back: \{half}")
  t.run_for(@motion.pop_out_ms / 2.0)
  assert_eq(side_words_alpha(t, "一"), -1.0)
}

///|
test "a menu closed half way in draws back from where it got to, never first whole: as faint as it was, fainter from there" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under)
  t.key(@ui.key_escape)
  t.run_for(@motion.pop_out_ms)
  assert_eq(side_words_alpha(t, "一"), -1.0)
  open.set(true)
  t.draw()
  t.run_for(@motion.pop_ms / 2.0)
  let mid = side_words_alpha(t, "一")
  assert_true(mid > 0.0 && mid < 1.0, msg="half way in: \{mid}")
  t.key(@ui.key_escape)
  t.draw()
  let closing = side_words_alpha(t, "一")
  assert_true(closing > 0.0 && closing <= mid, msg="as it closes: \{closing} after \{mid}")
  t.run_for(@motion.pop_out_ms / 4.0)
  let going = side_words_alpha(t, "一")
  assert_true(going < closing || going == -1.0, msg="going: \{going} after \{closing}")
  t.run_for(@motion.pop_out_ms)
  assert_eq(side_words_alpha(t, "一"), -1.0)
}

///|
/// A window 400 by 800 with a button 开 near its foot (at 740, 36 high), opening a menu of `rows` rows (行 00, 行 01,
/// …) under it, which has not the room there and goes above it, grown from its foot; open, `pop_ms` on.
fn foot_menu_tester(rows : Int, open : @signals.Signal[Bool]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=800.0, platform=0)
  @ui.set_glass_solid(Some(true))
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((100.0, 740.0, 0.0, 0.0))) |> ignore
    let opener = root.box(fn(o) {
      o
      .width(Is(Some(120.0)))
      .height(Is(Some(36.0)))
      .presses(Is(true))
      .on_press(fn() { open.set(true) })
      .says(Is(Some(@view.said(Button, label="开"))))
      |> ignore
    })
    root.box(fn(l) {
      l.over(Is(true)) |> ignore
      menu_node(
        l,
        fn() { open.get() },
        fn(_) { opener },
        fn() {
          Array::makei(rows, fn(i) {
            Some(menu_item_of("行 \{if i < 10 { "0" } else { "" }}\{i}", fn() {  }))
          })
        },
        "",
        Start,
        8.0,
        false,
        false,
        fn(_) { open.set(false) },
        fn() { open.set(false) },
      )
    })
    |> ignore
  })
  t.draw()
  t
}

///|
/// Where the menu's panel (the biggest drawn with its corner) and the words `first` are drawn now: the panel's top and
/// height, the words' top and how opaque they are (None: not drawn).
fn foot_menu_drawn(first : String) -> ((Double, Double)?, (Double, Double)?) {
  let drawn = @ui.view_tree().unwrap().drawn()
  let mut panel : (Double, Double)? = None
  let mut words : (Double, Double)? = None
  for d in drawn {
    if d.radius == r_menu && d.words == "" && (panel is None || d.h > panel.unwrap().1) {
      panel = Some((d.y, d.h))
    }
    if d.words == first && words is None {
      words = Some((d.y, d.alpha))
    }
  }
  (panel, words)
}

///|
test "a tall menu gone above what opened it comes in from its foot kept within pop_max_shift: its top row 8 or less from where it lands on its first frame, in and out smoothly" {
  defer { @ui.set_glass_solid(None) }
  let open = @signals.signal(false)
  let t = foot_menu_tester(18, open)
  open.set(true)
  t.draw()
  let (p0, w0) = foot_menu_drawn("行 00")
  t.run_for(@motion.pop_ms)
  let (p1, w1) = foot_menu_drawn("行 00")
  let (py, ph) = p1.unwrap()
  let (y1, a1) = w1.unwrap()
  assert_true(py + ph < 740.0, msg="above what opened it: \{py}, \{ph}")
  // (tall enough that 0.97 about its foot would leave its top more than 8 below)
  assert_true(ph * (1.0 - @motion.pop_in.scale) > pop_max_shift + 4.0, msg="tall: \{ph}")
  assert_eq(a1, 1.0)
  let (y0, _) = w0.unwrap()
  let first = y0 - y1
  assert_true(first > 0.0 && first <= pop_max_shift + 0.5, msg="its top row on its first frame: \{first} below")
  let (q0, h0) = p0.unwrap()
  assert_true((q0 + h0 - (py + ph)).abs() < 0.5, msg="grown from its foot: \{q0 + h0} and \{py + ph}")
  assert_true(h0 < ph && ph - h0 <= pop_max_shift + 0.5, msg="its panel \{h0} of \{ph}")
  // (back to its first frame, then in: never further off than the frame before, never past where it lands)
  open.set(false)
  t.run_for(@motion.pop_out_ms)
  assert_true(foot_menu_drawn("行 00").1 is None, msg="gone")
  open.set(true)
  t.draw()
  let mut last = pop_max_shift + 0.5
  for i in 1..=7 {
    t.run_for(@motion.pop_ms / 7.0)
    let (y, _) = foot_menu_drawn("行 00").1.unwrap()
    let off = y - y1
    assert_true(off >= -1.0e-6 && off <= last + 1.0e-6, msg="in, \{i}: \{off} after \{last}")
    last = off
  }
  assert_true(last.abs() < 1.0e-6, msg="in: where it lands (\{last})")
  // (out: drawn back toward its foot, never further off than at its first frame)
  open.set(false)
  t.draw()
  let mut last = 0.0
  for i in 1..=4 {
    t.run_for(@motion.pop_out_ms / 5.0)
    match foot_menu_drawn("行 00").1 {
      Some((y, _)) => {
        let off = y - y1
        assert_true(off >= last - 1.0e-6 && off <= pop_max_shift + 0.5, msg="out, \{i}: \{off} after \{last}")
        last = off
      }
      None => ()
    }
  }
  t.run_for(@motion.pop_out_ms / 5.0)
  assert_true(foot_menu_drawn("行 00").1 is None, msg="gone")
  assert_eq(t.audit(), [])
}

///|
test "a short menu gone above what opened it comes in at pop_in's own 0.97, within pop_max_shift as it is" {
  defer { @ui.set_glass_solid(None) }
  let open = @signals.signal(false)
  let t = foot_menu_tester(3, open)
  open.set(true)
  t.draw()
  let (p0, _) = foot_menu_drawn("行 00")
  t.run_for(@motion.pop_ms)
  let (py, ph) = foot_menu_drawn("行 00").0.unwrap()
  assert_true(py + ph < 740.0, msg="above what opened it: \{py}, \{ph}")
  assert_true(ph <= 266.0, msg="short: \{ph}")
  let (_, h0) = p0.unwrap()
  assert_true((h0 / ph - @motion.pop_in.scale).abs() < 1.0e-9, msg="as big as pop_in says: \{h0 / ph}")
  assert_eq(t.audit(), [])
}

///|
/// Liquid glass panel opacity (`I.c2.w`, slot 15) drawn now (-1.0 when no `kind == 6` glass is drawn).
fn side_menu_glass_alpha(t : @ui.Tester) -> Double {
  for inst in t.drawn_instances() {
    if inst[5] == 6.0 {
      return inst[15]
    }
  }
  -1.0
}

///|
test "liquid glass menu exit fades words and glass together across 0..pop_out_ms with no hollow glass frame" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under)
  assert_eq(side_words_alpha(t, "一"), 1.0)
  assert_eq(side_menu_glass_alpha(t), 1.0)
  t.key(@ui.key_escape)
  let mut prev_w = 1.0
  let mut prev_g = 1.0
  for step in 1..<=5 {
    t.run_for(@motion.pop_out_ms / 6.0)
    let wa = side_words_alpha(t, "一")
    let ga = side_menu_glass_alpha(t)
    assert_true(wa > 0.0 && ga > 0.0, msg="step \{step}: both visible (wa=\{wa}, ga=\{ga})")
    assert_true((wa - ga).abs() < 1.0e-3, msg="step \{step}: words and glass stay in lockstep (wa=\{wa}, ga=\{ga})")
    assert_true(wa <= prev_w + 1.0e-6 && ga <= prev_g + 1.0e-6, msg="step \{step}: monotonic")
    prev_w = wa
    prev_g = ga
  }
  t.run_for(@motion.pop_out_ms / 2.0)
  assert_eq((side_words_alpha(t, "一"), side_menu_glass_alpha(t)), (-1.0, -1.0))
}

///|
test "liquid glass menu interrupted mid-entrance reverses C0-continuously with both words and glass decreasing monotonically" {
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under)
  t.key(@ui.key_escape)
  t.run_for(@motion.pop_out_ms)
  assert_eq((side_words_alpha(t, "一"), side_menu_glass_alpha(t)), (-1.0, -1.0))
  open.set(true)
  t.draw()
  t.run_for(@motion.pop_ms / 2.0)
  let mid_w = side_words_alpha(t, "一")
  let mid_g = side_menu_glass_alpha(t)
  assert_true(mid_w > 0.0 && mid_w < 1.0 && (mid_w - mid_g).abs() < 1.0e-3, msg="mid-enter: w=\{mid_w}, g=\{mid_g}")
  t.key(@ui.key_escape)
  t.draw()
  let mut prev_w = side_words_alpha(t, "一")
  let mut prev_g = side_menu_glass_alpha(t)
  assert_true(prev_w > 0.0 && prev_w <= mid_w + 1.0e-6, msg="no upward jump on words: \{prev_w} after \{mid_w}")
  assert_true(prev_g > 0.0 && prev_g <= mid_g + 1.0e-6, msg="no upward jump on glass: \{prev_g} after \{mid_g}")
  assert_true((prev_w - prev_g).abs() < 1.0e-3, msg="sync on reverse: w=\{prev_w}, g=\{prev_g}")
  for step in 1..<=4 {
    t.run_for(@motion.pop_out_ms / 5.0)
    let wa = side_words_alpha(t, "一")
    let ga = side_menu_glass_alpha(t)
    if wa >= 0.0 {
      assert_true(wa <= prev_w + 1.0e-6 && ga <= prev_g + 1.0e-6, msg="step \{step}: monotonic")
      assert_true((wa - ga).abs() < 1.0e-3, msg="step \{step}: sync")
      prev_w = wa
      prev_g = ga
    }
  }
  t.run_for(@motion.pop_out_ms)
  assert_eq((side_words_alpha(t, "一"), side_menu_glass_alpha(t)), (-1.0, -1.0))
}

///|
test "MBUI_GLASS=solid menu keeps ground_first pop_out fallback" {
  defer { @ui.set_glass_solid(None) }
  let open = @signals.signal(false)
  let (cancels, under) = (Ref(0), Ref(0))
  let t = side_menu_tester(true, open, cancels, under, solid=true)
  assert_eq((side_words_alpha(t, "一"), side_menu_glass_alpha(t)), (1.0, -1.0))
  t.key(@ui.key_escape)
  // At 70ms under Leave + ground_first=true, words have already faded out while solid panel remains until 100ms
  t.run_for(@motion.pop_out_ms * 0.7)
  let wa = side_words_alpha(t, "一")
  assert_true(wa <= 0.0, msg="solid fallback clears words first: \{wa}")
  assert_true(t.drawn_shadows().length() > 0, msg="solid panel remains drawn before pop_out_ms")
  t.run_for(@motion.pop_out_ms * 0.5)
  assert_eq(side_words_alpha(t, "一"), -1.0)
}
