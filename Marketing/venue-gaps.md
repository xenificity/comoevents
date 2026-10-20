# Venue gap report

Generated 2026-10-20 by `scripts/venue_gap.py`. Rerun it any time.

OpenStreetMap lists 119 event-type places in Columbia (bars, pubs, clubs, theatres, breweries, arts spaces, museums, galleries, bookstores, libraries, community centres and the big parks).

- Covered with events in the feed: 43 (this counts 19 MU auditoriums, libraries and halls, which the Mizzou calendar source covers as a whole)
- In `feed/venues.json` but no events in the feed yet: 13
- Not covered: 63 (20 high, 32 medium, 11 low priority)
- Websites checked: 17 of 17 uncovered venues that have a website in OSM (or a known operator site), plus 5 venues from `feed/venues.json` with no events.

Most uncovered places (46 of 63) have no website in OSM, so the only way to reach them is in person or through their Facebook page.

Priority: high means downtown (within 1.2 km of 9th and Broadway) or on campus, and a bar, pub, club, music venue, theatre, event venue or brewery. Medium means another event-type place. Low means libraries, parks and community centres without a website.

OSM is not complete. It also leaves out restaurants and cafes, and several of those host music and trivia. A place missing here may still be worth a visit.

## Can add automatically now

These sites publish events a script can read. Tribe sites go in `TRIBE_SITES`, Posh groups in `POSH_GROUPS`. The rest need a small `src_*` parser. Add the venue to `feed/venues.json` too.

| Venue | Type | Method | Endpoint | Note |
|---|---|---|---|---|
| Stephens College calendar: Historic Costume Gallery, Windsor Auditorium | event venue, gallery, medium | Localist API | https://calendar.stephens.edu/api/2/events | 90 events in the next 90 days across the whole calendar |
| Gunter Hans | pub, high | Squarespace events (?format=json has upcoming) | https://www.gunterhans.com/events?format=json | 1 upcoming event(s) |

## Visit in person – downtown priority

Downtown and campus places with no feed we can read. High priority first (bars, clubs, theatres, breweries), then other downtown event places (galleries, bookstores, arts spaces). Within each group, the likeliest event hosts come first, then the closest to 9th and Broadway.

1. **Reign Bar**, 33 North 9th Street. Nightclub, downtown, high priority, 550 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask which ticket site they use for theme nights (Posh, Eventbrite). Send us the organizer link and we pull it automatically.
2. **Tropical Liqueurs**, 515 East Broadway. Bar, downtown, high priority, 250 m from 9th and Broadway.
   Website: http://www.2trops.com/columbia-downtown/. Online check: no events found.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
3. **McNally's**, 7 North 6th Street. Pub, downtown, high priority, 270 m from 9th and Broadway.
   Website: https://www.mcnallys.biz/. Online check: site unreachable.
   Ask: Ask for trivia, live music and watch-party nights. Public Facebook events or a simple events page is enough.
4. **Snapper's**, 12 South 7th Street. Bar, downtown, high priority, 400 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
5. **CJ's In Tiger Country**, 704 East Broadway. Pub, downtown, high priority, 410 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for trivia, live music and watch-party nights. Public Facebook events or a simple events page is enough.
6. **Vault**, 23 South 8th Street. Bar, downtown, high priority, 470 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
7. **The Understudy**, 813 Cherry Street. Bar, downtown, high priority, 540 m from 9th and Broadway.
   Website: https://theunderstudybar.com/. Online check: Wix/Facebook only.
   Ask: They only post on Facebook or a Wix page. Ask them to make their Facebook events public (AllEvents picks those up and so do we), or to send a weekly schedule.
8. **Endwell Taverna**, 107 North 9th Street. Pub, downtown, high priority, 570 m from 9th and Broadway.
   Website: https://www.endwelltaverna.com/menu. Online check: no events found.
   Ask: Ask for trivia, live music and watch-party nights. Public Facebook events or a simple events page is enough.
9. **Top Ten Wines**, 111 South 9th Street. Bar, downtown, high priority, 570 m from 9th and Broadway.
   Website: https://www.toptenwines.biz/. Online check: no events found.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
10. **Son of a Gun**, 16 North 9th Street. Bar, downtown, high priority, 580 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
11. **9th Street Public House**, 36 North 9th Street. Bar, downtown, high priority, 590 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
12. **The Shot Bar**, Cherry Street (approx.). Bar, downtown, high priority, 590 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
13. **Booches**, South 9th Street (approx.). Bar, downtown, high priority, 610 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
14. **On The Rocks**, East Broadway (approx.). Bar, downtown, high priority, 690 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
15. **Klik's LLC**, 205 North 10th Street. Bar, downtown, high priority, 700 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
16. **International Tap House**, Woodson Way (approx.). Bar, downtown, high priority, 760 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for their weekly specials and nights (trivia, karaoke, DJs, live music). Easiest for them: make Facebook events public, or post on Eventbrite. We list them free.
17. **Willie's**, 1109 East Broadway. Pub, downtown, high priority, 790 m from 9th and Broadway.
   Website: https://fieldhousecomo.com/. Online check: Wix/Facebook only.
   Ask: They only post on Facebook or a Wix page. Ask them to make their Facebook events public (AllEvents picks those up and so do we), or to send a weekly schedule.
18. **Dogmaster Distillery**, 210 Saint James Street. Distillery, downtown, high priority, 950 m from 9th and Broadway.
   Website: https://dogmasterdistillery.com/. Online check: no events found.
   Ask: Ask for tastings and live music. Public Facebook events or an events page works.
19. **The Atrium on Tenth**, 22 North 10th Street. Event venue, downtown, high priority, 700 m from 9th and Broadway.
   Website: https://theatriumontenth.com/. Online check: no events found.
   Ask: Ask for their public events calendar or ticket organizer link.
20. **Speaker's Circle**, East Walnut Street (approx.). Theatre, downtown, medium priority, 500 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Outdoor public stage. Find out who books it (city, county or college) and ask for their calendar.
21. **Resident Arts**, Artist Alley (approx.). Arts centre, downtown, medium priority, 750 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for openings, classes and shows. An events page or calendar feed works.
22. **Orr Street Gallery**, Orr Street (approx.). Arts centre, downtown, medium priority, 830 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for openings, classes and shows. An events page or calendar feed works.
23. **Peace Nook**, 804 East Broadway. Bookstore, downtown, medium priority, 500 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for author readings, book clubs and story times.
24. **Yellow Dog Bookstore**, 8 South 9th Street. Bookstore, downtown, medium priority, 580 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for author readings, book clubs and story times.
25. **Artlandish Gallery**, 1019 East Walnut Street. Gallery, downtown, medium priority, 730 m from 9th and Broadway.
   Website: https://www.facebook.com/ARTlandish-Gallery-99515315928/. Online check: Wix/Facebook only.
   Ask: They only post on Facebook or a Wix page. Ask them to make their Facebook events public (AllEvents picks those up and so do we), or to send a weekly schedule.
26. **The Text Book Game**, Watson Place (approx.). Bookstore, downtown, medium priority, 740 m from 9th and Broadway.
   Website: none listed. Online check: no website in OSM.
   Ask: Ask for author readings, book clubs and story times.
27. **Sager Reeves Gallery**, 1025 East Walnut Street. Gallery, downtown, medium priority, 750 m from 9th and Broadway.
   Website: https://www.sagerreevesgallery.com/. Online check: no events found.
   Ask: Ask for First Friday openings and artist talks.

Also worth a stop: these are in `feed/venues.json` but have no events in the feed right now.

- Broadway Brewery (bar, East Broadway (approx.), 530 m from 9th and Broadway)
- Broadway Brewery Taproom on 9th (bar, 15 South 9th Street, 560 m from 9th and Broadway)
- Nash Vegas (nightclub, 929 East Broadway, 650 m from 9th and Broadway)
- FieldHouse (pub, 1107 East Broadway, 770 m from 9th and Broadway)
- Talking Horse Productions (theatre, 210 Saint James Street, 940 m from 9th and Broadway)
- Logboat Brewing Co (brewery, Fay Street (approx.), 1210 m from 9th and Broadway)

### Walking route

Start at 9th and Broadway. 32 stops, about 2.6 km, roughly 35 minutes of walking plus time at each stop. Go late afternoon, when managers are in and it is not busy yet.

1. Tropical Liqueurs, 515 East Broadway (250 m)
2. McNally's, 7 North 6th Street (20 m)
3. CJ's In Tiger Country, 704 East Broadway (160 m)
4. Snapper's, 12 South 7th Street (30 m)
5. Vault, 23 South 8th Street (70 m)
6. Peace Nook, 804 East Broadway (60 m)
7. Broadway Brewery, East Broadway (approx.) (40 m)
8. Son of a Gun, 16 North 9th Street (110 m)
9. 9th Street Public House, 36 North 9th Street (30 m)
10. Reign Bar, 33 North 9th Street (40 m)
11. Speaker's Circle, East Walnut Street (approx.) (100 m)
12. Endwell Taverna, 107 North 9th Street (80 m)
13. Klik's LLC, 205 North 10th Street (140 m)
14. Talking Horse Productions, 210 Saint James Street (250 m)
15. Dogmaster Distillery, 210 Saint James Street (10 m)
16. Orr Street Gallery, Orr Street (approx.) (150 m)
17. Resident Arts, Artist Alley (approx.) (80 m)
18. Artlandish Gallery, 1019 East Walnut Street (30 m)
19. Sager Reeves Gallery, 1025 East Walnut Street (30 m)
20. The Atrium on Tenth, 22 North 10th Street (60 m)
21. Willie's, 1109 East Broadway (130 m)
22. FieldHouse, 1107 East Broadway (20 m)
23. On The Rocks, East Broadway (approx.) (80 m)
24. Nash Vegas, 929 East Broadway (50 m)
25. Yellow Dog Bookstore, 8 South 9th Street (90 m)
26. Broadway Brewery Taproom on 9th, 15 South 9th Street (40 m)
27. The Understudy, 813 Cherry Street (40 m)
28. The Shot Bar, Cherry Street (approx.) (50 m)
29. Booches, South 9th Street (approx.) (30 m)
30. Top Ten Wines, 111 South 9th Street (40 m)
31. The Text Book Game, Watson Place (approx.) (230 m)
32. International Tap House, Woodson Way (approx.) (70 m)

## Visit later – rest of Columbia

| Venue | Type | Priority | Address | Website | Online check |
|---|---|---|---|---|---|
| Launer Auditorium | theatre | medium | Rogers Street (approx.) | https://www.ccis.edu/ | no events found |
| Whitcraft-Schiffman Memorial Amphitheater | theatre | medium | North 8th Street (approx.) | https://www.ccis.edu/ | no events found |
| Maplewood Barn Theatre | theatre | medium | East Nifong Boulevard (approx.) |  | no website in OSM |
| The Thirsty Turtle | bar | medium | North Boulevard (approx.) |  | no website in OSM |
| McGinty's Pub | pub | medium | Old 63 South (approx.) |  | no website in OSM |
| Deuce | pub | medium | Monterey Drive (approx.) |  | no website in OSM |
| Truman's Bar and Grill | pub | medium | Wind River Circle (approx.) |  | no website in OSM |
| Tropical Liquor | bar | medium | Outer Road (approx.) |  | no website in OSM |
| Trail Stop Brewery | brewery | medium | 3901 S Brushwood Lake Rd | https://trailstopbrewery.com | no events found |
| Six Mile Ordinary | distillery | medium | Fay Street (approx.) |  | no website in OSM |
| Goodrich Forum 8 | cinema | medium | 1209 Forum Katy Parkway |  | no website in OSM |
| Wine Cellar | winery | medium | Carter Lane (approx.) |  | no website in OSM |
| Macadoodles | winery | medium | East Green Meadows Road (approx.) |  | no website in OSM |
| Hollywood Theater | cinema | medium | Bluff Creek Boulevard (approx.) |  | no website in OSM |
| Access Arts | arts centre | medium | North Stadium Boulevard (approx.) |  | no website in OSM |
| Distant Planet Comics & Collectibles | bookstore | medium | 711 North College Street |  | no website in OSM |
| Riechmann Pavilion | event venue | medium | 2300 East Walnut Street |  | no website in OSM |
| Columbia Exposition Center | event venue | medium | Knipp Street (approx.) |  | no website in OSM |
| Barnes & Noble | bookstore | medium | Bernadette Drive (approx.) |  | no website in OSM |
| Walters-Boone County Historic Museum | museum | medium | Ponderosa Street (approx.) |  | no website in OSM |
| Elk Park Event Center | event venue | medium | 4747 Elk Park Drive |  | no website in OSM |
| Orchids & Arts | gallery | medium | Commercial Drive (approx.) |  | no website in OSM |
| Douglass Park | park | low |  |  | no website in OSM |
| Peace Park | park | low |  |  | no website in OSM |
| Capen Park | park | low | 1600 Capen Park Drive |  | no website in OSM |
| Clary-Shy Community Park | park | low | 1701 West Ash Street |  | no website in OSM |
| Bear Creek Park | park | low | 1402 Elleta Boulevard |  | no website in OSM |
| 3M Flat Branch-Hinkson Creek Wetlands | park | low |  |  | no website in OSM |
| Fairview Park | park | low |  |  | no website in OSM |
| American Legion Park | park | low | 3675 Legion Lane |  | no website in OSM |
| Rothwell Park | park | low |  |  | no website in OSM |
| Nifong Park | park | low | 2900 East Nifong Boulevard |  | no website in OSM |
| Gans Creek Recreation Area | park | low | 3360 East Gans Road | https://www.como.gov/parks/gans-creek-recreation-area/ | no events found |

Full data, including covered venues: `Marketing/venue-gaps.csv`.
