#!/bin/sh
# Rebuild feed/events.json from the live sources and copy it into the app bundle.
set -e
cd "$(dirname "$0")/.."
python3 feed/aggregate.py "$@"
python3 scripts/make_covers.py   # pictures for events without one (needs Chrome + Pillow)
cp feed/events.json CoMoEvents/Resources/events.json
cp feed/events.json docs/events.json
cp feed/venues.json CoMoEvents/Resources/venues.json
cp feed/venues.json docs/venues.json
cp feed/search.json CoMoEvents/Resources/search.json
cp feed/search.json docs/search.json
python3 scripts/build_event_pages.py
echo "Copied feed into CoMoEvents/Resources/events.json and docs/events.json"
