(function () {
  // Close flash messages
  document.addEventListener('click', function (e) {
    const btn = e.target.closest('[data-close-flash]');
    if (btn) {
      const flash = btn.closest('.flash');
      if (flash) flash.remove();
    }
  });

  // Confirm soft delete or other destructive actions
  document.addEventListener('click', function (e) {
    const btn = e.target.closest('[data-confirm]');
    if (btn) {
      const msg = btn.getAttribute('data-confirm') || 'Are you sure?';
      if (!confirm(msg)) {
        e.preventDefault();
        e.stopPropagation();
      }
    }
  });
})();
