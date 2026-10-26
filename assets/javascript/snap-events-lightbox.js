// Lightbox for event flyers on the "Upcoming SNAP Events" list (see
// _includes/upcoming_events.html). Clicking a flyer image opens a full-screen
// overlay showing it larger; the X button, a backdrop click, or Escape closes
// it. Mirrors assets/javascript/stance-team-lightbox.js.

(function () {
  "use strict";

  function setupSection(root) {
    var imgs = Array.prototype.slice.call(
      root.querySelectorAll(".snap-event__flyer-img")
    );
    var box = root.querySelector(".snap-events__lightbox");
    if (!imgs.length || !box) return;

    var lbImg = box.querySelector(".snap-events__lb-img");
    var closeBtn = box.querySelector(".snap-events__lb-close");
    var lastFocused = null;

    function open(img) {
      lbImg.src = img.currentSrc || img.src;
      lbImg.alt = img.alt || "";
      lastFocused = document.activeElement;
      box.hidden = false;
      document.body.style.overflow = "hidden"; // stop background scroll
      window.requestAnimationFrame(function () {
        closeBtn.focus();
      });
    }

    function close() {
      box.hidden = true;
      document.body.style.overflow = "";
      if (lastFocused && typeof lastFocused.focus === "function") {
        lastFocused.focus();
      }
    }

    imgs.forEach(function (img) {
      img.setAttribute("role", "button");
      img.setAttribute("tabindex", "0");
      img.setAttribute("aria-label", "Enlarge flyer" + (img.alt ? ": " + img.alt : ""));

      img.addEventListener("click", function () {
        open(img);
      });
      img.addEventListener("keydown", function (e) {
        if (e.key === "Enter" || e.key === " " || e.key === "Spacebar") {
          e.preventDefault();
          open(img);
        }
      });
    });

    closeBtn.addEventListener("click", close);

    // Click on the backdrop (but not on the image or the close button) closes.
    box.addEventListener("click", function (e) {
      if (e.target === box) close();
    });

    document.addEventListener("keydown", function (e) {
      if (box.hidden) return;
      if (e.key === "Escape") close();
    });
  }

  // The include can appear more than once on a page (upcoming + past), and each
  // copy loads this script, so mark sections as set up to avoid doubling up.
  function init() {
    document.querySelectorAll(".snap-events").forEach(function (root) {
      if (root.dataset.lightboxReady) return;
      root.dataset.lightboxReady = "true";
      setupSection(root);
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
}());
