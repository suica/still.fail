// Home made once (home.mbt's home_page as nodes of the window's tree): the workspace's chats' lists (sfpages'
// chats_lists_node) under the top bar (待处理, the filter · the workspace's switcher and settings), what the last
// update brought and what the update wants over the rows. What is left up long is 待处理's (its bell lit by the viewer's
// own not looked at yet), not the list's: the chats come first on Home.

///|
/// Home in node `v` for `src` (as the narrow frame makes it once: narrow_made_as's Home): the lists under the top bar's
/// room, over the bottom bar's; the top bar over them. Tips in `tips`, pictures asked for on `stint`.
fn home_node(
  v : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  stint : () -> Int,
  serial? : Int = 0,
  shown? : () -> Bool = fn() { true },
) -> Unit {
  let workspace = fn() { workspace_in_view(src).0 }
  let view = fn() {
    match workspace() {
      Some(w) => chats_of(src, w.id, filter_of(src, w.id)).0
      None => None
    }
  }
  let frame : @sfpages.ListsNodeFrame = {
    // under the top bar, the status bar's height and its own; over the bottom bar
    top: fn() { status_top_now(v.window_w()) + bar_h + 8.0 },
    under: fn() { status_top_now(v.window_w()) + bar_h },
    foot: fn() { nav_foot() + bar_room_at(v.window_w()) },
    ground: fn() { @sf.theme().p.bg },
    // what the update wants of the person, over what the last one brought (until it is seen)
    before: fn(filter, view) {
      let parts : Array[@sfpages.NodePart] = @sfpages.restart_interrupted_parts(src, view, fn() {
        match workspace() {
          Some(w) => chats_of(src, w.id, filter).0
          None => None
        }
      })
      if @sfpages.stale_build_card_shown() {
        parts.push({ key: "stale-build-card", make: fn(p) { @sfpages.stale_build_card_node(p, src) } })
      }
      if @sfpages.update_card_shown() {
        parts.push({ key: "update-card", make: fn(p) { @sfpages.update_card_node(p, src) } })
      }
      if @sfpages.news_of(src) is Some(_) {
        parts.push({ key: "changelog-news", make: fn(p) { @sfpages.changelog_news_node(p, src, tips) } })
      }
      parts
    },
    after: fn(_, _) { [] },
    others: [],
    shown: fn() {
      match workspace() {
        Some(w) => @sfpages.filter_at(src, w)
        None => 0
      }
    },
    at: Whole,
    // (in view while it is the page on top: what changes under another page is as it is as it is come back to)
    watched: fn() { app.nav.top() is Home },
  }
  // (what is left up long asked with the lists from the start, not once they have come: Home opens on both,
  // home_opens; its bell's dot reads it)
  @sfbase.long_jobs_read(v, src, workspace)
  // (a search the app starts with open: sfpages' search.mbt)
  @sfpages.search_start_now()
  // (while the app's first page waits for what it shows: drawn at none, the splash in its place, as the old views are)
  v
  .grow(Is(1.0))
  .min_height(Is(Some(0.0)))
  .alpha(By(fn() { if @sfbase.first_page_waits.get() { 0.0 } else { 1.0 } }))
  .takes_unseen(Is(true))
  |> ignore
  // under a finger's search the bar faded with the lists going away, the search over them (its old
  // view, hosted)
  let away = @sfpages.search_away_node(v)
  v.box(fn(lists) {
    lists.over(Is(true)) |> ignore
    if serial != 0 {
      tab_body_comes_in(lists, serial)
    }
    // (the chats as a board where it is chosen: sfpages' board_node, under the bar, over the bottom bar; the one not
    // chosen, once made, put by as it was (View::each's `keeps`), taken in again at once as it is chosen again: the
    // board's cards and the lists' rows not made anew at each switch)
    lists.each(fn() { [@sfbase.board_on_now(src)] }, fn(k) { k }, keeps=fn() { [true, false] }, at_once=true, fn(l, on) {
      let board = @signals.untracked(fn() { on.get() })
      l.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
      if board {
        // (the window's whole height, as the list: what its columns scroll passing under the top bar, the board's chips
        // under it on the same glass, and under the bottom bar)
        @sfpages.board_node(
          l,
          src,
          tips,
          workspace,
          fn() { l.window_w() },
          top=fn() { (frame.under)() + @sfpages.board_chips_h(l) },
          foot=fn() { (frame.foot)() },
          stint~,
        )
      } else {
        @sfpages.chats_lists_node(l, src, workspace, frame, tips, stint)
      }
    })
  })
  |> ignore
  v.box(fn(bar) {
    bar
    .over(Is(true))
    .lies_along(Is(Start))
    .alpha(By(fn() { if serial != 0 && app.nav.is_swapping_out(serial) { 0.0 } else { 1.0 - away() } }))
    |> ignore
    home_top_bar_node(bar, src, tips, workspace, view, shown~)
  })
  |> ignore
  v.show(@sfpages.search_on_lists, fn(s) {
    if serial != 0 {
      tab_body_comes_in(s, serial)
    }
    @sfpages.search_page_node(s, src, workspace, fn() { status_top_now(s.window_w()) }, Whole)
  })
}

///|
/// What Home of workspace `ws` (home_node) opens on, asked of `ask` (sfbase's opens_answered): its chats' list as it is
/// filtered (sfbase's list_opens), what the last update brought over it, and what is left up long after its rows.
/// Whether all of it is answered: Home opening waits for it (app.mbt's page_ready), a workspace switched on 小屏 too
/// (narrow_shell: sfbase's workspace_switch_node). Not the core's marks its bar's 待处理 dot shows: the app's first
/// page would wait for every workspace's marks, made after the list (40 ms after it in Hermes on a Mac Studio at a
/// workspace of real size, 2026-11-11), for a dot.
fn home_opens(src : Source, ws : String, ask : (String, Map[String, Json]) -> @sfbase.TopicState) -> Bool {
  let list = @sfbase.list_opens(src, ws, ask)
  let news = @sfbase.opens_answered(ask("changelog", @sfpages.news_params()))
  let long = @sfbase.opens_answered(ask("longJobs", @sfbase.long_jobs_asked(ws)))
  // (and what the narrow shell round it reads as it is first built, asked with it and not waited for: Home shows,
  // and the splash goes, as it did before they were asked here: sfbase's shell_opens)
  @sfbase.shell_opens(src, ws, ask) |> ignore
  // (the board where the workspace shows it: its chats, all of them, and its stations)
  let board = @sfbase.board_opens(src, ws, ask)
  list && news && long && board
}

///|
/// Home's top bar in `v`, on its glass, under the status bar: the filter at the left (with stations to
/// narrow), what is catching up and going up beside it, the workspace's switcher and settings at the right; 待处理
/// first unless not `bell` (over the page of a device waiting in the lock: nothing of the workspace's to attend to).
/// Its tips in `tips`.
fn home_top_bar_node(
  v : @view.View,
  src : Source,
  tips : @sf.TipLayer,
  workspace : () -> Workspace?,
  view : () -> ChatsView?,
  bell? : Bool = true,
  shown? : () -> Bool = fn() { true },
) -> Unit {
  v.box(fn(g) {
    // (Apple iOS 26 UIScrollEdgeEffect.soft: 100% solid behind the system status bar, then full bar_h soft fade
    // so scrolled chat rows refract cleanly through the translucent liquid glass pills and feather into the status bar)
    narrow_bar_scrim_node(
      g,
      fn(s) {
        let top = status_top_now(s.window_w())
        if top > 0.0 { top + 20.0 } else { 0.0 }
      },
      fn(s) {
        let top = status_top_now(s.window_w())
        if top > 0.0 { top + 20.0 } else { 0.0 }
      },
    )
    g.box(fn(row) {
      row
      .row(Is(true))
      .sets_together(fn() { status_top_now(row.window_w()) }, fn(top) {
        row.padding(Is((12.0, top, 12.0, 0.0))).min_height(Is(Some(top + bar_h))) |> ignore
      })
      .gap(Is(6.0))
      .lines_up(Is(Some(Middle)))
      .fits(Is(true))
      |> ignore
      // the filter, and the archive in its menu: nothing to narrow or look back on with no station; on the board as on
      // the list (its menu the board's: 全部会话 or 我参与的 on it, 已隐藏 and 已归档 off it: home_filter_go)
      let keyed = fn() { @sfbase.board_on_now(src) || view().map(fn(v) { v.stations > 0 }).unwrap_or(false) }
      let stations_said = fn() {
        match workspace() {
          Some(w) if (src.asks_station_updates)() => @sfpages.station_updates_said(settings_core(src, w), w.id)
          _ => ""
        }
      }
      let has_left = fn() {
        bell ||
        keyed() ||
        stations_said() != "" ||
        (match view() {
          Some({ syncing: Some(_), .. }) => true
          _ => false
        })
      }
      let left_pill = @sf.bar_pill_group_node(row, height=40.0, pad=3.0, gap=2.0, fn(pill) {
        pill.fits(Is(true)) |> ignore
        // 待处理, first on the bar: as a system's bar has it (no rail here to hold its bell)
        if bell {
          pill.box(fn(k) {
            @sf.round_key_node(k, "bell", fn() { tr("web-main.attention.entry") }, fn() {
              guard @signals.untracked(workspace) is Some(w) else { return }
              @sfdesk.open_attention_panel(src, w, Node(k))
            })
            k.show(fn() { workspace().map(fn(w) { @sfdesk.bell_lit(src, w) }).unwrap_or(false) }, fn(m) {
              m.over(Is(true)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Start))) |> ignore
              m.box(fn(at) {
                at.offset(Is((-home_bell_dot_at, home_bell_dot_at))) |> ignore
                @sfpages.chat_mark_node(at, fn() { "done" })
              })
              |> ignore
            })
          })
          |> ignore
        }
        pill.show(keyed, fn(f) {
          let key : Ref[@view.View?] = Ref(None)
          let opener = @sf.Opener::new()
          let shown = fn(w : Workspace) {
            if @sfbase.board_on_now(src) {
              @sfbase.board_filter_of(src, w.id)
            } else {
              filter_of(src, w.id)
            }
          }
          key.val = Some(f)
          @sf.round_key_node(
            f,
            "filter",
            fn() {
              let filter = match workspace() {
                Some(w) => shown(w)
                None => "all"
              }
              fill("android-chat.home.filter.label", [
                (
                  "filter",
                  tr(
                    match filter {
                      "mine" => "android-chat.home.filter.mine"
                      "watching" => "android-chat.home.filter.watching"
                      "hidden" => "web-main.filter.hidden"
                      _ => "android-chat.home.filter.all"
                    },
                  ),
                ),
              ])
            },
            fn() {
              guard @signals.untracked(workspace) is Some(w) else { return }
              let (x, y, wd, h) = key.val.map(fn(k) { k.placed_window_now() }).unwrap_or((0.0, 0.0, 0.0, 0.0))
              let board = @sfbase.board_on_now(src)
              @sfpages.filter_menu(At(x, y, wd, h), shown(w), fn(f) { home_filter_go(src, w, f, board~) }, in_board=board, along=Start)
              opener.mark()
            },
            icon_size=20.0,
            opener~,
          )
        })
        // 列表 | 看板, its own key beside the filter: 看板 on the list, 列表 on the board; 看板 the second to leave where
        // the bar has not the room (catching up and transfers both beside it on a narrow phone, till they are done), 列表
        // never (the way back to the list); only while 实验性功能's 对话列表看板视图 is on
        pill.show(fn() { @sfbase.board_feature.get() && keyed() }, fn(m) {
          m.drops(By(fn() { if @sfbase.board_on_now(src) { 0 } else { 2 } })) |> ignore
          // (one key, its icon and words following the mode: nothing made again as it turns)
          let on = fn() { @sfbase.board_on_now(src) }
          @sf.round_key_node(
            m,
            "view-columns",
            fn() { if on() { @sf.t("web-main.board.list") } else { @sf.t("web-main.board.board") } },
            fn() { @sfbase.board_set(src, !@signals.untracked(on)) },
            icon_size=20.0,
            icon_now=fn() { if on() { "list" } else { "view-columns" } },
          )
        })
        // catching up beside them (laid nowhere while it is not there): it and transfers stay, the workspace's name giving
        // way to them; the stations' releases the first to leave where the bar has not the room (their dialog in 设置 as
        // well), 看板 the second (end's, below)
        @sf.sync_key_node(pill, tips, 34.0, 20.0, fn() {
          match view() {
            Some({ syncing: Some(y), .. }) => Some(y)
            _ => None
          }
        })
        // transfers beside it (sfdesk's transfers_key_node: there only while something comes or goes)
        pill.box(fn(k) {
          k.shrink(Is(0.0)) |> ignore
          @sfdesk.transfers_key_node(k, src, fn() { workspace().map(fn(w) { w.id }).unwrap_or("") }, 34.0, 20.0, tips, shown~)
        })
        |> ignore
        // the stations' newer releases waiting for this person, in the app's own update mark as the wide frames' sidebar
        // offers them beside the app's own; pressed, their dialog (sfpages station_updates.mbt)
        pill.show(fn() { stations_said() != "" }, fn(s) {
          s.drops(Is(1)) |> ignore
          @sf.round_key_node(s, "download", stations_said, fn() {
            match @signals.untracked(workspace) {
              Some(w) => @sfpages.station_updates_dialog(src, settings_core(src, w), w.id)
              None => ()
            }
          }, icon_size=20.0)
        })
      })
      left_pill.laid_nowhere(By(fn() { !has_left() })).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      row.box(fn(end) {
        // (giving way, its name cut short: reserve room for settings + 4-em workspace title so left_pill shrinks and
        // drops optional keys before squeezing the workspace name)
        end.row(Is(true)).grow(Is(1.0)).shrink(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(170.0))).gap(Is(8.0)).lines_up(Is(Some(Middle))).lies_along(Is(End))
        |> ignore
        // the workspace's switcher: its mark, its name, what the others have waiting
        let open = fn(s : @view.View) {
          @sfpages.open_workspaces(
            src,
            {
              let (x, y, w, h) = s.placed_window_now()
              @sf.Anchor::At(x, y, w, h)
            },
            along=End,
          )
        }
        @sf.bar_pill_group_node(end, height=40.0, pad=3.0, gap=0.0, fn(ws_pill) {
          @sf.action_box_node(ws_pill, fn() { workspace().map(fn(w) { w.name }).unwrap_or("") }, open, fn(s) {
            s
            .row(Is(true))
            .height(Is(Some(34.0)))
            .radius(Is(17.0))
            .padding(Is((6.0, 0.0, 8.0, 0.0)))
            .gap(Is(4.0))
            .lines_up(Is(Some(Middle)))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            |> ignore
            @sf.bar_pill_key_press_node(s)
            // (the fixture's home-sheet: opened by it as the app starts, beside it wherever it is laid out)
            if home_sheet_at_start.val {
              home_sheet_at_start.val = false
              @sfpages.open_workspaces(src, @sf.Anchor::Node(s), along=End)
            }
            @sf.icon_node(s, "chevron-down", 16.0, By(fn() { @sf.theme().p.muted })) |> ignore
            s.show(fn() { workspace().map(fn(w) { @sf.has_station_mark(w.emoji, w.icon) }).unwrap_or(false) }, fn(m) {
              @sf.station_mark_node(
                m,
                fn() { workspace().map(fn(w) { w.emoji }).unwrap_or("") },
                fn() { workspace().map(fn(w) { w.icon }).unwrap_or("") },
                home_ws_mark,
                fn() { @sf.theme().p.muted },
                fn() { 0 },
              )
            })
            // (a row, its name cut short along it: what the bar keeps of it, four of its size, above)
            s.box(fn(t) {
              t.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              let name = fn() { workspace().map(fn(w) { w.name }).unwrap_or("") }
              @sf.top_bar_title_node(t, name, look=@sf.home_workspace_title_look) |> ignore
            })
            |> ignore
            // (what the others have waiting, as the workspace shown's mark says it)
            let marks = fn() {
              match workspace() {
                Some(w) => field(field(src.topic("workspaceMarks", @sfbase.marks_asked()).get().value, "workspaces"), w.id)
                None => None
              }
            }
            s.show(fn() { field(marks(), "others") is Some(String(_)) }, fn(m) {
              m.says(By(fn() { Some(@view.said(Image, label=text(marks(), "othersLabel"))) })) |> ignore
              @sfpages.chat_mark_node(m, fn() { text(marks(), "others") })
            })
          })
          |> ignore
        })
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
        @sf.bar_pill_group_node(end, height=40.0, pad=3.0, gap=0.0, fn(set_pill) {
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
  })
  |> ignore
}

///|
/// How far in from its corner the bell's dot is.
let home_bell_dot_at : Double = 5.0

