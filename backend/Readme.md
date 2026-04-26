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
BACKEND_API_KEY=
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
AI_RESPONDER_MODEL=gpt-5.4-mini
AI_RESPONDER_DELAY_SECONDS=30
AI_RESPONDER_DOCS_DIR=../docs/src/pages
```

When `AI_RESPONDER_ENABLED=true`, these are required:

-   `AI_RESPONDER_DISCORD_TOKEN`
-   `AI_RESPONDER_DISCORD_BOT_ID`
-   `AI_RESPONDER_HUMAN_SUPPORT_USER_ID`
-   `OPENAI_API_KEY`

## Discord Setup

Create a second Discord application for the AI responder. Do not reuse the bridge bot token.

Required bot permissions/intents:

-   Server membership in the same guild as the bridge bot.
-   Access to the support channel and its threads.
-   Send Messages.
-   Send Messages in Threads.
-   Read Message History.
-   Use the Message Content privileged intent, because the responder needs thread text for context.

Set `AI_RESPONDER_DISCORD_BOT_ID` to the bot user's numeric Discord id, not the application id if those differ.

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
  BACKEND_API_KEY=... \
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
  AI_RESPONDER_MODEL=gpt-5.4-mini \
  AI_RESPONDER_DELAY_SECONDS=30
```

`AI_RESPONDER_DOCS_DIR` can be left unset on Fly. `fly.toml` sets it to `/app/docs/pages`, and the Dockerfile copies `docs/src/pages` there.

Deploy from the repository root, not from `backend/`, because the Docker image needs both `backend/` and `docs/src/pages` in the build context:

```sh
fly deploy --config backend/fly.toml --ignorefile backend/.dockerignore
```

Useful checks after deploy:

```sh
fly logs
curl https://backend.roam.msd3.io/health
```

## Using the system

Human support can send :translate: text, /translate text, or <@bot> :translate: text; reply-style :translate: also uses the referenced message text.
