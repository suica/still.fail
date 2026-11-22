// A round button floating over a page's list (sfpages' float_button, chatToBottom: the way to a chat's newest) as a
// node of the window's tree, made once: 32 high and round, the single-layer liquid glass of the capsules over the
// composer (`glass_floating().sharing()`, falling back to `glass_floating().solid` + hairline `control_edge_w`
// `theme().p.line` border under `MBUI_GLASS=solid`) with outside-only `glass_control_shadow()`, its icon and the words
// beside it it says; the hover ground under the hand; pressed in 44 by 44 round it at the least.

///|
/// The round button in `parent` showing icon `icon` and, where `count` says any, those words after it; named `label`
/// (read out a button, its tip in `tips` on its top, `shortcut`'s keys after it); `press` done as it is pressed. Pressed
/// in its room (`float_button_reach` round what is drawn). While `busy` (what it asked still under way) a spinner
/// takes its icon's place, the icon going as the spinner comes (button_node's way with an icon), and it is pressed
/// no more, to the hand, the keys and a screen reader alike (disabled to the headless button, as button_node's at
/// work is). The node: its room.
#callsite(autofill(loc))
pub fn float_button_node(
  parent : @view.View,
  icon : String,
  label : () -> String,
  press : () -> Unit,
  count? : () -> String = fn() { "" },
  busy? : () -> Bool,
  tips? : TipLayer,
  shortcut? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  // (its room a plain box round it; the button what is drawn, 32 round, which the tree presses in 44 by 44 at the least
  // (Tree::press_least): what a screen reader is told of it is what is seen, not its room)
  parent.box(made_for=loc, fn(o) {
    let room = float_button_reach
    o
    .padding(Is((room, room, room, room)))
    .min_width(Is(Some(float_button_side + 2.0 * room)))
    |> ignore
    @headless.button(made_for=loc, o, label, fn(_) { press() }, disabled=busy.unwrap_or(fn() { false }), fn(b, btn) {
      let ih = @lg.InteractiveHighlight::new()
      ih.attach(b)
      let scale_bound = Ref(false)
      let ensure_scale = fn() {
        if !scale_bound.val {
          scale_bound.val = true
          b.scale(
            By(fn() {
              if @ui.reduced_motion() {
                1.0
              } else {
                let (_, _, sx, sy) = ih.stretch(b)
                (sx + sy) / 2.0
              }
            }),
            about=At(0.5, 0.5),
          )
          |> ignore
        }
      }
      style_node(b, fn() { float_button_look })
      hover_ground_node(b)
      b
      .glass(By(fn() {
        let sp = if !b.glass_solid() && ih.pressed(b) > 0.001 {
          let (_, _, bw, bh) = b.placed_window_now()
          if bw > 0.0 && bh > 0.0 {
            Some(ih.spot(b, bw, bh))
          } else {
            None
          }
        } else {
          None
        }
        Some(glass_floating(spot=sp).sharing())
      }))
      .edge(By(fn() { if b.glass_solid() { (control_edge_w, theme().p.line) } else { (0.0, 0L) } }))
      .shadow(By(fn() { glass_control_shadow() }))
      .shadow_outside(Is(true))
      .clips(Is(true))
      .gesture(
        @ui.touch_slop(),
        press=fn(d) {
          if !btn.disabled() {
            ensure_scale()
            ih.down(d.x, d.y, d.w, d.h)
          }
        },
        tap=fn(d) {
          ih.up()
          if !btn.disabled() && b.finger_target(d.wx, d.wy) {
            btn.press()
          }
        },
        drag=fn(d) {
          match d.kind {
            Down | Moved =>
              if !btn.disabled() {
                ih.moved(d.x, d.y)
              }
            Up => {
              ih.up()
              if !btn.disabled() && @ui.pointing() is Mouse && b.finger_target(d.wx, d.wy) {
                btn.press()
              }
            }
            Off => ih.up()
          }
        },
      )
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
      float_icon(b, icon, busy, loc~)
      b.show(fn() { count() != "" }, fn(w) { words_node(w, count, fn() { float_button_count }) |> ignore })
      match tips {
        Some(t) => tip_node(t, b, label, side=Top, shortcut~) |> ignore
        None => ()
      }
    })
    |> ignore
  })
}

///|
/// How high the button is drawn (float_side), its icon, and the room round it it is pressed in too (44 in all).
pub let float_button_side : Double = 32.0

///|
pub let float_button_icon : Double = 16.0

///|
pub let float_button_reach : Double = 6.0

///|
/// The button (float_button's): 32 high, round, its count beside its arrow; glass/solid ground, edge, shadow and hover
/// ground are bound on the node.
// kept across runs: a value (no field of it changes)
let float_button_look : @ui.Style = @ui.css((
  #|row h=S8 min_w=S8 px=S2 gap=S1 radius=Full align=ACenter justify=JCenter
))

///|
/// The round floating badge look matching float_button_look (same diameter, full radius and Md shadow) without fixed
/// ground/border so callers can animate fill and border on state transitions.
// kept across runs: a value (no field of it changes)
pub let float_badge_look : @ui.Style = @ui.css((
  #|row w=S8 h=S8 radius=Full shadow=Md align=ACenter justify=JCenter
))

///|
// kept across runs: a value (no field of it changes)
let float_button_count : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, color=Fg, wrap=false)

///|
/// The icon `icon` of a floating round button `b` (float_button_node's, float_pill_item_node's), 16 square; while
/// `busy` (what it asked still under way) a spinner over the icon's own square takes its place, the icon going as the
/// spinner comes (button_node's way with an icon).
#callsite(autofill(loc))
fn float_icon(b : @view.View, icon : String, busy : (() -> Bool)?, loc~ : SourceLoc) -> Unit {
  match busy {
    // (its icon, and over the icon's own square the spinner while it is at work: how far the spinner is in, from
    // where it is as it is made (at work already: in), eased as button_node's; the icon faded and shrunk as it
    // comes, never the two seen side by side whole, on one 16 square node so a button that may be at work adds no
    // node to the page's budget and reads no cycle while still)
    Some(busy) => {
      let pi = 3.141592653589793
      let mid = float_button_icon / 2.0
      let r = mid - spin_stroke / 2.0
      let round = @ui.arc(mid, mid, r, from=0.0, sweep=2.0 * pi)
      let part = @ui.arc(mid, mid, r, from=-0.75 * pi, sweep=0.5 * pi)
      let turning = @motion.NodeWay::new(if @signals.untracked(busy) { 1.0 } else { 0.0 })
      b.reacts(busy, fn(on) {
        let to = if on { 1.0 } else { 0.0 }
        if @view.answering_now() {
          turning.put(to)
        } else {
          turning.go_ms(b, to, dur_ms)
        }
      }, at_start=false)
      b.box(made_for=loc, fn(i) {
        let u = fn() { dmin(1.0, dmax(turning.shown(i), 0.0)) }
        i
        .width(Is(Some(float_button_icon)))
        .height(Is(Some(float_button_icon)))
        .shapes(By(fn() {
          if u() <= 0.5 {
            match icon_numbers(icon) {
              Some(d) => icon_shapes(d, float_button_icon / 24.0, 0x000000FFL)
              None => []
            }
          } else {
            []
          }
        }))
        .lines(By(fn() {
          if u() > 0.5 {
            let p = theme().p
            [@ui.line(round, width=spin_stroke, color=p.line_strong), @ui.line(part, width=spin_stroke, color=p.accent)]
          } else {
            []
          }
        }))
        .tint(By(fn() { if u() <= 0.5 { theme().p.text } else { 0L } }))
        .drawn_as(By(fn() { if u() <= 0.5 { "/icon/" + icon + "/" } else { "/spinner/" } }))
        .alpha(By(fn() {
          let t = u()
          if t <= 0.5 {
            seen_at(1.0 - t)
          } else {
            seen_at(t)
          }
        }))
        .scale(By(fn() {
          let t = u()
          if t <= 0.5 {
            1.0 - t
          } else {
            t
          }
        }), about=At(0.5, 0.5))
        .turn(By(fn() { if u() > 0.5 { i.cycle(spinner_turn_ms) * 2.0 * pi } else { 0.0 } }), drawn=true)
        |> ignore
      })
      |> ignore
    }
    None => icon_node(b, icon, float_button_icon, By(fn() { theme().p.text }), loc~) |> ignore
  }
}
