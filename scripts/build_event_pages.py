#!/usr/bin/env python3
"""Build one static page per event under docs/e/<slug>/ with schema.org Event markup, an
index of upcoming events at docs/e/, docs/sitemap.xml and docs/robots.txt.

Google's event search only reads pages about a single event, so every event gets its own URL.
Events that repeat on several days with the same id become one page with startDate/endDate.
Output is deterministic (no build timestamps), so the feed bot only commits real changes.

  python3 scripts/build_event_pages.py            # reads docs/events.json
"""
import datetime as dt
import html
import json
import os
import re
import shutil
import sys
import unicodedata
from collections import defaultdict
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import weekly_post   # noqa: E402  (the weekend guide's top-10 picks)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")
OUT = os.path.join(DOCS, "e")
SITE = "https://comoevent.com"
FALLBACK_IMAGE = SITE + "/img/icon-512.png"
CAT_LABEL = {"party": "Party", "music": "Music", "nightlife": "Nightlife", "food": "Food", "arts": "Arts",
             "sports": "Sports", "family": "Family", "campus": "Campus", "community": "Community"}
CAT_EMOJI = {"party": "🎉", "music": "🎵", "nightlife": "🌙", "food": "🍴", "arts": "🎭",
             "sports": "🏟️", "family": "👨‍👩‍👧", "campus": "🎓", "community": "📍"}
TAG = re.compile(r"<[^>]+>")


def clean(text):
    if not text:
        return ""
    return re.sub(r"\s+", " ", html.unescape(TAG.sub(" ", str(text)))).strip()


def slugify(text, max_len=60):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    text = re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")
    return text[:max_len].rstrip("-") or "event"


def parse(s):
    return dt.datetime.fromisoformat(s) if s else None


def tz_name(d):
    off = d.utcoffset()
    return {-5: "CDT", -6: "CST"}.get(int(off.total_seconds() // 3600), "") if off is not None else ""


def fmt_time(d):
    return d.strftime("%-I:%M %p").replace(":00 ", " ")


def when_text(ev):
    s, e = parse(ev["start"]), parse(ev.get("end"))
    day = lambda d: d.strftime("%a, %b %-d")
    if e and e.date() > s.date():
        if ev.get("allDay") or ev.get("timeTBD") or (s.hour == 0 and s.minute == 0):
            return f"{day(s)} – {day(e)}"
        return f"{day(s)}, {fmt_time(s)} – {day(e)}, {fmt_time(e)} {tz_name(e)}"
    if ev.get("allDay"):
        return f"{day(s)} · All day"
    if ev.get("timeTBD"):
        return f"{day(s)} · Time to be announced"
    if e and e > s:
        return f"{day(s)} · {fmt_time(s)} – {fmt_time(e)} {tz_name(s)}"
    return f"{day(s)} · {fmt_time(s)} {tz_name(s)}"


def load_venues():
    try:
        table = json.load(open(os.path.join(DOCS, "venues.json")))
    except (OSError, ValueError):
        return {}
    index = {}
    for name, v in table.items():
        for key in [name] + list(v.get("aliases") or []):
            index[key.lower().strip()] = dict(v, name=name)
    return index


ADDR = re.compile(r"^(?P<street>.*?),\s*(?P<city>[A-Za-z .'-]+),?\s+(?P<state>[A-Z]{2})\s*(?P<zip>\d{5})?")


def postal_address(address):
    out = {"@type": "PostalAddress", "addressLocality": "Columbia", "addressRegion": "MO", "addressCountry": "US"}
    if not address:
        return out
    m = ADDR.match(address)
    if m:
        out["streetAddress"] = m.group("street").strip()
        out["addressLocality"] = m.group("city").strip()
        out["addressRegion"] = m.group("state")
        if m.group("zip"):
            out["postalCode"] = m.group("zip")
    else:
        out["streetAddress"] = address.split(",")[0].strip()
    return out


def merge_repeats(events):
    """Same id on several days (multi-day campus events) → one record spanning all of them."""
    groups = defaultdict(list)
    for ev in events:
        groups[ev["id"]].append(ev)
    merged = []
    for evs in groups.values():
        evs.sort(key=lambda e: e["start"])
        first = dict(evs[0])
        if len(evs) > 1:
            last = evs[-1]
            first["end"] = last.get("end") or last["start"]
            first["_days"] = len(evs)
        merged.append(first)
    merged.sort(key=lambda e: (e["start"], e["title"]))
    return merged


def assign_slugs(events):
    used = set()
    for ev in events:
        base = f"{slugify(ev['title'])}-{ev['id'][:6]}"
        slug, n = base, 2
        while slug in used:
            slug, n = f"{base}-{n}", n + 1
        used.add(slug)
        ev["_slug"] = slug


def json_ld(ev, venue):
    s, e = parse(ev["start"]), parse(ev.get("end"))
    date_only = ev.get("allDay") or ev.get("timeTBD")
    place = {"@type": "Place", "name": ev.get("venue") or (venue or {}).get("name") or "Columbia, MO",
             "address": postal_address(ev.get("address") or (venue or {}).get("address"))}
    if ev.get("lat") and ev.get("lng"):
        place["geo"] = {"@type": "GeoCoordinates", "latitude": ev["lat"], "longitude": ev["lng"]}
    data = {
        "@context": "https://schema.org",
        "@type": "Event",
        "name": ev["title"],
        "startDate": s.date().isoformat() if date_only else s.isoformat(),
        "eventStatus": "https://schema.org/EventScheduled",
        "eventAttendanceMode": "https://schema.org/OfflineEventAttendanceMode",
        "location": place,
        "image": [ev.get("imageUrl") or FALLBACK_IMAGE],
        "url": f"{SITE}/e/{ev['_slug']}/",
    }
    if e and e >= s:
        data["endDate"] = e.date().isoformat() if date_only else e.isoformat()
    desc = clean(ev.get("description"))
    if desc:
        data["description"] = desc[:1000]
    org = ev.get("organizer") or ev.get("sourceName")
    if org:
        data["organizer"] = {"@type": "Organization", "name": clean(org)}
        if ev.get("url"):
            data["organizer"]["url"] = ev["url"]
    price = clean(ev.get("price"))
    if ev.get("ticketUrl") or price.lower() == "free":
        offer = {"@type": "Offer", "url": ev.get("ticketUrl") or ev.get("url") or data["url"],
                 "priceCurrency": "USD", "availability": "https://schema.org/InStock"}
        if price.lower() == "free":
            offer["price"] = 0
        else:
            m = re.search(r"\$\s*(\d+(?:\.\d{2})?)", price)
            if m:
                offer["price"] = float(m.group(1)) if "." in m.group(1) else int(m.group(1))
        data["offers"] = offer
    return json.dumps(data, ensure_ascii=False, indent=1).replace("</", "<\\/")


CSS = """
:root{--ink:#121214;--muted:#6b6b74;--y:#FFD600;--card:rgba(255,255,255,.82);--bg:#f4f4f7}
@media (prefers-color-scheme:dark){:root{--ink:#f2f2f5;--muted:#a0a0aa;--card:rgba(32,32,38,.82);--bg:#0b0b0f}}
*{box-sizing:border-box}
body{margin:0;font-family:-apple-system,BlinkMacSystemFont,"SF Pro Text","Helvetica Neue",Inter,Arial,sans-serif;color:var(--ink);background:var(--bg);
 background-image:radial-gradient(60% 40% at 0% 0%,rgba(255,214,0,.35),transparent 65%),radial-gradient(45% 35% at 100% 100%,rgba(140,80,255,.18),transparent 65%);background-attachment:fixed;line-height:1.45}
a{color:inherit}
.wrap{max-width:720px;margin:0 auto;padding:20px 16px 48px}
.top{display:flex;align-items:center;justify-content:space-between;margin-bottom:18px}
.brand{display:flex;align-items:center;gap:10px;font-weight:800;text-decoration:none}
.brand img{width:36px;height:36px;border-radius:10px}
.top a.map{font-weight:700;text-decoration:none;font-size:14px;padding:8px 14px;border-radius:999px;background:var(--card);box-shadow:0 4px 14px rgba(0,0,0,.08)}
.card{background:var(--card);backdrop-filter:blur(18px);-webkit-backdrop-filter:blur(18px);border-radius:24px;box-shadow:0 12px 40px rgba(20,20,40,.12);overflow:hidden}
.hero{aspect-ratio:16/9;background:#222;display:block;width:100%;object-fit:cover}
.body{padding:22px}
.chip{display:inline-block;font-size:13px;font-weight:700;padding:4px 10px;border-radius:999px;background:rgba(255,214,0,.25)}
h1{font-size:30px;line-height:1.1;letter-spacing:-.02em;margin:12px 0 14px}
.row{display:flex;gap:10px;margin:8px 0;font-size:16px}
.row b{flex:none;width:22px;text-align:center}
.desc{margin:18px 0 0;color:var(--muted);white-space:pre-line}
.btns{display:flex;flex-wrap:wrap;gap:10px;margin-top:22px}
.btn{display:inline-block;text-decoration:none;font-weight:800;padding:12px 18px;border-radius:14px;background:var(--card);box-shadow:inset 0 0 0 1.5px rgba(127,127,127,.25)}
.btn.primary{background:var(--y);color:#121214;box-shadow:0 8px 22px rgba(255,214,0,.35)}
h2{font-size:18px;margin:30px 4px 10px}
ul.more{list-style:none;margin:0;padding:0;display:grid;gap:8px}
ul.more a{display:flex;gap:12px;align-items:center;text-decoration:none;padding:12px 14px;border-radius:16px;background:var(--card)}
ul.more small{display:block;color:var(--muted)}
.day{margin:26px 4px 8px;font-weight:800}
footer{margin-top:34px;text-align:center;color:var(--muted);font-size:13px}
nav.browse{display:flex;flex-wrap:wrap;gap:8px;margin:8px 0 0}
nav.browse a{text-decoration:none;font-weight:700;font-size:14px;padding:8px 12px;border-radius:999px;background:var(--card);box-shadow:0 2px 8px rgba(0,0,0,.06)}
.intro{color:var(--muted);margin:0 0 6px}
.facts{display:flex;flex-wrap:wrap;gap:8px 16px;font-size:14px;margin:8px 0 4px}
.empty-note{padding:16px;border-radius:16px;background:var(--card);color:var(--muted)}
.lede{font-size:17px}
.lede p{margin:0 0 12px}
ol.picks{list-style:none;margin:0;padding:0;display:grid;gap:8px;counter-reset:pick}
ol.picks li{counter-increment:pick;position:relative;padding:12px 14px 12px 52px;border-radius:16px;background:var(--card)}
ol.picks li:before{content:counter(pick);position:absolute;left:14px;top:12px;width:26px;height:26px;line-height:26px;border-radius:50%;background:var(--y);color:#121214;font-weight:800;font-size:14px;text-align:center}
ol.picks a{font-weight:800;text-decoration:none}
ol.picks small{display:block;color:var(--muted)}
ul.more span.past{display:flex;gap:12px;align-items:center;padding:12px 14px;border-radius:16px;background:var(--card);opacity:.75}
textarea.snippet{display:block;width:100%;min-height:118px;margin:8px 0;padding:12px;border-radius:14px;border:1px solid rgba(127,127,127,.3);background:var(--card);color:var(--ink);font:12px/1.45 ui-monospace,Menlo,Consolas,monospace;resize:vertical}
button.btn{font:inherit;font-weight:800;color:inherit;border:0;cursor:pointer}
"""


def head(title, desc, canonical, image, extra=""):
    t, d = html.escape(title), html.escape(desc)
    return f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>{t}</title>
<meta name="description" content="{d}">
<link rel="canonical" href="{canonical}">
<meta property="og:type" content="website"><meta property="og:site_name" content="CoMo Events">
<meta property="og:title" content="{t}"><meta property="og:description" content="{d}">
<meta property="og:url" content="{canonical}"><meta property="og:image" content="{html.escape(image)}">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="/img/icon-512.png">
<link rel="stylesheet" href="/e/event.css?v=2"><script src="/gc.js?v=1" defer></script>{extra}
</head><body><div class="wrap">
<div class="top"><a class="brand" href="/"><img src="/img/icon-512.png" alt="">CoMo Events</a><a class="map" href="/">Live map</a></div>
"""


BROWSE = [("/tonight/", "Today & tonight"), ("/this-weekend/", "This weekend"), ("/free/", "Free events"),
          ("/music/", "Live music"), ("/family/", "Family & kids"), ("/nightlife/", "Nightlife"), ("/arts/", "Arts, theater & film"),
          ("/food/", "Food & drink"), ("/sports/", "Sports"), ("/mizzou/", "Mizzou events"), ("/weekend-guide/", "Weekend guide"),
          ("/venues/", "Venues"), ("/e/", "Full calendar")]


def set_nav(extra=()):
    """Browse links at the bottom of every page; `extra` puts the in-season holiday pages first."""
    global NAV, FOOT
    NAV = '<nav class="browse">' + " ".join(f'<a href="{u}">{html.escape(t)}</a>' for u, t in list(extra) + BROWSE) + "</nav>"
    FOOT = """<h2>Browse events in Columbia, MO</h2>""" + NAV + """
<footer><a href="/">Live map</a> · <a href="/about/">About</a> · <a href="/get/?c=eventpage">Get the free iPhone app</a> · <a href="/stats/">Stats</a></footer>
</div></body></html>
"""


set_nav()


def event_page(ev, same_day, venue):
    cat = ev.get("category") or "community"
    when = when_text(ev)
    venue_name = ev.get("venue") or (venue or {}).get("name") or ""
    address = ev.get("address") or (venue or {}).get("address") or ""
    if address and "columbia" not in address.lower() and "mo " not in address.lower() + " ":
        address_show = f"{address}, Columbia, MO"
    else:
        address_show = address
    where = ", ".join(x for x in (venue_name, address_show) if x) or "Columbia, MO"
    desc = clean(ev.get("description"))
    meta = f"{when} at {venue_name or 'Columbia, MO'}. " + (desc[:120] if desc else "Free live map of every public event in Columbia, MO.")
    canonical = f"{SITE}/e/{ev['_slug']}/"
    image = ev.get("imageUrl") or FALLBACK_IMAGE
    ld = f'\n<script type="application/ld+json">\n{json_ld(ev, venue)}\n</script>'
    out = [head(f"{ev['title']} · {parse(ev['start']).strftime('%b %-d')} · Columbia, MO", meta, canonical, image, ld)]
    out.append('<article class="card">')
    if ev.get("imageUrl"):
        out.append(f'<img class="hero" src="{html.escape(ev["imageUrl"])}" alt="" fetchpriority="high" referrerpolicy="no-referrer" onerror="this.remove()">')
    out.append('<div class="body">')
    out.append(f'<span class="chip">{CAT_EMOJI.get(cat, "📍")} {CAT_LABEL.get(cat, "Event")}</span>')
    out.append(f"<h1>{html.escape(ev['title'])}</h1>")
    out.append(f'<div class="row"><b>🗓️</b><span>{html.escape(when)}</span></div>')
    vlink = ev.get("_venue_slug")
    where_html = (f'<a href="/venues/{vlink}/">{html.escape(venue_name)}</a>' + (html.escape(", " + address_show) if address_show else "")) if vlink and venue_name else html.escape(where)
    out.append(f'<div class="row"><b>📍</b><span>{where_html}</span></div>')
    price = clean(ev.get("price"))
    if price and price.lower() not in ("n/a", "no", "none"):
        out.append(f'<div class="row"><b>🎟️</b><span>{html.escape(price)}</span></div>')
    org = clean(ev.get("organizer") or ev.get("sourceName"))
    if org:
        out.append(f'<div class="row"><b>👤</b><span>{html.escape(org)}</span></div>')
    if desc:
        out.append(f'<p class="desc">{html.escape(desc[:2000])}</p>')
    out.append('<div class="btns">')
    out.append(f'<a class="btn primary" href="/?e={html.escape(ev["id"])}">Open on the live map</a>')
    if ev.get("lat") and ev.get("lng"):
        dest = f'{ev["lat"]},{ev["lng"]}'
    else:
        dest = where
    out.append(f'<a class="btn" href="https://maps.apple.com/?daddr={html.escape(dest.replace(" ", "+"))}">Directions</a>')
    if ev.get("ticketUrl"):
        out.append(f'<a class="btn" href="{html.escape(ev["ticketUrl"])}" rel="nofollow noopener">Tickets</a>')
    if ev.get("url"):
        out.append(f'<a class="btn" href="{html.escape(ev["url"])}" rel="nofollow noopener">Organizer page</a>')
    out.append("</div></div></article>")
    if same_day:
        out.append(f"<h2>More on {parse(ev['start']).strftime('%A, %B %-d')}</h2><ul class=\"more\">")
        for o in same_day:
            ocat = o.get("category") or "community"
            out.append(f'<li><a href="/e/{o["_slug"]}/"><span>{CAT_EMOJI.get(ocat, "📍")}</span><span>{html.escape(o["title"])}'
                       f'<small>{html.escape(when_text(o))}{" · " + html.escape(o["venue"]) if o.get("venue") else ""}</small></span></a></li>')
        out.append("</ul>")
    out.append(FOOT)
    return "\n".join(out)


def index_page(events):
    out = [head("Events in Columbia, MO · Full calendar of things to do · CoMo Events",
                f"{len(events)} upcoming public events in Columbia, Missouri: Mizzou, downtown, music, food, family and more. Updated every two hours.",
                f"{SITE}/e/", FALLBACK_IMAGE)]
    out.append('<h1 style="margin-top:4px">Upcoming events in Columbia, MO</h1>')
    out.append(f'<p class="desc" style="margin-top:0">{len(events)} public events from Mizzou, downtown venues, the library and more. '
               'See them all on the <a href="/">live map</a>.</p>')
    by_day = defaultdict(list)
    for ev in events:
        by_day[parse(ev["start"]).date()].append(ev)
    for day in sorted(by_day):
        out.append(f'<div class="day">{day.strftime("%A, %B %-d")}</div><ul class="more">')
        for ev in by_day[day]:
            cat = ev.get("category") or "community"
            out.append(f'<li><a href="/e/{ev["_slug"]}/"><span>{CAT_EMOJI.get(cat, "📍")}</span><span>{html.escape(ev["title"])}'
                       f'<small>{html.escape(when_text(ev))}{" · " + html.escape(ev["venue"]) if ev.get("venue") else ""}</small></span></a></li>')
        out.append("</ul>")
    out.append(FOOT)
    return "\n".join(out)


# ----------------------------------------------------------------- landing pages for local searches
LANDING_DIRS = ["tonight", "this-weekend", "free", "music", "family", "nightlife", "arts", "food", "sports", "mizzou", "venues"]
SKIP_VENUE = re.compile(r"^(online|virtual|tba|tbd|various|multiple|see |columbia,? mo)", re.I)

def is_free(ev):
    p = clean(ev.get("price")).lower()
    return p in ("free", "$0", "0", "$0.00") or p.startswith("free") or " free" in f" {p}"

def event_list_html(events, limit=200, live=None):
    """Events grouped by day. With `live` (the set of slugs that still have a page), past events are shown unlinked."""
    by_day = defaultdict(list)
    for ev in events[:limit]:
        by_day[parse(ev["start"]).date()].append(ev)
    out = []
    for day in sorted(by_day):
        out.append(f'<div class="day">{day.strftime("%A, %B %-d")}</div><ul class="more">')
        for ev in by_day[day]:
            cat = ev.get("category") or "community"
            inner = (f'<span>{CAT_EMOJI.get(cat, "📍")}</span><span>{html.escape(ev["title"])}'
                     f'<small>{html.escape(when_text(ev))}{" · " + html.escape(ev["venue"]) if ev.get("venue") else ""}</small></span>')
            if live is None or ev["_slug"] in live:
                out.append(f'<li><a href="/e/{ev["_slug"]}/">{inner}</a></li>')
            else:
                out.append(f'<li><span class="past">{inner}</span></li>')
        out.append("</ul>")
    return "\n".join(out)

def item_list_ld(name, url, events, crumbs):
    data = [{"@context": "https://schema.org", "@type": "ItemList", "name": name, "url": url,
             "numberOfItems": len(events),
             "itemListElement": [{"@type": "ListItem", "position": i + 1, "url": f"{SITE}/e/{ev['_slug']}/"} for i, ev in enumerate(events[:50])]},
            {"@context": "https://schema.org", "@type": "BreadcrumbList",
             "itemListElement": [{"@type": "ListItem", "position": i + 1, "name": n, "item": u} for i, (n, u) in enumerate(crumbs)]}]
    return "\n".join('<script type="application/ld+json">\n' + json.dumps(d, ensure_ascii=False, indent=1).replace("</", "<\\/") + "\n</script>" for d in data)

def landing_page(path, title, h1, intro, events, empty_text, crumbs, extra_top="", extra_bottom=""):
    url = f"{SITE}/{path}/"
    desc = intro if len(intro) <= 155 else intro[:152].rsplit(" ", 1)[0] + "…"
    out = [head(title, desc, url, FALLBACK_IMAGE, "\n" + item_list_ld(h1, url, events, crumbs))]
    out.append(f'<h1 style="margin-top:4px">{html.escape(h1)}</h1>')
    out.append(f'<p class="intro">{html.escape(intro)}</p>')
    out.append(extra_top)
    out.append(f'<p style="margin:14px 0"><a class="btn primary" href="/?c=seo-{path.replace("/", "-")}">Open the live map</a></p>')
    out.append(event_list_html(events) if events else f'<p class="empty-note">{html.escape(empty_text)}</p>')
    out.append(extra_bottom)
    out.append(FOOT)
    return "\n".join(out)

def write_page(path, text):
    d = os.path.join(DOCS, path)
    os.makedirs(d, exist_ok=True)
    with open(os.path.join(d, "index.html"), "w") as f:
        f.write(text)

def build_landing(events, venues_table, now):
    for d in LANDING_DIRS:
        if os.path.isdir(os.path.join(DOCS, d)):
            shutil.rmtree(os.path.join(DOCS, d))
    upcoming = [ev for ev in events if (parse(ev.get("end") or ev["start"]) or parse(ev["start"])) >= now - dt.timedelta(hours=1)]
    month = now.strftime("%B %Y")
    pages = []
    home = ("Home", f"{SITE}/")

    # today & tonight
    today = now.date()
    tonight = [ev for ev in upcoming if parse(ev["start"]).date() == today or (parse(ev["start"]) <= now and parse(ev.get("end") or ev["start"]) >= now)]
    pages.append(("tonight", landing_page("tonight", f"Things to do in Columbia, MO today & tonight · {now:%A, %B %-d}",
        "Things to do in Columbia, MO today and tonight",
        f"{len(tonight)} events happening today in Columbia, Missouri: live music, Mizzou, downtown bars, family activities, theater and more. Updated every two hours.",
        tonight, "Nothing else is listed for today. See this weekend's events below.", [home, ("Tonight", f"{SITE}/tonight/")])))

    # this weekend (Fri-Sun; on a weekend day, the current one)
    wd = today.weekday()
    fri = today - dt.timedelta(days=wd - 4) if wd >= 4 else today + dt.timedelta(days=4 - wd)
    sun = fri + dt.timedelta(days=2)
    weekend = [ev for ev in upcoming if fri <= parse(ev["start"]).date() <= sun]
    pages.append(("this-weekend", landing_page("this-weekend", f"Things to do in Columbia, MO this weekend · {fri:%b %-d}–{sun:%-d}",
        "Things to do in Columbia, MO this weekend",
        f"{len(weekend)} events in Columbia, Missouri this weekend, {fri:%A %B %-d} to {sun:%A %B %-d}: concerts, parties, markets, Mizzou games, theater, kids' activities and free events.",
        weekend, "The weekend's events will show up here as they are announced.", [home, ("This weekend", f"{SITE}/this-weekend/")])))

    # free
    free = [ev for ev in upcoming if is_free(ev)]
    pages.append(("free", landing_page("free", f"Free events in Columbia, MO · {month}",
        "Free events and things to do in Columbia, MO",
        f"{len(free)} free events in Columbia, Missouri: library programs, Mizzou lectures and concerts, art walks, community gatherings and family activities.",
        free, "No free events are listed right now.", [home, ("Free events", f"{SITE}/free/")])))

    # categories
    cats = [("music", "music", "Live music in Columbia, MO", "Live music and concerts in Columbia, MO",
             "concerts and live music in Columbia, Missouri: The Blue Note, Rose Music Hall, the Missouri Symphony, Mizzou ensembles, jazz, bars and outdoor shows."),
            ("family", "family", "Family & kids events in Columbia, MO", "Family-friendly events and things to do with kids in Columbia, MO",
             "family-friendly events in Columbia, Missouri: library story times, parks, festivals, museums, holiday events and kids' shows."),
            ("nightlife", "nightlife", "Nightlife & parties in Columbia, MO", "Nightlife, bars and parties in Columbia, MO",
             "nightlife events in Columbia, Missouri: downtown bars, DJ nights, comedy, trivia and late-night parties."),
            ("arts", "arts", "Theater, art & film in Columbia, MO", "Theater, art, film and performances in Columbia, MO",
             "arts events in Columbia, Missouri: plays and musicals, Ragtag Cinema films, galleries, First Fridays, dance and the symphony."),
            ("food", "food", "Food & drink events in Columbia, MO", "Food, drink and market events in Columbia, MO",
             "food and drink events in Columbia, Missouri: farmers markets, tastings, food trucks, brewery events and dinners."),
            ("sports", "sports", "Sports events in Columbia, MO", "Sports and games in Columbia, MO",
             "sports events in Columbia, Missouri: Mizzou Tigers home games, races, tournaments and rec leagues."),
            ("mizzou", "campus", "Mizzou events · University of Missouri campus events", "Mizzou and University of Missouri campus events",
             "events at the University of Missouri (Mizzou) in Columbia: concerts, lectures, student life, arts and athletics.")]
    for path, cat, title, h1, blurb in cats:
        evs = [ev for ev in upcoming if cat in (ev.get("categories") or [ev.get("category")])]
        pages.append((path, landing_page(path, f"{title} · {month}", h1, f"{len(evs)} upcoming {blurb}",
                      evs, "Nothing is listed in this category right now.", [home, (h1, f"{SITE}/{path}/")])))

    # venues
    groups = defaultdict(list)
    for ev in upcoming:
        v = clean(ev.get("venue"))
        if v and not SKIP_VENUE.search(v) and len(v) <= 70:
            groups[v].append(ev)
    used, vlinks, embeds = set(), [], {}
    for name in sorted(groups, key=lambda n: (-len(groups[n]), n.lower())):
        slug = slugify(name)
        n = 2
        while slug in used:
            slug, n = f"{slugify(name)}-{n}", n + 1
        used.add(slug)
        for ev in groups[name]:
            ev["_venue_slug"] = slug
        row = venues_table.get(name.lower()) or {}
        evs = groups[name]
        addr = row.get("address") or next((ev.get("address") for ev in evs if ev.get("address")), "")
        facts = []
        if addr:
            facts.append(f"📍 {html.escape(addr)}")
        if row.get("phone"):
            facts.append(f'📞 <a href="tel:{re.sub(r"[^0-9+]", "", row["phone"])}">{html.escape(row["phone"])}</a>')
        if row.get("website"):
            facts.append(f'🌐 <a href="{html.escape(row["website"])}" rel="nofollow noopener">Website</a>')
        top = f'<div class="facts">{" ".join(f"<span>{x}</span>" for x in facts)}</div>' if facts else ""
        pages.append((f"venues/{slug}", landing_page(f"venues/{slug}", f"{name} events · Columbia, MO schedule",
            f"{name} events in Columbia, MO",
            f"{len(evs)} upcoming events at {name}{(', ' + addr) if addr else ''} in Columbia, Missouri. Dates, times, tickets and directions, updated every two hours.",
            evs, "No upcoming events are listed here right now.", [home, ("Venues", f"{SITE}/venues/"), (name, f"{SITE}/venues/{slug}/")], top,
            embed_section(name, slug))))
        vlinks.append((name, slug, len(evs)))
        embeds[slug] = {"name": name, "address": addr, "url": f"{SITE}/venues/{slug}/", "events": [embed_event(ev) for ev in evs[:30]]}
    vl = "<ul class=\"more\">" + "".join(f'<li><a href="/venues/{s}/"><span>📍</span><span>{html.escape(n)}<small>{c} upcoming event{"s" if c != 1 else ""}</small></span></a></li>' for n, s, c in vlinks) + "</ul>"
    vidx = [head("Event venues in Columbia, MO · Concert halls, bars, theaters & more",
                 f"{len(vlinks)} places with upcoming events in Columbia, Missouri: music venues, theaters, bars, the library, Mizzou and more.",
                 f"{SITE}/venues/", FALLBACK_IMAGE),
            '<h1 style="margin-top:4px">Event venues in Columbia, MO</h1>',
            f'<p class="intro">{len(vlinks)} places with upcoming events, from concert halls and theaters to bars, churches, parks and the library.</p>', vl, FOOT]
    pages.append(("venues", "\n".join(vidx)))
    for path, text in pages:
        write_page(path, text)
    write_embeds(embeds)
    return [f"{SITE}/{p}/" for p, _ in pages]


# ----------------------------------------------------------------- venue widget (docs/embed/venue.html?v=<slug>)
EMBED_DATA = os.path.join(DOCS, "embed", "v")


def embed_snippet(name, slug):
    n = html.escape(name, quote=True)
    return (f'<iframe src="{SITE}/embed/venue.html?v={slug}" title="Upcoming events at {n}" width="100%" height="440" '
            f'style="border:0;max-width:480px" loading="lazy"></iframe>\n'
            f'<p style="font:13px sans-serif;max-width:480px;margin:6px 0"><a href="{SITE}/venues/{slug}/">{n} events calendar</a> '
            f'by CoMo Events, the live map of everything happening in Columbia, MO</p>')


def embed_section(name, slug):
    return (f'<h2>Add this calendar to your website</h2>'
            f'<p class="intro">Run {html.escape(name)} or a site about it? Paste this code into any web page to show its upcoming events. '
            f'It updates itself every two hours and is free.</p>'
            f'<textarea class="snippet" readonly aria-label="Embed code" onclick="this.select()">{html.escape(embed_snippet(name, slug))}</textarea>'
            f'<p class="btns" style="margin-top:4px"><button class="btn" type="button" '
            f'onclick="navigator.clipboard.writeText(document.querySelector(\'textarea.snippet\').value);this.textContent=\'Copied\'">Copy code</button> '
            f'<a class="btn" href="/embed/venue.html?v={slug}" rel="nofollow">Preview</a></p>')


def embed_event(ev):
    out = {"t": ev["title"], "s": ev["start"], "u": f"/e/{ev['_slug']}/"}
    if ev.get("end"):
        out["e"] = ev["end"]
    if ev.get("allDay") or ev.get("timeTBD"):
        out["a"] = 1
    price = clean(ev.get("price"))
    if price and len(price) <= 24:
        out["p"] = price
    return out


def write_embeds(embeds):
    """One small JSON per venue for the widget. Files of venues with nothing upcoming stay (emptied), so widgets
    already pasted on a venue's site keep working between seasons."""
    os.makedirs(EMBED_DATA, exist_ok=True)
    for f in sorted(os.listdir(EMBED_DATA)):
        slug = f[:-5]
        if f.endswith(".json") and slug not in embeds:
            try:
                old = json.load(open(os.path.join(EMBED_DATA, f)))
            except (OSError, ValueError):
                old = {}
            embeds[slug] = {"name": old.get("name", ""), "address": old.get("address", ""), "url": f"{SITE}/venues/", "events": []}
    for slug, data in embeds.items():
        with open(os.path.join(EMBED_DATA, slug + ".json"), "w") as f:
            json.dump(data, f, ensure_ascii=False, separators=(",", ":"))


# ----------------------------------------------------------------- seasonal and holiday pages
D = dt.date


def nth_weekday(year, month, weekday, n):
    first = D(year, month, 1)
    return first + dt.timedelta(days=(weekday - first.weekday()) % 7 + 7 * (n - 1))


def thanksgiving(y):
    return nth_weekday(y, 11, 3, 4)


# Each page exists only while today is inside one of its windows (open, close, holiday-or-None), dates inclusive.
# `title` is matched against the event title, `desc` (stricter) against title + description.
SEASONS = [
    dict(path="halloween", name="Halloween", h1="Halloween events in Columbia, MO",
         windows=lambda y: [(D(y, 10, 10), D(y, 10, 31), D(y, 10, 31))],
         title=r"hallowe+n|trick.or.treat|trunk.or.treat|costume|haunt|\bboos?\b|spooky|pumpkin|zombie|ghost|witch|horror|fright|"
               r"dia de (los )?muertos|day of the dead|monster mash|scream",
         desc=r"halloween|trick.or.treat|trunk.or.treat|costume contest|haunted",
         blurb="trunk-or-treats, haunted houses, costume parties and contests, pumpkin carving, kids' Halloween events and spooky shows"),
    dict(path="thanksgiving", name="Thanksgiving", h1="Thanksgiving events in Columbia, MO",
         windows=lambda y: [(thanksgiving(y) - dt.timedelta(days=21), thanksgiving(y) + dt.timedelta(days=3), thanksgiving(y))],
         title=r"thanksgiving|\bturkey|friendsgiving|black friday|small business saturday|gratitude|harvest|\bfeast",
         desc=r"thanksgiving|friendsgiving|turkey trot",
         blurb="the Turkey Trot, Friendsgiving and Thanksgiving dinners, harvest events, Black Friday and Small Business Saturday"),
    dict(path="christmas", name="Christmas", h1="Christmas and holiday events in Columbia, MO",
         windows=lambda y: [(D(y, 11, 10), D(y, 12, 25), D(y, 12, 25))],
         title=r"christmas|x-?mas|holiday|santa|nutcracker|\blights?\b|carol|hanukkah|chanukah|menorah|kwanzaa|tree lighting|ugly sweater|"
               r"jingle|grinch|gingerbread|winter wonderland|messiah|sleigh|\belf\b|noel|yule|mistletoe|reindeer|polar express|wreath|"
               r"ornament|cookie decorat|stocking|festive|merry|bazaar|craft (fair|show)",
         desc=r"christmas|santa|nutcracker|hanukkah|chanukah|holiday lights|holiday market|holiday concert|tree lighting",
         blurb="holiday light displays, The Nutcracker, photos with Santa, holiday markets and craft fairs, tree lightings, "
               "Christmas concerts and Hanukkah events"),
    dict(path="new-years-eve", name="New Year's Eve", h1="New Year's Eve events in Columbia, MO",
         windows=lambda y: [(D(y, 12, 17), D(y + 1, 1, 1), D(y, 12, 31))],
         title=r"new year|\bnye\b|countdown|ball drop|midnight|noon year|first night|polar plunge|champagne",
         desc=r"new year'?s eve|\bnye\b|countdown to midnight",
         night_of=(12, 31),   # plus every party, nightlife and music event on the night itself
         blurb="New Year's Eve parties, countdowns, live music, dinners and family-friendly Noon Year celebrations"),
    dict(path="valentines", name="Valentine's Day", h1="Valentine's Day events in Columbia, MO",
         windows=lambda y: [(D(y, 1, 25), D(y, 2, 15), D(y, 2, 14))],
         title=r"valentine|galentine|sweetheart|romanti|\bcouples?\b|date night|speed dat|cupid|be mine|\blove\b",
         desc=r"valentine|galentine|date night",
         blurb="Valentine's dinners, date nights, Galentine's parties, couples' classes, love-song concerts and singles events"),
    dict(path="st-patricks", name="St. Patrick's Day", h1="St. Patrick's Day events in Columbia, MO",
         windows=lambda y: [(D(y, 2, 24), D(y, 3, 17), D(y, 3, 17))],
         title=r"st\.? ?patrick|saint patrick|patty'?s day|paddy|shamrock|irish|green beer|leprechaun|celtic|bagpipe|pub crawl",
         desc=r"st\.? ?patrick|saint patrick|irish music",
         blurb="the St. Patrick's Day parade, Irish music, pub crawls, green beer and family shamrock events"),
    dict(path="fourth-of-july", name="Fourth of July", h1="Fourth of July events and fireworks in Columbia, MO",
         windows=lambda y: [(D(y, 6, 13), D(y, 7, 5), D(y, 7, 4))],
         title=r"fourth of july|4th of july|july 4|july fourth|independence day|firework|fire in the sky|red,? white|patriot|"
               r"america'?s birthday|freedom",
         desc=r"fourth of july|4th of july|independence day|fireworks",
         blurb="fireworks including Fire in the Sky, Independence Day parades, cookouts, concerts and family celebrations"),
    dict(path="graduation", name="Mizzou graduation", h1="Mizzou commencement and graduation events in Columbia, MO",
         windows=lambda y: [(D(y, 4, 25), D(y, 5, 20), None), (D(y, 12, 1), D(y, 12, 21), None)],
         title=r"commencement|graduat|hooding|convocation|\bgrads?\b|class of 20\d\d|cap and gown|lavender|recognition ceremony|"
               r"senior (send|celebration|recital)",
         desc=r"commencement|graduation ceremony|graduating",
         label="month",       # "December 2026" rather than just the year: there are two seasons a year
         blurb="University of Missouri commencement ceremonies, college and department celebrations, Stephens and Columbia "
               "College graduations, and things to do with family in town"),
]


def active_seasons(today):
    """[(season, open, close, holiday)] for the pages that should exist today."""
    out = []
    for season in SEASONS:
        for y in (today.year - 1, today.year):
            for opens, closes, holiday in season["windows"](y):
                if opens <= today <= closes:
                    out.append((season, opens, closes, holiday))
    return out


def season_label(season, closes, holiday):
    return (holiday or closes).strftime("%B %Y" if season.get("label") == "month" else "%Y")


def season_match(season, ev, closes):
    s = parse(ev["start"])
    if s.date() > closes:
        return False
    title = ev.get("title") or ""
    if re.search(season["title"], title, re.I):
        return True
    if re.search(season["desc"], title + " " + clean(ev.get("description"))[:400], re.I):
        return True
    night = season.get("night_of")
    if night and (s.month, s.day) == night and s.hour >= 18 and ev.get("category") in ("party", "nightlife", "music"):
        return True
    return False


SEASON_DIRS = [s["path"] for s in SEASONS]


def build_seasons(events, now, active):
    for d in SEASON_DIRS:
        if os.path.isdir(os.path.join(DOCS, d)):
            shutil.rmtree(os.path.join(DOCS, d))
    upcoming = [ev for ev in events if parse(ev.get("end") or ev["start"]) >= now - dt.timedelta(hours=1)]
    home = ("Home", f"{SITE}/")
    urls = []
    for season, opens, closes, holiday in active:
        path, label = season["path"], season_label(season, closes, holiday)
        evs = [ev for ev in upcoming if season_match(season, ev, closes)]
        h1 = f"{season['h1']} {label}"
        when = f" {season['name']} falls on {holiday:%A, %B %-d}." if holiday and holiday >= now.date() else ""
        intro = (f"{len(evs)} {season['name']} events in Columbia, Missouri: {season['blurb']}.{when} "
                 "Updated every two hours from venues, Mizzou, the library and local organizers.")
        write_page(path, landing_page(path, h1, h1, intro, evs,
                   f"{season['name']} events will show up here as they are announced. Check this weekend's events below.",
                   [home, (h1, f"{SITE}/{path}/")]))
        urls.append(f"{SITE}/{path}/")
    return urls


def season_links(active):
    seen, out = set(), []
    for season, opens, closes, holiday in active:
        if season["path"] not in seen:
            seen.add(season["path"])
            out.append((f"/{season['path']}/", f"{season['name']} {season_label(season, closes, holiday)}"))
    return out


def patch_homepage(links):
    """Keep the in-season holiday links in the homepage's static Browse row (between the season markers)."""
    p = os.path.join(DOCS, "index.html")
    try:
        text = open(p).read()
    except OSError:
        return
    inner = "".join(f'<a href="{u}">{html.escape(t)}</a>' for u, t in links)
    new = re.sub(r"(<!--season-->).*?(<!--/season-->)", lambda m: m.group(1) + inner + m.group(2), text, flags=re.S)
    if new != text:
        with open(p, "w") as f:
            f.write(new)


# ----------------------------------------------------------------- weekend guide (/weekend-guide/ and /weekend-guide/<friday>/)
GUIDE_DIR = os.path.join(DOCS, "weekend-guide")
GUIDE_DATA = os.path.join(ROOT, "feed", "weekend")    # one JSON per weekend: picks + events, so past weeks keep their content
GUIDE_KEYS = ("id", "title", "start", "end", "allDay", "timeTBD", "venue", "category", "categories", "price", "imageUrl",
              "ticketUrl", "source", "alsoOn", "_slug")


def guide_record(ev):
    rec = {k: ev[k] for k in GUIDE_KEYS if ev.get(k)}
    desc = clean(ev.get("description"))
    if desc:
        rec["description"] = desc[:300]
    return rec


def update_guide_data(events, now):
    """Refresh this weekend's stored picks and event list. Events that already happened stay (the feed drops them);
    picks freeze once the weekend starts (Friday 4 PM), so the archived page reads like it did that weekend."""
    win_start, win_end = weekly_post.weekend_window(now.date())
    fri = win_start.date()
    path = os.path.join(GUIDE_DATA, f"{fri}.json")
    try:
        stored = json.load(open(path))
    except (OSError, ValueError):
        stored = {"friday": fri.isoformat(), "published": now.date().isoformat(), "picks": [], "events": []}
    pool = {e["id"]: e for e in stored["events"] if parse(e["start"]) < now}
    for ev in events:
        if fri <= parse(ev["start"]).date() <= fri + dt.timedelta(days=2):
            pool[ev["id"]] = guide_record(ev)
    if now < win_start or not stored["picks"]:
        # a show one source marks canceled can still be live on another (Vox copies the Blue Note): skip both
        key = lambda t: re.sub(r"[^a-z0-9]+", " ", re.sub(r"(?i)\[?\b(cancell?ed|postponed)\b\]?:?", "", t).lower()).strip()
        off = {key(e["title"]) for e in pool.values() if re.search(r"(?i)\b(cancell?ed|postponed)\b", e["title"])}
        cands = [e for e in pool.values() if key(e["title"]) not in off]
        stored["picks"] = [e["id"] for _, e in weekly_post.pick(cands, win_start, win_end, 10)]
    stored["events"] = sorted(pool.values(), key=lambda e: (e["start"], e["title"], e["id"]))
    stored["modified"] = min(now.date(), fri + dt.timedelta(days=2)).isoformat()
    os.makedirs(GUIDE_DATA, exist_ok=True)
    with open(path, "w") as f:
        json.dump(stored, f, ensure_ascii=False, indent=1, sort_keys=True)
        f.write("\n")


def guide_range(fri):
    sun = fri + dt.timedelta(days=2)
    return f"{fri:%B %-d}–{sun:%-d}, {sun:%Y}" if fri.month == sun.month else f"{fri:%B %-d}–{sun:%B %-d}, {sun:%Y}"


def short_venue(v):
    return clean(v).split(",")[0].strip()


def ev_link(ev, live):
    t = html.escape(weekly_post.clean_title(ev["title"], short_venue(ev.get("venue"))))
    return f'<a href="/e/{ev["_slug"]}/">{t}</a>' if ev.get("_slug") in live else f"<b>{t}</b>"


def one_line(ev):
    """First sentence of the description, if it says more than the title."""
    desc = ev.get("description") or ""
    first = desc
    for m in re.finditer(r"[.!?]\s+(?=[A-Z0-9\"“])", desc):    # first sentence end that is not "St." or "Dr."
        if not re.search(r"\b(St|Dr|Mr|Mrs|Ms|Jr|Sr|vs|Ave|Blvd|Rd|[A-Z])$", desc[:m.start()]):
            first = desc[:m.start() + 1]
            break
    first = first.strip()
    if len(first) < 25 or first.lower().startswith(ev["title"].lower()[:30]):
        first = desc.strip()
    if not first or first.lower() == ev["title"].lower():
        return ""
    return first if len(first) <= 140 else first[:137].rsplit(" ", 1)[0] + "…"


def picks_html(picks, live):
    out = ['<ol class="picks">']
    for ev in picks:
        s = parse(ev["start"])
        meta = [s.strftime("%a") + ("" if ev.get("allDay") or ev.get("timeTBD") else " " + fmt_time(s).lower())]
        if short_venue(ev.get("venue")):
            meta.append(short_venue(ev["venue"]))
        price = clean(ev.get("price"))
        if price and len(price) <= 20:
            meta.append(price)
        line = one_line(ev)
        out.append(f'<li>{CAT_EMOJI.get(ev.get("category"), "📍")} {ev_link(ev, live)}<small>{html.escape(" · ".join(meta))}</small>'
                   + (f'<small>{html.escape(line)}</small>' if line else "") + "</li>")
    out.append("</ol>")
    return "\n".join(out)


def guide_intro(fri, picks, pool, live, active):
    """A few sentences written from the data: what kind of weekend it is, the headliners per day, families, budget."""
    sun = fri + dt.timedelta(days=2)
    free = [e for e in pool if is_free(e)]
    fam = [e for e in pool if "family" in (e.get("categories") or [e.get("category")])]
    night = [e for e in pool if e.get("category") in ("music", "nightlife", "party")]
    paras = []
    season = next((s for s, o, c, h in active_seasons(fri)), None)     # from the weekend's own date, so archives stay put
    opener = (f"It is {season['name']} season in Columbia, and this weekend's calendar shows it." if season
              else "Here is what is worth leaving the house for in Columbia this weekend.")
    paras.append(f"{opener} From {fri:%A, %B %-d} through {sun:%A, %B %-d}, CoMo Events lists {len(pool)} public events around town, "
                 f"{len(free)} of them free.")
    by_day = {}
    for e in picks:
        by_day.setdefault(parse(e["start"]).weekday(), e)
    bits = []
    phrases = {4: "Friday night, start with {t}{v}.", 5: "On Saturday, {t}{v} is our top pick.", 6: "Sunday closes things out with {t}{v}."}
    for wd in (4, 5, 6):
        if wd in by_day:
            e = by_day[wd]
            v = f" at {html.escape(short_venue(e.get('venue')))}" if short_venue(e.get("venue")) else ""
            bits.append(phrases[wd].format(t=ev_link(e, live), v=v))
    tigers = next((e for e in pool if e.get("category") == "sports" and re.search(r"mizzou|tigers", e["title"], re.I)
                   and re.search(r"\bvs?\.?\b|versus|football|basketball|volleyball|soccer|softball|baseball|wrestling|gymnastics",
                                 e["title"], re.I)), None)
    if tigers:
        bits.append(f"Mizzou fans: {ev_link(tigers, live)} is on {parse(tigers['start']):%A}.")
    if bits:
        paras.append(" ".join(bits))
    tail = []
    if fam:
        ex = next((e for e in fam if e["id"] not in {p["id"] for p in picks}), fam[0])
        tail.append(f"With kids, there are {len(fam)} family events to choose from, such as {ev_link(ex, live)}.")
    if night:
        tail.append(f"Night owls have {len(night)} concerts, parties and nightlife events.")
    if season and season["path"] in {s["path"] for s, o, c, h in active}:    # only while that page exists
        tail.append(f'See every {season["name"]} event on our <a href="/{season["path"]}/">{season["name"]} page</a>.')
    if tail:
        paras.append(" ".join(tail))
    return '<div class="lede">' + "".join(f"<p>{p}</p>" for p in paras) + "</div>"


def guide_page(data, live, active, newer, older):
    fri = D.fromisoformat(data["friday"])
    pool = data["events"]
    by_id = {e["id"]: e for e in pool}
    picks = [by_id[i] for i in data["picks"] if i in by_id]
    url = f"{SITE}/weekend-guide/{fri}/"
    rng = guide_range(fri)
    title = f"Columbia, MO weekend guide: {rng} · Top things to do"
    desc = (f"The best things to do in Columbia, MO, {rng}: our top {len(picks)} picks and all {len(pool)} events of the weekend, "
            "from concerts and Mizzou games to free and family events.")
    image = next((e["imageUrl"] for e in picks if e.get("imageUrl")), FALLBACK_IMAGE)
    article = {"@context": "https://schema.org", "@type": "Article", "headline": f"Things to do in Columbia, MO: weekend of {rng}",
               "description": desc, "image": [image], "datePublished": data["published"], "dateModified": data["modified"],
               "author": {"@type": "Organization", "name": "CoMo Events", "url": SITE + "/"},
               "publisher": {"@type": "Organization", "name": "CoMo Events", "logo": {"@type": "ImageObject", "url": FALLBACK_IMAGE}},
               "mainEntityOfPage": url}
    ld = ('\n<script type="application/ld+json">\n' + json.dumps(article, ensure_ascii=False, indent=1).replace("</", "<\\/") + "\n</script>\n"
          + item_list_ld(f"Top picks for the weekend of {rng}", url, [e for e in picks if e.get("_slug") in live],
                         [("Home", f"{SITE}/"), ("Weekend guide", f"{SITE}/weekend-guide/"), (rng, url)]))
    out = [head(title, desc, url, image, ld)]
    out.append(f'<p class="intro" style="margin:0">Weekend guide · updated {D.fromisoformat(data["modified"]):%B %-d, %Y}</p>')
    out.append(f'<h1 style="margin-top:4px">Things to do in Columbia, MO this weekend: {html.escape(rng)}</h1>')
    out.append(guide_intro(fri, picks, pool, live, active))
    if picks:
        out.append(f"<h2>Our top {len(picks)} picks</h2>")
        out.append(picks_html(picks, live))
    out.append(f'<h2>Everything happening {weekly_post.date_range(fri)}</h2>')
    out.append(event_list_html(pool, limit=400, live=live) if pool else '<p class="empty-note">Events for this weekend will show up here as they are announced.</p>')
    nav = []
    if older:
        nav.append(f'<a class="btn" href="/weekend-guide/{older}/">← Weekend of {D.fromisoformat(older):%b %-d}</a>')
    if newer:
        nav.append(f'<a class="btn" href="/weekend-guide/{newer}/">Weekend of {D.fromisoformat(newer):%b %-d} →</a>')
    nav.append('<a class="btn" href="/weekend-guide/">All weekend guides</a>')
    out.append('<p class="btns">' + " ".join(nav) + "</p>")
    out.append(FOOT)
    return "\n".join(out)


def build_weekend_guide(events, now, active):
    update_guide_data(events, now)
    live = {ev["_slug"] for ev in events}
    weeks = sorted(f[:-5] for f in os.listdir(GUIDE_DATA) if re.fullmatch(r"\d{4}-\d{2}-\d{2}\.json", f))
    datas = {w: json.load(open(os.path.join(GUIDE_DATA, w + ".json"))) for w in weeks}
    urls = [f"{SITE}/weekend-guide/"]
    for i, w in enumerate(weeks):    # every week is re-rendered so links to events that have passed go away
        write_page(f"weekend-guide/{w}", guide_page(datas[w], live, active, weeks[i + 1] if i + 1 < len(weeks) else None,
                                                    weeks[i - 1] if i else None))
        urls.append(f"{SITE}/weekend-guide/{w}/")
    cur = datas[weeks[-1]]
    fri = D.fromisoformat(cur["friday"])
    by_id = {e["id"]: e for e in cur["events"]}
    picks = [by_id[i] for i in cur["picks"] if i in by_id]
    rng = guide_range(fri)
    hub_url = f"{SITE}/weekend-guide/"
    out = [head("Columbia, MO weekend guide · Best things to do this weekend · CoMo Events",
                f"Every week, the best things to do in Columbia, Missouri: top 10 picks for {rng} plus every concert, party, market, "
                "Mizzou game and family event of the weekend.",
                hub_url, next((e["imageUrl"] for e in picks if e.get("imageUrl")), FALLBACK_IMAGE),
                "\n" + item_list_ld(f"Top picks for the weekend of {rng}", hub_url, [e for e in picks if e.get("_slug") in live],
                                    [("Home", f"{SITE}/"), ("Weekend guide", hub_url)]))]
    out.append('<h1 style="margin-top:4px">Weekend guide: the best things to do in Columbia, MO</h1>')
    out.append('<p class="intro">Every week we go through every public event in Columbia, Missouri, from The Blue Note and Mizzou '
               'to the library and the farmers market, and pick the ten worth planning your weekend around. '
               'A new guide goes up every Monday and fills in as the week goes on.</p>')
    out.append(f"<h2>This weekend: {html.escape(rng)}</h2>")
    out.append(guide_intro(fri, picks, cur["events"], live, active))
    if picks:
        out.append(picks_html(picks, live))
    out.append(f'<p class="btns"><a class="btn primary" href="/weekend-guide/{fri}/">Read the full guide: all {len(cur["events"])} events</a>'
               ' <a class="btn" href="/this-weekend/">This weekend, live</a></p>')
    past = [w for w in reversed(weeks[:-1])]
    if past:
        out.append("<h2>Past weekend guides</h2><ul class=\"more\">")
        for w in past:
            d = datas[w]
            out.append(f'<li><a href="/weekend-guide/{w}/"><span>🗓️</span><span>Weekend of {html.escape(guide_range(D.fromisoformat(w)))}'
                       f'<small>{len(d["picks"])} picks · {len(d["events"])} events</small></span></a></li>')
        out.append("</ul>")
    out.append(FOOT)
    write_page("weekend-guide", "\n".join(out))
    return urls


def main():
    feed = json.load(open(os.path.join(DOCS, "events.json")))
    events = merge_repeats([e for e in feed["events"] if e.get("start") and e.get("title")])
    assign_slugs(events)
    venues = load_venues()
    by_day = defaultdict(list)
    for ev in events:
        by_day[parse(ev["start"]).date()].append(ev)

    now = dt.datetime.now(ZoneInfo("America/Chicago"))
    active = active_seasons(now.date())
    links = season_links(active)
    set_nav(links)
    patch_homepage(links)
    landing_urls = build_landing(events, venues, now)
    landing_urls += build_seasons(events, now, active)
    landing_urls += build_weekend_guide(events, now, active)

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    for ev in events:
        venue = venues.get((ev.get("venue") or "").lower().strip())
        day = by_day[parse(ev["start"]).date()]
        i = day.index(ev)
        same_day = (day[i + 1:] + day[:i])[:6]
        d = os.path.join(OUT, ev["_slug"])
        os.makedirs(d)
        with open(os.path.join(d, "index.html"), "w") as f:
            f.write(event_page(ev, same_day, venue))
    with open(os.path.join(OUT, "index.html"), "w") as f:
        f.write(index_page(events))
    with open(os.path.join(OUT, "event.css"), "w") as f:
        f.write(CSS.strip() + "\n")

    urls = [f"{SITE}/", f"{SITE}/about/", f"{SITE}/e/"] + landing_urls + [f"{SITE}/e/{ev['_slug']}/" for ev in events]
    with open(os.path.join(DOCS, "sitemap.xml"), "w") as f:
        f.write('<?xml version="1.0" encoding="UTF-8"?>\n<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n')
        f.writelines(f"  <url><loc>{u}</loc></url>\n" for u in urls)
        f.write("</urlset>\n")
    with open(os.path.join(DOCS, "robots.txt"), "w") as f:
        f.write(f"User-agent: *\nAllow: /\n\nSitemap: {SITE}/sitemap.xml\n")
    print(f"wrote {len(events)} event pages, {len(landing_urls)} landing pages, docs/e/index.html, sitemap ({len(urls)} urls), robots.txt")


if __name__ == "__main__":
    main()
