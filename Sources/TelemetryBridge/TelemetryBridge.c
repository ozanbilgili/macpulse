#include "TelemetryBridge.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/mount.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <net/route.h>
#include <stdlib.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <string.h>

int mp_read_cpu(mp_cpu_ticks *result) {
    host_cpu_load_info_data_t info = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return status;
    result->user = info.cpu_ticks[CPU_STATE_USER];
    result->system = info.cpu_ticks[CPU_STATE_SYSTEM];
    result->idle = info.cpu_ticks[CPU_STATE_IDLE];
    result->nice = info.cpu_ticks[CPU_STATE_NICE];
    return 0;
}

int mp_read_memory(mp_memory *result) {
    vm_statistics64_data_t info = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    vm_size_t page_size = 0;
    mach_port_t host = mach_host_self();
    kern_return_t status = host_page_size(host, &page_size);
    if (status == KERN_SUCCESS)
        status = host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&info, &count);
    mach_port_deallocate(mach_task_self(), host);
    if (status != KERN_SUCCESS) return status;
    size_t size = sizeof(result->total);
    if (sysctlbyname("hw.memsize", &result->total, &size, NULL, 0) != 0) return errno;
    uint64_t internal = info.internal_page_count;
    uint64_t purgeable = info.purgeable_count;
    result->app = (internal > purgeable ? internal - purgeable : 0) * page_size;
    result->wired = (uint64_t)info.wire_count * page_size;
    result->compressed = (uint64_t)info.compressor_page_count * page_size;
    result->cached = ((uint64_t)info.external_page_count + purgeable) * page_size;
    result->free = ((uint64_t)info.free_count + info.speculative_count) * page_size;
    struct xsw_usage swap = {0};
    size = sizeof(swap);
    result->swap_valid = sysctlbyname("vm.swapusage", &swap, &size, NULL, 0) == 0;
    result->swap = result->swap_valid ? swap.xsu_used : 0;
    result->pressure = -1;
    int pressure = -1;
    size = sizeof(pressure);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressure, &size, NULL, 0) == 0)
        result->pressure = pressure;
    return 0;
}

int mp_read_disk_capacity(mp_disk_capacity *result) {
    struct statfs info;
    if (statfs("/System/Volumes/Data", &info) != 0 && statfs("/", &info) != 0) return errno;
    result->total = (uint64_t)info.f_blocks * info.f_bsize;
    result->available = (uint64_t)info.f_bavail * info.f_bsize;
    return 0;
}

static int64_t number(CFDictionaryRef dictionary, CFStringRef key, int64_t fallback) {
    CFTypeRef value = CFDictionaryGetValue(dictionary, key);
    int64_t result = fallback;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID())
        CFNumberGetValue(value, kCFNumberSInt64Type, &result);
    return result;
}

static int physical_storage(io_service_t service) {
    CFTypeRef property = IORegistryEntrySearchCFProperty(service, kIOServicePlane,
        CFSTR("Protocol Characteristics"), kCFAllocatorDefault,
        kIORegistryIterateRecursively | kIORegistryIterateParents);
    int physical = 0;
    if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
        CFDictionaryRef dictionary = (CFDictionaryRef)property;
        CFTypeRef interconnect = CFDictionaryGetValue(dictionary, CFSTR("Physical Interconnect"));
        CFTypeRef location = CFDictionaryGetValue(dictionary, CFSTR("Physical Interconnect Location"));
        physical = interconnect && CFGetTypeID(interconnect) == CFStringGetTypeID()
            && CFStringFind((CFStringRef)interconnect, CFSTR("Virtual"), kCFCompareCaseInsensitive).location == kCFNotFound
            && !(location && CFEqual(location, CFSTR("File")));
    }
    if (property) CFRelease(property);
    return physical;
}

int mp_read_disk_entries(mp_disk_entry *entries, int capacity, int *count) {
    *count = 0;
    io_iterator_t iterator = IO_OBJECT_NULL;
    kern_return_t status = IOServiceGetMatchingServices(kIOMainPortDefault,
        IOServiceMatching("IOBlockStorageDriver"), &iterator);
    if (status != KERN_SUCCESS) return status;
    io_service_t service;
    while ((service = IOIteratorNext(iterator))) {
        if (!physical_storage(service)) { IOObjectRelease(service); continue; }
        CFTypeRef property = IORegistryEntryCreateCFProperty(service, CFSTR("Statistics"), kCFAllocatorDefault, 0);
        if (property && CFGetTypeID(property) == CFDictionaryGetTypeID()) {
            CFDictionaryRef statistics = (CFDictionaryRef)property;
            int64_t read = number(statistics, CFSTR("Bytes (Read)"), -1);
            int64_t written = number(statistics, CFSTR("Bytes (Write)"), -1);
            if (read >= 0 && written >= 0) {
                if (*count >= capacity) { status = ENOSPC; CFRelease(property); IOObjectRelease(service); break; }
                uint64_t identifier = 0;
                if (IORegistryEntryGetRegistryEntryID(service, &identifier) == KERN_SUCCESS) {
                    entries[*count] = (mp_disk_entry){identifier, (uint64_t)read, (uint64_t)written};
                    (*count)++;
                }
            }
        }
        if (property) CFRelease(property);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);
    return status != KERN_SUCCESS ? status : (*count > 0 ? 0 : ENOTSUP);
}

int mp_read_network(mp_network_entry *entries, int capacity, int *count) {
    *count = 0;
    int mib[6] = {CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0};
    size_t size = 0;
    if (sysctl(mib, 6, NULL, &size, NULL, 0) != 0) return errno;
    if (size == 0) return 0;
    char *buffer = malloc(size);
    if (!buffer) return ENOMEM;
    if (sysctl(mib, 6, buffer, &size, NULL, 0) != 0) { int error = errno; free(buffer); return error; }
    int status = 0;
    /* Address records are shorter than if_msghdr; inspect only the common 4-byte prefix. */
    struct route_prefix { uint16_t length; uint8_t version, type; };
    for (char *cursor = buffer; cursor + sizeof(struct route_prefix) <= buffer + size;) {
        struct route_prefix prefix;
        memcpy(&prefix, cursor, sizeof(prefix));
        if (prefix.length < sizeof(prefix) || cursor + prefix.length > buffer + size) { status = EIO; break; }
        char *message = cursor;
        cursor += prefix.length;
        if (prefix.type != RTM_IFINFO2 || prefix.length < sizeof(struct if_msghdr2)) continue;
        struct if_msghdr2 *info = (struct if_msghdr2 *)message;
        if (!(info->ifm_flags & IFF_UP) || !(info->ifm_flags & IFF_RUNNING) || (info->ifm_flags & IFF_LOOPBACK)) continue;
        char name[IF_NAMESIZE] = {0};
        if (!if_indextoname(info->ifm_index, name) || strncmp(name, "en", 2) != 0) continue;
        if (*count >= capacity) { status = ENOSPC; break; }
        mp_network_entry *output = &entries[(*count)++];
        memset(output, 0, sizeof(*output));
        strlcpy(output->name, name, sizeof(output->name));
        output->received = info->ifm_data.ifi_ibytes;
        output->sent = info->ifm_data.ifi_obytes;
    }
    free(buffer);
    return status;
}

int mp_read_battery(mp_battery *result) {
    memset(result, 0, sizeof(*result));
    result->minutes_remaining = -1;
    CFTypeRef info = IOPSCopyPowerSourcesInfo();
    if (!info) return EIO;
    CFArrayRef list = IOPSCopyPowerSourcesList(info);
    if (!list) { CFRelease(info); return EIO; }
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        CFDictionaryRef dictionary = IOPSGetPowerSourceDescription(info, CFArrayGetValueAtIndex(list, i));
        if (!dictionary) continue;
        CFTypeRef type = CFDictionaryGetValue(dictionary, CFSTR(kIOPSTypeKey));
        if (!type || !CFEqual(type, CFSTR(kIOPSInternalBatteryType))) continue;
        CFTypeRef present = CFDictionaryGetValue(dictionary, CFSTR(kIOPSIsPresentKey));
        if (present && CFEqual(present, kCFBooleanFalse)) continue;
        result->present = 1;
        int64_t maximum = number(dictionary, CFSTR(kIOPSMaxCapacityKey), -1);
        int64_t current = number(dictionary, CFSTR(kIOPSCurrentCapacityKey), -1);
        result->percent = maximum > 0 && current >= 0 ? (int)(100 * current / maximum) : -1;
        CFTypeRef state = CFDictionaryGetValue(dictionary, CFSTR(kIOPSPowerSourceStateKey));
        result->on_ac = state && CFEqual(state, CFSTR(kIOPSACPowerValue));
        CFTypeRef charging = CFDictionaryGetValue(dictionary, CFSTR(kIOPSIsChargingKey));
        result->charging = charging && CFEqual(charging, kCFBooleanTrue);
        result->minutes_remaining = (int)number(dictionary,
            result->charging ? CFSTR(kIOPSTimeToFullChargeKey) : CFSTR(kIOPSTimeToEmptyKey), -1);
        break;
    }
    CFRelease(list);
    CFRelease(info);
    return 0;
}
