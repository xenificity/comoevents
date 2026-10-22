// Anonymous visit and click counting with GoatCounter (no cookies, no personal data).
// Pages call CE_track("click/directions") etc.; the public numbers are at comoevent.com/stats/.
(function () {
  var ENDPOINT = "https://comoevent.goatcounter.com/count";
  var campaign = new URLSearchParams(location.search).get("c");
  window.goatcounter = { no_onload: true, endpoint: ENDPOINT };
  var queue = [];
  function send(o) { if (window.goatcounter && window.goatcounter.count) window.goatcounter.count(o); else queue.push(o); }
  window.CE_track = function (path, title) { send({ path: path, title: title || path, event: true }); };
  // the page view itself; a ?c= campaign (QR code, flyer, Reddit...) is recorded as the referrer
  send({ path: location.pathname, title: document.title, referrer: campaign ? "campaign: " + campaign : document.referrer });
  var s = document.createElement("script");
  s.async = true; s.src = "https://gc.zgo.at/count.v4.js"; s.crossOrigin = "anonymous";
  s.integrity = "sha384-nRw6qfbWyJha9LhsOtSb2YJDyZdKvvCFh0fJYlkquSFjUxp9FVNugbfy8q1jdxI+";
  s.onload = function () { var q = queue; queue = []; q.forEach(send); };
  document.head.appendChild(s);
  // any link to the install page counts as "get the app"
  document.addEventListener("click", function (e) {
    var a = e.target.closest && e.target.closest("a[href]");
    if (a && /\/get\/(\?|$)|get\/\?c=/.test(a.getAttribute("href"))) window.CE_track("click/get-app");
  }, true);
})();
