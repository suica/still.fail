// Home's chats as a board (sfbase's board.mbt) made once as nodes: on the page's own paper, no frame round a column,
// its title standing on the paper and its cards under it; a card the chat's title, where it stands now, and where it
// runs, who and what is in it. Wide (720 and over) every column side by side under the board's bar (its filter, how it
// is grouped, 新待办; the list is the rail's 对话 on 中屏 and 大屏, Home's own key on 小屏), going sideways where they
// have not the room; a card pressed opens its chat beside the board at board_beside_from and over (the shell's,
// `beside`, as wide as its edge is dragged), else as its page. Narrow a column at a time under chips choosing it, the
// columns on a track a finger swipes across. No card is dragged on any screen (the user, 2026-11-17): a card is in the
// column its chat stands in and goes to another as its chat goes on (its node flies there: View::shared); a draft is
// started by its 开始 or its menu, a chat archived by its 归档, 归档已读 or its menu. What the board shows and keeps is
// the workspace's in view, as this device keeps it (sfbase's board.mbt): its drafts, how it is grouped, the stations a
// draft may go to (its stations' rows: none made up).

///|
/// What a column shows: a draft of 待派发's or a chat's card, by its key.
#derive(Eq, Hash)
priv enum BoardKey {
  DraftKey(String)
  ChatKey(String)
}

///|
/// The board's own: the field 新待办 is written in, the station it goes to.
priv struct BoardOwn {
  src : Source
  /// the workspace in view ("" none), and how its board is grouped
  ws : () -> String
  group : () -> String
  /// whether a card is the one picked (its chat beside the board), read by key: a card told only as it comes to be so
  /// or stops being so (View::selected)
  mut picked : (String) -> Bool
  mut side : () -> Bool
  /// whether the frame offers the chat beside the board (the wide frame's pane, sfdesk's), whatever the width now
  mut beside_offered : Bool
  /// the columns brought sideways so that column `key`'s shows whole (beside the chat as it opens), "" the first
  mut reveal : (String) -> Unit
  /// the columns put back to their start (another grouping)
  mut to_start : () -> Unit
  /// a draft started (its 开始 pressed, or its menu's 立即派发): its key and where its card was in the window then: its
  /// chat's card flies in from there as it comes, once
  mut start_from : (String, (Double, Double, Double, Double))?
  /// a draft just written: its key and where the card it was written in was, which its card grows from as it comes, once
  mut added_from : (String, (Double, Double, Double, Double))?
  /// how many times the room the line to write a draft in stands in was put away by what was written in it (not
  /// closed: let go at once, its draft come in its place, and made anew closed)
  room_made : @signals.Signal[Int]
  /// the stations a draft may go to (the workspace's), the one chosen for the next ("" none chosen: the first)
  stations : () -> Array[@sfbase.StationChoice]
  /// the chats and the stations by their keys (View::keyed_by): a card reads its own, told only as that one changes,
  /// never as another does
  items_by : @signals.KeyedList[String, ChatItem]
  /// the chats the board shows, as its columns are worked out of them (what 归档已读 counts and puts away)
  items : () -> Array[ChatItem]
  /// the drafts by their ids, worked out as they change, in the same change: a draft started or deleted is gone from its
  /// card as the card leaves (a keyed list follows its source a reaction after, the card leaving with its words then);
  /// the device's own few, read by the drafts' cards alone
  drafts_by : () -> Map[String, @sfbase.BoardDraft]
  stations_by : @signals.KeyedList[String, @sfbase.StationChoice]
  /// the viewer as the board names them among the people (by person)
  me : () -> String
  /// the columns the board shows now (board_columns', its empty ones left out where 显示空列 is off), and the cards of
  /// each by its key (board_cards'), each worked out once for all that reads it, told only as it comes out otherwise
  mut columns : () -> Array[(String, String)]
  mut cards_of : (String) -> Array[BoardKey]
  /// The task currently being written, whose files have their own persisted composer.
  draft_id : @signals.Signal[String]
  station : @signals.Signal[String]
  /// 已归档 chosen in the board's filter's menu (the frame's: its page, or its list in the board's place)
  archived : () -> Unit
  /// the page's time on top, what the faces' and the stations' pictures are asked for on
  stint : () -> Int
}

///|
/// The station the next draft goes to: the one chosen where it is one of the workspace's, else its first ("" none).
fn board_station_now(own : BoardOwn) -> String {
  let s = own.station.get()
  if s != "" && own.stations_by.get(s) is Some(_) {
    s
  } else {
    own.stations_by.keys().get(0).unwrap_or("")
  }
}

///|
/// 待派发's line to write in opened, where the workspace has a station for a draft to go to; else why not said.
fn board_open_add(own : BoardOwn) -> Bool {
  if @signals.untracked(own.stations).is_empty() {
    @sfbase.toast_later(@sf.t("web-main.board.no_station"))
    false
  } else {
    @sfbase.board_adding.set(true)
    true
  }
}

///|
/// New 待派发 from the bar or the new action: bring its column into view and write there.
fn board_new(own : BoardOwn) -> Unit {
  let was_adding = @sfbase.board_adding.untracked()
  if board_open_add(own) {
    if @signals.untracked(own.group) != "state" {
      @sfbase.set_board_group(own.src, @signals.untracked(own.ws), "state")
    }
    @sfbase.board_lane.set("draft")
    (own.reveal)("draft")
    // An unfinished line is kept; the action brings the cursor back to it.
    if was_adding {
      let ws = @signals.untracked(own.ws)
      @signals.after_flush(fn() {
        @signals.untracked(fn() { @sfbase.writing(own.src, @sfbase.board_file_key(ws, own.draft_id.get())) }).field.focus()
      })
    }
  }
}

///|
/// The board's words for what Home's list has none for yet.
fn board_words(key : String) -> String {
  match key {
    "by-state" => @sf.t("web-main.board.by_state")
    "by-station" => @sf.t("web-main.board.by_station")
    "by-person" => @sf.t("web-main.board.by_person")
    "display" => @sf.t("web-main.board.display")
    "group-by" => @sf.t("web-main.board.group_by")
    "show-empty" => @sf.t("web-main.board.show_empty")
    "new" => @sf.t("web-main.board.new")
    "new-here" => @sf.t("web-main.board.new_here")
    "add" => @sf.t("web-main.board.add")
    "dispatch" => @sf.t("web-main.board.dispatch")
    "edit" => @sf.t("web-main.board.edit")
    "cancel" => @sf.t("web-main.board.cancel")
    "goes-on" => @sf.t("web-main.board.goes_on")
    "start" => @sf.t("web-main.board.start")
    "start-now" => @sf.t("web-main.board.start_now")
    "delete" => @sf.t("web-main.board.delete")
    "archive" => @sf.t("web-main.board.archive")
    "placeholder" => @sf.t("web-main.board.placeholder")
    "empty" => @sf.t("web-main.board.empty")
    "empty-draft" => @sf.t("web-main.board.empty_draft")
    "pinned" => @sf.t("web-main.board.pinned")
    _ => key
  }
}

///|
/// How wide a column is at least, and the room between columns and round the board.
let board_col_least : Double = 252.0

///|
let board_col_most : Double = 336.0

///|
let board_gap : Double = 16.0

///|
let board_pad : Double = 16.0

///|
/// How far in from its end the board's own bar keeps what stands there: past the arc of a window's corner it may stand
/// in (16 round).
let board_bar_end : Double = 20.0

///|
/// From what width the board has the chat of the card picked beside it (as wide as sfbase's board_chat_w_of says,
/// its edge dragged between board_chat_least and board_chat_most).
pub let board_beside_from : Double = 1040.0

///|
/// How tall the board's bar is (the pane's bars': @sf.wide_bar_h's 50).
let board_bar_h : Double = 50.0

///|
/// The card's padding, and its corner: a card's (@sf.card_corner, 26: the surface of a face 20 across 16 in, so what
/// stands in its corners is concentric with them), what stands in its top end corner (a round key 28 across, as far in
/// from both its edges as its corner allows) worked out of it.
let card_pad : Double = 16.0

///|
let card_key : Double = 28.0

///|
fn card_key_in() -> Double {
  @sf.card_corner - card_key / 2.0
}

///|
/// The lanes the board shows now by how it is grouped, each its key and words: by state the five; by station each
/// station a draft or a chat is on; by person each one in a chat.
fn board_columns(own : BoardOwn, items : Array[ChatItem], drafts : Array[@sfbase.BoardDraft]) -> Array[(String, String)] {
  match (own.group)() {
    "station" => {
      let cols : Array[(String, String)] = []
      let add = fn(st : String, name : String) {
        if st != "" && !cols.iter().any(fn(c) { c.0 == "station:" + st }) {
          cols.push(("station:" + st, if name == "" { st } else { name }))
        }
      }
      // (the workspace's stations as their rows name them, then any a draft or a chat is on besides)
      for c in (own.stations)() {
        add(c.station, c.name)
      }
      for d in drafts {
        add(d.station, d.station_name)
      }
      for i in items {
        add(i.station, i.station_name)
      }
      cols
    }
    "person" => {
      let cols : Array[(String, String)] = []
      let add = fn(n : String) {
        if !cols.iter().any(fn(c) { c.0 == "person:" + n }) {
          cols.push(("person:" + n, n))
        }
      }
      // (the viewer first)
      let me = (own.me)()
      add(me)
      for i in items {
        for n in @sfbase.board_people_of(i, me) {
          add(n)
        }
      }
      cols
    }
    _ => @sfbase.board_lanes.map(fn(l) { (l, @sfbase.board_lane_words(l)) })
  }
}

///|
/// Whether column `col` (board_columns') lists chat `i`: 待派发 none; by station those on it; by person those of its
/// one (`me` the viewer as the board names them, asked only there); by state those standing in it.
fn board_holds(col : String, i : ChatItem, me : () -> String) -> Bool {
  if col == "draft" {
    false
  } else if col.has_prefix("station:") {
    i.station == col.exact_view(start=8).to_owned()
  } else if col.has_prefix("person:") {
    @sfbase.board_people_of(i, me()).contains(col.exact_view(start=7).to_owned())
  } else {
    @sfbase.board_lane_of(i) == col
  }
}

///|
/// The cards of column `col` (board_columns'), in order: 待派发's drafts, then its chats (pinned first; in 待收口 then
/// those just delivered and not read, then those read: what is new on top, what is only to put away under it).
fn board_cards(
  col : String,
  items : Array[ChatItem],
  drafts : Array[@sfbase.BoardDraft],
  me : () -> String,
) -> Array[BoardKey] {
  let out : Array[BoardKey] = []
  if col == "draft" {
    for d in drafts {
      out.push(DraftKey(d.id))
    }
  } else if col.has_prefix("station:") {
    let st = col.exact_view(start=8).to_owned()
    for d in drafts {
      if d.station == st {
        out.push(DraftKey(d.id))
      }
    }
  } else if col.has_prefix("person:") {
    if col.exact_view(start=7).to_owned() == me() {
      for d in drafts {
        out.push(DraftKey(d.id))
      }
    }
  }
  let chats = items.filter(fn(i) { board_holds(col, i, me) })
  for i in chats {
    if i.pinned == Some(true) {
      out.push(ChatKey(@sfbase.row_name(i)))
    }
  }
  let fresh = fn(i : ChatItem) { i.unread }
  if col == "done" {
    for i in chats {
      if i.pinned != Some(true) && fresh(i) {
        out.push(ChatKey(@sfbase.row_name(i)))
      }
    }
    for i in chats {
      if i.pinned != Some(true) && !fresh(i) {
        out.push(ChatKey(@sfbase.row_name(i)))
      }
    }
    return out
  }
  for i in chats {
    if i.pinned != Some(true) {
      out.push(ChatKey(@sfbase.row_name(i)))
    }
  }
  out
}

///|
/// 待收口's chats read put away at once (归档已读, sfbase's board_archivable_settled): each archived as its card's 归档
/// archives it, the chat open beside the board closed where it is one of them, one toast saying how many and taking
/// them all back.
fn board_archive_settled(src : Source, items : Array[ChatItem]) -> Unit {
  let gone = @sfbase.board_archivable_settled(items)
  guard gone.length() > 0 else { return }
  let asked : Array[Map[String, Json]] = []
  for i in gone {
    if @sfbase.board_pick.untracked().map(fn(p) { @sfbase.row_is(i, p) }).unwrap_or(false) {
      @sfbase.board_pick.set(None)
    }
    leave_archived(i)
    let params : Map[String, Json] = {
      "station": Json::string(i.station),
      "session": Json::string(i.session),
      "archived": Json::boolean(true),
    }
    match i.thread {
      Some(th) => params["thread"] = Json::number(th)
      None => ()
    }
    asked.push(params)
    @sfbase.act(src, @sf.t("android-chat.archive.verb"), "", "chat.archive", Json::object(params), at_once=true)
  }
  // (one toast for all of them, its 撤销 asking each back: what one row's archive says, for the whole press)
  @sfbase.toast_later(
    @sf.t("web-main.board.archived_read", args=[("n", gone.length().to_string())]),
    action=@sf.t("android-chat.archived.undo"),
    run=fn() {
      for k, params in asked {
        let back = params.copy()
        back["archived"] = Json::boolean(false)
        @sfbase.act(src, @sf.t("android-misc.archive.restoreWhat"), "", "chat.archive", Json::object(back), done=if k == asked.length() - 1 { @sf.t("android-misc.archive.restored") } else { "" }, at_once=true)
      }
    },
  )
}


///|
/// Home's chats as the board in `v`, of the workspace in view (`workspace`): `width` how wide it is given (its
/// arrangement's), `top` the room over it (a bar of the shell's over it: none where the board has its own), `foot` the
/// room under it, `bar` whether it has its own bar (wide: its own; narrow, under Home's), `beside` the chat of a card
/// pressed made beside it (wide and `board_beside_from` wide: the shell's; none: the card opens its chat's page),
/// `archive` what 已归档 in its bar's filter's menu opens (the archive's page where none is said); pictures asked for on
/// `stint`. Narrow, it reaches the window's foot and its cards pass under the bars over it and under it (`top` and `foot`
/// what they cover), as Home's list does; its chips choosing a column under Home's bar, on its glass (board_chips_node).
pub fn board_node(
  v : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  width : () -> Double,
  top? : () -> Double = fn() { 0.0 },
  foot? : () -> Double = fn() { 0.0 },
  beside? : (@view.View, ChatRef) -> Unit,
  ground? : () -> Int64 = fn() { @sf.theme().p.bg },
  columns? : Bool = beside is Some(_),
  bar_frame? : (@view.View, (@view.View) -> Unit) -> Unit,
  archive? : () -> Unit = fn() { open_page(Archived) },
  stint? : () -> Int = fn() { 0 },
) -> Unit {
  let ws = fn() { workspace().map(fn(w) { w.id }).unwrap_or("") }
  // (the chats, the drafts and the workspace's stations a draft may go to, as their rows say them: each worked out once
  // for all that reads it, told only as it comes out otherwise)
  let items_now = @signals.computed(fn(_) {
    match workspace() {
      Some(w) => @sfbase.board_items(src, w.id)
      None => []
    }
  })
  let items = fn() { items_now.get() }
  let drafts_now = @signals.computed(fn(_) { @sfbase.board_drafts_of(src, ws()) })
  let drafts = fn() { drafts_now.get() }
  let drafts_map = @signals.computed(fn(_) { Map::from_array(drafts().map(fn(d) { (d.id, d) })) })
  let stations_now = @signals.computed(fn(_) {
    let rows = match workspace() {
      Some(w) =>
        match @sfbase.station_rows(src, w.id).value {
          Some(Array(a)) => a
          _ => []
        }
      None => []
    }
    rows
    .map(fn(r) -> @sfbase.StationChoice {
      let one = Some(r)
      { station: text(one, "station"), name: text(one, "name"), emoji: text(one, "emoji"), icon: text(one, "icon") }
    })
    .filter(fn(c) { c.station != "" && c.name != "" })
  })
  let me_now = @signals.computed(fn(_) { @sfbase.board_me_of(items()) })
  let own : BoardOwn = {
    src,
    ws,
    group: fn() { @sfbase.board_group_of(src, ws()) },
    picked: fn(_) { false },
    side: fn() { false },
    beside_offered: false,
    reveal: fn(_) {  },
    to_start: fn() {  },
    start_from: None,
    added_from: None,
    room_made: @signals.signal(0),
    stations: fn() { stations_now.get() },
    items_by: v.keyed_by(items, @sfbase.row_name),
    items,
    drafts_by: fn() { drafts_map.get() },
    stations_by: v.keyed_by(fn() { stations_now.get() }, fn(c) { c.station }),
    me: fn() { me_now.get() },
    columns: fn() { [] },
    cards_of: fn(_) { [] },
    draft_id: @signals.signal(@sfbase.board_writing_id(@signals.untracked(ws))),
    station: @signals.signal(""),
    archived: archive,
    stint,
  }
  // (another workspace in view: the line its own task's, as it was left there)
  v.reacts(ws, fn(w) { own.draft_id.set(@sfbase.board_writing_id(w)) }, at_start=false)
  let raw_columns_now = @signals.computed(fn(_) { board_columns(own, items(), drafts()) })
  // (every column's cards and every state's (a narrow board's chips count them whatever the grouping), worked out
  // together as a chat or a draft changes; a map made anew each time: each column's own computed says whether its
  // cards came out otherwise)
  let cards_now = @signals.computed_ref(fn(_) {
    let all = items()
    let ds = drafts()
    let out : Map[String, Array[BoardKey]] = Map([])
    for c in raw_columns_now.get() {
      out[c.0] = board_cards(c.0, all, ds, own.me)
    }
    for l in @sfbase.board_lanes {
      if !out.contains(l) {
        out[l] = board_cards(l, all, ds, own.me)
      }
    }
    out
  })
  own.cards_of = fn(key) { cards_now.get().get(key).unwrap_or([]) }
  // (its empty columns left out where the workspace's board says so (显示空列 off), but 待派发 while a draft is being
  // written in it: 新待办 brings it in; shown, as by default, the cards not read here, so a chat's change tells
  // nothing to the columns)
  let columns_now = @signals.computed(fn(_) {
    let all = raw_columns_now.get()
    if @sfbase.board_show_empty_of(own.src, (own.ws)()) {
      all
    } else {
      let adding = @sfbase.board_adding.get()
      let cards = cards_now.get()
      all.filter(fn(c) { (c.0 == "draft" && adding) || cards.get(c.0).map(fn(k) { !k.is_empty() }).unwrap_or(false) })
    }
  })
  own.columns = fn() { columns_now.get() }
  // (the chat picked, as the card its row is: looked for only while one is picked)
  own.picked = v.selected(fn() {
    match @sfbase.board_pick.get() {
      Some(p) => items().iter().find_first(fn(i) { @sfbase.row_is(i, p) }).map(@sfbase.row_name)
      None => None
    }
  })
  // The frame passes its new action here while Home is the board; the person's keymap still chooses its keys.
  v.on_action("chat.new", fn(_) {
    board_new(own)
    true
  }, can=fn() { @sfbase.board_on_now(src) && app.nav.top() is Home }) |> ignore
  v.grow(Is(1.0)).min_height(Is(Some(0.0))).ground(By(ground)) |> ignore
  // (the workspace's stations read as long as the board shows, as its opening asked them (sfbase's board_opens): the
  // line to write a draft in, and its choice of a station, whole as it comes, whichever column shows)
  v.reacts(fn() { (own.stations)().length() }, fn(_) {  })
  // (columns side by side under the board's bar in a frame's pane or panel; Home's on a phone a column at a time)
  v.pick(fn() { columns }, fn(p, wide) {
    p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
    if wide {
      p.padding(By(fn() { (0.0, top(), 0.0, foot()) })) |> ignore
      board_wide(p, src, tips, own, width, beside, bar_frame)
    } else {
      board_narrow(p, src, tips, own, top, foot)
    }
  })
}

///|
/// The wide board: its bar over its columns side by side (whole columns where they have not all the room, going
/// sideways to the rest); the chat of the card picked beside all of it, the window's whole height, where there is the
/// room. The chat slides in and out from the board's end (a Move as far as it is wide). The columns keep their width as
/// the chat opens or closes; only the least sideways scroll needed to keep the chosen column in sight moves with it.
/// Open and still, its edge at its start dragged for its width (sfbase's board_chat_w_of: board_chat_least to
/// board_chat_most, a whole column and the board's margins always left beside it), the columns keeping theirs; pressed
/// twice, its own width again.
fn board_wide(
  p : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  width : () -> Double,
  beside : ((@view.View, ChatRef) -> Unit)?,
  bar_frame : ((@view.View, (@view.View) -> Unit) -> Unit)?,
) -> Unit {
  own.side = fn() { beside is Some(_) && width() >= board_beside_from }
  own.beside_offered = beside is Some(_)
  let split = fn() { beside is Some(_) && width() >= board_beside_from && @sfbase.board_pick.get() is Some(_) }
  // (how wide the chat beside them is: as its edge was dragged or kept, within what leaves a whole column and the
  // board's margins beside it)
  let beside_most = fn() {
    dmax(@sfbase.board_chat_least, dmin(@sfbase.board_chat_most, width() - (2.0 * board_pad + board_col_least)))
  }
  let beside_w = fn() { dmax(@sfbase.board_chat_least, dmin(beside_most(), @sfbase.board_chat_w_of(src))) }
  // (a Move as far as the chat is wide as it sets off)
  let spec = fn() { @motion.moved(over=@signals.untracked(beside_w)) }
  // (how far open the chat beside it is, 0 to 1; the chat it shows, kept as it slides out; where the columns are
  // brought sideways from and to, how far along that is)
  let opened = @motion.Way::new(if @signals.untracked(split) { 1.0 } else { 0.0 })
  let shown : @signals.Signal[ChatRef?] = @signals.signal(@signals.untracked(fn() { @sfbase.board_pick.get() }))
  let glide = @motion.Way::new(1.0)
  let glides = Ref((0.0, 0.0))
  let count = fn() { (own.columns)().length() }
  // (how far along a way is at `t`, from where it set out to where it goes: 1 where it is not going)
  let along = fn(way : @motion.Way, t : Double) -> Double {
    if !way.goes_at(t) {
      return 1.0
    }
    let from = way.value_at(way.starts_at())
    let to = way.target()
    if to == from {
      1.0
    } else {
      (way.value_at(t) - from) / (to - from)
    }
  }
  // (the chat changes how much of the board is seen, not the width of every column: opening or closing it must not
  // reflow all the cards under the reader)
  let laid_w = fn() { board_col_w(width(), count()) }
  p.row(Is(true)) |> ignore
  p.box(fn(left) {
    left.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    match bar_frame {
      // (laid out as the frame lays out a bar where it stands: the wide frame's pane's, as a chat's bar there)
      Some(frame) => frame(left, fn(bar) { board_bar_items(bar, own, apart=true) })
      None => board_bar(left, own)
    }
    left.box(fn(area) {
      area.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
      // (a card going to another column (View::shared, board_chat_card) drawn within the board as it goes, never over
      // its bar, the chat beside it or the window's edge round it)
      area.flights_within() |> ignore
      // (short of the chat beside it by as much as that chat's edge reaches over the board: a press there the edge's
      // alone)
      area.margin(By(fn() { (0.0, 0.0, if split() { board_edge_reach } else { 0.0 }, 0.0) })) |> ignore
      let across = @view.Scroll::across()
      // (the part of the scroll drawn apart from its anchor while the columns are on their way)
      let glide_extra = fn(at : Double) {
        if glide.goes_at(at) {
          let (from, to) = glides.val
          from - from.min(to) + (to - from) * along(glide, at)
        } else {
          0.0
        }
      }
      // (anchor at the lesser end so it stays in range while the chat opens or closes; draw the rest of the scroll
      // over the way, then put it at the destination. Anchoring at the old end on close let the growing viewport clamp
      // it before the way had finished.)
      let glide_to = fn(to : Double) {
        let at = area.cause_at()
        let now = across.at(area.tree) + glide_extra(at)
        // (as far as it goes there once laid out so)
        let to = if to < 0.0 { 0.0 } else { to }
        if (to - now).abs() < 0.5 {
          glide.put(1.0)
          across.put(to)
          return
        }
        across.put(now.min(to))
        glides.val = (now, to)
        glide.put(0.0)
        glide.go(1.0, spec(), at~)
        let end = glide.end()
        area.at_moment(end, fn() { if glide.end() == end { across.put(to) } }) |> ignore
      }
      // (where the columns are to be for column `key`'s to show whole, the chat beside them as it is to be)
      own.reveal = fn(key) {
        let cols = @signals.untracked(own.columns)
        let i = cols.search_by(fn(c) { c.0 == key }).unwrap_or(0)
        let r = width() -
          (if @signals.untracked(own.side) && key != "draft" { @signals.untracked(beside_w) + board_edge_reach } else { 0.0 })
        let w = laid_w()
        let now = across.at(area.tree) + glide_extra(area.cause_at())
        let stride = w + board_gap
        let start = i.to_double() * stride
        let end = start + w
        let room = r - 2.0 * board_pad
        // (only as far as needed, keeping the existing position where the column already fits)
        let to = if key == "draft" { 0.0 } else if start < now { start } else if end > now + room { end - room } else { now }
        glide_to(to)
      }
      own.to_start = fn() {
        glide.put(1.0)
        across.put(0.0)
      }
      // (both let go of with the area, as they were before it: reveal names `own`, which holds it, a ring native's
      // counting never frees)
      area.owns(fn() {
        own.reveal = fn(_) {  }
        own.to_start = fn() {  }
      })
      |> ignore
      // (the chat beside them opened or closed: its way starts at that moment)
      area.reacts(split, fn(open) {
        let at = area.cause_at()
        if open {
          shown.set(@sfbase.board_pick.untracked())
        }
        opened.go(if open { 1.0 } else { 0.0 }, spec(), at~)
        let end = opened.end()
        area.at_moment(end, fn() {
          if opened.end() == end && !@signals.untracked(split) {
            shown.set(None)
          }
        })
        |> ignore
        if !open {
          // (closed: no further than the columns go with the whole width)
          let w = board_col_w(width(), count())
          let n = count().to_double()
          let most = 2.0 * board_pad + n * w + (n - 1.0) * board_gap - width()
          let now = across.at(area.tree) + glide_extra(at)
          glide_to(if now > most { if most < 0.0 { 0.0 } else { most } } else { now })
        }
      }, at_start=false)
      // (the chat beside them made narrower or wider by its edge: the columns, their width kept, no further sideways than
      // they go in the room it leaves, none left empty at their end; put there at once, as the edge is in the hand)
      // (not as it opens or closes: the way above's)
      let was_w = Ref(0.0)
      area.reacts(fn() { if split() { beside_w() } else { 0.0 } }, fn(bw) {
        let was = was_w.val
        was_w.val = bw
        guard bw > 0.0 && was > 0.0 else { return }
        let r = width() - bw - board_edge_reach
        let n = count().to_double()
        let most = dmax(0.0, 2.0 * board_pad + n * laid_w() + (n - 1.0) * board_gap - r)
        if across.at(area.tree) > most {
          across.put(most)
        }
      }, at_start=false)
      // (another chat picked while it is open: shown in its place)
      area.reacts(fn() { @sfbase.board_pick.get() }, fn(r) { if r is Some(_) { shown.set(r) } }, at_start=false)
      area.scrolls(across, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(held) {
        held.min_height(Is(Some(0.0))) |> ignore
        held.box(fn(cols) {
          cols
          .row(Is(true))
          .gap(Is(board_gap))
          // (no room under them: each column's list reaches the pane's foot, its last card the foot's room in it)
          .padding(Is((board_pad, 4.0, board_pad, 0.0)))
          .min_height(Is(Some(0.0)))
          .grow(Is(1.0))
          // (on the columns' way sideways: what is left of it)
          .offset(By(fn() {
            glide.said()
            let t = cols.drawn_while(fn(at) { glide.goes_at(at) })
            if t == @double.infinity || !glide.goes_at(t) {
              (0.0, 0.0)
            } else {
              (-glide_extra(t), 0.0)
            }
          }))
          |> ignore
          cols.pick(own.group, fn(g, _group) {
            g.row(Is(true)).gap(Is(board_gap)).min_height(Is(Some(0.0))).grow(Is(1.0)) |> ignore
            g.each(
              fn() { (own.columns)() },
              fn(c) { c.0 },
              fn(col, c) {
                let key = @signals.untracked(fn() { c.get().0 })
                col.width(By(fn() { Some(laid_w()) })).lays_anew(By(laid_w)).shrink(Is(0.0))
                |> ignore
                board_column(col, src, tips, own, key, fn() { c.get().1 }, wide=true)
              },
              at_once=true,
            )
          }, at_once=true)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  match beside {
    Some(make) =>
      // (as wide as it is open, what it shows as wide as it is all the way: cut to its room as it slides, not once it is
      // there, its edge reaching out over the board)
      p.show(fn() { shown.get() is Some(_) }, fn(s) {
        s
        // det-ok(layout-drawn-while): split viewport between board (fixed laid_w columns) and beside chat (fixed beside_w inner) reshapes smoothly with no card or chat reflow
        .width(By(fn() { Some(beside_w() * opened.shown_on(s)) }))
        .shrink(Is(0.0))
        .min_height(Is(Some(0.0)))
        .clips(By(fn() { opened.shown_on(s) < 1.0 }))
        |> ignore
        s.box(fn(inner) {
          // (laid out anew at once at each width its edge drags it to, as the window made another size is: its chat's
          // words broken again in that frame, no move of its rows: View::lays_anew)
          inner.width(By(fn() { Some(beside_w()) })).lays_anew(By(fn() { beside_w() })).grow(Is(1.0)).min_height(Is(Some(0.0)))
          |> ignore
          inner.pick(fn() { shown.get() }, fn(b, r) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            match r {
              Some(r) => make(b, r)
              None => ()
            }
          }, at_once=true)
        })
        |> ignore
        // its edge, while it is open and still
        s.show(at_once=true, fn() { split() && opened.shown_on(s) >= 1.0 }, fn(e) {
          board_beside_edge(e, src, tips, beside_w, beside_most)
        })
      }, at_once=true)
    None => ()
  }
}

///|
/// The edge of the chat beside the board in `e` (over its start, handle_out of it over the board), as a side panel's is
/// (sfdesk's side_edge_node): its line and bar only under a pointer, focused or in hand, nothing drawn at rest; dragged,
/// its width, kept as it is let go (sfbase's set_board_chat_w), dragged on past either end its line drawn aside as a
/// string, sprung back as it is let go; pressed twice, its own width again; pressed once, nothing (× in its bar closes
/// it).
fn board_beside_edge(
  e : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  width : () -> Double,
  most : () -> Double,
) -> Unit {
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  e.over(Is(true)).width(Is(Some(@sf.handle_w))).offset(Is((-board_edge_reach, 0.0))) |> ignore
  let pull = @sf.EdgePull::new()
  let edge = @sf.edge_node(
    e,
    fn() { @sf.t("web-pages.chat.resizePanel") },
    width,
    fn() { @sfbase.board_chat_least },
    most,
    Left,
    fn(said, _) {
      match said {
        Dragging(x) => @sfbase.set_board_chat_w(src, Some(x), save=false)
        Dropped(x) => @sfbase.set_board_chat_w(src, Some(x), save=true)
        Twice => @sfbase.set_board_chat_w(src, None, save=true)
        Pressed | Untouched => ()
      }
    },
    fn(h) { held.set(h) },
    tips~,
    side=Left,
    pull~,
  )
  edge.box(fn(g) {
    g.over(Is(true)) |> ignore
    @sf.edge_look_node(
      g,
      fn() { false },
      fn() { edge.pointed() || edge.focus_shown() || held.get() },
      fn() { held.get() },
      pull~,
    )
    |> ignore
  })
  |> ignore
}

///|
/// How far the edge of the chat beside the board reaches over the board (board_beside_edge), as a side panel's over its
/// page (sfdesk's side_edge_node).
let board_edge_reach : Double = @sf.handle_out

///|
/// How wide each of `n` columns is in `room`: as many whole columns as `room` holds at the least, sharing it, at most
/// board_col_most (the rest sideways, never a column cut at the edge of what shows).
fn board_col_w(room : Double, n : Int) -> Double {
  let avail = room - 2.0 * board_pad
  let fits = ((avail + board_gap) / (board_col_least + board_gap)).floor().to_int()
  let shown = if fits < 1 { 1 } else if fits > n { n } else { fits }
  let fit = (avail - board_gap * (shown - 1).to_double()) / shown.to_double()
  // (all of them in the room: at most so wide, at the start; some going sideways: those that show filling it whole, so
  // the next one starts past its edge, never half in it)
  if shown >= n && fit > board_col_most {
    board_col_most
  } else if fit < board_col_least {
    board_col_least
  } else {
    fit
  }
}

///|
/// The wide board's bar: all it holds at its end (board_bar_items'), its start left empty.
fn board_bar(p : @view.View, own : BoardOwn) -> Unit {
  p.box(fn(bar) {
    bar
    .row(Is(true))
    .height(Is(Some(board_bar_h)))
    .shrink(Is(0.0))
    .gap(Is(10.0))
    .lines_up(Is(Some(Middle)))
    // (its end clear of the window's corner where it stands in it: the sidebar closed beside the board)
    .padding(Is((board_pad, 0.0, board_bar_end, 0.0)))
    |> ignore
    board_bar_items(bar, own, apart=true)
  })
  |> ignore
}

///|
/// What the board's bar holds, in `bar` (its own, or a frame's bar it is given: the tape's page's), all at its end, as
/// Linear's board has it: the filter, a quiet key; 显示, what opens how the board is shown (board_display); 新待办 (the
/// list again is the rail's 对话 on 中屏 and 大屏, Home's own key on 小屏). The filter and 显示 say on themselves what is chosen otherwise than as the board starts
/// (我参与的; 按机器 or 按成员, the empty columns left out). `apart`: the rest of the bar left empty before them.
fn board_bar_items(bar : @view.View, own : BoardOwn, apart~ : Bool) -> Unit {
  bar.box(fn(row) {
    // (新待办 the one to leave where the bar has not the room for all of it: 待派发's ＋ writes one as well)
    row.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).fits(Is(true)) |> ignore
    // (as wide as the bar gives it, not as all it holds: what has not the room then leaves)
    if apart {
      row.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      row.box(fn(g) { g.grow(Is(1.0)).min_width(Is(Some(0.0))) |> ignore }) |> ignore
    }
    board_filter_key(row, own)
    board_display_key(row, own)
    @sf.button_node(row, fn() { board_words("new") }, fn() { board_new(own) }, icon="plus")
    .drops(Is(1))
    |> ignore
  })
  |> ignore
}

///|
/// The board's filter, as the sidebar's filter is: its menu the board's (filter_menu's `in_board`: 全部会话 or 我参与的 on
/// it; 已隐藏 the list's, 已归档 the frame's, BoardOwn's `archived`). A quiet key while it shows all of them; narrowed to
/// 我参与的, a button saying so.
fn board_filter_key(bar : @view.View, own : BoardOwn) -> Unit {
  let src = own.src
  let open = fn(k : @view.View) {
    guard @signals.untracked(fn() { @sfbase.workspace_in_view(src).0 }) is Some(w) else { return }
    filter_menu(Node(k), @sfbase.board_filter_of(src, w.id), fn(f) { board_filter_go(src, w, f, own.archived) }, in_board=true)
  }
  bar.pick(fn() { @sfbase.board_filter_of(src, (own.ws)()) == "mine" }, at_once=true, fn(p, mine) {
    if mine {
      @sf.button_opens_node(p, fn() { @sf.t("web-main.filter.chats.mine") }, open, icon="filter") |> ignore
    } else {
      let key : Ref[@view.View?] = Ref(None)
      key.val = Some(
        @sf.icon_button_node(
          p,
          "filter",
          fn() { @sf.t("web-main.filter.chats.named", args=[("named", @sf.t("web-main.filter.all"))]) },
          fn() {
            if key.val is Some(k) {
              open(k)
            }
          },
          size=@sf.button_h,
        ),
      )
    }
  })
}

///|
/// 显示: what opens how the board is shown (board_display). Its words what it is grouped by where that is not by state;
/// quiet (a ghost's) while the board is as it starts, else on a ground of its own.
fn board_display_key(bar : @view.View, own : BoardOwn) -> Unit {
  let as_started = fn() { (own.group)() == "state" && @sfbase.board_show_empty_of(own.src, (own.ws)()) }
  bar.pick(as_started, at_once=true, fn(p, quiet) {
    @sf.button_opens_node(
      p,
      fn() {
        match (own.group)() {
          "station" => board_words("by-station")
          "person" => board_words("by-person")
          _ => board_words("display")
        }
      },
      fn(btn) { board_display(own, btn) },
      tone=if quiet { Ghost } else { Plain },
      icon="sliders",
    )
    |> ignore
  })
}

///|
/// 显示's panel beside it (Linear's Display): how the board is grouped, whether its empty columns show. Each changes the
/// board behind it at once, the panel left open.
fn board_display(own : BoardOwn, btn : @view.View) -> Unit {
  @sf.panel_nodes(
    board_words("display"),
    fn(held, _close) {
      // (in a column of its own, down the panel: the panel lays what it holds out as it says)
      held.box(fn(col) {
      col.row(Is(false)).gap(Is(10.0)).width_share(Is(1.0)) |> ignore
      // how it is grouped: its words over a choice the panel's width
      col.box(fn(g) {
        g.row(Is(false)).gap(Is(6.0)).width_share(Is(1.0)) |> ignore
        g.box(fn(t) {
          t.padding(Is((board_display_in, 0.0, board_display_in, 0.0))) |> ignore
          @sf.words_node(t, fn() { board_words("group-by") }, fn() { display_head_look }) |> ignore
        })
        |> ignore
        @sf.seg_fill_node(
          g,
          fn() { [board_words("by-state"), board_words("by-station"), board_words("by-person")] },
          fn() {
            match (own.group)() {
              "station" => 1
              "person" => 2
              _ => 0
            }
          },
          fn(i) {
            @sfbase.board_pick.set(None)
            (own.to_start)()
            @sfbase.set_board_group(own.src, @signals.untracked(own.ws), match i {
              1 => "station"
              2 => "person"
              _ => "state"
            })
          },
          said=board_words("group-by"),
        )
        |> ignore
      })
      |> ignore
      // a line, then whether its empty columns show
      col.box(fn(l) {
        l.height(Is(Some(@sf.rule_w))).margin(Is((board_display_in, 2.0, board_display_in, 0.0))).ground(By(@sf.rule_color)) |> ignore
      })
      |> ignore
      // (its words where 分组方式's are, its switch as far in from the panel's end as from its foot: concentric with its
      // corner)
      col.box(fn(r) {
        r.padding(Is((board_display_in, 0.0, board_display_in, 0.0))) |> ignore
        @sf.switch_row_node(
          r,
          fn() { board_words("show-empty") },
          fn() { @sfbase.board_show_empty_of(own.src, (own.ws)()) },
          fn(on) { @sfbase.set_board_show_empty(own.src, @signals.untracked(own.ws), on) },
        )
      })
      |> ignore
      })
      |> ignore
    },
    from=Node(btn),
    w=board_display_w,
    heads_itself=true,
    side=Bottom,
    along=End,
  )
}

///|
/// How wide 显示's panel is.
let board_display_w : Double = 288.0

///|
/// How far in from the cards' edges 显示's words and its switch stand: the switch (36 × 22, its corner 11) as far from
/// the panel's end as from its foot, where its row (34 high) leaves it, so concentric with the panel's corner (24).
let board_display_in : Double = 7.0


///|
// kept across runs: a value (no field of it changes)
let display_head_look : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The narrow board: the column chosen by its chips under Home's bar (board_chips_node), its cards under them across the
/// page, the window's whole height: what scrolls in a column passing under that bar and under the bottom bar (`top`
/// and `foot` what they cover), as Home's list does; up and away under a finger's search, as the lists go
/// (chats_lists_node's).
fn board_narrow(
  p : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  top : () -> Double,
  foot : () -> Double,
) -> Unit {
  let away = search_away_node(p)
  p
  // (gone by half way, what the search finds coming in after: never the cards' words and its seen one over another)
  .alpha(By(fn() { dmax(0.0, 1.0 - 2.0 * away()) }))
  .offset(By(fn() { (0.0, -search_list_rise * away()) }))
  |> ignore
  p.box(fn(track) { board_track(track, src, tips, own, top, foot) }) |> ignore
  // its floating liquid glass filter capsules directly over the transparent scroll area under Home's scroll-edge
  p.box(fn(strip) {
    strip.over(Is(true)).lies_along(Is(Start)) |> ignore
    strip.box(fn(g) {
      // (the window's width, what scrolls in it sideways)
      g
      .width_share(Is(1.0))
      .margin(By(fn() { (0.0, top() - board_chips_h(g), 0.0, 0.0) }))
      |> ignore
      board_chips_node(g, src, own.ws)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The narrow board's columns side by side on one track in `track`, a column its whole width, each in what scrolls of
/// its own (where it is scrolled to kept as another is shown): the one chosen (sfbase's board_lane) shown, slid to as
/// it is chosen (the chips) a column's width a step (the theme's slide, as the chats' lists are: chats_lists_node), and
/// in the hand across: a finger moving more across than down takes the track (View::claims: what scrolls a column keeps
/// the rest), the column it leaves and the one beside it following it; let go landing past board_swipe_share of a column
/// (board_swipe_far at most), or flung that way, the one beside it chosen, else back. Only the columns on the way are
/// there (the one chosen at rest; from where it set out to where it goes; in the hand, it and those beside it): one off
/// the way is put by as it was (View::each's `keeps`), laid out, drawn and read out nowhere, taken in again as it is on
/// the way.
fn board_track(
  track : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  top : () -> Double,
  foot : () -> Double,
) -> Unit {
  let lanes = @sfbase.board_lanes
  let n = lanes.length()
  let index_of = fn(lane : String) { lanes.search(lane).unwrap_or(0) }
  let first = index_of(@sfbase.board_lane.untracked())
  let at = @motion.NodeWay::new(first.to_double())
  // (those laid out: the one chosen at rest; on the way, from where it set out to where it goes)
  let span : @signals.Signal[(Int, Int)] = @signals.signal((first, first))
  let due = Ref(fn() {  })
  let slide_to = fn(k : Int) {
    let from = @signals.untracked(fn() { at.shown(track) })
    let lo = if from.floor().to_int() < k { from.floor().to_int() } else { k }
    let hi = if from.ceil().to_int() > k { from.ceil().to_int() } else { k }
    span.set((if lo < 0 { 0 } else { lo }, if hi >= n { n - 1 } else { hi }))
    let (_, _, w, _) = track.laid_window_now()
    at.go(track, k.to_double(), @sf.theme().chat_list.slide.per_unit(w))
    (due.val)()
    due.val = track.at_moment(at.end(), fn() { span.set((k, k)) })
  }
  track.reacts(fn() { index_of(@sfbase.board_lane.get()) }, slide_to, at_start=false)
  // (in the hand: where it was as the finger took it, and where the finger was then)
  let from = Ref(0.0)
  let from_x = Ref(0.0)
  track
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .clips(Is(true))
  .claims(fn(dx, dy) {
    let k = index_of(@sfbase.board_lane.untracked())
    dx.abs() > @ui.touch_slop() && dx.abs() > dy.abs() && ((dx > 0.0 && k > 0) || (dx < 0.0 && k < n - 1))
  })
  .on_drag(fn(d) {
    let w = if d.w > 1.0 { d.w } else { 1.0 }
    let k = index_of(@sfbase.board_lane.untracked())
    match d.kind {
      Down => {
        from.val = @signals.untracked(fn() { at.shown(track) })
        from_x.val = d.wx
        (due.val)()
        due.val = fn() {  }
        at.put(from.val)
        let lo = if k > 0 { k - 1 } else { k }
        let hi = if k < n - 1 { k + 1 } else { k }
        span.set((lo, hi))
      }
      Moved => {
        let pos = from.val - (d.wx - from_x.val) / w
        let lo = if k > 0 { (k - 1).to_double() } else { k.to_double() }
        let hi = if k < n - 1 { (k + 1).to_double() } else { k.to_double() }
        at.put(if pos < lo { lo } else if pos > hi { hi } else { pos })
      }
      Up => {
        let moved = d.wx - from_x.val
        let vx = d.vx()
        let far = dmin(board_swipe_far, board_swipe_share * w)
        let next = if k < n - 1 &&
          (@ui.lands_past(moved, vx, -far) || (vx < -board_fling_vx && moved < -board_fling_least)) {
          k + 1
        } else if k > 0 &&
          (@ui.lands_past(moved, vx, far) || (vx > board_fling_vx && moved > board_fling_least)) {
          k - 1
        } else {
          k
        }
        if next == k {
          slide_to(k)
        } else {
          @sfbase.board_lane.set(lanes[next])
        }
      }
      Off => slide_to(k)
    }
  })
  |> ignore
  for i, lane in lanes {
    track.box(fn(l) {
      l
      .over(Is(true))
      .shift(By(fn() { (i.to_double() - at.shown(l), 0.0) }))
      .clips(Is(true))
      // (read out only while it is the one chosen)
      .hides(By(fn() { index_of(@sfbase.board_lane.get()) != i }))
      |> ignore
      let on_way = fn() {
        let (lo, hi) = span.get()
        if i >= lo && i <= hi { [i] } else { [] }
      }
      l.each(on_way, fn(k) { k }, keeps=fn() { [i] }, at_once=true, fn(c, _) {
        // (the column its slot: board_column's growing to the track's height)
        board_column(c, src, tips, own, lane, fn() { @sfbase.board_lane_words(lane) }, wide=false, top~, foot~)
      })
    })
    |> ignore
  }
}

///|
/// How far across a column the narrow board's track is taken to have the one beside it chosen as it is let go, as far
/// as board_swipe_far at most (landing past it on from the finger's speed: @ui.lands_past), and how fast (points a
/// millisecond) and at least how far it is flung to have it so sooner.
let board_swipe_share : Double = 0.18

///|
let board_swipe_far : Double = 68.0

///|
let board_fling_vx : Double = 0.32

///|
let board_fling_least : Double = 16.0

///|
/// Column `key` (named `name`): its title on the paper (its count beside it, 待派发's ＋ at its end), the line to write a
/// draft in where it is open, its cards. Wide, its title over its cards; narrow, the chips name it, its cards alone.
fn board_column(
  col : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  key : String,
  name : () -> String,
  wide~ : Bool,
  top? : () -> Double = fn() { 0.0 },
  foot? : () -> Double = fn() { 0.0 },
) -> Unit {
  let cards_now = @signals.computed(fn(_) { (own.cards_of)(key) })
  let cards = fn() { cards_now.get() }
  // (待收口's: how many of its chats read may be put away at once)
  let settled_now = @signals.computed(fn(_) {
    if key == "done" {
      @sfbase.board_archivable_settled((own.items)()).length()
    } else {
      0
    }
  })
  let settled_n = fn() { settled_now.get() }
  col.gap(Is(if wide { 2.0 } else { 0.0 })).grow(Is(if wide { 0.0 } else { 1.0 })).min_height(Is(Some(0.0))) |> ignore
  if wide {
    col.box(fn(h) {
      h.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).min_height(Is(Some(44.0))).padding(Is((4.0, 0.0, 0.0, 0.0)))
      |> ignore
      @sf.words_node(h, name, fn() { lane_title_look }) |> ignore
      @sf.words_node(h, fn() { cards().length().to_string() }, fn() { lane_count_look }) |> ignore
      h.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
      if key == "draft" {
        @sf.icon_button_node(h, "plus", fn() { board_words("new-here") }, fn() { board_open_add(own) |> ignore }, tips~)
        |> ignore
      }
      // (待收口's chats read put away at once, while there are some)
      if key == "done" {
        h.show(fn() { settled_n() > 0 }, fn(k) {
          @sf.icon_button_node(k, "archive", fn() { @sf.t("web-main.board.archive_read", args=[("n", settled_n().to_string())]) }, fn() {
            board_archive_settled(src, @signals.untracked(own.items))
          }, tips~)
          |> ignore
        }, along_row=true)
      }
    })
    |> ignore
  }
  // its cards, a block each only while it shows (View::scrolls_window: a column of a hundred cards makes those that
  // show), under its title (wide) or the chips on Home's bar (narrow), each going in and out among the others for what
  // comes or leaves (a draft written, one started, a chat come or gone): the list's own way; the line to write a draft
  // in over 待派发's, its head (narrow, under the room the bar over it covers: its cards pass under that bar's glass, as
  // Home's list's rows do); what it says with none its last block; the room at its foot (narrow, what the bottom bar
  // covers and the list's room under it, as Home's list's: its last card comes to rest over that bar) its foot
  let ends = if wide { (0.0, 0.0) } else { (board_pad, board_pad) }
  let rows = fn() {
    let out = cards().map(fn(k) { CardRow(k) })
    if out.is_empty() && (key != "draft" || (wide && !@sfbase.board_adding.get())) {
      out.push(EmptyRow)
    }
    out
  }
  col.box(fn(l) {
    l.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_height(Is(Some(0.0))) |> ignore
    l.scrolls_window(
      @view.Scroll::list(),
      rows,
      fn(row, r) {
        match r {
          CardRow(k) => {
            row.padding(Is((ends.0, 0.0, ends.1, 10.0))) |> ignore
            match k {
              DraftKey(id) => draft_card(row, src, tips, own, id, key)
              ChatKey(name) => board_chat_card(row, src, tips, own, name, key, wide)
            }
          }
          EmptyRow => {
            row.padding(Is((ends.0 + 4.0, 6.0, ends.1 + 4.0, 6.0))) |> ignore
            @sf.words_node(row, fn() { if key == "draft" { board_words("empty-draft") } else { board_words("empty") } }, fn() {
              card_meta_look
            })
            |> ignore
          }
        }
      },
      est=board_card_est,
      slop=@ui.touch_slop(),
      bar=@ui.tree_scroll_bar(),
      // (narrow, what the bars over it and under it cover: where what is read is held from, and its bar clear of both,
      // as Home's list's)
      top_covered=top,
      bar_clear=if wide {
        // (wide, reaching the foot: clear of the panel's corner in a panel of its own, of the page's margin else)
        let in_pane = col.lent(@sf.pane_lent).unwrap_or(false)
        fn() { (0.0, if in_pane { @sf.pane_corner } else { board_pad }) }
      } else {
        fn() { (top(), foot()) }
      },
      comes=fn(r) { r is CardRow(_) },
      goes=fn(r) { r is CardRow(_) },
      comes_whole=fn(_) { true },
      // (its cards each one thing on the board (View::shared): one gone to another column flies there, one archived or
      // deleted here closes its room over the cards under it, as what comes and goes in a list whose blocks fly does)
      flips=true,
      head=fn(h) {
        h.padding(By(fn() { (ends.0, if wide { 0.0 } else { top() + board_narrow_top_in }, ends.1, 0.0) })) |> ignore
        if key == "draft" {
          if wide {
            board_add_room(h, own, tips)
          } else {
            h.box(fn(a) {
              a.padding(Is((0.0, 0.0, 0.0, 10.0))) |> ignore
              board_add(a, own, wide, tips)
            })
            |> ignore
          }
        }
        // (narrow, 待收口's chats read put away at once from its top, while there are some: how many, and 归档已读)
        if key == "done" && !wide {
          h.show(fn() { settled_n() > 0 }, fn(a) {
            a.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).padding(Is((4.0, 0.0, 0.0, 8.0))) |> ignore
            a.box(fn(w) {
              w.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              @sf.words_node(w, fn() { @sf.t("web-main.board.read_n", args=[("n", settled_n().to_string())]) }, fn() {
                card_meta_look
              })
              |> ignore
            })
            |> ignore
            a.box(fn(k) {
              k.shrink(Is(0.0)) |> ignore
              @sf.button_node(k, fn() { @sf.t("web-main.board.archive_read_short") }, fn() {
                board_archive_settled(src, @signals.untracked(own.items))
              }, tone=Ghost, icon="archive")
              |> ignore
            })
            |> ignore
          })
        }
      },
      // (wide, the page's margin under its last card (board_wide_foot); narrow, Home's list's: what the bottom bar
      // covers and the room under its last row)
      foot=fn(f) {
        f.height(By(fn() { Some(if wide { board_wide_foot } else { foot() + @sf.list_foot_in(Whole) }) })) |> ignore
      },
    )
    |> ignore
  })
  |> ignore
}

///|
/// How much room a wide column keeps under its last card: with the card's own room under it (board_column's 10), the
/// page's margin, so a column scrolled to its end has its last card as far from the foot as from the sides (in 中屏's
/// panel, concentric with its corner).
let board_wide_foot : Double = board_pad - 10.0

///|
/// How far under the room the bar over it covers a narrow column's first card stands.
let board_narrow_top_in : Double = 4.0

///|
/// What a column's list holds (board_column's): a card by its key, what the column says with none.
#derive(Eq, Hash)
priv enum ColRow {
  CardRow(BoardKey)
  EmptyRow
}

///|
/// How tall a card is taken to be in a column's list till it is measured (its title on one line, where it stands, where
/// it runs, its room under it).
let board_card_est : Double = 116.0

///|
/// The wide board's room the card a draft is written in stands in, at 待派发's top: opening and closing as a room does
/// (as tall as its share of the card, the card as big as it is open about its middle, seen from half open), what is
/// under it going with it, a Move as far as the card is tall; opened, the card empty. Put away by what was written in
/// it, gone at once: its draft comes in its place, grown from it (draft_card's), the cards under it going on one Move.
fn board_add_room(b : @view.View, own : BoardOwn, tips : @sf.TipLayer) -> Unit {
  // (opened on what was written in it and left: emptied only as that is added or put away, board_add's)
  let open = fn() { @sfbase.board_adding.get() }
  // (made anew at once as what was written in it is added, closed and laid nowhere: the one that held it let go with
  // what makes the cards under it, so that what moves for its draft finds both done; opened, mbui's room's way)
  b.pick(fn() { own.room_made.get() }, fn(room, _) {
    @motion.reveal_node(room, open, fn(h) {
      // (the column's list clips at its sides; leave room for the glass composer's outside contour)
      h.padding(Is((2.0, 0.0, 2.0, 10.0))) |> ignore
      board_add(h, own, true, tips)
    })
    |> ignore
  }, at_once=true)
}

///|
/// The card a draft is written in at 待派发's top: a chat's composer's box (composer_alone_node), opened all along, its
/// words and send alone (what is pasted or dropped in over its words), × to put it away (wide): where it goes, what it
/// runs on and what more it takes are its card's panel's once it is added (draft_panel), as a card has not the room for
/// so many keys a finger can press. Its send adds the draft (its own ＋) to the station last chosen; while the command
/// key is held it is the send arrow and starts it at once, as ⌘Enter does. Made again for each draft and each station:
/// its draft is that one's, its files go up to that station.
fn board_add(a : @view.View, own : BoardOwn, wide : Bool, tips : @sf.TipLayer) -> Unit {
  let card_at : Ref[@view.View?] = Ref(None)
  let dispatching = fn() {
    let primary = match @ui.keys_system() { 0 | 1 => @ui.mod_cmd; _ => @ui.mod_ctrl }
    (@ui.key_modifiers() & primary) != 0
  }
  let ws = @signals.untracked(own.ws)
  let writing = fn() { @sfbase.writing(own.src, @sfbase.board_file_key(ws, own.draft_id.get())) }
  let files = fn() {
    writing().files.get().map(fn(f) -> @sfbase.BoardFile { { id: text(Some(f), "id"), name: text(Some(f), "name") } })
  }
  // (its words let go of with it: the next draft's are its own)
  let emptied = fn(w : Writing) {
    w.field.set("")
    writing_text(own.src, w, "")
  }
  let discard = fn() {
    @sfbase.board_files_discard(own.src, ws, own.draft_id.untracked(), @signals.untracked(files))
    @sfbase.board_pick_forget(own.src, @signals.untracked(fn() { board_station_now(own) }), own.draft_id.untracked())
    emptied(@signals.untracked(writing))
    own.draft_id.set(@sfbase.board_writing_renew(ws))
  }
  let add = fn(w : Writing, start : Bool) {
    let st = @signals.untracked(fn() { board_station_now(own) })
    guard st != "" &&
      w.pending.untracked() == 0 &&
      !w.files.untracked().iter().any(fn(f) { text(Some(f), "error") != "" }) else {
      return
    }
    let words = w.field.text()
    let name = own.stations_by.peek(st).map(fn(s) { s.name }).unwrap_or("")
    let from = match card_at.val {
      Some(c) if c.alive() => Some(c.placed_window_now())
      _ => None
    }
    // (the draft and its line put away one change: what moves for it goes from where all of it stood before)
    let id = own.draft_id.untracked()
    let attached = @signals.untracked(files)
    @signals.start_batch()
    // (wide, put away at once once written, its words in it, its room let go first: its draft comes in its place,
    // grown from where it was)
    if wide {
      own.room_made.set(own.room_made.untracked() + 1)
      @sfbase.board_adding.set(false)
    }
    let added = @sfbase.board_draft_add(own.src, ws, words, st, name, id~, files=attached)
    if wide && !start && added is Some(id) {
      own.added_from = from.map(fn(r) { (id, r) })
    }
    if added is Some(_) {
      // (narrow it stays, 待派发's own line, empty for the next)
      emptied(w)
      own.draft_id.set(@sfbase.board_writing_renew(ws))
    }
    @signals.end_batch()
    guard start && added is Some(id) else { return }
    let draft : @sfbase.BoardDraft = {
      id,
      title: words.trim(chars=" \n\r\t").to_owned(),
      station: st,
      station_name: name,
      files: attached,
    }
    own.start_from = from.map(fn(r) { (st + "/" + @sfbase.board_key_of(draft), r) })
    @sfbase.board_start(own.src, ws, draft)
  }
  let cancel = fn() {
    discard()
    @sfbase.board_adding.set(false)
  }
  a.box(fn(card) {
    // (let go of with the board, its words and pictures kept for it to come back to: put away only by × or Escape)
    card_at.val = Some(card)
    card.reacts(fn() {
      writing().files.get().map(fn(f) { text(Some(f), "error") }).filter(fn(e) { e != "" }).join("\n")
    }, fn(error) {
      if error != "" { @sfbase.toast_later(error) }
    }, at_start=false)
    // (Escape puts it away, as × does)
    if wide {
      card.on_key(fn(k) {
        if k.code == @ui.key_escape {
          cancel()
          true
        } else {
          false
        }
      })
      |> ignore
    }
    card.pick(fn() { (own.draft_id.get(), board_station_now(own)) }, at_once=true, fn(c, made) {
      let (id, st) = made
      let spec : BoxSpec = {
        chat: false,
        roomy: true,
        placeholder: board_words("placeholder"),
        attach: false,
        tools: None,
        // (wide, clear of × in its corner)
        words_end: if wide { card_title_end() } else { 0.0 },
        sends: fn() { board_words(if dispatching() { "dispatch" } else { "add" }) },
        send_icon: fn() { if dispatching() { "arrow-up" } else { "plus" } },
        send: Some(fn(w) { add(w, @signals.untracked(dispatching)) }),
      }
      composer_alone_node(c, own.src, st, @sfbase.board_file_key(ws, id), spec, tips)
    })
    // (opened to be written in: the cursor in it, each time it opens; once what opened it is done, its room in use by
    // then, and once its room is laid out open where the host gives the focus by where it is: a browser's)
    card.reacts(fn() { @sfbase.board_adding.get() }, fn(on) {
      if on {
        @signals.after_flush(fn() { @signals.untracked(writing).field.focus() })
        card.at_moment(card.cause_at() + 1.0, fn() {
          if @sfbase.board_adding.untracked() { @signals.untracked(writing).field.focus() }
        })
        |> ignore
      }
    })
  })
  |> ignore
  if wide {
    card_corner_key(a, tips, fn() { true }, "close", fn() { board_words("cancel") }, cancel)
  }
}

///|
/// Files beside a task: their pictures come from the composer or the device's kept draft, not from board prefs.
/// `in_panel`: in a panel's body (draft_panel's), the strip out across the room the panel leaves at its sides
/// (panel_bleed_node), scrolling under its edges, its first file starting where the title's words do
/// (panel_title_at_node), as what is under it does; no room of its own over its files, the body's gap between them
/// and the words as between them and what is under them.
fn board_files_node(
  parent : @view.View,
  src : Source,
  key : () -> String,
  files : () -> Array[@sfbase.BoardFile],
  in_panel? : Bool = false,
) -> Unit {
  let over = if in_panel { 0.0 } else { 8.0 }
  let strip = fn(p : @view.View) {
    p.height(Is(Some(@sf.waiting_tile_side + over))).min_width(Is(Some(0.0))) |> ignore
    if in_panel {
      @sf.style_node(p, fn() { @sf.panel_bleed_node(p) })
    }
    // (how far in its first file and its last stand: in a panel the room at its sides and the title's words')
    let inset = fn() {
      if in_panel {
        @sf.panel_sides_at_node(p) + @sf.panel_title_at_node(p)
      } else {
        0.0
      }
    }
    p.scrolls(@view.Scroll::across(), slop=@ui.touch_slop(), fn(row) {
      row.row(Is(true)).gap(Is(6.0)).padding(By(fn() { (inset(), over, 8.0 + inset(), 0.0) })) |> ignore
      let by_id = row.keyed_by(files, fn(f) { f.id })
      row.each(fn() { by_id.keys() }, fn(id) { id }, fn(slot, id) {
        let file = fn() { by_id.get(id.get()).unwrap_or({ id: "", name: "" }) }
        let is_video = fn() { file_kind(file().name) == "video" }
        // (the picture picked here, else the device's kept one of an image (told as each comes); a video's its still
        // picked or drawn here; "!" none)
        let picture = fn() {
          let f = file()
          match file_kind(f.name) {
            "image" =>
              match @sfbase.writing_picture_told(f.id) {
                Some(p) => p
                None => src.draft_picture_told(key(), f.id)
              }
            "video" => @sfbase.writing_picture_told(f.id).unwrap_or("!")
            _ => "!"
          }
        }
        @sf.waiting_tile_node(
          slot,
          fn(p) {
            p.pick(fn() { picture() != "" && picture() != "!" }, at_once=true, fn(v, has_picture) {
              if has_picture {
                // (as big as the tile, covering it, decoded for the device's pixels it is drawn at; a video's on its
                // black, as the composer's: that black its matte, composited into it and cut once with it, never drawn
                // apart under it where their rounded edge would show it through as a rim)
                v
                .width(Is(Some(@sf.waiting_tile_side)))
                .height(Is(Some(@sf.waiting_tile_side)))
                .image(
                  By(fn() {
                    let k = picture()
                    let cap = if !is_video() && tile_start_crop(k) is Some(_) {
                      image_px_most.to_int()
                    } else {
                      (@sf.waiting_tile_side * v.pixel_scale()).ceil().to_int()
                    }
                    Some((k, "", cap))
                  }),
                )
                .image_for(Is((@sf.waiting_tile_side, @sf.waiting_tile_side)))
                .image_in(
                  By(fn() {
                    if is_video() {
                      Some(
                        (
                          (0.0, 0.0, @sf.waiting_tile_side, @sf.waiting_tile_side),
                          @ui.tree_theme().color(@sf.video_ground),
                        ),
                      )
                    } else {
                      None
                    }
                  }),
                )
                .image_covers(Is(true))
                .image_covers_at(By(fn() { if is_video() { None } else { tile_start_crop(picture()) } }))
                |> ignore
              } else {
                v.lines_up(Is(Some(Middle))).lies_along(Is(Middle)) |> ignore
                @sf.icon_node(v, "file", 22.0, By(fn() { @sf.theme().p.muted })) |> ignore
              }
            })
          },
          fn() { false },
          fn() { None },
          fn() { false },
          fn() {  },
          fn() { "" },
          video=fn() { is_video() && picture() != "" && picture() != "!" },
        )
        |> ignore
      })
    }) |> ignore
  }
  parent.show(fn() { !files().is_empty() }, at_once=true, fn(p) { strip(p) })
}


///|
/// The narrow board's chips choosing its column (sfbase's board_lane), under Home's bar on its glass (board_narrow's:
/// the cards pass under both): the five, each its words and its count, a tab of a tab list
/// (mbui's headless radio_group: the arrows along them, a screen reader's Activate), as wide as their words and
/// board_chip_in in at either end, sharing what is left of the window's width; going sideways where they have not the
/// room, the page's margin (board_pad) at either end of what scrolls, the bar's whole width scrolling. The one chosen
/// is brought whole into sight, its margin beside it, as it is chosen (a chip pressed, the track swiped to another
/// column, the board shown): scrolled to over a Move as far as it goes; at once as the board is shown.
fn board_chips_node(v : @view.View, src : Source, ws : () -> String) -> Unit {
  let lanes = @sfbase.board_lanes
  // (how many cards each column holds, as the board's columns by state have them: its drafts, its chats by where they
  // stand; worked out once for all the chips as a chat or a draft changes, told only as it comes out otherwise)
  let counts = @signals.computed(fn(_) {
    let ws = ws()
    let out = Array::make(lanes.length(), 0)
    if ws == "" {
      return out
    }
    out[0] = @sfbase.board_drafts_of(src, ws).length()
    for i in @sfbase.board_items(src, ws) {
      match lanes.search(@sfbase.board_lane_of(i)) {
        Some(k) => out[k] = out[k] + 1
        None => ()
      }
    }
    out
  })
  let across = @view.Scroll::across()
  // (each chip's node by its column, what is brought into sight)
  let chips : Map[String, @view.View] = Map([])
  // (what is left of a way into sight: drawn so much further back toward where it was, none as it ends)
  let left = @motion.NodeWay::new(0.0)
  v.box(fn(holder) {
    holder.shrink(Is(0.0)).width_share(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    holder.scrolls(across, slop=@ui.touch_slop(), fn(held) {
      // (what scrolls holds the row, drawn back by what is left of a way into sight: what scrolls moves it itself)
      let row = held.box(fn(_) {  })
      row
      .row(Is(true))
      .gap(Is(board_chip_gap))
      // (the cards' margin at either end, lined up with them, inside what scrolls; board_chips_pad over and under: each
      // pressed in 44 high)
      .padding(Is((board_pad, board_chips_pad, board_pad, board_chips_pad)))
      .min_width(By(fn() { Some(held.window_w()) }))
      .offset(By(fn() { (left.shown(row), 0.0) }))
      |> ignore
      @sf.chip_tabs_node(
        row,
        fn() { @sf.t("web-main.board.board") },
        lanes,
        fn() { @sfbase.board_lane.get() },
        fn(lane) { @sfbase.board_lane.set(lane) },
        fn(lane) {
          let k = lanes.search(lane).unwrap_or(0)
          let count = counts.get().get(k).unwrap_or(0)
          @sfbase.board_lane_words(lane) + " " + count.to_string()
        },
        fn(c, lane, item) {
          let k = lanes.search(lane).unwrap_or(0)
          let count = fn() { counts.get().get(k).unwrap_or(0) }
          board_chip_look(c, item, lane, count)
        },
        on_item=fn(lane, chip) { chips[lane] = chip },
      )
      |> ignore
      // (column `lane`'s chip whole in sight, its margin beside it: scrolled to (`glide`) from where it shows now, or
      // put there at once)
      let reveal = fn(lane : String, glide : Bool) {
        guard chips.get(lane) is Some(c) && c.alive() && holder.alive() else { return }
        let (rx, _, _, _) = row.laid_window_now()
        let (cx, _, cw, _) = c.laid_window_now()
        let (_, _, hw, _) = holder.laid_window_now()
        // (where it is along what scrolls, whatever is left of a way into sight; where what scrolls shows now)
        let x = cx - rx
        let now = across.at(holder.tree)
        let shown_at = now - @signals.untracked(fn() { left.shown(row) })
        let to = if x - board_pad < shown_at {
          x - board_pad
        } else if x + cw + board_pad > shown_at + hw {
          x + cw + board_pad - hw
        } else {
          return
        }
        let most = across.most()
        let to = if to < 0.0 { 0.0 } else if to > most { most } else { to }
        if (to - shown_at).abs() < 0.5 {
          return
        }
        across.put(to)
        if glide {
          left.go_from(row, to - shown_at, 0.0, @motion.moved(over=(to - shown_at).abs()))
        } else {
          left.put(0.0)
        }
      }
      row.reacts(fn() { @sfbase.board_lane.get() }, fn(lane) { reveal(lane, true) }, at_start=false)
      // (the board shown: the one chosen in sight at once, once the chips are laid out)
      row.at_moment(row.cause_at(), fn() { reveal(@sfbase.board_lane.untracked(), false) }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// How tall the narrow board's chips are on Home's bar in `v`'s tree, the room over and under them with them: as tall as
/// board_chip_h, or as their words' line at the system's size of words and board_chip_pad over and under it.
pub fn board_chips_h(v : @view.View) -> Double {
  let line = board_line(v, board_chip_words)
  2.0 * board_chips_pad + dmax(board_chip_h, line + 2.0 * board_chip_pad)
}

///|
/// The height of the line of words drawn as `look` in `v`'s tree, at the system's size of words there (followed as it
/// changes: View::words_scale).
fn board_line(v : @view.View, look : @ui.TextStyle) -> Double {
  let w = @ui.style_words(look)
  if w.line < 0.0 {
    -w.line * @sf.node_sp(v, w.size)
  } else {
    @sf.node_sp(v, w.line)
  }
}

///|
/// A chip's look (board_chips_node's, an item of its radio group in `c`): board_chip_h high at least, growing with its
/// words at the system's size of words, round; its words and its count on a tint of the words' ink, the accent's while
/// chosen; the hand on it warming its ground over dur_ms; the keyboard's focus a ring of the theme's where it shows.
fn board_chip_look(c : @view.View, item : @sf.RadioRow, lane : String, count : () -> Int) -> Unit {
  let on = fn() { item.picked() }
  let lit = fn() { !on() && item.lit() }
  let hand = @motion.NodeWay::new(if @signals.untracked(lit) { 1.0 } else { 0.0 })
  c.reacts(lit, fn(l) { hand.go_ms(c, if l { 1.0 } else { 0.0 }, @sf.dur_ms) })
  @sf.glass_capsule_node(c, min_height=Some(board_chip_h), radius=Some(1.0e6), interactive=true)
  .row(Is(true))
  .gap(Is(2.0))
  .lines_up(Is(Some(Middle)))
  .lies_along(Is(Middle))
  // (board_chip_in in at either end at least: five of them, the longest 等你处理, whole on a phone 390 wide within the
  // cards' margins, what the row leaves shared among them)
  .padding(Is((board_chip_in, board_chip_pad, board_chip_in, board_chip_pad)))
  // (as wide as its words at least, sharing what the row leaves; never narrower than they are)
  .shrink(Is(0.0))
  .grow(Is(1.0))
  .ground(By(fn() {
    let p = @sf.theme().p
    if on() {
      p.accent_bg
    } else {
      let h = hand.shown(c)
      if h > 0.001 {
        @sf.alpha(p.text, 0.06 * h)
      } else {
        0L
      }
    }
  }))
  .edge(By(fn() {
    if c.focus_shown() {
      (@ui.tree_theme().focus_w, @ui.tree_theme().focus)
    } else if c.glass_solid() {
      (@sf.control_edge_w, @sf.theme().p.line)
    } else {
      (0.0, 0L)
    }
  }))
  |> ignore
  @sf.words_node(c, fn() { @sfbase.board_lane_words(lane) }, fn() { if on() { chip_on_look } else { board_chip_words } }) |> ignore
  @sf.words_node(c, fn() { count().to_string() }, fn() { if on() { chip_on_look } else { chip_count_look } }) |> ignore
}

///|
/// A chip's least height, how far in its words are at either end and over and under them, the room between chips, and
/// over and under the row of them.
let board_chip_h : Double = 30.0

///|
let board_chip_in : Double = 8.0

///|
let board_chip_pad : Double = 6.0

///|
let board_chip_gap : Double = 3.0

///|
let board_chips_pad : Double = 7.0

///|
// kept across runs: a value (no field of it changes)
let board_chip_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let chip_count_look : @ui.TextStyle = @ui.text_style(size=Meta, color=Subtle, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let chip_on_look : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=AccentText, wrap=false)

///|
/// The ground every card has, at rest: the page's card, no line round it, no shadow; picked (its chat beside the board)
/// the accent's tint over it; the hand on it (`lit`) warming it, eased in and out over dur_ms as a control answering
/// does. The ground as it is now (what stands on it drawn round in it: its faces).
fn card_ground(
  card : @view.View,
  picked : () -> Bool,
  lit : () -> Bool,
  lifted : () -> Double,
) -> () -> Int64 {
  let hand = @motion.NodeWay::new(if @signals.untracked(lit) { 1.0 } else { 0.0 })
  card.reacts(lit, fn(l) { hand.go_ms(card, if l { 1.0 } else { 0.0 }, @sf.dur_ms) })
  let ground = fn() {
    let p = @sf.theme().p
    let at_rest = if picked() {
      @sf.over(p.card, @sf.alpha(p.accent_bg, 0.55))
    } else {
      let k = hand.shown(card)
      if k <= 0.0 { p.card } else { @sf.over(p.card, @sf.alpha(p.hover, 0.6 * k)) }
    }
    // (held by a finger for its menu: the raised ground as it lifts, as a row of Home's list's, chat_row_node's)
    let up = lifted()
    if up <= 0.0 { at_rest } else { @sf.over(at_rest, @sf.alpha(p.raised, up)) }
  }
  card
  .ground(By(ground))
  .radius(Is(@sf.card_corner))
  .padding(Is((card_pad, card_pad, card_pad, card_pad)))
  .gap(Is(6.0))
  |> ignore
  ground
}

///|
/// A card held by a finger for its menu (board_chat_card's, draft_card's): lifted toward the finger a little while it
/// is held, all the way while the menu that hold put up is drawn (presented_drawn_of: a step further in, its 分享,
/// too), back down as that goes, over the menu's scrim and clear of its sheet (@sf.lift_node, as a row of Home's list
/// is, chat_row_node's); a menu put up by a right click lifts nothing.
priv struct CardLift {
  held : @signals.Signal[Bool]
  menu : @signals.Signal[Int?]
}

///|
fn CardLift::new() -> CardLift {
  { held: @signals.signal(false), menu: @signals.signal(None) }
}

///|
/// `w`, all of the card (its corner's key with it), lifted so: how far up it is as it is drawn (0 … 1).
fn CardLift::node(self : CardLift, w : @view.View) -> () -> Double {
  @sf.lift_node(
    w,
    fn() { self.held.get() },
    fn() {
      match self.menu.get() {
        Some(s) => @sf.presented_open_chain_of(s)
        None => false
      }
    },
    card_lift_scale,
  )
}

///|
/// The menu just put up for it: by a finger's hold (`held`, lifted while it is drawn), else none lifted.
fn CardLift::put_up(self : CardLift, held : Bool) -> Unit {
  self.menu.set(if held { Some(@sf.last_presented()) } else { None })
}

///|
/// How much larger a card lifted all the way is drawn: a 358 wide one of 小屏's 368.7, more than 10 inside the page's
/// sides still, its corners and its shadow whole.
let card_lift_scale : Double = 1.03

///|
/// The shadow of a card lifted `up` (0 … 1) for its menu (held_raised's, as a row of Home's list's).
fn card_shadow(up : Double) -> (Double, Double, Int64) {
  if up <= 0.0 {
    return (0.0, 0.0, 0L)
  }
  let r = @sf.held_raised
  (r.sigma * up, r.dy * up, @sf.alpha(r.color, up))
}

///|
/// How a card answers the hand (card_ground's `lit`): a pointer over it, the keyboard's focus shown on it, its menu open
/// (`menu_on`); a finger or a press on it once it has stayed tap_indication_ms (`down` and `up`), so a finger going on
/// to scroll a column, or the track across, lights nothing.
priv struct CardHand {
  pressed : @signals.Signal[Bool]
  hovered : @signals.Signal[Bool]
  mut due : () -> Unit
}

///|
fn CardHand::new() -> CardHand {
  { pressed: @signals.signal(false), hovered: @signals.signal(false), due: fn() {  } }
}

///|
/// A pointer over `card` followed.
fn CardHand::watch(self : CardHand, card : @view.View) -> Unit {
  card.reacts(fn() { @sf.hovered_node(card) }, fn(h) { self.hovered.set(h) })
}

///|
/// Whether card `card` is lit now, `menu_on` whether its menu is open.
fn CardHand::lit(self : CardHand, card : @view.View, menu_on : () -> Bool) -> Bool {
  card.focus_shown() || menu_on() || self.pressed.get() || self.hovered.get()
}

///|
/// Pressed down on `card`: lit once it stays tap_indication_ms.
fn CardHand::down(self : CardHand, card : @view.View) -> Unit {
  (self.due)()
  self.due = card.at_moment(card.cause_at() + @ui.tap_indication_ms, fn() { self.pressed.set(true) })
}

///|
/// Let go (or taken by what scrolls): lit no more by the press.
fn CardHand::up(self : CardHand) -> Unit {
  (self.due)()
  self.due = fn() {  }
  self.pressed.set(false)
}

///|
/// A draft's card (待派发's): its words, where it is to run, 开始 at its top end; pressed, its panel beside it
/// (draft_panel: its words, where and on what it runs, 派发); held long (or right clicked), its menu (立即派发, 删除). Never dragged, wide or narrow: a finger on it scrolls
/// its column.
fn draft_card(
  row : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  id : String,
  lane : String,
) -> Unit {
  let d = fn() { (own.drafts_by)().get(id) }
  let title = fn() {
    d().map(fn(d) { if d.title == "" { d.files.get(0).map(fn(f) { f.name }).unwrap_or("") } else { d.title } }).unwrap_or("")
  }
  let card_at : Ref[@view.View?] = Ref(None)
  // (started from `from` in the window: its chat's card flies in from there, board_chat_card's)
  let start_from = fn(from : (Double, Double, Double, Double)) {
    match @signals.untracked(d) {
      Some(d) => {
        // (its chat's card is of the key it is made under: its row's all along)
        own.start_from = Some((d.station + "/" + @sfbase.board_key_of(d), from))
        @sfbase.board_start(src, @signals.untracked(own.ws), d)
      }
      None => ()
    }
  }
  let start = fn() {
    match card_at.val {
      Some(c) if c.alive() => start_from(c.placed_window_now())
      _ => start_from((0.0, 0.0, 0.0, 0.0))
    }
  }
  let delete = fn() { @sfbase.board_draft_remove(src, @signals.untracked(own.ws), id) }
  // (pressed: its panel beside it, where it is edited and started)
  let edit = fn() {
    match card_at.val {
      Some(c) if c.alive() => draft_panel(src, own, id, c, start)
      _ => ()
    }
  }
  let hand = CardHand::new()
  let lift = CardLift::new()
  // (its menu: start it now, delete it; held long, from the card, felt as it opens, the card lifted over its scrim)
  let menu = fn(x : Double, y : Double, held : Bool) {
    hand.up()
    let from = match card_at.val {
      Some(c) if held && c.alive() => {
        let (cx, cy, cw, ch) = c.placed_window_now()
        @sf.Beside::At(cx, cy, cw, ch)
      }
      _ => At(x, y, 0.0, 0.0)
    }
    if held {
      @sf.menu_held_node()
    }
    @sf.menu(
      [
        Some(@sf.menu_item_of(board_words("start-now"), start, icon="play")),
        Some(@sf.menu_item_of(board_words("delete"), delete, icon="trash", danger=true)),
      ],
      from~,
    )
    lift.put_up(held)
  }
  // (the station it goes to as the workspace's rows have it: its mark)
  let station = fn() {
    let st = d().map(fn(d) { d.station }).unwrap_or("")
    own.stations_by.get(st)
  }
  row.box(fn(w) {
  let lifted = lift.node(w)
  w.box(fn(card) {
    card_at.val = Some(card)
    // (written a moment ago in the card over 待派发's cards: its ground grows from as tall as that one was, its foot
    // coming up with the cards under it, one Move)
    match own.added_from {
      Some((added, from)) if added == id => {
        own.added_from = None
        let grow = @motion.NodeWay::new(0.0)
        let by = Ref(0.0)
        card.at_moment(card.cause_at(), fn() {
          by.val = from.3 - card.laid_window_now().3
          grow.go_from(card, 1.0, 0.0, @motion.moved(over=by.val.abs()))
        })
        |> ignore
        card.ground_drawn(By(fn() { { dx: 0.0, dy: 0.0, dw: 0.0, dh: by.val * grow.shown(card), corners: None } })) |> ignore
      }
      _ => ()
    }
    card_ground(card, fn() { false }, fn() { hand.lit(card, fn() { false }) }, lifted) |> ignore
    card.shadow(By(fn() { card_shadow(lifted()) })) |> ignore
    hand.watch(card)
    @sf.action_box_node(card, title, fn(_) { edit() }, in_node=true, fn(card) {
      card.on_menu(fn(e) { menu(e.wx, e.wy, false) }) |> ignore
      @sf.presses_held_node(
        card,
        edit,
        @ui.long_press_ms,
        // (held long by a finger: lifted, its menu; a mouse's button held is a press as long as any)
        fn(e) {
          if !@sf.pointer_rests() {
            lift.held.set(true)
            menu(e.wx, e.wy, true)
          }
        },
        down=fn(_) { hand.down(card) },
        up=fn() {
          hand.up()
          lift.held.set(false)
        },
      )
    })
    |> ignore
    card.box(fn(head) {
      head.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Start))) |> ignore
      head.box(fn(t) {
        t.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(t, title, fn() { card_title_look }) |> ignore
      })
      |> ignore
      head.padding(Is((0.0, 0.0, card_title_end(), 0.0))) |> ignore
    })
    |> ignore
    board_files_node(card, src, fn() { @sfbase.board_file_key((own.ws)(), id) }, fn() {
      d().map(fn(d) { d.files }).unwrap_or([])
    })
    // where it is to run, as a chat's card says where it runs (and, not by state, that it waits in 待派发): its station's
    // mark before its name where it has one, as a chat's row has it, else its name alone where the title begins
    card.box(fn(m) {
      m.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
      let emoji = fn() { station().map(fn(c) { c.emoji }).unwrap_or("") }
      let icon = fn() { station().map(fn(c) { c.icon }).unwrap_or("") }
      m.show(fn() { @sf.has_station_mark(emoji(), icon()) }, fn(k) {
        @sf.station_mark_node(k, emoji, icon, card_station_mark, fn() { @sf.theme().p.muted }, own.stint)
      }, along_row=true)
      @sf.words_node(m, fn() {
        let name = d().map(fn(d) { d.station_name }).unwrap_or("")
        if (own.group)() == "state" { name } else { name + " · " + @sfbase.board_lane_words("draft") }
      }, fn() { card_meta_look })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  card_corner_key(w, tips, fn() { true }, "play", fn() { board_words("start") }, start)
  })
  |> ignore
  ignore(lane)
}

///|
/// Draft `id`'s panel, opened by its card `from` (beside it; a sheet from the foot on 小屏): its words, the pictures and
/// files it carries, where it runs (the workspace's stations; kept to its own while it carries files this device does
/// not hold) and on what (the one model control, picked for it alone: `board:<id>`); at its foot 完成 and 派发 (`start`).
/// What is changed is kept as it closes, however it closes: 完成, 派发, Escape, back or a press outside; words left
/// empty with nothing carried keep the words it had.
fn draft_panel(src : Source, own : BoardOwn, id : String, from : @view.View, start : () -> Unit) -> Unit {
  let ws = @signals.untracked(own.ws)
  guard @signals.untracked(fn() { (own.drafts_by)().get(id) }) is Some(d0) else { return }
  let field = @ui.Field::new()
  // (its own words, not the name of its first file standing in for them)
  field.set(d0.title)
  let station = @signals.signal(d0.station)
  let kept = Ref(false)
  let keep = fn() {
    guard !kept.val else { return }
    kept.val = true
    let st = station.untracked()
    let name = own.stations_by.peek(st).map(fn(s) { s.name }).unwrap_or(d0.station_name)
    @sfbase.board_draft_set(src, ws, id, field.text(), st, name)
    // (the next one written goes where this one was sent last)
    if st != d0.station { own.station.set(st) }
  }
  // (where it may go: the workspace's stations while this device holds every file it carries, as its composer goes up
  // to whichever station it is sent to; else its own alone, the station that keeps the files it was given)
  let stations = fn() {
    let all = (own.stations)()
    let here = @sfbase.writing(src, @sfbase.board_file_key(ws, id)).files.get().map(fn(f) { text(Some(f), "id") })
    if d0.files.iter().all(fn(f) { here.contains(f.id) }) {
      all
    } else {
      all.filter(fn(s) { s.station == d0.station })
    }
  }
  @sf.panel_nodes(
    board_words("edit"),
    fn(p, close) {
      p.gap(Is(12.0)) |> ignore
      // (everything it holds starting on its title's line: the words where they start, its pictures, and the station's
      // mark past the room its own ground keeps round it)
      let words_at = fn() { @sf.panel_title_at_node(p) }
      p.box(fn(fb) {
      fb.padding(By(fn() { (words_at(), 0.0, words_at(), 0.0) })) |> ignore
      // (round its words the field's to a press too: a tap its caret and its menu to paste, a long press its 粘贴)
      @ui.field_backdrop(fb, field)
      let typed = @ui.field(
        fb,
        field,
        placeholder=board_words("placeholder"),
        label=board_words("placeholder"),
        max_lines=8,
        enter_sends=true,
        submitted=fn(_) {
          keep()
          close()
        },
        size_by=fn() { @sf.theme().t.ui },
        colors_by=fn() {
          let pal = @sf.theme().p
          (pal.text, pal.subtle, pal.accent)
        },
      )
      typed.min_height(Is(Some(32.0))).width_share(Is(1.0)) |> ignore
      // (the keys in it as the panel opens, however it is shown: the panel's layer gives them)
      @sf.panel_opens_in_node(typed)
      })
      |> ignore
      board_files_node(p, src, fn() { @sfbase.board_file_key(ws, id) }, fn() { d0.files }, in_panel=true)
      // (where it runs and on what, one row of choosers as a new chat's composer has them (new_choosers_node): its
      // station's, as wide as it needs, then its model's, leaving out its parts where the row has not the room; the
      // station's mark under the words' start, its ground out past it by the room it keeps round its mark)
      p.box(fn(on) {
        on
        .row(Is(true))
        .gap(Is(@ui.Space::px(S1)))
        .lines_up(Is(Some(Middle)))
        .min_width(Is(Some(0.0)))
        .margin(By(fn() { ((words_at() - @ui.Space::px(S2)).max(0.0), 0.0, 0.0, 0.0) }))
        |> ignore
        // (in a box of its own, the choice making none it gives back, never narrower than it)
        on.box(fn(c) {
          c.shrink(Is(0.0)) |> ignore
          @sfbase.station_choice_node(
            c,
            stations,
            fn() { station.get() },
            fn(at) { station.set(at) },
            title=board_words("goes-on"),
            label=fn(name) { board_words("goes-on") + ": " + name },
            chooser=true,
          )
        })
        |> ignore
        // (what was picked for it on the station it goes to: its own on each; in a row of its own, as wide as what it
        // says, not stretched across what the row leaves)
        on.pick(fn() { station.get() }, at_once=true, fn(m, st) {
          m.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          model_triple_node(m, src, st, @sfbase.board_pick_of(id), small=true)
        })
      })
      |> ignore
    },
    from=Node(from),
    gone=keep,
    foot=fn(f, close) {
      @sf.button_node(f, fn() { @sf.t("common.done") }, fn() {
        keep()
        close()
      })
      |> ignore
      @sf.button_node(f, fn() { board_words("dispatch") }, fn() {
        keep()
        close()
        start()
      }, tone=Primary)
      |> ignore
    },
  )
}

///|
/// A round key standing in the top end corner of card `w` holds while `when` holds, over it, concentric with the card's
/// corner (card_key_in from its top and its end), not part of what flies with the card (View::shared): its title keeps
/// clear of it (card_title_end).
fn card_corner_key(w : @view.View, tips : @sf.TipLayer, when : () -> Bool, icon : String, label : () -> String, press : () -> Unit) -> Unit {
  w.show(when, fn(o) {
    o.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))) |> ignore
    o.box(fn(k) {
      k.margin(Is((0.0, card_key_in(), card_key_in(), 0.0))).shrink(Is(0.0)) |> ignore
      @sf.icon_button_node(k, icon, label, press, tips~, size=card_key, icon_size=14.0) |> ignore
    })
    |> ignore
  }, at_once=true)
}

///|
/// How far a card's title stops short of its end where a key stands in its corner (card_corner_key's, and a gap).
fn card_title_end() -> Double {
  card_key_in() + card_key + 6.0 - card_pad
}

///|
/// The chat's card of row `name` in column `lane`, as its row in Home's list says its chat (chat_row_node's marks, in a
/// card's room): its title (two lines at most; bolder, the list's unread dot before it, while something in it is unread),
/// what marks it at its end (pinned, its station away or updating, opened by another chat's agent) and, done, 归档 at its
/// top end; where it stands now, led by the list's mark for it (a bell, the wait's arc, at work's spokes, a check, the
/// watch's beat; red where it failed) in the list's quiet inks (its words the page's ink where it is the viewer's turn,
/// red where it failed, else muted), two lines at most; where it runs (its station's mark only where it has one), where
/// it came from, its agents and its people as the list's rows show them (row_aside_node). Pressed, its chat beside the
/// board (wide) or its page; never dragged; right clicked, or held long by a finger,
/// the chat's menu (chat_menu_items, once its whole row is answered: WholeHeld), its time beside where it runs while
/// that shows.
fn board_chat_card(
  row : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  own : BoardOwn,
  name : String,
  lane : String,
  wide : Bool,
) -> Unit {
  // (listed in its column: one gone on to another column is that column's card now, not this one's; its own row read by
  // its key, told only as it changes)
  let found = fn() {
    match own.items_by.get(name) {
      Some(i) if board_holds(lane, i, own.me) => Some(i)
      _ => None
    }
  }
  // (as it was last listed: a card leaving keeps its words)
  let last : Ref[ChatItem?] = Ref(@signals.untracked(found))
  let item = fn() {
    match found() {
      Some(i) => {
        last.val = Some(i)
        Some(i)
      }
      None => last.val
    }
  }
  // (what reads a chat's row whole (its menu's, its people's): a row of nothing where none has come yet)
  let blank = @sfbase.chat_item(Json::object(Map([])))
  let item_now = fn() { item().unwrap_or(blank) }
  // (what of its row each part of it shows, each told only as that changes: a message or a thing of its chat that
  // changes none of it wakes nothing of the card)
  let head = @signals.computed(fn(_) { card_head_of(item()) })
  let state = @signals.computed(fn(_) { card_state_of(item()) })
  // (who is in it: its row as it was, while its agents and its people are)
  let aside = @signals.computed_by(
    fn(prev : ChatItem?) {
      let i = item_now()
      match prev {
        Some(p) if p.agents == i.agents &&
          p.people == i.people &&
          p.people_text == i.people_text &&
          p.creator == i.creator => p
        _ => i
      }
    },
    // (its row kept as it was where who is in it is the same: told only for another)
    same=physical_equal,
  )
  // (while its chat is being made, the words it was started with: not 新对话)
  let title = fn() { head.get().title }
  let r = fn() { item().map(fn(i) { row_ref(i) }) }
  let stands = fn() { if head.get().done { "done" } else { "" } }
  let open = fn() {
    guard @signals.untracked(r) is Some(r) else { return }
    if wide && @signals.untracked(own.side) {
      let opening = match (@sfbase.board_pick.untracked(), @signals.untracked(item)) {
        (Some(p), Some(i)) => !@sfbase.row_is(i, p)
        _ => true
      }
      @sfbase.board_pick.set(if opening { Some(r) } else { None })
      // (its column whole beside the chat as it opens)
      if opening {
        (own.reveal)(lane)
      }
    } else {
      // (in the wide frame's pane with no room for it beside the board: the list again, the chat open beside it, as
      // 全屏打开 has it; else (小屏) its page over the board, back to it)
      if wide && own.beside_offered {
        @sfbase.board_set(src, false)
      }
      open_page(Chat(r))
    }
  }
  // (archived from here: its chat no more beside the board)
  let unpick = fn() {
    match @signals.untracked(item) {
      Some(i) if @sfbase.board_pick.untracked().map(fn(p) { @sfbase.row_is(i, p) }).unwrap_or(false) =>
        @sfbase.board_pick.set(None)
      _ => ()
    }
  }
  let archive = fn() {
    match @signals.untracked(item) {
      Some(i) => {
        unpick()
        archive_row(src, i)
      }
      None => ()
    }
  }
  // (picked only where its chat shows beside the board: no ground of it left where there is not the room)
  let picked = fn() { (own.picked)(name) && (own.side)() }
  // the hand on it (CardHand), its chat's whole row held while the hand is down on it, its menu open, or a press waits
  // for it (WholeHeld, as a row's)
  let hand = CardHand::new()
  let lift = CardLift::new()
  let menu_open = @signals.computed(fn(_) { item().map(fn(i) { row_menu_open(i) }).unwrap_or(false) })
  let menu_on = fn() { menu_open.get() }
  let pressing = Ref(false)
  let whole = WholeHeld::new(src, item_now, fn() { pressing.val || menu_on() })
  let card_at : Ref[@view.View?] = Ref(None)
  let menu_ok = fn() { item().map(row_menu_offered).unwrap_or(false) }
  // (its menu, once its whole row is answered, whole: right clicked at the pointer; held long from the card, felt)
  let open_menu = fn(x : Double, y : Double, held : Bool) {
    hand.up()
    guard @signals.untracked(menu_ok) else { return }
    // (held by a finger: lifted a little at once, while its whole row may still be on its way)
    if held {
      lift.held.set(true)
    }
    whole.then(fn(i) {
      let from = match card_at.val {
        Some(c) if held && c.alive() => {
          let (cx, cy, cw, ch) = c.placed_window_now()
          @sf.Beside::At(cx, cy, cw, ch)
        }
        _ => @sf.at_point(x, y)
      }
      if held {
        @sf.menu_held_node()
      }
      @sf.menu(chat_menu_items(src, i, share_from=fn() { from }, asks_rename=true, archived=unpick), from~)
      rows.menu_for = @sfbase.row_name(i)
      rows.menu_serial = @sf.last_presented()
      lift.put_up(held)
    }, fn() {  })
  }
  let down = fn() {
    pressing.val = true
    whole.asks()
    match card_at.val {
      Some(c) if c.alive() => hand.down(c)
      _ => ()
    }
  }
  let up = fn() {
    pressing.val = false
    lift.held.set(false)
    hand.up()
    whole.idle()
  }
  // (its time while its menu is open, its whole row answered then)
  let shows_time = fn() { menu_on() && @sfbase.whole_answered(src, item_now()) }
  // (a draft's chat come as it was started: from where its card was; by its key alone, as the column lists it: its row
  // by key may come a moment after, items_by following the chats as a reaction)
  let came = match own.start_from {
    Some((sid, _)) if sid == name => own.start_from
    _ => None
  }
  if came is Some(_) {
    own.start_from = None
  }
  row.box(fn(w) {
  let raised = lift.node(w)
  match came {
    Some((_, (fx, fy, fw, _))) =>
      w.flies_in(@motion.flight_by(@motion.moved()), fn(to) { Some((fx, fy, fw, to.3)) }) |> ignore
    None => ()
  }
  w.box(fn(card) {
    card_at.val = Some(card)
    card.shadow(By(fn() { card_shadow(raised()) })) |> ignore
    // (one thing by its row's key: the same from the draft's card on through the core's pending row to its station's)
    // (narrow, its column's alone: the track slides from one to another, a card going on to another column is not
    // flown across it)
    @motion.shared(card, board_shared(own, lane, name) + (if wide { "" } else { "@" + lane })) |> ignore
    let ground = card_ground(card, picked, fn() { hand.lit(card, menu_on) }, raised)
    @sf.action_box_node(card, title, fn(_) { open() }, in_node=true, fn(card) {
      // (never dragged, wide or narrow: a finger on it scrolls its column; right clicked, its menu; held long by a finger,
      // its menu; a mouse's button held is a press as long as any)
      card.on_menu(fn(e) { open_menu(e.wx, e.wy, false) }) |> ignore
      @sf.presses_held_node(
        card,
        open,
        @ui.long_press_ms,
        fn(d) { if !@sf.pointer_rests() { open_menu(d.wx, d.wy, true) } },
        down=fn(_) { down() },
        up~,
      )
    })
    |> ignore
    // (a pointer over it lights it, asking nothing: its whole row is asked as the hand goes down on it or its menu is
    // asked for, never for each card a pointer passes over)
    hand.watch(card)
    card.reacts(menu_on, fn(on) { if !on { whole.idle() } })
    card.owns(fn() { whole.drop() }) |> ignore
    // its title, and what marks it at its end
    card.box(fn(h) {
      h.row(Is(true)).gap(Is(card_head_gap)).lines_up(Is(Some(Start))) |> ignore
      // (something in it unread: the list's dot before its title, on its first line)
      let unread = fn() { head.get().unread }
      h.show(unread, fn(m) {
        card_line_slot(m, card_title_look, chat_mark_slot_w)
        chat_mark_node(m, fn() { "done" })
      }, along_row=true)
      // (ended: bolder while not read, quieter once read, whatever the board is grouped by; else bolder while something
      // in it is unread: a card of another state's column is never one ended)
      let ended = lane == "done" || !@sfbase.board_lanes.contains(lane)
      @sf.words_node(h, title, fn() {
        match (ended && head.get().done, unread()) {
          (true, true) | (false, true) => card_title_fresh_look
          (true, false) => card_title_read_look
          (false, false) => card_title_look
        }
      })
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      |> ignore
      card_title_marks(h, tips, fn() { head.get() })
      h.padding(By(fn() { (0.0, 0.0, if stands() == "done" { card_title_end() } else { 0.0 }, 0.0) })) |> ignore
    })
    |> ignore
    // where it stands now
    card_state_node(card, fn() { state.get() })
    // the chats it leads still at work (1 个子会话进行中): why it is at work, its mark on its line's first line
    card.show(fn() { state.get().subchats != "" }, fn(sub) {
      sub.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Start))) |> ignore
      sub.box(fn(m) {
        card_line_slot(m, card_meta_look, state_icon)
        @sf.icon_node(m, "spawned", 13.0, By(fn() { @sf.theme().p.muted })) |> ignore
      })
      |> ignore
      @sf.words_node(sub, fn() { state.get().subchats }, fn() { card_meta_look })
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    // (what of its row its foot shows, told only as that changes, as its other parts: its words as it was last listed,
    // a card leaving keeps them)
    let foot = @signals.computed(fn(prev : CardFoot?) {
      let i = item()
      // (its time in words where its row says it, or where its whole row is answered and shown (its menu open): a list's
      // rows come without it, a chat's whole row is asked only as the hand comes to it, never a card's subscription of
      // its own)
      let said = match found() {
        Some(i) => {
          let ago = if i.ago != "" {
            i.ago
          } else if shows_time() {
            @sfbase.whole_row(src, i).map(fn(w) { w.ago }).unwrap_or("")
          } else {
            ""
          }
          if ago == "" {
            i.station_name
          } else {
            i.station_name + " · " + ago
          }
        }
        None => prev.map(fn(f) { f.said }).unwrap_or("")
      }
      match i {
        Some(i) =>
          {
            emoji: i.station_emoji,
            icon: i.station_icon,
            station: i.station_name,
            offline: i.offline is Some(_),
            said,
            origin: i.origin_kind,
            origin_said: i.origin_text,
          }
        None => { emoji: "", icon: "", station: "", offline: false, said, origin: "", origin_said: "" }
      }
    })
    // where it runs, where from, when; its agents and its people at the end
    card.box(fn(m) {
      m.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))).padding(Is((0.0, 2.0, 0.0, 0.0))) |> ignore
      // (its station's mark only where it has one: none of its own, its name where the title begins)
      let emoji = fn() { foot.get().emoji }
      let icon = fn() { foot.get().icon }
      m.show(fn() { @sf.has_station_mark(emoji(), icon()) }, fn(k) {
        k.says(By(fn() { Some(@view.said(Image, label=foot.get().station)) })) |> ignore
        @sf.station_mark_node(
          k,
          emoji,
          icon,
          card_station_mark,
          fn() { if foot.get().offline { @sf.theme().p.subtle } else { @sf.theme().p.muted } },
          own.stint,
        )
      }, along_row=true)
      @sf.words_node(m, fn() { foot.get().said }, fn() { card_meta_look }).shrink(Is(1.0)).min_width(Is(Some(0.0)))
      |> ignore
      // (where it came from, by its platform's mark: Comma's one colour, in the page's ink, as the list's)
      // (none made where it came from nowhere said)
      m.each(fn() { if foot.get().origin == "" { [] } else { [foot.get().origin] } }, fn(k) { k }, fn(o, kind) {
        let kind = kind.untracked()
        o.says(By(fn() { Some(@view.said(Image, label=foot.get().origin_said)) })) |> ignore
        if kind == "comma" {
          @sf.drawable_node(o, "comma", card_origin_mark, tint=fn() { Some(@sf.theme().p.text) }) |> ignore
        } else {
          @sf.origin_mark_node(o, fn() { kind }, card_origin_mark) |> ignore
        }
      }, at_once=true)
      // (who is in it, as the list's rows show them: its agents' marks a maker's once (past three, +N), its people's
      // faces (their pictures asked for on the page's time), who started it ringed; the card's ground round them: at
      // the foot's end, the room before them its own)
      m.box(fn(a) {
        a.grow(Is(1.0)).shrink(Is(0.0)) |> ignore
        row_aside_node(a, src, tips, fn() { aside.get() }, "agents", ground, own.stint)
        a.lies_along(Is(End)) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  card_corner_key(w, tips, fn() { stands() == "done" }, "archive", fn() { board_words("archive") }, archive)
  })
  |> ignore
  ignore(lane)
}

///|
/// What marks a card's chat at its title's end (chat_row_node's, each in a column on its title's first line, its tip
/// saying what it is): pinned; its station offline or its link coming back (unplugged, its update's mark while it
/// updates); opened by another chat's agent. One structure for all of them, made only where any is (a card's own most
/// often none).
fn card_title_marks(head : @view.View, tips : @sf.TipLayer, said : () -> CardHead) -> Unit {
  let ink = fn() { @sf.theme().p.subtle }
  // (which: pinned, away (unplugged, updating), opened by another chat; each in its column on the title's line, beside
  // the title as the title's line's own: nothing made round them, none at all where none is)
  let which = fn() {
    let h = said()
    let out : Array[CardMark] = []
    if h.pinned {
      out.push(Pinned)
    }
    if h.gone == 1 {
      out.push(Unplugged)
    } else if h.gone == 2 {
      out.push(Updating)
    }
    if h.opener {
      out.push(Opened)
    }
    out
  }
  head.each(which, fn(k) { k }, fn(s, k) {
    let k = k.untracked()
    let says = match k {
      Pinned => fn() { board_words("pinned") }
      Unplugged | Updating => fn() { said().away }
      Opened => fn() { said().opened }
    }
    card_line_slot(s, card_title_look, kind_slot_w)
    s.says(By(fn() { Some(@view.said(Image, label=says())) })) |> ignore
    match k {
      Pinned => @sf.icon_node(s, "pin", card_mark_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      Unplugged => @sf.icon_node(s, "unplug", card_mark_icon, By(ink)) |> ignore
      Updating => @sf.updating_mark_node(s, card_mark_icon, ink)
      Opened => @sf.icon_node(s, "spawned", card_mark_icon, By(ink)) |> ignore
    }
    @sf.tip_node(tips, s, says, within=true) |> ignore
  }, at_once=true)
}

///|
/// A mark at a card's title's end (card_title_marks').
#derive(Eq, Hash)
enum CardMark {
  Pinned
  Unplugged
  Updating
  Opened
}

///|
/// A column `w` wide in `m`, as tall as the first line of words drawn as `look` beside it at the system's size of words
/// (board_line), what it holds in its middle: a mark on that line, never centred on the lines under it.
fn card_line_slot(m : @view.View, look : @ui.TextStyle, w : Double) -> Unit {
  m
  .row(Is(true))
  .width(Is(Some(w)))
  .height(By(fn() { Some(board_line(m, look)) }))
  .shrink(Is(0.0))
  .lines_up(Is(Some(Middle)))
  .lies_along(Is(Middle))
  |> ignore
}

///|
/// Where a card's chat stands (board_chat_card's), in `card`: led on its first line by the list's mark for it (red where
/// it failed or a message did not go; a bell where it is the viewer's turn; the wait's arc where it waits on something
/// (CI, a reply); at work's spokes; a check, the archive's box once settled; the watch's beat), its words two lines at
/// most in the list's inks: red where it failed, the page's ink where it is the viewer's turn (who decides in bold, as the
/// list says it), else muted.
fn card_state_node(card : @view.View, state : () -> CardState) -> Unit {
  let look = fn() {
    let k = state()
    if k.failed {
      card_state_red
    } else if k.turn {
      card_state_turn
    } else if k.fresh {
      card_state_done()
    } else {
      card_state_muted
    }
  }
  let ink = fn() {
    let p = @sf.theme().p
    let k = state()
    if k.turn {
      p.text
    } else if k.fresh {
      p.green_ink
    } else {
      p.muted
    }
  }
  card.box(fn(s) {
    s.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Start))) |> ignore
    // (its mark in a column as tall as its first line: the column made with the mark it holds)
    s.pick(fn() { state().mark }, fn(m, k) {
      card_line_slot(m, card_state_muted, state_icon)
      match k {
        "" => ()
        "alert" | "busy" => chat_mark_node(m, fn() { k })
        icon => lead_icon_node(m, icon, ink, centred=true)
      }
    }, at_once=true)
    s.box(fn(w) {
      w.grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      // (its mark says where it stands, by state or not: no column's name before it; a decision's who in bold)
      w
      .words_runs(By(fn() {
          let k = state()
          if k.bold != "" {
            [@ui.span(k.bold, weight=600), @ui.span(k.said.clamped_view(start=k.bold.length()).to_owned())]
          } else {
            [@ui.span(k.said)]
          }
        }))
      .words_look(By(fn() { @ui.style_words(look()) }))
      .ink(By(fn() { @ui.style_ink(look()) }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What a card shows of its chat's row on its title's line (board_chat_card's), told only as it changes: its title
/// (while its chat is being made, the words it was started with), something in it unread, done (its archive key, its
/// title clear of it), and what marks it at its title's end: pinned; its station away (1 unplugged, 2 updating; why);
/// opened by another chat's agent (by which).
#derive(Eq)
struct CardHead {
  title : String
  unread : Bool
  done : Bool
  pinned : Bool
  gone : Int
  away : String
  opener : Bool
  opened : String
}

///|
/// What a card shows on its title's line of row `i` (none: a card as it is done, nothing said).
fn card_head_of(i : ChatItem?) -> CardHead {
  guard i is Some(i) else {
    return { title: "", unread: false, done: true, pinned: false, gone: 0, away: "", opener: false, opened: "" }
  }
  let away = match (i.offline, i.reconnecting) {
    (Some(why), _) | (None, Some(why)) => why
    _ => ""
  }
  {
    title: @sfbase.board_title_of(i),
    unread: i.unread,
    done: @sfbase.board_lane_of(i) == "done",
    pinned: i.pinned == Some(true),
    gone: if away == "" { 0 } else if i.updating { 2 } else { 1 },
    away,
    opener: i.opener is Some(_),
    opened: match i.opener {
      Some(o) => if o.archived { o.text + " · " + o.note } else { o.text }
      None => ""
    },
  }
}

///|
/// Where a card's chat stands (card_state_node's), told only as it changes: its mark ("" none), failed (red), the
/// viewer's turn (the page's ink), its words and who a decision waits for, led in bold ("" none).
#derive(Eq)
struct CardState {
  mark : String
  failed : Bool
  turn : Bool
  said : String
  bold : String
  /// in 待收口, a result just delivered and not read: its check and its words in green
  fresh : Bool
  /// the chats it leads still at work, in words ("" none)
  subchats : String
}

///|
/// Where row `i` stands, as its card says it (none: done, nothing said).
fn card_state_of(i : ChatItem?) -> CardState {
  let failed = i.map(fn(i) { i.unsent || i.state == "failed" }).unwrap_or(false)
  let stands = i.map(fn(i) { @sfbase.board_lane_of(i) }).unwrap_or("done")
  let lead = i.map(fn(i) { @sfbase.row_lead(i) }).unwrap_or("")
  let mark = if failed {
    "alert"
  } else {
    match stands {
      "done" => if lead == "archive" { "archive" } else { "done" }
      "watch" => "watch"
      "run" => if lead == "wait" { "wait" } else { "busy" }
      "wait" => "need"
      _ => ""
    }
  }
  let said = card_said(i)
  let bold = match i {
    Some(i) if lead == "decision" && i.state_lead_text != "" && said.has_prefix(i.state_lead_text) => i.state_lead_text
    _ => ""
  }
  {
    mark,
    failed,
    turn: !failed && stands == "wait",
    said,
    bold,
    fresh: !failed && stands == "done" && i.map(fn(i) { i.unread }).unwrap_or(false),
    subchats: i.map(fn(i) { i.subchats }).unwrap_or(""),
  }
}

///|
/// What a card's foot shows of its chat's row (board_chat_card's), told only as it changes: its station's mark, name and
/// whether it is offline, its words (its station and its time), where it came from.
#derive(Eq)
struct CardFoot {
  emoji : String
  icon : String
  station : String
  offline : Bool
  said : String
  origin : String
  origin_said : String
}

///|
/// What a card says of where its chat stands: the core's line for it, else the last thing said in it.
fn card_said(i : ChatItem?) -> String {
  guard i is Some(i) else { return "" }
  let rest = i.state_rest.trim(chars=" ·").to_owned()
  let whole = match (i.state_text, i.decision_text, i.last) {
    (Some(s), _, _) if s != "" => s
    (_, Some(d), _) if d != "" => d
    (_, _, Some(l)) => l
    _ => ""
  }
  // (its mark before it says where it stands already: the core's lead word not said again, as the sidebar's rows have
  // it; a decision keeps who it waits for, a failure what went wrong)
  match i.state_lead {
    "done" | "need" if rest != "" => rest
    "watch" => {
      let w = if rest != "" { rest } else { whole }
      let lead = @sf.t("web-main.board.watch_prefix")
      if lead != "" && w.has_prefix(lead) { w.exact_view(start=lead.length()).to_owned() } else { w }
    }
    _ => whole
  }
}

///|
// kept across runs: a value (no field of it changes)
let card_title_look : @ui.TextStyle = @ui.text_style(size=Ui, weight=Medium, wrap=true, max_lines=2, leading=L5)

///|
// kept across runs: a value (no field of it changes)
let card_title_fresh_look : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=true, max_lines=2, leading=L5)

///|
// kept across runs: a value (no field of it changes)
let card_title_read_look : @ui.TextStyle = @ui.text_style(size=Ui, weight=Normal, wrap=true, max_lines=2, leading=L5)

///|
// kept across runs: a value (no field of it changes)
let card_meta_look : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let card_state_muted : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=true, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let card_state_turn : @ui.TextStyle = @ui.text_style(size=Meta, color=Fg, wrap=true, max_lines=2)

///|
// kept across runs: a value (no field of it changes)
let card_state_red : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=true, max_lines=2)

///|
/// Where it stands in 待收口, a result just delivered and not read: the theme's green ink, read on the card's white.
fn card_state_done() -> @ui.TextStyle {
  let p = @sf.theme().p
  @ui.text_style(size=Meta, color=Data(p.green_ink), wrap=true, max_lines=2)
}

///|
/// The room between what stands on a card's title's line; the unread dot's column (the list's mark column: mark_slot's
/// 10); the marks at its end, its station's mark and where it came from.
let card_head_gap : Double = 6.0

///|
let chat_mark_slot_w : Double = 10.0

///|
let card_mark_icon : Double = 14.0

///|
let card_station_mark : Double = 14.0

///|
let card_origin_mark : Double = 13.0

///|
// kept across runs: a value (no field of it changes)
let lane_title_look : @ui.TextStyle = @ui.text_style(size=Ui, weight=Semibold, wrap=false)

///|
// kept across runs: a value (no field of it changes)
let lane_count_look : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)

///|
/// The key a card is one thing by (View::shared): its chat's (or its draft's, the chat it becomes), within how the board is
/// grouped (another grouping's columns another board, nothing flying between them); by person, within its column too (a
/// chat in each of its people's).
fn board_shared(own : BoardOwn, lane : String, id : String) -> String {
  let group = @signals.untracked(own.group)
  "board/" + group + "/" + (if lane.has_prefix("person:") { lane + "/" } else { "" }) + id
}

