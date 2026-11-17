#!/usr/bin/env python3
"""Daily data check for feed/events.json (Hinkson, the validation officer, runs it every morning).

Finds the kinds of mistakes we fixed by hand in Nov 2026:
  - an end before the start, or a start equal to the end
  - odd start times (between 1 AM and 6 AM) on events that are not all-day or time-TBD
  - the same event (same title, same day) listed at different times by different sources
  - one description shared by events with different titles from the same source (a reader borrowing a
    neighbour's text, like the Blue Note card bug)
  - events placed far from Columbia, or naming another town in the venue or address
  - events with no map location
  - sources that returned much less than in the previous feed (a reader that broke)
  - rows in feed/weekly.json not re-verified in 60 days
  - problem reports from users that reached three (from the worker's /fixes)

Usage:
  python3 scripts/check_feed.py                 # report to stdout (Markdown)
  python3 scripts/check_feed.py --json          # machine-readable
  python3 scripts/check_feed.py --previous <file>   # compare source counts with another events.json
Exit code 0 always; the report says what needs attention.
"""
import argparse, collections, datetime as dt, json, math, os, re, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEED = os.path.join(ROOT, "feed", "events.json")
WEEKLY = os.path.join(ROOT, "feed", "weekly.json")
DOWNTOWN = (38.9517, -92.3341)
RADIUS_KM = 25.0
FAR_OK = {"lyceum"}
FAR_TOWN = re.compile(r"\b(Jefferson City|Lincoln University|Fulton|Boonville|Moberly|Mexico,? MO|Fayette|Holts Summit|"
                      r"Kansas City|St\.? Louis|Springfield|Sedalia|Kirksville|Warrensburg)\b", re.I)
WORKER = "https://comoevents-social.comoevent.workers.dev"


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (*a, *b))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def norm(t):
    return re.sub(r"[^a-z0-9]+", " ", (t or "").lower()).strip()


def load(path):
    d = json.load(open(path))
    return d["events"] if isinstance(d, dict) else d


def previous_feed():
    """events.json as of the newest commit that is at least 20 hours old (yesterday's feed)."""
    try:
        sha = subprocess.check_output(["git", "-C", ROOT, "rev-list", "-1", "--before=20 hours ago", "HEAD", "--", "feed/events.json"],
                                      text=True).strip()
        if not sha:
            return None
        raw = subprocess.check_output(["git", "-C", ROOT, "show", f"{sha}:feed/events.json"], text=True)
        d = json.loads(raw)
        return d["events"] if isinstance(d, dict) else d
    except Exception:
        return None


def fixes():
    try:
        with urllib.request.urlopen(WORKER + "/fixes", timeout=15) as r:
            return json.load(r).get("fixes", [])
    except Exception:
        return None


def check(events, prev=None):
    out = collections.OrderedDict((k, []) for k in (
        "end_before_start", "odd_hour", "time_conflict", "borrowed_description", "far_away", "no_location",
        "source_drop", "weekly_stale", "user_reports"))
    for e in events:
        st = dt.datetime.fromisoformat(e["start"])
        en = dt.datetime.fromisoformat(e["end"]) if e.get("end") else None
        tag = f"{e['start'][:16]} · {e['title'][:70]} · {e['source']} · {e.get('url') or ''}"
        if en and en < st:
            out["end_before_start"].append(tag + f" (ends {e['end'][11:16]})")
        if not e.get("allDay") and not e.get("timeTBD") and 1 <= st.hour < 6:
            out["odd_hour"].append(tag)
        if e.get("lat") is None:
            out["no_location"].append(tag)
        elif e["source"] not in FAR_OK and km((e["lat"], e["lng"]), DOWNTOWN) > RADIUS_KM:
            out["far_away"].append(tag + f" ({km((e['lat'], e['lng']), DOWNTOWN):.0f} km)")
        if e["source"] not in FAR_OK and FAR_TOWN.search(f"{e.get('venue') or ''} | {e.get('address') or ''}"):
            out["far_away"].append(tag + " (names another town)")

    by_day = collections.defaultdict(list)
    for e in events:
        by_day[(norm(e["title"])[:40], e["start"][:10])].append(e)
    for (t, day), es in by_day.items():
        starts = {e["start"][11:16] for e in es if not e.get("timeTBD") and not e.get("allDay")}
        srcs = {e["source"] for e in es}
        if len(starts) > 1 and len(srcs) > 1:
            out["time_conflict"].append(f"{day} · {es[0]['title'][:70]} · " +
                                        ", ".join(f"{e['start'][11:16]} ({e['source']})" for e in es))

    by_desc = collections.defaultdict(list)
    for e in events:
        d = (e.get("description") or "").strip()
        if len(d) >= 40:
            by_desc[(e["source"], d)].append(e)
    for (src, d), es in by_desc.items():
        titles = {norm(e["title"]) for e in es}
        venues = {e.get("venue") for e in es}
        # one text on different shows at one venue, where a card-based reader may have borrowed it
        if len(titles) > 1 and src in ("bluenote", "allevents", "baselocal", "vox") and len(venues) == 1:
            out["borrowed_description"].append(f"{src} · \"{d[:60]}\" on: " + "; ".join(sorted({e['title'][:40] for e in es})[:5]))

    if prev:
        now_n = collections.Counter(e["source"] for e in events)
        old_n = collections.Counter(e["source"] for e in prev)
        # Aggregators (AllEvents, Visit Columbia, ...) lose merges to the venue's own calendar, so their own
        # count can fall while no event is missing; only flag them when they vanish.
        aggregators = {"allevents", "baselocal", "macaronikid", "vox", "visitcolumbia"}
        for s, n in old_n.items():
            if s in aggregators and now_n.get(s, 0) > 0:
                continue
            if n >= 8 and now_n.get(s, 0) < n * 0.5:
                out["source_drop"].append(f"{s}: {n} → {now_n.get(s, 0)} events")

    try:
        nights = json.load(open(WEEKLY)).get("nights", [])
        today = dt.date.today()
        for r in nights:
            v = dt.date.fromisoformat(r.get("verified", "2000-01-01"))
            if (today - v).days > 60:
                out["weekly_stale"].append(f"{r['id']} (last verified {v}; source: {r.get('source')})")
    except Exception as ex:
        out["weekly_stale"].append(f"weekly.json unreadable: {ex}")

    fx = fixes()
    if fx is None:
        out["user_reports"].append("could not reach the worker's /fixes")
    else:
        ids = {e["id"]: e for e in events}
        for f in fx:
            e = ids.get(f.get("id"))
            out["user_reports"].append(f"{f.get('kind')} ({f.get('count')} people) · " +
                                       (f"{e['start'][:16]} · {e['title'][:60]} · {e['source']} · {e.get('url') or ''}" if e else f.get("id", "?")) +
                                       (f" · suggested: {f['value']}" if f.get("value") else ""))
    return out


TITLES = {
    "end_before_start": "Ends before it starts",
    "odd_hour": "Starts between 1 AM and 6 AM",
    "time_conflict": "Same event, different times on different sites",
    "borrowed_description": "One description on several different shows",
    "far_away": "Outside Columbia",
    "no_location": "No map location",
    "source_drop": "Sources that dropped by half since yesterday",
    "weekly_stale": "Weekly nights to re-verify (over 60 days)",
    "user_reports": "Problems reported by 3+ people",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--feed", default=FEED)
    ap.add_argument("--previous")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    events = load(a.feed)
    prev = load(a.previous) if a.previous else previous_feed()
    res = check(events, prev)
    if a.json:
        print(json.dumps(res, indent=1, ensure_ascii=False))
        return
    total = sum(len(v) for k, v in res.items() if k != "no_location")
    print(f"# Feed check, {dt.date.today()}\n\n{len(events)} events. {total} items need a look"
          f" (plus {len(res['no_location'])} without a map location).\n")
    for k, items in res.items():
        print(f"## {TITLES[k]} ({len(items)})")
        for it in items[:40]:
            print(f"- {it}")
        if len(items) > 40:
            print(f"- … and {len(items) - 40} more")
        print()


if __name__ == "__main__":
    main()
