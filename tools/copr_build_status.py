#!/usr/bin/env python3
"""Report, and optionally wait for, the newest COPR build of this project.

Uses only the unauthenticated read-only APIv3, so it can run in CI without the
webhook/API token. Exit status:
  0  build succeeded
  1  build reached a terminal state that is not "succeeded"
  2  no build found, or the wait timed out
  3  could not reach the COPR API (0 with --allow-unreachable)

Usage:
  copr_build_status.py --owner dupeiran --project zotero-nightly
  copr_build_status.py ... --after-id 11116208 --timeout 5400   # wait for a new build
"""
import argparse
import http.client
import json
import sys
import time
import urllib.parse

API = "https://copr.fedorainfracloud.org/api_3"
RESULTS = "https://download.copr.fedorainfracloud.org/results"
ALLOWED_HOSTS = {"copr.fedorainfracloud.org",
                 "download.copr.fedorainfracloud.org"}
DONE = ("succeeded", "failed", "canceled", "canceled by user", "timed out", "skipped")
ERROR_MARKERS = ("error:", "Error: ", "***", "illegal option", "No matching",
                 "cannot find", "Bad exit status", "Copr build error")


class NetworkError(Exception):
    """Anything that went wrong talking to COPR."""


def fetch(url, timeout=60, redirects=0):
    """GET an allow-listed https COPR URL and return its bytes."""
    parts = urllib.parse.urlsplit(url)
    if parts.scheme != "https" or parts.netloc not in ALLOWED_HOSTS:
        raise NetworkError(f"refusing non-COPR url: {url}")
    target = parts.path + (f"?{parts.query}" if parts.query else "")
    conn = http.client.HTTPSConnection(parts.netloc, timeout=timeout)
    try:
        conn.request("GET", target, headers={"User-Agent": "zotero-nightly-copr/status"})
        resp = conn.getresponse()
        body = resp.read()
        location = resp.getheader("Location")
        if resp.status in (301, 302, 303, 307, 308) and location and redirects < 3:
            return fetch(urllib.parse.urljoin(url, location), timeout, redirects + 1)
        if resp.status != 200:
            raise NetworkError(f"{url}: HTTP {resp.status}")
        return body
    finally:
        conn.close()


def get(url, timeout=60):
    try:
        return json.loads(fetch(url, timeout).decode("utf-8", "replace"))
    except (OSError, ValueError, NetworkError) as exc:
        raise NetworkError(f"{url}: {exc}") from exc


def newest_build(owner, project, after_id=0):
    """Newest build id, or None when nothing newer than after_id exists yet."""
    url = (f"{API}/build/list?ownername={urllib.parse.quote(owner)}"
           f"&projectname={urllib.parse.quote(project)}&limit=1&order_type=DESC")
    items = get(url).get("items", [])
    if not items:
        return None
    build = items[0]
    if after_id and int(build["id"]) <= int(after_id):
        return None
    return build


def log_url(owner, project, chroot, build):
    pkg = (build.get("source_package") or {}).get("name") or project
    return (f"{RESULTS}/{owner}/{project}/{chroot}/"
            f"{int(build['id']):08d}-{pkg}/builder-live.log.gz")


def tail(url, limit=400_000):
    """Last lines of a (possibly huge, possibly missing) build log."""
    try:
        raw = fetch(url, timeout=120)
    except (NetworkError, OSError, ValueError):
        return []
    if raw[:2] == b"\x1f\x8b":
        import gzip
        try:
            raw = gzip.decompress(raw)
        except Exception:
            return []
    return raw[-limit:].decode("utf-8", "replace").splitlines()


def report_failure(owner, project, build, max_chroots=3):
    print(f"::error::COPR build {build['id']} finished as '{build['state']}'",
          file=sys.stderr)
    print(f"  https://copr.fedorainfracloud.org/coprs/{owner}/{project}/{build['id']}/")
    for chroot in (build.get("chroots") or [])[:max_chroots]:
        url = log_url(owner, project, chroot, build)
        hits = [line.strip() for line in tail(url)
                if any(m in line for m in ERROR_MARKERS)]
        print(f"  {chroot}: {url}")
        for line in dict.fromkeys(hits[-3:]):        # dedupe, keep last few
            print(f"    | {line[:300]}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--owner", default="dupeiran")
    p.add_argument("--project", default="zotero-nightly")
    p.add_argument("--after-id", type=int, default=0,
                   help="wait for a build newer than this id")
    p.add_argument("--timeout", type=int, default=0,
                   help="seconds to wait for a terminal state (0 = report once)")
    p.add_argument("--interval", type=int, default=60)
    p.add_argument("--id-only", action="store_true",
                   help="print the newest build id (0 if none) and exit")
    p.add_argument("--summary", action="store_true",
                   help="print '<id>\\t<state>\\t<version-release>\\t<chroot count>' and exit")
    p.add_argument("--allow-unreachable", action="store_true",
                   help="a COPR API outage is a warning, not a failure")
    args = p.parse_args()

    if args.id_only:
        try:
            build = newest_build(args.owner, args.project)
        except NetworkError as exc:
            print(f"::warning::cannot reach COPR API: {exc}", file=sys.stderr)
            return 3
        print(build["id"] if build else 0)
        return 0

    if args.summary:
        try:
            build = newest_build(args.owner, args.project, args.after_id)
        except NetworkError as exc:
            print(f"::warning::cannot reach COPR API: {exc}", file=sys.stderr)
            return 3
        if not build:
            print("0\tnone\tunknown\t0")
            return 0
        sp = build.get("source_package") or {}
        # for an SRPM-driven build 'version' already holds VERSION-RELEASE
        print(f"{build['id']}\t{build.get('state', 'unknown')}\t"
              f"{sp.get('version') or 'unknown'}\t{len(build.get('chroots') or [])}")
        return 0

    deadline = time.monotonic() + args.timeout
    try:
        while True:
            try:
                build = newest_build(args.owner, args.project, args.after_id)
            except NetworkError as exc:
                print(f"::warning::cannot reach COPR API: {exc}", file=sys.stderr)
                if args.timeout == 0:
                    return 0 if args.allow_unreachable else 3
                build = None
            if build is not None:
                state = build.get("state", "unknown")
                print(f"build {build['id']}: {state} "
                      f"({(build.get('source_package') or {}).get('name')}-"
                      f"{(build.get('source_package') or {}).get('version')}-"
                      f"{(build.get('source_package') or {}).get('release', '?')}, "
                      f"{len(build.get('chroots') or [])} chroots)")
                if state in DONE:
                    if state == "succeeded":
                        print("COPR build succeeded")
                        return 0
                    report_failure(args.owner, args.project, build)
                    return 1
                if args.timeout == 0:
                    # report-only mode: a build in progress is not a failure
                    print("build still in progress, nothing to conclude")
                    return 0
            if args.timeout == 0 or time.monotonic() >= deadline:
                print("::error::timed out waiting for a finished COPR build",
                      file=sys.stderr)
                return 2
            time.sleep(args.interval)
    except KeyboardInterrupt:
        return 2


if __name__ == "__main__":
    sys.exit(main())
