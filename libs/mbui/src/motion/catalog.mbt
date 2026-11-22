// Semantic spring tiers, symmetric overlay transitions, and curve/spring sampling helpers for the motion library.
// Pure values and pure functions only: zero mutable state, closed-form evaluation.

///|
/// Critically damped quick snap (zeta = 1.0, stiffness = 420, threshold = 0.001):
/// hover handoff, discrete stops, toolbar selection indicator — arrives cleanly without overshoot.
///
/// Example:
/// ```moonbit
/// let way = @motion.NodeWay::new(0.0)
/// way.go(node, 1.0, @motion.snappy_damped)
/// ```
// kept across runs: a value (no field of it changes)
pub let snappy_damped : Spec = spring(ratio=1.0, stiffness=420.0, threshold=0.001)

///|
/// Critically damped move spring (visual = 0.28s, bounce = 0, threshold = 0.5):
/// segmented controls, tab indicators, and regular layout displacements.
///
/// Example:
/// ```moonbit
/// let way = @motion.NodeWay::new(0.0)
/// way.go(node, 160.0, @motion.move_damped)
/// ```
// kept across runs: a value (no field of it changes)
pub let move_damped : Spec = motion_spring(0.28, threshold=0.5)

///|
/// Critically damped sheet/carousel spring (visual = 0.32s, bounce = 0, threshold = 0.5):
/// carousels, horizontal media strips, and settled sheets.
// kept across runs: a value (no field of it changes)
pub let carousel_spring : Spec = motion_spring(0.32, threshold=0.5)

///|
/// Tactile light-bounce spring (visual = 0.25s, bounce = 0.35):
/// long-press lift, finger drag follow, and tactile press release.
// kept across runs: a value (no field of it changes)
pub let tactile_bounce : Spec = motion_spring(0.25, bounce=0.35)

///|
/// Liquid glass lens spring triplet: (press_progress, scale_x, scale_y).
pub fn glass_lens_springs() -> (Spec, Spec, Spec) {
  (backdrop_press_spring, backdrop_scale_x_spring, backdrop_scale_y_spring)
}

///|
/// Critically damped zero-overshoot liquid glass popover bloom spring (zeta = 1.0, stiffness = 540, threshold = 0.001):
/// crisp iOS 27.0 droplet-to-menu emergence (67ms -> 0.46, 117ms -> 0.79, 150ms -> 0.91) with zero overshoot.
// kept across runs: a value (no field of it changes)
pub let popover_bloom_spring : Spec = spring(ratio=1.0, stiffness=540.0, threshold=0.001)

///|
/// Matching critically damped popover glide spring (zeta = 1.0, stiffness = 540, threshold = 0.001) keeping
/// droplet emergence, body morph, and corner radius in unified monotonic motion without overshoot.
// kept across runs: a value (no field of it changes)
pub let popover_neck_spring : Spec = spring(ratio=1.0, stiffness=540.0, threshold=0.001)

///|
/// Symmetric dialog exit duration (ms).
pub let dialog_out_ms : Double = pop_out_ms

///|
/// Symmetric dialog exit transition (fade to 0, scale to 0.98, dy +6 over pop_out_ms on Leave).
// kept across runs: a value (no field of it changes)
pub let dialog_out : Trans = trans(
  fade=0.0,
  scale=0.98,
  dy=6.0,
  spec=tween(dialog_out_ms, ease=Leave),
  ground_first=true,
)

///|
/// Symmetric tooltip exit duration (ms).
pub let tip_out_ms : Double = pop_out_ms

///|
/// Symmetric tooltip exit transition (fade to 0 over pop_out_ms on Leave).
// kept across runs: a value (no field of it changes)
pub let tip_out : Trans = trans(
  fade=0.0,
  spec=tween(tip_out_ms, ease=Leave),
  ground_first=true,
)

///|
/// Distance-adaptive Move duration (ms) for traveling `distance` points (`@ui.move_ms`).
pub fn move_duration_ms(distance : Double) -> Double {
  @ui.move_ms(distance)
}

///|
/// Sample `@ui.Ease` evenly across `[0, 1]` into `steps + 1` points.
pub fn sample_ease(ease : @ui.Ease, steps : Int) -> Array[Double] {
  if steps <= 0 {
    return [ease.at(0.0)]
  }
  let out : Array[Double] = []
  let denom = steps.to_double()
  for i in 0..<=steps {
    out.push(ease.at(i.to_double() / denom))
  }
  out
}

///|
/// Sample `spec` from `0.0` to `1.0` evenly across `[0, duration_ms]` into `steps + 1` points
/// using `Way::new(0.0)`. Useful for plotting trajectories and checking overshoot (`> 1.0`).
pub fn sample_spec(spec : Spec, duration_ms : Double, steps : Int) -> Array[Double] {
  let way = Way::new(0.0)
  way.go(1.0, spec, at=0.0)
  if steps <= 0 {
    return [way.value_at(0.0)]
  }
  let out : Array[Double] = []
  let denom = steps.to_double()
  for i in 0..<=steps {
    out.push(way.value_at(duration_ms * i.to_double() / denom))
  }
  out
}
