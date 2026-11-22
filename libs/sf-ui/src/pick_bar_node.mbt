// The bar over words a finger picked in a message (sfbase's pick_bar, MessagePick.kt) as a node of the window's tree,
// made once: a single-layer liquid glass capsule 40 high (`glass_menu()`, falling back to `panel_ground()` + hairline
// `control_edge_w` border under `MBUI_GLASS=solid`) with outside-only `glass_control_shadow()`; its buttons 32 high and
// round, each its icon (where it has one) and its words; after a thin line 16 high, what it does with the message, each
// a mark alone 32 round, read out by its words. Each a ripple where it is pressed, over mbui's headless button.

///|
/// One of the bar's buttons: its words (read out, and shown where it is no `mark`), its icon ("" none), whether it is a
/// mark alone after the line, and what pressing it does.
pub(all) struct PickBarItem {
  label : String
  icon : String
  mark : Bool
  press : () -> Unit
}

///|
/// The bar in `parent` with `items` in their order (those that are no mark, then a line and the marks, the line only
/// where there is a mark): what is picked anew makes a bar anew, so what it offers is said as it is made. The node:
/// the capsule.
#callsite(autofill(loc))
pub fn pick_bar_node(
  parent : @view.View,
  items : Array[PickBarItem],
  compact? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let bar = @lg.liquid_pill_group_node(
    parent,
    height=40.0,
    pad=4.0,
    gap=0.0,
    solid=panel_ground,
    fn(bar) {
      for it in items {
        if !it.mark {
          pick_bar_button(bar, it, compact~) |> ignore
        }
      }
      let marks = items.filter(fn(it) { it.mark })
      if !marks.is_empty() {
        bar.box(fn(r) { style_node(r, fn() { pick_bar_rule }) }) |> ignore
      }
      for it in marks {
        pick_bar_button(bar, it, compact~) |> ignore
      }
    },
    loc~,
  )
  bar
  .edge(By(fn() { if bar.glass_solid() { (control_edge_w, theme().p.line) } else { (0.0, 0L) } }))
  .shadow(By(fn() { glass_control_shadow() }))
  |> ignore
  bar
}

///|
/// A button of the bar (pick_bar's button, its mark): its ground the page's while pressed (its ripple), its icon 15
/// and its words in the ink.
#callsite(autofill(loc))
fn pick_bar_button(
  parent : @view.View,
  it : PickBarItem,
  compact? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  @headless.button(made_for=loc, parent, fn() { it.label }, fn(_) { (it.press)() }, fn(v, b) {
    style_node(v, fn() {
      if it.mark {
        pick_bar_mark_look
      } else if compact {
        pick_bar_button_compact_look
      } else {
        pick_bar_button_look
      }
    })
    if it.icon != "" {
      icon_node(v, it.icon, pick_bar_icon, By(fn() { theme().p.text })) |> ignore
    }
    if !it.mark {
      words_node(v, fn() { it.label }, fn() { pick_bar_words }) |> ignore
    }
    // (its ripple: MessagePick.kt's clip(Smooth(16)).clickable, plus outer liquid glass pill GPU spot)
    @lg.bind_pill_press(v)
    let rippled = press_look(v, Is(pick_bar_round), fn() { false })
    v.gesture(
      @ui.touch_slop(),
      press=fn(d) {
        if !b.disabled() {
          (rippled.down)(d)
        }
      },
      tap=fn(d) {
        if !b.disabled() {
          (rippled.tapped)(d)
          if v.finger_target(d.wx, d.wy) {
            b.press()
          }
        }
      },
      drag=fn(d) {
        // (a mouse's moved on it past the slop: still a press as it is let go on it, as a click is)
        if d.kind == Up && @ui.pointing() is Mouse && v.finger_target(d.wx, d.wy) {
          b.press()
        }
      },
    )
    |> ignore
  })
}

///|
/// A button (pick_button's): 32 high, 12 in, its icon 5 before its words, round.
// kept across runs: a value (no field of it changes)
let pick_bar_button_look : @ui.Style = @ui.css("row min_h=S8 px=S3 gap=S1_25 radius=Full align=ACenter")

///|
/// A compact button for tight narrow viewports (e.g. 320pt at 1.3x font scale with 4 actions): 8 in, round.
// kept across runs: a value (no field of it changes)
let pick_bar_button_compact_look : @ui.Style = @ui.css("row min_h=S8 px=S2 gap=S1 radius=Full align=ACenter")

///|
/// A mark alone (pick_mark_button's): 32 round, its icon in its middle.
// kept across runs: a value (no field of it changes)
let pick_bar_mark_look : @ui.Style = @ui.css("h=S8 w=S8 radius=Full align=ACenter justify=JCenter")

///|
/// The line before the marks (pick_bar_rule's): 1 wide, 16 high, 4 off what is beside it.
// kept across runs: a value (no field of it changes)
let pick_bar_rule : @ui.Style = @ui.css("w=SPx h=S4 mx=S1 bg=Line")

///|
// kept across runs: a value (no field of it changes)
let pick_bar_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
let pick_bar_icon : Double = 15.0

///|
let pick_bar_round : Double = 16.0
