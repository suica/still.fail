// A column of round buttons floating over a page's list on one capsule of liquid glass (a chat's 待处理, 对话目录 and
// 跳到最新 over its composer), made once as nodes: `float_pill_group_node` the capsule, the glass of the capsules over the
// composer (`glass_floating().sharing()`, `glass_control_shadow()` outside it; under `MBUI_GLASS=solid` its solid ground
// and a hairline `control_edge_w` edge), lit where it is pressed and springing back as `bar_pill_group_node` does;
// `float_pill_item_node` each button in it, 32 round, concentric with it.

///|
/// The room between two buttons on the capsule: half of it over and under each (float_pill_item_node's margin), so a
/// button coming or going on it (View::comes) opens or shuts its whole room, never a gap stepped at once.
let float_pill_gap : Double = 2.0

///|
/// The capsule in `parent` holding the round buttons `body` makes, one over another, float_pill_gap apart: `width`
/// across (its corners half that), `pad` round them. Never nest it in another glass. The node: the capsule.
#callsite(autofill(loc))
pub fn float_pill_group_node(
  parent : @view.View,
  body : (@view.View) -> Unit,
  width? : Double = 36.0,
  pad? : Double = 2.0,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(g) {
    let r = width / 2.0
    let fx_sig : @signals.Signal[((Double, Double)?, Int)] = @signals.signal((None, 0))
    let press_way = @motion.NodeWay::new(0.0)
    let scope : PillPressScope = { pill: g, fx: fx_sig, press_way, count: 0 }
    g
    .width(Is(Some(width)))
    .radius(Is(r))
    // (its buttons' own half gaps over and under them making up its pad there)
    .padding(Is((pad, dmax(0.0, pad - float_pill_gap / 2.0), pad, dmax(0.0, pad - float_pill_gap / 2.0))))
    .lines_up(Is(Some(Middle)))
    .shrink(Is(0.0))
    .glass(By(fn() { Some(glass_floating(spot=fx_sig.get().0).sharing()) }))
    .scale(By(fn() { 1.0 + 0.05 * press_way.shown(g) }), about=At(0.5, 0.5))
    .edge(By(fn() { if g.glass_solid() { (control_edge_w, theme().p.line) } else { (0.0, 0L) } }))
    .shadow(By(fn() { glass_control_shadow() }))
    .shadow_outside(Is(true))
    .clips(Is(true))
    .lends(pill_press_lent, scope)
    |> ignore
    corner_card_node(g, fn() { r }, inset=fn() { pad })
    body(g)
  })
}

///|
/// A round button in `parent` (a float_pill_group_node's) showing icon `icon`, named `label` (read out a button, its
/// tip in `tips` to its left so it never covers the one over or under it, `shortcut`'s keys after it); `press` done as
/// it is pressed. While `busy` a spinner takes its icon's place and it is pressed no more (float_button_node's way).
/// The node: the button.
#callsite(autofill(loc))
pub fn float_pill_item_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  busy? : () -> Bool,
  tips? : TipLayer,
  shortcut? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  @headless.button(made_for=loc, parent, label, fn(_) { press() }, disabled=busy.unwrap_or(fn() { false }), fn(b, _) {
    b
    .width(Is(Some(float_button_side)))
    .height(Is(Some(float_button_side)))
    .radius(Is(float_button_side / 2.0))
    .margin(Is((0.0, float_pill_gap / 2.0, 0.0, float_pill_gap / 2.0)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .ring(
      By(fn() {
        if b.focus_shown() {
          let t = @ui.tree_theme()
          (t.focus_w, t.focus_gap, t.focus)
        } else {
          (0.0, 0.0, 0L)
        }
      }),
    )
    |> ignore
    bar_pill_key_press_node(b)
    float_icon(b, icon, busy, loc~)
    match tips {
      Some(t) => tip_node(t, b, label, side=Left, shortcut~) |> ignore
      None => ()
    }
  })
}
