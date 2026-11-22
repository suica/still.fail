// Signed in with a workspace in view, laid out Small: the shell as nodes of the window's tree (mbui's view package,
// the way there's 4), made once and changed as the app's state does, the pages and what floats over
// them old views (islands) in it:
//
//   - under all of it, the window's top dragging it and the back of the stack's root a node said as what it reads
//     changes (narrow_takes_back); the keys are the shell node's actions (sfdesk's keys.mbt); what the old frame does
//     before its pages (signed_in_frame: what is told as the frame ends, the icon's number, whether the first page
//     waits) is its own (view_in);
//   - the pages: the stack (app.nav) a node, each page on it a node of its own made as it is put on and let go as it
//     leaves (what it made forgotten), the page in it built while it shows (an island), where it is drawn bound to its
//     slide, which sets out at its cause's moment, once the core has given what the page shows (mbui's nav_view.mbt);
//   - over them, the bottom bar (bar_glass_node, bar_node.mbt) and what is open over the pages, nodes too (the
//     presenters and the loupe over all of it: app_tree's).
//
// Still the old frame's (the way there): which island takes a press where they lie one over another (all of them are
// told of it), the back the islands take (a page's own, a menu's, a sheet's: said by them as they are built, in the
// tree's order; the stack's root's is the node above), the theme (each island built in it).

///|
/// What the signed-in app is laid out as (app_tree): the stack of pages laid out Small, the narrow shell made of the
/// window's tree's nodes; the tape (laid out Medium with a sidebar to show, or beside the system's bars: sfdesk's
/// tape_holds), its panels the window's tree's nodes (tape_shell.mbt); the wide frame off the tape (laid out Large, or
/// with no sidebar to show), its page and its block the tree's nodes (tape_shell.mbt's paned_shell); the landing's nodes
/// (no workspace yet, every account answered: entry_tree.mbt); the splash's nodes while the workspaces are read or fail
/// to be (app.mbt's reading_tree); a window of its own, its page in the tree's frame (app.mbt's lone_tree); or nothing
/// while the window's width is not known yet (the tree made before its first frame).
#derive(Eq)
priv enum ShellIs {
  Stacked
  Taped
  Paned
  Landing
  Reading
  Lone
  Unsized
}

///|
/// Which shell the signed-in app is in for a window `width` wide (app_tree).
fn shell_is(src : Source, width : Double) -> ShellIs {
  if width <= 0.0 {
    return Unsized
  }
  // (a window of its own: its page alone, the window's tree's frame round it: lone_tree; the first window's, as this
  // binding may run while another window's runtime is in place: sfbase's first_lone_page)
  if @sfbase.first_lone_page() is Some(_) {
    return Lone
  }
  // (no workspace yet, every account answered with none: the landing's nodes, entry_tree.mbt)
  if landing_now(src) {
    return Landing
  }
  let wide = !(@sf.layout(width) is Small) || @sf.native_able()
  match workspace_in_view(src).0 {
    Some(_) if !wide => Stacked
    Some(w) if @sfdesk.tape_holds(src, w, width) => Taped
    Some(_) => Paned
    // (none in view yet, the landing not shown: the workspaces still read, or failing to be: the splash's nodes)
    None => Reading
  }
}

///|
/// The narrow shell (above), in node `v`.
fn narrow_shell(v : @view.View, src : Source) -> Unit {
  // (on the window's ground, as the old view whole is (app_state_tree's): what no page covers, a page sliding, shows it)
  v.ground(By(fn() { @sf.theme().p.bg })) |> ignore
  // the window's top dragging it where nothing over it takes the press, as a way in's (entry_tree)
  v.show(fn() { @ui.window_inset_now() }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(b) { b.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore }) |> ignore
  })
  // back at the stack's root while the shell takes it (narrow_takes_back), a node of the window's tree's: before the
  // pages, what they and what is over them say takes back (a page's own stack, a menu, a sheet) taking it first; whose
  // it is said at the cause that changes it (a tab of the bar pressed), done as it is done (sfbase's back_step then)
  v.show(narrow_takes_back, fn(b) {
    b.takes_back(fn() {
      match @sfbase.back_step() {
        Some(f) => f()
        None => ()
      }
    })
    |> ignore
  })
  @ui.nav_view(
    v,
    app.nav,
    fn(_c, _page) {  },
    bg=fn() { @sf.theme().p.bg },
    // a page opened slides in once the core has given what it shows
    ready=fn(page) {
      match workspace_in_view(src).0 {
        Some(w) => page_ready(src, w, page)
        None => true
      }
    },
    most=page_local_ms,
    // (the pages made once as nodes: narrow_made)
    made=fn(page) { narrow_made(src, page) },
    // (a place of the bottom bar switched away from kept, its nodes put by at rest, taken back as it is switched to:
    // go_place's, sfbase's nav_root_kept)
    keeps_made=true,
    // (a chat's page made as nodes left (gone back from, put in place of) kept, its nodes put by at rest, taken back as
    // it is opened again: chat_page_left_key)
    keeps_left=@sfbase.chat_page_left_key,
    transition=@ui.NavTransition::layered(),
    tab_moves_slot=false,
  )
  |> ignore
  // (none kept of another workspace: those put by left for good as the workspace in view changes)
  v.reacts(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(_) { app.nav.shelf_empty() })
  // a station's screen with a page put over it (a chat a notice opened): its page is not built there, so its view is
  // let go of as it is covered, and opened again by its page as it is on top again
  v.reacts(
    fn() {
      let pages = app.nav.pages()
      let screens : Array[(String, String, Bool)] = []
      for i, p in pages {
        match p {
          Screen(at) => screens.push((at.station, at.screen, i < pages.length() - 1))
          _ => ()
        }
      }
      screens
    },
    fn(screens) {
      for k in screens {
        @sfpages.screen_covered(src, k.0, k.1, k.2)
      }
    },
  )
  // what the places of the bar open on asked ahead of them from the moment it shows, held till its page is gone from
  // view under another (the stack at rest: Nav::root_shows), at those moments whatever frames are drawn (sfbase's
  // places_ahead_node)
  @sfbase.places_ahead_node(v, src, fn() {
    match workspace_in_view(src).0 {
      // (its page shows, on top or beside a page sliding over it or off it: held across that slide, let go of as it
      // is over with its page gone from view; another page sliding over one already over it is no cause of the bar's)
      Some(w) if narrow_bar_shown(src, w) || app.nav.root_shows() => Some(w.id)
      _ => None
    }
  })
  // a workspace switched shows once all its Home opens on is answered (home_opens), the screen as it was till then
  // (sfbase's workspace_switch_node)
  @sfbase.workspace_switch_node(v, src, home_opens)
  // what the person's devices waiting on this one put up (signed_in_prompts)
  signed_in_prompts(v, src)
  // the bottom bar told what the app's state and the window say of it as that changes, at the moment of what changed it
  // (a page put on the stack, a place come in, the bars' order, the window's width), whatever frames are drawn: the
  // frames only read where it is then (bar_tell)
  v.reacts(
    fn() {
      match workspace_in_view(src).0 {
        Some(w) => {
          let active = place_of(app.nav.top())
          // (the width of the box it is laid out in, this node's: the window's less the system's bars beside it, as
          // the root's sides say it, told as either changes)
          let (left, right) = sides_room()
          Some(bar_told(src, w, active, narrow_bar_shown(src, w), v.window_w() - left - right))
        }
        None => None
      }
    },
    fn(told) {
      match told {
        Some(t) => bar_tell(t, v.cause_at())
        None => ()
      }
    },
  )
  // ⌘K's search over a page other than the lists (sfdesk's keys.mbt, sfpages' search.mbt), under the bars: on the
  // page's ground, nothing of the page under it seen
  v.show(at_once=true, @sfpages.search_over_on, fn(k) {
    k.over(Is(true)) |> ignore
    @sfpages.search_over_ground_node(k)
    @sfpages.search_page_node(k, src, fn() { workspace_in_view(src).0 }, fn() { status_top_now(k.window_w()) }, Whole)
  })
  // the bottom bar over the pages: its glass, a finger on it the bar's at each event's moment, the bar drawn in it
  // (bar_node.mbt); on a place's top page with nothing over it (narrow_bar_shown); none while this device waits to be
  // confirmed in the workspace's safe mode (its Home is the wait: lock_gate)
  bar_glass_node(v, src, fn() { workspace_in_view(src).0 })
  // ⌘K's panel over the pages (sfdesk's switcher.mbt), over what the old view puts over them
  @sfdesk.switcher_node(v, src)
  // ⌘/'s shortcuts, presented as the shell's keys_open says (sfdesk's shortcuts.mbt)
  @sfdesk.keys_dialog_node(v, src, @sfdesk.wide.keys_open)
  // the chat being shared as a picture, and a visualization over the whole screen, over the bar: nodes of the tree's of
  // their own (sfpages' publish.mbt, sfbase's viz_page.mbt)
  @sfpages.publish_layer_node(v, src)
  viz_full_layer_node(v, src)
  // an image opened over the pages, over the bar: nodes of the tree's of its own (sfbase's viewer_tree.mbt); what is
  // opened otherwise, nodes of their own over them
  // (its stage the box it is laid out in, this node's: the window's less the system's bars beside it, as the root's
  // sides say it, followed)
  @sfbase.viewer_node(v, src, fn() {
    let (w, h) = v.window()
    let (left, right) = sides_room()
    (dmax(0.0, w - left - right), h)
  })
}

///|
/// What the frame does with the app signed in and workspace `w` in view, in every tier, before its frame: what is
/// told as the frame ends, the icon's number, links, updates, what was shared in, whether the first page waits.
fn signed_in_frame(c : @ui.Ctx, src : Source, w : Workspace) -> Unit {
  // The folder and its player both need the same entries. Keep them while moving between the two and when
  // replacing one film with the next, until the new page has its own reader.
  match app.nav.top() {
    Drive(at) => match at.root {
      Some(root) => src.topic("drive", @sfbase.drive_params(at.station, root, at.path)).get() |> ignore
      None => ()
    }
    DrivePlay(at) => {
      let root = at.root.unwrap_or("")
      let folder = @sfbase.dv_parent(at.path)
      src.topic("drive", @sfbase.drive_params(at.station, root, folder)).get() |> ignore
    }
    _ => ()
  }
  // (told once the frame's builds are over, as the last saw the app, the workspace and the page on top)
  c.after_build("attend", fn() { attend(src, w.id, app.nav.top() is NewChat) })
  // (a person's act taken as an old view builds (a row pressed: its change is that build's), done with it: where it
  // left from let go where it went nowhere; where the app is noted as it changes, app_state_tree)
  c.after_build("history", fn() { @sfbase.history_settled() })
  // notifications: shown while the app is, a tapped one's chat opened, the one of a chat on top taken off (once the
  // frame's builds are over: a build let go of follows no workspace)
  c.after_build("notices", fn() { notices_frame(src, w) })
  // the core and the workspace links are opened against, as the frame ends (links.mbt)
  c.after_build("links", fn() { links_frame(src, w) })
  // the number on the app's icon (app_frame.mbt)
  badge_frame(c, src)
  // a link the system opened the app with, told once: what the core says of it shown by the frame after (Ctx::tell)
  // (whether one waits read as a signal: this part, kept as its nodes, built again as one is given)
  if links_wait() {
    c.tell("links-given", fn() { links_given(src) })
  }
  // a newer build of the app asked for once (updates.mbt)
  // (asked once, with the app's version: nothing a build changes)
  update_first(src)
  // and again while it stays open (one never shown again asks no more otherwise)
  update_again(c, src)
  // and as soon as a release may be out
  update_on_release(c, src)
  // what another app shared in (share.mbt)
  share_in_frame(c)
  // files being kept on the device, said once kept (keep.mbt)
  keeps_frame(c)
  // the first page built as it opens, asking for all it shows, and shown once it has it (first_page_ms at most), as a
  // page opening is: under the splash till then (view_in), not its loading look and its list a frame or two later
  first_waiting.val = !first_page_shown(c, src, w)
  first_hide(first_waiting.val)
}

///|
/// Laid out Small, how the lists take the hand: pointed at with a mouse (a desktop's narrow window), the wheel and the
/// trackpad scroll the lists and a drag picks words, as on the wide frame's page; a finger drags the lists and holds to
/// pick (pick.mbt).
fn narrow_lists(c : @ui.Ctx) -> Unit {
  c.mouse_drags_lists(stack_by_finger())
}

///|
/// Whether back at the narrow stack's root is the shell's now (back_where's: a place's top page other than the chats
/// back to the chats): nothing pushed on the stack, no menu, sheet or presenter over it. All it reads is told as it
/// changes (the stack, the presenters).
fn narrow_takes_back() -> Bool {
  app.nav.depth() == 1 && app.nav.top() != Home && !app.menu && !sheet_open() && !@sf.presenting()
}

///|
/// Whether the bottom bar shows: on a place's top page with nothing over it; not while this device waits to be
/// confirmed in the workspace's safe mode (its Home is the wait: lock_gate).
fn narrow_bar_shown(src : Source, w : Workspace) -> Bool {
  let root = app.nav.top()
  let waiting = root == Home && @settings.lock_waiting(settings_core(src, w), w.id)
  app.nav.depth() == 1 && place_of(root) is Some(_) && !@sfpages.search_bar_away() && !waiting
}

///|
/// What the devices of the person's waiting on this one put up over whichever page is open, with a workspace in view, in
/// every shell signed in (node `v`'s, done as what it reads changes, at its cause's moment): a new device waiting on
/// this one's code (settings' lock_prompts), then one waiting for a vault's key (settings' vault_prompts), in any
/// workspace of the person's (the core's `lockPrompts`), each put up when no other sheet is.
fn signed_in_prompts(v : @view.View, src : Source) -> Unit {
  v.reacts(
    fn() {
      match workspace_in_view(src).0 {
        Some(w) => {
          let core = settings_core(src, w)
          // (free: no sheet of the app's up, nothing presented)
          Some((w.id, (core.topic)("lockPrompts", Map([])).get().value, !sheet_open(), !@sf.presenting()))
        }
        None => None
      }
    },
    fn(said) {
      // (while a new device's code is shown here to be read off this one, the screen stays on: gone dark as the person
      // types it there, this device could not ask them as the code comes back, not in front)
      let pairing = match said {
        Some((_, prompts, _, _)) => !@settings.items(prompts, "pairing").is_empty()
        None => false
      }
      @sfbase.keep_awake_by("lock-pair", pairing)
      match (said, workspace_in_view(src).0) {
        (Some((_, _, free, _)), Some(w)) => {
          let core = settings_core(src, w)
          @settings.lock_prompts(core, free)
          // (none put up while the one before put one up: each asks whether anything is presented)
          @settings.vault_prompts(core, free)
        }
        _ => ()
      }
    },
  )
}

///|
/// What the Small stack gives a new chat made as nodes in node `v` (sfpages' new_chat_node): its bar (取消
/// back to where it was opened from, 新对话 in the middle) under the status bar as the window it is in is now, the
/// navigation bar's room under it; the chat it becomes opens in its place.
/// `width`: the window's, which the page is as wide as.
fn new_frame_node(src : Source, w : Workspace, width : () -> Double) -> @sfpages.NewChatNodeFrame {
  {
    core: settings_core(src, w),
    ground: fn(_) { @sf.theme().p.bg },
    width,
    apart: fn() { false },
    pane: fn() { None },
    bar: fn(b) {
      @sf.nav_bar_node(b, fn() { tr("common.cancel") }, fn() { tr("android-chat.new.title") }, fn() {
        @sfbase.close_page(NewChat) |> ignore
      }, top=fn() { status_top_now(b.window_w()) })
    },
    foot: fn() { nav_foot() },
    over: fn(_, _) {  },
    in_place: true,
    sent: fn(_) {  },
  }
}

///|
/// The pages of the stack made once as nodes of the tree's in the narrow shell (nav_view's `made`), by their kind, the
/// rest old views (narrow_page_held): the settings' list (the gear's), 关于, 记忆, 一台 station 的记忆 and 归档, an agent's history;
/// a chat (and the new chat that becomes it), its old view in it as yet (chat_page_made). Each in the workspace in view, made
/// again as that changes; its frame what the shell gives a page (back to the one under it, under the status bar, over
/// the navigation bar: setting_page's) as that changes; under the status bar the page's ground over it, and a window's
/// band its buttons are in dragging it, as page_view puts them over a page that has no top of its own.
fn narrow_made(src : Source, page : Page) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  match page {
    // (a place of the bottom bar's whose page is one of those: that page under the place's top bar, place_page's, made
    // under its own kind)
    Place("remote") => narrow_made_as(src, Place("remote"), true)
    Place(name) =>
      match @settings.route_of(name) {
        // (those whose old view is gone: every frame makes them once, as a page or a place)
        Some(r) if @settings.made_once(r) =>
          narrow_made_as(src, Setting(r), true).map(fn(m) { ("place/" + m.0, m.1) })
        _ => None
      }
    // (文件 at the root of the stack: the bottom bar's place, including while swapping out or shelved)
    Files if @signals.untracked(fn() { app.nav.is_root_place(Files) }) => narrow_made_as(src, page, true)
    _ => narrow_made_as(src, page, false)
  }
}

///|
/// narrow_made's page `page`, made as a place of the bottom bar's (`place`: named as the stack's entry is now, whichever
/// of its names it is) or as a page of the stack.
fn narrow_made_as(
  src : Source,
  page : Page,
  place : Bool,
) -> (String, (@view.View, () -> Page, Page?, () -> Int, Int) -> Unit)? {
  let made_at = fn(
    kind : String,
    place : Bool,
    f : (
      @view.View,
      @settings.Core,
      () -> @settings.Here,
      () -> PageFrame,
      () -> Int,
      ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
      Int,
    ) -> Unit,
  ) {
    Some(
      (
        kind,
        fn(outer : @view.View, page : () -> Page, under : Page?, stint : () -> Int, serial : Int) {
          // (a place switched to on the bar: only its content body slides/fades via Nav::tab_body_motion;
          // its top bar stays mounted on `outer` so the glass and settings gear stay steady at Δx = 0)
          let v = match place {
            true if under is None => {
              let mut inner : @view.View? = None
              outer.box(fn(i) {
                i.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
                tab_body_comes_in(i, serial)
                bar_built_node(i, page)
                inner = Some(i)
              })
              |> ignore
              inner.unwrap()
            }
            _ => outer
          }
          // (what the page does, given its place's top bar as it is made: each making of it its own, let go with it
          // where none since gave another)
          let page_actions : @signals.Signal[((@view.View) -> Unit, Int)?] = @signals.signal_by(None, same=fn(a, b) {
            match (a, b) {
              (None, None) => true
              (Some(x), Some(y)) => x.1 == y.1
              _ => false
            }
          })
          let frame = fn() -> PageFrame {
            // (under the status bar as the window it is in is now: status_top_now, by its width as it changes; a place
            // of the bottom bar's under the top bar, which names it, over the bottom bar: place_page's)
            if place {
              let width = v.window_w()
              { back: None, top: status_top_now(width) + bar_h + 8.0, foot: nav_foot() + bar_room_at(width), named: true }
            } else {
              { back: under.map(@sfbase.back_label), top: status_top_now(v.window_w()), foot: nav_foot(), named: false }
            }
          }
          v.pick(fn() { workspace_in_view(src).0.map(fn(w) { w.id }) }, fn(p, _id) {
            let last_gen = Ref(0)
            let acts = fn(make : (@view.View) -> Unit, _side : (@sf.Look) -> Double) {
              let gen = next_place_actions_gen()
              last_gen.val = gen
              page_actions.set(Some((make, gen)))
            }
            p.owns(fn() {
              if last_gen.val > 0 && page_actions.untracked() is Some((_, g)) && g == last_gen.val {
                page_actions.set(None)
              }
            })
            |> ignore
            match @signals.untracked(fn() { workspace_in_view(src).0 }) {
              Some(w) => {
                let core = settings_core(src, w)
                let here = fn() { @settings.here_of(core, w.id, w.name) }
                @settings.frame(core, @signals.untracked(here))
                // (a dialog a fixture's mode puts up over its page, before the page is made: setting_page's)
                @sfdesk.settings_fixture(src, core)
                // (its words in pieces picked with the mouse, as an old view's page's in this frame are (narrow_page's
                // c.selectable), before what it holds is made)
                @ui.words_picked(p)
                f(p, core, here, frame, stint, acts, serial)
              }
              None => ()
            }
          })
          // Home and a place draw their own top bar under the status bar.
          narrow_made_top(outer, has_top=place || kind == "home")
          // (a place of the bottom bar's: its top bar mounted on `outer` so push/pop slides it with the page,
          // while root tab switches keep the glass & settings gear stationary and cross-fade only title/actions)
          if place {
            outer.box(fn(o) {
              o
              .over(Is(true))
              .alpha(By(fn() { if app.nav.is_swapping_out(serial) { 0.0 } else { 1.0 } }))
              |> ignore
              place_top_bar_node(
                o,
                fn() {
                  match page() {
                    Place(n) => n
                    Files => "files"
                    _ => ""
                  }
                },
                fn() { page_actions.get() },
                title_alpha=fn(n) { app.nav.tab_title_alpha(serial, fn() { app.nav.tab_moment(n) }) },
              )
              |> ignore
            })
            |> ignore
          }
        },
      ),
    )
  }
  let made = fn(
    kind : String,
    f : (
      @view.View,
      @settings.Core,
      () -> @settings.Here,
      () -> PageFrame,
      () -> Int,
      ((@view.View) -> Unit, (@sf.Look) -> Double) -> Unit,
    ) -> Unit,
  ) {
    made_at(kind, place, fn(p, core, here, frame, stint, acts, _serial) { f(p, core, here, frame, stint, acts) })
  }
  match page {
    // (a chat, and the new chat that becomes one in place: the same page, a node of the tree's)
    page if @sfbase.chat_page_is(page) && !place =>
      Some(
        (
          @sfbase.chat_page_kind(),
          fn(v, _page, _under, stint, k) {
            @sfbase.chat_page_made(
              v,
              src,
              k,
              // (its bar the page's node's: chat_bar_node)
              over=chat_bar_node,
              stint~,
              // (its messages nodes, its composer made as nodes in their list's foot)
              body=fn(col, s, r, composer, shows, on_stack) {
                if @sf.native_input() is Mouse {
                  @sfdesk.context_node(col)
                }
                @sfpages.chat_page_body_node(
                  col,
                  s,
                  r,
                  // (its tips and hover cards over the page, in its node: an agent's card over its picture)
                  tips=@sf.TipLayer::new(fn() { Some(v) }),
                  stint~,
                  shows~,
                  on_stack~,
                  cover=fn() { bar_foot_live(col, r) },
                  // (and what it comes to, its second row measured or pressed open: where the list was put, under it)
                  cover_to=fn() { bar_foot_coming(col, r) },
                  room=list_room,
                  foot=list_foot,
                  foot_clear_extra=fn() { if @ui.system_tabletop() is Some(_) { 0.0 } else { 34.0 } },
                  composer~,
                  lead=unread_lead(),
                )
              },
              foot_node=fn(n, s, r, shows, _) { chat_foot_node(n, s, r, shows, @sf.TipLayer::new(fn() { Some(v) }), stint) },
              // (the new chat it is till it becomes one, made as nodes: sfpages' new_chat_node, under its bar of 取消)
              new_node=fn(n, s) {
                match @signals.untracked(fn() { workspace_in_view(s).0 }) {
                  Some(w) => @sfpages.new_chat_node(n, s, w, new_frame_node(s, w, fn() { n.window_w() }), @sf.TipLayer::new(fn() { Some(v) }))
                  None => ()
                }
              },
            )
            |> ignore
          },
        ),
      )
    // the chats' lists under Home's top bar (home_node); a device waiting to be confirmed in the workspace's safe mode
    // sees that instead (lock_gate_node)
    Home =>
      made_at("home", place, fn(p, core, _here, _frame, stint, _acts, serial) {
        let tips = @sf.TipLayer::new(fn() { None })
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        bar_built_node(p, fn() { Home })
        p.pick(fn() { workspace_in_view(src).0.map(fn(w) { @settings.lock_waiting(core, w.id) }).unwrap_or(false) }, fn(
          q,
          waiting,
        ) {
          // (all of the page's room, the lock's page and Home alike)
          q.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          if waiting {
            lock_gate_node(q, src, core)
          } else {
            home_node(q, src, tips, stint, serial~, shown=fn() { app.nav.shows(serial) })
          }
        })
      })
    Settings | Setting(Home) =>
      made("settings", fn(p, core, here, frame, stint, _acts) {
        @sfpages.settings_home_node(p, core, here, fn(r) { (core.push)(r) }, on_back=core.pop, frame~, stint~, bars=fn() {
          @sf.layout(p.window_w()) is Small
        })
      })
    Setting(About) => made("about", fn(p, core, _here, frame, _stint, _acts) { @sfpages.about_node(p, core, on_back=core.pop, frame~) })
    Setting(Changelog) =>
      made("changelog", fn(p, core, _here, frame, _stint, _acts) { @sfpages.changelog_node(p, core, on_back=core.pop, frame~) })
    // (已归档 laid out Small: its page, the settings' 已归档)
    Archived | Setting(Archive) =>
      made("archive", fn(p, core, here, frame, _stint, _acts) { @sfpages.archive_node(p, core, here, on_back=core.pop, frame~) })
    Setting(Archiving) =>
      made("archiving", fn(p, core, here, frame, stint, _acts) {
        @sfpages.archiving_node(p, core, here, on_back=core.pop, frame~, stint~)
      })
    Setting(StationArchiving(st)) =>
      made("station-archiving/" + st, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.station_archiving_node(p, core, here, st, on_back=core.pop, frame~)
      })
    Setting(StationMove(st)) =>
      made("station-move/" + st, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.station_move_node(p, core, here, st, on_back=core.pop, frame~)
      })
    Setting(AutoDecisions) =>
      made("auto-decisions", fn(p, core, here, frame, _stint, _acts) {
        @sfpages.decisions_node(p, core, here, on_back=core.pop, frame~)
      })
    Setting(AutoCompletion) =>
      // (what it does in its place's top bar as a place; at its head as a page of the stack)
      made("auto-completion", fn(p, core, here, frame, _stint, acts) {
        @sfpages.completion_node(p, core, here, on_back=core.pop, frame~, bar_actions?=if place { Some(acts) } else { None })
      })
    Setting(Usage) =>
      // (what it does in its place's top bar as a place; at its head as a page of the stack)
      made("usage", fn(p, core, here, frame, _stint, acts) {
        @sfpages.usage_node(p, core, src, here, on_back=core.pop, frame~, bar_actions?=if place { Some(acts) } else { None })
      })
    Setting(Shortcuts) =>
      // (recording while it is the one on top of the stack: its stay there, stint's)
      made("shortcuts", fn(p, core, _here, frame, stint, _acts) {
        @sfpages.shortcuts_node(p, core, on_back=core.pop, frame~, active=fn() { app.nav.top_stay().1 == stint() })
      })
    Setting(Notifications) =>
      made("notifications", fn(p, core, here, frame, stint, _acts) {
        @sfpages.notify_node(p, core, here, on_back=core.pop, frame~, stint~)
      })
    Setting(MemoryDoc(address, skill, at)) =>
      made("memory-doc/" + address + "/" + skill + "/" + at.to_string(), fn(p, core, here, frame, _stint, _acts) {
        @sfpages.memory_doc_node(p, core, here, address, skill, at, on_back=core.pop, frame~)
      })
    Setting(AutoPolicy(st)) =>
      made("auto-policy/" + st, fn(p, core, here, frame, _stint, _acts) { @sfpages.policy_node(p, core, here, st, on_back=core.pop, frame~) })
    Setting(Appearance) =>
      made("appearance", fn(p, core, _here, frame, _stint, _acts) { @sfpages.appearance_node(p, core, on_back=core.pop, frame~) })
    Setting(Experimental) =>
      made("experimental", fn(p, core, _here, frame, _stint, _acts) { @sfpages.experimental_node(p, core, on_back=core.pop, frame~) })
    Setting(LocalStation) =>
      made("local-station", fn(p, core, _here, frame, _stint, _acts) { @sfpages.local_station_node(p, core, on_back=core.pop, frame~) })
    Setting(Permissions) =>
      made("permissions", fn(p, core, _here, frame, _stint, _acts) { @sfpages.permissions_node(p, core, on_back=core.pop, frame~) })
    Setting(Me) =>
      made("me", fn(p, core, here, frame, stint, _acts) { @sfpages.me_node(p, core, here, on_back=core.pop, frame~, stint~) })
    Setting(Fonts) => made("fonts", fn(p, core, _here, frame, _stint, _acts) { @sfpages.fonts_node(p, core, on_back=core.pop, frame~) })
    Setting(BarSettings) =>
      made("bars", fn(p, core, _here, frame, _stint, _acts) { @sfpages.bars_node(p, core, on_back=core.pop, frame~) })
    Setting(Security) =>
      made("security", fn(p, core, here, frame, stint, _acts) { @sfpages.security_node(p, core, here, on_back=core.pop, frame~, stint~) })
    Setting(SecurityOpen) =>
      made("security-open", fn(p, core, here, frame, _stint, _acts) {
        @sfpages.security_open_node(p, core, here, on_back=core.pop, frame~)
      })
    Setting(Workspace) =>
      made("workspace", fn(p, core, here, frame, stint, _acts) { @sfpages.workspace_node(p, core, here, on_back=core.pop, frame~, stint~) })
    Setting(VaultItems) =>
      made("vault-items", fn(p, core, here, frame, _stint, _acts) { @sfpages.vault_items_node(p, core, here, on_back=core.pop, frame~) })
    Setting(KeptFiles) => made("kept", fn(p, core, _here, frame, _stint, _acts) { @settings.kept_node(p, core, on_back=core.pop, frame~) })
    // (by its station and thread: another chat's another page)
    Setting(KeptChat(station, thread)) =>
      made("kept/" + station + "/" + thread.to_string(), fn(p, core, _here, frame, _stint, _acts) {
        @settings.kept_chat_node(p, core, station, thread, on_back=core.pop, frame~)
      })
    // (by the station whose step is said first: another station's another page)
    Setting(AdbShare(focus)) =>
      made("adb/" + focus, fn(p, core, here, frame, _stint, _acts) {
        @settings.adb_node(p, core, focus, on_back=core.pop, frame~, sub=fn() { here().sub })
      })
    Setting(Vault) => made("vault", fn(p, core, here, frame, _stint, _acts) { @sfpages.vault_node(p, core, here, on_back=core.pop, frame~) })
    // (by its vault and item: another's another page)
    Setting(VaultItem(vault, item)) =>
      made("vault-item/" + vault + "/" + item, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.vault_item_node(p, core, here, vault, item, on_back=core.pop, frame~)
      })
    // (by its station: another station's another page; as a place of the bottom bar's, its ＋ the bar's notch:
    // connects_add)
    Setting(Connects(only)) =>
      made("connects/" + only, fn(p, core, here, frame, stint, _acts) {
        @sfpages.connects_node(p, src, core, here, only, on_back=core.pop, frame~, stint~)
      })
    Setting(Connect(station, id)) =>
      made("connect/" + station + "/" + id, fn(p, core, here, frame, stint, _acts) {
        @sfpages.connect_node(p, src, core, here, station, id, on_back=core.pop, frame~, stint~)
      })
    // 文件: its places (files_narrow.mbt); at the root of the stack a place of the bottom bar's (narrow_made)
    Files =>
      made_at(if place { "place/files" } else { "files" }, place, fn(p, _core, _here, frame, _stint, _acts, serial) {
        guard workspace_in_view(src).0 is Some(w) else { return }
        files_narrow_node(p, src, w.id, place, frame, shown=fn() { app.nav.shows(serial) })
      })
    // a page of a station's drive (by its folder: another folder another page), laid out by its width (sfpages'
    // drive_page_node), a folder gone into a page over it (or back to it where it is in the stack)
    Drive(at) =>
      made_at("drive/" + at.station + "/" + at.root.unwrap_or("") + "/" + at.path, false, fn(p, _core, _here, frame, _stint, _acts, serial) {
        guard workspace_in_view(src).0 is Some(w) else { return }
        let under = app.nav.under()
        @sfpages.drive_page_node(
          p,
          src,
          w.id,
          fn() { at },
          frame=fn() { { ..frame(), back: under.map(fn(u) { drive_back_label(src, w, u) }) } },
          width=fn() { p.window_w() },
          on_back=fn() { @sfbase.go_back() |> ignore },
          go=drive_go_back_to,
          shown=fn() { app.nav.shows(serial) },
        )
      })
    // a drive's text read: the whole window, the reader's own bars over it (sfpages' reader_page_node)
    DriveRead(at) =>
      made("drive-read/" + at.station + "/" + at.root.unwrap_or("") + "/" + at.path, fn(p, _core, _here, _frame, _stint, _acts) {
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        @sfpages.reader_page_node(p, src, at)
      })
    // a web service an agent started, a visualization it posted: their page, its bar under the status bar
    // (sfpages' service_page_node, preview_file_page_node)
    Service(station, job) =>
      made("service/" + station + "/" + job, fn(p, core, _here, frame, _stint, _acts) {
        @sfpages.service_page_node(p, src, station, job, core.pop, fn() { frame().top }, fn() { frame().foot })
      })
    PreviewFile(station, key, path, name) =>
      made("preview-file/" + station + "/" + key + "/" + path, fn(p, core, _here, frame, _stint, _acts) {
        @sfpages.preview_file_page_node(p, src, station, key, path, name, core.pop, fn() { frame().top }, fn() {
          frame().foot
        })
      })
    // a drive's video or song played: the whole window, the player's own bars over it (sfpages' play_page_node)
    DrivePlay(at) =>
      made("drive-play/" + at.station + "/" + at.root.unwrap_or("") + "/" + at.path, fn(p, _core, _here, _frame, _stint, _acts) {
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        @sfpages.play_page_node(p, src, at)
      })
    // a station's terminal: the whole window, its bar under the status bar (terminal_node)
    Terminal(at) =>
      made("terminal/" + at.station + "/" + at.terminal, fn(p, core, _here, frame, _stint, _acts) {
        @sfpages.terminal_pane_node(
          p,
          src,
          at,
          back=fn() { frame().back.unwrap_or(@sf.t("common.back")) },
          on_back=core.pop,
          top=fn() { frame().top },
          on_switch_page=fn(next) { app.nav.replace(next) },
        )
      })
    Place("remote") =>
      made("place/remote", fn(p, _core, here, frame, stint, _acts) {
        @sfpages.remote_page_node(p, src, fn() { here().workspace }, frame~, stint~)
      })
    // (by its station: another station's another page, not this one become it)
    Setting(Station(address)) =>
      made("station/" + address, fn(p, core, here, frame, stint, _acts) {
        @sfpages.station_node(p, core, src, here, address, on_back=core.pop, frame~, stint~)
      })
    Setting(UsagePrices(days)) =>
      made("usage-prices/" + days.to_string(), fn(p, core, here, frame, _stint, _acts) {
        @sfpages.usage_prices_node(p, core, here, days, on_back=core.pop, frame~)
      })
    Setting(Memories) =>
      made("memories", fn(p, core, here, frame, _stint, _acts) { @sfpages.memories_node(p, core, here, on_back=core.pop, frame~) })
    Setting(Memory(address)) =>
      made("memory/" + address, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.memory_node(p, core, here, address, on_back=core.pop, frame~)
      })
    // an agent's history (history_node), made again for another agent's
    // (its old parts built as the stack builds its page's: Nav::page_island, by the page's serial)
    History(r, key, entry) =>
      made_at("history/" + r.station + "/" + key, place, fn(p, _core, _here, frame, _stint, _acts, serial) {
        history_node(p, src, r, key, entry, frame, serial)
      })
    // a chat's Farview tab, drawn here (sfpages' farview_tab_node): the bar back, the tab's name, the tab; while
    // 实验性功能's Farview 原生标签页渲染 is on (read as the stack asks what kind each page is: turned off, the page is
    // made again in its place as any screen's, its old view)
    Screen(at) if @sfpages.farview_native_screen(at.screen) =>
      made("farview/" + at.station + "/" + at.screen, fn(p, _core, _here, frame, _stint, _acts) {
        p.grow(Is(1.0)).min_height(Is(Some(0.0))).padding(By(fn() { (0.0, 0.0, 0.0, frame().foot) })) |> ignore
        @sf.nav_bar_node(
          p,
          fn() { frame().back.unwrap_or(tr("common.back")) },
          fn() { if at.title != "" { at.title } else { @sf.t("core-views.screen.kind.browser") } },
          fn() { @sfbase.go_back() |> ignore },
          top=fn() { frame().top },
        )
        @sfpages.farview_pane_node(
          p,
          src,
          at.station,
          at.screen,
          title=at.title,
          on_switch=fn(next) { app.nav.replace(next) },
          on_close=fn() { @sfbase.go_back() |> ignore },
        )
      })
    // a station's screen (sfpages' screen_node): its bar, its picture and what drives it its own, inside the room the
    // stack's frame keeps over and under it (but in 全屏); let go as the page leaves (app.mbt's page_left: screen_left),
    // its view paused while a page is over it (screen_covered, above)
    Screen(at) =>
      made("screen/" + at.station + "/" + at.screen, fn(p, _core, _here, frame, _stint, _acts) {
        p.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        @sfpages.screen_node(p, src, at, frame)
      })
    // the stations' list, the profiles' (by station: another station's another page) and an account's on several
    // stations (sfpages' stations_list.mbt, profiles_list.mbt); as a place of the bottom bar's, their ＋ the bar's notch
    Setting(Stations) =>
      made_at("stations", place, fn(p, core, here, frame, _stint, _acts, serial) {
        @sfpages.stations_list_node(p, core, here, on_back=core.pop, frame~, shown=fn() { app.nav.shows(serial) })
      })
    // (the workspace's: its list or 概览, one page; as a place of the bottom bar's, its own 概览 and its ＋ the bar's
    // notch, none in its top bar, where its share stands by the settings: 2026-11-17 用户「放齿轮旁边」)
    Setting(Profiles("")) =>
      made("profiles/", fn(p, core, here, frame, _stint, acts) {
        let overview = if place { @settings.profiles_place_overview } else { @settings.profiles_narrow_overview }
        @sfpages.profiles_page_node(
          p,
          src,
          core,
          here,
          overview,
          on_back=core.pop,
          frame~,
          bar_actions?=if place { Some(acts) } else { None },
          bar_add=false,
        )
      })
    Setting(Profiles(only)) =>
      made("profiles/" + only, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.profiles_list_node(p, core, here, only, on_back=core.pop, frame~)
      })
    Setting(ProfileAccount(key)) =>
      made("profile-account/" + key, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.profile_account_node(p, core, here, key, on_back=core.pop, frame~)
      })
    Setting(Profile(address, id)) =>
      made("profile/" + address + "/" + id, fn(p, core, here, frame, stint, _acts) {
        @sfpages.profile_node(p, core, here, address, id, on_back=core.pop, frame~, stint~)
      })
    Setting(NewProfile(address)) =>
      made("new-profile/" + address, fn(p, core, here, frame, _stint, _acts) {
        @sfpages.new_profile_node(p, core, src, here, address, on_back=core.pop, frame~)
      })
    _ => None
  }
}

///|
/// A root page body driven by `Nav::replace_tab` dual-ended motion: slides and cross-fades cleanly without
/// moving the decoupled top bar glass or right-side settings gear.
fn tab_body_comes_in(v : @view.View, serial : Int) -> Unit {
  v
  .moved_by(
    fn(_, _, t) {
      let (dx, _) = app.nav.tab_body_motion(serial, fn() { t }, slide=22.0)
      (dx, 0.0)
    },
    fn(_, _) { app.nav.tab_ends_at() },
  )
  .alpha(By(fn() { app.nav.tab_body_motion(serial, fn() { app.nav.tab_moment(v) }, slide=22.0).1 }))
  .carries_until(fn() { app.nav.tab_ends_at() })
  |> ignore
}

///|
/// Over a page made once: its ground under the status bar if it has no top of its own, and the band a window's buttons
/// are in dragging it where it has them (page_view's, an old view's).
fn narrow_made_top(v : @view.View, has_top~ : Bool) -> Unit {
  if !has_top {
    v.box(fn(o) {
      o.over(Is(true)) |> ignore
      o.show(fn() { status_top_now(v.window_w()) > 0.0 }, fn(paper) {
        paper.height(By(fn() { Some(status_top_now(v.window_w())) })).ground(By(fn() { @sf.theme().p.bg })) |> @sf.ground_node |> ignore
      })
    })
    |> ignore
  }
  v.box(fn(o) {
    o.over(Is(true)) |> ignore
    // (where the frame is not wide: is_wide, by the window as it is)
    o.show(fn() { @ui.window_inset_now() && @sf.layout(v.window_w()) is Small && !@sf.native_able() }, fn(band) {
      band.height(By(fn() { Some(window_band_now()) })).moves_window(Is(true)) |> ignore
    })
  })
  |> ignore
}

///|
/// A place's top bar as nodes, over a page made once at a place of the bottom bar's (place_top_bar's): on the bar's
/// glass, under the status bar, 16 in, 10 apart, as high as a top bar at least; the place's name (the page's entry as it
/// is now, `place`), what its page does at its end where it gave the bar any (`actions`: made again as the page that
/// gave them is, laid out narrow at a head's end: head_end's), settings at the right edge (as at Home's).
fn place_top_bar_node(
  v : @view.View,
  place : () -> String,
  actions : () -> ((@view.View) -> Unit, Int)?,
  title_alpha? : (@view.View) -> Double = fn(_) { 1.0 },
) -> Unit {
  // (over the page, as place_page draws it: nothing of it cut but its name)
  place_top_bar_glass(v, place, actions, title_alpha~)
}

///|
/// Progressive blur soft scroll-edge backdrop for floating-pill narrow top bars (iOS 26 UIScrollEdgeEffect.soft):
/// blurs and veils scrolled content progressively over the lower `fade_h` pt down to `base_h`, degrading to a
/// solid `p.bg` alpha fade under `MBUI_GLASS=solid`.
fn narrow_bar_scrim_node(
  parent : @view.View,
  base_h : (@view.View) -> Double,
  fade_h : (@view.View) -> Double,
) -> Unit {
  @sf.top_scroll_edge_node(
    parent,
    base_h,
    fade_h,
    bg=fn() { @sf.theme().p.bg },
    shield=true,
  )
  |> ignore
}

///|
/// place_top_bar_node's bar in `v`: soft bottom-fade scrim behind the title (no full-width `glass_bar()` to avoid
/// glass-on-glass) with the right-side settings action inside a floating liquid glass circle.
fn place_top_bar_glass(
  v : @view.View,
  place : () -> String,
  actions : () -> ((@view.View) -> Unit, Int)?,
  title_alpha? : (@view.View) -> Double = fn(_) { 1.0 },
) -> Unit {
  v.box(fn(g) {
    narrow_bar_scrim_node(
      g,
      fn(s) { top_bar_h_at(s.window_w()) + 16.0 },
      fn(s) { top_bar_h_at(s.window_w()) + 16.0 },
    )
    g.box(fn(row) {
      row
      .row(Is(true))
      .padding(By(fn() { (16.0, status_top_now(row.window_w()), 12.0, 0.0) }))
      .min_height(By(fn() { Some(top_bar_h_at(row.window_w())) }))
      .gap(Is(8.0))
      .lines_up(Is(Some(Middle)))
      |> ignore
      // (its words whole: what the page does at its end gives way where the bar has not the room)
      row.box(fn(t) {
        t
        .grow(Is(1.0))
        .basis(Is(Some(0.0)))
        .keeps_held(Is(true))
        .fits(Is(true))
        .height(Is(Some(34.0)))
        .row(Is(true))
        .lines_up(Is(Some(Middle)))
        .alpha(By(fn() { title_alpha(t) }))
        |> ignore
        @sf.top_bar_title_node(t, fn() { place_label(place()) }) |> ignore
      })
      |> ignore
      row.show(fn() { actions() is Some(_) }, fn(a) {
        a.row(Is(true)).shrink(Is(1.0)).alpha(By(fn() { title_alpha(a) })) |> ignore
        a.pick(
          fn() {
            match actions() {
              Some((_, g)) => g
              None => 0
            }
          },
          fn(k, _) {
            @sf.top_bar_actions_lent(k)
            k.row(Is(true)).gap(Is(8.0)).lines_up(Is(Some(Middle))).shrink(Is(1.0)) |> ignore
            match @signals.untracked(actions) {
              Some((make, _)) => make(k)
              None => ()
            }
          },
        )
      })
      // settings at the right edge, as at Home's: standalone 40pt liquid glass circle
      @sf.bar_pill_group_node(row, height=40.0, pad=3.0, gap=0.0, fn(set_pill) {
        @sf.round_key_node(set_pill, "settings", fn() { tr("android-chat.home.settings") }, fn() {
          @sfbase.history_push()
          app.nav.push(Settings)
        })
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// The makings of pages that give a place's top bar what they do, numbered.
// kept across runs: a count
let place_actions_made : Ref[Int] = Ref(0)

///|
fn next_place_actions_gen() -> Int {
  place_actions_made.val += 1
  place_actions_made.val
}
