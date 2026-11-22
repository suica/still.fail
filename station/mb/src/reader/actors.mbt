// The sessions' actors (station/src/sessions/actor.ts `SessionActor`) run here, in the sessions' program (`--sessions`, with agents.mbt): each
// session's state and its serial queue, every change of it going through the queue as there (a runtime's events, what
// its tools say, what the hub asks). What an actor needs of the station that is not here yet (the store, the drivers
// and their runtime sessions, the chat surfaces, the account pool, the live view, the words) it asks of Node (`rpc`),
// which answers with its own (station/src/sessions/mb-actor.ts); what the hub asks of an actor at once (where it
// stands, whether its queue is run out) Node reads of what this program last told it of each (`mirror`). Its time is
// Node's (`now`, said with every message), and its waits are Node's clock's (`after`, told back as `due`): a TestClock
// in tests moves them as it moves the rest.
//
// Node says, a line each: `actor` (one made: its key, its runtime), `call` (a method of one, as SessionActor's, its
// answer `returned`), `event` (its runtime session's event, by the generation it was opened as), `answer` (to an
// `rpc`), `due` (a wait's time come). It is said `rpc`, `after`, `mirror` and `returned`.

///|
priv struct Turn {
  id : String
  mut declared : Json?
  auth_retried : Bool
  mut codex_retried : Bool
  passive : Bool
  by : Json
  // (a turn its background work woke, `job`: the need of the turn before it, still asked of a person as it began, so
  // that a turn that only says how that work goes and waits on asks the same; `begin_turn`)
  asked_before : Json?
}

///|
/// An `auth_retry` or `spend` failover continuation deferred while active turn slots exceed `max_concurrent_turns`.
priv struct QueuedRetry {
  kind : String
  text : String
  by : Json
  codex_retried : Bool
}

///|
/// An undeclared turn end deferred while the session is held (e.g. during handover `drain` or `starting`).
priv struct DeferredEnd {
  lost : Bool
  unheard : Bool
  recorded : String?
}

///|
priv struct Working {
  connect : String
  channel : String
  thread_ts : String
  mut ts : Json
  first_ts : Json
  since : Double
}

///|
priv struct Agent {
  generation : Int
  /// its runtime session, as Node keeps it (`agent.*` asked by it)
  handle : Int
}

///|
/// A failed turn waiting for the machine's shared Codex update (actor.ts `codexUpdate`): its number, who it was for,
/// the turn, and whether the update is over.
priv struct CodexUpdate {
  id : Int
  by : Json
  turn : String
  mut finished : Bool
}

///|
priv struct Actor {
  key : String
  mut runtime : String
  tasks : @effect.Queue[async () -> Unit]
  /// tasks queued or running
  mut queued : Int
  /// what Node said of it, counted, and what of it this program has taken in (Node's `settled`, mb-actor.ts)
  mut seen : Int
  mut agent : Agent?
  mut stale : Bool
  mut restart : Bool
  /// the changes it was told of (`changed`), counted, and the last of them that needs a new process: one told while its
  /// process was opened or took one in place is taken after it (actor_run.mbt `ensure_agent`, `catch_up`)
  mut change_seq : Int
  mut restart_seq : Int
  mut profile : Json
  mut running_identity : Json
  mut read_back : Bool
  mut phase : String
  mut turn : Turn?
  /// true between an undeclared turn end and the follow-up nudge/tools-lost `begin_turn`, keeping `process_state` running
  mut warm : Bool
  /// deferred undeclared turn end waiting for `release` after `hold`
  mut deferred_end : DeferredEnd?
  /// true while acquiring/opening a turn before `turn` is set, or deciding continuation in `on_turn_ended`
  mut starting_turn : Bool
  /// deferred `auth_retry` / `spend` continuation waiting for a concurrency slot
  mut queued_retry : QueuedRetry?
  /// profiles this turn's chain of `auth_retry` turns was refused on (FB-44): each rechecked and passed over, so a pool
  /// with several revoked logins goes on to a good one; emptied when a turn begins anew or ends otherwise
  mut auth_tried : Array[String]
  mut codex_update : CodexUpdate?
  mut codex_next : Int
  /// the Codex thread taken up again from its rollout after its turn was refused with a bare Bad Request (FB-26;
  /// actor_run.mbt `refused_thread`): refused again, the next turn starts afresh
  mut codex_reloaded : String?
  mut nudges : Int
  asked_to_name : Array[String]
  mut overloads : Int
  mut tools_lost : String?
  mut tools_restarts : Int
  mut tools_retry : Int?
  mut tools_retries : Int
  mut tools_retry_at : Double
  mut tools_retry_deferred : Bool
  mut saying : (String, String)?
  mut last_said : String
  mut turn_text : String
  mut posted : Bool
  mut stop_requested : Bool
  mut resume_lost : Bool
  mut afresh : String?
  mut compacted_untold : Bool
  mut compacting : Bool
  mut over_while_compacting : Bool
  stopped : Array[Json]
  mut stopped_note : String?
  mut idle_since : Double
  mut working_for : Array[Working]
  mut ended_for : Array[Working]
  mut tools : Array[(String, String)]
  mut notices : Array[String]
  mut waiting : Int?
  mut waits : Int
  mut waiting_until : Double
  mut waiting_seconds : Double
  mut refill : Int?
  mut refills : Int
  mut refill_at : Double
  mut steered : Array[Json]
  mut steered_for : Array[Working]
  mut unread : Array[Json]
  mut delivery_interruptions : Int
  mut recoveries : Int
  mut recovery_deferred : Bool
  /// how many times a turn on what waited for it failed to start
  mut start_failures : Int
  /// what was handed to the last of those (`handed_ids`); "" once one started
  mut failed_handed : String
  /// waiting in `cap_wait_queue` for an account concurrency slot to open
  mut paused_cap : Bool
  /// bypasses per-account concurrency caps on the next open (manual jump-the-queue start)
  mut force_session_cap : Bool
  /// whether the queued notice was already posted for the current wait
  mut cap_wait_notified : Bool
  /// the `node.open` asked of Node and not answered yet (actor_run.mbt `rpc_open`): what a stop, a suspension, a close or
  /// its deadline gives up at once, never waited on behind it (FB-34)
  mut opening_rpc : Int?
  /// its waits on Node's clock, by name
  timers : Map[String, () -> Unit]
  /// what it last told Node of itself
  mut mirrored : String
}

///|
priv struct Actors {
  host : @host.Host
  actors : Map[String, Actor]
  asked : Map[Int, @effect.Deferred[Json]]
  timers : Map[Int, () -> Unit]
  mut next : Int
  mut now : Double
  /// tasks running and not waiting on Node: none, and what Node said is all taken in, and this program is quiet
  mut active : Int
  /// Node's lines taken in
  mut seen : Int
  /// the station's database, where Node said it is (a store in memory is Node's alone)
  mut db : @sql.Db?
  /// the station's background jobs (jobs.mbt), Node's shell of them the pseudo-actor `#jobs`
  mut jobs : JobsState
  /// the tasks of other stations here and this station's there (remote.mbt), Node's shell of them `#remote`
  mut remote : RemoteState
  /// the agents' processes read here (agents.mbt): what each read, once Node took it, is given its actor here
  mut agents : Agents?
  /// the live view of the sessions (live.mbt), Node's shell of it `#live`
  mut live : LiveState
  /// the separator of this station's system's paths (`--sep`): what is joined here as Node joins it (remote_files.mbt)
  sep : String
  /// maximum concurrent running turns across all sessions (0: unlimited)
  mut max_concurrent_turns : Int
  /// deduplicated FIFO queue of session keys waiting for a turn slot
  turn_wait_queue : Array[String]
  /// deduplicated FIFO queue of session keys waiting for an account concurrency cap slot
  cap_wait_queue : Array[String]
  /// serial lock preventing thundering-herd concurrent drains of `cap_wait_queue`
  mut draining_cap : Bool
  /// set when another drain is requested while a drain pass is already running
  mut drain_cap_again : Bool
}

///|
fn Actors::new(host : @host.Host, sep : String) -> Actors {
  { host, actors: Map([]), asked: Map([]), timers: Map([]), next: 0, now: 0.0, active: 0, seen: 0, db: None, jobs: JobsState::new(), remote: RemoteState::new(), agents: None, live: LiveState::new(), sep, max_concurrent_turns: 0, turn_wait_queue: [], cap_wait_queue: [], draining_cap: false, drain_cap_again: false }
}

///|
suberror Asked {
  Asked(Json)
}

///|
/// Its words as they are, where an error is said (`to_string`): without it MoonBit says only the type's name
/// ("station/reader.Asked.Asked" in a chat's notice in place of what Node said, Office-VM-1 2026-11-16).
impl Show for Asked with output(self, logger) {
  match self {
    Asked(j) =>
      logger.write_string(
        match j.value("message") {
          Some(String(s)) => s
          _ => j.stringify()
        },
      )
  }
}

///|
fn Asked::message(e : Error) -> String {
  e.to_string()
}

///|
/// Says `message` to Node, with where this program stands (`active`): Node's `settled` and its tests' `settle` go by it.
fn Actors::say_node(self : Actors, message : Map[String, Json]) -> Unit {
  message["active"] = Json::number(self.active.to_double())
  message["seen"] = Json::number(self.seen.to_double())
  self.host.say(Json::object(message).stringify())
}

///|
/// Asks Node `fn` with `args` (station/src/sessions/mb-actor.ts `rpc`): its answer, or its error raised.
async fn Actors::rpc(self : Actors, key : String, f : String, args : Array[Json]) -> Json raise {
  self.next += 1
  let id = self.next
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  self.asked[id] = d
  if self.actors.get(key) is Some(a) {
    self.mirror(a)
  }
  self.active -= 1
  self.say_node({ "rpc": Json::number(id.to_double()), "actor": Json::string(key), "fn": Json::string(f), "args": Json::array(args) })
  // (counted again as its answer comes: `heard`)
  let answer = d.wait()
  match answer {
    { "error": err, .. } => raise Asked(err)
    _ => answer.value("value").unwrap_or(Json::null())
  }
}

///|
/// Gives up `id` asked of Node (`rpc`): what waits on it goes on at once with `err` as its error, counted active again
/// as an answer would be (`heard`); its answer, come later, is dropped there. Whether it was still waiting.
fn Actors::cancel_rpc(self : Actors, id : Int, err : Json) -> Bool {
  match self.asked.get(id) {
    Some(d) => {
      self.asked.remove(id)
      self.active += 1
      ignore(d.succeed({ "error": err }))
      true
    }
    None => false
  }
}

///|
/// What is asked of Node and not waited for (it says nothing back that matters).
fn Actors::tell(self : Actors, key : String, f : String, args : Array[Json]) -> Unit {
  if self.actors.get(key) is Some(a) {
    self.mirror(a)
  }
  self.say_node({ "tell": Json::string(f), "actor": Json::string(key), "args": Json::array(args) })
}

///|
/// A wait of Node's clock (`after`): `then` once its time comes; the function given back lets it go.
fn Actors::after(self : Actors, ms : Double, then : () -> Unit, on? : String) -> () -> Unit {
  self.next += 1
  let id = self.next
  self.timers[id] = then
  let said : Map[String, Json] = { "after": Json::number(id.to_double()), "ms": Json::number(if ms < 0.0 { 0.0 } else { ms }) }
  if on is Some(key) {
    said["on"] = Json::string(key)
  }
  self.say_node(said)
  () => {
    if self.timers.contains(id) {
      self.timers.remove(id)
      self.say_node({ "cancel": Json::number(id.to_double()) })
    }
  }
}

///|
/// Runs `work` as a fiber of its own, counted active while it runs.
fn Actors::spawn(self : Actors, work : async () -> Unit) -> Unit {
  self.active += 1
  ignore(
    self.host.rt.fork_daemon("actor work", on_error=e => @host.note("actor work failed: \{e}"), () => {
      work()
      self.active -= 1
      self.quiet()
    }),
  )
}

///|
/// Tells Node where this program stands, once nothing of it runs.
fn Actors::quiet(self : Actors) -> Unit {
  if self.active == 0 {
    self.say_node({ "quiet": Json::boolean(true) })
  }
}

///|
fn Actors::actor(self : Actors, key : String, runtime : String) -> Actor {
  match self.actors.get(key) {
    Some(a) => a
    None => {
      let a : Actor = {
        key,
        runtime,
        tasks: @effect.Queue::unbounded(),
        queued: 0,
        seen: 0,
        agent: None,
        stale: false,
        restart: false,
        change_seq: 0,
        restart_seq: 0,
        profile: Json::null(),
        running_identity: Json::null(),
        read_back: false,
        phase: "idle",
        turn: None,
        warm: false,
        deferred_end: None,
        starting_turn: false,
        queued_retry: None,
        auth_tried: [],
        codex_update: None,
        codex_next: 0,
        codex_reloaded: None,
        nudges: 0,
        asked_to_name: [],
        overloads: 0,
        tools_lost: None,
        tools_restarts: 0,
        tools_retry: None,
        tools_retries: 0,
        tools_retry_at: 0.0,
        tools_retry_deferred: false,
        saying: None,
        last_said: "",
        turn_text: "",
        posted: false,
        stop_requested: false,
        resume_lost: false,
        afresh: None,
        compacted_untold: false,
        compacting: false,
        over_while_compacting: false,
        stopped: [],
        stopped_note: None,
        idle_since: self.now,
        working_for: [],
        ended_for: [],
        tools: [],
        notices: [],
        waiting: None,
        waits: 0,
        waiting_until: 0.0,
        waiting_seconds: 0.0,
        refill: None,
        refills: 0,
        refill_at: 0.0,
        steered: [],
        steered_for: [],
        unread: [],
        delivery_interruptions: 0,
        recoveries: 0,
        recovery_deferred: false,
        start_failures: 0,
        failed_handed: "",
        paused_cap: false,
        force_session_cap: false,
        cap_wait_notified: false,
        opening_rpc: None,
        timers: Map([]),
        mirrored: "",
      }
      self.actors[key] = a
      // (its queue: one task at a time, in order)
      ignore(
        self.host.rt.fork_daemon("actor", on_error=e => @host.note("actor failed: \{e}"), () => {
          while (try { Some(a.tasks.take()) } catch { _ => None }) is Some(task) {
            task()
          }
        }),
      )
      a
    }
  }
}

///|
/// What the hub reads of it at once (mb-actor.ts `Mirror`), told as it changes.
fn Actors::mirror(self : Actors, a : Actor) -> Unit {
  let turn = match a.turn {
    Some(t) => Json::string(t.id)
    None => Json::null()
  }
  let state : Json = {
    "queued": Json::number(a.queued.to_double()),
    "seen": Json::number(a.seen.to_double()),
    "turn": turn,
    "warm": Json::boolean(a.warm),
    "deferredEnd": Json::boolean(a.deferred_end is Some(_)),
    "codexUpdate": Json::boolean(a.codex_update is Some(_)),
    "agent": match a.agent { Some(g) => Json::number(g.handle.to_double()); None => Json::null() },
    "idleSince": Json::number(a.idle_since),
    "notices": Json::number(a.notices.length().to_double()),
    "waiting": Json::boolean(a.waiting is Some(_)),
    "refill": Json::boolean(a.refill is Some(_)),
    "toolsRetry": Json::boolean(a.tools_retry is Some(_) || a.tools_retry_deferred),
    "startFailed": Json::boolean(a.failed_handed != "" && !a.paused_cap && !self.turn_wait_queue.contains(a.key)),
    "unread": Json::array(a.unread.map(m => [m.value("thread").unwrap_or(Json::null()), m.value("n").unwrap_or(Json::null()), m.value("ts").unwrap_or(Json::null())])),
    "identity": a.running_identity,
    "runtime": Json::string(a.runtime),
    "closed": Json::boolean(a.phase == "closed"),
  }
  let said = state.stringify()
  if said == a.mirrored {
    return
  }
  a.mirrored = said
  self.say_node({ "mirror": Json::string(a.key), "state": state })
}

///|
/// Queues `task` (actor.ts `enqueue`): done once it has run, or was skipped (the actor closed); its failure logged.
async fn Actors::enqueue(self : Actors, a : Actor, task : async () -> Unit raise) -> Unit {
  a.queued += 1
  self.mirror(a)
  let done : @effect.Deferred[Unit] = @effect.Deferred::new()
  // (its caller is counted active while it waits on its task: the task is its work, waiting its turn or running)
  ignore(
    a.tasks.try_offer(() => {
      if a.phase != "closed" {
        task() catch {
          e => {
            // (which runtime and model it ran under, never what was said)
            let fields : Map[String, Json] = {
              "error": Json::string(Asked::message(e)),
              "runtime": Json::string(a.runtime),
            }
            if str_of(a.running_identity.value("model")) is Some(m) && m != "" {
              fields["model"] = Json::string(m)
            }
            self.log(a, "error", "session task failed", fields~)
          }
        }
      }
      a.queued -= 1
      self.mirror(a)
      ignore(done.succeed(()))
    }),
  )
  done.wait()
}

///|
/// The sessions' program (`--sessions`): the agents' output read (agents.mbt) and the actors (this file) in one, each
/// line of Node's to the one it is for: an actor's says `actor`, or is an answer, a wait's time, the database's place.
pub async fn serve_sessions(host : @host.Host, sep : String) -> Unit {
  let s = Actors::new(host, sep)
  let a = Agents::new(host)
  s.agents = Some(a)
  host.say(({ "ready": true } : Json).stringify())
  while host.line() is Some(line) {
    if actors_line(line) {
      s.heard(line)
      s.quiet()
    } else {
      a.told(line)
    }
  }
  @host.exit(0)
}

///|
/// A batch of what its runtime session's process said, read here (agents.mbt `tell`) and taken by Node (mb-actor.ts
/// `routed`): each event given the actor as Node gave it before, in order. Node says what it decides of them: a turn's
/// outcome (`outcome`, the failure's reason by its words). The live view here takes each first (live.mbt), and a turn's
/// end waits for what its transcript said last there (`live_end`).
fn Actors::routed(self : Actors, a : Actor, n : Int, k : Int, generation : Int, said : Json) -> Unit {
  guard self.agents is Some(agents) else { return }
  guard agents.take(n, k) is Some((events, _)) else { return }
  for e in events {
    let event = e.to_json()
    // (the live view takes each first, as it is: live.mbt)
    let mut read = Json::null()
    match str_of(event.value("type")) {
      Some("live") => self.live_event(a.key, event.value("event").unwrap_or(Json::null()))
      Some("turnEnded") => read = { "live": jnum(self.live_end(a.key).to_double()) }
      _ => ()
    }
    let event = match event {
      // (what the session's owner keeps of a turn's start and end, not the actor's: Claude Code's turn, a Codex
      // thread's turn's id and where it is in the output)
      Object(fields) if str_of(event.value("type")) == Some("turnEnded") => {
        let m = fields.copy()
        for k in ["turn", "from", "to"] {
          m.remove(k)
        }
        if said.value("outcome") is Some(o) {
          m["outcome"] = o
        }
        Json::object(m)
      }
      Object(fields) if str_of(event.value("type")) == Some("turnStarted") => {
        let m = fields.copy()
        for k in ["turn", "turnId", "from", "to"] {
          m.remove(k)
        }
        Json::object(m)
      }
      Object(_) if str_of(event.value("type")) == Some("live") =>
        match live_for_actor(event.value("event").unwrap_or(Json::null())) {
          Some(ev) => Json::object({ "type": jstr("live"), "event": ev })
          None => continue
        }
      // (what the session's owner alone takes: a token asked for, an ACP runtime's transcript lines, a prompt's answer,
      // its usage: own-process.ts `took`)
      Object(_) if str_of(event.value("type")) is Some("renew" | "kept" | "answered" | "usage") => continue
      _ => event
    }
    self.spawn(() => self.on_event(a, generation, event, read) catch {
      e => self.log(a, "error", "session event failed", fields={ "error": Json::string(Asked::message(e)) })
    })
  }
}

///|
/// What of a live event an actor reads (mb-actor.ts `#event`, as Node gave it): what moves its status line and its
/// words; a tool's start without its input.
fn live_for_actor(e : Json) -> Json? {
  let kind = str_of(e.value("kind")).unwrap_or("")
  if kind == "tasks" || kind == "plan" {
    return None
  }
  if kind == "delta" && str_of(e.value("field")) != Some("text") {
    return None
  }
  if kind == "start" && str_of(e.value("step")) == Some("thinking") {
    return None
  }
  if kind == "start" && str_of(e.value("step")) == Some("tool") {
    let m : Map[String, Json] = { "kind": jstr(kind), "step": jstr("tool") }
    for f in ["id", "tool"] {
      if e.value(f) is Some(v) {
        m[f] = v
      }
    }
    return Some(Json::object(m))
  }
  Some(e)
}

///|
/// Whether `a` currently holds a concurrency slot (running a turn or transitioning into/out of one).
fn holds_turn_slot(a : Actor) -> Bool {
  a.phase != "closed" && (a.turn is Some(_) || a.starting_turn)
}

///|
fn Actors::active_turn_slots(self : Actors) -> Int {
  let mut n = 0
  for a in self.actors.values() {
    if holds_turn_slot(a) {
      n += 1
    }
  }
  n
}

///|
fn Actors::turn_slots_full(self : Actors, a : Actor) -> Bool {
  if self.max_concurrent_turns <= 0 || holds_turn_slot(a) {
    return false
  }
  self.active_turn_slots() >= self.max_concurrent_turns
}

///|
fn Actors::enqueue_turn_wait(self : Actors, a : Actor) -> Unit {
  if a.phase == "closed" {
    return
  }
  if !self.turn_wait_queue.contains(a.key) {
    self.turn_wait_queue.push(a.key)
  }
}

///|
fn Actors::remove_turn_wait(self : Actors, key : String) -> Unit {
  if self.turn_wait_queue.search_by(k => k == key) is Some(i) {
    ignore(self.turn_wait_queue.remove(i))
  }
}

///|
fn Actors::enqueue_cap_wait(self : Actors, a : Actor) -> Unit {
  if a.phase == "closed" {
    return
  }
  if !self.cap_wait_queue.contains(a.key) {
    self.cap_wait_queue.push(a.key)
  }
}

///|
fn Actors::remove_cap_wait(self : Actors, key : String) -> Unit {
  if self.cap_wait_queue.search_by(k => k == key) is Some(i) {
    ignore(self.cap_wait_queue.remove(i))
  }
}

///|
/// Serially drains `cap_wait_queue` in strict FIFO order, skipping runtimes already known to be full
/// in this pass so a capped Claude account never head-of-line blocks Codex sessions.
fn Actors::drain_cap_queue(self : Actors) -> Unit {
  if self.cap_wait_queue.length() == 0 {
    return
  }
  if self.draining_cap {
    self.drain_cap_again = true
    return
  }
  self.draining_cap = true
  self.spawn(() => {
    defer {
      self.draining_cap = false
      if self.drain_cap_again {
        self.drain_cap_again = false
        self.drain_cap_queue()
      }
    }
    let blocked_runtimes : Array[String] = []
    let mut i = 0
    while i < self.cap_wait_queue.length() {
      let key = self.cap_wait_queue[i]
      match self.actors.get(key) {
        None => {
          ignore(self.cap_wait_queue.remove(i))
          continue
        }
        Some(actor) => {
          if actor.phase == "closed" || holds_turn_slot(actor) || !actor.paused_cap {
            ignore(self.cap_wait_queue.remove(i))
            continue
          }
          if blocked_runtimes.contains(actor.runtime) {
            i += 1
            continue
          }
          actor.paused_cap = false
          self.wake_cap_queued(actor) catch {
            _ => ()
          }
          if actor.paused_cap {
            if !blocked_runtimes.contains(actor.runtime) {
              blocked_runtimes.push(actor.runtime)
            }
            match self.cap_wait_queue.search_by(k => k == key) {
              Some(pos) => i = pos + 1
              None => ()
            }
          } else {
            self.remove_cap_wait(key)
            actor.cap_wait_notified = false
          }
        }
      }
    }
  })
}

///|
fn Actors::set_max_concurrent_turns(self : Actors, next : Int) -> Unit {
  let prev = self.max_concurrent_turns
  self.max_concurrent_turns = if next > 0 { next } else { 0 }
  if self.max_concurrent_turns == 0 || (prev > 0 && self.max_concurrent_turns > prev) {
    self.drain_turn_queue()
  }
}

///|
/// Wakes up to the available slot budget of queued sessions in strict FIFO order.
/// Each popped actor synchronously reserves `starting_turn = true` before spawning
/// `wake_queued`, so `active_turn_slots()` reflects the reservation immediately and
/// never cascades across the rest of the queue.
fn Actors::drain_turn_queue(self : Actors, drain_cap? : Bool = true) -> Unit {
  let mut budget = if self.max_concurrent_turns <= 0 {
    self.turn_wait_queue.length()
  } else {
    self.max_concurrent_turns - self.active_turn_slots()
  }
  while budget > 0 && self.turn_wait_queue.length() > 0 {
    let key = self.turn_wait_queue.remove(0)
    match self.actors.get(key) {
      Some(actor) => {
        if actor.phase == "closed" || holds_turn_slot(actor) {
          continue
        }
        actor.starting_turn = true
        budget -= 1
        self.spawn(() => {
          self.wake_queued(actor) catch {
            e => {
              actor.starting_turn = false
              self.log(actor, "error", "queued session wake failed", fields={ "error": jstr(Asked::message(e)) })
              if actor.turn is None {
                self.drain_turn_queue()
              }
            }
          }
        })
      }
      None => ()
    }
  }
  if drain_cap {
    self.drain_cap_queue()
  }
}

///|
/// Whether a line of Node's is for the actors: what Node says them begins so (mb-actor.ts `post`, its keys first).
fn actors_line(line : String) -> Bool {
  ["{\"call\":", "{\"answer\":", "{\"due\":", "{\"db\":", "{\"maxConcurrentTurns\":", "{\"drainCapQueue\":", "{\"runtime\":", "{\"event\":", "{\"routed\":", "{\"codexUpdated\":"].iter().any(p => line.has_prefix(p))
}

///|
/// A line of Node's.
fn Actors::heard(self : Actors, line : String) -> Unit {
  self.seen += 1
  let said = @json.parse(line) catch { _ => return }
  if said.value("now") is Some(Number(now, ..)) {
    self.now = now
  }
  match said {
    { "db": place, .. } => {
      // (a hub's actors begin: those of one before it, closed, go, and what it is told is counted from here)
      self.actors.clear()
      self.asked.clear()
      self.timers.clear()
      self.turn_wait_queue.clear()
      self.cap_wait_queue.clear()
      self.draining_cap = false
      self.drain_cap_again = false
      self.max_concurrent_turns = 0
      self.seen = 1
      self.active = 0
      self.jobs = JobsState::new()
      self.remote = RemoteState::new()
      self.live = LiveState::new()
      if self.db is Some(db) {
        db.close()
      }
      self.db = match place {
        String(path) =>
          Some(@sql.Db::attach(self.host, path, wait=30000)) catch {
            e => {
              @host.note("actors: the station's database not opened: " + (match e { @wire.ShellError(m) => m }))
              None
            }
          }
        _ => None
      }
      return
    }
    { "maxConcurrentTurns": Number(n, ..), .. } => {
      let next = if n.is_nan() || n.is_inf() || n <= 0.0 { 0 } else { n.to_int() }
      self.set_max_concurrent_turns(next)
      return
    }
    { "drainCapQueue": True, .. } => {
      self.drain_cap_queue()
      return
    }
    { "answer": Number(id, ..), .. } => {
      let id = id.to_int()
      if self.asked.get(id) is Some(d) {
        self.asked.remove(id)
        // (what waited on it runs again from now: so it is said to be, before it does)
        self.active += 1
        ignore(d.succeed(said))
      }
      return
    }
    { "due": Number(id, ..), .. } => {
      let id = id.to_int()
      if self.timers.get(id) is Some(then) {
        self.timers.remove(id)
        // (counted active while it runs: what it says Node meanwhile, a `tell` too, must not say this program quiet)
        self.active += 1
        then()
        self.active -= 1
        self.quiet()
      }
      return
    }
    _ => ()
  }
  guard said.value("actor") is Some(String(key)) else { return }
  if key == live_key {
    // (each as it comes, in order: what of it waits goes on as a fiber of its own)
    if said is { "call": Number(id, ..), "method": String(method), .. } {
      let args = match said.value("args") {
        Some(Array(args)) => args
        _ => []
      }
      // (counted active while it runs, as a due timer's work)
      self.active += 1
      self.live_called(id, method, args)
      self.active -= 1
      self.quiet()
    }
    return
  }
  if key == jobs_key || key == remote_key {
    // (the jobs' calls: each a fiber of its own, as an actor's call is before it is queued)
    if said is { "call": Number(id, ..), "method": String(method), .. } {
      let args = match said.value("args") {
        Some(Array(args)) => args
        _ => []
      }
      self.spawn(() => {
        let answer : Map[String, Json] = { "returned": Json::number(id) }
        let value = (if key == jobs_key { self.jobs_called(method, args) } else { self.remote_called(method, args) }) catch {
          e => {
            answer["error"] = Json::string(Asked::message(e))
            if e is Asked(j) {
              answer["cause"] = j
            }
            Json::null()
          }
        }
        answer["value"] = value
        self.say_node(answer)
      })
    }
    return
  }
  let a = match said.value("runtime") {
    Some(String(runtime)) => self.actor(key, runtime)
    _ =>
      match self.actors.get(key) {
        Some(a) => a
        None => return
      }
  }
  a.seen += 1
  match said {
    { "call": Number(id, ..), "method": String(method), .. } => {
      let args = match said.value("args") {
        Some(Array(args)) => args
        _ => []
      }
      // (what is done of it before it is queued, as it comes: in order with the rest Node says)
      self.spawn(() => {
        let answer : Map[String, Json] = { "returned": Json::number(id) }
        let value = self.called(a, method, args) catch {
          e => {
            answer["error"] = Json::string(Asked::message(e))
            if e is Asked(j) {
              answer["cause"] = j
            }
            Json::null()
          }
        }
        answer["value"] = value
        self.mirror(a)
        self.say_node(answer)
      })
    }
    { "event": event, "generation": Number(generation, ..), .. } => {
      let read = said.value("read").unwrap_or(Json::null())
      self.spawn(() => self.on_event(a, generation.to_int(), event, read) catch {
        e => self.log(a, "error", "session event failed", fields={ "error": Json::string(Asked::message(e)) })
      })
    }
    { "routed": Number(n, ..), "batch": Number(k, ..), "generation": Number(generation, ..), .. } =>
      self.routed(a, n.to_int(), k.to_int(), generation.to_int(), said)
    { "codexUpdated": Number(id, ..), .. } => {
      let why = match said.value("why") {
        Some(String(w)) => Some(w)
        _ => None
      }
      self.spawn(() => self.enqueue(a, async fn() { self.codex_updated(a, id.to_int(), why) }))
    }
    _ => ()
  }
  self.mirror(a)
}
