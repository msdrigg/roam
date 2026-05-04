CREATE TABLE pending_symbolications (
    id TEXT PRIMARY KEY,
    device_id TEXT NOT NULL,
    thread_id INTEGER NOT NULL,
    payload_path TEXT NOT NULL,
    diagnostics_json TEXT NOT NULL,
    installation_info_json TEXT NOT NULL,
    binary_uuids_json TEXT NOT NULL,
    payload_index INTEGER NOT NULL,
    received_at_ms INTEGER NOT NULL,
    leased_at_ms INTEGER,
    completed_at_ms INTEGER,
    failed_at_ms INTEGER,
    attempts INTEGER NOT NULL DEFAULT 0,
    last_error TEXT
);

CREATE INDEX idx_pending_symbolications_lease
    ON pending_symbolications (completed_at_ms, failed_at_ms, leased_at_ms, received_at_ms);
