// Tokens, glass recipes, vector icon shapes and shared helpers for the Liquid Glass overlay,
// navigation and feedback component family (Track B). All private identifiers are prefixed with
// `ovl_` to stay collision-free with parallel tracks.

///|
/// Three-anchor continuous optical interpolation for iOS 27.0 in-place liquid-droplet popover morphing:
/// - `stage == 0.0`: bar-pill anchor (`a=0x67`, `blur=2.5`, `bezel=14`, `refr=20`, `rim=0.60`);
/// - `stage == 0.5`: bright crystal mid-flight droplet (`a=0x4E`, `blur=1.6`, `bezel=18`, `refr=15`, `rim=0.78`);
/// - `stage == 1.0`: resting frosted menu anchor (`a=0xBF`, `blur=8.0`, `bezel=16`, `refr=22`, `rim=0.60`).
pub fn liquid_menu_morph_glass(
  stage : Double,
  solid? : Int64 = clear,
  dark? : Bool,
  merge? : Double = 0.0,
  layer? : Int = 0,
  break_gap? : Double = 0.0,
) -> @paint.Glass {
  let s = clamp(stage, 0.0, 1.0)
  let d = match dark {
    Some(v) => v
    None => is_dark()
  }
  let base_rgb = if d { 0x20202000L } else { 0xFDFCFD00L }
  let (a_f, blur, bezel, refraction, rim) = if s <= 0.5 {
    let u = s * 2.0
    (
      103.0 + (78.0 - 103.0) * u,
      2.5 + (1.6 - 2.5) * u,
      14.0 + (18.0 - 14.0) * u,
      20.0 + (15.0 - 20.0) * u,
      0.60 + (0.78 - 0.60) * u,
    )
  } else {
    let u = (s - 0.5) * 2.0
    (
      78.0 + (191.0 - 78.0) * u,
      1.6 + (8.0 - 1.6) * u,
      18.0 + (16.0 - 18.0) * u,
      15.0 + (22.0 - 15.0) * u,
      0.78 + (0.60 - 0.78) * u,
    )
  }
  let a = a_f.round().to_int64() & 0xFFL
  let resolved_solid = if solid != clear {
    solid
  } else if d {
    0x1C1C1EFFL
  } else {
    0xF7F7FAFFL
  }
  @paint.Glass::liquid(
    blur~,
    tint=base_rgb | a,
    solid=resolved_solid,
    saturation=1.0,
    rim~,
    bezel~,
    refraction~,
    chroma=0.0,
    merge~,
    layer~,
    break_gap~,
    adaptive=false,
  )
}

///|
/// Liquid glass material for floating panels (Menu, Popover, List, Disclosure).
/// Symmetric 75% high-readability liquid glass (`0xFDFCFDBFL` light / `0x202020BFL` dark).
pub fn liquid_panel_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=8.0,
    tint=if d { 0x202020BFL } else { 0xFDFCFDBFL },
    solid=if solid != clear { solid } else if d { 0x1C1C1EFFL } else { 0xF7F7FAFFL },
    saturation=1.0,
    rim=0.6,
    bezel=16.0,
    refraction=22.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// Liquid glass material for modal dialogs and dialog shells.
/// Symmetric 70% luminous liquid glass (`0xFDFCFDB3L` light / `0x202020B3L` dark) calibrated to iOS 26/27:
/// >= 5.7:1–9.7:1 contrast over high-contrast backdrops while preserving crisp bevel refraction and rim glint.
pub fn liquid_dialog_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=9.0,
    tint=if d { 0x202020B3L } else { 0xFDFCFDB3L },
    solid=if solid != clear { solid } else if d { 0x1C1C1EFFL } else { 0xF7F7FAFFL },
    saturation=1.0,
    rim=0.65,
    bezel=22.0,
    refraction=32.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// Liquid glass material for detached floating sheets and action sheets.
/// Symmetric 80% dense liquid glass (`0xFDFCFDCCL` light / `0x202020CCL` dark) for >= 4.5:1 body text contrast.
pub fn liquid_sheet_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=12.0,
    tint=if d { 0x202020CCL } else { 0xFDFCFDCCL },
    solid=if solid != clear { solid } else if d { 0x1C1C1EFFL } else { 0xF7F7FAFFL },
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
/// Liquid glass material for floating island side drawers (`r=28pt`, 10pt outer margin).
/// Symmetric 80% dense liquid glass (`0xFDFCFDCCL` light / `0x202020CCL` dark) with crisp bevel refraction.
pub fn liquid_drawer_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=12.0,
    tint=if d { 0x202020CCL } else { 0xFDFCFDCCL },
    solid=if solid != clear { solid } else if d { 0x1C1C1EFFL } else { 0xF7F7FAFFL },
    saturation=1.0,
    rim=0.6,
    bezel=22.0,
    refraction=36.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// Liquid glass material for floating toast capsules (`blur=2.1`, symmetric 75% tint, crisp 12/14 bevel).
pub fn liquid_toast_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=2.1,
    tint=if d { 0x202020BFL } else { 0xFDFCFDBFL },
    solid=if solid != clear { solid } else if d { 0x1E1F24FFL } else { 0xFAFAFAFFL },
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
/// Liquid glass material for capsule surfaces (Select trigger, Tooltip, NavBar, Toolbar).
pub fn liquid_capsule_glass(solid? : Int64 = clear) -> @paint.Glass {
  let d = is_dark()
  @paint.Glass::liquid(
    blur=3.0,
    tint=if d { 0x20202067L } else { 0xFDFCFD67L },
    solid=if solid != clear { solid } else if d { 0x1E1F24FFL } else { 0xFAFAFAFFL },
    saturation=1.0,
    rim=0.6,
    bezel=16.0,
    refraction=24.0,
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
/// Progressive blur soft scroll-edge backdrop (iOS 26 `UIScrollEdgeEffect.soft`): blurs and veils scrolled content
/// progressively across the host node's `View::fades` band (`blur=8.5`, 50% `bg` veil, `saturation=1.25`,
/// `progressive=true`), degrading to a solid `bg` alpha fade under `MBUI_GLASS=solid`.
pub fn liquid_scroll_edge_glass(bg? : Int64 = clear) -> @paint.Glass {
  let resolved = if bg != clear {
    bg
  } else if is_dark() {
    0x121212FFL
  } else {
    0xFFFFFFFFL
  }
  @paint.Glass::frosted(
    blur=8.5,
    tint=alpha(resolved, 0.50),
    solid=resolved,
    saturation=1.25,
    progressive=true,
  )
}

///|
/// 1pt hairline border used when `MBUI_GLASS=solid` degrades a floating glass overlay to opaque solid.
pub fn liquid_overlay_solid_edge() -> (Double, Int64) {
  if is_dark() { (1.0, 0xFFFFFF24L) } else { (1.0, 0x00000018L) }
}

///|
fn ovl_panel_glass() -> @paint.Glass {
  liquid_panel_glass()
}

///|
fn ovl_sheet_glass() -> @paint.Glass {
  liquid_sheet_glass()
}

///|
/// Liquid glass material for floating sheets that morph smoothly from a detached glass island
/// (`detent = 0.0`, 80% symmetric `0xCC`) into a high-readability full-height liquid glass surface
/// (`detent = 1.0`, 86% symmetric `0xDC`) in both light and dark modes, keeping soft specular rim
/// and subtle backdrop translucency.
fn ovl_sheet_glass_at(detent : Double) -> @paint.Glass {
  let t = clamp(detent, 0.0, 1.0)
  if t <= 0.001 {
    return ovl_sheet_glass()
  }
  let d = is_dark()
  let a = (lerp(204.0, 220.0, t).round()).to_int64() & 0xFFL
  let tint = if d { 0x20202000L | a } else { 0xFDFCFD00L | a }
  @paint.Glass::liquid(
    blur=lerp(12.0, 16.0, t),
    tint~,
    solid=if d { 0x1C1C1EFFL } else { 0xF7F7FAFFL },
    saturation=1.0,
    rim=lerp(0.6, 0.45, t),
    bezel=lerp(20.0, 14.0, t),
    refraction=lerp(24.0, 18.0, t),
    chroma=0.0,
    merge=0.0,
    adaptive=false,
  )
}

///|
fn ovl_solid_edge() -> (Double, Int64) {
  liquid_overlay_solid_edge()
}

///|
fn ovl_capsule_glass() -> @paint.Glass {
  liquid_capsule_glass()
}

///|
/// Subtle translucent hover ground inside a glass surface (zero glass-on-glass).
fn ovl_row_hover() -> Int64 {
  if is_dark() { 0xFFFFFF18L } else { 0x00000012L }
}

///|
/// Subtle translucent pressed ground inside a glass surface.
fn ovl_row_press() -> Int64 {
  if is_dark() { 0xFFFFFF26L } else { 0x0000001FL }
}

///|
/// Subtle translucent selected ground inside a glass surface.
fn ovl_row_selected() -> Int64 {
  if is_dark() { 0x0091FF24L } else { 0x0088FF1AL }
}

///|
/// Translucent ground for an icon-only circular close button inside a glass surface.
fn ovl_close_ground() -> Int64 {
  if is_dark() { 0xFFFFFF1CL } else { 0x00000014L }
}

///|
/// Translucent ground for a secondary capsule action button inside a toast or sheet.
fn ovl_action_pill_ground() -> Int64 {
  if is_dark() { 0xFFFFFF22L } else { 0x00000016L }
}

///|
/// Hairline separator color inside glass surfaces.
fn ovl_hairline() -> Int64 {
  if is_dark() { 0xFFFFFF1FL } else { 0x0000001AL }
}

///|
/// Top grabber pill color inside a detached floating sheet.
fn ovl_grabber_color() -> Int64 {
  if is_dark() { 0xFFFFFF40L } else { 0x00000033L }
}

///|
/// Secondary / muted text ink with >= 4.5:1 contrast on light and dark glass solid fallbacks.
fn ovl_muted_ink() -> Int64 {
  if is_dark() { 0xFFFFFFB8L } else { 0x000000A8L }
}

///|
/// Destructive semantic ink with >= 4.5:1 contrast on light and dark glass surfaces.
fn ovl_destructive() -> Int64 {
  if is_dark() { 0xFF6961FFL } else { 0xA80010FFL }
}

///|
/// Accessible accent ink for progress indicators and selection checkmarks (>= 4.5:1 contrast).
fn ovl_accent_ink() -> Int64 {
  if is_dark() { 0x4DA6FFFFL } else { 0x0066CCFFL }
}

///|
/// Progress track background color.
fn ovl_track_color() -> Int64 {
  if is_dark() { 0x78788052L } else { 0x78788029L }
}

///|
/// Semantic status color for toast badges and icons.
fn ovl_status_color(status : LiquidStatus) -> Int64 {
  let d = is_dark()
  match status {
    Info => if d { 0x4DA6FFFFL } else { 0x0066CCFFL }
    Success => if d { 0x4CD964FFL } else { 0x1B7E38FFL }
    Warning => if d { 0xFFB340FFL } else { 0x9E5A00FFL }
    Error => ovl_destructive()
  }
}

///|
/// Disabled control opacity.
let ovl_disabled_alpha : Double = 0.45

///|
/// Focus ring stroke width and outset.
let ovl_focus_stroke : Double = 2.0

///|
let ovl_focus_outset : Double = 3.0

///|
/// Hairline thickness.
let ovl_hairline_h : Double = 1.0

///|
/// Floating overlay gap from its anchor and viewport safe padding.
let ovl_float_gap : Double = 8.0

///|
let ovl_float_pad : Double = 8.0

///|
/// Menu concentric geometry: outer radius 22pt, padding 6pt -> inner item radius 16pt.
let ovl_menu_radius : Double = 22.0

///|
let ovl_menu_pad : Double = 6.0

///|
let ovl_menu_item_radius : Double = 16.0

///|
let ovl_menu_item_h : Double = 38.0

///|
let ovl_menu_item_px : Double = 12.0

///|
let ovl_menu_item_py : Double = 6.0

///|
let ovl_menu_item_gap : Double = 10.0

///|
/// Vertical breathing gap between menu/select items so active and hovered pills never touch.
let ovl_menu_item_gap_y : Double = 2.0

///|
let ovl_menu_sep_px : Double = 10.0

///|
let ovl_menu_sep_py : Double = 4.0

///|
let ovl_menu_icon_size : Double = 16.0

///|
let ovl_menu_check_w : Double = 16.0

///|
/// Select trigger capsule geometry (matches `button_h = 48pt` so side-by-side controls align).
let ovl_select_h : Double = 48.0

///|
let ovl_select_px : Double = 16.0

///|
let ovl_select_radius : Double = 24.0

///|
let ovl_select_gap : Double = 8.0

///|
let ovl_select_chevron : Double = 14.0

///|
/// Popover geometry.
let ovl_popover_radius : Double = 22.0

///|
let ovl_popover_pad : Double = 16.0

///|
/// Tooltip geometry.
let ovl_tooltip_radius : Double = 12.0

///|
let ovl_tooltip_px : Double = 12.0

///|
let ovl_tooltip_py : Double = 6.0

///|
let ovl_tooltip_max_w : Double = 260.0

///|
/// Detached floating sheet geometry (r=28pt floating -> narrow-screen docked top r=24pt / bottom r=0pt).
let ovl_sheet_radius : Double = 28.0

///|
let ovl_sheet_expanded_top_radius : Double = 24.0

///|
let ovl_sheet_inset : Double = 10.0

///|
let ovl_sheet_wide_inset : Double = 12.0

///|
let ovl_sheet_pad : Double = 20.0

///|
/// Concentric footer inset inside a 28pt sheet (`12pt + 16pt capsule button radius == 28pt`).
let ovl_sheet_footer_pad : Double = 12.0

///|
let ovl_sheet_gap : Double = 12.0

///|
let ovl_sheet_grabber_w : Double = 36.0

///|
let ovl_sheet_grabber_h : Double = 4.0

///|
let ovl_sheet_hdr_pr : Double = 12.0

///|
let ovl_sheet_hdr_pr_expanded : Double = 8.0

///|
let ovl_sheet_drag_dismiss : Double = 80.0

///|
let ovl_sheet_drag_vel : Double = 0.45

///|
let ovl_sheet_overpull_max : Double = 20.0

///|
/// Floating island side drawer geometry (10pt floating margin, r=28pt, 12pt concentric header/body/footer pad).
let ovl_drawer_inset : Double = 10.0

///|
let ovl_drawer_radius : Double = 28.0

///|
let ovl_drawer_pad : Double = 12.0

///|
let ovl_drawer_hdr_pl : Double = 16.0

///|
let ovl_drawer_scrim_alpha : Double = 0.18

///|
let ovl_drawer_overpull_max : Double = 16.0

///|
let ovl_drawer_dismiss_ratio : Double = 0.32

///|
let ovl_drawer_dismiss_vel : Double = 0.45

///|
let ovl_drawer_leave_ms : Double = 320.0

///|
let ovl_close_btn_size : Double = 32.0

///|
let ovl_close_icon_size : Double = 12.0

///|
/// ActionSheet geometry (r=28pt, pad=8pt -> item r=20pt).
let ovl_action_radius : Double = 28.0

///|
let ovl_action_pad : Double = 8.0

///|
let ovl_action_item_radius : Double = 20.0

///|
let ovl_action_item_h : Double = 52.0

///|
let ovl_action_gap : Double = 10.0

///|
let ovl_action_hdr_px : Double = 16.0

///|
let ovl_action_hdr_py : Double = 12.0

///|
/// Toast capsule geometry (r=24pt, top/end inset 9pt -> 30×30 r=15pt close button concentric).
let ovl_toast_radius : Double = 24.0

///|
let ovl_toast_px : Double = 16.0

///|
let ovl_toast_pr : Double = 9.0

///|
let ovl_toast_py : Double = 9.0

///|
let ovl_toast_gap : Double = 12.0

///|
let ovl_toast_icon_size : Double = 20.0

///|
let ovl_toast_action_h : Double = 30.0

///|
let ovl_toast_action_px : Double = 12.0

///|
let ovl_toast_close_size : Double = 30.0

///|
/// First-line vertical centering offsets for icons/chevrons beside 15pt body text (line=21pt).
let ovl_first_line_icon_pt : Double = 0.5

///|
let ovl_first_line_chevron_pt : Double = 3.5

///|
let ovl_first_line_sub_pt : Double = 1.4

///|
/// Progress bar geometry.
let ovl_progress_gap : Double = 6.0

///|
let ovl_progress_sweep_w : Double = 0.36

///|
/// NavBar & Toolbar geometry (nav_bar h=56 r=28, pad_x=10 -> 36pt trailing/leading pill r=18 is exact concentric).
let ovl_nav_px : Double = 10.0

///|
let ovl_nav_gap : Double = 12.0

///|
let ovl_toolbar_px : Double = 12.0

///|
let ovl_toolbar_gap : Double = 8.0

///|
/// Grouped inset List geometry (r=24pt, pad=6pt -> row r=18pt).
let ovl_list_radius : Double = 24.0

///|
let ovl_list_pad : Double = 6.0

///|
let ovl_list_row_radius : Double = 18.0

///|
let ovl_list_row_min_h : Double = 48.0

///|
let ovl_list_row_px : Double = 14.0

///|
let ovl_list_row_py : Double = 10.0

///|
let ovl_list_row_gap : Double = 12.0

///|
let ovl_list_sep_inset : Double = 14.0

///|
/// Vertical breathing padding above/below each hairline divider in a grouped list (`3 + 1 + 3 = 7pt`), so a hovered
/// or active row's pill never touches the divider beside it.
let ovl_list_sep_py : Double = 3.0

///|
/// A quarter turn in radians (`π / 2`, 90°): `View::turn` takes radians.
let ovl_turn_quarter : Double = 1.5707963267948966

///|
/// A half turn in radians (`π`, 180°): `View::turn` takes radians.
let ovl_turn_half : Double = 3.141592653589793

///|
/// Vertical row gap in sidebar / divider-free list mode (`dividers=false`).
let ovl_list_gap_nodiv : Double = 4.0

///|
let ovl_list_meta_px : Double = 16.0

///|
let ovl_list_meta_py : Double = 6.0

///|
let ovl_list_chevron : Double = 14.0

///|
/// Disclosure card geometry (r=22pt, pad=6pt -> header r=16pt).
let ovl_disc_radius : Double = 22.0

///|
let ovl_disc_pad : Double = 6.0

///|
let ovl_disc_hdr_radius : Double = 16.0

///|
let ovl_disc_hdr_px : Double = 14.0

///|
let ovl_disc_hdr_py : Double = 12.0

///|
let ovl_disc_body_px : Double = 14.0

///|
let ovl_disc_body_py : Double = 12.0

///|
let ovl_disc_chevron : Double = 14.0

///|
/// Typography sizes for overlay, navigation and feedback parts.
let ovl_type_title : Double = 19.0

///|
let ovl_type_heading : Double = 16.0

///|
let ovl_type_body : Double = 15.0

///|
let ovl_type_sub : Double = 13.0

///|
let ovl_type_meta : Double = 12.0

///|
let ovl_weight_semibold : Int = 600

///|
/// Default spacing for stacked title/subtitle pairs.
let ovl_text_gap : Double = 2.0

///|
/// Map `@headless.Placement` to `View::beside` `(Side, Along)`.
fn ovl_beside_of(p : @headless.Placement) -> (@view.Side, @view.Along) {
  match p {
    BelowStart => (Bottom, Start)
    BelowCenter => (Bottom, Middle)
    BelowEnd => (Bottom, End)
    AboveStart => (Top, Start)
    AboveCenter => (Top, Middle)
    AboveEnd => (Top, End)
    RightStart => (Right, Start)
    RightCenter => (Right, Middle)
    RightEnd => (Right, End)
    LeftStart => (Left, Start)
    LeftCenter => (Left, Middle)
    LeftEnd => (Left, End)
  }
}

///|
/// Concentric focus ring drawn around an interactive control when focus is keyboard-visible.
fn ovl_focus_ring(parent : @view.View, shown : () -> Bool, radius : Double) -> Unit {
  parent.show(shown, fn(ring) {
    ring
    .over(Is(true))
    .points(Is(false))
    .margin(Is((-ovl_focus_outset, -ovl_focus_outset, -ovl_focus_outset, -ovl_focus_outset)))
    .radius(Is(radius + ovl_focus_outset))
    .edge(By(fn() { (ovl_focus_stroke, colors().accent) }))
    |> ignore
  })
}

///|
/// Smooth hover + press + optional selected ground inside a glass container using closed-form
/// `@motion.hover_fade` (avoids raw hover ground snapping).
fn ovl_attach_row_ground(
  node : @view.View,
  hovered : () -> Bool,
  pressed : () -> Bool,
  selected? : () -> Bool = fn() { false },
  disabled? : () -> Bool = fn() { false },
) -> Unit {
  let hover_t = @motion.hover_fade(node, fn() { hovered() && !disabled() })
  let press_t = @motion.hover_fade(node, fn() { pressed() && !disabled() }, duration_ms=@motion.pointer_tap_ms)
  node
  .ground(
    By(fn() {
      let base = if selected() { ovl_row_selected() } else { clear }
      let h = hover_t()
      let p = press_t()
      let with_hover = if h > 0.001 { over(base, alpha(ovl_row_hover(), h)) } else { base }
      if p > 0.001 {
        over(with_hover, alpha(ovl_row_press(), p))
      } else {
        with_hover
      }
    }),
  )
  |> ignore
}

///|
/// Vector checkmark glyph (`size × size`).
fn ovl_check_shapes(size : Double, color : Int64) -> Array[@paint.Shape] {
  let s = size / 16.0
  let pts : Array[Double] = [3.0 * s, 8.5 * s, 6.5 * s, 12.0 * s, 13.0 * s, 4.5 * s]
  [@paint.shape_of([(pts, false)], stroke=color, width=1.8 * s)]
}

///|
/// Vector downward chevron glyph (`size × size`).
fn ovl_chevron_down_shapes(size : Double, color : Int64) -> Array[@paint.Shape] {
  let s = size / 16.0
  let pts : Array[Double] = [3.5 * s, 6.0 * s, 8.0 * s, 10.5 * s, 12.5 * s, 6.0 * s]
  [@paint.shape_of([(pts, false)], stroke=color, width=1.6 * s)]
}

///|
/// Vector rightward chevron glyph (`size × size`).
fn ovl_chevron_right_shapes(size : Double, color : Int64) -> Array[@paint.Shape] {
  let s = size / 16.0
  let pts : Array[Double] = [6.0 * s, 3.5 * s, 10.5 * s, 8.0 * s, 6.0 * s, 12.5 * s]
  [@paint.shape_of([(pts, false)], stroke=color, width=1.6 * s)]
}

///|
/// Vector close (`×`) glyph (`size × size`).
fn ovl_close_shapes(size : Double, color : Int64) -> Array[@paint.Shape] {
  let s = size / 16.0
  let a : Array[Double] = [4.0 * s, 4.0 * s, 12.0 * s, 12.0 * s]
  let b : Array[Double] = [12.0 * s, 4.0 * s, 4.0 * s, 12.0 * s]
  [@paint.shape_of([(a, false), (b, false)], stroke=color, width=1.8 * s)]
}

///|
/// Vector circle polyline centered at `(cx, cy)` with radius `r`.
fn ovl_arc_pts(cx : Double, cy : Double, r : Double, from : Double, to : Double, steps : Int) -> Array[Double] {
  let n = if steps < 4 { 4 } else { steps }
  let pts : Array[Double] = []
  for i in 0..=n {
    let a = from + (to - from) * i.to_double() / n.to_double()
    pts.push(cx + r * @dmath.cos(a))
    pts.push(cy + r * @dmath.sin(a))
  }
  pts
}

///|
/// Vector status badge icon (`size × size`) for `LiquidStatus`.
fn ovl_status_shapes(status : LiquidStatus, size : Double, color : Int64) -> Array[@paint.Shape] {
  let s = size / 20.0
  let pi = 3.141592653589793
  let w = 1.7 * s
  match status {
    Info => {
      let ring = ovl_arc_pts(10.0 * s, 10.0 * s, 8.0 * s, 0.0, 2.0 * pi, 32)
      let dot : Array[Double] = [10.0 * s, 6.2 * s, 10.0 * s, 6.8 * s]
      let stem : Array[Double] = [10.0 * s, 9.2 * s, 10.0 * s, 14.0 * s]
      [@paint.shape_of([(ring, true), (dot, false), (stem, false)], stroke=color, width=w)]
    }
    Success => {
      let ring = ovl_arc_pts(10.0 * s, 10.0 * s, 8.0 * s, 0.0, 2.0 * pi, 32)
      let chk : Array[Double] = [6.2 * s, 10.2 * s, 8.8 * s, 12.8 * s, 14.0 * s, 7.4 * s]
      [@paint.shape_of([(ring, true), (chk, false)], stroke=color, width=w)]
    }
    Warning => {
      let tri : Array[Double] = [10.0 * s, 2.8 * s, 17.6 * s, 16.4 * s, 2.4 * s, 16.4 * s]
      let bar : Array[Double] = [10.0 * s, 7.5 * s, 10.0 * s, 11.8 * s]
      let dot : Array[Double] = [10.0 * s, 14.0 * s, 10.0 * s, 14.6 * s]
      [@paint.shape_of([(tri, true), (bar, false), (dot, false)], stroke=color, width=w)]
    }
    Error => {
      let ring = ovl_arc_pts(10.0 * s, 10.0 * s, 8.0 * s, 0.0, 2.0 * pi, 32)
      let a : Array[Double] = [7.0 * s, 7.0 * s, 13.0 * s, 13.0 * s]
      let b : Array[Double] = [13.0 * s, 7.0 * s, 7.0 * s, 13.0 * s]
      [@paint.shape_of([(ring, true), (a, false), (b, false)], stroke=color, width=w)]
    }
  }
}

///|
/// Vector progress ring shapes: track circle + active arc (determinate or spinning indeterminate).
fn ovl_ring_shapes(
  size : Double,
  stroke : Double,
  start_turn : Double,
  sweep_turn : Double,
  color : Int64,
  track : Int64,
) -> Array[@paint.Shape] {
  let mid = size / 2.0
  let r = if size / 2.0 - stroke / 2.0 > 1.0 { size / 2.0 - stroke / 2.0 } else { 1.0 }
  let pi = 3.141592653589793
  let full = ovl_arc_pts(mid, mid, r, 0.0, 2.0 * pi, 48)
  let shapes : Array[@paint.Shape] = [@paint.shape_of([(full, true)], stroke=track, width=stroke)]
  let clamped = clamp(sweep_turn, 0.0, 1.0)
  if clamped > 0.001 {
    let from = -0.5 * pi + start_turn * 2.0 * pi
    let to = from + clamped * 2.0 * pi
    shapes.push(@paint.shape_of([(ovl_arc_pts(mid, mid, r, from, to, 48), false)], stroke=color, width=stroke))
  }
  shapes
}

///|
/// Mirrors a reactive boolean `open` onto a transition-scoped signal within `scope`, so `View::show(..., leave=...)`
/// always runs its full closing animation inside `@ui.run_tree` (`transitions_only=true`) apps regardless of whether
/// callers wrap `set_open(false)` in `@view.transition`.
fn ovl_transitioned_bool(scope : @view.View, open : () -> Bool) -> () -> Bool {
  let shown = @signals.signal(@signals.untracked(open))
  scope.reacts(
    open,
    fn(on) { @view.transition(within=scope, fn() { shown.set(on) }) },
    at_start=false,
  )
  fn() { shown.get() }
}
