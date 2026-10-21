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
| Shanthi Mandir (Hindu temple) | Public Google Calendar .ics, recurring rules expanded with dateutil | Add other public .ics calendars to `ICS_SITES` |
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

## Features added in 1.1

- **Notifications** (local only): a reminder one hour before each saved event, and a "Tonight in CoMo"
  digest at 4 PM built from the cached feed. Toggles in Profile. `Support/NotificationService.swift`.
- **Share**: a 1080×1080 card (ImageRenderer) plus text and link through the system share sheet.
- **Add to Calendar**: Apple's event editor prefilled; write-only calendar access.
- **Post an event**: anyone with iCloud on their phone can submit; it lands as `pending` in the public
  CloudKit database (`SubmittedEvent`) and shows after a moderator sets `status = approved`. Posts can be
  reported (`Report` records; three reports hide a post). Moderation needs no CloudKit role: a moderator's
  decision is an `Approval` record, and the app only honours approvals whose creator is listed in
  `CommunityStore.moderators`. Add a moderator by putting their iCloud user record name (Profile › Your
  CoMo ID) in that set.
- **Friends**: opt-in `FriendProfile` record with a 6-letter code; add friends by code; "X is going"
  on event details and a Friends tab listing friends' upcoming saves (only if they turned sharing on).
- **Siri / Spotlight**: App Shortcuts "What's happening in CoMo Events tonight" and "Open the CoMo
  Events map"; every upcoming event is indexed in Spotlight and opens the detail. URL scheme
  `comoevents://event/<id>`, `comoevents://map`, `comoevents://submit`, `comoevents://friends`.

## Features added in 1.2

- **Attendance**: Going / I'm here / Went on every event. Each is a public `Attendance` record
  (`att-<user>-<event>`), so events show "N going" and "N here" counts. "I'm here" is only offered
  from one hour before the start until the end; "Went" after it ends. `Support/AttendanceStore.swift`.
- **Friends on the map**: friends who are going to or at an event show as initial bubbles under the
  pin (green = here, yellow = going or saved). `FriendProfile` carries `going` and `here` lists.
- **Quick fill when posting**: scan a poster QR code (VisionKit; a real iPhone is needed, the
  simulator shows a fallback) or paste a link. The page title and any JSON-LD `Event` fill title,
  time, venue and address. `Views/QRScanView.swift`.
- **Multiple categories**: `events.json` records carry `categories` (primary first, up to four) and
  an event shows under every one of them. The submit sheet has "Also show under".
- **Invite from Contacts**: pick people in the system contact picker (no Contacts permission needed),
  then Messages opens with the invite text and your friend code. `Support/ContactsInvite.swift`.
- **Send feedback / Rate**: in Profile › Help & contact (mailto template, App Store write-review link).
- Not done on purpose: Facebook sync (no public API; AllEvents already mirrors public Facebook
  events) and live friend location (only event attendance is shared).

CloudKit schema for all of this is in `feed/cloudkit-schema.ckdb` (schema v4).

## Marketing kit

Launch goal: 1,000 users in Columbia by Dec 31, 2026. Everything lives in `Marketing/`:

- `CoMoEvents-flyer-letter.pdf` (US Letter, tear-off tabs) and `CoMoEvents-venue-card-4x6.pdf` (counter card).
  Regenerate with `python3 Marketing/make_assets.py`.
- `qr/` one QR per channel (PDF for print, PNG for posts). `campaign-links.md` explains the links.
- `drafts/` press pitches, student-org outreach, Reddit and Halloween posts. Drafts only, nothing is sent.
- `scripts/weekly_post.py` prints a "This weekend in CoMo" top-10 caption from `feed/events.json`.

All install links go through `docs/get/` (`https://xenificity.github.io/comoevents/get/?c=<channel>`), which
opens the App Store once the app is live and the TestFlight beta until then. The app uses the same page
(`Support/AppLinks.swift`): share cards carry a QR and link (`c=share`), the Friends tab has an Invite
button (`c=invite`), and the app asks once for a rating after the third saved event. Press kit:
`docs/press.html`.

## Web app

`docs/app/` is a browser twin of the app at https://xenificity.github.io/comoevents/app/: same feed,
same light glass look, the four tabs (Map / Upcoming / Saved / Profile), the Now / Today / Weekend /
7 days / All windows, audience and category filters, search, "Next up" strip, venue sheets, day-grouped
image cards, a "For you" row from the profile's interests, and an event page with More info,
Directions, Add to calendar (.ics), Share, deep link and install buttons. The map is MapLibre GL on
OpenFreeMap's "liberty" vector style (free, no key) with pitch and 3D buildings; pins are clustered
with the same grid rule as `Hotspot.swift`. Favorites and profile stay in the browser's localStorage.
`?e=<id>` opens an event, `?tab=upcoming` a tab. It reads `docs/events.json`, which the feed workflow
and `scripts/update-feed.sh` copy from `feed/events.json`, with the raw GitHub copy as fallback.
No build step: plain `index.html`, `app.css`, `app.js`; bump the `?v=` on the two asset links in
`index.html` after every change so browsers pick it up. With a CloudKit JS API token in `docs/app/ck-config.js`, the web app also signs in with iCloud and
has Going / I'm here / Went with live counts, Friends by code and Post an event, through the same
public CloudKit records as the app (`docs/app/cloud.js`).

## Flyer events and smart fill

`feed/extra.json` holds events typed in from posters and pamphlets. A row needs only `title`, `start`
and `venue`; address, pin, phone and website come from `feed/venues.json` (which now has `website`),
and `imageUrl` can point at a flyer photo in `docs/img/flyers/`. Past rows are dropped automatically.
The same idea runs in both apps when someone posts: type a venue name and the address, website and
pin are filled from the venue table, then Apple Maps (`Support/VenueLookup.swift`) or OpenStreetMap
(`docs/app/cloud.js`, `Cloud.lookupVenue`). Community posts are also enriched on display with the
venue's phone and website when the venue is known. `scripts/update-feed.sh` copies `venues.json` into
the app bundle and into `docs/`.

## Usage counter

"N people use CoMo Events" (Profile header, map count pill, web Profile, landing page) counts anonymous
`Install` records in the public CloudKit database: one per app install or signed-in web browser,
created once and touched at most weekly (`Support/UsageCounter.swift`, `Cloud.registerInstall`). No
device id, no location. Writes need an iCloud account like every other public write; reads are open,
so the landing page queries CloudKit Web Services directly. Anonymous web visitors are not counted.

## App Review compliance notes (guideline 1.2 and friends)

The community features make this a user-generated-content app, so the app ships the four things
guideline 1.2 asks for: a word filter at post time (`Support/ContentFilter.swift`) plus human
pre-moderation; Report on posts and friend profiles (three reports auto-hide a post); Block for
posters and friends; and contact info in Profile › Help & contact and on the website
(`docs/guidelines.html`). There are no hidden or undocumented features (2.5.19): moderators are
hardcoded, nothing is unlocked by gestures.

Before submitting 1.1.x to the App Store: set the age-rating answer "User-Generated Content" to Yes,
and update App Privacy to declare "User Content" (post text, display name) collected for app
functionality, not linked to identity, no tracking, since posts live in the public CloudKit database.

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
