// A tip as nodes of the window's tree (tip's, kit's tooltip's way): what a control is for, in a few words, shown by it
// as the mouse's pointer rests on it a while (at once where another tip of the same layer went a moment before), and
// while the keyboard's focus shows on it; shut by a press on it till the hand and the focus have left it; gone as either
// leaves, as its control takes input no more (said to take no press, it or what holds it; leaving; under a modal layer:
// View::takes_input, told at that cause), or goes. Each of these at its cause's moment: the rest's end a moment of the
// timeline, its control's state as it is then; drawn beside its control by where that is as the tree is placed
// (View::beside), in its layer (over all of the window), in the look tip_look draws (small words on the primary ink),
// set as the window's theme says as that changes.

///|
fn init {
  // (the window's tooltip slot, headless's, which knows no ui: forgotten as the app begins anew)
  @ui.on_reset(@headless.tip_slot_reset)
}

///|
/// Where a window's tips are drawn (a node over all of it, as it is given when a tip is first shown) and when the last
/// of them went (another shown within tooltip_skip_ms of it at once: kit's tip_closed): one for the window's tree, made
/// and let go with what holds it. `hands`: its tips handing their ground on, the next shown at once going from where
/// the one before was drawn (@motion.Handoff, within tooltip_skip_ms of its going).
pub struct TipLayer {
  layer : () -> @view.View?
  mut went_at : Double
  priv hands : @motion.Handoff
}

///|
/// The tips' layer of a window, drawn in what `layer` gives (the node it is first shown in).
pub fn TipLayer::new(layer : () -> @view.View?) -> TipLayer {
  { layer, went_at: -1.0e18, hands: @motion.Handoff::new(within=@headless.tooltip_skip_ms) }
}

///|
/// What a tip can take over from (@motion.HandPart's tag): one on the same side of its control; one by the pointer
/// (`at_pointer`) none, nor is it taken over from.
fn tip_hand_tag(side : @view.Side, at_pointer : Bool) -> Int {
  if at_pointer {
    return -1
  }
  match side {
    Top => 0
    Right => 1
    Bottom => 2
    Left => 3
  }
}

///|
/// How a tip comes in (kit's tip_in: faded in, eased out, 120 ms); it goes symmetrically as pure fade (eased to leave).
let tip_in_ms : Double = 120.0

///|
/// A tip saying `label` (as it changes; none said: no tip) of the control `anchor`, on its `side`, in `tips` (its
/// layer over all of the window). What shows it and what shuts it as the file's head says. `delay`: how long the
/// pointer rests on it before it shows; `skip`: shown at once where another of the layer went a moment before; `gap`:
/// how far from what it is beside; `at_pointer`: beside the pointer as it moves along the control, its middle level with
/// it (a tall thin thing's: an edge, usePointerTip), not the control's middle. `within`: shown by the pointer within
/// `anchor` as it is placed (View::pointer_within), over what it holds as over itself (a bar's name, what is pressed
/// there the bar's), not by its being pointed at; without it, by `anchor` pointed at (View::pointed), whatever it takes
/// of the hand, a control or none (a mark, a status). `repeats`: it says words the control shows itself (a file's
/// name on its card), whole: shown only where they show cut short there as it would show (View::words_cut_now: any words
/// in `anchor`, as the old tip's Ctx::shows_cut), none where they show whole; once shown, it goes as any does, not as
/// they come to show whole. `shortcut`: the action that does what the control does, its keys said after the words
/// (tip's: shortcut_keys, as the app says them; none while no keyboard is at hand). `pressed`: whether what a press on
/// it lands on is held (none: `anchor` itself), where that is a control `within` it (an update's key in what holds its
/// tip): its press shuts it as one on `anchor` does.
pub fn tip_node(
  tips : TipLayer,
  anchor : @view.View,
  label : () -> String,
  side? : @view.Side = Bottom,
  delay? : Double = tip_delay_ms,
  skip? : Bool = true,
  gap? : Double = tip_gap,
  at_pointer? : Bool = false,
  within? : Bool = false,
  repeats? : Bool = false,
  shortcut? : String = "",
  pressed? : () -> Bool,
) -> TipHand {
  if within {
    anchor.points(Is(true)) |> ignore
  }
  let open : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })
  // (a finger held on its control: Held while it is down, Lifted a while once it is let go, till then or the next
  // press, wherever it lands; Free otherwise)
  let hand : @signals.Signal[TipHeld] = @signals.signal(Free, same=fn(a, b) { a == b })
  let lifted_end : Ref[() -> Unit] = Ref(fn() {  })
  let shut = Ref(false)
  let rest : Ref[(() -> Unit)?] = Ref(None)
  // (how it comes in, this time it is shown: from when, from how far in it was (shown again as it went: as far as it
  // had gone), whether it is in whole yet, and the moment that says so: this showing's own, let go as it goes)
  let fade = TipFade::new()
  let anchor_id = anchor.id()
  let owner = @headless.tip_node_owner()
  // (its ground handed on among its layer's tips: seen while its slot is its own and some of it is in)
  let glide = tips.hands.part(
    fn(t) {
      if @signals.untracked(fn() { @headless.tip_owns(owner) }) {
        fade.at(t)
      } else {
        0.0
      }
    },
    tag=tip_hand_tag(side, at_pointer),
  )
  // (made in its layer as it is first shown where there is one then (none yet: shown the next time it is, as there is
  // one), held there for its control, let go with it)
  let made = Ref(false)
  let holder_v : Ref[@view.View?] = Ref(None)
  // (Escape while it shows: its, before what is under it (a viewer it is over) is asked; gone, shut as a press shuts it)
  let escaped : Ref[() -> Unit] = Ref(fn() {  })
  let make = fn() -> Bool {
    guard (tips.layer)() is Some(l) else { return false }
    let holder = l.box(fn(h) { h.transitions_only().over(Is(true)) |> ignore }).lives_with(anchor)
    holder_v.val = Some(holder)
    holder.on_key(fn(k) {
      if k.code == @ui.key_escape && @signals.untracked(fn() { open.get() && @headless.tip_owns(owner) }) {
        (escaped.val)()
        true
      } else {
        false
      }
    })
    |> ignore
    holder.show(fn() { open.get() }, leave=@motion.pop_out_ms, fn(t) {
      tip_look_node(t, anchor_id, side, label, shortcut, fade, glide, gap, at_pointer, owner)
    })
    true
  }
  let stop_rest = fn() {
    match rest.val {
      Some(s) => s()
      None => ()
    }
    rest.val = None
  }
  let set_open = fn(on : Bool) {
    if on == open.untracked() {
      return
    }
    // (saying what its control shows whole: not shown where that shows whole as it would show, at this moment)
    if on && repeats && !anchor.words_cut_now() {
      return
    }
    let at = anchor.cause_at()
    if on {
      // (another of the layer's showing or gone a moment ago, on the same side: taken over from where it is drawn now,
      // as fast as it goes, before this one takes the window's slot from it; there before tip_settled moments,
      // @motion.hand_spring)
      let taken = glide.came(at, @motion.hand_spring, takes=skip && !at_pointer)
      if !made.val {
        made.val = make()
      }
      if made.val {
        @headless.tip_claim(owner)
      }
      match taken {
        // (in whole at once, its ground going from where the other's was to its own place, its words with it)
        Some(_) => fade.put(1.0)
        // (in, as kit's tip_in: from where it is at this moment, eased out)
        None => fade.go(anchor, 1.0, at, tip_in_ms, Out)
      }
    } else {
      // (out, as pop_out: from where it is at this moment, eased to leave, over as long as it is kept going)
      fade.go(anchor, 0.0, at, @motion.pop_out_ms, Leave)
      tips.went_at = at
      glide.left(at)
    }
    match holder_v.val {
      Some(h) if h.alive() => @view.transition(within=h, fn() { open.set(on) })
      _ => open.set(on)
    }
  }
  // (opened on its control (TipHand::open): the window's taps then, shut by the one after it)
  let opened_at = Ref(0)
  // (what decides it, as of each cause: the pointer over it (a mouse's), a press on it, the keyboard's focus shown on it,
  // whether it takes input at all, whether there is anything to say, how a finger holds it and, while that is let go
  // (Lifted) or tapped open (Opened), the window's presses or taps (View::window_downs, window_taps): read only then,
  // so a tip a finger holds not is woken by no press or tap elsewhere in the window)
  let state = fn() {
    let held = hand.get()
    (
      @ui.pointing() is Mouse && (if within { anchor.pointed_in() } else { anchor.pointed() }),
      match pressed {
        Some(f) => f()
        None => anchor.pressed()
      },
      anchor.focus_shown(),
      anchor.takes_input(),
      label() != "",
      held,
      match held {
        Lifted => anchor.window_downs()
        Opened => anchor.window_taps()
        _ => 0
      },
    )
  }
  let before = Ref((false, false, Free, 0))
  anchor.reacts(state, fn(s) {
    let (over, pressed, focused, takes, says, held, n) = s
    let (was_over, was_focused, was_held, was_n) = before.val
    before.val = (over, focused, held, n)
    // (let go by a finger that held it open: shown on a while, gone at the next press wherever it lands, or then;
    // opened on its control: shown till the next tap, wherever it lands (a press let go without dragging, as about's
    // tapped_anywhere; a finger's tap that opened it told after its control took it, so the one after that), a press
    // held, dragged or called off shutting it not)
    if held == was_held && n != was_n {
      if held == Lifted {
        (lifted_end.val)()
        hand.set(Free)
        return
      }
      if held == Opened && n > opened_at.val + 1 {
        hand.set(Free)
        return
      }
    }
    if made.val && open.untracked() && takes && says &&
      (held != Free || (!pressed && !shut.val)) &&
      ((over && !was_over) || (focused && !was_focused) || (held != Free && was_held == Free)) {
      @headless.tip_claim(owner)
    }
    let at = anchor.cause_at()
    stop_rest()
    // (held open by a finger: shown at once, as long as there is something to say and it takes input; taking none, this
    // holding over, not shown again as it takes input again)
    if held != Free {
      if says && takes {
        set_open(true)
      } else {
        (lifted_end.val)()
        hand.set(Free)
        set_open(false)
      }
      return
    }
    // (a press on it shuts it till the hand and the focus have left it: neither over it nor shown on it)
    if pressed {
      shut.val = true
    } else if !over && !focused {
      shut.val = false
    }
    if !says || !takes || shut.val || (!over && !focused) {
      set_open(false)
    } else if focused || open.untracked() {
      set_open(true)
    } else if skip && (at < tips.went_at + @headless.tooltip_skip_ms || glide.other_near(at)) {
      // (another of the layer's went a moment ago, or shows still (the hand come from it to this one, that one told it
      // left after this one is told it came): at once)
      set_open(true)
    } else {
      // (rested on a while from now: shown then, as it is then, a pointer over it carrying no press, taking input)
      rest.val = Some(
        anchor.at_moment(at + delay, fn() {
          let (over, pressed, _, takes, says, _, _) = @signals.untracked(state)
          if over && !pressed && takes && says && !shut.val {
            set_open(true)
          }
        }),
      )
    }
  })
  escaped.val = fn() {
    shut.val = true
    (lifted_end.val)()
    hand.set(Free)
    set_open(false)
  }
  // (its control let go: nothing of it left pending; escaped let go of last, as it names itself through set_open's
  // make, a ring native's counting never frees)
  anchor.owns(fn() {
    stop_rest()
    fade.stop()
    glide.gone()
    (lifted_end.val)()
    escaped.val = fn() {  }
  })
  |> ignore
  {
    hold: fn() {
      (lifted_end.val)()
      hand.set(Held)
    },
    cancel: fn() {
      (lifted_end.val)()
      hand.set(Free)
    },
    open: fn(tapped) {
      (lifted_end.val)()
      // (the tap opening it told the window after its control took it: the one after it shuts it; opened otherwise (a
      // key, a screen reader), the next)
      let now = @signals.untracked(fn() { anchor.window_taps() })
      opened_at.val = if tapped { now } else { now - 1 }
      hand.set(Opened)
    },
    opened: fn() { hand.untracked() == Opened },
    lift: fn() {
      if hand.untracked() == Held {
        hand.set(Lifted)
        lifted_end.val = anchor.at_moment(anchor.cause_at() + @headless.tooltip_lifted_ms, fn() { hand.set(Free) })
      }
    },
  }
}

///|
/// How a finger holds a tip open (tip_node): not at all, held down on its control, let go of it a moment ago, tapped open
/// (till the next tap).
#derive(Eq)
enum TipHeld {
  Free
  Held
  Lifted
  Opened
}

///|
/// What a control tells its tip of a finger (tip_node's): held on it long enough (`hold`: shown at once, as long as it
/// stays down), let go after (`lift`: shown on tooltip_lifted_ms more, or till the next press, wherever it lands),
/// called off instead (`cancel`: the system took the touch, its control was taken from the hand: gone, none of it
/// kept).
pub struct TipHand {
  hold : () -> Unit
  lift : () -> Unit
  cancel : () -> Unit
  /// shown till the next tap, wherever it lands (about's): after the finger's tap on its control that opens it where
  /// `tapped` (told the window after its control took it), else (a key, a screen reader) the next one
  open : (Bool) -> Unit
  /// whether it is so opened now (not shut since: a tap after, `cancel`)
  opened : () -> Bool
}

///|
/// How far a tip is in (0 none of it, 1 all of it) as it comes and goes (tip_node): one way at a time, from where the
/// one before had it at the moment it was turned (`from`, worked out of that one as of then: the same however far it had
/// got), to `to` over `ms` from `start` as `ease` has it; while it goes (`moving`, till the moment it ends: the clock
/// read no longer than that), the moment it ends its own, let go as another way is set out.
priv struct TipFade {
  mut from : Double
  mut to : Double
  mut start : Double
  mut ms : Double
  mut ease : @ui.Ease
  moving : @signals.Signal[Bool]
  mut due : (() -> Unit)?
}

///|
/// A tip none of which is in, going nowhere.
fn TipFade::new() -> TipFade {
  { from: 0.0, to: 0.0, start: 0.0, ms: 0.0, ease: Out, moving: @signals.signal(false, same=fn(a, b) { a == b }), due: None }
}

///|
/// How far in it is at `t`, by the way it goes now.
fn TipFade::at(self : TipFade, t : Double) -> Double {
  if self.ms <= 0.0 || t >= self.start + self.ms {
    return self.to
  }
  let p = (t - self.start) / self.ms
  self.from + (self.to - self.from) * self.ease.at(if p < 0.0 { 0.0 } else { p })
}

///|
/// It set going to `to` from `at` over `ms` as `ease` has it, from where it is at `at`; its end, the moment `node` says
/// it is (its own, the way before's let go).
fn TipFade::go(self : TipFade, node : @view.View, to : Double, at : Double, ms : Double, ease : @ui.Ease) -> Unit {
  self.from = self.at(at)
  self.to = to
  self.start = at
  self.ms = ms
  self.ease = ease
  self.stop()
  self.moving.set(true)
  self.due = Some(node.at_moment(at + ms, fn() { self.moving.set(false) }))
}

///|
/// All of it in (`to`) at once, going nowhere (shown in place of another of its layer: tip_node's handoff).
fn TipFade::put(self : TipFade, to : Double) -> Unit {
  self.from = to
  self.to = to
  self.start = 0.0
  self.ms = 0.0
  self.stop()
  self.moving.set(false)
}

///|
/// Its end's moment let go of (another way set out, its control gone).
fn TipFade::stop(self : TipFade) -> Unit {
  match self.due {
    Some(s) => s()
    None => ()
  }
  self.due = None
}

///|
/// How far in it is as drawn now: by the clock while it goes, where it went once it is there.
fn TipFade::shown(self : TipFade, t : @view.View) -> Double {
  if self.moving.get() {
    self.at(t.drawn_at())
  } else {
    self.to
  }
}

///|
/// A tip's node `t` as tip_look draws it (tip_ground, tip_edge, tip_words), beside `anchor` on `side`, saying `label`,
/// then the keys of action `shortcut` where there are any as it is shown, each a cap of its own at its end (key_caps,
/// tip_cap_node): its look and its words set as the window's theme says, as that changes; in and out as `fade` says.
/// With keys it stands `tip_key_in` over, under and after them, as tall as one without (its words' line, tip_cap_over
/// over and under it), its last cap concentric with its corners at its end (tip_cap_round), its words as far from its
/// start as a tip of words alone has them.
#callsite(autofill(loc))
fn tip_look_node(
  t : @view.View,
  anchor : @view.NodeId,
  side : @view.Side,
  label : () -> String,
  shortcut : String,
  fade : TipFade,
  glide : @motion.HandPart,
  gap : Double,
  at_pointer : Bool,
  owner : @headless.TipOwner,
  loc~ : SourceLoc,
) -> Unit {
  let theme = fn() { @ui.tree_theme() }
  let px = @ui.Space::px(S2_5)
  let py = @ui.Space::px(S1_25)
  // (whether it says keys, as it is shown: a keyboard come or gone while it shows, so the next time it is)
  let keys = @signals.untracked(fn() { key_caps(shortcut_keys(shortcut)) })
  t
  .beside(anchor, side~, along=Middle, offset=gap, at_pointer~)
  // (with keys: its words as far from its start as a tip of words alone, its last cap tip_key_in from its top, end and
  // foot, concentric with its corners there)
  .padding(
    Is(
      if keys.is_empty() {
        (px, py, px, py)
      } else if @signals.untracked(fn() { label() }) == "" {
        (tip_key_in, tip_key_in, tip_key_in, tip_key_in)
      } else {
        (px, tip_key_in, tip_key_in, tip_key_in)
      },
    ),
  )
  .max_width(Is(Some(tip_widest)))
  .radius(Is(tip_round))
  .points(Is(false))
  .glass(By(fn() {
    if @headless.tip_owns(owner) {
      Some(@lg.liquid_panel_glass(solid=panel_ground()))
    } else {
      None
    }
  }))
  .edge(By(fn() {
    if @headless.tip_owns(owner) && t.glass_solid() {
      @lg.liquid_overlay_solid_edge()
    } else {
      (0.0, 0L)
    }
  }))
  .shadow(By(fn() {
    if @headless.tip_owns(owner) {
      glass_overlay_shadow()
    } else {
      (0.0, 0.0, 0L)
    }
  }))
  .shadow_outside(Is(true))
  // (its ground in first, its words after, as kit's tip_in and pop_out have them (ground_first): the ground the first
  // half of the way in, the words the second; going, the other way round)
  .alpha(By(fn() {
    let a = if @headless.tip_owns(owner) { fade.shown(t) } else { 0.0 }
    if a * 2.0 < 1.0 {
      a * 2.0
    } else {
      1.0
    }
  }))
  .says(By(fn() { Some(@view.said(Tooltip, label=label())) }))
  .hides(By(fn() { !@headless.tip_owns(owner) }))
  |> ignore
  let words_look = fn(wrap : Bool) -> @view.WordsLook {
    let (size, line) = theme().text_size(Meta)
    { size, weight: 400, line, wrap, tracking: @view.letters_own, balance: false, max_lines: 0 }
  }
  t.box(made_for=loc, fn(w) {
    if !keys.is_empty() {
      // (its words, then its keys' caps, on its words' first line however many lines they break into: the words as
      // far from the caps' top and foot as their line is shorter than the caps)
      style_node(w, fn() { tip_key_line })
      w.box(fn(l) {
        l
        .padding(Is((0.0, tip_cap_over, 0.0, tip_cap_over)))
        .shrink(Is(1.0))
        .words(By(fn() { label() }))
        .words_look(By(fn() { words_look(true) }))
        .ink(By(fn() { library_theme().p.text }))
        |> ignore
      })
      |> ignore
      w.box(fn(q) {
        style_node(q, fn() { tip_caps_node })
        for cap in keys {
          tip_cap_node(q, cap)
        }
      })
      |> ignore
    } else {
      w.words(By(fn() { label() })).words_look(By(fn() { words_look(true) })).ink(By(fn() { library_theme().p.text })) |> ignore
    }
    // (its ground handed on among its layer's tips, its words with it: from where the one before was drawn, from its
    // middle)
    glide.draws(t, carries=w)
    w
    .alpha(By(fn() {
      // (of its ground's: what of the words shows over as much of the ground as there is)
      let a = fade.shown(t)
      let ground = if a * 2.0 < 1.0 { a * 2.0 } else { 1.0 }
      let words = if a * 2.0 - 1.0 > 0.0 { a * 2.0 - 1.0 } else { 0.0 }
      if ground > 0.0 {
        words / ground
      } else {
        0.0
      }
    }))
    |> ignore
  })
  |> ignore
}

///|
/// A key's cap in a tip's row of them (`parent`): `cap` (⌘, ⇧, K, Ctrl, Esc) in the tip's words' ink at the caption's
/// size, 500, in the middle of a box as high as the tip's words' line and tip_cap_over over and under it, as wide at
/// least, tip_cap_round round, its ground and line the tip's words mixed into its ground (opaque: no line seen through a
/// ground under it), as the theme says as that changes.
#callsite(autofill(loc))
fn tip_cap_node(parent : @view.View, cap : String, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(k) {
    style_node(k, fn() { tip_cap_node_look })
    let side = fn() { node_sp(k, @ui.tree_theme().text_size(Meta).1) + 2.0 * tip_cap_over }
    k
    .height(By(fn() { Some(side()) }))
    .min_width(By(fn() { Some(side()) }))
    .radius(Is(tip_cap_round))
    .ground(By(fn() { mix(library_theme().p.text, tip_cap_ground, panel_ground()) }))
    |> ignore
    k.box(fn(w) {
      w
      .words(Is(cap))
      .words_look(
        By(fn() {
          let (size, line) = @ui.tree_theme().text_size(Caption)
          { size, weight: 500, line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
        }),
      )
      .ink(By(fn() { mix(library_theme().p.text, tip_cap_ink, panel_ground()) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The keys of a shortcut as the app says them, each a cap of its own: on an Apple keyboard its marks (⌃ ⌥ ⇧ ⌘) one a
/// cap each and the key after them one (`⌘⇧F`, `⌘ Enter`); elsewhere each part between `+` (`Ctrl+Shift+F`), a `+`
/// where a part would be empty the key itself (`Ctrl++`). None for none.
pub fn key_caps(keys : String) -> Array[String] {
  let caps : Array[String] = []
  let is_mark = fn(c : Char) { c == '⌃' || c == '⌥' || c == '⇧' || c == '⌘' }
  let said = keys.trim(chars=" ").to_owned()
  let chars = said.to_array()
  if chars.is_empty() {
    return caps
  }
  if is_mark(chars[0]) {
    let mut at = 0
    while at < chars.length() && is_mark(chars[at]) {
      caps.push(chars[at].to_string())
      at += 1
    }
    let key = String::from_array(chars[at:]).trim(chars=" ").to_owned()
    if key != "" {
      caps.push(key)
    }
    return caps
  }
  let mut part : Array[Char] = []
  for c in chars {
    if c == '+' && !part.is_empty() {
      caps.push(String::from_array(part).trim(chars=" ").to_owned())
      part = []
    } else {
      part.push(c)
    }
  }
  if !part.is_empty() {
    caps.push(String::from_array(part).trim(chars=" ").to_owned())
  }
  caps
}

///|
/// A tip's ground: the primary ink in light (a dark charcoal over the page); in the dark not that ink (the light grey,
/// a glare of a block) but what floats lifted `tip_lift` toward the words, a step over a menu's (panel_ground).
pub fn tip_ground() -> Int64 {
  let t = theme()
  if t.dark {
    mix(t.p.text, tip_lift, t.p.raised)
  } else {
    t.p.primary
  }
}

///|
/// A tip's line (how wide, its colour): in the dark a faint one, its words' ink at `tip_edge_seen`, cutting it off a dark
/// ground; none in light, its dark ground off the light page by itself.
pub fn tip_edge() -> (Double, Int64) {
  let t = theme()
  if t.dark {
    (1.0, alpha(t.p.text, tip_edge_seen))
  } else {
    (0.0, 0L)
  }
}

///|
/// A tip's words: on the primary ink's in light, the words' own ink in the dark.
pub fn tip_words() -> Int64 {
  let t = theme()
  if t.dark {
    t.p.text
  } else {
    t.p.on_primary
  }
}

///|
let tip_lift : Double = 0.05

///|
let tip_edge_seen : Double = 0.09

///|
/// A tip's caps: how far over and under its words' line they reach (so the tip, tip_key_in round them, is as tall as one
/// of words alone, 5 round them), how round the tip is (the library's small corner), how far in from them the tip
/// stands over, under and after them (concentric: tip_round less it), and how much of the tip's words their ground and
/// words are (opaque, no line round them).
let tip_cap_over : Double = 1.0

///|
let tip_round : Double = small_corner

///|
let tip_key_in : Double = 4.0

///|
let tip_cap_round : Double = @ui.concentric(tip_round, tip_key_in)

///|
let tip_cap_ground : Double = 0.12

///|
let tip_cap_ink : Double = 0.88

///|
// kept across runs: a value (no field of it changes)
let tip_caps_node : @ui.Style = @ui.css("row gap=S0_5 align=AStart")

///|
// kept across runs: a value (no field of it changes)
let tip_cap_node_look : @ui.Style = @ui.css("row px=S1_25 align=ACenter justify=JCenter")

///|
/// How far a tip is from its control (kit's tooltip `offset`), and how wide it may grow (tip_max).
let tip_gap : Double = 6.0

///|
let tip_widest : Double = match tip_max {
  Fixed(v) => v
  _ => 0.0
}
