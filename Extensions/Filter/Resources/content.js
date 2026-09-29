// Ma Filter: hides the bottomless parts of social sites and leaves the rest.
//
// Hiding is done with one injected stylesheet rather than by deleting nodes.
// These sites re-render constantly; CSS keeps applying to whatever they draw
// next, a removed node just comes back. Only redirects and the "Following"
// tab on X need script, and both run from a cheap URL poll because the sites
// are single-page apps that never reload.
(() => {
  "use strict";

  const DEFAULTS = {
    instagramReels: true,
    instagramExplore: false,
    youtubeShorts: true,
    youtubeHome: false,
    xTrends: true,
    xFollowingOnly: false,
    linkedinFeed: false,
    facebookReels: true,
    tiktok: true,
  };

  const host = location.hostname.replace(/^(www|m|mobile)\./, "");
  const site =
    host.endsWith("instagram.com") ? "instagram" :
    host.endsWith("youtube.com") ? "youtube" :
    host.endsWith("x.com") || host.endsWith("twitter.com") ? "x" :
    host.endsWith("linkedin.com") ? "linkedin" :
    host.endsWith("facebook.com") ? "facebook" :
    host.endsWith("tiktok.com") ? "tiktok" : null;
  if (!site) return;

  let settings = { ...DEFAULTS };
  const german = (navigator.language || "").toLowerCase().startsWith("de");
  const HIDE = "{display:none!important}";

  // ---------------------------------------------------------------- rules

  function cssFor(s, path) {
    const out = [];
    if (site === "instagram") {
      if (s.instagramReels) {
        out.push(`a[href="/reels/"],a[href^="/reels/"],a[href*="/reel/"],article:has(a[href*="/reel/"])${HIDE}`);
      }
      if (s.instagramExplore) out.push(`a[href="/explore/"],a[href^="/explore/"]${HIDE}`);
    }
    if (site === "youtube") {
      if (s.youtubeShorts) {
        out.push([
          "ytd-reel-shelf-renderer",
          "ytd-rich-shelf-renderer[is-shorts]",
          "ytd-rich-section-renderer:has(ytd-rich-shelf-renderer[is-shorts])",
          "ytd-guide-entry-renderer:has(a[title='Shorts'])",
          "ytd-mini-guide-entry-renderer[aria-label='Shorts']",
          "ytd-video-renderer:has(a[href^='/shorts/'])",
          "ytd-grid-video-renderer:has(a[href^='/shorts/'])",
          "ytm-reel-shelf-renderer",
          "ytm-shorts-lockup-view-model",
          "ytm-shorts-lockup-view-model-v2",
          "grid-shelf-view-model:has(ytm-shorts-lockup-view-model-v2)",
          "grid-shelf-view-model:has(ytm-shorts-lockup-view-model)",
          "ytm-rich-section-renderer:has(ytm-shorts-lockup-view-model-v2)",
          "ytm-pivot-bar-item-renderer:has(.pivot-shorts)",
          "ytm-video-with-context-renderer:has(a[href^='/shorts/'])",
          "yt-tab-shape[tab-title='Shorts']",
        ].join(",") + HIDE);
      }
      if (s.youtubeHome && (path === "/" || path === "")) {
        out.push("ytd-browse[page-subtype='home'] #contents,ytd-browse[page-subtype='home'] #header,ytm-browse ytm-rich-grid-renderer,ytm-browse .rich-grid-renderer-contents,ytm-browse ytm-section-list-renderer" + HIDE);
      }
    }
    if (site === "x") {
      if (s.xTrends) {
        out.push("[aria-label*='Trending'],[aria-label*='Trends'],[data-testid='sidebarColumn'] section,[data-testid='trend'],a[href='/explore'],a[href^='/explore/']" + HIDE);
      }
    }
    if (site === "linkedin") {
      if (s.linkedinFeed && path.startsWith("/feed")) {
        out.push(".scaffold-finite-scroll,.feed-shared-update-v2,[data-id^='urn:li:activity'],[data-finite-scroll-hotkey-context='FEED'],main .relative > .scaffold-finite-scroll__content" + HIDE);
      }
    }
    if (site === "facebook") {
      if (s.facebookReels) {
        out.push("a[href*='/reel/'],a[href^='/reels/'],a[href*='/watch/'],div[aria-label='Reels'],div[aria-label='Reels and short videos']" + HIDE);
      }
    }
    if (site === "tiktok" && s.tiktok) {
      out.push("html>body>*:not(#ma-calm)" + HIDE);
    }
    return out.join("\n");
  }

  function redirectFor(s, url) {
    const path = url.pathname;
    if (site === "instagram") {
      if (s.instagramReels && /^\/reels?\//.test(path)) return "/";
      if (s.instagramExplore && path.startsWith("/explore")) return "/";
    }
    if (site === "youtube" && s.youtubeShorts) {
      const m = path.match(/^\/shorts\/([\w-]{6,})/);
      if (m) return `/watch?v=${m[1]}`;
    }
    if (site === "x" && s.xTrends && path.startsWith("/explore")) return "/home";
    if (site === "facebook" && s.facebookReels && /^\/(reel|reels|watch)\b/.test(path)) return "/";
    return null;
  }

  function wantsCalm(s, path) {
    if (site === "tiktok") return s.tiktok;
    if (site === "youtube") return s.youtubeHome && (path === "/" || path === "");
    if (site === "linkedin") return s.linkedinFeed && path.startsWith("/feed");
    return false;
  }

  // ------------------------------------------------------------- applying

  let styleEl = null;
  function applyStyle() {
    const css = cssFor(settings, location.pathname);
    if (!styleEl) {
      styleEl = document.createElement("style");
      styleEl.id = "ma-filter";
    }
    if (styleEl.textContent !== css) styleEl.textContent = css;
    const parent = document.head || document.documentElement;
    if (parent && styleEl.parentNode !== parent) parent.appendChild(styleEl);
  }

  function applyCalm() {
    const want = wantsCalm(settings, location.pathname);
    let calm = document.getElementById("ma-calm");
    if (!want) {
      if (calm) calm.remove();
      return;
    }
    if (calm || !document.body) return;
    calm = document.createElement("div");
    calm.id = "ma-calm";
    calm.setAttribute("role", "note");
    calm.style.cssText = [
      "position:relative",
      "margin:24px auto",
      "max-width:420px",
      "padding:28px 24px",
      "border-radius:22px",
      "background:#F4EFE6",
      "color:#1F1D1B",
      "font:16px/1.5 -apple-system,system-ui,sans-serif",
      "text-align:center",
      "box-shadow:0 1px 0 rgba(0,0,0,.06)",
      "z-index:2147483646",
    ].join(";");
    const glyph = document.createElement("div");
    glyph.textContent = "間";
    glyph.style.cssText = "font:600 44px/1 'Hiragino Mincho ProN',serif;color:#C8412C;margin-bottom:10px";
    const text = document.createElement("div");
    text.textContent = site === "tiktok"
      ? (german ? "TikTok ist in Ma ausgeschaltet. Was wolltest du eigentlich finden?" : "TikTok is switched off in Ma. What were you actually looking for?")
      : (german ? "Hier war ein Feed. Suche gezielt, statt dich treiben zu lassen." : "A feed used to be here. Search for something instead of drifting.");
    calm.append(glyph, text);
    if (site === "tiktok") {
      calm.style.position = "fixed";
      calm.style.inset = "30% 16px auto 16px";
      calm.style.margin = "0 auto";
      document.body.appendChild(calm);
    } else {
      document.body.prepend(calm);
    }
  }

  let lastUrl = "";
  let followingTried = "";
  function tick() {
    const href = location.href;
    if (href !== lastUrl) {
      lastUrl = href;
      const target = redirectFor(settings, new URL(href));
      if (target && target !== location.pathname + location.search) {
        location.replace(target);
        return;
      }
      applyStyle();
    }
    applyCalm();
    if (site === "x" && settings.xFollowingOnly && location.pathname === "/home" && followingTried !== href) {
      // "For you" is the first tab, "Following" the second. Clicking is the
      // only lever: the choice lives in X's own state, not in the URL.
      const tabs = document.querySelectorAll("[data-testid='primaryColumn'] [role='tablist'] [role='tab']");
      if (tabs.length >= 2) {
        followingTried = href;
        if (tabs[0].getAttribute("aria-selected") === "true") tabs[1].click();
      }
    }
  }

  function start(next) {
    settings = { ...DEFAULTS, ...(next || {}) };
    lastUrl = "";
    tick();
  }

  // Cached switches first, so the page never flashes a Reel while the
  // native side is being asked.
  applyStyle();
  browser.storage.local.get("settings").then((stored) => start(stored.settings)).catch(() => start(null));
  browser.runtime.sendMessage({ type: "ma-settings" }).then((fresh) => { if (fresh) start(fresh); }).catch(() => {});

  setInterval(tick, 400);
  document.addEventListener("DOMContentLoaded", tick);
})();
