// Continuous flat-surface to iOS 27 liquid-glass elevation binding (`glass_lift_surface`).
// At rest (`t <= 0.001`), emits zero glass and zero backdrop captures; for `0.001 < t <= 1.0`, fades out any
// optional `flat_ground` while smoothly materialising liquid glass and an outside-only shadow. Under
// `MBUI_GLASS=solid`, fades in `theme().p.raised` smoothly by `t`.

///|
/// Bind container shell `v` to transition continuously between an optional flat surface (`flat_ground`) and a lifted
/// liquid glass card (`glass`) as `progress()` moves across `[0.0, 1.0]`. Bind only on a container shell, never on a
/// glyph-bearing leaf node, so text `ViewBlock` caches stay warm across the animation.
#callsite(autofill(loc))
pub fn glass_lift_surface(
  v : @view.View,
  progress : () -> Double,
  flat_ground? : (() -> Int64)? = None,
  glass? : () -> @ui.Glass = fn() { glass_menu() },
  radius? : Double = row_corner,
  shadow? : () -> (Double, Double, Int64) = fn() {
    (held_raised.sigma, held_raised.dy, held_raised.color)
  },
  loc~ : SourceLoc,
) -> Unit {
  let t = fn() { dclamp(progress(), 0.0, 1.0) }
  v
  .glass(
    By(fn() {
      let k = t()
      if k <= 0.001 {
        None
      } else {
        Some({ ..glass(), solid: theme().p.raised }.at_strength(k))
      }
    }),
    loc~,
  )
  .radius(Is(radius), loc~)
  .shadow(
    By(fn() {
      let k = t()
      if k <= 0.001 {
        (0.0, 0.0, 0L)
      } else {
        let (sigma, dy, color) = shadow()
        (sigma * k, dy * k, alpha(color, k))
      }
    }),
    loc~,
  )
  .shadow_outside(Is(true), loc~)
  |> ignore
  match flat_ground {
    Some(fg) =>
      v
      .ground(
        By(fn() {
          let k = t()
          if k <= 0.001 {
            fg()
          } else {
            alpha(fg(), 1.0 - k)
          }
        }),
        loc~,
      )
      |> ignore
    None => ()
  }
}
