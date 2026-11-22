// A tip's keys, each a cap of its own (key_caps, tip_cap_node), the tip 4 in from them and concentric with them, as
// tall as a tip of words alone; in the dark on a lifted ground with a faint line, not the light primary ink. What
// floats over a card in the dark (panel_ground, panel_edge, float_shadow_ink) stands off it by its ground and a tight
// shadow, its line the theme's.

///|
test "key caps: an Apple keyboard's marks one a cap each, the key after them one; elsewhere parts between +" {
  assert_eq(key_caps("⌘⇧F"), ["⌘", "⇧", "F"])
  assert_eq(key_caps("⌘K"), ["⌘", "K"])
  assert_eq(key_caps("⌘["), ["⌘", "["])
  assert_eq(key_caps("⌃⌥⇧⌘↑"), ["⌃", "⌥", "⇧", "⌘", "↑"])
  assert_eq(key_caps("⌘ Enter"), ["⌘", "Enter"])
  assert_eq(key_caps("⌘+"), ["⌘", "+"])
  assert_eq(key_caps("Ctrl+Shift+F"), ["Ctrl", "Shift", "F"])
  assert_eq(key_caps("Alt+Up"), ["Alt", "Up"])
  assert_eq(key_caps("Ctrl++"), ["Ctrl", "+"])
  assert_eq(key_caps("Ctrl+Shift++"), ["Ctrl", "Shift", "+"])
  assert_eq(key_caps("+"), ["+"])
  assert_eq(key_caps("Esc"), ["Esc"])
  assert_eq(key_caps(""), [])
  assert_eq(key_caps("  "), [])
}

///|
/// A colour's lightness, roughly (its channels' mean, 0 to 255).
fn caps_light_of(c : Int64) -> Double {
  (((c >> 24) & 0xFF).to_double() + ((c >> 16) & 0xFF).to_double() + ((c >> 8) & 0xFF).to_double()) / 3.0
}

///|
test "what floats: its line the theme's; in the dark the raised grey with a tight shadow, a tip lifted over it" {
  let _ = @ui.Tester::new(fn(_c) {  }, w=200.0, h=160.0, platform=0)
  set_dark(Some(false))
  assert_eq(panel_ground(), theme().p.canvas)
  assert_eq(panel_edge(), theme().p.line)
  assert_eq(float_shadow(), (12.0, 8.0, theme().p.shadow))
  assert_eq(tip_ground(), theme().p.primary)
  assert_eq(tip_edge(), (0.0, 0L))
  set_dark(Some(true))
  let p = theme().p
  let ground = panel_ground()
  assert_eq(ground, p.raised)
  // (its line: the theme's, no lit rim; more contrast asked, the theme's more seen one)
  assert_eq(panel_edge(), p.line)
  assert_eq(float_shadow(), (8.0, 6.0, alpha(0x000000FFL, 0.34)))
  assert_eq(float_shadow_ink(), alpha(0x000000FFL, 0.34))
  // (a tip's line: fainter than what floats has)
  assert_eq(tip_edge(), (1.0, alpha(p.text, 0.09)))
  // (a tip: not the light primary ink, a step over what floats)
  assert_true(tip_ground() != p.primary, msg="a tip on the primary ink in the dark")
  assert_true(caps_light_of(tip_ground()) > caps_light_of(ground), msg="a tip \{tip_ground()} under a menu \{ground}")
  assert_eq(tip_words(), p.text)
  set_dark(Some(false))
}

///|
/// A window with two buttons side by side, each with a tip, the first's of keys `keys` (an action's, said by
/// set_shortcuts), dark or light; the pointer resting on the first.
fn caps_tester(dark : Bool, keys : String, solid? : Bool = false) -> @ui.Tester raise {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=240.0, platform=0)
  t.check_looks(false)
  set_dark(Some(dark))
  @ui.set_glass_solid(if solid { Some(true) } else { None })
  @ui.set_tree_theme(ui_theme_now)
  set_shortcuts(fn(a) { if a == "find" { keys } else { "" } })
  @ui.set_view_app(fn(root) {
    let layer : Ref[@view.View?] = Ref(None)
    let tips = TipLayer::new(fn() { layer.val })
    root.box(fn(row) {
      row.row(Is(true)).pad(Is(60.0)).gap(Is(8.0)) |> ignore
      row.box(fn(k) {
        k.width(Is(Some(34.0))).height(Is(Some(34.0))).says(Is(Some(@view.said(Button, label="查找")))) |> ignore
        tip_node(tips, k, fn() { "在对话里查找" }, shortcut="find") |> ignore
      })
      |> ignore
      row.box(fn(k) {
        k.width(Is(Some(34.0))).height(Is(Some(34.0))).says(Is(Some(@view.said(Button, label="新对话")))) |> ignore
        tip_node(tips, k, fn() { "新对话" }) |> ignore
      })
      |> ignore
    })
    |> ignore
    layer.val = Some(root.box(fn(l) { l.over(Is(true)) |> ignore }))
  })
  t.draw()
  let k = t.get(Button, label="查找")
  t.move_to(k.rect.0 + 17.0, k.rect.1 + 17.0)
  t.run_for(tip_delay_ms + tip_settled_ms)
  t
}

///|
/// The tip's glass surface (single-layer liquid glass, wider than tall; or solid panel_ground fallback under
/// MBUI_GLASS=solid) and its caps', as (x, y, w, h).
fn caps_drawn(t : @ui.Tester) -> ((Double, Double, Double, Double)?, Array[(Double, Double, Double, Double)]) {
  let glass = t.drawn_glass().filter(fn(g) { g.4 == 6 && g.2 > g.3 })
  let tip = match glass.get(0) {
    Some(g) => Some((g.0, g.1, g.2, g.3))
    None =>
      t.drawn_rects()
      .filter(fn(r) { r.4 == panel_ground() && r.2 > r.3 })
      .get(0)
      .map(fn(r) { (r.0, r.1, r.2, r.3) })
  }
  let cap = mix(library_theme().p.text, tip_cap_ground, panel_ground())
  let caps = t.drawn_rects().filter(fn(r) { r.4 == cap }).map(fn(r) { (r.0, r.1, r.2, r.3) })
  (tip, caps)
}

///|
test "a tip's keys each a cap at its end, 4 in from its top, foot and end, concentric with its corners, its words 10 from its start, as tall as a tip of words" {
  assert_eq(tip_round, small_corner)
  assert_eq(tip_cap_round, @ui.concentric(tip_round, tip_key_in))
  for dark in [false, true] {
    let words_alone = {
      let t = caps_tester(dark, "")
      guard caps_drawn(t).0 is Some((_, _, _, h)) else { fail("dark \{dark}: no tip of words alone") }
      t.move_to(300.0, 220.0)
      t.run_for(@motion.pop_out_ms * 2.0)
      h
    }
    let t = caps_tester(dark, "⌘⇧F")
    let (tip, caps) = caps_drawn(t)
    guard tip is Some((tx, ty, tw, th)) else { fail("dark \{dark}: no tip drawn: \{Repr(t.drawn_rects())}") }
    assert_eq(caps.length(), 3)
    for c in caps {
      assert_eq(c.3, th - 2.0 * tip_key_in)
      assert_true(c.2 >= c.3, msg="a cap narrower than high: \{Repr(c)}")
      assert_eq(c.1 - ty, tip_key_in)
      assert_eq(ty + th - (c.1 + c.3), tip_key_in)
    }
    let last = caps[caps.length() - 1]
    assert_eq(tx + tw - (last.0 + last.2), tip_key_in)
    assert_eq(last.1 - ty, tip_key_in)
    assert_eq(th, words_alone)
    let faults = t.audit()
    assert_true(faults.is_empty(), msg="dark \{dark}: \{Repr(faults)}")
    t.move_to(300.0, 220.0)
    t.run_for(@motion.pop_out_ms * 2.0)
  }
  set_dark(Some(false))
}

///|
test "a tip with no keys: no caps; Ctrl's keys split by +, every rule kept in the dark" {
  let t = caps_tester(false, "")
  let (tip, caps) = caps_drawn(t)
  assert_true(tip is Some(_), msg="no tip drawn")
  assert_eq(caps.length(), 0)
  let t = caps_tester(true, "Ctrl+Shift++")
  let (_, caps) = caps_drawn(t)
  assert_eq(caps.length(), 3)
  assert_true(t.audit().is_empty(), msg="\{Repr(t.audit())}")
  set_dark(Some(false))
}

///|
test "the pointer moved to the next button: its tip comes at once from where the first was, no caps left on it" {
  let t = caps_tester(true, "⌘⇧F")
  let k = t.get(Button, label="新对话")
  t.move_to(k.rect.0 + 17.0, k.rect.1 + 17.0)
  t.run_for(@motion.pop_out_ms + tip_settled_ms)
  let tips = t.semantics().filter(fn(s) { s.role == Tooltip }).map(fn(s) { s.label })
  assert_eq(tips, ["新对话"])
  let (tip, caps) = caps_drawn(t)
  assert_true(tip is Some(_), msg="no tip drawn")
  assert_eq(caps.length(), 0)
  set_dark(Some(false))
}

///|
test "tip_node: single-layer liquid glass when shown, zero hidden glass when dismissed, solid degradation, and contrast pass" {
  for dark in [false, true] {
    for solid in [false, true] {
      let t = caps_tester(dark, "⌘K", solid~)
      let shown_glass = t.drawn_glass()
      let expected_glass = if solid { 0 } else { 1 }
      let liquid_count = shown_glass.filter(fn(g) { g.4 == 6 }).length()
      let contrast = t.contrast_faults()
      assert_eq(
        (dark, solid, shown_glass.length(), liquid_count, contrast),
        (dark, solid, expected_glass, expected_glass, []),
      )
      // Move pointer away and settle: zero hidden glass instances left behind
      t.move_to(350.0, 220.0)
      t.run_for(@motion.pop_out_ms * 2.0)
      assert_eq(t.drawn_glass().length(), 0, msg="dark=\{dark} solid=\{solid} hidden tip emitted glass")
    }
  }
  @ui.set_glass_solid(None)
  set_dark(None)
}
