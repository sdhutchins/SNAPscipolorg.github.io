(function () {
  "use strict";

  var copyButton = document.querySelector("[data-copy-target]");
  if (!copyButton) return;

  var targetId = copyButton.getAttribute("data-copy-target");
  var doiElement = document.getElementById(targetId);
  var label = copyButton.querySelector("[data-copy-label]");
  var status = document.querySelector(".scipol-course__copy-status");
  var resetTimer;

  // Older browsers may not expose the Clipboard API. The temporary textarea
  // keeps the copy control useful without changing what visitors see.
  function copyWithFallback(value) {
    var textArea = document.createElement("textarea");
    textArea.value = value;
    textArea.setAttribute("readonly", "");
    textArea.style.position = "fixed";
    textArea.style.opacity = "0";
    document.body.appendChild(textArea);
    textArea.select();

    var copied = document.execCommand("copy");
    document.body.removeChild(textArea);
    if (!copied) throw new Error("Copy command was not accepted");
  }

  function copyDoi(value) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(value);
    }

    copyWithFallback(value);
    return Promise.resolve();
  }

  copyButton.addEventListener("click", function () {
    var doi = doiElement.textContent.trim();

    copyDoi(doi).then(function () {
      window.clearTimeout(resetTimer);
      label.textContent = "Copied";
      status.textContent = "Placeholder DOI copied to the clipboard.";
      resetTimer = window.setTimeout(function () {
        label.textContent = "Copy DOI";
        status.textContent = "";
      }, 2500);
    }).catch(function () {
      label.textContent = "Copy failed";
      status.textContent = "Select the placeholder DOI and copy it manually.";
    });
  });
}());
