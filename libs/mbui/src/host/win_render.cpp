// Direct3D 11 renderer: one instanced quad per scene instance, the Metal/GLES
// shader in HLSL, made a pixel shader for each kind it draws most (kind_ps).
// Without a usable GPU (CI) the device is WARP.
// The canvas is a composition swap chain with alpha in a DirectComposition
// tree, over a visual the native views (win_views.cpp) go in: they show through
// the holes the app paints (kind 9, written transparent without blending), as
// on the other hosts. Where DirectComposition cannot be had, the swap chain is
// the window's own and there are no native views.
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <objbase.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dcomp.h>
#include <dwmapi.h>
#include <d3dcompiler.h>
#include <wincodec.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "win.h"
#include "corner_sl.h"
#include "contained.h"
#include "bands.h"
// the groups of instances the host keeps, drawn out as a frame is taken (submit)
#include "groups.h"

#pragma comment(lib, "d3d11.lib")
#pragma comment(lib, "d3dcompiler.lib")
#pragma comment(lib, "dcomp.lib")
#pragma comment(lib, "dwmapi.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "user32.lib")
#pragma comment(lib, "windowscodecs.lib")
#pragma comment(lib, "ole32.lib")

int mb_atlas_size = 4096;

static ID3D11Device *dev;
static ID3D11DeviceContext *ctx;
static ID3D11VertexShader *vs;
static ID3D11PixelShader *ps;
// a ground's flat middle (bands.h mb_pieces)
static ID3D11PixelShader *ps_flat;
static ID3D11InputLayout *layout;
static ID3D11Buffer *vbuf, *ubuf;
static size_t vbuf_cap;
static ID3D11Texture2D *atlas;
static ID3D11ShaderResourceView *atlas_srv;
static ID3D11SamplerState *sampler;
static ID3D11BlendState *blend;
// the composition's device, the windows' (NULL: each swap chain is its window's own)
static IDCompositionDevice *dcomp;
// what makes a window's swap chain, kept for the windows of the run opened after the first (mb_render_open)
static IDXGIFactory2 *dxgi_factory;
static ID3D11RasterizerState *raster, *raster_cut;
// the swap chain is a flip model's (its Present1 takes the part that changed)
static int flip_chain;
// glass (src/ui/glass.mbt): its passes, their constants, the copies they work in (level j 1/2^j of the largest
// capture yet, the glass and the blur's margin round it, not of the target: a composer's strip, not the window; [4] a
// Gaussian's first half), the glass's own constants, the blurred copy in view
static ID3D11VertexShader *pvs;
static ID3D11PixelShader *pps, *edge_ps, *prog_ps, *ad_ps;
static ID3D11Buffer *pbuf, *gbuf, *ad_cb;
struct level { ID3D11Texture2D *t; ID3D11RenderTargetView *rt; ID3D11ShaderResourceView *srv; int w, h; DXGI_FORMAT fmt; };
static level lv[5];
static MBContained post_edge;
static int lv_w, lv_h;
#define MB_ADAPTIVE_MAX 16
#define MB_AD_TAU 0.070
#define MB_AD_SETTLE_SEC 0.42
#define MB_AD_MATCH_DIST 64.0
struct MBAdSlot {
  int active;
  float cx, cy, hx, hy;
  int is_dark;
  double settle_left;
  uint64_t updated_serial;
  uint64_t seen_serial;
};
struct GU { float map[4]; float uvc[4]; float gb[4]; float shape[8][4]; float rad[8][4]; float misc[4]; float ad_box[MB_ADAPTIVE_MAX][4]; float ad_meta[4]; };
static GU gu;
static ID3D11ShaderResourceView *gsrv;
// What is a window's own (win_app.c: the windows of one run): its swap chain and its buffer's view, its composition's
// target, root, the native views' visual under the canvas's and the canvas's (NULL: the swap chain is the window's own),
// its buffer's size in pixels and its size in points and scale (mb_render_set_size's); the last frame, kept for
// snapshots (the vertex buffer still holds it) and to find the runs of each image; the canvas its frames are drawn
// into and what of it is said to differ (partial redraw, below). Put in place for a window by mb_render_use.
#define MB_PARTS 8
struct RenderWin {
  IDXGISwapChain1 *chain;
  ID3D11RenderTargetView *rtv;
  IDCompositionTarget *dtarget;
  IDCompositionVisual *droot, *dunder, *dcanvas;
  int fb_w, fb_h;
  double vw, vh, vscale;
  int32_t last_count;
  float *last_inst;
  size_t last_cap;
  float last_bg[3];
  ID3D11Texture2D *canvas;
  ID3D11RenderTargetView *canvas_rtv;
  int canvas_w, canvas_h, canvas_ok;
  double dirty[MB_PARTS][4];
  int dirty_n, dirty_whole, dirty_told;
  // a picture the frame drawn last had none of yet (drawn without it): the next drawn whole
  int pictures_missing;
  level ad_tex[2];
  int ad_cur;
  MBAdSlot ad_slots[MB_ADAPTIVE_MAX];
  double ad_last_time;
  uint64_t ad_frame_serial;
  int ad_settling;
  UINT last_present_count;
  UINT last_sync_refresh;
  int64_t last_present_qpc;
  int has_frame_stats;
};
static RenderWin render_wins[MB_WINS];
static RenderWin *rw = &render_wins[0];
static void render_win_fresh(RenderWin *w) {
  memset(w, 0, sizeof *w);
  w->vw = 800, w->vh = 600, w->vscale = 1;
}
static struct RenderWinsMade {
  RenderWinsMade() {
    for (int k = 0; k < MB_WINS; k++) render_win_fresh(&render_wins[k]);
  }
} render_wins_made;
#define chain (rw->chain)
#define rtv (rw->rtv)
#define dtarget (rw->dtarget)
#define droot (rw->droot)
#define dunder (rw->dunder)
#define dcanvas (rw->dcanvas)
#define fb_w (rw->fb_w)
#define fb_h (rw->fb_h)
#define vw (rw->vw)
#define vh (rw->vh)
#define vscale (rw->vscale)
#define last_count (rw->last_count)
#define last_inst (rw->last_inst)
#define last_cap (rw->last_cap)
#define last_bg (rw->last_bg)
#define canvas (rw->canvas)
#define canvas_rtv (rw->canvas_rtv)
#define canvas_w (rw->canvas_w)
#define canvas_h (rw->canvas_h)
#define canvas_ok (rw->canvas_ok)
#define dirty (rw->dirty)
#define dirty_n (rw->dirty_n)
#define dirty_whole (rw->dirty_whole)
#define dirty_told (rw->dirty_told)
#define pictures_missing (rw->pictures_missing)

// The window of the run drawn now (win_app.c's win_use): its swap chain, its size, its last frame and its canvas.
void mb_render_use(int wid) {
  if (wid >= 0 && wid < MB_WINS) rw = &render_wins[wid];
}

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 60
#include "glass_damage.h"

static const char *shader_src =
    "// the kind of what this pixel shader draws, fixed (kind_ps); -1 any, as the instance says\n"
    "#ifndef ONE_KIND\n"
    "#define ONE_KIND -1\n"
    "#endif\n"
    "cbuffer U : register(b0) { float2 vp; float scale; float pad; };\n"
    "// glass (src/ui/glass.mbt): where a point is in the blurred copy under it (uv = p * gmap.xy + gmap.zw, kept in guvc),\n"
    "// a liquid group's bounds, shapes, corners (x of each), how many\n"
    "cbuffer G : register(b1) { float4 gmap; float4 guvc; float4 ggb; float4 gshape[8]; float4 grad[8]; float4 gmisc; float4 gad_box[16]; float4 gad_meta; };\n"
    "Texture2D atlas : register(t0);\n"
    "Texture2D img : register(t1);\n"
    "Texture2D bd : register(t2);\n"
    "// the pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), 15 fours each\n"
    "Buffer<float4> segs : register(t3);\n"
    "Texture2D ad_tex : register(t5);\n"
    "SamplerState samp : register(s0);\n"
    "struct VIn { float4 rect : INST0; float4 p : INST1; float4 color : INST2; float4 c2 : INST3;\n"
    "  float4 clip : INST4; float4 pd : INST5; float4 rc : INST6; float4 rs : INST7; float4 rot : INST8;\n"
    "  float4 rr : INST9; float4 oclip : INST10; float4 orc : INST11; float4 ors : INST12; float4 fade : INST13; float4 fadex : INST14;\n"
    "  uint vid : SV_VertexID; };\n"
    "struct VOut { float4 pos : SV_Position; float2 p : POS; float2 cp : CPOS;\n"
    "  nointerpolation float4 rect : INST0; nointerpolation float4 prm : INST1;\n"
    "  nointerpolation float4 color : INST2; nointerpolation float4 c2 : INST3;\n"
    "  nointerpolation float4 clip : INST4; nointerpolation float4 pd : INST5; nointerpolation float4 rc : INST6;\n"
    "  nointerpolation float4 rs : INST7; nointerpolation float4 rr : INST8;\n"
    "  nointerpolation float4 oclip : INST9; nointerpolation float4 orc : INST10; nointerpolation float4 ors : INST11;\n"
    "  nointerpolation float4 fade : INST12; nointerpolation float4 fadex : INST13; };\n"
    "VOut vmain(VIn I) {\n"
    "  uint vid = I.vid;\n"
    "  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
    "                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
    "  int kind = int(I.p.y + 0.5);\n"
    "  bool merged_liquid = kind == 6 && I.pd.w > 0.0;\n"
    "  float grow = kind == 2 ? I.p.w * 3.0 + 2.0 : (kind == 6 && I.pd.w <= 0.0) ? 2.0 : ((kind == 0 || kind == 4 || kind == 5) ? 1.0 : 0.0);\n"
    "  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
    "  if (merged_liquid) pos = lerp(ggb.xy, ggb.zw, corner);\n"
    "  // the pieces of shapes (kind 12): nothing drawn\n"
    "  if (kind == 12) pos = float2(0.0, 0.0);\n"
    "  // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (o.p), its clip\n"
    "  // there too or (35: one from outside what turned) where it is drawn (o.cp)\n"
    "  float2 at = pos;\n"
    "  if (I.rot.x != 0.0) { float2 d = pos - I.rot.yz; float c = cos(I.rot.x), s = sin(I.rot.x);\n"
    "    at = I.rot.yz + float2(c * d.x - s * d.y, s * d.x + c * d.y); }\n"
    "  VOut o;\n"
    "  o.pos = float4(at.x / vp.x * 2.0 - 1.0, 1.0 - at.y / vp.y * 2.0, 0.0, 1.0);\n"
    "  o.p = pos; o.cp = I.rot.w > 0.5 ? at : pos; o.rect = I.rect; o.prm = I.p; o.color = I.color; o.c2 = I.c2; o.clip = I.clip; o.pd = I.pd; o.rc = I.rc; o.rs = I.rs; o.rr = I.rr;\n"
    "  if (kind == 1) o.prm.x = I.rot.x;\n"
    "  if (kind == 4 && I.pd.z > 0.5) o.pd.x = I.rot.w;\n"
    "  o.oclip = I.oclip; o.orc = I.orc; o.ors = I.ors; o.fade = I.fade; o.fadex = I.fadex;\n"
    "  return o;\n"
    "}\n"
    MB_CORNER_SL
    "float sd_rr(float2 p, float4 r, float4 rad) {\n"
    "  float2 hs = r.zw * 0.5;\n"
    "  return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);\n"
    "}\n"
    "// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
    "// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
    "float notch_cut(float d, float2 p, float4 r, float4 pad) {\n"
    "  if (pad.z <= 0.0) return d;\n"
    "  float b = pad.z - length(p - float2(r.x + r.z * 0.5, r.y + pad.y));\n"
    "  float f = max(pad.w, 0.0);\n"
    "  float2 u = max(float2(f + d, f + b), 0.0);\n"
    "  return min(-f, max(d, b)) + length(u);\n"
    "}\n"
    "float smin_k(float a, float b, float k) {\n"
    "  if (k <= 0.0) return min(a, b);\n"
    "  float h = max(k - abs(a - b), 0.0) / k;\n"
    "  return min(a, b) - h * h * k * 0.25;\n"
    "}\n"
    "float sd_group(float2 p, float k) {\n"
    "  float d = 1e9;\n"
    "  int n = int(gmisc.x + 0.5);\n"
    "  [loop] for (int i = 0; i < 8; i++) {\n"
    "    if (i >= n) break;\n"
    "    d = smin_k(d, sd_rr(p, gshape[i], grad[i]), k);\n"
    "  }\n"
    "  return d;\n"
    "}\n"
    "// Integral of linear ramp from 0 to w (contourOffset = 0, width w in device px)\n"
    "float mb_contour_int(float t, float w) {\n"
    "  float u = clamp(t, 0.0, w);\n"
    "  return u - u * u / (2.0 * w);\n"
    "}\n"
    "float3 backdrop(float2 p) {\n"
    "  return bd.SampleLevel(samp, clamp(p * gmap.xy + gmap.zw, guvc.xy, guvc.zw), 0).rgb;\n"
    "}\n"
    "float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
    "float mb_backdrop_luma_rect(float2 c, float2 h) {\n"
    "  float sum = 0.0;\n"
    "  float mx1 = -1.0, mx2 = -1.0;\n"
    "  float mn1 = 2.0, mn2 = 2.0;\n"
    "  [unroll] for (int iy = -1; iy <= 1; iy++) {\n"
    "    float py = c.y + float(iy) * (h.y * 0.60);\n"
    "    [unroll] for (int ix = -2; ix <= 2; ix++) {\n"
    "      float px = c.x + float(ix) * (h.x * 0.38);\n"
    "      float y = luma(backdrop(float2(px, py)));\n"
    "      sum += y;\n"
    "      if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }\n"
    "      if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }\n"
    "    }\n"
    "  }\n"
    "  return (sum - mx1 - mx2 - mn1 - mn2) / 11.0;\n"
    "}\n"
    "float mb_unpack16(float2 rg) {\n"
    "  float hi = floor(saturate(rg.x) * 255.0 + 0.5);\n"
    "  float lo = floor(saturate(rg.y) * 255.0 + 0.5);\n"
    "  return (hi * 256.0 + lo) / 65535.0;\n"
    "}\n"
    "float ad_sample(float2 ac, float fallback_r, bool is_dark_glass) {\n"
    "  int ad_n = int(gad_meta.x + 0.5);\n"
    "  [branch] if (ad_n > 0) {\n"
    "    int best = -1;\n"
    "    float best_d = 1e9;\n"
    "    [loop] for (int i = 0; i < 16; i++) {\n"
    "      if (i >= ad_n) break;\n"
    "      float d = length(ac - gad_box[i].xy);\n"
    "      if (d <= 2.0 && d < best_d) { best = i; best_d = d; }\n"
    "    }\n"
    "    if (best < 0) {\n"
    "      best_d = 1e9;\n"
    "      [loop] for (int i = 0; i < 16; i++) {\n"
    "        if (i >= ad_n) break;\n"
    "        float2 diff = abs(ac - gad_box[i].xy);\n"
    "        if (diff.x <= gad_box[i].z + 2.0 && diff.y <= gad_box[i].w + 2.0) {\n"
    "          float d = length(diff);\n"
    "          if (d < best_d) { best = i; best_d = d; }\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "    if (best >= 0) {\n"
    "      return mb_unpack16(ad_tex.Load(int3(best, 0, 0)).rg);\n"
    "    }\n"
    "  }\n"
    "  float bgL = mb_backdrop_luma_rect(ac, float2(max(fallback_r, 1.0), max(fallback_r, 1.0)));\n"
    "  return is_dark_glass ? smoothstep(0.35, 0.85, bgL) : (1.0 - smoothstep(0.30, 0.42, bgL));\n"
    "}\n"
    "float3 mb_adaptive_ink(float3 rgb, float darkT) {\n"
    "  float ch = max(max(rgb.r, rgb.g), rgb.b) - min(min(rgb.r, rgb.g), rgb.b);\n"
    "  if (ch <= 0.08) {\n"
    "    float origL = luma(rgb);\n"
    "    if (origL < 0.5) {\n"
    "      float inkT = smoothstep(0.0, 1.0, darkT);\n"
    "      float lightL = clamp(1.06 - origL, 0.68, 0.98);\n"
    "      rgb = lerp(rgb, float3(lightL, lightL, lightL), inkT);\n"
    "    }\n"
    "  }\n"
    "  return rgb;\n"
    "}\n"
    "// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
    "// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts\n"
    "// it\n"
    "float clip_cover(float2 p, float4 c, float4 r, float4 s, float sc) {\n"
    "  float d = mb_sd_clip(p, c, r, s, 1.0 + 2.0 / sc);\n"
    "  return saturate(0.5 - d * sc);\n"
    "}\n"
    "// A glyph's coverage, a pixel's three stripes each its own (ClearType: win_text.cpp draw_layout), blended stripe by\n"
    "// stripe as the second source (the blend's INV_SRC1_COLOR); what else is drawn, by its alpha as before. Every\n"
    "// target is cleared opaque (encode), so the stripes always fall on a ground of the pixel's own.\n"
    "static float3 stripes;\n"
    "static bool striped;\n"
    "float4 fmain0(VOut I);\n"
    "struct FOut { float4 c : SV_Target0; float4 w : SV_Target1; };\n"
    "FOut fmain(VOut I) {\n"
    "  striped = false;\n"
    "  FOut o;\n"
    "  o.c = fmain0(I);\n"
    "  o.w = striped ? float4(stripes, o.c.a) : o.c.aaaa;\n"
    "  return o;\n"
    "}\n"
    "float4 fmain0(VOut I) {\n"
    "  float2 p = I.p, cp = I.cp;\n"
    "  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
    "  float cover = 1.0;\n"
    "  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
    "    cover = clip_cover(cp, I.clip, I.rc, I.rs, scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  } else if (cp.x < I.clip.x || cp.y < I.clip.y || cp.x > I.clip.z || cp.y > I.clip.w) discard;\n"
    "  // and by the clip outside it, where it has one (scene.mbt 40-51: a pane round an image's frame in its corner)\n"
    "  if (max(max(I.orc.x, I.orc.y), max(I.orc.z, I.orc.w)) > 0.0) {\n"
    "    cover *= clip_cover(cp, I.oclip, I.orc, I.ors, scale);\n"
    "    if (cover <= 0.0) discard;\n"
    "  }\n"
    "  int kind = ONE_KIND == 13 ? 6 : (ONE_KIND >= 0 ? ONE_KIND : int(I.prm.y + 0.5));\n"
    "  bool prog_glass = (kind == 5 && I.pd.z < -0.5);\n"
    "  // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)\n"
    "  float fade_r = 1.0;\n"
    "  if (I.fade.y > 0.0) fade_r *= saturate((cp.y - I.fade.x) / I.fade.y);\n"
    "  if (I.fade.w > 0.0) fade_r *= saturate((I.fade.z - cp.y) / I.fade.w);\n"
    "  if (I.fadex.y > 0.0) fade_r *= saturate((cp.x - I.fadex.x) / I.fadex.y);\n"
    "  if (I.fadex.w > 0.0) fade_r *= saturate((I.fadex.z - cp.x) / I.fadex.w);\n"
    "  if (fade_r <= 0.0) discard;\n"
    "  if (!prog_glass) {\n"
    "    cover *= fade_r;\n"
    "    if (cover <= 0.0) discard;\n"
    "  }\n"
    "  if (kind == 9) { float2 hh = I.rect.zw * 0.5; float rr = min(mb_corner_of(p - I.rect.xy - hh, I.rr), min(hh.x, hh.y)); float2 q = abs(p - I.rect.xy - hh) - hh + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard; return (float4(0.0, 0.0, 0.0, 0.0)) * cover; }\n"
    "  float4 col = I.color;\n"
    "  if (kind == 11) {\n"
    "    // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x; prm.x half its stroke's width (0: a fill,\n"
    "    // c2.z 1 by the even-odd rule)\n"
    "    int first = int(I.c2.x + 0.5), n = int(I.c2.y + 0.5);\n"
    "    float a;\n"
    "    if (I.prm.x > 0.0) {\n"
    "      float d = 1e9;\n"
    "      for (int i = first; i < first + n; i++) d = min(d, mb_seg_dist(segs.Load((i / 6) * 15 + mb_seg_slot(i)), I.rect, p));\n"
    "      a = saturate(0.5 - (d - I.prm.x) * scale);\n"
    "    } else {\n"
    "      float4 w = float4(0.0, 0.0, 0.0, 0.0);\n"
    "      for (int i = first; i < first + n; i++) w += mb_path_rows(segs.Load((i / 6) * 15 + mb_seg_slot(i)), I.rect, p, scale);\n"
    "      a = mb_path_cover(w, I.c2.z);\n"
    "    }\n"
    "    [branch] if (I.pd.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(I.pd.yz, I.pd.w * 0.5, false));\n"
    "    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
    "  }\n"
    "  if (kind == 10) {\n"
    "    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), prm.x half its width, its ends round\n"
    "    float2 a = I.rect.xy + I.c2.xy * I.rect.zw, ab = I.rect.xy + I.c2.zw * I.rect.zw - a;\n"
    "    float h = saturate(dot(p - a, ab) / max(dot(ab, ab), 1e-8));\n"
    "    float d = length(p - a - ab * h) - I.prm.x;\n"
    "    [branch] if (I.pd.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(I.pd.yz, I.pd.w * 0.5, false));\n"
    "    return (float4(col.rgb, 1.0) * col.a * saturate(0.5 - d * scale)) * cover;\n"
    "  }\n"
    "  if (kind == 1 || kind == 3 || kind == 7) {\n"
    "    // within its own cell (c2: where in the atlas, in texels), however its rect is stretched or turned: a sample\n"
    "    // past the cell's edge texels would blend in what lies beside it (another glyph, one left from before the atlas\n"
    "    // started over); an unscaled, unrotated glyph snaps to exact texel centres so float32 rounding at 1.25x/1.5x\n"
    "    // never bleeds adjacent ClearType stripes.\n"
    "    float2 off = abs(I.rect.zw * scale - I.c2.zw);\n"
    "    // (exact only where its corner is on a pixel too: one half way between two had a row of its texels taken twice\n"
    "    // and the next not at all, where floor's step fell)\n"
    "    float2 r0 = I.rect.xy * scale, r0i = floor(r0 + 0.5);\n"
    "    bool exact = kind == 1 && max(off.x, off.y) <= 0.5 && max(abs(r0.x - r0i.x), abs(r0.y - r0i.y)) <= 0.05 && I.prm.x == 0.0;\n"
    "    float2 tex = exact ? floor(p * scale - r0i) + 0.5 : (p - I.rect.xy) / I.rect.zw * I.c2.zw;\n"
    "    float2 uv = clamp(I.c2.xy + tex, I.c2.xy + 0.5, I.c2.xy + I.c2.zw - 0.5) / 4096.0;\n"
    "    float4 t = atlas.SampleLevel(samp, uv, 0);\n"
    "    if (kind == 1) {\n"
    "      // (a mask drawn in gray has its three the same as its alpha: as before; a glyph drawn larger or smaller than\n"
    "      // its picture, its stripes no longer on the screen's: in gray, their mean). Its cover blended as it is, light\n"
    "      // words on dark as dark on light, as Metal's does (apple_render.m: its colour times its cover)\n"
    "      float3 cov = max(off.x, off.y) > 0.5 ? t.aaa : t.rgb;\n"
    "      stripes = cov * (col.a * cover);\n"
    "      striped = true;\n"
    "      return float4(col.rgb * stripes, dot(stripes, float3(1.0, 1.0, 1.0) / 3.0));\n"
    "    }\n"
    "    if (kind == 7) {\n"
    "      // inked by how light what is under its glass is, looked at round the glass's middle\n"
    "      float darkT = ad_sample(I.pd.yz, I.pd.w * 0.5, false);\n"
    "      float3 ink = mb_adaptive_ink(col.rgb, darkT);\n"
    "      return (float4(ink, 1.0) * (t.a * col.a)) * cover;\n"
    "    }\n"
    "    return (t * col.a) * cover;\n"
    "  }\n"
    "  if (kind == 6) {\n"
    "    // Copyright 2025, Tim Lehmann for whynotmake.it. Adapted from flutter_liquid_glass\n"
    "    // liquid_glass_final_render_core.glsl, Apache-2.0.\n"
    "    float k = I.pd.w;\n"
    "    float4 s_rr = max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) > 0.0 ? I.rr : float4(I.prm.x, I.prm.x, I.prm.x, I.prm.x);\n"
    "    float d;\n"
    "    float halfMinor = 1e9;\n"
    "#if ONE_KIND == 13\n"
    "    d = sd_rr(p, I.rect, s_rr);\n"
    "    halfMinor = min(I.rect.z, I.rect.w) * 0.5;\n"
    "#else\n"
    "    [branch] if (k <= 0.0) {\n"
    "      d = sd_rr(p, I.rect, s_rr);\n"
    "      halfMinor = min(I.rect.z, I.rect.w) * 0.5;\n"
    "    } else {\n"
    "      d = 1e9;\n"
    "      int n_sh = int(gmisc.x + 0.5);\n"
    "      [loop] for (int i = 0; i < 8; i++) {\n"
    "        if (i >= n_sh) break;\n"
    "        float di = sd_rr(p, gshape[i], grad[i]);\n"
    "        float hi = min(gshape[i].z, gshape[i].w) * 0.5;\n"
    "        if (i == 0) {\n"
    "          d = di;\n"
    "          halfMinor = hi;\n"
    "        } else {\n"
    "          float h = max(k - abs(d - di), 0.0) / k;\n"
    "          float w = d < di ? 0.5 * h : 1.0 - 0.5 * h;\n"
    "          d = min(d, di) - h * h * k * 0.25;\n"
    "          halfMinor = lerp(halfMinor, hi, w);\n"
    "        }\n"
    "      }\n"
    "    }\n"
    "#endif\n"
    "    halfMinor = max(halfMinor, 1.0);\n"
    "    float sd_px = -d * scale;\n"
    "    float materialAlpha = saturate(sd_px + 0.5);\n"
    "    float edgeW = 0.75 * scale;\n"
    "    float outward = -sd_px;\n"
    "    float ext_cov = mb_contour_int(max(outward + 0.5, 0.0), edgeW)\n"
    "                  - mb_contour_int(max(outward - 0.5, 0.0), edgeW);\n"
    "    if (materialAlpha < 0.01 && ext_cov < 0.01) discard;\n"
    "    bool is_clear = (I.prm.w <= 0.1 && col.a < 0.12);\n"
    "    bool is_adaptive = I.c2.z < -0.5;\n"
    "    float spot_raw = is_adaptive ? (-I.c2.z - 1.0) : I.c2.z;\n"
    "    bool is_dark = (!is_clear && col.a >= 0.05 && luma(col.rgb) < 0.35);\n"
    "    float inward = max(-d, 0.0);\n"
    "    float rawBevel = max(I.c2.y, 0.0);\n"
    "    float rawAmount = max(I.pd.y, 0.0);\n"
    "    float bevel;\n"
    "    float amount;\n"
    "    if (!is_clear) {\n"
    "      // refractionFitsShape = true (iOS 27 regular)\n"
    "      bevel = min(rawBevel, 0.5 * halfMinor);\n"
    "      amount = min(rawAmount, halfMinor);\n"
    "    } else {\n"
    "      // refractionFitsShape = false (iOS 27 clear)\n"
    "      float lensScale = min(1.0, halfMinor / max(rawBevel, 0.001));\n"
    "      bevel = rawBevel * lensScale;\n"
    "      amount = rawAmount * lensScale;\n"
    "    }\n"
    "    float2 surfaceNormal = float2(0.0, 0.0);\n"
    "    float shortening = 0.0;\n"
    "    float2 disp = float2(0.0, 0.0);\n"
    "    bool need_grad = (inward < max(bevel, 23.0)) || (ext_cov > 0.0);\n"
    "    [branch] if (need_grad) {\n"
    "      float e = 0.5;\n"
    "#if ONE_KIND == 13\n"
    "      float2 sdfGrad = float2(\n"
    "          sd_rr(p + float2(e, 0.0), I.rect, s_rr) - sd_rr(p - float2(e, 0.0), I.rect, s_rr),\n"
    "          sd_rr(p + float2(0.0, e), I.rect, s_rr) - sd_rr(p - float2(0.0, e), I.rect, s_rr)\n"
    "        ) / (2.0 * e);\n"
    "#else\n"
    "      float2 sdfGrad;\n"
    "      [branch] if (k <= 0.0) {\n"
    "        sdfGrad = float2(\n"
    "          sd_rr(p + float2(e, 0.0), I.rect, s_rr) - sd_rr(p - float2(e, 0.0), I.rect, s_rr),\n"
    "          sd_rr(p + float2(0.0, e), I.rect, s_rr) - sd_rr(p - float2(0.0, e), I.rect, s_rr)\n"
    "        ) / (2.0 * e);\n"
    "      } else {\n"
    "        sdfGrad = float2(\n"
    "          sd_group(p + float2(e, 0.0), k) - sd_group(p - float2(e, 0.0), k),\n"
    "          sd_group(p + float2(0.0, e), k) - sd_group(p - float2(0.0, e), k)\n"
    "        ) / (2.0 * e);\n"
    "      }\n"
    "#endif\n"
    "      float gradLen = length(sdfGrad);\n"
    "      surfaceNormal = gradLen > 0.0001 ? sdfGrad / gradLen : float2(0.0, 0.0);\n"
    "      shortening = sqrt(saturate(gradLen));\n"
    "      if (inward < bevel && bevel > 0.001 && amount > 0.0) {\n"
    "        float bevelX = 1.0 - saturate(inward / bevel);\n"
    "        float mag = amount * (1.0 - sqrt(max(1.0 - bevelX * bevelX, 0.0))) * shortening;\n"
    "        disp = surfaceNormal * (-mag);\n"
    "      }\n"
    "    }\n"
    "    float lensZoom = (I.prm.w < 0.0) ? clamp(1.0 - I.prm.w, 1.0, 3.0) : 1.0;\n"
    "    float2 sampleBase = p;\n"
    "    if (lensZoom > 1.0001) {\n"
    "#if ONE_KIND == 13\n"
    "      float2 zoomC = I.rect.xy + I.rect.zw * 0.5;\n"
    "#else\n"
    "      float2 zoomC = (k <= 0.0) ? (I.rect.xy + I.rect.zw * 0.5) : ((ggb.xy + ggb.zw) * 0.5);\n"
    "#endif\n"
    "      sampleBase = zoomC + (p - zoomC) / lensZoom;\n"
    "    }\n"
    "    float3 refractColor;\n"
    "    if (inward >= bevel || abs(I.pd.z) * amount * scale <= 0.25) {\n"
    "      refractColor = backdrop(sampleBase + disp);\n"
    "    } else {\n"
    "      float ds = I.pd.z * 0.5;\n"
    "      refractColor = float3(\n"
    "        backdrop(sampleBase + disp * (1.0 + ds)).r,\n"
    "        backdrop(sampleBase + disp).g,\n"
    "        backdrop(sampleBase + disp * (1.0 - ds)).b\n"
    "      );\n"
    "    }\n"
    "    float3 emission;\n"
    "    float transmittance;\n"
    "    float lift;\n"
    "    float chromaGain;\n"
    "    float contourStr;\n"
    "    float contourDirAmt;\n"
    "    float bevelShadowStr;\n"
    "    float glintLum;\n"
    "    float glintFaceGain;\n"
    "    float glintVib;\n"
    "    float fogT = 0.0;\n"
    "    if (is_clear) {\n"
    "      // iOS 27 clear liquid glass: col.a == 0.0 keeps crystal-clear zero-veil optical lens\n"
    "      // (lifted tab-bar / toggle / slider thumb & loupe), while Glass::clear() (col.a ~ 0.102)\n"
    "      // blends smoothly into the +0.126 translucent micro-veil over media.\n"
    "      float clearVeil = smoothstep(0.005, 0.102, col.a);\n"
    "      emission = float3(1.0, 1.0, 1.0) * (0.126 * clearVeil);\n"
    "      transmittance = lerp(1.0, 0.90, clearVeil);\n"
    "      lift = lerp(0.0, 0.10, clearVeil);\n"
    "      chromaGain = lerp(1.06, 1.0, clearVeil);\n"
    "      contourStr = lerp(0.24, 0.25, clearVeil);\n"
    "      contourDirAmt = lerp(0.85, 0.77, clearVeil);\n"
    "      bevelShadowStr = lerp(0.045, 0.04, clearVeil);\n"
    "      glintLum = lerp(1.6, 1.2, clearVeil);\n"
    "      glintFaceGain = lerp(0.0, 0.25, clearVeil);\n"
    "      glintVib = lerp(2.85, 1.5, clearVeil);\n"
    "    } else {\n"
    "      [branch] if (is_adaptive) {\n"
    "#if ONE_KIND == 13\n"
    "        float2 ac = I.rect.xy + I.rect.zw * 0.5;\n"
    "        float ar = max(min(I.rect.z, I.rect.w) * 0.5, 1.0) * 0.5;\n"
    "#else\n"
    "        float2 ac = (k <= 0.0) ? (I.rect.xy + I.rect.zw * 0.5) : ((ggb.xy + ggb.zw) * 0.5);\n"
    "        float ar = ((k <= 0.0) ? max(min(I.rect.z, I.rect.w) * 0.5, 1.0) : max(min(ggb.z - ggb.x, ggb.w - ggb.y) * 0.5, 1.0)) * 0.5;\n"
    "#endif\n"
    "        float val = ad_sample(ac, ar, is_dark);\n"
    "        float baseDens = (col.a > 0.41) ? col.a : 0.30;\n"
    "        if (is_dark) {\n"
    "          float brightT = val;\n"
    "          fogT = brightT;\n"
    "          float dens = max(baseDens, lerp(baseDens, 0.64, brightT));\n"
    "          float extra = saturate((dens - 0.30) / (1.0 - 0.30));\n"
    "          emission = lerp(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);\n"
    "          transmittance = lerp(0.54, 0.0, extra);\n"
    "          lift = lerp(0.36, 0.0, extra);\n"
    "          chromaGain = lerp(0.92, 0.0, extra);\n"
    "          contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;\n"
    "          glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
    "        } else {\n"
    "          float darkMix = val;\n"
    "          fogT = darkMix;\n"
    "          float extra = saturate((baseDens - 0.30) / (1.0 - 0.30));\n"
    "          float darkDens = max(baseDens, lerp(baseDens, 0.52, darkMix));\n"
    "          float darkExtra = saturate((darkDens - 0.30) / (1.0 - 0.30));\n"
    "          float3 lightEm = float3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * baseDens;\n"
    "          float3 darkEm = lerp(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), darkExtra);\n"
    "          emission = lerp(lightEm, darkEm, darkMix);\n"
    "          transmittance = lerp(lerp(0.70, 0.0, extra), lerp(0.54, 0.0, darkExtra), darkMix);\n"
    "          lift = lerp(lerp(0.16, 0.0, extra), lerp(0.36, 0.0, darkExtra), darkMix);\n"
    "          chromaGain = lerp(lerp(1.18, 0.0, extra), lerp(0.92, 0.0, darkExtra), darkMix);\n"
    "          contourStr = lerp(0.43, 0.88, darkMix);\n"
    "          contourDirAmt = lerp(0.77, 1.0, darkMix);\n"
    "          bevelShadowStr = 0.036;\n"
    "          glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
    "        }\n"
    "      } else if (is_dark) {\n"
    "        float darkDens = (col.a > 0.41) ? col.a : 0.30;\n"
    "        float extra = saturate((darkDens - 0.30) / (1.0 - 0.30));\n"
    "        emission = lerp(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);\n"
    "        transmittance = lerp(0.54, 0.0, extra);\n"
    "        lift = lerp(0.36, 0.0, extra);\n"
    "        chromaGain = lerp(0.92, 0.0, extra);\n"
    "        contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;\n"
    "        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
    "      } else {\n"
    "        float lightDens = (col.a > 0.41) ? col.a : 0.30;\n"
    "        float extra = saturate((lightDens - 0.30) / (1.0 - 0.30));\n"
    "        emission = float3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * lightDens;\n"
    "        transmittance = lerp(0.70, 0.0, extra);\n"
    "        lift = lerp(0.16, 0.0, extra);\n"
    "        chromaGain = lerp(1.18, 0.0, extra);\n"
    "        contourStr = 0.43; contourDirAmt = 0.77; bevelShadowStr = 0.036;\n"
    "        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
    "      }\n"
    "    }\n"
    "    [branch] if (fogT > 0.001) {\n"
    "      float r1 = fogT * 2.6;\n"
    "      float r2 = fogT * 3.6;\n"
    "      float2 fc = sampleBase + disp;\n"
    "      float3 fBlur = (refractColor * 2.0\n"
    "        + (backdrop(fc + float2(r1, 0.0)) + backdrop(fc - float2(r1, 0.0))\n"
    "         + backdrop(fc + float2(0.0, r1)) + backdrop(fc - float2(0.0, r1))) * 1.5\n"
    "        + (backdrop(fc + float2(r2, r2)) + backdrop(fc + float2(-r2, r2))\n"
    "         + backdrop(fc + float2(r2, -r2)) + backdrop(fc + float2(-r2, -r2)))) * (1.0 / 12.0);\n"
    "      refractColor = lerp(refractColor, fBlur, fogT);\n"
    "    }\n"
    "    float Y = luma(refractColor);\n"
    "    float transLum = saturate(Y * (1.0 + lift * (1.0 - Y)));\n"
    "    float3 transmittedColor = (transLum * transmittance).xxx + (refractColor - Y.xxx) * (chromaGain * I.prm.z);\n"
    "    float3 baseColor = saturate(emission + transmittedColor);\n"
    "    // Honor explicit chromatic tints (non-neutral) if a caller requests colored liquid glass\n"
    "    float colChroma = max(max(col.r, col.g), col.b) - min(min(col.r, col.g), col.b);\n"
    "    if (colChroma > 0.08 && col.a > 0.001) {\n"
    "      baseColor = lerp(baseColor, col.rgb, col.a * 0.5);\n"
    "    }\n"
    "    float spot = 0.0;\n"
    "    if (spot_raw > 0.5) {\n"
    "      float q = spot_raw - 1.0;\n"
    "      float qx = floor(q * 0.000244140625);\n"
    "      float qy = q - qx * 4096.0;\n"
    "      float2 gp = I.rect.xy + float2(qx * 0.5 - 256.0, qy * 0.5 - 256.0);\n"
    "      float gr = max(min(I.rect.z, I.rect.w) * 1.5, 64.0);\n"
    "      spot = 1.0 - smoothstep(gr * 0.1, gr, length(p - gp));\n"
    "      baseColor = saturate(baseColor + (0.08 * spot).xxx);\n"
    "    }\n"
    "    float2 rn = float2(0.0, 0.0);\n"
    "    float tangency = 0.0;\n"
    "    [branch] if (need_grad) {\n"
    "      float2 la = gmisc.zw;\n"
    "      rn = float2(\n"
    "        surfaceNormal.x * la.x + surfaceNormal.y * la.y,\n"
    "        -surfaceNormal.x * la.y + surfaceNormal.y * la.x\n"
    "      );\n"
    "      tangency = abs(rn.x);\n"
    "    }\n"
    "    float3 result = baseColor;\n"
    "    // (a) Inner bevel shadow (subtracts only transmittedColor; lightFacing = -rn.y)\n"
    "    if (bevelShadowStr >= 0.001 && inward < 23.0) {\n"
    "      float lightFacing = -rn.y;\n"
    "      float shadowShift = 6.0 * lightFacing;\n"
    "      float penumbra = 2.0 * shadowShift;\n"
    "      float bevelLeading = penumbra > 0.001 ? smoothstep(0.0, penumbra, inward) : 1.0;\n"
    "      float bevelFalloff = 1.0 - smoothstep(0.0, 16.0, inward - shadowShift);\n"
    "      float wrappedFacing = smoothstep(0.0, 1.0, lightFacing * 0.5 + 0.5);\n"
    "      float bevelDir = lerp(1.0, wrappedFacing, 0.5);\n"
    "      float bevelShadow = saturate(bevelLeading * bevelFalloff * bevelDir * bevelShadowStr);\n"
    "      result = max(result - transmittedColor * bevelShadow, float3(0.0, 0.0, 0.0));\n"
    "    }\n"
    "    // (b) Glint (1.2pt ramp + 0.21 * 4.8pt bleed, both top & bottom walls, recolors face)\n"
    "    if (I.c2.x > 0.01 && inward < 4.8) {\n"
    "      float glintProfile = saturate(1.0 - inward / 1.2)\n"
    "                         + 0.21 * saturate(1.0 - inward / 4.8);\n"
    "      float lobe = max(1.0 - tangency, 0.0);\n"
    "      float glint = saturate(I.c2.x * 0.252 * lobe * glintProfile + spot * 0.08 * glintProfile);\n"
    "      float resLum = luma(result);\n"
    "      float3 glintTarget = glintLum.xxx + result * glintFaceGain + (result - resLum.xxx) * glintVib;\n"
    "      result = saturate(lerp(result, glintTarget, glint));\n"
    "    }\n"
    "    result = saturate(result + mb_dither(p * scale) / 255.0);\n"
    "    // (c) External 0.75pt dark contour (concentrated perpendicular to light axis where glint fades)\n"
    "    float contourDir = lerp(1.0, tangency, contourDirAmt);\n"
    "    float extA = ext_cov * contourStr * contourDir * I.c2.w;\n"
    "    float visA = materialAlpha * I.c2.w;\n"
    "    return float4(result * visA, saturate(visA + extA)) * cover;\n"
    "  }\n"
    "  float2 hs = I.rect.zw * 0.5;\n"
    "  float2 c = I.rect.xy + hs;\n"
    "  // worked out as near the curve as its cover, its edge or its blur reaches\n"
    "  float band = 1.0 + 2.0 / scale + (kind == 2 ? max(I.prm.w, 0.5) : max(I.prm.z, 0.0));\n"
    "  // (its corner by p: rr, each its own)\n"
    "  float rad = mb_corner_of(p - c, I.rr);\n"
    "  float d = mb_sd_box(p - c, hs, rad, band);\n"
    "  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pd);\n"
    "  if (kind == 4) {\n"
    "    float2 uv = I.c2.xy + saturate((p - I.rect.xy) / I.rect.zw) * I.c2.zw;\n"
    "    float2 dudx = ddx(p) / max(I.rect.zw, 1e-6) * I.c2.zw;\n"
    "    float2 dudy = ddy(p) / max(I.rect.zw, 1e-6) * I.c2.zw;\n"
    "    float4 pic = img.SampleGrad(samp, saturate(uv), dudx, dudy);\n"
    "    float edge = saturate(0.5 - d * scale);\n"
    "    if (I.pd.z > 0.5) {\n"
    "      // Only picture edges inside the frame cut it; the frame's clip covers shared edges once.\n"
    "      float2 size = I.rect.zw / I.c2.zw, lo = I.rect.xy - I.c2.xy * size, hi = lo + size;\n"
    "      float2 a = lo - p, b = p - hi;\n"
    "      if (I.c2.x >= 0.0) a.x = -1e9; if (I.c2.y >= 0.0) a.y = -1e9;\n"
    "      if (I.c2.x + I.c2.z <= 1.0) b.x = -1e9; if (I.c2.y + I.c2.w <= 1.0) b.y = -1e9;\n"
    "      float2 q = max(a, b);\n"
    "      float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);\n"
    "      pic *= I.pd.w * saturate(0.5 - pd * scale);\n"
    "      pic += float4(col.rgb * I.pd.y, I.pd.y) * (1.0 - pic.a);\n"
    "      if (I.pd.x < 0.5 && max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) <= 0.0 &&\n"
    "          max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0 &&\n"
    "          all(I.clip.xy >= I.rect.xy) && all(I.clip.zw <= I.rect.xy + I.rect.zw)) edge = 1.0;\n"
    "    }\n"
    "    return (pic * (col.a * edge)) * cover;\n"
    "  }\n"
    "  if (kind == 2) {\n"
    "    // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)\n"
    "    float a = mb_shadow(p - c, hs, rad, max(I.prm.w, 0.25));\n"
    "    // glass's: only outside its box (c2.y above it)\n"
    "    if (I.c2.x > 0.5) {\n"
    "      float2 q = p - c + float2(0.0, I.c2.y);\n"
    "      float db = mb_sd_box(q, hs, mb_corner_of(q, I.rr), band);\n"
    "      a *= saturate(0.5 + db * scale);\n"
    "    }\n"
    "    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
    "  }\n"
    "  float a = clamp(0.5 - d * scale, 0.0, 1.0);\n"
    "  if (kind == 5) {\n"
    "    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
    "    // the foot and right less), 0.5 wide\n"
    "    float3 g3 = backdrop(p);\n"
    "    float lg = luma(g3);\n"
    "    float ps = prog_glass ? fade_r : 1.0;\n"
    "    float ts = prog_glass ? (fade_r <= 0.0 ? 0.0 : pow(fade_r, 1.25)) : 1.0;\n"
    "    float sat = prog_glass ? lerp(1.0, I.prm.z, ps) : I.prm.z;\n"
    "    float bg_diff = prog_glass ? smoothstep(0.22, 0.72, abs(luma(col.rgb) - lg)) : 0.0;\n"
    "    float base_a = prog_glass ? lerp(col.a, min(0.86, col.a + 0.34), bg_diff) : col.a;\n"
    "    float ta = prog_glass ? (base_a * ts) : col.a;\n"
    "    g3 = max(lerp(float3(lg, lg, lg), g3, sat), 0.0);\n"
    "    g3 = g3 * (1.0 - ta) + col.rgb * ta;\n"
    "    if (I.c2.x + I.c2.y + I.c2.z > 0.0) {\n"
    "      float edge = saturate(0.5 + (d + 0.5) * scale);\n"
    "      float lit = saturate(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.rr), p - 0.5, I.rect, I.pd) * scale);\n"
    "      float back = saturate(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.rr), p + 0.5, I.rect, I.pd) * scale);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.x * edge);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.y * lit);\n"
    "      g3 = lerp(g3, float3(1.0, 1.0, 1.0), I.c2.z * back);\n"
    "    }\n"
    "    // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)\n"
    "    g3 += mb_dither(p * scale) * ps / 255.0;\n"
    "    float edge_a = prog_glass ? smoothstep(0.0, 0.04, fade_r) : 1.0;\n"
    "    return (float4(g3, 1.0) * (a * I.c2.w * edge_a)) * cover;\n"
    "  }\n"
    "  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
    "  float bw = I.prm.z;\n"
    "  if (bw > 0.0) {\n"
    "    float inner = clamp(0.5 - (d + bw) * scale, 0.0, 1.0);\n"
    "    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
    "    fill = lerp(bc, fill, inner);\n"
    "  }\n"
    "  return (fill * a) * cover;\n"
    "}\n"
    "// the flat pipeline: a ground's colour where it is covered whole, cut by straight clips alone (bands.h mb_pieces):\n"
    "// what fmain writes there, nothing worked out\n"
    "FOut fflat(VOut I) {\n"
    "  FOut o;\n"
    "  o.c = float4(I.color.rgb, 1.0) * I.color.a;\n"
    "  o.w = o.c.aaaa;\n"
    "  return o;\n"
    "}\n";

// glass's passes over its copy of what is under it
static const char *post_src =
    "// The backdrop's passes: pa.xy the source's texel, pa.z 1 halving (dual Kawase's down), 2 a Gaussian along pb.zw of\n"
    "// deviation pa.w (texels); pb.xy the last texel's centre of what the source holds\n"
    "cbuffer PU : register(b0) { float4 pa; float4 pb; float4 pc[9]; };\n"
    "Texture2D src : register(t0);\n"
    "SamplerState samp : register(s0);\n"
    "float4 vpost(uint vid : SV_VertexID) : SV_Position {\n"
    "  return float4(vid == 1 ? 3.0 : -1.0, vid == 2 ? -3.0 : 1.0, 0.0, 1.0);\n"
    "}\n"
    "float4 fpost(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 ts = pa.xy;\n"
    "  float2 lo = ts * 0.5, hi = pb.xy;\n"
    "  if (pa.z < 1.5) {\n"
    "    float2 uv = pos.xy * 2.0 * ts;\n"
    "    float4 s = src.SampleLevel(samp, clamp(uv, lo, hi), 0) * 4.0;\n"
    "    s += src.SampleLevel(samp, clamp(uv - ts, lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + ts, lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + float2(ts.x, -ts.y), lo, hi), 0);\n"
    "    s += src.SampleLevel(samp, clamp(uv + float2(-ts.x, ts.y), lo, hi), 0);\n"
    "    return s / 8.0;\n"
    "  }\n"
    "  float2 uv = pos.xy * ts;\n"
    "  float2 dir = pb.zw * ts;\n"
    "  float sg = pa.w;\n"
    "  float k = -0.5 / (sg * sg);\n"
    "  float4 s = src.SampleLevel(samp, clamp(uv, lo, hi), 0);\n"
    "  float wsum = 1.0;\n"
    "  int n = int(ceil(sg * 3.0));\n"
    "  [loop] for (int i = 1; i <= 64; i += 2) {\n"
    "    if (i > n) break;\n"
    "    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
    "    float w = w1 + w2;\n"
    "    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
    "    s += (src.SampleLevel(samp, clamp(uv + dir * off, lo, hi), 0) + src.SampleLevel(samp, clamp(uv - dir * off, lo, hi), 0)) * w;\n"
    "    wsum += 2.0 * w;\n"
    "  }\n"
    "  return s / wsum;\n"
    "}\n";

// The corner extension is a pass of its own, before the ordinary blur.
static const char *ad_src =
    "cbuffer AdU : register(b0) { float4 u_map; float4 u_uvc; float4 u_box; float4 u_param; };\n"
    "Texture2D bd : register(t0);\n"
    "Texture2D prev_ad : register(t1);\n"
    "SamplerState samp : register(s0);\n"
    "float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
    "float mb_unpack16(float2 rg) {\n"
    "  float hi = floor(saturate(rg.x) * 255.0 + 0.5);\n"
    "  float lo = floor(saturate(rg.y) * 255.0 + 0.5);\n"
    "  return (hi * 256.0 + lo) / 65535.0;\n"
    "}\n"
    "float2 mb_pack16(float v) {\n"
    "  float q = floor(saturate(v) * 65535.0 + 0.5);\n"
    "  float hi = floor(q / 256.0);\n"
    "  float lo = q - hi * 256.0;\n"
    "  return float2(hi / 255.0, lo / 255.0);\n"
    "}\n"
    "float4 fad(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 c = u_box.xy, h = u_box.zw;\n"
    "  float sum = 0.0, mx1 = -1.0, mx2 = -1.0, mn1 = 2.0, mn2 = 2.0;\n"
    "  [unroll] for (int iy = -1; iy <= 1; iy++) {\n"
    "    float py = c.y + float(iy) * (h.y * 0.60);\n"
    "    [unroll] for (int ix = -2; ix <= 2; ix++) {\n"
    "      float px = c.x + float(ix) * (h.x * 0.38);\n"
    "      float2 uv = clamp(float2(px, py) * u_map.xy + u_map.zw, u_uvc.xy, u_uvc.zw);\n"
    "      float y = luma(bd.SampleLevel(samp, uv, 0).rgb);\n"
    "      sum += y;\n"
    "      if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }\n"
    "      if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }\n"
    "    }\n"
    "  }\n"
    "  float bgL = (sum - mx1 - mx2 - mn1 - mn2) / 11.0;\n"
    "  int sid = int(u_param.w + 0.5);\n"
    "  float4 prev = prev_ad.Load(int3(sid, 0, 0));\n"
    "  float prevT = mb_unpack16(prev.rg);\n"
    "  float is_dark = u_param.x, is_new = u_param.y, dt = u_param.z;\n"
    "  float latch, target;\n"
    "  if (is_dark > 0.5) {\n"
    "    target = smoothstep(0.35, 0.85, bgL);\n"
    "    latch = target;\n"
    "  } else {\n"
    "    if (is_new > 0.5) latch = (bgL < 0.36) ? 1.0 : 0.0;\n"
    "    else if (prev.b > 0.5) latch = (bgL > 0.46) ? 0.0 : 1.0;\n"
    "    else latch = (bgL < 0.36) ? 1.0 : 0.0;\n"
    "    target = latch;\n"
    "  }\n"
    "  float nextT;\n"
    "  if (is_new > 0.5 || dt >= 1.0) nextT = target;\n"
    "  else if (dt <= 0.0) nextT = prevT;\n"
    "  else {\n"
    "    nextT = lerp(prevT, target, 1.0 - exp(-dt / 0.070));\n"
    "    if (abs(nextT - target) < 0.003) nextT = target;\n"
    "  }\n"
    "  return float4(mb_pack16(nextT), latch, saturate(bgL));\n"
    "}\n";

static const char *edge_src =
    "#define MB_CONTAINED_LOOP [loop]\n"
    MB_CORNER_SL
    "cbuffer PU : register(b0) { float4 pa; float4 pb; float4 pc[9]; };\n"
    "Texture2D src : register(t0);\n"
    "SamplerState samp : register(s0);\n"
    "float4 fedge(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 ts = pa.xy;\n"
    "  float2 lo = ts * 0.5, hi = pb.xy;\n"
    "  float2 p = pc[0].xy + pos.xy * pc[0].zw;\n"
    "  p = mb_contained_point(p, pc[1], pc[2], pc[3], pc[4], pc[5], pc[6], pc[7], pc[8], pc[0].z);\n"
    "  return src.SampleLevel(samp, clamp((p - pc[0].xy) / pc[0].zw * ts, lo, hi), 0);\n"
    "}\n";

static const char *prog_src =
    "cbuffer PU : register(b0) { float4 pa; float4 pb; float4 pc[9]; };\n"
    "Texture2D lv0 : register(t0); Texture2D lv1 : register(t1); Texture2D lv2 : register(t2); Texture2D lv3 : register(t3);\n"
    "SamplerState samp : register(s0);\n"
    "float4 fprog(float4 pos : SV_Position) : SV_Target {\n"
    "  float2 p = pc[0].xy + pos.xy * pc[0].zw;\n"
    "  float ramp = 1.0;\n"
    "  if (pc[1].y > 0.0) ramp *= saturate((p.y - pc[1].x) / pc[1].y);\n"
    "  if (pc[1].w > 0.0) ramp *= saturate((pc[1].z - p.y) / pc[1].w);\n"
    "  if (pc[2].y > 0.0) ramp *= saturate((p.x - pc[2].x) / pc[2].y);\n"
    "  if (pc[2].w > 0.0) ramp *= saturate((pc[2].z - p.x) / pc[2].w);\n"
    "  float sp = max(pc[3].x, 1.0);\n"
    "  float kf = pc[3].y;\n"
    "  float4 m0 = pc[4], m1 = pc[5], m2 = pc[6], m3 = pc[7];\n"
    "  if (kf < 0.5) return lv0.SampleLevel(samp, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw), 0);\n"
    "  float r = saturate(ramp);\n"
    "  if (r <= 0.0) return lv0.SampleLevel(samp, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw), 0);\n"
    "  if (r >= 1.0) {\n"
    "    int ki = int(kf + 0.5);\n"
    "    if (ki <= 1) return lv1.SampleLevel(samp, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw), 0);\n"
    "    if (ki == 2) return lv2.SampleLevel(samp, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw), 0);\n"
    "    return lv3.SampleLevel(samp, clamp(pos.xy * m3.xy, m3.xy * 4.0, m3.zw), 0);\n"
    "  }\n"
    "  float sig1 = pow(sp, 1.0 / kf);\n"
    "  float target_px = sp * pow(r, 1.15);\n"
    "  if (target_px <= sig1 || kf <= 1.05) {\n"
    "    float2 uv0_min = m0.xy * 0.5, uv0_max = m0.zw;\n"
    "    float2 c_uv = pos.xy * m0.xy;\n"
    "    float4 g_small;\n"
    "    if (target_px <= 0.01) {\n"
    "      g_small = lv0.SampleLevel(samp, clamp(c_uv, uv0_min, uv0_max), 0);\n"
    "    } else {\n"
    "      float r_tap = target_px * 1.5;\n"
    "      float2 d0 = float2(r_tap, 0.0) * m0.xy;\n"
    "      float2 d1 = float2(0.0, r_tap) * m0.xy;\n"
    "      float2 dd = float2(r_tap * 0.70710678, r_tap * 0.70710678) * m0.xy;\n"
    "      g_small  = lv0.SampleLevel(samp, clamp(c_uv, uv0_min, uv0_max), 0) * 0.25;\n"
    "      g_small += (lv0.SampleLevel(samp, clamp(c_uv + d0, uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv - d0, uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv + d1, uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv - d1, uv0_min, uv0_max), 0)) * 0.125;\n"
    "      g_small += (lv0.SampleLevel(samp, clamp(c_uv + dd, uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv - dd, uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv + float2(dd.x, -dd.y), uv0_min, uv0_max), 0) +\n"
    "                  lv0.SampleLevel(samp, clamp(c_uv + float2(-dd.x, dd.y), uv0_min, uv0_max), 0)) * 0.0625;\n"
    "    }\n"
    "    float blend1 = smoothstep(sig1 * 0.65, sig1, target_px);\n"
    "    if (blend1 > 0.0) {\n"
    "      float4 c_lv1 = lv1.SampleLevel(samp, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw), 0);\n"
    "      return lerp(g_small, c_lv1, blend1);\n"
    "    }\n"
    "    return g_small;\n"
    "  }\n"
    "  float lv_u = clamp(1.0 + (kf - 1.0) * log(target_px / sig1) / max(log(sp / sig1), 1e-4), 1.0, kf);\n"
    "  int idx = min(int(floor(lv_u)), int(kf + 0.5) - 1);\n"
    "  if (idx < 0) idx = 0;\n"
    "  float f = lv_u - float(idx);\n"
    "  float4 c0, c1;\n"
    "  if (idx == 0) {\n"
    "    c0 = lv0.SampleLevel(samp, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw), 0);\n"
    "    c1 = lv1.SampleLevel(samp, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw), 0);\n"
    "  } else if (idx == 1) {\n"
    "    c0 = lv1.SampleLevel(samp, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw), 0);\n"
    "    c1 = lv2.SampleLevel(samp, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw), 0);\n"
    "  } else {\n"
    "    c0 = lv2.SampleLevel(samp, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw), 0);\n"
    "    c1 = lv3.SampleLevel(samp, clamp(pos.xy * m3.xy, m3.xy * 4.0, m3.zw), 0);\n"
    "  }\n"
    "  return lerp(c0, c1, f);\n"
    "}\n";

// A shader's bytecode kept on disk once compiled (shader_dir: an app's own folder, or the one its program says; a
// program that is neither, a demo, keeps none), so a run after the first takes it from there: compiling these at level
// 3 took 2.4 to 3.6 s of a window's start on a fast machine (measured on an RTX 5080's, 2026-11-13), all of it before
// the first frame. A file's name is of all it is compiled of (its source, entry, target, defines, the compiler's
// version and the level), so a changed shader, or another compiler, is compiled anew and kept beside the old, and
// programs that share a folder share what is the same. A file says how long its bytecode is and its hash before it:
// one cut short or damaged is deleted and compiled again, never handed to the device. One that cannot be read or
// written is compiled as before.
struct ShaderKept {
  char magic[4];  // "MBSH"
  UINT32 size;
  UINT64 hash;
};

static UINT64 shader_fnv(const void *p, size_t n, UINT64 h) {
  const unsigned char *b = (const unsigned char *)p;
  for (size_t i = 0; i < n; i++) {
    h ^= b[i];
    h *= 1099511628211ULL;
  }
  return h;
}

static const UINT64 shader_fnv_start = 1469598103934665603ULL;

// The folder the bytecode is kept in, found once ("": none is kept). MBUI_SHADERS names it where the program says so
// (its environment or its own: win_life.h's app_env; %NAMES% in it read of the environment), for a program that keeps
// its shaders and is no app (an app's id brings its one instance, its tray icon and its logs with it); else it is the
// app's own, %LOCALAPPDATA%\<the app's id>\shaders. %LOCALAPPDATA% is read of the environment, not asked of the shell:
// shell32 loaded for it here was 0.27 s of a start that took its shaders from the folder (measured, 2026-11-13).
static wchar_t shader_dir[MAX_PATH * 2];
static INIT_ONCE shader_dir_once = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK shader_dir_find(PINIT_ONCE, PVOID, PVOID *) {
  wchar_t dir[MAX_PATH * 2] = L"";
  const wchar_t *said = mb_win_env(L"MBUI_SHADERS");
  if (said && *said) {
    DWORD n = ExpandEnvironmentStringsW(said, dir, MAX_PATH * 2);
    if (n == 0 || n > MAX_PATH * 2) return TRUE;
  } else {
    const wchar_t *id = mb_win_app_id();
    wchar_t local[MAX_PATH];
    DWORD n = GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH);
    if (!id || !*id || n == 0 || n >= MAX_PATH) return TRUE;
    wchar_t app[MAX_PATH * 2];
    int m = _snwprintf(app, MAX_PATH * 2, L"%ls\\%ls", local, id);
    if (m < 0 || m >= MAX_PATH * 2) return TRUE;
    CreateDirectoryW(app, NULL);
    m = _snwprintf(dir, MAX_PATH * 2, L"%ls\\shaders", app);
    if (m < 0 || m >= MAX_PATH * 2) return TRUE;
  }
  // (its last folder made here; a said one's parents are the program's to have made)
  if (!CreateDirectoryW(dir, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) return TRUE;
  wcscpy(shader_dir, dir);
  return TRUE;
}

// Where the bytecode of `key` is kept (false: nowhere).
static bool shader_path(wchar_t *out, size_t cap, UINT64 key) {
  InitOnceExecuteOnce(&shader_dir_once, shader_dir_find, NULL, NULL);
  if (!*shader_dir) return false;
  int n = _snwprintf(out, cap, L"%ls\\%016llx.cso", shader_dir, (unsigned long long)key);
  return n > 0 && (size_t)n < cap;
}

// The bytecode kept at `path`, whole and as it was written; NULL (the file deleted where it is there and is not that).
static ID3DBlob *shader_kept(const wchar_t *path) {
  HANDLE f = CreateFileW(path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return NULL;
  ShaderKept head;
  LARGE_INTEGER size;
  ID3DBlob *blob = NULL;
  DWORD got = 0;
  bool ok = GetFileSizeEx(f, &size) && ReadFile(f, &head, sizeof head, &got, NULL) && got == sizeof head &&
            memcmp(head.magic, "MBSH", 4) == 0 && head.size > 0 && head.size < (64u << 20) &&
            size.QuadPart == (LONGLONG)sizeof head + (LONGLONG)head.size &&
            SUCCEEDED(D3DCreateBlob(head.size, &blob)) &&
            ReadFile(f, blob->GetBufferPointer(), head.size, &got, NULL) && got == head.size &&
            shader_fnv(blob->GetBufferPointer(), head.size, shader_fnv_start) == head.hash;
  CloseHandle(f);
  if (ok) return blob;
  if (blob) blob->Release();
  DeleteFileW(path);
  return NULL;
}

static void shader_keep(const wchar_t *path, ID3DBlob *code) {
  if (code->GetBufferSize() == 0 || code->GetBufferSize() >= (64u << 20)) return;
  // (written whole under another name and moved into place: a run reading it meanwhile reads none or all of it; the
  // name its thread's, the kinds' shaders being compiled on another: make_kinds)
  wchar_t part[MAX_PATH * 2 + 32];
  int n = _snwprintf(part, MAX_PATH * 2 + 32, L"%ls.%lu.%lu.part", path, GetCurrentProcessId(), GetCurrentThreadId());
  if (n < 0 || n >= MAX_PATH * 2 + 32) return;
  HANDLE f = CreateFileW(part, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, 0, NULL);
  if (f == INVALID_HANDLE_VALUE) return;
  ShaderKept head;
  memcpy(head.magic, "MBSH", 4);
  head.size = (UINT32)code->GetBufferSize();
  head.hash = shader_fnv(code->GetBufferPointer(), head.size, shader_fnv_start);
  DWORD put = 0;
  bool ok = WriteFile(f, &head, sizeof head, &put, NULL) && put == sizeof head &&
            WriteFile(f, code->GetBufferPointer(), head.size, &put, NULL) && put == head.size;
  CloseHandle(f);
  if (!ok || !MoveFileExW(part, path, MOVEFILE_REPLACE_EXISTING)) DeleteFileW(part);
}

static ID3DBlob *compile(const char *entry, const char *target, const char *src = shader_src,
                         const D3D_SHADER_MACRO *defines = NULL) {
  UINT64 key = shader_fnv(src, strlen(src), shader_fnv_start);
  key = shader_fnv(entry, strlen(entry) + 1, key);
  key = shader_fnv(target, strlen(target) + 1, key);
  for (const D3D_SHADER_MACRO *d = defines; d && d->Name; d++) {
    key = shader_fnv(d->Name, strlen(d->Name) + 1, key);
    key = shader_fnv(d->Definition, strlen(d->Definition) + 1, key);
  }
  UINT32 made_by[2] = {D3D_COMPILER_VERSION, D3DCOMPILE_OPTIMIZATION_LEVEL3};
  key = shader_fnv(made_by, sizeof made_by, key);
  wchar_t path[MAX_PATH * 2 + 32];
  bool kept = shader_path(path, MAX_PATH * 2, key);
  if (kept) {
    ID3DBlob *was = shader_kept(path);
    if (was) return was;
  }
  ID3DBlob *code = NULL, *err = NULL;
  HRESULT hr = D3DCompile(src, strlen(src), "mbui", defines, NULL, entry, target,
                          D3DCOMPILE_OPTIMIZATION_LEVEL3, 0, &code, &err);
  if (FAILED(hr)) fprintf(stderr, "shader %s: %s\n", entry, err ? (char *)err->GetBufferPointer() : "?");
  if (err) err->Release();
  if (code && kept) shader_keep(path, code);
  return code;
}

static HRESULT make_device(D3D_DRIVER_TYPE type, UINT flags) {
  D3D_FEATURE_LEVEL levels[] = {D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1, D3D_FEATURE_LEVEL_10_0};
  return D3D11CreateDevice(NULL, type, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT | flags, levels, 3,
                           D3D11_SDK_VERSION, &dev, NULL, &ctx);
}

// The window in place's canvas as a composition swap chain (premultiplied alpha) on top of a DirectComposition tree whose
// other visual, under it, holds the native views, the composition's device made with the first; 0 (nothing made) where
// that cannot be had. MBUI_NO_DCOMP=1: not tried.
static int make_composed(IDXGIDevice1 *xdev, HWND hwnd) {
  const char *no = getenv("MBUI_NO_DCOMP");
  if (no && *no && *no != '0') return 0;
  RECT rc;
  GetClientRect(hwnd, &rc);
  DXGI_SWAP_CHAIN_DESC1 sd = {};
  sd.Width = rc.right > 0 ? (UINT)rc.right : 1;
  sd.Height = rc.bottom > 0 ? (UINT)rc.bottom : 1;
  sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sd.SampleDesc.Count = 1;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  sd.BufferCount = 2;
  sd.Scaling = DXGI_SCALING_STRETCH;
  sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
  sd.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
  int made_device = !dcomp;
  HRESULT hr = dcomp ? S_OK : DCompositionCreateDevice(xdev, __uuidof(IDCompositionDevice), (void **)&dcomp);
  if (SUCCEEDED(hr)) hr = dcomp->CreateTargetForHwnd(hwnd, TRUE, &dtarget);
  if (SUCCEEDED(hr)) hr = dxgi_factory->CreateSwapChainForComposition(dev, &sd, NULL, &chain);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&droot);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&dunder);
  if (SUCCEEDED(hr)) hr = dcomp->CreateVisual(&dcanvas);
  if (SUCCEEDED(hr)) hr = dcanvas->SetContent(chain);
  if (SUCCEEDED(hr)) hr = droot->AddVisual(dunder, FALSE, NULL);
  if (SUCCEEDED(hr)) hr = droot->AddVisual(dcanvas, TRUE, dunder);
  if (SUCCEEDED(hr)) hr = dtarget->SetRoot(droot);
  if (SUCCEEDED(hr)) hr = dcomp->Commit();
  if (SUCCEEDED(hr)) {
    fb_w = (int)sd.Width;
    fb_h = (int)sd.Height;
    return 1;
  }
  fprintf(stderr, "no DirectComposition (0x%08lx): the window's own swap chain, no native views\n", (unsigned long)hr);
  if (dcanvas) dcanvas->Release();
  if (dunder) dunder->Release();
  if (droot) droot->Release();
  if (chain) chain->Release();
  if (dtarget) dtarget->Release();
  if (dcomp && made_device) dcomp->Release(), dcomp = NULL;
  dcanvas = dunder = droot = NULL;
  chain = NULL;
  dtarget = NULL;
  return 0;
}

// The window in place's swap chain, its own where there is no composition: a flip model's, or before Windows 10 a
// blit model's (flip_chain says which, the first window's for all)
static int make_own_chain(HWND hwnd) {
  DXGI_SWAP_CHAIN_DESC1 sd = {};
  sd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  sd.SampleDesc.Count = 1;
  sd.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
  sd.BufferCount = 2;
  sd.Scaling = DXGI_SCALING_NONE;
  sd.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
  if (flip_chain && SUCCEEDED(dxgi_factory->CreateSwapChainForHwnd(dev, hwnd, &sd, NULL, NULL, &chain))) return 1;
  // before Windows 10
  sd.Scaling = DXGI_SCALING_STRETCH;
  sd.SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
  sd.BufferCount = 1;
  flip_chain = 0;
  return SUCCEEDED(dxgi_factory->CreateSwapChainForHwnd(dev, hwnd, &sd, NULL, NULL, &chain));
}

static void make_pipeline(void);

int mb_render_init(void *hwnd) {
  // (with its video side where the GPU has one: a remote screen decoded and shown by the GPU, win_stream.cpp)
  if (FAILED(make_device(D3D_DRIVER_TYPE_HARDWARE, D3D11_CREATE_DEVICE_VIDEO_SUPPORT)) &&
      FAILED(make_device(D3D_DRIVER_TYPE_HARDWARE, 0)) && FAILED(make_device(D3D_DRIVER_TYPE_WARP, 0))) {
    fprintf(stderr, "no Direct3D 11 device\n");
    return 0;
  }
  IDXGIDevice1 *xdev = NULL;
  IDXGIAdapter *adapter = NULL;
  dev->QueryInterface(__uuidof(IDXGIDevice1), (void **)&xdev);
  xdev->SetMaximumFrameLatency(1);  // input to photon over throughput
  xdev->GetAdapter(&adapter);
  adapter->GetParent(__uuidof(IDXGIFactory2), (void **)&dxgi_factory);
  flip_chain = 1;
  if (make_composed(xdev, (HWND)hwnd)) {
    // the composition's swap chain, made at the window's size (its first buffers' view: at the first frame's size)
    fb_w = fb_h = 0;
  } else {
    make_own_chain((HWND)hwnd);
  }
  dxgi_factory->MakeWindowAssociation((HWND)hwnd, DXGI_MWA_NO_ALT_ENTER);
  adapter->Release();
  xdev->Release();
  make_pipeline();
  return chain != NULL;
}

// Window `wid` of the run beside the first (win_app.c win_open), its HWND made: its swap chain as the first's is (in the
// composition, the views under it, where the first's is), nothing drawn in it yet. Window 0 put back in place after.
int mb_render_open(int wid, void *hwnd) {
  if (wid <= 0 || wid >= MB_WINS || !dev || !dxgi_factory) return 0;
  RenderWin *back = rw;
  rw = &render_wins[wid];
  render_win_fresh(rw);
  int ok;
  if (dcomp) {
    ok = make_composed(NULL, (HWND)hwnd);
    if (ok) fb_w = fb_h = 0;
  } else {
    ok = make_own_chain((HWND)hwnd);
  }
  if (ok) dxgi_factory->MakeWindowAssociation((HWND)hwnd, DXGI_MWA_NO_ALT_ENTER);
  rw = back;
  return ok;
}

// What window `wid` kept let go of, as it closes (its views taken off it first: win_views.cpp mb_views_forget): the
// next window given its number starts as none was drawn.
void mb_render_forget(int wid) {
  if (wid <= 0 || wid >= MB_WINS) return;
  RenderWin *back = rw;
  rw = &render_wins[wid];
  if (canvas_rtv) canvas_rtv->Release();
  if (canvas) canvas->Release();
  for (int i = 0; i < 2; i++) {
    if (rw->ad_tex[i].srv) rw->ad_tex[i].srv->Release();
    if (rw->ad_tex[i].rt) rw->ad_tex[i].rt->Release();
    if (rw->ad_tex[i].t) rw->ad_tex[i].t->Release();
  }
  if (rtv) rtv->Release();
  if (dtarget) dtarget->SetRoot(NULL);
  if (dcanvas) dcanvas->SetContent(NULL);
  if (droot) {
    droot->RemoveAllVisuals();
    droot->Release();
  }
  if (dunder) {
    dunder->RemoveAllVisuals();
    dunder->Release();
  }
  if (dcanvas) dcanvas->Release();
  if (chain) chain->Release();
  if (dtarget) dtarget->Release();
  if (dcomp) dcomp->Commit();
  free(last_inst);
  // (the device's state left naming none of its views)
  ctx->OMSetRenderTargets(0, NULL, NULL);
  ctx->Flush();
  render_win_fresh(rw);
  rw = back == &render_wins[wid] ? &render_wins[0] : back;
}

void *mb_render_views_visual_of(int wid) {
  if (wid < 0 || wid >= MB_WINS) return NULL;
  RenderWin *back = rw;
  rw = &render_wins[wid];
  IDCompositionVisual *v = dunder;
  rw = back;
  return v;
}

// The kinds drawn by a pixel shader of their own: the shader with its kind fixed (ONE_KIND), so each is compiled to its
// kind's branch alone and a pixel of it is shaded with the registers that branch needs, not the most any kind's does
// (as Metal's: apple_render.m kind_pipe says what it saved there), what it draws the same to the byte. Compiled after
// the rest, on a thread of their own (kinds_thread), the device's own to make them on: until they are, the one for
// any kind draws every kind, the same pixels.
#define MB_KIND_LIQUID_SINGLE 13
#define MB_KINDS 14
static int has_own_ps(int kind) {
  return (kind >= 0 && kind <= 7) || kind == 10 || kind == 11 || kind == MB_KIND_LIQUID_SINGLE;
}
static ID3D11PixelShader *kps[MB_KINDS];
static HANDLE kinds_thread;
static volatile LONG kinds_ready;

static DWORD WINAPI make_kinds(void *arg) {
  ID3D11Device *d = (ID3D11Device *)arg;
  for (int k = 0; k < MB_KINDS; k++) {
    if (!has_own_ps(k)) continue;
    char one[8];
    snprintf(one, sizeof one, "%d", k);
    D3D_SHADER_MACRO defines[2] = {{"ONE_KIND", one}, {NULL, NULL}};
    ID3DBlob *code = compile("fmain", "ps_4_0", shader_src, defines);
    if (code) {
      d->CreatePixelShader(code->GetBufferPointer(), code->GetBufferSize(), NULL, &kps[k]);
      code->Release();
    }
  }
  InterlockedExchange(&kinds_ready, 1);
  return 0;
}

// The pixel shader that draws a run of instances of `kind`.
static ID3D11PixelShader *kind_ps(int kind) {
  return has_own_ps(kind) && InterlockedCompareExchange(&kinds_ready, 1, 1) && kps[kind] ? kps[kind] : ps;
}

// The shaders, buffers, atlas and states every target is drawn with (the window's, the offscreen one).
static void make_pipeline(void) {
  // (those of a device before, if there was one, let go once made)
  if (kinds_thread) {
    WaitForSingleObject(kinds_thread, INFINITE);
    CloseHandle(kinds_thread);
    kinds_thread = NULL;
  }
  kinds_ready = 0;
  for (int k = 0; k < MB_KINDS; k++)
    if (kps[k]) {
      kps[k]->Release();
      kps[k] = NULL;
    }
  ID3DBlob *vcode = compile("vmain", "vs_4_0"), *pcode = compile("fmain", "ps_4_0"), *fcode = compile("fflat", "ps_4_0");
  dev->CreateVertexShader(vcode->GetBufferPointer(), vcode->GetBufferSize(), NULL, &vs);
  dev->CreatePixelShader(pcode->GetBufferPointer(), pcode->GetBufferSize(), NULL, &ps);
  dev->CreatePixelShader(fcode->GetBufferPointer(), fcode->GetBufferSize(), NULL, &ps_flat);
  fcode->Release();
  // the instance's fifteen float4s (scene.mbt): rect, p, color, c2, clip, pad, the clip's corners' radii, how smooth,
  // how it is turned, a box's corners' radii, the outer clip's rect, corners' radii and how smooth, how it fades down
  // and across
  D3D11_INPUT_ELEMENT_DESC el[15];
  for (UINT i = 0; i < 15; i++)
    el[i] = {"INST", i, DXGI_FORMAT_R32G32B32A32_FLOAT, 0, i * 16, D3D11_INPUT_PER_INSTANCE_DATA, 1};
  dev->CreateInputLayout(el, 15, vcode->GetBufferPointer(), vcode->GetBufferSize(), &layout);
  vcode->Release();
  pcode->Release();
  kinds_thread = CreateThread(NULL, 0, make_kinds, dev, 0, NULL);
  ID3DBlob *pv = compile("vpost", "vs_4_0", post_src), *pp = compile("fpost", "ps_4_0", post_src);
  ID3DBlob *ep = compile("fedge", "ps_4_0", edge_src);
  ID3DBlob *gp = compile("fprog", "ps_4_0", prog_src);
  ID3DBlob *ap = compile("fad", "ps_4_0", ad_src);
  dev->CreateVertexShader(pv->GetBufferPointer(), pv->GetBufferSize(), NULL, &pvs);
  dev->CreatePixelShader(pp->GetBufferPointer(), pp->GetBufferSize(), NULL, &pps);
  dev->CreatePixelShader(ep->GetBufferPointer(), ep->GetBufferSize(), NULL, &edge_ps);
  dev->CreatePixelShader(gp->GetBufferPointer(), gp->GetBufferSize(), NULL, &prog_ps);
  dev->CreatePixelShader(ap->GetBufferPointer(), ap->GetBufferSize(), NULL, &ad_ps);
  pv->Release();
  pp->Release();
  ep->Release();
  gp->Release();
  ap->Release();

  D3D11_BUFFER_DESC ud = {16, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&ud, NULL, &ubuf);
  D3D11_BUFFER_DESC pd = {32 + sizeof(MBContained), D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&pd, NULL, &pbuf);
  D3D11_BUFFER_DESC gd = {(UINT)sizeof(GU), D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&gd, NULL, &gbuf);
  D3D11_BUFFER_DESC adbd = {64, D3D11_USAGE_DEFAULT, D3D11_BIND_CONSTANT_BUFFER, 0, 0, 0};
  dev->CreateBuffer(&adbd, NULL, &ad_cb);

  D3D11_TEXTURE2D_DESC td = {};
  td.Width = td.Height = (UINT)mb_atlas_size;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_SHADER_RESOURCE;
  dev->CreateTexture2D(&td, NULL, &atlas);
  dev->CreateShaderResourceView(atlas, NULL, &atlas_srv);

  D3D11_SAMPLER_DESC smp = {};
  smp.Filter = D3D11_FILTER_MIN_MAG_MIP_LINEAR;
  smp.AddressU = smp.AddressV = smp.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
  smp.MaxLOD = D3D11_FLOAT32_MAX;
  dev->CreateSamplerState(&smp, &sampler);

  // premultiplied alpha, as on Metal and GLES
  D3D11_BLEND_DESC bd = {};
  D3D11_RENDER_TARGET_BLEND_DESC &b = bd.RenderTarget[0];
  b.BlendEnable = TRUE;
  b.SrcBlend = b.SrcBlendAlpha = D3D11_BLEND_ONE;
  b.DestBlend = D3D11_BLEND_INV_SRC1_COLOR;
  b.DestBlendAlpha = D3D11_BLEND_INV_SRC1_ALPHA;
  b.BlendOp = b.BlendOpAlpha = D3D11_BLEND_OP_ADD;
  b.RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
  dev->CreateBlendState(&bd, &blend);

  D3D11_RASTERIZER_DESC rd = {};
  rd.FillMode = D3D11_FILL_SOLID;
  rd.CullMode = D3D11_CULL_NONE;
  rd.DepthClipEnable = TRUE;
  dev->CreateRasterizerState(&rd, &raster);
  // (a part drawn again: cut to it)
  rd.ScissorEnable = TRUE;
  dev->CreateRasterizerState(&rd, &raster_cut);
}

void *mb_render_device(void) { return dev; }
void *mb_render_context(void) { return ctx; }

void *mb_render_dcomp(void) { return dcomp; }
void *mb_render_views_visual(void) { return dunder; }
void mb_render_commit(void) {
  if (dcomp) dcomp->Commit();
}

// A view placed (win_views.cpp apply_place) is committed with the frame that paints its hole where it now is: just
// after that frame's Present, both then taken by the same composition. Committed as it was placed, the view moved a
// frame ahead of its hole while a list scrolled, the window's black showing along its edge in the hole (2026-10-29).
static bool commit_after_present;
extern "C" void mb_host_request_frame(void);
void mb_render_commit_with_frame(void) {
  commit_after_present = true;
  mb_host_request_frame();
}
void mb_render_commit_soon(void) {
  if (!commit_after_present) mb_render_commit();
}
static void commit_presented(void) {
  if (!commit_after_present) return;
  commit_after_present = false;
  mb_render_commit();
}

static void ensure_canvas(int tw, int th);

void mb_render_set_size(int pw, int ph, double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  if (!chain || (pw == fb_w && ph == fb_h && rtv)) return;
  if (rtv) rtv->Release();
  rtv = NULL;
  ctx->OMSetRenderTargets(0, NULL, NULL);
  ensure_canvas(0, 0);
  chain->ResizeBuffers(0, (UINT)pw, (UINT)ph, DXGI_FORMAT_UNKNOWN, 0);
  ID3D11Texture2D *back = NULL;
  if (SUCCEEDED(chain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void **)&back))) {
    dev->CreateRenderTargetView(back, NULL, &rtv);
    back->Release();
  }
  fb_w = pw;
  fb_h = ph;
}

#ifndef MB_WIN_ATLAS_UPDATE
#define MB_WIN_ATLAS_UPDATE(c, tex, box, data, pitch) ((c)->UpdateSubresource((tex), 0, (box), (data), (pitch), 0))
#endif

// Glyphs queued for the atlas before the next draw: consecutive glyphs placed on the same shelf (same y, x == right + 1
// within the same 512px atlas plot) are merged into a single horizontal UpdateSubresource strip in atlas_flush().
struct AtlasPut {
  int x, y, w, h;
  size_t off;
};
static AtlasPut *atlas_puts;
static int atlas_puts_n, atlas_puts_cap;
static uint8_t *atlas_px_buf;
static size_t atlas_px_len, atlas_px_cap;
static uint8_t *atlas_row_buf;
static size_t atlas_row_cap;

static void atlas_flush(void) {
  if (atlas_puts_n == 0 || !ctx || !atlas) return;
  int i = 0;
  while (i < atlas_puts_n) {
    AtlasPut first = atlas_puts[i];
    int plot_x = first.x >> 9;
    int j = i + 1;
    int right = first.x + first.w;
    int h = first.h;
    while (j < atlas_puts_n) {
      AtlasPut g = atlas_puts[j];
      if (g.y != first.y || g.x != right + 1 || (g.x >> 9) != plot_x) break;
      right = g.x + g.w;
      if (g.h > h) h = g.h;
      j++;
    }
    if (j - i == 1) {
      D3D11_BOX box = {(UINT)first.x, (UINT)first.y, 0, (UINT)(first.x + first.w), (UINT)(first.y + first.h), 1};
      MB_WIN_ATLAS_UPDATE(ctx, atlas, &box, atlas_px_buf + first.off, (UINT)first.w * 4);
    } else {
      int w = right - first.x;
      size_t bytes = (size_t)w * (size_t)h * 4;
      if (bytes > atlas_row_cap) {
        size_t cap = bytes <= (SIZE_MAX / 2) ? bytes * 2 : bytes;
        uint8_t *grown = (uint8_t *)realloc(atlas_row_buf, cap);
        if (!grown && cap != bytes) {
          cap = bytes;
          grown = (uint8_t *)realloc(atlas_row_buf, cap);
        }
        if (grown) {
          atlas_row_buf = grown;
          atlas_row_cap = cap;
        }
      }
      if (atlas_row_buf && atlas_row_cap >= bytes) {
        memset(atlas_row_buf, 0, bytes);
        for (int k = i; k < j; k++) {
          AtlasPut g = atlas_puts[k];
          int ox = g.x - first.x;
          const uint8_t *src = atlas_px_buf + g.off;
          size_t row_bytes = (size_t)g.w * 4;
          for (int r = 0; r < g.h; r++) {
            memcpy(atlas_row_buf + ((size_t)r * (size_t)w + (size_t)ox) * 4, src + (size_t)r * row_bytes, row_bytes);
          }
        }
        D3D11_BOX box = {(UINT)first.x, (UINT)first.y, 0, (UINT)(first.x + w), (UINT)(first.y + h), 1};
        MB_WIN_ATLAS_UPDATE(ctx, atlas, &box, atlas_row_buf, (UINT)w * 4);
      } else {
        for (int k = i; k < j; k++) {
          AtlasPut g = atlas_puts[k];
          D3D11_BOX box = {(UINT)g.x, (UINT)g.y, 0, (UINT)(g.x + g.w), (UINT)(g.y + g.h), 1};
          MB_WIN_ATLAS_UPDATE(ctx, atlas, &box, atlas_px_buf + g.off, (UINT)g.w * 4);
        }
      }
    }
    i = j;
  }
  atlas_puts_n = 0;
  atlas_px_len = 0;
}

void mb_atlas_upload(int x, int y, int w, int h, const void *rgba) {
  if (w <= 0 || h <= 0 || x < 0 || y < 0 || x + w > mb_atlas_size || y + h > mb_atlas_size || !rgba) return;
  size_t bytes = (size_t)w * (size_t)h * 4;
  if (atlas_puts_n == atlas_puts_cap) {
    int cap = atlas_puts_cap ? atlas_puts_cap * 2 : 128;
    AtlasPut *grown = (AtlasPut *)realloc(atlas_puts, (size_t)cap * sizeof *atlas_puts);
    if (!grown) {
      if (ctx && atlas) {
        atlas_flush();
        D3D11_BOX box = {(UINT)x, (UINT)y, 0, (UINT)(x + w), (UINT)(y + h), 1};
        MB_WIN_ATLAS_UPDATE(ctx, atlas, &box, rgba, (UINT)w * 4);
      }
      return;
    }
    atlas_puts = grown;
    atlas_puts_cap = cap;
  }
  if (bytes > SIZE_MAX - atlas_px_len) {
    atlas_flush();
  }
  if (atlas_px_len + bytes > atlas_px_cap) {
    size_t need = atlas_px_len + bytes;
    size_t cap = atlas_px_cap ? atlas_px_cap : (1u << 16);
    while (cap < need) cap = cap <= (SIZE_MAX / 2) ? cap * 2 : need;
    uint8_t *grown = (uint8_t *)realloc(atlas_px_buf, cap);
    if (!grown && cap != need) {
      cap = need;
      grown = (uint8_t *)realloc(atlas_px_buf, cap);
    }
    if (!grown) {
      if (ctx && atlas) {
        atlas_flush();
        D3D11_BOX box = {(UINT)x, (UINT)y, 0, (UINT)(x + w), (UINT)(y + h), 1};
        MB_WIN_ATLAS_UPDATE(ctx, atlas, &box, rgba, (UINT)w * 4);
      }
      return;
    }
    atlas_px_buf = grown;
    atlas_px_cap = cap;
  }
  size_t off = atlas_px_len;
  memcpy(atlas_px_buf + off, rgba, bytes);
  atlas_px_len += bytes;
  atlas_puts[atlas_puts_n++] = {x, y, w, h, off};
}

// ---------------------------------------------------------------------------
// Glass: when the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far
// under it (its rects with room for the blur round them) is copied out, halved down to where the blur is a few texels
// wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left, and drawn
// through. Level 0, the copy, has 8 bits a channel as the target has; what the passes write keeps 10 (R10G10B10A2, in
// as many bytes): at 8 each pass rounds the frost's slow slopes into flat steps, a texel of the last level 8 pixels
// wide on the screen (a blur under 4 pixels, too narrow to halve, is written back into the copy: it leaves no slope
// that wide).

static level level_tex(DXGI_FORMAT format, int w, int h) {
  level l = {NULL, NULL, NULL, w > 0 ? w : 1, h > 0 ? h : 1, format};
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)l.w;
  td.Height = (UINT)l.h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = format;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &l.t)) || !l.t) return level{};
  if (FAILED(dev->CreateRenderTargetView(l.t, NULL, &l.rt)) || !l.rt) {
    l.t->Release();
    return level{};
  }
  if (FAILED(dev->CreateShaderResourceView(l.t, NULL, &l.srv)) || !l.srv) {
    l.rt->Release();
    l.t->Release();
    return level{};
  }
  return l;
}

static void glass_free(void);
static void slots_invalidate(void);

static int ensure_levels(int w, int h) {
  if (lv[0].t && lv_w >= w && lv_h >= h) return 1;
  for (int j = 0; j < 5; j++) {
    if (lv[j].srv) lv[j].srv->Release();
    if (lv[j].rt) lv[j].rt->Release();
    if (lv[j].t) lv[j].t->Release();
    lv[j] = level{};
  }
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++) {
    lv[j] = level_tex(j == 0 ? DXGI_FORMAT_B8G8R8A8_UNORM : DXGI_FORMAT_R10G10B10A2_UNORM, (lv_w + (1 << j) - 1) >> j,
                      (lv_h + (1 << j) - 1) >> j);
    if (!lv[j].t || !lv[j].rt || !lv[j].srv) {
      glass_free();
      return 0;
    }
  }
  lv[4] = level_tex(DXGI_FORMAT_R10G10B10A2_UNORM, lv_w, lv_h);
  if (!lv[4].t || !lv[4].rt || !lv[4].srv) {
    glass_free();
    return 0;
  }
  slots_invalidate();
  return 1;
}

// Glass's own textures let go of: the levels (made again at the size the next capture needs, ensure_levels, its blur
// the same to the byte). Unbound first where a pass or the glass's draw left them (t0-t2): the context holds what is
// bound till it is bound again.
static int ad_mode = 1;  // 1 = update, 0 = read-only, -1 = stateless
static double ad_cur_dt = 0.0;

static void ad_forget(RenderWin *w) {
  if (!w) return;
  memset(w->ad_slots, 0, sizeof w->ad_slots);
  w->ad_last_time = 0.0;
  w->ad_settling = 0;
}

static int ensure_ad_tex(RenderWin *w) {
  if (!w || !dev) return 0;
  if (w->ad_tex[0].t) return 1;
  for (int i = 0; i < 2; i++) {
    w->ad_tex[i] = level_tex(DXGI_FORMAT_R8G8B8A8_UNORM, MB_ADAPTIVE_MAX, 1);
    if (!w->ad_tex[i].t) return 0;
  }
  w->ad_cur = 0;
  return 1;
}

static void ad_fill_gu(RenderWin *w) {
  if (!w || ad_mode < 0) {
    gu.ad_meta[0] = 0.0f;
    return;
  }
  int max_active = 0;
  for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
    if (w->ad_slots[i].active) {
      gu.ad_box[i][0] = w->ad_slots[i].cx;
      gu.ad_box[i][1] = w->ad_slots[i].cy;
      gu.ad_box[i][2] = w->ad_slots[i].hx;
      gu.ad_box[i][3] = w->ad_slots[i].hy;
      max_active = i + 1;
    } else {
      gu.ad_box[i][0] = -1e9f;
      gu.ad_box[i][1] = -1e9f;
      gu.ad_box[i][2] = -1e9f;
      gu.ad_box[i][3] = -1e9f;
    }
  }
  gu.ad_meta[0] = (float)max_active;
}

struct WinAdPend {
  int sid, is_new, is_dark;
  float cx, cy, hx, hy;
};

static int ad_collect_and_match(RenderWin *w, const float *f, int32_t start, int32_t count, int backdrop_changed,
                                double dt, uint64_t serial, WinAdPend out[MB_ADAPTIVE_MAX]) {
  if (!w || ad_mode <= 0 || dt < 0.0) return 0;
  const float *a = f + (size_t)start * MB_INST;
  int kind = (int)(a[5] + 0.5f);
  if (kind != 6) return 0;
  int merged_liquid = a[23] > 0.0f;
  struct { float cx, cy, hx, hy; int is_dark; } items[MB_ADAPTIVE_MAX];
  int ni = 0;
  if (merged_liquid) {
    int is_clear = (a[7] <= 0.1f && a[11] < 0.12f);
    int is_adaptive = a[14] < -0.5f;
    if (is_adaptive && !is_clear) {
      float lum = 0.2126f * a[8] + 0.7152f * a[9] + 0.0722f * a[10];
      items[ni].cx = (gu.gb[0] + gu.gb[2]) * 0.5f;
      items[ni].cy = (gu.gb[1] + gu.gb[3]) * 0.5f;
      items[ni].hx = fmaxf((gu.gb[2] - gu.gb[0]) * 0.5f, 1.0f);
      items[ni].hy = fmaxf((gu.gb[3] - gu.gb[1]) * 0.5f, 1.0f);
      items[ni].is_dark = (a[11] >= 0.05f && lum < 0.35f) ? 1 : 0;
      ni++;
    }
  } else {
    float tid = a[20];
    for (int32_t i = start; i < count && ni < MB_ADAPTIVE_MAX; i++) {
      const float *b = f + (size_t)i * MB_INST;
      if (b[20] != tid) continue;
      if ((int)(b[5] + 0.5f) != 6 || b[23] > 0.0f) continue;
      int is_clear = (b[7] <= 0.1f && b[11] < 0.12f);
      int is_adaptive = b[14] < -0.5f;
      if (!is_adaptive || is_clear) continue;
      float lum = 0.2126f * b[8] + 0.7152f * b[9] + 0.0722f * b[10];
      items[ni].cx = b[0] + b[2] * 0.5f;
      items[ni].cy = b[1] + b[3] * 0.5f;
      items[ni].hx = fmaxf(b[2] * 0.5f, 1.0f);
      items[ni].hy = fmaxf(b[3] * 0.5f, 1.0f);
      items[ni].is_dark = (b[11] >= 0.05f && lum < 0.35f) ? 1 : 0;
      ni++;
    }
  }
  int n_upd = 0;
  for (int k = 0; k < ni; k++) {
    int sid = -1, is_new = 0;
    for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
      MBAdSlot *s = &w->ad_slots[i];
      if (s->active && s->seen_serial == serial && s->is_dark == items[k].is_dark &&
          hypotf(items[k].cx - s->cx, items[k].cy - s->cy) <= 2.0f) {
        sid = i;
        break;
      }
    }
    if (sid < 0) {
      float best_d = (float)MB_AD_MATCH_DIST + 1e-3f;
      for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
        MBAdSlot *s = &w->ad_slots[i];
        if (!s->active || s->seen_serial == serial || s->is_dark != items[k].is_dark) continue;
        float d = hypotf(items[k].cx - s->cx, items[k].cy - s->cy);
        if (d <= best_d) { best_d = d; sid = i; }
      }
      if (sid < 0) {
        for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
          if (!w->ad_slots[i].active) { sid = i; break; }
        }
        if (sid < 0) {
          uint64_t oldest = UINT64_MAX;
          for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
            if (w->ad_slots[i].seen_serial != serial && w->ad_slots[i].seen_serial < oldest) {
              oldest = w->ad_slots[i].seen_serial;
              sid = i;
            }
          }
          if (sid < 0) sid = 0;
        }
        is_new = 1;
        memset(&w->ad_slots[sid], 0, sizeof w->ad_slots[sid]);
        w->ad_slots[sid].active = 1;
        w->ad_slots[sid].is_dark = items[k].is_dark;
      }
      w->ad_slots[sid].cx = items[k].cx;
      w->ad_slots[sid].cy = items[k].cy;
      w->ad_slots[sid].hx = items[k].hx;
      w->ad_slots[sid].hy = items[k].hy;
      w->ad_slots[sid].seen_serial = serial;
    }
    MBAdSlot *s = &w->ad_slots[sid];
    if (s->updated_serial == serial) continue;
    int need = is_new || backdrop_changed || s->settle_left > 0.0;
    if (need) {
      if (is_new) {
        s->settle_left = 0.0;
      } else if (backdrop_changed) {
        s->settle_left = MB_AD_SETTLE_SEC;
      } else {
        s->settle_left -= dt;
        if (s->settle_left <= 0.0) s->settle_left = 0.0;
      }
      s->updated_serial = serial;
      out[n_upd++] = {sid, is_new, s->is_dark, s->cx, s->cy, s->hx, s->hy};
    }
  }
  return n_upd;
}

static void ad_run_updates(RenderWin *w, const WinAdPend *pend, int n_upd, double dt) {
  if (!w || n_upd <= 0 || !gsrv || !ad_ps || !ad_cb) return;
  if (!ensure_ad_tex(w)) return;
  int cur = w->ad_cur, nxt = 1 - cur;
  ID3D11ShaderResourceView *none6[6] = {NULL, NULL, NULL, NULL, NULL, NULL};
  ctx->PSSetShaderResources(0, 6, none6);
  ctx->CopyResource(w->ad_tex[nxt].t, w->ad_tex[cur].t);
  ctx->OMSetRenderTargets(1, &w->ad_tex[nxt].rt, NULL);
  D3D11_VIEWPORT vp = {0, 0, (float)MB_ADAPTIVE_MAX, 1.0f, 0, 1};
  ctx->RSSetViewports(1, &vp);
  ctx->RSSetState(raster_cut);
  ctx->VSSetShader(pvs, NULL, 0);
  ctx->PSSetShader(ad_ps, NULL, 0);
  ctx->IASetInputLayout(NULL);
  ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
  ctx->PSSetConstantBuffers(0, 1, &ad_cb);
  ID3D11ShaderResourceView *srvs[2] = {gsrv, w->ad_tex[cur].srv};
  ctx->PSSetShaderResources(0, 2, srvs);
  ctx->PSSetSamplers(0, 1, &sampler);
  for (int i = 0; i < n_upd; i++) {
    D3D11_RECT sc = {pend[i].sid, 0, pend[i].sid + 1, 1};
    ctx->RSSetScissorRects(1, &sc);
    struct { float map[4]; float uvc[4]; float box[4]; float param[4]; } u;
    memcpy(u.map, gu.map, sizeof u.map);
    memcpy(u.uvc, gu.uvc, sizeof u.uvc);
    u.box[0] = pend[i].cx; u.box[1] = pend[i].cy; u.box[2] = pend[i].hx; u.box[3] = pend[i].hy;
    u.param[0] = (float)pend[i].is_dark;
    u.param[1] = (float)pend[i].is_new;
    u.param[2] = (float)dt;
    u.param[3] = (float)pend[i].sid;
    ctx->UpdateSubresource(ad_cb, 0, NULL, &u, 0, 0);
    ctx->Draw(3, 0);
  }
  ctx->PSSetShaderResources(0, 2, none6);
  w->ad_cur = nxt;
}

static double ad_next_dt(RenderWin *w) {
  LARGE_INTEGER freq, now;
  QueryPerformanceFrequency(&freq);
  QueryPerformanceCounter(&now);
  double t = freq.QuadPart ? (double)now.QuadPart / (double)freq.QuadPart : 0.0;
  double dt = (w && w->ad_last_time > 0.0) ? (t - w->ad_last_time) : (1.0 / 60.0);
  if (w) w->ad_last_time = t;
  if (dt < 0.0) dt = 0.0;
  if (dt > 0.1) dt = 0.1;
  return dt;
}

static void ad_finalize_frame(RenderWin *w, int whole_frame, uint64_t serial) {
  if (!w) return;
  int settling = 0;
  for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
    MBAdSlot *s = &w->ad_slots[i];
    if (!s->active) continue;
    if (whole_frame && s->seen_serial != serial) {
      s->active = 0;
      s->settle_left = 0.0;
      continue;
    }
    if (s->settle_left > 0.0) settling = 1;
  }
  w->ad_settling = settling;
}

struct Grab {
  int px0, py0, w, h, k, contained, progressive;
  int vis_x, vis_y, vis_w, vis_h;
  float sg, sp;
  float fade[4], fadex[4];
  GU g;
  MBContained edge;
};

#define MB_GLASS_SLOTS 32
struct GlassSlot {
  level bt;
  float *under;
  size_t under_cap, under_n;
  int32_t whole, picked;
  Grab grab;
  double key[7];
  int valid;
  unsigned used;
};
static GlassSlot gslots[MB_GLASS_SLOTS];
static unsigned gslots_clock;
static float *under_now;
static size_t under_now_cap, under_now_n;
static int32_t under_whole, under_picked;

static void slots_invalidate(void) {
  for (int i = 0; i < MB_GLASS_SLOTS; i++) gslots[i].valid = 0;
}

static void level_release(level *l) {
  if (l->srv) l->srv->Release();
  if (l->rt) l->rt->Release();
  if (l->t) l->t->Release();
  *l = level{};
}

static void glass_free(void) {
  if (!ctx) return;
  ID3D11ShaderResourceView *none[6] = {NULL, NULL, NULL, NULL, NULL, NULL};
  ctx->PSSetShaderResources(0, 6, none);
  gsrv = NULL;
  for (int j = 0; j < 5; j++) level_release(&lv[j]);
  for (int i = 0; i < MB_GLASS_SLOTS; i++) {
    level_release(&gslots[i].bt);
    free(gslots[i].under);
    gslots[i] = GlassSlot{};
  }
  for (int k = 0; k < MB_WINS; k++) {
    for (int i = 0; i < 2; i++) level_release(&render_wins[k].ad_tex[i]);
    ad_forget(&render_wins[k]);
  }
  lv_w = lv_h = 0;
}

// Glass's levels (as big as the largest capture yet) let go of once this many frames in a row drew no glass (a sheet
// closed, the composer gone): held on, they are tens of MB at a window's size.
#define MB_GLASS_IDLE 180
static int glass_idle_frames;
static int glass_drawn;  // a frame drawing now reached glass (encode)

static void glass_idle_tick(void) {
  if (glass_drawn) glass_idle_frames = 0;
  else if (glass_idle_frames < MB_GLASS_IDLE && ++glass_idle_frames == MB_GLASS_IDLE && lv_w > 0) glass_free();
  glass_drawn = 0;
}

// What drawing holds beyond the frames given back (a window minimized or hidden: win_app.c): glass's levels, made
// again as a frame with glass is drawn.
void mb_render_trim(void) {
  glass_free();
  glass_idle_frames = 0;
}

static void post_pass(level *src, int sw, int sh, level *dst, int w, int h, int mode, float sg, float dx, float dy) {
  ID3D11ShaderResourceView *none[3] = {NULL, NULL, NULL};
  ctx->PSSetShaderResources(0, 3, none);
  ctx->OMSetRenderTargets(1, &dst->rt, NULL);
  D3D11_VIEWPORT vp = {0, 0, (float)w, (float)h, 0, 1};
  ctx->RSSetViewports(1, &vp);
  struct { float a[4], b[4]; MBContained edge; } u = {
    {1.0f / src->w, 1.0f / src->h, (float)mode, sg}, {(sw - 0.5f) / src->w, (sh - 0.5f) / src->h, dx, dy}, post_edge};
  ctx->UpdateSubresource(pbuf, 0, NULL, &u, 0, 0);
  ctx->PSSetConstantBuffers(0, 1, &pbuf);
  ctx->PSSetShaderResources(0, 1, &src->srv);
  ctx->Draw(3, 0);
}

// Partial redraw: a window's frame is drawn into a canvas of its own, kept across frames, and
// copied into the swap chain's buffer (a flip model's holds a frame before the last); where the app says only some
// parts differ from the frame before (@hostapi.render_dirty), only those parts of the canvas are drawn again, each cut
// to it (the scissor, `cut`, while `cut_on`), the frame's ground over it first (the instance after the frame's,
// submit's), then every instance. Without a window the offscreen target is the canvas.
// (the canvas, its size and whether it holds the last frame given are the window's: RenderWin above) what the offscreen
// target holds, the frame drawn last
static int off_ok;
// (the parts of the next frame that differ, points: x, y, w, h, all of it, `dirty_whole`, and whether any was said, the
// window's) a picture the frame being drawn has none of yet
static int encode_missing;
static int cut_on;
static D3D11_RECT cut;

static float g_light_angle = 0.0f;

extern "C" void mb_host_glass_light_angle(double rad) {
  g_light_angle = (float)rad;
}

extern "C" void mb_host_render_dirty(double x, double y, double w, double h) {
  dirty_told = 1;
  if (w < 0 || h < 0) {
    dirty_whole = 1;
  } else if (w > 0 && h > 0) {
    // (more than it keeps: the last one grown round it)
    if (dirty_n == MB_PARTS) {
      double *d = dirty[MB_PARTS - 1];
      double x1 = fmax(d[0] + d[2], x + w), y1 = fmax(d[1] + d[3], y + h);
      d[0] = fmin(d[0], x);
      d[1] = fmin(d[1], y);
      d[2] = x1 - d[0];
      d[3] = y1 - d[1];
    } else {
      double *d = dirty[dirty_n++];
      d[0] = x; d[1] = y; d[2] = w; d[3] = h;
    }
  }
}

// The parts of a target tw × th pixels the next frame draws, from what was said of them (taken: a frame nothing was
// said for is drawn whole), into `r`: how many (0 none), -1 all of it. `kept`: the target holds the frame before.
static int take_parts(int tw, int th, int kept, D3D11_RECT r[MB_PARTS]) {
  int told = dirty_told, whole = dirty_whole, n = dirty_n;
  dirty_told = dirty_whole = dirty_n = 0;
  if (!told || whole || !kept || pictures_missing) return -1;
  int k = 0;
  for (int i = 0; i < n; i++) {
    // (whole pixels round it, and one more)
    int x0 = (int)floor(dirty[i][0] * vscale) - 1, y0 = (int)floor(dirty[i][1] * vscale) - 1;
    int x1 = (int)ceil((dirty[i][0] + dirty[i][2]) * vscale) + 1, y1 = (int)ceil((dirty[i][1] + dirty[i][3]) * vscale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > tw) x1 = tw;
    if (y1 > th) y1 = th;
    if (x1 > x0 && y1 > y0) r[k++] = {x0, y0, x1, y1};
  }
  return k;
}

// The canvas a window's frames are drawn into, tw × th pixels: made again at another size, what it held lost.
static void ensure_canvas(int tw, int th) {
  if (canvas && canvas_w == tw && canvas_h == th) return;
  if (canvas_rtv) canvas_rtv->Release();
  if (canvas) canvas->Release();
  canvas = NULL;
  canvas_rtv = NULL;
  canvas_ok = 0;
  canvas_w = tw;
  canvas_h = th;
  if (tw <= 0 || th <= 0) return;
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)tw;
  td.Height = (UINT)th;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &canvas))) {
    canvas = NULL;
    return;
  }
  if (FAILED(dev->CreateRenderTargetView(canvas, NULL, &canvas_rtv))) {
    canvas->Release();
    canvas = NULL;
    canvas_rtv = NULL;
  }
}

static int grab_of(Grab *m, const float *f, int32_t start, int32_t end, int32_t count, int pw, int ph) {
  memset(m, 0, sizeof *m);
  const float *a = f + start * MB_INST;
  // For frosted glass (kind 5), negative slot 7 is contained; for liquid glass (kind 6), negative slot 7 encodes clear-lens zoom.
  int kind = (int)(a[5] + 0.5f);
  int is_contained = (kind == 5 && a[7] < 0.0f);
  int is_progressive = (kind == 5 && a[22] < -0.5f);
  float blur_r = (kind == 6 && a[7] < 0.0f) ? 0.0f : fabsf(a[7]);
  int merged_liquid = (kind == 6 && a[23] > 0.0f);
  int unmerged_liquid = (kind == 6 && !merged_liquid);
  float margin = is_contained ? 0.0f : 3.0f * blur_r + (kind == 6 ? a[21] * (1.0f + fabsf(a[22])) + fmaxf(a[23], 0.0f) : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  int n = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
    float bx0 = b[0] > b[16] ? b[0] : b[16], by0 = b[1] > b[17] ? b[1] : b[17];
    float bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18], by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    if (kind == 6) {
      float m23 = fmaxf(unmerged_liquid ? b[23] : a[23], 0.0f);
      bx0 = b[0] - m23; by0 = b[1] - m23; bx1 = b[0] + b[2] + m23; by1 = b[1] + b[3] + m23;
      if (merged_liquid && n < 8) {
        for (int k = 0; k < 4; k++) m->g.shape[n][k] = b[k];
        if (fmaxf(fmaxf(b[36], b[37]), fmaxf(b[38], b[39])) > 0.0f) {
          for (int k = 0; k < 4; k++) m->g.rad[n][k] = b[36 + k];
        } else {
          for (int k = 0; k < 4; k++) m->g.rad[n][k] = b[4];
        }
        n++;
      }
      if (unmerged_liquid) {
        float bm = 3.0f * blur_r + b[21] * (1.0f + fabsf(b[22])) + m23 + 2.0f;
        if (bm > margin) margin = bm;
      }
    }
    if (bx0 < x0) x0 = bx0;
    if (by0 < y0) y0 = by0;
    if (bx1 > x1) x1 = bx1;
    if (by1 > y1) y1 = by1;
  }
  for (int32_t i = end; (kind == 5 || unmerged_liquid) && i < count; i++) {
    const float *b = f + i * MB_INST;
    if (b[20] != a[20]) continue;
    float bx0, by0, bx1, by1;
    if (unmerged_liquid) {
      float m23 = fmaxf(b[23], 0.0f);
      bx0 = b[0] - m23; by0 = b[1] - m23; bx1 = b[0] + b[2] + m23; by1 = b[1] + b[3] + m23;
      {
        float bm = 3.0f * blur_r + b[21] * (1.0f + fabsf(b[22])) + m23 + 2.0f;
        if (bm > margin) margin = bm;
      }
    } else {
      bx0 = b[0] > b[16] ? b[0] : b[16]; by0 = b[1] > b[17] ? b[1] : b[17];
      bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18]; by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
    }
    if (bx0 < x0) x0 = bx0;
    if (by0 < y0) y0 = by0;
    if (bx1 > x1) x1 = bx1;
    if (by1 > y1) y1 = by1;
  }
  m->g.misc[0] = (float)n;
  m->g.misc[1] = 0.0f;
  m->g.gb[0] = x0 - 2; m->g.gb[1] = y0 - 2; m->g.gb[2] = x1 + 2; m->g.gb[3] = y1 + 2;
  float sc = (float)vscale;
  int px0 = (int)floorf((x0 - margin) * sc), py0 = (int)floorf((y0 - margin) * sc);
  int px1 = (int)ceilf((x1 + margin) * sc), py1 = (int)ceilf((y1 + margin) * sc);
  if (px0 < 0) px0 = 0;
  if (py0 < 0) py0 = 0;
  if (px1 > pw) px1 = pw;
  if (py1 > ph) py1 = ph;
  if (px1 <= px0 || py1 <= py0 || x1 <= x0 || y1 <= y0) return 0;
  m->px0 = px0; m->py0 = py0; m->w = px1 - px0; m->h = py1 - py0;
  m->contained = is_contained ? mb_contained_make(&m->edge, a, px0 / sc, py0 / sc, 1.0f / sc, 1.0f / sc) : 0;
  m->progressive = is_progressive;
  if (is_progressive) {
    for (int i = 0; i < 4; i++) {
      m->fade[i] = a[52 + i];
      m->fadex[i] = a[56 + i];
    }
    int vx0 = (int)floorf(x0 * sc) - px0 - 2;
    int vy0 = (int)floorf(y0 * sc) - py0 - 2;
    int vx1 = (int)ceilf(x1 * sc) - px0 + 2;
    int vy1 = (int)ceilf(y1 * sc) - py0 + 2;
    if (vx0 < 0) vx0 = 0;
    if (vy0 < 0) vy0 = 0;
    if (vx1 > m->w) vx1 = m->w;
    if (vy1 > m->h) vy1 = m->h;
    if (vx1 <= vx0) { vx0 = 0; vx1 = m->w; }
    if (vy1 <= vy0) { vy0 = 0; vy1 = m->h; }
    m->vis_x = vx0; m->vis_y = vy0; m->vis_w = vx1 - vx0; m->vis_h = vy1 - vy0;
  }
  float sp = blur_r * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  m->sp = sp;
  if (is_progressive && k == 0 && sp > 0.5f) k = 1;
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  m->k = k;
  m->sg = sqrtf(sk * sk - pre > 0 ? sk * sk - pre : 0);
  return 1;
}

static void grab_levels(const Grab *m, int lw[4], int lh[4]) {
  lw[0] = m->w; lh[0] = m->h;
  for (int j = 1; j <= 3; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
  }
}

static void show_blur(const Grab *m, const level *L) {
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  gu = m->g;
  gu.misc[2] = cosf(g_light_angle);
  gu.misc[3] = sinf(g_light_angle);
  gsrv = L->srv;
  int sk = m->progressive ? 0 : m->k;
  float sc = (float)vscale;
  float d = (float)(1 << sk);
  gu.map[0] = sc / d / L->w; gu.map[1] = sc / d / L->h;
  gu.map[2] = -(float)m->px0 / d / L->w; gu.map[3] = -(float)m->py0 / d / L->h;
  if (m->progressive) {
    gu.uvc[0] = ((float)m->vis_x + 0.5f) / L->w; gu.uvc[1] = ((float)m->vis_y + 0.5f) / L->h;
    gu.uvc[2] = ((float)(m->vis_x + m->vis_w) - 0.5f) / L->w; gu.uvc[3] = ((float)(m->vis_y + m->vis_h) - 0.5f) / L->h;
  } else {
    gu.uvc[0] = 0.5f / L->w; gu.uvc[1] = 0.5f / L->h;
    gu.uvc[2] = (lw[sk] - 0.5f) / L->w; gu.uvc[3] = (lh[sk] - 0.5f) / L->h;
  }
}

static int reaches(const float *f, int32_t i, int32_t run, const float g[4]) {
  const float *b = f + (size_t)i * MB_INST;
  if (b[32] != 0.0f) return 1;
  int kind = (int)(b[5] + 0.5f);
  float e = kind == 2 ? fabsf(b[7]) * 3.0f + 2.0f : 1.0f;
  if (kind == 6) e = fmaxf(fmaxf(b[23], f[(size_t)run * MB_INST + 23]), 0.0f) + 2.0f;
  e += 1.0f;
  float x0 = fminf(b[0], b[0] + b[2]) - e, x1 = fmaxf(b[0], b[0] + b[2]) + e;
  float y0 = fminf(b[1], b[1] + b[3]) - e, y1 = fmaxf(b[1], b[1] + b[3]) + e;
  return x1 > g[0] && x0 < g[2] && y1 > g[1] && y0 < g[3];
}

static int under_take(const float *f, int32_t start, int32_t count, int32_t pieces, const Grab *m) {
  float sc = (float)vscale;
  float dep[4] = {(float)m->px0 / sc - 1.0f, (float)m->py0 / sc - 1.0f, (float)(m->px0 + m->w) / sc + 1.0f,
                  (float)(m->py0 + m->h) / sc + 1.0f};
  float seen_tids[32];
  int seen_n = 0;
  for (int pass = 0; pass < 4; pass++) {
    int grew = 0;
    for (int32_t i = start - 1; i >= 0; i--) {
      const float *bi = f + (size_t)i * MB_INST;
      float tid = bi[20];
      int k = (int)(bi[5] + 0.5f);
      int is_glass = tid < 0.0f;
      int is_ad = k == 7 || ((k == 10 || k == 11) && bi[23] > 0.0f);
      if (!is_glass && !is_ad) continue;
      int32_t run = i;
      if (is_glass) {
        while (run > 0 && f[(size_t)(run - 1) * MB_INST + 20] == tid) run--;
      }
      if (!reaches(f, i, run, dep)) continue;
      if (is_glass) {
        int already = 0;
        for (int s = 0; s < seen_n; s++) {
          if (seen_tids[s] == tid) { already = 1; break; }
        }
        if (already) continue;
        if (seen_n < 32) seen_tids[seen_n++] = tid;
        int32_t first_i = run;
        for (int32_t j = 0; j < run; j++) {
          if (f[(size_t)j * MB_INST + 20] == tid) { first_i = j; break; }
        }
        const float *a = f + (size_t)first_i * MB_INST;
        int gkind = (int)(a[5] + 0.5f);
        int is_contained = (gkind == 5 && a[7] < 0.0f);
        float blur_r = (gkind == 6 && a[7] < 0.0f) ? 0.0f : fabsf(a[7]);
        int merged_liquid = (gkind == 6 && a[23] > 0.0f);
        int unmerged_liquid = (gkind == 6 && !merged_liquid);
        float margin = is_contained ? 0.0f : 3.0f * blur_r + (gkind == 6 ? a[21] * (1.0f + fabsf(a[22])) + fmaxf(a[23], 0.0f) : 0.0f) + 2.0f;
        float gx0 = 1e9f, gy0 = 1e9f, gx1 = -1e9f, gy1 = -1e9f;
        for (int32_t j = first_i; j < count; j++) {
          const float *b = f + (size_t)j * MB_INST;
          if (b[20] != tid) continue;
          float bx0, by0, bx1, by1;
          if (gkind == 6) {
            float m23 = fmaxf(unmerged_liquid ? b[23] : a[23], 0.0f);
            bx0 = b[0] - m23; by0 = b[1] - m23; bx1 = b[0] + b[2] + m23; by1 = b[1] + b[3] + m23;
            if (unmerged_liquid) {
              float bm = 3.0f * blur_r + b[21] * (1.0f + fabsf(b[22])) + m23 + 2.0f;
              if (bm > margin) margin = bm;
            }
          } else {
            bx0 = b[0] > b[16] ? b[0] : b[16]; by0 = b[1] > b[17] ? b[1] : b[17];
            bx1 = b[0] + b[2] < b[18] ? b[0] + b[2] : b[18]; by1 = b[1] + b[3] < b[19] ? b[1] + b[3] : b[19];
          }
          if (bx0 < gx0) gx0 = bx0;
          if (by0 < gy0) gy0 = by0;
          if (bx1 > gx1) gx1 = bx1;
          if (by1 > gy1) gy1 = by1;
        }
        if (gx1 > gx0 && gy1 > gy0) {
          float ex0 = gx0 - margin - 2.0f, ey0 = gy0 - margin - 2.0f;
          float ex1 = gx1 + margin + 2.0f, ey1 = gy1 + margin + 2.0f;
          if (ex0 < dep[0]) { dep[0] = ex0; grew = 1; }
          if (ey0 < dep[1]) { dep[1] = ey0; grew = 1; }
          if (ex1 > dep[2]) { dep[2] = ex1; grew = 1; }
          if (ey1 > dep[3]) { dep[3] = ey1; grew = 1; }
        }
      } else {
        float rad = bi[23] + 4.0f;
        float ex0 = bi[21] - rad, ey0 = bi[22] - rad;
        float ex1 = bi[21] + rad, ey1 = bi[22] + rad;
        if (ex0 < dep[0]) { dep[0] = ex0; grew = 1; }
        if (ey0 < dep[1]) { dep[1] = ey0; grew = 1; }
        if (ex1 > dep[2]) { dep[2] = ex1; grew = 1; }
        if (ey1 > dep[3]) { dep[3] = ey1; grew = 1; }
      }
    }
    if (!grew) break;
  }
  size_t most = ((size_t)start + (size_t)(count - pieces)) * MB_INST;
  if (under_now_cap < most) {
    float *grown = (float *)realloc(under_now, most * sizeof(float));
    if (!grown) return 0;
    under_now = grown;
    under_now_cap = most;
  }
  float *o = under_now;
  int32_t picked = 0, run = 0;
  for (int32_t i = 0; i < start; i++) {
    float tid = f[(size_t)i * MB_INST + 20];
    if (i > 0 && tid != f[(size_t)(i - 1) * MB_INST + 20]) run = i;
    if (!reaches(f, i, run, dep)) continue;
    if (tid > (float)MB_STREAM_TEX) return 0;
    memcpy(o, f + (size_t)i * MB_INST, MB_INST * sizeof(float));
    o += MB_INST;
    picked++;
  }
  memcpy(o, f + (size_t)pieces * MB_INST, (size_t)(count - pieces) * MB_INST * sizeof(float));
  o += (size_t)(count - pieces) * MB_INST;
  under_now_n = (size_t)(o - under_now);
  under_whole = 0;
  under_picked = picked;
  return 1;
}

static int slot_same(const Grab *m, const double key[7]) {
  for (int i = 0; i < MB_GLASS_SLOTS; i++) {
    GlassSlot *s = &gslots[i];
    if (s->valid && s->bt.srv && s->under_n == under_now_n && s->whole == under_whole && s->picked == under_picked &&
        memcmp(&s->grab, m, sizeof *m) == 0 && memcmp(s->key, key, sizeof s->key) == 0 &&
        memcmp(s->under, under_now, under_now_n * sizeof(float)) == 0)
      return i;
  }
  return -1;
}

static int slot_fill(const Grab *m, unsigned frame_clock) {
  level *Lp = (m->progressive || (m->contained && m->k == 0)) ? &lv[4] : &lv[m->k];
  int t0 = -1, t1 = -1, t2 = -1, t3 = -1, t4 = -1, fallback = 0;
  for (int j = 0; j < MB_GLASS_SLOTS; j++) {
    if (gslots[j].used < gslots[fallback].used) fallback = j;
    if (gslots[j].used > frame_clock) continue;
    int has_bt = gslots[j].bt.t != NULL;
    int same_tex = has_bt && gslots[j].bt.w == Lp->w && gslots[j].bt.h == Lp->h && gslots[j].bt.fmt == Lp->fmt;
    if (!gslots[j].valid) {
      if (same_tex) {
        if (t0 < 0) t0 = j;
      } else if (!has_bt) {
        if (t1 < 0) t1 = j;
      } else {
        if (t3 < 0) t3 = j;
      }
    } else if (same_tex) {
      if (t2 < 0 || gslots[j].used < gslots[t2].used) t2 = j;
    }
    if (t4 < 0 || gslots[j].used < gslots[t4].used) t4 = j;
  }
  int i = t0 >= 0 ? t0 : t1 >= 0 ? t1 : t2 >= 0 ? t2 : t3 >= 0 ? t3 : t4 >= 0 ? t4 : fallback;
  gslots[i].valid = 0;
  if (gslots[i].bt.t && gslots[i].bt.w == Lp->w && gslots[i].bt.h == Lp->h && gslots[i].bt.fmt == Lp->fmt) {
    level old = gslots[i].bt;
    gslots[i].bt = *Lp;
    *Lp = old;
  } else {
    level fresh = level_tex(Lp->fmt, Lp->w, Lp->h);
    if (!fresh.t) return -1;
    level_release(&gslots[i].bt);
    gslots[i].bt = *Lp;
    *Lp = fresh;
  }
  return i;
}

static void slot_show(const Grab *m, int i) {
  gslots[i].used = ++gslots_clock;
  show_blur(m, &gslots[i].bt);
}

static void slot_keep(int i, const Grab *m, const double key[7]) {
  GlassSlot *s = &gslots[i];
  if (s->under_cap < under_now_n) {
    float *grown = (float *)realloc(s->under, under_now_n * sizeof(float));
    if (!grown) return;
    s->under = grown;
    s->under_cap = under_now_n;
  }
  memcpy(s->under, under_now, under_now_n * sizeof(float));
  s->under_n = under_now_n;
  s->whole = under_whole;
  s->picked = under_picked;
  s->grab = *m;
  memcpy(s->key, key, sizeof s->key);
  s->valid = 1;
}

static int blur_grab(ID3D11RenderTargetView *target, const Grab *m) {
  if (!ensure_levels(m->w, m->h)) return 0;
  ID3D11Resource *res = NULL;
  target->GetResource(&res);
  D3D11_BOX box = {(UINT)m->px0, (UINT)m->py0, 0, (UINT)(m->px0 + m->w), (UINT)(m->py0 + m->h), 1};
  ctx->CopySubresourceRegion(lv[0].t, 0, 0, 0, 0, res, 0, &box);
  res->Release();
  ctx->VSSetShader(pvs, NULL, 0);
  ctx->PSSetShader(pps, NULL, 0);
  ctx->IASetInputLayout(NULL);
  ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
  ctx->RSSetState(raster);
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  int k = m->k;
  if (m->progressive) {
    float prev_var = 0.0f;
    for (int j = 1; j <= k; j++) {
      post_pass(&lv[j - 1], lw[j - 1], lh[j - 1], &lv[j], lw[j], lh[j], 1, 0, 0, 0);
      float target_px = powf(fmaxf(m->sp, 1.0f), (float)j / (float)k);
      float have_var = prev_var + 0.75f * (float)(1 << (2 * j - 2));
      float need_var = fmaxf(target_px * target_px - have_var, 0.0f);
      float sg_j = sqrtf(need_var) / (float)(1 << j);
      if (sg_j > 0.3f) {
        post_pass(&lv[j], lw[j], lh[j], &lv[4], lw[j], lh[j], 2, sg_j, 1, 0);
        post_pass(&lv[4], lw[j], lh[j], &lv[j], lw[j], lh[j], 2, sg_j, 0, 1);
      }
      prev_var = fmaxf(have_var, target_px * target_px);
    }
    float sc = (float)vscale;
    memset(&post_edge, 0, sizeof post_edge);
    post_edge.map[0] = (float)m->px0 / sc; post_edge.map[1] = (float)m->py0 / sc;
    post_edge.map[2] = 1.0f / sc; post_edge.map[3] = 1.0f / sc;
    for (int i = 0; i < 4; i++) { post_edge.box[i] = m->fade[i]; post_edge.rr[i] = m->fadex[i]; }
    post_edge.clip[0] = m->sp; post_edge.clip[1] = (float)k;
    float *ms[4] = {post_edge.rc, post_edge.rs, post_edge.outer, post_edge.orc};
    for (int j = 0; j < 4; j++) {
      float dj = (float)(1 << j), tw = (float)lv[j].w, th = (float)lv[j].h;
      ms[j][0] = 1.0f / (dj * tw); ms[j][1] = 1.0f / (dj * th);
      ms[j][2] = ((float)lw[j] - 0.5f) / tw; ms[j][3] = ((float)lh[j] - 0.5f) / th;
    }
    ID3D11ShaderResourceView *none4[4] = {NULL, NULL, NULL, NULL};
    ctx->PSSetShaderResources(0, 4, none4);
    ctx->PSSetShader(prog_ps, NULL, 0);
    ctx->OMSetRenderTargets(1, &lv[4].rt, NULL);
    D3D11_VIEWPORT vp = {0, 0, (float)m->w, (float)m->h, 0, 1};
    ctx->RSSetViewports(1, &vp);
    struct { float a[4], b[4]; MBContained edge; } u = {
      {1.0f / lv[0].w, 1.0f / lv[0].h, 4.0f, 0.0f}, {(m->w - 0.5f) / lv[0].w, (m->h - 0.5f) / lv[0].h, 0.0f, 0.0f}, post_edge};
    ctx->UpdateSubresource(pbuf, 0, NULL, &u, 0, 0);
    ctx->PSSetConstantBuffers(0, 1, &pbuf);
    ID3D11ShaderResourceView *srvs[4] = {lv[0].srv, lv[1].srv, lv[2].srv, lv[3].srv};
    ctx->PSSetShaderResources(0, 4, srvs);
    ctx->RSSetState(raster_cut);
    D3D11_RECT vsc = {m->vis_x, m->vis_y, m->vis_x + m->vis_w, m->vis_y + m->vis_h};
    ctx->RSSetScissorRects(1, &vsc);
    ctx->Draw(3, 0);
    ctx->RSSetState(raster);
    ctx->PSSetShaderResources(0, 4, none4);
  } else {
    if (m->contained) {
      post_edge = m->edge;
      ctx->PSSetShader(edge_ps, NULL, 0);
      post_pass(&lv[0], m->w, m->h, &lv[4], m->w, m->h, 3, 0, 0, 0);
      ctx->PSSetShader(pps, NULL, 0);
    }
    for (int j = 1; j <= k; j++)
      post_pass(j == 1 && m->contained ? &lv[4] : &lv[j - 1], lw[j - 1], lh[j - 1], &lv[j], lw[j], lh[j], 1, 0, 0, 0);
    if (m->sg > 0.3f) {
      level *from = m->contained && k == 0 ? &lv[4] : &lv[k];
      level *tmp = m->contained && k == 0 ? &lv[0] : &lv[4];
      post_pass(from, lw[k], lh[k], tmp, lw[k], lh[k], 2, m->sg, 1, 0);
      post_pass(tmp, lw[k], lh[k], from, lw[k], lh[k], 2, m->sg, 0, 1);
    }
    ID3D11ShaderResourceView *none[3] = {NULL, NULL, NULL};
    ctx->PSSetShaderResources(0, 3, none);
  }
  return 1;
}

// what the run [start, end) of glass sees, from target (pw × ph) into gsrv and gu, frosted glass of the same capture
// further on (glass.mbt shares_capture) too; 0 when none of it shows. Sets *switched if GPU render target changed.
static int capture(ID3D11RenderTargetView *target, int pw, int ph, const float *f, int32_t start, int32_t end,
                   int32_t count, int32_t pieces, const float *bg, unsigned frame_clock, int *switched) {
  *switched = 0;
  Grab m;
  if (!grab_of(&m, f, start, end, count, pw, ph)) return 0;
  // (a capture outside the part drawn: neither copied nor drawn. One that meets it is in it whole: @damage)
  if (cut_on && (m.px0 + m.w <= cut.left || cut.right <= m.px0 || m.py0 + m.h <= cut.top || cut.bottom <= m.py0)) return 0;
  double key[7] = {(double)pw, (double)ph, vscale, (double)bg[0], (double)bg[1], (double)bg[2], 1.0};
  int known = under_take(f, start, count, pieces, &m);
  int slot = known ? slot_same(&m, key) : -1;
  int reblurred = 0;
  if (slot >= 0) {
    slot_show(&m, slot);
  } else {
    reblurred = 1;
    *switched = 1;
    if (!blur_grab(target, &m)) return 0;
    slot = slot_fill(&m, frame_clock);
    if (slot >= 0) {
      if (known && !encode_missing) slot_keep(slot, &m, key);
      slot_show(&m, slot);
    } else {
      level *L = (m.progressive || (m.contained && m.k == 0)) ? &lv[4] : &lv[m.k];
      show_blur(&m, L);
    }
  }
  WinAdPend ad_pend[MB_ADAPTIVE_MAX];
  int ad_n_upd = ad_collect_and_match(rw, f, start, count, reblurred, ad_cur_dt,
                                      rw ? rw->ad_frame_serial : 0, ad_pend);
  if (ad_n_upd > 0) {
    *switched = 1;
    ad_run_updates(rw, ad_pend, ad_n_upd, ad_cur_dt);
  }
  ad_fill_gu(rw);
  return 1;
}

// The pieces of the frame's shapes (src/ui/shape.mbt: the instances of kind 12 after every one drawn), for the pixel
// shader to read (segs, t3): as they are, 15 fours an instance.
static ID3D11Buffer *segs_buf;
static ID3D11ShaderResourceView *segs_srv;
static size_t segs_cap;

static void segs_upload(const float *f, int32_t count) {
  if (!dev || !ctx || count <= 0) return;
  int32_t d = count;
  while (d > 0 && (int)(f[(size_t)(d - 1) * MB_INST + 5] + 0.5f) == 12) d--;
  if (d == count) return;
  size_t n_seg = (size_t)(count - d);
  if (n_seg > (size_t)UINT_MAX / ((size_t)MB_INST * sizeof(float))) return;
  size_t need = n_seg * MB_INST * sizeof(float);
  if (!segs_buf || !segs_srv || segs_cap < need) {
    if (segs_srv) {
      segs_srv->Release();
      segs_srv = NULL;
    }
    if (segs_buf) {
      segs_buf->Release();
      segs_buf = NULL;
    }
    segs_cap = 0;
    size_t cap = need <= ((size_t)UINT_MAX / 2) ? need * 2 : need;
    D3D11_BUFFER_DESC bd = {(UINT)cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_SHADER_RESOURCE, D3D11_CPU_ACCESS_WRITE, 0, 0};
    if (FAILED(dev->CreateBuffer(&bd, NULL, &segs_buf)) || !segs_buf) {
      segs_buf = NULL;
      if (cap != need) {
        cap = need;
        bd.ByteWidth = (UINT)cap;
        if (FAILED(dev->CreateBuffer(&bd, NULL, &segs_buf)) || !segs_buf) {
          segs_buf = NULL;
          return;
        }
      } else {
        return;
      }
    }
    D3D11_SHADER_RESOURCE_VIEW_DESC sd = {};
    sd.Format = DXGI_FORMAT_R32G32B32A32_FLOAT;
    sd.ViewDimension = D3D11_SRV_DIMENSION_BUFFER;
    sd.Buffer.FirstElement = 0;
    sd.Buffer.NumElements = (UINT)(cap / 16);
    if (FAILED(dev->CreateShaderResourceView(segs_buf, &sd, &segs_srv)) || !segs_srv) {
      segs_srv = NULL;
      segs_buf->Release();
      segs_buf = NULL;
      return;
    }
    segs_cap = cap;
  }
  if (!segs_buf || !segs_srv) return;
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(segs_buf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return;
  memcpy(m.pData, f + (size_t)d * MB_INST, need);
  ctx->Unmap(segs_buf, 0);
}

// the main pipeline's state, at the start and after the passes
static void main_state(ID3D11RenderTargetView *target, int pw, int ph) {
  D3D11_VIEWPORT vp = {0, 0, (float)pw, (float)ph, 0, 1};
  UINT stride = MB_INST * sizeof(float), off = 0;
  ctx->OMSetRenderTargets(1, &target, NULL);
  ctx->RSSetViewports(1, &vp);
  ctx->RSSetState(cut_on ? raster_cut : raster);
  if (cut_on) ctx->RSSetScissorRects(1, &cut);
  ctx->IASetInputLayout(layout);
  ctx->IASetPrimitiveTopology(D3D11_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
  ctx->IASetVertexBuffers(0, 1, &vbuf, &stride, &off);
  ctx->UpdateSubresource(gbuf, 0, NULL, &gu, 0, 0);
  ID3D11Buffer *cbs[2] = {ubuf, gbuf};
  ctx->VSSetShader(vs, NULL, 0);
  ctx->VSSetConstantBuffers(0, 2, cbs);
  ctx->PSSetShader(ps, NULL, 0);
  ctx->PSSetConstantBuffers(0, 2, cbs);
  ctx->PSSetShaderResources(0, 1, &atlas_srv);
  ctx->PSSetShaderResources(2, 1, gsrv ? &gsrv : &atlas_srv);
  ctx->PSSetShaderResources(3, 1, &segs_srv);
  ID3D11ShaderResourceView *ad_srv = (rw && rw->ad_tex[rw->ad_cur].srv) ? rw->ad_tex[rw->ad_cur].srv : atlas_srv;
  ctx->PSSetShaderResources(5, 1, &ad_srv);
  ctx->PSSetSamplers(0, 1, &sampler);
  ctx->OMSetBlendState(blend, NULL, 0xffffffff);
}

// Instances start to end drawn by `run`, each that pays for it in strips (bands.h), the rest as they come.
static void draw_banded(const float *f, int32_t start, int32_t end, int32_t count, int pw, int ph,
                        ID3D11PixelShader *run) {
  MBStrip to = cut_on ? mb_strip((int)cut.left, (int)cut.top, (int)cut.right, (int)cut.bottom) : mb_strip(0, 0, pw, ph);
  MBStrip st[MB_STRIPS];
  int32_t s = start;
  for (int32_t i = start; i < end; i++) {
    if (!mb_band_kind(f, i)) continue;
    int n = mb_bands(f, i, count, (float)vscale, to, st);
    if (n < 0) continue;
    if (i > s) ctx->DrawInstanced(6, (UINT)(i - s), 0, (UINT)s);
    ctx->RSSetState(raster_cut);
    for (int k = 0; k < n; k++) {
      if (k == 0 || st[k].flat != st[k - 1].flat) ctx->PSSetShader(st[k].flat ? ps_flat : run, NULL, 0);
      D3D11_RECT r = {st[k].x0, st[k].y0, st[k].x1, st[k].y1};
      ctx->RSSetScissorRects(1, &r);
      ctx->DrawInstanced(6, 1, 0, (UINT)i);
    }
    if (n > 0 && st[n - 1].flat) ctx->PSSetShader(run, NULL, 0);
    if (cut_on) ctx->RSSetScissorRects(1, &cut);
    else ctx->RSSetState(raster);
    s = i + 1;
  }
  if (end > s) ctx->DrawInstanced(6, (UINT)(end - s), 0, (UINT)s);
}

// `part`: only that part of the target drawn again, over what it holds (the frame's ground first: the instance after
// the frame's in the vertex buffer, submit's); NULL, all of it, cleared to the ground.
static void encode(ID3D11RenderTargetView *target, int pw, int ph, int32_t count, const float *bg,
                   const float *f, const D3D11_RECT *part = NULL) {
  atlas_flush();
  float clear[4] = {bg[0], bg[1], bg[2], 1};
  encode_missing = 0;
  ctx->OMSetRenderTargets(1, &target, NULL);
  cut_on = part != NULL;
  if (part) cut = *part;
  else ctx->ClearRenderTargetView(target, clear);
  if (count <= 0 && !part) return;
  struct { float vp[2]; float scale; float pad; } u = {{(float)vw, (float)vh}, (float)vscale, 0};
  ctx->UpdateSubresource(ubuf, 0, NULL, &u, 0, 0);
  memset(&gu, 0, sizeof gu);
  ad_fill_gu(rw);
  gsrv = NULL;
  segs_upload(f, count);
  main_state(target, pw, ph);
  if (part) {
    ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
    ctx->DrawInstanced(6, 1, 0, (UINT)count);
    ctx->OMSetBlendState(blend, NULL, 0xffffffff);
  }
  // one draw per run of instances showing the same image (slot 20; 0: none, the atlas stands in) of one kind (its
  // pixel shader: kind_ps), or sharing one capture of glass (negative)
  int32_t start = 0;
  int bound = 0, shows = 0, levels_sized = 0;
  unsigned frame_clock = gslots_clock;
  int32_t pieces = count;
  while (pieces > 0 && (int)(f[(size_t)(pieces - 1) * MB_INST + 5] + 0.5f) == 12) pieces--;
  while (start < count) {
    int tid = (int)f[start * MB_INST + 20];
    int32_t end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid) end++;
    if (tid < 0) {
      glass_drawn = 1;
      if (!levels_sized) {
        levels_sized = 1;
        int max_w = 0, max_h = 0, scan_bound = 0;
        for (int32_t s0 = start; s0 < count;) {
          int stid = (int)f[s0 * MB_INST + 20];
          int32_t e0 = s0 + 1;
          if (stid < 0) {
            while (e0 < count && (int)f[e0 * MB_INST + 20] == stid) e0++;
            if (stid != scan_bound) {
              scan_bound = stid;
              Grab gm;
              if (grab_of(&gm, f, s0, e0, count, pw, ph) &&
                  (!cut_on || !(gm.px0 + gm.w <= cut.left || cut.right <= gm.px0 || gm.py0 + gm.h <= cut.top || cut.bottom <= gm.py0))) {
                if (gm.w > max_w) max_w = gm.w;
                if (gm.h > max_h) max_h = gm.h;
              }
            }
          }
          s0 = e0;
        }
        if (max_w > lv_w || max_h > lv_h) ensure_levels(max_w, max_h);
      }
      if (tid != bound) {
        int switched = 0;
        shows = capture(target, pw, ph, f, start, end, count, pieces, bg, frame_clock, &switched);
        bound = tid;
        if (switched) {
          main_state(target, pw, ph);
        } else if (shows) {
          ctx->UpdateSubresource(gbuf, 0, NULL, &gu, 0, 0);
          ID3D11ShaderResourceView *bsrv = gsrv ? gsrv : atlas_srv;
          ctx->PSSetShaderResources(2, 1, &bsrv);
        }
      }
      // merged liquid (merge > 0): the group as one shape, drawn once; unmerged liquid and frosted: each instance
      int gkind_raw = (int)(f[start * MB_INST + 5] + 0.5f);
      int merged_liquid = gkind_raw == 6 && f[start * MB_INST + 23] > 0.0f;
      int gkind = gkind_raw == 5 ? 5 : (gkind_raw == 6 ? (merged_liquid ? 6 : MB_KIND_LIQUID_SINGLE) : -1);
      ctx->PSSetShader(kind_ps(gkind), NULL, 0);
      if (shows) ctx->DrawInstanced(6, merged_liquid ? 1 : (UINT)(end - start), 0, (UINT)start);
      start = end;
      continue;
    }
    // holes for native views (kind 9) apart, written without blending: transparent there
    int kind = (int)(f[start * MB_INST + 5] + 0.5f), hole = kind == 9, own = has_own_ps(kind);
    // (kinds without their own pixel shader one run, as before)
    end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid) {
      int k = (int)(f[end * MB_INST + 5] + 0.5f);
      if ((k == 9) != hole || (own ? k != kind : has_own_ps(k))) break;
      end++;
    }
    // (a hole's image is its view's, src/hostapi/host.mbt view_tex_base + its id: the view is under the canvas here)
    ID3D11ShaderResourceView *t = hole ? atlas_srv
                                  : tid > MB_STREAM_TEX ? (ID3D11ShaderResourceView *)mb_stream_srv(tid - MB_STREAM_TEX)
                                  : tid ? (ID3D11ShaderResourceView *)mb_image_srv(tid) : atlas_srv;
    // (a stream with no frame of its own yet: nothing, not the atlas)
    if (!hole && tid > MB_STREAM_TEX && !t) {
      start = end;
      continue;
    }
    if (!hole && tid > 0 && tid <= MB_STREAM_TEX && !t) encode_missing = 1;
    ctx->PSSetShaderResources(1, 1, t ? &t : &atlas_srv);
    ID3D11PixelShader *run = own ? kind_ps(kind) : ps;
    ctx->PSSetShader(run, NULL, 0);
    if (hole) ctx->OMSetBlendState(NULL, NULL, 0xffffffff);
    if (hole) ctx->DrawInstanced(6, (UINT)(end - start), 0, (UINT)start);
    else draw_banded(f, start, end, count, pw, ph, run);
    if (hole) ctx->OMSetBlendState(blend, NULL, 0xffffffff);
    start = end;
  }
  if (cut_on) ctx->RSSetState(raster);
  cut_on = 0;
}

#ifndef MB_WIN_CREATE_BUFFER
#define MB_WIN_CREATE_BUFFER(d, desc, init, out) ((d)->CreateBuffer((desc), (init), (out)))
#endif

// Non-blocking D3D11 GPU timestamp disjoint query ring (4 slots): polls completed oldest slots with
// D3D11_ASYNC_GETDATA_DONOTFLUSH (zero pipeline stall) and gracefully degrades to -1.0 if CreateQuery fails.
#define MB_GPU_Q_SLOTS 4
struct GpuQuerySlot {
  ID3D11Query *disjoint;
  ID3D11Query *ts_begin;
  ID3D11Query *ts_end;
  int in_flight;
};
static GpuQuerySlot gpu_q[MB_GPU_Q_SLOTS];
static int gpu_q_head = 0;
static int gpu_q_tail = 0;
static int gpu_q_init_done = 0;
static int gpu_q_ok = 0;
static double last_gpu_ms = -1.0;
static int32_t present_dropped = 0;

static void gpu_q_free(void) {
  for (int i = 0; i < MB_GPU_Q_SLOTS; i++) {
    if (gpu_q[i].disjoint) {
      gpu_q[i].disjoint->Release();
      gpu_q[i].disjoint = NULL;
    }
    if (gpu_q[i].ts_begin) {
      gpu_q[i].ts_begin->Release();
      gpu_q[i].ts_begin = NULL;
    }
    if (gpu_q[i].ts_end) {
      gpu_q[i].ts_end->Release();
      gpu_q[i].ts_end = NULL;
    }
    gpu_q[i].in_flight = 0;
  }
  gpu_q_head = 0;
  gpu_q_tail = 0;
  gpu_q_init_done = 0;
  gpu_q_ok = 0;
}

static int gpu_q_ensure(void) {
  if (gpu_q_init_done) return gpu_q_ok;
  gpu_q_init_done = 1;
  gpu_q_ok = 0;
  if (!dev || !ctx) return 0;
  D3D11_QUERY_DESC dq = {};
  dq.Query = D3D11_QUERY_TIMESTAMP_DISJOINT;
  D3D11_QUERY_DESC tq = {};
  tq.Query = D3D11_QUERY_TIMESTAMP;
  for (int i = 0; i < MB_GPU_Q_SLOTS; i++) {
    if (FAILED(dev->CreateQuery(&dq, &gpu_q[i].disjoint)) || !gpu_q[i].disjoint ||
        FAILED(dev->CreateQuery(&tq, &gpu_q[i].ts_begin)) || !gpu_q[i].ts_begin ||
        FAILED(dev->CreateQuery(&tq, &gpu_q[i].ts_end)) || !gpu_q[i].ts_end) {
      gpu_q_free();
      gpu_q_init_done = 1;
      gpu_q_ok = 0;
      return 0;
    }
    gpu_q[i].in_flight = 0;
  }
  gpu_q_head = 0;
  gpu_q_tail = 0;
  gpu_q_ok = 1;
  return 1;
}

static void gpu_q_poll(void) {
  if (!ctx || !gpu_q_ok) return;
  for (int n = 0; n < MB_GPU_Q_SLOTS; n++) {
    GpuQuerySlot *s = &gpu_q[gpu_q_head];
    if (!s->in_flight) break;
    D3D11_QUERY_DATA_TIMESTAMP_DISJOINT dj = {};
    UINT64 t0 = 0, t1 = 0;
    HRESULT hr_d = ctx->GetData(s->disjoint, &dj, sizeof dj, D3D11_ASYNC_GETDATA_DONOTFLUSH);
    if (hr_d == S_FALSE) break;
    if (FAILED(hr_d)) {
      s->in_flight = 0;
      gpu_q_head = (gpu_q_head + 1) % MB_GPU_Q_SLOTS;
      continue;
    }
    HRESULT hr_0 = ctx->GetData(s->ts_begin, &t0, sizeof t0, D3D11_ASYNC_GETDATA_DONOTFLUSH);
    if (hr_0 == S_FALSE) break;
    HRESULT hr_1 = ctx->GetData(s->ts_end, &t1, sizeof t1, D3D11_ASYNC_GETDATA_DONOTFLUSH);
    if (hr_1 == S_FALSE) break;
    if (hr_0 == S_OK && hr_1 == S_OK && !dj.Disjoint && dj.Frequency > 0 && t1 >= t0) {
      last_gpu_ms = (double)(t1 - t0) * 1000.0 / (double)dj.Frequency;
    }
    s->in_flight = 0;
    gpu_q_head = (gpu_q_head + 1) % MB_GPU_Q_SLOTS;
  }
}

static int gpu_q_begin(void) {
  if (!gpu_q_ensure()) return -1;
  gpu_q_poll();
  int idx = gpu_q_tail;
  if (gpu_q[idx].in_flight) return -1;
  ctx->Begin(gpu_q[idx].disjoint);
  ctx->End(gpu_q[idx].ts_begin);
  return idx;
}

static void gpu_q_end(int idx) {
  if (idx < 0 || idx >= MB_GPU_Q_SLOTS || !ctx || !gpu_q_ok) return;
  ctx->End(gpu_q[idx].ts_end);
  ctx->End(gpu_q[idx].disjoint);
  gpu_q[idx].in_flight = 1;
  gpu_q_tail = (idx + 1) % MB_GPU_Q_SLOTS;
}

#define MB_WIN_DROPPED_CLAMP 10
// Pure logic for counting dropped frames from consecutive DXGI_FRAME_STATISTICS samples:
// counts drops only when consecutive presents are within 2.5 * period_ms (continuous animation/scroll, not idle pauses).
static int32_t win_count_dropped_step(UINT prev_present, UINT prev_sync, int64_t prev_qpc, int has_prev,
                                      UINT cur_present, UINT cur_sync, int64_t cur_qpc,
                                      int64_t qpc_freq, double period_ms) {
  if (!has_prev || qpc_freq <= 0 || period_ms <= 0.0) return 0;
  if (cur_qpc <= prev_qpc) return 0;
  double dt_ms = (double)(cur_qpc - prev_qpc) * 1000.0 / (double)qpc_freq;
  if (dt_ms >= 2.5 * period_ms) return 0;
  if (cur_present <= prev_present || cur_sync <= prev_sync) return 0;
  UINT d_present = cur_present - prev_present;
  UINT d_sync = cur_sync - prev_sync;
  if (d_sync <= d_present) return 0;
  UINT dropped = d_sync - d_present;
  if (dropped > MB_WIN_DROPPED_CLAMP) dropped = MB_WIN_DROPPED_CLAMP;
  return (int32_t)dropped;
}

static double win_display_period_ms(int64_t qpc_freq) {
  DWM_TIMING_INFO ti = {};
  ti.cbSize = sizeof ti;
  if (qpc_freq > 0 && SUCCEEDED(DwmGetCompositionTimingInfo(NULL, &ti)) && ti.qpcRefreshPeriod) {
    return (double)ti.qpcRefreshPeriod * 1000.0 / (double)qpc_freq * (double)mb_frame_beats();
  }
  return 1000.0 / 60.0;
}

// Ensures `vbuf` can hold at least `room` bytes: doubles when possible, falls back to exact `room`, and always clears
// `vbuf`/`vbuf_cap` on failure so callers never dereference a stale or NULL buffer.
static int ensure_vbuf(size_t room) {
  if (!dev || room == 0 || room > (size_t)UINT_MAX) return 0;
  if (vbuf && vbuf_cap >= room) return 1;
  if (vbuf) {
    vbuf->Release();
    vbuf = NULL;
  }
  vbuf_cap = 0;
  size_t cap = room <= ((size_t)UINT_MAX / 2) ? room * 2 : room;
  D3D11_BUFFER_DESC bd = {(UINT)cap, D3D11_USAGE_DYNAMIC, D3D11_BIND_VERTEX_BUFFER,
                          D3D11_CPU_ACCESS_WRITE, 0, 0};
  if (FAILED(MB_WIN_CREATE_BUFFER(dev, &bd, NULL, &vbuf)) || !vbuf) {
    vbuf = NULL;
    if (cap != room) {
      cap = room;
      bd.ByteWidth = (UINT)cap;
      if (FAILED(MB_WIN_CREATE_BUFFER(dev, &bd, NULL, &vbuf)) || !vbuf) {
        vbuf = NULL;
        return 0;
      }
    } else {
      return 0;
    }
  }
  vbuf_cap = cap;
  return 1;
}

// The frame's instances into the vertex buffer and kept (a snapshot draws them again), as floats with its groups'
// headers drawn out (groups.h: one pass, into what is kept), then drawn into the target: a window's (`chain`) into the
// canvas, only the parts that differ where it holds the frame before; how many in `parts_out` (-1 all of it, 0 none),
// the parts in `cuts`.
static int submit(const double *inst, int32_t count, double r, double g, double b, int *parts_out = NULL,
                  D3D11_RECT *cuts = NULL, int adaptive_damage = 0) {
  if (!rtv || !dev || !ctx || count < 0) return 0;
  atlas_flush();
  size_t slots = (size_t)(count > 0 ? count : 1);
  const size_t stride_bytes = (size_t)MB_INST * sizeof(float);
  if (slots > ((size_t)UINT_MAX - stride_bytes) / stride_bytes) return 0;
  size_t need = slots * stride_bytes;
  // (and the frame's ground after its instances: a rect over all the window, opaque, a part drawn again first)
  size_t room = need + stride_bytes;
  size_t n = (size_t)count * MB_INST;
  if (last_cap < need || !last_inst) {
    size_t cap = need <= (SIZE_MAX / 2) ? need * 2 : need;
    float *grown = (float *)realloc(last_inst, cap);
    if (!grown && cap != need) {
      cap = need;
      grown = (float *)realloc(last_inst, cap);
    }
    if (!grown) return 0;
    last_inst = grown;
    last_cap = cap;
  }
  if (!ensure_vbuf(room)) return 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return 0;
  float *f = (float *)m.pData;
  mb_groups_floats(last_inst, inst, count);
  if (n > 0) memcpy(f, last_inst, n * sizeof(float));
  float *gr = f + n;
  memset(gr, 0, MB_INST * sizeof(float));
  gr[0] = -16.0f; gr[1] = -16.0f; gr[2] = (float)vw + 32.0f; gr[3] = (float)vh + 32.0f;
  gr[8] = (float)r; gr[9] = (float)g; gr[10] = (float)b; gr[11] = 1.0f;
  gr[16] = -1e9f; gr[17] = -1e9f; gr[18] = 1e9f; gr[19] = 1e9f;
  ctx->Unmap(vbuf, 0);
  last_count = count;
  last_bg[0] = (float)r;
  last_bg[1] = (float)g;
  last_bg[2] = (float)b;
  // a window's into its canvas; without one, the offscreen target is kept as a canvas is
  int qslot = gpu_q_begin();
  ID3D11RenderTargetView *target = rtv;
  int *kept = &off_ok;
  if (chain) {
    ensure_canvas(fb_w, fb_h);
    if (!canvas_rtv) {
      dirty_told = dirty_whole = dirty_n = 0;
      encode(rtv, fb_w, fb_h, count, last_bg, last_inst);
      gpu_q_end(qslot);
      if (parts_out) *parts_out = -1;
      return 1;
    }
    target = canvas_rtv;
    kept = &canvas_ok;
  }
  D3D11_RECT parts[MB_PARTS];
  if (adaptive_damage && !dirty_whole &&
      !mb_glass_damage_expand(last_inst, count, dirty, &dirty_n, fb_w / vscale, fb_h / vscale, vscale)) dirty_whole = 1;
  int np = take_parts(fb_w, fb_h, *kept, parts);
  int missing = 0;
  if (np < 0) {
    encode(target, fb_w, fb_h, count, last_bg, last_inst);
    missing = encode_missing;
  }
  for (int i = 0; i < np; i++) {
    encode(target, fb_w, fb_h, count, last_bg, last_inst, &parts[i]);
    missing |= encode_missing;
  }
  if (np != 0) pictures_missing = missing;
  *kept = 1;
  if (parts_out) *parts_out = np;
  if (cuts) for (int i = 0; i < np; i++) cuts[i] = parts[i];
  if (chain) {
    // the canvas whole into the swap chain's buffer
    ID3D11Resource *back = NULL;
    rtv->GetResource(&back);
    ctx->CopyResource(back, canvas);
    back->Release();
  }
  gpu_q_end(qslot);
  return 1;
}

// How many of the compositor's beats a frame takes: one, or as many as keep the window to MB_FRAMES_MOST frames a
// second where the display shows twice that or more (240 Hz: two, 120 frames a second; 360: three; 144 and 165: one,
// each of theirs, not half of them). No more than 120 by default, as the other hosts' displays show at most (the
// user, 2026-11-13: 「给still fail/screenreplay默认最高120就行」): what a frame costs is paid for each, and past 120 it
// is not seen (ScreenReplay's viewer playing: 24% of a core at 240). MBUI_FRAMES_MOST says another most (0: the
// display's every frame). Asked of the compositor again each second, a display's rate being the user's to change.
int mb_frame_beats(void) {
  if (!dcomp) return 1;
  static int beats = 1;
  static ULONGLONG asked;
  ULONGLONG now = GetTickCount64();
  if (asked && now - asked < 1000) return beats;
  asked = now ? now : 1;
  static int most = -1;
  if (most < 0) {
    const wchar_t *said = mb_win_env(L"MBUI_FRAMES_MOST");
    most = said && *said ? _wtoi(said) : 120;
    if (most < 0) most = 120;
  }
  beats = 1;
  DWM_TIMING_INFO ti = {};
  ti.cbSize = sizeof ti;
  if (most > 0 && SUCCEEDED(DwmGetCompositionTimingInfo(NULL, &ti)) && ti.rateRefresh.uiDenominator) {
    // (a display's 239.76 is 240)
    double hz = (double)ti.rateRefresh.uiNumerator / (double)ti.rateRefresh.uiDenominator;
    int k = (int)((hz + 1.0) / (double)most);
    if (k > 1) beats = k;
  }
  return beats;
}

// what the frames presented since the last mb_render_pace owe the compositor's beat: 0 nothing, 1 the wait, 2 a window
// occluded (a hidden or minimized window does not wait for vsync: paced as if it did)
static int pace_owed;

int mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  int n = -1;
  D3D11_RECT parts[MB_PARTS];
  glass_drawn = 0;
  ad_mode = 1;
  ad_cur_dt = ad_next_dt(rw);
  rw->ad_frame_serial++;
  int adaptive_damage = dirty_told && !dirty_whole && rw->ad_settling;
  if (adaptive_damage) {
    for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
      if (rw->ad_slots[i].active && rw->ad_slots[i].settle_left > 0.0)
        mb_host_render_dirty(rw->ad_slots[i].cx - rw->ad_slots[i].hx - 4.0,
                             rw->ad_slots[i].cy - rw->ad_slots[i].hy - 4.0,
                             rw->ad_slots[i].hx * 2.0 + 8.0, rw->ad_slots[i].hy * 2.0 + 8.0);
    }
  }
  int drawn = submit(inst, count, r, g, b, &n, parts, adaptive_damage);
  if (drawn) ad_finalize_frame(rw, n < 0, rw->ad_frame_serial);
  glass_idle_tick();
  if (!drawn || !chain) {
    commit_presented();
    return 0;
  }
  // a hidden or minimized window does not wait for vsync; pace it as if it did. A flip model's swap chain is told the
  // parts that changed (what the compositor takes again; none: a pixel's), all of its buffer the canvas's
  HRESULT hr;
  if (flip_chain && n >= 0) {
    RECT dr[MB_PARTS];
    for (int i = 0; i < n; i++) dr[i] = {parts[i].left, parts[i].top, parts[i].right, parts[i].bottom};
    if (n == 0) dr[n++] = {0, 0, 1, 1};
    DXGI_PRESENT_PARAMETERS pp = {};
    pp.DirtyRectsCount = (UINT)n;
    pp.pDirtyRects = dr;
    hr = chain->Present1(1, 0, &pp);
  } else {
    hr = chain->Present(1, 0);
  }
  commit_presented();
  if (SUCCEEDED(hr) && hr != DXGI_STATUS_OCCLUDED) {
    DXGI_FRAME_STATISTICS fs = {};
    if (SUCCEEDED(chain->GetFrameStatistics(&fs)) && fs.PresentCount > 0) {
      LARGE_INTEGER now_qpc, freq_qpc;
      QueryPerformanceCounter(&now_qpc);
      QueryPerformanceFrequency(&freq_qpc);
      double period_ms = win_display_period_ms(freq_qpc.QuadPart);
      present_dropped += win_count_dropped_step(rw->last_present_count, rw->last_sync_refresh,
                                                rw->last_present_qpc, rw->has_frame_stats,
                                                fs.PresentCount, fs.SyncRefreshCount,
                                                now_qpc.QuadPart, freq_qpc.QuadPart, period_ms);
      rw->last_present_count = fs.PresentCount;
      rw->last_sync_refresh = fs.SyncRefreshCount;
      rw->last_present_qpc = now_qpc.QuadPart;
      rw->has_frame_stats = 1;
    }
  } else {
    rw->has_frame_stats = 0;
  }
  pace_owed = hr != DXGI_STATUS_OCCLUDED ? 1 : pace_owed ? pace_owed : 2;
  return SUCCEEDED(hr);
}

int mb_render_adaptive_settling(int wid) {
  if (wid < 0 || wid >= MB_WINS) return 0;
  return render_wins[wid].ad_settling;
}

int mb_render_adaptive_step(int wid) {
  if (wid < 0 || wid >= MB_WINS) return 0;
  RenderWin *back = rw;
  rw = &render_wins[wid];
  if (!rw->ad_settling || !last_inst || !rtv || !dev || !ctx || !chain) {
    rw = back;
    return 0;
  }
  dirty_told = dirty_whole = dirty_n = 0;
  for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
    if (rw->ad_slots[i].active && rw->ad_slots[i].settle_left > 0.0)
      mb_host_render_dirty(rw->ad_slots[i].cx - rw->ad_slots[i].hx - 4.0,
                           rw->ad_slots[i].cy - rw->ad_slots[i].hy - 4.0,
                           rw->ad_slots[i].hx * 2.0 + 8.0, rw->ad_slots[i].hy * 2.0 + 8.0);
  }
  if (!dirty_whole && !mb_glass_damage_expand(last_inst, last_count, dirty, &dirty_n,
                                               fb_w / vscale, fb_h / vscale, vscale)) dirty_whole = 1;
  ad_mode = 1;
  ad_cur_dt = ad_next_dt(rw);
  rw->ad_frame_serial++;
  ensure_canvas(fb_w, fb_h);
  ID3D11RenderTargetView *target = canvas_rtv ? canvas_rtv : rtv;
  D3D11_RECT parts[MB_PARTS];
  int np = canvas_rtv ? take_parts(fb_w, fb_h, canvas_ok, parts) : -1;
  if (np < 0) encode(target, fb_w, fb_h, last_count, last_bg, last_inst);
  else for (int i = 0; i < np; i++) encode(target, fb_w, fb_h, last_count, last_bg, last_inst, &parts[i]);
  if (canvas_rtv) {
    canvas_ok = 1;
    ID3D11Resource *back_res = NULL;
    rtv->GetResource(&back_res);
    ctx->CopyResource(back_res, canvas);
    back_res->Release();
  }
  ad_finalize_frame(rw, np < 0, rw->ad_frame_serial);
  HRESULT hr;
  if (flip_chain && np >= 0) {
    RECT dr[MB_PARTS];
    for (int i = 0; i < np; i++) dr[i] = {parts[i].left, parts[i].top, parts[i].right, parts[i].bottom};
    if (np == 0) dr[np++] = {0, 0, 1, 1};
    DXGI_PRESENT_PARAMETERS pp = {};
    pp.DirtyRectsCount = (UINT)np;
    pp.pDirtyRects = dr;
    hr = chain->Present1(1, 0, &pp);
  } else {
    hr = chain->Present(1, 0);
  }
  pace_owed = hr != DXGI_STATUS_OCCLUDED ? 1 : pace_owed ? pace_owed : 2;
  rw = back;
  return SUCCEEDED(hr);
}

// A composition's swap chain is not held to the display by its Present, so each round of frames (win_app.c: every
// window of the run that wanted one presented its, then this, once: each waiting after its own, two windows drew at
// half the display's rate) waits here for the compositor to compose (DwmFlush): a frame for each of the display's, none between that no one sees. Without it a window that
  // moves something every frame (a playhead going, a motion) drew as many as the machine could: 1759 to 1794 a second
  // whole in view on a 240 Hz display, 118% of a core, and 238 to 240 a second, 24% of one, waiting so (measured on
  // ScreenReplay's viewer, an RTX 5080's machine, 2026-11-13; partly covered 461 to 484 and 212 to 217). A waitable
  // swap chain's handle held nothing there (1648 to 1691). The compositor's beat is the primary display's: a window
  // on another display of another rate draws at the primary's. Where the compositor will not say (FAILED), a
  // millisecond's rest, so nothing spins. A frame is as many beats as mb_frame_beats says, counted from the beat the
  // frame before was let go on, not waited after its work: where its work had taken one beat of them already, it waits
  // for the next alone. Waiting them all after the work, a frame whose work took 4.2 to 8.3 ms at 240 Hz (a fast drag
  // of ScreenReplay's playhead over a 4K picture) came every 12.5 ms instead of 8.3, half its frames so, 92 to 97 a
  // second in an uneven step; counted from the last, 118 to 120 a second, 8.3 ms apart (2026-11-15).
void mb_render_pace(void) {
  int owed = pace_owed;
  pace_owed = 0;
  if (!owed) return;
  if (owed == 2) Sleep(16);
  else if (dcomp) {
    static LARGE_INTEGER last_beat;
    int beats = mb_frame_beats();
    if (FAILED(DwmFlush())) {
      Sleep(1);
    } else if (beats > 1) {
      LARGE_INTEGER now;
      QueryPerformanceCounter(&now);
      DWM_TIMING_INFO ti = {};
      ti.cbSize = sizeof ti;
      // (the beats since the last frame's, to the nearest: a DwmFlush comes back a little after its beat)
      int passed = 1;
      if (last_beat.QuadPart && SUCCEEDED(DwmGetCompositionTimingInfo(NULL, &ti)) && ti.qpcRefreshPeriod)
        passed = (int)((double)(now.QuadPart - last_beat.QuadPart) / (double)ti.qpcRefreshPeriod + 0.5);
      for (int i = passed < 1 ? 1 : passed; i < beats; i++)
        if (FAILED(DwmFlush())) break;
    }
    QueryPerformanceCounter(&last_beat);
  }
}

// Without a window (mbui-render, src/render): WARP's device whatever the machine has (the same rasterizer on every
// Windows: what the references are of), a texture the size a window's swap chain would be as
// the target, the text at the list's scale. A frame drawn there is drawn as a window's is, and its snapshot is of it.
static ID3D11Texture2D *off_target;

extern "C" void mb_render_init_offscreen(double w, double h, double scale) {
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  if (FAILED(make_device(D3D_DRIVER_TYPE_WARP, 0))) {
    fprintf(stderr, "no Direct3D 11 WARP device\n");
    return;
  }
  // which WARP drew it (the app's own beside it, as render_windows.sh puts the pinned one, or the system's)
  HMODULE warp = GetModuleHandleW(L"d3d10warp.dll");
  wchar_t warp_path[MAX_PATH];
  if (warp && GetModuleFileNameW(warp, warp_path, MAX_PATH)) fwprintf(stderr, L"WARP %ls\n", warp_path);
  make_pipeline();
  // (with every kind's pixel shader: what is drawn here is what a window draws once they are made)
  if (kinds_thread) WaitForSingleObject(kinds_thread, INFINITE);
  vw = w;
  vh = h;
  vscale = scale;
  fb_w = (int)floor(w * scale + 0.5);
  fb_h = (int)floor(h * scale + 0.5);
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)fb_w;
  td.Height = (UINT)fb_h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
  dev->CreateTexture2D(&td, NULL, &off_target);
  dev->CreateRenderTargetView(off_target, NULL, &rtv);
  mb_text_set_scale(scale);
}

// A frame drawn into the offscreen target and finished: out[0] the CPU's time of it, out[1] the GPU's (not measured
// here: -1), in ms.
extern "C" void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  LARGE_INTEGER f, t0, t1;
  QueryPerformanceFrequency(&f);
  QueryPerformanceCounter(&t0);
  submit(inst, count, r, g, b);
  ctx->Flush();
  QueryPerformanceCounter(&t1);
  out[0] = (double)(t1.QuadPart - t0.QuadPart) * 1000.0 / (double)f.QuadPart;
  out[1] = -1;
}

static int write_png(const wchar_t *path, const uint8_t *bgra, int w, int h, int stride) {
  IWICImagingFactory *wic = NULL;
  IWICStream *stream = NULL;
  IWICBitmapEncoder *enc = NULL;
  IWICBitmapFrameEncode *frame = NULL;
  int ok = 0;
  CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
  if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory, NULL, CLSCTX_INPROC_SERVER,
                                 __uuidof(IWICImagingFactory), (void **)&wic)) &&
      SUCCEEDED(wic->CreateStream(&stream)) &&
      SUCCEEDED(stream->InitializeFromFilename(path, GENERIC_WRITE)) &&
      SUCCEEDED(wic->CreateEncoder(GUID_ContainerFormatPng, NULL, &enc)) &&
      SUCCEEDED(enc->Initialize(stream, WICBitmapEncoderNoCache)) &&
      SUCCEEDED(enc->CreateNewFrame(&frame, NULL)) && SUCCEEDED(frame->Initialize(NULL)) &&
      SUCCEEDED(frame->SetSize((UINT)w, (UINT)h))) {
    WICPixelFormatGUID fmt = GUID_WICPixelFormat32bppBGRA;
    ok = SUCCEEDED(frame->SetPixelFormat(&fmt)) &&
         SUCCEEDED(frame->WritePixels((UINT)h, (UINT)stride, (UINT)(stride * h), (BYTE *)bgra)) &&
         SUCCEEDED(frame->Commit()) && SUCCEEDED(enc->Commit());
  }
  if (frame) frame->Release();
  if (enc) enc->Release();
  if (stream) stream->Release();
  if (wic) wic->Release();
  return ok;
}

// Instances `f` (`count` of them) drawn on the ground `bg` into a texture of their own, `w` × `h`, and copied where the
// CPU reads it (a staging texture, to Map; NULL where it could not be made). What the vertex buffer holds is drawn: the
// caller has put `f` there.
static ID3D11Texture2D *redrawn_of(int w, int h, int32_t count, const float *bg, const float *f) {
  D3D11_TEXTURE2D_DESC td = {};
  td.Width = (UINT)w;
  td.Height = (UINT)h;
  td.MipLevels = td.ArraySize = 1;
  td.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
  td.SampleDesc.Count = 1;
  td.Usage = D3D11_USAGE_DEFAULT;
  td.BindFlags = D3D11_BIND_RENDER_TARGET;
  ID3D11Texture2D *tex = NULL, *staging = NULL;
  ID3D11RenderTargetView *view = NULL;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &tex))) return NULL;
  if (FAILED(dev->CreateRenderTargetView(tex, NULL, &view))) {
    tex->Release();
    return NULL;
  }
  int prev_ad_mode = ad_mode;
  if (ad_mode > 0) ad_mode = 0;
  encode(view, w, h, count, bg, f);
  ad_mode = prev_ad_mode;
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  if (SUCCEEDED(dev->CreateTexture2D(&td, NULL, &staging))) ctx->CopyResource(staging, tex);
  view->Release();
  tex->Release();
  if (rtv) ctx->OMSetRenderTargets(1, &rtv, NULL);
  return staging;
}

// The last presented frame drawn again (its instances are what the vertex buffer holds), as redrawn_of draws.
static ID3D11Texture2D *redrawn(int w, int h) {
  return redrawn_of(w, h, last_count, last_bg, last_inst);
}

// `count` instances of `f` into the vertex buffer, grown to hold them: 0 where it could not be written.
static int fill_vbuf(const float *f, int32_t count) {
  if (!dev || !ctx || count < 0) return 0;
  size_t slots = (size_t)(count > 0 ? count : 1);
  const size_t stride_bytes = (size_t)MB_INST * sizeof(float);
  if (slots > (size_t)UINT_MAX / stride_bytes) return 0;
  size_t need = slots * stride_bytes;
  if (!ensure_vbuf(need)) return 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (FAILED(ctx->Map(vbuf, 0, D3D11_MAP_WRITE_DISCARD, 0, &m))) return 0;
  if (count > 0) memcpy(m.pData, f, (size_t)count * stride_bytes);
  ctx->Unmap(vbuf, 0);
  return 1;
}

// Instances never presented (a shot's, mbui/src/ui/shot.mbt) drawn as a frame is, but `scale` pixels a point into a
// picture of their own w × h (their 0, 0 its top left), on the ground r, g, b, and its pixels into `out` as
// mb_render_drawn_pixels gives the frame's; the size frames are drawn at put back after, and the vertex buffer given
// back the frame's (a snapshot draws it again). 1 when read.
extern "C" int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale,
                                       int32_t w, int32_t h, moonbit_bytes_t out) {
  if (!dev || !ctx || count <= 0 || !(scale > 0) || w <= 0 || h <= 0) return 0;
  if ((size_t)w > SIZE_MAX / 4 / (size_t)h) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * (size_t)h * 4) return 0;
  if ((size_t)count > (size_t)UINT_MAX / ((size_t)MB_INST * sizeof(float))) return 0;
  size_t n = (size_t)count * MB_INST;
  float *f = (float *)malloc(n * sizeof(float));
  if (!f) return 0;
  for (size_t i = 0; i < n; i++) f[i] = (float)inst[i];
  float bg[3] = {(float)r, (float)g, (float)b};
  double kw = vw, kh = vh, ks = vscale;
  vscale = scale;
  vw = w / scale;
  vh = h / scale;
  int prev_ad_mode = ad_mode;
  ad_mode = -1;
  ID3D11Texture2D *staging = fill_vbuf(f, count) ? redrawn_of(w, h, count, bg, f) : NULL;
  ad_mode = prev_ad_mode;
  vw = kw;
  vh = kh;
  vscale = ks;
  free(f);
  // (the frame's own back where it was)
  if (last_inst) fill_vbuf(last_inst, last_count);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    for (int k = 0; k < h; k++) {
      const uint8_t *s = (const uint8_t *)m.pData + (size_t)k * m.RowPitch;
      uint8_t *d = out + (size_t)k * w * 4;
      for (int j = 0; j < w; j++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    ctx->Unmap(staging, 0);
    ok = 1;
  }
  staging->Release();
  return ok;
}

extern "C" int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out) {
  int fw = fb_w, fh = fb_h;
  if (!dev || !last_inst || fw <= 0 || fh <= 0 || w <= 0 || h <= 0 || x < 0 || y < 0 || x + w > fw || y + h > fh) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  ID3D11Texture2D *staging = redrawn(fw, fh);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    for (int r = 0; r < h; r++) {
      const uint8_t *s = (const uint8_t *)m.pData + (size_t)(y + r) * m.RowPitch + (size_t)x * 4;
      uint8_t *d = out + (size_t)r * w * 4;
      for (int k = 0; k < w; k++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    ctx->Unmap(staging, 0);
    ok = 1;
  }
  staging->Release();
  return ok;
}

int mb_render_snapshot(const wchar_t *path) {
  int w = fb_w, h = fb_h;
  if (!dev || w <= 0 || h <= 0) return 0;
  ID3D11Texture2D *staging = redrawn(w, h);
  if (!staging) return 0;
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    const uint8_t *px = (const uint8_t *)m.pData;
    int stride = (int)m.RowPitch;
    uint8_t *out = NULL;
    if (mb_views_count() > 0) {
      // the native views' pictures under the canvas, seen through its holes (premultiplied: canvas + under × (1 - α))
      out = (uint8_t *)calloc((size_t)w * h, 4);
      mb_views_draw_under(out, w, h, mb_app_scale());
      for (int y = 0; y < h; y++) {
        const uint8_t *s = px + (size_t)y * stride;
        uint8_t *d = out + (size_t)y * w * 4;
        for (int x = 0; x < w; x++, s += 4, d += 4) {
          int k = 255 - s[3];
          for (int c = 0; c < 3; c++) d[c] = (uint8_t)(s[c] + (d[c] * k + 127) / 255);
          d[3] = (uint8_t)(s[3] + (d[3] * k + 127) / 255);
        }
      }
      px = out;
      stride = w * 4;
    }
    ok = write_png(path, px, w, h, stride);
    free(out);
    ctx->Unmap(staging, 0);
  }
  staging->Release();
  return ok;
}

// The offscreen target as its frames left it (not the last frame drawn again: what drawing only the parts that differ
// made of it, mbui-render's MBUI_DL_FROM), as a PNG.
extern "C" int mb_render_snapshot_drawn(const wchar_t *path) {
  if (!off_target) return 0;
  D3D11_TEXTURE2D_DESC td = {};
  off_target->GetDesc(&td);
  td.Usage = D3D11_USAGE_STAGING;
  td.BindFlags = 0;
  td.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
  ID3D11Texture2D *staging = NULL;
  if (FAILED(dev->CreateTexture2D(&td, NULL, &staging))) return 0;
  ctx->CopyResource(staging, off_target);
  int ok = 0;
  D3D11_MAPPED_SUBRESOURCE m;
  if (SUCCEEDED(ctx->Map(staging, 0, D3D11_MAP_READ, 0, &m))) {
    ok = write_png(path, (const uint8_t *)m.pData, (int)td.Width, (int)td.Height, (int)m.RowPitch);
    ctx->Unmap(staging, 0);
  }
  staging->Release();
  return ok;
}

// What the screen shows of the window's client area (the desktop's composition: the canvas over the native views),
// as a PNG: a check of what the snapshot above puts together itself.
int mb_screen_snapshot(void *hwnd, const wchar_t *path) {
  RECT rc;
  GetClientRect((HWND)hwnd, &rc);
  POINT o = {0, 0};
  ClientToScreen((HWND)hwnd, &o);
  int w = rc.right, h = rc.bottom;
  if (w <= 0 || h <= 0) return 0;
  HDC screen = GetDC(NULL), mem = CreateCompatibleDC(screen);
  BITMAPINFO bi = {};
  bi.bmiHeader.biSize = sizeof bi.bmiHeader;
  bi.bmiHeader.biWidth = w;
  bi.bmiHeader.biHeight = -h;
  bi.bmiHeader.biPlanes = 1;
  bi.bmiHeader.biBitCount = 32;
  void *bits = NULL;
  HBITMAP bm = CreateDIBSection(mem, &bi, DIB_RGB_COLORS, &bits, NULL, 0);
  int ok = 0;
  if (bm) {
    HGDIOBJ was = SelectObject(mem, bm);
    if (BitBlt(mem, 0, 0, w, h, screen, o.x, o.y, SRCCOPY | CAPTUREBLT)) {
      GdiFlush();
      uint8_t *px = (uint8_t *)bits;
      for (int i = 0; i < w * h; i++) px[i * 4 + 3] = 255;
      ok = write_png(path, px, w, h, w * 4);
    }
    SelectObject(mem, was);
    DeleteObject(bm);
  }
  DeleteDC(mem);
  ReleaseDC(NULL, screen);
  return ok;
}

// The GPU's time for the last completed D3D11 frame (non-blocking timestamp query ring), in ms (-1: none yet).
extern "C" double mb_host_gpu_ms(void) {
  gpu_q_poll();
  return last_gpu_ms;
}
// Frames dropped during continuous presentation (DXGI_FRAME_STATISTICS sync-refresh vs present-count delta).
extern "C" int32_t mb_host_frames_dropped(void) { return present_dropped; }
