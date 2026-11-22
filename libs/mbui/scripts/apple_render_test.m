// src/host/apple_render.m's tests: after mb_render_trim shrinks the layer's drawableSize to 1x1 (the window hidden,
// covered, minimized or the Mac asleep) and mb_render_set_size restores the window's size, the next frame is drawn
// whole into a new canvas and presented, never skipped by same_as_shown as equal to the frame before the trim; the
// blur under glass kept while what is under it is the same, never while a picture under it had no texture yet; three
// groups of glass on one screen each keeping its own blur, made again only for the one something moved under; frames
// handed to the presenting queue while it is busy drawn as the newest alone, what each said to differ joined, the
// glyphs put meanwhile kept, the canvas then the same to the byte as the frame drawn whole; and many frames in a row
// with sizes, trims and read-backs between them:
//   cc -Wall -fobjc-arc -I src/host -I "$MOON_HOME/include" scripts/apple_render_test.m -framework Foundation -framework QuartzCore -framework Metal -framework CoreGraphics -framework ImageIO -o out/apple_render_test && out/apple_render_test
#include <stdio.h>
#import "apple_render.m"

// picture 1's texture: none (not decoded yet) till a test makes one
static id<MTLTexture> picture_one;
id<MTLTexture> mb_image_texture(int iid) { return iid == 1 ? picture_one : nil; }
id<MTLTexture> mb_stream_texture(int sid) { (void)sid; return nil; }
int mb_views_take_moved(void) { return 0; }
int mb_views_frost(int n, const double *frosts) { (void)n, (void)frosts; return 0; }
int mb_views_count(void) { return 0; }
void mb_views_draw_under(CGContextRef ctx, double scale) { (void)ctx, (void)scale; }
void mb_text_set_scale(double scale) { (void)scale; }

static int failed;

#define CHECK(c)                                                      \
  do {                                                                \
    if (!(c)) {                                                       \
      fprintf(stderr, "%s:%d: failed: %s\n", __FILE__, __LINE__, #c); \
      failed = 1;                                                     \
    }                                                                 \
  } while (0)

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
  d[16] = 0;
  d[17] = 0;
  d[18] = 400;
  d[19] = 300;
  d[20] = tid;
}

// The canvas the window's frames were drawn into the same to the byte as its last frame drawn whole again.
static int canvas_as_whole(void) {
  int cw, ch, ww, wh;
  uint8_t *drawn = read_texture(canvas, &cw, &ch);
  uint8_t *whole = read_last(&ww, &wh);
  int same = cw == ww && ch == wh && memcmp(drawn, whole, (size_t)cw * ch * 4) == 0;
  free(drawn);
  free(whole);
  return same;
}

int main(void) {
  @autoreleasepool {
    CAMetalLayer *layer = [CAMetalLayer layer];
    mb_render_init(layer);
    CHECK(mlayer == layer);
    CHECK(mlayer.framebufferOnly == YES);
    CHECK(mlayer.opaque == YES);
    mb_render_set_size(400, 300, 2);
    CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(800, 600)));

    double inst[MB_INST] = {0};
    inst[0] = 10;
    inst[1] = 20;
    inst[2] = 100;
    inst[3] = 50;
    inst[16] = 0;
    inst[17] = 0;
    inst[18] = 400;
    inst[19] = 300;
    float f[MB_INST] = {0};
    for (int i = 0; i < MB_INST; i++) f[i] = (float)inst[i];
    last_inst = f;
    last_count = 1;
    last_bg[0] = 0.1;
    last_bg[1] = 0.2;
    last_bg[2] = 0.3;
    shown_w = 400;
    shown_h = 300;
    shown_scale = 2;
    shown_ok = 1;
    canvas_ok = 1;

    // An identical frame while shown is skipped.
    CHECK(same_as_shown(f, 1, 0.1, 0.2, 0.3) == 1);
    CHECK(glass_through(f, 1) == 0);

    // A frame with a visible hole (kind 9) turns mlayer.opaque off; once the hole leaves, mlayer.opaque is YES again.
    double hole[MB_INST] = {0};
    hole[0] = 10;
    hole[1] = 20;
    hole[2] = 100;
    hole[3] = 50;
    hole[5] = 9;
    hole[16] = 0;
    hole[17] = 0;
    hole[18] = 400;
    hole[19] = 300;
    float hole_f[MB_INST];
    for (int i = 0; i < MB_INST; i++) hole_f[i] = (float)hole[i];
    CHECK(glass_through(hole_f, 1) == 1);
    last_inst = NULL;
    mb_render_present(hole, 1, 0.1, 0.2, 0.3);
    CHECK(mlayer.opaque == NO);
    CHECK(shown_ok == 1);
    mb_render_present(inst, 1, 0.1, 0.2, 0.3);
    CHECK(mlayer.opaque == YES);
    CHECK(shown_ok == 1);
    present_drain();
    // A frame drawn whole with no glass goes straight into the drawable: the canvas holds no frame after it.
    CHECK(canvas_ok == 0);
    // One said to differ in a part is drawn into the canvas (whole, as it held none) and copied.
    double moved[MB_INST];
    memcpy(moved, inst, sizeof moved);
    moved[0] = 12;
    mb_host_render_dirty(0, 0, 200, 100);
    mb_render_present(moved, 1, 0.1, 0.2, 0.3);
    CHECK(shown_ok == 1);
    present_drain();
    CHECK(canvas_ok == 1);
    // One with glass (slot 20 negative) goes through the canvas, whose copy its blur reads, though drawn whole.
    double glass[2 * MB_INST];
    memcpy(glass, inst, sizeof inst);
    memcpy(glass + MB_INST, inst, sizeof inst);
    glass[MB_INST + 5] = 5;
    glass[MB_INST + 7] = 10;
    glass[MB_INST + 11] = 0.5;
    glass[MB_INST + 20] = -1;
    canvas_ok = 0;
    mb_render_present(glass, 2, 0.1, 0.2, 0.3);
    CHECK(shown_ok == 1);
    present_drain();
    CHECK(canvas_ok == 1);

    // The blur under glass is kept while what is drawn under it is the same: what is over it changing draws none
    // again; what is under it changing does.
    {
      double g3[3 * MB_INST];
      rect_at(g3, 20, 20, 200, 100, 0, 0.9, 0.1, 0.1, 0);
      rect_at(g3 + MB_INST, 40, 40, 120, 60, 5, 1, 1, 1, -2);
      g3[MB_INST + 7] = 10;
      g3[MB_INST + 11] = 0.5;
      rect_at(g3 + 2 * MB_INST, 300, 200, 20, 20, 0, 0.1, 0.1, 0.9, 0);
      mb_render_present(g3, 3, 0.1, 0.2, 0.3);
      present_drain();
      int made = blurs_made;
      CHECK(kept_ok == 1);
      g3[2 * MB_INST + 0] = 320;  // over the glass: moved
      mb_render_present(g3, 3, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made);
      CHECK(kept_ok == 1);
      g3[0] = 24;  // under it: moved
      mb_render_present(g3, 3, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 1);
      CHECK(kept_ok == 1);

      // A picture under it with no texture yet (drawn without it): that blur is not kept as what is under it, and
      // once the picture has its texture, it is drawn and kept.
      double p3[3 * MB_INST];
      memcpy(p3, g3, sizeof p3);
      rect_at(p3, 20, 20, 200, 100, 4, 1, 1, 1, 1);
      p3[12] = 0;
      p3[13] = 0;
      p3[14] = 1;
      p3[15] = 1;
      picture_one = nil;
      mb_render_present(p3, 3, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(kept_ok == 0);
      MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                    width:2
                                                                                   height:2
                                                                                mipmapped:NO];
      picture_one = [dev newTextureWithDescriptor:td];
      uint8_t px[16] = {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255};
      [picture_one replaceRegion:MTLRegionMake2D(0, 0, 2, 2) mipmapLevel:0 withBytes:px bytesPerRow:8];
      p3[2 * MB_INST + 0] = 330;  // (a frame of its own: the same numbers would be the one shown)
      made = blurs_made;
      mb_render_present(p3, 3, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 1);
      CHECK(kept_ok == 1);
      picture_one = nil;
    }

    // Three groups of glass on one screen (frosted at the top, liquid in the middle, frosted at the foot, each with
    // something of its own under it, a caret over all): each keeps its own blur. A frame where only what is over them
    // moves makes none; one where something moves under the middle one alone makes that one's again, the others kept.
    // The canvas each time the same to the byte as the frame drawn whole with every blur made anew.
    {
      double s3[8 * MB_INST];
      rect_at(s3, 0, 0, 400, 300, 0, 0.95, 0.95, 0.9, 0);
      rect_at(s3 + 1 * MB_INST, 32, 16, 104, 32, 0, 0.9, 0.1, 0.1, 0);
      rect_at(s3 + 2 * MB_INST, 20, 8, 144, 40, 5, 1, 1, 1, -2);
      s3[2 * MB_INST + 7] = 8;
      s3[2 * MB_INST + 11] = 0.5;
      rect_at(s3 + 3 * MB_INST, 248, 128, 80, 32, 0, 0.1, 0.7, 0.2, 0);
      rect_at(s3 + 4 * MB_INST, 240, 120, 120, 48, 6, 1, 1, 1, -3);
      s3[4 * MB_INST + 4] = 24;
      s3[4 * MB_INST + 7] = 8;
      s3[4 * MB_INST + 11] = 0.3;
      s3[4 * MB_INST + 21] = 8;
      s3[4 * MB_INST + 23] = 4;
      rect_at(s3 + 5 * MB_INST, 40, 240, 100, 24, 0, 0.2, 0.2, 0.9, 0);
      rect_at(s3 + 6 * MB_INST, 20, 228, 160, 48, 5, 1, 1, 1, -4);
      s3[6 * MB_INST + 7] = 8;
      s3[6 * MB_INST + 11] = 0.5;
      rect_at(s3 + 7 * MB_INST, 360, 260, 8, 24, 0, 0, 0, 0, 0);
      int made = blurs_made;
      mb_render_present(s3, 8, 0.1, 0.2, 0.3);
      present_drain();
      printf("apple_render_test: three groups, first frame: %d blurs\n", blurs_made - made);
      CHECK(blurs_made == made + 3);
      glass_forget();
      CHECK(canvas_as_whole());
      for (int i = 0; i < 3; i++) {
        s3[7 * MB_INST + 1] = 250 + 4 * i;  // the caret: moved
        made = blurs_made;
        mb_render_present(s3, 8, 0.1, 0.2, 0.3);
        present_drain();
        printf("apple_render_test: three groups, the caret moved: %d blurs\n", blurs_made - made);
        CHECK(blurs_made == made);
        CHECK(kept_ok == 1);
        CHECK(canvas_as_whole());
        glass_forget();
        CHECK(canvas_as_whole());
      }
      s3[3 * MB_INST + 0] = 256;  // under the liquid glass alone: moved
      made = blurs_made;
      mb_render_present(s3, 8, 0.1, 0.2, 0.3);
      present_drain();
      printf("apple_render_test: three groups, what is under the middle one moved: %d blurs\n", blurs_made - made);
      CHECK(blurs_made == made + 1);
      glass_forget();
      CHECK(canvas_as_whole());
      s3[1 * MB_INST + 0] = 36;  // under the top one: moved, that one's alone made again
      made = blurs_made;
      mb_render_present(s3, 8, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 1);
      glass_forget();
      CHECK(canvas_as_whole());
    }

    // Fourteen independent glass groups of mixed sizes and blur radii on one screen: all 14 stay cached when only the
    // top-level caret moves (blurs_made delta == 0) and match a fresh render byte-for-byte.
    {
      double g14[16 * MB_INST];
      static const double blurs[4] = {1.0, 3.0, 7.0, 16.0};
      rect_at(g14, 0, 0, 400, 300, 0, 0.92, 0.90, 0.88, 0);
      for (int i = 0; i < 14; i++) {
        int col = i % 7, row = i / 7;
        double gx = 8 + col * 52;
        double gy = 8 + row * 128;
        double gw = 32 + i * 4;
        double gh = 24 + i * 4;
        double *d = g14 + (i + 1) * MB_INST;
        rect_at(d, gx, gy, gw, gh, 5, 1, 1, 1, -(101 + i));
        d[7] = blurs[i % 4];
        d[11] = 0.4;
      }
      rect_at(g14 + 15 * MB_INST, 368, 264, 8, 24, 0, 0, 0, 0, 0);
      glass_free();
      int made = blurs_made;
      mb_render_present(g14, 16, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 14);
      CHECK(canvas_as_whole());
      g14[15 * MB_INST + 0] = 376;  // only top-level caret moves
      made = blurs_made;
      mb_render_present(g14, 16, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made);
      CHECK(kept_ok == 1);
      CHECK(canvas_as_whole());
      glass_forget();
      CHECK(canvas_as_whole());
    }

    // Frames handed over while the queue is busy (here held by a block of the test's): drawn once, the newest, in
    // part, what both said to differ joined; the glyph put between them kept; the canvas then the same to the byte as
    // that frame drawn whole.
    {
      double two[2 * MB_INST];
      rect_at(two, 20, 20, 40, 40, 0, 0.9, 0.2, 0.1, 0);
      rect_at(two + MB_INST, 200, 150, 40, 40, 0, 0.1, 0.8, 0.3, 0);
      // (a frame drawn in part first: the canvas then holds it)
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      present_drain();
      mb_host_render_dirty(18, 18, 46, 44);
      two[0] = 22;
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(canvas_ok == 1);
      CHECK(canvas_as_whole());
      dispatch_semaphore_t gate = dispatch_semaphore_create(0);
      dispatch_async(present_q, ^{
        dispatch_semaphore_wait(gate, DISPATCH_TIME_FOREVER);
      });
      int drawn = present_drawn;
      two[0] = 60;  // the first moved, said
      mb_host_render_dirty(18, 18, 84, 44);
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      uint8_t glyph[4] = {11, 22, 33, 44};
      mb_atlas_upload(0, 8, 4, 2, 2, glyph);
      two[MB_INST + 1] = 100;  // then the second, said: the first's part not said again
      mb_host_render_dirty(198, 98, 44, 94);
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      CHECK(shown_ok == 1);
      CHECK(present_drawn == drawn);
      dispatch_semaphore_signal(gate);
      present_drain();
      CHECK(present_drawn == drawn + 1);
      // (put in by the queue for the frame drawn, before anything here reads back)
      uint8_t back[4] = {0};
      [atlas getBytes:back bytesPerRow:2 fromRegion:MTLRegionMake2D(8, 4, 2, 2) mipmapLevel:0];
      CHECK(memcmp(back, glyph, 4) == 0);
      CHECK(canvas_ok == 1);
      CHECK(canvas_as_whole());

      // Many frames in a row, the queue never waited for but by what reads back, resizes or trims: each frame's
      // canvas, when read, the frame drawn whole.
      for (int i = 0; i < 400; i++) {
        two[0] = 20 + (i * 7) % 300;
        two[MB_INST + 1] = 10 + (i * 13) % 200;
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(two, 2, 0.1, 0.2, 0.3);
        if (i % 97 == 50) {
          mb_render_trim();
          CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(1, 1)));
        }
        if (i % 41 == 20) mb_render_set_size(i % 2 ? 380 : 400, 300, 2);
        if (i % 41 == 30) mb_render_set_size(400, 300, 2);
        if (i % 53 == 0) {
          int fw, fh;
          free(read_last(&fw, &fh));
          CHECK(fw == (int)round(vw * 2) && fh == 600);
        }
      }
      mb_render_set_size(400, 300, 2);
      two[0] = 33;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      two[0] = 35;
      mb_host_render_dirty(30, 18, 50, 44);
      mb_render_present(two, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(canvas_ok == 1);
      CHECK(canvas_as_whole());
      mb_render_trim();
      CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(1, 1)));
      CHECK(canvas_ok == 0);
      mb_render_set_size(400, 300, 2);
    }

    // What drawing holds beyond its frames given back: the trim lets go of the read back's texture and glass's (made
    // again by the next read and the next glass, the canvas then the same to the byte as the frame drawn whole); and
    // glass's textures go once MB_GLASS_IDLE frames in a row drew none, the glass after them blurred anew, as the frame
    // drawn whole.
    {
      double g1[2 * MB_INST];
      rect_at(g1, 30, 30, 160, 80, 0, 0.9, 0.1, 0.1, 0);
      rect_at(g1 + MB_INST, 20, 20, 200, 100, 6, 1, 1, 1, -5);
      g1[MB_INST + 4] = 24;
      g1[MB_INST + 7] = 8;
      g1[MB_INST + 11] = 0.3;
      g1[MB_INST + 21] = 8;
      g1[MB_INST + 23] = 4;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(g1, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(lv[0] != nil && lv_w > 0);
      CHECK(slot_bt[0] != nil);
      // the same capture frosted (kind 5), kept in the same slot
      g1[MB_INST + 5] = 5;
      g1[0] = 32;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(g1, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(slot_bt[0] != nil);
      CHECK(canvas_as_whole());

      int fw, fh;
      free(read_last(&fw, &fh));
      CHECK(read_tex != nil);
      mb_render_trim();
      CHECK(read_tex == nil);
      CHECK(lv[0] == nil && ltmp == nil && lv_w == 0 && lv_h == 0);
      CHECK(slot_bt[0] == nil);
      mb_render_set_size(400, 300, 2);
      g1[0] = 34;
      mb_render_present(g1, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(lv[0] != nil);
      CHECK(canvas_as_whole());

      // frames with no glass: the glass's textures kept till the MB_GLASS_IDLE-th, then let go
      double plain[MB_INST];
      rect_at(plain, 30, 30, 160, 80, 0, 0.9, 0.1, 0.1, 0);
      for (int i = 1; i <= MB_GLASS_IDLE; i++) {
        plain[0] = 30 + i % 50;  // (each a frame of its own: the same numbers would be the one shown)
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(plain, 1, 0.1, 0.2, 0.3);
        present_drain();
        if (i == MB_GLASS_IDLE - 1) CHECK(lv[0] != nil && slot_bt[0] != nil);
      }
      CHECK(lv[0] == nil && ltmp == nil && lv_w == 0);
      for (int i = 0; i < MB_GLASS_SLOTS; i++) CHECK(slot_bt[i] == nil);
      // a frame with glass after: its blur made anew, as the frame drawn whole
      int made = blurs_made;
      g1[0] = 36;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(g1, 2, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 1);
      CHECK(lv[0] != nil);
      CHECK(canvas_as_whole());
      // a frame with glass among those without keeps them: the count starts again
      for (int i = 1; i < MB_GLASS_IDLE; i++) {
        plain[0] = 30 + i % 50;
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(plain, 1, 0.1, 0.2, 0.3);
        present_drain();
      }
      g1[0] = 38;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(g1, 2, 0.1, 0.2, 0.3);
      present_drain();
      for (int i = 1; i < MB_GLASS_IDLE; i++) {
        plain[0] = 30 + i % 50;
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(plain, 1, 0.1, 0.2, 0.3);
        present_drain();
      }
      CHECK(lv[0] != nil);
    }

    // Unmerged liquid glass (kind 6, a[23] <= 0):
    // (1) single shape with merge=0 (tight quad + direct sd_rr) matches merge=1e-7 (merged_liquid + sd_group, same float32 quad bounds) byte-for-byte;
    // (2) two unmerged liquid shapes separated by a shadow (kind 2) sharing one capture make only 1 blur and preserve
    //     each instance's own spot, matching separate captures byte-for-byte at k == 0.
    {
      double eq[2 * MB_INST];
      rect_at(eq, 0, 0, 400, 300, 0, 0.85, 0.30, 0.20, 0);
      rect_at(eq + MB_INST, 70, 90, 220, 96, 6, 1, 1, 1, -9);
      eq[MB_INST + 4] = 48;
      eq[MB_INST + 6] = 1;
      eq[MB_INST + 7] = 2;
      eq[MB_INST + 11] = 0.25;
      eq[MB_INST + 12] = 0.8;
      eq[MB_INST + 13] = 10;
      eq[MB_INST + 14] = 0;
      eq[MB_INST + 15] = 1;
      eq[MB_INST + 21] = 8;
      eq[MB_INST + 22] = 0.2;
      eq[MB_INST + 23] = 0;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(eq, 2, 0.1, 0.2, 0.3);
      present_drain();
      int sw, sh;
      uint8_t *px_single = read_texture(canvas, &sw, &sh);

      eq[MB_INST + 23] = 1e-7;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(eq, 2, 0.1, 0.2, 0.3);
      present_drain();
      int mw, mh;
      uint8_t *px_merged = read_texture(canvas, &mw, &mh);
      CHECK(sw == mw && sh == mh && memcmp(px_single, px_merged, (size_t)sw * sh * 4) == 0);
      free(px_single);
      free(px_merged);

      double lq[5 * MB_INST];
      rect_at(lq, 0, 0, 400, 300, 0, 0.92, 0.90, 0.85, 0);
      rect_at(lq + 1 * MB_INST, 20, 180, 340, 72, 0, 0.85, 0.25, 0.20, 0);
      // left capsule (no spot, merge=0)
      rect_at(lq + 2 * MB_INST, 24, 192, 160, 56, 6, 1, 1, 1, -9);
      lq[2 * MB_INST + 4] = 28;
      lq[2 * MB_INST + 6] = 1;
      lq[2 * MB_INST + 7] = 1.5;  // sp = 3.0 -> k == 0
      lq[2 * MB_INST + 11] = 0.25;
      lq[2 * MB_INST + 12] = 0.8;
      lq[2 * MB_INST + 13] = 10;
      lq[2 * MB_INST + 14] = 0;
      lq[2 * MB_INST + 15] = 1;
      lq[2 * MB_INST + 21] = 4;
      lq[2 * MB_INST + 22] = 0;
      lq[2 * MB_INST + 23] = 0;
      // shadow between the two shapes (outside the right disc's capture box)
      rect_at(lq + 3 * MB_INST, 24, 192, 40, 20, 2, 0, 0, 0, 0);
      lq[3 * MB_INST + 7] = 2;
      lq[3 * MB_INST + 11] = 0.2;
      // right disc (with its own spot, merge=0, sharing capture -9)
      rect_at(lq + 4 * MB_INST, 280, 192, 56, 56, 6, 1, 1, 1, -9);
      lq[4 * MB_INST + 4] = 28;
      lq[4 * MB_INST + 6] = 1;
      lq[4 * MB_INST + 7] = 1.5;
      lq[4 * MB_INST + 11] = 0.25;
      lq[4 * MB_INST + 12] = 0.8;
      lq[4 * MB_INST + 13] = 10;
      lq[4 * MB_INST + 14] = 537.0 * 4096.0 + 528.0 + 1.0;
      lq[4 * MB_INST + 15] = 1;
      lq[4 * MB_INST + 21] = 4;
      lq[4 * MB_INST + 22] = 0;
      lq[4 * MB_INST + 23] = 0;

      glass_forget();
      int made = blurs_made;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lq, 5, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 1);
      uint8_t *px_lq_shared = read_texture(canvas, &sw, &sh);

      lq[2 * MB_INST + 20] = -10;
      lq[4 * MB_INST + 20] = -11;
      glass_forget();
      made = blurs_made;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lq, 5, 0.1, 0.2, 0.3);
      present_drain();
      CHECK(blurs_made == made + 2);
      int sep_w, sep_h;
      uint8_t *px_lq_sep = read_texture(canvas, &sep_w, &sep_h);
      CHECK(sw == sep_w && sh == sep_h && memcmp(px_lq_shared, px_lq_sep, (size_t)sw * sh * 4) == 0);
      free(px_lq_shared);
      free(px_lq_sep);
    }

    // Asymmetric 4-corner merged_liquid (rr = 24,24,0,0 sheet merged with pill) + Glass::clear() micro-veil vs pure lens:
    {
      double as[3 * MB_INST];
      rect_at(as, 0, 0, 400, 300, 0, 0.10, 0.12, 0.16, 0);
      // Sheet with top-rounded, bottom-square corners (24, 24, 0, 0)
      rect_at(as + 1 * MB_INST, 60, 100, 160, 120, 6, 1, 1, 1, -12);
      as[1 * MB_INST + 4] = 24;
      as[1 * MB_INST + 6] = 1;
      as[1 * MB_INST + 7] = 1;
      as[1 * MB_INST + 11] = 0.25;
      as[1 * MB_INST + 12] = 0.55;
      as[1 * MB_INST + 13] = 14;
      as[1 * MB_INST + 15] = 1;
      as[1 * MB_INST + 21] = 9;
      as[1 * MB_INST + 22] = 0.18;
      as[1 * MB_INST + 23] = 16;
      as[1 * MB_INST + 36] = 24;
      as[1 * MB_INST + 37] = 24;
      as[1 * MB_INST + 38] = 0;
      as[1 * MB_INST + 39] = 0;
      // Adjacent circular button merged with the sheet
      rect_at(as + 2 * MB_INST, 226, 128, 56, 56, 6, 1, 1, 1, -12);
      as[2 * MB_INST + 4] = 28;
      as[2 * MB_INST + 6] = 1;
      as[2 * MB_INST + 7] = 1;
      as[2 * MB_INST + 11] = 0.25;
      as[2 * MB_INST + 12] = 0.55;
      as[2 * MB_INST + 13] = 14;
      as[2 * MB_INST + 15] = 1;
      as[2 * MB_INST + 21] = 9;
      as[2 * MB_INST + 22] = 0.18;
      as[2 * MB_INST + 23] = 16;
      as[2 * MB_INST + 36] = 28;
      as[2 * MB_INST + 37] = 28;
      as[2 * MB_INST + 38] = 28;
      as[2 * MB_INST + 39] = 28;

      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(as, 3, 0.1, 0.12, 0.16);
      present_drain();
      int aw, ah;
      uint8_t *px_as = read_texture(canvas, &aw, &ah);
      // BGRA8Unorm top-down at scale 2
      uint8_t *bg_p = px_as + (10 * aw + 10) * 4;
      uint8_t *tl_p = px_as + (206 * aw + 126) * 4;  // (63, 103) outside top-left rounded corner (r=24)
      uint8_t *bl_p = px_as + (434 * aw + 126) * 4;  // (63, 217) inside bottom-left square corner (r=0)
      CHECK(abs((int)tl_p[1] - (int)bg_p[1]) <= 2 && abs((int)tl_p[2] - (int)bg_p[2]) <= 2);
      CHECK((int)bl_p[2] > 90 && (int)bl_p[1] > 90);
      free(px_as);

      // Glass::clear() (col.a = 26/255 ~ 0.102, blur = 0) yields +0.126 veil vs pure lens (col.a = 0, blur = 0) zero veil
      double cl[3 * MB_INST];
      rect_at(cl, 0, 0, 400, 300, 0, 0.08, 0.08, 0.10, 0);
      rect_at(cl + 1 * MB_INST, 40, 80, 120, 100, 6, 1, 1, 1, -13);
      cl[1 * MB_INST + 4] = 24;
      cl[1 * MB_INST + 6] = 1;
      cl[1 * MB_INST + 7] = 0;
      cl[1 * MB_INST + 11] = 26.0 / 255.0;
      cl[1 * MB_INST + 12] = 0.6;
      cl[1 * MB_INST + 13] = 14;
      cl[1 * MB_INST + 15] = 1;
      cl[1 * MB_INST + 21] = 16;
      cl[1 * MB_INST + 22] = 0;
      cl[1 * MB_INST + 23] = 0;
      rect_at(cl + 2 * MB_INST, 220, 80, 120, 100, 6, 1, 1, 1, -14);
      cl[2 * MB_INST + 4] = 24;
      cl[2 * MB_INST + 6] = 1;
      cl[2 * MB_INST + 7] = 0;
      cl[2 * MB_INST + 11] = 0.0;
      cl[2 * MB_INST + 12] = 0.6;
      cl[2 * MB_INST + 13] = 14;
      cl[2 * MB_INST + 15] = 1;
      cl[2 * MB_INST + 21] = 16;
      cl[2 * MB_INST + 22] = 0;
      cl[2 * MB_INST + 23] = 0;

      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(cl, 3, 0.08, 0.08, 0.10);
      present_drain();
      uint8_t *px_cl = read_texture(canvas, &aw, &ah);
      uint8_t *cl_bg = px_cl + (10 * aw + 10) * 4;
      uint8_t *cl_veil = px_cl + (260 * aw + 200) * 4;  // center of Glass::clear()
      uint8_t *cl_lens = px_cl + (260 * aw + 560) * 4;  // center of pure clear optical lens
      CHECK((int)cl_veil[1] >= 44 && (int)cl_veil[1] <= 62);
      CHECK(abs((int)cl_lens[1] - (int)cl_bg[1]) <= 2 && abs((int)cl_lens[2] - (int)cl_bg[2]) <= 2);
      free(px_cl);

      // Wave 3A (1): clear-lens optical zoom (slot 7 = -(zoom - 1.0)) magnifies centered backdrop
      double zm[3 * MB_INST];
      rect_at(zm, 0, 0, 400, 300, 0, 0.05, 0.05, 0.08, 0);
      // Red square centered at (100, 130), half-width 14pt -> x in [86, 114]
      rect_at(zm + 1 * MB_INST, 86, 116, 28, 28, 0, 0.95, 0.10, 0.10, 0);
      // Clear liquid lens (40, 80, 120, 100), center (100, 130), refraction = 0 so only zoom shifts sample
      rect_at(zm + 2 * MB_INST, 40, 80, 120, 100, 6, 1, 1, 1, -15);
      zm[2 * MB_INST + 4] = 24;
      zm[2 * MB_INST + 6] = 1;
      zm[2 * MB_INST + 7] = 0.0;  // zoom = 1.0
      zm[2 * MB_INST + 11] = 0.0;
      zm[2 * MB_INST + 12] = 0.0;
      zm[2 * MB_INST + 13] = 8;
      zm[2 * MB_INST + 15] = 1;
      zm[2 * MB_INST + 21] = 0;
      zm[2 * MB_INST + 22] = 0;
      zm[2 * MB_INST + 23] = 0;

      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(zm, 3, 0.05, 0.05, 0.08);
      present_drain();
      uint8_t *px_z1 = read_texture(canvas, &aw, &ah);
      // Probe (116, 130) -> (232, 260) at 2x: outside [86, 114] at zoom=1.0 -> dark background
      uint8_t *z1_p = px_z1 + (260 * aw + 232) * 4;
      CHECK((int)z1_p[2] < 40);
      free(px_z1);

      zm[2 * MB_INST + 7] = -0.25;  // zoom = 1.25 -> sampleBase.x = 100 + 16/1.25 = 112.8 (inside red square!)
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(zm, 3, 0.05, 0.05, 0.08);
      present_drain();
      uint8_t *px_z2 = read_texture(canvas, &aw, &ah);
      uint8_t *z2_p = px_z2 + (260 * aw + 232) * 4;
      CHECK((int)z2_p[2] > 200);
      free(px_z2);

      // Wave 3A (2): global ambient light_angle rotates specular glint by 90 deg and restores bit-exact at 0.0
      double la_inst[2 * MB_INST];
      rect_at(la_inst, 0, 0, 400, 300, 0, 0.10, 0.10, 0.12, 0);
      rect_at(la_inst + 1 * MB_INST, 100, 80, 120, 120, 6, 0.12, 0.12, 0.12, -16);
      la_inst[1 * MB_INST + 4] = 28;
      la_inst[1 * MB_INST + 6] = 1;
      la_inst[1 * MB_INST + 7] = 1.0;
      la_inst[1 * MB_INST + 11] = 0.5;
      la_inst[1 * MB_INST + 12] = 1.0;
      la_inst[1 * MB_INST + 13] = 12;
      la_inst[1 * MB_INST + 15] = 1;
      la_inst[1 * MB_INST + 21] = 0;
      la_inst[1 * MB_INST + 22] = 0;
      la_inst[1 * MB_INST + 23] = 0;

      mb_host_glass_light_angle(0.0);
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(la_inst, 2, 0.10, 0.10, 0.12);
      present_drain();
      uint8_t *px_la0 = read_texture(canvas, &aw, &ah);
      // Top edge (160, 80.5) -> (320, 161); Left edge (100.5, 140) -> (201, 280)
      int top0 = (int)px_la0[(161 * aw + 320) * 4 + 1];
      int left0 = (int)px_la0[(280 * aw + 201) * 4 + 1];
      CHECK(top0 > left0 + 30);

      mb_host_glass_light_angle(1.5707963267948966);  // PI / 2
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(la_inst, 2, 0.10, 0.10, 0.12);
      present_drain();
      uint8_t *px_la90 = read_texture(canvas, &aw, &ah);
      int top90 = (int)px_la90[(161 * aw + 320) * 4 + 1];
      int left90 = (int)px_la90[(280 * aw + 201) * 4 + 1];
      int right90 = (int)px_la90[(280 * aw + 439) * 4 + 1];
      CHECK(left90 > top90 + 30);
      CHECK(right90 > top90 + 30);
      free(px_la90);

      mb_host_glass_light_angle(0.0);
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(la_inst, 2, 0.10, 0.10, 0.12);
      present_drain();
      uint8_t *px_la0_again = read_texture(canvas, &aw, &ah);
      CHECK(memcmp(px_la0, px_la0_again, (size_t)aw * (size_t)ah * 4) == 0);
      free(px_la0);
      free(px_la0_again);

      // Neutral light liquid glass density (kind 6, !is_clear && !is_dark): alpha <= 0.41 keeps the 0.4032 baseline to
      // the byte (0xFDFCFD50 and 0xFDFCFD67 draw the same), while a dense veil (0xFDFCFDD9 ~ 0.851) emits its own alpha
      // and fades transmittance, lift and chroma to 0, so over black it is far brighter and over saturated blue it
      // stays neutral.
      double ld[2 * MB_INST];
      uint8_t *px_ld[4];
      // (alpha byte, backdrop r, g, b)
      static const double ld_case[4][4] = {
          {0x50, 0, 0, 0}, {0x67, 0, 0, 0}, {0xD9, 0, 0, 0}, {0xD9, 0.0, 0.4, 1.0}};
      for (int i = 0; i < 4; i++) {
        rect_at(ld, 0, 0, 400, 300, 0, ld_case[i][1], ld_case[i][2], ld_case[i][3], 0);
        rect_at(ld + MB_INST, 100, 80, 200, 140, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -17);
        ld[MB_INST + 4] = 28;
        ld[MB_INST + 6] = 1;
        ld[MB_INST + 7] = 1.0;
        ld[MB_INST + 11] = ld_case[i][0] / 255.0;
        ld[MB_INST + 12] = 0.0;
        ld[MB_INST + 13] = 12;
        ld[MB_INST + 15] = 1;
        ld[MB_INST + 21] = 0;
        ld[MB_INST + 22] = 0;
        ld[MB_INST + 23] = 0;
        glass_forget();
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(ld, 2, ld_case[i][1], ld_case[i][2], ld_case[i][3]);
        present_drain();
        px_ld[i] = read_texture(canvas, &aw, &ah);
      }
      // centre (200, 150) -> (400, 300) at 2x; the canvas is BGRA
      double ld_lum[4];
      for (int i = 0; i < 4; i++) {
        uint8_t *c = px_ld[i] + (300 * aw + 400) * 4;
        ld_lum[i] = (0.2126 * c[2] + 0.7152 * c[1] + 0.0722 * c[0]) / 255.0;
        printf("apple_render: light glass 0x%02X over (%.1f, %.1f, %.1f): rgb %d %d %d, luma %.4f\n",
               (int)ld_case[i][0], ld_case[i][1], ld_case[i][2], ld_case[i][3], c[2], c[1], c[0], ld_lum[i]);
      }
      CHECK(memcmp(px_ld[0], px_ld[1], (size_t)aw * (size_t)ah * 4) == 0);
      CHECK(ld_lum[1] >= 0.25 && ld_lum[1] <= 0.36);
      CHECK(ld_lum[2] >= 0.80 && ld_lum[2] > ld_lum[1] + 0.40);
      CHECK(px_ld[3][(300 * aw + 400) * 4 + 2] >= (int)(0.72 * 255.0 + 0.5));
      for (int i = 0; i < 4; i++) free(px_ld[i]);

      // Neutral dark liquid glass density (kind 6, is_dark): alpha <= 0.41 keeps the regular baseline to the byte
      // (0x20202050 and 0x20202067 draw the same), while dense veils (0x202020BF 75%, 0x202020D9 85%) fade
      // transmittance, lift and chroma toward 0, so over white they stay dark for white ink and over saturated blue
      // chroma is cleanly attenuated.
      double dd[2 * MB_INST];
      uint8_t *px_dd[5];
      // (alpha byte, backdrop r, g, b)
      static const double dd_case[5][4] = {
          {0x50, 1, 1, 1}, {0x67, 1, 1, 1}, {0xBF, 1, 1, 1}, {0xD9, 1, 1, 1}, {0xD9, 0.0, 0.4, 1.0}};
      for (int i = 0; i < 5; i++) {
        rect_at(dd, 0, 0, 400, 300, 0, dd_case[i][1], dd_case[i][2], dd_case[i][3], 0);
        rect_at(dd + MB_INST, 100, 80, 200, 140, 6, 32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0, -17);
        dd[MB_INST + 4] = 28;
        dd[MB_INST + 6] = 1;
        dd[MB_INST + 7] = 1.0;
        dd[MB_INST + 11] = dd_case[i][0] / 255.0;
        dd[MB_INST + 12] = 0.0;
        dd[MB_INST + 13] = 12;
        dd[MB_INST + 15] = 1;
        dd[MB_INST + 21] = 0;
        dd[MB_INST + 22] = 0;
        dd[MB_INST + 23] = 0;
        glass_forget();
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(dd, 2, dd_case[i][1], dd_case[i][2], dd_case[i][3]);
        present_drain();
        px_dd[i] = read_texture(canvas, &aw, &ah);
      }
      double dd_lum[5];
      for (int i = 0; i < 5; i++) {
        uint8_t *c = px_dd[i] + (300 * aw + 400) * 4;
        dd_lum[i] = (0.2126 * c[2] + 0.7152 * c[1] + 0.0722 * c[0]) / 255.0;
        printf("apple_render: dark glass 0x%02X over (%.1f, %.1f, %.1f): rgb %d %d %d, luma %.4f\n",
               (int)dd_case[i][0], dd_case[i][1], dd_case[i][2], dd_case[i][3], c[2], c[1], c[0], dd_lum[i]);
      }
      CHECK(memcmp(px_dd[0], px_dd[1], (size_t)aw * (size_t)ah * 4) == 0);
      CHECK(dd_lum[1] >= 0.55 && dd_lum[1] <= 0.74);
      CHECK(dd_lum[2] <= 0.36 && dd_lum[2] <= dd_lum[1] - 0.25);
      CHECK(dd_lum[3] <= 0.30 && dd_lum[3] < dd_lum[2]);
      uint8_t *dd_blue = px_dd[4] + (300 * aw + 400) * 4;
      CHECK(((double)dd_blue[0] - (double)dd_blue[2]) / 255.0 <= 0.28);
      for (int i = 0; i < 5; i++) free(px_dd[i]);

      // Dedicated ONE_KIND=13 (unmerged liquid, merge=0) vs ONE_KIND=6 (merged liquid, merge=1e-7) with large flat
      // interior (inward >= 23), non-zero bevel/refraction/chroma/rim: must be byte-for-byte identical; and zero-copy
      // slot swap across frames + glass_free() must preserve identical pixels without aliasing/double-free.
      dispatch_group_wait(kinds_made, DISPATCH_TIME_FOREVER);
      CHECK(kpipe[5] != nil && kpipe[6] != nil && kpipe[MB_KIND_LIQUID_SINGLE] != nil);
      double lp[3 * MB_INST];
      rect_at(lp, 0, 0, 400, 300, 0, 0.12, 0.24, 0.48, 0);
      rect_at(lp + MB_INST, 120, 90, 160, 120, 0, 0.92, 0.35, 0.18, 0);
      rect_at(lp + 2 * MB_INST, 80, 60, 240, 180, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -18);
      lp[2 * MB_INST + 4] = 28;
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
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lp, 3, 0.12, 0.24, 0.48);
      present_drain();
      uint8_t *px_single = read_texture(canvas, &aw, &ah);

      lp[2 * MB_INST + 23] = 1e-7;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lp, 3, 0.12, 0.24, 0.48);
      present_drain();
      uint8_t *px_merged = read_texture(canvas, &aw, &ah);
      CHECK(memcmp(px_single, px_merged, (size_t)aw * (size_t)ah * 4) == 0);
      free(px_merged);

      // Zero-copy slot swap across moving backdrop frames + glass_free() + re-render parity.
      lp[2 * MB_INST + 23] = 0.0;
      for (int step = 1; step <= 4; step++) {
        lp[MB_INST + 0] = 120 + step * 5;
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(lp, 3, 0.12, 0.24, 0.48);
        present_drain();
      }
      dispatch_sync(present_q, ^{ glass_free(); });
      lp[MB_INST + 0] = 120;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lp, 3, 0.12, 0.24, 0.48);
      present_drain();
      uint8_t *px_after_free = read_texture(canvas, &aw, &ah);
      CHECK(memcmp(px_single, px_after_free, (size_t)aw * (size_t)ah * 4) == 0);
      free(px_single);
      free(px_after_free);

      // Wave 7: adaptive liquid glass (slot 14 = -1.0) + adaptive kind 10 neutral/chromatic ink:
      // 0: light glass over white (bg=1.0) -> light glass + dark ink
      // 1: light glass over black (bg=0.0) -> dark glass + light ink
      // 2: light glass over mid-tone (bg=0.50) -> stays light glass + dark ink
      // 3: dark glass (0x20202067) over white (bg=1.0) -> stays dark smoked glass + light ink (never flips white)
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
        rect_at(ad, 0, 0, 400, 300, 0, bg, bg, bg, 0);
        rect_at(ad + MB_INST, 100, 80, 200, 140, 6,
                dg ? 32.0 / 255.0 : 253.0 / 255.0,
                dg ? 32.0 / 255.0 : 252.0 / 255.0,
                dg ? 32.0 / 255.0 : 253.0 / 255.0, -19);
        ad[MB_INST + 4] = 28;
        ad[MB_INST + 6] = 1.0;
        ad[MB_INST + 7] = 2.0;
        ad[MB_INST + 11] = 0x67 / 255.0;
        ad[MB_INST + 12] = 0.0;
        ad[MB_INST + 13] = 14.0;
        ad[MB_INST + 14] = -1.0;  // adaptive=true, no spot
        ad[MB_INST + 15] = 1.0;
        ad[MB_INST + 21] = 0.0;
        ad[MB_INST + 22] = 0.0;
        ad[MB_INST + 23] = 0.0;
        // Neutral line inside glass at y=120 (x=140..180)
        rect_at(ad + 2 * MB_INST, 130, 110, 60, 20, 10, ink, ink, ink, 0);
        ad[2 * MB_INST + 4] = 4.0;
        ad[2 * MB_INST + 12] = 0.1;
        ad[2 * MB_INST + 13] = 0.5;
        ad[2 * MB_INST + 14] = 0.9;
        ad[2 * MB_INST + 15] = 0.5;
        ad[2 * MB_INST + 21] = 200.0;
        ad[2 * MB_INST + 22] = 150.0;
        ad[2 * MB_INST + 23] = 70.0;
        // Chromatic accent line inside glass at y=180 (x=140..180): must preserve color on dark backdrop
        rect_at(ad + 3 * MB_INST, 130, 170, 60, 20, 10, 0.90, 0.30, 0.15, 0);
        ad[3 * MB_INST + 4] = 4.0;
        ad[3 * MB_INST + 12] = 0.1;
        ad[3 * MB_INST + 13] = 0.5;
        ad[3 * MB_INST + 14] = 0.9;
        ad[3 * MB_INST + 15] = 0.5;
        ad[3 * MB_INST + 21] = 200.0;
        ad[3 * MB_INST + 22] = 150.0;
        ad[3 * MB_INST + 23] = 70.0;
        glass_forget();
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(ad, 4, bg, bg, bg);
        present_drain();
        uint8_t *px_ad = read_texture(canvas, &aw, &ah);
        // Glass interior at (240, 150) -> (480, 300) at 2x (BGRA)
        uint8_t *gp = px_ad + (300 * aw + 480) * 4;
        double g_lum = (0.2126 * gp[2] + 0.7152 * gp[1] + 0.0722 * gp[0]) / 255.0;
        // Neutral line center at (160, 120) -> (320, 240)
        uint8_t *np = px_ad + (240 * aw + 320) * 4;
        double n_lum = (0.2126 * np[2] + 0.7152 * np[1] + 0.0722 * np[0]) / 255.0;
        // Chromatic line center at (160, 180) -> (320, 360)
        uint8_t *cp = px_ad + (360 * aw + 320) * 4;
        printf("apple_render: wave7 case=%d bg=%.2f dg=%d glass=%.3f neutral_ink=%.3f chroma_rgb=%d,%d,%d\n",
               ci, bg, dg, g_lum, n_lum, cp[2], cp[1], cp[0]);
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
        CHECK((int)cp[2] > (int)cp[0] + 120);
        free(px_ad);
      }

      // Smooth fogging on adaptive flip: thin bright stripe over black is softened by dual-ring fog blur + higher darkDens
      double fg[3 * MB_INST];
      double fog_peaks[2] = {0.0, 0.0};
      for (int adaptive_on = 0; adaptive_on <= 1; adaptive_on++) {
        rect_at(fg, 0, 0, 400, 300, 0, 0.0, 0.0, 0.0, 0);
        // Place the thin 2pt white stripe at y=165 (off the 5-point luma sample cross at y=150 and y=150+/-35)
        rect_at(fg + MB_INST, 80, 164, 240, 2, 0, 1.0, 1.0, 1.0, 0);
        rect_at(fg + 2 * MB_INST, 100, 80, 200, 140, 6, 32.0 / 255.0, 32.0 / 255.0, 32.0 / 255.0, -20);
        fg[2 * MB_INST + 4] = 28;
        fg[2 * MB_INST + 6] = 1.0;
        fg[2 * MB_INST + 7] = 1.0;
        fg[2 * MB_INST + 11] = 0x67 / 255.0;
        fg[2 * MB_INST + 12] = 0.0;
        fg[2 * MB_INST + 13] = 14.0;
        fg[2 * MB_INST + 14] = adaptive_on ? -1.0 : 0.0;
        fg[2 * MB_INST + 15] = 1.0;
        fg[2 * MB_INST + 21] = 0.0;
        fg[2 * MB_INST + 22] = 0.0;
        fg[2 * MB_INST + 23] = 0.0;
        // Over black, light tint with adaptive_on triggers fogT=1.0; compare against non-adaptive dark tint
        if (adaptive_on) {
          fg[2 * MB_INST + 8] = 253.0 / 255.0;
          fg[2 * MB_INST + 9] = 252.0 / 255.0;
          fg[2 * MB_INST + 10] = 253.0 / 255.0;
        }
        glass_forget();
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(fg, 3, 0.0, 0.0, 0.0);
        present_drain();
        uint8_t *px_fg = read_texture(canvas, &aw, &ah);
        uint8_t *sp = px_fg + (330 * aw + 400) * 4;  // (200, 165) on the bright 2pt stripe
        fog_peaks[adaptive_on] = (0.2126 * sp[2] + 0.7152 * sp[1] + 0.0722 * sp[0]) / 255.0;
        free(px_fg);
      }
      printf("apple_render: wave7 fog stripe peak plain_dark=%.3f adaptive_fog=%.3f\n",
             fog_peaks[0], fog_peaks[1]);
      CHECK(fog_peaks[1] < fog_peaks[0] - 0.15);

      // Test A: wide 320x36pt adaptive capsule over deep navy #173255 with centered 60x24pt pure white "{less}" block
      // must resist ping-pong flipping (trimmed mean stays dark -> dark glass + white ink).
      double ta[4 * MB_INST];
      rect_at(ta, 0, 0, 400, 300, 0, 23.0 / 255.0, 50.0 / 255.0, 85.0 / 255.0, 0);
      rect_at(ta + MB_INST, 170, 138, 60, 24, 0, 1.0, 1.0, 1.0, 0);
      rect_at(ta + 2 * MB_INST, 40, 132, 320, 36, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -21);
      ta[2 * MB_INST + 4] = 18.0;
      ta[2 * MB_INST + 6] = 1.0;
      ta[2 * MB_INST + 7] = 2.0;
      ta[2 * MB_INST + 11] = 0x67 / 255.0;
      ta[2 * MB_INST + 12] = 0.0;
      ta[2 * MB_INST + 13] = 14.0;
      ta[2 * MB_INST + 14] = -1.0;
      ta[2 * MB_INST + 15] = 1.0;
      ta[2 * MB_INST + 21] = 0.0;
      ta[2 * MB_INST + 22] = 0.0;
      ta[2 * MB_INST + 23] = 0.0;
      rect_at(ta + 3 * MB_INST, 70, 140, 60, 20, 10, 0.11, 0.11, 0.11, 0);
      ta[3 * MB_INST + 4] = 4.0;
      ta[3 * MB_INST + 12] = 0.1;
      ta[3 * MB_INST + 13] = 0.5;
      ta[3 * MB_INST + 14] = 0.9;
      ta[3 * MB_INST + 15] = 0.5;
      ta[3 * MB_INST + 21] = 200.0;
      ta[3 * MB_INST + 22] = 150.0;
      ta[3 * MB_INST + 23] = 36.0;
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(ta, 4, 23.0 / 255.0, 50.0 / 255.0, 85.0 / 255.0);
      present_drain();
      uint8_t *px_ta = read_texture(canvas, &aw, &ah);
      uint8_t *ta_gp = px_ta + (300 * aw + 560) * 4;  // (280, 150) glass over navy
      uint8_t *ta_np = px_ta + (300 * aw + 200) * 4;  // (100, 150) neutral ink inside capsule
      double ta_g = (0.2126 * ta_gp[2] + 0.7152 * ta_gp[1] + 0.0722 * ta_gp[0]) / 255.0;
      double ta_n = (0.2126 * ta_np[2] + 0.7152 * ta_np[1] + 0.0722 * ta_np[0]) / 255.0;
      printf("apple_render: wave7 testA wide_less glass=%.3f ink=%.3f\n", ta_g, ta_n);
      CHECK(ta_g < 0.28);
      CHECK(ta_n > 0.80);
      free(px_ta);

      // Test B: cross-frame temporal smoothing + synchronized glass/ink + Schmitt hysteresis + auto-settle stop
      mb_render_set_fixed_dt(1.0 / 60.0);
      double tb[3 * MB_INST];
      rect_at(tb, 0, 0, 400, 300, 0, 1.0, 1.0, 1.0, 0);
      rect_at(tb + MB_INST, 40, 132, 320, 36, 6, 253.0 / 255.0, 252.0 / 255.0, 253.0 / 255.0, -22);
      tb[MB_INST + 4] = 18.0;
      tb[MB_INST + 6] = 1.0;
      tb[MB_INST + 7] = 2.0;
      tb[MB_INST + 11] = 0x67 / 255.0;
      tb[MB_INST + 12] = 0.0;
      tb[MB_INST + 13] = 14.0;
      tb[MB_INST + 14] = -1.0;
      tb[MB_INST + 15] = 1.0;
      tb[MB_INST + 21] = 0.0;
      tb[MB_INST + 22] = 0.0;
      tb[MB_INST + 23] = 0.0;
      rect_at(tb + 2 * MB_INST, 70, 140, 60, 20, 10, 0.11, 0.11, 0.11, 0);
      tb[2 * MB_INST + 4] = 4.0;
      tb[2 * MB_INST + 12] = 0.1;
      tb[2 * MB_INST + 13] = 0.5;
      tb[2 * MB_INST + 14] = 0.9;
      tb[2 * MB_INST + 15] = 0.5;
      tb[2 * MB_INST + 21] = 200.0;
      tb[2 * MB_INST + 22] = 150.0;
      tb[2 * MB_INST + 23] = 36.0;

      // Frame 0: pure white -> instant light state
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(tb, 3, 1.0, 1.0, 1.0);
      present_drain();
      uint8_t *px_tb = read_texture(canvas, &aw, &ah);
      double f0_g = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
      double f0_n = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
      free(px_tb);
      printf("apple_render: wave7 testB f0_white glass=%.3f ink=%.3f\n", f0_g, f0_n);
      CHECK(f0_g > 0.75);
      CHECK(f0_n < 0.25);

      // Frame 1: switch to deep navy #173255 -> intermediate state (no 1-frame hard jump)
      tb[8] = 23.0 / 255.0; tb[9] = 50.0 / 255.0; tb[10] = 85.0 / 255.0;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(tb, 3, tb[8], tb[9], tb[10]);
      present_drain();
      px_tb = read_texture(canvas, &aw, &ah);
      double f1_g = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
      double f1_n = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
      free(px_tb);
      printf("apple_render: wave7 testB f1_navy glass=%.3f ink=%.3f settling=%d\n", f1_g, f1_n, mb_render_adaptive_settling());
      CHECK(f1_g > 0.28 && f1_g < 0.72);
      CHECK(f1_n > 0.15 && f1_n < 0.75);
      CHECK(mb_render_adaptive_settling() == 1);

      // Step 25 more frames (~420ms): monotonic convergence to dark state
      double prev_g = f1_g, prev_n = f1_n;
      for (int s = 0; s < 25; s++) {
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(tb, 3, tb[8], tb[9], tb[10]);
        present_drain();
        px_tb = read_texture(canvas, &aw, &ah);
        double cg = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
        double cn = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
        free(px_tb);
        CHECK(cg <= prev_g + 0.015);
        CHECK(cn >= prev_n - 0.015);
        prev_g = cg;
        prev_n = cn;
      }
      printf("apple_render: wave7 testB f26_dark glass=%.3f ink=%.3f settling=%d\n", prev_g, prev_n, mb_render_adaptive_settling());
      CHECK(prev_g < 0.28);
      CHECK(prev_n > 0.85);

      // Schmitt hysteresis: bg=0.40 (in [0.36, 0.46]) for 25 frames stays dark
      tb[8] = 0.40; tb[9] = 0.40; tb[10] = 0.40;
      for (int s = 0; s < 25; s++) {
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(tb, 3, 0.40, 0.40, 0.40);
        present_drain();
      }
      px_tb = read_texture(canvas, &aw, &ah);
      double hyst_g = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
      double hyst_n = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
      free(px_tb);
      printf("apple_render: wave7 testB hyst_0.40 glass=%.3f ink=%.3f\n", hyst_g, hyst_n);
      CHECK(hyst_g < 0.40);
      CHECK(hyst_n > 0.80);

      // Return to bright bg=0.95: frame 1 intermediate, +26 frames settles back to light and stops settling
      tb[8] = 0.95; tb[9] = 0.95; tb[10] = 0.95;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(tb, 3, 0.95, 0.95, 0.95);
      present_drain();
      px_tb = read_texture(canvas, &aw, &ah);
      double r1_g = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
      double r1_n = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
      free(px_tb);
      printf("apple_render: wave7 testB return_f1 glass=%.3f ink=%.3f\n", r1_g, r1_n);
      CHECK(r1_g > 0.30 && r1_g < 0.82);
      CHECK(r1_n > 0.20 && r1_n < 0.88);
      for (int s = 0; s < 26; s++) {
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(tb, 3, 0.95, 0.95, 0.95);
        present_drain();
      }
      px_tb = read_texture(canvas, &aw, &ah);
      double r_end_g = (0.2126 * px_tb[(300 * aw + 560) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 560) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 560) * 4 + 0]) / 255.0;
      double r_end_n = (0.2126 * px_tb[(300 * aw + 200) * 4 + 2] + 0.7152 * px_tb[(300 * aw + 200) * 4 + 1] + 0.0722 * px_tb[(300 * aw + 200) * 4 + 0]) / 255.0;
      free(px_tb);
      printf("apple_render: wave7 testB return_end glass=%.3f ink=%.3f settling=%d\n", r_end_g, r_end_n, mb_render_adaptive_settling());
      CHECK(r_end_g > 0.75);
      CHECK(r_end_n < 0.25);
      CHECK(mb_render_adaptive_settling() == 0);
      // Caret / instance drawn ABOVE the glass changing must NOT re-trigger adaptive settling.
      double tb4[4 * MB_INST];
      memcpy(tb4, tb, 3 * MB_INST * sizeof(double));
      rect_at(tb4 + 3 * MB_INST, 10, 10, 2, 16, 0, 0.1, 0.1, 0.1, 0);
      mb_host_render_dirty(0, 0, 40, 40);
      mb_render_present(tb4, 4, 0.95, 0.95, 0.95);
      present_drain();
      CHECK(mb_render_adaptive_settling() == 0);
      tb4[3 * MB_INST + 0] = 20;
      mb_host_render_dirty(0, 0, 40, 40);
      mb_render_present(tb4, 4, 0.95, 0.95, 0.95);
      present_drain();
      CHECK(mb_render_adaptive_settling() == 0);
      // Kind 7 (adaptive glyph) has its own specialized pipeline.
      CHECK(has_own_pipe(7) == 1);
      // Same-side backdrop change (0.95 -> 0.93, both light) converges early via async readback instead of spinning
      // for the full 420ms settle window.
      tb[8] = 0.93; tb[9] = 0.93; tb[10] = 0.93;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(tb, 3, 0.93, 0.93, 0.93);
      present_drain();
      for (int s = 0; s < 4 && mb_render_adaptive_settling(); s++) {
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(tb, 3, 0.93, 0.93, 0.93);
        present_drain();
      }
      CHECK(mb_render_adaptive_settling() == 0);
      mb_render_set_fixed_dt(0.0);
      glass_forget();
    }

    // A selection changes shape data while two adaptive glasses share a capture. Settle regions must contain the
    // complete capture so they never blur the preceding frame's glass or foreground.
    {
      double a[6 * MB_INST];
      rect_at(a, 0, 0, 400, 300, 0, 0.95, 0.95, 0.95, 0);
      rect_at(a + MB_INST, 56, 216, 160, 12, 0, 0.1, 0.1, 0.1, 0);
      rect_at(a + 2 * MB_INST, 40, 116, 140, 32, 6, 0.99, 0.99, 0.99, -1);
      rect_at(a + 3 * MB_INST, 32, 180, 336, 92, 6, 0.99, 0.99, 0.99, -1);
      for (int i = 2; i <= 3; i++) {
        a[i * MB_INST + 4] = 16.0;
        a[i * MB_INST + 6] = 1.0;
        a[i * MB_INST + 7] = 4.0;
        a[i * MB_INST + 11] = 0x67 / 255.0;
        a[i * MB_INST + 13] = 8.0;
        a[i * MB_INST + 14] = -1.0;
        a[i * MB_INST + 15] = 1.0;
        a[i * MB_INST + 21] = 6.0;
      }
      rect_at(a + 4 * MB_INST, 40, 8, 120, 12, 0, 0.4, 0.6, 1.0, 0);
      a[4 * MB_INST + 11] = 0.0;
      rect_at(a + 5 * MB_INST, 0, 0, 0, 0, 12, 0, 0, 0, 0);
      mb_render_set_fixed_dt(1.0 / 60.0);
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(a, 6, 0.95, 0.95, 0.95);
      present_drain();
      a[8] = 0.93;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(a, 6, 0.95, 0.95, 0.95);
      present_drain();
      CHECK(mb_render_adaptive_settling());
      a[4 * MB_INST + 11] = 0.5;
      a[5 * MB_INST + 12] = 1.0;
      mb_host_render_dirty(32, 0, 144, 32);
      mb_render_present(a, 6, 0.95, 0.95, 0.95);
      present_drain();
      slots_invalidate();
      CHECK(canvas_as_whole());
      mb_render_set_fixed_dt(0.0);
      glass_forget();
    }

    // Two independent adaptive liquid glasses spaced 8pt apart so their captures overlap, with a high-contrast blue
    // foreground caret drawn after the lower glass. Three consecutive partial frames updating only the top non-glass
    // region while settling must stay pixel-identical to a whole redraw, and overlapping settle damage merges to one.
    {
      double a[7 * MB_INST];
      rect_at(a, 0, 0, 400, 300, 0, 0.95, 0.95, 0.95, 0);
      rect_at(a + MB_INST, 56, 216, 160, 12, 0, 0.1, 0.1, 0.1, 0);
      rect_at(a + 2 * MB_INST, 40, 128, 140, 32, 6, 0.99, 0.99, 0.99, -1);
      a[2 * MB_INST + 4] = 16.0;
      a[2 * MB_INST + 6] = 1.0;
      a[2 * MB_INST + 7] = 2.1;
      a[2 * MB_INST + 11] = 0x67 / 255.0;
      a[2 * MB_INST + 13] = 8.0;
      a[2 * MB_INST + 14] = -1.0;
      a[2 * MB_INST + 15] = 1.0;
      a[2 * MB_INST + 21] = 28.0;
      rect_at(a + 3 * MB_INST, 32, 168, 336, 92, 6, 0.99, 0.99, 0.99, -2);
      a[3 * MB_INST + 4] = 16.0;
      a[3 * MB_INST + 6] = 1.0;
      a[3 * MB_INST + 7] = 4.0;
      a[3 * MB_INST + 11] = 0x67 / 255.0;
      a[3 * MB_INST + 13] = 8.0;
      a[3 * MB_INST + 14] = -1.0;
      a[3 * MB_INST + 15] = 1.0;
      a[3 * MB_INST + 21] = 28.0;
      rect_at(a + 4 * MB_INST, 48, 196, 2, 24, 0, 0.05, 0.35, 1.0, 0);
      rect_at(a + 5 * MB_INST, 40, 8, 120, 12, 0, 0.4, 0.6, 1.0, 0);
      a[5 * MB_INST + 11] = 0.0;
      rect_at(a + 6 * MB_INST, 0, 0, 0, 0, 12, 0, 0, 0, 0);
      mb_render_set_fixed_dt(1.0 / 60.0);
      glass_forget();
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(a, 7, 0.95, 0.95, 0.95);
      present_drain();
      a[8] = 0.93;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(a, 7, 0.95, 0.95, 0.95);
      present_drain();
      CHECK(mb_render_adaptive_settling());
      for (int step = 0; step < 3; step++) {
        a[5 * MB_INST + 11] = 0.3 * (step + 1);
        a[6 * MB_INST + 12] = (double)(step + 1);
        mb_host_render_dirty(32, 0, 144, 32);
        mb_render_present(a, 7, 0.95, 0.95, 0.95);
        present_drain();
        slots_invalidate();
        CHECK(canvas_as_whole());
      }
      float f[7 * MB_INST];
      for (int i = 0; i < 7 * MB_INST; i++) f[i] = (float)a[i];
      double r[][4] = {{36, 124, 148, 40}, {28, 164, 344, 100}};
      int rn = 2;
      CHECK(mb_glass_damage_expand(f, 7, r, &rn, 400, 300, 2));
      CHECK(rn == 1);
      CHECK(r[0][1] <= 92 && r[0][1] + r[0][3] >= 298);
      mb_render_set_fixed_dt(0.0);
      glass_forget();
      // Wave 4B v17: foreground optical lens (kind == 8): offscreen Gaussian defocus + spherical bevel refraction + SDF clip
      double k8[3 * MB_INST];
      rect_at(k8, 0, 0, 400, 300, 0, 1.0, 1.0, 1.0, 0);
      rect_at(k8 + MB_INST, 100, 80, 120, 120, 8, 1.0, 1.0, 1.0, 0);
      k8[MB_INST + 4] = 28;
      k8[MB_INST + 7] = 4.0;   // blur = 4pt
      k8[MB_INST + 11] = 1.0;  // alpha = 1
      k8[MB_INST + 12] = 1.0;  // child_n = 1
      k8[MB_INST + 13] = 24.0; // bezel = 24pt
      k8[MB_INST + 14] = 18.0; // refraction = 18pt
      k8[MB_INST + 15] = 1.0;
      k8[MB_INST + 36] = 28; k8[MB_INST + 37] = 28; k8[MB_INST + 38] = 28; k8[MB_INST + 39] = 28;
      rect_at(k8 + 2 * MB_INST, 140, 120, 40, 40, 0, 1.0, 0.0, 0.0, 0);
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(k8, 3, 1.0, 1.0, 1.0);
      present_drain();
      int k8w = 0, k8h = 0;
      uint8_t *px_k8 = read_texture(canvas, &k8w, &k8h);
      // BGRA at 2x: center (160,140)->(320,280), blur halo (136,140)->(272,280), outside SDF (80,140)->(160,280)
      uint8_t *k8_ctr = px_k8 + (280 * k8w + 320) * 4;
      uint8_t *k8_halo = px_k8 + (280 * k8w + 272) * 4;
      uint8_t *k8_out = px_k8 + (280 * k8w + 160) * 4;
      printf("apple_render: kind8 lens ctr=%d,%d,%d halo=%d,%d,%d out=%d,%d,%d\n",
             k8_ctr[2], k8_ctr[1], k8_ctr[0], k8_halo[2], k8_halo[1], k8_halo[0], k8_out[2], k8_out[1], k8_out[0]);
      CHECK((int)k8_ctr[2] - (int)k8_ctr[0] > 120);
      CHECK((int)k8_halo[2] - (int)k8_halo[0] > 20);
      CHECK(abs((int)k8_out[2] - (int)k8_out[0]) <= 2 && k8_out[2] >= 250);
      free(px_k8);
    }

    // 5K progressive blur + mixed aspect-ratio 40-frame scroll stress:
    // A wide top progressive bar + tall sidebar stretch lv_w/lv_h to near-5K, then 40 frames of moving backdrop
    // under small progressive + regular frosted glass must stay within MB_GLASS_CACHE_MAX_BYTES (64 MiB), keep
    // compact slot textures far smaller than lv_w * lv_h, and match canvas_as_whole() byte-for-byte on every frame.
    {
      glass_free();
      mb_render_set_size(2560, 1440, 2);
      double big[3 * MB_INST];
      rect_at(big, 0, 0, 2560, 1440, 0, 0.12, 0.16, 0.22, 0);
      big[18] = 2560; big[19] = 1440;
      // Wide top bar progressive frosted glass
      rect_at(big + MB_INST, 0, 0, 2500, 60, 5, 1, 1, 1, -30);
      big[MB_INST + 7] = 12.0;
      big[MB_INST + 11] = 0.4;
      big[MB_INST + 18] = 2560; big[MB_INST + 19] = 1440;
      big[MB_INST + 22] = -1.0;  // progressive
      big[MB_INST + 55] = 60.0;
      big[MB_INST + 56] = 1.0;
      // Tall sidebar frosted glass
      rect_at(big + 2 * MB_INST, 0, 80, 120, 1340, 5, 1, 1, 1, -31);
      big[2 * MB_INST + 7] = 12.0;
      big[2 * MB_INST + 11] = 0.4;
      big[2 * MB_INST + 18] = 2560; big[2 * MB_INST + 19] = 1440;
      mb_host_render_dirty(0, 0, 2560, 1440);
      mb_render_present(big, 3, 0.12, 0.16, 0.22);
      present_drain();
      CHECK(lv_w >= 4800 && lv_h >= 2600);
      CHECK(slots_total_bytes() <= MB_GLASS_CACHE_MAX_BYTES);
      CHECK(canvas_as_whole());

      double small[4 * MB_INST];
      rect_at(small, 0, 0, 2560, 1440, 0, 0.14, 0.18, 0.24, 0);
      small[18] = 2560; small[19] = 1440;
      // Moving backdrop stripe under both small glasses
      rect_at(small + MB_INST, 20, 30, 420, 60, 0, 0.90, 0.35, 0.20, 0);
      small[MB_INST + 18] = 2560; small[MB_INST + 19] = 1440;
      // Small progressive glass capsule
      rect_at(small + 2 * MB_INST, 40, 40, 160, 44, 5, 1, 1, 1, -32);
      small[2 * MB_INST + 7] = 12.0;
      small[2 * MB_INST + 11] = 0.45;
      small[2 * MB_INST + 18] = 2560; small[2 * MB_INST + 19] = 1440;
      small[2 * MB_INST + 22] = -1.0;  // progressive
      small[2 * MB_INST + 55] = 44.0;
      small[2 * MB_INST + 56] = 1.0;
      // Small regular frosted pill
      rect_at(small + 3 * MB_INST, 300, 40, 120, 40, 5, 1, 1, 1, -33);
      small[3 * MB_INST + 7] = 3.0;
      small[3 * MB_INST + 11] = 0.45;
      small[3 * MB_INST + 18] = 2560; small[3 * MB_INST + 19] = 1440;

      size_t peak_slot_bytes = slots_total_bytes();
      size_t max_small_tex_area = 0;
      for (int step = 0; step < 40; step++) {
        small[MB_INST + 0] = 20 + (step * 7) % 120;
        mb_host_render_dirty(0, 0, 2560, 1440);
        mb_render_present(small, 4, 0.14, 0.18, 0.24);
        present_drain();
        size_t cur_bytes = slots_total_bytes();
        if (cur_bytes > peak_slot_bytes) peak_slot_bytes = cur_bytes;
        CHECK(cur_bytes <= MB_GLASS_CACHE_MAX_BYTES);
        for (int j = 0; j < MB_GLASS_SLOTS; j++) {
          if (slots[j].valid && slot_bt[j] && slots[j].grab.w < 1000) {
            size_t area = (size_t)slot_bt[j].width * (size_t)slot_bt[j].height;
            if (area > max_small_tex_area) max_small_tex_area = area;
          }
        }
        CHECK(canvas_as_whole());
      }
      printf("apple_render: 5K glass stress peak_slot_bytes=%zu (limit=%zu) max_small_area=%zu lv_area=%zu\n",
             peak_slot_bytes, (size_t)MB_GLASS_CACHE_MAX_BYTES, max_small_tex_area, (size_t)lv_w * (size_t)lv_h);
      CHECK(peak_slot_bytes <= MB_GLASS_CACHE_MAX_BYTES);
      CHECK(max_small_tex_area > 0 && max_small_tex_area * 16 < (size_t)lv_w * (size_t)lv_h);
      glass_free();
      mb_render_set_size(400, 300, 2);
    }

    // High-water mark shrink: after a large glass stretches lv_w * lv_h, MB_GLASS_IDLE consecutive frames with only
    // small glass must shrink lv_w * lv_h back down and preserve byte-for-byte parity with canvas_as_whole().
    {
      glass_free();
      mb_render_set_size(400, 300, 2);
      double lg[2 * MB_INST];
      rect_at(lg, 0, 0, 400, 300, 0, 0.15, 0.25, 0.40, 0);
      rect_at(lg + MB_INST, 0, 0, 400, 300, 5, 1, 1, 1, -40);
      lg[MB_INST + 7] = 8.0;
      lg[MB_INST + 11] = 0.45;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(lg, 2, 0.15, 0.25, 0.40);
      present_drain();
      size_t big_lv_area = (size_t)lv_w * (size_t)lv_h;
      CHECK(lv_w == 800 && lv_h == 600);
      CHECK(canvas_as_whole());

      double sm[3 * MB_INST];
      rect_at(sm, 0, 0, 400, 300, 0, 0.15, 0.25, 0.40, 0);
      rect_at(sm + MB_INST, 24, 24, 52, 32, 0, 0.90, 0.20, 0.20, 0);
      rect_at(sm + 2 * MB_INST, 20, 20, 60, 40, 5, 1, 1, 1, -41);
      sm[2 * MB_INST + 7] = 4.0;
      sm[2 * MB_INST + 11] = 0.45;
      for (int i = 0; i < MB_GLASS_IDLE; i++) {
        sm[MB_INST + 0] = 24 + (i % 20);
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(sm, 3, 0.15, 0.25, 0.40);
        present_drain();
      }
      size_t shrunk_lv_area = (size_t)lv_w * (size_t)lv_h;
      printf("apple_render: lv shrink big_area=%zu -> shrunk_area=%zu (%dx%d)\n",
             big_lv_area, shrunk_lv_area, lv_w, lv_h);
      CHECK(shrunk_lv_area * 4 < big_lv_area);
      CHECK(canvas_as_whole());
      glass_forget();
      CHECK(canvas_as_whole());
      glass_free();
    }

    // Perf-29: Stacked glass cache independence (top progressive blur + top liquid glass capsule + changing bottom
    // content must produce 0 blur rebuilds and match a whole redraw to the byte; changing content under top
    // progressive blur rebuilds both and matches a whole redraw).
    {
      double sg[5 * MB_INST];
      rect_at(sg, 0, 0, 400, 300, 0, 0.94, 0.94, 0.92, 0);
      rect_at(sg + 1 * MB_INST, 20, 8, 120, 24, 0, 0.85, 0.20, 0.20, 0);
      rect_at(sg + 2 * MB_INST, 20, 220, 200, 32, 0, 0.20, 0.45, 0.90, 0);
      rect_at(sg + 3 * MB_INST, 0, 0, 400, 64, 5, 0.96, 0.96, 0.96, -30);
      sg[3 * MB_INST + 6] = 1.1;
      sg[3 * MB_INST + 7] = 6.0;
      sg[3 * MB_INST + 11] = 0.35;
      sg[3 * MB_INST + 15] = 1.0;
      sg[3 * MB_INST + 22] = -1.0;
      sg[3 * MB_INST + 54] = 64.0;
      sg[3 * MB_INST + 55] = 24.0;
      rect_at(sg + 4 * MB_INST, 24, 12, 140, 32, 6, 0.99, 0.99, 0.99, -31);
      sg[4 * MB_INST + 4] = 16.0;
      sg[4 * MB_INST + 6] = 1.0;
      sg[4 * MB_INST + 7] = 2.0;
      sg[4 * MB_INST + 11] = 0x67 / 255.0;
      sg[4 * MB_INST + 13] = 8.0;
      sg[4 * MB_INST + 14] = -1.0;
      sg[4 * MB_INST + 15] = 1.0;
      sg[4 * MB_INST + 21] = 6.0;

      mb_render_set_fixed_dt(1.0 / 60.0);
      glass_forget();
      int b0 = blurs_made;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(sg, 5, 0.94, 0.94, 0.92);
      present_drain();
      CHECK(blurs_made == b0 + 2);
      CHECK(canvas_as_whole());

      for (int step = 0; step < 3; step++) {
        sg[2 * MB_INST + 8] = 0.20 + 0.25 * (step + 1);
        b0 = blurs_made;
        mb_host_render_dirty(0, 0, 400, 300);
        mb_render_present(sg, 5, 0.94, 0.94, 0.92);
        present_drain();
        CHECK(blurs_made == b0);
        CHECK(canvas_as_whole());
      }

      sg[1 * MB_INST + 9] = 0.80;
      b0 = blurs_made;
      mb_host_render_dirty(0, 0, 400, 300);
      mb_render_present(sg, 5, 0.94, 0.94, 0.92);
      present_drain();
      CHECK(blurs_made == b0 + 2);
      CHECK(canvas_as_whole());
      mb_render_set_fixed_dt(0.0);
      glass_forget();
    }

    // Progressive blur small-radius anti-ghosting regression: 1pt and 1px dark vertical/horizontal strokes over
    // a light background under blur=8.5, fade_h=68 progressive blur at both 2x and 1x scale must produce strictly
    // unimodal profiles (no 9-tap comb ghosting / secondary dark peaks) and monotonically attenuate center contrast.
    {
      static const double scales[2] = {2.0, 1.0};
      static const double v_ramps[6] = {0.06, 0.10, 0.14, 0.18, 0.24, 0.35};
      static const double h_ramps[3] = {0.10, 0.18, 0.24};
      for (int si = 0; si < 2; si++) {
        double sc = scales[si];
        mb_render_set_size(400, 300, sc);
        double widths[2] = {1.0, 1.0 / sc};
        int n_widths = (sc > 1.5) ? 2 : 1;
        for (int wi = 0; wi < n_widths; wi++) {
          double lw = widths[wi];
          // 1) Vertical stroke across the entire fade band (y=0..80)
          double pb[3 * MB_INST];
          rect_at(pb, 0, 0, 400, 300, 0, 0.96, 0.96, 0.96, 0);
          rect_at(pb + MB_INST, 50.0, 0.0, lw, 80.0, 0, 0.05, 0.05, 0.05, 0);
          rect_at(pb + 2 * MB_INST, 0, 0, 400, 68.0, 5, 0.96, 0.96, 0.96, -40);
          pb[2 * MB_INST + 6] = 1.0;
          pb[2 * MB_INST + 7] = 8.5;
          pb[2 * MB_INST + 11] = 0.15;
          pb[2 * MB_INST + 15] = 1.0;
          pb[2 * MB_INST + 22] = -1.0;
          pb[2 * MB_INST + 54] = 68.0;
          pb[2 * MB_INST + 55] = 68.0;
          glass_forget();
          mb_host_render_dirty(0, 0, 400, 300);
          mb_render_present(pb, 3, 0.96, 0.96, 0.96);
          present_drain();
          int cw = 0, ch = 0;
          uint8_t *px = read_texture(canvas, &cw, &ch);
          int prev_center = -1;
          int first_center = -1;
          int last_center = -1;
          int mono_ok = 1;
          int max_dip = 0;
          for (int ri = 0; ri < 6; ri++) {
            int py = (int)llround(68.0 * (1.0 - v_ramps[ri]) * sc);
            if (py < 0) py = 0;
            if (py >= ch) py = ch - 1;
            int x0 = (int)floor(50.0 * sc) - 2;
            int x1 = (int)ceil((50.0 + lw) * sc) + 2;
            int xc = x0, min_l = 256;
            for (int x = x0; x <= x1; x++) {
              int l = px[(py * cw + x) * 4 + 1];
              if (l < min_l) { min_l = l; xc = x; }
            }
            if (ri == 0) first_center = min_l;
            last_center = min_l;
            if (prev_center >= 0 && min_l < prev_center - 2) {
              fprintf(stderr, "apple_render: prog-blur v-stroke center non-mono sc=%.0f lw=%.2f ramp=%.2f prev=%d cur=%d\n",
                      sc, lw, v_ramps[ri], prev_center, min_l);
              mono_ok = 0;
            }
            prev_center = min_l;
            for (int dir = -1; dir <= 1; dir += 2) {
              int max_seen = min_l;
              for (int dx = 1; dx <= 12; dx++) {
                int x = xc + dir * dx;
                if (x < 0 || x >= cw) break;
                int l = px[(py * cw + x) * 4 + 1];
                if (max_seen - l > max_dip) max_dip = max_seen - l;
                if (l < max_seen - 2) mono_ok = 0;
                if (l > max_seen) max_seen = l;
              }
            }
          }
          printf("apple_render: prog-blur v-stroke sc=%.0f lw=%.2f first=%d last=%d max_dip=%d\n",
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
            rect_at(hp, 0, 0, 400, 300, 0, 0.96, 0.96, 0.96, 0);
            rect_at(hp + MB_INST, 20.0, y_pt, 160.0, lw, 0, 0.05, 0.05, 0.05, 0);
            rect_at(hp + 2 * MB_INST, 0, 0, 400, 68.0, 5, 0.96, 0.96, 0.96, -41);
            hp[2 * MB_INST + 6] = 1.0;
            hp[2 * MB_INST + 7] = 8.5;
            hp[2 * MB_INST + 11] = 0.15;
            hp[2 * MB_INST + 15] = 1.0;
            hp[2 * MB_INST + 22] = -1.0;
            hp[2 * MB_INST + 54] = 68.0;
            hp[2 * MB_INST + 55] = 68.0;
            glass_forget();
            mb_host_render_dirty(0, 0, 400, 300);
            mb_render_present(hp, 3, 0.96, 0.96, 0.96);
            present_drain();
            int hcw = 0, hch = 0;
            uint8_t *hpx = read_texture(canvas, &hcw, &hch);
            int px_x = (int)llround(100.0 * sc);
            int y0 = (int)floor(y_pt * sc) - 2;
            int y1 = (int)ceil((y_pt + lw) * sc) + 2;
            int yc = y0, min_l = 256;
            for (int y = y0; y <= y1; y++) {
              int l = hpx[(y * hcw + px_x) * 4 + 1];
              if (l < min_l) { min_l = l; yc = y; }
            }
            for (int dir = -1; dir <= 1; dir += 2) {
              int max_seen = min_l;
              for (int dy = 1; dy <= 10; dy++) {
                int y = yc + dir * dy;
                if (y < 0 || y >= hch) break;
                int l = hpx[(y * hcw + px_x) * 4 + 1];
                if (max_seen - l > h_max_dip) h_max_dip = max_seen - l;
                if (l < max_seen - 2) h_mono_ok = 0;
                if (l > max_seen) max_seen = l;
              }
            }
            free(hpx);
          }
          printf("apple_render: prog-blur h-stroke sc=%.0f lw=%.2f max_dip=%d\n", sc, lw, h_max_dip);
          CHECK(h_mono_ok);
        }
      }
      mb_render_set_size(400, 300, 2);
      glass_forget();
    }

    // A group kept by the host (groups.h) drawn out by a header, straight into the floats: each instance moved in
    // doubles, then made a float, as the app's own instance moved there would be.
    double kept[MB_INST];
    memcpy(kept, inst, sizeof kept);
    kept[0] = 10.1;
    kept[1] = 20.3;
    double kept_moves[1] = {0};
    mb_host_group_set(5, kept, kept_moves, 1);
    double head[MB_INST] = {0};
    head[0] = 0.2;
    head[1] = -7.7;
    head[5] = MB_GROUP_HEAD;
    head[12] = 5;
    head[13] = 0;
    head[14] = 1;
    mb_render_present(head, 1, 0.1, 0.2, 0.3);
    CHECK(shown_ok == 1);
    CHECK(last_count == 1);
    CHECK(last_inst[0] == (float)(10.1 + 0.2));
    CHECK(last_inst[1] == (float)(20.3 + -7.7));
    CHECK(last_inst[2] == 100.0f);
    CHECK(last_inst[5] == 0.0f);
    // the same frame again is the one on the screen: nothing drawn
    float shown_first = last_inst[0];
    CHECK(same_as_shown(last_inst, 1, 0.1, 0.2, 0.3) == 1);
    mb_render_present(head, 1, 0.1, 0.2, 0.3);
    CHECK(last_inst[0] == shown_first);
    mb_host_group_drop(5);
    free(last_inst);
    last_cap = 0;

    // Restore synthetic state for trim checks.
    for (int i = 0; i < MB_INST; i++) f[i] = (float)inst[i];
    last_inst = f;
    last_count = 1;
    last_bg[0] = 0.1;
    last_bg[1] = 0.2;
    last_bg[2] = 0.3;
    shown_w = 400;
    shown_h = 300;
    shown_scale = 2;
    shown_ok = 1;
    canvas_ok = 1;

    // Trimming shrinks drawableSize to 1x1 and invalidates both canvas_ok and shown_ok; after mb_render_set_size
    // restores the full drawableSize, an identical frame must not be skipped by same_as_shown.
    mb_host_render_dirty(10, 20, 30, 40);
    mb_render_trim();
    CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(1, 1)));
    CHECK(shown_ok == 0);
    CHECK(canvas_ok == 0);
    CHECK(dirty_told == 0);

    mb_render_set_size(400, 300, 2);
    CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(800, 600)));
    CHECK(same_as_shown(f, 1, 0.1, 0.2, 0.3) == 0);

    // Even if shown_ok were set while drawableSize differed from the view's size, restoring drawableSize via
    // mb_render_set_size clears shown_ok so the new drawable size is presented.
    mlayer.drawableSize = CGSizeMake(1, 1);
    shown_ok = 1;
    mb_render_set_size(400, 300, 2);
    CHECK(CGSizeEqualToSize(mlayer.drawableSize, CGSizeMake(800, 600)));
    CHECK(shown_ok == 0);
    CHECK(same_as_shown(f, 1, 0.1, 0.2, 0.3) == 0);

    last_inst = NULL;
  }
  if (!failed) printf("apple_render: ok\n");
  return failed;
}
