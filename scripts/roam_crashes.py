#!/usr/bin/env python3
"""Roam crash triage over the backend API.

Talks only to the Roam backend, which proxies Discord with its own bot
credentials -- this needs BACKEND_URL and CRASH_API_KEY, never a Discord
token.

    export BACKEND_URL=https://backend.roam.msd3.io
    export CRASH_API_KEY=...

    roam_crashes.py unreviewed
    roam_crashes.py unreviewed --app-version 1.50 --all-pages
    roam_crashes.py messages <thread_id> --limit 20
    roam_crashes.py download <thread_id> <message_id> --out ./reports
    roam_crashes.py reply <thread_id> --reply-to <message_id> --file body.md
    roam_crashes.py review <thread_id> --by scott --note "known issue"
    roam_crashes.py rules
    roam_crashes.py daily --since 2026-06-01
    roam_crashes.py records --app-version 1.58 --limit 20
    roam_crashes.py backfill
"""

import argparse
import json
import os
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request

TIMEOUT = 120


def _config():
    base = os.environ.get("BACKEND_URL")
    key = os.environ.get("CRASH_API_KEY")
    if not base or not key:
        sys.exit("Set BACKEND_URL and CRASH_API_KEY")
    return base.rstrip("/"), key


def _request(path, method="GET", body=None, query=None):
    base, key = _config()
    url = base + path
    if query:
        clean = {k: v for k, v in query.items() if v is not None}
        if clean:
            url += "?" + urllib.parse.urlencode(clean)
    req = urllib.request.Request(url, method=method)
    req.add_header("x-api-key", key)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        return urllib.request.urlopen(req, data, timeout=TIMEOUT)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", "replace")[:500]
        sys.exit(f"HTTP {e.code} {method} {url}\n{detail}")


def _json(path, method="GET", body=None, query=None):
    with _request(path, method, body, query) as response:
        raw = response.read()
    return json.loads(raw) if raw else None


def cmd_unreviewed(args):
    crashes, before_ms = [], args.before_ms
    while True:
        page = _json(
            "/v2/crashes",
            query={
                "unreviewed": "true" if not args.include_reviewed else "false",
                "app_version": args.app_version,
                "before_ms": before_ms,
                "limit": args.limit,
            },
        )
        crashes.extend(page["crashes"])
        before_ms = page.get("next_before_ms")
        if not args.all_pages or before_ms is None:
            break

    if args.json:
        print(json.dumps(crashes, indent=2))
        return
    if not crashes:
        print("Nothing outstanding.")
        return
    print(f"{len(crashes)} crash thread(s):\n")
    for c in crashes:
        flag = "UNREVIEWED" if _is_unreviewed(c) else f"reviewed by {c.get('reviewed_by')}"
        print(f"  thread {c['thread_id']}  [{flag}]")
        print(
            f"    v{c.get('app_version') or '?'}  {c.get('device_type') or '?'}"
            f"  {c.get('os_version') or '?'}"
        )
        print(
            f"    exceptionType={c.get('exception_type')} signal={c.get('signal')}"
            f" termination={c.get('termination_code') or '-'}"
        )
        if c.get("latest_crash_message_id"):
            print(f"    crash message: {c['latest_crash_message_id']}")
        print()


def _is_unreviewed(crash):
    reviewed_at = crash.get("reviewed_at_ms")
    return reviewed_at is None or reviewed_at < crash["latest_crash_at_ms"]


def cmd_messages(args):
    messages = _json(
        f"/v2/discord/threads/{args.thread_id}/messages",
        query={"limit": args.limit, "before": args.before, "after": args.after},
    )
    if args.json:
        print(json.dumps(messages, indent=2))
        return
    for m in messages:
        stamp = (m.get("timestamp") or "")[:19]
        print(f"[{stamp}] {m['id']} (author {m['author']['id']})")
        content = (m.get("content") or "").strip()
        if content:
            for line in content.splitlines()[:6]:
                print(f"    {line}")
        for a in m.get("attachments", []):
            print(f"    * attachment {a['id']}  {a['filename']}")
        print()


def cmd_download(args):
    message = _json(f"/v2/discord/threads/{args.thread_id}/messages/{args.message_id}")
    attachments = message.get("attachments", [])
    if args.attachment_id:
        attachments = [a for a in attachments if a["id"] == args.attachment_id]
    if not attachments:
        sys.exit("No matching attachments on that message")

    os.makedirs(args.out, exist_ok=True)
    for a in attachments:
        target = os.path.join(args.out, f"{args.thread_id}_{args.message_id}_{a['filename']}")
        path = (
            f"/v2/discord/threads/{args.thread_id}/messages/{args.message_id}"
            f"/attachments/{a['id']}"
        )
        # Streamed straight to disk; reports can be hundreds of KB and there is
        # no reason to hold one in memory.
        with _request(path) as response, open(target, "wb") as out:
            shutil.copyfileobj(response, out)
        print(f"wrote {target} ({os.path.getsize(target)} bytes)")


def cmd_reply(args):
    content = open(args.file, encoding="utf-8").read() if args.file else args.content
    if not content:
        sys.exit("Provide --content or --file")
    posted = _json(
        f"/v2/discord/threads/{args.thread_id}/messages",
        method="POST",
        body={
            "content": content,
            "reply_to_message_id": args.reply_to,
            "notify": args.notify,
        },
    )
    print(f"posted message {posted['id']} in thread {args.thread_id}")


def cmd_review(args):
    review = _json(
        f"/v2/crashes/{args.thread_id}/review",
        method="POST",
        body={
            "reviewed_by": args.by,
            "reviewed_message_id": args.reviewed_message_id,
            "matched_rule_id": args.rule,
            "note": args.note,
        },
    )
    print(f"thread {review['thread_id']} reviewed by {review.get('reviewed_by')}")


def cmd_unreview(args):
    review = _json(f"/v2/crashes/{args.thread_id}/review", method="DELETE")
    print(f"thread {review['thread_id']} reopened")


def cmd_rules(args):
    rules = _json("/v2/crashes/rules")
    if args.json:
        print(json.dumps(rules, indent=2))
        return
    for r in rules:
        print(f"{r['id']}\n    {r['title']}")
        conditions = []
        if r.get("exception_type") is not None:
            conditions.append(f"exceptionType={r['exception_type']}")
        if r.get("signal") is not None:
            conditions.append(f"signal={r['signal']}")
        if r.get("termination_code"):
            conditions.append(f"code={r['termination_code']}")
        if r.get("all_of"):
            conditions.append("contains " + ", ".join(r["all_of"]))
        print(f"    when: {'; '.join(conditions) or 'always'}\n")


def _record_query(args):
    return {
        "since": args.since,
        "app_version": args.app_version,
        "thread_id": args.thread_id,
        "include_dev": "true" if args.include_dev else None,
    }


def cmd_daily(args):
    days = _json("/v2/crashes/daily", query=_record_query(args))
    if args.json:
        print(json.dumps(days, indent=2))
        return
    if not days:
        print("No crash records.")
        return
    peak = max(d["crashes"] for d in days)
    for d in days:
        bar = "#" * max(1, round(40 * d["crashes"] / peak))
        print(f"  {d['day']}  {d['crashes']:5d} crashes  {d['devices']:3d} devices  {bar}")
    total = sum(d["crashes"] for d in days)
    print(f"\n  {total} crashes over {len(days)} day(s) with any crash")


def cmd_records(args):
    query = _record_query(args) | {"limit": args.limit, "before_id": args.before_id}
    page = _json("/v2/crashes/records", query=query)
    if args.json:
        print(json.dumps(page, indent=2))
        return
    for r in page["records"]:
        print(
            f"  {r['crash_day']}  v{r.get('app_version') or '?'}  {r.get('device_type') or '?'}"
            f"  exc={r.get('exception_type')} sig={r.get('signal')}"
            f"  rule={r.get('matched_rule_id') or '-'}  thread {r['thread_id']}"
        )
    if page.get("next_before_id") is not None:
        print(f"\n  more: --before-id {page['next_before_id']}")


def cmd_backfill(args):
    if args.thread_id:
        thread_ids = args.thread_id
    else:
        threads = _json("/v2/discord/threads", query={"archived_pages": args.archived_pages})
        thread_ids = [t["id"] for t in threads]
    total = 0
    for i, thread_id in enumerate(thread_ids, 1):
        result = _json(f"/v2/crashes/{thread_id}/backfill", method="POST")
        total += result["crashes_inserted"]
        if result["reports"]:
            print(
                f"  [{i}/{len(thread_ids)}] thread {thread_id}: {result['reports']} report(s),"
                f" {result['crashes_inserted']} new crash(es)"
            )
    print(f"\n  {total} new crash record(s) across {len(thread_ids)} thread(s)")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("unreviewed", help="list crash threads needing attention")
    p.add_argument("--app-version")
    p.add_argument("--before-ms", type=int)
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--all-pages", action="store_true")
    p.add_argument("--include-reviewed", action="store_true")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_unreviewed)

    p = sub.add_parser("messages", help="list messages in a thread, newest first")
    p.add_argument("thread_id")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--before", help="page backwards from this message id")
    p.add_argument("--after", help="page forwards from this message id")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_messages)

    p = sub.add_parser("download", help="stream a message's attachments to disk")
    p.add_argument("thread_id")
    p.add_argument("message_id")
    p.add_argument("--attachment-id")
    p.add_argument("--out", default="./reports")
    p.set_defaults(func=cmd_download)

    p = sub.add_parser("reply", help="post a reply into a thread")
    p.add_argument("thread_id")
    p.add_argument("--content")
    p.add_argument("--file", help="read the message body from this file")
    p.add_argument("--reply-to", help="message id to reply to")
    p.add_argument("--notify", action="store_true")
    p.set_defaults(func=cmd_reply)

    p = sub.add_parser("review", help="mark a thread reviewed")
    p.add_argument("thread_id")
    p.add_argument("--by", default="manual")
    p.add_argument("--reviewed-message-id")
    p.add_argument("--rule")
    p.add_argument("--note")
    p.set_defaults(func=cmd_review)

    p = sub.add_parser("unreview", help="reopen a thread for review")
    p.add_argument("thread_id")
    p.set_defaults(func=cmd_unreview)

    p = sub.add_parser("rules", help="list auto-review rules")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_rules)

    def record_filters(p):
        p.add_argument("--since", help="inclusive YYYY-MM-DD, device-local crash day")
        p.add_argument("--app-version")
        p.add_argument("--thread-id")
        p.add_argument("--include-dev", action="store_true", help="keep simulator/debug builds")
        p.add_argument("--json", action="store_true")

    p = sub.add_parser("daily", help="crashes per day from individual crash records")
    record_filters(p)
    p.set_defaults(func=cmd_daily)

    p = sub.add_parser("records", help="list individual crash records, newest first")
    record_filters(p)
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--before-id", type=int)
    p.set_defaults(func=cmd_records)

    p = sub.add_parser("backfill", help="load crash records from reports already in Discord")
    p.add_argument("thread_id", nargs="*", help="default: every support-forum thread")
    p.add_argument("--archived-pages", type=int, default=4)
    p.set_defaults(func=cmd_backfill)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
