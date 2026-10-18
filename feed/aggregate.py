#!/usr/bin/env python3
"""CoMo Events feed builder.

Pulls public event listings for Columbia, Missouri from several sources,
normalizes them, geocodes venues, de-duplicates, and writes events.json.

Sources (all public, no login):
  mizzou        calendar.missouri.edu  (LiveWhale JSON + RSS with coordinates)
  visitcolumbia visitcolumbiamo.com    (WordPress REST + event page for address)
  eventbrite    eventbrite.com         (listing page server data)
  allevents     allevents.in           (listing JSON-LD; mirrors public Facebook events)
  baselocal     baselocal.com          (listing JSON-LD)
  bluenote      thebluenote.com / rosemusichall.com (calendar cards + event pages)
  dbrl          events.dbrl.org        (Communico JSON)

Usage:  python3 aggregate.py [--out events.json] [--max-geocode 80] [--days 90]
"""
import argparse, datetime as dt, hashlib, html, json, os, re, sys, time
from zoneinfo import ZoneInfo
import requests

HERE = os.path.dirname(os.path.abspath(__file__))
TZ = ZoneInfo("America/Chicago")
UA = "CoMoEvents/0.1 (community events app prototype; ajay.kumar@missouri.edu)"
BROWSER_UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              "(KHTML, like Gecko) Chrome/130 Safari/537.36")
DOWNTOWN = (38.9517, -92.3341)   # 9th & Broadway
RADIUS_KM = 25.0

S = requests.Session()
S.headers["User-Agent"] = BROWSER_UA

# ----------------------------------------------------------------- helpers
def log(*a):
    print(*a, file=sys.stderr, flush=True)

def get(url, **kw):
    kw.setdefault("timeout", 30)
    r = S.get(url, **kw)
    r.raise_for_status()
    return r

def strip_html(s, limit=500):
    if not s:
        return ""
    s = re.sub(r"<(script|style).*?</\1>", "", s, flags=re.S)
    s = re.sub(r"<br\s*/?>|</p>|</div>|</li>", "\n", s, flags=re.I)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"[ \t]+", " ", s)
    s = re.sub(r"\s*\n\s*", "\n", s).strip()
    if len(s) > limit:
        s = s[:limit].rsplit(" ", 1)[0] + "…"
    return s

def clean_title(s):
    s = html.unescape(s or "").strip()
    return re.sub(r"\s+", " ", s)

def iso(d):
    return d.astimezone(TZ).isoformat(timespec="seconds")

def parse_dt(s):
    """Parse an ISO-ish string into an aware datetime (Chicago if naive)."""
    if not s:
        return None
    s = s.strip().replace("Z", "+00:00")
    try:
        d = dt.datetime.fromisoformat(s)
    except ValueError:
        return None
    if d.tzinfo is None:
        d = d.replace(tzinfo=TZ)
    return d

def haversine_km(a, b):
    import math
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = math.sin((la2-la1)/2)**2 + math.cos(la1)*math.cos(la2)*math.sin((lo2-lo1)/2)**2
    return 6371 * 2 * math.asin(math.sqrt(h))

def norm_key(s):
    s = html.unescape(s or "").lower()
    s = re.sub(r"\b(the|a|an|at|with|and|&|live|presents?)\b", " ", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    return " ".join(s.split())

PHONE_RE = re.compile(r"(?:\+1[\s.-]?)?\(?(\d{3})\)?[\s.-]?(\d{3})[\s.-]?(\d{4})\b")
def find_phone(text):
    m = PHONE_RE.search(text or "")
    return f"({m.group(1)}) {m.group(2)}-{m.group(3)}" if m else None

def ld_events(html_text):
    out = []
    for b in re.findall(r"<script[^>]*application/ld\+json[^>]*>(.*?)</script>", html_text, re.S):
        try:
            d = json.loads(b)
        except Exception:
            continue
        stack = [d]
        while stack:
            x = stack.pop()
            if isinstance(x, dict):
                t = x.get("@type")
                if (isinstance(t, str) and t.endswith("Event")) or (isinstance(t, list) and "Event" in t):
                    out.append(x)
                stack.extend(x.values())
            elif isinstance(x, list):
                stack.extend(x)
    return out

# ----------------------------------------------------------------- caches
def load_json(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return default

def save_json(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, indent=1, ensure_ascii=False, sort_keys=True)
    os.replace(tmp, path)

GEOCACHE_PATH = os.path.join(HERE, "cache", "geocode.json")
PAGECACHE_PATH = os.path.join(HERE, "cache", "pages.json")
os.makedirs(os.path.join(HERE, "cache"), exist_ok=True)
GEOCACHE = load_json(GEOCACHE_PATH, {})
PAGECACHE = load_json(PAGECACHE_PATH, {})
VENUES = load_json(os.path.join(HERE, "venues.json"), {})

def cached_page(url, max_age_days=14):
    ent = PAGECACHE.get(url)
    now = time.time()
    if ent and now - ent.get("t", 0) < max_age_days * 86400:
        return ent.get("body", "")
    try:
        body = get(url).text
    except Exception as e:
        log("  page fetch failed", url, e)
        body = ""
    PAGECACHE[url] = {"t": now, "body": body[:200000]}
    return body

# ----------------------------------------------------------------- geocoding
GEOCODE_BUDGET = {"n": 80}
LAST_NOMINATIM = [0.0]

def nominatim(q):
    if GEOCODE_BUDGET["n"] <= 0:
        return None
    wait = 1.1 - (time.time() - LAST_NOMINATIM[0])
    if wait > 0:
        time.sleep(wait)
    LAST_NOMINATIM[0] = time.time()
    GEOCODE_BUDGET["n"] -= 1
    try:
        r = requests.get("https://nominatim.openstreetmap.org/search",
                         params={"q": q, "format": "json", "limit": 1,
                                 "viewbox": "-92.55,39.10,-92.10,38.80", "bounded": 1},
                         headers={"User-Agent": UA}, timeout=20)
        r.raise_for_status()
        js = r.json()
    except Exception as e:
        log("  nominatim error", q, e)
        return None
    if not js:
        return None
    poi = js[0].get("addresstype") not in ("house", "building", "road", "residential", "postcode", "city", "town", "suburb", "neighbourhood")
    return {"lat": float(js[0]["lat"]), "lng": float(js[0]["lon"]),
            "name": (js[0].get("name") or None) if poi else None}

def venue_lookup(name):
    """Known venue table: exact or alias match, case-insensitive substring."""
    if not name:
        return None
    n = name.lower().strip()
    for key, v in VENUES.items():
        names = [key.lower()] + [a.lower() for a in v.get("aliases", [])]
        for cand in names:
            if n == cand or (len(cand) >= 6 and cand in n):
                return dict(v, canonical=key)
    return None

def geocode(venue, address):
    """Return (lat, lng, resolved_venue_name, resolved_address) or None."""
    v = venue_lookup(venue) or venue_lookup(address)
    if v and "lat" in v:
        return v["lat"], v["lng"], v.get("canonical") or venue, v.get("address") or address
    queries = []
    if address and re.search(r"\d", address):
        a = address if re.search(r"\bMO\b|Missouri|Columbia", address, re.I) else address + ", Columbia, MO"
        queries.append(a)
    if venue and venue.lower() not in ("columbia", "columbia, mo", "tbd", "tba", "online"):
        queries.append(f"{venue}, Columbia, MO")
    if v and v.get("address"):
        queries.insert(0, v["address"] + ", Columbia, MO")
    for q in queries:
        key = q.lower()
        if key in GEOCACHE:
            hit = GEOCACHE[key]
        else:
            hit = nominatim(q)
            if hit is None and GEOCODE_BUDGET["n"] <= 0:
                continue   # budget exhausted: don't cache a negative
            GEOCACHE[key] = hit
        if hit:
            return hit["lat"], hit["lng"], venue or hit.get("name"), address or (v or {}).get("address")
    return None

# ----------------------------------------------------------------- event record
def make_event(source, source_name, sid, title, start, end=None, all_day=False, time_tbd=False,
               venue=None, address=None, lat=None, lng=None, url=None, ticket_url=None,
               phone=None, price=None, category=None, image=None, description=None, organizer=None):
    if not title or not start:
        return None
    eid = hashlib.sha1(f"{source}:{sid}".encode()).hexdigest()[:16]
    return {
        "id": eid, "source": source, "sourceName": source_name,
        "title": clean_title(title)[:160],
        "start": iso(start), "end": iso(end) if end else None,
        "allDay": bool(all_day), "timeTBD": bool(time_tbd),
        "venue": (venue or "").strip()[:120] or None,
        "address": (address or "").strip()[:160] or None,
        "lat": lat, "lng": lng,
        "url": url, "ticketUrl": ticket_url, "phone": phone, "price": price,
        "category": category or "community", "imageUrl": image,
        "description": strip_html(description, 600) if description else None,
        "organizer": organizer,
    }

CATEGORY_RULES = [
    ("sports", r"\b(football|basketball|volleyball|soccer|softball|baseball|wrestling|gymnastics|golf|tennis|swim|track|5k|10k|marathon|run\b|race|tigers? vs|vs\.?)\b"),
    ("music", r"\b(concert|live music|band|orchestra|symphony|choir|dj|jazz|tribute|tour|album|singer|acoustic|open mic|karaoke)\b"),
    ("nightlife", r"\b(bar|brewery|trivia|dance party|night out|21\+|18\+|pub crawl|happy hour)\b"),
    ("arts", r"\b(theatre|theater|gallery|art|museum|film|movie|comedy|improv|dance|ballet|opera|poetry|exhibit|craft)\b"),
    ("family", r"\b(kids|family|children|toddler|story ?time|teen|youth|trick.or.treat|trunk.or.treat|pumpkin|sensory)\b"),
    ("food", r"\b(food|brunch|dinner|tasting|wine|beer|coffee|cook|farmers? market|market|bbq|taco|festival of|oktoberfest)\b"),
    ("campus", r"\b(lecture|seminar|workshop|colloquium|symposium|webinar|career|research|class|course|registration|deadline|study|exam|student)\b"),
]
def infer_category(title, desc="", default="community"):
    """Keyword categoriser. default=None returns None when nothing matches."""
    t = f"{title} {desc or ''}".lower()
    for cat, rx in CATEGORY_RULES:
        if re.search(rx, t):
            return cat
    return default

# ----------------------------------------------------------------- sources
def src_mizzou(days):
    """LiveWhale JSON (dates, cost) joined with RSS (coordinates, image, categories)."""
    out = []
    rss = {}
    try:
        x = get("https://calendar.missouri.edu/live/rss/events").text
        for it in re.findall(r"<item>(.*?)</item>", x, re.S):
            lid = re.search(r"<livewhale:id>(\d+)</livewhale:id>", it)
            if not lid:
                continue
            pt = re.search(r"<georss:point>([-\d.]+)\s+([-\d.]+)</georss:point>", it)
            fn = re.search(r"<georss:featurename>(.*?)</georss:featurename>", it, re.S)
            img = re.search(r"<livewhale:image>(.*?)</livewhale:image>", it)
            cats = re.search(r"<livewhale:categories>(.*?)</livewhale:categories>", it)
            desc = re.search(r"<description><!\[CDATA\[(.*?)\]\]></description>", it, re.S)
            ends = re.search(r"<livewhale:ends>(.*?)</livewhale:ends>", it)
            rss[lid.group(1)] = {
                "lat": float(pt.group(1)) if pt else None, "lng": float(pt.group(2)) if pt else None,
                "venue": html.unescape(fn.group(1)).strip() if fn else None,
                "image": img.group(1) if img and "localistImg" not in img.group(1) else None,
                "cats": html.unescape(cats.group(1)) if cats else "",
                "desc": desc.group(1) if desc else "",
                "ends": ends.group(1) if ends else None,
            }
    except Exception as e:
        log("  mizzou rss failed:", e)
    horizon = dt.datetime.now(TZ) + dt.timedelta(days=days)
    for page in range(1, 12):
        try:
            js = get(f"https://calendar.missouri.edu/live/json/events?page={page}").json()
        except Exception as e:
            log("  mizzou json page", page, "failed:", e); break
        data = js.get("data", [])
        if not data:
            break
        for it in data:
            if it.get("is_canceled") or it.get("is_online"):
                continue
            start = parse_dt(it.get("date_utc", "").replace(" ", "T") + "+00:00") if it.get("date_utc") else None
            end = parse_dt(it.get("date2_utc", "").replace(" ", "T") + "+00:00") if it.get("date2_utc") else None
            if not start:
                continue
            lid = str(it.get("id"))
            r = rss.get(lid, {})
            title = clean_title(it.get("title"))
            group = (it.get("url") or "").split("calendar.missouri.edu/")[-1].split("/")[0].replace("_", " ").replace("-", " ")
            if group == "academic calendar" or re.search(r"\b(due|deadline|applications? (open|close)|last day to)\b", title, re.I):
                continue   # deadlines, not events people go to
            venue_name = (rss.get(str(it.get("id")), {}).get("venue") or "").strip()
            if re.match(r"^(virtual|online|hybrid|zoom|tbd|tba|varies|various)\b", venue_name, re.I) or "St Louis" in venue_name or "Kansas City" in venue_name:
                continue
            cat = "sports" if group == "athletics" else infer_category(title, r.get("cats", ""), "campus")
            if group == "athletics" and " at " in title and "vs" not in title.lower():
                continue   # "Missouri at X" = away game, not in Columbia
            cost = str(it.get("cost") or "").strip() or None
            out.append(make_event("mizzou", "Mizzou Calendar", lid, title, start, end,
                                  all_day=bool(it.get("is_all_day")),
                                  venue=r.get("venue"), lat=r.get("lat"), lng=r.get("lng"),
                                  url=it.get("url"), price=cost, category=cat,
                                  image=r.get("image"), description=r.get("desc"),
                                  organizer=group.title() if group else "University of Missouri"))
        last = parse_dt(data[-1].get("date_utc", "").replace(" ", "T") + "+00:00")
        if last and last > horizon:
            break
    return out

VISIT_CATS = {239: "arts", 244: "arts", 240: "arts", 241: "campus", 234: "family", 235: "community",
              233: "arts", 228: "food", 238: "community", 301: "community", 327: "community",
              229: "family", 230: "music", 232: "nightlife", 236: "community", 231: "arts",
              237: "community", 243: "sports"}
def src_visitcolumbia(days):
    out = []
    today = dt.datetime.now(TZ).strftime("%Y%m%d")
    horizon = (dt.datetime.now(TZ) + dt.timedelta(days=days)).strftime("%Y%m%d")
    items = []
    for page in (1, 2, 3):
        try:
            r = get(f"https://www.visitcolumbiamo.com/wp-json/wp/v2/event?per_page=100&page={page}&orderby=modified&order=desc")
        except Exception as e:
            log("  visitcolumbia page", page, "failed:", e); break
        js = r.json()
        if not js:
            break
        items += js
        if len(js) < 100:
            break
    for it in items:
        acf = it.get("acf") or {}
        sd, ed = acf.get("start_date") or "", acf.get("end_date") or sd
        if not sd or ed < today or sd > horizon:
            continue
        st, et = acf.get("start_time") or "", acf.get("end_time") or ""
        start = parse_dt(f"{sd[:4]}-{sd[4:6]}-{sd[6:]}T{st or '00:00:00'}")
        end = parse_dt(f"{ed[:4]}-{ed[4:6]}-{ed[6:]}T{et}") if et else None
        link = it.get("link")
        page = cached_page(link) if link else ""
        m = re.search(r'google\.com/maps/dir/([^"\'<>]+)', page)
        address = html.unescape(requests.utils.unquote(m.group(1)).replace("+", " ")) if m else None
        # venue: text right after "Location" / "Venue" heading, else from title " at X"
        venue = None
        mv = re.search(r'<h[2-6][^>]*>\s*(?:Location|Venue|Where)\s*</h[2-6]>\s*(?:<[^>]+>\s*)*([^<]{3,80})', page, re.I)
        if mv:
            venue = html.unescape(mv.group(1)).strip()
        ttl = clean_title(it["title"]["rendered"])
        if not venue:
            mt = re.search(r"\s(?:at|@)\s+([A-Z][^|:\-–]{2,60})$", ttl) or re.search(r"\s[–\-|]\s+([A-Z][^|:\-–]{2,60})$", ttl)
            venue = mt.group(1).strip() if mt else None
        if venue and re.match(r"^(columbia|downtown columbia)\b", venue, re.I):
            venue = None
        vcats = [VISIT_CATS.get(c) for c in it.get("event-category", []) if VISIT_CATS.get(c)]
        if "sports" in vcats:
            cat = "sports"
        else:
            guess = infer_category(ttl, "", None)
            cat = guess or (vcats[0] if vcats else infer_category(ttl, it.get("content", {}).get("rendered", "")))
        img = None
        yj = it.get("yoast_head_json") or {}
        if yj.get("og_image"):
            img = yj["og_image"][0].get("url")
        out.append(make_event("visitcolumbia", "Visit Columbia", it["id"], ttl, start, end,
                              all_day=not st, time_tbd=not st, venue=venue, address=address, url=link,
                              price="Free" if 242 in it.get("event-category", []) else None,
                              category=cat, image=img, description=it.get("content", {}).get("rendered"),
                              phone=find_phone(strip_html(page, 100000) if page else "")))
    return out

def src_eventbrite(days):
    out = []
    seen = set()
    for page in (1, 2, 3):
        try:
            h = get(f"https://www.eventbrite.com/d/mo--columbia/all-events/?page={page}").text
        except Exception as e:
            log("  eventbrite page", page, "failed:", e); break
        m = re.search(r"window\.__SERVER_DATA__\s*=\s*(\{.*?\});\s*\n", h, re.S)
        events = []
        if m:
            try:
                d = json.loads(m.group(1))
                stack = [d]
                while stack:
                    x = stack.pop()
                    if isinstance(x, dict):
                        if "start_date" in x and "name" in x and "url" in x:
                            events.append(x)
                        else:
                            stack.extend(x.values())
                    elif isinstance(x, list):
                        stack.extend(x)
            except Exception as e:
                log("  eventbrite server data parse failed:", e)
        for e in events:
            if e.get("url") in seen or e.get("is_online_event"):
                continue
            seen.add(e.get("url"))
            pv = e.get("primary_venue") or {}
            addr = pv.get("address") or {}
            city = (addr.get("city") or "").lower()
            if city and city != "columbia":
                continue
            start = parse_dt(f"{e['start_date']}T{e.get('start_time') or '00:00'}")
            end = parse_dt(f"{e.get('end_date') or e['start_date']}T{e.get('end_time')}") if e.get("end_time") else None
            lat = float(addr["latitude"]) if addr.get("latitude") else None
            lng = float(addr["longitude"]) if addr.get("longitude") else None
            img = ((e.get("image") or {}).get("url"))
            price = None
            ta = e.get("ticket_availability") or {}
            if ta.get("is_free"):
                price = "Free"
            elif ta.get("minimum_ticket_price", {}).get("display"):
                price = "From " + ta["minimum_ticket_price"]["display"]
            out.append(make_event("eventbrite", "Eventbrite", e.get("id") or e["url"], e["name"], start, end,
                                  time_tbd=not e.get("start_time"), venue=pv.get("name"),
                                  address=addr.get("localized_address_display"), lat=lat, lng=lng,
                                  url=e["url"], ticket_url=e["url"], price=price,
                                  category=infer_category(e["name"], e.get("summary", "")),
                                  image=img, description=e.get("summary")))
    return out

def src_allevents(days):
    out = []
    seen = set()
    for page in (1, 2, 3, 4):
        try:
            h = get(f"https://allevents.in/columbia-mo/all?page={page}").text
        except Exception as e:
            log("  allevents page", page, "failed:", e); break
        evs = ld_events(h)
        if not evs:
            break
        for e in evs:
            url = e.get("url")
            if not url or url in seen:
                continue
            seen.add(url)
            loc = e.get("location") if isinstance(e.get("location"), dict) else {}
            addr = loc.get("address") if isinstance(loc.get("address"), dict) else {}
            if (addr.get("addressLocality") or "").lower() not in ("columbia", ""):
                continue
            # time from the card text: "Sat, 24 Oct, 2026 - 09:00 AM"
            i = h.find(url)
            seg = strip_html(h[max(0, i-1500):i+2500], 100000) if i >= 0 else ""
            mt = re.search(r"\b\d{1,2}\s+[A-Z][a-z]{2},?\s+\d{4}\s*-\s*(\d{1,2}:\d{2}\s*[AP]M)", seg)
            sd = (e.get("startDate") or "")[:10]
            if not sd:
                continue
            if mt:
                t = dt.datetime.strptime(mt.group(1).replace(" ", ""), "%I:%M%p").time()
                start = dt.datetime.combine(dt.date.fromisoformat(sd), t, TZ)
                tbd = False
            else:
                start = parse_dt(e.get("startDate")) if "T" in (e.get("startDate") or "") else dt.datetime.combine(dt.date.fromisoformat(sd), dt.time(0, 0), TZ)
                tbd = "T" not in (e.get("startDate") or "")
            geo = loc.get("geo") or {}
            lat = float(geo["latitude"]) if geo.get("latitude") else None
            lng = float(geo["longitude"]) if geo.get("longitude") else None
            vname = loc.get("name") or ""
            if re.match(r"^\d", vname):      # name is really an address
                vname = ""
            address = addr.get("streetAddress") or (loc.get("name") if re.match(r"^\d", loc.get("name") or "") else None)
            img = e.get("image") if isinstance(e.get("image"), str) else (e.get("image") or [None])[0] if isinstance(e.get("image"), list) else None
            out.append(make_event("allevents", "AllEvents (Facebook & more)", url, e.get("name"), start,
                                  time_tbd=tbd, venue=vname or None, address=address, lat=lat, lng=lng,
                                  url=url, category=infer_category(e.get("name"), e.get("description", "")),
                                  image=img, description=e.get("description")))
    return out

def src_baselocal(days):
    out = []
    try:
        h = get("https://baselocal.com/mo/columbia/events/").text
    except Exception as e:
        log("  baselocal failed:", e); return out
    for e in ld_events(h):
        loc = e.get("location") if isinstance(e.get("location"), dict) else {}
        addr = loc.get("address") if isinstance(loc.get("address"), dict) else {}
        if (addr.get("addressLocality") or "Columbia").lower() != "columbia":
            continue
        start = parse_dt(e.get("startDate"))
        if not start:
            continue
        end = parse_dt(e.get("endDate"))
        offers = e.get("offers") or {}
        price = None
        if isinstance(offers, dict):
            p = offers.get("price")
            if p is not None:
                price = "Free" if str(p) in ("0", "0.0", "0.00") else f"${p}"
        url = e.get("url") or ""
        ext = None
        if "baselocal.com" in url:
            # the card links out somewhere; try to find an external link near the card
            i = h.find(url.split("#")[-1])
            m = re.search(r'href="(https?://(?!baselocal\.com)[^"]+)"', h[i:i+4000]) if i >= 0 else None
            ext = m.group(1) if m else None
        out.append(make_event("baselocal", "Base Local", url, e.get("name"), start, end,
                              venue=loc.get("name"), address=addr.get("streetAddress"),
                              url=ext or url, price=price,
                              category=infer_category(e.get("name"), e.get("description", "")),
                              image=e.get("image") if isinstance(e.get("image"), str) else None,
                              description=e.get("description"), organizer=(e.get("organizer") or {}).get("name") if isinstance(e.get("organizer"), dict) else None))
    return out

def src_bluenote(days):
    out = []
    for site, name, phone in (("https://thebluenote.com", "The Blue Note", "(573) 874-1944"),
                              ("https://rosemusichall.com", "Rose Music Hall", "(573) 874-1944")):
        try:
            h = get(site + "/calendar/").text
        except Exception as e:
            log("  bluenote calendar failed:", site, e); continue
        seen = set()
        for m in re.finditer(r'href="(%s/event/[^"]+)"' % re.escape(site), h):
            url = m.group(1)
            if url in seen:
                continue
            seen.add(url)
            i = m.end()
            card = h[i:i+6000]
            def field(cls):
                mm = re.search(r'class="event-%s"[^>]*>\s*(.*?)\s*</div>' % cls, card, re.S)
                return strip_html(mm.group(1), 300) if mm else None
            title, venue, date, acts, pres = field("title"), field("venue"), field("date"), field("supporting-acts"), field("presented-by")
            if not title or not date:
                continue
            try:
                day = dt.datetime.strptime(date.strip(), "%B %d, %Y").date()
            except ValueError:
                continue
            page = cached_page(url)
            text = strip_html(page, 100000)
            mt = re.search(r"(?:Show|Starts|Showtime)[:\s]*(\d{1,2}(?::\d{2})?\s*[ap]m)", text, re.I) or \
                 re.search(r"Doors(?: Open)?[:\s]*(\d{1,2}(?::\d{2})?\s*[ap]m)", text, re.I)
            tbd = mt is None
            if mt:
                ts = mt.group(1).lower().replace(" ", "")
                fmt = "%I:%M%p" if ":" in ts else "%I%p"
                t = dt.datetime.strptime(ts, fmt).time()
            else:
                t = dt.time(19, 0)
            start = dt.datetime.combine(day, t, TZ)
            tk = re.search(r'href="(https?://(?:www\.)?(?:ticketmaster|etix|seetickets|ticketweb|eventbrite|dice|tixr|axs)\.[^"]+)"', card + page)
            pr = re.search(r"\$\s?\d{1,3}(?:\.\d{2})?(?:\s*[-–]\s*\$?\s?\d{1,3}(?:\.\d{2})?)?", text)
            img = re.search(r'<img[^>]+src="([^"]+wp-content/uploads[^"]+)"', h[max(0, i-3000):i+3000])
            desc = " · ".join(x for x in (pres, acts) if x)
            out.append(make_event("bluenote", name, url, title, start, time_tbd=tbd,
                                  venue=venue or name, url=url, ticket_url=tk.group(1) if tk else url,
                                  phone=phone, price=pr.group(0) if pr else None,
                                  category="music" if "comedy" not in (title + desc).lower() else "arts",
                                  image=img.group(1) if img else None, description=desc or None,
                                  organizer=pres))
    return out

def src_dbrl(days):
    out = []
    req = json.dumps({"private": False, "date": dt.datetime.now(TZ).strftime("%Y-%m-%d"),
                      "days": min(days, 60), "locations": [], "ages": [], "types": []})
    try:
        js = get("https://events.dbrl.org/eeventcaldata", params={"event_type": 0, "req": req},
                 headers={"Accept": "application/json"}).json()
    except Exception as e:
        log("  dbrl failed:", e); return out
    for it in js:
        loc = (it.get("location") or "").strip()
        if loc in ("Callaway County Public Library", "Holts Summit Public Library", "Southern Boone County Public Library"):
            continue
        if re.search(r"\b(Sturgeon|Hallsville|Harrisburg|Rocheport|Centralia|Ashland|Fulton|Holts Summit|online)\b", f"{loc} {it.get('venue_description') or ''}", re.I):
            continue
        if str(it.get("private_event")) in ("1", "True", "true") or str(it.get("venue_type", "")).lower() == "online":
            continue
        start = parse_dt(it.get("event_start", "").replace(" ", "T"))
        end = parse_dt(it.get("event_end", "").replace(" ", "T"))
        img = it.get("image")
        img_url = f"https://d4804za1f1gw.cloudfront.net/wp-content/uploads/sites/{img}" if False else None
        price = "Free"
        if it.get("registration_cost") and str(it["registration_cost"]) not in ("0", "0.00", "", "None"):
            price = f"${it['registration_cost']}"
        title = clean_title(it.get("title"))
        cat = infer_category(title, it.get("description", ""), "family" if re.search(r"Babies|Toddlers|Preschool|School-Age", it.get("ages") or "") else "community")
        out.append(make_event("dbrl", "Daniel Boone Regional Library", it.get("id"), title, start, end,
                              venue=loc + (f" · {it['venue_room']}" if it.get("venue_room") else ""),
                              url=it.get("url") or f"https://events.dbrl.org/event/{it.get('id')}",
                              price=price, category=cat, image=img_url,
                              description=it.get("description") or it.get("long_description"),
                              organizer="Daniel Boone Regional Library",
                              phone="(573) 443-3161" if loc.startswith("Columbia Public") else None))
    return out

SOURCES = [src_mizzou, src_visitcolumbia, src_eventbrite, src_allevents, src_baselocal, src_bluenote, src_dbrl]

# ----------------------------------------------------------------- merge
def dedupe(events):
    """Merge events with the same normalized title on the same local date."""
    by_key = {}
    order = []
    for e in events:
        nk = norm_key(e["title"])
        key = (nk[:40], e["start"][:10])
        if key not in by_key:
            # same day, one title contains the other (e.g. "Hexagon Alley Presents X" vs "X")
            match = None
            for k2 in order:
                if k2[1] != key[1]:
                    continue
                other = norm_key(by_key[k2]["title"])
                short, long_ = sorted((nk, other), key=len)
                if len(short) >= 12 and short in long_:
                    match = k2; break
            if match is None:
                by_key[key] = e
                order.append(key)
                e["alsoOn"] = []
                continue
            key = match
        a = by_key[key]
        # prefer the record with coordinates, then an exact time, then richer text
        def score(x):
            return (x["lat"] is not None, not x["timeTBD"], bool(x.get("description")), bool(x.get("imageUrl")))
        keep, drop = (a, e) if score(a) >= score(e) else (e, a)
        for k in ("lat", "lng", "venue", "address", "phone", "price", "imageUrl", "description", "ticketUrl", "end"):
            if keep.get(k) in (None, "") and drop.get(k):
                keep[k] = drop[k]
        if keep["timeTBD"] and not drop["timeTBD"]:
            keep["start"], keep["timeTBD"], keep["allDay"] = drop["start"], False, drop["allDay"]
        keep["alsoOn"] = list({*(a.get("alsoOn") or []), *(e.get("alsoOn") or []),
                               *( [drop["url"]] if drop.get("url") and drop["url"] != keep.get("url") else [] )})
        keep["id"] = a["id"]
        by_key[key] = keep
    return [by_key[k] for k in order]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(HERE, "events.json"))
    ap.add_argument("--days", type=int, default=90)
    ap.add_argument("--max-geocode", type=int, default=80)
    ap.add_argument("--only", help="comma list of sources to run")
    args = ap.parse_args()
    GEOCODE_BUDGET["n"] = args.max_geocode

    now = dt.datetime.now(TZ)
    lo = (now - dt.timedelta(hours=6))
    hi = now + dt.timedelta(days=args.days)
    # Previous feed: if a source fails or returns nothing (site down, bot block on the
    # CI runner, parser broken), keep its last known events instead of dropping them.
    previous = load_json(args.out, {}).get("events", [])
    prev_by_source = {}
    for e in previous:
        prev_by_source.setdefault(e.get("source"), []).append(e)

    all_events = []
    stats = {}
    for fn in SOURCES:
        name = fn.__name__[4:]
        if args.only and name not in args.only.split(","):
            evs = prev_by_source.get(name, [])
            log(f"[{name}] skipped (--only); carrying {len(evs)} events forward")
            all_events += evs
            continue
        t0 = time.time()
        try:
            evs = [e for e in fn(args.days) if e]
        except Exception as e:
            log(f"[{name}] FAILED: {e}")
            evs = []
        if not evs and prev_by_source.get(name):
            evs = prev_by_source[name]
            log(f"[{name}] returned nothing; carrying {len(evs)} previous events forward")
            stats[name] = {"carriedForward": len(evs)}
        else:
            stats[name] = len(evs)
        log(f"[{name}] {len(evs)} events in {time.time()-t0:.1f}s")
        all_events += evs

    # window + geocode + radius
    kept = []
    for e in all_events:
        st = parse_dt(e["start"])
        en = parse_dt(e["end"]) if e.get("end") else None
        if (en or st) < lo or st > hi:
            continue
        if e.get("venue") and re.match(r"^columbia(,| mo| misso?urr?i|$)", e["venue"].strip(), re.I):
            e["venue"] = None
        known = venue_lookup(e.get("venue"))
        if known and "lat" in known and e["source"] in ("allevents", "visitcolumbia", "baselocal", "dbrl"):
            e["lat"], e["lng"] = known["lat"], known["lng"]
            e["address"] = e.get("address") or known.get("address")
            e["phone"] = e.get("phone") or known.get("phone")
        if e["lat"] is None and (e.get("venue") or e.get("address")):
            g = geocode(e.get("venue"), e.get("address"))
            if g:
                e["lat"], e["lng"], v, a = g
                e["venue"] = e.get("venue") or v
                e["address"] = e.get("address") or a
        if e["lat"] is not None and haversine_km((e["lat"], e["lng"]), DOWNTOWN) > RADIUS_KM:
            continue
        kept.append(e)
    save_json(GEOCACHE_PATH, GEOCACHE)
    save_json(PAGECACHE_PATH, PAGECACHE)

    merged = dedupe(kept)
    merged.sort(key=lambda e: e["start"])
    with_geo = sum(1 for e in merged if e["lat"] is not None)
    feed = {
        "generatedAt": now.isoformat(timespec="seconds"),
        "city": "Columbia, MO", "center": {"lat": DOWNTOWN[0], "lng": DOWNTOWN[1]},
        "sources": stats, "count": len(merged), "withCoordinates": with_geo,
        "events": merged,
    }
    with open(args.out, "w") as f:
        json.dump(feed, f, ensure_ascii=False, separators=(",", ":"))
    log(f"wrote {args.out}: {len(merged)} events ({with_geo} with coordinates), geocode budget left {GEOCODE_BUDGET['n']}")

if __name__ == "__main__":
    main()
