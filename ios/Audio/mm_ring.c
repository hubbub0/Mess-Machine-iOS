#include "mm_ring.h"

#include <stdlib.h>
#include <string.h>
#include <time.h>

mm_ring *mm_ring_new(void) {
    mm_ring *r = calloc(1, sizeof *r);
    if (r) mm_ring_reset(r, 512);
    return r;
}

void mm_ring_free(mm_ring *r) { free(r); }

void mm_ring_reset(mm_ring *r, int32_t fill) {
    atomic_store(&r->wpos, 0);
    atomic_store(&r->rpos, 0);
    atomic_store(&r->dry, 0);
    atomic_store(&r->dead, 0);
    atomic_store(&r->primed, 0);
    atomic_store(&r->target, fill > 0 && fill < MM_RING / 2 ? fill : 512);
}

void mm_ring_read(mm_ring *r, float *out, int32_t n) {
    int64_t rp = atomic_load_explicit(&r->rpos, memory_order_relaxed);
    int64_t w = atomic_load_explicit(&r->wpos, memory_order_acquire);
    int64_t have = w - rp;
    int32_t take = have < n ? (int32_t) have : n;
    int32_t at = (int32_t) (rp & (MM_RING - 1));
    int32_t first = take < MM_RING - at ? take : MM_RING - at;
    memcpy(out, r->buf + at * 2, (size_t) first * 2 * sizeof(float));
    if (take > first) memcpy(out + first * 2, r->buf, (size_t) (take - first) * 2 * sizeof(float));
    if (take < n) {
        memset(out + take * 2, 0, (size_t) (n - take) * 2 * sizeof(float));
        if (atomic_load_explicit(&r->primed, memory_order_relaxed)) atomic_fetch_add(&r->dry, 1);
    }
    atomic_store_explicit(&r->rpos, rp + take, memory_order_release);
}

int32_t mm_ring_write(mm_ring *r, const float *in, int32_t frames, int32_t rate) {
    if (frames <= 0) return 0;
    if (frames > MM_RING / 2) frames = MM_RING / 2;
    for (;;) {
        if (atomic_load(&r->dead)) return -1;
        int64_t have = atomic_load_explicit(&r->wpos, memory_order_relaxed) - atomic_load_explicit(&r->rpos, memory_order_acquire);
        int32_t t = atomic_load_explicit(&r->target, memory_order_relaxed);
        if (have + frames <= t) break;
        if (!atomic_load_explicit(&r->primed, memory_order_relaxed)) atomic_store(&r->primed, 1);
        /* sleep about the time the extra takes to play, at least half a millisecond */
        int64_t extra = have + frames - t;
        int64_t ns = extra * 1000000000LL / (rate > 0 ? rate : 48000);
        if (ns < 500000) ns = 500000;
        if (ns > 20000000) ns = 20000000;
        struct timespec ts = { 0, (long) ns };
        nanosleep(&ts, NULL);
    }
    int64_t w = atomic_load_explicit(&r->wpos, memory_order_relaxed);
    int32_t at = (int32_t) (w & (MM_RING - 1));
    int32_t first = frames < MM_RING - at ? frames : MM_RING - at;
    memcpy(r->buf + at * 2, in, (size_t) first * 2 * sizeof(float));
    if (frames > first) memcpy(r->buf, in + first * 2, (size_t) (frames - first) * 2 * sizeof(float));
    atomic_store_explicit(&r->wpos, w + frames, memory_order_release);
    return frames;
}

void mm_ring_set_fill(mm_ring *r, int32_t fill) {
    if (fill > 0 && fill < MM_RING / 2) atomic_store(&r->target, fill);
}

int32_t mm_ring_fill(mm_ring *r) { return atomic_load(&r->target); }
int64_t mm_ring_written(mm_ring *r) { return atomic_load(&r->wpos); }
int64_t mm_ring_read_pos(mm_ring *r) { return atomic_load(&r->rpos); }
int32_t mm_ring_dry(mm_ring *r) { return atomic_load(&r->dry); }
void mm_ring_mark_dead(mm_ring *r) { atomic_store(&r->dead, 1); }
