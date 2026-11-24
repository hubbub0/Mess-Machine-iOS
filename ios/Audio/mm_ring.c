#if !defined(__APPLE__) && !defined(_POSIX_C_SOURCE)
#define _POSIX_C_SOURCE 200809L /* sem_timedwait, clock_gettime under -std=c11 */
#endif
#include "mm_ring.h"

#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

mm_ring *mm_ring_new(void) {
    mm_ring *r = calloc(1, sizeof *r);
    if (r) mm_ring_reset(r, 512);
    return r;
}

void mm_ring_free(mm_ring *r) {
    if (!r) return;
#ifdef __APPLE__
    if (r->wake_ready) semaphore_destroy(mach_task_self(), r->wake);
#else
    if (r->wake_ready) sem_destroy(&r->wake);
#endif
    free(r);
}

static void wake_init(mm_ring *r) {
    if (r->wake_ready) return;
#ifdef __APPLE__
    r->wake_ready = semaphore_create(mach_task_self(), &r->wake, SYNC_POLICY_FIFO, 0) == KERN_SUCCESS;
#else
    r->wake_ready = sem_init(&r->wake, 0, 0) == 0;
#endif
}

static void wake_signal(mm_ring *r) {
#ifdef __APPLE__
    semaphore_signal(r->wake);
#else
    sem_post(&r->wake);
#endif
}

/* Wait up to ns for the reader's signal. */
static void wake_wait(mm_ring *r, int64_t ns) {
#ifdef __APPLE__
    mach_timespec_t t = { (unsigned int) (ns / 1000000000LL), (clock_res_t) (ns % 1000000000LL) };
    semaphore_timedwait(r->wake, t);
#else
    struct timespec t;
    clock_gettime(CLOCK_REALTIME, &t);
    t.tv_nsec += (long) (ns % 1000000000LL);
    t.tv_sec += (time_t) (ns / 1000000000LL) + t.tv_nsec / 1000000000L;
    t.tv_nsec %= 1000000000L;
    while (sem_timedwait(&r->wake, &t) == -1 && errno == EINTR) {}
#endif
}

#ifdef __APPLE__
#include <mach/mach_time.h>
#include <mach/thread_policy.h>
#include <pthread.h>
int mm_thread_realtime(int64_t period_ns, int64_t computation_ns) {
    mach_timebase_info_data_t tb;
    mach_timebase_info(&tb);
    double ticks = (double) tb.denom / (double) tb.numer; /* ticks per ns */
    thread_time_constraint_policy_data_t p;
    p.period = (uint32_t) (period_ns * ticks);
    p.computation = (uint32_t) (computation_ns * ticks);
    p.constraint = (uint32_t) (period_ns * ticks);
    p.preemptible = 1;
    return thread_policy_set(pthread_mach_thread_np(pthread_self()), THREAD_TIME_CONSTRAINT_POLICY,
                             (thread_policy_t) &p, THREAD_TIME_CONSTRAINT_POLICY_COUNT) == KERN_SUCCESS ? 0 : -1;
}
#else
int mm_thread_realtime(int64_t period_ns, int64_t computation_ns) { (void) period_ns; (void) computation_ns; return -1; }
#endif

void mm_ring_reset(mm_ring *r, int32_t fill) {
    wake_init(r);
    atomic_store(&r->waiting, 0);
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
    if (atomic_exchange_explicit(&r->waiting, 0, memory_order_acq_rel)) wake_signal(r);
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
        /* wait for the reader to free room; the timeout (about the time the extra takes to play) is only a backstop */
        int64_t extra = have + frames - t;
        int64_t ns = extra * 1000000000LL / (rate > 0 ? rate : 48000);
        if (ns < 500000) ns = 500000;
        if (ns > 20000000) ns = 20000000;
        if (r->wake_ready) {
            atomic_store_explicit(&r->waiting, 1, memory_order_seq_cst);
            /* look again after saying we wait: room freed in between would otherwise be missed until the timeout */
            int64_t have2 = atomic_load_explicit(&r->wpos, memory_order_relaxed) - atomic_load_explicit(&r->rpos, memory_order_seq_cst);
            if (have2 + frames <= t) { atomic_store(&r->waiting, 0); continue; }
            wake_wait(r, ns);
        } else {
            struct timespec ts = { 0, (long) ns };
            nanosleep(&ts, NULL);
        }
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
