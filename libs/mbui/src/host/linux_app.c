// Linux host: a GTK 4 window (Wayland or X11, as GTK finds the session) whose canvas is a GtkGLArea the app draws in
// with OpenGL ES 3 (linux_render.c), over the native views (linux_views.c: web pages, shown through it); frames from GTK's frame clock, asked for only while the app has something to
// draw; input from the area's events, and the input method (IBus, Fcitx: GTK's) through a GtkIMContext while a field
// has the focus. The window keeps the system's title bar (GTK's own on GNOME's Wayland, the window manager's where it
// draws them): none of its buttons in the app's top row. A program that is an app (MBUI_APP_ID) runs once for its
// person, put away to its icon among the desktop's as its window closes (linux_life.h).
#include <sys/resource.h>
#include <epoxy/gl.h>
#include <gtk/gtk.h>
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>
#include "linux.h"
#include "post.h"
#include "term.h"
#include "app_calls.h"  // the app's own calls
#include "done_watch.h"

mb_callbacks mb_cb;

// Back (host_native.mbt `set_back`): a mouse's back button and Alt+Left, while the app takes it.
typedef void (*mb_back_fn)(int32_t, double, double, int32_t);
static mb_back_fn back_cb;
static int back_on;
static int go_back(void) {
  if (!back_cb || !back_on) return 0;
  back_cb(2, 0, 1, 0);
  return 1;
}

static double wake_at = -1;  // mb_now_ms() of the earliest wake_after, or -1

// ---- the windows of one run (@hostapi.windows_in_process: mb_host_windows) ----
// Each window the app opens beside its first is a window of this run: its own GtkWindow, its canvas (drawn with the
// first canvas's GL context, into pictures of its own: canvas_snapshot), its native views' GtkFixed (linux_views.c: a
// view is the window's it is placed in), its input method, its events; drawn by the same program, the same context,
// atlases, pictures, streams and players. The window drawn or handing input now is put in place for it (win_use: `ws`,
// and the renderer's frame kept, linux_render.c mb_render_use) and the first put back after: what the app asks of the
// window then (its size, its scale, a frame, its input method, a drag) is that window's, and the app is told which it
// is (mb_host_windows' 4). Closed by the person, the app is told (an outside event, MB_OUTSIDE_WINDOW) and the run goes
// on; the first put away (hidden), the windows beside it stay, their context kept for the first's again (canvas_context).
typedef struct WinSlot {
  // the window, its canvas, the native views' GtkFixed under it (NULL win: no window of that number)
  GtkWidget *win, *area, *under;
  GtkIMContext *im;
  GtkEventController *keys;
  int want_frame;
  int ad_stepping;
  guint tick_id;
  double scale;
  int fb_pw, fb_ph;         // the area's framebuffer in pixels, as GTK last sized it
  double frame_w, frame_h;  // the last frame's size in points
  int ime_active;
  double caret[4];  // x, y, w, h in points, from set_ime
  char *ime_words;  // the field's words (UTF-8) and its selection's ends in them, for the input method
  int ime_sel_a, ime_sel_b;
  int marked_len;
  int right_down, left_down, middle_down;  // whether the right (left, middle) button is down
  // the last press, for a move of the window it starts (mb_host_window_drag), in the surface's coordinates
  GdkDevice *press_device;
  double press_x, press_y;
  guint32 press_time;
  int press_button;
  // the last valid pointer position in the surface's coordinates, as a fallback for events without coordinates
  double ptr_x, ptr_y;
  int ptr_valid;
  // the last press that moved the window: when and where, for the second of a double click there
  guint32 drag_time;
  double drag_x, drag_y;
  // what the app opened it as (mb_host_windows' 1, its spec; the first's, window_setup): its role (its size kept under
  // it as it closes), when it opened, its least size (points) and whether its top row is the app's (an inset window)
  char role[64];
  int opened;
  double min_w, min_h;
  int inset;
} WinSlot;
static WinSlot win_slots[MB_WINS] = {{.scale = 1}};
static WinSlot *ws = &win_slots[0];
static int win_active;  // the window in place (0, the first, between frames and input)
static int win_of_area(GtkWidget *a) {
  for (int k = 0; k < MB_WINS; k++)
    if (a && win_slots[k].area == a) return k;
  return -1;
}
// Window `wid` put in place: its slot and its frame's drawing.
static void win_use(int wid) {
  if (wid == win_active || wid < 0 || wid >= MB_WINS || (wid > 0 && !win_slots[wid].win)) return;
  win_active = wid;
  ws = &win_slots[wid];
  mb_render_use(wid);
}
// The window in place before put back (the first where it has closed meanwhile).
static void win_put_back(int wid) {
  if (wid > 0 && !win_slots[wid].win) wid = 0;
  win_use(wid);
}
// The window a handler is of (its data: the window's number) put in place, the one before given back to put back.
static int win_in(gpointer data) {
  int back = win_active;
  win_use(GPOINTER_TO_INT(data));
  return back;
}
static int context_asked, context_new;  // the canvas's context asked anew, and made so (mb_host_drive 10, 11)
static const char *script;
static const char *shot_dir;
// the window as the app asks for it (@hostapi.window_setup)
static double setup_w, setup_h, setup_min_w, setup_min_h;
static int frames_drawn;
static mb_outside_fn outside_cb;  // who is told as what the host does for the app is done (mb_host_set_outside)
static void (*state_cb)(int32_t);  // the app in front or not (@hostapi.set_app_state)
// an inset window (@hostapi.window_setup's inset): no title bar of the system's, the app's top row is it
static int setup_inset;

double mb_now_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

static moonbit_string_t mstr(const char *s) {
  glong n = 0;
  gunichar2 *u = s ? g_utf8_to_utf16(s, -1, NULL, &n, NULL) : NULL;
  moonbit_string_t out = moonbit_make_string_raw(u ? (int32_t)n : 0);
  if (u && n) memcpy(out, u, (size_t)n * 2);
  g_free(u);
  return out;
}

// MoonBit's words as UTF-8 (a lone surrogate as U+FFFD)
static char *utf8(moonbit_string_t s) {
  int32_t n = Moonbit_array_length(s);
  GString *o = g_string_sized_new((gsize)n * 3 + 1);
  for (int32_t i = 0; i < n; i++) {
    gunichar c = s[i];
    if (c >= 0xD800 && c < 0xDC00 && i + 1 < n && s[i + 1] >= 0xDC00 && s[i + 1] < 0xE000)
      c = 0x10000 + ((c - 0xD800) << 10) + (s[++i] - 0xDC00);
    else if (c >= 0xD800 && c < 0xE000)
      c = 0xFFFD;
    g_string_append_unichar(o, c);
  }
  return g_string_free(o, FALSE);
}

static void send_text(int kind, const char *s, int a, int b) { mb_cb.text(kind, mstr(s), a, b); }

static void run_script_step(int step);
double mb_host_mem_bytes(void);

// ---- frames: GTK's frame clock ticks while one is wanted, and each tick has the area drawn ----

static void canvas_queue_render(GtkWidget *w);

// (each window's frame clock its own: data, the window's number)
static gboolean on_tick(GtkWidget *w, GdkFrameClock *clock, gpointer data) {
  (void)w, (void)clock;
  WinSlot *o = &win_slots[GPOINTER_TO_INT(data)];
  if (o->want_frame) {
    canvas_queue_render(o->area);
    return G_SOURCE_CONTINUE;
  }
  o->tick_id = 0;
  return G_SOURCE_REMOVE;
}

// The window held out of sight as it opens (@hostapi.window_hold, said before mb_host_run): realized, not shown (its
// canvas's context made, nothing of it on the screen), its frames drawn meanwhile into the canvas's picture at the size
// it is to have (held_w × held_h points: held_frame, as each is asked), till the app shows it (mb_host_window_show): then it is presented
// as that frame ends, its first picture on the screen the app's page drawn (at its size as laid out: drawn again in the
// snapshot where that is another), not its ground for the page's first moments.
static int window_held, window_shown, window_to_show;
static int held_w, held_h;
static guint held_source;
static gboolean held_frame(gpointer data);
// (a frame asked of the first window while it is held: no frame clock ticks for a window not shown, so it is drawn as
// the loop is next idle, once however often it was asked; a held window is held for its first page's few moments)
static void held_tick(void) {
  if (!window_held || window_shown || held_source) return;
  held_source = g_idle_add(held_frame, NULL);
}

// A frame of the window in place asked for.
static void schedule(void) {
  ws->want_frame = 1;
  if (!ws->tick_id && ws->area)
    ws->tick_id = gtk_widget_add_tick_callback(ws->area, on_tick, GINT_TO_POINTER(win_active), NULL);
  if (win_active == 0) held_tick();
}

// A frame of every window of the run asked for (what changed may be any's: each draws only what changed of its own).
static void schedule_all(void) {
  int back = win_active;
  for (int k = 0; k < MB_WINS; k++)
    if (win_slots[k].win) {
      win_use(k);
      schedule();
    }
  win_put_back(back);
}

// asked for from any thread (an image decoded, a message posted): its frame on the main thread
static gint waking;
static gint posting;  // a told of what was posted asked of the main loop, not yet run (mb_post_wake)
static gboolean wake_idle(gpointer data) {
  (void)data;
  g_atomic_int_set(&waking, 0);
  schedule_all();
  return G_SOURCE_REMOVE;
}

void mb_app_wake(void) {
  if (g_atomic_int_compare_and_exchange(&waking, 0, 1)) g_idle_add_full(G_PRIORITY_HIGH_IDLE, wake_idle, NULL, NULL);
}

// A message posted from outside the frames (post.h), on whatever thread: the app told on the main loop, between frames
// (MB_OUTSIDE_POSTED, ui's messages_between), as the Mac's host tells it (mac_app.m): it takes what changes only
// signals then and asks for a frame only where something is left for one. Never taken as a frame begins: there the
// frame has read what it does again before what came is taken, and a change only the window's tree reads went unseen
// till something else built the frame whole (the web and Linux, 2026-11-11).
static gboolean posted_idle(gpointer data) {
  (void)data;
  g_atomic_int_set(&posting, 0);
  if (outside_cb) outside_cb(MB_OUTSIDE_POSTED, 0, 0);
  else mb_app_wake();
  return G_SOURCE_REMOVE;
}

static void mb_post_wake(void) {
  if (g_atomic_int_compare_and_exchange(&posting, 0, 1)) g_idle_add_full(G_PRIORITY_HIGH_IDLE, posted_idle, NULL, NULL);
}

double mb_app_scale(void) { return ws->scale; }

void *mb_app_under(void) { return ws->under; }
void *mb_app_under_of(int wid) { return wid >= 0 && wid < MB_WINS ? win_slots[wid].under : NULL; }
int mb_app_wid(void) { return win_active; }

// the app's widgets for the system's accessibility (@hostapi.a11y_on, a11y_tree): accessibles under the canvas
#include "linux_a11y.h"

// The canvas: a GtkGLArea that holds no press where a native view shows (linux_views.c): the view under it has it.
// Drawn at the window's own scale, a fractional one too (GNOME's 125%, 150%, at which GTK draws the window:
// gdk_surface_get_scale): GtkGLArea makes its picture at the whole scale above that (2 for 1.25), which GTK then
// shrinks as it draws the window, softer than the rest of it and over twice the pixels. So the area's GL context is
// kept, but its picture is the canvas's own: a texture of the surface's scale drawn into through a framebuffer of its
// own (on_render), handed to GTK as a GdkGLTexture, which it draws pixel for pixel; upside down as GL draws, flipped
// back as GtkGLArea does. A texture GTK still holds is not drawn into; the last one drawn is drawn again when the
// window is drawn for something else.
typedef struct {
  GLuint id;
  int w, h;
  int held;     // GTK has it (its GdkTexture not released yet)
  GLsync sync;  // the fence GTK waited on for it, let go as it is drawn into again
} CanvasTex;

typedef struct {
  GtkGLArea parent;
  GLuint fbo;
  GPtrArray *texs;    // CanvasTex, made as needed, kept for drawing into again
  GdkTexture *last;   // the picture drawn last
  int needs_render;   // a frame asked for (canvas_queue_render), or none drawn yet
} Canvas;
typedef struct {
  GtkGLAreaClass parent;
} CanvasClass;
G_DEFINE_TYPE_WITH_CODE(Canvas, canvas, GTK_TYPE_GL_AREA,
                        G_IMPLEMENT_INTERFACE(GTK_TYPE_ACCESSIBLE, canvas_accessible_init))

static gboolean on_render(GtkGLArea *a, GdkGLContext *c, gpointer data);
static void canvas_resized(int pw, int ph);

static gboolean canvas_contains(GtkWidget *w, double x, double y) {
  return !mb_views_pass_through(x, y) && GTK_WIDGET_CLASS(canvas_parent_class)->contains(w, x, y);
}

// a frame of the canvas asked for: drawn as GTK next draws the window
static void canvas_queue_render(GtkWidget *w) {
  ((Canvas *)w)->needs_render = 1;
  gtk_widget_queue_draw(w);
}

static void canvas_tex_released(gpointer data) { ((CanvasTex *)data)->held = 0; }

// the window's scale now, fractional ones too
static double canvas_scale(GtkWidget *w) {
  GtkNative *n = gtk_widget_get_native(w);
  GdkSurface *s = n ? gtk_native_get_surface(n) : NULL;
  double k = s ? gdk_surface_get_scale(s) : 0;
  return k > 0 ? k : gtk_widget_get_scale_factor(w);
}

// The size the frame being drawn is drawn at (points), the area's as GTK lays it out, or the window's as it is to be
// while it is held out of sight (held_frame: not laid out yet)
static int draw_lw, draw_lh;

// A frame of canvas `w` drawn (its window in place) at lw × lh points, k pixels a point, into a texture of its own:
// the picture GTK is handed (c->last). 0 where it could not be.
static int canvas_draw(GtkWidget *w, int lw, int lh, double k) {
  Canvas *c = (Canvas *)w;
  GdkGLContext *ctx = gtk_gl_area_get_context(GTK_GL_AREA(w));
  int pw = (int)lround(lw * k), ph = (int)lround(lh * k);
  gtk_gl_area_make_current(GTK_GL_AREA(w));
  CanvasTex *t = NULL;
  for (guint i = 0; i < c->texs->len && !t; i++) {
    CanvasTex *u = g_ptr_array_index(c->texs, i);
    if (!u->held) t = u;
  }
  if (!t) {
    t = g_new0(CanvasTex, 1);
    glGenTextures(1, &t->id);
    g_ptr_array_add(c->texs, t);
  }
  if (t->sync) glDeleteSync(t->sync), t->sync = NULL;
  glBindTexture(GL_TEXTURE_2D, t->id);
  if (t->w != pw || t->h != ph) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, pw, ph, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    t->w = pw, t->h = ph;
  }
  if (!c->fbo) glGenFramebuffers(1, &c->fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, t->id, 0);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    fprintf(stderr, "mbui: the canvas's framebuffer is not complete (%dx%d)\n", pw, ph);
    return 0;
  }
  canvas_resized(pw, ph);
  c->needs_render = 0;
  draw_lw = lw, draw_lh = lh;
  on_render(GTK_GL_AREA(w), ctx, NULL);
  glBindFramebuffer(GL_FRAMEBUFFER, c->fbo);
  GdkGLTextureBuilder *b = gdk_gl_texture_builder_new();
  gdk_gl_texture_builder_set_context(b, ctx);
  gdk_gl_texture_builder_set_id(b, t->id);
  gdk_gl_texture_builder_set_width(b, pw);
  gdk_gl_texture_builder_set_height(b, ph);
  gdk_gl_texture_builder_set_format(b, GDK_MEMORY_R8G8B8A8_PREMULTIPLIED);
  // (GTK draws it once GL is done with it: a fence, which OpenGL ES 3 has)
  t->sync = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);
  gdk_gl_texture_builder_set_sync(b, t->sync);
  t->held = 1;
  g_clear_object(&c->last);
  c->last = gdk_gl_texture_builder_build(b, canvas_tex_released, t);
  g_object_unref(b);
  return 1;
}

// Drawn as GTK draws the window: the frame asked for drawn now, in the snapshot (so a window's first picture on the
// screen is the app's: a window of the run beside the first comes up with its page), else the last drawn again.
static void canvas_snapshot_here(GtkWidget *w, GtkSnapshot *snap) {
  Canvas *c = (Canvas *)w;
  GdkGLContext *ctx = gtk_gl_area_get_context(GTK_GL_AREA(w));
  int lw = gtk_widget_get_width(w), lh = gtk_widget_get_height(w);
  if (!ctx || gtk_gl_area_get_error(GTK_GL_AREA(w))) {
    GTK_WIDGET_CLASS(canvas_parent_class)->snapshot(w, snap);
    return;
  }
  if (lw <= 0 || lh <= 0) return;
  double k = canvas_scale(w);
  int pw = (int)lround(lw * k), ph = (int)lround(lh * k);
  if (c->last && (gdk_texture_get_width(c->last) != pw || gdk_texture_get_height(c->last) != ph)) c->needs_render = 1;
  if ((c->needs_render || !c->last) && !canvas_draw(w, lw, lh, k)) return;
  if (!c->last) return;
  gtk_snapshot_save(snap);
  gtk_snapshot_translate(snap, &GRAPHENE_POINT_INIT(0, lh));
  gtk_snapshot_scale(snap, 1, -1);
  gtk_snapshot_append_texture(snap, c->last, &GRAPHENE_RECT_INIT(0, 0, lw, lh));
  gtk_snapshot_restore(snap);
}

// (with its window in place)
static void canvas_snapshot(GtkWidget *w, GtkSnapshot *snap) {
  int k = win_of_area(w);
  if (k < 0) return;
  int back = win_active;
  win_use(k);
  canvas_snapshot_here(w, snap);
  win_put_back(back);
}

// its scale changing (to another monitor's, the desktop's setting changed): drawn anew at it
static void canvas_on_scale(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p;
  canvas_queue_render(data);
}

static void canvas_realize(GtkWidget *w) {
  GTK_WIDGET_CLASS(canvas_parent_class)->realize(w);
  GdkSurface *s = gtk_native_get_surface(gtk_widget_get_native(w));
  if (s) g_signal_connect_object(s, "notify::scale", G_CALLBACK(canvas_on_scale), w, 0);
  ((Canvas *)w)->needs_render = 1;
}

// its context let go: what was made in it with it (a texture GTK holds yet is left to GTK's release of it)
static void canvas_unrealize(GtkWidget *w) {
  Canvas *c = (Canvas *)w;
  if (gtk_gl_area_get_context(GTK_GL_AREA(w))) {
    gtk_gl_area_make_current(GTK_GL_AREA(w));
    if (c->fbo) glDeleteFramebuffers(1, &c->fbo);
    for (guint i = 0; i < c->texs->len; i++) {
      CanvasTex *t = g_ptr_array_index(c->texs, i);
      glDeleteTextures(1, &t->id);
      if (t->sync) glDeleteSync(t->sync);
    }
  }
  c->fbo = 0;
  g_clear_object(&c->last);
  g_ptr_array_set_size(c->texs, 0);
  GTK_WIDGET_CLASS(canvas_parent_class)->unrealize(w);
}

static void canvas_class_init(CanvasClass *k) {
  GTK_WIDGET_CLASS(k)->contains = canvas_contains;
  GTK_WIDGET_CLASS(k)->snapshot = canvas_snapshot;
  GTK_WIDGET_CLASS(k)->realize = canvas_realize;
  GTK_WIDGET_CLASS(k)->unrealize = canvas_unrealize;
}

static void canvas_init(Canvas *c) { c->texs = g_ptr_array_new(); }

static void device_tell(mb_outside_fn tell);  // linux_device.h: the clipboard's reads done
static void pick_tell(mb_outside_fn tell);    // the files picked
static void drop_start(void);                 // what is let go on the window in place taken
static int drop_drive(const char *text);      // a scripted run's drop
static void update_tell(mb_outside_fn tell);  // linux_update.h: how an update goes
void mb_host_set_cursor(int32_t kind);

// The area's context made current again for what is drawn: once WebKit is in the process (linux_views.c), its own GL
// can leave another context current, or none, behind GDK's back, and GDK's make_current, which goes by the one it made
// current last, would do nothing.
static GtkWidget *area_with_context(int but);
static void gl_current(void) {
  if (!mb_views_webkit()) return;
  gdk_gl_context_clear_current();
  // (the window in place's: every window's canvas has the one context, the first's realized or not)
  GtkWidget *a = ws->area && gtk_widget_get_realized(ws->area) ? ws->area : area_with_context(-1);
  if (a) gtk_gl_area_make_current(GTK_GL_AREA(a));
}

static gboolean on_render(GtkGLArea *a, GdkGLContext *c, gpointer data) {
  (void)c, (void)data;
  int app_wanted = ws->want_frame;
  ws->want_frame = 0;
  gl_current();
  if (!app_wanted && ws->ad_stepping) {
    ws->ad_stepping = 0;
    int w = draw_lw, h = draw_lh;
    if (w > 0 && h > 0 && ws->fb_pw > 0 && ws->fb_ph > 0) {
      mb_render_target(ws->fb_pw, ws->fb_ph, w, h, ws->scale);
      if (mb_render_adaptive_step() && mb_render_adaptive_settling()) {
        ws->ad_stepping = 1;
        gtk_gl_area_queue_render(a);
      }
    }
    return TRUE;
  }
  ws->ad_stepping = 0;
  // what was decoded meanwhile made textures, then told: the app finds them ready
  mb_images_upload();
  mb_streams_upload();
  mb_players_upload();
  mb_images_tell(outside_cb);
  device_tell(outside_cb);
  update_tell(outside_cb);
  mb_views_tell(outside_cb);
  int w = draw_lw, h = draw_lh;
  if (w <= 0 || h <= 0 || ws->fb_pw <= 0 || ws->fb_ph <= 0) return TRUE;
  double was = ws->scale;
  ws->scale = ws->fb_pw / (double)w;
  if (ws->scale != was) mb_views_rescale();
  ws->frame_w = w;
  ws->frame_h = h;
  mb_text_set_scale(ws->scale);
  mb_render_target(ws->fb_pw, ws->fb_ph, w, h, ws->scale);
  GdkFrameClock *clock = gtk_widget_get_frame_clock(GTK_WIDGET(a));
  double now = clock ? gdk_frame_clock_get_frame_time(clock) / 1000.0 : mb_now_ms();
  mb_cb.frame(w, h, ws->scale, now);
  // (a scripted run's steps go by the first window's frames)
  if (win_active == 0) {
    frames_drawn++;
    if (script) run_script_step(frames_drawn);
    // (shown, as the frame it was shown in ends: presented, its picture that frame's)
    if (window_to_show && !window_shown) {
      window_to_show = 0;
      window_shown = 1;
      gtk_window_present(GTK_WINDOW(ws->win));
    }
  }
  if (ws->want_frame) schedule();
  else if (mb_render_adaptive_settling()) {
    ws->ad_stepping = 1;
    gtk_gl_area_queue_render(a);
  }
  return TRUE;
}

// the framebuffer's size in pixels (the canvas's, at the window's scale), as it changes
static void canvas_resized(int pw, int ph) {
  if (pw == ws->fb_pw && ph == ws->fb_ph) return;
  ws->fb_pw = pw;
  ws->fb_ph = ph;
  schedule();
}

static int context_kept;  // the first's canvas given the context the windows beside it kept (canvas_context)
static void on_realize(GtkWidget *w, gpointer data) {
  (void)data;
  // (the first's canvas, whichever window is in place as it is realized: shown again from a window beside it)
  int back = win_active;
  win_use(0);
  gtk_gl_area_make_current(GTK_GL_AREA(w));
  GError *e = gtk_gl_area_get_error(GTK_GL_AREA(w));
  if (e) {
    fprintf(stderr, "mbui: no OpenGL ES 3 context: %s\n", e->message);
    exit(1);
  }
  // (the first's canvas realized again on the context the windows beside it kept: what was made in it stands)
  if (!context_kept) mb_render_setup();
  context_kept = 0;
  if (context_asked) context_asked = 0, context_new = 1;
  schedule();
  win_put_back(back);
}

// maximized or back, full screen or back: the app's top row and its buttons as it now is
static void on_window_state_here(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p, (void)data;
  schedule();
}

// ---- the input method ----

static void ime_place(void) {
  if (!ws->ime_active) return;
  GdkRectangle r = {(int)lround(ws->caret[0]), (int)lround(ws->caret[1]), (int)lround(ws->caret[2] > 1 ? ws->caret[2] : 1),
                    (int)lround(ws->caret[3])};
  gtk_im_context_set_cursor_location(ws->im, &r);
}

static void on_commit_here(GtkIMContext *c, const char *s, gpointer data) {
  (void)c, (void)data;
  ws->marked_len = 0;
  if (!ws->ime_active) return;
  // control characters come as keys (Enter, Backspace) or shortcuts
  if ((unsigned char)s[0] < 0x20 && !s[1]) return;
  send_text(0, s, 0, 0);
}

static void on_preedit_here(GtkIMContext *c, gpointer data) {
  (void)data;
  char *s = NULL;
  int cursor = 0;
  gtk_im_context_get_preedit_string(c, &s, NULL, &cursor);
  // the cursor in the composition: characters there, UTF-16 units here
  glong n = 0, at = 0;
  gunichar2 *u = g_utf8_to_utf16(s, -1, NULL, &n, NULL);
  const char *p = s;
  for (int i = 0; i < cursor && *p; i++, p = g_utf8_next_char(p)) at += g_utf8_get_char(p) >= 0x10000 ? 2 : 1;
  g_free(u);
  ws->marked_len = (int)n;
  send_text(1, s, (int)at, 0);
  g_free(s);
  ime_place();
}

static void on_preedit_end_here(GtkIMContext *c, gpointer data) {
  (void)c, (void)data;
  if (ws->marked_len) send_text(1, "", 0, 0);
  ws->marked_len = 0;
}

static gboolean on_surrounding_here(GtkIMContext *c, gpointer data) {
  (void)data;
  const char *w = ws->ime_words ? ws->ime_words : "";
  gtk_im_context_set_surrounding_with_selection(c, w, -1, ws->ime_sel_b, ws->ime_sel_a);
  return TRUE;
}

// the input method deleting round the caret (n characters from `offset`): the field's Backspace or Delete
static gboolean on_delete_surrounding_here(GtkIMContext *c, int offset, int n, gpointer data) {
  (void)c, (void)data;
  int before = offset < 0 ? -offset : 0, after = offset + n > 0 ? offset + n : 0;
  if (before > n) before = n;
  mb_cb.text(4, moonbit_make_string_raw(0), before, after);
  return TRUE;
}

// ---- the clipboard ----

static void paste_done_here(GObject *src, GAsyncResult *res, gpointer data);
static void paste_done(GObject *src, GAsyncResult *res, gpointer data) {
  int back = win_in(data);
  paste_done_here(src, res, data);
  win_put_back(back);
}
static void paste_done_here(GObject *src, GAsyncResult *res, gpointer data) {
  (void)data;
  char *s = gdk_clipboard_read_text_finish(GDK_CLIPBOARD(src), res, NULL);
  if (s && *s) {
    GString *t = g_string_new(NULL);
    for (const char *p = s; *p; p++)
      if (!(p[0] == '\r' && p[1] == '\n')) g_string_append_c(t, *p);
    send_text(8, t->str, 0, 0);  // put in as typed, a step of its own to undo
    g_string_free(t, TRUE);
  }
  g_free(s);
}

static int mods_of(GdkModifierType m) {
  return ((m & GDK_SHIFT_MASK) ? 1 : 0) | ((m & GDK_CONTROL_MASK) ? 2 : 0) | ((m & GDK_ALT_MASK) ? 4 : 0) |
         ((m & GDK_SUPER_MASK) ? 8 : 0);
}
int32_t mb_host_mods_held(void);

// the device beyond the window (device.mbt): a key catcher's keys, the clipboard read
#include "linux_device.h"

// ---- keys ----

static gboolean on_key_here(GtkEventControllerKey *k, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  (void)k, (void)keycode, (void)data;
  int mods = mods_of(state);
  // a key catcher's focus (linux_device.h): its keys (a composition under way keeps them)
  if (key_catching && ws->ime_active && ws->marked_len == 0 && catch_key(keyval, mods)) return TRUE;
  if ((mods & 4) && !(mods & 2) && keyval == GDK_KEY_Left && go_back()) return TRUE;
  // Alt+Right: forward, the app's key (key_forward)
  if ((mods & 4) && !(mods & 2) && keyval == GDK_KEY_Right) {
    mb_cb.key(40, 0);
    return TRUE;
  }
  if (mods & 2) {
    int ch = key_char(keyval);
    switch (ch) {
      case 'a': mb_cb.key(12, mods); return TRUE;
      case 'c': mb_cb.key(13, mods); return TRUE;
      case 'x': mb_cb.key(14, mods); return TRUE;
      case 'v': {
        // files or a picture on it: the app's Ctrl+V (1000 + v), which reads the clipboard for it (@hostapi.clip_read),
        // as a page's paste takes them as files; else its words
        GdkContentFormats *f = clip_formats();
        int app = gdk_content_formats_contain_gtype(f, GDK_TYPE_FILE_LIST) ||
                  gdk_content_formats_contain_gtype(f, GDK_TYPE_TEXTURE);
        gdk_content_formats_unref(f);
        if (app) mb_cb.key(1000 + 'v', mods);
        else gdk_clipboard_read_text_async(gtk_widget_get_clipboard(ws->area), NULL, paste_done, GINT_TO_POINTER(win_active));
        return TRUE;
      }
    }
    // any other Ctrl key with a character: the app's shortcut (1000 + the character, lower case)
    if (ch && !named_key(keyval)) {
      mb_cb.key(1000 + ch, mods);
      return TRUE;
    }
  }
  int code = named_key(keyval);
  // without a field to type in, these scroll the list under the pointer
  if ((code == 15 || code == 16) && ws->ime_active) code = 0;
  if (code) {
    mb_cb.key(code, mods);
    return TRUE;
  }
  // a character with no field to take it (Space, a letter): the app's, as 1000 + it
  if (!ws->ime_active) {
    int ch = key_char(keyval);
    if (ch) {
      mb_cb.key(1000 + ch, mods);
      return TRUE;
    }
  }
  return FALSE;
}

// ---- the pointer ----

// an event's place in the area's points
static void area_point(GdkEvent *ev, double *x, double *y) {
  double sx = 0, sy = 0, nx = 0, ny = 0;
  GtkNative *native = gtk_widget_get_native(ws->area);
  if (gdk_event_get_position(ev, &sx, &sy) && isfinite(sx) && isfinite(sy)) {
    ws->ptr_x = sx;
    ws->ptr_y = sy;
    ws->ptr_valid = 1;
  } else {
    // GTK 4 scroll events carry no coordinates (gdk_event_get_position returns FALSE and writes NaN);
    // query the seat pointer on the event's surface, falling back to the last valid surface position.
    GdkSurface *surf = gdk_event_get_surface(ev);
    if (!surf && native) surf = gtk_native_get_surface(native);
    GdkSeat *seat = gdk_event_get_seat(ev);
    if (!seat && surf) {
      GdkDisplay *disp = gdk_surface_get_display(surf);
      if (disp) seat = gdk_display_get_default_seat(disp);
    }
    GdkDevice *ptr = seat ? gdk_seat_get_pointer(seat) : NULL;
    GdkModifierType mask = 0;
    if (surf && ptr && gdk_surface_get_device_position(surf, ptr, &sx, &sy, &mask) && isfinite(sx) && isfinite(sy)) {
      ws->ptr_x = sx;
      ws->ptr_y = sy;
      ws->ptr_valid = 1;
    } else if (ws->ptr_valid) {
      sx = ws->ptr_x;
      sy = ws->ptr_y;
    } else {
      sx = 0;
      sy = 0;
    }
  }
  if (!native) {
    *x = sx;
    *y = sy;
    return;
  }
  gtk_native_get_surface_transform(native, &nx, &ny);
  graphene_point_t p = GRAPHENE_POINT_INIT((float)(sx - nx), (float)(sy - ny)), out;
  if (gtk_widget_compute_point(GTK_WIDGET(native), ws->area, &p, &out)) {
    *x = out.x;
    *y = out.y;
  } else {
    *x = sx - nx;
    *y = sy - ny;
  }
}

// A wheel's notch: 53 points, as a browser on Linux scrolls by one (Chromium's three lines), eased in by the app
// (phase 4); a touchpad's as it comes, in the surface's points (phase 1, the fingers on it).
#define NOTCH 53.333

static void scroll(GdkEvent *ev, double x, double y) {
  int mods = mods_of(gdk_event_get_modifier_state(ev));
  GdkScrollDirection d = gdk_scroll_event_get_direction(ev);
  double dx = 0, dy = 0;
  int phase = 4;
  if (d == GDK_SCROLL_SMOOTH) {
    gdk_scroll_event_get_deltas(ev, &dx, &dy);
    if (gdk_scroll_event_get_unit(ev) == GDK_SCROLL_UNIT_SURFACE) {
      phase = 1;
    } else {
      dx *= NOTCH;
      dy *= NOTCH;
    }
  } else {
    dy = d == GDK_SCROLL_UP ? -NOTCH : d == GDK_SCROLL_DOWN ? NOTCH : 0;
    dx = d == GDK_SCROLL_LEFT ? -NOTCH : d == GDK_SCROLL_RIGHT ? NOTCH : 0;
  }
  // Shift turns a mouse's wheel sideways, as the system's own widgets do
  if (phase == 4 && (mods & 1) && dx == 0) {
    dx = dy;
    dy = 0;
  }
  if (dx != 0 || dy != 0) mb_cb.wheel(x, y, dx, dy, phase | (mods << 4));
}

// The touches, each by its sequence (the same from its begin to its end), given an id of its own while it lasts (its
// whole pointer kept, never cut to an int): handed on as they come (pointer kinds 10 begun, 11 moved, 12 ended, 13
// called off, the id where a button goes), what they come to the app's to work out (touches.mbt: two of them its, the
// first let go the second the first, one called off all of it).
//
// Its time not said: GDK gives an event's (gdk_event_get_time) as ms on the display server's clock, 32 bits, wrapping,
// GDK_CURRENT_TIME (0) where it has none; neither GDK nor Wayland's or X's protocol says how that clock lines up with
// this process's (mb_now_ms), and nothing here has checked a backend that does. So no time of its own is said for it
// (mb_host_event_time -1): it is at the moment it is handled, as this host's other events are; what it did is kept on
// the tape at that moment and given again so. (Saying its own would need a backend's clock known to be this one.)
static GHashTable *touch_ids;          // a sequence's id, by its pointer
static int32_t touch_next = 1;
static void touch(GdkEvent *ev, GdkEventType t, double x, double y) {
  GdkEventSequence *s = gdk_event_get_event_sequence(ev);
  int kind = t == GDK_TOUCH_BEGIN ? 10 : t == GDK_TOUCH_UPDATE ? 11 : t == GDK_TOUCH_END ? 12 : 13;
  if (!touch_ids) touch_ids = g_hash_table_new(g_direct_hash, g_direct_equal);
  gpointer got = g_hash_table_lookup(touch_ids, s);
  int32_t id;
  if (got) {
    id = GPOINTER_TO_INT(got);
  } else {
    // (a sequence not begun here, its begin not seen: none of the app's)
    if (kind != 10) return;
    id = touch_next++;
    if (touch_next <= 0) touch_next = 1;
    g_hash_table_insert(touch_ids, s, GINT_TO_POINTER(id));
  }
  if (kind == 10) gtk_widget_grab_focus(ws->area);
  mb_cb.pointer(kind, x, y, id);
  if (kind == 12 || kind == 13) g_hash_table_remove(touch_ids, s);
}

// (with the window it came to in place: a view's, of whichever window it is in)
void mb_app_scroll(void *event) {
  GdkSurface *at = gdk_event_get_surface(event);
  int k = 0;
  for (int i = 0; i < MB_WINS; i++)
    if (win_slots[i].win && at && gtk_native_get_surface(GTK_NATIVE(win_slots[i].win)) == at) k = i;
  int back = win_active;
  win_use(k);
  double x = 0, y = 0;
  area_point(event, &x, &y);
  scroll(event, x, y);
  win_put_back(back);
}

static gboolean on_event_here(GtkEventControllerLegacy *c, GdkEvent *ev, gpointer data) {
  (void)c, (void)data;
  GdkEventType t = gdk_event_get_event_type(ev);
  // a pointer the system made of a touch: the touch is had already
  int pointer = t == GDK_BUTTON_PRESS || t == GDK_BUTTON_RELEASE || t == GDK_MOTION_NOTIFY;
  if (pointer && gdk_event_get_pointer_emulated(ev)) return TRUE;
  double x = 0, y = 0;
  switch (t) {
    case GDK_BUTTON_PRESS: {
      area_point(ev, &x, &y);
      guint b = gdk_button_event_get_button(ev);
      ws->press_device = gdk_event_get_device(ev);
      gdk_event_get_position(ev, &ws->press_x, &ws->press_y);
      ws->press_time = gdk_event_get_time(ev);
      ws->press_button = (int)b;
      gtk_widget_grab_focus(ws->area);
      if (b == 1) {
        ws->left_down = 1;
        mb_cb.pointer(0, x, y, 0);
      } else if (b == 2) {
        ws->middle_down = 1;
        mb_cb.pointer(0, x, y, 3);
      } else if (b == 3) {
        ws->right_down = 1;
        mb_cb.pointer(0, x, y, 2);
      }
      return TRUE;
    }
    case GDK_BUTTON_RELEASE: {
      area_point(ev, &x, &y);
      guint b = gdk_button_event_get_button(ev);
      if (b == 1 && ws->left_down) {
        ws->left_down = 0;
        mb_cb.pointer(2, x, y, 0);
      } else if (b == 2 && ws->middle_down) {
        ws->middle_down = 0;
        mb_cb.pointer(2, x, y, 3);
      } else if (b == 3 && ws->right_down) {
        ws->right_down = 0;
        mb_cb.pointer(2, x, y, 2);
      } else if (b == 8) {
        go_back();
      } else if (b == 9) {
        mb_cb.key(40, 0);
      }
      return TRUE;
    }
    case GDK_MOTION_NOTIFY:
      area_point(ev, &x, &y);
      mb_cb.pointer(1, x, y, 0);
      return TRUE;
    case GDK_LEAVE_NOTIFY:
      if (!ws->left_down && !ws->middle_down) mb_cb.pointer(7, -1, -1, 0);
      return FALSE;
    case GDK_SCROLL:
      area_point(ev, &x, &y);
      scroll(ev, x, y);
      return TRUE;
    case GDK_TOUCH_BEGIN:
    case GDK_TOUCH_UPDATE:
    case GDK_TOUCH_END:
    case GDK_TOUCH_CANCEL:
      area_point(ev, &x, &y);
      touch(ev, t, x, y);
      return TRUE;
    default:
      return FALSE;
  }
}

static void on_focus_in_here(GtkEventControllerFocus *f, gpointer data) {
  (void)f, (void)data;
  if (ws->ime_active) gtk_im_context_focus_in(ws->im);
}

static void on_focus_out_here(GtkEventControllerFocus *f, gpointer data) {
  (void)f, (void)data;
  if (ws->ime_active) gtk_im_context_focus_out(ws->im);
}


// ---- each window's handlers: what they handle done with their window in place (their data: its number) ----

static void on_window_state(GObject *o, GParamSpec *p, gpointer data) {
  int back = win_in(data);
  on_window_state_here(o, p, data);
  win_put_back(back);
}
static void on_commit(GtkIMContext *c, const char *s, gpointer data) {
  int back = win_in(data);
  on_commit_here(c, s, data);
  win_put_back(back);
}
static void on_preedit(GtkIMContext *c, gpointer data) {
  int back = win_in(data);
  on_preedit_here(c, data);
  win_put_back(back);
}
static void on_preedit_end(GtkIMContext *c, gpointer data) {
  int back = win_in(data);
  on_preedit_end_here(c, data);
  win_put_back(back);
}
static gboolean on_surrounding(GtkIMContext *c, gpointer data) {
  int back = win_in(data);
  gboolean r = on_surrounding_here(c, data);
  win_put_back(back);
  return r;
}
static gboolean on_delete_surrounding(GtkIMContext *c, int offset, int n, gpointer data) {
  int back = win_in(data);
  gboolean r = on_delete_surrounding_here(c, offset, n, data);
  win_put_back(back);
  return r;
}
static gboolean on_key(GtkEventControllerKey *k, guint keyval, guint keycode, GdkModifierType state, gpointer data) {
  int back = win_in(data);
  gboolean r = on_key_here(k, keyval, keycode, state, data);
  win_put_back(back);
  return r;
}
static gboolean on_modifiers(GtkEventControllerKey *k, GdkModifierType state, gpointer data) {
  (void)k;
  int back = win_in(data);
  mb_cb.key(0, mods_of(state));
  win_put_back(back);
  return FALSE;
}
static gboolean on_event(GtkEventControllerLegacy *c, GdkEvent *ev, gpointer data) {
  int back = win_in(data);
  gboolean r = on_event_here(c, ev, data);
  win_put_back(back);
  return r;
}
static void on_focus_in(GtkEventControllerFocus *f, gpointer data) {
  int back = win_in(data);
  mb_cb.key(0, mb_host_mods_held());
  on_focus_in_here(f, data);
  win_put_back(back);
}
static void on_focus_out(GtkEventControllerFocus *f, gpointer data) {
  int back = win_in(data);
  mb_cb.key(0, 0);
  on_focus_out_here(f, data);
  win_put_back(back);
}

// the window shown and in front (is-active) or not: 1 while shown, | 2 while in front
static void app_state(void) {
  GtkWidget *first = win_slots[0].win;
  if (!state_cb || !first) return;
  // (shown: any window of the run's, the first put away and another open among them)
  int shown = 0;
  for (int k = 0; k < MB_WINS && !shown; k++)
    if (win_slots[k].win && gtk_widget_get_mapped(win_slots[k].win)) shown = 1;
  // (in front: any window of the run's, a window beside the first among them)
  int front = 0;
  for (int k = 0; k < MB_WINS && shown; k++)
    if (win_slots[k].win && gtk_window_is_active(GTK_WINDOW(win_slots[k].win))) front = 1;
  // (told only as it changes: the same said again tells the app nothing, and draws nothing)
  static int told = -1;
  int s = (shown ? 1 : 0) | (front ? 2 : 0);
  if (s == told) return;
  // (no window of the run's on the screen any more: what drawing holds beyond its frames given back, in the run's
  // context, made again as a frame is drawn: mb_render_trim)
  if (!shown && told > 0 && (told & 1)) {
    GtkWidget *a = area_with_context(-1);
    if (a) {
      gdk_gl_context_clear_current();
      gtk_gl_area_make_current(GTK_GL_AREA(a));
      if (!gtk_gl_area_get_error(GTK_GL_AREA(a))) mb_render_trim();
    }
  }
  told = s;
  state_cb(s);
  schedule();
}

static void on_active(GObject *o, GParamSpec *p, gpointer data) {
  (void)o, (void)p, (void)data;
  app_state();
}

// the app's life: once for its person, put away to its icon, links, the network, sleep; and its updates
#include "linux_life.h"
#include "linux_update.h"

// ---- the system's settings: its colours, its words' size and face, its animations ----

static int portal_dark = -1;  // the desktop portal's color-scheme: 1 dark, 0 not, -1 unknown

static void color_scheme_is(GVariant *v) {
  while (v && g_variant_is_of_type(v, G_VARIANT_TYPE_VARIANT)) {
    GVariant *in = g_variant_get_variant(v);
    g_variant_unref(v);
    v = in;
  }
  if (v && g_variant_is_of_type(v, G_VARIANT_TYPE_UINT32)) portal_dark = g_variant_get_uint32(v) == 1;
  if (v) g_variant_unref(v);
}

static void on_setting_changed(GDBusConnection *c, const char *sender, const char *path, const char *iface,
                               const char *signal, GVariant *params, gpointer data) {
  (void)c, (void)sender, (void)path, (void)iface, (void)signal, (void)data;
  const char *ns = NULL, *key = NULL;
  GVariant *v = NULL;
  g_variant_get(params, "(&s&sv)", &ns, &key, &v);
  if (!strcmp(ns, "org.freedesktop.appearance") && !strcmp(key, "color-scheme")) color_scheme_is(v);
  else if (v) g_variant_unref(v);
  schedule();
}

static void settings_watch(void) {
  GDBusConnection *bus = g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL);
  if (!bus) return;
  GVariant *r = g_dbus_connection_call_sync(
      bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
      "ReadOne", g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"), NULL, G_DBUS_CALL_FLAGS_NONE, 500,
      NULL, NULL);
  if (!r)  // (a portal before ReadOne)
    r = g_dbus_connection_call_sync(bus, "org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                                    "org.freedesktop.portal.Settings", "Read",
                                    g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"), NULL,
                                    G_DBUS_CALL_FLAGS_NONE, 500, NULL, NULL);
  if (r) {
    GVariant *v = NULL;
    g_variant_get(r, "(v)", &v);
    color_scheme_is(v);
    g_variant_unref(r);
  }
  g_dbus_connection_signal_subscribe(bus, "org.freedesktop.portal.Desktop", "org.freedesktop.portal.Settings",
                                     "SettingChanged", "/org/freedesktop/portal/desktop", NULL,
                                     G_DBUS_SIGNAL_FLAGS_NONE, on_setting_changed, NULL, NULL);
}

static void on_font_name(GObject *o, GParamSpec *p, gpointer data) {
  (void)p, (void)data;
  char *name = NULL;
  g_object_get(o, "gtk-font-name", &name, NULL);
  PangoFontDescription *d = name ? pango_font_description_from_string(name) : NULL;
  if (d && pango_font_description_get_family(d)) mb_text_set_family(pango_font_description_get_family(d));
  if (d) pango_font_description_free(d);
  g_free(name);
  schedule();
}

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime|shot): drive the same paths an input method takes and save snapshots, as the macOS
// and Windows hosts do.

static void shot(const char *name) {
  if (!shot_dir) return;
  char p[1024];
  snprintf(p, sizeof p, "%s/%s.png", shot_dir, name);
  int ok = mb_render_snapshot(p);
  fprintf(stdout, "SHOT %s %s\n", p, ok ? "ok" : "failed");
  fflush(stdout);
}

static void run_script_step(int step) {
  double h = ws->frame_h;
  if (strcmp(script, "ime") == 0) {
    switch (step) {
      case 20: shot("01-start"); break;
      case 21:  // click the composer
        mb_cb.pointer(0, 120, h - 30, 0);
        mb_cb.pointer(2, 120, h - 30, 0);
        break;
      case 30: ws->marked_len = 6; send_text(1, "ni'hao", 6, 0); break;
      case 40: shot("02-composing"); break;
      case 41: ws->marked_len = 0; send_text(0, "\xe4\xbd\xa0\xe5\xa5\xbd", 0, 0); break;  // 你好
      case 42: send_text(0, "\xef\xbc\x8cMoonBit ", 0, 0); break;                     // ，MoonBit
      case 43: ws->marked_len = 7; send_text(1, "shi'jie", 3, 0); break;
      case 50: shot("03-composing-2"); break;
      case 51: ws->marked_len = 0; send_text(0, "\xe4\xb8\x96\xe7\x95\x8c \xf0\x9f\x91\x8b", 0, 0); break;  // 世界 👋
      case 60: shot("04-typed"); break;
      case 61: mb_cb.key(7, 0); break;
      case 100: shot("05-sent"); break;
      case 101:
        for (int i = 0; i < 40; i++) mb_cb.wheel(300, 300, 0, 120, 0);
        break;
      case 140: shot("06-scrolled"); break;
      case 141: exit(0);
    }
    ws->want_frame = 1;
  } else if (strcmp(script, "shot") == 0) {
    // from the 30th frame
    static int done;
    if (step >= 30 && !done) {
      shot(getenv("MBUI_SHOT_NAME") ? getenv("MBUI_SHOT_NAME") : "main");
      done = step;
    } else if (done && step > done) {
      exit(0);
    }
    ws->want_frame = 1;
  }
}

// GLib's loop, run here: its sources (GTK's events, its frame clock, what other threads ask for) as they come, and the
// app's wake (@hostapi.wake_after) as the longest it waits for them, as Windows' loop waits (win_app.c): no timer.
static void run_loop(void) {
  GMainContext *ctx = g_main_context_default();
  g_main_context_acquire(ctx);
  GPollFD *fds = NULL;
  gint alloc = 0;
  for (;;) {
    if (wake_at >= 0 && mb_now_ms() >= wake_at) {
      wake_at = -1;
      schedule_all();
    }
    gint prio = 0, timeout = -1, n;
    g_main_context_prepare(ctx, &prio);
    while ((n = g_main_context_query(ctx, prio, &timeout, fds, alloc)) > alloc) {
      alloc = n;
      fds = g_renew(GPollFD, fds, alloc);
    }
    if (wake_at >= 0) {
      gint ms = (gint)ceil(wake_at - mb_now_ms());
      if (ms < 0) ms = 0;
      if (timeout < 0 || ms < timeout) timeout = ms;
    }
    g_main_context_get_poll_func(ctx)(fds, n, timeout);
    g_main_context_check(ctx, prio, fds, n);
    g_main_context_dispatch(ctx);
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

// The window in place's parts (its GtkWindow made): an inset window's title bar of nothing, its canvas (the first's
// GL context its, every window's: canvas_context), its input method and events (their data its number), its native
// views' GtkFixed under the canvas.
// A realized canvas of the run's but window `but`'s (-1: any), whose context is the run's one: NULL where none is.
static GtkWidget *area_with_context(int but) {
  for (int k = 0; k < MB_WINS; k++)
    if (k != but && win_slots[k].area && gtk_widget_get_realized(win_slots[k].area) &&
        gtk_gl_area_get_context(GTK_GL_AREA(win_slots[k].area)))
      return win_slots[k].area;
  return NULL;
}
// The context a canvas is made with: the run's one, any realized canvas's (the first's, or, the first hidden and
// realized again, that of a window beside it: what drawing made in it stands, context_kept); none, GTK's own made.
static GdkGLContext *canvas_context(GtkGLArea *a, gpointer data) {
  (void)data;
  GtkWidget *with = area_with_context(win_of_area(GTK_WIDGET(a)));
  GdkGLContext *c = with ? gtk_gl_area_get_context(GTK_GL_AREA(with)) : NULL;
  if (c && GTK_WIDGET(a) == win_slots[0].area) context_kept = 1;
  return c ? g_object_ref(c) : NULL;
}
static void win_parts(void) {
  gpointer wid = GINT_TO_POINTER(win_active);
  // an inset window: its decorations GTK's own (its shadow and the edges it is resized by), a title bar of nothing,
  // the app's top row its title bar and its buttons the app's (@ui.window_keys_own), as Windows' is
  if (ws->inset) {
    GtkWidget *none = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_visible(none, FALSE);
    gtk_window_set_titlebar(GTK_WINDOW(ws->win), none);
  }
  g_signal_connect(ws->win, "notify::maximized", G_CALLBACK(on_window_state), wid);
  g_signal_connect(ws->win, "notify::fullscreened", G_CALLBACK(on_window_state), wid);
  ws->area = g_object_new(canvas_get_type(), NULL);
  g_signal_connect(ws->area, "create-context", G_CALLBACK(canvas_context), NULL);
  gtk_gl_area_set_allowed_apis(GTK_GL_AREA(ws->area), GDK_GL_API_GLES);
  gtk_gl_area_set_required_version(GTK_GL_AREA(ws->area), 3, 0);
  gtk_gl_area_set_auto_render(GTK_GL_AREA(ws->area), FALSE);
  gtk_gl_area_set_has_depth_buffer(GTK_GL_AREA(ws->area), FALSE);
  gtk_gl_area_set_has_stencil_buffer(GTK_GL_AREA(ws->area), FALSE);
  gtk_widget_set_focusable(ws->area, TRUE);
  gtk_widget_set_hexpand(ws->area, TRUE);
  gtk_widget_set_vexpand(ws->area, TRUE);
  if (ws->min_w > 0 || ws->min_h > 0)
    gtk_widget_set_size_request(ws->area, (int)lround(ws->min_w), (int)lround(ws->min_h));

  ws->im = gtk_im_multicontext_new();
  gtk_im_context_set_client_widget(ws->im, ws->area);
  gtk_im_context_set_use_preedit(ws->im, TRUE);
  g_signal_connect(ws->im, "commit", G_CALLBACK(on_commit), wid);
  g_signal_connect(ws->im, "preedit-changed", G_CALLBACK(on_preedit), wid);
  g_signal_connect(ws->im, "preedit-end", G_CALLBACK(on_preedit_end), wid);
  g_signal_connect(ws->im, "retrieve-surrounding", G_CALLBACK(on_surrounding), wid);
  g_signal_connect(ws->im, "delete-surrounding", G_CALLBACK(on_delete_surrounding), wid);

  GtkEventController *events = gtk_event_controller_legacy_new();
  g_signal_connect(events, "event", G_CALLBACK(on_event), wid);
  gtk_widget_add_controller(ws->area, events);
  ws->keys = gtk_event_controller_key_new();
  g_signal_connect(ws->keys, "key-pressed", G_CALLBACK(on_key), wid);
  g_signal_connect(ws->keys, "modifiers", G_CALLBACK(on_modifiers), wid);
  gtk_widget_add_controller(ws->area, ws->keys);
  GtkEventController *focus = gtk_event_controller_focus_new();
  g_signal_connect(focus, "enter", G_CALLBACK(on_focus_in), wid);
  g_signal_connect(focus, "leave", G_CALLBACK(on_focus_out), wid);
  gtk_widget_add_controller(ws->area, focus);

  // the native views under the canvas (linux_views.c): the overlay's child, the canvas over it, as big as the canvas
  ws->under = gtk_fixed_new();
  GtkWidget *overlay = gtk_overlay_new();
  gtk_overlay_set_child(GTK_OVERLAY(overlay), ws->under);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), ws->area);
  gtk_overlay_set_measure_overlay(GTK_OVERLAY(overlay), ws->area, TRUE);
  gtk_window_set_child(GTK_WINDOW(ws->win), overlay);
}

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer_fn, mb_wheel_fn wheel_fn,
                 mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer_fn, wheel_fn, key, text};
  script = getenv("MBUI_SCRIPT");
  shot_dir = getenv("MBUI_SHOT_DIR");
  // this machine's name (MBUI_MACHINE, @ui.env): what a station added from here is called (sfbase local_machine_name)
  if (!getenv("MBUI_MACHINE")) setenv("MBUI_MACHINE", g_get_host_name(), 0);
  setlocale(LC_ALL, "");
  // its icon's name its id (MBUI_APP_ID, as its desktop entry runs it: still.fail's linux/install.sh), which the
  // desktop knows its window by too (life_begin)
  gtk_init();
  if (*app_id()) gtk_window_set_default_icon_name(app_id());
  GtkSettings *gs = gtk_settings_get_default();
  if (gs) {
    on_font_name(G_OBJECT(gs), NULL, NULL);
    g_signal_connect(gs, "notify::gtk-font-name", G_CALLBACK(on_font_name), NULL);
  }
  settings_watch();

  ws->inset = setup_inset;
  ws->min_w = setup_min_w;
  ws->min_h = setup_min_h;
  ws->win = gtk_window_new();
  window_front_listen();
  char *t = utf8(title);
  gtk_window_set_title(GTK_WINDOW(ws->win), t);
  // MBUI_WIN=<w>x<h>: the area's size in points (a phone's, for the narrow layouts); else the app's own
  // (@hostapi.window_setup); 900 x 720 by default
  double ww = setup_w > 0 ? setup_w : 900, wh = setup_h > 0 ? setup_h : 720;
  const char *size = getenv("MBUI_WIN");
  if (size) sscanf(size, "%lfx%lf", &ww, &wh);
  held_w = (int)lround(ww), held_h = (int)lround(wh);
  gtk_window_set_default_size(GTK_WINDOW(ws->win), held_w, held_h);
  g_signal_connect(ws->win, "notify::is-active", G_CALLBACK(on_active), NULL);
  g_signal_connect(ws->win, "notify::visible", G_CALLBACK(on_active), NULL);
  life_start(t);
  g_free(t);
  win_parts();
  g_signal_connect(ws->area, "realize", G_CALLBACK(on_realize), NULL);
  drop_start();
  // (held: out of sight till the app shows it, its frames drawn meanwhile: held_frame)
  if (window_held && !window_shown) {
    gtk_widget_realize(ws->area);
  } else {
    window_shown = 1;
    gtk_window_present(GTK_WINDOW(ws->win));
  }
  gtk_widget_grab_focus(ws->area);
  schedule();
  run_loop();
}

// The first window's frame while it is held (held_tick): drawn as GTK would draw it, at the size it is to have, its
// scale the display's first monitor's, the window not laid out yet.
static gboolean held_frame(gpointer data) {
  (void)data;
  held_source = 0;
  WinSlot *o = &win_slots[0];
  if (window_shown || !o->want_frame || !o->area || !gtk_widget_get_realized(o->area)) return G_SOURCE_REMOVE;
  GdkDisplay *d = gdk_display_get_default();
  GListModel *ms = d ? gdk_display_get_monitors(d) : NULL;
  GdkMonitor *m = ms && g_list_model_get_n_items(ms) ? g_list_model_get_item(ms, 0) : NULL;
  double k = m ? gdk_monitor_get_scale(m) : 1;
  if (m) g_object_unref(m);
  int back = win_active;
  win_use(0);
  canvas_draw(o->area, held_w, held_h, k > 0 ? k : 1);
  win_put_back(back);
  return G_SOURCE_REMOVE;
}

// ---- the windows of one run (win_use, above) ----

// Window `wid` gone (closed by the person, or by the app: mb_host_windows' 3; its GtkWindow destroyed): its views taken
// off it, what it drew let go of (in the canvases' context), the app told between frames (MB_OUTSIDE_WINDOW; one the
// app closed itself it knows of already).
static gboolean win_closed_told(gpointer data) {
  if (outside_cb) outside_cb(MB_OUTSIDE_WINDOW, GPOINTER_TO_INT(data), -1);
  // (a run whose first was hidden as it closed, with no icon to put it away to, ends as the last window beside it
  // closes: none is left to be seen)
  int beside = 0;
  for (int k = 1; k < MB_WINS; k++)
    if (win_slots[k].win) beside = 1;
  if (first_hidden_bare && !beside && !gtk_widget_get_visible(win_slots[0].win)) exit(0);
  app_state();
  return G_SOURCE_REMOVE;
}

// How large each role's window last was as it closed (its default size, which GTK keeps as the person resizes it),
// for the next of the role (win_open): the run's, the most recent kept.
#define ROLES_KEPT 16
static struct {
  char role[64];
  int w, h;
  gint64 at;
} roles_kept[ROLES_KEPT];
static void role_keep(const WinSlot *o) {
  if (!o->role[0] || !o->win) return;
  int w = 0, h = 0;
  gtk_window_get_default_size(GTK_WINDOW(o->win), &w, &h);
  if (w <= 0 || h <= 0) return;
  int at = 0;
  for (int i = 0; i < ROLES_KEPT; i++) {
    if (!strcmp(roles_kept[i].role, o->role)) {
      at = i;
      break;
    }
    if (roles_kept[i].at < roles_kept[at].at) at = i;
  }
  snprintf(roles_kept[at].role, sizeof roles_kept[at].role, "%s", o->role);
  roles_kept[at].w = w, roles_kept[at].h = h;
  roles_kept[at].at = g_get_monotonic_time() | 1;
}
static void role_kept(const char *role, int *w, int *h) {
  for (int i = 0; i < ROLES_KEPT; i++)
    if (role[0] && roles_kept[i].at && !strcmp(roles_kept[i].role, role)) {
      *w = roles_kept[i].w, *h = roles_kept[i].h;
      return;
    }
}
static void win_closed(GtkWidget *w, gpointer data) {
  (void)w;
  int wid = GPOINTER_TO_INT(data);
  if (wid <= 0 || wid >= MB_WINS || !win_slots[wid].win) return;
  if (win_active == wid) win_use(0);
  mb_views_forget(wid);
  WinSlot *o = &win_slots[wid];
  role_keep(o);
  // (in the run's context: the first's canvas, or, the first hidden, another window's, else its own yet)
  GtkWidget *with = area_with_context(wid);
  if (!with && o->area && gtk_widget_get_realized(o->area) && gtk_gl_area_get_context(GTK_GL_AREA(o->area)))
    with = o->area;
  if (with) {
    gtk_gl_area_make_current(GTK_GL_AREA(with));
    mb_render_forget(wid);
  }
  g_free(o->ime_words);
  if (o->im) g_object_unref(o->im);
  memset(o, 0, sizeof *o);
  o->scale = 1;
  g_idle_add(win_closed_told, GINT_TO_POINTER(wid));
}

// A window of this run (@hostapi.window_open_id): its id, 0 where none. `what` a spec (a JSON object: role, title, w,
// h, minW, minH, inset, each left out as the first's), else the app's words for what it shows. As large as the first
// is now, its title the first's, its top row the app's as the first's, but for what the spec says; one of a role as
// large as the last of the role was as it closed (roles_kept: GTK 4 places no window itself, the desktop places it, so
// a second of a role is set where the desktop sets it, not down and to the right of the one before). Its first
// picture on the screen its first frame (canvas_snapshot, drawn in the snapshot of the window's first frame).
static int win_open(moonbit_string_t what) {
  WinSlot *first = &win_slots[0];
  // (the run's context made: the first's canvas realized, or, the first hidden, another window's)
  if (!first->win || !area_with_context(-1)) return 0;
  int wid = 0;
  for (int k = 1; k < MB_WINS; k++)
    if (!win_slots[k].win) {
      wid = k;
      break;
    }
  if (!wid) return 0;
  // (its spec, where `what` is one)
  char *u = what ? utf8(what) : NULL;
  jv spec;
  memset(&spec, 0, sizeof spec);
  const char *at = u;
  if (u && u[0] == '{' && !jparse(&at, &spec, 0)) {
    jv_free(&spec);
    memset(&spec, 0, sizeof spec);
  }
  const jv *inset_v = jget(&spec, "inset");
  int back = win_active;
  WinSlot *o = &win_slots[wid];
  memset(o, 0, sizeof *o);
  o->scale = first->scale;
  snprintf(o->role, sizeof o->role, "%s", jtext(&spec, "role"));
  o->min_w = jnum(&spec, "minW", 0) > 0 ? jnum(&spec, "minW", 0) : setup_min_w;
  o->min_h = jnum(&spec, "minH", 0) > 0 ? jnum(&spec, "minH", 0) : setup_min_h;
  o->inset = inset_v && (inset_v->kind == 't' || inset_v->kind == 'f') ? inset_v->kind == 't' : setup_inset;
  static int opened;
  o->opened = ++opened;
  o->win = gtk_window_new();
  win_use(wid);
  const char *title = jtext(&spec, "title");
  gtk_window_set_title(GTK_WINDOW(o->win), *title ? title : gtk_window_get_title(GTK_WINDOW(first->win)));
  int w = gtk_widget_get_width(first->win), h = gtk_widget_get_height(first->win);
  if (w <= 0) w = held_w;
  if (h <= 0) h = held_h;
  double spec_w = jnum(&spec, "w", 0), spec_h = jnum(&spec, "h", 0);
  if (spec_w > 0) w = (int)lround(spec_w);
  if (spec_h > 0) h = (int)lround(spec_h);
  role_kept(o->role, &w, &h);
  gtk_window_set_default_size(GTK_WINDOW(o->win), w, h);
  jv_free(&spec);
  g_free(u);
  if (life_app) gtk_window_set_application(GTK_WINDOW(o->win), life_app);
  g_signal_connect(o->win, "notify::is-active", G_CALLBACK(on_active), NULL);
  g_signal_connect(o->win, "notify::visible", G_CALLBACK(on_active), NULL);
  g_signal_connect(o->win, "destroy", G_CALLBACK(win_closed), GINT_TO_POINTER(wid));
  win_parts();
  drop_start();
  gtk_window_present(GTK_WINDOW(o->win));
  gtk_widget_grab_focus(o->area);
  schedule();
  win_put_back(back);
  return wid;
}

// The windows of this run (host_native.mbt's `windows`): 0 whether they open in it (yes, but in a window that is a run
// of its own, MBUI_WINDOW), 1 one opened, 2 one to the front, 3 one closed by the app, 4 the window in place now, 5 a
// window's title set to `what` (`wid` -1: the window in place's). 2 with `wid` 0 brings the first back (put away or
// hidden: bring_back).
static gboolean win_close_later(gpointer data) {
  int wid = GPOINTER_TO_INT(data);
  if (wid > 0 && wid < MB_WINS && win_slots[wid].win) gtk_window_destroy(GTK_WINDOW(win_slots[wid].win));
  return G_SOURCE_REMOVE;
}
int32_t mb_host_windows(int32_t op, int32_t wid, moonbit_string_t what) {
  GtkWidget *w = wid > 0 && wid < MB_WINS ? win_slots[wid].win : NULL;
  switch (op) {
    case 0: return !window_run();
    case 1: return win_open(what);
    case 2:
      if (wid == 0) {
        if (!win_slots[0].win) return 0;
        bring_back();
        return 1;
      }
      if (!w) return 0;
      gtk_window_unminimize(GTK_WINDOW(w));
      gtk_window_present(GTK_WINDOW(w));
      return 1;
    // (closed after the frame the app asked it in: never in the middle of drawing it)
    case 3:
      if (w) g_idle_add(win_close_later, GINT_TO_POINTER(wid));
      return 0;
    case 4: return win_active;
    case 5: {
      int target = wid < 0 ? win_active : wid;
      GtkWidget *t = target >= 0 && target < MB_WINS ? win_slots[target].win : NULL;
      if (!t) return 0;
      char *title = utf8(what);
      gtk_window_set_title(GTK_WINDOW(t), title);
      g_free(title);
      return 1;
    }
    default: return 0;
  }
}

double mb_host_now(void) { return mb_now_ms(); }

double mb_host_wall_ms(void) {
  struct timespec t;
  clock_gettime(CLOCK_REALTIME, &t);
  return t.tv_sec * 1000.0 + t.tv_nsec / 1e6;
}

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min)
int32_t mb_host_utc_offset_min(double at_ms) {
  time_t s = (time_t)(at_ms / 1000.0);
  struct tm local;
  if (!localtime_r(&s, &local)) return 0;
  return (int32_t)(local.tm_gmtoff / 60);
}

double mb_host_event_time(void) { return -1; }

// What a pointer's event came from (@hostapi.event_finger): not said (GTK hands touches as the pointer's here).
int32_t mb_host_event_finger(void) { return -1; }

// (how late the frame before reached the screen: not told here)
double mb_host_frame_late(void) { return 0; }

int32_t mb_host_platform(void) { return 5; }

// A frame asked for: of every window of the run where there are several, else the one.
void mb_host_request_frame(void) { schedule_all(); }

// A frame for what moves on by the clock that needs fewer (@hostapi.frames_paced): not paced here, the next drawn.
void mb_host_frames_paced(double hz) {
  (void)hz;
  mb_host_request_frame();
}

// (the loop waits no longer than it: run_loop)
void mb_host_wake_after(double ms) {
  double t = mb_now_ms() + ms;
  if (wake_at < 0 || t < wake_at) wake_at = t;
}

// (the frame as the app gave it, its groups' headers drawn out by the renderer as it takes it: groups.h)
void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  gl_current();  // (the frame may have opened a web view)
  mb_render_present(buf, count, r, g, b);
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text, int32_t a,
                     int32_t b) {
  int was = ws->ime_active;
  ws->ime_active = active != 0;
  ws->caret[0] = x;
  ws->caret[1] = y;
  ws->caret[2] = w;
  ws->caret[3] = h;
  // the field's words and its selection, in UTF-8's bytes, for the input method's surrounding text
  g_free(ws->ime_words);
  ws->ime_words = utf8(text);
  int32_t n = Moonbit_array_length(text);
  ws->ime_sel_a = ws->ime_sel_b = 0;
  const char *p = ws->ime_words;
  for (int32_t i = 0; i < n && *p; p = g_utf8_next_char(p)) {
    if (i < a) ws->ime_sel_a = (int)(g_utf8_next_char(p) - ws->ime_words);
    if (i < b) ws->ime_sel_b = (int)(g_utf8_next_char(p) - ws->ime_words);
    i += g_utf8_get_char(p) >= 0x10000 ? 2 : 1;
  }
  if (ws->ime_active && !was) {
    gtk_event_controller_key_set_im_context(GTK_EVENT_CONTROLLER_KEY(ws->keys), ws->im);
    if (gtk_widget_has_focus(ws->area)) gtk_im_context_focus_in(ws->im);
  } else if (!ws->ime_active && was) {
    gtk_im_context_reset(ws->im);
    gtk_im_context_focus_out(ws->im);
    gtk_event_controller_key_set_im_context(GTK_EVENT_CONTROLLER_KEY(ws->keys), NULL);
    ws->marked_len = 0;
  }
  ime_place();
}

// no floating text menu of the system's here (the field's own keys and shortcuts do what it would)
void mb_host_text_menu(int32_t shown, double x, double y, double w, double h, int32_t can) {
  (void)shown, (void)x, (void)y, (void)w, (void)h, (void)can;
}

// the app's own items of a floating text menu (@hostapi.text_menu_own): no such menu here
void mb_host_text_menu_own(moonbit_string_t words) { (void)words; }

// no menu bar of the app's here
void mb_host_edit_can(int32_t can) { (void)can; }

// whether the clipboard's words are the last secret this app copied, to be taken off (while the clipboard is the
// app's still: gdk_clipboard_is_local)
static int secret_on;

void mb_host_clipboard_set(moonbit_string_t s) {
  char *u = utf8(s);
  gdk_clipboard_set_text(gtk_widget_get_clipboard(ws->area), u);
  g_free(u);
  secret_on = 0;
}

// A secret on the clipboard (@hostapi.clipboard_set_secret): as any words here (no sensitive mark).
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  mb_host_clipboard_set(s);
  secret_on = clear_ms > 0;
}

// The last secret copied taken off (@hostapi.clipboard_secret_off), unless something else was copied since.
void mb_host_clipboard_secret_off(void) {
  GdkClipboard *cb = gtk_widget_get_clipboard(ws->area);
  if (secret_on && gdk_clipboard_is_local(cb)) gdk_clipboard_set_content(cb, NULL);
  secret_on = 0;
}

// A picture on the clipboard (@hostapi.clipboard_set_image): a PNG's, as a picture GTK offers in the formats other
// programs paste (image/png first); what is not a picture is put nowhere.
void mb_host_clipboard_image(moonbit_bytes_t data) {
  GBytes *b = g_bytes_new(data, Moonbit_array_length(data));
  GdkTexture *t = gdk_texture_new_from_bytes(b, NULL);
  g_bytes_unref(b);
  if (!t) return;
  gdk_clipboard_set_texture(gtk_widget_get_clipboard(ws->area), t);
  secret_on = 0;
  g_object_unref(t);
}

void mb_host_log(moonbit_string_t s) {
  char *u = utf8(s);
  fprintf(stdout, "%s\n", u);
  fflush(stdout);
  g_free(u);
}

// The app over another app done (@hostapi.over_done): it never is here.
void mb_host_over_done(int32_t open_app) { (void)open_app; }

// A URL handed to the system (@hostapi.open_url): the default browser or the app that takes it (GIO's, through the
// desktop portal where there is one); only http, https and mailto.
int32_t mb_host_open_url(moonbit_string_t s) {
  char *u = utf8(s);
  int ok = 0;
  if (!g_ascii_strncasecmp(u, "http://", 7) || !g_ascii_strncasecmp(u, "https://", 8) ||
      !g_ascii_strncasecmp(u, "mailto:", 7)) {
    fprintf(stdout, "%s\n", u);
    fflush(stdout);
    ok = g_app_info_launch_default_for_uri(u, NULL, NULL);
  }
  g_free(u);
  return ok;
}

// A page in a browser's tab over the app (@hostapi.open_tab): the default browser, as open_url.
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@hostapi.hold_words): nothing here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {
  (void)channel, (void)title, (void)body;
}

// The word around an offset (@hostapi.word_at): none from the host here (the app's own rule, words.mbt).
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  (void)text, (void)off;
  return -1;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): no run here is yet.
int32_t mb_host_own_clock(void) { return 0; }

// the system's animations off (GNOME's "Reduce animation" sets GTK's gtk-enable-animations)
int32_t mb_host_reduce_motion(void) {
  gboolean on = TRUE;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-enable-animations", &on, NULL);
  return on ? 0 : 1;
}

// What the host did for the app is done (host_native.mbt's set_outside): an image decoded (linux_image.c), the
// clipboard read (linux_device.h); told as each frame begins, on this thread.
int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}

// How many of the app's asks are not answered yet (host_native.mbt's frame_awaiting): nothing here waits on it yet.
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) { (void)awaiting, (void)what; }

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  return b ? atoi(b) : 0;
}

void mb_host_exit(int32_t code) { exit(code); }

void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

void mb_host_set_app_state(void (*f)(int32_t)) {
  state_cb = f;
  app_state();
}

// Whether the system is set to dark (@hostapi.system_dark): the desktop portal's color-scheme, else GTK's own
// preference.
int32_t mb_host_system_dark(void) {
  if (portal_dark >= 0) return portal_dark;
  gboolean dark = FALSE;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-application-prefer-dark-theme", &dark, NULL);
  return dark ? 1 : 0;
}

void mb_host_set_window_zoom(double zoom) { (void)zoom; }
void mb_host_set_window_key(int32_t (*f)(int32_t, int32_t)) { (void)f; }

// Words as the app sizes them (@hostapi.font_scale): the system's text scale (GNOME's "Large Text", its scaling
// factor), as Xft's DPI over 96.
double mb_host_font_scale(void) {
  int dpi = 0;
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_get(s, "gtk-xft-dpi", &dpi, NULL);
  return dpi > 0 ? dpi / 1024.0 / 96.0 : 1.0;
}

// What the app was started to be used with (@hostapi.native_pointing): keyboard and mouse.
int32_t mb_host_native_pointing(void) { return 2; }
// Whether a keyboard is at hand (@hostapi.keyboard): a computer's, always.
int32_t mb_host_keyboard(void) { return 1; }

// Sharing (@hostapi.share, @hostapi.shared_in): no share sheet on Linux; nothing comes in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)text, (void)name, (void)mime, (void)data;
  return 0;
}
moonbit_string_t mb_host_shared_in(void) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_shared_in_file(int32_t i) {
  (void)i;
  return moonbit_make_bytes(0, 0);
}

// A package for the system's installer (@hostapi.install_package): none here, said on the system channel (system.mbt):
// its name, escaped for JSON.
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  (void)data;
  char *u = utf8(name);
  GString *out = g_string_new("{\"install\":{\"name\":\"");
  json_put(out, u);
  g_string_append(out, "\",\"error\":\"unsupported\"}}");
  mb_post("system", out->str, out->len, NULL, 0);
  g_string_free(out, TRUE);
  g_free(u);
}


// Turned sideways for a film (@hostapi.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }
// Let turn as held (@hostapi.set_turnable): a window does not turn, and is not held upright.
int32_t mb_host_set_turnable(int32_t on) { (void)on; return 0; }

// The performance record (@hostapi.perf_state): none kept here (iOS keeps one, ios_app.m).
int32_t mb_host_perf_state(void) { return -1; }
void mb_host_set_perf(int32_t on) { (void)on; }
void mb_host_perf_line(moonbit_string_t line) { (void)line; }
moonbit_string_t mb_host_perf_where(void) { return moonbit_make_string_raw(0); }
int32_t mb_host_perf_open(int32_t go) { (void)go; return 0; }

// A file shown chosen in its folder in the desktop's file manager (@hostapi.reveal_file: 在文件夹中显示), or whether
// that can be done here (go 0): it can. Asked of the file manager over D-Bus (org.freedesktop.FileManager1's ShowItems,
// which Nautilus, Dolphin, Nemo and others serve); where none answers, its folder opened as any folder is. Only a file
// that is there.
int32_t mb_host_reveal_file(moonbit_string_t s, int32_t go) {
  if (!go) return 1;
  char *path = utf8(s);
  int ok = 0;
  if (path[0] && g_file_test(path, G_FILE_TEST_EXISTS)) {
    fprintf(stdout, "reveal-file: %s\n", path);
    fflush(stdout);
    char *uri = g_filename_to_uri(path, NULL, NULL);
    GDBusConnection *bus = uri ? g_bus_get_sync(G_BUS_TYPE_SESSION, NULL, NULL) : NULL;
    if (bus) {
      const char *items[] = {uri, NULL};
      GVariant *r = g_dbus_connection_call_sync(bus, "org.freedesktop.FileManager1", "/org/freedesktop/FileManager1",
                                                "org.freedesktop.FileManager1", "ShowItems",
                                                g_variant_new("(^ass)", items, ""), NULL, G_DBUS_CALL_FLAGS_NONE, 2000,
                                                NULL, NULL);
      if (r) {
        ok = 1;
        g_variant_unref(r);
      }
      g_object_unref(bus);
    }
    if (!ok) {
      char *dir = g_path_get_dirname(path);
      char *dir_uri = g_filename_to_uri(dir, NULL, NULL);
      ok = dir_uri && g_app_info_launch_default_for_uri(dir_uri, NULL, NULL);
      g_free(dir_uri);
      g_free(dir);
    }
    g_free(uri);
  }
  g_free(path);
  return ok;
}
double mb_host_perf_size(void) { return 0; }
moonbit_bytes_t mb_host_perf_read(void) { return moonbit_make_bytes(0, 0); }

// The app drawn dark (@hostapi.set_dark): GTK's own parts (the title bar) drawn as dark.
void mb_host_set_dark(int32_t dark) {
  GtkSettings *s = gtk_settings_get_default();
  if (s) g_object_set(s, "gtk-application-prefer-dark-theme", dark ? TRUE : FALSE, NULL);
}

// The canvas's GL context made anew (@hostapi.drive 10), as a context is lost: the canvas taken out of the window and
// put back, between frames (not inside the render that asked), unrealized with its context and realized with a new
// one (on_realize: mb_render_setup, what the old one held made again); `context_new` once it is (as GTK realizes it
// again, which comes after it is put back: its next layout's)
static gboolean context_again(gpointer data) {
  (void)data;
  GtkWidget *overlay = gtk_widget_get_parent(ws->area);
  g_object_ref(ws->area);
  gtk_overlay_remove_overlay(GTK_OVERLAY(overlay), ws->area);
  gtk_overlay_add_overlay(GTK_OVERLAY(overlay), ws->area);
  gtk_overlay_set_measure_overlay(GTK_OVERLAY(overlay), ws->area, TRUE);
  g_object_unref(ws->area);
  gtk_widget_grab_focus(ws->area);
  schedule();
  return G_SOURCE_REMOVE;
}

// Scripted runs' input given to the host (src/ui/drive.mbt): the window's picture saved (4), a notification clicked
// (6) or looked for (7) by its words (linux_life.h), the window resized to "<w>x<h>" points (8), the runner's directory
// watched (9), the canvas's context made anew (10), and whether it has been since (11), files let go on the window
// (13: drop_drive); the rest is sent to the app itself.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  if (kind == 9) return mb_done_watch(text);
  if (kind == 10) {
    context_new = 0;
    context_asked = 1;
    g_idle_add(context_again, NULL);
    return 1;
  }
  if (kind == 11) return context_new;
  char *u = utf8(text);
  int done = 0;
  if (kind == 6 || kind == 7) {
    done = notice_drive(kind == 6, u);
  } else if (kind == 13) {
    done = drop_drive(u);
  } else if (kind == 4) {
    int ok = mb_render_snapshot(u);
    fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
    fflush(stdout);
    done = 1;
  } else if (kind == 8) {
    double cw = 0, ch = 0;
    if (sscanf(u, "%lfx%lf", &cw, &ch) == 2 && cw > 0 && ch > 0) {
      gtk_window_set_default_size(GTK_WINDOW(ws->win), (int)lround(cw), (int)lround(ch));
      fprintf(stdout, "RESIZED %.0fx%.0f\n", cw, ch);
      fflush(stdout);
      schedule();
      done = 1;
    }
  }
  g_free(u);
  return done;
}

void mb_host_window_hold(void) { window_held = 1; }

void mb_host_window_show(void) {
  if (window_held && !window_shown) window_to_show = 1;
}

// The window as the app wants it, asked before `run` (@hostapi.window_setup): with `inset`, no title bar of the
// system's, the app's top row is it, its buttons the app's.
void mb_host_window_setup(double min_w, double min_h, double w, double h, int32_t inset) {
  setup_inset = inset != 0;
  setup_min_w = min_w;
  setup_min_h = min_h;
  win_slots[0].inset = setup_inset;
  win_slots[0].min_w = min_w;
  win_slots[0].min_h = min_h;
  setup_w = w;
  setup_h = h;
}

// Whether the window in place's buttons are in the app's top row now: an inset window, not full screen.
int32_t mb_host_window_inset(void) { return ws->inset && !(ws->win && gtk_window_is_fullscreen(GTK_WINDOW(ws->win))); }

// A window filling the screen (@hostapi.full_screen).
int32_t mb_host_full_screen(void) { return ws->win && gtk_window_is_fullscreen(GTK_WINDOW(ws->win)) ? 1 : 0; }
void mb_host_set_full_screen(int32_t on) {
  if (!ws->win) return;
  if (on) gtk_window_fullscreen(GTK_WINDOW(ws->win));
  else gtk_window_unfullscreen(GTK_WINDOW(ws->win));
}

// The app's own top row draws Linux's buttons (window_keys_own): nothing of the system's to move.
void mb_host_window_buttons_down(double by, double ms) { (void)by; (void)ms; }

// How round the system draws the window's corners (@hostapi.window_corner): its content's are square under the title
// bar.
double mb_host_window_corner(void) { return 0; }
double mb_host_window_corner_at(int k) { (void)k; return 0; }

void mb_host_window_act(int32_t what);

// The press under way moves the window (the app's top row), as the title bar's would; the second press of a double
// click there (the desktop's own time and distance for one), what the title bar's double click does: maximized, or
// back as it was.
void mb_host_window_drag(void) {
  GdkSurface *s = ws->win ? gtk_native_get_surface(GTK_NATIVE(ws->win)) : NULL;
  if (!s || !GDK_IS_TOPLEVEL(s) || !ws->press_device) return;
  ws->left_down = 0;
  int dt = 400, dd = 5;
  GtkSettings *gs = gtk_settings_get_default();
  if (gs) g_object_get(gs, "gtk-double-click-time", &dt, "gtk-double-click-distance", &dd, NULL);
  if (ws->drag_time && ws->press_time - ws->drag_time <= (guint32)dt && fabs(ws->press_x - ws->drag_x) <= dd && fabs(ws->press_y - ws->drag_y) <= dd) {
    ws->drag_time = 0;
    mb_host_window_act(2);
    return;
  }
  ws->drag_time = ws->press_time, ws->drag_x = ws->press_x, ws->drag_y = ws->press_y;
  gdk_toplevel_begin_move(GDK_TOPLEVEL(s), ws->press_device, ws->press_button, ws->press_x, ws->press_y, ws->press_time);
}

// The window's own buttons, the app's in an inset window (@hostapi.window_act, window_zoomed): minimized, maximized or
// back as it was, closed as the system's close button closes it (put away to its icon among the desktop's:
// linux_life.h); no Snap Layouts here (window_snap, window_snap_state: Windows').
void mb_host_window_act(int32_t what) {
  if (!ws->win) return;
  if (what == 1) gtk_window_minimize(GTK_WINDOW(ws->win));
  else if (what == 2 && gtk_window_is_maximized(GTK_WINDOW(ws->win))) gtk_window_unmaximize(GTK_WINDOW(ws->win));
  else if (what == 2) gtk_window_maximize(GTK_WINDOW(ws->win));
  else if (what == 3) gtk_window_close(GTK_WINDOW(ws->win));
}
int32_t mb_host_window_zoomed(void) { return ws->win && gtk_window_is_maximized(GTK_WINDOW(ws->win)) ? 1 : 0; }
void mb_host_window_snap(double x, double y, double w, double h) { (void)x, (void)y, (void)w, (void)h; }
int32_t mb_host_window_snap_state(void) { return 0; }

// (the number on the app's icon: linux_life.h)

// The keys held now (@hostapi.mods_held), as a key's are told.
int32_t mb_host_mods_held(void) {
  GdkDisplay *d = gdk_display_get_default();
  GdkSeat *seat = d ? gdk_display_get_default_seat(d) : NULL;
  GdkDevice *kb = seat ? gdk_seat_get_keyboard(seat) : NULL;
  return kb ? mods_of(gdk_device_get_modifier_state(kb)) : 0;
}

// The pointer held by the window and game controllers (@hostapi.set_pointer_lock, gamepads): none here.
void mb_host_pointer_lock(int32_t on) { (void)on; }
int32_t mb_host_pointer_locked(void) { return 0; }
void mb_host_pointer_delta(double *out) { out[0] = 0; out[1] = 0; }
int32_t mb_host_gamepads(double *out) { (void)out; return 0; }

// The pointer's shape (@hostapi.set_cursor): CSS's names, as GTK takes them.
void mb_host_set_cursor(int32_t kind) {
  static int now = -1;
  if (!ws->area || kind == now) return;
  now = kind;
  static const char *names[] = {"default", "pointer", "text", "ew-resize", "ns-resize", "move", "grabbing",
                                "crosshair", "not-allowed", "nwse-resize", "nesw-resize"};
  int count = (int)(sizeof names / sizeof names[0]);
  gtk_widget_set_cursor_from_name(ws->area, names[kind >= 0 && kind < count ? kind : 0]);
}

moonbit_string_t mb_host_env(moonbit_string_t name) {
  char *k = utf8(name);
  moonbit_string_t out = mstr(getenv(k));
  g_free(k);
  return out;
}

int32_t mb_host_reduce_transparency(void) { return 0; }
int32_t mb_host_increase_contrast(void) { return 0; }
// (no heat of the machine an app is told of here: never slowed)
int32_t mb_host_thermal_throttled(void) { return 0; }

double mb_host_gpu_ms(void) { return -1; }

// what the process keeps in memory (its resident pages)
// The CPU's time the whole process has had, every thread's (@hostapi.cpu_ms: MBUI_PROBE's share of a CPU), in ms.
double mb_host_cpu_ms(void) {
  struct rusage u;
  if (getrusage(RUSAGE_SELF, &u) != 0) return -1;
  return (u.ru_utime.tv_sec + u.ru_stime.tv_sec) * 1000.0 + (u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1000.0;
}

// The CPU time of the calling thread (@hostapi.thread_cpu_ms), in ms (-1: unsupported).
double mb_host_thread_cpu_ms(void) {
  struct timespec ts;
  if (clock_gettime(CLOCK_THREAD_CPUTIME_ID, &ts) == 0)
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1e6;
  return -1.0;
}

// The display's refresh rate in Hz (@hostapi.display_hz; 0: unknown).
double mb_host_display_hz(void) { return 0.0; }

double mb_host_mem_bytes(void) {
  long pages = 0, resident = 0;
  FILE *f = fopen("/proc/self/statm", "r");
  if (!f) return 0;
  int n = fscanf(f, "%ld %ld", &pages, &resident);
  fclose(f);
  return n == 2 ? (double)resident * sysconf(_SC_PAGESIZE) : 0;
}

// Files picked (pick.mbt): GTK's file dialog (the desktop portal's chooser where there is one), more than one; pictures
// for the photo picker, anything for the file picker, no camera. Each read whole as the dialog answers (no file held
// by the host yet), told then on the main loop, between frames (picks_wake: never left for a frame to take as it
// begins). MBUI_PICK_FILES="<path>|<path>…" answers every ask with those files, no dialog (scripted runs; host_contract.sh
// linux picked), told so too.
typedef struct {
  int state;  // 0 asking, 1 answered, -1 called off or failed
  int told;
  GPtrArray *names;  // char *
  GPtrArray *bytes;  // GBytes *
  GPtrArray *dropped;  // GFile *: a drop's (drop_pick), read only once the app asks how it goes (mb_host_pick_state)
} pick;
static pick *picks;
static int npicks = 1;  // ids from 1

static pick *pick_of(int32_t id) { return id > 0 && id < npicks ? &picks[id] : NULL; }
static void drop_read_start(int32_t id, GPtrArray *files);  // a drop's files read (below)

// The picks answered since the app was last told, told now, between frames (pick_tell): what was picked taken into
// what reads it as it comes (ui's outside_take), a frame asked for only where something reads it.
static int picks_telling;
static gboolean picks_idle(gpointer data) {
  (void)data;
  picks_telling = 0;
  if (outside_cb) pick_tell(outside_cb);
  else schedule();
  return G_SOURCE_REMOVE;
}
static void picks_wake(void) {
  if (picks_telling) return;
  picks_telling = 1;
  g_idle_add_full(G_PRIORITY_HIGH_IDLE, picks_idle, NULL, NULL);
}

static void pick_done(GObject *src, GAsyncResult *res, gpointer data) {
  pick *k = pick_of(GPOINTER_TO_INT(data));
  GListModel *files = gtk_file_dialog_open_multiple_finish(GTK_FILE_DIALOG(src), res, NULL);
  if (k && k->state == 0) {
    k->state = files ? 1 : -1;
    for (guint i = 0; files && i < g_list_model_get_n_items(files); i++) {
      GFile *f = g_list_model_get_item(files, i);
      char *data_ = NULL;
      gsize n = 0;
      if (g_file_load_contents(f, NULL, &data_, &n, NULL, NULL)) {
        g_ptr_array_add(k->names, g_file_get_basename(f));
        g_ptr_array_add(k->bytes, g_bytes_new_take(data_, n));
      }
      g_object_unref(f);
    }
  }
  if (files) g_object_unref(files);
  g_object_unref(src);
  picks_wake();
}

int32_t mb_host_pick_start(int32_t kind) {
  int what = kind & 15;
  if (!ws->win || (what != 1 && what != 2)) return 0;
  picks = realloc(picks, sizeof(pick) * (size_t)(npicks + 1));
  int id = npicks++;
  picks[id] = (pick){0, 0, g_ptr_array_new_with_free_func(g_free),
                     g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref)};
  const char *canned = getenv("MBUI_PICK_FILES");
  if (canned && *canned) {
    pick *k = &picks[id];
    char **paths = g_strsplit(canned, "|", -1);
    for (int i = 0; paths[i]; i++) {
      char *data_ = NULL;
      gsize n = 0;
      if (*paths[i] && g_file_get_contents(paths[i], &data_, &n, NULL)) {
        g_ptr_array_add(k->names, g_path_get_basename(paths[i]));
        g_ptr_array_add(k->bytes, g_bytes_new_take(data_, n));
      }
    }
    g_strfreev(paths);
    k->state = k->names->len > 0 ? 1 : -1;
    picks_wake();
    return id;
  }
  GtkFileDialog *d = gtk_file_dialog_new();
  if (what == 1) {
    GtkFileFilter *f = gtk_file_filter_new();
    gtk_file_filter_add_mime_type(f, "image/*");
    GListStore *filters = g_list_store_new(GTK_TYPE_FILE_FILTER);
    g_list_store_append(filters, f);
    gtk_file_dialog_set_filters(d, G_LIST_MODEL(filters));
    gtk_file_dialog_set_default_filter(d, f);
    g_object_unref(filters);
    g_object_unref(f);
  }
  gtk_file_dialog_open_multiple(d, GTK_WINDOW(ws->win), NULL, pick_done, GINT_TO_POINTER(id));
  return id;
}

// The picks answered since the app was last told, told it (picks_idle).
static void pick_tell(mb_outside_fn tell) {
  for (int i = 1; i < npicks; i++)
    if (picks[i].state != 0 && !picks[i].told) {
      picks[i].told = 1;
      if (tell) tell(MB_OUTSIDE_PICK, i, picks[i].state);
    }
}

int32_t mb_host_pick_state(int32_t id) {
  pick *k = pick_of(id);
  if (!k) return -1;
  // (a drop's files, asked for: read from now, drop_pick)
  if (k->dropped) drop_read_start(id, g_steal_pointer(&k->dropped));
  return k->state;
}
int32_t mb_host_pick_count(int32_t id) {
  pick *k = pick_of(id);
  return k && k->state == 1 ? (int32_t)k->names->len : 0;
}
moonbit_string_t mb_host_pick_name(int32_t id, int32_t i) {
  pick *k = pick_of(id);
  return k && i >= 0 && i < mb_host_pick_count(id) ? mstr(g_ptr_array_index(k->names, i)) : moonbit_make_string_raw(0);
}
moonbit_bytes_t mb_host_pick_bytes(int32_t id, int32_t i) {
  pick *k = pick_of(id);
  if (!k || i < 0 || i >= mb_host_pick_count(id)) return moonbit_make_bytes(0, 0);
  gsize n = 0;
  const void *p = g_bytes_get_data(g_ptr_array_index(k->bytes, i), &n);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n) memcpy(b, p, n);
  return b;
}
// (every one read whole: none held)
moonbit_string_t mb_host_pick_info(int32_t id, int32_t i) {
  (void)id, (void)i;
  return moonbit_make_string_raw(0);
}
void mb_host_pick_end(int32_t id) {
  pick *k = pick_of(id);
  if (!k) return;
  g_clear_pointer(&k->dropped, g_ptr_array_unref);
  g_ptr_array_set_size(k->names, 0);
  g_ptr_array_set_size(k->bytes, 0);
  k->state = -1;
  k->told = 1;
}

// ---- let go on the window ----

// Files dragged in from outside (a file manager) and let go on the window (ui/drop.mbt), as macOS's MBView takes them:
// where they are held, posted on `mbui.drop` as they move ({"type":"over","x","y"}, {"type":"left"}), then let go, with
// where each is and the pick their reading is, read once the app takes them as files ({"type":"drop","x","y","pick",
// "paths":[{"path","dir","size"}]}: a field, or a chat as this station's files, takes them by their paths, unread).
// Only files of this machine's are taken (a browser's link comes as a list of files too, of its own scheme: none of
// them, so nothing let go, as macOS takes file URLs alone). Words dragged in (another app's text) are said only as
// they are let go, with what they say ({"type":"words","x","y","text"}). Either let go here, the window comes to the
// front with the keys, as a click on it would give them. GTK's drop target on the canvas, in its coordinates (points);
// a scripted run's drop (MBUI_DRIVE `drop`: mb_host_drive 13) goes the same way from the files it names.

static void drop_post(const char *json, size_t n) { mb_post("mbui.drop", json, n, NULL, 0); }

// A drop's files read (a thread's, walked into where they were let go: a folder's by their way down from it, "照片/2026/a.jpg",
// each folder itself named with a "/" at its end and no bytes), then given to its pick on the main loop.
typedef struct {
  int id;
  GPtrArray *files;  // GFile *
  GPtrArray *names, *bytes;
} drop_read;

static void drop_read_one(drop_read *r, GFile *f, const char *name, int top, int depth) {
  GFileInfo *info = g_file_query_info(f, G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
                                      top ? G_FILE_QUERY_INFO_NONE : G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, NULL, NULL);
  if (!info) return;
  GFileType type = g_file_info_get_file_type(info);
  if (type == G_FILE_TYPE_SYMBOLIC_LINK) {
    // (a link in a folder: the file it names read, a folder it names not walked into)
    g_object_unref(info);
    info = g_file_query_info(f, G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
                             G_FILE_QUERY_INFO_NONE, NULL, NULL);
    if (!info) return;
    type = g_file_info_get_file_type(info);
    if (type == G_FILE_TYPE_DIRECTORY) type = G_FILE_TYPE_UNKNOWN;
  }
  goffset size = g_file_info_get_size(info);
  g_object_unref(info);
  if (type == G_FILE_TYPE_DIRECTORY) {
    g_ptr_array_add(r->names, g_strconcat(name, "/", NULL));
    g_ptr_array_add(r->bytes, g_bytes_new(NULL, 0));
    GFileEnumerator *e = depth < 64 ? g_file_enumerate_children(f, G_FILE_ATTRIBUTE_STANDARD_NAME,
                                                                G_FILE_QUERY_INFO_NOFOLLOW_SYMLINKS, NULL, NULL)
                                    : NULL;
    GFileInfo *c;
    while (e && (c = g_file_enumerator_next_file(e, NULL, NULL))) {
      GFile *child = g_file_get_child(f, g_file_info_get_name(c));
      char *child_name = g_strconcat(name, "/", g_file_info_get_name(c), NULL);
      drop_read_one(r, child, child_name, 0, depth + 1);
      g_free(child_name);
      g_object_unref(child);
      g_object_unref(c);
    }
    if (e) g_object_unref(e);
    return;
  }
  if (type != G_FILE_TYPE_REGULAR || size > ((goffset)1 << 30)) return;
  char *data = NULL;
  gsize n = 0;
  if (!g_file_load_contents(f, NULL, &data, &n, NULL, NULL)) return;
  g_ptr_array_add(r->names, g_strdup(name));
  g_ptr_array_add(r->bytes, g_bytes_new_take(data, n));
}

static gboolean drop_read_done(gpointer data) {
  drop_read *r = data;
  pick *k = pick_of(r->id);
  // (a pick let go meanwhile, mb_host_pick_end: what was read let go too)
  if (k && k->state == 0) {
    g_ptr_array_extend_and_steal(k->names, g_steal_pointer(&r->names));
    g_ptr_array_extend_and_steal(k->bytes, g_steal_pointer(&r->bytes));
    k->state = k->names->len > 0 ? 1 : -1;
    picks_wake();
  }
  if (r->names) g_ptr_array_unref(r->names);
  if (r->bytes) g_ptr_array_unref(r->bytes);
  g_ptr_array_unref(r->files);
  g_free(r);
  return G_SOURCE_REMOVE;
}

static gpointer drop_read_run(gpointer data) {
  drop_read *r = data;
  for (guint i = 0; i < r->files->len; i++) {
    GFile *f = g_ptr_array_index(r->files, i);
    char *name = g_file_get_basename(f);
    drop_read_one(r, f, name ? name : "file", 1, 0);
    g_free(name);
  }
  g_idle_add_full(G_PRIORITY_HIGH_IDLE, drop_read_done, r, NULL);
  return NULL;
}

static void drop_read_start(int32_t id, GPtrArray *files) {
  drop_read *r = g_new0(drop_read, 1);
  r->id = id;
  r->files = files;
  r->names = g_ptr_array_new_with_free_func(g_free);
  r->bytes = g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref);
  g_thread_unref(g_thread_new("mbui-drop", drop_read_run, r));
}

// A pick of the files let go (GFile *, its own refs), read once the app asks how it goes
static int32_t drop_pick(GPtrArray *files) {
  picks = realloc(picks, sizeof(pick) * (size_t)(npicks + 1));
  int id = npicks++;
  picks[id] = (pick){0, 0, g_ptr_array_new_with_free_func(g_free),
                     g_ptr_array_new_with_free_func((GDestroyNotify)g_bytes_unref), files};
  return id;
}

// a drop's end with nothing let go, said of window `wid`
static void drop_left(int wid) {
  char b[48];
  int n = snprintf(b, sizeof b, "{\"type\":\"left\",\"wid\":%d}", wid);
  drop_post(b, (size_t)n);
}

// window `wid` brought to the front, its canvas given the keys (the first where it has closed meanwhile)
static void drop_front(int wid) {
  WinSlot *o = &win_slots[wid >= 0 && wid < MB_WINS && win_slots[wid].win ? wid : 0];
  if (o->win) gtk_window_present(GTK_WINDOW(o->win));
  if (o->area) gtk_widget_grab_focus(o->area);
}

// files let go at (x, y) of window `wid`'s canvas: where each is said, their pick made, that window brought to the front
static void drop_files_at(int wid, GPtrArray *files, double x, double y) {
  if (!files->len) {
    g_ptr_array_unref(files);
    drop_left(wid);
    return;
  }
  GString *paths = g_string_new("");
  for (guint i = 0; i < files->len; i++) {
    GFile *f = g_ptr_array_index(files, i);
    char *path = g_file_get_path(f);
    if (!path) continue;
    GFileInfo *info = g_file_query_info(f, G_FILE_ATTRIBUTE_STANDARD_TYPE "," G_FILE_ATTRIBUTE_STANDARD_SIZE,
                                        G_FILE_QUERY_INFO_NONE, NULL, NULL);
    int dir = info && g_file_info_get_file_type(info) == G_FILE_TYPE_DIRECTORY;
    goffset size = info && !dir ? g_file_info_get_size(info) : 0;
    if (info) g_object_unref(info);
    g_string_append(paths, paths->len ? ",{\"path\":\"" : "{\"path\":\"");
    json_put(paths, path);
    g_string_append_printf(paths, "\",\"dir\":%s,\"size\":%" G_GINT64_FORMAT "}", dir ? "true" : "false", (gint64)size);
    g_free(path);
  }
  int id = drop_pick(files);
  GString *m = g_string_new("");
  g_string_printf(m, "{\"type\":\"drop\",\"x\":%.1f,\"y\":%.1f,\"pick\":%d,\"paths\":[%s],\"wid\":%d}", x, y, id,
                  paths->str, wid);
  drop_post(m->str, m->len);
  g_string_free(m, TRUE);
  g_string_free(paths, TRUE);
  drop_front(wid);
}

static int drag_has_files(GtkDropTarget *t) {
  GdkDrop *d = gtk_drop_target_get_current_drop(t);
  return d && gdk_content_formats_contain_gtype(gdk_drop_get_formats(d), GDK_TYPE_FILE_LIST);
}

// (each window's target its own: data, the window's number, said with what it posts)
static GdkDragAction on_drag_over(GtkDropTarget *t, double x, double y, gpointer data) {
  // (words: nothing said till they are let go, no files held over the window)
  if (!drag_has_files(t)) return GDK_ACTION_COPY;
  char b[128];
  int n = snprintf(b, sizeof b, "{\"type\":\"over\",\"x\":%.1f,\"y\":%.1f,\"wid\":%d}", x, y, GPOINTER_TO_INT(data));
  drop_post(b, (size_t)n);
  return GDK_ACTION_COPY;
}

static void on_drag_left(GtkDropTarget *t, gpointer data) {
  if (drag_has_files(t)) drop_left(GPOINTER_TO_INT(data));
}

static gboolean on_dropped(GtkDropTarget *t, const GValue *v, double x, double y, gpointer data) {
  (void)t;
  int wid = GPOINTER_TO_INT(data);
  if (G_VALUE_HOLDS(v, GDK_TYPE_FILE_LIST)) {
    GPtrArray *files = g_ptr_array_new_with_free_func(g_object_unref);
    for (GSList *l = gdk_file_list_get_files(g_value_get_boxed(v)); l; l = l->next)
      if (g_file_is_native(l->data)) g_ptr_array_add(files, g_object_ref(l->data));
    drop_files_at(wid, files, x, y);
    return TRUE;
  }
  const char *words = G_VALUE_HOLDS_STRING(v) ? g_value_get_string(v) : NULL;
  if (!words || !*words) return FALSE;
  GString *m = g_string_new("");
  g_string_printf(m, "{\"type\":\"words\",\"x\":%.1f,\"y\":%.1f,\"wid\":%d,\"text\":\"", x, y, wid);
  json_put(m, words);
  g_string_append(m, "\"}");
  drop_post(m->str, m->len);
  g_string_free(m, TRUE);
  drop_front(wid);
  return TRUE;
}

// the canvas of the window in place takes what is let go on it: files first, else words
static void drop_start(void) {
  gpointer wid = GINT_TO_POINTER(win_active);
  GtkDropTarget *t = gtk_drop_target_new(G_TYPE_INVALID, GDK_ACTION_COPY);
  GType types[2] = {GDK_TYPE_FILE_LIST, G_TYPE_STRING};
  gtk_drop_target_set_gtypes(t, types, 2);
  g_signal_connect(t, "enter", G_CALLBACK(on_drag_over), wid);
  g_signal_connect(t, "motion", G_CALLBACK(on_drag_over), wid);
  g_signal_connect(t, "leave", G_CALLBACK(on_drag_left), wid);
  g_signal_connect(t, "drop", G_CALLBACK(on_dropped), wid);
  gtk_widget_add_controller(ws->area, GTK_EVENT_CONTROLLER(t));
}

// A scripted run's drop (mb_host_drive 13): "<x> <y> <path>|<path>…", the files let go there as a file manager's are.
static int drop_drive(const char *text) {
  double x = 0, y = 0;
  int at = 0;
  if (sscanf(text, "%lf %lf %n", &x, &y, &at) != 2 || !at) return 0;
  GPtrArray *files = g_ptr_array_new_with_free_func(g_object_unref);
  char **paths = g_strsplit(text + at, "|", -1);
  for (int i = 0; paths[i]; i++)
    if (*paths[i]) g_ptr_array_add(files, g_file_new_for_path(paths[i]));
  g_strfreev(paths);
  drop_files_at(win_active, files, x, y);
  return 1;
}

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) {
  (void)id;
  return -1;
}
moonbit_string_t mb_host_gallery_read_rows(int32_t id) {
  (void)id;
  return moonbit_make_string_raw(0);
}
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) {
  (void)src;
  return 0;
}

// Marks drawn onto an image (marks.mbt): none on this host yet.
int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) {
  (void)image, (void)marks;
  return 0;
}
int32_t mb_host_marks_state(int32_t id) {
  (void)id;
  return -1;
}
moonbit_bytes_t mb_host_marks_png(int32_t id) {
  (void)id;
  return moonbit_make_bytes(0, 0);
}

// Text in a legacy encoding (charset.mbt): iconv's, by IANA's names (a byte with no mapping: U+FFFD).
int32_t mb_host_charset_known(moonbit_string_t charset) {
  char *c = utf8(charset);
  GIConv cd = g_iconv_open("UTF-8", c);
  g_free(c);
  if (cd == (GIConv)-1) return 0;
  g_iconv_close(cd);
  return 1;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  char *c = utf8(charset);
  gsize n = 0;
  char *u = g_convert_with_fallback((const char *)data, Moonbit_array_length(data), "UTF-8", c, "\xef\xbf\xbd", NULL,
                                    &n, NULL);
  g_free(c);
  moonbit_string_t s = mstr(u ? u : "");
  g_free(u);
  return s;
}

// ---------------------------------------------------------------------------
// Files kept (keep.mbt) and saved (save_file): into the user's Downloads folder (XDG's; MBUI_DOWNLOADS_DIR instead,
// for scripted runs), either way (no save dialog yet); a name taken gets " (2)", " (3)"… before its extension.

static char *keep_dir(void) {
  const char *over = getenv("MBUI_DOWNLOADS_DIR");
  const char *d = over && *over ? over : g_get_user_special_dir(G_USER_DIRECTORY_DOWNLOAD);
  char *dir = d ? g_strdup(d) : g_build_filename(g_get_home_dir(), "Downloads", NULL);
  g_mkdir_with_parents(dir, 0755);
  return dir;
}

// the app's name for a file made safe for a folder (no separator, never empty, ".", "..")
static char *keep_safe(moonbit_string_t name) {
  char *n = utf8(name);
  for (char *c = n; *c; c++)
    if (*c == '/' || (unsigned char)*c < 32) *c = '_';
  if (!*n || !strcmp(n, ".") || !strcmp(n, "..")) {
    g_free(n);
    n = g_strdup("file");
  }
  return n;
}

// the i-th name tried in `dir` for `n`: n, then "base (2).ext"…
static char *keep_name(const char *dir, const char *n, int i) {
  if (i == 1) return g_build_filename(dir, n, NULL);
  const char *dot = strrchr(n, '.');
  if (!dot || dot == n) dot = n + strlen(n);
  char *name = g_strdup_printf("%.*s (%d)%s", (int)(dot - n), n, i, dot);
  char *p = g_build_filename(dir, name, NULL);
  g_free(name);
  return p;
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  char *dir = keep_dir(), *n = keep_safe(name);
  int ok = 0;
  for (int i = 1; i < 10000 && !ok; i++) {
    char *path = keep_name(dir, n, i);
    FILE *f = fopen(path, "wbx");
    if (f) {
      size_t len = (size_t)Moonbit_array_length(data);
      ok = fwrite(data, 1, len, f) == len;
      ok = fclose(f) == 0 && ok;
      if (!ok) remove(path);
      g_free(path);
      break;
    }
    g_free(path);
  }
  g_free(n);
  g_free(dir);
  return ok;
}

// each keep: its state (0 keeping, 1 kept, -1 failed), its name, its part file while its bytes come, where it went
typedef struct {
  int state;
  FILE *part;
  char *name, *tmp, *where;
} keep;
static keep *keeps;
static int nkeeps = 1;  // ids from 1

static keep *keep_of(int32_t id) { return id > 0 && id < nkeeps ? &keeps[id] : NULL; }

static void keep_fail(keep *k) {
  if (k->part) fclose(k->part);
  k->part = NULL;
  if (k->tmp) remove(k->tmp);
  k->state = -1;
}

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  (void)mime, (void)way;
  keeps = realloc(keeps, sizeof(keep) * (size_t)(nkeeps + 1));
  int id = nkeeps++;
  keep *k = &keeps[id];
  memset(k, 0, sizeof *k);
  k->name = keep_safe(name);
  char *dir = keep_dir();
  k->tmp = g_strdup_printf("%s/.mbui-keep-%d-%d.part", dir, (int)getpid(), id);
  g_free(dir);
  k->part = fopen(k->tmp, "wb");
  k->state = k->part ? 0 : -1;
  return id;
}

int32_t mb_host_keep_append(int32_t id, moonbit_bytes_t data) {
  keep *k = keep_of(id);
  if (!k || k->state != 0 || !k->part) return 0;
  size_t n = (size_t)Moonbit_array_length(data);
  if (fwrite(data, 1, n, k->part) == n) return 1;
  keep_fail(k);
  return 0;
}

// finished: the part file named as asked, under a name not taken
void mb_host_keep_finish(int32_t id) {
  keep *k = keep_of(id);
  if (!k || k->state != 0 || !k->part) return;
  int ok = fclose(k->part) == 0;
  k->part = NULL;
  char *dir = keep_dir();
  for (int i = 1; ok && i < 10000; i++) {
    char *path = keep_name(dir, k->name, i);
    // (link: fails when the name is taken, never over another's file)
    if (link(k->tmp, path) == 0) {
      remove(k->tmp);
      k->where = path;
      k->state = 1;
      break;
    }
    g_free(path);
  }
  g_free(dir);
  if (k->state != 1) keep_fail(k);
  schedule();
}

int32_t mb_host_keep_state(int32_t id) {
  keep *k = keep_of(id);
  return k ? k->state : -1;
}

moonbit_string_t mb_host_keep_where(int32_t id) {
  keep *k = keep_of(id);
  return k && k->state == 1 ? mstr(k->where) : moonbit_make_string_raw(0);
}

void mb_host_keep_end(int32_t id) {
  keep *k = keep_of(id);
  if (k && k->state == 0) keep_fail(k);
  if (k) k->state = -1;
}
