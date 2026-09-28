# Roam Backend (new)

## Motivation

-   Had to rewrite away from cloudflare workers due to being blocked by discord (shared public IP) and having no recourse

## Discord Bots

This service can run two Discord bots at the same time:

-   The bridge bot uses `DISCORD_TOKEN` and keeps the existing Roam app bridge working. It creates/reads support threads and sends user messages into Discord.
-   The optional AI responder bot uses a separate Discord application and token. It watches the same support threads, treats messages from the bridge bot as user messages, waits before responding, and sends normal Discord messages from the AI bot when it can answer.

The AI responder is disabled unless `AI_RESPONDER_ENABLED=true`.

## AI Responder Behavior

The responder is intentionally conservative:

-   It only considers messages sent by the bridge bot in threads that map to a known Roam user.
-   It waits `AI_RESPONDER_DELAY_SECONDS` seconds, default `30`, before answering. If the user sends another message during that window, the older pending response is cancelled.
-   Before answering, it re-reads the thread. If human support or the AI bot already replied after the triggering user message, it skips the response.
-   It uses the OpenAI Responses API with two function tools: `search_roam_docs` and `bring_in_human_support`.
-   `search_roam_docs` searches local Markdown/MDX docs from `AI_RESPONDER_DOCS_DIR`. The Fly image copies `docs/src/pages` into `/app/docs/pages`; if that directory is missing, the binary falls back to bundled Roam support notes.
-   `bring_in_human_support` posts a hidden Discord message that mentions `AI_RESPONDER_HUMAN_SUPPORT_USER_ID`.

Human handoff messages start with `!HiddenMessage`, for example:

```text
!HiddenMessage <@123456789> AI responder handoff requested.
Reason: user asked for the developer
```

The existing message-read APIs already filter `!HiddenMessage` and `:ninja:` messages, so handoff mentions alert Discord support without being returned to the app user.

## Environment

Existing bridge/backend variables:

```text
DISCORD_HELP_CHANNEL=
DISCORD_BOT_ID=
DISCORD_GUILD_ID=
DISCORD_TOKEN=
BACKEND_URL=
CRASH_API_KEY=
LEGACY_APP_API_KEY=
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_PRIVATE_KEY=
APNS_BUNDLE_ID=
APNS_DISABLED=false
DATA_DIR=
DATABASE_URL=
SQLX_OFFLINE=true
```

Optional AI responder variables:

```text
AI_RESPONDER_ENABLED=false
AI_RESPONDER_DISCORD_TOKEN=
AI_RESPONDER_DISCORD_BOT_ID=
AI_RESPONDER_HUMAN_SUPPORT_USER_ID=
OPENAI_API_KEY=
AI_RESPONDER_MODEL=gpt-5.5
AI_RESPONDER_DELAY_SECONDS=30
AI_RESPONDER_DOCS_DIR=../docs/src/pages
```

When `AI_RESPONDER_ENABLED=true`, these are required:

-   `AI_RESPONDER_DISCORD_TOKEN`
-   `AI_RESPONDER_DISCORD_BOT_ID`
-   `AI_RESPONDER_HUMAN_SUPPORT_USER_ID`
-   `OPENAI_API_KEY`

## Discord Setup

This backend uses two Discord applications. Keep their tokens and bot user IDs separate:

-   The bridge bot is configured by `DISCORD_TOKEN` and `DISCORD_BOT_ID`.
-   The AI responder bot is configured by `AI_RESPONDER_DISCORD_TOKEN` and `AI_RESPONDER_DISCORD_BOT_ID`.

Set `AI_RESPONDER_DISCORD_BOT_ID` to the bot user's numeric Discord id, not the application id if those differ.

### Bridge bot install

The bridge bot creates support threads and posts app-user messages into them.

OAuth2 guild install scopes:

-   `bot`
-   `applications.commands` only if slash commands are added for this bot.

Bot permissions:

-   View Channels
-   Send Messages
-   Send Messages in Threads
-   Create Public Threads
-   Create Private Threads, only if support threads are changed to private threads.
-   Read Message History

Privileged gateway intents:

-   Message Content Intent, because the bridge bot reads support-thread messages and forwards human replies back to app users.

### AI responder bot install

Create a second Discord application for the AI responder. Do not reuse the bridge bot token.

OAuth2 guild install scopes:

-   `bot`
-   `applications.commands`, because the AI responder auto-registers the guild-scoped `/translate` command at startup.

Bot permissions:

-   View Channels
-   Send Messages
-   Send Messages in Threads
-   Read Message History

The AI responder registers `/translate` as a guild command when it starts. The command accepts a required `text` option, acknowledges privately to the human support user, then sends the translated message visibly in the support thread. Guild command registration is intentionally used so command changes are available immediately in the support server.

Privileged gateway intents:

-   Message Content Intent, because the responder receives thread messages over the gateway and needs message text for context.
-   Server Members Intent is not required.
-   Presence Intent is not required.

The AI bot does not create support threads. It watches existing support threads, joins them when needed, sends typing indicators, posts AI replies, and posts hidden handoff/translation messages.

### Adding bots to the server

For each Discord application:

1.  Open the Discord Developer Portal.
2.  Select the application.
3.  Go to OAuth2 -> URL Generator.
4.  Select the guild install scopes listed above.
5.  Select the bot permissions listed above.
6.  Open the generated authorization URL in a browser.
7.  Choose the support server and authorize the bot.
8.  Go to Bot -> Privileged Gateway Intents and enable Message Content Intent.

After installing, verify the bot role has access to the parent support channel. Channel-specific permission overrides can deny access even when the OAuth install permissions are correct.

### Support channel and thread access

The parent support channel must allow both bot roles to:

-   View Channel
-   Read Message History
-   Send Messages in Threads
-   Send Messages

If support threads are public threads, the AI bot can join a thread itself as long as it can view the parent channel and the thread is not archived.

If support threads are private threads, the AI bot must be explicitly added to each private thread, or it must have a moderator-style permission such as Manage Threads that lets it see private threads. Private threads are only visible to invited members and moderators. A bot that cannot see a private thread will not receive gateway `MESSAGE_CREATE` events for that thread and REST calls such as joining the thread will fail with `403 Missing Access`.

The current backend attempts to have the AI bot add itself to a support thread before the bridge bot posts a user message. That means the actor is the AI bot, using `AI_RESPONDER_DISCORD_TOKEN`. If this logs `Missing Access`, fix the AI bot role's support-channel access or explicitly add the AI bot to the private thread.

If the design changes so the bridge bot adds the AI bot to private threads, the actor would be the bridge bot. In that case the bridge bot must already be able to access the thread and send messages in it, and it must call Discord's add-thread-member endpoint for `AI_RESPONDER_DISCORD_BOT_ID`.

## Fly Deployment

The checked-in `fly.toml` keeps non-secret runtime config in `[env]`, including `DATA_DIR` and `RUST_LOG`. Keep tokens and API keys in Fly secrets.

For the existing bridge/backend secrets:

```sh
fly secrets set \
  DISCORD_HELP_CHANNEL=... \
  DISCORD_BOT_ID=... \
  DISCORD_GUILD_ID=... \
  DISCORD_TOKEN=... \
  BACKEND_URL=... \
  CRASH_API_KEY=... \
  APNS_KEY_ID=... \
  APNS_TEAM_ID=... \
  APNS_PRIVATE_KEY=... \
  APNS_BUNDLE_ID=...
```

To enable the AI responder:

```sh
fly secrets set \
  AI_RESPONDER_ENABLED=true \
  AI_RESPONDER_DISCORD_TOKEN=... \
  AI_RESPONDER_DISCORD_BOT_ID=... \
  AI_RESPONDER_HUMAN_SUPPORT_USER_ID=... \
  OPENAI_API_KEY=... \
  AI_RESPONDER_MODEL=gpt-5.5 \
  AI_RESPONDER_DELAY_SECONDS=30
```

`AI_RESPONDER_DOCS_DIR` can be left unset on Fly. `fly.toml` sets it to `/app/docs/pages`, and the Dockerfile copies `docs/src/pages` there.

Deploy from the repository root, not from `backend/`, because the Docker image needs both `backend/` and `docs/src/pages` in the build context:

```sh
fly deploy . --config backend/fly.toml --dockerfile backend/Dockerfile
```

`--dockerfile` is needed because the `dockerfile` path in `fly.toml` resolves
relative to that file, not to the build context. The root `.dockerignore`
applies automatically and is what keeps `backend/target` (many GB) out of the
context - don't pass `--ignorefile`, which would override it.

Useful checks after deploy:

```sh
fly logs
curl https://backend.roam.msd3.io/health
```

## Using the system

Human support can send :translate: text, /translate text, or <@bot> :translate: text; reply-style :translate: also uses the referenced message text.

## Authentication

The API is split into three zones, and which credential a route wants depends
only on which zone it is in.

**Public.** `/health`, `/`, and the `/v3/attest/*` handshake. A client that has
never attested holds nothing to present, so these are rate limited by IP
instead of authenticated.

**Crash tooling**, guarded by `CRASH_API_KEY`. The symbolication worker,
`scripts/roam_crashes.py`, dSYM upload from CI, the Discord proxy, and
`/user-info` and `/thread-info`. No app build has ever carried this key and
none should: it can read and post to the support Discord.

**App routes**, guarded by an App Attest session. Everything the app calls.
A client registers a Secure Enclave key once (`POST /v3/attest/register`),
then exchanges an assertion for a session (`POST /v3/attest/session`) on each
launch. The session token is a bearer credential the app holds only in memory.

Inside that zone, routes are classified by what they cost, not by HTTP method.
Only the four that create something durable (`/v2/new-message`, `/new-message`,
`/v2/upload-diagnostics`, `/new-apns`, plus the legacy
`/upload-diagnostics/{key}`) require `X-Roam-Assertion` and
`X-Roam-Client-Data`, and only those are metered. So a token lifted out of the
app's memory can read that install's own messages and nothing more.

Method-based classification looks equivalent and is not. `/typing` is a POST
the app sends every five seconds while someone is composing (720/hour), and
polling repeats every ten to sixty seconds (up to 360/hour). Metering either
breaks an ordinary conversation, and signing `/typing` puts a Secure Enclave
operation on a five-second timer, which is the assertion volume Apple's
guidance warns about. `auth.rs::requires_proof` and `requiresProof` in
`Shared/Backend/AppAttestation.swift` are the two halves of this list and have
to agree. `attest_keys.sign_count` plus
`replay_window` implement a 64-wide anti-replay window over assertion
counters, which rejects a captured assertion on its second use while still
accepting two that raced.

Apple's guidance is to require a strictly increasing counter. A strict
high-water mark also rejects the older of any two assertions that arrive out of
order, which HTTP does whenever the app has two writes in flight, so the window
trades that for a bounded reordering tolerance. Every counter is still spendable
exactly once, which is the property the anti-replay rule is there to provide.

An attested key is bound to the install id it first registered and never moves
to another, so a session can only address its own conversation. When a
reinstall clears `UserDefaults`, the backend hands the original id back and the
client adopts it, which is why the support thread survives a reinstall.

`LEGACY_APP_API_KEY` is the key older releases still send. It is accepted on
app routes only and carries no install binding. Only durable writes are
metered, at `LEGACY_HOURLY_LIMIT` per address per hour; polling and typing are
never metered, because throttling those would break the installs this key
exists to keep working. The budget is keyed by address because a release that
predates attestation cannot prove which install it is, which is also why it has
to be loose enough to tolerate several subscribers behind one carrier NAT
address. Unset it to refuse those releases outright.

The budget applies to message posting only, never to diagnostics upload. A
rejected send stays queued in the app and goes out on the next attempt, so a 429
there costs a delay; `MetricManager` in every shipped build deletes its cached
payload whatever the response says, so a 429 on diagnostics would destroy the
crash report instead. `auth.rs::is_metered` is deliberately narrower than
`requires_proof` for that reason. (The client bug is fixed going forward, but
the builds already in the field cannot be.)

The three write budgets are `ATTESTED_HOURLY_LIMIT` (60), `LEGACY_HOURLY_LIMIT`
(120 per address) and `UNATTESTED_HOURLY_LIMIT` (60). Attested and unattested
sit at the same number on purpose: with App Attest unavailable below macOS 27,
an unattested caller is an ordinary Mac user far more often than a suspect, and
the detection signal is the logged platform rather than a tighter cap.

`APP_ATTEST_ALLOW_DEVELOPMENT` must stay off in production. Builds signed with
a development profile attest against Apple's development environment, and
accepting those means the attestation proves nothing about the app that sent
it.

### The macOS fallback

App Attest reached macOS only in **macOS 27** (WWDC 2026 session 201), and the
Roam target deploys to macOS 15, so Macs below 27 cannot attest at all. They
authenticate at `POST /v3/attest/unattested` with their **Mac App Store
receipt** instead, which every copy carries because Roam ships
`app-store-connect` on every platform.

The receipt is verified properly: CMS SignedData, chain walked to the pinned
**Apple Root CA** (`apple_root_ca.der`, which is *not* the App Attest root),
RSA signature checked over the signed attributes with the `messageDigest`
binding the payload, then the bundle id matched against the policy. An earlier
cut took the client's word for "I cannot attest", which any caller can say;
that was not a credential.

What a receipt proves is narrower than an attestation, and the gap is worth
stating. It is a static file, so verifying it establishes that a genuine App
Store receipt for this bundle exists, not that the request came from the Mac it
was issued to. `receipt_bindings` maps one receipt to the first install that
presented it and hands that install id back on every later use, so a copied
receipt reaches the conversation it was copied from rather than opening a new
one.

**No other platform has a fallback, and no other platform ships the code for
one.** iOS 18, watchOS 11 and visionOS 2 all support App Attest, so a client
there claiming it cannot attest is tampering rather than an old OS. The client
half is inside `#if os(macOS)`, so an iOS binary does not contain the path at
all, and the server half refuses without a valid receipt. Both halves come out
together when macOS 27 becomes the floor.

Widget extensions cannot attest on any platform (Apple supports App Attest in
Action and SSO extensions only) and an extension bundle carries no receipt
either. Rather than give them a weaker credential, `sendBackendError` in a
widget writes the report into the shared app group and the containing app
sends it on its next launch. See `Shared/Backend/DeferredErrors.swift`.

An unattested session has the same capabilities as an attested one under a
lower message ceiling (`UNATTESTED_HOURLY_LIMIT`, 30, against
`MESSAGE_HOURLY_LIMIT`, 60): a receipt is replayable where an assertion is not,
so the weaker credential buys the smaller budget, and a refused send stays
queued in the app rather than being lost. Each session is logged at `warn` with
the platform, bundle id and app version the receipt named.

`APP_ATTEST_FALLBACK_ENABLED=false` closes the route outright. Set it once
macOS 27 is the deployment floor, in the same release that removes the
`#if os(macOS)` block from the client.

Two limits are worth stating plainly. A local Xcode build carries no receipt at
all, so developing against a production backend on a Mac below 27 needs a real
App Store or TestFlight build rather than a client-side bypass. And an iOS
receipt names the same bundle id as a Mac one, so a receipt extracted from an
iOS device would satisfy this route; the install binding, the lower ceiling and
the logging are what bound that, not the receipt check itself.

## Crash review API

Every endpoint below sits behind `x-api-key: $CRASH_API_KEY`, so a triage
client needs `BACKEND_URL` and `CRASH_API_KEY` and no Discord credentials of
its own - the backend proxies Discord with its bot token. No app build carries
this key; see [Authentication](#authentication). The `roam-crash-triage` skill
in `.claude/skills/` drives all of this.

When a symbolication completes, the backend records the crash against its
thread and matches the report against the auto-review rules in
`src/crash_rules.rs`. A match means it replies in-thread and marks the thread
reviewed as `auto:<rule id>`; no match leaves the thread in the unreviewed
queue for a human. A thread counts as unreviewed when it was never reviewed or
when a newer crash landed after the last review.

Every message this flow writes is prefixed `:ninja:` via
`discord::support_only`, which is what `DiscordMessage::is_hidden` keys on.
Skipping it puts backtraces, rule ids and fix verdicts into the reporter's
in-app support chat and feeds them to the AI responder as if the user had
written them.

#### The two versions on a report

A report names both, and after an App Store update they differ:

- **`app_version`** - the crash's own MetricKit `appVersion`, the build that
  died. This is the matching key: scoring against anything else would report
  every historical crash from an updated device as a fix that did not hold.
- **`installed_version`** - `release=` off the report's `Install:` line, what
  the device was running when it *uploaded* the payload, up to a day later.

Fix status combines them. A crash predating the rule's `fixed_in` on a device
still behind it is `fixed` (update prompt); the same crash on a device that has
already updated past it is `already_updated` - reviewed, but with no update
prompt, because telling a reporter on 1.54 to update to 1.54 is how this system
loses their trust. A crash from the fixing release or later is `unfixed` and is
left in the queue. A report with neither version is `unknown`.

Both are filterable on `/v2/crashes`, and they answer different questions:
`app_version=1.53` finds the crashes that build *produced*,
`installed_version=1.53` finds the reporters still *running* it.

| Method | Path | Purpose |
|---|---|---|
| GET | `/v2/crashes` | List tracked crashes. `unreviewed=true`, `app_version=`, `installed_version=`, `before_ms=`, `limit=` (1–200). The two version filters AND together. Response carries `next_before_ms` as the page cursor. |
| GET | `/v2/crashes/records` | Individual crashes, newest first. `since=YYYY-MM-DD`, `app_version=`, `thread_id=`, `include_dev=true`, `before_id=`, `limit=` (1–1000). Response carries `next_before_id`. |
| GET | `/v2/crashes/daily` | Crash and device counts per day. Same filters as `/records`. |
| POST | `/v2/crashes/{thread_id}/backfill` | Re-read every `symbolicated.txt` already in a thread into `crash_records`. Idempotent. |
| GET | `/v2/crashes/{thread_id}` | One thread's review state. |
| POST | `/v2/crashes/{thread_id}/review` | Mark reviewed. Optional `reviewed_by`, `reviewed_message_id`, `matched_rule_id`, `note`. |
| DELETE | `/v2/crashes/{thread_id}/review` | Reopen for review. |
| GET | `/v2/crashes/rules` | The auto-review rules. |
| GET | `/v2/discord/threads` | Forum threads. `archived_pages=` walks 100 archived per page (max 20). |
| GET | `/v2/discord/threads/{id}/messages` | Messages, newest first. `before=`, `after=`, `limit=` (1–100). |
| POST | `/v2/discord/threads/{id}/messages` | Post a reply. `content`, optional `reply_to_message_id`, `notify`. Mentions always suppressed. |
| GET | `/v2/discord/threads/{id}/messages/{mid}` | One message. |
| GET | `/v2/discord/threads/{id}/messages/{mid}/attachments/{aid}` | Stream an attachment through from Discord's CDN. Never buffered server-side. |

Snowflake ids are strings in every request and response, since they exceed
JavaScript's safe integer range.

#### Individual crash records

`crash_reviews` keeps one row per thread, and one report can hold hundreds of
`Crash N` sections, so neither answers "how many crashes". `crash_records`
stores one row per section, keyed by `(message_id, crash_index)`, written when
a report is posted and by the backfill endpoint for reports that predate the
table (`python3 scripts/roam_crashes.py backfill`).

`crash_day` is the device-local date of MetricKit's payload window, which has
no offset. Simulator and debug builds (`dyld_sim`, `Roam.debug.dylib`) are
flagged `dev_build` and left out of `/records` and `/daily` unless
`include_dev=true`.

### Adding an auto-review rule

Rules are a compiled-in list in `src/crash_rules.rs`, matched in order with
first-match-wins, so narrower rules go first - several distinct bugs share
`EXC_CRASH (10)` / `SIGKILL (9)`. Add a test alongside the rule that covers the
new report shape and asserts it does not steal matches from existing rules.

### Regenerating the `.sqlx` offline cache

Adding or changing a `query_as!` needs the cache regenerated against a probe
database built from *every* migration, not just the initial one:

```bash
rm -f /tmp/probe.db
for f in migrations/*.up.sql; do sqlite3 /tmp/probe.db < "$f"; done
DATABASE_URL="sqlite:///tmp/probe.db" cargo sqlx prepare -- --lib --tests
```

`--tests` is not optional: several fixtures in `#[cfg(test)]` use `query_as!`,
and preparing with `-- --lib` alone silently drops their cache entries, so
`SQLX_OFFLINE=true cargo test` then fails to compile.

These queries used to be runtime-checked (`query_as::<_, T>`) because
`sqlx_sqlite`'s `column_nullable` calls `CStr::from_ptr` on the declared type
from `sqlite3_table_column_metadata` with no null check, and SQLite returns NULL
there for a column declared with no type - `users.device_id PRIMARY KEY` in the
initial migration was one, so `cargo sqlx prepare` segfaulted rustc.
`20260811120000_users_device_id_text` gave it an explicit `TEXT` type and the
macros went back to `query_as!`; preparing locally has worked since.
