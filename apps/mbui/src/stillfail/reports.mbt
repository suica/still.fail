// still.fail's crash reports and timings, as its own Android app sends them (Crashes.kt,
// BarTiming.kt): the host's (android/app/src/main/java/dev/mbui: Crashes.java, BarTiming.java), told here what only
// the app knows: the account signed in (the crashes kept since the last report go as it), the core failing and started
// again (CoreFailed), what the UI could not do as asked (UiFault), the bottom bar's switches (src/sfapp/bar_timing.mbt)
// and the topics their pages subscribe, the window thread's hangs (mbui's src/ui/journal.mbt). iOS's host takes them
// too (src/host/apple_reports.m: MetricKit's crash and hang reports; the bar's timing not), and macOS's (the same file:
// the window thread's hangs and the errors got past, no MetricKit). Where no host takes them (Windows, the web, an
// Apple build without PostHog's key: host_tell answers 0) UiFault and CoreFailed go as the core's `client.error` span.

///|
/// Whether the account signed in was told (once a process, as Android's MainActivity does).
let reported : Ref[Bool] = Ref(false)

///|
/// Which hangs are sent (hang_gate.mbt).
let hang_gate : HangGate = HangGate::new()

///|
/// How long the window thread must have been held by one piece of work for its hang to be kept in this device's log.
let hang_local_ms : Double = 500.0

///|
/// What this device's own hang log keeps of `h` (none: too short): its page, passes, their causes and parts, as the
/// journal says them. Written by the host to a local file and never sent.
fn hang_local_line(h : @ui.Hang) -> String? {
  if h.stall_ms >= hang_local_ms { Some(h.said()) } else { None }
}

///|
fn hang_keep_local(h : @ui.Hang) -> Unit {
  if hang_local_line(h) is Some(line) {
    host_tell("hang_local", line, "", 0, 0) |> ignore
  }
}

///|
/// The subscriptions a switch being timed took on (by their ids), until their first message.
let timed : Map[Int, Bool] = Map([])

///|
/// Whether the host takes `bar_switch` JSON directly from MoonBit's `BarSwitchTracker` (iOS, macOS, Windows, Web),
/// rather than timing switches itself (Android's `BarTiming.java`).
let use_mb_bar : Ref[Bool] = Ref(false)

///|
/// Shared `bar_switch` state machine for hosts where `bar_switch_ready` answers 1.
let bar_tracker : BarSwitchTracker = BarSwitchTracker::new()

///|
fn emit_bar_switch(json : String?) -> Unit {
  match json {
    Some(j) => host_tell("bar_switch", j, "", 0, 0) |> ignore
    None => ()
  }
}

///|
/// Flushes any timed-out `bar_switch` (3000 ms) when MoonBit owns the state machine.
fn report_bar_tick() -> Unit {
  if use_mb_bar.val && bar_tracker.has_pending() {
    emit_bar_switch(bar_tracker.tick(@core.monotonic_ms()))
  }
}

///|
/// The latest core failure not yet told, where no host takes it: kept as the core fails (its core gone), sent to the core
/// started after it (`@core.on_restarted`). Only the latest: a core failing again before one takes calls replaces it.
let pending_core_failed : Ref[String?] = Ref(None)

///|
/// The host's reports set going, before the app's first frame.
fn reports_start() -> Unit {
  // what a call in flight as the core failed says (StillFailCore.restartedText)
  @core.restarted_text.val = @sfapp.tr("android-misc.core.restarted")
  if host_tell("hello", "", "", 0, 0) == 0 {
    // (a build that reports nothing still keeps its long hangs in this device's log)
    @ui.hangs_told(Some(hang_keep_local))
    // (no host's error report: what the UI could not do as asked goes as the core's `client.error` span, to Cloud Trace
    // with the rest of its traces, and to the host's log; a page showing 这部分显示出错了 said nothing otherwise)
    @view.fault_told.val = Some(fn(said) {
      let category = ui_fault_category(said)
      @hostapi.log("ui fault: " + category)
      @core.call("client.error", params={ "source": "ui_fault", "message": category })
    })
    // (the core failing: told to the core started after it, the one failing being gone; the core sends only its first
    // 1000 characters)
    @core.on_failed.val = Some(fn(reason) {
      @hostapi.log("core failed: " + reason)
      pending_core_failed.val = Some(reason)
    })
    @core.on_restarted.val = Some(fn() {
      match pending_core_failed.val {
        Some(reason) => {
          pending_core_failed.val = None
          @core.call("client.error", params={ "source": "core_failed", "message": reason })
        }
        None => ()
      }
    })
    return
  }
  @core.on_failed.val = Some(fn(reason) { host_tell("core_failed", reason, "", 0, 0) |> ignore })
  // what the UI was asked that it could not do as asked, shown in its place by the boundary round it (UiFault)
  @view.fault_told.val = Some(fn(said) { host_tell("ui_fault", ui_fault_category(said), "", 0, 0) |> ignore })
  // the settings' 发送使用统计和错误报告 (-1: a build that sends nothing, no row)
  if host_tell("reporting", "", "", 0, 0) >= 0 {
    @sfapp.reporting_host.set(
      Some({
        get: fn() { host_tell("reporting", "", "", 0, 0) == 1 },
        set: fn(on) { host_tell("set_reporting", "", "", if on { 1 } else { 0 }, 0) |> ignore },
      }),
    )
  }
  // the window thread's hangs (mbui's src/ui/journal.mbt), those hang_gate lets go; what the app did while shown as it
  // is hidden, its hangs all counted (hangs per hour shown), the heaviest held sent before it and how many were not
  @ui.hangs_told(
    Some(fn(h) {
      hang_keep_local(h)
      for s in hang_gate.offer(h) {
        host_tell("hang", s.json().stringify(), "", 0, 0) |> ignore
      }
    }),
  )
  @ui.hang_summary_told(
    Some(fn(s) {
      report_bar_tick()
      let (held, unsent, unsent_by) = hang_gate.flush()
      for h in held {
        host_tell("hang", h.json().stringify(), "", 0, 0) |> ignore
      }
      let json = match s.json() {
        Object(m) => {
          m["hangs_unsent"] = Json::number(unsent.to_double())
          if !unsent_by.is_empty() {
            let by : Map[String, Json] = Map([])
            for k, v in unsent_by {
              by[k] = Json::number(v.to_double())
            }
            m["hangs_unsent_by"] = Json::object(by)
          }
          // (what the core said meanwhile to ids nothing held, let be unread, by what the ids were: how many, their
          // length; none: not said)
          let unheld : Map[String, Json] = Map([])
          for u in @core.unheld_said() {
            unheld[u.0] = Json::array([Json::number(u.1.to_double()), Json::number(u.2.to_double())])
          }
          if !unheld.is_empty() {
            m["unheld"] = Json::object(unheld)
          }
          Json::object(m)
        }
        j => j
      }
      host_tell("hang_summary", json.stringify(), "", 0, 0) |> ignore
    }),
  )
  use_mb_bar.val = host_tell("bar_switch_ready", "", "", 0, 0) != 0
  let on_placed = fn(from : String, to : String) {
    if use_mb_bar.val {
      timed.clear()
      emit_bar_switch(bar_tracker.placed(from, to, @core.monotonic_ms()))
    } else {
      host_tell("placed", from, to, 0, 0) |> ignore
    }
  }
  let on_built = fn(place : String) {
    if use_mb_bar.val {
      emit_bar_switch(bar_tracker.built(place, @core.monotonic_ms()))
    } else {
      host_tell("built", place, "", 0, 0) |> ignore
    }
  }
  @sfapp.bar_timing.val = Some({ placed: on_placed, built: on_built })
  // (an account's page opened by a press, timed as a switch is: its asks the topics followed)
  @sfbase.open_timing.val = Some({ asked: fn(to) { on_placed("", to) }, opened: on_built })
  @core.time_topics(
    Some(fn(id, topic, value, first) {
      if !first {
        // (the host or MoonBit tracker says whether a switch is being timed: a value's size is counted only then)
        let take = if use_mb_bar.val {
          bar_tracker.followed(id, topic, @core.monotonic_ms())
        } else {
          host_tell("followed", topic, "", id, 0) != 0
        }
        if take {
          timed[id] = true
        }
      } else if timed.contains(id) {
        timed.remove(id)
        // (what it weighs, and of one `weights_floor` heavy at least where its bytes are, by field: @core.weights,
        // names and numbers alone; no text of it made to count them)
        let (bytes, parts) = match value {
          Some(v) => {
            let (n, heavy) = @core.weights(v)
            let said : Map[String, Json] = Map([])
            if n >= weights_floor {
              for p in heavy {
                said[p.0] = Json::number(p.1.to_double())
              }
            }
            (n, if said.is_empty() { "" } else { Json::object(said).stringify() })
          }
          None => (-1, "")
        }
        if use_mb_bar.val {
          emit_bar_switch(bar_tracker.decoded(id, bytes, parts, @core.monotonic_ms()))
        } else {
          host_tell("decoded", topic, parts, id, bytes) |> ignore
        }
      }
    }),
  )
}

///|
/// The account signed in told to the host once the accounts are read (Android: Crashes.report, iOS: apple_reports.m,
/// as the first account's `sub`): what crashed before this start goes as it, and so do the reports after.
fn report_signed_in(c : @ui.Ctx, accounts : @core.Sub) -> Unit {
  if reported.val {
    return
  }
  let sub = match accounts.value {
    Some(Array(a)) if a.length() > 0 =>
      match a[0] {
        Object(m) =>
          match m.get("sub") {
            Some(String(s)) => s
            _ => return
          }
        _ => return
      }
    _ => return
  }
  c.after_build("crashes", fn() {
    if !reported.val {
      reported.val = true
      host_tell("signed_in", sub, "", 0, 0) |> ignore
    }
  })
}

///|
/// A topic's first value this heavy (bytes) says where its bytes are with the bar's timing (BarTiming's `parts`).
let weights_floor : Int = 32768
