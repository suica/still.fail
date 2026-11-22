// A text read as a book (reader.mbt's state) as nodes of the window's tree, made once: one column that scrolls, never
// pages, a page's list of its blocks (View::scrolls_window: a block made only while it shows), each its words in the
// reader's size, lines, margins and face (a Markdown file's as a chat's Markdown is drawn, markdown_node), the places
// found marked on them. Where the top of what shows is is told by the list as it changes (ListPlace::on_sight) and
// kept as it holds still; a jump (a chapter, a place found, the track, where it was left) is a block brought with what
// it marks there before the eyes (ListPlace::bring_sought, View::sought), in the fill that measures it.
//
// Its chrome by the screen it is on: on 大屏 and 中屏 the bar every file opened has (viewer_bar_node) on the paper and
// in its ink, gone as the text is read on down and back as it is read back up or the pointer comes to the window's
// top; the hairline along the foot; what was found under the bar; the contents' and the search's panel docked at the
// right under the bar, 320 wide, the text kept clear of it (the layout's the window's tree's own: reader_layout_nodes).
// On 小屏 its own bars that a tap on the text brings (and takes away), coming in 140 ms and going in 240, a step up or
// down as they fade; the contents and the search sheets from the window's foot (sheet_node), the layout's half as tall.
// In a tab beside a chat (`host` Tab or PanelTab) the tab's tools open its panels (reader_panel_toggle), while
// scroll-to-bottom floats at the tab's bottom-right (reader_beside_chrome, matching a chat's float); the column starts
// at the tab's top (wider in PanelTab: panel_column_ems), and an open panel sits over the text where the tab has not
// room for both.
//
// ⌘F finds, ← → go from chapter to chapter, Esc closes what is open over the text (else goes back): the keymap's
// reader.* (reader_bindings), at their key's moment; none of a tab's (the window's keys are the chat's).

///|
/// A text read (Reader) as nodes in `parent` (all of its room): `file` (read as `key`, Markdown or not) on its paper,
/// back to `back_label` (`on_back`); while it comes, how far it has; failed, why; empty, so said. On 小屏 a phone's bars
/// that a tap brings, else a desktop's bar and its panels docked at its right; `host`: OwnPage for a page of its own,
/// Tab for a tab over the whole window or in a window of its own, PanelTab for a tab in the chat's panel (wider column:
/// panel_column_ems), `width()` its width (its panel beside the text where it has room for both). `move_beside`: while
/// its first says so, a
/// desktop's bar's 移到侧边 (its file to a tab beside the page), where offered. `source`: 源码 in its bars (not in a tab,
/// whose own tools say it), its text shown as it is written in place of the reader.
#callsite(autofill(loc))
pub fn reader_node(
  parent : @view.View,
  key : String,
  file : ViewerFile,
  markdown~ : Bool,
  back_label~ : () -> String,
  on_back~ : () -> Unit,
  host? : ReaderHost = OwnPage,
  width? : () -> Double,
  move_beside? : (() -> Bool, () -> Unit)? = None,
  source? : (() -> Unit)? = None,
  loc~ : SourceLoc,
) -> @view.View {
  let beside = host != OwnPage
  let ems = if host == PanelTab { panel_column_ems } else { desk_column_ems }
  let r = reading_for(key)
  reader_load(r, file, markdown)
  // (gone back: its layout's panel, the window's tree's, closed with it)
  let back = fn() {
    if r.panel.untracked() == Layout {
      reader_panel_set(r, NoPanel)
    }
    on_back()
  }
  let paper = fn() { reader_paper((viewer_host().reader_style)().paper) }
  parent.box(made_for=loc, fn(page) {
    page.over(Is(true)).ground(By(fn() { paper().ground })) |> ignore
    // (over the whole window, what it shows and its chrome clear of the column of the system's bars down the window's
    // trailing edge, an iPhone Duo's on its side (native_clear), its paper on under it, as a film's or a page's opened
    // over it is (sfbase's viewer_tree.mbt); in a tab, the tab's room)
    let clear = fn() { if beside { 0.0 } else { native_clear() } }
    let room = page.box(fn(r) { r.over(Is(true)).row(Is(true)).padding(By(fn() { (0.0, 0.0, clear(), 0.0) })) |> ignore })
    let root = room.box(fn(m) { m.grow(Is(1.0)) |> ignore })
    // laid out 小屏 (the window's tier): a phone's, its own bars that a tap brings; not in a tab
    let small = fn() { !beside && layout(root.window_w()) is Small }
    // (the panel beside the text: on 大屏 and 中屏 always, in a tab where it has room for both; on 小屏 never, its
    // panels the window's sheets over it)
    let wide = match width {
      Some(w) if beside => fn() { w() >= beside_both_least }
      _ => fn() { !small() }
    }
    let tab_w = match width {
      Some(w) => w
      None => fn() { dmax(0.0, root.window_w() - clear()) }
    }
    reader_start(root, r)
    if !beside {
      reader_keys(root, r, back)
    }
    // (what the text shows: coming, failed, empty, the column; nothing while where it was left is waited on)
    root.pick(
      fn() {
        match (r.book.get(), r.failed.get()) {
          (Some(b), _) =>
            if !r.started.get() {
              ReaderWaits
            } else if b.text.trim(chars=" \n\t\r\u{3000}").to_owned() == "" {
              ReaderEmpty
            } else {
              ReaderReads
            }
          (None, Some(_)) => ReaderFailed
          (None, None) => ReaderComing
        }
      },
      fn(p, now) {
        p.over(Is(true)) |> ignore
        match now {
          ReaderWaits => ()
          ReaderComing => reader_coming_node(p, r, paper)
          ReaderFailed =>
            reader_note_node(p, fn() { t("web-pages.drive.reader.failed", args=[("error", r.failed.get().unwrap_or(""))]) }, paper)
          ReaderEmpty => reader_note_node(p, fn() { t("web-pages.drive.reader.empty") }, paper)
          ReaderReads =>
            match r.book.untracked() {
              Some(book) => reader_column_node(p, r, book, beside, ems, wide, small, paper)
              None => ()
            }
        }
      },
      at_once=true,
    )
    // its chrome, by where it is (the window's tier, a tab)
    if beside {
      reader_beside_chrome(root, r, paper, wide, tab_w)
    } else {
      // (a phone's or a desktop's, by the window's tier: each made once, the other kept at rest while the window is of
      // the other tier and taken in again as it comes back to its own, never made anew for a window resized across)
      root.each(
        fn() { [small()] },
        fn(k) { k },
        keeps=fn() { [true, false] },
        at_once=true,
        fn(c, phone) {
          c.over(Is(true)) |> ignore
          if phone.untracked() {
            reader_narrow_chrome(c, r, file, back_label, back, source, paper, tab_w)
          } else {
            reader_desk_chrome(c, r, file, back_label, back, move_beside, source, paper, tab_w)
          }
        },
      )
    }
  })
}

///|
/// What a reader's text shows (reader_node's): opened where it was left once that is said (or not waited on any
/// longer), coming, failed, empty, the column.
#derive(Eq)
priv enum ReaderShows {
  ReaderWaits
  ReaderComing
  ReaderFailed
  ReaderEmpty
  ReaderReads
}

///|
/// Reading `r` opened where it was left, in `root`'s time: as its book is ready and its file says where it was left
/// (LeftAt, NeverLeft: at once), or once it has not said for reader_place_ms from the moment the book came (no wait for
/// a station); once.
fn reader_start(root : @view.View, r : Reading) -> Unit {
  let waits : Ref[(() -> Unit)?] = Ref(None)
  let place = fn() -> PlaceNow {
    match r.file {
      Some(f) => (f.place)()
      None => NeverLeft
    }
  }
  root.reacts(
    fn() {
      // (what it was left at, as a value: the book ready, and where; asked no more once opened, what it read let go)
      guard !r.started.get() else { return (false, (3, 0.0, 0.0)) }
      let said = match place() {
        LeftAt(at, of) => (1, at, of)
        NeverLeft => (2, 0.0, 0.0)
        NotKnown => (0, 0.0, 0.0)
      }
      (r.book.get() is Some(_), said)
    },
    fn(now) {
      guard now.0 else { return }
      guard r.book.untracked() is Some(book) else { return }
      match now.1 {
        (1, at, of) => reader_open_at(r, book, LeftAt(at, of))
        (2, _, _) => reader_open_at(r, book, NeverLeft)
        _ =>
          if waits.val is None {
            waits.val = Some(
              root.at_moment(root.cause_at() + reader_place_ms, fn() {
                match r.book.untracked() {
                  Some(b) => reader_open_at(r, b, NotKnown)
                  None => ()
                }
              }),
            )
          }
      }
    },
  )
}

///|
/// The reader's keys in `root` (a desktop's and a phone's, not a tab's): ⌘F finds, ← → a chapter back or on (where the
/// text has chapters), Esc closes what is open over the text, else lets go of the place found, else goes back (`back`);
/// each at its key's moment (reader_bindings).
fn reader_keys(root : @view.View, r : Reading, back : () -> Unit) -> Unit {
  root.key_context("Reader") |> ignore
  let chapters = fn() {
    match r.book.untracked() {
      Some(b) if b.chapters.length() >= 2 => Some(b)
      _ => None
    }
  }
  let go = fn(by : Int) {
    match chapters() {
      Some(b) => {
        let to = reader_chapter(b, r.place.untracked()) + by
        match b.chapters.get(if to < 0 { 0 } else { to }) {
          Some((_, k, o)) => reader_jump(r, k, o)
          None => ()
        }
      }
      None => ()
    }
  }
  root
  .on_action("reader.find", fn(_) {
    reader_open_panel(r, Find)
    true
  })
  .on_action("reader.chapter_back", fn(_) {
    go(-1)
    true
  }, can=fn() { chapters() is Some(_) })
  .on_action("reader.chapter_on", fn(_) {
    go(1)
    true
  }, can=fn() { chapters() is Some(_) })
  .on_action("reader.escape", fn(_) {
    if r.panel.untracked() != NoPanel {
      reader_close_panel(r)
    } else if r.hit.untracked() >= 0 {
      r.hit.set(-1)
    } else {
      back()
    }
    true
  })
  |> ignore
}

///|
/// A panel opened, at a cause (the search's field taking the keys; the contents brought to the chapter read).
pub fn reader_open_panel(r : Reading, panel : ReaderPanel) -> Unit {
  reader_panel_set(r, panel)
  if panel == Contents {
    match r.book.untracked() {
      Some(b) => {
        let chapter = reader_chapter(b, r.place.untracked())
        r.contents.bring(if chapter > desk_contents_lead { chapter - desk_contents_lead } else { 0 })
      }
      None => ()
    }
  }
  if panel == Find {
    r.search.focus()
  }
}

///|
/// The panel closed, at a cause (the search's field letting go of the keys).
pub fn reader_close_panel(r : Reading) -> Unit {
  reader_panel_set(r, NoPanel)
  r.search.let_go()
}

///|
/// A tool's panel opened, or closed again by its own tool.
fn reader_toggle_panel(r : Reading, panel : ReaderPanel) -> Unit {
  if r.panel.untracked() == panel {
    reader_close_panel(r)
  } else {
    reader_open_panel(r, panel)
  }
}

///|
/// A phone's bars shown or taken away: a tap on the text (a press, never a drag), at its moment.
fn reader_tapped(r : Reading) -> Unit {
  @view.transition(fn() { r.chrome.set(!r.chrome.untracked()) })
}

///|
/// A note in `parent` on the paper (`paper`), 30% of the way down its room: `words` as they change, in the middle.
#callsite(autofill(loc))
fn reader_note_node(parent : @view.View, words : () -> String, paper : () -> ReaderPaper, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(col) {
    col.over(Is(true)) |> ignore
    col.box(fn(g) { g.grow(Is(desk_note_down)).basis(Is(Some(0.0))) |> ignore }) |> ignore
    col.box(fn(n) {
      style_node(n, fn() { desk_note_box })
      words_node(n, words, fn() { desk_note_words.then(@ui.text_style(color=Data(paper().muted))) }) |> ignore
    })
    |> ignore
    col.box(fn(g) { g.grow(Is(desk_whole - desk_note_down)).basis(Is(Some(0.0))) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// While reading `r`'s file comes (reader_note_node's place): how much has, of how much, over a bar that fills as it
/// comes (sweeps while how much is not said).
#callsite(autofill(loc))
fn reader_coming_node(parent : @view.View, r : Reading, paper : () -> ReaderPaper, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(col) {
    col.over(Is(true)) |> ignore
    col.box(fn(g) { g.grow(Is(desk_note_down)).basis(Is(Some(0.0))) |> ignore }) |> ignore
    col.box(fn(n) {
      style_node(n, fn() { desk_note_box })
      words_node(
        n,
        fn() {
          match r.got.get() {
            Some(g) => t("web-pages.drive.reader.reading", args=[("got", file_size(g.loaded)), ("of", file_size(g.total))])
            None => t("common.opening")
          }
        },
        fn() { desk_note_words.then(@ui.text_style(color=Data(paper().muted))) },
      )
      |> ignore
      n.box(fn(track) {
        track.width(Is(Some(desk_load_w))) |> ignore
        progress_node(
          track,
          fn() {
            match r.got.get() {
              Some(g) if g.total > 0.0 => Some(g.loaded / g.total)
              _ => None
            }
          },
          fn() { @ui.tree_theme().line },
          fn() { theme().p.accent },
        )
        |> ignore
      })
      |> ignore
    })
    |> ignore
    col.box(fn(g) { g.grow(Is(desk_whole - desk_note_down)).basis(Is(Some(0.0))) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The column of text (column, TextBody / MarkdownBody) in `parent`: `book`'s blocks a page's list's, each in the
/// reader's size, lines, margins and face, as wide as a line reads well (34 of its size, and the margins) in the middle
/// of what the panel leaves (on 大屏 and 中屏, where one is open; in a tab, where the tab has room for both); from under
/// the bar (or the tab's top, or a phone's status bar) and over the foot; a note under a text cut at reader_most. Where
/// the top of what shows is followed (ListPlace::on_sight) and kept as it holds still; a desktop's bar told which way
/// it is read; a tap on the text takes or brings a phone's bars.
#callsite(autofill(loc))
fn reader_column_node(
  parent : @view.View,
  r : Reading,
  book : Book,
  beside : Bool,
  ems : Double,
  wide : () -> Bool,
  small : () -> Bool,
  paper : () -> ReaderPaper,
  loc~ : SourceLoc,
) -> Unit {
  let style = fn() { (viewer_host().reader_style)() }
  let room = fn() { (viewer_host().room)() }
  let n = book.chunks.length()
  let keys = Array::makei(n, fn(i) { i })
  let top = fn() {
    if beside {
      beside_reader_top
    } else if small() {
      room().0 + narrow_reader_top
    } else {
      room().0 + desk_reader_top
    }
  }
  let foot = fn() {
    if beside {
      beside_reader_top
    } else if small() {
      room().1 + narrow_reader_foot
    } else {
      room().1 + desk_reader_foot
    }
  }
  // (where the top of what shows is: told as it changes, kept as it holds still (each move a wait of its own, nothing
  // shown waiting for it); a desktop's bar gone as it is read on down, back as it is read back up, near its top)
  let keeps : Ref[() -> Unit] = Ref(fn() {  })
  r.list.on_sight(fn(s) {
    if r.sight_from == @double.infinity {
      r.sight_from = parent.cause_at()
    }
    r.long.set(s.from_top + s.from_foot > s.shows)
    let away_now = s.from_foot > reader_end_away
    if parent.cause_at() > r.sight_from {
      @view.transition(fn() { r.away.set(away_now) })
    } else {
      r.away.set(away_now)
    }
    let (first, within) = reader_held_place(r, s.first, s.into, if s.tall > 0.0 { dmin(1.0, dmax(0.0, s.into / s.tall)) } else { 0.0 })
    let (chunk, was) = r.place.untracked()
    if first != chunk || (within - was).abs() > 0.002 {
      r.place.set((first, within))
      r.moves = r.moves + 1
      (keeps.val)()
      keeps.val = parent.at_moment(
        parent.cause_at() + reader_still_ms,
        fn() {
          if r.moves > r.kept_moves {
            reader_keep(r, book)
          }
        },
        later=true,
      )
    }
    let (was_first, was_off) = r.seen
    if s.first == 0 && s.into < viewer_top_kept {
      r.bar_hidden.set(false)
    } else if s.first > was_first || (s.first == was_first && s.into - was_off > viewer_moved) {
      r.bar_hidden.set(true)
    } else if s.first < was_first || (s.first == was_first && was_off - s.into > viewer_moved) {
      r.bar_hidden.set(false)
    }
    r.seen = (s.first, s.into)
  })
  parent.box(made_for=loc, fn(col) {
    col.over(Is(true)) |> ignore
    // (a ground under the text on 小屏: a tap on it or on the words over it a phone's bars; elsewhere taking no press,
    // a mouse's press on the words picking them: under them, never round them, so what scrolls takes the wheel and the
    // hand whatever it says)
    col.box(fn(g) {
      g.over(Is(true)).presses(By(small)).on_press(fn() { reader_tapped(r) }).cursor(Is(Some(Arrow))).as_ground() |> ignore
    })
    |> ignore
    col.box(fn(l) {
      l.over(Is(true)) |> ignore
      l.scrolls_window(
        @view.Scroll::list(),
        fn() { keys },
        fn(row, k) { reader_chunk_node(row, r, book, k, ems, wide, small, style, paper) },
        est=reader_est_chars,
        slop=@ui.touch_slop(),
        bar=@ui.tree_scroll_bar(),
        place=r.list,
        // (where what is brought comes to rest (a chapter gone to, where it was left) and where what is read is counted
        // from: never under the status bar's room or a desktop's bar, nor on 小屏 under its top bar while that shows,
        // where what was found comes too (reader_narrow_chrome's))
        top_covered=fn() {
          if !beside && small() && r.chrome.get() {
            room().0 + narrow_bar_off + narrow_found_down
          } else {
            top()
          }
        },
        head=fn(h) { h.height(By(fn() { Some(top()) })) |> ignore },
        foot=fn(f) {
          // a text cut at reader_most says so under it
          if book.truncated {
            f.box(fn(cut) {
              style_node(cut, fn() { reader_cut_row })
              reader_sides(cut, r, ems, wide, style, fn(m) {
                words_node(m, fn() { t("web-pages.drive.reader.cut", args=[("size", file_size(reader_most.to_double()))]) }, fn() {
                  reader_cut_words.then(@ui.text_style(color=Data(paper().muted)))
                })
                |> ignore
              })
            })
            |> ignore
          }
          f.box(fn(g) { g.height(By(fn() { Some(foot()) })) |> ignore }) |> ignore
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// Row `row`'s room for the text in the middle (`middle`, given its node): one column as wide as a line reads well (34
/// of the size, and the margins) in the middle of what the panel leaves (desk_reader_sides): what is either side of it
/// equal, the panel's 320 kept at the end while it is open where it is beside the text (`wide`: in a tab, only where
/// the tab has room for both, beside_both_least; else the panel over the text).
#callsite(autofill(loc))
fn reader_sides(
  row : @view.View,
  r : Reading,
  ems : Double,
  wide : () -> Bool,
  style : () -> ReaderStyle,
  middle : (@view.View) -> Unit,
  loc~ : SourceLoc,
) -> Unit {
  row.row(Is(true)) |> ignore
  row.box(made_for=loc, fn(g) { g.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore }) |> ignore
  row.box(fn(m) {
    m
    .basis(Is(Some(0.0)))
    .grow(Is(reader_middle_grows))
    .shrink(Is(1.0))
    .max_width(By(fn() {
      let s = style()
      Some(ems * s.size.to_double() + 2.0 * s.margin.to_double())
    }))
    .padding(By(fn() {
      let margin = style().margin.to_double()
      (margin, 0.0, margin, 0.0)
    }))
    |> ignore
    middle(m)
  })
  |> ignore
  row.box(fn(g) { g.grow(Is(1.0)).basis(Is(Some(0.0))) |> ignore }) |> ignore
  // (the panel's room while one docked at the right is open: the layout's too)
  row.box(fn(p) { p.width(By(fn() { Some(reader_panel_room(r, wide)) })) |> ignore }) |> ignore
}

///|
/// How much of a row's end the panel takes where one is open beside the text (`wide`), else none.
fn reader_panel_room(r : Reading, wide : () -> Bool) -> Double {
  if r.panel.get() != NoPanel && wide() {
    desk_panel_w
  } else {
    desk_none
  }
}

///|
/// How much more of what a row leaves the text's column takes than the room either side of it (reader_sides): all of
/// it, but for a hair, up to as wide as it reads well.
let reader_middle_grows : Double = 1000.0

///|
/// Block `k` of `book` in `row` (TextBody's piece): its words in the reader's size, lines and face (a Markdown file's as
/// a chat's Markdown is drawn, its headings a document's), a text's heading lines in 600 and a fifth larger, the places
/// found on it marked (the one gone to stronger); what a jump to it brings marked (View::sought: where in it the offset
/// is, at its share of its height). A tap on it a phone's bars (on 小屏: `small`).
fn reader_chunk_node(
  row : @view.View,
  r : Reading,
  book : Book,
  k : Int,
  ems : Double,
  wide : () -> Bool,
  small : () -> Bool,
  style : () -> ReaderStyle,
  paper : () -> ReaderPaper,
) -> Unit {
  ignore(small)
  // (its places found, and the one gone to where it is on it: worked out as the search changes, not as it scrolls)
  let mine = @signals.computed(fn(_) { r.matches.get().filter(fn(m) { m.chunk == k }) })
  let now = @signals.computed(fn(_) {
    let all = r.matches.get()
    let h = r.hit.get()
    if h >= 0 && h < all.length() && all[h].chunk == k {
      Some(all[h])
    } else {
      None
    }
  })
  reader_sides(row, r, ems, wide, style, fn(m) {
    let words = if book.markdown {
      markdown_node(
        m,
        fn() { book.text },
        nodes=fn() { book.parts.get(k).unwrap_or([]) },
        size=fn() { style().size.to_double() },
        line=fn() { style().line },
        apart=k > 0,
        ink=fn() { paper().ink },
        document=true,
        found=fn() { if mine.get().length() > 0 { [r.searched.get()] } else { [] } },
        on_link=viewer_host().on_link,
        serif=fn() { style().face == "serif" },
      )
    } else {
      m.box(fn(w) {
        w
        .words_runs(By(fn() {
          let s = style()
          let p = paper()
          let runs = [@ui.plain(render_chunk(book.chunks[k], book.starts[k], book.heads, s.indent))]
          let runs = reader_headings(runs, book.chunks[k], book.starts[k], book.heads, s.indent)
          let found = mine.get()
          let runs = if found.length() == 0 {
            runs
          } else {
            reader_marked(
              runs,
              fn(o) { reader_drawn_offset(book, k, o, s.indent) },
              found,
              now.get(),
              alpha(p.accent, if p.dark { reader_mark_dark } else { reader_mark_light }),
              alpha(p.accent, if p.dark { reader_mark_now_dark } else { reader_mark_now_light }),
            )
          }
          // (in the serif face where the layout says so)
          if s.face == "serif" {
            runs.map(fn(x) { { ..x, serif: true } })
          } else {
            runs
          }
        }))
        .words_look(By(fn() {
          let s = style()
          let size = s.size.to_double()
          // (a line as a share of the words as drawn, the system's size of words applied first: the old view's line_em)
          { size, weight: 400, line: -s.line, wrap: true, tracking: @view.letters_own, balance: false, max_lines: 0 }
        }))
        .ink(By(fn() { paper().ink }))
        |> ignore
      })
    }
    // (what a jump to it brings: the line the offset is on, as its words are laid out (a chapter's heading at the
    // top, not a line or two past it); a Markdown block's at its share of how much of it is drawn)
    words.sought(fn() {
      match r.jump.untracked() {
        Some((jk, off, _)) if jk == k => {
          let indent = @signals.untracked(style).indent
          if off <= 0 {
            Some(fn(w, _) { Some((0.0, 0.0, w, 1.0)) })
          } else if book.markdown {
            Some(fn(w, h) {
              let len = dmax(1.0, reader_drawn_len(book, k, indent).to_double())
              Some((0.0, h * reader_drawn_offset(book, k, off, indent).to_double() / len, w, 1.0))
            })
          } else {
            let d = reader_drawn_offset(book, k, off, indent)
            let line = @ui.runs_piece(words, d, d + 1)
            Some(fn(w, h) { line(w, h).map(fn(b) { (0.0, b.1, w, 1.0) }) })
          }
        }
        _ => None
      }
    })
    |> ignore
  })
}

// ── a desktop's ─────────────────────────────────────────────────────────

///|
/// What floats over the paper on 大屏 and 中屏 in `parent`: the bar (back by name, the file's name, its chapter, how far
/// read and its size; 目录 · 搜索 · 排版 · 移到侧边 · 源码 · 下载), gone as the text is read on down while no panel is open; what
/// was found, 10 under it over the text's middle, clear of the panel; the hairline along the foot; the contents' or the
/// search's panel docked at the right under the bar (the layout's: reader_layout_nodes). The pointer at the window's
/// top brings the bar back. The bar's middle by how wide the reader is laid out (`width`, reader_node's).
#callsite(autofill(loc))
fn reader_desk_chrome(
  parent : @view.View,
  r : Reading,
  file : ViewerFile,
  back_label : () -> String,
  back : () -> Unit,
  move_beside : (() -> Bool, () -> Unit)?,
  source : (() -> Unit)?,
  paper : () -> ReaderPaper,
  width : () -> Double,
  loc~ : SourceLoc,
) -> Unit {
  let ink = fn() { paper_viewer_ink(paper()) }
  let share = fn() {
    match r.book.get() {
      Some(b) => reader_fraction(b, r.place.get())
      None => 0.0
    }
  }
  let meta = fn() {
    match r.book.get() {
      Some(b) => {
        let chapter = reader_chapter(b, r.place.get())
        joined(
          [
            if chapter >= 0 && b.chapters.length() >= 2 { b.chapters[chapter].0 } else { "" },
            "\{(share() * 100.0).round().to_int()}%",
            file_size(file.size),
          ],
          " · ",
        )
      }
      None => file_size(file.size)
    }
  }
  reader_hairline(parent, paper, share, fn(_) { 1.0 })
  // the pointer at the window's top brings the bar back (VIEWER_BAR_REACH)
  parent.box(made_for=loc, fn(reach) {
    reach.over(Is(true)) |> ignore
    reach.box(fn(z) {
      z.height(Is(Some(viewer_bar_reach))).points(Is(true)) |> ignore
      z.reacts(fn() { z.pointed() }, fn(on) { if on { r.bar_hidden.set(false) } })
    })
    |> ignore
  })
  |> ignore
  // the contents' or the search's panel, docked at the right under the bar
  parent.show(fn() { r.panel.get() == Contents || r.panel.get() == Find }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(top) { top.height(By(fn() { Some(viewer_bar_under()) })) |> ignore }) |> ignore
    reader_panel_docked(o, r, paper, None)
  })
  // what was found, under the bar over the text's middle, clear of the panel
  parent.show(fn() { r.hit.get() >= 0 && r.matches.get().length() > 0 }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(top) { top.height(By(fn() { Some(viewer_bar_under() + desk_found_gap) })) |> ignore }) |> ignore
    reader_found_row(o, r, paper, fn() { true })
  })
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = TipLayer::new(fn() { tips_at.val })
  viewer_bar_node(
    parent,
    back_label,
    fn() { file.name },
    meta,
    fn() { file.title },
    fn() { r.bar_hidden.get() && r.panel.get() == NoPanel },
    fn(_) { 1.0 },
    fn() { (viewer_host().room)().0 },
    width,
    ink,
    fn(row, corner) {
      let tool = fn(icon : String, label : String, panel : ReaderPanel) {
        tool_node(
          row,
          fn() { { icon, label: t(label), on: r.panel.get() == panel, disabled: false } },
          ink,
          corner,
          fn() { reader_toggle_panel(r, panel) },
          tip=tips,
        )
        |> ignore
      }
      tool("list", "web-pages.drive.reader.contents", Contents)
      tool("search", "web-pages.drive.reader.find", Find)
      tool("text", "web-pages.drive.reader.layout", Layout)
      // (its file to a tab beside the page, at the press's moment: what reads it let go then)
      match move_beside {
        Some((offered, f)) =>
          row.show(offered, fn(b) {
            tool_node(
              b,
              fn() { { icon: "panel-open", label: t("web-main.preview.moveBeside"), on: false, disabled: false } },
              ink,
              corner,
              f,
              tip=tips,
            )
            |> ignore
          })
        None => ()
      }
      // (源码: its text as it is written, in place of this reader)
      match source {
        Some(f) =>
          tool_node(
            row,
            fn() { { icon: "file-code", label: t("web-main.preview.source"), on: false, disabled: false } },
            ink,
            corner,
            f,
            tip=tips,
          )
          |> ignore
        None => ()
      }
      tool_node(
        row,
        fn() { { icon: "download", label: t("web-main.preview.download"), on: false, disabled: false } },
        ink,
        corner,
        fn() { (file.save)() },
        tip=tips,
      )
      |> ignore
    },
    back,
    tips,
  )
  |> ignore
  tips_at.val = Some(parent.box(fn(l) { l.over(Is(true)) |> ignore }))
}

///|
/// How far through it is in `parent` (all of its room): a hairline along the foot, `share` of it in the accent, as far
/// seen as `seen` says of it as it is drawn.
#callsite(autofill(loc))
fn reader_hairline(
  parent : @view.View,
  paper : () -> ReaderPaper,
  share : () -> Double,
  seen : (@view.View) -> Double,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(place) {
    place.over(Is(true)).lies_along(Is(End)).presses(Is(false)) |> ignore
    place.box(fn(line) {
      style_node(line, fn() { desk_hairline.then(@ui.style(bg=Data(alpha(paper().ink, desk_hairline_share)))) })
      line.alpha(By(fn() { seen(line) })) |> ignore
      line.box(fn(read) {
        read.grow(By(fn() { dmax(desk_none, share()) })).basis(Is(Some(0.0))).ground(By(fn() { alpha(paper().accent, desk_hairline_fill) })) |> ignore
      })
      |> ignore
      line.box(fn(left) { left.grow(By(fn() { dmax(desk_none, desk_whole - share()) })).basis(Is(Some(0.0))) |> ignore }) |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// What was found in a row of `parent`, over the text's middle, clear of the panel while one is open beside the text
/// (`wide`, as reader_sides has it): reader_found_node.
#callsite(autofill(loc))
fn reader_found_row(parent : @view.View, r : Reading, paper : () -> ReaderPaper, wide : () -> Bool, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(row) {
    row.row(Is(true)) |> ignore
    row.box(fn(m) {
      m.grow(Is(1.0)).basis(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
      reader_found_node(m, r, paper)
    })
    |> ignore
    row.box(fn(p) { p.width(By(fn() { Some(reader_panel_room(r, wide)) })) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// What was found and the steps through it in `parent`: 「what」 which of how many, the one before and after (none
/// before the first, none after the last), and the search let go; a capsule of the paper's raised ground, frosted.
#callsite(autofill(loc))
fn reader_found_node(parent : @view.View, r : Reading, paper : () -> ReaderPaper, loc~ : SourceLoc) -> Unit {
  let step = fn(d : Int) {
    let all = r.matches.untracked()
    let n = all.length()
    if n > 0 {
      let h = ((r.hit.untracked() + d) % n + n) % n
      r.hit.set(h)
      reader_jump(r, all[h].chunk, all[h].start, lead=true)
    }
  }
  // (the library's find in a page, without a field: what was looked for and where among it, its keys in the paper's
  // ink)
  page_find_node(
    loc~,
    parent,
    fn() {
      t("web-pages.drive.reader.foundAt", args=[
        ("query", r.searched.get()),
        ("at", "\{r.hit.get() + 1}"),
        ("n", "\{r.matches.get().length()}"),
      ])
    },
    step,
    fn(d) { if d < 0 { r.hit.get() > 0 } else { r.hit.get() < r.matches.get().length() - 1 } },
    fn() { r.hit.set(-1) },
    frame=fn(b) {
      // (a capsule now its keys are round: they stand in its ends concentric with them, 5 in)
      style_node(b, fn() { desk_found_box.then(desk_found_round) })
      b
      .glass(By(fn() { Some(narrow_pill_glass(paper())) }))
      .edge(By(fn() { if b.glass_solid() { @lg.liquid_solid_edge() } else { (0.0, 0L) } }))
      .shadow(By(fn() { glass_control_shadow() }))
      .shadow_outside(Is(true))
      .clips(Is(true))
      .presses(Is(true))
      .on_press(fn() {  })
      .as_ground()
      |> ignore
    },
    said_look=fn() { desk_found_words.then(@ui.text_style(color=Data(paper().ink))) },
    ink=fn() { paper().ink },
    prev_label=fn() { t("android-misc.drive.reader.prevHit") },
    next_label=fn() { t("android-misc.drive.reader.nextHit") },
    close_label=fn() { t("common.close") },
    key_side=desk_found_key,
  )
  |> ignore
}

///|
/// Its keys as tall as its chips were (30), and its round as a capsule's, 5 round them in its 40.
let desk_found_key : Double = 30.0

///|
// kept across runs: a value (no field of it changes)
let desk_found_round : @ui.Style = @ui.css("radius=Full")

///|
/// The contents' or the search's panel docked at the right of `parent` (a column), from where it is to its foot: the
/// text's room, then the panel 320 wide on the paper (no wider than a tab `tab()` wide), its head the title (the
/// contents' with how many chapters and how far read) and its close, then what it is.
#callsite(autofill(loc))
fn reader_panel_docked(parent : @view.View, r : Reading, paper : () -> ReaderPaper, tab : (() -> Double)?, loc~ : SourceLoc) -> Unit {
  parent.box(made_for=loc, fn(row) {
    style_node(row, fn() { desk_panel_row })
    row.box(fn(room) { style_node(room, fn() { desk_panel_room }, in_row=true) }) |> ignore
    row.box(fn(p) {
      style_node(p, fn() { desk_panel_box.then(@ui.style(bg=Data(paper().ground))) }, in_row=true)
      match tab {
        Some(w) => p.width(By(fn() { Some(dmin(desk_panel_inner, w())) })) |> ignore
        None => ()
      }
      // (a press on it its own: not the text's under it)
      ground_node(p) |> ignore
      p.box(fn(head) {
        style_node(head, fn() { desk_panel_head })
        words_node(
          head,
          fn() { if r.panel.get() == Contents { t("web-pages.drive.reader.contents") } else { t("web-pages.drive.reader.find") } },
          fn() { desk_panel_title.then(@ui.text_style(color=Data(paper().ink))) },
        )
        |> ignore
        head.box(fn(g) { style_node(g, fn() { desk_grow }, in_row=true) }) |> ignore
        head.show(fn() { r.panel.get() == Contents && reader_sheet_note(r) != "" }, fn(n) {
          words_node(n, fn() { reader_sheet_note(r) }, fn() { desk_panel_note.then(@ui.text_style(color=Data(paper().muted))) })
          |> ignore
        })
        chip_node(head, fn() { "" }, fn() { reader_close_panel(r) }, icon="close", ink=fn() { paper().ink }, said=fn() {
          t("common.close")
        })
        |> ignore
      })
      |> ignore
      p.pick(fn() { r.panel.get() == Contents }, fn(b, contents) {
        b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
        if contents {
          reader_contents_node(b, r, paper, fn() {  })
        } else {
          reader_find_node(b, r, paper, fn() {  })
        }
      }, at_once=true)
    })
    |> ignore
  })
  |> ignore
}

///|
/// The chapters in `col`: finding in the whole text first, then each chapter numbered, the one being read in the
/// accent's ink with a check; pressed, there (and `done`). None found: said so.
#callsite(autofill(loc))
fn reader_contents_node(col : @view.View, r : Reading, paper : () -> ReaderPaper, done : () -> Unit, loc~ : SourceLoc) -> Unit {
  col.box(made_for=loc, fn(top) {
    style_node(top, fn() { desk_panel_list_top })
    @headless.button(top, fn() { t("web-pages.drive.reader.findPlaceholder") }, fn(_) { reader_open_panel(r, Find) }, fn(b, s) {
      reader_row_look(b, s)
      icon_node(b, "search", desk_row_icon, By(fn() { paper().muted })) |> ignore
      words_node(b, fn() { t("web-pages.drive.reader.findPlaceholder") }, fn() {
        desk_row_words.then(@ui.text_style(color=Data(paper().muted)))
      })
      |> ignore
    })
    |> ignore
  })
  |> ignore
  let chapters = fn() {
    match r.book.get() {
      Some(b) if b.chapters.length() >= 2 => b.chapters
      _ => []
    }
  }
  col.show(fn() { chapters().length() == 0 }, fn(n) {
    style_node(n, fn() { desk_panel_note_box })
    words_node(n, fn() { t("web-pages.drive.reader.noChapters") }, fn() {
      desk_panel_note.then(@ui.text_style(color=Data(paper().muted)))
    })
    |> ignore
  })
  col.show(fn() { chapters().length() > 0 }, fn(l) {
    style_node(l, fn() { desk_panel_list })
    let chapter = @signals.computed(fn(_) {
      match r.book.get() {
        Some(b) => reader_chapter(b, r.place.get())
        None => -1
      }
    })
    l.scrolls_window(
      @view.Scroll::list(),
      fn() { Array::makei(chapters().length(), fn(i) { i }) },
      fn(row, i) {
        row.height(Is(Some(desk_row_h))) |> ignore
        let ch = fn() { chapters().get(i).unwrap_or(("", 0, 0)) }
        @headless.button(row, fn() { ch().0 }, fn(_) {
          let (_, k, o) = ch()
          reader_jump(r, k, o)
          done()
        }, fn(b, s) {
          reader_row_look(b, s)
          let now = fn() { chapter.get() == i }
          b.box(fn(num) {
            style_node(num, fn() { desk_chapter_number }, in_row=true)
            words_node(num, fn() { "\{i + 1}" }, fn() { desk_chapter_n_words.then(@ui.text_style(color=Data(paper().muted))) })
            |> ignore
          })
          |> ignore
          b.box(fn(w) {
            style_node(w, fn() { desk_grow_clip }, in_row=true)
            words_node(w, fn() { ch().0 }, fn() {
              if now() {
                desk_row_now
              } else {
                desk_row_words.then(@ui.text_style(color=Data(paper().ink)))
              }
            })
            |> ignore
          })
          |> ignore
          b.show(now, fn(c) { icon_node(c, "check", desk_check_icon, By(fn() { paper().accent })) |> ignore })
        })
        |> ignore
      },
      est=desk_row_h,
      slop=@ui.touch_slop(),
      bar=@ui.tree_scroll_bar(),
      place=r.contents,
    )
    |> ignore
  })
}

///|
/// A row of a reader's panel pressed (`b`, its state `s`: desk_row's look): a row, 12 and 10 in, 10 apart, round, the
/// tint under the hand.
fn reader_row_look(b : @view.View, s : @headless.Button) -> Unit {
  style_node(b, fn() { reader_row_box })
  reader_lit_over(b, s)
}

///|
/// The tint over what a reader's control `b` stands on (hover_ground_node's) while the hand or the keyboard is on it
/// or it is held (its state `s`, a button's or a toggle's), and `on` says so (a toggle not on already: its own ground
/// says it then).
fn[S : ReaderLit] reader_lit_over(b : @view.View, s : S, on? : () -> Bool = fn() { true }) -> Unit {
  hover_ground_node(b, on~, lit=Some(fn() { s.lit() }), color=fn() { @ui.tree_theme().color(Tint) })
}

///|
/// What of a reader's control's state lights it (reader_lit_over): the keyboard's focus shown on it, the pointer over
/// it, a finger or the pointer held on it.
priv trait ReaderLit {
  lit(Self) -> Bool
}

///|
impl ReaderLit for @headless.Button with lit(s) {
  s.focus_shown() || s.hovered() || s.pressed()
}

///|
impl ReaderLit for @headless.Toggle with lit(s) {
  s.focus_shown() || s.hovered() || s.pressed()
}

///|
/// Words to find in the file in `col`: the field (⏎ to the first place found, and `done`), how many were found, each
/// place in a line of its text (at most desk_hits_most); one pressed goes there (and `done`). The search goes
/// reader_search_ms after the last thing typed.
#callsite(autofill(loc))
fn reader_find_node(col : @view.View, r : Reading, paper : () -> ReaderPaper, done : () -> Unit, loc~ : SourceLoc) -> Unit {
  let waits : Ref[() -> Unit] = Ref(fn() {  })
  let go_first = fn() {
    let all = r.matches.untracked()
    if all.length() > 0 {
      r.hit.set(0)
      reader_jump(r, all[0].chunk, all[0].start, lead=true)
      done()
    }
  }
  col.box(made_for=loc, fn(place) {
    style_node(place, fn() { desk_find_place })
    place.box(fn(f) {
      style_node(f, fn() { desk_find_field.then(@ui.style(border_color=Data(alpha(paper().ink, desk_field_line)))) })
      @ui.field(
        f,
        r.search,
        placeholder_by=fn() { t("web-pages.drive.reader.findPlaceholder") },
        line=if theme().touch { narrow_field_line_h } else { desk_field_line_h },
        max_lines=1,
        enter_sends=true,
        size_by=fn() { if theme().touch { narrow_field_size } else { desk_field_size } },
        colors_by=fn() {
          let p = paper()
          (p.ink, p.muted, p.accent)
        },
        submitted=fn(_) { go_first() },
        edited=fn(words) {
          r.query.set(words)
          (waits.val)()
          if words.trim(chars=" ").to_owned() == "" {
            r.searched.set(words)
            r.matches.set([])
            r.hit.set(-1)
          } else {
            match r.book.untracked() {
              Some(book) =>
                waits.val = col.at_moment(col.cause_at() + reader_search_ms, fn() {
                  if r.query.untracked() == words {
                    reader_search(r, book, words)
                  }
                })
              None => ()
            }
          }
        },
      )
      |> ignore
    })
    |> ignore
  })
  |> ignore
  col.show(fn() { r.query.get().trim(chars=" ").to_owned() != "" && r.searched.get() == r.query.get() }, fn(n) {
    style_node(n, fn() { desk_panel_note_box })
    words_node(
      n,
      fn() {
        let found = r.matches.get().length()
        if found == 0 {
          t("web-pages.drive.reader.notFound")
        } else {
          t("web-pages.drive.reader.foundCount", args=[("n", "\{found}")])
        }
      },
      fn() { desk_panel_note.then(@ui.text_style(color=Data(paper().muted))) },
    )
    |> ignore
  })
  col.box(fn(l) {
    style_node(l, fn() { desk_panel_list })
    l.scrolls_window(
      @view.Scroll::list(),
      fn() {
        let n = r.matches.get().length()
        Array::makei(if n > desk_hits_most { desk_hits_most } else { n }, fn(i) { (r.searched.get(), i) })
      },
      fn(row, key) {
        let i = key.1
        let m = fn() { r.matches.get().get(i) }
        row.height(Is(Some(desk_hit_h))) |> ignore
        @headless.button(
          row,
          fn() {
            match (m(), r.book.get()) {
              (Some(x), Some(b)) => reader_snippet(b.chunks[x.chunk], x, 0L).map(fn(run) { run.text }).join("")
              _ => ""
            }
          },
          fn(_) {
            match m() {
              Some(x) => {
                r.hit.set(i)
                reader_jump(r, x.chunk, x.start, lead=true)
                done()
              }
              None => ()
            }
          },
          fn(b, s) {
            style_node(b, fn() { desk_hit_row })
            reader_lit_over(b, s)
            b.box(fn(w) {
              w
              .words_runs(By(fn() {
                match (m(), r.book.get()) {
                  (Some(x), Some(bk)) => reader_snippet(bk.chunks[x.chunk], x, paper().accent)
                  _ => []
                }
              }))
              .words_look(By(fn() { @ui.style_words(desk_hit_words) }))
              .ink(By(fn() { paper().ink }))
              |> ignore
            })
            |> ignore
          },
        )
        |> ignore
      },
      est=desk_hit_h,
      slop=@ui.touch_slop(),
      bar=@ui.tree_scroll_bar(),
    )
    |> ignore
  })
  |> ignore
}

///|
/// What floats over the paper in a tab beside a chat (reader_node's `beside`) in `parent`: the hairline; the
/// scroll-to-bottom round button (shown when taller than two screens and further than reader_end_away from its end) at
/// the tab's bottom-right (under the panel when narrow so an open panel covers it, shifted left of the docked panel
/// when wide); the contents' or search's panel at its right from its top (as wide as the tab, 320 at most); what was
/// found, 10 under the tab's top over the text's middle; and the tips layer over all of it. The tab's tools open the
/// panels; no keys (the window's are the chat's).
#callsite(autofill(loc))
fn reader_beside_chrome(
  parent : @view.View,
  r : Reading,
  paper : () -> ReaderPaper,
  wide : () -> Bool,
  tab : () -> Double,
  loc~ : SourceLoc,
) -> Unit {
  let tips_at : Ref[@view.View?] = Ref(None)
  let tips = TipLayer::new(fn() { tips_at.val })
  let share = fn() {
    match r.book.get() {
      Some(b) => reader_fraction(b, r.place.get())
      None => 0.0
    }
  }
  reader_hairline(parent, paper, share, fn(_) { 1.0 })
  // (floating scroll-to-bottom key at bottom-right; no ground on the over box so wheel and text selection pass
  // straight through to the column underneath)
  parent.box(made_for=loc, fn(o) {
    let reach = float_button_reach
    o
    .over(Is(true))
    .lies_along(Is(End))
    .lines_up(Is(Some(End)))
    .padding(By(fn() {
      (0.0, 0.0, reader_panel_room(r, wide) + beside_float_in - reach, beside_float_lift - reach)
    }))
    |> ignore
    o.show(fn() { r.long.get() && r.away.get() }, at_once=true, leave=beside_float_ms, fn(stand) {
      let settled = stand.cause_at() <= r.sight_from || @view.answering_now()
      stand.alpha(
        By(@motion.presence_in(stand, @motion.tween(beside_float_ms, ease=Out), from=if settled { 1.0 } else { 0.0 })),
      )
      |> ignore
      float_button_node(
        stand,
        "arrow-down",
        fn() { t("web-pages.drive.reader.toEnd") },
        fn() { reader_to_end(r) },
        tips~,
      )
      |> ignore
    })
  })
  |> ignore
  parent.show(fn() { r.panel.get() == Contents || r.panel.get() == Find }, fn(o) {
    o.over(Is(true)) |> ignore
    reader_panel_docked(o, r, paper, Some(tab))
  })
  parent.show(fn() { r.hit.get() >= 0 && r.matches.get().length() > 0 }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(top) { top.height(Is(Some(desk_found_gap))) |> ignore }) |> ignore
    reader_found_row(o, r, paper, wide)
  })
  tips_at.val = Some(parent.box(made_for=loc, fn(l) { l.over(Is(true)) |> ignore }))
}

// ── a phone's ───────────────────────────────────────────────────────────

///|
/// What floats over the paper on 小屏 in `parent` (Reader with a finger): the paper under the page's top bar (a phone's
/// clock and icons); nothing more till a tap on the text brings the bars, a tap taking them away (coming in 140 ms,
/// going in reader_bars_ms, eased out, a step up or down as they fade, from the tap's moment). At the top the way back,
/// the name with its chapter and how far read under it, 搜索 and 下载; at the foot the chapter with 上一章 and 下一章, a
/// track with a knob to go anywhere and how far, 目录 and 排版. While they are away, how far through it is: a hairline
/// along the foot. What was found under the top bar while it shows, at the top while it is away. The contents and the
/// search: sheets from the window's foot, on the page's own ground (the layout's: reader_layout_nodes). The bars as wide
/// as the reader is laid out (`width`, reader_node's: clear of the column of the system's bars) leaves them.
#callsite(autofill(loc))
fn reader_narrow_chrome(
  parent : @view.View,
  r : Reading,
  file : ViewerFile,
  back_label : () -> String,
  back : () -> Unit,
  source : (() -> Unit)?,
  paper : () -> ReaderPaper,
  width : () -> Double,
  loc~ : SourceLoc,
) -> Unit {
  let room = fn() { (viewer_host().room)() }
  let bars = @motion.NodeWay::new(if r.chrome.untracked() { 1.0 } else { 0.0 })
  parent.reacts(fn() { r.chrome.get() }, fn(on) {
    bars.go_ms(parent, if on { 1.0 } else { 0.0 }, if on { narrow_bars_in_ms } else { reader_bars_ms })
  })
  let shown = fn(n : @view.View) { bars.shown(n) }
  let chapters = fn() {
    match r.book.get() {
      Some(b) => b.chapters
      None => []
    }
  }
  let chapter = fn() {
    match r.book.get() {
      Some(b) => reader_chapter(b, r.place.get())
      None => -1
    }
  }
  let share = fn() {
    match r.book.get() {
      Some(b) => if r.draft.get() >= 0.0 { r.draft.get() } else { reader_fraction(b, r.place.get()) }
      None => 0.0
    }
  }
  let pct = fn() { "\{(share() * 100.0).round().to_int()}%" }
  // the page's top bar (a phone's clock and icons) on the paper, not over the text read on up under it
  parent.box(made_for=loc, fn(top) {
    top.over(Is(true)) |> ignore
    top.box(fn(b) { b.height(By(fn() { Some(room().0) })).ground(By(fn() { paper().ground })) |> ignore }) |> ignore
  })
  |> ignore
  // how far through it is while they are away (made as they go, let go once they are whole)
  parent.show(fn() { !r.chrome.get() }, leave=reader_bars_ms, fn(o) {
    o.over(Is(true)) |> ignore
    reader_hairline(o, paper, share, fn(n) { desk_whole - shown(n) })
  })
  // what was found: under the top bar while it shows, at the top while it is away
  parent.show(fn() { r.hit.get() >= 0 && r.matches.get().length() > 0 }, fn(o) {
    o.over(Is(true)) |> ignore
    o.box(fn(top) { top.height(By(fn() { Some(room().0 + narrow_bar_off) })) |> ignore }) |> ignore
    o.box(fn(row) {
      style_node(row, fn() { narrow_bar_row })
      row.offset(By(fn() { (0.0, narrow_found_down * shown(row)) })) |> ignore
      reader_found_node(row, r, paper)
    })
    |> ignore
  })
  // the top bar (made as they come, let go once they are gone)
  parent.show(fn() { r.chrome.get() }, leave=reader_bars_ms, fn(o) {
    o.over(Is(true)) |> ignore
    let top_edge_h = fn(_ : @view.View) { room().0 + narrow_bar_off + @ui.Space::px(S12) + 12.0 }
    @lg.liquid_scroll_edge_node(o, top_edge_h, top_edge_h, side=Top, bg=fn() { paper().ground }, shield=false)
    .alpha(By(fn() { shown(o) }))
    |> ignore
    o.box(fn(top) { top.height(By(fn() { Some(room().0 + narrow_bar_off) })) |> ignore }) |> ignore
    o.box(fn(row) {
      style_node(row, fn() { narrow_bar_row })
      row.box(fn(bar) {
        style_node(bar, fn() { narrow_top_box })
        bar
        .width(By(fn() { Some(dmin(width() - narrow_bar_side, narrow_top_most)) }))
        .glass(By(fn() { Some(narrow_pill_glass(paper())) }))
        .edge(By(fn() { if bar.glass_solid() { @lg.liquid_solid_edge() } else { (0.0, 0L) } }))
        .shadow(By(fn() { glass_control_shadow() }))
        .shadow_outside(Is(true))
        .clips(Is(true))
        .alpha(By(fn() { shown(bar) }))
        .offset(By(fn() { (0.0, -narrow_bars_step * (desk_whole - shown(bar))) }))
        // (gone or going, it takes no press: what is under it does)
        .presses(By(fn() { r.chrome.get() }))
        |> ignore
        // the way back (its words only on a wide screen)
        bar.box(fn(start) {
          style_node(start, fn() { narrow_top_end })
          @headless.button(start, back_label, fn(_) { back() }, fn(b, s) {
            style_node(b, fn() { narrow_back_box })
            reader_lit_over(b, s)
            icon_node(b, "chevron-left", viewer_back_icon, By(fn() { paper().ink })) |> ignore
          })
          |> ignore
        })
        |> ignore
        bar.box(fn(title) {
          style_node(title, fn() { narrow_title_box }, in_row=true)
          words_node(
            title,
            fn() {
              match r.book.get() {
                Some(b) => b.title
                None => ""
              }
            },
            fn() { narrow_title_words.then(@ui.text_style(color=Data(paper().ink))) },
          )
          |> ignore
          let small = fn() {
            match r.book.get() {
              Some(_) => {
                let ch = chapter()
                let all = chapters()
                joined([if ch >= 0 && all.length() >= 2 { all[ch].0 } else { "" }, pct()], " · ")
              }
              None => ""
            }
          }
          title.show(fn() { small() != "" }, fn(s) {
            words_node(s, small, fn() { narrow_title_small.then(@ui.text_style(color=Data(paper().muted))) }) |> ignore
          })
        })
        |> ignore
        // 源码 (where it is offered), 搜索, then 下载, as every file opened has it (the desktop's bar's last)
        bar.box(fn(end) {
          style_node(end, fn() { narrow_top_end.then(@ui.style(justify=JEnd, gap=keys_gap(size=narrow_key_side))) })
          match source {
            Some(f) =>
              @headless.button(end, fn() { t("web-main.preview.source") }, fn(_) { f() }, fn(b, s) {
                style_node(b, fn() { narrow_top_button })
                reader_lit_over(b, s)
                icon_node(b, "file-code", viewer_back_icon, By(fn() { paper().ink })) |> ignore
              })
              |> ignore
            None => ()
          }
          @headless.toggle(end, Button, fn() { t("web-pages.drive.reader.find") }, fn() { r.panel.get() == Find }, fn(_) {
            reader_toggle_panel(r, Find)
          }, fn(b, s) {
            style_node(b, fn() { narrow_top_button })
            b.ground(By(fn() { if r.panel.get() == Find { @ui.tree_theme().color(Tint) } else { no_ground } })) |> ignore
            reader_lit_over(b, s, on=fn() { r.panel.get() != Find })
            icon_node(b, "search", viewer_back_icon, By(fn() { paper().ink })) |> ignore
          })
          |> ignore
          @headless.button(end, fn() { t("web-main.preview.download") }, fn(_) { (file.save)() }, fn(b, s) {
            style_node(b, fn() { narrow_top_button })
            reader_lit_over(b, s)
            icon_node(b, "download", viewer_back_icon, By(fn() { paper().ink })) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  // the foot (as the top bar)
  parent.show(fn() { r.chrome.get() }, leave=reader_bars_ms, fn(o) {
    style_node(o, fn() { narrow_foot_place })
    o.over(Is(true)) |> ignore
    let foot_edge_h = fn(_ : @view.View) { room().1 + narrow_bar_off + 72.0 }
    @lg.liquid_scroll_edge_node(o, foot_edge_h, foot_edge_h, side=Bottom, bg=fn() { paper().ground }, shield=false)
    .alpha(By(fn() { shown(o) }))
    |> ignore
    o.box(fn(row) {
      style_node(row, fn() { narrow_bar_row })
      row.box(fn(card) {
        let w = fn() { dmin(width() - narrow_bar_side, narrow_foot_most) }
        style_node(card, fn() { narrow_foot_box })
        card
        .width(By(fn() { Some(w()) }))
        .glass(By(fn() { Some(narrow_panel_glass(paper())) }))
        .edge(By(fn() { if card.glass_solid() { @lg.liquid_overlay_solid_edge() } else { (0.0, 0L) } }))
        .shadow(By(fn() { glass_overlay_shadow() }))
        .shadow_outside(Is(true))
        .clips(Is(true))
        .alpha(By(fn() { shown(card) }))
        .offset(By(fn() { (0.0, narrow_bars_step * (desk_whole - shown(card))) }))
        .presses(By(fn() { r.chrome.get() }))
        |> ignore
        // its chapter, with 上一章 and 下一章
        card.show(fn() { chapters().length() > 0 }, fn(c) {
          style_node(c, fn() { narrow_chapter_row })
          let to = fn(by : Int) {
            match r.book.untracked() {
              Some(b) =>
                match b.chapters.get(reader_chapter(b, r.place.untracked()) + by) {
                  Some((_, ck, co)) => reader_jump(r, ck, co)
                  None => ()
                }
              None => ()
            }
          }
          let ink = fn() { paper().ink }
          chip_node(c, fn() { t("web-pages.drive.reader.prevChapter") }, fn() { to(-1) }, ink~, capsule=true, disabled=fn() {
            chapter() <= 0
          })
          |> ignore
          c.box(fn(m) {
            style_node(m, fn() { desk_grow_middle.then(@ui.style(clip=true)) }, in_row=true)
            words_node(
              m,
              fn() {
                let all = chapters()
                let ch = chapter()
                if ch >= 0 {
                  all[ch].0
                } else {
                  all.get(0).map(fn(x) { x.0 }).unwrap_or("")
                }
              },
              fn() { narrow_chapter_words.then(@ui.text_style(color=Data(paper().muted))) },
            )
            |> ignore
          })
          |> ignore
          chip_node(c, fn() { t("web-pages.drive.reader.nextChapter") }, fn() { to(1) }, ink~, capsule=true, disabled=fn() {
            chapter() >= chapters().length() - 1
          })
          |> ignore
        })
        // the track, and how far
        card.box(fn(tr) {
          style_node(tr, fn() { narrow_track_row })
          tr.box(fn(k) {
            style_node(k, fn() { narrow_track_box }, in_row=true)
            slider_node(
              k,
              fn() { t("web-pages.drive.reader.position") },
              share,
              desk_none,
              desk_whole,
              narrow_track_step,
              fn() { { ..paper(), ground: paper().raised } },
              fn(v) { r.draft.set(v) },
              fn(to) {
                r.draft.set(-1.0)
                match r.book.untracked() {
                  Some(b) if b.length > 0 && b.chunks.length() > 0 => {
                    let (chunk, offset) = b.at((to * b.length.to_double()).round().to_int())
                    reader_jump(r, chunk, offset)
                  }
                  _ => ()
                }
              },
            )
          })
          |> ignore
          tr.box(fn(p) {
            style_node(p, fn() { narrow_percent_box })
            words_node(p, pct, fn() { narrow_percent_words.then(@ui.text_style(color=Data(paper().ink))) }) |> ignore
          })
          |> ignore
        })
        |> ignore
        // 目录 and 排版, each a third of its row
        card.box(fn(tools) {
          style_node(tools, fn() { narrow_tools })
          let third = fn() { (w() - 2.0 * narrow_foot_in - 2.0 * narrow_tools_gap) / 3.0 }
          narrow_tool_node(tools, r, "list", "web-pages.drive.reader.contents", Contents, third, paper)
          narrow_tool_node(tools, r, "text", "web-pages.drive.reader.layout", Layout, third, paper)
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
    o.box(fn(g) { g.height(By(fn() { Some(room().1 + narrow_foot_off) })) |> ignore }) |> ignore
  })
  reader_sheets(parent, r, paper)
}

///|
/// How fine a phone's track goes (a thousandth of the whole).
let narrow_track_step : Double = 0.001

///|
/// A tool of a phone's foot in `row`: its icon over its name, a third of the row (`w`), 50 high; its ground the ink at
/// 7% while what it opens (`panel`) is open, the tint under the hand; round as the foot's corner is in it. Pressed, it
/// opens it.
#callsite(autofill(loc))
fn narrow_tool_node(
  row : @view.View,
  r : Reading,
  icon : String,
  label : String,
  panel : ReaderPanel,
  w : () -> Double,
  paper : () -> ReaderPaper,
  loc~ : SourceLoc,
) -> Unit {
  @headless.toggle(made_for=loc, row, Button, fn() { t(label) }, fn() { r.panel.get() == panel }, fn(_) { reader_open_panel(r, panel) }, fn(
    b,
    s,
  ) {
    style_node(b, fn() { narrow_tool_box }, in_row=true)
    b
    .width(By(fn() { Some(w()) }))
    .radius(By(fn() { @ui.concentric(@ui.tree_theme().corner(Xl3), narrow_foot_in) }))
    .ground(By(fn() { if r.panel.get() == panel { alpha(paper().ink, narrow_tool_on) } else { no_ground } }))
    |> ignore
    reader_lit_over(b, s, on=fn() { r.panel.get() != panel })
    icon_node(b, icon, viewer_back_icon, By(fn() { paper().ink })) |> ignore
    words_node(b, fn() { t(label) }, fn() { narrow_tool_words.then(@ui.text_style(color=Data(paper().ink))) }) |> ignore
  })
  |> ignore
}

///|
/// The contents' and the search's sheets on 小屏 in `parent` (the layout's the window's tree's: reader_layout_nodes):
/// from the window's foot, 72% of it tall, on the page's own ground; its title (the contents' with how many chapters
/// and how far read), what it is; a pick in it closes it. Let go (dragged down, a press outside, back), the panel
/// closed.
#callsite(autofill(loc))
fn reader_sheets(parent : @view.View, r : Reading, paper : () -> ReaderPaper, loc~ : SourceLoc) -> Unit {
  ignore(paper)
  let close = fn() { reader_close_panel(r) }
  let sheet_of = fn(panel : ReaderPanel) -> PanelOf {
    let title = if panel == Contents { t("web-pages.drive.reader.contents") } else { t("web-pages.drive.reader.find") }
    {
      title,
      description: "",
      w: panel_w,
      fits: false,
      wide: false,
      live: None,
      tall: narrow_sheet_tall,
      grows: false,
      focus: panel == Find,
      ruled: false,
      fade_out_together: false,
      form: false,
      stage: false,
      above: None,
      heads_itself: true,
      side: Bottom,
      along: Start,
      offset: panel_offset,
      match_panel: 0,
      on_back: None,
      nodes: {
        body: fn(col, _) {
          col.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
          col.box(fn(head) {
            style_node(head, fn() { layout_sheet_head })
            head.box(fn(w) {
              w
              .grow(Is(1.0))
              .words(Is(title))
              .words_look(By(fn() { { ..@ui.style_words(sheet_title_words), line: -@ui.tree_theme().text_line } }))
              .ink(By(fn() { @ui.style_ink(sheet_title_words) }))
              |> ignore
            })
            |> ignore
            if panel == Contents {
              head.show(fn() { reader_sheet_note(r) != "" }, fn(n) {
                words_node(n, fn() { reader_sheet_note(r) }, fn() { desk_panel_note.then(@ui.text_style(color=Data(theme().p.muted))) })
                |> ignore
              })
            }
          })
          |> ignore
          col.box(fn(b) {
            b.grow(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            if panel == Contents {
              reader_contents_node(b, r, sheet_paper, close)
            } else {
              reader_find_node(b, r, sheet_paper, close)
            }
          })
          |> ignore
        },
        foot: None,
        hugs: false,
        hugs_centred: false,
        steps: false,
        sheet_heads: true,
        heads: false,
        top: 0.0,
        most: None,
        flush: false,
        head_end: None,
      },
    }
  }
  let sheet = fn(panel : ReaderPanel) {
    parent.box(made_for=loc, fn(layer) {
      layer.over(Is(true)).stacked(Is(0)) |> ignore
      sheet_node(
        layer,
        fn() { r.panel.get() == panel },
        fn() {
          let x = sheet_of(panel)
          [{ n: 0, x, close, from: Unanchored }]
        },
        close,
      )
    })
    |> ignore
  }
  sheet(Contents)
  sheet(Find)
}

///|
/// What a phone's contents' sheet says beside its title: how many chapters and how far read ("" none).
fn reader_sheet_note(r : Reading) -> String {
  match r.book.get() {
    Some(b) if b.chapters.length() > 0 =>
      t("web-pages.drive.reader.contentsNote", args=[
        ("n", "\{b.chapters.length()}"),
        ("read", "\{(reader_fraction(b, r.place.get()) * 100.0).round().to_int()}"),
      ])
    _ => ""
  }
}

///|
/// Single-layer liquid glass for a phone reader's floating top bar and search-hit capsules,
/// preserving the paper's opaque solid fallback under `MBUI_GLASS=solid`.
fn narrow_pill_glass(p : ReaderPaper) -> @ui.Glass {
  @lg.liquid_bar_pill_glass(solid=over(p.ground, alpha(p.raised, desk_glass_share)), sharing=true)
}

///|
/// Single-layer liquid glass for a phone reader's floating bottom control panel,
/// preserving the paper's opaque solid fallback under `MBUI_GLASS=solid`.
fn narrow_panel_glass(p : ReaderPaper) -> @ui.Glass {
  @lg.liquid_panel_glass(solid=over(p.ground, alpha(p.raised, desk_glass_share)))
}

///|
/// A tab's reader's column from its top (and as far from its foot).
let beside_reader_top : Double = 24.0

///|
/// The least a tab beside a chat is wide for a reader's panel and its text side by side (the panel's 320 and as much of
/// the text): narrower, the panel over the text.
let beside_both_least : Double = 2.0 * desk_panel_w

///|
/// A row of a reader's panel (desk_row's, the tint under the hand its look's: reader_row_look).
// kept across runs: a value (no field of it changes)
let reader_row_box : @ui.Style = @ui.css("row w=Full px=S3 py=S2_5 gap=S2_5 align=ACenter radius=Xl")
