#!/usr/bin/env python3
"""Bounded, read-only resource measurement of the packaged GUI, not the probe.

CPU uses libproc Mach durations converted with the device timebase; 100% is one
core. Verifies the executable and process start identity on every read. Does not
include WindowServer or other apps. Diagnostic input is optional and local.
"""
import argparse
import ctypes as c
import json
from pathlib import Path
import statistics
import subprocess
import time


class Usage(c.Structure):
    _fields_ = [("uuid", c.c_uint8 * 16)] + [(name, c.c_uint64) for name in (
        "user", "system", "pkg_wakeups", "interrupt_wakeups", "pageins",
        "wired", "resident", "footprint", "start", "exit")]


class Timebase(c.Structure):
    _fields_ = [("numer", c.c_uint32), ("denom", c.c_uint32)]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--duration", type=int, default=60, choices=range(15, 301), metavar="15..300")
    parser.add_argument("--mode", choices=("foreground", "background", "paused"), required=True)
    parser.add_argument("--diagnostics", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    expected = Path(__file__).resolve().parents[1] / "MacPulse.app/Contents/MacOS/MacPulse"
    lib = c.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    lib.proc_pidpath.argtypes = [c.c_int, c.c_void_p, c.c_uint32]
    lib.proc_pid_rusage.argtypes = [c.c_int, c.c_int, c.c_void_p]
    system = c.CDLL("/usr/lib/libSystem.B.dylib")
    base = Timebase()
    if system.mach_timebase_info(c.byref(base)) != 0 or base.denom == 0:
        raise RuntimeError("Mach timebase unavailable")
    candidates = subprocess.run(["pgrep", "-x", "MacPulse"], capture_output=True, text=True, check=True).stdout.split()
    matching = []
    for pid in map(int, candidates):
        buf = c.create_string_buffer(4096)
        if lib.proc_pidpath(pid, buf, len(buf)) > 0 and Path(buf.value.decode()).resolve() == expected:
            matching.append(pid)
    if len(matching) != 1:
        raise RuntimeError("Expected exactly one packaged GUI process")
    pid = matching[0]

    def read():
        buf = c.create_string_buffer(4096)
        usage = Usage()
        if lib.proc_pidpath(pid, buf, len(buf)) <= 0 or Path(buf.value.decode()).resolve() != expected:
            raise RuntimeError("GUI process exited or executable changed")
        if lib.proc_pid_rusage(pid, 0, c.byref(usage)) != 0 or usage.exit:
            raise RuntimeError("GUI resource read unavailable")
        return usage, time.monotonic()

    previous, stamp = read()
    identity = previous.start
    samples = []
    for _ in range(args.duration):
        time.sleep(1)
        usage, now = read()
        if usage.start != identity:
            raise RuntimeError("Process identity changed")
        elapsed = now - stamp
        cpu_ns = ((usage.user + usage.system) - (previous.user + previous.system)) * base.numer / base.denom
        if cpu_ns < 0:
            raise RuntimeError("CPU counters reset")
        entry = {"elapsed": elapsed, "cpu": cpu_ns / (elapsed * 1e9) * 100,
                 "footprintMiB": usage.footprint / 2**20, "rssMiB": usage.resident / 2**20}
        if args.diagnostics:
            d = json.loads(args.diagnostics.read_text())
            visible = d["mainVisible"] or d["panelVisible"]
            valid = d["paused"] if args.mode == "paused" else not d["paused"] and visible == (args.mode == "foreground")
            if not valid or d["starts"] != 1 or d["stopped"] or d["sleeping"]:
                raise RuntimeError("Requested mode or single-loop condition was not maintained")
            entry["diagnostics"] = d
        samples.append(entry)
        previous, stamp = usage, now
    cpus = [s["cpu"] for s in samples]
    duration = sum(s["elapsed"] for s in samples)
    result = {"mode": args.mode, "durationSeconds": duration, "readCount": len(samples), "cpuScope": "100% = one logical core; GUI process only",
              "cpuAveragePercent": sum(s["cpu"] * s["elapsed"] for s in samples) / duration,
              "cpuMedianPercent": statistics.median(cpus), "cpuPeakOneSecondPercent": max(cpus),
              "footprintRangeMiB": [min(s["footprintMiB"] for s in samples), max(s["footprintMiB"] for s in samples)],
              "rssRangeMiB": [min(s["rssMiB"] for s in samples), max(s["rssMiB"] for s in samples)], "samples": samples}
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    args.output.chmod(0o600)
    print(json.dumps({k: v for k, v in result.items() if k != "samples"}, indent=2))


if __name__ == "__main__":
    main()
