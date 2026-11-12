local _, ns = ...
local L = ns.L
local IsID = ns.IsID

-- ---------------------------------------------------------------------------
-- Saved data
-- ---------------------------------------------------------------------------
--
-- ItemNotesDB, layout version 2:
--
--   version = 2,
--   notes = {
--       [itemID] = {
--           text = "...",                          -- the note itself; may be ""
--           created = <time>, updated = <time>,
--           char = "Name - Realm",                 -- who wrote it
--           loc = { zone = "...", subzone = "...", mapID = n, x = 0..1, y = 0..1 },   -- where; all optional
--           refs = { "item:123", "quest:456", ... },   -- what the note references, in the order shown
--       },
--   },
--   cache = {                                      -- names the client cannot always give, one entry per ID
--       items = { [itemID] = "name" }, quality = { [itemID] = n },
--       quests = { [questID] = "title" }, recipes = { [spellID] = "name" },
--       spells = { [spellID] = "name" }, npcs = { [npcID] = "name" },
--   },
--   window = { ... },                              -- the Item Notes window's layout; see UI\Browser.lua
--   invalid = { ... },                             -- entries of notes that could not be read, set aside
--
-- A reference is one string, in the style of the game's own links:
--
--   "item:<itemID>"      an item
--   "note:<itemID>"      another item's note
--   "quest:<questID>"    a quest
--   "recipe:<spellID>"   a crafting recipe
--   "spell:<spellID>"    a spell or ability
--   "npc:<npcID>"        a named NPC, or a kind of mob: every spawn of a mob shares one ID
--   "macro:<name>"       a macro, by its name: the game gives a macro no ID that lasts
--   "pin:<mapID>:<x>:<y>"   a map location; x and y are fractions of the map, to four decimals
--
-- A note holds each reference once, and holds no refs list while it has none. A reference between two notes is
-- stored on both of them: every function here keeps that true, and loading repairs it.
--
-- To change the layout: raise DB_VERSION and add MIGRATIONS[<old version>], which turns the old layout into the
-- next one. Loading runs every migration between the saved version and DB_VERSION, in order.

local DB_VERSION = 2

-- ---------------------------------------------------------------------------
-- Change notifications
-- ---------------------------------------------------------------------------

-- Listeners are told what changed: "notes" when notes or cached names did (lists must be rebuilt), "state"
-- when only the game around them did (bags, quest log, professions: what is on screen must be redrawn).
local listeners = {}

function ns.OnChanged(callback)
    listeners[#listeners + 1] = callback
end

local function FireChanged(what)
    for index = 1, #listeners do listeners[index](what) end
end

-- Game events come in bursts (a bag update per looted item, item data arriving one item at a time). They are
-- announced together, once the burst has had this long to arrive.
local CHANGE_DELAY = 0.1
local queued

local function FlushChanged()
    local what = queued
    queued = nil
    FireChanged(what)
end

function ns.QueueChanged(what)
    if not queued then
        queued = what
        C_Timer.After(CHANGE_DELAY, FlushChanged)
    elseif what == "notes" then
        -- A rebuild covers a redraw.
        queued = what
    end
end

-- ---------------------------------------------------------------------------
-- References
-- ---------------------------------------------------------------------------

-- The kinds of reference that are an ID. A macro and a map pin are the other kinds.
local ID_KINDS = { item = true, note = true, quest = true, recipe = true, spell = true, npc = true }

-- A map coordinate, as a fraction of the map's width or height. NaN fails the comparison.
local function IsCoord(value)
    return type(value) == "number" and value >= 0 and value <= 1
end

-- Returns the reference to anything that is an ID (kind is "item", "note", "quest", "recipe", "spell" or
-- "npc"), or to a macro: kind is "macro" and id is its name.
function ns.Ref(kind, id)
    return kind .. ":" .. id
end

-- Returns the reference to a map location. pin is { mapID = n, x = 0..1, y = 0..1 }.
function ns.PinRef(pin)
    return ("pin:%d:%.4f:%.4f"):format(pin.mapID, pin.x, pin.y)
end

-- Takes a reference apart. Returns its kind and ID or, for a macro, "macro" and its name or, for a map pin,
-- "pin", mapID, x, y. A string that is not a reference gives nil, or a kind without usable numbers.
function ns.ParseRef(ref)
    local kind, rest = ref:match("^(%a+):(.+)$")
    if kind == "pin" then
        local mapID, x, y = rest:match("^(%d+):([%d.]+):([%d.]+)$")
        return kind, tonumber(mapID), tonumber(x), tonumber(y)
    elseif kind == "macro" then
        -- The name stays text, even one that is all digits.
        return kind, rest
    end
    return kind, rest and rest:match("^%d+$") and tonumber(rest) or nil
end

-- Returns the reference as it is stored, or nil when it is not a valid one. Two references to the same thing
-- always come out as the same string.
local function CleanRef(ref)
    if type(ref) ~= "string" then return nil end
    local kind, id, x, y = ns.ParseRef(ref)
    if kind == "pin" then
        if IsID(id) and IsCoord(x) and IsCoord(y) then return ("pin:%d:%.4f:%.4f"):format(id, x, y) end
    elseif kind == "macro" then
        -- Any name will do: it only has to be there, and ParseRef gives no kind without one.
        return ref
    elseif ID_KINDS[kind] and IsID(id) then
        return kind .. ":" .. id
    end
    return nil
end

-- Returns the item a reference to a note names, or nil for any other reference.
local function LinkedNote(ref)
    return tonumber(ref:match("^note:(%d+)$"))
end

-- Scratch table for CleanRefs.
local seen = {}

-- Returns a new list of the valid references in list, in order and without repeats, or nil when there are
-- none. itemID is the note the list belongs to: a note does not reference itself or its own item. notes, when
-- given, are the notes that exist: a reference to a note that is not among them is dropped.
local function CleanRefs(list, itemID, notes)
    if type(list) ~= "table" then return nil end
    wipe(seen)
    seen["item:" .. itemID], seen["note:" .. itemID] = true, true
    local clean, count = nil, 0
    for _, entry in ipairs(list) do
        local ref = CleanRef(entry)
        if ref and not seen[ref] then
            seen[ref] = true
            local linked = notes and LinkedNote(ref)
            if not linked or notes[linked] ~= nil then
                clean = clean or {}
                count = count + 1
                clean[count] = ref
            end
        end
    end
    return clean
end

local function HasRef(list, ref)
    if list then
        for index = 1, #list do
            if list[index] == ref then return true end
        end
    end
    return false
end

local function AddRef(note, ref)
    local list = note.refs
    if not list then
        note.refs = { ref }
    elseif not HasRef(list, ref) then
        list[#list + 1] = ref
    end
end

local function RemoveRef(note, ref)
    local list = note.refs
    if not list then return end
    for index = #list, 1, -1 do
        if list[index] == ref then table.remove(list, index) end
    end
    if not list[1] then note.refs = nil end
end

-- ---------------------------------------------------------------------------
-- Validation
-- ---------------------------------------------------------------------------

local function TextOrNil(value)
    return type(value) == "string" and value ~= "" and value or nil
end

-- A point in time: any number date() can take. NaN fails the comparison.
local function IsTime(value)
    return type(value) == "number" and value >= 0 and value < math.huge
end

local function CleanLocation(loc)
    if type(loc) ~= "table" then return nil end
    loc.zone, loc.subzone = TextOrNil(loc.zone), TextOrNil(loc.subzone)
    loc.mapID = IsID(loc.mapID) and loc.mapID or nil
    if not (loc.mapID and IsCoord(loc.x) and IsCoord(loc.y)) then loc.x, loc.y = nil, nil end
    return next(loc) ~= nil and loc or nil
end

-- Gives every note that another note references a reference back to it, where that is missing. One pass over
-- the references, however many notes there are.
local function MirrorNoteRefs(notes)
    local linked = {}
    for itemID, note in pairs(notes) do
        if note.refs then
            local set
            for _, ref in ipairs(note.refs) do
                local otherID = LinkedNote(ref)
                if otherID then
                    set = set or {}
                    set[otherID] = true
                end
            end
            linked[itemID] = set
        end
    end
    for itemID, set in pairs(linked) do
        local back = "note:" .. itemID
        for otherID in pairs(set) do
            local theirs = linked[otherID]
            if not (theirs and theirs[itemID]) then
                -- Known to be missing, so it is appended without searching the list for it.
                local other = notes[otherID]
                if other.refs then
                    other.refs[#other.refs + 1] = back
                else
                    other.refs = { back }
                end
            end
        end
    end
end

-- Keeps the cached values of one kind that a note still uses and that are of the right type.
local function CleanCache(cache, kind, used, valueType)
    local values = cache[kind]
    if type(values) ~= "table" then
        cache[kind] = {}
        return
    end
    for id, value in pairs(values) do
        if not used[id] or type(value) ~= valueType then values[id] = nil end
    end
end

-- Makes sure the saved data has the shape the rest of the addon expects, so a damaged or hand-edited
-- saved-variables file cannot cause errors later. Entries that are not notes at all are moved to db.invalid
-- rather than deleted. Every step is linear in the amount of data.
local function Sanitize(db)
    if type(db.notes) ~= "table" then db.notes = {} end
    local notes = db.notes

    local invalid
    for itemID, note in pairs(notes) do
        if IsID(itemID) and type(note) == "table" then
            note.text = type(note.text) == "string" and note.text or ""
            note.created = IsTime(note.created) and note.created or nil
            note.updated = IsTime(note.updated) and note.updated or nil
            note.char = TextOrNil(note.char)
            note.loc = CleanLocation(note.loc)
        else
            invalid = invalid or {}
            invalid[#invalid + 1] = itemID
        end
    end
    if invalid then
        if type(db.invalid) ~= "table" then db.invalid = {} end
        for _, key in ipairs(invalid) do
            db.invalid[tostring(key)] = notes[key]
            notes[key] = nil
        end
    end

    -- Only once every note is known to be valid can references between them be checked.
    for itemID, note in pairs(notes) do
        note.refs = CleanRefs(note.refs, itemID, notes)
    end
    MirrorNoteRefs(notes)

    -- Cached names nothing refers to any more (a deleted note, a removed reference) are dropped here.
    local used = { item = {}, quest = {}, recipe = {}, spell = {}, npc = {} }
    used.note = used.item
    for itemID, note in pairs(notes) do
        used.item[itemID] = true
        if note.refs then
            for _, ref in ipairs(note.refs) do
                local kind, id = ns.ParseRef(ref)
                if used[kind] then used[kind][id] = true end
            end
        end
    end
    if type(db.cache) ~= "table" then db.cache = {} end
    CleanCache(db.cache, "items", used.item, "string")
    CleanCache(db.cache, "quality", used.item, "number")
    CleanCache(db.cache, "quests", used.quest, "string")
    CleanCache(db.cache, "recipes", used.recipe, "string")
    CleanCache(db.cache, "spells", used.spell, "string")
    CleanCache(db.cache, "npcs", used.npc, "string")
end

-- ---------------------------------------------------------------------------
-- Migrations
-- ---------------------------------------------------------------------------

-- MIGRATIONS[n] turns layout version n into version n + 1, in place. It is given a copy of the saved data, so
-- a migration that fails leaves the original untouched. It only has to move things to where the new layout
-- keeps them: Sanitize runs afterwards and drops whatever is left over or damaged.
local MIGRATIONS = {}

-- 1 -> 2. A note kept one list per kind of reference, each reference a table ({ id = n, name = "..." }, or
-- { mapID = n, x = n, y = n, name = "..." } for a map pin). They become one list of reference strings, in the
-- order they were shown in: items, notes, quests, recipes, map pins. The names those tables held, and the name
-- and quality each note kept for its own item, move to the shared cache. Notes no longer store their item's
-- icon, nor map pins their map's name: the client always knows both.
MIGRATIONS[1] = function(db)
    local cache = { items = {}, quality = {}, quests = {}, recipes = {} }

    local function Keep(values, id, value, valueType)
        if values[id] == nil and type(value) == valueType and value ~= "" then values[id] = value end
    end

    -- Appends a reference of the given kind to refs for each entry of an old list. names and nameField, when
    -- given, say where the entry's name goes in the cache and which of its fields holds it.
    local function Move(refs, list, kind, names, nameField)
        if type(list) ~= "table" then return end
        for _, old in ipairs(list) do
            if type(old) == "table" and IsID(old.id) then
                refs[#refs + 1] = ns.Ref(kind, old.id)
                if names then Keep(names, old.id, old[nameField], "string") end
                if kind == "item" then Keep(cache.quality, old.id, old.quality, "number") end
            end
        end
    end

    if type(db.notes) ~= "table" then db.notes = {} end
    -- A note's own name for its item is the freshest, so those are taken before any reference's.
    for itemID, note in pairs(db.notes) do
        if IsID(itemID) and type(note) == "table" then
            Keep(cache.items, itemID, note.name, "string")
            Keep(cache.quality, itemID, note.quality, "number")
        end
    end
    for _, note in pairs(db.notes) do
        if type(note) == "table" then
            local refs = {}
            Move(refs, note.items, "item", cache.items, "name")
            Move(refs, note.notes, "note")
            Move(refs, note.quests, "quest", cache.quests, "title")
            Move(refs, note.recipes, "recipe", cache.recipes, "name")
            if type(note.pins) == "table" then
                for _, pin in ipairs(note.pins) do
                    if type(pin) == "table" and IsID(pin.mapID) and IsCoord(pin.x) and IsCoord(pin.y) then
                        refs[#refs + 1] = ns.PinRef(pin)
                    end
                end
            end
            note.items, note.notes, note.quests, note.recipes, note.pins = nil, nil, nil, nil, nil
            note.name, note.quality, note.icon = nil, nil, nil
            note.refs = refs
        end
    end
    db.cache = cache
    -- Never held anything.
    db.settings = nil
end

local function DeepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, entry in pairs(value) do copy[key] = DeepCopy(entry) end
    return copy
end

-- Readies the saved notes for use and sets ns.db. Data saved by an older version of the addon is brought up
-- to date first. Data that cannot be used (saved by a newer version, or a migration failed) is left exactly
-- as it is: ns.db stays unset, which turns the addon off for the session, and ns.dbProblem says why.
function ns.LoadDatabase()
    local db = ItemNotesDB
    if type(db) ~= "table" then db = { version = DB_VERSION } end

    -- Version 1 was the first layout, and the only one that could have been saved without a usable version.
    local version = type(db.version) == "number" and db.version or 1
    if version > DB_VERSION then
        ns.dbProblem = L["Your saved notes were written by a newer version of this addon and were left untouched. Update Item Notes to use them."]
        return
    end

    if version < DB_VERSION then
        local migrated = DeepCopy(db)
        local ok = ns.Try(function()
            for from = version, DB_VERSION - 1 do
                local migrate = MIGRATIONS[from]
                if not migrate then error("Item Notes: no migration from data version " .. tostring(from)) end
                migrate(migrated)
            end
        end)
        if not ok then
            ns.dbProblem = L["Your saved notes could not be updated to this version of the addon and were left untouched."]
            return
        end
        db = migrated
    end

    if not ns.Try(function() Sanitize(db) end) then
        ns.dbProblem = L["Your saved notes could not be read and were left untouched."]
        return
    end
    db.version = DB_VERSION
    ItemNotesDB = db
    ns.db = db
end

-- ---------------------------------------------------------------------------
-- Cached names
-- ---------------------------------------------------------------------------

-- The client only knows an item's name once the server has sent it, a quest's title while the quest is at
-- hand, an NPC's name while the NPC is in sight, and so on. Names are therefore remembered when they are seen.
-- kind is "items", "quests", "recipes", "spells" or "npcs".

function ns.CachedName(kind, id)
    return ns.db.cache[kind][id]
end

-- Remembers a name. Does nothing without one.
function ns.Remember(kind, id, name)
    if type(name) == "string" and name ~= "" then ns.db.cache[kind][id] = name end
end

-- Items the client has been asked about this session.
local asked = {}

-- Caches what the client knows about the item now. Returns true when that changed what was cached.
local function LearnItem(itemID)
    local name, _, quality = ns.ItemInfo(itemID)
    if type(name) ~= "string" then return false end
    if type(quality) ~= "number" then quality = nil end
    local cache = ns.db.cache
    if cache.items[itemID] == name and cache.quality[itemID] == quality then return false end
    cache.items[itemID], cache.quality[itemID] = name, quality
    return true
end

-- Returns the item's name and quality; either is nil while unknown. The client is asked once per session,
-- and again for as long as the name is missing: asking is what makes it request the item's data from the
-- server. After that the cache answers.
function ns.ItemDisplay(itemID)
    local cache = ns.db.cache
    if not asked[itemID] or not cache.items[itemID] then
        asked[itemID] = true
        LearnItem(itemID)
    end
    return cache.items[itemID], cache.quality[itemID]
end

-- Item data arrived from the server. Only items that were asked about matter.
function ns.ItemInfoReceived(itemID)
    if asked[itemID] and LearnItem(itemID) then ns.QueueChanged("notes") end
end

-- ---------------------------------------------------------------------------
-- Notes
-- ---------------------------------------------------------------------------

function ns.GetNote(itemID)
    return ns.db and ns.db.notes[itemID]
end

-- Keeps the other side of a note's references to notes in step, after its references changed from previous
-- to current: a note newly referenced gains a reference back, a note no longer referenced loses its own.
-- Only the notes involved are touched, never the whole collection.
local function SyncNoteRefs(notes, itemID, previous, current)
    local back = "note:" .. itemID
    if previous then
        for _, ref in ipairs(previous) do
            local other = notes[LinkedNote(ref)]
            if other and not HasRef(current, ref) then RemoveRef(other, back) end
        end
    end
    if current then
        for _, ref in ipairs(current) do
            local other = notes[LinkedNote(ref)]
            if other then AddRef(other, back) end
        end
    end
end

-- The player's name as "First Last". On the Forever client a character has a surname, and UnitName returns it
-- as its second value, where other clients return a realm. Builds have differed on this, so when UnitName gives
-- no surname the full display name is taken from GetUnitName, which has the two joined already.
local function PlayerName()
    local first, last = UnitName("player")
    if type(first) ~= "string" or first == "" then return "?" end
    if type(last) == "string" and last ~= "" then return first .. " " .. last end
    local full = GetUnitName and GetUnitName("player", true)
    if type(full) == "string" and full ~= "" then return full end
    return first
end

-- Creates or updates a note. Location, character and creation time are recorded once, when the note is created.
-- refs is the list of the note's references, in the order they are to be shown: it replaces the note's
-- current list, and without it the references stay as they are. The list is copied, not kept.
function ns.SaveNote(itemID, text, refs)
    local db = ns.db
    local note = db.notes[itemID]
    local now = time()
    if not note then
        note = {
            created = now,
            loc = ns.CaptureLocation(),
            char = PlayerName() .. " - " .. (GetRealmName() or "?"),
        }
        db.notes[itemID] = note
    end
    note.text = text or ""
    note.updated = now
    if refs then
        local previous = note.refs
        note.refs = CleanRefs(refs, itemID, db.notes)
        SyncNoteRefs(db.notes, itemID, previous, note.refs)
    end
    -- Have the names of the items involved cached, or asked for.
    ns.ItemDisplay(itemID)
    if note.refs then
        for _, ref in ipairs(note.refs) do
            local kind, id = ns.ParseRef(ref)
            if kind == "item" then ns.ItemDisplay(id) end
        end
    end
    FireChanged("notes")
    return note
end

-- Told of every reference ns.ReplaceRef replaces, as (old, new): new is nil for one that was removed.
local refListeners = {}

function ns.OnRefReplaced(callback)
    refListeners[#refListeners + 1] = callback
end

-- Replaces one reference by another in every note, or removes it when there is no other: what follows a macro
-- that was renamed or deleted. Not for a reference to a note: those go both ways, and SaveNote and DeleteNote
-- keep them in step. A note left without text or references stays, as one does when a note it referenced is
-- deleted. Returns how many notes held the reference.
function ns.ReplaceRef(old, new)
    local count = 0
    for _, note in pairs(ns.db.notes) do
        local list = note.refs
        -- A note holds a reference once.
        for index = 1, list and #list or 0 do
            if list[index] == old then
                count = count + 1
                if new and not HasRef(list, new) then
                    list[index] = new
                else
                    table.remove(list, index)
                    if not list[1] then note.refs = nil end
                end
                break
            end
        end
    end
    -- Unsaved edits can hold the reference when no note does.
    for index = 1, #refListeners do refListeners[index](old, new) end
    if count > 0 then FireChanged("notes") end
    return count
end

-- Deletes a note, and with it the references other notes hold to it. Those are exactly the notes it references.
function ns.DeleteNote(itemID)
    local db = ns.db
    local note = db.notes[itemID]
    if not note then return end
    db.notes[itemID] = nil
    SyncNoteRefs(db.notes, itemID, note.refs, nil)
    FireChanged("notes")
end
