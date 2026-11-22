// Tests for `bar_pill_group_node`: single-layer iOS 26 / macOS 26 liquid glass (`kind == 6`, zero nested glass),
// tight outside-only `glass_control_shadow()` (`shadow_outside == true`), exact concentric corners for both 34pt `round_key_node`
// (`height=40, pad=3`) and 32pt `icon_button_node` (`height=36, pad=2`), 40pt standalone circle (`height=40, pad=0`),
// `MBUI_GLASS=solid` degradation (`panel_ground()` + `control_edge_w` `panel_edge()`, 0 glass instances), and clean
// `Tester::audit()` in both Light and Dark themes.

///|
fn has_pill_solid_edge(t : @ui.Tester, edge_color : Int64) -> Bool {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  t.drawn_instances().iter().any(fn(a) {
    if a.length() > 15 && a[5] == 0.0 && (a[6] - control_edge_w).abs() < 0.01 {
      let c = (ch(a[12]) << 24) | (ch(a[13]) << 16) | (ch(a[14]) << 8) | ch(a[15])
      c == edge_color
    } else {
      false
    }
  })
}

///|
fn pill_group_tester(kind : String, dark : Bool, solid : Bool) -> @ui.Tester {
  presenters_reset()
  set_words(fn(key, _) { key })
  let platform = if kind == "wide" { 0 } else { 2 }
  let t = @ui.Tester::new(fn(_c) {  }, w=420.0, h=160.0, dark~, platform~)
  set_dark(Some(dark))
  if solid {
    @ui.set_glass_solid(Some(true))
  } else {
    @ui.set_glass_solid(None)
  }
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(bar) {
      bar
      .row(Is(true))
      .grow(Is(1.0))
      .padding(Is((24.0, 24.0, 24.0, 24.0)))
      .lines_up(Is(Some(Middle)))
      .ground(By(fn() { theme().p.bg }))
      |> ignore
      if kind == "narrow" {
        bar_pill_group_node(bar, height=40.0, pad=3.0, gap=2.0, fn(g) {
          round_key_node(g, "bell", fn() { "Attention" }, fn() {  })
          round_key_node(g, "filter", fn() { "Filter" }, fn() {  }, icon_size=20.0)
        })
        |> ignore
      } else if kind == "back" {
        bar_pill_group_node(bar, height=40.0, pad=0.0, gap=0.0, fn(g) {
          round_key_node(g, "chevron-left", fn() { "Back" }, fn() {  }, side=40.0, icon_size=22.0)
        })
        |> ignore
      } else {
        bar_pill_group_node(bar, height=36.0, pad=2.0, gap=2.0, fn(g) {
          icon_button_node(g, "info", fn() { "Info" }, fn() {  }) |> ignore
          icon_button_node(g, "more", fn() { "More" }, fn() {  }) |> ignore
        })
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "bar_pill_group_node renders single-layer liquid glass with shadow_outside, zero corner faults, and clean solid fallback in light and dark" {
  for kind in ["narrow", "back", "wide"] {
    for dark in [false, true] {
      let t = pill_group_tester(kind, dark, false)
      let glass = t.drawn_glass()
      let liquid_count = glass.filter(fn(g) { g.4 == 6 }).length()
      let shadows = outside_shadows(t)
      let expected_shadow = glass_control_shadow()
      let corners = t.corner_faults()
      let audits = t.audit()
      assert_eq(
        (kind, dark, glass.length(), liquid_count, shadows, corners, audits),
        (kind, dark, 1, 1, [expected_shadow], [], []),
      )

      let ts = pill_group_tester(kind, dark, true)
      let solid_glass = ts.drawn_glass().length()
      let expected_solid = panel_ground()
      let has_ground = ts.drawn_rects().iter().any(fn(r) { r.4 == expected_solid })
      let has_edge = has_pill_solid_edge(ts, panel_edge())
      let solid_corners = ts.corner_faults()
      let solid_audits = ts.audit()
      @ui.set_glass_solid(None)
      assert_eq(
        (kind, dark, solid_glass, has_ground, has_edge, solid_corners, solid_audits),
        (kind, dark, 0, true, true, [], []),
      )
    }
  }
}

///|
test "bar_pill_group_node interactive press drives GPU spot highlight, spring scale, theme-adaptive ink, and settles cleanly" {
  for dark in [false, true] {
    presenters_reset()
    set_words(fn(key, _) { key })
    let t = @ui.Tester::new(fn(_c) {  }, w=420.0, h=160.0, dark~, platform=2)
    set_dark(Some(dark))
    @ui.set_glass_solid(None)
    let pill_ref : Ref[@view.View?] = Ref(None)
    let key_ref : Ref[@view.View?] = Ref(None)
    let ws_ref : Ref[@view.View?] = Ref(None)
    @ui.set_view_app(fn(root) {
      @ui.set_tree_theme(ui_theme_now)
      root.box(fn(bar) {
        bar
        .row(Is(true))
        .grow(Is(1.0))
        .padding(Is((24.0, 24.0, 24.0, 24.0)))
        .lines_up(Is(Some(Middle)))
        .ground(By(fn() { theme().p.bg }))
        |> ignore
        let g = bar_pill_group_node(bar, height=40.0, pad=3.0, gap=2.0, fn(g) {
          g.box(fn(k) {
            key_ref.val = Some(k)
            round_key_node(k, "bell", fn() { "Attention" }, fn() {  })
          })
          |> ignore
          action_box_node(g, fn() { "Workspace" }, fn(_) {  }, fn(s) {
            ws_ref.val = Some(s)
            s
            .row(Is(true))
            .height(Is(Some(34.0)))
            .radius(Is(17.0))
            .padding(Is((8.0, 0.0, 8.0, 0.0)))
            .lines_up(Is(Some(Middle)))
            |> ignore
            bar_pill_key_press_node(s)
            words_node(s, fn() { "AFK AI" }, fn() { @ui.text_style(size=Ui, color=Fg) }) |> ignore
          })
          |> ignore
        })
        pill_ref.val = Some(g)
      })
      |> ignore
    })
    t.draw()
    // Dark mode press ink must be bright (non-black) so ripples/overlays are clearly visible over dark glass.
    let ink = bar_pill_press_ink()
    let rgb = (ink >> 8) & 0xFFFFFFL
    if dark {
      assert_true(rgb > 0x808080L, msg="dark press ink rgb should be bright, got \{ink}")
    } else {
      assert_true(rgb < 0x808080L, msg="light press ink rgb should be dark, got \{ink}")
    }
    let pill = pill_ref.val.unwrap()
    let has_spot = fn() {
      t.drawn_instances().iter().any(fn(a) { a.length() > 14 && a[5] == 6.0 && a[14] > 0.0 })
    }
    assert_eq(has_spot(), false)
    assert_true((pill.drawn_scale() - 1.0).abs() < 0.001)
    for target in [key_ref.val.unwrap(), ws_ref.val.unwrap()] {
      let (tx, ty, tw, th) = target.placed_window_now()
      let (cx, cy) = (tx + tw / 2.0, ty + th / 2.0)
      t.press_at(cx, cy)
      t.run_for(part_whole_ms)
      assert_true(has_spot(), msg="spot must be active while pressed (dark=\{dark})")
      assert_true(pill.drawn_scale() > 1.01, msg="pill must spring-scale > 1.01 while pressed, got \{pill.drawn_scale()}")
      t.release(cx, cy)
      t.run_for(@ui.move_most_ms)
      assert_eq(has_spot(), false)
      assert_true((pill.drawn_scale() - 1.0).abs() < 0.002, msg="pill must settle back to 1.0, got \{pill.drawn_scale()}")
    }
    t.assert_idle()
  }
}

///|
/// The window's own buttons (window_keys_node) alone in a Windows window `w` wide, its corner `corner` round, `whole`
/// as a window of its own's: the tester and their pill.
fn window_keys_tester(
  w : Double,
  corner : Double,
  whole : Bool,
  dark : Bool,
  solid : Bool,
) -> (@ui.Tester, Ref[@view.View?]) {
  presenters_reset()
  set_words(fn(key, _) { key })
  let t = @ui.Tester::new(fn(_c) {  }, w~, h=700.0, dark~, platform=3, window_corner=corner, window_inset=true)
  set_dark(Some(dark))
  @ui.set_glass_solid(if solid { Some(true) } else { None })
  let pill : Ref[@view.View?] = Ref(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) { page.grow(Is(1.0)).ground(By(fn() { theme().p.bg })) |> ignore }) |> ignore
    window_keys_made(root, fn() { whole }, fn(p) { pill.val = Some(p) })
  })
  t.draw()
  (t, pill)
}

///|
/// The window's own buttons by their words (set_words' keys): where each is.
fn window_key_rect(t : @ui.Tester, label : String) -> (Double, Double, Double, Double) raise {
  match t.semantics().filter(fn(s) { !s.hidden && s.label == label && s.role is Button }) {
    [s] => s.rect
    all => fail("\{all.length()} buttons named \{label}")
  }
}

///|
/// The tint's colour (RRGGBB, its opacity aside) of the liquid glass 104 by 36 drawn in the last frame.
fn window_pill_tint_rgb(t : @ui.Tester) -> Int64? {
  let ch = fn(v : Double) { (v * 255.0).round().to_int64() }
  for a in t.drawn_instances() {
    if a.length() > 11 && a[5] == 6.0 && (a[2] - 104.0).abs() < 0.01 && (a[3] - 36.0).abs() < 0.01 {
      return Some((ch(a[8]) << 16) | (ch(a[9]) << 8) | ch(a[10]))
    }
  }
  None
}

///|
/// The windows the buttons are tried in: (name, width, whole).
let window_keys_shapes : Array[(String, Double, Bool)] = [
  ("large", 1280.0, false),
  ("medium", 800.0, false),
  ("small", 390.0, false),
  ("whole", 600.0, true),
]

///|
test "window_keys_node: one 104x36 liquid glass pill, its outside shadow, no rule, concentric 32 buttons, in every layout and window corner, light and dark, and solid" {
  for shape in window_keys_shapes {
    let (name, w, whole) = shape
    for corner in [0.0, 8.0, 12.0, 16.0] {
      for dark in [false, true] {
        let at = "\{name} corner=\{corner} dark=\{dark}"
        let (t, _) = window_keys_tester(w, corner, whole, dark, false)
        let (top, side) = window_keys_at_roots(w, whole, @ui.tree_corner_roots_now())
        let glass = t.drawn_glass()
        assert_eq(glass.length(), 1, msg="\{at}: glass \{Repr(glass)}")
        let (gx, gy, gw, gh, kind, _) = glass[0]
        assert_eq((kind, gw, gh), (6, 104.0, 36.0), msg="\{at}")
        assert_true((gx + gw - (w - side)).abs() < 1.0e-6 && (gy - top).abs() < 1.0e-6, msg="\{at}: pill at \{gx},\{gy}")
        // (Large and a window of its own's: past the window's corner, 12 where that is past it; the buttons on the
        // bars' line, 6 under the top. Small: in the middle of the 44 band. Medium: the buttons on the tape's line)
        let expect_top = if name == "medium" { window_in + tape_line - 2.0 } else { 4.0 }
        assert_eq(top, expect_top, msg="\{at}")
        if name != "medium" {
          let expect_side = if corner > 0.0 && 12.0 < corner + corner_fit.near { corner + 12.0 } else { 12.0 }
          assert_eq(side, expect_side, msg="\{at}")
        }
        // (the buttons 2 in from the pill's edges and 2 apart, 32 round, concentric with its 36)
        let (cx, cy, cw, ch) = window_key_rect(t, "desktop.menu.close")
        let (zx, _, _, _) = window_key_rect(t, "desktop.window.maximize")
        let (mx, _, _, _) = window_key_rect(t, "desktop.menu.minimize")
        assert_eq((cx + cw, cy, cw, ch, zx, mx), (gx + gw - 2.0, gy + 2.0, 32.0, 32.0, cx - 34.0, cx - 68.0), msg="\{at}")
        assert_eq(mx - 2.0, gx, msg="\{at}")
        assert_eq(t.window_snap_rect(), (zx, cy, 32.0, 32.0), msg="\{at}")
        assert_eq(outside_shadows(t), [glass_control_shadow()], msg="\{at}")
        // (their glass the window's own tint, told apart from the neutral pills of the bar beside it)
        let tint = window_keys_glass_tint()
        let neutral = if dark { 0x20202067L } else { 0xFDFCFD67L }
        assert_eq(window_pill_tint_rgb(t), Some(tint >> 8), msg="\{at}")
        assert_true(tint >> 8 != neutral >> 8, msg="\{at}")
        let rule = t.drawn_rects().filter(fn(r) { r.2 <= 1.5 && r.3 >= 10.0 && r.1 < 50.0 })
        assert_eq(rule.length(), 0, msg="\{at}: a rule \{Repr(rule)}")
        assert_eq((t.corner_faults(), t.audit()), ([], []), msg="\{at}")
        // MBUI_GLASS=solid: the panel's ground and hairline edge, no glass
        let (ts, _) = window_keys_tester(w, corner, whole, dark, true)
        let solid_glass = ts.drawn_glass().length()
        let ground = over(panel_ground(), alpha(window_keys_glass_tint(), 0.24))
        let has_ground = ts.drawn_rects().iter().any(fn(r) { r.4 == ground && r.2 == 104.0 && r.3 == 36.0 })
        let has_edge = has_pill_solid_edge(ts, panel_edge())
        let solid_faults = (ts.corner_faults(), ts.audit())
        @ui.set_glass_solid(None)
        assert_eq((solid_glass, has_ground, has_edge, solid_faults), (0, true, true, ([], [])), msg="\{at} solid")
      }
    }
  }
  set_dark(None)
}

///|
test "window_keys_node: pressing minimize, maximize or close, or the host holding maximize down, lights the pill's spot and springs it, settling back" {
  for shape in window_keys_shapes {
    let (name, w, whole) = shape
    for dark in [false, true] {
      let at = "\{name} dark=\{dark}"
      let (t, pill_ref) = window_keys_tester(w, 8.0, whole, dark, false)
      let pill = pill_ref.val.unwrap()
      let scope = pill.lent(pill_press_lent).unwrap()
      assert_eq(scope.fx.untracked().0, None)
      for label in ["desktop.menu.minimize", "desktop.window.maximize", "desktop.menu.close"] {
        let (x, y, kw, kh) = window_key_rect(t, label)
        let (cx, cy) = (x + kw / 2.0, y + kh / 2.0)
        t.press_at(cx, cy)
        t.run_for(part_whole_ms)
        assert_true(scope.fx.untracked().0 is Some(_), msg="\{at} \{label}: no spot pressed")
        assert_true(pill.drawn_scale() > 1.01, msg="\{at} \{label}: pill at \{pill.drawn_scale()} pressed")
        t.release(cx, cy)
        t.run_for(@ui.move_most_ms)
        assert_eq(scope.fx.untracked().0, None, msg="\{at} \{label}")
        assert_true((pill.drawn_scale() - 1.0).abs() < 0.002, msg="\{at} \{label}: pill at \{pill.drawn_scale()} let go")
      }
      assert_eq(t.window_acts(), [1, 2, 3], msg="\{at}")
      // (maximize held down by the pointer as the host says: its press the host's, the pill's all the same)
      t.set_window_snap(1)
      t.run_for(dur_ms)
      assert_eq(scope.fx.untracked().0, None, msg="\{at}: lit is no press")
      t.set_window_snap(2)
      t.run_for(part_whole_ms)
      assert_true(scope.fx.untracked().0 is Some(_), msg="\{at}: no spot as the host holds maximize")
      assert_true(pill.drawn_scale() > 1.01, msg="\{at}: pill at \{pill.drawn_scale()} as the host holds maximize")
      t.set_window_snap(0)
      t.run_for(@ui.move_most_ms)
      assert_eq(scope.fx.untracked().0, None, msg="\{at}")
      assert_true((pill.drawn_scale() - 1.0).abs() < 0.002, msg="\{at}: pill at \{pill.drawn_scale()} let go by the host")
      t.assert_idle()
    }
  }
  set_dark(None)
}
