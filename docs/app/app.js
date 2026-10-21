/* CoMo Events web app: the same feed as the iPhone app, in a browser.
   No build step, no account, no analytics. Reads ../events.json (copied from feed/ by the
   workflow) and falls back to the raw GitHub copy. Favorites live in localStorage only. */
(function () {
  "use strict";

  var FEED = ["../events.json", "https://raw.githubusercontent.com/xenificity/comoevents/main/feed/events.json"];
  var CATS = {
    party:     { label: "Party",     emoji: "🎉", color: "var(--party)" },
    music:     { label: "Music",     emoji: "🎵", color: "var(--music)" },
    nightlife: { label: "Nightlife", emoji: "🌙", color: "var(--nightlife)" },
    food:      { label: "Food",      emoji: "🍽️", color: "var(--food)" },
    arts:      { label: "Arts",      emoji: "🎭", color: "var(--arts)" },
    sports:    { label: "Sports",    emoji: "🏟️", color: "var(--sports)" },
    family:    { label: "Family",    emoji: "👨‍👩‍👧", color: "var(--family)" },
    campus:    { label: "Campus",    emoji: "🎓", color: "var(--campus)" },
    community: { label: "Community", emoji: "👥", color: "var(--community)" }
  };
  var WINDOWS = [["now", "Now"], ["today", "Today"], ["weekend", "Weekend"], ["week", "7 days"], ["all", "All"]];
  var AUDIENCES = [["", "Everyone"], ["singles", "Singles"], ["couples", "Couples"], ["groups", "Groups"], ["family", "Family"]];
  var INSTALL = "../get/?c=webapp";

  var state = {
    events: [], generatedAt: null,
    window: "today", categories: new Set(), audience: "", search: "",
    favorites: new Set(JSON.parse(localStorage.getItem("favorites") || "[]")),
    selected: null, visible: []
  };

  var $ = function (id) { return document.getElementById(id); };
  var el = function (tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  var esc = function (s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); };

  // ---------- dates ----------
  function parseDate(s) { return s ? new Date(s) : null; }
  function effectiveEnd(e) { return e._end || new Date(e._start.getTime() + (e.allDay ? 86400e3 : 3 * 3600e3)); }
  function isLive(e, now) { return e._start <= now && effectiveEnd(e) >= now; }
  function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
  function startOfDay(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function weekendBounds(now) {
    var today = startOfDay(now), wd = today.getDay(); // 0 Sun ... 6 Sat
    var daysToSat = wd === 0 ? -1 : 6 - wd;
    var sat = new Date(today); sat.setDate(sat.getDate() + daysToSat);
    var sunEnd = new Date(sat); sunEnd.setDate(sunEnd.getDate() + 2);
    return [sat, sunEnd];
  }
  function inWindow(e, w, now) {
    var end = effectiveEnd(e);
    switch (w) {
      case "now": return end >= now && e._start <= new Date(now.getTime() + 3 * 3600e3);
      case "today": return (end >= now && sameDay(e._start, now)) || (e._start < now && end >= now);
      case "weekend": var b = weekendBounds(now); return (e._start >= b[0] && e._start < b[1]) || (e._start < b[0] && end >= b[0] && end >= now);
      case "week": return end >= now && e._start < new Date(now.getTime() + 7 * 86400e3);
      default: return end >= now;
    }
  }
  var fmtTime = new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit" });
  var fmtDay = new Intl.DateTimeFormat("en-US", { weekday: "short", month: "short", day: "numeric" });
  var fmtLong = new Intl.DateTimeFormat("en-US", { weekday: "long", month: "long", day: "numeric" });
  function timeText(e) { return e.allDay ? "All day" : e.timeTBD ? "Time TBD" : fmtTime.format(e._start); }
  function whenText(e) {
    if (e.allDay || e.timeTBD) return fmtDay.format(e._start) + (e.allDay ? " · All day" : " · Time TBD");
    var s = fmtDay.format(e._start) + " · " + fmtTime.format(e._start);
    if (e._end && sameDay(e._end, e._start)) s += " – " + fmtTime.format(e._end);
    return s;
  }
  function dayHeader(d) {
    var now = new Date(), t = startOfDay(now), tm = new Date(t); tm.setDate(tm.getDate() + 1);
    if (sameDay(d, t)) return "Today"; if (sameDay(d, tm)) return "Tomorrow"; return fmtLong.format(d);
  }
  function relative(d) {
    var m = Math.round((Date.now() - d.getTime()) / 60000);
    if (m < 2) return "just now"; if (m < 60) return m + " min ago"; var h = Math.round(m / 60);
    if (h < 24) return h + (h === 1 ? " hour ago" : " hours ago"); return Math.round(h / 24) + " days ago";
  }

  // ---------- filtering ----------
  function kinds(e) { return (e.categories && e.categories.length ? e.categories : [e.category]).filter(function (c) { return CATS[c]; }); }
  function matches(e, now) {
    if (!inWindow(e, state.window, now)) return false;
    if (state.audience && (e.audience || []).indexOf(state.audience) < 0) return false;
    if (state.categories.size && !kinds(e).some(function (k) { return state.categories.has(k); })) return false;
    if (state.search) { var q = state.search; if ((e.title || "").toLowerCase().indexOf(q) < 0 && (e.venue || "").toLowerCase().indexOf(q) < 0) return false; }
    return true;
  }
  function recompute() {
    var now = new Date();
    state.visible = state.events.filter(function (e) { return matches(e, now); });
    state.visible.sort(function (a, b) { return a._start - b._start; });
    renderCount(); renderList(); renderMarkers();
  }

  // ---------- header controls ----------
  function renderSegs() {
    var w = $("windows"); w.innerHTML = "";
    WINDOWS.forEach(function (p) {
      var b = el("button", p[0] === state.window ? "on" : "", p[1]);
      b.onclick = function () { state.window = p[0]; renderSegs(); recompute(); };
      w.appendChild(b);
    });
    var a = $("audiences"); a.innerHTML = "";
    AUDIENCES.forEach(function (p) {
      var b = el("button", p[0] === state.audience ? "on" : "", p[1]);
      b.onclick = function () { state.audience = p[0]; renderSegs(); recompute(); };
      a.appendChild(b);
    });
    var c = $("categories"); c.innerHTML = "";
    Object.keys(CATS).forEach(function (k) {
      var on = state.categories.has(k);
      var b = el("button", "chip" + (on ? " on" : "") + (state.categories.size && !on ? " dim" : ""), "<i>" + CATS[k].emoji + "</i>" + CATS[k].label);
      b.style.setProperty("--c", CATS[k].color);
      b.onclick = function () { if (on) state.categories.delete(k); else state.categories.add(k); renderSegs(); recompute(); };
      c.appendChild(b);
    });
  }
  function renderCount() {
    var n = state.visible.length;
    $("count").textContent = n + (n === 1 ? " event" : " events") + (state.generatedAt ? " · updated " + relative(state.generatedAt) : "");
  }

  // ---------- list ----------
  function thumb(e, big) {
    var k = kinds(e)[0] || "community";
    var t = el("div", "thumb");
    t.style.setProperty("--c", CATS[k].color);
    if (e.imageUrl) { var img = el("img"); img.loading = "lazy"; img.alt = ""; img.src = e.imageUrl; img.onerror = function () { img.remove(); t.textContent = CATS[k].emoji; }; t.appendChild(img); }
    else t.textContent = CATS[k].emoji;
    return t;
  }
  function card(e, now) {
    var k = kinds(e)[0] || "community";
    var c = el("div", "ev" + (state.selected === e.id ? " sel" : ""));
    c.style.setProperty("--c", CATS[k].color);
    c.appendChild(thumb(e));
    var mid = el("div");
    var meta = el("div", "meta");
    meta.innerHTML = '<span class="pill">' + esc(timeText(e)) + "</span>" + (isLive(e, now) ? '<span class="pill live">● LIVE</span>' : "") +
      (e.price && /free/i.test(e.price) ? '<span class="pill free">Free</span>' : "") + '<span class="pill cat">' + CATS[k].emoji + " " + CATS[k].label + "</span>";
    mid.appendChild(meta);
    mid.appendChild(el("h3", "", esc(e.title)));
    var where = e.venue || e.address; if (where) mid.appendChild(el("div", "where", "📍 " + esc(where)));
    c.appendChild(mid);
    var h = el("button", "heart" + (state.favorites.has(e.id) ? " on" : ""), state.favorites.has(e.id) ? "♥" : "♡");
    h.title = "Save"; h.onclick = function (ev) { ev.stopPropagation(); toggleFav(e.id); };
    c.appendChild(h);
    c.onclick = function () { select(e, true); };
    c.dataset.id = e.id;
    return c;
  }
  function renderList() {
    var list = $("list"); list.innerHTML = "";
    if (!state.visible.length) { list.appendChild(el("div", "empty", "Nothing in this window. Try another filter.")); return; }
    var now = new Date(), lastDay = null, frag = document.createDocumentFragment();
    state.visible.slice(0, 400).forEach(function (e) {
      var d = startOfDay(e._start).getTime();
      if (d !== lastDay) { lastDay = d; frag.appendChild(el("div", "day", dayHeader(e._start))); }
      frag.appendChild(card(e, now));
    });
    if (state.visible.length > 400) frag.appendChild(el("div", "empty", "Showing the first 400. Narrow the filters to see the rest."));
    list.appendChild(frag);
  }

  // ---------- map ----------
  var map, cluster, markers = {};
  function initMap() {
    map = L.map("map", { zoomControl: false, attributionControl: true }).setView([38.9480, -92.3300], 13);
    L.control.zoom({ position: "bottomright" }).addTo(map);
    // OpenStreetMap's own tiles (no key; light use is within their policy). app.css darkens them
    // with a CSS filter so the map matches the rest of the site.
    L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
    }).addTo(map);
    cluster = L.markerClusterGroup({
      maxClusterRadius: 44, showCoverageOnHover: false, spiderfyOnMaxZoom: true, disableClusteringAtZoom: 18,
      iconCreateFunction: function (c) {
        var counts = {}, n = 0;
        c.getAllChildMarkers().forEach(function (m) { var k = m.options.kind; counts[k] = (counts[k] || 0) + 1; n++; });
        var dom = Object.keys(counts).sort(function (a, b) { return counts[b] - counts[a]; })[0] || "community";
        return L.divIcon({ className: "", iconSize: [48, 48], iconAnchor: [24, 24],
          html: '<div class="pin big' + (n >= 3 ? " busy" : "") + '" style="--c:' + CATS[dom].color + '">' + CATS[dom].emoji + "<b>" + (n > 99 ? "99+" : n) + "</b></div>" });
      }
    });
    map.addLayer(cluster);
    if (navigator.geolocation) navigator.geolocation.getCurrentPosition(function (p) {
      L.circleMarker([p.coords.latitude, p.coords.longitude], { radius: 7, color: "#fff", weight: 2, fillColor: "#0a84ff", fillOpacity: 1 }).addTo(map).bindTooltip("You");
    }, function () {}, { maximumAge: 600000, timeout: 8000 });
  }
  function renderMarkers() {
    cluster.clearLayers(); markers = {};
    var byPlace = {};
    state.visible.forEach(function (e) {
      if (e.lat == null || e.lng == null) return;
      var key = e.lat.toFixed(4) + "," + e.lng.toFixed(4);
      (byPlace[key] = byPlace[key] || []).push(e);
    });
    var layers = [];
    Object.keys(byPlace).forEach(function (key) {
      var evs = byPlace[key], k = kinds(evs[0])[0] || "community";
      var m = L.marker([evs[0].lat, evs[0].lng], {
        kind: k,
        icon: L.divIcon({ className: "", iconSize: [38, 38], iconAnchor: [19, 19],
          html: '<div class="pin" data-key="' + key + '" style="--c:' + CATS[k].color + '">' + CATS[k].emoji + (evs.length > 1 ? "<b>" + evs.length + "</b>" : "") + "</div>" })
      });
      m.bindTooltip(esc(evs[0].venue || evs[0].address || evs[0].title) + (evs.length > 1 ? " · " + evs.length + " events" : ""), { direction: "top", offset: [0, -14] });
      m.on("click", function () { if (evs.length === 1) select(evs[0], false); else showPlace(evs); });
      evs.forEach(function (e) { markers[e.id] = m; });
      layers.push(m);
    });
    cluster.addLayers(layers);
  }
  function showPlace(evs) {
    // Several events at one spot: filter the list to them by scrolling to the first and highlighting.
    openPanel();
    var first = $("list").querySelector('[data-id="' + evs[0].id + '"]');
    if (first) first.scrollIntoView({ behavior: "smooth", block: "start" });
    toast(evs.length + " events at " + (evs[0].venue || evs[0].address || "this spot") + ". Scrolling the list there.");
  }

  // ---------- selection / detail ----------
  function select(e, fromList) {
    state.selected = e.id;
    if (e.lat != null && e.lng != null) {
      map.flyTo([e.lat, e.lng], Math.max(map.getZoom(), 16), { duration: 0.6 });
      var m = markers[e.id]; if (m && cluster.hasLayer(m)) cluster.zoomToShowLayer(m, function () {});
    }
    if (!fromList) { var c = $("list").querySelector('[data-id="' + e.id + '"]'); if (c) c.scrollIntoView({ behavior: "smooth", block: "center" }); }
    document.querySelectorAll(".ev.sel").forEach(function (x) { x.classList.remove("sel"); });
    var sel = $("list").querySelector('[data-id="' + e.id + '"]'); if (sel) sel.classList.add("sel");
    history.replaceState(null, "", "?e=" + encodeURIComponent(e.id));
    renderDetail(e);
  }
  function closeDetail() { $("detail").hidden = true; state.selected = null; history.replaceState(null, "", location.pathname); }
  function renderDetail(e) {
    var d = $("detail"), k = kinds(e)[0] || "community", now = new Date();
    d.innerHTML = "";
    d.style.setProperty("--c", CATS[k].color);
    var hero = el("div", "hero");
    if (e.imageUrl) { var img = el("img"); img.alt = ""; img.src = e.imageUrl; img.onerror = function () { img.remove(); }; hero.appendChild(img); }
    var close = el("button", "close", "‹"); close.title = "Close"; close.onclick = closeDetail; hero.appendChild(close);
    var fav = el("button", "fav" + (state.favorites.has(e.id) ? " on" : ""), state.favorites.has(e.id) ? "♥" : "♡"); fav.title = "Save";
    fav.onclick = function () { toggleFav(e.id); renderDetail(e); }; hero.appendChild(fav);
    d.appendChild(hero);
    var head = el("div", "head");
    var chips = kinds(e).map(function (c) { return '<span class="pill" style="background:' + CATS[c].color + ';color:#fff">' + CATS[c].emoji + " " + CATS[c].label + "</span>"; }).join(" ");
    head.innerHTML = '<div class="meta">' + chips + (isLive(e, now) ? ' <span class="pill live">● LIVE</span>' : "") + "</div><h2>" + esc(e.title) + "</h2>" +
      (e.organizer || e.sourceName ? '<div class="org">' + esc(e.organizer || e.sourceName) + "</div>" : "");
    d.appendChild(head);
    var sec = el("div", "sec");
    sec.innerHTML = '<div><span class="ic">🕒</span><span>' + esc(whenText(e)) + "</span></div>" +
      ((e.venue || e.address) ? '<div><span class="ic">📍</span><span>' + esc([e.venue, e.address].filter(Boolean).join(" · ")) + "</span></div>" : "") +
      (e.price ? '<div><span class="ic">🎟️</span><span>' + esc(e.price) + "</span></div>" : "") +
      (e.phone ? '<div><span class="ic">📞</span><a href="tel:' + esc(e.phone.replace(/[^\d+]/g, "")) + '">' + esc(e.phone) + "</a></div>" : "");
    d.appendChild(sec);
    if (e.audience && e.audience.length) {
      var g = el("div", "good", "Good for " + e.audience.map(function (a) { return "<span>" + esc(a.charAt(0).toUpperCase() + a.slice(1)) + "</span>"; }).join(""));
      d.appendChild(g);
    }
    if (e.description) d.appendChild(el("div", "desc", esc(e.description)));
    var act = el("div", "actions");
    var link = e.ticketUrl || e.url;
    if (link) act.appendChild(Object.assign(el("a", "primary", (e.ticketUrl ? "🎟️ Tickets" : "↗ More info")), { href: link, target: "_blank", rel: "noopener" }));
    if (e.lat != null) act.appendChild(Object.assign(el("a", "", "🚗 Directions"), { href: "https://maps.apple.com/?daddr=" + e.lat + "," + e.lng + "&q=" + encodeURIComponent(e.venue || e.title), target: "_blank", rel: "noopener" }));
    var cal = el("button", "", "📅 Add to calendar"); cal.onclick = function () { downloadICS(e); }; act.appendChild(cal);
    var share = el("button", "", "↑ Share"); share.onclick = function () { shareEvent(e); }; act.appendChild(share);
    d.appendChild(act);
    var open = el("div", "openapp");
    open.innerHTML = "On an iPhone? <a href=\"comoevents://event/" + encodeURIComponent(e.id) + "\">Open in the CoMo Events app</a> for reminders, friends and attendance, or <a href=\"" + INSTALL + "\">get the app</a>.";
    d.appendChild(open);
    d.hidden = false; d.scrollTop = 0;
  }

  // ---------- actions ----------
  function toggleFav(id) {
    if (state.favorites.has(id)) state.favorites.delete(id); else state.favorites.add(id);
    localStorage.setItem("favorites", JSON.stringify(Array.from(state.favorites)));
    renderList();
  }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function icsDate(d) { return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + "T" + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + "00Z"; }
  function icsText(s) { return String(s || "").replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/[,;]/g, function (c) { return "\\" + c; }); }
  function downloadICS(e) {
    var end = effectiveEnd(e);
    var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//CoMo Events//Web//EN", "BEGIN:VEVENT",
      "UID:" + e.id + "@comoevents", "DTSTAMP:" + icsDate(new Date()),
      e.allDay ? "DTSTART;VALUE=DATE:" + e._start.getFullYear() + pad(e._start.getMonth() + 1) + pad(e._start.getDate()) : "DTSTART:" + icsDate(e._start),
      e.allDay ? "" : "DTEND:" + icsDate(end),
      "SUMMARY:" + icsText(e.title), "LOCATION:" + icsText([e.venue, e.address].filter(Boolean).join(", ")),
      "DESCRIPTION:" + icsText((e.description ? e.description + "\n\n" : "") + (e.url || "")), e.url ? "URL:" + e.url : "",
      "END:VEVENT", "END:VCALENDAR"].filter(Boolean);
    var blob = new Blob([lines.join("\r\n")], { type: "text/calendar;charset=utf-8" });
    var a = el("a"); a.href = URL.createObjectURL(blob); a.download = (e.title || "event").replace(/[^\w\- ]+/g, "").slice(0, 60) + ".ics"; document.body.appendChild(a); a.click(); a.remove();
  }
  function shareEvent(e) {
    var url = location.origin + location.pathname + "?e=" + encodeURIComponent(e.id);
    var text = e.title + " · " + whenText(e) + (e.venue ? " · " + e.venue : "");
    if (navigator.share) navigator.share({ title: e.title, text: text, url: url }).catch(function () {});
    else navigator.clipboard.writeText(text + "\n" + url).then(function () { toast("Link copied"); });
  }
  var toastTimer;
  function toast(msg) { var t = $("toast"); t.textContent = msg; t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.hidden = true; }, 2600); }

  // ---------- phone bottom sheet ----------
  function openPanel() { $("panel").classList.remove("collapsed"); $("toggle").textContent = "Map"; }
  function togglePanel() { var p = $("panel"); p.classList.toggle("collapsed"); $("toggle").textContent = p.classList.contains("collapsed") ? "List" : "Map"; setTimeout(function () { map.invalidateSize(); }, 300); }

  // ---------- load ----------
  function load(i) {
    i = i || 0;
    if (i >= FEED.length) { $("count").textContent = "Could not load events. Try again in a minute."; return; }
    fetch(FEED[i] + (FEED[i].indexOf("http") === 0 ? "" : "?t=" + Math.floor(Date.now() / 600000)), { cache: "no-cache" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (feed) {
        state.generatedAt = parseDate(feed.generatedAt);
        state.events = (feed.events || []).map(function (e) { e._start = parseDate(e.start) || new Date(0); e._end = parseDate(e.end); return e; });
        var now = new Date();
        if (state.events.filter(function (e) { return inWindow(e, "today", now); }).length < 3) state.window = "week";
        renderSegs(); recompute();
        var want = new URLSearchParams(location.search).get("e");
        if (want) { var e = state.events.find(function (x) { return x.id === want; }); if (e) { state.window = "all"; renderSegs(); recompute(); select(e, false); } }
      })
      .catch(function () { load(i + 1); });
  }

  document.addEventListener("DOMContentLoaded", function () {
    initMap(); renderSegs();
    var t; $("search").addEventListener("input", function (ev) { clearTimeout(t); t = setTimeout(function () { state.search = ev.target.value.trim().toLowerCase(); recompute(); }, 120); });
    $("toggle").onclick = togglePanel;
    $("handle").onclick = togglePanel;
    document.addEventListener("keydown", function (ev) { if (ev.key === "Escape") closeDetail(); });
    if (matchMedia("(max-width:820px)").matches) $("panel").classList.add("collapsed"), $("toggle").textContent = "List";
    load();
    setInterval(function () { recompute(); }, 60000);          // LIVE badges and "Now" stay right
    setInterval(function () { load(); }, 30 * 60000);          // pick up the 2-hourly feed rebuilds
  });
})();
