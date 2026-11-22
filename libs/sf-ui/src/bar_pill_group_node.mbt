// Single-layer iOS 26 / macOS 26 floating liquid glass pill container for top bar action button groups:
// delegates neutral pills to `@lg.liquid_pill_group_node` & `@lg.bind_pill_press`, adding sf-ui's calibrated
// outside-only `glass_control_shadow()`, `MBUI_GLASS=solid` hairline `panel_edge()` fallback, and automatic
// concentric corner scope (`corner_card_node`). Tinted pills (`bar_pill_group_with` with `tint=Some(...)`,
// `window_keys_node`) and vertical `float_pill_group_node` share the package-local `PillPressScope` / `pill_press_lent`.

///|
/// Shared press-feedback scope lent by tinted `bar_pill_group_with` (`window_keys_node`) and vertical
/// `float_pill_group_node` to their interactive children (neutral horizontal `bar_pill_group_node` / `pick_bar_node`
/// delegate to `@lg.liquid_pill_group_node`).
priv struct PillPressScope {
  pill : @view.View
  spot : @signals.Signal[(Double, Double)?]
  press_way : @motion.NodeWay
  mut count : Int
}

///|
let pill_press_lent : @view.Lent[PillPressScope] = @view.Lent::new()

///|
/// Theme-adaptive press overlay ink for controls inside a liquid glass top bar pill: delegates to `@lg.liquid_pill_press_ink()`.
pub fn bar_pill_press_ink() -> Int64 {
  @lg.liquid_pill_press_ink()
}

///|
/// Connects an interactive child control inside `bar_pill_group_node`, `bar_pill_group_with`, or
/// `float_pill_group_node` to its enclosing liquid glass pill's `.glassEffect(.interactive())` response: moves the
/// GPU `spot` specular highlight to the child's center and springs the pill scale via `@motion.backdrop_press_spring`.
/// No-op outside a pill group.
pub fn bind_pill_press(child : @view.View) -> Unit {
  @lg.bind_pill_press(child)
  bind_pill_press_by(child, fn() { child.pressed() })
}

///|
/// bind_pill_press with what holds `child` down said by `down` (a press the host takes rather than the app: the
/// window's maximize button held down as the host says, @ui.window_snap_state), sharing the pill's press count with
/// any other press bound to it.
fn bind_pill_press_by(child : @view.View, down : () -> Bool) -> Unit {
  guard child.lent(pill_press_lent) is Some(scope) else { return }
  let active = Ref(false)
  let release = fn() {
    if active.val {
      active.val = false
      scope.count = if scope.count > 0 { scope.count - 1 } else { 0 }
      if scope.count == 0 {
        scope.spot.set(None)
        scope.press_way.go(scope.pill, 0.0, @motion.backdrop_press_spring)
      }
    }
  }
  child.reacts(down, fn(is_down) {
    if is_down {
      if !active.val {
        active.val = true
        scope.count += 1
      }
      if !scope.pill.glass_solid() {
        let (gx, gy, _, _) = scope.pill.placed_window_now()
        let (cx, cy, cw, ch) = child.placed_window_now()
        scope.spot.set(Some((cx - gx + cw / 2.0, cy - gy + ch / 2.0)))
      }
      if !@ui.reduced_motion() {
        scope.press_way.go(scope.pill, 1.0, @motion.backdrop_press_spring)
      }
    } else {
      release()
    }
  })
  child.owns(release) |> ignore
}

///|
/// Attaches theme-adaptive hover + press highlight and outer liquid glass pill press feedback (`bind_pill_press`)
/// to a custom `action_box_node` inside `bar_pill_group_node` (such as the home workspace switcher capsule).
pub fn bar_pill_key_press_node(v : @view.View) -> Unit {
  hover_ground_node(
    v,
    color=fn() {
      if v.pressed() {
        bar_pill_press_ink()
      } else {
        @ui.tree_theme().color(Hover)
      }
    },
  )
  bind_pill_press(v)
}

///|
/// A single-layer liquid glass pill container in `parent` for a group of top bar controls made by `body`:
/// `height` tall (default `40.0`, full capsule radius `height / 2.0`), padded `pad` all around (default `3.0`,
/// concentric with 34pt `round_key_node` at `height=40.0, pad=3.0` and 32pt `icon_button_node` at `height=36.0, pad=2.0`),
/// children `gap` apart (default `2.0`). Never nest inside another glass surface.
#callsite(autofill(loc))
pub fn bar_pill_group_node(
  parent : @view.View,
  body : (@view.View) -> Unit,
  height? : Double = 40.0,
  pad? : Double = 3.0,
  gap? : Double = 2.0,
  loc~ : SourceLoc,
) -> @view.View {
  let g = @lg.liquid_pill_group_node(
    parent,
    height~,
    pad~,
    gap~,
    solid=panel_ground,
    fn(g) {
      corner_card_node(g, fn() { height / 2.0 }, inset=fn() { pad })
      body(g)
    },
    loc~,
  )
  g
  .edge(By(fn() { if g.glass_solid() { (control_edge_w, panel_edge()) } else { (0.0, 0L) } }))
  .shadow(By(fn() { glass_control_shadow() }))
  |> ignore
  g
}

///|
/// bar_pill_group_node's pill, its glass `tint()` where said (`window_keys_node`), else delegates to neutral `bar_pill_group_node`.
#callsite(autofill(loc))
fn bar_pill_group_with(
  parent : @view.View,
  body : (@view.View) -> Unit,
  height? : Double = 40.0,
  pad? : Double = 3.0,
  gap? : Double = 2.0,
  tint? : (() -> Int64)? = None,
  loc~ : SourceLoc,
) -> @view.View {
  match tint {
    None => bar_pill_group_node(loc~, parent, body, height~, pad~, gap~)
    Some(tint_fn) =>
      parent.box(made_for=loc, fn(g) {
        let r = height / 2.0
        let spot_sig : @signals.Signal[(Double, Double)?] = @signals.signal(None)
        let press_way = @motion.NodeWay::new(0.0)
        let scope : PillPressScope = { pill: g, spot: spot_sig, press_way, count: 0 }
        g
        .row(Is(true))
        .height(Is(Some(height)))
        .radius(Is(r))
        .padding(Is((pad, pad, pad, pad)))
        .gap(Is(gap))
        .lines_up(Is(Some(Middle)))
        .shrink(Is(0.0))
        .glass(By(fn() {
          let c = tint_fn()
          Some({ ..@lg.liquid_bar_pill_glass(spot=spot_sig.get()), tint: c, solid: over(panel_ground(), alpha(c, 0.24)) })
        }))
        .scale(By(fn() { 1.0 + 0.05 * press_way.shown(g) }), about=At(0.5, 0.5))
        .edge(By(fn() { if g.glass_solid() { (control_edge_w, panel_edge()) } else { (0.0, 0L) } }))
        .shadow(By(fn() { glass_control_shadow() }))
        .shadow_outside(Is(true))
        .clips(Is(true))
        .lends(pill_press_lent, scope)
        |> ignore
        corner_card_node(g, fn() { r }, inset=fn() { pad })
        body(g)
      })
  }
}
