// Windows host: a per-monitor DPI-aware Win32 window drawn with Direct3D 11,
// frames from a message loop that blocks while there is nothing to draw,
// input from window messages, and the input method through IMM32 (TSF input
// methods reach it through their IMM32 compatibility layer). A windowed program
// (the GUI subsystem: no console of its own), its life as an app's (win_life.h).
#ifndef _WIN32_WINNT
#define _WIN32_WINNT 0x0A00  // per-monitor DPI v2 (Windows 10 1703)
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <windowsx.h>
#include <shellapi.h>
#include <objbase.h>
#include <imm.h>
#include <psapi.h>
#include <powrprof.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include "win.h"
#include <dwmapi.h>
#include "post.h"
#include "term.h"
#include "app_calls.h"  // the app's own calls
#include "done_watch.h"

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "powrprof.lib")
// (a window's program, not a console's: started from Explorer, a shortcut or a link, no console window comes with it;
// started from a terminal, its lines go there: win_life.h life_console)
#pragma comment(linker, "/SUBSYSTEM:WINDOWS /ENTRY:mainCRTStartup")

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

// The run's first window: its life (win_life.h: put away, brought back, its icon, its state told), its notifications,
// what is posted to the run's thread
static HWND hwnd;
static double wake_at = -1;  // mb_now_ms() of the earliest wake_after, or -1

// ---- the windows of one run (@hostapi.windows_in_process: mb_host_windows) ----
// Each window the app opens beside its first is a window of this run: its own HWND, its swap chain, composition target
// and canvas (win_render.cpp RenderWin), its native views (win_views.cpp: each view the window's it is placed in),
// drawn by the same program, the same device, pipelines, atlas, pictures and stream decoders, one button in the
// taskbar for each. The window drawn or handing input now is put in place for it (win_use: `ws`, and the renderer's)
// and the first put back after: what the app asks of the window then (its size, its scale, a frame, its input method,
// a drag, its cursor) is that window's, and the app is told which it is (mb_host_windows' 4). Closed by the person,
// the app is told (an outside event, MB_OUTSIDE_WINDOW) and the run goes on; the first put away (hidden, not destroyed),
// the windows beside it stay.
typedef struct WinSlot {
  HWND h;  // NULL: no window of that number
  int want_frame;
  // its scale (pixels per point), its content's zoom (@hostapi.set_window_zoom), the last frame's size in points
  double scale, window_content_zoom, frame_w, frame_h;
  // the input method: a field taking it, its caret (x, y, w, h in points, from set_ime), what is composed, a key's
  // first half
  int ime_active;
  double caret[4];
  int marked_len;
  WCHAR high_surrogate;
  // the kind of field it is (mb_host_ime_action: @hostapi.ime_action_*), and whether the system's input method is
  // given the window now (ime_sync): never while a field of digits or a secret has the keys
  int32_t ime_action;
  int ime_associated;
  // the pointer's shape (@hostapi.set_cursor), whether its leaving is asked to be told (TrackMouseEvent), whether the
  // right button is down
  int cursor_kind, tracking_leave, right_down;
  // an inset window's maximize button where the app says (window_snap, in the client's pixels) hit as the title bar's
  // own, so Windows 11's Snap Layouts open from it; how the pointer stands on it (0 off, 1 on, 2 pressing it, its press
  // held: snap_held), the non-client area's leaving asked to be told
  RECT snap_px;
  int snap_state, snap_held, tracking_nc_leave;
  // the fingers down that it takes (0: a free place), the first of them down while it is (what may move the window),
  // its place on the screen (pixels); a finger moving the window from the app's top row (mb_host_window_drag in its
  // press): where it and the window were then, the window following it till it lifts (Windows' own move goes by the
  // mouse)
  UINT32 touch_taken[10], touch_first;
  POINT touch_screen, touch_move_from;
  RECT touch_move_rect;
  int touch_moving;
  // a window beside the first, out of sight (cloaked) till its first frame is presented (win_open, held_shown)
  int held;
  // what the app opened it as (mb_host_windows' 1, its spec; the first's, window_setup): its role (its place and size
  // kept under it as it closes, a second of the role set down and to the right of the one before), when it opened,
  // its least size (points) and whether its top row is the app's (an inset window: WM_NCCALCSIZE and the rest)
  char role[64];
  int opened;
  double min_w, min_h;
  int inset;
  // filling its monitor (mb_host_set_full_screen): its place, styles and frame before, put back as it comes out
  int full_screen;
  WINDOWPLACEMENT saved_place;
  LONG_PTR saved_style, saved_ex_style;
  // the last press in its top row that asked to drag it (mb_host_window_drag): when and where, for the second of a
  // double click there, its own (a press in another window is no first half of it); the move itself begun once the
  // app's handling of the press is over (WM_MB_DRAG: Windows' move is a loop of its own, which draws frames as it goes)
  DWORD drag_time;
  POINT drag_at;
} WinSlot;
// (each beside the first made fresh as it opens: win_slot_fresh)
static WinSlot win_slots[MB_WINS] = {{.scale = 1, .window_content_zoom = 1.0}};
static WinSlot *ws = &win_slots[0];
static int win_active;  // the window in place (0, the first, between frames and input)
static void win_slot_fresh(WinSlot *w) {
  memset(w, 0, sizeof *w);
  w->scale = 1;
  w->window_content_zoom = 1.0;
}
static int win_of(HWND h) {
  if (!h) return -1;
  for (int k = 0; k < MB_WINS; k++)
    if (win_slots[k].h == h) return k;
  return -1;
}
void mb_host_request_frame(void);
// Window `wid` put in place: its slot and its drawing.
static void win_use(int wid) {
  if (wid == win_active || wid < 0 || wid >= MB_WINS || (wid > 0 && !win_slots[wid].h)) return;
  win_active = wid;
  ws = &win_slots[wid];
  mb_render_use(wid);
}
// The window in place before put back (the first where it has closed meanwhile).
static void win_put_back(int wid) {
  if (wid > 0 && !win_slots[wid].h) wid = 0;
  win_use(wid);
}
// the window being made (CreateWindowExW: its first messages, before its HWND is known), -1 none; the windows' class
static int win_making = -1;
static WCHAR win_class[300];
static int32_t (*window_key)(int32_t, int32_t);

void mb_host_set_window_zoom(double zoom) {
  if (zoom > 0) ws->window_content_zoom = zoom;
}
void mb_host_set_window_key(int32_t (*f)(int32_t, int32_t)) { window_key = f; }
int32_t mb_host_window_key(int32_t code, int32_t mods) { return window_key ? window_key(code, mods) : 0; }
static const char *script;
static const wchar_t *shot_dir;
// The window as the app asks for it (@hostapi.window_setup)
static double setup_w, setup_h, setup_min_w, setup_min_h;
// An inset window (@hostapi.window_setup's inset): no title bar of the system's, the app's top row its title bar, the
// window's buttons the app's to draw (@ui's window_keys_own; each window's: WinSlot's snap_*)
static int setup_inset;
// a message posted from outside (mb_post_wake), a stream shown by its layer that said something (mb_app_streamed:
// wParam its id), each told the app between frames, which asks for a frame only where something is left for one
enum { WM_MB_DRAG = WM_APP + 6, WM_MB_POSTED = WM_APP + 7, WM_MB_STREAMED = WM_APP + 8, WM_MB_CALL = WM_APP + 9,
       WM_MB_CAUGHT_KEY = WM_APP + 10, WM_MB_PICKED = WM_APP + 11, WM_MB_TOLD = WM_APP + 12 };  // (win_life.h has 1 to 5, win.h 4)
static void mb_app_picked(void);  // a pick read on its thread: the app told between frames (WM_MB_PICKED)
static int frames_drawn;
static int sizing;  // inside the modal move/size loop, where our loop does not run

// a reading of the performance counter in ms: the clock of mb_host_now (and of a pointer's own time, which Windows
// gives in its counts)
static double qpc_ms(LONGLONG count) {
  static LARGE_INTEGER freq;
  if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
  return (double)count * 1000.0 / (double)freq.QuadPart;
}

static double mb_now_ms(void) {
  LARGE_INTEGER t;
  QueryPerformanceCounter(&t);
  return qpc_ms(t.QuadPart);
}

// How much later than its time the frame before reached the screen (mb_host_frame_late, as the Apple hosts and
// Android say it): a frame begun right after the one before (the frames running on: Present waits for the display's
// frame) more than the display's frame after it, that one was late by as much; the first after the loop waited for
// what came next, or a scripted run's, none. When the last such frame began (-1: the loop waited since).
static double frame_late, last_begin = -1;

// the display's frame (ms), as the compositor goes (as many of its beats as mb_render_present waits)
static double display_period(void) {
  DWM_TIMING_INFO ti;
  memset(&ti, 0, sizeof ti);
  ti.cbSize = sizeof ti;
  if (SUCCEEDED(DwmGetCompositionTimingInfo(NULL, &ti)) && ti.qpcRefreshPeriod)
    return qpc_ms((LONGLONG)ti.qpcRefreshPeriod) * mb_frame_beats();
  return 1000.0 / 60.0;
}

// the time of the pointer's event being delivered (mb_host_event_time): a finger's own, -1 none said
static double event_t = -1;

static void send_text(int kind, const WCHAR *s, int n, int a, int b) {
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, s, (size_t)n * sizeof(WCHAR));
  mb_cb.text(kind, out, a, b);
}

static void run_script_step(int step);
static void ime_place(void);

// The window's size for a client area of `r` (pixels, at `dpi`): the system's frame around it; an inset window's
// without its title bar and its top border, which its client area takes (WM_NCCALCSIZE)
static void window_for_client(RECT *r, UINT dpi, int inset) {
  LONG top = r->top;
  AdjustWindowRectExForDpi(r, WS_OVERLAPPEDWINDOW, FALSE, 0, dpi ? dpi : 96);
  if (inset) r->top = top;
}

// How thick the system's frame is at the window's top (its resize border with its padding), in pixels: what a
// maximized window has past the screen's edge, and the band an inset window is resized by at its top
static int frame_top(HWND h) {
  UINT dpi = GetDpiForWindow(h);
  return GetSystemMetricsForDpi(SM_CYFRAME, dpi) + GetSystemMetricsForDpi(SM_CXPADDEDBORDER, dpi);
}

// How the pointer stands on the app's maximize button (snap_state), told the app at once as it changes
static void snap_set(int state) {
  if (state == ws->snap_state) return;
  ws->snap_state = state;
  ws->want_frame = 1;
}
double mb_host_mem_bytes(void);


static mb_outside_fn outside_cb;  // who is told as what the host does for the app is done (mb_host_set_outside)
static void device_tell(mb_outside_fn tell);  // win_device.h: the clipboard's reads done
static void pick_tell(mb_outside_fn tell);    // win_files.h: the picks read
static void update_tell(mb_outside_fn tell);  // win_update.h: how an update goes

// While the window is not shown (minimized, put away to the notification area: win_life.h), the app goes on as what
// comes from outside asks (a message posted: the core's words, the system's say; an outside wait done: mb_app_wake),
// its frame built at the window's last size and nothing presented: what to show then is the app's (a notification of
// what the core said); what it asks for itself (a motion's frames, its timers) waits till it is shown again, when
// what is owed is drawn at once.
static int outside_asked;  // a frame asked for from outside since the last one

// What came from outside told the app between frames (ui's messages_between, streams_said): it takes what changes
// nothing drawn as it comes, and asks for a frame (as from outside: one built while the window is away) only where
// something is left for one. Before the app has said who is told: a frame, which takes it.
static void told_between(int kind, int id) {
  if (!outside_cb) {
    ws->want_frame = 1;
    outside_asked = 1;
    return;
  }
  int was = ws->want_frame;
  ws->want_frame = 0;
  outside_cb(kind, id, 0);
  if (ws->want_frame) outside_asked = 1;
  ws->want_frame |= was;
}

// The picks read since the app was last told, told now, between frames (pick_tell, each with how it went): what was
// picked taken into what reads it as it comes (ui's outside_take), a frame asked for only where something reads it.
static void picks_between(void) {
  if (!outside_cb) {
    ws->want_frame = 1;
    outside_asked = 1;
    return;
  }
  int was = ws->want_frame;
  ws->want_frame = 0;
  pick_tell(outside_cb);
  if (ws->want_frame) outside_asked = 1;
  ws->want_frame |= was;
}
static int presenting = 1;  // the frame under way is put on the screen

static double win_scale(HWND h) {
  const char *s = getenv("MBUI_SCALE");
  if (s && *s) {
    double v = atof(s);
    if (v > 0) return v;
  }
  return GetDpiForWindow(h) / 96.0;
}

// A frame drawn: a scripted run's steps (MBUI_SCRIPT) go by the first window's.
static void frame_counted(void) {
  if (win_active != 0) return;
  frames_drawn++;
  if (script) run_script_step(frames_drawn);
}

static void draw_frame(void) {
  RECT rc;
  GetClientRect(ws->h, &rc);
  ws->want_frame = 0;
  int outside = outside_asked;
  outside_asked = 0;
  mb_images_tell(outside_cb);
  mb_views_tell(outside_cb);
  device_tell(outside_cb);
  update_tell(outside_cb);
  int away = rc.right <= 0 || rc.bottom <= 0 || !IsWindowVisible(ws->h) || IsIconic(ws->h);
  if (away) {
    // (none drawn yet: nothing to build at)
    if (!outside || ws->frame_w <= 0) return;
    presenting = 0;
    mb_cb.frame(ws->frame_w, ws->frame_h, ws->scale, mb_now_ms());
    presenting = 1;
    frame_counted();
    return;
  }
  double was = ws->scale;
  ws->scale = win_scale(ws->h);
  if (ws->scale != was) {
    ime_place();  // the candidate window is placed in pixels
    mb_views_rescale();
  }
  ws->frame_w = rc.right / ws->scale;
  ws->frame_h = rc.bottom / ws->scale;
  mb_text_set_scale(ws->scale * ws->window_content_zoom);
  mb_render_set_size(rc.right, rc.bottom, ws->frame_w / ws->window_content_zoom, ws->frame_h / ws->window_content_zoom,
                     ws->scale * ws->window_content_zoom);
  double begins = mb_now_ms();
  frame_late = last_begin >= 0 && !script ? fmax(0, begins - last_begin - display_period()) : 0;
  last_begin = begins;
  mb_cb.frame(ws->frame_w, ws->frame_h, ws->scale, begins);
  frame_counted();
}

// The window held out of sight as it opens (@hostapi.window_hold, said before mb_host_run): cloaked (DWM's: shown, its
// frames drawn and presented at its size and scale on its screen, none of it composed onto the screen) till the app
// shows it (mb_host_window_show), then uncloaked once the compositor has taken the frame it was shown in: it comes up
// with the app's page drawn, not with nothing for the page's first moments. So is each window beside the first, till
// its first frame is (win_open: held).
static int window_held, window_shown, window_to_show;

static int cloak(HWND h, BOOL on) { return SUCCEEDED(DwmSetWindowAttribute(h, DWMWA_CLOAK, &on, sizeof on)); }

void mb_host_window_hold(void) { window_held = 1; }

void mb_host_window_show(void) {
  if (window_held && !window_shown) window_to_show = 1;
}

// After a round of frames, the compositor's beat waited for (mb_render_pace: what they presented taken by it): a window
// held whose frame is there uncloaked, the first window once the app has shown it.
static void held_shown_now(void) {
  for (int k = 1; k < MB_WINS; k++) {
    WinSlot *w = &win_slots[k];
    if (!w->h || w->held != 2) continue;
    w->held = 0;
    cloak(w->h, FALSE);
  }
  if (window_to_show && !window_shown && hwnd) {
    window_to_show = 0;
    window_shown = 1;
    cloak(hwnd, FALSE);
  }
}

// What the frames presented since the last round owe the compositor waited for, and what was held shown then.
static void frames_paced(void) {
  mb_render_pace();
  held_shown_now();
}

static int any_want_frame(void) {
  for (int k = 0; k < MB_WINS; k++)
    if (win_slots[k].h && (win_slots[k].want_frame || mb_render_adaptive_settling(k))) return 1;
  return 0;
}

// The windows of the run that want a frame each drawn, put in place for it, then the compositor's beat waited for once
// (mb_render_pace): 1 when any was drawn.
static int frames_round(void) {
  int any = 0;
  for (int k = 0; k < MB_WINS; k++) {
    if (!win_slots[k].h) continue;
    if (win_slots[k].want_frame) {
      any = 1;
      int back = win_active;
      win_use(k);
      draw_frame();
      win_put_back(back);
    } else if (mb_render_adaptive_settling(k)) {
      if (mb_render_adaptive_step(k)) any = 1;
    }
  }
  if (any) frames_paced();
  return any;
}

// ---- input method ----

static void ime_compose(const WCHAR *s, int n, int cursor);
static int key_catching;  // (win_keys.h: a key catcher has the focus, whatever field had it before)

// The system's input method given the window while a field takes the keys, but one of digits (a code) or a secret (a
// password; @hostapi.ime_action_number, ime_action_secret): an input method there catches the digits and letters
// typed (a Chinese one, on by default, turned 1 into a candidate), and a secret's words would go through it. Without
// one the keys still come as WM_CHAR, as a keyboard's own. Taken away, what it was composing is let go.
static void ime_sync(void) {
  int want = ws->ime_active && (key_catching || (ws->ime_action != 3 && ws->ime_action != 4));
  if (want == ws->ime_associated) return;
  if (want) {
    ImmAssociateContextEx(ws->h, NULL, IACE_DEFAULT);
  } else {
    HIMC imc = ImmGetContext(ws->h);
    if (imc) {
      ImmNotifyIME(imc, NI_COMPOSITIONSTR, CPS_CANCEL, 0);
      ImmReleaseContext(ws->h, imc);
    }
    ImmAssociateContextEx(ws->h, NULL, 0);
    // (a field still taking the keys is told its composition went)
    if (ws->ime_active && ws->marked_len) ime_compose(NULL, 0, 0);
    ws->marked_len = 0;
  }
  ws->ime_associated = want;
}

// the kind of field taking the keys (@hostapi.ime_action_*), said just before set_ime (editor.mbt)
void mb_host_ime_action(int32_t kind) {
  ws->ime_action = kind;
  ime_sync();
}

static void ime_place(void) {
  if (!ws->ime_active) return;
  int x = (int)lround(ws->caret[0] * ws->scale), y = (int)lround(ws->caret[1] * ws->scale);
  int b = (int)lround((ws->caret[1] + ws->caret[3]) * ws->scale);
  SetCaretPos(x, y);  // some input methods follow the system caret
  HIMC imc = ImmGetContext(ws->h);
  if (!imc) return;
  COMPOSITIONFORM cf = {CFS_POINT, {x, y}, {0, 0, 0, 0}};
  ImmSetCompositionWindow(imc, &cf);
  CANDIDATEFORM cand = {0, CFS_EXCLUDE, {x, b}, {x, y, x + 1, b}};
  ImmSetCandidateWindow(imc, &cand);
  ImmReleaseContext(ws->h, imc);
}

static void ime_compose(const WCHAR *s, int n, int cursor) {
  ws->marked_len = n;
  if (n == 0) send_text(1, L"", 0, 0, 0);
  else send_text(1, s, n, cursor, 0);
}

static void ime_commit(const WCHAR *s, int n) {
  ws->marked_len = 0;
  send_text(0, s, n, 0, 0);
}

static WCHAR *ime_string(HIMC imc, DWORD which, int *n) {
  LONG bytes = ImmGetCompositionStringW(imc, which, NULL, 0);
  if (bytes <= 0) {
    *n = 0;
    return NULL;
  }
  WCHAR *s = (WCHAR *)malloc((size_t)bytes);
  ImmGetCompositionStringW(imc, which, s, (DWORD)bytes);
  *n = (int)(bytes / sizeof(WCHAR));
  return s;
}

static void ime_composition(LPARAM lp) {
  HIMC imc = ImmGetContext(ws->h);
  if (!imc) return;
  int n;
  if (lp & GCS_RESULTSTR) {
    WCHAR *s = ime_string(imc, GCS_RESULTSTR, &n);
    ime_commit(s, n);
    free(s);
  }
  if (lp & GCS_COMPSTR) {
    WCHAR *s = ime_string(imc, GCS_COMPSTR, &n);
    int cursor = (lp & GCS_CURSORPOS) ? (int)ImmGetCompositionStringW(imc, GCS_CURSORPOS, NULL, 0) : n;
    ime_compose(s, n, cursor < 0 || cursor > n ? n : cursor);
    free(s);
  } else if (!(lp & GCS_RESULTSTR) && ws->marked_len) {
    ime_compose(NULL, 0, 0);  // composition cancelled
  }
  ImmReleaseContext(ws->h, imc);
  ime_place();
}

// ---- clipboard ----

// The clipboard's words pasted (text kind 8: put in as typed, a step of its own to undo).
static void paste(void) {
  if (!OpenClipboard(hwnd)) return;
  HANDLE h = GetClipboardData(CF_UNICODETEXT);
  const WCHAR *p = h ? (const WCHAR *)GlobalLock(h) : NULL;
  if (p) {
    size_t n = wcslen(p), k = 0;
    WCHAR *s = (WCHAR *)malloc((n + 1) * sizeof(WCHAR));
    for (size_t i = 0; i < n; i++)
      if (!(p[i] == '\r' && p[i + 1] == '\n')) s[k++] = p[i];
    GlobalUnlock(h);
    CloseClipboard();
    if (k) send_text(8, s, (int)k, 0, 0);
    free(s);
    return;
  }
  CloseClipboard();
}

// ---- keys ----

// files from outside: the system's dialog, let go on the window
#include "win_files.h"
// the device beyond the window (device.mbt): a key catcher's keys, the clipboard, awake
// (a key catcher's windows: each of the run's, its own field and composition: win_keys.h)
static int keys_typing(HWND h) {
  int k = win_of(h);
  return k >= 0 && win_slots[k].ime_active && !win_slots[k].marked_len;
}
#define KEYS_OURS(h) (win_of(h) >= 0)
#define KEYS_TYPING(h) keys_typing(h)
// (its frame the window in place's, as a test of it has its one)
#define want_frame ws->want_frame
#include "win_device.h"
#undef want_frame
// its log files: what it says on stderr, its performance record
#include "win_logs.h"
// the app's life: once for its person, put away to the notification area, links, in front or not, light or dark
#include "win_life.h"
// the app keeping itself current: a newer build's installer downloaded, checked, run
#include "win_update.h"

// A paste by key (`mods` the app's Ctrl with what else is held): files on it (Explorer's copied ones) or a picture (PNG,
// or a bitmap): the app's Ctrl+V (1000 + v), which reads the clipboard for them (@hostapi.clip_read), as a page's paste
// takes them as files; else its words
static void paste_key(int mods) {
  if (IsClipboardFormatAvailable(CF_HDROP) ||
      IsClipboardFormatAvailable(RegisterClipboardFormatW(L"PNG")) || IsClipboardFormatAvailable(CF_DIB) ||
      IsClipboardFormatAvailable(CF_DIBV5) || IsClipboardFormatAvailable(CF_BITMAP)) {
    mb_cb.key(1000 + 'v', mods);
  } else {
    paste();
  }
}

static void key_down(WPARAM vk) {
  // a key catcher's focus (win_device.h): its keys (a composition under way keeps them)
  if (key_catching && ws->ime_active && ws->marked_len == 0 && catch_vk(vk)) return;
  int mods = mods_now(), code = 0;
  // Shift+Insert: the system's other key for a paste, what a clipboard manager may press for one (Raycast does): as
  // Ctrl+V
  if (vk == VK_INSERT && mods == 1) {
    paste_key(2);
    return;
  }
  if (mods & 2) {
    switch (vk) {
      case 'A': code = 12; break;
      case 'C': code = 13; break;
      case 'X': code = 14; break;
      case 'V': paste_key(mods); return;
    }
    // any other Ctrl key with a character: the app's shortcut (1000 + the character, lower case)
    if (!code) {
      UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
      if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
      if (ch >= 32) {
        mb_cb.key(1000 + (int)ch, mods);
        return;
      }
    }
  }
  switch (vk) {
    case VK_ESCAPE: code = 17; break;
    case VK_TAB: code = 18; break;
    case VK_BACK: code = 1; break;
    case VK_DELETE: code = 2; break;
    case VK_LEFT: code = 3; break;
    case VK_RIGHT: code = 4; break;
    case VK_UP: code = 5; break;
    case VK_DOWN: code = 6; break;
    case VK_RETURN: code = 7; break;
    case VK_HOME: code = 8; break;
    case VK_END: code = 9; break;
    // without a field to type in, these scroll the list under the pointer
    case VK_PRIOR: code = ws->ime_active ? 0 : 15; break;
    case VK_NEXT: code = ws->ime_active ? 0 : 16; break;
  }
  if (code) {
    mb_cb.key(code, mods);
    return;
  }
  // a character with no field to take it (Space, a letter): the app's, as 1000 + it
  if (!ws->ime_active) {
    UINT ch = MapVirtualKeyW((UINT)vk, MAPVK_VK_TO_CHAR) & 0x7FFF;
    if (ch >= 'A' && ch <= 'Z') ch += 'a' - 'A';
    if (ch >= 32) mb_cb.key(1000 + (int)ch, mods);
  }
}

static void char_in(WCHAR c) {
  if (IS_HIGH_SURROGATE(c)) {
    ws->high_surrogate = c;
    return;
  }
  if (IS_LOW_SURROGATE(c)) {
    WCHAR pair[2] = {ws->high_surrogate, c};
    if (ws->high_surrogate) send_text(0, pair, 2, 0, 0);
    ws->high_surrogate = 0;
    return;
  }
  ws->high_surrogate = 0;
  // control characters arrive as keys (Enter, Backspace) or shortcuts; with no field, characters are keys (key_down)
  if (c < 0x20 || c == 0x7F || !ws->ime_active) return;
  send_text(0, &c, 1, 0, 0);
}

// ---- the window ----

// What the pointer's event being handled came from (@hostapi.event_finger): 1 a finger, 0 a mouse or a pen (or a
// finger the system made a mouse of: over a web view), -1 none being handled
static int event_by = -1;
int32_t mb_host_event_finger(void) { return event_by; }

static void pointer_by(int by, int kind, double x, double y, int button) {
  event_by = by;
  mb_cb.pointer(kind, x, y, button);
  event_by = -1;
}

static void pointer(int kind, LPARAM lp) { pointer_by(0, kind, GET_X_LPARAM(lp) / ws->scale, GET_Y_LPARAM(lp) / ws->scale, 0); }

static void pointer_button(int kind, LPARAM lp, int button) {
  pointer_by(0, kind, GET_X_LPARAM(lp) / ws->scale, GET_Y_LPARAM(lp) / ws->scale, button);
}

// The pointer held by a window (@hostapi.set_pointer_lock): the system's pointer hidden and held where it is (clipped to
// that one pixel), the mouse read raw (WM_INPUT's RAWMOUSE, its own distance each time in the mouse's own counts, as a
// browser's movementX on Windows and as the other machine's SendInput moves by them, summed till the app takes it:
// mb_host_pointer_delta) and each read a move where the pointer stays; let
// go of as the window goes out of focus (WM_KILLFOCUS, WM_ACTIVATE) or is closed.
static int lock_win = -1;
static POINT lock_at;
static double lock_dx, lock_dy;
static void lock_set(int on) {
  if (on == (lock_win >= 0)) return;
  RAWINPUTDEVICE rid = {0x01, 0x02, on ? 0 : RIDEV_REMOVE, on ? ws->h : NULL};
  if (on) {
    if (!ws->h || GetForegroundWindow() != ws->h) return;
    if (!RegisterRawInputDevices(&rid, 1, sizeof rid)) return;
    lock_win = win_active;
    GetCursorPos(&lock_at);
    RECT r = {lock_at.x, lock_at.y, lock_at.x + 1, lock_at.y + 1};
    ClipCursor(&r);
    ShowCursor(FALSE);
  } else {
    lock_win = -1;
    RegisterRawInputDevices(&rid, 1, sizeof rid);
    ClipCursor(NULL);
    ShowCursor(TRUE);
  }
  lock_dx = lock_dy = 0;
}
void mb_host_pointer_lock(int32_t on) { lock_set(on ? 1 : 0); }
int32_t mb_host_pointer_locked(void) { return lock_win >= 0; }
void mb_host_pointer_delta(double *out) {
  out[0] = lock_dx;
  out[1] = lock_dy;
  lock_dx = lock_dy = 0;
}
// A raw read of the mouse while the pointer is held: its distance summed, a move told where the pointer stays.
static void lock_input(HWND h, LPARAM lp) {
  if (lock_win != win_active) return;
  RAWINPUT in;
  UINT size = sizeof in;
  if (GetRawInputData((HRAWINPUT)lp, RID_INPUT, &in, &size, sizeof(RAWINPUTHEADER)) == (UINT)-1) return;
  if (in.header.dwType != RIM_TYPEMOUSE || (in.data.mouse.usFlags & MOUSE_MOVE_ABSOLUTE)) return;
  if (in.data.mouse.lLastX == 0 && in.data.mouse.lLastY == 0) return;
  lock_dx += in.data.mouse.lLastX;
  lock_dy += in.data.mouse.lLastY;
  POINT p = lock_at;
  ScreenToClient(h, &p);
  pointer_by(0, 1, p.x / ws->scale, p.y / ws->scale, 0);
}

// The game controllers connected (@hostapi.gamepads): XInput's four slots, read as the W3C's Standard Gamepad (its
// sticks down positive: XInput's up), from whichever of its DLLs the system has (none: no controllers).
typedef struct {
  WORD wButtons;
  BYTE bLeftTrigger, bRightTrigger;
  SHORT sThumbLX, sThumbLY, sThumbRX, sThumbRY;
} XPad;
typedef struct {
  DWORD dwPacketNumber;
  XPad Gamepad;
} XState;
typedef DWORD(WINAPI *XGetState)(DWORD, XState *);
static XGetState xinput_get(void) {
  static int tried;
  static XGetState get;
  if (!tried) {
    tried = 1;
    HMODULE m = LoadLibraryW(L"xinput1_4.dll");
    if (!m) m = LoadLibraryW(L"xinput9_1_0.dll");
    if (m) get = (XGetState)(void *)GetProcAddress(m, "XInputGetState");
  }
  return get;
}
static double stick(SHORT v) { return v < 0 ? v / 32768.0 : v / 32767.0; }
int32_t mb_host_gamepads(double *out) {
  XGetState get = xinput_get();
  if (!get) return 0;
  int n = 0;
  for (DWORD i = 0; i < 4; i++) {
    XState st;
    if (get(i, &st) != ERROR_SUCCESS) continue;
    XPad *g = &st.Gamepad;
    WORD w = g->wButtons;
    // XInput's bits: 0x1 up, 0x2 down, 0x4 left, 0x8 right, 0x10 start, 0x20 back, 0x40 L3, 0x80 R3, 0x100 LB,
    // 0x200 RB, 0x1000 A, 0x2000 B, 0x4000 X, 0x8000 Y
    int b = ((w & 0x1000) ? 1 << 0 : 0) | ((w & 0x2000) ? 1 << 1 : 0) | ((w & 0x4000) ? 1 << 2 : 0) |
            ((w & 0x8000) ? 1 << 3 : 0) | ((w & 0x100) ? 1 << 4 : 0) | ((w & 0x200) ? 1 << 5 : 0) |
            (g->bLeftTrigger > 30 ? 1 << 6 : 0) | (g->bRightTrigger > 30 ? 1 << 7 : 0) | ((w & 0x20) ? 1 << 8 : 0) |
            ((w & 0x10) ? 1 << 9 : 0) | ((w & 0x40) ? 1 << 10 : 0) | ((w & 0x80) ? 1 << 11 : 0) |
            ((w & 0x1) ? 1 << 12 : 0) | ((w & 0x2) ? 1 << 13 : 0) | ((w & 0x4) ? 1 << 14 : 0) | ((w & 0x8) ? 1 << 15 : 0);
    double *o = out + n * 9;
    o[0] = i;
    o[1] = 1;
    o[2] = b;
    o[3] = stick(g->sThumbLX);
    o[4] = -stick(g->sThumbLY);
    o[5] = stick(g->sThumbRX);
    o[6] = -stick(g->sThumbRY);
    o[7] = g->bLeftTrigger / 255.0;
    o[8] = g->bRightTrigger / 255.0;
    n++;
  }
  return n;
}

// A touch screen's fingers (WM_POINTER*), each by its pointer id, handed on as they come (pointer kinds 10 down, 11
// moved, 12 up, 13 called off: cancelled, the capture taken; the id where a button goes), what they come to the app's
// to work out (touches.mbt: two of them its, the first let go the second the first, one called off all of it); not a
// mouse the system makes of them (its press and hold a right click, its drag a selection). A finger that goes down on
// a web view with none down is left to the system, its mouse the page's (mb_views_input).
// (the fingers down that a window takes, the first of them, where it is and whether it moves the window: WinSlot's)
static int touch_at(UINT32 id) {
  for (int i = 0; i < 10; i++)
    if (ws->touch_taken[i] == id) return i;
  return -1;
}
// 1: taken (the system makes no mouse of it)
static int touch(HWND h, UINT msg, WPARAM wp) {
  UINT32 id = GET_POINTERID_WPARAM(wp);
  POINTER_INPUT_TYPE type;
  POINTER_INFO info;
  if (!id || !GetPointerType(id, &type) || type != PT_TOUCH || !GetPointerInfo(id, &info)) return 0;
  POINT p = info.ptPixelLocation;
  if (id == ws->touch_first || (msg == WM_POINTERDOWN && !ws->touch_first)) ws->touch_screen = p;
  // (the window moved by the finger: its moves the window's, its lift calls the press off for the app)
  if (ws->touch_moving && id == ws->touch_first && msg == WM_POINTERUPDATE) {
    SetWindowPos(h, NULL, ws->touch_move_rect.left + p.x - ws->touch_move_from.x, ws->touch_move_rect.top + p.y - ws->touch_move_from.y, 0,
                 0, SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
    return 1;
  }
  ScreenToClient(h, &p);
  double x = p.x / ws->scale, y = p.y / ws->scale;
  int at = touch_at(id), kind;
  if (msg == WM_POINTERDOWN) {
    if (at < 0) {
      int none = 1;
      for (int i = 0; i < 10; i++)
        if (ws->touch_taken[i]) none = 0;
      if (none && mb_views_pass_through(x, y)) return 0;
      int free = touch_at(0);
      if (free < 0) return 0;
      ws->touch_taken[free] = id;
    }
    if (!ws->touch_first) {
      ws->touch_first = id;
      SetFocus(h);
    }
    kind = 10;
  } else {
    if (at < 0) return 0;
    if (msg == WM_POINTERUPDATE) {
      kind = 11;
    } else {  // WM_POINTERUP, WM_POINTERCAPTURECHANGED
      ws->touch_taken[at] = 0;
      int moved = ws->touch_moving && id == ws->touch_first;
      if (id == ws->touch_first) ws->touch_first = 0, ws->touch_moving = 0;
      // (let go: up; cancelled, the capture taken from it, or it moved the window (the press the app's no more):
      // called off)
      kind = msg == WM_POINTERUP && !IS_POINTER_CANCELED_WPARAM(wp) && !moved ? 12 : 13;
    }
  }
  // a move's samples merged since the last (the oldest first, each at its own place and time: a fling's speed is
  // theirs), then the move itself at its own time, as Android's host hands a MotionEvent's history
  if (kind == 11) {
    UINT32 n = info.historyCount;
    if (n > 1) {
      POINTER_INFO past[64];
      if (n > 64) n = 64;
      if (GetPointerInfoHistory(id, &n, past)) {
        for (UINT32 i = n; i-- > 1;) {
          POINT q = past[i].ptPixelLocation;
          ScreenToClient(h, &q);
          event_t = past[i].PerformanceCount ? qpc_ms((LONGLONG)past[i].PerformanceCount) : -1;
          pointer_by(1, kind, q.x / ws->scale, q.y / ws->scale, (int)id);
        }
      }
    }
  }
  event_t = info.PerformanceCount ? qpc_ms((LONGLONG)info.PerformanceCount) : -1;
  pointer_by(1, kind, x, y, (int)id);
  event_t = -1;
  return 1;
}

static LPCSTR cursor_name(int kind) {
  switch (kind) {
    case 1: return IDC_HAND;
    case 2: return IDC_IBEAM;
    case 3: return IDC_SIZEWE;
    case 4: return IDC_SIZENS;
    case 5: return IDC_SIZEALL;
    case 6: return IDC_SIZEALL;
    case 7: return IDC_CROSS;
    case 8: return IDC_NO;
    case 9: return IDC_SIZENWSE;
    case 10: return IDC_SIZENESW;
    default: return IDC_ARROW;
  }
}

static void wheel(WPARAM wp, LPARAM lp, int horizontal) {
  POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
  ScreenToClient(ws->h, &p);
  UINT lines = 3;
  SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
  if (lines == WHEEL_PAGESCROLL) lines = 20;
  // a notch is WHEEL_DELTA; a line 100/3 points, as a browser scrolls (100 a notch of three lines), eased in by the
  // app (phase 4)
  double d = GET_WHEEL_DELTA_WPARAM(wp) / (double)WHEEL_DELTA * lines * (100.0 / 3.0);
  // what is held with it, above the phase (ui's wheel_mod_*), as the message says it (MK_*): a precision touchpad's
  // pinch comes as the wheel with MK_CONTROL and no Ctrl key down, so the keyboard's state would never see it
  WORD keys = GET_KEYSTATE_WPARAM(wp);
  int mods = ((keys & MK_SHIFT) ? 1 : 0) | ((keys & MK_CONTROL) ? 2 : 0) | (GetKeyState(VK_MENU) < 0 ? 4 : 0);
  if (horizontal) mb_cb.wheel(p.x / ws->scale, p.y / ws->scale, d, 0, 4 | (mods << 4));
  else mb_cb.wheel(p.x / ws->scale, p.y / ws->scale, 0, -d, 4 | (mods << 4));
}

static void win_closed(int wid);

// A message of window `h`'s, handled with that window in place (win_use), the one in place before put back after.
static LRESULT wndproc_here(HWND h, UINT msg, WPARAM wp, LPARAM lp);
static LRESULT CALLBACK wndproc(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  int k = win_of(h);
  if (k < 0 && win_making >= 0 && !win_slots[win_making].h) win_slots[k = win_making].h = h;
  if (k < 0) return DefWindowProcW(h, msg, wp, lp);
  int back = win_active;
  win_use(k);
  LRESULT r = wndproc_here(h, msg, wp, lp);
  win_put_back(back);
  return r;
}

static LRESULT wndproc_here(HWND h, UINT msg, WPARAM wp, LPARAM lp) {
  // the app's maximize button pressed (snap_held): the mouse the host's till it is let go, there or elsewhere
  if (ws->snap_held && (msg == WM_MOUSEMOVE || msg == WM_LBUTTONUP)) {
    POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
    int on = PtInRect(&ws->snap_px, p);
    if (msg == WM_LBUTTONUP) {
      ws->snap_held = 0;
      ReleaseCapture();
      snap_set(on ? 1 : 0);
      if (on) ShowWindow(h, IsZoomed(h) ? SW_RESTORE : SW_MAXIMIZE);
    } else {
      snap_set(on ? 2 : 0);
    }
    return 0;
  }
  // the mouse over a web view (win_views.cpp) is its page's
  if (((msg >= WM_MOUSEFIRST && msg <= WM_MOUSELAST) || msg == WM_MOUSELEAVE) && mb_views_input(msg, wp, lp)) {
    if (msg == WM_MOUSEMOVE && !ws->tracking_leave) {
      TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
      ws->tracking_leave = TrackMouseEvent(&t) ? 1 : 0;
    }
    return 0;
  }
  LRESULT taken = 0;
  // (the run's life is its first window's: a window beside it only closes, and tells the run its state may have changed)
  if (h != hwnd) {
    switch (msg) {
      case WM_ACTIVATE:
      case WM_SHOWWINDOW:
      case WM_SIZE: PostMessageW(hwnd, WM_MB_STATE, 0, 0); break;
      case WM_DESTROY:
        if (lock_win == win_active) lock_set(0);
        win_closed(win_active);
        return 0;
    }
  } else if (life_message(msg, wp, lp, &taken)) {
    return taken;
  }
  // the taskbar's button made anew (the window shown again from its tray): its number put on it again
  static UINT button_made;
  if (!button_made) button_made = RegisterWindowMessageW(L"TaskbarButtonCreated");
  if (msg == button_made) {
    mb_win_badge_again(h);
    return 0;
  }
  switch (msg) {
    // An inset window: its client area the whole window but the system's frame at its sides and foot (resized there,
    // its shadow, Windows 11's corners), its title bar and top border the app's top row; maximized, without what of it
    // is past the screen's top edge, as the title bar it has not would have been
    case WM_NCCALCSIZE:
      // (filling its monitor: all of it the client's, no frame of the system's)
      if (wp && ws->full_screen) return 0;
      if (ws->inset && wp) {
        NCCALCSIZE_PARAMS *nc = (NCCALCSIZE_PARAMS *)lp;
        LONG top = nc->rgrc[0].top;
        LRESULT r = DefWindowProcW(h, msg, wp, lp);
        if (r != 0) return r;
        nc->rgrc[0].top = top + (IsZoomed(h) ? frame_top(h) : 0);
        return 0;
      }
      break;
    // where an inset window's top row is resized (its frame's thickness at its top, not maximized) and its maximize
    // button (the app's, window_snap: the system's Snap Layouts over it as the pointer rests there); the rest of the
    // top row the app's (it drags the window where it says: mb_host_window_drag)
    case WM_NCHITTEST:
      if (ws->inset && !ws->full_screen) {
        LRESULT hit = DefWindowProcW(h, msg, wp, lp);
        if (hit != HTCLIENT) return hit;
        POINT p = {GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
        ScreenToClient(h, &p);
        int band = frame_top(h);
        if (!IsZoomed(h) && p.y < band) {
          RECT c;
          GetClientRect(h, &c);
          return p.x < band ? HTTOPLEFT : p.x >= c.right - band ? HTTOPRIGHT : HTTOP;
        }
        if (ws->snap_px.right > ws->snap_px.left && PtInRect(&ws->snap_px, p)) return HTMAXBUTTON;
        return HTCLIENT;
      }
      break;
    // the pointer on the app's maximize button, which is the system's for it (HTMAXBUTTON): its Snap Layouts opened by
    // the system's own handling of its hover; its press and its letting go the host's (not the system's, which would
    // draw a button of its own there)
    case WM_NCMOUSEMOVE:
      if (ws->inset) {
        if (!ws->tracking_nc_leave) {
          TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE | TME_NONCLIENT, h, 0};
          ws->tracking_nc_leave = TrackMouseEvent(&t) ? 1 : 0;
        }
        if (!ws->snap_held) snap_set(wp == HTMAXBUTTON ? 1 : 0);
      }
      break;
    case WM_NCMOUSELEAVE:
      ws->tracking_nc_leave = 0;
      if (!ws->snap_held) snap_set(0);
      break;
    case WM_NCLBUTTONDOWN:
    case WM_NCLBUTTONDBLCLK:
      if (ws->inset && wp == HTMAXBUTTON) {
        ws->snap_held = 1;
        SetCapture(h);
        snap_set(2);
        return 0;
      }
      break;
    case WM_NCLBUTTONUP:
      if (ws->inset && wp == HTMAXBUTTON) return 0;
      break;
    case WM_CAPTURECHANGED:
      if (ws->snap_held && (HWND)lp != h) {
        ws->snap_held = 0;
        snap_set(0);
      }
      break;
    case WM_PAINT: {
      PAINTSTRUCT ps;
      BeginPaint(h, &ps);
      EndPaint(h, &ps);
      ws->want_frame = 1;
      return 0;
    }
    case WM_ERASEBKGND: return 1;
    case WM_APP: ws->want_frame = 1; outside_asked = 1; return 0;  // mb_app_wake
    case WM_MB_POSTED: told_between(MB_OUTSIDE_POSTED, 0); return 0;
    case WM_MB_STREAMED: told_between(MB_OUTSIDE_STREAMED, (int)wp); return 0;
    case WM_MB_PICKED: picks_between(); return 0;
    case WM_MB_TOLD: told_between((int)wp, (int)lp); return 0;
    case WM_MB_CALL: ((void (*)(void *))wp)((void *)lp); return 0;  // mb_app_call
    case WM_MB_DRAG:
      if (GetKeyState(VK_LBUTTON) < 0) {
        int k = win_of(h);
        POINT at = k >= 0 ? win_slots[k].drag_at : ws->drag_at;
        ReleaseCapture();
        SendMessageW(h, WM_NCLBUTTONDOWN, HTCAPTION, MAKELPARAM(at.x, at.y));
      }
      return 0;
    // minimized or hidden: what drawing holds beyond its frames given back (glass's levels), made again as it draws
    case WM_SHOWWINDOW:
      if (!wp) mb_render_trim();
      break;
    case WM_SIZE:
      if (wp == SIZE_MINIMIZED) mb_render_trim();
      ws->want_frame = 1;
      if (sizing) {
        draw_frame();
        frames_paced();
      }
      return 0;
    case WM_ENTERSIZEMOVE: sizing = 1; SetTimer(h, 1, 16, NULL); return 0;
    case WM_EXITSIZEMOVE:
      sizing = 0;
      KillTimer(h, 1);
      // (the first's place kept as it was moved or sized: not a window beside it's)
      if (h == hwnd) place_keep();
      return 0;
    case WM_TIMER:
      // (inside the system's move or size loop, its window's frames: the others' as the loop ends)
      if (wake_at >= 0 && mb_now_ms() >= wake_at) {
        wake_at = -1;
        mb_host_request_frame();
      }
      if (ws->want_frame) {
        draw_frame();
        frames_paced();
      }
      return 0;
    case WM_DPICHANGED: {
      RECT *r = (RECT *)lp;
      SetWindowPos(h, NULL, r->left, r->top, r->right - r->left, r->bottom - r->top,
                   SWP_NOZORDER | SWP_NOACTIVATE);
      ws->want_frame = 1;
      return 0;
    }
    case WM_GETOBJECT: {
      // (the app's widgets are its first window's to read: a window beside it is read as the system reads any)
      intptr_t r;
      if (h == hwnd && mb_a11y_object(h, wp, lp, &r)) return (LRESULT)r;
      break;
    }
    case WM_POINTERDOWN:
    case WM_POINTERUPDATE:
    case WM_POINTERUP:
    case WM_POINTERCAPTURECHANGED:
      if (touch(h, msg, wp)) return 0;
      break;
    case WM_LBUTTONDOWN: SetCapture(h); SetFocus(h); pointer(0, lp); return 0;
    case WM_MOUSEMOVE:
      if (!ws->tracking_leave) {
        TRACKMOUSEEVENT t = {sizeof t, TME_LEAVE, h, 0};
        ws->tracking_leave = TrackMouseEvent(&t) ? 1 : 0;
      }
      pointer(1, lp);
      return 0;
    case WM_MOUSELEAVE:
      ws->tracking_leave = 0;
      pointer_by(0, 7, -1, -1, 0);
      return 0;
    case WM_RBUTTONDOWN: SetFocus(h); ws->right_down = 1; pointer_button(0, lp, 2); return 0;
    case WM_RBUTTONUP:
      if (ws->right_down) pointer_button(2, lp, 2);
      ws->right_down = 0;
      return 0;
    // the middle button: the host's 3, down and up, held as the primary is (the window's till it is let go)
    case WM_MBUTTONDOWN: SetCapture(h); SetFocus(h); pointer_button(0, lp, 3); return 0;
    case WM_MBUTTONUP:
      if (!(wp & (MK_LBUTTON | MK_RBUTTON))) ReleaseCapture();
      pointer_button(2, lp, 3);
      return 0;
    case WM_INPUT: lock_input(h, lp); break;
    case WM_CONTEXTMENU: return 0;
    case WM_SETCURSOR:
      if (LOWORD(lp) == HTCLIENT) {
        POINT p;
        GetCursorPos(&p);
        ScreenToClient(h, &p);
        HCURSOR page = (HCURSOR)mb_views_cursor(p.x / ws->scale, p.y / ws->scale);
        SetCursor(page ? page : LoadCursor(NULL, cursor_name(ws->cursor_kind)));
        return TRUE;
      }
      break;
    case WM_GETMINMAXINFO: {
      MINMAXINFO *mm = (MINMAXINFO *)lp;
      if (getenv("MBUI_WIN")) {
        if (mm->ptMaxTrackSize.x < 4096) mm->ptMaxTrackSize.x = 4096;
        if (mm->ptMaxTrackSize.y < 4096) mm->ptMaxTrackSize.y = 4096;
      }
      // the least the app asked for (@hostapi.window_setup, or the spec the window was opened with: its slot's), as a
      // client area at the window's scale
      if (ws->min_w > 0 || ws->min_h > 0) {
        UINT dpi = GetDpiForWindow(h);
        double k = win_scale(h);
        RECT r = {0, 0, (LONG)lround(ws->min_w * k), (LONG)lround(ws->min_h * k)};
        window_for_client(&r, dpi, ws->inset);
        mm->ptMinTrackSize.x = r.right - r.left;
        mm->ptMinTrackSize.y = r.bottom - r.top;
      }
      return 0;
    }
    case WM_LBUTTONUP: ReleaseCapture(); pointer(2, lp); return 0;
    case WM_MOUSEWHEEL: wheel(wp, lp, 0); return 0;
    case WM_MOUSEHWHEEL: wheel(wp, lp, 1); return 0;
    case WM_KEYDOWN:
      if (wp == VK_SHIFT || wp == VK_CONTROL || wp == VK_MENU) mb_cb.key(0, mods_now());
      key_down(wp); return 0;
    case WM_KEYUP:
      if (wp == VK_SHIFT || wp == VK_CONTROL || wp == VK_MENU) { mb_cb.key(0, mods_now()); return 0; }
      break;
    case WM_MB_CAUGHT_KEY:
      if (catch_canvas()) mb_cb.key((int32_t)wp, (int32_t)lp);
      return 0;
    case WM_SYSKEYDOWN:
      if (wp == VK_SHIFT || wp == VK_CONTROL || wp == VK_MENU) mb_cb.key(0, mods_now());
      // Alt with a key: a key catcher's shortcut (win_device.h)
      if (key_catching && ws->ime_active && catch_vk(wp)) return 0;
      if (wp == VK_LEFT && go_back()) return 0;
      // Alt+Right: forward, the app's key (key_forward)
      if (wp == VK_RIGHT) {
        mb_cb.key(40, 0);
        return 0;
      }
      break;
    case WM_SYSKEYUP:
      if (wp == VK_SHIFT || wp == VK_CONTROL || wp == VK_MENU) mb_cb.key(0, mods_now());
      break;
    case WM_XBUTTONUP:
      if (GET_XBUTTON_WPARAM(wp) == XBUTTON1) go_back();
      else if (GET_XBUTTON_WPARAM(wp) == XBUTTON2) mb_cb.key(40, 0);
      return TRUE;
    case WM_CHAR: char_in((WCHAR)wp); return 0;
    case WM_SETFOCUS:
      mb_cb.key(0, mods_now());
      catch_keys_focus(1);
      if (ws->ime_active) {
        CreateCaret(h, NULL, 1, (int)lround(ws->caret[3] * ws->scale));
        ime_place();
      }
      return 0;
    case WM_KILLFOCUS:
      // (the pointer it held let go of, seen again)
      if (lock_win == win_active) lock_set(0);
      mb_cb.key(0, 0); catch_keys_focus(0); DestroyCaret(); return 0;
    case WM_IME_SETCONTEXT:
      // we draw the composition ourselves; the system draws the candidates
      lp &= ~(LPARAM)ISC_SHOWUICOMPOSITIONWINDOW;
      break;
    case WM_IME_STARTCOMPOSITION: ime_place(); return 0;
    case WM_IME_COMPOSITION: ime_composition(lp); return 0;
    case WM_IME_ENDCOMPOSITION:
      if (ws->marked_len) ime_compose(NULL, 0, 0);
      return 0;
    case WM_DESTROY: place_keep(); exit(0);
  }
  return DefWindowProcW(h, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// Scripted runs (MBUI_SCRIPT=ime|shot): drive the same paths an input method
// takes and save snapshots, as the macOS host does.

static void shot(const char *name) {
  if (!shot_dir) return;
  wchar_t p[1024];
  _snwprintf(p, 1024, L"%ls\\%hs.png", shot_dir, name);
  p[1023] = 0;
  int ok = mb_render_snapshot(p);
  char u[2048];
  WideCharToMultiByte(CP_UTF8, 0, p, -1, u, sizeof u, NULL, NULL);
  fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
  // MBUI_SHOT_SCREEN=1: also what the screen shows (<name>-screen.png)
  const char *sc = getenv("MBUI_SHOT_SCREEN");
  if (sc && *sc == '1') {
    _snwprintf(p, 1024, L"%ls\\%hs-screen.png", shot_dir, name);
    p[1023] = 0;
    fprintf(stdout, "SHOT screen %s\n", mb_screen_snapshot(hwnd, p) ? "ok" : "failed");
  }
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
      case 30: ime_compose(L"ni'hao", 6, 6); break;
      case 40: shot("02-composing"); break;
      case 41: ime_commit(L"\x4f60\x597d", 2); break;  // 你好
      case 42: ime_commit(L"\xff0cMoonBit ", 9); break;  // ，MoonBit
      case 43: ime_compose(L"shi'jie", 7, 3); break;
      case 50: shot("03-composing-2"); break;
      case 51: ime_commit(L"\x4e16\x754c \xd83d\xdc4b", 5); break;  // 世界 👋
      case 60: shot("04-typed"); break;
      case 61: mb_cb.key(7, 0); break;
      case 100: shot("05-sent"); break;
      case 101:
        for (int i = 0; i < 40; i++) mb_cb.wheel(300, 300, 0, -120, 0);
        break;
      case 140: shot("06-scrolled"); break;
      case 141: exit(0);
    }
    ws->want_frame = 1;
  } else if (strcmp(script, "photos") == 0) {
    // decodes take a while: a shot once they have had some, then the keys
    // that scroll the list under the pointer, as a keyboard sends them
    static int phase;
    static double at;
    double now = mb_now_ms();
    if (!at) at = now;
    if (now - at > 4000) {
      at = now;
      char name[16];
      snprintf(name, sizeof name, "photos-%d", phase + 1);
      shot(name);
      fprintf(stdout, "memory at %s: %.1f MB\n", name, mb_host_mem_bytes() / 1048576.0);
      fflush(stdout);
      mb_cb.pointer(1, 300, 300, 0);
      if (phase == 0) for (int i = 0; i < 3; i++) SendMessageW(hwnd, WM_KEYDOWN, VK_NEXT, 0);
      if (phase == 1) SendMessageW(hwnd, WM_KEYDOWN, VK_END, 0);
      if (phase == 2) exit(0);
      phase++;
    }
    ws->want_frame = 1;
  } else if (strcmp(script, "shot") == 0) {
    // from the 30th frame, once the native views have opened (loaded or failed) and their pictures are taken anew;
    // 30 s at most
    static int snapped, done;
    static double since;
    if (step >= 30 && !done) {
      if (!since) since = mb_now_ms();
      int late = mb_now_ms() - since > 30000;
      if (late || !mb_views_busy()) {
        if (!snapped && mb_views_count() > 0 && !late) {
          mb_views_snap_all();
          snapped = 1;
        } else {
          if (late) fprintf(stdout, "shot: native views still busy after 30 s\n");
          shot(getenv("MBUI_SHOT_NAME") ? getenv("MBUI_SHOT_NAME") : "main");
          done = step;
        }
      }
    } else if (done && step > done) {
      exit(0);
    }
    ws->want_frame = 1;
  }
}

// ---------------------------------------------------------------------------
// The host API MoonBit calls

void mb_host_run(moonbit_string_t title, mb_frame_fn frame, mb_pointer_fn pointer_fn,
                 mb_wheel_fn wheel_fn, mb_key_fn key, mb_text_fn text) {
  mb_cb = (mb_callbacks){frame, pointer_fn, wheel_fn, key, text};
  script = getenv("MBUI_SCRIPT");
  shot_dir = _wgetenv(L"MBUI_SHOT_DIR");
  // (an app's console, its one run and its identity: decided as the program started, win_life.h life_begin)
  SetConsoleOutputCP(CP_UTF8);
  SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  // (OLE's, for the drop target: COM's single-threaded apartment with it)
  OleInitialize(NULL);

  WCHAR *cls = win_class;
  window_class(cls, 300);
  WNDCLASSEXW wc = {sizeof wc};
  wc.lpfnWndProc = wndproc;
  wc.hInstance = GetModuleHandleW(NULL);
  wc.hCursor = LoadCursor(NULL, IDC_ARROW);
  // the program's own icon (its resource 1), as large and as small as the system shows a window's
  wc.hIcon = own_icon(GetSystemMetrics(SM_CXICON));
  wc.hIconSm = own_icon(GetSystemMetrics(SM_CXSMICON));
  wc.lpszClassName = cls;
  RegisterClassExW(&wc);
  int n = Moonbit_array_length(title);
  WCHAR *given = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
  memcpy(given, title, (size_t)n * sizeof(WCHAR));
  // (the app's name, as its identity says it, where it has one: what its taskbar button and Alt+Tab show)
  const WCHAR *t = app_name(given);
  DWORD style = WS_OVERLAPPEDWINDOW;
  // MBUI_WIN=<w>x<h>: the client area's size in points (a phone's, for the narrow layouts); else the app's own
  // (@hostapi.window_setup); 900 x 720 by default
  double ww = setup_w > 0 ? setup_w : 900, wh = setup_h > 0 ? setup_h : 720;
  const char *win = getenv("MBUI_WIN");
  if (win) sscanf(win, "%lfx%lf", &ww, &wh);
  win_slots[0].inset = setup_inset;
  win_slots[0].min_w = setup_min_w;
  win_slots[0].min_h = setup_min_h;
  win_making = 0;
  hwnd = CreateWindowExW(0, cls, t, style, CW_USEDEFAULT, CW_USEDEFAULT, (int)ww, (int)wh, NULL, NULL,
                         wc.hInstance, NULL);
  win_making = -1;
  win_slots[0].h = hwnd;
  // that client area at the monitor's scale
  UINT dpi = GetDpiForWindow(hwnd);
  ws->scale = win_scale(hwnd);
  RECT r = {0, 0, (LONG)lround(ww * ws->scale), (LONG)lround(wh * ws->scale)};
  window_for_client(&r, dpi, setup_inset);
  // (SWP_FRAMECHANGED: its frame asked for again, an inset window's without the title bar: WM_NCCALCSIZE)
  SetWindowPos(hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER | SWP_FRAMECHANGED);
  ImmAssociateContextEx(hwnd, NULL, 0);  // no input method until an editor has focus
  // (where it was last left, an app's: win_life.h place_put_back)
  int show = place_put_back();
  if (!mb_render_init(hwnd)) exit(1);
  // (held: out of sight till the app shows it, mb_host_window_show; shown at once where DWM cannot cloak it)
  if (window_held && !window_shown && !cloak(hwnd, TRUE)) window_shown = 1;
  ShowWindow(hwnd, show);
  life_start(t);
  drop_start(0);
  free(given);
  ws->want_frame = 1;

  for (;;) {
    MSG m, move_msg;
    int has_move = 0;
    double drain_began = mb_now_ms();
    // Coalesce WM_MOUSEMOVE within each message batch before dispatching (flushing before any other message to keep
    // exact ordering), and bound continuous draining once a frame is owed so high-polling-rate mice cannot re-trigger
    // synthesized WM_MOUSEMOVE inside PeekMessageW and starve frames_round().
    while (PeekMessageW(&m, NULL, 0, 0, PM_REMOVE)) {
      if (m.message == WM_QUIT) exit(0);
      if (m.message == WM_MOUSEMOVE) {
        if (has_move && move_msg.hwnd != m.hwnd) {
          TranslateMessage(&move_msg);
          DispatchMessageW(&move_msg);
        }
        move_msg = m;
        has_move = 1;
      } else {
        if (has_move) {
          has_move = 0;
          TranslateMessage(&move_msg);
          DispatchMessageW(&move_msg);
        }
        TranslateMessage(&m);
        DispatchMessageW(&m);
      }
      if (any_want_frame() && mb_now_ms() - drain_began >= 4.0) break;
    }
    if (has_move) {
      TranslateMessage(&move_msg);
      DispatchMessageW(&move_msg);
    }
    double now = mb_now_ms();
    if (wake_at >= 0 && now >= wake_at) {
      wake_at = -1;
      mb_host_request_frame();
    }
    // (each window's that wants one, then the display waited for: win_render.cpp mb_render_pace)
    if (frames_round()) continue;
    DWORD timeout = wake_at < 0 ? INFINITE : (DWORD)ceil(wake_at - now);
    // (the frames stopped: the next is no later than its time for what the one before took)
    last_begin = -1;
    MsgWaitForMultipleObjectsEx(0, NULL, timeout, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
  }
}

double mb_host_now(void) { return mb_now_ms(); }

// The time of day (host_native.mbt's wall_ms): FILETIME's 100 ns since 1601, from 1970 in ms.
double mb_host_wall_ms(void) {
  FILETIME ft;
  GetSystemTimeAsFileTime(&ft);
  ULARGE_INTEGER u;
  u.LowPart = ft.dwLowDateTime;
  u.HighPart = ft.dwHighDateTime;
  return (double)(u.QuadPart - 116444736000000000ULL) / 10000.0;
}

// how far local time is ahead of UTC then, in minutes (@hostapi.utc_offset_min)
int32_t mb_host_utc_offset_min(double at_ms) {
  __time64_t s = (__time64_t)(at_ms / 1000.0);
  struct tm local, utc;
  if (_localtime64_s(&local, &s) != 0 || _gmtime64_s(&utc, &s) != 0) return 0;
  return (int32_t)((_mkgmtime64(&local) - _mkgmtime64(&utc)) / 60);
}

double mb_host_event_time(void) { return event_t; }

double mb_host_frame_late(void) { return frame_late; }

int32_t mb_host_platform(void) { return 3; }

// A frame asked for: of every window of the run where there are several (what changed may be any's: each draws only
// what changed of its own), else the one.
void mb_host_request_frame(void) {
  for (int k = 0; k < MB_WINS; k++)
    if (k == 0 || win_slots[k].h) win_slots[k].want_frame = 1;
}

void mb_app_wake(void) { PostMessageW(hwnd, WM_APP, 0, 0); }

// A message posted from outside the frames (post.h), on whatever thread: the app told on the window's thread
// (told_between), which takes what changes only signals (a remote screen's frame) without a frame.
static void mb_post_wake(void) { PostMessageW(hwnd, WM_MB_POSTED, 0, 0); }

void mb_app_streamed(int id) { PostMessageW(hwnd, WM_MB_STREAMED, (WPARAM)id, 0); }
static void mb_app_picked(void) { PostMessageW(hwnd, WM_MB_PICKED, 0, 0); }
void mb_app_told(int kind, int id) { PostMessageW(hwnd, WM_MB_TOLD, (WPARAM)kind, (LPARAM)id); }

void mb_app_call(void (*fn)(void *), void *arg) { PostMessageW(hwnd, WM_MB_CALL, (WPARAM)fn, (LPARAM)arg); }

void *mb_app_hwnd(void) { return hwnd; }
int mb_app_wid(void) { return win_active; }
void *mb_app_hwnd_now(void) { return ws->h; }
void *mb_app_hwnd_of(int wid) { return wid >= 0 && wid < MB_WINS ? win_slots[wid].h : NULL; }

// ---- the windows of one run (win_use, above) ----

// Window `wid` gone (closed by the person, or by the app: mb_host_windows' 3; its WM_DESTROY): its views taken off it,
// what it drew let go of, the app told between frames (MB_OUTSIDE_WINDOW; one the app closed itself it knows of
// already).
// Where each role's window was last left as it closed (screen pixels, its frame; its normal place where it was
// maximized, minimized or filling its monitor), for the next of the role (win_open): the run's, the most recent kept.
#define ROLES_KEPT 16
static struct {
  char role[64];
  RECT rect;
  ULONGLONG at;
} roles_kept[ROLES_KEPT];
static void role_keep(const WinSlot *w) {
  if (!w->role[0] || !w->h) return;
  RECT r;
  WINDOWPLACEMENT pl;
  memset(&pl, 0, sizeof pl);
  pl.length = sizeof pl;
  if (w->full_screen) {
    r = w->saved_place.rcNormalPosition;
  } else if (IsIconic(w->h) || IsZoomed(w->h) || !GetWindowRect(w->h, &r)) {
    if (!GetWindowPlacement(w->h, &pl)) return;
    r = pl.rcNormalPosition;
  }
  int at = 0;
  for (int i = 0; i < ROLES_KEPT; i++) {
    if (!strcmp(roles_kept[i].role, w->role)) {
      at = i;
      break;
    }
    if (roles_kept[i].at < roles_kept[at].at) at = i;
  }
  snprintf(roles_kept[at].role, sizeof roles_kept[at].role, "%s", w->role);
  roles_kept[at].rect = r;
  roles_kept[at].at = GetTickCount64() | 1;
}
static const RECT *role_kept(const char *role) {
  for (int i = 0; i < ROLES_KEPT; i++)
    if (role[0] && roles_kept[i].at && !strcmp(roles_kept[i].role, role)) return &roles_kept[i].rect;
  return NULL;
}

static void win_closed(int wid) {
  if (wid <= 0 || wid >= MB_WINS || !win_slots[wid].h) return;
  if (win_active == wid) win_use(0);
  role_keep(&win_slots[wid]);
  drop_stop(wid);
  mb_views_forget(wid);
  mb_render_forget(wid);
  win_slot_fresh(&win_slots[wid]);
  // (a bare run whose first was hidden as it closed ends as the last window beside it closes: none is left to be seen)
  int beside = 0;
  for (int k = 1; k < MB_WINS; k++)
    if (win_slots[k].h) beside = 1;
  if (first_hidden_bare && !beside && !IsWindowVisible(hwnd)) PostQuitMessage(0);
  tell_state();
  PostMessageW(hwnd, WM_MB_TOLD, (WPARAM)MB_OUTSIDE_WINDOW, (LPARAM)wid);
}

// UTF-16 `s` (n of its units) as UTF-8, malloc'd (NULL: none)
static char *utf8_of(const WCHAR *s, int n) {
  int m = n > 0 ? WideCharToMultiByte(CP_UTF8, 0, s, n, NULL, 0, NULL, NULL) : 0;
  char *u = (char *)malloc((size_t)m + 1);
  if (!u) return NULL;
  if (m) WideCharToMultiByte(CP_UTF8, 0, s, n, u, m, NULL, NULL);
  u[m] = 0;
  return u;
}

// A window of this run (@hostapi.window_open_id): its id, 0 where none. `what` a spec (a JSON object: role, title, w,
// h, minW, minH, inset, each left out as the first's), else the app's words for what it shows. As large as the first
// is now, down and to the right of it, its title the first's, its top row the app's as the first's, but for what the
// spec says; one of a role where the last of the role was left as it closed (roles_kept), a second of a role open
// beside the first of it down and to the right of the last one opened, never over it. Out of sight (cloaked) till its
// first frame, drawn in the round of frames under way or the next, is on the screen (held_shown_now).
static int win_open(moonbit_string_t what) {
  if (!hwnd || !*win_class) return 0;
  int wid = 0;
  for (int k = 1; k < MB_WINS; k++)
    if (!win_slots[k].h) {
      wid = k;
      break;
    }
  if (!wid) return 0;
  // (its spec, where `what` is one)
  jv spec;
  memset(&spec, 0, sizeof spec);
  int n = what ? Moonbit_array_length(what) : 0;
  char *u = n && what[0] == '{' ? utf8_of(what, n) : NULL;
  const char *at = u;
  if (u && !jparse(&at, &spec, 0)) {
    jv_free(&spec);
    memset(&spec, 0, sizeof spec);
  }
  const jv *inset_v = jget(&spec, "inset");
  WinSlot *w = &win_slots[wid];
  win_slot_fresh(w);
  snprintf(w->role, sizeof w->role, "%s", jtext(&spec, "role"));
  w->min_w = jnum(&spec, "minW", 0) > 0 ? jnum(&spec, "minW", 0) : setup_min_w;
  w->min_h = jnum(&spec, "minH", 0) > 0 ? jnum(&spec, "minH", 0) : setup_min_h;
  w->inset = inset_v && (inset_v->kind == 't' || inset_v->kind == 'f') ? inset_v->kind == 't' : setup_inset;
  static int opened;
  w->opened = ++opened;
  RECT fr;
  GetWindowRect(hwnd, &fr);
  WCHAR title[256];
  const char *given = jtext(&spec, "title");
  if (!*given || !MultiByteToWideChar(CP_UTF8, 0, given, -1, title, 256)) {
    if (!GetWindowTextW(hwnd, title, 256)) title[0] = 0;
  }
  title[255] = 0;
  UINT dpi = GetDpiForWindow(hwnd);
  double k = dpi ? dpi / 96.0 : 1;
  // its size: the spec's (points, a client area at the first's scale, framed as the window's: window_for_client),
  // else the first's
  int x = fr.left + (int)lround(32 * wid * k), y = fr.top + (int)lround(32 * wid * k);
  int cx = fr.right - fr.left, cy = fr.bottom - fr.top;
  double spec_w = jnum(&spec, "w", 0), spec_h = jnum(&spec, "h", 0);
  if (spec_w > 0 || spec_h > 0) {
    RECT c;
    GetClientRect(hwnd, &c);
    RECT r = {0, 0, spec_w > 0 ? (LONG)lround(spec_w * k) : c.right - c.left,
              spec_h > 0 ? (LONG)lround(spec_h * k) : c.bottom - c.top};
    window_for_client(&r, dpi, w->inset);
    cx = r.right - r.left, cy = r.bottom - r.top;
  }
  // its place: down and to the right of the last of its role open now, else where the last of it was left
  const WinSlot *same = NULL;
  for (int i = 1; i < MB_WINS && w->role[0]; i++)
    if (i != wid && win_slots[i].h && !strcmp(win_slots[i].role, w->role) && (!same || win_slots[i].opened > same->opened))
      same = &win_slots[i];
  const RECT *kept = role_kept(w->role);
  if (same) {
    RECT sr;
    GetWindowRect(same->h, &sr);
    int step = (int)lround(28 * (GetDpiForWindow(same->h) / 96.0));
    x = sr.left + step, y = sr.top + step;
  } else if (kept) {
    x = kept->left, y = kept->top, cx = kept->right - kept->left, cy = kept->bottom - kept->top;
  }
  jv_free(&spec);
  free(u);
  win_making = wid;
  HWND h = CreateWindowExW(0, win_class, title, WS_OVERLAPPEDWINDOW, x, y, cx, cy, NULL, NULL, GetModuleHandleW(NULL),
                           NULL);
  win_making = -1;
  if (!h) {
    win_slot_fresh(w);
    return 0;
  }
  w->h = h;
  w->scale = GetDpiForWindow(h) / 96.0;
  // (an inset window's frame without the title bar, as the first's: WM_NCCALCSIZE)
  SetWindowPos(h, NULL, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  ImmAssociateContextEx(h, NULL, 0);
  if (!mb_render_open(wid, h)) {
    win_slot_fresh(w);
    DestroyWindow(h);
    return 0;
  }
  title_dark_of(h);
  drop_start(wid);
  w->held = cloak(h, TRUE) ? 1 : 0;
  ShowWindow(h, SW_SHOW);
  w->want_frame = 1;
  return wid;
}

// The windows of this run (host_native.mbt's `windows`): 0 whether they open in it (yes, but in a window that is a run
// of its own, MBUI_WINDOW), 1 one opened, 2 one to the front, 3 one closed by the app, 4 the window in place now, 5 a
// window's title set to `what` (`wid` -1: the window in place's). 2 with `wid` 0 brings the first back (put away or
// hidden: bring_back).
int32_t mb_host_windows(int32_t op, int32_t wid, moonbit_string_t what) {
  HWND h = wid > 0 && wid < MB_WINS ? win_slots[wid].h : NULL;
  switch (op) {
    case 0: return !window_run();
    case 1: return win_open(what);
    case 2:
      if (wid == 0) {
        if (!hwnd) return 0;
        bring_back();
        return 1;
      }
      if (!h) return 0;
      if (IsIconic(h)) ShowWindow(h, SW_RESTORE);
      SetForegroundWindow(h);
      return 1;
    // (closed after the frame the app asked it in: never in the middle of drawing it)
    case 3:
      if (h) PostMessageW(h, WM_CLOSE, 0, 0);
      return 0;
    case 4: return win_active;
    case 5: {
      int target = wid < 0 ? win_active : wid;
      HWND t = target >= 0 && target < MB_WINS ? win_slots[target].h : NULL;
      if (!t) return 0;
      int n = what ? Moonbit_array_length(what) : 0;
      WCHAR *title = (WCHAR *)calloc((size_t)n + 1, sizeof(WCHAR));
      if (!title) return 0;
      if (n) memcpy(title, what, (size_t)n * sizeof(WCHAR));
      SetWindowTextW(t, title);
      free(title);
      return 1;
    }
    default: return 0;
  }
}

double mb_app_scale(void) { return ws->scale; }

// A frame for what moves on by the clock that needs fewer (@hostapi.frames_paced): not paced here, the next drawn.
void mb_host_frames_paced(double hz) {
  (void)hz;
  mb_host_request_frame();
}

void mb_host_wake_after(double ms) {
  double t = mb_now_ms() + ms;
  if (wake_at < 0 || t < wake_at) wake_at = t;
}

// (the frame as the app gave it, its groups' headers drawn out by the renderer as it takes it: groups.h)
void mb_host_present(double *buf, int32_t count, double r, double g, double b) {
  // (a frame built while the window is not shown: nothing of it on the screen)
  if (!presenting) return;
  // (a window held whose frame this is: shown once the compositor has it, held_shown_now)
  if (mb_render_present(buf, count, r, g, b) && ws->held) ws->held = 2;
}

void mb_host_set_ime(int32_t active, double x, double y, double w, double h, moonbit_string_t text,
                     int32_t a, int32_t b) {
  int was = ws->ime_active;
  ws->ime_active = active != 0;
  ws->caret[0] = x;
  ws->caret[1] = y;
  ws->caret[2] = w;
  ws->caret[3] = h;
  if (ws->ime_active && !was) {
    if (GetFocus() == ws->h) CreateCaret(ws->h, NULL, 1, (int)lround(h * ws->scale));
  } else if (!ws->ime_active && was) {
    DestroyCaret();
  }
  // (the input method given or taken by the field's kind too: mb_host_ime_action, said just before this)
  ime_sync();
  if (!ws->ime_active) ws->marked_len = 0;
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

// a DWORD put on the open clipboard in the format named so
static void clipboard_dword(const WCHAR *format, DWORD v) {
  UINT f = RegisterClipboardFormatW(format);
  HGLOBAL h = f ? GlobalAlloc(GMEM_MOVEABLE, sizeof(DWORD)) : NULL;
  if (!h) return;
  *(DWORD *)GlobalLock(h) = v;
  GlobalUnlock(h);
  if (!SetClipboardData(f, h)) GlobalFree(h);
}

// words on the clipboard; a secret's kept out of the clipboard's history and of the cloud's (Win+V, its sync to the
// person's other devices: the formats Windows reads for that, which other programs' secrets carry too). 1: put there
static int clipboard_words(moonbit_string_t s, int secret) {
  int n = Moonbit_array_length(s), k = 0;
  // other Windows programs expect CR LF
  HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, ((size_t)n * 2 + 1) * sizeof(WCHAR));
  if (!h) return 0;
  WCHAR *p = (WCHAR *)GlobalLock(h);
  for (int i = 0; i < n; i++) {
    if (s[i] == '\n' && (i == 0 || s[i - 1] != '\r')) p[k++] = '\r';
    p[k++] = s[i];
  }
  p[k] = 0;
  GlobalUnlock(h);
  if (!OpenClipboard(hwnd)) {
    GlobalFree(h);
    return 0;
  }
  EmptyClipboard();
  int put = SetClipboardData(CF_UNICODETEXT, h) != NULL;
  if (!put) GlobalFree(h);
  if (put && secret) {
    clipboard_dword(L"ExcludeClipboardContentFromMonitorProcessing", 0);
    clipboard_dword(L"CanIncludeInClipboardHistory", 0);
    clipboard_dword(L"CanUploadToCloudClipboard", 0);
  }
  CloseClipboard();
  return put;
}

void mb_host_clipboard_set(moonbit_string_t s) { clipboard_words(s, 0); }

// The secret this app put on the clipboard, to be taken off: the clipboard's sequence number just after (another
// copy since, the app's or another program's, changes it), 0 for none
static DWORD secret_seq;

// the secret taken off, unless something else was copied since (at the app's end too: `quitting`, its window gone)
static void secret_off(int quitting) {
  if (!secret_seq) return;
  int ours = GetClipboardSequenceNumber() == secret_seq;
  secret_seq = 0;
  if (ours && OpenClipboard(quitting ? NULL : hwnd)) {
    EmptyClipboard();
    CloseClipboard();
  }
  fputs(ours ? "win: the secret copied taken off the clipboard\n" : "win: the secret copied left: something else copied since\n", stdout);
  fflush(stdout);
}
static void secret_off_at_end(void) { secret_off(1); }

// A secret on the clipboard (@hostapi.clipboard_set_secret): kept out of its history and the cloud's; one to be taken
// off (clear_ms: the app does it then, mb_host_clipboard_secret_off) taken off as the app ends before then.
void mb_host_clipboard_secret(moonbit_string_t s, double clear_ms) {
  static int at_end;
  secret_seq = 0;
  if (!clipboard_words(s, 1) || clear_ms <= 0) return;
  secret_seq = GetClipboardSequenceNumber();
  if (!at_end) atexit(secret_off_at_end), at_end = 1;
}

// The last secret copied taken off (@hostapi.clipboard_secret_off), unless something else was copied since.
void mb_host_clipboard_secret_off(void) { secret_off(0); }

// A picture on the clipboard (@hostapi.clipboard_set_image): a PNG's bytes, under "PNG" and as a bitmap
// (win_device.h clipboard_png); what is not a PNG is put nowhere.
void mb_host_clipboard_image(moonbit_bytes_t data) {
  int n = Moonbit_array_length(data);
  static const unsigned char sig[8] = {0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'};
  if (n < 8 || memcmp(data, sig, 8) != 0) return;
  clipboard_png(data, (size_t)n);
}


void mb_host_log(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  int bytes = WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, NULL, 0, NULL, NULL);
  char *u = (char *)malloc((size_t)bytes + 1);
  WideCharToMultiByte(CP_UTF8, 0, (const WCHAR *)s, n, u, bytes, NULL, NULL);
  u[bytes] = 0;
  fprintf(stdout, "%s\n", u);
  fflush(stdout);
  free(u);
  logs_line_wide(LOGS_LOG, (const WCHAR *)s, n);
}

// The app over another app done (@hostapi.over_done): it never is here.
void mb_host_over_done(int32_t open_app) { (void)open_app; }

// A page in a browser's tab over the app (@hostapi.open_tab): the default browser, as open_url.
int32_t mb_host_open_url(moonbit_string_t s);
int32_t mb_host_open_tab(moonbit_string_t s) { return mb_host_open_url(s); }

// What holds the app up while it listens for a browser (@hostapi.hold_words): nothing here, the app runs on.
void mb_host_hold_words(moonbit_string_t channel, moonbit_string_t title, moonbit_string_t body) {
  (void)channel;
  (void)title;
  (void)body;
}

// A URL handed to the system (@hostapi.open_url): ShellExecute, the default browser or the app that takes it; only
// http, https and mailto (nothing ShellExecute would run as a program).
int32_t mb_host_open_url(moonbit_string_t s) {
  int n = Moonbit_array_length(s);
  WCHAR *w = (WCHAR *)malloc(((size_t)n + 1) * sizeof(WCHAR));
  memcpy(w, s, (size_t)n * sizeof(WCHAR));
  w[n] = 0;
  int ok = 0;
  if (_wcsnicmp(w, L"http://", 7) == 0 || _wcsnicmp(w, L"https://", 8) == 0 || _wcsnicmp(w, L"mailto:", 7) == 0) {
    mb_host_log(s);
    ok = (INT_PTR)ShellExecuteW(NULL, L"open", w, NULL, NULL, SW_SHOWNORMAL) > 32;
  }
  free(w);
  return ok;
}

// The word around an offset (@hostapi.word_at): none from the host here yet (the app's own rule, words.mbt).
double mb_host_word_at(moonbit_string_t text, int32_t off) {
  (void)text; (void)off;
  return -1;
}

// Whether the run is on its own clock (host_native.mbt's own_clock): no run here is yet.
int32_t mb_host_own_clock(void) { return 0; }

int32_t mb_host_reduce_motion(void) {
  // the system's "show animations in Windows" off
  BOOL on = TRUE;
  SystemParametersInfoW(SPI_GETCLIENTAREAANIMATION, 0, &on, 0);
  return on ? 0 : 1;
}

// What the host did for the app is done (host_native.mbt's set_outside): kind 1 an image decoded (win_image.cpp), 2 a
// native view ready, failed, or waiting on the app (win_views.cpp); told as each frame begins: on this thread, between
// frames (a PDF's page drawn among the images).
int32_t mb_host_set_outside(mb_outside_fn f) {
  outside_cb = f;
  return 1;
}
// How many of the app's asks are not answered yet, and what they are, as the frame just built left it
// (host_native.mbt's frame_awaiting): nothing here waits on it yet.
void mb_host_frame_awaiting(int32_t awaiting, moonbit_string_t what) {
  (void)awaiting;
  (void)what;
}

int32_t mb_host_bench_mode(void) {
  const char *b = getenv("MBUI_BENCH");
  return b ? atoi(b) : 0;
}

void mb_host_exit(int32_t code) { exit(code); }

void mb_host_set_back(mb_back_fn f) { back_cb = f; }
void mb_host_back_enabled(int32_t on) { back_on = on; }

// The app in front or not (@hostapi.set_app_state), whether the system is set to dark (@hostapi.system_dark), the
// title bar as the app is drawn (@hostapi.set_dark), the app's menus (@hostapi.menu_setup) and its environment
// (@hostapi.env): win_life.h.
// (words as the app sizes them, @hostapi.font_scale: the system's Text size, win_a11y.cpp)
// What the app was started to be used with (@hostapi.native_pointing): touch where the machine has a touch screen ready
// and no mouse, or is a tablet used as one (a convertible folded flat, a detachable off its keyboard); else keyboard
// and mouse. Slate mode (SM_CONVERTIBLESLATEMODE 0) counts only on a machine that can be a tablet, as Chromium reads it
// (IsDeviceUsedAsATablet): not docked, able to turn (a sensor, not a laptop's), a mobile's or a slate's by its power
// role; elsewhere its 0 means nothing (2026-10-26: a desktop PC with a touch digitizer, 0 there, started as touch: Enter
// a new line in the composer, touch's sizes).
#ifndef SM_DIGITIZER
#define SM_DIGITIZER 94
#endif
#ifndef SM_CONVERTIBLESLATEMODE
#define SM_CONVERTIBLESLATEMODE 0x2003
#endif
#ifndef SM_SYSTEMDOCKED
#define SM_SYSTEMDOCKED 0x2004
#endif
#ifndef NID_INTEGRATED_TOUCH
#define NID_INTEGRATED_TOUCH 0x01
#endif
#ifndef NID_EXTERNAL_TOUCH
#define NID_EXTERNAL_TOUCH 0x02
#endif
#ifndef NID_READY
#define NID_READY 0x80
#endif
static int used_as_tablet(void) {
  if (GetSystemMetrics(SM_CONVERTIBLESLATEMODE) != 0 || GetSystemMetrics(SM_SYSTEMDOCKED) != 0) return 0;
  AR_STATE turn;
  if (GetAutoRotationState(&turn) && (turn & (AR_NOT_SUPPORTED | AR_LAPTOP | AR_NOSENSOR))) return 0;
  POWER_PLATFORM_ROLE role = PowerDeterminePlatformRoleEx(POWER_PLATFORM_ROLE_V2);
  return role == PlatformRoleMobile || role == PlatformRoleSlate;
}
int32_t mb_host_native_pointing(void) {
  int digitizer = GetSystemMetrics(SM_DIGITIZER);
  int touch = (digitizer & NID_READY) && (digitizer & (NID_INTEGRATED_TOUCH | NID_EXTERNAL_TOUCH));
  if (!touch) return 2;
  return (!GetSystemMetrics(SM_MOUSEPRESENT) || used_as_tablet()) ? 1 : 2;
}
// Whether a keyboard is at hand (@hostapi.keyboard): a Windows PC's, always.
int32_t mb_host_keyboard(void) { return 1; }
// (the app's widgets for the system's accessibility, @hostapi.a11y_on and a11y_tree: win_a11y.cpp's UI Automation)

// Sharing (@hostapi.share, @hostapi.shared_in): no share sheet here yet; nothing comes in.
int32_t mb_host_share(moonbit_string_t text, moonbit_string_t name, moonbit_string_t mime, moonbit_bytes_t data) {
  (void)text; (void)name; (void)mime; (void)data;
  return 0;
}
moonbit_string_t mb_host_shared_in(void) { return moonbit_make_string_raw(0); }
moonbit_bytes_t mb_host_shared_in_file(int32_t i) { (void)i; return moonbit_make_bytes(0, 0); }

// Updates (@hostapi.app_version, update_fetch, update_apply, update_state): win_update.h.
// A package for the system's installer (@hostapi.install_package): none here, said on the system channel (system.mbt):
// its name as UTF-8, escaped for JSON.
void mb_host_install_package(moonbit_string_t name, moonbit_bytes_t data) {
  (void)data;
  int n = Moonbit_array_length(name);
  int u = WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)name, n, NULL, 0, NULL, NULL);
  char *utf8 = (char *)malloc((size_t)u + 1);
  WideCharToMultiByte(CP_UTF8, 0, (LPCWCH)name, n, utf8, u, NULL, NULL);
  char *out = (char *)malloc((size_t)u * 6 + 64);
  size_t o = (size_t)sprintf(out, "{\"install\":{\"name\":\"");
  for (int i = 0; i < u; i++) {
    unsigned char ch = (unsigned char)utf8[i];
    if (ch == '"' || ch == '\\') out[o++] = '\\', out[o++] = (char)ch;
    else if (ch < 0x20) o += (size_t)sprintf(out + o, "\\u%04x", ch);
    else out[o++] = (char)ch;
  }
  o += (size_t)sprintf(out + o, "\",\"error\":\"unsupported\"}}");
  mb_post("system", out, o, NULL, 0);
  free(out);
  free(utf8);
}

// Turned sideways for a film (@hostapi.set_sideways): a window does not turn.
void mb_host_set_sideways(int32_t on) { (void)on; }
// Let turn as held (@hostapi.set_turnable): a window does not turn, and is not held upright.
int32_t mb_host_set_turnable(int32_t on) { (void)on; return 0; }

// The performance record (@hostapi.perf_state), kept as iOS's is (win_logs.h), in the app's log folder with its other
// log files. No program with no id of its own (a demo) keeps one.
int32_t mb_host_perf_state(void) { return logs_perf_state(); }
void mb_host_set_perf(int32_t on) { logs_set_perf(on); }
void mb_host_perf_line(moonbit_string_t line) {
  if (logs_perf_on) logs_line_wide(LOGS_PERF, (const WCHAR *)line, Moonbit_array_length(line));
}
moonbit_string_t mb_host_perf_where(void) {
  int running = logs_perf_state() >= 0, n = running ? (int)wcslen(logs_dir) : 0;
  moonbit_string_t out = moonbit_make_string_raw(n);
  if (n) memcpy(out, logs_dir, (size_t)n * sizeof(WCHAR));
  return out;
}
double mb_host_perf_size(void) { return logs_perf_bytes; }
// (nothing shares it here, no share sheet: its folder is opened instead, mb_host_perf_open)
moonbit_bytes_t mb_host_perf_read(void) { return moonbit_make_bytes(0, 0); }
// Whether the record's folder can be opened here (go 0), or opened (go 1) (@hostapi.perf_open).
int32_t mb_host_perf_open(int32_t go) { return go ? logs_open() : logs_perf_state() >= 0; }

// Notifications (notify.mbt): the system's toasts, win_notify.cpp.

// Scripted runs' input given to the host (src/ui/drive.mbt): the window's picture saved (4), a notification tapped (6)
// or looked for (7) by its words (win_notify.cpp), the window resized to "<w>x<h>" points (8), the runner's directory
// watched (9); the rest is sent to the app itself.
int32_t mb_host_drive(int32_t kind, moonbit_string_t text) {
  // the directory the run's runner says what it has done in, watched (done_watch.h)
  if (kind == 9) return mb_done_watch(text);
  int n = Moonbit_array_length(text);
  wchar_t w[1024];
  if (n > 1023) n = 1023;
  memcpy(w, text, (size_t)n * sizeof(wchar_t));
  w[n] = 0;
  if (kind == 6 || kind == 7) return mb_notice_drive(kind == 6, w);
  if (kind == 4) {
    int ok = mb_render_snapshot(w);
    char u[2048];
    WideCharToMultiByte(CP_UTF8, 0, w, -1, u, sizeof u, NULL, NULL);
    fprintf(stdout, "SHOT %s %s\n", u, ok ? "ok" : "failed");
    fflush(stdout);
    return 1;
  }
  if (kind == 8) {
    double cw = 0, ch = 0;
    if (swscanf(w, L"%lfx%lf", &cw, &ch) != 2 || cw <= 0 || ch <= 0) return 0;
    UINT dpi = GetDpiForWindow(hwnd);
    RECT r = {0, 0, (LONG)lround(cw * ws->scale), (LONG)lround(ch * ws->scale)};
    window_for_client(&r, dpi, win_slots[0].inset);
    SetWindowPos(hwnd, NULL, 0, 0, r.right - r.left, r.bottom - r.top, SWP_NOMOVE | SWP_NOZORDER);
    fprintf(stdout, "RESIZED %.0fx%.0f\n", cw, ch);
    fflush(stdout);
    ws->want_frame = 1;
    return 1;
  }
  return 0;
}

// The window as the app wants it, asked before `run` (@hostapi.window_setup): with `inset`, no title bar of the
// system's (WM_NCCALCSIZE), the app's top row is it, its buttons the app's.

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

// Whether the app's top row is the window's title bar (an inset window, maximized too, not filling its monitor), the
// window's buttons in it the app's: the window in place's.
int32_t mb_host_window_inset(void) { return ws->inset && !ws->full_screen; }
// The window in place filling its monitor (@hostapi.full_screen), and made to or back: no frame of the system's, its
// monitor's whole rectangle (the taskbar's too); back to its place, its styles and its frame as they were.
int32_t mb_host_full_screen(void) { return ws->h && ws->full_screen ? 1 : 0; }
void mb_host_set_full_screen(int32_t on) {
  HWND h = ws->h;
  if (!h || (on != 0) == ws->full_screen) return;
  if (on) {
    MONITORINFO mi;
    memset(&mi, 0, sizeof mi);
    mi.cbSize = sizeof mi;
    ws->saved_place.length = sizeof ws->saved_place;
    if (!GetWindowPlacement(h, &ws->saved_place) ||
        !GetMonitorInfoW(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST), &mi))
      return;
    ws->saved_style = GetWindowLongPtrW(h, GWL_STYLE);
    ws->saved_ex_style = GetWindowLongPtrW(h, GWL_EXSTYLE);
    ws->full_screen = 1;
    SetWindowLongPtrW(h, GWL_STYLE, ws->saved_style & ~(LONG_PTR)(WS_CAPTION | WS_THICKFRAME));
    SetWindowLongPtrW(h, GWL_EXSTYLE,
                      ws->saved_ex_style & ~(LONG_PTR)(WS_EX_DLGMODALFRAME | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE |
                                                       WS_EX_STATICEDGE));
    SetWindowPos(h, HWND_TOP, mi.rcMonitor.left, mi.rcMonitor.top, mi.rcMonitor.right - mi.rcMonitor.left,
                 mi.rcMonitor.bottom - mi.rcMonitor.top, SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  } else {
    ws->full_screen = 0;
    SetWindowLongPtrW(h, GWL_STYLE, ws->saved_style);
    SetWindowLongPtrW(h, GWL_EXSTYLE, ws->saved_ex_style);
    SetWindowPlacement(h, &ws->saved_place);
    SetWindowPos(h, NULL, 0, 0, 0, 0,
                 SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_FRAMECHANGED);
  }
  ws->want_frame = 1;
}
void mb_host_window_buttons_down(double by, double ms) { (void)by; (void)ms; }

// How round the system draws the window's corners (@hostapi.window_corner): Windows 11's 8 (its build 22000 on: the
// rounding DWM gives every window that does not ask otherwise), none maximised; Windows 10's are square.
double mb_host_window_corner(void) {
  static int build = -1;
  if (build < 0) {
    build = 0;
    typedef LONG(WINAPI * rtl_get_version)(OSVERSIONINFOW *);
    HMODULE nt = GetModuleHandleW(L"ntdll.dll");
    rtl_get_version get = nt ? (rtl_get_version)(void *)GetProcAddress(nt, "RtlGetVersion") : NULL;
    OSVERSIONINFOW v = {sizeof v};
    if (get && get(&v) == 0) build = (int)v.dwBuildNumber;
  }
  if (build < 22000 || !ws->h || IsZoomed(ws->h) || ws->full_screen) return 0;
  return 8;
}

// Each corner (@hostapi.window_corner_at): all alike.
double mb_host_window_corner_at(int k) {
  (void)k;
  return mb_host_window_corner();
}

// The press under way moves the window (the app's top row), as the title bar's would (Windows' own move, its snapping
// at the screen's edges among it); the second press of a double click there, the first one the window's too, what the
// title bar's double click does: maximized, or back as it was.
void mb_host_window_drag(void) {
  DWORD now = GetTickCount();
  POINT at;
  // (a finger's: where it is, not the cursor, which it does not move)
  if (event_by == 1) at = ws->touch_screen;
  else GetCursorPos(&at);
  if (ws->drag_time && now - ws->drag_time <= GetDoubleClickTime() &&
      abs(at.x - ws->drag_at.x) <= GetSystemMetrics(SM_CXDOUBLECLK) / 2 &&
      abs(at.y - ws->drag_at.y) <= GetSystemMetrics(SM_CYDOUBLECLK) / 2) {
    ws->drag_time = 0;
    ReleaseCapture();
    ShowWindow(ws->h, IsZoomed(ws->h) ? SW_RESTORE : SW_MAXIMIZE);
    return;
  }
  ws->drag_time = now;
  ws->drag_at = at;
  if (event_by == 1) {
    // (a maximized window stays: its title bar's drag would make it as it was first)
    if (!IsZoomed(ws->h)) ws->touch_moving = 1, ws->touch_move_from = at, GetWindowRect(ws->h, &ws->touch_move_rect);
    return;
  }
  PostMessageW(ws->h, WM_MB_DRAG, 0, 0);
}

// The window's own buttons, the app's in an inset window (@hostapi.window_act): minimized, maximized or back as it was,
// closed as its close button closes it (put away to the notification area: win_life.h).
void mb_host_window_act(int32_t what) {
  if (!ws->h) return;
  if (what == 1) ShowWindow(ws->h, SW_MINIMIZE);
  else if (what == 2) ShowWindow(ws->h, IsZoomed(ws->h) ? SW_RESTORE : SW_MAXIMIZE);
  else if (what == 3) PostMessageW(ws->h, WM_CLOSE, 0, 0);
}

// Whether the window is maximized now (@hostapi.window_zoomed).
int32_t mb_host_window_zoomed(void) { return ws->h && IsZoomed(ws->h) ? 1 : 0; }

// Where the app draws the window's maximize button this frame, in points (@hostapi.window_snap): hit there as the
// title bar's own (WM_NCHITTEST); w 0, none.
void mb_host_window_snap(double x, double y, double w, double h) {
  if (w <= 0 || h <= 0) {
    SetRectEmpty(&ws->snap_px);
    if (!ws->snap_held) snap_set(0);
    return;
  }
  ws->snap_px.left = (LONG)lround(x * ws->scale);
  ws->snap_px.top = (LONG)lround(y * ws->scale);
  ws->snap_px.right = (LONG)lround((x + w) * ws->scale);
  ws->snap_px.bottom = (LONG)lround((y + h) * ws->scale);
}

// How the pointer stands on it, which the host has (@hostapi.window_snap_state).
int32_t mb_host_window_snap_state(void) { return ws->snap_state; }

// The pointer's shape (@hostapi.set_cursor), shown at once where it is over the window.
// The number on the app's icon (@hostapi.set_badge): its taskbar button's overlay (win_notify.cpp).
void mb_host_set_badge(int32_t n) { mb_win_badge(hwnd, n); }
// The keys held now (@hostapi.mods_held), as a key's are told.
int32_t mb_host_mods_held(void) { return mods_now(); }

void mb_host_set_cursor(int32_t kind) {
  ws->cursor_kind = kind;
  POINT p;
  if (GetCursorPos(&p) && WindowFromPoint(p) == ws->h) SetCursor(LoadCursor(NULL, cursor_name(kind)));
}

// Windows' transparency effects (Settings > Personalization > Colors) turned off: glass drawn solid.
int32_t mb_host_reduce_transparency(void) {
  DWORD v = 1, n = sizeof v;
  if (RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                   L"EnableTransparency", RRF_RT_REG_DWORD, NULL, &v, &n) != ERROR_SUCCESS)
    return 0;
  return v == 0;
}

// Windows' high contrast (Settings > Accessibility > Contrast themes) on: lines and quiet words drawn stronger.
int32_t mb_host_increase_contrast(void) {
  HIGHCONTRASTW hc = {sizeof hc};
  if (!SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof hc, &hc, 0)) return 0;
  return (hc.dwFlags & HCF_HIGHCONTRASTON) ? 1 : 0;
}

// (no heat of the machine Windows tells an app of: never slowed)
int32_t mb_host_thermal_throttled(void) { return 0; }

// The CPU's time the whole process has had, every thread's (@hostapi.cpu_ms: MBUI_PROBE's share of a CPU), in ms.
double mb_host_cpu_ms(void) {
  FILETIME made, ended, kernel, user;
  if (!GetProcessTimes(GetCurrentProcess(), &made, &ended, &kernel, &user)) return -1;
  ULARGE_INTEGER k = {.LowPart = kernel.dwLowDateTime, .HighPart = kernel.dwHighDateTime};
  ULARGE_INTEGER u = {.LowPart = user.dwLowDateTime, .HighPart = user.dwHighDateTime};
  return (double)(k.QuadPart + u.QuadPart) / 10000.0;
}

// The CPU time of the calling thread (@hostapi.thread_cpu_ms), in ms (-1: unsupported).
double mb_host_thread_cpu_ms(void) {
  FILETIME create, exit, kernel, user;
  if (!GetThreadTimes(GetCurrentThread(), &create, &exit, &kernel, &user)) return -1.0;
  ULARGE_INTEGER k = {.LowPart = kernel.dwLowDateTime, .HighPart = kernel.dwHighDateTime};
  ULARGE_INTEGER u = {.LowPart = user.dwLowDateTime, .HighPart = user.dwHighDateTime};
  return (double)(k.QuadPart + u.QuadPart) / 10000.0;
}

// The display's refresh rate in Hz (@hostapi.display_hz; 0: unknown).
double mb_host_display_hz(void) {
  double period = display_period();
  return period > 0.0 ? 1000.0 / period : 0.0;
}

double mb_host_mem_bytes(void) {
  PROCESS_MEMORY_COUNTERS_EX pmc = {sizeof pmc};
  if (!K32GetProcessMemoryInfo(GetCurrentProcess(), (PROCESS_MEMORY_COUNTERS *)&pmc, sizeof pmc)) return 0;
  return (double)pmc.PrivateUsage;
}


// A sign-in in the browser that comes back here (host_native.mbt `browser_login`): win_browser_login.c.

// Files picked (pick.mbt) and let go on the window (drop.mbt): win_files.h.

// The gallery (gallery.mbt): none on this host; no photo of it picked.
int32_t mb_host_gallery_access(void) { return -1; }
void mb_host_gallery_ask(void) {}
int32_t mb_host_gallery_answers(void) { return 0; }
int32_t mb_host_gallery_read(void) { return 0; }
int32_t mb_host_gallery_read_state(int32_t id) { (void)id; return -1; }
moonbit_string_t mb_host_gallery_read_rows(int32_t id) { (void)id; return moonbit_make_string_raw(0); }
void mb_host_gallery_read_end(int32_t id) { (void)id; }
int32_t mb_host_pick_photo(moonbit_string_t src) { (void)src; return 0; }

// Native views over the canvas: win_views.cpp. PDFs (host_native.mbt): win_image.cpp, Windows.Data.Pdf's. (Saving a
// file: at the end, with keep.mbt's.)
int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data);  // below, with keep.mbt's

// ---------------------------------------------------------------------------
// Files kept (keep.mbt) and saved (save_file): into the Downloads known folder (MBUI_DOWNLOADS_DIR instead, for
// scripted runs), either way (no save dialog yet); a name taken gets " (2)", " (3)"… before its extension. Written at
// once, so each keep is answered as it starts.
#include <shlobj.h>
#include <knownfolders.h>
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")

// A file shown chosen in its folder in Explorer (@hostapi.reveal_file: 在资源管理器中显示), or whether that can be
// done here (go 0): it can. Only a file that is there; a scripted run (MBUI_SCRIPT) says it on the log alone.
int32_t mb_host_reveal_file(moonbit_string_t s, int32_t go) {
  if (!go) return 1;
  int n = Moonbit_array_length(s);
  if (n <= 0) return 0;
  WCHAR *w = (WCHAR *)malloc(((size_t)n + 1) * sizeof(WCHAR));
  memcpy(w, s, (size_t)n * sizeof(WCHAR));
  w[n] = 0;
  for (int i = 0; i < n; i++) if (w[i] == L'/') w[i] = L'\\';
  int ok = 0;
  if (GetFileAttributesW(w) != INVALID_FILE_ATTRIBUTES) {
    mb_host_log(s);
    if (getenv("MBUI_SCRIPT")) {
      ok = 1;
    } else {
      PIDLIST_ABSOLUTE item = ILCreateFromPathW(w);
      if (item) {
        // (COM on this thread for the shell, as it may not be yet; a mode it already has is kept)
        HRESULT com = CoInitializeEx(NULL, COINIT_APARTMENTTHREADED);
        ok = SUCCEEDED(SHOpenFolderAndSelectItems(item, 0, NULL, 0));
        if (SUCCEEDED(com)) CoUninitialize();
        ILFree(item);
      }
    }
  }
  free(w);
  return ok;
}

// where downloads go: MBUI_DOWNLOADS_DIR, else the Downloads known folder; made if it is not there
static int keep_dir(wchar_t *dir) {
  const wchar_t *over = _wgetenv(L"MBUI_DOWNLOADS_DIR");
  if (over && *over) {
    lstrcpynW(dir, over, MAX_PATH);
  } else {
    PWSTR p = NULL;
    if (FAILED(SHGetKnownFolderPath(&FOLDERID_Downloads, 0, NULL, &p))) return 0;
    lstrcpynW(dir, p, MAX_PATH);
    CoTaskMemFree(p);
  }
  CreateDirectoryW(dir, NULL);
  return 1;
}

// the app's name for a file made safe for a folder (no separators or reserved characters, never empty)
static void keep_safe(moonbit_string_t name, wchar_t *n) {
  int len = Moonbit_array_length(name), k = 0;
  for (int i = 0; i < len && k < 200; i++) {
    wchar_t ch = (wchar_t)name[i];
    n[k++] = (ch < 32 || wcschr(L"\\/:*?\"<>|", ch)) ? L'_' : ch;
  }
  n[k] = 0;
  if (k == 0 || !wcscmp(n, L".") || !wcscmp(n, L"..")) lstrcpynW(n, L"file", MAX_PATH);
}

// the i-th name tried in `dir` for `n`: n, then "base (2).ext"…
static void keep_name(const wchar_t *dir, const wchar_t *n, int i, wchar_t *out) {
  wchar_t base[MAX_PATH], ext[MAX_PATH] = {0};
  lstrcpynW(base, n, MAX_PATH);
  wchar_t *dot = wcsrchr(base, L'.');
  if (dot && dot != base) {
    lstrcpynW(ext, dot, MAX_PATH);
    *dot = 0;
  }
  if (i == 1) _snwprintf(out, MAX_PATH, L"%ls\\%ls", dir, n);
  else _snwprintf(out, MAX_PATH, L"%ls\\%ls (%d)%ls", dir, base, i, ext);
  out[MAX_PATH - 1] = 0;
}

static int keep_put(HANDLE f, const char *b, DWORD left) {
  DWORD put = 0;
  while (left > 0) {
    if (!WriteFile(f, b, left, &put, NULL)) return 0;
    b += put;
    left -= put;
  }
  return 1;
}

int32_t mb_host_save_file(moonbit_string_t name, moonbit_bytes_t data) {
  wchar_t dir[MAX_PATH], n[MAX_PATH], path[MAX_PATH];
  if (!keep_dir(dir)) return 0;
  keep_safe(name, n);
  for (int i = 1; i < 10000; i++) {
    keep_name(dir, n, i, path);
    HANDLE f = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) {
      if (GetLastError() == ERROR_FILE_EXISTS) continue;
      return 0;
    }
    int ok = keep_put(f, (const char *)data, (DWORD)Moonbit_array_length(data));
    CloseHandle(f);
    if (!ok) DeleteFileW(path);
    return ok;
  }
  return 0;
}

// each keep: its state (0 keeping, 1 kept, -1 failed), its name, its part file in the temporary directory while its
// bytes come, where it went
typedef struct {
  int state;
  HANDLE part;
  wchar_t name[MAX_PATH], tmp[MAX_PATH], where[MAX_PATH];
} win_keep;
static win_keep *keeps;
static int nkeeps = 1;  // ids from 1

static win_keep *keep_of(int32_t id) { return id > 0 && id < nkeeps ? &keeps[id] : NULL; }

static void keep_fail(win_keep *k) {
  if (k->part != INVALID_HANDLE_VALUE) CloseHandle(k->part);
  k->part = INVALID_HANDLE_VALUE;
  DeleteFileW(k->tmp);
  k->state = -1;
}

int32_t mb_host_keep_begin(moonbit_string_t name, moonbit_string_t mime, int32_t way) {
  (void)mime;
  (void)way;
  win_keep *grown = realloc(keeps, sizeof(win_keep) * (nkeeps + 1));
  if (!grown) return 0;
  keeps = grown;
  int id = nkeeps++;
  win_keep *k = &keeps[id];
  memset(k, 0, sizeof *k);
  keep_safe(name, k->name);
  wchar_t t[MAX_PATH];
  GetTempPathW(MAX_PATH, t);
  _snwprintf(k->tmp, MAX_PATH, L"%lsmbui-keep-%lu-%d.part", t, (unsigned long)GetCurrentProcessId(), id);
  k->tmp[MAX_PATH - 1] = 0;
  k->part = CreateFileW(k->tmp, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_TEMPORARY, NULL);
  k->state = k->part == INVALID_HANDLE_VALUE ? -1 : 0;
  return id;
}

int32_t mb_host_keep_append(int32_t id, moonbit_bytes_t data) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 0 || k->part == INVALID_HANDLE_VALUE) return 0;
  if (keep_put(k->part, (const char *)data, (DWORD)Moonbit_array_length(data))) return 1;
  keep_fail(k);
  return 0;
}

// finished: the part file moved into Downloads under a name not taken (a copy across volumes)
void mb_host_keep_finish(int32_t id) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 0 || k->part == INVALID_HANDLE_VALUE) return;
  CloseHandle(k->part);
  k->part = INVALID_HANDLE_VALUE;
  wchar_t dir[MAX_PATH];
  if (keep_dir(dir)) {
    for (int i = 1; i < 10000; i++) {
      keep_name(dir, k->name, i, k->where);
      if (GetFileAttributesW(k->where) != INVALID_FILE_ATTRIBUTES) continue;
      if (MoveFileExW(k->tmp, k->where, MOVEFILE_COPY_ALLOWED)) {
        k->state = 1;
        ws->want_frame = 1;
        return;
      }
      if (GetLastError() != ERROR_ALREADY_EXISTS && GetLastError() != ERROR_FILE_EXISTS) break;
    }
  }
  k->where[0] = 0;
  keep_fail(k);
  ws->want_frame = 1;
}

int32_t mb_host_keep_state(int32_t id) {
  win_keep *k = keep_of(id);
  return k ? k->state : -1;
}

moonbit_string_t mb_host_keep_where(int32_t id) {
  win_keep *k = keep_of(id);
  if (!k || k->state != 1) return moonbit_make_string_raw(0);
  int n = (int)wcslen(k->where);
  moonbit_string_t s = moonbit_make_string_raw(n);
  memcpy(s, k->where, n * sizeof(uint16_t));
  return s;
}

void mb_host_keep_end(int32_t id) {
  win_keep *k = keep_of(id);
  if (k && k->state == 0) keep_fail(k);
  if (k) k->state = -1;
}

// Text in a legacy encoding (charset.mbt): Windows' code pages by IANA's names (those a reader meets), decoded by
// MultiByteToWideChar (a byte with no mapping: U+FFFD).
#include <wctype.h>
static UINT cs_page(moonbit_string_t charset) {
  static const struct { const wchar_t *name; UINT page; } pages[] = {
    {L"gb18030", 54936}, {L"gbk", 936}, {L"gb2312", 936}, {L"big5", 950}, {L"shift_jis", 932},
    {L"euc-kr", 949}, {L"windows-1252", 1252}, {L"iso-8859-1", 28591}, {L"utf-8", 65001},
  };
  int n = Moonbit_array_length(charset);
  wchar_t name[32];
  if (n <= 0 || n >= 32) return 0;
  for (int i = 0; i < n; i++) name[i] = (wchar_t)towlower((wint_t)charset[i]);
  name[n] = 0;
  for (size_t i = 0; i < sizeof pages / sizeof pages[0]; i++)
    if (!wcscmp(name, pages[i].name)) return pages[i].page;
  return 0;
}

int32_t mb_host_charset_known(moonbit_string_t charset) {
  UINT p = cs_page(charset);
  return p && IsValidCodePage(p) ? 1 : 0;
}

moonbit_string_t mb_host_charset_decode(moonbit_bytes_t data, moonbit_string_t charset) {
  UINT p = cs_page(charset);
  int len = Moonbit_array_length(data);
  if (!p || len == 0) return moonbit_make_string_raw(0);
  int n = MultiByteToWideChar(p, 0, (const char *)data, len, NULL, 0);
  if (n <= 0) return moonbit_make_string_raw(0);
  moonbit_string_t s = moonbit_make_string_raw(n);
  MultiByteToWideChar(p, 0, (const char *)data, len, (wchar_t *)s, n);
  return s;
}

// Marks drawn onto an image (marks.mbt): none on this host yet.
int32_t mb_host_marks_start(moonbit_bytes_t image, moonbit_string_t marks) { (void)image; (void)marks; return 0; }
int32_t mb_host_marks_state(int32_t id) { (void)id; return -1; }
moonbit_bytes_t mb_host_marks_png(int32_t id) { (void)id; return moonbit_make_bytes(0, 0); }
