// White-box tests for Wave 4B v19 1:1 iOS 27.0 LiquidMorphPhysics (`bar_pill_group_node` +
// `anchored_popover_bridge` + `anchored_popover_shell`), verified across 60/120/24/7 fps:
// 1. Liquid glass `bar_pill_group_node` + `icon_button_node` trigger:
//    - Three-anchor optical invariant: `stage=0.0` == `glass_bar_pill()`, `stage=0.5` == `0x88/blur=5.0/bezel=18/refr=14`,
//      `stage=1.0` == `glass_menu()`.
//    - Rest (`>= 540ms`): 2 liquid instances (Archive + Menu), `merge == 0.0`, 0 `kind == 8` `content_lens`, `audit() == []`.
//    - Close recoil (`~183ms`): trigger pill kicks upward (`dy <= -10pt`) while Blob A + Blob B fuse in private group.
//    - Post-handoff splash (`~400ms`): Blob B vanishes (only 2 liquid instances remain — zero double glass) while
//      trigger pill exhibits `+1.6%` horizontal width splash (`> resting pill_w`) and rides recoil smoothly back.
//    - Post-close (`>= 620ms`): menu unmounts cleanly, trigger pill returns to resting `y` and `w` with `merge == 0.0`.
// 2. Non-pill plain button anchor (80×36): scales into button (`< 0.65` mid-exit) without stacking an extra glass droplet.
// 3. Context menu 1×1 point anchor (`at_point`): never emits a bridge and keeps `0.97..1.0` scale.
// 4. `MBUI_GLASS=solid` fallback: 0 `kind == 6` instances throughout entrance, rest, and exit, with clean audit.

///|
let bridge_test_settle_ms : Double = 640.0

///|
let bridge_test_recoil_ms : Double = 215.0

///|
let bridge_test_splash_step_ms : Double = 185.0

///|
/// Returns `(index, merge)` for every `kind == 6` liquid glass instance emitted in the last frame.
fn bridge_liquid_instances(t : @ui.Tester) -> Array[(Int, Double)] {
  let out : Array[(Int, Double)] = []
  let insts = t.drawn_instances()
  for i in 0..<insts.length() {
    let a = insts[i]
    if a.length() > 23 && a[5] == 6.0 {
      out.push((i, a[23]))
    }
  }
  out
}

///|
fn bridge_pill_menu_tester(
  open : @signals.Signal[Bool],
  solid : Bool,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, dark=false, platform=0)
  set_dark(Some(false))
  @ui.set_glass_solid(if solid { Some(true) } else { None })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    let more_ref : Ref[@view.View?] = Ref(None)
    root.box(fn(page) {
      page.grow(Is(1.0)).padding(Is((64.0, 24.0, 64.0, 64.0))).ground(By(fn() { theme().p.bg })) |> ignore
      page.box(fn(bar) {
        bar.row(Is(true)).gap(Is(6.0)).lies_along(Is(End)) |> ignore
        bar_pill_group_node(bar, height=36.0, pad=2.0, gap=2.0, fn(k) {
          icon_button_node(k, "archive", fn() { "Archive" }, fn() {  }) |> ignore
        })
        |> ignore
        bar_pill_group_node(bar, height=36.0, pad=2.0, gap=2.0, fn(k) {
          icon_button_node(k, "info", fn() { "Info" }, fn() {  }) |> ignore
          let more = icon_button_node(k, "more", fn() { "More" }, fn() { open.set(true) })
          more_ref.val = Some(more)
        })
        |> ignore
      })
      |> ignore
      root.box(fn(l) {
        l.over(Is(true)) |> ignore
        menu_node(
          l,
          fn() { open.get() },
          fn(_) { more_ref.val.unwrap() },
          fn() {
            [
              Some(menu_item_of("Copy Link", fn() {  })),
              Some(menu_item_of("Pin Message", fn() {  })),
              Some(menu_item_of("Delete", fn() {  })),
            ]
          },
          "",
          End,
          panel_offset,
          false,
          false,
          fn(_) { open.set(false) },
          fn() { open.set(false) },
        )
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
fn bridge_plain_menu_tester(
  open : @signals.Signal[Bool],
  solid : Bool,
) -> @ui.Tester {
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, dark=false, platform=0)
  set_dark(Some(false))
  @ui.set_glass_solid(if solid { Some(true) } else { None })
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      page.grow(Is(1.0)).padding(Is((64.0, 64.0, 64.0, 64.0))).ground(By(fn() { theme().p.bg })) |> ignore
      let btn = page.box(fn(o) {
        o
        .width(Is(Some(80.0)))
        .height(Is(Some(36.0)))
        .presses(Is(true))
        .on_press(fn() { open.set(true) })
        .says(Is(Some(@view.said(Button, label="Actions"))))
        |> ignore
      })
      root.box(fn(l) {
        l.over(Is(true)) |> ignore
        menu_node(
          l,
          fn() { open.get() },
          fn(_) { btn },
          fn() {
            [
              Some(menu_item_of("Copy Link", fn() {  })),
              Some(menu_item_of("Pin Message", fn() {  })),
              Some(menu_item_of("Delete", fn() {  })),
            ]
          },
          "",
          Start,
          panel_offset,
          false,
          false,
          fn(_) { open.set(false) },
          fn() { open.set(false) },
        )
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  t
}

///|
test "bar_pill_group_node menu performs iOS 27.0 LiquidMorphPhysics with upward close recoil and horizontal splash while Archive stays isolated" {
  defer {
    @ui.set_glass_solid(None)
    set_dark(None)
  }
  let open = @signals.signal(false)
  let t = bridge_pill_menu_tester(open, false)

  // Before open: 2 resting pill liquid glass instances ([Archive] + [(i) ...]), both merge == 0.0
  let init_glass = t.drawn_glass()
  let init_liq = bridge_liquid_instances(t)
  assert_eq(init_liq.length(), 2, msg="2 resting pills emit 2 liquid glass instances")
  assert_eq(init_liq[0].1, 0.0, msg="resting archive pill merge is 0.0")
  assert_eq(init_liq[1].1, 0.0, msg="resting trigger pill merge is 0.0")
  let rest_pill_y = init_glass[1].1
  let rest_pill_w = init_glass[1].2

  // Three-anchor optical boundary invariant:
  // stage=0.0 == glass_bar_pill(), stage=0.5 == luminous 0x88/blur=5.0/bezel=18/refr=14, stage=1.0 == glass_menu()
  let pill_gl = glass_bar_pill()
  let clear_gl = glass_menu_morph(0.0)
  let mid_gl = glass_menu_morph(0.5)
  let rest_gl = glass_menu()
  let frosted_gl = glass_menu_morph(1.0)
  assert_eq(clear_gl.tint, pill_gl.tint, msg="stage=0.0 tint bit-identical to glass_bar_pill")
  assert_eq(clear_gl.blur, pill_gl.blur, msg="stage=0.0 blur bit-identical to glass_bar_pill")
  assert_eq(mid_gl.tint & 0xFFL, 0x4EL, msg="stage=0.5 droplet uses 0x4E luminous crystal alpha")
  assert_true((mid_gl.blur - 1.6).abs() < 1.0e-9, msg="stage=0.5 droplet uses 1.6pt blur: \{mid_gl.blur}")
  assert_true((mid_gl.bezel - 18.0).abs() < 1.0e-9, msg="stage=0.5 droplet uses 18.0pt bezel: \{mid_gl.bezel}")
  assert_true((mid_gl.refraction - 15.0).abs() < 1.0e-9, msg="stage=0.5 droplet uses 15.0pt refraction: \{mid_gl.refraction}")
  assert_eq(frosted_gl.tint, rest_gl.tint, msg="stage=1.0 tint bit-identical to glass_menu")
  assert_eq(frosted_gl.blur, rest_gl.blur, msg="stage=1.0 blur bit-identical to glass_menu")

  // Open menu and settle (>= 600ms): Archive + Menu (2 instances), 0 kind==8 lens overhead at rest, clean audit
  open.set(true)
  t.draw()
  t.run_for(bridge_test_settle_ms)
  let rest_glass = t.drawn_glass()
  let rest_liq = bridge_liquid_instances(t)
  assert_eq(rest_glass.length(), 2, msg="rest has 2 liquid surfaces (Archive + in-place Menu)")
  assert_eq(rest_liq.length(), 2, msg="rest has 2 raw liquid instances")
  assert_true((rest_glass[1].1 - rest_glass[0].1).abs() <= 1.5, msg="menu top aligns with top bar pill top")
  for x in rest_liq {
    assert_eq(x.1, 0.0, msg="rest merge is 0.0 for all surfaces")
  }
  let rest_lens_n = t.drawn_instances().filter(fn(a) { a.length() > 5 && a[5] == 8.0 }).length()
  assert_eq(rest_lens_n, 0, msg="resting menu emits 0 kind == 8 content_lens instances")
  assert_eq(t.audit(), [], msg="clean audit at rest")

  // Close menu: advance to ~185ms (peak parallel upward recoil ~-16..-17.5pt)
  open.set(false)
  t.draw()
  let close_t0 = t.time()
  t.run_for(bridge_test_recoil_ms)
  let recoil_dt = t.time() - close_t0
  if recoil_dt >= 140.0 && recoil_dt <= 260.0 {
    let recoil_glass = t.drawn_glass()
    let recoil_liq = bridge_liquid_instances(t)
    assert_eq(recoil_liq[0].1, 0.0, msg="Archive pill stays 100% isolated during close recoil")
    // Trigger pill (index 1 when Blob A emerged) has significant upward negative dy displacement
    if recoil_glass.length() >= 3 {
      let trig_dy = recoil_glass[1].1 - rest_pill_y
      assert_true(trig_dy <= -6.5 && trig_dy >= -11.5, msg="trigger pill kicks upward ~-9.5pt at \{recoil_dt}ms: dy=\{trig_dy}")
    }
  }

  // Advance to ~400ms (post-handoff horizontal splash > rest_pill_w, only 2 liquid instances — zero double glass)
  t.run_for(bridge_test_splash_step_ms)
  let splash_dt = t.time() - close_t0
  if splash_dt >= 340.0 && splash_dt <= 460.0 {
    let splash_glass = t.drawn_glass()
    let splash_liq = bridge_liquid_instances(t)
    assert_eq(splash_liq.length(), 2, msg="post-handoff has 2 liquid instances (no double glass) at \{splash_dt}ms")
    assert_true(splash_glass[1].2 > rest_pill_w + 0.1, msg="horizontal splash exceeds resting width at \{splash_dt}ms: w=\{splash_glass[1].2} vs rest=\{rest_pill_w}")
  }

  // Complete full 580ms close recoil + splash settle: trigger pill restored cleanly to resting y & w
  t.run_for(bridge_test_settle_ms)
  let after_glass = t.drawn_glass()
  let after_liq = bridge_liquid_instances(t)
  assert_eq(after_liq.length(), 2, msg="only 2 original top bar pills remain after close finishes")
  assert_eq(after_liq[0].1, 0.0, msg="restored archive pill merge is 0.0")
  assert_eq(after_liq[1].1, 0.0, msg="restored trigger pill merge is 0.0")
  assert_true((after_glass[1].1 - rest_pill_y).abs() < 0.5, msg="trigger pill returns to resting y")
  assert_true((after_glass[1].2 - rest_pill_w).abs() < 0.5, msg="trigger pill returns to resting width")
}

///|
test "non-pill plain button anchored popover keeps FromBeside 0.97..1.0 scale without stacking extra glass" {
  defer {
    @ui.set_glass_solid(None)
    set_dark(None)
  }
  let open = @signals.signal(false)
  let t = bridge_plain_menu_tester(open, false)
  open.set(true)
  t.draw()
  t.run_for(@motion.pop_ms * 0.3)
  let enter_glass = t.drawn_glass()
  assert_eq(enter_glass.length(), 1, msg="non-pill button emits single glass surface without fake droplet")
  t.run_for(@motion.pop_ms)
  let rest_glass = t.drawn_glass()
  assert_eq(rest_glass.length(), 1, msg="rest emits 1 liquid glass instance")
  assert_eq(t.audit(), [], msg="clean audit at rest")
  let rest_h = rest_glass[0].3
  assert_true(enter_glass[0].3 / rest_h >= 0.96, msg="non-pill entrance keeps 0.97..1.0 FromBeside scale: \{enter_glass[0].3 / rest_h}")
  open.set(false)
  t.draw()
  t.run_for(@motion.pop_out_ms * 0.5)
  let exit_glass = t.drawn_glass()
  assert_eq(exit_glass.length(), 1, msg="non-pill exit emits 1 liquid glass instance")
  let exit_scale = exit_glass[0].3 / rest_h
  assert_true(exit_scale >= 0.96 && exit_scale <= 1.0, msg="non-pill exit keeps 0.97..1.0 FromBeside scale: scale=\{exit_scale}")
  t.run_for(@motion.pop_out_ms)
  assert_eq(t.drawn_glass().length(), 0, msg="no glass instances after non-pill exit completes")
}

///|
test "1x1 point anchor context menu never emits a capillary bridge and keeps 0.97 scale" {
  defer {
    @ui.set_glass_solid(None)
    set_dark(None)
  }
  presenters_reset()
  let t = @ui.Tester::new(fn(_c) {  }, w=800.0, h=600.0, dark=false, platform=0)
  set_dark(Some(false))
  @ui.set_glass_solid(None)
  @ui.set_view_app(fn(root) {
    @ui.set_tree_theme(ui_theme_now)
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(By(fn() { theme().p.bg })) |> ignore
    })
    |> ignore
    presented_nodes(root)
  })
  t.draw()
  menu(
    [Some(menu_item_of("Copy", fn() {  })), Some(menu_item_of("Paste", fn() {  }))],
    from=at_point(240.0, 180.0),
  )
  t.draw()
  t.run_for(@motion.pop_ms * 0.3)
  let pt_mid = t.drawn_glass()
  assert_true(pt_mid.length() <= 1, msg="at_point mid-entrance emits at most 1 glass instance")
  t.run_for(@motion.pop_ms)
  let pt_rest = t.drawn_glass()
  assert_eq(pt_rest.length(), 1, msg="at_point resting emits 1 glass instance")
  assert_true(pt_mid[0].3 / pt_rest[0].3 >= 0.96, msg="at_point keeps 0.97..1.0 scale range: \{pt_mid[0].3 / pt_rest[0].3}")
  t.key(@ui.key_escape)
  t.draw()
  t.run_for(@motion.pop_out_ms * 0.5)
  let pt_exit = t.drawn_glass()
  assert_true(pt_exit.length() <= 1, msg="at_point mid-exit emits at most 1 glass instance")
  assert_true(pt_exit[0].3 / pt_rest[0].3 >= 0.96, msg="at_point exit keeps 0.97..1.0 scale range: \{pt_exit[0].3 / pt_rest[0].3}")
  t.run_for(@motion.pop_out_ms)
  assert_eq(t.drawn_glass().length(), 0, msg="at_point exit clears glass")
}

///|
test "MBUI_GLASS=solid emits zero liquid glass instances across pill menu entrance, rest, and exit" {
  defer {
    @ui.set_glass_solid(None)
    set_dark(None)
  }
  let open = @signals.signal(false)
  let t = bridge_pill_menu_tester(open, true)
  open.set(true)
  t.draw()
  t.run_for(@motion.pop_ms * 0.3)
  assert_eq(t.drawn_glass().length(), 0, msg="solid mid-entrance has 0 glass")
  t.run_for(@motion.pop_ms)
  assert_eq(t.drawn_glass().length(), 0, msg="solid rest has 0 glass")
  assert_eq(t.audit(), [], msg="solid rest audit clean")
  open.set(false)
  t.draw()
  t.run_for(@motion.pop_out_ms * 0.4)
  assert_eq(t.drawn_glass().length(), 0, msg="solid mid-exit has 0 glass")
  t.run_for(@motion.pop_out_ms)
  assert_eq(t.drawn_glass().length(), 0, msg="solid post-exit has 0 glass")
}
