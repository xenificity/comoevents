# Reply to App Review (submission 08747631, Guideline 2.1 Information Needed)

Send as one message from the submission page ("Reply to App Review"), with the screen recording attached, then press "Resubmit to App Review".

---

Hello,

Thank you for the review. The requested information follows. The same text is in the Notes field of App Review Information. The build has been updated to 1.2.1 (6), which adds a few features and performance fixes since 1.0.0; the recording shows this build.

1. Screen recording: attached. It was captured on a physical iPhone running the current iOS, starting from launch. It shows the map and list, saving an event, Sign in with Apple, profile deletion, posting a community event, and the Report and Block controls on community posts.

2. Purpose and audience: CoMo Events shows every public event in Columbia, Missouri on one map: Mizzou campus events, downtown venues, concerts, markets, library and family events. The audience is students and residents of Columbia, MO. The problem it solves is that local events are scattered across many websites and Facebook pages; the app puts them in one free place with no ads and no account required.

3. Setup and access: there is nothing to set up. The map and the Upcoming list load on launch from a public feed. No login is required for any feature, so there is no demo account; Sign in with Apple is optional and only syncs the user's own saved events. Account deletion is in Profile ("Delete profile"). Community posting: Profile > Post an event. Posts stay pending until a moderator approves them; each post has Report and Block in its "..." menu. Attendance: Going / I'm here / Went buttons on every event.

4. External services: event data is produced by our own open-source script, which reads public web pages and public JSON feeds (University of Missouri calendar, Visit Columbia, Eventbrite, AllEvents, Base Local, Blue Note / Rose Music Hall, Daniel Boone Regional Library, Posh, Cooper's Landing, Vox Magazine) and publishes a single static JSON file on GitHub Pages. The app downloads that file. Addresses are geocoded with OpenStreetMap Nominatim while the feed is built, not inside the app. Within the app we use Apple frameworks only: Sign in with Apple, CloudKit, MapKit, EventKit, VisionKit and Core Spotlight. There are no analytics, ads, payments, tracking, third-party SDKs or AI services. Source: https://github.com/xenificity/comoevents

5. Regional differences: none. The content concerns Columbia, MO, but the app works identically in every region.

6. Regulated industry or protected material: none. Listings are factual public event information with links to the organizers; images are the organizers' own public event images.

Please let me know if anything else is needed.

Ajay Kumar
