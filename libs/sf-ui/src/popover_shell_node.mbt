// Unified anchored popover shell and placement-side helper for overlays anchored beside a trigger
// (`menu_node`, `panel_node`, `pick_node`, `hover_panel_node`): single-layer iOS 27 liquid glass (`glass_menu()`),
// automatic solid fallback (`panel_ground()` + 1 pt `panel_edge()`) when `MBUI_GLASS=solid`, outside-only
// `glass_overlay_shadow()` (`shadow_outside(Is(true))` so outer shadows never bleed inside glass), `r_menu` corner
// radius, clipping, `FromBeside` pop motion, and `ground_node` input boundary.
//
// Popovers (`menu_node`) anchored to a button inside a liquid glass `bar_pill_group_node` (`glass_pill_trigger_lent`)
// execute the 1:1 CADisplayLink-calibrated iOS 27.0 `LiquidMorphPhysics` engine (`@lg` `liquid_morph_physics.mbt`):
// - Open (`420ms` linear phase clock driving critically damped `omega0=26.0, zeta=1.0` spring): luminous crystal
//   droplet (`0x4E`, `blur=1.6`) blooms from the contracting trigger capsule with scaled blurred content (`content_lens`)
//   and settles with zero `kind == 8` overhead at rest;
// - Close (`610ms` linear phase clock): `0..~285ms` teardrop contraction + gap-gated Blob A emergence & SDF neck
//   fusion + parallel `-9.5pt` peak upward trigger recoil (`t ≈ 213ms`) and impact scale (`~0.965`), handing off
//   cleanly at `raw <= 0.045` to the real trigger pill for `285..610ms` recoil return and `+1.6%` horizontal splash.
// Non-pill buttons and `1×1` point anchors keep the original `FromBeside` (`0.97..1.0`) pop motion.

///|
/// Shared pill-morph state lent from `anchored_popover_bridge` to `anchored_popover_shell` and `popover_content_motion`.
priv struct PillMorphState {
  along : @ui.Along
  pill_layer : Int
  ah : Double
  pill_pad : Double
  pill_x : Double
  pill_y : Double
  pill_w : Double
  pill_h : Double
  tx_win : Double
  is_closing : @signals.Signal[Bool]
  t_way : @motion.NodeWay
  shell_ref : Ref[@view.View?]
}

///|
let pill_morph_lent : @view.Lent[PillMorphState] = @view.Lent::new()

///|
fn pill_morph_eval(
  pm : PillMorphState,
  px_win : Double,
  py_win : Double,
  menu_w : Double,
  menu_h : Double,
  closing : Bool,
  t : Double,
) -> @lg.LiquidMorphFrame {
  let align_x = match pm.along {
    Start => -1.0
    End => 1.0
    Middle => 0.0
  }
  @lg.lm_eval_pill_morph(
    pm.pill_x,
    pm.pill_y,
    pm.pill_w,
    pm.pill_h,
    pm.tx_win,
    px_win,
    py_win,
    menu_w,
    menu_h,
    r_menu,
    align_x,
    closing,
    t,
  )
}

///|
fn pill_morph_shell_bounds(pm : PillMorphState) -> (Double, Double, Double, Double) {
  match pm.shell_ref.val {
    Some(shell) => {
      let (px, py, w, h) = shell.placed_window_now()
      if w > 0.0 && h > 0.0 {
        (px, py, w, h)
      } else {
        (pm.pill_x, pm.pill_y, dmax(pm.pill_w, 180.0), 220.0)
      }
    }
    None => (pm.pill_x, pm.pill_y, dmax(pm.pill_w, 180.0), 220.0)
  }
}

///|
/// Content opacity for popover bodies (`menu_node`, `panel_node`, `pick_node`): when GPU `content_lens` is active
/// (`content_opacity > 0.01 && content_blur > 0.05`), returns `1.0` so `content_lens` owns linear opacity + blur
/// without double-multiplying alpha.
fn popover_content_alpha(p : @view.View, node : @view.View, fallback : () -> Double) -> Double {
  match p.lent(pill_morph_lent) {
    Some(pm) => {
      let t = pm.t_way.shown(node)
      let closing = pm.is_closing.get()
      let (px_win, py_win, w, h) = p.placed_window_now()
      let f = pill_morph_eval(pm, px_win, py_win, dmax(w, 1.0), dmax(h, 1.0), closing, t)
      let lens_on = !p.glass_solid() && f.content_opacity > 0.01 && f.content_blur > 0.05
      if f.content_opacity <= 0.01 {
        0.0
      } else if lens_on {
        1.0
      } else {
        f.content_opacity
      }
    }
    None => fallback()
  }
}

///|
/// Scaled + droplet-centered content reveal for pill-anchored popovers (`contentScale = clamp(cur_w / menu_w, 0.20, 1.0)`,
/// centered inside `(mx, my, cur_w, cur_h)` so rows scale smoothly with the morphing capsule without clipping or colliding).
fn popover_content_motion(p : @view.View, node : @view.View, fallback : () -> Double) -> Unit {
  node.alpha(By(fn() { popover_content_alpha(p, node, fallback) })) |> ignore
  match p.lent(pill_morph_lent) {
    Some(pm) if !p.glass_solid() => {
      node.scale(
        By(fn() {
          let t = pm.t_way.shown(node)
          let closing = pm.is_closing.get()
          if !closing && t >= @lg.lm_open_duration_ms / 1000.0 - 0.001 {
            1.0
          } else {
            let (px_win, py_win, w, h) = p.placed_window_now()
            if w <= 0.0 || h <= 0.0 {
              1.0
            } else {
              let f = pill_morph_eval(pm, px_win, py_win, w, h, closing, t)
              dclamp(f.cur_w / w, 0.20, 1.0)
            }
          }
        }),
        about=At(0.5, 0.5),
      )
      |> ignore
      node.offset(
        By(fn() {
          let t = pm.t_way.shown(node)
          let closing = pm.is_closing.get()
          if !closing && t >= @lg.lm_open_duration_ms / 1000.0 - 0.001 {
            (0.0, 0.0)
          } else {
            let (px_win, py_win, w, h) = p.placed_window_now()
            if w <= 0.0 || h <= 0.0 {
              (0.0, 0.0)
            } else {
              let f = pill_morph_eval(pm, px_win, py_win, w, h, closing, t)
              (f.mx + f.cur_w * 0.5 - w * 0.5, f.my + f.cur_h * 0.5 - h * 0.5)
            }
          }
        }),
      )
      |> ignore
    }
    _ => ()
  }
}

///|
/// Smooth capillary liquid-bridge merge radius (pt) during popover entrance/exit scale motion (`look.sx < 0.9999`):
/// aligned to `glass_pop_in`'s `0.97..1.0` span (`0.03`) with a root-shaped curve (`s * 0.6 + s.sqrt() * 0.4`).
pub fn popover_bridge_merge(look : @ui.Look) -> Double {
  if look.alpha > 0.001 && look.sx < 0.9999 {
    let rem = dclamp((1.0 - look.sx) / 0.03, 0.0, 1.0)
    if rem > 0.003 {
      let s = rem.sqrt()
      let k = s * 0.6 + s.sqrt() * 0.4
      40.0 * k
    } else {
      0.0
    }
  } else {
    0.0
  }
}

///|
/// Full-body liquid-glass scale factor (`0.28 <-> 1.00`) for a non-pill button-anchored popover so it emerges from
/// and retracts back into its anchor button across the standard `pop_ms` / `pop_out_ms` transition.
pub fn popover_bridge_scale(look : @ui.Look) -> Double {
  if look.sx >= 0.9999 {
    1.0
  } else {
    let rem = dclamp((1.0 - look.sx) / 0.03, 0.0, 1.0)
    let f = 0.45 * rem + 0.55 * rem.sqrt()
    1.0 - 0.72 * f
  }
}

///|
/// High-presence opacity curve for a non-pill button-anchored liquid-glass popover.
pub fn popover_bridge_alpha(look : @ui.Look) -> Double {
  if look.alpha <= 0.001 {
    0.0
  } else if look.sx >= 0.9999 {
    look.alpha
  } else {
    let rem = dclamp((1.0 - look.sx) / 0.03, 0.0, 1.0)
    let a = 1.0 - rem * rem.sqrt()
    dmin(a, dmin(look.alpha * 3.0, 1.0))
  }
}

///|
/// Configures anchored popover liquid morphing on `layer` immediately before the popover shell (`menu_node`):
/// - Branch A (liquid glass `bar_pill_group_node` trigger): lends `pill_morph_lent` driving 1:1 iOS 27.0
///   `LiquidMorphPhysics` (trigger pill recoil, impact compression, horizontal splash, Blob A/B SDF fusion, and
///   `holds_leaving=true` sentinel through `610ms` close settle; 0 new cold-start bindings).
/// - Non-pill buttons, `1×1` point anchors, and `MBUI_GLASS=solid`: no-op, preserving original `FromBeside` (`0.97..1.0`).
#callsite(autofill(loc))
pub fn anchored_popover_bridge(
  layer : @view.View,
  anchor : @view.View,
  look : () -> @ui.Look,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = panel_offset,
  loc~ : SourceLoc,
) -> Unit {
  ignore(look)
  ignore(side)
  ignore(offset)
  let (ax, _, aw, ah) = anchor.placed_window_now()
  if aw < 16.0 || ah < 16.0 || layer.glass_solid() {
    return
  }
  match anchor.lent(glass_pill_trigger_lent) {
    Some(trig) => {
      let pill_h = trig.height
      let pill_pad = trig.pad
      let pill_layer = trig.pill.id().at + 100
      let (pill_x, pill_y, pill_w_raw, pill_h_raw) = trig.pill.placed_window_now()
      let pill_h_eff = if pill_h_raw > 0.0 { pill_h_raw } else { pill_h }
      let pill_w = dmax(pill_w_raw, pill_h_eff)
      let tx_win = ax + aw * 0.5
      let tx_mid = dclamp(tx_win - pill_x, pill_h_eff * 0.5, dmax(pill_h_eff * 0.5, pill_w - pill_h_eff * 0.5))
      let is_closing = @signals.signal(false)
      let t_way = @motion.NodeWay::new(0.0)
      let shell_ref : Ref[@view.View?] = Ref(None)
      let pm : PillMorphState = {
        along,
        pill_layer,
        ah,
        pill_pad,
        pill_x,
        pill_y,
        pill_w,
        pill_h: pill_h_eff,
        tx_win,
        is_closing,
        t_way,
        shell_ref,
      }
      let eval_trig = fn() -> (Double, Bool, @lg.LiquidMorphFrame) {
        let t = t_way.shown(trig.pill)
        let closing = is_closing.get()
        let (px_win, py_win, mw, mh) = pill_morph_shell_bounds(pm)
        (t, closing, pill_morph_eval(pm, px_win, py_win, mw, mh, closing, t))
      }
      // Attach trigger pill live morph glass/shadow callbacks & private SDF layer (0 cold-start bindings).
      trig.morph_glass.val = Some(fn() {
        let (t, closing, f) = eval_trig()
        if !closing {
          if f.open_anchor_scale <= 0.15 {
            None
          } else {
            let stage = 0.5 * @lg.lm_smoothstep(0.0, 0.06, t)
            Some(glass_menu_morph(stage, layer=pill_layer, break_gap=32.0))
          }
        } else if f.platter_active {
          if f.blob_a_emerge <= 0.001 {
            None
          } else {
            let stage = 0.5 * @lg.lm_smoothstep(0.0, 0.12, f.raw_value)
            Some(glass_menu_morph(stage, layer=pill_layer, break_gap=48.0))
          }
        } else {
          Some(glass_bar_pill())
        }
      })
      trig.morph_shadow.val = Some(fn() {
        let (_, closing, f) = eval_trig()
        if closing && !f.platter_active {
          glass_control_shadow()
        } else {
          (0.0, 0.0, 0L)
        }
      })
      let (sp0, _) = trig.fx.get()
      trig.fx.set((sp0, pill_layer))
      trig.pill.offset(
        By(fn() {
          let (_, closing, f) = eval_trig()
          if closing {
            (0.0, f.push_dy)
          } else {
            (0.0, 0.0)
          }
        }),
      )
      |> ignore
      trig.pill.scale(
        By(fn() {
          let (t, closing, f) = eval_trig()
          if closing {
            @lg.lm_impact_scale(t, f.final_dy.abs())
          } else {
            1.0 + 0.05 * trig.press_way.shown(trig.pill)
          }
        }),
        about=At(0.5, 0.5),
      )
      |> ignore
      trig.pill.ground_drawn(
        By(fn() {
          let (t, closing, f) = eval_trig()
          if !closing {
            let wp = @lg.lm_open_trigger_width(t)
            let cw = @lg.lm_lerp(pill_h_eff, pill_w, wp)
            let cx = @lg.lm_lerp(tx_mid, pill_w * 0.5, wp)
            let r = dmin(cw, pill_h_eff) * 0.5
            { dx: cx - cw * 0.5, dy: 0.0, dw: cw - pill_w, dh: 0.0, corners: Some((r, r, r, r)) }
          } else if f.platter_active {
            let wp = @lg.lm_delayed_close_width(t)
            let cw = @lg.lm_lerp(pill_h_eff, pill_w, wp)
            let cx = @lg.lm_lerp(tx_mid, pill_w * 0.5, dclamp(wp, 0.0, 1.0))
            let r = dmin(cw, pill_h_eff) * 0.5
            {
              dx: cx - cw * 0.5,
              dy: 0.0,
              dw: cw - pill_w,
              dh: 0.0,
              corners: Some((r, r, r, r)),
            }
          } else {
            let raw_scale = @lg.lm_lerp(pill_h_eff, pill_w, @lg.lm_close_trigger_width(t)) / pill_w
            let cw = pill_w * dclamp(raw_scale, 0.90, 1.04)
            let r = pill_h_eff * 0.5
            { dx: (pill_w - cw) * 0.5, dy: 0.0, dw: cw - pill_w, dh: 0.0, corners: Some((r, r, r, r)) }
          }
        }),
      )
      |> ignore
      trig.pill.alpha(
        By(fn() {
          let (_, closing, f) = eval_trig()
          if !closing {
            if f.open_anchor_scale <= 0.15 { 0.0 } else { 1.0 }
          } else if f.platter_active {
            if f.blob_a_emerge <= 0.001 { 0.0 } else { 1.0 }
          } else {
            1.0
          }
        }),
      )
      |> ignore
      let bound_children = trig.children.copy()
      for child in bound_children {
        let (cx0, _, cw0, _) = child.placed_window_now()
        let child_cx_local = cx0 + cw0 * 0.5 - pill_x
        let child_cx_off = child_cx_local - pill_w * 0.5
        let child_to_tx = tx_mid - child_cx_local
        child.alpha(
          By(fn() {
            let t = t_way.shown(child)
            if is_closing.get() {
              if t < 0.19 { 0.0 } else { @lg.lm_smoothstep(0.19, 0.275, t) }
            } else {
              1.0 - @lg.lm_smoothstep(0.0, 0.032, t)
            }
          }),
        )
        |> ignore
        child.offset(
          By(fn() {
            let t = t_way.shown(child)
            if !is_closing.get() {
              let wp = @lg.lm_open_trigger_width(t)
              (child_to_tx * (1.0 - wp) * 0.45, 0.0)
            } else {
              let raw = @lg.lm_close_progress(t)
              if @lg.lm_close_platter_active(raw) {
                let blob_a_w = @lg.lm_lerp(pill_h_eff, pill_w, @lg.lm_delayed_close_width(t))
                (-child_cx_off * (1.0 - dclamp(blob_a_w / pill_w, 0.5, 1.0)), 0.0)
              } else {
                (0.0, 0.0)
              }
            }
          }),
        )
        |> ignore
      }
      layer.owns(fn() {
        let (sp, ly) = trig.fx.get()
        if ly == pill_layer || ly < 0 {
          trig.morph_glass.val = None
          trig.morph_shadow.val = None
          trig.fx.set((sp, 0))
        }
        trig.pill.scale(By(fn() { 1.0 + 0.05 * trig.press_way.shown(trig.pill) }), about=At(0.5, 0.5)) |> ignore
        trig.pill.offset(Is((0.0, 0.0))) |> ignore
        trig.pill.ground_drawn(Is(@view.ground_as_laid)) |> ignore
        trig.pill.alpha(Is(1.0)) |> ignore
        for child in bound_children {
          child.alpha(Is(1.0)) |> ignore
          child.offset(Is((0.0, 0.0))) |> ignore
        }
      })
      |> ignore
      layer.reacts(fn() { layer.leaving() }, fn(leaving) {
        if leaving {
          is_closing.set(true)
          let (sp, _) = trig.fx.get()
          trig.fx.set((sp, pill_layer))
          t_way.go_from(
            layer,
            0.0,
            @lg.lm_close_duration_ms / 1000.0,
            @motion.tween(@lg.lm_close_duration_ms, ease=@ui.Ease::Linear),
          )
        } else {
          t_way.go_from(
            layer,
            0.0,
            @lg.lm_open_duration_ms / 1000.0,
            @motion.tween(@lg.lm_open_duration_ms, ease=@ui.Ease::Linear),
          )
        }
      })
      layer.lends(pill_morph_lent, pm) |> ignore
      // Dynamic leave-hold sentinel so the full 610ms close recoil + horizontal splash completes before unmount.
      layer.box(made_for=loc, fn(hold) {
        hold
        .over(Is(true))
        .points(Is(false))
        .width(Is(Some(0.0)))
        .height(Is(Some(0.0)))
        .moved_by(fn(_, _, _) { (0.0, 0.0) }, fn(_, _) { t_way.ends_at() }, holds_leaving=true)
        |> ignore
      })
      |> ignore
    }
    None => ()
  }
}

///|
/// Configures `p` as the shared visual shell for an anchored popover beside `anchor_id`:
/// single-layer liquid glass (`glass_menu()`), solid hairline fallback when `p.glass_solid()` is true,
/// outside-only `glass_overlay_shadow()`, `r_menu` corner radius, clipping, `FromBeside` alpha/scale motion from `look`
/// (or full 1:1 iOS 27.0 `LiquidMorphPhysics` when `menu_node` is anchored to `bar_pill_group_node`), and
/// `ground_node` press boundary.
/// - `holds_side`: keeps the chosen side while it still fits (default `true`; pass `false` for `menu_node`).
/// - `concentric_inset`: when `>= 0.0`, registers `corner_card_node(p, fn() { r_menu }, inset=fn() { concentric_inset })`.
pub fn anchored_popover_shell(
  p : @view.View,
  anchor_id : @view.NodeId,
  look : () -> @ui.Look,
  side? : @ui.Side = Bottom,
  along? : @ui.Along = Start,
  offset? : Double = panel_offset,
  holds_side? : Bool = true,
  concentric_inset? : Double = -1.0,
) -> @view.View {
  let (eff_offset, eff_along_offset) = match p.lent(pill_morph_lent) {
    Some(pm) if !p.glass_solid() => {
      pm.shell_ref.val = Some(p)
      let off = match side {
        Bottom | Top => -(pm.ah + pm.pill_pad)
        Left | Right => offset
      }
      let aoff = match along {
        End => pm.pill_pad
        Start => -pm.pill_pad
        Middle => 0.0
      }
      (off, aoff)
    }
    _ => (offset, 0.0)
  }
  p
  .beside(
    anchor_id,
    side~,
    along=view_along(along),
    offset=eff_offset,
    along_offset=eff_along_offset,
    padding=8.0,
    holds_side~,
  )
  .radius(Is(r_menu))
  .edge(By(fn() { if p.glass_solid() { (1.0, panel_edge()) } else { (0.0, 0L) } }))
  .shadow_outside(Is(true))
  .clips(Is(true))
  |> ignore
  match p.lent(pill_morph_lent) {
    Some(pm) if !p.glass_solid() => {
      let eval_shell = fn() -> (Double, Bool, Double, Double, @lg.LiquidMorphFrame) {
        let t = pm.t_way.shown(p)
        let closing = pm.is_closing.get()
        let (px_win, py_win, w, h) = p.placed_window_now()
        let f = pill_morph_eval(pm, px_win, py_win, dmax(w, 1.0), dmax(h, 1.0), closing, t)
        (t, closing, w, h, f)
      }
      p
      .alpha(
        By(fn() {
          let (_, closing, _, _, f) = eval_shell()
          if !closing {
            if f.raw_value <= 0.001 { 0.0 } else { 1.0 }
          } else if !f.platter_active {
            0.0
          } else {
            1.0
          }
        }),
      )
      .glass(
        By(fn() {
          let (t, closing, _, _, f) = eval_shell()
          if !closing {
            if f.raw_value <= 0.001 {
              None
            } else {
              let stage = 0.5 + 0.5 * @lg.lm_smoothstep(0.08, 0.20, t)
              if f.open_anchor_scale > 0.15 {
                Some(
                  glass_menu_morph(
                    stage,
                    merge=14.0 * f.open_anchor_scale,
                    layer=pm.pill_layer,
                    break_gap=32.0,
                  ),
                )
              } else {
                Some(glass_menu_morph(stage))
              }
            }
          } else if !f.platter_active {
            None
          } else {
            let stage = 0.5 * @lg.lm_smoothstep(0.0, 0.12, f.raw_value) +
              0.5 * @lg.lm_smoothstep(0.35, 0.95, f.raw_value)
            if f.blob_a_emerge > 0.001 {
              Some(
                glass_menu_morph(
                  stage,
                  merge=@lg.lm_close_blend(f.raw_value),
                  layer=pm.pill_layer,
                  break_gap=48.0,
                ),
              )
            } else {
              Some(glass_menu_morph(stage))
            }
          }
        }),
      )
      .content_lens(
        By(fn() {
          let (_, _, _, _, f) = eval_shell()
          if f.content_opacity > 0.01 && f.content_blur > 0.05 {
            {
              blur: f.content_blur,
              refraction: 6.0 * dclamp(f.content_blur / 8.0, 0.0, 1.0),
              bezel: 24.0,
              alpha: f.content_opacity,
            }
          } else {
            @paint.ContentLens::none()
          }
        }),
      )
      .shadow(
        By(fn() {
          let (_, closing, _, _, f) = eval_shell()
          if closing && !f.platter_active {
            (0.0, 0.0, 0L)
          } else {
            let ga = @lg.lm_smoothstep(0.25, 0.78, dclamp(f.raw_value, 0.0, 1.0))
            if ga <= 0.001 {
              (0.0, 0.0, 0L)
            } else {
              let (s, dy, ink) = glass_overlay_shadow()
              (s, dy, alpha(ink, ga))
            }
          }
        }),
      )
      .ground_drawn(
        By(fn() {
          let (t, closing, w, h, f) = eval_shell()
          if w <= 0.0 || h <= 0.0 || (!closing && t >= @lg.lm_open_duration_ms / 1000.0 - 0.001) {
            @view.ground_as_laid
          } else {
            let r = f.radius
            { dx: f.mx, dy: f.my, dw: f.cur_w - w, dh: f.cur_h - h, corners: Some((r, r, r, r)) }
          }
        }),
      )
      |> ignore
    }
    _ =>
      p
      .glass(By(fn() { Some(glass_menu()) }))
      .shadow(By(fn() { glass_overlay_shadow() }))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }), about=FromBeside, max_shift=pop_max_shift)
      |> ignore
  }
  if concentric_inset >= 0.0 {
    corner_card_node(p, fn() { r_menu }, inset=fn() { concentric_inset })
  }
  ground_node(p)
}

///|
/// Preferred side (`Top` or `Bottom`) for an anchored popover beside `anchor`: opens upward when space below `anchor`
/// is smaller than `need` and there is more room above than below.
pub fn beside_side_for(anchor : @view.View, need? : Double = 360.0) -> @ui.Side {
  let (_, y, _, h) = anchor.placed_window_now()
  let under = anchor.window_h() - (y + h)
  if under < need && y > under {
    Top
  } else {
    Bottom
  }
}
