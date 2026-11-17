#!/usr/bin/env python3
"""Places tab: everyday spots in Columbia (bowling, escape rooms, parks and trails, museums, coffee, bars,
the mall) from Visit Columbia's public directory, plus a few we add by hand (feed/places-extra.json).

Writes docs/places.json (website) and CoMoEvents/Resources/places.json (app snapshot). The apps also
download docs/places.json, so a rebuild shows up without an app update. Run it now and then:
  python3 scripts/build_places.py
"""
import datetime as dt, html, json, os, re, sys, urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "feed"))
import aggregate as A   # noqa: E402  (get with polite pacing, geocode with cache, haversine)

API = "https://www.visitcolumbiamo.com/wp-json/wp/v2/directory"
# Visit Columbia section id -> our place category
SECTIONS = [
    (34, "fun"), (33, "outdoors"), (43, "outdoors"), (46, "outdoors"), (272, "outdoors"), (49, "outdoors"),
    (165, "culture"), (247, "culture"), (54, "coffee"), (122, "nightlife"), (248, "nightlife"), (35, "shopping"),
]
CATEGORIES = {
    "fun": {"label": "Fun & games", "symbol": "gamecontroller.fill"},
    "outdoors": {"label": "Parks & trails", "symbol": "tree.fill"},
    "culture": {"label": "Museums & arts", "symbol": "building.columns.fill"},
    "coffee": {"label": "Coffee & hangouts", "symbol": "cup.and.saucer.fill"},
    "nightlife": {"label": "Bars & breweries", "symbol": "wineglass.fill"},
    "shopping": {"label": "Shopping", "symbol": "bag.fill"},
}
# A family-fun listing that is really a park, a cafe or a bar goes to that group instead.
RECAT = [
    (r"\b(park|recreation area|trail|garden|nature|state park|lake|aquatic|pool|farm|lavender|camp)\b", "outdoors"),
    (r"\b(cafe|café|coffee|candy|bakery|tea)\b", "coffee"),
    (r"\b(brewery|brewing|winery|taproom|bar\b|pub\b)", "nightlife"),
    (r"\b(theat(er|re)|cinema|museum|gallery|arts\b|library)\b", "culture"),
    (r"\bmall\b", "shopping"),
]
SKIP = re.compile(r"(?i)\b(tours?|catering|magician|candles|rentals?|planner|senior activity|first fridays|culinary|speaker|panera|starbucks|dunkin|mcdonald|scooter's|casey's|qdoba)\b")
# Directory rows that are not places to go (series, offices, shops for errands) or have closed.
EXCLUDE = {"ancestry guns", "office of cultural affairs", "orchids and art custom framing", "poppy", "wildys world",
           "university concert series", "odyssey chamber music series", "we always swing jazz series", "shilb antiquarian",
           "academy sports", "a y global market", "shiloh bar grill", "the social room", "hooters", "buffalo wild wings",
           "columbia college"}
# Directory rows filed under the wrong group
MOVE = {"witches and wizards arcade": "fun", "billiards on broadway": "fun", "silverball barcade": "fun",
        "the shops at sharp end": "shopping", "shelter gardens": "outdoors", "cooper s landing river port marina": "outdoors"}
TAGS = [
    ("kids", r"(?i)\b(kids?|children|family|families|playground|bounce|trampoline|play cafe|splash)\b"),
    ("free", r"(?i)\b(free (admission|entry|to the public)|admission is free|no admission)\b"),
    ("indoor", r"(?i)\b(indoor|escape room|bowling|arcade|climbing gym|museum|gallery|cinema|theat)\b"),
    ("outdoor", r"(?i)\b(outdoor|trail|park|lake|garden|patio|beer garden|hiking|bike)\b"),
    ("21+", r"(?i)\b(21\+|bar|pub|brewery|brewing|taproom|nightclub|cocktail)\b"),
    ("dogs", r"(?i)\b(dog park|dogs? welcome|dog-friendly|off-leash)\b"),
]
OUT_WEB = os.path.join(ROOT, "docs", "places.json")
OUT_APP = os.path.join(ROOT, "CoMoEvents", "Resources", "places.json")
EXTRA = os.path.join(ROOT, "feed", "places-extra.json")
NOT_WEBSITES = ("visitcolumbiamo.com", "google.com", "discoverthedistrict.com", "como.gov/cultural", "visitmo.com",
                "wpadacompliance", "twitter.com", "facebook.com/visitcolumbiamo", "instagram.com/visitcolumbiamo",
                "pinterest.com", "simpleviewinc", "tripadvisor")


def text(s, n=220):
    t = html.unescape(re.sub(r"<[^>]+>", " ", s or ""))
    t = re.sub(r"\s+", " ", t).strip()
    if len(t) <= n:
        return t
    cut = t[:n]
    end = max(cut.rfind(". "), cut.rfind("! "))
    return (cut[:end + 1] if end > 80 else cut.rsplit(" ", 1)[0] + "…").strip()


def slugify(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")[:60]


def listing_details(link):
    """Address (from the 'Get directions' Google Maps link), website and phone on the listing page."""
    try:
        h = A.get(link).text
    except Exception:
        return None, None, None
    m = re.search(r'https://www\.google\.com/maps/dir/([^"\'\s<]+)', h)
    addr = None
    if m:
        addr = urllib.parse.unquote_plus(m.group(1)).replace("\r", " ").replace("\n", ", ")
        addr = re.sub(r"\s*,\s*", ", ", re.sub(r"\s+", " ", addr)).strip(", ")
        addr = re.sub(r"(?i),?\s*united states$", "", addr).strip(", ")
    site = None
    for u in re.findall(r'href="(https?://[^"]+)"', h):
        if not any(x in u for x in NOT_WEBSITES):
            site = u
            break
    tel = re.search(r'href="tel:([^"]+)"', h)
    return addr, site, (tel.group(1) if tel else None)


def main():
    A.GEOCODE_BUDGET["n"] = 400   # first build looks up every address once; later runs hit the cache
    places, seen = [], set()
    for sec, cat in SECTIONS:
        page = 1
        while True:
            try:
                rows = A.get(API, params={"section": sec, "per_page": 100, "page": page}).json()
            except Exception as e:
                A.log("  places section", sec, "failed:", e); break
            if not isinstance(rows, list) or not rows:
                break
            for r in rows:
                name = html.unescape(r["title"]["rendered"]).strip()
                key = A.norm_key(name)
                plain = re.sub(r"[^a-z0-9]+", " ", name.lower().replace("“", "").replace("”", "")).strip()
                if key in seen or SKIP.search(name) or plain in EXCLUDE:
                    continue
                blurb = text(r.get("excerpt", {}).get("rendered") or r.get("content", {}).get("rendered"))
                c = cat
                if cat == "fun":
                    for rx, other in RECAT:
                        if re.search(rx, name, re.I):
                            c = other
                            break
                c = MOVE.get(plain, c)
                addr, site, phone = listing_details(r["link"])
                if not addr:
                    continue
                g = A.geocode(name, addr if re.search(r"(?i)columbia|mo\b|missouri", addr) else addr + ", Columbia, MO")
                if not g or A.haversine_km((g[0], g[1]), A.DOWNTOWN) > A.RADIUS_KM:
                    continue
                img = None
                og = (r.get("yoast_head_json") or {}).get("og_image") or []
                if og and isinstance(og, list):
                    img = og[0].get("url")
                seen.add(key)
                hay = f"{name} {blurb}"
                places.append({
                    "id": slugify(name), "name": name, "category": c, "address": addr,
                    "lat": round(g[0], 6), "lng": round(g[1], 6), "website": site, "phone": phone,
                    "blurb": blurb, "imageUrl": img, "tags": [t for t, rx in TAGS if re.search(rx, hay)] + (
                        ["free"] if c == "outdoors" and re.search(r"(?i)\b(park|trail|nature|conservation|garden|sanctuary|recreation area)\b", name)
                        and not re.search(r"(?i)\b(golf|aquatic|pool|farm|lavender|camp|marina)\b", name) and not re.search(r"(?i)free", " ".join(t for t, rx in TAGS if re.search(rx, hay))) else []),
                    "source": "visitcolumbia", "link": r["link"],
                })
            if len(rows) < 100:
                break
            page += 1
    try:
        extra = json.load(open(EXTRA)).get("places", [])
    except Exception:
        extra = []
    for p in extra:
        key = A.norm_key(p["name"])
        if key in seen:
            places = [q for q in places if A.norm_key(q["name"]) != key]   # the hand-written row wins
        seen.add(key)
        if p.get("lat") is None:
            g = A.geocode(p["name"], p.get("address"))
            if not g:
                A.log("  places: no pin for", p["name"]); continue
            p["lat"], p["lng"] = round(g[0], 6), round(g[1], 6)
        p.setdefault("id", slugify(p["name"]))
        p.setdefault("source", "comoevents")
        places.append(p)
    A.save_json(A.GEOCACHE_PATH, A.GEOCACHE)
    order = list(CATEGORIES)
    places.sort(key=lambda p: (order.index(p["category"]) if p["category"] in order else 99, p["name"].lower()))
    out = {"generatedAt": dt.datetime.now(A.TZ).isoformat(timespec="seconds"), "categories": CATEGORIES,
           "count": len(places), "places": places}
    for path in (OUT_WEB, OUT_APP):
        with open(path, "w") as f:
            json.dump(out, f, ensure_ascii=False, indent=1)
            f.write("\n")
    by = {}
    for p in places:
        by[p["category"]] = by.get(p["category"], 0) + 1
    print(f"wrote {len(places)} places: {by}")


if __name__ == "__main__":
    main()
