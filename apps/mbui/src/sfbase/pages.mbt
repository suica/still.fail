// The app's pages, as a stack both frames show (the phone's pages pushed and swiped back; the wide frame's pane beside
// the rail): what a page is, the stack and what the app keeps of it; a chat, a drive's place and a station's screen as
// a page names them.

///|
/// A page of the stack.
#derive(Eq)
pub(all) enum Page {
  Home
  /// a chat (chat.mbt)
  Chat(ChatRef)
  /// the archived chats (from the filter's menu)
  Archived
  /// settings (the gear)
  Settings
  /// 文件: every station's folders lent (drive.mbt)
  Files
  /// a page of a station's drive: its roots, or a folder (drive.mbt)
  Drive(DriveAt)
  /// a text of a drive, read (drive_reader.mbt)
  DriveRead(DriveAt)
  /// a video or a song of a drive, played (play.mbt)
  DrivePlay(DriveAt)
  /// a web service an agent started, its page (service.mbt): its station, its job
  Service(String, String)
  /// a visualization as a page of its own: its station, the session that keeps it, its
  /// path and its name
  PreviewFile(String, String, String, String)
  /// an agent's execution history (history.mbt): its chat, its session, the transcript entry it opens at (a link's
  /// `entry`; None: its newest)
  History(ChatRef, String, Int?)
  /// a new chat (newchat.mbt), rising from the bottom; it becomes the chat it makes, in place
  NewChat
  /// a place of the bottom bar's other than the chats and 文件 (stations, profiles, connects, usage, archive):
  /// its page at the stack's root
  Place(String)
  /// a page under settings (src/sfapp/settings: me, appearance, stations, the workspace…)
  Setting(@settings.Route)
  /// a station's screen, seen and driven (screen_view.mbt), over the app as Android's ScreenActivity is
  Screen(ScreenAt)
  /// one of a station's terminals (src/sfpages terminal_view_node.mbt), over the whole window as a screen is
  Terminal(TerminalAt)
  /// a tab of a chat's side panel (a file in the viewer, a mini-program, a web service, a visualization: tab_full.mbt)
  /// in a window of its own (window.mbt), its third place; never on the stack of the app's window
  SideTab(TabFull)
}

///|
/// Keep a chat's own reader while its navigation entry remains on the stack, including while another page covers it.
/// Other pages keep only the readers of their visible views.
pub fn page_chat_reader(src : Source, entry : @view.View, serial : Int) -> (Page) -> Unit {
  let held : Ref[(String, TopicLease)?] = Ref(None)
  // (let go of as its entry is put by on the stack's kept left, page_entry_parked: no chat held while it is not on the
  // stack; asked again as it is read again, put on once more)
  let let_go = fn() {
    let previous = held.val
    held.val = None
    match previous { Some((_, reader)) => reader.release(); None => () }
  }
  entry.owns(fn() {
    if active_chat_readers.get(serial) is Some(f) && physical_equal(f, let_go) {
      active_chat_readers.remove(serial)
    }
  })
  |> ignore
  fn(page) {
    match page {
      Chat(r) => {
        let key = r.station + "\u{1}" + r.session
        if held.val is Some((old, reader)) && old == key && reader.alive() {
          page_chat_ready(serial, src, key)
          return
        }
        let next = src.lease_topic("chat", chat_params(r))
        next.bind_to(entry)
        let previous = held.val
        held.val = Some((key, next))
        active_chat_readers[serial] = let_go
        match previous { Some((_, reader)) => reader.release(); None => () }
        if next.alive() { page_chat_ready(serial, src, key) }
      }
      _ => {
        let previous = held.val
        held.val = None
        match previous { Some((_, reader)) => reader.release(); None => () }
      }
    }
  }
}

///|
/// What puts by at rest the sources each entry's page reads by (Source::owned_by_parkable: page_entry_source's, a chat
/// page's own), by its serial: put by once the entry kept left has told what it left (page_entry_parked), taken back as
/// it is read again (page_entry_read).
let entry_parks : Map[Int, Array[(Bool) -> Unit]] = Map([])

///|
/// The entries put by on the stack's kept left (page_entry_parked), by serial, till taken back (page_entry_read) or let
/// go for good (page_entry_gone): whether their sources are put by yet (entries_kept_park_due).
let entries_kept : Map[Int, Bool] = Map([])

///|
/// The sources of the entries put by on the stack's kept left and not yet so put by at rest (entry_parked): once what
/// they left is told (the frame's pages left, chat_left, reading through them), in that frame's build, so that what
/// they held is let go of as that frame ends; else as the frame ends where no build tells it.
pub fn entries_kept_park_due() -> Unit {
  let due : Array[Int] = []
  for serial, done in entries_kept {
    if !done {
      due.push(serial)
    }
  }
  for serial in due {
    entries_kept[serial] = true
    entry_parked(serial, true)
  }
}

///|
/// `park` (Source::owned_by_parkable's, of a source owned by `view`) entry `serial`'s, till `view` goes.
fn entry_park_said(serial : Int, view : @view.View, park : (Bool) -> Unit) -> Unit {
  match entry_parks.get(serial) {
    Some(all) => all.push(park)
    None => entry_parks[serial] = [park]
  }
  view.owns(fn() {
    match entry_parks.get(serial) {
      Some(all) => {
        let rest = all.filter(fn(p) { !physical_equal(p, park) })
        if rest.is_empty() {
          entry_parks.remove(serial)
        } else {
          entry_parks[serial] = rest
        }
      }
      None => ()
    }
  })
  |> ignore
}

///|
/// Entry `serial`'s sources put by (true) or taken back (false): entry_parks'.
fn entry_parked(serial : Int, on : Bool) -> Unit {
  match entry_parks.get(serial) {
    Some(all) => for p in all.copy() { p(on) }
    None => ()
  }
}

///|
/// The chat each entry's page holds (page_chat_reader), by its serial: what lets it go as the entry is put by on the
/// stack's kept left (page_entry_parked).
let active_chat_readers : Map[Int, () -> Unit] = Map([])

///|
/// What a stack keeps of a page that left it (nav_view's and nav_flat_view's `keeps_left`): a chat's page whole, its
/// composer too, by its station and session and the kind it is made as (chat_page_kind); none other.
pub fn chat_page_left_key(p : Page) -> (String, String)? {
  match p {
    Chat(r) => Some((r.station + "\u{1}" + r.session, chat_page_kind()))
    _ => None
  }
}

///|
/// The kind a chat's page is made as by a shell's `made` (nav_view's: a kind changed, the page made again in its place).
pub fn chat_page_kind() -> String {
  "chat"
}

///|
/// Whether Farview browser tabs (`browser:fv_…`) are drawn natively on this device (实验性功能 › Farview 原生标签页渲染).
// kept across runs: false as a run begins (reset)
pub let farview_native : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether Home offers and shows the board view on this device (实验性功能 › 对话列表看板视图).
// kept across runs: false as a run begins (reset)
pub let board_feature : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// How a chat's column is laid out as the shell has it at a node's moment (chat_page_made's `narrower`): how much narrower
/// than it is drawn (`by`), how far across it is moved (`across`), and the width it is laid out at (`laid`: where that
/// steps, all it holds is laid out anew at once, View::lays_anew); the width at the other end of its way (`toward`:
/// where it set off from, or the wider end it is laid out short of) and how much of the way it has still to go to be
/// drawn as at `laid` (`toward_by`, 1 … 0): what is arranged otherwise at the two widths (a message's picture out in the
/// margin or over its head, chat_narrow_w) drawn that much of the way to how it is at `toward`, never stepping where the
/// column is laid out anew. None at rest but the width.
pub(all) struct ColumnLaid {
  by : Double
  across : Double
  laid : Double
  toward : Double
  toward_by : Double
}

///|
/// Each chat's column on the page's way to another width, by its station and session (`\u{1}` between): how it is laid
/// out at a node's moment, chat_page_made's `narrower`, said as its column is made and let go with it.
// kept across runs: said by each chat's page made, let go with its column
let columns_laid : Map[String, (@view.View) -> ColumnLaid] = Map([])

///|
/// What each chat's list does as its column sets off on the page's way to another width (by its station and session,
/// `\u{1}` between: said by the list as it is made, let go with it): its rows laid out anew there going on its one way.
// kept across runs: said by each chat's list made, let go with it
let columns_set_off : Map[String, () -> Unit] = Map([])

///|
// kept across runs: how far what sets the column off goes while it is told so (column_sets_off), 0 otherwise
let column_set_off_over_ref : Ref[Double] = Ref(0.0)

///|
/// How far what sets a chat's column off on its way goes (a side panel sliding in or out), read as it is told so
/// (column_sets_off's `over`): what goes on that way with it (a row's room, the list's head, the composer's foot) a
/// Move by as far (@ui.move_ms), as long as it. 0 where none was said, or outside its telling.
pub fn column_set_off_over() -> Double {
  column_set_off_over_ref.val
}

///|
/// Chat `chat`'s list told, at the cause of the page's way to another width, that its column sets off on it; `over`:
/// how far what sets it off goes (column_set_off_over), 0 none said; `resize` false: only the count told, no list or
/// row told to lay out anew (the fold's own way).
pub fn column_sets_off(chat : String, over? : Double = 0.0, resize? : Bool = true) -> Unit {
  // (the page set off on its way by its cause (a side panel opened or shut): what it changes on the chat's page goes its
  // way, @view.transition)
  column_set_off_over_ref.val = over
  @view.transition(fn() {
    columns_set_off_said.set(columns_set_off_said.untracked() + 1)
    if resize {
      match columns_set_off.get(chat) {
        Some(f) => f()
        None => ()
      }
      // (each row's room over it told after its list, in the same change: column_set_off_each)
      for _, f in columns_set_off_each.copy() {
        f()
      }
    }
  })
  column_set_off_over_ref.val = 0.0
}

///|
/// What a row's room over it does as a chat's column sets off on the page's way (column_sets_off), by the order it was
/// said in: told directly, no binding of each row's following the count (columns_set_off_said).
// kept across runs: said by each row's room as it is made, let go with it
let columns_set_off_each : Map[Int, () -> Unit] = Map([])

///|
// kept across runs: the order the next one said is told in
let columns_set_off_next : Ref[Int] = Ref(0)

///|
/// `f` done as any chat's column sets off on the page's way (column_sets_off), till node `n` goes: what a row's room over
/// it, worked out of the width the column is laid out at, says then (its height's change made on its list's way).
pub fn column_set_off_each(n : @view.View, f : () -> Unit) -> Unit {
  let k = columns_set_off_next.val
  columns_set_off_next.val = k + 1
  columns_set_off_each[k] = f
  n.owns(fn() { columns_set_off_each.remove(k) }) |> ignore
}

///|
/// How many times a chat's column has set off on the page's way to another width (column_sets_off): what is bound to the
/// column's place on that way only once it has set off follows it (chat_jump_node's stands).
// put back by reset: what is first drawn reads whether any column has set off yet (chat_body_node's clip)
let columns_set_off_said : @signals.Signal[Int] = @signals.signal(0)

///|
/// What follows a chat's column setting off on the page's way (columns_set_off_said).
pub fn column_set_off_count() -> Int {
  columns_set_off_said.get()
}

///|
/// What chat `chat`'s list in node `n` does as its column sets off on the page's way (column_sets_off), till `n` goes.
pub fn column_set_off_by(chat : String, n : @view.View, f : () -> Unit) -> Unit {
  columns_set_off[chat] = f
  n.owns(fn() { if columns_set_off.get(chat) is Some(g) && physical_equal(g, f) { columns_set_off.remove(chat) } })
  |> ignore
}

///|
/// How chat `chat`'s column is laid out as node `n` is drawn (column_laid's `narrower`): none of it narrower or moved at
/// rest, or where its page says none. What stands at its right (a message of one's own, the round buttons over the
/// composer, the rail at its right) is laid out where its column is laid out, at the narrower end of its way, and drawn
/// moved by as much more as it would stand further right at the width the column is drawn at: past `across`, the rest
/// of how much wider it is drawn (`by`), so that it goes with the page's right edge as the words at its left go with
/// its left, none of it stepping where the column is laid out anew (the panel opened, shut).
pub fn column_laid(chat : String, n : @view.View) -> ColumnLaid {
  match columns_laid.get(chat) {
    Some(f) => f(n)
    None => { by: 0.0, across: 0.0, laid: 0.0, toward: 0.0, toward_by: 0.0 }
  }
}

///|
/// A chat's page made once in node `v` of a stack's (entry `serial`'s: nav_view's and nav_flat_view's `made`), and the
/// new chat that becomes it in place, the same page (a chat from the source it keeps while its entry is on the stack,
/// its reader held: page_entry_source, page_chat_reader). Over it a picture flying from its list while under its bar
/// (viewer_flight_slot), and over that its bar (`over`: given a node over the page, the chat's source, what the page
/// is now and its time on top, `stint`; made while `drawn` says its entry is drawn: shown, or kept shown in place
/// while the one on top waits). What it reads by, the source it keeps (its reads the page's, let go with it), given
/// back: what is beside it reads by it too. Its inside is what the page is, one in the other's place at once as it
/// changes: a new chat its nodes (`new_node`); a chat, one made so or a new chat become it in place (Nav::become),
/// chat `r`'s messages made by `body` in a column, given what makes its composer as nodes (by `foot_node`) in the node it is put in, the foot of the
/// messages' list, and whether its entry is drawn (as `drawn` says). On the
/// page's way to another width (a side panel sliding in or out beside it), its column laid out as at the narrower of
/// where the way set off and where it goes, from the frame it sets off till the one it is there, so that its rows are
/// laid out anew only at those two (as the old list's laid_w had it held), and moved across by as much as its rows'
/// words start further in at the width it is drawn at than at the one it is laid out at, so that they go across with
/// the page, never stepping where it is laid out anew: both the shell's to say, at a node's moment (`narrower`: how much
/// narrower, how far across; none at rest), and moved aside with all of it (`aside`, as a node is drawn: the pane's page
/// moved off what is folded over it), in the one offset of its column. Its composer, in the list's foot, is laid out at
/// the width the column is drawn at all the way. A new chat (`new_node`) is made over the column, leaving over the chat
/// it becomes.
pub fn chat_page_made(
  v : @view.View,
  src : Source,
  serial : Int,
  over? : (@view.View, Source, () -> Page?, () -> Int) -> Unit,
  stint? : () -> Int = fn() { 0 },
  drawn? : (Int) -> Bool = fn(serial) { app.nav.shows(serial) },
  body~ : (@view.View, Source, ChatRef, (@view.View) -> Unit, () -> Bool, () -> Bool) -> Unit,
  foot_node~ : (@view.View, Source, ChatRef, () -> Bool, () -> Double?) -> Unit,
  narrower? : (Source, @view.View) -> ColumnLaid,
  aside? : (@view.View) -> Double,
  new_node~ : (@view.View, Source) -> Unit,
) -> Source {
  let retained = page_entry_source(src, v, serial)
  // (the entry on top of its stack, not put by: what a page made for it reads and tells as drawn only then, never as it
  // slides away popped, still made and drawn)
  let on_stack = fn() { app.nav.top_stay().0 == serial && !app.nav.is_kept_left(serial) }
  // (what the shell says of its column read by the page's own source, what it holds the page's, let go with it: never
  // the window's)
  let narrower = narrower.map(fn(f) { fn(n : @view.View) { f(retained, n) } })
  let page_read = page_chat_reader(retained, v, serial)
  let (_, shown_park) = src.owned_by_parkable(v)
  entry_park_said(serial, v, shown_park)
  let aside_of = fn(n : @view.View) {
    match aside {
      Some(f) => f(n)
      None => 0.0
    }
  }
  v.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
  // (a chat's made as nodes inside, as what the page is: a new chat its own, a chat once it has become one in place,
  // Nav::become, its nodes, at once, the one in the other's place)
  // (which chat the page is, by its station and session, "" while a new chat; as it was once its entry is gone)
  let was = Ref("")
  v.pick(
    fn() {
      match app.nav.page_of(serial) {
        Some((Chat(r), _)) => was.val = r.station + "\u{1}" + r.session
        Some(_) => was.val = ""
        None => ()
      }
      was.val
    },
    fn(col, chat) {
      col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      let made = if chat == "" { None } else { @signals.untracked(fn() { app.nav.page_of(serial) }) }
      match made {
        Some((Chat(r), _)) => {
          // a column: the chat's messages growing to all of it, the composer in their list's foot at its own
          // height, its old view in a node of its own as yet (built as the stack's island is, what the page reads
          // read there)
          col.ground(By(fn() { @sf.theme().p.bg })) |> ignore
          // (on the page's way to another width, laid out as at the narrower end the whole way, at its left, and
          // moved across as its rows' words would be: the shell's to say, `narrower`, read as it is drawn; none at
          // rest)
          match narrower {
            Some(by) => {
              // (what of it stands at its right, or by the width it is drawn at, read by its parts: column_laid)
              let chat = r.station + "\u{1}" + r.session
              columns_laid[chat] = by
              col.owns(fn() { if columns_laid.get(chat) is Some(f) && physical_equal(f, by) { columns_laid.remove(chat) } })
              |> ignore
              // (laid out narrower than drawn: room at its right; wider (on its way to where the panel is gone):
              // past its right, cut there by what holds it)
              // (none of that at rest, by none: bound once a column has first set off on such a way, at that cause)
              col
              .offset(By(fn() { (by(col).across + aside_of(col), 0.0) }))
              .lays_anew(By(fn() { by(col).laid }))
              |> ignore
              let bound = Ref(false)
              col.reacts(fn() { column_set_off_count() > 0 }, fn(going) {
                if going && !bound.val && col.alive() {
                  bound.val = true
                  col
                  .padding(By(fn() { (0.0, 0.0, @sf.dmax(0.0, by(col).by), 0.0) }))
                  .margin(By(fn() { (0.0, 0.0, @sf.dmin(0.0, by(col).by), 0.0) }))
                  |> ignore
                  v.clips(By(fn() { by(v).by < -0.5 })) |> ignore
                }
              })
            }
            // (moved aside alone, where something moves it: its one offset, a node's one binding of it, not one a
            // later one let go of)
            None =>
              if aside is Some(_) {
                col.offset(By(fn() { (aside_of(col), 0.0) })) |> ignore
              }
          }
          // (what the page reads as its entry, read as its old view's build read it: its source's page, its chat's
          // subscription held by the entry; read again as the page it is changes, and as it is put on again from
          // the stack's kept left (its time on top anew), where its chat was let go of, page_entry_parked)
          col.reacts(fn() { (app.nav.page_of(serial).map(fn(e) { e.0 }), app.nav.stint_of(serial), app.nav.is_kept_left(serial)) }, fn(
            now,
          ) {
            match now {
              (Some(page), _, false) => {
                // (its reader and what was handed over at once, so a quick press hands its read over; said
                // rendered only once a frame has drawn it there, still its stack's: one made and gone before
                // that (pushed and popped in one go) leaves as one never shown)
                page_entry_wake(serial)
                page_read(page)
                @ui.after_drawn_frame(fn() {
                  if col.alive() &&
                    on_stack() &&
                    !app.nav.is_kept_left(serial) &&
                    app.nav.page_of(serial) is Some((p, _)) &&
                    p == page {
                    page_entry_seen(serial, retained, page)
                  }
                })
              }
              _ => ()
            }
          })
          // (coming to need the viewer while open, felt, as its old view felt it)
          feel_needed_node(col, retained, r)
          body(col, retained, r, fn(n) {
            // (its composer made as nodes in the list's foot, its height going its own way, View::resizes)
            n
            .box(fn(at) {
              // (and the width its column is laid out at on the page's way, the narrower end: none at rest)
              foot_node(at, retained, r, fn() { drawn(serial) }, fn() {
                match narrower {
                  Some(by) => {
                    let c = by(n)
                    if c.by == 0.0 && c.across == 0.0 {
                      None
                    } else {
                      Some(c.laid)
                    }
                  }
                  None => None
                }
              })
            })
            |> ignore
            // (the composer as wide as the column is drawn, where it is drawn, whatever the column is laid out
            // at: its own way to another width with_side's)
            // (none of it at rest: bound once a column has first set off on such a way, at that cause)
            match narrower {
              Some(by) => {
                let bound = Ref(false)
                n.reacts(fn() { column_set_off_count() > 0 }, fn(going) {
                  if going && !bound.val && n.alive() {
                    bound.val = true
                    n
                    .margin(By(fn() { (0.0, 0.0, -by(n).by, 0.0) }))
                    .offset(By(fn() { (-by(n).across, 0.0) }))
                    |> ignore
                  }
                })
              }
              None => ()
            }
          }, fn() { drawn(serial) }, on_stack)
        }
        // (a new chat: nothing here, its own nodes over it, below)
        _ => ()
      }
    },
    at_once=true,
  )
  // (a new chat made as nodes (`new_node`): over the column, the page while it is the
  // new chat; become its chat (its first words sent: Nav::become), leaving over it as its scene does (new_leave_ms:
  // View::show's `leave`, how far it has left its View::going), nothing of it pressed, focused or read out as it
  // leaves, the chat's own under it; come back as it was where its chat was not made; what it reads let go with it)
  // (none on a page made as a chat: only a new chat becomes one, and comes back as itself where its chat is not made)
  let made_new = @signals.untracked(fn() { app.nav.page_of(serial) is Some((NewChat, _)) })
  if made_new {
    // (held while it is the new chat, and while it leaves over the chat it becomes in place (Nav::become); let go
    // at once as the page becomes anything else: another chat, a place, 设置)
    let keeps_new = fn() {
      match app.nav.page_of(serial) {
        Some((NewChat, _)) => true
        Some((Chat(r), _)) => fresh.became.get() == Some(r)
        _ => false
      }
    }
    v.show(at_once=true, keeps_new, fn(hold) {
      hold.over(Is(true)) |> ignore
      // (the new chat itself, leaving over the chat it became for new_leave_ms; come back to where it was asked
      // back before it is gone)
      hold.show(at_once=true, leave=new_leave_ms, fn() { app.nav.page_of(serial) is Some((NewChat, _)) }, fn(o) {
        o.over(Is(true)) |> ignore
        // (on the page's way to another width as what is beside it slides, laid out at the width it goes to all
        // the way, drawn as the frame says: `narrower`, as a chat's column)
        match narrower {
          Some(by) =>
            o
            .width(By(fn() { Some(by(o).laid) }))
            .offset(By(fn() { (-by(o).across, 0.0) }))
            |> ignore
          None => ()
        }
        // (what it reads put by as it leaves (the page its chat now, it fading where it was): its draft read no
        // more from that moment; back as it was where it comes back, the send called off)
        let (new_src, new_park) = src.owned_by_parkable(o)
        o.reacts(fn() { o.leaving() }, fn(leaving) { new_park(leaving) }, at_start=false)
        new_node(o, new_src)
      })
    })
  }
  match over {
    Some(f) =>
      // (while the page shows, as its old view is built: what it reads let go of while another covers it; kept, at rest,
      // as its entry is put by on the stack's kept left, Nav::try_park_left)
      v.show(fn() { drawn(serial) || app.nav.is_kept_left(serial) }, fn(o) {
        o.over(Is(true)) |> ignore
        f(o, retained, fn() { app.nav.page_of(serial).map(fn(e) { e.0 }) }, stint)
      })
    None => ()
  }
  retained
}

///|
/// How far a chat's composer made as nodes came down at once as words were sent from it (sfpages' composer_sent_holds:
/// the list takes that in the change their key comes), the chat's draft, the moment they were sent and by how much: what
/// stands beside the list by that foot (对话目录's rail, sfpages' chat_rail_node) drawn from where it stood, down to
/// where it is laid out on the ground's way (chat_foot_dropped_off), never stepped by half of it in a frame.
pub let chat_foot_dropped : @signals.Signal[(String, Double, Double)?] = @signals.signal(None)

///|
/// How far from where chat `chat`'s foot lays out what stands in the middle over it that is drawn at moment `t`, as
/// its foot came down at once at words sent (chat_foot_dropped): half as far as the foot came down, less as much as
/// the composer's ground has come down since on its way (held as it was for sent_out_hold_ms, then on their flight's
/// curve till move_most_ms, as sfpages' composer shapes it); none past that. And when that is over.
pub fn chat_foot_dropped_off(chat : String, t : Double) -> (Double, Double) {
  match chat_foot_dropped.get() {
    Some((c, at, by)) if c == chat => {
      let x = t - at
      let share = if x <= sent_out_hold_ms {
        0.0
      } else if x >= @ui.move_most_ms {
        1.0
      } else {
        @ui.Ease::Flight.at((x - sent_out_hold_ms) / (@ui.move_most_ms - sent_out_hold_ms))
      }
      (-by / 2.0 * (1.0 - share), at + @ui.move_most_ms)
    }
    _ => (0.0, 0.0)
  }
}

///|
/// Whether page `page` is a chat's made once (chat_page_made): a chat, or the new chat that becomes one in place.
pub fn chat_page_is(page : Page) -> Bool {
  page is (Chat(_) | NewChat)
}

///|
priv struct PageSource {
  source : Source
  mut page : Page?
  mut seen : Int
  mut chat_ready : String
  mut chat_view : ChatView?
  mut active : Bool
}

///|
let page_sources : Map[Int, Array[PageSource]] = Map([])

///|
priv struct LeftPageChat {
  source : Source
  view : ChatView?
}

///|
// An explicitly absent entry means a navigation entry left before it had a page source. A missing map entry is an
// older caller that placed a page directly in left_pages and still uses the surrounding source.
let left_page_sources : Map[Int, LeftPageChat?] = Map([])

///|
// The navigation entry serial that recorded each left_pages index, and indices cancelled because that serial woke back
// onto the stack before pages_left ran.
let left_page_serials : Map[Int, Int] = Map([])

///|
let left_pages_cancelled : Map[Int, Bool] = Map([])

///|
let page_source_seen : Ref[Int] = Ref(0)

///|
priv struct PendingChatReader {
  reader : TopicLease
  mut unkeep : (() -> Unit)?
}

///|
let pending_chat_readers : Map[Int, PendingChatReader] = Map([])

///|
/// Whether a row is still keeping an early reader for this navigation entry.
pub fn chat_open_is_pending(serial : Int) -> Bool {
  pending_chat_readers.contains(serial)
}

///|
fn stop_pending_chat(pending : PendingChatReader) -> Unit {
  match pending.unkeep {
    Some(unkeep) => { pending.unkeep = None; unkeep() }
    None => ()
  }
  pending.reader.release()
}

///|
fn release_pending_chat(serial : Int) -> Unit {
  match pending_chat_readers.get(serial) {
    Some(pending) => {
      pending_chat_readers.remove(serial)
      stop_pending_chat(pending)
    }
    None => ()
  }
}

///|
fn page_chat_ready(serial : Int, src : Source, key : String) -> Unit {
  match page_sources.get(serial) {
    Some(sources) => for current in sources {
      if physical_equal(current.source, src) { current.chat_ready = key }
    }
    None => ()
  }
  // The page's own reader was acquired before the early reader can be stopped.
  release_pending_chat(serial)
}

///|
/// Keep a row's reader through the open callback, which may synchronously let the row's view go.
pub fn prepare_chat_handoff(reader : TopicLease) -> TopicLease? {
  match @ui.view_tree() {
    Some(tree) => match reader.detach_to(tree.root()) {
      Some(next) => Some(next)
      None => { reader.release(); None }
    }
    None => { reader.release(); None }
  }
}

///|
/// After a row opens a chat, keep its early reader until the actual navigation entry has acquired its reader.
pub fn handoff_chat_open(r : ChatRef, reader : TopicLease) -> Unit {
  if !reader.alive() { return }
  let target = @signals.untracked(fn() { app.nav.top() })
  match target {
    Chat(chat) if chat.station == r.station && chat.session == r.session => {
      let (serial, _) = @signals.untracked(fn() { app.nav.top_stay() })
      let key = r.station + "\u{1}" + r.session
      if page_sources.get(serial) is Some(sources) && sources.iter().any(fn(current) {
        current.chat_ready == key && @signals.untracked(fn() { (current.source.topic_alive)() })
      }) {
        reader.release()
        return
      }
      let previous = pending_chat_readers.get(serial)
      let pending : PendingChatReader = { reader, unkeep: None }
      pending_chat_readers[serial] = pending
      match @ui.view_tree() {
        Some(tree) => {
          let root = tree.root()
          if root.alive() {
            pending.unkeep = Some(root.owns_while(fn() {
              match pending_chat_readers.get(serial) {
                Some(current) if physical_equal(current, pending) => pending_chat_readers.remove(serial)
                _ => ()
              }
              stop_pending_chat(pending)
            }))
          } else {
            release_pending_chat(serial)
          }
        }
        None => release_pending_chat(serial)
      }
      match previous { Some(old) => stop_pending_chat(old); None => () }
    }
    _ => reader.release()
  }
}

///|
/// The readers a page handed over as it opened another in its place (open_handing), by the entry opened's serial:
/// each the entry's as its view is made (page_entry_source), let go once its first build has read what it reads
/// (page_entry_read).
let handed_readers : Map[Int, Array[TopicLease]] = Map([])

///|
/// `open` run (a page opening the next in its place: a folder the folder it goes into), with this page's reader of
/// topic `name` handed over to the entry it opened: kept past this page as it leaves (as a row's early reader is,
/// prepare_chat_handoff), taken by that entry as its view is made and let go as its first build ends. So a next page
/// that reads it as it is first built reads the subscription this one read, never one made again after this one let
/// it go (a press opens the next at once, outside any build: the old entry leaves before the new one is built); one
/// that does not read it then lets it go then, as it would have been had the open come in a build. Only a topic this
/// page holds is handed over: one nothing reads is not asked for here (a lease of it would be a subscription of its
/// own).
pub fn open_handing(src : Source, name : String, params : Map[String, Json], open : () -> Unit) -> Unit {
  if !topic_held(name, params) {
    open()
    return
  }
  hand_over([src.lease_topic(name, params)], open)
}

///|
/// `open` run (a place of a sidebar's opening its page in place of the one shown: a favorite folder, a station),
/// with every topic held now handed over to the entry it opened as open_handing hands one: the page it opens reads, as
/// it is first built, what the page it leaves read, never one asked for again after that one let it go (opened in a
/// build, the page left was let go only once the one opened was built in the same frame); what it does not read then
/// is let go as its first build ends. Not what a place of the page left browses (its topic said by that `place`,
/// browse_where): that place goes with it, and kept past it, it would be asked again for what the opening changes
/// (the tabs it keeps), the page opened browsing its own.
pub fn open_handing_held(open : () -> Unit) -> Unit {
  let held = topics_held().filter(fn(t) { !t.2.contains("place") })
  hand_over(held.map(fn(t) { t.0.lease_topic(t.1, t.2) }), open)
}

///|
/// `open` run, `leases` handed to the entry it put on top (open_handing): kept past the page that leaves, taken by
/// that entry as its view is made; let go at once where nothing was put on top.
fn hand_over(leases : Array[TopicLease], open : () -> Unit) -> Unit {
  let readers : Array[TopicLease] = []
  for lease in leases {
    match prepare_chat_handoff(lease) {
      Some(reader) => readers.push(reader)
      None => ()
    }
  }
  let (before, _) = @signals.untracked(fn() { app.nav.top_stay() })
  open()
  let (serial, _) = @signals.untracked(fn() { app.nav.top_stay() })
  // (nothing opened in its place: no one to hand them to)
  if serial == before {
    for reader in readers {
      reader.release()
    }
    return
  }
  match handed_readers.get(serial) {
    Some(had) => had.append(readers)
    None => handed_readers[serial] = readers
  }
}

///|
/// The readers a press handed over to a page it shows in a pane in place of the one there, no entry of the stack put on
/// top (a place's side list's pick: hand_over_shown), by what that page is shown for (`at`): taken as that page is
/// first built (shown_read), let go at that frame's end, as an entry's are (page_entry_read).
let handed_shown : Map[String, Array[TopicLease]] = Map([])

///|
/// `open` run (a press showing a page in a pane in place of the one there: a place's side list's row), `leases` handed
/// to the page it shows, `at` what that page is shown for (shown_read's): kept past the page that leaves, let go at the
/// end of the frame the page shown is first built in. What was handed for the same page and not taken yet is let go
/// first (shown again before it was built).
pub fn hand_over_shown(at : String, leases : Array[TopicLease], open : () -> Unit) -> Unit {
  let readers : Array[TopicLease] = []
  for lease in leases {
    match prepare_chat_handoff(lease) {
      Some(reader) => readers.push(reader)
      None => ()
    }
  }
  match handed_shown.get(at) {
    Some(had) => for reader in had { reader.release() }
    None => ()
  }
  handed_shown[at] = readers
  open()
}

///|
/// The page shown for `at` (hand_over_shown's) first built, or a reader of a page switched in place having read anew
/// (switch_answered's): what was handed to it let go once this build has read what it reads, at its frame's end; what
/// it read is its own reader's by then.
pub fn shown_read(at : String) -> Unit {
  match handed_shown.get(at) {
    Some(readers) => {
      handed_shown.remove(at)
      @ui.after_frame(fn() { for reader in readers { reader.release() } })
    }
    None => ()
  }
}

///|
/// What a profile's page is shown for (hand_over_shown, shown_read): its station and profile.
pub fn profile_shown_at(station : String, id : String) -> String {
  "profile\u{1}" + station + "\u{1}" + id
}

///|
/// The source for one actual navigation entry. Keep its identity until the entry leaves so its final events can
/// use the same projection that the page read, rather than the surrounding window's source. What the page before it
/// handed over as it opened it (open_handing) is the entry's from here, till its first build (page_entry_read).
pub fn page_entry_source(src : Source, entry : @view.View, serial : Int) -> Source {
  match handed_readers.get(serial) {
    Some(readers) => for reader in readers { reader.bind_to(entry) }
    None => ()
  }
  let (source, park) = src.owned_by_parkable(entry)
  entry_park_said(serial, entry, park)
  let current : PageSource = { source, page: None, seen: 0, chat_ready: "", chat_view: None, active: true }
  let sources = match page_sources.get(serial) {
    Some(sources) => sources
    None => { let sources : Array[PageSource] = []; page_sources[serial] = sources; sources }
  }
  sources.push(current)
  entry.owns(fn() {
    current.active = false
    match page_sources.get(serial) {
      Some(sources) => {
        // An entry can leave through another navigation path after this view's cleanup. Keep its most recently
        // read ended source for that callback, and at most one such source while the entry stays on the stack.
        let mut latest_ended : PageSource? = None
        for candidate in sources {
          if !candidate.active && (latest_ended is None || candidate.seen > latest_ended.unwrap().seen) {
            latest_ended = Some(candidate)
          }
        }
        let remaining = sources.filter(fn(other) {
          other.active || (latest_ended is Some(last) && physical_equal(other, last))
        })
        page_sources[serial] = remaining
      }
      _ => ()
    }
  }) |> ignore
  source
}

///|
fn page_source_read_page(source : PageSource, page : Page) -> Bool {
  match (source.page, page) {
    (Some(Chat(a)), Chat(b)) => a.station == b.station && a.session == b.session
    (Some(a), b) => a == b
    _ => false
  }
}

///|
fn entry_last_source(serial : Int, page : Page) -> PageSource? {
  let mut chosen : PageSource? = None
  match page_sources.get(serial) {
    Some(sources) => for candidate in sources {
      match chosen {
        None => chosen = Some(candidate)
        Some(previous) => {
          let read = page_source_read_page(candidate, page)
          let previous_read = page_source_read_page(previous, page)
          if (read && !previous_read) || (read == previous_read &&
            ((candidate.active && !previous.active) ||
             (candidate.active == previous.active && candidate.seen > previous.seen))) {
            chosen = Some(candidate)
          }
        }
      }
    }
    None => ()
  }
  match chosen {
    Some(current) if page_source_read_page(current, page) => Some(current)
    _ => None
  }
}

///|
pub fn page_entry_read(serial : Int, source : Source, page : Page) -> Unit {
  page_entry_wake(serial)
  page_entry_seen(serial, source, page)
}

///|
/// What entry `serial` takes up as its page is made (page_entry_read's first half): taken back from the stack's kept
/// left, and what the page before handed over let go of once this frame's build has read what it reads.
fn page_entry_wake(serial : Int) -> Unit {
  // (woken back onto the stack before pages_left ran: cancel any pending leave recorded for this serial)
  for index, s in left_page_serials {
    if s == serial {
      left_pages_cancelled[index] = true
    }
  }
  // (taken back from the stack's kept left: its sources read again)
  match entries_kept.get(serial) {
    Some(done) => {
      entries_kept.remove(serial)
      // (put by already: taken back; else taken back before it was, nothing to take back)
      if done {
        entry_parked(serial, false)
      }
    }
    None => ()
  }
  // (what the page before handed over, open_handing: let go once this build has read what it reads, at its frame's
  // end; what it read is its own reader's by then)
  match handed_readers.get(serial) {
    Some(readers) => {
      handed_readers.remove(serial)
      @ui.after_frame(fn() { for reader in readers { reader.release() } })
    }
    None => ()
  }
}

///|
/// Entry `serial`'s page `page`, read through `source`, said to be the one its sources were last read for
/// (page_entry_read's second half): what its leaving tells of as rendered.
fn page_entry_seen(serial : Int, source : Source, page : Page) -> Unit {
  match page_sources.get(serial) {
    Some(sources) => for current in sources {
      if !physical_equal(current.source, source) { continue }
      if !page_source_read_page(current, page) { current.chat_view = None }
      page_source_seen.val += 1
      current.seen = page_source_seen.val
      current.page = Some(page)
    }
    None => ()
  }
}

///|
pub fn page_source_for_chat(fallback : Source, r : ChatRef) -> Source {
  let mut latest = -1
  let mut result = fallback
  for serial, sources in page_sources {
    // (an entry put by on the stack's kept left reads nothing while it rests: none of its sources the chat's, so that
    // what reads a chat through its page's source (linger_tick, each frame) holds none of it meanwhile)
    if entries_kept.contains(serial) {
      continue
    }
    for current in sources {
      match current.page {
        Some(Chat(chat)) if current.active && chat.station == r.station && chat.session == r.session && current.seen > latest &&
          @signals.untracked(fn() { (current.source.topic_alive)() }) => {
          latest = current.seen
          result = current.source
        }
        _ => ()
      }
    }
  }
  result
}

///|
// Save the actual projection while its owner is live. Disposing a view can invalidate its derived value before the
// navigation entry's leave callback runs; an ending source must not replace the last live projection with None.
fn page_chat_view_read(source : Source, chat : ChatRef, value : ChatView?) -> Unit {
  if !@signals.untracked(fn() { (source.topic_alive)() }) { return }
  for _, sources in page_sources {
    for current in sources {
      // (none read where it had one: kept, a page taken back from the stack's kept left reading it again before the
      // core's first answer to it, page_chat_view_kept)
      if physical_equal(current.source, source) && page_source_read_page(current, Chat(chat)) &&
        (value is Some(_) || current.chat_view is None) {
        current.chat_view = value
      }
    }
  }
}

///|
/// The view of chat `chat` that page source `source` last read, where it is a page's (page_entry_source) and still
/// live: what a page taken back from the stack's kept left shows while its chat, asked again, waits for the core's
/// first answer (chat_view_now). None for a page that never read it (one opened cold).
fn page_chat_view_kept(source : Source, chat : ChatRef) -> ChatView? {
  for _, sources in page_sources {
    for current in sources {
      if current.active && physical_equal(current.source, source) && page_source_read_page(current, Chat(chat)) {
        return current.chat_view
      }
    }
  }
  None
}

///|
pub fn left_page_source(fallback : Source, index : Int) -> (Source?, ChatView?) {
  let saved = left_page_sources.get(index)
  left_page_sources.remove(index)
  match saved {
    Some(Some(chat)) => (Some(chat.source), chat.view)
    Some(None) => (None, None)
    None => (Some(fallback), None)
  }
}

///|
/// Whether `left_pages[index]` was cancelled because its navigation entry woke back onto the stack before
/// `pages_left` ran.
pub fn left_page_cancelled(index : Int) -> Bool {
  left_pages_cancelled.get(index).unwrap_or(false)
}

///|
/// Clears `left_pages` and its per-index metadata once `pages_left` finishes.
pub fn left_pages_clear() -> Unit {
  left_pages.clear()
  left_page_sources.clear()
  left_page_serials.clear()
  left_pages_cancelled.clear()
}

///|
/// What the frame a page is shown in gives it: the library's (@sf.page's `frame`).
pub using @sf {
  type PageFrame,
}

///|
/// A station's screen to view: its station (`<workspace>/<station>`), its id there, and its title until the core says
/// one (the link's own, or the row's it was opened from; "" none). `until_gone`: opened for a while only (a login's
/// page in the station's browser, its tab closed as the login ends): the page goes back by itself once the screen is
/// gone.
#derive(Eq)
pub(all) struct ScreenAt {
  station : String
  screen : String
  title : String
  until_gone : Bool
}

///|
/// A terminal's page: its station's address, its id (`new`: one opened for the page), whether it is only looked at,
/// the folder a new one opens in.
#derive(Eq)
pub(all) struct TerminalAt {
  station : String
  terminal : String
  watch : Bool
  cwd : String
}

///|
/// A new terminal's id (one opened for its page): `new`, `new#<seq>` the seq-th beside others, and `:<chat>` after
/// either where it opens in that chat's workspace. The chat rides in the id, not a field of `TerminalAt`, whose shape
/// every unit that reads a page is compiled by.
pub fn new_terminal_id(chat? : String = "", seq? : Int = 0) -> String {
  let base = if seq > 0 { "new#" + seq.to_string() } else { "new" }
  if chat != "" {
    base + ":" + chat
  } else {
    base
  }
}

///|
/// Whether a terminal's id is a new one's (new_terminal_id), none of the station's yet.
pub fn terminal_is_new(id : String) -> Bool {
  id == "new" || id.has_prefix("new:") || id.has_prefix("new#")
}

///|
/// The chat a new terminal's id says it opens in ("" none, or a terminal of the station's).
pub fn terminal_open_chat(id : String) -> String {
  guard terminal_is_new(id) else { return "" }
  match id.find(":") {
    Some(i) => id.exact_view(start=i + 1).to_owned()
    None => ""
  }
}

///|
/// A terminal's id without the chat a new one's says (`new`, `new#<seq>`, or the station's id as it is).
pub fn terminal_base_id(id : String) -> String {
  guard terminal_is_new(id) else { return id }
  match id.find(":") {
    Some(i) => id.exact_view(end=i).to_owned()
    None => id
  }
}

///|
/// A terminal's id with `chat` put in where it is a new one's that says none yet.
pub fn terminal_with_chat(id : String, chat : String) -> String {
  if chat == "" || !terminal_is_new(id) || terminal_open_chat(id) != "" {
    id
  } else {
    id + ":" + chat
  }
}

///|
/// What page `p` is, by its kind alone: a name out of a fixed set written here, never a chat's, station's, session's,
/// file's, job's or person's id, name, title or path, nor anything typed. What the window thread's hang reports sent
/// to PostHog say of the page shown (shown_kind, mbui's journal_shows) and the device's performance record says too.
/// Each is a constructor's literal; a place, data, only as one of `bar_places` (else `other`); a page of the settings
/// as its route's constructor alone (setting_kind). sfapp's shown_wbtest holds every name a screen comes to.
pub fn page_kind(p : Page) -> String {
  match p {
    Home => "Home"
    Chat(_) => "Chat"
    Archived => "Archived"
    Settings => "Settings"
    Files => "Files"
    Drive(_) => "Drive"
    DriveRead(_) => "DriveRead"
    DrivePlay(_) => "DrivePlay"
    Service(_, _) => "Service"
    PreviewFile(_, _, _, _) => "PreviewFile"
    History(_, _, _) => "History"
    NewChat => "NewChat"
    Place(place) => "Place " + place_kind(place)
    Setting(r) => "Setting " + setting_kind(r)
    Screen(_) => "Screen"
    Terminal(_) => "Terminal"
    SideTab(_) => "SideTab"
  }
}

///|
/// A place of the bar's by its name, as a literal of the places a bar can hold (bars.mbt's bar_places); any other
/// `other`: what comes in a string is never said as it came.
fn place_kind(place : String) -> String {
  match place {
    "chats" => "chats"
    "files" => "files"
    "remote" => "remote"
    "stations" => "stations"
    "profiles" => "profiles"
    "connects" => "connects"
    "usage" => "usage"
    "archive" => "archive"
    "vault" => "vault"
    _ => "other"
  }
}

///|
/// A page of the settings by its route's constructor alone: no station's address, id or key it carries.
fn setting_kind(r : @settings.Route) -> String {
  match r {
    Home => "Home"
    Me => "Me"
    Appearance => "Appearance"
    Experimental => "Experimental"
    Fonts => "Fonts"
    Workspace => "Workspace"
    Security => "Security"
    SecurityOpen => "SecurityOpen"
    Vault => "Vault"
    Stations => "Stations"
    Station(_) => "Station"
    Profiles(_) => "Profiles"
    Profile(_, _) => "Profile"
    Connects(_) => "Connects"
    Connect(_, _) => "Connect"
    Memories => "Memories"
    Memory(_) => "Memory"
    MemoryDoc(_, _, _) => "MemoryDoc"
    Usage => "Usage"
    Archive => "Archive"
    AdbShare(_) => "AdbShare"
    NewProfile(_) => "NewProfile"
    ProfileAccount(_) => "ProfileAccount"
    VaultItems => "VaultItems"
    VaultItem(_, _) => "VaultItem"
    AutoDecisions => "AutoDecisions"
    AutoCompletion => "AutoCompletion"
    AutoPolicy(_) => "AutoPolicy"
    BarSettings => "BarSettings"
    KeptFiles => "KeptFiles"
    KeptChat(_, _) => "KeptChat"
    Changelog => "Changelog"
    About => "About"
    Shortcuts => "Shortcuts"
    LocalStation => "LocalStation"
    Notifications => "Notifications"
    Permissions => "Permissions"
    Archiving => "Archiving"
    StationArchiving(_) => "StationArchiving"
    StationMove(_) => "StationMove"
    UsagePrices(_) => "UsagePrices"
  }
}

///|
/// What the app shows as a whole (sfapp's shown_now says which): before it can show a workspace (the splash, the
/// accounts or workspaces still read or failing), the way in signed out, the landing with no workspace, a share sheet
/// over another app, or a page (the stack's top, the page the pane lands on on 中屏 and 大屏; a window of its own's).
#derive(Eq)
pub(all) enum Shown {
  Starting
  SignIn
  Landing
  Share
  Shows(Page)
}

///|
/// What the app shows by its kind alone (page_kind's for a page): what it tells the window thread's journal as that
/// changes (mbui's journal_shows), which its hang reports and the device's performance record say.
pub fn shown_kind(s : Shown) -> String {
  match s {
    Starting => "Starting"
    SignIn => "Sign in"
    Landing => "Landing"
    Share => "Share"
    Shows(p) => page_kind(p)
  }
}

///|
pub(all) struct App {
  mut nav : @ui.Nav[Page]
  /// the workspace switched to here, before the core's prefs say it
  picked : @signals.Signal[String]
  /// the list's filter chosen here, by workspace, before the prefs say it
  filters : @sf.LiveMap[String, String]
  /// the filter's menu open
  mut menu : Bool
  /// a place switched to on the bar: from which side (1 from the right, -1 the left, 0 from no side)
  mut switch_way : Int
  /// a row held: its id, and whether it has been held long (its time on Ctx::held)
  mut held : Int
  mut held_long : Bool
  /// what was said last of a write (a toast): its words, which saying it is (one said again is a new one), what it
  /// offers to do (its button's words, "" none: an archive's 撤销) and what that does, said together (toast_later);
  /// each window's of the run its own (window.mbt: said in the window it was said in)
  mut toast : @signals.Signal[ToastSaid]
}

///|
/// A write's toast as it was said (toast_later): its words ("" none), which saying it is, its button's words ("" none)
/// and what that does, one value: what reads it reads them all as one saying.
pub(all) struct ToastSaid {
  words : String
  n : Int
  action : String
  run : () -> Unit
}

///|
/// No toast (none said, or the one said gone).
pub let toast_none : ToastSaid = { words: "", n: 0, action: "", run: fn() {  } }

///|
pub let app : App = {
  nav: new_nav(),
  picked: @signals.signal("", same=fn(a, b) { a == b }),
  filters: @sf.LiveMap::new(),
  menu: false,
  switch_way: 0,
  held: 0,
  held_long: false,
  toast: toast_said_new(),
}

///|
fn toast_said_new() -> @signals.Signal[ToastSaid] {
  @signals.signal_ref(toast_none)
}

///|
/// What a page left leaves behind: a chat's topic and what it told the core.
pub let left_pages : Array[Page] = []

///|
/// The page last left (left_pages), by its entry's serial (unique across every Nav, never one again): what tells where
/// it was left (the frame's pages-left) built again as another is left.
// kept across runs: a serial is never given twice (nav.mbt), so the last left of a run before is no page of this one
pub let left_said : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })

///|
fn page_entry_left(serial : Int, p : Page) -> Unit {
  page_entry_tells_left(serial, p, false)
}

///|
/// Entry `serial` of page `p` put by on the stack's kept left (Nav::try_park_left), its nodes at rest: told as left
/// (where it was left, the core told so, what was handed to it let go: page_entry_left's) but for its sources, kept for it
/// as it is put on again, and its chat let go of, none held while it is put by (page_chat_reader's).
fn page_entry_parked(serial : Int, p : Page) -> Unit {
  page_entry_tells_left(serial, p, true)
}

///|
/// Entry `serial` let go for good (Nav's on_entry_gone): what was kept for it as it was put by let go (none, where it
/// left without being put by: page_entry_left let go of all of it then).
fn page_entry_gone(serial : Int, _p : Page) -> Unit {
  entries_kept.remove(serial)
  page_sources.remove(serial)
  // (its chat's reader let go by the entry it is bound to as that goes in the frame after (page_chat_reader's
  // bind_to), never here: Nav tells it gone before then, the original read still asked till that frame)
  active_chat_readers.remove(serial)
  release_pending_chat(serial)
  match handed_readers.get(serial) {
    Some(readers) => {
      handed_readers.remove(serial)
      for reader in readers {
        reader.release()
      }
    }
    None => ()
  }
}

///|
/// Entry `serial` of page `p` told as left (page_entry_left), or as put by (`parked`: page_entry_parked).
fn page_entry_tells_left(serial : Int, p : Page, parked : Bool) -> Unit {
  let entry = entry_last_source(serial, p)
  let chat : LeftPageChat? = match (p, entry) {
    (Chat(r), Some(current)) => {
      let view = match chat_kept_from(current.source, r) {
        Some(view) => Some(view)
        None => current.chat_view
      }
      Some({ source: current.source, view })
    }
    _ => None
  }
  // (a chat's entry never drawn (no source it was last read through): nothing told of it leaving (no chat_left), what
  // its sources made of the chat (its read, its head's) let go of all the same, telling the core nothing)
  match (p, chat) {
    (Chat(r), None) =>
      match page_sources.get(serial) {
        Some(sources) => for current in sources { chat_inputs_left_from(current.source, r) }
        None => ()
      }
    _ => ()
  }
  // (its chat's reader let go at once only where nothing else lets go of it: put by (kept_left), or never drawn; one
  // drawn and let go for good lets go of it as its entry goes in the frame after (page_chat_reader's bind_to))
  if parked || chat is None {
    match active_chat_readers.get(serial) {
      Some(let_go) => {
        active_chat_readers.remove(serial)
        let_go()
      }
      None => ()
    }
  }
  if parked {
    // (its sources kept for it as it is put on again: what they had read of its chat read anew then)
    match page_sources.get(serial) {
      Some(sources) => for current in sources { current.chat_ready = "" }
      None => ()
    }
    // (its sources put by once what it left is told (the frame's pages left, chat_left, reading through them), at the
    // end of the frame that tells it, where it is still kept then)
    if !entries_kept.contains(serial) {
      entries_kept[serial] = false
    }
    @ui.after_frame(entries_kept_park_due)
  } else {
    // (a chat's entry never drawn: what its source reads put by with it, as one put by is)
    if p is Chat(_) && chat is None {
      entry_parked(serial, true)
    }
    page_sources.remove(serial)
  }
  release_pending_chat(serial)
  // (what was handed to it and never taken, its view made in the open that handed it, before the handing (a page
  // made once as nodes, put up in a frame: an account's page's station, account and memberships its press asked):
  // held while it showed, let go as it leaves, not by the tree's root for good)
  match handed_readers.get(serial) {
    Some(readers) => {
      handed_readers.remove(serial)
      for reader in readers {
        reader.release()
      }
    }
    None => ()
  }
  let index = left_pages.length()
  left_page_serials[index] = serial
  left_pages_cancelled.remove(index)
  match p {
    Chat(_) => left_page_sources[index] = chat
    _ => ()
  }
  left_pages.push(p)
  left_said.set(serial)
  match p {
    Setting(r) => @settings.left(r)
    Archived => @settings.left(@settings.Route::Archive)
    Settings => @settings.left(@settings.Route::Home)
    // a place of the bar's whose page is the settings' (bar.mbt place_page)
    Place(name) => @settings.place_left(name)
    _ => ()
  }
}

///|
/// The stack's root made `page`'s, the one there put on its shelf and `page`'s entry taken back from it where it is
/// there (Nav::replace_kept: where what holds the stack keeps pages so, the narrow shell; else as Nav::replace): what a
/// place of the bar switched to is on 小屏, from the bar, back or the history. A place taken back is as it was left, its
/// scroll and 连接's 我的 too (the owner, 2026-11-12: 「三样都记得」); one put on the shelf has not left the stack yet, so
/// nothing is let go of it here (@settings.left is page_entry_left's, as its entry leaves for good).
pub fn nav_root_kept(page : Page) -> Unit {
  app.nav.replace_kept(page)
}

///|
pub fn new_nav() -> @ui.Nav[Page] {
  // what its own back comes to, back's in the history (app_history.mbt went_back); settings' gear is at the right of
  // every top bar, so it comes in from the right like any page
  @ui.Nav::new(Home, went_back~, on_entry_leave=page_entry_left, on_entry_park=page_entry_parked, on_entry_gone=page_entry_gone)
}

///|
/// A page of the settings opened over Home from the start (screenshots of them, a scripted run): by its name
/// (@settings.route_of), through the pages one comes to it by (setting_way: a memory page under its station's memory,
/// under 记忆), so what is over it and back says are as a person finds them.
pub fn open_setting(name : String) -> Unit {
  match @settings.route_of(name) {
    Some(@settings.Route::Home) => open_page(Settings)
    Some(r) => {
      open_page(Settings)
      for w in setting_way(r) {
        open_page(Setting(w))
      }
      open_page(Setting(r))
    }
    None => ()
  }
}

///|
/// The settings' pages one comes through to `r` from their list, where it is not on it.
fn setting_way(r : @settings.Route) -> Array[@settings.Route] {
  match r {
    Memory(_) => [Memories]
    StationMove(a) => [Stations, Station(a)]
    MemoryDoc(a, _, _) => [Memories, Memory(a)]
    AutoCompletion => [AutoDecisions]
    AutoPolicy(_) => [AutoDecisions, AutoCompletion]
    _ => []
  }
}

///|
/// Back to Home (the stack's root), the filter's menu closed: a workspace left, from either frame.
pub fn nav_home() -> Unit {
  app.menu = false
  while app.nav.depth() > 1 {
    if !app.nav.pop() {
      break
    }
  }
}

///|
/// The stack made Home and `pages` over it, in place, as one change: Home kept where it is the root, else the non-Home
/// root is parked on the shelf via `nav_root_kept` (preserving the shelf) inside a single signal batch before `pages`
/// are placed over Home.
pub fn nav_over_home(pages : Array[Page]) -> Unit {
  if app.nav.pages()[0] == Home {
    app.nav.replace_above(1, pages)
  } else {
    @signals.start_batch()
    if app.nav.depth() > 1 {
      app.nav.replace_above(1, [])
    }
    nav_root_kept(Home)
    if pages.length() > 0 {
      app.nav.replace_above(1, pages)
    }
    @signals.end_batch()
  }
}

///|
/// A chat opened over Home from the start (a link, a scripted run).
pub fn open_chat(r : ChatRef) -> Unit {
  open_page(Chat(r))
}

///|
/// Page `p` opened, where the layout has it (Shell's `open`: the pane table): what pages, links
/// and the app's own doings call, never the stack themselves.
pub fn open_page(p : Page) -> Unit {
  if window_front(p) {
    return
  }
  full_page_noted(p)
  history_act(fn() { (shell.val.open)(p) })
}

///|
/// What page `p` reads of the core as it is first built, each asked of `ask`, in the order its build asks them: a
/// chat its view, its draft, its workspace's stations (the names it shows its agents by) and its jobs' summary. A
/// page not said here asks as its build runs. Only what it reads on every screen, at once: what its build reads
/// later or on one screen alone is its build's (sfapp's declared_read_wbtest holds each said here read at rest, and
/// the frame that builds it asking nothing more).
///
/// A bridge while pages are built by the old view, as opens_ahead_node's is (apps/mbui/AGENTS.md): only for a page the
/// old view builds whose first screen reads the core (the chat's, so far; another added only with the coordinator of
/// the migration, 2026-11-12), not a table every page is put in. A page made as nodes says what it reads where it is
/// made, and goes from here then.
pub fn page_opens(p : Page, ask : (String, Map[String, Json]) -> Unit) -> Unit {
  match p {
    Chat(r) => {
      ask("chat", chat_params(r))
      ask("composer", { "key": Json::string(r.station + ":" + r.session) })
      ask("stations", stations_asked(workspace_of(r.station)))
      ask("chatJobs", chat_jobs_summary_params(r))
    }
    _ => ()
  }
}

///|
/// Page `p` opened from the page in view (a chat's link in a message): over it, back coming to it again, where the
/// layout has it (Shell's `open_over`).
pub fn open_page_over(p : Page) -> Unit {
  if window_front(p) {
    return
  }
  history_act(fn() { (shell.val.open_over)(p) })
}


///|
/// A chat the page is of: its station, the session it is opened by (a row's `session`), its title and its station's
/// name as the row said them (the page shows the view's own once it is read).
#derive(Eq)
pub(all) struct ChatRef {
  station : String
  session : String
  title : String
  station_name : String
}

///|
/// Where a page of a drive is: a station, one of its roots (None: the drive itself, its roots), a path under it.
#derive(Eq)
pub(all) struct DriveAt {
  station : String
  root : String?
  path : String
}

///|
/// Stations whose restart-interrupted banner was optimistically acted on (resumed or dismissed) on this device.
pub let restart_interrupted_gone : @sf.LiveMap[String, Bool] = @sf.LiveMap::new()

///|
/// As at the start: Home alone on the stack, nothing chosen here yet, nothing said, no page left (the app's reset; a
/// toast's count goes on, as before it was here).
pub fn reset() -> Unit {
  restart_interrupted_gone.clear()
  app.nav = new_nav()
  chat_remote_caps_reset()
  // (the core given no mermaid: a run's core is a new one)
  mermaid_begin()
  // (no page on its way: a frame with no wide page in it says none, the last run's left as it was)
  page_way_said("", 0.0, ends=0.0)
  columns_laid.clear()
  // (no column set off yet: a run's first page is cut at rest as the app's first is, the last run's way forgotten)
  columns_set_off_said.set(0)
  // where it has been (app_history.mbt)
  history_reset()
  last_reset()
  ahead_reset()
  remote_tabs_reset()
  switch_reset()
  app.picked.set("")
  @ui.set_motion_chosen(None)
  @ui.set_haptics(true)
  awake_reset()
  board_reset()
  app.filters.clear()
  app.menu = false
  app.switch_way = 0
  app.held = 0
  app.held_long = false
  // (none said; which saying was last kept: the next a new one, as ever)
  app.toast.set({ ..toast_none, n: @signals.untracked(fn() { app.toast.get().n }) })
  left_pages_clear()
  active_chat_readers.clear()
  entry_parks.clear()
  entries_kept.clear()
  let pending = pending_chat_readers.values().collect()
  pending_chat_readers.clear()
  for reader in pending { stop_pending_chat(reader) }
  let shown = handed_shown.values().collect()
  handed_shown.clear()
  for readers in shown {
    for reader in readers {
      reader.release()
    }
  }
  let handed = handed_readers.values().collect()
  handed_readers.clear()
  for readers in handed {
    for reader in readers {
      reader.release()
    }
  }
  page_sources.clear()
  left_page_sources.clear()
  page_source_seen.val = 0
  // the topics read for what has not ended yet (held.mbt)
  held_reset()
  nav_tapped.set([])
  // the drive's files going up and being fetched (drive_upload.mbt, drive_keep.mbt)
  ups_reset()
  dv_fetches.clear()
  dv_orders_reset()
  keepings.clear()
  // what was worked out of the core's topics (derived.mbt)
  kept_reset()
  // how many rows each chats' list was told to grow to, the window's height they are worked out of (rows.mbt)
  chat_windows_reset()
  open_titled.val = ""
  shown_days.clear()
  held_from.clear()
  // the core's downloads being taken and kept (downloads.mbt)
  downloads_reset()
  // the drafts as the core keeps them (compose.mbt)
  writings_reset()
  // services' pages kept, their sizes, what was marked on them (service_page.mbt)
  service_pages_reset()
  // a file open over the pages, what it flew from and kept (viewer.mbt, viewer_marks.mbt)
  file_viewer_reset()
  machine_here.val = None
  // a station's screens' cards live in a chat (screen_links.mbt)
  peeks_reset()
  // visualizations drawn, one open over the whole window, words they asked to send (viz_page.mbt)
  viz_pages_reset()
  // what was sent from here, not in the core's view yet (sent.mbt)
  sent_reset()
  // what the core said of the composers' fields, their marks and `@` words (refs.mbt)
  refs_reset()
  // a send asking about what it refers to (outside.mbt)
  outside_reset()
  // what was asked of the core from a button, under way or failed (act.mbt)
  acting_reset()
  // a colour theme shown a moment over the one set (app_frame.mbt)
  accent_preview_reset()
  // how an update stands (updates.mbt)
  update_reset()
  // a chat's relay picker (relay.mbt)
  relay_reset()
  // the messages chats are to go to (jump.mbt)
  go_tos.clear()
  go_to_passages.clear()
  go_to_words.clear()
  go_to_around.clear()
  // and where each chat's reader was as a go-to took its list away (jump.mbt)
  places_back.clear()
  places_back_pieces.clear()
  go_back_offsets.clear()
  go_back_pieces.clear()
  places_back_said.set(0)
  // when the flash of a message gone to on a page made as nodes is over (chat_list.mbt)
  flash_rest_nodes.val = -1.0
  // a new chat while it is made (fresh.mbt)
  fresh_reset()
  // how times are said (message_words.mbt)
  absolute_times.set(false)
  // whether Farview tabs are native, or the board enabled
  farview_native.set(false)
  board_feature.set(false)
  // a chat's messages out of avatars (emit.mbt)
  emits.clear()
  chat_foot_dropped.set(None)
  sent_from_at.clear()
  sent_words_room_at.clear()
  sent_quote_ids_at.clear()
  // the chats' lists as kept while they show and where they were left (chat_list.mbt)
  readings.clear()
  kept_places.clear()
  flash_held.val = false
  at_end_env.val = -1
  // what the settings' core keeps (settings_core.mbt, notices.mbt, faces.mbt, bars.mbt)
  reporting_host.set(None)
  reporting_said.set(None)
  notices_reset()
  faces_reset()
  bars_picked.set(None)
  // what the app does whichever frame draws it (app_frame.mbt, open_links.mbt, menu_bar.mbt, shell.mbt)
  app_frame_reset()
  links_reset()
  menu_bar_given.val = ""
  shell.val = bare_shell()
  beside_room_now.set(false)
  tab_full_reset()
  // the page shown alone in a window of its own (window.mbt) and remote workbench tabs (remote_tabs.mbt)
  lone_page.val = None
  first_lone.val = None
  lone_shown.val = @signals.signal(None)
  remote_tabs_reset()
  windows_open.clear()
  windows_here_show.clear()
  tab_windows.clear()
}

///|
/// What back over a page says: the title of the page it goes back to.
pub fn back_label(p : Page) -> String {
  match p {
    Home => @sf.t("android-misc.bar.place.chats")
    Settings | Setting(@settings.Route::Home) => @sf.t("android-settings.title")
    Setting(@settings.Route::About) => @sf.t("web-pages.settings.nav.about")
    Setting(@settings.Route::Permissions) => @sf.t("web-pages.settings.nav.permissions")
    Setting(@settings.Route::Memories) | Setting(@settings.Route::Memory(_)) => @sf.t("web-pages.settings.memory.title")
    Setting(@settings.Route::AutoDecisions) => @sf.t("web-pages.automaticDecisions.title")
    Setting(@settings.Route::AutoCompletion) => @sf.t("web-pages.automaticDecisions.completion")
    Setting(@settings.Route::Archiving) => @sf.t("web-pages.archiving.title")
    Setting(@settings.Route::Shortcuts) => @sf.t("web-main.shortcuts.title")
    Setting(@settings.Route::Usage) => @sf.t("web-pages.settings.nav.usage")
    Setting(@settings.Route::Security) => @sf.t("web-pages.security.title")
    Setting(@settings.Route::Vault) => @sf.t("web-pages.vault.title")
    Setting(@settings.Route::VaultItems) => @sf.t("web-pages.vault.all")
    Setting(@settings.Route::KeptFiles) => @sf.t("android-settings.files.title")
    Setting(@settings.Route::Connects(_)) | Place("connects") => @sf.t("android-settings.connects.title")
    // (the stations' and the profiles' lists, as their old pages said them to what they led to: an account on several
    // stations, a station's own page)
    Setting(@settings.Route::Stations) | Place("stations") => @sf.t("android-misc.bar.place.stations")
    Setting(@settings.Route::Profiles(_)) | Place("profiles") => @sf.t("android-misc.bar.place.profiles")
    Place("remote") => @sf.t("web-main.rail.remote")
    Place("usage") => @sf.t("web-pages.settings.nav.usage")
    Place("vault") => @sf.t("android-settings.vault.title")
    _ => @sf.t("common.back")
  }
}

///|
/// The page picked in a place with a list of its own (the stations', the profiles'), by workspace and place
/// (`place_key`); none: the shell's first. Said by the place's list (a row pressed) and by a page that leads to another
/// of its list or is gone from it (a profile's other stations, a profile deleted); the shell shows it (src/sfdesk
/// places.mbt place_route). Each workspace keeps its own: one picked in another is none of this one's list.
// kept across runs: said by a row or a page; the shell's places_reset empties it
pub let place_pick : @sf.LiveMap[String, @settings.Route] = @sf.LiveMap::new()

///|
/// `place_pick`'s key for `place` in the workspace `ws`.
pub fn place_key(ws : String, place : String) -> String {
  ws + "\n" + place
}
