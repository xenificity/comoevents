# CoMo Events logo

Vector sources are the `.svg` files; PNGs are 4x exports with transparent backgrounds
(avatars are opaque squares). Regenerate the PNGs with headless Chrome:

    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=new \
      --screenshot=logo-mark.png --window-size=240,290 --force-device-scale-factor=4 \
      --default-background-color=00000000 --hide-scrollbars file://$PWD/logo-mark.svg

- `logo-horizontal-light` / `-light-accent`: pin + "CoMo Events", for white or light backgrounds.
- `logo-horizontal-dark`: white + yellow wordmark, for black or dark backgrounds.
- `logo-stacked-light` / `-dark`: pin above the wordmark, for square-ish spaces.
- `logo-mark`: the pin alone (transparent). `logo-avatar-yellow` / `-black`: 400x400 profile pictures.

Colors: yellow #FFD600, ink #121214. The wordmark uses the system font (SF Pro on Apple
devices), so the SVGs render with a fallback font elsewhere; use the PNGs for sharing.
