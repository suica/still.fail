// The stops as nodes (stops_node): a few levels in order on one line, the one it is at named in its thumb.

///|
/// A phone's window with the stops of `labels` in it as nodes (stops_node), at `chosen` as its caller says; what was
/// picked in it, in order.
fn stops_run(labels : Array[String], chosen : @signals.Signal[Int], state : Stops, picks : Array[Int]) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=360.0, h=200.0, platform=2)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    // (in a row, as a page's row has it: across the rest of it)
    root.box(fn(r) {
      r.row(Is(true)) |> ignore
      stops_node(r, fn() { labels }, fn() { chosen.get() }, state, said="思考深度", on_pick=fn(i) { picks.push(i) })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  t
}

///|
/// What its caller does at the window's moment, as an event: says another level, or that a pick did not take.
fn stops_told(t : @ui.Tester, f : () -> Unit) -> Unit {
  @ui.view_tree().unwrap().event(t.time(), f)
}

///|
/// Which of `labels` are drawn.
fn stops_named(t : @ui.Tester, labels : Array[String]) -> Array[String] {
  labels.filter(fn(l) { t.words().iter().any(fn(w) { w.0 == l }) })
}

///|
test "stops: every level a stop on one line, the one it is at alone named; a stop tapped is picked, said once, and stays shown while its caller still says the level before" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (@signals.signal(2), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let s = t.get(@ui.Role::Slider, label="思考深度")
  assert_eq(s.value, "高")
  assert_eq(stops_named(t, labels), ["高"])
  // (its name whole in its thumb, the thumb in its track)
  let (x, y, w, h) = s.rect
  let (nx, _, nw, _) = t.rect_of("高").unwrap()
  assert_true(nx >= x && nx + nw <= x + w, msg="\{Repr((nx, nw))} in \{Repr(s.rect)}")
  // its last stop tapped
  t.tap(x + w - w / 8.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [3])
  assert_eq(stops_named(t, labels), ["最高"])
  assert_eq(t.get(@ui.Role::Slider, label="思考深度").value, "最高")
  // (its caller's save answered before its value is told: it says the level before for a while yet)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["最高"], msg="taken back to what its caller still says")
  // said back, then another level from elsewhere: news, shown
  stops_told(t, fn() { chosen.set(3) })
  t.draw()
  stops_told(t, fn() { chosen.set(1) })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["中"])
  assert_eq(picks, [3], msg="what its caller says is not a pick")
  assert_eq(t.squeeze_faults(), [])
}

///|
test "stops: a finger takes its thumb along the track, nothing picked on the way; let go, the level under the finger is picked" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (@signals.signal(2), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  let at = fn(i : Int) { dclamp(x + w * i.to_double() / 3.0, x + 2.0, x + w - 2.0) }
  let mid = y + h / 2.0
  // down on the stop it is at, along to its first: the stop under the finger named as it goes, none picked
  t.touch(0, at(2), mid)
  t.frame()
  t.touch(1, at(1), mid)
  t.frame()
  assert_eq(picks, [])
  t.touch(1, at(0), mid)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [])
  assert_eq(stops_named(t, labels), ["低"])
  // let go there
  t.touch(2, at(0), mid)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [0])
  assert_eq(stops_named(t, labels), ["低"])
}

///|
test "stops: at none of its levels, a stop tapped stays shown while its caller still says none; its caller's reset takes it back to none" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (@signals.signal(-1), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  assert_eq(stops_named(t, labels), [])
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  t.tap(x + w * 2.5 / 4.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(picks, [2])
  // (its caller's save answered before its value is told: it says none for a while yet)
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["高"], msg="taken back to none while its save is on its way")
  // kept none of it
  stops_told(t, fn() { state.reset() })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), [])
}

///|
test "stops: a pick that did not take (its caller's reset) shows what its caller says again" {
  let labels = ["低", "中", "高", "最高"]
  let (chosen, state, picks) = (@signals.signal(1), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  t.tap(x + w - w / 8.0, y + h / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["最高"])
  stops_told(t, fn() { state.reset() })
  t.draw()
  t.run_for(@ui.move_most_ms)
  assert_eq(stops_named(t, labels), ["中"])
}

///|
test "stops: seven levels with long names on a narrow phone: still one line, the one it is at whole in its thumb" {
  let labels = ["Minimal", "Low", "Medium", "High", "Very high", "Maximum", "Ultra"]
  let (chosen, state, picks) = (@signals.signal(4), Stops::new(), [])
  let t = stops_run(labels, chosen, state, picks)
  t.resize(320.0, 200.0)
  t.draw()
  t.run_for(@ui.move_most_ms)
  let (x, _, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  assert_eq(t.lines_of("Very high"), ["Very high"])
  let (nx, _, nw, _) = t.rect_of("Very high").unwrap()
  assert_true(nx >= x && nx + nw <= x + w, msg="\{Repr((nx, nw))} in \{Repr((x, w))}")
  assert_true(h <= 44.5, msg="\{h} high: more than a line")
  assert_eq(stops_named(t, labels), ["Very high"])
  assert_eq(t.squeeze_faults(), [])
}

///|
test "stops_node: discrete keyboard switch uses critically damped spring without overshoot" {
  let labels = ["低", "中", "高", "极高"]
  let chosen = @signals.signal(0)
  let state = Stops::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=360.0, h=200.0, platform=0)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    stops_node(root, fn() { labels }, fn() { chosen.get() }, state, said="思考深度", on_pick=fn(i) { chosen.set(i) })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let thumb_x = fn() {
    let raised = theme().p.raised
    t.drawn_rects().iter().find_first(fn(r) { r.4 == raised }).map(fn(r) { r.0 }).unwrap_or(-1.0)
  }
  let x0 = thumb_x()
  // Switch from 0 -> 2 via keyboard focus + Right twice
  t.act(@ui.Role::Slider, Focus, label="思考深度")
  t.key(@ui.key_code_right)
  t.key(@ui.key_code_right)
  // Find target settled x2 first by sampling trajectory and checking monotonicity / no overshoot past settled x2
  let xs : Array[Double] = []
  let step = @ui.move_most_ms / 30.0
  for _ in 0..<30 {
    t.run_for(step)
    xs.push(thumb_x())
  }
  t.run_for(@ui.move_most_ms)
  let x2 = thumb_x()
  assert_true(x2 > x0 + 20.0, msg="moved right: x0=\{x0}, x2=\{x2}")
  for x in xs {
    assert_true(x >= x0 - 0.05 && x <= x2 + 0.05, msg="stops_node discrete switch overshot [\{x0}, \{x2}]: x=\{x}")
  }
}

///|
test "stops_node: liquid glass lens scale animation causes zero relayout (laid == 0)" {
  let labels = ["低", "中", "高", "极高"]
  let chosen = @signals.signal(1)
  let state = Stops::new()
  let t = @ui.Tester::new(fn(_c) {  }, w=360.0, h=200.0, platform=2)
  t.check_looks(false)
  @ui.set_view_app(fn(root) {
    root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
    stops_node(root, fn() { labels }, fn() { chosen.get() }, state, said="思考深度", on_pick=fn(i) { chosen.set(i) })
    |> ignore
  })
  t.draw()
  t.run_for(@ui.move_most_ms)
  let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
  let mid = y + h / 2.0
  let lens_step_ms = @ui.move_most_ms / 2.0
  t.touch(0, x + w * 1.5 / 4.0, mid)
  t.draw()
  t.tree_frames_from_now()
  t.run_for(lens_step_ms)
  let frames = t.tree_frames()
  assert_true(frames.length() > 0, msg="expected animation frames while lens scales")
  assert_true(
    frames.iter().all(fn(f) { f.laid == 0 }),
    msg="stops_node lens animation must not trigger relayout: \{Repr(frames.map(fn(f) { f.laid }))}",
  )
  t.touch(2, x + w * 1.5 / 4.0, mid)
  t.run_for(@ui.move_most_ms * 2.0)
}

///|
test "stops_node: zero hidden glass at rest, clear refraction lens while pressed, and settles back to 0 glass" {
  for dark in [false, true] {
    set_dark(Some(dark))
    @ui.set_glass_solid(None)
    let labels = ["低", "中", "高", "极高"]
    let chosen = @signals.signal(1)
    let state = Stops::new()
    let t = @ui.Tester::new(fn(_c) {  }, w=360.0, h=200.0, dark~, platform=2)
    t.check_looks(false)
    @ui.set_view_app(
      fn(root) {
        root.padding(Is((20.0, 20.0, 20.0, 20.0))) |> ignore
        stops_node(root, fn() { labels }, fn() { chosen.get() }, state, said="思考深度", on_pick=fn(i) { chosen.set(i) })
        |> ignore
      },
      theme=ui_theme_now,
    )
    t.draw()
    t.run_for(@ui.move_most_ms)
    // Rest: zero hidden glass instances.
    assert_eq(t.drawn_glass().length(), 0, msg="stops_node rest must draw 0 glass (dark=\{dark})")
    let (x, y, w, h) = t.get(@ui.Role::Slider, label="思考深度").rect
    let mid = y + h / 2.0
    t.touch(0, x + w * 1.5 / 4.0, mid)
    t.run_for(part_whole_ms)
    let pressed_glass = t.drawn_glass()
    assert_eq(pressed_glass.length(), 1, msg="stops_node held must draw 1 glass lens (dark=\{dark})")
    assert_eq(pressed_glass[0].4, 6, msg="stops_node lens must be kind == 6")
    t.touch(2, x + w * 1.5 / 4.0, mid)
    t.run_for(@ui.move_most_ms * 2.0)
    assert_eq(t.drawn_glass().length(), 0, msg="stops_node settled must return to 0 glass (dark=\{dark})")
  }
  set_dark(None)
}
