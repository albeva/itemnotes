# Item Notes

A World of Warcraft addon for the **Forever** client that lets you attach personal notes to items.

Notes are stored by item ID and shared across all characters on your account. They stay even if the item is sold, banked or destroyed.

## Features

- Add a note to any item by hovering it and pressing a keybind
- Notes appear in the item's tooltip
- Attach quests, map locations and other items as references
- Location, time and character are recorded automatically
- One window to search, sort and manage all notes
- Copy a Wowhead link or post the item link in chat

## Usage

### Add a note

Hover over an item and press your keybind. Type the note and press Enter.

![Note editor](screenshots/editor.png)

While the editor is open:

- **Shift-click** a quest (tracker or quest log) or any item to attach it
- **Drag** an item onto the window to attach it
- **Add My Location** / **Add Map Pin** attach a map location

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

Clone into your AddOns folder. The folder must be named `ItemNotesAddon`:

```
cd "World of Warcraft/_forever_/Interface/AddOns"
git clone https://github.com/albeva/itemnotes ItemNotesAddon
```

Restart the game.

## License

[MIT](LICENSE)
