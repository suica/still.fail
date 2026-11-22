// still.fail's glass (web mobile/styles/pages.css.ts and ui/styles/glass.ts), as
// @ui.Glass for a box's `glass=`. Haze's blur radius is cssBlur(px) = (px - 0.5) / 0.57735 dp, which RenderEffect
// takes as a deviation of px dp: CSS blur(px)'s, what @ui.Glass's blur is. Each has its solid ground for where the
// system asks for less transparency: what the glass would be with nothing under it (the page's paper under its tint).

///|
/// A bar at the top of a page over the list running under it (TopGlassBar; mGlass): the page's paper
/// at 70% over a 24px blur, no line along its foot: the frost alone sets it off (2026-10-24, asked).
pub fn glass_bar() -> @ui.Glass {
  let t = theme()
  @ui.Glass::frosted(blur=24.0, tint=alpha(t.p.bg, 0.7), solid=t.p.bg)
}

///|
/// The same glass as a band along the page's foot (Glass.kt glassFoot: a new chat's choices and composer stand on
/// it), no line.
pub fn glass_foot() -> @ui.Glass {
  glass_bar()
}

///|
/// A capsule floating over the list (mFloating, the composer's): iOS 27 liquid glass (`ios27Dark` / `ios27Light`
/// neutral tint when `tint` is `None`, or caller-supplied `tint` such as drag-over accent), its blur, bezel and
/// refraction the small screen's bottom bar's (`glass_tab_bar`) so the composer and the bar read as one glass;
/// `solid` preserves the opaque raised fallback under `MBUI_GLASS=solid`; `spot`, where a press lights it (points from
/// its top left: float_pill_group_node's).
pub fn glass_floating(tint? : Int64, spot? : (Double, Double)? = None) -> @ui.Glass {
  let t = theme()
  let solid = over(t.p.bg, alpha(tint.unwrap_or(t.p.raised), 0.72))
  @lg.liquid_floating_glass(tint~, solid~, spot~)
}

///|
/// Single-layer iOS 27 liquid glass for anchored popovers (`anchored_popover_shell`: menus, panels, picks, hover panels; `small_panel_node`).
pub fn glass_menu(merge? : Double = 0.0) -> @ui.Glass {
  let t = theme()
  @ui.Glass::liquid(
    blur=8.0,
    tint=if t.dark { 0x202020BFL } else { 0xFDFCFDBFL },
    solid=panel_ground(),
    saturation=1.0,
    rim=0.6,
    bezel=16.0,
    refraction=22.0,
    chroma=0.0,
    merge~,
    adaptive=false,
  )
}

///|
/// Three-anchor continuous optical interpolation for iOS 27.0 in-place liquid-droplet popover morphing:
/// - `stage == 0.0`: bar-pill anchor, bit-identical to `glass_bar_pill` (`a=0x67`, `blur=2.5`, `bezel=14`, `refr=20`, `rim=0.60`);
/// - `stage == 0.5`: crisp luminous crystal droplet (`a=0x4E`, `blur=1.6`, `bezel=18`, `refr=15`, `rim=0.78`;
///   `refr/bezel=0.83 < 1.0` prevents fold-over while matching native iOS 27.0 bright crystal refraction);
/// - `stage == 1.0`: resting frosted menu anchor, bit-identical to `glass_menu` (`a=0xBF`, `blur=8.0`, `bezel=16`, `refr=22`, `rim=0.60`).
/// Alpha stays strictly within `0x4E..0xBF` (at or above `kind == 6`'s `regMix` upper knee) for zero flash.
fn glass_menu_morph(
  stage : Double,
  merge? : Double = 0.0,
  layer? : Int = 0,
  break_gap? : Double = 0.0,
) -> @ui.Glass {
  @lg.liquid_menu_morph_glass(
    stage,
    solid=panel_ground(),
    dark=theme().dark,
    merge~,
    layer~,
    break_gap~,
  )
}

///|
/// Single-layer iOS 27 liquid glass for floating toast capsules (`toaster_node`): light translucent glass with
/// dark ink in Light mode, dark translucent glass with light ink in Dark mode.
pub fn glass_toast() -> @ui.Glass {
  let t = theme()
  @ui.Glass::liquid(
    blur=2.1,
    tint=if t.dark { 0x202020BFL } else { 0xFDFCFDBFL },
    solid=if t.dark { 0x1E1F24FFL } else { 0xFAFAFAFFL },
    saturation=1.0,
    rim=0.6,
    bezel=12.0,
    refraction=14.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// High-translucency neutral single-layer iOS 27 liquid glass for floating controls over media (`viewer_steps_node`,
/// `viewer_page_glass`): desaturated backdrop (`saturation=0.55`, `blur=4.0`) prevents vivid saturated photos from
/// turning circular discs into colored stickers while keeping crisp 9/12 bezel refraction, specular rim, and legible
/// `<` / `>` chevrons in both Light and Dark themes.
pub fn glass_viewer_clear(spot? : (Double, Double)? = None) -> @ui.Glass {
  @lg.liquid_viewer_clear_glass(spot~, solid=theme().p.canvas)
}

///|
/// Dark translucent liquid glass for floating white-ink media viewer capsules (`dark_glass` / `viewer_marks_node`):
/// neutral dark iOS 27 glass with controlled saturation (`0.65`) and 9/12 liquid bevel refraction.
pub fn glass_viewer_dark(spot? : (Double, Double)? = None) -> @ui.Glass {
  @lg.liquid_viewer_dark_glass(spot~)
}

///|
/// The bottom bar's glass: iOS 27 regular liquid glass calibrated for 56pt controls (flutter_liquid_glass
/// ios27Light / ios27Dark: uniform 2.1pt Gaussian blur across center and rim, quarter-circle bevel refraction,
/// adaptive color transfer, inner bevel shadow, glint, and 0.75pt external contour); where glass is drawn solid,
/// its opaque ground.
pub fn glass_tab_bar(spot? : (Double, Double)? = None, merge? : Double = 0.0) -> @ui.Glass {
  @lg.liquid_tab_bar_glass(spot~, merge~)
}

///|
/// The bottom bar's shadow by theme: delegates to `glass_control_shadow()` so all persistent liquid glass controls
/// share one calibrated outside-only shadow.
pub fn tab_bar_shadow() -> Raised {
  let (sigma, dy, color) = glass_control_shadow()
  { sigma, dy, color }
}

///|
/// The pill under the place shown inside glass: black at 7.1% on light grounds, white at 12% in the dark.
pub fn glass_selection() -> Int64 {
  if theme().dark {
    0xFFFFFF1FL
  } else {
    0x00000012L
  }
}

///|
/// The bar's ball held (the lens over the places, iOS 27 clear loupe): clear liquid glass, its rim bending the places
/// under it with subtle chromatic dispersion.
fn glass_lens() -> @ui.Glass {
  let t = theme()
  @ui.Glass::liquid(
    blur=0.0,
    tint=0xFFFFFF00L,
    solid=over(t.p.bg, alpha(t.p.raised, 0.72)),
    saturation=1.0,
    rim=0.6,
    bezel=10.0,
    refraction=12.0,
    chroma=-0.06,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// A control's knob held (a switch's, a segmented choice's thumb): the bar's clear lens, its rim narrower and bending
/// less, as small as it is.
pub fn glass_knob() -> @ui.Glass {
  { ..glass_lens(), bezel: 7.0, refraction: 5.0 }
}

///|
/// Clear lifted liquid glass lens while a tab bar / segmented control thumb is held (iOS 27 clear loupe).
pub fn glass_tab_lens(press : Double) -> @ui.Glass {
  @lg.liquid_tab_lens_glass(press, solid=theme().p.raised)
}

///|
/// The shadow under the bottom bar's lens (blur sigma 12, 4 down, black at 10%): the lens's look fades it in with
/// the lens as it is pressed.
pub let tab_lens_raised : Raised = { sigma: 12.0, dy: 4.0, color: 0x0000001AL }

///|
fn track_glass_ink() -> Int64 {
  if theme().dark { 0x7878805CL } else { 0x78787833L }
}

///|
/// How far a sheet reaches on under the window's foot (sheet_node's: its foot's corners out of sight).
let sheet_under : Double = pane_corner

///|
/// The scrim under a sheet at its fullest: black at 28%.
pub let sheet_scrim : Int64 = 0x00000047L

///|
/// A sheet or floating side drawer over the page: single-layer symmetric 80% iOS 26 liquid glass (`0xFDFCFDCC` in
/// Light, `0x202020CC` in Dark, aligned with PR #8057 symmetric density curve; `blur=12`, `bezel=20`,
/// `refraction=24`). Degrades to opaque `t.p.bg` under `MBUI_GLASS=solid`.
pub fn glass_sheet() -> @ui.Glass {
  let t = theme()
  @ui.Glass::liquid(
    blur=12.0,
    tint=if t.dark { 0x202020CCL } else { 0xFDFCFDCCL },
    solid=t.p.bg,
    saturation=1.0,
    rim=0.6,
    bezel=20.0,
    refraction=24.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// Progressive blur soft scroll-edge backdrop (iOS 26 UIScrollEdgeEffect.soft): blurs and veils scrolled content
/// progressively across the host node's `View::fades` band (blur sigma 0 -> 8.5pt, `p.bg` veil 0 -> 50% with
/// adaptive contrast boost over opposing-luminance content, vibrancy saturation 1.25), degrading to a solid
/// `p.bg` alpha fade under `MBUI_GLASS=solid`. `ground`: the ground it veils into where that is not `p.bg` (a page's
/// panel a step darker behind the one in use); none (0) is `p.bg`.
pub fn glass_scroll_edge(ground? : Int64 = 0L) -> @ui.Glass {
  let t = theme()
  let bg = if ground != 0L { ground } else { t.p.bg }
  @ui.Glass::frosted(
    blur=8.5,
    tint=alpha(bg, 0.50),
    solid=bg,
    saturation=1.25,
    progressive=true,
  )
}
