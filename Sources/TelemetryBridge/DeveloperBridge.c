#include "TelemetryBridge.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <stdlib.h>

static int matches(int32_t pid, uint64_t start) {
    struct proc_bsdinfo info = {0};
    return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info)) == sizeof(info)
        && info.pbi_uid == geteuid() && !(info.pbi_flags & PROC_FLAG_INEXIT)
        && info.pbi_start_tvsec * 1000000 + info.pbi_start_tvusec == start;
}

int mp_read_developer(int32_t pid, uint64_t start, mp_developer_info *out,
                      mp_tcp_listener *listeners, int capacity, int *count) {
    memset(out, 0, sizeof(*out)); *count = 0;
    if (!matches(pid, start)) return MP_PROCESS_CHANGED;
    struct proc_vnodepathinfo vnode = {0};
    out->cwd_status = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &vnode, sizeof(vnode)) == sizeof(vnode) ? 0 : (errno ? errno : EIO);
    if (!out->cwd_status) strlcpy(out->cwd, vnode.pvi_cdir.vip_path, sizeof(out->cwd));

    errno = 0;
    int needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, NULL, 0);
    if (needed < 0 || (needed == 0 && errno != 0)) out->sockets_status = errno ? errno : EIO;
    else if (needed > 0) {
        /* Leave headroom for descriptors opened during enumeration; never exceed 4096. */
        int limit = needed / (int)sizeof(struct proc_fdinfo) + 32;
        if (limit > 4096) { limit = 4096; out->truncated = 1; }
        struct proc_fdinfo *fds = calloc(limit, sizeof(*fds));
        if (!fds) out->sockets_status = ENOMEM;
        else {
            errno = 0;
            int bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, fds, limit * (int)sizeof(*fds));
            if (bytes < 0 || (bytes == 0 && errno != 0)) out->sockets_status = errno ? errno : EIO;
            else {
                int n = bytes / (int)sizeof(*fds);
                if (n >= limit) out->truncated = 1;
                for (int i = 0; i < n; i++) {
                    if (fds[i].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
                    struct socket_fdinfo fd = {0};
                    if (proc_pidfdinfo(pid, fds[i].proc_fd, PROC_PIDFDSOCKETINFO, &fd, sizeof(fd)) != sizeof(fd)) {
                        out->failed_sockets++; continue;
                    }
                    if (fd.psi.soi_kind != SOCKINFO_TCP) continue;
                    const struct tcp_sockinfo *tcp = &fd.psi.soi_proto.pri_tcp;
                    if (tcp->tcpsi_state != TSI_S_LISTEN && tcp->tcpsi_state != TSI_S_CLOSED && tcp->tcpsi_state != TSI_S_TIME_WAIT)
                        out->active_connections++;
                    out->queued_bytes += (uint64_t)fd.psi.soi_rcv.sbi_cc + fd.psi.soi_snd.sbi_cc;
                    if (tcp->tcpsi_state != TSI_S_LISTEN) continue;
                    if (*count >= capacity) { out->truncated = 1; continue; }
                    mp_tcp_listener entry = { .port = ntohs((uint16_t)tcp->tcpsi_ini.insi_lport), .family = fd.psi.soi_family };
                    if (fd.psi.soi_family == AF_INET) {
                        uint32_t addr = ntohl(tcp->tcpsi_ini.insi_laddr.ina_46.i46a_addr4.s_addr);
                        entry.loopback = (addr >> 24) == 127; entry.wildcard = addr == INADDR_ANY;
                    } else if (fd.psi.soi_family == AF_INET6) {
                        const struct in6_addr *addr = &tcp->tcpsi_ini.insi_laddr.ina_6;
                        entry.loopback = IN6_IS_ADDR_LOOPBACK(addr); entry.wildcard = IN6_IS_ADDR_UNSPECIFIED(addr);
                    }
                    if (entry.port > 0) listeners[(*count)++] = entry;
                }
            }
            free(fds);
        }
    }
    if (!matches(pid, start)) { memset(out, 0, sizeof(*out)); *count = 0; return MP_PROCESS_CHANGED; }
    return 0;
}
