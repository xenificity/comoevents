#!/usr/bin/env python3
"""Generate CoMo Events print assets: QR flyer (US Letter), venue counter card (4x6), and
per-channel QR PNGs. Every QR points at the website's /get/ page with a campaign name, which
forwards to the App Store when the app is live and to the TestFlight beta until then.

Usage: python3 Marketing/make_assets.py      (needs reportlab and Pillow)
"""
import os
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import inch
from reportlab.lib.colors import HexColor, white
from reportlab.pdfgen import canvas
from reportlab.graphics.barcode.qr import QrCodeWidget
from reportlab.graphics.shapes import Drawing
from reportlab.graphics import renderPDF, renderPM

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ICON = os.path.join(ROOT, "docs", "img", "icon-512.png")   # 512px keeps the PDFs small
BASE = "https://comoevent.com/get/?c="
SHORT = "comoevent.com"

YELLOW = HexColor("#FFD600")
GOLD = HexColor("#EDAE00")
INK = HexColor("#121214")
GREY = HexColor("#5A5A63")
CATS = [("Party", "#FF408C"), ("Music", "#8C4DFF"), ("Nightlife", "#5A5AE6"), ("Food", "#E5484D"),
        ("Arts", "#00B3C0"), ("Sports", "#FF8C1A"), ("Family", "#2ECC71"), ("Campus", "#EDAE00")]

CHANNELS = ["flyer", "venue", "reddit", "instagram", "orgs", "press", "tiktok", "email", "tabling"]


def qr_drawing(url, size):
    w = QrCodeWidget(url, barLevel="M")
    b = w.getBounds()
    bw, bh = b[2] - b[0], b[3] - b[1]
    d = Drawing(size, size, transform=[size / bw, 0, 0, size / bh, 0, 0])
    d.add(w)
    return d


def draw_qr(c, url, x, y, size, pad=10):
    c.setFillColor(white)
    c.roundRect(x - pad, y - pad, size + 2 * pad, size + 2 * pad, 14, fill=1, stroke=0)
    renderPDF.draw(qr_drawing(url, size), c, x, y)


def wrap(c, text, font, size, width):
    words, lines, line = text.split(), [], ""
    for w in words:
        t = (line + " " + w).strip()
        if c.stringWidth(t, font, size) <= width:
            line = t
        else:
            lines.append(line)
            line = w
    if line:
        lines.append(line)
    return lines


def flyer(path):
    W, H = letter
    c = canvas.Canvas(path, pagesize=letter)
    c.setTitle("CoMo Events flyer")
    m = 0.55 * inch

    # Yellow top block
    top_h = H * 0.52
    top_y = H - top_h
    c.setFillColor(YELLOW)
    c.rect(0, top_y, W, top_h, fill=1, stroke=0)
    c.drawImage(ICON, m, H - m - 1.05 * inch, 1.05 * inch, 1.05 * inch, mask="auto")
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 22)
    c.drawString(m + 1.25 * inch, H - m - 0.45 * inch, "CoMo Events")
    c.setFont("Helvetica", 13)
    c.drawString(m + 1.25 * inch, H - m - 0.75 * inch, "Free for iPhone · Columbia, MO")

    c.setFont("Helvetica-Bold", 44)
    y = H - m - 1.85 * inch
    for line in ["Everything happening", "in Columbia,", "on one map."]:
        c.drawString(m, y, line)
        y -= 50
    y -= 4
    c.setFont("Helvetica", 15)
    sub = "Mizzou, downtown, concerts, parties, markets, the library and family days. Refreshed around the clock."
    for line in wrap(c, sub, "Helvetica", 15, W - 2 * m):
        c.drawString(m, y, line)
        y -= 20

    # Category chips along the bottom edge of the yellow block
    x, cy = m, top_y + 0.22 * inch
    c.setFont("Helvetica-Bold", 11)
    for name, hexcol in CATS:
        w = c.stringWidth(name, "Helvetica-Bold", 11) + 30
        if x + w > W - m:
            break
        c.setFillColor(INK)
        c.roundRect(x, cy, w, 22, 11, fill=1, stroke=0)
        c.setFillColor(HexColor(hexcol))
        c.circle(x + 12, cy + 11, 5, fill=1, stroke=0)
        c.setFillColor(white)
        c.drawString(x + 21, cy + 7, name)
        x += w + 6

    # Bottom: features + QR
    qr = 2.6 * inch
    qx, qy = W - m - qr - 10, 2.25 * inch
    c.setFillColor(YELLOW)
    c.roundRect(qx - 16, qy - 16, qr + 32, qr + 32, 22, fill=1, stroke=0)
    draw_qr(c, BASE + "flyer", qx, qy, qr)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 16)
    c.drawCentredString(qx + qr / 2, qy - 38, "Scan to get the app")

    fy = top_y - 0.6 * inch
    feats = [
        ("Now, tonight, this weekend", "One tap switches the whole map."),
        ("Who is it for", "Everyone, singles, couples, groups or family."),
        ("Save and go", "Tickets, directions and reminders in one tap."),
        ("Go with friends", "See what your friends are going to."),
        ("Free. No ads. No account.", "Made in Columbia by a Mizzou student."),
    ]
    for head, body in feats:
        c.setFillColor(GOLD)
        c.circle(m + 6, fy + 5, 5, fill=1, stroke=0)
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 15)
        c.drawString(m + 20, fy, head)
        c.setFillColor(GREY)
        c.setFont("Helvetica", 12)
        c.drawString(m + 20, fy - 16, body)
        fy -= 0.56 * inch

    # Tear-off tabs
    tabs, tab_h = 8, 1.32 * inch
    tw = W / tabs
    c.setDash(3, 3)
    c.setStrokeColor(GREY)
    c.line(0, tab_h, W, tab_h)
    for i in range(1, tabs):
        c.line(i * tw, 0, i * tw, tab_h)
    c.setDash()
    for i in range(tabs):
        c.saveState()
        c.translate(i * tw + tw / 2 + 4, 0.1 * inch)
        c.rotate(90)
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 10)
        c.drawString(0, 0, "CoMo Events app")
        c.setFont("Helvetica", 7.5)
        c.drawString(0, -11, SHORT)
        c.restoreState()
    c.showPage()
    c.save()


def venue_card(path):
    W, H = 4 * inch, 6 * inch
    c = canvas.Canvas(path, pagesize=(W, H))
    c.setTitle("CoMo Events venue card")
    m = 0.3 * inch
    c.setFillColor(YELLOW)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.drawImage(ICON, m, H - m - 0.75 * inch, 0.75 * inch, 0.75 * inch, mask="auto")
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 16)
    c.drawString(m + 0.9 * inch, H - m - 0.33 * inch, "CoMo Events")
    c.setFont("Helvetica", 10)
    c.drawString(m + 0.9 * inch, H - m - 0.55 * inch, "Free for iPhone")
    c.setFont("Helvetica-Bold", 25)
    y = H - m - 1.3 * inch
    for line in ["What's happening", "tonight?"]:
        c.drawString(m, y, line)
        y -= 28
    c.setFont("Helvetica", 11)
    c.drawString(m, y - 4, "Every event in Columbia, on one map.")
    qr = 2.15 * inch
    qx, qy = (W - qr) / 2, 0.85 * inch
    draw_qr(c, BASE + "venue", qx, qy, qr)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 13)
    c.drawCentredString(W / 2, 0.42 * inch, "Scan · free · no ads")
    c.setFont("Helvetica", 8)
    c.drawCentredString(W / 2, 0.22 * inch, SHORT)
    c.showPage()
    c.save()


def qr_pngs():
    """One QR per channel, as PDF (vector, for print) and PNG (via macOS sips, for posts)."""
    import subprocess
    for ch in CHANNELS:
        pdf = os.path.join(HERE, "qr", f"qr-{ch}.pdf")
        size = 600
        c = canvas.Canvas(pdf, pagesize=(size, size))
        c.setFillColor(white)
        c.rect(0, 0, size, size, fill=1, stroke=0)
        renderPDF.draw(qr_drawing(BASE + ch, size - 60), c, 30, 30)
        c.showPage()
        c.save()
        png = pdf[:-4] + ".png"
        subprocess.run(["sips", "-s", "format", "png", pdf, "--out", png], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    flyer(os.path.join(HERE, "CoMoEvents-flyer-letter.pdf"))
    venue_card(os.path.join(HERE, "CoMoEvents-venue-card-4x6.pdf"))
    qr_pngs()
    print("wrote flyer, venue card and", len(CHANNELS), "QR PNGs")
