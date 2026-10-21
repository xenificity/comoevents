#!/usr/bin/env python3
"""Print a "This weekend in CoMo" top-10 list for Instagram (or Reddit, or a group chat).

Reads feed/events.json, takes the coming Friday 4 PM to Sunday night, ranks events by how
likely people are to go (nightlife, music, parties and big ticketed shows first; deadlines and
office-hours style campus items last), keeps the list varied (at most 3 per category and
1 per venue), and prints a ready-to-paste caption.

Usage:
  python3 scripts/weekly_post.py                     # the coming weekend
  python3 scripts/weekly_post.py --date 2026-10-30   # the weekend containing that date
  python3 scripts/weekly_post.py --count 8 --campaign instagram
  python3 scripts/weekly_post.py --json              # the picks as JSON, for other tools
"""
import argparse
import datetime as dt
import json
import os
import re
from zoneinfo import ZoneInfo

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEED = os.path.join(ROOT, "feed", "events.json")
TZ = ZoneInfo("America/Chicago")
GET = "https://comoevent.com/get/?c="

EMOJI = {"party": "🎉", "music": "🎵", "nightlife": "🌙", "food": "🍴", "arts": "🎭",
         "sports": "🏟️", "family": "👨‍👩‍👧", "campus": "🎓", "community": "📍"}
CATEGORY_WEIGHT = {"party": 10, "music": 9, "nightlife": 8, "food": 7, "arts": 7,
                   "sports": 7, "family": 5, "community": 3, "campus": 2}
SOURCE_WEIGHT = {"bluenote": 4, "posh": 4, "visitcolumbia": 3, "vox": 3, "cooperslanding": 2,
                 "eventbrite": 2, "allevents": 2, "baselocal": 1, "community": 2, "dbrl": 0, "mizzou": 0}
# Things nobody plans a weekend around.
SKIP = re.compile(r"\b(deadline|due|office hours|orientation|registration|webinar|meeting|"
                  r"training|seminar|colloquium|defense|workshop|study|class|lab hours|"
                  r"weekly play|commander|story ?time|support group|info session)\b", re.I)


def parse(s):
    if not s:
        return None
    d = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return d if d.tzinfo else d.replace(tzinfo=TZ)


def weekend_window(day):
    """Friday 4 PM through Sunday 11:59 PM of the weekend that contains `day` (or the next one)."""
    wd = day.weekday()                  # Mon=0 ... Sun=6
    friday = day - dt.timedelta(days=wd - 4) if wd >= 4 else day + dt.timedelta(days=4 - wd)
    start = dt.datetime.combine(friday, dt.time(16, 0), TZ)
    end = dt.datetime.combine(friday + dt.timedelta(days=2), dt.time(23, 59), TZ)
    return start, end


def score(e, start):
    s = CATEGORY_WEIGHT.get(e.get("category"), 3) + SOURCE_WEIGHT.get(e.get("source"), 1)
    if e.get("imageUrl"):
        s += 2
    if e.get("venue"):
        s += 1
    if e.get("ticketUrl") or e.get("price"):
        s += 1
    if len(e.get("alsoOn") or []) >= 1:
        s += 2                          # listed on several sites = a bigger event
    if 17 <= start.hour <= 23:
        s += 2                          # evenings are what people plan around
    if e.get("allDay") or e.get("timeTBD"):
        s -= 2
    if SKIP.search(e.get("title", "")):
        s -= 20
    return s


def pick(events, win_start, win_end, count):
    seen_titles, per_cat, per_venue, picks = set(), {}, {}, []
    cands = []
    for e in events:
        st = parse(e.get("start"))
        if not st or not (win_start <= st.astimezone(TZ) <= win_end):
            continue
        cands.append((score(e, st.astimezone(TZ)), st.astimezone(TZ), e))
    cands.sort(key=lambda t: (-t[0], t[1]))
    for sc, st, e in cands:
        if sc < 0:
            continue
        key = re.sub(r"[^a-z0-9]+", " ", e["title"].lower()).strip()[:40]
        cat = e.get("category", "community")
        venue = (e.get("venue") or "").lower()
        if key in seen_titles or per_cat.get(cat, 0) >= 3 or (venue and per_venue.get(venue, 0) >= 1):
            continue
        seen_titles.add(key)
        per_cat[cat] = per_cat.get(cat, 0) + 1
        if venue:
            per_venue[venue] = 1
        picks.append((st, e))
        if len(picks) >= count:
            break
    picks.sort(key=lambda t: t[0])
    return picks


def when(st, e):
    day = st.strftime("%a")
    if e.get("allDay") or e.get("timeTBD"):
        return day
    t = st.strftime("%-I:%M %p").replace(":00", "").lower()
    return f"{day} {t}"


def short_venue(v):
    """'Flat Branch Park, 300 S Providence Rd, ...' -> 'Flat Branch Park'."""
    return v.split(",")[0].strip() if v else ""


def clean_title(title, venue):
    """Drop a trailing ' – The Blue Note' or ' at Eastside Tavern' when the venue is shown anyway."""
    t = title.strip()
    if venue:
        t = re.sub(r"\s*(?:[–—-]|\bat\b|@)\s*" + re.escape(venue) + r"\s*$", "", t, flags=re.I).strip()
    return t or title.strip()


def date_range(start):
    end = start + dt.timedelta(days=2)
    return f"{start:%b %-d}–{end:%-d}" if start.month == end.month else f"{start:%b %-d}–{end:%b %-d}"


def caption(picks, win_start, campaign):
    lines = [f"This weekend in CoMo ✨ {date_range(win_start)}", ""]
    for st, e in picks:
        v = short_venue(e.get("venue"))
        venue = f" · {v}" if v else ""
        price = f" · {e['price']}" if e.get("price") and len(e["price"]) <= 18 else ""
        lines.append(f"{EMOJI.get(e.get('category'), '📍')} {clean_title(e['title'], v)}{venue} · {when(st, e)}{price}")
    lines += ["", "Everything else happening in Columbia this weekend is on the map in CoMo Events. Free, no ads. Link in bio.",
              "", "#ColumbiaMO #CoMo #Mizzou #ThingsToDo #ColumbiaMissouri",
              "", f"(link: {GET}{campaign})"]
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--date", help="any date in the target weekend, YYYY-MM-DD (default: today)")
    ap.add_argument("--count", type=int, default=10)
    ap.add_argument("--campaign", default="instagram")
    ap.add_argument("--feed", default=FEED)
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()

    day = dt.date.fromisoformat(a.date) if a.date else dt.datetime.now(TZ).date()
    win_start, win_end = weekend_window(day)
    with open(a.feed) as f:
        events = json.load(f)["events"]
    picks = pick(events, win_start, win_end, a.count)
    if a.json:
        print(json.dumps([dict(e, when=when(st, e)) for st, e in picks], indent=1, ensure_ascii=False))
    elif not picks:
        print(f"No events found for the weekend of {date_range(win_start)}. Refresh the feed with scripts/update-feed.sh.")
    else:
        print(caption(picks, win_start, a.campaign))


if __name__ == "__main__":
    main()
