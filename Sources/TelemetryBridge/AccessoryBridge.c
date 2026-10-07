#include "TelemetryBridge.h"
#include <CoreAudio/CoreAudio.h>
#include <CoreFoundation/CoreFoundation.h>
#include <spawn.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>

static int property(AudioObjectID id, AudioObjectPropertySelector selector, AudioObjectPropertyScope scope, void *value, UInt32 size) {
    AudioObjectPropertyAddress address = {selector, scope, kAudioObjectPropertyElementMain};
    if (!AudioObjectHasProperty(id, &address)) return 0;
    UInt32 actual = size;
    return AudioObjectGetPropertyData(id, &address, 0, NULL, &actual, value) == noErr && actual == size;
}
static int channels(AudioObjectID id, AudioObjectPropertyScope scope, uint32_t *result) {
    AudioObjectPropertyAddress address = {kAudioDevicePropertyStreamConfiguration, scope, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(id, &address, 0, NULL, &size) != noErr || size < offsetof(AudioBufferList, mBuffers) || size > 65536) return 0;
    AudioBufferList *list = calloc(1, size);
    if (!list) return 0;
    UInt32 actual = size;
    int good = AudioObjectGetPropertyData(id, &address, 0, NULL, &actual, list) == noErr && actual <= size && actual >= offsetof(AudioBufferList, mBuffers);
    uint64_t total = 0;
    if (good) {
        size_t available = (actual - offsetof(AudioBufferList, mBuffers)) / sizeof(AudioBuffer);
        good = list->mNumberBuffers <= available;
        if (good) for (UInt32 i = 0; i < list->mNumberBuffers; i++) total += list->mBuffers[i].mNumberChannels;
        good = good && total <= 4096;
    }
    free(list);
    if (good) *result = (uint32_t)total;
    return good;
}
static void device_name(AudioObjectID id, char *buffer, size_t capacity) {
    CFStringRef name = NULL;
    if (property(id, kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal, &name, sizeof(name)) && name) {
        if (CFGetTypeID(name) == CFStringGetTypeID()) CFStringGetCString(name, buffer, capacity, kCFStringEncodingUTF8);
        CFRelease(name);
    }
}
int mp_read_audio(mp_audio_device *entries, int capacity, int *count, mp_audio_info *info) {
    if (!entries || !count || !info || capacity <= 0 || capacity > 128) return -1;
    *count = 0; memset(info, 0, sizeof(*info));
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 size = 0;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &address, 0, NULL, &size) != noErr || size > 65536 || size % sizeof(AudioDeviceID)) return -1;
    if (!size) return 0;
    AudioDeviceID *devices = calloc(1, size);
    if (!devices) return -1;
    UInt32 actual = size;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &address, 0, NULL, &actual, devices) != noErr || actual > size || actual % sizeof(AudioDeviceID)) { free(devices); return -1; }
    AudioObjectPropertyScope global = kAudioObjectPropertyScopeGlobal, input = kAudioObjectPropertyScopeInput, output = kAudioObjectPropertyScopeOutput;
    if (!property(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultInputDevice, global, &info->default_input, sizeof(uint32_t))) info->failures++;
    if (!property(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultOutputDevice, global, &info->default_output, sizeof(uint32_t))) info->failures++;
    if (!property(kAudioObjectSystemObject, kAudioHardwarePropertyDefaultSystemOutputDevice, global, &info->default_system_output, sizeof(uint32_t))) info->failures++;
    for (UInt32 i = 0; i < actual / sizeof(AudioDeviceID); i++) {
        AudioObjectID id = devices[i];
        if (!id) continue;
        int duplicate = 0;
        for (int j = 0; j < *count; j++) if (entries[j].id == id) duplicate = 1;
        if (duplicate) continue;
        if (*count >= capacity) { info->truncated = 1; break; }
        mp_audio_device d = {.id = id}; UInt32 flag = 0; Float32 level = 0;
        if (property(id, kAudioDevicePropertyDeviceIsAlive, global, &flag, sizeof(flag))) {
            if (!flag) continue;
            d.alive = 1; d.valid_mask |= 1;
        } else info->failures++;
        device_name(id, d.name, sizeof(d.name));
        if (property(id, kAudioDevicePropertyDeviceIsRunningSomewhere, global, &flag, sizeof(flag))) { d.running = flag != 0; d.valid_mask |= 2; }
        if (channels(id, input, &d.input_channels)) d.valid_mask |= 4; else info->failures++;
        if (channels(id, output, &d.output_channels)) d.valid_mask |= 8; else info->failures++;
        if (property(id, kAudioDevicePropertyNominalSampleRate, global, &d.sample_rate, sizeof(double))) d.valid_mask |= 16;
        if (property(id, kAudioDevicePropertyTransportType, global, &d.transport, sizeof(d.transport))) d.valid_mask |= 32;
        if (d.input_channels && property(id, kAudioDevicePropertyVolumeScalar, input, &level, sizeof(level))) { d.input_volume = level; d.valid_mask |= 64; }
        if (d.output_channels && property(id, kAudioDevicePropertyVolumeScalar, output, &level, sizeof(level))) { d.output_volume = level; d.valid_mask |= 128; }
        if (d.input_channels && property(id, kAudioDevicePropertyMute, input, &flag, sizeof(flag))) { d.input_mute = flag != 0; d.valid_mask |= 256; }
        if (d.output_channels && property(id, kAudioDevicePropertyMute, output, &flag, sizeof(flag))) { d.output_mute = flag != 0; d.valid_mask |= 512; }
        // Removal during property reads invalidates the entire device row.
        if (!property(id, kAudioDevicePropertyDeviceIsAlive, global, &flag, sizeof(flag)) || !flag) { info->failures++; continue; }
        entries[(*count)++] = d;
    }
    free(devices); return 0;
}
static double monotonic_seconds(void) {
    struct timespec value; clock_gettime(CLOCK_MONOTONIC, &value);
    return value.tv_sec + value.tv_nsec / 1e9;
}
int mp_read_bluetooth_profile(char *json, uint32_t capacity, uint32_t *length) {
    if (!json || !length || capacity < 2 || capacity > 1048576) return 3;
    *length = 0;
    int pipes[2]; if (pipe(pipes)) return 3;
    fcntl(pipes[0], F_SETFD, FD_CLOEXEC); fcntl(pipes[1], F_SETFD, FD_CLOEXEC);
    posix_spawn_file_actions_t actions;
    if (posix_spawn_file_actions_init(&actions)) { close(pipes[0]); close(pipes[1]); return 3; }
    int setup = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    setup |= posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    setup |= posix_spawn_file_actions_adddup2(&actions, pipes[1], STDOUT_FILENO);
    setup |= posix_spawn_file_actions_addclose(&actions, pipes[0]);
    setup |= posix_spawn_file_actions_addclose(&actions, pipes[1]);
    // mini omits device_address, destroying stable identities across observations.
    char *args[] = {"/usr/sbin/system_profiler", "SPBluetoothDataType", "-json", "-detailLevel", "basic", NULL};
    char *env[] = {"PATH=/usr/bin:/bin:/usr/sbin:/sbin", "LC_ALL=C", NULL};
    pid_t child = 0;
    int spawned = setup ? setup : posix_spawn(&child, args[0], &actions, NULL, args, env);
    posix_spawn_file_actions_destroy(&actions); close(pipes[1]);
    if (spawned) { close(pipes[0]); return 3; }
    fcntl(pipes[0], F_SETFL, O_NONBLOCK);
    double deadline = monotonic_seconds() + 3;
    int status = 0, reaped = 0, eof = 0, error = 0;
    while (!eof || !reaped) {
        if (monotonic_seconds() >= deadline) { error = 1; break; }
        struct pollfd fd = {eof ? -1 : pipes[0], POLLIN | POLLHUP, 0};
        int ready = poll(&fd, 1, 25);
        if (ready < 0 && errno != EINTR) { error = 3; break; }
        if (ready > 0) {
            char chunk[8192]; ssize_t n = read(pipes[0], chunk, sizeof(chunk));
            if (n > 0) {
                if ((uint64_t)*length + n >= capacity) { error = 2; break; }
                memcpy(json + *length, chunk, n); *length += (uint32_t)n;
            } else if (!n) eof = 1;
            else if (errno != EAGAIN && errno != EINTR) { error = 3; break; }
        }
        if (!reaped) {
            pid_t done = waitpid(child, &status, WNOHANG);
            if (done == child) reaped = 1;
            else if (done < 0 && errno != EINTR) { reaped = 1; error = 3; break; }
        }
    }
    close(pipes[0]);
    // Only this collector's unreaped child can be terminated on timeout/overflow.
    if (!reaped) { kill(child, SIGKILL); while (waitpid(child, &status, 0) < 0 && errno == EINTR) {} }
    if (error || !WIFEXITED(status) || WEXITSTATUS(status)) { *length = 0; return error ? error : 3; }
    json[*length] = 0; return 0;
}
