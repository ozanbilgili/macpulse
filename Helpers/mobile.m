#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <signal.h>
#import <unistd.h>

// Read-only adapter to the macOS device transport. The framework is dynamically
// loaded so an unavailable private API cannot prevent the menu-bar app launching.
typedef void *Device;
typedef struct { Device device; uint32_t message; } DeviceNotification;
static int (*subscribeDevices)(void (*)(DeviceNotification *, void *), int, int, void *, void **, CFDictionaryRef);
static int (*unsubscribeDevices)(void *);
static void (*retainDevice)(Device);
static void (*releaseDevice)(Device);
static int (*interfaceType)(Device);
static CFStringRef (*copyIdentifier)(Device);
static int (*connectDevice)(Device);
static int (*disconnectDevice)(Device);
static int (*isPaired)(Device);
static int (*validatePairing)(Device);
static int (*startSession)(Device);
static int (*stopSession)(Device);
static CFTypeRef (*copyValue)(Device, CFStringRef, CFStringRef);
static NSMutableArray<NSValue *> *discovered;
static NSMutableSet<NSValue *> *sessions;
static BOOL discoveryOnly = NO;
static volatile sig_atomic_t running = 1;
static BOOL printEvents = NO;
static void stopRunning(int signum) { running = 0; }

@interface BatteryBonjourBrowser : NSObject <NSNetServiceBrowserDelegate, NSNetServiceDelegate>
@property(nonatomic, strong) NSMutableSet<NSNetService *> *services;
@end
@implementation BatteryBonjourBrowser
- (instancetype)init { self = [super init]; if (self) _services = [NSMutableSet set]; return self; }
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didFindService:(NSNetService *)service moreComing:(BOOL)more {
    if (self.services.count >= 16) return;
    [self.services addObject:service];
    service.delegate = self;
    [service resolveWithTimeout:5];
}
- (void)netServiceBrowser:(NSNetServiceBrowser *)browser didRemoveService:(NSNetService *)service moreComing:(BOOL)more {
    [service stop]; [self.services removeObject:service];
    if (discoveryOnly) { puts("{\"event\":\"devicesChanged\"}"); fflush(stdout); }
}
- (void)netServiceDidResolveAddress:(NSNetService *)service {
    if (discoveryOnly) { puts("{\"event\":\"devicesChanged\"}"); fflush(stdout); }
}
@end

static void notified(DeviceNotification *info, void *context) {
    if (!info || !info->device) return;
    if (printEvents) fprintf(stderr, "event=%u interface=%d\n", info->message, interfaceType(info->device));
    NSValue *value = [NSValue valueWithPointer:info->device];
    if (info->message == 1 && ![discovered containsObject:value] && discovered.count < 16) {
        retainDevice(info->device);
        [discovered addObject:value];
    } else if (info->message == 2 && [discovered containsObject:value]) {
        [discovered removeObject:value];
        [sessions removeObject:value];
        releaseDevice(info->device);
    }
    if (discoveryOnly && (info->message == 1 || info->message == 2)) {
        puts("{\"event\":\"devicesChanged\"}"); fflush(stdout);
    }
}

static BOOL loadAPI(void) {
    void *library = dlopen("/Library/Apple/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_LAZY);
    if (!library) library = dlopen("/System/Library/PrivateFrameworks/MobileDevice.framework/MobileDevice", RTLD_LAZY);
    if (!library) return NO;
#define LOAD(variable, symbol) variable = dlsym(library, symbol); if (!variable) return NO;
    LOAD(subscribeDevices, "AMDeviceNotificationSubscribeWithOptions")
    LOAD(unsubscribeDevices, "AMDeviceNotificationUnsubscribe")
    LOAD(retainDevice, "AMDeviceRetain")
    LOAD(releaseDevice, "AMDeviceRelease")
    LOAD(interfaceType, "AMDeviceGetInterfaceType")
    LOAD(copyIdentifier, "AMDeviceCopyDeviceIdentifier")
    LOAD(connectDevice, "AMDeviceConnect")
    LOAD(disconnectDevice, "AMDeviceDisconnect")
    LOAD(isPaired, "AMDeviceIsPaired")
    LOAD(validatePairing, "AMDeviceValidatePairing")
    LOAD(startSession, "AMDeviceStartSession")
    LOAD(stopSession, "AMDeviceStopSession")
    LOAD(copyValue, "AMDeviceCopyValue")
#undef LOAD
    return YES;
}

static id readValue(Device device, CFStringRef domain, CFStringRef key) {
    CFTypeRef value = copyValue(device, domain, key);
    return value ? CFBridgingRelease(value) : nil;
}

static void keepTrustedSessions(void) {
    // Keep only authenticated battery-query sessions alive. Discovery alone lets
    // an idle wireless device disappear from usbmuxd between one-minute polls.
    for (NSValue *value in [discovered copy]) {
        Device device = value.pointerValue;
        // RemoteXPC Watch references have their own connection lifecycle. Keep
        // classic iPhone/iPad sessions alive without blocking on a sleeping Watch.
        if (interfaceType(device) != 1 && interfaceType(device) != 2) continue;
        if (![sessions containsObject:value]) {
            if (connectDevice(device) != 0) continue;
            if (!isPaired(device) || validatePairing(device) != 0 || startSession(device) != 0) {
                disconnectDevice(device); continue;
            }
            [sessions addObject:value];
        }
        (void)readValue(device, CFSTR("com.apple.mobile.battery"), CFSTR("BatteryCurrentCapacity"));
    }
}

static BOOL hasPendingSessions(void) {
    for (NSValue *value in discovered) {
        int type = interfaceType(value.pointerValue);
        if ((type == 1 || type == 2) && ![sessions containsObject:value]) return YES;
    }
    return NO;
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        signal(SIGPIPE, SIG_IGN);
        discoveryOnly = argc > 1 && strcmp(argv[1], "--discover") == 0;
        printEvents = argc > 1 && strcmp(argv[1], "--events") == 0;
        signal(SIGTERM, stopRunning);
        signal(SIGINT, stopRunning);
        if (!discoveryOnly) alarm(printEvents ? 30 : 15);
        if (!loadAPI()) return 2;
        discovered = [NSMutableArray array];
        sessions = [NSMutableSet set];
        BatteryBonjourBrowser *bonjourDelegate = [BatteryBonjourBrowser new];
        NSNetServiceBrowser *bonjour = [NSNetServiceBrowser new];
        bonjour.delegate = bonjourDelegate;
        [bonjour searchForServicesOfType:@"_apple-mobdev2._tcp." inDomain:@"local."];
        NSDictionary *options = @{
            @"NotificationOptionSearchForPairedDevices": @YES,
            @"NotificationOptionSearchForPairedDevicesViaDirectConnectionsOnly": @NO,
            @"NotificationOptionSearchForWiFiPairableDevices": @YES,
            @"NotificationOptionEnableUSBMux": @YES
        };
        void *subscription = NULL;
        int result = subscribeDevices(notified, 0, 0, NULL, &subscription, (__bridge CFDictionaryRef)options);
        if (result != 0) return 3;
        if (discoveryOnly) {
            puts("{\"event\":\"ready\"}"); fflush(stdout);
            CFAbsoluteTime nextQuery = 0;
            while (running && getppid() > 1) {
                @autoreleasepool {
                    CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.5, false);
                    if (CFAbsoluteTimeGetCurrent() >= nextQuery || hasPendingSessions()) {
                        alarm(15);
                        keepTrustedSessions();
                        alarm(0);
                        nextQuery = CFAbsoluteTimeGetCurrent() + 30;
                    }
                }
            }
            unsubscribeDevices(subscription);
            [bonjour stop];
            for (NSNetService *service in bonjourDelegate.services) [service stop];
            for (NSValue *value in sessions) { stopSession(value.pointerValue); disconnectDevice(value.pointerValue); }
            for (NSValue *value in discovered) releaseDevice(value.pointerValue);
            return 0;
        }
        CFAbsoluteTime deadline = CFAbsoluteTimeGetCurrent() + (printEvents ? 15 : 4);
        while (CFAbsoluteTimeGetCurrent() < deadline) CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.1, false);
        NSMutableArray *rows = [NSMutableArray array];
        for (NSValue *value in [discovered copy]) {
            Device device = value.pointerValue;
            NSMutableDictionary *row = [@{ @"transport": interfaceType(device) == 1 ? @"usb" : @"network", @"interface": @(interfaceType(device)) } mutableCopy];
            int connection = connectDevice(device);
            row[@"connectCode"] = @(connection);
            if (connection == 0) {
                BOOL paired = isPaired(device) != 0;
                row[@"paired"] = @(paired);
                int validation = paired ? validatePairing(device) : -1;
                row[@"pairingCode"] = @(validation);
                int session = validation == 0 ? startSession(device) : -1;
                row[@"sessionCode"] = @(session);
                if (session == 0) {
                    row[@"name"] = readValue(device, NULL, CFSTR("DeviceName")) ?: @"iPhone / iPad";
                    row[@"level"] = readValue(device, CFSTR("com.apple.mobile.battery"), CFSTR("BatteryCurrentCapacity")) ?: [NSNull null];
                    row[@"charging"] = readValue(device, CFSTR("com.apple.mobile.battery"), CFSTR("BatteryIsCharging")) ?: @NO;
                    if (argc > 1 && strcmp(argv[1], "--json") == 0) {
                        row[@"id"] = CFBridgingRelease(copyIdentifier(device)) ?: @"";
                        row[@"class"] = readValue(device, NULL, CFSTR("DeviceClass")) ?: @"";
                        id canonicalID = readValue(device, NULL, CFSTR("UniqueDeviceID"));
                        if ([canonicalID isKindOfClass:NSString.class] && [canonicalID length] > 0) row[@"id"] = canonicalID;
                        NSData *line = [NSJSONSerialization dataWithJSONObject:row options:0 error:nil];
                        if (line) { fwrite(line.bytes, 1, line.length, stdout); putchar('\n'); fflush(stdout); }
                    }
                    stopSession(device);
                }
                disconnectDevice(device);
            }
            [rows addObject:row];
        }
        unsubscribeDevices(subscription);
        [bonjour stop];
        for (NSNetService *service in bonjourDelegate.services) [service stop];
        for (NSValue *value in discovered) releaseDevice(value.pointerValue);
        if (argc > 1 && strcmp(argv[1], "--json") == 0) {
            puts("{\"complete\":true}"); fflush(stdout);
        } else {
            NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:0 error:nil];
            if (data) fwrite(data.bytes, 1, data.length, stdout);
        }
        return 0;
    }
}
