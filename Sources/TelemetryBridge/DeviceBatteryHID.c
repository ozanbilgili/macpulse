#include "DeviceBatteryHID.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>

// This transport opens only Logitech devices in shared mode. The allowlist below
// limits outgoing reports to feature discovery, device-name and battery queries.
typedef struct {
    IOHIDDeviceRef device;
    uint8_t pendingDevice, pendingFeature, pendingFunction;
    uint8_t response[64];
    int responseLength, error, waiting;
    uint8_t softwareID;
} PBSession;

static void receive(void *context, IOReturn result, void *sender, IOHIDReportType type,
                    uint32_t reportID, uint8_t *report, CFIndex length) {
    PBSession *s = context;
    if (!s->waiting || result != kIOReturnSuccess || length < 4) return;
    if (report[0] != 0x10 && report[0] != 0x11) return;
    if (report[1] != s->pendingDevice) return;
    if ((report[2] == 0xFF || report[2] == 0x8F) && length >= 6 &&
        report[3] == s->pendingFeature && report[4] == s->pendingFunction) {
        s->error = 1; s->waiting = 0; return;
    }
    if (report[2] != s->pendingFeature || report[3] != s->pendingFunction) return;
    s->responseLength = (int)(length > 64 ? 64 : length);
    memcpy(s->response, report, s->responseLength);
    s->waiting = 0;
}

static void discard(void *context, IOReturn result, void *sender, IOHIDReportType type,
                    uint32_t reportID, uint8_t *report, CFIndex length) { }

static int query(PBSession *s, uint8_t slot, uint8_t feature, uint8_t function, const uint8_t *params, int count) {
    // Vary the client tag per query to reject a late response from a previous
    // query and reduce collisions with another HID++ client such as Options+.
    s->softwareID = (s->softwareID % 15) + 1;
    uint8_t output[20] = {0x11, slot, feature, (uint8_t)(function | s->softwareID)};
    if (count > 16) return 0;
    if (params && count) memcpy(output + 4, params, count);
    s->pendingDevice = slot; s->pendingFeature = feature; s->pendingFunction = output[3];
    s->responseLength = 0; s->error = 0; s->waiting = 1;
    if (IOHIDDeviceSetReport(s->device, kIOHIDReportTypeOutput, 0x11, output, 20) != kIOReturnSuccess) {
        s->waiting = 0; return 0;
    }
    CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + 0.35;
    while (s->waiting && CFAbsoluteTimeGetCurrent() < deadline)
        CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.015, true);
    s->waiting = 0;
    return !s->error && s->responseLength >= 7;
}

static uint8_t feature(PBSession *s, uint8_t slot, uint16_t identifier) {
    uint8_t params[] = {identifier >> 8, identifier & 0xFF, 0};
    return query(s, slot, 0, 0, params, 3) ? s->response[4] : 0;
}

static int integerProperty(IOHIDDeviceRef device, CFStringRef key) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    int result = 0;
    if (value && CFGetTypeID(value) == CFNumberGetTypeID()) CFNumberGetValue(value, kCFNumberIntType, &result);
    return result;
}

static void stringProperty(IOHIDDeviceRef device, CFStringRef key, char *output, int capacity) {
    CFTypeRef value = IOHIDDeviceGetProperty(device, key);
    if (value && CFGetTypeID(value) == CFStringGetTypeID())
        CFStringGetCString(value, output, capacity, kCFStringEncodingUTF8);
}

static void deviceName(PBSession *s, uint8_t slot, char *output, int capacity) {
    uint8_t index = feature(s, slot, 0x0005);
    if (!index || !query(s, slot, index, 0, NULL, 0)) return;
    int length = s->response[4];
    if (length <= 0 || length >= capacity) return;
    char name[256] = {0};
    for (int offset = 0; offset < length;) {
        uint8_t parameter = offset;
        if (!query(s, slot, index, 0x10, &parameter, 1)) return;
        int chunk = s->responseLength - 4;
        if (chunk > length - offset) chunk = length - offset;
        memcpy(name + offset, s->response + 4, chunk);
        offset += chunk;
    }
    snprintf(output, capacity, "%s", name);
}

static int battery(PBSession *s, uint8_t slot, PBBattery *sample) {
    uint8_t index = feature(s, slot, 0x1004);
    if (index) {
        if (!query(s, slot, index, 0, NULL, 0)) return 0;
        int precise = (s->response[5] & 2) != 0;
        if (!query(s, slot, index, 0x10, NULL, 0)) return 0;
        sample->level = precise && s->response[4] <= 100 ? s->response[4] : -1;
        sample->charging = s->response[6] == 1 || s->response[6] == 2;
        sample->approximate = !precise;
        return 1;
    }
    index = feature(s, slot, 0x1000);
    if (!index || !query(s, slot, index, 0, NULL, 0)) return 0;
    int level = s->response[4], state = s->response[6];
    sample->charging = state == 1 || state == 2 || state == 4;
    sample->level = state == 3 ? 100 : (state == 0 && level <= 100 ? level : -1);
    sample->approximate = 1;
    if (query(s, slot, index, 0x10, NULL, 0))
        sample->approximate = s->response[4] < 10 || !(s->response[5] & 2);
    return 1;
}

int pb_request_hid_access(void) { return IOHIDRequestAccess(kIOHIDRequestTypeListenEvent); }

int pb_read_logitech(PBBattery *batteries, int capacity, int *permissionDenied) {
    *permissionDenied = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted;
    if (*permissionDenied) return 0;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault, kIOHIDOptionsTypeNone);
    int vendor = 0x046D;
    CFNumberRef vendorNumber = CFNumberCreate(NULL, kCFNumberIntType, &vendor);
    const void *keys[] = {CFSTR(kIOHIDVendorIDKey)};
    const void *values[] = {vendorNumber};
    CFDictionaryRef matching = CFDictionaryCreate(NULL, keys, values, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    IOHIDManagerSetDeviceMatching(manager, matching);
    CFRelease(matching); CFRelease(vendorNumber);
    // Enumeration does not seize any input device.
    CFSetRef set = IOHIDManagerCopyDevices(manager);
    if (!set) { CFRelease(manager); return 0; }
    CFIndex count = CFSetGetCount(set);
    IOHIDDeviceRef *devices = calloc(count, sizeof(IOHIDDeviceRef));
    CFSetGetValues(set, (const void **)devices);
    int found = 0;
    for (CFIndex i = 0; i < count && found < capacity; i++) {
        IOHIDDeviceRef d = devices[i];
        char name[256] = {0}, transport[64] = {0}, serial[256] = {0};
        stringProperty(d, CFSTR(kIOHIDProductKey), name, sizeof(name));
        stringProperty(d, CFSTR(kIOHIDTransportKey), transport, sizeof(transport));
        stringProperty(d, CFSTR(kIOHIDSerialNumberKey), serial, sizeof(serial));
        int receiver = strstr(name, "Receiver") || strstr(name, "receiver");
        if (!receiver && !strstr(name, "MX") && !strstr(name, "Craft")) continue;
        if (receiver && integerProperty(d, CFSTR(kIOHIDPrimaryUsagePageKey)) != 0xFF00) continue;
        IOReturn opened = IOHIDDeviceOpen(d, kIOHIDOptionsTypeNone);
        if (opened != kIOReturnSuccess) { if (opened == kIOReturnNotPermitted) *permissionDenied = 1; continue; }
        PBSession session = {.device = d, .softwareID = (uint8_t)(getpid() % 15)};
        uint8_t input[512] = {0};
        IOHIDDeviceRegisterInputReportCallback(d, input, sizeof(input), receive, &session);
        IOHIDDeviceScheduleWithRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        for (int slot = receiver ? 1 : 255; slot <= (receiver ? 6 : 255) && found < capacity; slot++) {
            PBBattery sample = {.level = -1};
            sample.connection = strstr(transport, "Bluetooth") ? 1 : strstr(transport, "USB") ? (receiver ? 3 : 2) : 0;
            snprintf(sample.name, sizeof(sample.name), "%s", name);
            if (battery(&session, (uint8_t)slot, &sample)) {
                if (receiver) deviceName(&session, (uint8_t)slot, sample.name, sizeof(sample.name));
                snprintf(sample.identifier, sizeof(sample.identifier), "logitech:%s:%04X:%d", serial[0] ? serial : name,
                         integerProperty(d, CFSTR(kIOHIDProductIDKey)), slot);
                batteries[found++] = sample;
            }
        }
        IOHIDDeviceUnscheduleFromRunLoop(d, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
        IOHIDDeviceRegisterInputReportCallback(d, input, sizeof(input), discard, NULL);
        IOHIDDeviceClose(d, kIOHIDOptionsTypeNone);
    }
    free(devices); CFRelease(set); CFRelease(manager);
    return found;
}
