// A panel of the presenters' opened by nothing (panel_centred's: the library's dialog, a panel in the middle of the
// window) as nodes of the window's tree: the presenters' dialog layer (dialog_layer_node: a press outside it closes it,
// as a dialog's does), its frame as dialog draws it (dialog_w wide, dialog_wide_w where `wide`, the window less
// dialog_margin at most, no taller than it less dialog_room; 24 in, a line round it, dialog_r round, the panel's ground
// and shadow); its head (its title and its close button, what it says under them, or its close button alone in its top
// corner where it has no title), what it holds and its foot its nodes (panel_nodes), out to the dialog's edges they
// stand by, the dialog's padding inside them, what it holds scrolling where the window leaves the dialog short of room. Escape, back, a press outside and its close button close it (its gone told); what it holds
// closes it with what it was given (nothing told).

///|
/// Single-layer iOS 26/27 70% luminous liquid glass for modal dialogs (`panel_centred_node`, `confirm_node`,
/// `switcher_node`), degrading cleanly to opaque `panel_ground()` under `MBUI_GLASS=solid`.
pub fn dialog_glass() -> @ui.Glass {
  let g = @lg.liquid_dialog_glass(solid=panel_ground())
  // In Light mode, raise dialog veil density to 82% (`0xD1`) so muted secondary text (`#535559`) inside centred
  // dialogs over dimmed or high-contrast page backdrops stays >= 4.5:1 WCAG AA (~4.70:1).
  if theme().dark {
    g
  } else {
    { ..g, tint: 0xFDFCFDD1L }
  }
}

///|
/// 1pt hairline border for floating liquid glass overlays degraded to opaque solid under `MBUI_GLASS=solid`.
pub fn overlay_solid_edge() -> (Double, Int64) {
  @lg.liquid_overlay_solid_edge()
}

///|
/// A centred panel `x` in `parent` while `open()` (going over pop_out_ms once not); `close`: what what it holds is given to close it; `cancel` as it is closed by its close button,
/// Escape, back or a press outside. `shown`, `gone`: as dialog_layer_node's.
fn panel_centred_node(
  parent : @view.View,
  open : () -> Bool,
  x : PanelOf,
  close : () -> Unit,
  cancel : () -> Unit,
  keyed : Presented,
  shown? : () -> Unit = fn() {  },
  gone? : () -> Unit = fn() {  },
  dims? : () -> Bool = fn() { true },
  covered? : () -> Bool = fn() { false },
) -> Unit {
  // (a step further in from a panel: back to that one)
  let within = fn() { back_under(keyed) }
  // (its own ground keeps the focus as it opens, none of what it holds given it: a search at hand by touch)
  let own_ground : Ref[Bool] = Ref(false)
  // (one put at a share of the window down from its top (panel_nodes' `top_share`): no close button, a row's room in)
  let top_share = x.nodes.top
  dialog_layer_node(parent, open, cancel, outside=true, top_share~, first_stop=fn() { !own_ground.val }, first_takes=fn(s : @view.Said) { opens_on_role(s.role) }, shown~, gone~, dims~, covered~, within~, fn(across, layer, look, veil) {
    let theme = fn() { @ui.tree_theme() }
    // (its title, step and what it says as they are now: `live`'s, read where each is used and followed as it changes;
    // its head there or not as they say, what holds what it holds the same)
    let now = fn() {
      match x.live {
        Some(f) => f()
        None => (x.title, "", x.description)
      }
    }
    let untitled = fn() {
      let (title, step, _) = now()
      title == "" && step == ""
    }
    let w = fn() { dmin(if x.wide { dialog_wide_w } else { dialog_w }, over_room(layer).0 - dialog_margin) }
    // (what it holds and its head on the line of its words, a row's padding in: panel_centred's)
    let words_in = panel_words - dialog_pad
    // (what is at its foot)
    let footed = x.nodes.foot is Some(_)
    // (which of what it holds takes the focus as it opens, where what it holds says one: panel_opens_on_node)
    let opens_on : Ref[@view.View?] = Ref(None)
    // (and the field it opens to be typed in, before that: panel_opens_in_node, panel_search_at_hand_node)
    let field : Ref[PanelField?] = Ref(None)
    // (what its fields offer made in its layer: offers_layer_lent)
    offers_layer_lend(layer)
    across.box(fn(d) {
      d.lends(panel_opens_lent, opens_on) |> ignore
      d.lends(panel_field_lent, field) |> ignore
      d
      .width(By(fn() { Some(w()) }))
      // (no taller than the window leaves it, dialog_room: what it holds scrolls in itself past that)
      .max_height(By(fn() { Some(dmax(0.0, over_room(layer).1 - dialog_room)) }))
      // (dialog_box: 24 over its title, 24 in at its sides; each part out to them, the padding inside it)
      .padding(Is(if top_share > 0.0 { (top_pad, top_pad, top_pad, top_pad) } else { (dialog_pad, dialog_pad, dialog_pad, 0.0) }))
      .radius(Is(dialog_r))
      .glass(By(fn() { Some(dialog_glass()) }))
      .edge(By(fn() { if d.glass_solid() { (1.0, theme().color(Line)) } else { (0.0, 0L) } }))
      .shadow(By(glass_overlay_shadow))
      .shadow_outside(Is(true))
      .clips(Is(true))
      .alpha(By(fn() { look().alpha }))
      .scale(By(fn() { look().sx }))
      .offset(By(fn() { (look().dx, look().dy) }))
      .says(By(fn() {
        let (title, _, description) = now()
        Some(@view.said(Dialog, label=title, description~))
      }))
      // (a press on it its own: not outside it)
      |> ground_node
      |> ignore
      corner_card_node(d, fn() { dialog_r }, inset=fn() { if top_share > 0.0 { top_pad } else { dialog_pad } })
      // (where what it holds starts: under an untitled one's close button; right under its own head row where it heads
      // itself (`heads_itself`: in the title's place, clear of the close button over its corner), which keeps what space
      // it wants under it; a title's gap else)
      // (one at a share of the window down (`top_share`): no head over it, what it holds at its room's top)
      // (how far its close button stands out under a titled head with nothing said under it (dialog_close_at's `up`):
      // the body's box starts that much lower and its column's top room is that much less, so what scrolls in it stops
      // clear of the button and what it holds stands where it did)
      let close_under = fn() {
        if top_share == 0.0 && !x.nodes.heads &&
          !untitled() &&
          now().2 == "" {
          dmax(0.0, @ui.capsule_in(dialog_r, dialog_close) - (dialog_pad + dialog_head_over))
        } else {
          0.0
        }
      }
      let body_top = fn() {
        if top_share > 0.0 {
          top_share_body
        } else if untitled() && !x.nodes.heads && top_share == 0.0 {
          dialog_untitled_top()
        } else if x.nodes.heads {
          title_row_under
        } else {
          no_style
        }
      }
      // (untitled: its close button alone over its top corner, concentric with it, there while it is untitled: built
      // first, as a dialog builds its layer before what it holds (read out first, drawn under what comes after it); one
      // whose title is as it is now (`live`) built after what it holds and its foot (read out last, drawn over them))
      // (no stop of Tab's: a press, Escape and back close it)
      let close_node = fn(v : @view.View) {
        icon_button_node(v, "close", fn() { t("common.close") }, cancel, size=dialog_close)
        .tab_stop(Is(false))
        |> ignore
      }
      let corner = fn() {
        d.show(untitled, fn(o) {
          o.over(Is(true)).width(By(fn() { Some(w()) })) |> ignore
          o.box(fn(row) {
            style_node(row, fn() { dialog_close_row })
            row.alpha(By(fn() { look().words })) |> ignore
            row.box(fn(at) {
              style_node(at, fn() { dialog_close_corner() })
              close_node(at)
            })
            |> ignore
          })
          |> ignore
        })
      }
      if x.live is None && top_share == 0.0 {
        corner()
      }
      // (its head: its title (its step beside it) and its close button at its end where it has a title, what it says
      // under them where it says something: dialog's, as they are now)
      d.show(fn() { !untitled() || now().2 != "" }, fn(h) {
        h.margin(Is((-dialog_pad, -dialog_pad, -dialog_pad, 0.0))) |> ignore
        // (its words as faint as its look says)
        {
          // (as wide as the dialog, out to its sides)
          h.width(By(fn() { Some(w()) })) |> ignore
          h.box(fn(part) {
            // (as far over what it holds as its close button stands out under its line (close_under), so what scrolls
            // under it stops clear of the button)
            style_node(part, fn() { centred_part_in(dialog_pad, 0.0).then(@ui.style(pb=room(close_under()))) })
            part.alpha(By(fn() { look().words })) |> ignore
            // (its title's line, there while it has a title: its title, its step beside it, its close button at its end)
            part.box(fn(line) {
              style_node(line, fn() { dialog_head.then(@ui.style(pl=room(words_in))) })
              line.laid_nowhere(By(untitled)) |> ignore
              // (a step further in from a panel: its back key before its title, back to that one)
              let stepped = keyed.under is Some(_)
              if stepped {
                line.box(fn(k) {
                  style_node(k, fn() { dialog_back_at }, in_row=true)
                  icon_button_node(k, "chevron-left", fn() { t("common.back") }, fn() { back_under(keyed) |> ignore }, size=step_back_side)
                  |> ignore
                })
                |> ignore
              }
              line.box(fn(l) {
                style_node(l, fn() { dialog_title_line }, in_row=true)
                l.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
                if stepped {
                  l.grow(Is(1.0)) |> ignore
                }
                words_node(l, fn() { now().0 }, fn() { if now().1 != "" { dialog_title_one } else { dialog_title } })
                |> ignore
                words_node(l, fn() { now().1 }, fn() { dialog_step }) |> ignore
              })
              |> ignore
              line.box(fn(at) {
                style_node(at, fn() { dialog_close_at() }, in_row=true)
                close_node(at)
              })
              |> ignore
            })
            |> ignore
            part.show(fn() { now().2 != "" }, fn(lead) {
              style_node(lead, fn() { dialog_lead_at.then(@ui.style(pl=room(words_in))) })
              words_node(lead, fn() { now().2 }, fn() { dialog_lead }) |> ignore
            })
          })
          |> ignore
        }
      })
      // (a share of the window tall, not a form (one as tall as what it holds, whatever its share): its share of the
      // window less its frame, its body's own room over and under it outside that; no taller than the dialog leaves it,
      // all of it giving way where it is short of room, what it holds filling that share and laid out in it, scrolling
      // as it does itself, nothing of it scrolling past it)
      let n = x.nodes
      if x.tall > 0.0 && !x.form {
        d.box(fn(b) {
          style_node(b, fn() { centred_part_in(0.0, 0.0) })
          b
          .shrink(Is(1.0))
          .min_height(Is(Some(0.0)))
          .margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0)))
          .alpha(By(fn() { look().words }))
          |> ignore
          b.box(fn(col) {
            style_node(col, fn() {
              (if footed { dialog_body } else { dialog_body_end }).then(@ui.style(px=room(words_in), pt=room(@ui.Space::S4_5.px() - close_under()))).then(body_top())
            })
            col.grow(Is(1.0)).shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
            // (its rows out across the room the dialog leaves them)
            panel_in_lend(col, Wide, 0.0, sides=dialog_pad + words_in, rows_out=panel_words - panel_card_in, centred=true, clear=@signals.untracked(fn() {
              if untitled() && top_share == 0.0 { dialog_close_clear() } else { 0.0 }
            }))
            // (what it holds, together in one box (none of the body's gap between its parts): its share tall; one as tall
            // as what it holds up to that share (`hugs`), no taller)
            col.box(fn(held) {
              let share = fn() { Some(dmax(0.0, x.tall * over_room(layer).1 - dialog_frame_h)) }
              if n.hugs || n.hugs_centred {
                held.max_height(By(share)) |> ignore
              } else {
                held.height(By(share)) |> ignore
              }
              held.shrink(Is(1.0)).min_height(Is(Some(0.0))) |> ignore
              (n.body)(held, close)
            })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      } else {
        // (what it holds: 18 under its head, scrolling in itself where the dialog is short of room, out to its sides,
        // what it holds as far in as without: dialog's capped body)
        d.box(fn(b) {
          let scroll = @view.Scroll::new()
          b.shrink(Is(1.0)).min_height(Is(Some(0.0))).margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0))) |> ignore
          // (holding nothing laid out, none of its room, its margin over it with it: what it holds gone_empty below)
          b.gone_empty(Is(true)) |> ignore
          b.scrolls(scroll, slop=@ui.touch_slop(), bar=@ui.tree_scroll_bar(), fn(s) {
            s.gone_empty(Is(true)) |> ignore
            // (what it holds: in a column on its words' line, its words as far in as its look says)
            s.box(fn(outer) {
                  style_node(outer, fn() { centred_part_in(0.0, 0.0) })
                  outer.alpha(By(fn() { look().words })).gone_empty(Is(true)) |> ignore
                  outer.box(fn(col) {
                    style_node(col, fn() {
                      (if footed { dialog_body } else { dialog_body_end }).then(@ui.style(px=room(words_in), pt=room(@ui.Space::S4_5.px() - close_under()))).then(body_top())
                    })
                    // (holding nothing laid out, none of its room: its title and what it says straight over its foot)
                    col.gone_empty(Is(true)) |> ignore
                    // (on its words' line already: none further in; its rows out across the room the dialog leaves them;
                    // clear of its close button while untitled)
                    panel_in_lend(col, Wide, 0.0, sides=dialog_pad + words_in, rows_out=panel_words - panel_card_in, centred=true, clear=@signals.untracked(fn() {
                      if untitled() && top_share == 0.0 { dialog_close_clear() } else { 0.0 }
                    }))
                    (n.body)(col, close)
                  })
                  |> ignore
                })
                |> ignore
          })
          // (cut at its box while what it holds is taller than it, and taking presses within it alone then)
          .clips(By(fn() { scroll.goes() }))
          .bounds_input(By(fn() { scroll.goes() }))
          |> ignore
        })
        |> ignore
      }
      // (its foot nodes: its buttons at its end in its foot corner)
      match n.foot {
        Some(f) =>
          d.box(fn(fv) {
            style_node(fv, fn() { centred_part_in(0.0, 0.0) })
            fv.margin(Is((-dialog_pad, 0.0, -dialog_pad, 0.0))).alpha(By(fn() { look().words })) |> ignore
            fv.box(fn(row) {
              style_node(row, fn() { dialog_foot.then(dialog_corner_foot(dialog_pad)) })
              row.wraps(By(fn() { Some(ask_foot_lines()) })) |> ignore
              f(row, close)
            })
            |> ignore
          })
          |> ignore
        None => ()
      }
      if x.live is Some(_) && top_share == 0.0 {
        corner()
      }
      // (another dialog over it: dimmed over all of itself, its corners its own)
      d.box(fn(v) { v.over(Is(true)).radius(Is(dialog_r)).ground(By(veil)) |> ignore }) |> ignore
    })
    |> ignore
    // (the focus on its own ground as it opens, back to what had it as it goes: on the field it opens to be typed in, or
    // the one of what it holds that said so, where one did (panel_opens_in_node, panel_search_at_hand_node,
    // panel_opens_on_node); else the first of what it holds that takes it once that is built and laid out (first_stop;
    // not one in steps, whose steps keep it on its ground as they come), as kit's dialog's: where what it holds is nodes,
    // only what takes what is typed or the arrows (opens_on_role), none of it where nothing does (its own ground: the
    // keys its, Escape; Enter nothing), as the old dialog's went to the first of its fields and choices it registered)
    let (to, own) = match (field.val, opens_on.val) {
      (Some(f), _) if f.keyed(false) => (f.field, false)
      // (a search at hand by touch: its own ground, no input method raised over what it lists)
      (Some(_), _) => (layer, true)
      (None, Some(first)) => (first, false)
      (None, None) => (layer, false)
    }
    own_ground.val = own
    to
  })
}

///|
/// A part of a centred panel's out to its sides (and `over` above it, `under` below it): the dialog's padding at its
/// sides inside it.
fn centred_part_in(over : Double, under : Double) -> @ui.Style {
  @ui.style(w=Full, pl=room(dialog_pad), pt=room(over), pr=room(dialog_pad), pb=room(under))
}

///|
/// What a panel holds under its own title row (panel's `title_row`): from right under it, the row keeping what it
/// wants under it.
// kept across runs: a value (no field of it changes)
let title_row_under : @ui.Style = @ui.css("pt=S0")

///|
/// Whether what is read out as `role` is what a dialog of nodes opens on (its layer's focus_opens_first `takes`): what takes what is typed (a field, a
/// box offering what to type) or the arrow keys (a choice of a few, its radios or its tabs; a slider). One place: a
/// kind to add is added here.
fn opens_on_role(role : @view.Role) -> Bool {
  match role {
    TextField | Combobox | Radio | Tab | Slider => true
    _ => false
  }
}

///|
/// The room in all round one put at a share of the window down from its top (panel_nodes' `top_share`): a row's.
let top_pad : Double = 12.0

///|
/// What such a one holds starts at its room's top: no head over it, none of a body's room under one (dialog_body's).
let top_share_body : @ui.Style = @ui.css("pt=S0")
