#include "DeviceBatteryHID.h"
#ifndef TELEMETRY_BRIDGE_H
#define TELEMETRY_BRIDGE_H
#include <stdint.h>

typedef struct { uint32_t user, system, idle, nice; } mp_cpu_ticks;
typedef struct {
    uint64_t total, app, wired, compressed, cached, free, swap;
    int pressure; /* 1 normal, 2 warning, 4 critical, -1 unavailable */
    int swap_valid;
} mp_memory;
typedef struct { uint64_t total, available; } mp_disk_capacity;
typedef struct { uint64_t identifier, read, written; } mp_disk_entry;
typedef struct { char name[32]; uint64_t received, sent; } mp_network_entry;
typedef struct {
    int present, on_ac, charging, percent, minutes_remaining;
} mp_battery;

int mp_read_cpu(mp_cpu_ticks *result);
int mp_read_memory(mp_memory *result);
int mp_read_disk_capacity(mp_disk_capacity *result);
int mp_read_disk_entries(mp_disk_entry *entries, int capacity, int *count);
int mp_read_network(mp_network_entry *entries, int capacity, int *count);
int mp_read_battery(mp_battery *result);

typedef struct {
    int32_t pid, parent_pid;
    uint64_t start_seconds, start_microseconds, cpu_nanoseconds, footprint, resident, coalition;
    int usage_status, path_status, coalition_status;
    char name[64];
    char path[4096];
} mp_process;
enum { MP_PROCESS_OTHER_USER = 1, MP_PROCESS_GONE = 2, MP_PROCESS_METADATA_DENIED = 3, MP_PROCESS_CHANGED = 4 };
int mp_list_process_ids(int32_t *pids, int capacity, int *count, int *truncated);
int mp_read_process(int32_t pid, mp_process *result);
typedef struct { uint16_t port; int family, loopback, wildcard; } mp_tcp_listener;
typedef struct {
    int cwd_status, sockets_status, truncated, failed_sockets, active_connections;
    uint64_t queued_bytes;
    char cwd[4096];
} mp_developer_info;
int mp_read_developer(int32_t pid, uint64_t start_microseconds, mp_developer_info *result,
                      mp_tcp_listener *listeners, int capacity, int *count);
/* Bounded, local Unix-socket HTTP GET. Only container inventory/stat endpoints. */
int mp_container_get(const char *socket_path, const char *endpoint, int timeout_ms,
                     char *response, int capacity, int *count);

/* Phase 6: read-only, optional Apple silicon interfaces. No SMC write command. */
typedef struct mp_hardware_context mp_hardware_context;
typedef struct {
    uint64_t registry_id, memory_in_use, memory_allocated;
    double device_percent, renderer_percent, tiler_percent;
    int valid_mask;
} mp_gpu;
typedef struct {
    char key[5], type[5];
    uint8_t bytes[32];
    int size, kind; /* 1 Te/Tp, 2 Tg, 3 fan actual, 4 PSTR */
} mp_sensor;
typedef struct {
    uint64_t driver_id, channel_id;
    int64_t value;
    char name[64], unit[8];
} mp_energy;
typedef struct {
    int installed, on_ac, charging, current_valid;
    int64_t millivolts, milliamps, updated_seconds;
} mp_battery_flow;
mp_hardware_context *mp_hardware_open(void);
void mp_hardware_close(mp_hardware_context *context);
int mp_read_gpu(mp_gpu *entries, int capacity, int *count);
int mp_read_sensors(mp_hardware_context *context, mp_sensor *entries, int capacity, int *count, int *failed, int *truncated);
int mp_read_energy(mp_hardware_context *context, mp_energy *entries, int capacity, int *count);
int mp_read_battery_flow(mp_battery_flow *result);

typedef struct {
    uint32_t id, transport, input_channels, output_channels, valid_mask;
    int alive, running, input_mute, output_mute;
    double sample_rate, input_volume, output_volume;
    char name[256];
} mp_audio_device;
typedef struct {
    uint32_t default_input, default_output, default_system_output;
    int failures, truncated;
} mp_audio_info;
// Read-only HAL properties; no AudioDeviceStart, IOProc, tap or set-property.
int mp_read_audio(mp_audio_device *entries, int capacity, int *count, mp_audio_info *info);
// Exact system_profiler Bluetooth inventory, bounded to 1 MiB / 3 seconds.
// 0 success; 1 timeout; 2 size limit; 3 executable/process failure.
int mp_read_bluetooth_profile(char *json, uint32_t capacity, uint32_t *length);
#endif
