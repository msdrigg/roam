-- One row per crash, where `crash_reviews` keeps one row per thread.
--
-- A symbolicated report renders a whole MetricKit payload, which can carry any
-- number of `Crash N` sections, so a row is keyed by the Discord message the
-- report was posted in plus its section number. Recording is idempotent on
-- that pair, which lets a backfill re-walk threads the live path already saw.
-- A requeued payload is symbolicated and posted again under a new message, so
-- the thread plus payload window plus section is unique as well.
CREATE TABLE crash_records (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    thread_id INTEGER NOT NULL,
    message_id INTEGER NOT NULL,
    crash_index INTEGER NOT NULL,
    -- When the report was posted, from the message's snowflake.
    received_at_ms INTEGER NOT NULL,
    -- MetricKit's payload window, verbatim. These are device-local wall-clock
    -- times with no offset, so they are kept as text rather than converted.
    window_begin TEXT,
    window_end TEXT,
    -- `YYYY-MM-DD` off `window_begin`: the device-local day of the crash.
    crash_day TEXT,
    user_id TEXT,
    app_version TEXT,
    app_build_version TEXT,
    installed_version TEXT,
    device_type TEXT,
    os_version TEXT,
    exception_type INTEGER,
    signal INTEGER,
    termination_code TEXT,
    matched_rule_id TEXT,
    -- Simulator or debug build (`dyld_sim`, `Roam.debug.dylib` in the stacks).
    dev_build INTEGER NOT NULL DEFAULT 0,
    UNIQUE (message_id, crash_index),
    UNIQUE (thread_id, window_begin, window_end, crash_index)
);

CREATE INDEX idx_crash_records_day ON crash_records (crash_day);
CREATE INDEX idx_crash_records_received ON crash_records (received_at_ms DESC);
CREATE INDEX idx_crash_records_thread ON crash_records (thread_id);
