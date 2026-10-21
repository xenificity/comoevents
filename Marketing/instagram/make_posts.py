#!/usr/bin/env python3
"""Render the CoMo Events Instagram grid: 9 posts at 1080x1350 that read as a dark/yellow
checkerboard on the profile, plus grid-preview.png showing how the profile will look.

  python3 Marketing/instagram/make_posts.py

Instagram shows the newest post top-left, so post them in POST_ORDER (01 first, 09 last).
Profile thumbnails are 3:4, which trims about 34 px from each side of a 4:5 post; keep text
inside the 72 px margins. The weekend tile reads scripts/weekly_post.py, so re-render it weekly.
"""
import html, json, os, subprocess, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
OUT = os.path.join(HERE, "grid")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
IMG = "../../../docs/img"
LOGO = "../../../Design/logo"
FONT = "-apple-system,'SF Pro Display','Helvetica Neue',Inter,Arial,sans-serif"

CSS = f"""
*{{box-sizing:border-box}} html,body{{margin:0;width:1080px;height:1350px;overflow:hidden}}
body{{font-family:{FONT};position:relative;-webkit-font-smoothing:antialiased}}
body.dark{{color:#fff;background:#0b0b0f}}
body.dark::before{{content:"";position:absolute;inset:0;background:
 radial-gradient(60% 40% at 8% 4%,rgba(255,214,0,.5),transparent 60%),
 radial-gradient(45% 40% at 98% 35%,rgba(255,64,140,.38),transparent 60%),
 radial-gradient(60% 45% at 50% 110%,rgba(110,70,255,.5),transparent 60%)}}
body.yellow{{color:#121214;background:#FFD600}}
body.yellow::before{{content:"";position:absolute;inset:0;background-image:radial-gradient(rgba(0,0,0,.09) 2.4px,transparent 2.6px);background-size:44px 44px}}
.brand{{position:absolute;left:72px;top:64px;display:flex;align-items:center;gap:16px;font-weight:800;font-size:32px}}
.brand img{{width:64px;height:64px;border-radius:18px;box-shadow:0 10px 26px rgba(0,0,0,.3)}}
h1{{position:absolute;left:72px;right:72px;margin:0;font-weight:900;letter-spacing:-.045em;line-height:.93}}
.y{{color:#FFD600}}
p.lead{{position:absolute;left:72px;margin:0;font-size:34px;line-height:1.3;font-weight:500}}
.dark p.lead{{color:rgba(255,255,255,.75)}} .yellow p.lead{{color:rgba(0,0,0,.7)}}
.phone{{position:absolute;border-radius:58px;overflow:hidden;background:#000}}
.dark .phone{{border:3px solid rgba(255,255,255,.25);box-shadow:0 60px 120px rgba(0,0,0,.65)}}
.yellow .phone{{border:8px solid #121214;box-shadow:0 50px 90px rgba(0,0,0,.35)}}
.phone img{{display:block;width:100%}}
.foot{{position:absolute;left:72px;right:72px;bottom:58px;display:flex;justify-content:space-between;font-size:27px;font-weight:700}}
.dark .foot{{color:rgba(255,255,255,.6)}} .yellow .foot{{color:rgba(0,0,0,.6)}}
.pill{{display:inline-flex;align-items:center;gap:16px;border-radius:999px;padding:16px 32px 16px 16px;font-size:32px;font-weight:800;width:max-content}}
.dark .pill{{background:rgba(255,255,255,.1);border:1.5px solid rgba(255,255,255,.2)}}
.yellow .pill{{background:#121214;color:#fff}}
.pill i{{width:58px;height:58px;border-radius:50%;display:grid;place-items:center;font-style:normal;font-size:30px;background:rgba(255,255,255,.14)}}
"""

def page(kind, body, extra=""):
    return (f"<!doctype html><html><head><meta charset='utf-8'><style>{CSS}{extra}</style></head>"
            f"<body class='{kind}'>{body}</body></html>")

def brand(dark=True):
    return f"<div class='brand'><img src='{IMG}/icon-512.png'>CoMo Events</div>"

# ---------- the nine tiles (named by posting order)

def p01_hero():
    return page("dark", brand() + f"""
    <h1 style='top:190px;font-size:128px;max-width:640px'>Every&shy;thing happening in CoMo.</h1>
    <h1 class='y' style='top:610px;font-size:128px'>One map.</h1>
    <p class='lead' style='top:770px;max-width:480px'>Mizzou, downtown, music, parties, markets. Live and free.</p>
    <div class='phone' style='right:-30px;top:330px;width:430px;transform:rotate(7deg)'><img src='{IMG}/01-map.jpg'></div>
    <div class='foot'><span>comoevent.com</span><span>Link in bio</span></div>""")

def p02_made_here():
    return page("yellow", brand() + f"""
    <h1 style='top:230px;font-size:150px'>Made in Columbia.</h1>
    <p class='lead' style='top:600px;max-width:820px;font-size:40px'>Built by a Mizzou student so nobody in CoMo misses the good stuff.</p>
    <div style='position:absolute;left:72px;right:72px;top:860px;display:grid;grid-template-columns:repeat(3,1fr);gap:20px'>
      {''.join(f"<div style='background:#121214;color:#fff;border-radius:34px;padding:34px 28px'><b style='display:block;font-size:66px;letter-spacing:-.03em;color:#FFD600'>{n}</b><span style='font-size:28px;font-weight:700;opacity:.85'>{t}</span></div>" for n,t in (("1,000+","events listed"),("12","local sources"),("2 hr","refresh")))}
    </div>
    <div class='foot'><span>comoevent.com</span><span>Free · no ads</span></div>""")

def p03_how():
    steps = [("🗺️", "Open the map", "See what's on right now, near you"),
             ("✨", "Filter", "Tonight, weekend, music, food, campus"),
             ("📍", "Go", "Directions, calendar, share with friends")]
    rows = "".join(f"""<div style='display:flex;gap:30px;align-items:center;padding:34px 36px;border-radius:40px;background:rgba(255,255,255,.08);border:1.5px solid rgba(255,255,255,.16)'>
        <div style='flex:none;width:110px;height:110px;border-radius:32px;background:rgba(255,255,255,.14);border:2px solid #FFD600;display:grid;place-items:center;font-size:56px'>{e}</div>
        <div><b style='display:block;font-size:52px;letter-spacing:-.02em'><span class='y'>{i+1}.</span> {t}</b><span style='font-size:31px;opacity:.7'>{s}</span></div></div>"""
        for i, (e, t, s) in enumerate(steps))
    return page("dark", brand() + f"""
    <h1 style='top:180px;font-size:128px'>Open.<br>Filter. <span class='y'>Go.</span></h1>
    <div style='position:absolute;left:72px;right:72px;top:520px;display:flex;flex-direction:column;gap:24px'>{rows}</div>
    <div class='foot'><span>comoevent.com</span><span>How it works</span></div>""")

def p04_free():
    return page("yellow", brand() + f"""
    <h1 style='top:200px;font-size:132px;max-width:560px'>Free on iPhone.</h1>
    <p class='lead' style='top:560px;max-width:520px;font-size:44px;font-weight:800;color:#121214'>And in any browser.</p>
    <div style='position:absolute;left:72px;top:720px;display:flex;flex-direction:column;gap:20px'>
      <span class='pill'><i>📲</i>iPhone app · link in bio</span>
      <span class='pill'><i>🌐</i>comoevent.com</span>
      <span class='pill'><i>🙅</i>No account needed</span>
    </div>
    <div class='phone' style='right:-20px;top:300px;width:400px;transform:rotate(-6deg)'><img src='{IMG}/03-upcoming.jpg'></div>
    <div class='foot'><span>comoevent.com</span><span>Free · no ads</span></div>""")

def p05_logo():
    return page("dark", f"""
    <img src='{LOGO}/logo-mark.png' style='position:absolute;left:50%;top:230px;width:420px;transform:translateX(-50%);filter:drop-shadow(0 40px 60px rgba(0,0,0,.6))'>
    <h1 style='top:830px;text-align:center;font-size:120px'>CoMo <span class='y'>Events</span></h1>
    <p class='lead' style='top:975px;left:0;right:0;text-align:center;font-size:40px'>What's on in Columbia tonight?</p>
    <div class='foot' style='justify-content:center'><span>comoevent.com</span></div>""")

def p06_who():
    words = [("👤", "Singles."), ("💛", "Couples."), ("👯", "Groups."), ("👪", "Family.")]
    rows = "".join(f"<div style='display:flex;align-items:center;gap:26px'><span style='font-size:86px;width:110px;text-align:center'>{e}</span><span>{w}</span></div>" for e, w in words)
    return page("yellow", brand() + f"""
    <div style='position:absolute;left:72px;top:200px;font-size:122px;font-weight:900;letter-spacing:-.045em;line-height:1.08;display:flex;flex-direction:column;gap:6px'>{rows}</div>
    <p class='lead' style='top:880px;max-width:520px;font-size:38px'>One tap filters the whole town to the night you want.</p>
    <div class='phone' style='right:-10px;top:440px;width:330px;transform:rotate(6deg)'><img src='{IMG}/02-party.jpg'></div>
    <div class='foot'><span>comoevent.com</span><span>Who's it for? You.</span></div>""")

def p07_tap():
    return page("dark", brand() + f"""
    <h1 style='top:190px;font-size:136px;max-width:560px'>Tap a pin.<br><span class='y'>Just go.</span></h1>
    <div style='position:absolute;left:72px;top:640px;display:flex;flex-direction:column;gap:18px'>
      <span class='pill'><i>🕗</i>Time and place</span>
      <span class='pill'><i>🧭</i>One-tap directions</span>
      <span class='pill'><i>🎟️</i>Tickets and organizer</span>
      <span class='pill'><i>🙋</i>See who's going</span>
    </div>
    <div class='phone' style='right:-40px;top:300px;width:430px;transform:rotate(6deg)'><img src='{IMG}/04-detail.jpg'></div>
    <div class='foot'><span>comoevent.com</span><span>Link in bio</span></div>""")

def p08_post():
    field = lambda label, value: (f"<div style='border-bottom:2px solid #eee;padding:22px 0'><small style='display:block;font-size:24px;color:#8a8a93;font-weight:700'>{label}</small>"
                                  f"<span style='font-size:36px;font-weight:800'>{value}</span></div>")
    card = f"""<div style='position:absolute;left:72px;right:72px;top:600px;background:#fff;border-radius:44px;padding:20px 44px 36px;box-shadow:0 40px 80px rgba(0,0,0,.25)'>
      {field('Event', 'Open mic night 🎤')}{field('When', 'Fri · 8 pm')}{field('Where', 'Downtown CoMo')}
      <div style='display:flex;align-items:center;gap:16px;margin-top:28px;font-size:30px;font-weight:700;color:#55555e'>
        <span style='font-size:40px'>✨</span>We add the pin, directions and contact.</div></div>"""
    return page("yellow", brand() + f"""
    <h1 style='top:190px;font-size:128px'>Got an event?</h1>
    <h1 style='top:330px;font-size:128px'>Post it free.</h1>
    <p class='lead' style='top:480px;font-size:36px'>Student orgs, venues, anyone. Three fields.</p>
    {card}
    <div class='foot'><span>comoevent.com</span><span>Profile → Post an event</span></div>""")

EMOJI = {"party": "🎉", "music": "🎵", "nightlife": "🌙", "food": "🍴", "arts": "🎭",
         "sports": "🏟️", "family": "👨‍👩‍👧", "campus": "🎓", "community": "📍"}

def p09_weekend():
    picks = json.loads(subprocess.check_output([sys.executable, os.path.join(ROOT, "scripts", "weekly_post.py"), "--json", "--count", "6"]))
    first, last = picks[0]["start"][:10], picks[-1]["start"][:10]
    import datetime as dt
    a, b = dt.date.fromisoformat(first), dt.date.fromisoformat(last)
    rng = f"{a:%b} {a.day}–{b.day}" if a.month == b.month else f"{a:%b} {a.day} – {b:%b} {b.day}"
    rows = ""
    for p in picks:
        t = p["title"]; t = t if len(t) <= 30 else t[:28].rstrip(" -–:") + "…"
        v = p.get("venue") or ""; v = v if len(v) <= 34 else v[:32].rstrip() + "…"
        rows += f"""<div style='display:flex;align-items:center;gap:24px;padding:15px 24px;border-radius:30px;background:rgba(255,255,255,.08);border:1.5px solid rgba(255,255,255,.15)'>
          <div style='flex:none;width:76px;height:76px;border-radius:24px;background:#FFD600;display:grid;place-items:center;font-size:38px'>{EMOJI.get(p.get('category'), '📍')}</div>
          <div style='flex:1;min-width:0'><b style='display:block;font-size:34px;letter-spacing:-.01em;white-space:nowrap;overflow:hidden'>{html.escape(t)}</b>
            <span style='display:block;font-size:25px;opacity:.6;white-space:nowrap;overflow:hidden'>{html.escape(v)}</span></div>
          <div style='font-size:28px;font-weight:800;color:#FFD600;white-space:nowrap'>{html.escape(p.get('when', ''))}</div></div>"""
    return page("dark", brand() + f"""
    <h1 style='top:170px;font-size:108px'>This weekend<br><span class='y'>in CoMo</span></h1>
    <p class='lead' style='top:388px'>{rng} · our picks</p>
    <div style='position:absolute;left:72px;right:72px;top:462px;display:flex;flex-direction:column;gap:12px'>{rows}</div>
    <div class='foot'><span>comoevent.com</span><span>Everything else: link in bio</span></div>""")

POST_ORDER = [p01_hero, p02_made_here, p03_how, p04_free, p05_logo, p06_who, p07_tap, p08_post, p09_weekend]

def render(name, markup):
    h = os.path.join(OUT, f"{name}.html"); png = os.path.join(OUT, f"{name}.png"); jpg = os.path.join(OUT, f"{name}.jpg")
    open(h, "w").write(markup)
    subprocess.run([CHROME, "--headless=new", f"--screenshot={png}", "--window-size=1080,1350", "--hide-scrollbars",
                    "--allow-file-access-from-files", f"file://{h}"], stderr=subprocess.DEVNULL, check=True)
    Image.open(png).convert("RGB").save(jpg, quality=92); os.remove(png)
    return jpg

def preview(jpgs):
    """How the profile grid looks: newest top-left, 3:4 thumbnails."""
    cell_w, cell_h, gap = 360, 480, 3
    grid = Image.new("RGB", (cell_w * 3 + gap * 2, cell_h * 3 + gap * 2), (0, 0, 0))
    for i, j in enumerate(reversed(jpgs)):
        im = Image.open(j); sc = cell_h / im.height
        im = im.resize((round(im.width * sc), cell_h), Image.LANCZOS)
        off = (im.width - cell_w) // 2; im = im.crop((off, 0, off + cell_w, cell_h))
        grid.paste(im, ((i % 3) * (cell_w + gap), (i // 3) * (cell_h + gap)))
    grid.save(os.path.join(OUT, "grid-preview.jpg"), quality=90)

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    jpgs = [render(f"{i:02d}-{fn.__name__.split('_', 1)[1].replace('_', '-')}", fn()) for i, fn in enumerate(POST_ORDER, 1)]
    preview(jpgs)
    for j in jpgs: print("wrote", os.path.relpath(j, ROOT))
    print("wrote Marketing/instagram/grid/grid-preview.jpg")
