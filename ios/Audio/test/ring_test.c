/*
 * Ring tests, plain C with threads. Runs on Linux and macOS:
 *   cc -std=c11 -O2 -pthread -I ios/Audio ios/Audio/mm_ring.c ios/Audio/test/ring_test.c -o /tmp/ring_test && /tmp/ring_test
 */
#define _POSIX_C_SOURCE 200809L
#include "mm_ring.h"

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static int failures = 0;
#define CHECK(ok, what) do { int _ok = (ok); printf("%s %s\n", _ok ? "PASS" : "FAIL", what); if (!_ok) failures++; } while (0)

static mm_ring R;

/* every frame carries its own index, so order and loss show up */
static void fill_block(float *b, int64_t start, int32_t n) {
    for (int32_t i = 0; i < n; i++) { b[i * 2] = (float) ((start + i) % 1000003); b[i * 2 + 1] = -b[i * 2]; }
}

typedef struct { int64_t total; int32_t block; int32_t rate; } writer_args;

static void *writer(void *p) {
    writer_args *a = p;
    /* like the app's writer thread: a real-time schedule where the OS allows it (Apple) */
    int rt = mm_thread_realtime((int64_t) a->block * 1000000000LL / a->rate, (int64_t) a->block * 500000000LL / a->rate);
    printf("     writer real-time schedule: %s\n", rt == 0 ? "granted" : "not on this system");
    float *b = malloc(sizeof(float) * 2 * a->block);
    int64_t done = 0;
    while (done < a->total) {
        fill_block(b, done, a->block);
        if (mm_ring_write(&R, b, a->block, a->rate) < 0) break;
        done += a->block;
    }
    free(b);
    return NULL;
}

static void sleep_ns(long ns) { struct timespec ts = { ns / 1000000000L, ns % 1000000000L }; nanosleep(&ts, NULL); }

static void *late_reader(void *p) {
    (void) p;
    float out[2 * 256];
    sleep_ns(30000000L);
    mm_ring_read(&R, out, 256);
    return NULL;
}

static void test_wrap_single_thread(void) {
    mm_ring_reset(&R, 4096);
    float in[2 * 1000], out[2 * 1000];
    int64_t pos = 0; int ok = 1;
    /* push far past the ring size so every wrap point is crossed */
    for (int k = 0; k < 200; k++) {
        fill_block(in, pos, 1000);
        if (mm_ring_write(&R, in, 1000, 48000) != 1000) ok = 0;
        mm_ring_read(&R, out, 1000);
        for (int i = 0; i < 1000; i++) if (out[i * 2] != (float) ((pos + i) % 1000003) || out[i * 2 + 1] != -out[i * 2]) ok = 0;
        pos += 1000;
    }
    CHECK(ok, "single thread: 200000 frames through the ring, every frame in order across the wrap");
    CHECK(mm_ring_dry(&R) == 0, "single thread: no clicks when every read finds enough");
}

static void test_short_read_counts_click(void) {
    mm_ring_reset(&R, 512);
    float in[2 * 100], out[2 * 256];
    fill_block(in, 0, 100);
    mm_ring_read(&R, out, 256);
    CHECK(mm_ring_dry(&R) == 0, "a short read before the ring was ever full is not a click");
    /* fill it to the target, then one more block: the writer waits, which marks the ring primed */
    float big[2 * 256]; fill_block(big, 0, 256);
    mm_ring_reset(&R, 256);
    mm_ring_write(&R, big, 256, 48000);
    pthread_t t; pthread_create(&t, NULL, late_reader, NULL);
    mm_ring_write(&R, big, 56, 48000); /* waits until the late reader takes 256 */
    pthread_join(t, NULL);
    CHECK(atomic_load(&R.primed) == 1, "a writer that had to wait marks the ring primed");
    mm_ring_read(&R, out, 200); /* 56 there: short */
    int zeros = 1; for (int i = 56; i < 200; i++) if (out[i * 2] != 0 || out[i * 2 + 1] != 0) zeros = 0;
    CHECK(mm_ring_dry(&R) == 1, "a read that runs out counts one click");
    CHECK(zeros, "the missing part of a short read is silence");
}

static void test_writer_waits_at_target(void) {
    mm_ring_reset(&R, 512);
    float b[2 * 256]; fill_block(b, 0, 256);
    mm_ring_write(&R, b, 256, 48000);
    mm_ring_write(&R, b, 256, 48000);
    pthread_t t; pthread_create(&t, NULL, late_reader, NULL);
    struct timespec t0, t1; clock_gettime(CLOCK_MONOTONIC, &t0);
    mm_ring_write(&R, b, 256, 48000); /* full at 512: must wait for the reader */
    clock_gettime(CLOCK_MONOTONIC, &t1);
    pthread_join(t, NULL);
    double ms = (t1.tv_sec - t0.tv_sec) * 1e3 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    CHECK(ms > 20, "the writer waits while the ring holds its target");
    CHECK(mm_ring_written(&R) - mm_ring_read_pos(&R) <= 512, "the ring never holds more than its target");
}

static void test_dead_stops_writer(void) {
    mm_ring_reset(&R, 256);
    float b[2 * 256]; fill_block(b, 0, 256);
    mm_ring_write(&R, b, 256, 48000);
    mm_ring_mark_dead(&R);
    CHECK(mm_ring_write(&R, b, 256, 48000) == -1, "a dead ring sends the writer back to reopen");
}

/* a real-time reader on its own thread, like Core Audio, pulling 256 frames every 5.33 ms */
static void test_threads_realtime(void) {
    mm_ring_reset(&R, 256 * 3);
    writer_args a = { 48000 * 2, 256, 48000 };
    pthread_t t; pthread_create(&t, NULL, writer, &a);
    sleep_ns(20000000L);
    float out[2 * 256]; int64_t pos = 0; int ok = 1; int reads = 0;
    struct timespec next; clock_gettime(CLOCK_MONOTONIC, &next);
    while (pos < a.total - 256 * 4 && reads < 2000) {
        int64_t before = mm_ring_read_pos(&R);
        mm_ring_read(&R, out, 256);
        int32_t took = (int32_t) (mm_ring_read_pos(&R) - before);
        /* whatever arrived must be the next frames in order; a short read is a click, counted below */
        for (int i = 0; i < took; i++) if (out[i * 2] != (float) ((pos + i) % 1000003)) { ok = 0; break; }
        pos += took;
        reads++;
        /* macOS has no clock_nanosleep: sleep to the next deadline by hand */
        next.tv_nsec += 5333333L;
        while (next.tv_nsec >= 1000000000L) { next.tv_nsec -= 1000000000L; next.tv_sec++; }
        struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        long wait = (next.tv_sec - now.tv_sec) * 1000000000L + (next.tv_nsec - now.tv_nsec);
        if (wait > 0) sleep_ns(wait);
    }
    mm_ring_mark_dead(&R);
    pthread_join(t, NULL);
    CHECK(ok, "two threads at audio pace: 2 seconds of frames arrive whole and in order");
    /* a shared CI machine is not real time: its sleeps overshoot, so allow a few clicks there, never a lot */
    int clicks = mm_ring_dry(&R);
    printf("     clicks: %d in %d reads\n", clicks, reads);
    CHECK(clicks * 20 <= reads, "two threads at audio pace: clicks in under 5% of reads");
}

int main(void) {
    test_wrap_single_thread();
    test_short_read_counts_click();
    test_writer_waits_at_target();
    test_dead_stops_writer();
    test_threads_realtime();
    printf(failures == 0 ? "ALL PASS\n" : "%d FAILED\n", failures);
    return failures == 0 ? 0 : 1;
}
