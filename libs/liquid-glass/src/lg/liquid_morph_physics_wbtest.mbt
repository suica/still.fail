// White-box unit tests for 1:1 iOS 27.0 LiquidMorphPhysics (`liquid_morph_physics.mbt`) in `@lg`:
// verifies open/close springs, mid-open circular bubble aspect ratio, 30ms-lead parallel close trigger recoil
// (~213ms peak, ~-9.5pt catch, ~580ms settle), wide-trigger horizontal splash (~400ms +1.016), delayed close
// width C0 continuity at handoff, top-bar hugging close geometry, gap-gated Blob A emergence, and zero NaN.

///|
test "LiquidMorphPhysics open/close springs, recoil pulse, and horizontal splash match CADisplayLink calibration" {
  // 1. Open spring (omega0=26, zeta=1.0): critically damped monotonic rise (~95% at 180ms, >99.9% at 420ms, no overshoot)
  assert_eq(lm_open_progress(0.0), 0.0)
  let open_180 = lm_open_progress(0.18)
  let open_210 = lm_open_progress(0.21)
  assert_true(open_180 > 0.93 && open_180 < 1.0, msg="open spring ~95% at 180ms: \{open_180}")
  assert_true(open_210 >= open_180 && open_210 <= 1.0, msg="open spring monotonic without overshoot: \{open_180} -> \{open_210}")
  let open_end = lm_open_progress(0.42)
  assert_true(open_end > 0.999 && open_end <= 1.0, msg="open spring settled by 420ms: \{open_end}")
  // Open mid-phase aspect ratio stays near-circular on 190x265 menu (width leads height: w^0.44 vs h^0.70)
  let f67 = lm_eval_pill_morph(300.0, 35.0, 74.0, 36.0, 358.0, 184.0, 35.0, 190.0, 265.0, 20.0, 1.0, false, 0.067)
  let aspect67 = f67.cur_w / f67.cur_h
  assert_true(aspect67 >= 0.80 && aspect67 <= 1.15, msg="open mid bubble near-circular at 67ms: aspect=\{aspect67}")
  assert_true(lm_open_size_progress(0.5, lm_scale_delta(36.0, 36.0, 190.0, 265.0)) > 0.65)

  // 2. Close spring (omega0=15, zeta=0.88): platter active > 0.045 at 200ms, hands off by ~320ms
  assert_eq(lm_close_progress(0.0), 1.0)
  assert_true(lm_close_platter_active(lm_close_progress(0.20)), msg="platter active at 200ms")
  assert_true(!lm_close_platter_active(lm_close_progress(0.32)), msg="platter handed off by 320ms")

  // 3. Parallel close recoil pulse: 0 for t<=0.03s, peak ~1.0 at t=0.213s, near 0 at 0.58s
  assert_eq(lm_recoil_pulse(0.0), 0.0)
  assert_eq(lm_recoil_pulse(0.03), 0.0)
  let pulse_peak = lm_recoil_pulse(0.213)
  assert_true((pulse_peak - 1.0).abs() < 0.02, msg="recoil pulse peaks ~1.0 at 213ms: \{pulse_peak}")
  let pulse_end = lm_recoil_pulse(0.58)
  assert_true(pulse_end.abs() < 0.06, msg="recoil pulse settles near 0 by 580ms: \{pulse_end}")

  // 4. Recoil vertical offset: negative (upward) ~-9.5..-10.0pt for Bottom menu (matching iOS 27.0 ~24% pill height)
  let dy_phone = lm_recoil_offset_y(0.213, 120.0, 10.0)
  assert_true(dy_phone < -9.0 && dy_phone > -10.5, msg="phone recoil peak ~-9.8pt: \{dy_phone}")
  let dy_capped = lm_recoil_offset_y(0.213, 120.0, 5.0)
  assert_true(dy_capped < -4.8 && dy_capped > -5.2, msg="capped recoil peak ~-5.0pt: \{dy_capped}")

  // 5. Impact compression scale: ~0.965 at 213ms, 1.0 at t=0
  assert_eq(lm_impact_scale(0.0, 120.0), 1.0)
  let imp = lm_impact_scale(0.213, 120.0)
  assert_true(imp > 0.95 && imp < 0.975, msg="impact scale ~0.965 at 213ms: \{imp}")

  // 6. Close trigger width: crosses 1.0 around 320ms, horizontal splash ~1.016 at 400ms
  let w_400 = lm_close_trigger_width(0.40)
  assert_true(w_400 > 1.010 && w_400 < 1.025, msg="horizontal splash ~1.016 at 400ms: \{w_400}")
  let diff_handoff = (lm_delayed_close_width(0.283) - lm_close_trigger_width(0.283)).abs()
  assert_true(diff_handoff < 1.0e-6, msg="delayed close width C0 at handoff: diff=\{diff_handoff}")

  // 7. Three-anchor liquid_menu_morph_glass optical recipe invariants
  let g0 = liquid_menu_morph_glass(0.0, dark=false)
  let g5 = liquid_menu_morph_glass(0.5, dark=false)
  let g1 = liquid_menu_morph_glass(1.0, dark=false)
  assert_eq(g0.tint & 0xFFL, 0x67L)
  assert_eq(g5.tint & 0xFFL, 0x4EL)
  assert_true((g5.blur - 1.6).abs() < 1.0e-9)
  assert_eq(g1.tint & 0xFFL, 0xBFL)

  // 8. No NaN and close hugs top bar (my <= pill_h + 18pt) across 0..600ms sampling
  for i in 0..<=60 {
    let t = i.to_double() * 0.01
    let raw_c = lm_close_progress(t)
    let (mx, my, mw, mh, r) = lm_closing_teardrop_geometry(
      raw_c, 150.0, 18.0, 74.0, 36.0, 190.0, 265.0, 20.0, lm_recoil_offset_y(t, 114.0, 10.0), t, 1.0,
    )
    assert_true(!mx.is_nan() && !my.is_nan() && !mw.is_nan() && !mh.is_nan() && !r.is_nan(), msg="no NaN at t=\{t}")
    assert_true(mw >= 0.0 && mh >= 0.0 && r >= 0.0, msg="non-negative close geometry at t=\{t}")
    if lm_close_platter_active(raw_c) {
      assert_true(my <= 36.0 + 18.0, msg="close hugs top bar without plunging at t=\{t}: my=\{my}")
    }
    let em = lm_close_blob_a_emergence(mx, my, mw, mh, r, 150.0, 18.0, raw_c)
    assert_true(em == 0.0 || (em >= 0.45 && em <= 1.0), msg="blob A emergence valid range: \{em}")
    let bl = lm_close_blend(raw_c)
    assert_true(bl >= 0.0 && bl <= 22.0, msg="close blend in [0, 22]: \{bl}")
  }
}
