// still.fail, as its Android app is: signed out it is the sign-in page; signed in,
// the chats of one workspace are home, and everything else a page pushed over it (@ui.Nav: sliding in,
// swiped back from the left edge; a new chat rising from the bottom), or a sheet from the bottom (sheet.mbt). The
// places of the bottom bar (bar.mbt) are the pages at the stack's root, switched in place.

///|
/// reset() called by hand since the last Tester started: what the test set after it (its clock, its system) is the
/// next Tester's to start from, not forgotten again as it starts.
let reset_by_hand : Ref[Bool] = Ref(false)

///|
/// Every Tester starts from the app as at the start (mbui's on_reset), whatever ran before it in the process: what is
/// kept here from one Tester to the next would be an input the test does not give.
fn init {
  // ＋'s Station 文件 (a composer's, sfpages): the station files' picker (sfdesk's station_pick.mbt). Said once, as the
  // app starts (reset runs only as a Tester starts: a wire set there is never set in the app)
  station_files_asked.val = @sfpages.station_files_pick
  // 浏览文件夹 of a preset's folders (sfpages presets.mbt): the files' page's folder picker, a step further in
  @sfbase.folder_pick_asked.val = @sfpages.folder_pick
  // a page's own key made as nodes (sfpages' chat page: Space): the tape's page brought over first, as the old page's
  @sfbase.page_for_key.val = @sfdesk.tape_page_for_key
  // an agent's card's jobs (sfpages): the chat's services and jobs as the screen shows them
  @sfbase.chat_jobs_open.val = fn(src, r, w) {
    if @sf.layout(w) is Small {
      open_chat_jobs(src, r)
    } else {
      @sfdesk.open_jobs_pop()
    }
  }
  // the library's run begun by the app's own reset where one was said by hand since a Tester last began (new_run): that
  // Tester begins none again, what the test opened in between is its run's (sf's run_begins.mbt)
  @sf.run_begun_by_app.val = fn() { reset_by_hand.val }
  @ui.on_reset(fn() {
    if !reset_by_hand.val {
      reset()
    }
    reset_by_hand.val = false
  })
}

///|
/// A run begun before its Tester is made (the made-up core given what it opens first, then the Tester): the run
/// before let go of first (its window's tree follows nothing this one says), then the app as at the start (reset).
pub fn new_run() -> Unit {
  @ui.run_let_go()
  @ui.host_let_go()
  reset()
}

///|
/// The app as at the start for a test that makes no Tester after it (a model's, a source's, a draft's): new_run, but
/// leaving nothing for a Tester to come. reset_by_hand is for what a test sets between new_run() and its own Tester;
/// left set by a test that made none, the next test's Tester (in the same process, whichever test that is) took the app
/// as that test had left it, not as at the start (2026-11-11). detlint's `reset-by-hand` holds new_run() to a Tester
/// after it.
// called by tests alone; here, as detlint's `reset-by-hand` wants it
pub fn fresh_app() -> Unit {
  new_run()
  reset_by_hand.val = false
}

///|
/// As at the start: Home alone, nothing chosen here yet (tests; every Tester as it starts: init above). Each global
/// of this package is put back here (or in what this calls) as its `let` has it, or says why it is kept across runs
/// (scripts/check.sh checks).
pub fn reset() -> Unit {
  files_cornered.val = false
  // the stack and what the app keeps of it (src/sfbase)
  @sfbase.reset()
  // the desktop's own (src/sfdesk)
  @sfdesk.reset()
  sheet_host.kind = NoSheet
  sheet_host.serial = 0
  bar_reset()
  bar_timing.val = None
  bar_timed.val = None
  place_switch.put(1.0)
  home_sheet_at_start.val = false
  peeks_reset()
  share_in.shared.set(None)
  share_in.files.set([])
  share_in.raised.set(false)
  // (taken: a Tester never reads the machine's MBUI_SHARE_TEXT)
  share_in.env_taken.set(true)
  share_in.searching.set(false)
  share_in.choosing.set(false)
  share_in.opening.set(None)
  share_in.error.set("")
  share_in.query.set("")
  share_in.find.set("")
  share_closing.val = false
  share_sinking.val = false
  splash_waited.set(false)
  splash_from.val = -1.0
  splash_owner.val = None
  first_shown.set(false)
  first_waiting.val = false
  @sfbase.first_page_waits.set(false)
  first_has.val = 0
  first_expired.set(false)
  first_built_ready.set(false)
  first_held.set([])
  first_words.set("")
  first_answered.set(false)
  first_from.val = -1.0
  first_top.val = None
  first_left.val = false
  first_wide.val = None
  frame_bare.val = false
  window_shown.val = false
  @sfbase.held_pictures_waiting.val = []
  cui.restore_error.clear()
  cui.doing.clear()
  pick_reset()
  chat_bar_reset()
  dv_reset()
  decide_reset()
  @settings.reset()
  ask_turns.clear()
  wide_reset()
  invite_reset()
  login_link_reset()
  // the library as a run begins (what is presented, the menus open, a group's and a page's rows, the viewers: the texts
  // read, the films played, the reader's layout; the system's bars): this is the moment the run begins where it is said
  // by hand (sf's run_begins.mbt)
  @sf.run_begin()
  outside_reset()
  attach_reset()
  // the menu bar given (menu_bar.mbt)
  // Home (home.mbt), the host told (above), a chat's page and what is in it
  tool_parts.clear()
  flashing.val = ("", 0.0)
  bench_on.val = -1
  boxed_n.val = 0
  // the composer: what waits for it
  share_files_made.val = 0
  // the made-up core's own, where one is linked (a test's, a tool's: sffixture's, as its wire says)
  (@sfbase.made_reset.val)()
  // a drive's files, a text read (keep.mbt, drive_reader.mbt)
  reset_by_hand.val = true
}

///|
/// What the app's own doings ask of the pages (sfbase shell.mbt): home and what is over the pages put their sheets
/// down too, an invitation's link shows its sheet, the screens live in their cards stop as the app goes behind; a file
/// asked beside, in the side panel of the chat in view where the frame is the wide one (`wide`, this frame's).
fn pages_shell(src : Source, wide : Bool, window_width : Double, now : () -> Double) -> Shell {
  {
    home,
    close_overlays,
    open_invite,
    open_login,
    behind: fn(s) {
      peeks_stop_all(s)
      // (where each chat open on a page made as nodes is, kept and told now: no frame may come after)
      @sfpages.chat_reads_behind()
    },
    open: fn(p) { open_where(src, wide, p) },
    open_over: fn(p) { open_over_where(src, wide, p) },
    detail: fn(s, r, tab) { detail_where(s, wide, r, tab) },
    beside: fn(tab, full) { beside_where(src, wide, tab, full) },
    beside_for: fn(tab, was) {
      match app.nav.top() {
        Chat(r) if wide => Some(@sfdesk.view_step(src, r, tab, was))
        _ => None
      }
    },
    beside_room: fn() { wide && app.nav.top() is Chat(_) },
    back: fn() { back_where(src, wide, now) },
    show: fn() {
      if wide {
        @sfdesk.show_page()
      }
    },
    bring: fn() {
      if @sfdesk.wide.tape.get() && @sfdesk.shown_in_page(app.nav.top()) {
        @sfdesk.bring_page()
      }
    },
    notice_on_board: fn(r) { wide && @sfdesk.notice_on_board(src, r, window_width) },
    edit_rail: fn() { @sfdesk.wide.editing.set(true) },
  }
}

///|
/// What back does where the layout has it (the tiers' table): the wide frame's (sfdesk's
/// wide_back); laid out Small, a page of the stack popped, a place's top page other than the chats back to the chats
/// in place (from no side), none at the chats' (the system's: the app left).
fn back_where(src : Source, wide : Bool, now : () -> Double) -> (() -> Unit)? {
  if wide {
    return @sfdesk.wide_back(src)
  }
  if app.nav.depth() > 1 {
    Some(@sfbase.back_pop)
  } else if app.nav.top() != Home {
    Some(fn() { go_place(now(), "chats", [], -1) })
  } else {
    None
  }
}

///|
/// Page `p` opened where the layout has it (the pane table): on the wide frame the page pushed,
/// a chat's detail asked as a page (its history, a service, a file) laid beside its chat by the frame (sfdesk's
/// beside_follow), on the tape shown in the page pane (sfdesk's show_page: brought over with the side panel in use, also
/// the chat already shown, chosen again); laid out Small on the phone's stack (a new chat risen from the foot).
fn open_where(src : Source, wide : Bool, p : Page) -> Unit {
  if !wide {
    stack_open(p)
    return
  }
  match app.nav.top() {
    Chat(r) => if @sfdesk.station_page_beside(src, r, p) { return }
    Place("remote") => if @sfdesk.remote_page_in_workbench(src, p) { return }
    _ => ()
  }
  // (a chat put in the page pane's place from the board (待处理's, ⌘K's, ⌘N, a row of the list beside it): the list
  // again, so that the board shows as Home again only as 看板 is pressed; on the tape over the board in use, back
  // coming to it again: page_goes_on's)
  if (p is Chat(_) || p is NewChat) && !@sfdesk.page_goes_on() && @sfbase.board_on_now(src) {
    @sfbase.board_set(src, false)
  }
  // (wide NewChat <-> Chat switch: snapshot the departing composer's box before nav replacement unmounts it)
  if !@ui.reduced_motion() {
    match (app.nav.top(), p) {
      (NewChat, Chat(r)) =>
        if @signals.untracked(fn() { @sfbase.fresh.became.get() }) != Some(r) {
          @sfbase.composer_handoff_at.set(@sfpages.composer_node_shown(0.0))
        }
      (Chat(_), NewChat) => @sfbase.composer_handoff_at.set(@sfpages.composer_node_shown(0.0))
      _ => ()
    }
  }
  match p {
    Chat(r) => open_chat_beside(r)
    NewChat => new_chat_beside()
    // the settings: their list the sidebar's, the page of its first row beside it
    Settings => @sfdesk.settings_beside(@sfdesk.settings_landing)
    // (on the tape from the page in use: over it, as a phone's is, back coming to it again)
    _ => if @sfdesk.goes_over(p) { app.nav.push_over(p) } else { app.nav.push(p) }
  }
  if @sfdesk.shown_in_page(p) {
    @sfdesk.show_page()
  }
}

///|
/// Page `p` opened from the page in view (a chat's link in a message): on the wide frame, another chat over the chat
/// shown (Nav::push_over), so back comes to it again as the web's history does (the user, 2026-10-27: a chat's link
/// followed, back went to a new chat); else where the layout has it (open_where).
fn open_over_where(src : Source, wide : Bool, p : Page) -> Unit {
  if wide {
    match (app.nav.top(), p) {
      (Chat(open), Chat(r)) if open.station != r.station || open.session != r.session => {
        app.nav.push_over(p)
        @sfdesk.show_page()
        return
      }
      _ => ()
    }
  }
  open_where(src, wide, p)
}

///|
/// A new chat on the wide frame (新建对话, ⌘N): the page pane's, in place of what was there, the chats the place in view;
/// one there already, nothing.
fn new_chat_beside() -> Unit {
  if app.nav.top() is NewChat {
    return
  }
  nav_over_home([NewChat])
}

///|
/// Chat `r` opened on the wide frame, from anywhere (a list's row, a search's, ⌘K, a link): the chat in the page pane
/// already, nothing; else the chats the place in view (from settings or another place), and the chat in the page
/// pane in place of whatever was there, never over it: the stack then holds the list and the chat alone (laid out
/// Medium, back from it goes to the list). On the tape opened from the page or its side panel in use (a link in a
/// message, a history's chat, ⌘K there): over the page, as a phone's is, back coming to the page again.
fn open_chat_beside(r : ChatRef) -> Unit {
  if @sfdesk.page_goes_on() {
    match app.nav.top() {
      Chat(open) if open.station == r.station && open.session == r.session => ()
      _ => app.nav.push_over(Chat(r))
    }
    return
  }
  // (the chat in the page pane: the stack's last chat, the chats the place in view; what is laid beside it, its
  // detail asked as a page, stays)
  if @sfdesk.lit_place() == "chats" && !app.nav.pages().contains(Archived) {
    let pages = app.nav.pages()
    for k = pages.length() - 1; k >= 0; k = k - 1 {
      match pages[k] {
        Chat(open) if open.station == r.station && open.session == r.session => return
        Chat(_) => break
        _ => ()
      }
    }
  }
  nav_over_home([Chat(r)])
}

///|
/// Chat `r`'s detail `tab` opened where the layout has it: on the wide frame its side panel's tab, toggled; laid out
/// Small the page it is (an agent's history, what the pages' message rows ask).
fn detail_where(src : Source, wide : Bool, r : ChatRef, tab : String) -> Unit {
  if wide {
    @sfdesk.side_toggle(src, r, tab)
  } else {
    app.nav.push(History(r, tab, None))
  }
}

///|
/// A file's tab `tab` asked beside (Shell's `beside`, `full` to go over the whole window at once): on the wide frame,
/// in the side panel of the chat in view, in front (that file's tab there already, brought to the front): the tab put
/// there and whether it is new there; else nowhere (None: it opens over the whole window).
fn beside_where(src : Source, wide : Bool, tab : String, full : Bool) -> (String, Bool)? {
  match app.nav.top() {
    Chat(r) if wide => Some(@sfdesk.view_beside(src, r, tab, full~))
    _ => None
  }
}

///|
/// Back to Home (the stack's root), what is over the pages put down (close_overlays: a file open over the window too,
/// as a notification tapped opens its chat over Home).
pub fn home() -> Unit {
  close_overlays()
  nav_home()
}

///|
/// The pages left since a build last began, told so (where each was left, what it held let go).
fn pages_left(src : Source) -> Unit {
  for i in 0..<left_pages.length() {
    let p = left_pages[i]
    let (page_src, chat_view) = @sfbase.left_page_source(src, i)
    if @sfbase.left_page_cancelled(i) {
      continue
    }
    match p {
      Chat(r) => {
        match page_src {
          Some(source) => {
            chat_left(source, r, saved=chat_view)
            // (what the window's source read of it too, nothing following it, let go of; nothing still read)
            if !physical_equal(source, src) {
              @sfbase.chat_reads_forget_from(src, r)
            }
            viz_chat_left(r.station, r.session)
          }
          // (an entry never drawn: nothing told; what the window's source read of its chat, nothing following it, let
          // go of where no page of that chat is left on the stack)
          None =>
            if !app.nav
              .pages()
              .iter()
              .any(fn(q) { q is Chat(x) && x.station == r.station && x.session == r.session }) {
              @sfbase.chat_reads_forget_from(src, r)
            }
        }
      }
      DriveRead(at) => reader_left(at)
      // (a drive's film played: where it was kept and its player closed as its page's nodes are let go, sfpages'
      // play_page_node)
      DrivePlay(_) => ()
      // (one put beside its chat as a tab, drawn there or over the whole window: the tab's, let go as it closes)
      Service(station, job) => if !@sfdesk.service_tab_held(station, job) { service_left(src, station, job) }
      PreviewFile(station, key, path, _) => {
        let job = "file:" + key + "\n" + path
        if !@sfdesk.service_tab_held(station, job) {
          service_left(src, station, job)
        }
      }
      History(r, key, _) => history_left(src, r, key)
      // the drive's folders read, watched for changes while shown: let go of once no page of the drive is left on
      // the stack (a folder entered over another, its columns reading those above it, keeps them)
      Files | Drive(_) =>
        if !app.nav.pages().iter().any(fn(q) { q is (Files | Drive(_) | DriveRead(_) | DrivePlay(_)) }) {
          @sfbase.let_go(src, @sfbase.drive_scope)
        }
      // (shown still in its chat's side panel, its 全屏 from there gone back to it: kept for the panel)
      Screen(at) =>
        if !@sfdesk.side_screen_shown(src, at.station, at.screen) {
          @sfpages.screen_left(src, at.station, at.screen)
        }
      _ => ()
    }
  }
  @sfbase.left_pages_clear()
  // (the pages put by on the stack's kept left told what they left: their sources put by at rest now, what they held
  // let go of as this frame ends)
  @sfbase.entries_kept_park_due()
}

///|
/// The app over `src`: call each frame.
pub fn view(c : @ui.Ctx, src : Source) -> Unit {
  // (the made-up core, where one is linked, on this frame's runtime)
  (@sfbase.made_frame.val)(c)
  @sfbase.held_build()
  c.after_build("held/end", fn() { @sfbase.held_end() })
  shell_set(pages_shell(src, @sfdesk.is_wide(c), c.window_size().0, fn() { c.moment() }))
  // the Mac's menu bar, in the app's words (menu_bar.mbt); an item of the pages' chosen is done as its action is, at
  // that moment (@settings.ask_action)
  menu_bar(c, src)
  @sfdesk.window_zoom_keys(c, src)
  appearance(c, src, page_dark(src))
  faces(src, @sfdesk.is_wide(c))
  // pictures put up by their address come as the core gives them (a GIF among them moves)
  @sf.picture_of.val = fn(url, frame) { (src.picture)(url, frame) }
  // a tip's keys, as the core's prefs set them (sfdesk's keys.mbt)
  @sf.set_shortcuts(@sfdesk.tip_keys(src))
  // the library's words, the app's catalog's; what its viewers ask of the page (viewer_host.mbt)
  @sf.set_words(fill)
  @sf.set_viewer_host(viewer_host_of(src, fn() { c.window_size().0 }))
  // a chat's file downloaded by the core, all here: kept where the system keeps downloads, whatever page shows
  // (downloads.mbt)
  downloads_frame(c, src)
  let t = @sf.begin(c)
  // under it all, the app's ground (what shows under the keyboard as it moves, the frame before the page follows it)
  // (the palette's colours are 0xRRGGBBAA; what the host clears to is said as 0xAARRGGBB, a window's background)
  c.set_clear((t.p.bg >> 8) & 0xFFFFFFL)
  // laid out Medium or Large (@sf.layout: the screen's room and kind, never what it is pointed with): the web app's
  // wide frame (sfdesk's frame.mbt: on a tape, Medium); Small, the phone's pages
  let wide = @sfdesk.is_wide(c)
  // the wide frame's lines set as the desktop app's pages set them (a browser's way)
  @ui.set_web_lines(wide)
  @settings.wide.val = wide
  @settings.status_top.val = status_top_now(c.window_size().0)
  @settings.nav_foot.val = nav_foot()
  @settings.bar_room.val = bar_room_at(c.window_size().0)
  linger_tick(c, src, in_front=app_in_front())
  // the screens live in their cards (screen_links.mbt): which are on the screen, their frames acknowledged
  peeks_frame(c, src)
  // pages left: where they were left told once the frame's builds are over (a later build would see them left too)
  @sfbase.left_said.get() |> ignore
  if left_pages.length() > 0 {
    c.after_build("pages-left", fn() { pages_left(src) })
  }
  // everything in still.fail's theme, as this frame's palette has it (light or dark, a phone's or a desktop's): the
  // styles' roles (@sf styles.mbt, the pages' own) its ink, its sizes, its corners; the one place it is put (the room
  // beside what the system has at the window's sides the tree's root keeps: app_tree, sides.mbt)
  // (the system's own bars as this frame wants them: the wide frame's tabs, else none: sfdesk's rail_native.mbt)
  c.with_theme(@sf.ui_theme(), fn() { @sfdesk.nav_frame(fn() { view_in(c, src) }) })
}

///|
fn view_in(c : @ui.Ctx, src : Source) -> Unit {
  // (the state the app is in, a node of the window's tree (app_tree), its pages old views of it put here; starting or
  // failed, signed out, the landing, reading or a window of its own, nodes with no old view to say it: said here, as the
  // state is)
  match app_is(src) {
    (Starting | Failed) as state => splash_said(src, state)
    // (signed out, or signed in at the landing: the ways in's nodes, entry_tree.mbt)
    SignedOut => entry_said()
    SignedIn if shell_is(src, c.window_size().0) is Landing => entry_said()
    // (signed in, its workspaces still read or failing to be: the splash's nodes)
    SignedIn if shell_is(src, c.window_size().0) is Reading => reading_said(src)
    // (a window of its own: its page, an old view the tree hosts, says nothing of the first page or the splash)
    SignedIn if shell_is(src, c.window_size().0) is Lone => entry_said()
    _ => ()
  }
  // (what the old frame does under its old views: over another app what is shared taken (over_view); signed in with a
  // workspace in view, in every tier (signed_in_frame) and the shell's own (shell_under))
  let over = share_over.get()
  let shell = if !over && app_is(src) is SignedIn { Some(shell_is(src, c.window_size().0)) } else { None }
  if over {
    share_in_frame(c)
  } else {
    match shell {
      Some(s) => shell_under(c, src, s)
      None => ()
    }
  }
  // (and over that: over another app its sheet (over_view); in the wide frame the presenters told the app is under
  // them (shell_over))
  if over {
    over_view(c, src)
  } else {
    match shell {
      Some(s) => shell_over(c, src, s)
      None => ()
    }
  }
  // the first page built with what it shows, the pictures the device holds in it decoded as it drew them (a likeness
  // in a picture's place for the frame or two its decoding takes is not shown): shown from this frame
  if first_waiting.val {
    // (what this frame built with what it shows answered: what it holds of the device's pictures not decoded yet
    // said with it, what first_page_done waits by; first_page_node read it of the core as it holds it now)
    if first_has.val == 1 {
      first_held.set(@sfbase.held_pictures_waiting.val.copy())
      first_built_ready.set(true)
    }
    if first_page_done() {
      first_shown.set(true)
      first_waiting.val = false
    }
  }
  first_hide(first_waiting.val)
  // the first page built, waiting for what it shows (signed_in): not shown yet, the splash over the window's ground
  // (what the host clears to, the ground's colour) in its place, its words as while the workspaces are read
  if first_waiting.val {
    // (the splash itself the window's tree's nodes over the shell: first_splash_node; the ground alone till the app's
    // first splash has waited its second, the window held not shown for it)
    if !splash_waited.get() {
      frame_bare.val = true
    }
  }
  // the window held (host_setup) shown with the first frame that draws more than the ground (the host shows it once
  // the frame is on it)
  if !frame_bare.val && !window_shown.val {
    window_shown.val = true
    @hostapi.window_show()
  }
}

///|
/// What the old frame does signed in, in shell `shell`, before its old views (view_in): with a workspace in view, what
/// it does in every tier (signed_in_frame) and the shell's own: laid out Small how the lists take the hand
/// (narrow_lists), on the tape and off it the wide frame's (sfdesk's tape_under, pane_under).
fn shell_under(c : @ui.Ctx, src : Source, shell : ShellIs) -> Unit {
  guard shell is (Stacked | Taped | Paned) else { return }
  frame_bare.val = false
  let (now, all, _, _) = workspace_in_view(src)
  match now {
    Some(w) => signed_in_frame(c, src, w)
    None => ()
  }
  match (shell, now) {
    (Stacked, _) => narrow_lists(c)
    (Taped, Some(w)) => @sfdesk.tape_under(c, src, w, all)
    (Paned, Some(w)) => @sfdesk.pane_under(c, src, w, all)
    _ => ()
  }
}

///|
/// What the old frame does last signed in, in shell `shell` (view_in): in the wide frame with a workspace in view, the
/// presenters told the app is under them (what they put up is the window's tree's: presented_nodes).
fn shell_over(c : @ui.Ctx, src : Source, shell : ShellIs) -> Unit {
  guard shell is (Taped | Paned) && workspace_in_view(src).0 is Some(_) else { return }
  @sf.presented(c)
}

///|
/// What the app shows under all of it (view_in).
#derive(Eq)
priv enum AppIs {
  /// the core failed
  Failed
  /// signed out: the sign-in page
  SignedOut
  SignedIn
  /// the accounts not read yet, or failing to be
  Starting
}

///|
/// Whether the stack of pages laid out Small (narrow_shell.mbt) is in a finger's hand now: its lists dragged and words
/// held to pick (pick.mbt); else a mouse's, the wheel scrolling them and a drag picking words, as the wide frame's.
fn stack_by_finger() -> Bool {
  @ui.pointing() is Finger
}

///|
/// Which of the app's states it is in, as the core's accounts and its failure say.
fn app_is(src : Source) -> AppIs {
  match (src.topic("accounts", {}).get().value, (src.fatal)()) {
    (_, Some(_)) => Failed
    (Some(Array(list)), _) if list.length() == 0 => SignedOut
    (Some(Array(_)), _) => SignedIn
    _ => Starting
  }
}

///|
/// A layout's name as a hang report says it (@ui.journal_arranged): one of a fixed few, never more.
fn layout_name(l : @sf.Layout) -> String {
  match l {
    Small => "Small"
    Medium => "Medium"
    Large => "Large"
  }
}

///|
/// What the app shows as a whole in a window `width` wide (sfbase's Shown, its name shown_kind's): what the window's
/// tree picks (app_tree's share sheet over another app, app_is, shell_is), a page the stack's top: on 小屏 the page on
/// top, on 中屏 and 大屏 the page the pane lands on and shows (the chats' sidebar or the rail beside it are no page;
/// sfdesk's land pushes what it lands on), a window of its own its page. What is presented over it (a sheet, a panel,
/// a menu) is not said.
fn shown_now(src : Source, width : Double) -> @sfbase.Shown {
  if share_over.get() {
    return @sfbase.Shown::Share
  }
  match app_is(src) {
    Failed | Starting => @sfbase.Shown::Starting
    SignedOut => @sfbase.Shown::SignIn
    SignedIn =>
      match shell_is(src, width) {
        Stacked | Taped | Paned => @sfbase.Shown::Shows(app.nav.top())
        Lone =>
          match @sfbase.first_lone_page() {
            Some(p) => @sfbase.Shown::Shows(p)
            None => @sfbase.Shown::Starting
          }
        Landing => @sfbase.Shown::Landing
        Reading | Unsized => @sfbase.Shown::Starting
      }
  }
}

///|
/// What the old frame (view) says each build of how everything looks and what words are set in, told the window's tree
/// `root` as it is made and as each of it changes, before any page of nodes is made, laid out or measured: light or
/// dark, the accent, motion and haptics (sfbase's appearance_from_prefs) and a tip's keys, as the prefs and the system
/// say them; and, with `words_set`, the wide frame's or not as the window is first given (Tree::frame tells its size
/// before it lays anything out), its lines set as a browser's or not and the places' faces given the host (sfbase's
/// faces). So the first frame measures its words once, in what they are drawn in, never in the system's face and lines
/// and then all of them again as the old frame says otherwise; the old frame saying the same after it does nothing.
fn app_looks_told(root : @view.View, src : Source, words_set~ : Bool = true) -> Unit {
  // (what is chosen here before the core answers read with the prefs, as 实验性功能's switches are: 外观's 深色 and its
  // accent pressed on a page made as nodes take at once, no old frame built to read them)
  root.reacts(
    fn() {
      let p = src.topic("prefs", {}).get().value
      let sys = @ui.system_dark()
      (p, sys, @settings.dark(p, sys), @settings.pref_from(p, "accent"))
    },
    fn(a) {
      @sfbase.appearance_from_prefs(a.0, a.1) |> ignore
      @sf.set_shortcuts(@sfdesk.tip_keys(src))
    },
  )
  guard words_set else { return }
  root.reacts(fn() { (src.topic("prefs", {}).get().value, root.window_w(), @sf.native_able()) }, fn(a) {
    // (none before the first frame gives the window: told as anything there would be laid out by the wide frame's
    // being otherwise and its faces then changed with nothing measured yet)
    if a.1 > 0.0 {
      let wide = @sfdesk.wide_at(a.1)
      shell_set(pages_shell(src, wide, a.1, fn() { root.cause_at() }))
      @settings.wide.val = wide
      @ui.set_web_lines(wide)
      faces(src, wide)
    }
  })
}

///|
/// The window as a tree made once (mbui's view_host.mbt, the way there's 4: from the outside in): the
/// state the app is in (app_is) a node picked by it, made as it comes and let go as it goes, the app in that state an old
/// view in it, built the old way on the window's ground (`view` the old frame around it: what every state shares, the
/// theme, the window's sides, the layers over it).
pub fn app_tree(src : Source) -> (@view.View) -> Unit {
  fn(root) {
    // (how it looks and what it is set in, told first of all, before any page of nodes is made: app_looks_told)
    app_looks_told(root, src)
    // (the source the sheets show what they show of, said before one is put up: sheet.mbt)
    sheet_src.val = Some(src)
    // (the library's words, the app's catalog's, and their language as the core's prefs say it, said before any page of
    // nodes is made: what one says on its first frame is its words in that language, not their keys or the device's
    // laid out and then said again; the old frame tells them each build, the same)
    @sf.set_words(fill)
    // (what its viewers ask of the page, said before any page of nodes is made: a text a reader of nodes reads as it is
    // made read by the core, viewer_host.mbt)
    @sf.set_viewer_host(viewer_host_of(src, fn() { root.window_w() }))
    // Keep the prefs reader with the tree from its first read, including before the first frame is built.
    root.reacts(fn() { src.topic("prefs", {}).get().value }, fn(p) {
      @sfbase.language_from_prefs(p)
      @sfbase.stale_build_from_prefs(p)
    })
    // (the experimental switches of 实验性功能 (Farview 原生标签页渲染, 看板), told before any page of nodes
    // is made and in the frame a switch is pressed: what is chosen here before the core answers is read with the prefs)
    root.reacts(
      fn() {
        let p = src.topic("prefs", {}).get().value
        (
          p,
          @settings.feature_from(p, "farviewNative"),
          @settings.feature_from(p, "board"),
        )
      },
      fn(t) { @sfbase.features_from_prefs(t.0) },
    )
    // (the window's keys as the core's prefs keep them on this device, changed as they are: settings' keymap.mbt)
    // (and a Farview tab's page's caret's keys, where it has the keyboard: fvclient's stage)
    root.keymap(By(fn() {
      let m = @settings.keymap_of(src.topic("prefs", {}).get().value)
      { ..m, bindings: [..@stage.page_keys(), ..m.bindings] }
    }))
    |> ignore
    // (the window's height, what a chat list's and a chat's first window are worked out of wherever they are first
    // asked: sfbase's first_window, chat_first_window; said before any page of nodes is made, as it asks; none before
    // the first frame gives it, what was known kept till then). Read as window().1, not window_h(): the first frame sets
    // the width before the height, and the shell below (opens_ahead_node, the pick of shell_is) is woken by the width;
    // read by the height alone this would run after them, and the chats they ask would find no height told yet.
    root.reacts(fn() { root.window().1 }, fn(h) { if h > 0.0 { @sfbase.window_tall.val = h } })
    // (the window's size from the menu bar, in every state: sfdesk's window_zoom.mbt)
    @sfdesk.zoom_actions(root, src)
    // (pictures by their address as the core gives them, said before any page of nodes is made: what one shows on its
    // first frame asks the core, not the library's stand-in; the old frame says it each build, the same)
    @sf.picture_of.val = fn(url, frame) { (src.picture)(url, frame) }
    // (what the app shows, by its kind alone, told the window thread's journal as it changes, on every host: what its
    // hang reports and the device's performance record say; no frame asks it)
    root.reacts(fn() { @sfbase.shown_kind(shown_now(src, root.window_w())) }, @ui.journal_shows)
    // (to a core that counts what people use (client/core-ts's use-counts.ts: a build given still.fail's project, on
    // its own cloud), whether to, as the settings say, and while it does what the app shows by that same kind alone,
    // each as it changes; nothing to one that does not, as under a Tester or a replay)
    root.reacts(fn() { @sfbase.counts_told(src, @sfbase.shown_kind(shown_now(src, root.window_w()))) }, fn(told) {
      match told {
        Some((on, kind)) => {
          (src.call)("client.reports", { "on": Json::boolean(on) }, @sfbase.answer_unread)
          if on {
            (src.call)("client.shown", { "page": Json::string(kind) }, @sfbase.answer_unread)
          }
        }
        None => ()
      }
    })
    // (how it lays out what it shows, 小屏/中屏/大屏 by @sf.layout's name, and the window's size, told the journal as
    // either changes: what a hang report says beside the page, so it is made again in a Tester's window of that size)
    root.reacts(
      fn() {
        let (w, h) = root.window()
        (layout_name(@sf.layout(w)), w, h)
      },
      // (none before the first frame gives the window)
      fn(a) { if a.1 > 0.0 { @ui.journal_arranged(a.0, a.1, a.2) } },
    )
    // (each window of this run beside its first, a page alone over the same core, accounts and workspaces: its tree,
    // lone_window_tree, its old views in lone_view's frame)
    @ui.set_window_tree(fn(wid, _) { lone_window_tree(src, wid) }, around=fn(c) { lone_view(c, src) })
    // (what the splash waits by, kept by what lives through the app's states: splash_begin)
    splash_owner.val = Some(root)
    // (its nodes drawn in still.fail's theme, the one its old views are built in, as light or dark is set: view's
    // with_theme)
    @ui.set_tree_theme(@sf.ui_theme_now)
    // (the window's sides beside the system's bars kept, all of it between: sides.mbt)
    root.sides(By(fn() { sides_room() })) |> ignore
    // (static by default across the whole app: structures, lists and reshapes settle at Δt 0 unless told inside
    // @view.transition for an explicit cause, libs/mbui/src/view/transition.mbt)
    root.transitions_only() |> ignore
    // over another app (a share sheet over the app it came from: share.mbt): nothing but the sheet, an old view of its
    // own; the app's state's nodes let go meanwhile, made again as it opens
    root.pick(fn() { share_over.get() }, fn(o, over) {
      o.grow(Is(1.0)) |> ignore
      if over {
        over_tree(o, src)
      } else {
        app_state_tree(o, src)
      }
    })
    // (the core what the settings put up by what has none at hand draws with (a station's card from a chat), said as
    // the tree is made and as the workspace in view changes, before what is presented is made: one put up before the
    // first frame is built (a fixture's) is made with it, not with none: settings' panels_frame)
    root.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(_) {
      match workspace_in_view(src).0 {
        Some(w) => @settings.panels_frame(settings_core(src, w), w.id)
        None => ()
      }
    })
    // the library's confirms in the middle of the window, each at its place in the window's stack of layers among what
    // else is presented (src/sf presented_node.mbt)
    @sf.presented_nodes(root)
    // what a right click offers, over every shell, switcher, viewer and presented modal (sfdesk context_menu.mbt)
    @sfdesk.context_menu_node(root)
    // floating liquid-glass editing bar for focused text fields, over presented layers and below the loupe
    @ui.field_menu_bar(root) |> ignore
    @sf.field_bar_node(
      root,
      fn() { !share_over.get() && app_is(src) is SignedIn },
      fn() {
        {
          cut: @sf.t("desktop.contextMenu.cut"),
          copy: @sf.t("desktop.contextMenu.copy"),
          paste: @sf.t("desktop.contextMenu.paste"),
          select_all: @sf.t("desktop.contextMenu.selectAll"),
        }
      },
      on_copied=fn() { @sfbase.toast_later(@sf.t("common.copied")) },
    )
    // what a write said, over all of it, in every state and shell (sfbase's toasts_node)
    @sfbase.toasts_node(root, fn() { toast_bottom_now(root) }) |> ignore
    // what a finger hides as it drags a field's caret or what is picked, shown larger over all of it, signed in (the
    // library's loupe_node: a switch's knob held's glass)
    @sf.loupe_node(root, fn() { !share_over.get() && app_is(src) is SignedIn })
    // the window's own buttons where they are the app's (Windows', Linux's), over all of it as a title bar's are: on
    // the bar's line of a page over all the window (a window of its own, a chat's tab or a file over the whole window)
    // at any width, as in a window's whole
    @sf.window_keys_node(
      root,
      whole=fn() {
        shell_is(src, root.window_w()) is Lone ||
          @sfbase.tab_full.get() is Some(_) ||
          @sfbase.preview_open()
      },
    )
  }
}

///|
/// Over another app in node `o` (app_tree's, as share_over says): in a browser's window of its own, what is shared
/// filling it (share_window), made once as nodes; what is shared taken and its sheet put up by the old frame (view_in:
/// over_view).
fn over_tree(o : @view.View, src : Source) -> Unit {
  o.show(at_once=true, share_inline, fn(w) {
    @sf.style_node(w, fn() { share_window })
    share_sheet_node(w, src)
  })
}

///|
/// The app in the state it is in (app_is), a node picked by it (app_tree's, not over another app).
fn app_state_tree(root : @view.View, src : Source) -> Unit {
  root.pick(
    fn() { app_is(src) },
    fn(v, state) {
      v.grow(Is(1.0)) |> ignore
      match state {
        // starting or failed, the splash: the window's tree's nodes (splash_tree)
        Starting | Failed => splash_tree(v, src, state)
        // signed out, the sign-in page: the window's tree's nodes (entry_tree.mbt)
        SignedOut => signed_out_tree(v, src)
        SignedIn => {
        // where the app is, put in the history's entry now as the stack or the workspace in view changes, at that
        // change (sfbase's app_history.mbt: a person's act pushed an entry before it moved the stack, one for all the
        // steps it takes, noted once it is done: history_acts_ended); on the wide frame Home alone is passing (land)
        v.reacts(
          fn() {
            let ws = match workspace_in_view(src).0 {
              Some(now) => now.id
              None => ""
            }
            let wide = !(@sf.layout(v.window_w()) is Small) || @sf.native_able()
            (ws, app.nav.pages(), wide, @sfbase.history_acts_ended())
          },
          fn(said) {
            let (ws, pages, wide, _) = said
            @sfbase.history_note(ws, wide && pages == [Home])
          },
        )
        // the first page's wait, at the moments its causes come (first_page_node)
        first_page_node(v, src)
        // what the page on top reads as it is first built, asked as it comes on top (sfbase's page_opens_node)
        @sfbase.page_opens_node(v, src, fn(w, p, ask) {
          if @sf.layout(v.window_w()) is Small && !@sf.native_able() {
            page_opens_by(src, w, p, ask)
          } else {
            @sfdesk.pane_opens(src, w.id, p, ask)
          }
        })
        // what the start says of notifications, at the moment the core's notify is answered or the app shown again
        @sfbase.notices_said_node(v, src)
        // what the workspace in view opens on, asked as it comes to be in view, the splash or the shell before it
        // still shown (sfbase's opens_ahead_node): its shell's panes' (小屏's Home, home_opens; the wide frame's,
        // sfdesk's frame_opens)
        @sfbase.opens_ahead_node(v, src, fn() {
          let width = v.window_w()
          if width <= 0.0 {
            None
          } else if @sf.layout(width) is Small && !@sf.native_able() {
            Some(("narrow", home_opens))
          } else {
            // (a page open already, not Home: the pane opens on it, not on what it would land on)
            match @signals.untracked(fn() { app.nav.top() }) {
              Home => Some(("wide", @sfdesk.frame_opens))
              p => Some(("wide", fn(src, ws, ask) { @sfdesk.frame_opens_on(src, ws, Some(p), ask) }))
            }
          }
        }, first_waits=fn() { !first_shown.get() })
        // signed in, the shell it is laid out in a node picked by the window's width and what is in view
        // (narrow_shell.mbt): laid out Small with a workspace, the narrow shell's nodes; on the tape, its panels' nodes
        // (tape_shell.mbt); the ways in, the splash, a window of its own; nothing before the window has a width
        let shell_was : Ref[ShellIs] = Ref(Unsized)
        v.pick(fn() { shell_is(src, v.window_w()) }, fn(s, shell) {
          // Resizing into the tape keeps the page being read in front, not the sidebar's old selection.
          if shell is Taped && shell_was.val is (Stacked | Paned) && !@sf.native_able() &&
            app.nav.top() != Home && pane_ready(src, app.nav.top()) {
            @sfdesk.wide.tape_at.set(Page)
            @sfdesk.wide.tape_ask.set(None)
          }
          shell_was.val = shell
          s.grow(Is(1.0)) |> ignore
          // the app's keys, in every tier with a workspace in view (sfdesk's keys.mbt): what is the wide frame's alone
          // passes the key on laid out Small
          if shell is (Stacked | Taped | Paned) {
            @sfdesk.frame_actions(s, src)
          }
          match shell {
            Stacked => narrow_shell(s, src)
            Taped => taped_shell(s, src)
            Paned => paned_shell(s, src)
            Landing => landing_tree(s, src)
            Reading => reading_tree(s, src)
            Lone => lone_tree(s, src)
            // (no width yet: nothing laid out, the window's first frame giving one before anything is (Tree::frame:
            // the room set before what follows it is worked out), the shell picked again by it)
            Unsized => ()
          }
        })
        // the first page built, waiting for what it shows: not shown yet, the splash over it, its words as while the
        // workspaces are read (first_words), on the window's ground (what the host clears to)
        first_splash_node(v)
        }
      }
    },
  )
}

///|
/// A window of its own (sfbase's window.mbt) in node `v` (shell_is's Lone): on the window's ground, its top dragging it
/// where its buttons are in the app's top row (under all of it), its page alone over all of it (a station's screen,
/// sfpages' screen_node: closing it closes the window; a terminal; a chat's tab, sfdesk's tab_window_node), the library's presenters and the toasts over that, taking a finger
/// only where they draw something.
fn lone_tree(v : @view.View, src : Source) -> Unit {
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  v.show(fn() { @ui.window_inset_now() }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(b) { b.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore }) |> ignore
  })
  // a Farview tab, while 实验性功能's Farview 原生标签页渲染 is on: drawn here (sfpages' farview_tab_node), under the
  // window's top band, as the panel and the phone's page draw it: its page laid out at this window's width as it
  // changes, not a picture of the tab; any other station's screen (and a Farview tab with it turned off) its page,
  // sfpages' screen_node, a terminal its own (sfpages' terminal_node), closing it closing the window. Made again for
  // another page put in its place (a child popup followed, another tab chosen, another of the station's switched to
  // from its bar: sfbase's lone_page_replace)
  // (the window's own, as what started it put it: lone_page, the run's own for a run of its own)
  let shown = @sfbase.lone_shown.val
  shown.set(@sfbase.lone_page.val)
  // (its title the page's, said again as another is put in its place; this window's by its id, taken as it is made, as
  // what tells it may come while another window's runtime is in place: a tab's own, as its name comes, sfdesk's)
  let wid = @ui.current_window_id()
  v.reacts(fn() { shown.get() }, fn(p) {
    match p {
      Some((Screen(_) | Terminal(_)) as p) if wid > 0 => @ui.set_window_title_of(wid, @sfbase.window_title(p))
      _ => ()
    }
  })
  v.pick(
    at_once=true,
    fn() {
      let native = @sfbase.farview_native.get()
      match shown.get() {
        Some(Screen(at)) => Some((@sfbase.Page::Screen(at), native && @sfpages.farview_screen(at.screen)))
        Some(Terminal(at)) => Some((@sfbase.Page::Terminal(at), false))
        Some(SideTab(f)) => Some((@sfbase.Page::SideTab(f), false))
        _ => None
      }
    },
    fn(q, shown) {
      q.over(Is(true)) |> ignore
      match shown {
        // (each page's one bar the window's top row, a bar's height at its top, clear of the window's buttons (a Mac's at
        // its left, Windows' and Linux's at its right) and moving the window where nothing of it takes the press; no way
        // back, the window's own close (⌘W) closing it)
        Some((Screen(at), true)) =>
          @sfpages.farview_pane_node(
            q,
            src,
            at.station,
            at.screen,
            title=at.title,
            on_switch=@sfbase.lone_page_replace,
            on_close=fn() { lone_closed(q) },
            bar_pads=fn() {
              (
                if @ui.window_keys_left_now() { lone_bar_buttons_in } else { lone_bar_in },
                @sf.window_end_in(lone_bar_in, roots=@ui.tree_corner_roots_now()),
              )
            },
          )
        Some((Screen(at), false)) => {
          q.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          // (its frame the window's top, no band over it at any width: the band is a phone's laid out Small, never a
          // window of its own's)
          @sfpages.screen_node(
            q,
            src,
            at,
            fn() { { back: None, top: @ui.system_bars().top, foot: nav_foot(), named: false } },
            on_close=fn() { lone_closed(q) },
          )
        }
        Some((Terminal(at), _)) =>
          @sfpages.terminal_pane_node(
            q,
            src,
            at,
            back=fn() { "" },
            on_back=fn() { lone_closed(q) },
            top=fn() { @ui.system_bars().top },
            width=fn() { q.window_w() },
            on_switch_page=@sfbase.lone_page_replace,
          )
        // (a chat's tab: drawn as over the whole window, its bar the window's top row, clear of the window's buttons as
        // that bar keeps itself (sf's viewer_bar_node), its 移到侧边 putting it back beside the chat and closing the
        // window: sfdesk's tab_window_node)
        Some((SideTab(f), _)) => @sfdesk.tab_window_node(q, src, f, top=fn() { 0.0 }, on_close=fn() { lone_closed(q) })
        Some(_) => ()
        None => ()
      }
    },
  )
}

///|
/// A window of its own's page closed (lone_tree's, in node `q`): a window of this run beside its first closed
/// (@ui.window_close_here: the run goes on), else the run of its own it is (its window closed as its own close button
/// closes it), once the press that closed it is done.
fn lone_closed(q : @view.View) -> Unit {
  let wid = @ui.current_window_id()
  q.at_moment(q.logic_at(), fn() { if wid > 0 { @ui.window_close_here(wid) } else { @hostapi.exit(0) } }) |> ignore
}

///|
/// Window `wid` of this run beside its first (sfbase's open_window: a station's screen to a window of its own) as a
/// tree made once: its page alone (lone_tree), over the core, the accounts and the workspaces this run holds already,
/// so its first frame shows the page as it is (no splash, nothing read anew: a screen's view the window it left handed
/// it); its keys the app's, what is presented in it and its toasts its own (sfbase's window.mbt, the library's
/// presenters: each window's apart), none of the first window's history, splash or first page.
pub fn lone_window_tree(src : Source, wid : Int) -> (@view.View) -> Unit {
  fn(root) {
    // (light or dark, the accent and a tip's keys as the first window's tree tells them, before its page is made: the
    // faces and lines its words are set in are the run's, told by the first window's (app_looks_told's `words_set`))
    app_looks_told(root, src, words_set=false)
    @sfbase.lone_page.val = @sfbase.window_here_page(wid)
    // (the library's words and their language as the first window's tree says them: app_tree's)
    @sf.set_words(fill)
    root.reacts(fn() { src.topic("prefs", {}).get().value }, @sfbase.language_from_prefs)
    // (its own size from the menu bar and its keys, apart from the first window's)
    @sfdesk.zoom_actions(root, src, kept=false)
    root.keymap(By(fn() {
      let m = @settings.keymap_of(src.topic("prefs", {}).get().value)
      { ..m, bindings: [..@stage.page_keys(), ..m.bindings] }
    }))
    |> ignore
    @ui.set_tree_theme(@sf.ui_theme_now)
    root.sides(By(fn() { sides_room() })) |> ignore
    root.transitions_only() |> ignore
    // ⌘W (a Mac's, the web's there) or Ctrl+W closes it, nothing presented over its page: what its own close button
    // does, the tab or the screen it shows let go of as it closes (sfbase's window_here_gone); a Mac's menu bar's ⌘W
    // the same, Windows', Linux's and a browser's window having none of it to
    root.on_key(fn(k) {
      let primary = match @ui.keys_system() {
        0 | 1 => @ui.mod_cmd
        _ => @ui.mod_ctrl
      }
      guard wid > 0 && k.code == @ui.key_of_char('w') && k.mods == primary else { return false }
      guard !@signals.untracked(@sf.presenting) else { return false }
      lone_closed(root)
      true
    })
    |> ignore
    root.box(fn(v) {
      v.grow(Is(1.0)) |> ignore
      lone_tree(v, src)
    })
    |> ignore
    @sf.presented_nodes(root)
    @sfdesk.context_menu_node(root)
    @ui.field_menu_bar(root) |> ignore
    @sf.field_bar_node(
      root,
      fn() { true },
      fn() {
        {
          cut: @sf.t("desktop.contextMenu.cut"),
          copy: @sf.t("desktop.contextMenu.copy"),
          paste: @sf.t("desktop.contextMenu.paste"),
          select_all: @sf.t("desktop.contextMenu.selectAll"),
        }
      },
      on_copied=fn() { @sfbase.toast_later(@sf.t("common.copied")) },
    )
    @sfbase.toasts_node(root, fn() { toast_bottom_now(root) }) |> ignore
    @sf.window_keys_node(root, whole=fn() { true })
  }
}

///|
/// How far in from the window's sides a window of its own's one bar stands (lone_tree's Farview tab): at its corner
/// alone, after a Mac's own buttons at its left.
let lone_bar_in : Double = 12.0

///|
let lone_bar_buttons_in : Double = 84.0

///|
/// The old frame round window `wid`'s old views (lone_window_tree's): still.fail's theme as the first window's frame has
/// it (view's), what the host clears to its ground; nothing of the first window's own (its shells, its first page, its
/// menu bar, what the core says each frame).
pub fn lone_view(c : @ui.Ctx, src : Source) -> Unit {
  ignore(src)
  let t = @sf.begin(c)
  c.set_clear((t.p.bg >> 8) & 0xFFFFFFL)
  c.with_theme(@sf.ui_theme(), fn() {
    entry_said()
  })
}

///|
/// What the splash says while no workspace is in view yet and the landing is not shown (reading_tree's): why reading the
/// workspaces failed (the core's words), else 正在读取你的 workspace and what it waits on (t_reading_workspaces); and
/// whether it failed (said at once, not after the splash's second).
fn reading_said_words(src : Source) -> (String, Bool) {
  match src.topic("workspaces", {}).get().error {
    Some(e) => (text(Some(e), "message"), true)
    None => (t_reading_workspaces(src), false)
  }
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), as the frame begins (view_in's): what is
/// said of the frame: no first page waiting nor its pictures; the ground
/// alone until the splash's second, unless it failed.
fn reading_said(src : Source) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = []
  // (whether it failed alone: the words, the core's status read, are the splash's nodes' (reading_tree), read as they
  // change; read by a frame, status was held till the frame after the workspace came into view, not let go of then)
  frame_bare.val = !splash_waited.get() && src.topic("workspaces", {}).get().error is None
}

///|
/// Signed in, its workspaces still read or failing to be (shell_is's Reading), in node `v`: the splash's nodes saying so
/// as it changes (reading_said_words).
fn reading_tree(v : @view.View, src : Source) -> Unit {
  splash_of_tree(v, fn() { Some(reading_said_words(src).0) }, fn() { reading_said_words(src).1 })
}

///|
/// 正在读取你的 workspace, with what the core has been waiting on for a while under it, a line each (`status`'s
/// lines: what is read and how far it has come, then what lasts).
fn t_reading_workspaces(src : Source) -> String {
  let lines = items(src.topic("status", {}).get().value, "lines").filter_map(fn(l) {
    match l {
      String(s) => Some(s)
      _ => None
    }
  })
  [tr("android-misc.workspaces.loading"), ..lines].join("\n")
}

///|
/// A place from the bottom bar (AppState.place): its page takes the stack's root, in place (nothing to go back to),
/// coming in from the side the ball goes to; the same place again changes nothing. `sets`, `cur`:
/// the bar it is chosen in (none: from no side). The page left kept and the one come to taken back where it was kept
/// (go_place_by's `kept`).
pub fn go_place(at : Double, place : String, sets : Array[Array[String]], cur : Int) -> Unit {
  go_place_by(at, place, sets, cur, true)
}

///|
/// go_place's, the page that leaves the stack's root put on its shelf and the one come to taken back from it where it is
/// there (`kept`: sfbase's nav_root_kept), or let go and made anew (not `kept`: what a test compares a page kept with,
/// bar_places_kept_test.mbt).
pub fn go_place_by(at : Double, place : String, sets : Array[Array[String]], cur : Int, kept : Bool) -> Unit {
  let from = match place_of(app.nav.top()) {
    Some(p) => p
    None => ""
  }
  // the side it comes in from: the bar's order now
  let bar_now = if cur >= 0 && cur < sets.length() { sets[cur] } else { [] }
  let a = bar_now.search(from).unwrap_or(-1)
  let b = bar_now.search(place).unwrap_or(-1)
  let way = if a < 0 || b < 0 || a == b {
    0
  } else if b > a {
    1
  } else {
    -1
  }
  // the shell's (sfbase's shell.mbt), then the bar's own: timed from here (BarTiming), the page coming in from its side
  // (Arrive), from this moment; the page left kept on the stack's shelf, the one come to taken back from it where it is
  // there (sfbase's nav_root_kept)
  let tab_ms = if cur >= 0 { 260.0 } else { 0.0 }
  if !@sfbase.go_place(place, way~, kept~, tab_ms~) {
    return
  }
  bar_placed(from, place)
  place_switch.put(0.0)
  place_switch.go(
    1.0,
    if way == 0 { @motion.tween(switch_fade_ms, ease=Out) } else { @motion.moved(points=switch_slide) },
    at~,
  )
  // (what a finger's press on its tab asked ahead held till the place has come in: sfbase's places_ahead_node)
  let tab_end = app.nav.tab_ends_at()
  @sfbase.place_switched(if tab_end > 0.0 { tab_end } else { place_switch.ends_at() })
}

///|
/// What a device waiting to be confirmed in the workspace's safe mode sees in Home's place, in `q` (all of the page's
/// room): sfpages' page over the navigation bar, Home's top bar over it (settings and the workspace's switcher: with no
/// bottom bar either, a phone had no way out of the workspace, Security.kt SecurityWaitingScreen, 2026-10-23).
fn lock_gate_node(q : @view.View, src : Source, core : @settings.Core) -> Unit {
  let workspace = fn() { workspace_in_view(src).0 }
  q.box(fn(page) {
    page.over(Is(true)) |> ignore
    page.box(fn(held) {
      held.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      held.show(fn() { workspace() is Some(_) }, fn(p) {
        let w = @signals.untracked(workspace).unwrap()
        p.grow(Is(1.0)) |> ignore
        // (the top bar lies over the page's top: its column stays out from under it, home_top_bar_node's height)
        @sfpages.lock_wait_node(p, core, @settings.here_of(core, w.id, w.name), clear=fn() {
          status_top_now(p.window_w()) + bar_h
        })
        |> ignore
      })
    })
    |> ignore
    page.box(fn(foot) { foot.height(By(fn() { Some(nav_foot()) })) |> ignore }) |> ignore
  })
  |> ignore
  q.box(fn(bar) {
    bar.over(Is(true)).lies_along(Is(Start)) |> ignore
    // (nothing it shows has a tip: no chats' view, so nothing catching up)
    home_top_bar_node(bar, src, @sf.TipLayer::new(fn() { None }), workspace, fn() { None }, bell=false)
  })
  |> ignore
}

///|
/// How long a place switched to on the bar takes to come in: fading in from no side, from the side the ball goes to.
pub let switch_fade_ms : Double = 180.0

///|
/// How far a place switched to on the bar comes in from its side (points), a Move as long as that is far.
pub let switch_slide : Double = 30.0

///|
/// How far the page at the stack's root has come in as its place was switched to on the bar (0 … 1, go_place's way
/// from the moment it was switched to, from the side app.switch_way says): its old view's (page_view) and its nodes'
/// where it is made once (place_comes_in) read this one, whenever made.
// kept across runs: put back as a run begins (reset)
let place_switch : @motion.Way = @motion.Way::new(1.0)

///|
/// How far over what the system's bars leave of the window's foot the toast is, for the window's tree's (toast's,
/// followed): the wide frame's 24; the narrow one's over the bar's room.
fn toast_bottom_now(v : @view.View) -> Double {
  let wide = !(@sf.layout(v.window_w()) is Small) || @sf.native_able()
  // (over the system's bars at the window's foot: the toaster keeps clear of them itself, View::clear)
  if wide {
    @sf.toast_bottom
  } else {
    bar_room
  }
}

///|
/// How long a toast stays (paused while the pointer is on it): the library's (toast.tsx).
pub let toast_ms : Double = @sf.toast_ms

///|
/// How long a toast offering something to do stays (an archive's 撤销): the library's.
pub let toast_action_ms : Double = @sf.toast_action_ms

///|
/// What the splash says it waits for, or what failed (`state` Starting or Failed): the core's failure; the accounts'
/// error. Said at once where there is one (splash's `now`).
fn splash_label(src : Source, state : AppIs) -> String? {
  match state {
    Failed => (src.fatal)()
    _ =>
      match src.topic("accounts", {}).get().error {
        Some(e) => Some(text(Some(e), "message"))
        None => None
      }
  }
}

///|
/// Starting or failed, the window's tree's nodes in its place (app_state_tree): what is said of the frame, said from the state it is in as the frame begins (view_in): no first
/// page waiting nor its pictures; the ground alone until the splash's second, unless there is something to say at once.
fn splash_said(src : Source, state : AppIs) -> Unit {
  first_waiting.val = false
  @sfbase.held_pictures_waiting.val = []
  frame_bare.val = !splash_waited.get() && splash_label(src, state) is None
}

///|
/// The splash (`state` Starting or Failed) as the window's tree's nodes (app_state_tree's): splash_of_tree saying what
/// it waits for or what failed (splash_label), at once where there is something to say.
fn splash_tree(v : @view.View, src : Source, state : AppIs) -> Unit {
  splash_of_tree(v, fn() { splash_label(src, state) }, fn() { splash_label(src, state) is Some(_) })
}

///|
/// The app starting, or waiting for what every page needs: the ground alone, as the system's own splash before the
/// app's first frame is (Android's theme, iOS's launch screen), so an opening quicker than a second is one picture and
/// then the page; once it takes a while (a second), still.fail's mark and what it waits for under it, from then on; at
/// once when `now` (a failure). (The mark at once, on Android after the launcher's icon on the system's splash, then
/// the page: three pictures in a second, 2026-10-26 「打开的时候感觉乱闪」.)
/// The splash as the window's tree's nodes in `v`: saying `label` as it changes, the ground alone till the
/// app's first splash has waited its second unless `now` says to show it at once (splash_begin, at this moment if none
/// has begun); then still.fail's mark and what it says under it, its lines each in the middle, all in the middle of the
/// window. Where the window's buttons are in the app's top row (as that changes), its top drags it, under all of it.
fn splash_of_tree(v : @view.View, label : () -> String?, now : () -> Bool) -> Unit {
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  v.show(fn() { @ui.window_inset_now() }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(b) { b.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore }) |> ignore
  })
  match splash_owner.val {
    Some(owner) if owner.alive() =>
      v.reacts(fn() { v.window_w() > 0.0 }, fn(sized) {
        if sized && owner.alive() {
          splash_begin(owner, v.cause_at())
        }
      })
    _ => ()
  }
  let mark = fn() { if @sf.theme().dark { "stillfail_mark_dark" } else { "stillfail_mark" } }
  v.box(fn(s) {
    s.over(Is(true)).pad(Is(24.0)).lines_up(Is(Some(Middle))) |> ignore
    // (in the middle of the window's height: as much room above as below)
    s.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
    s.show(fn() { splash_waited.get() || now() }, fn(m) {
      m.gap(Is(16.0)).lines_up(Is(Some(Middle))) |> ignore
      // (the mark, its curves cut for the pixels the window is drawn at)
      m.box(fn(k) {
        k
        .width(Is(Some(56.0)))
        .height(By(fn() { Some(@sf.drawable_height(mark(), 56.0)) }))
        .picture(By(fn() { @sf.drawable_vector(mark()) }))
        |> ignore
      })
      |> ignore
      m.show(fn() { !now() }, fn(b) {
        b.width(Is(Some(splash_bar_w))) |> ignore
        @sf.progress_node(b, fn() { None }, fn() { @ui.tree_theme().line }, fn() { @sf.theme().p.accent }) |> ignore
      })
      m.show(fn() { label() is Some(_) }, fn(w) {
        w
        .words(By(fn() { label().unwrap_or("") }))
        .words_look(By(fn() { { size: @sf.theme().t.meta, weight: 400, line: 18.0, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 } }))
        .ink(By(fn() { @sf.theme().p.muted }))
        .words_centered(Is(true))
        |> ignore
      })
    })
    s.box(fn(g) { g.grow(Is(1.0)) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// How wide the splash's bar is, under still.fail's mark while it waits.
let splash_bar_w : Double = 120.0

///|
/// How long the splash shows the ground alone before it says that it waits, and for what (the app's first splash's
/// second, waited by the window's tree from its start whatever state the app comes to meanwhile).
pub let splash_label_ms : Double = 1000.0

///|
/// Whether the app's first splash has waited its second (splash_label_ms): its mark and what it waits for shown from
/// then on.
let splash_waited : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// When the app's first splash began (-1: none yet), and what keeps the moment it has waited its second: the window's
/// tree's root, which lives through the app's states (app_tree).
// kept across runs: put back as a run begins (new_run)
let splash_from : Ref[Double] = Ref(-1.0)

///|
// kept across runs: put back as a run begins (new_run)
let splash_owner : Ref[@view.View?] = Ref(None)

///|
/// The app's first splash begun at `at` (once; a splash begun again, in another of the app's states, waits for the same
/// moment): the moment it has waited its second kept by `owner`, splash_waited set then, at that moment.
fn splash_begin(owner : @view.View, at : Double) -> Unit {
  if splash_from.val >= 0.0 {
    return
  }
  splash_from.val = at
  owner.at_moment(at + splash_label_ms, fn() { splash_waited.set(true) }) |> ignore
}

///|
/// How long a page opening waits at most for the core's answer: what it shows, as the device holds it, or that it
/// waits on a station (Source.waits: a chat none of whose messages are here), never for a station. As long as the
/// first page's (first_page_ms), not LOCAL_MS: the core reads what is here in its own time, slower on a phone and
/// busy as the app comes back (what came meanwhile read in); cut short at LOCAL_MS, a chat on the device slid in as its
/// messages' bones, they a moment later (2026-10-31, android 0.1.6303: no request to a station as the chats opened).
pub let page_local_ms : Double = splash_label_ms

///|
/// How long the app's first page waits for what it shows (all of it the core's on the device, as a page opening's):
/// as long as the window shows its ground alone (splash_label_ms), not a page opening's LOCAL_MS. The core is starting
/// then and answers more slowly than in a running app; cut short at LOCAL_MS, the page came in pieces (2026-10-27,
/// the sidebar by itself, then the chat's bones, then its messages), where an opening quicker than that is meant to be
/// one picture and then the page (splash).
pub let first_page_ms : Double = splash_label_ms

///|
/// Whether the core has answered (a value or why not) for what page `p` of workspace `w` shows as it opens (App.kt
/// opening): a chat (or said its messages wait on a station: its page shows them to come), an agent's history, Home
/// (all it opens on: home_opens, what a workspace switched waits for too); where what opens waits for what it shows
/// (gates_opens, MBUI_OPEN_WHOLE) every other page what it reads as it is first drawn (sfbase's page_reads), else none.
fn page_ready(src : Source, w : Workspace, p : Page) -> Bool {
  page_opens_by(src, w, p, @sfbase.read_now(src))
}

///|
/// page_ready's, each topic asked of `ask`.
fn page_opens_by(
  src : Source,
  w : Workspace,
  p : Page,
  ask : (String, Map[String, Json]) -> @sfbase.TopicState,
) -> Bool {
  let whole = (src.gates_opens)()
  match p {
    Chat(r) => @sfbase.chat_opens(r, ask, whole~)
    History(r, key, _) => {
      let t = ask("history", history_params(r, key))
      @sfbase.chat_opens(r, ask) && (t.value is Some(_) || t.error is Some(_))
    }
    Home => home_opens(src, w.id, ask)
    // (every other page, where what opens waits for what it shows: all it reads as it is first drawn, sfbase's
    // page_reads, the table a press opening it asks by too)
    _ => !whole || @sfbase.reads_told(@sfbase.page_reads(src, w.id, p, false), ask)
  }
}

///|
/// Whether the app's first page shows: once the core has answered for what it shows and the pictures the device holds
/// in it are decoded (first_page_done), or `first_page_ms` after the workspace came into view (first_expired), from
/// then on. What the frame finds of it as it begins (first_has), for view_in to say after its builds. Under the
/// window's tree what it shows answered is first_page_node's (first_answered, by opens_ahead_node's reads), read here
/// alone: the old frame, built in no island, reading what the first page opens by would hold all of it itself and ask
/// and let go of it as its own builds go (the replays' order); only without the tree is it read here.
fn first_page_shown(c : @ui.Ctx, src : Source, w : Workspace) -> Bool {
  if !first_shown.get() {
    first_has.val = if first_expired.get() {
      2
    } else if @ui.view_tree() is Some(_) {
      if first_answered.get() {
        1
      } else {
        0
      }
    } else if first_page_ready_by(src, w, @sfdesk.is_wide(c), @sfbase.read_now(src)) {
      1
    } else {
      0
    }
  }
  first_shown.get()
}

///|
/// What the first page not shown yet has this frame (first_page_shown): 0 not what it shows, 1 what it shows (shown
/// once the pictures the device holds in it are decoded too: view_in), 2 first_page_ms gone by (shown as it is).
let first_has : Ref[Int] = Ref(0)

///|
/// Whether the core has answered for what the app's first page shows, as a page opening waits for it, each topic asked
/// of `ask`: laid out Small the page on top as the wait began (first_top: one opened over it before it is shown, a
/// chat tapped on what shows of it, is that page's own wait, not the first page's), in the wide frame (`wide`) what it
/// opens on, as opens_ahead_node declares it: on Home the rail, the sidebar and the page the pane lands on, whether or
/// not a frame has landed it yet (@sfdesk.landing_opens), on another page that page in the pane.
fn first_page_ready_by(
  src : Source,
  w : Workspace,
  wide : Bool,
  ask : (String, Map[String, Json]) -> @sfbase.TopicState,
) -> Bool {
  if wide {
    // (the pane landed by a frame (sfdesk's land): waited for by that, as landing(w) was till 2026-11-12, the first
    // page was answered no sooner than the frame after what it shows was; a page opened before it lands is in the
    // pane in its place, never landed on, so the page on top now, as opens_ahead_node has it)
    match app.nav.top() {
      Home => @sfdesk.landing_opens(src, w.id, ask)
      p => @sfdesk.frame_opens_on(src, w.id, Some(p), ask)
    }
  } else {
    page_opens_by(src, w, first_top.val.unwrap_or(app.nav.top()), ask)
  }
}

///|
/// Whether the first page waits no more, at the moment its cause comes: `first_page_ms` gone by (first_expired), or
/// what it shows answered as a frame built it (first_built_ready) and each picture the device holds in it that build
/// found not decoded decoded since (first_held: the host's word on each, image_decoded's moment).
fn first_page_done() -> Bool {
  first_expired.get() ||
  (first_built_ready.get() && first_held.get().iter().all(fn(k) { @ui.image_any_ready(k) }))
}

///|
/// Whether `first_page_ms` has gone by since the workspace came into view, not shown yet (first_page_node: set at
/// that moment).
let first_expired : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether a frame has built the first page with what it shows answered (view_in: what it holds of the device's
/// pictures said with it, first_held).
let first_built_ready : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// The pictures the device holds in the first page that its build found not decoded (sfbase's held_pictures_waiting,
/// as the frame that built it with what it shows answered left it: view_in).
let first_held : @signals.Signal[Array[String]] = @signals.signal([], same=fn(a, b) { a == b })

///|
/// What the splash over the first page says while it waits (first_page_node: 正在读取你的 workspace and what the core
/// waits on, read till what the page shows is answered, the last of it said after).
let first_words : @signals.Signal[String] = @signals.signal("", same=fn(a, b) { a == b })

///|
/// Whether what the first page shows has been answered as first_page_node read it (the splash's words read of the
/// core's status no more from then).
let first_answered : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// The first page's wait in node `v` (signed in), at the moments its causes come, between frames: `first_page_ms`
/// after the workspace came into view, the first page shown as it ends (first_expired); the first page shown at the
/// moment it waits no more (first_page_done: its pictures decoded, the host's word's moment); and the splash's words
/// over it (first_words) read of the core's `status` only till what the page shows is answered, so what was asked for
/// them is let go of at that moment, not as a frame after it builds.
fn first_page_node(v : @view.View, src : Source) -> Unit {
  // (its first_page_ms waited for no more once it has shown: nothing left due)
  let expiry : Ref[() -> Unit] = Ref(fn() {  })
  v.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(ws) {
    if ws is Some(_) && !first_shown.get() && first_from.val < 0.0 {
      first_from.val = v.cause_at()
      first_top.val = Some(app.nav.top())
      let at = first_from.val + first_page_ms
      let due = if splash_from.val >= 0.0 && !@signals.untracked(fn() { splash_waited.get() }) {
        let floor = first_from.val + @sf.local_ms * 3.0
        let cap = splash_from.val + splash_label_ms - 1.0
        dmax(floor, dmin(at, cap))
      } else {
        at
      }
      expiry.val = v.at_moment(due, fn() { first_expired.set(true) })
    }
  })
  v.reacts(fn() { first_shown.get() }, fn(shown) {
    if shown {
      (expiry.val)()
    }
  })
  v.reacts(fn() { !first_shown.get() && first_from.val >= 0.0 && first_page_done() }, fn(done) {
    if done {
      first_shown.set(true)
      first_waiting.val = false
      first_hide(false)
    }
  })
  v.reacts(
    fn() {
      if first_shown.get() {
        return None
      }
      // (told again as a page declares more of what it reads: a chat's login cards, as its view says them, sfbase's
      // page_opens_node; read held then)
      @sfbase.page_declared_now() |> ignore
      // (once answered, the core's status read no more for it, though what the first page shows comes to be another)
      let answered = first_answered.get()
      guard workspace_in_view(src).0 is Some(w) else { return None }
      // (read once what its shell opens on is declared, each of it followed then: read before, none of it is, and
      // nothing would tell this of what comes to be; a frame after was what told it, till 2026-11-12)
      if @sfbase.opens_declared_now() != Some(w.id) {
        return Some(if answered { None } else { Some(t_reading_workspaces(src)) })
      }
      // (the shell whose function was declared, as it was: a window resized across the breakpoint before it shows
      // declares nothing again (opens_ahead_node), the page it began on waited for as it was)
      let wide = match first_wide.val {
        Some(wide) => wide
        None => {
          let wide = !(@sf.layout(v.window_w()) is Small) || @sf.native_able()
          first_wide.val = Some(wide)
          wide
        }
      }
      let held = @sfbase.read_held_found(src)
      let ask = fn(n : String, p : Map[String, Json]) -> @sfbase.TopicState {
        match held(n, p) {
          Some(st) => st
          None => {
            // (what the first page waits for that its shell's function does not say: followed by nothing, so read
            // as not answered, never told when it is)
            // (one the function comes to say as this change answers what it read, declared in it too (opens_ahead_node):
            // told again then; one still not declared as the change is told whole, a fault: under a Tester it stops
            // the test, on a device it is told as a ui_fault report (src/stillfail/reports.mbt) and the app goes on,
            // the first page waiting for it as not answered till first_page_ms. A read the first page comes to have
            // goes in its shell's function, sfapp's home_opens or sfdesk's frame_opens, never here)
            // (once answered, not a fault: opens_ahead_node and page_opens_node, done with the first page as it was
            // answered, declare nothing more of what it comes to read after (a chat's older messages, one come before
            // it shows, a login card in it); a read the first page waits for and nothing declares leaves it unanswered,
            // told so as ever)
            if !answered {
              let params = p.copy()
              @signals.after_flush(fn() {
                if @sfbase.read_held_found(src)(n, params) is None {
                  @view.fault(
                    "first_page_node (stillfail/src/sfapp/app.mbt): the first page reads \{n} \{Json::object(params).stringify()}, which the shell's function it opens by (sfapp's home_opens, sfdesk's frame_opens) does not say",
                  )
                }
              })
            }
            { value: None, error: None, version: -1, waiting: false }
          }
        }
      }
      // (what it read held on to till the first page shows, answered or not: its readers are built by then, and
      // what was declared and read by this alone, let go of as this stops, would be asked again by them)
      // (in the wide frame a place of the rail's gone to before the first page is shown: the first page is not shown at
      // all, so waited for no more; what that place reads is its own wait, the pane's. Not the page the frame lands on,
      // a chat or a new chat put over Home (sfdesk's land): that is the first page, waited for as ever)
      // (once gone, gone: back to the chats after is no first page shown again)
      if wide &&
        (match first_top.val { Some(p) => p != app.nav.top(); None => false }) &&
        !(app.nav.top() is (Home | Chat(_) | NewChat)) {
        first_left.val = true
      }
      let left = first_left.val
      if left || first_page_ready_by(src, w, wide, ask) || answered {
        Some(None)
      } else {
        Some(Some(t_reading_workspaces(src)))
      }
    },
    fn(said) {
      match said {
        Some(Some(words)) => first_words.set(words)
        // (answered: the core's status no longer read, the words last read kept; none read yet, the words alone)
        Some(None) => {
          first_answered.set(true)
          if first_words.get() == "" {
            first_words.set(tr("android-misc.workspaces.loading"))
          }
        }
        _ => ()
      }
    },
  )
}

///|
/// The splash over the first page while it is built and waits for what it shows (sfbase's first_page_waits, told by
/// the frame as it is: first_hide), in node `v`, over all it holds: splash_of_tree saying first_words, once the app's
/// first splash has waited its second; before it nothing over what the shell's nodes draw, its old views drawn at none
/// (view_in), as the old view's splash was.
fn first_splash_node(v : @view.View) -> Unit {
  v.show(fn() { @sfbase.first_page_waits.get() && splash_waited.get() }, fn(s) {
    s.over(Is(true)) |> ignore
    splash_of_tree(s, fn() { Some(first_words.get()) }, fn() { false })
  })
}

///|
/// When the workspace came into view, the first page's wait begun (-1: not yet): first_page_node's.
// kept across runs: put back as a run begins (new_run)
let first_from : Ref[Double] = Ref(-1.0)

///|
/// The page on top as the first page's wait began (first_page_node), laid out Small: the first page, what its wait
/// waits for (first_page_ready_by), whatever is opened over it meanwhile.
// kept across runs: put back as a run begins (new_run)
let first_top : Ref[Page?] = Ref(None)

///|
/// Whether a place of the rail's was gone to in the wide frame before the first page was shown (first_page_node): its
/// wait over for good.
// kept across runs: put back as a run begins (reset)
let first_left : Ref[Bool] = Ref(false)

///|
/// Whether the shell whose function was declared as the workspace came into view (opens_ahead_node) is the wide frame,
/// as first_page_node first read it so (None: not yet): what the first page waits for is what that shell declared
/// (first_page_ready_by), the window resized across the breakpoint before it shows or not.
// kept across runs: put back as a run begins (new_run)
let first_wide : Ref[Bool?] = Ref(None)

///|
/// Whether the app's first page has shown (first_page_shown).
let first_shown : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
/// Whether this frame's first page is built and not shown yet (signed_in, view_in).
let first_waiting : Ref[Bool] = Ref(false)

///|
/// The chats' lists made once drawn at none while `on` (sfbase's first_page_waits), told only as it changes.
fn first_hide(on : Bool) -> Unit {
  if @signals.untracked(fn() { @sfbase.first_page_waits.get() }) != on {
    @sfbase.first_page_waits.set(on)
  }
}

///|
/// Whether this frame drew the ground alone (splash), and whether the window held (host_setup) is shown (view_in).
let frame_bare : Ref[Bool] = Ref(false)

///|
let window_shown : Ref[Bool] = Ref(false)

///|
/// Whether the core has answered for what the wide frame's pane shows of page `p` (sfdesk's pane_opens, what a
/// workspace switched waits for the page its pane lands on too): a chat; a new chat; an agent's history, a service and
/// a file asked as pages are their chat's with them beside it (sfdesk's service_tab.mbt beside_follow), the chat shown already,
/// what is beside it waited for in its tab; any other page is not waited for.
fn pane_ready(src : Source, p : Page) -> Bool {
  match workspace_in_view(src).0 {
    Some(w) => @sfdesk.pane_opens(src, w.id, p, @sfbase.read_now(src))
    None => true
  }
}

///|
fn wide_reset() -> Unit {
  @sfdesk.side_slide_reset()
  @sfpages.find_forget()
  find_around.val = -1.0
}

///|
/// The system's side of still.fail (before @ui.run). The desktop's window: 1280 by 820 at first, as still.fail's
/// desktop app opens (apps/desktop main.ts), its size not kept (the desktop app keeps none either); at least 360 by
/// 560, a phone's page below the breakpoint; on macOS its title bar the app's (its buttons in its top row, as the
/// desktop app's hiddenInset: the rail's and the sidebar's tops, a phone's page under their band), on Windows the
/// system's. On a phone the app is
/// Android's whatever the phone: on iOS too its lists fling and give at their edges as Android's,
/// its fields take a tap, draw their caret and handles and pick words as Android's (@ui.feel_as). So in a browser
/// started with a finger (a phone's or a tablet's): a browser has no field's ways of its own for a finger, and the
/// desktop's give a finger no way to its menu (粘贴 on a field held, its caret's handle tapped), as a finger has none to
/// right-click.
pub fn host_setup() -> Unit {
  @hostapi.window_setup(360.0, 560.0, 1280.0, 820.0, inset=true)
  // out of sight till it has more than its ground to show (view_in): the first page as it is shown, else the splash
  // once it says that it waits (splash_label_ms), not an empty window for the page's first moments
  @hostapi.window_hold()
  if @ui.platform() == 1 || (@ui.platform() == 4 && @ui.native_pointing() is Finger) {
    @ui.feel_as(2)
  }
}

///|
using @sf {
  dmin,
  dmax,
  dclamp,
}
