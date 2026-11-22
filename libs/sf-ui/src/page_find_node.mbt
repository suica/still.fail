// Finding words in what a page shows (a chat's ⌘F, a text read in the reader) as one part: what is looked for (a field
// to type it in, where the page has one there), where among what was found the reader is (m/n, or that nothing was),
// the one before and the one after, and the find let go. Its keys are the library's icon buttons (each with its tip,
// held up by a finger's long press too). Where it has its field: Enter the next, ⇧Enter the one before (the keymap's
// `find.prev` in the `Find` context), Escape lets the find go.

///|
/// Single-layer iOS 26/27 liquid glass for floating find bars (`find_bar_node`), degrading cleanly to `panel_ground()`
/// under `MBUI_GLASS=solid`.
pub fn find_panel_glass() -> @ui.Glass {
  @lg.liquid_panel_glass(solid=panel_ground())
}

///|
/// Single-layer floating liquid glass for search capsules (`search_field_node`, `search_page_node`), degrading to
/// the theme's subtle tinted ground under `MBUI_GLASS=solid`.
pub fn search_capsule_glass(solid? : Int64) -> @ui.Glass {
  let t = theme()
  let fallback = match solid {
    Some(c) => c
    None => over(t.p.bg, alpha(t.p.text, 0.06))
  }
  @lg.liquid_floating_glass(solid=fallback)
}

///|
/// Top-edge progressive blur soft scroll-edge backdrop backed by `@lg.liquid_scroll_edge_node`.
#callsite(autofill(loc))
pub fn top_scroll_edge_node(
  parent : @view.View,
  base_h : (@view.View) -> Double,
  fade_h : (@view.View) -> Double,
  bg? : () -> Int64 = fn() { theme().p.bg },
  shield? : Bool = true,
  loc~ : SourceLoc,
) -> @view.View {
  @lg.liquid_scroll_edge_node(parent, base_h, fade_h, side=Top, bg~, shield~, loc~)
}

///|
/// What finds in a page in `parent`: a row (`frame` its look and its room, said by the page) of, where `field` is given,
/// a line to type what is looked for in (`placeholder_by` while empty, `edited` told its words as the person changes them;
/// Enter: `step(1)`; ⇧Enter: `step(-1)`; Escape: `close`), what `said()` says of where the reader is among what was
/// found while it says something (in `said_look`), then the one before (`step(-1)`, while `has(-1)`), the one after
/// (`step(1)`, while `has(1)`) and the find let go (`close`): round keys `key_side` across, their icons 16, `ink` under
/// the hand, their tips in `tips`, named `prev_label`, `next_label` and `close_label`. `field_in`: how far in the
/// field's words stand past what `frame` leaves the row (a capsule whose ends hold its keys concentric: its words clear
/// of the round end, the row's own room even at both ends). The row's node.
#callsite(autofill(loc))
pub fn page_find_node(
  parent : @view.View,
  said : () -> String,
  step : (Int) -> Unit,
  has : (Int) -> Bool,
  close : () -> Unit,
  field? : @ui.Field,
  placeholder_by? : () -> String = fn() { "" },
  edited? : (String) -> Unit,
  frame? : (@view.View) -> Unit = fn(_) {  },
  said_look? : () -> @ui.TextStyle = fn() { page_find_said },
  field_size? : Double = page_find_field_size,
  field_line? : Double = page_find_field_line,
  colors_by? : () -> (Int64, Int64, Int64) = fn() {
    let p = theme().p
    (p.text, p.muted, p.accent)
  },
  ink? : () -> Int64 = fn() { theme().p.text },
  tips? : TipLayer,
  key_side? : Double = page_find_key_side,
  prev_label? : () -> String = fn() { t("web-main.find.prev") },
  next_label? : () -> String = fn() { t("web-main.find.next") },
  close_label? : () -> String = fn() { t("web-main.find.close") },
  field_in? : Double = 0.0,
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    b.row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
    frame(b)
    match field {
      Some(f) => {
        // (⇧Enter: the one before, as it comes, before the field takes it as its Enter; Escape: the find let go)
        b
        .key_context("Find")
        .on_action("find.prev", fn(_) {
          step(-1)
          true
        })
        .on_key(fn(k) {
          if k.code == @ui.key_escape && k.mods == 0 {
            close()
            true
          } else {
            false
          }
        })
        |> ignore
        let at = if field_in > 0.0 {
          b.box(fn(w) {
            w
            .row(Is(true))
            .lines_up(Is(Some(Middle)))
            .padding(Is((field_in, 0.0, 0.0, 0.0)))
            .grow(Is(1.0))
            .basis(Is(Some(0.0)))
            .shrink(Is(1.0))
            .min_width(Is(Some(0.0)))
            |> ignore
          })
        } else {
          b
        }
        @ui.field(
          at,
          f,
          placeholder_by~,
          font_size=field_size,
          line=field_line,
          max_lines=1,
          enter_sends=true,
          colors_by~,
          // Enter: the next one, as it is pressed
          submitted=fn(_) { step(1) },
          edited?,
        )
        .grow(Is(1.0))
        .basis(Is(Some(0.0)))
        .shrink(Is(1.0))
        .min_width(Is(Some(0.0)))
        |> ignore
      }
      None => ()
    }
    // which of how many, or none, while it says so
    b.show(fn() { said() != "" }, fn(n) {
      style_node(n, fn() { page_find_said_box }, in_row=true)
      n.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
      words_node(n, said, said_look) |> ignore
    })
    // (as far apart as makes each a press's room across: keys_row)
    b.box(fn(k) {
      style_node(k, fn() { keys_row(size=key_side) }, in_row=true)
      icon_button_node(k, "chevron-up", prev_label, fn() { step(-1) }, tips?, size=key_side, ink~, disabled=fn() {
        !has(-1)
      })
      |> ignore
      icon_button_node(k, "chevron-down", next_label, fn() { step(1) }, tips?, size=key_side, ink~, disabled=fn() {
        !has(1)
      })
      |> ignore
      icon_button_node(k, "close", close_label, close, tips?, size=key_side, ink~) |> ignore
    })
    |> ignore
  })
}

///|
/// Its keys' side (find_button's 26) and its field's words (14 on 20).
pub let page_find_key_side : Double = 26.0

///|
let page_find_field_size : Double = 14.0

///|
let page_find_field_line : Double = 20.0

///|
/// What it says of where the reader is: 6 in at either side, the meta's size, muted, on one line.
// kept across runs: a value (no field of it changes)
let page_find_said_box : @ui.Style = @ui.css("px=S1_5")

///|
// kept across runs: a value (no field of it changes)
let page_find_said : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false)
