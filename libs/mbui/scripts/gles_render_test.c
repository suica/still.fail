// src/host/gles_render.h's tests on the window's way (not mbui-render's offscreen one: Android's surface, Linux's
// window), in OpenGL ES 3 on EGL's surfaceless platform (Mesa's llvmpipe where there is no GPU), a framebuffer of the
// test's own standing for the surface (target_fb): a frame drawn whole goes straight onto it, no canvas made; one said
// to differ in parts is drawn into the canvas and shown, the surface then the same to the byte as the frame drawn
// whole; the blur under glass kept while what is under it is the same, made again once it is not, never kept while a
// picture under it had no texture yet; a group the host keeps drawn out to the float the app's own instance would be;
// a frame handed over from another thread (frame_mail.h) taken only to read back leaving the next drawn whole; three
// groups of glass on one screen each keeping its own blur, made again only for the one something moved under.
//   cc -Wall -Wno-unused-function -I src/host -I "$MOON_HOME/include" scripts/gles_render_test.c
//     $(pkg-config --cflags --libs epoxy zlib) -lm -o out/gles_render_test && out/gles_render_test
#include <epoxy/gl.h>
#include <epoxy/egl.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>
#include "moonbit.h"
#include "corner_sl.h"

#define LOG(...) (fprintf(stderr, "gles_render_test: " __VA_ARGS__), fputc('\n', stderr))
#define MB_STREAM_TEX 4194304
#define MB_VIEW_TEX 8388608

// picture 1's texture: none (not decoded yet) till a test makes one
static GLuint picture_one;
static GLuint image_tex(int id) { return id == 1 ? picture_one : 0; }
static void view_parts_in(int tid, int32_t start, int32_t end) { (void)tid, (void)start, (void)end; }

#include "gles_render.h"
#include "frame_mail.h"

static int failed;

#define CHECK(c)                                                      \
  do {                                                                \
    if (!(c)) {                                                       \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                     \
    }                                                                 \
  } while (0)

// the surface: 100 × 75 points, 2 pixels a point
#define W 100
#define H 75
#define S 2

// An instance: a rect at x, y, w × h of colour (r, g, b), kind `kind`, image `tid`, its clip the window's.
static void rect_at(double *d, double x, double y, double w, double h, int kind, double r, double g, double b,
                    double tid) {
  memset(d, 0, MB_INST * sizeof(double));
  d[0] = x;
  d[1] = y;
  d[2] = w;
  d[3] = h;
  d[5] = kind;
  d[8] = r;
  d[9] = g;
  d[10] = b;
  d[11] = 1;
  d[18] = W;
  d[19] = H;
  d[20] = tid;
}

// What framebuffer `fb` holds (fb_w × fb_h, RGBA): the caller frees it.
static unsigned char *pixels_of_fb(GLuint fb) {
  unsigned char *px = malloc((size_t)fb_w * fb_h * 4);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, fb);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, fb_w, fb_h, GL_RGBA, GL_UNSIGNED_BYTE, px);
  return px;
}

// The surface the same to the byte as the frame kept drawn whole again (draw_kept_read, as drawn_pixels reads it).
// (the blurs kept by glass shown again there as they are: surface_as_fresh makes them anew)
static int surface_as_whole(GLuint surface) {
  unsigned char *shown = pixels_of_fb(surface);
  draw_kept_read();
  unsigned char *whole = pixels_of_fb(read_fb);
  glBindFramebuffer(GL_FRAMEBUFFER, surface);
  int same = memcmp(shown, whole, (size_t)fb_w * fb_h * 4) == 0;
  free(shown);
  free(whole);
  return same;
}

// The surface the same to the byte as the frame kept drawn whole again with no blur kept, each made anew.
static int surface_as_fresh(GLuint surface) {
  glass_forget();
  return surface_as_whole(surface);
}

// A frame handed over from the thread that makes it (frame_mail.h: Android's app thread), what it says differs a
// part x, y, w × h of it.
static void hand(const double *inst, int32_t count, double x, double y, double w, double h) {
  // (said as it is painted, before it is presented: mb_host_render_dirty)
  fm_said(x, y, w, h);
  float *f = fm_present(gl_frame_floats(count), count, 0.1, 0.2, 0.3, W, H, S);
  mb_groups_floats(f, inst, count);
  CHECK(fm_publish());
}

// The frame handed over taken (Android's Native.take): to be drawn (and drawn, Native.draw), or only read back.
static void take(int shown) {
  handed_frame got;
  CHECK(fm_take(&got));
  fm_keep(&got, shown);
  if (shown) gl_present_kept(kept_count, kept_r, kept_g, kept_b);
}

int main(void) {
  EGLDisplay d = eglGetPlatformDisplayEXT(EGL_PLATFORM_SURFACELESS_MESA, EGL_DEFAULT_DISPLAY, NULL);
  if (d == EGL_NO_DISPLAY || !eglInitialize(d, NULL, NULL)) {
    LOG("no EGL display (surfaceless)");
    return 1;
  }
  eglBindAPI(EGL_OPENGL_ES_API);
  static const EGLint want[] = {EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES3_BIT, EGL_NONE};
  EGLConfig cfg = NULL;
  EGLint n = 0;
  eglChooseConfig(d, want, &cfg, 1, &n);
  static const EGLint attrs[] = {EGL_CONTEXT_MAJOR_VERSION, 3, EGL_CONTEXT_MINOR_VERSION, 0, EGL_NONE};
  EGLContext ctx = eglCreateContext(d, n > 0 ? cfg : EGL_NO_CONFIG_KHR, EGL_NO_CONTEXT, attrs);
  if (ctx == EGL_NO_CONTEXT || !eglMakeCurrent(d, EGL_NO_SURFACE, EGL_NO_SURFACE, ctx)) {
    LOG("no OpenGL ES 3 context");
    return 1;
  }
  gl_setup();
  // the surface: a framebuffer of the test's, drawn into as the window's is (offscreen 0)
  fb_w = W * S;
  fb_h = H * S;
  cur_w = W;
  cur_h = H;
  cur_scale = S;
  GLuint surface_tex, surface;
  glGenTextures(1, &surface_tex);
  glBindTexture(GL_TEXTURE_2D, surface_tex);
  glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
  glGenFramebuffers(1, &surface);
  glBindFramebuffer(GL_FRAMEBUFFER, surface);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, surface_tex, 0);
  CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
  target_fb = surface;
  CHECK(offscreen == 0);

  // A frame drawn whole goes straight onto the surface: no canvas made, none holding a frame.
  double two[2 * MB_INST];
  rect_at(two, 10, 10, 20, 20, 0, 0.9, 0.2, 0.1, 0);
  rect_at(two + MB_INST, 60, 40, 20, 20, 0, 0.1, 0.8, 0.3, 0);
  gl_present(two, 2, 0.1, 0.2, 0.3);
  CHECK(canvas_fb == 0);
  CHECK(canvas_ok == 0);
  CHECK(surface_as_whole(surface));

  // One said to differ in a part: the canvas made, drawn whole into it first (it held no frame), then shown; the next
  // drawn in its parts alone. The surface each time the same to the byte as the frame drawn whole.
  two[0] = 12;
  mb_host_render_dirty(8, 8, 26, 24);
  gl_present(two, 2, 0.1, 0.2, 0.3);
  CHECK(canvas_fb != 0);
  CHECK(canvas_ok == 1);
  CHECK(surface_as_whole(surface));
  two[0] = 14;
  two[MB_INST + 1] = 44;
  mb_host_render_dirty(10, 8, 26, 24);
  mb_host_render_dirty(58, 38, 24, 28);
  gl_present(two, 2, 0.1, 0.2, 0.3);
  CHECK(canvas_ok == 1);
  CHECK(surface_as_whole(surface));
  // (and one whole again after: straight onto the surface, the canvas left holding no frame)
  two[0] = 16;
  gl_present(two, 2, 0.1, 0.2, 0.3);
  CHECK(canvas_ok == 0);
  CHECK(surface_as_whole(surface));

  // Frames handed over from another thread (frame_mail.h, Android's two), drawn in their parts as they say. One taken
  // only to read back (Android's glSync, the app waiting on a pixel of it) is never on the surface: what it said differs
  // is not what the next drawn goes by, nor is anything left of it there, and the canvas no longer holds the frame
  // before. So the next drawn, which says only its own part, is drawn whole into the canvas: the surface then is what it
  // is drawn whole, the part the one read back changed too. So too where the one read back is drawn again first
  // (Native.redraw: a native view's picture changed).
  hand(two, 2, 10, 8, 30, 30);
  take(1);
  CHECK(surface_as_whole(surface));
  two[MB_INST + 1] = 46;
  hand(two, 2, 58, 38, 24, 30);
  take(1);
  CHECK(canvas_ok == 1);
  CHECK(surface_as_whole(surface));
  two[0] = 20;
  hand(two, 2, 10, 8, 32, 24);
  take(0);
  draw_kept_read();
  glBindFramebuffer(GL_FRAMEBUFFER, surface);
  CHECK(canvas_ok == 0);
  CHECK(dirty_told == 0 && dirty_whole == 0 && dirty_n == 0);
  two[MB_INST + 1] = 40;
  hand(two, 2, 58, 38, 24, 30);
  take(1);
  CHECK(surface_as_whole(surface));
  two[0] = 24;
  hand(two, 2, 18, 8, 28, 24);
  take(0);
  draw_kept_read();
  draw_kept();
  CHECK(dirty_told == 0);
  two[MB_INST + 1] = 44;
  hand(two, 2, 58, 38, 24, 30);
  take(1);
  CHECK(surface_as_whole(surface));
  // (and the canvas holds the frame again: the one after drawn in its parts alone, the same)
  two[MB_INST + 1] = 42;
  hand(two, 2, 58, 38, 24, 30);
  take(1);
  CHECK(canvas_ok == 1);
  CHECK(surface_as_whole(surface));

  // The blur under glass kept while what is drawn under it is the same: what is over it changing makes none again;
  // what is under it changing does.
  double g3[3 * MB_INST];
  rect_at(g3, 10, 10, 60, 40, 0, 0.9, 0.1, 0.1, 0);
  rect_at(g3 + MB_INST, 20, 20, 40, 30, 5, 1, 1, 1, -2);
  g3[MB_INST + 7] = 6;
  g3[MB_INST + 11] = 0.5;
  rect_at(g3 + 2 * MB_INST, 80, 60, 10, 10, 0, 0.1, 0.1, 0.9, 0);
  int made = blurs_made;
  gl_present(g3, 3, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made + 1);
  CHECK(kept_ok == 1);
  g3[2 * MB_INST + 0] = 84;  // over the glass: moved
  gl_present(g3, 3, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made + 1);
  CHECK(kept_ok == 1);
  g3[0] = 12;  // under it: moved
  gl_present(g3, 3, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made + 2);
  CHECK(kept_ok == 1);

  // A picture under it with no texture yet (drawn without it): that blur is not kept as what is under it; once the
  // picture has its texture, it is made and kept.
  double p3[3 * MB_INST];
  memcpy(p3, g3, sizeof p3);
  rect_at(p3, 10, 10, 60, 40, 4, 1, 1, 1, 1);
  p3[12] = 0;
  p3[13] = 0;
  p3[14] = 1;
  p3[15] = 1;
  gl_present(p3, 3, 0.1, 0.2, 0.3);
  CHECK(kept_ok == 0);
  CHECK(pictures_missing == 1);
  static const unsigned char px[16] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255};
  glGenTextures(1, &picture_one);
  glBindTexture(GL_TEXTURE_2D, picture_one);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  made = blurs_made;
  p3[2 * MB_INST + 0] = 86;
  gl_present(p3, 3, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made + 1);
  CHECK(kept_ok == 1);
  CHECK(pictures_missing == 0);

  // Three groups of glass on one screen (frosted at the top, liquid in the middle, frosted at the foot, each with
  // something of its own under it, a caret over all): each keeps its own blur. A frame where only what is over them
  // moves makes none; one where something moves under the middle one alone makes that one's again, the others kept.
  // The surface each time the same to the byte as the frame drawn whole with every blur made anew.
  double s3[8 * MB_INST];
  rect_at(s3, 0, 0, W, H, 0, 0.95, 0.95, 0.9, 0);
  rect_at(s3 + 1 * MB_INST, 8, 4, 26, 8, 0, 0.9, 0.1, 0.1, 0);
  rect_at(s3 + 2 * MB_INST, 5, 2, 36, 10, 5, 1, 1, 1, -2);
  s3[2 * MB_INST + 7] = 2;
  s3[2 * MB_INST + 11] = 0.5;
  rect_at(s3 + 3 * MB_INST, 62, 32, 20, 8, 0, 0.1, 0.7, 0.2, 0);
  rect_at(s3 + 4 * MB_INST, 60, 30, 30, 12, 6, 1, 1, 1, -3);
  s3[4 * MB_INST + 4] = 6;
  s3[4 * MB_INST + 7] = 2;
  s3[4 * MB_INST + 11] = 0.3;
  s3[4 * MB_INST + 21] = 2;
  s3[4 * MB_INST + 23] = 1;
  rect_at(s3 + 5 * MB_INST, 10, 60, 25, 6, 0, 0.2, 0.2, 0.9, 0);
  rect_at(s3 + 6 * MB_INST, 5, 57, 40, 12, 5, 1, 1, 1, -4);
  s3[6 * MB_INST + 7] = 2;
  s3[6 * MB_INST + 11] = 0.5;
  rect_at(s3 + 7 * MB_INST, 90, 65, 2, 6, 0, 0, 0, 0, 0);
  made = blurs_made;
  gl_present(s3, 8, 0.1, 0.2, 0.3);
  LOG("three groups, first frame: %d blurs", blurs_made - made);
  CHECK(blurs_made == made + 3);
  CHECK(surface_as_fresh(surface));
  for (int i = 0; i < 3; i++) {
    s3[7 * MB_INST + 1] = 62 + i;  // the caret: moved
    made = blurs_made;
    gl_present(s3, 8, 0.1, 0.2, 0.3);
    LOG("three groups, the caret moved: %d blurs", blurs_made - made);
    CHECK(blurs_made == made);
    CHECK(kept_ok == 1);
    CHECK(surface_as_fresh(surface));
  }
  s3[3 * MB_INST + 0] = 64;  // under the liquid glass alone: moved
  made = blurs_made;
  gl_present(s3, 8, 0.1, 0.2, 0.3);
  LOG("three groups, what is under the middle one moved: %d blurs", blurs_made - made);
  CHECK(blurs_made == made + 1);
  CHECK(surface_as_fresh(surface));
  s3[7 * MB_INST + 1] = 60;
  made = blurs_made;
  gl_present(s3, 8, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made);
  CHECK(surface_as_fresh(surface));
  s3[1 * MB_INST + 0] = 9;  // under the top one: moved, that one's alone made again
  made = blurs_made;
  gl_present(s3, 8, 0.1, 0.2, 0.3);
  CHECK(blurs_made == made + 1);
  CHECK(surface_as_fresh(surface));

  // Fourteen independent glass groups of mixed sizes and blur radii on one screen: all 14 stay cached when only the
  // top-level caret moves (blurs_made delta == 0) and match a fresh render byte-for-byte.
  {
    double g14[16 * MB_INST];
    static const double blurs[4] = {1.0, 3.0, 7.0, 16.0};
    rect_at(g14, 0, 0, W, H, 0, 0.92, 0.90, 0.88, 0);
    for (int i = 0; i < 14; i++) {
      int col = i % 7, row = i / 7;
      double gx = 2 + col * 13;
      double gy = 2 + row * 32;
      double gw = 8 + i;
      double gh = 6 + i;
      double *d = g14 + (i + 1) * MB_INST;
      rect_at(d, gx, gy, gw, gh, 5, 1, 1, 1, -(101 + i));
      d[7] = blurs[i % 4];
      d[11] = 0.4;
    }
    rect_at(g14 + 15 * MB_INST, 92, 66, 2, 6, 0, 0, 0, 0, 0);
    glass_free();
    made = blurs_made;
    gl_present(g14, 16, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 14);
    CHECK(surface_as_whole(surface));
    g14[15 * MB_INST + 0] = 94;  // only top-level caret moves
    made = blurs_made;
    gl_present(g14, 16, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made);
    CHECK(kept_ok == 1);
    CHECK(surface_as_fresh(surface));
  }

  // What drawing holds beyond its frames given back: the trim lets go of glass's textures and the read back's
  // framebuffer; glass's textures go once MB_GLASS_IDLE frames in a row drew none. Each made again as it is next
  // needed, the surface then the same to the byte as the frame drawn whole.
  {
    double g1[2 * MB_INST];
    rect_at(g1, 10, 10, 40, 20, 0, 0.9, 0.1, 0.1, 0);
    rect_at(g1 + MB_INST, 5, 5, 50, 25, 6, 1, 1, 1, -5);
    g1[MB_INST + 4] = 6;
    g1[MB_INST + 7] = 2;
    g1[MB_INST + 11] = 0.3;
    g1[MB_INST + 21] = 2;
    g1[MB_INST + 23] = 1;
    glass_forget();
    gl_present(g1, 2, 0.1, 0.2, 0.3);
    CHECK(lv[0].t != 0 && lv_w > 0);
    CHECK(slots[0].bt != 0);
    CHECK(surface_as_fresh(surface));
    // the same capture frosted (kind 5), kept in the same slot
    g1[MB_INST + 5] = 5;
    g1[0] = 11;
    glass_forget();
    gl_present(g1, 2, 0.1, 0.2, 0.3);
    CHECK(slots[0].bt != 0);
    CHECK(surface_as_fresh(surface));

    CHECK(read_fb != 0);
    mb_render_trim();
    CHECK(read_fb == 0 && read_tex == 0);
    CHECK(lv[0].t == 0 && lv[4].t == 0 && lv_w == 0 && lv_h == 0);
    for (int i = 0; i < MB_GLASS_SLOTS; i++) CHECK(slots[i].bt == 0 && slots[i].under == NULL);
    g1[0] = 12;
    made = blurs_made;
    gl_present(g1, 2, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 1);
    CHECK(lv[0].t != 0);
    CHECK(surface_as_fresh(surface));

    // frames with no glass: glass's textures kept till the MB_GLASS_IDLE-th, then let go
    double plain[MB_INST];
    rect_at(plain, 10, 10, 40, 20, 0, 0.9, 0.1, 0.1, 0);
    for (int i = 1; i <= MB_GLASS_IDLE; i++) {
      plain[0] = 10 + i % 20;
      gl_present(plain, 1, 0.1, 0.2, 0.3);
      if (i == MB_GLASS_IDLE - 1) CHECK(lv[0].t != 0 && slots[0].bt != 0);
    }
    CHECK(lv[0].t == 0 && lv_w == 0);
    for (int i = 0; i < MB_GLASS_SLOTS; i++) CHECK(slots[i].bt == 0);
    g1[0] = 13;
    made = blurs_made;
    gl_present(g1, 2, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 1);
    CHECK(surface_as_fresh(surface));
    // a frame with glass among those without keeps them: the count starts again
    for (int i = 1; i < MB_GLASS_IDLE; i++) {
      plain[0] = 10 + i % 20;
      gl_present(plain, 1, 0.1, 0.2, 0.3);
    }
    g1[0] = 14;
    gl_present(g1, 2, 0.1, 0.2, 0.3);
    for (int i = 1; i < MB_GLASS_IDLE; i++) {
      plain[0] = 10 + i % 20;
      gl_present(plain, 1, 0.1, 0.2, 0.3);
    }
    CHECK(lv[0].t != 0);
  }

  // Unmerged liquid glass (kind 6, a[23] <= 0):
  // (1) single shape with merge=0 (tight quad + direct sd_rr) matches merge=1e-7 (merged_liquid + sd_group, same float32 quad bounds) byte-for-byte;
  // (2) two unmerged liquid shapes separated by a shadow (kind 2) sharing one capture make only 1 blur and preserve each
  //     instance's own spot, matching separate captures byte-for-byte at k == 0.
  {
    double eq[2 * MB_INST];
    rect_at(eq, 0, 0, W, H, 0, 0.85, 0.30, 0.20, 0);
    rect_at(eq + MB_INST, 18, 22, 54, 24, 6, 1, 1, 1, -9);
    eq[MB_INST + 4] = 12;
    eq[MB_INST + 6] = 1;
    eq[MB_INST + 7] = 2;
    eq[MB_INST + 11] = 0.25;
    eq[MB_INST + 12] = 0.8;
    eq[MB_INST + 13] = 8;
    eq[MB_INST + 14] = 0;
    eq[MB_INST + 15] = 1;
    eq[MB_INST + 21] = 4;
    eq[MB_INST + 22] = 0.2;
    eq[MB_INST + 23] = 0;
    glass_forget();
    gl_present(eq, 2, 0.1, 0.2, 0.3);
    unsigned char *px_single = pixels_of_fb(surface);

    eq[MB_INST + 23] = 1e-7;
    glass_forget();
    gl_present(eq, 2, 0.1, 0.2, 0.3);
    unsigned char *px_merged = pixels_of_fb(surface);
    CHECK(memcmp(px_single, px_merged, (size_t)fb_w * fb_h * 4) == 0);
    free(px_single);
    free(px_merged);

    double lq[5 * MB_INST];
    rect_at(lq, 0, 0, W, H, 0, 0.92, 0.90, 0.85, 0);
    rect_at(lq + 1 * MB_INST, 10, 46, 76, 18, 0, 0.85, 0.25, 0.20, 0);
    // left capsule (no spot, merge=0)
    rect_at(lq + 2 * MB_INST, 6, 48, 30, 14, 6, 1, 1, 1, -9);
    lq[2 * MB_INST + 4] = 7;
    lq[2 * MB_INST + 6] = 1;
    lq[2 * MB_INST + 7] = 1.5;  // sp = 3.0 -> k == 0
    lq[2 * MB_INST + 11] = 0.25;
    lq[2 * MB_INST + 12] = 0.8;
    lq[2 * MB_INST + 13] = 6;
    lq[2 * MB_INST + 14] = 0;
    lq[2 * MB_INST + 15] = 1;
    lq[2 * MB_INST + 21] = 2;
    lq[2 * MB_INST + 22] = 0;
    lq[2 * MB_INST + 23] = 0;
    // shadow between the two shapes (outside the right disc's capture box)
    rect_at(lq + 3 * MB_INST, 6, 48, 10, 6, 2, 0, 0, 0, 0);
    lq[3 * MB_INST + 7] = 1;
    lq[3 * MB_INST + 11] = 0.2;
    // right disc (with its own spot, merge=0, sharing capture -9)
    rect_at(lq + 4 * MB_INST, 68, 48, 18, 14, 6, 1, 1, 1, -9);
    lq[4 * MB_INST + 4] = 7;
    lq[4 * MB_INST + 6] = 1;
    lq[4 * MB_INST + 7] = 1.5;
    lq[4 * MB_INST + 11] = 0.25;
    lq[4 * MB_INST + 12] = 0.8;
    lq[4 * MB_INST + 13] = 6;
    lq[4 * MB_INST + 14] = 537.0 * 4096.0 + 528.0 + 1.0;
    lq[4 * MB_INST + 15] = 1;
    lq[4 * MB_INST + 21] = 2;
    lq[4 * MB_INST + 22] = 0;
    lq[4 * MB_INST + 23] = 0;

    glass_forget();
    made = blurs_made;
    gl_present(lq, 5, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 1);
    unsigned char *px_lq_shared = pixels_of_fb(surface);

    lq[2 * MB_INST + 20] = -10;
    lq[4 * MB_INST + 20] = -11;
    glass_forget();
    made = blurs_made;
    gl_present(lq, 5, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 2);
    unsigned char *px_lq_sep = pixels_of_fb(surface);
    CHECK(memcmp(px_lq_shared, px_lq_sep, (size_t)fb_w * fb_h * 4) == 0);
    free(px_lq_shared);
    free(px_lq_sep);
  }

  // Asymmetric 4-corner merged_liquid (rr = 14,14,0,0 sheet merged with pill) + Glass::clear() micro-veil vs pure lens:
  {
    double as[3 * MB_INST];
    rect_at(as, 0, 0, W, H, 0, 0.10, 0.12, 0.16, 0);
    rect_at(as + 1 * MB_INST, 10, 20, 48, 40, 6, 1, 1, 1, -12);
    as[1 * MB_INST + 4] = 14;
    as[1 * MB_INST + 6] = 1;
    as[1 * MB_INST + 7] = 1;
    as[1 * MB_INST + 11] = 0.25;
    as[1 * MB_INST + 12] = 0.55;
    as[1 * MB_INST + 13] = 8;
    as[1 * MB_INST + 15] = 1;
    as[1 * MB_INST + 21] = 6;
    as[1 * MB_INST + 22] = 0.18;
    as[1 * MB_INST + 23] = 8;
    as[1 * MB_INST + 36] = 14;
    as[1 * MB_INST + 37] = 14;
    as[1 * MB_INST + 38] = 0;
    as[1 * MB_INST + 39] = 0;
    rect_at(as + 2 * MB_INST, 62, 28, 20, 20, 6, 1, 1, 1, -12);
    as[2 * MB_INST + 4] = 10;
    as[2 * MB_INST + 6] = 1;
    as[2 * MB_INST + 7] = 1;
    as[2 * MB_INST + 11] = 0.25;
    as[2 * MB_INST + 12] = 0.55;
    as[2 * MB_INST + 13] = 8;
    as[2 * MB_INST + 15] = 1;
    as[2 * MB_INST + 21] = 6;
    as[2 * MB_INST + 22] = 0.18;
    as[2 * MB_INST + 23] = 8;
    as[2 * MB_INST + 36] = 10;
    as[2 * MB_INST + 37] = 10;
    as[2 * MB_INST + 38] = 10;
    as[2 * MB_INST + 39] = 10;

    glass_forget();
    gl_present(as, 3, 0.10, 0.12, 0.16);
    unsigned char *px_as = pixels_of_fb(surface);
    // RGBA8 bottom-up at scale 2
    unsigned char *bg_p = px_as + ((fb_h - 1 - 6) * fb_w + 6) * 4;
    unsigned char *tl_p = px_as + ((fb_h - 1 - 44) * fb_w + 24) * 4;  // (12, 22) outside top-left rounded corner (r=14)
    unsigned char *bl_p = px_as + ((fb_h - 1 - 116) * fb_w + 24) * 4; // (12, 58) inside bottom-left square corner (r=0)
    CHECK(abs((int)tl_p[0] - (int)bg_p[0]) <= 2 && abs((int)tl_p[1] - (int)bg_p[1]) <= 2);
    CHECK((int)bl_p[0] > 90 && (int)bl_p[1] > 90);
    free(px_as);

    double cl[3 * MB_INST];
    rect_at(cl, 0, 0, W, H, 0, 0.08, 0.08, 0.10, 0);
    rect_at(cl + 1 * MB_INST, 8, 15, 36, 40, 6, 1, 1, 1, -13);
    cl[1 * MB_INST + 4] = 10;
    cl[1 * MB_INST + 6] = 1;
    cl[1 * MB_INST + 7] = 0;
    cl[1 * MB_INST + 11] = 26.0 / 255.0;
    cl[1 * MB_INST + 12] = 0.6;
    cl[1 * MB_INST + 13] = 6;
    cl[1 * MB_INST + 15] = 1;
    cl[1 * MB_INST + 21] = 8;
    cl[1 * MB_INST + 22] = 0;
    cl[1 * MB_INST + 23] = 0;
    rect_at(cl + 2 * MB_INST, 56, 15, 36, 40, 6, 1, 1, 1, -14);
    cl[2 * MB_INST + 4] = 10;
    cl[2 * MB_INST + 6] = 1;
    cl[2 * MB_INST + 7] = 0;
    cl[2 * MB_INST + 11] = 0.0;
    cl[2 * MB_INST + 12] = 0.6;
    cl[2 * MB_INST + 13] = 6;
    cl[2 * MB_INST + 15] = 1;
    cl[2 * MB_INST + 21] = 8;
    cl[2 * MB_INST + 22] = 0;
    cl[2 * MB_INST + 23] = 0;

    glass_forget();
    gl_present(cl, 3, 0.08, 0.08, 0.10);
    unsigned char *px_cl = pixels_of_fb(surface);
    unsigned char *cl_bg = px_cl + ((fb_h - 1 - 6) * fb_w + 6) * 4;
    unsigned char *cl_veil = px_cl + ((fb_h - 1 - 70) * fb_w + 52) * 4;   // (26, 35) center of Glass::clear()
    unsigned char *cl_lens = px_cl + ((fb_h - 1 - 70) * fb_w + 148) * 4;  // (74, 35) center of pure clear optical lens
    CHECK((int)cl_veil[1] >= 44 && (int)cl_veil[1] <= 62);
    CHECK(abs((int)cl_lens[0] - (int)cl_bg[0]) <= 2 && abs((int)cl_lens[1] - (int)cl_bg[1]) <= 2);
    free(px_cl);

    // Wave 3A (1): clear-lens optical zoom (slot 7 = -(zoom - 1.0)) magnifies centered backdrop
    double zm[3 * MB_INST];
    rect_at(zm, 0, 0, W, H, 0, 0.05, 0.05, 0.08, 0);
    // Red square centered at (50, 35), half-width 8pt -> x in [42, 58]
    rect_at(zm + 1 * MB_INST, 42, 27, 16, 16, 0, 0.95, 0.10, 0.10, 0);
    // Clear liquid lens (10, 10, 80, 50), center (50, 35), refraction = 0
    rect_at(zm + 2 * MB_INST, 10, 10, 80, 50, 6, 1, 1, 1, -15);
    zm[2 * MB_INST + 4] = 12;
    zm[2 * MB_INST + 6] = 1;
    zm[2 * MB_INST + 7] = 0.0;  // zoom = 1.0
    zm[2 * MB_INST + 11] = 0.0;
    zm[2 * MB_INST + 12] = 0.0;
    zm[2 * MB_INST + 13] = 4;
    zm[2 * MB_INST + 15] = 1;
    zm[2 * MB_INST + 21] = 0;
    zm[2 * MB_INST + 22] = 0;
    zm[2 * MB_INST + 23] = 0;

    glass_forget();
    gl_present(zm, 3, 0.05, 0.05, 0.08);
    unsigned char *px_z1 = pixels_of_fb(surface);
    // Probe (59, 35) -> (118, 70) at 2x: outside [42, 58] at zoom=1.0 -> dark background
    unsigned char *z1_p = px_z1 + ((fb_h - 1 - 70) * fb_w + 118) * 4;
    CHECK((int)z1_p[0] < 40);
    free(px_z1);

    zm[2 * MB_INST + 7] = -0.25;  // zoom = 1.25 -> sampleBase.x = 50 + 9/1.25 = 57.2 (inside red square!)
    glass_forget();
    gl_present(zm, 3, 0.05, 0.05, 0.08);
    unsigned char *px_z2 = pixels_of_fb(surface);
    unsigned char *z2_p = px_z2 + ((fb_h - 1 - 70) * fb_w + 118) * 4;
    CHECK((int)z2_p[0] > 200);
    free(px_z2);

    // Wave 3A (2): global ambient light_angle rotates specular glint by 90 deg and restores bit-exact at 0.0
    double la_inst[2 * MB_INST];
    rect_at(la_inst, 0, 0, W, H, 0, 0.10, 0.10, 0.12, 0);
    rect_at(la_inst + 1 * MB_INST, 25, 10, 50, 50, 6, 0.12, 0.12, 0.12, -16);
    la_inst[1 * MB_INST + 4] = 12;
    la_inst[1 * MB_INST + 6] = 1;
    la_inst[1 * MB_INST + 7] = 1.0;
    la_inst[1 * MB_INST + 11] = 0.5;
    la_inst[1 * MB_INST + 12] = 1.0;
    la_inst[1 * MB_INST + 13] = 8;
    la_inst[1 * MB_INST + 15] = 1;
    la_inst[1 * MB_INST + 21] = 0;
    la_inst[1 * MB_INST + 22] = 0;
    la_inst[1 * MB_INST + 23] = 0;

    mb_host_glass_light_angle(0.0);
    glass_forget();
    gl_present(la_inst, 2, 0.10, 0.10, 0.12);
    unsigned char *px_la0 = pixels_of_fb(surface);
    // Top edge (50, 10.5) -> (100, 21); Left edge (25.5, 35) -> (51, 70)
    int top0 = (int)px_la0[((fb_h - 1 - 21) * fb_w + 100) * 4 + 1];
    int left0 = (int)px_la0[((fb_h - 1 - 70) * fb_w + 51) * 4 + 1];
    CHECK(top0 > left0 + 30);

    mb_host_glass_light_angle(1.5707963267948966);  // PI / 2
    glass_forget();
    gl_present(la_inst, 2, 0.10, 0.10, 0.12);
    unsigned char *px_la90 = pixels_of_fb(surface);
    int top90 = (int)px_la90[((fb_h - 1 - 21) * fb_w + 100) * 4 + 1];
    int left90 = (int)px_la90[((fb_h - 1 - 70) * fb_w + 51) * 4 + 1];
    int right90 = (int)px_la90[((fb_h - 1 - 70) * fb_w + 149) * 4 + 1];
    CHECK(left90 > top90 + 30);
    CHECK(right90 > top90 + 30);
    free(px_la90);

    mb_host_glass_light_angle(0.0);
    glass_forget();
    gl_present(la_inst, 2, 0.10, 0.10, 0.12);
    unsigned char *px_la0_again = pixels_of_fb(surface);
    CHECK(memcmp(px_la0, px_la0_again, (size_t)fb_w * (size_t)fb_h * 4) == 0);
    free(px_la0);
    free(px_la0_again);
  }

  // Neutral light liquid glass density (kind 6, !is_clear && !is_dark): alpha <= 0.41 keeps the 0.4032 baseline to the
  // byte (0xFDFCFD50 and 0xFDFCFD67 draw the same), while a dense veil (0xFDFCFDD9 ~ 0.851) emits its own alpha and
  // fades transmittance, lift and chroma to 0, so over black it is far brighter and over saturated blue it stays neutral.
  {
    double ld[2 * MB_INST];
    unsigned char *px_ld[4];
    // (alpha byte, backdrop r, g, b)
    static const double ld_case[4][4] = {
        {0x50, 0, 0, 0}, {0x67, 0, 0, 0}, {0xD9, 0, 0, 0}, {0xD9, 0.0, 0.4, 1.0}};
    for (int i = 0; i < 4; i++) {
      rect_at(ld, 0, 0, W, H, 0, ld_case[i][1], ld_case[i][2], ld_case[i][3], 0);
      rect_at(ld + MB_INST, 10, 10, 80, 50, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -17);
      ld[MB_INST + 4] = 12;
      ld[MB_INST + 6] = 1;
      ld[MB_INST + 7] = 1.0;
      ld[MB_INST + 11] = ld_case[i][0] / 255.0;
      ld[MB_INST + 12] = 0.0;
      ld[MB_INST + 13] = 4;
      ld[MB_INST + 15] = 1;
      ld[MB_INST + 21] = 0;
      ld[MB_INST + 22] = 0;
      ld[MB_INST + 23] = 0;
      glass_forget();
      gl_present(ld, 2, ld_case[i][1], ld_case[i][2], ld_case[i][3]);
      px_ld[i] = pixels_of_fb(surface);
    }
    // centre (50, 35) -> (100, 70) at 2x
    double ld_lum[4];
    for (int i = 0; i < 4; i++) {
      unsigned char *c = px_ld[i] + ((fb_h - 1 - 70) * fb_w + 100) * 4;
      ld_lum[i] = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0;
      printf("gles_render: light glass 0x%02X over (%.1f, %.1f, %.1f): rgb %d %d %d, luma %.4f\n", (int)ld_case[i][0],
             ld_case[i][1], ld_case[i][2], ld_case[i][3], c[0], c[1], c[2], ld_lum[i]);
    }
    CHECK(memcmp(px_ld[0], px_ld[1], (size_t)fb_w * fb_h * 4) == 0);
    CHECK(ld_lum[1] >= 0.25 && ld_lum[1] <= 0.36);
    CHECK(ld_lum[2] >= 0.80 && ld_lum[2] > ld_lum[1] + 0.40);
    CHECK(px_ld[3][((fb_h - 1 - 70) * fb_w + 100) * 4 + 0] >= (int)(0.72 * 255.0 + 0.5));
    for (int i = 0; i < 4; i++) free(px_ld[i]);
  }

  // Neutral dark liquid glass density (kind 6, is_dark): alpha <= 0.41 keeps the regular baseline to the byte
  // (0x20202050 and 0x20202067 draw the same), while dense veils (0x202020BF 75%, 0x202020D9 85%) fade
  // transmittance, lift and chroma toward 0, so over white they stay dark for white ink and over saturated blue
  // chroma is cleanly attenuated.
  {
    double dd[2 * MB_INST];
    unsigned char *px_dd[5];
    // (alpha byte, backdrop r, g, b)
    static const double dd_case[5][4] = {
        {0x50, 1, 1, 1}, {0x67, 1, 1, 1}, {0xBF, 1, 1, 1}, {0xD9, 1, 1, 1}, {0xD9, 0.0, 0.4, 1.0}};
    for (int i = 0; i < 5; i++) {
      rect_at(dd, 0, 0, W, H, 0, dd_case[i][1], dd_case[i][2], dd_case[i][3], 0);
      rect_at(dd + MB_INST, 10, 10, 80, 50, 6, 32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0, -17);
      dd[MB_INST + 4] = 12;
      dd[MB_INST + 6] = 1;
      dd[MB_INST + 7] = 1.0;
      dd[MB_INST + 11] = dd_case[i][0] / 255.0;
      dd[MB_INST + 12] = 0.0;
      dd[MB_INST + 13] = 4;
      dd[MB_INST + 15] = 1;
      dd[MB_INST + 21] = 0;
      dd[MB_INST + 22] = 0;
      dd[MB_INST + 23] = 0;
      glass_forget();
      gl_present(dd, 2, dd_case[i][1], dd_case[i][2], dd_case[i][3]);
      px_dd[i] = pixels_of_fb(surface);
    }
    // centre (50, 35) -> (100, 70) at 2x
    double dd_lum[5];
    for (int i = 0; i < 5; i++) {
      unsigned char *c = px_dd[i] + ((fb_h - 1 - 70) * fb_w + 100) * 4;
      dd_lum[i] = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255.0;
      printf("gles_render: dark glass 0x%02X over (%.1f, %.1f, %.1f): rgb %d %d %d, luma %.4f\n", (int)dd_case[i][0],
             dd_case[i][1], dd_case[i][2], dd_case[i][3], c[0], c[1], c[2], dd_lum[i]);
    }
    CHECK(memcmp(px_dd[0], px_dd[1], (size_t)fb_w * fb_h * 4) == 0);
    CHECK(dd_lum[1] >= 0.55 && dd_lum[1] <= 0.74);
    CHECK(dd_lum[2] <= 0.36 && dd_lum[2] <= dd_lum[1] - 0.25);
    CHECK(dd_lum[3] <= 0.30 && dd_lum[3] < dd_lum[2]);
    unsigned char *dd_blue = px_dd[4] + ((fb_h - 1 - 70) * fb_w + 100) * 4;
    CHECK(((double)dd_blue[2] - (double)dd_blue[0]) / 255.0 <= 0.28);
    for (int i = 0; i < 5; i++) free(px_dd[i]);
  }

  // Dedicated ONE_KIND=13 (unmerged liquid, merge=0) vs ONE_KIND=6 (merged liquid, merge=1e-7) with large flat
  // interior (inward >= 23), non-zero bevel/refraction/chroma/rim: must be byte-for-byte identical; and zero-copy
  // slot swap across frames + glass_free() must preserve identical pixels.
  {
    CHECK(progs[5].p != 0 && progs[6].p != 0 && progs[MB_KIND_LIQUID_SINGLE].p != 0);
    double lp[3 * MB_INST];
    rect_at(lp, 0, 0, W, H, 0, 0.12, 0.24, 0.48, 0);
    rect_at(lp + MB_INST, 20, 15, 60, 50, 0, 0.92, 0.35, 0.18, 0);
    rect_at(lp + 2 * MB_INST, 8, 6, 84, 68, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -18);
    lp[2 * MB_INST + 4] = 16;
    lp[2 * MB_INST + 6] = 1.0;
    lp[2 * MB_INST + 7] = 2.5;
    lp[2 * MB_INST + 11] = 0x67 / 255.0;
    lp[2 * MB_INST + 12] = 0.6;
    lp[2 * MB_INST + 13] = 14.0;
    lp[2 * MB_INST + 15] = 1.0;
    lp[2 * MB_INST + 21] = 18.0;
    lp[2 * MB_INST + 22] = 0.4;
    lp[2 * MB_INST + 23] = 0.0;
    glass_forget();
    gl_present(lp, 3, 0.12, 0.24, 0.48);
    unsigned char *px_single = pixels_of_fb(surface);

    lp[2 * MB_INST + 23] = 1e-7;
    glass_forget();
    gl_present(lp, 3, 0.12, 0.24, 0.48);
    unsigned char *px_merged = pixels_of_fb(surface);
    CHECK(memcmp(px_single, px_merged, (size_t)fb_w * fb_h * 4) == 0);
    free(px_merged);

    lp[2 * MB_INST + 23] = 0.0;
    for (int step = 1; step <= 4; step++) {
      lp[MB_INST + 0] = 20 + step * 3;
      gl_present(lp, 3, 0.12, 0.24, 0.48);
    }
    glass_free();
    lp[MB_INST + 0] = 20;
    gl_present(lp, 3, 0.12, 0.24, 0.48);
    unsigned char *px_after_free = pixels_of_fb(surface);
    CHECK(memcmp(px_single, px_after_free, (size_t)fb_w * fb_h * 4) == 0);
    free(px_single);
    free(px_after_free);
  }

  // Wave 7: adaptive liquid glass (slot 14 = -1.0) + adaptive kind 10 neutral/chromatic ink:
  // 0: light glass over white (bg=1.0), 1: light glass over black (bg=0.0),
  // 2: light glass over mid-tone (bg=0.50), 3: dark glass (0x20202067) over white (bg=1.0).
  {
    double ad[4 * MB_INST];
    struct { double bg; int dark_glass; double ink; } w7_cases[4] = {
      {1.0, 0, 0.11},
      {0.0, 0, 0.11},
      {0.50, 0, 0.11},
      {1.0, 1, 0.93},
    };
    for (int ci = 0; ci < 4; ci++) {
      double bg = w7_cases[ci].bg;
      int dg = w7_cases[ci].dark_glass;
      double ink = w7_cases[ci].ink;
      rect_at(ad, 0, 0, W, H, 0, bg, bg, bg, 0);
      rect_at(ad + MB_INST, 8, 6, 84, 68, 6,
              dg ? 32.0 / 255.0 : 253.0 / 255.0,
              dg ? 32.0 / 255.0 : 252.0 / 255.0,
              dg ? 32.0 / 255.0 : 253.0 / 255.0, -19);
      ad[MB_INST + 4] = 16;
      ad[MB_INST + 6] = 1.0;
      ad[MB_INST + 7] = 2.0;
      ad[MB_INST + 11] = 0x67 / 255.0;
      ad[MB_INST + 12] = 0.0;
      ad[MB_INST + 13] = 10.0;
      ad[MB_INST + 14] = -1.0;  // adaptive=true, no spot
      ad[MB_INST + 15] = 1.0;
      ad[MB_INST + 21] = 0.0;
      ad[MB_INST + 22] = 0.0;
      ad[MB_INST + 23] = 0.0;
      // Neutral line inside glass at y=28 (x=24..46)
      rect_at(ad + 2 * MB_INST, 20, 22, 30, 12, 10, ink, ink, ink, 0);
      ad[2 * MB_INST + 4] = 3.0;
      ad[2 * MB_INST + 12] = 0.1;
      ad[2 * MB_INST + 13] = 0.5;
      ad[2 * MB_INST + 14] = 0.9;
      ad[2 * MB_INST + 15] = 0.5;
      ad[2 * MB_INST + 21] = 50.0;
      ad[2 * MB_INST + 22] = 40.0;
      ad[2 * MB_INST + 23] = 34.0;
      // Chromatic accent line inside glass at y=52 (x=24..46)
      rect_at(ad + 3 * MB_INST, 20, 46, 30, 12, 10, 0.90, 0.30, 0.15, 0);
      ad[3 * MB_INST + 4] = 3.0;
      ad[3 * MB_INST + 12] = 0.1;
      ad[3 * MB_INST + 13] = 0.5;
      ad[3 * MB_INST + 14] = 0.9;
      ad[3 * MB_INST + 15] = 0.5;
      ad[3 * MB_INST + 21] = 50.0;
      ad[3 * MB_INST + 22] = 40.0;
      ad[3 * MB_INST + 23] = 34.0;
      glass_forget();
      gl_present(ad, 4, bg, bg, bg);
      unsigned char *px_ad = pixels_of_fb(surface);
      // Glass interior at (68, 40) -> (136, 80) at 2x (RGBA, y flipped)
      unsigned char *gp = px_ad + ((fb_h - 1 - 80) * fb_w + 136) * 4;
      double g_lum = (0.2126 * gp[0] + 0.7152 * gp[1] + 0.0722 * gp[2]) / 255.0;
      unsigned char *np = px_ad + ((fb_h - 1 - 56) * fb_w + 70) * 4;
      double n_lum = (0.2126 * np[0] + 0.7152 * np[1] + 0.0722 * np[2]) / 255.0;
      unsigned char *cp = px_ad + ((fb_h - 1 - 104) * fb_w + 70) * 4;
      printf("gles_render: wave7 case=%d bg=%.2f dg=%d glass=%.3f neutral_ink=%.3f chroma_rgb=%d,%d,%d\n",
             ci, bg, dg, g_lum, n_lum, cp[0], cp[1], cp[2]);
      if (ci == 0) {
        CHECK(g_lum > 0.75);
        CHECK(n_lum < 0.25);
      } else if (ci == 1) {
        CHECK(g_lum < 0.20);
        CHECK(n_lum > 0.80);
      } else if (ci == 2) {
        CHECK(g_lum > 0.55);
        CHECK(n_lum < 0.25);
      } else {
        CHECK(g_lum < 0.45);
        CHECK(n_lum > 0.85);
      }
      CHECK((int)cp[0] > (int)cp[2] + 120);
      free(px_ad);
    }

    // Smooth fogging on adaptive flip: thin bright stripe over black is softened by dual-ring fog blur + higher darkDens
    double fg[3 * MB_INST];
    double fog_peaks[2] = {0.0, 0.0};
    for (int adaptive_on = 0; adaptive_on <= 1; adaptive_on++) {
      rect_at(fg, 0, 0, W, H, 0, 0.0, 0.0, 0.0, 0);
      // Place the thin 2pt white stripe at y=48 (off the 5-point luma sample cross at y=40 and y=40+/-17)
      rect_at(fg + MB_INST, 4, 47, 92, 2, 0, 1.0, 1.0, 1.0, 0);
      rect_at(fg + 2 * MB_INST, 8, 6, 84, 68, 6,
              adaptive_on ? 253.0 / 255.0 : 32.0 / 255.0,
              adaptive_on ? 252.0 / 255.0 : 32.0 / 255.0,
              adaptive_on ? 253.0 / 255.0 : 32.0 / 255.0, -20);
      fg[2 * MB_INST + 4] = 16;
      fg[2 * MB_INST + 6] = 1.0;
      fg[2 * MB_INST + 7] = 1.0;
      fg[2 * MB_INST + 11] = 0x67 / 255.0;
      fg[2 * MB_INST + 12] = 0.0;
      fg[2 * MB_INST + 13] = 10.0;
      fg[2 * MB_INST + 14] = adaptive_on ? -1.0 : 0.0;
      fg[2 * MB_INST + 15] = 1.0;
      fg[2 * MB_INST + 21] = 0.0;
      fg[2 * MB_INST + 22] = 0.0;
      fg[2 * MB_INST + 23] = 0.0;
      glass_forget();
      gl_present(fg, 3, 0.0, 0.0, 0.0);
      unsigned char *px_fg = pixels_of_fb(surface);
      unsigned char *sp = px_fg + ((fb_h - 1 - 96) * fb_w + 100) * 4;  // (50, 48) on the bright 2pt stripe
      fog_peaks[adaptive_on] = (0.2126 * sp[0] + 0.7152 * sp[1] + 0.0722 * sp[2]) / 255.0;
      free(px_fg);
    }
    printf("gles_render: wave7 fog stripe peak plain_dark=%.3f adaptive_fog=%.3f\n",
           fog_peaks[0], fog_peaks[1]);
    CHECK(fog_peaks[1] < fog_peaks[0] - 0.15);

    // Test A: wide 84x16pt adaptive capsule over deep navy #173255 with centered 16x10pt pure white "{less}" block
    // must resist ping-pong flipping (trimmed mean stays dark -> dark glass + white ink).
    double ta[4 * MB_INST];
    rect_at(ta, 0, 0, W, H, 0, 23.0 / 255.0, 50.0 / 255.0, 85.0 / 255.0, 0);
    rect_at(ta + MB_INST, 42, 31, 16, 10, 0, 1.0, 1.0, 1.0, 0);
    rect_at(ta + 2 * MB_INST, 8, 28, 84, 16, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -21);
    ta[2 * MB_INST + 4] = 8.0;
    ta[2 * MB_INST + 6] = 1.0;
    ta[2 * MB_INST + 7] = 2.0;
    ta[2 * MB_INST + 11] = 0x67 / 255.0;
    ta[2 * MB_INST + 12] = 0.0;
    ta[2 * MB_INST + 13] = 8.0;
    ta[2 * MB_INST + 14] = -1.0;
    ta[2 * MB_INST + 15] = 1.0;
    ta[2 * MB_INST + 21] = 0.0;
    ta[2 * MB_INST + 22] = 0.0;
    ta[2 * MB_INST + 23] = 0.0;
    rect_at(ta + 3 * MB_INST, 16, 30, 20, 12, 10, 0.11, 0.11, 0.11, 0);
    ta[3 * MB_INST + 4] = 3.0;
    ta[3 * MB_INST + 12] = 0.1;
    ta[3 * MB_INST + 13] = 0.5;
    ta[3 * MB_INST + 14] = 0.9;
    ta[3 * MB_INST + 15] = 0.5;
    ta[3 * MB_INST + 21] = 50.0;
    ta[3 * MB_INST + 22] = 36.0;
    ta[3 * MB_INST + 23] = 16.0;
    glass_forget();
    gl_present(ta, 4, 23.0 / 255.0, 50.0 / 255.0, 85.0 / 255.0);
    unsigned char *px_ta = pixels_of_fb(surface);
    unsigned char *ta_gp = px_ta + ((fb_h - 1 - 72) * fb_w + 148) * 4;  // (74, 36) glass over navy
    unsigned char *ta_np = px_ta + ((fb_h - 1 - 72) * fb_w + 52) * 4;   // (26, 36) neutral ink inside capsule
    double ta_g = (0.2126 * ta_gp[0] + 0.7152 * ta_gp[1] + 0.0722 * ta_gp[2]) / 255.0;
    double ta_n = (0.2126 * ta_np[0] + 0.7152 * ta_np[1] + 0.0722 * ta_np[2]) / 255.0;
    printf("gles_render: wave7 testA wide_less glass=%.3f ink=%.3f\n", ta_g, ta_n);
    CHECK(ta_g < 0.28);
    CHECK(ta_n > 0.80);
    free(px_ta);

    // Test B: cross-frame temporal smoothing + synchronized glass/ink + Schmitt hysteresis + auto-settle stop
    gl_set_fixed_dt(1.0 / 60.0);
    double tb[3 * MB_INST];
    rect_at(tb, 0, 0, W, H, 0, 1.0, 1.0, 1.0, 0);
    rect_at(tb + MB_INST, 8, 28, 84, 16, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -22);
    tb[MB_INST + 4] = 8.0;
    tb[MB_INST + 6] = 1.0;
    tb[MB_INST + 7] = 2.0;
    tb[MB_INST + 11] = 0x67 / 255.0;
    tb[MB_INST + 12] = 0.0;
    tb[MB_INST + 13] = 8.0;
    tb[MB_INST + 14] = -1.0;
    tb[MB_INST + 15] = 1.0;
    tb[MB_INST + 21] = 0.0;
    tb[MB_INST + 22] = 0.0;
    tb[MB_INST + 23] = 0.0;
    rect_at(tb + 2 * MB_INST, 16, 30, 20, 12, 10, 0.11, 0.11, 0.11, 0);
    tb[2 * MB_INST + 4] = 3.0;
    tb[2 * MB_INST + 12] = 0.1;
    tb[2 * MB_INST + 13] = 0.5;
    tb[2 * MB_INST + 14] = 0.9;
    tb[2 * MB_INST + 15] = 0.5;
    tb[2 * MB_INST + 21] = 50.0;
    tb[2 * MB_INST + 22] = 36.0;
    tb[2 * MB_INST + 23] = 16.0;

    // Frame 0: pure white -> instant light state
    glass_forget();
    gl_present(tb, 3, 1.0, 1.0, 1.0);
    unsigned char *px_tb = pixels_of_fb(surface);
    double f0_g = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
    double f0_n = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
    free(px_tb);
    printf("gles_render: wave7 testB f0_white glass=%.3f ink=%.3f\n", f0_g, f0_n);
    CHECK(f0_g > 0.75);
    CHECK(f0_n < 0.25);

    // Frame 1: switch to deep navy #173255 -> smooth intermediate state
    tb[8] = 23.0 / 255.0; tb[9] = 50.0 / 255.0; tb[10] = 85.0 / 255.0;
    gl_present(tb, 3, tb[8], tb[9], tb[10]);
    px_tb = pixels_of_fb(surface);
    double f1_g = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
    double f1_n = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
    free(px_tb);
    printf("gles_render: wave7 testB f1_navy glass=%.3f ink=%.3f settling=%d\n", f1_g, f1_n, gl_adaptive_settling());
    CHECK(f1_g > 0.28 && f1_g < 0.72);
    CHECK(f1_n > 0.15 && f1_n < 0.75);
    CHECK(gl_adaptive_settling() == 1);

    // Step 25 more frames (~420ms): monotonic convergence to dark state
    double prev_g = f1_g, prev_n = f1_n;
    for (int s = 0; s < 25; s++) {
      gl_present(tb, 3, tb[8], tb[9], tb[10]);
      px_tb = pixels_of_fb(surface);
      double cg = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
      double cn = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
      free(px_tb);
      CHECK(cg <= prev_g + 0.015);
      CHECK(cn >= prev_n - 0.015);
      prev_g = cg;
      prev_n = cn;
    }
    printf("gles_render: wave7 testB f26_dark glass=%.3f ink=%.3f settling=%d\n", prev_g, prev_n, gl_adaptive_settling());
    CHECK(prev_g < 0.28);
    CHECK(prev_n > 0.85);

    // Schmitt hysteresis: bg=0.40 (in [0.36, 0.46]) for 25 frames stays dark
    tb[8] = 0.40; tb[9] = 0.40; tb[10] = 0.40;
    for (int s = 0; s < 25; s++) gl_present(tb, 3, 0.40, 0.40, 0.40);
    px_tb = pixels_of_fb(surface);
    double hyst_g = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
    double hyst_n = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
    free(px_tb);
    printf("gles_render: wave7 testB hyst_0.40 glass=%.3f ink=%.3f\n", hyst_g, hyst_n);
    CHECK(hyst_g < 0.40);
    CHECK(hyst_n > 0.80);

    // Return to bright bg=0.95: frame 1 intermediate, +26 frames settles back to light and stops settling
    tb[8] = 0.95; tb[9] = 0.95; tb[10] = 0.95;
    gl_present(tb, 3, 0.95, 0.95, 0.95);
    px_tb = pixels_of_fb(surface);
    double r1_g = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
    double r1_n = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
    free(px_tb);
    printf("gles_render: wave7 testB return_f1 glass=%.3f ink=%.3f\n", r1_g, r1_n);
    CHECK(r1_g > 0.30 && r1_g < 0.82);
    CHECK(r1_n > 0.20 && r1_n < 0.88);
    for (int s = 0; s < 26; s++) gl_present(tb, 3, 0.95, 0.95, 0.95);
    px_tb = pixels_of_fb(surface);
    double r_end_g = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 148) * 4 + 2]) / 255.0;
    double r_end_n = (0.2126 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 0] + 0.7152 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 1] + 0.0722 * px_tb[((fb_h - 1 - 72) * fb_w + 52) * 4 + 2]) / 255.0;
    free(px_tb);
    printf("gles_render: wave7 testB return_end glass=%.3f ink=%.3f settling=%d\n", r_end_g, r_end_n, gl_adaptive_settling());
    CHECK(r_end_g > 0.75);
    CHECK(r_end_n < 0.25);
    CHECK(gl_adaptive_settling() == 0);
    gl_set_fixed_dt(0.0);
    glass_forget();
    // Wave 4B v17: foreground optical lens (kind == 8): offscreen Gaussian defocus + spherical bevel refraction + SDF clip
    double k8[3 * MB_INST];
    rect_at(k8, 0, 0, W, H, 0, 1.0, 1.0, 1.0, 0);
    rect_at(k8 + MB_INST, 15, 10, 70, 60, 8, 1.0, 1.0, 1.0, 0);
    k8[MB_INST + 4] = 16;
    k8[MB_INST + 7] = 3.0;   // blur = 3pt
    k8[MB_INST + 11] = 1.0;  // alpha = 1
    k8[MB_INST + 12] = 1.0;  // child_n = 1
    k8[MB_INST + 13] = 18.0; // bezel = 18pt
    k8[MB_INST + 14] = 14.0; // refraction = 14pt
    k8[MB_INST + 15] = 1.0;
    k8[MB_INST + 36] = 16; k8[MB_INST + 37] = 16; k8[MB_INST + 38] = 16; k8[MB_INST + 39] = 16;
    rect_at(k8 + 2 * MB_INST, 38, 28, 24, 24, 0, 1.0, 0.0, 0.0, 0);
    gl_present(k8, 3, 1.0, 1.0, 1.0);
    unsigned char *px_k8 = pixels_of_fb(surface);
    // RGBA at 2x (y flipped): center (50,40)->(100,80), blur halo (35,40)->(70,80), outside SDF (5,40)->(10,80)
    unsigned char *k8_ctr = px_k8 + ((fb_h - 1 - 80) * fb_w + 100) * 4;
    unsigned char *k8_halo = px_k8 + ((fb_h - 1 - 80) * fb_w + 70) * 4;
    unsigned char *k8_out = px_k8 + ((fb_h - 1 - 80) * fb_w + 10) * 4;
    printf("gles_render: kind8 lens ctr=%d,%d,%d halo=%d,%d,%d out=%d,%d,%d\n",
           k8_ctr[0], k8_ctr[1], k8_ctr[2], k8_halo[0], k8_halo[1], k8_halo[2], k8_out[0], k8_out[1], k8_out[2]);
    CHECK((int)k8_ctr[0] - (int)k8_ctr[2] > 120);
    CHECK((int)k8_halo[0] - (int)k8_halo[2] > 20);
    CHECK(abs((int)k8_out[0] - (int)k8_out[2]) <= 2 && k8_out[0] >= 250);
    free(px_k8);
  }

  // A group the host keeps drawn out by its header straight into the floats: each instance moved in doubles, then
  // made a float, as the app's own instance moved there would be.
  double kept[MB_INST];
  rect_at(kept, 10.1, 20.3, 30, 20, 0, 0.5, 0.5, 0.5, 0);
  double kept_moves[1] = {0};
  mb_host_group_set(5, kept, kept_moves, 1);
  double head[MB_INST] = {0};
  head[0] = 0.2;
  head[1] = -7.7;
  head[5] = MB_GROUP_HEAD;
  head[12] = 5;
  head[13] = 0;
  head[14] = 1;
  gl_present(head, 1, 0.1, 0.2, 0.3);
  CHECK(kept_count == 1);
  CHECK(fbuf[0] == (float)(10.1 + 0.2));
  CHECK(fbuf[1] == (float)(20.3 + -7.7));
  CHECK(fbuf[2] == 30.0f);
  CHECK(fbuf[5] == 0.0f);
  CHECK(surface_as_whole(surface));
  mb_host_group_drop(5);

  // IME height sliding hits top-bar glass cache, and gradually growing glass height stays in one 256px level bucket
  // without rebuilding levels or clearing unchanged glass slots.
  {
    int saved_fb_w = fb_w, saved_fb_h = fb_h;
    double saved_w = cur_w, saved_h = cur_h, saved_scale = cur_scale;
    GLuint saved_target = target_fb;

    const int BW = 300, BH = 500, BS = 2;
    fb_w = BW * BS;
    fb_h = BH * BS;
    cur_w = BW;
    cur_h = BH;
    cur_scale = BS;
    GLuint big_tex, big_fb;
    glGenTextures(1, &big_tex);
    glBindTexture(GL_TEXTURE_2D, big_tex);
    glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
    glGenFramebuffers(1, &big_fb);
    glBindFramebuffer(GL_FRAMEBUFFER, big_fb);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, big_tex, 0);
    CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
    target_fb = big_fb;
    glass_free();

    // (1) IME cur_h sliding: top-bar glass stays cached (blurs_made +1 per step, only bottom bar re-blurred)
    double ime_inst[5 * MB_INST];
    static const double ime_hs[5] = {460, 420, 380, 420, 460};
    rect_at(ime_inst, 0, 0, BW, BH, 0, 0.94, 0.94, 0.92, 0);
    ime_inst[18] = BW; ime_inst[19] = BH;
    rect_at(ime_inst + 1 * MB_INST, 20, 12, 120, 20, 0, 0.85, 0.20, 0.20, 0);
    ime_inst[1 * MB_INST + 18] = BW; ime_inst[1 * MB_INST + 19] = BH;
    rect_at(ime_inst + 2 * MB_INST, 10, 6, 280, 32, 5, 1, 1, 1, -20);
    ime_inst[2 * MB_INST + 7] = 3;
    ime_inst[2 * MB_INST + 11] = 0.4;
    ime_inst[2 * MB_INST + 18] = BW; ime_inst[2 * MB_INST + 19] = BH;
    rect_at(ime_inst + 3 * MB_INST, 20, 466, 120, 20, 0, 0.20, 0.30, 0.85, 0);
    ime_inst[3 * MB_INST + 18] = BW; ime_inst[3 * MB_INST + 19] = BH;
    rect_at(ime_inst + 4 * MB_INST, 10, 460, 280, 32, 5, 1, 1, 1, -21);
    ime_inst[4 * MB_INST + 7] = 3;
    ime_inst[4 * MB_INST + 11] = 0.4;
    ime_inst[4 * MB_INST + 18] = BW; ime_inst[4 * MB_INST + 19] = BH;

    made = blurs_made;
    gl_present(ime_inst, 5, 0.1, 0.2, 0.3);
    CHECK(blurs_made == made + 2);
    CHECK(surface_as_fresh(big_fb));
    for (int i = 0; i < 5; i++) {
      cur_h = ime_hs[i];
      ime_inst[3 * MB_INST + 1] = cur_h - 34;
      ime_inst[4 * MB_INST + 1] = cur_h - 40;
      made = blurs_made;
      gl_present(ime_inst, 5, 0.1, 0.2, 0.3);
      CHECK(blurs_made == made + 1);
      CHECK(surface_as_fresh(big_fb));
    }

    // (2) Glass height growing from 100px to 220px (+12px/step, 10 steps): levels_rebuilt <= 1, unchanged glass hits cache
    cur_h = BH;
    glass_free();
    int rb0 = levels_rebuilt;
    double grow_inst[5 * MB_INST];
    rect_at(grow_inst, 0, 0, BW, BH, 0, 0.92, 0.90, 0.88, 0);
    grow_inst[18] = BW; grow_inst[19] = BH;
    rect_at(grow_inst + 1 * MB_INST, 20, 14, 100, 24, 0, 0.15, 0.65, 0.25, 0);
    grow_inst[1 * MB_INST + 18] = BW; grow_inst[1 * MB_INST + 19] = BH;
    rect_at(grow_inst + 2 * MB_INST, 10, 10, 160, 32, 5, 1, 1, 1, -22);
    grow_inst[2 * MB_INST + 7] = 2;
    grow_inst[2 * MB_INST + 11] = 0.4;
    grow_inst[2 * MB_INST + 18] = BW; grow_inst[2 * MB_INST + 19] = BH;
    rect_at(grow_inst + 3 * MB_INST, 20, 140, 100, 120, 0, 0.75, 0.25, 0.15, 0);
    grow_inst[3 * MB_INST + 18] = BW; grow_inst[3 * MB_INST + 19] = BH;
    rect_at(grow_inst + 4 * MB_INST, 10, 120, 160, 50, 5, 1, 1, 1, -23);
    grow_inst[4 * MB_INST + 7] = 2;
    grow_inst[4 * MB_INST + 11] = 0.4;
    grow_inst[4 * MB_INST + 18] = BW; grow_inst[4 * MB_INST + 19] = BH;

    for (int step = 0; step < 10; step++) {
      // height in pt: 50 + step * 6 -> 100px..208px (+ margin 16px = 132px..240px, within one 256px bucket)
      grow_inst[4 * MB_INST + 3] = 50.0 + step * 6.0;
      made = blurs_made;
      gl_present(grow_inst, 5, 0.1, 0.2, 0.3);
      CHECK(blurs_made == made + (step == 0 ? 2 : 1));
      CHECK(surface_as_whole(big_fb));
    }
    CHECK(surface_as_fresh(big_fb));
    CHECK(levels_rebuilt - rb0 <= 1);

    glass_free();
    glBindFramebuffer(GL_FRAMEBUFFER, saved_target);
    glDeleteFramebuffers(1, &big_fb);
    glDeleteTextures(1, &big_tex);
    fb_w = saved_fb_w;
    fb_h = saved_fb_h;
    cur_w = saved_w;
    cur_h = saved_h;
    cur_scale = saved_scale;
    target_fb = saved_target;
  }

  // A selection changes shape data while two adaptive glasses share a backdrop. Each host-added settle
  // region must redraw the complete shared capture, so no previous glass or caret enters the new blur.
  {
    double a[6 * MB_INST];
    rect_at(a, 0, 0, W, H, 0, 0.95, 0.95, 0.95, 0);
    rect_at(a + MB_INST, 14, 54, 40, 3, 0, 0.1, 0.1, 0.1, 0);
    rect_at(a + 2 * MB_INST, 10, 29, 35, 8, 6, 0.99, 0.99, 0.99, -1);
    a[2 * MB_INST + 4] = 4.0;
    a[2 * MB_INST + 6] = 1.0;
    a[2 * MB_INST + 7] = 4.0;
    a[2 * MB_INST + 11] = 0x67 / 255.0;
    a[2 * MB_INST + 13] = 8.0;
    a[2 * MB_INST + 14] = -1.0;
    a[2 * MB_INST + 15] = 1.0;
    a[2 * MB_INST + 21] = 6.0;
    rect_at(a + 3 * MB_INST, 8, 45, 84, 23, 6, 0.99, 0.99, 0.99, -1);
    a[3 * MB_INST + 4] = 8.0;
    a[3 * MB_INST + 6] = 1.0;
    a[3 * MB_INST + 7] = 4.0;
    a[3 * MB_INST + 11] = 0x67 / 255.0;
    a[3 * MB_INST + 13] = 8.0;
    a[3 * MB_INST + 14] = -1.0;
    a[3 * MB_INST + 15] = 1.0;
    a[3 * MB_INST + 21] = 6.0;
    rect_at(a + 4 * MB_INST, 10, 2, 30, 3, 0, 0.4, 0.6, 1.0, 0);
    a[4 * MB_INST + 11] = 0.0;
    rect_at(a + 5 * MB_INST, 0, 0, 0, 0, 12, 0, 0, 0, 0);
    glass_forget();
    gl_set_fixed_dt(1.0 / 60.0);
    gl_present(a, 6, 0.95, 0.95, 0.95);
    gl_dirty_add(0, 0, W, H);
    a[8] = 0.93;
    gl_present(a, 6, 0.95, 0.95, 0.95);
    CHECK(gl_adaptive_settling());
    a[4 * MB_INST + 11] = 0.5;
    a[5 * MB_INST + 12] = 1.0;
    gl_dirty_add(8, 0, 36, 8);
    gl_present(a, 6, 0.95, 0.95, 0.95);
    slots_invalidate();
    CHECK(surface_as_whole(surface));
    gl_set_fixed_dt(0.0);
    glass_forget();
  }

  // Two independent adaptive liquid glasses spaced 8pt apart so their captures overlap, with a high-contrast blue
  // foreground caret drawn after the lower glass. Three consecutive partial frames updating only the top non-glass
  // region while settling must stay pixel-identical to a whole redraw, and overlapping settle damage merges to one.
  {
    double a[7 * MB_INST];
    rect_at(a, 0, 0, W, H, 0, 0.95, 0.95, 0.95, 0);
    rect_at(a + MB_INST, 14, 50, 40, 3, 0, 0.1, 0.1, 0.1, 0);
    rect_at(a + 2 * MB_INST, 10, 20, 35, 10, 6, 0.99, 0.99, 0.99, -1);
    a[2 * MB_INST + 4] = 4.0;
    a[2 * MB_INST + 6] = 1.0;
    a[2 * MB_INST + 7] = 2.1;
    a[2 * MB_INST + 11] = 0x67 / 255.0;
    a[2 * MB_INST + 13] = 8.0;
    a[2 * MB_INST + 14] = -1.0;
    a[2 * MB_INST + 15] = 1.0;
    a[2 * MB_INST + 21] = 28.0;
    rect_at(a + 3 * MB_INST, 8, 38, 84, 24, 6, 0.99, 0.99, 0.99, -2);
    a[3 * MB_INST + 4] = 8.0;
    a[3 * MB_INST + 6] = 1.0;
    a[3 * MB_INST + 7] = 4.0;
    a[3 * MB_INST + 11] = 0x67 / 255.0;
    a[3 * MB_INST + 13] = 8.0;
    a[3 * MB_INST + 14] = -1.0;
    a[3 * MB_INST + 15] = 1.0;
    a[3 * MB_INST + 21] = 28.0;
    rect_at(a + 4 * MB_INST, 16, 44, 2, 12, 0, 0.05, 0.35, 1.0, 0);
    rect_at(a + 5 * MB_INST, 10, 2, 30, 4, 0, 0.4, 0.6, 1.0, 0);
    a[5 * MB_INST + 11] = 0.0;
    rect_at(a + 6 * MB_INST, 0, 0, 0, 0, 12, 0, 0, 0, 0);
    glass_forget();
    gl_set_fixed_dt(1.0 / 60.0);
    gl_present(a, 7, 0.95, 0.95, 0.95);
    gl_dirty_add(0, 0, W, H);
    a[8] = 0.93;
    gl_present(a, 7, 0.95, 0.95, 0.95);
    CHECK(gl_adaptive_settling());
    for (int step = 0; step < 3; step++) {
      a[5 * MB_INST + 11] = 0.3 * (step + 1);
      a[6 * MB_INST + 12] = (double)(step + 1);
      gl_dirty_add(8, 0, 36, 8);
      gl_present(a, 7, 0.95, 0.95, 0.95);
      slots_invalidate();
      CHECK(surface_as_whole(surface));
    }
    float f[7 * MB_INST];
    for (int i = 0; i < 7 * MB_INST; i++) f[i] = (float)a[i];
    double r[][4] = {{6, 16, 43, 18}, {4, 34, 92, 32}};
    int rn = 2;
    CHECK(mb_glass_damage_expand(f, 7, r, &rn, W, H, S));
    CHECK(rn == 1);
    gl_set_fixed_dt(0.0);
    glass_forget();
  }

  // Captures reached through another capture are closed too, including every shape of a merged liquid group.
  {
    float f[4 * MB_INST] = {0};
    const float x[] = {70, 10, 40, 160};
    const float id[] = {-2, -1, -1, -3};
    for (int i = 0; i < 4; i++) {
      float *a = f + i * MB_INST;
      a[0] = x[i]; a[1] = 40; a[2] = 10; a[3] = 10; a[5] = 6; a[20] = id[i];
    }
    f[MB_INST + 23] = 8;
    double r[][4] = {{12, 42, 1, 1}};
    int rn = 1;
    CHECK(mb_glass_damage_expand(f, 4, r, &rn, 200, 100, 1));
    CHECK(rn == 1);
    CHECK(r[0][0] <= 0 && r[0][0] + r[0][2] >= 84 && r[0][0] + r[0][2] < 150);
  }

  // Perf-29: (1) Stacked glass cache independence (top progressive blur + top liquid glass capsule + changing bottom
  // content must produce 0 blur rebuilds, while changing content under top progressive blur rebuilds both identically
  // to a fresh render); (2) GLES async PBO+fence same-side early stop within 4 frames; (3) progressive blur visible-box
  // scissor & ramp boundary fast-path pixel equivalence.
  {
    double sg[5 * MB_INST];
    // 0: full background
    rect_at(sg, 0, 0, W, H, 0, 0.94, 0.94, 0.92, 0);
    // 1: top content under progressive blur
    rect_at(sg + 1 * MB_INST, 10, 4, 40, 10, 0, 0.85, 0.20, 0.20, 0);
    // 2: bottom unrelated content (far below top glass & its blur margin)
    rect_at(sg + 2 * MB_INST, 10, 62, 60, 10, 0, 0.20, 0.45, 0.90, 0);
    // 3: top progressive frosted blur (kind 5, a[22] = -1, fade y from 14..22)
    rect_at(sg + 3 * MB_INST, 0, 0, W, 22, 5, 0.96, 0.96, 0.96, -30);
    sg[3 * MB_INST + 6] = 1.1;
    sg[3 * MB_INST + 7] = 4.0;
    sg[3 * MB_INST + 11] = 0.35;
    sg[3 * MB_INST + 15] = 1.0;
    sg[3 * MB_INST + 22] = -1.0;
    sg[3 * MB_INST + 54] = 22.0;  // fade bottom end
    sg[3 * MB_INST + 55] = 8.0;   // fade bottom length (y=0..14 full ramp=1, 14..22 ramp->0)
    // 4: top liquid glass capsule stacked over the progressive blur
    rect_at(sg + 4 * MB_INST, 12, 4, 44, 12, 6, 0.99, 0.99, 0.99, -31);
    sg[4 * MB_INST + 4] = 6.0;
    sg[4 * MB_INST + 6] = 1.0;
    sg[4 * MB_INST + 7] = 2.0;
    sg[4 * MB_INST + 11] = 0x67 / 255.0;
    sg[4 * MB_INST + 13] = 8.0;
    sg[4 * MB_INST + 14] = -1.0;
    sg[4 * MB_INST + 15] = 1.0;
    sg[4 * MB_INST + 21] = 4.0;

    glass_forget();
    gl_set_fixed_dt(1.0 / 60.0);
    made = blurs_made;
    gl_present(sg, 5, 0.94, 0.94, 0.92);
    CHECK(blurs_made == made + 2);
    CHECK(surface_as_fresh(surface));

    // Mutate bottom unrelated rect across 3 frames: neither top progressive nor stacked liquid glass may re-blur.
    for (int step = 0; step < 3; step++) {
      sg[2 * MB_INST + 8] = 0.20 + 0.25 * (step + 1);
      made = blurs_made;
      gl_present(sg, 5, 0.94, 0.94, 0.92);
      CHECK(blurs_made == made);
      CHECK(surface_as_fresh(surface));
    }

    // Mutate content under the top progressive blur: both top progressive and stacked liquid glass must re-blur.
    sg[1 * MB_INST + 9] = 0.80;
    made = blurs_made;
    gl_present(sg, 5, 0.94, 0.94, 0.92);
    CHECK(blurs_made == made + 2);
    CHECK(surface_as_fresh(surface));

    // GLES async PBO+fence same-side early stop: light->light (0.94 -> 0.92) stops settling within 4 frames.
    double es[3 * MB_INST];
    rect_at(es, 0, 0, W, H, 0, 0.95, 0.95, 0.95, 0);
    rect_at(es + MB_INST, 8, 28, 84, 16, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -32);
    es[MB_INST + 4] = 8.0;
    es[MB_INST + 6] = 1.0;
    es[MB_INST + 7] = 2.0;
    es[MB_INST + 11] = 0x67 / 255.0;
    es[MB_INST + 13] = 8.0;
    es[MB_INST + 14] = -1.0;
    es[MB_INST + 15] = 1.0;
    rect_at(es + 2 * MB_INST, 16, 30, 20, 12, 10, 0.11, 0.11, 0.11, 0);
    es[2 * MB_INST + 4] = 3.0;
    es[2 * MB_INST + 12] = 0.1; es[2 * MB_INST + 13] = 0.5;
    es[2 * MB_INST + 14] = 0.9; es[2 * MB_INST + 15] = 0.5;
    es[2 * MB_INST + 21] = 50.0; es[2 * MB_INST + 22] = 36.0; es[2 * MB_INST + 23] = 16.0;
    glass_forget();
    gl_present(es, 3, 0.95, 0.95, 0.95);
    CHECK(gl_adaptive_settling() == 0);
    es[8] = 0.93; es[9] = 0.93; es[10] = 0.93;
    gl_present(es, 3, 0.93, 0.93, 0.93);
    CHECK(gl_adaptive_settling() == 1);
    for (int s = 0; s < 4 && gl_adaptive_settling(); s++) {
      gl_present(es, 3, 0.93, 0.93, 0.93);
    }
    CHECK(gl_adaptive_settling() == 0);
    gl_set_fixed_dt(0.0);
    glass_forget();
  }

  // Progressive blur small-radius anti-ghosting regression: 1pt and 1px dark vertical/horizontal strokes over
  // a light background under blur=8.5, fade_h=68 progressive blur at both 2x and 1x scale must produce strictly
  // unimodal profiles (no 9-tap comb ghosting / secondary dark peaks) and monotonically attenuate center contrast.
  {
    static const int scales[2] = {2, 1};
    static const double v_ramps[6] = {0.06, 0.10, 0.14, 0.18, 0.24, 0.35};
    static const double h_ramps[3] = {0.10, 0.18, 0.24};
    GLuint pb_tex = 0, pb_fb = 0;
    for (int si = 0; si < 2; si++) {
      int sc = scales[si];
      fb_w = W * sc;
      fb_h = H * sc;
      cur_w = W;
      cur_h = H;
      cur_scale = (double)sc;
      if (pb_fb) { glDeleteFramebuffers(1, &pb_fb); pb_fb = 0; }
      if (pb_tex) { glDeleteTextures(1, &pb_tex); pb_tex = 0; }
      glGenTextures(1, &pb_tex);
      glBindTexture(GL_TEXTURE_2D, pb_tex);
      glTexStorage2D(GL_TEXTURE_2D, 1, GL_RGBA8, fb_w, fb_h);
      glGenFramebuffers(1, &pb_fb);
      glBindFramebuffer(GL_FRAMEBUFFER, pb_fb);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, pb_tex, 0);
      CHECK(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE);
      target_fb = pb_fb;
      canvas_ok = 0;

      double widths[2] = {1.0, 1.0 / (double)sc};
      int n_widths = (sc > 1) ? 2 : 1;
      for (int wi = 0; wi < n_widths; wi++) {
        double lw = widths[wi];
        // 1) Vertical stroke across the entire fade band (y=0..75)
        double pb[3 * MB_INST];
        rect_at(pb, 0, 0, W, H, 0, 0.96, 0.96, 0.96, 0);
        rect_at(pb + MB_INST, 50.0, 0.0, lw, H, 0, 0.05, 0.05, 0.05, 0);
        rect_at(pb + 2 * MB_INST, 0, 0, W, 68.0, 5, 0.96, 0.96, 0.96, -40);
        pb[2 * MB_INST + 6] = 1.0;
        pb[2 * MB_INST + 7] = 8.5;
        pb[2 * MB_INST + 11] = 0.15;
        pb[2 * MB_INST + 15] = 1.0;
        pb[2 * MB_INST + 22] = -1.0;
        pb[2 * MB_INST + 54] = 68.0;
        pb[2 * MB_INST + 55] = 68.0;
        glass_forget();
        gl_present(pb, 3, 0.96, 0.96, 0.96);
        unsigned char *px = pixels_of_fb(pb_fb);
        int prev_center = -1;
        int first_center = -1;
        int last_center = -1;
        int mono_ok = 1;
        int max_dip = 0;
        for (int ri = 0; ri < 6; ri++) {
          int py = (int)llround(68.0 * (1.0 - v_ramps[ri]) * (double)sc);
          if (py < 0) py = 0;
          if (py >= fb_h) py = fb_h - 1;
          int row = fb_h - 1 - py;
          int x0 = (int)floor(50.0 * (double)sc) - 2;
          int x1 = (int)ceil((50.0 + lw) * (double)sc) + 2;
          int xc = x0, min_l = 256;
          for (int x = x0; x <= x1; x++) {
            int l = px[(row * fb_w + x) * 4 + 1];
            if (l < min_l) { min_l = l; xc = x; }
          }
          if (ri == 0) first_center = min_l;
          last_center = min_l;
          if (prev_center >= 0 && min_l < prev_center - 2) {
            fprintf(stderr, "gles_render: prog-blur v-stroke center non-mono sc=%d lw=%.2f ramp=%.2f prev=%d cur=%d\n",
                    sc, lw, v_ramps[ri], prev_center, min_l);
            mono_ok = 0;
          }
          prev_center = min_l;
          for (int dir = -1; dir <= 1; dir += 2) {
            int max_seen = min_l;
            for (int dx = 1; dx <= 12; dx++) {
              int x = xc + dir * dx;
              if (x < 0 || x >= fb_w) break;
              int l = px[(row * fb_w + x) * 4 + 1];
              if (max_seen - l > max_dip) max_dip = max_seen - l;
              if (l < max_seen - 2) mono_ok = 0;
              if (l > max_seen) max_seen = l;
            }
          }
        }
        printf("gles_render: prog-blur v-stroke sc=%d lw=%.2f first=%d last=%d max_dip=%d\n",
               sc, lw, first_center, last_center, max_dip);
        CHECK(mono_ok);
        CHECK(last_center > first_center + 15);
        free(px);

        // 2) Horizontal strokes at representative small-radius ramps
        int h_mono_ok = 1;
        int h_max_dip = 0;
        for (int ri = 0; ri < 3; ri++) {
          double y_pt = 68.0 * (1.0 - h_ramps[ri]);
          double hp[3 * MB_INST];
          rect_at(hp, 0, 0, W, H, 0, 0.96, 0.96, 0.96, 0);
          rect_at(hp + MB_INST, 10.0, y_pt, 80.0, lw, 0, 0.05, 0.05, 0.05, 0);
          rect_at(hp + 2 * MB_INST, 0, 0, W, 68.0, 5, 0.96, 0.96, 0.96, -41);
          hp[2 * MB_INST + 6] = 1.0;
          hp[2 * MB_INST + 7] = 8.5;
          hp[2 * MB_INST + 11] = 0.15;
          hp[2 * MB_INST + 15] = 1.0;
          hp[2 * MB_INST + 22] = -1.0;
          hp[2 * MB_INST + 54] = 68.0;
          hp[2 * MB_INST + 55] = 68.0;
          glass_forget();
          gl_present(hp, 3, 0.96, 0.96, 0.96);
          unsigned char *hpx = pixels_of_fb(pb_fb);
          int px_x = 50 * sc;
          int y0 = (int)floor(y_pt * (double)sc) - 2;
          int y1 = (int)ceil((y_pt + lw) * (double)sc) + 2;
          int yc = y0, min_l = 256;
          for (int y = y0; y <= y1; y++) {
            int row = fb_h - 1 - y;
            int l = hpx[(row * fb_w + px_x) * 4 + 1];
            if (l < min_l) { min_l = l; yc = y; }
          }
          for (int dir = -1; dir <= 1; dir += 2) {
            int max_seen = min_l;
            for (int dy = 1; dy <= 10; dy++) {
              int y = yc + dir * dy;
              if (y < 0 || y >= fb_h) break;
              int row = fb_h - 1 - y;
              int l = hpx[(row * fb_w + px_x) * 4 + 1];
              if (max_seen - l > h_max_dip) h_max_dip = max_seen - l;
              if (l < max_seen - 2) h_mono_ok = 0;
              if (l > max_seen) max_seen = l;
            }
          }
          free(hpx);
        }
        printf("gles_render: prog-blur h-stroke sc=%d lw=%.2f max_dip=%d\n", sc, lw, h_max_dip);
        CHECK(h_mono_ok);
      }
    }
    if (pb_fb) glDeleteFramebuffers(1, &pb_fb);
    if (pb_tex) glDeleteTextures(1, &pb_tex);
    fb_w = W * S;
    fb_h = H * S;
    cur_w = W;
    cur_h = H;
    cur_scale = S;
    target_fb = surface;
    glBindFramebuffer(GL_FRAMEBUFFER, surface);
    canvas_ok = 0;
    glass_forget();
  }

  if (!failed) printf("gles_render: ok\n");
  return failed;
}
