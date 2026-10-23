/* CoMo Events smart search + ranking (web). Mirrors CoMoEvents/Support/SmartSearch.swift and
   TasteProfile.swift; change both together.

   - Concepts come from search.json (same file the feed uses to tag events: e.tags, "x~" = weak).
   - A query becomes "units": a concept (typos forgiven: "intellignece", "shanti") or a plain word.
     Each unit scores an event by its tags and by words in title / venue / organizer / description.
   - Rank = relevance + quality (e.score from the feed) + what this person likes + how soon.
   - Taste: learned in this browser only from saves, Going / I'm here and opened events. */
(function () {
  var S = window.SmartSearch = { concepts: {}, aliases: [], stop: new Set(), time: {}, vocab: new Set(), ready: false };

  function norm(s) {
    return String(s || "").toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "")
      .replace(/[’']/g, "").replace(/[^a-z0-9+&]+/g, " ").trim();
  }
  function words(s) { var n = norm(s); return n ? n.split(" ") : []; }
  S.norm = norm; S.words = words;

  // Damerau-Levenshtein (optimal string alignment), bounded.
  function dist(a, b, max) {
    if (Math.abs(a.length - b.length) > max) return max + 1;
    var d = [], i, j;
    for (i = 0; i <= a.length; i++) { d[i] = [i]; }
    for (j = 0; j <= b.length; j++) d[0][j] = j;
    for (i = 1; i <= a.length; i++) {
      var rowMin = Infinity;
      for (j = 1; j <= b.length; j++) {
        var c = a[i - 1] === b[j - 1] ? 0 : 1;
        d[i][j] = Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + c);
        if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) d[i][j] = Math.min(d[i][j], d[i - 2][j - 2] + 1);
        if (d[i][j] < rowMin) rowMin = d[i][j];
      }
      if (rowMin > max) return max + 1;
    }
    return d[a.length][b.length];
  }
  function allowed(w) { return w.length >= 8 ? 2 : w.length >= 5 ? 1 : 0; }
  /** 1 exact, 0.85 typo, 0 no. Short words must match exactly. */
  function wordSim(q, w) {
    if (q === w) return 1;
    var m = allowed(q);
    if (m && dist(q, w, m) <= m) return 0.85;
    return 0;
  }
  S.wordSim = wordSim;

  S.load = function (data) {
    S.concepts = {}; S.aliases = [];
    Object.keys(data.concepts || {}).forEach(function (k) {
      var c = data.concepts[k]; S.concepts[k] = c;
      // Head words name the whole topic ("tech", "church", "religious"); other aliases are narrower ("volleyball", "jazz").
      var heads = new Set([norm(k), norm(c.label)].concat((c.query || []).slice(0, 2).map(norm)));
      (c.query || []).concat([norm(c.label)]).forEach(function (q) { var w = words(q); if (w.length) S.aliases.push({ w: w, key: k, head: heads.has(w.join(" ")) }); });
    });
    S.aliases.sort(function (a, b) { return b.w.length - a.w.length; });   // longest phrase first
    S.stop = new Set(data.stopwords || []);
    S.time = {}; Object.keys(data.time || {}).forEach(function (k) { data.time[k].forEach(function (w) { S.time[w] = k; }); });
    S.ready = true;
  };
  S.fetch = function (url) {
    return fetch(url, { cache: "no-cache" }).then(function (r) { return r.json(); }).then(S.load).catch(function () {});
  };

  /** Query → { units: [{concepts:Set, words:[...], label}], time: "today"|"tomorrow"|"weekend"|null } */
  S.parse = function (q) {
    var toks = words(q), units = [], time = null, i = 0;
    while (i < toks.length) {
      if (S.time[toks[i]]) { time = S.time[toks[i]]; i++; continue; }
      if (toks[i] === "this" && toks[i + 1] === "weekend") { time = "weekend"; i += 2; continue; }
      // Longest alias phrase wins, then the closest spelling; ties add every concept they name.
      var hit = null;
      for (var a = 0; a < S.aliases.length; a++) {
        var al = S.aliases[a], n = al.w.length;
        if (hit && n < hit.n) break;
        if (i + n > toks.length) continue;
        var sim = 1;
        for (var k = 0; k < n && sim > 0; k++) {
          var t = toks[i + k], s1 = wordSim(t, al.w[k]);
          if (s1 < 1 && S.vocab.has(t)) s1 = 0;   // a real word in the events ("james") is not a typo of "games"
          sim = Math.min(sim, s1);
        }
        if (!sim) continue;
        if (!hit || sim > hit.sim) hit = { n: n, sim: sim, keys: new Set([al.key]), head: al.head };
        else if (sim === hit.sim) { hit.keys.add(al.key); hit.head = hit.head || al.head; }
      }
      if (hit) {
        var span = toks.slice(i, i + hit.n);
        var same = units.find(function (u) { return u.concepts && Array.from(hit.keys).some(function (k) { return u.concepts.has(k); }); });
        if (same) { hit.keys.forEach(function (k) { same.concepts.add(k); }); same.words = same.words.concat(span); same.broad = same.broad || hit.head; }
        else units.push({ concepts: hit.keys, words: span, broad: hit.head });
        i += hit.n; continue;
      }
      if (!S.stop.has(toks[i]) && toks[i].length >= 2) units.push({ concepts: null, words: [toks[i]] });
      i++;
    }
    units.forEach(function (u) { u.label = u.concepts ? S.concepts[Array.from(u.concepts)[0]].label : u.words.join(" "); });
    return { units: units, time: time };
  };

  /** Words that really occur in event titles, venues and organizers (guards typo matching). */
  S.setVocab = function (events) {
    var v = new Set();
    events.forEach(function (e) { var f = fields(e); f.title.concat(f.venue, f.org).forEach(function (w) { v.add(w); }); });
    S.vocab = v;
  };

  /** Lazily built, cached per event: normalized words of each field. */
  function fields(e) {
    if (e._sf) return e._sf;
    var org = typeof e.organizer === "string" ? e.organizer : "";
    e._sf = { title: words(e.title), venue: words(e.venue), org: words(org), desc: words((e.description || "").slice(0, 600)),
              cats: (e.categories || [e.category]).join(" ") };
    return e._sf;
  }
  function fieldHit(qw, list, fuzzy) {
    var best = 0;
    for (var i = 0; i < list.length; i++) {
      var w = list[i];
      if (w === qw) return 1;
      if (qw.length >= 3 && w.indexOf(qw) === 0) best = Math.max(best, 0.9);
      else if (fuzzy && best < 0.85 && !S.vocab.has(qw) && wordSim(qw, w)) best = 0.85;
    }
    return best;
  }
  /** Mean over the unit's words, so "mizzou football" needs both words to score fully. */
  function textScore(words_, e) {
    var f = fields(e), total = 0, n = 0;
    for (var i = 0; i < words_.length; i++) {
      var w = words_[i]; if (S.stop.has(w)) continue;
      n++;
      total += Math.max(fieldHit(w, f.title, true) * 1, fieldHit(w, f.venue, true) * 0.85, fieldHit(w, f.org, false) * 0.7,
                        fieldHit(w, f.desc, false) * 0.4, f.cats.indexOf(w) >= 0 ? 0.8 : 0);
    }
    return n ? total / n : 0;
  }
  function conceptScore(concepts, e) {
    var tags = e.tags || [], best = 0;
    concepts.forEach(function (k) {
      if (tags.indexOf(k) >= 0) best = 1;
      else if (best < 0.5 && tags.indexOf(k + "~") >= 0) best = 0.5;
      var cat = S.concepts[k] && S.concepts[k].category;
      if (cat && (e.categories || [e.category]).indexOf(cat) >= 0) best = 1;
    });
    return best;
  }
  /** 0..1 relevance, or 0 if the event doesn't answer enough of the query. */
  /** loose: accept events that answer any part of the query (used when nothing answers all of it). */
  S.relevance = function (parsed, e, loose) {
    var units = parsed.units; if (!units.length) return 1;
    var sum = 0, hits = 0;
    for (var i = 0; i < units.length; i++) {
      var u = units[i], s;
      if (u.concepts) {
        // "tech": every tech-tagged event counts fully, a stray "Tennessee Tech" title less.
        // "volleyball": the word itself first, other sports after.
        var c = conceptScore(u.concepts, e), t = textScore(u.words, e);
        s = u.broad ? Math.max(c, t * (c ? 1 : 0.6)) + (c && t >= 0.85 ? 0.15 : 0) : Math.max(c * 0.55, t);
      } else s = textScore(u.words, e);
      if (s >= 0.3) hits++; else s = 0;
      sum += s;
    }
    var need = loose ? 1 : units.length <= 2 ? units.length : units.length - 1;
    return hits >= need ? sum / units.length : 0;
  };
  /** Ranked search over a list: [{e, rel, rank}], repeats of the same title + venue collapsed to the soonest. */
  S.search = function (q, list, now, goingCount) {
    var p = S.parse(q), out = [];
    for (var pass = 0; pass < 2 && !out.length; pass++) {
      list.forEach(function (e) {
        var r = S.relevance(p, e, pass === 1);
        if (r > 0) out.push({ e: e, rel: r, rank: S.searchRank(r, e, now, goingCount ? goingCount(e) : 0) });
      });
      if (p.units.length < 2) break;
    }
    // Strong matches exist → drop the loosely related tail ("pottery" shouldn't list comedy shows).
    var top = out.reduce(function (m, x) { return Math.max(m, x.rel); }, 0);
    if (top >= 0.85) out = out.filter(function (x) { return x.rel >= 0.6 * top; });
    out.sort(function (a, b) { return b.rank - a.rank; });
    var seen = new Set();
    out = out.filter(function (x) { var k = norm(x.e.title) + "|" + norm(x.e.venue); if (seen.has(k)) return false; seen.add(k); return true; });
    out.parsed = p;
    return out;
  };

  // ---------- taste (this browser only) ----------
  var KEY = "taste.v1";
  function loadTaste() { try { return JSON.parse(localStorage.getItem(KEY)) || {}; } catch (e) { return {}; } }
  var taste = loadTaste();
  function saveTaste() {
    var keys = Object.keys(taste);
    if (keys.length > 400) keys.sort(function (a, b) { return taste[a] - taste[b]; }).slice(0, keys.length - 400).forEach(function (k) { delete taste[k]; });
    try { localStorage.setItem(KEY, JSON.stringify(taste)); } catch (e) {}
  }
  function features(e) {
    var out = [];
    (e.categories || [e.category]).forEach(function (c) { out.push("c:" + c); });
    (e.tags || []).forEach(function (t) { if (t.slice(-1) !== "~" && t !== "downtown" && t !== "campus" && t !== "free") out.push("t:" + t); });
    if (e.venue) out.push("v:" + norm(e.venue));
    words(e.title).forEach(function (w) { if (w.length >= 4 && !S.stop.has(w) && !/^\d+$/.test(w)) out.push("w:" + w); });
    return out;
  }
  /** Signal weights: save 3, going 4, here/went 4, open 1. Negative undoes a save. */
  S.learn = function (e, weight) {
    if (!e) return;
    features(e).forEach(function (f) { taste[f] = Math.max(0, (taste[f] || 0) + weight); if (!taste[f]) delete taste[f]; });
    saveTaste();
  };
  S.seedInterests = function (cats) { (cats || []).forEach(function (c) { if (!taste["c:" + c]) taste["c:" + c] = 2; }); };
  S.hasTaste = function () { return Object.keys(taste).length > 0; };
  S.resetTaste = function () { taste = {}; saveTaste(); };
  /** 0..18 boost for how well the event fits what this person saves, attends and opens. */
  S.personal = function (e) {
    var raw = 0;
    features(e).forEach(function (f) {
      var w = taste[f]; if (!w) return;
      raw += w * (f[0] === "v" ? 1.4 : f[0] === "t" ? 1 : f[0] === "c" ? 0.8 : 0.35);
    });
    return 18 * (1 - Math.exp(-raw / 10));
  };

  /** Base rank without a query: quality + taste + popularity (going count). */
  S.baseRank = function (e, going) {
    return (e.score == null ? 40 : e.score) * 0.6 + S.personal(e) + Math.min(going || 0, 5) * 2;
  };
  /** Rank with a query. */
  S.searchRank = function (rel, e, now, going) {
    var days = (e._start - now) / 864e5, soon = days < 0 ? 10 : days < 2 ? 10 : days < 7 ? 6 : days < 30 ? 2 : 0;
    return rel * 60 + (e.score == null ? 40 : e.score) * 0.25 + S.personal(e) + soon + Math.min(going || 0, 5);
  };
})();
