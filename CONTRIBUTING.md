# Contributing to CoMo Events

Thanks for helping. This is a free community app, so the rules are simple: keep it free,
keep it serverless, and keep every feature working without an account.

## Set up (Mac)

1. Install Xcode 26 from the App Store and open it once so it installs its tools.
2. Install Homebrew (brew.sh) if you do not have it, then:
   ```bash
   brew install xcodegen gh
   pip3 install requests
   ```
3. Clone and generate the Xcode project:
   ```bash
   gh auth login
   git clone https://github.com/xenificity/comoevents.git
   cd comoevents
   xcodegen generate
   open CoMoEvents.xcodeproj
   ```
4. In Xcode pick any iPhone simulator and press Run. The app ships with a snapshot of the
   event feed, so it works with no setup. Signing in with Apple only works on a real device.

## Working with Claude Code (desktop app)

Open the `comoevents` folder in the Code tab of the Claude desktop app. The repo has a
`CLAUDE.md` that tells Claude how the project is built, where the parsers live, and the rules
we follow, so you can describe what you want in plain words and it will know where to go.
Good first asks:

- "Add a new event source for <venue website>" (it goes in `feed/aggregate.py`)
- "This venue's pin is in the wrong place" (fix is in `feed/venues.json`)
- "Change the look of the event cards" (`CoMoEvents/Views/EventCard.swift`)

## Day to day

- Never commit directly to `main`. Make a branch, push it, open a pull request:
  ```bash
  git checkout -b my-change
  git add -A && git commit -m "What and why"
  git push -u origin my-change
  gh pr create --fill
  ```
- Do not commit `CoMoEvents.xcodeproj` or `build/` (they are ignored) or `feed/cache/pages.json`.
- After adding or renaming Swift files, run `xcodegen generate` again.
- To refresh the events locally: `./scripts/update-feed.sh`. The first run takes a few minutes.
  A GitHub Action also rebuilds `feed/events.json` every two hours on its own.
- Build from the terminal to check nothing broke:
  ```bash
  xcodebuild -project CoMoEvents.xcodeproj -scheme CoMoEvents \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build build CODE_SIGNING_ALLOWED=NO
  ```

## Where things are

| Path | What |
|---|---|
| `feed/aggregate.py` | Pulls every source, geocodes, de-duplicates, writes `feed/events.json` |
| `feed/venues.json` | Known venues with coordinates; add here to fix a pin |
| `CoMoEvents/Models` | `Event`, `EventStore` (load, refresh, favorites), `Hotspot` (clustering), `UserProfile` |
| `CoMoEvents/Views` | Map, Upcoming, Saved, Profile, event cards and detail |
| `CoMoEvents/Support` | Theme and glass styling, location, Sign in with Apple + CloudKit |
| `README.md` | Sources, feed format, App Store notes |

Questions: open an issue on GitHub or message Ajay.
