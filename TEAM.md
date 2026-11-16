# The CoMo Events team

CoMo Events is run by a small team of people, each with an AI officer that does the first pass
of the work. The officers are Claude Code agents. Their instructions live in this repository,
in `.claude/agents/`, so everyone who opens the project gets the same team.

| Officer | Role | Human owner | Ask them for |
|---|---|---|---|
| **Boone** | Chief Executive Officer (CEO) | Ajay | Plans, priorities, weekly status |
| **Hinkson** | Chief Validation Officer (CVO) | Parth | Feed checks, app and website testing, release checklist |
| **Broadway** | Chief Marketing Officer (CMO) | Anand | Posts, flyer copy, App Store text, outreach drafts |
| **Walnut** | Chief Legal Officer (CLO) | Ajay | Privacy, App Store rules, sources we may read, the name and mark |
| **Orr** | Chief Design Officer (CDO) | Ajay | App and website look, icons, flyers, banners |

The officer prepares; the human owner decides. No officer posts, emails, publishes or uploads
anything on its own.

## Get access (once)

1. Make a GitHub account and send your username to Ajay. Ajay adds you as a collaborator on
   `xenificity/comoevents`. Accept the invitation email.
2. Get Claude Code with your own Claude account: the Claude desktop app (Code tab), the
   `claude` command in a terminal, or claude.ai/code in a browser.

## Use the team

**In the browser, no setup (works on any computer)**
Open claude.ai/code, connect GitHub, choose the `comoevents` repository and start a session.
The officers load from the repository by themselves.

**On your own computer**
```bash
git clone https://github.com/xenificity/comoevents.git
```
Open the `comoevents` folder in the Claude desktop app (Code tab) or run `claude` inside it.

**Then talk to an officer by name**
- "Hinkson, check today's feed for wrong venues and bad times."
- "Broadway, draft a LinkedIn post about this weekend's events."
- "Walnut, does the privacy policy cover everything the app collects?"
- "Orr, review the event page on a small iPhone."
- "Boone, give me this week's status and the top three things to do."

You can also type `@` and pick the officer, or ask for two at once ("Broadway drafts the post
while Orr makes the picture").

To make Boone run the whole session and hand work to the others, start Claude Code in a
terminal with:
```bash
claude --agent boone
```

## Working at the same time

Several people can use the officers at once. Each person has their own session; the officers'
instructions and all the work are shared through GitHub.

- Start by getting the latest files: `git pull` (or ask Claude to "pull the latest").
- Do your work on a branch and open a pull request, as CONTRIBUTING.md describes. A robot
  refreshes the feed on `main` every two hours, so direct pushes to `main` often collide.
- Save drafts and results as files in the repository (for example `Marketing/drafts/`).
  A chat is private to the person who had it; a file in the repository is seen by everyone.
- To change how an officer behaves, edit its file in `.claude/agents/` and open a pull
  request. Once merged, everyone gets the new behavior on their next pull.

## What only works on Ajay's Mac

- Uploading a build to Apple (signing keys are kept outside the repository).
- Anything that needs Ajay's logins: App Store Connect, the LinkedIn page, the domain.

Simulator testing (Hinkson, Orr) needs any Mac with Xcode. Everything else, including feed
checks, drafts, legal reviews and web design, works in the browser.

## Ground rules

- The repository is public. No passwords, keys, home addresses, phone numbers or other
  private details in any file.
- CoMo Events stays free, with no ads. Anything involving money goes to Ajay first.
- Only claim what is true and live.
