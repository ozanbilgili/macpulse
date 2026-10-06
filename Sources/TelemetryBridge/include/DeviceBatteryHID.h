#ifndef PILBAR_HID_H
#define PILBAR_HID_H
#include <stdint.h>
typedef struct {
    char name[256];
    char identifier[256];
    int level; // -1 means no numeric capacity available
    int charging;
    int approximate;
    int connection; // 1 Bluetooth, 2 USB device, 3 USB receiver; 0 unknown
} PBBattery;
int pb_read_logitech(PBBattery *batteries, int capacity, int *permissionDenied);
int pb_request_hid_access(void);
#endif
