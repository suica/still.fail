// A new chat made once as nodes of the window's tree (new_chat.mbt's page, the chat's page made as nodes,
// its composer too; the chat page made's `new_node`): the same page, said by
// the tree's own mechanisms, one tree laid out by the width its frame gives it (its bindings; laid out anew at once as
// that crosses page_narrow_most, View::lays_anew): narrow, the scene in a page's list (View::scrolls_window) over all that is
// left, the foot pinned over its end a band of glass with what is wrong for now, the choices in glass capsules and the
// composer where a chat's stands at its foot (composer_node's, laid out as a chat's is there, so the chat the page
// becomes has its own where it stood); wide, a column 720 at most in the middle of the pane, the scene over the
// composer, roomy with the choices in its row, what differs by the station and its picks under it, as much room under
// it as over it so the composer stays where it is as another station is picked. Its first message sent, it becomes
// the chat in place (new_chat.mbt's new_send_go); what the page shows stays over the chat while its scene leaves,
// fading where it is, as the page leaves (chat_page_made's show, its `leave`: View::going), its composer the chat's at
// once.

///|
/// What the frame a new chat made as nodes is drawn in gives it (NewChatFrame's, a node's): the settings' core (the
/// machine's own sessions, borrowing a model), its bar over it (the Small stack's 取消 and 新对话; a pane's none), the
/// room under it (the navigation bar), whether the chat it becomes opens in its place (its first words flying as
/// Android's do) or beside it, and what the frame does as the page becomes the chat; its ground as node `n` draws it (a
/// tape's panel's, a step darker while behind the one in use); the width it is drawn at (`width`: what its frame gives
/// it, by which it is laid out); what the frame puts over the whole page (`over`: a pane's, a row of its 文件 tab
/// carried over it to let go into its message), given the page's node and whether it shows (not leaving); whether its
/// composer stands apart from the page's edges (`apart`: on the tape, in a panel of its own) and the corners of the
/// panel it stands in (`pane`: a tape's panel's, so what is in its corners is concentric with them), as a chat's
/// composer is given them (chat_composer_node's).
pub(all) struct NewChatNodeFrame {
  core : Core
  ground : (@view.View) -> Int64
  width : () -> Double
  apart : () -> Bool
  pane : () -> FixedArray[@ui.CornerOf]?
  bar : (@view.View) -> Unit
  over : (@view.View, () -> Bool) -> Unit
  foot : () -> Double
  in_place : Bool
  sent : (ChatRef) -> Unit
}

///|
/// What a new chat's page is as nodes: on a station (or while its stations are read, as it will be), nothing to run a
/// chat with yet there, no station at all, none of them up.
#derive(Eq)
priv enum NewKind {
  On
  Blocked
  AutoEmpty
  First
  NoneUp
}

///|
/// The new chat of workspace `w` made as nodes in `v` (new_chat_page's: chat_page_made's `new_node`, a node of a show
/// that leaves over new_leave_ms), leaving as it becomes its chat, its scene leaving over it (what it shows then is as
/// it was sent: the view it showed, fresh.scene; nothing of it pressed: View::leaving). Its tips in `tips`.
pub fn new_chat_node(v : @view.View, src : Source, w : Workspace, frame : NewChatNodeFrame, tips : @sf.TipLayer) -> Unit {
  // (told as it starts leaving, as what reads it there is at rest (View::leaving): its composer's pick let go of then)
  let left = @signals.signal(false)
  v.on_leaving(fn() { left.set(true) }) |> ignore
  v.reacts(fn() { v.leaving() }, at_start=false, fn(l) {
    if !l {
      left.set(false)
    }
  })
  let going = fn() { v.leaving() || left.get() }
  // (made anew after its leaving finished because newChat.create failed: arm the reversing choreography on this node)
  if @sfbase.fresh_back.val {
    @sfbase.fresh_choreo.val.arm(v)
  }
  // the chat's keys here as on a chat's page (chat_page_node's): composer.focus the cursor in its composer, the page
  // brought over first where the tape has it behind
  let draft = new_chat_drafts + w.id
  let wr = @signals.untracked(fn() { @sfbase.writing(src, draft) })
  v.key_context("Chat")
  .on_action("composer.focus", fn(e) {
    (@sfbase.page_for_key.val)(e.at)
    wr.field.focus()
    composer_take_focus(drafts=new_chat_drafts)
    @sfbase.draft_given(draft)
    true
  })
  |> ignore
  let topic = fn() { src.topic("newChat", new_chat_asked(w.id)).get() }
  // (as it was sent while it leaves: what the core says of it since is the chat's)
  let view = fn() {
    if going() {
      @sfbase.fresh.scene.get()
    } else {
      topic().value
    }
  }
  // (what is picked now: a chat made with other picks, nothing sent to it, let go)
  v.reacts(fn() { if going() { None } else { topic().value } }, fn(now) {
    if field(now, "station") is Some(Object(_)) && field(now, "stations") is Some(Array(_)) {
      @sfbase.fresh_picked(now)
    }
  })
  let kind = fn() {
    let now = view()
    match field(now, "stations") {
      Some(Array(_)) =>
        match field(now, "station") {
          Some(Object(_)) => if text(now, "blocked") != "" { Blocked } else { On }
          _ => if text(now, "blocked") == "auto_empty" { AutoEmpty } else if flag(now, "any") { NoneUp } else { First }
        }
      // (its stations not read yet: the page as it will be on the station it last started on)
      _ => On
    }
  }
  // (its ground none as it leaves: what is left of it seen over the chat it became, as new_chat_left's)
  v.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))).ground(By(fn() { if going() { 0L } else { (frame.ground)(v) } })) |> ignore
  // (its bar fades out smoothly along bar_out while non-interactive, crossfading with the chat bar's bar_in)
  v.box(fn(b) {
    b
    .alpha(By(fn() { 1.0 - @sfbase.fresh_progress(b, "bar_out") }))
    .points(By(fn() { !going() }))
    |> ignore
    (frame.bar)(b)
  })
  |> ignore
  v.box(fn(room) {
    room.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    room.pick(kind, at_once=true, fn(p, k) {
      p.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      match k {
        On => new_on_node(p, v, src, w, frame, tips, topic, view, going)
        Blocked => new_blocked_node(p, src, w, frame, tips, view)
        AutoEmpty => new_auto_empty_node(p, src, w, frame, view)
        First =>
          new_alone_node(p, "illus_no_station", fn() { @sf.t("android-settings.station.first") }, fn() {
            @sf.t("android-settings.station.firstNote")
          })
        NoneUp =>
          new_alone_node(p, "illus_station_offline", fn() { @sf.t("android-chat.new.offline.title") }, fn() {
            @sf.t("android-chat.new.offline.text", args=[("app", @sf.product())])
          })
      }
    })
  })
  |> ignore
  // (the navigation bar's room under it)
  v.box(fn(f) { f.height(By(fn() { Some((frame.foot)()) })) |> ignore }) |> ignore
  // (what the frame has over it, while it is not leaving)
  (frame.over)(v, fn() { !going() })
}

///|
/// The page on a station (new_on's), laid out by its width: its station, what is picked and why its stations could not
/// be read, as `view` and `topic` say them now.
fn new_on_node(
  v : @view.View,
  page : @view.View,
  src : Source,
  w : Workspace,
  frame : NewChatNodeFrame,
  tips : @sf.TipLayer,
  topic : () -> @sfbase.TopicState,
  view : () -> Json?,
  going : () -> Bool,
) -> Unit {
  // (its stations not read yet: why they could not be ("" while they are read))
  let held = fn() { !(field(view(), "stations") is Some(Array(_))) }
  let error = fn() {
    match text(view(), "error") {
      "" =>
        match topic().error {
          Some(e) => text(Some(e), "message")
          None => ""
        }
      e => e
    }
  }
  let station = fn() { if held() { None } else { field(view(), "station") } }
  let on : NewOn = { page, src, w, frame, tips, view, held, error, station, going }
  new_on_tree(v, on)
}

///|
/// The page on a station as one tree whatever its width (new_narrow's and new_wide's), so its composer, its field and
/// what is typed in it stay one node as the page is laid out the other way (a window made narrower or wider past
/// page_narrow_most): how it is laid out bound to `wide` (the width its frame gives it, page_narrow_most or more), never a
/// structure switched by it but for what each way alone shows (the choices in glass over the composer, or in its row;
/// what differs by the station in the scene, or under the composer).
/// - Narrow: the scene at the top, scrolled where it does not fit; at the foot a band of glass, as far over the choices
///   as a chat's composer is from the page's foot, with what is wrong for now and the choices over the composer, which
///   stands where a chat's does (so the chat the page becomes has its own where it stood).
/// - Wide: a column 720 at most, 32 in from the pane's sides, the scene over the composer (roomy, its choices in its
///   row) in its middle, as much room under it as over it, what differs by the station from the composer's foot down
///   (what is wrong for now, what it waits for or why its stations could not be read, the machine's own sessions): what
///   comes and goes there moves nothing in the middle.
/// As it becomes its chat, the scene leaves where it is, what is under the composer sooner, the band, the choices and
/// the composer at once (the chat's composer is where it was).
fn new_on_tree(v : @view.View, on : NewOn) -> Unit {
  // (laid out wide where its width is the narrow page's most or more, as new_on: @sf.page_narrow_most)
  let wide = fn() { (on.frame.width)() >= @sf.page_narrow_most }
  // (wide, a column new_column_w at most in its middle, new_column_in at least from its sides: as wide as it is laid
  // out, never a width worked out of the frame's, so it goes with the page as that goes another width)
  // (laid out anew at the width its frame says, at once, as that comes to cross page_narrow_most: narrow or wide as it
  // comes to be, never on a way between the two (View::lays_anew), what holds it going its own way meanwhile)
  v
  .grow(Is(1.0))
  .shrink(Is(1.0))
  .basis(Is(Some(0.0)))
  .min_height(Is(Some(0.0)))
  .lines_up(Is(Some(Middle)))
  .padding(By(fn() { if wide() { (new_column_in, 0.0, new_column_in, 0.0) } else { (0.0, 0.0, 0.0, 0.0) } }))
  .lays_anew(By(fn() { (on.frame.width)() }))
  .points(Is(true))
  |> ignore
  // (what is let go on the page beside its composer, as the old page's room took it (new_chat.mbt's `new/room`): words
  // dragged in from another app into its field at its caret, as a paste's; files from this machine's Finder by their
  // station and path where it is a station of this workspace, else read and put in as files picked are; none while it
  // takes no words, sending or with no station to start on)
  let draft = new_chat_drafts + on.w.id
  let w_draft = @signals.untracked(fn() { @sfbase.writing(on.src, draft) })
  let composes = fn() { !(on.going)() && !((on.held)() && on.address() == "") }
  @ui.paths_into(
    v,
    w_draft.field,
    fn(paths) {
      if @signals.untracked(composes) {
        @sfbase.files_into_many(draft, @sfbase.finder_dragged(on.src, paths))
      }
    },
    takes=fn() { @signals.untracked(composes) && @sfbase.finder_by_station_in(on.w.id) },
  )
  |> @ui.files_into(w_draft.field, fn(files) {
    if @signals.untracked(composes) {
      @sfbase.picked_files_into(draft, files)
    }
  })
  |> @ui.words_into(w_draft.field)
  |> ignore
  v.box(fn(col) {
    col
    .width_share(Is(1.0))
    .max_width(By(fn() { if wide() { Some(new_column_w) } else { None } }))
    .lines_up(By(fn() { if wide() { Some(Middle) } else { None } }))
    .gap(By(fn() { if wide() { @ui.Space::px(S2_5) } else { 0.0 } }))
    .grow(Is(1.0))
    .shrink(Is(1.0))
    .basis(Is(Some(0.0)))
    .min_height(Is(Some(0.0)))
    |> ignore
    // (wide, as much room over the scene and the composer as under them; narrow, none: the scene takes it all)
    col.box(fn(over) {
      over.grow(By(fn() { if wide() { 1.0 } else { 0.0 } })).basis(Is(Some(0.0))) |> ignore
    })
    |> ignore
    // (narrow, all that is left over the band, the scene scrolled where it does not fit; wide, as tall as the scene)
    col.box(fn(top) {
      top
      .grow(By(fn() { if wide() { 0.0 } else { 1.0 } }))
      .basis(By(fn() { if wide() { None } else { Some(0.0) } }))
      .min_height(Is(Some(0.0)))
      |> ignore
      top.scrolls(@view.Scroll::list(), fn(s) {
        s
        .min_height(Is(Some(0.0)))
        .lines_up(Is(Some(Middle)))
        .lies_along(By(fn() { if wide() { End } else { Start } }))
        .alpha(By(fn() { 1.0 - @sfbase.fresh_progress(s, "scene_out") }))
        .offset(By(fn() { (0.0, -10.0 * @sfbase.fresh_progress(s, "scene_out")) }))
        |> ignore
        new_scene_node(s, on, wide)
      })
      |> ignore
    })
    |> ignore
    // (the band at the foot narrow; wide, the composer alone)
    col.by_room(fn(band, room) {
      band
      // Transparent bottom safe area (eliminates glass-on-glass stacking behind the liquid glass composer & capsules)
      .lines_up(Is(Some(Middle)))
      .padding(By(fn() { (0.0, if wide() { 0.0 } else { composer_foot_at(room.width()) }, 0.0, 0.0) }))
      |> ignore
      let width = fn() { composer_width(room.width()) }
      // (narrow alone: there at once as the page is laid out another way, no way in or out, #5767)
      band.show(fn() { !wide() }, at_once=true, fn(o) {
        @sf.style_node(o, fn() { new_over })
        o
        .lines_up(Is(Some(Middle)))
        .alpha(By(fn() { 1.0 - @sfbase.fresh_progress(o, "choices_out") }))
        .offset(By(fn() {
          let p = @sfbase.fresh_progress(o, "choices_out")
          let dy = if (on.going)() { -@sfbase.fresh_over_held.get() - 4.0 * p } else { 0.0 }
          (0.0, dy)
        }))
        |> ignore
        new_notices_node(o, on, width)
      })
      band.box(fn(c) {
        c.width(By(fn() { Some(room.width()) })) |> ignore
        new_composer_place_node(c, on, wide)
      })
      |> ignore
    })
    |> ignore
    // (wide, under the composer, as much room as over it, more where what is there needs it)
    col.box(fn(under) {
      under
      .grow(By(fn() { if wide() { 1.0 } else { 0.0 } }))
      .basis(Is(Some(0.0)))
      .gap(Is(@ui.Space::px(S2_5)))
      .lines_up(Is(Some(Middle)))
      .alpha(By(fn() { 1.0 - @sfbase.fresh_progress(under, "under_out") }))
      .offset(By(fn() { (0.0, 6.0 * @sfbase.fresh_progress(under, "under_out")) }))
      |> ignore
      under.by_room(fn(held, room) {
        held.lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S2_5))) |> ignore
        // (wide alone: there at once as the page is laid out another way, no way in or out, #5767; what is in it comes and
        // goes by what the core says as ever; its notices as wide as the column is laid out, `room`)
        held.show(wide, at_once=true, fn(wd) {
          wd.lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S2_5))) |> ignore
          wd.show(fn() { !(on.held)() }, at_once=true, fn(n) {
            n.lines_up(Is(Some(Middle))) |> ignore
            new_notices_node(n, on, fn() { room.width() })
          })
          wd.pick(fn() { if (on.held)() { if (on.error)() != "" { 2 } else { 1 } } else { 0 } }, at_once=true, fn(w, k) {
            w.lines_up(Is(Some(Middle))).gap(Is(@ui.Space::px(S2_5))) |> ignore
            match k {
              2 => @sf.words_node(w, on.error, fn() { new_error }).words_centered(Is(true)) |> ignore
              1 => @sf.wait_line_node(w, fn() { @sf.t("common.readingStations") }) |> ignore
              _ => {
                // what it waits for, in a line of its own under the composer
                w.show(fn() { text((on.view)(), "problem") != "" }, fn(p) {
                  @sf.words_node(p, fn() { text((on.view)(), "problem") }, fn() { new_status }).words_centered(Is(true))
                  |> ignore
                })
                new_offer_node(w, on, new_offer_under)
              }
            }
          })
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The scene (new_scene_narrow_body's and new_head's), laid out narrow or wide as `wide` says: the picture, what to do,
/// where; narrow, under them what keeps it from starting (or why its stations could not be read) and the machine's own
/// sessions to go on with (wide, those are under the composer).
fn new_scene_node(s : @view.View, on : NewOn, wide : () -> Bool) -> Unit {
  s.box(fn(c) {
    c
    .padding(
      By(fn() {
        if wide() {
          (0.0, 0.0, 0.0, 0.0)
        } else {
          (@ui.Space::px(S8), @ui.Space::px(S8), @ui.Space::px(S8), @ui.Space::px(S2_5))
        }
      }),
    )
    .gap(By(fn() { if wide() { @ui.Space::px(S2_5) } else { @ui.Space::px(S1_5) } }))
    .lines_up(Is(Some(Middle)))
    |> ignore
    new_head_node(c, on, wide)
    let problem = fn() {
      if (on.held)() {
        (on.error)()
      } else {
        text((on.view)(), "problem")
      }
    }
    // (narrow alone: there at once as the page is laid out another way, #5767; what is in it by what the core says)
    c.show(fn() { !wide() }, at_once=true, fn(nw) {
      nw.lines_up(Is(Some(Middle))) |> ignore
      nw.show(fn() { problem() != "" }, fn(b) {
        @sf.style_node(b, fn() { new_problem_box })
        @sf.words_node(b, problem, fn() { if (on.held)() { new_error } else { new_status } }).words_centered(Is(true)) |> ignore
      })
      new_offer_node(nw, on, new_offer_box)
    })
  })
  |> ignore
}

///|
/// What the page on a station reads (new_on_node's), handed to its parts.
priv struct NewOn {
  page : @view.View
  src : Source
  w : Workspace
  frame : NewChatNodeFrame
  tips : @sf.TipLayer
  view : () -> Json?
  held : () -> Bool
  error : () -> String
  station : () -> Json?
  going : () -> Bool
}

///|
/// The station a new chat is on (new_address's): the one picked; while its stations are read, the one it last started
/// on (the core's `kept`) ("" none).
fn NewOn::address(self : NewOn) -> String {
  if (self.held)() {
    match text((self.view)(), "kept") {
      "" => ""
      kept => self.w.id + "/" + kept
    }
  } else {
    text((self.station)(), "station")
  }
}

///|
/// The choices (new_choosers'): where it runs, what it runs on, what it is for, each a capsule of glass over the
/// composer (`floating`) or in its row; while its stations are read, both breathing in their places as high as they
/// will be (still once what they wait on failed). Made again as the station or what can be picked on it changes.
fn new_choosers_node(row : @view.View, on : NewOn, floating : Bool) -> Unit {
  let key = fn() {
    let v = (on.view)()
    (
      (on.held)(),
      on.address(),
      flag(v, "waiting"),
      field(v, "pick") is None || text(v, "runtime") == "" || field(v, "model") is None,
      text((on.station)(), "name") != "",
    )
  }
  row.pick(key, at_once=true, fn(r, k) {
    let (held, address, waiting, none, named) = k
    if floating {
      @sf.style_node(r, fn() { new_choosers_row })
    } else {
      r.row(Is(true)).gap(Is(@ui.Space::px(S1))).lines_up(Is(Some(Middle))) |> ignore
    }
    // (short of room, what each choice may leave out leaves first, in the order they say (new_drop_station_name,
    // preset_drop_words, the model's parts): View::fits)
    r.min_width(Is(Some(0.0))).fits(Is(true)) |> ignore
    if held {
      // (a made-up station's and model's, in their bones)
      @sf.waiting_node(r, fn(b) {
        b.row(Is(true)).gap(Is(@ui.Space::px(S1_5))).lines_up(Is(Some(Middle))) |> ignore
        new_station_control_node(b, on, fn() { Some(new_sample_station()) }, fn() { Some(new_sample_view()) }, floating)
        model_triple_node(b, @sfbase.sample_source, "sample", "new", face=fn() { field(Some(new_sample_view()), "pick") }, small=true, floating~)
      }, error=on.error, note=fn() { { reading: (on.error)() == "", text: "", failing: [] } })
      return
    }
    new_preset_control_node(r, on, address, floating)
    if named {
      new_station_control_node(r, on, on.station, on.view, floating)
    }
    if waiting {
      // (its profiles read: a made-up model's, in its bones, as narrow as the row leaves it: what it drops to fit dropped)
      @sf.waiting_node(
        r,
        fn(b) {
          model_triple_node(b, @sfbase.sample_source, "sample", "new", face=fn() { field(Some(new_sample_view()), "pick") }, small=true, floating~)
        },
        fits=true,
      )
    } else if none {
      // nothing to run it with: the way to where models are enabled
      new_capsule_node(r, fn() { @sf.t("web-main.newChat.noModels") }, floating, fn() { false }, fn(_) {
        if !(on.going)() {
          open_page(Place("profiles"))
        }
      }, fn(b) { @sf.words_node(b, fn() { @sf.t("web-main.newChat.noModels") }, fn() { new_capsule_words }) |> ignore })
    } else {
      // (asked from elsewhere, opened here: its control opens it as it is first placed, model_triple_node's `ask_open`)
      let ask_open = take_asked("model")
      // (its face, as the page has it: its panel asked as the hand comes to it, opened whole once answered; a preset
      // that names its model: shown as the preset's, not opened)
      model_triple_node(
        r,
        on.src,
        address,
        "new",
        face=fn() { field((on.view)(), "pick") },
        small=true,
        floating~,
        ask_open~,
        bound=fn() { flag((on.view)(), "presetModel") },
        on_bound=fn(from) {
          if !(on.going)() {
            let v = @signals.untracked(on.view)
            preset_fixed_menu(on.src, on.w, address, v, @sf.t("web-main.preset.fixedModel", args=[("name", @sf.title_accented(text(v, "presetName")))]), from)
          }
        },
      )
    }
  })
}

///|
/// A control of the page's (new_capsule's) in `parent`: over the composer a capsule of its glass (`floating`), in its
/// row as the composer's other controls; read out a button named `label()`, `press` given it as it is pressed; what it
/// holds `body`. `marked()`: it starts with a mark of a corner of its own, as far in from the glass's start as from its
/// top and foot.
fn new_capsule_node(
  parent : @view.View,
  label : () -> String,
  floating : Bool,
  marked : () -> Bool,
  press : (@view.View) -> Unit,
  body : (@view.View) -> Unit,
) -> Unit {
  let made : Ref[@view.View?] = Ref(None)
  @sf.ripple_button_node(parent, label, fn() { if made.val is Some(b) { press(b) } }, fn(b, state) {
    made.val = Some(b)
    if floating {
      @sf.style_node(b, fn() { if marked() { glass_chooser_marked_box } else { glass_chooser_box } }, in_row=true)
      @sf.glass_capsule_node(b, interactive=true) |> ignore
    } else {
      @sf.style_node(b, fn() { new_capsule_in_row }, in_row=true)
      @sf.hover_ground_node(b, lit=Some(fn() { state.hovered() || state.pressed() || state.focus_shown() }))
    }
    // (as wide as what it holds needs, never cut by its row: what is beside it gives way, the model's control leaving
    // out its parts in what is left (model_triple_node's); short of room, what of it may leave leaves, in the order the
    // row says (View::drops), it as wide as what it keeps of them (View::fits))
    b.shrink(Is(0.0)).fits(Is(true)) |> ignore
    body(b)
    Is(if floating { glass_chooser_corner } else { @ui.Space::px(S2) })
  })
  |> ignore
}

///|
/// Where it runs (new_station_control's): its mark, its name (left out after what the model's control leaves out), a
/// chevron; pressed, the workspace's stations through the presenters (station_rows_node), or where a preset holds it,
/// said so with the ways to change it.
fn new_station_control_node(
  parent : @view.View,
  on : NewOn,
  station : () -> Json?,
  view : () -> Json?,
  floating : Bool,
) -> Unit {
  // (a preset that names the stations: only those offered, none to pick where it names the one it is on)
  let fixed = fn() { flag(view(), "presetStations") && items(view(), "stations").length() <= 1 }
  let open = fn(b : @view.View) {
    let v = @signals.untracked(view)
    @sf.panel_nodes(@sf.t("android-chat.new.station.pick"), fn(n, close) { station_rows_node(n, on.src, on.w, v, close) }, from=Node(b), side=choice_side(Node(b)))
  }
  let auto_on = fn() { flag(view(), "autoStation") }
  let label = fn() {
    if auto_on() {
      @sf.t("web-main.newChat.autoStationShort")
    } else {
      text(station(), "name")
    }
  }
  let made : Ref[@view.View?] = Ref(None)
  new_capsule_node(parent, label, floating, fn() { false }, fn(b) {
    if (on.going)() || b.in_bones() {
      ()
    } else if @signals.untracked(fixed) {
      let v = @signals.untracked(view)
      preset_fixed_menu(on.src, on.w, text(field(v, "station"), "station"), v, @sf.t("web-main.preset.fixedStation", args=[("name", @sf.title_accented(text(v, "presetName")))]), Node(b))
    } else {
      open(b)
    }
  }, fn(b) {
    made.val = Some(b)
    // (a station of no mark of its own the server's, as in its pick: never a bare chevron)
    b.pick(fn() { if auto_on() { 2 } else if @sf.has_station_mark(text(station(), "emoji"), text(station(), "icon")) { 1 } else { 0 } }, fn(m, kind) {
      if kind == 2 {
        @sf.icon_node(m, "sparks", new_mark, By(fn() { @sf.theme().p.accent_text })) |> ignore
      } else if kind == 1 {
        @sf.station_mark_node(m, fn() { text(station(), "emoji") }, fn() { text(station(), "icon") }, new_mark, fn() {
          @sf.theme().p.text
        }, fn() { 0 })
      } else {
        @sf.icon_node(m, "server", new_mark, By(fn() { @sf.theme().p.text })) |> ignore
      }
    })
    // (its name left out after what the model's control leaves out, its mark kept: the page says where it starts)
    b.box(fn(n) {
      // (cut short past 128: new_station_name)
      @sf.style_node(n, fn() { new_station_name }, in_row=true)
      n.row(Is(true)).min_width(Is(Some(0.0))).drops(Is(new_drop_station_name)) |> ignore
      @sf.words_node(n, label, fn() { new_capsule_words }).cuts(Is(true)).min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
    b.show(fn() { !fixed() }, fn(c) { @sf.icon_node(c, "chevron-down", new_chevron, By(fn() { @sf.theme().p.muted })) |> ignore })
  })
  // (asked from elsewhere: opened as it is seen, or as it is asked while it is)
  if !parent.in_bones() {
    parent.reacts(fn() { new_chat_asked_seq.get() }, fn(_) {
      if !@signals.untracked(fixed) && take_asked("station") {
        @ui.after_frame(fn() {
          match made.val {
            Some(b) if b.alive() => open(b)
            _ => ()
          }
        })
      }
    })
  }
}

///|
/// What a new chat is opened with (new_preset_control's, presets.mbt): its folders' marks (or a mark of what it adds),
/// the preset's name (预设 while none is picked), a chevron; pressed, the menu of the station's presets.
fn new_preset_control_node(parent : @view.View, on : NewOn, address : String, floating : Bool) -> Unit {
  guard address != "" && !parent.in_bones() else { return }
  let v = on.view
  let name = fn() { if text(v(), "preset") == "" { "" } else { text(v(), "presetName") } }
  let label = fn() { if name() == "" { @sf.t("web-main.preset.label") } else { name() } }
  let marks = fn() { items(v(), "presetMarks") }
  let made : Ref[@view.View?] = Ref(None)
  let open = fn(b : @view.View) { preset_menu_open(on.src, on.w, address, @signals.untracked(v), Node(b)) }
  new_capsule_node(parent, label, floating, fn() { name() != "" && marks().length() > 0 }, fn(b) {
    if !(on.going)() {
      open(b)
    }
  }, fn(b) {
    made.val = Some(b)
    // (picked: its folders' marks, as they are shown where they are picked; none: a quiet mark of what it adds)
    b.pick(fn() { if name() == "" { 0 } else if marks().length() > 0 { 2 } else { 1 } }, fn(m, k) {
      match k {
        2 => {
          @sf.style_node(m, fn() { preset_marks_row }, in_row=true)
          m.each(marks, fn(x) { text(Some(x), "name") + "\u{1}" + text(Some(x), "repo") }, fn(t, x) {
            let x = fn() { Some(x.get()) }
            @sf.tile_avatar_node(t, fn() { if text(x(), "repo") != "" { text(x(), "repo") } else { text(x(), "name") } }, fn() {
              text(x(), "name")
            }, fn() { text(x(), "icon") }, new_mark, corner=@sf.small_corner)
          })
        }
        1 => @sf.icon_node(m, "sparks", new_mark, By(fn() { @sf.theme().p.accent_text })) |> ignore
        _ => @sf.icon_node(m, "folder-plus", new_mark, By(fn() { @sf.theme().p.muted })) |> ignore
      }
    })
    // (its name cut short past 128: new_station_name; short of room, left out with the model's first parts, then its
    // chevron after the station's name: preset_drop_words, preset_drop_chevron)
    b.box(fn(n) {
      @sf.style_node(n, fn() { new_station_name }, in_row=true)
      n.row(Is(true)).min_width(Is(Some(0.0))).drops(Is(preset_drop_words)) |> ignore
      @sf.words_node(n, label, fn() { if name() == "" { preset_capsule_quiet } else { new_capsule_words } })
      .cuts(Is(true))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
    b.box(fn(c) {
      c.drops(Is(preset_drop_chevron)) |> ignore
      @sf.icon_node(c, "chevron-down", new_chevron, By(fn() { @sf.theme().p.muted })) |> ignore
    })
    |> ignore
  })
  // (asked from elsewhere: a fixture's screen of what the control opens, once the frame is drawn; or as it is asked
  // while it is)
  let w = on.w
  parent.reacts(fn() { new_chat_asked_seq.get() }, fn(_) {
    let stations = items(@signals.untracked(v), "stations")
    let first = text(items(@signals.untracked(v), "presets").get(0), "id")
    for ask in [
      ("preset-new", "", ""),
      ("preset-edit", first, ""),
      ("preset-add", first, "add"),
      ("preset-new-add", "", "add"),
      ("preset-new-browse", "", "browse"),
      ("preset-new-clone", "", "clone"),
      ("preset-new-browse-repos", "", "browse:/Users/lin/项目"),
    ] {
      if take_asked(ask.0) {
        @ui.after_frame(fn() { preset_dialog(on.src, w, address, ask.1, stations, then=ask.2) })
      }
    }
    if take_asked("preset-new-clones") {
      @ui.after_frame(fn() {
        preset_dialog(on.src, w, address, "", stations, clones=[
          { station: address, id: "c-web", repo: "github.com/acme/shop", name: "shop" },
          { station: address, id: "c-bad", repo: "github.com/acme/private", name: "private" },
        ])
      })
    }
    for ask in ["preset", "preset-others"] {
      if take_asked(ask) {
        @ui.after_frame(fn() {
          match made.val {
            Some(b) if b.alive() =>
              if ask == "preset" {
                open(b)
              } else {
                preset_others_open(on.src, w, @signals.untracked(v), Node(b))
              }
            _ => ()
          }
        })
      }
    }
  })
}

///|
/// The page's composer (new_composer_place's) in `c`: the workspace's new chat's draft, sent to the station it is on
/// (made again as another is picked); roomy wide, the choices in its row; locked while nothing can run it, never while
/// its stations are read (then it sends to the one it last started on) unless they could not be. Gone at once as the
/// page becomes its chat: the chat's composer is where it was. Held on no station (none started on yet, the stations'
/// first value not come): its room as it will be, nothing of it shown or in use.
fn new_composer_place_node(c : @view.View, on : NewOn, roomy : () -> Bool) -> Unit {
  let away = fn() { (on.going)() || ((on.held)() && on.address() == "") }
  // (narrow, its choices in glass over it, at its foot with it: drawn with its top as it opens; wrap in a child box so
  // we never clobber composer_node's over_drawn offset on `r`, while holding pre-send multi-line height via
  // fresh_over_held and fading out smoothly along choices_out; the same as the page leaves, its composer gone)
  let over_choices = fn(r : @view.View) {
    r.box(fn(inner) {
      inner
      .alpha(By(fn() { 1.0 - @sfbase.fresh_progress(inner, "choices_out") }))
      .offset(By(fn() {
        let p = @sfbase.fresh_progress(inner, "choices_out")
        let dy = if (on.going)() { -@sfbase.fresh_over_held.get() - 4.0 * p } else { 0.0 }
        (0.0, dy)
      }))
      |> ignore
      new_choosers_node(inner, on, true)
    })
    |> ignore
  }
  // (gone as the page leaves (sent: it becomes its chat): its draft's composer let go of in that frame, what it read
  // with it; its room kept as tall as it was laid out, so that nothing under it moves as it goes, its choices fading
  // out in it along choices_out, as they were over it)
  c.pick(fn() { if (on.going)() { None } else { Some(on.address()) } }, at_once=true, fn(p, addr) {
    guard addr is Some(address) else {
      let (_, _, _, h) = c.placed_window_now()
      p.height(Is(Some(h))).lines_up(Is(Some(Middle))) |> ignore
      if !@signals.untracked(roomy) {
        p.by_room(fn(host, room) {
          host.width(By(fn() { Some(composer_width(room.width())) })) |> ignore
          over_choices(host)
        })
        |> ignore
      }
      return
    }
    p.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    let name = fn() { text((on.station)(), "name") }
    new_composer_node(
      p,
      on.src,
      fn() { address },
      {
        draft: "new:" + on.w.id,
        // (nothing said while it is away: its room alone)
        placeholder: fn() { if away() { "" } else { @sf.t("web-main.newChat.placeholder") } },
        roomy,
        toolbar: Some(fn(t) { t.show(fn() { !(on.held)() }, fn(r) { new_choosers_node(r, on, false) }) }),
        locked: fn() {
          if (on.held)() {
            address == "" || (on.error)() != ""
          } else {
            let v = (on.view)()
            !flag(v, "waiting") && (text(v, "runtime") == "" || field(v, "model") is None)
          }
        },
        send: fn(d) { new_send_node(on, address, name(), d) },
        starting: fn() { @sfbase.fresh.starting.get() },
        // (narrow, its choices over it: over_choices)
        over_it: Some(over_choices),
        over_tall: @sf.glass_chooser_h.points().unwrap_or(0.0) + @ui.Space::px(S1_5),
        away,
      },
      shows=fn() { !(on.going)() },
      tips=on.tips,
      apart=on.frame.apart,
      pane=on.frame.pane,
      // (at the band's foot, the choices' own room over it: new_choosers_row's)
      over=0.0,
    )
  })
}

///|
/// What is wrong for now (new_notices'), `width()` wide: what is sent waits for its quota; its station went as it was
/// written in.
fn new_notices_node(n : @view.View, on : NewOn, width : () -> Double) -> Unit {
  let line = fn(shown : () -> Bool, words : () -> String) {
    n.show(shown, fn(b) {
      @sf.style_node(b, fn() { new_notice_box })
      b.width(By(fn() { Some(width()) })) |> ignore
      @sf.words_node(b, words, fn() { new_notice_words }) |> ignore
    })
  }
  line(fn() { text((on.view)(), "spent") != "" }, fn() { text((on.view)(), "spent") })
  line(fn() { flag((on.view)(), "down") }, fn() {
    @sf.t("web-main.newChat.down", args=[("name", new_station_words((on.station)()))])
  })
}

///|
/// The machine's own sessions to go on with (new_offer's), in a box of `style`: nothing while its stations are read, nor
/// read only.
fn new_offer_node(c : @view.View, on : NewOn, style : @ui.Style) -> Unit {
  c.show(fn() { !(on.held)() && field((on.station)(), "overview") is Some(Object(_)) && !on.src.read_only }, at_once=true, fn(o) {
    @sf.style_node(o, fn() { style })
    @settings.machine_sessions_offer_node(o, on.frame.core, fn() { text((on.station)(), "station") }, fn() {
      text((on.station)(), "name")
    })
  })
}

///|
/// The page's head (new_head's): the picture (as wide as `wide` says), what to do, where it starts (while its stations are read,
/// a made-up one in its bones, still once what they wait on failed).
fn new_head_node(c : @view.View, on : NewOn, wide : () -> Bool) -> Unit {
  // (320 wide, 230 narrow: the same picture, its size bound to how the page is laid out)
  c.pick(fn() { @sf.theme().dark }, at_once=true, fn(a, dark) {
    let name = if dark { "illus_new_chat_dark" } else { "illus_new_chat" }
    let w_now = fn() {
      if wide() {
        new_scene_w
      } else {
        new_scene_narrow_w
      }
    }
    // (its width and height bound to how the page is laid out, over the size it is made at)
    @sf.drawable_node(a, name, new_scene_narrow_w)
    .width(By(fn() { Some(w_now()) }))
    .height(By(fn() { Some(@sf.drawable_height(name, w_now())) }))
    |> ignore
  })
  c.box(fn(h) {
    @sf.style_node(h, fn() { new_heading_box })
    @sf.words_node(h, fn() { @sf.t("android-chat.new.heading") }, fn() { new_title }).words_centered(Is(true)) |> ignore
  })
  |> ignore
  c.box(fn(s) {
    @sf.style_node(s, fn() { new_sub_box })
    s.pick(on.held, at_once=true, fn(b, held) {
      b.min_width(Is(Some(0.0))) |> ignore
      if held {
        @sf.waiting_node(b, fn(x) {
          @sf.words_node(x, fn() { @sf.t("android-chat.new.sub", args=[("station", @sf.sample_words(4))]) }, fn() { new_sub })
          .words_centered(Is(true))
          |> ignore
        }, error=on.error, note=fn() { { reading: (on.error)() == "", text: "", failing: [] } })
      } else {
        @sf.words_node(b, fn() { @sf.t("android-chat.new.sub", args=[("station", new_station_words((on.station)()))]) }, fn() {
          new_sub
        })
        .words_centered(Is(true))
        |> ignore
      }
    })
  })
  |> ignore
}

///|
/// A page of a picture (`art`, its dark one `art` + "_dark"), a title and what it means, in the middle of the page
/// (new_alone's).
fn new_alone_node(v : @view.View, art : String, title : () -> String, note : () -> String) -> Unit {
  v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
  v.box(fn(b) {
    @sf.style_node(b, fn() { new_alone_box })
    b.pick(fn() { @sf.theme().dark }, fn(a, dark) { @sf.drawable_node(a, if dark { art + "_dark" } else { art }, new_scene_narrow_w) |> ignore })
    @sf.words_node(b, title, fn() { new_alone_title }).words_centered(Is(true)) |> ignore
    @sf.words_node(b, note, fn() { new_sub }).words_centered(Is(true)) |> ignore
  })
  |> ignore
}

///|
/// Automatic assignment is active, but no online station is in the allowlist: offer picking a station manually or
/// opening Station settings (never silently fall back to a non-allowlisted station).
fn new_auto_empty_node(
  v : @view.View,
  src : Source,
  w : Workspace,
  frame : NewChatNodeFrame,
  view : () -> Json?,
) -> Unit {
  v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
  v.box(fn(o) {
    o.width(By(fn() { Some(@sf.dmin(new_column_w, (frame.width)() - 2.0 * new_column_in)) })) |> ignore
    @sf.first_one_node(
      o,
      fn() { @sf.t("web-main.newChat.autoEmptyTitle") },
      lead=fn() { text(view(), "problem") },
      art=fn(a) {
        a.pick(fn() { @sf.theme().dark }, fn(x, dark) {
          @sf.drawable_node(x, if dark { "illus_station_offline_dark" } else { "illus_station_offline" }, new_scene_narrow_w) |> ignore
        })
      },
      fn(acts) {
        let pick_btn : Ref[@view.View?] = Ref(None)
        acts.show(fn() { items(view(), "stations").length() > 0 }, fn(s) {
          pick_btn.val = Some(s)
          @sf.button_node(s, fn() { @sf.t("web-main.newChat.pickStation") }, fn() {
            let v = @signals.untracked(view)
            let anchor = match pick_btn.val {
              Some(b) if b.alive() => @sf.Anchor::Node(b)
              _ => @sf.Anchor::Unanchored
            }
            @sf.panel_nodes(@sf.t("android-chat.new.station.pick"), fn(n, close) { station_rows_node(n, src, w, v, close) }, from=anchor)
          }, tone=Primary)
          |> ignore
        })
        @sf.button_node(acts, fn() { @sf.t("web-main.newChat.goStations") }, fn() {
          open_page(Place("stations"))
        }, tone=Ghost)
        |> ignore
      },
    )
  })
  |> ignore
}

///|
/// Nothing to run a chat with yet (new_blocked's): what to add, whom to ask, where to pick models; the station chosen
/// anew among several.
fn new_blocked_node(
  v : @view.View,
  src : Source,
  w : Workspace,
  frame : NewChatNodeFrame,
  tips : @sf.TipLayer,
  view : () -> Json?,
) -> Unit {
  let station = fn() { field(view(), "station") }
  let address = fn() { text(station(), "station") }
  let name = fn() { new_station_words(station()) }
  let blocked = fn() { text(view(), "blocked") }
  v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
  v.box(fn(o) {
    o.width(By(fn() { Some(@sf.dmin(new_column_w, (frame.width)() - 2.0 * new_column_in)) })) |> ignore
    @sf.first_one_node(
      o,
      fn() {
        match blocked() {
          "profile" => @sf.t("web-main.newChat.addProfileFor", args=[("name", name())])
          "disabled" => @sf.t("web-main.newChat.profilesDisabled")
          "shared" => @sf.t("web-main.newChat.notShared", args=[("name", name())])
          _ => @sf.t("web-main.newChat.pickModels")
        }
      },
      lead=fn() {
        match blocked() {
          "profile" =>
            @sf.t("web-pages.profiles.lead", args=[("subscription", @sf.t("web-pages.profiles.leadSubscription"))])
          "shared" | "disabled" => text(view(), "problem")
          _ => @sf.t("web-main.newChat.noModelsLead", args=[("name", name())])
        }
      },
      art=fn(a) {
        a.pick(fn() { @sf.theme().dark }, fn(x, dark) {
          @sf.drawable_node(x, if dark { "illus_no_profile_dark" } else { "illus_no_profile" }, new_scene_w) |> ignore
        })
      },
      fn(acts) {
        acts.pick(blocked, fn(b, k) {
          match k {
            "profile" =>
              @sf.button_node(b, fn() { @sf.t("web-main.newChat.addProfile") }, fn() {
                open_page(Setting(@settings.Route::NewProfile(address())))
              }, tone=Primary, icon="plus")
              |> ignore
            "shared" => if flag(view(), "profileScopeMissing") {
              @sf.button_node(b, fn() { @sf.t("web-main.newChat.goPickModels") }, fn() {
                open_page(Setting(@settings.Route::Profiles(address())))
              }, tone=Primary)
              |> ignore
            }
            _ =>
              @sf.button_node(b, fn() { @sf.t("web-main.newChat.goPickModels") }, fn() {
                open_page(Setting(@settings.Route::Profiles(address())))
              }, tone=Primary)
              |> ignore
          }
        })
        acts.show(fn() { items(view(), "stations").length() > 1 }, fn(s) {
          let on : NewOn = {
            page: v,
            src,
            w,
            frame,
            tips,
            view,
            held: fn() { false },
            error: fn() { "" },
            station,
            going: fn() { false },
          }
          new_station_control_node(s, on, station, view, false)
        })
      },
    )
  })
  |> ignore
}

///|
/// The new chat's first message sent from its composer made as nodes (new_send's, a node's) to `station` (its
/// name `name`): the page becomes the chat the frame it is sent, by the key the core keeps for the next one made (the
/// one made for it already while the picks are the same), its first words in its list from then and flying there from
/// where they stand (composer_sent_from_node), its scene leaving as the page does (chat_page_made's show); what the core
/// does then goes on behind it (new_send_go).
fn new_send_node(on : NewOn, station : String, name : String, d : Writing) -> Unit {
  let src = on.src
  let fresh = @sfbase.fresh
  if src.read_only {
    toast_later(read_only_words)
    return
  }
  if @signals.untracked(fn() { fresh.starting.get() }) {
    return
  }
  let v = @signals.untracked(on.view)
  // the chat it becomes: the one made for it already (its picks the same), else the next the core keeps for it
  let made = @signals.untracked(fn() { fresh.made.get() })
  let make = made == ""
  let key = if make { text(v, "next") } else { made }
  if key == "" {
    return
  }
  // sent, felt as a key's light tap (a no as something refused)
  @ui.haptic(KeyboardTap)
  let words = sent_words(d)
  remember_sent_pictures_now(src, d, station)
  let up = @signals.untracked(fn() { up_files(d) })
  let going = @signals.untracked(fn() { going_files(d) })
  let quotes = @signals.untracked(fn() { sent_quotes(d) })
  let runs = @sfbase.refs_sent_runs(d.key, words)
  let rk = station + "\u{1}" + key
  // called what the page was (新对话) until someone names it, as the core calls it
  let r : ChatRef = { station, session: key, title: @sf.t("web-main.newChat.title"), station_name: name }
  // (its words, cards and files flying from where they stand in this page's composer: composer_sent_from_node, as a
  // chat's own)
  let from = composer_sent_from_node(src, d)
  let row = sent_local(rk, None, words, up, going~, quotes~, runs~, from~, now=(src.now)())
  // (start unified choreography for actual layout width: wide morphs the roomy composer from middle to foot; narrow
  // hands off any multi-line/attachment extra height so frame 0 never collapses)
  let wide = @signals.untracked(fn() { (on.frame.width)() >= @sf.page_narrow_most })
  let at = on.page.cause_at()
  @sfbase.fresh_choreo_start(wide, at)
  @sfbase.fresh_choreo.val.arm(on.page)
  if wide && !@ui.reduced_motion() {
    @sfbase.fresh_composer_at.set(composer_node_box(d.key))
  } else if !wide && !@ui.reduced_motion() {
    let extra = composer_node_extra_height(d.key)
    @sfbase.fresh_composer_over.set(extra)
    @sfbase.fresh_over_held.set(extra)
  }
  // (the cursor in its field as it is sent: in the chat's composer as that comes, the keyboard as it was, this page's
  // field let go as it leaves (composer_take_focus, as the chat's composer asks it); sent without it, none)
  if d.field.focused() {
    composer_take_focus()
  }
  // (its scene leaving as the page does, as it becomes the chat (chat_page_made's show); the chat not made, reverse
  // choreography smoothly back from current mid-flight values (or arm anew if page remounts via fresh_back))
  new_send_go(src, on.frame.sent, v, station, key, make, d, rk, row, r, fn() {  }, fn() {  }, fn() {
    @sfbase.fresh_choreo_reverse(on.page.cause_at())
    if on.page.alive() {
      @sfbase.fresh_choreo.val.arm(on.page)
    } else {
      @sfbase.fresh_back.val = true
      @ui.after_frame(fn() { @sfbase.fresh_back.val = false })
    }
  })
}
