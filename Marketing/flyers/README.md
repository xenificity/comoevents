# Flyers

Three US Letter designs, each with two QR codes: the iPhone app (`/get/?c=flyer`, which opens TestFlight
now and the App Store after launch) and the web map (`/app/?c=flyer`).

- `flyer-night.html` → `CoMoEvents-flyer-night.pdf` (dark, glossy)
- `flyer-day.html` → `CoMoEvents-flyer-day.pdf` (light, like the app)
- `flyer-bold.html` → `CoMoEvents-flyer-bold.pdf` (yellow poster)
- `card-night.html` / `card-day.html` → `CoMoEvents-card-4x6-*.pdf` (4x6 reception-desk cards; print on cardstock, 4x6 acrylic holder)

Edit the HTML, then re-render with headless Chrome:

    CH="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
    "$CH" --headless=new --disable-gpu --no-pdf-header-footer --print-to-pdf=CoMoEvents-flyer-night.pdf "file://$PWD/flyer-night.html"

QR codes are `qr-app.svg` / `qr-web.svg`, generated with reportlab (see the top of this folder's history).
Screenshots come from `docs/img/`; replace them there when the app's look changes.
