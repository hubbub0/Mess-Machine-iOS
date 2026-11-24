/*
 * Core Audio output for Mess Machine on iOS. The engine makes the sound on its own thread and writes each block
 * into the ring (mm_ring.c); the RemoteIO render callback reads the ring. Nothing in the callback allocates,
 * locks, logs or calls into Swift or Kotlin (Kotlin on iOS has a garbage collector that can pause).
 *
 * One stream at a time. All counts are frames (one frame = two floats, left and right, interleaved).
 */
#include "mmaudio_ios.h"
#include "mm_ring.h"

#include <AudioToolbox/AudioToolbox.h>
#include <mach/mach_time.h>
#include <stdatomic.h>

static mm_ring ring;
static AudioComponentInstance unit = NULL;
static _Atomic int32_t device_frames = 0;   /* frames asked for by the last callback */
static _Atomic int32_t out_latency = 0;     /* session output latency, frames */
static _Atomic uint64_t last_host = 0;      /* host time of the last callback's first frame */
static _Atomic int64_t last_rpos = 0;       /* ring read position at that callback */
static mach_timebase_info_data_t tb;

int64_t mm_now_ns(void) {
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (int64_t) ((__uint128_t) mach_absolute_time() * tb.numer / tb.denom);
}

static int64_t host_to_ns(uint64_t h) {
    if (tb.denom == 0) mach_timebase_info(&tb);
    return (int64_t) ((__uint128_t) h * tb.numer / tb.denom);
}

static OSStatus render(void *ref, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *ts, UInt32 bus,
                       UInt32 frames, AudioBufferList *io) {
    (void) ref; (void) bus;
    if (ts && (ts->mFlags & kAudioTimeStampHostTimeValid)) {
        atomic_store_explicit(&last_host, ts->mHostTime, memory_order_relaxed);
        atomic_store_explicit(&last_rpos, mm_ring_read_pos(&ring), memory_order_relaxed);
    }
    atomic_store_explicit(&device_frames, (int32_t) frames, memory_order_relaxed);
    float *out = (float *) io->mBuffers[0].mData;
    mm_ring_read(&ring, out, (int32_t) frames);
    (void) flags;
    return noErr;
}

int32_t mm_open(int32_t rate, int32_t fill) {
    if (unit) return -2;
    mm_ring_reset(&ring, fill);
    atomic_store(&device_frames, 0);
    atomic_store(&last_host, 0);

    AudioComponentDescription d = {0};
    d.componentType = kAudioUnitType_Output;
    d.componentSubType = kAudioUnitSubType_RemoteIO;
    d.componentManufacturer = kAudioUnitManufacturer_Apple;
    AudioComponent comp = AudioComponentFindNext(NULL, &d);
    if (!comp) return -1;
    AudioComponentInstance u = NULL;
    if (AudioComponentInstanceNew(comp, &u) != noErr || !u) return -1;

    /* the engine renders at its own rate: interleaved float stereo at exactly that rate, or nothing */
    AudioStreamBasicDescription f = {0};
    f.mSampleRate = rate;
    f.mFormatID = kAudioFormatLinearPCM;
    f.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
    f.mChannelsPerFrame = 2;
    f.mBitsPerChannel = 32;
    f.mBytesPerFrame = 8;
    f.mFramesPerPacket = 1;
    f.mBytesPerPacket = 8;
    OSStatus e = AudioUnitSetProperty(u, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &f, sizeof f);
    AURenderCallbackStruct cb = { render, NULL };
    if (e == noErr) e = AudioUnitSetProperty(u, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &cb, sizeof cb);
    if (e == noErr) e = AudioUnitInitialize(u);
    if (e == noErr) e = AudioOutputUnitStart(u);
    if (e != noErr) { AudioComponentInstanceDispose(u); return -1; }

    UInt32 maxf = 0, sz = sizeof maxf;
    AudioUnitGetProperty(u, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxf, &sz);
    unit = u;
    /* the real per-callback size shows up with the first callback; until then report the slice limit's floor */
    return maxf > 0 && maxf < 4096 ? (int32_t) maxf : 256;
}

int32_t mm_write(const float *buf, int32_t frames, int32_t rate) {
    if (!unit) return -1;
    return mm_ring_write(&ring, buf, frames, rate);
}

void mm_set_fill(int32_t fill) { mm_ring_set_fill(&ring, fill); }

int32_t mm_clicks(void) { return mm_ring_dry(&ring); }

int64_t mm_behind(int64_t now_ns, int32_t rate) {
    if (!unit) return -1;
    uint64_t h = atomic_load(&last_host);
    if (h == 0) return -1;
    int64_t played = atomic_load(&last_rpos) + (now_ns - host_to_ns(h)) * (int64_t) rate / 1000000000LL;
    return mm_ring_written(&ring) - played + atomic_load(&out_latency);
}

const char *mm_mode(void) { return unit ? "Core Audio (RemoteIO)" : ""; }

int32_t mm_device_buffer(void) { return unit ? atomic_load(&device_frames) : 0; }

void mm_close(void) {
    if (!unit) return;
    mm_ring_mark_dead(&ring);
    AudioOutputUnitStop(unit);
    AudioUnitUninitialize(unit);
    AudioComponentInstanceDispose(unit);
    unit = NULL;
}

void mm_set_output_latency(int32_t frames) { atomic_store(&out_latency, frames > 0 ? frames : 0); }

void mm_mark_dead(void) { mm_ring_mark_dead(&ring); }
