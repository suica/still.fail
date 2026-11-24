// Experimental selection intent inference panel and pinned reply cards:
// shows only the inferred reply directly ("I'm feeling lucky" style), with Pin and Copy actions.

///|
fn open_selection_intent(
  src : Source,
  r : ChatRef,
  thread : Double,
  draft : String,
  selection : String,
  message_ts : String,
  author : String,
  role : String,
  from~ : @sf.Anchor,
) -> Unit {
  @sfbase.selection_intent_ask(src, r.station, thread, draft, selection, message_ts, author, role)
  @sf.panel_nodes(
    "",
    fn(v, close) { selection_intent_body(v, src, close) },
    from~,
    heads_itself=true,
    gone=fn() { @sfbase.selection_intent_reset() },
  )
}

///|
#derive(Eq)
priv enum IntentViewKind {
  Loading
  Failed
  Ready
}

///|
fn selection_intent_body(v : @view.View, src : Source, close : () -> Unit) -> Unit {
  let s = @sfbase.selection_intent
  // (its words text_in in from where the panel's grounds stand, as a small panel's words are)
  let column = intent_column.then(@ui.style(px=@sf.room_of(@sf.text_in)))
  // (its head: 戳一下, and at its end what can be done with the answer as quiet keys, as a pinned answer's head has)
  v.box(fn(head) {
    @sf.style_node(head, fn() { intent_head.then(@ui.style(pl=@sf.room_of(@sf.text_in))) })
    head.box(fn(t) {
      @sf.style_node(t, fn() { intent_pin_title_wrap }, in_row=true)
      @sf.words_node(t, fn() { @sf.t("web-main.chat.inferIntent.title") }, fn() { intent_title_words }) |> ignore
    })
    |> ignore
    selection_intent_keys(head, src, close)
  })
  |> ignore
  v.pick(
    fn() {
      if s.loading.get() {
        IntentViewKind::Loading
      } else if s.error.get() != "" {
        IntentViewKind::Failed
      } else {
        IntentViewKind::Ready
      }
    },
    fn(area, kind) {
      @sf.style_node(area, fn() { column })
      match kind {
        Loading =>
          area.box(fn(row) {
            @sf.style_node(row, fn() { intent_loading_row })
            @sf.spinner_node(row, size=14.0) |> ignore
            @sf.words_node(row, fn() { @sf.t("web-main.chat.inferIntent.loading") }, fn() { intent_meta_words })
            |> ignore
          })
          |> ignore
        Failed =>
          area.box(fn(said) {
            @sf.style_node(said, fn() { intent_failed_column })
            @sf.words_node(
              said,
              fn() {
                @sf.t(
                  if intent_outdated() {
                    "web-main.chat.inferIntent.outdated"
                  } else {
                    "web-main.chat.inferIntent.failed"
                  },
                )
              },
              fn() { intent_failed_title },
            )
            |> ignore
            @sf.words_node(
              said,
              fn() {
                if intent_outdated() {
                  @sf.t("web-main.chat.inferIntent.outdatedHint")
                } else {
                  s.error.get()
                }
              },
              fn() { intent_meta_words },
            )
            |> ignore
          })
          |> ignore
        Ready => @sf.words_node(area, fn() { s.reply.get() }, fn() { intent_reply_words }) |> ignore
      }
    },
  )
}

///|
/// Whether the request failed because the chat's station predates 戳一下 (its answer `no route …`): trying again
/// cannot help there, updating the station does.
fn intent_outdated() -> Bool {
  @sfbase.selection_intent.error.get().has_prefix("no route ")
}

///|
/// What can be done with the answer, as quiet round keys at the end of the popover's head: 复制 and 固定 while there is
/// one to have; 重试 in their place once it failed, none where the station must be updated (trying again cannot help).
fn selection_intent_keys(head : @view.View, src : Source, close : () -> Unit) -> Unit {
  let s = @sfbase.selection_intent
  let failed = fn() { !s.loading.get() && s.error.get() != "" }
  let none = fn() { s.loading.get() || s.reply.get() == "" }
  head.show(along_row=true, fn() { !failed() }, fn(k) {
    @sf.icon_button_node(
      k,
      "copy",
      fn() { @sf.t("common.copy") },
      fn() {
        let reply = @signals.untracked(fn() { s.reply.get() })
        if reply != "" {
          @sfbase.copy_out(reply, said=@sf.t("common.copied"))
        }
      },
      size=intent_pin_btn,
      icon_size=intent_pin_icon,
      disabled=none,
    )
    |> ignore
  })
  head.show(along_row=true, fn() { !failed() }, fn(k) {
    @sf.icon_button_node(
      k,
      "pin",
      fn() { @sf.t("web-main.chat.inferIntent.pin") },
      fn() {
        if @sfbase.selection_intent_pin() {
          @sfbase.toast_later(@sf.t("web-main.chat.inferIntent.pinned"))
          close()
        }
      },
      size=intent_pin_btn,
      icon_size=intent_pin_icon,
      disabled=none,
    )
    |> ignore
  })
  head.show(along_row=true, fn() { failed() && !intent_outdated() }, fn(k) {
    @sf.icon_button_node(
      k,
      "refresh",
      fn() { @sf.t("web-main.chat.inferIntent.retry") },
      fn() { @sfbase.selection_intent_retry(src) },
      size=intent_pin_btn,
      icon_size=intent_pin_icon,
    )
    |> ignore
  })
}

///|
/// Floating stack of pinned selection-intent reply cards in chat `draft`.
fn pinned_intents_node(v : @view.View, _src : Source, draft : String) -> Unit {
  v.show(
    fn() { @sfbase.selection_intent_feature.get() && @sfbase.pinned_intents_for(draft).length() > 0 },
    at_once=true,
    fn(layer) {
      layer.over(Is(true)) |> ignore
      @sf.style_node(layer, fn() { intent_pins_layer })
      layer.pick(fn() { @sfbase.pinned_intents_for(draft) }, fn(stack, list) {
        @sf.style_node(stack, fn() { intent_pins_stack })
        for p in list {
          pinned_intent_card(stack, p)
        }
      })
    },
  )
}

///|
fn pinned_intent_card(parent : @view.View, p : @sfbase.PinnedIntent) -> Unit {
  let id = p.id
  parent.box(fn(card) {
    @sf.style_node(card, fn() { intent_pin_card })
    @sf.glass_capsule_node(card, radius=Some(@sf.card_corner), panel=true) |> ignore
    // (its head's last key in its top right corner, concentric with the card's: as far in from the top and the right
    // as the card's corner is round past the key's)
    let corner_in = @sf.card_corner - intent_pin_btn / 2.0
    card.padding(Is((intent_pin_side_in, corner_in, corner_in, intent_pin_side_in))) |> ignore
    card.box(fn(head) {
      @sf.style_node(head, fn() { intent_pin_head })
      @sf.icon_node(head, "pin", intent_pin_icon, By(fn() { @sf.theme().p.accent_text })) |> ignore
      head.box(fn(t) {
        @sf.style_node(t, fn() { intent_pin_title_wrap }, in_row=true)
        if p.collapsed {
          @sf.words_node(t, fn() { p.reply }, fn() { intent_pin_preview }) |> ignore
        }
      })
      |> ignore
      @sf.icon_button_node(
        head,
        if p.collapsed { "chevron-down" } else { "chevron-up" },
        fn() { @sf.t(if p.collapsed { "web-main.chat.inferIntent.expand" } else { "web-main.chat.inferIntent.collapse" }) },
        fn() { @sfbase.selection_intent_toggle_collapse(id) },
        size=intent_pin_btn,
        icon_size=intent_pin_icon,
      )
      |> ignore
      @sf.icon_button_node(
        head,
        "copy",
        fn() { @sf.t("common.copy") },
        fn() { @sfbase.copy_out(p.reply, said=@sf.t("common.copied")) },
        size=intent_pin_btn,
        icon_size=intent_pin_icon,
      )
      |> ignore
      @sf.icon_button_node(
        head,
        "close",
        fn() { @sf.t("web-main.chat.inferIntent.unpin") },
        fn() { @sfbase.selection_intent_unpin(id) },
        size=intent_pin_btn,
        icon_size=intent_pin_icon,
      )
      |> ignore
    })
    |> ignore
    if !p.collapsed {
      @sf.words_node(card, fn() { p.reply }, fn() { intent_reply_words }) |> ignore
    }
  })
  |> ignore
}

///|
// kept across runs: a value (no field of it changes)
let intent_column : @ui.Style = @ui.css("w=Full pt=S1 pb=S3 gap=S2")

///|
// kept across runs: a value (no field of it changes)
let intent_head : @ui.Style = @ui.css("row w=Full gap=S1 pt=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let intent_title_words : @ui.TextStyle = @ui.text_style(size=Body, weight=Semibold, color=Fg, wrap=false, w=Full)

///|
// kept across runs: a value (no field of it changes)
let intent_loading_row : @ui.Style = @ui.css("row w=Full gap=S2 py=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let intent_failed_column : @ui.Style = @ui.css("w=Full gap=S1 py=S1")

///|
// kept across runs: a value (no field of it changes)
let intent_reply_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, leading=L5, w=Full)

///|
// kept across runs: a value (no field of it changes)
let intent_meta_words : @ui.TextStyle = @ui.text_style(size=Caption, color=Muted, w=Full)

///|
// kept across runs: a value (no field of it changes)
let intent_failed_title : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, weight=Medium, w=Full)

///|
// kept across runs: a value (no field of it changes)
let intent_pins_layer : @ui.Style = @ui.css("w=Full px=S5 pt=S16 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let intent_pins_stack : @ui.Style = @ui.css("gap=S2_5 align=AEnd")

///|
// kept across runs: a value (no field of it changes)
let intent_pin_card : @ui.Style = @ui.style(w=Fixed(@sf.panel_w), gap=S2, radius=Xl)

///|
/// How far a pinned answer's words are in from its card's left and foot.
let intent_pin_side_in : Double = 16.0

///|
// kept across runs: a value (no field of it changes)
let intent_pin_head : @ui.Style = @ui.css("row w=Full gap=S1 align=ACenter")

///|
// kept across runs: a value (no field of it changes)
let intent_pin_title_wrap : @ui.Style = @ui.style(w=@sf.grow)

///|
// kept across runs: a value (no field of it changes)
let intent_pin_preview : @ui.TextStyle = @ui.text_style(size=Meta, color=Muted, wrap=false, w=Full)

///|
let intent_pin_btn : Double = 26.0

///|
let intent_pin_icon : Double = 14.0
