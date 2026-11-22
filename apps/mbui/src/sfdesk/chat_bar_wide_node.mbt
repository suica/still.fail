// A chat's bar on 中屏 and 大屏 (chat_page.mbt's chat_bar) as nodes of the window's tree, made once over the chat's page
// (chat_page_made's `over`), changed as what it shows does: its title (while a new one goes, that one with a turning
// ring; a red mark a while where it did not), its station while no agent is in it (its card over it), its people, its
// agents (each its history beside the chat, its card on hover; the first one tile with the station it runs on); at its
// end ⌘F's bar while the find is open in it (find_bar_node), else 归档 while nothing is left in it, its services and
// jobs, its station's screens, 对话信息, "…" and the side panel's switch while the panel is closed, none of them where
// the system's bars have them (rail_native.mbt's bar_chat, handed as the old view builds). Where it keeps clear at its
// ends is the frame's (ChatBarEnds: the window's corner on 大屏, the page's panel's on the tape); laid out as the old
// bar was, by the same styles. What opens under it (its info, its jobs) is the old view's as yet, opened by the signals
// its buttons set, beside them (chat_bar_from).

///|
/// Where a chat's bar keeps clear at its ends and over its buttons, as the frame it is in says (chat_bar_wide_node's):
/// how much taller it is over its buttons (`over`: the tape's line), how far it is moved in from its ends while the
/// folded sidebar is shown a while (`margins`, before and after: less than none before, drawn moved back), its room
/// at its start (`start`, given whether a title starts it: one that has none starts with its marks, round as they
/// are) and at its end (`end`, given whether the side panel is open beside it and ⌘F's bar is in it),
/// the corner its buttons share with the window's (`linked`: none on the tape), its ground as drawn in node `bar`
/// (`ground`: the page's; on the tape, the page's panel's, a step darker while that is behind the one in use), and how
/// far its page's column starts from its own start past where the bar starts (`content_offset`: the page's margin
/// before the bar's taken back, while the folded sidebar is shown a while; none on the tape).
pub(all) struct ChatBarEnds {
  over : () -> Double
  margins : () -> (Double, Double)
  start : (Bool) -> Double
  end : (Bool, Bool) -> Double
  linked : () -> @ui.CornerOf?
  ground : (@view.View) -> Int64
  content_offset : () -> Double
}

///|
/// The bar of the chat page `page` is (none over any other page) in node `v`, over the page's old view, from source
/// `src`, keeping clear at its ends as `ends` says; its tips in `tips`, its pictures asked for on the page's time on
/// top, `stint`.
pub fn chat_bar_wide_node(
  v : @view.View,
  src : Source,
  page : () -> Page?,
  ends : ChatBarEnds,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let chat = fn() {
    match page() {
      Some(Chat(r)) => Some(r)
      _ => None
    }
  }
  // (the new chat made as nodes with the page (its new_node's): its bar, dragging the window whatever it holds; its 文件
  // where a station lends its files, new_bar_of)
  let new_of = fn() {
    match page() {
      Some(NewChat) => @sfbase.workspace_in_view(src).0
      _ => None
    }
  }
  // (by the chat it is of: another one become in its place another bar, at once, as tall as a bar from the first: none
  // become one (a new chat, a place, 设置 left for a chat) is no bar growing)
  v.switch_by(fn() { (chat().map(fn(r) { (r.station, r.session) }), new_of().map(fn(w) { w.id })) }, fn(b, which) {
    match which {
      (Some(_), _) =>
        match @signals.untracked(chat) {
          Some(r) => wide_bar_of(b, src, r, ends, tips, stint)
          None => ()
        }
      (None, Some(_)) =>
        match @signals.untracked(new_of) {
          Some(w) => new_bar_of(b, src, w, ends, tips)
          None => ()
        }
      (None, None) => ()
    }
  })
}

///|
/// Workspace `w`'s new chat's bar in `b` (new_chat_page's, chat_bar_wide_node's): 文件 where a chat's bar has the side
/// panel's switch, at its end, as far in as `ends` keeps a chat's (the window's corner while its panel is not open beside
/// it), toggling its Station 文件 beside it (new_files_set); nothing else of it, the page's ground under it, its empty
/// part dragging the window where the window's buttons are the app's. Its tips in `tips`.
fn new_bar_of(b : @view.View, src : Source, w : Workspace, ends : ChatBarEnds, tips : @sf.TipLayer) -> Unit {
  let high = fn() { @sf.wide_bar_h + (ends.over)() }
  let beside = fn() { new_files_open(src, w.id) }
  // (its 文件 handed the system's bars where they are the app's, as a chat's actions are (chat_page.mbt's
  // chat_bar_handed_node): as the page comes on top, as the bars come or the column grows short, as a station to look in
  // comes or goes; the actions handed for another page let go first)
  b.reacts(fn() { (app.nav.top() is NewChat, @sf.native_on(), column_short.get(), new_drive_station(src, w) is Some(_)) }, fn(
    said,
  ) {
    guard said.0 else { return }
    @signals.untracked(fn() {
      nav_page_for(NewChat)
      nav_page.retain(fn(p) { p.0.id != "page/new/files" })
      if said.3 {
        bar_action("new/files", @sf.t("web-pages.chat.files"), "folder", fn() {
          new_files_set(src, w.id, !new_files_open(src, w.id))
        })
        |> ignore
      }
    })
  })
  b
  .row(Is(true))
  .height(By(fn() { Some(high()) }))
  .alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
  .takes_unseen(Is(true))
  .offset(By(fn() { (dmin(0.0, (ends.margins)().0), 0.0) }))
  |> ignore
  bar_room_node(b, fn() { dmax(0.0, (ends.margins)().0) })
  b.box(fn(bar) {
    bar
    .row(Is(true))
    .grow(Is(1.0))
    .height(By(fn() { Some(high()) }))
    .padding(By(fn() { (0.0, (ends.over)(), 0.0, 1.0) }))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(End))
    // (its empty part drags the window, in one with its buttons in the app's top row: what is in it taking presses all
    // the same, so it is said to take them always, as a chat's bar's)
    .presses(Is(true))
    .moves_window(By(@ui.window_inset_now))
    |> ignore
    // (drawn in the page where the system's bars are not the app's: there, handed them, above)
    bar.show(fn() { !@sf.native_on() && new_drive_station(src, w) is Some(_) }, fn(e) {
      e.shrink(Is(0.0)) |> ignore
      @sf.icon_button_node(
        e,
        "folder",
        fn() { @sf.t("web-pages.chat.files") },
        fn() { new_files_set(src, w.id, !new_files_open(src, w.id)) },
        tips~,
        linked=ends.linked,
      )
      |> ignore
    })
    bar_room_node(bar, fn() { (ends.end)(beside(), false) })
  })
  |> ignore
  bar_room_node(b, fn() {
    let (ml, mr) = (ends.margins)()
    mr + dmin(0.0, ml)
  })
}

///|
/// Chat `r`'s bar in `b` (chat_bar_wide_node's): its row as page_bar_row's (as high as a bar is, with what is over its
/// buttons; its margins while the folded sidebar is shown a while), its box (its empty part dragging the window where
/// the window's buttons are the app's) over a soft scroll edge in its ground (wide_bar_scrim_node: what scrolls under
/// it blurred and veiled away, as 小屏's bar has it), its rooms at its ends: its title where the chat's words start in
/// its column (as the column is laid out on its way to another width), never nearer its start than its ends allow.
fn wide_bar_of(b : @view.View, src : Source, r : ChatRef, ends : ChatBarEnds, tips : @sf.TipLayer, stint : () -> Int) -> Unit {
  let view = fn() { @sfbase.chat_view_now(src, r) }
  b.reacts(fn() {
    match @sfbase.workspace_in_view(src).0 {
      Some(w) => @sfbase.station_marks(src, w.id) |> ignore
      None => ()
    }
    src.topic("chatJobs", chat_jobs_summary_params(r)).get() |> ignore
  }, fn(_) { () })
  // (what opens under it, as the bar is made: chat_pops_node)
  chat_pops_node(b, src, r, view, stint)
  let finding = fn() {
    match view() {
      Some(v) => @sfpages.find_chat() == chat_key(r) && v.thread is Some(_)
      None => false
    }
  }
  // (whether a title starts it: a chat with none starts with its marks)
  let titled = fn() {
    match view() {
      Some(v) => v.title != ""
      None => r.title != ""
    }
  }
  let beside = fn() {
    match view() {
      Some(v) => side_of(v).0.length() > 0
      None => false
    }
  }
  // ⌘F's bar while the find is open and, once it closes, while it fades out as it was (the pick's `leave_of`, its way
  // out its own: find_bar_node's presence_in); then the chat's buttons in its place, faded in over as long from there
  // alone (`back_in`): a bar made with the find shut shows them at once, nothing more made for it. Which of the two
  // holds the place, for its room at its end (`find_shown`), as each is made
  let back_in = Ref(false)
  let find_shown = @signals.signal(@signals.untracked(finding), same=fn(a, b) { a == b })
  let high = fn() { @sf.wide_bar_h + (ends.over)() }
  b.by_room(fn(held, room) {
    held
    .row(Is(true))
    .height(By(fn() { Some(high()) }))
    // (drawn at none while the app's first page waits, as the page's old view is: sfbase's first_page_waits)
    .alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
    .takes_unseen(Is(true))
    // (its margins as spaces at its ends, one less than none taken back by drawing the row moved back as far)
    .offset(By(fn() { (dmin(0.0, (ends.margins)().0), 0.0) }))
    |> ignore
    bar_room_node(held, fn() { dmax(0.0, (ends.margins)().0) })
    held.box(fn(bar) {
      bar
      .row(Is(true))
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      .lines_up(Is(Some(Middle)))
      .height(By(fn() { Some(high()) }))
      .padding(By(fn() { (0.0, (ends.over)(), 0.0, 1.0) }))
      // (its empty part drags the window, in one with its buttons in the app's top row: what is in it taking presses
      // all the same, so it is said to take them always)
      .presses(Is(true))
      .moves_window(By(fn() { @ui.window_inset() }))
      |> ignore
      // (as tall as the bar and 16 more, faded out over all of it: the chat under it never cut off at a line; where glass
      // is drawn solid (no blur: less see-through asked for), whole under the bar and faded out over its 16 past it, no
      // words under it showing through the title)
      wide_bar_scrim_node(
        bar,
        fn(_) { high() + 16.0 },
        fn(s) { if s.glass_solid() { 16.0 } else { high() + 16.0 } },
        ends.ground,
      )
      // (the title's words, chat_bar_title_in into its row, where the column's words start: chat_row_side of the width
      // it is laid out at, moved across as the column is on its way (sfbase's column_laid); none before the bar's start
      // room)
      let chat_id = r.station + "\u{1}" + r.session
      bar_room_node(bar, fn() {
        let least = (ends.start)(titled())
        let col = @sfbase.column_laid(chat_id, bar)
        let side = if col.laid > 0.0 {
          @sfpages.chat_row_side(col.laid) + col.across
        } else {
          @sfpages.chat_row_side(room.width())
        }
        dmax(least, side + (ends.content_offset)() - chat_bar_title_in)
      })
      bar.box(fn(inner) {
        inner
        .row(Is(true))
        .grow(Is(1.0))
        .basis(Is(Some(0.0)))
        .min_width(Is(Some(0.0)))
        .height(Is(Some(@sf.wide_bar_h)))
        .gap(Is(16.0))
        .lines_up(Is(Some(Middle)))
        |> ignore
        wide_bar_title_row(inner, src, r, view, fn() { room.width() }, tips, stint)
        // ⌘F's bar, in place of the buttons while the find is open: it covers none of the chat. Closed, it goes out
        // over find_in_ms before the buttons come (one, then the other: never both seen)
        inner.pick(
          leave_of=fn(was, now) { if was && !now { @sfpages.find_in_ms } else { 0.0 } },
          fn() { finding() },
          fn(e, open) {
            find_shown.set(open)
            if open {
              back_in.val = true
              // (what holds it giving way as it does: the old row's had none of its own)
              e.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              @sfpages.find_bar_node(
                e,
                src,
                r,
                fn() { view().bind(fn(v) { v.thread }) },
                @sfpages.chat_find_list(r),
                tips,
              )
              |> ignore
            } else {
              // (back from ⌘F's bar faded out: faded in from now, as long)
              if back_in.val {
                back_in.val = false
                let seen = @motion.presence_in(e, @motion.tween(@sfpages.find_in_ms, ease=Out))
                e.alpha(By(seen)) |> ignore
              }
              wide_bar_keys(e, src, r, view, ends, tips, stint)
            }
          },
        )
      })
      |> ignore
      // (the trailing action pill is a visible 38pt liquid glass capsule, so keep >= 12pt right inset to stay symmetric with the 12pt left title inset)
      bar_room_node(bar, fn() {
        let end_room = (ends.end)(beside(), find_shown.get())
        if find_shown.get() {
          end_room
        } else {
          dmax(12.0, end_room)
        }
      })
    })
    |> ignore
    bar_room_node(held, fn() {
      let (ml, mr) = (ends.margins)()
      mr + dmin(0.0, ml)
    })
  })
  // (as high as the bar, what takes presses in it within it)
  .height(By(fn() { Some(high()) }))
  |> ignore
}

///|
/// The bar's soft scroll edge in `parent` (narrow_shell.mbt's narrow_bar_scrim_node, in the bar's ground `ground`):
/// `base_h` tall from its top, faded out over the lower `fade_h` of it. Its fill takes the presses within the bar (none
/// reach the chat under it) but points at nothing, and is the bar's own: the bar's empty part still drags the window.
fn wide_bar_scrim_node(
  parent : @view.View,
  base_h : (@view.View) -> Double,
  fade_h : (@view.View) -> Double,
  ground : (@view.View) -> Int64,
) -> Unit {
  parent.box(fn(scrim) {
    scrim
    .over(Is(true), from_top=true)
    .width_share(Is(1.0))
    .height(By(fn() { Some(base_h(scrim)) }))
    .fades(By(fn() { (0.0, 0.0, 0.0, fade_h(scrim)) }))
    |> ignore
    scrim.box(fn(fill) {
      fill
      .width_share(Is(1.0))
      .height_share(Is(1.0))
      .glass(By(fn() { if base_h(fill) > 0.0 { Some(@sf.glass_scroll_edge(ground=ground(fill))) } else { None } }))
      .points(Is(false))
      |> ignore
      fill.pointed() |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The bar's title row in `inner` (chat_bar_title_row's: never narrower than what is left in it needs, ⌘F's field
/// beside it giving way first): the title, 42% of the bar's width (`across`) at most, 80 at least, cut short; then,
/// once the view is read, its station's tag while no agent is in it, its people (the first to leave the row short of
/// room), its agents (the last but the first leaving next), each made again as what it draws changes. Each of them the
/// row's own (what leaves it, as the old row's boxes: a row leaves out of what it holds, View::fits).
fn wide_bar_title_row(
  inner : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  across : () -> Double,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  inner.box(fn(row) {
    row
    .row(Is(true))
    .grow(Is(1.0))
    .basis(Is(Some(0.0)))
    .min_width(Is(Some(0.0)))
    .padding(Is((8.0, 0.0, 4.0, 0.0)))
    .gap(Is(10.0))
    .lines_up(Is(Some(Middle)))
    .keeps_held(Is(true))
    .fits(Is(true))
    |> ignore
    wide_bar_breadcrumb(row, view, across, tips)
    wide_bar_title(row, src, r, view, across, tips)
    let people = fn() {
      match view() {
        Some(v) => v.people
        None => []
      }
    }
    row.show(fn() { people().length() > 0 }, along_row=true, fn(p) {
      p.drops(Is(chat_bar_drop_people)) |> ignore
      p.pick(fn() { people().map(fn(p) { "\{p.id}\u{1}\{p.display}\u{1}\{p.picture}" }).join("\u{2}") }, fn(q, _) {
        wide_people(q, src, @signals.untracked(people), 5, tips, stint)
      })
    })
  })
  |> ignore
}

///|
/// Led parent-chat route breadcrumb before the chat title on Medium/Large screens:
/// - 0 ancestors: renders nothing (zero visual noise on ordinary chats and chats opened for a person)
/// - 1-2 ancestors: `[ spawned + parent1 ] › [ parent2 ] ›`
/// - 3+ ancestors: `[ spawned + root ] › [ … ] › [ direct parent ] ›` (clicking `…` opens a menu of middle ancestors)
fn wide_bar_breadcrumb(
  row : @view.View,
  view : () -> ChatView?,
  across : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  let openers = fn() {
    match view() {
      Some(v) => v.openers
      None => []
    }
  }
  let key_of = fn() {
    openers().map(fn(o) { "\{o.chat.station}\u{1}\{o.chat.session}\u{1}\{o.chat.title}\u{1}\{o.archived}" }).join("\u{2}")
  }
  row.show(fn() { openers().length() > 0 }, at_once=true, fn(wrap) {
    wrap.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(2.0)).shrink(Is(0.0)) |> ignore
    wrap.pick(at_once=true, key_of, fn(bc, _) {
      bc.row(Is(true)).lines_up(Is(Some(Middle))).gap(Is(2.0)).shrink(Is(0.0)) |> ignore
      let list = @signals.untracked(openers)
      let n = list.length()
      guard n > 0 else { return }
      let seg_max = fn() { dmax(56.0, dmin(140.0, across() * 0.16)) }
      let crumb_item = fn(p : @view.View, o : @sfbase.Opener, first : Bool) {
        let tip_text = if o.archived && o.note != "" { o.chat.title + " (" + o.note + ")" } else { o.chat.title }
        @sf.action_box_node(p, fn() { o.chat.title }, fn(_) { @sfbase.open_page(Chat(o.chat)) }, fn(b) {
          b
          .row(Is(true))
          .height(Is(Some(@sf.bar_key_side)))
          .padding(Is((6.0, 0.0, 6.0, 0.0)))
          .gap(Is(4.0))
          .lines_up(Is(Some(Middle)))
          .radius(Is(8.0))
          .max_width(By(fn() { Some(seg_max()) }))
          |> ignore
          @sf.hover_ground_node(b)
          @sf.focus_ring_node(b)
          if first {
            @sf.icon_node(b, "spawned", 14.0, By(fn() { if @sf.lit_node(b) { @sf.theme().p.text } else { @sf.theme().p.muted } }))
            |> ignore
          }
          @sf.words_node(b, fn() { o.chat.title }, fn() {
            if @sf.lit_node(b) {
              wide_crumb_words_hot
            } else {
              wide_crumb_words
            }
          })
          .allow_ellipsis(Is(true))
          .min_width(Is(Some(0.0)))
          |> ignore
          @sf.tip_node(tips, b, fn() { tip_text }) |> ignore
        })
        .says(Is(Some(@view.said(Link, label=o.chat.title))))
        |> ignore
      }
      let chevron = fn(p : @view.View) {
        @sf.icon_node(p, "chevron-right", 12.0, By(fn() { @sf.theme().p.subtle })) |> ignore
      }
      if n <= 2 {
        for i, o in list {
          crumb_item(bc, o, i == 0)
          chevron(bc)
        }
      } else {
        crumb_item(bc, list[0], true)
        chevron(bc)
        let middle = list[1:n - 1].to_owned()
        @sf.action_box_node(bc, fn() { @sf.t("web-pages.chat.breadcrumbMore") }, fn(at) {
          let items : Array[@sf.MenuItem?] = middle.map(fn(o) {
            let label = if o.archived && o.note != "" { o.chat.title + " (" + o.note + ")" } else { o.chat.title }
            Some(@sf.menu_item_of(label, icon="spawned", fn() { @sfbase.open_page(Chat(o.chat)) }))
          })
          @sf.menu(items, from=Node(at))
        }, fn(b) {
          b
          .row(Is(true))
          .height(Is(Some(@sf.bar_key_side)))
          .padding(Is((6.0, 0.0, 6.0, 0.0)))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          .radius(Is(8.0))
          |> ignore
          @sf.hover_ground_node(b)
          @sf.focus_ring_node(b)
          @sf.icon_node(b, "more", 14.0, By(fn() { if @sf.lit_node(b) { @sf.theme().p.text } else { @sf.theme().p.muted } }))
          |> ignore
          @sf.tip_node(tips, b, fn() { @sf.t("web-pages.chat.breadcrumbMore") }) |> ignore
        })
        |> ignore
        chevron(bc)
        crumb_item(bc, list[n - 1], false)
        chevron(bc)
      }
    })
  })
}

///|
// kept across runs: a value (no field of it changes)
let wide_crumb_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Muted, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let wide_crumb_words_hot : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false, w=Cut)

///|
// kept across runs: a value (no field of it changes)
let wide_subchats_count : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Muted, wrap=false, tabular=true)

///|
// kept across runs: a value (no field of it changes)
let wide_subchats_count_hot : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=false, tabular=true)

///|
/// The chat's title in its row (chat_title's): while a new one goes (`chat.rename`), that one, a turning ring beside
/// it; its own again where it did not, a red mark there a while saying why.
fn wide_bar_title(
  row : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  across : () -> Double,
  tips : @sf.TipLayer,
) -> Unit {
  // (a rename of this chat: by the session the page names it by, or by its thread, as its "…" names it by its row's:
  // a chat a new chat's page became is named by the key it was sent under all along, its row by its station's session)
  let ours = fn(d : Json?) {
    let p = field(d, "params")
    text(d, "call") == "chat.rename" &&
    text(p, "station") == r.station &&
    (text(p, "session") == r.session ||
    (match (opt_number(p, "thread"), view()) {
      (Some(th), Some(v)) => v.thread == Some(th)
      _ => false
    }))
  }
  let renaming = fn() {
    let mut renaming = ""
    for d in items(src.topic("doing", {}).get().value, "doing") {
      let dv = Some(d)
      if text(dv, "stage") != "failed" && ours(dv) {
        renaming = text(field(dv, "params"), "title")
      }
    }
    renaming
  }
  // (what shows: the one going while one goes)
  let title = fn() {
    match renaming() {
      "" =>
        match view() {
          Some(v) => v.title
          None => r.title
        }
      now => now
    }
  }
  let failed = fn() { core_failed_of(src, fn(d) { ours(Some(d)) }) }
  row.box(fn(t) {
    // (42% of the bar at most, 80 at least; giving way with ⌘F's field once the people have left, down to 4 of its
    // letters)
    @sf.style_node(t, fn() { chat_title_room.then(@ui.style(max_w=Fixed(dmax(chat_title_least, across() * chat_title_part)))) }, in_row=true)
    t.shrink(Is(1.0)) |> ignore
    @sf.words_node(
      t,
      title,
      fn() { chat_title_words },
    )
    |> ignore
    // (read out as its words, where they are)
    t.says(By(fn() { Some(@view.said(Text, label=title())) })) |> ignore
  })
  |> ignore
  row.show(fn() { renaming() != "" || failed() is Some(_) }, along_row=true, fn(d) {
    @sfpages.doing_mark_node(d, fn() { renaming() != "" }, failed, size=wide_doing_mark)
    @sf.tip_node(
      tips,
      d,
      fn() {
        match failed() {
          Some(why) => why
          None => @sf.t("web-pages.settings.stations.renaming")
        }
      },
      within=true,
    )
    |> ignore
  })
}

///|
/// The doing mark's size beside the title (doing_mark's, not inline: 14).
let wide_doing_mark : Double = 14.0

///|
/// Unified iOS 27 single-layer liquid glass floating capsule (30pt) for composer-top controls on Medium/Large screens.
fn wide_glass_capsule(b : @view.View) -> Unit {
  @sf.glass_capsule_node(b, min_height=Some(30.0), radius=Some(999.0))
  .row(Is(true))
  .lines_up(Is(Some(Middle)))
  .lies_along(Is(Middle))
  .shrink(Is(1.0))
  .min_width(Is(Some(0.0)))
  |> ignore
}

///|
/// The machine the chat runs on above the composer while it has no agent to share a capsule with:
/// single-layer 30pt liquid glass capsule with the station's mark and its via dot (@sfpages.station_via_mark_node) and name.
fn wide_station_tag(
  m : @view.View,
  address : String,
  s : Station,
  via : () -> String,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  m.box(fn(k) {
    let hot = fn() { @sf.lit_within_node(k) }
    wide_glass_capsule(k)
    k.padding(Is((10.0, 0.0, 10.0, 0.0))).gap(Is(6.0)) |> ignore
    @sf.hover_ground_node(k, lit=Some(hot))
    k.says(Is(Some(@view.said(Group, label=s.name)))) |> ignore
    @sf.hover_card_node(tips, k, fn(c) { @settings.station_peek_card_node(c, address, stint) }, tile=true, padded=false, side=Top, tapped=fn() {
      @settings.open_station_peek(address, from=Node(k))
    })
    |> ignore
    @sfpages.station_via_mark_node(k, fn() { s.emoji }, fn() { s.icon }, via, fn() { @sf.theme().p.text }, stint)
    k.box(fn(w) {
      w
      .words(Is(s.name))
      .words_look(By(fn() { @ui.style_words(chat_station_words) }))
      .ink(By(fn() { @ui.style_ink(chat_station_words) }))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      .cuts(Is(true))
      .allow_ellipsis(Is(true))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// People overlapping a little (people_stack's): the library's stack (@sf.avatar_stack_node), `most` of them at most,
/// each a 16 face ringed 1.5 in the sidebar's ground (their picture, or their initial on the paper), each ringed face 7
/// along the one before it and drawn over it, the first's ring standing out of where the stack starts; more, +n after them;
/// their names in its tip.
fn wide_people(
  parent : @view.View,
  src : Source,
  people : Array[Person],
  most : Int,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let faces = people.map(fn(p) {
    let face : @sf.StackFace = {
      id: p.id,
      name: p.display,
      pictured: p.picture != "",
      picture: fn() { if p.picture != "" { (src.picture)(p.picture, stint()) } else { "" } },
    }
    face
  })
  @sf.avatar_stack_node(
    parent,
    faces,
    person_side,
    fn() { @sf.theme().p.sidebar },
    over=7.0,
    // (each over the one before, one with no picture its initial on the paper: the old page's people_stack, drawn the
    // same as it beside it)
    first_over=false,
    letter=(fn() { @sf.theme().p.paper }, fn() { people_letter }),
    most~,
    tips~,
    tip=fn() {
      @sf.t("web-main.people.in", args=[("names", people.map(fn(p) { p.display }).join(@sf.t("web-main.list.separator")))])
    },
  )
  .margin(Is((-1.5, 0.0, 0.0, 0.0)))
  |> ignore
}

///|
/// One station group of agents above the composer on Medium / Large screens: a single 30pt liquid glass capsule with
/// Station first (mark + via dot + name), followed by the main divider and all agents on that station separated by
/// subtle vertical hairlines. On keyboard-and-mouse each segment hovers and activates independently (and the active
/// side-panel agent highlights its own segment without framing the whole capsule). On touch a single-agent capsule
/// stays one whole button (tap for history, hold for agent + station cards); a multi-agent capsule makes each agent
/// segment its own button (tap for history, hold for agent + station cards).
fn wide_station_group_tile(
  parent : @view.View,
  src : Source,
  r : ChatRef,
  group : @sfpages.StationAgentGroup,
  badge_of : (Int, String) -> () -> String,
  marked_of : (String) -> () -> Bool,
  station_now : () -> Station?,
  via : () -> String,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let n = group.agents.length()
  guard n > 0 else { return }
  if @sf.tile_whole() && n == 1 {
    let a = group.agents[0]
    let said = fn() { @sf.t("web-pages.chat.historyOf", args=[("agent", a.who)]) }
    let badge = badge_of(0, a.key)
    let badge_said = fn() { text(field(agent_json(@sfbase.chat_head_json(src, r), a.key), "session"), "badgeText") }
    let toggle = fn() { side_toggle(src, r, a.key) }
    let hand : Ref[@sf.HoverHand?] = Ref(None)
    let held : Ref[() -> Bool] = Ref(fn() { false })
    let card = fn() {
      match hand.val {
        Some(h) => (h.card)()
        None => None
      }
    }
    // (with touch a single-agent capsule is one button: tapped its history's; held, its card and its station's as one)
    @sf.action_box_node(parent, said, fn(_) { toggle() }, on_hold=fn() { if hand.val is Some(h) { (h.hold)() } }, fn(t) {
      wide_glass_capsule(t)
      t.fits(Is(true)) |> ignore
      @sf.hover_ground_node(t)
      hand.val = Some(
        @sf.hover_card_node(
          tips,
          t,
          fn(c) {
            c.box(fn(o) {
              @sf.style_node(o, fn() { tile_card_agent })
              held.val = @sfpages.agent_card_node(o, src, r, a.key, tips, card, across=true)
            })
            |> ignore
            if @signals.untracked(station_now) is Some(_) {
              @settings.station_peek_part_node(c, r.station, stint)
            }
          },
          tile=true,
          padded=false,
          side=Top,
          held=fn() { (held.val)() },
          pointed=fn() { t.pointed_in() },
        ),
      )
      t.show(at_once=true, fn() { station_now() is Some(_) }, fn(p) {
        p.row(Is(true)).fits(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))).min_height(Is(Some(30.0))).lines_up(Is(Some(Middle))) |> ignore
        p.box(fn(sp) {
          sp
          .row(Is(true))
          .fits(Is(true))
          .shrink(Is(1.0))
          .min_width(Is(Some(0.0)))
          .min_height(Is(Some(30.0)))
          .padding(Is((10.0, 0.0, 8.0, 0.0)))
          .gap(Is(6.0))
          .lines_up(Is(Some(Middle)))
          |> ignore
          wide_station_inline(sp, station_now, via, stint)
        })
        |> ignore
        p.box(fn(sep) {
          sep.width(Is(Some(1.0))).height(Is(Some(12.0))).shrink(Is(0.0)).ground(By(fn() { @sf.alpha(@sf.theme().p.line, 0.7) }))
          |> ignore
        })
        |> ignore
      })
      t.box(fn(g) {
        g
        .row(Is(true))
        .fits(Is(true))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .keeps_held(Is(true))
        .min_height(Is(Some(30.0)))
        .lines_up(Is(Some(Middle)))
        .gap(Is(6.0))
        .padding(By(fn() { if station_now() is Some(_) { (8.0, 0.0, 10.0, 0.0) } else { (10.0, 0.0, 10.0, 0.0) } }))
        |> ignore
        wide_agent_inline(g, a, badge, badge_said)
      })
      |> ignore
    })
    |> ignore
  } else {
    let t = parent
    wide_glass_capsule(t)
    t.fits(Is(true)) |> ignore
    let touch_multi = @sf.tile_whole()
    t.show(at_once=true, fn() { station_now() is Some(_) }, fn(p) {
      p.row(Is(true)).fits(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))).min_height(Is(Some(30.0))).lines_up(Is(Some(Middle))) |> ignore
      p.box(fn(sp) {
        sp
        .row(Is(true))
        .fits(Is(true))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .min_height(Is(Some(30.0)))
        .padding(Is((10.0, 0.0, 8.0, 0.0)))
        .gap(Is(6.0))
        .lines_up(Is(Some(Middle)))
        |> ignore
        sp.says(By(fn() { station_now().map(fn(s) { @view.said(Group, label=s.name) }) })) |> ignore
        if touch_multi {
          wide_station_inline(sp, station_now, via, stint)
        } else {
          let hot = fn() { @sf.lit_within_node(sp) }
          @sf.hover_ground_node(sp, lit=Some(hot))
          @sf.hover_card_node(
            tips,
            sp,
            fn(c) { @settings.station_peek_card_node(c, r.station, stint) },
            tile=true,
            padded=false,
            side=Top,
            press=fn() { @settings.open_station_peek(r.station, from=Node(sp)) },
            tapped=fn() { @settings.open_station_peek(r.station, from=Node(sp)) },
          )
          |> ignore
          wide_station_inline(sp, station_now, via, stint)
        }
      })
      |> ignore
      p.box(fn(sep) {
        sep.width(Is(Some(1.0))).height(Is(Some(12.0))).shrink(Is(0.0)).ground(By(fn() { @sf.alpha(@sf.theme().p.line, 0.7) }))
        |> ignore
      })
      |> ignore
    })
    for i, a in group.agents {
      if i > 0 {
        t.box(fn(sep) {
          sep
          .width(Is(Some(1.0)))
          .height(Is(Some(10.0)))
          .margin(Is((1.0, 0.0, 1.0, 0.0)))
          .shrink(Is(0.0))
          .ground(By(fn() { @sf.alpha(@sf.theme().p.line, 0.35) }))
          |> ignore
        })
        |> ignore
      }
      let said = fn() { @sf.t("web-pages.chat.historyOf", args=[("agent", a.who)]) }
      let badge = badge_of(i, a.key)
      let badge_said = fn() { text(field(agent_json(@sfbase.chat_head_json(src, r), a.key), "session"), "badgeText") }
      let toggle = fn() { side_toggle(src, r, a.key) }
      let hand : Ref[@sf.HoverHand?] = Ref(None)
      let held : Ref[() -> Bool] = Ref(fn() { false })
      let card = fn() {
        match hand.val {
          Some(h) => (h.card)()
          None => None
        }
      }
      let is_last = i == n - 1
      @sf.action_box_node(t, said, fn(_) { toggle() }, on_hold=fn() { if hand.val is Some(h) { (h.hold)() } }, fn(g) {
        g
        .row(Is(true))
        .fits(Is(true))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        .keeps_held(Is(true))
        .min_height(Is(Some(30.0)))
        .lines_up(Is(Some(Middle)))
        .gap(Is(6.0))
        |> ignore
        if i == 0 {
          let pr = if is_last { 10.0 } else { 8.0 }
          g.padding(By(fn() { if station_now() is Some(_) { (8.0, 0.0, pr, 0.0) } else { (10.0, 0.0, pr, 0.0) } })) |> ignore
        } else {
          g.padding(Is((8.0, 0.0, if is_last { 10.0 } else { 8.0 }, 0.0))) |> ignore
        }
        if n > 1 {
          let marked = marked_of(a.key)
          g.radius(Is(999.0)) |> ignore
          @sf.hover_ground_node(g, extra=marked)
          hand.val = Some(
            @sf.hover_card_node(
              tips,
              g,
              fn(c) {
                if touch_multi {
                  c.box(fn(o) {
                    @sf.style_node(o, fn() { tile_card_agent })
                    held.val = @sfpages.agent_card_node(o, src, r, a.key, tips, card, across=true)
                  })
                  |> ignore
                  if @signals.untracked(station_now) is Some(_) {
                    @settings.station_peek_part_node(c, r.station, stint)
                  }
                } else {
                  held.val = @sfpages.agent_card_node(c, src, r, a.key, tips, card)
                }
              },
              tile=true,
              padded=!touch_multi,
              side=Top,
              held=fn() { (held.val)() },
              pointed=fn() { g.pointed_in() },
            ),
          )
          wide_agent_inline(g, a, badge, badge_said, marked=Some(marked))
        } else {
          @sf.hover_ground_node(g)
          hand.val = Some(
            @sf.hover_card_node(
              tips,
              g,
              fn(c) { held.val = @sfpages.agent_card_node(c, src, r, a.key, tips, card) },
              tile=true,
              side=Top,
              held=fn() { (held.val)() },
              pointed=fn() { g.pointed_in() },
            ),
          )
          wide_agent_inline(g, a, badge, badge_said)
        }
      })
      |> ignore
    }
  }
}

///|
/// Agent mark (15pt) + badge + readable agent name inside a composer-top liquid glass capsule.
fn wide_agent_inline(
  parent : @view.View,
  a : Agent,
  badge : () -> String,
  said : () -> String,
  marked? : (() -> Bool)? = None,
) -> Unit {
  parent.box(fn(m) {
    m
    .width(Is(Some(16.0)))
    .height(Is(Some(16.0)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .shrink(Is(0.0))
    |> ignore
    m.says(By(fn() { if said() == "" { None } else { Some(@view.said(Group, label=said())) } })) |> ignore
    @sf.maker_mark_node(m, a.maker, a.runtime, 15.0) |> ignore
    @sfpages.agent_badge_slot(m, badge, 16.0)
  })
  |> ignore
  let ink : (() -> Int64)? = match marked {
    Some(is_marked) =>
      Some(fn() { if is_marked() { @sf.theme().p.accent_text } else { @ui.style_ink(wide_subchats_words) } })
    None => None
  }
  @sfpages.model_agent_segments_static(
    parent,
    a.model_name,
    a.model_short,
    a.effort,
    a.who,
    fn() { wide_subchats_words },
    ink~,
    drop_short=1,
    drop_effort=2,
    drop_hide=0,
    cuts_last=true,
  )
}

///|
/// Station half inside the first agent's liquid glass capsule: station mark (15pt) with its via dot on its corner, or
/// the dot alone before the name for a station with no mark (@sfpages.station_via_mark_node), + station name.
fn wide_station_inline(p : @view.View, station_now : () -> Station?, via : () -> String, stint : () -> Int) -> Unit {
  @sfpages.station_via_mark_node(
    p,
    fn() { station_now().map(fn(s) { s.emoji }).unwrap_or("") },
    fn() { station_now().map(fn(s) { s.icon }).unwrap_or("") },
    via,
    fn() { @sf.theme().p.text },
    stint,
  )
  @sf.words_node(
    p,
    fn() { station_now().map(fn(s) { s.name }).unwrap_or("") },
    fn() { chat_station_words },
  )
  .shrink(Is(1.0))
  .min_width(Is(Some(0.0)))
  .cuts(Is(true))
  .allow_ellipsis(Is(true))
  .fit_whole(Is(true))
  |> ignore
}

///|
/// The bar's buttons at its end in `e` (chat_bar's keys_row, none where the system's bars have them): 归档 while
/// nothing is left in it, its services and jobs (a dot while one died lately or a service restarts), its station's
/// screens, 对话信息, "…", the side panel's switch while the panel is closed and an agent is in it.
fn wide_bar_keys(
  e : @view.View,
  src : Source,
  r : ChatRef,
  view : () -> ChatView?,
  _ends : ChatBarEnds,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let own = fn() { view() is Some(_) && !@sf.native_on() }
  e.show(own, at_once=true, fn(slot) {
    slot.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
    let scope = fn() {
      match @sfbase.workspace_in_view(src).0 {
        Some(w) => w.id
        None => ""
      }
    }
    let chat = fn() { @sfbase.chat_head_json(src, r) }
    // nothing left in it (the core's `archivable`): standalone 36×36 liquid glass circle so dynamic show/hide
    // outside a transition never steps the width of the persistent action pill
    slot.show(
      fn() {
        match view() {
          Some(v) => v.archivable && !v.archived
          None => false
        }
      },
      along_row=true,
      fn(b) {
        @sf.bar_pill_group_node(b, height=36.0, pad=2.0, gap=0.0, fn(p) {
          @sf.icon_button_node(p, "archive", fn() { @sf.t("web-pages.chat.archive") }, fn() {
            match (@signals.untracked(view), @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 })) {
              (Some(v), Some(w)) => archive_asked(src, w, r, v, @signals.untracked(chat))
              _ => ()
            }
          }, tips~, shortcut="chat.archive")
          |> ignore
        })
        |> ignore
      },
    )
    // grouped action pill: idle remote screens, info, more (active jobs, driven screen, and led subchats live in wide_composer_bar_node)
    @sf.bar_pill_group_node(slot, height=36.0, pad=2.0, gap=2.0, fn(k) {
      // idle remote screens entry stays in the top bar; when an agent actively drives a screen, it moves above the composer
      k.show(
        fn() {
          match view() {
            Some(v) => chat_has_remote(v) && !chat_screens_driven(v.screens)
            None => false
          }
        },
        along_row=true,
        fn(b) {
          let me : Ref[@view.View?] = Ref(None)
          let button = @sf.icon_button_node(b, "monitor", fn() { @sf.t("web-pages.chat.screen") }, fn() {
            match (@signals.untracked(view), me.val) {
              (Some(v), Some(at)) => chat_remote_open(src, r, v, from=Node(at))
              _ => ()
            }
          }, tips~, shortcut="chat.screen")
          me.val = Some(button)
        },
      )
      // what it is (its info's popover beside it: chat_pops_node's), what is done with it ("…": the menu a row of the sidebar has)
      k.box(fn(b) {
        let button = @sf.icon_button_node(b, "info", fn() { @sf.t("web-pages.chat.info") }, fn() {
          chat_own.info_open.set(!chat_own.info_open.untracked())
        }, tips~)
        chat_info_pop_node(b, src, r, view, stint, Some(button))
      })
      |> ignore
      k.box(fn(b) {
        let me : Ref[@view.View?] = Ref(None)
        me.val = Some(
          @sf.icon_button_node(b, "more", fn() { @sf.t("common.more") }, fn() {
            let extra = @sfpages.chat_extra_items(src, r, @signals.untracked(chat))
            match me.val {
              Some(at) => @sfpages.open_chat_menu(src, @signals.untracked(scope), r, extra, from=Node(at), along=End)
              None => ()
            }
          }, tips~),
        )
      })
      |> ignore
    })
    |> ignore
    // the side panel's switch while it is closed: standalone 36×36 liquid glass circle matching macOS 26 Tahoe sidebar toggle
    let panel_closed_with_switch = fn() {
      match view() {
        Some(v) => side_of(v).0.length() == 0 && v.agents.length() > 0
        None => false
      }
    }
    slot.show(
      panel_closed_with_switch,
      along_row=true,
      fn(b) {
        @sf.bar_pill_group_node(b, height=36.0, pad=2.0, gap=0.0, fn(p) {
          @sf.icon_button_node(p, "panel-open", fn() { @sf.t("web-pages.chat.openPanel") }, fn() {
            match @signals.untracked(view) {
              Some(v) if v.agents.length() > 0 => side_change(src, r, "open", Some(v.agents[0].key))
              _ => ()
            }
          }, tips~, shortcut="chat.history")
          |> ignore
        })
        |> ignore
      },
    )
  })
}

///|
// kept across runs: a value (no field of it changes)
let wide_subchats_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=false)

///|
/// Active controls strip directly above the composer on Medium / Large screens (isomorphic with Small's
/// `chat_composer_bar_node`):
/// - Left: frequent controls (Agent + Station tiles via `wide_agent_tile`, or `wide_station_tag` when no agent)
/// - Right: live/active controls (Active Jobs, Driven Screen, Led Sub-chats) under a single `show` so ordinary chats
///   with none pay at most one idle slot node. Popovers for Jobs and Sub-chats anchor upward (`side=Top`).
fn wide_composer_bar_node(
  o : @view.View,
  src : Source,
  r : ChatRef,
  tips : @sf.TipLayer,
  stint : () -> Int,
) -> Unit {
  let view = fn() { @sfbase.chat_view_now(src, r) }
  let station_held = @sfbase.station_mark_held(src, r.station)
  let station = fn() { station_held.get() }
  let station_key = fn() {
    match station() {
      Some(s) => "\{s.name}\u{1}\{s.emoji}\u{1}\{s.icon}"
      None => ""
    }
  }
  let via = fn() {
    match station() {
      Some(s) => s.via
      None => ""
    }
  }
  let agents = fn() {
    match view() {
      Some(v) => v.agents
      None => []
    }
  }
  let jobs_held = @sfbase.topic_value_held(src, "chatJobs", chat_jobs_summary_params(r))
  let jobs = fn() { jobs_held.get() }
  let has_jobs = fn() { flag(jobs(), "hasJobs") || items(jobs(), "jobs").length() > 0 }
  let alarm = fn() { if has_jobs() { text(jobs(), "alarm") } else { "" } }
  let driven = fn() {
    match view() {
      Some(v) => chat_screens_driven(v.screens)
      None => false
    }
  }
  let led_subchats = fn() {
    match view() {
      Some(v) => @sfpages.led_subchats(v.opened)
      None => []
    }
  }
  let has_subchats = fn() { led_subchats().length() > 0 }
  let subchats_tone = fn() {
    match view() {
      Some(v) => @sfpages.opened_summary_tone(v.opened)
      None => ""
    }
  }
  let own = fn() { !@sf.native_on() }
  let has_right = fn() { (own() && (has_jobs() || driven())) || has_subchats() }
  o
  .row(Is(true))
  .fits(Is(true))
  .min_height(Is(Some(36.0)))
  .lines_up(Is(Some(Middle)))
  .gap(Is(6.0))
  .padding(Is((2.0, 0.0, 2.0, 6.0)))
  |> ignore
  // Left group: frequent Station + Agent controls grouped by station under a single `each` (no idle show/pick slots)
  o.each(
    at_once=true,
    fn() {
      let all = agents()
      if all.length() > 0 {
        @sfpages.group_agents_by_station(all, r.station).map(fn(g) { (Some(g), "") })
      } else {
        let sk = station_key()
        if view() is Some(_) && station() is Some(_) {
          [(None, sk)]
        } else {
          []
        }
      }
    },
    fn(item) {
      match item.0 {
        Some(g) => {
          let ags = g.agents.map(fn(a) { "\{a.key}\u{1}\{a.maker}\u{1}\{a.runtime}\u{1}\{a.who}\u{1}\{a.model_name}\u{1}\{a.model_short}\u{1}\{a.effort}" }).join("\u{2}")
          "g\u{1}\{g.station}\u{1}\{ags}"
        }
        None => "s\u{1}\{item.1}"
      }
    },
    fn(k, it) {
      // (each capsule giving way along the row, its names cut only where the row has no room for them)
      k.row(Is(true)).fits(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      let (group_opt, _) = it.untracked()
      match group_opt {
        None =>
          match @signals.untracked(station) {
            Some(s) => wide_station_tag(k, r.station, s, via, tips, stint)
            None => ()
          }
        Some(group) => {
          let badge_of = fn(idx : Int, key : String) {
            fn() {
              match it.get().0 {
                Some(g) if idx < g.agents.length() && g.agents[idx].key == key => g.agents[idx].badge
                _ => ""
              }
            }
          }
          let marked_of = fn(key : String) {
            fn() {
              let front = match view() {
                Some(v) => side_of(v).1
                None => ""
              }
              agents().length() > 1 && front == key
            }
          }
          wide_station_group_tile(k, src, r, group, badge_of, marked_of, station, via, tips, stint)
        }
      }
    },
  )
  // Right group: live/active controls under a single `show`
  o.show(has_right, at_once=true, fn(right) {
    right.row(Is(true)).grow(Is(1.0)).lies_along(Is(End)).gap(Is(6.0)).lines_up(Is(Some(Middle))).shrink(Is(0.0)) |> ignore
    // Active Jobs pill
    right.show(fn() { own() && has_jobs() }, at_once=true, fn(b) {
      let button = @sf.action_box_node(b, fn() { @sf.t("web-pages.chat.services") }, fn(_) { jobs_pressed(src, r) }, fn(btn) {
        wide_glass_capsule(btn)
        btn.padding(Is((10.0, 0.0, 10.0, 0.0))).gap(Is(5.0)) |> ignore
        @sf.hover_ground_node(btn, extra=fn() { chat_own.jobs_open.get() })
        @sf.focus_ring_node(btn)
        let hot = fn() { @sf.lit_node(btn) || chat_own.jobs_open.get() }
        @sf.icon_node(btn, "web", 14.0, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
        btn.show(fn() { alarm() == "fail" || alarm() == "restart" }, at_once=true, fn(d) {
          d
          .width(Is(Some(6.0)))
          .height(Is(Some(6.0)))
          .radius(Is(3.0))
          .ground(By(fn() { if alarm() == "fail" { @sf.theme().p.red } else { @ui.tree_theme().color(Warn) } }))
          |> ignore
        })
        @sf.tip_node(tips, btn, fn() { @sf.t("web-pages.chat.services") }, shortcut="chat.jobs") |> ignore
      })
      if @signals.untracked(own) {
        chat_jobs_pop_node(b, src, r, Some(button))
      }
    })
    // Driven Screen pill
    right.show(fn() { own() && driven() }, at_once=true, fn(b) {
      @sf.action_box_node(b, fn() { @sf.t("web-pages.chat.screen") }, fn(at) {
        match @signals.untracked(view) {
          Some(v) => chat_remote_open(src, r, v, from=Node(at), along=End)
          None => ()
        }
      }, fn(btn) {
        wide_glass_capsule(btn)
        btn.padding(Is((10.0, 0.0, 10.0, 0.0))).gap(Is(5.0)) |> ignore
        @sf.hover_ground_node(btn)
        @sf.focus_ring_node(btn)
        let hot = fn() { @sf.lit_node(btn) }
        @sf.icon_node(btn, "monitor", 14.0, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
        btn.box(fn(d) {
          d
          .width(Is(Some(6.0)))
          .height(Is(Some(6.0)))
          .radius(Is(3.0))
          .ground(By(fn() { @sf.theme().p.primary }))
          |> ignore
        })
        |> ignore
        @sf.tip_node(tips, btn, fn() { @sf.t("web-pages.chat.screen") }, shortcut="chat.screen") |> ignore
      })
      |> ignore
    })
    // Led Sub-chats pill
    right.show(has_subchats, at_once=true, fn(b) {
      let label = fn() { @sf.t("web-pages.chat.subchats") }
      let button = @sf.action_box_node(b, label, fn(_) { toggle_subchats_pop() }, fn(btn) {
        wide_glass_capsule(btn)
        btn.padding(Is((11.0, 0.0, 11.0, 0.0))).gap(Is(5.0)) |> ignore
        @sf.hover_ground_node(btn, extra=fn() { chat_own.subchats_open.get() })
        @sf.focus_ring_node(btn)
        let hot = fn() { @sf.lit_node(btn) || chat_own.subchats_open.get() }
        @sf.icon_node(btn, "spawned", 14.0, By(fn() { if hot() { @sf.theme().p.text } else { @sf.theme().p.muted } })) |> ignore
        @sf.words_node(btn, label, fn() { wide_subchats_words }) |> ignore
        @sf.words_node(btn, fn() { led_subchats().length().to_string() }, fn() {
          if hot() {
            wide_subchats_count_hot
          } else {
            wide_subchats_count
          }
        })
        |> ignore
        btn.show(at_once=true, fn() { subchats_tone() != "" }, fn(d) {
          d
          .width(Is(Some(6.0)))
          .height(Is(Some(6.0)))
          .radius(Is(3.0))
          .ground(By(fn() {
            match subchats_tone() {
              "fail" => @sf.theme().p.red
              "need" => @ui.tree_theme().color(Warn)
              _ => @sf.theme().p.online
            }
          }))
          |> ignore
        })
        @sf.tip_node(tips, btn, label) |> ignore
      })
      if @signals.untracked(own) {
        chat_subchats_pop_node(b, src, r, view, Some(button))
      }
    })
  })
}
