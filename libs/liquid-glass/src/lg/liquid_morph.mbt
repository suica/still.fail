// Apple iOS 26/27 Liquid Glass Menu Morph with zero-double-glass trigger handoff,
// C2-continuous emergence, physically gap-driven GPU SDF capillary bridge (`merged_liquid`),
// and zero-cliff pinch-off for anchored floating overlays (`liquid_menu_node`,
// `liquid_select_node`, `liquid_popover_node`).
//
// Architecture (closed-form `@motion.NodeWay`, 60/120/24/7 fps invariant):
// - When `trigger_face` is provided (`OvlMorphHandoff`), the original `trigger` hides (`alpha=0`)
//   during `is_bridging` (`gap < ovl_morph_break_gap`) while `trigger_ghost` + `shell` render as ONE
//   single-layer GPU `merged_liquid` SDF using the trigger's exact glass recipe (`blur=2.1, bezel=14,
//   refraction=18, rim=0.6`), and `trigger_face_box` draws the razor-sharp icon/label ON TOP of the
//   glass (after `shell`, never breaking glass batching).
// - At `gap >= 5.8pt`, `is_bridging` flips `false` in the exact same frame on both `trigger` and
//   `host`: `trigger_ghost` (`m≈0`, trigger recipe) hands off pixel-identically to the real `trigger`,
//   while `shell` smoothly transitions its material to `ovl_panel_glass()` via `material_way` (150ms).

///|
/// Leave duration (ms) passed to `pop.layer(..., leave=ovl_morph_leave_ms)` so the closing capillary
/// re-absorption (`snappy_damped` from 1.0 to `ovl_morph_handoff_p` takes ~274ms) completes cleanly before unmount.
let ovl_morph_leave_ms : Double = 340.0

///|
/// Progress threshold at which the closing morph shell has already converged 0.00px onto `trigger_ghost`,
/// allowing `shell` to turn off and `is_bridging` to hand off pixel-identically to the real `trigger`.
let ovl_morph_handoff_p : Double = 0.025

///|
/// Peak GPU smooth-min metaball merge radius (pt) between `trigger_ghost` and `shell` while bonded.
let ovl_morph_merge_max : Double = 28.0

///|
/// Physical air gap (pt) at which `merge` reaches `0.0` (natural SDF pinch-off occurs earlier near `m == 2 * gap`).
let ovl_morph_break_gap : Double = 5.8

///|
/// Physical air gap (pt) at which fallback `trigger_ghost` (when `trigger_face` is None) completes fade-out.
let ovl_morph_ghost_gone_gap : Double = 7.6

///|
/// Independent content reveal timing (ms): delayed so text fades in softly over ~10 frames once the shell opens,
/// and fades out first over 65ms when closing.
let ovl_morph_reveal_open_ms : Double = 160.0

///|
let ovl_morph_reveal_delay_ms : Double = 170.0

///|
let ovl_morph_reveal_close_ms : Double = 65.0

///|
/// Post-pinch material transition timing (ms): `shell` glides from trigger-matched clear glass to `ovl_panel_glass()`.
let ovl_morph_mat_open_ms : Double = 150.0

///|
let ovl_morph_mat_delay_ms : Double = 190.0

///|
let ovl_morph_mat_close_ms : Double = 45.0

///|
/// GLSL-style cubic Hermite smoothstep supporting both rising (`edge0 < edge1`) and falling (`edge0 > edge1`) ramps.
fn ovl_smoothstep(edge0 : Double, edge1 : Double, x : Double) -> Double {
  if edge0 == edge1 {
    return if x >= edge1 { 1.0 } else { 0.0 }
  }
  let u = clamp((x - edge0) / (edge1 - edge0), 0.0, 1.0)
  u * u * (3.0 - 2.0 * u)
}

///|
/// Exact scale pivot `(ox, oy)` aligned to the trigger's `(side, along)` anchor for content reveal.
fn ovl_morph_pivot(side : @view.Side, along : @view.Along) -> @view.Pivot {
  let ax = match along {
    Start => 0.12
    End => 0.88
    Middle => 0.5
  }
  let ay = match along {
    Start => 0.15
    End => 0.85
    Middle => 0.5
  }
  match side {
    Bottom => At(ax, 0.0)
    Top => At(ax, 1.0)
    Right => At(0.0, ay)
    Left => At(1.0, ay)
  }
}

///|
/// Closed-form physical edge gap (pt) between trigger and morphing shell, independent of panel size `(w, h)`.
/// Allows both the original `trigger` and the overlay `host` to evaluate bit-identical `gap` in the same frame.
fn ovl_morph_gap(side : @view.Side, anchor_size : (Double, Double), p : Double) -> Double {
  let pt = clamp((p - ovl_morph_handoff_p) / (1.0 - ovl_morph_handoff_p), 0.0, 1.0)
  let axis = match side {
    Bottom | Top => anchor_size.1
    Right | Left => anchor_size.0
  }
  (ovl_float_gap + axis) * pt - axis
}

///|
/// Continuous capillary bridge merge radius (pt) driven strictly by physical edge gap `gap`:
/// - `gap >= ovl_morph_break_gap` or `p <= ovl_morph_handoff_p`: strictly `0.0`.
/// - `gap <= 0.0`: ramps smoothly via `onset = ovl_smoothstep(ovl_morph_handoff_p, 0.24, p)`.
/// - `0.0 < gap < ovl_morph_break_gap`: decays continuously from `28.0` to `0.0` with zero cliff.
fn ovl_morph_bridge_merge_for_gap(p : Double, gap : Double) -> Double {
  if gap >= ovl_morph_break_gap || p <= ovl_morph_handoff_p {
    return 0.0
  }
  let onset = ovl_smoothstep(ovl_morph_handoff_p, 0.24, p)
  if gap <= 0.0 {
    let m = ovl_morph_merge_max * onset
    if m < 0.02 { 0.02 } else { m }
  } else {
    ovl_morph_merge_max * (1.0 - ovl_smoothstep(0.0, ovl_morph_break_gap, gap)) * onset
  }
}

///|
/// Trigger-matched clear Liquid Glass recipe used during capillary bridging (`blur=2.1, bezel=14, refraction=18,
/// rim=0.6, chroma=0.0`), matching `lib_nav_menu_trigger` bit-for-bit so pinch-off handoff has zero pixel pop.
fn ovl_morph_bridge_glass(merge~ : Double) -> @paint.Glass {
  let d = is_dark()
  let m = if merge > 0.0 { merge } else { 0.0 }
  @paint.Glass::liquid(
    blur=2.1,
    tint=if d { 0x20202067L } else { 0xFDFCFD67L },
    solid=if d { 0x1E1F24FFL } else { 0xFAFAFAFFL },
    saturation=1.0,
    rim=0.6,
    bezel=14.0,
    refraction=18.0,
    chroma=0.0,
    merge=m,
    adaptive=false,
  )
}

///|
/// Panel shell glass recipe: returns bit-identical `ovl_morph_bridge_glass(merge~)` while `merge > 0.01`
/// (guaranteeing GPU `merged_liquid` batching & 0-diff handoff at pinch-off), then glides smoothly along
/// `min(mat_t, smoothstep(break_gap, float_gap - 0.1, gap))` to `ovl_panel_glass()` (`blur 2.1->8.0,
/// bezel 14->20, refraction 18->36`) so both opening and closing re-bonding have zero blur pop.
fn ovl_morph_shell_glass(mat_t : Double, gap : Double, merge~ : Double) -> @paint.Glass {
  if merge > 0.01 {
    return ovl_morph_bridge_glass(merge~)
  }
  let mt = clamp(mat_t, 0.0, 1.0)
  let gt = ovl_smoothstep(ovl_morph_break_gap, ovl_float_gap - 0.1, gap)
  let t = if mt < gt { mt } else { gt }
  if t >= 0.999 {
    return ovl_panel_glass()
  }
  liquid_menu_morph_glass(0.5 + 0.5 * t)
}

///|
/// Closed-form trigger recoil way: fires a crisp `0.94 -> 1.0` tactile bounce when `open` transitions to `true`.
fn ovl_trigger_recoil_way(trigger : @view.View, open : () -> Bool) -> @motion.NodeWay {
  let way = @motion.NodeWay::new(1.0)
  trigger.reacts(at_start=false, open, fn(is_open) {
    if is_open {
      way.go_from(trigger, 0.94, 1.0, @motion.tactile_bounce)
    }
  })
  way
}

///|
/// Shared handoff handle linking a trigger node and its overlay layer so both read the exact same `p_way`
/// and flip `is_bridging` in the exact same frame (zero double-glass stacking, zero icon blur).
priv struct OvlMorphHandoff {
  trigger : @view.View
  p_way : @motion.NodeWay
  side : @view.Side
  anchor_size : (Double, Double)
  live_anchor : Ref[(Double, Double)]
  open : () -> Bool
  trigger_face : ((@view.View) -> Unit)?
  attach_recoil : Bool
  layer_live : Ref[() -> Bool]
}

///|
fn OvlMorphHandoff::is_bridging(self : OvlMorphHandoff, node : @view.View) -> Bool {
  let p = self.p_way.shown(node)
  let gap = ovl_morph_gap(self.side, self.live_anchor.val, p)
  let active = (self.layer_live.val)()
  active && gap < ovl_morph_break_gap && ((self.open)() || p > ovl_morph_handoff_p)
}

///|
/// Creates a shared handoff handle and wires the trigger's visibility / recoil:
/// - With `trigger_face`: hides original `trigger` (`alpha=0`) during `is_bridging` while keeping its outer
///   glass box unscaled (`scale=1.0`) for 0.00px alignment at handoff.
/// - Without `trigger_face`: attaches the standard tactile recoil (`0.94 -> 1.0`) to `trigger`.
fn ovl_setup_trigger_handoff(
  trigger : @view.View,
  open : () -> Bool,
  side : @view.Side,
  anchor_size : (Double, Double),
  trigger_face : ((@view.View) -> Unit)?,
  attach_recoil? : Bool = true,
) -> OvlMorphHandoff {
  let handoff : OvlMorphHandoff = {
    trigger,
    p_way: @motion.NodeWay::new(0.0),
    side,
    anchor_size,
    live_anchor: Ref(anchor_size),
    open,
    trigger_face,
    attach_recoil,
    layer_live: Ref(fn() { false }),
  }
  match trigger_face {
    Some(_) =>
      trigger.alpha(By(fn() { if handoff.is_bridging(trigger) { 0.0 } else { 1.0 } })) |> ignore
    None =>
      if attach_recoil {
        let way = ovl_trigger_recoil_way(trigger, open)
        trigger.scale(By(fn() { way.shown(trigger) })) |> ignore
      }
  }
  handoff
}

///|
/// Exact trigger button rect `(tx, ty, tw, th, tr)` in the unscaled `panel` coordinate space `(0, 0, w, h)`.
fn ovl_morph_trigger_rect(
  w : Double,
  h : Double,
  side : @view.Side,
  along : @view.Along,
  anchor_size : (Double, Double),
) -> (Double, Double, Double, Double, Double) {
  let tw = anchor_size.0
  let th = anchor_size.1
  let tr = th * 0.5
  let ax = match along {
    Start => 0.0
    End => w - tw
    Middle => (w - tw) * 0.5
  }
  let ay = match along {
    Start => 0.0
    End => h - th
    Middle => (h - th) * 0.5
  }
  let (tx, ty) = match side {
    Bottom => (ax, -ovl_float_gap - th)
    Top => (ax, h + ovl_float_gap)
    Right => (-ovl_float_gap - tw, ay)
    Left => (w + ovl_float_gap, ay)
  }
  (tx, ty, tw, th, tr)
}

///|
/// Computes both the morphing panel `GroundShape` and the exact physical edge gap `gap` (pt) between the
/// trigger and the morphing shell (`gap < 0` overlapping, `gap == 0` touching, `gap > 0` clean air gap).
/// Starts 100% coincident with the trigger rect at `pt = 0` (`C2` continuous, 0px first-frame jump) with
/// coordinated proportional droplet growth so the emerging droplet stays round and never clips neighbors.
fn ovl_morph_shell_geom(
  w : Double,
  h : Double,
  side : @view.Side,
  along : @view.Along,
  anchor_size : (Double, Double),
  panel_radius : Double,
  sx : Double,
  sy : Double,
  p : Double,
) -> (@view.GroundShape, Double) {
  if (sx - 1.0).abs() < 0.001 && (sy - 1.0).abs() < 0.001 && (p - 1.0).abs() < 0.001 {
    return (@view.ground_as_laid, ovl_float_gap)
  }
  if w <= 0.0 || h <= 0.0 {
    return (@view.ground_as_laid, ovl_float_gap)
  }
  let (tx, ty, tw, th, tr) = ovl_morph_trigger_rect(w, h, side, along, anchor_size)
  let remap_scale = fn(v : Double) -> Double {
    let u = (v - ovl_morph_handoff_p) / (1.0 - ovl_morph_handoff_p)
    if u > 0.0 { u } else { 0.0 }
  }
  let px = remap_scale(sx)
  let py = remap_scale(sy)
  let pt = clamp((p - ovl_morph_handoff_p) / (1.0 - ovl_morph_handoff_p), 0.0, 1.0)
  let (mx, my, mw, mh, gap) = match side {
    Bottom => {
      let y = lerp(ty, 0.0, pt)
      let g = y - (ty + th)
      let clear_t = ovl_smoothstep(-th * 0.65, ovl_float_gap, g)
      let grow_w = lerp(px * 0.22, px, clear_t)
      let grow_h = lerp(py * 0.32, py, ovl_smoothstep(-th * 0.75, ovl_float_gap, g))
      let raw_mw = lerp(tw, w, grow_w)
      let raw_mh = lerp(th, h, grow_h)
      let cur_w = if raw_mw > 4.0 { raw_mw } else { 4.0 }
      let cur_h = if raw_mh > 4.0 { raw_mh } else { 4.0 }
      let x = match along {
        Start => 0.0
        End => w - cur_w
        Middle => (w - cur_w) * 0.5
      }
      (x, y, cur_w, cur_h, g)
    }
    Top => {
      let bot = lerp(ty + th, h, pt)
      let g = ty - bot
      let clear_t = ovl_smoothstep(-th * 0.65, ovl_float_gap, g)
      let grow_w = lerp(px * 0.22, px, clear_t)
      let grow_h = lerp(py * 0.32, py, ovl_smoothstep(-th * 0.75, ovl_float_gap, g))
      let raw_mw = lerp(tw, w, grow_w)
      let raw_mh = lerp(th, h, grow_h)
      let cur_w = if raw_mw > 4.0 { raw_mw } else { 4.0 }
      let cur_h = if raw_mh > 4.0 { raw_mh } else { 4.0 }
      let x = match along {
        Start => 0.0
        End => w - cur_w
        Middle => (w - cur_w) * 0.5
      }
      (x, bot - cur_h, cur_w, cur_h, g)
    }
    Right => {
      let x = lerp(tx, 0.0, pt)
      let g = x - (tx + tw)
      let clear_t = ovl_smoothstep(-tw * 0.65, ovl_float_gap, g)
      let grow_h = lerp(py * 0.22, py, clear_t)
      let grow_w = lerp(px * 0.32, px, ovl_smoothstep(-tw * 0.75, ovl_float_gap, g))
      let raw_mw = lerp(tw, w, grow_w)
      let raw_mh = lerp(th, h, grow_h)
      let cur_w = if raw_mw > 4.0 { raw_mw } else { 4.0 }
      let cur_h = if raw_mh > 4.0 { raw_mh } else { 4.0 }
      let y = match along {
        Start => 0.0
        End => h - cur_h
        Middle => (h - cur_h) * 0.5
      }
      (x, y, cur_w, cur_h, g)
    }
    Left => {
      let r_edge = lerp(tx + tw, w, pt)
      let g = tx - r_edge
      let clear_t = ovl_smoothstep(-tw * 0.65, ovl_float_gap, g)
      let grow_h = lerp(py * 0.22, py, clear_t)
      let grow_w = lerp(px * 0.32, px, ovl_smoothstep(-tw * 0.75, ovl_float_gap, g))
      let raw_mw = lerp(tw, w, grow_w)
      let raw_mh = lerp(th, h, grow_h)
      let cur_w = if raw_mw > 4.0 { raw_mw } else { 4.0 }
      let cur_h = if raw_mh > 4.0 { raw_mh } else { 4.0 }
      let y = match along {
        Start => 0.0
        End => h - cur_h
        Middle => (h - cur_h) * 0.5
      }
      (r_edge - cur_w, y, cur_w, cur_h, g)
    }
  }
  let half_min = (if mw < mh { mw } else { mh }) * 0.5
  let raw_r = lerp(tr, panel_radius, pt)
  let mr = if raw_r < half_min { raw_r } else { half_min }
  ({ dx: mx, dy: my, dw: mw - w, dh: mh - h, corners: Some((mr, mr, mr, mr)) }, gap)
}

///|
/// Attaches the physically gap-driven GPU-merged capillary Liquid Glass Menu Morph to `panel` inside `layer`.
/// `panel` stays unscaled with no `.glass`, `.shadow`, or `.clips`; `content` receives `content_box`.
fn ovl_attach_liquid_morph(
  layer : @view.View,
  panel : @view.View,
  side : @view.Side,
  along : @view.Along,
  panel_radius : Double,
  handoff : OvlMorphHandoff,
  content : (@view.View) -> Unit,
) -> () -> Bool {
  let (_, _, pw, ph) = handoff.trigger.placed_now()
  let anchor_size = if pw > 0.0 && ph > 0.0 { (pw, ph) } else { handoff.anchor_size }
  handoff.live_anchor.val = anchor_size
  let has_face = handoff.trigger_face is Some(_)
  let p_way = handoff.p_way
  let sx_way = @motion.NodeWay::new(0.0)
  let sy_way = @motion.NodeWay::new(0.0)
  let reveal_way = @motion.NodeWay::new(0.0)
  let material_way = @motion.NodeWay::new(0.0)
  let icon_recoil_way = @motion.NodeWay::new(1.0)
  handoff.layer_live.val = fn() { layer.alive() && ((handoff.open)() || layer.leaving()) }
  layer.reacts(fn() { layer.leaving() }, fn(leaving) {
    if leaving {
      sx_way.go(layer, 0.0, @motion.snappy_damped)
      sy_way.go(layer, 0.0, @motion.snappy_damped)
      p_way.go(layer, 0.0, @motion.snappy_damped)
      reveal_way.go(layer, 0.0, @motion.tween(ovl_morph_reveal_close_ms, ease=@ui.Ease::Out))
      material_way.go(layer, 0.0, @motion.tween(ovl_morph_mat_close_ms, ease=@ui.Ease::Out))
    } else {
      sx_way.go(layer, 1.0, @motion.backdrop_scale_x_spring)
      sy_way.go(layer, 1.0, @motion.backdrop_scale_y_spring)
      p_way.go(layer, 1.0, @motion.backdrop_scale_y_spring)
      reveal_way.go(
        layer,
        1.0,
        @motion.tween(ovl_morph_reveal_open_ms, ease=@ui.Ease::Out, delay=ovl_morph_reveal_delay_ms),
      )
      material_way.go(
        layer,
        1.0,
        @motion.tween(ovl_morph_mat_open_ms, ease=@ui.Ease::Out, delay=ovl_morph_mat_delay_ms),
      )
      if has_face && handoff.attach_recoil {
        icon_recoil_way.go_from(layer, 0.92, 1.0, @motion.tactile_bounce)
      }
    }
  })
  let modal_live = fn() { !layer.leaving() }
  panel.by_room(fn(inner, room) {
    let content_ref : Ref[@view.View?] = Ref(None)
    let panel_h = fn() -> Double {
      match content_ref.val {
        Some(c) => room.tall(c)
        None => 0.0
      }
    }
    let tw = anchor_size.0
    let th = anchor_size.1
    let tr = th * 0.5
    // 1. Trigger outside-only shadow during handoff (preserves trigger's exact shadow while real trigger is hidden)
    if has_face {
      inner.box(fn(trigger_shadow_box) {
        trigger_shadow_box
        .over(Is(true))
        .points(Is(false))
        .width(Is(Some(tw)))
        .height(Is(Some(th)))
        .radius(Is(tr))
        .shadow_outside(Is(true))
        .offset(
          By(fn() {
            let (tx, ty, _, _, _) = ovl_morph_trigger_rect(
              room.width(),
              panel_h(),
              side,
              along,
              anchor_size,
            )
            (tx, ty)
          }),
        )
        .shadow(
          By(fn() {
            if handoff.is_bridging(trigger_shadow_box) {
              shadow_default
            } else {
              shadow_none
            }
          }),
        )
        |> ignore
      })
      |> ignore
    }
    // 2. Panel outside-only shadow layer (zero `.glass`, never breaks glass batching)
    inner.box(fn(shadow_box) {
      shadow_box
      .over(Is(true))
      .points(Is(false))
      .radius(Is(panel_radius))
      .shadow_outside(Is(true))
      .shadow(
        By(fn() {
          let ga = ovl_smoothstep(0.06, 0.30, p_way.shown(shadow_box))
          if ga <= 0.001 {
            shadow_none
          } else {
            let (s, dy, ink) = shadow_default
            (s, dy, alpha(ink, ga))
          }
        }),
      )
      .ground_drawn(
        By(fn() {
          let (shape, _) = ovl_morph_shell_geom(
            room.width(),
            panel_h(),
            side,
            along,
            anchor_size,
            panel_radius,
            sx_way.shown(shadow_box),
            sy_way.shown(shadow_box),
            p_way.shown(shadow_box),
          )
          shape
        }),
      )
      |> ignore
    })
    |> ignore
    // 3 & 4. Strictly adjacent liquid glass siblings (`trigger_ghost` + `shell`): zero shadow, zero ground,
    //        zero children, bit-identical trigger glass recipe (`blur=2.1, bezel=14, refraction=18, rim=0.6`)
    //        during bridging so Metal / WebGL 2 merges them into ONE SDF `sd_group` with 0-diff handoff.
    inner.box(fn(trigger_ghost) {
      let ghost_alpha = fn() -> Double {
        if has_face {
          if handoff.is_bridging(trigger_ghost) {
            1.0
          } else {
            0.0
          }
        } else {
          let p = p_way.shown(trigger_ghost)
          let ga = ovl_smoothstep(ovl_morph_handoff_p, 0.18, p)
          let gap = ovl_morph_gap(side, anchor_size, p)
          let m = ovl_morph_bridge_merge_for_gap(p, gap)
          if m > 0.01 {
            ga
          } else {
            ga * (1.0 - ovl_smoothstep(ovl_morph_break_gap, ovl_morph_ghost_gone_gap, gap))
          }
        }
      }
      trigger_ghost
      .over(Is(true))
      .points(Is(false))
      .width(Is(Some(tw)))
      .height(Is(Some(th)))
      .radius(Is(tr))
      .offset(
        By(fn() {
          let (tx, ty, _, _, _) = ovl_morph_trigger_rect(
            room.width(),
            panel_h(),
            side,
            along,
            anchor_size,
          )
          (tx, ty)
        }),
      )
      .alpha(By(ghost_alpha))
      .glass(
        By(fn() {
          let p = p_way.shown(trigger_ghost)
          let a = ghost_alpha()
          if a > 0.01 {
            let gap = ovl_morph_gap(side, anchor_size, p)
            let m = ovl_morph_bridge_merge_for_gap(p, gap)
            Some(ovl_morph_bridge_glass(merge=m))
          } else {
            None
          }
        }),
      )
      |> ignore
    })
    |> ignore
    inner.box(fn(shell) {
      shell
      .over(Is(true))
      .points(Is(false))
      .radius(Is(panel_radius))
      .alpha(
        By(fn() {
          let p = p_way.shown(shell)
          if has_face {
            if p <= ovl_morph_handoff_p { 0.0 } else { 1.0 }
          } else {
            ovl_smoothstep(ovl_morph_handoff_p, 0.18, p)
          }
        }),
      )
      .glass(
        By(fn() {
          let p = p_way.shown(shell)
          if has_face && p <= ovl_morph_handoff_p {
            return None
          }
          let ga = if has_face { 1.0 } else { ovl_smoothstep(ovl_morph_handoff_p, 0.18, p) }
          if ga > 0.01 {
            let gap = ovl_morph_gap(side, anchor_size, p)
            let m = ovl_morph_bridge_merge_for_gap(p, gap)
            let mat_t = material_way.shown(shell)
            Some(ovl_morph_shell_glass(mat_t, gap, merge=m))
          } else {
            None
          }
        }),
      )
      .ground_drawn(
        By(fn() {
          let (shape, _) = ovl_morph_shell_geom(
            room.width(),
            panel_h(),
            side,
            along,
            anchor_size,
            panel_radius,
            sx_way.shown(shell),
            sy_way.shown(shell),
            p_way.shown(shell),
          )
          shape
        }),
      )
      |> ignore
    })
    |> ignore
    // 5. Razor-sharp trigger face drawn ON TOP of the merged glass (after `shell`, never breaks glass batching)
    match handoff.trigger_face {
      Some(draw_face) =>
        inner.box(fn(trigger_face_box) {
          trigger_face_box
          .over(Is(true))
          .points(Is(false))
          .width(Is(Some(tw)))
          .height(Is(Some(th)))
          .row(Is(true))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .offset(
            By(fn() {
              let (tx, ty, _, _, _) = ovl_morph_trigger_rect(
                room.width(),
                panel_h(),
                side,
                along,
                anchor_size,
              )
              (tx, ty)
            }),
          )
          .scale(By(fn() { icon_recoil_way.shown(trigger_face_box) }))
          .alpha(By(fn() { if handoff.is_bridging(trigger_face_box) { 1.0 } else { 0.0 } }))
          |> ignore
          draw_face(trigger_face_box)
        })
        |> ignore
      None => ()
    }
    // 6. Foreground content box: smooth reveal with optical focus-in/defocus via `content_lens` (0 resting overhead)
    inner.box(fn(content_box) {
      content_ref.val = Some(content_box)
      content_box
      .scale(
        By(fn() { lerp(0.95, 1.0, reveal_way.shown(content_box)) }),
        about=ovl_morph_pivot(side, along),
      )
      .alpha(
        By(fn() {
          let r = reveal_way.shown(content_box)
          let cblur = 6.5 * (1.0 - r)
          let lens_on = !content_box.glass_solid() && r > 0.01 && cblur > 0.05
          if r <= 0.01 {
            0.0
          } else if lens_on {
            1.0
          } else {
            r
          }
        }),
      )
      .content_lens(
        By(fn() {
          let r = reveal_way.shown(content_box)
          let cblur = 6.5 * (1.0 - r)
          if !content_box.glass_solid() && r > 0.01 && cblur > 0.05 {
            {
              blur: cblur,
              refraction: 6.0 * clamp(cblur / 8.0, 0.0, 1.0),
              bezel: 24.0,
              alpha: r,
            }
          } else {
            @paint.ContentLens::none()
          }
        }),
      )
      .offset(
        By(fn() {
          let d = (1.0 - reveal_way.shown(content_box)) * 4.0
          match side {
            Bottom => (0.0, -d)
            Top => (0.0, d)
            Right => (-d, 0.0)
            Left => (d, 0.0)
          }
        }),
      )
      |> ignore
      content(content_box)
    })
    |> ignore
  })
  |> ignore
  modal_live
}
