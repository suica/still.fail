// A notice over the composer (the old composer's composer_notice) as a node of the window's tree, made once: a capsule
// on the composer's glass, 8 over it, its ends drawn in so its mark stands over the composer's ＋ in the middle of its
// round start; its words quiet; what it offers at its end, a step heavier, or a × concentric with its round end, or a
// choice among a few in a quiet chooser, beside its words where the line has the room for both, else on the line under
// them where its words begin (the row wrapping as it is laid out, nothing measured by hand); why what it offered failed
// under its words, red. Round as a line of it is high: a capsule while its words fit one line; wrapped, its corners
// still that round start, its mark on its first line.

///|
/// What a notice offers at its end (its words, its name for what reads the screen, whether it is out of reach) and
/// what a press on it does.
pub(all) struct NoticeOffer {
  words : () -> String
  name : () -> String
  off : () -> Bool
  press : () -> Unit
}

///|
/// What a notice lets be chosen at its end: its `choices` (each its id and words), the one `chosen`, what `choose` is
/// given as one is picked, and `on_open`, told as its menu opens and shuts.
pub(all) struct NoticeChoice {
  choices : () -> Array[(String, String)]
  chosen : () -> String
  choose : (String) -> Unit
  on_open : ((Bool) -> Unit)?
}

///|
/// The notice in `parent`: its mark (`mark()`: an icon's name; "updating", the update's mark turning), what it says
/// (`said`; `summary`, where said, its status and its detail as separate words in place of it), what it offers
/// (`offer`), its × (`dismiss`: named by its offer's `name`, out of reach by its `off`), or its `choice` (NoticeChoice:
/// out of reach while `held`); `failed`: why what it
/// offered failed ("" none). `plus_mid`: how far in from its start the middle of the composer's ＋ is, where its mark
/// stands. Its tips in `tips`. The capsule's node.
#callsite(autofill(loc))
pub fn composer_notice_node(
  parent : @view.View,
  tips : TipLayer,
  mark : () -> String,
  said : () -> String,
  plus_mid : () -> Double,
  summary? : () -> (String, String)?,
  offer? : NoticeOffer,
  dismiss? : NoticeOffer,
  choice? : NoticeChoice,
  held? : () -> Bool = fn() { false },
  failed? : () -> String = fn() { "" },
  loc~ : SourceLoc,
) -> @view.View {
  // (a line of it: its words' line and its padding; its mark in a square that high at its start)
  let side = fn() { theme().t.meta_line + 2.0 * notice_pad }
  // (its first line: what stands beside its words stands on it, never in the middle of what wraps under it. As high as
  // its words' line; with a choice, as its chooser is (28); with a ×, a line and its padding, the × as round as its end,
  // concentric with it)
  let with_x = dismiss is Some(_)
  let with_choice = choice is Some(_)
  let head = fn() {
    let line = theme().t.meta_line
    if with_x {
      side()
    } else if with_choice {
      dmax(line, @ui.Space::S7.px())
    } else {
      line
    }
  }
  // (its first line and the room over and under it: as round as that at its ends, its mark in a square that wide; drawn
  // in from the composer's ends as far as puts that mark's middle over the ＋'s)
  let outer = fn() { if with_x { head() } else { head() + 2.0 * notice_pad } }
  let inset = fn() { dmax(0.0, plus_mid() - outer() / 2.0) }
  // (each part's room on that line: its middle the line's)
  let on_head = fn(v : @view.View) {
    v.height(By(fn() { Some(head()) })).row(Is(true)).lines_up(Is(Some(Middle))) |> ignore
  }
  parent.box(made_for=loc, fn(b) {
    style_node(b, fn() { if with_x { notice_box_x } else { notice_box } })
    // (with a choice at its end: that choice's capsule as far in as makes it concentric with the notice's round end, as
    // the old one's inline_end)
    if with_choice {
      b.padding(By(fn() { (0.0, notice_pad, (outer() - @ui.Space::S7.px()) / 2.0, notice_pad) })) |> ignore
    }
    b
    .margin(By(fn() { (inset(), 0.0, inset(), notice_over) }))
    .radius(By(fn() { outer() / 2.0 }))
    |> ignore
    glass_capsule_node(b, sharing=false) |> ignore
    // its line: the mark, what it says, then what it offers, its ×, or its choice (wrapping under what it says where
    // the line has not the room for both)
    b.box(fn(line) {
      // (what it offers and its × on its line whatever its words wrap to; a choice beside them where the line has the
      // room for both as they lie on one line (their own width, not grown), else on the line under them: the row
      // wrapping, laid out so)
      line.row(Is(true)).lines_up(Is(Some(Start))) |> ignore
      if with_choice {
        line.wraps(Is(Some(@ui.Space::S1.px()))).lies_along(Is(Between)) |> ignore
      }
      line.box(fn(title) {
        title.row(Is(true)).lines_up(Is(Some(Start))).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        if !with_choice {
          title.grow(Is(1.0)) |> ignore
        }
        title.box(fn(m) {
          m
          .width(By(fn() { Some(outer()) }))
          .height(By(fn() { Some(head()) }))
          .lines_up(Is(Some(Middle)))
          .lies_along(Is(Middle))
          |> ignore
          m.pick(fn() { mark() == "updating" }, fn(i, turning) {
            if turning {
              updating_mark_node(i, notice_mark, fn() { theme().p.muted })
            } else {
              icon_node(i, "", notice_mark, By(fn() { theme().p.muted }), name_now=mark) |> ignore
            }
          })
        })
        |> ignore
        title.box(fn(words) {
          words.row(Is(true)).wraps(Is(Some(@ui.Space::S1.px()))).gap(Is(@ui.Space::S2.px())).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
          // (its first line's middle the head's: as far down as that puts it, what wraps under it going on down)
          words.padding(By(fn() { (0.0, (head() - theme().t.meta_line) / 2.0, 0.0, 0.0) })) |> ignore
          words.pick(fn() { summary.map(fn(f) { f() is Some(_) }).unwrap_or(false) }, fn(w, parts) {
            if parts {
              // (side by side, the line wrapping under them where it has not the room: the status and its detail
              // together, as the words' box lays what it holds; the pick's own box a row as that one is)
              w.row(Is(true)).wraps(Is(Some(@ui.Space::S1.px()))).gap(Is(@ui.Space::S2.px())).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
              words_node(w, fn() { summary.bind(fn(f) { f() }).map(fn(s) { s.0 }).unwrap_or("") }, fn() { notice_status })
              |> ignore
              words_node(w, fn() { summary.bind(fn(f) { f() }).map(fn(s) { s.1 }).unwrap_or("") }, fn() { notice_words })
              |> ignore
            } else {
              words_node(w, said, fn() { notice_words }) |> ignore
            }
          })
        })
        |> ignore
      })
      |> ignore
      match offer {
        Some(o) =>
          line.box(fn(at) {
            style_node(at, fn() { notice_offer_at }, in_row=true)
            on_head(at)
            // (its words a step heavier in the words' ink, quiet while out of reach: a press on them what it offers)
            link_node(
              at,
              o.words,
              o.press,
              style=fn() { notice_offer_words },
              ink=fn() { if (o.off)() { theme().p.muted } else { theme().p.text } },
              on=fn() { !(o.off)() },
            )
            |> ignore
          })
          |> ignore
        None => ()
      }
      match dismiss {
        Some(d) =>
          line.box(fn(at) {
            on_head(at)
            icon_button_node(at, "close", d.name, d.press, tips~, size=@signals.untracked(side), icon_size=notice_mark, disabled=d.off) |> ignore
          })
          |> ignore
        None => ()
      }
      match choice {
        Some({ choices: cs, chosen: now, choose: f, on_open }) =>
          line.box(fn(at) {
            // (wrapped under what it says: its words where those begin)
            at.margin(By(fn() { (outer() - @ui.Space::S2.px(), 0.0, 0.0, 0.0) })) |> ignore
            on_head(at)
            // (a quiet choice, round as a capsule concentric with the notice's round end: the old one's `capsule`)
            capsule_chooser_node(at, fn() {
              let id = now()
              cs().iter().find_first(fn(c) { c.0 == id }).map(fn(c) { c.1 }).unwrap_or("")
            }, cs, now, fn(id) { if !held() { f(id) } }, side=Top, disabled=held, on_open?) |> ignore
          })
          |> ignore
        _ => ()
      }
    })
    |> ignore
    b.show(fn() { failed() != "" }, fn(e) {
      e.padding(By(fn() { (outer(), 0.0, 0.0, 0.0) })) |> ignore
      words_node(e, failed, fn() { notice_failed }) |> ignore
    })
  })
}

///|
/// How far a notice's line is in from its top and bottom; how big its mark is; how far it stands over the composer.
let notice_pad : Double = 8.0

///|
let notice_mark : Double = 16.0

///|
let notice_over : Double = 8.0

///|
// kept across runs: a value (no field of it changes)
let notice_box : @ui.Style = @ui.css("pr=S4 py=S2 gap=S1")

///|
/// With a ×: no room round it of its own, the × concentric with its round end (composer_notice_box_dismiss).
// kept across runs: a value (no field of it changes)
let notice_box_x : @ui.Style = @ui.css("gap=S1")

///|
// kept across runs: a value (no field of it changes)
let notice_offer_at : @ui.Style = @ui.css("pl=S3")

///|
// kept across runs: a value (no field of it changes)
let notice_status : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, color=Fg, wrap=true)

///|
// kept across runs: a value (no field of it changes)
let notice_words : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=true)

///|
// kept across runs: a value (no field of it changes)
let notice_failed : @ui.TextStyle = @ui.text_style(size=Meta, color=Danger, wrap=true, w=Full)

///|
// kept across runs: a value (no field of it changes)
let notice_offer_words : @ui.TextStyle = @ui.text_style(size=Meta, weight=Medium, wrap=false)
