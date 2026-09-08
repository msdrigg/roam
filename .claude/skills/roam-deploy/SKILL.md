---
name: roam-deploy
description: Ship Roam - deploy the Rust backend to Fly and release the apps to App Store Connect via the Export Roam workflow. Use when asked to deploy, ship, release, push to production, cut a build, upload to TestFlight/ASC, re-upload dSYMs, or roll the backend back. Covers why a push to main deploys nothing, the exact flyctl invocation and why its flags are load-bearing, and how to verify a deploy actually landed.
---

# Deploying Roam

Two halves that ship independently and by different means. The backend is a
**local** `fly deploy`; the apps are a **manually dispatched GitHub workflow**.
Neither happens on a push.

## A push to `main` ships nothing

`deploy-fly.yml` is written to trigger on push to `main`, but the workflow is
disabled at the repository level, so the trigger never fires. `archive-push.yml`
is disabled too. Reading the YAML will tell you the opposite of the truth here,
so check the live state rather than the file:

```sh
gh workflow list --all      # look for `disabled_manually`
```

This is deliberate - deploys are gated on a human - so re-enable it only if
asked, never to make a deploy happen.

## Backend to Fly

Run from the **repository root**, not from `backend/`. The Docker build context
needs both `backend/` and `docs/src/pages`:

```sh
fly deploy . --config backend/fly.toml --dockerfile backend/Dockerfile
```

Both flags are load-bearing:

- `--dockerfile` is required because the `dockerfile` path inside `fly.toml`
  resolves relative to that file, not to the build context.
- Do **not** pass `--ignorefile`. The root `.dockerignore` applies
  automatically and is the only thing keeping `backend/target` (many GB) out of
  the build context; overriding it makes the upload enormous.

App `roam-backend`, region `iad`, one machine, `auto_stop_machines = 'off'`.

### Secrets

The backend reads `CRASH_API_KEY` and refuses to start without it. If a deploy
comes up unhealthy, check secrets before suspecting the code:

```sh
fly secrets list --app roam-backend
fly secrets set CRASH_API_KEY=... LEGACY_APP_API_KEY=... --app roam-backend
```

`CRASH_API_KEY` guards the crash, symbolication and Discord-proxy routes; no app
build carries it. `LEGACY_APP_API_KEY` is what older releases still send - unset
it to cut those releases off. `backend/Readme.md` has the full split.

### Two traps when running the deploy from an agent

1. **Never pipe `fly deploy` into `tail`/`grep` and read `$?`** - that reports
   the exit status of the *pipe tail*, so a failed deploy looks like success.
   Redirect to a file and echo the exit code, or check `${PIPESTATUS[0]}`.

2. **`fly deploy` needs unsandboxed network.** The remote builder resolves
   `api.depot.dev` and holds a long connection to `api.fly.io`; under the
   default sandbox these fail as `lookup api.depot.dev: no such host` and
   `connection reset by peer` partway through the build. Read-only `fly logs`
   works fine sandboxed, so a working `fly logs` proves nothing about deploy.

```sh
fly deploy . --config backend/fly.toml --dockerfile backend/Dockerfile \
  > /tmp/deploy.log 2>&1; echo "FLY_EXIT=$?"
```

A `DNS verification failed: expected 1 AAAA records for roam-backend.fly.dev`
warning at the end is benign - traffic uses `backend.roam.msd3.io`.

### Verify it landed

```sh
curl -s -o /dev/null -w '%{http_code}\n' https://backend.roam.msd3.io/health   # 200
fly logs -a roam-backend --no-tail | grep -iE 'ERROR|WARN|panic'
```

Deploying does not prove a client works. To confirm an app-facing fix, watch for
real device traffic - a quiet log only means nothing has called yet.

### Rollback

```sh
fly releases --app roam-backend
fly deploy --image <previous-image-ref> --app roam-backend
```

## Apps to App Store Connect

`Export Roam` (`export-app.yml`) is manual-dispatch only and is what actually
publishes. It archives iOS/macOS/visionOS, uploads builds to ASC, and uploads
dSYMs to the Roam backend. Roughly 30 minutes on a 10x-billed macOS runner, so
do not fire it speculatively.

```sh
gh workflow run export-app.yml --ref main \
  -f platforms="iOS macOS visionOS" \
  -f publish=true -f upload_dsyms=true -f bump_versions=true \
  -f xcode_version=26.6

gh run list --workflow=export-app.yml --limit 3
gh run watch <run-id>
```

Signing is fully automatic - every target uses `CODE_SIGN_STYLE = Automatic`
with no pinned profiles, and `scripts/export.py` passes
`-allowProvisioningUpdates` with the ASC API key. Nothing needs importing from a
developer machine beyond the `.p8`.

`concurrency: export-app` with `cancel-in-progress: false`, so a second dispatch
queues rather than killing the first.

### Filling in missing dSYMs

A failed dSYM upload fails the workflow but does **not** stop the release - the
builds reach ASC either way. It goes red because a build whose symbols never
landed produces crash reports with every app frame unresolved, which match no
auto-review rule and reach the manual queue unreadable. Re-run with symbols only:

```sh
gh workflow run export-app.yml --ref main \
  -f platforms="iOS macOS visionOS" \
  -f publish=false -f upload_dsyms=true -f bump_versions=false
```

`publish=false` and `bump_versions=false` matter - you want the symbols for the
build already on ASC, not a new build number.

## Order for a change that spans both

Backend first, then the app. The backend stays compatible with shipped clients,
so deploying it early is safe; shipping an app that depends on an undeployed
backend is not.

A backend-only fix needs no app release at all - devices pick it up on their
next request.
