/* CoMo Events web app. A browser twin of the iPhone app: same feed, same filters, same look.
   No build step, no account, no analytics. Reads ../events.json (copied from feed/ by the
   workflow) with the raw GitHub copy as fallback. Favorites and profile live in localStorage.
   Map: MapLibre GL on OpenFreeMap's "liberty" style (free, no key) with pitch and 3D buildings. */
(function () {
  "use strict";

  var FEED = ["events.json", "https://raw.githubusercontent.com/xenificity/comoevents/main/feed/events.json"];
  var STYLE = "https://tiles.openfreemap.org/styles/liberty";
  var INSTALL = "get/?c=webapp";
  function track(path, title) { try { if (window.CE_track) window.CE_track(path, title); } catch (_) {} }
  function siteRoot() { return location.origin + location.pathname.replace(/(app\/)?[^/]*$/, ""); }   // the folder the app is served from: comoevent.com/ or github.io/comoevents/
  var CENTER = [-92.3300, 38.9480];

  // SF-Symbol-like glyphs (Material paths, 24x24).
  var ICONS = {
    party: "M14.5 2l1.1 2.4L18 5.5l-2.4 1.1L14.5 9l-1.1-2.4L11 5.5l2.4-1.1zM4 22l3-10 7 7-10 3zm15-9l.8 1.7 1.7.8-1.7.8L19 18l-.8-1.7-1.7-.8 1.7-.8z",
    music: "M12 3v10.55A4 4 0 1 0 14 17V7h4V3h-6z",
    nightlife: "M12 3a9 9 0 1 0 9 9c0-.46-.04-.92-.1-1.36a5.389 5.389 0 0 1-4.4 2.26 5.403 5.403 0 0 1-3.14-9.8c-.44-.06-.9-.1-1.36-.1z",
    food: "M11 9H9V2H7v7H5V2H3v7c0 2.12 1.66 3.84 3.75 3.97V22h2.5v-9.03C11.34 12.84 13 11.12 13 9V2h-2v7zm5-3v8h2.5v8H21V2c-2.76 0-5 2.24-5 4z",
    arts: "M12 2C6.49 2 2 6.49 2 12s4.49 10 10 10c1.38 0 2.5-1.12 2.5-2.5 0-.61-.23-1.2-.64-1.67-.08-.1-.13-.21-.13-.33 0-.28.22-.5.5-.5H16c3.31 0 6-2.69 6-6 0-4.96-4.49-9-10-9zm5.5 11c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zm-3-4c-.83 0-1.5-.67-1.5-1.5S13.67 6 14.5 6s1.5.67 1.5 1.5S15.33 9 14.5 9zM5 11.5c0-.83.67-1.5 1.5-1.5S8 10.67 8 11.5 7.33 13 6.5 13 5 12.33 5 11.5zm6-4c0 .83-.67 1.5-1.5 1.5S8 8.33 8 7.5 8.67 6 9.5 6s1.5.67 1.5 1.5z",
    sports: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 2c1.3 0 2.5.3 3.6.9L12 8.3 8.4 4.9C9.5 4.3 10.7 4 12 4zM4 12c0-1.9.7-3.7 1.8-5.1L9 11v2l-3.2 4.1A7.96 7.96 0 0 1 4 12zm8 8c-1.3 0-2.5-.3-3.6-.9L12 15.7l3.6 3.4c-1.1.6-2.3.9-3.6.9zm6.2-2.9L15 13v-2l3.2-4.1A7.96 7.96 0 0 1 20 12c0 1.9-.7 3.7-1.8 5.1z",
    family: "M16 4a2 2 0 1 1 0 4 2 2 0 0 1 0-4zM8 4a2 2 0 1 1 0 4 2 2 0 0 1 0-4zm4 5a1.5 1.5 0 1 1 0 3 1.5 1.5 0 0 1 0-3zM5 9h6l-1 7H9v5H7v-5H6L5 9zm8 0h6l-1 7h-1v5h-2v-5h-1l-1-7zm-2.5 4h3l-.5 4h-.5v3h-1v-3h-.5l-.5-4z",
    campus: "M12 3L1 9l11 6 9-4.91V17h2V9L12 3zm0 13.5L5 12.7V16c0 1.66 3.13 3 7 3s7-1.34 7-3v-3.3l-7 3.8z",
    community: "M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z",
    sparkles: "M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8zM5 16l.9 2.1L8 19l-2.1.9L5 22l-.9-2.1L2 19l2.1-.9zM19 14l.7 1.6 1.6.7-1.6.7L19 18.6l-.7-1.6-1.6-.7 1.6-.7z",
    person: "M12 12c2.21 0 4-1.79 4-4s-1.79-4-4-4-4 1.79-4 4 1.79 4 4 4zm0 2c-2.67 0-8 1.34-8 4v2h16v-2c0-2.66-5.33-4-8-4z",
    heart: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z",
    heartO: "M16.5 3c-1.74 0-3.41.81-4.5 2.09C10.91 3.81 9.24 3 7.5 3 4.42 3 2 5.42 2 8.5c0 3.78 3.4 6.86 8.55 11.54L12 21.35l1.45-1.32C18.6 15.36 22 12.28 22 8.5 22 5.42 19.58 3 16.5 3zm-4.4 15.55l-.1.1-.1-.1C7.14 14.24 4 11.39 4 8.5 4 6.5 5.5 5 7.5 5c1.54 0 3.04.99 3.57 2.36h1.87C13.46 5.99 14.96 5 16.5 5c2 0 3.5 1.5 3.5 3.5 0 2.89-3.14 5.74-7.9 10.05z",
    map: "M20.5 3l-.16.03L15 5.1 9 3 3.36 4.9c-.21.07-.36.25-.36.48V20.5c0 .28.22.5.5.5l.16-.03L9 18.9l6 2.1 5.64-1.9c.21-.07.36-.25.36-.48V3.5c0-.28-.22-.5-.5-.5zM15 19l-6-2.11V5l6 2.11V19z",
    pin: "M12 2C8.13 2 5 5.13 5 9c0 5.25 7 13 7 13s7-7.75 7-13c0-3.87-3.13-7-7-7zm0 9.5a2.5 2.5 0 1 1 0-5 2.5 2.5 0 0 1 0 5z",
    clock: "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm.5 5v5.25l4.5 2.67-.75 1.23L11 13V7h1.5z",
    tag: "M21.41 11.58l-9-9C12.05 2.22 11.55 2 11 2H4c-1.1 0-2 .9-2 2v7c0 .55.22 1.05.59 1.42l9 9c.36.36.86.58 1.41.58s1.05-.22 1.41-.59l7-7c.37-.36.59-.86.59-1.41s-.23-1.06-.59-1.42zM5.5 7C4.67 7 4 6.33 4 5.5S4.67 4 5.5 4 7 4.67 7 5.5 6.33 7 5.5 7z",
    phone: "M6.62 10.79c1.44 2.83 3.76 5.14 6.59 6.59l2.2-2.2c.27-.27.67-.36 1.02-.24 1.12.37 2.33.57 3.57.57.55 0 1 .45 1 1V20c0 .55-.45 1-1 1-9.39 0-17-7.61-17-17 0-.55.45-1 1-1h3.5c.55 0 1 .45 1 1 0 1.25.2 2.45.57 3.57.11.35.03.74-.25 1.02l-2.2 2.2z",
    share: "M18 16.08c-.76 0-1.44.3-1.96.77L8.91 12.7c.05-.23.09-.46.09-.7s-.04-.47-.09-.7l7.05-4.11c.54.5 1.25.81 2.04.81 1.66 0 3-1.34 3-3s-1.34-3-3-3-3 1.34-3 3c0 .24.04.47.09.7L8.04 9.81C7.5 9.31 6.79 9 6 9c-1.66 0-3 1.34-3 3s1.34 3 3 3c.79 0 1.5-.31 2.04-.81l7.12 4.16c-.05.21-.08.43-.08.65 0 1.61 1.31 2.92 2.92 2.92 1.61 0 2.92-1.31 2.92-2.92s-1.31-2.92-2.92-2.92z",
    calendar: "M19 4h-1V2h-2v2H8V2H6v2H5c-1.11 0-2 .9-2 2v14c0 1.1.89 2 2 2h14c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 16H5V9h14v11zM12 11h5v5h-5z",
    car: "M18.92 6.01C18.72 5.42 18.16 5 17.5 5h-11c-.66 0-1.21.42-1.42 1.01L3 12v8c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-1h12v1c0 .55.45 1 1 1h1c.55 0 1-.45 1-1v-8l-2.08-5.99zM6.5 16c-.83 0-1.5-.67-1.5-1.5S5.67 13 6.5 13s1.5.67 1.5 1.5S7.33 16 6.5 16zm11 0c-.83 0-1.5-.67-1.5-1.5s.67-1.5 1.5-1.5 1.5.67 1.5 1.5-.67 1.5-1.5 1.5zM5 11l1.5-4.5h11L19 11H5z",
    arrow: "M7 7h8.59L5.29 17.29l1.42 1.42L17 8.41V17h2V5H7z",
    list: "M3 13h2v-2H3v2zm0 4h2v-2H3v2zm0-8h2V7H3v2zm4 4h14v-2H7v2zm0 4h14v-2H7v2zM7 7v2h14V7H7z",
    search: "M15.5 14h-.79l-.28-.27A6.47 6.47 0 0 0 16 9.5 6.5 6.5 0 1 0 9.5 16c1.61 0 3.09-.59 4.23-1.57l.27.28v.79l5 4.99L20.49 19l-4.99-5zm-6 0C7.01 14 5 11.99 5 9.5S7.01 5 9.5 5 14 7.01 14 9.5 11.99 14 9.5 14z",
    thumb: "M1 21h4V9H1v12zm22-11c0-1.1-.9-2-2-2h-6.31l.95-4.57.03-.32c0-.41-.17-.79-.44-1.06L14.17 1 7.59 7.59C7.22 7.95 7 8.45 7 9v10c0 1.1.9 2 2 2h9c.83 0 1.54-.5 1.84-1.22l3.02-7.05c.09-.23.14-.47.14-.73v-2z",
    here: "M12 8c-2.21 0-4 1.79-4 4s1.79 4 4 4 4-1.79 4-4-1.79-4-4-4zm8.94 3A8.994 8.994 0 0 0 13 3.06V1h-2v2.06A8.994 8.994 0 0 0 3.06 11H1v2h2.06A8.994 8.994 0 0 0 11 20.94V23h2v-2.06A8.994 8.994 0 0 0 20.94 13H23v-2h-2.06zM12 19c-3.87 0-7-3.13-7-7s3.13-7 7-7 7 3.13 7 7-3.13 7-7 7z",
    check: "M12 2l2.09 2.26 3.05-.44.44 3.05L20 9l-1.42 2.74 1.42 2.74-2.42 2.13-.44 3.05-3.05-.44L12 22l-2.09-2.26-3.05.44-.44-3.05L4 15.48l1.42-2.74L4 10l2.42-2.13.44-3.05 3.05.44L12 2zm-1.2 13.4l5.6-5.6-1.4-1.4-4.2 4.2-2-2-1.4 1.4 3.4 3.4z",
    plus: "M19 13h-6v6h-2v-6H5v-2h6V5h2v6h6v2z",
    refresh: "M17.65 6.35A7.958 7.958 0 0 0 12 4c-4.42 0-7.99 3.58-7.99 8s3.57 8 7.99 8c3.73 0 6.84-2.55 7.73-6h-2.08A5.99 5.99 0 0 1 12 18c-3.31 0-6-2.69-6-6s2.69-6 6-6c1.66 0 3.14.69 4.22 1.78L13 11h7V4l-2.35 2.35z",
    back: "M15.41 7.41L14 6l-6 6 6 6 1.41-1.41L10.83 12z",
    more: "M6 10a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4zm6 0a2 2 0 1 0 0 4 2 2 0 0 0 0-4z",
    flag: "M14.4 6L14 4H5v17h2v-7h5.6l.4 2h7V6z",
    couples: "M12 21.35l-1.45-1.32C5.4 15.36 2 12.28 2 8.5 2 5.42 4.42 3 7.5 3c1.74 0 3.41.81 4.5 2.09C13.09 3.81 14.76 3 16.5 3 19.58 3 22 5.42 22 8.5c0 3.78-3.4 6.86-8.55 11.54L12 21.35z",
    mail: "M20 4H4c-1.1 0-2 .9-2 2v12c0 1.1.9 2 2 2h16c1.1 0 2-.9 2-2V6c0-1.1-.9-2-2-2zm0 4l-8 5-8-5V6l8 5 8-5v2z",
    star: "M12 17.27L18.18 21l-1.64-7.03L22 9.24l-7.19-.61L12 2 9.19 8.63 2 9.24l5.46 4.73L5.82 21z",
    shield: "M12 1L3 5v6c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V5l-9-4zm-2 16l-4-4 1.41-1.41L10 14.17l6.59-6.59L18 9l-8 8z",
    lock: "M18 8h-1V6c0-2.76-2.24-5-5-5S7 3.24 7 6v2H6c-1.1 0-2 .9-2 2v10c0 1.1.9 2 2 2h12c1.1 0 2-.9 2-2V10c0-1.1-.9-2-2-2zm-6 9c-1.1 0-2-.9-2-2s.9-2 2-2 2 .9 2 2-.9 2-2 2zm3.1-9H8.9V6c0-1.71 1.39-3.1 3.1-3.1 1.71 0 3.1 1.39 3.1 3.1v2z",
    phoneDev: "M17 1.01L7 1c-1.1 0-2 .9-2 2v18c0 1.1.9 2 2 2h10c1.1 0 2-.9 2-2V3c0-1.1-.9-1.99-2-1.99zM17 19H7V5h10v14z",
    sound: "M3 9v6h4l5 5V4L7 9H3zm13.5 3A4.5 4.5 0 0 0 14 7.97v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z",
    people: "M16 11c1.66 0 2.99-1.34 2.99-3S17.66 5 16 5c-1.66 0-3 1.34-3 3s1.34 3 3 3zm-8 0c1.66 0 2.99-1.34 2.99-3S9.66 5 8 5C6.34 5 5 6.34 5 8s1.34 3 3 3zm0 2c-2.33 0-7 1.17-7 3.5V19h14v-2.5c0-2.33-4.67-3.5-7-3.5zm8 0c-.29 0-.62.02-.97.05 1.16.84 1.97 1.97 1.97 3.45V19h6v-2.5c0-2.33-4.67-3.5-7-3.5z"
  };
  function ic(name) { return '<i class="ic"><svg viewBox="0 0 24 24"><path d="' + ICONS[name] + '"/></svg></i>'; }

  var CATS = {
    party:     { label: "Party",     color: "var(--party)" },
    music:     { label: "Music",     color: "var(--music)" },
    nightlife: { label: "Nightlife", color: "var(--nightlife)" },
    food:      { label: "Food",      color: "var(--food)" },
    arts:      { label: "Arts",      color: "var(--arts)" },
    sports:    { label: "Sports",    color: "var(--sports)" },
    family:    { label: "Family",    color: "var(--family)" },
    campus:    { label: "Campus",    color: "var(--campus)" },
    community: { label: "Community", color: "var(--community)" }
  };
  var WINDOWS = [["now", "Now"], ["today", "Today"], ["weekend", "Weekend"], ["week", "7 days"], ["all", "All"]];
  var AUDIENCES = [["", "Everyone", "sparkles"], ["singles", "Singles", "person"], ["couples", "Couples", "couples"], ["groups", "Groups", "people"], ["family", "Family", "family"]];

  // ---------- state ----------
  var store = {
    load: function (k, d) { try { var v = localStorage.getItem(k); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    save: function (k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) {} }
  };
  var state = {
    events: [], generatedAt: null, error: null,
    tab: "map", window: "today", categories: new Set(), audience: "", search: "",
    favorites: new Set(store.load("favorites", [])),
    profile: store.load("profile", { name: "", audience: "", interests: [] }),
    sounds: store.load("sounds", true),
    selected: null, visible: [], hotspots: []
  };
  if (state.profile.audience) state.audience = state.profile.audience;

  var $ = function (id) { return document.getElementById(id); };
  var el = function (tag, cls, html) { var e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
  var esc = function (s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); };
  function cap(s) { return s.charAt(0).toUpperCase() + s.slice(1); }

  // ---------- dates (mirrors TimeWindow.swift) ----------
  function parseDate(s) { return s ? new Date(s) : null; }
  function effectiveEnd(e) { return e._end || new Date(e._start.getTime() + (e.allDay ? 86400e3 : 3 * 3600e3)); }
  function isLive(e, now) { return e._start <= now && effectiveEnd(e) >= now; }
  function sameDay(a, b) { return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate(); }
  function startOfDay(d) { var x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
  function weekendBounds(now) {
    var today = startOfDay(now), wd = today.getDay();
    var sat = new Date(today); sat.setDate(sat.getDate() + (wd === 0 ? -1 : 6 - wd));
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
    var t = startOfDay(new Date()), tm = new Date(t); tm.setDate(tm.getDate() + 1);
    if (sameDay(d, t)) return "Today"; if (sameDay(d, tm)) return "Tomorrow"; return fmtLong.format(d);
  }
  function relative(d) {
    var m = Math.round((Date.now() - d.getTime()) / 60000);
    if (m < 2) return "just now"; if (m < 60) return m + " min. ago"; var h = Math.round(m / 60);
    if (h < 24) return h + " hr. ago"; return Math.round(h / 24) + " days ago";
  }

  // ---------- events ----------
  function kinds(e) { return (e.categories && e.categories.length ? e.categories : [e.category]).filter(function (c) { return CATS[c]; }); }
  function kind(e) { return kinds(e)[0] || "community"; }
  function color(e) { return CATS[kind(e)].color; }
  function matches(e, now, opts) {
    opts = opts || {};
    if (!inWindow(e, opts.window || state.window, now)) return false;
    var aud = "audience" in opts ? opts.audience : state.audience;
    if (aud && (e.audience || []).indexOf(aud) < 0) return false;
    var cats = opts.categories || state.categories;
    if (cats.size && !kinds(e).some(function (k) { return cats.has(k); })) return false;
    var q = "search" in opts ? opts.search : state.search;
    if (q && (e.title || "").toLowerCase().indexOf(q) < 0 && (e.venue || "").toLowerCase().indexOf(q) < 0) return false;
    return true;
  }
  function query(opts) {
    var now = new Date();
    return state.events.filter(function (e) { return matches(e, now, opts); }).sort(function (a, b) { return a._start - b._start; });
  }
  function favoriteEvents() { var now = new Date(); return state.events.filter(function (e) { return state.favorites.has(e.id) && effectiveEnd(e) >= now; }); }

  // ---------- sounds (same two sounds as the app, synthesised with WebAudio) ----------
  var audio;
  function playSound(name) {
    if (!state.sounds) return;
    try {
      audio = audio || new (window.AudioContext || window.webkitAudioContext)();
      if (audio.state === "suspended") audio.resume();
      var notes = name === "welcome"
        ? [[523.25, 0, .55, .8], [659.25, .16, .55, .8], [783.99, .32, .7, .85], [1046.5, .5, .95, .6]]
        : [[783.99, 0, .22, .9], [1046.5, .09, .3, .8]];
      var t0 = audio.currentTime;
      notes.forEach(function (n) {
        [1, 2, 3].forEach(function (h, i) {
          var o = audio.createOscillator(), g = audio.createGain();
          o.type = "sine"; o.frequency.value = n[0] * h;
          var peak = n[3] * [0.22, 0.055, 0.018][i];
          g.gain.setValueAtTime(0, t0 + n[1]);
          g.gain.linearRampToValueAtTime(peak, t0 + n[1] + 0.012);
          g.gain.exponentialRampToValueAtTime(0.0005, t0 + n[1] + n[2]);
          o.connect(g); g.connect(audio.destination);
          o.start(t0 + n[1]); o.stop(t0 + n[1] + n[2] + 0.05);
        });
      });
    } catch (e) {}
  }

  // ---------- shared pieces ----------
  function thumb(e, cls) {
    var t = el("div", "thumb " + (cls || ""));
    t.style.setProperty("--c", color(e));
    if (e.imageUrl) { var img = el("img"); img.loading = "lazy"; img.alt = ""; img.src = e.imageUrl; img.onerror = function () { img.remove(); t.innerHTML = ic(kind(e)); }; t.appendChild(img); }
    else t.innerHTML = ic(kind(e));
    return t;
  }
  function heartBtn(e, cls) {
    var on = state.favorites.has(e.id);
    var b = el("button", "heart " + (cls || "") + (on ? " on" : ""), ic(on ? "heart" : "heartO"));
    b.type = "button"; b.title = on ? "Remove from saved" : "Save";
    b.onclick = function (ev) { ev.stopPropagation(); toggleFav(e); b.classList.add("pop"); };
    return b;
  }
  function pills(e, now, extra) {
    var h = '<span class="pill">' + esc(timeText(e)) + "</span>";
    if (isLive(e, now)) h += '<span class="pill live"><i></i>LIVE</span>';
    if (e.price && extra) h += '<span class="pill soft">' + esc(e.price) + "</span>";
    return h;
  }
  function attPill(e) {
    var c = window.Cloud ? Cloud.count(e.id) : { going: 0, here: 0 };
    if (!c.going && !c.here) return "";
    return '<span class="pill count' + (c.here ? " here" : "") + '">' + ic(c.here ? "here" : "thumb") + (c.going + c.here) + "</span>";
  }
  function bigCard(e, now) {
    var k = kind(e);
    var c = el("button", "big"); c.type = "button";
    c.style.setProperty("--c", CATS[k].color);
    if (e.imageUrl) { var img = el("img"); img.loading = "lazy"; img.alt = ""; img.src = e.imageUrl; img.onerror = function () { img.remove(); }; c.appendChild(img); }
    else c.appendChild(el("div", "sym", ic(k)));
    var inner = el("div", "in");
    var top = el("div", "top", pills(e, now, true) + attPill(e) + '<span class="sp"></span>');
    top.appendChild(heartBtn(e));
    inner.appendChild(top);
    var bottom = el("div", "", '<span class="pill cat">' + ic(k) + " " + CATS[k].label + "</span><h3>" + esc(e.title) + "</h3>" +
      ((e.venue || e.address) ? '<div class="where">' + ic("pin") + esc(e.venue || e.address) + "</div>" : ""));
    inner.appendChild(bottom);
    c.appendChild(inner);
    c.onclick = function () { openDetail(e); };
    return c;
  }
  function miniCard(e, now) {
    var c = el("button", "mini glass"); c.type = "button";
    c.appendChild(thumb(e));
    c.appendChild(el("div", "t", '<div class="meta">' + pills(e, now) + "</div><h4>" + esc(e.title) + "</h4>" + (e.venue ? '<div class="v">' + esc(e.venue) + "</div>" : "")));
    c.onclick = function () { focusOn(e); };
    return c;
  }
  function row(e, now) {
    var r = el("button", "row-ev"); r.type = "button";
    r.appendChild(thumb(e));
    r.appendChild(el("div", "t", '<div class="meta">' + pills(e, now, true) + "</div><h4>" + esc(e.title) + "</h4>" + ((e.venue || e.address) ? '<div class="v">' + esc(e.venue || e.address) + "</div>" : "")));
    r.appendChild(heartBtn(e, "dark"));
    r.onclick = function () { openDetail(e); };
    return r;
  }
  function cardList(container, events, emptyText) {
    container.innerHTML = "";
    if (!events.length) { container.appendChild(el("div", "empty", ic("sparkles") + emptyText)); return; }
    var now = new Date(), last = null, frag = document.createDocumentFragment();
    events.slice(0, 300).forEach(function (e) {
      var d = startOfDay(e._start).getTime();
      if (d !== last) { last = d; frag.appendChild(el("div", "day glass", dayHeader(e._start))); }
      frag.appendChild(bigCard(e, now));
    });
    if (events.length > 300) frag.appendChild(el("p", "feed-note", "Showing the first 300. Narrow the filters to see the rest."));
    container.appendChild(frag);
  }

  // ---------- controls ----------
  function segButtons(container, items, current, onPick, withIcon) {
    container.innerHTML = "";
    items.forEach(function (p) {
      var b = el("button", p[0] === current ? "on" : "", (withIcon && p[2] ? ic(p[2]) : "") + "<span>" + p[1] + "</span>");
      b.type = "button"; b.onclick = function () { onPick(p[0]); };
      container.appendChild(b);
    });
  }
  function chipRow(container, legend) {
    container.innerHTML = "";
    Object.keys(CATS).forEach(function (k) {
      var on = state.categories.has(k);
      var b = el("button", "chip glass" + (on ? " on" : "") + (state.categories.size && !on ? " dim" : ""), '<span class="dot">' + ic(k) + "</span>" + CATS[k].label);
      b.type = "button"; b.style.setProperty("--c", CATS[k].color);
      b.onclick = function () { if (on) state.categories.delete(k); else state.categories.add(k); renderControls(); recompute(); };
      container.appendChild(b);
    });
  }
  function renderControls() {
    segButtons($("audiences"), AUDIENCES, state.audience, function (a) { state.audience = a; renderControls(); recompute(); }, true);
    segButtons($("audiences2"), AUDIENCES, state.audience, function (a) { state.audience = a; renderControls(); recompute(); }, true);
    segButtons($("windows"), WINDOWS, state.window, function (w) { state.window = w; renderControls(); recompute(); });
    chipRow($("categories")); chipRow($("categories2"));
  }

  // ---------- map ----------
  var map, markers = [], meMarker;
  function initMap() {
    window.__como = state;
    map = new maplibregl.Map({ container: "map", style: STYLE, center: CENTER, zoom: 13.4, pitch: 45, bearing: -8, attributionControl: { compact: true }, maxPitch: 65 });
    map.addControl(new maplibregl.NavigationControl({ showCompass: true, visualizePitch: true }), "bottom-right");
    var geo = new maplibregl.GeolocateControl({ positionOptions: { enableHighAccuracy: false }, trackUserLocation: false, showUserLocation: true });
    map.addControl(geo, "bottom-right");
    map.on("load", function () {
      map.on("zoomend", renderMarkers);
      renderMarkers();
    });
  }
  function cellDegrees() {
    // The app grows the grid cell as the camera pulls back; zoom 13.4 ≈ the app's default distance.
    var z = map ? map.getZoom() : 13.4;
    return Math.max(0.0015, 0.0015 * Math.pow(2, 15.3 - z));
  }
  function buildHotspots(list) {
    var cell = cellDegrees(), buckets = {};
    list.forEach(function (e) {
      if (e.lat == null || e.lng == null) return;
      var key = Math.round(e.lat / cell) + "_" + Math.round(e.lng / cell);
      (buckets[key] = buckets[key] || []).push(e);
    });
    return Object.keys(buckets).map(function (key) {
      var evs = buckets[key].sort(function (a, b) { return a._start - b._start; }), lat = 0, lng = 0, counts = {};
      evs.forEach(function (e) { lat += e.lat; lng += e.lng; counts[kind(e)] = (counts[kind(e)] || 0) + 1; });
      var dom = Object.keys(counts).sort(function (a, b) { return counts[b] - counts[a]; })[0];
      var title = evs[0].venue || evs[0].address || (evs.length + " events");
      return { id: key + "|" + evs.length + "|" + dom, lat: lat / evs.length, lng: lng / evs.length, events: evs, dominant: dom, title: title };
    }).sort(function (a, b) { return b.events.length - a.events.length; });
  }
  function renderMarkers() {
    if (!map) return;
    state.hotspots = buildHotspots(state.visible);
    markers.forEach(function (m) { m.remove(); }); markers = [];
    state.hotspots.forEach(function (h) {
      var n = h.events.length, size = Math.min(38 + n * 1.5, 56), c = CATS[h.dominant].color;
      var wrap = el("div", "pinwrap");
      wrap.style.setProperty("--c", c); wrap.style.setProperty("--s", size + "px");
      if (n >= 3) { var busy = el("div", "busy"); busy.style.setProperty("--h", Math.min(100 + n * 6, 170) + "px"); wrap.appendChild(busy); }
      wrap.appendChild(el("div", "halo"));
      var pin = el("div", "pin" + (state.selected && h.events.some(function (e) { return e.id === state.selected; }) ? " sel" : ""), ic(h.dominant) + (n > 1 ? "<b>" + (n > 99 ? "99+" : n) + "</b>" : ""));
      pin.title = h.title + (n > 1 ? " · " + n + " events" : "");
      pin.onclick = function (ev) { ev.stopPropagation(); if (n === 1) openDetail(h.events[0]); else openSheet(h); };
      wrap.appendChild(pin);
      if (window.Cloud && Cloud.friends.list.length) {
        var fa = Cloud.friendsAt(new Set(h.events.map(function (e) { return e.id; })));
        var all = fa.here.concat(fa.going);
        if (all.length) {
          var fb = el("div", "fbubbles");
          all.slice(0, 3).forEach(function (f, i) { fb.appendChild(el("span", i < fa.here.length ? "here" : "", esc((f.name || "?")[0].toUpperCase()))); });
          if (all.length > 3) fb.appendChild(el("span", "", "+" + (all.length - 3)));
          wrap.appendChild(fb);
        }
      }
      var m = new maplibregl.Marker({ element: wrap, anchor: "center" }).setLngLat([h.lng, h.lat]).addTo(map);
      markers.push(m);
    });
  }
  function focusOn(e) {
    state.selected = e.id;
    if (e.lat != null && e.lng != null) {
      showTab("map");
      map.flyTo({ center: [e.lng, e.lat], zoom: Math.max(map.getZoom(), 16), pitch: 45, duration: 700 });
      map.once("moveend", function () {
        renderMarkers();
        var h = state.hotspots.find(function (x) { return x.events.some(function (y) { return y.id === e.id; }); });
        if (h) { if (h.events.length === 1) openDetail(e); else openSheet(h); }
      });
    } else openDetail(e);
  }

  // ---------- map overlays ----------
  function renderMapOverlays() {
    var n = state.visible.length;
    $("count-n").textContent = n + (n === 1 ? " event" : " events");
    $("count-upd").textContent = (state.generatedAt ? " · Updated " + relative(state.generatedAt) : "") + (window.Cloud && Cloud.users && Cloud.users.total ? " · " + Cloud.users.total.toLocaleString() + " using" : "");
    $("all-n").textContent = "All " + n;
    $("nextup-label").textContent = state.window === "now" ? "Happening now" : "Next up";
    var now = new Date();
    var next = state.visible.slice().sort(function (a, b) {
      var la = isLive(a, now), lb = isLive(b, now);
      if (la !== lb) return la ? -1 : 1;
      return a._start - b._start;
    }).slice(0, 12);
    var strip = $("nextup"); strip.innerHTML = "";
    next.forEach(function (e) { strip.appendChild(miniCard(e, now)); });
    $("nextup-label").parentElement.parentElement.style.display = next.length ? "" : "none";
  }

  // ---------- pages ----------
  function renderUpcoming() {
    var list = query({ window: "all" });
    cardList($("upcoming-list"), list, "Nothing matches. Try another filter.");
    var fy = $("foryou"); fy.innerHTML = "";
    var interests = new Set((state.profile.interests || []).filter(function (c) { return CATS[c]; }));
    if (interests.size && !state.search && !state.categories.size) {
      var picks = query({ window: "week", categories: interests }).slice(0, 10);
      if (picks.length) {
        var box = el("div", "foryou", "<h3>" + ic("sparkles") + "For you <small>· from your interests</small></h3>");
        var strip = el("div", "strip"); var now = new Date();
        picks.forEach(function (e) { var m = miniCard(e, now); m.onclick = function () { openDetail(e); }; strip.appendChild(m); });
        box.appendChild(strip); fy.appendChild(box);
      }
    }
    var note = $("feed-note"); note.hidden = !state.error; note.textContent = state.error || "";
  }
  function renderSaved() {
    var favs = favoriteEvents().sort(function (a, b) { return a._start - b._start; });
    cardList($("saved-list"), favs, "Tap the heart on any event and it lands here.");
    var badge = $("saved-badge"); badge.hidden = !favs.length; badge.textContent = favs.length;
  }
  function renderProfile() {
    var p = state.profile, box = $("profile"); box.innerHTML = "";
    var initials = (p.name || "").split(/\s+/).filter(Boolean).map(function (w) { return w[0].toUpperCase(); }).slice(0, 2).join("") || "☺";
    var ck = window.Cloud || {};
    var status = !ck.available ? "Profile saved in this browser" : ck.signedIn ? "Signed in with iCloud" : "Not signed in · profile saved in this browser only";
    var users = ck.users && ck.users.total ? '<div class="users">' + ic("people") + " " + ck.users.total.toLocaleString() + (ck.users.total === 1 ? " person uses" : " people use") + " CoMo Events</div>" : "";
    var head = el("div", "glass card pcard", '<div class="head"><div class="avatar">' + esc(initials) + "</div><div><b>" + esc(p.name || "Hey there") + "</b><small>" + status + "</small>" + users + "</div></div>");
    box.appendChild(head);
    if (ck.available) {
      var sc = el("div", "glass card pcard", ck.signedIn
        ? "<h3>iCloud</h3><p>Going, I'm here, friends and posting are on. Your name and saves stay in this browser; attendance and your friend code are public records, like in the iPhone app.</p><div id=\"ck-signout\"></div>"
        : "<h3>Keep your plans</h3><p>Sign in with your iCloud account to say you're going, see friends, and post events. No password is shared with us.</p><div id=\"ck-signin\"></div>");
      box.appendChild(sc);
      setTimeout(function () { try { if (window.CloudKit && CloudKit.getDefaultContainer) { var c = CloudKit.getDefaultContainer(); c.setUpAuth(); } } catch (e) {} }, 0);
    } else if (window.CK_TOKEN === "") {
      box.appendChild(el("div", "glass card pcard", "<h3>iCloud on the web</h3><p>Waiting for the CloudKit token. Until then Going, friends and posting live in the <a href=\"" + INSTALL + "\">iPhone app</a>.</p>"));
    }

    var about = el("div", "glass card pcard", "<h3>About you</h3>");
    var field = el("div", "glass capsule field"); var input = el("input"); input.placeholder = "Your name"; input.value = p.name || "";
    input.onchange = function () { p.name = input.value.trim(); store.save("profile", p); renderProfile(); };
    field.appendChild(input); about.appendChild(field);
    about.appendChild(el("p", "", "I'm usually out as…"));
    var aud = el("div", "flow");
    AUDIENCES.slice(1).forEach(function (a) {
      var on = p.audience === a[0];
      var b = el("button", "chip glass" + (on ? " on" : ""), ic(a[2]) + a[1]); b.type = "button";
      b.onclick = function () { p.audience = on ? "" : a[0]; state.audience = p.audience; store.save("profile", p); renderControls(); recompute(); renderProfile(); };
      aud.appendChild(b);
    });
    about.appendChild(aud); box.appendChild(about);

    var inter = el("div", "glass card pcard", "<h3>Interests</h3><p>Pick what you're into. Upcoming gets a \"For you\" row from these.</p>");
    var flow = el("div", "flow");
    Object.keys(CATS).forEach(function (k) {
      var on = (p.interests || []).indexOf(k) >= 0;
      var b = el("button", "chip glass" + (on ? " on" : ""), '<span class="dot">' + ic(k) + "</span>" + CATS[k].label); b.type = "button"; b.style.setProperty("--c", CATS[k].color);
      b.onclick = function () { p.interests = on ? p.interests.filter(function (x) { return x !== k; }) : (p.interests || []).concat([k]); store.save("profile", p); renderProfile(); renderUpcoming(); };
      flow.appendChild(b);
    });
    inter.appendChild(flow); box.appendChild(inter);

    var sounds = el("div", "glass card pcard", "<h3>Sounds</h3>");
    var tg = el("div", "toggle", "<div><b>Chimes</b><small>A soft chime when you open the app and when you save an event.</small></div>");
    var sw = el("button", "switch" + (state.sounds ? " on" : "")); sw.type = "button"; sw.setAttribute("aria-label", "Sounds");
    sw.onclick = function () { state.sounds = !state.sounds; store.save("sounds", state.sounds); sw.classList.toggle("on", state.sounds); if (state.sounds) playSound("favorite"); };
    tg.appendChild(sw); sounds.appendChild(tg); box.appendChild(sounds);

    var comm = el("div", "glass card pcard", "<h3>Community</h3>");
    var post = el("button", "ylink", ic("plus") + "Post an event"); post.type = "button"; post.onclick = openPost; comm.appendChild(post);
    comm.appendChild(el("p", "", "Student orgs, venues, anyone: post a public event and it appears on the map after a quick check."));
    if (window.Cloud && Cloud.community.mine && Cloud.community.mine.length) {
      comm.appendChild(el("p", "mine", "Your posts: " + Cloud.community.mine.map(function (e) { return "<b>" + esc(e.title) + "</b> · " + (e.decision === true ? "live" : e.decision === false ? "declined" : "waiting for a moderator"); }).join(" · ")));
    }
    box.appendChild(comm);

    var favs = favoriteEvents().length;
    box.appendChild(el("div", "glass card pcard savedrow", ic("heart") + "<span>" + favs + " saved event" + (favs === 1 ? "" : "s") + " coming up</span>" + ic("phoneDev")));

    var help = el("div", "glass card pcard", "<h3>Help &amp; contact</h3>" +
      '<a class="plink" href="mailto:xenificity@icloud.com?subject=CoMo%20Events%20feedback&body=What%20I%20liked%3A%0A%0AWhat%20was%20confusing%20or%20broken%3A%0A%0AEvents%20or%20places%20missing%3A%0A">' + ic("mail") + "Send feedback</a>" +
      '<a class="plink" href="https://apps.apple.com/app/id6824363992?action=write-review" target="_blank" rel="noopener">' + ic("star") + "Rate CoMo Events on the App Store</a>" +
      '<a class="plink" href="guidelines.html">' + ic("shield") + "Community guidelines</a>" +
      '<a class="plink" href="privacy.html">' + ic("lock") + "Privacy policy</a>" +
      '<a class="plink" href="' + INSTALL + '">' + ic("phoneDev") + "Get the iPhone app</a>" +
      '<a class="plink" href="about/">' + ic("sparkles") + "About CoMo Events</a>" +
      '<p style="margin:8px 0 0;font-size:12px">Reminders, friends, attendance and posting live in the iPhone app. This web version shows the same events and keeps your saves in this browser.</p>');
    box.appendChild(help);
    if (ck.userRecordName) box.appendChild(el("div", "glass card pcard", "<small style=\"font-weight:700;color:var(--muted)\">Your CoMo ID</small><div class=\"mono\">" + esc(ck.userRecordName) + "</div>"));
  }

  // ---------- friends (mirrors FriendsScreen) ----------
  function renderFriends() {
    var box = $("friends"); box.innerHTML = "";
    var ck = window.Cloud;
    if (!ck || !ck.available) {
      box.appendChild(el("div", "glass card pcard", "<h3>Go together</h3><p>Friends needs iCloud on the web, which is waiting for its CloudKit token. In the meantime the <a href=\"" + INSTALL + "\">iPhone app</a> has it.</p>"));
      return;
    }
    if (!ck.friends.enabled) {
      var intro = el("div", "glass card pcard", "<h3>" + ic("people") + " Go together</h3><p>Turn on Friends to get a 6-letter code. Swap codes with people, and you'll see which saved events you have in common and who's going where. Sharing your own saved events is a separate switch, off by default.</p>");
      var b = el("button", "ylink", ic("sparkles") + (ck.signedIn ? "Turn on Friends" : "Sign in with iCloud first")); b.type = "button";
      b.onclick = function () { if (!ck.signedIn) { showTab("profile"); return; } ck.enableFriends().then(function (msg) { if (msg) toast(msg); renderFriends(); }); };
      intro.appendChild(b);
      intro.appendChild(el("p", "", "<small>Uses your iCloud account. Nothing else is shared.</small>"));
      box.appendChild(intro); return;
    }
    var my = el("div", "glass card pcard", "<h3>Your code</h3><div class=\"code\">" + esc(ck.friends.myCode || "······") + "</div>");
    var acts = el("div", "addrow");
    var sh = el("button", "ybtn", ic("share") + " Invite"); sh.type = "button"; sh.onclick = function () {
      var text = "I use CoMo Events to see everything happening in Columbia on one map. My friend code is " + ck.friends.myCode + ". Get it: " + siteRoot() + "get/?c=invite";
      if (navigator.share) navigator.share({ text: text }).catch(function () {}); else if (navigator.clipboard) navigator.clipboard.writeText(text).then(function () { toast("Invite text copied"); });
    };
    var cp = el("button", "ybtn", "Copy code"); cp.type = "button"; cp.onclick = function () { if (navigator.clipboard) navigator.clipboard.writeText(ck.friends.myCode).then(function () { toast("Code copied"); }); };
    acts.appendChild(sh); acts.appendChild(cp); my.appendChild(acts);
    var tg = el("div", "toggle", "<div><b>Share my saved events with friends</b><small>Friends who have your code see what you've hearted and where you're going.</small></div>");
    var sw = el("button", "switch" + (ck.friends.share ? " on" : "")); sw.type = "button"; sw.onclick = function () { ck.setShare(!ck.friends.share); sw.classList.toggle("on", ck.friends.share); };
    tg.appendChild(sw); my.appendChild(tg); box.appendChild(my);
    var add = el("div", "glass card pcard", "<h3>Add a friend</h3>");
    var row = el("div", "addrow"); var fld = el("div", "glass capsule field"); var inp = el("input"); inp.placeholder = "Friend's code"; inp.maxLength = 6; fld.appendChild(inp);
    var go = el("button", "ybtn", "Add"); go.type = "button"; go.onclick = function () { go.disabled = true; ck.addFriend(inp.value).then(function (msg) { go.disabled = false; if (msg) toast(msg); else { inp.value = ""; toast("Friend added"); } renderFriends(); }); };
    row.appendChild(fld); row.appendChild(go); add.appendChild(row); box.appendChild(add);
    if (!ck.friends.list.length) { box.appendChild(el("div", "empty", ic("people") + "No friends yet. Add someone's code above.")); return; }
    var now = new Date();
    ck.friends.list.forEach(function (f) {
      var going = state.events.filter(function (e) { return (f.favorites.indexOf(e.id) >= 0 || f.going.indexOf(e.id) >= 0) && effectiveEnd(e) >= now; }).sort(function (a, b) { return a._start - b._start; });
      var card = el("div", "glass card pcard");
      var head = el("div", "friend", '<div class="av">' + esc((f.name || "?")[0].toUpperCase()) + '</div><div class="t"><b>' + esc(f.name) + "</b><small>" + (f.sharing ? going.length + " upcoming saved" : "Not sharing saves") + "</small></div>");
      var ac = el("div", "acts");
      var rm = el("button", "glass", "Remove"); rm.type = "button"; rm.onclick = function () { ck.removeFriend(f.id); renderFriends(); };
      var bk = el("button", "glass danger", "Block"); bk.type = "button"; bk.onclick = function () { if (confirm("Block " + f.name + "?")) { ck.blockFriend(f.id); ck.report(f, "friend profile: blocked by a user"); renderFriends(); } };
      ac.appendChild(rm); ac.appendChild(bk); head.appendChild(ac); card.appendChild(head);
      going.slice(0, 5).forEach(function (e) { card.appendChild(row(e, now)); });
      box.appendChild(card);
    });
  }

  // ---------- post an event (mirrors SubmitEventView) ----------
  function openPost() {
    if (!window.Cloud || !Cloud.available) { location.href = INSTALL; return; }
    if (!Cloud.signedIn) { toast("Sign in with iCloud in the Profile tab to post."); showTab("profile"); return; }
    var f = $("post-form");
    if (!f.category.options.length) {
      Object.keys(CATS).forEach(function (k) { var o = el("option", "", CATS[k].label); o.value = k; if (k === "community") o.selected = true; f.category.appendChild(o); });
      var extra = $("post-extra"); Object.keys(CATS).forEach(function (k) {
        var b = el("button", "chip glass", '<span class="dot">' + ic(k) + "</span>" + CATS[k].label); b.type = "button"; b.style.setProperty("--c", CATS[k].color); b.dataset.cat = k;
        b.onclick = function () { b.classList.toggle("on"); }; extra.appendChild(b);
      });
    }
    var d = new Date(Date.now() + 86400e3); d.setMinutes(Math.ceil(d.getMinutes() / 30) * 30, 0, 0);
    f.start.value = new Date(d.getTime() - d.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
    f.submitterName.value = f.submitterName.value || state.profile.name || "";
    $("post-err").hidden = true;
    $("post").hidden = false; $("post").scrollTop = 0;
  }
  function closePost() { $("post").hidden = true; }
  function submitPost(ev) {
    track("click/post-event");
    ev.preventDefault();
    var f = $("post-form"), btn = $("post-send");
    var d = {
      title: f.title.value, category: f.category.value, extra: [...$("post-extra").querySelectorAll(".chip.on")].map(function (b) { return b.dataset.cat; }),
      start: f.start.value ? new Date(f.start.value) : null, end: f.hasEnd.checked && f.end.value ? new Date(f.end.value) : null,
      venue: f.venue.value.trim(), address: f.address.value.trim(), price: f.price.value.trim(), link: f.link.value.trim(), details: f.details.value.trim(),
      submitterName: f.submitterName.value.trim(), agreed: f.agreed.checked
    };
    if (!d.start) { showPostError("Pick a start time."); return; }
    btn.disabled = true; btn.textContent = "Posting…";
    Cloud.submit(d).then(function (msg) {
      btn.disabled = false; btn.innerHTML = "Post";
      if (msg) { showPostError(msg); return; }
      closePost(); f.reset(); $("post-extra").querySelectorAll(".chip.on").forEach(function (b) { b.classList.remove("on"); });
      toast("Posted. A moderator will check it, usually within a day.");
      if (state.tab === "profile") renderProfile();
    });
  }
  function showPostError(msg) { var e = $("post-err"); e.textContent = msg; e.hidden = false; e.scrollIntoView({ block: "center", behavior: "smooth" }); }

  // ---------- venue sheet ----------
  function openSheet(h) {
    $("sheet-title").textContent = h.title;
    var rows = $("sheet-rows"); rows.innerHTML = "";
    var now = new Date(), last = null;
    h.events.forEach(function (e) {
      var d = startOfDay(e._start).getTime();
      if (d !== last) { last = d; rows.appendChild(el("div", "rowh", dayHeader(e._start))); }
      rows.appendChild(row(e, now));
    });
    $("sheet").hidden = false;
  }
  function closeSheet() { $("sheet").hidden = true; }

  // ---------- detail ----------
  var miniMap;
  function openDetail(e) {
    state.selected = e.id;
    track("event/" + e.id, e.title + (e.venue ? " · " + e.venue : ""));
    history.replaceState(null, "", "?e=" + encodeURIComponent(e.id));
    var d = $("detail"), k = kind(e), now = new Date();
    d.innerHTML = ""; d.style.setProperty("--c", CATS[k].color);
    d.appendChild(el("div", "bg"));
    var inner = el("div", "inner");

    var hero = el("div", "hero");
    if (e.imageUrl) { var img = el("img"); img.alt = ""; img.src = e.imageUrl; img.onerror = function () { img.remove(); hero.insertBefore(el("div", "sym", ic(k)), hero.firstChild); }; hero.appendChild(img); }
    else hero.appendChild(el("div", "sym", ic(k)));
    var cats = kinds(e).map(function (c, i) { return '<span class="pill' + (i ? " alt" : "") + '">' + ic(c) + " " + CATS[c].label + "</span>"; }).join("");
    if (isLive(e, now)) cats += '<span class="pill live"><i></i>LIVE</span>';
    hero.appendChild(el("div", "in", '<div class="cats">' + cats + "</div><h2>" + esc(e.title) + "</h2>" + (e.organizer ? '<div class="org">' + esc(e.organizer) + "</div>" : "")));
    var nav = el("div", "nav");
    var back = el("button", "glass circle", ic("back")); back.type = "button"; back.title = "Back"; back.onclick = closeDetail;
    var more = el("button", "glass circle", ic("more")); more.type = "button"; more.title = "More";
    more.onclick = function (ev) { ev.stopPropagation(); toggleMenu(e, hero); };
    nav.appendChild(back); nav.appendChild(more); hero.appendChild(nav);
    inner.appendChild(hero);

    var body = el("div", "body");
    var facts = el("div", "glass card facts");
    facts.innerHTML = "<div>" + ic("clock") + "<span>" + esc(whenText(e)) + "</span></div>" +
      ((e.venue || e.address) ? "<div>" + ic("pin") + "<span>" + esc([e.venue, e.address].filter(Boolean).join(" · ")) + "</span></div>" : "") +
      (e.price ? "<div>" + ic("tag") + "<span>" + esc(e.price) + "</span></div>" : "") +
      (e.phone ? "<div>" + ic("phone") + '<a href="tel:' + esc(e.phone.replace(/[^\d+]/g, "")) + '">' + esc(e.phone) + "</a></div>" : "");
    body.appendChild(facts);

    var att = el("div", "glass card att"); body.appendChild(att); renderAttendance(att, e);
    var going = window.Cloud ? Cloud.friendsGoing(e.id) : [];
    if (going.length) body.appendChild(el("div", "glass card going-card", ic("people") + "<span>" + esc(going.map(function (f) { return f.name; }).join(", ")) + (going.length === 1 ? " is going" : " are going") + "</span>"));

    if (e.lat != null && e.lng != null) {
      var mm = el("div", "minimap"); mm.onclick = function () { window.open(directionsURL(e), "_blank", "noopener"); };
      body.appendChild(mm);
      // Built after the panel is visible, so the container has a size.
      requestAnimationFrame(function () { setTimeout(function () {
        try {
          if (miniMap) { miniMap.remove(); miniMap = null; }
          miniMap = new maplibregl.Map({ container: mm, style: STYLE, center: [e.lng, e.lat], zoom: 15.2, pitch: 30, interactive: false, attributionControl: false });
          miniMap.on("load", function () { miniMap.resize(); });
          var pw = el("div", "pinwrap"); pw.style.setProperty("--c", CATS[k].color); pw.style.setProperty("--s", "36px"); pw.appendChild(el("div", "pin", ic(k)));
          new maplibregl.Marker({ element: pw, anchor: "center" }).setLngLat([e.lng, e.lat]).addTo(miniMap);
          window.__comoMini = miniMap;
        } catch (err) {}
      }, 80); });
    }
    if (e.description) body.appendChild(el("div", "glass card desc", esc(e.description)));
    if (e.audience && e.audience.length) {
      body.appendChild(el("div", "good", "Good for " + e.audience.map(function (a) { var A = AUDIENCES.find(function (x) { return x[0] === a; }); return '<span class="pill soft glass">' + (A ? ic(A[2]) : "") + cap(a) + "</span>"; }).join("")));
    }
    body.appendChild(el("div", "src", "Source: " + esc(e.sourceName || e.source) + (e.alsoOn && e.alsoOn.length ? " · Also listed on " + e.alsoOn.length + " other site" + (e.alsoOn.length === 1 ? "" : "s") : "")));
    body.appendChild(el("div", "openapp", "On an iPhone? <a href=\"comoevents://event/" + encodeURIComponent(e.id) + "\">Open in the CoMo Events app</a> for reminders, friends and attendance, or <a href=\"" + INSTALL + "\">get the app</a>."));
    inner.appendChild(body);

    var bar = el("div", "actionbar glass");
    var link = e.ticketUrl || e.url;
    if (link) { var a = el("a", "primary", ic("arrow") + (e.ticketUrl ? "Tickets / Register" : "More info")); a.href = link; a.target = "_blank"; a.rel = "noopener"; a.addEventListener("click", function () { track(e.ticketUrl ? "click/tickets" : "click/more-info"); }); bar.appendChild(a); }
    bar.appendChild(roundBtn("share", "Share", function () { shareEvent(e); }));
    bar.appendChild(roundBtn("calendar", "Add to calendar", function () { downloadICS(e); }));
    if (e.phone) { var ph = roundBtn("phone", "Call", function () { location.href = "tel:" + e.phone.replace(/[^\d+]/g, ""); }); bar.appendChild(ph); }
    if (e.lat != null || e.address) bar.appendChild(roundBtn("car", "Directions", function () { track("click/directions"); window.open(directionsURL(e), "_blank", "noopener"); }));
    bar.appendChild(heartBtn(e, "dark glass circle"));
    inner.appendChild(bar);

    d.appendChild(inner);
    d.hidden = false; d.scrollTop = 0;
  }
  /// Going / I'm here / Went with everyone's counts (mirrors attendanceCard in EventDetailView).
  function renderAttendance(att, e) {
    var now = new Date(), started = e._start <= new Date(now.getTime() + 2 * 3600e3), over = effectiveEnd(e) < now;
    var c = window.Cloud ? Cloud.count(e.id) : { going: 0, here: 0, went: 0 }, mine = window.Cloud ? Cloud.status(e.id) : null;
    att.innerHTML = '<div class="counts"><span>' + ic("thumb") + " " + c.going + " going</span>" + (c.here ? '<span class="g">' + ic("here") + " " + c.here + " here now</span>" : "") + (c.went ? "<span>" + ic("check") + " " + c.went + " went</span>" : "") + "</div>";
    var btns = el("div", "btns");
    [["going", "Going", "thumb", !over], ["here", "I'm here", "here", started && !over], ["went", "Went", "check", started]].forEach(function (st) {
      if (!st[3]) return;
      var b = el("button", "glass" + (mine === st[0] ? " on " + st[0] : ""), ic(st[2]) + st[1]); b.type = "button";
      b.onclick = function () {
        if (!window.Cloud || !Cloud.available) { toast("Going and I'm here need iCloud: add the token or use the iPhone app."); return; }
        if (mine !== st[0]) track("click/" + st[0]);
        Cloud.setStatus(e, mine === st[0] ? null : st[0]).then(function (msg) { if (msg) toast(msg); });
        renderAttendance(att, e);
      };
      btns.appendChild(b);
    });
    att.appendChild(btns);
    var here = window.Cloud ? Cloud.friendsHere(e.id) : [];
    if (here.length) att.appendChild(el("small", "", ic("people") + " " + esc(here.map(function (f) { return f.name; }).join(", ")) + (here.length === 1 ? " is" : " are") + " here now"));
    if (!window.Cloud || !Cloud.available) att.appendChild(el("small", "", "Counts sync through iCloud; the web app is waiting for its CloudKit token. The <a href=\"" + INSTALL + "\">iPhone app</a> has it all."));
    else if (!Cloud.signedIn) att.appendChild(el("small", "", "Kept in this browser. <a href=\"#\" data-tab-link=\"profile\">Sign in with iCloud</a> to count for everyone and show friends."));
    var link = att.querySelector("[data-tab-link]"); if (link) link.onclick = function (ev) { ev.preventDefault(); closeDetail(); showTab("profile"); };
  }
  function roundBtn(icon, title, fn) { var b = el("button", "glass circle", ic(icon)); b.type = "button"; b.title = title; b.onclick = fn; return b; }
  function toggleMenu(e, hero) {
    var old = hero.querySelector(".menu"); if (old) { old.remove(); return; }
    var m = el("div", "menu glass");
    var s = el("button", "", ic("share") + "Share"); s.onclick = function () { m.remove(); shareEvent(e); }; m.appendChild(s);
    var c = el("button", "", ic("calendar") + "Add to Calendar"); c.onclick = function () { m.remove(); downloadICS(e); }; m.appendChild(c);
    if (e.source === "community" && window.Cloud && Cloud.available) {
      var rp = el("button", "danger", ic("flag") + "Report this post"); rp.onclick = function () {
        m.remove();
        var reason = prompt("Why? (Spam or scam, Wrong or misleading, Inappropriate, Not an event)", "Spam or scam"); if (!reason) return;
        Cloud.report(e, reason).then(function (msg) { toast(msg || "Thanks. A moderator will take a look."); });
      }; m.appendChild(rp);
      if (e.submitterID) { var bl = el("button", "danger", ic("flag") + "Block this poster"); bl.onclick = function () { m.remove(); if (confirm("Block and hide their posts? A report is also sent to the moderator.")) { Cloud.block(e.submitterID); Cloud.report(e, "Blocked by a user"); closeDetail(); mergeEvents(); } }; m.appendChild(bl); }
    } else {
      var r = el("a", "danger", ic("flag") + "Report a problem"); r.href = "mailto:xenificity@icloud.com?subject=" + encodeURIComponent("CoMo Events: problem with \"" + e.title + "\"") + "&body=" + encodeURIComponent("Event id: " + e.id + "\nWhat is wrong:\n"); m.appendChild(r);
    }
    hero.appendChild(m);
    setTimeout(function () { document.addEventListener("click", function h() { m.remove(); document.removeEventListener("click", h); }); }, 0);
  }
  function closeDetail() {
    $("detail").hidden = true; state.selected = null;
    if (miniMap) { miniMap.remove(); miniMap = null; }
    history.replaceState(null, "", location.pathname + (state.tab !== "map" ? "?tab=" + state.tab : ""));
    renderMarkers();
  }
  function directionsURL(e) {
    if (e.lat != null) return "https://maps.apple.com/?daddr=" + e.lat + "," + e.lng + "&q=" + encodeURIComponent(e.venue || e.title);
    return "https://maps.apple.com/?daddr=" + encodeURIComponent(e.address + ", Columbia, MO");
  }

  // ---------- actions ----------
  function toggleFav(e) {
    if (state.favorites.has(e.id)) state.favorites.delete(e.id); else { state.favorites.add(e.id); playSound("favorite"); track("click/save"); }
    store.save("favorites", Array.from(state.favorites));
    syncFriendProfile();
    renderUpcoming(); renderSaved(); renderMapOverlays();
    if (!$("detail").hidden && state.selected === e.id) { var bar = $("detail").querySelector(".actionbar .heart"); if (bar) { var nb = heartBtn(e, "dark glass circle"); bar.replaceWith(nb); } }
    if (!$("sheet").hidden) { var h = state.hotspots.find(function (x) { return x.events.some(function (y) { return y.id === e.id; }); }); if (h) openSheet(h); }
  }
  function syncFriendProfile() {
    if (!window.Cloud) return;
    Cloud.profileForFriends = { name: state.profile.name || "", favorites: Array.from(state.favorites) };
    if (Cloud.friends.enabled) Cloud.publishFriend();
  }
  function pad(n) { return (n < 10 ? "0" : "") + n; }
  function icsDate(d) { return d.getUTCFullYear() + pad(d.getUTCMonth() + 1) + pad(d.getUTCDate()) + "T" + pad(d.getUTCHours()) + pad(d.getUTCMinutes()) + "00Z"; }
  function icsText(s) { return String(s || "").replace(/\\/g, "\\\\").replace(/\n/g, "\\n").replace(/[,;]/g, function (c) { return "\\" + c; }); }
  function downloadICS(e) {
    track("click/calendar");
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
    toast("Calendar file downloaded");
  }
  function shareEvent(e) {
    track("click/share");
    var url = location.origin + location.pathname + "?e=" + encodeURIComponent(e.id);
    var text = e.title + " · " + whenText(e) + (e.venue ? " · " + e.venue : "") + "\nFound on CoMo Events, free for iPhone: " + siteRoot() + "get/?c=share";
    if (navigator.share) navigator.share({ title: e.title, text: text, url: url }).catch(function () {});
    else if (navigator.clipboard) navigator.clipboard.writeText(text + "\n" + url).then(function () { toast("Link copied"); });
  }
  var toastTimer;
  function toast(msg) { var t = $("toast"); t.textContent = msg; t.hidden = false; clearTimeout(toastTimer); toastTimer = setTimeout(function () { t.hidden = true; }, 2600); }

  // ---------- tabs ----------
  function showTab(tab) {
    state.tab = tab;
    ["map", "upcoming", "saved", "friends", "profile"].forEach(function (t) { $("screen-" + t).hidden = t !== tab; });
    document.querySelectorAll("#tabbar button").forEach(function (b) { b.classList.toggle("on", b.dataset.tab === tab); });
    if (tab === "map" && map) setTimeout(function () { map.resize(); }, 50);
    if (tab === "upcoming") renderUpcoming();
    if (tab === "saved") renderSaved();
    if (tab === "profile") renderProfile();
    if (tab === "friends") renderFriends();
    if ($("detail").hidden) history.replaceState(null, "", location.pathname + (tab !== "map" ? "?tab=" + tab : ""));
  }

  // ---------- recompute everything that depends on the filters ----------
  function recompute() {
    state.visible = query();
    renderMapOverlays(); renderMarkers();
    if (state.tab === "upcoming") renderUpcoming();
    if (state.tab === "saved") renderSaved();
  }

  /// Feed events plus approved community posts, like EventStore.recombine().
  function mergeEvents(rerender) {
    var ids = new Set((state.feed || []).map(function (e) { return e.id; }));
    var extra = (window.Cloud ? Cloud.community.approved : []).filter(function (e) { return !ids.has(e.id); }).map(function (e) { e._start = parseDate(e.start) || new Date(0); e._end = parseDate(e.end); return e; });
    state.events = (state.feed || []).concat(extra).sort(function (a, b) { return a._start - b._start; });
    if (rerender !== false) { recompute(); renderSaved(); }
  }

  // ---------- load ----------
  function load(i) {
    i = i || 0;
    if (i >= FEED.length) { state.error = "Offline; showing the last saved events."; $("count-n").textContent = "Could not load events"; return; }
    fetch(FEED[i] + (FEED[i].indexOf("http") === 0 ? "" : "?t=" + Math.floor(Date.now() / 600000)), { cache: "no-cache" })
      .then(function (r) { if (!r.ok) throw new Error(r.status); return r.json(); })
      .then(function (feed) {
        state.generatedAt = parseDate(feed.generatedAt); state.error = null;
        state.feed = (feed.events || []).map(function (e) { e._start = parseDate(e.start) || new Date(0); e._end = parseDate(e.end); return e; });
        mergeEvents(false);
        var now = new Date();
        if (!state._windowPicked) { state._windowPicked = true; if (state.events.filter(function (e) { return inWindow(e, "today", now); }).length < 3) state.window = "week"; }
        renderControls(); recompute(); renderSaved();
        var params = new URLSearchParams(location.search);
        var want = params.get("e");
        if (want) { var e = state.events.find(function (x) { return x.id === want; }); if (e) openDetail(e); }
        if (params.get("tab") && !want) showTab(params.get("tab"));
      })
      .catch(function () { load(i + 1); });
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-ic]").forEach(function (n) { n.outerHTML = ic(n.dataset.ic); });
    initMap(); renderControls();
    document.querySelectorAll("#tabbar button").forEach(function (b) { b.onclick = function () { showTab(b.dataset.tab); }; });
    $("all-btn").onclick = function () { showTab("upcoming"); };
    $("sheet-close").onclick = closeSheet;
    $("sheet").addEventListener("click", function (ev) { if (ev.target === $("sheet")) closeSheet(); });
    $("refresh-btn").onclick = function () { load(); toast("Refreshing…"); };
    $("post-btn").onclick = openPost;
    $("post-close").onclick = closePost;
    $("post-form").addEventListener("submit", submitPost);
    $("post-form").hasEnd.addEventListener("change", function (ev) { $("post-end").hidden = !ev.target.checked; });
    // Smart fill: a venue name is enough; address, website and the pin come from the venue table or OpenStreetMap.
    var vt; $("post-form").venue.addEventListener("input", function (ev) {
      clearTimeout(vt); var q = ev.target.value.trim(); var hint = $("post-venue-hint");
      if (q.length < 3) { hint.hidden = true; return; }
      vt = setTimeout(function () {
        Cloud.lookupVenue(q).then(function (m) {
          if (!m || $("post-form").venue.value.trim() !== q) return;
          var f = $("post-form");
          if (!f.address.value && m.address) f.address.value = m.address;
          if (!f.link.value && m.website) f.link.value = m.website;
          hint.textContent = "Found " + m.name + (m.address ? " · " + m.address : "") + (m.phone ? " · " + m.phone : "") + (m.fromTable ? "" : " (OpenStreetMap)");
          hint.hidden = false;
        });
      }, 600);
    });
    var waited = 0; (function waitCK() {
      if (window.CloudKit || !window.CK_TOKEN || waited > 8000) { Cloud.setup(); return; }
      waited += 200; setTimeout(waitCK, 200);
    })();
    Cloud.on(function (what) {
      if (what === "community") mergeEvents();
      if (what === "attendance") { renderMapOverlays(); if (state.tab === "upcoming") renderUpcoming(); if (state.tab === "saved") renderSaved(); var a = $("detail").querySelector(".att"); if (a && state.selected) { var ev = state.events.find(function (x) { return x.id === state.selected; }); if (ev) renderAttendance(a, ev); } }
      if (what === "friends") { renderMarkers(); if (state.tab === "friends") renderFriends(); }
      if (what === "auth" || what === "ready") { syncFriendProfile(); if (state.tab === "profile") renderProfile(); if (state.tab === "friends") renderFriends(); }
      if (what === "users") { renderMapOverlays(); if (state.tab === "profile") renderProfile(); }
    });
    var t; $("search").addEventListener("input", function (ev) { clearTimeout(t); t = setTimeout(function () { state.search = ev.target.value.trim().toLowerCase(); recompute(); renderUpcoming(); }, 120); });
    document.addEventListener("keydown", function (ev) { if (ev.key === "Escape") { closeDetail(); closeSheet(); } });
    // Browsers only allow sound after the first tap or click.
    var welcomed = false;
    document.addEventListener("pointerdown", function () { if (!welcomed) { welcomed = true; playSound("welcome"); } }, { once: true });
    load();
    setInterval(function () { recompute(); }, 60000);
    setInterval(function () { load(); }, 30 * 60000);
  });
})();
