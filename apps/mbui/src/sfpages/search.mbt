// The search at the top of the chats' lists (still.fail web/src/mobile/Home.tsx SearchField, SearchPage;
// apps/android chat/screens/Search.kt), in every tier, with a finger or a mouse (⌘K's panel too where there are keys):
// a field at a list's top, out of view till the list is pulled down past its first row; tapped, the lists go up and away
// with their bar, the field comes up from where it was to
// the top of the lists' box (narrowing as 取消 comes in beside it), and under it what the words find (the finder,
// switcher.mbt: the same as ⌘K's). Back goes from one kind to all of them first; 取消 (or back) puts the field back
// in the list. A row opened goes where the shell has it, the search left open in the lists' box.

///|
/// The search's page as it stands (what it finds is sfpages' finder: switcher.mbt): open (its field off the list: `from`,
/// its top in the window when tapped), going back (`leaving`). Opened by the keys (⌘K laid out Small: `summoned`), what
/// can be done here among what it finds (`offered`, read where what it finds is made), and whether over another page
/// than the lists (`over`: the shell's, search_over_on).
priv struct Search {
  mut open : Bool
  mut leaving : Bool
  mut from : Double
  mut summoned : Bool
  mut over : Bool
  mut offered : () -> Array[Offered]
  /// how its page is to come up as it is next built, opened where that page is not (a list made once: search_open_from,
  /// search_start_now): 1 from its field, 2 up at once; 0 as it is
  mut fly : Int
  /// told as it opens, goes back or closes (search_told): what reads it, the shell's bar and what is over another
  /// page among it, built again wherever that was
  said : @signals.Signal[Int]
  /// the mounted search page node, for letting go of focus on close without @ui.current()
  mut node : @view.View?
}

///|
let search : Search = {
  open: false,
  leaving: false,
  from: 0.0,
  summoned: false,
  over: false,
  offered: fn() { [] },
  fly: 0,
  said: @signals.signal(0),
  node: None,
}

///|
/// The search opened, gone back or closed: what reads it told.
fn search_told() -> Unit {
  search.said.set(search.said.untracked() + 1)
}

///|
/// The search as it stands, read: what reads it built again as it changes (search_told).
fn search_read() -> Search {
  search.said.get() |> ignore
  search
}

///|
/// A search open as the app starts (src/sffix's modes search-results and search-jobs, the Android app's
/// SearchResultsTest twins): the words typed, the kind alone ("" every kind); its field come up, the keyboard away.
let search_at_start : Ref[(String, String)?] = Ref(None)

///|
/// What a fixture mode opens of the search (open_fixture_mode).
pub fn open_search_mode(mode : String) -> Unit {
  if mode == "search-results" || mode == "search-results-dark" {
    search_at_start.val = Some(("登录", ""))
  } else if mode == "search-jobs" || mode == "search-jobs-dark" {
    search_at_start.val = Some(("登录", "job"))
  }
}

///|
fn search_reset() -> Unit {
  search_at_start.val = None
  search.open = false
  search.leaving = false
  search.from = 0.0
  search.summoned = false
  search.over = false
  search.offered = fn() { [] }
  search.fly = 0
  search.node = None
  search_told()
}

///|
/// How far the list goes up as the field comes up; the field's way up and back a Move as long as
/// it is far (from where it stood in the list to the top: search_way).
pub let search_list_rise : Double = 56.0

///|
/// The bottom bar out of the search's way while it is open: from the tap until it starts back.
pub fn search_bar_away() -> Bool {
  search_read() |> ignore
  search.open && !search.leaving && !search.over
}

///|
/// The field at the top of a list made once pressed (search_field_node: its top in the window, its width): the search
/// opens from it, its page coming up from there as it is first built.
fn search_open_from(from : Double) -> Unit {
  if search.open {
    return
  }
  search.open = true
  search.leaving = false
  search.from = from
  search.fly = 1
  search_told()
}

///|
/// The search the app starts with (search_start's), opened as lists made once are: its page up at once as it is built.
pub fn search_start_now() -> Unit {
  match search_at_start.val {
    Some((q, k)) => {
      search_at_start.val = None
      search.open = true
      search.fly = 2
      search_told()
      finder_start(q, kind=k)
    }
    None => ()
  }
}

///|
/// How far lists made once are away under the search, in node `v`'s timeline (search_away's: 0 none, 1 up and gone):
/// off up as it opens over them, as long as its field's way up (search_way), back as it goes back; nothing while it is
/// over another page.
pub fn search_away_node(v : @view.View) -> () -> Double {
  let up = fn() {
    let s = search_read()
    s.open && !s.leaving && !s.over
  }
  let way = @motion.NodeWay::new(if @signals.untracked(up) { 1.0 } else { 0.0 })
  v.reacts(up, fn(on) {
    if @signals.untracked(fn() { search_read().fly }) == 2 {
      way.go_from(v, 1.0, 1.0, @motion.Snap(0.0))
    } else {
      way.go(v, if on { 1.0 } else { 0.0 }, search_way())
    }
  })
  fn() { way.shown(v) }
}

///|
/// ⌘K laid out Small (the shell's keys: sfdesk's keys.mbt), at the key's moment: the search open, its field at the top
/// with the keys in it, up at once as its page is built, what can be done here (`offered`, as what it finds is built)
/// among what it finds; `over` another page than the lists (a chat), drawn over it by the shell (search_over). Open
/// already, closed.
pub fn search_summon(offered : () -> Array[Offered], over : Bool) -> Unit {
  if search.open {
    search_close_now()
    return
  }
  finder_cleared()
  search.open = true
  search.leaving = false
  search.from = 0.0
  search.summoned = true
  search.over = over
  search.offered = offered
  // (up at once, what goes away under it gone at once too: search_away_node, search_page)
  search.fly = 2
  search_told()
}

///|
/// The field's way up and back: from where it stood in the list (its top in the window) to the top, a Move as long as
/// that (the list's rise at least).
fn search_way() -> @motion.Spec {
  @motion.moved(points=dmax(search.from, search_list_rise))
}

///|
/// Closed: the field the list's again, what was found let go.
fn search_gone() -> Unit {
  search.fly = 0
  search.open = false
  search.leaving = false
  search.summoned = false
  search.over = false
  search.offered = fn() { [] }
  finder_cleared()
  search_told()
}

///|
/// Whether the search is open over another page than the lists (⌘K laid out Small in a chat: search_summon): the shell
/// puts its page there (search_page_node, on the page's ground: search_over_ground_node).
pub fn search_over_on() -> Bool {
  let s = search_read()
  s.open && s.over
}

///|
/// The search's page over another page than the lists in `v` (search_over_on's): on the page's ground, nothing of the
/// page under it seen.
pub fn search_over_ground_node(v : @view.View) -> Unit {
  @sf.style_node(v, fn() { search_over_box })
}

///|
/// Over another page than the lists (search_over): on the page's ground, nothing of the page under it seen.
// kept across runs: a value (no field of it changes)
let search_over_box : @ui.Style = @ui.css("w=Full h=Full bg=Bg")

///|
/// Its bar: under the status bar 8 (the home bar's top), 16 either side, 8 under; 取消 12 after the field.
// kept across runs: a value (no field of it changes)
let search_bar_row : @ui.Style = @ui.css("row w=Full pl=S4 pr=S4 pt=S2 pb=S2 gap=S3 align=ACenter")

///|
/// The field's ground (SearchPage's): a full-radius capsule; liquid glass is attached on the host node.
// kept across runs: a value (no field of it changes)
let search_field_ground : @ui.Style = @ui.css("w=Full radius=Full")

///|
/// What it holds: its icon 8 before the words.
// kept across runs: a value (no field of it changes)
let search_field_in : @ui.Style = @ui.css("row w=Full gap=S2 align=ACenter")

///|
/// The field, its ground and what it holds.
// kept across runs: a value (no field of it changes)
let search_field_box : @ui.Style = search_field_ground.then(search_field_in)

///|
/// One field, in the list and come up from it alike (search_field, search_page): what it holds as high as the theme's
/// band (what stands over a sidebar's list: 38 with touch) and its words as far in from its ends as where its list
/// stands has them (`at`: band_pad_in, 12 with a finger on the tape and across a phone's screen), its mark and its
/// words the band's too.
fn search_field_room(band : @sf.ChatList, at : @sf.ListAt) -> @ui.Style {
  @ui.style(h=Fixed(band.band_h), px=@sf.room_of(@sf.band_pad_in(at)))
}

///|
/// The field at the list's top: 6 under it (how far in: search_field), what is under it when it is tucked over the
/// rows (sidebar.mbt: its foot out of view under the bar with it).
// kept across runs: a value (no field of it changes)
let search_field_line : @ui.Style = @ui.css("w=Full").then(@ui.style(pb=@sf.room_of(tucked_foot)))

///|
let tucked_foot : Double = 6.0

///|
/// Its words: the band's, muted (what to do in it, not yet done).
// kept across runs: a value (no field of it changes)
let search_field_words : @ui.TextStyle = @ui.text_style(color=Muted)

///|
///|
// kept across runs: a value (no field of it changes)
let search_cancel : @ui.TextStyle = @ui.text_style(size=Title, color=Link, wrap=false)

// ── Home's field ───────────────────────────────────────────────────────

///|
/// What the field says where 搜索全部内容 does not fit (in the list's and as it is typed in alike).
fn search_field_shorter() -> Array[String] {
  [@sf.t("common.search")]
}

///|
/// The search at the top of a list made once (search_field's) in its line `line`: a quiet field; pressed, the search
/// opens from it. Not seen while the search's field is it. It stands on the list's line (`at`).
fn search_field_node(
  line : @view.View,
  at : @sf.ListAt,
  reveal? : () -> Double = fn() { 1.0 },
) -> @view.View {
  let field : Ref[@view.View?] = Ref(None)
  line.box(fn(l) {
    @sf.style_node(l, fn() {
      let band = @sf.theme().chat_list
      match at {
        Side | Tape => search_field_line
        Whole => search_field_line.then(@ui.style(px=@sf.room_of(band.band_in)))
      }
    })
    @sf.action_box_node(
      l,
      fn() { @sf.t("android-chat.search.field") },
      fn(f) {
        let (_, y, _, _) = f.placed_window_now()
        search_open_from(y)
      },
      fn(f) {
        field.val = Some(f)
        match at {
          Whole => {
            @sf.style_node_and(
              f,
              fn() { search_field_box.then(search_field_room(@sf.theme().chat_list, at)) },
              fn() {
                let show = !search_read().open && reveal() > 0.001
                let glass = if show { Some(@sf.search_capsule_glass()) } else { None }
                let edge = if show && f.glass_solid() { @sf.overlay_solid_edge() } else { (0.0, 0L) }
                let shadow = if show { @sf.glass_overlay_shadow() } else { (0.0, 0.0, 0L) }
                (glass, edge, shadow)
              },
              fn(look) {
                let (glass, edge, shadow) = look
                f.glass(Is(glass)).edge(Is(edge)).shadow(Is(shadow)) |> ignore
              },
            )
            f.shadow_outside(Is(true)) |> ignore
          }
          Side | Tape =>
            @sf.style_node(f, fn() {
              search_field_box.then(@ui.style(bg=@sf.search_ground)).then(search_field_room(@sf.theme().chat_list, at))
            })
        }
        f
        .alpha(By(fn() { if search_read().open { 0.0 } else { reveal() } }))
        .presses(By(fn() { !search_read().open && reveal() > 0.001 }))
        |> ignore
      @sf.icon_node(f, "search", @sf.theme().chat_list.band_icon, By(fn() { @sf.theme().p.muted })) |> ignore
      @sf.words_node(f, fn() { @sf.t("android-chat.search.field") }, fn() {
        @sf.theme().chat_list.band_words.then(search_field_words)
      })
      // (cut short where its line has not the room: whole beside its mark in a list, which is wide enough wherever
      // one has its search)
      .grow(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
  })
  |> ignore
  field.val.unwrap()
}

// ── the page ───────────────────────────────────────────────────────────

///|
/// Whether the search is open over the lists (and whether it is going back to its field).
pub fn search_opened() -> Bool {
  search_read() |> ignore
  search.open
}

///|
pub fn search_leaving() -> Bool {
  search_read() |> ignore
  search.leaving
}

// ── the page made once ─────────────────────────────────────────────────

///|
/// The search over lists made once (search_page's) in node `v`, while it is open: under `inset`
/// (what is over the lists' box), its bar (the field come up from where it stood in the list to the top, 取消 coming in
/// beside it), what the words find under it (the finder's list, its old view, hosted), its lines standing as the lists'
/// do (`at`). Back and Esc go from one kind to every kind first, then the search away; 取消 the same.
pub fn search_page_node(
  v : @view.View,
  src : Source,
  workspace : () -> Workspace?,
  inset : () -> Double,
  at : @sf.ListAt,
) -> Unit {
  // its way up: from its field in the list (0) to the top (1), from the moment it opened; back as it goes back, gone
  // at that way's end
  let up = @motion.NodeWay::new(if search.fly == 1 { 0.0 } else { 1.0 })
  let gone_due = Ref(fn() {  })
  let fly = fn() {
    match search.fly {
      1 => up.go_from(v, 0.0, 1.0, search_way())
      2 => up.put(1.0)
      _ => ()
    }
  }
  // (how it came up said for what goes away under it too (search_away_node): let go as it closes, search_gone)
  search.node = Some(v)
  v.owns(fn() {
    if search.node is Some(cur) && physical_equal(cur, v) {
      search.node = None
    }
  })
  |> ignore
  fly()
  v.reacts(fn() { search_read().leaving }, fn(leaving) {
    if leaving {
      up.go(v, 0.0, search_way())
      (gone_due.val)()
      gone_due.val = v.at_moment(up.end(), fn() { search_gone() })
    }
  })
  let u = fn() { up.shown(v) }
  let close = fn() {
    if search.over {
      v.focus_let_go()
      search_gone()
    }
  }
  // (back: one kind first, then the search away; Escape clears what is typed before that, as a Mac's search field)
  let back = fn() {
    if !finder_back() {
      search_close_now()
    }
  }
  let escape = fn() {
    if !finder_escape() {
      search_close_now()
    }
  }
  v
  .over(Is(true))
  .presses(Is(true))
  .takes_back(fn() { if !search.leaving { back() } })
  .on_key(fn(k) {
    if k.code == @ui.key_escape && !search.leaving {
      escape()
      true
    } else {
      false
    }
  })
  |> ignore
  v.box(fn(top) { top.height(By(fn() { Some(inset()) })) |> ignore }) |> ignore
  let combo : Ref[@sf.SearchCombo?] = Ref(None)
  v.box(fn(bar) {
    @sf.style_node(bar, fn() { search_bar_row })
    // (取消's room beside the field as it comes in: its words' width and the room before them)
    let cancel_w = fn() {
      @ui.text_advance(@sf.t("android-chat.search.cancel"), size=@sf.node_sp(bar, @sf.theme().t.title)) + 12.0
    }
    bar.box(fn(slot) {
      slot
      .grow(Is(1.0))
      .basis(Is(Some(0.0)))
      .min_width(Is(Some(0.0)))
      .height(By(fn() { Some(@sf.theme().chat_list.band_h) }))
      .radius(By(fn() { @sf.theme().chat_list.band_h / 2.0 }))
      .glass(By(fn() { Some(@sf.search_capsule_glass()) }))
      .edge(By(fn() { if slot.glass_solid() { @sf.overlay_solid_edge() } else { (0.0, 0L) } }))
      .shadow(By(@sf.glass_overlay_shadow))
      .shadow_outside(Is(true))
      // (as wide as the list's field there, narrowing to its room as 取消 comes in with its right edge)
      .margin(By(fn() { (0.0, 0.0, -(1.0 - u()) * cancel_w(), 0.0) }))
      // (from where it stood in the list: its top in the window then, to where it rests)
      .offset(By(fn() { (0.0, (search.from - inset() - search_bar_top) * (1.0 - u())) }))
      |> ignore
      // (the search's combobox: the field's slot, its list's lines the options: finder_combobox_node)
      combo.val = Some(finder_combobox_node(slot, fn() { @sf.t("android-chat.search.field") }, close))
      // (the library's field to look through a list by, as the one in the list it came up from looks: its clear key
      // while it holds words)
      let field = @sf.search_input_node(
        slot,
        finder_field(),
        fn() { @sf.t("android-chat.search.field") },
        at~,
        shorter=search_field_shorter(),
        // the keyboard's search key, as a keyboard's Enter: the line chosen opened where one is shown chosen
        submitted=fn(typed) {
          finder_typed(typed)
          finder_enter(close)
        },
      )
      v.focus_opens(field) |> ignore
      // (what is typed, as it is: what the finder looks for)
      slot.reacts(fn() { finder_field().text() }, fn(words) { finder_typed(words) })
    })
    |> ignore
    @sf.action_box_node(bar, fn() { @sf.t("android-chat.search.cancel") }, fn(_) { if !search.leaving { search_close_now() } }, fn(k) {
      k
      .alpha(By(u))
      .offset(By(fn() { (cancel_w() * (1.0 - u()), 0.0) }))
      |> ignore
      @sf.words_node(k, fn() { @sf.t("android-chat.search.cancel") }, fn() { search_cancel }) |> ignore
    })
    |> ignore
  })
  |> ignore
  // what the words find (sfpages' finder: finder_list_node): a row opened, its page over this one, back to it; ↑ ↓
  // choose a line with the cursor in its field (finder_keys_node)
  finder_keys_node(v)
  v.box(fn(l) {
    // (coming in from half way, the lists under it gone by then: search_away_node's readers)
    l.grow(Is(1.0)).min_height(Is(Some(0.0))).alpha(By(fn() { dmax(0.0, 2.0 * u() - 1.0) })) |> ignore
    @sf.style_node(l, fn() { @sf.list_line(at) })
    finder_list_node(
      l,
      combo.val.unwrap(),
      src,
      workspace,
      fn() { (search.offered)() },
      // (who, where and when under a line's words where the list is narrow: a side column's always, across a
      // phone's screen by its width)
      fn() {
        match at {
          Whole => found_stacked(l.window_w() - 2.0 * @sf.list_line_in(at))
          Side | Tape => true
        }
      },
      idle_chats=search.summoned,
      at~,
    )
  })
  |> ignore
}

///|
/// 取消, back or Esc on the search made once: the keyboard goes and the field goes back to the list (search_close's);
/// opened by the keys, gone at once.
fn search_close_now() -> Unit {
  if !search.open || search.leaving {
    return
  }
  match search.node {
    Some(n) => n.focus_let_go()
    None => ()
  }
  if search.summoned {
    search_gone()
    return
  }
  search.leaving = true
  search_told()
}

///|
/// Its bar's room over the field (search_bar_row's pt: S2).
let search_bar_top : Double = 8.0

///|
/// Whether the search is open over the lists (not over another page: search_over's).
pub fn search_on_lists() -> Bool {
  let s = search_read()
  s.open && !s.over
}
