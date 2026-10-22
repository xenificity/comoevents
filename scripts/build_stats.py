#!/usr/bin/env python3
"""Build docs/stats/data.json for the public dashboard at comoevent.com/stats/.

Three inputs:
  * the feed (docs/events.json, docs/venues.json) → events listed now, by source, category, venue;
  * feed/stats/seen.json, a running record of every event id ever listed → "events listed so far"
    and a daily history (seed it from git history once with --backfill);
  * GoatCounter (only when GOATCOUNTER_TOKEN is set) → visitors, iPhone app opens, clicks,
    locations, referrers and devices for the last 120 days.
Installs, community posts and Going taps are not here: the page reads them live from CloudKit.

  python3 scripts/build_stats.py              # normal run (CI, hourly)
  python3 scripts/build_stats.py --backfill   # replay git history of feed/events.json first
"""
import argparse
import datetime as dt
import json
import os
import re
import subprocess
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
SEEN = os.path.join(ROOT, "feed", "stats", "seen.json")
OUT = os.path.join(DOCS, "stats", "data.json")
TZ = ZoneInfo("America/Chicago")
GC_CODE = os.environ.get("GOATCOUNTER_CODE", "comoevent")
GC_TOKEN = os.environ.get("GOATCOUNTER_TOKEN", "")
SOURCE_NAMES = {"mizzou": "Mizzou calendar", "dbrl": "Daniel Boone Regional Library", "visitcolumbia": "Visit Columbia",
                "allevents": "AllEvents", "baselocal": "Base Local", "shanthimandir": "Shanthi Mandir",
                "cooperslanding": "Cooper's Landing", "eventbrite": "Eventbrite", "bluenote": "The Blue Note & Rose Music Hall",
                "vox": "Vox Magazine", "posh": "Posh", "flyer": "Flyers", "community": "Posted by the community"}


def today_local(now=None):
    return (now or dt.datetime.now(TZ)).astimezone(TZ).date().isoformat()


def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def norm_venue(v):
    return re.sub(r"\s+", " ", (v or "").strip())


# ---------------------------------------------------------------- seen events / history

def absorb(seen, feed, day):
    """Record every event in this feed snapshot; update the history row for `day`."""
    evs = seen.setdefault("events", {})
    new = 0
    for e in feed.get("events", []):
        if not e.get("id"):
            continue
        rec = evs.get(e["id"])
        if rec is None:
            new += 1
            evs[e["id"]] = {"first": day, "title": e.get("title", ""), "venue": norm_venue(e.get("venue")),
                            "source": e.get("source", ""), "category": e.get("category", "")}
    venues = {r["venue"] for r in evs.values() if r["venue"]}
    hist = seen.setdefault("history", {})
    row = hist.get(day, {"new": 0})
    row.update({"listed": len({e["id"] for e in feed.get("events", []) if e.get("id")}),
                "total": len(evs), "venues": len(venues), "new": row.get("new", 0) + new,
                "sources": len({e.get("source") for e in feed.get("events", []) if e.get("source")})})
    hist[day] = row


def backfill(seen):
    log = subprocess.check_output(["git", "-C", ROOT, "log", "--reverse", "--format=%H %cI", "--", "feed/events.json"], text=True)
    for line in log.split("\n"):
        if not line.strip():
            continue
        sha, when = line.split()
        try:
            feed = json.loads(subprocess.check_output(["git", "-C", ROOT, "show", f"{sha}:feed/events.json"], text=True))
        except (subprocess.CalledProcessError, ValueError):
            continue
        absorb(seen, feed, today_local(dt.datetime.fromisoformat(when)))


# ---------------------------------------------------------------- feed snapshot

def feed_stats(feed, venues_table, seen):
    events = feed.get("events", [])
    now = dt.datetime.now(TZ)
    by_source = Counter(e.get("source") or "other" for e in events)
    by_cat = Counter(e.get("category") or "community" for e in events)
    by_day = Counter()
    for e in events:
        try:
            d = dt.datetime.fromisoformat(e["start"]).astimezone(TZ).date()
        except (KeyError, ValueError):
            continue
        if 0 <= (d - now.date()).days < 30:
            by_day[d.isoformat()] += 1
    # venues: current events + all-time events, with a pin when we know one
    table = {k.lower(): dict(v, name=k) for k, v in venues_table.items()}
    for k, v in venues_table.items():
        for a in v.get("aliases") or []:
            table[a.lower()] = dict(v, name=k)
    now_count = Counter(norm_venue(e.get("venue")) for e in events if e.get("venue"))
    all_count = Counter(r["venue"] for r in seen.get("events", {}).values() if r["venue"])
    pins = {}
    for e in events:
        v = norm_venue(e.get("venue"))
        if v and v not in pins and e.get("lat") and e.get("lng"):
            pins[v] = (round(e["lat"], 5), round(e["lng"], 5), e.get("address") or "")
    venues = []
    for name, total in all_count.most_common():
        t = table.get(name.lower())
        lat, lng, addr = pins.get(name, (None, None, ""))
        if t and t.get("lat"):
            lat, lng, addr = t["lat"], t["lng"], t.get("address") or addr
        venues.append({"name": name, "now": now_count.get(name, 0), "total": total, "lat": lat, "lng": lng,
                       "address": addr, "website": (t or {}).get("website")})
    return {
        "generatedAt": feed.get("generatedAt"),
        "listedNow": len({e["id"] for e in events if e.get("id")}),
        "withPins": sum(1 for e in events if e.get("lat")),
        "sources": [{"id": s, "name": SOURCE_NAMES.get(s, s), "events": n} for s, n in by_source.most_common()],
        "categories": [{"id": c, "events": n} for c, n in by_cat.most_common()],
        "next30Days": [{"day": d, "events": by_day[d]} for d in sorted(by_day)],
        "venues": venues,
    }


# ---------------------------------------------------------------- GoatCounter

def gc(path, **params):
    q = urllib.parse.urlencode(params, doseq=True)
    req = urllib.request.Request(f"https://{GC_CODE}.goatcounter.com/api/v0/{path}?{q}",
                                 headers={"Authorization": f"Bearer {GC_TOKEN}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def daily_series(stats):
    return {s["day"]: s.get("daily", 0) for s in stats or []}


def analytics():
    """Visitors, app opens and clicks per day for 120 days, plus top lists for each dashboard window."""
    if not GC_TOKEN:
        return None
    import time
    end = dt.datetime.now(dt.timezone.utc).replace(minute=0, second=0, microsecond=0) + dt.timedelta(hours=1)
    iso = lambda d: d.strftime("%Y-%m-%dT%H:%M:%SZ")
    full = {"start": iso(end - dt.timedelta(days=120)), "end": iso(end)}
    hits, exclude = [], []
    for _ in range(10):  # 100 paths per page
        page = gc("stats/hits", limit=100, exclude_paths=exclude, **full)
        hits += page.get("hits", [])
        exclude += [h["path_id"] for h in page.get("hits", [])]
        if not page.get("more"):
            break
    web_paths, ios_paths = [], []
    clicks = defaultdict(lambda: defaultdict(int))
    per_event, per_page, per_install = defaultdict(dict), defaultdict(dict), defaultdict(dict)
    titles = {}
    for h in hits:
        p, daily = h["path"], {s["day"]: s.get("daily", 0) for s in h.get("stats", []) if s.get("daily")}
        if h.get("event"):
            if p.startswith(("event/", "ios-event/")):
                kind = "Event opened"
                eid = p.split("/", 1)[1]
                for d, n in daily.items():
                    per_event[eid][d] = per_event[eid].get(d, 0) + n
            elif p.startswith("install/"):
                kind = "Install tap"
                src = p.split("/", 1)[1] or "direct"
                for d, n in daily.items():
                    per_install[src][d] = per_install[src].get(d, 0) + n
            else:
                kind = (p.split("/", 1)[1] if "/" in p else p).replace("-", " ").capitalize()
            for d, n in daily.items():
                clicks[kind][d] += n
        else:
            (ios_paths if p.startswith("/ios/") else web_paths).append(h["path_id"])
            if not p.startswith("/ios/"):
                per_page[p] = daily
                titles[p] = h.get("title") or ""
    total_web = gc("stats/total", include_paths=web_paths, **full) if web_paths else {}
    total_ios = gc("stats/total", include_paths=ios_paths, **full) if ios_paths else {}

    def top(per, since, n):
        sums = Counter({k: sum(v for d, v in days.items() if d >= since) for k, days in per.items()})
        return [(k, c) for k, c in sums.most_common(n) if c]

    def table(name, rng, limit=12, detail=None):
        try:
            time.sleep(0.3)  # API allows 4 requests a second
            url = f"stats/{name}/{detail}" if detail else f"stats/{name}"
            names = {"phone": "Phone", "tablet": "Tablet", "desktop": "Computer", "desktophd": "Large screen"}
            return [{"name": s.get("name") or names.get(s.get("id") or "", "Not reported"), "id": s.get("id"), "count": s.get("count", 0)}
                    for s in gc(url, limit=limit, **rng).get("stats", []) if s.get("count")]
        except Exception:
            return []

    windows = {}
    for key, days in (("7", 7), ("30", 30), ("90", 90), ("all", 120)):
        rng = {"start": iso(end - dt.timedelta(days=days)), "end": iso(end)}
        since = (end - dt.timedelta(days=days)).date().isoformat()
        locations = table("locations", rng, 15)
        us = next((l for l in locations if (l.get("id") or "").upper() == "US"), None)
        windows[key] = {
            "topEvents": [{"id": k, "opens": c} for k, c in top(per_event, since, 15)],
            "topPages": [{"path": k, "title": titles.get(k, ""), "visitors": c} for k, c in top(per_page, since, 12)],
            "installTaps": [{"source": k, "taps": c} for k, c in top(per_install, since, 12)],
            "locations": locations,
            "usRegions": table("locations", rng, 15, "US") if us else [],
            "referrers": table("toprefs", rng),
            "campaigns": table("campaigns", rng),
            "systems": table("systems", rng, 8),
            "sizes": table("sizes", rng, 6),
        }
    web, ios = daily_series(total_web.get("stats")), daily_series(total_ios.get("stats"))
    days_with_data = [d for series in [web, ios] + list(clicks.values()) for d, n in series.items() if n]
    since = min(days_with_data) if days_with_data else end.date().isoformat()
    trim = lambda m: {d: n for d, n in m.items() if d >= since}
    return {
        "since": since,
        "webVisitors": trim(web),
        "iosOpens": trim(ios),
        "clicks": {k: dict(v) for k, v in clicks.items()},
        "windows": windows,
    }


# ---------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backfill", action="store_true")
    args = ap.parse_args()
    seen = load_json(SEEN, {})
    if args.backfill:
        seen = {}
        backfill(seen)
    feed = load_json(os.path.join(DOCS, "events.json"), {"events": []})
    absorb(seen, feed, today_local())
    os.makedirs(os.path.dirname(SEEN), exist_ok=True)
    with open(SEEN, "w") as f:
        json.dump(seen, f, separators=(",", ":"), sort_keys=True)

    fs = feed_stats(feed, load_json(os.path.join(DOCS, "venues.json"), {}), seen)
    # titles for the most-opened events (public data: it's the event's own title)
    ana = None
    try:
        ana = analytics()
    except Exception as e:  # never fail the job because the analytics API hiccuped
        print("GoatCounter unavailable:", e)
        ana = load_json(OUT, {}).get("analytics")
    if ana:
        for w in ana.get("windows", {}).values():
            for t in w["topEvents"]:
                r = seen["events"].get(t["id"]) or {}
                t.update({"title": r.get("title", ""), "venue": r.get("venue", "")})
    data = {
        "feed": fs,
        "totals": {"eventsAllTime": len(seen["events"]), "venuesAllTime": len(fs["venues"]),
                   "sourcesNow": len(fs["sources"]), "firstDay": min(seen["history"]) if seen.get("history") else None},
        "history": [dict(day=d, **seen["history"][d]) for d in sorted(seen["history"])],
        "analytics": ana,
    }
    old = load_json(OUT, {})
    if {k: v for k, v in old.items() if k != "builtAt"} == data:
        print("stats unchanged")
        return
    data["builtAt"] = dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with open(OUT, "w") as f:
        json.dump(data, f, separators=(",", ":"))
    print(f"wrote {os.path.relpath(OUT, ROOT)}: {fs['listedNow']} listed now, {len(seen['events'])} all-time, "
          f"{len(fs['venues'])} venues, analytics={'yes' if ana else 'no'}")


if __name__ == "__main__":
    main()
