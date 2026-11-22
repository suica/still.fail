// One of a few levels in order as nodes of the window's tree (stops' made-once form, seg.mbt: how hard a model thinks
// on a sheet): delegates to `@lg.liquid_slider_node(stops=..., thumb_label=...)` with sf-ui's optimistic `Stops`
// state machine (`Stops::reset`), semantic label readout, and lazy-mounted clear refraction loupe (zero hidden glass
// instances at rest, zero relayout during drag).

///|
/// The levels `labels` in `parent`, at `chosen()` (-1: none), `said` what a screen reader calls it, `state` what it
/// keeps (its caller's, one for each of them: Stops). The level it shows is its own once picked in it: shown from
/// then on whatever its caller says meanwhile that is no news (the level it had, an earlier pick's) until its caller
/// says that level back; a level its caller says that is news is shown as it is said (stops'). `on_pick`: what
/// choosing another level does, given its index, as it is chosen; where that does not take, its caller says so
/// (Stops::reset), and it shows what its caller says again. The node.
#callsite(autofill(loc))
pub fn stops_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  state : Stops,
  said? : String = "",
  on_pick? : (Int) -> Unit = fn(_) {  },
  loc~ : SourceLoc,
) -> @view.View {
  let shown : @signals.Signal[Int] = @signals.signal(-1)
  let told = fn(c : Int) {
    if state.expect >= 0 {
      if c == state.expect {
        state.expect = -1
        state.stale.clear()
        state.said = c
      } else if !state.stale.contains(c) {
        state.expect = -1
        state.stale.clear()
        state.said = c
        state.shown = c
      }
    } else if c != state.said {
      state.said = c
      state.shown = c
    }
    shown.set(state.shown)
  }
  @signals.untracked(fn() { told(chosen()) })
  let pick_it = fn(i : Int) {
    if i < 0 || i == state.shown {
      return
    }
    for old in [(state.said, -1), (state.shown, -1), (state.expect, 0)] {
      if old.0 >= old.1 && old.0 != i && !state.stale.contains(old.0) {
        state.stale.push(old.0)
      }
    }
    state.stale.retain(fn(x) { x != i })
    state.expect = i
    state.shown = i
    shown.set(i)
    on_pick(i)
  }
  let count = @signals.untracked(fn() { labels().length() })
  let last = dmax(1.0, (count - 1).to_double())
  let pad = @ui.Space::px(S1)
  let high = @signals.untracked(button_height)
  let thumb_h = dmax(20.0, high - 2.0 * pad)
  let init_v = dmax(0.0, @signals.untracked(fn() { shown.get() }).to_double())
  let dd = @lg.DampedDrag::new(init_v, lo=0.0, hi=last, held_scale=@lg.thumb_held_scale)
  parent.box(made_for=loc, fn(wrap) {
    style_node(wrap, fn() { stops_track.then(@ui.style(h=Fixed(button_height()))) }, in_row=true)
    wrap.ground(Is(0L)).lines_up(Is(Some(Middle))) |> ignore
    wrap.reacts(at_start=false, fn() { (chosen(), state.resets.get()) }, fn(k) { told(k.0) })
    let sl = @lg.liquid_slider_node(
      wrap,
      fn() { dmax(0.0, shown.get().to_double()) },
      fn(v) { pick_it(v.round().to_int()) },
      fn() { said },
      least=0.0,
      most=last,
      track_h=10.0,
      thumb_w_px=40.0,
      thumb_h_px=thumb_h,
      track_color=track_glass_ink,
      fill_color=fn() { alpha(theme().p.accent, 0.45) },
      stops=count,
      thumb_label=fn(v) {
        let a = shown.get()
        if a < 0 && !dd.pressing() {
          ""
        } else {
          labels().get(v.round().to_int()).unwrap_or("")
        }
      },
      drag=dd,
      loc~,
    )
    sl
    .grow(Is(1.0))
    .says(By(fn() {
      let ls = labels()
      let a = shown.get()
      let value = if a >= 0 && a < ls.length() { ls[a] } else { "" }
      Some(@view.said(Slider, label=said, value~, range=(0.0, dmax(0.0, a.to_double()), last), actions=[Increment, Decrement]))
    }))
    |> ignore
  })
}
