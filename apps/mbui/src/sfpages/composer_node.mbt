// A chat's composer made as nodes of the window's tree (composer.mbt's chat_composer, made once): its page made
// as nodes, in its messages' list's foot (chat_page_made's `foot_node`). What it holds
// and how it answers is the old composer's, said here by the tree's own mechanisms: a frosted capsule that grows into
// a box with its text, ＋ and send at its ends; opened (focused, written in, a file or a quote waiting) its words over
// its row of ＋, what is said before send and send, the quotes and files waiting over the words. One field all along
// (its node never made again as it opens or shuts: the focus, the caret and what the input method composes stay with
// it): one row that goes on to a second line once it is opened, its words the whole of the first (View::wraps), ＋
// laid over its foot's start (it stands there in either shape, the words kept clear of it while it is a capsule). What
// it holds is the draft as the core keeps it (sfbase's compose.mbt); what it reads of its chat is its head alone
// (sfbase's chat_view_now: a message patched in place reads none of it again).

///|
/// What a chat's composer made as nodes keeps of its own, each its draft's: when the cursor left it (it stays a box a
/// moment, let_go_ms), when typing last warmed its agent, the quotes' comment fields, the restores asked.
priv struct ComposingNode {
  /// a box kept a moment after the cursor left it, by draft (let_go_ms)
  held : @sf.LiveMap[String, Bool]
  /// how many times typing warmed each session's agent, and when last
  warmed : Map[String, (Int, Double)]
  /// the draft whose composer last came to show: another's coming takes the cursor
  mut shown : String
  /// the cursor put in it as its page comes (no cause of a way of its own: what the page is as it comes), and how many
  /// times it was: what changes its shape then is there at once
  mut quiet : Bool
  quiet_n : @signals.Signal[Int]
  /// the draft whose composer was given the cursor as its page came, before its field was made (its box made by the
  /// room its foot is given, after that): its field takes it as it is made
  mut focus_waits : String
  /// the chats (by their draft) whose notice's choice of how their agent goes on (the cache's, 接着聊) has its menu
  /// open: the composer under it, the cursor gone from it to the menu, not let go to a capsule (the old one's
  /// choosing_cache)
  choosing_cache : @sf.LiveMap[String, Bool]
}

///|
// kept across runs: put back by composing_reset
let composing_node : ComposingNode = {
  held: @sf.LiveMap::new(),
  warmed: {},
  shown: "",
  quiet: false,
  quiet_n: @signals.signal(0),
  focus_waits: "",
  choosing_cache: @sf.LiveMap::new(),
}

///|
/// Dedicated flight for the wide-layout composer moving between center (NewChat) and foot (Chat): uses `@ui.move_ms`
/// with `Ease::Move` and zero `up_late` so movement begins on frame 0 without the send-word stall.
// kept across runs: pure curve function
let composer_move_flight : @view.Flight = @motion.flight_scaled(
  fn(far) { if far <= 0.5 { 0.0 } else { @ui.move_ms(far) } },
  ease=Move,
)

///|
/// Last departed composer box `(was_new_chat, rect)` on wide layout, used as a fallback handoff when unmount precedes
/// `page_switch_to` during sidebar `NewChat <-> Chat` switches; cleared on `composer_node_left` and `composing_node_reset`.
// kept across runs: cleared in composing_node_reset and composer_node_left
let composer_departed : Ref[(Bool, (Double, Double, Double, Double))?] = Ref(None)

///|
/// Clear wide-layout node composer handoff state when switching to a page without a composer.
pub fn composer_node_left() -> Unit {
  composer_departed.val = None
}

///|
/// What composing_node keeps, forgotten as a run starts (composing_reset).
fn composing_node_reset() -> Unit {
  draft_sent_counts.clear()
  composer_extra_heights.clear()
  composer_departed.val = None
  composing_node.held.clear()
  composing_node.warmed.clear()
  composing_node.shown = ""
  composing_node.focus_waits = ""
  composing_node.choosing_cache.clear()
}

///|
/// The line a composer's field is laid out on at the system's size of words `scale` (field_line's, a node's).
fn node_field_line(scale : Double) -> Double {
  @ui.sp_at(scale, @ui.style_words(@sf.theme().t.words).line)
}

///|
/// How much further in a capsule's round buttons stand than its padding says (capsule_extra's, a node's).
fn node_capsule_extra(scale : Double) -> Double {
  @sf.dmax(0.0, (node_field_line(scale) - @sf.theme().round.side) / 2.0)
}

///|
/// How many lines a composer's field grows to before it scrolls, in a window `high` tall (text_lines', a node's).
fn node_text_lines(scale : Double, high : Double) -> Int {
  let n = (@sf.dmin(text_most, high * text_window_share) / node_field_line(scale)).to_int()
  if n < 1 {
    1
  } else {
    n
  }
}

///|
/// Where a chat's composer made as nodes stands: as wide as the column it is in is laid out (`wide`), at the system's
/// size of words (`scale`), in a panel of its own where `apart` (its corners `pane`: what stands in them concentric
/// with them), else alone.
priv struct Stand {
  wide : () -> Double
  /// how wide its composer is drawn now: as `wide` says, or on the column's way to another width as far between its
  /// ends as that has come (composer_width_on)
  composer_w : () -> Double
  scale : () -> Double
  apart : () -> Bool
  pane : () -> FixedArray[@ui.CornerOf]?
}

///|
/// Where it stands at a panel's foot (composer_place's, a node's): in a panel of its own whose foot corners it reaches,
/// its capsule's ends each as far in as makes it concentric with the corner it is in; else as it stands alone.
fn Stand::place(self : Stand) -> ComposerPlace {
  guard (self.apart)() else { return composer_alone }
  let wide = (self.wide)()
  let extra = node_capsule_extra((self.scale)())
  @sf.with_pane((self.pane)(), fn() {
    let d = composer_side()
    if !@sf.in_pane() || (self.composer_w)() < wide - 2.0 * d - 0.5 {
      composer_alone
    } else {
      let side = @sf.theme().round.side
      let h = @sf.foot_capsule_h(side + 2.0 * (capsule_pad_alone + extra), side)
      let (l, r, b) = @sf.foot_capsule(h, d, d)
      { capsule_in: (l - d, r - d, b - d), capsule_pad: dmax(0.0, (h - side) / 2.0 - extra), corner: @sf.pane_composer_corner() }
    }
  })
}

///|
/// `f` worked out as where it stands has it: in its panel (pane_round), its box's corner its place's (composer_round),
/// what stands in its corners following them (composer_inner, composer_round_in).
fn[T] Stand::at(self : Stand, f : () -> T) -> T {
  let corner = self.place().corner
  @sf.with_pane((self.pane)(), fn() {
    let was = @sf.composer_round.val
    @sf.composer_round.val = corner
    let out = f()
    @sf.composer_round.val = was
    out
  })
}

///|
/// What a composer made as nodes is for where it is no chat's yet (a new chat's: new_chat_node.mbt), each its own: its
/// draft (`new:<workspace>`, whichever station it is to go to), what its field says while empty, laid out roomy in the
/// page's middle as it says now (`roomy`: its words over its row even for one line, standing alone, no list's foot
/// under it; the same composer, its field kept, as the page it is in is laid out another way) with the
/// page's choices in that row after ＋ (`toolbar`), locked while nothing can run it (`locked`: it takes words, nothing
/// goes, no file comes in), what send does with what is written once it is ready (`send`), and while a chat is made for
/// it (`starting`: a turning ring in place of send's arrow); what stands over it at a list's foot (`over_it`: the page's
/// choices where they are not in its row, `over_tall` high); while it is `away` (the page leaving as it becomes its chat,
/// or nothing to run it on known yet), its box not seen, pressed, focused nor read out, its room kept. The old view's
/// ComposerSpec, as nodes read it as it changes.
pub(all) struct ComposerNodeFor {
  draft : String
  placeholder : () -> String
  roomy : () -> Bool
  toolbar : ((@view.View) -> Unit)?
  locked : () -> Bool
  send : (Writing) -> Unit
  starting : () -> Bool
  over_it : ((@view.View) -> Unit)?
  over_tall : Double
  away : () -> Bool
}

///|
/// Chat `r`'s composer made as nodes in `v` (its messages' list's foot: chat_page_made's `foot_node`), as `src` reads
/// its chat: its head alone (chat_view_now). Its tips in `tips`; `apart`, the page a panel of its own (the tape's: the
/// composer as far from its foot as from its sides, concentric with its corners `pane`); `laid`, the width its column
/// is laid out at on the page's way to another (a side panel sliding beside it: the narrower end), none at rest: how
/// far it stands from its foot is as at that end all the way, as the old composer's (composer_foot_in). Switched to as its page comes
/// to show (`shows`) from another chat's, the cursor in it with keyboard and mouse (its keyboard at hand), not taken
/// from a field in use; asked for (composer_take_focus), with touch too.
pub fn chat_composer_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  shows~ : () -> Bool,
  tips~ : @sf.TipLayer,
  apart? : () -> Bool = fn() { false },
  pane? : () -> FixedArray[@ui.CornerOf]? = fn() { None },
  laid? : () -> Double? = fn() { None },
  over_it? : (@view.View) -> Unit,
  over_full? : Bool = false,
  over_tall? : () -> Double = fn() { 0.0 },
) -> Unit {
  // (what changes in it moves only for a cause said (a key typed, the cursor come or let go, a file or a quote put in
  // or taken out by a hand here): what the core answers is there at once, @view.transition)
  v.transitions_only() |> ignore
  composer_node_of(v, src, r, None, shows~, tips~, apart~, pane~, laid~, over_it?, over_full~, over_tall~)
}

///|
/// A composer made as nodes in `v` for what is no chat yet (`made`: a new chat's), as chat_composer_node's is for a
/// chat's, writing to `made`'s draft, its files going up to `station` (ChatRef's station; no session): at the foot of
/// the page's list where it is not roomy (as a chat's composer is there, so the chat the page becomes has its own where
/// it stood), alone in the page's middle where it is. `over`: the room it keeps over itself at a list's foot (a chat's
/// 12; less where what stands over it there keeps its own room, a new chat's choices). What `made` has stand over it in
/// its foot (`over_it`, a new chat's choices: laid out narrow alone, never roomy) is drawn with its ground's top as it
/// opens or is let go, as a chat's notices are, its least as much taller (`over_tall`), so nothing round it steps.
pub fn new_composer_node(
  v : @view.View,
  src : Source,
  station : () -> String,
  made : ComposerNodeFor,
  shows~ : () -> Bool,
  tips~ : @sf.TipLayer,
  apart? : () -> Bool = fn() { false },
  pane? : () -> FixedArray[@ui.CornerOf]? = fn() { None },
  over? : Double = composer_over,
) -> Unit {
  // (the station it goes to as it is made: another picked, the page makes it again (new_chat_node's composer pick))
  let r : ChatRef = { station: @signals.untracked(station), session: "", title: "", station_name: "" }
  composer_node_of(v, src, r, Some(made), shows~, tips~, apart~, pane~, laid=fn() { None }, over~)
}

///|
/// What a chat's page lends its composer (chat_body_node's foot) to be told, at a column `wide` across and as node `u`
/// draws it, how far under the composer's foot's top the top of what it shows there is drawn (its 12 over it, the room
/// its least keeps over a capsule (node_open_room), its ground's way from a capsule to a box or back and as words left
/// it, its foot's way): the round buttons over the list (chat_floats_node) standing that far over it; written as the
/// composer is made, read as they are drawn.
// kept across runs: a kind of value lent, each lender's let go with the node that lent it (View::lends)
let composer_floats_drop_lent : @view.Lent[Ref[(@view.View, Double) -> Double]] = @view.Lent::new()

///|
/// What a chat's composer box (composer_box_node's) shares with its foot, made with the composer (composer_node_of's)
/// so what it tells the page (composer_floats_drop_lent) is there as it is made: whether what waits to go still
/// shows in it, how far it is drawn a box or a capsule (`morph`) and how much taller than it is laid out as words left
/// it (`sent_over`).
priv struct ChatBoxShared {
  extras_alive : @signals.Signal[Bool]
  morph : @motion.NodeWay
  sent_over : @motion.NodeWay
}

///|
/// chat_composer_node's and new_composer_node's: chat `r`'s composer, or (`made`) one for what is no chat yet.
fn composer_node_of(
  v : @view.View,
  src : Source,
  r : ChatRef,
  made : ComposerNodeFor?,
  shows~ : () -> Bool,
  tips~ : @sf.TipLayer,
  apart~ : () -> Bool,
  pane~ : () -> FixedArray[@ui.CornerOf]?,
  laid~ : () -> Double?,
  over? : Double = composer_over,
  over_it? : (@view.View) -> Unit,
  over_full? : Bool = false,
  over_tall? : () -> Double = fn() { 0.0 },
) -> Unit {
  let draft = match made {
    Some(m) => m.draft
    None => r.station + ":" + r.session
  }
  let w = @signals.untracked(fn() { writing(src, draft) })
  let head = fn() { if made is Some(_) { None } else { @sfbase.chat_view_now(src, r) } }
  let locked = fn() {
    match made {
      Some(m) => (m.locked)()
      None => false
    }
  }
  let offline = fn() { locked() || head().map(fn(h) { h.offline }).unwrap_or(false) }
  // (what it says before send: each thread it is copied to, as its head says)
  let note = fn() {
    match head() {
      Some(h) => h.cc.filter(fn(o) { o.on }).map(fn(o) { (o.via, o.place) })
      None => []
    }
  }
  // (its field's focus as it was, so a composer made again for another screen takes it back: let go as it is taken down)
  let had_field_focus = Ref(false)
  v.owns(fn() {
    if had_field_focus.val && composing_node.shown == draft {
      composing_node.shown = ""
    }
  })
  |> ignore
  // switched to another chat (its page come to show from another's): the cursor in it with keyboard and mouse, before
  // it is first drawn; not taken from a field in use (the switcher's, a dialog's)
  v.reacts(shows, fn(on) {
    guard on && !@signals.untracked(locked) else { return }
    let come = composing_node.shown != draft
    composing_node.shown = draft
    // (and the new chat it was, become it under the cursor where its composer had it: that cursor kept, the keyboard as
    // it was; sent from it without it (its send pressed alone), none, as the old composer's)
    let became = made is None &&
      @signals.untracked(fn() { @sfbase.fresh.became.get() }) == Some(r) &&
      @ui.field_has_focus()
    if composing.wanted || (come && became) || (come && !@sf.soft_keyboard() && !@ui.field_focused_here_node(v)) {
      // (as its page comes: opened at once, as what the page is as it comes, no way of its own)
      composing_node.quiet = true
      composing_node.quiet_n.set(composing_node.quiet_n.untracked() + 1)
      // (its field made by the room its foot is given, after this: taken as it is made, where it is not yet)
      composing_node.focus_waits = draft
      w.field.focus()
      composing_node.quiet = false
    }
  })
  // (asked for and taken: asked no more)
  v.reacts(fn() { w.field.focused() }, fn(on) {
    if v.alive() {
      had_field_focus.val = on
    }
    if on {
      composing.wanted = false
    }
  })
  // (what comes into its draft from outside its field, taken as it is told)
  // (what its box does before what is given its draft is taken in: composer_box_node's, said as it is made)
  let before_take_in : Ref[() -> Unit] = Ref(fn() {  })
  // (a new chat held with no station yet: what was given its draft left waiting till its station is known and
  // new_composer_place_node makes it anew for that station, as the old new_chat.mbt's Held("") did)
  if r.station != "" {
    take_in_node(v, src, r, w, offline, before=before_take_in)
  }
  // (its send asking the viewer where what it refers to must be shared (sfbase's outside.mbt): put up as it opens,
  // taken down as it is decided, as the asking says, whenever that changes)
  v.reacts(fn() { @sfbase.outside_asking(w.key).map(fn(s) { s.open.get() }) }, fn(_) { outside_shown(src, w.key) })
  let roomy = fn() {
    match made {
      Some(m) => (m.roomy)()
      None => false
    }
  }
  // (how far what stands in its foot is drawn off where it is laid out, as its foot's room goes its way: below)
  let foot_shift = @motion.NodeWay::new(0.0)
  // (a chat's: what its box shares with its foot, made here so the page is told where the top of what it shows is as
  // it is made (composer_floats_drop_lent), before its foot is first laid out)
  let shared : ChatBoxShared? = if made is None {
    let extras_alive = @signals.signal(
      @signals.untracked(fn() { w.files.get().length() > 0 || w.quotes.get().length() > 0 }),
      same=fn(a, b) { a == b },
    )
    // (opened as its box says, composer_box_node's `multiline` of a chat's: no `own`, never roomy)
    let multiline = fn() {
      composer_wants_open(
        w,
        roomy=false,
        focused=w.field.focused(),
        lingers=composing_node.held.get(draft).unwrap_or(false),
      ) ||
      extras_alive.get()
    }
    let morph = @motion.NodeWay::new(if @signals.untracked(multiline) { 1.0 } else { 0.0 })
    let sent_over = @motion.NodeWay::new(0.0)
    match v.lent(composer_floats_drop_lent) {
      Some(drop) => {
        let chat = r.station + "\u{1}" + r.session
        drop.val = fn(u, wide) {
          let st : Stand = {
            wide: fn() { wide },
            composer_w: fn() { composer_width_on(wide, @signals.untracked(fn() { @sfbase.column_laid(chat, u) })) },
            scale: fn() { u.words_scale() },
            apart: fn() { apart() },
            pane,
          }
          // (what stands over its box as tall as its least keeps for it (`over_tall`, its row of capsules), its notices
          // or an error making it taller than its least, its foot laid out as tall as what it holds: no room over them)
          let has_extra = w.error.get() != "" || composer_notice_kinds(src, r).length() > 0
          let slack_and_morph = if has_extra || @ui.system_tabletop() is Some(_) {
            0.0
          } else {
            let (_, _, b) = st.place().capsule_in
            let one_line = @sf.dmax(@sf.theme().round.side, node_field_line(u.words_scale()))
            let shut_h = one_line + 2.0 * st.place().capsule_pad
            let open_h = st.at(fn() { node_open_room(st, wide) - 12.0 - composer_foot_at(wide) })
            // (a capsule: its least's room over it; on its way from a capsule to a box or back, its ground's top where
            // it is drawn (composer_box_node's morph_dy))
            let slack = if multiline() { 0.0 } else { @sf.dmax(0.0, open_h - shut_h - b) }
            let k = morph.shown(u)
            let to = morph.target()
            let mdy = if k != to {
              let low = fn(t : Double) { b * (1.0 - t) }
              let high = fn(t : Double) { shut_h + (open_h - shut_h) * t }
              low(to) + high(to) - low(k) - high(k)
            } else {
              0.0
            }
            slack + mdy
          }
          over + slack_and_morph - sent_over.shown(u) + foot_shift.shown(u)
        }
      }
      None => ()
    }
    Some({ extras_alive, morph, sent_over })
  } else {
    None
  }
  // (by the width the column gives it, as it changes: never one worked out of the shell's state)
  v.by_room(fn(foot, room) {
    let chat = r.station + "\u{1}" + r.session
    let stand : Stand = {
      wide: fn() { room.width() },
      // (on the column's way to another width (a side panel opened or shut beside it), as wide as that way has it
      // between its ends, as the column's round buttons over it are (chat_jump_node): never stopped dead where its
      // width comes to be held by its sides; read as its room's width changes, which it follows already)
      composer_w: fn() {
        let w = room.width()
        composer_width_on(w, @signals.untracked(fn() { @sfbase.column_laid(chat, foot) }))
      },
      scale: fn() { foot.words_scale() },
      apart: fn() { !roomy() && apart() },
      pane,
    }
    // (the width its foot's room is worked out at: as wide as the chat's column is laid out, as its rows are, on the
    // page's way to another width (sfbase's column_laid), else the narrower end its page says, else its own)
    let rest_wide = fn() {
      let column = @sfbase.column_laid(chat, foot).laid
      if column > 0.0 {
        column
      } else {
        match laid() {
          Some(w) => w
          None => room.width()
        }
      }
    }
    // (12 over it (`over`), its foot's room under it: composer_foot_in's at rest; never less tall than it takes opened
    // with one line, so that opening or letting it go moves none of the messages: composer_open_room's, the old one's
    // least)
    // (roomy, alone in the page's middle: as tall as its box, nothing round it)
    foot
    .padding(
      By(fn() {
        if roomy() {
          (0.0, 0.0, 0.0, 0.0)
        } else {
          (0.0, over, 0.0, stand.at(fn() { composer_foot_at(rest_wide()) }))
        }
      }),
    )
    .min_height(
      By(fn() {
        match made {
          // (on a device half open, at the top of the half under the fold, the latest chats under it: no room kept over
          // it for its opening, which only pushed it off the fold's edge, tabletop.mbt)
          None if @ui.system_tabletop() is Some(_) => None
          None => Some(stand.at(fn() { node_open_room(stand, rest_wide()) }) + (over_tall)())
          Some(_) if roomy() => None
          Some(m) => Some(stand.at(fn() { node_open_room(stand, rest_wide()) }) - (composer_over - over) + m.over_tall)
        }
      }),
    )
    .lies_along(By(fn() { if made is None && @ui.system_tabletop() is Some(_) { Start } else { End } }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    // (its room under it come to another height as the page sets off on its way to another width (a side panel opened
    // or shut beside it: sfbase's column_sets_off): its height on the page's way from that moment (a Move, said there,
    // before the change is laid out, as each row's room over it is: message_row_node), what stands in it drawn from where
    // it stood on the same way, never stepped in the frame it sets off nor going on its own after the rows rest, never a
    // spring; none where its height comes out the same (View::resizes drops it))
    let set_off_at = Ref(@double.neg_infinity)
    // (as far as what sets the page off goes where that is said (column_set_off_over): its foot and what stands in it on
    // the one Move, as long)
    let set_off_over = Ref(0.0)
    @sfbase.column_set_off_each(foot, fn() {
      if foot.alive() {
        set_off_at.val = foot.cause_at()
        // (the side panel's pace where none is said)
        let over = @sfbase.column_set_off_over()
        set_off_over.val = if over > 0.0 { over } else { 360.0 }
        if foot.was_placed() {
          // (a Move as long, as the rows' rooms go and as what stands in it is drawn: `foot_shift`, below)
          foot.resizes(foot=true, spec=(@ui.move_ms(set_off_over.val), fn(p) { @ui.Ease::Move.at(p) })) |> ignore
        }
      }
    })
    let foot_was = Ref(@signals.untracked(fn() { stand.at(fn() { composer_foot_at(rest_wide()) }) }))
    foot.reacts(fn() { stand.at(fn() { composer_foot_at(rest_wide()) }) }, fn(now) {
      let at = foot.cause_at()
      if at == set_off_at.val && foot.was_placed() && now != foot_was.val {
        let by = foot_shift.value_at(at) + now - foot_was.val
        foot_shift.put(by)
        foot_shift.go(foot, 0.0, @motion.moved(over=set_off_over.val))
      }
      foot_was.val = now
    })
    // (how far its ground's top is drawn off where it is laid out as its shape goes: what is said over it with it)
    // (its box's, said as it is made, after what is over it: read as said, `drawn_top_said`)
    let drawn_top : Ref[(@view.View) -> Double] = Ref(fn(_) { 0.0 })
    let drawn_top_said = @signals.signal(0)
    let from_fresh = made is None && @signals.untracked(fn() { @sfbase.fresh.became.get() }) == Some(r)
    let over_in : @motion.NodeWay? = if from_fresh && !@ui.reduced_motion() {
      Some(@motion.NodeWay::new(0.0))
    } else {
      None
    }
    // (what stands over it drawn with its ground's top: a chat's notices; a new chat's choices where it is not roomy
    // (laid out so at once, as its page is), its page saying its own notices over it)
    let over_drawn = fn(v : @view.View) {
      drawn_top_said.get() |> ignore
      (drawn_top.val)(v) + foot_shift.shown(v)
    }
    // (wide-layout composer handoff: NewChat -> Chat on send via fresh_composer_at, or bidirectional sidebar
    // NewChat <-> Chat via composer_handoff_at / composer_departed; both use container=true morph on composer_move_flight)
    let from_at = if @signals.untracked(fn() { room.width() }) >= @sf.page_narrow_most {
      if made is None && @signals.untracked(fn() { @sfbase.fresh.became.get() }) == Some(r) {
        let was = @signals.untracked(fn() { @sfbase.fresh_composer_at.get() })
        @sfbase.fresh_composer_at.set(None)
        @sfbase.composer_handoff_at.set(None)
        composer_departed.val = None
        was
      } else {
        let was = @signals.untracked(fn() { @sfbase.composer_handoff_at.get() })
        @sfbase.composer_handoff_at.set(None)
        match was {
          Some(rect) => {
            composer_departed.val = None
            Some(rect)
          }
          None =>
            match composer_departed.val {
              Some((was_new, rect)) if was_new != (made is Some(_)) => {
                composer_departed.val = None
                Some(rect)
              }
              _ => None
            }
        }
      }
    } else {
      None
    }
    composer_foot_scrim_node(foot, roomy, made, fn() { stand.at(fn() { composer_foot_at(rest_wide()) }) })
    match made {
      None => {
        composer_notices_node(foot, src, r, tips, stand, over_drawn)
        match over_it {
          Some(f) => {
            let field_menu_hides = fn() { @ui.field_menu_now() is Some(_) && w.field.focused() }
            foot.box(fn(o) {
              o
              .width(By(fn() { Some(stand.at(if over_full { stand.wide } else { stand.composer_w })) }))
              .offset(By(fn() { (0.0, over_drawn(o)) }))
              .alpha(By(fn() {
                if field_menu_hides() {
                  0.0
                } else {
                  match over_in {
                    Some(way) => way.shown(o)
                    None => 1.0
                  }
                }
              }))
              .in_use(By(fn() { !field_menu_hides() }))
              |> ignore
              match over_in {
                Some(way) if from_at is None =>
                  way.go(o, 1.0, @motion.tween(140.0, ease=Out, delay=100.0))
                _ => ()
              }
              f(o)
            })
            |> ignore
          }
          None => ()
        }
      }
      Some({ over_it: Some(f), .. }) =>
        foot.show(fn() { !roomy() }, at_once=true, fn(o) {
          o
          .width(By(fn() { Some(stand.at(stand.composer_w)) }))
          .offset(By(fn() { (0.0, over_drawn(o)) }))
          |> ignore
          f(o)
        })
      Some(_) => ()
    }
    composer_box_node(
      foot,
      src,
      r,
      w,
      tips,
      head,
      note,
      offline,
      stand,
      foot_shift,
      fn(f) {
        drawn_top.val = f
        drawn_top_said.set(drawn_top_said.untracked() + 1)
      },
      fn() { stand.at(fn() { if roomy() { room.width() } else { (stand.composer_w)() } }) },
      from_at~,
      own=made,
      before_take_in~,
      over_in~,
      shared?,
    )
    // (what went wrong, under it)
    foot.show(at_once=true, fn() { w.error.get() != "" }, fn(e) {
      @sf.style_node(e, fn() { error_box })
      @sf.words_node(e, fn() { w.error.get() }, fn() { composer_error_words }) |> ignore
    })
  })
  |> ignore
}

///|
/// The short top-fade seam seal used while the soft keyboard is down. Reuses `p.bg` with `alpha(254/255)` so
/// `Node::covers` never blocks selection or wheel scrolling beside the composer and no new palette color is introduced.
let composer_seam_fade : Double = 18.0

///|
/// What the chat holds fades out behind the composer, so a picture or a busy message passing under its glass does not
/// drown what is being written: the page's own ground, as good as solid at the foot and clear `composer_backdrop_fade`
/// above the seam. With a soft keyboard it comes and goes with the keyboard; with keyboard and mouse it stays there.
let composer_backdrop_fade : Double = 220.0

///|
let composer_backdrop_in_ms : Double = 220.0

///|
let composer_backdrop_out_ms : Double = 200.0

///|
fn composer_foot_scrim_node(
  foot : @view.View,
  roomy : () -> Bool,
  made : ComposerNodeFor?,
  seam_h : () -> Double,
) -> Unit {
  foot.box(fn(scrim) {
    scrim
    .over(Is(true))
    .presses(Is(false))
    .width_share(Is(1.0))
    .height_share(Is(1.0))
    .lies_along(Is(End))
    .points(Is(false))
    |> ignore
    match made {
      Some(m) =>
        scrim
        .laid_nowhere(By(roomy))
        .alpha(By(fn() { if (m.away)() { 0.0 } else { 1.0 } }))
        .hides(By(m.away))
        |> ignore
      None =>
        scrim
        .laid_nowhere(By(fn() { @ui.system_tabletop() is Some(_) }))
        |> ignore
    }
    let seam_fade = if @sf.soft_keyboard() { composer_seam_fade } else { composer_backdrop_fade }
    scrim.box(fn(band) {
      band
      .width_share(Is(1.0))
      .height(By(fn() { Some(seam_h() + 6.0 + seam_fade) }))
      .fades(Is((0.0, seam_fade, 0.0, 0.0)))
      .points(Is(false))
      |> ignore
      band.box(fn(fill) {
        fill
        .width_share(Is(1.0))
        .height_share(Is(1.0))
        .points(Is(false))
        .ground(By(fn() { @sf.theme().p.bg }))
        .alpha(Is(254.0 / 255.0))
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // (the soft keyboard's fade: eased in as it comes up and out as it goes; the band above handles keyboard and mouse)
    if !@sf.soft_keyboard() {
      return
    }
    let typing = @motion.NodeWay::new(if @signals.untracked(fn() { scrim.keyboard_inset() }) > 0.0 { 1.0 } else { 0.0 })
    scrim.reacts(fn() { scrim.keyboard_inset() > 0.0 }, fn(up) {
      if up {
        typing.go_ms(scrim, 1.0, composer_backdrop_in_ms)
      } else {
        typing.go_ms(scrim, 0.0, composer_backdrop_out_ms, ease=Leave)
      }
    })
    // (made only while the keyboard is up, and as it fades out once it goes: nothing more on a chat opened without it)
    scrim.show(fn() { scrim.keyboard_inset() > 0.0 }, leave=composer_backdrop_out_ms, fn(lift) {
      lift
      .over(Is(true))
      .width_share(Is(1.0))
      .height_share(Is(1.0))
      .lies_along(Is(End))
      .points(Is(false))
      .alpha(By(fn() { typing.shown(lift) }))
      |> ignore
      lift.box(fn(band) {
        band
        .width_share(Is(1.0))
        .height(By(fn() { Some(seam_h() + 6.0 + composer_backdrop_fade) }))
        .fades(Is((0.0, composer_backdrop_fade, 0.0, 0.0)))
        .points(Is(false))
        |> ignore
        band.box(fn(fill) {
          fill
          .width_share(Is(1.0))
          .height_share(Is(1.0))
          .points(Is(false))
          .ground(By(fn() { @sf.theme().p.bg }))
          .alpha(Is(254.0 / 255.0))
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
  })
  |> ignore
}

///|
/// What a composer's box made as nodes is for: a chat's (`chat`: its `@` menu, 抄送, its agent warmed as it is typed,
/// ↑ ↓ to the chat beside it with nothing typed, what is said over it, its words sent into the chat, its foot kept as
/// it grows), or what is written for something else in it (待派发's new task): opened however little it holds
/// (`roomy`), what its field says while empty (`placeholder`, the chat's where none), whether ＋ stands in its foot
/// (`attach`: what is pasted or dropped in is taken either way), what stands in its foot's row between ＋ and send
/// (`tools`: where it goes), how much room its words leave at their end, clear of what stands over
/// its top corner (`words_end`), what send is called and shows (`sends`, `send_icon`), and what it does with what is
/// written once it is ready (`send`: composer_submit's; a chat's sends it into the chat).
priv struct BoxSpec {
  chat : Bool
  roomy : Bool
  placeholder : String
  attach : Bool
  tools : ((@view.View) -> Unit)?
  words_end : Double
  sends : () -> String
  send_icon : () -> String
  send : ((Writing) -> Unit)?
}

///|
/// A chat's composer's box (chat_composer_node's).
fn chat_box_spec() -> BoxSpec {
  {
    chat: true,
    roomy: false,
    placeholder: "",
    attach: true,
    tools: None,
    words_end: 0.0,
    sends: fn() { @sf.t("web-main.composer.send") },
    send_icon: fn() { "arrow-up" },
    send: None,
  }
}

///|
/// A composer's box made as nodes in `v` for draft `draft` on `station`, no chat's (`spec`: 待派发's new task): as wide as
/// it is given, alone (no panel's foot), what is given its draft from outside taken in (take_in_node), its tips in
/// `tips`.
fn composer_alone_node(v : @view.View, src : Source, station : String, draft : String, spec : BoxSpec, tips : @sf.TipLayer) -> Unit {
  v.transitions_only() |> ignore
  let r : ChatRef = { station, session: "", title: "", station_name: "" }
  let w = @signals.untracked(fn() { writing(src, draft) })
  // (what its box does before what is given its draft is taken in: composer_box_node's, said as it is made)
  let before_take_in : Ref[() -> Unit] = Ref(fn() {  })
  take_in_node(v, src, r, w, fn() { false }, before=before_take_in)
  v.by_room(fn(foot, room) {
    let stand : Stand = {
      wide: fn() { room.width() },
      composer_w: fn() { composer_width(room.width()) },
      scale: fn() { foot.words_scale() },
      apart: fn() { false },
      pane: fn() { None },
    }
    composer_box_node(
      foot,
      src,
      r,
      w,
      tips,
      fn() { None },
      fn() { [] },
      fn() { false },
      stand,
      @motion.NodeWay::new(0.0),
      fn(_) {  },
      fn() { room.width() },
      spec~,
      before_take_in~,
    )
  })
  |> ignore
}

///|
/// The room a composer made as nodes keeps over itself at a list's foot (composer_foot_in's 12).
let composer_over : Double = 12.0

///|
/// The blur of the composer's glass opened (its capsule's is @sf.glass_floating's, the bottom bar's): its words read
/// over it clear of what lies behind, where the bar has only marks.
let composer_open_blur : Double = 4.0

///|
/// The composer's box in `foot`, `width()` wide: its capsule or its box, its field, ＋, what it says before send, send;
/// a chat's, or as `spec` says, or a new chat's (`own`) as that says.
fn composer_box_node(
  foot : @view.View,
  src : Source,
  r : ChatRef,
  w : Writing,
  tips : @sf.TipLayer,
  head : () -> ChatView?,
  note : () -> Array[(String, String)],
  no_files : () -> Bool,
  stand : Stand,
  foot_shift : @motion.NodeWay,
  drawn_top : ((@view.View) -> Double) -> Unit,
  width : () -> Double,
  spec? : BoxSpec = chat_box_spec(),
  from_at? : (Double, Double, Double, Double)? = None,
  own? : ComposerNodeFor? = None,
  before_take_in? : Ref[() -> Unit] = Ref(fn() {  }),
  over_in? : @motion.NodeWay? = None,
  shared? : ChatBoxShared,
) -> Unit {
  let draft = w.key
  let focused = fn() { w.field.focused() }
  // (roomy, a new chat's in the page's middle: a box all along, its words over its row)
  let roomy = fn() {
    match own {
      Some(m) => (m.roomy)()
      None => false
    }
  }
  let locked = fn() {
    match own {
      Some(m) => (m.locked)()
      None => false
    }
  }
  // (what send does: a chat's into it; a new chat's its own)
  let send = fn(w : Writing) {
    match own {
      Some(m) => (m.send)(w)
      None =>
        match @signals.untracked(head) {
          Some(v) => send_in_chat_node(src, r, v, w)
          None => ()
        }
    }
  }
  // (a box while it has the cursor; lost, a capsule a moment later, let_go_ms: kept so by the cursor's leaving)
  let held = fn() { composing_node.held.get(draft).unwrap_or(false) }
  // (opened, and whether what is written can go: composer_state.mbt's, the old view's as well; and while what waits to
  // go still shows in it, leaving too: a box till that is gone, its padding and corners as they were, what is in it
  // concentric with it all the way, composer_extras_node's)
  // (a chat's made with its foot: composer_node_of's ChatBoxShared)
  let extras_alive = match shared {
    Some(sh) => sh.extras_alive
    None =>
      @signals.signal(
        @signals.untracked(fn() { w.files.get().length() > 0 || w.quotes.get().length() > 0 }),
        same=fn(a, b) { a == b },
      )
  }
  // (while a departing new-chat composer is hidden (`away()`), keep its last open/capsule shape so its fading
  // `over_it` choices never snap when clearing the draft triggers `morph.put(0.0)` while `b.resizes` holds height)
  let multiline_was = Ref(false)
  let multiline = fn() {
    if own is Some(m) && (m.away)() {
      multiline_was.val
    } else {
      let on = composer_wants_open(w, roomy=spec.roomy || roomy(), focused=focused(), lingers=held()) ||
        extras_alive.get()
      multiline_was.val = on
      on
    }
  }
  let ready = fn() { composer_ready(w, locked=locked()) }
  let scale = stand.scale
  // (send pressed, or Enter: a chat's into its chat, a new chat's as `own` says, else as `spec` says, once ready)
  let submit = fn() {
    // (a chat's: the cursor kept in its field where it was there as send was pressed (its box still held as the press
    // took the focus off it), as the old composer's send kept it, so it does not go to a capsule a moment after)
    if own is None && spec.chat && @signals.untracked(fn() { focused() || held() }) && !w.field.focused() {
      w.field.focus()
    }
    match (own, spec.send) {
      (None, Some(send)) => composer_submit(src, w, r.station, locked=false, send) |> ignore
      _ => composer_node_submit(src, w, r.station, locked, send)
    }
  }
  // (and the room under the list's last row with its ground, from the same cause, the same way: its foot's height, kept
  // to its foot, the composer growing from it: View::resizes)
  // (its height and the foot's room going their way for what changes them, said in the change of each cause: the
  // cursor come or let go, a line typed or taken out, a file or a quote put in by a hand here (View::resizes); what an
  // answer of the core's puts in is there at once, as an answer is)
  let made : Ref[@view.View?] = Ref(None)
  // (how far it is a box (1) or a capsule (0), on the way its height goes as it opens or is let go)
  let shape = @motion.NodeWay::new(if @signals.untracked(multiline) { 1.0 } else { 0.0 })
  // (how far it is drawn as a box (1) or a capsule (0) where it is opened from a capsule with nothing in it or let go to
  // one, a box of one line: laid out at once, its foot's least (node_open_room) keeping what is round it where it
  // stood, its ground, its words, ＋ and send drawn from where they stood in the shape it had, on the old one's clock
  // (composer_shape_ms), never a resize; at its end, as laid out)
  let morph = match shared {
    Some(sh) => sh.morph
    None => @motion.NodeWay::new(@signals.untracked(fn() { shape.target() }))
  }
  // (where its parts stand `k` of the way from its capsule (0) to its box of one line (1), from the left and the foot
  // of the box it is laid in opened: its capsule as far in as its place's capsule_in, its parts as far in as its
  // padding and theirs, as laid out below)
  let side = fn() { @sf.theme().round.side }
  let one_line = fn() { @sf.dmax(side(), node_field_line(scale())) }
  let shut_in = fn() { stand.place().capsule_in }
  let shut_pad = fn() { stand.place().capsule_pad + node_capsule_extra(scale()) }
  let open_in = fn() { stand.at(fn() { @sf.composer_round_in() }) }
  let between = fn(shut : Double, opened : Double, k : Double) { shut + (opened - shut) * k }
  // (drawn off where it is laid out: by where a part stands at `k` from where it stands at the way's end, across and
  // down)
  let drawn_off = fn(v : @view.View, left : (Double) -> Double, foot : (Double) -> Double) -> (Double, Double) {
    let k = morph.shown(v)
    let to = morph.target()
    if k == to {
      (0.0, 0.0)
    } else {
      (left(k) - left(to), foot(to) - foot(k))
    }
  }
  // (how far what it says while empty shows: composer_field_node's)
  // (and while a layer over the page keeps its cursor for it, parked: its own again as that layer goes)
  // (a new chat's, nor while a menu or a panel is put up at all: a press on a choice of its row opened it, the cursor
  // gone from it to that choice, what is under it saying nothing then, as the old composer's held its box)
  // (and flying in from the new chat it was (`from_at`): away till it has landed, then back as at rest)
  let hint_away = fn() { focused() || w.field.parked() || (own is Some(_) && @sf.presenting()) }
  // (and while anything is written in it; kept a box a moment after the cursor left it, while it holds no quote and no
  // file, to be let go to a capsule)
  let has_extras = fn() { w.files.get().length() > 0 || w.quotes.get().length() > 0 }
  let hint_hidden = fn() { hint_away() || w.text.get() != "" || (held() && !has_extras()) }
  let narrow_fresh = over_in is Some(_) && from_at is None
  let hint_in = @motion.NodeWay::new(
    if from_at is Some(_) || narrow_fresh || @signals.untracked(fn() { hint_away() || held() }) {
      0.0
    } else {
      1.0
    },
  )
  // (its hint's way back said by that flight: not set off again as it is first made)
  let fresh_fly = Ref(from_at is Some(_) || narrow_fresh)
  // (how much taller than it is laid out its ground is drawn, over it: what it was as words were sent from it, held as
  // long as the old composer's on this page is (sfbase's sent_out_hold_ms), then down to none on their flight's curve)
  let sent_over = match shared {
    Some(sh) => sh.sent_over
    None => @motion.NodeWay::new(0.0)
  }
  // (the moment it goes down from as tall as it was, once the way it was going on as words left it is over: -1 when
  // it is said to go down as they are sent)
  let sent_down_at = Ref(-1.0)
  // (words sent from it: its field's hint and caret away till they are half way up and out of it, as the old flight's
  // (sfbase's flight_hint_away, sent_out_away_ms): till this moment, said as they are sent (-1: none); its caret drawn
  // away by the clock till then, its hint's way back said with it, so nothing is told again as that moment comes)
  let away_until = Ref(-1.0)
  // (said as it is set: what draws its caret by it reads it anew then, at the moment they are sent)
  let away_said = @signals.signal(0)
  // (said once a moment, whatever said it first: what changes it again at the same moment, another cause of that
  // moment, goes on the one way said then, never set out again over it)
  let reshaped_at = Ref(-1.0)
  // (its page put by at rest (a chat's page kept as it is left): no shape's way then, nor the chat read for one: its
  // moment of letting go to a capsule comes due meanwhile, the cursor gone with the page)
  let foot_at_rest = Ref(false)
  foot.on_rest(fn() { foot_at_rest.val = true }, wake=fn() { foot_at_rest.val = false }) |> ignore
  let resize = fn(way : (Double, (Double) -> Double)?) {
    // (none before it is first drawn: what it is as its page comes in is there at once)
    guard foot.was_placed() && !composing_node.quiet && !foot_at_rest.val else { return }
    guard foot.cause_at() != reshaped_at.val else { return }
    reshaped_at.val = foot.cause_at()
    // (a chat's kept to its foot as it grows; elsewhere to its top, as a card is)
    match made.val {
      Some(b) => b.resizes(foot=spec.chat, spec?=way) |> ignore
      None => foot.resizes(foot=spec.chat, spec?=way) |> ignore
    }
  }
  // (a line more or fewer, what waits to go put in or taken out: a Move by how far)
  let reshape = fn() { resize(None) }
  // (said by a person's act on it (a line typed, the cursor come or let go): its way, where the page moves only for a
  // cause, @view.transition)
  let resize_moved = fn(way : (Double, (Double) -> Double)?) { @view.transition(fn() { resize(way) }) }
  // (opened from a capsule with nothing in it, or let go to one: its foot's height on its shape's way, kept to its foot,
  // said in the change of that cause (the cursor come, its moment let go after it left), the box laid out at once and
  // drawn from the shape it had (`morph`). Nothing where its least (node_open_room) holds it as tall both ways; where
  // something over it (what is said over it, what went wrong) has it taller than that least, the room it grows or
  // shrinks by goes its way, the messages over it going with it as one, never at once)
  let shape_way = fn() {
    guard foot.was_placed() && !composing_node.quiet && !foot_at_rest.val else { return }
    guard foot.cause_at() != reshaped_at.val else { return }
    // (taller than its least, opened or not, only with something over it (what is said over it) or under it (what went
    // wrong): its shape moves it then)
    guard spec.chat &&
      @signals.untracked(fn() { w.error.get() != "" || composer_notice_kinds(src, r).length() > 0 }) else {
      return
    }
    reshaped_at.val = foot.cause_at()
    @view.transition(fn() {
      foot.resizes(foot=true, spec=(composer_shape_ms, fn(p) { @ui.Ease::Move.at(p) })) |> ignore
    })
  }
  // (what waits to go put in or taken out from outside its hand here (the system's picker answering, a file shared
  // into the app or quoted from a message, a 文件 row put in, what the core gives back): its height its way too, from
  // the change that brought it, as the old composer's foot gave its list its room)
  // (taken out too, as the core answers what a hand here asked (its ✕): from that answer's moment; not what goes as
  // it is sent, which leaves at once, its ground held as it was: sent_from_node, `sent_at`)
  let sent_at = Ref(-1.0)
  // (what is given its draft from outside (a pick, a share, a quote, a drop): capsule-to-box opening is handled by
  // `morph` + `quotes_room`/`files_room` `resizes(uncut=true)` so `area` is never clipped by `box.resizes(foot=true)`)
  before_take_in.val = fn() {  }
  // (how far its words are drawn under where they are laid out as a line more of them makes its way in (`regrow`):
  // where they stood, by its top, down to where they stand; how far that line is from all of it shown)
  let grow = @motion.NodeWay::new(0.0)
  let grew = Ref(0.0)
  // (the rooms of what waits to go, over its words, while it holds any: composer_extras_node's, its top inset pad_room,
  // its quotes' and its files', each growing or shrinking its own way; and how many of each it held as last told)
  let extras_mounted = @signals.signal(
    @signals.untracked(fn() { w.quotes.get().length() > 0 || w.files.get().length() > 0 }),
    same=fn(a, b) { a == b },
  )
  let pad_room : Ref[@view.View?] = Ref(None)
  let quotes_room : Ref[@view.View?] = Ref(None)
  let files_room : Ref[@view.View?] = Ref(None)
  let counts_was = Ref(@signals.untracked(fn() { (w.quotes.get().length(), w.files.get().length()) }))
  let is_user_move = fn(v : @view.View) -> Bool {
    v.allows_transition() || @sfbase.writing_by_user(w)
  }
  // (a line more or fewer, `by` how far: its height its way as any other (resize), its words kept to its top on that way
  // as the old one's field grew, the line it grows by coming out at its words' foot, fading to it pixel by pixel, what
  // showed before untouched (the owner, 2026-10-30: 「带渐隐，但不是整行渐隐」), at the same rate)
  let regrow = fn(by : Double) {
    guard foot.was_placed() && !composing_node.quiet else { return }
    let ms = @ui.row_size_ms
    let left = grow.value_at(foot.cause_at())
    resize_moved(Some((ms, fn(p) { @ui.Ease::Move.at(p) })))
    grew.val = left + by
    grow.put(left + by)
    grow.go_ms(foot, 0.0, ms, ease=Move)
  }
  // (from none or to none, its box opened from a capsule or let go to one: its height its way, kept to its foot; one
  // more or fewer while it holds some, each room it changes in (its quotes', its files') grows or shrinks its own way
  // from its top, the other where it was, the list's foot keeping the composer's foot where it is: never laid out at
  // once where it ends, nothing of one room drawn over the other's)
  foot.reacts(fn() { (w.quotes.get().length(), w.files.get().length()) }, fn(now) {
    let (qn_was, fn_was) = counts_was.val
    counts_was.val = now
    let (qn, fn_) = now
    if qn + fn_ > 0 {
      extras_mounted.set(true)
    } else if foot.cause_at() == sent_at.val {
      extras_mounted.set(false)
    }
    let user_change = is_user_move(foot)
    if foot.cause_at() != sent_at.val &&
      foot.was_placed() &&
      !composing_node.quiet &&
      !foot_at_rest.val &&
      !@view.answering_now() &&
      foot.cause_at() != reshaped_at.val &&
      (user_change || (qn_was + fn_was > 0 && qn + fn_ > 0)) {
      // (first attachment mounting lazy `area` in this same flush: let `area`'s mount callback call resizes(uncut=true))
      if qn_was + fn_was == 0 && qn + fn_ > 0 && pad_room.val is None {
        return
      }
      // (a cause of a person's, a file added from a panel over it too (its closing no cause here): its way, the box's
      // transitions_only; uncut so attachments scale/fade into the room without clipping)
      let change = fn() {
        let mut said = false
        if (qn + fn_ > 0) != (qn_was + fn_was > 0) && pad_room.val is Some(pr) && pr.was_placed() {
          pr.resizes(uncut=true) |> ignore
          said = true
        }
        if qn != qn_was && quotes_room.val is Some(qr) && qr.was_placed() {
          qr.resizes(uncut=true) |> ignore
          said = true
        }
        if fn_ != fn_was && files_room.val is Some(fr) && fr.was_placed() {
          fr.resizes(uncut=true) |> ignore
          said = true
        }
        if said {
          reshaped_at.val = foot.cause_at()
        } else {
          reshape()
        }
      }
      if foot.allows_transition() {
        change()
      } else {
        @view.transition(within=foot.transitions_root(), change)
      }
    }
  })
  foot.box(fn(box) {
    // (a capsule as wide as the box less its place's capsule_in either side, its margin's (below): centred in the
    // foot, concentric with the corner it is in)
    box.width(
      By(fn() {
        let w = width()
        if multiline() {
          Some(w)
        } else {
          let (l, r, _) = stand.place().capsule_in
          Some(@sf.dmax(0.0, w - l - r))
        }
      }),
    )
    |> ignore
    // (a new chat's while it is away: its room alone)
    match own {
      Some(m) =>
        box
        .alpha(By(fn() { if (m.away)() { 0.0 } else { 1.0 } }))
        .points(By(fn() { !(m.away)() }))
        .hides(By(m.away))
        .in_use(By(fn() { !(m.away)() }))
        |> ignore
      None => ()
    }
    // (drawn off where it is laid out as its foot's room goes its way on the page's: chat_composer_node's foot_shift)
    box.offset(By(fn() { (0.0, foot_shift.shown(box)) })) |> ignore
    made.val = Some(box)
    // (a chat's alone: what flies from it and what is set beside it find it)
    if spec.chat {
      let entry = (box, foot, sent_over, foot_shift)
      composer_nodes[draft] = entry
      let extra_fn = fn() {
        let (box_was, box_speed) = box.height_going_now()
        let was = if box_speed != 0.0 {
          box_was
        } else {
          let mut dh = 0.0
          for rm_opt in [pad_room.val, quotes_room.val, files_room.val] {
            if rm_opt is Some(rm) {
              let (rh, rv) = rm.height_going_now()
              if rv != 0.0 {
                dh = dh + (rh - rm.placed_now().3)
              }
            }
          }
          box_was + dh
        }
        let wide = (stand.wide)()
        let one = stand.at(fn() { node_open_room(stand, wide) - 12.0 - composer_foot_at(wide) })
        @sf.dmax(0.0, was - one)
      }
      composer_extra_heights[draft] = extra_fn
      // (none found while its page is put by at rest (a chat's page kept as it is left: drawn nowhere, where it is not
      // the window's), nor once it is let go; found again as it wakes)
      box.on_rest(
        fn() {
          if composer_nodes.get(draft) is Some(now) && now.0.id() == box.id() {
            if !@ui.reduced_motion() && box.was_placed() {
              composer_departed.val = Some((own is Some(_), box.placed_window_now()))
            }
            composer_nodes.remove(draft)
            composer_extra_heights.remove(draft)
          }
        },
        wake=fn() {
          if box.alive() {
            composer_nodes[draft] = entry
            composer_extra_heights[draft] = extra_fn
            // (kept chat page woken from a wide NewChat sidebar switch: morph composer from departed box)
            if !@ui.reduced_motion() && @signals.untracked(stand.wide) >= @sf.page_narrow_most {
              let wake_from = match @signals.untracked(fn() { @sfbase.composer_handoff_at.get() }) {
                Some(rect) => {
                  @sfbase.composer_handoff_at.set(None)
                  composer_departed.val = None
                  Some(rect)
                }
                None =>
                  match composer_departed.val {
                    Some((was_new, rect)) if was_new != (own is Some(_)) => {
                      composer_departed.val = None
                      Some(rect)
                    }
                    _ => None
                  }
              }
              match wake_from {
                Some((fx, fy, fw, fh)) =>
                  box.flies_in(
                    composer_move_flight,
                    fn(_) { Some((fx, fy, fw, fh)) },
                    up_late=0.0,
                    container=true,
                    far_of=sent_far,
                  )
                  |> ignore
                None => ()
              }
            }
          }
        },
      )
      |> ignore
    }
    // (narrow NewChat -> Chat height handoff: preserve multi-line / attachment / quote height on frame 0 and collapse
    // smoothly with the same sent_out_hold_ms + Ease::Flight curve as in-chat sends)
    if own is None && @signals.untracked(fn() { @sfbase.fresh.became.get() }) == Some(r) {
      let handoff_over = @signals.untracked(fn() { @sfbase.fresh_composer_over.get() })
      @sfbase.fresh_composer_over.set(0.0)
      if !@ui.reduced_motion() && handoff_over > 0.5 {
        let hold = @sfbase.sent_out_hold_ms
        sent_over.put(handoff_over)
        sent_over.go(box, 0.0, @motion.tween(@ui.move_most_ms - hold, ease=Flight, delay=hold))
      }
      if narrow_fresh && !@signals.untracked(hint_hidden) {
        hint_in.go(foot, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay=@sfbase.sent_out_away_ms()))
      }
    }
    // (true container morph from the departing composer's full (fx, fy, fw, fh) on composer_move_flight with
    // up_late=0.0 and container=true: no top-cut, no initial stall, children kept 1:1)
    match from_at {
      Some((fx, fy, fw, fh)) => {
        let start_at = box.cause_at()
        box.flies_in(
          composer_move_flight,
          fn(to) {
            let from = (fx, fy, fw, fh)
            let (dur, _) = (composer_move_flight.way)(sent_far(from, to))
            let ms = @sf.dmax(1.0, dur)
            let holds = fn() { w.text.get() != "" || w.files.get().length() > 0 || w.quotes.get().length() > 0 }
            if !@signals.untracked(fn() { focused() || w.field.parked() || (held() && !holds()) }) {
              hint_in.put_at(
                foot,
                0.0,
                1.0,
                @motion.tween(@sf.hint_back_ms, ease=Out, delay=ms),
                start_at,
              )
            }
            match over_in {
              Some(way) =>
                way.put_at(
                  foot,
                  0.0,
                  1.0,
                  @motion.tween(@sf.hint_back_ms, ease=Out, delay=ms),
                  start_at,
                )
              None => ()
            }
            Some(from)
          },
          up_late=0.0,
          container=true,
          far_of=sent_far,
        )
        |> ignore
      }
      None => ()
    }
    // (as tall as it was as words left it while it was going: once that way has slowed to rest, down on the flight's
    // curve from the moment what flies from it begins its rise (sent_out_hold_ms after), or from then if that is past,
    // to come to none as it would have)
    box.reacts(fn() { sent_over.goes(box) }, fn(going) {
      let start = sent_down_at.val
      if !going && start >= 0.0 {
        sent_down_at.val = -1.0
        let now = box.cause_at()
        let hold = @sfbase.sent_out_hold_ms
        let end = start - hold + @ui.move_most_ms
        let from = if start > now { start } else { now }
        if end > from {
          sent_over.go(box, 0.0, @motion.tween(end - from, ease=Flight, delay=from - now))
        } else {
          sent_over.put(0.0)
        }
      }
    })
    let sent_hold = fn() {
      // (its hint and caret away from this moment till the words sent are half way out of it, then its hint back as at
      // rest without the cursor)
      let at = box.cause_at()
      sent_at.val = at
      extras_mounted.set(false)
      // (words or quotes going: files alone leave it where it is, as the old flight's, flight_hint_away)
      let words_go = @signals.untracked(fn() {
        w.text.get().trim(chars=" \n\t") != "" || w.quotes.get().length() > 0
      })
      if words_go {
        @sfbase.sent_out_told(draft, at)
        away_until.val = at + @sfbase.sent_out_away_ms()
        away_said.set(away_said.untracked() + 1)
        hint_in.put(0.0)
        // (back as at rest without the cursor once they are half way out, said now: nothing set off at that moment)
        if !@signals.untracked(hint_hidden) {
          hint_in.go(foot, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay=@sfbase.sent_out_away_ms()))
        }
      }
      // (as tall as it is at this moment, all it held still in it, and as fast as its height went on a way then (View::
      // height_going_now: nothing laid out for it, a layout here laying its list out with the row sent and not the
      // composer emptied); to its one line's box, as it is laid out once emptied)
      // (or the rooms of what waits to go on their ways within it, the box at rest: as tall as those have it now)
      let (box_was, box_speed) = box.height_going_now()
      let (was, speed) = if box_speed != 0.0 {
        (box_was, box_speed)
      } else {
        let mut dh = 0.0
        let mut v = 0.0
        for room in [pad_room.val, quotes_room.val, files_room.val] {
          if room is Some(rm) {
            let (rh, rv) = rm.height_going_now()
            if rv != 0.0 {
              dh = dh + (rh - rm.placed_now().3)
              v = v + rv
            }
          }
        }
        (box_was + dh, v)
      }
      let wide = (stand.wide)()
      let one = stand.at(fn() { node_open_room(stand, wide) - 12.0 - composer_foot_at(wide) })
      if was > one || speed != 0.0 {
        // (its foot down at once, words sent from it: what stands beside the list by that foot (对话目录's rail) told
        // how far, and from when, as the old one's tells it: sfbase's chat_foot_dropped)
        if was > one && words_go {
          @sfbase.chat_foot_dropped.set(Some((draft, at, was - one)))
        }
        let hold = @sfbase.sent_out_hold_ms
        sent_over.put(was - one)
        if speed != 0.0 {
          // (on a way as it was sent: slowing to rest from as fast as it went, as the old one's (@motion.stop_for), not
          // stopped dead; down from there once that way is over: `sent_down_at`)
          sent_down_at.val = at + hold
          // (to where that way slows to rest of itself (as Anim::stop_at has it): never past it and back)
          let ahead = @ui.move_stop_points(speed)
          let stop_to = @sf.dmax(0.0, if speed >= 0.0 { was - one + ahead } else { was - one - ahead })
          sent_over.go(box, stop_to, @motion.Moved(1.0, -1.0, 0.0), velocity=speed * 1000.0)
        } else {
          // (held so till what flies from it begins its rise, then down on their flight's curve)
          sent_down_at.val = -1.0
          sent_over.go(box, 0.0, @motion.tween(@ui.move_most_ms - hold, ease=Flight, delay=hold))
        }
      }
    }
    if spec.chat {
      composer_sent_holds[draft] = sent_hold
    }
    // (its ground as drawn now off where it is laid out, as node `v` draws it: from its capsule to its box of one line
    // or back (`morph`), or as tall as it was as words left it (`sent_over`); what stands over it going with its top:
    // chat_composer_node's `drawn_top`)
    let morph_dy = fn(v : @view.View) -> Double {
      let k = morph.shown(v)
      let to = morph.target()
      if k != to {
        let (_, _, b) = shut_in()
        let shut_h = one_line() + 2.0 * stand.place().capsule_pad
        let open_h = stand.at(fn() { node_open_room(stand, (stand.wide)()) - 12.0 - composer_foot_at((stand.wide)()) })
        let low = fn(k : Double) { between(b, 0.0, k) }
        let high = fn(k : Double) { between(shut_h, open_h, k) }
        low(to) + high(to) - low(k) - high(k)
      } else {
        0.0
      }
    }
    let ground_now = fn(v : @view.View) -> @view.GroundShape {
      let over = sent_over.shown(v)
      let k = morph.shown(v)
      let to = morph.target()
      if k != to {
        // (from its capsule to its box of one line, or back: its sides, its foot and its height between the two)
        let (l, r, b) = shut_in()
        let shut_h = one_line() + 2.0 * stand.place().capsule_pad
        let open_h = stand.at(fn() { node_open_room(stand, (stand.wide)()) - 12.0 - composer_foot_at((stand.wide)()) })
        let left = fn(k : Double) { between(l, 0.0, k) }
        let right = fn(k : Double) { between(r, 0.0, k) }
        let low = fn(k : Double) { between(b, 0.0, k) }
        let high = fn(k : Double) { between(shut_h, open_h, k) }
        // (as tall as words left it as well, where they were sent on its way: `sent_over` with it, never let go of)
        {
          dx: left(k) - left(to),
          dy: low(to) + high(to) - low(k) - high(k) - over,
          dw: left(to) + right(to) - left(k) - right(k),
          dh: high(k) - high(to) + over,
          corners: None,
        }
      } else if over > 0.0 {
        { dx: 0.0, dy: -over, dw: 0.0, dh: over, corners: None }
      } else {
        @view.ground_as_laid
      }
    }
    drawn_top(fn(v) { ground_now(v).dy })
    box.ground_drawn(By(fn() { ground_now(box) }))
    |> ignore
    box.owns(fn() {
      match composer_nodes.get(draft) {
        Some((b, _, _, _)) if b.id() == box.id() => {
        if !@ui.reduced_motion() && box.was_placed() {
          composer_departed.val = Some((own is Some(_), box.placed_window_now()))
        }
        composer_nodes.remove(draft)
        composer_extra_heights.remove(draft)
        composer_sent_holds.remove(draft)
      }
        _ => ()
      }
    })
    |> ignore
    // words dragged in from another app and let go on it beside its field (its ＋, send, its edge: on the field they
    // go where they were let go): into its field at its caret, as a paste's; files from this machine's Finder let go on
    // it (or on its field) where it is a station of the chat's workspace: by its station and path, named so or sent as
    // files as the chat takes what is dragged in (the old composer's cap: c.paths_into, c.words_into); elsewhere (or
    // where the host says no paths, as Windows' does) read and put in as files picked are (c.files_into); either way
    // given to the draft, whose taker says where it takes no files (take_in_node)
    @ui.paths_into(
      box,
      w.field,
      fn(paths) {
        @sfbase.files_into_many(w.key, @sfbase.finder_dragged(src, paths))
      },
      takes=fn() { @sfbase.finder_by_station_in(@sfbase.workspace_of(r.station)) },
    )
    |> @ui.files_into(w.field, fn(files) { @sfbase.picked_files_into(w.key, files) })
    |> @ui.words_into(w.field)
    |> ignore
    // (its ground the floating glass, the accent's over it while a file is dragged over: a 文件 tab's row, files from
    // the computer the page takes)
    box
    .glass(
      By(fn() {
        // (a row carried from a 文件 tab in the app's own hand, the pointer taken by what carries it, so not lit: where
        // it would land were it let go now, as chat_drop_node finds it; files from outside the app as the hand lights it)
        let over = box.pointer_piece(fn(_, _) {
          guard (@sfbase.drag_carried.val)() is Some(_) else { return 0 }
          let (x, y) = box.tree.pointer_said()
          match box.tree.drop_at(x, y) {
            Some(OnNode(id)) | Some(OnOld(id)) if box.tree.holds(box.id(), id) => 1
            _ => 0
          }
        }) ==
          1
        let dragging = !no_files() && (@sfbase.drag_carried.val)() is Some(_) && (over || @sf.lit_node(box))
        let base = @sf.glass_floating(
          tint?=if dragging { Some(@sf.alpha(@sf.theme().p.accent, drag_tint)) } else { None },
        )
        // (frosted more as it opens, on its shape's way: words written over it read clear of what lies behind; as a
        // capsule the bottom bar's 2.1, shared with the capsule over it)
        let open = shape.shown(box)
        let glass = if open > 0.0 {
          { ..base, blur: base.blur + (composer_open_blur - base.blur) * open }
        } else {
          base
        }
        Some(glass.sharing())
      }),
    )
    // (persistent liquid glass control shadow (@sf.glass_control_shadow), outside its outline only: the glass bends
    // nothing of it)
    .shadow(By(fn() { @sf.glass_control_shadow() }))
    .shadow_outside(Is(true))
    // (round as a capsule is, or as its box's corner; from one to the other as its height goes its way: drawn, as a
    // control answering, never laid out again for it)
    .radius(
      By(fn() {
        let pill = (@sf.theme().round.side + 2.0 * (stand.place().capsule_pad + node_capsule_extra(scale()))) / 2.0
        let k = stand.place().corner
        let p = shape.shown(box)
        pill + (k - pill) * p
      }),
    )
    // (a capsule further in than the box by its place's capsule_in, from its left, its right and its foot)
    .margin(
      By(fn() {
        if multiline() {
          (0.0, 0.0, 0.0, 0.0)
        } else {
          let (l, r, b) = stand.place().capsule_in
          (l, 0.0, r, b)
        }
      }),
    )
    .padding(
      By(fn() {
        if multiline() {
          let p = @sf.composer_pad
          (p, p, p, p)
        } else {
          let pad = stand.place().capsule_pad
          let extra = node_capsule_extra(scale())
          (pad + extra, pad, pad + extra, pad)
        }
      }),
    )
    // (the I-beam over it; a new chat's locked, none)
    .cursor(
      match own {
        Some(m) => By(fn() { if (m.locked)() { None } else { Some(IBeam) } })
        None => Is(Some(IBeam))
      },
    )
    |> ignore
    // (what waits to go over its words: its quotes, its files)
    composer_extras_node(
      box,
      src,
      r,
      w,
      tips,
      stand,
      extras_alive,
      extras_mounted,
      foot_at_rest,
      sent_at,
      reshaped_at,
      is_user_move,
      grow,
      morph_dy,
      pad_room,
      quotes_room,
      files_room,
    )
    // (`@` and a few letters: the chats they find, over it: a chat's)
    if spec.chat {
      ref_menu_node(box, src, r, w)
    }
    // (its words, then what is said before send and send: one line as a capsule, ＋ laid over its start; opened, the
    // words the whole of the first line, the rest on a second, at its end)
    box.box(fn(line) {
      // (a press on its words' row beside its field is its field's, the cursor put in it; one on what waits to go over
      // it is that one's, as the old composer's cards took theirs, never the field's. Taken by what lies under the row,
      // not the row itself: what is drawn small on it (send) reached from round it as far as its press's room holds,
      // over the row's own, as the old composer's (reach.mbt's `cut` is only by what holds it). Secondary click on that
      // backdrop opens the field's editing menu via field_menu_on, which skips touch long-press.)
      // (with what stands between ＋ and send (a station choice, as tall as a row's press room, past the row's foot):
      // the box's own, under all it holds, as nothing it holds overlaps it; none while it is locked)
      let focus = fn() {
        if !locked() {
          w.field.focus()
        }
      }
      if spec.tools is None {
        line.box(fn(under) {
          under
          .over(Is(true))
          .takes(fn(w, h, _) {
            let dy = morph_dy(under)
            if dy <= 0.0 {
              [(0.0, 0.0, w, h)]
            } else if dy < h {
              [(0.0, dy, w, h - dy)]
            } else {
              []
            }
          })
          .on_press(focus)
          |> ignore
          @ui.field_menu_on(under, w.field, enabled=fn() { !locked() })
        })
        |> ignore
      } else {
        box.on_press(focus) |> ignore
        line.box(fn(under) {
          under.over(Is(true)) |> ignore
          @ui.field_menu_on(under, w.field, enabled=fn() { !locked() })
        })
        |> ignore
      }
      line
      .row(Is(true))
      // (its parts a point apart, as the capsule's are: composer_box's)
      .gap(Is(1.0))
      .lies_along(Is(End))
      .lines_up(Is(Some(Middle)))
      .wraps(By(fn() { if multiline() { Some(@ui.Space::px(S2_5)) } else { None } }))
      |> ignore
      line.box(fn(words) {
        words
        // (cut to what shows of it as a line more makes its way in, softly at that foot: `grow`)
        .clips(Is(true))
        .clips_past(By(fn() { -grow.shown(words) }))
        .fades(
          By(fn() {
            let left = grow.shown(words)
            (0.0, 0.0, 0.0, if left > 0.0 { @ui.cut_soft(grew.val - left, left) } else { 0.0 })
          }),
        )
        .grow(Is(1.0))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .width_share(By(fn() { if multiline() { 1.0 } else { 0.0 } }))
        // (a row, its field growing across it: on one line as high as the capsule's round buttons, its line in their
        // middle (text_shut); opened, as tall as its lines (text_open))
        .row(Is(true))
        .min_height(
          By(fn() {
            if multiline() {
              None
            } else {
              Some(@sf.dmax(@sf.theme().round.side, node_field_line(scale())))
            }
          }),
        )
        .lines_up(By(fn() { if multiline() { Some(Start) } else { Some(Middle) } }))
        .margin(
          By(fn() {
            if multiline() {
              (0.0, 0.0, 0.0, 0.0)
            } else {
              (@sf.theme().round.side + 1.0, 0.0, 0.0, 0.0)
            }
          }),
        )
        .padding(By(fn() { if multiline() { (8.0, 8.0, 8.0 + spec.words_end, 0.0) } else { (0.0, 0.0, 8.0, 0.0) } }))
        // (its field: on one line past ＋ in the capsule's middle, opened over the row of ＋ and send)
        .offset(
          By(fn() {
            let (x, y) = drawn_off(
              words,
              fn(k) { between(shut_in().0 + shut_pad() + side() + 1.0, @sf.composer_pad + 8.0, k) },
              fn(k) {
                between(
                  shut_in().2 + stand.place().capsule_pad + (one_line() - node_field_line(scale())) / 2.0,
                  open_in() + side() + 10.0,
                  k,
                )
              },
            )
            (x, y + grow.shown(words))
          }),
        )
        |> ignore
        composer_field_node(
          words,
          src,
          r,
          w,
          scale,
          fn() { hint_in.shown(words) },
          fn() {
            away_said.get() |> ignore
            words.drawn_while(fn(t) { t < away_until.val }) < away_until.val
          },
          spec, submit, fn(on) {
          if on {
            // (the cursor come in by a person's act: what it changes goes its way; as its page comes (`quiet`), at once)
            let opened = fn() {
              // (from a capsule: opened as the cursor comes in, a box of one line, drawn from the capsule: `morph`)
              // (a capsule till now: kept by nothing, holding nothing)
              let shut = @signals.untracked(fn() {
                !held() && w.text.get() == "" && w.files.get().length() == 0 && w.quotes.get().length() == 0
              })
              if shut {
                shape_way()
              }
              composing_node.held.set(draft, true)
            }
            if composing_node.quiet {
              opened()
            } else {
              @view.transition(opened)
            }
          }
        }, regrow, placeholder?=own.map(fn(m) { m.placeholder }), locked~, no_files~)
      })
      |> ignore
      // (a new chat's choices in its row, after ＋, as far in as ＋ leaves them (＋ concentric with the box's foot corner,
      // its side and S1 past it: composer.mbt's tools_row, `choices`); what is left of the row theirs, send at its end)
      match own {
        Some({ toolbar: Some(tools), .. }) =>
          // (as the page is laid out roomy or not: there at once, no way in or out, #5767)
          line.show(roomy, at_once=true, fn(t) {
            t
            .row(Is(true))
            .gap(Is(@ui.Space::px(S1)))
            .lines_up(Is(Some(Middle)))
            .grow(Is(1.0))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            .margin(
              By(fn() {
                let d = stand.at(fn() { @sf.composer_round_in() }) - @sf.composer_pad
                (d + @sf.theme().round.side + @ui.Space::px(S1), 0.0, 0.0, d)
              }),
            )
            |> ignore
            tools(t)
          })
          |> ignore
        _ => ()
      }
      line.box(fn(tail) {
        tail
        .row(Is(true))
        .gap(Is(@ui.Space::px(S1)))
        .lines_up(Is(Some(Middle)))
        .shrink(Is(0.0))
        // (send at its end: in the capsule's end, opened in its foot corner)
        .offset(
          By(fn() {
            drawn_off(tail, fn(k) { -between(shut_in().1 + shut_pad(), open_in(), k) }, fn(k) {
              between(shut_in().2 + stand.place().capsule_pad + (one_line() - side()) / 2.0, open_in(), k)
            })
          }),
        )
        // (opened, its send round in the box's foot corner, concentric with it: composer_round_in)
        .margin(
          By(fn() {
            if multiline() {
              let d = stand.at(fn() { @sf.composer_round_in() }) - @sf.composer_pad
              (0.0, 0.0, d, d)
            } else {
              (0.0, 0.0, 0.0, 0.0)
            }
          }),
        )
        |> ignore
        // (抄送 once opened, in a chat its agents' threads are copied from)
        // (抄送 and where it is copied, made only in a chat copied elsewhere)
        tail.show(fn() { (multiline() && cc_shown(head())) || note().length() > 0 }, fn(cc) {
          cc.row(Is(true)).gap(Is(@ui.Space::px(S1))).lines_up(Is(Some(Middle))) |> ignore
          cc.show(fn() { multiline() && cc_shown(head()) }, fn(t) { cc_chooser_node(t, src, r, head, tips) })
          cc.show(fn() { note().length() > 0 }, fn(n) {
          @sf.style_node(n, fn() { cc_note_box })
          n.each(note, fn(o) { o.0 + "\u{1}" + o.1 }, fn(p, o) {
            let (via, place) = @signals.untracked(fn() { o.get() })
            @sf.style_node(p, fn() { cc_place })
            cc_mark_node(p, via)
            @sf.words_node(p, fn() { place }, fn() { cc_words }) |> ignore
          })
        })
        })
        // (what it says of where it goes, where it says so: from ＋'s end, as far as send leaves, as tall as ＋ and send,
        // what it holds centred on theirs whatever its own press room: a station choice is as tall as a row, ＋ and send
        // are round)
        match spec.tools {
          Some(tools) => {
            tail.grow(Is(1.0)) |> ignore
            tail.box(fn(gap) {
              gap
              .grow(Is(1.0))
              .shrink(Is(1.0))
              .min_width(Is(Some(0.0)))
              .row(Is(true))
              .lines_up(Is(Some(Middle)))
              .height(By(fn() { Some(side()) }))
              .padding(By(fn() { (open_in() - @sf.composer_pad + side() + 6.0, 0.0, 6.0, 0.0) }))
              |> ignore
              tools(gap)
            })
            |> ignore
          }
          None => ()
        }
        // (send: the library's, its arrow alone in a chat's (its own draft never makes a chat), a new chat's turning
        // while its chat is made)
        let starting = match own {
          Some(m) => m.starting
          None => fn() { false }
        }
        @sf.send_button_node(tail, spec.sends, ready, starting, submit, tips~, icon_now=spec.send_icon)
        |> ignore
      })
      |> ignore
    })
    |> ignore
    // (＋ over its foot's start, in either shape: in its capsule's start; opened, in its box's foot corner, concentric
    // with it)
    // (laid over the box from its foot's start, no box of its own round it: as far in as the capsule's round end
    // leaves it, or concentric with the box's foot corner)
    if spec.attach {
    attach_node(box, src, w, tips, no_files, place=fn(b) {
      b
      .over(Is(true), edges=(Some(0.0), None, None, Some(0.0)))
      // (in the capsule's start, opened in its foot corner)
      .offset(
        By(fn() {
          drawn_off(b, fn(k) { between(shut_in().0 + shut_pad(), open_in(), k) }, fn(k) {
            between(shut_in().2 + shut_pad(), open_in(), k)
          })
        }),
      )
      .margin(
        By(fn() {
          if multiline() {
            let d = stand.at(fn() { @sf.composer_round_in() })
            (d, 0.0, 0.0, d)
          } else {
            // (as far from the capsule's foot as from its start, as send is from its end: concentric with it)
            let d = shut_pad()
            (d, 0.0, 0.0, d)
          }
        }),
      )
      |> ignore
    })
    }
  })
  |> ignore
  // (its corners going from a capsule's to its box's as it opens, and back as it is let go, as far as its height
  // goes then: a Move over the height between them)
  let quiet_was = Ref(@signals.untracked(fn() { composing_node.quiet_n.get() }))
  let first = Ref(true)
  // (whether anything is in it: what is written, what waits to go)
  let held_in = fn() { w.text.get() != "" || w.files.get().length() > 0 || w.quotes.get().length() > 0 }
  // (roomy as the window's width has it: crossed by the window resized, its shape there at once, no motion)
  let roomy_was = Ref(@signals.untracked(roomy))
  foot.reacts(fn() { (multiline(), composing_node.quiet_n.get(), roomy()) }, fn(now) {
    let (on, quiet, roomy_now) = now
    let resized = roomy_now != roomy_was.val
    roomy_was.val = roomy_now
    let to = if on { 1.0 } else { 0.0 }
    // (opened as its page came, the cursor put in it then: there at once; ignore quiet_n bumped by another page's
    // composer mounting, e.g. the incoming Chat composer while a departing NewChat's choices fade out; so too as the
    // window resized changes it)
    let quiet_changed = quiet != quiet_was.val
    quiet_was.val = quiet
    if first.val || (quiet_changed && composing_node.shown == draft) || !foot.was_placed() || resized {
      first.val = false
      shape.put(to)
      morph.put(to)
    } else if to != shape.target() {
      // (opened from a capsule or let go to one with nothing in it before or after, the cursor come or gone: a box of
      // one line, in its foot's least, drawn there; with something put in or taken out, its height its way, laid out;
      // changed by no person's act (the window resized), there at once)
      // (emptied by words sent from it, in the very frame they are sent: its foot closing on its way, not at once,
      // under what it holds as it was sent: sent_hold's)
      let on_send = foot.cause_at() == sent_at.val
      if !is_user_move(foot) && !on_send {
        shape.put(to)
        morph.put(to)
      } else {
        // det-ok(motion-length): the field opening past ＋ and send kept off them on this clock, as the old one's
        shape.go_ms(foot, to, composer_shape_ms, ease=Move)
        // det-ok(motion-length): smooth morph between capsule and expanded box even when attachments arrive or leave
        morph.go_ms(foot, to, composer_shape_ms, ease=Move)
      }
    }
  })
  // (what it says while empty only on it at rest without the cursor, so it never moves with its shape (composer_hint's):
  // gone at once as the cursor comes in or the box is kept, or as it goes from a box to a capsule or back (a quote or a
  // file taken out, the last of them); back over hint_back_ms once it is at rest without the cursor and its shape's way
  // there is over)
  // (its shape as the old one's composer_hint has it: roomy, a box or a capsule, what waits in it, what went wrong)
  let shape_key = fn() {
    (roomy(), multiline(), w.files.get().length(), w.quotes.get().length(), w.error.get() != "")
  }
  let hint_shape = Ref(@signals.untracked(shape_key))
  let hint_roomy = Ref(@signals.untracked(roomy))
  // (the moment its shape last changed: its way there from then, whatever comes after it in its own changes)
  let reshaped_since = Ref(-1.0e9)
  // (kept a box a moment after the cursor left it: hidden then only where it holds nothing, to be let go to a capsule;
  // holding something (a quote, a file), it stays a box, at rest, the hint on it as the old one's, the cursor in a
  // quote's line or nowhere)
  foot.reacts(fn() { (hint_hidden(), shape_key()) }, fn(now) {
    let (hidden, shaped) = now
    let reshaped = shaped != hint_shape.val
    hint_shape.val = shaped
    // (the window resized across roomy: there at once, as what it is on is)
    if shaped.0 != hint_roomy.val {
      hint_roomy.val = shaped.0
      hint_in.put(if hidden { 0.0 } else { 1.0 })
      return
    }
    let at = foot.cause_at()
    if reshaped && foot.was_placed() && !fresh_fly.val {
      reshaped_since.val = at
    }
    // (flying in from the new chat it was: its hint's way back is that flight's)
    if fresh_fly.val {
      fresh_fly.val = false
      if !hidden && !reshaped {
        return
      }
    }
    if hidden || reshaped {
      hint_in.put(0.0)
    }
    if !hidden && !foot.allows_transition() {
      // (changed by no person's act (the window resized): there at once)
      hint_in.put(1.0)
    } else if !hidden {
      // (once its shape's way there is over, from when it set out (composer_shape_ms, composer_hint's `going`), and what
      // was sent from it is half way out of it (`away_until`))
      let delay = @sf.dmax(0.0, @sf.dmax(reshaped_since.val + composer_shape_ms - at, away_until.val - at))
      if delay > 0.0 {
        hint_in.go(foot, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out, delay~))
      } else {
        hint_in.go(foot, 1.0, @motion.tween(@sf.hint_back_ms, ease=Out))
      }
    }
  })
  // (the cursor gone: a box a moment more, then a capsule; back in it before then, still a box; gone to its notice's
  // choice's menu, a box while that is open, and let go so once it shuts, the cursor not back)
  // (and while a picture is open over the window or something is presented over it: let go once that is gone, nothing
  // of it going its way unseen behind)
  let held_behind = fn() {
    composing_node.choosing_cache.get(draft).unwrap_or(false) || @sfbase.viewer.get() is Some(_) || @sf.presenting()
  }
  let let_go = fn() {
    foot.at_moment(foot.cause_at() + let_go_ms, fn() {
      if !w.field.focused() && !w.field.parked() && !foot_at_rest.val && !@signals.untracked(held_behind) {
        // (the cursor let go a moment ago, a person's act: what it changes goes its way)
        @view.transition(fn() {
          // (let go to a capsule now, drawn from its box of one line: `morph`)
          if !@signals.untracked(held_in) {
            shape_way()
          }
          composing_node.held.set(draft, false)
        })
      }
    })
    |> ignore
  }
  foot.reacts(
    held_behind,
    fn(open) { if !open && @signals.untracked(held) && !w.field.focused() { let_go() } },
    at_start=false,
  )
  // (from what it comes to: as it is made unfocused, nothing to let go of, no wake asked)
  foot.reacts(
    focused,
    fn(now) {
      if now {
        if !@signals.untracked(held) {
          composing_node.held.set(draft, true)
        }
      } else if @signals.untracked(held) {
        let_go()
      }
    },
  )
}

///|
/// How many rows of a composer made as nodes each quote is given to now (by its draft's key and its id), till each is let go (its way out over):
/// one that comes in again while its old row still leaves is given a comment field of its own.
// kept across runs: emptied by composing_reset (pages_reset)
let comment_rows_live : Map[String, Int] = Map([])

///|
/// What is said over chat `r`'s composer made as nodes, a notice each, in their order (composer_notices_node's): it
/// archived, its agent's prompt cache over, its station down, a report of the person's answered.
fn composer_notice_kinds(src : Source, r : ChatRef, reports? : () -> Array[Json]) -> Array[String] {
  let reports = match reports {
    Some(f) => f
    None => fn() { feedback_reports(src, r) }
  }
  let h = @sfbase.chat_view_now(src, r)
  let ks : Array[String] = []
  if h.map(fn(h) { h.archived }).unwrap_or(false) {
    ks.push("archive")
  }
  if h.map(fn(h) { h.cache_cold is Some(_) && !h.archived }).unwrap_or(false) {
    ks.push("wait")
  }
  if h.map(fn(h) { h.offline }).unwrap_or(false) {
    ks.push("unplug")
  }
  // (the person's reports read once the chat's view is there: none read for a page still waiting on it)
  if h is Some(_) && reports().iter().any(fn(f) { !report_dismissed(f) }) {
    ks.push("said")
  }
  ks
}

///|
/// The room a chat's composer made as nodes takes opened with one line at the foot of a column `wide` (composer_open_room's,
/// a node's): its box (its padding, 8 over its field's one line, 10 to its row, its round buttons as far from its foot as
/// makes them concentric with its corner), 12 over it and its foot's room under it.
fn node_open_room(stand : Stand, wide : Double) -> Double {
  let t = @sf.theme()
  let corner = stand.place().corner
  @sf.composer_pad + (8.0 + node_field_line((stand.scale)())) + 10.0 + t.round.side + @ui.capsule_in(corner, t.round.side) +
  12.0 +
  composer_foot_at(wide)
}

///|
/// Whether chat `h`'s composer offers 抄送 (its agents' threads in Slack or Feishu: cc_chooser's).
fn cc_shown(h : ChatView?) -> Bool {
  match h {
    Some({ cc, thread: Some(_), .. }) => cc.length() > 0
    _ => false
  }
}

///|
/// The composer's field in `words` (composer_text's, a node's): the theme's words at the system's size, growing with
/// what is typed to text_lines', then scrolling; while empty what to write, or with keyboard and mouse and nothing
/// focused the key that brings the cursor back; typed, told to the core (its agent warmed once a minute); Enter sends
/// (⌘Enter where chosen), ⇧Enter a new line; with nothing typed ↑ / ↓ go to the chat above or below. What it says while
/// empty shows as far as `hint_in()` says.
fn composer_field_node(
  words : @view.View,
  src : Source,
  r : ChatRef,
  w : Writing,
  scale : () -> Double,
  hint_in : () -> Double,
  away : () -> Bool,
  spec : BoxSpec,
  submit : () -> Unit,
  focus_told : (Bool) -> Unit,
  regrow : (Double) -> Unit,
  placeholder? : () -> String,
  locked? : () -> Bool = fn() { false },
  no_files? : () -> Bool = fn() { false },
) -> Unit {
  let prefs = fn() { src.topic("prefs", {}).get().value }
  let by_command = fn() { @settings.sends_by_command(prefs()) }
  // (what it says while empty: with keyboard and mouse and nothing focused, the key that brings the cursor back
  // (never while it is locked, nor a new chat's while a menu or a panel is put up over it: the key is that one's then);
  // else what to write, a new chat's its own as its spec says it)
  let written = placeholder.unwrap_or(fn() { @sf.t("web-main.composer.placeholder") })
  // (nothing at all where it says nothing: a new chat's while it is away)
  let hint = fn() {
    let said = written()
    if spec.placeholder != "" {
      spec.placeholder
    } else if said != "" &&
      !locked() &&
      // (nothing of a key's while what is presented over it has the keys, or its field put by under it)
      !@sf.presenting() &&
      !w.field.parked() &&
      !@sf.soft_keyboard() &&
      !w.field.focused() &&
      !@ui.field_has_focus() {
      match @settings.key_label(prefs(), "composer.focus") {
        "" => said
        key => @sf.t("web-main.composer.pressToTypeCjk", args=[("key", key)])
      }
    } else {
      said
    }
  }
  let wl = @signals.untracked(fn() { @ui.style_words(@sf.theme().t.words) })
  // (how many lines it shows at most as the system's size of words and the window are now: followed, not as made)
  let live_max_lines = fn() { node_text_lines(scale(), words.window_h()) }
  let typed = @ui.field(
    words,
    w.field,
    placeholder_by=hint,
    font_size=wl.size,
    line=wl.line,
    trim=true,
    max_lines_by=live_max_lines,
    words=true,
    // (the core's bound, asked as it is made, followed as it answers; 0 while files are refused or starting: composer.mbt)
    paste_limit_by=fn() { if no_files() || w.starting.get() { 0 } else { @sfbase.paste_threshold_now(src) } },
    look=@sfbase.refs_look_by(w.key, fn() { @sf.theme().p.accent }),
    colors_by=fn() {
      let p = @sf.theme().p
      // (its caret away while what was sent from it leaves it: composer_box_node's `away`)
      (p.text, @sf.alpha(p.subtle, hint_in()), if away() { @sf.alpha(p.accent, 0.0) } else { p.accent })
    },
    edit=fn(e) { @sfbase.refs_edited(src, w.key, w.field, r.station, false, e) },
    edited=fn(now) {
      // (a line more or fewer: its height its way; the same lines, nothing said, so nothing coming in its column in
      // the same change is set off with it)
      let max_lines = @signals.untracked(live_max_lines)
      match field_comes_other(w.field, wl, max_lines, @signals.untracked(fn() { w.text.get() }), now) {
        Some(by) => regrow(by)
        None => ()
      }
      if now != @signals.untracked(fn() { w.text.get() }) && !@signals.untracked(fn() { w.starting.get() }) {
        writing_text(src, w, now)
        if spec.chat {
          composer_warm(src, r, words.cause_at())
        }
      }
    },
    submitted=fn(now) {
      if !@signals.untracked(fn() { w.starting.get() }) {
        if now != @signals.untracked(fn() { w.text.get() }) {
          writing_text(src, w, now)
        }
        submit()
      }
    },
    pasted=fn(now) {
      @sfbase.writing_paste(src, w, r.station, now)
    },
    files=fn(files) {
      if @signals.untracked(no_files) {
        let why = if @signals.untracked(locked) {
          @sf.t("web-main.composer.filesLocked")
        } else {
          @sf.t("web-main.composer.filesOffline")
        }
        toast_later(why)
      } else {
        for f in files {
          writing_add(src, w, r.station, f.0, f.1)
        }
      }
    },
  )
  // (as 快捷键's 发送 says now (prefs sendKey), followed: changed while it is made, the next Enter goes by it)
  @ui.field_sends_by(typed, fn() {
    let command = by_command()
    (@sf.enter_sends(command~), @sf.command_sends(command))
  })
  // (whether the cursor is in it, as it was last told: what it had as it is let go, the focus let go with it then
  // unsaid; read once the field is made, a focus asked of it taken as it is made, tree_field's)
  let had_focus = Ref(@signals.untracked(fn() { w.field.focused() }))
  @ui.field_focus_told(typed, fn(on) {
    // (what it had as it is let go of kept: its field gone tells it lost, not the person)
    if typed.alive() {
      had_focus.val = on
    }
    focus_told(on)
  })
  // (let go with the cursor in it (its page made anew: another node of the same draft's composer to come), the cursor
  // kept for the one that takes its place, as an old view's editor of the same draft keeps it)
  typed.owns(fn() {
    if had_focus.val {
      composing_node.focus_waits = w.key
    }
  })
  |> ignore
  // (the cursor given it as its page came, before it was made: taken now, as what the page is as it comes)
  if composing_node.focus_waits == w.key {
    composing_node.focus_waits = ""
    // (once what it is made in is held from the window's root, as the change that makes it is told)
    @signals.after_flush(fn() {
      if !w.field.focused() {
        composing_node.quiet = true
        w.field.focus()
        composing_node.quiet = false
      }
    })
  }
  typed.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
  // nothing typed in a chat's: ↑ ↓ the chat above or below, as the list shows them now, before the field sees it
  typed.on_key(fn(k) {
    // (its own keys alone: a key pressed on what stands over it in the tree (a notice's choice, 接着聊's ↓) is that one's)
    guard w.field.focused() && spec.chat && k.mods == 0 && (k.code == @ui.key_code_up || k.code == @ui.key_code_down) else {
      return false
    }
    guard w.text.get() == "" && !(@sfbase.neighbour_held.val)() else { return false }
    match @sfbase.workspace_in_view(src).0 {
      Some(ws) => (@sfbase.neighbour_go.val)(src, ws, if k.code == @ui.key_code_up { -1 } else { 1 })
      None => ()
    }
    true
  })
  |> ignore
}

///|
/// Whether field `field` (composer_field_node's: words `wl`, `max_lines` at most) comes out another height with `now` in
/// it than with `was`, as wide as its words were laid out last: a line more or fewer. Not laid out yet, so.
fn field_comes_other(field : @ui.Field, wl : @view.WordsLook, max_lines : Int, was : String, now : String) -> Double? {
  guard field.lines() is Some(lines) else { return Some(0.0) }
  let wide = lines.room.2 / (if lines.scale > 0.0 { lines.scale } else { 1.0 })
  let laid = field.laid(font_size=wl.size, line=wl.line, max_lines~, trim=true)
  let (_, h0) = { ..laid, words: was }.size(Some(wide))
  let (_, h1) = { ..laid, words: now }.size(Some(wide))
  if (h1 - h0).abs() > 0.01 {
    Some(h1 - h0)
  } else {
    None
  }
}

///|
/// Typing warms chat `r`'s agent's runtime, so a cold start overlaps the writing: the first time, then a minute after
/// the last (warm's, at moment `at`).
fn composer_warm(src : Source, r : ChatRef, at : Double) -> Unit {
  guard @sfbase.chat_view_now(src, r) is Some(h) && !h.archived && !h.offline && !src.read_only else { return }
  let (n, last) = composing_node.warmed.get(r.session).unwrap_or((0, @double.neg_infinity))
  if n > 0 && at - last < warm_every_ms {
    return
  }
  composing_node.warmed[r.session] = (n + 1, at)
  (src.call)("session.warm", { "station": Json::string(r.station), "key": Json::string(r.session) }, @sfbase.answer_unread)
}

///|
/// Send pressed (or Enter) in draft `w`'s composer of chat `r` (`head`, its view as it is): the line of a quote it takes
/// that had the focus gives it to the words' field first, as Enter in that line does and as its ✕ does (not lost with the
/// line as its card sets out); then, once the press is told, its own change of the press's moment (as the old composer's
/// send was made by its build: what it puts in the chat's list comes in it as one sent, its row made from the field's
/// words as they flew), composer_submit's (composer_state.mbt): `send` where it is ready (a chat's send_in_chat_node, a
/// new chat's its own), not while it is `locked`.
fn composer_node_submit(src : Source, w : Writing, station : String, locked : () -> Bool, send : (Writing) -> Unit) -> Unit {
  guard @signals.untracked(fn() { composer_ready(w, locked=locked()) }) else { return }
  let quote_had = @signals.untracked(fn() {
    w.quotes
    .get()
    .iter()
    .any(fn(q) { composing.comments.get(text(Some(q), "id")).map(fn(f) { f.focused() }).unwrap_or(false) })
  })
  if quote_had {
    w.field.focus()
  }
  @ui.after_frame(fn() {
    @signals.start_batch()
    composer_submit(src, w, station, locked=@signals.untracked(locked), send) |> ignore
    @signals.end_batch()
  })
}

///|
/// ＋ in `parent` (attach's, a node's): 32 round, the muted ink, the hover's ground and the text's ink under the
/// pointer, faint where no file is taken in; pressed, the system's file picker (on a touch system the sheet of what can
/// go in: attach.mbt); its tip with its keys (composer.file).
fn attach_node(
  parent : @view.View,
  src : Source,
  w : Writing,
  tips : @sf.TipLayer,
  no_files : () -> Bool,
  place? : (@view.View) -> Unit = fn(_) {  },
) -> Unit {
  @sf.action_box_node(
    parent,
    fn() { @sf.t("web-main.composer.attach") },
    fn(b) {
      if @sf.attach_from_sheet() {
        attach_open_node(b, src, w.key)
      } else {
        pick_files(w)
      }
    },
    disabled=no_files,
    fn(b) {
      let lit = fn() { !no_files() && @sf.lit_node(b) }
      let side = @sf.theme().round.side
      place(b)
      b
      .width(Is(Some(side)))
      .height(Is(Some(side)))
      .radius(Is(side / 2.0))
      .lines_up(Is(Some(Middle)))
      .lies_along(Is(Middle))
      |> ignore
      @sf.hover_ground_node(b, on=fn() { !no_files() })
      @sf.icon_node(
        b,
        "plus",
        plus_icon,
        By(fn() {
          let p = @sf.theme().p
          if no_files() {
            @sf.alpha(p.text, faint)
          } else if lit() {
            p.text
          } else {
            p.muted
          }
        }),
      )
      |> ignore
      @sf.tip_node(tips, b, fn() { if no_files() { "" } else { @sf.t("web-main.composer.attach") } }, shortcut="composer.file")
      |> ignore
    },
  )
  |> ignore
}

///|
/// 抄送 in `parent` (cc_chooser's, a node's): a chooser's look (12, quiet, the hover's ground while the hand is on it or
/// its menu is open), opening a menu over it of the threads to tick, each its mark and place, the ticked ones checked:
/// one closes once ticked, several stay open to tick in turn (each tick `chat.cc`).
fn cc_chooser_node(parent : @view.View, src : Source, r : ChatRef, head : () -> ChatView?, tips : @sf.TipLayer) -> Unit {
  ignore(tips)
  let to = fn() {
    match head() {
      Some({ cc, thread: Some(th), .. }) => (cc, th)
      _ => ([], 0.0)
    }
  }
  let open = @signals.signal(false, same=fn(a, b) { a == b })
  let set_open = fn(v : Bool) {
    composing.cc_open = v
    open.set(v)
  }
  let label = fn() { @sf.t("web-main.composer.ccLabel") }
  let b = @sf.action_box_node(
    parent,
    fn() { ([label()] + to().0.filter(fn(o) { o.on }).map(fn(o) { o.place })).join(" ") },
    fn(_) { set_open(!open.untracked()) },
    expanded=fn() { open.get() },
    fn(v) {
      let lit = fn() { @sf.lit_node(v) || open.get() }
      v
      .row(Is(true))
      .height(Is(Some(@ui.Space::px(S7))))
      .padding(Is((@ui.Space::px(S2), 0.0, @ui.Space::px(S2), 0.0)))
      .gap(Is(@ui.Space::px(S1_5)))
      .radius(By(fn() { @ui.tree_theme().corner(Lg) }))
      .lines_up(Is(Some(Middle)))
      .ground(By(fn() { if lit() { @ui.tree_theme().color(Hover) } else { 0L } }))
      |> ignore
      @sf.words_node(v, label, fn() { if lit() { cc_words_lit } else { cc_words } }) |> ignore
      @sf.icon_node(v, "chevron-down", 12.0, By(fn() { if lit() { @sf.theme().p.text } else { @sf.theme().p.muted } }))
      |> ignore
      v.on_leaving(fn() { set_open(false) }) |> ignore
    },
  )
  // (its menu made over the window, living as long as 抄送 does: not in the composer, which cuts what it holds)
  let holder = parent.tree.root().box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(b)
  @sf.menu_ticks_node(
    holder,
    fn() { open.get() },
    fn(_) { b },
    fn() {
      let (cc, th) = to()
      cc.map(fn(o) {
        Some(
          @sf.menu_item_of(o.place, chosen=o.on, fn() {
            (src.call)(
              "chat.cc",
              {
                "station": Json::string(r.station),
                "thread": Json::number(th),
                "to": Json::number(o.thread),
                "on": Json::boolean(!o.on),
              },
              @sfbase.answer_unread,
            )
          }),
        )
      })
    },
    "",
    End,
    6.0,
    false,
    false,
    fn(item) {
      (item.select)()
      // (one: done once ticked; several: left open to tick the next)
      if to().0.length() <= 1 {
        set_open(false)
      }
    },
    fn() { set_open(false) },
    side=Top,
    min_w=@sf.chooser_menu_w,
    // (each ticked one's check at its row's end, none before its mark: the old one's, 左子健's)
    check_end=true,
    extras=fn(i) {
      match to().0.get(i) {
        Some(o) => { note: "", value: "", mark: Some(Drawn(if o.via == "feishu" { "feishu" } else { "slack" })), end: None }
        None => { note: "", value: "", mark: None, end: None }
      }
    },
  )
}

///|
/// The mark of the platform what is sent is copied to (cc_mark's, a node's): Feishu's for Feishu, else Slack's, 14.
fn cc_mark_node(parent : @view.View, via : String) -> Unit {
  @sf.origin_mark_node(parent, fn() { via }, 14.0) |> ignore
}

///|
/// What waits to go with the message in `box` (composer_extras', as nodes): the quotes, each with a line for what is
/// said about it (the one the core asks the focus for takes it; Enter in it goes back to the words), then the files: a
/// picture as its tile, pasted words, a station's file, a link or any other file as its card; each with its ✕ hung on
/// its corner. Made while there is any, coming in and going down the composer's column as what comes does.
fn composer_extras_node(
  box : @view.View,
  src : Source,
  r : ChatRef,
  w : Writing,
  tips : @sf.TipLayer,
  stand : Stand,
  alive : @signals.Signal[Bool],
  extras_mounted : @signals.Signal[Bool],
  foot_at_rest : Ref[Bool],
  sent_at : Ref[Double],
  reshaped_at : Ref[Double],
  is_user_move : (@view.View) -> Bool,
  grow : @motion.NodeWay,
  morph_dy : (@view.View) -> Double,
  pad_room : Ref[@view.View?],
  quotes_room : Ref[@view.View?],
  files_room : Ref[@view.View?],
) -> Unit {
  let inner = fn() { stand.at(fn() { @sf.composer_inner() }) }
  let live_count = Ref(0)
  let track_live = fn(v : @view.View) {
    live_count.val = live_count.val + 1
    alive.set(true)
    v.owns(fn() {
      live_count.val = live_count.val - 1
      if live_count.val <= 0 {
        live_count.val = 0
        @view.transition(fn() { alive.set(false) })
      }
    })
    |> ignore
  }
  let leave_ease = fn(x : Double) -> Double {
    if x <= 0.0 {
      0.0
    } else if x >= 1.0 {
      1.0
    } else {
      1.0 - (1.0 - x) * (1.0 - x)
    }
  }
  let attach_motion = fn(
    room : @view.View,
    item : @view.View,
    fill_across : Bool,
    force_anim : Bool,
    build : (@view.View) -> Unit,
  ) {
    let animates = item.allows_transition() || (force_anim && !@ui.reduced_motion())
    let enter : (() -> Double)? = if animates {
      Some(@motion.presence_in(item, @sf.waiting_in.spec, carries=true))
    } else {
      None
    }
    let from_room : @signals.Signal[Bool?] = @signals.signal(if animates { None } else { Some(false) })
    if animates {
      @signals.after_flush(fn() {
        guard item.alive() && room.alive() else { return }
        let s = @signals.untracked(fn() { room.come_share_of(item) })
        from_room.set(Some(s < 0.999))
      })
    }
    item.box(fn(wrap) {
      if fill_across {
        wrap.fills_across(Is(true)) |> ignore
      }
      wrap
      .takes_unseen(By(fn() { !item.leaving() }))
      .scale(
        By(fn() {
          let s = room.come_share_of(item)
          if item.leaving() {
            if s < 0.999 {
              s
            } else {
              1.0 - 0.1 * leave_ease(item.going())
            }
          } else {
            match from_room.get() {
              Some(true) => s
              Some(false) =>
                match enter {
                  Some(e) => 0.92 + 0.08 * e()
                  None => 1.0
                }
              None => s
            }
          }
        }),
        about=At(0.0, 0.0),
      )
      .alpha(
        By(fn() {
          let s = room.come_share_of(item)
          if item.leaving() {
            if s < 0.999 {
              @sf.seen_at(s)
            } else {
              1.0
            }
          } else {
            match from_room.get() {
              Some(true) => @ui.Ease::Out.at(@sf.seen_at(s))
              Some(false) =>
                match enter {
                  Some(e) => e()
                  None => 1.0
                }
              None => 0.0
            }
          }
        }),
      )
      |> ignore
      build(wrap)
    })
    |> ignore
  }
  // (lazily mounted on first attachment so an empty composer adds zero nodes/spaces on cold open, then stays mounted
  // so 1->0 collapse finishes smoothly without unloading early at leave_ms)
  box.show(at_once=true, fn() {
    let any = w.quotes.get().length() > 0 || w.files.get().length() > 0
    any || extras_mounted.get()
  }, fn(area) {
    let user_change = is_user_move(box)
    let first_animate = box.was_placed() &&
      user_change &&
      !composing_node.quiet &&
      !foot_at_rest.val &&
      !@view.answering_now() &&
      box.cause_at() != sent_at.val &&
      box.cause_at() != reshaped_at.val
    let q_any = if first_animate { @signals.untracked(fn() { w.quotes.get().length() > 0 }) } else { false }
    let f_any = if first_animate { @signals.untracked(fn() { w.files.get().length() > 0 }) } else { false }
    let mounting = Ref(true)
    let build_area = fn() {
    // (drawn with its words as a line more of them makes its way in (`grow`) and with the morphing glass top (`morph_dy`))
    area.offset(By(fn() { (0.0, grow.shown(area) + morph_dy(area)) })) |> ignore
    area
    .padding(
      By(fn() {
        let d = stand.at(fn() { @sf.composer_waiting_in() })
        (d, 0.0, d, 0.0)
      }),
    )
    |> ignore
    // (top inset room: carries composer_waiting_in() so qs/fs first rows stay at rel_y=0 and stacking quotes never shifts files)
    area.box(fn(pr) {
      pad_room.val = Some(pr)
      pr.owns(fn() {
        match pad_room.val {
          Some(v) if v.id() == pr.id() => pad_room.val = None
          _ => ()
        }
      })
      |> ignore
      pr
      .shrink(Is(0.0))
      .height(
        By(fn() {
          if w.quotes.get().length() > 0 || w.files.get().length() > 0 {
            Some(stand.at(fn() { @sf.composer_waiting_in() }))
          } else {
            Some(0.0)
          }
        }),
      )
      |> ignore
      if q_any || f_any {
        pr.resizes(uncut=true) |> ignore
      }
    })
    |> ignore
    // (its quotes, then its files: each nothing while it holds none, so what goes closes with its room's own way)
    area.box(fn(qs_room) {
      quotes_room.val = Some(qs_room)
      qs_room.owns(fn() {
        match quotes_room.val {
          Some(v) if v.id() == qs_room.id() => quotes_room.val = None
          _ => ()
        }
      })
      |> ignore
      if q_any {
        qs_room.resizes(uncut=true) |> ignore
      }
      let q_moves : Ref[@motion.Moves?] = Ref(None)
      let q_first : Array[@view.View] = []
      qs_room.box(fn(qs) {
        // (each 10 over what follows it, within it; padding collapses to 0 when empty so no gone_empty out-flag blocks focus)
        qs
        .gap(Is(@ui.Space::px(S1_5)))
        .padding(
          By(fn() {
            if w.quotes.get().length() > 0 {
              (0.0, 0.0, 0.0, @ui.Space::px(S2_5))
            } else {
              (0.0, 0.0, 0.0, 0.0)
            }
          }),
        )
        |> ignore
        qs.each(leave=@sf.leave_ms, pop_leave=true, fn() { w.quotes.get() }, fn(q) { text(Some(q), "id") }, fn(row, q) {
          track_live(row)
          match q_moves.val {
            Some(m) => m.moves_with(row)
            None => q_first.push(row)
          }
          let id = text(Some(@signals.untracked(fn() { q.get() })), "id")
          let v = fn() { Some(q.get()) }
          // (its comment's field, kept by the quote's id; a new one where the one kept is still another row's, that row
          // still leaving as this one comes in (the same quote put in again within its way out): a field is one editor's)
          let live_key = w.key + "\u{1}" + id
          let live = comment_rows_live.get(live_key).unwrap_or(0)
          let f = match composing.comments.get(id) {
            Some(f) if live == 0 => f
            _ => {
              let f = @ui.Field::new(text=text(@signals.untracked(v), "comment"))
              composing.comments[id] = f
              f
            }
          }
          comment_rows_live[live_key] = live + 1
          row.owns(fn() {
            match comment_rows_live.get(live_key) {
              Some(n) if n > 1 => comment_rows_live[live_key] = n - 1
              _ => comment_rows_live.remove(live_key)
            }
          })
          |> ignore
          let card_key = w.key + "\u{1}" + id
          attach_motion(qs_room, row, true, mounting.val && q_any, fn(wrap) {
            @sf.composer_quote_card_node(
              wrap,
              tips,
              fn() { text(v(), "author") },
              fn() { text(v(), "text") },
              fn() { text(v(), "role") },
              fn(line) {
                @ui.field(
                  line,
                  f,
                  placeholder=@sf.t("web-main.quote.commentPlaceholder"),
                  font_size=@signals.untracked(fn() { @sf.theme().t.ui }),
                  line=@signals.untracked(fn() { @sf.theme().t.ui_line }),
                  max_lines=1,
                  enter_sends=true,
                  colors_by=fn() {
                    let p = @sf.theme().p
                    (p.text, p.subtle, p.accent)
                  },
                  edited=fn(now) { writing_comment(src, w, id, now) },
                  // (Enter in it: back to the words)
                  submitted=fn(_) { w.field.focus() },
                )
                .grow(Is(1.0))
                |> ignore
              },
              fn() {
                if f.focused() {
                  w.field.focus()
                }
                writing_unquote(src, w, id)
              },
              fn() { @sf.t("web-main.quote.remove") },
              pictured=fn() { quote_picture_now(src, w, r.station, v()) is Some(_) },
              picture=fn(b) {
                // (its picture flies on its own as it is sent, from its square to its place in the message's card: none of
                // it in the card flown from here, View::flies_apart)
                b.flies_apart() |> ignore
                // (a message's video on the station: its still, as a message's file shows it: video_still_node)
                let still = quote_still_node(b, src, r.station, v)
                let tile = waiting_tile_of(
                  b,
                  fn() {
                    match quote_picture_now(src, w, r.station, v()).map(fn(p) { p.0 }) {
                      Some("") => still()
                      Some(k) => k
                      None => ""
                    }
                  },
                  fn() { quote_picture_now(src, w, r.station, v()).map(fn(p) { p.1 }).unwrap_or(false) },
                  fn() { going_now(field(v(), "own")) },
                  fn() { gone_up(field(v(), "own")) },
                  fn() { text(field(v(), "own"), "error") != "" },
                  fn() { writing_retry(src, w, text(field(v(), "own"), "id")) },
                )
                // (its square, for what is sent to fly from: composer_sent_parts)
                composer_sent_parts_kept(w.key + "\u{1}" + id + "\u{1}picture", tile)
              },
              // (the card and its ✕ as one, what a message sent from here takes it to its own card as: its card flies from it
              // as one box, its words and its ✕ seen going as the message's come, mbui's View::shared `container`)
              whole=fn(h) {
                let made = @signals.untracked(fn() { draft_sent_into(w.key) })
                h.shared(By(fn() { composer_quote_shared(w.key, card_key, made) }), sent_part_flight, container=true) |> ignore
              },
            )
            |> ignore
          })
          // (the one the core says asks for the focus: given it, told; none where it says none, a quote of its own with no id
          // among them)
          // (given once what it is made in is held from the window's root, and once a menu or a sheet its quote was asked
          // from is closing: in a change of that moment after the one that closed it, once the layer it was has let the
          // keys go (Tree::takes_keys) and given back the focus it held, the focus given to it after that)
          row.reacts(fn() { w.focus.get() != "" && w.focus.get() == id && !@sf.presenting() }, fn(asks) {
            if asks {
              row.at_moment(row.cause_at(), fn() {
                if @signals.untracked(fn() { w.focus.get() }) == id {
                  f.focus()
                  writing_focused(src, w)
                }
              })
              |> ignore
            }
          })
        })
      })
      |> ignore
      let qm = @motion.moves_for(qs_room, fn() { w.quotes.get().map(fn(q) { text(Some(q), "id") }) })
      for p in q_first {
        qm.moves_with(p)
      }
      q_first.clear()
      q_moves.val = Some(qm)
    })
    |> ignore
    area.box(fn(fs_room) {
      files_room.val = Some(fs_room)
      fs_room.owns(fn() {
        match files_room.val {
          Some(v) if v.id() == fs_room.id() => files_room.val = None
          _ => ()
        }
      })
      |> ignore
      if f_any {
        fs_room.resizes(uncut=true) |> ignore
      }
      let f_moves : Ref[@motion.Moves?] = Ref(None)
      let f_first : Array[@view.View] = []
      fs_room.box(fn(fs) {
        fs
        .row(Is(true))
        .gap(Is(@ui.Space::px(S1_5)))
        .wraps(By(fn() { Some(@ui.Space::px(S1_5) + @sf.corner_remove_reach(inner())) }))
        .padding(
          By(fn() {
            if w.files.get().length() > 0 {
              let end = stand.at(fn() { @sf.composer_files_end() - @sf.composer_waiting_in() })
              (0.0, 0.0, end, @ui.Space::px(S2_5))
            } else {
              (0.0, 0.0, 0.0, 0.0)
            }
          }),
        )
        |> ignore
        fs.each(leave=@sf.leave_ms, pop_leave=true, fn() { w.files.get() }, fn(f) { text(Some(f), "id") }, fn(item, f) {
          track_live(item)
          match f_moves.val {
            Some(m) => m.moves_with(item)
            None => f_first.push(item)
          }
          attach_motion(fs_room, item, false, mounting.val && f_any, fn(wrap) {
            composer_file_node(wrap, src, r, w, tips, fn() { Some(f.get()) }, inner, stand)
          })
        })
      })
      |> ignore
      let fm = @motion.moves_for(fs_room, fn() { w.files.get().map(fn(f) { text(Some(f), "id") }) })
      for p in f_first {
        fm.moves_with(p)
      }
      f_first.clear()
      f_moves.val = Some(fm)
    })
    |> ignore
    mounting.val = false
    if q_any || f_any {
      reshaped_at.val = box.cause_at()
    }
    }
    if q_any || f_any {
      @view.transition(within=box.transitions_root(), build_area)
    } else {
      build_area()
    }
  })
}

///|
/// A picture or a video's still waiting in the composer in `parent` (the library's waiting_tile_node): picture `key()`
/// covering it (a video's still on the words' ink; none yet, the neutral ground), decoded for as many of the device's
/// pixels as it is drawn at; going up, failed and a video's mark as the library's tile draws them. The tile's node.
fn waiting_tile_of(
  parent : @view.View,
  key : () -> String,
  video : () -> Bool,
  going : () -> Bool,
  part : () -> Double?,
  failed : () -> Bool,
  again : () -> Unit,
) -> @view.View {
  @sf.waiting_tile_node(
    parent,
    fn(p) {
      // (a video's black as a message's video draws it, in either theme; a picture's neutral ground. No picture yet: that
      // ground alone. Once there is one, the ground is its matte, composited into it before the tile's rounded clip cuts
      // their edge once: the ground drawn apart under it showed through that edge as a rim round a light still)
      p
      .sets_together(
        fn() {
          (
            key(),
            @ui.tree_theme().color(if video() { @sf.video_ground } else { Neutral }),
            (@sf.waiting_tile_side * p.pixel_scale()).ceil().to_int(),
          )
        },
        fn(state) {
          let (k, ground, px) = state
          match k {
            "" | "!" => p.ground(Is(ground)).image(Is(None)).image_in(Is(None)) |> ignore
            _ =>
              p
              .ground(Is(0L))
              .image(Is(Some((k, "", px))))
              .image_in(Is(Some(((0.0, 0.0, @sf.waiting_tile_side, @sf.waiting_tile_side), ground))))
              |> ignore
          }
        },
      )
      .image_for(Is((@sf.waiting_tile_side, @sf.waiting_tile_side)))
      .image_covers(Is(true))
      |> ignore
    },
    going,
    part,
    failed,
    again,
    fn() { @sf.t("web-main.composer.retryUpload") },
    video~,
  )
}

///|
/// A quote's own picture as the composer shows it now (quote_picture's, a node's): its key and whether it is a video's
/// still; the device's own while it holds it (a mark's screenshot), else the station's image of a message quoted. Read
/// by a node: told as any of them comes.
fn quote_picture_now(src : Source, w : Writing, station : String, q : Json?) -> (String, Bool)? {
  let own = field(q, "own")
  let kind = file_kind(text(own, "name"))
  guard own is Some(_) && (kind == "image" || kind == "video") else { return None }
  match @sfbase.writing_picture_told(text(own, "id")) {
    Some(picture) => Some((picture, kind == "video"))
    None => {
      match field(own, "done") {
        Some(j) => {
          let a = attachment_of(j)
          let owner = text(Some(j), "owner")
          match @sfbase.sent_picture_told(station, a) {
            Some(k) => return Some((k, kind == "video"))
            None => ()
          }
          if owner != "" && kind == "image" {
            return Some((src.file_told(station, owner, stored_name(a.path)), false))
          }
          // (a message's video on the station: its first frame, made where its tile is: quote_still_node)
          if owner != "" && kind == "video" {
            return Some(("", true))
          }
        }
        None => ()
      }
      waiting_picture_told(src, w, own).map(fn(p) { (p, kind == "video") })
    }
  }
}

///|
/// The first frame of quote `q`'s own video where it is a message's on the station (its `done` with its session
/// `owner`), for its tile in node `b` (video_still_node: as a message's file shows it), "" while it is not made or
/// where it is none such. Followed as the quote comes to be one (its own video gone up while it is quoted): made again
/// for the message it names.
fn quote_still_node(b : @view.View, src : Source, station : String, q : () -> Json?) -> () -> String {
  let still : @signals.Signal[String] = @signals.signal("")
  let named = fn() -> (String, String)? {
    let own = field(q(), "own")
    let done = field(own, "done")
    let owner = text(done, "owner")
    if done is Some(_) && owner != "" && file_kind(text(own, "name")) == "video" {
      Some((owner, text(done, "path")))
    } else {
      None
    }
  }
  b.pick(at_once=true, named, fn(p, which) {
    p.over(Is(true)).presses(Is(false)) |> ignore
    match (which, field(field(@signals.untracked(q), "own"), "done")) {
      (Some((owner, _)), Some(j)) => {
        let a = attachment_of(j)
        let made = @sfbase.video_still_node(p, src, station, owner, a, station + "/" + owner + "/" + a.path)
        p.reacts(made, fn(k) { still.set(k) })
      }
      _ => p.reacts(fn() { "" }, fn(k) { still.set(k) })
    }
  })
  fn() { still.get() }
}

///|
/// One file waiting in `item` (composer_file's, a node's): its picture's tile, or its card; its ✕ hung on its corner.
fn composer_file_node(
  item : @view.View,
  src : Source,
  r : ChatRef,
  w : Writing,
  tips : @sf.TipLayer,
  v : () -> Json?,
  inner : () -> Double,
  stand : Stand,
) -> Unit {
  let id = text(@signals.untracked(v), "id")
  let name = fn() { text(v(), "name") }
  let remove = fn() { writing_remove(src, w, id) }
  // (its picture as it is told while the draft holds it; taken out, the one it showed then: a tile leaving fades as
  // it stood, whatever its picture does as it goes, pop_leave.mbt)
  let shown : Ref[String?] = Ref(None)
  let held_now = fn() { w.files.get().iter().any(fn(f) { text(Some(f), "id") == id }) }
  let picture_told = fn() {
    let held = held_now()
    if held {
      shown.val = waiting_picture_told(src, w, v())
    }
    shown.val
  }
  item.pick(fn() { picture_told() is Some(_) }, at_once=true, fn(p, pictured) {
    if pictured {
      @sf.with_corner_remove_node(
        p,
        fn() { @sf.t("web-main.file.remove", args=[("name", name())]) },
        @signals.untracked(inner),
        fn(at) {
          // (a video's that the host has no picture of: its first frame, made from its bytes)
          let still = @sfbase.writing_still_node(at, id)
          // (what its tile shows, what flies from it and what the viewer opens on: the picture picked, else the still
          // drawn here of a video's bytes)
          let picture = fn() {
            match picture_told() {
              Some("") => still()
              Some(k) => k
              None => ""
            }
          }
          let tile = waiting_tile_of(
            at,
            picture,
            fn() { file_kind(name()) == "video" },
            fn() { going_now(v()) },
            fn() { gone_up(v()) },
            fn() { text(v(), "error") != "" },
            fn() { writing_retry(src, w, id) },
          )
          @sf.tip_node(tips, tile, fn() { if text(v(), "error") != "" { text(v(), "error") } else { name() } }) |> ignore
          composer_sent_parts_kept(w.key + "\u{1}" + id, tile)
          // (the end of the preview's flight that stays, by the viewer's id of what it opens: drawn nowhere while the
          // viewer shows it, its picture flown from here and back here, View::shared's `stays`, as a message's
          // thumbnail is (message_media_node))
          tile
          .image_covers(Is(true))
          .shared(
            By(fn() {
              // (one the viewer cannot open yet, a video whose first frame is still being made: the id it will open by
              // once it can, from here, drafted)
              match waiting_seen(waiting_preview(r.station, id, name(), picture(), v())) {
                "" => r.station + "//draft:" + id
                seen => seen
              }
            }),
            @motion.flight_by(@motion.moved()),
            stays=true,
          )
          |> ignore
          // tapped, it opens in the viewer (preview_composer_picture's): a press on what holds it and its ✕, so the ✕
          // over its corner is pressed within it, not beside it
          at.on_press(fn() { preview_waiting(r.station, id, name(), @signals.untracked(picture), v()) })
          |> ignore
        },
        remove,
      )
      |> ignore
    } else {
      @sf.with_corner_remove_node(
        p,
        fn() { remove_label(v(), name()) },
        @signals.untracked(inner),
        fn(at) {
          // (as wide as a file's card, or the composer where it is narrower)
          at.width(By(fn() { Some(@sf.dmin(@sf.file_card_w, stand.at(stand.composer_w))) })) |> ignore
          let card : Ref[@view.View?] = Ref(None)
          let as_ = fn() { waiting_as(v()) }
          let ref_ = fn() { field(v(), "ref") }
          let error = fn() { text(v(), "error") }
          card.val = Some(
            @sf.file_waiting_node(
              at,
              tips,
              fn() {
                if as_() is Link {
                  text(field(v(), "link"), "url")
                } else if as_() is AnyFile && field(ref_(), "dir") is Some(True) {
                  name() + ".zip"
                } else {
                  name()
                }
              },
              fn() {
                match as_() {
                  Link =>
                    match text(field(v(), "link"), "title") {
                      "" => text(field(v(), "link"), "url")
                      t => t
                    }
                  Pasted =>
                    match text(field(v(), "pasted"), "preview") {
                      "" => @sf.t("web-main.composer.pastedText")
                      first => first
                    }
                  _ => ""
                }
              },
              fn() { waiting_meta(v()) },
              inner,
              fn(on) {
                match (as_(), on) {
                  (Link, Opened) => open_link(text(field(v(), "link"), "url"))
                  (Pasted, Back) => {
                    let back = text(field(v(), "pasted"), "text")
                    let now = w.text.get()
                    let words = if now == "" { back } else { now + "\n" + back }
                    @sfbase.refs_put(w.key, w.field, words)
                    writing_text(src, w, words)
                    remove()
                    w.field.focus()
                  }
                  (Pasted, Again) => @sfbase.writing_paste_again(src, w, id)
                  (ByPath | AnyFile, Opened) =>
                    match (field(v(), "ref"), card.val) {
                      (Some(Object(_)), Some(c)) =>
                        @sf.panel_nodes(name(), fn(pv, close) { ref_panel_body(pv, close, src, w.key, r.station, id) }, from=Node(c))
                      _ => ()
                    }
                  (ByPath | AnyFile, Again) => writing_retry(src, w, id)
                  _ => ()
                }
              },
              tip=fn() {
                match as_() {
                  ByPath => text(ref_(), "path")
                  Link => text(field(v(), "link"), "url")
                  Pasted => waiting_meta(v())
                  AnyFile => name()
                }
              },
              dir=fn() { field(ref_(), "dir") is Some(True) },
              named=fn() { as_() is ByPath },
              fails=fn() { error() != "" },
              spins=fn() { going_now(v()) && field(v(), "sent") is None && as_() is (AnyFile | Pasted) },
              retry=fn() { error() != "" && (as_() is AnyFile || as_() is Pasted) },
              restore=fn() { as_() is Pasted && restorable(w, v()) },
              opens=fn() { as_() is (ByPath | Link) || (as_() is AnyFile && ref_() is Some(Object(_))) },
            ),
          )
          match card.val {
            Some(c) => composer_sent_parts_kept(w.key + "\u{1}" + id, c)
            None => ()
          }
        },
        remove,
      )
      |> ignore
    }
  })
}

///|
/// What a file waiting's card says under its name (file_card's `meta` as waiting_card asks it): why it failed; going up,
/// how far; a station's file named by its path, its station and that it goes so; a link, its site; pasted words, how
/// many characters; else its size.
fn waiting_meta(v : Json?) -> String {
  let error = text(v, "error")
  if error != "" {
    return error
  }
  match waiting_as(v) {
    ByPath => text(field(v, "ref"), "stationName") + " · " + @sf.t("web-main.file.modePath")
    Link => text(field(v, "link"), "site")
    Pasted =>
      if going_now(v) {
        waiting_going(v)
      } else {
        @sf.t("web-main.composer.pasteAttachment", args=[("count", @sf.grouped(number(field(v, "pasted"), "characters")))])
      }
    AnyFile =>
      if going_now(v) {
        waiting_going(v)
      } else {
        let done = field(v, "done")
        @sf.file_size(number(done, "size") + (if done is None { number(v, "size") } else { 0.0 }))
      }
  }
}

///|
/// How far a file waiting has gone up (file_card's `pending`): every byte gone, its station not yet saying it has them,
/// not 100%.
fn waiting_going(v : Json?) -> String {
  let size = number(v, "size")
  match field(v, "sent") {
    Some(Number(s, ..)) if size > 0.0 && s >= size => @sf.t("common.uploadConfirming")
    Some(Number(s, ..)) if size > 0.0 =>
      @sf.t("web-main.file.uploadingPart", args=[("percent", (s / size * 100.0).floor().to_int().to_string()), ("size", @sf.file_size(size))])
    _ => @sf.t("common.uploading")
  }
}

///|
/// What a picture waiting opens in the viewer as it is tapped (preview_composer_picture's): its station, its session
/// (none: it is in the draft) and the file, with the bytes picked or kept where it has them (`draft:<id>`), else a
/// quoted message's file on the station (`done` with its session `owner`), else the picture its tile shows; none where
/// it has nothing to show.
fn waiting_preview(
  station : String,
  id : String,
  name : String,
  picture : String,
  v : Json?,
) -> (String, String, Attachment, Bytes?)? {
  let done = field(v, "done")
  let width = if number(done, "width") > 0.0 { number(done, "width") } else { number(v, "width") }
  let height = if number(done, "height") > 0.0 { number(done, "height") } else { number(v, "height") }
  let drafted = fn(size : Double) -> Attachment {
    {
      name,
      path: "draft:" + id,
      size,
      width,
      height,
      thumbhash: "",
      owner: "",
      upload: "",
      duration: 0.0,
      frames: 0,
      held: false,
    }
  }
  match @sfbase.writing_went_to(id) {
    Some((went_station, _, bytes)) => {
      let s = if station != "" { station } else { went_station }
      Some((s, "", drafted(bytes.length().to_double()), Some(bytes)))
    }
    None =>
      match done {
        Some(j) if text(done, "owner") != "" => Some((station, text(done, "owner"), attachment_of(j), None))
        _ if picture != "" && picture != "!" => {
          let size = if number(done, "size") > 0.0 { number(done, "size") } else { number(v, "size") }
          Some((station, "", drafted(size), None))
        }
        _ => None
      }
  }
}

///|
/// The viewer's id of what `preview` opens (its station, its session if any, its path: preview_composer_picture's
/// `seen`), its tile's as the viewer flies from it and back into it; "" none.
fn waiting_seen(preview : (String, String, Attachment, Bytes?)?) -> String {
  match preview {
    Some((s, owner, a, _)) => s + "/" + owner + "/" + a.path
    None => ""
  }
}

///|
/// A picture waiting tapped (preview_composer_picture's): it opens in the viewer (waiting_preview's), growing out of
/// its tile, the bytes it has kept for the viewer to read by its id.
fn preview_waiting(station : String, id : String, name : String, picture : String, v : Json?) -> Unit {
  let preview = waiting_preview(station, id, name, picture, v)
  match preview {
    Some((s, owner, a, bytes)) => {
      match bytes {
        Some(b) => @sfbase.keep_read(waiting_seen(preview), b)
        None => ()
      }
      // (a draft's picture, kept for the viewer to stand in with as it opens (Viewer::stand_in, still): one restored
      // with no bytes here, a video's still drawn here)
      if a.path.has_prefix("draft:") && picture != "" && picture != "!" {
        @sfbase.sent_picture_kept(@sfbase.sent_key(s, a.path), picture)
      }
      @sfbase.open_preview(s, owner, a)
    }
    None => ()
  }
}

///|
/// What is said over a chat's composer in `foot` (chat_notices', as nodes), each a capsule of its own over it as the
/// composer is, coming in and going down its column as what comes does: an archived chat's, with 还原对话 (why it
/// failed under it; not while its station is down); its agent's prompt cache over, with the choice of how it goes on;
/// its station down; the still.fail team's reply on a bug report sent from it.
fn composer_notices_node(
  foot : @view.View,
  src : Source,
  r : ChatRef,
  tips : @sf.TipLayer,
  stand : Stand,
  drawn_off : (@view.View) -> Double,
) -> Unit {
  let key = r.station + ":" + r.session
  let head = fn() { @sfbase.chat_view_now(src, r) }
  let width = fn() { stand.at(stand.composer_w) }
  // (each a notice of its own, in their order: one comes in and goes down the column as what comes does)
  // (the team's replies as the core says them, what they last were while asked again: sfbase's asked_again.mbt)
  let reports_held = @sfbase.topic_value_held(src, "chatFeedback", @sfbase.chat_params(r))
  // (asked once the chat itself has answered: none of its replies read before its head is)
  let reports = fn() { if head() is Some(_) { items(reports_held.get(), "reports") } else { [] } }
  let report = fn() { reports().iter().find_first(fn(f) { !report_dismissed(f) }) }
  // (a notice arriving or leaving while the chat is already open and visible — cache expired, station offline/back,
  // archived, team reply — is a live cause of its own under the chat page's transitions_only: its column and the list's
  // foot ease smoothly instead of snapping the messages; opening or waking from rest stays at once)
  let judged : Ref[Array[String]?] = Ref(None)
  let had_head = Ref(@signals.untracked(head) is Some(_))
  let woke_at = Ref(-1.0)
  foot.on_rest(fn() {  }, wake=fn() {
    woke_at.val = foot.cause_at()
    judged.val = None
  })
  |> ignore
  let kinds = fn() {
    let ks = composer_notice_kinds(src, r, reports~)
    let has_head = @signals.untracked(head) is Some(_)
    let was_head = had_head.val
    had_head.val = has_head
    match judged.val {
      Some(was) if was != ks &&
        was_head &&
        has_head &&
        foot.was_placed() &&
        !@view.answering_now() &&
        @signals.untracked(@ui.app_visible) &&
        foot.cause_at() != woke_at.val =>
        @view.transition(within=foot.transitions_root(), fn() {  })
      _ => ()
    }
    judged.val = Some(ks)
    ks
  }
  // (the ＋'s middle as the composer draws it, from its start: its round control's, a point wider for the capsule's edge
  // line, its capsule_pad_alone in; where each notice's mark stands)
  let plus_mid = fn() { capsule_pad_alone + node_capsule_extra((stand.scale)()) + (@sf.theme().round.side + 1.0) / 2.0 }
  foot.each(kinds, fn(k) { k }, fn(n, kind) {
    // (as wide as the composer, the library's notice drawn in from its ends)
    n.width(By(fn() { Some(width()) })) |> ignore
    match @signals.untracked(fn() { kind.get() }) {
      // (archived: sending restores it; 还原对话 restores it now)
      "archive" => {
        let busy = fn() { composing.restoring.get(key).unwrap_or(false) }
        let off = fn() { busy() || head().map(fn(h) { h.offline }).unwrap_or(false) || src.read_only }
        // (drawn with the composer's ground's top as its shape goes, as far over it all the way: where its foot's
        // room goes its way on the page's too; the notice's own box, its row a slot of the column)
        let made = @sf.composer_notice_node(
          n,
          tips,
          fn() { "archive" },
          fn() { @sf.t("web-main.archived.sendRestores") },
          plus_mid,
          offer={
            words: fn() { @sf.t(if busy() { "web-main.archived.restoring" } else { "web-main.archived.restore" }) },
            name: fn() { @sf.t("web-main.archived.restore") },
            off,
            press: fn() { notice_restore(src, r, key) },
          },
          failed=fn() { composing.restore_errors.get(key).unwrap_or("") },
        )
        made.offset(By(fn() { (0.0, drawn_off(made)) })) |> ignore
      }
      // (its agent's prompt cache over: what going on would read again, and the choice of how it goes on)
      "wait" => {
        let cold = fn() { head().bind(fn(h) { h.cache_cold }) }
        let doing = fn() {
          match cold() {
            Some((session, _, _, _)) => "session.settings/" + r.station + "/" + session
            None => ""
          }
      }
        let held = fn() { @sfbase.doing(doing()) || head().map(fn(h) { h.offline }).unwrap_or(false) }
        // (drawn with the composer's ground's top as its shape goes, as far over it all the way: where its foot's
        // room goes its way on the page's too; the notice's own box, its row a slot of the column)
        let made = @sf.composer_notice_node(
          n,
          tips,
          fn() { "wait" },
          fn() { cold().map(fn(c) { c.1 }).unwrap_or("") },
          plus_mid,
          summary=fn() {
            match cold() {
              Some((_, status, detail, _)) if detail != "" => Some((status, detail))
              _ => None
            }
          },
          held~,
          choice={
            choices: fn() { [("go_on", @sf.t("web-main.chat.goOn")), ("afresh", @sf.t("web-main.chat.afresh"))] },
            chosen: fn() { if cold().map(fn(c) { c.3 }).unwrap_or(false) { "afresh" } else { "go_on" } },
            // (its menu open: the composer under it kept a box, the cursor gone to the menu (let_go_ms's))
            on_open: Some(fn(on) {
              if on {
                composing_node.choosing_cache.set(key, true)
              } else if composing_node.choosing_cache.contains(key) {
                composing_node.choosing_cache.remove(key)
              }
            }),
            choose: fn(value) {
              guard cold() is Some((session, _, _, afresh)) && !held() else { return }
              let next = value == "afresh"
              if next != afresh {
                let words = if next { "web-main.chat.afresh" } else { "web-main.chat.goOn" }
                let params : Json = { "station": Json::string(r.station), "key": Json::string(session), "afresh": Json::boolean(next) }
                @sfbase.act(src, @sf.t(words), doing(), "session.settings", params)
              }
            },
          },
        )
        made.offset(By(fn() { (0.0, drawn_off(made)) })) |> ignore
      }
      // (its station down, or gone for its update)
      "unplug" => {
        // (drawn with the composer's ground's top as its shape goes, as far over it all the way: where its foot's
        // room goes its way on the page's too; the notice's own box, its row a slot of the column)
        let made = @sf.composer_notice_node(
          n,
          tips,
          fn() { if head().map(fn(h) { h.updating }).unwrap_or(false) { "updating" } else { "unplug" } },
          fn() {
            match head().bind(fn(h) { h.offline_note }) {
              Some(note) => note
              None =>
                if r.station_name != "" {
                  @sf.t("web-main.chat.offline.named", args=[("name", r.station_name)])
                } else {
                  @sf.t("web-main.chat.offline")
                }
            }
          },
          plus_mid,
        )
        made.offset(By(fn() { (0.0, drawn_off(made)) })) |> ignore
      }
      // (the still.fail team's reply on a bug report sent from it: the chat's people's to read)
      "said" => {
        // (drawn with the composer's ground's top as its shape goes, as far over it all the way: where its foot's
        // room goes its way on the page's too; the notice's own box, its row a slot of the column)
        let made = @sf.composer_notice_node(
          n,
          tips,
          fn() { "said" },
          // (whose reply it is and the first line of their latest, as one, as the old composer's notice says it
          // (feedback_replies.mbt): its words wrapping as one line's do, never its title broken to stand beside them)
          fn() {
            let h = report().map(fn(f) { text(Some(f), "heading") }).unwrap_or("")
            let l = report().map(fn(f) { text(Some(f), "latest") }).unwrap_or("")
            if l == "" {
              h
            } else {
              h + "：" + l
            }
          },
          plus_mid,
          offer={
            words: fn() { @sf.t("web-main.feedback.open") },
            name: fn() { @sf.t("web-main.feedback.open") },
            off: fn() { false },
            press: fn() {
              match report() {
                Some(f) => open_feedback(src, r, text(Some(f), "id"))
                None => ()
              }
            },
          },
          dismiss={
            words: fn() { "" },
            name: fn() { @sf.t("web-main.feedback.dismiss") },
            off: fn() { false },
            press: fn() {
              guard report() is Some(f) else { return }
              let id = text(Some(f), "id")
              let latest_id = report_latest_id(f)
              guard latest_id != "" else { return }
              feedback_dismissed[id] = latest_id
              (src.call)(
                "feedback.dismiss",
                { "workspace": Json::string(text(Some(f), "workspace")), "id": Json::string(id), "reply": Json::string(latest_id) },
                @sfbase.answer_unread,
              )
            },
          },
        )
        made.offset(By(fn() { (0.0, drawn_off(made)) })) |> ignore
      }
      _ => ()
    }
  })
}

///|
/// An archived chat restored (还原对话 over its composer): told the core, felt as done or refused, why it failed kept.
fn notice_restore(src : Source, r : ChatRef, key : String) -> Unit {
  composing.restoring[key] = true
  composing.restore_errors.remove(key)
  let p : Map[String, Json] = {
    "station": Json::string(r.station),
    "session": Json::string(r.session),
    "archived": Json::boolean(false),
  }
  match @sfbase.chat_view_now(src, r).bind(fn(h) { h.thread }) {
    Some(th) => p["thread"] = Json::number(th)
    None => ()
  }
  (src.call)("chat.archive", Json::object(p), fn(res) {
    composing.restoring.remove(key)
    match res {
      Err(e) => {
        composing.restore_errors[key] = error_words(e)
        @ui.haptic(Reject)
      }
      Ok(_) => @ui.haptic(Confirm)
    }
  })
}

///|
/// ＋'s sheet for draft `key` on a touch system, opened by ＋ (`plus`, a node: attach_open's).
fn attach_open_node(plus : @view.View, src : Source, key : String) -> Unit {
  @sf.panel_nodes("", fn(v, close) { attach_body_node(v, src, key, close) }, from=Node(plus), w=attach_w)
  recent_opened()
}

///|
/// What is put into draft `w` from outside its field taken in as it is given, at its moment (take_in's, a node's: sfbase's
/// draft_taker while it shows; take_given), the cursor in its field after words a visualization asked to send; none of
/// what holds files while no file is taken in (`no_files`).
fn take_in_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  w : Writing,
  no_files : () -> Bool,
  before? : Ref[() -> Unit] = Ref(fn() {  }),
) -> Unit {
  let take = fn() {
    let off_files = @signals.untracked(no_files)
    let mut refused = false
    // (files let go on it together taken in as one drop, as the old composer takes them)
    let dropped : Array[@sfbase.Dragged] = []
    // (told once, before the first of what fills its draft is taken in: `before`)
    let mut told = false
    for g in @sfbase.draft_taken(w.key) {
      if off_files && (g is Dropped(_) || (g is Picked(list) && !list.is_empty())) {
        refused = true
      }
      let fills = !off_files && (g is Picked(_) || g is Shared(_) || g is Quoted(_) || g is Marked(_) || g is Dropped(_))
      if fills && !told {
        told = true
        (before.val)()
      }
      match g {
        Dropped(d) => dropped.push(d)
        _ => given_into(src, r.station, w, off_files, g)
      }
    }
    if !dropped.is_empty() && !off_files {
      writing_drop(src, w, r.station, dropped.map(dropped_of), drops_as_files(src, w.key))
    }
    // (files not taken in where none goes up now, its station not reached: said why, and what to do, never let go of
    // with nothing said, as the old composer says it)
    if refused {
      toast_later(@sf.t("web-main.composer.filesOffline"))
    }
  }
  let off = @sfbase.draft_taker(w.key, take)
  v.owns(off) |> ignore
}

///|
/// How many times each draft was sent with quotes from its composer made as nodes (composer_sent_from_node: a chat's or
/// a new chat's), by its key.
// kept across runs: put back by composing_node_reset
let draft_sent_counts : @sf.LiveMap[String, Int] = @sf.LiveMap::new()

///|
/// How many times draft `draft` was sent with quotes (draft_sent_counts'), followed as it changes.
fn draft_sent_into(draft : String) -> Int {
  draft_sent_counts.get(draft).unwrap_or(0)
}

///|
/// The id a quote's card waiting in a draft's composer made as nodes is shared by (mbui's View::shared), by its key and
/// the quote's id (`card_key`), as it changes: none ("") while it waits; once draft `draft` is sent after it was made
/// (`made`: draft_sent_into as it was made), the one of that send (sent_quote_id), which the message's card made with it
/// flies from as one box (composer_sent_from_node, SentFrom's `quote_ids`). So it pairs with nothing while it waits,
/// made again as what is round it is, and one of a later send's card is another's, never one living twice.
fn composer_quote_shared(draft : String, card_key : String, made : Int) -> String {
  let sent = draft_sent_into(draft)
  if sent > made {
    sent_quote_id(card_key, sent)
  } else {
    ""
  }
}

///|
/// The id the card of the quote `card_key` sent with the `sent`-th send with quotes of its draft is shared by.
fn sent_quote_id(card_key : String, sent : Int) -> String {
  "sent-quote:" + card_key + "#" + sent.to_string()
}

///|
/// What holds each draft's composer made as nodes at the shape it had as words were sent from it (its ground drawn as
/// tall as it was, coming down to its one line: composer_box_node's), said as it is emptied (sent_from_node).
// kept across runs: each let go with its composer's node
let composer_sent_holds : Map[String, () -> Unit] = Map([])

///|
/// The tiles of the files and the quotes' pictures waiting in each draft's composer made as nodes, by its key and the
/// file's id (a quote's picture: the quote's id, then `picture`): where each is laid out is said at a send
/// (send_in_chat_node), for the sent row's parts to fly from (sfbase's sent_part_said), as the old composer's are.
// kept across runs: each let go with its node
let composer_sent_parts : Map[String, @view.View] = Map([])

///|
/// Node `v` kept as `key`'s among composer_sent_parts while it is made.
fn composer_sent_parts_kept(key : String, v : @view.View) -> Unit {
  composer_sent_parts[key] = v
  v.owns(fn() {
    match composer_sent_parts.get(key) {
      Some(k) if k.id() == v.id() => composer_sent_parts.remove(key)
      _ => ()
    }
  })
  |> ignore
}

///|
/// Where node `key` of composer_sent_parts was last placed, while it is made: as it stood before the change under way,
/// nothing laid out for it.
fn composer_sent_part_at(key : String, keep_bottom? : Bool = false) -> (Double, Double, Double, Double)? {
  match composer_sent_parts.get(key) {
    Some(v) if v.alive() => {
      let (x, y, w, h) = v.rect()
      if keep_bottom {
        let (_, _, _, full_h) = v.placed_now()
        if full_h > h + 0.5 {
          Some((x, y + h - full_h, w, full_h))
        } else {
          Some((x, y, w, h))
        }
      } else {
        Some((x, y, w, h))
      }
    }
    _ => None
  }
}

///|
/// What is written sent into chat `r` from a composer made as nodes (send_in_chat's): in the list in the moment it is
/// sent, before the core has it (sent_local: its list goes to its end for it, chat_body_node's), the composer empty at
/// once; then what the core took (`composer.take`) goes (`chat.send`). Not taken in at all: back in the composer unless
/// something new is written there, saying why.
pub fn send_in_chat_node(src : Source, r : ChatRef, v : ChatView, w : Writing) -> Unit {
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  @ui.haptic(KeyboardTap)
  let words = sent_words(w)
  let rk = r.station + "\u{1}" + r.session
  remember_sent_pictures_now(src, w, r.station)
  let marks = @sfbase.refs_sent_marks(w.key, words)
  ignore(marks)
  let runs = @sfbase.refs_sent_runs(w.key, words)
  let from = composer_sent_from_node(src, w)
  let row = sent_local(
    rk,
    Some(chat_whole(src, r, v)),
    words,
    @signals.untracked(fn() { up_files(w) }),
    going=@signals.untracked(fn() { going_files(w) }),
    quotes=@signals.untracked(fn() { sent_quotes(w) }),
    runs~,
    from~,
    now=(src.now)(),
  )
  @sfbase.chat_latest_now(src, r, v, @sf.t("web-main.chat.toLatest")) |> ignore
  // (emptied in the change its sent key comes in, as the old composer's take was asked in the build that sent it: its
  // foot giving back its room as that key comes, in the one way of its column; what the core answers a change of its
  // own)
  sent_from_node(src, r, v, w, rk, row)
}

///|
/// Where what draft `w`'s composer made as nodes holds stands in it now, as part of what is sent from it (send_in_chat_node's,
/// a new chat's): its row flies from there, whatever makes it at whatever moment (sent_local's `from`, SentFrom; mbui's
/// View::flies_in); none with motion reduced.
pub fn composer_sent_from_node(src : Source, w : Writing) -> @sfbase.SentFrom? {
  if @ui.reduced_motion() {
    None
  } else {
    // (its words from where they stand in the field)
    let words = w.field.words_at().map(fn(at) { at.0 })
    // (the room of the field they are seen within: what of them is scrolled out of it not seen as they set out)
    let words_room = w.field.words_at().map(fn(at) { at.1 })
    // (each quote's card by the id it is shared by once this is sent, this draft's next send with quotes: the message's
    // made with it flies from it as one box, View::shared)
    let held_quotes = @signals.untracked(fn() { w.quotes.get() })
    let quote_ids = if held_quotes.is_empty() {
      []
    } else {
      let sent = @signals.untracked(fn() { draft_sent_into(w.key) }) + 1
      draft_sent_counts.set(w.key, sent)
      held_quotes.map(fn(q) { sent_quote_id(w.key + "\u{1}" + text(Some(q), "id"), sent) })
    }
    // (each of its files from its tile there, as the old composer's: its picture's or its card's, by what its row keys
    // it by (flying_key); each quote's own picture from its square in its card)
    let parts : Array[(String, (Double, Double, Double, Double))] = []
    let going = @signals.untracked(fn() { going_files(w) }).map(fn(f) { text(Some(f), "id") })
    for f in @signals.untracked(fn() { w.files.get() }) {
      let v = Some(f)
      let id = text(v, "id")
      let pictured = waiting_picture(src, w, v) is Some(_)
      let key = flying_key(v, going.contains(id), pictured)
      match composer_sent_part_at(w.key + "\u{1}" + id, keep_bottom=!pictured) {
        Some(at) if key != "" => parts.push((key, at))
        _ => ()
      }
    }
    let held = @signals.untracked(fn() { w.quotes.get() })
    for i, _ in @signals.untracked(fn() { sent_quotes(w) }) {
      let q = Some(held[i])
      let own = field(q, "own")
      let key = flying_key(own, going.contains(text(own, "id")), true)
      match composer_sent_part_at(w.key + "\u{1}" + text(q, "id") + "\u{1}picture") {
        Some(at) if own is Some(_) && key != "" => parts.push((@sfbase.quote_picture_key(i), at))
        _ => ()
      }
    }
    Some({ words, words_room, quote_ids, parts, delay: 0.0 })
  }
}

///|
/// Draft `w` sent into chat `r` as row `row` of `rk` from a composer made as nodes (send_in_chat_node's): its ground held
/// at the shape it had, then taken and sent as any composer's is (chat_draft_take).
fn sent_from_node(src : Source, r : ChatRef, v : ChatView, w : Writing, rk : String, row : String) -> Unit {
  // (words sent before these still in the field they set out from: landed in their row first, these flying over none)
  sent_in_field_land(r.station + "\u{1}" + r.session)
  // (emptied as it is taken: laid out at its one line at once, its room under the list's last row with it (the sent
  // row carries it), its ground keeping the shape it had as what
  // was sent left it, as the old composer's on this page does (sfbase's sent_out_hold_ms: till what flies from it begins
  // its rise), then down on their flight's curve, by move_most_ms)
  if !@ui.reduced_motion() {
    match composer_sent_holds.get(w.key) {
      Some(hold) => hold()
      None => ()
    }
  }
  sent_into_chat(src, r, v, w, rk, row)
}

///|
/// The pictures a composer made as nodes shows going with its message (remember_sent_pictures'), each by its upload
/// and, once up, by the station's path, so its row draws the same picture.
fn remember_sent_pictures_now(src : Source, w : Writing, station : String) -> Unit {
  let remember = fn(v : Json?, picture : String) {
    if picture == "" || picture == "!" {
      return
    }
    let id = text(v, "id")
    if id != "" {
      @sfbase.sent_picture_kept("upload\u{1}" + id, picture)
    }
    let path = text(field(v, "done"), "path")
    if station != "" && path != "" {
      @sfbase.sent_picture_kept(@sfbase.sent_key(station, path), picture)
    }
  }
  for file in @signals.untracked(fn() { w.files.get() }) {
    let v = Some(file)
    remember(v, waiting_picture(src, w, v).unwrap_or(""))
  }
  // (a quote's own picture where this device has it: picked here, or kept as the draft was (composer.picture); a
  // station's has the same source in both places already, its reveal not stopped half way as its message takes over)
  for q in @signals.untracked(fn() { w.quotes.get() }) {
    let own = field(Some(q), "own")
    match writing_pictures.get(text(own, "id")) {
      Some(p) => remember(own, p)
      // (a message's on the station quoted: its picture the station's, never one kept for a draft under its name)
      None if text(field(own, "done"), "owner") == "" => remember(own, waiting_picture(src, w, own).unwrap_or(""))
      None => ()
    }
  }
}

///|
/// The `@` menu over composer `box` for draft `w` (ref_menu's, as nodes: the library's offers_node), while its field
/// has the focus and is at `@` and a few letters: its head (引用对话 and the words typed), then the chats they find (the
/// workspace's on every station of it, then the viewer's others', not this one), each its agent's mark, its title
/// (another workspace's or station's whose after it), when it was last active; or what it says in their place. ↑ / ↓
/// choose, Enter or Tab or a press put the one chosen in as its mark; Escape closes it for this `@`.
fn ref_menu_node(box : @view.View, src : Source, r : ChatRef, w : Writing) -> Unit {
  let into = workspace_of(r.station)
  let at = fn() {
    guard w.field.focused() && @sfbase.refs_at(w.key) is Some((start, query)) else { return None }
    if @sfbase.refs_closed(w.key, start) {
      None
    } else {
      Some((start, query))
    }
  }
  let found = fn() -> (Int, String, @sfbase.Topic, Array[Json])? {
    guard at() is Some((start, query)) else { return None }
    let params : Map[String, Json] = {
      "scope": Json::string(into),
      "query": Json::string(query),
      "station": Json::string(r.station),
      "limit": Json::number(ref_shown.to_double()),
      "elsewhere": Json::boolean(true),
      "exclude": Json::string(r.session),
    }
    let topic = @sfbase.refs_search(src, w.key, params)
    Some((start, query, topic, items(topic.value, "items")))
  }
  // (what it shows: what is found now, or, its `@` gone (picked, let go), what it showed then, kept as it leaves: so its
  // words, rows and height go with it as they were, never turned to what it says when it has none on its way out;
  // what opens it, what it waits for and what a pick takes read what is found now alone)
  let kept_found : Ref[(String, @sfbase.Topic, Array[Json])?] = Ref(None)
  let shown_found = fn() {
    match found() {
      Some((_, q, topic, list)) => {
        let now = Some((q, topic, list))
        kept_found.val = now
        now
      }
      None => kept_found.val
    }
  }
  let chats = fn() { shown_found().map(fn(f) { f.2 }).unwrap_or([]) }
  let key_of = fn(x : Json) { text(Some(x), "station") + "\t" + text(Some(x), "id") }
  // (the chats found by their key, once for every row: a row reads its own by its key)
  let by_key : @signals.Computed[Map[String, Json]] = @signals.computed(fn(_) {
    Map::from_array(chats().map(fn(x) { (key_of(x), x) }))
  })
  let current = @signals.signal(0, same=fn(a, b) { a == b })
  // (opened once what it lists is answered, so it comes in as tall as what it holds, never growing on its way in; one
  // the core is slow to answer opened after later_ms on what says it is read: `wait_long`, a wait's own timing,
  // sf's waited_past_node, from when it began to wait)
  let waiting = fn() {
    match (at(), found()) {
      (Some(_), Some((_, _, topic, _))) => topic.value is None && topic.error is None
      _ => false
    }
  }
  let wait_since = @signals.signal(0.0, same=fn(a, b) { a == b })
  let last_query : Ref[String?] = Ref(None)
  // (the words typed after the `@` another: the first chosen again, and its wait from now)
  box.reacts(fn() { at().map(fn(a) { a.1 }) }, fn(q) {
    if q is Some(_) && last_query.val != q {
      current.set(0)
      wait_since.set(box.cause_at())
    }
    last_query.val = q
  })
  let wait_long = @sf.waited_past_node(box, fn() { wait_since.get() }, @sf.later_ms, going=waiting)
  @sf.offers_node(
    box,
    box,
    fn() {
      match found() {
        Some((_, _, topic, _)) => topic.value is Some(_) || topic.error is Some(_) || wait_long()
        None => false
      }
    },
    fn() { chats().map(key_of) },
    current,
    fn(row, k, on) {
      let item = fn() { by_key.get().get(k) }
      let ci = fn() { item().map(@sfbase.chat_item) }
      row.box(fn(logo) {
        @sf.style_node(logo, fn() { ref_logo })
        logo.pick(fn() { ci().bind(fn(c) { c.agents.get(0) }).map(fn(a) { (a.maker, a.runtime) }) }, at_once=true, fn(m, a) {
          match a {
            Some((maker, runtime)) => @sf.maker_mark_node(m, maker, runtime, ref_logo_size) |> ignore
            None => ()
          }
        })
      })
      |> ignore
      row.box(fn(cell) {
        @sf.style_node(cell, fn() { ref_title_cell })
        // (all the row leaves, its time at the row's end, as the old menu's)
        cell.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(cell, fn() { ci().map(fn(c) { c.title }).unwrap_or("") }, fn() { ref_title }) |> ignore
        // another workspace's: whose; another station's: its mark and name
        cell.show(fn() { text(item(), "outside") != "" }, fn(chip) {
          @sf.style_node(chip, fn() { ref_chip_station })
          @sf.workspace_badge_node(
            chip,
            fn() { text(item(), "outside") },
            fn() { text(item(), "outsideEmoji") },
            fn() { text(item(), "outsideIcon") },
            ref_chip_icon,
          )
          @sf.words_node(chip, fn() { text(item(), "outside") }, fn() { ref_chip_words }) |> ignore
        })
        cell.show(fn() { text(item(), "outside") == "" && flag(item(), "otherStation") }, fn(chip) {
          @sf.style_node(chip, fn() { ref_chip_station })
          @sf.station_mark_node(
            chip,
            fn() { ci().map(fn(c) { c.station_emoji }).unwrap_or("") },
            fn() { ci().map(fn(c) { c.station_icon }).unwrap_or("") },
            ref_chip_icon,
            fn() { @sf.theme().p.muted },
            fn() { 0 },
          )
          @sf.words_node(chip, fn() { ci().map(fn(c) { c.station_name }).unwrap_or("") }, fn() { ref_chip_words })
          |> ignore
        })
      })
      |> ignore
      @sf.words_node(row, fn() { ci().map(fn(c) { c.ago }).unwrap_or("") }, fn() { ref_time }) |> ignore
      ignore(on)
    },
    fn(k) { @signals.untracked(fn() { by_key.get().get(k) }).map(fn(x) { @sfbase.chat_item(x).title }).unwrap_or("") },
    fn(i) {
      guard found() is Some((start, _, _, list)) && list.get(i) is Some(x) else { return }
      let item = @sfbase.chat_item(x)
      @sfbase.refs_pick_now(src, w.key, w.field, start, into, item.station, item.id, item.title, fn(why) {
        toast_later(@sf.t("web-main.composer.refFailed", args=[("title", item.title), ("error", why)]))
      })
    },
    fn() { @sfbase.refs_close(w.key) },
    @sf.t("web-main.chatRef.title"),
    head=fn() { (@sf.t("web-main.chatRef.title"), shown_found().map(fn(f) { f.0 }).unwrap_or("")) },
    side=Top,
    offset=ref_menu_off,
    none=fn(n) {
      @sf.style_node(n, fn() { ref_empty })
      n.pick(
        fn() {
          match shown_found() {
            Some((_, topic, _)) if topic.value is None => if topic.error is Some(_) { 2 } else { 1 }
            Some((q, _, list)) if list.is_empty() => if q != "" { 3 } else { 4 }
            _ => 0
          }
        },
        at_once=true,
        fn(p, said) {
          match said {
            1 => @sf.wait_line_node(p, fn() { @sf.t("common.reading") }) |> ignore
            2 =>
              @sf.words_node(p, fn() { @sf.t("web-main.chatRef.update", args=[("app", @sf.product())]) }, fn() {
                ref_empty_words
              })
              |> ignore
            3 => @sf.words_node(p, fn() { @sf.t("web-main.chatRef.noMatch") }, fn() { ref_empty_words }) |> ignore
            4 => @sf.words_node(p, fn() { @sf.t("web-main.chatRef.none") }, fn() { ref_empty_words }) |> ignore
            _ => ()
          }
        },
      )
    },
  )
}

///|
/// Each draft's composer made as nodes: its box, its foot in its list (what it is laid out as, read by what looks at
/// it: a test) and how much taller than it is laid out its ground is drawn (what it held as words were sent from it:
/// composer_box_node's sent_over), let go with it.
// kept across runs: each let go with its node
let composer_nodes : Map[String, (@view.View, @view.View, @motion.NodeWay, @motion.NodeWay)] = Map([])

///|
/// Per-draft extra height (was - one) reader for narrow NewChat -> Chat composer height handoff.
// kept across runs: cleared in composing_node_reset and on node rest/unmount
let composer_extra_heights : Map[String, () -> Double] = Map([])

///|
/// Extra height above one-line open height (multi-line text, attachments, or quotes) for draft `draft`'s composer node.
pub fn composer_node_extra_height(draft : String) -> Double {
  composer_extra_heights.get(draft).map(fn(f) { f() }).unwrap_or(0.0)
}

///|
/// How much taller than it is laid out composer `c`'s ground is drawn at `at` (what it holds of the shape it had as
/// words were sent from it), 0 at rest.
fn composer_node_over(c : (@view.View, @view.View, @motion.NodeWay, @motion.NodeWay), at : Double) -> Double {
  c.2.value_at(at)
}

///|
/// Where draft `draft`'s composer made as nodes is drawn now (its box's ground, in the window), none where none shows.
pub fn composer_node_box(draft : String) -> (Double, Double, Double, Double)? {
  composer_nodes.get(draft).map(fn(c) { c.0.placed_window_now() })
}

///|
/// How much room draft `draft`'s composer made as nodes takes under its list's last row at `at` (its foot as laid out,
/// with what its ground holds over it of the shape it had as words were sent from it: as the old composer's room is
/// held for them, composer_room), none where none shows.
pub fn composer_node_room(draft : String, at : Double) -> Double? {
  composer_nodes.get(draft).map(fn(c) { c.1.laid_window_now().3 + composer_node_over(c, at) })
}

///|
/// Where the composer made as nodes shown now is laid out (composer_node_box's), whichever draft's it is: none where none
/// shows. (`at`: what its ground holds over it as words leave it is drawn, not laid out: composer_node_room's.)
pub fn composer_node_shown(at : Double) -> (Double, Double, Double, Double)? {
  ignore(at)
  for _, c in composer_nodes {
    if c.0.alive() {
      return Some(c.0.placed_window_now())
    }
  }
  None
}

///|
/// What words go of draft `w` as it is sent, as the core's composer.take says them (client/core-ts/src/composer.ts:
/// `linkWords`, `pathWords`): what is written, then each link (its title on a line, then where it goes), then where each
/// file named by its path is; so the row sent from here says at once what the core's says of it.
fn sent_words(w : Writing) -> String {
  let parts : Array[String] = []
  let written = @signals.untracked(fn() { w.text.get() }).trim(chars=" \n\t").to_owned()
  if written != "" {
    parts.push(written)
  }
  let files = @signals.untracked(fn() { @sfbase.writing_files(w) })
  for f in files {
    match field(Some(f), "link") {
      Some(Object(_)) as l if text(l, "url") != "" =>
        parts.push(if text(l, "title") != "" { text(l, "title") + "\n" + text(l, "url") } else { text(l, "url") })
      _ => ()
    }
  }
  for f in files {
    match field(Some(f), "ref") {
      Some(Object(_)) as r if text(r, "mode") == "path" =>
        parts.push(
          @sf.t(if flag(r, "dir") { "common.folderOn" } else { "common.pathOn" }, args=[
            ("station", text(r, "stationName")),
            ("path", text(r, "path")),
          ]),
        )
      _ => ()
    }
  }
  parts.join("\n")
}
