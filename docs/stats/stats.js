/* CoMo Events public stats dashboard. Hand-built SVG charts, no chart library.
   Data: data.json (feed + GoatCounter, rebuilt hourly by GitHub Actions) and live CloudKit counts. */
(function () {
  "use strict";
  var CK = "https://api.apple-cloudkit.com/database/1/iCloud.com.xenificity.comoevents/production/public/records/query?ckAPIToken=" + (window.CK_TOKEN || "");
  var SVGNS = "http://www.w3.org/2000/svg";
  var state = { range: "30", grain: "day", data: null, ck: null };
  var CAT = { party: "Party", music: "Music", nightlife: "Nightlife", food: "Food", arts: "Arts", sports: "Sports", family: "Family", campus: "Campus", community: "Community" };

  // ---------- small helpers
  function $(id) { return document.getElementById(id); }
  function el(tag, cls, text) { var n = document.createElement(tag); if (cls) n.className = cls; if (text != null) n.textContent = text; return n; }
  function sv(tag, attrs) { var n = document.createElementNS(SVGNS, tag); for (var k in attrs || {}) n.setAttribute(k, attrs[k]); return n; }
  function fmt(n) { return (n == null || isNaN(n)) ? "–" : Math.round(n).toLocaleString("en-US"); }
  function css(name) { return getComputedStyle(document.body).getPropertyValue(name).trim(); }
  function ymd(d) { return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0"); }
  function parseDay(s) { var p = s.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function addDays(d, n) { var x = new Date(d); x.setDate(x.getDate() + n); return x; }
  var MON = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  function shortDay(d) { return MON[d.getMonth()] + " " + d.getDate(); }

  // ---------- time range and buckets
  function rangeStart() {
    var today = new Date(); today.setHours(0, 0, 0, 0);
    if (state.range !== "all") return addDays(today, -(+state.range - 1));
    var c = [], d = state.data, ck = state.ck;
    if (d && d.totals && d.totals.firstDay) c.push(parseDay(d.totals.firstDay));
    if (d && d.analytics && d.analytics.since) c.push(parseDay(d.analytics.since));
    if (ck && ck.firstInstall) c.push(ck.firstInstall);
    return c.length ? new Date(Math.min.apply(null, c)) : addDays(today, -29);
  }
  function periods() {
    var start = rangeStart(), end = new Date(), out = [], cur = new Date(start);
    end.setHours(0, 0, 0, 0);
    if (state.grain === "week") { var wd = (cur.getDay() + 6) % 7; cur = addDays(cur, -wd); }
    if (state.grain === "month") cur = new Date(cur.getFullYear(), cur.getMonth(), 1);
    while (cur <= end) {
      var next = state.grain === "day" ? addDays(cur, 1) : state.grain === "week" ? addDays(cur, 7) : new Date(cur.getFullYear(), cur.getMonth() + 1, 1);
      var label = state.grain === "month" ? MON[cur.getMonth()] + " " + cur.getFullYear() : state.grain === "week" ? "Week of " + shortDay(cur) : shortDay(cur);
      out.push({ from: new Date(Math.max(cur, start)), to: next, label: label, tick: state.grain === "month" ? MON[cur.getMonth()] : shortDay(cur) });
      cur = next;
    }
    return out;
  }
  // sum a {day: n} map into periods; mode "last" keeps the last value (for running totals)
  function series(map, ps, mode) {
    return ps.map(function (p) {
      var v = 0, seen = false;
      for (var d = new Date(p.from); d < p.to; d = addDays(d, 1)) {
        var k = ymd(d);
        if (map[k] != null) { v = mode === "last" ? map[k] : v + map[k]; seen = true; }
      }
      return mode === "last" && !seen ? null : v;
    });
  }
  // analytics days before counting began are unknown, not zero
  function since(vals, ps, day) { if (!day) return vals; var d0 = parseDay(day); return vals.map(function (v, i) { return ps[i].to <= d0 ? null : v; }); }
  function sumRange(map) { var s = rangeStart(), t = 0; for (var k in map || {}) if (parseDay(k) >= s) t += map[k]; return t; }
  function windowKey() { return state.range; }

  // ---------- card scaffolding (title, subtitle, legend, table toggle)
  function card(id, title, sub, table) {
    var c = $(id); c.innerHTML = "";
    var head = el("div", "card-head"), t = el("div");
    t.appendChild(el("h3", null, title)); if (sub) t.appendChild(el("p", "sub", sub));
    head.appendChild(t); c.appendChild(head);
    var body = el("div"); c.appendChild(body);
    if (table) {
      var b = el("button", "tbl-btn", "Table"); b.type = "button"; b.setAttribute("aria-expanded", "false");
      var tv = el("div", "tview table-wrap"); tv.hidden = true; tv.appendChild(buildTable(table.cols, table.rows));
      b.onclick = function () { tv.hidden = !tv.hidden; b.textContent = tv.hidden ? "Table" : "Chart"; b.setAttribute("aria-expanded", String(!tv.hidden)); body.hidden = !tv.hidden; };
      head.appendChild(b); c.appendChild(tv);
    }
    return body;
  }
  function buildTable(cols, rows) {
    var t = el("table", "data"), th = el("thead"), tr = el("tr");
    cols.forEach(function (c, i) { var h = el("th", i ? "num" : null, c); tr.appendChild(h); });
    th.appendChild(tr); t.appendChild(th);
    var tb = el("tbody");
    rows.forEach(function (r) { var row = el("tr"); r.forEach(function (v, i) { row.appendChild(el("td", i ? "num" : null, i ? fmt(v) : v)); }); tb.appendChild(row); });
    t.appendChild(tb); return t;
  }
  function empty(body, title, text) { var e = el("div", "empty"), d = el("div"); d.appendChild(el("b", null, title)); d.appendChild(document.createTextNode(text)); e.appendChild(d); body.appendChild(e); }
  function legend(body, items, box) {
    var l = el("div", "legend");
    items.forEach(function (s) { var sp = el("span"), i = el("i", box ? "box" : null); i.style.background = s.color; sp.appendChild(i); sp.appendChild(document.createTextNode(s.name)); l.appendChild(sp); });
    body.appendChild(l);
  }

  // ---------- tooltip
  var tip = $("tip");
  function showTip(evt, title, rows) {
    tip.innerHTML = ""; tip.appendChild(el("div", "t", title));
    rows.forEach(function (r) {
      var row = el("div", "r"), left = el("span");
      if (r.color) { var i = el("i"); i.style.background = r.color; left.appendChild(i); }
      left.appendChild(document.createTextNode(r.name));
      row.appendChild(el("b", null, fmt(r.value))); row.appendChild(left); tip.appendChild(row);
    });
    tip.hidden = false;
    var x = evt.clientX + 14, y = evt.clientY + 14, w = tip.offsetWidth, h = tip.offsetHeight;
    if (x + w > innerWidth - 8) x = evt.clientX - w - 14;
    if (y + h > innerHeight - 8) y = evt.clientY - h - 14;
    tip.style.left = x + "px"; tip.style.top = y + "px";
  }
  function hideTip() { tip.hidden = true; }

  // ---------- chart geometry shared by line and bar charts
  function niceMax(v) { if (v <= 4) return 4; var p = Math.pow(10, Math.floor(Math.log10(v))), m = v / p; return (m <= 1 ? 1 : m <= 1.2 ? 1.2 : m <= 1.6 ? 1.6 : m <= 2 ? 2 : m <= 2.4 ? 2.4 : m <= 3 ? 3 : m <= 4 ? 4 : m <= 5 ? 5 : m <= 6 ? 6 : m <= 8 ? 8 : 10) * p; }
  function frame(body, ps, max) {
    var W = 640, H = 240, L = 40, R = 10, T = 10, B = 26;
    var wrap = el("div", "chart"), s = sv("svg", { viewBox: "0 0 " + W + " " + H, role: "img" });
    var ymax = niceMax(max || 1), g = sv("g", { "class": "axis" });
    for (var i = 0; i <= 4; i++) {
      var y = T + (H - T - B) * (1 - i / 4), v = ymax * i / 4;
      s.appendChild(sv("line", { x1: L, x2: W - R, y1: y, y2: y, "class": "gridline" }));
      var t = sv("text", { x: L - 6, y: y + 4, "text-anchor": "end" }); t.textContent = v >= 1000 ? (v / 1000).toFixed(v % 1000 ? 1 : 0) + "k" : String(Math.round(v * 10) / 10); g.appendChild(t);
    }
    var n = ps.length, step = (W - L - R) / Math.max(n, 1), every = Math.max(1, Math.ceil(n / 7));
    ps.forEach(function (p, i) {
      if (i % every) return;
      var t = sv("text", { x: L + step * (i + .5), y: H - 8, "text-anchor": "middle" }); t.textContent = p.tick; g.appendChild(t);
    });
    s.appendChild(g); wrap.appendChild(s); body.appendChild(wrap);
    return { svg: s, W: W, H: H, L: L, R: R, T: T, B: B, step: step, ymax: ymax, y: function (v) { return T + (H - T - B) * (1 - v / ymax); }, x: function (i) { return L + step * (i + .5); } };
  }

  function lineChart(body, ps, list, unit) {
    var max = 0; list.forEach(function (s) { s.values.forEach(function (v) { if (v != null && v > max) max = v; }); });
    if (list.length > 1) legend(body, list, false);
    var f = frame(body, ps, max), s = f.svg;
    list.forEach(function (sr) {
      var d = "", started = false;
      sr.values.forEach(function (v, i) { if (v == null) return; d += (started ? "L" : "M") + f.x(i).toFixed(1) + " " + f.y(v).toFixed(1); started = true; });
      if (d) s.appendChild(sv("path", { d: d, fill: "none", stroke: sr.color, "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round" }));
      if (ps.length <= 31) sr.values.forEach(function (v, i) { if (v != null) s.appendChild(sv("circle", { cx: f.x(i), cy: f.y(v), r: 3.5, fill: sr.color, stroke: css("--surface-1"), "stroke-width": 2 })); });
    });
    var hair = sv("line", { "class": "hair", y1: f.T, y2: f.H - f.B, visibility: "hidden" }); s.appendChild(hair);
    var hit = sv("rect", { x: f.L, y: f.T, width: f.W - f.L - f.R, height: f.H - f.T - f.B, fill: "transparent", tabindex: 0, "aria-label": "Chart, use arrow keys to read values" });
    var cur = -1;
    function at(i, evt) {
      cur = Math.max(0, Math.min(ps.length - 1, i)); var x = f.x(cur);
      hair.setAttribute("x1", x); hair.setAttribute("x2", x); hair.setAttribute("visibility", "visible");
      showTip(evt, ps[cur].label, list.map(function (sr) { return { name: sr.name + (unit ? " " + unit : ""), value: sr.values[cur], color: sr.color }; }));
    }
    hit.addEventListener("pointermove", function (e) { var r = s.getBoundingClientRect(), vx = (e.clientX - r.left) * f.W / r.width; at(Math.floor((vx - f.L) / f.step), e); });
    hit.addEventListener("pointerleave", function () { hair.setAttribute("visibility", "hidden"); hideTip(); });
    hit.addEventListener("keydown", function (e) {
      if (e.key !== "ArrowRight" && e.key !== "ArrowLeft") return; e.preventDefault();
      var r = hit.getBoundingClientRect(), i = cur < 0 ? ps.length - 1 : cur + (e.key === "ArrowRight" ? 1 : -1);
      at(i, { clientX: r.left + (f.x(Math.max(0, Math.min(ps.length - 1, i))) - f.L) * r.width / (f.W - f.L - f.R), clientY: r.top + 20 });
    });
    hit.addEventListener("blur", function () { hair.setAttribute("visibility", "hidden"); hideTip(); });
    s.appendChild(hit);
  }

  function barChart(body, ps, list) {
    var totals = ps.map(function (_, i) { return list.reduce(function (a, s) { return a + (s.values[i] || 0); }, 0); });
    if (list.length > 1) legend(body, list, true);
    var f = frame(body, ps, Math.max.apply(null, totals.concat([0]))), s = f.svg, surface = css("--surface-1");
    var bw = Math.max(2, Math.min(28, f.step * .7));
    ps.forEach(function (p, i) {
      var base = f.y(0), x = f.x(i) - bw / 2, top = list.length - 1;
      while (top >= 0 && !list[top].values[i]) top--;
      var g = sv("g", { tabindex: 0 });
      list.forEach(function (sr, k) {
        var v = sr.values[i] || 0; if (!v) return;
        var h = f.y(0) - f.y(v);
        var y0 = base - h, r = k === top ? Math.min(4, h, bw / 2) : 0;
        var d = "M" + x + " " + base + "V" + (y0 + r) + (r ? "Q" + x + " " + y0 + " " + (x + r) + " " + y0 : "") + "H" + (x + bw - r) + (r ? "Q" + (x + bw) + " " + y0 + " " + (x + bw) + " " + (y0 + r) : "") + "V" + base + "Z";
        g.appendChild(sv("path", { d: d, fill: sr.color, stroke: surface, "stroke-width": 1 }));
        base = y0;
      });
      var hit = sv("rect", { x: f.x(i) - f.step / 2, y: f.T, width: f.step, height: f.H - f.T - f.B, fill: "transparent" });
      g.appendChild(hit);
      function show(e) { g.style.opacity = .85; showTip(e, p.label, list.map(function (sr) { return { name: sr.name, value: sr.values[i] || 0, color: sr.color }; }).concat(list.length > 1 ? [{ name: "Total", value: totals[i] }] : [])); }
      g.addEventListener("pointermove", show);
      g.addEventListener("pointerleave", function () { g.style.opacity = 1; hideTip(); });
      g.addEventListener("focus", function () { var r = hit.getBoundingClientRect(); show({ clientX: r.left + r.width / 2, clientY: r.top + 30 }); });
      g.addEventListener("blur", function () { g.style.opacity = 1; hideTip(); });
      s.appendChild(g);
    });
  }

  function barsList(body, rows, max) {
    var ul = el("ul", "bars"), m = max || Math.max.apply(null, rows.map(function (r) { return r.value; }).concat([1]));
    rows.forEach(function (r) {
      var li = el("li"), lab = el("span", "lab", r.label);
      if (r.sub) lab.appendChild(el("small", null, r.sub));
      li.title = r.label + (r.sub ? " · " + r.sub : "") + ": " + fmt(r.value);
      li.appendChild(lab); li.appendChild(el("span", "val", fmt(r.value)));
      var tr = el("div", "track"), fl = el("div", "fill"); fl.style.width = Math.max(1.5, 100 * r.value / m) + "%"; tr.appendChild(fl); li.appendChild(tr);
      ul.appendChild(li);
    });
    body.appendChild(ul);
  }

  // ---------- CloudKit (live)
  function query(recordType, filterBy, desiredKeys) {
    var out = [];
    function page(marker) {
      var body = { query: { recordType: recordType, filterBy: filterBy }, resultsLimit: 400, desiredKeys: desiredKeys };
      if (marker) body.continuationMarker = marker;
      return fetch(CK, { method: "POST", body: JSON.stringify(body) }).then(function (r) { return r.json(); }).then(function (j) {
        if (j.serverErrorCode) throw new Error(j.serverErrorCode);
        out = out.concat(j.records || []);
        if (j.continuationMarker && out.length < 50000) return page(j.continuationMarker);
        return out;
      });
    }
    return page();
  }
  function fv(r, k) { return r.fields && r.fields[k] ? r.fields[k].value : null; }
  function loadCloud() {
    if (!window.CK_TOKEN) return Promise.resolve(null);
    var gt0 = function (f) { return [{ fieldName: f, comparator: "GREATER_THAN", fieldValue: { value: 0 } }]; };
    return Promise.all([
      query("Install", gt0("installedAt"), ["platform", "installedAt", "lastSeen"]).catch(function () { return null; }),
      query("SubmittedEvent", gt0("start"), ["status"]).catch(function () { return null; }),
      query("Approval", [{ fieldName: "approved", comparator: "EQUALS", fieldValue: { value: 1 } }], ["eventRecordName"]).catch(function () { return null; }),
      query("Attendance", gt0("eventStart"), ["status"]).catch(function () { return null; })
    ]).then(function (r) {
      var inst = r[0] || [], now = Date.now(), byDay = { ios: {}, web: {} }, first = null, active = 0, ios = 0, web = 0;
      inst.forEach(function (rec) {
        var p = fv(rec, "platform") === "web" ? "web" : "ios", t = fv(rec, "installedAt"), ls = fv(rec, "lastSeen") || t;
        if (p === "ios") ios++; else web++;
        if (ls && now - ls < 30 * 864e5) active++;
        if (t) { var d = new Date(t), k = ymd(d); byDay[p][k] = (byDay[p][k] || 0) + 1; d.setHours(0, 0, 0, 0); if (!first || d < first) first = d; }
      });
      var att = { going: 0, here: 0, went: 0 };
      (r[3] || []).forEach(function (a) { var s = fv(a, "status"); if (att[s] != null) att[s]++; });
      return {
        ok: !!r[0], installs: inst.length, ios: ios, web: web, active: active, byDay: byDay, firstInstall: first,
        posts: r[1] ? r[1].length : null, approved: r[2] ? r[2].length : null, attendance: r[3] ? att : null
      };
    });
  }

  // ---------- render
  function tile(parent, k, v, s, brand) {
    var t = el("div", "tile" + (brand ? " hl" : "")); t.appendChild(el("div", "k", k)); t.appendChild(el("div", "v", v)); if (s) t.appendChild(el("div", "s", s)); parent.appendChild(t);
  }
  function rangeLabel() { return state.range === "all" ? "all time" : "last " + state.range + " days"; }

  function render() {
    var d = state.data, ck = state.ck, a = d && d.analytics, ps = periods(), grain = state.grain;
    var blue = css("--series-1"), orange = css("--series-2"), aqua = css("--series-3"), yellow = css("--series-4"), other = css("--other");

    // tiles
    var tiles = $("tiles"); tiles.innerHTML = "";
    tile(tiles, "People using the app", ck && ck.ok ? fmt(ck.installs) : "–", ck && ck.ok ? fmt(ck.ios) + " iPhone · " + fmt(ck.web) + " web" : "loading", true);
    tile(tiles, "Active in the last 30 days", ck && ck.ok ? fmt(ck.active) : "–", "opened the app recently");
    var newInst = ck && ck.ok ? sumRange(ck.byDay.ios) + sumRange(ck.byDay.web) : null;
    tile(tiles, "New installs", ck && ck.ok ? fmt(newInst) : "–", rangeLabel());
    tile(tiles, "Web visitors", a ? fmt(sumRange(a.webVisitors)) : "–", a ? rangeLabel() : "visit counting starting soon");
    tile(tiles, "iPhone app opens", a ? fmt(sumRange(a.iosOpens)) : "–", a ? rangeLabel() : "counting starts with the next app update");
    var clickTotal = 0; if (a) for (var kk in a.clicks) clickTotal += sumRange(a.clicks[kk]);
    tile(tiles, "Clicks", a ? fmt(clickTotal) : "–", a ? rangeLabel() : "event opens, directions, saves");
    if (d) {
      tile(tiles, "Events listed now", fmt(d.feed.listedNow), "upcoming in Columbia");
      tile(tiles, "Events listed so far", fmt(d.totals.eventsAllTime), "since " + shortDay(parseDay(d.totals.firstDay)) + ", " + d.totals.firstDay.slice(0, 4));
      tile(tiles, "Venues covered", fmt(d.totals.venuesAllTime), "places with at least one event");
      tile(tiles, "Sources", fmt(d.totals.sourcesNow), "calendars read every 2 hours");
    }

    // visitors
    var colLabel = grain === "day" ? "Day" : grain === "week" ? "Week" : "Month";
    if (a) {
      var web = since(series(a.webVisitors, ps), ps, a.since), ios = since(series(a.iosOpens, ps), ps, a.since);
      var b = card("c-visitors", "Visitors", "Web visitors and iPhone app opens, " + rangeLabel() + (grain !== "day" ? ", daily unique visitors added up" : ""),
        { cols: [colLabel, "Web visitors", "iPhone app opens"], rows: ps.map(function (p, i) { return [p.label, web[i], ios[i]]; }) });
      lineChart(b, ps, [{ name: "Web visitors", color: blue, values: web }, { name: "iPhone app opens", color: orange, values: ios }]);
    } else empty(card("c-visitors", "Visitors", "Web visitors and iPhone app opens"), "Visit counting is being switched on", "Daily visitors and app opens will appear here within an hour of the first visit.");

    // installs (live)
    if (ck && ck.ok) {
      var iI = series(ck.byDay.ios, ps), iW = series(ck.byDay.web, ps);
      var bi = card("c-installs", "New installs", "First launch on a new iPhone, or a new signed-in browser · live",
        { cols: [colLabel, "iPhone", "Web"], rows: ps.map(function (p, i) { return [p.label, iI[i], iW[i]]; }) });
      barChart(bi, ps, [{ name: "iPhone", color: orange, values: iI }, { name: "Web (signed in)", color: blue, values: iW }]);
    } else empty(card("c-installs", "New installs", "live from CloudKit"), ck ? "Couldn't reach CloudKit" : "Loading…", ck ? "Refresh the page to try again." : "");

    // clicks
    if (a && Object.keys(a.clicks).length) {
      var kinds = Object.keys(a.clicks).map(function (k) { return { k: k, n: sumRange(a.clicks[k]) }; }).sort(function (x, y) { return y.n - x.n; });
      var colors = [blue, orange, aqua], list = kinds.slice(0, 3).map(function (o, i) { return { name: o.k, color: colors[i], values: series(a.clicks[o.k], ps) }; });
      if (kinds.length > 3) { var rest = {}; kinds.slice(3).forEach(function (o) { var m = a.clicks[o.k]; for (var dd in m) rest[dd] = (rest[dd] || 0) + m[dd]; }); list.push({ name: "Other", color: other, values: series(rest, ps) }); }
      var bc = card("c-clicks", "Clicks", "What people tap: opening an event, directions, saving, getting the app",
        { cols: [colLabel].concat(list.map(function (s) { return s.name; })), rows: ps.map(function (p, i) { return [p.label].concat(list.map(function (s) { return s.values[i]; })); }) });
      barChart(bc, ps, list);
    } else empty(card("c-clicks", "Clicks", "Event opens, directions, saves, app downloads"), "No clicks recorded yet", "Clicks on the web map and in the iPhone app will show up here.");

    // top events (window)
    var w = a && a.windows ? a.windows[windowKey()] : null;
    var te = card("c-top-events", "Most opened events", rangeLabel());
    if (w && w.topEvents.length) barsList(te, w.topEvents.slice(0, 10).map(function (t) { return { label: t.title || t.id, sub: t.venue, value: t.opens }; }));
    else empty(te, "Nothing yet", "The events people open most will be listed here.");

    // where from
    var rg = card("c-regions", "Locations", rangeLabel() + " · from visitors' internet address, state level at most");
    if (w && (w.usRegions.length || w.locations.length)) {
      if (w.usRegions.length) { rg.appendChild(el("p", "sub", "US states")); barsList(rg, w.usRegions.slice(0, 8).map(function (r) { return { label: r.name, value: r.count }; })); }
      var nonUS = w.locations.filter(function (l) { return (l.id || "").toUpperCase() !== "US"; });
      if (nonUS.length) { rg.appendChild(el("p", "sub", "Other countries")); barsList(rg, nonUS.slice(0, 5).map(function (r) { return { label: r.name, value: r.count }; })); }
    } else empty(rg, "No visits yet", "States and countries visitors come from.");
    var so = card("c-sources", "Traffic sources", rangeLabel() + " · links, QR codes and campaigns");
    var srcRows = w ? w.referrers.map(function (r) { return { label: r.name, value: r.count }; }).concat(w.campaigns.map(function (r) { return { label: r.name, sub: "campaign", value: r.count }; })) : [];
    srcRows.sort(function (x, y) { return y.value - x.value; });
    if (srcRows.length) { so.appendChild(el("p", "sub", "Visits")); barsList(so, srcRows.slice(0, 8)); }
    if (w && w.installTaps && w.installTaps.length) { so.appendChild(el("p", "sub", "Taps on \"Get the app\", by link or QR code")); barsList(so, w.installTaps.slice(0, 6).map(function (r) { return { label: r.source, value: r.taps }; })); }
    if (!srcRows.length && !(w && w.installTaps && w.installTaps.length)) empty(so, "No visits yet", "Reddit, Instagram, flyer QR codes and search will show here.");
    var dv = card("c-devices", "Devices", rangeLabel());
    if (w && (w.systems.length || w.sizes.length)) {
      if (w.sizes.length) { dv.appendChild(el("p", "sub", "Screen")); barsList(dv, w.sizes.map(function (r) { return { label: r.name, value: r.count }; })); }
      if (w.systems.length) { dv.appendChild(el("p", "sub", "System")); barsList(dv, w.systems.slice(0, 6).map(function (r) { return { label: r.name, value: r.count }; })); }
    } else empty(dv, "No visits yet", "Phones, tablets and computers.");

    if (!d) return;
    // events history (running totals: last value per period)
    var hist = {}, listed = {};
    d.history.forEach(function (h) { hist[h.day] = h.total; listed[h.day] = h.listed; });
    var hT = series(hist, ps, "last"), hL = series(listed, ps, "last");
    var bh = card("c-history", "Events listed so far", "Every event that has appeared on the map, and how many are listed at that moment",
      { cols: [colLabel, "Listed so far", "Listed at the time"], rows: ps.map(function (p, i) { return [p.label, hT[i], hL[i]]; }) });
    lineChart(bh, ps, [{ name: "Listed so far", color: blue, values: hT }, { name: "Listed at the time", color: orange, values: hL }], "events");

    // upcoming next 30 days (not range-scoped)
    var up = d.feed.next30Days, ups = up.map(function (u) { var dd = parseDay(u.day); return { label: ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][dd.getDay()] + " " + shortDay(dd), tick: shortDay(dd) }; });
    var bu = card("c-upcoming", "Coming up", "Events per day for the next 30 days, as listed right now",
      { cols: ["Day", "Events"], rows: up.map(function (u, i) { return [ups[i].label, u.events]; }) });
    barChart(bu, ups, [{ name: "Events", color: blue, values: up.map(function (u) { return u.events; }) }]);

    var bs = card("c-by-source", "Where the events come from", "Upcoming events per source, right now");
    barsList(bs, d.feed.sources.map(function (s) { return { label: s.name, value: s.events }; }));
    var bk = card("c-by-category", "What kind of events", "Upcoming events per category, right now");
    barsList(bk, d.feed.categories.map(function (c) { return { label: CAT[c.id] || c.id, value: c.events }; }));

    // community (live)
    var cm = $("community"); cm.innerHTML = "";
    if (ck && ck.ok) {
      tile(cm, "Events posted by people", fmt(ck.posts), ck.approved != null ? fmt(ck.approved) + " approved" : "");
      tile(cm, "Going taps", ck.attendance ? fmt(ck.attendance.going) : "–", "people who said they're going");
      tile(cm, "\"I'm here\" check-ins", ck.attendance ? fmt(ck.attendance.here) : "–", "at events right now or earlier");
      tile(cm, "Went", ck.attendance ? fmt(ck.attendance.went) : "–", "marked after the event");
    } else tile(cm, "Community", "–", "loading from CloudKit");
  }

  // ---------- venues (map + table), rendered once per data load
  var vmap = null;
  function renderVenues() {
    var d = state.data; if (!d) return;
    var vs = d.feed.venues;
    $("venue-sub").textContent = fmt(vs.length) + " venues so far · " + fmt(vs.filter(function (v) { return v.now; }).length) + " with upcoming events. Circle size shows how many events each one has had.";
    var tb = document.querySelector("#venue-table tbody");
    function fill(q) {
      tb.innerHTML = ""; q = (q || "").toLowerCase();
      vs.filter(function (v) { return !q || v.name.toLowerCase().indexOf(q) >= 0; }).forEach(function (v) {
        var tr = el("tr"), td = el("td");
        if (v.website) { var a = el("a", null, v.name); a.href = v.website; a.rel = "noopener nofollow"; td.appendChild(a); } else td.textContent = v.name;
        if (v.address) td.appendChild(el("div", "sub", v.address));
        tr.appendChild(td); tr.appendChild(el("td", "num", fmt(v.now))); tr.appendChild(el("td", "num", fmt(v.total))); tb.appendChild(tr);
      });
    }
    fill($("venue-q").value); $("venue-q").oninput = function (e) { fill(e.target.value); };
    var pts = vs.filter(function (v) { return v.lat && v.lng && Math.abs(v.lat - 38.95) < 0.25 && Math.abs(v.lng + 92.33) < 0.3; });
    var gj = { type: "FeatureCollection", features: pts.map(function (v) { return { type: "Feature", geometry: { type: "Point", coordinates: [v.lng, v.lat] }, properties: { name: v.name, now: v.now, total: v.total } }; }) };
    if (vmap) { var src = vmap.getSource && vmap.getSource("venues"); if (src) src.setData(gj); return; }
    if (fallbackDrawn) { drawFallback(pts); return; }
    if (mapPending) return;
    mapPending = true;
    // start the map only when its card is near the screen (no WebGL in hidden or background tabs)
    var box = $("venue-map");
    var go = function () { startMap(gj, pts, 0); };
    if ("IntersectionObserver" in window) {
      var io = new IntersectionObserver(function (en) { if (en.some(function (x) { return x.isIntersecting; })) { io.disconnect(); go(); } }, { rootMargin: "400px" });
      io.observe(box);
    } else go();
  }
  var mapPending = false, fallbackDrawn = false;
  function startMap(gj, pts, tries) {
    if (/[?&]map=simple/.test(location.search)) return drawFallback(pts);
    if (!window.maplibregl) { if (tries < 20) return setTimeout(function () { startMap(gj, pts, tries + 1); }, 500); return drawFallback(pts); }
    try {
      vmap = new maplibregl.Map({ container: "venue-map", style: "https://tiles.openfreemap.org/styles/liberty", center: [-92.3341, 38.9517], zoom: 11.4, attributionControl: { compact: true }, cooperativeGestures: true });
    } catch (err) { vmap = null; return drawFallback(pts); }
    var loaded = false;
    var timer = setTimeout(function () { if (!loaded) { try { vmap.remove(); } catch (_) {} vmap = null; drawFallback(pts); } }, 15000);
    vmap.on("error", function (e) { if (!loaded && e && e.error && /style|webgl/i.test(String(e.error.message || ""))) { clearTimeout(timer); try { vmap.remove(); } catch (_) {} vmap = null; drawFallback(pts); } });
    vmap.addControl(new maplibregl.NavigationControl({ showCompass: false }), "top-right");
    vmap.on("load", function () {
      loaded = true; clearTimeout(timer);
      vmap.addSource("venues", { type: "geojson", data: gj });
      vmap.addLayer({ id: "venues", type: "circle", source: "venues", paint: {
        "circle-color": css("--seq") || "#2a78d6", "circle-opacity": .75, "circle-stroke-color": "#ffffff", "circle-stroke-width": 1.5,
        "circle-radius": ["interpolate", ["linear"], ["sqrt", ["get", "total"]], 1, 4, 5, 10, 16, 26] } });
      var pop = new maplibregl.Popup({ closeButton: false, closeOnClick: false, offset: 8 });
      vmap.on("mousemove", "venues", function (e) {
        vmap.getCanvas().style.cursor = "pointer"; var p = e.features[0].properties, b = el("div");
        b.appendChild(el("b", null, p.name)); b.appendChild(el("div", null, fmt(p.total) + " events so far · " + fmt(p.now) + " upcoming"));
        pop.setLngLat(e.features[0].geometry.coordinates).setDOMContent(b).addTo(vmap);
      });
      vmap.on("mouseleave", "venues", function () { vmap.getCanvas().style.cursor = ""; pop.remove(); });
    });
    document.addEventListener("visibilitychange", function () { if (!document.hidden && vmap) vmap.resize(); });
  }

  // A plain SVG dot map: used when the browser can't start the WebGL map.
  function drawFallback(pts) {
    fallbackDrawn = true;
    var box = $("venue-map"); box.innerHTML = ""; box.className = "venue-map fallback";
    var W = 1000, H = 420, lat0 = 38.9517, lng0 = -92.3341, k = Math.cos(lat0 * Math.PI / 180);
    var span = 0.16, sx = function (lng) { return W / 2 + (lng - lng0) * k / span * W / 2; }, sy = function (lat) { return H / 2 - (lat - lat0) / (span * H / W) * H / 2; };
    var s = sv("svg", { viewBox: "0 0 " + W + " " + H, role: "img", "aria-label": "Venue map" });
    for (var i = 1; i < 6; i++) { s.appendChild(sv("line", { x1: 0, x2: W, y1: H * i / 6, y2: H * i / 6, "class": "gridline" })); s.appendChild(sv("line", { y1: 0, y2: H, x1: W * i / 6, x2: W * i / 6, "class": "gridline" })); }
    var c = sv("circle", { cx: W / 2, cy: H / 2, r: 5, fill: "none", stroke: css("--axis") }); s.appendChild(c);
    var lab = sv("text", { x: W / 2 + 10, y: H / 2 - 8, "class": "fb-label" }); lab.textContent = "Downtown Columbia"; s.appendChild(lab);
    var color = css("--seq"), surface = css("--surface-1");
    pts.slice().sort(function (a, b) { return b.total - a.total; }).forEach(function (v) {
      var x = sx(v.lng), y = sy(v.lat); if (x < 0 || x > W || y < 0 || y > H) return;
      var dot = sv("circle", { cx: x.toFixed(1), cy: y.toFixed(1), r: Math.max(4, Math.min(26, 2.2 * Math.sqrt(v.total) + 2)), fill: color, "fill-opacity": .7, stroke: surface, "stroke-width": 1.5 });
      var t = sv("title"); t.textContent = v.name + ": " + v.total + " events so far, " + v.now + " upcoming"; dot.appendChild(t);
      dot.addEventListener("pointermove", function (e) { showTip(e, v.name, [{ name: "events so far", value: v.total }, { name: "upcoming", value: v.now }]); });
      dot.addEventListener("pointerleave", hideTip);
      s.appendChild(dot);
    });
    box.appendChild(s);
    box.appendChild(el("p", "sub fb-note", "Simple view: your browser couldn't start the interactive map. Hover a circle for its name."));
  }

  // ---------- load + refresh
  function stamp() {
    var u = $("updated"); u.innerHTML = ""; u.appendChild(el("span", "dot"));
    var d = state.data, parts = ["Live · checked " + new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" })];
    if (d && d.builtAt) parts.push("visits and events updated " + new Date(d.builtAt).toLocaleString([], { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" }));
    u.appendChild(document.createTextNode(parts.join(" · ")));
  }
  function load() {
    return Promise.all([
      fetch("data.json?t=" + Date.now()).then(function (r) { return r.json(); }).catch(function () { return state.data; }),
      loadCloud().catch(function () { return { ok: false }; })
    ]).then(function (r) {
      state.data = r[0]; state.ck = r[1] || { ok: false };
      try { render(); } catch (err) { console.error("stats render", err); }
      try { renderVenues(); } catch (err) { console.error("venues", err); }
      stamp();
    });
  }
  function seg(id, key) {
    $(id).addEventListener("click", function (e) {
      var b = e.target.closest("button"); if (!b) return;
      state[key] = b.dataset.v;
      $(id).querySelectorAll("button").forEach(function (x) { var on = x === b; x.classList.toggle("on", on); x.setAttribute("aria-checked", String(on)); });
      render();
    });
  }
  document.addEventListener("DOMContentLoaded", function () {
    seg("range", "range"); seg("grain", "grain");
    load(); setInterval(load, 5 * 60 * 1000);
    var t; addEventListener("resize", function () { clearTimeout(t); t = setTimeout(render, 150); });
    matchMedia("(prefers-color-scheme: dark)").addEventListener("change", render);
  });
})();
