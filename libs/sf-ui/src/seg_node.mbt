// A choice of a few as nodes of the window's tree (segmented's, parts.mbt, its wide way: the web's Segmented): a quiet
// pill track, the chosen one lifted out of it (the theme's lifted, a hairline round it) sliding to it as a thing moved
// does (@motion's move_spring), its options equal columns as wide as the widest of their words in the chosen weight with
// segmented_in either side, `item_w` at least; each chosen by a press, the arrows along it, a screen reader's
// Activate, read out as a radio of a group.

///|
/// Its options' columns as segmented has them: each as wide as the widest of their words in the chosen weight with
/// segmented_in either side, `item_w` at least.
fn seg_node_cols(v : @view.View, labels : Array[String], item_w : Double) -> Double {
  let size = node_sp(v, theme().t.ui)
  labels.fold(init=item_w, fn(m, l) { dmax(m, node_words_w(l, size, weight=500) + 2.0 * segmented_in) })
}

///|
/// `labels`' options fitted to `room` as node `v` draws them (fitted's): their words at the system's size of words in
/// its tree, in the theme its tree's words are drawn in.
fn node_fitted(
  v : @view.View,
  labels : Array[String],
  room : Double,
  base : Double,
  weight : Int,
  side : Double,
  least : Double,
) -> Fitted {
  fitted_by(fn(x) { node_sp(v, x) }, @ui.tree_theme().tabular, labels, room, base, weight, side, least)
}

///|
/// A segmented choice of `labels` in `parent`, `chosen()` the one chosen, `choose` told the one a press, an arrow, a
/// screen reader or its pick chooses (the caller says it chosen then: `chosen` follows it), `item_w` each option at
/// least, `said` what a screen reader calls it. Its thumb slides from where it is to the one chosen as that changes, at
/// that moment. Where its columns need more room than there is (its track laid out narrower than they are: it gives
/// way, as segmented's cut to where it is), its options share what there is as option_widths has them, as segmented's
/// do: as alike as their words let them, their sides narrower, else their words smaller alike (to the system's own
/// size of words), else the chosen one alone in its track with a chevron, the others in a pick (@sf.pick) a press on
/// it opens. Always one line, each one's words whole.
#callsite(autofill(loc))
pub fn seg_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  item_w? : Double = 0.0,
  each_own? : Bool = false,
  said? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  // (measured again as all words are, the system's size of words changed: View::words_redone)
  let col = fn() {
    parent.words_redone() |> ignore
    seg_node_cols(parent, labels(), item_w)
  }
  // (each option as wide as its own words, `each_own`, or all of them as the widest's)
  let cols = fn() -> Array[Double] {
    if each_own {
      parent.words_redone() |> ignore
      labels().map(fn(l) { seg_node_cols(parent, [l], item_w) })
    } else {
      Array::make(labels().length(), col())
    }
  }
  let gaps = fn() { segmented_gap * (labels().length() - 1).to_double() }
  // (as wide as its columns, its track round them: what it is laid out before it gives way)
  let whole = fn() { cols().fold(init=0.0, fn(a, c) { a + c }) + gaps() + 2.0 * segmented_pad }
  // (a line of its own round its track, whatever way `parent` lays out what it holds: the track's basis its width
  // there; it gives way as the track does, down to nothing)
  parent.box(made_for=loc, fn(line) {
    line.row(Is(true)).shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    line.box(fn(track) {
      let opt_h = fn() {
        track.words_redone() |> ignore
        dmax(segmented_h, node_sp(track, theme().t.ui * @ui.tree_theme().text_line).ceil() + 2.0 * 2.0)
      }
      // (its pad round its options inside what it holds: what is said of it as a group (View::by_room's) out to its edges)
      track
      .row(Is(true))
      // (as wide as its columns where its line has the room, giving way to what it has: down to nothing, its options
      // fitted to it)
      .basis(By(fn() { Some(whole()) }))
      // (as high as its options with its pad round them: not stretched to its line's height)
      .height(By(fn() { Some(opt_h() + 2.0 * segmented_pad) }))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
      // (what it holds by the room the track is given, its options fitted to that as the layout comes to it)
      track.by_room(fn(inner, given) {
        // how its options fit the room its track is given (none: their columns whole), as segmented's
        let fit : () -> Fitted? = fn() {
          let room = given.width()
          if room < whole() - 0.5 {
            inner.words_redone() |> ignore
            Some(node_fitted(inner, labels(), room - 2.0 * segmented_pad - gaps(), theme().t.ui, 500, segmented_in, segmented_least))
          } else {
            None
          }
        }
        let menu = fn() { fit() is Some({ fit: Menu, .. }) }
        // (each option's width: its column, or its share of the room as fitted; its words that much smaller)
        let widths = fn() {
          match fit() {
            Some({ widths, fit: Whole | Smaller(_) }) => widths
            _ => cols()
          }
        }
        let smaller = fn() {
          match fit() {
            Some({ fit: Smaller(k), .. }) => k
            _ => 1.0
          }
        }
        let ink = fn() { theme().p.text }
        let seg = @lg.liquid_segmented_node(
          inner,
          labels,
          chosen,
          choose,
          glass_track=false,
          pad=segmented_pad,
          gap=segmented_gap,
          widths~,
          height_by=fn() { opt_h() + 2.0 * segmented_pad },
          text_size=fn() { theme().t.ui * smaller() },
          kind=Radio,
          said~,
          shown=fn() { !menu() },
          loc~,
        )
        seg.laid_nowhere(By(menu)) |> ignore
        // not side by side: the chosen one's words as its option has them (cut short where they must be), a chevron at its
        // end; pressed, a pick of them all beside it, the chosen one marked (search none: a few short words)
        inner.box(fn(menu_track) {
          menu_track
          .row(Is(true))
          .laid_nowhere(By(fn() { !menu() }))
          .padding(Is((segmented_pad, segmented_pad, segmented_pad, segmented_pad)))
          .height(By(fn() { Some(opt_h() + 2.0 * segmented_pad) }))
          .radius(By(fn() { opt_h() / 2.0 + segmented_pad }))
          .ground(By(fn() { alpha(theme().p.text, 0.06) }))
          |> ignore
          let words = fn() { labels().get(chosen()).unwrap_or("") }
          // (the pick it opened, as presented: 0, none yet; open while it is drawn, presented_drawn_of)
          let opened : @signals.Signal[Int] = @signals.signal(0)
          let open = fn() {
            let s = opened.get()
            s != 0 && presented_drawn_of(s)
          }
          @headless.disclosure(
            menu_track,
            fn() { if said == "" { words() } else { said + " " + words() } },
            open,
            fn(m) {
              let (x, y, w, h) = m.rect()
              let all = @signals.untracked(labels)
              let now = @signals.untracked(chosen)
              pick(
                "",
                all.mapi(fn(i, l) { choice(i.to_string(), l) }),
                now.to_string(),
                fn(k) {
                  let i = labels_at(all, k, now)
                  if i != now {
                    choose(i)
                  }
                },
                from=At(x, y, w, h),
                search=false,
              )
              opened.set(last_presented())
            },
            fn(m, _) {
              m
              .row(Is(true))
              .grow(Is(1.0))
              .height(By(fn() { Some(opt_h()) }))
              .lines_up(Is(Some(Middle)))
              .padding(Is((segmented_least, 0.0, segmented_least, 0.0)))
              .gap(Is(segmented_least))
              |> ignore
              m.box(fn(w) {
                w
                .grow(Is(1.0))
                .shrink(Is(1.0))
                .min_width(Is(Some(0.0)))
                .words(By(words))
                .words_look(By(fn() {
                  let size = theme().t.ui
                  { size, weight: 500, line: @ui.tree_theme().text_line * size, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
                }))
                .ink(By(ink))
                |> ignore
              })
              |> ignore
              icon_node(m, "chevron-down", segmented_chevron, By(fn() { theme().p.muted })) |> ignore
            },
          )
          |> ignore
        })
        |> ignore
      })
      .grow(Is(1.0))
      .shrink(Is(1.0))
      .min_width(Is(Some(0.0)))
      |> ignore
    })
    |> ignore
  })
}

///|
/// A sliding group's lens's shadow, held all the way (@kit.toggle_group's): its blur and how far down.
let seg_lens_shadow : Double = 6.0

///|
let seg_lens_shadow_y : Double = 2.0

///|
/// Growth ratio of the clear liquid glass lens while a compact segmented thumb is held (1.15x).
let seg_lens_grow : Double = 0.15

///|
/// Solid thumb opacity while cross-fading out under the lifted clear liquid glass lens.
fn seg_thumb_alpha(l : Double) -> Double {
  if l > 0.001 {
    1.0 - dmin(1.0, l)
  } else {
    1.0
  }
}

///|
/// Clear lifted liquid glass lens mounted above a segmented/pill-tab strip's labels while held (`lens() > 0.001`).
/// Zero hidden glass instances at rest, zero pointer interception, and zero relayout via paint-layer `ground_drawn`.
fn seg_lens_overlay_node(
  parent : @view.View,
  lens : () -> Double,
  h : () -> Double,
  rect : () -> (Double, Double, Double, Double)?,
  jelly? : (@view.View) -> (Double, Double),
  active? : () -> Bool = fn() { false },
) -> Unit {
  // Mount lazily on first press/hold so idle pages allocate zero nodes, then keep mounted across slide settle so
  // releasing the lens never triggers a layout pass (`laid == 0`). Glass stays `None` whenever `full() <= 0.001`.
  let mounted : @signals.Signal[Bool] = @signals.signal(false)
  parent.reacts(fn() { lens() > 0.001 || active() }, fn(on) {
    if on && !mounted.untracked() {
      mounted.set(true)
    }
  })
  parent.show(fn() { mounted.get() }, fn(l) {
    let full = fn() { dmin(1.0, lens()) }
    l
    .over(Is(true))
    .points(Is(false))
    .offset(Is((0.0, 0.0)))
    .width(Is(Some(0.0)))
    .height(By(fn() { Some(h()) }))
    // (round as a pill is said to be, Full, as the old lens's capsule: as round as it can be)
    .radius(Is(1.0e6))
    .glass(By(fn() {
      let p = full()
      if p > 0.001 {
        Some(@lg.liquid_tab_lens_glass(p, solid=theme().p.raised))
      } else {
        None
      }
    }))
    .shadow(By(fn() {
      let p = full()
      if p > 0.001 {
        (seg_lens_shadow * p, seg_lens_shadow_y * p, @ui.tree_theme().shadow)
      } else {
        (0.0, 0.0, 0x00000000L)
      }
    }))
    .shadow_outside(Is(true))
    .alpha(By(full))
    .ground_drawn(By(fn() {
      match rect() {
        Some((rx, ry, rw, _)) => {
          let hh = h()
          let (lw, lh) = match jelly {
            Some(jf) => {
              let (sx, sy) = jf(l)
              (dmax(0.0, rw + hh * (sx - 1.0)), dmax(0.0, hh * sy))
            }
            None => {
              let grow = hh * seg_lens_grow * lens()
              (rw + grow, hh + grow)
            }
          }
          {
            dx: rx + (rw - lw) / 2.0,
            dy: ry + (hh - lh) / 2.0,
            dw: lw,
            dh: lh - hh,
            corners: Some((lh / 2.0, lh / 2.0, lh / 2.0, lh / 2.0)),
          }
        }
        None => @view.ground_as_laid
      }
    }))
    |> ignore
  })
}

///|
/// The thumb's motion belongs to the view that keeps the selection across page changes.
pub struct SegThumb {
  priv held : @motion.NodeWay
  priv position : @motion.NodeWay
  priv fingered : @signals.Signal[Double?]
  priv mouse_dd : @lg.DampedDrag
  priv mouse_active : @signals.Signal[Bool]
}

///|
/// Keep the thumb's current position and press motion on `owner`, so a new view can draw the same motion.
pub fn SegThumb::new(owner : @view.View, chosen : () -> Int) -> SegThumb {
  let fingered : @signals.Signal[Double?] = @signals.signal(None)
  let mouse_active : @signals.Signal[Bool] = @signals.signal(false)
  let held = @motion.NodeWay::new(0.0)
  owner.reacts(
    fn() { !owner.glass_solid() && !@ui.reduced_motion() && fingered.get() is Some(_) },
    fn(down) { held.go(owner, if down { 1.0 } else { 0.0 }, @motion.backdrop_press_spring) },
  )
  let goal = fn() { fingered.get().unwrap_or(chosen().to_double()) }
  let init = @signals.untracked(goal)
  let position = @motion.NodeWay::new(init)
  owner.reacts(at_start=false, goal, fn(p) {
    let spring = if fingered.untracked() is Some(_) { @motion.tactile_bounce } else { @motion.snappy_damped }
    position.go(owner, p, spring)
  })
  let mouse_dd = @lg.DampedDrag::new(init, lo=0.0, hi=1.0, held_scale=1.0 + seg_lens_grow)
  mouse_dd.attach(owner)
  { held, position, fingered, mouse_dd, mouse_active }
}

///|
/// A narrow page's choice of a few (seg's filling Seg, as nodes: segmented's on a narrow page) in `parent`: as wide as
/// where it is, `labels` sharing it alike, none narrower than its words with their sides (fitted: where they need more,
/// their sides narrower, else their words smaller alike, else the chosen one alone with a chevron, the others in a pick a
/// press on it opens), on a neutral capsule track, 34 high, 2 in. A thumb in the theme's lifted colour sits under the
/// chosen one's words and slides to the new option when the selection changes. On a hold or horizontal drag,
/// a glass lens grows over the thumb. The thumb follows the nearest option and leans toward the finger.
/// The finger can leave the track. Release selects the nearest option. `chosen()` gives the selected option.
/// `choose` receives the option a press, an arrow, a screen
/// reader or its pick chooses (the caller says it chosen then: `chosen` follows it); `said` what a screen reader calls
/// it. As wide as where it is laid out, its words at the system's size of words, in the language as it is, as those
/// change. `labels()` says how many options there are once, as it is made: their words may change (another language),
/// their number not.
#callsite(autofill(loc))
pub fn seg_fill_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  said? : String = "",
  thumb? : SegThumb,
  loc~ : SourceLoc,
) -> @view.View {
  let labels_now = @signals.computed(fn(_) { labels() })
  let labels = fn() { labels_now.get() }
  let chosen_now = @signals.computed(fn(_) { chosen() })
  let chosen = fn() { chosen_now.get() }
  parent.box(made_for=loc, fn(track) {
    let thumb = match thumb {
      Some(kept) => kept
      None => SegThumb::new(track, chosen)
    }
    let track_h = fn() {
      track.words_redone() |> ignore
      let (_, line) = @ui.tree_theme().text_size(Base)
      dmax(segmented_narrow_h, node_sp(track, line).ceil() + 2.0 * seg_inset)
    }
    // (its inset round its options inside what it holds: what is said of it as a group (View::by_room's) out to its
    // edges)
    track
    .row(Is(true))
    .height(By(fn() { Some(track_h()) }))
    .radius(By(fn() { track_h() / 2.0 }))
    .ground(By(track_glass_ink))
    |> ignore
    // (what it holds by the room the track is given: its options shared or fitted to that as the layout comes to it)
    track.by_room(fn(inner, given) {
      // how its options share the room its track is given, as seg's: where their words with their sides come to
      // more than it, fitted to it (seg's fitted); else none, the layout sharing it alike (none narrower than its words
      // with their sides: Seg's flex)
      let fit : () -> Fitted? = fn() {
        inner.words_redone() |> ignore
        let base = @ui.tree_theme().text_size(Base).0
        let size = node_sp(inner, base)
        let room = given.width() - 2.0 * seg_inset
        let need = labels().fold(init=0.0, fn(s, l) { s + node_words_w(l, size) + 2.0 * seg_side })
        if need > room + 0.5 {
          Some(node_fitted(inner, labels(), room, base, 400, seg_side, seg_least))
        } else {
          None
        }
      }
      // (each option's share of the room where none is fitted: alike, none narrower than its words with their sides, as
      // Seg's flex shares it; worked out here from the room it is given, what each is laid out at and where the thumb goes
      // one number)
      let shared = fn() {
        inner.words_redone() |> ignore
        let size = node_sp(inner, @ui.tree_theme().text_size(Base).0)
        seg_shares(given.width() - 2.0 * seg_inset, labels().map(fn(l) { node_words_w(l, size) + 2.0 * seg_side }))
      }
      let menu = fn() { fit() is Some({ fit: Menu, .. }) }
      let widths = fn() {
        match fit() {
          Some({ widths, fit: Whole | Smaller(_) }) => widths
          _ => []
        }
      }
      let smaller = fn() {
        match fit() {
          Some({ fit: Smaller(k), .. }) => k
          _ => 1.0
        }
      }
      inner.row(Is(true)) |> ignore
      let felt : Ref[Int?] = Ref(None)
      let felt_choose = fn(k : Int) {
        if @ui.pointing() is Finger && felt.val != Some(k) {
          @ui.haptic(TextHandleMove)
        }
        choose(k)
      }
      @headless.radio_group(
        inner,
        fn() { said },
        chosen,
        felt_choose,
        shown=fn() { !menu() },
        in_node=true,
        fn(g, rg) {
          g
          .row(Is(true))
          .grow(Is(1.0))
          .padding(Is((seg_inset, seg_inset, seg_inset, seg_inset)))
          .height(By(fn() { Some(track_h()) }))
          |> ignore
          // side by side: the thumb under the options' words, and the options
          g.box(fn(strip) {
            strip.row(Is(true)).grow(Is(1.0)).laid_nowhere(By(menu)) |> ignore
          // (each option's width: as fitted, else its share; as many as there are options as it is made)
          let n = @signals.untracked(labels).length()
          let w_of = fn(k : Int) {
            let ws = widths()
            if ws.length() > 0 {
              ws.get(k).unwrap_or(0.0)
            } else {
              shared().get(k).unwrap_or(0.0)
            }
          }
          let x_of = fn(k : Int) {
            let mut x = seg_inset
            for i in 0..<k {
              x = x + w_of(i)
            }
            x
          }
          // Follow the touch between option centers. The nearest center sets the snap point.
          let along = fn(x : Double) -> Double {
            let mut left = seg_inset
            let mut from = left + w_of(0) / 2.0
            left = left + w_of(0)
            for k in 1..<n {
              let w = w_of(k)
              let to = left + w / 2.0
              if x < to && to > from {
                return (k - 1).to_double() + dclamp((x - from) / (to - from), 0.0, 1.0)
              }
              from = to
              left = left + w
            }
            dmax(0.0, (n - 1).to_double())
          }
          let dd = thumb.mouse_dd
          let last_f = if n > 1 { (n - 1).to_double() } else { 0.0 }
          dd.set_bounds(lo=0.0, hi=last_f)
          let current = Ref(@signals.untracked(chosen))
          let strip_origin_x = Ref(0.0)
          strip.reacts(at_start=false, chosen, fn(i) {
            if i != current.val {
              current.val = i
              dd.slide_to(i.to_double())
            }
          })
          let preview = fn(k : Int, event : @view.Drag?) -> Int? {
            match event {
              Some(d) if @ui.pointing() is Finger => {
                thumb.mouse_active.set(false)
                let p = along(x_of(k) + d.x)
                let nearest = (p + 0.5).floor().to_int()
                if nearest != felt.val.unwrap_or(chosen()) {
                  @ui.haptic(TextHandleMove)
                }
                felt.val = Some(nearest)
                let target = nearest.to_double()
                thumb.fingered.set(Some(target + (p - target) * seg_drag_lean))
                Some(nearest)
              }
              _ => {
                felt.val = None
                thumb.fingered.set(None)
                None
              }
            }
          }
          strip.owns(fn() {
            felt.val = None
            thumb.fingered.set(None)
          })
          |> ignore
          strip.reacts(menu, fn(m) {
            if m {
              felt.val = None
              thumb.fingered.set(None)
              if thumb.mouse_active.untracked() {
                dd.cancel_to(@signals.untracked(chosen).to_double())
              }
            }
          })
          |> ignore
          let no_lens = fn() { strip.glass_solid() || @ui.reduced_motion() }
          let lens = fn() {
            if no_lens() {
              0.0
            } else if thumb.mouse_active.get() {
              dd.pressed(strip)
            } else {
              thumb.held.shown(strip)
            }
          }
          let mouse_stopped = fn() {
            let to = dclamp(dd.target().round(), 0.0, last_f)
            let i = to.to_int()
            current.val = i
            if no_lens() {
              dd.slide_to(to)
            } else {
              dd.animate_to(to)
            }
            if i != @signals.untracked(chosen) {
              felt_choose(i)
            }
          }
          let on_mouse_drag = fn(d : @view.Drag) {
            match d.kind {
              Down | Moved => {
                let p = along(seg_inset + (d.wx - strip_origin_x.val))
                if no_lens() {
                  dd.slide_to(p)
                } else {
                  dd.update_value(p)
                }
              }
              Up => mouse_stopped()
              Off => {
                let orig = @signals.untracked(chosen)
                current.val = orig
                if no_lens() {
                  dd.slide_to(orig.to_double())
                } else {
                  dd.cancel_to(orig.to_double())
                }
              }
            }
          }
          // (past either end, where a way turned back with speed takes it (@motion.cover_damped_spring goes past no
          // end from rest), the end pair's blend carried on, as @ui.cover_rect's does: held at the end, the thumb
          // would stop dead there)
          let rect = fn() {
            guard n > 0 else { return None }
            let h = track_h() - 2.0 * seg_inset
            guard n > 1 else { return Some((x_of(0), 0.0, w_of(0), h)) }
            let p = if thumb.mouse_active.get() { dd.value(strip) } else { thumb.position.shown(strip) }
            let i = p.floor().to_int()
            let a = if i < 0 { 0 } else { imin(i, n - 2) }
            let f = p - a.to_double()
            let w = w_of(a)
            Some((x_of(a) + w * f, 0.0, dmax(0.0, w + (w_of(a + 1) - w) * f), h))
          }
          // (each of its corners as the corner rule makes it in the track's (@ui corners.mbt, as the old frame works them out
          // after layout): concentric with the track's where it lies in that corner as far from both its edges, at an end
          // or a hair short of it on its way there, as the theme's ranges let it be; else its own. Nothing between them cuts
          // a corner of the track's: the rule's own conditions, here, are these)
          let thumb_corners = fn(r : (Double, Double, Double, Double)) -> (Double, Double, Double, Double)? {
            let (x, _, w, h) = r
            let track_r = track_h() / 2.0
            let own = @ui.concentric(track_r, seg_inset)
            let room = given.width()
            let (l, t, rr, d) = (x, seg_inset, room - x - w, seg_inset)
            let half = dmin(w, h) / 2.0
            let fit = @ui.tree_theme().corner_fit
            let rs = FixedArray::make(4, own)
            let mut moved = 0
            for k in 0..<4 {
              match @ui.corner_lies_in(k, l, t, rr, d, track_r) {
                Some(inset) =>
                  match @ui.corner_following(own, half, track_r, inset, fit) {
                    Some(kk) => {
                      rs[k] = kk
                      moved += 1
                    }
                    None => ()
                  }
                None => ()
              }
            }
            if @ui.corners_kept(rs, moved) {
              Some((rs[0], rs[1], rs[2], rs[3]))
            } else {
              None
            }
          }
          // the thumb: where its cover has it, its corner concentric in the track's; faded under the lens (zero relayout)
          strip.box(fn(th) {
            th
            .over(Is(true))
            .laid_nowhere(By(fn() { w_of(chosen()) <= 0.0 }))
            .width(Is(Some(0.0)))
            .height(By(fn() { Some(track_h() - 2.0 * seg_inset) }))
            .radius(By(fn() { @ui.concentric(track_h() / 2.0, seg_inset) }))
            .ground(By(fn() { @ui.tree_theme().lifted }))
            .ground_drawn(By(fn() {
              match rect() {
                Some((x, y, w, h)) => {
                  dx: x - seg_inset,
                  dy: 0.0,
                  dw: w,
                  dh: 0.0,
                  corners: thumb_corners((x, y, w, h)),
                }
                None => @view.ground_as_laid
              }
            }))
            // (as the old thumb: faded only while the lens is out, not past 1 as the hand's spring comes back past 0)
            .alpha(By(fn() { seg_thumb_alpha(lens()) }))
            |> ignore
          })
          |> ignore
          // its options: each its share of the room it is given, its words in its middle, the
          // chosen one's in the ink, the others muted, smaller as fitted
          for k in 0..<n {
            let label = fn() { labels().get(k).unwrap_or("") }
            let kf = k.to_double()
            rg.item(strip, fn() { k }, label, fn(o, item) {
              let on = fn() { item.chosen() }
              let horizontal : Ref[Bool?] = Ref(None)
              let across = fn(d : @view.Drag) { (d.x - d.ox).abs() > (d.y - d.oy).abs() }
              let on_it = fn(d : @view.Drag) { o.finger_target(d.wx, d.wy) }
              o
              // (its share, or as fitted)
              .width(By(fn() { Some(w_of(k)) }))
              .height(By(fn() { Some(track_h() - 2.0 * seg_inset) }))
              .row(Is(true))
              .lines_up(Is(Some(Middle)))
              // (its words in its middle, as laid out: seg_full_option's justify)
              .lies_along(Is(Middle))
              .gesture(
                @ui.touch_slop(),
                press=fn(d) {
                  if @ui.pointing() is Finger {
                    horizontal.val = None
                  } else {
                    thumb.mouse_active.set(true)
                    strip_origin_x.val = d.wx - ((x_of(k) - seg_inset) + d.x)
                    if !no_lens() {
                      dd.press()
                    }
                    if (kf - dd.target()).abs() > 0.001 {
                      if no_lens() {
                        dd.slide_to(kf)
                      } else {
                        dd.update_value(kf)
                      }
                    }
                  }
                },
                tap=fn(d) {
                  if @ui.pointing() is Finger {
                    if on_it(d) {
                      o.press() |> ignore
                    }
                    preview(k, None) |> ignore
                  } else {
                    mouse_stopped()
                  }
                },
                hold=(seg_hold_ms, fn(d) {
                  if @ui.pointing() is Finger {
                    preview(k, Some(d)) |> ignore
                  }
                }),
                hold_yields=true,
                drag=fn(d) {
                  if @ui.pointing() is Finger {
                    match d.kind {
                      Down | Moved => {
                        if d.kind == Down {
                          horizontal.val = Some(across(d))
                        }
                        preview(k, if horizontal.val == Some(true) { Some(d) } else { None }) |> ignore
                      }
                      Up if horizontal.val.unwrap_or(across(d)) => {
                        match preview(k, Some(d)) {
                          Some(sel) => if sel != @signals.untracked(chosen) { felt_choose(sel) }
                          None => if on_it(d) { o.press() |> ignore }
                        }
                        preview(k, None) |> ignore
                      }
                      Up => {
                        if on_it(d) {
                          o.press() |> ignore
                        }
                        preview(k, None) |> ignore
                      }
                      Off => preview(k, None) |> ignore
                    }
                  } else {
                    on_mouse_drag(d)
                  }
                },
              )
              |> ignore
              o.box(fn(w) {
                w
                .words(By(label))
                .words_look(By(fn() {
                  // (Base, on its own line, as Seg's words: both that much smaller where fitted as drawn, after the system's size
                  // of words applies, as Ctx::words_smaller has them: said by the size that draws them so)
                  o.words_redone() |> ignore
                  let (size, line) = @ui.tree_theme().text_size(Base)
                  let k = smaller()
                  let (size, line) = if k == 1.0 { (size, line) } else { (node_sp_of(w, node_sp(w, size) * k), node_sp_of(w, node_sp(w, line) * k)) }
                  { size, weight: 400, line, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
                }))
                .ink(By(fn() {
                  if thumb.mouse_active.get() {
                    let lit = dclamp(1.0 - (dd.value(w) - kf).abs(), 0.0, 1.0)
                    @ui.blend(theme().p.muted, theme().p.text, lit)
                  } else if on() {
                    theme().p.text
                  } else {
                    theme().p.muted
                  }
                }))
                |> ignore
              })
              |> ignore
            })
            |> ignore
          }
          // held by a finger or pointer: the thumb a lens of liquid glass over the options (iOS 26's), a capsule on the
          // thumb's way, larger as it is held (past the track's edges), raised off it by a shadow
          seg_lens_overlay_node(
            strip,
            lens,
            fn() { track_h() - 2.0 * seg_inset },
            fn() { rect().map(fn(r) { (r.0 - seg_inset, r.1, r.2, r.3) }) },
            jelly=fn(l) {
              if thumb.mouse_active.get() {
                dd.jelly(l, 10.0)
              } else {
                let s = 1.0 + seg_lens_grow * lens()
                (s, s)
              }
            },
          )
          })
          |> ignore
          // not side by side: the chosen one's words (cut short where they must be), a chevron at its end; pressed, a pick of
          // them all beside it, the chosen one marked
          let words = fn() { labels().get(chosen()).unwrap_or("") }
          let opened : @signals.Signal[Int] = @signals.signal(0)
          let open = fn() {
            let s = opened.get()
            s != 0 && presented_drawn_of(s)
          }
          @headless.disclosure(
            g,
            fn() { if said == "" { words() } else { said + " " + words() } },
            open,
            fn(m) {
              let (x, y, w, h) = m.rect()
              let all = @signals.untracked(labels)
              let now = @signals.untracked(chosen)
              pick(
                "",
                all.mapi(fn(i, l) { choice(i.to_string(), l) }),
                now.to_string(),
                fn(k) {
                  let i = labels_at(all, k, now)
                  if i != now {
                    choose(i)
                  }
                },
                from=At(x, y, w, h),
                search=false,
              )
              opened.set(last_presented())
            },
            fn(m, _) {
              m
              .row(Is(true))
              .grow(Is(1.0))
              .laid_nowhere(By(fn() { !menu() }))
              .lines_up(Is(Some(Middle)))
              .padding(Is((seg_menu_in, 0.0, seg_menu_in, 0.0)))
              .gap(Is(seg_menu_gap))
              |> ignore
              // (where even its ellipsis has not the room, that drawn past its words' box into the gap before the chevron, as
              // seg_menu_words' `w=Cut` words are drawn)
              m.box(fn(w) { styled_words(w.grow(Is(1.0)), words, fn() { seg_menu_words }).ellipsis_past(Is(true)) |> ignore })
              |> ignore
              icon_node(m, "chevron-down", seg_chevron, By(fn() { theme().p.muted })) |> ignore
            },
          )
          |> ignore
        },
      )
      |> ignore
    })
    .grow(Is(1.0))
    .shrink(Is(1.0))
    .min_width(Is(Some(0.0)))
    |> ignore
  })
}

///|
/// How `room` is shared among items each `least` wide at least, as flex shares it among items grown alike from nothing:
/// alike, one that would come out narrower than its least kept at it and what is left shared among the others.
fn seg_shares(room : Double, least : Array[Double]) -> Array[Double] {
  let n = least.length()
  let kept = Array::make(n, false)
  let mut share = 0.0
  let mut again = true
  while again {
    again = false
    let mut left = room
    let mut free = 0
    for i in 0..<n {
      if kept[i] {
        left = left - least[i]
      } else {
        free = free + 1
      }
    }
    share = if free > 0 { dmax(0.0, left) / free.to_double() } else { 0.0 }
    for i in 0..<n {
      if !kept[i] && least[i] > share {
        kept[i] = true
        again = true
      }
    }
  }
  least.mapi(fn(i, l) { if kept[i] { l } else { share } })
}

///|
/// Match the bottom bar's hold time and how far its thumb leans toward the finger.
let seg_hold_ms : Double = 200.0

///|
let seg_drag_lean : Double = 0.25

///|
/// How wide a filling Seg of `labels` is with their words whole at their size with their sides, and how narrow it may
/// go: the chosen one's (the widest's) words with the chevron (seg_room's, the old view's), as node `v` has the system's
/// size of words and the theme as they change (a binding reading it follows them).
fn seg_room_of(v : @view.View, labels : Array[String]) -> (Double, Double) {
  v.words_redone() |> ignore
  let t = @ui.tree_theme()
  let size = node_sp(v, t.text_size(Base).0)
  let whole = labels.fold(init=2.0 * seg_inset, fn(s, l) { s + node_words_w(l, size) + 2.0 * seg_side })
  let menu = node_sp(v, t.text_size(Body).0)
  let widest = labels.fold(init=0.0, fn(m, l) { dmax(m, node_words_w(l, menu)) })
  (whole, 2.0 * seg_inset + 2.0 * seg_menu_in + widest + seg_menu_gap + seg_chevron)
}

///|
/// A narrow page's choice at a head's end (segmented's there: seg_room), in `parent`: a Seg as wide as its options
/// with their words whole at their size with their sides, as narrow as the chosen one's (the widest's) words with the
/// chevron where its line has less (giving way first: what is at a head's end does), filling what that leaves it, as
/// seg_fill_node is; its words at the system's size of words as that changes. `labels`, `chosen`, `choose`, `said`:
/// seg_fill_node's.
#callsite(autofill(loc))
pub fn seg_head_node(
  parent : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  said? : String = "",
  loc~ : SourceLoc,
) -> @view.View {
  parent.box(made_for=loc, fn(b) {
    let room = fn() { seg_room_of(b, labels()) }
    b
    .width(By(fn() { Some(room().0) }))
    .min_width(By(fn() { Some(room().1) }))
    .shrink(Is(1.0))
    |> ignore
    seg_fill_node(b, labels, chosen, choose, said~) |> ignore
  })
}

///|
/// A choice of a few on a page made once (segmented's), by how the page is laid out (look_node), in `slot`, which it
/// lays out: narrow, Seg (seg_fill_node) sharing its line, the slot growing from none to what the line leaves it, or
/// at a head's end (`head`) as wide as its options (seg_head_node); wide, the web's Segmented (seg_node), as wide as
/// its options, the slot as wide as it. `labels`, `chosen`, `choose`, `said`: theirs.
#callsite(autofill(loc))
pub fn segmented_node(
  slot : @view.View,
  labels : () -> Array[String],
  chosen : () -> Int,
  choose : (Int) -> Unit,
  head? : Bool = false,
  said? : String = "",
  loc~ : SourceLoc,
) -> Unit {
  match look_node(slot) {
    Wide => seg_node(loc~, slot, labels, chosen, choose, said~) |> ignore
    Narrow if head => seg_head_node(slot, labels, chosen, choose, said~) |> ignore
    Narrow => {
      slot.grow(Is(1.0)).basis(Is(Some(0.0))).min_width(Is(Some(0.0))) |> ignore
      seg_fill_node(slot, labels, chosen, choose, said~) |> ignore
    }
  }
}

///|
/// How high segmented_node stands in a page laid out `look`: wide, the web's Segmented's track round its options; narrow,
/// Seg's (segmented_height's).
pub fn segmented_node_height(look : Look) -> Double {
  match look {
    Narrow => segmented_narrow_h
    Wide => segmented_h + 2.0 * segmented_pad
  }
}

///|
/// A choice of a few ways, an icon each, among a bar's buttons (segmented's of icons in a bar: `bar` with `icons`), as
/// nodes in `parent`, over mbui's headless radio group: as high as the bar's buttons, its track 2 round its options, each
/// option square, the chosen one on the lifted thumb, which goes to the one chosen as that changes; its icons the ink
/// where chosen or pointed at, else muted. `ways` are its options by key (each key's icon and what it is called, read
/// out and its tip), as they are now; `chosen` the key chosen, `choose` told the one pressed (the one chosen again
/// too: where the room has not what was chosen before, the one shown is chosen again). The node.
#callsite(autofill(loc))
pub fn seg_icons_node(
  parent : @view.View,
  ways : () -> Array[(String, String, String)],
  chosen : () -> String,
  choose : (String) -> Unit,
  said? : String = "",
  tips? : TipLayer,
  loc~ : SourceLoc,
) -> @view.View {
  let pad = segmented_bar_pad
  let high = icon_button_side - 2.0 * pad
  let at = fn() { ways().search_by(fn(w) { w.0 == chosen() }).unwrap_or(0) }
  let g = @lg.liquid_segmented_node(
    parent,
    fn() { ways().map(fn(w) { w.2 }) },
    at,
    fn(i) {
      match @signals.untracked(ways).get(i) {
        Some((k, _, _)) => choose(k)
        None => ()
      }
    },
    glass_track=false,
    pad~,
    gap=segmented_gap,
    widths=fn() { Array::make(ways().length(), high) },
    height_by=fn() { icon_button_side },
    kind=Radio,
    said~,
    in_node=true,
    render_item=fn(seg, idx, is_chosen) {
      icon_node(
        seg,
        "",
        16.0,
        By(fn() {
          if is_chosen() || seg.pointed() {
            theme().p.text
          } else {
            theme().p.muted
          }
        }),
        name_now=fn() { ways().get(idx).map(fn(w) { w.1 }).unwrap_or("") },
      )
      |> ignore
      match tips {
        Some(layer) =>
          tip_node(layer, seg, fn() { ways().get(idx).map(fn(w) { w.2 }).unwrap_or("") }) |> ignore
        None => ()
      }
    },
    loc~,
  )
  g
  .width(By(fn() {
    let n = ways().length()
    Some(2.0 * pad + n.to_double() * high + dmax(0.0, (n - 1).to_double()) * segmented_gap)
  }))
  .shrink(Is(0.0))
  |> ignore
  g
}
