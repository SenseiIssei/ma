const LABELS = {
  instagramReels: "Instagram Reels",
  instagramExplore: "Instagram Entdecken",
  youtubeShorts: "YouTube Shorts",
  youtubeHome: "YouTube Startseite",
  xTrends: "X Trends",
  xFollowingOnly: "X nur Folge ich",
  linkedinFeed: "LinkedIn Feed",
  facebookReels: "Facebook Reels",
  tiktok: "TikTok",
};

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
    state.textContent = on ? "aus dem Weg" : "sichtbar";
    li.append(name, state);
    list.appendChild(li);
  }
}

browser.runtime
  .sendMessage({ type: "ma-settings" })
  .then(render)
  .catch(() => browser.storage.local.get("settings").then((s) => render(s.settings)));
