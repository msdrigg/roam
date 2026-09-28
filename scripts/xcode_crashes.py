#!/usr/bin/env python3
"""List Roam crashes Xcode Organizer has downloaded from Apple.

Reads the local cache Organizer writes under
~/Library/Developer/Xcode/Products/com.msdrigg.roam*/Crashes. That cache only
refreshes while Organizer's Crashes tab is open, so check `refreshed` in the
output before trusting it.

Crashes are grouped by the top frames of the thread that crashed. Xcode's own
point names come from an arbitrary thread and split one bug across many points.

    xcode_crashes.py                        # everything, grouped
    xcode_crashes.py --since 2026-09-20     # only logs dated on or after
    xcode_crashes.py --since 2026-09-20 --files   # also print log paths
"""

import argparse
import collections
import datetime
import glob
import json
import os
import re

ROOT = os.path.expanduser("~/Library/Developer/Xcode/Products")
NOISE = ("libdispatch", "libsystem_", "libswift_Concurrency", "libswiftCore.dylib")


def _field(text, key):
    m = re.search(r"^" + re.escape(key) + r":\s*(.*)$", text, re.M)
    return m.group(1).strip() if m else ""


def _crashed_frames(text):
    # iOS/watchOS logs say "Triggered by Thread", macOS logs say "Crashed Thread".
    n = _field(text, "Triggered by Thread") or _field(text, "Crashed Thread")
    n = n.split()[0] if n else ""
    m = re.search(r"^Thread %s Crashed:[^\n]*\n((?:.+\n)+)" % re.escape(n), text, re.M)
    if not m:
        return []
    frames = []
    for line in m.group(1).splitlines():
        line = re.sub(r"^\d+\s+", "", line.strip())
        line = re.sub(r"\s+0x[0-9a-f]+\s+", " ", line, count=1)
        # Drop offsets, source locations and load addresses so builds group together.
        line = re.sub(r"\s+\(.*?:-?\d+\)$|\s+\+ \d+|0x[0-9a-f]+", "", line).strip()
        if not line.startswith(NOISE) or "runtime failure" in line:
            frames.append(line)
    return frames


def _log_date(text):
    raw = _field(text, "Date/Time")[:19]
    try:
        return datetime.datetime.strptime(raw, "%Y-%m-%d %H:%M:%S").date()
    except ValueError:
        return None


def collect():
    rows = []
    for path in glob.glob(ROOT + "/com.msdrigg.roam*/Crashes/Points/*.xccrashpoint/Filters/*/Logs/*.crash"):
        filt = os.path.dirname(os.path.dirname(path))
        refreshed = ""
        try:
            with open(os.path.join(filt, "DistributionInfo.json")) as f:
                refreshed = json.load(f)["header"].get("lastRefresh", "")
        except (OSError, ValueError, KeyError):
            pass
        with open(path, errors="replace") as f:
            text = f.read()
        frames = _crashed_frames(text)
        rows.append({
            "bundle": _field(text, "Identifier"),
            "version": _field(text, "Version"),
            "os": _field(text, "OS Version"),
            "hardware": _field(text, "Hardware Model"),
            "exception": _field(text, "Exception Type"),
            "date": _log_date(text),
            "refreshed": refreshed,
            "signature": " | ".join(frames[:3]) or "(no crashed thread)",
            "path": path,
        })
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--since", type=datetime.date.fromisoformat, help="YYYY-MM-DD")
    ap.add_argument("--files", action="store_true", help="print each log's path")
    args = ap.parse_args()

    rows = collect()
    if not rows:
        raise SystemExit(f"No crash logs under {ROOT}. Open Xcode > Window > Organizer > Crashes first.")
    refreshed = max(r["refreshed"] for r in rows)
    if args.since:
        rows = [r for r in rows if r["date"] and r["date"] >= args.since]
    print(f"refreshed: {refreshed or 'unknown'}   logs: {len(rows)}")

    groups = collections.defaultdict(list)
    for r in rows:
        groups[(r["bundle"], r["signature"])].append(r)
    for (bundle, sig), rs in sorted(groups.items(), key=lambda kv: -len(kv[1])):
        versions = sorted({r["version"].split()[0] for r in rs})
        dates = sorted(r["date"].isoformat() for r in rs if r["date"])
        span = f"{dates[0]}..{dates[-1]}" if dates else "?"
        print(f"\n[{len(rs)}] {bundle}  versions={','.join(versions)}  {span}  {rs[0]['exception']}")
        print(f"    {sig}")
        if args.files:
            for r in sorted(rs, key=lambda r: str(r["date"]), reverse=True):
                print(f"    {r['date']} {r['hardware']} {r['os']}  {r['path']}")


if __name__ == "__main__":
    main()
