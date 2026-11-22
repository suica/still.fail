///|
fn gate_hang(trigger : @ui.HangTrigger, end : Double, stall : Double) -> @ui.Hang {
  {
    trigger,
    page: "Chat",
    arranged: "",
    window_w: 0.0,
    window_h: 0.0,
    sealed_by: Presented,
    startup: false,
    start: end - stall,
    end,
    stall_ms: stall,
    work_ms: stall,
    pieces: 1,
    small: 0,
    small_ms: 0.0,
    lost: 0,
    contributors: [],
    elided: 0,
  }
}

///|
test "past each ten minutes' first twenty, the heaviest twenty held, stalls first, sent as the app is hidden" {
  let g = HangGate::new()
  let mut sent = 0
  for i in 0..<20 {
    sent += g.offer(gate_hang(LateFrame, 1000.0 + i.to_double(), 30.0)).length()
  }
  assert_eq(sent, 20)
  // (forty more late frames, then five stalls: none sent at once)
  for i in 0..<40 {
    assert_eq(g.offer(gate_hang(LateFrame, 2000.0 + i.to_double(), 20.0 + i.to_double())).length(), 0)
  }
  for i in 0..<5 {
    assert_eq(g.offer(gate_hang(Stall, 3000.0 + i.to_double(), 60.0)).length(), 0)
  }
  let (held, unsent, unsent_by) = g.flush()
  assert_eq(held.length(), 20)
  assert_eq(held.filter(fn(h) { h.trigger is Stall }).length(), 5)
  // (the late frames kept are the longest: 45 to 59 ms)
  let late = held.filter(fn(h) { h.trigger is LateFrame }).map(fn(h) { h.stall_ms })
  assert_eq(late.length(), 15)
  assert_true(late.iter().all(fn(ms) { ms >= 45.0 }), msg=Repr(late).to_string())
  assert_eq(unsent, 25)
  assert_eq(unsent_by, Map([("Chat/late_frame/-", 25)]))
  assert_eq(g.flush(), ([], 0, Map([])))
}

///|
test "the held ones go first as the next ten minutes begin" {
  let g = HangGate::new()
  for i in 0..<21 {
    g.offer(gate_hang(LateFrame, 1000.0 + i.to_double(), 30.0)) |> ignore
  }
  let out = g.offer(gate_hang(Stall, 1000.0 + 600000.0, 80.0))
  assert_eq(out.map(fn(h) { h.trigger }), [LateFrame, Stall])
  let (held, unsent, unsent_by) = g.flush()
  assert_eq(held.length(), 0)
  assert_eq(unsent, 0)
  assert_eq(unsent_by, Map([]))
}

///|
test "unsent_by records dropped hang page/trigger/top_kind and caps distinct keys at 16 with other" {
  let g = HangGate::new()
  let make = fn(page : String, trigger : @ui.HangTrigger, end : Double, stall : Double, what : @ui.Done) -> @ui.Hang {
    {
      ..gate_hang(trigger, end, stall),
      page,
      contributors: [{ what, start: end - stall, end, notes: [] }],
    }
  }
  // Fill 20 sent + 20 held with heavy stalls so subsequent lighter hangs are dropped directly
  for i in 0..<40 {
    g.offer(make("Heavy", Stall, 1000.0 + i.to_double(), 200.0, Present)) |> ignore
  }
  // Drop 18 distinct keys (first 16 kept, remaining 2 folded into "other") plus 1 empty page
  for i in 0..<18 {
    let page = if i == 0 { "" } else { "Page\{i}" }
    g.offer(make(page, LateFrame, 2000.0 + i.to_double(), 30.0, Event("touch-move"))) |> ignore
  }
  // Repeat an existing key to verify it increments instead of going to "other"
  g.offer(make("", LateFrame, 2100.0, 30.0, Event("touch-move"))) |> ignore
  let (_, unsent, unsent_by) = g.flush()
  assert_eq(unsent, 19)
  assert_eq(unsent_by.get("-/late_frame/touch-move"), Some(2))
  assert_eq(unsent_by.get("Page1/late_frame/touch-move"), Some(1))
  assert_eq(unsent_by.get("Page15/late_frame/touch-move"), Some(1))
  assert_eq(unsent_by.get("other"), Some(2))
  assert_eq(unsent_by.length(), 17)
}

///|
test "this device's hang log keeps what held the window thread half a second or more, as the journal says it" {
  assert_eq(hang_local_line(gate_hang(Stall, 1000.0, 499.0)), None)
  let line = hang_local_line(gate_hang(Stall, 2000.0, 500.0)).unwrap()
  assert_true(line.contains("page=Chat"), msg=line)
  assert_true(line.contains("stall=500"), msg=line)
}
