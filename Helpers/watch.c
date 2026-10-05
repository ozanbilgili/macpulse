#include <libimobiledevice/libimobiledevice.h>
#include <libimobiledevice/companion_proxy.h>
#include <plist/plist.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>

// Each registry query requires a fresh service connection. Only three battery/name
// keys are requested; there is no port forwarding or companion configuration.
static plist_t value(idevice_t phone, const char *watch, const char *key) {
    companion_proxy_client_t client = NULL;
    if (companion_proxy_client_start_service(phone, &client, "PilBar") != COMPANION_PROXY_E_SUCCESS) return NULL;
    plist_t response = NULL;
    companion_proxy_error_t error = companion_proxy_get_value_from_registry(client, watch, key, &response);
    companion_proxy_client_free(client);
    if (error != COMPANION_PROXY_E_SUCCESS || !response) { if (response) plist_free(response); return NULL; }
    plist_t node = plist_dict_get_item(response, key);
    plist_t copy = node ? plist_copy(node) : NULL;
    plist_free(response);
    return copy;
}

int main(int argc, char **argv) {
    if (argc != 3) return 1;
    signal(SIGPIPE, SIG_IGN);
    idevice_t phone = NULL;
    enum idevice_options options = strcmp(argv[2], "network") == 0 ? IDEVICE_LOOKUP_NETWORK : IDEVICE_LOOKUP_USBMUX;
    if (idevice_new_with_options(&phone, argv[1], options) != IDEVICE_E_SUCCESS) return 2;
    companion_proxy_client_t client = NULL;
    plist_t registry = NULL, output = plist_new_array();
    if (companion_proxy_client_start_service(phone, &client, "PilBar") == COMPANION_PROXY_E_SUCCESS) {
        companion_proxy_get_device_registry(client, &registry);
        companion_proxy_client_free(client);
    }
    if (registry && plist_get_node_type(registry) == PLIST_ARRAY) {
        uint32_t count = plist_array_get_size(registry);
        for (uint32_t index = 0; index < count && index < 8; index++) {
            char *id = NULL;
            plist_t entry = plist_array_get_item(registry, index);
            if (plist_get_node_type(entry) != PLIST_STRING) continue;
            plist_get_string_val(entry, &id);
            if (!id) continue;
            plist_t capacity = value(phone, id, "BatteryCurrentCapacity");
            if (capacity && plist_get_node_type(capacity) == PLIST_UINT) {
                uint64_t level = 0;
                plist_get_uint_val(capacity, &level);
                if (level <= 100) {
                    plist_t row = plist_new_dict();
                    plist_dict_set_item(row, "id", plist_new_string(id));
                    plist_dict_set_item(row, "name", plist_new_string("Apple Watch"));
                    plist_dict_set_item(row, "level", plist_new_uint(level));
                    plist_t charging = value(phone, id, "BatteryIsCharging");
                    uint8_t flag = 0;
                    if (charging && plist_get_node_type(charging) == PLIST_BOOLEAN) plist_get_bool_val(charging, &flag);
                    plist_dict_set_item(row, "charging", plist_new_bool(flag));
                    if (charging) plist_free(charging);
                    plist_array_append_item(output, row);
                }
            }
            if (capacity) plist_free(capacity);
            free(id);
        }
    }
    char *json = NULL; uint32_t length = 0;
    plist_to_json(output, &json, &length, 0);
    if (json) { fwrite(json, 1, length, stdout); plist_mem_free(json); }
    plist_free(output);
    if (registry) plist_free(registry);
    idevice_free(phone);
    return 0;
}
