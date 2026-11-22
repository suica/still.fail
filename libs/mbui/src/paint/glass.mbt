// Glass, as it is said (what is drawn of it, its capture and its run, is the host's: ui's glass.mbt).


///|
/// How a glass box looks. `blur` is CSS blur()'s deviation, in logical px;
/// `tint` is laid over the frost (its alpha how much); `saturation` as CSS
/// saturate(); `solid` is the ground drawn instead where the system asks for
/// less transparency (or MBUI_GLASS=solid).
#derive(Eq, Debug)
pub(all) struct Glass {
  blur : Double
  tint : Int64
  saturation : Double
  solid : Int64
  // the rim, frosted: a hairline inside the edge, light along the top and
  // left, less along the foot and right (white's alpha each)
  rim_edge : Double
  rim_lit : Double
  rim_back : Double
  // liquid
  liquid : Bool
  rim : Double
  bezel : Double
  refraction : Double
  chroma : Double
  merge : Double
  adaptive : Bool
  // frosted: frosts what the glass before it frosts (its capture), not what
  // has been drawn since
  shares_capture : Bool
  // frosted: frosts only what is under its own box, its edges carried on
  // past them (CSS backdrop-filter's), so nothing round it bleeds in at its
  // rim: a picture's frost (a message's image coming in)
  contained : Bool
  // liquid: where the pointer is over it, in points from its own top left (View::pointer_here's), a light drawn
  // there along its rim and over its face; None: none
  spot : (Double, Double)?
  // liquid: optical magnification factor of the backdrop inside a clear lens (1.0: none, up to 3.0; active when
  // `liquid` is true and `blur <= 0.0`)
  zoom : Double
  // continuous materialisation strength in [0.0, 1.0] (0.0: fully flat / no glass emitted; 1.0: full glass)
  strength : Double
  // frosted: progressive / variable blur modulated by the node's `View::fades` ramp (0 -> blur, 0 -> tint/sat)
  progressive : Bool
  // liquid auto-merge layer (> 0 participates in framework same-layer proximity fusion; 0 keeps manual adjacency)
  layer : Int
  // physical edge-gap break threshold (pt) for same-layer liquid fusion (<= 0 defaults to merge * 0.25)
  break_gap : Double
}

///|
/// Frosted glass: what is under it blurred by `blur` (CSS px), `tint` over it.
pub fn Glass::frosted(
  blur~ : Double,
  tint~ : Int64,
  solid~ : Int64,
  saturation? : Double = 1.0,
  rim_edge? : Double = 0.0,
  rim_lit? : Double = 0.0,
  rim_back? : Double = 0.0,
  shares_capture? : Bool = false,
  contained? : Bool = false,
  progressive? : Bool = false,
  strength? : Double = 1.0,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge,
    rim_lit,
    rim_back,
    liquid: false,
    rim: 0.0,
    bezel: 0.0,
    refraction: 0.0,
    chroma: 0.0,
    merge: 0.0,
    adaptive: false,
    shares_capture,
    contained,
    spot: None,
    zoom: 1.0,
    strength: dclamp(strength, 0.0, 1.0),
    progressive,
    layer: 0,
    break_gap: 0.0,
  }
}

///|
/// The same glass frosting what the glass painted before it in this frame frosts (its capture, at that glass's
/// blur), whatever has been drawn since, over that glass too: a ball over a bar, both of the page under them.
pub fn Glass::sharing(self : Glass) -> Glass {
  { ..self, shares_capture: true }
}

///|
/// Liquid glass (iOS 27 optical model, ported from flutter_liquid_glass): uniform blurred backdrop across center and
/// rim, quarter-circle bevel refraction (`bezel` wide, up to `refraction` px displacement, chromatic dispersion
/// `chroma`), adaptive iOS 27 light/dark/clear color transfer, inner bevel shadow, glint (`rim`), and 0.75pt external
/// contour; text in it inked by what is under it (`adaptive`); shapes of one `glass_group` within `merge` of each
/// other flow into one; `spot`, where the pointer is over it (points from its top left), lights its rim and face round
/// that point.
pub fn Glass::liquid(
  blur? : Double = 1.0,
  tint? : Int64 = 0xFFFFFF1AL,
  solid? : Int64 = 0xECECF0FFL,
  saturation? : Double = 1.3,
  rim? : Double = 0.55,
  bezel? : Double = 14.0,
  refraction? : Double = 9.0,
  chroma? : Double = 0.18,
  merge? : Double = 16.0,
  adaptive? : Bool = true,
  spot? : (Double, Double)? = None,
  zoom? : Double = 1.0,
  strength? : Double = 1.0,
  layer? : Int = 0,
  break_gap? : Double = 0.0,
) -> Glass {
  {
    blur,
    tint,
    saturation,
    solid,
    rim_edge: 0.0,
    rim_lit: 0.0,
    rim_back: 0.0,
    liquid: true,
    rim,
    bezel,
    refraction,
    chroma,
    merge,
    adaptive,
    shares_capture: false,
    contained: false,
    spot,
    zoom,
    strength: dclamp(strength, 0.0, 1.0),
    progressive: false,
    layer,
    break_gap,
  }
}

///|
/// Scale this glass's materialisation continuously by `t` in `[0.0, 1.0]` for smooth flat-to-glass transitions
/// (clamping spring overshoots). `bezel` keeps its full width so the bevel never collapses into a sharp hairline,
/// while optical effects (`blur`, `refraction`, `rim`, `chroma`, `saturation`, `zoom`) and `strength` scale smoothly.
pub fn Glass::at_strength(self : Glass, t : Double) -> Glass {
  let t = dclamp(t, 0.0, 1.0)
  if t >= 0.9999 {
    return self
  }
  {
    ..self,
    blur: self.blur * t,
    refraction: self.refraction * t,
    rim: self.rim * t,
    chroma: self.chroma * t,
    rim_edge: self.rim_edge * t,
    rim_lit: self.rim_lit * t,
    rim_back: self.rim_back * t,
    saturation: 1.0 + (self.saturation - 1.0) * t,
    zoom: 1.0 + (self.zoom - 1.0) * t,
    strength: self.strength * t,
  }
}

///|
/// Clear liquid glass (iOS 27 standalone translucent variant over media/photos): zero backdrop blur with a subtle
/// +0.126 white micro-veil (`tint` alpha ≈ 0.102) and pronounced edge refraction (`refraction=16.0`), distinct from
/// pure zero-veil optical lenses (`tint=0xFFFFFF00L`).
pub fn Glass::clear(
  blur? : Double = 0.0,
  tint? : Int64 = 0xFFFFFF1AL,
  solid? : Int64 = 0xECECF0FFL,
  saturation? : Double = 1.0,
  rim? : Double = 0.6,
  bezel? : Double = 14.0,
  refraction? : Double = 16.0,
  chroma? : Double = 0.0,
  merge? : Double = 16.0,
  adaptive? : Bool = true,
  spot? : (Double, Double)? = None,
  zoom? : Double = 1.0,
  strength? : Double = 1.0,
) -> Glass {
  Glass::liquid(
    blur~,
    tint~,
    solid~,
    saturation~,
    rim~,
    bezel~,
    refraction~,
    chroma~,
    merge~,
    adaptive~,
    spot~,
    zoom~,
    strength~,
  )
}

///|
/// Foreground optical lens (`kind == 8`) applied to a node's child subtree: offscreen Gaussian defocus blur (`blur`,
/// pt), quarter-circle bevel refraction (`refraction` and `bezel`, pt), and opacity (`alpha`). When `blur <= 0.05 &&
/// refraction <= 0.05` (`ContentLens::none()`), zero extra instances or GPU passes are emitted at rest.
#derive(Eq, Debug)
pub(all) struct ContentLens {
  blur : Double
  refraction : Double
  bezel : Double
  alpha : Double
}

///|
/// Inactive foreground lens (zero blur, zero refraction, full alpha): zero-overhead resting default.
pub fn ContentLens::none() -> ContentLens {
  { blur: 0.0, refraction: 0.0, bezel: 0.0, alpha: 1.0 }
}
