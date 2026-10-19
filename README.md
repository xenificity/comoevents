# CoMo Events

A free iOS app that puts every public event in Columbia, Missouri on one map.
Pins cluster into "busy areas" (cluster size adapts to zoom), a time switch
(Now / Today / Weekend / 7 days / All) and a "who's it for" switch
(Everyone / Singles / Couples / Groups / Family) filter the map, a "Next up" card strip
sits over it, and an Upcoming card list plus a Saved tab round it out.
The look is Liquid Glass on iOS 26 (frosted material on iOS 17/18) in the icon's yellow and black.

The app has no backend of its own. A Python script (`feed/aggregate.py`) pulls
public listings from several sources, geocodes them, merges duplicates and writes
`feed/events.json`. The app ships a snapshot of that file and, once the repo is on
GitHub, fetches the live copy that a scheduled GitHub Action rebuilds.

## Sources

| Source | How | Notes |
|---|---|---|
| Mizzou calendar (calendar.missouri.edu) | LiveWhale JSON + RSS | RSS carries coordinates for ~40% of events; the rest match a venue table |
| Visit Columbia (visitcolumbiamo.com) | WordPress REST + event page | Address is scraped from the page's Google Maps link |
| Eventbrite | listing page server data | Has coordinates and times. Blocked from GitHub runners, so it refreshes only on local runs; the Action carries the last copy forward |
| AllEvents.in | listing JSON-LD | Mirrors public Facebook events; has coordinates |
| Base Local (baselocal.com) | listing JSON-LD | Small local things: trivia, game nights, library |
| The Blue Note / Rose Music Hall | calendar cards + event pages | Show times and ticket links |
| Daniel Boone Regional Library | Communico JSON | Columbia Public Library only |
| MyHouse Nightclub | Posh (posh.vip) group JSON | Add more promoters' Posh slugs to `POSH_GROUPS` |
| Cooper's Landing | The Events Calendar REST | Add other WordPress venues to `TRIBE_SITES` |
| Vox Magazine calendar | TownNews listing cards | Community submissions; recurring schedules expanded weekly; site rate-limits, so no per-event fetch |

Facebook itself has no public API for page events, so it is covered indirectly via AllEvents.
Checked and not usable (as of Oct 2026): The District (calendar only lists past events), The Social Room
(Wix events widget with nothing published), Broadway Brewery and Cafe Berlin (no event listings online;
Cafe Berlin says tickets are on Facebook), Bur Oak (empty calendar), Logboat (no public events page),
Bandsintown / Songkick / JamBase (block scripted access).

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

Categories: party, music, nightlife, food, arts, sports, family, campus, community. Each has its own
map symbol and colour (see `Category` in `Models/Event.swift`); the legend row on the map filters by them.
`audience` is a list drawn from singles / couples / groups / family, set by keyword rules in
`infer_audience()` with per-category defaults; tune the rules there, not in the app.

## Accounts and profiles

Optional. The app works fully without signing in. The Profile tab offers **Sign in with Apple**;
once signed in, the profile (name, interests, "I'm usually out as…", saved event ids) is stored as one
record in the user's **private CloudKit database** (`iCloud.com.xenificity.comoevents`, record type
`Profile`) and merged back on every launch, so it follows the person to a new phone. Signed out, the
same profile lives in `Application Support/profile.json`. There is no server of ours and no email list.

Before the App Store:
- Deploy the CloudKit schema from Development to Production in CloudKit Console (the `Profile` record
  type is created just-in-time the first time a dev build saves).
- Apple requires account deletion; the app deletes the CloudKit record and local data. Apple also asks
  that Sign in with Apple tokens be revoked via their REST API on deletion, which needs a tiny server
  (a Cloudflare Worker is enough). Not done yet.
- Signing in cannot be tested in the simulator without an Apple ID signed into it; use a device.

## Status

Submitted to App Review on Oct 18, 2026 (App Store Connect app ID 6824363992, version 1.0.0 build 1,
iPhone only). TestFlight internal group "Developer" carries the same build. CloudKit schema is deployed
to Production. Not yet: Apple token revocation on account deletion (needs a tiny server), iPad layout,
push notifications, user-submitted events, a real "busy right now" signal beyond event counts.
