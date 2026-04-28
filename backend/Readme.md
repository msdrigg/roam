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
-   `applications.commands` only if real Discord slash commands are added. The current `:translate:` and `/translate` support is parsed from normal message text, so this scope is optional today.

Bot permissions:

-   View Channels
-   Send Messages
-   Send Messages in Threads
-   Read Message History

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
  AI_RESPONDER_MODEL=gpt-5.5 \
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
