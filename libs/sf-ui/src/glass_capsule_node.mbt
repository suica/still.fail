// Unified single-layer iOS 27 Liquid Glass floating capsule decorator for 30pt/32pt floating pills and overlays:
// delegates glass material to `@lg.liquid_floating_glass` (or `@lg.liquid_viewer_dark_glass` when `dark=true`),
// pairs with `glass_control_shadow()` + `shadow_outside(Is(true))`, `MBUI_GLASS=solid` hairline border fallback,
// and optional press-point GPU `spot` specular highlight (`interactive=true`).

///|
/// Decorates `b` as a single-layer iOS 27 floating liquid glass capsule and returns `b`.
/// Never nest inside another `Glass::liquid` surface.
pub fn glass_capsule_node(
  b : @view.View,
  min_height? : Double? = None,
  radius? : Double? = None,
  sharing? : Bool = true,
  interactive? : Bool = false,
  dark? : Bool = false,
  solid? : () -> Int64,
  tint? : () -> Int64,
) -> @view.View {
  if min_height is Some(h) {
    b.min_height(Is(Some(h))) |> ignore
  }
  if radius is Some(r) {
    b.radius(Is(r)) |> ignore
  }
  b
  .glass(By(fn() {
    let spot = if interactive && b.pressed() && !b.glass_solid() {
      let (_, _, w, h) = b.placed_window_now()
      if w > 0.0 && h > 0.0 {
        Some((w / 2.0, h / 2.0))
      } else {
        None
      }
    } else {
      None
    }
    let sol = match solid {
      Some(f) => f()
      None => if dark { 0x161618FFL } else { panel_ground() }
    }
    let base = if dark {
      @lg.liquid_viewer_dark_glass(spot~, solid=sol, sharing~)
    } else {
      @lg.liquid_floating_glass(solid=sol, spot~, sharing~)
    }
    Some(
      match tint {
        Some(f) => { ..base, tint: f() }
        None => base
      },
    )
  }))
  .edge(By(fn() {
    if b.glass_solid() {
      (control_edge_w, if dark { 0xFFFFFF26L } else { theme().p.line })
    } else {
      (0.0, 0L)
    }
  }))
  .shadow(By(fn() { glass_control_shadow() }))
  .shadow_outside(Is(true))
  .clips(Is(true))
}
