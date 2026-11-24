// Experimental selection intent inference (实验性功能 › 选中文本自动推测意图):
// off by default (selection pill/bar unchanged); when enabled, selecting text in a chat shows 推测意图 beside 引用,
// calls `chat.selectionIntent`, and displays the inferred intent and direct reply in a panel.

///|
test "选中文本自动推测意图: off by default; when enabled, finger selection offers 推测意图 and opens the reply panel" {
  new_run()
  let calls : Array[(String, Json)] = []
  let src = fixture("chat")
  let orig_call = src.call
  let src : Source = {
    ..src,
    call: fn(name, params, cb) {
      calls.push((name, params))
      orig_call(name, params, cb)
    },
  }
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)

  // Locate a message with words to select.
  for _ in 0..<12 {
    match t.run_rects("高度先按 90 估") {
      [(_, py, _, _), ..] if py > 180.0 && py < 680.0 => break
      _ => {
        t.wheel(195.0, 400.0, -200.0)
        t.run_for(@ui.move_most_ms)
      }
    }
  }
  guard t.run_rects("高度先按 90 估") is [(px, py, _, ph), ..] else { fail("message words not drawn") }

  // 1. Default off: no 推测意图 button.
  t.press_at(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.long_press_ms)
  t.release(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_true(t.query(Button, label="引用") is Some(_))
  assert_true(t.query(Button, label="戳一下") is None)
  @ui.picked_let_go()
  t.run_for(@ui.move_most_ms)

  // 2. Turn on the experimental switch.
  exp_set(t, src, ["selectionIntent"], true)
  assert_true(@sfbase.selection_intent_feature.get())

  // 3. Long-press again: 戳一下 appears beside 引用.
  t.press_at(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.long_press_ms)
  t.release(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.move_most_ms)
  guard t.query(Button, label="戳一下") is Some(btn) else { fail("no 戳一下 button when feature is enabled") }
  let (bx, by, bw, bh) = btn.rect
  t.tap(bx + bw / 2.0, by + bh / 2.0)
  t.run_for(@ui.move_most_ms)

  // 4. `chat.selectionIntent` was called and the panel shows the direct reply with Pin and Copy actions.
  let asked = calls.filter(fn(c) { c.0 == "chat.selectionIntent" })
  assert_eq(asked.length(), 1, msg="expected one chat.selectionIntent call")
  assert_true(t.find("轻量模型结合当前对话上下文") is Some(_), msg="reply not shown")
  let drawn = @ui.view_tree().unwrap().drawn()
  guard drawn.iter().find_first(fn(d) { d.words.contains("轻量模型结合当前对话上下文") }) is Some(reply_d) else {
    fail("reply node not drawn")
  }
  guard drawn.iter().find_first(fn(d) { d.words == "戳一下" }) is Some(title_d) else {
    fail("title node not drawn")
  }
  assert_eq(reply_d.words_look.size, @sf.theme().t.meta, msg="poke reply uses meta size")
  assert_eq(title_d.words_look.size, @sf.theme().t.meta, msg="poke title uses meta size")
  assert_true(reply_d.words_look.size < @sfpages.body_size, msg="poke reply smaller than chat body prose")
  assert_true(t.query(Button, label="固定") is Some(_))
  assert_true(t.query(Button, label="复制") is Some(_))

  // 5. Clicking 固定 pins the reply into the chat, closes the panel, and supports collapse/unpin.
  t.click(Button, label="固定")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.pinned_intents_for("ws1/st1:s-c1").length(), 1)
  assert_true(t.find("轻量模型结合当前对话上下文") is Some(_), msg="pinned card not visible in chat")
  t.click(Button, label="收起")
  t.run_for(@ui.move_most_ms)
  assert_true(@sfbase.pinned_intents_for("ws1/st1:s-c1")[0].collapsed)
  t.click(Button, label="展开")
  t.run_for(@ui.move_most_ms)
  assert_false(@sfbase.pinned_intents_for("ws1/st1:s-c1")[0].collapsed)
  t.click(Button, label="取消固定")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.pinned_intents_for("ws1/st1:s-c1").length(), 0)
}

///|
/// 戳一下 asked of `src` whose `chat.selectionIntent` fails with `message`: the words picked, 戳一下 pressed.
fn intent_failed_tester(message : String, calls : Array[String]) -> @ui.Tester raise {
  new_run()
  let src = fixture("chat")
  let orig_call = src.call
  let src : Source = {
    ..src,
    call: fn(name, params, cb) {
      if name == "chat.selectionIntent" {
        calls.push(name)
        cb(Err({ "message": Json::string(message) }))
      } else {
        orig_call(name, params, cb)
      }
    },
  }
  open_fixture_over("chat", src)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=390.0, h=844.0, platform=2)
  t.run_for(@ui.move_most_ms)
  exp_set(t, src, ["selectionIntent"], true)
  for _ in 0..<12 {
    match t.run_rects("高度先按 90 估") {
      [(_, py, _, _), ..] if py > 180.0 && py < 680.0 => break
      _ => {
        t.wheel(195.0, 400.0, -200.0)
        t.run_for(@ui.move_most_ms)
      }
    }
  }
  guard t.run_rects("高度先按 90 估") is [(px, py, _, ph), ..] else { fail("message words not drawn") }
  t.press_at(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.long_press_ms)
  t.release(px + 6.0, py + ph / 2.0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="戳一下")
  t.run_for(@ui.move_most_ms)
  t
}

///|
test "戳一下 failed: says so in words, 重试 in the foot in place of 复制 and 固定, the raw error under it" {
  let calls : Array[String] = []
  let t = intent_failed_tester("timeout", calls)
  assert_true(t.find("没能拿到回复") is Some(_))
  assert_true(t.find("timeout") is Some(_))
  assert_true(t.query(Button, label="复制") is None)
  assert_true(t.query(Button, label="固定") is None)
  t.click(Button, label="重试")
  t.run_for(@ui.move_most_ms)
  assert_eq(calls.length(), 2)
}

///|
test "戳一下 on a station that predates it: says to update the station, no raw route, nothing to retry" {
  let calls : Array[String] = []
  let t = intent_failed_tester("no route POST /threads/1/selection-intent", calls)
  assert_true(t.find("这台 station 还不支持「戳一下」") is Some(_))
  assert_true(t.find("no route") is None)
  assert_true(t.query(Button, label="重试") is None)
  assert_true(t.query(Button, label="复制") is None)
}

///|
test "大屏, 戳一下 kept on the words picked: they stay lit, its answer a note in the margin at the right of their message, the column narrowed for it; 关闭 takes both off" {
  new_run()
  @sf.presenters_reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  exp_set(t, src, ["selectionIntent"], true)
  let (px, py, pw, ph) = quote_nodes_words(t, "高度先按 90 估")
  // (the right of the line its words are in, the message's whole line: as far right as the column reaches)
  let line_right = fn() {
    match t.words().filter(fn(w) { w.0.has_prefix("高度先按 90 估，") }).last() {
      Some(w) => w.1 + w.3
      None => 0.0
    }
  }
  let column_right = line_right()
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="戳一下")
  t.run_for(@ui.move_most_ms)
  let notes = @sfbase.intent_notes_for("ws1/st1:s-c1")
  assert_eq(notes.length(), 1, msg="one note")
  assert_eq(notes[0].selection, "高度先按 90 估")
  assert_false(@sf.presented_drawn(), msg="no panel opened")
  guard t.words().filter(fn(w) { w.0.contains("轻量模型结合当前对话上下文") }).last() is Some(answer) else {
    fail("the answer not drawn")
  }
  let (nx, ny) = (answer.1, answer.2)
  guard t.run_rects("高度先按 90 估") is [(wx, wy, _, _), ..] else { fail("the words not drawn") }
  let narrowed = line_right()
  assert_true(narrowed < column_right, msg="the column narrowed: \{column_right} to \{narrowed}")
  assert_true(nx > narrowed, msg="the note at the column's right: \{nx} past \{narrowed}")
  assert_true(ny >= wy - 40.0 && ny < wy + 120.0, msg="the note by its message: \{ny} by \{wy}")
  assert_true(wx > 0.0)
  t.click(Button, label="关闭")
  t.run_for(@ui.move_most_ms)
  assert_eq(@sfbase.intent_notes_for("ws1/st1:s-c1").length(), 0, msg="taken off")
  assert_true(t.words().filter(fn(w) { w.0.contains("轻量模型结合当前对话上下文") }).is_empty(), msg="the note gone")
}

///|
test "大屏, two 戳一下 on words of one message: each lit, each a note of its own, in the order the words stand; the pointer on one lights its words deeper" {
  new_run()
  @sf.presenters_reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1280.0, h=800.0, platform=0, corners_held=false)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  exp_set(t, src, ["selectionIntent"], true)
  let poke = fn(words : String) raise {
    let (px, py, pw, ph) = quote_nodes_words(t, words)
    t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
    t.run_for(@ui.move_most_ms)
    t.click(Button, label="戳一下")
    t.run_for(@ui.move_most_ms)
  }
  // (the later words first)
  poke("深色模式我一起看")
  poke("高度先按 90 估")
  let notes = @sfbase.intent_notes_for("ws1/st1:s-c1")
  assert_eq(notes.length(), 2)
  assert_eq(notes[0].row, notes[1].row, msg="both of one message")
  assert_eq(@sfbase.intent_notes_on("ws1/st1:s-c1", notes[0].row).map(fn(n) { n.selection }), ["高度先按 90 估", "深色模式我一起看"])
  // (each passage on its ground, as a quote's flash lights one: two grounds drawn)
  let ground = @sf.alpha(@sf.theme().p.accent, @sfbase.picked_alpha)
  let deeper = @sf.alpha(@sf.theme().p.accent, 2.0 * @sfbase.picked_alpha)
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == ground }).length(), 2, msg="both lit")
  let card_of = fn(words : String) {
    t.words().filter(fn(w) { w.0.contains("关于「" + words + "」") }).last()
  }
  guard (card_of("高度先按 90 估"), card_of("深色模式我一起看")) is (Some(first), Some(second)) else { fail("two cards") }
  assert_true(first.2 < second.2, msg="the first words' note above: \{first.2} over \{second.2}")
  // (the pointer on the second's card: its words deeper, the first's as they were)
  t.move_to(second.1 + 20.0, second.2 + second.4 / 2.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == deeper }).length(), 1, msg="the pointed one deeper")
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == ground }).length(), 1, msg="the other as it was")
  t.move_to(700.0, 700.0)
  t.run_for(@ui.move_most_ms)
  assert_eq(t.drawn_rects().filter(fn(r) { r.4 == ground }).length(), 2, msg="both as they were once it is off")
}

///|
test "戳一下 open beside the words picked with the mouse, the list too narrow for notes: the wheel over the chat scrolls it, the answer staying open" {
  new_run()
  @sf.presenters_reset()
  let src = fixture("chat")
  open_chat({ station: "ws1/st1", session: "s-c1", title: "整理发布清单", station_name: "Willow" })
  // (a window whose chat list is narrower than notes need (intent_notes_fit): 戳一下 opens in its popover)
  let t = @ui.Tester::new(fn(c) { view(c, src) }, tree=app_tree(src), w=1000.0, h=800.0, platform=0)
  t.check_looks(false)
  t.run_for(@ui.move_most_ms)
  exp_set(t, src, ["selectionIntent"], true)
  let (px, py, pw, ph) = quote_nodes_words(t, "高度先按 90 估")
  t.drag(px + 1.0, py + ph / 2.0, px + pw - 1.0, py + ph / 2.0)
  t.run_for(@ui.move_most_ms)
  t.click(Button, label="戳一下")
  t.run_for(@ui.move_most_ms)
  assert_true(@sf.presented_drawn(), msg="the popover opened")
  assert_true(t.find("轻量模型结合当前对话上下文") is Some(_), msg="the answer shown")
  // (over the words picked, clear of the panel under them: the chat moves under the pointer)
  t.wheel(px + 1.0, py + ph / 2.0, -40.0)
  t.run_for(@ui.move_most_ms)
  guard t.run_rects("高度先按 90 估") is [(_, moved, _, _), ..] else { fail("words not drawn") }
  assert_true(moved > py + 20.0, msg="the chat scrolled: \{py} to \{moved}")
  assert_true(t.find("轻量模型结合当前对话上下文") is Some(_), msg="the answer stays open")
}
