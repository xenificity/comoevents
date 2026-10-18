# CoMo Events

A free iOS app that puts every public event in Columbia, Missouri on one map.
Pins cluster into "busy areas", a time switch (Now / Today / Weekend / 7 days / All)
filters the map, and an Upcoming list plus a Saved tab round it out.

The app has no backend of its own. A Python script (`feed/aggregate.py`) pulls
public listings from several sources, geocodes them, merges duplicates and writes
`feed/events.json`. The app ships a snapshot of that file and, once the repo is on
GitHub, fetches the live copy that a scheduled GitHub Action rebuilds.

## Sources

| Source | How | Notes |
|---|---|---|
| Mizzou calendar (calendar.missouri.edu) | LiveWhale JSON + RSS | RSS carries coordinates for ~40% of events; the rest match a venue table |
| Visit Columbia (visitcolumbiamo.com) | WordPress REST + event page | Address is scraped from the page's Google Maps link |
| Eventbrite | listing page server data | Has coordinates and times |
| AllEvents.in | listing JSON-LD | Mirrors public Facebook events; has coordinates |
| Base Local (baselocal.com) | listing JSON-LD | Small local things: trivia, game nights, library |
| The Blue Note / Rose Music Hall | calendar cards + event pages | Show times and ticket links |
| Daniel Boone Regional Library | Communico JSON | Columbia Public Library only |

Facebook itself has no public API for page events, so it is covered indirectly via AllEvents.
The District (discoverthedistrict.com) was checked but its calendar only lists past events.

## Run it

Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`),
Python 3.11+ with `requests` (`pip3 install requests`).

```bash
git clone https://github.com/xenificity/comoevents.git
cd comoevents
xcodegen generate          # creates CoMoEvents.xcodeproj (not committed)
open CoMoEvents.xcodeproj  # pick an iPhone simulator, press Run
```

Or from the terminal:

```bash
xcodebuild -project CoMoEvents.xcodeproj -scheme CoMoEvents \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
```

### Refresh the events

```bash
./scripts/update-feed.sh            # rebuilds feed/events.json and copies it into the app bundle
./scripts/update-feed.sh --only bluenote,dbrl   # just some sources
```

The first run takes a few minutes because it geocodes new venues (Nominatim, 1 request/second)
and caches event pages. Later runs take about a minute. `feed/cache/geocode.json` is committed
so collaborators share the cache; `feed/cache/pages.json` is not.

## Layout

```
feed/aggregate.py          source parsers, geocoding, de-dup, writes events.json
feed/venues.json           known venues with coordinates (add a venue here when a pin is missing or wrong)
feed/events.json           the generated feed (committed; the Action keeps it fresh)
CoMoEvents/Models          Event, EventStore (load/refresh/favorites), TimeWindow, Hotspot (clustering)
CoMoEvents/Views           MapScreen, UpcomingScreen, SavedScreen, EventList, EventDetailView
CoMoEvents/Resources       bundled events.json snapshot
scripts/update-feed.sh     rebuild + copy
.github/workflows/feed.yml scheduled rebuild (every 2 hours)
project.yml                XcodeGen spec; regenerate the project after adding files
```

## Event JSON shape

```json
{"id":"…","source":"bluenote","sourceName":"The Blue Note","title":"…",
 "start":"2026-10-24T21:00:00-05:00","end":null,"allDay":false,"timeTBD":false,
 "venue":"The Blue Note","address":"17 N 9th St","lat":38.952,"lng":-92.3277,
 "url":"…","ticketUrl":"…","phone":"(573) 874-1944","price":"$25",
 "category":"music","imageUrl":"…","description":"…","organizer":"…","alsoOn":[]}
```

Categories: music, sports, arts, family, food, nightlife, campus, community.

## Status

Prototype. Works in the simulator. Not yet: app icon, App Store listing, push notifications,
user-submitted events, a real "busy right now" signal beyond event counts.
