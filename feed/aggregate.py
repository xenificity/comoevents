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
FAR_OK_SOURCES = {"lyceum"}   # regional venues the user asked to include despite the distance

S = requests.Session()
S.headers["User-Agent"] = BROWSER_UA

# ----------------------------------------------------------------- helpers
def log(*a):
    print(*a, file=sys.stderr, flush=True)

LAST_HIT = {}
def get(url, **kw):
    """GET with a polite per-host gap and a retry on 429/5xx."""
    kw.setdefault("timeout", 30)
    host = url.split("/")[2]
    gap = 1.5 if "voxmagazine" in host else 0.3
    wait = gap - (time.time() - LAST_HIT.get(host, 0))
    if wait > 0:
        time.sleep(wait)
    for attempt in range(3):
        LAST_HIT[host] = time.time()
        r = S.get(url, **kw)
        if r.status_code in (429, 500, 502, 503, 504) and attempt < 2:
            time.sleep(8 * (attempt + 1))
            continue
        r.raise_for_status()
        return r
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
        "audience": infer_audience(title, strip_html(description, 2000) if description else "", category or "community"),
        "categories": all_categories(title, description, category or "community",
                                     campus_ok=source in ("mizzou", "dbrl")),
    }

def all_categories(title, desc, primary, campus_ok=False):
    """Every category an event belongs to: the primary first, then any other rule that matches the
    title (or the first 200 characters of the description). An event can be music AND nightlife AND food."""
    t = f"{title} {strip_html(desc, 200) if desc else ''}".lower()
    cats = [primary]
    for cat, rx in CATEGORY_RULES:
        if cat in cats or (cat == "campus" and not campus_ok):
            continue
        if re.search(rx, t):
            cats.append(cat)
    return cats[:4]

CATEGORY_RULES = [
    ("party", r"\b((dance|costume|halloween|glow|foam|pool|block|release|launch|watch|viewing|after|pre|birthday|house|toga|darty|frat|white|masquerade|holiday|christmas|nye|new year'?s eve) party|parties|bollywood|desi night|afrobeats?|latin night|salsa night|reggaeton|club night|rave|dj set|djs?|fastpass|fast pass|night ?club|nightclub|silent disco|darty|bash|pregame|after ?party)\b|\bparty\b.*\b(dj|club|21\+|18\+|bar|tickets?|vip|bottle)\b"),
    ("sports", r"\b(football|basketball|volleyball|soccer|softball|baseball|wrestling|gymnastics|golf|tennis|swim|track|5k|10k|marathon|run\b|race|tigers? vs|vs\.?)\b"),
    ("music", r"\b(concert|live music|band|orchestra|symphony|choir|dj|jazz|tribute|tour|album|singer|acoustic|open mic|karaoke)\b"),
    ("nightlife", r"\b(bar|brewery|trivia|dance party|night out|21\+|18\+|pub crawl|happy hour)\b"),
    ("arts", r"\b(theatre|theater|gallery|art|museum|film|movie|comedy|improv|dance|ballet|opera|poetry|exhibit|craft)\b"),
    ("family", r"\b(kids|family|children|toddler|story ?time|teen|youth|trick.or.treat|trunk.or.treat|pumpkin|sensory)\b"),
    ("food", r"\b(food|brunch|dinner|tasting|wine|beer|coffee|cook|farmers? market|market|bbq|taco|festival of|oktoberfest)\b"),
    ("campus", r"\b(lecture|seminar|workshop|colloquium|symposium|webinar|career|research|class|course|registration|deadline|study|exam|student)\b"),
]
AUDIENCE_RULES = {
    "singles": r"\b(singles?|speed dating|mixer|meet ?up|meet new people|networking|social hour|happy hour|open mic|karaoke|trivia|dance party|night out|club night|latin night|salsa|swing dance|comedy|young professionals|newcomers|volunteer)\b",
    "couples": r"\b(date night|couples?|romantic|candlelight|wine|paint (and|&) sip|sip (and|&) paint|dinner|tasting|brunch|sunset|ballet|symphony|orchestra|jazz|theatre|theater|musical|gala|cocktail|chocolate|valentine|anniversary|stargazing|dance lessons?)\b",
    "groups": r"\b(tailgate|watch party|trivia|festival|fest|parade|tournament|game night|board games?|party|bar crawl|pub crawl|brewery|beer|5k|10k|run|race|market|karaoke|bowling|escape room|league|pickup|potluck|block party|homecoming|concert|show|live music|band|dj)\b",
    "family": r"\b(kids?|family|families|children|child|toddlers?|babies|baby|preschool|story ?time|teens?|youth|all ages|trick.or.treat|trunk.or.treat|pumpkin|sensory|petting zoo|craft|lego|puppet|school.age)\b",
}
AUDIENCE_DEFAULT = {
    "party": ["singles", "groups"],
    "music": ["groups", "singles", "couples"], "nightlife": ["singles", "groups"],
    "food": ["couples", "groups"], "family": ["family", "groups"], "sports": ["groups", "family"],
    "arts": ["couples", "singles"], "campus": ["singles", "groups"], "community": ["groups"],
}
def infer_audience(title, desc, category):
    t = f"{title} {desc or ''}".lower()
    tags = [a for a, rx in AUDIENCE_RULES.items() if re.search(rx, t)]
    if "family" in tags and re.search(r"\b(21\+|18\+|bar|brewery|happy hour|cocktail)\b", t):
        tags.remove("family")
    if not tags:
        tags = list(AUDIENCE_DEFAULT.get(category, ["groups"]))
    elif category == "family" and "family" not in tags:
        tags.append("family")
    return tags

def infer_category(title, desc="", default="community", campus_ok=False):
    """Keyword categoriser. default=None returns None when nothing matches.
    The 'campus' guess (lecture, workshop, class...) is only used when campus_ok is set."""
    t = f"{title} {desc or ''}".lower()
    for cat, rx in CATEGORY_RULES:
        if cat == "campus" and not campus_ok:
            continue
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
            cat = "sports" if group == "athletics" else infer_category(title, r.get("cats", ""), "campus", campus_ok=True)
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
        cat = infer_category(title, it.get("description", ""), "family" if re.search(r"Babies|Toddlers|Preschool|School-Age", it.get("ages") or "") else "community", campus_ok=True)
        out.append(make_event("dbrl", "Daniel Boone Regional Library", it.get("id"), title, start, end,
                              venue=loc + (f" · {it['venue_room']}" if it.get("venue_room") else ""),
                              url=it.get("url") or f"https://events.dbrl.org/event/{it.get('id')}",
                              price=price, category=cat, image=img_url,
                              description=it.get("description") or it.get("long_description"),
                              organizer="Daniel Boone Regional Library",
                              phone="(573) 443-3161" if loc.startswith("Columbia Public") else None))
    return out

POSH_GROUPS = {
    # posh.vip group slug -> (display name, venue, address, phone)
    "myhouse-1": ("MyHouse", "MyHouse Nightclub", "119 S 7th St, Columbia, MO 65201", None),
}
def src_posh(days):
    """Posh (posh.vip) ticketing pages for downtown clubs and party promoters."""
    out = []
    now = dt.datetime.now(dt.timezone.utc)
    for slug, (name, venue, address, phone) in POSH_GROUPS.items():
        try:
            js = get(f"https://posh.vip/api/web/v2/util/group_url/{slug}", headers={"Accept": "application/json"}).json()
        except Exception as e:
            log("  posh", slug, "failed:", e); continue
        for e in js.get("events", []):
            if e.get("status") not in (None, "live"):
                continue
            start = parse_dt(e.get("startUtc") or e.get("start"))
            end = parse_dt(e.get("endUtc") or e.get("end"))
            if not start or start < now - dt.timedelta(hours=6):
                continue
            v = e.get("venue") or {}
            prices = [t.get("price") for t in e.get("ticketGroups", []) if isinstance(t, dict) and t.get("price") is not None]
            price = None
            if prices:
                lo = min(prices)
                price = "Free" if lo == 0 else f"From ${lo:g}"
            title = clean_title(e.get("name"))
            desc = e.get("description") or ""
            if re.match(r"^\s*fast ?pass", title, re.I):
                start = start.astimezone(TZ).replace(hour=22, minute=0)
                end = None
                title = re.sub(r"^\s*fast ?pass:?\s*", f"{name} ", title, flags=re.I) + " Night"
                desc = (desc + " Ticket is a FastPass to skip the line; doors are usually around 10 PM.").strip()
            out.append(make_event("posh", f"{name} (Posh)", e.get("id") or e.get("url"), title, start, end,
                                  venue=v.get("name") or venue, address=v.get("address") or address,
                                  url=f"https://posh.vip/e/{e.get('url')}", ticket_url=f"https://posh.vip/e/{e.get('url')}",
                                  phone=phone, price=price,
                                  category=infer_category(title, desc, "party"),
                                  image=e.get("flyer"), description=desc, organizer=name))
    return out

TRIBE_SITES = {
    # The Events Calendar (WordPress) REST sites: slug -> (display name, default venue, address)
    "cooperslanding": ("Cooper's Landing", "https://cooperslandingmo.com", "Cooper's Landing", "11505 Smith Hatchery Rd, Columbia, MO 65203"),
}
def src_tribe(days):
    out = []
    end_date = (dt.datetime.now(TZ) + dt.timedelta(days=days)).strftime("%Y-%m-%d")
    for key, (name, base, venue_default, address_default) in TRIBE_SITES.items():
        page = 1
        while page <= 5:
            try:
                js = get(f"{base}/wp-json/tribe/events/v1/events", params={"per_page": 50, "page": page, "end_date": end_date}).json()
            except Exception as e:
                log("  tribe", key, "page", page, "failed:", e); break
            for e in js.get("events", []):
                if e.get("is_virtual") or e.get("hide_from_listings"):
                    continue
                start = parse_dt(e.get("start_date", "").replace(" ", "T"))
                end = parse_dt(e.get("end_date", "").replace(" ", "T"))
                v = e.get("venue") or {}
                if isinstance(v, list):
                    v = v[0] if v else {}
                lat = float(v["geo_lat"]) if v.get("geo_lat") else None
                lng = float(v["geo_lng"]) if v.get("geo_lng") else None
                cats = [c.get("name", "") for c in e.get("categories", [])]
                title = clean_title(e.get("title"))
                cl = " ".join(cats).lower()
                if "music" in cl or "concert" in cl:
                    cat = "music"
                elif "food" in cl or "truck" in cl:
                    cat = "food"
                elif "trivia" in cl or "karaoke" in cl:
                    cat = "nightlife"
                else:
                    cat = infer_category(title, e.get("description", ""), "community")
                cost = (e.get("cost") or "").strip() or None
                out.append(make_event(key, name, e.get("id"), title, start, end, all_day=bool(e.get("all_day")),
                                      venue=v.get("venue") or venue_default,
                                      address=v.get("address") or address_default, lat=lat, lng=lng,
                                      url=e.get("website") or e.get("url"), price=cost, category=cat,
                                      image=(e.get("image") or {}).get("url") if isinstance(e.get("image"), dict) else None,
                                      description=e.get("description") or e.get("excerpt"), organizer=name))
            if page >= int(js.get("total_pages") or 1):
                break
            page += 1
    return out

MONTHS = {m: i for i, m in enumerate(["january", "february", "march", "april", "may", "june", "july",
                                       "august", "september", "october", "november", "december"], 1)}
def _vox_date(text):
    m = re.search(r"([A-Z][a-z]+),\s+([A-Z][a-z]+)\s+(\d{1,2})(?:st|nd|rd|th)?,\s+(\d{4})", text)
    if not m or m.group(2).lower() not in MONTHS:
        return None
    return dt.date(int(m.group(4)), MONTHS[m.group(2).lower()], int(m.group(3)))

def _vox_times(text):
    m = re.search(r"@\s*(\d{1,2}(?::\d{2})?\s*[ap]m)(?:\s*[–-]\s*(\d{1,2}(?::\d{2})?\s*[ap]m))?", text, re.I)
    def t(x):
        if not x:
            return None
        x = x.lower().replace(" ", "")
        return dt.datetime.strptime(x, "%I:%M%p" if ":" in x else "%I%p").time()
    return (t(m.group(1)), t(m.group(2))) if m else (None, None)

def src_vox(days):
    """Vox Magazine community calendar (TownNews). Listing cards only: no per-event fetch,
    because voxmagazine.com rate-limits hard. Recurring schedules are expanded week by week."""
    out = []
    today = dt.datetime.now(TZ).date()
    horizon = today + dt.timedelta(days=days)
    seen = set()
    for offset in (0, 50, 100, 150):
        try:
            h = get("https://www.voxmagazine.com/calendar/search/",
                    params={"f": "json", "l": 50, "o": offset, "s": "start_time", "sd": "asc", "d1": today.isoformat()}).text
        except Exception as e:
            log("  vox page", offset, "failed:", e); break
        cards = re.split(r'(?=<div class="card-container)', h)
        found = 0
        for c in cards:
            m = re.search(r'href="(/calendar/[^"]+/event_[^"]+\.html)"', c)
            if not m or m.group(1) in seen:
                continue
            seen.add(m.group(1)); found += 1
            def field(cls, limit=300):
                mm = re.search(r'class="card-%s[^"]*"[^>]*>(.*?)</div>' % cls, c, re.S)
                return strip_html(mm.group(1), limit) if mm else None
            title = field("headline", 160)
            venue = field("venue", 120)
            cost = field("cost", 60)
            lead = field("lead", 600)
            img = re.search(r'<img[^>]+(?:data-src|src)="(https://bloximages[^"]+)"', c)
            url = "https://www.voxmagazine.com" + m.group(1)
            if not title:
                continue
            schedules = re.findall(r'<li class="schedule">\s*<small>(.*?)</small>', c, re.S)
            dates = []
            for sch in schedules:
                sch = html.unescape(re.sub(r"<[^>]+>", " ", sch))
                st, et = _vox_times(sch)
                first = _vox_date(sch)
                if not first:
                    continue
                rep = re.search(r"repeat(?:s|ed)\s+every\s+(\d+\s+)?weeks?\s+on\s+([A-Za-z]+).*?until\s+(.*)$", sch, re.I)
                if rep:
                    until = _vox_date(rep.group(3)) or horizon
                    step = int((rep.group(1) or "1").strip()) * 7
                    d = first
                    while d < today:
                        d += dt.timedelta(days=step)
                    while d <= min(until, horizon):
                        dates.append((d, st, et)); d += dt.timedelta(days=step)
                else:
                    dates.append((first, st, et))
            for d, st, et in dates:
                if d < today or d > horizon:
                    continue
                start = dt.datetime.combine(d, st or dt.time(0, 0), TZ)
                end = dt.datetime.combine(d, et, TZ) if et else None
                if end and end < start:
                    end += dt.timedelta(days=1)
                out.append(make_event("vox", "Vox Magazine Calendar", f"{m.group(1)}#{d.isoformat()}", title, start, end,
                                      all_day=st is None, time_tbd=st is None,
                                      venue=venue, url=url, price=cost or None,
                                      category=infer_category(title, lead or ""),
                                      image=img.group(1) if img else None, description=lead))
        if found == 0:
            break
    return out

# ----------------------------------------------------------------- public iCalendar feeds
ICS_SITES = {
    # key -> (display name, ICS url, venue, address, lat, lng, info url, default category)
    # Shanthi Mandir (Hindu Temple and Community Center of Mid-Missouri) publishes its poojas in a
    # public Google Calendar embedded at shanthimandir.missouri.org/events-calendar/.
    "shanthimandir": ("Shanthi Mandir", "https://calendar.google.com/calendar/ical/shanthimandir2005%40gmail.com/public/basic.ics",
                      "Shanthi Mandir", "2006 Holly Ave, Columbia, MO 65202", 38.97534, -92.30822,
                      "https://shanthimandir.missouri.org/events-calendar/", "community"),
    # Maplewood Barn Community Theatre (Nifong Park): Google Calendar embedded on maplewoodbarn.org/index.php/calendar/.
    # Shows run May-September as weekly recurring rules.
    "maplewoodbarn": ("Maplewood Barn Theatre", "https://calendar.google.com/calendar/ical/maplewoodbarntheatre%40gmail.com/public/basic.ics",
                      "Maplewood Barn Theatre", "2900 E Nifong Blvd, Columbia, MO 65201", 38.90876, -92.29616,
                      "https://maplewoodbarn.org/index.php/calendar/", "arts"),
    # The Arcade District (Fay St: The Tokyo Club, arcade bar, comedy, DJ nights): GoDaddy calendar widget backed by Google Calendar.
    "arcadedistrict": ("The Arcade District", "https://calendar.google.com/calendar/ical/jv0v6af2rpdhnicccjkgfa644k%40group.calendar.google.com/public/basic.ics",
                       "The Arcade District", "602 Fay St, Columbia, MO 65201", 38.95781, -92.32236,
                       "https://thearcadedistrict.org/", "nightlife"),
}
ICS_SITE_SKIP = {
    "maplewoodbarn": re.compile(r"\b(board meeting|director application|application|board|work day|strike|load[- ]?in|rehearsal)\b", re.I),
    "arcadedistrict": re.compile(r"\b(closed|private event|private party)\b", re.I),
}
ICS_SKIP = re.compile(r"\b(temple\s+(open|closed)|open\s+hours|closed)\b", re.I)
ICS_BLURB = {
    "shanthimandir": "At Shanthi Mandir, the Hindu Temple and Community Center of Mid-Missouri. Everyone is welcome; "
                     "regular poojas are led by volunteers and can be sponsored. Details: shanthimandir.missouri.org",
}

def _ics_unescape(s):
    return (s or "").replace("\\n", "\n").replace("\\,", ",").replace("\\;", ";").replace("\\\\", "\\").strip()

def _ics_datetime(params, val):
    """DTSTART/DTEND value -> (aware datetime in Chicago, is_all_day)."""
    val = val.strip()
    tz = TZ
    if params.get("TZID"):
        try:
            tz = ZoneInfo(params["TZID"])
        except Exception:
            pass
    if len(val) == 8 and val.isdigit():
        return dt.datetime(int(val[:4]), int(val[4:6]), int(val[6:8]), tzinfo=TZ), True
    utc = val.endswith("Z")
    val = val.rstrip("Z")
    d = dt.datetime.strptime(val, "%Y%m%dT%H%M%S")
    d = d.replace(tzinfo=dt.timezone.utc).astimezone(TZ) if utc else d.replace(tzinfo=tz).astimezone(TZ)
    return d, False

def src_ics(days):
    """One-off and recurring events from public .ics calendars. Recurring rules are expanded with
    dateutil when it is installed (the workflow installs it); without it only one-off dates are used."""
    try:
        from dateutil.rrule import rrulestr
    except ImportError:  # pragma: no cover
        rrulestr = None
        log("  ics: python-dateutil missing, recurring events skipped")
    out = []
    now = dt.datetime.now(TZ)
    horizon = now + dt.timedelta(days=days)
    for key, (name, url, venue, address, lat, lng, info, default_cat) in ICS_SITES.items():
        try:
            text = get(url).text.replace("\r\n", "\n")
        except Exception as e:
            log("  ics", key, "failed:", e); continue
        text = re.sub(r"\n[ \t]", "", text)          # unfold continuation lines
        for block in text.split("BEGIN:VEVENT")[1:]:
            block = block.split("END:VEVENT")[0]
            props = {}
            for line in block.split("\n"):
                if ":" not in line:
                    continue
                head, val = line.split(":", 1)
                parts = head.split(";")
                params = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
                props.setdefault(parts[0], []).append((params, val))
            summary = _ics_unescape(props.get("SUMMARY", [({}, "")])[0][1])
            if not summary or ICS_SKIP.search(summary) or (key in ICS_SITE_SKIP and ICS_SITE_SKIP[key].search(summary)) or props.get("STATUS", [({}, "")])[0][1].strip() == "CANCELLED":
                continue
            if "DTSTART" not in props:
                continue
            try:
                start, all_day = _ics_datetime(*props["DTSTART"][0])
                end = _ics_datetime(*props["DTEND"][0])[0] if "DTEND" in props else None
            except Exception:
                continue
            duration = (end - start) if end else dt.timedelta(days=1 if all_day else 0, hours=0 if all_day else 1, minutes=0 if all_day else 30)
            if duration.total_seconds() <= 0:
                duration = dt.timedelta(hours=1, minutes=30)
            exdates = set()
            for params, val in props.get("EXDATE", []):
                for v in val.split(","):
                    try:
                        exdates.add(_ics_datetime(params, v)[0].date())
                    except Exception:
                        pass
            occurrences = []
            if "RRULE" in props:
                if rrulestr:
                    try:
                        try:
                            rule = rrulestr(props["RRULE"][0][1].strip(), dtstart=start)
                            occurrences = list(rule.between(now - dt.timedelta(hours=3), horizon, inc=True))
                        except ValueError:
                            # UNTIL without a UTC "Z" next to a zoned DTSTART: expand in local wall time instead
                            rule = rrulestr(props["RRULE"][0][1].strip(), dtstart=start.replace(tzinfo=None))
                            occurrences = [o.replace(tzinfo=start.tzinfo) for o in rule.between(
                                (now - dt.timedelta(hours=3)).astimezone(start.tzinfo).replace(tzinfo=None),
                                horizon.astimezone(start.tzinfo).replace(tzinfo=None), inc=True)]
                    except Exception as e:
                        log("  ics", key, "rrule failed for", summary, e)
            elif now - dt.timedelta(hours=3) <= start <= horizon:
                occurrences = [start]
            uid = props.get("UID", [({}, summary)])[0][1].strip()
            desc = _ics_unescape(props.get("DESCRIPTION", [({}, "")])[0][1]) or ICS_BLURB.get(key)
            loc = _ics_unescape(props.get("LOCATION", [({}, "")])[0][1])
            for occ in occurrences:
                if occ.date() in exdates:
                    continue
                sid = f"{uid}:{occ:%Y%m%d%H%M}"
                ev = make_event(key, name, sid, summary, occ, occ + duration, all_day=all_day,
                                venue=venue, address=loc or address, lat=lat, lng=lng, url=info,
                                category=infer_category(summary, desc or "", default_cat),
                                description=desc, organizer=name)
                if ev:
                    if key == "shanthimandir":
                        ev["audience"] = sorted(set(ev["audience"]) | {"family", "groups"})   # temple programs are for families too
                    out.append(ev)
    return out

# ----------------------------------------------------------------- hand-entered flyer events
def venue_lookup(name):
    """Row from feed/venues.json for a venue name (exact name or alias, case-insensitive), or None."""
    if not name:
        return None
    key = name.strip().lower()
    for vname, row in VENUES.items():
        if key == vname.lower() or key in [a.lower() for a in row.get("aliases", [])]:
            return dict(row, name=vname)
    for vname, row in VENUES.items():
        if len(key) > 4 and (key in vname.lower() or any(a.lower() in key for a in row.get("aliases", []) if len(a) > 4)):
            return dict(row, name=vname)
    return None

def src_extra(days):
    """feed/extra.json: events typed in from flyers. Minimal rows; the venue table fills the rest."""
    path = os.path.join(HERE, "extra.json")
    if not os.path.exists(path):
        return []
    try:
        rows = json.load(open(path)).get("events", [])
    except Exception as e:
        log("  extra.json unreadable:", e); return []
    out = []
    horizon = dt.datetime.now(TZ) + dt.timedelta(days=days)
    for r in rows:
        start = parse_dt(r.get("start"))
        if not start or start > horizon or start < dt.datetime.now(TZ) - dt.timedelta(days=1):
            continue
        v = venue_lookup(r.get("venue")) or {}
        address = r.get("address") or (v.get("address") if v else None)
        if address and v and "Columbia" not in address and "Jefferson" not in address:
            address = f"{address}, Columbia, MO"
        out.append(make_event("flyer", r.get("sourceName") or "Posted from a flyer", r.get("id") or r["title"], r["title"],
                              start, parse_dt(r.get("end")), all_day=bool(r.get("allDay")),
                              venue=v.get("name") or r.get("venue"), address=address,
                              lat=r.get("lat") or v.get("lat"), lng=r.get("lng") or v.get("lng"),
                              url=r.get("link") or v.get("website"), phone=r.get("phone") or v.get("phone"),
                              price=r.get("price"), category=r.get("category") or "community",
                              image=r.get("imageUrl"), description=r.get("description"), organizer=r.get("organizer")))
        if out[-1] and r.get("categories"):
            cats = [c for c in r["categories"] if c in dict(CATEGORY_RULES) or c in ("community", "campus")]
            out[-1]["categories"] = list(dict.fromkeys([out[-1]["category"]] + cats))
    return out


# ----------------------------------------------------------------- arts venues (Oct 2026 batch)
# Each reads the venue's own public listing. Squarespace sites expose ?format=json; others are noted inline.

def _ms(ts):
    return dt.datetime.fromtimestamp(ts / 1000, TZ) if ts else None

SQUARESPACE_SITES = {
    # key -> (display name, events JSON url, default venue, default address, default category)
    "mosy": ("The Missouri Symphony", "https://www.themosy.org/calendar?format=json", "Missouri Theatre", "203 S 9th St, Columbia, MO 65201", "music"),
    "cec": ("Columbia Entertainment Company", "https://www.cectheatre.org/events?format=json", "Columbia Entertainment Company", "1800 Nelwood Dr, Columbia, MO 65202", "arts"),
}
def src_squarespace(days):
    out = []
    horizon = dt.datetime.now(TZ) + dt.timedelta(days=days)
    for key, (name, url, venue_default, address_default, cat) in SQUARESPACE_SITES.items():
        try:
            js = get(url, headers={"User-Agent": BROWSER_UA}).json()
        except Exception as e:
            log("  squarespace", key, "failed:", e); continue
        base = url.split("/")[0] + "//" + url.split("/")[2]
        for it in js.get("upcoming", []):
            start, end = _ms(it.get("startDate")), _ms(it.get("endDate"))
            if not start or start > horizon:
                continue
            title = clean_title(html.unescape(it.get("title") or ""))
            desc = strip_html(it.get("excerpt") or it.get("body") or "", 600)
            # a theatre run is one entry spanning weeks: keep opening night, note the closing date
            if end and (end - start).days >= 1:
                closing = end
                end = start.replace(hour=end.hour, minute=end.minute)
                if end <= start:
                    end = start + dt.timedelta(hours=2, minutes=30)
                desc = f"Runs through {closing:%A, %B %-d}. " + desc
            loc = it.get("location") or {}
            venue = (loc.get("addressTitle") or venue_default).strip()
            addr = ", ".join(x for x in (loc.get("addressLine1"), loc.get("addressLine2")) if x) or address_default
            lat, lng = loc.get("markerLat"), loc.get("markerLng")
            if not lat or abs(lat - DOWNTOWN[0]) > 1 or abs(lng - DOWNTOWN[1]) > 1:   # Squarespace often leaves a NYC default pin
                lat = lng = None
            out.append(make_event(key, name, it.get("id") or it.get("urlId") or title, title, start, end,
                                  venue=venue, address=addr, lat=lat, lng=lng, url=base + (it.get("fullUrl") or ""),
                                  category=infer_category(title, desc, cat), image=it.get("assetUrl"),
                                  description=desc, organizer=name))
    return out

def src_ragtag(days):
    """Ragtag Cinema showtimes: the JSON its FullCalendar loads (every showtime ever, so filter by date)."""
    try:
        rows = json.loads(S.post("https://ragtagcinema.org/wp-admin/admin-ajax.php", data={"action": "calendar_events"},
                                 headers={"User-Agent": BROWSER_UA}, timeout=30).text)
    except Exception as e:
        log("  ragtag failed:", e); return []
    now = dt.datetime.now(TZ)
    horizon = now + dt.timedelta(days=days)
    out = []
    for r in rows:
        start = parse_dt((r.get("start") or "").replace(" ", "T"))
        end = parse_dt((r.get("end") or "").replace(" ", "T"))
        if not start or not (now - dt.timedelta(hours=2) <= start <= horizon):
            continue
        title = clean_title(html.unescape(r.get("title") or ""))
        out.append(make_event("ragtag", "Ragtag Cinema", f"{r.get('url')}:{start:%Y%m%d%H%M}", title, start, end,
                              venue="Ragtag Cinema", address="10 Hitt St, Columbia, MO 65201", lat=38.95124, lng=-92.32539,
                              url=r.get("url"), category="arts",
                              description="Film screening at Ragtag Cinema, Columbia's independent movie theater.",
                              organizer="Ragtag Cinema"))
    return out

def src_stephens(days):
    """Stephens College performing arts (Macklanburg Playhouse, Warehouse Theatre) from its Localist calendar."""
    out = []
    try:
        js = get("https://calendar.stephens.edu/api/2/events", params={"days": min(days, 365), "pp": 100, "type": 53310692394891}).json()
    except Exception as e:
        log("  stephens failed:", e); return []
    for wrap in js.get("events", []):
        ev = wrap.get("event", {})
        geo = ev.get("geo") or {}
        for inst in ev.get("event_instances", []):
            i = inst.get("event_instance", {})
            start, end = parse_dt(i.get("start")), parse_dt(i.get("end"))
            if not start:
                continue
            out.append(make_event("stephens", "Stephens College Performing Arts", i.get("id"), ev.get("title"), start, end,
                                  all_day=bool(i.get("all_day")), venue=ev.get("location_name"), address=ev.get("address"),
                                  lat=float(geo["latitude"]) if geo.get("latitude") else None,
                                  lng=float(geo["longitude"]) if geo.get("longitude") else None,
                                  url=ev.get("localist_url"), ticket_url=ev.get("ticket_url"), price=ev.get("ticket_cost"),
                                  category="arts", image=ev.get("photo_url"), description=ev.get("description_text") or ev.get("description"),
                                  organizer="Stephens College Conservatory for the Performing Arts"))
    return out

def src_talkinghorse(days):
    """Talking Horse Productions: the listings JSON embedded in its TicketLeap page."""
    try:
        page = get("https://events.ticketleap.com/events/talkinghorse", headers={"User-Agent": BROWSER_UA}).text
    except Exception as e:
        log("  talkinghorse failed:", e); return []
    i = page.find('[{"type":"listing"')
    if i < 0:
        return []
    depth, j = 0, i
    for j in range(i, len(page)):
        depth += page[j] == "["
        depth -= page[j] == "]"
        if depth == 0:
            break
    try:
        rows = json.loads(page[i:j + 1])
    except ValueError:
        return []
    now, out = dt.datetime.now(TZ), []
    for r in rows:
        title = clean_title(r.get("listing_title") or "")
        if not title or re.search(r"flex pass|cancel+ed|gift card|season ticket", title, re.I):
            continue
        start, end = parse_dt((r.get("event_start") or "").replace(" ", "T")), parse_dt((r.get("event_end") or "").replace(" ", "T"))
        if not start or start < now - dt.timedelta(hours=3) or start > now + dt.timedelta(days=days):
            continue
        if end and (end - start).days >= 1:
            end = None
        out.append(make_event("talkinghorse", "Talking Horse Productions", r.get("event_id") or title, title, start, end,
                              venue="Talking Horse Productions", address="210 St James St, Suite B, Columbia, MO 65201",
                              url="https://events.ticketleap.com/events/" + (r.get("listing_slug") or "talkinghorse"),
                              ticket_url="https://events.ticketleap.com/events/" + (r.get("listing_slug") or "talkinghorse"),
                              price=r.get("min_price_fmt"), category="arts",
                              image=("https:" + r["image"]) if (r.get("image") or "").startswith("//") else r.get("image"),
                              organizer="Talking Horse Productions"))
    return out

def src_mizzouarts(days):
    """Mizzou Arts / University Concert Series: WordPress 'event' posts with ACF performance dates."""
    try:
        rows = get("https://mizzouarts.missouri.edu/wp-json/wp/v2/event", params={"per_page": 100, "_fields": "id,title,link,acf"}).json()
    except Exception as e:
        log("  mizzouarts failed:", e); return []
    now, out = dt.datetime.now(TZ), []
    for r in rows:
        acf = r.get("acf") or {}
        title = clean_title(html.unescape((r.get("title") or {}).get("rendered") or ""))
        for n, d in enumerate(acf.get("dates") or []):
            when = f"{d.get('date', '')} {d.get('time', '')}".strip().replace(".", "")
            start = None
            for fmt in ("%b %d, %Y %I:%M %p", "%B %d, %Y %I:%M %p", "%b %d, %Y %I %p", "%b %d, %Y"):
                try:
                    start = dt.datetime.strptime(re.sub(r"\bSept\b", "Sep", when), fmt).replace(tzinfo=TZ)
                    break
                except ValueError:
                    continue
            if not start or not (now - dt.timedelta(hours=3) <= start <= now + dt.timedelta(days=days)):
                continue
            venue = (d.get("location") or "").strip() or "Missouri Theatre"
            host = (acf.get("host") or "").strip() or "University Concert Series"
            out.append(make_event("mizzouarts", "Mizzou Arts · University Concert Series", f"{r['id']}:{n}", title, start,
                                  time_tbd=not d.get("time"), venue=venue, url=r.get("link"), ticket_url=d.get("ticket_link") or None,
                                  category=infer_category(title, "", "music"), organizer=host))
    return out

WAS_MONTHS = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}
def src_wealwaysswing(days):
    """We Always Swing Jazz Series: the season page (one table per show; venue on each event page)."""
    now = dt.datetime.now(TZ)
    season = f"{now.year}-{now.year + 1}" if now.month >= 7 else f"{now.year - 1}-{now.year}"
    base = "https://www.wealwaysswing.org/season/" + season + "/"
    try:
        page = get(base + "season.php", headers={"User-Agent": BROWSER_UA}).text
    except Exception as e:
        log("  wealwaysswing failed:", e); return []
    times_by_href = {href: t for _, t, href, _ in re.findall(r"<b>\s*([^<]*\d{4})\s*<br\s*/?>\s*([^<]*)</b>.*?href=['\"]?(event\.php\?id=\d+)['\"]?[^>]*>([^<]+)</a>", page, re.S | re.I)}
    shows = re.findall(r'HREF="[^"]*?(event\.php\?id=\d+)"\s+title="(\d{1,2})/(\d{1,2})/(\d{4})\s*(?:&mdash;|—|-)\s*([^"]+)"', page, re.I)
    out, seen = [], set()
    for href, mo, dd, yy, title in shows:
        if href in seen:
            continue
        seen.add(href)
        day = dt.date(int(yy), int(mo), int(dd))
        if not (now.date() - dt.timedelta(days=1) <= day <= (now + dt.timedelta(days=days)).date()):
            continue
        times = [t.strip() for t in times_by_href.get(href, "").split("|") if t.strip()]
        detail = ""
        try:
            detail = cached_page(base + href) or ""
        except Exception:
            pass
        dl = strip_html(detail, 4000)
        venue, address = "We Always Swing Jazz Series", None
        if re.search(r"murry", dl, re.I):
            venue, address = "Murry's", "3107 Green Meadows Way, Columbia, MO 65203"
        elif re.search(r"whitmore", dl, re.I):
            venue, address = "Whitmore Recital Hall", "Sinquefield Music Center, Columbia, MO 65211"
        elif re.search(r"missouri theatre", dl, re.I):
            venue, address = "Missouri Theatre", "203 S 9th St, Columbia, MO 65201"
        elif re.search(r"tokyo club", dl, re.I):
            venue, address = "The Tokyo Club", "709 Fay St, Columbia, MO 65201"
        for t in times or [""]:
            tm = re.match(r"(\d{1,2})(?::(\d{2}))?", t)
            hour = int(tm.group(1)) if tm else 19
            hour = hour + 12 if hour < 12 else hour   # the season page lists afternoon/evening hours without am/pm
            start = dt.datetime(day.year, day.month, day.day, hour, int(tm.group(2) or 0) if tm else 0, tzinfo=TZ)
            out.append(make_event("wealwaysswing", "We Always Swing Jazz Series", f"{href}:{start:%H%M}", html.unescape(title).strip(), start,
                                  start + dt.timedelta(hours=2), time_tbd=not tm, venue=venue, address=address,
                                  url=base + href, category="music", description=strip_html(detail, 600) if detail else None,
                                  organizer="We Always Swing Jazz Series"))
    return out

def src_lyceum(days):
    """Arrow Rock Lyceum Theatre: PatronTicket (Salesforce) public ticket app, fetchEvents remote call."""
    try:
        page = get("https://lyceumtheatre.my.salesforce-sites.com/ticket/", headers={"User-Agent": BROWSER_UA}).text
        cfg = json.loads(re.search(r'\{"name":"fetchEvents"[^{}]*\}', page).group(0))
        vid = re.search(r'"vid":"([^"]+)"', page).group(1)
        body = {"action": "PatronTicket.Controller_PublicTicketApp", "method": "fetchEvents", "data": ["", "", "", ""], "type": "rpc", "tid": 2,
                "ctx": {"csrf": cfg.get("csrf"), "vid": vid, "ns": cfg.get("ns", "PatronTicket"), "ver": cfg.get("ver", 51), "authorization": cfg.get("authorization")}}
        r = S.post("https://lyceumtheatre.my.salesforce-sites.com/ticket/apexremote", json=body, timeout=30,
                   headers={"User-Agent": BROWSER_UA, "X-User-Agent": "Visualforce-Remoting", "Referer": "https://lyceumtheatre.my.salesforce-sites.com/ticket/"})
        events = r.json()[0].get("result") or []
    except Exception as e:
        log("  lyceum failed:", e); return []
    now, out = dt.datetime.now(TZ), []
    for e in events if isinstance(events, list) else []:
        for inst in e.get("instances", []):
            start = _ms((inst.get("formattedDates") or {}).get("ISO8601"))
            if not start or not (now - dt.timedelta(hours=3) <= start <= now + dt.timedelta(days=days)):
                continue
            out.append(make_event("lyceum", "Arrow Rock Lyceum Theatre", inst.get("id") or f"{e.get('id')}:{start}", e.get("name"), start,
                                  start + dt.timedelta(hours=2, minutes=30), venue="Arrow Rock Lyceum Theatre",
                                  address="114 High St, Arrow Rock, MO 65320", lat=39.07108, lng=-92.94358,
                                  url="https://lyceumtheatre.org/", ticket_url="https://lyceumtheatre.my.salesforce-sites.com/ticket/" + (inst.get("purchaseUrl") or ""),
                                  category="arts", image=e.get("largeImagePath") or e.get("smallImagePath"),
                                  description=strip_html(e.get("description") or "", 600) + " About an hour's drive from Columbia, in historic Arrow Rock.",
                                  organizer="Arrow Rock Lyceum Theatre"))
    return out

CAAM_DATE = re.compile(r"^(January|February|March|April|May|June|July|August|September|October|November|December) (\d{1,2}), (\d{4})\s*(?:\|\s*(.*))?$")
def src_caam(days):
    """Choral Arts Alliance of Missouri: concerts page (WordPress). One concert per paragraph: the first bold
    line is the title, the next bold lines say who sings, and 'Month D, YYYY | time | venue' lines are performances."""
    try:
        page = get("https://www.choralartsallianceofmissouri.org/wp-json/wp/v2/pages", params={"slug": "caam-concerts", "_fields": "content,link"}).json()[0]
    except Exception as e:
        log("  caam failed:", e); return []
    months = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
    nice = lambda t: re.sub(r"[A-Za-z][A-Za-z'’]*", lambda m: m.group(0).capitalize() if m.group(0).isupper() else m.group(0), t).strip()
    text_of = lambda x: html.unescape(re.sub(r"<[^>]+>", "", x)).strip()
    now, out = dt.datetime.now(TZ), []
    for para in re.findall(r"<p[^>]*>(.*?)</p>", page["content"]["rendered"], re.S):
        para = para.replace("</strong><strong>", "</strong><br /><strong>")
        lines = [text_of(l) for l in re.split(r"<br\s*/?>", para)]
        dated = [l for l in lines if CAAM_DATE.match(l) and "|" in l]
        if not dated:
            continue
        strongs = [text_of(x) for x in re.findall(r"<strong>(.*?)</strong>", para, re.S)]
        strongs = [x for x in strongs if x and not CAAM_DATE.match(x)]
        if not strongs:
            continue
        title = nice(strongs[0])
        sub = [x for x in strongs[1:3] if not re.search(r"\$|ticket|free", x, re.I)]
        for line in dated:
            m = CAAM_DATE.match(line)
            rest = [x.strip() for x in (m.group(4) or "").split("|")]
            tm = re.search(r"(\d{1,2})(?::(\d{2}))?(?:\s*-\s*\d{1,2}(?::\d{2})?)?\s*([ap])\.?\s*m", rest[0] if rest else "", re.I)
            hour = (int(tm.group(1)) % 12 + (12 if tm.group(3).lower() == "p" else 0)) if tm else 19
            start = dt.datetime(int(m.group(3)), months.index(m.group(1)) + 1, int(m.group(2)), hour, int(tm.group(2) or 0) if tm else 0, tzinfo=TZ)
            if not (now - dt.timedelta(hours=3) <= start <= now + dt.timedelta(days=days)):
                continue
            where = rest[1] if len(rest) > 1 and rest[1] and not re.search(r"\bTBA\b", rest[1], re.I) else None
            if where and re.search(r"Jefferson City|Boonville|Kansas|St\. Louis", where):
                continue
            venue = where.split(",")[0].strip() if where else None
            out.append(make_event("caam", "Choral Arts Alliance of Missouri", f"{title}:{start:%Y%m%d%H%M}", title, start, start + dt.timedelta(hours=2),
                                  time_tbd=not tm, venue=venue, address=where, url=page.get("link"), category="music",
                                  description=" · ".join(sub) or None, organizer="Choral Arts Alliance of Missouri"))
    return out

SOURCES = [src_mizzou, src_visitcolumbia, src_eventbrite, src_allevents, src_baselocal, src_bluenote, src_dbrl,
           src_posh, src_tribe, src_vox, src_ics, src_extra,
           src_squarespace, src_ragtag, src_stephens, src_talkinghorse, src_mizzouarts, src_wealwaysswing, src_lyceum, src_caam]

# ----------------------------------------------------------------- merge
def dedupe(events):
    """Merge the same event listed by several sources: same normalized title (or one title containing the
    other) on the same local date. Showtimes from ONE source at different times stay separate (a film's
    1 pm and 6:30 pm screenings, a matinee and an evening show)."""
    by_key = {}
    order = []
    for e in events:
        nk = norm_key(e["title"])
        day = e["start"][:10]
        candidates = []
        for k2 in order:
            if k2[1] != day:
                continue
            other = norm_key(by_key[k2]["title"])
            short, long_ = sorted((nk, other), key=len)
            if k2[0] == nk[:40] or (len(short) >= 12 and short in long_):
                candidates.append(k2)
        same_time = [k2 for k2 in candidates if by_key[k2]["start"] == e["start"]]
        other_source = [k2 for k2 in candidates if by_key[k2]["source"] != e["source"]]
        key = (same_time or other_source or [None])[0]
        if key is None:
            key = (nk[:40], day, e["start"])
            by_key[key] = e
            order.append(key)
            e["alsoOn"] = []
            continue
        a = by_key[key]
        # prefer the record with coordinates, then an exact time, then richer text
        def score(x):
            return (x["lat"] is not None, not x["timeTBD"], bool(x.get("description")), bool(x.get("imageUrl")))
        keep, drop = (a, e) if score(a) >= score(e) else (e, a)
        for k in ("lat", "lng", "venue", "address", "phone", "price", "imageUrl", "description", "ticketUrl", "end"):
            if keep.get(k) in (None, "") and drop.get(k):
                keep[k] = drop[k]
        if keep.get("category") == "community" and drop.get("category") not in (None, "community"):
            keep["category"] = drop["category"]
            keep["audience"] = drop.get("audience") or keep.get("audience")
        merged_cats = [keep.get("category")] + [c for c in (keep.get("categories") or []) + (drop.get("categories") or [])
                                                if c != keep.get("category")]
        keep["categories"] = [c for i, c in enumerate(merged_cats) if c and c not in merged_cats[:i]][:4]
        if len(keep["categories"]) > 1 and "community" in keep["categories"]:
            keep["categories"].remove("community")
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
        if known and "lat" in known and e["source"] in ("allevents", "visitcolumbia", "baselocal", "dbrl", "vox", "posh", "cooperslanding",
                                                 "mosy", "cec", "talkinghorse", "mizzouarts", "wealwaysswing", "caam"):
            e["lat"], e["lng"] = known["lat"], known["lng"]
            e["address"] = e.get("address") or known.get("address")
            e["phone"] = e.get("phone") or known.get("phone")
        if e["lat"] is None and (e.get("venue") or e.get("address")):
            g = geocode(e.get("venue"), e.get("address"))
            if g:
                e["lat"], e["lng"], v, a = g
                e["venue"] = e.get("venue") or v
                e["address"] = e.get("address") or a
        if e["lat"] is not None and haversine_km((e["lat"], e["lng"]), DOWNTOWN) > RADIUS_KM and e["source"] not in FAR_OK_SOURCES:
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
