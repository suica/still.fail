// Rows that go somewhere on a group's card in a panel's body (link_row_node in group_node), one with a mark before its
// words (a 20 icon, made by the page) and one with none, on every screen a panel is drawn on: everything drawn and
// every word where it stood when it stood where the old view's rows (link_row in group) did, and as high.

///|
/// What a panel holding two rows that go somewhere on a group's card draws at rest, every rectangle (where and how big,
/// to a thousandth of a point) and every word (where and how high), in order, on a window `at`, opened by its 打开
/// (`pressed`) or by nothing. Closed after, gone.
fn link_card_drawn(at : (Int, Double, Double), pressed : Bool) -> Array[String] raise {
  let open = fn(from : Anchor) {
    let from = if pressed {
      if layout(at.1) is Small { Anchor::At(40.0, at.2 - 80.0, 60.0, 32.0) } else { from }
    } else {
      Unanchored
    }
    panel_nodes("一组", from~, fn(v, _) {
      v.box(fn(b) {
        style_node(b, fn() { panel_words_in_node(b) })
        words_node(b, fn() { "它说的话" }, fn() { secondary }) |> ignore
      })
      |> ignore
      v.box(fn(b) {
        style_node(b, fn() { group_panel_block.then(panel_card_last_node(b)) })
        group_node(b, fn(g) {
          link_row_node(g, fn() { "上传图片" }, fn() {  }, chevron=false, lead=LeadMade(fn(l) {
            icon_node(l, "image-upload", 20.0, By(fn() { theme().p.text })) |> ignore
          }))
          link_row_node(g, fn() { "不带图标" }, fn() {  }, chevron=false)
        })
      })
      |> ignore
    })
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
  let words = t.words().map(fn(w) { "words \{w.0}@\{k(w.1)},\{k(w.2)} h\{k(w.4)} a\{w.5}" })
  // (the old view's words and the tree's are told in their own orders)
  words.sort()
  close_all_presented()
  t.run_for(@ui.move_most_ms)
  assert_false(presented_drawn(), msg="closed")
  drawn + words
}

///|
test "rows that go somewhere, with a mark before their words and with none, on a group's card in a panel's body as nodes: a sheet opened by nothing and by a press, a small panel beside what opened it, a dialog in the middle of the window" {
  let seen : Array[String] = []
  for screen in [
    ("sheet opened by nothing", phone, false),
    ("sheet opened by a press", phone, true),
    ("sheet opened by a press, with a mouse", (0, 390.0, 844.0), true),
    ("small panel", (0, 800.0, 600.0), true),
    ("dialog", (0, 800.0, 600.0), false),
  ] {
    let (about, at, pressed) = screen
    seen.push("\{about}:")
    seen.append(link_card_drawn(at, pressed))
  }
  inspect(seen.join("\n"), content=(
    #|sheet opened by nothing:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,605 38x5 841819172
    #|rect 22,698 346x124 606546701
    #|words 一组@30,622 h24 a1
    #|words 打开@180,45 h22 a1
    #|words 上传图片@78,722 h22 a1
    #|words 不带图标@46,776 h22 a1
    #|words 它说的话@30,656 h18 a1
    #|sheet opened by a press:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,615 38x5 841819172
    #|rect 22,698 346x124 606546701
    #|words 一组@30,632 h24 a1
    #|words 打开@180,45 h22 a1
    #|words 上传图片@78,722 h22 a1
    #|words 不带图标@46,776 h22 a1
    #|words 它说的话@30,666 h18 a1
    #|sheet opened by a press, with a mouse:
    #|rect 40,40 310x32 3907312895
    #|rect 0,0 390x844 71
    #|rect 176,615 38x5 841819172
    #|rect 22,698 346x124 606546701
    #|words 一组@30,632 h24 a1
    #|words 打开@182,46 h20 a1
    #|words 上传图片@78,722 h22 a1
    #|words 不带图标@46,776 h22 a1
    #|words 它说的话@30,666 h18 a1
    #|small panel:
    #|rect 40,40 720x32 3907312895
    #|rect 46,146 284x94 4294967295
    #|words 一组@62,90 h20 a1
    #|words 打开@387,46 h20 a1
    #|words 不带图标@68,204 h20 a1
    #|words 它说的话@62,114 h18 a1
    #|words 上传图片@100,162 h20 a1
    #|dialog:
    #|rect 40,40 720x32 3907312895
    #|rect 0,0 800x600 320215859
    #|rect 156,305.5 488x96 606546701
    #|words 打开@387,46 h20 a1
    #|words 一组@164,208.5 h30 a1
    #|words 上传图片@212,323.5 h20 a1
    #|words 不带图标@180,363.5 h20 a1
    #|words 它说的话@164,257.5 h18 a1


  ))
}
