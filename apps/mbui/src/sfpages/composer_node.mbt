// The composer made as nodes of the window's tree, once (实验性功能's 试用新输入框: sfbase's composer_nodes), in the place
// of the old one (composer.mbt) in a chat's list's foot. What it is, apart from how it is drawn, is the old one's
// (composer_state.mbt: whether it is opened, whether what is written can go, what send does; compose_given.mbt: what is
// put into its draft from outside it, taken at that moment; sent_into_chat: what goes once the core took it). One
// ground, its field one node all along (opened or not, its focus and what the input method composes never let go):
// a capsule of one line, its ＋ and send at its ends, opened a box, its words over the row of ＋ and send; ＋ and send
// in its two foot corners all the way, what it holds keeping to its foot as it changes height (View::resizes, foot:
// 「以底部为 origin」, the owner 2026-10-30), its words going across from where they stood on one line to where they
// stand opened on the same way. Not made as nodes yet, so not shown here: the `@` menu, 抄送 and what is said over it
// (sfpages' chat_ref, cc_chooser, chat_notices), its words flying from where each card stood.

///|
/// What a composer made as nodes writes to and how it shows (ComposerSpec's, followed): its station, its draft, its
/// chat's session (typing warms its agent), what its field says while empty, whether it takes words and nothing goes
/// (`locked`), whether its station is offline (no file taken in), whether typing warms its agent; whether it stays
/// opened however little it holds (`roomy`: a new chat's, 待派发's), whether it takes the cursor as it is made (a chat's,
/// as it comes on top), what stands in its foot's row between ＋ and send (`tools`: where it goes), and how much room its
/// words leave at their end, clear of what stands over its top corner (`words_end`), and what send is called (`sends`).
priv struct NodeSpec {
  station : String
  draft : String
  session : String
  placeholder : String
  locked : () -> Bool
  offline : () -> Bool
  warm_agent : () -> Bool
  roomy : Bool
  takes_focus : Bool
  tools : ((@view.View) -> Unit)?
  words_end : Double
  sends : String
}

///|
/// Chat `r`'s composer made as nodes in `parent` (its list's foot: chat_page_made's `foot_node`), as wide as the column
/// leaves it (composer_width), 12 over it and its foot's room under it (composer_foot_at), its corner where it stands
/// (`apart`: at a panel's foot, concentric with its corners; composer_place), its tips in `tips`. What it sends goes
/// into the chat as it is now (sent_into_chat).
pub fn chat_composer_node(parent : @view.View, src : Source, r : ChatRef, tips : @sf.TipLayer, apart? : Bool = false) -> Unit {
  guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(ws) else { return }
  let head = fn() { @sfbase.chat_view_now(src, r) }
  let spec : NodeSpec = {
    station: r.station,
    draft: r.station + ":" + r.session,
    session: r.session,
    placeholder: @sf.t("web-main.composer.placeholder"),
    locked: fn() { false },
    offline: fn() { head().map(fn(v) { v.offline }).unwrap_or(false) },
    warm_agent: fn() { !head().map(fn(v) { v.archived }).unwrap_or(false) },
    roomy: false,
    takes_focus: true,
    tools: None,
    words_end: 0.0,
    sends: @sf.t("web-main.composer.send"),
  }
  parent.by_room(fn(foot, room) {
    foot
    .lies_along(Is(@view.Lies::End))
    .lines_up(Is(Some(@view.Along::Middle)))
    .padding(By(fn() { (0.0, 12.0, 0.0, composer_foot_at(room.width())) }))
    // (never less than it takes opened with one line: its being opened or let go moves none of the messages, as
    // composer_open_room keeps for the old one)
    .min_height(By(fn() {
      Some(composer_open_box_at(node_field_line(foot), @sf.composer_corner()) + 12.0 + composer_foot_at(room.width()))
    }))
    |> ignore
    foot.box(fn(at) {
      at.width(By(fn() { Some(composer_width(room.width())) })) |> ignore
      composer_node(at, src, ws, spec, fn(w) { send_in_chat_node(src, r, w) }, fn() {
        if apart {
          composer_place_at(room.width(), node_field_line(at))
        } else {
          composer_alone
        }
      }, tips)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The line a composer's field made as nodes is laid out on: the theme's words' line at the system's size of words as
/// node `v`'s tree draws it (field_line's).
fn node_field_line(v : @view.View) -> Double {
  let look = @ui.style_words(@sf.theme().t.words)
  let line = if look.line < 0.0 { -look.line * look.size } else { look.line }
  @ui.sp_at(v.words_scale(), line)
}

///|
/// The composer for `spec` made in `parent`, `send` what pressing send (or Enter) does with what is written once it is
/// ready (composer_submit), where it stands as `place` says.
fn composer_node(
  parent : @view.View,
  src : Source,
  ws : Workspace,
  spec : NodeSpec,
  send : (Writing) -> Unit,
  place : () -> ComposerPlace,
  tips : @sf.TipLayer,
) -> Unit {
  let w = writing(src, spec.draft)
  let no_files = fn() { (spec.locked)() || (spec.offline)() }
  // (its corner where it stands: what waits in it and its round controls follow it, @sf.composer_inner)
  @sf.composer_round.val = @signals.untracked(fn() { place().corner })
  // (the box it stays a moment after its field lets the focus go, LET_GO_MS; none while a layer over it holds it)
  let lingers = @signals.signal(false)
  // (whether it is opened: composer_state's, followed)
  let open = fn() {
    composer_wants_open(w, roomy=spec.roomy, focused=w.field.focused(), lingers=lingers.get())
  }
  // (made for a chat come on top, with keyboard and mouse: the cursor in it, its keyboard at hand, taken from no field
  // in use (the switcher's, a dialog's); asked for, composer_take_focus, with touch too, its keyboard up)
  if spec.takes_focus &&
    @signals.untracked(fn() {
      (!@sf.soft_keyboard() && !@ui.field_has_keys()) || (composing.wanted && !(spec.locked)())
    }) {
    composing.wanted = false
    w.field.focus()
  }
  // (words just sent from it: its field's caret away till they are half way up and out of it, as the old flight's,
  // flight_hint_away)
  let away = @signals.signal(false)
  parent.box(fn(cap) {
    // words sent from it (send pressed, Enter): its ground keeps the shape it had as they leave it (sent_out_hold_ms),
    // then comes down to what it holds now on their flight's curve, the list's foot with it, one way (the old one's
    // sent_out shape); its caret away meanwhile
    let send = fn(w : Writing) {
      let hold = @sfbase.sent_out_hold_ms
      let total = @ui.move_most_ms
      cap.resizes(foot=true, spec=(total, fn(f) {
        let t = f * total
        if t <= hold {
          0.0
        } else {
          @ui.Ease::Flight.at((t - hold) / (total - hold))
        }
      }))
      |> ignore
      away.set(true)
      cap.at_moment(cap.cause_at() + @sfbase.flight_desk_ms / 2.0, fn() { away.set(false) }) |> ignore
      send(w)
    }
    let line = fn() { node_field_line(cap) }
    let side = fn() { @sf.theme().round.side }
    // (its round controls as far in as makes them concentric with it: on one line its place's capsule_pad, opened its
    // foot corners' composer_round_in)
    let pad_shut = fn() { place().capsule_pad + capsule_extra_at(line()) }
    let shut_h = fn() { dmax(side(), line()) + 2.0 * place().capsule_pad }
    let shown_open = @motion.NodeWay::new(if @signals.untracked(open) { 1.0 } else { 0.0 })
    cap
    .glass(Is(Some(@sf.glass_floating())))
    .cursor(Is(Some(@view.Cursor::IBeam)))
    .margin(By(fn() {
      let (l, r, b) = if open() { (0.0, 0.0, 0.0) } else { place().capsule_in }
      (l, 0.0, r, b)
    }))
    .padding(By(fn() {
      if open() {
        let p = @sf.composer_pad
        (p, p, p, p)
      } else {
        let p = place().capsule_pad
        (p + capsule_extra_at(line()), p, p + capsule_extra_at(line()), p)
      }
    }))
    |> ignore
    // opened or let go (what it holds then is one line at most: anything more keeps it opened): laid out as it comes
    // out at once, nothing round it moving (its list's foot keeps the room it takes opened, composer_open_room), its
    // ground drawn from the shape it had to that one on the old one's clock (composer_shape_ms), kept to its foot, its
    // words going across with it (their offset); round as a capsule as tall as it is, as round as the box opened
    let open_h = fn() { composer_open_box_at(line(), @sf.composer_corner()) }
    let round = fn(h : Double) {
      let k = if h <= shut_h() { 0.0 } else if h >= open_h() { 1.0 } else { (h - shut_h()) / (open_h() - shut_h()) }
      dmin(h / 2.0, shut_h() / 2.0 + (@sf.composer_corner() - shut_h() / 2.0) * k)
    }
    cap
    .ground_drawn(By(fn() {
      let k = shown_open.shown(cap)
      let to = if shown_open.target() >= 0.5 { 1.0 } else { 0.0 }
      if k == to {
        let r = if to == 1.0 { @sf.composer_corner() } else { shut_h() / 2.0 }
        { ..@view.ground_as_laid, corners: Some((r, r, r, r)) }
      } else {
        let drawn = shut_h() + (open_h() - shut_h()) * k
        let laid = if to == 1.0 { open_h() } else { shut_h() }
        let r = round(drawn)
        { dx: 0.0, dy: laid - drawn, dw: 0.0, dh: drawn - laid, corners: Some((r, r, r, r)) }
      }
    }))
    |> ignore
    cap.reacts(open, fn(on) {
      // det-ok(motion-length): the field opening past ＋ and send kept off them on this clock, as the old one's
      shown_open.go_ms(cap, if on { 1.0 } else { 0.0 }, composer_shape_ms, ease=Move)
    }, at_start=false)
    // (a press on it beside its field: the field's, the focus given it)
    cap.on_press(fn() { if !(spec.locked)() { w.field.focus() } }) |> ignore
    // (the focus gone from its field: the box kept a moment (LET_GO_MS), let go then, unless it comes back meanwhile
    // or a layer over it holds it to give it back)
    let let_go_off : Ref[() -> Unit] = Ref(fn() {  })
    cap.reacts(fn() { w.field.focused() }, fn(focused) {
      (let_go_off.val)()
      let_go_off.val = fn() {  }
      if focused {
        lingers.set(false)
      } else if !w.field.parked() {
        lingers.set(true)
        let_go_off.val = cap.at_moment(cap.cause_at() + let_go_ms, fn() { lingers.set(false) })
      }
    }, at_start=false)
    // (what is put into its draft from outside it, taken at that moment, whatever is drawn: compose_given.mbt)
    let taken = fn() {
      @signals.untracked(fn() {
        let dropped : Array[Json] = []
        for g in @sfbase.draft_taken(w.key) {
          match g {
            Dropped(d) => dropped.push(dropped_of(d))
            _ => given_into(src, spec.station, w, no_files(), g)
          }
        }
        if !dropped.is_empty() {
          if no_files() {
            // (not taken in where none goes up now: said why, and what to do, never let go of with nothing said)
            let why = if (spec.offline)() {
              @sf.t("web-main.composer.filesOffline")
            } else {
              @sf.t("web-main.composer.filesLocked")
            }
            toast_later(why)
          } else {
            writing_drop(src, w, spec.station, dropped, drops_as_files(src, w.key))
          }
        }
      })
    }
    cap.owns(@sfbase.draft_taker(w.key, taken)) |> ignore
    // what waits to go with it, over its words: the quotes, then the files
    cap.show(fn() { w.quotes.get().length() > 0 || w.files.get().length() > 0 }, fn(s) {
      waiting_node(s, src, w, tips)
    })
    // its words, one node all along: on one line between ＋ and send, opened over their row
    cap.box(fn(words) {
      words
      .padding(By(fn() {
        if open() {
          (8.0, 8.0, 8.0 + spec.words_end, side() + @sf.composer_round_in() - @sf.composer_pad + 10.0)
        } else {
          let gap = side() + 1.0
          (gap, dmax(0.0, (side() - line()) / 2.0), gap + 8.0, dmax(0.0, (side() - line()) / 2.0))
        }
      }))
      // (drawn from where they stood on one line to where they stand opened, and back, on its way, from its left and its
      // foot: laid out where they go)
      .offset(By(fn() {
        let k = shown_open.shown(words)
        let to = if shown_open.target() >= 0.5 { 1.0 } else { 0.0 }
        let (ml, _, mb) = place().capsule_in
        let left_shut = ml + pad_shut() + side() + 1.0
        let left_open = @sf.composer_pad + 8.0
        let foot_shut = mb + place().capsule_pad + dmax(0.0, (side() - line()) / 2.0)
        let foot_open = side() + @sf.composer_round_in() + 10.0
        let left = fn(at : Double) { left_shut + (left_open - left_shut) * at }
        let foot = fn(at : Double) { foot_shut + (foot_open - foot_shut) * at }
        (left(k) - left(to), foot(to) - foot(k))
      }))
      |> ignore
      composer_field_node(words, src, ws, spec, w, fn() { lingers.get() }, fn() { away.get() }, send)
    })
    |> ignore
    // ＋ and send in its foot corners, all the way: over all of it, on its foot
    cap.box(fn(row) {
      row
      .over(Is(true))
      .row(Is(true))
      .lies_along(Is(@view.Lies::Between))
      .lines_up(Is(Some(@view.Along::End)))
      .padding(By(fn() {
        let d = if open() { @sf.composer_round_in() } else { pad_shut() }
        let b = if open() { @sf.composer_round_in() } else { place().capsule_pad }
        (d, 0.0, d, b)
      }))
      |> ignore
      let plus : Ref[@view.View?] = Ref(None)
      plus.val = @sf.icon_button_node(
        row,
        "plus",
        fn() { @sf.t("web-main.composer.attach") },
        fn() {
          if @sf.attach_from_sheet() {
            match plus.val {
              Some(p) => attach_open(Node(p), src, w.key)
              None => ()
            }
          } else {
            pick_files(w)
          }
        },
        tips~,
        size=side(),
        icon_size=plus_icon,
        disabled=no_files,
        shortcut="composer.file",
      )
      |> Some
      // (between them what it says of where it goes, where it says so: from ＋'s end, as far as send leaves)
      row.box(fn(gap) {
        gap.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        match spec.tools {
          Some(tools) => {
            gap.row(Is(true)).lines_up(Is(Some(@view.Along::Middle))).padding(Is((6.0, 0.0, 6.0, 0.0))) |> ignore
            tools(gap)
          }
          None => ()
        }
      })
      |> ignore
      @sf.send_button_node(
        row,
        fn() { spec.sends },
        fn() { composer_ready(w, locked=(spec.locked)()) },
        fn() { w.starting.get() },
        fn() { composer_submit(src, w, spec.station, locked=(spec.locked)(), send) |> ignore },
        tips~,
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  // why what it held could not go up or be read, under it
  parent.show(fn() { w.error.get() != "" }, fn(s) {
    s.box(fn(e) {
      @sf.style_node(e, fn() { error_box })
      @sf.words_node(e, fn() { w.error.get() }, fn() { composer_error_words }) |> ignore
    })
    |> ignore
  })
}

///|
/// The field of draft `w`'s composer made as nodes in `parent` (composer_text's): what is typed set as its message
/// will set it, as tall as its lines up to what it grows to (a share of the window), its references marked as the core
/// reads them; Enter sends (⌘Enter where 快捷键 says so), words pasted past the core's bound go as a file of their own,
/// files pasted go up; what it says while empty shown only at rest without the cursor (`lingers`: the box kept a
/// moment after the focus went), nor its caret while words sent leave it (`away`); each edit told the core at its moment (warming the agent's runtime as it is typed); with
/// nothing typed ↑ / ↓ go to the chat above or below.
fn composer_field_node(
  parent : @view.View,
  src : Source,
  ws : Workspace,
  spec : NodeSpec,
  w : Writing,
  lingers : () -> Bool,
  away : () -> Bool,
  send : (Writing) -> Unit,
) -> Unit {
  let prefs = fn() { src.topic("prefs", {}).get().value }
  let by_command = @signals.untracked(fn() { @settings.sends_by_command(prefs()) })
  let no_files = fn() { (spec.locked)() || (spec.offline)() }
  @sfbase.paste_bound_ask(src)
  let f = @ui.field(
    parent,
    w.field,
    words=true,
    line=@signals.untracked(fn() { node_field_line(parent) }),
    trim=true,
    enter_sends=@sf.enter_sends(command=by_command),
    command_sends=@sf.command_sends(by_command),
    look=@sfbase.refs_look(w.key, @signals.untracked(fn() { @sf.theme().p.accent })),
    size_by=fn() { @ui.style_words(@sf.theme().t.words).size },
    // (what it says while empty only on a composer at rest without the cursor (composer_hint's): none while its field
    // has the focus or keeps its box a moment after)
    colors_by=fn() {
      let p = @sf.theme().p
      let hint = if w.field.focused() || lingers() || away() { @sf.alpha(p.subtle, 0.0) } else { p.subtle }
      (p.text, hint, if away() { @sf.alpha(p.accent, 0.0) } else { p.accent })
    },
    placeholder_by=fn() {
      match space_hint_now(prefs(), (spec.locked)()) {
        "" => spec.placeholder
        hint => hint
      }
    },
    max_lines_by=fn() {
      let n = (dmin(text_most, parent.window().1 * text_window_share) / node_field_line(parent)).to_int()
      if n < 1 {
        1
      } else {
        n
      }
    },
    paste_limit_by=fn() { if no_files() || w.starting.get() { 0 } else { @sfbase.paste_bound_now() } },
    pasted=fn(words) { @sfbase.writing_paste(src, w, spec.station, words) },
    files=fn(files) {
      if !no_files() {
        for f in files {
          writing_add(src, w, spec.station, f.0, f.1)
        }
      }
    },
    edit=fn(e) { @sfbase.refs_edited(src, w.key, w.field, spec.station, (spec.locked)(), e) },
    edited=fn(words) {
      if words != w.text.get() && !w.starting.get() {
        writing_text(src, w, words)
        warm_now(src, spec, parent.cause_at())
      }
    },
    submitted=fn(words) {
      if !w.starting.get() {
        if words != w.text.get() {
          writing_text(src, w, words)
        }
        composer_submit(src, w, spec.station, locked=(spec.locked)(), send) |> ignore
      }
    },
    label=spec.placeholder,
  )
  f.grow(Is(1.0)) |> ignore
  // nothing typed in a chat's: ↑ ↓ the chat above or below, as the list shows them now
  f.on_key(fn(k) {
    guard spec.session != "" && k.mods == 0 && (k.code == @ui.key_code_up || k.code == @ui.key_code_down) else { return false }
    guard w.text.get() == "" && !(@sfbase.neighbour_held.val)() else { return false }
    (@sfbase.neighbour_go.val)(src, ws, if k.code == @ui.key_code_up { -1 } else { 1 })
    true
  })
  |> ignore
}

///|
/// What the composer's field says in place of its placeholder with keyboard and mouse: that the composer's key puts the
/// cursor there ("" otherwise: locked, a soft keyboard's, no key said for it) (space_hint's, as nodes have it: its
/// field holding the focus shows no placeholder anyway).
fn space_hint_now(prefs : Json?, locked : Bool) -> String {
  if locked || @sf.soft_keyboard() {
    return ""
  }
  match @settings.key_label(prefs, "composer.focus") {
    "" => ""
    key => @sf.t("web-main.composer.pressToTypeCjk", args=[("key", key)])
  }
}

///|
/// Typing starts the agent's runtime, so a cold start overlaps the writing (warm's, at the moment `at` of what was
/// typed): the first time, then a minute after it last did.
fn warm_now(src : Source, spec : NodeSpec, at : Double) -> Unit {
  if spec.session == "" || (spec.locked)() || (spec.offline)() || !(spec.warm_agent)() || src.read_only {
    return
  }
  match warmed_at.get(spec.session) {
    Some(last) if at - last < warm_every_ms => return
    _ => ()
  }
  warmed_at[spec.session] = at
  (src.call)("session.warm", { "station": Json::string(spec.station), "key": Json::string(spec.session) }, @sfbase.answer_unread)
}

///|
/// When typing last warmed each session's agent from a composer made as nodes (warm_now).
// kept across runs: emptied by composing_reset
let warmed_at : Map[String, Double] = Map([])

///|
/// What waits to go with draft `w` in its composer made as nodes, in `parent`: its quotes, each its card with the line
/// for what is said of it, then its files, each its card (a picture its tile), wrapping; each ✕ taking it out, a
/// failed one's ↻ trying it again.
fn waiting_node(parent : @view.View, src : Source, w : Writing, tips : @sf.TipLayer) -> Unit {
  parent.box(fn(col) {
    col.row(Is(false)).gap(Is(10.0)).padding(Is((0.0, 0.0, 0.0, 10.0))) |> ignore
    col.each(fn() { w.quotes.get() }, fn(q) { text(Some(q), "id") }, fn(item, q) {
      let id = text(Some(q.get()), "id")
      let comment = match composing.comments.get(id) {
        Some(f) => f
        None => {
          let f = @ui.Field::new(text=text(Some(q.untracked()), "comment"))
          composing.comments[id] = f
          f
        }
      }
      @sf.composer_quote_card_node(
        item,
        tips,
        fn() { text(Some(q.get()), "author") },
        fn() { text(Some(q.get()), "text") },
        fn() { text(Some(q.get()), "role") },
        fn(line) {
          @ui.field(
            line,
            comment,
            placeholder=@sf.t("web-main.quote.commentPlaceholder"),
            font_size=@sf.theme().t.ui,
            line=@sf.theme().t.ui_line,
            max_lines=1,
            enter_sends=true,
            edited=fn(words) { writing_comment(src, w, id, words) },
            submitted=fn(_) { w.field.focus() },
          )
          .grow(Is(1.0))
          |> ignore
        },
        fn() {
          if comment.focused() {
            w.field.focus()
          }
          writing_unquote(src, w, id)
        },
        fn() { @sf.t("web-main.quote.remove") },
      )
      |> ignore
    })
    col.box(fn(files) {
      files.row(Is(true)).wraps(Is(Some(files_lines()))).gap(Is(6.0)) |> ignore
      files.each(fn() { w.files.get() }, fn(f) { text(Some(f), "id") }, along_row=true, fn(item, f) {
        let v = fn() { Some(f.get()) }
        let id = text(Some(f.untracked()), "id")
        // a picture as its tile (the old one's composer_picture): its ✕ in its corner, going up darkened, a failed
        // one's ↻ trying it again
        let picture = fn() { waiting_picture(src, w, v()) }
        if @signals.untracked(picture) is Some(_) {
          @sf.with_corner_remove_node(item, fn() { remove_label(v(), text(v(), "name")) }, @sf.card_corner, fn(at) {
            @sf.waiting_tile_node(
              at,
              fn(p) {
                p.pick(fn() { picture().unwrap_or("") != "" }, at_once=true, fn(pv, drawn) {
                  if drawn {
                    // (as big as the tile, covering it)
                    pv
                    .width(Is(Some(@sf.waiting_tile_side)))
                    .height(Is(Some(@sf.waiting_tile_side)))
                    .image(By(fn() { Some((picture().unwrap_or(""), "", 168)) }))
                    .image_covers(Is(true))
                    |> ignore
                  } else {
                    pv.lines_up(Is(Some(@view.Along::Middle))).lies_along(Is(@view.Lies::Middle)) |> ignore
                    @sf.icon_node(pv, "file", 22.0, By(fn() { @sf.theme().p.muted })) |> ignore
                  }
                })
              },
              fn() { going_now(v()) },
              fn() { None },
              fn() { text(v(), "error") != "" },
              fn() { writing_retry(src, w, id) },
              fn() { @sf.t("common.retry") },
            )
            |> ignore
          }, fn() { writing_remove(src, w, id) })
          |> ignore
          return
        }
        @sf.file_card_node(
          item,
          tips,
          fn() { waiting_name(v()) },
          fn() { waiting_meta(v()) },
          fn() { text(v(), "error") != "" },
          fn() { text(v(), "error") != "" && field(v(), "pasted") is None },
          fn() { true },
          fn() { @sf.t("common.retry") },
          fn() { remove_label(v(), text(v(), "name")) },
          fn(on) {
            match on {
              Remove => writing_remove(src, w, id)
              Retry =>
                match waiting_as(v()) {
                  Pasted => @sfbase.writing_paste_again(src, w, id)
                  _ => writing_retry(src, w, id)
                }
              Open =>
                match waiting_as(v()) {
                  Link => open_link(text(field(v(), "link"), "url"))
                  _ => ()
                }
              Restore => ()
            }
          },
        )
        |> ignore
      })
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a file waiting's card is called (waiting_card's): a link's title (its address where it has none), pasted
/// words' first words, a station's folder going as the file its zip, else its name.
fn waiting_name(v : Json?) -> String {
  match waiting_as(v) {
    Link => {
      let l = field(v, "link")
      match text(l, "title") {
        "" => text(l, "url")
        t => t
      }
    }
    Pasted =>
      match text(field(v, "pasted"), "preview") {
        "" => @sf.t("web-main.composer.pastedText")
        first => first
      }
    AnyFile if field(field(v, "ref"), "dir") is Some(True) => text(v, "name") + ".zip"
    _ => text(v, "name")
  }
}

///|
/// What a file waiting's card says under its name (waiting_card's): why it failed; a station's file named by its path,
/// its station and that it goes so; a link, its site; pasted words, how many; else its size.
fn waiting_meta(v : Json?) -> String {
  match text(v, "error") {
    "" => ()
    e => return e
  }
  match waiting_as(v) {
    ByPath => text(field(v, "ref"), "stationName") + " · " + @sf.t("web-main.file.modePath")
    Link => text(field(v, "link"), "site")
    Pasted =>
      @sf.t("web-main.composer.pasteAttachment", args=[("count", @sf.grouped(number(field(v, "pasted"), "characters")))])
    AnyFile => {
      let done = field(v, "done")
      @sf.file_size(number(done, "size") + (if done is None { number(v, "size") } else { 0.0 }))
    }
  }
}

///|
/// Words sent into chat `r` from draft `w`'s composer made as nodes (send_in_chat's, at the press): in its list at once
/// (sent_local), their bubble flying from where they stood in the field, its list at its latest; then what the core
/// takes goes (sent_into_chat).
fn send_in_chat_node(src : Source, r : ChatRef, w : Writing) -> Unit {
  guard @signals.untracked(fn() { @sfbase.chat_view_now(src, r) }) is Some(v) else { return }
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  @ui.haptic(KeyboardTap)
  let words = w.text.get().trim(chars=" \n\t").to_owned()
  let rk = r.station + "\u{1}" + r.session
  remember_sent_pictures(src, w, r.station)
  let runs = @sfbase.refs_sent_runs(w.key, words)
  let from : @sfbase.SentFrom? = if @ui.reduced_motion() {
    None
  } else {
    Some({ words: w.field.words_at().map(fn(at) { at.0 }), quotes: [], parts: [] })
  }
  let row = sent_local(rk, Some(chat_whole(src, r, v)), words, up_files(w), going=going_files(w), quotes=sent_quotes(w), runs~, from~, now=(src.now)())
  @sfbase.chat_latest_now(src, r, v, @sf.t("web-main.chat.toLatest")) |> ignore
  sent_into_chat(src, r, v, w, rk, row)
}
