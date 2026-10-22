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
import unicodedata
from collections import defaultdict
from zoneinfo import ZoneInfo

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
<link rel="stylesheet" href="/e/event.css?v=1"><script src="/gc.js?v=1" defer></script>{extra}
</head><body><div class="wrap">
<div class="top"><a class="brand" href="/"><img src="/img/icon-512.png" alt="">CoMo Events</a><a class="map" href="/">Live map</a></div>
"""


BROWSE = [("/tonight/", "Today & tonight"), ("/this-weekend/", "This weekend"), ("/free/", "Free events"),
          ("/music/", "Live music"), ("/family/", "Family & kids"), ("/nightlife/", "Nightlife"), ("/arts/", "Arts, theater & film"),
          ("/food/", "Food & drink"), ("/sports/", "Sports"), ("/mizzou/", "Mizzou events"), ("/venues/", "Venues"), ("/e/", "Full calendar")]
NAV = '<nav class="browse">' + " ".join(f'<a href="{u}">{html.escape(t)}</a>' for u, t in BROWSE) + "</nav>"
FOOT = """<h2>Browse events in Columbia, MO</h2>""" + NAV + """
<footer><a href="/">Live map</a> · <a href="/about/">About</a> · <a href="/get/?c=eventpage">Get the free iPhone app</a> · <a href="/stats/">Stats</a></footer>
</div></body></html>
"""


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

def event_list_html(events, limit=200):
    by_day = defaultdict(list)
    for ev in events[:limit]:
        by_day[parse(ev["start"]).date()].append(ev)
    out = []
    for day in sorted(by_day):
        out.append(f'<div class="day">{day.strftime("%A, %B %-d")}</div><ul class="more">')
        for ev in by_day[day]:
            cat = ev.get("category") or "community"
            out.append(f'<li><a href="/e/{ev["_slug"]}/"><span>{CAT_EMOJI.get(cat, "📍")}</span><span>{html.escape(ev["title"])}'
                       f'<small>{html.escape(when_text(ev))}{" · " + html.escape(ev["venue"]) if ev.get("venue") else ""}</small></span></a></li>')
        out.append("</ul>")
    return "\n".join(out)

def item_list_ld(name, url, events, crumbs):
    data = [{"@context": "https://schema.org", "@type": "ItemList", "name": name, "url": url,
             "numberOfItems": len(events),
             "itemListElement": [{"@type": "ListItem", "position": i + 1, "url": f"{SITE}/e/{ev['_slug']}/"} for i, ev in enumerate(events[:50])]},
            {"@context": "https://schema.org", "@type": "BreadcrumbList",
             "itemListElement": [{"@type": "ListItem", "position": i + 1, "name": n, "item": u} for i, (n, u) in enumerate(crumbs)]}]
    return "\n".join('<script type="application/ld+json">\n' + json.dumps(d, ensure_ascii=False, indent=1).replace("</", "<\\/") + "\n</script>" for d in data)

def landing_page(path, title, h1, intro, events, empty_text, crumbs, extra_top=""):
    url = f"{SITE}/{path}/"
    desc = intro if len(intro) <= 155 else intro[:152].rsplit(" ", 1)[0] + "…"
    out = [head(title, desc, url, FALLBACK_IMAGE, "\n" + item_list_ld(h1, url, events, crumbs))]
    out.append(f'<h1 style="margin-top:4px">{html.escape(h1)}</h1>')
    out.append(f'<p class="intro">{html.escape(intro)}</p>')
    out.append(extra_top)
    out.append(f'<p style="margin:14px 0"><a class="btn primary" href="/?c=seo-{path.replace("/", "-")}">Open the live map</a></p>')
    out.append(event_list_html(events) if events else f'<p class="empty-note">{html.escape(empty_text)}</p>')
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
    used, vlinks = set(), []
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
            evs, "No upcoming events are listed here right now.", [home, ("Venues", f"{SITE}/venues/"), (name, f"{SITE}/venues/{slug}/")], top)))
        vlinks.append((name, slug, len(evs)))
    vl = "<ul class=\"more\">" + "".join(f'<li><a href="/venues/{s}/"><span>📍</span><span>{html.escape(n)}<small>{c} upcoming event{"s" if c != 1 else ""}</small></span></a></li>' for n, s, c in vlinks) + "</ul>"
    vidx = [head("Event venues in Columbia, MO · Concert halls, bars, theaters & more",
                 f"{len(vlinks)} places with upcoming events in Columbia, Missouri: music venues, theaters, bars, the library, Mizzou and more.",
                 f"{SITE}/venues/", FALLBACK_IMAGE),
            '<h1 style="margin-top:4px">Event venues in Columbia, MO</h1>',
            f'<p class="intro">{len(vlinks)} places with upcoming events, from concert halls and theaters to bars, churches, parks and the library.</p>', vl, FOOT]
    pages.append(("venues", "\n".join(vidx)))
    for path, text in pages:
        write_page(path, text)
    return [f"{SITE}/{p}/" for p, _ in pages]


def main():
    feed = json.load(open(os.path.join(DOCS, "events.json")))
    events = merge_repeats([e for e in feed["events"] if e.get("start") and e.get("title")])
    assign_slugs(events)
    venues = load_venues()
    by_day = defaultdict(list)
    for ev in events:
        by_day[parse(ev["start"]).date()].append(ev)

    landing_urls = build_landing(events, venues, dt.datetime.now(ZoneInfo("America/Chicago")))

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
