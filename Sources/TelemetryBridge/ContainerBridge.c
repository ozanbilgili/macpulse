#include "TelemetryBridge.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <string.h>
#include <errno.h>
#include <stdio.h>
#include <ctype.h>

static int64_t millis(void) { struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return t.tv_sec * 1000 + t.tv_nsec / 1000000; }
static int ready(int fd, short events, int64_t until) {
    int left = (int)(until - millis()); if (left <= 0) return ETIMEDOUT;
    struct pollfd p = { .fd = fd, .events = events };
    int status = poll(&p, 1, left);
    return status > 0 ? 0 : (status == 0 ? ETIMEDOUT : errno);
}
static int allowed(const char *endpoint) {
    if (!strcmp(endpoint, "/containers/json?all=1")) return 1;
    const char *prefix = "/containers/", *suffix = "/stats?stream=false&one-shot=true";
    if (strncmp(endpoint, prefix, strlen(prefix))) return 0;
    const char *id = endpoint + strlen(prefix), *slash = strchr(id, '/');
    if (!slash || slash - id != 64 || strcmp(slash, suffix)) return 0;
    for (const char *p = id; p < slash; p++) if (!isxdigit((unsigned char)*p)) return 0;
    return 1;
}
int mp_container_get(const char *path, const char *endpoint, int timeout_ms, char *response, int capacity, int *count) {
    *count = 0;
    if (!allowed(endpoint) || timeout_ms <= 0 || timeout_ms > 1500 || capacity <= 0) return EINVAL;
    struct sockaddr_un address = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof(address.sun_path)) return ENAMETOOLONG;
    strlcpy(address.sun_path, path, sizeof(address.sun_path));
    int fd = socket(AF_UNIX, SOCK_STREAM, 0); if (fd < 0) return errno;
    int no_signal = 1; setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &no_signal, sizeof(no_signal));
    fcntl(fd, F_SETFL, O_NONBLOCK);
    int64_t until = millis() + timeout_ms;
    int result = 0;
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) != 0) {
        if (errno != EINPROGRESS || (result = ready(fd, POLLOUT, until)) != 0) { if (!result) result = errno; goto done; }
        socklen_t length = sizeof(result); getsockopt(fd, SOL_SOCKET, SO_ERROR, &result, &length);
        if (result) goto done;
    }
    char request[256]; int length = snprintf(request, sizeof(request), "GET %s HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\nAccept: application/json\r\n\r\n", endpoint);
    if (length <= 0 || length >= sizeof(request)) { result = EINVAL; goto done; }
    for (int sent = 0; sent < length;) {
        if ((result = ready(fd, POLLOUT, until))) goto done;
        ssize_t n = write(fd, request + sent, length - sent);
        if (n > 0) sent += (int)n;
        else if (errno != EAGAIN && errno != EINTR) { result = errno ? errno : EIO; goto done; }
    }
    for (;;) {
        if (*count == capacity) { result = EMSGSIZE; goto done; }
        if ((result = ready(fd, POLLIN, until))) goto done;
        ssize_t n = read(fd, response + *count, capacity - *count);
        if (n > 0) *count += (int)n;
        else if (n == 0) break;
        else if (errno != EAGAIN && errno != EINTR) { result = errno; goto done; }
    }
done:
    close(fd); if (result) *count = 0; return result;
}
