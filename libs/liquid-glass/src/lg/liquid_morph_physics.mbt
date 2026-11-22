// Pure stateless iOS 27.0 LiquidMorphPhysics engine (1:1 port of sdegenaar/liquid_glass_widgets
// `liquid_morph_physics.dart`, calibrated against 60 fps CADisplayLink CALayer.presentation() traces
// and frame-aligned to native iOS 27.0 grouped menus).
// All functions are pure closed-form functions of elapsed phase time `t` (seconds), ensuring 100%
// identical trajectories across 60/120/24/7 fps with zero global mutable state.

///|
/// Total open phase duration (ms) for `t_way` linear clock (`0.0 -> 0.42s`, reaching steady silhouette at ~185ms).
pub let lm_open_duration_ms : Double = 420.0

///|
/// Total close phase duration (ms) for `t_way` linear clock (`0.0 -> 0.61s`, covering ~285ms platter handoff +
/// ~213ms peak trigger recoil + ~400ms horizontal splash + ~580ms settle).
pub let lm_close_duration_ms : Double = 610.0

///|
/// Cubic Hermite smoothstep supporting both rising (`edge0 < edge1`) and falling (`edge0 > edge1`) ramps.
pub fn lm_smoothstep(edge0 : Double, edge1 : Double, x : Double) -> Double {
  if edge0 == edge1 {
    return if x >= edge1 { 1.0 } else { 0.0 }
  }
  let u = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
  u * u * (3.0 - 2.0 * u)
}

///|
/// Linear interpolation `a + (b - a) * t`.
pub fn lm_lerp(a : Double, b : Double, t : Double) -> Double {
  a + (b - a) * t
}

///|
/// Closed-form unit step response `0.0 -> 1.0` with `v(0) = 0` for a damped harmonic oscillator
/// of natural frequency `omega0` (rad/s) and damping ratio `zeta`.
pub fn lm_step_response(t : Double, omega0 : Double, zeta : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  if zeta < 1.0 - 1.0e-6 {
    let r = zeta * omega0
    let wd = omega0 * (1.0 - zeta * zeta).sqrt()
    1.0 - @dmath.exp(-r * t) * (@dmath.cos(wd * t) + (r / wd) * @dmath.sin(wd * t))
  } else if zeta > 1.0 + 1.0e-6 {
    let s = (zeta * zeta - 1.0).sqrt()
    let r1 = -omega0 * (zeta - s)
    let r2 = -omega0 * (zeta + s)
    1.0 - (r2 * @dmath.exp(r1 * t) - r1 * @dmath.exp(r2 * t)) / (r2 - r1)
  } else {
    1.0 - (1.0 + omega0 * t) * @dmath.exp(-omega0 * t)
  }
}

///|
/// Primary open spring (`omega0 = 26.0 rad/s, zeta = 1.0`, critically damped: monotonic with zero overshoot,
/// smooth zero-velocity settle, ~95% at ~183ms and 99.98% at 420ms, avoiding `sizes_steady` clamp dead-stops).
pub fn lm_open_progress(t : Double, start? : Double = 0.0) -> Double {
  start + (1.0 - start) * lm_step_response(t, 26.0, 1.0)
}

///|
/// Primary close platter contraction spring (`omega0 = 15.0 rad/s, zeta = 0.88`, gentle early contraction).
pub fn lm_close_progress(t : Double, start? : Double = 1.0) -> Double {
  start * (1.0 - lm_step_response(t, 15.0, 0.88))
}

///|
/// Whether the closing floating platter (Blob B) is still active before handing off to the real trigger pill
/// (`raw_value > 0.045`, turning false around `t ≈ 0.285s`).
pub fn lm_close_platter_active(raw_value : Double) -> Bool {
  raw_value > 0.045
}

///|
/// Normalized parallel close recoil pulse with `0.03s` impact lead (`0.0` for `t <= 0.03s`, peak `1.0` at
/// `t ≈ 0.213s` aligned with Blob B catching the trigger pill, zero-crossing at `~0.513s`, settled by `~0.58s`).
pub fn lm_recoil_pulse(t : Double) -> Double {
  let te = t - 0.03
  if te <= 0.0 {
    return 0.0
  }
  let s_under = lm_step_response(te, 17.0, 0.70)
  let s_crit = lm_step_response(te, 18.0, 1.0)
  (s_under - s_crit) / 0.139711
}

///|
/// Parallel vertical recoil offset (pt) for the trigger pill during close, kicking opposite to `final_dy`
/// (upward negative `dy` for `Bottom` menus), capped by `max_travel_cap` (`~-9.5pt` native iOS 27.0 catch).
pub fn lm_recoil_offset_y(t : Double, final_dy : Double, max_travel_cap : Double) -> Double {
  if t <= 0.0 || final_dy.abs() <= 0.001 || max_travel_cap <= 0.0 {
    return 0.0
  }
  let travel = final_dy.abs()
  let raw_mag = 10.5 * travel / (travel + 8.0)
  let mag = if raw_mag < max_travel_cap { raw_mag } else { max_travel_cap }
  let dir = if final_dy > 0.0 { -1.0 } else { 1.0 }
  dir * mag * lm_recoil_pulse(t)
}

///|
/// Tactile impact compression scale (`~0.965..1.0`) applied to the trigger pill in parallel with close recoil.
pub fn lm_impact_scale(t : Double, travel : Double) -> Double {
  if t <= 0.0 {
    return 1.0
  }
  let rp = lm_recoil_pulse(t)
  let pulse = if rp > 0.0 { rp } else { 0.0 }
  let depth = 0.025 + 0.015 * (travel / (travel + 75.0))
  clamp(1.0 - depth * pulse, 0.92, 1.02)
}

///|
/// Open wide-trigger width contraction (`1.0 -> 0.0`, `pill_w -> pill_h`, `omega0 = 52.0, zeta = 1.0`:
/// contracts 55% by 17ms and reaches compact pebble by 33ms so no wide-pill chin bulge appears).
pub fn lm_open_trigger_width(t : Double) -> Double {
  clamp(1.0 - lm_step_response(t, 52.0, 1.0), 0.0, 1.0)
}

///|
/// Close wide-trigger width re-expansion (`0.0 -> 1.0`, crossing `1.0` at `~320ms`, horizontal splash `+1.016`
/// at `~400ms`, settling by `~550ms`, `omega0 = 13.0, zeta = 0.795`).
pub fn lm_close_trigger_width(t : Double) -> Double {
  lm_step_response(t, 13.0, 0.795)
}

///|
/// Delayed close capsule width progress for Blob A: evaluates `lm_close_trigger_width` `0.05s` late and
/// blends linearly to the undelayed spring across `0.05..0.28s` so handoff is strictly C⁰ continuous.
pub fn lm_delayed_close_width(t : Double) -> Double {
  let delay = 0.05
  let raw = lm_close_trigger_width(t)
  let td = if t - delay > 0.0 { t - delay } else { 0.0 }
  let delayed = lm_close_trigger_width(td)
  let blend = clamp((t - delay) / 0.23, 0.0, 1.0)
  lm_lerp(delayed, raw, blend)
}

///|
/// Geometric scale ratio `sqrt(target_area / source_area)`.
pub fn lm_scale_delta(core_w : Double, core_h : Double, menu_w : Double, menu_h : Double) -> Double {
  let src = core_w * core_h
  if src <= 0.0 {
    1.0
  } else {
    (menu_w * menu_h / src).sqrt()
  }
}

///|
/// Open size progress: `raw^0.55` for large menus (`scale_delta > 3.0`), linear clamp otherwise.
pub fn lm_open_size_progress(raw_value : Double, scale_delta : Double) -> Double {
  let u = clamp(raw_value, 0.0, 1.0)
  if scale_delta > 3.0 {
    @dmath.pow(u, 0.55)
  } else {
    u
  }
}

///|
/// Vertical open drift (pt, unsigned; caller applies travel direction) kept gentle (`<= 16pt`) so bubble stays near bar.
pub fn lm_open_drift(t : Double, menu_h : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  let peak = clamp(0.055 * menu_h, 0.0, 16.0)
  let pulse = (lm_step_response(t, 24.0, 0.60) - lm_step_response(t, 20.0, 0.90)) / 0.2865
  let pos_pulse = if pulse > 0.0 { pulse } else { 0.0 }
  let fade = 1.0 - lm_smoothstep(0.18, 0.34, t)
  peak * pos_pulse * fade
}

///|
/// Opening platter corner radius: holds near-circular bubble (`rho = 1.0`) until `hold` then relaxes over `0.105s`.
pub fn lm_open_corner_radius(
  cur_w : Double,
  cur_h : Double,
  menu_w : Double,
  menu_h : Double,
  target_r : Double,
  t : Double,
) -> Double {
  let min_cur = if cur_w < cur_h { cur_w } else { cur_h }
  let shortest_half = if min_cur > 0.0 { min_cur * 0.5 } else { 0.0 }
  let min_rest = if menu_w < menu_h { menu_w } else { menu_h }
  let resting_half = if min_rest * 0.5 > 1.0e-3 { min_rest * 0.5 } else { 1.0e-3 }
  let rho0 = clamp(target_r / resting_half, 0.0, 1.0)
  let hold = clamp(0.085 - 0.02 * ((menu_h - 200.0) / 300.0), 0.055, 0.095)
  let k = clamp((t - 0.02 - hold) / 0.105, 0.0, 1.0)
  let roundness = rho0 + (1.0 - rho0) * @dmath.pow(1.0 - k, 1.3)
  shortest_half * clamp(roundness, 0.0, 1.0)
}

///|
/// Effective uniform glass scale for a closing menu platter returning into a trigger of shortest side `min_trigger_side`.
pub fn lm_close_glass_scale(u : Double, min_trigger_side : Double, menu_w : Double) -> Double {
  let u = clamp(u, 0.0, 1.0)
  if menu_w <= 0.0 {
    return clamp(0.20 + 0.80 * u, 0.08, 1.0)
  }
  let tail_scale = clamp(0.56 * min_trigger_side / menu_w, 0.08, 0.20)
  let floor = tail_scale + (0.20 - tail_scale) * lm_smoothstep(0.0, 0.24, u)
  clamp(floor + (1.0 - floor) * u, 0.08, 1.0)
}

///|
/// Absolute height envelope (pt) of the closing glass blob: `core_h + 400 * u^1.1` plus rapid decay of excess height.
pub fn lm_close_height_envelope(u : Double, core_h : Double, resting_h : Double) -> Double {
  let u = clamp(u, 0.0, 1.0)
  let base_env = core_h + 400.0 * @dmath.pow(u, 1.1)
  let raw_extra = resting_h - (core_h + 400.0)
  let extra = if raw_extra > 0.0 { raw_extra } else { 0.0 }
  base_env + extra * @dmath.pow(u, 2.5)
}

///|
/// Corner radius of the closing platter: climbs from `rho0` (resting menu) to `1.0` (circle) as `1 - (1 - rho0) * s^2.2`.
pub fn lm_close_corner_radius(
  cur_w : Double,
  cur_h : Double,
  menu_w : Double,
  menu_h : Double,
  target_r : Double,
  s : Double,
) -> Double {
  let min_cur = if cur_w < cur_h { cur_w } else { cur_h }
  let shortest_half = if min_cur > 0.0 { min_cur * 0.5 } else { 0.0 }
  let min_rest = if menu_w < menu_h { menu_w } else { menu_h }
  let resting_half = if min_rest * 0.5 > 1.0e-3 { min_rest * 0.5 } else { 1.0e-3 }
  let rho0 = clamp(target_r / resting_half, 0.0, 1.0)
  let s = clamp(s, 0.0, 1.0)
  let roundness = 1.0 - (1.0 - rho0) * @dmath.pow(s, 2.2)
  shortest_half * clamp(roundness, 0.0, 1.0)
}

///|
/// Close-phase neck drift (pt, unsigned; caller applies travel direction) capped at `+10pt` so in-place menus
/// hug the top bar cleanly during dismissal instead of plunging into the chat body.
pub fn lm_close_drift(t : Double, menu_h : Double) -> Double {
  if t <= 0.0 {
    return 0.0
  }
  let unit = lm_step_response(t, 20.0, 1.0) * (1.0 - lm_step_response(t, 24.0, 1.0))
  let peak = 10.0 * clamp((menu_h - 80.0) / 160.0, 0.0, 1.0)
  peak * unit / 0.2047
}

///|
/// Analytical close-phase teardrop geometry `(mx, my, cur_w, cur_h, radius)` in `p`'s local coordinates `(0, 0, menu_w, menu_h)`:
/// width contracts slightly slower than height (`w_scale = pow(close_glass_scale, 0.82)`) so mid-close stays a plump
/// droplet hugging the top bar rather than a thin vertical strip.
pub fn lm_closing_teardrop_geometry(
  raw_value : Double,
  trig_cx : Double,
  trig_cy : Double,
  tw : Double,
  th : Double,
  menu_w : Double,
  menu_h : Double,
  target_r : Double,
  push_dy : Double,
  t : Double,
  align_x : Double,
) -> (Double, Double, Double, Double, Double) {
  let u = clamp(raw_value, 0.0, 1.0)
  let min_side = if tw < th { tw } else { th }
  let close_glass_scale = lm_close_glass_scale(u, min_side, menu_w)
  let w_scale = @dmath.pow(close_glass_scale, 0.82)
  let h_scale = close_glass_scale
  let tapered_core_h = min_side * (0.65 + 0.35 * lm_smoothstep(0.0, 0.24, u))
  let max_h = lm_close_height_envelope(u, tapered_core_h, menu_h)
  let fx = if menu_w > 0.0 { trig_cx / menu_w } else { 0.5 }
  let fy = if menu_h > 0.0 { trig_cy / menu_h } else { 0.5 }
  let base_w = clamp(menu_w * w_scale, 0.0, menu_w)
  let raw_h = menu_h * h_scale
  let base_h = clamp(if raw_h < max_h { raw_h } else { max_h }, 0.0, menu_h)
  let base_left = trig_cx - fx * base_w
  let base_top = trig_cy - fy * base_h
  let base_cx = base_left + base_w * 0.5
  let base_cy = base_top + base_h * 0.5
  let tail_scale = if menu_w > 0.0 { clamp(0.56 * min_side / menu_w, 0.08, 0.20) } else { 0.20 }
  let close_size_p = clamp((close_glass_scale - tail_scale) / (1.0 - tail_scale), 0.0, 1.0)
  let radius = lm_close_corner_radius(base_w, base_h, menu_w, menu_h, target_r, close_size_p)
  let recoil_catch_y = push_dy * (1.0 - u)
  let dir_y = if menu_h * 0.5 - trig_cy >= 0.0 { 1.0 } else { -1.0 }
  let close_drift_y = dir_y * lm_close_drift(t, menu_h)
  let raw_cy = base_cy + recoil_catch_y + close_drift_y
  let converge_x = lm_smoothstep(0.0, 0.28, 0.36 - u)
  let mut closed_cx = base_cx + (trig_cx - base_cx) * converge_x
  if align_x < -0.1 {
    let trig_left = trig_cx - tw * 0.5
    let lim = trig_left + base_w * 0.5
    if closed_cx < lim {
      closed_cx = lim
    }
  } else if align_x > 0.1 {
    let trig_right = trig_cx + tw * 0.5
    let lim = trig_right - base_w * 0.5
    if closed_cx > lim {
      closed_cx = lim
    }
  }
  (closed_cx - base_w * 0.5, raw_cy - base_h * 0.5, base_w, base_h, radius)
}

///|
/// Gap-gated emergence factor (`0.0`, or `0.45 -> 1.0`) for Blob A during close so it only emerges inside
/// metaball bridge reach (`raw_value < 0.45` and rounded-rect distance `< 24pt`), avoiding detached dots.
pub fn lm_close_blob_a_emergence(
  mx : Double,
  my : Double,
  mw : Double,
  mh : Double,
  platter_r : Double,
  trig_cx : Double,
  trig_cy : Double,
  raw_value : Double,
) -> Double {
  let u = clamp(raw_value, 0.0, 1.0)
  let half_min = (if mw < mh { mw } else { mh }) * 0.5
  let r = if platter_r < half_min { platter_r } else { half_min }
  let in_l = mx + r
  let in_r = mx + mw - r
  let in_t = my + r
  let in_b = my + mh - r
  let dx1 = in_l - trig_cx
  let dx2 = trig_cx - in_r
  let ddx_raw = if dx1 > dx2 { dx1 } else { dx2 }
  let ddx = if ddx_raw > 0.0 { ddx_raw } else { 0.0 }
  let dy1 = in_t - trig_cy
  let dy2 = trig_cy - in_b
  let ddy_raw = if dy1 > dy2 { dy1 } else { dy2 }
  let ddy = if ddy_raw > 0.0 { ddy_raw } else { 0.0 }
  let gap_raw = (ddx * ddx + ddy * ddy).sqrt() - r
  let gap = if gap_raw > 0.0 { gap_raw } else { 0.0 }
  let by_time = lm_smoothstep(0.0, 0.12, 0.40 - u)
  let by_gap = lm_smoothstep(0.0, 11.0, 24.0 - gap)
  let emerge = if by_time < by_gap { by_time } else { by_gap }
  if emerge <= 0.001 {
    0.0
  } else {
    0.45 + 0.55 * emerge
  }
}

///|
/// SDF smooth-union radius (pt) on close (`22.0 * ramp_in * ramp_out`), keeping the teardrop neck slender.
pub fn lm_close_blend(raw_value : Double) -> Double {
  let u = clamp(raw_value, 0.0, 1.0)
  let ramp_in = lm_smoothstep(0.0, 0.20, 0.97 - u)
  let ramp_out = 1.0 - lm_smoothstep(0.0, 0.16, 0.16 - u)
  22.0 * ramp_in * ramp_out
}

///|
/// Menu content opacity on open (`0 -> 1` across `t in [0.065, 0.145]s`: visible at +100ms, full by +145ms).
pub fn lm_open_content_opacity(t : Double) -> Double {
  lm_smoothstep(0.065, 0.145, t)
}

///|
/// Menu content blur sigma (pt) on open (`6.5 -> 0.0` across `t in [0.075, 0.175]s`: crisp by +175ms).
pub fn lm_open_content_blur(t : Double) -> Double {
  6.5 * (1.0 - lm_smoothstep(0.075, 0.175, t))
}

///|
/// Menu content opacity on close: fades rows and focus highlights completely to `0.0` by `raw_value <= 0.45`
/// (`t ≈ 115ms`), matching iOS 27.0 clearing text before droplet contraction and avoiding mid-close corner faults.
pub fn lm_close_content_opacity(raw_value : Double) -> Double {
  lm_smoothstep(0.45, 0.98, clamp(raw_value, 0.0, 1.0))
}

///|
/// Menu content blur sigma (pt) on close (`28 * (1 - u)` clamped to `[0, 8]`).
pub fn lm_close_content_blur(raw_value : Double) -> Double {
  clamp(28.0 * (1.0 - clamp(raw_value, 0.0, 1.0)), 0.0, 8.0)
}

///|
/// Shared per-frame analytical morph state evaluated by `lm_eval_pill_morph` in the popover shell's
/// local coordinates `(0, 0, menu_w, menu_h)`.
pub(all) struct LiquidMorphFrame {
  mx : Double
  my : Double
  cur_w : Double
  cur_h : Double
  radius : Double
  raw_value : Double
  push_dy : Double
  platter_active : Bool
  content_opacity : Double
  content_blur : Double
  final_dy : Double
  open_anchor_scale : Double
  blob_a_emerge : Double
}

///|
/// Evaluates the full per-frame `LiquidMorphFrame` for an in-place pill-anchored popover morph.
pub fn lm_eval_pill_morph(
  pill_x : Double,
  pill_y : Double,
  pill_w : Double,
  pill_h : Double,
  tx_win : Double,
  px_win : Double,
  py_win : Double,
  menu_w : Double,
  menu_h : Double,
  target_r : Double,
  align_x : Double,
  closing : Bool,
  t : Double,
) -> LiquidMorphFrame {
  let trig_cx = pill_x + pill_w * 0.5 - px_win
  let trig_cy = pill_y + pill_h * 0.5 - py_win
  let tx_local = tx_win - px_win
  let final_dy = menu_h * 0.5 - trig_cy
  let raw_cap = pill_y - 4.0
  let floor_cap = if raw_cap > 5.0 { raw_cap } else { 5.0 }
  let max_up = if floor_cap < 10.0 { floor_cap } else { 10.0 }
  if !closing {
    let raw = lm_open_progress(t)
    let u = clamp(raw, 0.0, 1.0)
    let core = if pill_w < pill_h { pill_w } else { pill_h }
    let w_prog = @dmath.pow(u, 0.44)
    let h_prog = @dmath.pow(u, 0.70)
    let cur_w = clamp(lm_lerp(core, menu_w, w_prog), core, menu_w)
    let cur_h = clamp(lm_lerp(core, menu_h, h_prog), core, menu_h)
    let pill_l = pill_x - px_win
    let origin_cx = if pill_w >= core {
      clamp(tx_local, pill_l + core * 0.5, pill_l + pill_w - core * 0.5)
    } else {
      trig_cx
    }
    let interp_cx = lm_lerp(origin_cx, menu_w * 0.5, w_prog)
    let interp_cy = lm_lerp(trig_cy, menu_h * 0.5, h_prog)
    let dir_y = if final_dy >= 0.0 { 1.0 } else { -1.0 }
    let drift_y = dir_y * lm_open_drift(t, menu_h)
    let min_x_raw = origin_cx - cur_w * 0.5
    let min_x = if min_x_raw < 0.0 { min_x_raw } else { 0.0 }
    let max_x_raw = menu_w - cur_w
    let max_x = if max_x_raw > 0.0 { max_x_raw } else { 0.0 }
    let mx = clamp(interp_cx - cur_w * 0.5, min_x, max_x)
    let my_raw = interp_cy + drift_y - cur_h * 0.5
    let my = if my_raw > 0.0 { my_raw } else { 0.0 }
    let radius = lm_open_corner_radius(cur_w, cur_h, menu_w, menu_h, target_r, t)
    let open_anchor_scale = 1.0 - clamp(t / 0.035, 0.0, 1.0)
    let settled = t >= lm_open_duration_ms / 1000.0 - 0.001
    let content_opacity = if settled { 1.0 } else { lm_open_content_opacity(t) }
    let content_blur = if settled { 0.0 } else { lm_open_content_blur(t) }
    {
      mx,
      my,
      cur_w,
      cur_h,
      radius,
      raw_value: raw,
      push_dy: 0.0,
      platter_active: raw > 0.001 || settled,
      content_opacity,
      content_blur,
      final_dy,
      open_anchor_scale: if settled { 0.0 } else { open_anchor_scale },
      blob_a_emerge: 0.0,
    }
  } else {
    let raw = lm_close_progress(t)
    let platter_active = lm_close_platter_active(raw)
    let push_dy = lm_recoil_offset_y(t, final_dy, max_up)
    let (mx, my, cur_w, cur_h, radius) = lm_closing_teardrop_geometry(
      raw, trig_cx, trig_cy, pill_w, pill_h, menu_w, menu_h, target_r, push_dy, t, align_x,
    )
    let emerge = if platter_active {
      lm_close_blob_a_emergence(mx, my, cur_w, cur_h, radius, trig_cx, trig_cy + push_dy, raw)
    } else {
      1.0
    }
    let content_opacity = if platter_active { lm_close_content_opacity(raw) } else { 0.0 }
    let content_blur = if platter_active { lm_close_content_blur(raw) } else { 0.0 }
    {
      mx,
      my,
      cur_w,
      cur_h,
      radius,
      raw_value: raw,
      push_dy,
      platter_active,
      content_opacity,
      content_blur,
      final_dy,
      open_anchor_scale: 0.0,
      blob_a_emerge: emerge,
    }
  }
}
