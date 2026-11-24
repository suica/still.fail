// Experimental selection intent inference state: holds the selected passage, the in-flight `chat.selectionIntent` call,
// and the lightweight model's inferred intent and direct reply.

///|
pub(all) struct SelectionIntentState {
  station : @signals.Signal[String]
  thread : @signals.Signal[Double]
  draft : @signals.Signal[String]
  selection : @signals.Signal[String]
  message_ts : @signals.Signal[String]
  author : @signals.Signal[String]
  role : @signals.Signal[String]
  loading : @signals.Signal[Bool]
  intent : @signals.Signal[String]
  reply : @signals.Signal[String]
  model : @signals.Signal[String]
  error : @signals.Signal[String]
}

///|
// kept across runs: reset by selection_intent_reset()
pub let selection_intent : SelectionIntentState = {
  station: @signals.signal("", same=fn(a, b) { a == b }),
  thread: @signals.signal(-1.0, same=fn(a, b) { a == b }),
  draft: @signals.signal("", same=fn(a, b) { a == b }),
  selection: @signals.signal("", same=fn(a, b) { a == b }),
  message_ts: @signals.signal("", same=fn(a, b) { a == b }),
  author: @signals.signal("", same=fn(a, b) { a == b }),
  role: @signals.signal("", same=fn(a, b) { a == b }),
  loading: @signals.signal(false, same=fn(a, b) { a == b }),
  intent: @signals.signal("", same=fn(a, b) { a == b }),
  reply: @signals.signal("", same=fn(a, b) { a == b }),
  model: @signals.signal("", same=fn(a, b) { a == b }),
  error: @signals.signal("", same=fn(a, b) { a == b }),
}

///|
/// Serial of the latest inference request so a stale reply cannot overwrite a newer one or a closed panel.
// kept across runs: only counts on
let selection_intent_serial : Ref[Int] = Ref(0)

///|
pub fn selection_intent_reset() -> Unit {
  selection_intent_serial.val = selection_intent_serial.val + 1
  selection_intent.station.set("")
  selection_intent.thread.set(-1.0)
  selection_intent.draft.set("")
  selection_intent.selection.set("")
  selection_intent.message_ts.set("")
  selection_intent.author.set("")
  selection_intent.role.set("")
  selection_intent.loading.set(false)
  selection_intent.intent.set("")
  selection_intent.reply.set("")
  selection_intent.model.set("")
  selection_intent.error.set("")
}

///|
fn selection_intent_run(src : Source) -> Unit {
  let station = @signals.untracked(fn() { selection_intent.station.get() })
  let thread = @signals.untracked(fn() { selection_intent.thread.get() })
  let selection = @signals.untracked(fn() { selection_intent.selection.get() })
  let message_ts = @signals.untracked(fn() { selection_intent.message_ts.get() })
  let author = @signals.untracked(fn() { selection_intent.author.get() })
  guard station != "" && thread >= 0.0 && selection != "" else { return }
  selection_intent_serial.val = selection_intent_serial.val + 1
  let seq = selection_intent_serial.val
  selection_intent.loading.set(true)
  selection_intent.intent.set("")
  selection_intent.reply.set("")
  selection_intent.model.set("")
  selection_intent.error.set("")
  let params : Map[String, Json] = {
    "station": Json::string(station),
    "thread": Json::number(thread),
    "selection": Json::string(selection),
  }
  if message_ts != "" {
    params["messageTs"] = Json::string(message_ts)
  }
  if author != "" {
    params["author"] = Json::string(author)
  }
  (src.call)("chat.selectionIntent", Json::object(params), fn(res) {
    if selection_intent_serial.val != seq {
      return
    }
    selection_intent.loading.set(false)
    match res {
      Ok(v) => {
        selection_intent.intent.set(text(Some(v), "intent"))
        selection_intent.reply.set(text(Some(v), "reply"))
        selection_intent.model.set(text(Some(v), "model"))
      }
      Err(e) => selection_intent.error.set(error_words(e))
    }
  })
}

///|
/// Starts an intent-inference request for a selected passage in chat `thread` of `station`.
pub fn selection_intent_ask(
  src : Source,
  station : String,
  thread : Double,
  draft : String,
  selection : String,
  message_ts : String,
  author : String,
  role : String,
) -> Unit {
  selection_intent.station.set(station)
  selection_intent.thread.set(thread)
  selection_intent.draft.set(draft)
  selection_intent.selection.set(selection)
  selection_intent.message_ts.set(message_ts)
  selection_intent.author.set(author)
  selection_intent.role.set(role)
  selection_intent_run(src)
}

///|
/// Retries the current selection intent request after a failure.
pub fn selection_intent_retry(src : Source) -> Unit {
  selection_intent_run(src)
}

///|
/// A pinned selection-intent reply kept floating in its chat until unpinned.
#derive(Eq)
pub(all) struct PinnedIntent {
  id : Int
  draft : String
  selection : String
  intent : String
  reply : String
  model : String
  collapsed : Bool
}

///|
// kept across runs: reset by selection_intent_pins_reset()
pub let pinned_intents : @signals.Signal[Array[PinnedIntent]] = @signals.signal([], same=fn(a, b) { a == b })

///|
// kept across runs: only counts on
let pinned_intent_serial : Ref[Int] = Ref(0)

///|
pub fn selection_intent_pins_reset() -> Unit {
  pinned_intents.set([])
}

///|
/// Pins the current inferred reply into its chat (deduplicating identical selection+reply in the same chat).
pub fn selection_intent_pin() -> Bool {
  let draft = @signals.untracked(fn() { selection_intent.draft.get() })
  let selection = @signals.untracked(fn() { selection_intent.selection.get() })
  let intent = @signals.untracked(fn() { selection_intent.intent.get() })
  let reply = @signals.untracked(fn() { selection_intent.reply.get() })
  let model = @signals.untracked(fn() { selection_intent.model.get() })
  guard draft != "" && reply != "" else { return false }
  let cur = @signals.untracked(fn() { pinned_intents.get() })
  if cur.iter().any(fn(p) { p.draft == draft && p.selection == selection && p.reply == reply }) {
    return true
  }
  pinned_intent_serial.val = pinned_intent_serial.val + 1
  let next = cur.copy()
  next.push({ id: pinned_intent_serial.val, draft, selection, intent, reply, model, collapsed: false })
  pinned_intents.set(next)
  true
}

///|
/// Removes a pinned reply by its id.
pub fn selection_intent_unpin(id : Int) -> Unit {
  let cur = @signals.untracked(fn() { pinned_intents.get() })
  pinned_intents.set(cur.filter(fn(p) { p.id != id }))
}

///|
/// Toggles collapsed/expanded state of a pinned reply card.
pub fn selection_intent_toggle_collapse(id : Int) -> Unit {
  let cur = @signals.untracked(fn() { pinned_intents.get() })
  pinned_intents.set(
    cur.map(fn(p) { if p.id == id { { ..p, collapsed: !p.collapsed } } else { p } }),
  )
}

///|
/// All pinned intent replies belonging to chat `draft`.
pub fn pinned_intents_for(draft : String) -> Array[PinnedIntent] {
  pinned_intents.get().filter(fn(p) { p.draft == draft })
}

///|
/// A 戳一下 kept on the words it was asked of, as a note in its chat's margin beside the message they are of (its row's
/// key `row`, the list's): the words lit there, the answer beside them as it comes (asked of the core on its own, so
/// that several stand at once, each with its answer), till it is taken off.
#derive(Eq)
pub(all) struct IntentNote {
  id : Int
  draft : String
  row : String
  /// where its words stand in their message's text (-1 not found): its note's place among the message's
  at : Int
  station : String
  thread : Double
  selection : String
  message_ts : String
  author : String
  loading : Bool
  intent : String
  reply : String
  model : String
  error : String
}

///|
// kept across runs: reset by intent_notes_reset()
pub let intent_notes : @signals.Signal[Array[IntentNote]] = @signals.signal([], same=fn(a, b) { a == b })

///|
// kept across runs: only counts on
let intent_note_serial : Ref[Int] = Ref(0)

///|
pub fn intent_notes_reset() -> Unit {
  intent_notes.set([])
  intent_note_pointed.set(0)
}

///|
/// Note `id` as `f` makes it of what it is, where it still is.
fn intent_note_set(id : Int, f : (IntentNote) -> IntentNote) -> Unit {
  let cur = @signals.untracked(fn() { intent_notes.get() })
  intent_notes.set(cur.map(fn(n) { if n.id == id { f(n) } else { n } }))
}

///|
/// Asks the core of note `id`'s words, its answer kept in it as it comes (none where it was taken off meanwhile).
fn intent_note_run(src : Source, id : Int) -> Unit {
  guard @signals.untracked(fn() { intent_notes.get() }).search_by(fn(n) { n.id == id }) is Some(i) else { return }
  let n = @signals.untracked(fn() { intent_notes.get() })[i]
  intent_note_set(id, fn(n) { { ..n, loading: true, intent: "", reply: "", model: "", error: "" } })
  let params : Map[String, Json] = {
    "station": Json::string(n.station),
    "thread": Json::number(n.thread),
    "selection": Json::string(n.selection),
  }
  if n.message_ts != "" {
    params["messageTs"] = Json::string(n.message_ts)
  }
  if n.author != "" {
    params["author"] = Json::string(n.author)
  }
  (src.call)("chat.selectionIntent", Json::object(params), fn(res) {
    match res {
      Ok(v) =>
        intent_note_set(id, fn(n) {
          { ..n, loading: false, intent: text(Some(v), "intent"), reply: text(Some(v), "reply"), model: text(Some(v), "model") }
        })
      Err(e) => intent_note_set(id, fn(n) { { ..n, loading: false, error: error_words(e) } })
    }
  })
}

///|
/// A 戳一下 of `selection`, words of the message of row `row` in chat `draft` (`at` where in its text; chat `thread` of
/// `station`; the message's ts and whose it is, as selection_intent_ask's), kept on those words as a note: asked of the
/// core at once. Its id.
pub fn intent_note_ask(
  src : Source,
  draft : String,
  row : String,
  at : Int,
  station : String,
  thread : Double,
  selection : String,
  message_ts : String,
  author : String,
) -> Int {
  intent_note_serial.val = intent_note_serial.val + 1
  let id = intent_note_serial.val
  let cur = @signals.untracked(fn() { intent_notes.get() })
  let next = cur.copy()
  next.push({
    id,
    draft,
    row,
    at,
    station,
    thread,
    selection,
    message_ts,
    author,
    loading: true,
    intent: "",
    reply: "",
    model: "",
    error: "",
  })
  intent_notes.set(next)
  intent_note_run(src, id)
  id
}

///|
/// Asks again of note `id`'s words, after its answer failed.
pub fn intent_note_retry(src : Source, id : Int) -> Unit {
  intent_note_run(src, id)
}

///|
/// Takes note `id` off its words.
pub fn intent_note_remove(id : Int) -> Unit {
  let cur = @signals.untracked(fn() { intent_notes.get() })
  intent_notes.set(cur.filter(fn(n) { n.id != id }))
}

///|
/// The notes of chat `draft`, in the order they were made.
pub fn intent_notes_for(draft : String) -> Array[IntentNote] {
  intent_notes.get().filter(fn(n) { n.draft == draft })
}

///|
/// The notes on the message of row `row` of chat `draft`, in the order their words stand in it (as made where they
/// stand together), so that the first lit is the first beside it.
pub fn intent_notes_on(draft : String, row : String) -> Array[IntentNote] {
  let on = intent_notes.get().filter(fn(n) { n.draft == draft && n.row == row })
  on.sort_by(fn(a, b) { if a.at != b.at { a.at.compare(b.at) } else { a.id.compare(b.id) } })
  on
}

///|
/// The note whose card the pointer is on (0 none): its words lit deeper than the others' (intent_note_lits).
// kept across runs: reset by intent_notes_reset()
pub let intent_note_pointed : @signals.Signal[Int] = @signals.signal(0, same=fn(a, b) { a == b })
