# comoevents-social (Cloudflare Worker)

Links a CoMo Events iCloud user to Facebook or Google and finds friends who already use the app.
See the comment at the top of `src/index.js` for the flow. Stored data: one `SocialLink` record per
user and provider in the CloudKit public database (`provider`, `idHash` = HMAC-SHA256(SECRET, id),
`ckUser`), readable only by the server key. Friend lists and contacts are never stored.

## One-time setup

1. CloudKit
   - Import `feed/cloudkit-schema.ckdb` into Development, then deploy schema changes to Production.
   - Production → Tokens & Keys → Server-to-Server Keys → add the public key from
     `openssl ec -in ~/.comoevents-keys/ck-s2s.pem -pubout`. Note the Key ID.
2. Cloudflare: `npx wrangler login`, then `npx wrangler kv namespace create SOCIAL_KV` and paste the id into
   `wrangler.toml`. Deploy once (`npx wrangler deploy`) to get the workers.dev URL.
3. Meta for Developers: app type "Consumer" (Facebook Login). Valid OAuth redirect URI:
   `https://comoevent.com/auth/facebook/` (that page forwards to the worker). Privacy policy `https://comoevent.com/privacy.html`, data deletion
   callback `<worker>/facebook/deletion`. Permission `user_friends` needs App Review before the public can use it.
4. Google Cloud: enable People API; OAuth consent screen (External) with scopes `openid`, `email`,
   `contacts.readonly`; OAuth client "Web application" with redirect `https://comoevent.com/auth/google/`.
   Until Google verifies the app, only listed test users can connect.
5. Secrets (`npx wrangler secret put NAME`): `SECRET` (random 32 bytes, never change it: links depend on it),
   `CK_API_TOKEN`, `CK_KEY_ID`, `CK_PRIVATE_KEY` (contents of ~/.comoevents-keys/ck-s2s.pkcs8.pem),
   `FB_APP_ID`, `FB_APP_SECRET`, `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`.
6. Turn it on: set `window.SOCIAL_API` in `docs/ck-config.js` and `SocialConnect.api` in
   `CoMoEvents/Support/SocialConnect.swift` to the worker URL. Check `<worker>/health`.
