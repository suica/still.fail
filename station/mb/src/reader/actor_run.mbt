// What a session's actor does (station/src/sessions/actor.ts, method by method, in the same order there): what the
// hub asks of it, what its runtime session says, its turns, its waits. What it asks of Node is actor_base.mbt's.

///|
fn Actors::idle_now(self : Actors, a : Actor) -> Unit {
  a.idle_since = self.now
}

///|
/// Its runtime session now (actor.ts `agent`'s setter): what it has going in the background told as it is taken up,
/// and as none once let go of.
fn Actors::set_agent(self : Actors, a : Actor, agent : Agent?) -> Unit {
  let was = a.agent.map(g => g.handle)
  a.agent = agent
  let now = agent.map(g => g.handle)
  if was != now {
    self.tell(a.key, "node.tasks", [match now { Some(h) => jnum(h.to_double()); None => Json::null() }])
  }
}

///|
async fn Actors::busy(self : Actors, a : Actor) -> Bool raise {
  self.busy_of(a, a.agent)
}

///|
async fn Actors::holding(self : Actors, a : Actor) -> Bool raise {
  match a.agent {
    Some(g) => truthy(self.agent_do(a, g, "holding", []))
    None => false
  }
}

///|
fn Actors::closed(self : Actors, a : Actor) -> Bool {
  ignore(self)
  a.phase == "closed"
}

///|
/// What the hub asks (actor.ts, its public methods): `method` with `args`; what it answers.
async fn Actors::called(self : Actors, a : Actor, method : String, args : Array[Json]) -> Json raise {
  let arg = (i : Int) => if i < args.length() { args[i] } else { Json::null() }
  match method {
    "flushed" => self.enqueue(a, async fn() { () })
    "cleanArchive" =>
      self.enqueue(a, async fn() {
        if a.agent is Some(_) || a.turn is Some(_) || a.waiting is Some(_) || a.notices.length() > 0 {
          return
        }
        ignore(self.deps(a, "cleanArchive", [jstr(a.key)]))
      })
    "kick" => {
      let before = a.start_failures
      self.enqueue(a, async fn() { self.pump(a, before_failures=before) })
    }
    "notify" => {
      // (not told where it is archived: Node's to see, as it asks)
      a.notices.push(str_of(Some(arg(0))).unwrap_or(""))
      self.enqueue(a, async fn() { self.give_notices(a) })
    }
    "putAway" =>
      self.enqueue(a, async fn() {
        a.notices.clear()
        a.queued_retry = None
        a.paused_cap = false
        a.cap_wait_notified = false
        a.force_session_cap = false
        self.remove_cap_wait(a.key)
        if a.codex_update is Some(_) {
          a.codex_update = None
          self.set_running(a, false)
        }
        if a.turn is None && !self.busy(a) {
          self.let_go(a)
        }
      })
    "postedNow" => self.enqueue(a, async fn() { a.posted = true })
    "postedForTurn" => {
      let id = str_of(Some(arg(0)))
      self.enqueue(a, async fn() {
        if a.turn.map(t => t.id) == id && id is Some(_) {
          a.posted = true
        }
      })
    }
    // A post with no state after all_done or need_human in the same turn: it goes on, so that end no longer stands
    // (instructions.ts: a post that says what you do next means you go on doing it now).
    "goesOn" =>
      self.enqueue(a, async fn() {
        guard a.turn is Some(t) && t.declared is Some(d) else { return }
        guard kind_of(Some(d)) is Some("all_done" | "need_help") else { return }
        self.log(a, "info", "a post after the turn said it ended goes on: that state no longer stands", fields={ "was": d.value("kind").unwrap_or(Json::null()) })
        t.declared = None
        self.declare_turn(a, t.id, None)
      })
    "stateForTurn" => return self.state_for_turn(a, args)
    "toolsAt" => {
      let url = str_of(Some(arg(0))).unwrap_or("")
      self.enqueue(a, async fn() { self.tools_at(a, url) })
    }
    "declare" => {
      let state = arg(0)
      let mut recorded = false
      self.enqueue(a, async fn() {
        guard a.turn is Some(t) else { return }
        t.declared = Some(state)
        self.declare_turn(a, t.id, Some(state))
        recorded = true
      })
      return jbool(recorded)
    }
    "waitFor" => {
      let what = arg(0)
      let watch = arg(1)
      self.enqueue(a, async fn() {
        if a.turn is Some(t) {
          ignore(self.store(a, "setWaitFor", [jstr(t.id), what, watch]))
        }
      })
    }
    "need" => {
      let what = arg(0)
      self.enqueue(a, async fn() {
        if a.turn is Some(t) {
          ignore(self.store(a, "setNeed", [jstr(t.id), what]))
        }
      })
    }
    "about" => {
      let about = arg(0)
      self.enqueue(a, async fn() {
        if a.turn is Some(t) {
          ignore(self.store(a, "setAbout", [jstr(t.id), about]))
        }
      })
    }
    "stop" => return self.stop(a)
    "cancelRetry" => {
      let (thread, seq) = (arg(0), arg(1))
      self.enqueue(a, async fn() {
        let last = self.last_turn(a)
        if a.turn is Some(_) || self.busy(a) || last is Null || !retrying(last) || !about_is(last, thread, seq) {
          return
        }
        ignore(self.stop_waiting(a, say=false))
        self.notice(a, self.t(a, "station.notice.retryCanceled"))
        self.live_turn_ended(a)
      })
    }
    "retryFailed" => {
      let (thread, seq) = (arg(0), arg(1))
      self.enqueue(a, async fn() {
        let last = self.last_turn(a)
        let cap_paused = !(last is Null) &&
          str_of(last.value("outcome")) == Some("failed") &&
          str_of(last.value("detail")) == Some("other: session_cap")
        if self.blocked(a) || (!cap_paused && self.has_pending(a)) {
          return
        }
        if last is Null || !retryable(last) || !about_is(last, thread, seq) {
          return
        }
        if cap_paused {
          self.remove_cap_wait(a.key)
          a.paused_cap = false
          a.cap_wait_notified = false
          a.force_session_cap = true
          self.log(a, "info", "manually starting a turn queued by account concurrency cap, as asked")
          if self.has_pending(a) {
            return self.pump(a)
          }
          if a.queued_retry is Some(r) {
            a.queued_retry = None
            return self.start_turn(a, r.kind, r.text, by=r.by)
          }
          return self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_FAILED"), fresh=true)
        }
        self.log(a, "info", "trying again a failed turn, as asked")
        let words_key = if cut_off_by_restart(last) {
          "RESUME_AFTER_RESTART"
        } else if given_up(last) {
          "GO_ON_AFTER_UNANSWERED"
        } else {
          "GO_ON_AFTER_FAILED"
        }
        self.start_turn(a, "resume", self.words(a, words_key), fresh=true)
      })
    }
    "reassign" => {
      let (thread, seq) = (arg(0), arg(1))
      self.enqueue(a, async fn() { self.reassign(a, thread, seq) })
    }
    "stopFromSlack" => return self.stop_from_slack(a, args)
    "goOn" =>
      self.enqueue(a, async fn() {
        if self.blocked(a) {
          return
        }
        a.refill = None
        if self.has_pending(a) {
          return self.pump(a)
        }
        let last = self.last_turn(a)
        self.start_turn(a, "resume", self.words(a, if !(last is Null) && retrying(last) { "GO_ON_AFTER_OVERLOADED" } else { "GO_ON_AFTER_SPENT" }))
      })
    "allowanceReset" =>
      self.enqueue(a, async fn() {
        if a.refill is None || self.archived(a) || a.turn is Some(_) || self.busy(a) {
          return
        }
        if self.held(a) {
          a.refill_at = self.now
          return
        }
        if self.turn_slots_full(a) {
          a.refill_at = self.now
          self.enqueue_turn_wait(a)
          return
        }
        let reserved = !a.starting_turn
        if reserved {
          a.starting_turn = true
        }
        defer {
          if reserved {
            a.starting_turn = false
            if a.turn is None {
              self.drain_turn_queue()
            }
          }
        }
        a.refill = None
        if self.has_pending(a) {
          return self.pump(a)
        }
        self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_REFILL"), passive=true)
      })
    "recover" => return self.recover(a)
    "cutOffByRestart" => return self.cut_off_by_restart(a)
    "takeWait" => self.enqueue(a, async fn() { self.take_wait(a) })
    "takeRefill" =>
      self.enqueue(a, async fn() {
        if a.refill is Some(_) || a.turn is Some(_) || self.busy(a) || self.archived(a) {
          return
        }
        let last = self.last_turn(a)
        if str_of(last.value("outcome")) != Some("failed") ||
          !str_of(last.value("detail")).unwrap_or("").has_prefix("rate_limit:") ||
          last.value("endedAt") is (None | Some(Null)) {
          return
        }
        self.await_refill(a, self.refills_at(a))
      })
    "release" => return self.release(a)
    "warm" =>
      self.enqueue(a, async fn() {
        if a.agent is Some(_) || a.codex_update is Some(_) || self.held(a) {
          return
        }
        self.log(a, "info", "warming session process")
        // (its start given up by a stop, a suspension or a close: nothing to warm)
        ignore(self.ensure_agent(a)) catch {
          e => if open_abort_reason(e) is Some(_) { return } else { raise e }
        }
        self.idle_now(a)
        self.notify_store(a)
        ignore(self.deps(a, "idle", [jstr(a.key)]))
      })
    "changed" => {
      let restart = truthy(arg(0))
      let was_paused_cap = a.paused_cap
      a.paused_cap = false
      a.cap_wait_notified = false
      self.remove_cap_wait(a.key)
      // (counted with no process too: one being opened, or taking an earlier change in place, takes it after)
      a.change_seq += 1
      if restart {
        a.restart_seq = a.change_seq
      }
      if a.agent is Some(_) {
        a.stale = true
        if restart {
          a.restart = true
        }
      }
      self.enqueue(a, async fn() {
        self.catch_up(a, a.turn is None && a.waiting is None)
        if was_paused_cap && a.turn is None && !self.busy(a) {
          if self.has_pending(a) {
            self.pump(a)
          } else if a.queued_retry is Some(r) {
            a.queued_retry = None
            self.start_turn(a, r.kind, r.text, by=r.by)
          }
        }
      })
    }
    "evict" => {
      // (`force`: its session archived, its process ends once its turn is over, what it left in the background too:
      // an archived session keeps nothing running, and is packed cold only once its process is gone)
      let force = truthy(arg(0))
      self.enqueue(a, async fn() {
        guard a.agent is Some(g) else { return }
        if self.busy(a) || a.turn is Some(_) || (!force && self.holding(a)) {
          return
        }
        // (another taken up meanwhile is not the idle one)
        guard still(a, Some(g)) else { return }
        self.set_agent(a, None)
        self.log(a, "info", "evicting idle session process")
        ignore(self.agent_do(a, g, "dispose", []))
        self.notify_store(a)
      })
    }
    "compact" => {
      let say = truthy(arg(0))
      let mut refused : String? = None
      self.enqueue(a, async fn() {
        refused = self.begin_compacting(a)
        if refused is Some(r) && say {
          self.notice(a, "⚠️ " + r)
        }
      })
      return match refused { Some(r) => jstr(r); None => Json::null() }
    }
    "compactToCap" => self.enqueue(a, async fn() { ignore(self.compacting_to_cap(a)) })
    "clear" => {
      let say = truthy(arg(0))
      let read_back = truthy(arg(1))
      let mut refused : String? = None
      self.enqueue(a, async fn() {
        refused = self.clear_now(a, read_back)
        if refused is Some(r) && say {
          self.notice(a, "⚠️ " + r)
        }
      })
      return match refused { Some(r) => jstr(r); None => Json::null() }
    }
    "suspend" => return self.suspend(a, why=str_of(Some(arg(0))).unwrap_or("the station is in no workspace"))
    "runChanged" => self.notice(a, str_of(Some(arg(0))).unwrap_or(""), change=arg(1))
    "adopt" => self.adopt(a, arg(0), arg(1), arg(2), arg(3))
    "snapshot" => return self.snapshot(a)
    "close" => self.close(a)
    "dispose" => {
      let agent = a.agent
      self.set_agent(a, None)
      self.close(a)
      if agent is Some(g) {
        ignore(self.agent_do(a, g, "dispose", []))
      }
    }
    _ => raise Asked({ "message": jstr("no actor method \{method}") })
  }
  Json::null()
}

///|
fn about_is(last : Json, thread : Json, seq : Json) -> Bool {
  match last.value("about") {
    Some(Object(about)) => about.get("thread") == Some(thread) && about.get("seq") == Some(seq)
    _ => false
  }
}

///|
/// Held, archived, or something runs (actor.ts's guard of what a press asks).
async fn Actors::blocked(self : Actors, a : Actor) -> Bool raise {
  self.held(a) || self.archived(a) || a.turn is Some(_) || a.codex_update is Some(_) || self.busy(a)
}

///|
/// What instructions.ts says, by its name (`GO_ON_AFTER_*`, `NUDGE`, ...).
async fn Actors::words(self : Actors, a : Actor, name : String, args? : Array[Json] = []) -> String raise {
  match self.rpc(a.key, "node.words", [jstr(name)] + args) {
    String(s) => s
    _ => ""
  }
}

///|
async fn Actors::refills_at(self : Actors, a : Actor) -> Double raise {
  match self.deps(a, "refillsAt", [jstr(a.key)]) {
    Number(n, ..) => n
    _ => self.now + 3600000.0
  }
}

///|
async fn Actors::live_turn_ended(self : Actors, a : Actor) -> Unit raise {
  self.live_turn_end(a.key)
}

///|
async fn Actors::declare_turn(self : Actors, a : Actor, id : String, state : Json?) -> Unit raise {
  match state {
    Some(s) => {
      let kind = s.value("kind").unwrap_or(Json::null())
      let wait = if kind_of(Some(s)) == Some("waiting") { s.value("seconds").unwrap_or(Json::null()) } else { Json::null() }
      ignore(self.store(a, "declareTurn", [jstr(id), kind, wait]))
    }
    None => ignore(self.store(a, "declareTurn", [jstr(id), Json::null(), Json::null()]))
  }
}

///|
/// actor.ts `stateForTurn`: recorded (Node writes it, `record` its transaction) only while that same turn runs.
async fn Actors::state_for_turn(self : Actors, a : Actor, args : Array[Json]) -> Json raise {
  let id = str_of(args.get(0))
  let state = args.get(1).unwrap_or(Json::null())
  let mut recorded = false
  let mut failure : Error? = None
  self.enqueue(a, async fn() {
    guard a.turn is Some(t) && id == Some(t.id) else { return }
    ignore(self.rpc(a.key, "node.stateWrite", args)) catch {
      e => {
        failure = Some(e)
        return
      }
    }
    t.declared = Some(state)
    recorded = true
  })
  if failure is Some(e) {
    raise e
  }
  jbool(recorded)
}

///|
async fn Actors::tools_at(self : Actors, a : Actor, url : String) -> Unit raise {
  guard a.agent is Some(g) else { return }
  let was = match self.agent_do(a, g, "mcpUrl", []) {
    String(s) => s
    _ => return
  }
  if was == url {
    return
  }
  if a.turn is Some(_) || self.busy(a) {
    if a.tools_lost is None {
      a.tools_lost = Some("its process was told the station's tools are at \{was}, not \{url}")
    }
    self.log(a, "warn", "the process taken up was told another address of the station's tools; it starts again once its turn ends", fields={ "was": jstr(was), "now": jstr(url) })
    return
  }
  self.set_agent(a, None)
  self.log(a, "warn", "the process taken up was told another address of the station's tools; ending it, its next turn resumes in a new one", fields={ "was": jstr(was), "now": jstr(url) })
  self.end_process(a, Some(g))
  self.notify_store(a)
}

///|
async fn Actors::undeclare(self : Actors, a : Actor) -> Unit raise {
  guard a.turn is Some(t) && t.declared is Some(d) else { return }
  self.log(a, "info", "a message read after the turn said its state: the state no longer stands", fields={ "was": d.value("kind").unwrap_or(Json::null()) })
  t.declared = None
  self.declare_turn(a, t.id, None)
}

///|
/// actor.ts `stop`.
async fn Actors::stop(self : Actors, a : Actor) -> Json raise {
  let stop_recovery = a.recoveries > 0 || a.recovery_deferred
  a.recovery_deferred = false
  a.queued_retry = None
  let had_deferred = a.deferred_end is Some(_) || a.warm
  a.deferred_end = None
  a.warm = false
  self.cancel_tools_retry(a)
  a.tools_restarts = 0
  a.paused_cap = false
  a.cap_wait_notified = false
  a.force_session_cap = false
  self.mirror(a)
  self.remove_turn_wait(a.key)
  self.remove_cap_wait(a.key)
  a.delivery_interruptions += 1
  // (its runtime's process being opened is given up at once, never waited on behind it in its queue: one that never
  // answered held the stop for hours, FB-34; a turn starting then is said stopped here once its start has unwound,
  // a process only warmed is not)
  let was_starting_turn = a.starting_turn
  let stop_starting = self.abort_open(a, "stopped") && was_starting_turn
  // (what is being read and formatted for it: Node's, given up at once there, mb-actor.ts)
  self.enqueue(a, async fn() {
    defer {
      a.delivery_interruptions -= 1
    }
    if stop_recovery || had_deferred || stop_starting {
      self.set_running(a, false)
    }
    if a.codex_update is Some(_) {
      a.codex_update = None
      self.set_running(a, false)
      self.notice(a, self.t(a, "station.notice.stopped"))
      self.live_turn_ended(a)
      return
    }
    if self.busy_agent(a) is Some(agent) {
      a.stop_requested = true
      ignore(self.agent_do(a, agent, "abort", [])) catch {
        e => {
          a.stop_requested = false
          raise e
        }
      }
      return
    }
    if a.turn is Some(_) {
      return
    }
    let stopped_wait = self.stop_waiting(a)
    if stop_starting && !stopped_wait {
      self.notice(a, self.t(a, "station.notice.stopped"))
    }
    self.live_turn_ended(a)
  })
  Json::null()
}

///|
async fn Actors::reassign(self : Actors, a : Actor, thread : Json, seq : Json) -> Unit raise {
  if self.blocked(a) || self.has_pending(a) {
    return
  }
  let last = self.last_turn(a)
  if last is Null || str_of(last.value("outcome")) != Some("failed") || !about_is(last, thread, seq) {
    return
  }
  // (`shownLimitOf`: the model's own limit, null the account's; none: not such a failure)
  let model = match self.rpc(a.key, "node.words", [jstr("shownLimitOf"), last.value("detail").unwrap_or(Json::null())]) {
    Object(o) => o.get("model").unwrap_or(Json::null())
    _ => return
  }
  let row = self.store(a, "getSession", [jstr(a.key)])
  let ran_on = if a.profile is Null { row.value("profile").unwrap_or(Json::null()) } else { a.profile }
  let moved = self.deps(a, "spend", [jstr(a.key), ran_on, model]) catch {
    e => {
      self.log(a, "warn", "could not move off a profile its allowance showed spent", fields={ "error": jstr(e.to_string()) })
      Json::null()
    }
  }
  if moved is Array(m) {
    let agent = a.agent
    self.set_agent(a, None)
    self.end_process(a, agent)
    self.log(a, "info", "its allowance showed a limit; going on on another profile, as asked", fields={ "from": m[0], "to": m[1] })
    a.refill = None
    return self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_SPENT"))
  }
  if moved is Object(o) && str_of(o.get("paused")) == Some("session_cap") {
    let agent = a.agent
    self.set_agent(a, None)
    self.end_process(a, agent)
    a.refill = None
    a.queued_retry = Some({ kind: "resume", text: self.words(a, "GO_ON_AFTER_SPENT"), by: turn_for_nobody(), codex_retried: false })
    self.pause_for_session_cap(
      a,
      str_of(o.get("profile")).unwrap_or(""),
      num_of(o.get("active")).unwrap_or(0.0).to_int(),
      num_of(o.get("cap")).unwrap_or(0.0).to_int(),
      o.get("protection") is Some(True),
      "resume",
      turn_for_nobody(),
      None,
    )
    return
  }
  let pinned = truthy(row.value("profilePinned").unwrap_or(Json::null()))
  self.notice(a, "⚠️ " + self.t(a, if pinned { "station.notice.reassignPinned" } else { "station.notice.reassignNone" }), profile=ran_on)
  self.await_refill(a, self.refills_at(a))
}

///|
/// actor.ts `stopFromSlack`.
async fn Actors::stop_from_slack(self : Actors, a : Actor, args : Array[Json]) -> Json raise {
  let connect = str_of(args.get(0)).unwrap_or("")
  let channel = str_of(args.get(1)).unwrap_or("")
  let thread_ts = str_of(args.get(2)).unwrap_or("")
  let ts = str_of(args.get(3)).unwrap_or("0")
  // (absent: undefined, as the ts; null: none)
  let local_at = args.get(4)
  let mut failure : Error? = None
  self.enqueue(a, async fn() {
    let at = @string.parse_double(ts) catch { _ => 0.0 }
    let previous = self.store(a, "slackStop", [jstr(a.key), jstr(connect), jstr(channel), jstr(thread_ts)]) catch {
      e => {
        failure = Some(e)
        return
      }
    }
    let prev_ts = str_of(previous.value("ts")).map(s => @string.parse_double(s) catch { _ => 0.0 })
    if prev_ts is Some(p) && p > at {
      return
    }
    let turn = if prev_ts is Some(p) && p == at {
      str_of(previous.value("turn"))
    } else {
      let work = a.working_for.search_by(w => w.connect == connect && w.channel == channel && w.thread_ts == thread_ts).map(i => a.working_for[i])
      let since = match work {
        Some(w) => w.since
        None => num_of(self.last_turn(a).value("startedAt")).unwrap_or(0.0)
      }
      let first = work.map(w => if w.first_ts is Null { w.ts } else { w.first_ts })
      let timely_ts = match first {
        Some(String(f)) if f != "" => at >= (@string.parse_double(f) catch { _ => 0.0 })
        _ => true
      }
      let timely_local = match local_at {
        Some(Null) => true
        Some(Number(l, ..)) => l >= since
        _ => at * 1000.0 >= since
      }
      let turn = match (work, a.turn) {
        (Some(_), Some(t)) if timely_ts && timely_local => Some(t.id)
        _ => None
      }
      ignore(self.store(a, "rememberSlackStop", [jstr(a.key), jstr(connect), jstr(channel), jstr(thread_ts), jstr(ts), match turn { Some(t) => jstr(t); None => Json::null() }])) catch {
        e => {
          failure = Some(e)
          return
        }
      }
      turn
    }
    guard turn is Some(id) && a.turn.map(t => t.id) == Some(id) else { return }
    let busy = self.busy_agent(a) catch {
      e => {
        failure = Some(e)
        return
      }
    }
    guard busy is Some(agent) && !a.stop_requested else { return }
    a.stop_requested = true
    ignore(self.agent_do(a, agent, "abort", [])) catch {
      e => {
        a.stop_requested = false
        failure = Some(e)
      }
    }
  })
  if failure is Some(e) {
    raise e
  }
  Json::null()
}

///|
/// Ends a turn cut off by a non-update station restart without auto-starting the runtime:
/// posts a notice bound to the cut-off turn (when not already declared done/need_human and
/// no pending user message awaits delivery) and returns whether the session awaits manual resume.
async fn Actors::cut_off_by_restart(self : Actors, a : Actor) -> Json raise {
  let mut interrupted = false
  self.enqueue(a, async fn() {
    if a.turn is Some(_) {
      return
    }
    a.recovery_deferred = false
    let ended = num_of(Some(self.store(a, "endCutOff", [jstr(a.key)]))).unwrap_or(0.0).to_int()
    self.set_running(a, false)
    if self.archived(a) {
      self.let_go(a)
      return
    }
    if ended > 0 && !self.has_pending(a) {
      let latest = self.store(a, "latestTurn", [jstr(a.key)])
      let summary = latest.value("summary").unwrap_or(Json::null())
      if cut_off_by_restart(summary) {
        self.notice(a, "⚠️ " + self.t(a, "station.notice.cutOffRestart"), about=str_of(latest.value("id")))
        interrupted = true
      }
    }
  })
  jbool(interrupted)
}

///|
/// actor.ts `recover`.
async fn Actors::recover(self : Actors, a : Actor, slot_reserved? : Bool = false) -> Json raise {
  a.recoveries += 1
  self.enqueue(a, async fn() {
    let mut reading = true
    let mut reserved = slot_reserved && a.starting_turn
    defer {
      if reading {
        a.recoveries -= 1
      }
      if reserved {
        a.starting_turn = false
        if a.turn is None {
          self.drain_turn_queue()
        }
      }
    }
    if a.delivery_interruptions > 0 {
      return
    }
    // The turn the restart cut off (its process gone with no runner to keep it) is ended here, before anything that may
    // fail: left open, the session would be shown at work for ever (2026-11-16, a recovery that could not start).
    if a.turn is None {
      ignore(self.store(a, "endCutOff", [jstr(a.key)]))
    }
    if self.archived(a) {
      a.recovery_deferred = false
      self.set_running(a, false)
      return self.let_go(a)
    }
    if self.held(a) {
      a.recovery_deferred = true
      return
    }
    if self.turn_slots_full(a) {
      a.recovery_deferred = true
      self.enqueue_turn_wait(a)
      return
    }
    if !a.starting_turn {
      a.starting_turn = true
      reserved = true
    }
    a.recovery_deferred = false
    let delivery = self.pending_and_format(a, true)
    a.recoveries -= 1
    reading = false
    guard delivery is Some(d) else { return }
    if a.delivery_interruptions > 0 || self.closed(a) {
      return
    }
    if self.archived(a) {
      self.set_running(a, false)
      return self.let_go(a)
    }
    if self.held(a) {
      a.recovery_deferred = true
      return
    }
    self.set_running(a, false)
    let resume = self.words(a, "RESUME_AFTER_RESTART")
    // (marked delivered by `start_turn_body` before it was written to the runtime, its widgets told after: `start_turn`)
    self.start_turn(a, "resume", if d.text == "" { resume } else { resume + "\n\n" + d.text }, delivery=Some(d))
  })
  Json::null()
}

///|
async fn Actors::take_wait(self : Actors, a : Actor) -> Unit raise {
  if a.waiting is Some(_) || a.turn is Some(_) || self.archived(a) {
    return
  }
  let last = self.last_turn(a)
  if last is Null || last.value("endedAt") is (None | Some(Null)) || str_of(last.value("declared")) != Some("waiting") {
    return
  }
  if str_of(last.value("outcome")) != Some("completed") && !retrying(last) {
    ignore(self.store(a, "forgetWait", [jstr(a.key)]))
    return
  }
  let seconds = num_of(last.value("waitSeconds")).unwrap_or(0.0)
  self.log(a, "info", "taking up a wait on record", fields={ "seconds": jnum(seconds) })
  self.wait_ms(a, seconds, num_of(last.value("endedAt")).unwrap_or(0.0) + seconds * 1000.0 - self.now)
}

///|
/// Wakes a session popped from `turn_wait_queue` with `starting_turn` already reserved.
/// Releases the reserved slot and drains the next queued session if this actor does not start a turn.
async fn Actors::wake_queued(self : Actors, a : Actor) -> Unit raise {
  if a.recovery_deferred && a.recoveries == 0 {
    a.recovery_deferred = false
    ignore(self.recover(a, slot_reserved=true))
    return
  }
  let before = a.start_failures
  self.enqueue(a, async fn() {
    let owned = a.starting_turn
    defer {
      if owned {
        a.starting_turn = false
        if a.turn is None {
          self.drain_turn_queue()
        }
      }
    }
    if a.waiting is Some(wait) && a.waiting_until <= self.now {
      self.fire_wait(a, wait, a.waiting_seconds)
      if a.turn is Some(_) {
        return
      }
    }
    if a.refill is Some(refill) && a.refill_at <= self.now {
      self.fire_refill(a, refill)
      if a.turn is Some(_) {
        return
      }
    }
    if a.queued_retry is Some(r) {
      if self.archived(a) {
        a.queued_retry = None
      } else if !self.held(a) {
        a.queued_retry = None
        if !self.has_pending(a) {
          self.start_turn(a, r.kind, r.text, by=r.by)
          if a.turn is Some(nt) && r.codex_retried {
            nt.codex_retried = true
          }
          if a.turn is Some(_) {
            return
          }
        }
      }
    }
    self.pump(a, before_failures=before)
    if a.turn is None && a.notices.length() > 0 {
      self.give_notices(a)
    }
  })
}

///|
/// Serially wakes a single actor waiting in `cap_wait_queue` until it either starts a turn
/// (occupying a running slot) or hits `sessionCap` again.
async fn Actors::wake_cap_queued(self : Actors, a : Actor) -> Unit raise {
  self.enqueue(a, async fn() {
    if a.phase == "closed" || self.archived(a) || a.turn is Some(_) || self.busy(a) {
      return
    }
    if self.held(a) {
      a.paused_cap = true
      return
    }
    if a.queued_retry is Some(r) {
      if !self.has_pending(a) {
        a.queued_retry = None
        self.start_turn(a, r.kind, r.text, by=r.by) catch {
          e => {
            if session_cap_info(e) is Some(_) {
              a.queued_retry = Some(r)
            }
            raise e
          }
        }
        if a.turn is Some(nt) && r.codex_retried {
          nt.codex_retried = true
        }
        return
      }
    }
    if self.has_pending(a) {
      self.pump(a)
    }
  })
}

///|
async fn Actors::release(self : Actors, a : Actor) -> Json raise {
  if a.recovery_deferred {
    a.recovery_deferred = false
    if a.recoveries == 0 {
      return self.recover(a)
    }
  }
  let before = a.start_failures
  self.enqueue(a, async fn() {
    if a.waiting is Some(_) && a.waiting_until <= self.now {
      self.wait_ms(a, a.waiting_seconds, 0.0)
    }
    if a.refill is Some(_) && a.refill_at <= self.now {
      self.await_refill(a, self.now)
    }
    if a.queued_retry is Some(_) {
      self.enqueue_turn_wait(a)
      self.drain_turn_queue()
      return
    }
    self.pump(a, before_failures=before)
    if a.notices.length() > 0 {
      self.give_notices(a)
    }
    if !self.held(a) && a.turn is None && a.deferred_end is Some(d) {
      let was_warm = a.warm
      a.deferred_end = None
      self.mirror(a)
      defer {
        if a.warm && a.deferred_end is None {
          a.warm = false
          self.mirror(a)
        }
      }
      if self.archived(a) {
        self.cool(a, was_warm)
        self.let_go(a)
        return
      }
      self.continue_undeclared_end(a, d.lost, d.unheard, d.recorded, was_warm)
      return
    }
    if !self.held(a) && a.turn is None && a.tools_retry_deferred {
      a.tools_retry_deferred = false
      self.mirror(a)
      if self.archived(a) {
        self.let_go(a)
        return
      }
      self.start_turn(a, "resume", self.words(a, "TOOLS_LOST"))
    }
  })
  Json::null()
}

///|
async fn Actors::compacting_to_cap(self : Actors, a : Actor) -> Bool raise {
  if self.store(a, "getSession", [jstr(a.key)]).value("contextBefore") is (None | Some(Null)) {
    return false
  }
  if a.turn is Some(_) || a.codex_update is Some(_) || a.compacting || a.waiting is Some(_) || self.busy(a) || self.held(a) || self.archived(a) {
    return false
  }
  guard self.begin_compacting(a) is Some(refused) else { return true }
  self.log(a, "info", "could not compact down to its most context", fields={ "why": jstr(refused) })
  ignore(self.store(a, "setSessionContextBefore", [jstr(a.key), Json::null()]))
  self.notify_store(a)
  false
}

///|
/// Why a thing that failed in Node failed, as its chat is told it (`compactFailed`, `cannotStartWords`).
async fn Actors::failed_words(self : Actors, a : Actor, how : String, e : Error) -> String raise {
  let err = match e {
    Asked(j) => j
    _ => { "message": jstr(e.to_string()) }
  }
  match self.rpc(a.key, "node.words", [jstr(how), err]) {
    String(s) => s
    _ => ""
  }
}

///|
async fn Actors::begin_compacting(self : Actors, a : Actor) -> String? raise {
  if a.turn is Some(_) || a.codex_update is Some(_) || a.compacting || self.busy(a) {
    return Some(self.t(a, "station.context.busy"))
  }
  if self.held(a) {
    return Some(self.t(a, "station.context.held"))
  }
  let row = self.store(a, "getSession", [jstr(a.key)])
  if !truthy(row.value("runtimeSessionId").unwrap_or(Json::null())) {
    return Some(self.t(a, "station.context.empty"))
  }
  let agent = self.ensure_agent(a) catch {
    // (its start given up by a stop, a suspension or a close: what was asked for is over, nothing to say of it)
    e if open_abort_reason(e) is Some(_) => return None
    e => return Some(self.failed_words(a, "compactFailed", e))
  }
  if a.afresh is Some(_) {
    return Some(self.t(a, "station.context.empty"))
  }
  if !truthy(self.agent_do(a, agent, "canCompact", [])) {
    return Some(self.t(a, "station.context.cannotCompact", args={ "name": self.rpc(a.key, "node.words", [jstr("runtimeLabel"), jstr(a.runtime)]) }))
  }
  self.log(a, "info", "compacting its context")
  a.compacting = true
  self.set_running(a, true)
  self.notify_store(a)
  ignore(self.agent_do(a, agent, "compact", [])) catch {
    e => {
      a.compacting = false
      self.set_running(a, false)
      self.notify_store(a)
      return Some(self.failed_words(a, "compactFailed", e))
    }
  }
  None
}

///|
async fn Actors::compacted(self : Actors, a : Actor, outcome : Json) -> Unit raise {
  a.compacting = false
  self.idle_now(a)
  let stop_requested = a.stop_requested
  a.stop_requested = false
  self.set_running(a, false)
  ignore(self.store(a, "setSessionContextBefore", [jstr(a.key), Json::null()]))
  self.notify_store(a)
  let kind = str_of(outcome.value("kind")).unwrap_or("")
  self.log(a, "info", "compaction ended", fields={ "outcome": jstr(kind) })
  if kind == "completed" {
    self.notice(a, self.t(a, "station.notice.compacted"))
  } else if kind == "failed" {
    let reason = str_of(outcome.value("reason")).unwrap_or("")
    self.log(a, "warn", "compaction failed", fields={ "reason": jstr(reason), "error": outcome.value("message").unwrap_or(Json::null()) })
    let said = match self.rpc(a.key, "node.words", [jstr("compactFailedNotice"), outcome]) {
      String(s) => s
      _ => ""
    }
    self.notice(a, said, profile=if reason == "auth" || reason == "refused" { a.profile } else { Json::null() })
  } else if stop_requested {
    self.notice(a, self.t(a, "station.notice.stopped"))
  }
  if self.archived(a) {
    self.let_go(a)
    ignore(self.deps(a, "idle", [jstr(a.key)]))
    return
  }
  if a.over_while_compacting {
    a.over_while_compacting = false
    if a.waiting is Some(_) {
      self.wait_ms(a, a.waiting_seconds, 0.0)
    }
  }
  if self.has_pending(a) {
    return self.pump(a)
  }
  if a.notices.length() > 0 {
    return self.give_notices(a)
  }
  ignore(self.deps(a, "idle", [jstr(a.key)]))
}

///|
async fn Actors::clear_now(
  self : Actors,
  a : Actor,
  read_back : Bool,
  said? : String = if read_back { "station.notice.afresh" } else { "station.notice.cleared" },
  by? : String = "by hand",
  keep_jobs? : Bool = false,
) -> String? raise {
  if a.turn is Some(_) || a.codex_update is Some(_) || a.compacting || self.busy(a) {
    return Some(self.t(a, "station.context.busy"))
  }
  let row = self.store(a, "getSession", [jstr(a.key)])
  let left = row.value("runtimeSessionId").unwrap_or(Json::null())
  if !truthy(left) {
    return Some(self.t(a, "station.context.empty"))
  }
  ignore(self.stop_waiting(a, say=false, keep_jobs~))
  let agent = a.agent
  let background = match agent {
    Some(g) => self.agent_do(a, g, "background", [])
    None => Json::array([])
  }
  self.set_agent(a, None)
  self.log(a, "info", "clearing its context, asked \{by}", fields={
    "left": left,
    "readBack": jbool(read_back),
    "background": jnum(match background { Array(b) => b.length().to_double(); _ => 0.0 }),
  })
  if agent is Some(g) {
    ignore(self.agent_do(a, g, "dispose", []))
  }
  a.stopped.clear()
  a.stopped_note = None
  a.resume_lost = false
  a.afresh = None
  a.codex_reloaded = None
  a.compacted_untold = false
  a.nudges = 0
  self.cancel_tools_retry(a)
  a.tools_restarts = 0
  a.deferred_end = None
  a.warm = false
  self.mirror(a)
  ignore(self.deps(a, "ranIn", [jstr(a.key), left, Json::null()]))
  ignore(self.store(a, "setRuntimeSessionId", [jstr(a.key), Json::null()]))
  a.read_back = read_back
  self.notify_store(a)
  self.notice(a, self.t(a, said))
  None
}

///|
/// actor.ts `suspend`: `why`, what is said of it, in the log and as the turn's end (the station left its workspace, or
/// this chat is held for a move).
async fn Actors::suspend(self : Actors, a : Actor, why? : String = "the station is in no workspace") -> Json raise {
  // (its runtime's process being opened is given up at once: what it was handed stays undelivered, taken up after)
  ignore(self.abort_open(a, "suspended"))
  a.delivery_interruptions += 1
  self.enqueue(a, async fn() {
    defer {
      a.delivery_interruptions -= 1
    }
    let agent = a.agent
    self.set_agent(a, None)
    let busy = self.busy_of(a, agent)
    let turn = a.turn
    let had_slot = turn is Some(_) || a.starting_turn
    a.turn = None
    a.warm = false
    a.deferred_end = None
    self.cancel_tools_retry(a)
    a.starting_turn = false
    a.queued_retry = None
    self.remove_turn_wait(a.key)
    defer {
      if had_slot && a.turn is None && !a.starting_turn {
        self.drain_turn_queue()
      }
    }
    a.tools.clear()
    a.working_for = []
    a.stop_requested = false
    let steered = a.steered
    a.steered = []
    a.steered_for = []
    a.unread = []
    if agent is None && turn is None {
      return
    }
    let resume = (turn is Some(_) || busy) && !(turn is Some({ declared: Some(d), .. }) && settled_state(d))
    self.log(a, "info", "ending the runtime process: " + why, fields={ "resume": jbool(resume) })
    if agent is Some(g) {
      ignore(self.agent_do(a, g, "dispose", []))
    }
    if turn is Some(t) {
      let ended = kind_of(ended_in(t.declared, "aborted"))
      ignore(self.store(a, "endTurn", [jstr(t.id), jstr("aborted"), jstr("other: " + why), match ended { Some(k) => jstr(k); None => Json::null() }, Json::null()]))
    }
    self.set_running(a, resume)
    if turn is Some(_) || busy {
      ignore(self.store(a, "markUndelivered", [jstr(a.key), Json::array(steered)]))
    }
    self.live_turn_ended(a)
    self.notify_store(a)
    a.phase = "idle"
  })
  Json::null()
}

///|
/// Where it stands, for the next station (actor.ts `snapshot`; its runtime session's own is Node's to add); from here on
/// it does nothing more.
fn Actors::snapshot(self : Actors, a : Actor) -> Json {
  let turn = match a.turn {
    Some(t) =>
      ({
        "id": jstr(t.id),
        "authRetried": jbool(t.auth_retried),
        "codexRetried": jbool(t.codex_retried),
        "passive": jbool(t.passive),
        "by": t.by,
        "declared": match kind_of(t.declared) { Some(k) => jstr(k); None => Json::null() },
        "wait": if kind_of(t.declared) == Some("waiting") { t.declared.unwrap().value("seconds").unwrap_or(Json::null()) } else { Json::null() },
        "askedBefore": t.asked_before.unwrap_or(Json::null()),
      } : Json)
    None => Json::null()
  }
  let deferred_end = match a.deferred_end {
    Some(d) =>
      ({
        "lost": jbool(d.lost),
        "unheard": jbool(d.unheard),
        "recorded": match d.recorded { Some(r) => jstr(r); None => Json::null() },
      } : Json)
    None => Json::null()
  }
  let max0 = (x : Double) => if x < 0.0 { 0.0 } else { x }
  let snap : Json = {
    "key": jstr(a.key),
    "runtime": jstr(a.runtime),
    "identity": a.running_identity,
    "turn": turn,
    "deferredEnd": deferred_end,
    "workingFor": Json::array(a.working_for.map(working_json)),
    "notices": Json::array(a.notices.map(jstr)),
    "waitingMs": if a.waiting is Some(_) { jnum(max0(a.waiting_until - self.now)) } else { Json::null() },
    "waitingSeconds": jnum(a.waiting_seconds),
    "nudges": jnum(a.nudges.to_double()),
    "toolsRestarts": jnum(a.tools_restarts.to_double()),
    "toolsRetryMs": if a.tools_retry is Some(_) { jnum(max0(a.tools_retry_at - self.now)) } else if a.tools_retry_deferred { jnum(0.0) } else { Json::null() },
    "stopRequested": jbool(a.stop_requested),
    "refillMs": if a.refill is Some(_) { jnum(max0(a.refill_at - self.now)) } else { Json::null() },
    "idleMs": jnum(max0(self.now - a.idle_since)),
    "stale": jbool(a.stale),
    "restart": jbool(a.restart),
    "compacting": jbool(a.compacting),
    "agent": match a.agent { Some(g) => jnum(g.handle.to_double()); None => Json::null() },
  }
  self.close(a)
  snap
}

///|
/// actor.ts `adopt`: `agent` its runtime session taken up (`{handle, generation}`, or null), on `profile`.
fn Actors::adopt(self : Actors, a : Actor, snap : Json, agent : Json, profile : Json, row : Json) -> Unit {
  let runtime = str_of(snap.value("runtime")).unwrap_or(a.runtime)
  let taken = match agent {
    Object(g) => Some({ generation: num_of(g.get("generation")).unwrap_or(0.0).to_int(), handle: num_of(g.get("handle")).unwrap_or(0.0).to_int() })
    _ => None
  }
  if taken is Some(_) {
    a.runtime = runtime
  }
  a.running_identity = match (taken, snap.value("identity")) {
    (None, _) => Json::null()
    (Some(_), Some(Object(_) as i)) => i
    _ => { "runtime": jstr(runtime), "model": row.value("model").unwrap_or(Json::null()), "effort": row.value("effort").unwrap_or(Json::null()) }
  }
  self.set_agent(a, taken)
  a.profile = if taken is Some(_) { profile } else { Json::null() }
  a.turn = match snap.value("turn") {
    Some(Object(t)) =>
      Some({
        id: str_of(t.get("id")).unwrap_or(""),
        auth_retried: t.get("authRetried") is Some(True),
        codex_retried: t.get("codexRetried") is Some(True),
        passive: t.get("passive") is Some(True),
        by: t.get("by").unwrap_or(turn_for_nobody()),
        declared: match str_of(t.get("declared")) {
          Some(k) => parse_declared(k, num_of(t.get("wait")).unwrap_or(0.0))
          None => None
        },
        asked_before: match t.get("askedBefore") {
          Some(Object(_) as b) => Some(b)
          _ => None
        },
      })
    _ => None
  }
  a.phase = if a.turn is Some(_) { "running" } else { "idle" }
  a.deferred_end = match snap.value("deferredEnd") {
    Some(Object(d)) =>
      Some({
        lost: d.get("lost") is Some(True),
        unheard: d.get("unheard") is Some(True),
        recorded: str_of(d.get("recorded")),
      })
    _ => None
  }
  a.warm = a.turn is None && a.deferred_end is Some(_)
  a.working_for = match snap.value("workingFor") {
    Some(Array(ws)) => ws.map(working_of)
    _ => []
  }
  let notices = match snap.value("notices") {
    Some(Array(ns)) => ns.filter_map(n => str_of(Some(n)))
    _ => []
  }
  a.notices = notices + a.notices
  a.nudges = num_of(snap.value("nudges")).unwrap_or(0.0).to_int()
  a.tools_restarts = num_of(snap.value("toolsRestarts")).unwrap_or(0.0).to_int()
  a.stop_requested = snap.value("stopRequested") is Some(True)
  let runtime_changed = taken is Some(_) && str_of(row.value("runtime")) != Some(runtime)
  a.stale = runtime_changed || snap.value("stale") is Some(True)
  a.restart = runtime_changed || snap.value("restart") is Some(True)
  a.compacting = snap.value("compacting") is Some(True)
  a.idle_since = self.now - num_of(snap.value("idleMs")).unwrap_or(0.0)
  if num_of(snap.value("waitingMs")) is Some(ms) {
    self.wait_ms(a, num_of(snap.value("waitingSeconds")).unwrap_or(0.0), ms)
  }
  if num_of(snap.value("refillMs")) is Some(ms) {
    self.await_refill(a, self.now + ms)
  }
  if num_of(snap.value("toolsRetryMs")) is Some(ms) {
    self.schedule_tools_retry(a, ms)
  }
  // (told now, its idle time with it: what `set_agent` told above was before it was taken up whole)
  self.mirror(a)
}

///|
/// For shutdown or handover: queued and later tasks are skipped, timers end.
fn Actors::close(self : Actors, a : Actor) -> Unit {
  let had_slot = a.turn is Some(_) || a.starting_turn
  ignore(self.abort_open(a, "closed"))
  a.phase = "closed"
  a.turn = None
  a.warm = false
  a.deferred_end = None
  self.cancel_tools_retry(a)
  a.starting_turn = false
  a.queued_retry = None
  a.paused_cap = false
  a.cap_wait_notified = false
  a.force_session_cap = false
  self.remove_turn_wait(a.key)
  self.remove_cap_wait(a.key)
  for cancel in a.timers.values() {
    cancel()
  }
  a.timers.clear()
  self.mirror(a)
  if had_slot {
    self.drain_turn_queue()
  }
}

// ── inside the queue ──────────────────────────────────────────────────────────────────────────────────────────────

///|
/// What its notices say, as it is handed them (they stay its own until they are: `drain_notices`).
async fn Actors::format_notices(self : Actors, a : Actor, notices : Array[String]) -> String? raise {
  if notices.length() == 0 {
    return None
  }
  let at = str_of(Some(self.deps(a, "nextTs", []))).unwrap_or("")
  Some(
    notices
    .map(n => "<message via=\"station\" from=\"station\" ts=\"\{at}\">\n\{n}\n</message>")
    .join("\n"),
  )
}

///|
/// Its first `n` notices, taken as handed (written to its runtime, or stopped by a person): what they were.
fn drain_notices(a : Actor, n : Int) -> Array[String] {
  let k = if n > a.notices.length() { a.notices.length() } else { n }
  if k <= 0 {
    return []
  }
  let taken : Array[String] = []
  let left : Array[String] = []
  for i, notice in a.notices {
    if i < k {
      taken.push(notice)
    } else {
      left.push(notice)
    }
  }
  a.notices = left
  taken
}

///|
/// The words handed with what people chose on its cards meanwhile (actor.ts `withChoices`): Node's, which marks them
/// told once `told` is asked of it.
async fn Actors::with_choices(self : Actors, a : Actor, text : String) -> (String, Json) raise {
  let got = self.rpc(a.key, "node.withChoices", [jstr(text)])
  (str_of(got.value("text")).unwrap_or(text), got.value("told").unwrap_or(Json::null()))
}

///|
async fn Actors::told(self : Actors, a : Actor, told : Json) -> Unit raise {
  if !(told is Null) {
    ignore(self.rpc(a.key, "node.told", [told]))
  }
}

///|
async fn Actors::timed(self : Actors, a : Actor, text : String) -> String raise {
  str_of(Some(self.rpc(a.key, "node.timed", [jstr(text)]))).unwrap_or(text)
}

///|
async fn Actors::give_notices(self : Actors, a : Actor) -> Unit raise {
  if self.held(a) || a.compacting || a.codex_update is Some(_) {
    return
  }
  if self.archived(a) {
    a.notices = []
    return
  }
  if a.refill is Some(_) && !self.busy(a) {
    return
  }
  let was = a.agent
  let busy = self.busy_of(a, was)
  // (let go of meanwhile: its turn's end gives them)
  guard still(a, was) else { return }
  if busy && was is Some(agent) {
    // (never into a turn on how it ran before a change: they wait for its end, which gives them a turn as changed)
    if a.stale {
      return
    }
    let n = a.notices.length()
    guard self.format_notices(a, a.notices) is Some(text) else { return }
    let (handed, told) = self.with_choices(a, text)
    // (taken once written: one not taken stays as it was, given with the next turn)
    if truthy(self.agent_do(a, agent, "steer", [jstr(self.timed(a, handed))])) {
      ignore(drain_notices(a, n))
      self.told(a, told)
    }
    return
  }
  if a.notices.length() == 0 {
    return
  }
  if self.turn_slots_full(a) {
    self.enqueue_turn_wait(a)
    return
  }
  let reserved = !a.starting_turn
  if reserved {
    a.starting_turn = true
  }
  defer {
    if reserved {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!a.paused_cap)
      }
    }
  }
  // (still its own while its runtime opens: taken as they are written to it (`start_turn_body`), so a start that
  // fails, times out, waits for room, is suspended or handed over keeps them for its next turn)
  let n = a.notices.length()
  if self.format_notices(a, a.notices) is Some(text) {
    self.start_turn(a, "job", text, notices_taken=n)
  }
}

///|
priv struct Delivery {
  /// what each message is (mb-actor.ts `light`): where it came by, its entry, who wrote it
  pending : Array[Json]
  text : String
  widgets : Json
}

///|
fn Actors::interrupted(self : Actors, a : Actor) -> Bool {
  a.delivery_interruptions > 0 || a.recoveries > 0 || a.recovery_deferred || self.closed(a)
}

///|
/// What `pending` hands over, as one key: the same messages waiting again say the same.
fn handed_ids(pending : Array[Json]) -> String {
  pending.map(m => m.value("handed").unwrap_or(Json::null()).stringify()).join(",")
}

///|
/// `before_failures`: how many turns had failed to start as it was asked (a kick, a release queued behind a start
/// that then failed); -1, now. Asked before a failure, with the same messages still waiting and none since, it starts
/// no turn on them again: the hub's kicks at a start came three at once, each waiting 120 s on a runtime that could not
/// start (2026-11-19). What comes after the failure, a message or a wake of its own, starts one.
async fn Actors::pump(self : Actors, a : Actor, before_failures? : Int = -1) -> Unit raise {
  // (stopped by a move and spoken to: said once in this stop what it waits for and what to do; what was said is kept:
  // actor.ts `pump`, SessionDeps `stoppedNotice`)
  let held = self.held(a)
  if held && self.has_pending(a) {
    if str_of(Some(self.deps(a, "stoppedNotice", [jstr(a.key)]))) is Some(words) {
      self.notice(a, "⚠️ " + words)
    }
  }
  if a.delivery_interruptions > 0 || a.recoveries > 0 || a.recovery_deferred || held || self.archived(a) || a.compacting {
    return
  }
  if a.codex_update is Some(u) {
    if u.finished {
      self.continue_after_codex_update(a, u)
    }
    return
  }
  if !self.has_pending(a) || self.compacting_to_cap(a) {
    return
  }
  if self.interrupted(a) || self.held(a) || self.archived(a) || a.compacting {
    return
  }
  let mut reserved = false
  if a.turn is None && !a.starting_turn {
    if self.turn_slots_full(a) {
      self.enqueue_turn_wait(a)
      if a.failed_handed != "" {
        self.mirror(a)
        self.notify_store(a)
      }
      return
    }
    a.starting_turn = true
    reserved = true
  }
  defer {
    if reserved {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!a.paused_cap)
      }
    }
  }
  let delivery = self.pending_and_format(a, false)
  guard delivery is Some(d) else { return }
  if self.interrupted(a) || self.held(a) || self.archived(a) || a.compacting {
    return
  }
  let was = a.agent
  let busy = self.busy_of(a, was)
  let hkey = handed_ids(d.pending)
  if !busy && a.paused_cap {
    if hkey != "" && hkey == a.failed_handed {
      return
    }
    // New user reply arrived while queued: jump the queue and bypass the concurrency cap.
    self.remove_cap_wait(a.key)
    a.paused_cap = false
    a.cap_wait_notified = false
    a.force_session_cap = true
  }
  if !busy &&
    before_failures >= 0 &&
    before_failures < a.start_failures &&
    hkey != "" &&
    hkey == a.failed_handed {
    return
  }
  // A new attempt (including a capacity queue) supersedes the failed attempt, but keeps its messages.
  if a.failed_handed != "" && !a.paused_cap {
    a.failed_handed = ""
    self.mirror(a)
    self.notify_store(a)
  }
  // (let go of meanwhile: its turn's end pumps again)
  guard still(a, was) else { return }
  if busy && was is Some(agent) {
    // (never into a turn on how it ran before a change, which would answer as it: what was said waits for its end,
    // which pumps it into a turn as changed)
    if a.stale {
      return
    }
    if truthy(self.deps(a, "backgroundOnMessage", [jstr(a.key)])) {
      ignore(self.agent_do(a, agent, "backgroundTools", []))
    }
    let (handed, told) = self.with_choices(a, d.text)
    // (unread before it is written: the model can read it and ask again, `requesting`, before the steer answers)
    let before = a.unread.length()
    let mut added = 0
    for m in d.pending {
      if !(m.value("apart") is Some(True)) {
        a.unread.push(m)
        added += 1
      }
    }
    let unsteer = () => if a.unread.length() >= before + added {
      for _ in 0..<added {
        ignore(a.unread.pop())
      }
    }
    let steered = truthy(self.agent_do(a, agent, "steer", [jstr(self.timed(a, handed))])) catch {
      e => {
        unsteer()
        raise e
      }
    }
    if !steered {
      unsteer()
    } else {
      self.told(a, told)
      self.work_for(a, d.pending)
      self.delivered(a, d)
      for m in d.pending {
        a.steered.push(m.value("handed").unwrap_or(Json::null()))
      }
      let from = (w : Working) => d.pending.iter().any(m => str_of(m.value("connect")) == Some(w.connect) &&
        str_of(m.value("channel")) == Some(w.channel) &&
        str_of(m.value("threadTs")) == Some(w.thread_ts))
      a.steered_for = a.steered_for.filter(w => !from(w)) + a.working_for.filter(from)
    }
    return
  }
  if self.turn_slots_full(a) {
    self.enqueue_turn_wait(a)
    return
  }
  if !a.starting_turn {
    a.starting_turn = true
    reserved = true
  }
  a.nudges = 0
  self.cancel_tools_retry(a)
  a.tools_restarts = 0
  a.deferred_end = None
  self.work_for(a, d.pending)
  let by = match d.pending.search_by(m => str_of(m.value("authorKind")) == Some("person")) {
    Some(i) => ({ "person": d.pending[i].value("person").unwrap_or(Json::null()), "thread": d.pending[i].value("thread").unwrap_or(Json::null()), "profile": Json::null() } : Json)
    None => turn_for_nobody()
  }
  self.start_turn(a, "input", d.text, by~, delivery=Some(d)) catch {
    e => {
      a.start_failures += 1
      a.failed_handed = hkey
      self.mirror(a)
      self.notify_store(a)
      raise e
    }
  }
  a.failed_handed = ""
}

///|
async fn Actors::work_for(self : Actors, a : Actor, messages : Array[Json]) -> Unit raise {
  for m in messages {
    if str_of(m.value("surface")) == Some("stillfail") {
      continue
    }
    let connect = str_of(m.value("connect")).unwrap_or("")
    let channel = str_of(m.value("channel")).unwrap_or("")
    let thread_ts = str_of(m.value("threadTs")).unwrap_or("")
    let ts = m.value("ts").unwrap_or(Json::null())
    match a.working_for.search_by(w => w.connect == connect && w.channel == channel && w.thread_ts == thread_ts) {
      Some(i) => a.working_for[i].ts = ts
      None => a.working_for.push({ connect, channel, thread_ts, ts, first_ts: ts, since: self.now })
    }
  }
  self.say(a, jstr("thinking"))
}

///|
/// Its threads' status line (actor.ts `say`), told Node (each thread's surface's `working`): "" none, "thinking", or
/// `{tool}` what a tool is doing (its words Node's).
fn Actors::say(self : Actors, a : Actor, status : Json) -> Unit {
  if a.working_for.length() == 0 {
    return
  }
  self.tell(a.key, "node.working", [Json::array(a.working_for.map(working_json)), status])
}

///|
/// A live step of the running turn, for its threads' status line.
fn Actors::on_live(self : Actors, a : Actor, event : Json) -> Unit {
  if a.working_for.length() == 0 {
    return
  }
  let kind = str_of(event.value("kind")).unwrap_or("")
  let id = str_of(event.value("id")).unwrap_or("")
  if kind == "start" && str_of(event.value("step")) == Some("tool") && str_of(event.value("tool")) is Some(tool) && tool != "" {
    if !a.tools.iter().any(t => t.0 == id) {
      a.tools.push((id, tool))
    }
  } else if kind == "end" {
    a.tools = a.tools.filter(t => t.0 != id)
  } else if kind != "phase" {
    return
  }
  match a.tools.last() {
    Some((_, tool)) => self.say(a, { "tool": jstr(tool) })
    None => self.say(a, jstr("thinking"))
  }
}

///|
fn Actors::done_working(self : Actors, a : Actor) -> Unit {
  if a.working_for.length() > 0 {
    a.ended_for = a.working_for
  }
  self.say(a, jstr(""))
  a.working_for = []
  a.tools = []
}

///|
async fn Actors::delivered(self : Actors, a : Actor, d : Delivery) -> Unit raise {
  ignore(self.store(a, "markDelivered", [jstr(a.key), Json::array(d.pending.map(m => m.value("handed").unwrap_or(Json::null())))]))
  ignore(self.store(a, "markWidgetModelsTold", [jstr(a.key), d.widgets]))
}

///|
/// What waits for it, read and formatted as it reads it (Node's: actor.ts `pendingAndFormat`); none (`allowEmpty`
/// aside) or stopped meanwhile: nothing.
async fn Actors::pending_and_format(self : Actors, a : Actor, allow_empty : Bool) -> Delivery? raise {
  match self.rpc(a.key, "node.pendingAndFormat", [jbool(allow_empty)]) {
    Object(d) =>
      Some({
        pending: match d.get("pending") {
          Some(Array(p)) => p
          _ => []
        },
        text: str_of(d.get("text")).unwrap_or(""),
        widgets: d.get("widgets").unwrap_or(Json::array([])),
      })
    _ => None
  }
}

///|
fn session_cap_info(e : Error) -> (String, Int, Int, Bool)? {
  match e {
    Asked(j) if j.value("sessionCap") is Some(True) => {
      let profile = str_of(j.value("profile")).unwrap_or("")
      let active = num_of(j.value("active")).unwrap_or(0.0).to_int()
      let cap = num_of(j.value("cap")).unwrap_or(0.0).to_int()
      let protection = j.value("protection") is Some(True)
      Some((profile, active, cap, protection))
    }
    _ => None
  }
}

///|
/// Enqueues `a` in `cap_wait_queue` and posts a retryable queued notice once per wait.
async fn Actors::pause_for_session_cap(
  self : Actors,
  a : Actor,
  profile : String,
  active : Int,
  cap : Int,
  protection : Bool,
  kind : String,
  by : Json,
  turn : Turn?,
) -> Unit raise {
  self.enqueue_cap_wait(a)
  a.paused_cap = true
  a.force_session_cap = false
  if !a.cap_wait_notified {
    let tid = match turn {
      Some(t) => t.id
      None => {
        let id = str_of(Some(self.rpc(a.key, "node.uuid", []))).unwrap_or("")
        ignore(self.store(a, "startTurnFor", [jstr(id), jstr(a.key), jstr(kind), by]))
        id
      }
    }
    ignore(self.store(a, "endTurn", [jstr(tid), jstr("failed"), jstr("other: session_cap"), Json::null(), Json::null()]))
    let notice_key = if protection {
      "station.notice.accountCapProtectionPaused"
    } else {
      "station.notice.accountCapPaused"
    }
    let said = self.t(a, notice_key, args={
      "profile": jstr(profile),
      "active": jnum(active.to_double()),
      "cap": jnum(cap.to_double()),
    })
    self.notice(a, said, about=Some(tid))
    a.cap_wait_notified = true
  } else if turn is Some(t) {
    ignore(self.store(a, "endTurn", [jstr(t.id), jstr("failed"), jstr("other: session_cap"), Json::null(), Json::null()]))
  }
  self.set_running(a, false)
  self.live_turn_ended(a)
  self.done_working(a)
}

///|
/// actor.ts `startTurn`.
async fn Actors::start_turn(
  self : Actors,
  a : Actor,
  kind : String,
  text : String,
  by? : Json = turn_for_nobody(),
  delivery? : Delivery? = None,
  passive? : Bool = false,
  notices_taken? : Int = 0,
  fresh? : Bool = false,
) -> Unit raise {
  let own_slot = !a.starting_turn
  if own_slot {
    a.starting_turn = true
  }
  let mut paused_by_cap = false
  defer {
    if own_slot {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!paused_by_cap)
      }
    }
  }
  let retry_about = if text == self.words(a, "GO_ON_AFTER_OVERLOADED") {
    self.last_turn(a).value("about").unwrap_or(Json::null())
  } else {
    Json::null()
  }
  if kind != "input" && self.archived(a) {
    self.log(a, "info", "archived: no turn of its own", fields={ "kind": jstr(kind) })
    return
  }
  // (a turn begun anew: the profiles a chain of `auth_retry` turns was refused on are those of turns before)
  if kind != "auth_retry" {
    a.auth_tried = []
  }
  self.start_turn_body(a, kind, text, by, retry_about, delivery, passive, notices_taken, fresh) catch {
    e => {
      let turn = a.turn
      a.turn = None
      // (its runtime's start given up (`abort_open`): no failure, never said it could not start, nor counted one in
      // `pump`. Stopped by a person, what it was handed is taken as had, as a turn stopped once running is; suspended,
      // it waits to be handed again; closed, the next station takes it up as it stands)
      if open_abort_reason(e) is Some(why) {
        if why == "closed" {
          return
        }
        a.phase = "idle"
        if why == "stopped" {
          if delivery is Some(d) {
            self.delivered(a, d)
          }
          ignore(drain_notices(a, notices_taken))
        }
        if turn is Some(t) {
          let stopped = why == "stopped"
          ignore(self.store(a, "endTurn", [jstr(t.id), jstr("aborted"), jstr(if stopped { "user" } else { "other: " + why }), if stopped { jstr("stopped") } else { Json::null() }, Json::null()]))
        }
        self.set_running(a, false)
        self.live_turn_ended(a)
        self.done_working(a)
        return
      }
      a.phase = "idle"
      if session_cap_info(e) is Some((profile, active, cap, protection)) {
        paused_by_cap = true
        self.pause_for_session_cap(a, profile, active, cap, protection, kind, by, turn)
        raise e
      }
      let message = match e {
        Asked(j) => str_of(j.value("message")).unwrap_or("")
        _ => e.to_string()
      }
      if turn is Some(t) {
        ignore(self.store(a, "endTurn", [jstr(t.id), jstr("failed"), jstr("other: " + message), Json::null(), Json::null()]))
      }
      self.set_running(a, false)
      self.live_turn_ended(a)
      self.done_working(a)
      let missing = match e {
        Asked(j) => j.value("missing") is Some(True)
        _ => false
      }
      // (what it is to run, as its row said before it failed to)
      if e is Asked(j) && str_of(j.value("runtime")) is Some(runtime) {
        a.runtime = runtime
      }
      if missing {
        ignore(self.deps(a, "runtimeMissing", [jstr(a.runtime)]))
      }
      async fn missing_said() -> String raise {
        "⚠️ " + self.t(a, "station.notice.runtimeMissing", args={ "name": self.rpc(a.key, "node.words", [jstr("runtimeLabel"), jstr(a.runtime)]) })
      }
      let said = if missing {
        missing_said()
      } else {
        "⚠️ " + self.failed_words(a, "cannotStartWords", e)
      }
      // (a start failing is said once until a person speaks, whatever its reason; but the runtime said missing
      // before, starting with the same words, is not that: its failing now that it is there is news)
      let cannot_start = "⚠️ " + self.t(a, "station.notice.cannotStart")
      let dup = match self.said_last(a) {
        Some(l) if l == said => true
        Some(l) if !missing && l.has_prefix(cannot_start) => l != missing_said()
        _ => false
      }
      if !dup {
        self.notice(a, said, runtime=if missing { jstr(a.runtime) } else { Json::null() }, about=turn.map(t => t.id))
      }
      raise e
    }
  }
  // (what it was handed is its model's now: the widgets it showed are told, never for one not handed)
  if delivery is Some(d) {
    ignore(self.store(a, "markWidgetModelsTold", [jstr(a.key), d.widgets]))
  }
}

///|
async fn Actors::start_turn_body(
  self : Actors,
  a : Actor,
  kind : String,
  text : String,
  by : Json,
  retry_about : Json,
  delivery : Delivery?,
  passive : Bool,
  notices_taken : Int,
  fresh : Bool,
) -> Unit raise {
  self.live_event(a.key, { "kind": "phase", "phase": "starting" })
  if (kind == "input" || kind == "job") && !self.holding(a) && !self.busy(a) &&
    self.deps(a, "coldAfresh", [jstr(a.key), jnum(self.now)]) is True {
    ignore(self.clear_now(a, true, said="station.notice.afreshCold", by="as its cache is over", keep_jobs=true))
  }
  if (kind == "input" || kind == "resume" || kind == "job") && a.runtime == "codex" && !self.busy(a) {
    self.refused_thread(a)
  }
  let mut agent = self.open_over(a, passive)
  let lost = a.resume_lost
  a.resume_lost = false
  let (handed, told_choices) = self.with_choices(a, text)
  a.turn_text = handed
  let stopped = a.stopped_note
  a.stopped_note = None
  let afresh = a.afresh
  a.afresh = None
  let compacted = a.compacted_untold
  a.compacted_untold = false
  // (what goes before what it is handed: its resume lost, what was stopped, a long chat, afresh, continued here, what
  // changed in how it works; Node's words, actor.ts `startTurn`)
  let prompt = str_of(
    Some(
      self.rpc(a.key, "node.prompt", [
        jstr(handed),
        jbool(lost),
        match stopped { Some(s) => jstr(s); None => Json::null() },
        match afresh { Some(s) => jstr(s); None => Json::null() },
        jbool(compacted),
      ]),
    ),
  ).unwrap_or(handed)
  // (changed while it was asked its prompt: taken before the turn begins, never run on how it was before)
  if a.stale && !self.busy_of(a, Some(agent)) {
    agent = self.ensure_agent(a)
  }
  // (what it is handed, marked delivered before it is written: the runtime can answer with `chat_post` before the
  // prompt's answer comes back, and a message still undelivered then is taken as one it has not read, holding the post)
  let delivered = match delivery {
    Some(d) => d.pending.map(m => m.value("handed").unwrap_or(Json::null()))
    None => []
  }
  if self.busy_of(a, Some(agent)) && truthy(self.agent_do(a, agent, "steer", [jstr(prompt)])) {
    if delivered.length() > 0 {
      ignore(self.store(a, "markDelivered", [jstr(a.key), Json::array(delivered)]))
    }
    ignore(drain_notices(a, notices_taken))
    return self.told(a, told_choices)
  }
  a.steered = []
  a.steered_for = []
  a.unread = []
  self.begin_turn(a, kind, by, passive~, fresh~)
  if !(retry_about is Null) && a.turn is Some(t) {
    ignore(self.store(a, "setAbout", [jstr(t.id), [retry_about.value("thread").unwrap_or(Json::null()), retry_about.value("seq").unwrap_or(Json::null()), retry_about.value("ts").unwrap_or(Json::null())]]))
  }
  let marked = delivered.length() > 0
  if marked {
    ignore(self.store(a, "markDelivered", [jstr(a.key), Json::array(delivered)]))
  }
  // (its notices taken as what it is handed is: given back with it where it never began)
  let drained_notices = drain_notices(a, notices_taken)
  ignore(self.agent_do(a, agent, "prompt", [jstr(prompt)])) catch {
    // (its runtime began a turn of its own while this one was begun (the awaits of `begin_turn`, after `busy_of` said
    // idle): what it is handed is steered into that turn, which the turn begun here takes as its own, never the
    // process ended and the turn it runs lost with it)
    e if Asked::message(e) == "a turn is already running" &&
      truthy(self.agent_do(a, agent, "steer", [jstr(prompt)]) catch { _ => Json::boolean(false) }) =>
      return self.told(a, told_choices)
    e => {
      self.log(a, "warn", "prompt failed, reopening the runtime", fields={ "error": jstr(e.to_string()) })
      try {
        self.set_agent(a, None)
        ignore(self.agent_do(a, agent, "dispose", []))
        agent = self.ensure_agent(a)
        ignore(self.agent_do(a, agent, "prompt", [jstr(prompt)]))
      } catch {
        e2 => {
          // (never begun: waiting again, to be handed again; but not what a person stopped as it began)
          if open_abort_reason(e2) != Some("stopped") {
            if marked {
              ignore(self.store(a, "markUndelivered", [jstr(a.key), Json::array(delivered)]))
            }
            if drained_notices.length() > 0 {
              a.notices = drained_notices + a.notices
            }
          }
          raise e2
        }
      }
    }
  }
  self.told(a, told_choices)
}

///|
/// Its last turn refused by Codex with a bare Bad Request (FB-26, `bare_bad_request`), and it is asked to go on (重试, a
/// message, its work's report): never on the thread as it is loaded, which refuses every turn. First that thread is let
/// go and taken up again from its rollout (codex.ts `thread/unload`, then `resume`: its context and cache kept, the
/// account's app-server and its other threads untouched); where the one taken up again is refused too, its history
/// itself is what the backend refuses, and it starts afresh (its jobs kept), told to read back what it needs.
async fn Actors::refused_thread(self : Actors, a : Actor) -> Unit raise {
  if !refused_bad_request(self.last_turn(a)) {
    return
  }
  let id = match str_of(self.store(a, "getSession", [jstr(a.key)]).value("runtimeSessionId")) {
    Some(id) if id != "" => id
    _ => return
  }
  if a.codex_reloaded == Some(id) {
    a.codex_reloaded = None
    self.log(a, "warn", "its Codex thread, taken up again, was refused again with Bad Request: starting afresh", fields={ "thread": jstr(id) })
    ignore(self.clear_now(a, true, said="station.notice.afreshRefused", by="as its Codex thread taken up again was refused with Bad Request", keep_jobs=true))
    return
  }
  a.codex_reloaded = Some(id)
  self.log(a, "warn", "its Codex thread was refused with Bad Request: taking it up again from its rollout", fields={ "thread": jstr(id) })
  guard a.agent is Some(_) else { return }
  let agent = a.agent
  self.set_agent(a, None)
  self.end_process(a, agent)
  self.notify_store(a)
}

///|
async fn Actors::begin_turn(self : Actors, a : Actor, kind : String, by : Json, passive? : Bool = false, fresh? : Bool = false) -> Unit raise {
  a.queued_retry = None
  self.cancel_tools_retry(a)
  if fresh || kind == "input" || kind == "job" {
    a.last_said = ""
    a.posted = false
  }
  let id = str_of(Some(self.rpc(a.key, "node.uuid", []))).unwrap_or("")
  let asked_before = if kind == "job" { self.asked_now(a) } else { None }
  let is_passive = passive || kind == "title" || kind == "nudge"
  a.turn = Some({ id, declared: None, auth_retried: kind == "auth_retry", codex_retried: kind == "codex_retry", passive: is_passive, by, asked_before })
  a.deferred_end = None
  a.warm = false
  a.phase = "running"
  a.waiting = None
  self.mirror(a)
  let for_ = match by {
    Object(o) => {
      let o = Map::from_iter(o.iter())
      o["profile"] = a.profile
      Json::object(o)
    }
    _ => by
  }
  ignore(self.store(a, "startTurnFor", [jstr(id), jstr(a.key), jstr(kind), for_]))
  self.set_running(a, true)
}

///|
/// actor.ts `catchUp`.
async fn Actors::catch_up(self : Actors, a : Actor, end : Bool) -> Unit raise {
  while a.stale && !self.busy(a) {
    guard a.agent is Some(agent) else { return }
    let seq = a.change_seq
    let restart = a.restart
    // (taken in place where it can be: Node's, its profile asked of the pool, `retune`)
    let identity = self.rpc(a.key, "node.retune", [jnum(agent.handle.to_double()), a.profile, jbool(restart), jbool(self.holding(a))])
    if !still(a, Some(agent)) {
      return
    }
    if identity is Object(_) {
      a.running_identity = identity
      self.mirror(a)
      self.log(a, "info", "session process takes the change in place", fields={ "model": identity.value("model").unwrap_or(jstr("")), "effort": identity.value("effort").unwrap_or(jstr("")) })
      if a.change_seq == seq {
        a.stale = false
        a.restart = false
        return
      }
      // (changed again while it took this one: taken as it is now)
      a.stale = true
      a.restart = a.restart_seq > seq
      continue
    }
    // (begun a turn of its own meanwhile: never ended under it, taken at that turn's end)
    if !end || self.busy(a) {
      return
    }
    // (its process ends: the next is opened as the session is then)
    a.stale = false
    a.restart = false
    let background = self.agent_do(a, agent, "background", [])
    self.set_agent(a, None)
    self.log(a, "info", "ending the process from before the session was changed", fields={ "background": jnum(match background { Array(b) => b.length().to_double(); _ => 0.0 }) })
    self.end_process(a, Some(agent))
    self.notify_store(a)
    return
  }
}

///|
async fn Actors::end_process(self : Actors, a : Actor, agent : Agent?) -> Unit raise {
  guard agent is Some(g) else { return }
  match self.agent_do(a, g, "background", []) {
    Array(tasks) => a.stopped.append(tasks)
    _ => ()
  }
  ignore(self.agent_do(a, g, "dispose", []))
}

///|
/// How long its runtime session's process may take to open (`node.open`) before it is given up: one that never answered
/// held its session's queue, and the stop behind it, for hours (FB-34). As long as own-process.ts `ANSWER_MS`.
let open_timeout_ms : Double = 120000.0

///|
/// Why opening its runtime session was given up by a stop, a suspension or a close (`abort_open`): "stopped",
/// "suspended" or "closed"; none for any other failure.
fn open_abort_reason(e : Error) -> String? {
  match e {
    Asked(j) => str_of(j.value("openAbort"))
    _ => None
  }
}

///|
/// Gives up at once the opening of its runtime session its queue waits on (`rpc_open`), as `why`, and has Node give it
/// up too (mb-actor.ts `cancelOpen`: a process that comes of it later is ended there). Whether one was waiting.
fn Actors::abort_open(self : Actors, a : Actor, why : String) -> Bool {
  guard a.opening_rpc is Some(id) else { return false }
  a.opening_rpc = None
  if !self.cancel_rpc(id, { "openAbort": jstr(why), "message": jstr("open " + why) }) {
    return false
  }
  self.log(a, "info", "opening its runtime given up", fields={ "why": jstr(why) })
  self.tell(a.key, "node.cancelOpen", [jnum(id.to_double())])
  true
}

///|
/// Asks Node to open its runtime session (`node.open` with `args`, and the ask's number for Node to give it up by),
/// waiting at most `open_timeout_ms`, and no longer than a stop, a suspension or a close (`abort_open`).
async fn Actors::rpc_open(self : Actors, a : Actor, args : Array[Json]) -> Json raise {
  self.next += 1
  let id = self.next
  let d : @effect.Deferred[Json] = @effect.Deferred::new()
  self.asked[id] = d
  a.opening_rpc = Some(id)
  // timer: a deadline for its runtime's process to open, which may never answer (FB-34)
  let cancel_timer = self.after(open_timeout_ms, () => if self.cancel_rpc(id, { "openTimeout": Json::boolean(true), "message": jstr("agent startup timed out") }) {
    if a.opening_rpc == Some(id) {
      a.opening_rpc = None
    }
    self.tell(a.key, "node.cancelOpen", [jnum(id.to_double())])
  })
  defer {
    cancel_timer()
    if a.opening_rpc == Some(id) {
      a.opening_rpc = None
    }
  }
  self.mirror(a)
  self.active -= 1
  self.say_node({ "rpc": jnum(id.to_double()), "actor": jstr(a.key), "fn": jstr("node.open"), "args": Json::array(args + [jnum(id.to_double())]) })
  // (counted again as its answer comes, `heard`, or as it is given up, `cancel_rpc`)
  let answer = d.wait()
  match answer {
    { "error": err, .. } => {
      if err.value("openTimeout") is Some(True) {
        self.log(a, "warn", "agent startup timed out", fields={ "ms": jnum(open_timeout_ms) })
        raise Asked({ "message": jstr(self.t(a, "station.notice.openTimedOut")), "said": Json::boolean(true) })
      }
      raise Asked(err)
    }
    _ => answer.value("value").unwrap_or(Json::null())
  }
}

///|
/// At most this many profiles a turn goes on to after each refused it (`auth_tried`): a pool of any size is tried
/// through, never round and round.
const AUTH_TRIED_MOST : Int = 16

///|
/// The profiles `a`'s turn was refused on, as Node takes them (sessions/accounts.ts `canAuthRetry`'s `tried`).
fn auth_tried_json(a : Actor) -> Json {
  Json::array(a.auth_tried.map(jstr))
}

///|
/// `ensure_agent`, going on on another profile where its process could not open as the login of the one it was to
/// open on is over (Node's `auth`: a borrowed profile whose host said so, share/index.ts LOGIN_OVER, FB-44): that one
/// rechecked (passed over from then on) and the next the pool gives opened, each once, till none is left. Any other
/// failure to open is as before.
async fn Actors::open_over(self : Actors, a : Actor, passive : Bool) -> Agent raise {
  while true {
    let opened : Agent? = try {
      Some(self.ensure_agent(a))
    } catch {
      // (a start given up by a stop, a suspension or a close goes as it is: `open_abort_reason`)
      Asked(j) as e if !passive && j.value("auth") is Some(True) && open_abort_reason(e) is None => {
        let id = match str_of(j.value("authProfile")) {
          Some(p) if p != "" => p
          _ =>
            match a.profile {
              String(p) if p != "" => p
              _ => raise e
            }
        }
        if a.auth_tried.length() >= AUTH_TRIED_MOST {
          raise e
        }
        let already = a.auth_tried.contains(id)
        ignore(self.deps(a, "recheck", [jstr(id), jbool(already)]))
        let retry = !(self.deps(a, "canAuthRetry", [jstr(a.key), jstr(id), auth_tried_json(a)]) is False)
        if !already {
          a.auth_tried.push(id)
        }
        if !retry {
          a.auth_tried = []
          raise e
        }
        self.log(a, "info", "its login is over where it was to open; going on on another profile", fields={ "profile": jstr(id), "error": j.value("message").unwrap_or(jstr("")) })
        None
      }
      e => raise e
    }
    if opened is Some(g) {
      return g
    }
  }
  abort("unreachable")
}

///|
/// actor.ts `ensureAgent`: its runtime session, opened (Node's: the driver, its options, the words it is told of how it
/// was opened) where it has none.
async fn Actors::ensure_agent(self : Actors, a : Actor) -> Agent raise {
  while true {
    if a.agent is Some(g) && !a.stale && !self.busy(a) {
      let on = self.rpc(a.key, "node.profileId", [jbool(self.holding(a)), jbool(a.force_session_cap)]) catch {
        e => {
          if session_cap_info(e) is Some(_) {
            raise e
          }
          Json::null()
        }
      }
      if !(on is Null) && on != a.profile {
        a.stale = true
      }
      // (its process can no longer take a turn as it is: an Antigravity CLI one whose borrowed sign-in runs out, runtime.ts
      // `outlived`; its retune refuses, so it is opened again)
      if !a.stale {
        let outlived = self.rpc(a.key, "node.outlived", [jnum(g.handle.to_double())]) catch { _ => Json::null() }
        if outlived is True {
          a.stale = true
        }
      }
    }
    self.catch_up(a, true)
    if a.agent is Some(g) {
      a.force_session_cap = false
      a.paused_cap = false
      a.cap_wait_notified = false
      return g
    }
    // (what it is changed in while it opens is taken once it is open: `changed` counts it with no process to mark)
    let seq = a.change_seq
    let opened = self.rpc_open(a, [Json::array(a.stopped), jbool(a.read_back), a.profile, jbool(a.force_session_cap)])
    a.force_session_cap = false
    a.paused_cap = false
    a.cap_wait_notified = false
    let handle = num_of(opened.value("handle")).unwrap_or(0.0).to_int()
    let generation = num_of(opened.value("generation")).unwrap_or(0.0).to_int()
    a.runtime = str_of(opened.value("runtime")).unwrap_or(a.runtime)
    match str_of(opened.value("afresh")) {
      Some(s) => a.afresh = Some(s)
      None => ()
    }
    if opened.value("resumeLost") is Some(True) {
      a.resume_lost = true
    }
    if opened.value("readBackTold") is Some(True) {
      a.read_back = false
    }
    a.stopped.clear()
    if str_of(opened.value("stoppedNote")) is Some(note) {
      a.stopped_note = Some(note)
    }
    let g = { generation, handle }
    self.set_agent(a, Some(g))
    a.running_identity = opened.value("identity").unwrap_or(Json::null())
    a.profile = opened.value("profile").unwrap_or(Json::null())
    if a.change_seq == seq {
      a.stale = false
      a.restart = false
      self.mirror(a)
      return g
    }
    // (opened as it was before a change told meanwhile: taken in place, or ended and opened again, before it is used)
    a.stale = true
    a.restart = a.restart_seq > seq
    self.mirror(a)
  }
  abort("unreachable")
}

///|
fn Actors::is_current(self : Actors, a : Actor, generation : Int) -> Bool {
  ignore(self)
  a.agent.map(g => g.generation) == Some(generation)
}

///|
/// A runtime session's event (actor.ts `onEvent`), as Node gives it: `read`, for a turn's end, what its live view reads
/// of it first, started there as it came.
async fn Actors::on_event(self : Actors, a : Actor, generation : Int, event : Json, read : Json) -> Unit {
  match str_of(event.value("type")).unwrap_or("") {
    "turnStarted" =>
      ignore(
        self.enqueue(a, async fn() {
          if !self.is_current(a, generation) || a.turn is Some(_) || a.compacting {
            return
          }
          self.begin_turn(a, "input", turn_for_nobody())
          if a.working_for.length() == 0 && a.steered_for.length() > 0 {
            a.working_for = a.steered_for.map(w => { ..w, first_ts: w.ts, since: self.now })
            a.steered_for = []
            self.say(a, jstr("thinking"))
          }
        }),
      )
    "turnEnded" => {
      self.done_working(a)
      let outcome = event.value("outcome").unwrap_or(Json::null())
      ignore(
        self.enqueue(a, async fn() {
          match read {
            { "live": Number(n, ..), .. } => self.live_ended(n.to_int())
            _ => ignore(self.rpc(a.key, "node.read", [read]))
          }
          self.on_turn_ended(a, generation, outcome)
        }),
      )
    }
    "live" => {
      let ev = event.value("event").unwrap_or(Json::null())
      if str_of(ev.value("kind")) == Some("phase") && str_of(ev.value("phase")) == Some("requesting") {
        if a.unread.length() > 0 {
          ignore(self.enqueue(a, async fn() { self.undeclare(a) }))
        }
        a.unread = []
      }
      if self.is_current(a, generation) {
        self.hear_words(a, ev)
      }
      self.on_live(a, ev)
    }
    "toolsLost" => {
      let why = str_of(event.value("why")).unwrap_or("")
      ignore(
        self.enqueue(a, async fn() {
          if !self.is_current(a, generation) || a.tools_lost is Some(_) {
            return
          }
          self.log(a, "warn", "the agent cannot reach the station's tools", fields={ "why": jstr(why) })
          a.tools_lost = Some(why)
        }),
      )
    }
    "compacted" => ignore(self.enqueue(a, async fn() { self.on_compacted(a, generation) }))
    "closed" => {
      let why = event.value("why").unwrap_or(Json::null())
      ignore(
        self.enqueue(a, async fn() {
          if !self.is_current(a, generation) {
            return
          }
          self.log(a, "info", "session runtime closed", fields={ "reason": why })
          if a.compacting {
            a.compacting = false
            self.set_running(a, false)
          }
          let gone = match a.agent {
            Some(g) =>
              match self.agent_do(a, g, "background", []) {
                Array(b) => b
                _ => []
              }
            None => []
          }
          a.stopped.append(gone)
          self.set_agent(a, None)
          self.notify_store(a)
          if gone.length() > 0 && a.phase == "waiting" && !self.held(a) {
            self.log(a, "info", "its background work ended with its process while it waits; going on now", fields={ "stopped": jnum(gone.length().to_double()) })
            self.start_turn(a, "resume", self.words(a, "BACKGROUND_STOPPED_WAITING"), fresh=true)
          }
        }),
      )
    }
    _ => ()
  }
}

///|
async fn Actors::on_compacted(self : Actors, a : Actor, generation : Int) -> Unit raise {
  if !self.is_current(a, generation) {
    return
  }
  // (counted for its card, on its own or by hand: store.ts `noteCompacted`)
  ignore(self.store(a, "noteCompacted", [jstr(a.key)]))
  if !a.compacting && self.busy_agent(a) is Some(agent) {
    match self.deps(a, "longChat", [jstr(a.key)]) {
      String(long) => {
        let at = str_of(Some(self.deps(a, "nextTs", []))).unwrap_or("")
        let told = self.timed(a, "<message via=\"station\" from=\"station\" ts=\"\{at}\">\n\{long}\n</message>")
        if truthy(self.agent_do(a, agent, "steer", [jstr(told)])) {
          return
        }
      }
      _ => return
    }
  }
  a.compacted_untold = true
}

///|
/// The agent's own words as they come (not a subagent's, not its thinking).
fn Actors::hear_words(self : Actors, a : Actor, event : Json) -> Unit {
  ignore(self)
  let kind = str_of(event.value("kind")).unwrap_or("")
  if kind == "start" && str_of(event.value("step")) == Some("text") && !(event.value("subagent") is Some(True)) && event.value("parent") is None {
    a.saying = Some((str_of(event.value("id")).unwrap_or(""), ""))
  } else if kind == "delta" && str_of(event.value("field")) == Some("text") {
    match a.saying {
      Some((id, text)) if str_of(event.value("id")) == Some(id) => {
        let text = text + str_of(event.value("text")).unwrap_or("")
        a.saying = Some((id, text))
        let trimmed = text.trim_space().to_string()
        if trimmed != "" {
          a.last_said = trimmed
        }
      }
      _ => ()
    }
  }
}

///|
/// actor.ts `onTurnEnded`.
async fn Actors::on_turn_ended(self : Actors, a : Actor, generation : Int, outcome : Json) -> Unit raise {
  if !self.is_current(a, generation) {
    return
  }
  if a.compacting && a.turn is None {
    return self.compacted(a, outcome)
  }
  let mut kind = str_of(outcome.value("kind")).unwrap_or("")
  let mut reason = str_of(outcome.value("reason")).unwrap_or("")
  let message = str_of(outcome.value("message")).unwrap_or("")
  let mut lent_expired = false
  // (its sign-in run out under it, not refused: nothing to recheck)
  let mut ran_out = false
  if a.runtime == "agy" && kind == "failed" && a.agent is Some(g) {
    // (agy 1.5.8 says only `⚠ Agent execution terminated due to error.` (`other`) when its borrowed sign-in runs out
    // under a turn, 2026-11-16: where the process's sign-in has expired, take it as `auth` so `auth_retry` reopens on
    // one lent anew and goes on)
    if reason == "other" && message.to_lower().contains("agent execution terminated due to error") {
      if truthy(self.agent_do(a, g, "signInExpired", []) catch { _ => Json::null() }) {
        reason = "auth"
        ran_out = true
      }
      if !self.is_current(a, generation) {
        return
      }
    }
    // (a long-running turn on a borrowed agy sign-in outlives multiple 1-hour access tokens: if this `auth_retry`
    // turn ran on a valid borrowed token until it naturally expired, reopen on one lent anew again)
    if reason == "auth" && a.turn is Some({ auth_retried: true, .. }) {
      lent_expired = truthy(self.agent_do(a, g, "lentExpired", []) catch { _ => Json::null() })
      if !self.is_current(a, generation) {
        return
      }
    }
  }
  // (undefined: none shown; null: the account's; a name: that model's own)
  let mut limit : Json? = None
  if kind == "failed" && reason == "model" && a.turn is Some(_) && !(a.profile is Null) && !a.stop_requested {
    let after = self.rpc(a.key, "node.limitAfter", [a.profile]) catch { _ => Json::null() }
    if after is Object(o) && o.get("limit") is Some(l) {
      limit = Some(l)
    }
    if !self.is_current(a, generation) {
      return
    }
    if limit is Some(l) {
      self.log(a, "info", "a failure its words did not name is where the allowance shows a limit", fields={ "model": if l is Null { jstr("") } else { l } })
    }
  }
  self.idle_now(a)
  let turn = a.turn
  a.turn = None
  if kind == "completed" && !a.stop_requested && turn is Some({ declared: None, .. }) {
    a.warm = true
  }
  let had_turn = turn is Some(_)
  if had_turn {
    a.starting_turn = true
  }
  defer {
    if a.warm && a.deferred_end is None {
      a.warm = false
      self.mirror(a)
    }
    if had_turn {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue()
      }
    }
  }
  a.phase = "idle"
  // (a thread taken up again that ends otherwise than refused so is one that works: refused later, it is taken up
  // again first, `refused_thread`)
  if !(a.runtime == "codex" && kind == "failed" && reason == "model" && limit is None && bare_bad_request(message)) {
    a.codex_reloaded = None
  }
  let stop_requested = a.stop_requested
  a.stop_requested = false
  // (a chain of `auth_retry` turns goes on only while each is refused so)
  let refused = kind == "failed" && reason == "auth" && !stop_requested && turn is Some({ declared: None, .. })
  if !refused {
    a.auth_tried = []
  }
  // A turn that already declared its end state (all_done, need_human, waiting) only needed the runtime's trailing LLM
  // call to emit unread closing text. If that call fails with auth (an hourly borrowed token expiring right after
  // chat_state returned), close the stale process so the next turn opens fresh, keep the declared state (its waiting
  // timer too), and post no false auth error. A bad account still fails on the next turn, which declared nothing yet.
  if kind == "failed" && reason == "auth" && !stop_requested && turn is Some({ declared: Some(_), .. }) {
    if a.agent is Some(_) {
      let agent = a.agent
      self.set_agent(a, None)
      self.end_process(a, agent)
      self.notify_store(a)
    }
    self.log(a, "info", "trailing auth failure after the turn declared its state; closing the stale process and keeping the state", fields={ "runtime": jstr(a.runtime) })
    kind = "completed"
  }
  // How a turn that said no state ends (2026-11-16, the status refactor): one that posted a card still waiting ends
  // need_human on it; one that posted, asked once again, ends all_done (no ⚠️ after an answer given). And a turn its
  // background work woke, that only waits on, asks what the turn before it asked, while no person has spoken or decided
  // since (`asked_before`, `node.keepAsk`): the work's report does not take the question away.
  let mut kept_wait : Double? = None
  if kind == "completed" && turn is Some(t) && !stop_requested {
    if t.declared is None && a.posted {
      let started = self.last_turn(a).value("startedAt").unwrap_or(Json::null())
      let most = num_of(Some(self.deps(a, "maxNudges", []))).unwrap_or(0.0).to_int()
      if truthy(self.rpc(a.key, "node.cardAsks", [jstr(t.id), started])) {
        t.declared = Some({ "kind": "need_help" })
        self.log(a, "info", "the turn ended with no state on a card it posted, still waiting: it ends needing a person")
      } else if a.nudges >= (if most < 1 { most } else { 1 }) {
        t.declared = Some({ "kind": "all_done" })
        self.log(a, "info", "the turn posted and said no state, asked again: it ends done")
      }
    }
    if kind_of(t.declared) == Some("waiting") && t.asked_before is Some(before) && a.steered.length() == 0 {
      let seconds = num_of(t.declared.unwrap().value("seconds")).unwrap_or(0.0)
      if truthy(self.rpc(a.key, "node.keepAsk", [jstr(t.id), before])) {
        t.declared = Some({ "kind": "need_help" })
        kept_wait = Some(seconds)
        self.log(a, "info", "woken by its background work, it waits on: what it asked before still stands")
      }
    }
  }
  // (one that ends with no state is asked again at once: it stays running till then, never shown stopped meanwhile;
  // one asked as often as it may be ends here, stopped at once)
  let warm = kind == "completed" && !stop_requested && turn is Some({ declared: None, .. }) &&
    a.nudges < num_of(Some(self.deps(a, "maxNudges", []))).unwrap_or(0.0).to_int()
  if warm {
    a.warm = true
  } else {
    a.warm = false
    self.set_running(a, false)
  }
  let overloaded = turn is Some(_) && kind == "failed" && reason == "overloaded" && !stop_requested
  let retry : Json? = if overloaded {
    let n = a.overloads
    a.overloads += 1
    Some({ "kind": "waiting", "seconds": jnum(retry_after(n)) })
  } else {
    None
  }
  if !overloaded {
    a.overloads = 0
  }
  let ends = match retry {
    Some(_) => retry
    None =>
      match turn {
        Some(t) => ended_in(t.declared, kind)
        None => None
      }
  }
  let recorded = turn.map(t => t.id)
  if turn is Some(t) {
    let detail = if kind != "failed" {
      Json::null()
    } else {
      match limit {
        Some(l) => jstr("limit:" + (match l { String(s) => s; _ => "" }) + ": " + message)
        None => jstr(reason + ": " + message)
      }
    }
    let ends_kind = match kind_of(ends) { Some(k) => jstr(k); None => Json::null() }
    let wait = if kind_of(ends) == Some("waiting") { ends.unwrap().value("seconds").unwrap_or(Json::null()) } else { Json::null() }
    ignore(self.store(a, "endTurn", [jstr(t.id), jstr(kind), detail, ends_kind, wait]))
    if retry is Some(_) {
      ignore(self.store(a, "setWaitFor", [jstr(t.id), jstr(self.t(a, "station.wait.overloaded")), jbool(false)]))
    }
  }
  // (a turn that said nothing, its process never having reached the station's tools at all: Antigravity CLI tells
  // nothing of an MCP server it could not connect, so no call of one failed; Node keeps what its token made, `toolsUnheard`)
  let mut unheard_tools = false
  if a.tools_lost is None && kind == "completed" && !stop_requested && !a.posted && turn is Some({ declared: None, .. }) &&
    a.agent is Some(g) {
    let unheard = self.rpc(a.key, "node.toolsUnheard", [jnum(g.handle.to_double()), jbool(a.nudges > 0)]) catch {
      e => {
        self.log(a, "warn", "toolsUnheard check failed", fields={ "error": jstr(e.to_string()) })
        Json::null()
      }
    }
    match unheard {
      String(why) => {
        self.log(a, "warn", "the agent cannot reach the station's tools", fields={ "why": jstr(why) })
        a.tools_lost = Some(why)
        unheard_tools = true
      }
      _ => ()
    }
  }
  let lost = a.tools_lost
  a.tools_lost = None
  if lost is Some(why) {
    let agent = a.agent
    self.set_agent(a, None)
    self.log(a, "warn", "ending the process that lost the station's tools; the next one resumes it", fields={ "why": jstr(why) })
    self.end_process(a, agent)
    self.notify_store(a)
  }
  if turn is Some({ declared: Some(_), .. }) {
    a.tools_restarts = 0
  }
  let too_old = a.runtime == "codex" && kind == "failed" && self.rpc(a.key, "node.words", [jstr("codexTooOld"), jstr(message)]) is True
  if too_old && !stop_requested && !self.held(a) && turn is Some(t) && !t.codex_retried && t.declared is None &&
    self.rpc(a.key, "node.canUpdateCodex", []) is True {
    let agent = a.agent
    a.codex_next += 1
    let update : CodexUpdate = { id: a.codex_next, by: t.by, finished: false, turn: t.id }
    a.codex_update = Some(update)
    self.set_agent(a, None)
    a.nudges = 0
    self.notice(a, self.t(a, "station.notice.codexUpdating"), about=Some(t.id))
    // (its version, and whether it updates where the station's is, asked of it before it ends)
    let handle = match agent { Some(g) => jnum(g.handle.to_double()); None => Json::null() }
    ignore(self.rpc(a.key, "node.codexBefore", [handle, jnum(update.id.to_double())]))
    self.end_process(a, agent)
    self.set_running(a, true)
    // (not holding the queue during the install: Node updates it, and tells its end as `codexUpdated`)
    ignore(self.rpc(a.key, "node.updateCodex", [jnum(update.id.to_double())]))
    return
  }
  // (refused on its profile, any runtime's: rechecked at once, so the pool passes over one whose login is over, a
  // borrowed one's too, before the next is picked, FB-44; one refused again after it was rechecked and tried again in
  // this chain is taken as over, `force`. A sign-in that only ran out is not rechecked.)
  let refused_on = match a.profile {
    String(p) if p != "" && refused && !lent_expired && !ran_out => Some(p)
    _ => None
  }
  let tried_before = auth_tried_json(a)
  if refused_on is Some(p) {
    ignore(self.deps(a, "recheck", [jstr(p), jbool(a.auth_tried.contains(p))]))
  }
  // (agy: session/load answers without checking the CLI's conversation database, and a prompt on a conversation whose
  // database is absent or corrupt fails with "trajectory not found"; end the broken process so no retry hits it again,
  // and reopen once in a new conversation that reads back, 2026-11-16)
  if a.runtime == "agy" && kind == "failed" && message.to_lower().contains("trajectory not found") {
    let agent = a.agent
    self.set_agent(a, None)
    self.end_process(a, agent)
    self.notify_store(a)
    if !stop_requested && !self.held(a) && turn is Some(t) && !t.auth_retried && t.declared is None {
      a.nudges = 0
      self.log(a, "warn", "Antigravity trajectory missing; reopening in a new runtime session", fields={ "error": jstr(message) })
      self.start_turn(a, "auth_retry", a.turn_text, by=t.by)
      if a.turn is Some(nt) && t.codex_retried {
        nt.codex_retried = true
      }
      return
    }
  }
  // (agy: a sign-in lent by another station runs out under a process that never reads it again; a new one opens on
  // one lent anew, agents/agy.ts AGY_LENT_RENEW_MS)
  // (each profile it is refused on rechecked and left for the next the pool gives, till none is left: never round and
  // round, `AUTH_TRIED_MOST`)
  if refused && !self.held(a) && turn is Some(t) && (!t.passive || lent_expired) &&
    (lent_expired || ran_out || !t.auth_retried || refused_on is Some(_)) && a.auth_tried.length() < AUTH_TRIED_MOST {
    let agent = a.agent
    self.set_agent(a, None)
    self.end_process(a, agent)
    let allow_retry = match refused_on {
      Some(p) => {
        let can = !(self.deps(a, "canAuthRetry", [jstr(a.key), jstr(p), tried_before]) is False)
        if !a.auth_tried.contains(p) {
          a.auth_tried.push(p)
        }
        can
      }
      None => lent_expired || ran_out || !t.auth_retried
    }
    if !allow_retry {
      a.auth_tried = []
      self.notify_store(a)
      self.log(a, "info", "authentication failed; profile unusable and no healthy fallback, waiting for user", fields={ "runtime": jstr(a.runtime) })
    } else {
      a.nudges = 0
      self.log(a, "info", "authentication failed; reopening and continuing", fields={ "runtime": jstr(a.runtime), "tried": auth_tried_json(a) })
      let text = self.words(a, "GO_ON_AFTER_AUTH")
      if self.max_concurrent_turns > 0 && self.active_turn_slots() > self.max_concurrent_turns {
        a.queued_retry = Some({ kind: "auth_retry", text, by: t.by, codex_retried: t.codex_retried })
        self.enqueue_turn_wait(a)
        return
      }
      self.start_turn(a, "auth_retry", text, by=t.by)
      if a.turn is Some(nt) && t.codex_retried {
        nt.codex_retried = true
      }
      return
    }
  }
  if a.runtime == "agy" && kind == "failed" && reason == "auth" && a.agent is Some(_) {
    let agent = a.agent
    self.set_agent(a, None)
    self.end_process(a, agent)
    self.notify_store(a)
  }
  let spent = kind == "failed" && reason == "rate_limit"
  if !spent {
    a.refill = None
  }
  if spent {
    a.nudges = 0
    let model = self.rpc(a.key, "node.words", [jstr("modelLimitOf"), jstr(message)])
    let moved = self.deps(a, "spend", [jstr(a.key), a.profile, model]) catch {
      e => {
        self.log(a, "warn", "could not move off a spent profile", fields={ "error": jstr(e.to_string()) })
        Json::null()
      }
    }
    if moved is Array(m) {
      let agent = a.agent
      self.set_agent(a, None)
      self.end_process(a, agent)
      self.log(a, "info", "allowance ran out; going on on another profile", fields={ "from": m[0], "to": m[1] })
      a.refill = None
      if self.max_concurrent_turns > 0 && self.active_turn_slots() > self.max_concurrent_turns {
        if !self.has_pending(a) {
          a.queued_retry = Some({ kind: "resume", text: self.words(a, "GO_ON_AFTER_SPENT"), by: turn_for_nobody(), codex_retried: false })
        }
        self.enqueue_turn_wait(a)
        return
      }
      if self.has_pending(a) {
        return self.pump(a)
      }
      return self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_SPENT"))
    }
    if moved is Object(o) && str_of(o.get("paused")) == Some("session_cap") {
      let agent = a.agent
      self.set_agent(a, None)
      self.end_process(a, agent)
      a.refill = None
      a.queued_retry = Some({ kind: "resume", text: self.words(a, "GO_ON_AFTER_SPENT"), by: turn_for_nobody(), codex_retried: false })
      self.pause_for_session_cap(
        a,
        str_of(o.get("profile")).unwrap_or(""),
        num_of(o.get("active")).unwrap_or(0.0).to_int(),
        num_of(o.get("cap")).unwrap_or(0.0).to_int(),
        o.get("protection") is Some(True),
        "resume",
        turn_for_nobody(),
        None,
      )
      return
    }
    let notice = self.failure_notice(a, outcome)
    let spent_before = match self.rpc(a.key, "node.words", [jstr("spentBefore")]) {
      Array(s) => s.filter_map(x => str_of(Some(x)))
      _ => []
    }
    let head = match notice.split("\n\n").next() { Some(h) => h.to_string(); None => notice }
    let starts = [head] + spent_before
    let said = self.said_last(a)
    if !(said is Some(s) && starts.iter().any(p => s.has_prefix(p))) {
      self.notice(a, notice, profile=a.profile, about=recorded)
    } else if turn is Some(t) {
      let latest = self.store(a, "latestThread", [jstr(a.key)])
      if latest.value("thread") is Some(thread) {
        let tid = thread.value("id").unwrap_or(Json::null())
        match self.store(a, "entriesBefore", [tid, Json::null(), jnum(1.0)]) {
          Array(rows) if rows.length() > 0 => {
            let last = rows[rows.length() - 1]
            ignore(self.store(a, "setAbout", [jstr(t.id), [tid, last.value("n").unwrap_or(Json::null()), last.value("ts").unwrap_or(Json::null())]]))
            self.notify_store(a)
          }
          _ => ()
        }
      }
    }
    self.await_refill(a, self.refills_at(a))
  } else if overloaded {
    a.nudges = 0
    let about = self.last_turn(a).value("about")
    let latest = self.store(a, "latestThread", [jstr(a.key)])
    let notice = "⚠️ " + self.t(a, "station.notice.overloaded")
    let same = match (about, latest.value("thread")) {
      (Some(Object(ab)), Some(thread)) => {
        let tid = thread.value("id").unwrap_or(Json::null())
        match self.store(a, "entriesBefore", [tid, Json::null(), jnum(1.0)]) {
          Array(rows) if rows.length() > 0 => {
            let last = rows[rows.length() - 1]
            ab.get("thread") == Some(tid) && ab.get("seq") == last.value("n") && ab.get("ts") == last.value("ts") &&
            str_of(last.value("text")) == Some(notice)
          }
          _ => false
        }
      }
      _ => false
    }
    if !same {
      self.notice(a, notice, about=recorded, quiet=true)
    }
    self.notify_store(a)
  } else if kind == "failed" {
    a.nudges = 0
    let said = match limit {
      Some(l) =>
        str_of(Some(self.rpc(a.key, "node.words", [jstr("limitShownNotice"), l, jstr(message)]))).unwrap_or("")
      None =>
        if a.runtime == "codex" && turn is Some({ codex_retried: true, .. }) && too_old {
          str_of(Some(self.rpc(a.key, "node.words", [jstr("codexStillOld"), jstr(message)]))).unwrap_or("")
        } else {
          self.failure_notice(a, outcome)
        }
    }
    self.notice(a, said, profile=if reason == "auth" || reason == "refused" { a.profile } else { Json::null() }, about=recorded)
  } else if kind == "aborted" {
    a.nudges = 0
    if stop_requested {
      self.stop_background(a)
      self.notice(a, self.t(a, "station.notice.stopped"))
    }
  }
  if turn is Some(t) {
    let ended = match kind_of(t.declared) {
      Some("all_done") => Some("all_done")
      Some("need_help") => Some("need_human")
      _ =>
        if retry is Some(_) {
          None
        } else if kind == "failed" {
          Some("failed")
        } else if kind == "aborted" && stop_requested {
          Some("stopped")
        } else {
          None
        }
    }
    let words = if ended == Some("failed") {
      jstr(message)
    } else {
      self.last_turn(a).value("need").unwrap_or(Json::null())
    }
    let stands : Json = match ended {
      Some("all_done") => { "kind": "done", "words": words }
      Some("need_human") => { "kind": "need", "words": words }
      _ => Json::null()
    }
    for w in a.ended_for {
      let left = self.store(a, "leftThread", [jstr(a.key), jstr(w.connect), jstr(w.channel), jstr(w.thread_ts)]) catch { _ => Json::null() }
      self.tell(a.key, "chat.standsAt", [jstr(w.connect), jstr(w.channel), jstr(w.thread_ts), if left is True { { "kind": "left", "words": Json::null() } } else { stands }])
    }
    if ended is Some(e) && kept_wait is None {
      ignore(self.deps(a, "settled", [jstr(a.key), jstr(e), words])) catch {
        err => self.log(a, "warn", "the opener of its chat was not told", fields={ "error": jstr(err.to_string()) })
      }
    }
  }
  if self.archived(a) {
    a.deferred_end = None
    self.cool(a, warm)
    self.let_go(a)
    ignore(self.deps(a, "idle", [jstr(a.key)]))
    return
  }
  if kind == "completed" && kind_of(ends) != Some("waiting") && self.compacting_to_cap(a) {
    return self.cool(a, warm)
  }
  if self.has_pending(a) {
    self.pump(a)
    return self.cool(a, warm)
  }
  if a.notices.length() > 0 {
    self.give_notices(a)
    return self.cool(a, warm)
  }
  let declared = match turn {
    Some(t) => t.declared
    None => None
  }
  if kind_of(ends) == Some("waiting") {
    a.nudges = 0
    if retry is None && a.stopped.length() > 0 && !self.held(a) {
      self.log(a, "info", "its background work ended with its process while it waits; going on now", fields={ "stopped": jnum(a.stopped.length().to_double()) })
      return self.start_turn(a, "resume", self.words(a, "BACKGROUND_STOPPED_WAITING"), fresh=true)
    }
    self.wait_ms(a, num_of(ends.unwrap().value("seconds")).unwrap_or(0.0), num_of(ends.unwrap().value("seconds")).unwrap_or(0.0) * 1000.0)
    ignore(self.deps(a, "idle", [jstr(a.key)]))
    // (changed while its turn ran: its process takes it now, in place alone while it waits, before a turn of its
    // own posts as it ran before)
    if a.stale {
      self.catch_up(a, a.waiting is None)
    }
    return
  }
  ignore(self.deps(a, "idle", [jstr(a.key)]))
  if kept_wait is Some(seconds) {
    self.wait_ms(a, seconds, seconds * 1000.0)
  }
  if kind != "completed" || declared is Some(_) {
    a.nudges = 0
    let untitled = if kind == "completed" && !self.held(a) { str_of(Some(self.deps(a, "untitled", [jstr(a.key)]))) } else { None }
    if untitled is Some(u) && !a.asked_to_name.contains(u) {
      a.asked_to_name.push(u)
      self.log(a, "info", "its chat has no title; asking it to name it", fields={ "chat": jstr(u) })
      return self.start_turn(a, "title", self.words(a, "nameUntitled", args=[jstr(u)]))
    }
    if a.stale {
      self.catch_up(a, a.waiting is None)
    }
    return
  }
  if self.held(a) {
    a.deferred_end = Some({ lost: lost is Some(_), unheard: unheard_tools, recorded })
    self.mirror(a)
    return
  }
  self.continue_undeclared_end(a, lost is Some(_), unheard_tools, recorded, warm)
}

///|
/// Backoff before the second toolsUnheard restart: outlasts a station handover or load spike longer than agy's 5s MCP preload timeout.
let tools_retry_delay_ms : Double = 5000.0

///|
/// Continues after a turn ended without declaring a state (immediately or once `release` lifts a hold).
async fn Actors::continue_undeclared_end(
  self : Actors,
  a : Actor,
  lost : Bool,
  unheard : Bool,
  recorded : String?,
  warm : Bool,
) -> Unit raise {
  if lost {
    a.nudges = 0
    if a.tools_restarts < 1 {
      a.tools_restarts += 1
      self.log(a, "info", "the turn reached nobody; going on in a new process", fields={ "attempt": jnum(a.tools_restarts.to_double()) })
      self.start_turn(a, "resume", self.words(a, "TOOLS_LOST"))
      return self.cool(a, warm)
    }
    if unheard && a.tools_restarts < 2 {
      a.tools_restarts += 1
      self.log(a, "info", "the turn still reached no tools; retrying in a new process after backoff", fields={ "attempt": jnum(a.tools_restarts.to_double()), "delayMs": jnum(tools_retry_delay_ms) })
      self.schedule_tools_retry(a, tools_retry_delay_ms)
      return self.cool(a, warm)
    }
    a.tools_restarts = 0
    self.cool(a, warm)
    if a.stale {
      self.catch_up(a, a.waiting is None)
    }
    return self.give_up(a, recorded)
  }
  let most = num_of(Some(self.deps(a, "maxNudges", []))).unwrap_or(0.0).to_int()
  if a.nudges < most {
    a.nudges += 1
    self.log(a, "info", "turn ended without a state; nudging", fields={ "attempt": jnum(a.nudges.to_double()) })
    self.start_turn(a, "nudge", self.words(a, "NUDGE"))
    return self.cool(a, warm)
  }
  a.nudges = 0
  self.cool(a, warm)
  if a.stale {
    self.catch_up(a, a.waiting is None)
  }
  self.give_up(a, recorded)
}

///|
/// A turn's end that kept it running (`warm`: it said no state, to be asked again at once) and started nothing after
/// all: stopped now.
async fn Actors::cool(self : Actors, a : Actor, warm : Bool) -> Unit raise {
  if a.warm {
    a.warm = false
    self.mirror(a)
  }
  if warm && a.turn is None && !a.compacting && a.codex_update is None {
    self.set_running(a, false)
  }
}

///|
/// What the session's last turn asked a person and still asks (ended need_human): what a turn its background work woke
/// keeps asking while it waits on (`on_turn_ended`).
async fn Actors::asked_now(self : Actors, a : Actor) -> Json? raise {
  let last = self.last_turn(a)
  guard last is Object(_) && str_of(last.value("ending")) == Some("need_help") && !(last.value("endedAt") is (None | Some(Null))) else {
    return None
  }
  Some(last)
}

///|
async fn Actors::failure_notice(self : Actors, a : Actor, outcome : Json) -> String raise {
  str_of(Some(self.rpc(a.key, "node.words", [jstr("failureNotice"), outcome]))).unwrap_or("")
}

///|
/// The shared Codex update ended (`codexUpdated` from Node): `why`, why it failed.
async fn Actors::codex_updated(self : Actors, a : Actor, id : Int, why : String?) -> Unit raise {
  guard a.codex_update is Some(update) && update.id == id else { return }
  match why {
    None => {
      update.finished = true
      self.continue_after_codex_update(a, update)
    }
    Some(why) => {
      a.codex_update = None
      self.set_running(a, false)
      self.notice(a, "⚠️ " + self.t(a, "station.notice.codexUpdateFailed", args={ "why": jstr(why) }), about=Some(update.turn))
      ignore(self.deps(a, "settled", [jstr(a.key), jstr("failed"), jstr(why)]))
      ignore(self.deps(a, "idle", [jstr(a.key)]))
      if self.has_pending(a) {
        self.pump(a)
      }
    }
  }
}

///|
async fn Actors::continue_after_codex_update(self : Actors, a : Actor, update : CodexUpdate) -> Unit raise {
  guard a.codex_update is Some(u) && u.id == update.id && update.finished && !self.held(a) else { return }
  a.codex_update = None
  self.set_running(a, false)
  if self.archived(a) {
    return
  }
  self.start_turn(a, "codex_retry", self.words(a, "GO_ON_AFTER_CODEX_UPDATE"), by=update.by)
  if self.has_pending(a) {
    self.pump(a)
  } else if a.notices.length() > 0 {
    self.give_notices(a)
  }
}

///|
async fn Actors::give_up(self : Actors, a : Actor, turn : String?) -> Unit raise {
  let said = if a.posted { "" } else { a.last_said }
  a.last_said = ""
  if said == "" {
    return self.notice(a, "⚠️ " + self.t(a, "station.notice.noResult"), about=turn)
  }
  self.log(a, "info", "the turn reached nobody; its last words are shown in its place")
  let quoted = str_of(Some(self.rpc(a.key, "node.words", [jstr("quoted"), jstr(said)]))).unwrap_or("")
  self.notice(a, "⚠️ " + self.t(a, "station.notice.noResultSaid") + "\n\n" + quoted, about=turn)
}

///|
/// Whether it was waiting (on its background work, a refill, or as its last turn said) and was stopped.
async fn Actors::stop_waiting(self : Actors, a : Actor, say? : Bool = true, keep_jobs? : Bool = false) -> Bool raise {
  let refill = a.refill is Some(_)
  let waited = a.waiting is Some(_) || refill
  a.waiting = None
  a.refill = None
  if a.phase == "waiting" {
    a.phase = "idle"
  }
  let last = self.last_turn(a)
  let recorded = !(last is Null) && !(last.value("endedAt") is (None | Some(Null))) && str_of(last.value("declared")) == Some("waiting")
  if !waited && !recorded {
    return false
  }
  self.log(a, "info", "stopped while waiting")
  if !(last is Null) && retrying(last) {
    a.overloads = 0
  } else if !keep_jobs {
    ignore(self.deps(a, "stopJobs", [jstr(a.key)]))
    // (what its jobs told it goes with them, as `stop_background`'s)
    a.notices = []
  }
  a.nudges = 0
  let agent = a.agent
  self.set_agent(a, None)
  if agent is Some(g) {
    ignore(self.agent_do(a, g, "dispose", []))
  }
  ignore(self.store(a, "stopWait", [jstr(a.key), jbool(refill)]))
  if say {
    self.notice(a, self.t(a, "station.notice.stopped"))
  }
  true
}

///|
async fn Actors::stop_background(self : Actors, a : Actor) -> Unit raise {
  let agent = a.agent
  self.set_agent(a, None)
  self.end_process(a, agent)
  ignore(self.deps(a, "stopJobs", [jstr(a.key)]))
  a.notices = []
  self.notify_store(a)
}

///|
async fn Actors::let_go(self : Actors, a : Actor) -> Unit raise {
  a.notices = []
  a.queued_retry = None
  a.deferred_end = None
  a.warm = false
  self.cancel_tools_retry(a)
  self.mirror(a)
  a.nudges = 0
  let waited = a.waiting is Some(_)
  a.waiting = None
  if a.phase == "waiting" {
    a.phase = "idle"
  }
  let last = self.last_turn(a)
  if waited || (!(last is Null) && !(last.value("endedAt") is (None | Some(Null))) && str_of(last.value("declared")) == Some("waiting")) {
    self.log(a, "info", "archived: its wait ends")
    ignore(self.store(a, "stopWait", [jstr(a.key)]))
  }
  ignore(self.deps(a, "endJobs", [jstr(a.key)]))
}

///|
async fn Actors::fire_wait(self : Actors, a : Actor, wait : Int, seconds : Double) -> Unit raise {
  if self.held(a) || a.waiting != Some(wait) {
    return
  }
  if self.archived(a) {
    return self.let_go(a)
  }
  if a.compacting {
    a.over_while_compacting = true
    return
  }
  if self.turn_slots_full(a) {
    a.waiting_until = self.now
    self.enqueue_turn_wait(a)
    return
  }
  let reserved = !a.starting_turn
  if reserved {
    a.starting_turn = true
  }
  defer {
    if reserved {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!a.paused_cap)
      }
    }
  }
  a.waiting = None
  a.phase = "idle"
  let last = self.last_turn(a)
  if !(last is Null) && retrying(last) {
    self.log(a, "info", "trying again a turn the provider had no room for", fields={ "seconds": jnum(seconds) })
    return self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_OVERLOADED"), passive=true)
  }
  if !(last.value("waitWatch") is Some(False)) && truthy(self.store(a, "hasSessionActiveWatch", [jstr(a.key)])) {
    return self.wait_ms(a, seconds, seconds * 1000.0)
  }
  self.log(a, "info", "the wait is over without word; asking again", fields={ "seconds": jnum(seconds) })
  self.start_turn(a, "nudge", self.words(a, "waitOver", args=[jnum(seconds)]), fresh=true)
}

///|
/// Asks the agent again after `seconds` (`ms` of it left), unless a turn has started by then: a wait of Node's clock.
fn Actors::wait_ms(self : Actors, a : Actor, seconds : Double, ms : Double) -> Unit {
  a.waits += 1
  let wait = a.waits
  a.waiting = Some(wait)
  a.phase = "waiting"
  a.waiting_until = self.now + ms
  a.waiting_seconds = seconds
  self.timer(a, "wait", ms, async fn() { self.fire_wait(a, wait, seconds) })
}

///|
/// What the thread people spoke in last ends with, where the station said it (actor.ts `saidLast`).
async fn Actors::said_last(self : Actors, a : Actor) -> String? raise {
  str_of(Some(self.rpc(a.key, "node.saidLast", [])))
}

///|
async fn Actors::fire_refill(self : Actors, a : Actor, refill : Int) -> Unit raise {
  if a.refill != Some(refill) {
    return
  }
  if self.held(a) {
    return
  }
  if self.archived(a) || a.turn is Some(_) || self.busy(a) {
    a.refill = None
    return
  }
  if self.turn_slots_full(a) {
    a.refill_at = self.now
    self.enqueue_turn_wait(a)
    return
  }
  let reserved = !a.starting_turn
  if reserved {
    a.starting_turn = true
  }
  defer {
    if reserved {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!a.paused_cap)
      }
    }
  }
  a.refill = None
  self.log(a, "info", "its allowance should have refilled; going on")
  if self.has_pending(a) {
    return self.pump(a)
  }
  self.start_turn(a, "resume", self.words(a, "GO_ON_AFTER_REFILL"), passive=true)
}

///|
fn Actors::await_refill(self : Actors, a : Actor, at : Double) -> Unit {
  a.refills += 1
  let refill = a.refills
  a.refill = Some(refill)
  a.refill_at = at
  self.timer(a, "refill", at - self.now, async fn() { self.fire_refill(a, refill) })
}

///|
fn Actors::cancel_tools_retry(self : Actors, a : Actor) -> Unit {
  let had = a.tools_retry is Some(_) || a.tools_retry_deferred
  a.tools_retry = None
  a.tools_retry_deferred = false
  if a.timers.get("tools_retry") is Some(cancel) {
    cancel()
    a.timers.remove("tools_retry")
  }
  if had {
    self.mirror(a)
  }
}

///|
fn Actors::schedule_tools_retry(self : Actors, a : Actor, ms : Double) -> Unit {
  a.tools_retries += 1
  let id = a.tools_retries
  a.tools_retry = Some(id)
  a.tools_retry_at = self.now + ms
  a.tools_retry_deferred = false
  self.mirror(a)
  self.timer(a, "tools_retry", ms, async fn() { self.fire_tools_retry(a, id) })
}

///|
async fn Actors::fire_tools_retry(self : Actors, a : Actor, id : Int) -> Unit raise {
  if a.tools_retry != Some(id) {
    return
  }
  a.tools_retry = None
  if self.held(a) {
    a.tools_retry_deferred = true
    self.mirror(a)
    return
  }
  self.mirror(a)
  if self.archived(a) {
    return self.let_go(a)
  }
  if a.turn is Some(_) || self.busy(a) {
    return
  }
  if self.turn_slots_full(a) {
    a.queued_retry = Some({ kind: "resume", text: self.words(a, "TOOLS_LOST"), by: turn_for_nobody(), codex_retried: false })
    self.enqueue_turn_wait(a)
    return
  }
  let reserved = !a.starting_turn
  if reserved {
    a.starting_turn = true
  }
  defer {
    if reserved {
      a.starting_turn = false
      if a.turn is None {
        self.drain_turn_queue(drain_cap=!a.paused_cap)
      }
    }
  }
  self.start_turn(a, "resume", self.words(a, "TOOLS_LOST"))
}

///|
/// A wait of the actor's (`name`: a newer of the same name ends the older's timer, as its number voids it there): at
/// its time, `then` is queued.
fn Actors::timer(self : Actors, a : Actor, name : String, ms : Double, then : async () -> Unit raise) -> Unit {
  if a.timers.get(name) is Some(cancel) {
    cancel()
  }
  let cancel = self.after(ms, () => {
    a.timers.remove(name)
    self.spawn(() => self.enqueue(a, then))
  })
  a.timers[name] = cancel
}

///|
/// The station's own words (not the agent's) in the thread people spoke in last (Node's: actor.ts `notice`); `about`,
/// the turn it is about (its place recorded on it); `quiet`, recorded without its change told.
async fn Actors::notice(
  self : Actors,
  a : Actor,
  text : String,
  profile? : Json = Json::null(),
  runtime? : Json = Json::null(),
  change? : Json = Json::null(),
  about? : String? = None,
  quiet? : Bool = false,
) -> Unit raise {
  ignore(
    self.rpc(a.key, "node.notice", [
      jstr(text),
      profile,
      runtime,
      change,
      match about { Some(t) => jstr(t); None => Json::null() },
      jbool(quiet),
    ]),
  )
}
