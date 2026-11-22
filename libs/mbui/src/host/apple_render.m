// Metal renderer: one instanced quad per scene instance (some drawn in strips: bands.h), by one shader made a pipeline
// for each kind it draws most (kind_pipe).
#import "apple.h"
#include "corner_sl.h"
#include "contained.h"
#include "bands.h"
#include "groups.h"
#import <ImageIO/ImageIO.h>
#import <CoreGraphics/CoreGraphics.h>
#include <os/lock.h>
#include <stdatomic.h>

// the numbers of an instance (src/ui/scene.mbt)
#define MB_INST 60
#include "glass_damage.h"

static id<MTLDevice> dev;
static id<MTLCommandQueue> queue;
static id<MTLRenderPipelineState> mpipe;
static id<MTLRenderPipelineState> rpipe_off;
// holes for native views (kind 9): written, not blended
static id<MTLRenderPipelineState> hpipe;
// a ground's flat middle (bands.h mb_pieces)
static id<MTLRenderPipelineState> fpipe;
// the words' glyphs (R8) and colour glyphs (RGBA), square (apple.h)
static id<MTLTexture> atlas, catlas;
static id<MTLBuffer> bufs[3];
static size_t buf_cap[3];
static int buf_i;
static dispatch_semaphore_t inflight;
// What of a frame is said to differ from the frame before (partial redraw, below): told at all, all of it, or its parts.
#define MB_PARTS 8
// the captures of glass over native views a frame has at most (glass_through)
#define MB_THROUGH 16
typedef struct {
  int told, whole, n, glass_closure;
  double r[MB_PARTS][4];
} MBDirty;

// A frame handed from the main thread to the presenting queue (present_q, below): its instances as floats (a buffer of
// pool_take's), its ground, the size it was made at and the drawable's then, what of it differs from the frame before,
// whether it has glass and which of its captures frost a native view (glass_through), the atlas's puts it needs
// (atlas_seq), the textures of its pictures and streams as they were when it was made (mb_image_texture and
// mb_stream_texture are the main thread's alone), and its frame of a latency run (mac_latency.h).
@interface MBFrame : NSObject {
 @public
  float *inst;
  size_t cap;
  int32_t count;
  double bg[3], w, h, scale;
  int tw, th, glass, lat;
  MBDirty parts;
  int through_n;
  float through_tid[MB_THROUGH];
  uint64_t atlas_seq;
  NSMutableDictionary<NSNumber *, id> *texs;
}
@end

// What is a window's own (mac_app.m: the windows of one run, each its view and its layer; the device, the queue, the
// pipelines, the atlases and the ring of instance buffers are all the windows'). The main thread's: its layer and its
// size (mb_render_set_size's); the last frame, kept for snapshots and compared with the next (its instances and ground:
// keep_last's); the frame last handed to be shown: its size, and whether it shows a stream (whose pictures change under
// the same instances); what was said to differ since (`said`). The presenting queue's (present_q): the canvas its frames
// are drawn into, whether it holds the last drawn; the frame waiting to be drawn (`pending`, under present_mu) and
// whether a drawing of it is queued; whether a frame found no drawable (`missed`: the next is not skipped as shown). Put
// in place for a window by mb_render_use.
#define MB_ADAPTIVE_MAX 16
#define MB_AD_TAU 0.070
#define MB_AD_SETTLE_SEC 0.42
#define MB_AD_MATCH_DIST 64.0

typedef struct {
  int active;
  float cx, cy, hx, hy;
  int is_dark;
  double settle_left;
  uint64_t settle_serial;
  uint64_t updated_serial;
  uint64_t seen_serial;
} MBAdSlot;

typedef struct {
  CAMetalLayer *layer;
  double w, h, scale;
  float *inst;
  int32_t count;
  size_t cap;
  double bg[3];
  double shown_w, shown_h, shown_scale;
  int shown_ok, shown_streams;
  MBDirty said;
  id<MTLTexture> cv;
  int cv_ok;
  MBFrame *pending;
  int queued;
  atomic_int missed;
  id<MTLTexture> ad_tex[2];
  int ad_cur;
  id<MTLBuffer> ad_rb[3];
  int ad_rb_i;
  int ad_rb_prev_copied;
  uint32_t ad_track_mask;
  atomic_uint_fast64_t ad_conv_serial[MB_ADAPTIVE_MAX];
  MBAdSlot ad_slots[MB_ADAPTIVE_MAX];
  double ad_last_time;
  uint64_t ad_frame_serial;
  atomic_int ad_settling;
  atomic_int ad_drawing;
  atomic_int ad_has_adaptive;
  MBDirty ad_settle_dirty;
} MBRenderWin;
static MBRenderWin render_wins[MB_WINS] = {[0 ... MB_WINS - 1] = {.w = 800, .h = 600, .scale = 2}};
static MBRenderWin *rw = &render_wins[0];
#define mlayer (rw->layer)
#define vw (rw->w)
#define vh (rw->h)
#define vscale (rw->scale)
#define last_inst (rw->inst)
#define last_count (rw->count)
#define last_cap (rw->cap)
#define last_bg (rw->bg)
#define shown_w (rw->shown_w)
#define shown_h (rw->shown_h)
#define shown_scale (rw->shown_scale)
#define shown_ok (rw->shown_ok)
#define shown_streams (rw->shown_streams)
#define canvas (rw->cv)
#define canvas_ok (rw->cv_ok)
#define dirty (rw->said.r)
#define dirty_n (rw->said.n)
#define dirty_whole (rw->said.whole)
#define dirty_told (rw->said.told)

// The window of the run drawn now (mac_app.m's win_use): its layer, its size, its last frame and its canvas in place.
void mb_render_use(int wid) {
  if (wid >= 0 && wid < MB_WINS) rw = &render_wins[wid];
}

// ---------------------------------------------------------------------------
// Presenting off the main thread. Waiting for a buffer of the ring (the GPU three frames behind), for a drawable (the
// display's swapchain full: a GPU slowed by its heat, a busy window server) and encoding a frame are done on a serial
// queue of their own (present_q), not on the main thread that takes input and builds the next frame: there such a wait
// held the touches, a glide and the next frame's layout for 16-50 ms. The main thread makes a frame's floats, compares
// it with the last, keeps it as the last and hands it over (MBFrame) as the window's one frame waiting (`pending`): a
// frame made while the one before still waits takes its place, what each said to differ joined (dirty_join), so a slow
// GPU draws the newest frame, never a queue of old ones behind the hand. What the main thread alone may touch stays
// there: the pictures' and streams' textures are looked up as the frame is made (frame_texs), the glyphs it puts in the
// atlases are kept in order and put in by the queue before the frame that needs them (atlas_puts). A frame presented
// with Core Animation's transaction (a window resized, shown first or turned; native views moved with it; the layer's
// opacity changed) or checked (MBUI_PARTIAL_CHECK) is drawn on the main thread as before, once the queue has drawn what
// it holds (present_drain); so is all that reads back or lets go of what drawing holds.
static dispatch_queue_t present_q;
static os_unfair_lock present_mu = OS_UNFAIR_LOCK_INIT;

// Everything handed to present_q drawn, its state the caller's (the main thread's) till it hands more.
static void present_drain(void) {
  if (present_q) dispatch_sync(present_q, ^{
                 });
}

// The buffers frames' floats are made into, given back as a frame is drawn or replaced: a few kept, the rest freed.
#define MB_POOL 3
static float *pool_bufs[MB_POOL];
static size_t pool_caps[MB_POOL];

static float *pool_take(size_t need, size_t *cap) {
  float *got = NULL;
  size_t got_cap = 0;
  os_unfair_lock_lock(&present_mu);
  for (int i = 0; i < MB_POOL; i++)
    if (pool_bufs[i] && (!got || pool_caps[i] >= need)) {
      float *b = pool_bufs[i];
      size_t c = pool_caps[i];
      pool_bufs[i] = got;
      pool_caps[i] = got_cap;
      got = b;
      got_cap = c;
      if (got_cap >= need) break;
    }
  os_unfair_lock_unlock(&present_mu);
  if (got_cap < need) {
    free(got);
    got_cap = need + need / 4;
    got = malloc(got_cap);
  }
  *cap = got_cap;
  return got;
}

static void pool_give(float *b, size_t cap) {
  if (!b) return;
  os_unfair_lock_lock(&present_mu);
  for (int i = 0; i < MB_POOL; i++)
    if (!pool_bufs[i]) {
      pool_bufs[i] = b;
      pool_caps[i] = cap;
      b = NULL;
      break;
    }
  os_unfair_lock_unlock(&present_mu);
  free(b);
}

@implementation MBFrame
- (void)dealloc {
  pool_give(inst, cap);
}
@end

// What window `wid` kept let go of, as it closes: the next window given its number starts as none was drawn.
void mb_render_forget(int wid) {
  if (wid <= 0 || wid >= MB_WINS) return;
  present_drain();
  MBRenderWin *w = &render_wins[wid];
  free(w->inst);
  *w = (MBRenderWin){.w = 800, .h = 600, .scale = 2};
}

// A part said to differ added to `d`: past as many as it keeps, the last grown round it.
static void dirty_add(MBDirty *d, double x, double y, double w, double h) {
  d->told = 1;
  if (w < 0 || h < 0) {
    d->whole = 1;
  } else if (w > 0 && h > 0) {
    if (d->n == MB_PARTS) {
      double *e = d->r[MB_PARTS - 1];
      double x1 = fmax(e[0] + e[2], x + w), y1 = fmax(e[1] + e[3], y + h);
      e[0] = fmin(e[0], x);
      e[1] = fmin(e[1], y);
      e[2] = x1 - e[0];
      e[3] = y1 - e[1];
    } else {
      double *e = d->r[d->n++];
      e[0] = x; e[1] = y; e[2] = w; e[3] = h;
    }
  }
}

// What a frame said to differ from the one before joined with what the frame it replaces (`was`, never drawn) said:
// all of it where either was drawn whole, else both's parts (what differs from the frame drawn last is in one or the
// other).
static void dirty_join(MBDirty *d, const MBDirty *was) {
  if (!d->told || d->whole) return;
  if (!was->told || was->whole) {
    d->whole = 1;
    return;
  }
  d->glass_closure |= was->glass_closure;
  for (int i = 0; i < was->n; i++) dirty_add(d, was->r[i][0], was->r[i][1], was->r[i][2], was->r[i][3]);
}

// The glyphs put in the atlases (mb_atlas_upload, the main thread's), kept in order till the queue puts them in, each
// numbered: a frame is drawn after the puts made before it and none after (a glyph put for the next frame where an
// atlas started over could be where one of this frame's was).
typedef struct {
  uint64_t seq;
  int color, x, y, w, h;
  uint8_t *px;
} AtlasPut;
static AtlasPut *atlas_puts;
static size_t atlas_puts_n, atlas_puts_cap, atlas_puts_head;
static uint64_t atlas_seq;
// glass (src/ui/glass.mbt): the passes that blur what is under it (into the copy, 8 bits a channel, and into the rest,
// half floats), the copies they work in (level j is 1/2^j of the largest capture yet, the glass and the blur's margin
// round it, not of the target: a composer's strip, not the window; tmp for a Gaussian's first half), the GPU's time of
// the last frame done
static id<MTLRenderPipelineState> ppipe, ppipe_deep, cpipe, adpipe;
static id<MTLTexture> lv[4], ltmp;
static int lv_w, lv_h;
static int lv_shrink_frames, lv_win_max_w, lv_win_max_h, lv_frame_max_w, lv_frame_max_h;
static double last_gpu = -1;
static double ad_fixed_dt = 0.0;
// The size, in points, and the pixels a point of the frame being drawn (encode and what it draws by): its MBFrame's on
// present_q, the window's or a picture's own (read_of) on the main thread.
static double at_w = 800, at_h = 600, at_scale = 2;
// The textures of its pictures and streams as its MBFrame found them (frame_texs; NSNull none yet), or nil: looked up
// as it is drawn (the main thread's own drawing).
static NSDictionary<NSNumber *, id> *at_texs;

static NSString *shader_src = @
"#include <metal_stdlib>\n"
"using namespace metal;\n"
"// the kind of what this pipeline draws, fixed (kind_pipe); -1 any, as the instance says\n"
"constant int one_kind [[function_constant(0)]];\n"
"// scene.mbt's 60 numbers: clip, rc and rs the rounded rect it is cut to (its rect x0 y0 x1 y1, its corners' radii,\n"
"// how smooth they are); rot how it is turned (radians, about rot.yz; its clip where it is drawn when rot.w is 1); rr\n"
"// a box's corners' radii (top left, top right, bottom right, bottom left); oclip, orc, ors the rounded clip outside\n"
"// its own that its own cuts through, as clip, rc, rs (none where orc is 0); fade where it fades out towards a cut\n"
"// (from its top: 0 at x, whole y below it; from its foot: 0 at z, whole w above it; none where y, w are 0), fadex\n"
"// the same across (from its left, from its right)\n"
"struct Inst { float4 rect; float4 p; float4 color; float4 c2; float4 clip; float4 pad; float4 rc; float4 rs; float4 rot; float4 rr; float4 oclip; float4 orc; float4 ors; float4 fade; float4 fadex; };\n"
"struct U { float2 vp; float scale; float pad; float2 origin; float2 _pad2; };\n"
"// glass: where a point's backdrop is in the blurred copy (uv = p * map.xy + map.zw, kept in uvc), a liquid group's\n"
"// bounds, shapes and corners, how many (misc.x); misc.y 1 where what it copied of a native view's hole is let through\n"
"// (glass_through)\n"
"struct G { float4 map; float4 uvc; float4 gb; float4 shape[8]; float4 rad[8]; float4 misc; float4 ad_box[16]; float4 ad_meta; };\n"
"struct VOut { float4 pos [[position]]; float2 p; float2 cp; uint iid [[flat]]; };\n"
"vertex VOut vmain(uint vid [[vertex_id]], uint iid [[instance_id]],\n"
"    const device Inst* inst [[buffer(0)]], constant U& u [[buffer(1)]], constant G& g [[buffer(2)]]) {\n"
"  Inst I = inst[iid];\n"
"  float2 corner = float2((vid == 1 || vid == 4 || vid == 5) ? 1.0 : 0.0,\n"
"                         (vid == 2 || vid == 3 || vid == 5) ? 1.0 : 0.0);\n"
"  int kind = int(I.p.y + 0.5);\n"
"  bool merged_liquid = kind == 6 && I.pad.w > 0.0;\n"
"  float grow = kind == 2 ? I.p.w * 3.0 + 2.0 : (kind == 6 && I.pad.w <= 0.0) ? 2.0 : ((kind == 0 || kind == 4 || kind == 5 || kind == 8) ? 1.0 : 0.0);\n"
"  float2 pos = I.rect.xy - grow + corner * (I.rect.zw + 2.0 * grow);\n"
"  if (merged_liquid) pos = mix(g.gb.xy, g.gb.zw, corner);\n"
"  // the pieces of shapes (kind 12): nothing drawn\n"
"  if (kind == 12) pos = float2(0.0, 0.0);\n"
"  // turned (scene.mbt 32-35): drawn turned about its point, everything of how in its own place (o.p), its clip there\n"
"  // too or (35: one from outside what turned) where it is drawn (o.cp)\n"
"  float2 at = pos;\n"
"  if (I.rot.x != 0.0) { float2 d = pos - I.rot.yz; float c = cos(I.rot.x), s = sin(I.rot.x); at = I.rot.yz + float2(c * d.x - s * d.y, s * d.x + c * d.y); }\n"
"  VOut o;\n"
"  float2 rel = at - u.origin;\n"
"  o.pos = float4(rel.x / u.vp.x * 2.0 - 1.0, 1.0 - rel.y / u.vp.y * 2.0, 0.0, 1.0);\n"
"  o.p = pos; o.cp = I.rot.w > 0.5 ? at : pos; o.iid = iid;\n"
"  return o;\n"
"}\n"
MB_CORNER_SL
"static float sd_rr(float2 p, float4 r, float4 rad) {\n"
"  float2 hs = r.zw * 0.5;\n"
"  return mb_sd_box(p - r.xy - hs, hs, mb_corner_of(p - r.xy - hs, rad), 1e9);\n"
"}\n"
"// a notch cut into the top edge (scene.mbt 21-23): a circle about the top's middle (pad.y below it, pad.z its radius),\n"
"// met by the edge through fillets (pad.w): the rounded intersection with what is outside the circle\n"
"static float notch_cut(float d, float2 p, float4 r, float4 pad) {\n"
"  if (pad.z <= 0.0) return d;\n"
"  float b = pad.z - length(p - float2(r.x + r.z * 0.5, r.y + pad.y));\n"
"  float f = max(pad.w, 0.0);\n"
"  float2 u = max(float2(f + d, f + b), 0.0);\n"
"  return min(-f, max(d, b)) + length(u);\n"
"}\n"
"static float smin_k(float a, float b, float k) {\n"
"  if (k <= 0.0) return min(a, b);\n"
"  float h = max(k - abs(a - b), 0.0) / k;\n"
"  return min(a, b) - h * h * k * 0.25;\n"
"}\n"
"static float sd_group(float2 p, constant G& g, float k) {\n"
"  float d = 1e9;\n"
"  int n = int(g.misc.x + 0.5);\n"
"  for (int i = 0; i < 8; i++) {\n"
"    if (i >= n) break;\n"
"    d = smin_k(d, sd_rr(p, g.shape[i], g.rad[i]), k);\n"
"  }\n"
"  return d;\n"
"}\n"
"// Integral of linear ramp from 0 to w (contourOffset = 0, width w in device px)\n"
"static float mb_contour_int(float t, float w) {\n"
"  float u = clamp(t, 0.0, w);\n"
"  return u - u * u / (2.0 * w);\n"
"}\n"
"static float4 backdrop4(texture2d<float> bd, constant G& g, float2 p) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 uv = clamp(p * g.map.xy + g.map.zw, g.uvc.xy, g.uvc.zw);\n"
"  return bd.sample(s, uv);\n"
"}\n"
"static float3 backdrop(texture2d<float> bd, constant G& g, float2 p) { return backdrop4(bd, g, p).rgb; }\n"
"static float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }\n"
"static float mb_backdrop_luma_rect(texture2d<float> bd, constant G& g, float2 c, float2 h) {\n"
"  float sum = 0.0;\n"
"  float mx1 = -1.0, mx2 = -1.0;\n"
"  float mn1 = 2.0, mn2 = 2.0;\n"
"  for (int iy = -1; iy <= 1; iy++) {\n"
"    float py = c.y + float(iy) * (h.y * 0.60);\n"
"    for (int ix = -2; ix <= 2; ix++) {\n"
"      float px = c.x + float(ix) * (h.x * 0.38);\n"
"      float y = luma(backdrop(bd, g, float2(px, py)));\n"
"      sum += y;\n"
"      if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }\n"
"      if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }\n"
"    }\n"
"  }\n"
"  return (sum - mx1 - mx2 - mn1 - mn2) / 11.0;\n"
"}\n"
"static float mb_unpack16(float2 rg) {\n"
"  float hi = floor(clamp(rg.x, 0.0, 1.0) * 255.0 + 0.5);\n"
"  float lo = floor(clamp(rg.y, 0.0, 1.0) * 255.0 + 0.5);\n"
"  return (hi * 256.0 + lo) / 65535.0;\n"
"}\n"
"static float2 mb_pack16(float v) {\n"
"  float q = floor(clamp(v, 0.0, 1.0) * 65535.0 + 0.5);\n"
"  float hi = floor(q / 256.0);\n"
"  float lo = q - hi * 256.0;\n"
"  return float2(hi / 255.0, lo / 255.0);\n"
"}\n"
"static float ad_sample(texture2d<float> bd, texture2d<float> ad_tex, constant G& g, float2 ac, float fallback_r, bool is_dark_glass) {\n"
"  int ad_n = int(g.ad_meta.x + 0.5);\n"
"  if (ad_n > 0) {\n"
"    int best = -1;\n"
"    float best_d = 1e9;\n"
"    for (int i = 0; i < 16; i++) {\n"
"      if (i >= ad_n) break;\n"
"      float d = length(ac - g.ad_box[i].xy);\n"
"      if (d <= 2.0 && d < best_d) { best = i; best_d = d; }\n"
"    }\n"
"    if (best < 0) {\n"
"      best_d = 1e9;\n"
"      for (int i = 0; i < 16; i++) {\n"
"        if (i >= ad_n) break;\n"
"        float2 diff = abs(ac - g.ad_box[i].xy);\n"
"        if (diff.x <= g.ad_box[i].z + 2.0 && diff.y <= g.ad_box[i].w + 2.0) {\n"
"          float d = length(diff);\n"
"          if (d < best_d) { best = i; best_d = d; }\n"
"        }\n"
"      }\n"
"    }\n"
"    if (best >= 0) {\n"
"      return mb_unpack16(ad_tex.read(uint2(uint(best), 0)).rg);\n"
"    }\n"
"  }\n"
"  float bgL = mb_backdrop_luma_rect(bd, g, ac, float2(max(fallback_r, 1.0)));\n"
"  return is_dark_glass ? smoothstep(0.35, 0.85, bgL) : (1.0 - smoothstep(0.30, 0.42, bgL));\n"
"}\n"
"static float3 mb_adaptive_ink(float3 rgb, float darkT) {\n"
"  float ch = max(max(rgb.r, rgb.g), rgb.b) - min(min(rgb.r, rgb.g), rgb.b);\n"
"  if (ch <= 0.08) {\n"
"    float origL = luma(rgb);\n"
"    if (origL < 0.5) {\n"
"      float inkT = smoothstep(0.0, 1.0, darkT);\n"
"      float lightL = clamp(1.06 - origL, 0.68, 0.98);\n"
"      rgb = mix(rgb, float3(lightL), inkT);\n"
"    }\n"
"  }\n"
"  return rgb;\n"
"}\n"
"// how much of the pixel at p its rounded clip keeps (r: the corners' radii, top left, then clockwise; s: how smooth\n"
"// each is), its edge covered as a box's own (0.5 - d * scale), so what it cuts meets the ground of the box that cuts it\n"
"static float clip_cover(float2 p, float4 c, float4 r, float4 s, float scale) {\n"
"  float d = mb_sd_clip(p, c, r, s, 1.0 + 2.0 / scale);\n"
"  return clamp(0.5 - d * scale, 0.0, 1.0);\n"
"}\n"
"fragment float4 fmain(VOut in [[stage_in]], const device Inst* inst [[buffer(0)]],\n"
"    constant U& u [[buffer(1)]], constant G& g [[buffer(2)]], texture2d<float> atlas [[texture(0)]],\n"
"    texture2d<float> img [[texture(1)]], texture2d<float> bd [[texture(2)]], texture2d<float> catlas [[texture(3)]],\n"
"    texture2d<float> ad_tex [[texture(4)]]) {\n"
"  Inst I = inst[in.iid];\n"
"  float2 p = in.p, cp = in.cp;\n"
"  // cut to its clip: a rect's, hard; a rounded one's, covered as edges are\n"
"  float cover = 1.0;\n"
"  if (max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0) {\n"
"    cover = clip_cover(cp, I.clip, I.rc, I.rs, u.scale);\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  } else if (cp.x < I.clip.x || cp.y < I.clip.y || cp.x > I.clip.z || cp.y > I.clip.w) discard_fragment();\n"
"  // and by the clip outside it, where it has one (a pane round an image's frame in its corner)\n"
"  if (max(max(I.orc.x, I.orc.y), max(I.orc.z, I.orc.w)) > 0.0) {\n"
"    cover *= clip_cover(cp, I.oclip, I.orc, I.ors, u.scale);\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  }\n"
"  int kind = one_kind == 13 ? 6 : (one_kind >= 0 ? one_kind : int(I.p.y + 0.5));\n"
"  bool prog_glass = (kind == 5 && I.pad.z < -0.5);\n"
"  // and faded out towards a cut, each pixel by where it is (scene.mbt 52-59)\n"
"  float fade_r = 1.0;\n"
"  if (I.fade.y > 0.0) fade_r *= clamp((cp.y - I.fade.x) / I.fade.y, 0.0, 1.0);\n"
"  if (I.fade.w > 0.0) fade_r *= clamp((I.fade.z - cp.y) / I.fade.w, 0.0, 1.0);\n"
"  if (I.fadex.y > 0.0) fade_r *= clamp((cp.x - I.fadex.x) / I.fadex.y, 0.0, 1.0);\n"
"  if (I.fadex.w > 0.0) fade_r *= clamp((I.fadex.z - cp.x) / I.fadex.w, 0.0, 1.0);\n"
"  if (fade_r <= 0.0) discard_fragment();\n"
"  if (!prog_glass) {\n"
"    cover *= fade_r;\n"
"    if (cover <= 0.0) discard_fragment();\n"
"  }\n"
"  float4 col = I.color;\n"
"  if (kind == 1 || kind == 3 || kind == 7) {\n"
"    constexpr sampler s(filter::linear, coord::pixel);\n"
"    // within its own cell (c2: where in the atlas, in texels; a colour glyph's MB_ATLAS_COLOR_U across past its place\n"
"    // in theirs), however its rect is stretched or turned: a sample past the cell's edge texels would blend in what\n"
"    // lies beside it (another glyph, one left from before the atlas started over). The words' atlas has a glyph's\n"
"    // cover alone: white, premultiplied, as the colour one would have it.\n"
"    bool colour = I.c2.x >= 16384.0;\n"
"    float2 at = float2(I.c2.x - (colour ? 16384.0 : 0.0), I.c2.y);\n"
"    // One drawn as big as its picture, not turned, its corner on a pixel: each pixel its texel's centre, as\n"
"    // win_render.cpp takes it (worked out of where it is across the rect, a float's division took a texel's\n"
"    // neighbour in where its rounding fell, at 3, 2.625 and 1.5 pixels a point and far across)\n"
"    float2 off = abs(I.rect.zw * u.scale - I.c2.zw);\n"
"    float2 r0 = I.rect.xy * u.scale, r0i = floor(r0 + 0.5);\n"
"    bool exact = I.rot.x == 0.0 && max(off.x, off.y) <= 0.5 && max(abs(r0.x - r0i.x), abs(r0.y - r0i.y)) <= 0.05;\n"
"    float2 tex = exact ? floor(p * u.scale - r0i) + 0.5 : (p - I.rect.xy) / I.rect.zw * I.c2.zw;\n"
"    float2 uv = clamp(at + tex, at + 0.5, at + I.c2.zw - 0.5);\n"
"    float4 t = colour ? catlas.sample(s, uv) : float4(atlas.sample(s, uv).r);\n"
"    if (kind == 1) return (float4(col.rgb, 1.0) * (t.a * col.a)) * cover;\n"
"    if (kind == 7) {\n"
"      // inked by how light what is under its glass is, looked at round the glass's middle\n"
"      float darkT = ad_sample(bd, ad_tex, g, I.pad.yz, I.pad.w * 0.5, false);\n"
"      float3 ink = mb_adaptive_ink(col.rgb, darkT);\n"
"      return (float4(ink, 1.0) * (t.a * col.a)) * cover;\n"
"    }\n"
"    return (t * col.a) * cover;\n"
"  }\n"
"  if (kind == 6) {\n"
"    // Copyright 2025, Tim Lehmann for whynotmake.it. Adapted from flutter_liquid_glass\n"
"    // liquid_glass_final_render_core.glsl, Apache-2.0.\n"
"    float k = I.pad.w;\n"
"    float4 s_rr = max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) > 0.0 ? I.rr : float4(I.p.x);\n"
"    float d;\n"
"    float halfMinor = 1e9;\n"
"    bool single_liquid = (one_kind == 13) || (k <= 0.0);\n"
"    if (single_liquid) {\n"
"      d = sd_rr(p, I.rect, s_rr);\n"
"      halfMinor = min(I.rect.z, I.rect.w) * 0.5;\n"
"    } else {\n"
"      d = 1e9;\n"
"      int n_sh = int(g.misc.x + 0.5);\n"
"      for (int i = 0; i < 8; i++) {\n"
"        if (i >= n_sh) break;\n"
"        float di = sd_rr(p, g.shape[i], g.rad[i]);\n"
"        float hi = min(g.shape[i].z, g.shape[i].w) * 0.5;\n"
"        if (i == 0) {\n"
"          d = di;\n"
"          halfMinor = hi;\n"
"        } else {\n"
"          float h = max(k - abs(d - di), 0.0) / k;\n"
"          float w = d < di ? 0.5 * h : 1.0 - 0.5 * h;\n"
"          d = min(d, di) - h * h * k * 0.25;\n"
"          halfMinor = mix(halfMinor, hi, w);\n"
"        }\n"
"      }\n"
"    }\n"
"    halfMinor = max(halfMinor, 1.0);\n"
"    float sd_px = -d * u.scale;\n"
"    float materialAlpha = clamp(sd_px + 0.5, 0.0, 1.0);\n"
"    float edgeW = 0.75 * u.scale;\n"
"    float outward = -sd_px;\n"
"    float ext_cov = mb_contour_int(max(outward + 0.5, 0.0), edgeW)\n"
"                  - mb_contour_int(max(outward - 0.5, 0.0), edgeW);\n"
"    if (materialAlpha < 0.01 && ext_cov < 0.01) discard_fragment();\n"
"    float regMix = smoothstep(0.105, 0.305, col.a);\n"
"    bool is_clear = (regMix <= 0.0);\n"
"    bool is_adaptive = I.c2.z < -0.5;\n"
"    float spot_raw = is_adaptive ? (-I.c2.z - 1.0) : I.c2.z;\n"
"    bool is_dark = (!is_clear && luma(col.rgb) < 0.35);\n"
"    float inward = max(-d, 0.0);\n"
"    float rawBevel = max(I.c2.y, 0.0);\n"
"    float rawAmount = max(I.pad.y, 0.0);\n"
"    float lensScale = min(1.0, halfMinor / max(rawBevel, 0.001));\n"
"    float clearBevel = rawBevel * lensScale;\n"
"    float clearAmount = rawAmount * lensScale;\n"
"    float regBevel = min(rawBevel, 0.5 * halfMinor);\n"
"    float regAmount = min(rawAmount, halfMinor);\n"
"    float bevel = mix(clearBevel, regBevel, regMix);\n"
"    float amount = mix(clearAmount, regAmount, regMix);\n"
"    float2 surfaceNormal = float2(0.0, 0.0);\n"
"    float shortening = 0.0;\n"
"    float2 disp = float2(0.0, 0.0);\n"
"    bool need_grad = (inward < max(bevel, 23.0)) || (ext_cov > 0.0);\n"
"    if (need_grad) {\n"
"      float e = 0.5;\n"
"      float2 grad = single_liquid\n"
"        ? float2(\n"
"            sd_rr(p + float2(e, 0.0), I.rect, s_rr) - sd_rr(p - float2(e, 0.0), I.rect, s_rr),\n"
"            sd_rr(p + float2(0.0, e), I.rect, s_rr) - sd_rr(p - float2(0.0, e), I.rect, s_rr)\n"
"          ) / (2.0 * e)\n"
"        : float2(\n"
"            sd_group(p + float2(e, 0.0), g, k) - sd_group(p - float2(e, 0.0), g, k),\n"
"            sd_group(p + float2(0.0, e), g, k) - sd_group(p - float2(0.0, e), g, k)\n"
"          ) / (2.0 * e);\n"
"      float gradLen = length(grad);\n"
"      surfaceNormal = gradLen > 0.0001 ? grad / gradLen : float2(0.0, 0.0);\n"
"      shortening = sqrt(clamp(gradLen, 0.0, 1.0));\n"
"      if (inward < bevel && bevel > 0.001 && amount > 0.0) {\n"
"        float bevelX = 1.0 - clamp(inward / bevel, 0.0, 1.0);\n"
"        float mag = amount * (1.0 - sqrt(max(1.0 - bevelX * bevelX, 0.0))) * shortening;\n"
"        disp = surfaceNormal * (-mag);\n"
"      }\n"
"    }\n"
"    float lensZoom = (I.p.w < 0.0) ? clamp(1.0 - I.p.w, 1.0, 3.0) : 1.0;\n"
"    float2 sampleBase = p;\n"
"    if (lensZoom > 1.0001) {\n"
"      float2 zoomC = single_liquid ? (I.rect.xy + I.rect.zw * 0.5) : ((g.gb.xy + g.gb.zw) * 0.5);\n"
"      sampleBase = zoomC + (p - zoomC) / lensZoom;\n"
"    }\n"
"    float3 refractColor;\n"
"    if (inward >= bevel || abs(I.pad.z) * amount * u.scale <= 0.25) {\n"
"      refractColor = backdrop(bd, g, sampleBase + disp);\n"
"    } else {\n"
"      float ds = I.pad.z * 0.5;\n"
"      refractColor = float3(\n"
"        backdrop(bd, g, sampleBase + disp * (1.0 + ds)).r,\n"
"        backdrop(bd, g, sampleBase + disp).g,\n"
"        backdrop(bd, g, sampleBase + disp * (1.0 - ds)).b\n"
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
"      transmittance = mix(1.0, 0.90, clearVeil);\n"
"      lift = mix(0.0, 0.10, clearVeil);\n"
"      chromaGain = mix(1.06, 1.0, clearVeil);\n"
"      contourStr = mix(0.24, 0.25, clearVeil);\n"
"      contourDirAmt = mix(0.85, 0.77, clearVeil);\n"
"      bevelShadowStr = mix(0.045, 0.04, clearVeil);\n"
"      glintLum = mix(1.6, 1.2, clearVeil);\n"
"      glintFaceGain = mix(0.0, 0.25, clearVeil);\n"
"      glintVib = mix(2.85, 1.5, clearVeil);\n"
"    } else if (is_adaptive) {\n"
"      float2 ac = single_liquid ? (I.rect.xy + I.rect.zw * 0.5) : ((g.gb.xy + g.gb.zw) * 0.5);\n"
"      float ar = (single_liquid ? max(min(I.rect.z, I.rect.w) * 0.5, 1.0) : max(min(g.gb.z - g.gb.x, g.gb.w - g.gb.y) * 0.5, 1.0)) * 0.5;\n"
"      float val = ad_sample(bd, ad_tex, g, ac, ar, is_dark);\n"
"      float baseDens = (col.a > 0.41) ? col.a : 0.30;\n"
"      if (is_dark) {\n"
"        float brightT = val;\n"
"        fogT = brightT;\n"
"        float dens = max(baseDens, mix(baseDens, 0.64, brightT));\n"
"        float extra = clamp((dens - 0.30) / (1.0 - 0.30), 0.0, 1.0);\n"
"        emission = mix(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);\n"
"        transmittance = mix(0.54, 0.0, extra);\n"
"        lift = mix(0.36, 0.0, extra);\n"
"        chromaGain = mix(0.92, 0.0, extra);\n"
"        contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;\n"
"        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
"      } else {\n"
"        float darkMix = val;\n"
"        fogT = darkMix;\n"
"        float extra = clamp((baseDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);\n"
"        float darkDens = max(baseDens, mix(baseDens, 0.52, darkMix));\n"
"        float darkExtra = clamp((darkDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);\n"
"        float3 lightEm = float3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * baseDens;\n"
"        float3 darkEm = mix(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), darkExtra);\n"
"        emission = mix(lightEm, darkEm, darkMix);\n"
"        transmittance = mix(mix(0.70, 0.0, extra), mix(0.54, 0.0, darkExtra), darkMix);\n"
"        lift = mix(mix(0.16, 0.0, extra), mix(0.36, 0.0, darkExtra), darkMix);\n"
"        chromaGain = mix(mix(1.18, 0.0, extra), mix(0.92, 0.0, darkExtra), darkMix);\n"
"        contourStr = mix(0.43, 0.88, darkMix);\n"
"        contourDirAmt = mix(0.77, 1.0, darkMix);\n"
"        bevelShadowStr = 0.036;\n"
"        glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
"      }\n"
"    } else if (is_dark) {\n"
"      float darkDens = (col.a > 0.41) ? col.a : 0.30;\n"
"      float extra = clamp((darkDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);\n"
"      emission = mix(float3(28.0 / 255.0, 28.0 / 255.0, 28.0 / 255.0), float3(34.0 / 255.0, 34.0 / 255.0, 34.0 / 255.0), extra);\n"
"      transmittance = mix(0.54, 0.0, extra);\n"
"      lift = mix(0.36, 0.0, extra);\n"
"      chromaGain = mix(0.92, 0.0, extra);\n"
"      contourStr = 0.88; contourDirAmt = 1.0; bevelShadowStr = 0.036;\n"
"      glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
"    } else {\n"
"      float lightDens = (col.a > 0.41) ? col.a : 0.30;\n"
"      float extra = clamp((lightDens - 0.30) / (1.0 - 0.30), 0.0, 1.0);\n"
"      emission = float3(253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0) * lightDens;\n"
"      transmittance = mix(0.70, 0.0, extra);\n"
"      lift = mix(0.16, 0.0, extra);\n"
"      chromaGain = mix(1.18, 0.0, extra);\n"
"      contourStr = 0.43; contourDirAmt = 0.77; bevelShadowStr = 0.036;\n"
"      glintLum = 1.6; glintFaceGain = 0.0; glintVib = 2.85;\n"
"    }\n"
"    if (regMix > 0.0 && regMix < 1.0) {\n"
"      emission = mix(float3(0.126, 0.126, 0.126), emission, regMix);\n"
"      transmittance = mix(0.90, transmittance, regMix);\n"
"      lift = mix(0.10, lift, regMix);\n"
"      chromaGain = mix(1.0, chromaGain, regMix);\n"
"      contourStr = mix(0.25, contourStr, regMix);\n"
"      contourDirAmt = mix(0.77, contourDirAmt, regMix);\n"
"      bevelShadowStr = mix(0.04, bevelShadowStr, regMix);\n"
"      glintLum = mix(1.2, glintLum, regMix);\n"
"      glintFaceGain = mix(0.25, glintFaceGain, regMix);\n"
"      glintVib = mix(1.5, glintVib, regMix);\n"
"    }\n"
"    if (fogT > 0.001) {\n"
"      float r1 = fogT * 2.6;\n"
"      float r2 = fogT * 3.6;\n"
"      float2 fc = sampleBase + disp;\n"
"      float3 fBlur = (refractColor * 2.0\n"
"        + (backdrop(bd, g, fc + float2(r1, 0.0)) + backdrop(bd, g, fc - float2(r1, 0.0))\n"
"         + backdrop(bd, g, fc + float2(0.0, r1)) + backdrop(bd, g, fc - float2(0.0, r1))) * 1.5\n"
"        + (backdrop(bd, g, fc + float2(r2, r2)) + backdrop(bd, g, fc + float2(-r2, r2))\n"
"         + backdrop(bd, g, fc + float2(r2, -r2)) + backdrop(bd, g, fc + float2(-r2, -r2)))) * (1.0 / 12.0);\n"
"      refractColor = mix(refractColor, fBlur, fogT);\n"
"    }\n"
"    float Y = luma(refractColor);\n"
"    float transLum = clamp(Y * (1.0 + lift * (1.0 - Y)), 0.0, 1.0);\n"
"    float3 transmittedColor = float3(transLum * transmittance) + (refractColor - float3(Y)) * (chromaGain * I.p.z);\n"
"    float3 baseColor = clamp(emission + transmittedColor, 0.0, 1.0);\n"
"    // Honor explicit chromatic tints (non-neutral) if a caller requests colored liquid glass\n"
"    float colChroma = max(max(col.r, col.g), col.b) - min(min(col.r, col.g), col.b);\n"
"    if (colChroma > 0.08 && col.a > 0.001) {\n"
"      baseColor = mix(baseColor, col.rgb, col.a * 0.5);\n"
"    }\n"
"    float spot = 0.0;\n"
"    if (spot_raw > 0.5) {\n"
"      float q = spot_raw - 1.0;\n"
"      float qx = floor(q * 0.000244140625);\n"
"      float qy = q - qx * 4096.0;\n"
"      float2 gp = I.rect.xy + float2(qx * 0.5 - 256.0, qy * 0.5 - 256.0);\n"
"      float gr = max(min(I.rect.z, I.rect.w) * 1.5, 64.0);\n"
"      spot = 1.0 - smoothstep(gr * 0.1, gr, length(p - gp));\n"
"      baseColor = clamp(baseColor + float3(0.08 * spot), 0.0, 1.0);\n"
"    }\n"
"    float2 rn = float2(0.0, 0.0);\n"
"    float tangency = 0.0;\n"
"    if (need_grad) {\n"
"      float2 la = g.misc.zw;\n"
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
"      float bevelDir = mix(1.0, wrappedFacing, 0.5);\n"
"      float bevelShadow = clamp(bevelLeading * bevelFalloff * bevelDir * bevelShadowStr, 0.0, 1.0);\n"
"      result = max(result - transmittedColor * bevelShadow, float3(0.0));\n"
"    }\n"
"    // (b) Glint (1.2pt ramp + 0.21 * 4.8pt bleed, both top & bottom walls, recolors face)\n"
"    if (I.c2.x > 0.01 && inward < 4.8) {\n"
"      float glintProfile = clamp(1.0 - inward / 1.2, 0.0, 1.0)\n"
"                         + 0.21 * clamp(1.0 - inward / 4.8, 0.0, 1.0);\n"
"      float lobe = max(1.0 - tangency, 0.0);\n"
"      float glint = clamp(I.c2.x * 0.252 * lobe * glintProfile + spot * 0.08 * glintProfile, 0.0, 1.0);\n"
"      float resLum = luma(result);\n"
"      float3 glintTarget = float3(glintLum) + result * glintFaceGain + (result - float3(resLum)) * glintVib;\n"
"      result = clamp(mix(result, glintTarget, glint), 0.0, 1.0);\n"
"    }\n"
"    result = clamp(result + mb_dither(p * u.scale) / 255.0, 0.0, 1.0);\n"
"    // (c) External 0.75pt dark contour (concentrated perpendicular to light axis where glint fades)\n"
"    float contourDir = mix(1.0, tangency, contourDirAmt);\n"
"    float extA = ext_cov * contourStr * contourDir * I.c2.w;\n"
"    float visA = materialAlpha * I.c2.w;\n"
"    return float4(result * visA, clamp(visA + extA, 0.0, 1.0)) * cover;\n"
"  }\n"
"  if (kind == 8) {\n"
"    // Foreground optical lens (View::content_lens): offscreen blurred child subtree refracted through spherical bevel & SDF-clipped\n"
"    float4 s_rr = max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) > 0.0 ? I.rr : float4(I.p.x);\n"
"    float d = sd_rr(p, I.rect, s_rr);\n"
"    float materialAlpha = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"    if (materialAlpha < 0.005) discard_fragment();\n"
"    float halfMinor = max(min(I.rect.z, I.rect.w) * 0.5, 1.0);\n"
"    float inward = max(-d, 0.0);\n"
"    float rawBevel = max(I.c2.y, 0.0);\n"
"    float rawAmount = max(I.c2.z, 0.0);\n"
"    float lensScale = min(1.0, halfMinor / max(rawBevel, 0.001));\n"
"    float bevel = rawBevel * lensScale;\n"
"    float amount = rawAmount * lensScale;\n"
"    float2 disp = float2(0.0, 0.0);\n"
"    if (inward < bevel && bevel > 0.001 && amount > 0.001) {\n"
"      float e = 0.5;\n"
"      float2 grad = float2(\n"
"        sd_rr(p + float2(e, 0.0), I.rect, s_rr) - sd_rr(p - float2(e, 0.0), I.rect, s_rr),\n"
"        sd_rr(p + float2(0.0, e), I.rect, s_rr) - sd_rr(p - float2(0.0, e), I.rect, s_rr)\n"
"      ) / (2.0 * e);\n"
"      float gradLen = length(grad);\n"
"      float2 surfaceNormal = gradLen > 0.0001 ? grad / gradLen : float2(0.0, 0.0);\n"
"      float shortening = sqrt(clamp(gradLen, 0.0, 1.0));\n"
"      float bevelX = 1.0 - clamp(inward / bevel, 0.0, 1.0);\n"
"      float mag = amount * (1.0 - sqrt(max(1.0 - bevelX * bevelX, 0.0))) * shortening;\n"
"      disp = surfaceNormal * (-mag);\n"
"    }\n"
"    float2 uv = (p + disp) * g.map.xy + g.map.zw;\n"
"    float4 fg = float4(0.0);\n"
"    if (uv.x >= g.uvc.x && uv.x <= g.uvc.z && uv.y >= g.uvc.y && uv.y <= g.uvc.w) {\n"
"      constexpr sampler sb(filter::linear, address::clamp_to_edge);\n"
"      fg = bd.sample(sb, uv);\n"
"    }\n"
"    return fg * (materialAlpha * col.a) * cover;\n"
"  }\n"
"  if (kind == 10) {\n"
"    // a piece of a line (scene.mbt): from c2.xy to c2.zw (shares of its rect), p.x half its width, its ends round\n"
"    float2 a = I.rect.xy + I.c2.xy * I.rect.zw, ab = I.rect.xy + I.c2.zw * I.rect.zw - a;\n"
"    float h = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-8), 0.0, 1.0);\n"
"    float d = length(p - a - ab * h) - I.p.x;\n"
"    if (I.pad.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(bd, ad_tex, g, I.pad.yz, I.pad.w * 0.5, false));\n"
"    return (float4(col.rgb, 1.0) * col.a * clamp(0.5 - d * u.scale, 0.0, 1.0)) * cover;\n"
"  }\n"
"  if (kind == 11) {\n"
"    // a band of a shape (src/ui/shape.mbt): c2.y of its pieces from c2.x, among those after every instance drawn\n"
"    // (kind 12, from instance u.pad on); p.x half its stroke's width (0: a fill, c2.z 1 by the even-odd rule)\n"
"    const device float4* sg = (const device float4*)inst;\n"
"    int first = int(I.c2.x + 0.5), n = int(I.c2.y + 0.5), base = int(u.pad + 0.5);\n"
"    float a;\n"
"    if (I.p.x > 0.0) {\n"
"      float d = 1e9;\n"
"      for (int i = first; i < first + n; i++) d = min(d, mb_seg_dist(sg[(base + i / 6) * 15 + mb_seg_slot(i)], I.rect, p));\n"
"      a = clamp(0.5 - (d - I.p.x) * u.scale, 0.0, 1.0);\n"
"    } else {\n"
"      float4 w = float4(0.0);\n"
"      for (int i = first; i < first + n; i++) w += mb_path_rows(sg[(base + i / 6) * 15 + mb_seg_slot(i)], I.rect, p, u.scale);\n"
"      a = mb_path_cover(w, I.c2.z);\n"
"    }\n"
"    if (I.pad.w > 0.0) col.rgb = mb_adaptive_ink(col.rgb, ad_sample(bd, ad_tex, g, I.pad.yz, I.pad.w * 0.5, false));\n"
"    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
"  }\n"
"  float2 hs = I.rect.zw * 0.5;\n"
"  float2 c = I.rect.xy + hs;\n"
"  // worked out as near the curve as its cover, its edge or its blur reaches\n"
"  float band = 1.0 + 2.0 / u.scale + (kind == 2 ? max(I.p.w, 0.5) : max(I.p.z, 0.0));\n"
"  // (its corner by p: rr, each its own)\n"
"  float rad = mb_corner_of(p - c, I.rr);\n"
"  float d = mb_sd_box(p - c, hs, rad, band);\n"
"  if (kind == 0 || kind == 5) d = notch_cut(d, p, I.rect, I.pad);\n"
"  if (kind == 9) { float rr = min(rad, min(hs.x, hs.y)); float2 q = abs(p - c) - hs + rr; if (length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - rr > 0.0) discard_fragment(); return (float4(0.0)) * cover; }\n"
"  if (kind == 4) {\n"
"    constexpr sampler si(filter::linear, address::clamp_to_edge);\n"
"    float2 uv = I.c2.xy + clamp((p - I.rect.xy) / I.rect.zw, 0.0, 1.0) * I.c2.zw;\n"
"    float4 pic = img.sample(si, clamp(uv, 0.0, 1.0));\n"
"    float edge = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"    if (I.pad.z > 0.5) {\n"
"      // Only picture edges inside the frame cut it; the frame's clip covers shared edges once.\n"
"      float2 size = I.rect.zw / I.c2.zw, lo = I.rect.xy - I.c2.xy * size, hi = lo + size;\n"
"      float2 a = lo - p, b = p - hi;\n"
"      if (I.c2.x >= 0.0) a.x = -1e9; if (I.c2.y >= 0.0) a.y = -1e9;\n"
"      if (I.c2.x + I.c2.z <= 1.0) b.x = -1e9; if (I.c2.y + I.c2.w <= 1.0) b.y = -1e9;\n"
"      float2 q = max(a, b);\n"
"      float pd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);\n"
"      pic *= I.pad.w * clamp(0.5 - pd * u.scale, 0.0, 1.0);\n"
"      pic += float4(col.rgb * I.pad.y, I.pad.y) * (1.0 - pic.a);\n"
"      if (I.rot.w < 0.5 && max(max(I.rr.x, I.rr.y), max(I.rr.z, I.rr.w)) <= 0.0 &&\n"
"          max(max(I.rc.x, I.rc.y), max(I.rc.z, I.rc.w)) > 0.0 &&\n"
"          all(I.clip.xy >= I.rect.xy) && all(I.clip.zw <= I.rect.xy + I.rect.zw)) edge = 1.0;\n"
"    }\n"
"    return (pic * (col.a * edge)) * cover;\n"
"  }\n"
"  if (kind == 2) {\n"
"    // as Core Animation's: the shape blurred, sigma its radius (corner.sl mb_shadow)\n"
"    float a = mb_shadow(p - c, hs, rad, max(I.p.w, 0.25));\n"
"    // glass's: only outside its box (c2.y above it)\n"
"    if (I.c2.x > 0.5) {\n"
"      float2 q = p - c + float2(0.0, I.c2.y);\n"
"      float db = mb_sd_box(q, hs, mb_corner_of(q, I.rr), band);\n"
"      a *= clamp(0.5 + db * u.scale, 0.0, 1.0);\n"
"    }\n"
"    return (float4(col.rgb, 1.0) * col.a * a) * cover;\n"
"  }\n"
"  float a = clamp(0.5 - d * u.scale, 0.0, 1.0);\n"
"  if (kind == 5) {\n"
"    // frosted: the blurred copy, saturated, the tint over it; the rim (a hairline inside the edge, the top left lit,\n"
"    // the foot and right less), 0.5 wide. Through (misc.y): as much of it as was a native view's hole left out (its\n"
"    // alpha), for the view's own frost under the canvas to show there\n"
"    float4 b4 = backdrop4(bd, g, p);\n"
"    float ps = prog_glass ? fade_r : 1.0;\n"
"    float ts = prog_glass ? (fade_r <= 0.0 ? 0.0 : pow(fade_r, 1.25)) : 1.0;\n"
"    float sat = prog_glass ? mix(1.0, I.p.z, ps) : I.p.z;\n"
"    float bg_diff = prog_glass ? smoothstep(0.22, 0.72, abs(luma(col.rgb) - luma(b4.rgb))) : 0.0;\n"
"    float base_a = prog_glass ? mix(col.a, min(0.86, col.a + 0.34), bg_diff) : col.a;\n"
"    float ta = prog_glass ? (base_a * ts) : col.a;\n"
"    float3 g3 = max(mix(float3(luma(b4.rgb)), b4.rgb, sat), 0.0);\n"
"    float ga = g.misc.y > 0.5 ? b4.a : 1.0;\n"
"    g3 = g3 * (1.0 - ta) + col.rgb * ta;\n"
"    ga = ga * (1.0 - ta) + ta;\n"
"    if (I.c2.x + I.c2.y + I.c2.z > 0.0) {\n"
"      float edge = clamp(0.5 + (d + 0.5) * u.scale, 0.0, 1.0);\n"
"      float lit = clamp(0.5 + notch_cut(sd_rr(p - 0.5, I.rect, I.rr), p - 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      float back = clamp(0.5 + notch_cut(sd_rr(p + 0.5, I.rect, I.rr), p + 0.5, I.rect, I.pad) * u.scale, 0.0, 1.0);\n"
"      float4 w4 = mix(float4(g3, ga), float4(1.0), I.c2.x * edge);\n"
"      w4 = mix(w4, float4(1.0), I.c2.y * lit);\n"
"      w4 = mix(w4, float4(1.0), I.c2.z * back);\n"
"      g3 = w4.rgb; ga = w4.a;\n"
"    }\n"
"    // dithered as it is written to 8 bits, so its slopes do not band (corner.sl mb_dither)\n"
"    g3 += mb_dither(p * u.scale) * ps / 255.0;\n"
"    float edge_a = prog_glass ? smoothstep(0.0, 0.04, fade_r) : 1.0;\n"
"    return (float4(g3, ga) * (a * I.c2.w * edge_a)) * cover;\n"
"  }\n"
"  float4 fill = float4(col.rgb, 1.0) * col.a;\n"
"  float bw = I.p.z;\n"
"  if (bw > 0.0) {\n"
"    float inner = clamp(0.5 - (d + bw) * u.scale, 0.0, 1.0);\n"
"    float4 bc = float4(I.c2.rgb, 1.0) * I.c2.a;\n"
"    fill = mix(bc, fill, inner);\n"
"  }\n"
"  return (fill * a) * cover;\n"
"}\n"
"// the flat pipeline: a ground's colour where it is covered whole, cut by straight clips alone (bands.h mb_pieces): what\n"
"// fmain writes there, nothing worked out\n"
"fragment float4 fflat(VOut in [[stage_in]], const device Inst* inst [[buffer(0)]]) {\n"
"  float4 col = inst[in.iid].color;\n"
"  return float4(col.rgb, 1.0) * col.a;\n"
"}\n"
"// The backdrop's passes: a.xy the source's texel, a.z 1 halving (dual Kawase's down), 2 a Gaussian along b.zw of\n"
"// deviation a.w (texels); b.xy the last texel's centre of what the source holds\n"
"struct PU { float4 a; float4 b; float4 map, box, rr, clip, rc, rs, outer, orc, ors; };\n"
"vertex float4 vpost(uint vid [[vertex_id]]) {\n"
"  float2 c = float2(vid == 1 ? 3.0 : -1.0, vid == 2 ? 3.0 : -1.0);\n"
"  return float4(c, 0.0, 1.0);\n"
"}\n"
"fragment float4 fcopy(float4 pos [[position]], texture2d<float, access::read> src [[texture(0)]]) {\n"
"  return src.read(uint2(pos.xy));\n"
"}\n"
"fragment float4 fpost(float4 pos [[position]], texture2d<float> src [[texture(0)]],\n"
"    texture2d<float> lv1 [[texture(1)]], texture2d<float> lv2 [[texture(2)]], texture2d<float> lv3 [[texture(3)]],\n"
"    constant PU& u [[buffer(0)]]) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 ts = u.a.xy;\n"
"  float2 lo = ts * 0.5, hi = u.b.xy;\n"
"  if (u.a.z > 3.5) {\n"
"    float2 p = u.map.xy + pos.xy * u.map.zw;\n"
"    float ramp = 1.0;\n"
"    if (u.box.y > 0.0) ramp *= clamp((p.y - u.box.x) / u.box.y, 0.0, 1.0);\n"
"    if (u.box.w > 0.0) ramp *= clamp((u.box.z - p.y) / u.box.w, 0.0, 1.0);\n"
"    if (u.rr.y > 0.0) ramp *= clamp((p.x - u.rr.x) / u.rr.y, 0.0, 1.0);\n"
"    if (u.rr.w > 0.0) ramp *= clamp((u.rr.z - p.x) / u.rr.w, 0.0, 1.0);\n"
"    float sp = max(u.clip.x, 1.0);\n"
"    float kf = u.clip.y;\n"
"    float4 m0 = u.rc, m1 = u.rs, m2 = u.outer, m3 = u.orc;\n"
"    if (kf < 0.5) return src.sample(s, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw));\n"
"    float r = clamp(ramp, 0.0, 1.0);\n"
"    if (r <= 0.0) return src.sample(s, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw));\n"
"    if (r >= 1.0) {\n"
"      int ki = int(kf + 0.5);\n"
"      if (ki <= 1) return lv1.sample(s, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw));\n"
"      if (ki == 2) return lv2.sample(s, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw));\n"
"      return lv3.sample(s, clamp(pos.xy * m3.xy, m3.xy * 4.0, m3.zw));\n"
"    }\n"
"    float sig1 = pow(sp, 1.0 / kf);\n"
"    float target_px = sp * pow(r, 1.15);\n"
"    if (target_px <= sig1 || kf <= 1.05) {\n"
"      float2 uv0_min = m0.xy * 0.5, uv0_max = m0.zw;\n"
"      float2 c_uv = pos.xy * m0.xy;\n"
"      float4 g_small;\n"
"      if (target_px <= 0.01) {\n"
"        g_small = src.sample(s, clamp(c_uv, uv0_min, uv0_max));\n"
"      } else if (target_px <= 0.55) {\n"
"        // Exact separable 3x3 Gaussian via 2x2 bilinear taps (center weight 0.5 split across +-o1)\n"
"        float inv2 = -0.5 / (target_px * target_px);\n"
"        float w1 = exp(inv2);\n"
"        float o1 = w1 / (0.5 + w1);\n"
"        float2 ox = float2(o1, 0.0) * m0.xy;\n"
"        float2 oy = float2(0.0, o1) * m0.xy;\n"
"        g_small = (src.sample(s, clamp(c_uv - ox - oy, uv0_min, uv0_max)) +\n"
"                   src.sample(s, clamp(c_uv + ox - oy, uv0_min, uv0_max)) +\n"
"                   src.sample(s, clamp(c_uv - ox + oy, uv0_min, uv0_max)) +\n"
"                   src.sample(s, clamp(c_uv + ox + oy, uv0_min, uv0_max))) * 0.25;\n"
"      } else {\n"
"        // Exact separable 7x7 Gaussian via 4x4 bilinear taps (zero gaps, zero comb ghosting)\n"
"        float inv2 = -0.5 / (target_px * target_px);\n"
"        float w1 = exp(inv2);\n"
"        float w2 = exp(4.0 * inv2);\n"
"        float w3 = exp(9.0 * inv2);\n"
"        float W1 = 0.5 + w1;\n"
"        float W2 = w2 + w3;\n"
"        float o1 = w1 / W1;\n"
"        float o2 = (2.0 * w2 + 3.0 * w3) / max(W2, 1e-6);\n"
"        float inv_sum = 0.5 / (W1 + W2);\n"
"        float p1 = W1 * inv_sum;\n"
"        float p2 = W2 * inv_sum;\n"
"        float ox[4] = {-o2, -o1, o1, o2};\n"
"        float pw[4] = {p2, p1, p1, p2};\n"
"        g_small = float4(0.0);\n"
"        for (int iy = 0; iy < 4; iy++) {\n"
"          float4 row = float4(0.0);\n"
"          float uy = clamp(c_uv.y + ox[iy] * m0.y, uv0_min.y, uv0_max.y);\n"
"          for (int ix = 0; ix < 4; ix++) {\n"
"            float ux = clamp(c_uv.x + ox[ix] * m0.x, uv0_min.x, uv0_max.x);\n"
"            row += src.sample(s, float2(ux, uy)) * pw[ix];\n"
"          }\n"
"          g_small += row * pw[iy];\n"
"        }\n"
"      }\n"
"      float blend_lo = min(1.1, sig1 * 0.45);\n"
"      float bt = clamp((target_px - blend_lo) / max(sig1 - blend_lo, 1e-4), 0.0, 1.0);\n"
"      float blend1 = bt > 0.0 ? pow(bt, 1.8) : 0.0;\n"
"      if (blend1 > 0.0) {\n"
"        float4 c_lv1 = lv1.sample(s, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw));\n"
"        return mix(g_small, c_lv1, blend1);\n"
"      }\n"
"      return g_small;\n"
"    }\n"
"    float lv_u = clamp(1.0 + (kf - 1.0) * log(target_px / sig1) / max(log(sp / sig1), 1e-4), 1.0, kf);\n"
"    int idx = min(int(floor(lv_u)), int(kf + 0.5) - 1);\n"
"    if (idx < 0) idx = 0;\n"
"    float f = lv_u - float(idx);\n"
"    float4 c0, c1;\n"
"    if (idx == 0) {\n"
"      c0 = src.sample(s, clamp(pos.xy * m0.xy, m0.xy * 0.5, m0.zw));\n"
"      c1 = lv1.sample(s, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw));\n"
"    } else if (idx == 1) {\n"
"      c0 = lv1.sample(s, clamp(pos.xy * m1.xy, m1.xy * 1.0, m1.zw));\n"
"      c1 = lv2.sample(s, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw));\n"
"    } else {\n"
"      c0 = lv2.sample(s, clamp(pos.xy * m2.xy, m2.xy * 2.0, m2.zw));\n"
"      c1 = lv3.sample(s, clamp(pos.xy * m3.xy, m3.xy * 4.0, m3.zw));\n"
"    }\n"
"    return mix(c0, c1, f);\n"
"  }\n"
"  if (u.a.z > 2.5) {\n"
"    float2 p = u.map.xy + pos.xy * u.map.zw;\n"
"    p = mb_contained_point(p, u.box, u.rr, u.clip, u.rc, u.rs, u.outer, u.orc, u.ors, u.map.z);\n"
"    return src.sample(s, clamp((p - u.map.xy) / u.map.zw * ts, lo, hi));\n"
"  }\n"
"  if (u.a.z < 1.5) {\n"
"    float2 uv = pos.xy * 2.0 * ts;\n"
"    float4 o = src.sample(s, clamp(uv, lo, hi)) * 4.0;\n"
"    o += src.sample(s, clamp(uv - ts, lo, hi));\n"
"    o += src.sample(s, clamp(uv + ts, lo, hi));\n"
"    o += src.sample(s, clamp(uv + float2(ts.x, -ts.y), lo, hi));\n"
"    o += src.sample(s, clamp(uv + float2(-ts.x, ts.y), lo, hi));\n"
"    return o / 8.0;\n"
"  }\n"
"  float2 uv = pos.xy * ts;\n"
"  float2 dir = u.b.zw * ts;\n"
"  float sg = u.a.w;\n"
"  float k = -0.5 / (sg * sg);\n"
"  float4 o = src.sample(s, clamp(uv, lo, hi));\n"
"  float wsum = 1.0;\n"
"  int n = int(ceil(sg * 3.0));\n"
"  for (int i = 1; i <= 64; i += 2) {\n"
"    if (i > n) break;\n"
"    float w1 = exp(float(i * i) * k), w2 = exp(float((i + 1) * (i + 1)) * k);\n"
"    float w = w1 + w2;\n"
"    float off = (float(i) * w1 + float(i + 1) * w2) / w;\n"
"    o += (src.sample(s, clamp(uv + dir * off, lo, hi)) + src.sample(s, clamp(uv - dir * off, lo, hi))) * w;\n"
"    wsum += 2.0 * w;\n"
"  }\n"
"  return o / wsum;\n"
"}\n"
"struct AdU { float4 map; float4 uvc; float4 box; float4 param; };\n"
"fragment float4 fad(float4 pos [[position]], texture2d<float> bd [[texture(0)]],\n"
"    texture2d<float> prev_ad [[texture(1)]], constant AdU& u [[buffer(0)]]) {\n"
"  constexpr sampler s(filter::linear, address::clamp_to_edge);\n"
"  float2 c = u.box.xy, h = u.box.zw;\n"
"  float sum = 0.0, mx1 = -1.0, mx2 = -1.0, mn1 = 2.0, mn2 = 2.0;\n"
"  for (int iy = -1; iy <= 1; iy++) {\n"
"    float py = c.y + float(iy) * (h.y * 0.60);\n"
"    for (int ix = -2; ix <= 2; ix++) {\n"
"      float px = c.x + float(ix) * (h.x * 0.38);\n"
"      float2 uv = clamp(float2(px, py) * u.map.xy + u.map.zw, u.uvc.xy, u.uvc.zw);\n"
"      float y = luma(bd.sample(s, uv).rgb);\n"
"      sum += y;\n"
"      if (y > mx1) { mx2 = mx1; mx1 = y; } else if (y > mx2) { mx2 = y; }\n"
"      if (y < mn1) { mn2 = mn1; mn1 = y; } else if (y < mn2) { mn2 = y; }\n"
"    }\n"
"  }\n"
"  float bgL = (sum - mx1 - mx2 - mn1 - mn2) / 11.0;\n"
"  uint sid = uint(u.param.w + 0.5);\n"
"  float4 prev = prev_ad.read(uint2(sid, 0));\n"
"  float prevT = mb_unpack16(prev.rg);\n"
"  float is_dark = u.param.x, is_new = u.param.y, dt = u.param.z;\n"
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
"    nextT = mix(prevT, target, 1.0 - exp(-dt / 0.070));\n"
"    if (abs(nextT - target) < 0.003) nextT = target;\n"
"  }\n"
"  return float4(mb_pack16(nextT), latch, clamp(bgL, 0.0, 1.0));\n"
"}\n";

// What draws by `frag` only instances of one kind (`kind`; -1 any).
static id<MTLRenderPipelineState> make_pipe(id<MTLLibrary> lib, MTLPixelFormat fmt, BOOL blend, NSString *frag,
                                            int kind) {
  MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
  d.vertexFunction = [lib newFunctionWithName:@"vmain"];
  MTLFunctionConstantValues *cv = [MTLFunctionConstantValues new];
  [cv setConstantValue:&kind type:MTLDataTypeInt atIndex:0];
  NSError *ferr = nil;
  d.fragmentFunction = [lib newFunctionWithName:frag constantValues:cv error:&ferr];
  if (!d.fragmentFunction) NSLog(@"%@ %d: %@", frag, kind, ferr);
  d.colorAttachments[0].pixelFormat = fmt;
  d.colorAttachments[0].blendingEnabled = blend;
  d.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
  d.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
  d.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  d.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
  NSError *err = nil;
  id<MTLRenderPipelineState> p = [dev newRenderPipelineStateWithDescriptor:d error:&err];
  if (!p) NSLog(@"pipeline: %@", err);
  return p;
}

// The kinds drawn by a pipeline of their own: the shader with its kind fixed (one_kind), so each is compiled to its
// kind's branch alone and a pixel of it is shaded with the registers that branch needs, not the most any kind's does.
// So a frame's GPU time on an M2 Max fell (2026-11-09, mbui-render's bench, after bands.h and what is covered left
// out: Home on Small 0.56 ms to 0.50, a chat on Large 0.43 to 0.37, a chat on Small 0.435 to 0.424), what it draws the
// same to the byte; the draws one for each run of a kind instead of each run of an image, which cost next to nothing
// (a hundred more, 0.01 ms). Rounded rects, glyphs,
// shadows, colour glyphs, images, lines, shapes' bands: what else there is (glass, a native view's hole) the pipeline
// for any kind draws. Made after the rest, on their own (kinds_made): until they are, that one draws every kind, the
// same pixels.
#define MB_KIND_LIQUID_SINGLE 13
#define MB_KINDS 14
static int has_own_pipe(int kind) {
  return (kind >= 0 && kind <= 8) || kind == 10 || kind == 11 || kind == MB_KIND_LIQUID_SINGLE;
}
static id<MTLRenderPipelineState> kpipe[MB_KINDS];
static dispatch_group_t kinds_made;
static int kinds_ready;

// The pipeline that draws a run of instances of `kind` where `p` would draw them all.
static id<MTLRenderPipelineState> kind_pipe(id<MTLRenderPipelineState> p, int kind) {
  if (p != mpipe || !has_own_pipe(kind)) return p;
  if (!kinds_ready) kinds_ready = dispatch_group_wait(kinds_made, DISPATCH_TIME_NOW) == 0;
  return kinds_ready && kpipe[kind] ? kpipe[kind] : p;
}

// An atlas `side` texels square: the words' a byte a texel, colour glyphs' four.
static id<MTLTexture> atlas_texture(int color, int side) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:color ? MTLPixelFormatRGBA8Unorm : MTLPixelFormatR8Unorm
                                   width:(NSUInteger)side
                                  height:(NSUInteger)side
                               mipmapped:NO];
  td.usage = MTLTextureUsageShaderRead;
  return [dev newTextureWithDescriptor:td];
}

// The device, the shaders compiled and the pipelines made: what drawing needs whatever it draws into, on a queue of its
// own from as the program loads (prepare, below), so that compiling the shaders (most of a start's time before its
// window, as AppKit waited on Metal's compiler: 2026-10-27) goes on while the program starts and AppKit makes the app
// and its window; what is drawn into waits for it only as it is made (mb_render_init).
static dispatch_group_t prepared;

static void prepare_gpu(void) {
  dev = MTLCreateSystemDefaultDevice();
  queue = [dev newCommandQueue];
  NSError *err = nil;
  id<MTLLibrary> lib = [dev newLibraryWithSource:shader_src options:nil error:&err];
  if (!lib) NSLog(@"shader: %@", err);
  mpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm, YES, @"fmain", -1);
  hpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm, NO, @"fmain", -1);
  fpipe = make_pipe(lib, MTLPixelFormatBGRA8Unorm, YES, @"fflat", -1);
  rpipe_off = mpipe;
  MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
  pd.vertexFunction = [lib newFunctionWithName:@"vpost"];
  pd.fragmentFunction = [lib newFunctionWithName:@"fpost"];
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  ppipe = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
  if (!ppipe) NSLog(@"post pipeline: %@", err);
  pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
  ppipe_deep = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
  if (!ppipe_deep) NSLog(@"post pipeline: %@", err);
  MTLRenderPipelineDescriptor *cd = [MTLRenderPipelineDescriptor new];
  cd.vertexFunction = [lib newFunctionWithName:@"vpost"];
  cd.fragmentFunction = [lib newFunctionWithName:@"fcopy"];
  cd.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
  cpipe = [dev newRenderPipelineStateWithDescriptor:cd error:&err];
  if (!cpipe) NSLog(@"copy pipeline: %@", err);
  MTLRenderPipelineDescriptor *ad = [MTLRenderPipelineDescriptor new];
  ad.vertexFunction = [lib newFunctionWithName:@"vpost"];
  ad.fragmentFunction = [lib newFunctionWithName:@"fad"];
  ad.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
  adpipe = [dev newRenderPipelineStateWithDescriptor:ad error:&err];
  if (!adpipe) NSLog(@"adaptive pipeline: %@", err);
  atlas = atlas_texture(0, MB_ATLAS_SIDE);
  catlas = atlas_texture(1, MB_ATLAS_COLOR_SIDE);
  inflight = dispatch_semaphore_create(3);
  dispatch_group_async(kinds_made, dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    for (int k = 0; k < MB_KINDS; k++)
      if (has_own_pipe(k)) kpipe[k] = make_pipe(lib, MTLPixelFormatBGRA8Unorm, YES, @"fmain", k);
  });
}

__attribute__((constructor)) static void prepare(void) {
  present_q = dispatch_queue_create("mbui.present", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                                           QOS_CLASS_USER_INTERACTIVE, 0));
  prepared = dispatch_group_create();
  kinds_made = dispatch_group_create();
  dispatch_group_async(prepared, dispatch_get_global_queue(QOS_CLASS_USER_INTERACTIVE, 0), ^{ prepare_gpu(); });
}

void mb_render_init(CAMetalLayer *layer) {
  dispatch_group_wait(prepared, DISPATCH_TIME_FOREVER);
  mlayer = layer;
  layer.device = dev;
  layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
  // frames are drawn into canvas (where glass copies out what is drawn so far) and copied into the drawable by a
  // render pass, so the drawable needs no shader read or blit and keeps lossless framebuffer compression
  layer.framebufferOnly = YES;
  // opaque while no native view's hole shows through the canvas (glass_through); cleared only on frames with holes
  layer.opaque = YES;
}

id<MTLDevice> mb_render_device(void) {
  dispatch_group_wait(prepared, DISPATCH_TIME_FOREVER);
  return dev;
}

void mb_render_set_size(double w, double h, double scale) {
  vw = w;
  vh = h;
  vscale = scale;
  CGSize want = CGSizeMake(round(w * scale), round(h * scale));
  if (!CGSizeEqualToSize(mlayer.drawableSize, want)) {
    // (not while the queue may be asking the layer for a drawable)
    present_drain();
    mlayer.drawableSize = want;
    shown_ok = 0;
  }
}

// A glyph's pixels for an atlas, kept to be put in before the next frame drawn (atlas_puts, above).
void mb_atlas_upload(int color, int x, int y, int w, int h, const void *px) {
  if (w <= 0 || h <= 0) return;
  size_t n = (size_t)w * h * (color ? 4 : 1);
  uint8_t *copy = malloc(n);
  memcpy(copy, px, n);
  os_unfair_lock_lock(&present_mu);
  if (atlas_puts_head > 0 && atlas_puts_head == atlas_puts_n) atlas_puts_head = atlas_puts_n = 0;
  if (atlas_puts_n == atlas_puts_cap) {
    if (atlas_puts_head > 0) {
      memmove(atlas_puts, atlas_puts + atlas_puts_head, (atlas_puts_n - atlas_puts_head) * sizeof *atlas_puts);
      atlas_puts_n -= atlas_puts_head;
      atlas_puts_head = 0;
    }
    if (atlas_puts_n == atlas_puts_cap) {
      atlas_puts_cap = atlas_puts_cap ? atlas_puts_cap * 2 : 64;
      atlas_puts = realloc(atlas_puts, atlas_puts_cap * sizeof *atlas_puts);
    }
  }
  atlas_puts[atlas_puts_n++] = (AtlasPut){++atlas_seq, color, x, y, w, h, copy};
  os_unfair_lock_unlock(&present_mu);
}

// The glyphs kept put into the atlases, in order, those numbered up to `upto`.
static void atlas_flush(uint64_t upto) {
  for (;;) {
    os_unfair_lock_lock(&present_mu);
    AtlasPut p = {0};
    int has = atlas_puts_head < atlas_puts_n && atlas_puts[atlas_puts_head].seq <= upto;
    if (has) p = atlas_puts[atlas_puts_head++];
    os_unfair_lock_unlock(&present_mu);
    if (!has) return;
    [(p.color ? catlas : atlas) replaceRegion:MTLRegionMake2D(p.x, p.y, p.w, p.h) mipmapLevel:0 withBytes:p.px
                                 bytesPerRow:(NSUInteger)p.w * (p.color ? 4 : 1)];
    free(p.px);
  }
}

// ---------------------------------------------------------------------------
// Glass: when the instances reach a run of glass (slot 20 negative: the capture it shares), what is drawn so far
// under it (its rects with room for the blur round them) is copied out, halved down to where the blur is a few texels
// wide (dual Kawase's downsample, at most 1/8), blurred there by a Gaussian of what deviation is left, and drawn
// through. Level 0, the copy, has 8 bits a channel as the target has; what the passes write keeps more (half floats,
// its alpha too: how much of it was a native view's hole, glass_through): at 8 each pass rounds the frost's slow
// slopes into flat steps, a texel of the last level 8 pixels wide on the screen (a blur under 4 pixels, too narrow to
// halve, is written back into the copy: it leaves no slope that wide).

typedef struct { float map[4]; float uvc[4]; float gb[4]; float shape[8][4]; float rad[8][4]; float misc[4]; float ad_box[MB_ADAPTIVE_MAX][4]; float ad_meta[4]; } GU;
static GU gu;
static id<MTLTexture> gtex;  // the blurred copy the glass in view shows

static id<MTLTexture> level_tex(MTLPixelFormat format, int w, int h) {
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:format width:(NSUInteger)(w > 0 ? w : 1)
                                  height:(NSUInteger)(h > 0 ? h : 1) mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  return [dev newTextureWithDescriptor:td];
}

// the last capture's blur is kept to be shown again (encode, below)
static int kept_ok;
static void slots_invalidate(void);
static void slots_drop_textures(void);
static void glass_forget(void);

static void ensure_levels(int w, int h) {
  if (lv_w >= w && lv_h >= h && lv[0]) return;
  lv_w = w > lv_w ? w : lv_w;
  lv_h = h > lv_h ? h : lv_h;
  for (int j = 0; j < 4; j++)
    lv[j] = level_tex(j == 0 ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA16Float, (lv_w + (1 << j) - 1) >> j,
                      (lv_h + (1 << j) - 1) >> j);
  ltmp = level_tex(MTLPixelFormatRGBA16Float, lv_w, lv_h);
  lv_shrink_frames = 0;
  lv_win_max_w = lv_win_max_h = 0;
  lv_frame_max_w = lv_frame_max_h = 0;
  // (the blurs kept were shown by where they lie in levels of the old size: one made now would be shown by the new)
  slots_invalidate();
  slots_drop_textures();
}

// one pass of the blur: src into dst's top left (w × h); mode 1 halving, 2 a Gaussian of deviation sg along (dx, dy)
static void post_pass(id<MTLCommandBuffer> cb, id<MTLTexture> src, int sw, int sh, id<MTLTexture> dst, int w, int h,
                      int mode, float sg, float dx, float dy, const MBContained *edge, const MTLScissorRect *sc_rect) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = dst;
  rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:dst.pixelFormat == MTLPixelFormatRGBA16Float ? ppipe_deep : ppipe];
  [e setViewport:(MTLViewport){0, 0, (double)w, (double)h, 0, 1}];
  [e setScissorRect:sc_rect ? *sc_rect : (MTLScissorRect){0, 0, (NSUInteger)w, (NSUInteger)h}];
  float tw = 1.0f / (float)src.width, th = 1.0f / (float)src.height;
  struct { float a[4]; float b[4]; MBContained edge; } u = {{tw, th, (float)mode, sg}, {((float)sw - 0.5f) * tw, ((float)sh - 0.5f) * th, dx, dy}, {0}};
  if (edge) u.edge = *edge;
  [e setFragmentBytes:&u length:sizeof u atIndex:0];
  [e setFragmentTexture:src atIndex:0];
  [e setFragmentTexture:(mode == 4 ? lv[1] : src) atIndex:1];
  [e setFragmentTexture:(mode == 4 ? lv[2] : src) atIndex:2];
  [e setFragmentTexture:(mode == 4 ? lv[3] : src) atIndex:3];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e endEncoding];
}

// Glass over a native view (a page, a video: under the canvas, seen through its hole) frosts what the view shows too.
// The canvas holds none of it (a hole is nothing in it), so that part of the frost is Core Animation's: a backdrop
// over the views, under the canvas (apple_views.m mb_views_frost), each the shape of a glass instance, blurred and
// saturated as the glass is; the canvas's glass leaves out as much of its frost as was the hole (its copy's alpha,
// gu.misc.y), for that to show there. The captures that do (their slot 20, through_tid), found as a frame is
// presented; none in a frame drawn otherwise (offscreen, read back, a snapshot: no views under it).
#define MB_HOLES 32
static int through_n;
static float through_tid[MB_THROUGH];
// (those of the frame being drawn: its MBFrame's, or the main thread's as it draws one itself; none read back)
static int at_through_n;
static float at_through_tid[MB_THROUGH];

static int in_through(const float *tids, int n, float tid) {
  for (int i = 0; i < n; i++)
    if (tids[i] == tid) return 1;
  return 0;
}

static int is_through(float tid) { return in_through(through_tid, through_n, tid); }

// what of instance b shows: its rect cut by its clip's (x0 y0 x1 y1); 0 when nothing does
static int shows_of(const float *b, float r[4]) {
  r[0] = fmaxf(b[0], b[16]); r[1] = fmaxf(b[1], b[17]);
  r[2] = fminf(b[0] + b[2], b[18]); r[3] = fminf(b[1] + b[3], b[19]);
  return r[2] > r[0] && r[3] > r[1];
}

// The frame's frosted glass over holes (kind 9) painted before it: its captures through, and every instance of them
// a backdrop over the views whose holes were painted before it (the last of them: `under`), at that view's place
// among them. Told to the views (which say whether they can frost: else none is through, the glass as before).
// Returns whether any hole shows in this frame.
static int glass_through(const float *f, int32_t count) {
  // Instances are in content points; the system views underneath are placed in window points.
  double zoom = mlayer && mlayer.contentsScale > 0 ? vscale / mlayer.contentsScale : 1.0;
  float holes[MB_HOLES][4];
  int nh = 0, has_hole = 0;
  through_n = 0;
  for (int32_t i = 0; i < count; i++) {
    const float *b = f + i * MB_INST;
    int kind = (int)(b[5] + 0.5f);
    float r[4];
    if (kind == 9) {
      if (shows_of(b, r)) {
        has_hole = 1;
        if (nh < MB_HOLES) memcpy(holes[nh++], r, sizeof r);
      }
      continue;
    }
    if (kind != 5 || b[22] < -0.5f || b[20] >= 0 || !nh || through_n >= MB_THROUGH || is_through(b[20]) || !shows_of(b, r))
      continue;
    // (its blur reaches a hole near it too)
    float m = 3.0f * fabsf(b[7]);
    for (int h = 0; h < nh; h++)
      if (holes[h][0] < r[2] + m && r[0] - m < holes[h][2] && holes[h][1] < r[3] + m && r[1] - m < holes[h][3]) {
        through_tid[through_n++] = b[20];
        break;
      }
  }
  double frosts[MB_FROSTS * MB_FROST_N];
  int n = 0;
  int32_t under = 0;
  for (int32_t i = 0; i < count && through_n; i++) {
    const float *b = f + i * MB_INST;
    int kind = (int)(b[5] + 0.5f);
    if (kind == 9) under = (int32_t)(b[20] + 0.5f) - MB_VIEW_TEX;
    float r[4];
    if (kind != 5 || b[22] < -0.5f || !is_through(b[20]) || under <= 0 || n >= MB_FROSTS || !shows_of(b, r)) continue;
    double *e = frosts + n++ * MB_FROST_N;
    for (int k = 0; k < 4; k++) {
      e[k] = r[k] * zoom;
      e[4 + k] = b[k] * zoom;
      e[8 + k] = b[36 + k] * zoom;
    }
    e[12] = fabs(b[7]) * zoom;
    e[13] = b[6];
    e[14] = b[15];
    e[15] = under;
  }
  if (!mb_views_frost(n, frosts)) through_n = 0;
  return has_hole;
}

// What a capture of glass is of, worked out before any of the GPU's work: its rectangle in the target's pixels, how
// many times it is halved (k, at most 3) and the Gaussian left after (sg), and the glass's own numbers (gu's but map
// and uvc, which follow from these and the level's size). Zeroed whole first, so two of the same compare the same.
typedef struct {
  int px0, py0, w, h, k, contained, progressive;
  int vis_x, vis_y, vis_w, vis_h;
  float sg, sp;
  float fade[4], fadex[4];
  GU g;
  MBContained edge;
} Grab;

// The capture the run [start, end) of glass makes, of a target tw × th pixels; 0 when none of it shows.
// Frosted glass of the same capture further on (glass.mbt shares_capture) is under it too.
static int grab_of(Grab *m, const float *f, int32_t start, int32_t end, int32_t count, int tw, int th) {
  memset(m, 0, sizeof *m);
  const float *a = f + start * MB_INST;
  // For frosted glass (kind 5), negative slot 7 is contained; for liquid glass (kind 6), negative slot 7 encodes clear-lens zoom.
  int kind = (int)(a[5] + 0.5f);
  int is_contained = (kind == 5 && a[7] < 0.0f);
  int is_progressive = (kind == 5 && a[22] < -0.5f);
  float blur = (kind == 6 && a[7] < 0.0f) ? 0.0f : fabsf(a[7]);
  int merged_liquid = (kind == 6 && a[23] > 0.0f);
  int unmerged_liquid = (kind == 6 && !merged_liquid);
  float margin = is_contained ? 0.0f : 3.0f * blur + (kind == 6 ? a[21] * (1.0f + fabsf(a[22])) + fmaxf(a[23], 0.0f) : 0.0f) + 2.0f;
  float x0 = 1e9f, y0 = 1e9f, x1 = -1e9f, y1 = -1e9f;
  int n = 0;
  for (int32_t i = start; i < end; i++) {
    const float *b = f + i * MB_INST;
    // what of it shows: its clip
    float bx0 = fmaxf(b[0], b[16]), by0 = fmaxf(b[1], b[17]);
    float bx1 = fminf(b[0] + b[2], b[18]), by1 = fminf(b[1] + b[3], b[19]);
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
        float bm = 3.0f * blur + b[21] * (1.0f + fabsf(b[22])) + m23 + 2.0f;
        if (bm > margin) margin = bm;
      }
    }
    x0 = fminf(x0, bx0); y0 = fminf(y0, by0); x1 = fmaxf(x1, bx1); y1 = fmaxf(y1, by1);
  }
  if (kind == 5 || unmerged_liquid) {
    for (int32_t i = end; i < count; i++) {
      const float *b = f + i * MB_INST;
      if (b[20] != a[20]) continue;
      if (unmerged_liquid) {
        float m23 = fmaxf(b[23], 0.0f);
        x0 = fminf(x0, b[0] - m23); y0 = fminf(y0, b[1] - m23);
        x1 = fmaxf(x1, b[0] + b[2] + m23); y1 = fmaxf(y1, b[1] + b[3] + m23);
        {
          float bm = 3.0f * blur + b[21] * (1.0f + fabsf(b[22])) + m23 + 2.0f;
          if (bm > margin) margin = bm;
        }
      } else {
        x0 = fminf(x0, fmaxf(b[0], b[16])); y0 = fminf(y0, fmaxf(b[1], b[17]));
        x1 = fmaxf(x1, fminf(b[0] + b[2], b[18])); y1 = fmaxf(y1, fminf(b[1] + b[3], b[19]));
      }
    }
  }
  m->g.misc[0] = (float)n;
  m->g.misc[1] = in_through(at_through_tid, at_through_n, a[20]) ? 1.0f : 0.0f;
  m->g.gb[0] = x0 - 2; m->g.gb[1] = y0 - 2; m->g.gb[2] = x1 + 2; m->g.gb[3] = y1 + 2;
  float sc = (float)at_scale;
  int px0 = (int)floorf((x0 - margin) * sc), py0 = (int)floorf((y0 - margin) * sc);
  int px1 = (int)ceilf((x1 + margin) * sc), py1 = (int)ceilf((y1 + margin) * sc);
  if (px0 < 0) px0 = 0;
  if (py0 < 0) py0 = 0;
  if (px1 > tw) px1 = tw;
  if (py1 > th) py1 = th;
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
  // down to where the deviation is 2 texels or more, at most 1/8
  float sp = blur * sc;
  int k = 0;
  while (k < 3 && sp / (float)(1 << (k + 1)) >= 2.0f) k++;
  m->sp = sp;
  if (is_progressive && k == 0 && sp > 0.5f) k = 1;
  // what is left of the deviation once the halvings' and the last look's (bilinear) spread are taken out
  float sk = sp / (float)(1 << k);
  float pre = k > 0 ? 0.75f * (1.0f - powf(0.25f, (float)k)) / 3.0f + 1.0f / 6.0f : 0.0f;
  m->k = k;
  m->sg = sqrtf(fmaxf(sk * sk - pre, 0.0f));
  return 1;
}

// The size of a grab's level k (its passes write each level's top left)
static void grab_levels(const Grab *m, int lw[4], int lh[4]) {
  lw[0] = m->w; lh[0] = m->h;
  for (int j = 1; j <= 3; j++) {
    lw[j] = (lw[j - 1] + 1) / 2;
    lh[j] = (lh[j - 1] + 1) / 2;
  }
}

static float g_light_angle = 0.0f;

static void grab_map_uvc(const Grab *m, id<MTLTexture> bt, float map[4], float uvc[4]) {
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  int sk = m->progressive ? 0 : m->k;
  float sc = (float)at_scale;
  float W = (float)bt.width, H = (float)bt.height, d = (float)(1 << sk);
  map[0] = sc / d / W; map[1] = sc / d / H;
  map[2] = -(float)m->px0 / d / W; map[3] = -(float)m->py0 / d / H;
  if (m->progressive) {
    uvc[0] = ((float)m->vis_x + 0.5f) / W;
    uvc[1] = ((float)m->vis_y + 0.5f) / H;
    uvc[2] = ((float)(m->vis_x + m->vis_w) - 0.5f) / W;
    uvc[3] = ((float)(m->vis_y + m->vis_h) - 0.5f) / H;
  } else {
    uvc[0] = 0.5f / W; uvc[1] = 0.5f / H;
    uvc[2] = ((float)lw[sk] - 0.5f) / W; uvc[3] = ((float)lh[sk] - 0.5f) / H;
  }
}

// What the glass shows of a grab's blur in texture `bt` (level k's place in it): gtex and gu, its numbers with where
// in it it is.
static void show_blur(const Grab *m, id<MTLTexture> bt) {
  gu = m->g;
  gu.misc[2] = cosf(g_light_angle);
  gu.misc[3] = sinf(g_light_angle);
  gtex = bt;
  grab_map_uvc(m, bt, gu.map, gu.uvc);
}

// The level a grab's blur is left in.
static id<MTLTexture> grab_blurred(const Grab *m) { return (m->progressive || (m->contained && m->k == 0)) ? ltmp : lv[m->k]; }

// A grab of target blurred into the levels: what is drawn so far in its rectangle copied out, halved k times, the
// Gaussian left (passes of their own, the target's pass ended before; grab_blurred). The levels are shared by every
// capture: what is shown is the copy a slot keeps (below).
// (how many: scripts/apple_render_test.m, a blur shown again as kept is none)
static int blurs_made;

static void blur(id<MTLCommandBuffer> cb, id<MTLTexture> target, const Grab *m) {
  blurs_made++;
  ensure_levels(m->w, m->h);
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl copyFromTexture:target sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(m->px0, m->py0, 0)
           sourceSize:MTLSizeMake(m->w, m->h, 1) toTexture:lv[0] destinationSlice:0 destinationLevel:0
    destinationOrigin:MTLOriginMake(0, 0, 0)];
  [bl endEncoding];
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  int k = m->k;
  if (m->progressive) {
    float prev_var = 0.0f;
    for (int j = 1; j <= k; j++) {
      post_pass(cb, lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0, NULL, NULL);
      float target_px = powf(fmaxf(m->sp, 1.0f), (float)j / (float)k);
      float have_var = prev_var + 0.75f * (float)(1 << (2 * j - 2));
      float need_var = fmaxf(target_px * target_px - have_var, 0.0f);
      float sg_j = sqrtf(need_var) / (float)(1 << j);
      if (sg_j > 0.3f) {
        post_pass(cb, lv[j], lw[j], lh[j], ltmp, lw[j], lh[j], 2, sg_j, 1, 0, NULL, NULL);
        post_pass(cb, ltmp, lw[j], lh[j], lv[j], lw[j], lh[j], 2, sg_j, 0, 1, NULL, NULL);
      }
      prev_var = fmaxf(have_var, target_px * target_px);
    }
    float sc = (float)at_scale;
    MBContained prog;
    memset(&prog, 0, sizeof prog);
    prog.map[0] = (float)m->px0 / sc; prog.map[1] = (float)m->py0 / sc;
    prog.map[2] = 1.0f / sc; prog.map[3] = 1.0f / sc;
    for (int i = 0; i < 4; i++) { prog.box[i] = m->fade[i]; prog.rr[i] = m->fadex[i]; }
    prog.clip[0] = m->sp; prog.clip[1] = (float)k;
    float *ms[4] = {prog.rc, prog.rs, prog.outer, prog.orc};
    for (int j = 0; j < 4; j++) {
      float dj = (float)(1 << j), tw = (float)lv[j].width, th = (float)lv[j].height;
      ms[j][0] = 1.0f / (dj * tw); ms[j][1] = 1.0f / (dj * th);
      ms[j][2] = ((float)lw[j] - 0.5f) / tw; ms[j][3] = ((float)lh[j] - 0.5f) / th;
    }
    MTLScissorRect sc_vis = {(NSUInteger)m->vis_x, (NSUInteger)m->vis_y, (NSUInteger)m->vis_w, (NSUInteger)m->vis_h};
    post_pass(cb, lv[0], lw[0], lh[0], ltmp, lw[0], lh[0], 4, 0, 0, 0, &prog, &sc_vis);
    return;
  }
  if (m->contained) post_pass(cb, lv[0], lw[0], lh[0], ltmp, lw[0], lh[0], 3, 0, 0, 0, &m->edge, NULL);
  for (int j = 1; j <= k; j++) post_pass(cb, j == 1 && m->contained ? ltmp : lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0, NULL, NULL);
  if (m->sg > 0.3f) {
    id<MTLTexture> from = grab_blurred(m);
    id<MTLTexture> tmp = m->contained && k == 0 ? lv[0] : ltmp;
    post_pass(cb, from, lw[k], lh[k], tmp, lw[k], lh[k], 2, m->sg, 1, 0, NULL, NULL);
    post_pass(cb, tmp, lw[k], lh[k], from, lw[k], lh[k], 2, m->sg, 0, 1, NULL, NULL);
  }
}

// The blurs kept, a slot each, as many as a window has groups of glass at once (a bar at the top, a composer and its
// ground at the foot, a sheet's, a page sliding over another: 2 to 6), the one least lately shown taken for a new one
// (gles_render.h's, GLES's). A slot holds a capture's blur copied out of the levels,
// as big as the levels (so it is shown by the same numbers as the level it came from, to the byte), and what it was
// of. What a capture copies is what the frame drew before it in the grab's rectangle (the instances up to the glass
// that reach into it, the pieces of the frame's shapes they are drawn by, the ground the frame cleared to) of a target
// of that size: a frame that draws all that the same under the same glass (a caret blinking in a composer over a chat
// at rest) shows the blur as it is, with no copy, no passes, and its pass not broken in two; one where something moved
// under one group of glass makes that group's blur again, the others' kept. A stream or a native view's hole drawn
// into it (its pictures change under the same instances) is blurred anew each frame, as is a frame an image under it
// had no texture for yet.
#define MB_GLASS_SLOTS 32
#define MB_GLASS_CACHE_MAX_BYTES ((size_t)64 * 1024 * 1024)
typedef struct {
  float *under;
  size_t under_cap, under_n;
  int32_t whole, picked;
  Grab grab;
  double key[7];
  int valid;
  unsigned used;
  unsigned gen;
} GlassSlot;
static GlassSlot slots[MB_GLASS_SLOTS];
static id<MTLTexture> slot_bt[MB_GLASS_SLOTS];
static unsigned slots_clock;
static unsigned slots_gen;

static size_t glass_tex_bytes(id<MTLTexture> t) {
  if (!t) return 0;
  size_t bpp = t.pixelFormat == MTLPixelFormatRGBA16Float ? 8 : 4;
  return (size_t)t.width * (size_t)t.height * bpp;
}

static size_t slots_total_bytes(void) {
  size_t total = 0;
  for (int i = 0; i < MB_GLASS_SLOTS; i++) total += glass_tex_bytes(slot_bt[i]);
  return total;
}
// what the capture now is of (under_take), as a slot keeps it
static float *under_now;
static size_t under_now_cap, under_now_n;
static int32_t under_whole, under_picked;

static MBRenderWin *at_win;

static void ad_forget(MBRenderWin *w) {
  if (!w) return;
  memset(w->ad_slots, 0, sizeof w->ad_slots);
  w->ad_last_time = 0.0;
  w->ad_track_mask = 0;
  w->ad_rb_prev_copied = 0;
  for (int i = 0; i < MB_ADAPTIVE_MAX; i++) atomic_store(&w->ad_conv_serial[i], 0);
  atomic_store(&w->ad_settling, 0);
  atomic_store(&w->ad_drawing, 0);
  atomic_store(&w->ad_has_adaptive, 0);
  os_unfair_lock_lock(&present_mu);
  w->ad_settle_dirty = (MBDirty){0};
  os_unfair_lock_unlock(&present_mu);
}

static void ensure_ad_tex(MBRenderWin *w) {
  if (!w || w->ad_tex[0]) return;
  for (int i = 0; i < 2; i++) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                  width:MB_ADAPTIVE_MAX
                                                                                 height:1
                                                                              mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    td.storageMode = MTLStorageModePrivate;
    w->ad_tex[i] = [dev newTextureWithDescriptor:td];
  }
  for (int i = 0; i < 3; i++) {
    if (!w->ad_rb[i]) w->ad_rb[i] = [dev newBufferWithLength:MB_ADAPTIVE_MAX * 4 * 2 options:MTLResourceStorageModeShared];
  }
  w->ad_cur = 0;
}

static void ad_fill_gu(MBRenderWin *w) {
  if (!w) {
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

typedef struct {
  int sid;
  int is_new;
  int is_dark;
  float cx, cy, hx, hy;
} AdPending;

static int ad_collect_and_match(MBRenderWin *w, const float *f, int32_t start, int32_t end, int32_t count,
                                const Grab *m, int backdrop_changed, double dt, uint64_t serial,
                                AdPending out[MB_ADAPTIVE_MAX]) {
  if (!w || dt < 0.0) return 0;
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
      items[ni].cx = (m->g.gb[0] + m->g.gb[2]) * 0.5f;
      items[ni].cy = (m->g.gb[1] + m->g.gb[3]) * 0.5f;
      items[ni].hx = fmaxf((m->g.gb[2] - m->g.gb[0]) * 0.5f, 1.0f);
      items[ni].hy = fmaxf((m->g.gb[3] - m->g.gb[1]) * 0.5f, 1.0f);
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
    int sid = -1;
    int is_new = 0;
    // Check if already seen in an earlier dirty part of this same frame
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
        w->ad_slots[sid] = (MBAdSlot){0};
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
    if (!is_new && !backdrop_changed && s->settle_left > 0.0 &&
        atomic_load(&w->ad_conv_serial[sid]) >= s->settle_serial) {
      s->settle_left = 0.0;
    }
    int need = is_new || backdrop_changed || s->settle_left > 0.0;
    if (need) {
      if (is_new) {
        s->settle_left = 0.0;
        s->settle_serial = serial;
      } else if (backdrop_changed) {
        s->settle_left = MB_AD_SETTLE_SEC;
        s->settle_serial = serial;
      } else {
        s->settle_left -= dt;
        if (s->settle_left <= 0.0) s->settle_left = 0.0;
      }
      s->updated_serial = serial;
      out[n_upd++] = (AdPending){sid, is_new, s->is_dark, s->cx, s->cy, s->hx, s->hy};
    }
  }
  return n_upd;
}

typedef struct {
  AdPending p;
  __unsafe_unretained id<MTLTexture> tex;
  float map[4];
  float uvc[4];
} AdBatchItem;

static void ad_run_updates_batch(id<MTLCommandBuffer> cb, MBRenderWin *w, const AdBatchItem *items, int n_upd,
                                 double dt) {
  if (!w || n_upd <= 0) return;
  ensure_ad_tex(w);
  int cur = w->ad_cur, nxt = 1 - cur;
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  if (!w->ad_rb_prev_copied && w->ad_rb[w->ad_rb_i]) {
    [bl copyFromTexture:w->ad_tex[cur] sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake(MB_ADAPTIVE_MAX, 1, 1) toBuffer:w->ad_rb[w->ad_rb_i] destinationOffset:0
      destinationBytesPerRow:MB_ADAPTIVE_MAX * 4 destinationBytesPerImage:MB_ADAPTIVE_MAX * 4];
    w->ad_rb_prev_copied = 1;
  }
  [bl copyFromTexture:w->ad_tex[cur] sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
           sourceSize:MTLSizeMake(MB_ADAPTIVE_MAX, 1, 1) toTexture:w->ad_tex[nxt] destinationSlice:0 destinationLevel:0
    destinationOrigin:MTLOriginMake(0, 0, 0)];
  [bl endEncoding];
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = w->ad_tex[nxt];
  rp.colorAttachments[0].loadAction = MTLLoadActionLoad;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:adpipe];
  [e setViewport:(MTLViewport){0, 0, (double)MB_ADAPTIVE_MAX, 1.0, 0, 1}];
  [e setFragmentTexture:w->ad_tex[cur] atIndex:1];
  id<MTLTexture> last_tex = nil;
  for (int i = 0; i < n_upd; i++) {
    if (items[i].tex != last_tex) {
      last_tex = items[i].tex;
      [e setFragmentTexture:last_tex atIndex:0];
    }
    [e setScissorRect:(MTLScissorRect){(NSUInteger)items[i].p.sid, 0, 1, 1}];
    struct { float map[4]; float uvc[4]; float box[4]; float param[4]; } u;
    memcpy(u.map, items[i].map, sizeof u.map);
    memcpy(u.uvc, items[i].uvc, sizeof u.uvc);
    u.box[0] = items[i].p.cx; u.box[1] = items[i].p.cy; u.box[2] = items[i].p.hx; u.box[3] = items[i].p.hy;
    u.param[0] = (float)items[i].p.is_dark;
    u.param[1] = (float)items[i].p.is_new;
    u.param[2] = (float)dt;
    u.param[3] = (float)items[i].p.sid;
    [e setFragmentBytes:&u length:sizeof u atIndex:0];
    [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    if (!items[i].p.is_new && dt > 0.0) w->ad_track_mask |= (1u << items[i].p.sid);
  }
  [e endEncoding];
  w->ad_cur = nxt;
}

static void ad_run_updates(id<MTLCommandBuffer> cb, MBRenderWin *w, const AdPending *pend, int n_upd, double dt) {
  if (!w || n_upd <= 0 || !gtex) return;
  AdBatchItem items[MB_ADAPTIVE_MAX];
  for (int i = 0; i < n_upd; i++) {
    items[i].p = pend[i];
    items[i].tex = gtex;
    memcpy(items[i].map, gu.map, sizeof items[i].map);
    memcpy(items[i].uvc, gu.uvc, sizeof items[i].uvc);
  }
  ad_run_updates_batch(cb, w, items, n_upd, dt);
}

static void ad_rb_finish(id<MTLCommandBuffer> cb, MBRenderWin *w, uint64_t serial) {
  if (!w) return;
  w->ad_rb_prev_copied = 0;
  if (!w->ad_track_mask) return;
  uint32_t mask = w->ad_track_mask;
  id<MTLBuffer> rb = w->ad_rb[w->ad_rb_i];
  w->ad_track_mask = 0;
  if (!rb || !w->ad_tex[w->ad_cur]) return;
  w->ad_rb_i = (w->ad_rb_i + 1) % 3;
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl copyFromTexture:w->ad_tex[w->ad_cur] sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
           sourceSize:MTLSizeMake(MB_ADAPTIVE_MAX, 1, 1) toBuffer:rb destinationOffset:MB_ADAPTIVE_MAX * 4
    destinationBytesPerRow:MB_ADAPTIVE_MAX * 4 destinationBytesPerImage:MB_ADAPTIVE_MAX * 4];
  [bl endEncoding];
  [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
    (void)done;
    const uint8_t *p = (const uint8_t *)rb.contents;
    const uint8_t *prev = p;
    const uint8_t *next = p + MB_ADAPTIVE_MAX * 4;
    for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
      if (!(mask & (1u << i))) continue;
      if (prev[i * 4 + 0] == next[i * 4 + 0] && prev[i * 4 + 1] == next[i * 4 + 1]) {
        uint64_t cur = atomic_load(&w->ad_conv_serial[i]);
        while (serial > cur && !atomic_compare_exchange_weak(&w->ad_conv_serial[i], &cur, serial)) {}
      }
    }
  }];
}

static double ad_next_dt(MBRenderWin *w) {
  if (ad_fixed_dt > 0.0) return ad_fixed_dt;
  double now = CACurrentMediaTime();
  double dt = (w && w->ad_last_time > 0.0) ? (now - w->ad_last_time) : (1.0 / 60.0);
  if (w) w->ad_last_time = now;
  if (dt < 0.0) dt = 0.0;
  if (dt > 0.1) dt = 0.1;
  return dt;
}

static void ad_finalize_frame(MBRenderWin *w, int whole_frame, uint64_t serial) {
  if (!w) return;
  int settling = 0, has_ad = 0;
  MBDirty sd = {0};
  for (int i = 0; i < MB_ADAPTIVE_MAX; i++) {
    MBAdSlot *s = &w->ad_slots[i];
    if (!s->active) continue;
    if (whole_frame && s->seen_serial != serial) {
      s->active = 0;
      s->settle_left = 0.0;
      continue;
    }
    has_ad = 1;
    if (s->settle_left > 0.0) {
      settling = 1;
      dirty_add(&sd, s->cx - s->hx - 4.0, s->cy - s->hy - 4.0, s->hx * 2.0 + 8.0, s->hy * 2.0 + 8.0);
    }
  }
  sd.glass_closure = settling;
  os_unfair_lock_lock(&present_mu);
  w->ad_settle_dirty = sd;
  os_unfair_lock_unlock(&present_mu);
  atomic_store(&w->ad_settling, settling);
  atomic_store(&w->ad_has_adaptive, has_ad);
}

static void slots_invalidate(void) {
  for (int i = 0; i < MB_GLASS_SLOTS; i++) slots[i].valid = 0;
  kept_ok = 0;
}

static void slots_drop_textures(void) {
  for (int i = 0; i < MB_GLASS_SLOTS; i++) slot_bt[i] = nil;
}

static void shrink_levels(int w, int h) {
  lv_w = w;
  lv_h = h;
  for (int j = 0; j < 4; j++)
    lv[j] = level_tex(j == 0 ? MTLPixelFormatBGRA8Unorm : MTLPixelFormatRGBA16Float, (lv_w + (1 << j) - 1) >> j,
                      (lv_h + (1 << j) - 1) >> j);
  ltmp = level_tex(MTLPixelFormatRGBA16Float, lv_w, lv_h);
  for (int i = 0; i < MB_GLASS_SLOTS; i++) {
    if (!slot_bt[i]) continue;
    int sk = slots[i].grab.progressive ? 0 : slots[i].grab.k;
    int max_sw = (lv_w + (1 << sk) - 1) >> sk;
    int max_sh = (lv_h + (1 << sk) - 1) >> sk;
    if (!slots[i].valid || (int)slot_bt[i].width > max_sw || (int)slot_bt[i].height > max_sh) {
      slot_bt[i] = nil;
      slots[i].valid = 0;
    }
  }
}

static void glass_free(void) {
  for (int j = 0; j < 4; j++) lv[j] = nil;
  ltmp = nil;
  gtex = nil;
  for (int i = 0; i < MB_GLASS_SLOTS; i++) {
    slot_bt[i] = nil;
    free(slots[i].under);
    slots[i].under = NULL;
    slots[i].under_cap = slots[i].under_n = 0;
  }
  lv_w = lv_h = 0;
  lv_shrink_frames = lv_win_max_w = lv_win_max_h = 0;
  lv_frame_max_w = lv_frame_max_h = 0;
  for (int i = 0; i < MB_WINS; i++) {
    render_wins[i].ad_tex[0] = nil;
    render_wins[i].ad_tex[1] = nil;
    for (int b = 0; b < 3; b++) render_wins[i].ad_rb[b] = nil;
    ad_forget(&render_wins[i]);
  }
  glass_forget();
}

// Glass's textures (its levels as big as the largest capture yet, a copy a slot) let go of once this many frames in a
// row drew no glass (a sheet closed, the composer gone): held on, they are tens of MB at a window's size.
#define MB_GLASS_IDLE 180
static int glass_idle_frames;

static void glass_idle_tick(int glass) {
  if (glass) {
    glass_idle_frames = 0;
    if (lv_w > 0 && lv_h > 0 && lv_frame_max_w > 0 && lv_frame_max_h > 0) {
      if (lv_frame_max_w > lv_win_max_w) lv_win_max_w = lv_frame_max_w;
      if (lv_frame_max_h > lv_win_max_h) lv_win_max_h = lv_frame_max_h;
      if (++lv_shrink_frames >= MB_GLASS_IDLE) {
        if ((size_t)lv_win_max_w * (size_t)lv_win_max_h * 2 < (size_t)lv_w * (size_t)lv_h) {
          shrink_levels(lv_win_max_w, lv_win_max_h);
        }
        lv_shrink_frames = 0;
        lv_win_max_w = lv_win_max_h = 0;
      }
    }
    lv_frame_max_w = lv_frame_max_h = 0;
  } else {
    lv_frame_max_w = lv_frame_max_h = 0;
    if (glass_idle_frames < MB_GLASS_IDLE && ++glass_idle_frames == MB_GLASS_IDLE && lv_w > 0) glass_free();
  }
}

static void glass_forget(void) {
  slots_invalidate();
  ad_forget(rw);
  if (at_win && at_win != rw) ad_forget(at_win);
}

// Whether instance i (its run of glass starting at `run`) draws anything in g (x0, y0, x1, y1, points): its quad as
// the vertex shader makes it (vmain: grown round its rect, liquid glass over its group's bounds), turned ones always.
static int reaches(const float *f, int32_t i, int32_t run, const float g[4]) {
  const float *b = f + (size_t)i * MB_INST;
  if (b[32] != 0.0f) return 1;
  int kind = (int)(b[5] + 0.5f);
  float e = kind == 2 ? fabsf(b[7]) * 3.0f + 2.0f : 1.0f;
  // (liquid: its group's bounds, each shape and the first's reach round it, 2 more: grab_of)
  if (kind == 6) e = fmaxf(fmaxf(b[23], f[(size_t)run * MB_INST + 23]), 0.0f) + 2.0f;
  e += 1.0f;
  float x0 = fminf(b[0], b[0] + b[2]) - e, x1 = fmaxf(b[0], b[0] + b[2]) + e;
  float y0 = fminf(b[1], b[1] + b[3]) - e, y1 = fmaxf(b[1], b[1] + b[3]) + e;
  return x1 > g[0] && x0 < g[2] && y1 > g[1] && y0 < g[3];
}

// What the capture of the run at start is of (under_now): exact spatial dependency closure of every instance before
// start whose pixels (directly, or transitively through an earlier glass capture or adaptive ink sample) reach into
// the capture's rectangle, plus the frame's shapes' pieces (from `pieces` on). 0 when a stream or a native view's
// hole is among them.
static int under_take(const float *f, int32_t start, int32_t count, int32_t pieces, const Grab *m) {
  float sc = (float)at_scale;
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
            bx0 = fmaxf(b[0], b[16]); by0 = fmaxf(b[1], b[17]);
            bx1 = fminf(b[0] + b[2], b[18]); by1 = fminf(b[1] + b[3], b[19]);
          }
          gx0 = fminf(gx0, bx0); gy0 = fminf(gy0, by0);
          gx1 = fmaxf(gx1, bx1); gy1 = fmaxf(gy1, by1);
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
    under_now_cap = most;
    under_now = realloc(under_now, under_now_cap * sizeof(float));
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

// The slot whose blur is of what the capture now is (under_now), or -1.
static int slot_same(const Grab *m, const double key[7]) {
  for (int i = 0; i < MB_GLASS_SLOTS; i++) {
    GlassSlot *s = &slots[i];
    if (s->valid && s->under_n == under_now_n && s->whole == under_whole && s->picked == under_picked &&
        memcmp(&s->grab, m, sizeof *m) == 0 && memcmp(s->key, key, sizeof s->key) == 0 &&
        memcmp(s->under, under_now, under_now_n * sizeof(float)) == 0)
      return i;
  }
  return -1;
}

static void slots_evict_budget(int keep_idx, unsigned frame_clock, int allow_frame_slots) {
  while (slots_total_bytes() > MB_GLASS_CACHE_MAX_BYTES) {
    int victim = -1;
    for (int j = 0; j < MB_GLASS_SLOTS; j++) {
      if (j == keep_idx || !slot_bt[j]) continue;
      if (!allow_frame_slots && slots[j].used > frame_clock) continue;
      if (victim < 0 || (!slots[j].valid && slots[victim].valid) ||
          (slots[j].valid == slots[victim].valid && slots[j].used < slots[victim].used)) {
        victim = j;
      }
    }
    if (victim < 0) break;
    slot_bt[victim] = nil;
    slots[victim].valid = 0;
  }
}

// The blur just made (blur) kept in the slot least lately shown: by swapping texture handles with the level
// (zero GPU blit) when the level is close to the grab's size, or copying only the grab's active top-left region
// into a compact 64-px-aligned slot texture when the shared level is much larger than the grab.
static int slot_fill(id<MTLCommandBuffer> cb, const Grab *m, unsigned frame_clock) {
  id<MTLTexture> __strong *Lp = (m->progressive || (m->contained && m->k == 0)) ? &ltmp : &lv[m->k];
  id<MTLTexture> L = *Lp;
  int lw[4], lh[4];
  grab_levels(m, lw, lh);
  int sk = m->progressive ? 0 : m->k;
  int gw = lw[sk] > 0 ? lw[sk] : 1;
  int gh = lh[sk] > 0 ? lh[sk] : 1;
  int Lw = (int)L.width, Lh = (int)L.height;
  int bw = (gw + 63) & ~63;
  int bh = (gh + 63) & ~63;
  if (bw > Lw) bw = Lw;
  if (bh > Lh) bh = Lh;
  if (bw < 1) bw = 1;
  if (bh < 1) bh = 1;
  size_t L_area = (size_t)Lw * (size_t)Lh;
  size_t b_area = (size_t)bw * (size_t)bh;
  int full_size = (bw >= Lw && bh >= Lh);
  int use_swap = full_size || (L_area <= 2 * b_area && glass_tex_bytes(L) <= MB_GLASS_CACHE_MAX_BYTES);
  int t0 = -1, t1 = -1, t2 = -1, t3 = -1, t4 = -1, fallback = 0;
  for (int j = 0; j < MB_GLASS_SLOTS; j++) {
    if (slots[j].used < slots[fallback].used) fallback = j;
    if (slots[j].used > frame_clock) continue;
    int has_bt = slot_bt[j] != nil;
    int reuse_tex = 0;
    if (use_swap) {
      reuse_tex = has_bt && (int)slot_bt[j].width == Lw && (int)slot_bt[j].height == Lh &&
                  slot_bt[j].pixelFormat == L.pixelFormat;
    } else {
      reuse_tex = has_bt && slot_bt[j].pixelFormat == L.pixelFormat && (int)slot_bt[j].width >= gw &&
                  (int)slot_bt[j].height >= gh && (size_t)slot_bt[j].width * (size_t)slot_bt[j].height <= 2 * b_area;
    }
    if (!slots[j].valid) {
      if (reuse_tex) {
        if (t0 < 0) t0 = j;
      } else if (!has_bt) {
        if (t1 < 0) t1 = j;
      } else {
        if (t3 < 0) t3 = j;
      }
    } else if (reuse_tex) {
      if (t2 < 0 || slots[j].used < slots[t2].used) t2 = j;
    }
    if (t4 < 0 || slots[j].used < slots[t4].used) t4 = j;
  }
  int i = t0 >= 0 ? t0 : t1 >= 0 ? t1 : t2 >= 0 ? t2 : t3 >= 0 ? t3 : t4 >= 0 ? t4 : fallback;
  slots[i].valid = 0;
  slots[i].gen = ++slots_gen;
  if (use_swap) {
    if (slot_bt[i] != nil && (int)slot_bt[i].width == Lw && (int)slot_bt[i].height == Lh &&
        slot_bt[i].pixelFormat == L.pixelFormat) {
      id<MTLTexture> old = slot_bt[i];
      slot_bt[i] = L;
      *Lp = old;
    } else {
      slot_bt[i] = L;
      *Lp = level_tex(L.pixelFormat, Lw, Lh);
    }
  } else {
    if (!(slot_bt[i] != nil && slot_bt[i].pixelFormat == L.pixelFormat && (int)slot_bt[i].width >= gw &&
          (int)slot_bt[i].height >= gh && (size_t)slot_bt[i].width * (size_t)slot_bt[i].height <= 2 * b_area)) {
      slot_bt[i] = level_tex(L.pixelFormat, bw, bh);
    }
    id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromTexture:L sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake((NSUInteger)gw, (NSUInteger)gh, 1) toTexture:slot_bt[i] destinationSlice:0
       destinationLevel:0 destinationOrigin:MTLOriginMake(0, 0, 0)];
    [bl endEncoding];
  }
  slots_evict_budget(i, frame_clock, 0);
  return i;
}

static void slot_show(const Grab *m, int i) {
  slots[i].used = ++slots_clock;
  show_blur(m, slot_bt[i]);
}

static void slot_keep(int i, const Grab *m, const double key[7]) {
  GlassSlot *s = &slots[i];
  if (s->under_cap < under_now_n) {
    s->under = realloc(s->under, under_now_n * sizeof(float));
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

// where the pieces of the frame's shapes start (src/ui/shape.mbt: the instances of kind 12 after every one drawn)
static int32_t seg_base;

// Partial redraw: a window's frame is drawn into a canvas of its own, kept across frames, and
// copied into the drawable; where the app says only some parts of it differ from the frame before
// (@hostapi.render_dirty), only those parts of the canvas are drawn again, a pass each: it loads what the canvas holds,
// cut to the part (the pass's scissor, `sc`, while `sc_on`), the frame's ground drawn over the part first (the
// instance after the frame's, upload's), then every instance (what falls outside is cut away).
// a picture the frame drawn last had none of yet (its texture not made: drawn without it): the next drawn whole, as
// what it shows changes under the same numbers
static int pictures_missing, encode_missing;
static int sc_on;
static MTLScissorRect sc;

void mb_host_render_dirty(double x, double y, double w, double h) { dirty_add(&rw->said, x, y, w, h); }
void mb_host_glass_light_angle(double rad) {
  float a = (float)rad;
  if (a != g_light_angle) { g_light_angle = a; if (rw) shown_ok = 0; }
}

// The parts of a target tw × th pixels a frame draws, from what was said of them (`d`, a frame nothing was said for
// drawn whole), into `r`: how many (0 none), -1 all of it. `kept`: the target holds the frame before.
static int take_parts(const MBDirty *d, int tw, int th, int kept, MTLScissorRect r[MB_PARTS]) {
  if (!d->told || d->whole || !kept || pictures_missing) return -1;
  int k = 0;
  for (int i = 0; i < d->n; i++) {
    // (whole pixels round it, and one more: the app's part reaches its pixels' antialiasing, not their rounding)
    const double *e = d->r[i];
    int x0 = (int)floor(e[0] * at_scale) - 1, y0 = (int)floor(e[1] * at_scale) - 1;
    int x1 = (int)ceil((e[0] + e[2]) * at_scale) + 1, y1 = (int)ceil((e[1] + e[3]) * at_scale) + 1;
    if (x0 < 0) x0 = 0;
    if (y0 < 0) y0 = 0;
    if (x1 > tw) x1 = tw;
    if (y1 > th) y1 = th;
    if (x1 > x0 && y1 > y0) r[k++] = (MTLScissorRect){(NSUInteger)x0, (NSUInteger)y0, (NSUInteger)(x1 - x0), (NSUInteger)(y1 - y0)};
  }
  return k;
}

// Whether a grab's rectangle meets the part drawn (all of it where the frame is drawn whole).
static int grab_in_part(const Grab *m) {
  if (!sc_on) return 1;
  return m->px0 < (int)(sc.x + sc.width) && (int)sc.x < m->px0 + m->w && m->py0 < (int)(sc.y + sc.height) &&
         (int)sc.y < m->py0 + m->h;
}

static id<MTLRenderCommandEncoder> begin_pass_ex(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                                                 id<MTLBuffer> buf, int clear, double r, double g, double b, double alpha,
                                                 float ox, float oy, float vp_w, float vp_h, int use_sc, int vpw, int vph) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = target;
  rp.colorAttachments[0].loadAction = clear ? MTLLoadActionClear : MTLLoadActionLoad;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  rp.colorAttachments[0].clearColor = MTLClearColorMake(r, g, b, alpha);
  id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
  if (vpw > 0 && vph > 0) {
    [enc setViewport:(MTLViewport){0, 0, (double)vpw, (double)vph, 0, 1}];
    [enc setScissorRect:(MTLScissorRect){0, 0, (NSUInteger)vpw, (NSUInteger)vph}];
  }
  struct { float vp[2]; float scale; float pad; float origin[2]; float pad2[2]; } u = {
    {vp_w, vp_h}, (float)at_scale, (float)seg_base, {ox, oy}, {0, 0}};
  [enc setRenderPipelineState:p];
  [enc setVertexBuffer:buf offset:0 atIndex:0];
  [enc setVertexBytes:&u length:sizeof(u) atIndex:1];
  [enc setVertexBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentBuffer:buf offset:0 atIndex:0];
  [enc setFragmentBytes:&u length:sizeof(u) atIndex:1];
  [enc setFragmentBytes:&gu length:sizeof(gu) atIndex:2];
  [enc setFragmentTexture:atlas atIndex:0];
  [enc setFragmentTexture:catlas atIndex:3];
  [enc setFragmentTexture:(gtex ?: atlas) atIndex:2];
  id<MTLTexture> adt = (at_win && at_win->ad_tex[at_win->ad_cur]) ? at_win->ad_tex[at_win->ad_cur] : atlas;
  [enc setFragmentTexture:adt atIndex:4];
  if (use_sc && sc_on) [enc setScissorRect:sc];
  return enc;
}

static id<MTLRenderCommandEncoder> begin_pass(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                                              id<MTLBuffer> buf, int clear, double r, double g, double b, double alpha) {
  return begin_pass_ex(cb, target, p, buf, clear, r, g, b, alpha, 0.0f, 0.0f, (float)at_w, (float)at_h, 1, 0, 0);
}

// Instances start to end drawn, each that pays for it in strips (bands.h), the rest as they come.
static void draw_banded(id<MTLRenderCommandEncoder> enc, id<MTLRenderPipelineState> p, const float *f, int32_t start,
                        int32_t end, int32_t count, int tw, int th) {
  MBStrip to = sc_on ? mb_strip((int)sc.x, (int)sc.y, (int)(sc.x + sc.width), (int)(sc.y + sc.height))
                     : mb_strip(0, 0, tw, th);
  MBStrip st[MB_STRIPS];
  int32_t s = start;
  for (int32_t i = start; i < end; i++) {
    if (!mb_band_kind(f, i)) continue;
    int n = mb_bands(f, i, count, (float)at_scale, to, st);
    if (n < 0) continue;
    if (i > s) [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:i - s baseInstance:s];
    for (int k = 0; k < n; k++) {
      if (k == 0 || st[k].flat != st[k - 1].flat) [enc setRenderPipelineState:st[k].flat ? fpipe : p];
      [enc setScissorRect:(MTLScissorRect){(NSUInteger)st[k].x0, (NSUInteger)st[k].y0, (NSUInteger)(st[k].x1 - st[k].x0),
                                           (NSUInteger)(st[k].y1 - st[k].y0)}];
      [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1 baseInstance:i];
    }
    if (n > 0 && st[n - 1].flat) [enc setRenderPipelineState:p];
    [enc setScissorRect:sc_on ? sc : (MTLScissorRect){0, 0, (NSUInteger)tw, (NSUInteger)th}];
    s = i + 1;
  }
  if (end > s) [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:end - s baseInstance:s];
}

// The texture of picture or stream `tid` (> 0) for the frame being drawn (at_texs), nil where it has none yet.
static id<MTLTexture> tex_of(int tid) {
  if (at_texs) {
    id t = at_texs[@(tid)];
    return t == (id)NSNull.null ? nil : t;
  }
  return tid > MB_STREAM_TEX ? mb_stream_texture(tid - MB_STREAM_TEX) : tid > 0 ? mb_image_texture(tid) : nil;
}

// The textures of the pictures and streams `f` draws (`count` instances), looked up now (the main thread), for the
// queue to draw them by: a picture's not decoded yet NSNull (drawn without it, encode_missing).
static NSMutableDictionary<NSNumber *, id> *frame_texs(const float *f, int32_t count) {
  NSMutableDictionary<NSNumber *, id> *d = [NSMutableDictionary new];
  int last = 0;
  for (int32_t i = 0; i < count; i++) {
    const float *b = f + (size_t)i * MB_INST;
    int tid = (int)b[20];
    if (tid <= 0 || tid == last || (int)(b[5] + 0.5f) == 9) continue;
    last = tid;
    NSNumber *k = @(tid);
    if (d[k]) continue;
    id<MTLTexture> t = tid > MB_STREAM_TEX ? mb_stream_texture(tid - MB_STREAM_TEX) : mb_image_texture(tid);
    d[k] = t ?: (id)NSNull.null;
  }
  return d;
}

// `part`: only that part of the target drawn again, over what it holds (the frame's ground first: the instance after
// the frame's, ring_put's); NULL, all of it, cleared to the ground.
static void encode(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLRenderPipelineState> p,
                   id<MTLBuffer> buf, int32_t count, double r, double g, double b, double alpha,
                   const MTLScissorRect *part, double ad_dt, uint64_t ad_serial) {
  gtex = nil;
  memset(&gu, 0, sizeof gu);
  encode_missing = 0;
  const float *f = (const float *)buf.contents;
  seg_base = count;
  while (seg_base > 0 && (int)(f[(seg_base - 1) * MB_INST + 5] + 0.5f) == 12) seg_base--;
  sc_on = part != NULL;
  if (part) sc = *part;
  // Pre-scan glass captures before opening the main render pass: size blur levels once, and batch adaptive updates for
  // blur-cache-hit groups into a single pass before begin_pass so the Retina canvas is not Store/Load split mid-pass.
  int levels_sized = 0;
  struct {
    int tid;
    int slot;
    unsigned gen;
    Grab grab;
  } pre_hits[16];
  int pre_hits_n = 0;
  {
    int max_w = 0, max_h = 0, all_max_w = 0, all_max_h = 0, scan_bound = 0, any_glass = 0;
    for (int32_t s0 = 0; s0 < count;) {
      int stid = (int)f[s0 * MB_INST + 20];
      int32_t e0 = s0 + 1;
      if (stid < 0) {
        any_glass = 1;
        while (e0 < count && (int)f[e0 * MB_INST + 20] == stid) e0++;
        if (stid != scan_bound) {
          scan_bound = stid;
          Grab gm;
          if (grab_of(&gm, f, s0, e0, count, (int)target.width, (int)target.height)) {
            if (gm.w > all_max_w) all_max_w = gm.w;
            if (gm.h > all_max_h) all_max_h = gm.h;
            if (grab_in_part(&gm)) {
              if (gm.w > max_w) max_w = gm.w;
              if (gm.h > max_h) max_h = gm.h;
            }
          }
        }
      }
      s0 = e0;
    }
    if (any_glass) {
      levels_sized = 1;
      if (max_w > lv_w || max_h > lv_h) {
        ensure_levels(max_w, max_h);
      } else if (ad_dt >= 0.0 && lv[0] && all_max_w > 0 && all_max_h > 0) {
        if (all_max_w > lv_frame_max_w) lv_frame_max_w = all_max_w;
        if (all_max_h > lv_frame_max_h) lv_frame_max_h = all_max_h;
      }
      if (at_win && ad_dt >= 0.0) {
        AdBatchItem pre_batch[MB_ADAPTIVE_MAX];
        int pre_n = 0;
        double key[7] = {target.width, target.height, at_scale, r, g, b, alpha};
        int pre_bound = 0;
        for (int32_t s0 = 0; s0 < count && pre_n < MB_ADAPTIVE_MAX;) {
          int stid = (int)f[s0 * MB_INST + 20];
          int32_t e0 = s0 + 1;
          if (stid < 0) {
            while (e0 < count && (int)f[e0 * MB_INST + 20] == stid) e0++;
            if (stid != pre_bound) {
              pre_bound = stid;
              if ((int)(f[s0 * MB_INST + 5] + 0.5f) == 6) {
                Grab gm;
                if (grab_of(&gm, f, s0, e0, count, (int)target.width, (int)target.height) && grab_in_part(&gm) &&
                    under_take(f, s0, count, seg_base, &gm)) {
                  int sl = slot_same(&gm, key);
                  if (sl >= 0 && slot_bt[sl]) {
                    if (pre_hits_n < 16) {
                      pre_hits[pre_hits_n].tid = stid;
                      pre_hits[pre_hits_n].slot = sl;
                      pre_hits[pre_hits_n].gen = slots[sl].gen;
                      pre_hits[pre_hits_n].grab = gm;
                      pre_hits_n++;
                    }
                    AdPending tmp[MB_ADAPTIVE_MAX];
                    int nu = ad_collect_and_match(at_win, f, s0, e0, count, &gm, 0, ad_dt, ad_serial, tmp);
                    if (nu > 0) {
                      float map[4], uvc[4];
                      grab_map_uvc(&gm, slot_bt[sl], map, uvc);
                      for (int i = 0; i < nu && pre_n < MB_ADAPTIVE_MAX; i++) {
                        pre_batch[pre_n].p = tmp[i];
                        pre_batch[pre_n].tex = slot_bt[sl];
                        memcpy(pre_batch[pre_n].map, map, sizeof map);
                        memcpy(pre_batch[pre_n].uvc, uvc, sizeof uvc);
                        pre_n++;
                      }
                    }
                  }
                }
              }
            }
          }
          s0 = e0;
        }
        if (pre_n > 0) ad_run_updates_batch(cb, at_win, pre_batch, pre_n, ad_dt);
      }
    }
  }
  ad_fill_gu(at_win);
  id<MTLRenderCommandEncoder> enc = begin_pass(cb, target, p, buf, part ? 0 : 1, r, g, b, alpha);
  if (part) {
    [enc setRenderPipelineState:hpipe];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1 baseInstance:count];
  }
  // one draw per run of instances showing the same image (slot 20; 0:
  // none, the atlas stands in) of one kind (its pipeline: kind_pipe), or sharing one capture of glass (negative),
  // and holes for native views (kind 9) apart, unblended. Glass over a hole
  // sees the hole (the canvas only, not the view under it).
  int32_t start = 0;
  int bound = 0, shows = 0;
  unsigned frame_clock = slots_clock;
  while (start < count) {
    int tid = (int)f[start * MB_INST + 20];
    int kind = (int)(f[start * MB_INST + 5] + 0.5f), hole = kind == 9;
    if (kind == 8) {
      int32_t child_n = (int32_t)(f[start * MB_INST + 12] + 0.5f);
      if (child_n < 0) child_n = 0;
      if (start + 1 + child_n > count) child_n = count - start - 1;
      const float *hb = f + (size_t)start * MB_INST;
      if (child_n <= 0 || hb[11] <= 0.001f || hb[2] <= 0.0f || hb[3] <= 0.0f) {
        start += 1 + child_n;
        continue;
      }
      float sc_f = (float)at_scale;
      float blur_pt = fmaxf(hb[7], 0.0f);
      float refr_pt = fmaxf(hb[14], 0.0f);
      float margin = blur_pt * 3.0f + refr_pt + 4.0f;
      float x0 = hb[0], y0 = hb[1], x1 = hb[0] + hb[2], y1 = hb[1] + hb[3];
      for (int32_t ci = start + 1; ci < start + 1 + child_n; ci++) {
        const float *cb_f = f + (size_t)ci * MB_INST;
        int ck = (int)(cb_f[5] + 0.5f);
        if (ck == 12 || cb_f[2] <= 0.0f || cb_f[3] <= 0.0f) continue;
        if (cb_f[0] < x0) x0 = cb_f[0];
        if (cb_f[1] < y0) y0 = cb_f[1];
        if (cb_f[0] + cb_f[2] > x1) x1 = cb_f[0] + cb_f[2];
        if (cb_f[1] + cb_f[3] > y1) y1 = cb_f[1] + cb_f[3];
      }
      float ox = floorf((x0 - margin) * sc_f) / sc_f;
      float oy = floorf((y0 - margin) * sc_f) / sc_f;
      int pw = (int)ceilf(((x1 + margin) - ox) * sc_f);
      int ph = (int)ceilf(((y1 + margin) - oy) * sc_f);
      int max_dim_w = (int)target.width > 2048 ? (int)target.width : 2048;
      int max_dim_h = (int)target.height > 2048 ? (int)target.height : 2048;
      if (pw < 1) pw = 1;
      if (ph < 1) ph = 1;
      if (pw > max_dim_w) pw = max_dim_w;
      if (ph > max_dim_h) ph = max_dim_h;
      [enc endEncoding];
      ensure_levels(pw, ph);
      // Pass 1: render child subtree into lv[0] cleared to transparent
      id<MTLRenderCommandEncoder> lenc = begin_pass_ex(cb, lv[0], p, buf, 1, 0, 0, 0, 0,
                                                       ox, oy, (float)pw / sc_f, (float)ph / sc_f, 0, pw, ph);
      int32_t cs = start + 1, cend_all = start + 1 + child_n;
      while (cs < cend_all) {
        int ctid = (int)f[cs * MB_INST + 20];
        int ck = (int)(f[cs * MB_INST + 5] + 0.5f);
        if (ck == 5 || ck == 6 || ck == 8 || ck == 9 || ck == 12 || ctid < 0) {
          cs++;
          continue;
        }
        int cown = has_own_pipe(ck);
        int32_t ce = cs + 1;
        while (ce < cend_all && (int)f[ce * MB_INST + 20] == ctid) {
          int kk = (int)(f[ce * MB_INST + 5] + 0.5f);
          if (kk == 5 || kk == 6 || kk == 8 || kk == 9 || kk == 12) break;
          if (cown ? kk != ck : has_own_pipe(kk)) break;
          ce++;
        }
        id<MTLTexture> ct = tex_of(ctid);
        if (ctid > MB_STREAM_TEX && !ct) { cs = ce; continue; }
        if (ctid > 0 && ctid <= MB_STREAM_TEX && !ct) encode_missing = 1;
        [lenc setRenderPipelineState:(cown ? kind_pipe(p, ck) : p)];
        [lenc setFragmentTexture:(ct ?: atlas) atIndex:1];
        [lenc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:ce - cs baseInstance:cs];
        cs = ce;
      }
      [lenc endEncoding];
      // Pass 2: optional downsample + separable Gaussian blur
      int lw[4], lh[4];
      lw[0] = pw; lh[0] = ph;
      for (int j = 1; j <= 3; j++) { lw[j] = (lw[j - 1] + 1) / 2; lh[j] = (lh[j - 1] + 1) / 2; }
      float sp = blur_pt * sc_f;
      int lk = 0;
      while (lk < 2 && sp / (float)(1 << (lk + 1)) >= 2.0f) lk++;
      float sk_f = sp / (float)(1 << lk);
      float pre = lk > 0 ? 0.75f * (1.0f - powf(0.25f, (float)lk)) / 3.0f + 1.0f / 6.0f : 0.0f;
      float sg = sqrtf(fmaxf(sk_f * sk_f - pre, 0.0f));
      if (sp > 0.25f) {
        for (int j = 1; j <= lk; j++) {
          post_pass(cb, lv[j - 1], lw[j - 1], lh[j - 1], lv[j], lw[j], lh[j], 1, 0, 0, 0, NULL, NULL);
        }
        if (sg > 0.3f) {
          post_pass(cb, lv[lk], lw[lk], lh[lk], ltmp, lw[lk], lh[lk], 2, sg, 1, 0, NULL, NULL);
          post_pass(cb, ltmp, lw[lk], lh[lk], lv[lk], lw[lk], lh[lk], 2, sg, 0, 1, NULL, NULL);
        }
      } else {
        lk = 0;
      }
      // Pass 3: composite refracted & SDF-clipped foreground lens onto target
      id<MTLTexture> ltex = lv[lk];
      gtex = ltex;
      memset(&gu, 0, sizeof gu);
      float W = (float)ltex.width, H = (float)ltex.height, d_lv = (float)(1 << lk);
      gu.map[0] = sc_f / d_lv / W; gu.map[1] = sc_f / d_lv / H;
      gu.map[2] = -(ox * sc_f) / d_lv / W; gu.map[3] = -(oy * sc_f) / d_lv / H;
      gu.uvc[0] = 0.5f / W; gu.uvc[1] = 0.5f / H;
      gu.uvc[2] = ((float)lw[lk] - 0.5f) / W; gu.uvc[3] = ((float)lh[lk] - 0.5f) / H;
      enc = begin_pass(cb, target, p, buf, 0, r, g, b, alpha);
      [enc setRenderPipelineState:kind_pipe(p, 8)];
      [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1 baseInstance:start];
      bound = 0;
      start += 1 + child_n;
      continue;
    }
    // (kinds without their own pipeline one run, as before)
    int own = tid >= 0 && has_own_pipe(kind);
    int32_t end = start + 1;
    while (end < count && (int)f[end * MB_INST + 20] == tid) {
      int k = (int)(f[end * MB_INST + 5] + 0.5f);
      if (k == 8 || (k == 9) != hole || (own ? k != kind : tid >= 0 && has_own_pipe(k))) break;
      end++;
    }
    if (tid < 0) {
      if (!levels_sized) {
        levels_sized = 1;
        int max_w = 0, max_h = 0, all_max_w = 0, all_max_h = 0, scan_bound = 0;
        for (int32_t s0 = start; s0 < count;) {
          int stid = (int)f[s0 * MB_INST + 20];
          int32_t e0 = s0 + 1;
          if (stid < 0) {
            while (e0 < count && (int)f[e0 * MB_INST + 20] == stid) e0++;
            if (stid != scan_bound) {
              scan_bound = stid;
              Grab gm;
              if (grab_of(&gm, f, s0, e0, count, (int)target.width, (int)target.height)) {
                if (gm.w > all_max_w) all_max_w = gm.w;
                if (gm.h > all_max_h) all_max_h = gm.h;
                if (grab_in_part(&gm)) {
                  if (gm.w > max_w) max_w = gm.w;
                  if (gm.h > max_h) max_h = gm.h;
                }
              }
            }
          }
          s0 = e0;
        }
        if (max_w > lv_w || max_h > lv_h) {
          ensure_levels(max_w, max_h);
        } else if (ad_dt >= 0.0 && lv[0] && all_max_w > 0 && all_max_h > 0) {
          if (all_max_w > lv_frame_max_w) lv_frame_max_w = all_max_w;
          if (all_max_h > lv_frame_max_h) lv_frame_max_h = all_max_h;
        }
      }
      if (tid != bound) {
        Grab m;
        double key[7] = {target.width, target.height, at_scale, r, g, b, alpha};
        int known = 0, slot = -1;
        for (int h = 0; h < pre_hits_n; h++) {
          if (pre_hits[h].tid == tid) {
            int hs = pre_hits[h].slot;
            if (slots[hs].valid && slot_bt[hs] && slots[hs].gen == pre_hits[h].gen) {
              m = pre_hits[h].grab;
              shows = 1;
              known = 1;
              slot = hs;
            }
            break;
          }
        }
        if (slot < 0) {
          shows = grab_of(&m, f, start, end, count, (int)target.width, (int)target.height);
          // (a capture outside the part drawn: neither copied nor drawn, the blur kept as it was. One that meets it is
          // in it whole: the app's part takes in all a capture it reaches copies, @damage)
          shows = shows && grab_in_part(&m);
          known = shows && under_take(f, start, count, seg_base, &m);
          slot = known ? slot_same(&m, key) : -1;
        }
        AdPending ad_pend[MB_ADAPTIVE_MAX];
        int ad_n_upd = 0;
        if (slot >= 0) {
          // what it sees is what a slot holds: shown on in this pass unless an adaptive slot needs a settle step
          kept_ok = 1;
          slot_show(&m, slot);
          ad_n_upd = ad_collect_and_match(at_win, f, start, end, count, &m, 0, ad_dt, ad_serial, ad_pend);
          if (ad_n_upd > 0) {
            [enc endEncoding];
            ad_run_updates(cb, at_win, ad_pend, ad_n_upd, ad_dt);
            ad_fill_gu(at_win);
            enc = begin_pass(cb, target, p, buf, 0, r, g, b, alpha);
          } else {
            ad_fill_gu(at_win);
            [enc setVertexBytes:&gu length:sizeof gu atIndex:2];
            [enc setFragmentBytes:&gu length:sizeof gu atIndex:2];
            [enc setFragmentTexture:gtex atIndex:2];
            id<MTLTexture> adt = (at_win && at_win->ad_tex[at_win->ad_cur]) ? at_win->ad_tex[at_win->ad_cur] : atlas;
            [enc setFragmentTexture:adt atIndex:4];
          }
        } else if (shows) {
          [enc endEncoding];
          blur(cb, target, &m);
          slot = slot_fill(cb, &m, frame_clock);
          // (an image drawn under it that had no texture yet: it comes under the same instances, so this blur is not
          // kept to be shown again as theirs)
          if (known && !encode_missing) slot_keep(slot, &m, key);
          kept_ok = slots[slot].valid;
          slot_show(&m, slot);
          ad_n_upd = ad_collect_and_match(at_win, f, start, end, count, &m, 1, ad_dt, ad_serial, ad_pend);
          if (ad_n_upd > 0) ad_run_updates(cb, at_win, ad_pend, ad_n_upd, ad_dt);
          ad_fill_gu(at_win);
          enc = begin_pass(cb, target, p, buf, 0, r, g, b, alpha);
        }
        bound = tid;
      }
      // merged liquid (merge > 0): the group as one shape, drawn once; unmerged liquid and frosted: each instance
      if (shows) {
        int merged_liquid = kind == 6 && f[start * MB_INST + 23] > 0.0f;
        int gkind = kind == 5 ? 5 : (kind == 6 ? (merged_liquid ? 6 : MB_KIND_LIQUID_SINGLE) : -1);
        [enc setRenderPipelineState:kind_pipe(p, gkind)];
        [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
                instanceCount:merged_liquid ? 1 : end - start baseInstance:start];
      }
      start = end;
      continue;
    }
    id<MTLRenderPipelineState> kp = own ? kind_pipe(p, kind) : p;
    [enc setRenderPipelineState:(hole ? hpipe : kp)];
    // (a hole's image is its view's, src/hostapi/host.mbt view_tex_base + its id: the view is under the canvas here)
    id<MTLTexture> t = hole ? nil : tex_of(tid);
    // (a stream with no frame of its own yet, or lost: nothing, not the atlas)
    if (!hole && tid > MB_STREAM_TEX && !t) {
      start = end;
      continue;
    }
    if (!hole && tid > 0 && tid <= MB_STREAM_TEX && !t) encode_missing = 1;
    [enc setFragmentTexture:(t ?: atlas) atIndex:1];
    if (hole) [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6
                      instanceCount:end - start baseInstance:start];
    else draw_banded(enc, kp, f, start, end, count, (int)target.width, (int)target.height);
    start = end;
  }
  [enc endEncoding];
  gtex = nil;
  if (levels_sized && slots_total_bytes() > MB_GLASS_CACHE_MAX_BYTES) slots_evict_budget(-1, frame_clock, 1);
  sc_on = 0;
}

// The frame in `buf` drawn into `target`, only its parts said to differ (`d`, take_parts) where it holds the frame
// before (`kept`), a pass each, else whole: how many parts (-1 whole, 0 none).
static int draw_parts(id<MTLCommandBuffer> cb, id<MTLTexture> target, id<MTLBuffer> buf, int32_t count, double r,
                      double g, double b, int kept, const MBDirty *d, double ad_dt, uint64_t ad_serial) {
  MTLScissorRect parts[MB_PARTS];
  MBDirty expanded = *d;
  if (expanded.glass_closure && expanded.told && !expanded.whole && kept && !pictures_missing &&
      !mb_glass_damage_expand((const float *)buf.contents, count, expanded.r, &expanded.n,
                              target.width / at_scale, target.height / at_scale, at_scale)) expanded.whole = 1;
  int n = take_parts(&expanded, (int)target.width, (int)target.height, kept, parts);
  int missing = 0;
  if (n < 0) {
    encode(cb, target, mpipe, buf, count, r, g, b, 1, NULL, ad_dt, ad_serial);
    missing = encode_missing;
  }
  for (int i = 0; i < n; i++) {
    encode(cb, target, mpipe, buf, count, r, g, b, 1, &parts[i], ad_dt, ad_serial);
    missing |= encode_missing;
  }
  if (n != 0) pictures_missing = missing;
  ad_rb_finish(cb, at_win, ad_serial);
  return n;
}

// The frame as floats as it comes (mb_groups_floats: a window's; as it is: one drawn offscreen), before it is the
// window's last (upload): each frame made here once, compared, put in the ring and kept from here.
static float *next_inst;
static size_t next_cap;

// Room in next_inst for `count` instances.
static float *next_room(int32_t count) {
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  if (next_cap < need) {
    next_inst = realloc(next_inst, need);
    next_cap = need;
  }
  return next_inst;
}

// Instances `inst` into next_inst as they are (no header of a group among them drawn out: a frame drawn offscreen, as
// it always was).
static void next_as_is(const double *inst, int32_t count) {
  float *f = next_room(count);
  size_t n = (size_t)(count > 0 ? count : 0) * MB_INST;
  for (size_t i = 0; i < n; i++) f[i] = (float)inst[i];
}

// The frame in next_inst (`count` instances) kept as the window's last (for snapshots, and what the next is compared
// with): next_inst and the last swapped, nothing copied.
static void keep_last(int32_t count, double r, double g, double b) {
  float *was = last_inst;
  size_t was_cap = last_cap;
  last_inst = next_inst;
  last_cap = next_cap;
  next_inst = was;
  next_cap = was ? was_cap : 0;
  last_count = count;
  last_bg[0] = r; last_bg[1] = g; last_bg[2] = b;
}

// Instances `f` (`count` of them) into the next buffer of the ring, and the frame's ground after them: a rect over all
// the frame (at_w × at_h), opaque, a part drawn again first.
static id<MTLBuffer> ring_put(const float *f, int32_t count, double r, double g, double b) {
  buf_i = (buf_i + 1) % 3;
  size_t need = (size_t)(count > 0 ? count : 1) * MB_INST * sizeof(float);
  size_t room = need + MB_INST * sizeof(float);
  if (buf_cap[buf_i] < room) {
    size_t cap = room * 2;
    bufs[buf_i] = [dev newBufferWithLength:cap options:MTLResourceStorageModeShared];
    buf_cap[buf_i] = cap;
  }
  float *d = (float *)bufs[buf_i].contents;
  int32_t n = count * MB_INST;
  if (n > 0) memcpy(d, f, (size_t)n * sizeof(float));
  float *gr = d + n;
  memset(gr, 0, MB_INST * sizeof(float));
  gr[0] = -16.0f; gr[1] = -16.0f; gr[2] = (float)at_w + 32.0f; gr[3] = (float)at_h + 32.0f;
  gr[8] = (float)r; gr[9] = (float)g; gr[10] = (float)b; gr[11] = 1.0f;
  gr[16] = -1e9f; gr[17] = -1e9f; gr[18] = 1e9f; gr[19] = 1e9f;
  return bufs[buf_i];
}

// Whether a frame is the one last handed to be shown to the last number: then it draws nothing and takes no drawable
// (the app builds a frame for what it waits on, as a clock's next second, that may show nothing new). Not one a layer
// presents with its transaction (a resize's: mac_app.m drawWithWindow), which the window's change waits for.
static int same_as_shown(const float *f, int32_t count, double r, double g, double b) {
  if (atomic_load(&rw->ad_settling)) return 0;
  if (!shown_ok || shown_streams || mlayer.presentsWithTransaction || count != last_count) return 0;
  if (vw != shown_w || vh != shown_h || vscale != shown_scale || r != last_bg[0] || g != last_bg[1] || b != last_bg[2]) return 0;
  size_t n = (size_t)(count > 0 ? count : 0) * MB_INST;
  return n == 0 || (last_inst && memcmp(f, last_inst, n * sizeof(float)) == 0);
}

// The canvas window `w`'s frames are drawn into (partial redraw, above), tw × th pixels: made again at another size,
// what it held lost.
static void ensure_canvas(MBRenderWin *w, int tw, int th) {
  if (w->cv && (int)w->cv.width == tw && (int)w->cv.height == th) return;
  w->cv = nil;
  w->cv_ok = 0;
  if (tw <= 0 || th <= 0) return;
  MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                width:(NSUInteger)tw
                                                                               height:(NSUInteger)th
                                                                            mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  w->cv = [dev newTextureWithDescriptor:td];
}

// MBUI_PARTIAL_CHECK=1 (a device's run, by hand: slow): each frame drawn in part compared with itself drawn whole,
// a line on the log where they differ, once its commands (`cb`, committed) are done. Its frames are drawn on the main
// thread (mb_render_present), the window's last frame then the one just drawn.
static int partial_check = -1, partial_frames;

static int partial_checking(void) {
  if (partial_check < 0) {
    const char *v = getenv("MBUI_PARTIAL_CHECK");
    partial_check = v && v[0] == '1';
  }
  return partial_check;
}

static uint8_t *read_texture(id<MTLTexture> src, int *pw, int *ph);
static uint8_t *read_last(int *pw, int *ph);

static void check_part(id<MTLCommandBuffer> cb, int parts, MBRenderWin *win) {
  if (!partial_checking()) return;
  [cb waitUntilCompleted];
  int w, h, fw, fh;
  uint8_t *drawn = read_texture(win->cv, &w, &h);
  uint8_t *whole = read_last(&fw, &fh);
  long apart = 0;
  int most = 0, ax = -1, ay = -1;
  if (fw == w && fh == h) {
    for (long i = 0; i < (long)w * h * 4; i++) {
      int d = abs((int)drawn[i] - (int)whole[i]);
      if (d) {
        if (!apart) { ax = (int)(i / 4 % w); ay = (int)(i / 4 / w); }
        apart++;
        if (d > most) most = d;
      }
    }
  }
  partial_frames++;
  if (apart || fw != w || fh != h || partial_frames % 120 == 1)
    fprintf(stderr, "PARTIAL check %d: %d parts of %dx%d: %ld bytes apart (at most %d, first at %d,%d)\n",
            partial_frames, parts, w, h, apart, most, ax, ay);
  free(drawn);
  free(whole);
}

// MBUI_PROBE=1 (src/ui/app.mbt's probe): where a present's time goes, said every 240 of them: waiting for a buffer of
// the ring (the GPU three frames behind), the instances into it, waiting for a drawable (the display's), and the
// drawing encoded and committed (ms, on average), on the queue that presents (present_q) or the main thread. On the
// log, and into the performance record while it is kept (ios_app.m's mb_perf_note, any thread: none on a Mac, these
// defaults).
static int present_probing = -1, present_n;
static double present_ms[4];

__attribute__((weak)) int mb_perf_on(void) { return 0; }
__attribute__((weak)) void mb_perf_note(const char *line) { (void)line; }

// A latency run's frames (mac_latency.h, a run measuring input to the screen: none elsewhere, these defaults): one
// made on the main thread (its number, -1 none: the events handled before it are its), one that took the place of
// another before it was drawn (the other's events are its), and its drawable about to be presented, on whatever thread
// draws it: when the frame asked for a buffer of the ring (p0), had one (p1), asked for the drawable (p2) and had it
// (p3), CACurrentMediaTime's seconds.
__attribute__((weak)) int mb_latency_built(void) { return -1; }
__attribute__((weak)) void mb_latency_merged(int from, int to) { (void)from, (void)to; }
__attribute__((weak)) void mb_latency_presenting(id<CAMetalDrawable> d, int k, double p0, double p1, double p2,
                                                 double p3) {
  (void)d, (void)k, (void)p0, (void)p1, (void)p2, (void)p3;
}

static void present_probe(double ring, double upload_s, double drawable, double encode_s) {
  if (present_probing < 0) {
    const char *v = getenv("MBUI_PROBE");
    present_probing = v && v[0] == '1';
  }
  if (!present_probing && !mb_perf_on()) return;
  present_ms[0] += ring * 1000.0;
  present_ms[1] += upload_s * 1000.0;
  present_ms[2] += drawable * 1000.0;
  present_ms[3] += encode_s * 1000.0;
  if (++present_n < 240) return;
  char line[160];
  snprintf(line, sizeof line, "present avg: ring wait %.2f, upload %.2f, drawable wait %.2f, encode %.2f ms",
           present_ms[0] / present_n, present_ms[1] / present_n, present_ms[2] / present_n, present_ms[3] / present_n);
  if (present_probing) fprintf(stderr, "PROBE %s\n", line);
  mb_perf_note(line);
  present_n = 0;
  memset(present_ms, 0, sizeof present_ms);
}

// the texture the last frame is drawn again into for the CPU to read (read_last), kept while its size is
static id<MTLTexture> read_tex;

// What drawing holds, given back as the window stops being shown (mac_app.m tell_state: the window covered,
// minimized, hidden or the Mac asleep): Core Animation keeps the layer's drawables (three or four, each
// the window's size in pixels: 22 MB at 3024 × 1890), and the glass its levels. The drawables shrink to a pixel, which
// frees all but the one shown (Core Animation shows it on), and the levels go; a frame after makes what it needs again
// at full size (mb_render_set_size). (The driver's own memory, 30 to 100 MB of the footprint's "owned unmapped
// (graphics)", it gives back itself a second or two after the last frame: same_as_shown and the caret at rest are what
// stop the frames.)
void mb_render_trim(void) {
  if (!mlayer || CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(1, 1))) return;
  // (what the queue holds drawn first, and nothing of the GPU's still in flight uses what goes)
  present_drain();
  for (int i = 0; i < 3; i++) dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  for (int i = 0; i < 3; i++) dispatch_semaphore_signal(inflight);
  glass_free();
  glass_idle_frames = 0;
  // (and the read back's texture, the size of the last picture read: made again by the next read)
  read_tex = nil;
  // (and the canvas: the next frame drawn whole into one made again, not skipped as the same as before)
  canvas = nil;
  canvas_ok = 0;
  shown_ok = 0;
  dirty_told = dirty_whole = dirty_n = 0;
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  mlayer.drawableSize = CGSizeMake(1, 1);
  [CATransaction commit];
}

// Copies `src` into `dst` (a drawable's texture) with a render pass so `mlayer.framebufferOnly` stays YES.
static void copy_to_drawable(id<MTLCommandBuffer> cb, id<MTLTexture> src, id<MTLTexture> dst) {
  MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor renderPassDescriptor];
  rp.colorAttachments[0].texture = dst;
  rp.colorAttachments[0].loadAction = MTLLoadActionDontCare;
  rp.colorAttachments[0].storeAction = MTLStoreActionStore;
  id<MTLRenderCommandEncoder> e = [cb renderCommandEncoderWithDescriptor:rp];
  [e setRenderPipelineState:cpipe];
  [e setViewport:(MTLViewport){0, 0, (double)dst.width, (double)dst.height, 0, 1}];
  [e setFragmentTexture:src atIndex:0];
  [e drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
  [e endEncoding];
}

// How many frames were drawn and presented (scripts/apple_render_test.m: frames that took another's place are not).
static int present_drawn;
// How many frames handed to present_q were never drawn, each's place taken by a newer one as it waited
// (@hostapi.frames_dropped; the main thread's).
static int32_t present_dropped;

// Frame `fr` drawn for window `w` and presented: on present_q, or on the main thread once the queue is drained (`tx`:
// presented with the main thread's Core Animation transaction, once its commands are scheduled, as Core Animation
// asks; `check`: MBUI_PARTIAL_CHECK's comparison after). Returns whether it had a drawable.
static int draw_frame(MBRenderWin *w, MBFrame *fr, int tx, int check) {
  double p0 = CACurrentMediaTime();
  dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
  double p1 = CACurrentMediaTime();
  atlas_flush(fr->atlas_seq);
  at_w = fr->w;
  at_h = fr->h;
  at_scale = fr->scale;
  at_texs = fr->texs;
  at_through_n = fr->through_n;
  at_win = w;
  memcpy(at_through_tid, fr->through_tid, sizeof at_through_tid);
  double ad_dt = ad_next_dt(w);
  uint64_t ad_serial = ++w->ad_frame_serial;
  int32_t count = fr->count;
  double r = fr->bg[0], g = fr->bg[1], b = fr->bg[2];
  id<MTLBuffer> buf = ring_put(fr->inst, count, r, g, b);
  double e0 = CACurrentMediaTime();
  // A frame drawn whole (nothing said of its parts, all of it said, a picture missing from the last) with no glass in
  // it is drawn straight into the drawable once it is had: the canvas would only be drawn whole and copied again, a
  // pass reading and writing every pixel twice more (30-45 MB a frame of a Retina window, as it scrolls), and the
  // drawable, framebufferOnly, is all such a frame needs. The canvas then holds no frame: the next drawn in part is
  // drawn whole into it first (canvas_ok). Glass copies what is under it out of what it is drawn into (blur), which a
  // drawable that is only a framebuffer cannot be read for: a frame with glass goes through the canvas, as do frames
  // drawn in part.
  int tw = fr->tw, th = fr->th;
  int direct = !fr->glass && tw > 0 && th > 0 && (!fr->parts.told || fr->parts.whole || pictures_missing);
  // drawn into the canvas and committed before asking for the drawable, so the GPU draws the canvas while nextDrawable
  // waits on the swapchain and the drawable is held only for the final copy; a drawable of another size than the
  // canvas (a resize between) redraws the canvas at that size before copying
  int checked = 0;
  id<MTLCommandBuffer> cb = nil;
  if (direct) {
    w->cv_ok = 0;
  } else if (tw > 0 && th > 0) {
    ensure_canvas(w, tw, th);
    cb = [queue commandBuffer];
    checked = draw_parts(cb, w->cv, buf, count, r, g, b, w->cv_ok, &fr->parts, ad_dt, ad_serial);
    w->cv_ok = 1;
    if (checked != 0) [cb commit];
  }
  double p2 = CACurrentMediaTime();
  id<CAMetalDrawable> drawable = [w->layer nextDrawable];
  double p3 = CACurrentMediaTime();
  id<MTLCommandBuffer> pcb = [queue commandBuffer];
  if (drawable && direct) {
    encode(pcb, drawable.texture, mpipe, buf, count, r, g, b, 1, NULL, ad_dt, ad_serial);
    ad_rb_finish(pcb, at_win, ad_serial);
    pictures_missing = encode_missing;
  } else if (drawable) {
    int dw = (int)drawable.texture.width, dh = (int)drawable.texture.height;
    if (dw != tw || dh != th) {
      ensure_canvas(w, dw, dh);
      encode(pcb, w->cv, mpipe, buf, count, r, g, b, 1, NULL, ad_dt, ad_serial);
      ad_rb_finish(pcb, at_win, ad_serial);
      w->cv_ok = 0;
      checked = 0;
    }
    copy_to_drawable(pcb, w->cv, drawable.texture);
  }
  ad_finalize_frame(w, direct || checked < 0, ad_serial);
  at_win = nil;
  __block dispatch_semaphore_t sem = inflight;
  id<MTLCommandBuffer> ccb = checked != 0 ? cb : nil;
  [pcb addCompletedHandler:^(id<MTLCommandBuffer> done) {
    double g0 = ccb && ccb.GPUEndTime > ccb.GPUStartTime ? ccb.GPUEndTime - ccb.GPUStartTime : 0;
    double g1 = done.GPUEndTime > done.GPUStartTime ? done.GPUEndTime - done.GPUStartTime : 0;
    last_gpu = (g0 + g1) * 1000.0;
    dispatch_semaphore_signal(sem);
  }];
  if (drawable) mb_latency_presenting(drawable, fr->lat, p0, p1, p2, p3);
  if (drawable && tx) {
    [pcb commit];
    [pcb waitUntilScheduled];
    [drawable present];
  } else {
    if (drawable) [pcb presentDrawable:drawable];
    [pcb commit];
  }
  at_texs = nil;
  at_through_n = 0;
  glass_idle_tick(fr->glass);
  present_drawn++;
  present_probe(p1 - p0, e0 - p1, p3 - p2, (p2 - e0) + (CACurrentMediaTime() - p3));
  if (check && checked > 0) check_part(cb, checked, w);
  return drawable != nil;
}

// The frame waiting for window `w` drawn (present_q): the newest the main thread handed over.
static void present_job(MBRenderWin *w) {
  @autoreleasepool {
    os_unfair_lock_lock(&present_mu);
    MBFrame *fr = w->pending;
    w->pending = nil;
    w->queued = 0;
    if (fr && w->layer) atomic_store(&w->ad_drawing, 1);
    os_unfair_lock_unlock(&present_mu);
    // (none had: the window let go of first)
    if (!fr || !w->layer) return;
    if (!draw_frame(w, fr, 0, 0)) atomic_store(&w->missed, 1);
    atomic_store(&w->ad_drawing, 0);
  }
}

void mb_render_present(const double *inst, int32_t count, double r, double g, double b) {
  // a frame that put a native view elsewhere (apple_views.m: a page in a message, as the list scrolls) presented in
  // the transaction that puts it there (the frame's: mac_app.m drawFrame, ios_app.m tick), so the view and the hole it
  // shows through change on the same refresh. Presented by itself the drawable is shown once the GPU has drawn it,
  // apart from the view's move, which the frame's transaction takes to the screen: a refresh or two apart, the page
  // out of step with its hole as the list moved
  // (the views' frost of glass over them put where it shows now, with them: glass_through)
  // the frame as floats, its groups' headers drawn out (groups.h): made once, compared, handed over, kept
  float *f = next_room(count);
  mb_groups_floats(f, inst, count);
  int has_hole = glass_through(f, count);
  BOOL want_opaque = !has_hole;
  int opaque_changed = mlayer && mlayer.opaque != want_opaque;
  int with_views = (mb_views_take_moved() || opaque_changed) && !mlayer.presentsWithTransaction;
  // (the last frame handed over had no drawable: not the one shown)
  if (atomic_exchange(&rw->missed, 0)) shown_ok = 0;
  if (!opaque_changed && same_as_shown(f, count, r, g, b)) {
    // (what was said of it, nothing changed, not left for the next)
    dirty_told = dirty_whole = dirty_n = 0;
    through_n = 0;
    return;
  }
  MBFrame *fr = [MBFrame new];
  fr->count = count;
  fr->bg[0] = r; fr->bg[1] = g; fr->bg[2] = b;
  fr->w = vw; fr->h = vh; fr->scale = vscale;
  fr->tw = (int)mlayer.drawableSize.width;
  fr->th = (int)mlayer.drawableSize.height;
  // (whether it has glass, which copies what is drawn under it out of what it is drawn into: slot 20 negative)
  int has_ad = 0;
  for (int32_t i = 0; i < count; i++) {
    const float *b = f + (size_t)i * MB_INST;
    if (b[20] < 0.0f) fr->glass = 1;
    if (!has_ad && (int)(b[5] + 0.5f) == 6 && b[14] < -0.5f && !(b[7] <= 0.1f && b[11] < 0.12f)) has_ad = 1;
  }
  if (has_ad) atomic_store(&rw->ad_has_adaptive, 1);
  if (atomic_load(&rw->ad_settling) && rw->said.told && !rw->said.whole) {
    os_unfair_lock_lock(&present_mu);
    MBDirty sd = rw->ad_settle_dirty;
    os_unfair_lock_unlock(&present_mu);
    dirty_join(&rw->said, &sd);
  }
  fr->parts = rw->said;
  rw->said = (MBDirty){0};
  fr->through_n = through_n;
  memcpy(fr->through_tid, through_tid, sizeof through_tid);
  fr->atlas_seq = atlas_seq;
  fr->lat = mb_latency_built();
  through_n = 0;
  int streams = 0;
  for (int32_t i = 0; i < count && !streams; i++) streams = f[i * MB_INST + 20] > (float)MB_STREAM_TEX;
  if (mlayer.presentsWithTransaction || with_views || partial_checking()) {
    // drawn here, in the main thread's transaction, once the queue has drawn what it holds
    present_drain();
    if (opaque_changed) mlayer.opaque = want_opaque;
    if (with_views) mlayer.presentsWithTransaction = YES;
    fr->inst = f;
    int had = draw_frame(rw, fr, mlayer.presentsWithTransaction, 1);
    fr->inst = NULL;
    if (with_views) mlayer.presentsWithTransaction = NO;
    keep_last(count, r, g, b);
    shown_ok = had;
  } else {
    size_t n = (size_t)(count > 0 ? count : 0) * MB_INST * sizeof(float);
    fr->inst = pool_take(n > 0 ? n : sizeof(float), &fr->cap);
    if (n > 0) memcpy(fr->inst, f, n);
    fr->texs = frame_texs(f, count);
    keep_last(count, r, g, b);
    shown_ok = 1;
    MBRenderWin *w = rw;
    MBFrame *was;
    int merged = -1, lat = fr->lat;
    os_unfair_lock_lock(&present_mu);
    was = w->pending;
    if (was) {
      // (it takes the place of one not drawn yet: what that said differs is still to be drawn, the events that one
      // showed this one shows)
      dirty_join(&fr->parts, &was->parts);
      if (fr->glass) fr->parts.glass_closure = 1;
      if (was->tw != fr->tw || was->th != fr->th || was->scale != fr->scale) fr->parts.whole = fr->parts.told = 1;
      if (was->lat >= 0 && lat >= 0) merged = was->lat;
      else if (was->lat >= 0) fr->lat = was->lat;
    }
    w->pending = fr;
    if (was) present_dropped++;
    int go = !w->queued;
    w->queued = 1;
    os_unfair_lock_unlock(&present_mu);
    if (merged >= 0) mb_latency_merged(merged, lat);
    if (go) dispatch_async(present_q, ^{
      present_job(w);
    });
  }
  shown_w = vw;
  shown_h = vh;
  shown_scale = vscale;
  shown_streams = streams;
}

void mb_render_set_fixed_dt(double dt) {
  present_drain();
  ad_fixed_dt = dt > 0.0 ? dt : 0.0;
}

void mb_render_adaptive_reset(void) {
  present_drain();
  ad_forget(rw);
}

int mb_render_adaptive_settling(void) {
  return rw ? atomic_load(&rw->ad_settling) : 0;
}

int mb_render_adaptive_settling_of(int wid) {
  if (wid < 0 || wid >= MB_WINS) return 0;
  MBRenderWin *w = &render_wins[wid];
  if (atomic_load(&w->ad_settling)) return 1;
  if (atomic_load(&w->ad_has_adaptive)) {
    os_unfair_lock_lock(&present_mu);
    int q = w->queued;
    os_unfair_lock_unlock(&present_mu);
    if (q || atomic_load(&w->ad_drawing)) return 1;
  }
  return 0;
}

int mb_render_adaptive_step(int wid) {
  if (wid < 0 || wid >= MB_WINS) return 0;
  MBRenderWin *w = &render_wins[wid];
  if (!w->inst || !w->layer) return 0;
  if (!atomic_load(&w->ad_settling)) {
    if (atomic_load(&w->ad_has_adaptive)) {
      os_unfair_lock_lock(&present_mu);
      int q = w->queued;
      os_unfair_lock_unlock(&present_mu);
      if (q || atomic_load(&w->ad_drawing)) return 1;
    }
    return 0;
  }
  os_unfair_lock_lock(&present_mu);
  MBDirty sd = w->ad_settle_dirty;
  os_unfair_lock_unlock(&present_mu);
  if (!sd.told) return 0;
  MBFrame *fr = [MBFrame new];
  fr->count = w->count;
  fr->bg[0] = w->bg[0]; fr->bg[1] = w->bg[1]; fr->bg[2] = w->bg[2];
  fr->w = w->w; fr->h = w->h; fr->scale = w->scale;
  fr->tw = (int)w->layer.drawableSize.width;
  fr->th = (int)w->layer.drawableSize.height;
  fr->glass = 1;
  fr->parts = sd;
  fr->through_n = 0;
  fr->atlas_seq = atlas_seq;
  fr->lat = -1;
  size_t n = (size_t)(w->count > 0 ? w->count : 0) * MB_INST * sizeof(float);
  fr->inst = pool_take(n > 0 ? n : sizeof(float), &fr->cap);
  if (n > 0) memcpy(fr->inst, w->inst, n);
  fr->texs = frame_texs(w->inst, w->count);
  os_unfair_lock_lock(&present_mu);
  MBFrame *was = w->pending;
  if (was) dirty_join(&fr->parts, &was->parts);
  w->pending = fr;
  int go = !w->queued;
  w->queued = 1;
  os_unfair_lock_unlock(&present_mu);
  if (go) dispatch_async(present_q, ^{
    present_job(w);
  });
  return 1;
}

// MBUI_SAFE's bands (mac_app.m), in points, and their ground
static double band_top, band_bottom;
static uint32_t band_ground;

void mb_render_set_bands(double top, double bottom, uint32_t ground) {
  band_top = top;
  band_bottom = bottom;
  band_ground = ground;
}

// Instances `f` (`count` of them, as a frame's floats are) drawn on the ground `bg` into a texture the CPU reads, at
// `sw` × `sh` points, `scale` pixels a point, and its pixels: BGRA, premultiplied, rows from the top, *pw × *ph; the
// caller frees them. On the main thread, what present_q holds drawn first (its state is then the main thread's), every
// glyph kept put in, no native view's frost through it, the pictures' textures as they are now.
// ad_mode: 1 = update adaptive state (film/read), 0 = read-only (snapshot/drawn_pixels), -1 = stateless (pixels_of)
static uint8_t *read_of(const float *f, int32_t count, const double bg[3], double alpha, double sw, double sh,
                        double scale, int ad_mode, int *pw, int *ph) {
  present_drain();
  atlas_flush(UINT64_MAX);
  at_w = sw;
  at_h = sh;
  at_scale = scale;
  at_texs = nil;
  at_through_n = 0;
  at_win = ad_mode < 0 ? NULL : rw;
  double ad_dt = ad_mode > 0 ? ad_next_dt(at_win) : -1.0;
  uint64_t ad_serial = (ad_mode > 0 && at_win) ? ++at_win->ad_frame_serial : 0;
  int w = (int)round(sw * scale), h = (int)round(sh * scale);
  if (!read_tex || (int)read_tex.width != w || (int)read_tex.height != h) {
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
    td.usage = MTLTextureUsageRenderTarget;
#if TARGET_OS_OSX
    td.storageMode = MTLStorageModeManaged;
#else
    td.storageMode = MTLStorageModeShared;
#endif
    read_tex = [dev newTextureWithDescriptor:td];
  }
  id<MTLTexture> tex = read_tex;
  id<MTLBuffer> buf = [dev newBufferWithBytes:f length:(count > 0 ? count : 1) * MB_INST * sizeof(float) options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> cb = [queue commandBuffer];
  encode(cb, tex, rpipe_off, buf, count, bg[0], bg[1], bg[2], alpha, NULL, ad_dt, ad_serial);
  ad_rb_finish(cb, at_win, ad_serial);
  if (ad_mode > 0 && at_win) ad_finalize_frame(at_win, 1, ad_serial);
  at_win = NULL;
#if TARGET_OS_OSX
  id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
  [bl synchronizeResource:tex];
  [bl endEncoding];
#endif
  [cb commit];
  [cb waitUntilCompleted];
  size_t bpr = (size_t)w * 4;
  uint8_t *px = malloc(bpr * h);
  [tex getBytes:px bytesPerRow:bpr fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
  *pw = w;
  *ph = h;
  return px;
}

// What a texture the GPU keeps (a canvas: private) holds, once what is drawn into it is done, read back as read_of
// reads: the caller frees it.
static uint8_t *read_texture(id<MTLTexture> src, int *pw, int *ph) {
  present_drain();
  int w = (int)src.width, h = (int)src.height;
  uint8_t *px = malloc((size_t)w * h * 4);
  @autoreleasepool {
    MTLTextureDescriptor *td = [MTLTextureDescriptor
        texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm width:w height:h mipmapped:NO];
#if TARGET_OS_OSX
    td.storageMode = MTLStorageModeManaged;
#else
    td.storageMode = MTLStorageModeShared;
#endif
    id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    id<MTLBlitCommandEncoder> bl = [cb blitCommandEncoder];
    [bl copyFromTexture:src sourceSlice:0 sourceLevel:0 sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake(w, h, 1) toTexture:tex destinationSlice:0 destinationLevel:0
      destinationOrigin:MTLOriginMake(0, 0, 0)];
#if TARGET_OS_OSX
    [bl synchronizeResource:tex];
#endif
    [bl endEncoding];
    [cb commit];
    [cb waitUntilCompleted];
    [tex getBytes:px bytesPerRow:(size_t)w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
  }
  *pw = w;
  *ph = h;
  return px;
}

// The window's last frame (keep_last's) drawn again at the size set (mb_render_set_size), read back as read_of reads.
static uint8_t *read_last(int *pw, int *ph) {
  return read_of(last_inst, last_count, last_bg, 1, vw, vh, vscale, 0, pw, ph);
}

// A frame drawn offscreen and read back (a film's, mbui/src/film): `inst` as mb_render_present takes them, kept as
// the last frame, and its pixels as read_of (updating adaptive state) gives them.
uint8_t *mb_render_read(const double *inst, int32_t count, double r, double g, double b, int *pw, int *ph) {
  @autoreleasepool {
    present_drain();
    next_as_is(inst, count);
    keep_last(count, r, g, b);
    return read_of(last_inst, last_count, last_bg, 1, vw, vh, vscale, 1, pw, ph);
  }
}

uint8_t *mb_render_read_step(int *pw, int *ph) {
  @autoreleasepool {
    if (!last_inst) return NULL;
    return read_of(last_inst, last_count, last_bg, 1, vw, vh, vscale, 1, pw, ph);
  }
}

// The frame presented last drawn again (read_last), and its pixels in the rectangle x, y, w × h (from its top left)
// into `out` as RGBA, premultiplied, rows from the top (host_native.mbt drawn_pixels): 1 when read, 0 where the
// rectangle is not all in the frame or none was presented.
int32_t mb_render_drawn_pixels(int32_t x, int32_t y, int32_t w, int32_t h, moonbit_bytes_t out) {
  if (!dev || !last_inst || w <= 0 || h <= 0 || x < 0 || y < 0) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  @autoreleasepool {
    int fw, fh;
    uint8_t *px = read_last(&fw, &fh);
    if (x + w > fw || y + h > fh) {
      free(px);
      return 0;
    }
    for (int r = 0; r < h; r++) {
      const uint8_t *s = px + ((size_t)(y + r) * fw + x) * 4;
      uint8_t *d = out + (size_t)r * w * 4;
      for (int k = 0; k < w; k++, s += 4, d += 4) {
        d[0] = s[2];
        d[1] = s[1];
        d[2] = s[0];
        d[3] = s[3];
      }
    }
    free(px);
  }
  return 1;
}

// Instances never presented (a shot's, mbui/src/ui/shot.mbt) drawn as a frame is, but `scale` pixels a point into a
// picture of their own w × h (their 0, 0 its top left), on the ground r, g, b, and its pixels into `out` as
// mb_render_drawn_pixels gives the frame's (the last frame kept as it was, the size frames are drawn at put back):
// 1 when read.
int32_t mb_render_pixels_of(const double *inst, int32_t count, double r, double g, double b, double scale, int32_t w,
                            int32_t h, moonbit_bytes_t out) {
  if (!dev || count < 0 || !(scale > 0) || w <= 0 || h <= 0) return 0;
  if ((size_t)Moonbit_array_length(out) < (size_t)w * h * 4) return 0;
  int ok = 0;
  @autoreleasepool {
    size_t n = (size_t)count * MB_INST;
    float *f = malloc((n > 0 ? n : MB_INST) * sizeof(float));
    for (size_t i = 0; i < n; i++) f[i] = (float)inst[i];
    double bg[3] = {r, g, b};
    // (drawn as a frame of that size is)
    int fw, fh;
    uint8_t *px = read_of(f, count, bg, 1, w / scale, h / scale, scale, -1, &fw, &fh);
    free(f);
    if (fw == w && fh == h) {
      for (int k = 0; k < h; k++) {
        const uint8_t *s = px + (size_t)k * fw * 4;
        uint8_t *d = out + (size_t)k * w * 4;
        for (int j = 0; j < w; j++, s += 4, d += 4) {
          d[0] = s[2];
          d[1] = s[1];
          d[2] = s[0];
          d[3] = s[3];
        }
      }
      ok = 1;
    }
    free(px);
  }
  return ok;
}

// Pixels `px` (read_of's, w × h, freed here) into a PNG at `path`, the native views under them and the bands round
// them as the window shows them.
static int snapshot_of(uint8_t *px, int w, int h, const char *path) {
  size_t bpr = (size_t)w * 4;
  CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
  CGContextRef ctx = CGBitmapContextCreate(px, w, h, 8, bpr, cs,
      kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
  CGImageRef img = CGBitmapContextCreateImage(ctx);
  if (mb_views_count() > 0) {
    // the native views' content under the canvas, seen through its holes
    CGContextRef under = CGBitmapContextCreate(NULL, w, h, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    double view_scale = mlayer && mlayer.contentsScale > 0 ? mlayer.contentsScale : vscale;
    mb_views_draw_under(under, view_scale);
    CGContextDrawImage(under, CGRectMake(0, 0, w, h), img);
    CGImageRelease(img);
    img = CGBitmapContextCreateImage(under);
    CGContextRelease(under);
  }
  if (band_top > 0 || band_bottom > 0) {
    // the window as it shows: the bands above and under the app's view in their ground
    int bt = (int)round(band_top * vscale), bb = (int)round(band_bottom * vscale);
    int fh = h + bt + bb;
    CGContextRef whole = CGBitmapContextCreate(NULL, w, fh, 8, bpr, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextSetRGBFillColor(whole, ((band_ground >> 16) & 0xFF) / 255.0, ((band_ground >> 8) & 0xFF) / 255.0,
                             (band_ground & 0xFF) / 255.0, 1);
    CGContextFillRect(whole, CGRectMake(0, 0, w, fh));
    // (a bitmap context's y up: the bottom band first)
    CGContextDrawImage(whole, CGRectMake(0, bb, w, h), img);
    CGImageRelease(img);
    img = CGBitmapContextCreateImage(whole);
    CGContextRelease(whole);
  }
  CFURLRef url = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)path, strlen(path), false);
  CGImageDestinationRef dst = CGImageDestinationCreateWithURL(url, CFSTR("public.png"), 1, NULL);
  int ok = 0;
  if (dst) {
    CGImageDestinationAddImage(dst, img, NULL);
    ok = CGImageDestinationFinalize(dst);
    CFRelease(dst);
  }
  CFRelease(url);
  CGImageRelease(img);
  CGContextRelease(ctx);
  CGColorSpaceRelease(cs);
  free(px);
  return ok;
}

int mb_render_snapshot(const char *path) {
  int w, h;
  uint8_t *px = read_last(&w, &h);
  return snapshot_of(px, w, h, path);
}

// The same last frame over a transparent ground, for an image used in another composition. Clear RGB to zero with
// alpha so the readback remains premultiplied; the window and video paths continue to clear opaque.
int mb_render_snapshot_transparent(const char *path) {
  int w, h;
  const double clear[3] = {0, 0, 0};
  uint8_t *px = read_of(last_inst, last_count, clear, 0, vw, vh, vscale, 0, &w, &h);
  return snapshot_of(px, w, h, path);
}

static id<MTLTexture> off_target;

// The offscreen target as its frames left it (not the last frame drawn again: what drawing only the parts that
// differ made of it, mbui-render's MBUI_DL_FROM), as a PNG.
int mb_render_snapshot_drawn(const char *path) {
  if (!off_target) return 0;
  int w, h;
  uint8_t *px = read_texture(off_target, &w, &h);
  return snapshot_of(px, w, h, path);
}

// Without a window (the bench, src/bench): the renderer with no layer, and
// frames drawn into a texture kept across frames, the size a window's
// drawable would be, as nanoui's hill-climb draws its own (off_target, above);
// whether it holds the frame drawn last (partial redraw: draw_parts).
static int off_ok;

void mb_render_init_offscreen(double w, double h, double scale) {
  mb_render_init(nil);
  // (with every kind's pipeline: what is drawn here is what a window draws once they are made)
  dispatch_group_wait(kinds_made, DISPATCH_TIME_FOREVER);
  mb_render_set_size(w, h, scale);
  mb_text_set_scale(scale);
  MTLTextureDescriptor *td = [MTLTextureDescriptor
      texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                   width:(NSUInteger)round(w * scale)
                                  height:(NSUInteger)round(h * scale)
                               mipmapped:NO];
  td.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
  td.storageMode = MTLStorageModePrivate;
  off_target = [dev newTextureWithDescriptor:td];
}

// Draws a frame into the offscreen texture as a window's frame is drawn
// (the ring of buffers, one command buffer), waits for it and times it:
// out[0] the CPU time of uploading and encoding it, out[1] its GPU time
// (the command buffer's timestamps), in ms.
void mb_render_draw_timed(const double *inst, int32_t count, double r, double g, double b, double *out) {
  @autoreleasepool {
    present_drain();
    dispatch_semaphore_wait(inflight, DISPATCH_TIME_FOREVER);
    double t0 = CACurrentMediaTime();
    next_as_is(inst, count);
    keep_last(count, r, g, b);
    atlas_flush(UINT64_MAX);
    at_w = vw;
    at_h = vh;
    at_scale = vscale;
    at_texs = nil;
    at_through_n = 0;
    at_win = rw;
    double ad_dt = ad_next_dt(rw);
    uint64_t ad_serial = ++rw->ad_frame_serial;
    id<MTLBuffer> buf = ring_put(last_inst, count, r, g, b);
    id<MTLCommandBuffer> cb = [queue commandBuffer];
    // (only the parts said to differ, as a window's canvas is drawn: the target is kept across frames too)
    MBDirty said = rw->said;
    rw->said = (MBDirty){0};
    int parts_n = draw_parts(cb, off_target, buf, count, r, g, b, off_ok, &said, ad_dt, ad_serial);
    ad_finalize_frame(rw, parts_n < 0, ad_serial);
    at_win = NULL;
    off_ok = 1;
    [cb commit];
    double t1 = CACurrentMediaTime();
    [cb waitUntilCompleted];
    out[0] = (t1 - t0) * 1000.0;
    out[1] = (cb.GPUEndTime - cb.GPUStartTime) * 1000.0;
    dispatch_semaphore_signal(inflight);
  }
}

// The GPU's time for the last frame presented that it finished (ms).
double mb_host_gpu_ms(void) { return last_gpu; }

int32_t mb_host_frames_dropped(void) { return present_dropped; }
