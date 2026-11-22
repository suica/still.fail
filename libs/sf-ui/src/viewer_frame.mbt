// The frame round a file opened over the whole window, whatever the tier and the input (still.fail web/src/FilePreview.tsx,
// FilePreview.css.ts): what draws it gives what it says and does (sfbase's viewer: the file, its stages, what is read).
// In the Small tier one bar floats at the top, as wide as what it holds and never narrower once open (fpHead: the
// file's name, its kind and size, its tools and close); otherwise the bar every file opened has across the top
// (viewer_bar.mbt: back by name, the name, its tools). The ways to the image before and after are discs of the
// canvas at its sides; a file not shown is told of in the middle. Under 640 the web's phone sizes.

///|
/// The width under which a viewer is laid out as a phone's.
pub let viewer_small_w : Double = 640.0

///|
/// Whether a file opened `w` wide has the bar floating at its top (viewer_frame_bar's: the Small tier, a phone's or a
/// fold half open wider than one, viewer_head_node's as nodes), not the bar across the top.
pub fn viewer_bar_floats(w : Double) -> Bool {
  layout(w) is Small
}

///|
/// How far down from the window's top what a file opened `w` wide has for a bar reaches: the bar floating at its top, or
/// the one across it (viewer_bar_under).
pub fn viewer_bar_clear(w : Double) -> Double {
  if viewer_bar_floats(w) {
    let top = (viewer_host().room)().0
    dmax(top, if w <= viewer_small_w { vfr_head_top_small } else { vfr_head_top }) + vfr_head_h
  } else {
    viewer_bar_under()
  }
}

///|
/// The floating bar's height (vfr_head_box's S11).
let vfr_head_h : Double = 44.0

///|
/// What is opened over the whole window to be done one way (a chat shared as a picture: sfpages' publish.mbt), in
/// `parent` (a layer over what it is for, all of its room): laid out Small (the window's `width` says the screen's tier:
/// the arrangement of what is opened over the whole window, as a file opened has its, never the room a part is given),
/// no bar over it, but a band of glass along the window's foot with 取消 and the doing (`label`) side by side, as wide
/// as each other (2026-10-26 用户「应该放下面，俩按钮，一个取消一个保存到相册」「pc 的话直接跟附件预览一样，有顶栏」「pc 也用文字
/// 按钮，不要用图标」); else the bar a file opened has across the top (viewer_bar_node: back to `back` by name, `name` and
/// `meta`), the doing a button in words at its end. `copy`: a second doing before it, copying (a phone's 复制图片 beside
/// its 保存到相册, 2026-11-06 用户「手机上都加复制」), at the foot 取消 and it as wide as their words, the doing the rest.
/// `busy`: a doing under way (`busy_copy`: the copying), the other not pressed meanwhile; `disabled`: nothing to do it
/// to yet. As they are pressed: `on_close` (its way back, 取消), `on_act` (the doing), `on_copy` (the copying). Each as it
/// changes; its tips in `tips`.
#callsite(autofill(loc))
pub fn viewer_frame_act_node(
  parent : @view.View,
  back : () -> String,
  name : () -> String,
  meta : () -> String,
  ink : () -> ViewerInk,
  label : () -> String,
  width : () -> Double,
  tips : TipLayer,
  copy? : () -> String,
  busy? : () -> Bool = fn() { false },
  busy_copy? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
  on_close~ : () -> Unit,
  on_act~ : () -> Unit,
  on_copy? : () -> Unit = fn() {  },
  loc~ : SourceLoc,
) -> Unit {
  let act_busy = fn() { busy() && !busy_copy() }
  let act_off = fn() { disabled() || (busy() && busy_copy()) }
  let copy_busy = fn() { busy() && busy_copy() }
  let copy_off = fn() { disabled() || (busy() && !busy_copy()) }
  parent.box(made_for=loc, fn(room) {
    room.over(Is(true)) |> ignore
    room.pick(fn() { layout(width()) is Small }, fn(p, small) {
      if small {
        // (the window's whole, floating liquid glass action pill over a soft bottom scroll-edge)
        p.over(Is(true)).lies_along(Is(End)) |> ignore
        let foot_h = fn(_ : @view.View) { vfr_act_in * 2.0 + button_height() + (viewer_host().room)().1 + 12.0 }
        @lg.liquid_scroll_edge_node(p, foot_h, foot_h, side=Bottom, bg=fn() { ink().ground }, shield=false) |> ignore
        p.box(fn(band) {
          let pill_pad = 4.0
          band
          .fills_across(Is(true))
          .padding(By(fn() {
            // (a long button keeps its shape and stands past a rounded window's corner where the foot has not brought
            // it past it already: viewer_frame_act's; subtract pill_pad so inner buttons keep full width)
            let bottom = dmax(0.0, vfr_act_in - pill_pad) + (viewer_host().room)().1
            let left = dmax(0.0, vfr_act_side_at(@ui.window_corner_at(3), bottom + pill_pad) - pill_pad)
            let right = dmax(0.0, vfr_act_side_at(@ui.window_corner_at(2), bottom + pill_pad) - pill_pad)
            (left, dmax(0.0, vfr_act_in - pill_pad), right, bottom)
          }))
          |> ignore
          band.box(fn(row) {
            let outer_r = fn() { (button_height() + 2.0 * pill_pad) / 2.0 }
            // (its buttons' ends giving way alike where the row is too narrow for them all, never their words:
            // button_node's ends_give_lent)
            row
            .row(Is(true))
            .lines_up(Is(Some(Middle)))
            .gap(Is(@ui.Space::px(S2)))
            .padding(Is((pill_pad, pill_pad, pill_pad, pill_pad)))
            .radius(By(outer_r))
            .glass(By(fn() { Some(@lg.liquid_bar_pill_glass(solid=panel_ground(), sharing=true)) }))
            .edge(By(fn() { if row.glass_solid() { @lg.liquid_solid_edge() } else { (0.0, 0L) } }))
            .shadow(By(fn() { glass_control_shadow() }))
            .shadow_outside(Is(true))
            .clips(Is(true))
            .lends(ends_give_lent, true)
            |> ignore
            corner_card_node(row, outer_r, inset=fn() { pill_pad })
            // (with a copying beside it, 取消 and it as wide as their words, the doing the rest: viewer_frame_act's.
            // Without, 取消 and the doing each half while both fit. The doing never narrower than its words and ends
            // need, nor 取消 beside it alone, as a sheet's foot's two (button_node's foot_fills_lent): what is beside it
            // giving way, so that at a large size of words 「Save to Photos」 keeps its ends beside 「Cancel」 and
            // 「Copy」, never pressed into its curve)
            let fill = fn(make : (@view.View) -> Unit) {
              row.box(fn(f) {
                f.grow(Is(1.0)).basis(Is(Some(0.0))).keeps_held(Is(true)) |> ignore
                make(f)
              })
              |> ignore
            }
            match copy {
              Some(words) => {
                button_node(row, fn() { t("common.cancel") }, on_close) |> ignore
                button_node(row, words, on_copy, busy=copy_busy, disabled=copy_off) |> ignore
              }
              None => fill(fn(f) { button_node(f, fn() { t("common.cancel") }, on_close, across=true) |> ignore })
            }
            fill(fn(f) { button_node(f, label, on_act, tone=Primary, busy=act_busy, disabled=act_off, across=true) |> ignore })
          })
          |> ignore
        })
        |> ignore
      } else {
        viewer_bar_node(
          p,
          back,
          name,
          meta,
          fn() { "" },
          fn() { false },
          fn(_) { 1.0 },
          fn() { (viewer_host().room)().0 },
          width,
          ink,
          fn(row, _) {
            match copy {
              Some(words) => button_node(row, words, on_copy, busy=copy_busy, disabled=copy_off) |> ignore
              None => ()
            }
            button_node(row, label, on_act, tone=Primary, busy=act_busy, disabled=act_off) |> ignore
          },
          on_close,
          tips,
          // (its last a capsule of words, past the window's corner)
          capsule_end=true,
        )
        |> ignore
      }
    })
  })
  |> ignore
}

///|
/// How much of the window's top what a thing opened to be done one way has over it takes (viewer_frame_act_node), the
/// window `w` wide: the bar on a wide screen (viewer_bar_under), on a small one nothing of its own, only the page's bars
/// over the window (a phone's status bar). What is under it starts that far down.
pub fn viewer_act_head(w : Double) -> Double {
  if layout(w) is Small {
    (viewer_host().room)().0
  } else {
    viewer_bar_under()
  }
}

///|
/// How much of the window's foot the band of a thing opened to be done one way takes on a small screen
/// (viewer_frame_act_node), the window `w` wide, the page's bar under it with it (a phone's navigation bar): what is
/// under it is laid out that much clear of the foot. None on a wide screen (its bar is at the top).
pub fn viewer_act_foot(w : Double) -> Double {
  if layout(w) is Small {
    vfr_act_in * 2.0 + button_height() + (viewer_host().room)().1
  } else {
    0.0
  }
}

///|
/// The band's buttons 12 in from its top and foot (the page's bar under it besides).
let vfr_act_in : Double = 12.0

///|
/// The band's buttons' usual distance from its sides.
let vfr_act_side : Double = 16.0

///|
/// A long action cannot follow a corner: if it lies beside the arc, keep it past that arc by its usual side room.
fn vfr_act_side_at(corner : Double, bottom : Double) -> Double {
  let reach = corner + corner_fit.near
  if corner > 0.0 && bottom < reach && vfr_act_side < reach {
    corner + vfr_act_side
  } else {
    vfr_act_side
  }
}

///|
/// Liquid glass for floating viewer capsules (`viewer_head_node`, `viz_page`): neutral single-layer iOS 27 liquid
/// glass over the viewer's canvas.
pub fn viewer_page_glass() -> @ui.Glass {
  @lg.liquid_viewer_clear_glass(solid=theme().p.canvas)
}

///|
/// How much of a file opened has come, beside the bar's tools (viewer_coming_node): its bar 120 wide.
let vfr_coming_track : Double = 120.0

///|
/// The same in the floating bar (viewer_head_node), its name beside it on a phone's width: its bar 48 wide.
pub let vfr_head_coming_track : Double = @ui.Space::px(S12)

///|
/// Key `code` (`mods` held) as an image's zoom takes it at `at` (the viewer's node's keys): + (⇧=, =) in, − (_) out, 0 fitted,
/// 1 as it is, on from how big it shows then; true where it is one of them (and the image has a size to zoom).
pub fn viewer_zoom_key(z : @motion.Zoom, code : Int, mods : Int, at : Double) -> Bool {
  if z.nw <= 0.0 || (mods & (@ui.mod_cmd | @ui.mod_ctrl | @ui.mod_alt)) != 0 {
    return false
  }
  let key = fn(ch : Char) { code == @ui.key_of_char(ch) }
  if key('+') || key('=') {
    z.zoom_to(z.scale_at(at) * viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else if key('-') || key('_') {
    z.zoom_to(z.scale_at(at) / viewer_zoom_step, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else if key('0') {
    z.reset(at~)
  } else if key('1') {
    z.zoom_to(1.0, z.bw / 2.0, z.bh / 2.0, true, at~)
  } else {
    return false
  }
  true
}

///|
/// The zoom's steps by the keys (a quarter more or less each).
pub let viewer_zoom_step : Double = 1.25

///|
/// The ways beside: 22 chevrons.
let viewer_step_icon : Double = 22.0

///|
/// A file told of: its mark (44) where it has no extension, an extension said up to 12 letters.
pub let viewer_facts_icon : Double = 44.0

///|
/// A file told of's card, its extension in its middle: as wide, as high, and its corner.
pub let viewer_facts_card : (Double, Double, Double) = (64.0, 80.0, 14.0)

///|
/// How wide a file told of's buttons are, one over the other.
pub let viewer_facts_actions : Double = 240.0

///|
let viewer_ext_most : Int = 12

///|
let vfr_head_top : Double = 16.0

///|
let vfr_head_top_small : Double = 8.0

///|
let vfr_head_side : Double = 32.0

///|
let vfr_head_side_small : Double = 16.0

///|
let vfr_head_most : Double = 1080.0

///|
/// A file's extension, up to 12 letters, as capitals; "" for none (or a longer one).
pub fn file_ext(name : String) -> String {
  match lower(name).rev_find(".") {
    Some(i) if i > 0 && name.length() - i - 1 <= viewer_ext_most => {
      let b = StringBuilder()
      for ch in name.exact_view(start=i + 1) {
        b.write_char(if ch >= 'a' && ch <= 'z' { (ch.to_int() - 32).unsafe_to_char() } else { ch })
      }
      b.to_string()
    }
    _ => ""
  }
}

///|
/// A file told of's size and extension (file_ext), as a file told of says them under its name (the viewer's facts' node).
pub fn facts_size(name : String, size : Double) -> String {
  let ext = file_ext(name)
  if ext == "" {
    file_size(size)
  } else {
    file_size(size) + " · " + ext
  }
}
