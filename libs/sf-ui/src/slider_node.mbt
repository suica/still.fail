// A slider as a node of the window's tree (what @kit.slider was on the old view), its look over mbui's headless slider
// (@headless.slider: a press along it goes there, a drag follows the hand, ←/→ a step, Page Up/Down ten, Home/End its
// ends, read out a slider with its value, its Increment and Decrement): a track, its part up to the knob in the accent,
// a white knob. Held, the knob and its part are one drop of ink held by its surface (@paint.meniscus_outline: the
// accent swelling round the knob and drawn into it from the track by a neck), springing to it as it is pressed (lift_spring)
// and eased back as it is let go, and over the knob a bubble with the value in it (rolling_number_node: rolling as the keys step it, each
// step under the hand there at once), round as small_corner says. Stepped by the keys, the knob and its part go there
// over a control's answer (dur_ms) from where they are drawn; in the hand they are where the hand has them. All of it drawn by the width it is given (View::by_room), nothing
// read back of its layout and nothing laid out again as the knob goes.

///|
/// A slider in `parent`, called `label`, at `value()` along `min` … `max` in steps of `step` (`change` told the value
/// it is moved to); faded and taking nothing while `disabled`. `format` how its value, rounded to a whole number, is
/// read out and written in its bubble (by default its digits); `bubble` whether the bubble shows while it is held, in
/// `tips`' layer where that is given (over all of the window, beside the knob), else over the knob in the slider
/// itself. As wide as what holds it gives it. The node.
#callsite(autofill(loc))
pub fn value_slider_node(
  parent : @view.View,
  label : () -> String,
  value : () -> Double,
  change : (Double) -> Unit,
  min? : Double = 0.0,
  max? : Double = 100.0,
  step? : Double = 1.0,
  disabled? : () -> Bool = fn() { false },
  format? : (Int) -> String = fn(n) { n.to_string() },
  bubble? : Bool = true,
  tips? : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  // (how far behind where it rests the knob is drawn, a part of the way: none at rest, the knob where its value lays it
  // out, as it is moved there by the hand or from outside. Stepped by the keys (an arrow, Home, End, a page), it is
  // drawn from where it was then, that far behind, coming to none over a control's answer, so it never jumps across
  // the track in a frame; set off at the step itself, as `change` is told)
  let lag = @motion.NodeWay::new(0.0)
  let made : Ref[(@view.View, @headless.Slider)?] = Ref(None)
  let span_of = max - min
  let part_of = fn(x : Double) { if span_of <= 0.0 { 0.0 } else { dmax(0.0, dmin(1.0, (x - min) / span_of)) } }
  let change = fn(x : Double) {
    match made.val {
      Some((v, sl)) if !sl.in_hand() => {
        let was = sl.part() + lag.value_at(v.cause_at())
        lag.put(was - part_of(x))
        lag.go_ms(v, 0.0, dur_ms)
      }
      _ => lag.put(0.0)
    }
    change(x)
  }
  @headless.slider(
    made_for=loc,
    parent,
    label,
    value,
    min~,
    max~,
    step~,
    change,
    thumb_room=vslider_knob_d,
    disabled~,
    value_text=fn(x) { format(x.round().to_int()) },
    fn(v, sl) {
      let dd = @lg.DampedDrag::new(@signals.untracked(value), lo=min, hi=max, held_scale=1.5)
      dd.attach(v)
      let no_lens = fn() { v.glass_solid() || @ui.reduced_motion() }
      let lens = fn(n : @view.View) -> Double { if no_lens() { 0.0 } else { dclamp(dd.pressed(n), 0.0, 1.0) } }
      // (held: the drop, its bubble, and its liquid glass lens; springing to it as the hand takes it and back as it lets go)
      let held = @motion.NodeWay::new(0.0)
      let pressed_at : Ref[Double] = Ref(-1.0)
      v.reacts(fn() { sl.pressed() && !disabled() }, at_start=false, fn(on) {
        // (taken on a spring, a little past it; let go, eased back out with no overshoot: the bubble gone once)
        if on {
          pressed_at.val = v.cause_at()
          held.go(v, 1.0, @motion.tactile_bounce)
          if !no_lens() {
            dd.press()
          }
        } else {
          pressed_at.val = -1.0
          held.go_ms(v, 0.0, vslider_let_go_ms)
          dd.release()
        }
      })
      v.reacts(at_start=false, value, fn(x) {
        if !no_lens() && sl.pressed() && v.cause_at() > pressed_at.val {
          dd.update_value(x)
        }
      })
      let hold = fn() { dmax(0.0, held.shown(v)) }
      made.val = Some((v, sl))
      v
      .height(Is(Some(vslider_h)))
      .min_width(Is(Some(vslider_least_w)))
      .focus_ring_theme()
      .alpha(By(fn() { if disabled() { vslider_disabled_alpha } else { 1.0 } }))
      |> ignore
      v.by_room(fn(row, room) {
        row.height(Is(Some(vslider_h))) |> ignore
        let r = vslider_knob_d / 2.0
        let cy = vslider_h / 2.0
        // (the knob's middle across: its part of the way between its ends' middles)
        let span = fn() { dmax(0.0, room.width() - vslider_knob_d) }
        let cx = fn() { r + sl.part() * span() }
        // (as it is drawn at `at`: how far off where it rests the knob is then; asked again as a step sets it off)
        let off_at = fn(at : Double) {
          lag.target() |> ignore
          lag.value_at(at) * span()
        }
        // its track
        row.box(fn(t) {
          t
          .over(Is(true))
          .margin(Is((0.0, cy - vslider_track_h / 2.0, 0.0, cy - vslider_track_h / 2.0)))
          .radius(Is(vslider_track_h / 2.0))
          .ground(By(fn() { theme().p.line_strong }))
          |> ignore
        })
        |> ignore
        // its part up to the knob, and held, the drop round the knob drawn into it
        row.box(fn(f) {
          f
          .over(Is(true))
          .shapes(By(fn() {
            let k = dmin(1.0, hold())
            let x = r + (sl.part() + lag.shown(f)) * span()
            let ink = theme().p.accent
            let part = vslider_capsule(0.0, x, cy, vslider_track_h)
            if k <= 0.01 {
              [@paint.shape_of(part, fill=ink)]
            } else {
              let drop = @paint.meniscus_outline(0.0, cy, vslider_track_h, x, r + vslider_drop_out * k, k)
              [@paint.shape_of(part, fill=ink), @paint.shape_of(drop, fill=ink)]
            }
          }))
          |> ignore
        })
        |> ignore
        // its knob: positioned in the paint layer via moved_by (zero relayout while dragging), fading out under the
        // lazy-mounted clear liquid glass refraction loupe while held
        let knob = row.box(fn(k) {
          k
          .over(Is(true))
          .points(Is(false))
          .offset(Is((0.0, cy - r)))
          .width(Is(Some(vslider_knob_d)))
          .height(Is(Some(vslider_knob_d)))
          .radius(Is(r))
          .ground(Is(0xFFFFFFFFL))
          .shadow(Is((2.0, 1.0, 0x00000033L)))
          .alpha(By(fn() { 1.0 - lens(k) }))
          .moved_by(fn(_w, _h, at) { (cx() - r + off_at(at), 0.0) }, fn(_w, _h) { lag.end() })
          |> ignore
        })
        // Lazy-mounted clear liquid glass magnifying lens over the knob while held (0 hidden glass & 0 extra nodes at rest; laid == 0)
        let lens_mounted : @signals.Signal[Bool] = @signals.signal(false)
        row.reacts(fn() { !no_lens() && (dd.pressing() || dd.pressed(row) > 0.001) }, fn(active) {
          if active && !lens_mounted.untracked() {
            lens_mounted.set(true)
          }
        })
        row.show(fn() { lens_mounted.get() }, at_once=true, fn(gl) {
          gl
          .over(Is(true))
          .points(Is(false))
          .offset(Is((0.0, 0.0)))
          .width(Is(Some(vslider_knob_d)))
          .height(Is(Some(vslider_knob_d)))
          .radius(Is(r))
          .glass(By(fn() {
            let p = lens(gl)
            if p > 0.001 {
              Some(@lg.liquid_tab_lens_glass(p, solid=theme().p.raised))
            } else {
              None
            }
          }))
          .shadow(By(fn() {
            let p = lens(gl)
            if p > 0.001 {
              (4.0 * p, 2.0 * p, 0x00000022L)
            } else {
              (0.0, 0.0, 0L)
            }
          }))
          .shadow_outside(Is(true))
          .alpha(By(fn() { lens(gl) }))
          .ground_drawn(By(fn() {
            let (sx, sy) = dd.jelly(gl, 10.0)
            let lw = vslider_knob_d * sx
            let lh = vslider_knob_d * sy
            let x = r + (sl.part() + lag.shown(gl)) * span()
            let rr = lh / 2.0
            {
              dx: x - lw / 2.0,
              dy: cy - lh / 2.0,
              dw: lw - vslider_knob_d,
              dh: lh - vslider_knob_d,
              corners: Some((rr, rr, rr, rr)),
            }
          }))
          |> ignore
        })
        // over the knob while held: its value (rolling as the keys step it, each step under the hand there at once), in
        // a bubble of its own
        let bubble_in = fn(o : @view.View) {
          o
          .row(Is(true))
          .padding(Is((vslider_bubble_pad, vslider_bubble_pad / 2.0, vslider_bubble_pad, vslider_bubble_pad / 2.0)))
          .radius(Is(small_corner))
          .ground(By(fn() { theme().p.text }))
          .alpha(By(fn() { seen_at(dmin(1.0, hold())) }))
          |> ignore
          rolling_number_node(o, fn() { value().round().to_int() }, format~, style=fn() { vslider_bubble_words }, rolls=fn() {
            !sl.pressed()
          })
          |> ignore
        }
        match (bubble, tips) {
          // (in the tips' layer, over all of the window: beside the slider track and shifted over the knob in paint
          // layer so dragging triggers zero relayout, never cut by what holds the slider; let go with the knob)
          (true, Some(layer)) => {
            let made = Ref(false)
            let make = fn() {
              guard !made.val && (layer.layer)() is Some(top) else { return }
              made.val = true
              let holder = top.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(knob)
              holder.show(fn() { hold() > 0.0 }, at_once=true, fn(o) {
                o
                .beside(knob.id(), side=Top, along=Middle, offset=vslider_bubble_gap)
                .scale(By(fn() { dmin(1.0, slider_bubble_scale_from + (1.0 - slider_bubble_scale_from) * hold()) }), about=FromBeside)
                |> ignore
                bubble_in(o)
              })
            }
            make()
            v.reacts(fn() { sl.pressed() }, at_start=false, fn(down) { if down { make() } })
          }
          // (no layer given: over the knob in the slider itself)
          (true, None) =>
            row.show(fn() { hold() > 0.0 }, at_once=true, fn(o) {
              o
              .over(Is(true), edges=(None, Some(-vslider_bubble_gap), None, None))
              .scale(By(fn() { dmin(1.0, slider_bubble_scale_from + (1.0 - slider_bubble_scale_from) * hold()) }), about=At(0.5, 1.0))
              .moved_by(fn(w, h, at) { (cx() + off_at(at) - w / 2.0, -h) }, fn(_w, _h) { lag.end() })
              |> ignore
              bubble_in(o)
            })
          _ => ()
        }
      })
      |> ignore
    },
  )
}

///|
/// A capsule's outline from `x0` to `x1` across, `h` thick about the line `cy` (a track's part): none where it is not
/// as long as it is thick.
fn vslider_capsule(x0 : Double, x1 : Double, cy : Double, h : Double) -> Array[(Array[Double], Bool)] {
  let r = h / 2.0
  if x1 - x0 < h {
    return []
  }
  let pi = 3.141592653589793
  let out : Array[Double] = []
  for p in @paint.arc(x0 + r, cy, r, from=pi / 2.0, sweep=pi) {
    out.push(p.0)
    out.push(p.1)
  }
  for p in @paint.arc(x1 - r, cy, r, from=-pi / 2.0, sweep=pi) {
    out.push(p.0)
    out.push(p.1)
  }
  [(out, true)]
}

///|
/// A slider's height, least width, track, knob, how far its drop swells past the knob held, how faded it is disabled.
let vslider_h : Double = 28.0

///|
let vslider_least_w : Double = 120.0

///|
let vslider_track_h : Double = 4.0

///|
let vslider_knob_d : Double = 20.0

///|
/// Starting scale of the slider value bubble when pressed (0.94 -> 1.0, avoiding abrupt pop).
let slider_bubble_scale_from : Double = 0.94

///|
let vslider_drop_out : Double = 3.0

///|
let vslider_disabled_alpha : Double = 0.45

///|
/// How long a slider's drop and bubble take to go as it is let go (eased out).
let vslider_let_go_ms : Double = 180.0

///|
/// Its bubble: how far over the slider's top it stands, its padding, its words.
let vslider_bubble_gap : Double = 6.0

///|
let vslider_bubble_pad : Double = 8.0

///|
let vslider_bubble_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Bg)
