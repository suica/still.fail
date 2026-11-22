// A segmented choice as the web's narrow pages have it (web/src/mobile/parts.tsx Seg): mbui's
// sliding toggle group in Seg's look. Not a part of its own: `segmented` (parts.mbt) draws it on a narrow page, the
// web's Segmented on a wide one.

///|
/// What a `stops` keeps between builds: the level its caller last said, the level it shows, the level last picked in
/// it that its caller has yet to say back (-1 none), and while one is, the levels its caller may still say that are
/// not news (what it said as each was picked, and what was picked before).
pub struct Stops {
  mut said : Int
  mut shown : Int
  mut expect : Int
  stale : Array[Int]
  /// how many times its caller has said a pick did not take (Stops::reset): what shows it as nodes (stops_node) told so
  resets : @signals.Signal[Int]
}

///|
pub fn Stops::new() -> Stops {
  { said: -2, shown: -1, expect: -1, stale: [], resets: @signals.signal(0) }
}

///|
/// What was picked in it did not take (its caller's: a save refused): it shows what its caller says again.
pub fn Stops::reset(self : Stops) -> Unit {
  self.said = -2
  self.expect = -1
  self.stale.clear()
  self.resets.set(self.resets.untracked() + 1)
}

///|
/// Its track: a capsule on the words' tint, its stops in a line across it, 4 in.
// kept across runs: a value (no field of it changes)
let stops_track : @ui.Style = @ui.css("row w=Full p=S1 radius=Full bg=Tint")

///|
/// How wide a node's words `s` are on one line at `size` and `weight`: in the theme the window's tree's words are drawn in (@ui.tree_theme, view_host's
/// words_style).
pub fn node_words_w(s : String, size : Double, weight? : Int = 400) -> Double {
  words_w(@ui.tree_theme().tabular, s, size, weight~)
}

///|
/// How wide words `s` are on one line at `size` and `weight`, their digits all one width where `tabular`.
fn words_w(tabular : Bool, s : String, size : Double, weight? : Int = 400) -> Double {
  @ui.text_advance(s, size~, weight~, style=if tabular { @hostapi.style_tabular } else { 0 })
}

///|
/// How far its track stands round its options (seg_track's p=S0_5).
let seg_inset : Double = @ui.Space::px(S0_5)

///|
/// How far the chosen one's words stand in from its track's side, and from the chevron, when they do not fit side by
/// side (seg_menu's px=S2_5, gap=S2).
let seg_menu_in : Double = @ui.Space::px(S2_5)

///|
let seg_menu_gap : Double = @ui.Space::px(S2)

///|
// kept across runs: a value (no field of it changes)
let seg_menu_words : @ui.TextStyle = @ui.text_style(size=Body, color=Fg, w=Cut, wrap=false)

///|
let seg_chevron : Double = 16.0

///|
/// A filling option's words' sides (seg_full_option's px=S2), and how little they go to where the room is short
/// (seg_squeezed_option's px=S1).
let seg_side : Double = @ui.Space::px(S2)

///|
let seg_least : Double = @ui.Space::px(S1)

///|
/// How a choice's options fit the room option_widths gives them: their words at their size; their words made smaller
/// alike, by this much (down to the system's own size of words, as the systems' own segmented controls make theirs);
/// or not side by side at all, the chosen one alone and the others offered in a pick (choice_pick).
// Eq, Show and Debug for its tests
#warnings("-unused_value")
#derive(Eq, Debug)
priv enum Fit {
  Whole
  Smaller(Double)
  Menu
}

///|
/// How wide each of a choice's options is in `room` (all of it, the gaps between them aside), their words `words`
/// wide, and how they fit it: as alike as they can be, none narrower than its words with `side` either side; where
/// those come to more than the room, each its words with their sides narrower alike (to `least`); where even that is
/// too much, their words made smaller alike till they fit with the least either side, `smallest` of their size at the
/// least; else not side by side (Menu, no widths). Always one line, each one's words whole: nothing wrapped, cut or
/// scrolled (the user, 2026-10-25: a sideways scroll and words on two lines alike ugly).
fn option_widths(
  words : Array[Double],
  room : Double,
  side : Double,
  least : Double,
  smallest : Double,
) -> (Array[Double], Fit) {
  let room = dmax(room, 0.0)
  let n = words.length().to_double()
  let total = words.fold(init=0.0, fn(s, w) { s + w })
  if total + 2.0 * side * n <= room {
    return (shares(room, words.map(fn(w) { w + 2.0 * side }), words.map(fn(_) { 1.0 })), Whole)
  }
  if total + 2.0 * least * n <= room {
    let s = (room - total) / (2.0 * n)
    return (words.map(fn(w) { w + 2.0 * s }), Whole)
  }
  let k = if total > 0.0 { (room - 2.0 * least * n) / total } else { 0.0 }
  if k >= smallest && k > 0.0 {
    (words.map(fn(w) { w * k + 2.0 * least }), Smaller(k))
  } else {
    ([], Menu)
  }
}

///|
/// A choice's options fitted to its room (option_widths): their widths, and how they fit (made smaller, their words
/// drawn so: Ctx::words_smaller).
priv struct Fitted {
  widths : Array[Double]
  fit : Fit
}

///|
/// `labels`' options fitted to `room`, their words said in `base` and `weight`, `side` either side and `least` at the
/// least, drawn at `sp` of the size said (node_sp), their digits all one width where `tabular` (the theme they are drawn in says so).
fn fitted_by(
  sp : (Double) -> Double,
  tabular : Bool,
  labels : Array[String],
  room : Double,
  base : Double,
  weight : Int,
  side : Double,
  least : Double,
) -> Fitted {
  let size = sp(base)
  let words = labels.map(fn(l) { words_w(tabular, l, size, weight~) })
  // (no smaller than the app says them: the size the system's own size of words draws)
  let smallest = dmin(1.0, base / size)
  let (widths, fit) = option_widths(words, room, side, least, smallest)
  match fit {
    // (their words as drawn that much smaller, what is left shared alike; a face's words narrow not quite as its size
    // does (San Francisco's optical sizes: smaller, set looser), so measured as drawn and made smaller again till they
    // fit with the least either side, else not side by side)
    Smaller(k0) => {
      let most = room - 2.0 * least * labels.length().to_double()
      let mut k = k0
      let mut drawn = labels.map(fn(l) { words_w(tabular, l, size * k, weight~) })
      let mut sum = drawn.fold(init=0.0, fn(s, w) { s + w })
      for _ in 0..<4 {
        if sum <= most + 0.01 || sum <= 0.0 || k < smallest {
          break
        }
        k = k * most / sum
        drawn = labels.map(fn(l) { words_w(tabular, l, size * k, weight~) })
        sum = drawn.fold(init=0.0, fn(s, w) { s + w })
      }
      if k < smallest || sum > most + 0.01 {
        return { widths: [], fit: Menu }
      }
      let left = (room - sum) / labels.length().to_double()
      { widths: drawn.map(fn(w) { w + left }), fit: Smaller(k) }
    }
    _ => { widths, fit }
  }
}

///|
/// The option of `labels` a pick's key `k` names (its index), else `none`.
fn labels_at(labels : Array[String], k : String, none : Int) -> Int {
  for i in 0..<labels.length() {
    if i.to_string() == k {
      return i
    }
  }
  none
}

///|
/// `room` shared by `weights`, none given less than its floor: those whose share falls short take their floor, the
/// rest sharing what is left by theirs (as CSS's flex with min-widths). Where the floors come to more than the room,
/// the room shared by them.
fn shares(room : Double, floors : Array[Double], weights : Array[Double]) -> Array[Double] {
  let floored = floors.fold(init=0.0, fn(s, f) { s + f })
  if floored >= room && floored > 0.0 {
    return floors.map(fn(f) { room * f / floored })
  }
  let held = floors.map(fn(_) { false })
  for _ in 0..=floors.length() {
    let mut left = room
    let mut weight = 0.0
    for i, f in floors {
      if held[i] {
        left = left - f
      } else {
        weight = weight + weights[i]
      }
    }
    let mut more = false
    for i, f in floors {
      if !held[i] && left * weights[i] / weight < f {
        held[i] = true
        more = true
      }
    }
    if !more {
      return floors.mapi(fn(i, f) { if held[i] { f } else { left * weights[i] / weight } })
    }
  }
  floors
}
