// ⌘F's bar (find_bar's) as nodes of the window's tree, made once in a chat's bar while its find is open there: what it
// did not look in before its field, while that is so; the field (finding's, the one Field the find keeps) 320 wide,
// giving way first down to 160, its count and its three round buttons at its end: the library's find in a page
// (@sf.page_find_node). What is typed is looked for find_typing_ms after the last edit, at that edit's moment and that
// much later (View::at_moment), never by watching it; Enter the next, ⇧Enter the one before (the keymap's `find.prev`
// where the bar is, `Find`: settings' keymap.mbt), Escape lets it go.
// It fades in as it comes (kit's tip_in: 120 ms, eased out), and out as long once the find closes, what holds it keeping
// it that long (chat_bar_wide_node's pick, `leave_of`), showing what it showed as the find closed (what the core found,
// where the reader was, the words typed), not the find as it is once closed; opened again meanwhile, back in from where
// it is (@motion.presence_in: a fade, carrying nothing).

///|
/// ⌘F's bar in `parent` (a row it lies along in) for chat `r` (its thread `thread`, as the chat's view has it), the list
/// it goes along `list`; its buttons' tips in `tips`. The bar's node.
pub fn find_bar_node(
  parent : @view.View,
  src : Source,
  r : ChatRef,
  thread : () -> Double?,
  list : FindList,
  tips : @sf.TipLayer,
) -> @view.View {
  let key = chat_key(r)
  let made : Ref[@view.View?] = Ref(None)
  // (what it shows of the find: as it is while it is open in this chat, held as it was once it closes, so the bar going
  // fades out as it was; sfpages' find_close empties the find at once)
  let open_here = fn() { finding.chat.get() == key }
  let found = @signals.signal(finding.found.untracked())
  let place = @signals.signal(
    (finding.position.untracked(), finding.total.untracked()),
    same=fn(a, b) { a == b },
  )
  let bringing = @signals.signal(finding.bringing.untracked(), same=fn(a, b) { a == b })
  parent.box(fn(bar) {
    made.val = Some(bar)
    @sf.style_node(bar, fn() { find_bar_style }, in_row=true)
    // (giving way along the row as an old view's box does, its field first down to its least)
    bar.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
    // (as it comes: faded in from its making, its cause's moment; out as what holds it lets it go, back in as it is
    // shown again on its way out: a fade, carrying nothing)
    bar.alpha(By(@motion.presence_in(bar, @motion.tween(find_in_ms, ease=Out)))) |> ignore
    bar.reacts(
      fn() {
        if open_here() {
          Some((finding.found.get(), find_position(), finding.bringing.get()))
        } else {
          None
        }
      },
      fn(now) {
        match now {
          Some((f, at, b)) => {
            found.set(f)
            place.set(at)
            bringing.set(b)
          }
          None => ()
        }
      },
    )
    // what it did not look in, while it is so
    bar.show(
      fn() {
        match found.get() {
          Some(f) => !f.whole
          None => false
        }
      },
      fn(n) {
        @sf.style_node(n, fn() { find_note_box }, in_row=true)
        n.shrink(Is(1.0)).min_width(Is(Some(0.0))) |> ignore
        @sf.words_node(
          n,
          fn() {
            let (held, of) = match found.get() {
              Some(f) => (f.held, f.of)
              None => (0, 0)
            }
            if bringing.get() {
              @sf.t("web-main.find.bringing", args=[("held", held.to_string())])
            } else {
              @sf.t("web-main.find.partial", args=[("held", held.to_string()), ("of", of.to_string())])
            }
          },
          fn() { find_meta },
        )
        |> ignore
      },
    )
    // (what is typed as it stands as the bar is made: looked for that much later, as an edit's is)
    finding.query = @signals.untracked(fn() { finding.field.text() }).replace_all(old="\n", new="")
    let due = Ref(fn() {  })
    let ask = fn(typed : String) {
      (due.val)()
      due.val = fn() {  }
      guard typed != finding.asked.untracked() else { return }
      let now = fn() {
        // (closed meanwhile: nothing asked)
        guard finding.chat.untracked() == key else { return }
        match @signals.untracked(thread) {
          Some(th) => find_ask(src, r.station, th, key, list, typed)
          None => ()
        }
      }
      // (none typed: nothing found at once)
      if typed.trim(chars=" ").is_empty() {
        now()
      } else {
        due.val = bar.at_moment(bar.cause_at() + find_typing_ms, now)
      }
    }
    ask(finding.query)
    // which of how many, or none (nothing found yet while the rest is read is not "nothing found"; nor before the core
    // has said where the reader is among them)
    let said = fn() {
      let (at, total) = place.get()
      match found.get() {
        Some(_) if !(bringing.get() && total == 0) && !(total > 0 && at == 0) =>
          if total > 0 {
            "\{at}/\{total}"
          } else {
            @sf.t("web-main.find.none")
          }
        _ => ""
      }
    }
    // the library's find in a page (@sf.page_find_node): the field (finding's, the one Field the find keeps), what
    // was found, the one before and after and the find let go
    @sf.page_find_node(
      bar,
      said,
      fn(d) { find_move(src, key, list, d) },
      fn(_) { place.get().1 > 0 },
      fn() {
        (list.forget)()
        find_close()
      },
      field=finding.field,
      placeholder_by=fn() { @sf.t("web-main.find.placeholder") },
      edited=fn(words) {
        guard finding.chat.untracked() == key else { return }
        // (a new line put in it otherwise: taken out)
        let typed = words.replace_all(old="\n", new="")
        finding.query = typed
        ask(typed)
      },
      frame=fn(f) {
        @sf.style_node(f, fn() { find_field_style }, in_row=true)
        f
        .shrink(Is(1.0))
        .ground(Is(0L))
        .glass(By(fn() { Some(@sf.find_panel_glass()) }))
        .edge(By(fn() { if f.glass_solid() { @sf.overlay_solid_edge() } else { (0.0, 0L) } }))
        .shadow(By(@sf.glass_overlay_shadow))
        .shadow_outside(Is(true))
        |> ignore
      },
      said_look=fn() { find_meta },
      tips~,
      field_in=@ui.Space::px(S3) - @ui.capsule_in(find_field_h / 2.0, find_button_w),
    )
    |> ignore
  })
  |> ignore
  made.val.unwrap()
}

///|
/// How long the bar takes to come, and to go (kit's tip_in, as find_bar's @motion.entering), the chat's buttons as long
/// coming back in its place (chat_bar_wide_node's).
pub let find_in_ms : Double = 120.0
