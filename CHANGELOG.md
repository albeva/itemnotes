# Changelog

## Unreleased

### Added

- Notes can reference crafting recipes. Shift-click a recipe while the editor is open.

### Changed

- New saved-data format. Existing notes are converted automatically.
- References show in the order they were attached.
- References in the editor have only a remove button.
- Sorting by name ignores case.

### Fixed

- Loading, searching and bag changes stay fast with many notes.

## 1.0.0-alpha3 - 2026-11-11

### Added

- Notes can reference other notes. Shift-click a note in the Item Notes window while the editor is open; the link shows on both notes.
- A new note starts with the item's quests attached, taken from the bags, the quest log and Questie when it is loaded.
- Locate button finds the item in the bags, and item icons show how many the bags hold.

### Changed

- Quests, items and notes are all attached by shift-click. The Add Quest button is gone.
- The editor no longer has Wowhead, Link in Chat and Locate buttons. They stay in the Item Notes window.
- The References section is hidden for a note that has no references.
- A quest's Open button is disabled when the quest is not in the quest log.

### Fixed

- The Item Notes window can no longer be resized past the screen, and resizing no longer jumps.
- A map location uses the Blizzard map pin when TomTom is missing or does not take the waypoint.

## 1.0.0-alpha2

- Renamed to ItemNotesForever. Existing installs must rename the AddOns folder and `SavedVariables/ItemNotesAddon.lua` to keep their notes.

## 1.0.0-alpha1

- First alpha.
