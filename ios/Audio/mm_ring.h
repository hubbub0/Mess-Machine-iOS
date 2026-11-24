/*
 * The lock-free ring between the engine's thread and the audio callback, the same design as Android's
 * app/src/main/cpp/mmaudio.c in hubbub0/Mess-Machine. Plain C11, no Apple headers, so it is tested on Linux too.
 *
 * One writer thread (the engine) and one reader (the audio callback). All counts are frames; one frame is two
 * floats, left and right, interleaved. Nothing on the reader side allocates, locks or sleeps.
 */
#ifndef MM_RING_H
#define MM_RING_H

#include <stdatomic.h>
#include <stdint.h>

#ifdef __APPLE__
#include <mach/mach.h>
typedef semaphore_t mm_sem;
#else
#include <semaphore.h>
typedef sem_t mm_sem;
#endif

#define MM_RING (1 << 14) /* 16384 frames, about 340 ms at 48 kHz: far more than ever used, so it never wraps over itself */

typedef struct {
    float buf[MM_RING * 2];
    _Atomic int64_t wpos, rpos;
    _Atomic int32_t target;  /* how full the writer keeps the ring */
    _Atomic int32_t dry;     /* reads that found the ring short: a click */
    _Atomic int32_t dead;    /* the output stopped for good (media reset): the writer gives up and reopens */
    _Atomic int32_t primed;  /* no clicks counted before the first full ring */
    /*
     * The reader wakes a waiting writer the moment it frees room. Sleeping and polling (Android's way) wakes late on
     * Apple systems, which coalesce timers: on a Mac CI runner it ran the ring dry in about a third of reads. Signalling
     * a semaphore is real-time safe (no lock, no allocation).
     */
    _Atomic int32_t waiting;
    mm_sem wake;
    int32_t wake_ready;
} mm_ring;

void mm_ring_reset(mm_ring *r, int32_t fill);

/* A ring on the heap, for callers (Swift tests) that should not lay the struct out themselves. */
mm_ring *mm_ring_new(void);
void mm_ring_free(mm_ring *r);

/* Reader (audio callback): copy n frames out, zero-filling and counting a click when the ring runs short. */
void mm_ring_read(mm_ring *r, float *out, int32_t n);

/* Ask the OS to run the calling (writer) thread on a real-time schedule: it must make each block within period_ns.
 * Returns 0 when granted. Apple only; elsewhere it does nothing and returns -1. */
int mm_thread_realtime(int64_t period_ns, int64_t computation_ns);

/*
 * Writer: write frames, waiting while the ring holds its target. Returns frames written, or -1 when the ring was
 * marked dead. rate only sets how long each wait is.
 */
int32_t mm_ring_write(mm_ring *r, const float *in, int32_t frames, int32_t rate);

void mm_ring_set_fill(mm_ring *r, int32_t fill);
int32_t mm_ring_fill(mm_ring *r);
int64_t mm_ring_written(mm_ring *r);
int64_t mm_ring_read_pos(mm_ring *r);
int32_t mm_ring_dry(mm_ring *r);
void mm_ring_mark_dead(mm_ring *r);

#endif
