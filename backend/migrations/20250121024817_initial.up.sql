CREATE TABLE users (
    device_id PRIMARY KEY,
    thread_id int8 NOT NULL UNIQUE,
    apns_token TEXT,
    device_info_json TEXT
);

create table parameters (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);