/* CloudKit layer for the web app: the same public records as the iPhone app.
   - Attendance   att-<user>-<event>: eventID, status (going|here|went), userID, eventStart, updatedAt
   - FriendProfile friend-<user>: code, displayName, favorites, going, here, sharing, updatedAt
   - SubmittedEvent (pending until a moderator's Approval record), Approval, Report
   Everything degrades to "off" when there is no API token or CloudKit JS failed to load. */
(function () {
  "use strict";

  var CONTAINER = "iCloud.com.xenificity.comoevents";
  var MODERATORS = ["_c8e8240fd2a875267839a35bf9779b30", "_c8e8240fd2a875267839a35bf9779b30v"];
  var BLOCKED_WORDS = ["fuck", "fucking", "motherfucker", "shit", "bullshit", "asshole", "bitch", "bitches", "cunt", "dick", "dicks", "cock", "pussy",
    "whore", "slut", "faggot", "fag", "dyke", "tranny", "retard", "retarded", "nigger", "nigga", "chink", "spic", "kike", "wetback",
    "towelhead", "raghead", "porn", "porno", "xxx", "nude", "nudes", "escort", "escorts", "onlyfans", "hookup", "blowjob", "handjob",
    "rape", "molest", "kill yourself", "kys", "heroin", "meth", "cocaine", "fentanyl"];

  var Cloud = {
    available: false, signedIn: false, userRecordName: null, error: null,
    attendance: { mine: load("attendance.mine", {}), counts: {} },
    friends: { enabled: load("friends.enabled", false), share: load("friends.share", false), ids: load("friends.ids", []), blocked: load("friends.blocked", []), list: [], myCode: null },
    community: { approved: [], blocked: load("community.blocked", []) },
    listeners: [],
    on: function (fn) { this.listeners.push(fn); },
    emit: function (what) { this.listeners.forEach(function (fn) { try { fn(what); } catch (e) {} }); }
  };
  var container, db;

  function load(k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } }
  function save(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  function val(f) { return f && f.value !== undefined ? f.value : null; }

  // ---------- content filter (mirrors ContentFilter.swift) ----------
  Cloud.offendingTerm = function (text) {
    var n = String(text || "").replace(/0/g, "o").replace(/1/g, "i").replace(/3/g, "e").replace(/4/g, "a").replace(/\$/g, "s").replace(/@/g, "a").toLowerCase();
    for (var i = 0; i < BLOCKED_WORDS.length; i++) {
      var w = BLOCKED_WORDS[i].replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      if (new RegExp("(?<![a-z0-9])" + w + "(?![a-z0-9])").test(n)) return BLOCKED_WORDS[i];
    }
    return null;
  };
  Cloud.safeName = function (name, fallback) {
    var t = String(name || "").trim();
    return !t || Cloud.offendingTerm(t) ? (fallback || "A CoMo Events user") : t;
  };

  // ---------- friend code (FNV-1a, same alphabet and arithmetic as FriendsStore.code) ----------
  Cloud.code = function (recordName) {
    var alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", mask = (1n << 64n) - 1n;
    var h = 1469598103934665603n;
    for (var i = 0; i < recordName.length; i++) { h = ((h ^ BigInt(recordName.charCodeAt(i) & 0xff)) * 1099511628211n) & mask; }
    var out = "";
    for (var k = 0; k < 6; k++) { out += alphabet[Number(h % 32n)]; h = h / 32n; }
    return out;
  };

  // ---------- setup ----------
  Cloud.setup = function () {
    if (!window.CK_TOKEN || !window.CloudKit) { Cloud.available = false; Cloud.emit("ready"); return Promise.resolve(false); }
    try {
      CloudKit.configure({ containers: [{ containerIdentifier: CONTAINER, apiTokenAuth: { apiToken: window.CK_TOKEN, persist: true, signInButton: { id: "ck-signin", theme: "black" }, signOutButton: { id: "ck-signout", theme: "black" } }, environment: "production" }] });
      container = CloudKit.getDefaultContainer(); db = container.publicCloudDatabase;
      Cloud.available = true;
    } catch (e) { Cloud.available = false; Cloud.error = String(e); Cloud.emit("ready"); return Promise.resolve(false); }
    function signedIn(identity) {
      Cloud.signedIn = true; Cloud.userRecordName = identity.userRecordName;
      Cloud.friends.myCode = Cloud.code(identity.userRecordName);
      Cloud.emit("auth");
      Cloud.refreshAll();
      container.whenUserSignsOut().then(signedOut);
    }
    function signedOut() {
      Cloud.signedIn = false; Cloud.userRecordName = null; Cloud.friends.myCode = null;
      Cloud.emit("auth");
      container.whenUserSignsIn().then(signedIn);
    }
    return container.setUpAuth().then(function (identity) {
      Cloud.emit("ready");
      if (identity) signedIn(identity); else { container.whenUserSignsIn().then(signedIn); Cloud.emit("auth"); }
      Cloud.refreshAll();
      return true;
    }).catch(function (e) { Cloud.error = (e && e.reason) || String(e); Cloud.emit("ready"); return false; });
  };
  Cloud.refreshAll = function () {
    if (!Cloud.available) return;
    Cloud.refreshCounts(); Cloud.loadCommunity(); if (Cloud.friends.enabled) Cloud.refreshFriends();
    Cloud.refreshUsers(); if (Cloud.signedIn) Cloud.registerInstall();
  };

  // ---------- "N people use CoMo Events" ----------
  // One anonymous Install record per browser (signed-in users only can write), read by everyone.
  Cloud.users = { total: load("usage.total", 0), updatedAt: load("usage.updatedAt", 0) };
  var registering = null;
  Cloud.registerInstall = function () {
    if (!Cloud.signedIn) return Promise.resolve();
    if (registering) return registering;                 // two callers at once must not make two records
    var name = load("usage.recordName", null);
    if (!name) { name = "install-web-" + ([1e7] + -1e3 + -4e3 + -8e3 + -1e11).replace(/[018]/g, function (c) { return (c ^ crypto.getRandomValues(new Uint8Array(1))[0] & 15 >> c / 4).toString(16); }); save("usage.recordName", name); }
    var last = load("usage.lastSeen", 0);
    if (Date.now() - last < 7 * 86400e3) return Promise.resolve();
    registering = fetchOne(name).then(function (existing) {
      var fields = { lastSeen: Date.now(), platform: "web", appVersion: "web" };
      if (!existing) fields.installedAt = Date.now();
      var rec = { recordType: "Install", recordName: name, fields: {} };
      Object.keys(fields).forEach(function (k) { rec.fields[k] = { value: fields[k] }; });
      if (existing) rec.recordChangeTag = existing.recordChangeTag;
      return db.saveRecords([rec]).then(function (r) { if (r.hasErrors) throw r.errors[0]; save("usage.lastSeen", Date.now()); });
    }).catch(function () {}).then(function () { registering = null; });
    return registering;
  };
  Cloud.refreshUsers = function (force) {
    if (!Cloud.available) return Promise.resolve();
    if (!force && Date.now() - Cloud.users.updatedAt < 6 * 3600e3) { Cloud.emit("users"); return Promise.resolve(); }
    return queryAll({ recordType: "Install", filterBy: [{ fieldName: "installedAt", comparator: "GREATER_THAN", fieldValue: { value: 0 } }], desiredKeys: [] }, 400).then(function (recs) {
      Cloud.users = { total: recs.length, updatedAt: Date.now() };
      save("usage.total", recs.length); save("usage.updatedAt", Date.now());
      Cloud.emit("users");
    }).catch(function () {});
  };

  // ---------- query helpers ----------
  function queryAll(query, limit) {
    var out = [];
    function page(resp) {
      if (resp.hasErrors) throw resp.errors[0];
      out = out.concat(resp.records || []);
      if (resp.moreComing && out.length < 3000) return db.performQuery(resp).then(page);
      return out;
    }
    return db.performQuery(query, { resultsLimit: limit || 400 }).then(page);
  }
  function fetchOne(recordName) {
    return db.fetchRecords([{ recordName: recordName }]).then(function (r) {
      var rec = r.records && r.records[0];
      return rec && !rec.serverErrorCode ? rec : null;
    }).catch(function () { return null; });
  }
  function upsert(recordType, recordName, fields) {
    return fetchOne(recordName).then(function (existing) {
      var rec = { recordType: recordType, recordName: recordName, fields: {} };
      Object.keys(fields).forEach(function (k) { rec.fields[k] = { value: fields[k] }; });
      if (existing) rec.recordChangeTag = existing.recordChangeTag;
      return db.saveRecords([rec]).then(function (r) { if (r.hasErrors) throw r.errors[0]; return r.records[0]; });
    });
  }
  function err(e) { return (e && (e.reason || e.message)) || String(e); }

  // ---------- attendance ----------
  Cloud.status = function (eventId) { return Cloud.attendance.mine[eventId] || null; };
  Cloud.count = function (eventId) { return Cloud.attendance.counts[eventId] || { going: 0, here: 0, went: 0 }; };
  Cloud.setStatus = function (event, status) {
    // Adjust the shared count at once; CloudKit's query index catches up a few seconds later.
    var prev = Cloud.attendance.mine[event.id], c = Cloud.attendance.counts[event.id] = Cloud.attendance.counts[event.id] || { going: 0, here: 0, went: 0 };
    if (prev && c[prev] > 0) c[prev]--;
    if (status) c[status]++;
    if (status) Cloud.attendance.mine[event.id] = status; else delete Cloud.attendance.mine[event.id];
    save("attendance.mine", Cloud.attendance.mine);
    Cloud.emit("attendance");
    if (Cloud.friends.enabled) Cloud.publishFriend();
    if (!Cloud.signedIn) return Promise.resolve("Sign in with iCloud (Profile tab) to share your plans with everyone.");
    var name = "att-" + Cloud.userRecordName + "-" + event.id;
    var p = status
      ? upsert("Attendance", name, { eventID: event.id, status: status, userID: Cloud.userRecordName, eventStart: event._start.getTime(), updatedAt: Date.now() })
      : db.deleteRecords([{ recordName: name }]);
    return p.then(function () { setTimeout(Cloud.refreshCounts, 4000); return null; }).catch(function (e) { return err(e); });
  };
  Cloud.refreshCounts = function () {
    if (!Cloud.available) return Promise.resolve();
    var since = Date.now() - 36 * 3600e3;
    return queryAll({ recordType: "Attendance", filterBy: [{ fieldName: "eventStart", comparator: "GREATER_THAN_OR_EQUALS", fieldValue: { value: since } }] }).then(function (recs) {
      var totals = {};
      recs.forEach(function (r) {
        var id = val(r.fields.eventID), s = val(r.fields.status); if (!id || !s) return;
        var t = totals[id] = totals[id] || { going: 0, here: 0, went: 0 };
        if (t[s] !== undefined) t[s]++;
      });
      Cloud.attendance.counts = totals; Cloud.emit("attendance");
    }).catch(function () {});
  };

  // ---------- friends ----------
  Cloud.enableFriends = function () {
    if (!Cloud.signedIn) return Promise.resolve("Sign in with iCloud first (Profile tab).");
    Cloud.friends.enabled = true; save("friends.enabled", true);
    return Cloud.publishFriend().then(function () { return Cloud.refreshFriends(); }).then(function () { Cloud.emit("friends"); return null; });
  };
  Cloud.setShare = function (on) { Cloud.friends.share = on; save("friends.share", on); Cloud.publishFriend(); Cloud.emit("friends"); };
  Cloud.publishFriend = function (profile) {
    if (!Cloud.signedIn || !Cloud.friends.enabled) return Promise.resolve();
    var p = profile || Cloud.profileForFriends || {};
    var mine = Cloud.attendance.mine, going = [], here = [];
    Object.keys(mine).forEach(function (id) { if (mine[id] === "going") going.push(id); if (mine[id] === "here") here.push(id); });
    var share = Cloud.friends.share;
    return upsert("FriendProfile", "friend-" + Cloud.userRecordName, {
      displayName: Cloud.safeName(p.name || "", "A CoMo Events user"), code: Cloud.friends.myCode, sharing: share ? 1 : 0,
      favorites: share ? (p.favorites || []) : [], going: share ? going.sort() : [], here: share ? here.sort() : [], updatedAt: Date.now()
    }).catch(function (e) { Cloud.error = err(e); });
  };
  Cloud.addFriend = function (raw) {
    var code = String(raw || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
    if (code.length !== 6) return Promise.resolve("Codes are 6 letters.");
    if (code === Cloud.friends.myCode) return Promise.resolve("That's your own code.");
    return db.performQuery({ recordType: "FriendProfile", filterBy: [{ fieldName: "code", comparator: "EQUALS", fieldValue: { value: code } }] }, { resultsLimit: 1 }).then(function (r) {
      var rec = r.records && r.records[0];
      if (!rec) return "No one has that code yet.";
      if (Cloud.friends.blocked.indexOf(rec.recordName) >= 0) return "You blocked this person.";
      if (Cloud.friends.ids.indexOf(rec.recordName) < 0) { Cloud.friends.ids.push(rec.recordName); save("friends.ids", Cloud.friends.ids); }
      return Cloud.refreshFriends().then(function () { return null; });
    }).catch(function (e) { return err(e); });
  };
  // ---------- find friends through Facebook / Google (comoevents-social worker) ----------
  Cloud.social = { api: (window.SOCIAL_API || "").replace(/\/$/, "") };
  Cloud.socialToken = function () {
    try { return (container && container._auth && container._auth._ckSession) || (container && container.getConfig && container.getConfig().ckWebAuthToken) || null; } catch (e) { return null; }
  };
  // Leaves the page: the worker sends the browser to Facebook/Google and back to ?tab=friends&social=<id>.
  Cloud.connectSocial = function (provider) {
    if (!Cloud.social.api) return Promise.resolve("Facebook and Google sign-in aren't set up yet.");
    if (!Cloud.signedIn) return Promise.resolve("Sign in with iCloud first.");
    var ready = Cloud.friends.enabled ? Promise.resolve(null) : Cloud.enableFriends();
    return ready.then(function (msg) {
      if (msg) return msg;
      var tok = Cloud.socialToken();
      if (!tok) return "Couldn't read your iCloud sign-in. Sign out and back in, then try again.";
      location.href = Cloud.social.api + "/auth/" + provider + "/start?" + new URLSearchParams({ ck: tok, return: location.origin + "/?tab=friends" });
      return null;
    });
  };
  // Called once on load when the URL has ?social=<id>: add every match as a friend.
  Cloud.finishSocial = function (id) {
    if (!Cloud.social.api) return Promise.resolve(null);
    return fetch(Cloud.social.api + "/result/" + encodeURIComponent(id)).then(function (r) { return r.json(); }).then(function (res) {
      if (res.error) return "That sign-in expired. Try again.";
      var added = 0;
      (res.matches || []).forEach(function (m) {
        if (Cloud.friends.blocked.indexOf(m.recordName) >= 0 || Cloud.friends.ids.indexOf(m.recordName) >= 0) return;
        Cloud.friends.ids.push(m.recordName); added++;
      });
      save("friends.ids", Cloud.friends.ids);
      save("social." + res.provider, Date.now());
      var who = res.provider === "facebook" ? "Facebook friends" : "Google contacts";
      return Cloud.refreshFriends().then(function () {
        if (added) return "Added " + added + " friend" + (added === 1 ? "" : "s") + " from your " + who + ".";
        if (res.linkedUsers) return "Your " + who + " on CoMo Events haven't turned on Friends yet. They'll appear when they do.";
        return "Connected. None of your " + who + " use CoMo Events yet. Invite them, and connect again later.";
      });
    }).catch(function () { return "Couldn't finish connecting. Try again."; });
  };
  Cloud.disconnectSocial = function (provider) {
    var tok = Cloud.socialToken();
    if (!Cloud.social.api || !tok) return Promise.resolve("Sign in with iCloud first.");
    return fetch(Cloud.social.api + "/unlink", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ ck: tok, provider: provider }) })
      .then(function (r) { return r.json(); }).then(function () { try { localStorage.removeItem("social." + provider); } catch (e) {} return "Disconnected " + (provider === "facebook" ? "Facebook" : "Google") + "."; })
      .catch(function () { return "Couldn't disconnect. Try again."; });
  };
  Cloud.socialConnected = function (provider) { return !!load("social." + provider, 0); };

  Cloud.removeFriend = function (id) { Cloud.friends.ids = Cloud.friends.ids.filter(function (x) { return x !== id; }); save("friends.ids", Cloud.friends.ids); Cloud.friends.list = Cloud.friends.list.filter(function (f) { return f.id !== id; }); Cloud.emit("friends"); };
  Cloud.blockFriend = function (id) { Cloud.removeFriend(id); if (Cloud.friends.blocked.indexOf(id) < 0) { Cloud.friends.blocked.push(id); save("friends.blocked", Cloud.friends.blocked); } };
  Cloud.refreshFriends = function () {
    if (!Cloud.available || !Cloud.friends.ids.length) { Cloud.friends.list = []; Cloud.emit("friends"); return Promise.resolve(); }
    return db.fetchRecords(Cloud.friends.ids.map(function (n) { return { recordName: n }; })).then(function (r) {
      Cloud.friends.list = (r.records || []).filter(function (rec) { return !rec.serverErrorCode; }).map(function (rec) {
        var f = rec.fields;
        return { id: rec.recordName, name: Cloud.safeName(val(f.displayName), "Friend"), code: val(f.code) || "", favorites: val(f.favorites) || [], going: val(f.going) || [], here: val(f.here) || [], sharing: val(f.sharing) === 1 };
      });
      Cloud.emit("friends");
    }).catch(function (e) { Cloud.error = err(e); });
  };
  Cloud.friendsGoing = function (eventId) { return Cloud.friends.list.filter(function (f) { return f.favorites.indexOf(eventId) >= 0 || f.going.indexOf(eventId) >= 0 || f.here.indexOf(eventId) >= 0; }); };
  Cloud.friendsHere = function (eventId) { return Cloud.friends.list.filter(function (f) { return f.here.indexOf(eventId) >= 0; }); };
  Cloud.friendsAt = function (ids) {
    var here = Cloud.friends.list.filter(function (f) { return f.here.some(function (x) { return ids.has(x); }); });
    var going = Cloud.friends.list.filter(function (f) { return here.indexOf(f) < 0 && (f.going.some(function (x) { return ids.has(x); }) || f.favorites.some(function (x) { return ids.has(x); })); });
    return { here: here, going: going };
  };

  // ---------- venue table (feed/venues.json, served as ../venues.json) ----------
  var venuesPromise;
  Cloud.venues = function () {
    venuesPromise = venuesPromise || fetch("venues.json").then(function (r) { return r.json(); }).catch(function () { return {}; });
    return venuesPromise;
  };
  /// Name or alias -> {name, address, lat, lng, phone, website}; Nominatim (Columbia) when the table has nothing.
  Cloud.lookupVenue = function (name) {
    var key = String(name || "").trim().toLowerCase();
    if (key.length < 3) return Promise.resolve(null);
    return Cloud.venues().then(function (venues) {
      var names = Object.keys(venues);
      for (var i = 0; i < names.length; i++) {
        var v = venues[names[i]], al = (v.aliases || []).map(function (a) { return a.toLowerCase(); });
        if (key === names[i].toLowerCase() || al.indexOf(key) >= 0 || (key.length > 4 && names[i].toLowerCase().indexOf(key) >= 0)) {
          var addr = v.address ? (/MO/.test(v.address) ? v.address : v.address + ", Columbia, MO") : null;
          return { name: names[i], address: addr, lat: v.lat, lng: v.lng, phone: v.phone || null, website: v.website || null, fromTable: true };
        }
      }
      var url = "https://nominatim.openstreetmap.org/search?format=json&limit=1&addressdetails=1&bounded=1&viewbox=-92.48,39.05,-92.18,38.85&q=" + encodeURIComponent(key + ", Columbia, MO");
      return fetch(url, { headers: { "Accept": "application/json" } }).then(function (r) { return r.json(); }).then(function (j) {
        if (!j || !j[0]) return null;
        var a = j[0].address || {}, line = [a.house_number, a.road].filter(Boolean).join(" ");
        return { name: j[0].name || key, address: [line, a.city || a.town || "Columbia", "MO", a.postcode].filter(Boolean).join(", "), lat: parseFloat(j[0].lat), lng: parseFloat(j[0].lon), phone: null, website: null, fromTable: false };
      }).catch(function () { return null; });
    });
  };

  // ---------- community ----------
  var venueIndex = null;
  function venueMatch(name) {
    var key = String(name || "").trim().toLowerCase(); if (key.length < 3) return null;
    var names = Object.keys(venueIndex);
    for (var i = 0; i < names.length; i++) {
      var v = venueIndex[names[i]], al = (v.aliases || []).map(function (a) { return a.toLowerCase(); });
      if (key === names[i].toLowerCase() || al.indexOf(key) >= 0 || (key.length > 4 && names[i].toLowerCase().indexOf(key) >= 0))
        return { address: v.address ? (/MO/.test(v.address) ? v.address : v.address + ", Columbia, MO") : null, lat: v.lat, lng: v.lng, phone: v.phone, website: v.website };
    }
    return null;
  }
  function mapEvent(rec) {
    var f = rec.fields, title = val(f.title), start = val(f.start);
    if (!title || !start) return null;
    var name = Cloud.safeName(val(f.submitterName), "a community member");
    var cat = val(f.category) || "community", cats = val(f.categories) || [];
    var v = (venueIndex && venueMatch(val(f.venue))) || {};
    return {
      id: "community:" + rec.recordName, source: "community", sourceName: "Posted in CoMo Events", title: title,
      start: new Date(start).toISOString(), end: val(f.end) ? new Date(val(f.end)).toISOString() : null, allDay: false, timeTBD: false,
      venue: val(f.venue) || null, address: val(f.address) || v.address || null, lat: val(f.lat) != null ? val(f.lat) : (v.lat || null), lng: val(f.lng) != null ? val(f.lng) : (v.lng || null),
      url: val(f.link) || v.website || null, ticketUrl: null, phone: v.phone || null, price: val(f.price) || null,
      category: cat, categories: cats.length ? cats : [cat], imageUrl: null, description: val(f.details) || "",
      organizer: "Posted by " + name, audience: ["groups", "singles", "couples", "family"], alsoOn: [],
      submitterID: val(f.submitterID) || null, recordName: rec.recordName, status: val(f.status)
    };
  }
  Cloud.loadCommunity = function () {
    if (!Cloud.available) return Promise.resolve();
    var decisions = {}, reports = {};
    return Cloud.venues().then(function (vs) { venueIndex = vs || {}; return queryAll({ recordType: "Approval" }, 500); }).then(function (recs) {
      recs.forEach(function (r) {
        var by = r.created && r.created.userRecordName;
        if (MODERATORS.indexOf(by) < 0 && by !== "__defaultOwner__") return;
        decisions[val(r.fields.eventRecordName)] = val(r.fields.approved) === 1;
      });
      return queryAll({ recordType: "Report" }, 500);
    }).then(function (recs) {
      recs.forEach(function (r) { var n = val(r.fields.eventRecordName); reports[n] = (reports[n] || 0) + 1; });
      return queryAll({ recordType: "SubmittedEvent", filterBy: [{ fieldName: "start", comparator: "GREATER_THAN_OR_EQUALS", fieldValue: { value: Date.now() - 6 * 3600e3 } }], sortBy: [{ fieldName: "start" }] });
    }).then(function (recs) {
      Cloud.community.approved = recs.filter(function (r) { return decisions[r.recordName] === true && (reports[r.recordName] || 0) < 3 && Cloud.community.blocked.indexOf(val(r.fields.submitterID) || "") < 0; })
        .map(mapEvent).filter(Boolean);
      Cloud.community.mine = recs.filter(function (r) { return Cloud.userRecordName && val(r.fields.submitterID) === Cloud.userRecordName; }).map(function (r) { var e = mapEvent(r); if (e) e.decision = decisions[r.recordName]; return e; }).filter(Boolean);
      Cloud.emit("community");
    }).catch(function (e) { Cloud.error = err(e); });
  };
  Cloud.geocode = function (venue, address) {
    var q = [venue, address].filter(Boolean).join(", ");
    return fetch("venues.json").then(function (r) { return r.json(); }).catch(function () { return {}; }).then(function (venues) {
      var v = (venue || "").toLowerCase().trim();
      var names = Object.keys(venues);
      for (var i = 0; i < names.length; i++) {
        var entry = venues[names[i]], al = [names[i].toLowerCase()].concat((entry.aliases || []).map(function (a) { return a.toLowerCase(); }));
        if (v && al.some(function (a) { return a === v || (a.length > 4 && v.indexOf(a) >= 0); })) return { lat: entry.lat, lng: entry.lng };
        if (address && entry.address && address.toLowerCase().indexOf(entry.address.toLowerCase()) >= 0) return { lat: entry.lat, lng: entry.lng };
      }
      if (!q) return null;
      var url = "https://nominatim.openstreetmap.org/search?format=json&limit=1&bounded=1&viewbox=-92.48,39.05,-92.18,38.85&q=" + encodeURIComponent(q + ", Columbia, MO");
      return fetch(url, { headers: { "Accept": "application/json" } }).then(function (r) { return r.json(); }).then(function (j) {
        return j && j[0] ? { lat: parseFloat(j[0].lat), lng: parseFloat(j[0].lon) } : null;
      }).catch(function () { return null; });
    });
  };
  Cloud.submit = function (d) {
    if (!Cloud.signedIn) return Promise.resolve("Sign in with iCloud (Profile tab) to post.");
    if ((d.title || "").trim().length < 3) return Promise.resolve("Give the event a title.");
    if (!d.venue && !d.address) return Promise.resolve("Where is it? Add a venue or an address.");
    if (!d.agreed) return Promise.resolve("Please agree to the community guidelines first.");
    var bad = [d.title, d.details, d.venue, d.submitterName, d.link].map(Cloud.offendingTerm).filter(Boolean)[0];
    if (bad) return Promise.resolve("That post can't go up: it contains \"" + bad + "\". Please reword it.");
    return Cloud.lookupVenue(d.venue).then(function (m) {
      if (m && m.lat != null) { if (!d.address && m.address) d.address = m.address; if (!d.link && m.website) d.link = m.website; return { lat: m.lat, lng: m.lng }; }
      return Cloud.geocode(d.venue, d.address);
    }).then(function (pt) {
      var fields = {
        title: d.title.trim(), category: d.category, categories: [d.category].concat((d.extra || []).filter(function (c) { return c !== d.category; })),
        start: d.start.getTime(), venue: d.venue || "", address: d.address || "", price: d.price || "", link: d.link || "", details: d.details || "",
        submitterName: d.submitterName || "", submitterID: Cloud.userRecordName, status: "pending", reports: 0
      };
      if (d.end) fields.end = d.end.getTime();
      if (pt) { fields.lat = pt.lat; fields.lng = pt.lng; }
      var rec = { recordType: "SubmittedEvent", fields: {} };
      Object.keys(fields).forEach(function (k) { rec.fields[k] = { value: fields[k] }; });
      return db.saveRecords([rec]).then(function (r) { if (r.hasErrors) throw r.errors[0]; Cloud.loadCommunity(); return null; });
    }).catch(function (e) { return "Couldn't post: " + err(e); });
  };
  Cloud.report = function (event, reason) {
    if (!Cloud.available) return Promise.resolve("Reporting needs iCloud on the web; email xenificity@icloud.com instead.");
    var name = event.recordName || (event.id.indexOf("community:") === 0 ? event.id.slice(10) : null);
    if (!name) return Promise.resolve("Only community posts can be reported here.");
    return db.saveRecords([{ recordType: "Report", fields: { eventRecordName: { value: name }, reason: { value: reason }, reporterID: { value: Cloud.userRecordName || "anonymous" } } }])
      .then(function (r) { if (r.hasErrors) throw r.errors[0]; return null; }).catch(function (e) { return err(e); });
  };
  Cloud.block = function (submitterID) {
    if (!submitterID) return;
    if (Cloud.community.blocked.indexOf(submitterID) < 0) { Cloud.community.blocked.push(submitterID); save("community.blocked", Cloud.community.blocked); }
    Cloud.community.approved = Cloud.community.approved.filter(function (e) { return e.submitterID !== submitterID; });
    Cloud.emit("community");
  };
  Cloud.unblockAll = function () { Cloud.community.blocked = []; save("community.blocked", []); Cloud.loadCommunity(); };
  Cloud.isModerator = function () { return Cloud.userRecordName && MODERATORS.indexOf(Cloud.userRecordName) >= 0; };
  Cloud.signOut = function () { if (container) return container.signOut ? container.signOut() : null; };

  window.Cloud = Cloud;
})();
