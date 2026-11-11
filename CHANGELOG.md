# Changelog

## Unreleased

### Fixed

- `/inotes <id>` only accepts whole-number IDs of items that exist. Values such as `1.5` or `1e3` no longer create a note.
- Opening the editor for another item while it has unsaved changes now asks before replacing them.
- Closing the editor with Escape or the close button keeps unsaved changes; they return when the same item is opened again.
- Shift-clicking a stack to attach it no longer leaves the split-stack prompt open.
- Shift-clicking a row in the notes window while the editor is open attaches the item without also linking it in chat.
- The options panel is no longer opened or closed from addon code during combat.
- A damaged saved-variables file can no longer cause errors: notes are checked when the addon loads.
- "Show" on a map location no longer adds a duplicate TomTom waypoint.
- The note pane no longer jumps back to the top when item data arrives in the background.
- Copying a Wowhead link closes the copy window on macOS (Cmd+C) too.

### Changed

- The notes list only creates row frames for the rows in view, so it stays light with many notes.
- Searching refreshes once typing pauses instead of on every keystroke.
- The notes window remembers its position as well as its size.
- All text goes through a locale table, ready for translation.

## 1.0.0

- First release.
