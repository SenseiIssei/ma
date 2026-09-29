// Remembers the language someone picked with the EN/DE switch, so the
// landing page does not send them back to the other edition. Nothing else
// is stored and nothing leaves the browser.
(function () {
  var links = document.querySelectorAll("[data-set-lang]");
  for (var i = 0; i < links.length; i++) {
    links[i].addEventListener("click", function (event) {
      try { localStorage.setItem("ma-lang", event.currentTarget.getAttribute("data-set-lang")); } catch (e) {}
    });
  }
  var year = document.getElementById("year");
  if (year) year.textContent = String(new Date().getFullYear());
})();
