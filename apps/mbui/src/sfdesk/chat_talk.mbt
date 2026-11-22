// A chat's talk on the desktop (still.fail web/src/Chat.tsx ChatShown): its list (sfpages chat_page_body_node) over the pane, the
// bar over it, the composer at its foot, what is picked and dropped over them.

///|
/// How tall the chat's bar over the list is (pageBar: 45; in a panel of its own as much taller as puts its buttons in
/// the panel's corner concentric with it: chat_bar_box_tape; `in_pane` as the page built now is), and the list's room
/// under it over its first row (24).
fn chat_bar_room(in_pane? : Bool = @sf.in_pane()) -> Double {
  @sf.wide_bar_h + (if in_pane { @sf.tape_bar_over() } else { 0.0 })
}

///|
let list_head_gap : Double = 24.0

///|
/// Chat `r`'s messages where its page is made with its inside nodes (chat_page_made's
/// `body`, `shows` whether it is drawn), in `v`, as wide as it is given: under the bar's room, `in_pane` the page a
/// panel of its own (chat_bar_room); its composer made by `composer` in the list's foot. What the page's old view
/// hands the system's bars said here as nodes (chat_bar_handed_node); ⌘F its find, in its bar.
fn chat_body_nodes(
  v : @view.View,
  src : Source,
  r : ChatRef,
  tips : @sf.TipLayer,
  stint : () -> Int,
  composer : (@view.View) -> Unit,
  shows : () -> Bool,
  in_pane? : Bool = false,
  on_stack? : () -> Bool = fn() { true },
) -> Unit {
  // (the composer's node: what is carried over it is its own to show, chat_drop_node)
  let held : Ref[@view.View?] = Ref(None)
  // (what covers its top is the bar as it is drawn; its room under it, room)
  @sfpages.chat_page_body_node(
    v,
    src,
    r,
    tips~,
    stint~,
    shows~,
    on_stack~,
    cover=fn() { chat_bar_room(in_pane~) },
    room=list_head_gap,
    foot_clear_extra=fn() { 36.0 },
    composer=fn(n) {
      held.val = Some(n)
      composer(n)
    },
  )
  // ⌘F (chat.find, the keymap's Chat, taken while the tree gives the page keys): the chat's find opened in its bar
  // (wide_bar_of's), as the old page's chat_page took it, but in a chat not made yet
  v.on_action("chat.find", fn(_) {
    guard @sfbase.chat_view_now(src, r) is Some({ thread: Some(_), .. }) else { return false }
    chat_find_open(r)
    true
  })
  |> ignore
  // the rest of the chat's own keys that act beyond its list, as the old page's chat_keys took them and by what it
  // did: ⌘⇧E into the archive, ⌘⇧H its first agent's history beside it, ⌘. its agents at work stopped, ⌘⇧J its
  // services and jobs, ⌘⇧D its station's own display; what it cannot do now passes the key on
  // (its head alone: sfbase's chat_view_now)
  let chat_view = fn() { @sfbase.chat_view_now(src, r) }
  v.on_action("chat.archive", fn(_) {
    guard chat_view() is Some(cv) && !cv.archived && !cv.offline else { return false }
    guard @sfbase.workspace_in_view(src).0 is Some(w) else { return false }
    archive_asked(src, w, r, cv, @sfbase.chat_head_json(src, r))
    true
  })
  .on_action("chat.history", fn(_) {
    guard chat_view() is Some(cv) && cv.agents.length() > 0 else { return false }
    history_toggle(src, r, cv)
    true
  })
  .on_action("chat.stop", fn(_) {
    guard chat_view() is Some(cv) else { return false }
    stop_agents(src, r, cv)
    true
  })
  .on_action("chat.jobs", fn(_) {
    guard chat_view() is Some(_) else { return false }
    jobs_pressed(src, r)
    true
  })
  .on_action("chat.screen", fn(_) {
    guard chat_view() is Some(cv) else { return false }
    chat_remote_first(r, cv.screens, cv.can_terminal())
    true
  })
  .key_context("Chat")
  .on_action("panel.tab.close", fn(_) { side_close_front(src, r) })
  .on_action("panel.tab.reopen", fn(_) { side_reopen_key(src, r) })
  .on_action("panel.tab.prev", fn(_) { side_step(src, r, -1) })
  .on_action("panel.tab.next", fn(_) { side_step(src, r, 1) })
  |> ignore
  // (another chat's find let go as this one's page comes to be drawn, as chat_page did as it was built: closed, what it
  // looked for forgotten, nothing left to go to there; a page kept of a chat left too, as it is drawn again; not while
  // it is made behind another)
  v.reacts(shows, fn(on) {
    if on && find_chat() != "" && find_chat() != chat_key(r) {
      find_forget()
    }
  })
  chat_bar_handed_node(v, src, r)
  chat_drop_node(v, src, r.station + ":" + r.session, fn() { r.station }, fn() { held.val }, shows)
}

///|
/// A row of the 文件 tab carried over the page made with its inside nodes of the chat whose draft is `draft` on station
/// `station()` as it is let go (`v`; chat_body_nodes; the new chat's, new_frame_node's `over`), as the old pane
/// had it (drop_hint, chat_drop): while it is where it would land on the page were it let go (drop_on_page) but on the
/// composer (`composer`'s node), frosted over all of it with 松开以添加到消息 under the row's mark, drawn only; let go on the page, into the
/// chat's draft (composer.add), named by its path or sent as a file as the chat takes what is dragged in. Where it was
/// let go is the page's as a drop from outside is (mbui's Tree::drop_at): the node drawn there, the page's node holding
/// it (what is drawn over the page there, a panel or another page, keeps it).
pub fn chat_drop_node(
  v : @view.View,
  src : Source,
  draft : String,
  station : () -> String,
  composer : () -> @view.View?,
  shows : () -> Bool,
) -> Unit {
  v.box(fn(h) {
    h.over(Is(true)).presses(Is(false)) |> ignore
    h.show(
      fn() {
        dragged() is Some(_) &&
        // (where the row would land were it let go now, followed as the pointer moves and as what is under it is
        // placed: the page's anywhere over it, its messages' ground beside and between them too, what takes no press
        // as what does; not where something drawn over the page is, nor on the composer's own points; nothing looked
        // for while no row is carried)
        h.pointer_piece(fn(_, _) {
          guard dragged() is Some(_) else { return 0 }
          let (x, y) = v.tree.pointer_said()
          match drop_on_page(v, x, y) {
            Some(id) =>
              match composer() {
                Some(n) if v.tree.holds(n.id(), id) => 0
                _ => 1
              }
            None => 0
          }
        }) ==
        1
      },
      fn(o) {
        @sf.glass_capsule_node(o.grow(Is(1.0)), sharing=false) |> ignore
        @sf.style_node(o, fn() { drop_hint_box })
        @sf.icon_node(
          o,
          "file",
          drop_folder * 2.0,
          By(fn() { @sf.theme().p.muted }),
          name_now=fn() { if dragged().map(fn(i) { i.dir }).unwrap_or(false) { "folder" } else { "file" } },
        )
        |> ignore
        o.box(fn(s) {
          s
          .words(By(fn() { @sf.t("web-main.composer.dropHere") }))
          .words_look(By(fn() { @ui.style_words(drop_hint_words) }))
          .ink(By(fn() { @sf.theme().p.text }))
          |> ignore
        })
        |> ignore
      },
      at_once=true,
    )
  })
  |> ignore
  // (let go off the tab: where, tab_take_drop's; on a node of the page's, its messages or its composer's old view)
  v.reacts(
    fn() { dragged() is Some(_) },
    fn(carried) {
      guard !carried && shows() && ftab.let_go is Some((item, x, y)) else { return }
      guard drop_on_page(v, x, y) is Some(_) else { return }
      ftab.let_go = None
      writing_drop(src, writing(src, draft), station(), [@sfpages.dropped_of(item)], @sfpages.drops_as_files(src, draft))
    },
    at_start=false,
  )
}

///|
/// What a row let go at (x, y) in the window lands on of chat page `v` (mbui's Tree::drop_at: the node drawn there, held
/// by the page's node), None where it lands on none of it (off the page, or on what is drawn over it there): one rule for
/// where the row is taken and where the page is frosted as it is held (chat_drop_node).
fn drop_on_page(v : @view.View, x : Double, y : Double) -> @view.NodeId? {
  match v.tree.drop_at(x, y) {
    Some(OnNode(id)) | Some(OnOld(id)) if v.tree.holds(v.id(), id) => Some(id)
    _ => None
  }
}

