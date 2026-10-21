#!/bin/sh
# Rebuild feed/events.json from the live sources and copy it into the app bundle.
set -e
cd "$(dirname "$0")/.."
python3 feed/aggregate.py "$@"
cp feed/events.json CoMoEvents/Resources/events.json
cp feed/events.json docs/events.json
echo "Copied feed into CoMoEvents/Resources/events.json and docs/events.json"
