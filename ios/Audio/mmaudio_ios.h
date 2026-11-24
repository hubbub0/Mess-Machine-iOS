/*
 * Mess Machine's Core Audio output: the iOS twin of Android's mmaudio.c (hubbub0/Mess-Machine,
 * app/src/main/cpp/mmaudio.c). Same calls, same meaning:
 *
 *   mm_open(rate, fill)        open and start; returns the device's frames per callback, or a negative number
 *   mm_write(buf, frames, rate) one block from the engine's thread; waits while the ring holds its target; -1 = reopen
 *   mm_set_fill(fill)          how full the writer keeps the ring
 *   mm_clicks()                times the callback found the ring short
 *   mm_behind(now_ns, rate)    frames between the newest one written and the one leaving the speaker; -1 = not known
 *   mm_mode()                  how the sound leaves, for notes and Settings
 *   mm_device_buffer()         frames Core Audio asks for each callback
 *   mm_close()
 *
 * The audio session (category, rate, interruptions, route changes) is set up in Swift before mm_open
 * (ios/App/Audio/AudioHost.swift). The render callback is a RemoteIO unit; it only copies from the ring.
 */
#ifndef MMAUDIO_IOS_H
#define MMAUDIO_IOS_H

#include <stdint.h>

int32_t mm_open(int32_t rate, int32_t fill);
int32_t mm_write(const float *buf, int32_t frames, int32_t rate);
void mm_set_fill(int32_t fill);
int32_t mm_clicks(void);
int64_t mm_behind(int64_t now_ns, int32_t rate);
const char *mm_mode(void);
int32_t mm_device_buffer(void);
void mm_close(void);

/* iOS only: the session's output latency in frames (AVAudioSession.outputLatency), added to mm_behind. */
void mm_set_output_latency(int32_t frames);
/* iOS only: the media server reset; the writer sees -1 and reopens. */
void mm_mark_dead(void);
/* Nanoseconds on the same clock mm_behind expects (mach_absolute_time, converted). */
int64_t mm_now_ns(void);

#endif
