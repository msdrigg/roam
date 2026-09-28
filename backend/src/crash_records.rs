//! Splits a symbolicated report into one record per crash.
//!
//! A report renders a whole MetricKit payload: a shared header (payload window,
//! `Install:` line), one `Crash N` section per diagnostic, then trailing
//! sections (in-process backtrace, debug errors, logs) that belong to the
//! upload rather than to any one crash.

use std::sync::LazyLock;

use regex::Regex;

use crate::crash_rules::{CrashFacts, match_rule, metadata_value};

const DISCORD_EPOCH_MS: i64 = 1_420_070_400_000;

/// Headers `render_metric_report` writes after the last crash section.
const TRAILING_HEADERS: [&str; 3] = [
    "In-process backtrace of the faulting thread",
    "Debug errors (",
    "Logs (",
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ParsedCrash {
    /// The `N` of `Crash N`, 1-based.
    pub crash_index: i64,
    pub window_begin: Option<String>,
    pub window_end: Option<String>,
    /// Device-local `YYYY-MM-DD` off the window's start.
    pub crash_day: Option<String>,
    pub user_id: Option<String>,
    pub app_build_version: Option<String>,
    pub facts: CrashFacts,
    pub matched_rule_id: Option<&'static str>,
    pub dev_build: bool,
}

/// Milliseconds since the Unix epoch encoded in a Discord snowflake.
pub fn snowflake_ms(id: i64) -> i64 {
    (id >> 22) + DISCORD_EPOCH_MS
}

fn payload_window(report: &str) -> (Option<String>, Option<String>) {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?m)^Payload window: (.+?) -> (.+?)\s*$").expect("valid window regex")
    });
    let known = |value: &str| (value != "unknown").then(|| value.to_string());
    match RE.captures(report) {
        Some(caps) => (known(&caps[1]), known(&caps[2])),
        None => (None, None),
    }
}

fn install_user_id(report: &str) -> Option<String> {
    static RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?m)^Install: user_id=(\S+)").expect("valid install-line regex")
    });
    RE.captures(report)
        .map(|caps| caps[1].to_string())
        .filter(|value| value != "unknown")
}

fn day_of(timestamp: &str) -> Option<String> {
    static RE: LazyLock<Regex> =
        LazyLock::new(|| Regex::new(r"^\d{4}-\d{2}-\d{2}").expect("valid day regex"));
    RE.find(timestamp).map(|m| m.as_str().to_string())
}

/// Byte ranges of each `Crash N` section, paired with `N`.
fn crash_sections(report: &str) -> Vec<(i64, usize, usize)> {
    static CRASH_RE: LazyLock<Regex> = LazyLock::new(|| {
        Regex::new(r"(?m)^Crash (\d+)(?: \(version [^)]*\))?\s*$").expect("valid crash regex")
    });
    let starts: Vec<(i64, usize)> = CRASH_RE
        .captures_iter(report)
        .filter_map(|caps| Some((caps[1].parse().ok()?, caps.get(0)?.start())))
        .collect();
    let Some(&(_, first_start)) = starts.first() else {
        return Vec::new();
    };

    let mut offset = first_start;
    let mut body_end = report.len();
    for line in report[first_start..].split_inclusive('\n') {
        if TRAILING_HEADERS.iter().any(|h| line.starts_with(h)) {
            body_end = offset;
            break;
        }
        offset += line.len();
    }

    starts
        .iter()
        .enumerate()
        .filter(|(_, (_, start))| *start < body_end)
        .map(|(i, &(index, start))| {
            let end = starts
                .get(i + 1)
                .map(|&(_, next)| next)
                .unwrap_or(body_end)
                .min(body_end);
            (index, start, end)
        })
        .collect()
}

/// One entry per `Crash N` section. A report that predates those headers but
/// still carries a `Metadata:` block is read as a single crash.
pub fn parse_report(report: &str) -> Vec<ParsedCrash> {
    let mut sections = crash_sections(report);
    if sections.is_empty() {
        if !report.contains("\nMetadata:") {
            return Vec::new();
        }
        sections.push((1, 0, report.len()));
    }

    let header = &report[..sections[0].1];
    let tail = &report[sections.last().map_or(report.len(), |s| s.2)..];
    let (window_begin, window_end) = payload_window(header);
    let crash_day = window_begin.as_deref().and_then(day_of);
    let user_id = install_user_id(header);

    sections
        .into_iter()
        .map(|(crash_index, start, end)| {
            let section = &report[start..end];
            let scoped = format!("{header}{section}");
            let facts = CrashFacts::from_report(&scoped);
            let dev_build = section.contains("dyld_sim") || section.contains("Roam.debug.dylib");
            let matched_rule_id = (!dev_build)
                .then(|| match_rule(&format!("{scoped}{tail}"), &facts).map(|m| m.rule.id))
                .flatten();
            ParsedCrash {
                crash_index,
                window_begin: window_begin.clone(),
                window_end: window_end.clone(),
                crash_day: crash_day.clone(),
                user_id: user_id.clone(),
                app_build_version: metadata_value(section, "appBuildVersion"),
                facts,
                matched_rule_id,
                dev_build,
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const TWO_CRASH_REPORT: &str = "Roam MetricKit Crash Diagnostics
================================

Payload window: 2026-09-15 17:51:00 -> 2026-09-15 18:02:00
Install: user_id=gfn-mkx-uvs build=20260915.2957742.2 release=1.58 platform=iOS os=26.6.2 locale=en
Diagnostics: logs=2 debug_errors=0 devices=3

Crash 1 (version 1.0.0)
Diagnosis: EXC_CRASH (10) / code 0 / SIGKILL (9)
Metadata:
  appBuildVersion: 20260909.3147770.0
  appVersion: 1.57
  deviceType: iPhone17,5
  exceptionType: 10
  osVersion: iPhone OS 26.6.2 (23G90)
  signal: 9
Threads (frame 0 is innermost):
Thread 0 (attributed - this is the thread that crashed):
  0   libsystem_kernel.dylib       +0x11e0      pread samples=1

Crash 2 (version 1.0.0)
Metadata:
  appVersion: 1.58
  deviceType: iPhone17,5
  exceptionType: 1
  signal: 11
Threads (frame 0 is innermost):
Thread 0 (attributed - this is the thread that crashed):
  0   Roam.debug.dylib             +0x11e0      main samples=1
  1   dyld_sim                     +0x11e0      start samples=1

Logs (2 entries, 2026-09-13 04:24:44.000Z -> 2026-09-16 00:51:14.000Z)
Crash 3 is not a section, it is a log line
  appVersion: 9.99
";

    #[test]
    fn splits_each_crash_with_shared_header() {
        let crashes = parse_report(TWO_CRASH_REPORT);
        assert_eq!(crashes.len(), 2);

        let first = &crashes[0];
        assert_eq!(first.crash_index, 1);
        assert_eq!(first.window_begin.as_deref(), Some("2026-09-15 17:51:00"));
        assert_eq!(first.window_end.as_deref(), Some("2026-09-15 18:02:00"));
        assert_eq!(first.crash_day.as_deref(), Some("2026-09-15"));
        assert_eq!(first.user_id.as_deref(), Some("gfn-mkx-uvs"));
        assert_eq!(
            first.app_build_version.as_deref(),
            Some("20260909.3147770.0")
        );
        assert_eq!(first.facts.app_version.as_deref(), Some("1.57"));
        assert_eq!(first.facts.installed_version.as_deref(), Some("1.58"));
        assert_eq!(first.facts.signal, Some(9));
        assert!(!first.dev_build);

        let second = &crashes[1];
        assert_eq!(second.crash_index, 2);
        assert_eq!(second.facts.app_version.as_deref(), Some("1.58"));
        assert_eq!(second.facts.exception_type, Some(1));
        assert_eq!(second.app_build_version, None);
        assert!(second.dev_build);
    }

    #[test]
    fn legacy_report_without_crash_headers_is_one_crash() {
        let report = "Payload window: unknown -> unknown\nMetadata:\n  appVersion: 1.49\n";
        let crashes = parse_report(report);
        assert_eq!(crashes.len(), 1);
        assert_eq!(crashes[0].crash_index, 1);
        assert_eq!(crashes[0].crash_day, None);
        assert_eq!(crashes[0].facts.app_version.as_deref(), Some("1.49"));
    }

    #[test]
    fn empty_payload_has_no_crashes() {
        let report =
            "Payload window: 2026-08-15 09:38:00 -> 2026-08-15 09:38:00\n\nLogs (none captured)\n";
        assert!(parse_report(report).is_empty());
    }

    #[test]
    fn snowflake_decodes_to_post_time() {
        // 2026-09-24T14:16:10.544Z, from a live `MK Diagnostics 0 Symbolicated`.
        assert_eq!(snowflake_ms(1552685079908851803), 1_790_259_370_544);
    }
}
