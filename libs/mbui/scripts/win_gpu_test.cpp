// src/host/win_render.cpp's D3D11 timestamp query ring and dropped-frame counting tests on Windows:
//   cl.exe -nologo -EHsc -W3 -WX -D_CRT_SECURE_NO_WARNINGS -Isrc/host scripts/win_gpu_test.cpp \
//     -Foout/gpu/ -Feout/gpu/win_gpu_test.exe \
//     -link d3d11.lib d3dcompiler.lib dcomp.lib dwmapi.lib gdi32.lib user32.lib windowscodecs.lib ole32.lib
//   out/gpu/win_gpu_test.exe
// Verifies:
// 1. Non-blocking 4-slot D3D11 timestamp disjoint query ring produces valid GPU ms (or degrades cleanly on WARP)
//    and recycles slots across multiple frames and gpu_q_free() without leaking or stalling.
// 2. win_count_dropped_step() accurately counts drops during continuous animation, ignores idle pauses
//    (>= 2.5 * display_period), clamps spikes to MB_WIN_DROPPED_CLAMP, and guards non-monotonic counters.
#define MB_NO_MOONBIT_H 1
#ifndef _CRT_SECURE_NO_WARNINGS
#define _CRT_SECURE_NO_WARNINGS
#endif
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef const wchar_t *moonbit_string_t;
typedef uint8_t *moonbit_bytes_t;
static size_t Moonbit_array_length(moonbit_bytes_t) { return 0; }

extern "C" {
const wchar_t *mb_win_env(const wchar_t *) { return NULL; }
const wchar_t *mb_win_app_id(void) { return L""; }
void mb_host_request_frame(void) {}
void *mb_image_srv(int) { return NULL; }
void *mb_stream_srv(int) { return NULL; }
void mb_text_set_scale(double) {}
int mb_views_count(void) { return 0; }
void mb_views_draw_under(uint8_t *, int, int, double) {}
double mb_app_scale(void) { return 1.0; }
}

#include "win_render.cpp"

static int failed = 0;
#define CHECK(c)                                                         \
  do {                                                                   \
    if (!(c)) {                                                          \
      printf("%s:%d: failed: %s\n", __FILE__, __LINE__, #c);             \
      fflush(stdout);                                                    \
      failed = 1;                                                        \
    }                                                                    \
  } while (0)

static void fill_rect_instances(double *inst, int count) {
  memset(inst, 0, (size_t)count * MB_INST * sizeof(double));
  for (int i = 0; i < count; i++) {
    double *p = inst + (size_t)i * MB_INST;
    p[0] = (double)((i % 16) * 8);
    p[1] = (double)((i / 16) * 8);
    p[2] = 8.0;
    p[3] = 8.0;
    p[8] = 0.2;
    p[9] = 0.5;
    p[10] = 0.8;
    p[11] = 1.0;
    p[16] = -1e9;
    p[17] = -1e9;
    p[18] = 1e9;
    p[19] = 1e9;
  }
}

static void test_dropped_step_logic(void) {
  const int64_t freq = 10000000;  // 10 MHz QPC (10000 ticks = 1 ms)
  const double p60 = 1000.0 / 60.0;
  // First sample (has_prev = 0): never counts drops.
  CHECK(win_count_dropped_step(0, 0, 0, 0, 10, 20, 100000, freq, p60) == 0);
  // Continuous 60Hz (dt = 16.67ms < 41.67ms), no drops (d_sync == d_present == 1).
  CHECK(win_count_dropped_step(10, 100, 100000, 1, 11, 101, 266700, freq, p60) == 0);
  // Continuous animation (dt = 33.3ms < 41.67ms), 2 sync refreshes missed (d_sync=3, d_present=1).
  CHECK(win_count_dropped_step(10, 100, 100000, 1, 11, 103, 433000, freq, p60) == 2);
  // Idle pause (dt = 50ms >= 2.5 * 16.67ms): ignored even if d_sync > d_present.
  CHECK(win_count_dropped_step(10, 100, 100000, 1, 11, 104, 600000, freq, p60) == 0);
  // Huge spike within continuous window: clamped to MB_WIN_DROPPED_CLAMP (10).
  CHECK(win_count_dropped_step(10, 100, 100000, 1, 11, 150, 300000, freq, p60) == MB_WIN_DROPPED_CLAMP);
  // Non-monotonic QPC or PresentCount: 0.
  CHECK(win_count_dropped_step(10, 100, 200000, 1, 11, 103, 100000, freq, p60) == 0);
  CHECK(win_count_dropped_step(10, 100, 100000, 1, 10, 103, 200000, freq, p60) == 0);
  // 120Hz continuous (period = 8.33ms, 2.5x = 20.83ms): dt = 16.67ms counts 1 drop, dt = 22ms ignored.
  const double p120 = 1000.0 / 120.0;
  CHECK(win_count_dropped_step(1, 10, 100000, 1, 2, 12, 266700, freq, p120) == 1);
  CHECK(win_count_dropped_step(1, 10, 100000, 1, 2, 13, 320000, freq, p120) == 0);
}

int main(void) {
  // 1. Initial values before any frame.
  CHECK(mb_host_gpu_ms() == -1.0);
  CHECK(mb_host_frames_dropped() == 0);

  // 2. Pure dropped-frame boundary logic.
  test_dropped_step_logic();

  // 3. D3D11 timestamp query ring on WARP offscreen device.
  mb_render_init_offscreen(128.0, 128.0, 1.0);
  CHECK(dev != NULL && ctx != NULL && rtv != NULL);
  if (!dev || !ctx || !rtv) return 1;

  static double inst[32 * MB_INST];
  fill_rect_instances(inst, 32);

  for (int i = 0; i < 8; i++) {
    CHECK(submit(inst, 32, 1.0, 1.0, 1.0) == 1);
    ctx->Flush();
  }
  // Poll until WARP finishes queued work (bounded spin with Sleep(1) only in test harness after Flush).
  for (int tries = 0; tries < 50; tries++) {
    gpu_q_poll();
    int any_in_flight = 0;
    for (int i = 0; i < MB_GPU_Q_SLOTS; i++) any_in_flight |= gpu_q[i].in_flight;
    if (!any_in_flight) break;
    Sleep(1);
  }
  if (gpu_q_ok) {
    int any_in_flight = 0;
    for (int i = 0; i < MB_GPU_Q_SLOTS; i++) any_in_flight |= gpu_q[i].in_flight;
    CHECK(any_in_flight == 0);
    // On WARP, timestamp queries normally return >= 0.0 (unless Disjoint=TRUE, in which case -1.0 without crash).
    double gms = mb_host_gpu_ms();
    CHECK(gms >= 0.0 || gms == -1.0);
    printf("win_gpu: warp gpu_ms=%.3f\n", gms);
  } else {
    CHECK(mb_host_gpu_ms() == -1.0);
    printf("win_gpu: timestamp queries unsupported on adapter (graceful fallback)\n");
  }

  // 4. gpu_q_free() cleans up and next submit() re-initializes cleanly.
  gpu_q_free();
  for (int i = 0; i < MB_GPU_Q_SLOTS; i++) {
    CHECK(gpu_q[i].disjoint == NULL && gpu_q[i].ts_begin == NULL && gpu_q[i].ts_end == NULL);
  }
  CHECK(submit(inst, 16, 1.0, 1.0, 1.0) == 1);
  ctx->Flush();
  gpu_q_free();

  if (failed) return 1;
  printf("win_gpu: ok\n");
  return 0;
}
