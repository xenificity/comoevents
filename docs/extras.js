/* CoMo Events website, version 1.3 additions (mirrors the iPhone app):
 *   Places tab, "Who's in?" invites, problem reports (3 people must agree), Instagram Story cards, game day mode.
 * Uses the hooks app.js puts on window.CoMo. Talks to the worker (window.SOCIAL_API, social/src/index.js):
 *   POST /report, POST /invite, GET /invite/<id>. */
(function () {
  "use strict";
  var C = window.CoMo;
  if (!C) return;
  var el = C.el, ic = C.ic, esc = C.esc, state = C.state;
  var $ = function (id) { return document.getElementById(id); };

  function api() {
    try { var o = localStorage.getItem("como.api"); if (o) return o; } catch (e) {}
    return window.SOCIAL_API || "https://comoevents-social.comoevent.workers.dev";
  }
  /** A random id for this browser: counts as one person for reports and invites. Not linked to anything else. */
  function myId() {
    var id = C.store.load("como.anon", "");
    if (!id) {
      var a = new Uint8Array(12); (window.crypto || window.msCrypto).getRandomValues(a);
      id = "w-" + Array.prototype.map.call(a, function (x) { return ("0" + x.toString(16)).slice(-2); }).join("");
      C.store.save("como.anon", id);
    }
    return id;
  }
  function post(path, body) {
    return fetch(api() + path, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
      .then(function (r) { return r.json().then(function (j) { if (!r.ok) throw new Error(j.error || ("Error " + r.status)); return j; }); });
  }
  function catColor(e) {
    var v = getComputedStyle(document.documentElement).getPropertyValue("--" + C.kind(e)).trim();
    return v || "#3b6cf6";
  }

  // ---------------------------------------------------------------- a small sheet for forms and lists
  function sheet(title, build) {
    var old = document.querySelector(".xsheet"); if (old) old.remove();
    var s = el("section", "xsheet");
    var card = el("div", "xsheet-card glass");
    var head = el("header", "", "<h2>" + esc(title) + "</h2>");
    var x = el("button", "glass circle", ic("back")); x.type = "button"; x.title = "Close"; x.onclick = function () { s.remove(); };
    head.appendChild(x); card.appendChild(head);
    var body = el("div", "xsheet-body"); card.appendChild(body);
    s.appendChild(card);
    s.addEventListener("click", function (ev) { if (ev.target === s) s.remove(); });
    document.body.appendChild(s);
    build(body, function () { s.remove(); });
    return s;
  }

  // ---------------------------------------------------------------- Places
  var places = null, placesP = null, placeCat = "", placeTags = new Set(), placeQ = "";
  var PLACE_ICON = { fun: "game", outdoors: "tree", culture: "museum", coffee: "cup", nightlife: "glass", shopping: "bag" };
  var PLACE_COLOR = { fun: "var(--party)", outdoors: "var(--family)", culture: "var(--arts)", coffee: "var(--religious)", nightlife: "var(--nightlife)", shopping: "var(--sports)" };
  var PLACE_TAGS = [["free", "Free"], ["kids", "Kids"], ["indoor", "Indoors"], ["outdoor", "Outdoors"], ["dogs", "Dogs OK"], ["21+", "21+"]];
  function loadPlaces() {
    if (!placesP) placesP = fetch("places.json?t=" + Math.floor(Date.now() / 3600000)).then(function (r) { return r.json(); })
      .then(function (d) { places = d; return d; }).catch(function () { placesP = null; return null; });
    return placesP;
  }
  function km(a, b) {
    var R = 6371, toR = Math.PI / 180, dLa = (b[0] - a[0]) * toR, dLo = (b[1] - a[1]) * toR;
    var h = Math.sin(dLa / 2) * Math.sin(dLa / 2) + Math.cos(a[0] * toR) * Math.cos(b[0] * toR) * Math.sin(dLo / 2) * Math.sin(dLo / 2);
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  function norm(s) { return String(s || "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim(); }
  /** Upcoming events at this place: same pin (within 120 m) or the same name. */
  function eventsAt(p) {
    var now = new Date(), n = norm(p.name);
    return state.events.filter(function (e) {
      if (C.effectiveEnd(e) < now) return false;
      if (e.lat != null && km([e.lat, e.lng], [p.lat, p.lng]) < 0.035) return true;   // same building; downtown neighbours are 50 m apart
      var v = norm(e.venue); return v && n && (v === n || (v.length > 6 && n.indexOf(v) >= 0) || (n.length > 6 && v.indexOf(n) >= 0));
    }).sort(function (a, b) { return a._start - b._start; });
  }
  function renderPlaces() {
    var list = $("places-list");
    if (!places) { list.innerHTML = '<div class="empty">' + ic("explore") + "Loading places…</div>"; loadPlaces().then(function (d) { if (d) renderPlaces(); else list.innerHTML = '<div class="empty">Could not load places. Try again in a minute.</div>'; }); return; }
    var cats = $("place-cats"); cats.innerHTML = "";
    [[""].concat(["All", "explore"])].concat(Object.keys(places.categories).map(function (k) { return [k, places.categories[k].label, PLACE_ICON[k]]; }))
      .forEach(function (c) {
        var b = el("button", "chip glass" + (placeCat === c[0] ? " on" : ""), '<span class="dot">' + ic(c[2]) + "</span>" + c[1]);
        b.type = "button"; b.onclick = function () { placeCat = c[0]; renderPlaces(); };
        b.style.setProperty("--c", PLACE_COLOR[c[0]] || "var(--gold)");
        cats.appendChild(b);
      });
    var tags = $("place-tags"); tags.innerHTML = "";
    PLACE_TAGS.forEach(function (t) {
      var on = placeTags.has(t[0]);
      var b = el("button", "chip glass small" + (on ? " on" : ""), t[1]); b.type = "button";
      b.onclick = function () { if (on) placeTags.delete(t[0]); else placeTags.add(t[0]); renderPlaces(); };
      tags.appendChild(b);
    });
    var q = norm(placeQ);
    var rows = places.places.filter(function (p) {
      if (placeCat && p.category !== placeCat) return false;
      for (var t of placeTags) if ((p.tags || []).indexOf(t) < 0) return false;
      if (q) { var hay = norm(p.name + " " + (p.blurb || "") + " " + (places.categories[p.category] || {}).label + " " + (p.tags || []).join(" ")); return q.split(" ").every(function (w) { return hay.indexOf(w) >= 0; }); }
      return true;
    });
    list.innerHTML = "";
    if (!rows.length) { list.appendChild(el("div", "empty", ic("explore") + "Nothing here. Try another word or filter.")); return; }
    var frag = document.createDocumentFragment();
    rows.forEach(function (p) {
      var evs = eventsAt(p);
      var card = el("article", "glass card place");
      card.innerHTML = '<div class="place-head"><span class="pdot ' + esc(p.category) + '">' + ic(PLACE_ICON[p.category] || "pin") + "</span><div><h3>" + esc(p.name) +
        "</h3><small>" + esc((places.categories[p.category] || {}).label || "") + ((p.tags || []).length ? " · " + esc(p.tags.map(function (t) { var T = PLACE_TAGS.find(function (x) { return x[0] === t; }); return T ? T[1] : t; }).join(" · ")) : "") + "</small></div></div>" +
        (p.blurb ? "<p>" + esc(p.blurb) + "</p>" : "") + '<div class="addr">' + ic("pin") + esc(p.address || "") + "</div>";
      var btns = el("div", "place-btns");
      var d = el("a", "glass capsule label", ic("car") + "<span>Directions</span>"); d.href = "https://maps.apple.com/?daddr=" + p.lat + "," + p.lng + "&q=" + encodeURIComponent(p.name); d.target = "_blank"; d.rel = "noopener";
      d.onclick = function () { C.track("click/place-directions"); };
      btns.appendChild(d);
      if (p.website) { var w = el("a", "glass capsule label", ic("arrow") + "<span>Website</span>"); w.href = p.website; w.target = "_blank"; w.rel = "noopener"; btns.appendChild(w); }
      if (p.phone) { var ph = el("a", "glass capsule label", ic("phone") + "<span>Call</span>"); ph.href = "tel:" + String(p.phone).replace(/[^\d+]/g, ""); btns.appendChild(ph); }
      card.appendChild(btns);
      if (evs.length) {
        var box = el("div", "place-events", "<b>" + ic("sparkles") + evs.length + (evs.length === 1 ? " event coming up" : " events coming up") + "</b>");
        var strip = el("div", "strip"), now = new Date();
        evs.slice(0, 6).forEach(function (e) { var m = C.miniCard(e, now); m.onclick = function () { C.openDetail(e); }; strip.appendChild(m); });
        box.appendChild(strip); card.appendChild(box);
      }
      frag.appendChild(card);
    });
    list.appendChild(frag);
  }

  // ---------------------------------------------------------------- problem reports
  function report(e) {
    C.track("click/report-problem");
    sheet("Report a problem", function (body, close) {
      body.appendChild(el("p", "hint", "What is wrong with “" + esc(e.title) + "”? We change the listing once <b>3 people</b> report the same thing, so one mistaken report can't break it."));
      var form = el("form", "pform report-form");
      var hh = e._start.getHours(), mm = e._start.getMinutes();
      form.innerHTML =
        '<label class="opt"><input type="radio" name="kind" value="time" checked> Wrong time</label>' +
        '<label class="sub" data-for="time">Right start time<input name="time" type="time" value="' + ("0" + hh).slice(-2) + ":" + ("0" + mm).slice(-2) + '"></label>' +
        '<label class="opt"><input type="radio" name="kind" value="place"> Wrong place</label>' +
        '<label class="sub" data-for="place" hidden>Right place<input name="place" maxlength="120" placeholder="e.g. Rose Music Hall"></label>' +
        '<label class="opt"><input type="radio" name="kind" value="cancelled"> Cancelled or not happening</label>' +
        '<label class="opt"><input type="radio" name="kind" value="other"> Something else</label>' +
        '<label class="sub" data-for="other" hidden>What is wrong?<input name="other" maxlength="120"></label>' +
        '<p class="err" hidden></p><button class="ylink" type="submit">Send report</button>';
      form.addEventListener("change", function () {
        var k = form.kind.value;
        form.querySelectorAll(".sub").forEach(function (s) { s.hidden = s.dataset.for !== k; });
      });
      form.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var k = form.kind.value, value = k === "time" ? form.time.value : k === "place" ? form.place.value.trim() : k === "other" ? form.other.value.trim() : "";
        var err = form.querySelector(".err"); err.hidden = true;
        var btn = form.querySelector("button"); btn.disabled = true;
        post("/report", { event: e.id, kind: k, value: value, reporter: myId(), title: e.title })
          .then(function (r) {
            close();
            C.toast(r.count >= r.needed ? "Thanks. 3 people agree, so it changes at the next update." : "Thanks. It changes once " + r.needed + " people report the same thing (" + r.count + " so far).");
          })
          .catch(function (x) { err.textContent = x.message || "Couldn't send. Try again."; err.hidden = false; btn.disabled = false; });
      });
      body.appendChild(form);
    });
  }

  // ---------------------------------------------------------------- "Who's in?" invites
  function invites() { return C.store.load("como.invites", {}); }
  function invite(e) {
    C.track("click/whos-in");
    var name = (state.profile && state.profile.name) || C.store.load("como.inviteName", "");
    var go = function (host) {
      C.store.save("como.inviteName", host);
      var have = invites()[e.id];
      var p = have ? Promise.resolve({ id: have, url: location.origin + "/in/?i=" + have }) :
        post("/invite", { event: e.id, title: e.title, start: e.start, venue: e.venue || "", host: host, guest: myId() });
      p.then(function (r) {
        var all = invites(); all[e.id] = r.id; C.store.save("como.invites", all);
        var url = r.url || (location.origin + "/in/?i=" + r.id);
        var text = "Who's in? " + e.title + ", " + C.whenText(e) + (e.venue ? " at " + e.venue : "") + ". Tap to say you're in:";
        if (navigator.share) navigator.share({ title: "Who's in?", text: text, url: url }).catch(function () {});
        else if (navigator.clipboard) navigator.clipboard.writeText(text + " " + url).then(function () { C.toast("Invite link copied. Paste it in your group chat."); });
        var slot = document.querySelector("#detail .invite-slot"); if (slot) renderInviteCard(slot, e);
      }).catch(function (x) { C.toast(x.message || "Couldn't make the invite. Try again."); });
    };
    if (name) return go(name);
    sheet("Who's in?", function (body, close) {
      body.appendChild(el("p", "hint", "Send friends a link. They tap “I'm in” in any browser, no app needed, and you see who's coming here."));
      var f = el("form", "pform", '<label>Your first name<input name="n" maxlength="40" required placeholder="So friends know who invited them"></label><button class="ylink" type="submit">Make the invite link</button>');
      f.addEventListener("submit", function (ev) { ev.preventDefault(); var n = f.n.value.trim(); if (!n) return; close(); go(n); });
      body.appendChild(f);
    });
  }
  function renderInviteCard(slot, e) {
    var id = invites()[e.id];
    slot.innerHTML = "";
    if (!id) return;
    fetch(api() + "/invite/" + id).then(function (r) { return r.ok ? r.json() : null; }).then(function (inv) {
      if (!inv) return;
      var ins = inv.guests.filter(function (g) { return g.status === "in"; }).map(function (g) { return g.name; });
      var maybe = inv.guests.filter(function (g) { return g.status === "maybe"; }).length;
      var card = el("div", "glass card whosin", ic("people") + "<div><b>Who's in: " + (ins.length ? esc(ins.join(", ")) : "nobody yet") + "</b>" +
        (maybe ? "<small> · " + maybe + " maybe</small>" : "") + "<small>Your invite link: " + esc(location.host + "/in/?i=" + id) + "</small></div>");
      var b = el("button", "glass capsule label", "<span>Invite more</span>"); b.type = "button"; b.onclick = function () { invite(e); };
      card.appendChild(b); slot.appendChild(card);
    }).catch(function () {});
  }

  // ---------------------------------------------------------------- Instagram Story card (1080 x 1920)
  function wrap(ctx, text, maxW) {
    var words = String(text).split(/\s+/), lines = [], line = "";
    words.forEach(function (w) { var t = line ? line + " " + w : w; if (ctx.measureText(t).width > maxW && line) { lines.push(line); line = w; } else line = t; });
    if (line) lines.push(line);
    return lines;
  }
  function storyShare(e) {
    C.track("click/story-share");
    var W = 1080, H = 1920, cv = document.createElement("canvas"); cv.width = W; cv.height = H;
    var x = cv.getContext("2d"), col = catColor(e);
    var g = x.createLinearGradient(0, 0, W, H); g.addColorStop(0, col); g.addColorStop(0.55, "#1d1b33"); g.addColorStop(1, "#0f0e1c");
    x.fillStyle = g; x.fillRect(0, 0, W, H);
    // header
    x.fillStyle = "#ffd60a"; x.font = "800 44px -apple-system, system-ui, sans-serif"; x.fillText("CoMo Events", 90, 170);
    x.fillStyle = "rgba(255,255,255,.75)"; x.font = "600 34px -apple-system, system-ui, sans-serif"; x.fillText("Columbia, MO", 90, 222);
    // when pill
    var when = C.whenText(e);
    x.font = "800 46px -apple-system, system-ui, sans-serif";
    var pw = Math.min(W - 180, x.measureText(when).width + 64);
    x.fillStyle = "#ffd60a"; roundRect(x, 90, 760, pw, 92, 46); x.fill();
    x.fillStyle = "#14121f"; x.fillText(when, 122, 822, W - 240);
    // title
    x.fillStyle = "#fff"; x.font = "900 96px -apple-system, system-ui, sans-serif";
    var lines = wrap(x, e.title, W - 180).slice(0, 4), y = 990;
    lines.forEach(function (l) { x.fillText(l, 90, y); y += 112; });
    if (e.venue) { x.fillStyle = "rgba(255,255,255,.9)"; x.font = "700 48px -apple-system, system-ui, sans-serif"; wrap(x, "📍 " + e.venue, W - 180).slice(0, 2).forEach(function (l) { y += 20; x.fillText(l, 90, y); y += 40; }); }
    // footer
    x.fillStyle = "rgba(255,255,255,.12)"; roundRect(x, 90, H - 330, W - 180, 190, 36); x.fill();
    x.fillStyle = "#fff"; x.font = "800 50px -apple-system, system-ui, sans-serif"; x.fillText("Find it on CoMo Events", 140, H - 240);
    x.fillStyle = "#ffd60a"; x.font = "700 44px -apple-system, system-ui, sans-serif"; x.fillText("comoevent.com", 140, H - 175);
    var finish = function () {
      cv.toBlob(function (blob) {
        if (!blob) { C.toast("Couldn't make the picture."); return; }
        var name = "como-" + (e.title || "event").replace(/[^\w]+/g, "-").slice(0, 40).toLowerCase() + ".png";
        var file = new File([blob], name, { type: "image/png" });
        if (navigator.canShare && navigator.canShare({ files: [file] })) {
          navigator.share({ files: [file], title: e.title, text: "comoevent.com" }).catch(function () {});
        } else {
          var a = el("a"); a.href = URL.createObjectURL(blob); a.download = name; document.body.appendChild(a); a.click(); a.remove();
          C.toast("Story picture saved. Open Instagram and add it to your Story.");
        }
      }, "image/png");
    };
    // the event photo, when its server allows it (otherwise the card is still complete)
    if (e.imageUrl) {
      var img = new Image(); img.crossOrigin = "anonymous";
      img.onload = function () {
        try {
          x.save(); roundRect(x, 90, 290, W - 180, 420, 40); x.clip();
          var s = Math.max((W - 180) / img.width, 420 / img.height);
          x.drawImage(img, 90 + ((W - 180) - img.width * s) / 2, 290 + (420 - img.height * s) / 2, img.width * s, img.height * s);
          x.restore(); cv.getContext("2d").getImageData(0, 0, 1, 1);   // throws if the image tainted the canvas
        } catch (err) { x.restore(); }
        finish();
      };
      img.onerror = finish;
      img.src = e.imageUrl;
      setTimeout(function () { if (!img.complete) { img.onload = img.onerror = null; finish(); } }, 4000);
    } else finish();
  }
  function roundRect(x, l, t, w, h, r) { x.beginPath(); x.moveTo(l + r, t); x.arcTo(l + w, t, l + w, t + h, r); x.arcTo(l + w, t + h, l, t + h, r); x.arcTo(l, t + h, l, t, r); x.arcTo(l, t, l + w, t, r); x.closePath(); }

  // ---------------------------------------------------------------- game day mode
  var HOME_VENUE = /faurot|memorial stadium|mizzou arena|hearnes|champions dr|walton stadium|taylor stadium|mizzou softball|simmons field|university of missouri/i;
  var SPORT = /football|basketball|volleyball|gymnastics|wrestling|soccer|softball|baseball/i;
  function today() {
    var p = new URLSearchParams(location.search).get("gameday");   // ?gameday=2026-11-21 to preview a game day
    if (p && /^\d{4}-\d{2}-\d{2}$/.test(p)) { var d = new Date(p + "T12:00:00"); return d; }
    return new Date();
  }
  function homeGame(day) {
    var d0 = C.startOfDay(day).getTime(), d1 = d0 + 864e5;
    var games = state.events.filter(function (e) {
      var t = e._start.getTime();
      if (t < d0 || t >= d1) return false;
      if (C.kinds(e).indexOf("sports") < 0 && !SPORT.test(e.title)) return false;
      if (!/mizzou|missouri|tigers/i.test(e.title) || !SPORT.test(e.title)) return false;
      if (/\b(at|@)\s+[A-Z]/.test(e.title) && !/\bvs\.?\b/i.test(e.title)) return false;   // away game
      return HOME_VENUE.test((e.venue || "") + " " + (e.address || "")) || /\b(mizzou|missouri)\b[^v]*\bvs\.?/i.test(e.title);
    });
    var rank = function (e) { return /football/i.test(e.title) ? 3 : /basketball/i.test(e.title) ? 2 : 1; };
    return games.sort(function (a, b) { return rank(b) - rank(a) || (b.score || 0) - (a.score || 0); })[0] || null;
  }
  var PRE = /tailgat|watch party|watch-party|pregame|pre-game|game ?day|tiger walk|homecoming|fan fest|kickoff party/i;
  function gameDayPlan(game, day) {
    var d0 = C.startOfDay(day).getTime(), d1 = d0 + 864e5 + 3 * 3600e3;   // after-parties run past midnight
    var kickoff = game._start.getTime(), after = kickoff + 3 * 3600e3;
    var sameDay = state.events.filter(function (e) { var t = e._start.getTime(); return e.id !== game.id && t >= d0 && t < d1; });
    var dayOnly = sameDay.filter(function (e) { return e._start.getTime() < d0 + 864e5; });   // only "after" may run past midnight
    var before = dayOnly.filter(function (e) { return PRE.test(e.title + " " + (e.description || "")) && e._start.getTime() <= kickoff + 3600e3; });
    var afterL = sameDay.filter(function (e) { var k = C.kinds(e); return e._start.getTime() >= after - 1800e3 && (k.indexOf("nightlife") >= 0 || k.indexOf("music") >= 0 || k.indexOf("party") >= 0); })
      .sort(function (a, b) { return (b.score || 0) - (a.score || 0); });
    // the same game listed again by another site ("Missouri Tigers vs. Kentucky Wildcats at Faurot Field") is not "more"
    var opp = ((game.title.split(/\bvs\.?\s*/i)[1] || "").match(/[A-Za-z][A-Za-z'.-]+/) || [""])[0].toLowerCase();
    var sameGame = function (e) { return opp && e.title.toLowerCase().indexOf(opp) >= 0; };
    var also = dayOnly.filter(function (e) { return before.indexOf(e) < 0 && afterL.indexOf(e) < 0 && !sameGame(e) && C.kinds(e).indexOf("sports") >= 0 && /mizzou|missouri|tigers/i.test(e.title); });
    before = before.filter(function (e) { return !sameGame(e); });
    return { before: before.slice(0, 8), after: afterL.slice(0, 8), also: also.slice(0, 4) };
  }
  function gameDayBanner(slot) {
    if (!slot) return;
    slot.innerHTML = "";
    if (!state.events.length) return;
    var day = today(), game = homeGame(day);
    if (!game) return;
    var b = el("button", "gameday glass", '<span class="gd-ic">' + ic("trophy") + '</span><span class="gd-t"><b>Game day</b><span>' + esc(game.title) + " · " + esc(C.timeText(game)) + '</span></span><span class="gd-go">Plan ›</span>');
    b.type = "button";
    b.onclick = function () { C.track("click/gameday"); openGameDay(game, day); };
    slot.appendChild(b);
  }
  function openGameDay(game, day) {
    var plan = gameDayPlan(game, day), now = new Date();
    sheet("Game day", function (body) {
      var g = el("div", "gd-section"); g.appendChild(el("h3", "", ic("trophy") + "The game"));
      var gc = C.bigCard(game, now); g.appendChild(gc); body.appendChild(g);
      var add = function (title, icon, list, empty) {
        var s = el("div", "gd-section"); s.appendChild(el("h3", "", ic(icon) + title));
        if (!list.length) s.appendChild(el("p", "hint", empty));
        var strip = el("div", "strip");
        list.forEach(function (e) { var m = C.miniCard(e, now); m.onclick = function () { C.openDetail(e); }; strip.appendChild(m); });
        if (list.length) s.appendChild(strip);
        body.appendChild(s);
      };
      add("Before: tailgates and watch parties", "party", plan.before, "No tailgates or watch parties listed yet. Bars downtown fill up early on game day.");
      add("After the game", "nightlife", plan.after, "Nothing listed for after the game yet.");
      if (plan.also.length) add("More Mizzou today", "sports", plan.also, "");
      body.appendChild(el("p", "hint", "Parking near Faurot Field and Mizzou Arena fills up fast: the MKT trail and the free campus shuttles from downtown are the easy way in."));
    });
  }

  // ---------------------------------------------------------------- wiring
  document.addEventListener("DOMContentLoaded", function () {
    var t;
    var ps = $("place-search"); if (ps) ps.addEventListener("input", function (ev) { clearTimeout(t); t = setTimeout(function () { placeQ = ev.target.value; renderPlaces(); }, 120); });
    var fb = $("friends-btn"); if (fb) fb.onclick = function () { C.showTab("friends"); };
    var bb = $("friends-back"); if (bb) bb.onclick = function () { C.showTab("saved"); };
    loadPlaces();
  });

  window.CoMoExtras = { renderPlaces: renderPlaces, report: report, invite: invite, renderInviteCard: renderInviteCard,
    storyShare: storyShare, gameDayBanner: gameDayBanner, homeGame: homeGame, gameDayPlan: gameDayPlan };
})();
