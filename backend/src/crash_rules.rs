//! Auto-review rules for symbolicated crash reports.
//!
//! A completed symbolication is matched against [`RULES`]. The first match
//! wins: its reply is posted in-thread and the thread is marked reviewed as
//! `auto:<rule id>`. Unmatched reports stay in `GET /v2/crashes/unreviewed`.
//!
//! Matches are tagged against the crash's own `appVersion`, not the `Install:`
//! line, which records what the device runs now and can be a later release.

use std::sync::LazyLock;

use regex::Regex;

/// Facts pulled out of a rendered report for matching, stored on the review
/// row so list endpoints can triage without re-downloading attachments.
#[derive(Debug, Clone, Default, PartialEq, Eq, serde::Serialize)]
pub struct CrashFacts {
    /// Marketing version of the build that died. Absent on older reports.
    pub app_version: Option<String>,
    /// `release=` off the `Install:` line: what the device ran when it sent
    /// the payload, not necessarily what crashed.
    pub installed_version: Option<String>,
    pub device_type: Option<String>,
    pub os_version: Option<String>,
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    /// Termination code as lowercase hex with an `0x` prefix, e.g. `0x8badf00d`.
    pub termination_code: Option<String>,
    /// `Thermal Level:` from `ThermalInfo`. 0 is nominal, 9 is critical.
    pub thermal_level: Option<i64>,
    /// The app's own CPU share over the watchdog window, from `Elapsed
    /// application CPU time`. Not the `Elapsed total` figure.
    pub app_cpu_percent: Option<i64>,
}

/// Reads `  key: value` out of a rendered report's metadata block.
fn metadata_value(report: &str, key: &str) -> Option<String> {
    let pattern = format!(r"(?m)^\s*{}: (.+)$", regex::escape(key));
    let regex = Regex::new(&pattern).ok()?;
    regex
        .captures(report)
        .map(|caps| caps[1].trim().to_string())
        .filter(|value| !value.is_empty())
}

/// Extract the `Code 0x...` value out of a termination reason line.
fn termination_code(report: &str) -> Option<String> {
    static RE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"(?i)code[: ]\s*0x([0-9a-f]+)").expect("valid code regex"));
    let reason = metadata_value(report, "terminationReason")
        .or_else(|| metadata_value(report, "Termination reason"))?;
    RE.captures(&reason)
        .map(|caps| format!("0x{}", caps[1].to_ascii_lowercase()))
}

/// Reads `Thermal Level:   9` out of the report.
///
/// Matched against the whole report: `ThermalInfo` sits inside the multi-line
/// `terminationReason` value, which [`metadata_value`] does not reach.
fn thermal_level(report: &str) -> Option<i64> {
    static RE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"Thermal Level:\s*(\d+)").expect("valid thermal regex"));
    RE.captures(report)?[1].parse().ok()
}

/// Reads `release=<version>` off the report's `Install:` line, which records
/// what the device runs now rather than what crashed.
fn installed_version(report: &str) -> Option<String> {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?m)^Install:.*?\brelease=(\S+)").expect("valid install-line regex")
    });
    RE.captures(report)
        .map(|caps| caps[1].to_string())
        .filter(|value| value != "unknown")
}

/// Reads the percentage off the `Elapsed application CPU time` line.
fn app_cpu_percent(report: &str) -> Option<i64> {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"Elapsed application CPU time \(seconds\): [\d.]+, (\d+)% CPU")
            .expect("valid app cpu regex")
    });
    RE.captures(report)?[1].parse().ok()
}

impl CrashFacts {
    pub fn from_report(report: &str) -> Self {
        Self {
            app_version: metadata_value(report, "appVersion"),
            installed_version: installed_version(report),
            device_type: metadata_value(report, "deviceType"),
            os_version: metadata_value(report, "osVersion"),
            exception_type: metadata_value(report, "exceptionType").and_then(|v| v.parse().ok()),
            signal: metadata_value(report, "signal").and_then(|v| v.parse().ok()),
            termination_code: termination_code(report),
            thermal_level: thermal_level(report),
            app_cpu_percent: app_cpu_percent(report),
        }
    }

    /// The version to place against a rule's `fixed_in`: the crash's own
    /// `appVersion`, falling back to the installed release on older reports.
    /// [`CrashFacts::version_phrase`] flags the fallback in the reply.
    pub fn crash_version(&self) -> Option<&str> {
        self.app_version
            .as_deref()
            .or(self.installed_version.as_deref())
    }

    /// Names [`CrashFacts::crash_version`] for a reply, flagging the fallback.
    fn version_phrase(&self) -> String {
        match (
            self.app_version.as_deref(),
            self.installed_version.as_deref(),
        ) {
            (Some(version), _) => format!("from {version}"),
            (None, Some(version)) => format!(
                "from {version} (the release the device reports installed - this report carries no `appVersion`)"
            ),
            (None, None) => "from an unrecorded version".to_string(),
        }
    }
}

/// Parses a dotted numeric version into comparable components. Anything after
/// the leading `[0-9.]` run is dropped, so `1.51 (204)` reads as `1.51`.
fn parse_version(version: &str) -> Option<Vec<u64>> {
    let numeric: String = version
        .trim()
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let parts: Vec<u64> = numeric
        .split('.')
        .filter(|part| !part.is_empty())
        .map(|part| part.parse().ok())
        .collect::<Option<_>>()?;
    (!parts.is_empty()).then_some(parts)
}

/// How a matched rule's fix relates to the crash's version. Comparison is
/// component-wise, so `1.50 < 1.51 < 1.51.1`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FixStatus {
    /// Crash and device both predate the fix; updating resolves it.
    Fixed,
    /// Crash predates the fix and the device has already updated past it, so
    /// there is no action for the reporter.
    AlreadyUpdated,
    /// Crash is from the fixing release or later, so the fix did not hold.
    Unfixed,
    /// Not a defect in the app, so there is no version to compare against.
    NotADefect,
    /// No usable version on the report at all, or no fix version on the rule.
    Unknown,
}

/// A single auto-review rule. All specified conditions must hold.
#[derive(Debug, Clone, serde::Serialize)]
pub struct CrashRule {
    pub id: &'static str,
    pub title: &'static str,
    /// App version that shipped this rule's fix, e.g. `"1.51"`. Crashes from
    /// this version onwards are tagged [`FixStatus::Unfixed`].
    pub fixed_in: Option<&'static str>,
    /// The kill comes from the device or OS rather than the app. Matching
    /// reports are tagged [`FixStatus::NotADefect`]. Set only where the report
    /// itself carries the evidence.
    pub environmental: bool,
    /// Mach exception type, e.g. 10 for `EXC_CRASH`, 12 for `EXC_GUARD`.
    pub exception_type: Option<i64>,
    pub signal: Option<i64>,
    /// Lowercase hex termination code, e.g. `0x8badf00d`.
    pub termination_code: Option<&'static str>,
    /// Minimum `Thermal Level:`, inclusive. A report with no thermal figure
    /// does not match.
    pub min_thermal_level: Option<i64>,
    /// Maximum `Elapsed application CPU time` percentage, inclusive. This is
    /// the app's own share, not `Elapsed total`. No figure means no match.
    pub max_app_cpu_percent: Option<i64>,
    /// Substrings that must all appear somewhere in the report (stack frames).
    pub all_of: &'static [&'static str],
    /// Substrings that must not appear. Used to keep rules from overlapping.
    pub none_of: &'static [&'static str],
    /// Markdown posted into the thread when this rule matches.
    pub reply: &'static str,
}

impl CrashRule {
    pub fn matches(&self, report: &str, facts: &CrashFacts) -> bool {
        if let Some(expected) = self.exception_type
            && facts.exception_type != Some(expected)
        {
            return false;
        }
        if let Some(expected) = self.signal
            && facts.signal != Some(expected)
        {
            return false;
        }
        if let Some(expected) = self.termination_code
            && facts.termination_code.as_deref() != Some(expected)
        {
            return false;
        }
        if let Some(minimum) = self.min_thermal_level
            && facts.thermal_level.is_none_or(|level| level < minimum)
        {
            return false;
        }
        if let Some(maximum) = self.max_app_cpu_percent
            && facts.app_cpu_percent.is_none_or(|share| share > maximum)
        {
            return false;
        }
        if !self.all_of.iter().all(|needle| report.contains(needle)) {
            return false;
        }
        if self.none_of.iter().any(|needle| report.contains(needle)) {
            return false;
        }
        true
    }

    /// Places the crash's version against the release that fixed this rule.
    /// Keyed on [`CrashFacts::crash_version`]; the installed release only
    /// decides whether the reporter still has anything to do.
    pub fn fix_status(&self, facts: &CrashFacts) -> FixStatus {
        if self.environmental {
            return FixStatus::NotADefect;
        }
        let Some(fixed_in) = self.fixed_in.and_then(parse_version) else {
            return FixStatus::Unknown;
        };
        let Some(crashed_on) = facts.crash_version().and_then(parse_version) else {
            return FixStatus::Unknown;
        };
        if crashed_on >= fixed_in {
            return FixStatus::Unfixed;
        }
        match facts.installed_version.as_deref().and_then(parse_version) {
            Some(installed) if installed >= fixed_in => FixStatus::AlreadyUpdated,
            _ => FixStatus::Fixed,
        }
    }
}

/// A matched rule plus where the crash sits relative to its fix.
#[derive(Debug, Clone, Copy)]
pub struct RuleMatch {
    pub rule: &'static CrashRule,
    pub status: FixStatus,
}

impl RuleMatch {
    /// Markdown to post in-thread: diagnosis, then the fix placement.
    pub fn reply(&self, facts: &CrashFacts) -> String {
        let fixed_in = self.rule.fixed_in.unwrap_or("a later release");
        let version = facts.version_phrase();
        let verdict = match self.status {
            FixStatus::Fixed => format!(
                ":white_check_mark: **Fixed in {fixed_in}.** This report is {version}, which predates the fix - updating to {fixed_in} or later resolves it."
            ),
            FixStatus::AlreadyUpdated => format!(
                ":white_check_mark: **Fixed in {fixed_in}, and already updated.** This report is {version}, which predates the fix, but the device is now on {} - the build that crashed is no longer installed, so there is nothing to do.",
                facts.installed_version.as_deref().unwrap_or(fixed_in),
            ),
            FixStatus::Unfixed => format!(
                ":rotating_light: **UNFIXED.** The fix above shipped in {fixed_in}, and this report is {version} - the crash survived it. Left unreviewed for a human."
            ),
            FixStatus::NotADefect => ":thermometer: **Nothing to fix in the app.** The report itself carries the evidence that the system, not Roam, ended the process - see above. Reviewed automatically; reopen the thread if you disagree.".to_string(),
            FixStatus::Unknown => match self.rule.fixed_in {
                Some(version) => format!(
                    ":grey_question: **Fix status unknown.** The fix shipped in {version}, but this report carries neither an `appVersion` nor an installed release, so whether it predates the fix is unclear."
                ),
                None => ":grey_question: **Fix status unknown.** No fix version is recorded for this rule.".to_string(),
            },
        };
        format!(
            "{}\n\n{verdict}\n\n_Matched automatically by rule `{}`._",
            self.rule.reply, self.rule.id
        )
    }

    /// One line for the review row, so triage need not open the thread.
    pub fn review_note(&self, facts: &CrashFacts) -> String {
        let title = self.rule.title;
        match (self.status, self.rule.fixed_in) {
            (FixStatus::Fixed, Some(fixed_in)) => format!("{title} (fixed in {fixed_in})"),
            (FixStatus::AlreadyUpdated, Some(fixed_in)) => format!(
                "{title} (fixed in {fixed_in}; device already on {})",
                facts.installed_version.as_deref().unwrap_or(fixed_in),
            ),
            (FixStatus::Unfixed, Some(fixed_in)) => format!(
                "UNFIXED - still crashing on {} after the {fixed_in} fix: {title}",
                facts.crash_version().unwrap_or("a later version"),
            ),
            (FixStatus::NotADefect, _) => format!("{title} (not an app defect)"),
            _ => format!("{title} (fix status unknown)"),
        }
    }
}

/// Returns the first rule matching the report, if any.
pub fn match_rule(report: &str, facts: &CrashFacts) -> Option<RuleMatch> {
    RULES
        .iter()
        .find(|rule| rule.matches(report, facts))
        .map(|rule| RuleMatch {
            rule,
            status: rule.fix_status(facts),
        })
}

const LAUNCH_DATABASE_LOCK_REPLY: &str = ":ninja: **Auto-review: `0xdead10cc` during database startup migration**

The termination reason confirms that iOS suspended Roam while it held a shared-container file or SQLite lock. The stack places the database migration inside the shared data handler's first open.

The launch guard used to be requested in `RoamApp.init`, before `UIApplicationMain` created `UIApplication`. That request returned an invalid background-task identifier, leaving the migration without suspension protection.

**Fix in 1.58:** open the database and read the legacy SwiftData store in `application(_:willFinishLaunchingWithOptions:)`, after acquiring a background task and before constructing the app's scenes. Release the task when initialization returns.";

const DEAD10CC_REPLY: &str = ":ninja: **Auto-review: `0xdead10cc` - suspended while holding the database lock**

`EXC_CRASH (10)` / `SIGKILL (9)` with the attributed thread in the middle of a database write. This is not a fault in the app's own code; iOS killed the process.

Persistent writes hold an exclusive `flock` on a lock file in the shared app-group container, on top of the SQLite/WAL locks on `Roam.sqlite` beside it. A suspended process still holding those can block the widget extension indefinitely, so the system terminates it.

**Known cause, fix:**
- a background-task assertion is held across every persistent write, so the process stays alive long enough to commit and release the lock
- the file lock covers the transaction only - it used to be held across a full snapshot reload that scans every table
- automatic device discovery stops when the app is backgrounded, removing the main source of writes still in flight at suspension time";

const EXC_GUARD_REPLY: &str = ":ninja: **Auto-review: `EXC_GUARD` - the SSDP socket was closed twice**

`EXC_GUARD (12)`, attributed to `close()` inside the `defer` in `scanDevicesContinually`.

That function closed its UDP socket in two places: the `onCancel` handler of `withTaskCancellationHandler` (which is what interrupts the blocking `receiveFrom`), and the body's own `defer` as it unwinds. On cancellation both run, so `close(2)` fires twice on the same descriptor. By the second call the kernel has usually reused that number, and when the new owner is a *guarded* descriptor - GRDB's SQLite handles and Network.framework both guard theirs - the process is killed on the spot.

`try? socket.close()` cannot defend against this: `EXC_GUARD` is a Mach exception, not an `errno`.

**Known cause, fix:** both paths now go through a close-once wrapper, so the descriptor reaches `close(2)` exactly once regardless of which path wins the race.";

const SCENE_UPDATE_REENTRANCY_REPLY: &str = ":ninja: **Auto-review: stack overflow - the macOS scene update pass re-entered itself**

`EXC_BAD_ACCESS (1)` / `SIGSEGV (11)` with the faulting address in the **Stack Guard** region below the main thread's stack: unbounded recursion, not a dangling pointer.

MetricKit cannot unwind an overflowed stack, so the attributed thread often shows only a Swift runtime frame. The in-process backtrace holds the cycle: `AppGraph.graphDidChange` alternating with `AppDelegate.scenesDidChange` for dozens of pairs.

A scene-phase change delivered inside a SwiftUI update seeds it, usually launch-time window restoration ordering the main window on screen. What sustains it is inside SwiftUI on macOS 26.5 through 26.7: `AppDelegate.scenesDidChange` copies the scenes' `Scene.keyboardShortcut` table into an attribute that AttributeGraph compares by storage identity, so a non-empty table reads as changed on every pass. That dirties every scene body, and `scenesDidChange` calls `graphDidChange` again from inside the pass that called it. An empty table compares equal, so the pass settles.

Roam put `.keyboardShortcut` on three `Window` scenes, and that is the trigger. The seeding frame (`forceFront`, `MenuBarExtra`, `applicationDidChangeScreenParameters`, a `Settings` body) varies between reports and only shows where the stack ran out.

**Known cause, fix:** the window shortcuts moved from `Scene.keyboardShortcut` to Window-menu commands, so the scene shortcut table stays empty and the update pass cannot re-enter itself.";

const WATCHDOG_REPLY: &str = ":ninja: **Auto-review: `0x8BADF00D` watchdog - main thread blocked cancelling the Bonjour browser**

The termination reason pins this down: the process failed to terminate within its 5 second budget.

The attributed thread is the **main thread**, parked in `nw_browser_cancel`, reached from `requestLocalNetworkAuthorization`'s `onCancel` handler.

`onCancel` runs synchronously on whichever thread cancels the task, and SwiftUI cancels `.task` work on the main thread while it applies a scene-phase change. `NWBrowser.cancel()` and `NWListener.cancel()` block on an internal Network.framework lock, so when the network queue is busy the main thread stalls past the termination budget and the watchdog kills the app.

**Known cause, fix:** listener/browser teardown is dispatched onto the queue those objects already run on, so the cancelling thread is never blocked.";

const AUDIO_PLAYER_NODE_EXCEPTION_REPLY: &str = ":ninja: **Auto-review: `SIGABRT` - AVFAudio raised on `play()` against a stale output format**

`EXC_CRASH (10)` / `SIGABRT (6)`, and the attributed thread shows why: `objc_exception_throw` out of `-[AVAudioPlayerNode play]`, through `objc_terminate`, into `abort`. An Objective-C exception, not a signal in Roam's own code.

Swift cannot catch those. AVFoundation reports misuse by raising rather than returning an error, and an unhandled raise ends the process immediately - `try` around the call does nothing.

`AudioPlayer` built its engine connections and its `AVAudioConverter` once, in `init`, against the output device's format at that moment. On iOS a route change tears the session down and `handleRouteChange` rebuilds it, but macOS had no equivalent observer: the user switches default output device, the next `start()` succeeds against the new one, and the player node is still connected with the *old* device's format. `play()` raises on the mismatch.

The `guard engine.isRunning` ahead of it did not help - the engine really was running. It was the graph below it that was stale.

**Known cause, fix:** the graph and converter are now re-derived from the current output format on every `start()`, and a device reporting no usable format is rejected with a thrown error rather than left for AVFAudio to raise on. The `play()` and `scheduleBuffer` calls additionally run under an Objective-C exception trap, so a raise that still slips through surfaces as a Swift error instead of killing the process.";

const LOCAL_NETWORK_CANCEL_RACE_REPLY: &str = ":ninja: **Auto-review: `SIGSEGV` - the Bonjour browser was cancelled before it was started**

`EXC_BAD_ACCESS (1)` / `SIGSEGV (11)` on the near-null address `0x54` inside `nw_browser_cancel`, attributed to the local network permission check. Not the `0x8BADF00D` stall that `local-network-cancel-watchdog` describes, which carries a termination reason.

`NWBrowser.start(queue:)` is what hands Network.framework its delivery queue. Cancel a browser that has a state update handler but no queue and `nw_browser_set_state_locked` calls `dispatch_async` with a NULL queue, faulting at a fixed small offset. Apple tracks this as a framework bug (r.139710124, https://developer.apple.com/forums/thread/768413); the only defence is to never make the call.

Roam had two paths that could: the `Task.isCancelled` guard that runs before the endpoints start, and `withTaskCancellationHandler`'s `onCancel`, which fires the instant the task is cancelled, including before setup reaches `start(queue:)`. SwiftUI cancels `.task` work on a scene-phase change, so backgrounding the app during the check was enough. The 1.52 and 1.54 fixes addressed concurrent cancels and could not stop this first, premature one.

**Known cause, fix:** start and cancel go through an `EndpointLifecycle` wrapper that tracks whether the endpoints were started. A cancel before the start skips teardown entirely, and one arriving during the start is deferred until the queue is set. Cancelling twice is still claimed once and teardown still runs on the endpoints' own queue, so both earlier fixes hold.";

const THERMAL_STARVATION_REPLY: &str = ":ninja: **Auto-review: `0x8BADF00D` watchdog - the device was overheating, not the app**

`EXC_CRASH (10)` / `SIGKILL (9)` with a watchdog termination reason, but the numbers in that reason rule the app out as the cause:

- **`Thermal State: critical`** (thermal level 9) - the highest tier iOS reports. At that point the system is aggressively throttling every process on the device.
- **`Elapsed application CPU time: 0% CPU`** - Roam got a rounding error's worth of CPU across the whole watchdog window, while the device as a whole stayed busy. The process was not doing slow work; it was not being scheduled.

A scene-update deadline is wall-clock, not CPU-time, so a process that never gets scheduled blows through it without ever running. The attributed thread is whatever the app happened to be parked in when the clock ran out, and reading it will mislead you.

**Nothing to fix:** this resolves when the device cools down. Common causes are charging in direct sun, a heavy game or export running in the foreground, or a stuck background process elsewhere on the system.";

/// Ordered: the first match wins, so put narrower rules first.
pub static RULES: &[CrashRule] = &[
    CrashRule {
        id: "scene-update-reentrancy-stack-overflow",
        title: "Stack overflow from the macOS scene update pass re-entering itself",
        // 1.52 and 1.54 each closed a seeding path and the crash outlived both;
        // 1.56 removes the `Scene.keyboardShortcut` table that sustains the
        // cycle. A 1.56 or later report here means that diagnosis is wrong.
        fixed_in: Some("1.56"),
        environmental: false,
        exception_type: Some(1),
        signal: Some(11),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // Both halves of the cycle plus the overflow, and no app frame. The
        // frame that seeds it differs per report (`forceFront`, `MenuBarExtra`,
        // `applicationDidChangeScreenParameters`, or, on thread
        // 1543063503160606833, a `Settings` scene carrying none of the three),
        // so keying on one of them mis-attributes the rest and drops the
        // reports that carry none.
        all_of: &[
            "AppGraph.graphDidChange",
            "AppDelegate.scenesDidChange",
            "Stack Guard",
        ],
        none_of: &[],
        reply: SCENE_UPDATE_REENTRANCY_REPLY,
    },
    CrashRule {
        id: "local-network-cancel-watchdog",
        title: "0x8BADF00D watchdog cancelling NWBrowser on the main thread",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: None,
        signal: None,
        termination_code: Some("0x8badf00d"),
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["nw_browser_cancel"],
        none_of: &[],
        reply: WATCHDOG_REPLY,
    },
    // Kept next to the watchdog rule they share `nw_browser_cancel` with. The
    // termination code and SIGSEGV keep the two from colliding.
    CrashRule {
        // Historical id: the bug is a cancel before `start(queue:)`, not a
        // race. Renaming would orphan existing `auto:` rows in `crash_reviews`.
        id: "local-network-cancel-race",
        title: "SIGSEGV from cancelling NWBrowser before start(queue:) in the local network check",
        fixed_in: Some("1.55"),
        environmental: false,
        exception_type: Some(1),
        signal: Some(11),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // Framework frame alone. Keying on an app frame broke this rule when
        // 0a68d67c moved the cancel into a closure. `NWBrowser` is used in one
        // file, so the framework frame cannot over-claim.
        all_of: &["nw_browser_cancel"],
        none_of: &[],
        reply: LOCAL_NETWORK_CANCEL_RACE_REPLY,
    },
    // EXC_CRASH/SIGABRT, which separates it from the SIGKILL rules below.
    CrashRule {
        id: "audio-player-node-play-exception",
        title: "SIGABRT from AVAudioPlayerNode.play() raising on a stale output format",
        fixed_in: Some("1.54"),
        environmental: false,
        exception_type: Some(10),
        signal: Some(6),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        // Both ends of the call, since `AVAudioPlayerNode` alone would claim
        // any abort that merely had audio on some thread.
        all_of: &[
            "objc_exception_throw",
            "AVAudioPlayerNode",
            "AudioPlayer.start",
        ],
        none_of: &[],
        reply: AUDIO_PLAYER_NODE_EXCEPTION_REPLY,
    },
    CrashRule {
        id: "ssdp-socket-double-close",
        title: "EXC_GUARD from double-closing the SSDP socket",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: Some(12),
        signal: None,
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["scanDevicesContinually", "FileDescriptor._close"],
        none_of: &[],
        reply: EXC_GUARD_REPLY,
    },
    CrashRule {
        id: "launch-database-lock-suspension",
        title: "0xdead10cc during the shared database's startup migration",
        fixed_in: Some("1.58"),
        environmental: false,
        exception_type: Some(10),
        signal: Some(9),
        termination_code: Some("0xdead10cc"),
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &[
            "RoamDataHandler.getForShared",
            "RoamDatabase.init",
            "DatabaseMigrator.migrate",
            "DatabaseFileLock.withExclusiveLock",
        ],
        none_of: &[],
        reply: LAUNCH_DATABASE_LOCK_REPLY,
    },
    CrashRule {
        id: "database-lock-suspension",
        title: "0xdead10cc suspension while holding the database file lock",
        fixed_in: Some("1.51"),
        environmental: false,
        exception_type: Some(10),
        signal: Some(9),
        termination_code: None,
        min_thermal_level: None,
        max_app_cpu_percent: None,
        all_of: &["DatabaseFileLock.withExclusiveLock"],
        // Startup used a separate guard. Reports without a confirmed kill
        // policy must remain available for review under that diagnosis.
        none_of: &["RoamDataHandler.getForShared"],
        reply: DEAD10CC_REPLY,
    },
    // Last: broadest rule, naming no app frame. Only the thermal figure
    // separates it from a real deadlock.
    CrashRule {
        id: "thermal-starvation-watchdog",
        title: "0x8BADF00D watchdog while the device was thermally throttled",
        fixed_in: None,
        environmental: true,
        exception_type: Some(10),
        signal: Some(9),
        termination_code: Some("0x8badf00d"),
        // Top of the scale, reported alongside `Thermal State: critical`.
        min_thermal_level: Some(9),
        // Not `0`: a starved app still gets scheduled, and rounding puts that
        // at a few percent. What matters is the ratio against a pegged device.
        max_app_cpu_percent: Some(5),
        all_of: &[],
        none_of: &[],
        reply: THERMAL_STARVATION_REPLY,
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    const DEAD10CC_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Metadata:
  appVersion: 1.50
  deviceType: iPhone14,7
  exceptionType: 10
  osVersion: iPhone OS 26.6 (23G71)
  signal: 9
Thread 16 (attributed):
  Roam +0x54788 specialized DatabaseFileLock.withExclusiveLock<A> at /x/DatabaseFileLock.swift:37
"#;

    // Trimmed from the 1.57 startup report. Its payload omitted the kill
    // policy; tests add an explicit termination reason only where required.
    const LAUNCH_DATABASE_REPORT: &str = r#"
Metadata:
  appVersion: 1.57
  exceptionType: 10
  signal: 9
Thread 0 (attributed):
  RoamGRDB DatabaseMigrator.migrate
  Roam closure #1 in RoamDatabase.init
  Roam specialized DatabaseFileLock.withExclusiveLock<A>
  Roam RoamDatabase.init
  Roam specialized static RoamDataHandler.getForShared
  Roam RoamApp.init
"#;

    #[test]
    fn launch_migration_requires_a_confirmed_suspension_kill() {
        for reason in [
            "",
            "Termination reason: Namespace RUNNINGBOARD, Code 0x8badf00d\n",
            "Termination reason: Namespace RUNNINGBOARD, Code 0xc51bad01\n",
        ] {
            let report = format!("{reason}{LAUNCH_DATABASE_REPORT}");
            let facts = CrashFacts::from_report(&report);
            assert!(match_rule(&report, &facts).is_none());
        }
    }

    #[test]
    fn confirmed_launch_migration_uses_the_158_fix_boundary() {
        for (version, installed, expected) in [
            ("1.57", "1.57", FixStatus::Fixed),
            ("1.57", "1.58", FixStatus::AlreadyUpdated),
            ("1.58", "1.58", FixStatus::Unfixed),
            ("1.59", "1.59", FixStatus::Unfixed),
        ] {
            let stack = LAUNCH_DATABASE_REPORT
                .replace("appVersion: 1.57", &format!("appVersion: {version}"));
            // The fixed app opens from its launch delegate, so regressions
            // must still match after the App.init frame disappears.
            let stack = if expected == FixStatus::Unfixed {
                stack.replace(
                    "RoamApp.init",
                    "RoamAppDelegate.application(_:willFinishLaunchingWithOptions:)",
                )
            } else {
                stack
            };
            let report = format!(
                "Install: release={installed}\nTermination reason: Namespace RUNNINGBOARD, Code 0xDEAD10CC\n{stack}"
            );
            let facts = CrashFacts::from_report(&report);
            let matched = match_rule(&report, &facts).expect("confirmed launch migration");
            assert_eq!(matched.rule.id, "launch-database-lock-suspension");
            assert_eq!(matched.status, expected);
            assert!(matched.reply(&facts).contains("1.58"));
        }
    }

    #[test]
    fn launch_rule_requires_the_startup_migration_frames() {
        let report = format!(
            "Termination reason: Namespace RUNNINGBOARD, Code 0xdead10cc\n{LAUNCH_DATABASE_REPORT}"
        );
        for frame in [
            "RoamDataHandler.getForShared",
            "RoamDatabase.init",
            "DatabaseMigrator.migrate",
            "DatabaseFileLock.withExclusiveLock",
        ] {
            let report = report.replace(frame, "otherFunction");
            let facts = CrashFacts::from_report(&report);
            assert_ne!(
                match_rule(&report, &facts).map(|m| m.rule.id),
                Some("launch-database-lock-suspension")
            );
        }
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("launch-database-lock-suspension")
            );
        }
    }

    const GUARD_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Metadata:
  appVersion: 1.50
  deviceType: iPhone13,2
  exceptionType: 12
  signal: 0
Thread 13 (attributed):
  libswiftSystem.dylib +0x12800 FileDescriptor._close samples=1
    Roam +0x6f5a0 $defer #1  in closure #2 in scanDevicesContinually at /x samples=1
"#;

    const STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) - stack overflow
Faulting VM region: 0x16ca6fed0 is in 0x16926c000-0x16ca70000;  bytes after start: 58736336  bytes before end: 303
--->  Stack Guard                 16926c000-16ca70000    [ 56.0M] ---/rwx SM=PRV
      Stack                       16ca70000-16d26c000    [ 8176K] rw-/rwx SM=SHM
Metadata:
  appVersion: 1.51
  deviceType: iMac21,1
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.5.1 (25F80)
  signal: 11
Thread 0 (attributed - this is the thread that crashed):
  38  SwiftUI +0x1476c7c AppGraph.graphDidChange samples=1
  39  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange samples=1
  40  SwiftUI +0x1476c7c AppGraph.graphDidChange samples=1
  53  SwiftUI +0x10d76c  PlatformSceneCache.setPhase samples=1
  66  AppKit  +0x1275e8  -[NSWindow makeKeyAndOrderFront:] samples=1
  67  Roam    +0x5e2e8   NSApplication.forceFront at /x/RoamAppDelegate.swift:152 samples=1
"#;

    const WATCHDOG_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:[app<com.msdrigg.roam>:12124] Failed to terminate gracefully after 5.0s
Metadata:
  appVersion: 1.50
  deviceType: iPhone13,1
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:[app<com.msdrigg.roam>:12124] Failed to terminate gracefully after 5.0s
Thread 0 (attributed):
  Network +0x1158200 nw_browser_cancel samples=1
"#;

    /// Trimmed from thread 1540815884619227250 (roam 1.52, Mac16,12): the same
    /// recursion as `STACK_OVERFLOW_REPORT`, driven by `MenuBarExtra`. The
    /// in-process frames are demangled, as the renderer emits them.
    const MENU_BAR_STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) - stack overflow: the faulting address is inside the Stack Guard region directly below a thread stack
Faulting VM region: 0x16d197ea0 is in 0x169994000-0x16d198000;  bytes after start: 58736288  bytes before end: 351
--->  Stack Guard                 169994000-16d198000    [ 56.0M] ---/rwx SM=PRV
Metadata:
  appVersion: 1.52
  deviceType: Mac16,12
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.6.2 (25G83)
  signal: 11
Thread 0 (attributed - this is the thread that crashed):
  0   libswiftCore.dylib +0xae994 DecodedMetadataBuilder::createGenericTypeParameterType samples=1

In-process backtrace of the faulting thread (1)
  20  SwiftUI +0x1476c7c AppGraph.graphDidChange
  21  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange
  22  SwiftUI +0x8dc94a8 closure #1 in MenuBarExtra<>.init
  23  SwiftUI +0x1476c7c AppGraph.graphDidChange
  24  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange
"#;

    /// Thread 1436017918377984024 (roam 1.52, iPhone12,1): `nw_browser_cancel`
    /// with a SIGSEGV rather than `WATCHDOG_REPORT`'s watchdog kill.
    const LOCAL_NETWORK_RACE_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_INVALID_ADDRESS (1) / SIGSEGV (11)
Faulting VM region: 0x54 is not in any region.  Bytes before following region: 4376493996
Metadata:
  appVersion: 1.52
  deviceType: iPhone12,1
  exceptionCode: 1
  exceptionType: 1
  osVersion: iPhone OS 18.6.2 (22G100)
  signal: 11
Thread 9 (attributed - this is the thread that crashed):
  2   Network +0xadb8ec nw_browser_cancel samples=1
  3   Roam    +0x173e68 closure #1 in closure #2 in requestLocalNetworkAuthorization at /x/NetworkPermissionsCheck.swift:115 samples=1
  5   Roam    +0x1739e8 closure #2 in requestLocalNetworkAuthorization at /x/NetworkPermissionsCheck.swift:194 samples=1
"#;

    #[test]
    fn matches_the_menu_bar_extra_stack_overflow() {
        let facts = CrashFacts::from_report(MENU_BAR_STACK_OVERFLOW_REPORT);
        let matched = match_rule(MENU_BAR_STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        // The report is from 1.52 and the fix shipped in 1.56.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn one_rule_claims_the_cycle_whichever_trigger_is_on_the_stack() {
        // Before consolidation these were three rules racing on trigger frames,
        // which mis-attributed reports carrying more than one.
        let report = MENU_BAR_STACK_OVERFLOW_REPORT.replace(
            "  20  SwiftUI +0x1476c7c AppGraph.graphDidChange",
            "  20  Roam +0x5e2e8 NSApplication.forceFront at /x/RoamAppDelegate.swift:152\n  21  SwiftUI +0x1476c7c AppGraph.graphDidChange",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.rule.id),
            Some("scene-update-reentrancy-stack-overflow")
        );
    }

    /// Thread 1543063503160606833 (roam 1.54, Mac16,1): the cycle with none of
    /// the three trigger frames anywhere in the report, dying in a `Settings`
    /// scene body 40 minutes into the run. No rule claimed this before
    /// consolidation.
    const SETTINGS_STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) - stack overflow: the faulting address is inside the Stack Guard region directly below a thread stack
Faulting VM region: 0x16c98bfd0 is in 0x169188000-0x16c98c000;  bytes after start: 58736592  bytes before end: 47
--->  Stack Guard                 169188000-16c98c000    [ 56.0M] ---/rwx SM=PRV
Metadata:
  appVersion: 1.54
  deviceType: Mac16,1
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.6.2 (25G83)
  signal: 11
Thread 0 (attributed - this is the thread that crashed):
  0   libswiftCore.dylib +0xae994 Demangler::getDependentGenericParamType samples=1

In-process backtrace of the faulting thread (1)
  20  SwiftUI     +0x8a82a4 Settings.body.getter
  23  SwiftUI     +0x8c0080 SceneBodyAccessor.updateBody
  31  SwiftUI     +0x1476c7c AppGraph.graphDidChange
  32  SwiftUI     +0x10f9b80 specialized AppDelegate.scenesDidChange
  33  SwiftUI     +0x1476c7c AppGraph.graphDidChange
  34  SwiftUI     +0x10f9b80 specialized AppDelegate.scenesDidChange
"#;

    #[test]
    fn matches_the_cycle_with_no_trigger_frame_at_all() {
        for absent in [
            "NSApplication.forceFront",
            "MenuBarExtra",
            "applicationDidChangeScreenParameters",
        ] {
            assert!(!SETTINGS_STACK_OVERFLOW_REPORT.contains(absent));
        }
        let facts = CrashFacts::from_report(SETTINGS_STACK_OVERFLOW_REPORT);
        let matched = match_rule(SETTINGS_STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        // A 1.54 crash predates the 1.56 fix.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    /// Thread 1539671345036664922 (roam 1.51, Mac17,5). MetricKit unwound this
    /// one, so every frame is demangled and `isInserted` appears nowhere.
    const MENU_BAR_DEMANGLED_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) - stack overflow: the faulting address is inside the Stack Guard region directly below a thread stack
--->  Stack Guard                 16b3a8000-16ebac000    [ 56.0M] ---/rwx SM=PRV
Metadata:
  appVersion: 1.51
  deviceType: Mac17,5
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.5.2 (25F84)
  signal: 11
Thread 0 (attributed - this is the thread that crashed):
  19  SwiftUICore +0x3e3ae8 static ObservableObject.environmentStore.getter samples=1
  20  Roam        +0x24e874 closure #4 in RoamApp.body.getter at /<compiler-generated> samples=1
  21  SwiftUI     +0x229e44 closure #1 in MenuBarExtra<>.init samples=1
  23  SwiftUI     +0x22891c MenuBarExtra.init samples=1
  26  Roam        +0x247174 RoamApp.body.getter at /x/RoamApp.swift:292 samples=1
  36  SwiftUI     +0x1476a9c AppGraph.graphDidChange samples=1
  37  SwiftUI     +0x10f9b80 specialized AppDelegate.scenesDidChange samples=1
  38  SwiftUI     +0x1476c7c AppGraph.graphDidChange samples=1
"#;

    #[test]
    fn matches_the_menu_bar_extra_stack_overflow_with_no_parameter_labels() {
        let facts = CrashFacts::from_report(MENU_BAR_DEMANGLED_REPORT);
        let matched = match_rule(MENU_BAR_DEMANGLED_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        // `name_only()` drops argument labels, so no rule may depend on one.
        assert!(!MENU_BAR_DEMANGLED_REPORT.contains("isInserted"));
    }

    #[test]
    fn a_menu_bar_extra_crash_without_the_recursion_is_not_claimed() {
        // MenuBarExtra is common on macOS stacks; only the cycle names the bug.
        let report = MENU_BAR_STACK_OVERFLOW_REPORT
            .replace("AppGraph.graphDidChange", "AppGraph.updateGraph");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    /// Thread 1536532380976812132 (roam 1.54, iPhone15,3): the same crash as
    /// `LOCAL_NETWORK_RACE_REPORT` after 0a68d67c moved the cancel into a
    /// wrapper, leaving no app function on the attributed stack.
    const LOCAL_NETWORK_CANCEL_BEFORE_START_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_INVALID_ADDRESS (1) / SIGSEGV (11)
Faulting VM region: 0x54 is not in any region.  Bytes before following region: 4305485740
Metadata:
  appBuildVersion: 20260825.0750154.0
  appVersion: 1.54
  deviceType: iPhone15,3
  exceptionCode: 1
  exceptionType: 1
  osVersion: iPhone OS 18.6.2 (22G100)
  signal: 11
Thread 4 (attributed - this is the thread that crashed):
  0   libdispatch.dylib +0x79b4 dispatch_async samples=1
  2   Network +0xadb8ec nw_browser_cancel samples=1
  3   Roam    +0x176828 partial apply for closure #2 in CancelOnceEndpoints.cancel at /<compiler-generated> samples=1
  4   Roam    +0xf8c14 thunk for @escaping @callee_guaranteed @Sendable () -> () at /<compiler-generated> samples=1
"#;

    #[test]
    fn matches_the_local_network_cancel_race() {
        let facts = CrashFacts::from_report(LOCAL_NETWORK_RACE_REPORT);
        let matched = match_rule(LOCAL_NETWORK_RACE_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        // The report is from 1.52 and the real fix shipped in 1.55.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_two_local_network_rules_do_not_steal_from_each_other() {
        // Both name `nw_browser_cancel`; the termination code separates them.
        for (report, expected) in [
            (WATCHDOG_REPORT, "local-network-cancel-watchdog"),
            (LOCAL_NETWORK_RACE_REPORT, "local-network-cancel-race"),
        ] {
            let facts = CrashFacts::from_report(report);
            assert_eq!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some(expected)
            );
        }
    }

    #[test]
    fn matches_the_cancel_before_start_report_that_names_no_app_frame() {
        // Regression check: the old app-frame key stopped matching after the
        // refactor. The framework frame does.
        let facts = CrashFacts::from_report(LOCAL_NETWORK_CANCEL_BEFORE_START_REPORT);
        let matched =
            match_rule(LOCAL_NETWORK_CANCEL_BEFORE_START_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        // The crash is from 1.54 and the real fix ships in 1.55.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn a_cancel_before_start_crash_on_1_55_is_unfixed() {
        let report = LOCAL_NETWORK_CANCEL_BEFORE_START_REPORT.replace("1.54", "1.55");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        // A 1.55 crash means this fix missed too, so it stays in the queue.
        assert_eq!(matched.status, FixStatus::Unfixed);
    }

    #[test]
    fn a_cancel_before_start_crash_on_1_53_is_fixed() {
        let report = LOCAL_NETWORK_CANCEL_BEFORE_START_REPORT.replace("1.54", "1.53");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_new_rules_do_not_steal_the_existing_crashes() {
        // `STACK_OVERFLOW_REPORT` belongs to the scene-update rule, so it is
        // checked in `matches_the_scene_phase_stack_overflow` instead.
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            let matched = match_rule(report, &facts).map(|m| m.rule.id);
            assert_ne!(matched, Some("scene-update-reentrancy-stack-overflow"));
            assert_ne!(matched, Some("local-network-cancel-race"));
            assert_ne!(matched, Some("audio-player-node-play-exception"));
        }
    }

    #[test]
    fn a_crash_from_a_rules_own_fix_version_is_tagged_unfixed() {
        // Each rule is checked at its own `fixed_in`; a shared version would
        // stop testing rules whose fix moved.
        for (report, expected, fix_version) in [
            (
                MENU_BAR_STACK_OVERFLOW_REPORT,
                "scene-update-reentrancy-stack-overflow",
                "1.56",
            ),
            (
                LOCAL_NETWORK_RACE_REPORT,
                "local-network-cancel-race",
                "1.55",
            ),
        ] {
            let report = report.replace("appVersion: 1.52", &format!("appVersion: {fix_version}"));
            let facts = CrashFacts::from_report(&report);
            let matched = match_rule(&report, &facts).expect("still matches");
            assert_eq!(matched.rule.id, expected);
            assert_eq!(matched.status, FixStatus::Unfixed);
        }
    }

    #[test]
    fn a_local_network_crash_from_1_54_now_reads_as_fixed_in_1_55() {
        // The two 1.54 crashes that reopened this rule.
        let report = LOCAL_NETWORK_RACE_REPORT.replace("appVersion: 1.52", "appVersion: 1.54");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("still matches");
        assert_eq!(matched.rule.id, "local-network-cancel-race");
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_1_53_reports_that_forced_these_rules_open_read_as_fixed() {
        // Both fixes landed after v1.53; UNFIXED here means a regression.
        for report in [MENU_BAR_STACK_OVERFLOW_REPORT, LOCAL_NETWORK_RACE_REPORT] {
            let report = report.replace("appVersion: 1.52", "appVersion: 1.53");
            let facts = CrashFacts::from_report(&report);
            assert_eq!(
                match_rule(&report, &facts).map(|m| m.status),
                Some(FixStatus::Fixed)
            );
        }
    }

    /// Thread 1540766480533291048 (roam 1.51, Mac16,13): an uncatchable
    /// Objective-C exception out of AVFAudio, so the process aborts.
    const AUDIO_PLAYER_EXCEPTION_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_CRASH (10) / code 0 / SIGABRT (6)
Metadata:
  appVersion: 1.51
  deviceType: Mac16,13
  exceptionCode: 0
  exceptionType: 10
  osVersion: macOS 26.5.2 (25F84)
  signal: 6
Thread 6 (attributed - this is the thread that crashed):
  2   libsystem_c.dylib +0x78644 abort samples=1
  5   libobjc.A.dylib   +0x24894 _objc_terminate() samples=1
  9   libobjc.A.dylib   +0x1aa84 objc_exception_throw samples=1
  10  CoreFoundation    +0xec0b0 +[NSException exceptionWithName:reason:userInfo:] samples=1
  11  AVFAudio          +0xdffa0 AVAudioPlayerNodeImpl::StartImpl(AVAudioTime*) samples=1
  13  AVFAudio          +0xdc1b4 -[AVAudioPlayerNode play] samples=1
  14  Roam              +0x2b4d94 AudioPlayer.start at /x/Loggers.swift:19 samples=1
  15  Roam              +0x1e5b00 closure #2 in closure #1 in RTPSession.streamAudio at /x/RokuSession.swift:561 samples=1
"#;

    #[test]
    fn matches_the_audio_player_node_exception() {
        let facts = CrashFacts::from_report(AUDIO_PLAYER_EXCEPTION_REPORT);
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(6));
        let matched = match_rule(AUDIO_PLAYER_EXCEPTION_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "audio-player-node-play-exception");
        // The report is from 1.51 and the graph rebuild shipped in 1.54.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn an_abort_without_the_audio_frames_is_not_claimed() {
        // A bare SIGABRT is not this bug; both ends must be present.
        let report =
            AUDIO_PLAYER_EXCEPTION_REPORT.replace("AudioPlayer.start", "SomeOtherThing.start");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_audio_rule_does_not_steal_the_sigkill_crashes() {
        // SIGABRT is what separates this from the SIGKILL EXC_CRASH rules.
        for report in [DEAD10CC_REPORT, THERMAL_REPORT, WATCHDOG_REPORT] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("audio-player-node-play-exception")
            );
        }
    }

    /// Thread 1541908323593363529 (roam 1.53, Macmini9,1): the same recursion
    /// with neither `forceFront` nor `MenuBarExtra` on the stack, triggered by
    /// `applicationDidChangeScreenParameters` during launch restoration.
    const SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Diagnosis: EXC_BAD_ACCESS (1) / KERN_PROTECTION_FAILURE (2) / SIGSEGV (11) â stack overflow: the faulting address is inside the Stack Guard region directly below a thread stack
Faulting VM region: 0x16ebabff0 is in 0x16b3a8000-0x16ebac000;  bytes after start: 58736624  bytes before end: 15
--->  STACK GUARD                 16b3a8000-16ebac000    [ 56.0M] ---/rwx SM=PRV  stack guard for thread 0
      Stack                       16ebac000-16f3a8000    [ 8176K] rw-/rwx SM=SHM  thread 0
Metadata:
  appVersion: 1.53
  deviceType: Macmini9,1
  exceptionCode: 2
  exceptionType: 1
  osVersion: macOS 26.5.2 (25F84)
  signal: 11
Thread 0 (attributed â this is the thread that crashed):
  0   libswiftCore.dylib +0xce568 swift::Demangle::__runtime::Node::addChild samples=1
  19  SwiftUI +0xfdc28  Settings.body.getter samples=1
  30  SwiftUI +0x1476b04 AppGraph.graphDidChange samples=1
  31  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange samples=1
  32  SwiftUI +0x1476c7c AppGraph.graphDidChange samples=1
  33  SwiftUI +0x10f9b80 specialized AppDelegate.scenesDidChange samples=1
  43  SwiftUI +0x10f76d0 closure #1 in AppDelegate.applicationDidChangeScreenParameters samples=1
  47  SwiftUI +0x10f709c AppDelegate.applicationDidChangeScreenParameters samples=1
  48  SwiftUI +0x10f780c @objc AppDelegate.applicationWillFinishLaunching samples=1
  83  AppKit  +0x109cdec -[NSPersistentUIRestorer _finishedRestoringWindowsWithZOrder:options:completionHandler:] samples=1
"#;

    #[test]
    fn matches_the_screen_parameters_stack_overflow() {
        let facts = CrashFacts::from_report(SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT);
        let matched =
            match_rule(SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        // The report is from 1.53 and the deferred wrapper shipped in 1.54.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn the_narrower_scene_rules_win_over_the_screen_parameters_rule() {
        // A report naming one of the other triggers belongs to that rule.
        for (trigger, expected) in [
            (
                "  44  Roam +0x5e2e8 NSApplication.forceFront at /x/RoamAppDelegate.swift:152",
                "scene-update-reentrancy-stack-overflow",
            ),
            (
                "  44  SwiftUI +0x8dc94a8 $s7SwiftUI12MenuBarExtraVA2A4TextVRszrlE_10isInserted7contentACyAEq_G",
                "scene-update-reentrancy-stack-overflow",
            ),
        ] {
            let report = SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT.replace(
                "  43  SwiftUI +0x10f76d0 closure #1 in AppDelegate.applicationDidChangeScreenParameters samples=1",
                &format!("{trigger}\n  43  SwiftUI +0x10f76d0 closure #1 in AppDelegate.applicationDidChangeScreenParameters samples=1"),
            );
            let facts = CrashFacts::from_report(&report);
            assert_eq!(
                match_rule(&report, &facts).map(|m| m.rule.id),
                Some(expected)
            );
        }
    }

    #[test]
    fn a_screen_parameters_crash_without_the_recursion_is_not_claimed() {
        // The notification is common; only the cycle names the bug.
        let report = SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT
            .replace("AppGraph.graphDidChange", "AppGraph.updateGraph");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_scene_update_rule_does_not_steal_the_other_crashes() {
        // Keying on the cycle rather than a trigger frame widens the rule, so
        // every crash that is not the cycle has to stay out of it.
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
            LOCAL_NETWORK_RACE_REPORT,
            AUDIO_PLAYER_EXCEPTION_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("scene-update-reentrancy-stack-overflow")
            );
        }
    }

    #[test]
    fn a_screen_parameters_crash_from_1_56_onwards_is_tagged_unfixed() {
        let report =
            SCREEN_PARAMETERS_STACK_OVERFLOW_REPORT.replace("appVersion: 1.53", "appVersion: 1.56");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("still matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        assert_eq!(matched.status, FixStatus::Unfixed);
    }

    #[test]
    fn extracts_facts_from_report() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        assert_eq!(facts.app_version.as_deref(), Some("1.50"));
        assert_eq!(facts.device_type.as_deref(), Some("iPhone14,7"));
        assert_eq!(facts.os_version.as_deref(), Some("iPhone OS 26.6 (23G71)"));
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(9));
        assert_eq!(facts.termination_code, None);
    }

    #[test]
    fn extracts_termination_code_case_insensitively() {
        let facts = CrashFacts::from_report(WATCHDOG_REPORT);
        assert_eq!(facts.termination_code.as_deref(), Some("0x8badf00d"));
    }

    #[test]
    fn matches_each_known_crash_to_its_own_rule() {
        for (report, expected) in [
            (DEAD10CC_REPORT, "database-lock-suspension"),
            (GUARD_REPORT, "ssdp-socket-double-close"),
            (WATCHDOG_REPORT, "local-network-cancel-watchdog"),
        ] {
            let facts = CrashFacts::from_report(report);
            let matched =
                match_rule(report, &facts).unwrap_or_else(|| panic!("no rule for {expected}"));
            assert_eq!(matched.rule.id, expected);
            // Every sample report is from 1.50; all three fixes shipped in 1.51.
            assert_eq!(matched.status, FixStatus::Fixed);
        }
    }

    #[test]
    fn matches_the_scene_phase_stack_overflow() {
        let facts = CrashFacts::from_report(STACK_OVERFLOW_REPORT);
        let matched = match_rule(STACK_OVERFLOW_REPORT, &facts).expect("a rule matches");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        // The report is from 1.51 and the deferral shipped in 1.52.
        assert_eq!(matched.status, FixStatus::Fixed);
    }

    #[test]
    fn a_plain_forcefront_stack_overflow_is_not_claimed() {
        // Only the recursion names the bug; an unrelated overflow stays queued.
        let report =
            STACK_OVERFLOW_REPORT.replace("AppGraph.graphDidChange", "AppGraph.updateGraph");
        let facts = CrashFacts::from_report(&report);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn the_stack_overflow_rule_does_not_steal_other_crashes() {
        for report in [
            DEAD10CC_REPORT,
            GUARD_REPORT,
            WATCHDOG_REPORT,
            THERMAL_REPORT,
        ] {
            let facts = CrashFacts::from_report(report);
            assert_ne!(
                match_rule(report, &facts).map(|m| m.rule.id),
                Some("scene-update-reentrancy-stack-overflow")
            );
        }
    }

    #[test]
    fn crash_from_the_fixing_release_is_tagged_unfixed() {
        let report = GUARD_REPORT.replace("appVersion: 1.50", "appVersion: 1.51");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("still matches the rule");
        assert_eq!(matched.rule.id, "ssdp-socket-double-close");
        assert_eq!(matched.status, FixStatus::Unfixed);
        assert!(matched.reply(&facts).contains("UNFIXED"));
    }

    #[test]
    fn crash_from_after_the_fixing_release_is_tagged_unfixed() {
        let report = GUARD_REPORT.replace("appVersion: 1.50", "appVersion: 1.52");
        let facts = CrashFacts::from_report(&report);
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.status),
            Some(FixStatus::Unfixed)
        );
    }

    #[test]
    fn crash_without_a_version_is_tagged_unknown() {
        let report = GUARD_REPORT.replace("  appVersion: 1.50\n", "");
        let facts = CrashFacts::from_report(&report);
        let matched = match_rule(&report, &facts).expect("matching does not depend on the version");
        assert_eq!(matched.status, FixStatus::Unknown);
        assert!(matched.reply(&facts).contains("Fix status unknown"));
    }

    #[test]
    fn reply_carries_the_diagnosis_and_the_rule_footer() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        let reply = match_rule(DEAD10CC_REPORT, &facts).unwrap().reply(&facts);
        assert!(reply.contains("suspended while holding the database lock"));
        assert!(reply.contains("Fixed in 1.51"));
        assert!(reply.ends_with("_Matched automatically by rule `database-lock-suspension`._"));
    }

    #[test]
    fn versions_compare_component_wise_not_lexically() {
        // The trap: "1.5" sorts after "1.50" as a string.
        assert!(parse_version("1.5") < parse_version("1.50"));
        assert!(parse_version("1.50") < parse_version("1.51"));
        assert!(parse_version("1.51") < parse_version("1.51.1"));
        assert!(parse_version("1.51") < parse_version("2.0"));
        assert_eq!(parse_version("1.51 (204)"), parse_version("1.51"));
        assert_eq!(parse_version("1.51-beta"), parse_version("1.51"));
        assert_eq!(parse_version("unknown"), None);
        assert_eq!(parse_version(""), None);
    }

    #[test]
    fn watchdog_rule_wins_over_database_rule_for_same_exception_pair() {
        // The watchdog report is also EXC_CRASH/SIGKILL. It must not fall
        // through to the database rule, which is why ordering matters.
        let facts = CrashFacts::from_report(WATCHDOG_REPORT);
        assert_eq!(facts.exception_type, Some(10));
        assert_eq!(facts.signal, Some(9));
        assert_eq!(
            match_rule(WATCHDOG_REPORT, &facts).map(|m| m.rule.id),
            Some("local-network-cancel-watchdog")
        );
    }

    #[test]
    fn unknown_crash_matches_nothing() {
        let report = r#"
Metadata:
  exceptionType: 1
  signal: 11
Thread 0 (attributed):
  Roam +0x1 someUnrelatedFunction at /x
"#;
        let facts = CrashFacts::from_report(report);
        assert!(match_rule(report, &facts).is_none());
    }

    /// Thread 1538417638026252298 (roam 1.50, iPhone15,5): scene-update
    /// watchdog on a thermally pegged device, 0.127s of app CPU in 40s.
    const THERMAL_REPORT: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: app<com.msdrigg.roam>:15540 exhausted real (wall clock) time allowance of 10.00 seconds
ProcessVisibility: Background
WatchdogEvent: scene-update
WatchdogCPUStatistics: (
"Elapsed total CPU time (seconds): 40.160 (user 28.900, system 11.260), 67% CPU",
"Elapsed application CPU time (seconds): 0.127, 0% CPU"
)
ThermalInfo: (
"Thermal Level:   9",
"Thermal State:   critical"
) reportType:CrashLog maxTerminationResistance:Interactive>
Metadata:
  appVersion: 1.50
  deviceType: iPhone15,5
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression
Thread 0 (attributed):
  AttributeGraph +0xc800 AG::Graph::UpdateStack::update() samples=1
"#;

    /// Same starvation as `THERMAL_REPORT` with a sliver of app CPU, which a
    /// `max_app_cpu_percent: Some(0)` bound would exclude.
    const THERMAL_REPORT_NONZERO_CPU: &str = r#"
Crash 1 (version 1.0.0)
Termination reason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression: app<com.msdrigg.roam>:6475 exhausted real (wall clock) time allowance of 10.00 seconds
ProcessVisibility: Background
WatchdogEvent: scene-update
WatchdogCPUStatistics: (
"Elapsed total CPU time (seconds): 41.210 (user 21.740, system 19.470), 67% CPU",
"Elapsed application CPU time (seconds): 2.122, 3% CPU"
)
ThermalInfo: (
"Thermal Level:   11",
"Thermal State:   critical"
) reportType:CrashLog maxTerminationResistance:Interactive>
Metadata:
  appVersion: 1.50
  deviceType: iPhone14,5
  exceptionType: 10
  signal: 9
  terminationReason: <RBSTerminateContext| domain:10 code:0x8BADF00D explanation:scene-update watchdog transgression
Thread 0 (attributed):
  SwiftUICore +0x29b8c BodyAccessor.setBody samples=1
"#;

    #[test]
    fn thermal_starvation_matches_when_the_app_got_a_sliver_of_cpu() {
        let facts = CrashFacts::from_report(THERMAL_REPORT_NONZERO_CPU);
        assert_eq!(facts.thermal_level, Some(11));
        assert_eq!(facts.app_cpu_percent, Some(3));

        let matched =
            match_rule(THERMAL_REPORT_NONZERO_CPU, &facts).expect("thermal rule matches at 3%");
        assert_eq!(matched.rule.id, "thermal-starvation-watchdog");
        assert_eq!(matched.status, FixStatus::NotADefect);
    }

    #[test]
    fn extracts_thermal_and_cpu_figures() {
        let facts = CrashFacts::from_report(THERMAL_REPORT);
        assert_eq!(facts.thermal_level, Some(9));
        assert_eq!(facts.app_cpu_percent, Some(0));
        // The 67% on the "Elapsed total" line is the whole device, not the app;
        // reading that one would invert the diagnosis.
        assert_ne!(facts.app_cpu_percent, Some(67));
    }

    #[test]
    fn reports_without_a_watchdog_block_carry_no_thermal_facts() {
        let facts = CrashFacts::from_report(DEAD10CC_REPORT);
        assert_eq!(facts.thermal_level, None);
        assert_eq!(facts.app_cpu_percent, None);
    }

    #[test]
    fn thermal_starvation_is_reviewed_as_not_a_defect() {
        let facts = CrashFacts::from_report(THERMAL_REPORT);
        let matched = match_rule(THERMAL_REPORT, &facts).expect("thermal rule matches");
        assert_eq!(matched.rule.id, "thermal-starvation-watchdog");
        // Not Unfixed, so the auto-review path marks the thread reviewed rather
        // than replying and leaving it in the queue.
        assert_eq!(matched.status, FixStatus::NotADefect);
        assert_ne!(matched.status, FixStatus::Unfixed);

        let reply = matched.reply(&facts);
        assert!(reply.contains("Nothing to fix in the app"));
        // A rule with no `fixed_in` must not claim an unknown fix version.
        assert!(!reply.contains("Fix status unknown"));
        assert!(matched.review_note(&facts).contains("not an app defect"));
    }

    #[test]
    fn thermal_rule_does_not_steal_a_recognised_stack() {
        // A hot device does not stop the app from having a real bug. Any rule
        // that names an app frame has to win, which is why this one is last.
        let report = THERMAL_REPORT.replace(
            "  AttributeGraph +0xc800 AG::Graph::UpdateStack::update() samples=1",
            "  Network +0x1158200 nw_browser_cancel samples=1",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, Some(9));
        assert_eq!(
            match_rule(&report, &facts).map(|m| m.rule.id),
            Some("local-network-cancel-watchdog")
        );
    }

    #[test]
    fn a_busy_app_on_a_hot_device_stays_in_the_manual_queue() {
        // Same thermal reading, but the app was actually running. That is a
        // watchdog kill we have not diagnosed, so it must not auto-close.
        let report = THERMAL_REPORT.replace(
            "Elapsed application CPU time (seconds): 0.127, 0% CPU",
            "Elapsed application CPU time (seconds): 31.800, 79% CPU",
        );
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.app_cpu_percent, Some(79));
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn a_starved_app_on_a_cool_device_stays_in_the_manual_queue() {
        // 0% app CPU on its own describes any blocked main thread, including
        // ones that are our fault. The thermal reading is the discriminator.
        let report = THERMAL_REPORT.replace(r#""Thermal Level:   9""#, r#""Thermal Level:   2""#);
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, Some(2));
        assert_eq!(facts.app_cpu_percent, Some(0));
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn a_watchdog_report_with_no_thermal_block_stays_in_the_manual_queue() {
        let report = THERMAL_REPORT
            .replace(r#""Thermal Level:   9""#, "")
            .replace("Elapsed application CPU time (seconds): 0.127, 0% CPU", "");
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.thermal_level, None);
        assert_eq!(facts.app_cpu_percent, None);
        assert!(match_rule(&report, &facts).is_none());
    }

    #[test]
    fn environmental_rules_declare_no_fix_version() {
        for rule in RULES.iter().filter(|rule| rule.environmental) {
            assert!(
                rule.fixed_in.is_none(),
                "{} is environmental but names a fix version",
                rule.id
            );
        }
    }

    /// A 1.53 overflow delivered after the device had updated to 1.54.
    const UPDATED_DEVICE_REPORT: &str = r#"
Roam MetricKit Crash Diagnostics
================================

Payload window: 2026-08-24 11:42:00 -> 2026-08-24 11:42:00
Install: user_id=lrm-uxk-vwf build=20260901.0000000.0 release=1.56 platform=macOS os=Version 26.5.2 (Build 25F84) locale=en

Crash 1 (version 1.0.0)
Faulting VM region: 0x16d26b000 is in 0x16ca70000-0x16d26c000
--->  Stack Guard                 16926c000-16ca70000    [ 56.0M] ---/rwx SM=PRV
Metadata:
  appBuildVersion: 20260820.0544073.0
  appVersion: 1.53
  deviceType: Mac14,2
  exceptionType: 1
  signal: 11
In-process backtrace of the faulting thread (1)
  0   Roam    0x1 SwiftUI.AppGraph.graphDidChange() -> ()
  1   Roam    0x2 Roam.AppDelegate.scenesDidChange() -> ()
  2   Roam    0x3 SwiftUI.MenuBarExtra<>.init
"#;

    #[test]
    fn extracts_the_installed_release_from_the_install_line() {
        let facts = CrashFacts::from_report(UPDATED_DEVICE_REPORT);
        // Two versions, and they disagree. The crash is the older one.
        assert_eq!(facts.app_version.as_deref(), Some("1.53"));
        assert_eq!(facts.installed_version.as_deref(), Some("1.56"));
        assert_eq!(facts.crash_version(), Some("1.53"));

        // Reports with no Install line at all still parse.
        assert_eq!(
            CrashFacts::from_report(DEAD10CC_REPORT).installed_version,
            None
        );
        // As do devices that never reported a release.
        let unknown = UPDATED_DEVICE_REPORT.replace("release=1.56", "release=unknown");
        assert_eq!(CrashFacts::from_report(&unknown).installed_version, None);
    }

    /// The bug this rewrite exists for: the reporter was already on the fix
    /// version and the reply told them to update to it.
    #[test]
    fn a_crash_predating_the_fix_on_a_device_that_already_updated_is_not_an_update_prompt() {
        let facts = CrashFacts::from_report(UPDATED_DEVICE_REPORT);
        let matched = match_rule(UPDATED_DEVICE_REPORT, &facts).expect("the stack is recognised");
        assert_eq!(matched.rule.id, "scene-update-reentrancy-stack-overflow");
        assert_eq!(matched.status, FixStatus::AlreadyUpdated);

        let reply = matched.reply(&facts);
        assert!(reply.contains("already updated"));
        assert!(reply.contains("device is now on 1.56"));
        assert!(!reply.contains("updating to 1.56 or later resolves it"));

        // The row says both versions, so the queue shows it without the thread.
        assert_eq!(
            matched.review_note(&facts),
            "Stack overflow from the macOS scene update pass re-entering itself \
             (fixed in 1.56; device already on 1.56)"
        );
    }

    /// Fix status keys on the crash version, not the installed release.
    #[test]
    fn an_updated_device_does_not_make_an_old_crash_read_as_unfixed() {
        let facts = CrashFacts::from_report(UPDATED_DEVICE_REPORT);
        let matched = match_rule(UPDATED_DEVICE_REPORT, &facts).unwrap();
        assert_ne!(matched.status, FixStatus::Unfixed);

        // Still on the old build: the update prompt is the right answer there.
        let behind = UPDATED_DEVICE_REPORT.replace("release=1.56", "release=1.53");
        let facts = CrashFacts::from_report(&behind);
        let matched = match_rule(&behind, &facts).unwrap();
        assert_eq!(matched.status, FixStatus::Fixed);
        assert!(
            matched
                .reply(&facts)
                .contains("updating to 1.56 or later resolves it")
        );
    }

    #[test]
    fn a_crash_on_the_fixing_release_is_unfixed_however_the_device_is_installed() {
        for install in ["release=1.56", "release=1.57"] {
            let report = UPDATED_DEVICE_REPORT
                .replace("appVersion: 1.53", "appVersion: 1.56")
                .replace("release=1.56", install);
            let facts = CrashFacts::from_report(&report);
            let matched = match_rule(&report, &facts).unwrap();
            assert_eq!(matched.status, FixStatus::Unfixed, "{install}");
        }
    }

    /// Reports with no `appVersion` fall back to the installed release, and
    /// the reply says so.
    #[test]
    fn a_report_without_an_appversion_falls_back_to_the_installed_release() {
        let report = UPDATED_DEVICE_REPORT.replace("  appVersion: 1.53\n", "");
        let facts = CrashFacts::from_report(&report);
        assert_eq!(facts.app_version, None);
        assert_eq!(facts.crash_version(), Some("1.56"));

        let matched = match_rule(&report, &facts).unwrap();
        // 1.56 is the fixing release, so this belongs in the manual queue.
        assert_eq!(matched.status, FixStatus::Unfixed);
        assert!(matched.reply(&facts).contains("carries no `appVersion`"));

        // A device still behind the fix reads as fixed, not as unknown.
        let behind = report.replace("release=1.56", "release=1.52");
        let facts = CrashFacts::from_report(&behind);
        assert_eq!(
            match_rule(&behind, &facts).unwrap().status,
            FixStatus::Fixed
        );

        // Neither version present is still unknown.
        let neither = behind.replace("Install:", "Installation:");
        let facts = CrashFacts::from_report(&neither);
        assert_eq!(
            match_rule(&neither, &facts).unwrap().status,
            FixStatus::Unknown
        );
    }

    /// Replies are support-only; without the marker they reach the reporter's
    /// chat and feed back into the responder.
    #[test]
    fn every_reply_is_support_only() {
        for rule in RULES {
            assert!(
                rule.reply.starts_with(crate::discord::SUPPORT_ONLY_PREFIX),
                "rule `{}` reply is not support-only",
                rule.id
            );
        }

        // And composition keeps it: the verdict and footer are appended, never
        // prepended, for exactly this reason.
        let facts = CrashFacts::from_report(UPDATED_DEVICE_REPORT);
        let no_version = CrashFacts::default();
        for rule in RULES {
            for facts in [&facts, &no_version] {
                let matched = RuleMatch {
                    rule,
                    status: rule.fix_status(facts),
                };
                assert!(
                    matched
                        .reply(facts)
                        .starts_with(crate::discord::SUPPORT_ONLY_PREFIX),
                    "rule `{}` composed reply is not support-only",
                    rule.id
                );
            }
        }
    }

    /// Auto-review posts a reply as one Discord message. Over the limit,
    /// Discord rejects the post and the crash is left unreviewed.
    #[test]
    fn every_composed_reply_fits_in_one_discord_message() {
        let facts = CrashFacts {
            app_version: Some("1.100.10".to_string()),
            installed_version: Some("1.100.11".to_string()),
            ..CrashFacts::default()
        };
        for rule in RULES {
            for status in [
                FixStatus::Fixed,
                FixStatus::AlreadyUpdated,
                FixStatus::Unfixed,
                FixStatus::NotADefect,
                FixStatus::Unknown,
            ] {
                let reply = RuleMatch { rule, status }.reply(&facts);
                let length = crate::discord::support_only(&reply).chars().count();
                assert!(
                    length <= crate::discord::DiscordClient::DISCORD_CONTENT_MAX_LENGTH,
                    "rule `{}` reply is {length} characters as {status:?}",
                    rule.id
                );
            }
        }
    }

    #[test]
    fn rule_ids_are_unique() {
        let mut ids: Vec<_> = RULES.iter().map(|r| r.id).collect();
        ids.sort_unstable();
        let count = ids.len();
        ids.dedup();
        assert_eq!(ids.len(), count, "duplicate rule id");
    }
}
