/* backend/app/static/js/admin.js
   SportsQuiz Admin UI helpers (Windows/desktop friendly)

   Combines your existing behavior:
     - Close flash messages
     - Confirm on elements with [data-confirm]

   Adds:
     - Prevent double-submit on forms
     - Auto-submit toolbar filter forms (class="toolbar")
     - Autofocus first meaningful field
     - “Next field on Enter” for quick option entry (use data-next="#selector")
*/

(function () {
  "use strict";

  // ---------------------------------------------------------------------------
  // Utilities
  // ---------------------------------------------------------------------------
  const $ = (sel, ctx = document) => ctx.querySelector(sel);
  const $$ = (sel, ctx = document) => Array.from(ctx.querySelectorAll(sel));

  const debounce = (fn, ms = 150) => {
    let t;
    return (...args) => {
      clearTimeout(t);
      t = setTimeout(() => fn.apply(null, args), ms);
    };
  };

  // ---------------------------------------------------------------------------
  // 1) Close flash messages  (merged from your existing code)
  //    Click on anything with [data-close-flash] to remove its parent .flash
  // ---------------------------------------------------------------------------
  document.addEventListener("click", function (e) {
    const btn = e.target.closest("[data-close-flash]");
    if (!btn) return;
    const flash = btn.closest(".flash");
    if (flash) flash.remove();
  });

  // ---------------------------------------------------------------------------
  // 2) Confirm soft delete / destructive actions  (merged from your existing code)
  //    Any clickable with [data-confirm] triggers a confirm() dialog
  // ---------------------------------------------------------------------------
  document.addEventListener("click", function (e) {
    const btn = e.target.closest("[data-confirm]");
    if (!btn) return;
    const msg = btn.getAttribute("data-confirm") || "Are you sure?";
    if (!window.confirm(msg)) {
      e.preventDefault();
      e.stopPropagation();
    }
  });

  // ---------------------------------------------------------------------------
  // 3) Prevent double-submit on forms
  //    Disables submit buttons and guards repeated posts
  // ---------------------------------------------------------------------------
  document.addEventListener("submit", (e) => {
    const form = e.target;
    if (!(form instanceof HTMLFormElement)) return;

    // If already submitting, stop a second submission
    if (form.dataset.submitting === "1") {
      e.preventDefault();
      return;
    }
    form.dataset.submitting = "1";

    // Disable submit buttons and optionally change text to "Saving…"
    $$('button[type="submit"], input[type="submit"]', form).forEach((btn) => {
      btn.disabled = true;
      if (!btn.dataset.originalText && "textContent" in btn) {
        btn.dataset.originalText = btn.textContent || "";
      }
      if ("textContent" in btn && btn.textContent) {
        btn.textContent = "Saving…";
      }
    });

    // Safety net: if we remain on the same page (e.g., validation error),
    // re-enable after a short timeout so the UI isn't stuck.
    setTimeout(() => {
      if (!form.isConnected) return; // Navigated away successfully.
      $$('button[type="submit"], input[type="submit"]', form).forEach((btn) => {
        btn.disabled = false;
        if (btn.dataset.originalText) btn.textContent = btn.dataset.originalText;
      });
      form.dataset.submitting = "0";
    }, 5000);
  });

  // ---------------------------------------------------------------------------
  // 4) Auto-submit toolbar filter forms
  //    Any <form class="toolbar"> will submit on change (checkbox/radio/select)
  // ---------------------------------------------------------------------------
  function wireToolbarAutosubmit() {
    $$(".toolbar").forEach((form) => {
      form.addEventListener(
        "change",
        debounce(() => {
          if (form instanceof HTMLFormElement) form.submit();
        }, 60)
      );
    });
  }

  // ---------------------------------------------------------------------------
  // 5) Autofocus first field (unless a field already has [autofocus])
  //    Focus first input/textarea/select within <main>
  // ---------------------------------------------------------------------------
  function focusFirstField() {
    if ($("[autofocus]")) return;
    const main = $("main") || document;
    const first = main.querySelector(
      'input:not([type="hidden"]), textarea, select'
    );
    if (first && typeof first.focus === "function") {
      first.focus();
      // Place caret at end for text inputs
      try {
        if ("setSelectionRange" in first && first.value) {
          const len = first.value.length;
          first.setSelectionRange(len, len);
        }
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // 6) “Next field on Enter” for speedy data entry
  //    Put data-next="#options_1" on #options_0 etc. Skips textareas.
  // ---------------------------------------------------------------------------
  function wireNextOnEnter() {
    document.addEventListener("keydown", (e) => {
      if (e.key !== "Enter") return;
      const el = e.target;
      if (!(el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement))
        return;

      // Allow enter inside textareas (new lines)
      if (el instanceof HTMLTextAreaElement) return;

      const nextSel = el.getAttribute("data-next");
      if (!nextSel) return;

      e.preventDefault();
      const next = $(nextSel);
      if (next && typeof next.focus === "function") {
        next.focus();
        try {
          if ("setSelectionRange" in next && next.value) {
            const len = next.value.length;
            next.setSelectionRange(len, len);
          }
        } catch (_) {}
      }
    });
  }

  // ---------------------------------------------------------------------------
  // Boot
  // ---------------------------------------------------------------------------
  function boot() {
    wireToolbarAutosubmit();
    wireNextOnEnter();
    focusFirstField();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }
})();
