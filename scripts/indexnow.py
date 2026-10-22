#!/usr/bin/env python3
"""Tell Bing (and other IndexNow engines) which comoevent.com pages changed in the last commit.

  python3 scripts/indexnow.py            # pages changed by HEAD
  python3 scripts/indexnow.py --all      # every URL in the sitemap (first run)

The key file docs/<key>.txt proves we own the site. Google does not use IndexNow; it reads the sitemap.
"""
import json, os, re, subprocess, sys, urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEY = "749858bc16b81d49474444807b1f5192"
SITE = "https://comoevent.com"
SEASON_DIRS = ["halloween", "thanksgiving", "christmas", "new-years-eve", "valentines", "st-patricks", "fourth-of-july", "graduation"]   # build_event_pages.SEASONS

def changed_urls():
    try:
        names = subprocess.check_output(["git", "-C", ROOT, "diff", "--name-only", "--diff-filter=AM", "HEAD~1", "HEAD", "--", "docs"], text=True).split()
    except subprocess.CalledProcessError:
        return []
    urls = []
    for n in names:
        if not n.endswith(".html"):
            continue
        path = n[len("docs/"):]
        if path in ("404.html",) or path.startswith(("stats/", "app/", "get/", "embed/")):   # embed/ is the noindex venue widget
            continue
        path = path[: -len("index.html")] if path.endswith("index.html") else path
        urls.append(f"{SITE}/{path}")
    # New pages (holiday pages opening, weekend guides, venue pages) come through as added files above. A holiday page that
    # closed for the season is deleted: tell the engines too, so they drop it instead of waiting for a recrawl.
    try:
        gone = subprocess.check_output(["git", "-C", ROOT, "diff", "--name-only", "--diff-filter=D", "HEAD~1", "HEAD", "--"]
                                       + [f"docs/{d}/index.html" for d in SEASON_DIRS], text=True).split()
    except subprocess.CalledProcessError:
        gone = []
    urls += [f"{SITE}/{n[len('docs/'):-len('index.html')]}" for n in gone]
    return urls

def sitemap_urls():
    return re.findall(r"<loc>(.*?)</loc>", open(os.path.join(ROOT, "docs", "sitemap.xml")).read())

def main():
    urls = sitemap_urls() if "--all" in sys.argv else changed_urls()
    urls = sorted(set(urls))[:10000]
    if not urls:
        print("indexnow: nothing changed"); return
    body = json.dumps({"host": "comoevent.com", "key": KEY, "keyLocation": f"{SITE}/{KEY}.txt", "urlList": urls}).encode()
    req = urllib.request.Request("https://api.indexnow.org/indexnow", data=body, headers={"Content-Type": "application/json; charset=utf-8"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            print("indexnow:", r.status, len(urls), "urls")
    except Exception as e:   # never fail the feed job over this
        print("indexnow failed:", e)

if __name__ == "__main__":
    main()
