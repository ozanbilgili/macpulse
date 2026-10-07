#include "TelemetryBridge.h"
#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/resource.h>
#include <mach/mach_time.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <limits.h>

/* Optional XNU SPI: flavor 20, two coalition IDs followed by three reserved words.
 * Apple source: bsd/sys/proc_info_private.h. Not in the public SDK.
 * Exact returned size is required. Failure means no coalition attribution.
 * This queries metadata only, for the same UID, and has no privileged fallback.
 */
enum { MP_COALITION_FLAVOR = 20 };
struct mp_coalition_info { uint64_t ids[2], reserved[3]; };

int mp_list_process_ids(int32_t *pids, int capacity, int *count, int *truncated) {
    *count = 0; *truncated = 0;
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids, capacity * (int)sizeof(int32_t));
    if (bytes <= 0) return errno ? errno : EIO;
    *count = bytes / sizeof(int32_t);
    *truncated = *count >= capacity;
    return 0;
}

static uint64_t ticks_to_ns(uint64_t ticks, mach_timebase_info_data_t base) {
    __uint128_t value = (__uint128_t)ticks * base.numer / base.denom;
    return value > UINT64_MAX ? UINT64_MAX : (uint64_t)value;
}

int mp_read_process(int32_t pid, mp_process *result) {
    memset(result, 0, sizeof(*result));
    struct proc_bsdinfo before = {0}, after = {0};
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &before, sizeof(before)) != sizeof(before))
        return errno == ESRCH ? MP_PROCESS_GONE : MP_PROCESS_METADATA_DENIED;
    if (before.pbi_uid != geteuid()) return MP_PROCESS_OTHER_USER;
    if (before.pbi_flags & PROC_FLAG_INEXIT) return MP_PROCESS_GONE;
    result->pid = pid;
    result->parent_pid = before.pbi_ppid;
    result->start_seconds = before.pbi_start_tvsec;
    result->start_microseconds = before.pbi_start_tvusec;
    strlcpy(result->name, before.pbi_name[0] ? before.pbi_name : before.pbi_comm, sizeof(result->name));

    struct rusage_info_v0 usage = {0};
    result->usage_status = proc_pid_rusage(pid, RUSAGE_INFO_V0, (rusage_info_t *)&usage) == 0 ? 0 : (errno ? errno : EIO);
    if (result->usage_status == 0) {
        mach_timebase_info_data_t base = {0};
        if (mach_timebase_info(&base) == KERN_SUCCESS && base.denom != 0) {
            /* rusage CPU durations are Mach ticks, NOT nanoseconds on Apple silicon. */
            uint64_t user = ticks_to_ns(usage.ri_user_time, base);
            uint64_t system = ticks_to_ns(usage.ri_system_time, base);
            result->cpu_nanoseconds = UINT64_MAX - user < system ? UINT64_MAX : user + system;
            result->footprint = usage.ri_phys_footprint;
            result->resident = usage.ri_resident_size;
        } else { result->usage_status = EIO; }
    }
    result->path_status = proc_pidpath(pid, result->path, sizeof(result->path)) > 0 ? 0 : (errno ? errno : EIO);
    struct mp_coalition_info coalition = {0};
    result->coalition_status = proc_pidinfo(pid, MP_COALITION_FLAVOR, 0, &coalition, sizeof(coalition)) == sizeof(coalition) ? 0 : ENOTSUP;
    if (result->coalition_status == 0) result->coalition = coalition.ids[0]; /* resource coalition */

    /* Reject exits or PID reuse between the metadata, resource and path reads. */
    if (proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &after, sizeof(after)) != sizeof(after)) return MP_PROCESS_GONE;
    if (after.pbi_uid != geteuid() || before.pbi_start_tvsec != after.pbi_start_tvsec || before.pbi_start_tvusec != after.pbi_start_tvusec)
        return MP_PROCESS_CHANGED;
    result->parent_pid = after.pbi_ppid;
    return 0;
}
