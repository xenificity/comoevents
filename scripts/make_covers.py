#!/usr/bin/env python3
"""Cover pictures for events that have none, made from the event itself.

Runs after feed/aggregate.py (scripts/update-feed.sh and the feed workflow). For every upcoming event
(next DAYS days) without a picture it picks motifs from the title, tags and category (a diya for a
puja, a saxophone for jazz, a robot for an AI talk), colours from the category, and a big faint
keyword from the title, renders that with headless Chrome and saves docs/img/gen/<key>.webp.
The event's imageUrl then points there, with "imageGenerated": true.

Covers are art only, no title text: the app and the site already lay the title over the bottom of
every picture. One cover per title + venue + motif, so a weekly class reuses its cover; covers no
event uses any more are deleted. Artwork: Twemoji (CC-BY 4.0), cached in feed/assets/twemoji/.

  python3 scripts/make_covers.py [--days 60] [--max 250] [--force]
"""
import argparse, base64, colorsys, hashlib, html, json, os, re, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

import io, urllib.parse

import requests
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FEED = os.path.join(ROOT, "feed", "events.json")
OUT_DIR = os.path.join(ROOT, "docs", "img", "gen")
EMOJI_DIR = os.path.join(ROOT, "feed", "assets", "twemoji")
SIZE_CACHE = os.path.join(ROOT, "feed", "cache", "imagesize.json")
MIN_W, MIN_H = 700, 300        # smaller photos look blurry on a phone card; they get a cover instead
HEAVY = 900_000                # bigger originals are resized into docs/img/gen/p-*.webp
OUT_W = 1800                   # covers are drawn at 2x and saved 1800 px wide: sharp on the iPhone detail header
FONT = os.path.join(ROOT, "feed", "assets", "fonts", "ArchivoBlack.woff2")
SITE = "https://comoevent.com"
TWEMOJI = "https://cdn.jsdelivr.net/gh/jdecked/twemoji@15.1.0/assets/svg/{}.svg"
VERSION = "v4"   # bump to redraw every cover after changing the design
W, H = 1200, 630

# Title (and venue) keywords → motifs, first match wins. Three emoji: the hero and two accents.
MOTIFS = [
    (r"durga|diwali|deepavali|lakshmi|laxmi|pooja|puja|aarti|archana|kumkuma|abhishekam|navratri|garba|dandiya", "🪔🌺🕉️"),
    (r"bhajan|gita|bhagwad|bhagavad|satsang|sai |shiva|krishna|rama|hanuman|anjaneya|ganesh|mandir|hindu", "🕉️🪔🌼"),
    (r"bible|church|worship|mass\b|gospel|ministry|fellowship|devotional|chi alpha|christian|chapel|sermon", "⛪🕊️✨"),
    (r"mosque|masjid|islam|muslim|ramadan|iftar|eid|jumm?ah", "🕌🌙✨"),
    (r"shabbat|hanukk?ah|chanukk?ah|jewish|synagogue|hillel|passover", "🕎✡️✨"),
    (r"buddhis|zen|dharma|sangha", "☸️🪷✨"),
    (r"meditat|mindful|yoga|breathwork|sound bath|reiki", "🧘🪷✨"),
    (r"\bai\b|a\.i\.|artificial intelligence|chatgpt|machine learning|\bllm|generative", "🤖💡✨"),
    (r"robot|sphero|lego|stem\b|coding|hackathon|program", "🤖⚙️🧩"),
    (r"3d print|makerspace|maker faire|cad\b", "🖨️⚙️🧩"),
    (r"data|gis\b|arcgis|map", "📊🗺️💡"),
    (r"tech|device|computer|digital|canva|excel|software|cyber|app\b|website", "💻📱💡"),
    (r"science|physics|chemistry|biology|lab\b|astronom|stargaz|telescope|planetarium", "🔬🔭🧪"),
    (r"vaccin|clinic|flu shot|health|medical|blood pressure|wellness check|nurse|doctor|dental|hospital", "🩺💉❤️"),
    (r"halloween|spooky|haunted|boo\b|zombie|costume|monster|trick.or.treat|trunk.or.treat|dia de|día de|muertos", "🎃👻🍬"),
    (r"pumpkin", "🎃🍂🌾"),
    (r"christmas|holiday|santa|nutcracker|tree lighting|wassail", "🎄🎁✨"),
    (r"thanksgiving|harvest|turkey", "🦃🍂🥧"),
    (r"new year", "🎆🥂✨"),
    (r"valentine|date night|romantic", "💘🌹🥂"),
    (r"pride|drag|lgbt|queer", "🏳️‍🌈🌈✨"),
    (r"football|tailgate|game day", "🏈🏟️🐯"),
    (r"basketball", "🏀🏟️🐯"),
    (r"volleyball", "🏐🏟️🐯"),
    (r"soccer", "⚽🏟️🐯"),
    (r"softball", "🥎🏟️🐯"),
    (r"baseball", "⚾🏟️🐯"),
    (r"wrestling", "🤼🏟️🐯"),
    (r"golf", "⛳🏌️🌤️"),
    (r"tennis|pickleball", "🎾🏓🌤️"),
    (r"swim", "🏊💧🌊"),
    (r"gymnastic", "🤸🏅✨"),
    (r"\brun\b|5k|10k|marathon|race|running", "🏃🏅👟"),
    (r"bike|cycling|biking", "🚴🌳🏅"),
    (r"hike|hiking|trail|nature|bird|garden|plant|botanic", "🌿🦋🌼"),
    (r"comedy|comedian|stand.?up|improv", "😂🎤✨"),
    (r"trivia|quiz", "🧠❓🏆"),
    (r"magic|commander|pok[eé]mon|lorcana|tcg|card game|gundam|one piece|weekly play|gym leader", "🃏🐉✨"),
    (r"board game|game night|gamer|chess|d&d|dungeons|bingo", "🎲♟️🧩"),
    (r"sew|quilt|knit|crochet|craft|fiber", "🧵🪡🧶"),
    (r"pottery|ceramic|clay", "🏺🎨✨"),
    (r"history|historic|heritage|hall of fame", "🏛️📜✨"),
    (r"climb|bouldering|skate|roller", "🧗🏅✨"),
    (r"jazz|swing", "🎷🎺🎶"),
    (r"piano|keyboard|instrument", "🎹🎶✨"),
    (r"symphony|orchestra|strings|violin|cello|chamber|quartet|ensemble|philharmonic", "🎻🎼🎶"),
    (r"choir|choral|sing|vocal|voice|opera|recital", "🎤🎼🎶"),
    (r"brass|trumpet|trombone|horn|tuba|euphonium|band\b", "🎺🎶🥁"),
    (r"guitar|acoustic|folk|bluegrass|country|songwriter", "🎸🎶🤠"),
    (r"dj|edm|rave|club|dance party|disco|afrobeat|latin night|bollywood", "🪩🎧💃"),
    (r"karaoke|open mic", "🎤🎶✨"),
    (r"concert|live music|tour|show", "🎸🎤🎶"),
    (r"dance|ballet|contra|swing|salsa|ballroom", "💃🩰✨"),
    (r"theat|play\b|musical|broadway|stage", "🎭🎟️✨"),
    (r"film|movie|cinema|screening|documentary", "🎬🍿🎞️"),
    (r"story ?time|storytime|book|read|author|poetry|library|writing|literary", "📚📖✨"),
    (r"lecture|talk|seminar|colloquium|symposium|panel|conference|keynote", "🎤💡📚"),
    (r"career|job|resume|internship|networking|professional|leadership|business", "💼🤝📈"),
    (r"workshop|class|course|training|lesson|bootcamp|studio", "🛠️💡✏️"),
    (r"paint|art|gallery|exhibit|museum|photograph|sculpt|first friday", "🎨🖼️✨"),
    (r"coffee|cafe", "☕🥐✨"),
    (r"beer|brew|pub", "🍺🍻✨"),
    (r"wine|tasting|cocktail", "🍷🥂✨"),
    (r"market|farmers|vendor|bazaar|sale|fair\b", "🧺🍎🌻"),
    (r"breakfast|pancake|brunch", "🥞☕🍓"),
    (r"bbq|barbecue|chili|taco|pizza|dinner|dining|lunch|food|cook|bake|potluck|picnic", "🍽️🥘✨"),
    (r"volunteer|donat|charity|fundraiser|blood drive|toys for tots|food drive|benefit", "🤝💛🎁"),
    (r"kid|child|toddler|baby|family|teen|youth|puppet", "🧸🎈🖍️"),
    (r"puppy|dog|cat\b|pet|animal|humane", "🐶🐾💛"),
    (r"graduat|commencement", "🎓🎉✨"),
    (r"festival|fest\b|celebrat|parade|party|gala|bash", "🎉🎊✨"),
]
CATEGORY_MOTIF = {"party": "🎉🎊✨", "music": "🎵🎶🎤", "nightlife": "🌙🍸✨", "food": "🍽️🥘✨", "arts": "🎨🎭✨",
                  "sports": "🏅🏟️🐯", "family": "🧸🎈🖍️", "campus": "🎓📚🐯", "religious": "🕊️✨🙏", "community": "🏘️🤝✨"}
# Two-tone backgrounds per category (deeper than the pin colours so white art stands out).
COLORS = {"party": ("#ff3d8b", "#7b1fa2"), "music": ("#7c4dff", "#311b92"), "nightlife": ("#3d3bb8", "#0b0c3d"),
          "food": ("#ff6b3d", "#b71c1c"), "arts": ("#00b3bf", "#0d4f73"), "sports": ("#ffa31a", "#c2410c"),
          "family": ("#34d399", "#0f766e"), "campus": ("#fcd34d", "#d97706"), "religious": ("#c79a5b", "#5b3a1e"),
          "community": ("#3b82f6", "#1e3a8a")}
STOP = set("the a an and or of at in on for with to from by your our my this that live presents presented "
           "featuring feat ft vs night day event events columbia mo como missouri mu mizzou 2026 2027 new "
           "annual fall spring winter summer weekly session part edition free".split())


def emoji_code(e):
    cps = [f"{ord(c):x}" for c in e]
    if "200d" not in cps:
        cps = [c for c in cps if c != "fe0f"]
    return "-".join(cps)


def emoji_svg(e):
    """Twemoji SVG for one emoji, from the repo cache or jsDelivr (then cached)."""
    os.makedirs(EMOJI_DIR, exist_ok=True)
    code = emoji_code(e)
    path = os.path.join(EMOJI_DIR, code + ".svg")
    if not os.path.exists(path):
        r = requests.get(TWEMOJI.format(code), timeout=20)
        r.raise_for_status()
        with open(path, "wb") as f:
            f.write(r.content)
    with open(path, "rb") as f:
        return "data:image/svg+xml;base64," + base64.b64encode(f.read()).decode()


def split_emoji(s):
    out, cur = [], ""
    for ch in s:
        if cur and (ord(ch) in (0xFE0F, 0x200D) or cur.endswith("‍")):
            cur += ch
        else:
            if cur:
                out.append(cur)
            cur = ch
    if cur:
        out.append(cur)
    return out


def pick_motif(e):
    # Title first ("Vaccination Clinic" at the library is a health event), then the venue, then the
    # feed's strong concept tags (hindu, tech, comedy, …; "x~" description-only tags are too loose).
    for text in ((e.get("title") or "").lower(), (e.get("venue") or "").lower(),
                 " ".join(t for t in (e.get("tags") or []) if not t.endswith("~"))):
        for rx, m in MOTIFS:
            if re.search(rf"(?<![a-z])(?:{rx})", text):
                return m
    cats = e.get("categories") or [e.get("category") or "community"]
    return CATEGORY_MOTIF.get(cats[0], CATEGORY_MOTIF["community"])


def keyword(e):
    words = re.findall(r"[A-Za-z][A-Za-z'’&-]+", e.get("title") or "")
    good = [w for w in words if w.lower() not in STOP and len(w) >= 3]
    if not good:
        return ""
    w = max(good[:6], key=len)   # the longest of the first few: usually the subject (JAZZ, PUJA, ROBOTS)
    return w.upper().replace("’", "'")[:12]


def shade(hex_, f, rot=0.0):
    r, g, b = (int(hex_[i:i + 2], 16) / 255 for i in (1, 3, 5))
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    r, g, b = colorsys.hls_to_rgb((h + rot) % 1, max(0, min(1, l * f)), s)
    return "#%02x%02x%02x" % (int(r * 255), int(g * 255), int(b * 255))


PAGE_CSS = """
html,body{margin:0;width:%dpx;overflow:hidden;background:#000}
.cv{position:relative;width:%dpx;height:%dpx;overflow:hidden}
.cv>*{position:absolute}
.bg{inset:0}
.pat{inset:0;-webkit-mask-image:linear-gradient(100deg,transparent 15%%,#000 70%%)}
.word{left:-14px;top:18px;font:200px/0.86 P,sans-serif;letter-spacing:-6px;color:transparent;
  -webkit-text-stroke:3px rgba(255,255,255,.22);white-space:nowrap;transform:rotate(-5deg);transform-origin:0 0}
.sun{left:470px;top:20px;width:520px;height:520px;border-radius:50%%;
  background:radial-gradient(rgba(255,255,255,.55),rgba(255,255,255,.12) 45%%,transparent 68%%)}
.ring{border-radius:50%%;border:3px solid rgba(255,255,255,.22)}
.cv img{filter:drop-shadow(0 22px 26px rgba(0,0,0,.32))}
.hero{left:560px;top:95px;width:340px;height:340px}
.a1{left:935px;top:70px;width:130px;height:130px;opacity:.96}
.a2{left:430px;top:330px;width:115px;height:115px;opacity:.96}
.a3{left:1010px;top:390px;width:80px;height:80px;opacity:.5;transform:rotate(18deg)}
""" % (W, W, H)
PATTERNS = ["radial-gradient(rgba(255,255,255,.13) 2px,transparent 2.6px) 0 0/30px 30px",
            "repeating-linear-gradient(-35deg,rgba(255,255,255,.07) 0 14px,transparent 14px 34px)",
            "radial-gradient(circle at 50% 50%,transparent 0 46px,rgba(255,255,255,.08) 47px 50px,transparent 51px) 0 0/120px 120px"]


def cover_block(e, motif):
    """One 1200x630 cover as a block of the batch page."""
    cat = (e.get("categories") or [e.get("category") or "community"])[0]
    c1, c2 = COLORS.get(cat, COLORS["community"])
    seed = int(hashlib.sha1((e.get("title") or "").encode()).hexdigest()[:8], 16)
    rot = ((seed % 21) - 10) / 360            # small hue shift so two arts events don't look identical
    c1, c2 = shade(c1, 1.0, rot), shade(c2, 1.0, rot)
    tilt = (seed >> 5) % 14 - 7
    hero, a1, a2 = (split_emoji(motif) + ["✨", "✨"])[:3]
    return (f'<div class="cv"><div class="bg" style="background:radial-gradient(circle at 62% 38%,{shade(c1, 1.25)} 0,transparent 58%),'
            f'linear-gradient(135deg,{c1},{c2})"></div><div class="pat" style="background:{PATTERNS[(seed >> 9) % 3]}"></div>'
            f'<div class="word">{html.escape(keyword(e))}</div><div class="sun"></div>'
            f'<div class="ring" style="left:520px;top:55px;width:420px;height:420px"></div>'
            f'<div class="ring" style="left:900px;top:30px;width:210px;height:210px;opacity:.6"></div>'
            f'<img class="a3" src="{emoji_svg(a1)}"><img class="a1" style="transform:rotate({12 - tilt}deg)" src="{emoji_svg(a1)}">'
            f'<img class="a2" style="transform:rotate({-14 + tilt}deg)" src="{emoji_svg(a2)}">'
            f'<img class="hero" style="transform:rotate({tilt}deg)" src="{emoji_svg(hero)}"></div>')


def batch_html(blocks, font_b64):
    return (f'<!doctype html><html><head><meta charset="utf-8"><style>@font-face{{font-family:P;src:url(data:font/woff2;base64,'
            f'{font_b64}) format("woff2")}}{PAGE_CSS}</style></head><body>{"".join(blocks)}</body></html>')


def find_chrome():
    for c in (os.environ.get("CHROME"), shutil.which("google-chrome"), shutil.which("google-chrome-stable"),
              shutil.which("chromium"), shutil.which("chromium-browser"),
              "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"):
        if c and os.path.exists(c):
            return c
    return None


def render(chrome, page, png, height=H):
    # Own throwaway profile: sharing the user's Chrome profile makes every call wait ~30 s.
    profile = tempfile.mkdtemp(prefix="chrome-")
    try:
        _render(chrome, page, png, profile, height)
    finally:
        shutil.rmtree(profile, ignore_errors=True)


def _render(chrome, page, png, profile, height):
    subprocess.run([chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars", "--no-sandbox",
                    f"--user-data-dir={profile}", "--no-first-run", "--no-default-browser-check",
                    "--disable-extensions", "--disable-background-networking", "--disable-sync",
                    "--force-device-scale-factor=2", f"--window-size={W},{height}",
                    f"--screenshot={png}", "file://" + page], check=True, capture_output=True, timeout=150)


# ---------- photos: ask sources for their big version, measure, drop the ones that stay small ----------
UA = {"User-Agent": "CoMoEvents/1.0 (+https://comoevent.com)"}


def better_url(u):
    """The source's full-size version of a thumbnail URL."""
    if "calendar.missouri.edu/live/image/" in u:              # LiveWhale: 80x80 crop → native size
        return re.sub(r"/width/\d+/height/\d+/crop/\d+/", "/width/1600/", u)
    if "cdn-ip.allevents.in/" in u:                            # imgproxy: 500x250 → 1200x600
        return re.sub(r"rs:fill:\d+:\d+", "rs:fill:1200:600", u)
    if "img.evbuc.com/" in u:                                  # signed resizer: use the original behind it
        return urllib.parse.unquote(u.split("img.evbuc.com/", 1)[1].split("?", 1)[0])
    return u


def probe(u, cache):
    """[width, height, bytes] of an image (bytes 0 if unknown), cached by URL; None if unreadable."""
    if u in cache:
        return cache[u]
    out = None
    try:
        r = requests.get(u, headers=dict(UA, Range="bytes=0-131071"), timeout=20)
        if r.status_code in (200, 206):
            total = r.headers.get("Content-Range", "").rsplit("/", 1)[-1]
            n = int(total) if total.isdigit() else int(r.headers.get("Content-Length") or 0)
            try:
                w, h = Image.open(io.BytesIO(r.content)).size
            except Exception:   # header past the first 128 KB: fetch it all
                r = requests.get(u, headers=UA, timeout=30)
                w, h = Image.open(io.BytesIO(r.content)).size
                n = len(r.content)
            out = [w, h, n]
    except Exception:
        out = None
    cache[u] = out
    return out


def fix_photos(events, used):
    """Sharpen or replace event photos in place. Returns (upgraded, replaced, resized) counts."""
    cache = json.load(open(SIZE_CACHE)) if os.path.exists(SIZE_CACHE) else {}
    todo = {e["imageUrl"] for e in events if e.get("imageUrl") and not e.get("imageGenerated")}
    with ThreadPoolExecutor(max_workers=10) as pool:
        list(pool.map(lambda u: (probe(better_url(u), cache), probe(u, cache) if better_url(u) != u else None), todo))
    up = repl = resized = 0
    for e in events:
        u = e.get("imageUrl")
        if not u or e.get("imageGenerated"):
            continue
        b = better_url(u)
        dims = cache.get(b) or (cache.get(u) if b != u else None)
        if b != u and not cache.get(b):
            b = u
        if not dims:
            continue                          # can't read it: leave as is
        w, h, n = dims
        if w < MIN_W or h < MIN_H:
            e.pop("imageUrl"); e["photoTooSmall"] = True; repl += 1   # make_covers draws one
            continue
        if n > HEAVY:
            key = "p-" + hashlib.sha1(b.encode()).hexdigest()[:14]
            path = os.path.join(OUT_DIR, key + ".webp")
            if not os.path.exists(path):
                try:
                    im = Image.open(io.BytesIO(requests.get(b, headers=UA, timeout=40).content)).convert("RGB")
                    im.thumbnail((1600, 1600), Image.LANCZOS)
                    im.save(path, "WEBP", quality=80, method=6)
                    resized += 1
                except Exception:
                    continue
            e["imageUrl"] = f"{SITE}/img/gen/{key}.webp"; used.add(key)
            continue
        if b != u:
            e["imageUrl"] = b; up += 1
    os.makedirs(os.path.dirname(SIZE_CACHE), exist_ok=True)
    keep = {k: v for k, v in cache.items() if v is not None}
    with open(SIZE_CACHE, "w") as f:
        json.dump(keep, f, separators=(",", ":"), sort_keys=True)
    return up, repl, resized


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--days", type=int, default=60)
    ap.add_argument("--max", type=int, default=250, help="most covers to draw in one run")
    ap.add_argument("--force", action="store_true", help="redraw covers that already exist")
    args = ap.parse_args()

    with open(FEED) as f:
        feed = json.load(f)
    now = datetime.now(timezone.utc)
    horizon = now + timedelta(days=args.days)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(FONT, "rb") as f:
        font_b64 = base64.b64encode(f.read()).decode()

    todo, used = {}, set()
    up, repl, resized = fix_photos(feed["events"], used)
    print(f"make_covers: photos: {up} switched to the full-size version, {repl} too small (cover instead), {resized} resized")
    for e in feed["events"]:
        if e.get("imageUrl") and not e.get("imageGenerated"):
            continue
        e.pop("imageUrl", None); e.pop("imageGenerated", None)
        start = datetime.fromisoformat(e["start"])
        end = datetime.fromisoformat(e["end"]) if e.get("end") else start
        if end < now or start > horizon:
            continue
        motif = pick_motif(e)
        key = hashlib.sha1(f"{VERSION}|{(e.get('title') or '').strip().lower()}|{(e.get('venue') or '').lower()}|{motif}".encode()).hexdigest()[:14]
        path = os.path.join(OUT_DIR, key + ".webp")
        if args.force or not os.path.exists(path):
            todo.setdefault(key, (e, motif))
        if os.path.exists(path) or key in todo:
            e["imageUrl"] = f"{SITE}/img/gen/{key}.webp"
            e["imageGenerated"] = True
            used.add(key)

    chrome = find_chrome()
    made = 0
    if todo and not chrome:
        print("make_covers: no Chrome found; skipping drawing", file=sys.stderr)
    elif todo:
        items = list(todo.items())[:args.max]
        tmp = tempfile.mkdtemp(prefix="covers-")

        # One Chrome launch draws BATCH covers stacked on a tall page; Pillow cuts them apart.
        # (A Chrome per cover is ~8 s each on a Mac; a batch of 20 takes about as long as one.)
        BATCH = 10
        batches = [items[i:i + BATCH] for i in range(0, len(items), BATCH)]

        def one(n_batch):
            n, batch = n_batch
            page, png = os.path.join(tmp, f"b{n}.html"), os.path.join(tmp, f"b{n}.png")
            with open(page, "w") as f:
                f.write(batch_html([cover_block(e, motif) for _, (e, motif) in batch], font_b64))
            for attempt in range(2):   # headless Chrome occasionally hangs; one retry, then skip the batch
                try:
                    render(chrome, page, png, H * len(batch))
                    sheet = Image.open(png).convert("RGB")
                    k = sheet.width / W   # 2 (device scale factor)
                    for i, (key, _) in enumerate(batch):
                        tile = sheet.crop((0, round(i * H * k), sheet.width, round((i + 1) * H * k)))
                        tile.resize((OUT_W, round(OUT_W * H / W)), Image.LANCZOS).save(
                            os.path.join(OUT_DIR, key + ".webp"), "WEBP", quality=78, method=6)
                    return len(batch)
                except Exception as x:
                    err = x
            print(f"make_covers: batch {n} failed: {str(err)[:160]}", file=sys.stderr)
            return 0

        with ThreadPoolExecutor(max_workers=2) as pool:
            made = sum(pool.map(one, enumerate(batches)))
        shutil.rmtree(tmp, ignore_errors=True)
        # Covers past --max wait for the next run: don't point events at files that don't exist yet.
        missing = {k for k in todo if not os.path.exists(os.path.join(OUT_DIR, k + ".webp"))}
        for e in feed["events"]:
            if e.get("imageGenerated") and e["imageUrl"].rsplit("/", 1)[-1][:-5] in missing:
                e.pop("imageUrl"); e.pop("imageGenerated")
        used -= missing

    removed = 0
    for name in os.listdir(OUT_DIR):
        if name.endswith(".webp") and name[:-5] not in used:
            os.remove(os.path.join(OUT_DIR, name)); removed += 1

    with open(FEED, "w") as f:
        json.dump(feed, f, ensure_ascii=False, separators=(",", ":"))
    print(f"make_covers: {len(used)} covers in use, {made} drawn, {removed} removed")


if __name__ == "__main__":
    main()
