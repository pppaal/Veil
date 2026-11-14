// Opens and closes the static modal dialogs in index.html by id. Dialogs
// stack: a confirmation can be asked from inside another dialog (app.css
// keeps #confirm-dialog above the rest). So the element to give focus back
// to is kept for each open dialog, innermost last, and closing the top
// dialog returns focus to what had it when that dialog opened; for a
// confirmation, that is the control in the dialog underneath that asked.

export function createDialogs(doc) {
  let stack = [];
  const byId = (id) => doc.getElementById(id);
  const isOpen = (id) => !byId(id).classList.contains('hidden');

  return {
    open(dialogId, firstFocusId) {
      // A dialog hidden without close() (the global Escape handler) has no
      // focus left to give back.
      stack = stack.filter((entry) => isOpen(entry.dialogId));
      stack.push({ dialogId, returnFocus: doc.activeElement });
      byId(dialogId).classList.remove('hidden');
      if (firstFocusId) requestAnimationFrame(() => byId(firstFocusId)?.focus());
    },

    close(dialogId) {
      byId(dialogId).classList.add('hidden');
      const index = stack.findLastIndex((entry) => entry.dialogId === dialogId);
      if (index === -1) return;
      const [{ returnFocus }] = stack.splice(index, 1);
      // Closed beneath another dialog: focus stays in the one on top.
      if (index < stack.length) return;
      if (returnFocus && doc.contains(returnFocus)) {
        try { returnFocus.focus(); } catch {}
      }
    },
  };
}
