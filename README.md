# Item Notes

A World of Warcraft addon for the **Forever** client that lets you attach personal notes to items.

Notes are stored by item ID and shared across all characters on your account. They stay even if the item is sold, banked or destroyed.

## Features

- Add a note to any item by hovering it and pressing a keybind
- Notes appear in the item's tooltip
- Attach quests, map locations, other items and other notes as references
- Location, time and character are recorded automatically
- One window to search, sort and manage all notes
- Copy a Wowhead link or post the item link in chat
- See how many of an item are in your bags; **Locate** opens them and searches for it

## Usage

### Add a note

Hover over an item and press your keybind. Type the note and press Enter.

![Note editor](screenshots/editor.png)

While the editor is open:

- **Shift-click** a quest (tracker or quest log) or any item to attach it
- **Shift-click** a note in the Item Notes window to attach that note
- **Drag** an item onto the window to attach it
- **Add My Location** / **Add Map Pin** attach a map location

A reference to another note opens that note, and goes both ways: attach note B to note A and B lists A as well. Removing it from either side removes it from both. Deleting a note also removes every reference to it.

Closing the editor with Escape keeps unsaved changes: open the same item again to continue. **Cancel** discards them.

### See it in the tooltip

![Tooltip](screenshots/tooltip.png)

### Manage all notes

Type `/inotes`, or open it from the addon compartment or **Options > AddOns > Item Notes**.

![Item Notes window](screenshots/notes-window.png)

Double-click a note to edit it. Drag an item onto the window to add a new note.

## Setup

Set the keybind under **Options > Keybindings > AddOns > Item Notes**. There is no default key.

## Commands

| Command | Action |
|---|---|
| `/inotes` | Open the Item Notes window |
| `/inotes <item link or ID>` | Open the editor for that item |
| `/inotes options` | Open the settings panel |

## Install

The addon itself lives in the `addon` folder of this repository. Copy that folder into your AddOns folder and name it `ItemNotesForever`:

```
World of Warcraft/_forever_/Interface/AddOns/ItemNotesForever/ItemNotesForever.toc
```

To keep it updated with `git pull`, clone the repository anywhere and link the folder instead of copying it.

Windows (Command Prompt):

```
git clone https://github.com/albeva/itemnotes
mklink /J "C:\Path\To\World of Warcraft\_forever_\Interface\AddOns\ItemNotesForever" "itemnotes\addon"
```

macOS:

```
git clone https://github.com/albeva/itemnotes
ln -s "$PWD/itemnotes/addon" "/Applications/World of Warcraft/_forever_/Interface/AddOns/ItemNotesForever"
```

Restart the game.

## Repository layout

| Path | Contents |
|---|---|
| `addon/` | Everything the game loads, plus lint config |
| `.pkgmeta` | CurseForge packaging config |
| `art/` | Icon source (SVG) and a 512px render |
| `screenshots/` | Images for this page |

## License

[MIT](LICENSE)
