# CoMo Events — App Store listing

**Name**: CoMo Events
**Subtitle** (30): Columbia, MO on one map
**Category**: Lifestyle (secondary: Entertainment)
**Price**: Free, all countries. No IAP, no ads.
**Age rating**: 12+ expected (infrequent/mild alcohol references: bar and brewery events appear in listings)
**Support URL**: https://comoevent.com/about/
**Privacy Policy URL**: https://comoevent.com/privacy.html
**Copyright**: 2026 Ajay Kumar
**Sign-in required for review**: No (Sign in with Apple is optional; every feature works signed out)

**Promotional text** (170):
Every public event in Columbia, Missouri on one live map: Mizzou, downtown, music, parties, markets, library, family. Free, no ads.

**Keywords** (100):
columbia mo,como,mizzou,events,things to do,tonight,concerts,parties,downtown,calendar,local,map

**Description**:
CoMo Events puts everything happening in Columbia, Missouri on one map, so you can see what's going on near you right now and what's coming up.

ONE MAP, EVERY SOURCE
We gather public listings from the Mizzou calendar, Visit Columbia, The Blue Note and Rose Music Hall, Daniel Boone Regional Library, Cooper's Landing, MyHouse, Eventbrite, AllEvents, Base Local and Vox Magazine's community calendar, and refresh them around the clock. No more checking eight websites.

SEE WHERE IT'S BUSY
Pins cluster into busy areas and show what kind of event is there at a glance: parties, music, nightlife, food, arts, sports, family, campus and community each have their own symbol.

PICK YOUR MOMENT
Now, Today, Weekend, 7 days or everything. A "Next up" strip floats over the map with what's starting soon.

WHO'S IT FOR
Switch between Everyone, Singles, Couples, Groups and Family to filter the whole app.

SAVE AND GO
Tap the heart to keep an event. Open tickets or registration, call the venue, or get directions in one tap.

OPTIONAL PROFILE
Sign in with Apple to keep your name, interests and saved events in your own iCloud, so they're there on your next phone. No password, no email list, no account required to use the app.

Built in Columbia, for Columbia. Free, with no ads and no tracking.

**What's New** (1.0.0): First release.

**App Review notes**:
No sign-in is required. Sign in with Apple is optional and stores the profile in the user's own private iCloud database; we operate no server. Location is used only to center the map and never leaves the device. Event data is a public JSON feed hosted on GitHub (https://github.com/xenificity/comoevents) built from public listings; a snapshot is bundled in the app so it works offline.

**App Privacy**: Data Not Collected. (Location stays on device; profile and saved events go only to the user's private CloudKit database, which the developer cannot read; no analytics, no ads, no third-party SDKs.)

---

# Version 1.2.1 (prepared Nov 2026)

**What's New in This Version** (use the second paragraph only once Google/Facebook are public):

Find the good stuff faster. Search now understands what you mean, typos included: try "tech", "hindu temple", "church" or "jazz downtown". The best events rank first, a new For You row learns what you like, and there's a new Religious category. More Mizzou student organization events are in, and every event has a sharp picture.

Also new: dark mode, a cleaner map that glows where it's busy, a profile picture, sounds, and adding a photo or scanning a flyer when you post an event. Sign in with Google or Facebook too.

**Notes for App Review:** the saved text is in App Store Connect on the 1.2.1 draft (Nov 4, 2026). It replaced the old "no analytics" claim: GoatCounter counts and our Cloudflare Worker are disclosed. Add a line about Google/Facebook sign-in only when they are switched on.

**App Privacy label** (App Store Connect > App Privacy; published before: Name, Other User Content, User ID. New: Photos or Videos, Product Interaction). None used for tracking:

| Data type | Linked to user | Why |
|---|---|---|
| Contact Info > Name | Yes | Display name; Google/Facebook sign-in |
| Contact Info > Email Address | Yes | Add when Google/Facebook sign-in goes public |
| User Content > Photos or Videos | Yes | Profile picture, event photos |
| User Content > Other User Content | Yes | Posted events, reports |
| Identifiers > User ID | Yes | Hashed account id, iCloud user id on public records |
| Usage Data > Product Interaction | No | Anonymous counts (also "Analytics") |

Flyer text and location stay on the device, and Google contact emails are only compared in real time, so none of these count as collected.

---

# Version 1.2.2 (build 20, Nov 10, 2026)

**What's New in This Version:**

Tap any place on the map to see everything happening there, with the address and directions. Zoom in and pins show the venue's name.

Posting an event is now instant: it goes live on the map and in search for everyone right away.

More to find: new events from The District, Columbia College, Columbia Art League, Macaroni Kid, the Columbia Farmers Market, the Chamber of Commerce, RunSignup races, COMO Tickets and Jabberwocky Studios. The map buttons no longer cover the pins, and the location button moved to the bottom right.

**App Review notes change:** community posts are no longer held for a moderator. Replace the moderation paragraph with:
"Community posts go live automatically after a word filter (the same list as ContentFilter.swift runs on our Cloudflare Worker before it approves a post). Every post can be reported or its poster blocked from the event page; three reports hide a post automatically, and the developer reads reports the same day and can remove any post (removal always wins). Posting requires agreeing to the community guidelines (https://comoevent.com/guidelines.html)."

**App Privacy:** no new data types in 1.2.2.

---

# Version 1.3.0 (build 21, Nov 17, 2026)

**What's New in This Version:**

The biggest update yet.

• Places: a new tab with 170+ spots to go any day: bowling, escape rooms, Rock Bridge, trails, museums, coffee, bars and Columbia Mall, with directions and what's on there.
• Free food: one tap shows every event that mentions free pizza, snacks or a meal.
• Who's in?: send friends a link to any event. They tap "I'm in" in any browser, no app needed, and you see who's coming.
• Game day: on Mizzou home game days, one screen with the game, tailgates and watch parties, and what's on after.
• Weekend picks: three picks for your weekend, Thursday at 6 PM and Friday at 3 PM, plus tonight's pick every evening. Turn them off in Profile.
• Share any event as an Instagram Story picture.
• Report a problem: if a time or place is wrong, tell us. Once 3 people report the same thing, the listing fixes itself.
• Ask Siri: "What's happening this weekend in CoMo Events", "Where's free food in CoMo Events", "Is it game day in CoMo Events".
• More events: game nights at Valhalla's Gate and Hexagon Alley, Dive Bar shows, high school plays and concerts, Pierpont, and weekly trivia, comedy and open mics.
• Friends moved under Saved.

**App Review notes change (add):**
"Version 1.3 adds no sign-in requirement. New features talk to our Cloudflare Worker without an account: 'Report a problem' sends the event id, the kind of problem, the correction typed and a random per-install id (scrambled before storage, deleted after 45 days); a listing only changes after 3 different reports agree. 'Who's in?' stores the event, the host's first name and the first names guests type on the invite web page (comoevent.com/in/), deleted a week after the event. Notifications are local (provisional authorization, no prompt): tonight's pick at 7 PM and weekend picks Thursday 6 PM and Friday 3 PM, all switchable off in Profile. To try game day mode in review, any Mizzou home game day shows the banner on the Map; Places is the third tab."

**App Privacy:** add nothing new to the label if "Other User Content" (names typed on invites, report text) and "User ID" are already declared, which they are since 1.2.1. Data is not used for tracking.
