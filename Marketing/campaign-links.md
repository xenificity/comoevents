# Campaign links

Every link and QR code points at one smart page, `https://comoevent.com/get/?c=<channel>`
([docs/get/index.html](../docs/get/index.html)). It checks Apple's public lookup API:

- **While CoMo Events is not on the App Store yet**, it opens the public TestFlight beta
  (`https://testflight.apple.com/join/HcEcPnzW`).
- **Once version 1.0 is live**, it opens the App Store page with the channel as the campaign token
  (`ct=`), so App Store Connect › App Analytics › Sources shows downloads per channel.

So printed flyers, posts and shared cards keep working through the launch with no reprint and no app update.

## Links per channel

| Channel | Use it for | Link | QR |
|---|---|---|---|
| `flyer` | Campus bulletin boards, tear-off flyer | https://comoevent.com/get/?c=flyer | [png](qr/qr-flyer.png) · [pdf](qr/qr-flyer.pdf) |
| `venue` | Counter cards at bars, venues, coffee shops | https://comoevent.com/get/?c=venue | [png](qr/qr-venue.png) · [pdf](qr/qr-venue.pdf) |
| `reddit` | r/columbiamo, r/mizzou posts and comments | https://comoevent.com/get/?c=reddit | [png](qr/qr-reddit.png) |
| `instagram` | Bio link, stories, weekly posts | https://comoevent.com/get/?c=instagram | [png](qr/qr-instagram.png) |
| `tiktok` | Bio link | https://comoevent.com/get/?c=tiktok | [png](qr/qr-tiktok.png) |
| `orgs` | Student org emails, GroupMe, newsletters | https://comoevent.com/get/?c=orgs | [png](qr/qr-orgs.png) |
| `press` | Press pitches and the press kit page | https://comoevent.com/get/?c=press | [png](qr/qr-press.png) |
| `email` | Your personal emails and signature | https://comoevent.com/get/?c=email | [png](qr/qr-email.png) |
| `tabling` | Student Center tabling, event booths | https://comoevent.com/get/?c=tabling | [png](qr/qr-tabling.png) |

Already wired in (no action needed):

| Channel | Where |
|---|---|
| `share` | QR and link on every shared event card in the app |
| `invite` | "Invite friends" button in the Friends tab |
| `site` | "Get it for iPhone" button on the website |

Need a new one? Any short name works, letters, digits and dashes: `…/get/?c=halloween`. Regenerate the
QR codes with `python3 Marketing/make_assets.py` after adding it to `CHANNELS` there.

## One setting to fill in after launch

App Analytics only attributes campaign downloads when the link also carries your **provider token**
(`pt=`). Find it in App Store Connect › Analytics › Acquisition › Campaigns › "Generate a Campaign Link"
(the `pt=` value in any generated link; it is the same for all your apps). Put it in the `PT` constant at
the top of `docs/get/index.html` and push. Until then the links still work; they just are not split by
channel in App Analytics.

## What the data will and will not show

- **Before launch (TestFlight):** no per-channel numbers. TestFlight only shows total testers and installs.
  Use the public link's tester count in App Store Connect › TestFlight › Public Beta as the running total.
- **After launch:** App Analytics › Sources › Campaigns shows impressions, product page views and
  first-time downloads per `ct`. Check it weekly and move effort to the top two channels.
- The app itself collects nothing. This stays true: attribution happens on Apple's side only.
