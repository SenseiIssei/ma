// Relays the content script's question to the native handler, which reads
// the switches the Ma app wrote into the App Group.
browser.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (!message || message.type !== "ma-settings") return false;
  browser.runtime
    .sendNativeMessage("com.sensei.ma", { type: "settings" })
    .then((settings) => {
      browser.storage.local.set({ settings });
      sendResponse(settings);
    })
    .catch(() => {
      browser.storage.local.get("settings").then((stored) => sendResponse(stored.settings || null));
    });
  return true;
});
