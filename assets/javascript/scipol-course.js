(function () {
  "use strict";

  var copyButton = document.querySelector("[data-copy-target]");
  if (!copyButton) return;

  var targetId = copyButton.getAttribute("data-copy-target");
  var citationElement = document.getElementById(targetId);
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

  function copyCitation(value) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(value);
    }

    copyWithFallback(value);
    return Promise.resolve();
  }

  copyButton.addEventListener("click", function () {
    var citation = citationElement.textContent.trim();

    copyCitation(citation).then(function () {
      window.clearTimeout(resetTimer);
      label.textContent = "Copied";
      status.textContent = "Citation copied to the clipboard.";
      resetTimer = window.setTimeout(function () {
        label.textContent = "Copy citation";
        status.textContent = "";
      }, 2500);
    }).catch(function () {
      label.textContent = "Copy failed";
      status.textContent = "Select the citation and copy it manually.";
    });
  });
}());
