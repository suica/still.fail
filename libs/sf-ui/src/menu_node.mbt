// A menu of the presenters' (the library's dropdown, kit's dropdown_menu and menu_panel, in the web's look) as nodes of
// the window's tree: a modal layer over the window, nothing under it dimmed, its small panel beside what opened it
// (where it was drawn as it opened: under it, `offset` off, lined up `along` it, over it where there is not the room
// under: View::beside), grown out of that side as it comes (pop_in), drawn back into it as it closes (pop_out, as kit's
// menu goes), nothing of it pressed, modal or read out from the moment it closes; its rows as menu_row draws them (as
// high as the screen's pick row at least, its icon or a choice's check in a column before its words where one has one,
// a danger's in red, one not to be chosen faint), headings and lines between parts; what it holds scrolling where it is
// taller than the window leaves it. Its rows are one roving group, the one with the focus lit: Up and Down move the
// focus along them (round past either end, as a Mac's), Home and End to the ends, letters typed (alone or with
// Shift) to the first whose words start with them (a second's worth together), shown, what holds them bringing it
// into sight; the pointer moving onto one gives it the focus, unseen. Enter, Space, a tap or a click choose one (it
// closes, then what it does goes on); a press on what of its panel cannot be chosen does nothing. Escape, back and a
// press outside close it; a secondary press outside goes on to what is under it. Opened by the keyboard, the focus on
// its first row, shown; else on its panel, nothing lit, till a key or the pointer moves it.

///|
/// A menu in `parent` while `open()` (let go of once drawn back, pop_out_ms after: closing, nothing of it pressed):
/// what `content` holds as it is now (None a line between parts: its rows, what can be chosen of them, the keys' way
/// along them and what a choice does, all from the same of it, read again as it is told changed, the menu open as it
/// was, its focus where it was), headed by `title` ("" none; none drawn over a heading of its own first, still its
/// name to a screen reader), beside what `anchor` makes in its layer (what opened it,
/// where that is drawn), `offset` off it, lined up `along` it; `by_key`: opened by the keyboard (the focus on its first
/// row); `keep_field`: opened by a finger with a field focused (kit's dropdown_menu: its input method left in place):
/// the focus left in that field, what is typed still its (View::leaves_typing), every key, the wheel and every press
/// the menu's as ever. `choose` with the item chosen, once, as it closes; `cancel` as it is closed unchosen. `shown`,
/// `gone`: as dialog_layer_node's. `side`: the side of what opened it it goes on (a submenu's beside its row:
/// submenu_row_node). Not `modal` (a submenu's, as kit's dropdown_menu's `submenu`): what is under it its own as ever,
/// a press outside its panel closing it as it goes down and going on to what it lands on; the arrow key back toward
/// what opened it (away from `side`) closing it too.
pub fn menu_node(
  parent : @view.View,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  content : () -> Array[MenuItem?],
  title : String,
  along : @ui.Along,
  offset : Double,
  by_key : Bool,
  keep_field : Bool,
  choose : (MenuItem) -> Unit,
  cancel : () -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  extras? : (Int) -> MenuExtra = fn(_) { menu_no_extra },
  min_w? : Double = menu_w,
  side? : @ui.Side = Bottom,
  modal? : Bool = true,
) -> Unit {
  menu_node_by(
    parent,
    open,
    anchor,
    content,
    title,
    along,
    offset,
    by_key,
    keep_field,
    choose,
    cancel,
    shown~,
    gone~,
    extras~,
    min_w~,
    side~,
    modal~,
    false,
  )
}

///|
/// `menu_node` whose `chosen` items are checkboxes that may be ticked several at once (read out as `MenuItemCheckbox`,
/// the menu left open after `choose` unless the caller closes `open`). `check_end`: each ticked one's check at its row's
/// end, no column before its words for it, its own mark (where it has one) first.
pub fn menu_ticks_node(
  parent : @view.View,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  content : () -> Array[MenuItem?],
  title : String,
  along : @ui.Along,
  offset : Double,
  by_key : Bool,
  keep_field : Bool,
  choose : (MenuItem) -> Unit,
  cancel : () -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  extras? : (Int) -> MenuExtra = fn(_) { menu_no_extra },
  min_w? : Double = menu_w,
  side? : @ui.Side = Bottom,
  modal? : Bool = true,
  check_end? : Bool = false,
) -> Unit {
  menu_node_by(
    parent,
    open,
    anchor,
    content,
    title,
    along,
    offset,
    by_key,
    keep_field,
    choose,
    cancel,
    shown~,
    gone~,
    extras~,
    min_w~,
    side~,
    modal~,
    true,
    check_end~,
  )
}

///|
fn menu_node_by(
  parent : @view.View,
  open : () -> Bool,
  anchor : (@view.View) -> @view.View,
  content : () -> Array[MenuItem?],
  title : String,
  along : @ui.Along,
  offset : Double,
  by_key : Bool,
  keep_field : Bool,
  choose : (MenuItem) -> Unit,
  cancel : () -> Unit,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  extras? : (Int) -> MenuExtra = fn(_) { menu_no_extra },
  min_w? : Double = menu_w,
  side? : @ui.Side = Bottom,
  modal? : Bool = true,
  ticks : Bool,
  check_end? : Bool = false,
) -> Unit {
  // (no line at either end, none twice: menu_clean_items)
  let content = fn() { menu_clean_items(content()) }
  parent.show(
    open,
    fn(layer) {
      shown()
      layer.owns(gone) |> ignore
      let t = theme()
      // (how far in it is, from the moment it opened; out from the moment it closed, back into the side it grew from,
      // as panel_node's)
      let (enter, exit) = @signals.untracked(fn() { (pop_in_for(layer), pop_out_for(layer)) })
      let (look, live) = @motion.overlay_presence(layer, enter~, exit~)
      if modal && layout(layer.window_w()) is Small {
        let rest_end = Ref(0.0)
        layer.reacts(fn() { layer.leaving() }, fn(going) {
          rest_end.val = layer.cause_at() + (if going { @motion.pop_out_ms } else { @motion.pop_ms })
        })
        presented_sheet_rest(layer, fn(_) { rest_end.val })
      }
      // (its words and icons as far in as its look says: its ground first, then they, as pop_in has it)
      let words_in = fn() { look().words }
      // (its rows that can be chosen, by their index: the one with the focus is lit; the keyboard moves the focus along
      // them, shown, the pointer onto one, unseen; Tab's one stop among them the last that had the focus, else the
      // first: @headless.menu's `roving`, Radix's roving focus)
      let rows : Map[Int, @view.View] = Map([])
      let lit = fn() {
        let mut at = -1
        for i, r in rows {
          if r.focused() {
            at = i
          }
        }
        at
      }
      let light = fn(i : Int) {
        match rows.get(i) {
          Some(r) => r.ask_focus(visible=true) |> ignore
          None => ()
        }
      }
      // (said once: the first choice, or a close)
      let said = Ref(false)
      let go = fn(i : Int) {
        // (what it holds now: what the row pressed shows)
        match @signals.untracked(content).get(i) {
          Some(Some(item)) if !item.disabled && !item.heading && !said.val => {
            // (one taken closes it; one of several ticked leaves it open to tick the next: said again)
            if !ticks {
              said.val = true
            }
            choose(item)
          }
          _ => ()
        }
      }
      // (letters typed together, and when the last was)
      let typed = Ref("")
      let typed_at = Ref(-1.0e9)
      // (its panel, once made, and what opened it: what a press outside it is outside of, where it is not modal)
      let panel : Ref[@view.View?] = Ref(None)
      let opener : Ref[@view.View?] = Ref(None)
      // (said before it is modal: the field the focus is in kept as the layer takes what is under it, never cleared)
      if keep_field {
        // (what is typed the field's it leaves the focus in: kit's dropdown_menu's initial focus none)
        layer.leaves_typing() |> ignore
      }
      layer
      .over(Is(true))
      // (modal while open: closing, what is under it its own again as it begins to go;
      // leaving nodes with left_at >= 0.0 are hidden from semantics by the framework)
      .modal(By(fn() { modal && live() }))
      .held_back_goes_on()
      |> ignore
      if !modal {
        // (a press anywhere in the window outside its panel: closed as it goes down, the press what it lands on's as
        // ever, at that moment)
        layer.reacts(fn() { layer.window_downs() }, at_start=false, fn(_) {
          let (x, y) = layer.window_down_point()
          // (on its panel or on what it holds, or on what opened it (its own press its own): what a press there is for,
          // as the tree is now)
          let on = fn(v : @view.View?) {
            match v {
              Some(p) =>
                match p.tree.target_at(x, y) {
                  Pressed(id) | Dragged(id) => p.tree.holds(p.id(), id)
                  _ => false
                }
              None => false
            }
          }
          let inside = on(panel.val) || on(opener.val)
          if @signals.untracked(live) && !inside {
            cancel()
          }
        })
      }
      // (not modal: the key back toward what opened it)
      let back = match side {
        Right => @ui.key_code_left
        Left => @ui.key_code_right
        _ => -1
      }
      if modal {
        layer
        // (a press outside its panel its own, nothing under it pressed: closing it as it goes down, as the old frame's
        // menu is dismissed then; not modal, the press under it's, nothing said of presses on the layer)
        .presses(Is(true))
        .on_drag(fn(d) {
          if d.kind == Down && @signals.untracked(live) {
            cancel()
          }
        })
        // (a secondary press outside closes the menu and asks what is under it for its own menu at that same press)
        .on_menu(fn(m) {
          let inside = match panel.val {
            Some(p) =>
              match p.tree.target_at(m.wx, m.wy) {
                Pressed(id) | Dragged(id) => p.tree.holds(p.id(), id)
                _ => false
              }
            None => false
          }
          if @signals.untracked(live) && !inside {
            cancel()
            layer.menu_behind(m)
          }
        })
        |> ignore
      }
      layer
      .on_key(fn(k) {
        if !@signals.untracked(live) {
          return false
        }
        let now = @signals.untracked(lit)
        let items = @signals.untracked(content)
        if k.code == @ui.key_escape {
          cancel()
          true
        } else if !modal && k.mods == 0 && k.code == back {
          cancel()
          true
        } else if keep_field && now < 0 {
          // (the focus still in the field it was opened by: no key of the menu's moves it into the menu, nor reaches
          // the field, as kit's menu takes none while the focus is not in it; once a mouse has brought it to a row,
          // its keys as ever)
          true
        } else if k.mods != 0 && !(k.mods == @ui.mod_shift_key && typed_char(k.code) is Some(_)) {
          // (with Ctrl, Alt, Cmd or Shift held, its keys none of the menu's, as kit's menu takes them bare alone
          // (but a letter with Shift, typed); Escape closes it whatever is held)
          false
        } else if k.code == @ui.key_code_down || k.code == @ui.key_code_up {
          // (the focus in the menu, @headless.menu's: these where it is not, the pointer having opened it beside a
          // field, the keys none of the field's)
          let down = k.code == @ui.key_code_down
          // (from nothing lit, Down to the first and Up to the last; on from one, round past either end to the other, as a
          // Mac's menus go: the owner, 2026-11-16, 照苹果的来)
          let first = first_live(items, 0, 1)
          let last = first_live(items, items.length() - 1, -1)
          let next = if now < 0 {
            if down { first } else { last }
          } else {
            match first_live(items, now + (if down { 1 } else { -1 }), if down { 1 } else { -1 }) {
              -1 => if down { first } else { last }
              n => n
            }
          }
          light(next)
          true
        } else if k.code == @ui.key_code_home || k.code == @ui.key_code_end {
          light(if k.code == @ui.key_code_home { first_live(items, 0, 1) } else { first_live(items, items.length() - 1, -1) })
          true
        } else if k.code == @ui.key_code_enter || k.code == @ui.key_of_char(' ') {
          if now >= 0 {
            go(now)
          }
          true
        } else {
          // (a letter or digit alone or with Shift, as kit's typeahead takes them: never with Ctrl, Alt or Cmd)
          match (if k.mods == 0 || k.mods == @ui.mod_shift_key { typed_char(k.code) } else { None }) {
            Some(ch) => {
              // (a second's worth together: the same letter again moves on to the next it starts)
              let s = if k.at < typed_at.val + @headless.typeahead_ms { typed.val + ch.to_string() } else { ch.to_string() }
              typed.val = s
              typed_at.val = k.at
              match typeahead_to(items, s, now) {
                -1 => ()
                n => light(n)
              }
              true
            }
            None => false
          }
        }
      })
      .takes_back(fn() {
        if @signals.untracked(live) {
          cancel()
        }
      })
      |> ignore
      // (what opened it, where it is drawn: what its panel goes beside)
      let at = anchor(layer)
      opener.val = Some(at)
      // (a column before every item's words where one has an icon or is one of a choice: the web's dropdown)
      let iconed = fn() { content().iter().any(fn(x) { x is Some(i) && i.chosen is None && i.icon != "" }) }
      // (none for a check said to go at its row's end)
      let lead = fn() { iconed() || (!check_end && content().iter().any(fn(x) { x is Some(i) && i.chosen is Some(_) })) }
      let gap = fn() { if lead() && !iconed() { chooser_gap } else { menu_gap } }
      // (how far in a heading's words are: past the check's or icon's column, and a mark's where a row has one, as the
      // dropdown's heading_look has them)
      let marked = fn() {
        let n = content().length()
        let mut any = false
        let items = content()
        for i in 0..<n {
          let leads = match items[i] {
            Some(it) => menu_mark_leads(it, extras(i), check_end~)
            None => false
          }
          if extras(i).mark is Some(_) && !(leads && lead()) {
            any = true
          }
        }
        any
      }
      let past = fn() {
        (if lead() { menu_check_w + gap() } else { 0.0 }) + (if marked() { menu_check_w + gap() } else { 0.0 })
      }
      let reach = menu_row_reach(t.rows.pick)
      let first_row = fn() {
        let items = content()
        items.length() > 0 && (items[0] is Some(i) && !i.heading) && title == ""
      }
      let last_row = fn() {
        let items = content()
        items.length() > 0 && (items[items.length() - 1] is Some(i) && !i.heading)
      }
      anchored_popover_bridge(layer, at, look, side~, along~, offset~)
      layer.box(fn(p) {
        panel.val = Some(p)
        // (what it is to the keys and a screen reader: @headless.menu, in its own node; the focus its own as it opens by
        // the pointer, no key pressing it, one of its two stops of Tab's, its rows the other; Escape, and not modal the
        // arrow back, closing it while the focus is in it, the layer's keys closing it otherwise)
        @headless.menu(
          p,
          label=fn() { title_plain(title) },
          on_close=fn() {
            if @signals.untracked(live) {
              cancel()
            }
          },
          close_key?=if !modal && back >= 0 { Some(back) } else { None },
          takes_focus=true,
          roving=true,
          in_node=true,
          fn(p, menu) {
            anchored_popover_shell(p, at.id(), look, side~, along~, offset~, holds_side=false)
            .min_width(Is(Some(min_w)))
            .max_width(By(fn() { Some(over_room(layer).0 - 16.0) }))
            .max_height(By(fn() { Some(dmax(0.0, over_room(layer).1 - 16.0)) }))
            // (small_panel: its padding, its rows reaching past it to stand concentric with its corners)
            .padding(
              By(fn() {
                (panel_pad - reach, if first_row() { panel_pad - reach } else { panel_pad }, panel_pad - reach, if last_row() { panel_pad - reach } else { panel_pad })
              }),
            )
            |> ignore
            p.box(fn(body) {
              // (all it holds as far in as its look says, past the panel's own ground, edge and shadow: its rows, their
              // grounds, checks, marks and words, its headings and lines, the same, Look's `words` as a surface's are)
              let side = panel_pad - reach
              body.margin(Is((-side, 0.0, -side, 0.0))) |> ignore
              popover_content_motion(p, body, words_in)
              body.scrolls(@view.Scroll::new(), slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(b) {
                b.padding(Is((side, 0.0, side, 0.0))) |> ignore
                // (its title over its rows, in a heading's look: none over a heading of its own first, two headings
                // one over the other reading as one more of them; a sheet of it still titled by it, sheet_shows_node's)
                if title != "" {
                  b.show(fn() { !(content().get(0) is Some(Some(i)) && i.heading) }, fn(h) {
                    menu_heading_node(h, fn() { title }, past, reach)
                  })
                }
                // (each of what it holds by its place and its kind: one changing what it is (a line, a heading, a row) made
                // anew there; a row's words, icon, check and whether it can be chosen read again as they change, the row the
                // same, its focus kept)
                b.each(fn() { content().mapi(fn(i, x) { (i, menu_row_kind(x, ticks)) }) }, fn(k) { k }, fn(cell, k) {
                  let (i, kind) = k.untracked()
                  let item = fn() {
                    match content().get(i) {
                      Some(Some(item)) => item
                      _ => menu_none
                    }
                  }
                  match kind {
                    0 => menu_rule_node(cell, reach)
                    1 => menu_heading_node(cell, fn() { item().label }, past, reach)
                    _ => {
                      rows[i] = menu_row_node(cell, menu, item, kind, lead, gap, reach, fn() { go(i) }, extras(i), check_end~)
                      cell.owns(fn() { rows.remove(i) }) |> ignore
                    }
                  }
                })
              })
              |> ignore
            })
            |> ignore
            // (the focus given as it opens: opened by the keyboard, to its first row; else its panel; back to what had it
            // as it goes)
            let first = match rows.get(first_live(@signals.untracked(content), 0, 1)) {
              Some(r) if by_key => r
              _ => p
            }
            // (the focus given as it opens; or, by a finger beside a field, left in that field, what had it given back as it
            // goes all the same: View::focus_returns)
            if keep_field {
              layer.focus_returns() |> ignore
            } else {
              layer.focus_opens(first) |> ignore
            }
          },
        )
        |> ignore
      })
      |> ignore
    },
    leave=@motion.pop_out_ms,
  )
}

///|
/// Whether a row's own mark goes in the menu's column before its words (where the menu has one): it has a mark and
/// neither a check nor an icon of its own for that column (a check said to go at its row's end takes none of it).
fn menu_mark_leads(item : MenuItem, extra : MenuExtra, check_end? : Bool = false) -> Bool {
  extra.mark is Some(_) && (item.chosen is None || check_end) && item.icon == ""
}

///|
/// What a menu holds at a place is, by its kind: a line (0), a heading (1), a row (2).
fn menu_kind(x : MenuItem?) -> Int {
  match x {
    None => 0
    Some(item) if item.heading => 1
    Some(_) => 2
  }
}

///|
/// What a menu (not a sheet's) holds at a place is, by its kind: a line (0), a heading (1), a row: an action (2), a
/// check (3: a choice's checkbox, or any choice of a menu ticking several), a radio (4); a row turned another kind made
/// anew, said as what it is now.
fn menu_row_kind(x : MenuItem?, ticks : Bool) -> Int {
  match x {
    Some(item) if !item.heading =>
      match item.chosen {
        Some(_) if item.checkbox || ticks => 3
        Some(_) => 4
        None => 2
      }
    _ => menu_kind(x)
  }
}

///|
/// What a row of a menu reads where its place holds nothing more (its menu holding less now, the row about to go).
let menu_none : MenuItem = {
  label: "",
  icon: "",
  danger: false,
  disabled: true,
  chosen: None,
  checkbox: false,
  heading: false,
  further: false,
  select: fn() {  },
}

///|
/// A row of a menu (menu_row's look) in `b`, an item of `menu` (@headless.menu's: an action, a check or a radio as
/// `kind` says, menu_row_kind): what `item()` is now; lit while it has the focus (its ground the pointer's or the
/// keyboard's where that is shown or the pointer is on it); the pointer moving onto it gives it the focus, unseen;
/// pressed, `go`. Its words, icon, check and whether it can be chosen as the item has them now. The row.
#callsite(autofill(loc))
fn menu_row_node(
  b : @view.View,
  menu : @headless.Menu,
  item : () -> MenuItem,
  kind : Int,
  lead : () -> Bool,
  gap : () -> Double,
  reach : Double,
  go : () -> Unit,
  extra : MenuExtra,
  check_end? : Bool = false,
  loc~ : SourceLoc,
) -> @view.View {
  let t = theme()
  let off = fn() { item().disabled }
  let label = fn() { item().label }
  let checked = fn() { item().chosen == Some(true) }
  let act = fn(_ : @view.View) { go() }
  let look = fn(r : @view.View, _ : @headless.MenuItem) {
    r
    .row(Is(true))
    .lines_up(Is(Some(Middle)))
    .min_height(Is(Some(t.rows.pick)))
    .padding(Is((text_in + reach, menu_row_over, text_in + reach, menu_row_over)))
    .gap(By(gap))
    .radius(Is(small_panel_inner(r_menu)))
    // det-ok(raw-hover-ground): roving menu active bar moves at once across items without trailing fade
    .ground(By(fn() { if r.focused() && (r.focus_shown() || r.pointed()) { library_theme().p.hover } else { 0L } }))
    |> ignore
    // (the pointer moved onto it or over it: the focus its, unseen, as kit's menu has it (hovered and the pointer moved);
    // come under a pointer that stays still (what holds it scrolled to bring another into sight), nothing)
    r.on_pointer_moved(fn() {
      if !@signals.untracked(off) {
        r.ask_focus() |> ignore
      }
    })
    |> ignore
    // (its own mark in that column where it has no check nor icon of its own to go there: a Slack account among kinds
    // of secret by their icons; one beside a check or an icon goes after it)
    let mark_leads = fn() { menu_mark_leads(item(), extra, check_end~) && lead() }
    // (that mark, as wide as the check's column, where it goes)
    let mark_in = fn(at : @view.View, m : ChoiceMark) { choice_mark_node(at, m, menu_check_w) }
    // (its first line: its column before its words, where the menu has one (a choice's check, or its icon, else its
    // own mark), its own mark after it otherwise, its words, and its value pushed to its end)
    let first_line = fn(into : @view.View) {
      into.show(lead, fn(col) {
        col.width(Is(Some(menu_check_w))).lines_up(Is(Some(Middle))) |> ignore
        match extra.mark {
          Some(m) if menu_mark_leads(@signals.untracked(item), extra, check_end~) => mark_in(col, m)
          _ => ()
        }
        let mark = fn() {
          let it = item()
          match it.chosen {
            // (at its row's end where the menu says so: none here)
            Some(true) => if check_end { "" } else { "\u{1}check" }
            Some(false) => ""
            None => it.icon
          }
        }
        col.each(fn() { if mark() == "" { [] } else { [mark()] } }, fn(m) { m }, fn(slot, m) {
          let name = m.untracked()
          if name == "\u{1}check" {
            icon_node(slot, "check", 14.0, By(fn() { library_theme().p.text })) |> ignore
          } else {
            icon_node(slot, name, 14.0, By(fn() {
              let p = library_theme().p
              if item().danger {
                if off() { p.subtle } else { p.red }
              } else {
                p.muted
              }
            }))
            |> ignore
          }
        })
      })
      // (its own mark (a station's, a maker's) after that column)
      match extra.mark {
        Some(m) => into.show(fn() { !mark_leads() }, fn(at) { mark_in(at, m) })
        None => ()
      }
      into.box(fn(w) {
        w
        .words(By(fn() { item().label }), look=toast_words_look(Ui, L5, 400, false))
        .ink(By(fn() { @ui.tree_theme().color(if off() { Subtle } else if item().danger { Danger } else { Fg }) }))
        |> ignore
      })
      |> ignore
      if extra.value != "" {
        into.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
        into.box(fn(w) {
          w
          .words(Is(extra.value), look=toast_words_look(Meta, L5, 400, false))
          .ink(By(fn() { @ui.tree_theme().color(Muted) }))
          |> ignore
        })
        |> ignore
      }
      // (what stands at its end beside its item (a place's ＋), pushed there)
      match extra.end {
        Some(e) => {
          into.box(fn(s) { s.grow(Is(1.0)) |> ignore }) |> ignore
          menu_end_node(into, r, e)
        }
        None => ()
      }
      // (ticked, its check at its end where the menu says so (a chat's 抄送: 左子健's), what it is shown in stretching
      // to the row's end)
      if check_end {
        into.show(fn() { item().chosen == Some(true) }, fn(at) {
          at.grow(Is(1.0)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Middle))) |> ignore
          icon_node(at, "check", 14.0, By(fn() { library_theme().p.text })) |> ignore
        })
      }
      // (one that asks more first: its chevron at its end, after its value where it has one)
      // (what it is shown in stretches to the row's end, as the menu is wide)
      into.show(fn() { item().further }, fn(at) {
        at.grow(Is(1.0)).row(Is(true)).lies_along(Is(End)).lines_up(Is(Some(Middle))) |> ignore
        icon_node(at, "chevron-right", 14.0, By(fn() { library_theme().p.subtle })) |> ignore
      })
    }
    if extra.note == "" {
      first_line(r)
    } else {
      // (what it is under its words, as far in as they are; what leads it by its first line: lead_by_first_line)
      r.box(fn(lines) {
        lines.grow(Is(1.0)) |> ignore
        lines.box(fn(l) {
          l.row(Is(true)).lines_up(Is(Some(Middle))).gap(By(gap)) |> ignore
          first_line(l)
        })
        |> ignore
        lines.box(fn(u) {
          u
          .padding(
            By(fn() {
              let w = (if lead() { menu_check_w + gap() } else { 0.0 }) +
                (if extra.mark is Some(_) && !mark_leads() { menu_check_w + gap() } else { 0.0 })
              (w, 0.0, 0.0, 0.0)
            }),
          )
          |> ignore
          // (its words a node of their own in it: what holds words is laid out as they are, not padded)
          u.box(fn(w) {
            w
            .words(Is(extra.note), look=toast_words_look(Meta, L5, 400, true))
            .ink(By(fn() { @ui.tree_theme().color(Muted) }))
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    }
  }
  match kind {
    3 => menu.check_item(b, label, checked, act, look, disabled=off, made_for=loc)
    4 => menu.radio_item(b, label, checked, act, look, disabled=off, made_for=loc)
    _ => menu.item(b, label, act, look, disabled=off, made_for=loc)
  }
}

///|
/// What a row of a menu has besides its item (a pick's choice's): what it is under its words (`note`), what it is at
/// now at its end (`value`), its own mark (`mark`, as wide as the column), a button of its own at its end (`end`).
pub(all) struct MenuExtra {
  note : String
  value : String
  mark : ChoiceMark?
  end : MenuEnd?
}

///|
/// A row with nothing besides its item.
let menu_no_extra : MenuExtra = { note: "", value: "", mark: None, end: None }

///|
/// A button at the end of a menu's row, beside what choosing the row does (a place's ＋ in the rail's menu, putting it
/// in the rail where the row goes to it): its icon (`icon`) and what it is read out as (`label`); `press`, what pressing
/// it does, the row not chosen.
pub(all) struct MenuEnd {
  label : String
  icon : String
  press : () -> Unit
}

///|
/// End `e` of menu row `row` in `into` (its first line): a round button 24 across in the row's capsule end
/// (menu_row_end), its icon 14, muted, in the words' ink with the hover's ground under the hand; shown while the row
/// is pointed at or its focus shown, the pointer on it, or always to a finger (which hovers over nothing), faded in and
/// out from the moment that changes (nav_fade), taking presses only while it shows (@headless.hover_reveal).
#callsite(autofill(loc))
fn menu_end_node(into : @view.View, row : @view.View, e : MenuEnd, loc~ : SourceLoc) -> Unit {
  @headless.button(made_for=loc, into, fn() { e.label }, fn(_) { (e.press)() }, fn(k, _) {
    style_node(k, fn() { menu_end_box }, in_row=true)
    let reveal = @headless.hover_reveal(row, k, always=fn() { !pointer_rests() || (row.focused() && row.focus_shown()) })
    let way = @motion.NodeWay::new(if @signals.untracked(fn() { reveal.shown() }) { 1.0 } else { 0.0 })
    k.reacts(fn() { reveal.shown() }, at_start=false, fn(on) { way.go(k, if on { 1.0 } else { 0.0 }, nav_fade) })
    hover_ground_node(k)
    k.box(fn(i) {
      i.alpha(By(fn() { way.shown(i) })) |> ignore
      icon_node(i, e.icon, menu_end_icon, By(fn() {
        let p = library_theme().p
        if lit_node(k) {
          p.text
        } else {
          p.muted
        }
      }))
      |> ignore
    })
    |> ignore
  })
  |> ignore
}

///|
/// A menu row's end button (menu_end_node): 24 round, its icon in its middle, in the row's capsule end, concentric
/// with it (menu_row_end).
// kept across runs: a value (no field of it changes)
let menu_end_box : @ui.Style = @ui.css("w=S6 h=S6 radius=Full align=ACenter justify=JCenter").then(menu_row_end)

///|
let menu_end_icon : Double = 14.0

///|
/// A heading among a menu's items: its words (`label()`) as far in as its rows' words
/// (`past()`: past the columns before them where there are: a check's or an icon's, a mark's), small and muted, 6 over and
/// 4 under it.
#callsite(autofill(loc))
fn menu_heading_node(
  b : @view.View,
  label : () -> String,
  past : () -> Double,
  reach : Double,
  loc~ : SourceLoc,
) -> Unit {
  b.box(made_for=loc, fn(h) {
    h.padding(By(fn() { (text_in + past() + reach, 6.0, 10.0 + reach, 4.0) })) |> ignore
    h.box(fn(w) {
      // (a part of it in the accent: title_accent.mbt)
      if title_marked(@signals.untracked(label)) {
        w
        .words_runs(By(fn() { title_runs(label(), theme().p.accent_text) }))
        .words_look(Is(toast_words_look(Meta, L4_75, 400, false)))
        .ink(By(fn() { @ui.tree_theme().color(Muted) }))
        |> ignore
      } else {
        w
        .words(By(label), look=toast_words_look(Meta, L4_75, 400, false))
        .ink(By(fn() { @ui.tree_theme().color(Muted) }))
        |> ignore
      }
    })
    |> ignore
  })
  |> ignore
}

///|
/// A line between parts of a menu (menu_rule): the words' ink faintly, 1 high, 6 over and under it, as wide as its rows'
/// grounds.
#callsite(autofill(loc))
fn menu_rule_node(b : @view.View, reach : Double, loc~ : SourceLoc) -> Unit {
  b.box(made_for=loc, fn(r) {
    r.padding(Is((reach, 6.0, reach, 6.0))) |> ignore
    r.box(fn(l) { l.height(Is(Some(1.0))).ground(By(fn() { @ui.alpha(@ui.tree_theme().fg, 0.12) })) |> ignore }) |> ignore
  })
  |> ignore
}

///|
/// The first item from `from` on, going `step`, that can be chosen (not a line, a heading, nor disabled): -1 none.
fn first_live(items : Array[MenuItem?], from : Int, step : Int) -> Int {
  let mut k = from
  while k >= 0 && k < items.length() {
    match items[k] {
      Some(item) if !item.disabled && !item.heading => return k
      _ => ()
    }
    k = k + step
  }
  -1
}

///|
/// The letter or digit key `code` is (kit's typeahead's: ASCII, lower case), if it is one.
fn typed_char(code : Int) -> Char? {
  let lower = "abcdefghijklmnopqrstuvwxyz0123456789".to_array()
  let upper = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".to_array()
  for i, ch in lower {
    if code == @ui.key_of_char(ch) || code == @ui.key_of_char(upper[i]) {
      return Some(ch)
    }
  }
  None
}

///|
/// Where letters `typed` take a menu lit at `at` (kit's typeahead): the same letter again to the next item after it
/// that starts with it; more letters to the first from it that starts with them; -1 none.
fn typeahead_to(items : Array[MenuItem?], typed : String, at : Int) -> Int {
  let n = items.length()
  if n == 0 {
    return -1
  }
  let first = typed.exact_view(start=0, end=1).to_owned()
  let same = typed.iter().all(fn(ch) { ch.to_string() == first })
  let want = if same { first } else { typed }
  let from = if same { at + 1 } else if at < 0 { 0 } else { at }
  for j in 0..<n {
    let k = (from + j) % n
    match items[k] {
      Some(item) if !item.disabled && !item.heading && item.label.to_lower().has_prefix(want) => return k
      _ => ()
    }
  }
  -1
}

///|
/// The tree's Along for the library's.
fn view_along(a : @ui.Along) -> @view.Along {
  match a {
    Start => Start
    Middle => Middle
    End => End
  }
}

///|
/// What a menu goes beside at a place in the window (x, y, w, h: a point where w and h are 0), made in `layer`.
#callsite(autofill(loc))
pub fn fixed_anchor(layer : @view.View, at : (Double, Double, Double, Double), loc~ : SourceLoc) -> @view.View {
  layer.box(made_for=loc, fn(a) {
    let (x, y, w, h) = at
    a.width(Is(Some(w))).height(Is(Some(h))).offset(Is((x, y))) |> ignore
  })
}
