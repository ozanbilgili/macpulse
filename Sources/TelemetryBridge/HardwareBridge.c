#include "TelemetryBridge.h"
#include <IOKit/IOKitLib.h>
#include <CoreFoundation/CoreFoundation.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <math.h>

/* Optional private ABI, dynamically resolved; see docs/THIRD-PARTY.md. */
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } smc_version;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } smc_limit;
typedef struct { uint32_t size, type; uint8_t attributes; } smc_info;
typedef struct {
    uint32_t key; smc_version version; smc_limit limits; smc_info info;
    uint8_t result, status, command; uint32_t index; uint8_t bytes[32];
} smc_packet;
_Static_assert(sizeof(smc_packet) == 80, "SMC ABI changed");

typedef CFDictionaryRef (*copy_channels_fn)(uint64_t, uint64_t);
typedef CFTypeRef (*subscribe_fn)(CFTypeRef, CFMutableDictionaryRef, CFMutableDictionaryRef *, uint64_t, CFTypeRef);
typedef CFDictionaryRef (*samples_fn)(CFTypeRef, CFMutableDictionaryRef, CFTypeRef);
typedef CFStringRef (*string_fn)(CFDictionaryRef);
typedef uint64_t (*id_fn)(CFDictionaryRef);
typedef int64_t (*integer_fn)(CFDictionaryRef, int);
typedef uint8_t (*format_fn)(CFDictionaryRef);
struct mp_hardware_context {
    io_connect_t smc;
    int smc_status, sensor_count, discovery_truncated;
    mp_sensor sensors[128];
    void *library;
    CFTypeRef subscription;
    CFMutableDictionaryRef channels;
    samples_fn sample;
    string_fn name, unit;
    id_fn driver, channel;
    integer_fn integer;
    format_fn format;
    int energy_status;
};
static int64_t integer(CFDictionaryRef dictionary, CFStringRef key, int64_t fallback) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    int64_t result;
    return value && CFGetTypeID(value) == CFNumberGetTypeID() && CFNumberGetValue(value, kCFNumberSInt64Type, &result) ? result : fallback;
}
static int boolean(CFDictionaryRef dictionary, CFStringRef key) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    return value && CFGetTypeID(value) == CFBooleanGetTypeID() && CFBooleanGetValue(value);
}
static uint32_t fourcc(const char *key) {
    return ((uint32_t)(uint8_t)key[0] << 24) | ((uint32_t)(uint8_t)key[1] << 16) | ((uint32_t)(uint8_t)key[2] << 8) | (uint8_t)key[3];
}
static void key_string(uint32_t key, char result[5]) {
    for (int i = 0; i < 4; i++) result[i] = (char)(key >> (24 - 8 * i));
    result[4] = 0;
}
static int smc_call(io_connect_t connection, smc_packet *in, smc_packet *out) {
    if (in->command != 5 && in->command != 8 && in->command != 9) return EPERM;
    size_t size = sizeof(*out); memset(out, 0, size);
    kern_return_t result = IOConnectCallStructMethod(connection, 2, in, sizeof(*in), out, &size);
    if (result != KERN_SUCCESS) return result;
    return size == sizeof(*out) && out->result == 0 ? 0 : EIO;
}
static int smc_read(io_connect_t connection, const char *key, mp_sensor *value) {
    smc_packet input = {0}, output = {0}; input.key = fourcc(key); input.command = 9;
    int status = smc_call(connection, &input, &output);
    if (status || output.info.size < 1 || output.info.size > 32) return status ? status : ENOTSUP;
    input.info = output.info; input.command = 5;
    status = smc_call(connection, &input, &output);
    if (status) return status;
    strlcpy(value->key, key, sizeof(value->key)); key_string(input.info.type, value->type);
    value->size = (int)input.info.size; memcpy(value->bytes, output.bytes, (size_t)value->size);
    return 0;
}
static void smc_discover(mp_hardware_context *ctx) {
    ctx->smc_status = ENOTSUP;
    io_iterator_t iterator = 0;
    kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSMC"), &iterator);
    if (status != KERN_SUCCESS) { ctx->smc_status = status; return; }
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        io_name_t name = {0}; IORegistryEntryGetName(service, name);
        if (strcmp(name, "AppleSMCKeysEndpoint") == 0) {
            ctx->smc_status = IOServiceOpen(service, mach_task_self(), 0, &ctx->smc);
            IOObjectRelease(service); break;
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    if (!ctx->smc || ctx->smc_status) return;
    mp_sensor count_value = {0};
    if (smc_read(ctx->smc, "#KEY", &count_value) || count_value.size != 4 || strcmp(count_value.type, "ui32")) return;
    uint32_t total = fourcc((const char *)count_value.bytes);
    uint64_t start = mach_absolute_time(); mach_timebase_info_data_t base; mach_timebase_info(&base);
    uint32_t limit = total < 4096 ? total : 4096;
    ctx->discovery_truncated = total > limit;
    for (uint32_t index = 0; index < limit; index++) {
        if ((double)(mach_absolute_time() - start) * base.numer / base.denom > 250000000) { ctx->discovery_truncated = 1; break; }
        smc_packet input = {0}, output = {0}; input.command = 8; input.index = index;
        if (smc_call(ctx->smc, &input, &output)) continue;
        char key[5]; key_string(output.key, key);
        int kind = 0;
        if (key[0] == 'T' && (key[1] == 'p' || key[1] == 'e')) kind = 1;
        else if (key[0] == 'T' && key[1] == 'g') kind = 2;
        else if (key[0] == 'F' && key[1] >= '0' && key[1] <= '7' && key[2] == 'A' && key[3] == 'c') kind = 3;
        if (!kind) continue;
        int duplicate = 0;
        for (int i = 0; i < ctx->sensor_count; i++) if (!strcmp(ctx->sensors[i].key, key)) { duplicate = 1; break; }
        if (duplicate) continue;
        if (ctx->sensor_count >= 126) { ctx->discovery_truncated = 1; break; }
        mp_sensor *entry = &ctx->sensors[ctx->sensor_count++]; strlcpy(entry->key, key, sizeof(entry->key)); entry->kind = kind;
    }
    const char *power_keys[] = {"PSTR"};
    for (int i = 0; i < 1; i++) {
        mp_sensor *entry = &ctx->sensors[ctx->sensor_count++]; strlcpy(entry->key, power_keys[i], sizeof(entry->key)); entry->kind = 4 + i;
    }
}
static void energy_open(mp_hardware_context *ctx) {
    ctx->energy_status = ENOTSUP;
    ctx->library = dlopen("/usr/lib/libIOReport.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (!ctx->library) return;
    copy_channels_fn copy = (copy_channels_fn)dlsym(ctx->library, "IOReportCopyAllChannels");
    subscribe_fn subscribe = (subscribe_fn)dlsym(ctx->library, "IOReportCreateSubscription");
    string_fn group = (string_fn)dlsym(ctx->library, "IOReportChannelGetGroup");
    ctx->sample = (samples_fn)dlsym(ctx->library, "IOReportCreateSamples");
    ctx->name = (string_fn)dlsym(ctx->library, "IOReportChannelGetChannelName");
    ctx->unit = (string_fn)dlsym(ctx->library, "IOReportChannelGetUnitLabel");
    ctx->driver = (id_fn)dlsym(ctx->library, "IOReportChannelGetDriverID");
    ctx->channel = (id_fn)dlsym(ctx->library, "IOReportChannelGetChannelID");
    ctx->integer = (integer_fn)dlsym(ctx->library, "IOReportSimpleGetIntegerValue");
    ctx->format = (format_fn)dlsym(ctx->library, "IOReportChannelGetFormat");
    if (!copy || !subscribe || !group || !ctx->sample || !ctx->name || !ctx->unit || !ctx->driver || !ctx->channel || !ctx->integer || !ctx->format) return;
    CFDictionaryRef all = copy(0, 0);
    if (!all || CFGetTypeID(all) != CFDictionaryGetTypeID()) { if (all) CFRelease(all); return; }
    CFTypeRef raw = CFDictionaryGetValue(all, CFSTR("IOReportChannels"));
    if (!raw || CFGetTypeID(raw) != CFArrayGetTypeID()) { CFRelease(all); return; }
    CFMutableArrayRef selected = CFArrayCreateMutable(NULL, 0, &kCFTypeArrayCallBacks);
    CFIndex count = CFArrayGetCount((CFArrayRef)raw);
    for (CFIndex i = 0; i < count && i < 8192 && CFArrayGetCount(selected) < 16; i++) {
        CFTypeRef item = CFArrayGetValueAtIndex((CFArrayRef)raw, i);
        if (CFGetTypeID(item) != CFDictionaryGetTypeID()) continue;
        CFStringRef g = group(item), n = ctx->name(item);
        if (!g || !n || !CFEqual(g, CFSTR("Energy Model")) || ctx->format(item) != 1) continue;
        if (CFEqual(n, CFSTR("GPU Energy")) || CFEqual(n, CFSTR("CPU Energy")) || CFEqual(n, CFSTR("DRAM Energy"))) CFArrayAppendValue(selected, item);
    }
    if (CFArrayGetCount(selected)) {
        CFMutableDictionaryRef channels = CFDictionaryCreateMutableCopy(NULL, 0, all);
        CFDictionarySetValue(channels, CFSTR("IOReportChannels"), selected);
        ctx->subscription = subscribe(NULL, channels, &ctx->channels, 0, NULL);
        if (ctx->subscription && ctx->channels) ctx->energy_status = 0;
        CFRelease(channels);
    }
    CFRelease(selected); CFRelease(all);
}
mp_hardware_context *mp_hardware_open(void) {
    mp_hardware_context *ctx = calloc(1, sizeof(*ctx));
    if (!ctx) return NULL;
    smc_discover(ctx); energy_open(ctx); return ctx;
}
void mp_hardware_close(mp_hardware_context *ctx) {
    if (!ctx) return;
    if (ctx->smc) IOServiceClose(ctx->smc);
    if (ctx->subscription) CFRelease(ctx->subscription);
    if (ctx->channels) CFRelease(ctx->channels);
    if (ctx->library) dlclose(ctx->library);
    free(ctx);
}
int mp_read_sensors(mp_hardware_context *ctx, mp_sensor *entries, int capacity, int *count, int *failed, int *truncated) {
    *count = 0; *failed = 0; *truncated = ctx ? ctx->discovery_truncated : 0;
    if (!ctx || !ctx->smc || ctx->smc_status) return ctx ? ctx->smc_status : ENOMEM;
    for (int i = 0; i < ctx->sensor_count; i++) {
        if (*count >= capacity) { *truncated = 1; break; }
        mp_sensor value = {0};
        if (smc_read(ctx->smc, ctx->sensors[i].key, &value)) { (*failed)++; continue; }
        value.kind = ctx->sensors[i].kind; entries[(*count)++] = value;
    }
    return 0;
}
int mp_read_energy(mp_hardware_context *ctx, mp_energy *entries, int capacity, int *count) {
    *count = 0;
    if (!ctx || ctx->energy_status) return ctx ? ctx->energy_status : ENOMEM;
    CFDictionaryRef sample = ctx->sample(ctx->subscription, ctx->channels, NULL);
    if (!sample || CFGetTypeID(sample) != CFDictionaryGetTypeID()) { if (sample) CFRelease(sample); return EIO; }
    CFTypeRef raw = CFDictionaryGetValue(sample, CFSTR("IOReportChannels"));
    if (!raw || CFGetTypeID(raw) != CFArrayGetTypeID()) { CFRelease(sample); return EIO; }
    int status = 0; CFIndex total = CFArrayGetCount(raw);
    for (CFIndex i = 0; i < total; i++) {
        if (*count >= capacity) { status = ENOSPC; break; }
        CFTypeRef item = CFArrayGetValueAtIndex(raw, i);
        if (CFGetTypeID(item) != CFDictionaryGetTypeID()) { status = EIO; break; }
        if (ctx->format(item) != 1) continue;
        mp_energy value = {0}; CFStringRef name = ctx->name(item), unit = ctx->unit(item);
        if (!name || !unit || !CFStringGetCString(name, value.name, sizeof(value.name), kCFStringEncodingUTF8) || !CFStringGetCString(unit, value.unit, sizeof(value.unit), kCFStringEncodingUTF8)) continue;
        value.driver_id = ctx->driver(item); value.channel_id = ctx->channel(item); value.value = ctx->integer(item, 0);
        entries[(*count)++] = value;
    }
    CFRelease(sample); return status;
}
int mp_read_gpu(mp_gpu *entries, int capacity, int *count) {
    *count = 0; io_iterator_t iterator = 0;
    int status = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AGXAccelerator"), &iterator);
    if (status) return status;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        if (*count >= capacity) { status = ENOSPC; IOObjectRelease(service); break; }
        CFTypeRef property = IORegistryEntryCreateCFProperty(service, CFSTR("PerformanceStatistics"), NULL, 0);
        if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
            mp_gpu value = {0}; IORegistryEntryGetRegistryEntryID(service, &value.registry_id);
            const CFStringRef keys[] = {CFSTR("Device Utilization %"), CFSTR("Renderer Utilization %"), CFSTR("Tiler Utilization %")};
            double *fields[] = {&value.device_percent, &value.renderer_percent, &value.tiler_percent};
            for (int i = 0; i < 3; i++) {
                CFTypeRef n = CFDictionaryGetValue(property, keys[i]); double v;
                if (n && CFGetTypeID(n) == CFNumberGetTypeID() && CFNumberGetValue(n, kCFNumberDoubleType, &v) && isfinite(v) && v >= 0 && v <= 100) { *fields[i] = v; value.valid_mask |= 1 << i; }
            }
            int64_t used = integer(property, CFSTR("In use system memory"), -1), allocated = integer(property, CFSTR("Alloc system memory"), -1);
            if (used >= 0) { value.memory_in_use = used; value.valid_mask |= 8; }
            if (allocated >= 0) { value.memory_allocated = allocated; value.valid_mask |= 16; }
            entries[(*count)++] = value;
        }
        if (property) CFRelease(property); IOObjectRelease(service);
    }
    IOObjectRelease(iterator); return status ? status : (*count ? 0 : ENOTSUP);
}
int mp_read_battery_flow(mp_battery_flow *result) {
    memset(result, 0, sizeof(*result));
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"));
    if (!service) return ENOTSUP;
    CFMutableDictionaryRef dictionary = NULL;
    int status = IORegistryEntryCreateCFProperties(service, &dictionary, NULL, 0);
    IOObjectRelease(service);
    if (status || !dictionary) return status ? status : EIO;
    result->installed = boolean(dictionary, CFSTR("BatteryInstalled"));
    result->on_ac = boolean(dictionary, CFSTR("ExternalConnected")); result->charging = boolean(dictionary, CFSTR("IsCharging"));
    result->millivolts = integer(dictionary, CFSTR("Voltage"), -1);
    result->updated_seconds = integer(dictionary, CFSTR("UpdateTime"), -1);
    CFTypeRef current = CFDictionaryGetValue(dictionary, CFSTR("InstantAmperage"));
    if (current && CFGetTypeID(current) == CFNumberGetTypeID()) {
        int64_t value;
        if (CFNumberGetValue(current, kCFNumberSInt64Type, &value)) {
            // Some drivers expose signed current as a 32-bit unsigned number.
            if (value > INT32_MAX && value <= UINT32_MAX) value = (int32_t)(uint32_t)value;
            result->milliamps = value; result->current_valid = 1;
        }
    }
    CFRelease(dictionary); return 0;
}
