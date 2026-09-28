---
name: roam-crash-triage
description: Triage Roam crash reports through the backend API - list unreviewed crashes, read Discord threads and messages with pagination, stream symbolicated reports and other attachments, post replies, and mark threads reviewed. Use when asked to look at crashes, check what crashes are outstanding, read a crash report or thread, reply to a crash, or work through the crash review queue. Also cross-checks the crashes Xcode Organizer downloaded from Apple, which cover the watch app and widgets the backend never sees. Needs only BACKEND_URL and CRASH_API_KEY, both already in ./backend/.env - never a Discord token.
---

# Roam crash triage

Everything here goes through the Roam backend, which proxies Discord using its
own bot credentials. **You never need a Discord token.** Two environment
variables are enough:

```bash
export BACKEND_URL=https://backend.roam.msd3.io
export CRASH_API_KEY=...              # sent as the x-api-key header
```

Both already live in `./backend/.env` in this repo - source it rather than
hunting for the values in 1Password, and source it rather than reading the file,
so the key never lands in the transcript:

```bash
set -a && . ./backend/.env && set +a
```

A helper script at `scripts/roam_crashes.py` (repo root) wraps the endpoints below:

```bash
python3 scripts/roam_crashes.py --help
```

## How crash review works

When a crash finishes symbolicating, the backend posts `symbolicated.txt` into
the reporter's Discord thread and records the crash in `crash_reviews`. It then
runs the report against the auto-review rules:

- **A rule matches a build older than the rule's `fixed_in` version** → the
  backend replies in-thread with the known diagnosis, tagged `Fixed in <version>`,
  and marks the thread reviewed as `auto:<rule id>`. Nothing left to do.
- **…and the device has already updated past `fixed_in`** → same diagnosis,
  tagged `Fixed in <version>, and already updated`, reviewed the same way, but
  with no prompt to update. The crash is real and historical; the build that
  produced it is no longer installed.
- **A rule matches a build at or past its `fixed_in` version** → the reply goes
  out tagged **UNFIXED**, the rule id and note land on the row, but the thread
  is left **unreviewed**. The stack outlived its fix, so it needs
  you: expect these in the queue with a `matched_rule_id` already set.
- **A rule matches a report with no version at all** → replied to as
  `Fix status unknown` and reviewed, same as the fixed case.
- **No rule matches** → the thread stays unreviewed. That is the queue you work.

### The two versions on a report

They routinely disagree, and reading the wrong one is the classic mistake here:

- `app_version` is the crash's own MetricKit `appVersion` - **the build that
  died**, and what fix status is scored against.
- `installed_version` is `release=` off the report's `Install:` line - what the
  device was running when it *uploaded* the payload, which is up to a day later
  and may be across an App Store update.

So a row reading `app_version: 1.53, installed_version: 1.54` is not a parsing
bug: that user crashed on 1.53 and has since updated. Quote `app_version` when
you describe what crashed.

Both are filters on `/v2/crashes` and they AND together, which is what makes
the pair useful: `app_version=1.53&installed_version=1.53` is everyone still
sitting on the build that crashed them, while
`app_version=1.53&installed_version=1.54` is everyone the update already
carried past it.

Every message the backend posts into a crash thread starts with `:ninja:`,
which hides it from the reporter's in-app chat and from the AI responder. Keep
that prefix on any reply you post through the API below.

A thread is unreviewed when it was never reviewed *or* when a newer crash
arrived after the last review, so marking a thread reviewed silences it only
until its next crash.

## Start here: what needs attention

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/crashes?unreviewed=true&limit=50"
```

Each entry carries enough to triage without downloading anything:
`thread_id`, `latest_crash_message_id`, `latest_crash_at_ms`, `app_version`,
`installed_version`, `device_type`, `os_version`, `exception_type`, `signal`,
`termination_code`, and the review fields.

Filter and page:

| Query param | Meaning |
|---|---|
| `unreviewed=true` | only threads needing attention |
| `app_version=1.50` | exact match on the crash's `appVersion` - the build that died |
| `installed_version=1.50` | exact match on the release the device is *running* now |
| `before_ms=<ms>` | page backwards; pass the previous page's `next_before_ms` |
| `limit=<n>` | 1–200, default 50 |

`next_before_ms` in the response is the cursor for the next page, or `null` on
the last page. Loop until it is `null`.

One thread:

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" "$BACKEND_URL/v2/crashes/<thread_id>"
```

## Reading a thread

List messages, newest first (`limit` 1–100, default 50):

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages?limit=50"
```

Page further back with `before=<message_id>`, or forward with
`after=<message_id>`. IDs are strings - snowflakes exceed JavaScript's safe
integer range, so every id in these APIs is a string on the wire.

One message:

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages/<message_id>"
```

All threads in the support forum (`archived_pages` walks 100 archived threads
per page, 0 = active only, max 20):

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/discord/threads?archived_pages=3"
```

## Downloading documents

Attachments stream straight through the backend from Discord's CDN - nothing is
buffered server-side, so large diagnostics dumps are fine. Take the
`attachments[].id` from a message and:

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages/<message_id>/attachments/<attachment_id>" \
  -o symbolicated.txt
```

Write it to a file and read that, rather than piping a whole report into
context. The interesting parts of a symbolicated report are:

- `Termination reason:` and `Diagnosis:` - present when the payload carried one;
  these name the OS policy that killed the process
- the `Metadata:` block - `exceptionType`, `signal`, `appVersion`, `deviceType`
- the thread marked `(attributed)` - the only stack that caused the crash
- `In-process backtrace of the faulting thread` - the app's own capture, from
  its `SIGSEGV`/`SIGBUS` handler on an alternate signal stack
- `Logs` - check the header line, which says whether they are pre-crash

Read the attributed thread. Other threads are usually idle and will mislead you.

**When the attributed thread has no frames**, the process blew its stack:
MetricKit cannot unwind an overflowed stack and reports the thread empty. Go to
the in-process backtrace instead - a frame repeating down that list is the
recursion. Confirm from the `Faulting VM region:` line, which will point into
`Stack Guard`.

The `Logs` header says where the lines came from. "Replayed from the app's own
file log for the run that crashed" means they predate the crash and are worth
reading. The older wording - "from this process only" - means the app had no
file log for that run, so the lines are from the launch *after* the crash and
say nothing about it.

## Replying and marking reviewed

Post a reply (mentions are always suppressed):

```bash
curl -s -X POST -H "x-api-key: $CRASH_API_KEY" -H "Content-Type: application/json" \
  "$BACKEND_URL/v2/discord/threads/<thread_id>/messages" \
  -d '{"content": "...", "reply_to_message_id": "<crash_message_id>"}'
```

Then mark the thread reviewed. Every field is optional:

```bash
curl -s -X POST -H "x-api-key: $CRASH_API_KEY" -H "Content-Type: application/json" \
  "$BACKEND_URL/v2/crashes/<thread_id>/review" \
  -d '{"reviewed_by": "scott", "reviewed_message_id": "<reply_id>", "note": "..."}'
```

Reopen one you want to revisit:

```bash
curl -s -X DELETE -H "x-api-key: $CRASH_API_KEY" \
  "$BACKEND_URL/v2/crashes/<thread_id>/review"
```

## Auto-review rules

```bash
curl -s -H "x-api-key: $CRASH_API_KEY" "$BACKEND_URL/v2/crashes/rules"
```

Rules live in `backend/src/crash_rules.rs` as a compiled-in list, matched in
order with first-match-wins. Each has an `id`, optional `exception_type` /
`signal` / `termination_code`, `all_of` / `none_of` substrings matched against
the report text, and the `reply` markdown that gets posted.

**When you diagnose a crash that recurs, add a rule** rather than replying by
hand a second time. Put narrower rules first - several distinct bugs share
`EXC_CRASH (10)` / `SIGKILL (9)`, so a rule keyed only on that pair will
swallow others. Add a test in the same file covering the new report shape and
asserting it does not steal matches from existing rules.

## Crash counts over time

`/v2/crashes` is one row per thread. For "how many crashes", use the
per-crash records, one per `Crash N` section of every report:

```bash
python3 scripts/roam_crashes.py daily --since 2026-06-01
python3 scripts/roam_crashes.py records --app-version 1.58
```

Both hide simulator/debug builds unless `--include-dev`. Days are the device's
local date from the payload window. Reports posted before the table existed
need `python3 scripts/roam_crashes.py backfill` once; it is idempotent.

## Working the queue

1. `GET /v2/crashes?unreviewed=true` - see what is outstanding.
2. For each, download the `symbolicated.txt` attachment and read the attributed
   thread.
3. Recognisable and already fixed → reply, mark reviewed, and consider adding a
   rule so it self-serves next time.
4. Novel → diagnose it, fix it in the app, then reply, mark reviewed, and add a
   rule.
5. Check Xcode Organizer for anything the backend cannot see (next section).

Do not mark a thread reviewed without actually replying to it; the review flag
is a record that someone answered, not that someone looked.

## Crashes the backend never sees: Xcode Organizer

The backend only hears about crashes the iOS/macOS/visionOS **main app**
uploads from its MetricKit subscriber (`Roam/MetricManager.swift`, compiled
into the `Roam` target only). Apple's own crash collection, shown in Xcode
Organizer, also covers what that path cannot:

- **The watch app.** MetricKit does not exist on watchOS (`API_UNAVAILABLE(watchos)`,
  no framework in the watchOS SDK). Watch crashes reach Organizer and nowhere else.
- **Widget and intent extensions** (`*.RoamWidgets`), on every platform. No
  subscriber runs in them and their crashes have never reached the backend.
- **Builds before 1.49**, which predate `/v2/upload-diagnostics`, and anything
  before the review table started in mid-August 2026.
- **Launches that die before `RoamApp.init`** subscribes (dyld failures, a
  crash in a static initialiser) on every launch, so no later run uploads them.

Organizer caches what it downloads under
`~/Library/Developer/Xcode/Products/com.msdrigg.roam*/Crashes`, and only
refreshes while its Crashes tab is open. At the start of a triage pass, have the
user open **Xcode > Window > Organizer > Crashes** with Roam selected (or do it
with computer use), wait for it to finish loading, then:

```bash
python3 scripts/xcode_crashes.py --since <date of the last triage pass>
python3 scripts/xcode_crashes.py --since 2026-09-20 --files   # log paths too
```

Use the newest `reviewed_at_ms` in `/v2/crashes` as the last pass if nobody
says otherwise. Check the `refreshed:` line first: a stale timestamp means
Organizer was not opened and the list is old.

The script groups by the top frames of the thread that crashed. Do not trust
Xcode's own point names: Organizer labels a point after an arbitrary thread,
so one bug shows up as a dozen points named after TipKit, WatchConnectivity or
UIKit. The `.crash` files are already symbolicated; read them directly.

For each group:

1. Main-app crash on 1.49+ → it should already be in the backend. Match it to a
   thread or rule (`installed_version`, device, date) and move on.
2. Watch, widget, or pre-1.49 → it has no thread, so there is nobody to reply
   to and nothing to mark reviewed. Diagnose and fix in the app; if it is
   already fixed, note the version that fixed it in your summary.
3. `ARM64_32` in the `Code Type:` line means a 32-bit-`Int` watch (Series 4-8,
   SE). Any `Double` to `Int` conversion of epoch milliseconds traps there.

Known Organizer-only history:

| Signature | Builds | Status |
|---|---|---|
| `FileLog.runFileName` Double→Int overflow, watch app and watch widget | 1.52-1.59 | Fixed in the release after 1.59 (`Int64` in `FileLog.swift`) |
| `demandSharedModelContainer` SwiftData fatal, macOS widget | 1.35 | Old SwiftData build still installed somewhere; code is gone |
| `demandSharedModelContainer`, sqlite SIGKILLs, iOS app | 1.48 | Pre-GRDB, pre-upload |
| dyld `Library not loaded: RoamGRDB.framework`, iOS 27 | 1.50 | Fixed in `432d7c6` |

