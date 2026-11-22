// ⌘K: a panel high on the window over a scrim, the
// search on top (搜索全部内容和操作), under it what a few words find in the workspace (the core's `search`, 
// its chats, the messages that have them, what every station finds besides, each kind under its heading, a few of each;
// 查看更多 that kind alone, 全部结果 or Esc back to all) and what can be done here by its name (the core's
// `commands.find` of what the frame offers now). With nothing typed, the latest chats, then what can be done. ↑ / ↓
// choose, Enter or a press opens; Esc (in one kind's list: back to all of them) or a press outside closes it.

///|
/// Whether ⌘K is open (what it shows and finds is sfpages' finder: switcher.mbt), a signal: what draws it built again as
/// it opens or closes, wherever that was.
// kept across runs: put back by switcher_reset (reset)
let switching : @signals.Signal[Bool] = @signals.signal(false, same=fn(a, b) { a == b })

///|
fn switcher_reset() -> Unit {
  switching.set(false)
}

///|
/// What one opening of it leaves behind, put back as it closes.
fn switcher_closed() -> Unit {
  @sfpages.finder_cleared()
}

///|
/// Whether ⌘K is open.
pub fn switcher_open() -> Bool {
  switching.get()
}

///|
/// ⌘K pressed (the keymap's chat.switch): open, empty; open already, closed, the keyboard let go (`blur`).
pub fn switcher_toggle(blur : () -> Unit) -> Unit {
  // (what it was, as the key is taken: not followed by what takes it)
  let was = switching.untracked()
  if was {
    blur()
  }
  switching.set(!was)
  switcher_closed()
}

///|
/// Esc: words typed cleared first; in one kind's list, back to all of them; else closed (its field let go: the keyboard goes nowhere until another
/// is pressed: `blur`). Whether it took it (open).
pub fn switcher_escape(blur : () -> Unit) -> Bool {
  if !switching.untracked() {
    return false
  }
  if !@sfpages.finder_escape() {
    switching.set(false)
    switcher_closed()
    blur()
  }
  true
}

///|
/// Opened with `words` typed (a made-up run's start).
pub fn switcher_open_with(words : String) -> Unit {
  switching.set(true)
  @sfpages.finder_start(words)
}

///|
/// How ⌘K's panel comes (140 ms on the ease-out), grown out of 97% and faded in, its ground first.
// kept across runs: a value (no field of it changes)
let switcher_in : @motion.Trans = @motion.trans(fade=0.0, scale=0.97, oy=0.0, spec=@motion.tween(@motion.pop_ms, ease=Out), ground_first=true)

///|
/// How its scrim comes: over 120 ms (tip_in's).
let switcher_ground_ms : Double = 120.0

///|
/// ⌘K over the page (ChatSwitcher), as nodes of the window's tree over a shell's (narrow_shell's, the wide frames'), in
/// `v`: while open, a modal layer over a scrim (@sf.over_panel_node: Escape, back or a press outside close it, Escape
/// in one kind's list back to all of them first and words typed cleared before that, finder_escape), the panel 14% down
/// the window in its middle, 560 wide at most (32 short of the window), 480 high at most (72% of the window); its
/// search (the keys in it as it opens), then sfpages' list of what is found and what can be done (finder_list_node), the
/// latest chats with nothing typed. Its scrim faded in over 120 ms, the panel grown out of 97% and faded in over 140 ms;
/// it goes at once.
pub fn switcher_node(v : @view.View, src : Source) -> Unit {
  let workspace = fn() { @sfbase.workspace_in_view(src).0 }
  let close = fn() {
    switching.set(false)
    switcher_closed()
  }
  @sf.over_panel_node(
    v,
    fn() { switching.get() && workspace() is Some(_) },
    close,
    within=fn() { @sfpages.finder_escape() },
    // (back closes it, whatever is typed or looked at alone)
    back_within=fn() { false },
    top_share=switcher_top_share,
    come=switcher_in,
    come_ms=@motion.pop_ms,
    ground_ms=switcher_ground_ms,
    go_ms=0.0,
    fn(across, layer, look) {
      let field : Ref[@view.View?] = Ref(None)
      // (32 short of the room the system's bars leave across the window at most (a column of the app's tabs down a
      // side, an iPhone Duo's on its side: over_room, as confirm_panel's): room round it however narrow the frame is)
      let room = fn() { dmin(switcher_w, @sf.over_room(layer).0 - switcher_side - switcher_side) }
      across.box(fn(p) {
        @sf.style_node(p, fn() { switcher_panel.then(@ui.style(w=Fixed(room()))) }, in_row=true)
        p
        .glass(By(fn() { Some(@sf.dialog_glass()) }))
        .edge(By(fn() { if p.glass_solid() { (1.0, @sf.panel_edge()) } else { (0.0, 0L) } }))
        .shadow(By(@sf.glass_overlay_shadow))
        .shadow_outside(Is(true))
        .clips(Is(true))
        .alpha(By(fn() { look().alpha }))
        .scale(By(fn() { look().sx }))
        .offset(By(fn() { (look().dx, look().dy) }))
        .says(Is(Some(@view.said(Dialog, label=@signals.untracked(fn() { @sf.t("web-main.switcher.search") })))))
        |> ignore
        // (↑ ↓ choose a line with the cursor in its field)
        @sfpages.finder_keys_node(p)
        // (what it holds as far in as its look says, past its own ground, edge and shadow: Look's `words`, its ground
        // first)
        let words_in = fn() { look().words }
        // (the search's combobox: its field's box, its list's lines the options: finder_combobox_node)
        let combo : Ref[@sf.SearchCombo?] = Ref(None)
        p.box(fn(b) {
          @sf.style_node(b, fn() { switcher_search_box })
          b.alpha(By(words_in)) |> ignore
          combo.val = Some(@sfpages.finder_combobox_node(b, fn() { @sf.t("web-main.switcher.search") }, close))
          let f = @ui.field(
            b,
            @sfpages.finder_field(),
            placeholder=@sf.t("web-main.switcher.search"),
            font_size=switcher_search_size,
            line=switcher_search_line,
            max_lines=1,
            enter_sends=true,
            colors_by=fn() {
              let t = @sf.theme().p
              (t.text, t.subtle, t.accent)
            },
            // Enter: the line chosen opened, as it is pressed
            submitted=fn(typed) {
              @sfpages.finder_typed(typed)
              @sfpages.finder_enter(close)
            },
          )
          f.grow(Is(1.0)).basis(Is(Some(0.0))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          field.val = Some(f)
        })
        |> ignore
        // The list reaches into the panel's foot padding, so the panel cuts what scrolls past to its own curve; at its
        // end the list gives that room back under its last row.
        p.box(fn(l) {
          @sf.style_node(l, fn() { @ui.style(w=Full).then(@sf.outset_bottom(switcher_edge)) })
          l.alpha(By(words_in)) |> ignore
          @sfpages.finder_list_node(
            l,
            combo.val.unwrap(),
            src,
            workspace,
            fn() {
              match workspace() {
                Some(w) => switcher_offered(src, w, !(@sf.layout(layer.window_w()) is Small) || @sf.native_able())
                None => []
              }
            },
            fn() { @sfpages.found_stacked(room() - 2.0 * switcher_edge) },
            idle_chats=true,
            most=fn() {
              Some(dmin(switcher_most_h, layer.window_h() * switcher_most_share) - switcher_panel_rest + switcher_edge)
            },
            foot_in=switcher_edge,
          )
        })
        |> ignore
      })
      |> ignore
      field.val.unwrap()
    },
  )
}

///|
/// The panel: 14% down the window, 560 wide at most and 32 short of the window, 480 high at
/// most and 72% of the window; 12 in (EDGE), its corner a row's (18) and that (30: concentric with its rows where
/// its list is scrolled to its end, not a pill's 19 the rows are not round by), a small panel's
/// ground and line, a deep shadow (0 24px 64px); what its search takes of it (76).
let switcher_top_share : Double = 0.14

///|
let switcher_most_h : Double = 480.0

///|
let switcher_most_share : Double = 0.72

///|
let switcher_edge : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let switcher_surface : @sf.Surface = @sf.surface(switcher_edge, @sf.row_corner)

///|
// kept across runs: a value (no field of it changes)
let switcher_panel : @ui.Style = switcher_surface
  .style()
  .then(
    @ui.style(w=Full, max_w=Fixed(switcher_w), clip=true),
  )

///|
let switcher_w : Double = 560.0

///|
/// What is left of the window either side of it at least (the web's calc(100vw - 32px)).
let switcher_side : Double = 16.0

///|
/// What the panel holds besides its list: its search's 48, its 12 in at its top and foot, 4 over the list.
let switcher_panel_rest : Double = 76.0

///|
/// The search: 48 high, 12 in, the words a title's (16), the placeholder subtle.
// kept across runs: a value (no field of it changes)
let switcher_search_box : @ui.Style = @ui.css("row w=Full h=S12 px=S3 align=ACenter")

///|
let switcher_search_size : Double = 16.0

///|
let switcher_search_line : Double = 24.0

///|
/// One of the keys' actions as ⌘K offers it (the core names it): its icon, what it does; for update.app and
/// update.station, the version it goes to and the station updated. Its keys are put in as it is offered.
fn action_offered(id : String, icon : String, version? : String = "", station? : String = "", run : () -> Unit) -> @sfpages.Offered {
  { id, group: "", label: "", words: "", typed: false, version, station, icon, keys: "", run }
}

///|
/// What ⌘K offers of what the frame can do now (and its own): the
/// open chat's (find, its outline, its services, into the archive, its agents' history, its agents stopped, a file into its draft,
/// relayed, its station updated: as its keys and its bar's offer them now), the app's newer build or looking for one, the app's (a new
/// chat, the sidebar, settings, the shortcuts), settings' pages (only found by typing). The core names the keys'
/// actions and finds what was typed among them (sfdesk/switcher.mbt).
fn switcher_offered(src : Source, w : Workspace, wide_frame : Bool) -> Array[@sfpages.Offered] {
  // an action's first keys as shown (as kept on this device: settings' 快捷键)
  let prefs = src.topic("prefs", {}).get().value
  let keys = fn(action : String) { @settings.key_label(prefs, action) }
  let all : Array[@sfpages.Offered] = []
  let offer = fn(o : @sfpages.Offered) { all.push({ ..o, keys: keys(o.id) }) }
  // the open chat's (ChatPage.tsx chat.find, the outline's chat.outline, chat.jobs, chat.archive, chat.history, chat.stop, composer.file; Relay.tsx
  // chat.relay; StationUpdate.tsx update.station)
  match app.nav.top() {
    Chat(r) => {
      let view = view_of_chat(src, r).0
      if view is Some({ thread: Some(_), .. }) {
        offer(action_offered("chat.find", "search", fn() { chat_find_open(r) }))
        // (its outline: beside its rail or its round button where one shows, its field taking the keys; not in a replay
        // of a run from before the outline, whose app offered none: Source's `asks_outline`)
        match view {
          Some(v) if (src.asks_outline)() => {
            offer(action_offered("chat.outline", "list", fn() { @sfpages.outline_open_keys(src, r, v) |> ignore }))
          }
          _ => ()
        }
      }
      offer(action_offered("chat.jobs", "web", fn() { open_jobs_pop() }))
      match view {
        Some(v) => {
          if chat_has_remote(v) {
            offer(action_offered("chat.screen", "monitor", fn() { chat_remote_first(r, v.screens, v.can_terminal()) }))
          }
          if v.can_terminal() && @sfpages.terminals_here() && (src.asks_terminals)() {
            all.push({
              id: "chat.terminal",
              group: "chat",
              label: @sf.t("web-pages.remote.openChatTerminal"),
              words: "terminal shell 终端",
              icon: "terminal",
              keys: "",
              typed: true,
              version: "",
              station: "",
              run: fn() { @sfbase.open_terminal(r.station, "new", "", r.session) },
            })
          }
          if v.can_browser() {
            let listed = v.screens.filter(fn(s) { s.id.has_prefix("browser:u_") }).map(fn(s) { s.id })
            all.push({
              id: "chat.browser",
              group: "chat",
              label: @sf.t("web-pages.remote.openBrowser"),
              words: "browser 浏览器",
              icon: "web",
              keys: "",
              typed: true,
              version: "",
              station: "",
              run: fn() { @sfbase.open_remote_browser(src, r.station, listed) },
            })
          }
          let chat = src.topic("chat", chat_params(r)).get().value
          let open = !v.archived && !v.offline
          if open {
            offer(action_offered("chat.archive", "archive", fn() { archive_asked(src, w, r, v, chat) }))
          }
          if v.agents.length() > 0 {
            offer(action_offered("chat.history", "thread", fn() { history_toggle(src, r, v) }))
          }
          if agents_working(v) {
            offer(action_offered("chat.stop", "stop", fn() { stop_agents(src, r, v) }))
          }
          if open {
            offer(action_offered("composer.file", "file", fn() { @sfpages.pick_files(writing(src, r.station + ":" + r.session)) }))
          }
          match v.thread {
            Some(th) if open && v.agents.length() > 0 =>
              offer(action_offered("chat.relay", "arrow-up-right", fn() { @sfpages.open_relay(src, r, th, from=Unanchored) }))
            _ => ()
          }
          let notice = v.station_update
          let on = [("station", r.station), ("id", "station")]
          if flag(notice, "canUpdate") && !core_doing(src, ["software.update"], on) {
            offer(action_offered("update.station", "download", station=text(notice, "station"), fn() {
              act(src, @sf.t("web-main.stationUpdate.updateAction"), "", "software.update", {
                "station": Json::string(r.station),
                "id": "station",
              })
            }))
          }
        }
        None => ()
      }
    }
    _ => ()
  }
  // the app's newer build, as 关于's row offers it: one ready put in place, or one downloaded now (what the person's
  // word does, sfbase updates.mbt update_go)
  match update_now() {
    Offered(v, ..) | Failed(v, _) | Ready(v, ..) | Allow(v) =>
      offer(action_offered("update.app", "download", version=text(Some(v), "versionName"), fn() { update_go(src) }))
    _ => ()
  }
  // looking for a newer build now, as the menu's 检查更新… does (its dialog: what it finds, or that there is none); found
  // only by typing (the core's), wherever the app asks still.fail cloud for its builds
  if update.source is Some(_) && !(update_now() is (Coming(_, _) | Installing(_))) {
    offer(action_offered("update.check", "refresh", fn() { @sfbase.update_from_menu(src) }))
  }
  offer(action_offered("chat.new", "compose", fn() { new_chat() }))
  // (the wide frame's alone)
  if wide_frame {
    offer(action_offered("sidebar.toggle", "panel-open", fn() { sidebar_toggle() }))
  }
  offer(action_offered("settings", "settings", fn() { open_settings() }))
  offer(action_offered("shortcuts", "keyboard", fn() { wide.keys_open.set(true) }))
  all.push({
    id: "place.remote",
    group: "global",
    label: @sf.t("web-main.rail.remote"),
    words: "remote desktop browser terminal 远程 桌面 浏览器 终端",
    icon: "monitor",
    keys: "",
    typed: true,
    version: "",
    station: "",
    run: fn() { @sfbase.go_place("remote", kept=true) |> ignore },
  })
  let routes : Array[(String, @settings.Route, String)] = [
    ("appearance", @settings.Route::Appearance, @sf.t("web-pages.settings.nav.appearance")),
    ("notifications", @settings.Route::Notifications, @sf.t("web-pages.settings.nav.notifications")),
    ("permissions", @settings.Route::Permissions, @sf.t("web-pages.settings.nav.permissions")),
    ("archive", @settings.Route::Archiving, @sf.t("web-pages.archiving.title")),
    ("memory", @settings.Route::Memories, @sf.t("web-pages.settings.nav.memory")),
    ("security", @settings.Route::Security, @sf.t("web-pages.security.title")),
    ("vault", @settings.Route::Vault, @sf.t("web-pages.vault.title")),
    ("changelog", @settings.Route::Changelog, @sf.t("web-pages.settings.nav.changelog")),
    ("about", @settings.Route::About, @sf.t("web-pages.settings.nav.about")),
  ]
  for p in routes {
    let (key, route, label) = p
    all.push({
      id: "settings." + key,
      group: "settings",
      label,
      words: "",
      icon: "settings",
      keys: "",
      typed: true,
      version: "",
      station: "",
      run: fn() {
        open_settings_at(route)
      },
    })
  }
  all
}
