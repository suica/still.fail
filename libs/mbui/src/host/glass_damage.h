// Close host-added dirty rectangles over every glass capture they meet. The app's @damage does the same for its own
// rectangles, but adaptive settle frames are added by the hosts after that calculation.
#ifndef MB_GLASS_DAMAGE_H
#define MB_GLASS_DAMAGE_H

#include <math.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct {
  float id;
  double x0, y0, x1, y1, blur, refract, rim;
} MBGlassDamage;

// Rectangles are x, y, width, height in points. Returns 0 on allocation failure so the caller can redraw the whole
// frame. Bounds conservatively contain grab_of's captures, with padding for host rounding.
static int mb_glass_damage_expand(const float *f, int32_t count, double rects[][4], int n,
                                  double width, double height, double scale) {
  int total = 0;
  for (int32_t i = 0; i < count; i++) if (f[(size_t)i * MB_INST + 20] < 0.0f) total++;
  if (!total || !n) return 1;
  MBGlassDamage *groups = (MBGlassDamage *)malloc((size_t)total * sizeof(*groups));
  if (!groups) return 0;
  int ng = 0;
  for (int32_t i = 0; i < count; i++) {
    const float *a = f + (size_t)i * MB_INST;
    if (a[20] >= 0.0f) continue;
    int kind = (int)(a[5] + 0.5f);
    double x0 = kind == 6 ? a[0] : fmax(a[0], a[16]);
    double y0 = kind == 6 ? a[1] : fmax(a[1], a[17]);
    double x1 = kind == 6 ? a[0] + a[2] : fmin(a[0] + a[2], a[18]);
    double y1 = kind == 6 ? a[1] + a[3] : fmin(a[1] + a[3], a[19]);
    double blur = kind == 6 && a[7] < 0.0f ? 0.0 : fabs(a[7]);
    double refract = kind == 6 ? fmax(0.0, a[21] * (1.0 + fabs(a[22]))) : 0.0;
    double rim = kind == 6 ? fmax(a[23], 0.0) : 0.0;
    int k = 0;
    while (k < ng && groups[k].id != a[20]) k++;
    if (k == ng) {
      MBGlassDamage g = {a[20], x0, y0, x1, y1, blur, refract, rim};
      groups[ng++] = g;
    } else {
      MBGlassDamage *g = &groups[k];
      g->x0 = fmin(g->x0, x0); g->y0 = fmin(g->y0, y0);
      g->x1 = fmax(g->x1, x1); g->y1 = fmax(g->y1, y1);
      g->blur = fmax(g->blur, blur); g->refract = fmax(g->refract, refract); g->rim = fmax(g->rim, rim);
    }
  }
  for (int j = 0; j < ng; j++) {
    MBGlassDamage *g = &groups[j];
    // A merged group's first rim and blur can apply to its other shapes; bound all of them conservatively.
    double m = 3.0 * g->blur + g->refract + 2.0 * g->rim + 2.0 + 2.0 / (scale > 0.0 ? scale : 1.0);
    g->x0 = fmax(0.0, g->x0 - m); g->y0 = fmax(0.0, g->y0 - m);
    g->x1 = fmin(width, g->x1 + m); g->y1 = fmin(height, g->y1 + m);
  }
  for (int i = 0; i < n; i++) {
    double x0 = fmax(0.0, rects[i][0]), y0 = fmax(0.0, rects[i][1]);
    double x1 = fmin(width, rects[i][0] + rects[i][2]);
    double y1 = fmin(height, rects[i][1] + rects[i][3]);
    if (x1 <= x0 || y1 <= y0) continue;
    int grew;
    do {
      grew = 0;
      for (int j = 0; j < ng; j++) {
        MBGlassDamage *g = &groups[j];
        if (g->x1 <= g->x0 || g->y1 <= g->y0 || x0 >= g->x1 || x1 <= g->x0 ||
            y0 >= g->y1 || y1 <= g->y0) continue;
        if (x0 > g->x0 || y0 > g->y0 || x1 < g->x1 || y1 < g->y1) {
          x0 = fmin(x0, g->x0); y0 = fmin(y0, g->y0);
          x1 = fmax(x1, g->x1); y1 = fmax(y1, g->y1);
          grew = 1;
        }
      }
    } while (grew);
    rects[i][0] = x0; rects[i][1] = y0; rects[i][2] = x1 - x0; rects[i][3] = y1 - y0;
  }
  free(groups);
  return 1;
}
#endif
