// CoMo Events social sign-in: Facebook friends and Google contacts -> friends in the app.
//
// Flow (same for web and iPhone):
//   1. The app gets the user's CloudKit web auth token and opens /auth/<provider>/start?ck=...&return=...
//   2. We check the token with CloudKit (who is this iCloud user?), remember it under a random state, and
//      send the browser to Facebook or Google.
//   3. On the way back (/auth/<provider>/callback) we swap the code for a token with our client secret,
//      read the user's own account id and their friends (Facebook: friends who also use CoMo Events;
//      Google: email addresses in their contacts), and:
//        - save ONE record for this user: SocialLink { provider, idHash = HMAC(secret, id), ckUser }
//        - look up which of their friends' HMACs already have a SocialLink -> those iCloud users are matches
//   4. We redirect back to the app with ?social=<result id>; the app fetches /result/<id> and adds the
//      matches to its friend list (FriendProfile "friend-<ckUser>").
// Nothing else is stored: no names, no emails, no friend lists. HMACs can't be reversed without SECRET.
//
// Accounts (Sign in with Google / Facebook, alongside iCloud):
//   /login/<provider>/start?client=ios|web&return=...  → provider sign-in (basic profile only) → back with ?login=<result id>
//   /result/<id> → { token, account }. The token is our own signed session ("s.<payload>.<sig>", 180 days).
//   Signed-in calls send "Authorization: Bearer <token>" (or "CK <CloudKit web auth token>" for iCloud users):
//     GET/PUT /me            name, picture and synced profile (KV acct:<id>)
//     POST /me/attendance    Going / I'm here / Went   → CloudKit Attendance  att-<id>-<event>
//     POST /me/friend        friend code + sharing     → CloudKit FriendProfile friend-<id>
//     POST /me/post          Post an event (pending)   → CloudKit SubmittedEvent post-<random>
//     POST /me/report        report a post             → CloudKit Report
//     POST /me/delete        delete the account and everything above
//     POST /img              upload a photo (event photo or profile picture) → { url }; GET /img/<id> serves it

const PROVIDERS = {
  facebook: {
    authorize: (env, redirect, state) =>
      `https://www.facebook.com/${env.FB_GRAPH_VERSION}/dialog/oauth?` + new URLSearchParams({
        client_id: env.FB_APP_ID, redirect_uri: redirect, state, response_type: "code", scope: "public_profile,user_friends",
      }),
    async identities(env, code, redirect) {
      const v = env.FB_GRAPH_VERSION;
      const tok = await j(`https://graph.facebook.com/${v}/oauth/access_token?` + new URLSearchParams({
        client_id: env.FB_APP_ID, client_secret: env.FB_APP_SECRET, redirect_uri: redirect, code }));
      if (!tok.access_token) throw new Error("facebook token: " + JSON.stringify(tok).slice(0, 200));
      const proof = await hmacHex(env.FB_APP_SECRET, tok.access_token);
      const q = (path) => `https://graph.facebook.com/${v}/${path}${path.includes("?") ? "&" : "?"}access_token=${encodeURIComponent(tok.access_token)}&appsecret_proof=${proof}`;
      const me = await j(q("me?fields=id"));
      if (!me.id) throw new Error("facebook me: " + JSON.stringify(me).slice(0, 200));
      const friends = [];
      let next = q("me/friends?limit=500&fields=id");
      for (let i = 0; next && i < 20; i++) {
        const page = await j(next);
        for (const f of page.data || []) friends.push(f.id);
        next = page.paging && page.paging.next;
      }
      return { self: ["fb:" + me.id], friends: friends.map((id) => "fb:" + id) };
    },
  },
  google: {
    authorize: (env, redirect, state) =>
      "https://accounts.google.com/o/oauth2/v2/auth?" + new URLSearchParams({
        client_id: env.GOOGLE_CLIENT_ID, redirect_uri: redirect, state, response_type: "code", access_type: "online",
        scope: "openid email https://www.googleapis.com/auth/contacts.readonly", prompt: "consent",
      }),
    async identities(env, code, redirect) {
      const tok = await j("https://oauth2.googleapis.com/token", {
        method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, redirect_uri: redirect, grant_type: "authorization_code" }),
      });
      if (!tok.access_token) throw new Error("google token: " + JSON.stringify(tok).slice(0, 200));
      const auth = { headers: { Authorization: "Bearer " + tok.access_token } };
      const me = await j("https://openidconnect.googleapis.com/v1/userinfo", auth);
      if (!me.email || me.email_verified === false) throw new Error("google: no verified email");
      const emails = new Set();
      let pageToken = "";
      for (let i = 0; i < 10; i++) {   // up to 10,000 contacts
        const page = await j("https://people.googleapis.com/v1/people/me/connections?" + new URLSearchParams({
          personFields: "emailAddresses", pageSize: "1000", ...(pageToken ? { pageToken } : {}) }), auth);
        for (const p of page.connections || []) for (const e of p.emailAddresses || []) if (e.value) emails.add(e.value.trim().toLowerCase());
        pageToken = page.nextPageToken;
        if (!pageToken) break;
      }
      emails.delete(me.email.toLowerCase());
      return { self: ["email:" + me.email.toLowerCase()], friends: [...emails].map((e) => "email:" + e) };
    },
  },
};

export default {
  async fetch(req, env) {
    const url = new URL(req.url);
    const cors = corsHeaders(req, env);
    if (req.method === "OPTIONS") return new Response(null, { headers: cors });
    try {
      const lm = url.pathname.match(/^\/login\/(facebook|google)\/start$/);
      if (lm) return await loginStart(lm[1], url, env);
      if (url.pathname.startsWith("/img/") && req.method === "GET") return await getImage(url.pathname.slice(5), env);
      if (url.pathname === "/img" && req.method === "POST") return await putImage(req, env, cors);
      if (url.pathname === "/me" || url.pathname.startsWith("/me/")) return await me(req, url, env, cors);
      const m = url.pathname.match(/^\/auth\/(facebook|google)\/(start|callback)$/);
      if (m && m[2] === "start") return await start(m[1], url, env);
      if (m && m[2] === "callback") return await callback(m[1], url, env);
      if (url.pathname.startsWith("/result/")) {
        const key = "result:" + url.pathname.slice(8);
        const body = await env.KV.get(key);
        if (body) await env.KV.delete(key);
        return json(body ? JSON.parse(body) : { error: "expired" }, body ? 200 : 404, cors);
      }
      if (url.pathname === "/unlink" && req.method === "POST") {
        const { ck, session, provider } = await req.json();
        const user = session ? ((await verifySession(env, session)) || {}).a : await ckUserFromToken(env, ck);
        if (!user) return json({ error: "Sign in again." }, 401, cors);
        const n = await deleteLinks(env, { ckUser: user, provider });
        return json({ ok: true, removed: n }, 200, cors);
      }
      if (url.pathname === "/facebook/deletion" && req.method === "POST") return await fbDeletion(req, env);
      if (url.pathname === "/deletion-status") return html(`<p>Your CoMo Events Facebook link has been deleted. Confirmation: ${esc(url.searchParams.get("code") || "")}</p>`);
      if (url.pathname === "/health") return json({ ok: true, facebook: !!(env.FB_APP_ID && env.FB_APP_SECRET), google: !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET), cloudkit: !!(env.CK_KEY_ID && env.CK_PRIVATE_KEY && env.SECRET), login: true, images: true }, 200, cors);
      return json({ error: "not found" }, 404, cors);
    } catch (e) {
      console.error("social error", url.pathname, String(e && e.stack || e));
      return html(`<h1>Something went wrong</h1><p>${esc(String(e.message || e)).slice(0, 300)}</p><p><a href="${env.SITE}/">Back to CoMo Events</a></p>`, 500);
    }
  },
};

// ---------------------------------------------------------------- flow
const RETURN_OK = (env, r) => r && (r.startsWith(env.SITE + "/") || r.startsWith("comoevents://"));

async function start(provider, url, env) {
  console.log("start", provider, "ck token length", (url.searchParams.get("ck") || "").length);
  const ck = url.searchParams.get("ck"), session = url.searchParams.get("session"), ret = url.searchParams.get("return") || env.SITE + "/?tab=friends";
  if (!ck && !session) return html("<p>Sign in to CoMo Events first.</p>", 400);
  if (!RETURN_OK(env, ret)) return html("<p>Bad return address.</p>", 400);
  // A Google/Facebook-account user is identified by their account id instead of an iCloud user.
  const ckUser = session ? (await verifySession(env, session) || {}).a : await ckUserFromToken(env, ck);
  if (!ckUser) return html("<p>Your sign-in expired. Sign in again and retry.</p>", 400);
  const state = randomId();
  await env.KV.put("state:" + state, JSON.stringify({ ckUser, ret, provider }), { expirationTtl: 600 });
  return Response.redirect(PROVIDERS[provider].authorize(env, redirectUri(url, provider), state), 302);
}

async function callback(provider, url, env) {
  console.log("callback", provider, "error=" + (url.searchParams.get("error") || ""), "code=" + !!url.searchParams.get("code"));
  const state = url.searchParams.get("state") || "";
  const saved = state && (await env.KV.get("state:" + state));
  if (!saved) return html("<p>This sign-in expired. Please try again from CoMo Events.</p>", 400);
  await env.KV.delete("state:" + state);
  const st = JSON.parse(saved);
  if (st.type === "login") return await loginCallback(provider, url, env, st);
  const { ckUser, ret } = st;
  const back = (params) => Response.redirect(ret + (ret.includes("?") ? "&" : "?") + new URLSearchParams(params), 302);
  if (url.searchParams.get("error")) return back({ social_error: url.searchParams.get("error_description") || url.searchParams.get("error") });

  const ids = await PROVIDERS[provider].identities(env, url.searchParams.get("code"), redirectUri(url, provider));
  // 1. save this user's link (one record per provider per iCloud user)
  const selfHashes = await Promise.all(ids.self.map((s) => hmacHex(env.SECRET, s)));
  await deleteLinks(env, { ckUser, provider });
  await ckModify(env, selfHashes.map((h) => ({
    operationType: "forceReplace",
    record: { recordType: "SocialLink", recordName: `link-${provider}-${h.slice(0, 40)}`,
              fields: { provider: { value: provider }, idHash: { value: h }, ckUser: { value: ckUser }, linkedAt: { value: Date.now(), type: "TIMESTAMP" } } },
  })));
  // 2. which friends are already linked?
  const friendHashes = await Promise.all(ids.friends.map((s) => hmacHex(env.SECRET, s)));
  const users = new Set();
  for (let i = 0; i < friendHashes.length; i += 100) {
    const recs = await ckQuery(env, "SocialLink", [{ fieldName: "idHash", comparator: "IN", fieldValue: { value: friendHashes.slice(i, i + 100), type: "STRING_LIST" } }]);
    for (const r of recs) if (r.fields && r.fields.ckUser && r.fields.ckUser.value !== ckUser) users.add(r.fields.ckUser.value);
  }
  // 3. their public friend profiles (only people who turned Friends on have one)
  const matches = [];
  const names = [...users].map((u) => "friend-" + u);
  for (let i = 0; i < names.length; i += 100) {
    const res = await ckPublic(env, "records/lookup", { records: names.slice(i, i + 100).map((n) => ({ recordName: n })) });
    for (const r of res.records || []) if (!r.serverErrorCode) matches.push({ recordName: r.recordName, displayName: (r.fields.displayName || {}).value || "A CoMo Events user" });
  }
  const id = randomId();
  await env.KV.put("result:" + id, JSON.stringify({ provider, checked: ids.friends.length, linkedUsers: users.size, matches }), { expirationTtl: 600 });
  return back({ social: id });
}

async function deleteLinks(env, { ckUser, provider }) {
  const filters = [{ fieldName: "ckUser", comparator: "EQUALS", fieldValue: { value: ckUser } }];
  if (provider) filters.push({ fieldName: "provider", comparator: "EQUALS", fieldValue: { value: provider } });
  const recs = await ckQuery(env, "SocialLink", filters);
  if (recs.length) await ckModify(env, recs.map((r) => ({ operationType: "forceDelete", record: { recordName: r.recordName } })));
  return recs.length;
}

// Facebook "data deletion callback": Facebook tells us a user removed the app; delete their link.
async function fbDeletion(req, env) {
  const form = await req.formData();
  const [sig, payload] = String(form.get("signed_request") || "").split(".");
  const expected = await hmacB64url(env.FB_APP_SECRET, payload || "");
  if (!sig || sig !== expected) return json({ error: "bad signature" }, 400);
  const data = JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/")));
  const h = await hmacHex(env.SECRET, "fb:" + data.user_id);
  const recs = await ckQuery(env, "SocialLink", [{ fieldName: "idHash", comparator: "EQUALS", fieldValue: { value: h } }]);
  if (recs.length) await ckModify(env, recs.map((r) => ({ operationType: "forceDelete", record: { recordName: r.recordName } })));
  const code = randomId().slice(0, 12);
  return json({ url: new URL("/deletion-status?code=" + code, req.url).toString(), confirmation_code: code }, 200);
}

// ---------------------------------------------------------------- accounts (Google / Facebook sign-in)
const LOGIN = {
  google: {
    authorize: (env, redirect, state) => "https://accounts.google.com/o/oauth2/v2/auth?" + new URLSearchParams({
      client_id: env.GOOGLE_CLIENT_ID, redirect_uri: redirect, state, response_type: "code", access_type: "online",
      scope: "openid email profile", prompt: "select_account" }),
    async profile(env, code, redirect) {
      const tok = await j("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ code, client_id: env.GOOGLE_CLIENT_ID, client_secret: env.GOOGLE_CLIENT_SECRET, redirect_uri: redirect, grant_type: "authorization_code" }) });
      if (!tok.access_token) throw new Error("google token: " + JSON.stringify(tok).slice(0, 200));
      const me = await j("https://openidconnect.googleapis.com/v1/userinfo", { headers: { Authorization: "Bearer " + tok.access_token } });
      if (!me.sub) throw new Error("google: no account id");
      const email = me.email && me.email_verified !== false ? me.email.toLowerCase() : null;
      return { sub: me.sub, name: me.name || me.given_name || "", email, picture: me.picture || null, links: email ? ["email:" + email] : [] };
    },
  },
  facebook: {
    authorize: (env, redirect, state) => `https://www.facebook.com/${env.FB_GRAPH_VERSION}/dialog/oauth?` + new URLSearchParams({
      client_id: env.FB_APP_ID, redirect_uri: redirect, state, response_type: "code", scope: "public_profile,email" }),
    async profile(env, code, redirect) {
      const v = env.FB_GRAPH_VERSION;
      const tok = await j(`https://graph.facebook.com/${v}/oauth/access_token?` + new URLSearchParams({
        client_id: env.FB_APP_ID, client_secret: env.FB_APP_SECRET, redirect_uri: redirect, code }));
      if (!tok.access_token) throw new Error("facebook token: " + JSON.stringify(tok).slice(0, 200));
      const proof = await hmacHex(env.FB_APP_SECRET, tok.access_token);
      const me = await j(`https://graph.facebook.com/${v}/me?fields=id,name,email,picture.width(400).height(400)&access_token=${encodeURIComponent(tok.access_token)}&appsecret_proof=${proof}`);
      if (!me.id) throw new Error("facebook me: " + JSON.stringify(me).slice(0, 200));
      const pic = me.picture && me.picture.data && !me.picture.data.is_silhouette ? me.picture.data.url : null;
      return { sub: me.id, name: me.name || "", email: me.email ? me.email.toLowerCase() : null, picture: pic, links: ["fb:" + me.id].concat(me.email ? ["email:" + me.email.toLowerCase()] : []) };
    },
  },
};

async function loginStart(provider, url, env) {
  const client = url.searchParams.get("client") === "ios" ? "ios" : "web";
  const ret = url.searchParams.get("return") || (client === "ios" ? "comoevents://login" : env.SITE + "/?tab=profile");
  if (!RETURN_OK(env, ret)) return html("<p>Bad return address.</p>", 400);
  const state = randomId();
  await env.KV.put("state:" + state, JSON.stringify({ type: "login", provider, ret }), { expirationTtl: 600 });
  return Response.redirect(LOGIN[provider].authorize(env, redirectUri(url, provider), state), 302);
}

async function loginCallback(provider, url, env, st) {
  const back = (params) => Response.redirect(st.ret + (st.ret.includes("?") ? "&" : "?") + new URLSearchParams(params), 302);
  if (url.searchParams.get("error")) return back({ login_error: url.searchParams.get("error_description") || url.searchParams.get("error") });
  const p = await LOGIN[provider].profile(env, url.searchParams.get("code"), redirectUri(url, provider));
  const id = provider[0] + "-" + (await hmacHex(env.SECRET, provider + ":" + p.sub)).slice(0, 24);
  const old = JSON.parse((await env.KV.get("acct:" + id)) || "null");
  const acct = { id, provider, name: (old && old.name) || p.name, email: p.email, providerPicture: p.picture,
                 profile: (old && old.profile) || { displayName: p.name || "", avatarUrl: p.picture || null }, createdAt: (old && old.createdAt) || Date.now() };
  await env.KV.put("acct:" + id, JSON.stringify(acct));
  // Let friends who connect Google contacts / Facebook find this account too.
  try {
    const hashes = await Promise.all(p.links.map((s) => hmacHex(env.SECRET, s)));
    await ckModify(env, hashes.map((h) => ({ operationType: "forceReplace", record: { recordType: "SocialLink", recordName: `link-${provider}-${h.slice(0, 40)}`,
      fields: { provider: { value: provider }, idHash: { value: h }, ckUser: { value: id }, linkedAt: { value: Date.now(), type: "TIMESTAMP" } } } })));
  } catch (e) { console.error("login link", String(e)); }
  const token = await makeSession(env, { a: id, p: provider });
  const rid = randomId();
  await env.KV.put("result:" + rid, JSON.stringify({ token, account: publicAccount(acct) }), { expirationTtl: 600 });
  return back({ login: rid });
}

function publicAccount(a) { return { id: a.id, provider: a.provider, name: a.name, email: a.email, profile: a.profile || {} }; }

async function makeSession(env, payload) {
  const body = btoa(JSON.stringify({ ...payload, exp: Date.now() + 180 * 86400000 })).replace(/=+$/, "");
  return "s." + body + "." + (await hmacB64url(env.SECRET, body));
}
async function verifySession(env, token) {
  const m = /^s\.([A-Za-z0-9+/]+)\.([A-Za-z0-9_-]+)$/.exec(token || "");
  if (!m || (await hmacB64url(env.SECRET, m[1])) !== m[2]) return null;
  const p = JSON.parse(atob(m[1]));
  return p.exp > Date.now() ? p : null;
}
/** Who is calling: a CoMo session (Google/Facebook account) or an iCloud user (CloudKit web auth token). */
async function who(req, env) {
  const h = req.headers.get("Authorization") || "";
  if (h.startsWith("Bearer ")) { const s = await verifySession(env, h.slice(7)); return s ? { id: s.a, kind: "account" } : null; }
  if (h.startsWith("CK ")) { try { return { id: await ckUserFromToken(env, h.slice(3)), kind: "icloud" }; } catch { return null; } }
  return null;
}

async function me(req, url, env, cors) {
  const u = await who(req, env);
  if (!u) return json({ error: "Sign in again." }, 401, cors);
  const path = url.pathname;
  if (path === "/me" && req.method === "GET") {
    const a = JSON.parse((await env.KV.get("acct:" + u.id)) || "null");
    return json(a ? publicAccount(a) : { id: u.id, profile: {} }, 200, cors);
  }
  if (path === "/me" && req.method === "PUT") {
    const body = await req.json();
    const a = JSON.parse((await env.KV.get("acct:" + u.id)) || "null") || { id: u.id, provider: u.kind, createdAt: Date.now() };
    const pr = body.profile || {};
    a.profile = { ...(a.profile || {}), ...pick(pr, ["displayName", "interests", "audience", "favorites", "avatarUrl"]), updatedAt: Date.now() };
    if (typeof pr.displayName === "string") a.name = pr.displayName.slice(0, 60);
    await env.KV.put("acct:" + u.id, JSON.stringify(a));
    return json(publicAccount(a), 200, cors);
  }
  if (req.method !== "POST") return json({ error: "not found" }, 404, cors);
  if (u.kind !== "account" && path !== "/me/delete") return json({ error: "iCloud users write to CloudKit directly." }, 400, cors);
  const b = await req.json().catch(() => ({}));
  if (path === "/me/attendance") {
    const ev = String(b.eventID || "").slice(0, 80);
    if (!ev) return json({ error: "eventID" }, 400, cors);
    const recordName = `att-${u.id}-${ev}`;
    if (!b.status) await ckModify(env, [{ operationType: "forceDelete", record: { recordName } }]);
    else await ckModify(env, [{ operationType: "forceReplace", record: { recordType: "Attendance", recordName, fields: {
      eventID: { value: ev }, status: { value: String(b.status).slice(0, 10) }, userID: { value: u.id },
      eventStart: { value: Number(b.eventStart) || Date.now(), type: "TIMESTAMP" }, updatedAt: { value: Date.now(), type: "TIMESTAMP" } } } }]);
    return json({ ok: true }, 200, cors);
  }
  if (path === "/me/friend") {
    const list = (x) => (Array.isArray(x) ? x.map(String).slice(0, 300) : []);
    const fields = { code: { value: String(b.code || "").slice(0, 12) }, displayName: { value: String(b.displayName || "").slice(0, 60) },
      favorites: { value: list(b.favorites), type: "STRING_LIST" }, going: { value: list(b.going), type: "STRING_LIST" },
      here: { value: list(b.here), type: "STRING_LIST" }, sharing: { value: b.sharing ? 1 : 0, type: "INT64" }, updatedAt: { value: Date.now(), type: "TIMESTAMP" } };
    if (b.avatarUrl) fields.avatarUrl = { value: String(b.avatarUrl).slice(0, 300) };
    if (b.remove) await ckModify(env, [{ operationType: "forceDelete", record: { recordName: "friend-" + u.id } }]);
    else await ckModify(env, [{ operationType: "forceReplace", record: { recordType: "FriendProfile", recordName: "friend-" + u.id, fields } }]);
    return json({ ok: true }, 200, cors);
  }
  if (path === "/me/post") {
    if (!(await rateOk(env, "post:" + u.id, 10))) return json({ error: "Too many posts today. Try again tomorrow." }, 429, cors);
    const str = (k, n) => ({ value: String(b[k] || "").slice(0, n) });
    const title = String(b.title || "").trim();
    if (title.length < 3 || !Number(b.start)) return json({ error: "Give the event a title and a start time." }, 400, cors);
    const fields = { title: str("title", 160), category: str("category", 20), venue: str("venue", 120), address: str("address", 160),
      price: str("price", 60), link: str("link", 400), details: str("details", 3000), submitterName: str("submitterName", 80),
      categories: { value: (Array.isArray(b.categories) ? b.categories : []).map(String).slice(0, 4), type: "STRING_LIST" },
      start: { value: Number(b.start), type: "TIMESTAMP" }, submitterID: { value: u.id }, status: { value: "pending" }, reports: { value: 0, type: "INT64" } };
    if (Number(b.end)) fields.end = { value: Number(b.end), type: "TIMESTAMP" };
    if (typeof b.lat === "number" && typeof b.lng === "number") { fields.lat = { value: b.lat, type: "DOUBLE" }; fields.lng = { value: b.lng, type: "DOUBLE" }; }
    if (b.imageUrl) fields.imageUrl = str("imageUrl", 300);
    const recordName = "post-" + randomId().slice(0, 20);
    await ckModify(env, [{ operationType: "create", record: { recordType: "SubmittedEvent", recordName, fields } }]);
    return json({ ok: true, recordName }, 200, cors);
  }
  if (path === "/me/report") {
    await ckModify(env, [{ operationType: "create", record: { recordType: "Report", recordName: "rep-" + randomId().slice(0, 20), fields: {
      eventRecordName: { value: String(b.eventRecordName || "").slice(0, 80) }, reason: { value: String(b.reason || "").slice(0, 300) }, reporterID: { value: u.id } } } }]);
    return json({ ok: true }, 200, cors);
  }
  if (path === "/me/delete") {   // App Store 5.1.1(v): accounts can be deleted from inside the app
    await env.KV.delete("acct:" + u.id);
    if (u.kind === "account") {
      const att = await ckQueryKeys(env, "Attendance", [{ fieldName: "userID", comparator: "EQUALS", fieldValue: { value: u.id } }]);
      await ckModify(env, att.map((r) => ({ operationType: "forceDelete", record: { recordName: r.recordName } }))
        .concat([{ operationType: "forceDelete", record: { recordName: "friend-" + u.id } }]));
      await deleteLinks(env, { ckUser: u.id });
    }
    return json({ ok: true }, 200, cors);
  }
  return json({ error: "not found" }, 404, cors);
}

function pick(o, keys) { const r = {}; for (const k of keys) if (k in o) r[k] = o[k]; return r; }
async function rateOk(env, key, perDay) {
  const k = "rate:" + key + ":" + new Date().toISOString().slice(0, 10);
  const n = Number(await env.KV.get(k)) || 0;
  if (n >= perDay) return false;
  await env.KV.put(k, String(n + 1), { expirationTtl: 2 * 86400 });
  return true;
}

// ---------------------------------------------------------------- photos (event photos, profile pictures)
const IMG_TYPES = { "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "image/heic": "heic" };
async function putImage(req, env, cors) {
  const u = await who(req, env);
  if (!u) return json({ error: "Sign in to add photos." }, 401, cors);
  const type = (req.headers.get("Content-Type") || "").split(";")[0];
  if (!IMG_TYPES[type]) return json({ error: "Send a JPEG, PNG or WebP photo." }, 415, cors);
  const buf = await req.arrayBuffer();
  if (buf.byteLength > 3_000_000) return json({ error: "That photo is too large (3 MB max)." }, 413, cors);
  if (!(await rateOk(env, "img:" + u.id, 30))) return json({ error: "Too many uploads today." }, 429, cors);
  const id = randomId().slice(0, 20) + "." + IMG_TYPES[type];
  await env.KV.put("img:" + id, buf, { metadata: { type, by: u.id } });
  return json({ url: new URL("/img/" + id, req.url).toString() }, 200, cors);
}
async function getImage(id, env) {
  const { value, metadata } = await env.KV.getWithMetadata("img:" + id, { type: "arrayBuffer" });
  if (!value) return new Response("not found", { status: 404 });
  return new Response(value, { headers: { "Content-Type": (metadata && metadata.type) || "image/jpeg", "Cache-Control": "public, max-age=31536000, immutable", "Access-Control-Allow-Origin": "*" } });
}

async function ckQueryKeys(env, recordType, filterBy) {
  const out = [];
  let marker;
  do {
    const body = { query: { recordType, filterBy }, resultsLimit: 200, desiredKeys: ["userID"] };
    if (marker) body.continuationMarker = marker;
    const r = await ckSigned(env, "records/query", body);
    if (r.serverErrorCode) throw new Error("CloudKit query: " + r.serverErrorCode);
    out.push(...(r.records || []));
    marker = r.continuationMarker;
  } while (marker && out.length < 5000);
  return out;
}

// ---------------------------------------------------------------- CloudKit
async function ckUserFromToken(env, ckWebAuthToken) {
  const u = `https://api.apple-cloudkit.com/database/1/${env.CK_CONTAINER}/${env.CK_ENV}/public/users/current?` +
    new URLSearchParams({ ckAPIToken: env.CK_API_TOKEN, ckWebAuthToken });
  const r = await j(u, { headers: { Origin: env.SITE } });
  if (!r.userRecordName) throw new Error("iCloud sign-in could not be verified. Sign in again and retry.");
  return r.userRecordName;
}

async function ckQuery(env, recordType, filterBy) {
  const out = [];
  let marker;
  do {
    const body = { query: { recordType, filterBy }, resultsLimit: 200, desiredKeys: ["ckUser", "provider", "idHash"] };
    if (marker) body.continuationMarker = marker;
    const r = await ckSigned(env, "records/query", body);
    if (r.serverErrorCode) throw new Error("CloudKit query: " + r.serverErrorCode + " " + (r.reason || ""));
    out.push(...(r.records || []));
    marker = r.continuationMarker;
  } while (marker && out.length < 5000);
  return out;
}

async function ckModify(env, operations) {
  for (let i = 0; i < operations.length; i += 200) {
    const r = await ckSigned(env, "records/modify", { operations: operations.slice(i, i + 200), atomic: false });
    const bad = (r.records || []).find((x) => x.serverErrorCode && x.serverErrorCode !== "NOT_FOUND");
    if (r.serverErrorCode || bad) throw new Error("CloudKit save: " + (r.serverErrorCode || bad.serverErrorCode) + " " + (r.reason || (bad && bad.reason) || ""));
  }
}

// Unsigned read with the public API token (FriendProfile is world-readable).
async function ckPublic(env, op, body) {
  return j(`https://api.apple-cloudkit.com/database/1/${env.CK_CONTAINER}/${env.CK_ENV}/public/${op}?ckAPIToken=${env.CK_API_TOKEN}`,
    { method: "POST", headers: { Origin: env.SITE }, body: JSON.stringify(body) });
}

// Server-to-server request signed with our CloudKit key (ECDSA P-256), as Apple's CloudKit Web Services require.
async function ckSigned(env, op, body) {
  const subpath = `/database/1/${env.CK_CONTAINER}/${env.CK_ENV}/public/${op}`;
  const text = JSON.stringify(body);
  const date = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
  const bodyHash = b64(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text)));
  const key = await importEcKey(env.CK_PRIVATE_KEY);
  const raw = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(`${date}:${bodyHash}:${subpath}`)));
  const r = await fetch("https://api.apple-cloudkit.com" + subpath, {
    method: "POST", body: text,
    headers: { "Content-Type": "application/json", "X-Apple-CloudKit-Request-KeyID": env.CK_KEY_ID,
               "X-Apple-CloudKit-Request-ISO8601Date": date, "X-Apple-CloudKit-Request-SignatureV1": b64(derSignature(raw)) },
  });
  return r.json();
}

let cachedKey;
async function importEcKey(pem) {
  if (cachedKey) return cachedKey;
  const der = Uint8Array.from(atob(pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "")), (c) => c.charCodeAt(0));
  cachedKey = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  return cachedKey;
}

// WebCrypto gives r||s (64 bytes); CloudKit wants an ASN.1 DER ECDSA signature.
function derSignature(raw) {
  const int = (b) => { let i = 0; while (i < b.length - 1 && b[i] === 0) i++; b = b.slice(i); return b[0] & 0x80 ? Uint8Array.of(0, ...b) : b; };
  const r = int(raw.slice(0, 32)), s = int(raw.slice(32));
  return Uint8Array.of(0x30, r.length + s.length + 4, 0x02, r.length, ...r, 0x02, s.length, ...s);
}

// ---------------------------------------------------------------- helpers
// Facebook/Google send people back to comoevent.com/auth/<provider>/ (a verified domain), which forwards here.
function redirectUri(url, provider) { return `${url.origin.includes("workers.dev") ? "https://comoevent.com" : url.origin}/auth/${provider}/`; }
async function j(u, opts) { const r = await fetch(u, opts); const t = await r.text(); try { return JSON.parse(t); } catch { throw new Error(`${r.status} from ${new URL(u).host}`); } }
function randomId() { return [...crypto.getRandomValues(new Uint8Array(16))].map((b) => b.toString(16).padStart(2, "0")).join(""); }
function b64(buf) { return btoa(String.fromCharCode(...new Uint8Array(buf))); }
async function hmacRaw(secret, msg) {
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  return new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg)));
}
async function hmacHex(secret, msg) { return [...(await hmacRaw(secret, msg))].map((b) => b.toString(16).padStart(2, "0")).join(""); }
async function hmacB64url(secret, msg) { return b64(await hmacRaw(secret, msg)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, ""); }
function corsHeaders(req, env) {
  const o = req.headers.get("Origin") || "";
  return o === env.SITE || o === "https://www.comoevent.com" ? { "Access-Control-Allow-Origin": o, "Access-Control-Allow-Methods": "GET,POST,PUT,OPTIONS", "Access-Control-Allow-Headers": "Content-Type, Authorization", Vary: "Origin" } : {};
}
function json(obj, status = 200, headers = {}) { return new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", ...headers } }); }
function html(body, status = 200) { return new Response(`<!doctype html><meta name="viewport" content="width=device-width,initial-scale=1"><body style="font-family:-apple-system,sans-serif;padding:24px">${body}</body>`, { status, headers: { "Content-Type": "text/html; charset=utf-8" } }); }
function esc(s) { return String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]); }
