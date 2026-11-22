// White-box tests for framework-level same-layer liquid glass proximity fusion (`Glass::liquid(layer?, break_gap?)`
// + `Ctx::merge_liquid_layers` in `glass_layer.mbt`).

///|
fn gl_liquid_insts(t : Tester) -> Array[(Int, Double, Double)] {
  let out : Array[(Int, Double, Double)] = []
  let insts = t.drawn_instances()
  for i in 0..<insts.length() {
    let a = insts[i]
    if a.length() > 23 && a[5] == 6.0 {
      out.push((i, a[20], a[23]))
    }
  }
  out
}

///|
fn gl_shadow_indices(t : Tester) -> Array[Int] {
  let out : Array[Int] = []
  let insts = t.drawn_instances()
  for i in 0..<insts.length() {
    let a = insts[i]
    if a.length() > 5 && a[5] == 2.0 {
      out.push(i)
    }
  }
  out
}

///|
fn gl_rect_indices_of_color(t : Tester, color : Int64) -> Array[Int] {
  let out : Array[Int] = []
  let insts = t.drawn_instances()
  let r = ((color >> 24) & 0xFFL).to_double() / 255.0
  let g = ((color >> 16) & 0xFFL).to_double() / 255.0
  let b = ((color >> 8) & 0xFFL).to_double() / 255.0
  for i in 0..<insts.length() {
    let a = insts[i]
    if a.length() > 11 &&
      a[5] == 0.0 &&
      (a[8] - r).abs() < 0.02 &&
      (a[9] - g).abs() < 0.02 &&
      (a[10] - b).abs() < 0.02 {
      out.push(i)
    }
  }
  out
}

///|
test "same-layer liquid glass auto-merges when gap < break_gap, lifts children above glass, keeps shadows beneath, and decouples at rest" {
  defer { set_glass_solid(None) }
  let gap_sig = @signals.signal(6.0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, dark=false, platform=0)
  set_glass_solid(None)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(Is(0xF5F5F7FFL)) |> ignore
      // Trigger pill in bar (layer=1, with shadow and child icon rect 0x1122CCFFL)
      page.box(fn(pill) {
        pill
        .over(Is(true))
        .offset(Is((40.0, 20.0)))
        .width(Is(Some(80.0)))
        .height(Is(Some(36.0)))
        .radius(Is(18.0))
        .glass(Is(Some(Glass::liquid(blur=2.5, merge=28.0, layer=1, break_gap=3.2))))
        .shadow(Is((4.0, 1.5, 0x00000022L)))
        .shadow_outside(Is(true))
        |> ignore
        pill.box(fn(ic) {
          ic.width(Is(Some(16.0))).height(Is(Some(16.0))).ground(Is(0x1122CCFFL)) |> ignore
        })
        |> ignore
      })
      |> ignore
      // Unrelated page content between the two glass surfaces
      page.box(fn(mid) {
        mid.over(Is(true)).offset(Is((10.0, 100.0))).width(Is(Some(200.0))).height(Is(Some(40.0))).ground(Is(0xDDDDDDFFL))
        |> ignore
      })
      |> ignore
      // Overlay panel in another layer (layer=1, with shadow and child menu row 0xCC2211FFL)
      page.box(fn(ov) {
        ov.over(Is(true)) |> ignore
        ov.box(fn(panel) {
          panel
          .over(Is(true))
          .offset(By(fn() { (40.0, 56.0 + gap_sig.get()) }))
          .width(Is(Some(140.0)))
          .height(Is(Some(100.0)))
          .radius(Is(14.0))
          .glass(Is(Some(Glass::liquid(blur=8.0, merge=28.0, layer=1, break_gap=3.2))))
          .shadow(Is((12.0, 4.0, 0x00000033L)))
          .shadow_outside(Is(true))
          |> ignore
          panel.box(fn(row) {
            row.width(Is(Some(100.0))).height(Is(Some(20.0))).ground(Is(0xCC2211FFL)) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // 1. At rest (gap = 6.0pt >= 3.2pt): independent captures, merge == 0.0
  t.draw()
  let rest_liq = gl_liquid_insts(t)
  assert_eq(rest_liq.length(), 2, msg="2 liquid instances at rest")
  assert_true(rest_liq[0].1 != rest_liq[1].1, msg="independent capture ids at rest")
  assert_eq(rest_liq[0].2, 0.0, msg="pill merge is 0.0 at rest")
  assert_eq(rest_liq[1].2, 0.0, msg="panel merge is 0.0 at rest")

  // 2. Within break_gap (gap = 1.6pt < 3.2pt): auto-merged!
  gap_sig.set(1.6)
  t.draw()
  let close_liq = gl_liquid_insts(t)
  let shadows = gl_shadow_indices(t)
  let pill_icons = gl_rect_indices_of_color(t, 0x1122CCFFL)
  let panel_rows = gl_rect_indices_of_color(t, 0xCC2211FFL)
  assert_eq(close_liq.length(), 2, msg="2 liquid instances when bridging")
  assert_eq(close_liq[1].0 - close_liq[0].0, 1, msg="merged liquid instances are strictly adjacent")
  assert_eq(close_liq[0].1, close_liq[1].1, msg="merged liquid instances share one capture id")
  assert_true(close_liq[0].2 > 0.0 && close_liq[1].2 > 0.0, msg="positive merge radius when gap < break_gap")
  assert_eq(shadows.length(), 2, msg="both shadows preserved")
  assert_true(shadows[0] < close_liq[0].0 && shadows[1] < close_liq[0].0, msg="all shadows strictly beneath merged glass")
  assert_eq(pill_icons.length(), 1, msg="pill icon drawn")
  assert_eq(panel_rows.length(), 1, msg="panel row drawn")
  assert_true(pill_icons[0] > close_liq[1].0, msg="pill child icon lifted strictly above merged glass")
  assert_true(panel_rows[0] > close_liq[1].0, msg="panel child row strictly above merged glass")
}

///|
test "3-way same-layer merge, cross-layer isolation, and MBUI_GLASS=solid fallback" {
  defer { set_glass_solid(None) }
  let panel_y = @signals.signal(57.5)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, dark=false, platform=0)
  set_glass_solid(None)
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.grow(Is(1.0)).ground(Is(0xF5F5F7FFL)) |> ignore
      // Pill A (layer=1) at x=20..56, y=20..56
      page.box(fn(a) {
        a
        .over(Is(true))
        .offset(Is((20.0, 20.0)))
        .width(Is(Some(36.0)))
        .height(Is(Some(36.0)))
        .radius(Is(18.0))
        .glass(Is(Some(Glass::liquid(blur=2.5, merge=28.0, layer=1, break_gap=3.2))))
        |> ignore
      })
      |> ignore
      // Pill B (layer=1) at x=62..132, y=20..56 (6pt from Pill A -> independent at rest!)
      page.box(fn(b) {
        b
        .over(Is(true))
        .offset(Is((62.0, 20.0)))
        .width(Is(Some(70.0)))
        .height(Is(Some(36.0)))
        .radius(Is(18.0))
        .glass(Is(Some(Glass::liquid(blur=2.5, merge=28.0, layer=1, break_gap=3.2))))
        |> ignore
      })
      |> ignore
      // Different layer (layer=2) overlapping Pill B -> must NEVER merge with layer=1
      page.box(fn(other) {
        other
        .over(Is(true))
        .offset(Is((70.0, 25.0)))
        .width(Is(Some(40.0)))
        .height(Is(Some(24.0)))
        .radius(Is(12.0))
        .glass(Is(Some(Glass::liquid(blur=2.5, merge=28.0, layer=2, break_gap=10.0))))
        |> ignore
      })
      |> ignore
      // Panel C (layer=1) spanning x=30..132, y=panel_y (1.5pt below BOTH Pill A and Pill B!)
      page.box(fn(c) {
        c
        .over(Is(true))
        .offset(By(fn() { (30.0, panel_y.get()) }))
        .width(Is(Some(102.0)))
        .height(Is(Some(80.0)))
        .radius(Is(14.0))
        .glass(Is(Some(Glass::liquid(blur=8.0, merge=28.0, layer=1, break_gap=3.2))))
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // 1. Panel C within 1.5pt of BOTH Pill A and Pill B -> 3-way merge on layer=1; layer=2 stays separate
  t.draw()
  let liq = gl_liquid_insts(t)
  assert_eq(liq.length(), 4, msg="4 liquid instances total")
  let merged = liq.filter(fn(x) { x.2 > 0.0 })
  let isolated = liq.filter(fn(x) { x.2 == 0.0 })
  assert_eq(merged.length(), 3, msg="3-way merge on layer=1")
  assert_eq(isolated.length(), 1, msg="layer=2 remains isolated")
  assert_eq(merged[0].1, merged[1].1, msg="merged[0] & merged[1] share capture")
  assert_eq(merged[1].1, merged[2].1, msg="merged[1] & merged[2] share capture")
  assert_eq(merged[1].0 - merged[0].0, 1, msg="merged[0] & merged[1] adjacent")
  assert_eq(merged[2].0 - merged[1].0, 1, msg="merged[1] & merged[2] adjacent")
  assert_true(isolated[0].1 != merged[0].1, msg="layer=2 has its own capture id")

  // 2. Move Panel C away (y = 70.0 -> 14pt gap): all 4 become independent
  panel_y.set(70.0)
  t.draw()
  let far = gl_liquid_insts(t)
  assert_eq(far.length(), 4, msg="4 independent liquid instances when separated")
  for x in far {
    assert_eq(x.2, 0.0, msg="merge is 0.0 when separated")
  }

  // 3. MBUI_GLASS=solid: 0 liquid instances
  set_glass_solid(Some(true))
  t.draw()
  assert_eq(gl_liquid_insts(t).length(), 0, msg="0 liquid glass instances in solid mode")
}

///|
test "glass layer nav_scope: distinct non-zero nav scopes never cross-page merge, root overlay (0) merges with one page only" {
  assert_true(glass_slots_nav_compatible(0, 0))
  assert_true(glass_slots_nav_compatible(1, 1))
  assert_true(glass_slots_nav_compatible(1, 0))
  assert_true(glass_slots_nav_compatible(0, 2))
  assert_true(!glass_slots_nav_compatible(1, 2))
  assert_true(!glass_slots_nav_compatible(2, 1))
  // Direct unit check on merge_liquid_layers with two overlapping slots on different nav_scopes (1 vs 2)
  let c = Ctx::new()
  c.ninst = 0
  let gl = Glass::liquid(blur=4.0, merge=0.0, layer=1, break_gap=3.2)
  c.glass_inst(40.0, 20.0, 60.0, 36.0, 18.0, gl, 1.0)
  let g0 = 0
  c.glass_inst(50.0, 20.0, 60.0, 36.0, 18.0, gl, 1.0)
  let g1 = 1
  let slots : Array[GlassSlot] = [
    {
      layer: 1,
      nav_scope: 1,
      id: { at: 1, gen: 1 },
      glass_idx: g0,
      shadow_idx: -1,
      sub_start: 0,
      sub_end: 1,
      x0: 40.0,
      y0: 20.0,
      x1: 100.0,
      y1: 56.0,
      cx0: 0.0,
      cy0: 0.0,
      cx1: 360.0,
      cy1: 740.0,
      merge_max: 28.0,
      break_gap: 3.2,
    },
    {
      layer: 1,
      nav_scope: 2,
      id: { at: 2, gen: 1 },
      glass_idx: g1,
      shadow_idx: -1,
      sub_start: 1,
      sub_end: 2,
      x0: 50.0,
      y0: 20.0,
      x1: 110.0,
      y1: 56.0,
      cx0: 0.0,
      cy0: 0.0,
      cx1: 360.0,
      cy1: 740.0,
      merge_max: 28.0,
      break_gap: 3.2,
    },
  ]
  c.merge_liquid_layers(0, slots)
  assert_eq(c.inst[g0 * inst_size + 23], 0.0, msg="nav_scope=1 slot must not merge with nav_scope=2")
  assert_eq(c.inst[g1 * inst_size + 23], 0.0, msg="nav_scope=2 slot must not merge with nav_scope=1")
  // Same test with root overlay (nav_scope=0) and page (nav_scope=1): MUST merge
  let slots_root : Array[GlassSlot] = [
    slots[0],
    { ..slots[1], nav_scope: 0 },
  ]
  c.merge_liquid_layers(0, slots_root)
  assert_true(c.inst[g0 * inst_size + 23] > 6.0 && c.inst[g0 * inst_size + 23] <= 6.41, msg="nav_scope=1 merges with root overlay nav_scope=0 capped at 2*break_gap")
  assert_true(c.inst[g1 * inst_size + 23] > 6.0 && c.inst[g1 * inst_size + 23] <= 6.41, msg="root overlay nav_scope=0 merges with nav_scope=1 capped at 2*break_gap")
  assert_eq(c.inst[g0 * inst_size + 20], c.inst[g1 * inst_size + 20], msg="shared capture id for page + root overlay")
}

///|
test "glass layer m_eff cap: strictly <= 2.0 * break_gap so third-shape entry/exit never flashes" {
  let c = Ctx::new()
  c.ninst = 0
  let gl = Glass::liquid(blur=4.0, merge=0.0, layer=1, break_gap=3.0)
  c.glass_inst(40.0, 20.0, 60.0, 36.0, 18.0, gl, 1.0)
  c.glass_inst(50.0, 20.0, 60.0, 36.0, 18.0, gl, 1.0)
  let slots : Array[GlassSlot] = [
    {
      layer: 1,
      nav_scope: 0,
      id: { at: 1, gen: 1 },
      glass_idx: 0,
      shadow_idx: -1,
      sub_start: 0,
      sub_end: 1,
      x0: 40.0,
      y0: 20.0,
      x1: 100.0,
      y1: 56.0,
      cx0: 0.0,
      cy0: 0.0,
      cx1: 360.0,
      cy1: 740.0,
      merge_max: 20.0,
      break_gap: 3.0,
    },
    {
      layer: 1,
      nav_scope: 0,
      id: { at: 2, gen: 1 },
      glass_idx: 1,
      shadow_idx: -1,
      sub_start: 1,
      sub_end: 2,
      x0: 50.0,
      y0: 20.0,
      x1: 110.0,
      y1: 56.0,
      cx0: 0.0,
      cy0: 0.0,
      cx1: 360.0,
      cy1: 740.0,
      merge_max: 20.0,
      break_gap: 3.0,
    },
  ]
  c.merge_liquid_layers(0, slots)
  assert_true(c.inst[23] > 0.0 && c.inst[23] <= 6.0, msg="effective merge capped at 2*break_gap=6.0: got \{c.inst[23]}")
  assert_true(c.inst[inst_size + 23] > 0.0 && c.inst[inst_size + 23] <= 6.0, msg="second slot effective merge capped at 6.0: got \{c.inst[inst_size + 23]}")
}
