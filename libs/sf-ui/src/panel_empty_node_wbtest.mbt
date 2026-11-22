// A panel of nodes whose body holds nothing this time (what it holds a show that is not there): on every screen a panel
// is drawn on, none of the body's room left, everything drawn and every word where it stood when it stood where the old
// panel's whose body drew nothing did, and as big; holding something, the same as ever.

///|
/// What a panel titled, saying something and with a button in its foot draws at rest, every rectangle and every word
/// (each where and how big, to a thousandth of a point), in order: the node panel's, its body holding a line of words
/// while `full` says so and nothing else, on a window `at`, opened by its 打开
/// (`pressed`: a sheet a press opened, a small panel beside it) or by nothing (a sheet, a dialog in the middle of the
/// window). Closed after, gone.
fn panel_empty_drawn(at : (Int, Double, Double), pressed : Bool, full : Bool) -> Array[String] raise {
  let open = fn(from : Anchor) {
    let from = if pressed {
      if layout(at.1) is Small { Anchor::At(40.0, at.2 - 80.0, 60.0, 32.0) } else { from }
    } else {
      Unanchored
    }
    panel_nodes(
      "一个",
      from~,
      description="它说的话",
      fn(v, _) {
        v.show(fn() { full }, fn(s) {
          s.box(fn(b) {
            style_node(b, fn() { panel_words_in_node(b) })
            words_node(b, fn() { "它里面的话" }, fn() { secondary }) |> ignore
          })
          |> ignore
        })
      },
      foot=fn(v, _) { button_node(v, fn() { "好" }, fn() {  }, tone=Primary) |> ignore },
    )
  }
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w~,
    h~,
    platform~,
  )
  t.check_looks(false)
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let drawn = t.drawn_rects().map(fn(r) { "rect \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)} \{r.4}" })
  let words = t.words().map(fn(w) { "words \{w.0}@\{k(w.1)},\{k(w.2)} \{k(w.3)}x\{k(w.4)} a\{w.5}" })
  // (the old view's words and the tree's are told in their own orders)
  words.sort()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  drawn + words
}

///|
test "a panel's body holding nothing takes none of its room; holding something, as ever: a sheet opened by nothing and by a press, with a finger and with a mouse, a small panel beside what opened it, a dialog in the middle of the window" {
  let seen : Array[String] = []
  for screen in [
    ("sheet opened by nothing", phone, false),
    ("sheet opened by a press", phone, true),
    ("sheet opened by a press, with a mouse", (0, 390.0, 844.0), true),
    ("small panel", (0, 800.0, 600.0), true),
    ("dialog", (0, 800.0, 600.0), false),
  ] {
    let (about, at, pressed) = screen
    for full in [false, true] {
      seen.push("\{about}, \{if full { "holding words" } else { "empty" }}:")
      seen.append(panel_empty_drawn(at, pressed, full))
    }
  }
  inspect(seen.join("\n"), content=(
    #|sheet opened by nothing, empty:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,667 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,684 32x24 a1
    #|words 打开@180,45 30x22 a1
    #|words 好@187.5,785 15x22 a1
    #|words 它说的话@30,718 330x20 a1
    #|sheet opened by nothing, holding words:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,625 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,642 32x24 a1
    #|words 打开@180,45 30x22 a1
    #|words 好@187.5,785 15x22 a1
    #|words 它说的话@30,676 330x20 a1
    #|words 它里面的话@30,714 330x18 a1
    #|sheet opened by a press, empty:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,667 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,684 32x24 a1
    #|words 打开@180,45 30x22 a1
    #|words 好@187.5,785 15x22 a1
    #|words 它说的话@30,718 330x20 a1
    #|sheet opened by a press, holding words:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,649 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,666 32x24 a1
    #|words 打开@180,45 30x22 a1
    #|words 好@187.5,785 15x22 a1
    #|words 它说的话@30,700 330x20 a1
    #|words 它里面的话@30,738 330x18 a1
    #|sheet opened by a press, with a mouse, empty:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,667 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,684 32x24 a1
    #|words 打开@182,46 26x20 a1
    #|words 好@188.5,786 13x20 a1
    #|words 它说的话@30,718 330x20 a1
    #|sheet opened by a press, with a mouse, holding words:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,649 38x5 841819172
    #|rect 32,780 326x32 606546943
    #|words 一个@30,666 32x24 a1
    #|words 打开@182,46 26x20 a1
    #|words 好@188.5,786 13x20 a1
    #|words 它说的话@30,700 330x20 a1
    #|words 它里面的话@30,738 330x18 a1
    #|small panel, empty:
    #|rect 40,40 720x32 3907312895
    #|rect 287,122 41x32 606546943
    #|words 一个@62,90 252x20 a1
    #|words 好@301,128 13x20 a1
    #|words 打开@387,46 26x20 a1
    #|small panel, holding words:
    #|rect 40,40 720x32 3907312895
    #|rect 287,140 41x32 606546943
    #|words 一个@62,90 252x20 a1
    #|words 好@301,146 13x20 a1
    #|words 打开@387,46 26x20 a1
    #|words 它里面的话@62,114 252x18 a1
    #|dialog, empty:
    #|rect 40,40 720x32 3907312895
    #|rect 0,0 800x600 320215859
    #|rect 593,324.5 41x32 606546943
    #|words 打开@387,46 26x20 a1
    #|words 好@607,330.5 13x20 a1
    #|words 一个@164,243.5 44x30 a1
    #|words 它说的话@164,280.5 472x20 a1
    #|dialog, holding words:
    #|rect 40,40 720x32 3907312895
    #|rect 0,0 800x600 320215859
    #|rect 593,342.5 41x32 606546943
    #|words 打开@387,46 26x20 a1
    #|words 好@607,348.5 13x20 a1
    #|words 一个@164,225.5 44x30 a1
    #|words 它说的话@164,262.5 472x20 a1
    #|words 它里面的话@164,300.5 472x18 a1


  ))
}

///|
/// What the node panel of panel_empty_drawn draws at rest once what its body holds has gone (it held its line of words
/// as it opened, then not), as panel_empty_drawn says it: the body closing its way to none of its room with what goes,
/// judged frame by frame on the way where a run judges motion. Closed after, gone.
fn panel_emptied_drawn(at : (Int, Double, Double)) -> Array[String] raise {
  let full = @signals.signal(true)
  let open = fn(_from : Anchor) {
    panel_nodes(
      "一个",
      from=Unanchored,
      description="它说的话",
      fn(v, _) {
        v.show(fn() { full.get() }, fn(s) {
          s.box(fn(b) {
            style_node(b, fn() { panel_words_in_node(b) })
            words_node(b, fn() { "它里面的话" }, fn() { secondary }) |> ignore
          })
          |> ignore
        })
      },
      foot=fn(v, _) { button_node(v, fn() { "好" }, fn() {  }, tone=Primary) |> ignore },
    )
  }
  presenters_reset()
  let (platform, w, h) = at
  let t = @ui.Tester::new(
    fn(c) { c.with_theme(ui_theme(), fn() { @ui.old_views_here(c) }) },
    tree=presented_tree(presenting_view(open)),
    w~,
    h~,
    platform~,
  )
  t.check_looks(false)
  t.draw()
  t.tap_text("打开")
  t.run_for(@ui.move_most_ms)
  t.leave()
  t.draw()
  full.set(false)
  t.run_for(@ui.move_most_ms)
  t.draw()
  let k = fn(v : Double) { (v * 1000.0).round() / 1000.0 }
  let drawn = t.drawn_rects().map(fn(r) { "rect \{k(r.0)},\{k(r.1)} \{k(r.2)}x\{k(r.3)} \{r.4}" })
  let words = t.words().map(fn(w) { "words \{w.0}@\{k(w.1)},\{k(w.2)} \{k(w.3)}x\{k(w.4)} a\{w.5}" })
  words.sort()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  drawn + words
}

///|
test "what a panel's body holds going, the body closes its way to none of its room with it, and at rest is the panel that held nothing: a sheet, a dialog in the middle of the window" {
  let differs : Array[String] = []
  for screen in [("sheet", phone), ("sheet, with a mouse", (0, 390.0, 844.0)), ("dialog", (0, 800.0, 600.0))] {
    let (about, at) = screen
    let emptied = panel_emptied_drawn(at)
    let empty = panel_empty_drawn(at, false, false)
    for i in 0..<(if emptied.length() > empty.length() { emptied.length() } else { empty.length() }) {
      let a = emptied.get(i).unwrap_or("-")
      let b = empty.get(i).unwrap_or("-")
      if a != b {
        differs.push("\{about}: line \{i}:\n  emptied \{a}\n  empty \{b}")
      }
    }
  }
  if !differs.is_empty() {
    fail(differs.join("\n"))
  }
}
