#!/usr/bin/env python3
"""Venue gap report for CoMo Events.

Compares the venues we already cover (feed/events.json + feed/venues.json) with
event-type places in Columbia from OpenStreetMap, checks the websites of the
uncovered ones for machine-readable events, and writes:

  Marketing/venue-gaps.md   human report (auto-add list, visit lists, walking route)
  Marketing/venue-gaps.csv  one row per OSM venue

Run:  python3 scripts/venue_gap.py            (uses caches when fresh)
      python3 scripts/venue_gap.py --refresh  (refetch OSM and websites)
      python3 scripts/venue_gap.py --max-sites 40

Caches live in scripts/.venue_gap_cache/ (not meant to be committed).
Only the standard library plus requests.
"""
import argparse
import csv
import difflib
import html
import json
import math
import os
import re
import sys
import time
import unicodedata
from urllib.parse import urljoin, urlparse, parse_qs, quote

import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "scripts", ".venue_gap_cache")
EVENTS = os.path.join(ROOT, "feed", "events.json")
VENUES = os.path.join(ROOT, "feed", "venues.json")
OUT_MD = os.path.join(ROOT, "Marketing", "venue-gaps.md")
OUT_CSV = os.path.join(ROOT, "Marketing", "venue-gaps.csv")

DOWNTOWN = (38.9517, -92.3341)   # 9th St & Broadway
CAMPUS = (38.9425, -92.3280)     # MU, between Francis Quad and the Student Center
DOWNTOWN_KM = 1.2
CAMPUS_KM = 0.9
BBOX = (38.85, -92.45, 39.02, -92.25)  # south, west, north, east

OVERPASS = ["https://overpass-api.de/api/interpreter",
            "https://overpass.private.coffee/api/interpreter"]
BROWSER_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/130 Safari/537.36")
BOT_UA = "CoMoEvents venue-gap/0.1 (community events app; ajay.kumar@missouri.edu)"

PARK_NAMES = re.compile(r"stephens lake|cosmo|flat branch|peace park|douglass park|albert.?oakland|"
                        r"twin lakes|nifong|rock bridge|gans creek|agricult|optimist|shelter gardens|"
                        r"rothwell|capen park|american legion|bear creek|fairview park|clary.?shy", re.I)

HIGH_CATS = {"bar", "pub", "nightclub", "music_venue", "theatre", "events_venue",
             "brewery", "winery", "distillery"}
EVENT_CATS = HIGH_CATS | {"arts_centre", "cinema", "community_centre", "museum", "gallery", "bookstore"}
LOW_CATS = {"library", "park"}

CAT_LABEL = {
    "bar": "bar", "pub": "pub", "nightclub": "nightclub", "music_venue": "music venue",
    "theatre": "theatre", "events_venue": "event venue", "brewery": "brewery", "winery": "winery",
    "distillery": "distillery", "arts_centre": "arts centre", "cinema": "cinema",
    "community_centre": "community centre", "museum": "museum", "gallery": "gallery",
    "bookstore": "bookstore", "library": "library", "park": "park",
}

STOP = set("""the a an and of at on in for by to bar grill pub co company brewing brewery brew
works winery vineyard vineyards distillery distilling columbia como mo missouri restaurant cafe club
house room hall center centre park st street llc inc tavern lounge music venue theatre theater library
museum gallery galleries shop books bookstore bookshop university mu mizzou s n e w ave avenue rd road
dr drive blvd building art arts community recreation area kitchen taproom saloon sports & n auditorium
amphitheater amphitheatre lounge public house hotel center space events event venue""".split())

# Places that are the same venue under another name, or covered by a source as a whole.
SAME_AS = {
    "daniel boone regional library": "Columbia Public Library",   # DBRL headquarters, Communico source
}
# Rooms run by a college with no website of their own: check the college's site instead.
OPERATOR_SITES = {"Columbia College": "https://www.ccis.edu/", "Stephens College": "https://www.stephens.edu/"}
INSTITUTION_RX = re.compile(r"auditorium|amphithea|lounge|library|archives|speaker.?s circle", re.I)
MU_BOX = (38.930, -92.340, 38.950, -92.312)  # south, west, north, east


# ----------------------------------------------------------------- helpers
def log(*a):
    print(*a, file=sys.stderr, flush=True)


def norm(s):
    s = html.unescape(s or "")
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    s = s.lower().replace("&", " and ").replace("'", "")
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = re.sub(r"\bthe\b", " ", s)
    return " ".join(s.split())


def tokens(s):
    return {t for t in norm(s).split() if t not in STOP and len(t) > 1}


def km(a, b):
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2 - la1) / 2) ** 2 + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2
    return 6371 * 2 * math.asin(math.sqrt(h))


def norm_addr(s):
    """'17 N. 9th Street, Columbia' -> '17 n 9th'"""
    s = norm(s)
    m = re.match(r"(\d+)\s+((?:[nsew]\s+)?\w+)", s)
    return f"{m.group(1)} {m.group(2)}" if m else None


def load_cache(name, max_age_days):
    p = os.path.join(CACHE, name)
    if os.path.exists(p) and time.time() - os.path.getmtime(p) < max_age_days * 86400:
        with open(p) as f:
            return json.load(f)
    return None


def save_cache(name, data):
    os.makedirs(CACHE, exist_ok=True)
    with open(os.path.join(CACHE, name), "w") as f:
        json.dump(data, f, indent=1)


# ----------------------------------------------------------------- 1. covered venues
def covered_venues():
    """Return list of dicts {name, n, toks, lat, lng, addr, kind} where kind is events|table."""
    out = []
    ev = json.load(open(EVENTS))["events"]
    seen = {}
    for e in ev:
        name = e.get("venue") or ""
        if not name or norm(name) in ("none", "tba", "tbd"):
            name = ""
        key = (norm(name), norm_addr(e.get("address") or ""))
        if key in seen:
            seen[key]["count"] += 1
            continue
        d = {"name": name, "n": norm(name), "toks": tokens(name), "lat": e.get("lat"), "lng": e.get("lng"),
             "addr": norm_addr(e.get("address") or "") or norm_addr(name), "kind": "events", "count": 1}
        seen[key] = d
        out.append(d)
    table = json.load(open(VENUES))
    for name, v in table.items():
        for alias in [name] + list(v.get("aliases", [])):
            out.append({"name": name, "n": norm(alias), "toks": tokens(alias), "lat": v.get("lat"),
                        "lng": v.get("lng"), "addr": norm_addr(v.get("address") or ""), "kind": "table",
                        "count": 0})
    return out


def similar(a, b):
    return difflib.SequenceMatcher(None, a, b).ratio()


def core(toks):
    return " ".join(sorted(toks))


def name_match(osm_n, osm_toks, c):
    if not osm_n or not c["n"]:
        return False
    if osm_n == c["n"] or similar(osm_n, c["n"]) >= 0.88:
        return True
    if osm_toks and core(osm_toks) == core(c["toks"]) and sum(map(len, osm_toks)) >= 4:
        return True
    # Every distinctive word of the OSM name appears in a (possibly long) feed location string,
    # e.g. "Bond Life Sciences Center" in "Monsanto Auditorium Bond Life Sciences Center ...".
    if len(osm_toks) >= 2 and osm_toks <= c["toks"]:
        return True
    # The feed name is a shorter form of the OSM name, with at most one extra word.
    if len(c["toks"]) >= 1 and sum(map(len, c["toks"])) >= 5 and c["toks"] <= osm_toks \
            and len(osm_toks - c["toks"]) <= 1:
        return True
    return False


def near_match(v, c):
    if c["lat"] is None or c["lng"] is None:
        near = False
    else:
        near = km((v["lat"], v["lon"]), (c["lat"], c["lng"])) <= 0.06
    same_addr = v["addr_key"] and c["addr"] and v["addr_key"] == c["addr"]
    if not (near or same_addr):
        return False
    a, b = core(v["toks"]), core(c["toks"])
    return bool(a and b) and (similar(a, b) >= 0.75 or bool(v["toks"] & c["toks"]))


def in_mu(v):
    s, w, n, e = MU_BOX
    return s <= v["lat"] <= n and w <= v["lon"] <= e


def coverage(v, cov):
    if v["n"] in SAME_AS:
        return "yes", SAME_AS[v["n"]]
    kinds = set()
    hit = None
    for c in cov:
        if name_match(v["n"], v["toks"], c) or near_match(v, c):
            kinds.add(c["kind"])
            hit = hit or c["name"]
            if c["kind"] == "events":
                return "yes", c["name"]
    campus_kind = v["category"] in ("theatre", "events_venue", "arts_centre", "library", "museum", "gallery")
    if (INSTITUTION_RX.search(v["name"]) or campus_kind) and (v.get("operator") == "University of Missouri" or in_mu(v)):
        return "yes", "Mizzou calendar (campus room)"
    return ("table-only", hit) if kinds else ("no", None)


# ----------------------------------------------------------------- 2. OSM universe
OVERPASS_Q = """[out:json][timeout:60];
(
  nwr["amenity"~"^(bar|pub|nightclub|theatre|arts_centre|cinema|community_centre|events_venue|music_venue|library)$"]({b});
  nwr["craft"~"^(brewery|winery|distillery)$"]({b});
  nwr["tourism"~"^(museum|gallery)$"]({b});
  nwr["shop"="books"]({b});
  nwr["leisure"="park"]["name"]({b});
);
out center tags;"""


def fetch_osm(refresh):
    if not refresh:
        c = load_cache("osm.json", 7)
        if c:
            return c
    q = OVERPASS_Q.format(b=",".join(str(x) for x in BBOX))
    wait = 15
    for attempt in range(6):
        url = OVERPASS[0] if attempt < 4 else OVERPASS[1]
        try:
            r = requests.post(url, data={"data": q}, headers={"User-Agent": BOT_UA}, timeout=90)
            if r.status_code == 200 and r.text.lstrip().startswith("{"):
                d = r.json()
                save_cache("osm.json", d)
                return d
            log(f"overpass {url} -> {r.status_code}, retry in {wait}s")
        except Exception as e:
            log("overpass error:", e)
        time.sleep(wait)
        wait = min(wait * 2, 120)
    stale = os.path.join(CACHE, "osm.json")
    if os.path.exists(stale):
        log("overpass unavailable, using stale cache")
        return json.load(open(stale))
    sys.exit("Overpass unavailable and no cache")


def osm_category(t):
    a = t.get("amenity")
    if t.get("craft") in ("brewery", "winery", "distillery"):
        return t["craft"]
    if a == "bar" and t.get("microbrewery") == "yes":
        return "brewery"
    if a in ("bar", "pub", "nightclub", "theatre", "arts_centre", "cinema", "community_centre",
             "events_venue", "music_venue", "library"):
        return a
    if t.get("tourism") in ("museum", "gallery"):
        return t["tourism"]
    if t.get("shop") == "books":
        return "bookstore"
    if t.get("leisure") == "park":
        return "park"
    return None


def osm_venues(d):
    out = []
    for el in d["elements"]:
        t = el.get("tags", {})
        name = t.get("name")
        if not name:
            continue
        cat = osm_category(t)
        if not cat:
            continue
        if cat == "park" and not PARK_NAMES.search(name):
            continue
        lat = el.get("lat") or (el.get("center") or {}).get("lat")
        lon = el.get("lon") or (el.get("center") or {}).get("lon")
        if lat is None:
            continue
        hn, st = t.get("addr:housenumber"), t.get("addr:street")
        addr = f"{hn} {st}" if hn and st else (st or "")
        web = t.get("website") or t.get("contact:website") or t.get("url") or ""
        fb = t.get("contact:facebook") or t.get("facebook") or ""
        if not web and fb:
            web = fb if fb.startswith("http") else f"https://www.facebook.com/{fb}"
        if not web and t.get("operator") in OPERATOR_SITES:
            web = OPERATOR_SITES[t["operator"]]
        if web and not web.startswith("http"):
            web = "https://" + web
        out.append({"name": name, "category": cat, "lat": lat, "lon": lon, "address": addr,
                    "website": web.strip(), "osm": f"{el['type']}/{el['id']}", "operator": t.get("operator", ""),
                    "n": norm(name), "toks": tokens(name), "addr_key": norm_addr(addr) if addr else None})
    # merge duplicates (same normalized name within 150 m), keep the richest record
    merged = []
    for v in sorted(out, key=lambda v: -(bool(v["website"]) * 2 + bool(v["address"]))):
        dup = next((m for m in merged if m["n"] == v["n"] and km((m["lat"], m["lon"]), (v["lat"], v["lon"])) < 0.15), None)
        if dup:
            continue
        merged.append(v)
    return merged


# ----------------------------------------------------------------- reverse geocode for missing addresses
def fill_addresses(venues, refresh):
    cache = (None if refresh else load_cache("revgeo.json", 90)) or {}
    last = 0
    for v in venues:
        if v["address"]:
            continue
        k = f"{v['lat']:.5f},{v['lon']:.5f}"
        if k not in cache:
            time.sleep(max(0, 1.05 - (time.time() - last)))
            last = time.time()
            try:
                r = requests.get("https://nominatim.openstreetmap.org/reverse",
                                 params={"lat": v["lat"], "lon": v["lon"], "format": "jsonv2", "zoom": 18},
                                 headers={"User-Agent": BOT_UA}, timeout=15)
                a = r.json().get("address", {})
                cache[k] = " ".join(x for x in (a.get("house_number"), a.get("road")) if x)
            except Exception as e:
                log("reverse geocode failed:", e)
                cache[k] = ""
        if cache.get(k):
            v["address"] = cache[k] + " (approx.)" if not re.match(r"\d", cache[k]) else cache[k]
    save_cache("revgeo.json", cache)


# ----------------------------------------------------------------- 4. website classification
S = requests.Session()
S.headers.update({"User-Agent": BROWSER_UA, "Accept-Language": "en-US,en;q=0.9"})
_last = [0.0]


def fetch(url, **kw):
    if re.search(r"/(login|signin|sign-in|account|my-account|wp-admin)\b", url, re.I):
        return None
    time.sleep(max(0, 1.0 - (time.time() - _last[0])))
    _last[0] = time.time()
    try:
        return S.get(url, timeout=10, allow_redirects=True, **kw)
    except requests.exceptions.SSLError:
        if url.startswith("https://"):
            log("   SSL error, trying http", url)
            return fetch("http://" + url[8:], **kw)
        return None
    except Exception as e:
        log("   fetch failed", url, type(e).__name__)
        return None


PROVIDERS = [
    ("Eventbrite", r"https?://(?:www\.)?eventbrite\.com/(?:o|e|cc)/[^\s\"'<>?#]+"),
    ("Posh", r"https?://(?:www\.)?posh\.vip/(?:g|e|f)/[^\s\"'<>?#]+"),
    ("Dice", r"https?://(?:link\.)?dice\.fm/(?:venue/)?[^\s\"'<>?#]+"),
    ("Ticketmaster", r"https?://(?:www\.)?(?:ticketmaster|livenation)\.com/[^\s\"'<>?#]+"),
    ("Etix", r"https?://(?:www\.)?etix\.com/ticket/[^\s\"'<>?#]+"),
    ("Prekindle", r"https?://(?:www\.)?prekindle\.com/[^\s\"'<>?#]+"),
    ("TicketWeb", r"https?://(?:www\.)?ticketweb\.com/[^\s\"'<>?#]+"),
    ("SeeTickets", r"https?://(?:wl\.)?seetickets\.us/[^\s\"'<>?#]+"),
    ("Tixr", r"https?://(?:www\.)?tixr\.com/[^\s\"'<>?#]+"),
    ("Ludus", r"https?://[a-z0-9-]+\.ludus\.com[^\s\"'<>?#]*"),
    ("OnTheStage", r"https?://(?:our\.)?onthestage\.tickets/[^\s\"'<>?#]+"),
    ("ThunderTix", r"https?://[a-z0-9-]+\.thundertix\.com[^\s\"'<>?#]*"),
    ("SimpleTix", r"https?://(?:www\.)?simpletix\.com/[^\s\"'<>?#]+"),
    ("ShowClix", r"https?://(?:www\.)?showclix\.com/[^\s\"'<>?#]+"),
    ("Universe", r"https?://(?:www\.)?universe\.com/[^\s\"'<>?#]+"),
    ("Tock", r"https?://(?:www\.)?exploretock\.com/[^\s\"'<>?#]+"),
    ("Resy events", r"https?://(?:www\.)?resy\.com/[^\s\"'<>?#]*events[^\s\"'<>?#]*"),
]
FEED_RES = [
    ("Google Calendar", r"calendar\.google\.com/calendar/(?:u/\d/)?(?:embed|ical)[^\s\"'<>]*"),
    ("iCal", r"(?:webcal://[^\s\"'<>]+|https?://[^\s\"'<>]+\.ics\b[^\s\"'<>]*)"),
    ("Tockify", r"tockify\.com/(?:embed/)?[a-z0-9_]+(?:/[a-z]+)?"),
    ("Timely", r"events\.time\.ly/[a-z0-9]+"),
]
EVENT_LINK = re.compile(r"\b(events?|calendar|shows?|live-?music|whats-?on|what-?s-?happening|concerts?|"
                        r"entertainment|lineup|upcoming|tickets|music)\b", re.I)


def ld_events(text):
    out = []
    for b in re.findall(r"<script[^>]*application/ld\+json[^>]*>(.*?)</script>", text or "", re.S | re.I):
        try:
            d = json.loads(b.strip())
        except Exception:
            continue
        stack = [d]
        while stack:
            x = stack.pop()
            if isinstance(x, dict):
                t = x.get("@type")
                ts = t if isinstance(t, list) else [t]
                if any(isinstance(y, str) and y.endswith("Event") for y in ts) and x.get("startDate"):
                    out.append(x)
                stack.extend(x.values())
            elif isinstance(x, list):
                stack.extend(x)
    return out


def future(ld):
    today = time.strftime("%Y-%m-%d")
    return [e for e in ld if str(e.get("startDate", ""))[:10] >= today]


def find_event_links(base, text):
    links = []
    def site(netloc):
        return ".".join(netloc.lower().split(":")[0].split(".")[-2:])
    host = site(urlparse(base).netloc)
    for href, label in re.findall(r"<a[^>]+href=[\"']([^\"'#]+)[\"'][^>]*>(.*?)</a>", text or "", re.S | re.I):
        label = re.sub(r"<[^>]+>", " ", label)
        full = urljoin(base, html.unescape(href))
        p = urlparse(full)
        if p.scheme not in ("http", "https") or site(p.netloc) != host:
            continue
        path = p.path.lower()
        if re.search(r"\.(jpg|png|pdf|gif|webp)$", path) or re.search(r"login|account|cart|wp-admin", path):
            continue
        if EVENT_LINK.search(path.replace("/", " ")) or EVENT_LINK.search(label.strip()[:40]):
            score = 2 if re.search(r"event|calendar", path) else 1
            links.append((score, full.split("#")[0]))
    seen, out = set(), []
    for s, u in sorted(links, key=lambda x: -x[0]):
        if u.rstrip("/") not in seen and u.rstrip("/") != base.rstrip("/"):
            seen.add(u.rstrip("/"))
            out.append(u)
    return out


def classify_site(url):
    """Return dict(method, endpoint, detail, platform)."""
    res = {"method": "no events found", "endpoint": "", "detail": "", "platform": ""}
    host = urlparse(url).netloc.lower()
    if re.search(r"facebook\.com|instagram\.com|fb\.me", host):
        res.update(method="Wix/Facebook only", platform="facebook", endpoint=url,
                   detail="Website is a Facebook/Instagram page")
        return res
    home = fetch(url)
    if home is None or home.status_code >= 400:
        res.update(method="site unreachable", detail=f"HTTP {getattr(home, 'status_code', 'error')}")
        return res
    base = home.url
    origin = f"{urlparse(base).scheme}://{urlparse(base).netloc}"
    pages = [(base, home.text)]
    h = home.text
    platform = ("wordpress" if re.search(r"wp-content|wp-json|wp-includes", h) or "api.w.org" in home.headers.get("Link", "")
                else "squarespace" if re.search(r"squarespace", h, re.I)
                else "wix" if re.search(r"wixstatic|wix\.com|_wixCIDX|X-Wix", h) or "x-wix-request-id" in {k.lower() for k in home.headers}
                else "shopify" if "cdn.shopify.com" in h
                else "godaddy" if "img1.wsimg.com" in h
                else "weebly" if "weebly" in h.lower()
                else "")
    res["platform"] = platform

    # The Events Calendar REST
    if platform == "wordpress":
        r = fetch(f"{origin}/wp-json/tribe/events/v1/events", params={"per_page": 10})
        if r is not None and r.status_code == 200 and r.headers.get("content-type", "").startswith("application/json"):
            try:
                js = r.json()
                n = js.get("total") or len(js.get("events", []))
                if js.get("events"):
                    res.update(method="Events Calendar REST", endpoint=f"{origin}/wp-json/tribe/events/v1/events",
                               detail=f"{n} upcoming event(s)")
                    return res
                res["detail"] = "Events Calendar REST answers but has no upcoming events"
            except Exception:
                pass

    links = find_event_links(base, h)
    if links:
        r = fetch(links[0])
        if r is not None and r.status_code == 200:
            pages.append((r.url, r.text))
            # one more hop if the first page is a generic "music" or "entertainment" page
            if not ld_events(r.text) and len(links) > 1 and not re.search(r"event|calendar", links[0], re.I):
                r2 = fetch(links[1])
                if r2 is not None and r2.status_code == 200:
                    pages.append((r2.url, r2.text))

    # Localist (common for colleges): public JSON API
    for purl, text in pages:
        if re.search(r"localist", text, re.I):
            po = f"{urlparse(purl).scheme}://{urlparse(purl).netloc}"
            r = fetch(f"{po}/api/2/events", params={"pp": 100, "days": 90})
            try:
                js = r.json() if r is not None and r.status_code == 200 else {}
            except Exception:
                js = {}
            if js.get("events"):
                total = len(js["events"])
                res.update(method="Localist API", endpoint=f"{po}/api/2/events",
                           detail=f"{total} events in the next 90 days across the whole calendar")
                return res

    # JSON-LD
    for purl, text in pages:
        fl = future(ld_events(text))
        if fl:
            res.update(method="JSON-LD Event on page", endpoint=purl, detail=f"{len(fl)} upcoming event(s) in JSON-LD")
            return res

    # Squarespace collection JSON
    if platform == "squarespace":
        cands = [p for p, _ in pages[1:]] or [f"{origin}/events"]
        for c in cands[:2]:
            r = fetch(c, params={"format": "json"})
            if r is not None and r.status_code == 200 and "json" in r.headers.get("content-type", ""):
                try:
                    js = r.json()
                except Exception:
                    continue
                up = js.get("upcoming") or []
                if up:
                    ep = c.split("?")[0] + "?format=json"
                    res.update(method="Squarespace events (?format=json has upcoming)", endpoint=ep,
                               detail=f"{len(up)} upcoming event(s)")
                    return res
                if "upcoming" in js or "past" in js:
                    res["detail"] = "Squarespace events page exists but nothing upcoming"

    alltext = "\n".join(t for _, t in pages)
    # calendar feeds
    for label, rx in FEED_RES:
        m = re.search(rx, alltext, re.I)
        if m:
            raw = html.unescape(m.group(0))
            ep = raw
            if label == "Google Calendar":
                qs = parse_qs(urlparse("https://" + raw.split("://")[-1]).query)
                src = (qs.get("src") or [""])[0]
                if src:
                    ep = f"https://calendar.google.com/calendar/ical/{quote(src)}/public/basic.ics"
                elif "/ical/" in raw:
                    ep = "https://" + raw.split("://")[-1] if not raw.startswith("http") else raw
                else:
                    continue
            elif label == "Tockify":
                cal = raw.split("/")[-1] if "/embed/" not in raw else raw.split("/embed/")[-1].split("/")[0]
                ep = f"https://tockify.com/api/ngevent?calname={cal}"
            res.update(method=f"{label} feed", endpoint=ep, detail=f"{label} calendar linked from site")
            return res

    # ticket providers
    found = []
    for label, rx in PROVIDERS:
        for m in re.findall(rx, alltext, re.I):
            u = html.unescape(m).rstrip("\\/.,)")
            if label == "Ticketmaster" and not re.search(r"/venue/|/artist/|/event/", u):
                continue
            found.append((label, u))
    if found:
        # prefer organizer / venue pages over single events
        found.sort(key=lambda x: 0 if re.search(r"/o/|/g/|/venue/|/promo|/organizer", x[1]) else 1)
        provs = sorted({f[0] for f in found})
        res.update(method="Ticket link found: " + ", ".join(provs), endpoint=found[0][1],
                   detail=f"{len(found)} ticket links")
        return res

    fb_events = re.search(r"https?://(?:www\.)?facebook\.com/[^\s\"'<>]*events", alltext, re.I)
    if platform == "wix" or fb_events:
        fb = re.search(r"https?://(?:www\.)?facebook\.com/[A-Za-z0-9.\-_/]+", alltext)
        res.update(method="Wix/Facebook only", endpoint=fb.group(0) if fb else "",
                   detail=("Wix site; " if platform == "wix" else "") + ("links to Facebook events" if fb_events else "no event listing found"))
        return res
    if not res["detail"]:
        res["detail"] = "events page checked: " + pages[-1][0] if len(pages) > 1 else "no events link on homepage"
    return res


AUTO_METHODS = ("Events Calendar REST", "Localist API", "JSON-LD Event on page", "Squarespace events", "Google Calendar feed",
                "iCal feed", "Tockify feed", "Timely feed")


def is_auto(m):
    return m.startswith(AUTO_METHODS) or (m.startswith("Ticket link found") and re.search(r"Posh|Eventbrite|Dice|Prekindle|Etix", m))


# ----------------------------------------------------------------- 5. scoring
def zone(v):
    d = km((v["lat"], v["lon"]), DOWNTOWN)
    c = km((v["lat"], v["lon"]), CAMPUS)
    v["dist_km"] = round(d, 2)
    return "downtown" if d <= DOWNTOWN_KM else "campus" if c <= CAMPUS_KM else "elsewhere"


def priority(v):
    z = v["zone"]
    cat = v["category"]
    if INSTITUTION_RX.search(v["name"]) or v.get("operator", "").endswith("College"):
        return "medium" if cat in EVENT_CATS else "low"
    if z in ("downtown", "campus") and cat in HIGH_CATS:
        return "high"
    if cat in EVENT_CATS and not (cat == "community_centre" and not v["website"]):
        return "medium"
    return "low"


def rank_key(v):
    w = {"music_venue": 6, "nightclub": 6, "theatre": 5, "events_venue": 2, "bar": 4, "pub": 4,
         "brewery": 4, "winery": 3, "distillery": 3, "arts_centre": 3, "cinema": 3, "bookstore": 2,
         "gallery": 2, "museum": 2, "community_centre": 1}.get(v["category"], 0)
    return (-w, v["dist_km"])


ASKS = {
    "bar": "Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.",
    "pub": "Ask for trivia, live music and watch-party nights. Public Facebook events or a simple events page is enough.",
    "nightclub": "Ask which ticket site they use for theme nights (Posh, Eventbrite). Send us the organizer link and we pull it automatically.",
    "music_venue": "Ask which ticket site they use and for the organizer page link. We pull shows automatically.",
    "theatre": "Ask for the season schedule and their ticketing site. We can read most ticket sites.",
    "events_venue": "Ask for their public events calendar or ticket organizer link.",
    "brewery": "Ask for food trucks, live music, trivia and release parties. A public Facebook events list or an events page is enough.",
    "winery": "Ask for live music and tasting events. Public Facebook events or an events page works.",
    "distillery": "Ask for tastings and live music. Public Facebook events or an events page works.",
    "arts_centre": "Ask for openings, classes and shows. An events page or calendar feed works.",
    "cinema": "Ask for special screenings and festivals.",
    "community_centre": "Ask for public classes and community events.",
    "museum": "Ask for exhibit openings and talks.",
    "gallery": "Ask for First Friday openings and artist talks.",
    "bookstore": "Ask for author readings, book clubs and story times.",
    "library": "Ask for public programs.",
    "park": "Covered by city and Visit Columbia listings; check Parks and Rec calendar.",
}


def suggested_ask(v):
    m = v.get("method", "")
    base = ASKS.get(v["category"], "Ask them to post public events.")
    if m.startswith("Ticket link found"):
        return f"They sell tickets on {m.split(': ', 1)[1]}. Confirm the organizer link so we can pull it. " + base
    if m == "Wix/Facebook only":
        return ("They only post on Facebook or a Wix page. Ask them to make their Facebook events public "
                "(AllEvents picks those up and so do we), or to send a weekly schedule.")
    if re.search(r"amphithea|circle", v["name"], re.I):
        return "Outdoor public stage. Find out who books it (city, county or college) and ask for their calendar."
    if v.get("operator", "").endswith("College"):
        return f"Ask the {v['operator']} events office for a public calendar feed (iCal or RSS)."
    return base


# ----------------------------------------------------------------- walking route
def route(points, start=DOWNTOWN):
    rest = list(points)
    order, cur = [], start
    while rest:
        nxt = min(rest, key=lambda p: km(cur, (p["lat"], p["lon"])))
        order.append(nxt)
        rest.remove(nxt)
        cur = (nxt["lat"], nxt["lon"])

    def length(o):
        pts = [start] + [(p["lat"], p["lon"]) for p in o]
        return sum(km(pts[i], pts[i + 1]) for i in range(len(pts) - 1))
    improved = True
    while improved:
        improved = False
        for i in range(len(order) - 1):
            for j in range(i + 2, len(order) + 1):
                cand = order[:i] + order[i:j][::-1] + order[j:]
                if length(cand) + 1e-9 < length(order):
                    order, improved = cand, True
    return order, length(order)


# ----------------------------------------------------------------- output
def clean(s):
    return (s or "").replace("\u2014", ", ").replace("|", "/").strip()


def write_outputs(venues, stats):
    os.makedirs(os.path.dirname(OUT_MD), exist_ok=True)
    cols = ["name", "category", "address", "lat", "lon", "website", "covered", "integration_method", "endpoint", "priority"]
    with open(OUT_CSV, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(cols)
        for v in sorted(venues, key=lambda v: ({"no": 0, "table-only": 1, "yes": 2}[v["covered"]],
                                               {"high": 0, "medium": 1, "low": 2}[v["priority"]], v["name"].lower())):
            w.writerow([v["name"], v["category"], v["address"], f"{v['lat']:.6f}", f"{v['lon']:.6f}", v["website"],
                        v["covered"], v.get("method", ""), v.get("endpoint", ""), v["priority"]])

    unc = [v for v in venues if v["covered"] == "no"]
    auto = [v for v in venues if v["covered"] != "yes" and is_auto(v.get("method", ""))]
    auto_ids = {id(v) for v in auto}
    def downtown_target(v):
        return v["priority"] == "high" or (v["priority"] == "medium" and v["zone"] == "downtown"
                                           and not v.get("operator", "").endswith("College"))
    down = sorted([v for v in unc if downtown_target(v) and id(v) not in auto_ids],
                  key=lambda v: ({"high": 0, "medium": 1}[v["priority"]],) + rank_key(v))
    down_ids = {id(v) for v in down}
    later = sorted([v for v in unc if id(v) not in down_ids and id(v) not in auto_ids],
                   key=lambda v: ({"high": 0, "medium": 1, "low": 2}[v["priority"]],) + rank_key(v))
    table_only = [v for v in venues if v["covered"] == "table-only" and v["category"] in EVENT_CATS
                  and id(v) not in auto_ids]

    L = []
    L.append("# Venue gap report")
    L.append("")
    L.append(f"Generated {time.strftime('%Y-%m-%d')} by `scripts/venue_gap.py`. Rerun it any time.")
    L.append("")
    L.append(f"OpenStreetMap lists {stats['osm']} event-type places in Columbia (bars, pubs, clubs, theatres, "
             f"breweries, arts spaces, museums, galleries, bookstores, libraries, community centres and the big parks).")
    L.append("")
    L.append(f"- Covered with events in the feed: {stats['yes']} (this counts {stats['mu_rooms']} MU auditoriums, "
             "libraries and halls, which the Mizzou calendar source covers as a whole)")
    L.append(f"- In `feed/venues.json` but no events in the feed yet: {stats['table']}")
    L.append(f"- Not covered: {stats['no']} ({stats['no_high']} high, {stats['no_med']} medium, {stats['no_low']} low priority)")
    L.append(f"- Websites checked: {stats['checked']} of {stats['with_site']} uncovered venues that have a website in OSM "
             f"(or a known operator site), plus {stats['table_checked']} venues from `feed/venues.json` with no events.")
    L.append("")
    L.append(f"Most uncovered places ({stats['no'] - stats['with_site']} of {stats['no']}) have no website in OSM, so "
             "the only way to reach them is in person or through their Facebook page.")
    L.append("")
    L.append("Priority: high means downtown (within 1.2 km of 9th and Broadway) or on campus, and a bar, pub, club, "
             "music venue, theatre, event venue or brewery. Medium means another event-type place. Low means libraries, parks "
             "and community centres without a website.")
    L.append("")
    L.append("OSM is not complete. It also leaves out restaurants and cafes, and several of those host music and trivia. "
             "A place missing here may still be worth a visit.")
    L.append("")

    L.append("## Can add automatically now")
    L.append("")
    if not auto:
        L.append("None found in this run.")
    else:
        L.append("These sites publish events a script can read. Tribe sites go in `TRIBE_SITES`, Posh groups in "
                 "`POSH_GROUPS`. The rest need a small `src_*` parser. Add the venue to `feed/venues.json` too.")
        L.append("")
        L.append("| Venue | Type | Method | Endpoint | Note |")
        L.append("|---|---|---|---|---|")
        order = {"Events Calendar REST": 0, "Localist": 0, "Squarespace": 1, "JSON-LD": 2, "Google": 3, "iCal": 3, "Tockify": 3, "Timely": 3}
        groups = {}
        for v in sorted(auto, key=lambda v: (min([o for k, o in order.items() if v["method"].startswith(k)] or [5]),
                                             {"high": 0, "medium": 1, "low": 2}[v["priority"]], v["dist_km"])):
            groups.setdefault(v["endpoint"], []).append(v)
        for ep, vs in groups.items():
            v = vs[0]
            nm = ", ".join(clean(x["name"]) + (" (in venues.json, no events yet)" if x["covered"] == "table-only" else "")
                           for x in vs)
            if v.get("operator"):
                nm = f"{v['operator']} calendar: {nm}"
            kinds = ", ".join(sorted({CAT_LABEL[x["category"]] for x in vs}))
            L.append(f"| {nm} | {kinds}, {v['priority']} | {clean(v['method'])} | {ep} | {clean(v.get('detail'))} |")
    L.append("")

    L.append("## Visit in person – downtown priority")
    L.append("")
    L.append("Downtown and campus places with no feed we can read. High priority first (bars, clubs, theatres, breweries), "
             "then other downtown event places (galleries, bookstores, arts spaces). Within each group, the likeliest "
             "event hosts come first, then the closest to 9th and Broadway.")
    L.append("")
    for i, v in enumerate(down, 1):
        L.append(f"{i}. **{clean(v['name'])}**, {clean(v['address']) or 'address not in OSM'}. "
                 f"{CAT_LABEL[v['category']].capitalize()}, {v['zone']}, {v['priority']} priority, "
                 f"{int(v['dist_km'] * 1000)} m from 9th and Broadway.")
        L.append(f"   Website: {v['website'] or 'none listed'}. Online check: {clean(v.get('method')) or 'not checked'}"
                 + (f" ({clean(v.get('endpoint'))})" if v.get("endpoint") and v.get("method", "").startswith("Ticket") else "") + ".")
        L.append(f"   Ask: {suggested_ask(v)}")
    if table_only:
        L.append("")
        L.append("Also worth a stop: these are in `feed/venues.json` but have no events in the feed right now.")
        L.append("")
        for v in sorted(table_only, key=lambda v: v["dist_km"]):
            L.append(f"- {clean(v['name'])} ({CAT_LABEL[v['category']]}, {clean(v['address']) or 'no address'}, "
                     f"{int(v['dist_km'] * 1000)} m from 9th and Broadway)")
    L.append("")

    walk = [v for v in down if v["dist_km"] <= DOWNTOWN_KM] + [v for v in table_only if v["dist_km"] <= DOWNTOWN_KM]
    if walk:
        order, total = route(walk)
        L.append("### Walking route")
        L.append("")
        L.append(f"Start at 9th and Broadway. {len(order)} stops, about {total:.1f} km, roughly "
                 f"{round(total * 1000 / 80 / 5) * 5 or 5} minutes of walking plus time at each stop. "
                 "Go late afternoon, when managers are in and it is not busy yet.")
        L.append("")
        prev = DOWNTOWN
        for i, v in enumerate(order, 1):
            step = km(prev, (v["lat"], v["lon"])) * 1000
            L.append(f"{i}. {clean(v['name'])}, {clean(v['address']) or 'see map'} ({int(round(step, -1))} m)")
            prev = (v["lat"], v["lon"])
        L.append("")

    L.append("## Visit later – rest of Columbia")
    L.append("")
    L.append("| Venue | Type | Priority | Address | Website | Online check |")
    L.append("|---|---|---|---|---|---|")
    for v in later:
        L.append(f"| {clean(v['name'])} | {CAT_LABEL[v['category']]} | {v['priority']} | {clean(v['address'])} | "
                 f"{v['website']} | {clean(v.get('method')) or 'not checked'} |")
    L.append("")
    L.append("Full data, including covered venues: `Marketing/venue-gaps.csv`.")
    L.append("")
    text = "\n".join(L).replace("\u2014", ", ")
    with open(OUT_MD, "w") as f:
        f.write(text)
    return auto, down, later


# ----------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="refetch OSM and websites")
    ap.add_argument("--max-sites", type=int, default=80)
    args = ap.parse_args()

    cov = covered_venues()
    log(f"covered venue strings: {sum(1 for c in cov if c['kind'] == 'events')} from events, "
        f"{sum(1 for c in cov if c['kind'] == 'table')} from venues.json")

    venues = osm_venues(fetch_osm(args.refresh))
    log(f"OSM venues: {len(venues)}")
    for v in venues:
        v["covered"], v["matched"] = coverage(v, cov)
        v["zone"] = zone(v)
        v["priority"] = priority(v)

    unc = [v for v in venues if v["covered"] == "no"]
    fill_addresses([v for v in venues if v["covered"] != "yes" and v["priority"] != "low"], args.refresh)

    site_cache = (None if args.refresh else load_cache("sites.json", 7)) or {}
    # uncovered first, then venues that are in venues.json but have no events in the feed
    to_check = sorted([v for v in venues if v["covered"] != "yes" and v["website"]],
                      key=lambda v: (v["covered"] != "no", {"high": 0, "medium": 1, "low": 2}[v["priority"]], v["dist_km"]))
    checked = 0
    for v in to_check:
        key = v["website"]
        if key not in site_cache or site_cache[key]["method"] in ("site unreachable", "check failed"):
            if checked >= args.max_sites:
                continue
            log(f"  [{checked + 1}] {v['name']}: {key}")
            try:
                site_cache[key] = classify_site(key)
            except Exception as e:
                site_cache[key] = {"method": "check failed", "endpoint": "", "detail": type(e).__name__, "platform": ""}
            checked += 1
            save_cache("sites.json", site_cache)
        v.update({k: site_cache[key][k] for k in ("method", "endpoint", "detail", "platform")})
    for v in unc:
        if not v["website"]:
            v.setdefault("method", "no website in OSM")
            v.setdefault("endpoint", "")

    stats = {"osm": len(venues), "yes": sum(v["covered"] == "yes" for v in venues),
             "table": sum(v["covered"] == "table-only" for v in venues), "no": len(unc),
             "no_high": sum(v["priority"] == "high" for v in unc), "no_med": sum(v["priority"] == "medium" for v in unc),
             "no_low": sum(v["priority"] == "low" for v in unc),
             "with_site": sum(1 for v in unc if v["website"]),
             "mu_rooms": sum(1 for v in venues if v["matched"] == "Mizzou calendar (campus room)"),
             "table_checked": sum(1 for v in venues if v["covered"] == "table-only" and v["website"] in site_cache),
             "checked": sum(1 for v in unc if v["website"] and v["website"] in site_cache)}
    auto, down, later = write_outputs(venues, stats)
    log(json.dumps(stats))
    log(f"auto: {len(auto)}  downtown visits: {len(down)}  later: {len(later)}")
    log(f"wrote {OUT_MD} and {OUT_CSV}")


if __name__ == "__main__":
    main()
