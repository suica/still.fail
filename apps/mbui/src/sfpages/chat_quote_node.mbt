// A passage of a message picked with the mouse in a chat's page made as nodes, quoted into its draft (the old page's
// pick_pop: sfbase's pick.mbt; web Chat.tsx useSelectionQuote, Chat.css.ts quotePop): once the pointer has let go of a
// pick wholly within one message, a small dark pill 引用 with its mark 8 over the end it let go (mbui's picked_now,
// picked_end_piece); pressed, what is picked kept (keeps_picked), quoted as the old page quoted it (whose words, the
// words, the message, as what: chat_layers'), let go, and gone. A pick across messages, or in a row that is no message
// (a notice's line, the list's own rows), gives none; what is on its way from here and what was said in Slack or Feishu
// are quoted with no id (`ts` ""). A finger's
// pick has no pill: the page's own bar over it, as the old page's (sfbase's pick_bar; @sf.pick_bar_node), never the
// system's text menu (mbui's picked_bar; the user, 2026-11-15: 「为什么要用系统的」): 引用, 复制, 全选 (but after it), and
// what that message offers of itself where it offers it (多选, its turn shared from the chat's picture; 复制链接, its
// link), each pressed doing it for what was picked as the bar was made.

///|
/// The message of chat `rows` whose words a mouse's pick lies wholly within, once the pointer let it go: what is
/// picked and the message (a message the core has, by its ts: the id the old page quoted by); none otherwise.
fn chat_quotable(rows : ChatBodyList) -> (@ui.WordsPicked, Message)? {
  guard chat_picked_message(rows) is Some((p, m)) && !p.finger else { return None }
  Some((p, m))
}

///|
/// The message of chat `rows` whose words a finger's pick lies wholly within, once let go: what is picked and the
/// message; none otherwise.
fn chat_finger_picked(rows : ChatBodyList) -> (@ui.WordsPicked, Message)? {
  guard chat_picked_message(rows) is Some((p, m)) && p.finger else { return None }
  Some((p, m))
}

///|
/// The message of chat `rows` whose words what is picked lies wholly within, once let go, with the mouse or a finger
/// (one the viewer sent not yet the chat's too: outgoing_said; one said in Slack or Feishu: elsewhere_said): what is
/// picked and the message; none otherwise.
fn chat_picked_message(rows : ChatBodyList) -> (@ui.WordsPicked, Message)? {
  guard @ui.picked_now() is Some(p) && p.of.length() == 1 else { return None }
  match rows.read().get(p.of[0]) {
    Some({ entry: Said(m), .. }) if m.ts != "" => Some((p, m))
    // (one of the viewer's not the chat's yet, on its way or failed: theirs, of no message, as the old rows quote it)
    Some({ entry: Out(o), .. }) => Some((p, outgoing_said(o)))
    // (one said in Slack or Feishu, the chat's only words where it has been nowhere else: whose there, of no message)
    Some({ entry: Sent(s), .. }) => Some((p, elsewhere_said(s)))
    _ => None
  }
}

///|
/// What was said in Slack or Feishu (`s`) as a message to quote: its words, whose they are there (a person's where it
/// was heard there, its agent's where it was sent), of no message in the chat (`ts` "", as outgoing_said's).
fn elsewhere_said(s : Elsewhere) -> Message {
  { ..@sfbase.message_of({}), author_kind: if s.received { "person" } else { "agent" }, text: s.text, by: s.by }
}

///|
/// What is picked within one message of chat `rows` quoted into draft `draft` (writing_quote: whose words and as what,
/// as the old rows said them, sfpages' picking; its text trimmed, nothing where that is empty) and let go; picked
/// across messages or in no message, nothing done, what is picked left as it is.
fn chat_quote_take(src : Source, draft : String, rows : ChatBodyList) -> Unit {
  guard @signals.untracked(fn() { chat_picked_message(rows) }) is Some((p, m)) else { return }
  chat_quote_of(src, draft, p, m)
}

///|
/// What `p` says is picked, of message `m`, quoted into draft `draft` as chat_quote_take quotes it, and let go: as it
/// was when what quotes it was made (the bar over a finger's pick), not found again as it is pressed.
fn chat_quote_of(src : Source, draft : String, p : @ui.WordsPicked, m : Message, whole? : Bool = false) -> Unit {
  let text = chat_picked_words(p, m, whole).trim(chars=" \n\t").to_owned()
  if text != "" {
    let author = if m.mine { @sf.t("web-main.chat.you") } else { m.by.name }
    let role = if !m.mine && m.author_kind == "agent" { "agent" } else { "person" }
    @sfbase.writing_quote(src, @sfbase.writing(src, draft), {
      "author": Json::string(author),
      "text": Json::string(text),
      "ts": Json::string(m.ts),
      "role": Json::string(role),
    })
  }
  @ui.picked_let_go()
}

///|
/// What is picked of message `m` as `p` says it, or all of its words where all of it was picked (`whole`: 全选 over a
/// finger's pick): those as the message has them, not what its rows drawn round what shows hold of them (a long
/// message's pieces past them made of none, its words picked of them cut short).
fn chat_picked_words(p : @ui.WordsPicked, m : Message, whole : Bool) -> String {
  if whole && m.text.trim(chars=" \n\t") != "" {
    m.text
  } else {
    p.text
  }
}

///|
/// Let go of this pick if it has not been replaced by a later one.
fn chat_pick_gone(p : @ui.WordsPicked) -> Unit {
  if @signals.untracked(@ui.picked_now) is Some(q) && q.made == p.made {
    @ui.picked_let_go()
  }
}

///|
/// Over chat `r`'s list in `v` (its rows `rows`, each message's words, from where they are read, said of its key:
/// picked_of, so 全选 over a finger's pick takes all of that message's, @ui's finger_select_all):
/// the pill 引用 over a mouse's pick within one message, quoting it into the chat's draft (writing_quote, its text
/// trimmed, nothing where that is empty), what is picked let go then. One for each pick (its `made`). A finger's pick
/// in what `v` holds has the page's bar over it instead (@sf.pick_bar_node: 引用, 复制, 全选, the message's own items, its
/// MessageShare in the chat `here` is: message_share_of).
fn chat_quote_node(
  v : @view.View,
  src : Source,
  r : ChatRef,
  here : MessageNodeHere,
  rows : ChatBodyList,
  place : @view.ListPlace[String],
) -> Unit {
  let draft = r.station + ":" + r.session
  // (a pick whose words' block was put by as the list moved on: let go of it and its bar or pill)
  place.on_sight(fn(_) {
    match chat_picked_message(rows) {
      Some((p, _)) =>
        match @ui.view_tree().bind(fn(tree) { tree.view_of(p.ends_in) }) {
          Some(end) if !end.shown_nowhere() => ()
          _ => @ui.picked_let_go()
        }
      None => ()
    }
  })
  // (a finger's pick: the bar over it, the page's own, not the system's text menu: 引用, 复制, 全选, and what the message
  // offers of itself, its turn shared and its link copied; one bar for each pick as it is let go of, made anew as what
  // is picked changes, 全选's too)
  @ui.picked_bar(v) |> ignore
  // (the pick whose 全选 was pressed: its bar made again offers no 全选)
  let alled : Ref[Int] = Ref(-1)
  // (in the layer over all of the window (@sf.window_tips), as a tip is: over the rows round what is picked, whose own
  // presses it covers while it shows; made there as a finger first picks, where there is one, living with the list;
  // else over the list itself)
  let bar_in = fn(at : @view.View) {
    at.pick(fn() { chat_finger_picked(rows).map(fn(q) { q.0 }) }, fn(holds, picked) {
      guard picked is Some(p) && @signals.untracked(fn() { chat_finger_picked(rows) }) is Some((_, m)) else { return }
      // (where the words it ends in are no more, made of none of a list's rows round what shows as it was moved on, or
      // put by to be another's: no bar beside nothing, and what was picked let go as they go, the bar with it)
      guard @ui.view_tree().bind(fn(tree) { tree.view_of(p.ends_in) }) is Some(end) else { return }
      // (all of the message picked by 全选: its words whole, quoted and copied)
      let whole = alled.val == p.made
      let items : Array[@sf.PickBarItem] = [
        {
          label: @sf.t("android-chat.pick.quote"),
          icon: if p.ends_at_start { "quote-open" } else { "quote" },
          mark: false,
          press: fn() { chat_quote_of(src, draft, p, m, whole~) },
        },
        {
          label: @sf.t("common.copy"),
          icon: "copy",
          mark: false,
          press: fn() {
            @sfbase.copy_out(chat_picked_words(p, m, whole), said=@sf.t("android-chat.annotate.copied"))
            @ui.picked_let_go()
          },
        },
      ]
      if !whole {
        items.push({
          label: @sf.t("android-chat.annotate.selectAll"),
          icon: "",
          mark: false,
          press: fn() {
            alled.val = p.made
            @ui.picked_select_all()
          },
        })
      }
      // (one not the chat's yet has no turn to share, no link)
      match (if m.ts == "" { None } else { @signals.untracked(fn() { message_share_of(src, here, fn() { m }) }) }) {
        Some(s) => {
          items.push({
            label: @sf.t("web-main.chat.selectMessages"),
            icon: "check-circle",
            mark: true,
            press: fn() {
              @ui.picked_let_go()
              (s.go)()
            },
          })
          let link = @signals.untracked(fn() { (s.link)() })
          if link != "" {
            items.push({
              label: @sf.t("common.link.copy"),
              icon: "link",
              mark: true,
              press: fn() {
                @sfbase.copy_out(link, said=@sf.t("common.link.copied"))
                @ui.picked_let_go()
              },
            })
          }
        }
        None => ()
      }
      holds.box(fn(b) {
        let gone = fn() { chat_pick_gone(p) }
        let unkept = end.owns_while(gone)
        b.owns(unkept) |> ignore
        // (taken for another message's words: View::scrolls_window's `reused`)
        end.on_reused(gone)
        @ui.keeps_picked(b)
        .beside(p.ends_in, side=Top, offset=chat_pick_bar_over, piece=@ui.picked_end_piece(p))
        |> ignore
        @sf.pick_bar_node(b, items) |> ignore
      })
      |> ignore
    })
  }
  let made = Ref(false)
  let make = fn() {
    guard !made.val else { return }
    made.val = true
    match (@sf.window_tips().layer)() {
      Some(l) => bar_in(l.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(v))
      None => bar_in(v)
    }
  }
  v.reacts(fn() { chat_finger_picked(rows) is Some(_) }, fn(on) { if on { make() } })
  let quote_in = fn(host : @view.View) {
    host.pick(fn() { chat_quotable(rows).map(fn(q) { q.0.made }) }, fn(holds, made) {
      guard made is Some(_) && @signals.untracked(fn() { chat_quotable(rows) }) is Some((p, _)) else { return }
      guard @ui.view_tree().bind(fn(tree) { tree.view_of(p.ends_in) }) is Some(end) else { return }
      @sf.action_box_node(holds, fn() { @sf.t("web-main.chat.quote") }, fn(_) { chat_quote_take(src, draft, rows) }, fn(b) {
        let gone = fn() { chat_pick_gone(p) }
        let unkept = end.owns_while(gone)
        b.owns(unkept) |> ignore
        end.on_reused(gone)
        @sf.style_node(b, fn() { chat_quote_pill })
        @sf.glass_capsule_node(@ui.keeps_picked(b), interactive=true)
        .beside(p.ends_in, side=Top, offset=8.0, piece=@ui.picked_end_piece(p))
        |> ignore
        @sf.hover_ground_node(b)
        @sf.icon_node(b, if p.ends_at_start { "quote-open" } else { "quote" }, chat_quote_icon, By(fn() { @sf.theme().p.text })) |> ignore
        @sf.words_node(b, fn() { @sf.t("web-main.chat.quote") }, fn() { chat_quote_words }) |> ignore
      })
      |> ignore
    })
  }
  let quote_made = Ref(false)
  let make_quote = fn() {
    guard !quote_made.val else { return }
    quote_made.val = true
    match (@sf.window_tips().layer)() {
      Some(l) => quote_in(l.box(fn(h) { h.over(Is(true)) |> ignore }).lives_with(v))
      None => quote_in(v)
    }
  }
  v.reacts(fn() { chat_quotable(rows) is Some(_) }, fn(on) { if on { make_quote() } })
}

///|
/// The pill (quotePop: 26 high, 10 in, its mark 4 before its words, round; single-layer liquid glass as the finger's
/// pick bar and the floating buttons are (`glass_menu()`, falling back to `panel_ground()` + hairline `control_edge_w`
/// border under `MBUI_GLASS=solid`) with outside-only `float_shadow()`, the hover ground where the hand is on it), its
/// mark 12 and its words in the ink.
// kept across runs: a value (no field of it changes)
let chat_quote_pill : @ui.Style = @ui.style(
  row=true,
  h=@sf.quote_pop_h,
  px=S2_5,
  gap=S1,
  radius=Full,
  align=ACenter,
)

///|
let chat_quote_icon : Double = 12.0

///|
// kept across runs: a value (no field of it changes)
let chat_quote_words : @ui.TextStyle = @ui.text_style(size=Caption, weight=Medium, color=Fg, wrap=false)

///|
/// How far over where a finger's pick ends its bar stands (pick_bar's: 52 over the line's top, the bar 40 high).
let chat_pick_bar_over : Double = 12.0
