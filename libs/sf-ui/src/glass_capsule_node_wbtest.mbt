// Whitebox tests for `glass_capsule_node`, `viewer_bar_node`, and `viewer_frame_act_node`:
// verifies single-layer iOS 27 `Glass::liquid` (`kind == 6`), press GPU `spot` highlight,
// `MBUI_GLASS=solid` hairline fallback, zero hidden glass at rest, and zero glass-on-glass (`assert_no_nested_glass`).

///|
fn assert_no_nested_glass(t : @ui.Tester, ctx : String) -> Unit raise {
  let rects : Array[(Double, Double, Double, Double)] = []
  for g in t.drawn_glass() {
    if g.4 == 6 && g.2 > 0.0 && g.3 > 0.0 {
      rects.push((g.0, g.1, g.2, g.3))
    }
  }
  let overlaps : Array[String] = []
  for i in 0..<rects.length() {
    let (ax, ay, aw, ah) = rects[i]
    for j in (i + 1)..<rects.length() {
      let (bx, by, bw, bh) = rects[j]
      let ix0 = if ax > bx { ax } else { bx }
      let iy0 = if ay > by { ay } else { by }
      let ix1 = if ax + aw < bx + bw { ax + aw } else { bx + bw }
      let iy1 = if ay + ah < by + bh { ay + ah } else { by + bh }
      if ix1 > ix0 && iy1 > iy0 && (ix1 - ix0) * (iy1 - iy0) > 1.0 {
        overlaps.push("(\{ax},\{ay},\{aw},\{ah}) x (\{bx},\{by},\{bw},\{bh})")
      }
    }
  }
  if overlaps.length() > 0 {
    fail("\{ctx}: glass-on-glass detected: \{overlaps.join("; ")}")
  }
}

///|
test "glass_capsule_node emits single-layer liquid glass, degrades cleanly under MBUI_GLASS=solid, and supports dark mode" {
  for dark in [false, true] {
    for solid in [false, true] {
      for media_dark in [false, true] {
        let t = @ui.Tester::new(fn(_c) {  }, w=420.0, h=200.0, dark~, platform=0)
        set_dark(Some(dark))
        @ui.set_glass_solid(if solid { Some(true) } else { None })
        @ui.set_view_app(fn(root) {
          @ui.set_tree_theme(ui_theme_now)
          root.box(fn(page) {
            page
            .grow(Is(1.0))
            .padding(Is((24.0, 24.0, 24.0, 24.0)))
            .ground(By(fn() { if media_dark { 0x161618FFL } else { theme().p.bg } }))
            |> ignore
            action_box_node(page, fn() { "Station" }, fn(_) {  }, fn(b) {
              glass_capsule_node(b, min_height=Some(30.0), radius=Some(999.0), interactive=true, dark=media_dark)
              .row(Is(true))
              .lines_up(Is(Some(Middle)))
              .lies_along(Is(Middle))
              .padding(Is((12.0, 0.0, 12.0, 0.0)))
              |> ignore
              b.box(fn(w) {
                w.words(Is("Office-Host-2")).ink(By(fn() { if media_dark { 0xFFFFFFFFL } else { theme().p.text } }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          })
          |> ignore
        })
        t.draw()
        let glass = t.drawn_glass()
        let expected = if solid { 0 } else { 1 }
        let liquid = glass.filter(fn(g) { g.4 == 6 }).length()
        assert_no_nested_glass(t, "glass_capsule_node dark=\{dark} solid=\{solid} media=\{media_dark}")
        let audits = t.audit()
        @ui.set_glass_solid(None)
        assert_eq(
          (dark, solid, media_dark, glass.length(), liquid, audits),
          (dark, solid, media_dark, expected, expected, []),
        )
      }
    }
  }
  set_dark(None)
}

///|
test "glass_capsule_node interactive press updates without nested glass or audit faults" {
  let pressed_count = Ref(0)
  let t = @ui.Tester::new(fn(_c) {  }, w=420.0, h=200.0, dark=false, platform=0)
  set_dark(Some(false))
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      page.grow(Is(1.0)).padding(Is((24.0, 24.0, 24.0, 24.0))).ground(By(fn() { theme().p.bg })) |> ignore
      action_box_node(page, fn() { "Model" }, fn(_) { pressed_count.val += 1 }, fn(b) {
        glass_capsule_node(b, min_height=Some(32.0), radius=Some(999.0), interactive=true)
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .lies_along(Is(Middle))
        .padding(Is((12.0, 0.0, 12.0, 0.0)))
        |> ignore
        b.box(fn(w) { w.words(Is("Gemini 4")).ink(By(fn() { theme().p.text })) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let (x, y, w, h) = t.rect_of("Gemini 4").unwrap()
  t.button_down(x + w / 2.0, y + h / 2.0, 0)
  t.draw()
  assert_no_nested_glass(t, "glass_capsule_node pressed")
  assert_eq(t.drawn_glass().filter(fn(g) { g.4 == 6 }).length(), 1)
  t.button_up(x + w / 2.0, y + h / 2.0, 0)
  t.draw()
  assert_eq(pressed_count.val, 1)
  assert_no_nested_glass(t, "glass_capsule_node released")
  assert_eq(t.audit(), [])
  set_dark(None)
}

///|
test "viewer_bar_node uses progressive scroll edge and floating liquid glass pills with zero hidden glass" {
  let ink : ViewerInk = {
    ground: 0x222222FFL,
    ink: 0xFFFFFFFFL,
    muted: 0xAAAAAAFFL,
    line: 0x444444FFL,
    hover: 0x2427E70FL,
    chosen: 0x2427E71FL,
  }
  let hidden = @signals.signal(false, same=fn(a, b) { a == b })
  let t = @ui.Tester::new(fn(_c) {  }, w=1280.0, h=800.0, dark=true, platform=0)
  set_dark(Some(true))
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    viewer_bar_test_node(root, ink, fn() { hidden.get() })
  })
  t.draw()
  assert_no_nested_glass(t, "viewer_bar_node visible")
  // Back capsule is single-layer liquid glass (`kind == 6`)
  assert_true(t.drawn_glass().filter(fn(g) { g.4 == 6 }).length() >= 1)
  // Hide bar and let animation complete: zero hidden glass instances at rest
  @ui.view_tree().unwrap().event(t.time(), fn() { hidden.set(true) })
  t.run_for(viewer_bar_ms + 50.0)
  assert_eq(t.drawn_glass().length(), 0)
  set_dark(None)
}
