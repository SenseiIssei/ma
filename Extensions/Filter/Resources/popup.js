const GERMAN = (navigator.language || "").toLowerCase().startsWith("de");

const LABELS = GERMAN ? {
  instagramReels: "Instagram Reels",
  instagramExplore: "Instagram Entdecken",
  youtubeShorts: "YouTube Shorts",
  youtubeHome: "YouTube Startseite",
  xTrends: "X Trends",
  xFollowingOnly: "X nur Folge ich",
  linkedinFeed: "LinkedIn Feed",
  facebookReels: "Facebook Reels",
  tiktok: "TikTok",
} : {
  instagramReels: "Instagram Reels",
  instagramExplore: "Instagram Explore",
  youtubeShorts: "YouTube Shorts",
  youtubeHome: "YouTube home page",
  xTrends: "X Trends",
  xFollowingOnly: "X Following only",
  linkedinFeed: "LinkedIn feed",
  facebookReels: "Facebook Reels",
  tiktok: "TikTok",
};

if (GERMAN) {
  const intro = document.getElementById("intro");
  intro.textContent = "Reels, Shorts und endlose Feeds bleiben draußen. Was genau, stellst du in der Ma-App unter ";
  const em = document.createElement("em");
  em.textContent = "Grenzen";
  intro.append(em, " ein.");
}

function render(settings) {
  const list = document.getElementById("list");
  list.textContent = "";
  for (const [key, label] of Object.entries(LABELS)) {
    const on = settings ? settings[key] !== false && settings[key] !== undefined : false;
    const li = document.createElement("li");
    if (on) li.className = "on";
    const name = document.createElement("span");
    name.textContent = label;
    const state = document.createElement("span");
    state.textContent = on ? (GERMAN ? "aus dem Weg" : "out of the way") : (GERMAN ? "sichtbar" : "visible");
    li.append(name, state);
    list.appendChild(li);
  }
}

browser.runtime
  .sendMessage({ type: "ma-settings" })
  .then(render)
  .catch(() => browser.storage.local.get("settings").then((s) => render(s.settings)));
