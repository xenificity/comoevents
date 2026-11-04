#!/usr/bin/env python3
"""CoMo Events T-shirt: print files (300 DPI, transparent PNG) and two QR codes, plus a mockup sheet.

Layouts (nothing fills the shirt):
  A  front only: logo, then the two QR codes side by side. One print side, so cheapest.
  B  front: small chest logo. Back: the two QR codes.
Colours: on a white shirt everything prints straight on it; on a black shirt each QR sits on a white
tile, because a scanner needs dark squares on a light background and a quiet margin around them.

  python3 Design/tshirt/make_tshirt.py   (needs reportlab, Pillow, Google Chrome)
"""
import os, shutil, subprocess, tempfile
import reportlab.graphics.barcode.qrencoder as qe

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "print")
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
APP_URL = "https://apps.apple.com/app/como-events/id6824363992"
WEB_URL = "https://comoevent.com/"
DPI = 300
YELLOW, INK = "#FFD600", "#121214"
FONT = "-apple-system,'SF Pro Display','Helvetica Neue',Helvetica,Arial,sans-serif"


def matrix(text):
    q = qe.QRCode(None, qe.QRErrorCorrectLevel.Q)   # Q: survives fabric texture and a little wear
    q.addData(text); q.make()
    n = q.getModuleCount()
    return [[bool(q.isDark(r, c)) for c in range(n)] for r in range(n)]


def qr_svg(text, x, y, size, color=INK, tile=None):
    """QR at (x, y) with `size` the code itself; a white tile adds the 4-module quiet margin around it."""
    m = matrix(text); n = len(m); s = size / n
    d = "".join(f"M{c} {r}h1v1h-1z" for r in range(n) for c in range(n) if m[r][c])
    pad = s * 4
    bg = f'<rect x="{x-pad:.1f}" y="{y-pad:.1f}" width="{size+2*pad:.1f}" height="{size+2*pad:.1f}" rx="{pad*.6:.1f}" fill="{tile}"/>' if tile else ""
    return bg + f'<path transform="translate({x:.2f},{y:.2f}) scale({s:.4f})" shape-rendering="crispEdges" fill="{color}" d="{d}"/>'


def pin(x, y, h, body, lens, pupil):
    """The CoMo Events pin, flat colours for printing. `h` is its height."""
    k = h / 250
    return (f'<g transform="translate({x:.1f},{y:.1f}) scale({k:.4f}) translate(-20,0)">'
            f'<path d="M100,250 L32.3,142.7 A80,80 0 1 1 167.7,142.7 Z" fill="{body}"/>'
            f'<circle cx="100" cy="100" r="50" fill="{lens}"/><circle cx="100" cy="100" r="22" fill="{pupil}"/></g>')


def wordmark(x, y, size, color, anchor="start"):
    return f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="{FONT}" font-size="{size}" font-weight="800" letter-spacing="-{size*0.012:.1f}" fill="{color}">CoMo Events</text>'


def label(x, y, text, size, color, weight=600):
    return f'<text x="{x}" y="{y}" text-anchor="middle" font-family="{FONT}" font-size="{size}" font-weight="{weight}" fill="{color}">{text}</text>'


def colours(shirt):
    if shirt == "white":
        return dict(fg=INK, body=INK, lens=YELLOW, pupil=INK, tile=None, qr=INK, sub="#55555c")
    return dict(fg="#ffffff", body=YELLOW, lens=INK, pupil=YELLOW, tile="#ffffff", qr=INK, sub="#d8d8dc")


def two_qrs(c, top, W):
    """Two 3-inch codes side by side with a label under each. Returns (svg, bottom y)."""
    q, gap = 3 * DPI, int(1.1 * DPI)
    left = (W - 2 * q - gap) / 2; right = left + q + gap
    y = top
    s = qr_svg(APP_URL, left, y, q, c["qr"], c["tile"]) + qr_svg(WEB_URL, right, y, q, c["qr"], c["tile"])
    ly = y + q + (0.62 * DPI if c["tile"] else 0.42 * DPI)
    s += label(left + q / 2, ly, "Get the iPhone app", 80, c["fg"], 700) + label(right + q / 2, ly, "comoevent.com", 80, c["fg"], 700)
    return s, ly + 40


def layout_a(c):   # front only, 8 x 6.6 in
    W = 8 * DPI; H = int(6.6 * DPI)
    ph = 300; word = 190
    tw = word * 5.75   # rough wordmark width, to centre pin + name as a group
    x0 = (W - (ph * .68 + 50 + tw)) / 2
    s = pin(x0, 30, ph, c["body"], c["lens"], c["pupil"]) + wordmark(x0 + ph * .68 + 50, 30 + ph * .66, word, c["fg"])
    q, _ = two_qrs(c, 30 + ph + 190, W)
    return W, H, s + q


def layout_b_front(c):   # chest logo, 3.6 in wide
    W = int(3.6 * DPI); H = int(1.3 * DPI)
    ph = 340
    s = pin(8, 20, ph, c["body"], c["lens"], c["pupil"]) + wordmark(ph * .68 + 40, 145, 118, c["fg"]) + \
        f'<text x="{ph*.68+42}" y="280" font-family="{FONT}" font-size="66" font-weight="600" fill="{c["sub"]}">Columbia, MO</text>'
    return W, H, s


def layout_b_back(c):   # two QRs, 8 x 4 in
    W = 8 * DPI; H = int(4.1 * DPI)
    q, _ = two_qrs(c, 150, W)
    return W, H, q


def render(jobs):
    tmp = tempfile.mkdtemp(prefix="tee-")
    prof = tempfile.mkdtemp(prefix="chrome-")
    for name, (W, H, body) in jobs.items():
        page = os.path.join(tmp, name + ".html")
        with open(page, "w") as f:
            f.write(f'<!doctype html><meta charset="utf-8"><style>html,body{{margin:0;background:transparent}}</style>'
                    f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{body}</svg>')
        subprocess.run([CHROME, "--headless=new", "--disable-gpu", "--hide-scrollbars", f"--user-data-dir={prof}", "--no-first-run",
                        "--force-device-scale-factor=1", "--default-background-color=00000000", f"--window-size={W},{H}",
                        f"--screenshot={os.path.join(OUT, name + '.png')}", "file://" + page], check=True, capture_output=True, timeout=120)
    shutil.rmtree(tmp, ignore_errors=True); shutil.rmtree(prof, ignore_errors=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    jobs = {}
    for shirt in ("white", "black"):
        c = colours(shirt)
        jobs[f"A-front-only-{shirt}-shirt"] = layout_a(c)
        jobs[f"B-chest-logo-{shirt}-shirt"] = layout_b_front(c)
        jobs[f"B-back-qr-{shirt}-shirt"] = layout_b_back(c)
    render(jobs)
    # The QR codes alone, for flyers, stickers and so on
    for name, url in (("qr-app-store", APP_URL), ("qr-website", WEB_URL)):
        size = 1200; pad = size * 4 / len(matrix(url))
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{-pad} {-pad} {size+2*pad} {size+2*pad}"><rect x="{-pad}" y="{-pad}" width="{size+2*pad}" height="{size+2*pad}" fill="#fff"/>{qr_svg(url, 0, 0, size)}</svg>'
        open(os.path.join(OUT, name + ".svg"), "w").write(svg)
    print("\n".join(sorted(os.listdir(OUT))))


if __name__ == "__main__":
    main()
