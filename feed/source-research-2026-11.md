# Source research, Nov 16, 2026

Three research passes: venues, campus and civic calendars, and holiday events (Nov 17 to Jan 1).
Checked against https://comoevent.com/events.json (1,145 events). Public pages only; nothing
behind a login or a bot check was read. Endpoints marked "verified" were fetched again on Nov 16.

## 1. New calendars to add, best first

| # | Source | Endpoint | Format | Upcoming | How to add |
|---|---|---|---|---|---|
| 1 | Valhalla's Gate (game store: MTG, D&D, Warhammer, Lorcana, board games) | `https://www.valhallasgate.com/index.php?option=com_dpcalendar&task=ical.download&id=root` | .ics (verified) | 117 dated + 56 weekly repeating | `ICS_SITES` row. Address not verified yet |
| 2 | Columbia Public Schools high schools (plays, band, choir, orchestra) | `https://www.cpsk12.org/fs/calendar-manager/events.ics?calendar_ids[]=…` (Rock Bridge 49,33; Hickman 50,32; Battle 11; Douglass 31) | .ics (verified, RBHS: 29 upcoming) | ~60, about half arts | New reader: LOCATION is often blank, so map calendar id to school; keep arts titles only |
| 3 | Hexagon Alley (board-game bar, 111 S 9th St) | Google public ical from its /events/ iframe | .ics (verified) | 14 dated + weekly nights | `ICS_SITES` row |
| 4 | Dive Bar (1116 Business Loop 70 E) | `https://divebarcomo.com/live-music/` | HTML list "11.18 Band 8pm" (verified) | ~23 through Dec 31 | Small regex reader |
| 5 | Jefferson City holiday events | `https://www.visitjeffersoncity.com/celebrate-the-season/` | HTML | 11 dated, none in feed | Seasonal reader, or add by hand to `feed/extra.json` |
| 6 | Missouri Dept. of Conservation (Runge, Eagle Bluffs) | `https://mdc.mo.gov/events?county=1147` and `?county=1205` | HTML, 10 per page | Boone 2, Cole 40 | Small HTML reader; mostly Jefferson City |
| 7 | Boone County History & Culture Center | `https://boonehistory.org/events/` | HTML (robots disallows /wp-json/) | 4, 3 missing | Small HTML reader |
| 8 | Skylark Bookshop, CoMo Preservation | `/new-events`, `/events` | Squarespace HTML | 7 and 4 | Parse the HTML list, not `?format=json` (see section 4) |
| 9 | Orr Street Studios | `/wp-json/wp/v2/event` (date in slug) | WordPress | 2 | Low volume |
| 10 | Bur Oak Brewing, The Broadway Hotel | `/wp-json/tribe/events/v1/events` | Tribe (works, empty now) | 0 | Add to `TRIBE_SITES`: free once they post |

Overlaps, not worth a new reader: Mizzou Athletics (mutigers.com JSON; about 21 of 22 home games
already arrive via other sources; maybe for spring baseball and tennis), MU Theatre and museums
(already in calendar.missouri.edu), Columbia Mall (no events), Missouri State Parks (nothing near
Columbia right now), MU Extension (mostly virtual).

Blocked (not attempted further): como.gov Parks calendar, Shelter Gardens, Bandsintown,
ABC17 events, universitytickets.com (all Cloudflare). Columbia Tribune events is paywalled.

## 2. Places with no online calendar (ask in person or get public Facebook events)

Café Berlin (Wed trivia, Mon open mic), Fretboard Coffee (3rd Friday open mic), Eastside Tavern
(Tue comedy open mic), Love Coffee (Fri open mic), Yellow Dog Bookshop, Harpo's (comedy),
Nash Vegas (country Tue–Sat), Booches, Snapper's, Thirsty Turtle, The Understudy, Klik's.
Several of these are weekly: good candidates for hand-made repeating entries in `feed/extra.json`.

Dead or hijacked sites (do not link): thesocialroomcomo.com and missouricontemporaryballet.com now
serve gambling spam; shilohbar-grill.com 404; roxyscomo.com, williespub.com, thebridgecomo.com down.

## 3. Holidays (Nov 17 to Jan 1)

64 events confirmed with 2026 dates; 47 already in the feed. The 17 missing are outside Columbia:
12 in Jefferson City (Capitol tree lighting Dec 3, Living Windows Dec 4, Governor's Mansion
lighting Dec 4 and candlelight tours Dec 4 and 7, Festival of Lights at Binder Park Dec 4–26,
Jaycees parade Dec 5, Jingle Dash Dec 6, Capitol caroling Dec 8, Skate with Santa Dec 12,
Santa at Carnahan Gardens), Fulton Field of Joy (Dec 3), Moberly Christmas parade (Dec 5),
Arrow Rock Old-Fashioned Christmas (Dec 5).

Wrong data found in the feed:
- Lincoln University Holiday Extravaganza (Dec 1) is pinned at MU's Francis Quadrangle; it is in
  Jefferson City (818 Chestnut St).
- Magic Tree Festival (Dec 3): feed says 6:30 PM, source says 5 to 8 PM, lighting 5:30.
- O Holy Lights (Broadway Christian Church) runs Dec 3, 4 and 5; feed has Dec 3 only.
- Wassail Stroll in The District (Dec 13): feed says 8 PM, source says 2 to 5 PM.
- The Kay Brothers Christmas at The Blue Note (Dec 17) carries another show's description.
- Tokyo Club New Year's Eve at The Arcade District: stored at midnight; doors 5 PM, show 7 PM.
- LEGO Christmas Party (Dec 19) stored at 11 PM; likely wrong.

Recurring, 2026 date not posted yet: Shelter Gardens lights, The Crossing Magic Tree, Boone
County Courthouse lighting, Chabad menorah lighting at City Hall (Hanukkah Dec 4–12), Thanksgiving
Day free meals (Everybody Eats, Salvation Army, St. Francis House, Powerhouse), Christmas Eve
services. Recheck around Nov 25.

## 4. Compliance issue in the current feed

Squarespace's robots.txt, on both themosy.org and cectheatre.org (verified), says
`Disallow: /*?format=json`. `SQUARESPACE_SITES` reads exactly that URL for the Missouri Symphony and
Columbia Entertainment Company. Switch both to parsing the public events HTML, or ask each
organization for permission.

## 5. "Places" layer idea

44 everyday places (Columbia Mall, bowling, escape rooms, climbing gyms, Sky Zone, museums, Rock
Bridge and the Devil's Icebox, MKT and Katy Trail heads, wineries in Rocheport, Laws Observatory
Wednesday nights). Visit Columbia's directory API lists 956 of them by section:
`https://www.visitcolumbiamo.com/wp-json/wp/v2/directory?section=<id>&per_page=100`
(34 family fun, 33 parks and trails, 165 arts and museums, 248 breweries). The full list is in the
research notes from this session; it would need a new "Places" view in the app and website.
