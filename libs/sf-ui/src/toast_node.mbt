// still.fail's toasts as nodes of the window's tree (made once): mbui's headless toaster (@headless.toaster: each toast's
// time, held while the pointer is over one or the focus on its action, swiped away, read out in a region) in the web's
// look. Where they are is this look's: over all of the window, at its foot in its middle `bottom` over what the system's
// bars leave of it (View::clear), as wide as that less 16 each side and `w` at most, the newest last, 8 apart. Each is
// the primary ink's capsule, its words 13 in its ink, its action a capsule in its end, concentric with it; in from 8
// below as it comes (presence_in_ms, eased out), its ground whole by half its way in, its words from there, and out as
// it is no longer given (presence_out_ms), put away to the right by half the toasts' width as far as it has gone; its
// room and the 8 over it opening and closing with it, it on its foot, those over it moved up and down with it.

///|
/// A toast (toaster_node's): its id (unique among those showing), its title, its description ("" none), its action's
/// words ("" none).
#derive(Eq, Debug)
pub(all) struct Toast {
  id : String
  title : String
  description : String
  action : String
}

///|
/// A toast of `title`, its id `id`.
pub fn toast(id : String, title : String, description? : String = "", action? : String = "") -> Toast {
  { id, title, description, action }
}

///|
/// When the next of toaster `key`'s toasts goes by itself (@headless.toaster_due): -1 where none is counting, None
/// where there is no toaster `key`.
pub fn toast_due(key : String) -> Double? {
  @headless.toaster_due(key)
}

///|
/// When toaster `key`'s toasts are done moving (@headless.toaster_rest): -1 where none moves, None where there is no
/// toaster `key`.
pub fn toast_rest(key : String) -> Double? {
  @headless.toaster_rest(key)
}

///|
/// The toasts `toasts` gives, over all of `parent` (toaster's: `duration`, `acted`, `gone`, read out as a region named
/// `label`, its times as `key`'s: toast_due, toast_rest), at the window's foot `bottom` over its system's
/// bars, `w` wide at most, each in still.fail's look. The node.
#callsite(autofill(loc))
pub fn toaster_node(
  parent : @view.View,
  toasts : () -> Array[Toast],
  duration : (Toast) -> Double,
  bottom : () -> Double,
  acted : (String) -> Unit,
  gone : (String) -> Unit,
  key? : String = "toast",
  w? : Double = toast_max,
  label? : String = "通知",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(v) {
    // (the window less what the system's bars reach in over its sides: View::clear)
    let width = fn() {
      let (_, right, _, left) = v.clear()
      let ww = v.window_w() - left - right
      if w < ww - 32.0 {
        w
      } else {
        ww - 32.0
      }
    }
    // (over all else of the window, the old frame's sheets and dialogs and the tree's modal layers too: View::over_all)
    v.transitions_only().over(Is(true)).over_all(Is(true)) |> ignore
    let shown_toasts = @signals.signal(@signals.untracked(toasts), same=fn(a, b) { a == b })
    v.reacts(toasts, fn(next) { @view.transition(within=v, fn() { shown_toasts.set(next) }) }, at_start=false)
    // (while one is given, and as the last given goes out: none, nothing of it)
    v.show(fn() { !shown_toasts.get().is_empty() }, fn(room) {
      // (clear of the system's bars: `bottom` over what they leave of the window's foot, in the middle of what they
      // leave of its width)
      room
      .grow(Is(1.0))
      .lines_up(Is(Some(Middle)))
      .padding(
        By(fn() {
          let (_, right, foot, left) = v.clear()
          (left, 0.0, right, foot + bottom())
        }),
      )
      |> ignore
      room.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
      @headless.toaster(
        room,
        fn() { shown_toasts.get() },
        fn(to) { to.id },
        fn(to) { (to.title, to.description) },
        duration,
        fn(region) { region.width(By(fn() { Some(width()) })).lines_up(Is(Some(Middle))) |> ignore },
        fn(b, s) { toast_look(b, s, key, width) },
        acted,
        gone,
        key~,
        label~,
        leave=@motion.presence_out_ms,
      )
      |> ignore
    }, leave=@motion.presence_out_ms)
  })
}

///|
/// Toast `s` drawn in `b` (toaster_node's), saying what it says now, its way in and out told as `key`'s: its action
/// (its toast's, "" none) a capsule in its end, pressed as the toaster's (ToastItem::action); going out, put away by
/// half the toasts' width (`width`) as far as it has gone.
#callsite(autofill(loc))
fn toast_look(
  b : @view.View,
  s : @headless.ToastItem[Toast],
  key : String,
  width : () -> Double,
  loc~ : SourceLoc,
) -> Unit {
  let row = s.row()
  let id = @signals.untracked(fn() { s.toast().id })
  // (how far in it is: in as it is made, out as it is no longer given, in again as it is given again as it goes)
  let shown = ToastWay::new(0.0, key + "/" + id)
  shown.go(row, 1.0, @motion.tween(@motion.presence_in_ms, ease=Out))
  let was_leaving = Ref(false)
  row.reacts(fn() { row.leaving() }, fn(l) {
    if l && !was_leaving.val {
      shown.go(row, 0.0, @motion.tween(@motion.presence_out_ms, ease=Leave))
    } else if !l && was_leaving.val {
      shown.go(row, 1.0, @motion.tween(@motion.presence_in_ms, ease=Out))
    }
    was_leaving.val = l
  })
  // (done, as of `now`, when its way in or out ends and, going out, as it is let go: View::leaves_at, the later; let go
  // with what holds it, done: ToastWay's `alive`)
  shown.rest = fn(now) {
    guard shown.alive else { return -1.0 }
    let way = if shown.way.ends_at() >= 0.0 && shown.way.end() > now { shown.way.end() } else { -1.0 }
    let gone = row.leaves_at()
    if gone > now && gone > way {
      gone
    } else {
      way
    }
  }
  s.moves(fn(now) { (shown.rest)(now) })
  row.owns(fn() {
    (shown.due)()
    // (said to move no more: nothing of it is drawn, whatever its way would have done; its rest, which names it, let
    // go of so: a ring native's counting never frees)
    shown.alive = false
    shown.rest = fn(_) { -1.0 }
  })
  |> ignore
  // (how far in, 0 … 1, as it is drawn)
  let t = fn() {
    let k = shown.shown(row)
    if k > 1.0 {
      1.0
    } else if k < 0.0 {
      0.0
    } else {
      k
    }
  }
  // (across: the finger's way while it is there; going out, put away as far as it has gone)
  let dx = fn() {
    if s.live() {
      s.dx()
    } else {
      (1.0 - t()) * width() * 0.5
    }
  }
  // (its room, and the 8 over it, opening as it comes in and closing as it goes, it on its foot: those over it moved up
  // and down with it, not at once, sizes_steady.mbt)
  row
  .padding(Is((0.0, 8.0, 0.0, 0.0)))
  .opens(
    By(fn() {
      let k = shown.shown(row)
      if k >= 1.0 {
        None
      } else {
        Some(dmax(0.0, k))
      }
    }),
    from_foot=true,
  )
  |> ignore
  let action = fn() { s.toast().action }
  // (its action while it is there: going out, none)
  let acting = fn() { action() != "" && s.live() }
  // (its ground whole by half its way in, its words from there)
  let ground = fn() { dmin(1.0, 2.0 * t()) }
  let words = fn() {
    let g = ground()
    if g > 0.0 && 2.0 * t() > 1.0 {
      (2.0 * t() - 1.0) / g
    } else {
      0.0
    }
  }
  b.box(made_for=loc, fn(tb) {
    tb
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .gap(Is(@ui.Space::px(S3)))
    .padding(By(fn() { (toast_px, toast_action_in, if acting() { toast_action_in } else { toast_px }, toast_action_in) }))
    .max_width(Is(Some(toast_max)))
    .radius(Is(toast_r))
    .glass(By(fn() { Some(@lg.liquid_toast_glass()) }))
    .edge(By(fn() { if tb.glass_solid() { @lg.liquid_overlay_solid_edge() } else { (0.0, 0L) } }))
    .shadow(By(glass_overlay_shadow))
    .shadow_outside(Is(true))
    .alpha(By(ground))
    // (in from below as it comes, moved across as it is swiped and put away: where it is, pressed and read out there
    // too)
    .offset(By(fn() { (dx(), (1.0 - t()) * toast_rise) }))
    |> ignore
    tb.box(fn(w) {
      w.padding(Is((0.0, toast_py - toast_action_in, 0.0, toast_py - toast_action_in))).shrink(Is(1.0)) |> ignore
      w.box(fn(x) {
        x
        .words(By(fn() { s.toast().title }), look=toast_words_look(Ui, L6, 400, true))
        .ink(By(fn() { library_theme().p.text }))
        .alpha(By(words))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // its action: a capsule in its end, concentric with it, while it has one
    tb.show(acting, fn(a) {
      let lit = fn() { a.pointed() || a.pressed() }
      a
      .row(Is(true))
      .min_height(Is(Some(toast_action_h)))
      .padding(Is((toast_px - toast_action_in, 1.0, toast_px - toast_action_in, 1.0)))
      .radius(Is(toast_action_h / 2.0))
      .lines_up(Is(Some(Middle)))
      .ground(By(fn() { alpha(library_theme().p.text, if lit() { 0.16 } else { 0.09 }) }))
      |> ignore
      s.action(a, action) |> ignore
      a.box(fn(w) {
        // (its words faded in after the ground, as the toast's are)
        w
        .words(By(action), look=toast_words_look(Ui, L5, 600, false))
        .ink(By(fn() { library_theme().p.text }))
        .alpha(By(words))
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// A way a toast's look goes (motion's Way, from the moment of its cause, drawn where it is at the moment it is drawn
/// while it goes): what reads it told as it ends. Said to move as it sets out, by `name` (the toaster's key and the
/// toast's id, as kit's presence is: Tester::rest_of, Tester::moving, @kit.toast_rest), till `rest` says it is done as
/// of the moment the frames are at (its end, and going out its letting go); let go with its toast (`alive` no more),
/// done.
priv struct ToastWay {
  way : @motion.Way
  ended : @signals.Signal[Int]
  mut due : () -> Unit
  name : String
  mut rest : (Double) -> Double
  mut alive : Bool
}

///|
fn ToastWay::new(v : Double, name : String) -> ToastWay {
  { way: @motion.Way::new(v), ended: @signals.signal(0), due: fn() {  }, name, rest: fn(_) { -1.0 }, alive: true }
}

///|
fn ToastWay::go(self : ToastWay, n : @view.View, to : Double, spec : @motion.Spec) -> Unit {
  (self.due)()
  self.way.go(to, spec, at=n.cause_at())
  self.due = if self.way.ends_at() >= 0.0 {
    n.at_moment(self.way.end(), fn() { self.ended.set(self.ended.untracked() + 1) })
  } else {
    fn() {  }
  }
  // (as of the moment the frames are at, as any of what is said to move answers)
  n.said_moving(self.name, "Anim \"\u{2}presence/" + self.name + "\" to \{to}", fn(now) { (self.rest)(now) })
}

///|
fn ToastWay::shown(self : ToastWay, n : @view.View) -> Double {
  self.ended.get() |> ignore
  self.way.shown_on(n)
}

///|
/// A toast's words' look: `size` and `line` as the window's theme has them, `weight`, wrapping or not.
fn toast_words_look(size : @ui.TextSize, line : @ui.Leading, weight : Int, wrap : Bool) -> @view.WordsLook {
  let th = @ui.tree_theme()
  let (px, own) = th.text_size(size)
  { size: px, weight, line: th.leading(line).unwrap_or(own), wrap, tracking: @view.letters_own, balance: false, max_lines: 0 }
}
