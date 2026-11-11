local addonName, ns = ...
local L = ns.L

ns.title = L["Item Notes"]
ns.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The addon's own icon (Media\icon.tga). Built from the folder name so it survives a renamed folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon"

BINDING_HEADER_ITEMNOTES = ns.title
BINDING_NAME_ITEMNOTES_EDIT = L["Add / edit note for hovered item"]
BINDING_NAME_ITEMNOTES_TOGGLE = L["Open Item Notes window"]

local DB_VERSION = 1
local MAX_ID = 2147483647

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function IsSecret(value)
    return issecretvalue and issecretvalue(value) or false
end

local function PublicNumber(value)
    return not IsSecret(value) and type(value) == "number"
end

local function PublicString(value)
    return not IsSecret(value) and type(value) == "string"
end

-- True for a positive whole number small enough to be an item or quest ID.
local function IsID(value)
    return PublicNumber(value) and value > 0 and value <= MAX_ID and value % 1 == 0
end

ns.PublicNumber = PublicNumber
ns.IsID = IsID

function ns.Print(message)
    print("|cffffd100" .. ns.title .. ":|r " .. tostring(message))
end

-- Runs fn. An error goes to the game's error handler (so it is still reported) instead of aborting the caller.
-- Returns true when fn finished without an error.
function ns.Try(fn)
    return (xpcall(fn, geterrorhandler()))
end

function ns.InCombat()
    return InCombatLockdown ~= nil and InCombatLockdown()
end

function ns.Trim(text)
    return (text or ""):match("^%s*(.-)%s*$")
end

function ns.FormatTime(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or ""
end

-- Returns name, link, quality, icon. Any of them may be nil until the client has cached the item.
function ns.ItemInfo(itemID)
    local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    local name, link, quality, icon
    if getInfo then
        local n, l, q, _, _, _, _, _, _, i = getInfo(itemID)
        name, link, quality, icon = n, l, q, i
    end
    if not icon then
        local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if instant then icon = select(5, instant(itemID)) end
    end
    return name, link, quality, icon
end

-- Whether the client knows an item with this ID. Answers from the local item database, without a server request.
function ns.ItemExists(itemID)
    if not IsID(itemID) then return false end
    local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not instant then return true end
    return instant(itemID) ~= nil
end

-- The item's name, or a placeholder while it is not known.
function ns.ItemName(itemID, name)
    return name or L["Item #%d"]:format(itemID)
end

function ns.MapName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

function ns.CaptureLocation()
    local zone = GetRealZoneText and GetRealZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc = {
        zone = PublicString(zone) and zone or "",
        subzone = PublicString(subzone) and subzone or "",
    }
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if PublicNumber(mapID) then
        loc.mapID = mapID
        -- Position is unavailable inside instances.
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos and not IsSecret(pos) then
            local x, y = pos:GetXY()
            if PublicNumber(x) and PublicNumber(y) then
                loc.x = math.floor(x * 10000 + 0.5) / 10000
                loc.y = math.floor(y * 10000 + 0.5) / 10000
            end
        end
    end
    return loc
end

function ns.LocationText(loc)
    if not loc then return "" end
    local text = loc.zone or ""
    if loc.subzone and loc.subzone ~= "" and loc.subzone ~= loc.zone then
        text = text ~= "" and (text .. " - " .. loc.subzone) or loc.subzone
    end
    if text == "" then text = ns.MapName(loc.mapID) or L["Unknown"] end
    if loc.x and loc.y then
        text = text .. string.format(" (%.1f, %.1f)", loc.x * 100, loc.y * 100)
    end
    return text
end

-- Where, when and by whom a note was recorded, one fact per line.
-- short drops the realm from the character name, for narrow panes.
function ns.RecordedText(note, short)
    local lines = { L["Recorded in %s"]:format(ns.LocationText(note.loc)) }
    local who = note.char
    if who and short then who = who:match("^(.-) %- ") or who end
    local when = ns.FormatTime(note.created)
    lines[2] = who and L["%s  by %s"]:format(when, who) or when
    if note.updated and note.updated ~= note.created then
        lines[3] = L["Edited %s"]:format(ns.FormatTime(note.updated))
    end
    return table.concat(lines, "\n")
end

-- Wowhead database for the Forever client. kind is "item" or "quest".
function ns.WowheadURL(kind, id)
    return "https://www.wowhead.com/forever/" .. kind .. "=" .. id
end

-- Returns the item's name in its quality colour, and the plain name.
local function ColoredName(itemID, name, quality)
    local plain = ns.ItemName(itemID, name)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return ((color and color.hex) or "|cffffffff") .. plain .. "|r", plain
end

-- Returns a quality-coloured name and the plain name for an item reference.
function ns.ItemRefLabel(ref)
    local name, _, quality = ns.ItemInfo(ref.id)
    if name then ref.name = name end
    if quality then ref.quality = quality end
    return ColoredName(ref.id, ref.name, ref.quality)
end

-- Returns a quality-coloured name and the plain name for a reference to another item's note.
-- The name comes from the referenced note, which keeps it cached.
function ns.NoteRefLabel(ref)
    local note = ns.GetNote(ref.id)
    local name, _, quality = ns.ItemInfo(ref.id)
    return ColoredName(ref.id, name or (note and note.name), quality or (note and note.quality))
end

-- Inserts a link into the chat box that is currently open. Returns false when there is none.
function ns.InsertChatLink(link)
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    if not insert then return false end
    local ok, result = pcall(insert, link)
    return ok and result == true
end

-- Puts the item's link into the chat input: into the open chat box if there is one, otherwise opens chat with it.
function ns.LinkInChat(itemID)
    local _, link = ns.ItemInfo(itemID)
    if not link then
        ns.Print(L["Item data is still loading. Try again in a moment."])
        return
    end
    if ns.InsertChatLink(link) then return end
    local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if not (open and pcall(open, link)) then ns.Print(link) end
end

-- Pins the item's tooltip on screen, like clicking an item link in chat.
function ns.ViewItem(itemID)
    local shown = ns.Try(function()
        ShowUIPanel(ItemRefTooltip)
        if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
        ItemRefTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not shown then ns.Print(L["Could not show item %d."]:format(itemID)) end
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

-- What the carried bags (backpack, equipped bags, reagent bag) hold: how many of each item, and the first bag
-- holding it. Built on first use and thrown away whenever the bags change.
local bagCounts, bagOfItem

-- Returns false when this client has no bag API we know.
local function ScanBags()
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotInfo = C_Container and C_Container.GetContainerItemInfo
    if not numSlots or not (slotInfo or (GetContainerItemID and GetContainerItemInfo)) then return false end
    local counts, bags = {}, {}
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4 do
        for slot = 1, numSlots(bag) or 0 do
            local itemID, count
            if slotInfo then
                local info = slotInfo(bag, slot)
                if info then itemID, count = info.itemID, info.stackCount end
            else
                itemID = GetContainerItemID(bag, slot)
                if itemID then count = select(2, GetContainerItemInfo(bag, slot)) end
            end
            if itemID then
                counts[itemID] = (counts[itemID] or 0) + (count or 1)
                bags[itemID] = bags[itemID] or bag
            end
        end
    end
    bagCounts, bagOfItem = counts, bags
    return true
end

-- Returns how many of the item the carried bags hold, and the first bag holding it. Returns nil when this
-- client has no bag API we know, so the answer is unknown.
function ns.BagCount(itemID)
    if not bagCounts and not ScanBags() then return nil end
    return bagCounts[itemID] or 0, bagOfItem[itemID]
end

-- Opens the bags and filters them to the item, the same as typing its name into the bag search box: every
-- other item is dimmed. The filter stays until the search box is cleared or the bags are closed.
function ns.LocateItem(itemID)
    local note = ns.GetNote(itemID)
    local name = ns.ItemInfo(itemID) or (note and note.name)
    if not name then
        ns.Print(L["Item data is still loading. Try again in a moment."])
        return
    end
    local count, bag = ns.BagCount(itemID)
    if count == 0 then
        ns.Print(L["%s is not in your bags."]:format(name))
        return
    end
    local filtered = false
    ns.Try(function()
        if OpenAllBags then OpenAllBags() end
        -- With separate bags, OpenAllBags leaves things alone when any bag is already open.
        if bag and OpenBag and IsBagOpen and not IsBagOpen(bag) then OpenBag(bag) end
        -- Filling the search box shows the player what is filtering their bags, and how to clear it.
        if BagItemSearchBox and BagItemSearchBox.SetText then BagItemSearchBox:SetText(name) end
        -- The box applies the search itself; this covers clients and bag frames without it.
        local setSearch = (C_Container and C_Container.SetItemSearch) or SetItemSearch
        if setSearch then
            setSearch(name)
            filtered = true
        end
    end)
    if not filtered then ns.Print(L["Could not search your bags for %s."]:format(name)) end
end

function ns.PinLabel(pin)
    local name = pin.name or ns.MapName(pin.mapID) or L["Map %s"]:format(tostring(pin.mapID))
    return string.format("%s (%.1f, %.1f)", name, pin.x * 100, pin.y * 100)
end

-- ---------------------------------------------------------------------------
-- Quests
-- ---------------------------------------------------------------------------

function ns.QuestTitle(questID)
    local title
    if C_QuestLog then
        if C_QuestLog.GetTitleForQuestID then
            title = C_QuestLog.GetTitleForQuestID(questID)
        elseif C_QuestLog.GetQuestInfo then
            title = C_QuestLog.GetQuestInfo(questID)
        end
    end
    return PublicString(title) and title ~= "" and title or nil
end

function ns.QuestLabel(quest)
    return quest.title or L["Quest #%d"]:format(quest.id)
end

-- Returns a description of the quest's state and, when it is in the quest log, its log index.
function ns.QuestStatus(questID)
    local index
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        index = C_QuestLog.GetLogIndexForQuestID(questID)
    elseif GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(questID)
    end
    if index and index > 0 then return L["in your quest log"], index end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return L["completed"]
    end
    return L["not in your quest log"]
end

-- Opens the quest log at the quest. Returns false when this client has no quest log UI we know.
local function ShowQuestInLog(questID, index)
    if QuestMapFrame_OpenToQuestDetails then
        QuestMapFrame_OpenToQuestDetails(questID)
        return true
    elseif QuestLogFrame then
        ShowUIPanel(QuestLogFrame)
        if QuestLog_SetSelection then QuestLog_SetSelection(index) end
        return true
    end
    return false
end

function ns.OpenQuest(quest)
    local status, index = ns.QuestStatus(quest.id)
    if index then
        local shown = false
        ns.Try(function() shown = ShowQuestInLog(quest.id, index) end)
        if shown then return end
    end
    ns.Print(L["%s (quest %d) is %s."]:format(quest.title or L["Quest"], quest.id, status))
end

-- ---------------------------------------------------------------------------
-- Map pins
-- ---------------------------------------------------------------------------

function ns.OpenPin(pin)
    local label = ns.PinLabel(pin)
    local title = pin.title or label
    if TomTom and TomTom.AddWaypoint then
        -- Third-party API: its failures must not stop the map from opening.
        pcall(function()
            if TomTom.WaypointExists and TomTom:WaypointExists(pin.mapID, pin.x, pin.y, title) then return end
            TomTom:AddWaypoint(pin.mapID, pin.x, pin.y, { title = title, from = ns.title })
        end)
    elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint then
        ns.Try(function()
            if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(pin.mapID) then return end
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x, pin.y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end)
    end
    local opened = ns.Try(function()
        if OpenWorldMap then
            OpenWorldMap(pin.mapID)
        else
            ShowUIPanel(WorldMapFrame)
            WorldMapFrame:SetMapID(pin.mapID)
        end
    end)
    if not opened then ns.Print(L["Location: %s"]:format(label)) end
end

-- Returns a pin for the Blizzard map waypoint (ctrl-click on the world map), if the client has one.
function ns.GetUserWaypointPin()
    if not (C_Map and C_Map.GetUserWaypoint) then return nil end
    local point = C_Map.GetUserWaypoint()
    if not point or not point.position then return nil end
    local x, y = point.position:GetXY()
    if not (PublicNumber(point.uiMapID) and PublicNumber(x) and PublicNumber(y)) then return nil end
    return { mapID = point.uiMapID, x = x, y = y, name = ns.MapName(point.uiMapID) }
end

-- ---------------------------------------------------------------------------
-- Database
-- ---------------------------------------------------------------------------

local listeners = {}

function ns.OnChanged(callback)
    listeners[#listeners + 1] = callback
end

local function FireChanged()
    for _, callback in ipairs(listeners) do callback() end
end

local function StringOrNil(value)
    return type(value) == "string" and value or nil
end

local function NumberOrNil(value)
    return type(value) == "number" and value or nil
end

-- Returns list itself when every entry passes validate, otherwise a copy without the bad entries.
local function CleanList(list, validate)
    if type(list) ~= "table" then return {} end
    local clean
    for index, entry in ipairs(list) do
        local valid = type(entry) == "table" and validate(entry)
        if clean then
            if valid then clean[#clean + 1] = entry end
        elseif not valid then
            clean = {}
            for kept = 1, index - 1 do clean[kept] = list[kept] end
        end
    end
    return clean or list
end

local function ValidQuestRef(quest)
    quest.title = StringOrNil(quest.title)
    return IsID(quest.id)
end

local function ValidPinRef(pin)
    pin.name, pin.title = StringOrNil(pin.name), StringOrNil(pin.title)
    return type(pin.mapID) == "number" and type(pin.x) == "number" and type(pin.y) == "number"
end

local function ValidItemRef(item)
    item.name, item.quality = StringOrNil(item.name), NumberOrNil(item.quality)
    return IsID(item.id)
end

-- A reference to another item's note: just that item's ID.
local function ValidNoteRef(ref)
    return IsID(ref.id)
end

local function HasNoteRef(refs, itemID)
    for _, ref in ipairs(refs) do
        if ref.id == itemID then return true end
    end
    return false
end

local function RemoveNoteRef(refs, itemID)
    for index = #refs, 1, -1 do
        if refs[index].id == itemID then table.remove(refs, index) end
    end
end

-- Drops the note's references to itself and to notes that do not exist, and any repeated reference.
local function CleanNoteRefs(db, itemID, note)
    local refs, seen = note.notes, {}
    for index = #refs, 1, -1 do
        local target = refs[index].id
        if target == itemID or seen[target] or not db.notes[target] then
            table.remove(refs, index)
        else
            seen[target] = true
        end
    end
end

-- References between notes go both ways. Makes every note that this one lists point back at it, and with
-- exclusive set, removes the reference to it from every note it does not list.
local function MirrorNoteRefs(db, itemID, note, exclusive)
    local linked = {}
    for _, ref in ipairs(note.notes) do linked[ref.id] = true end
    for otherID, other in pairs(db.notes) do
        if otherID ~= itemID then
            if linked[otherID] then
                if not HasNoteRef(other.notes, itemID) then other.notes[#other.notes + 1] = { id = itemID } end
            elseif exclusive then
                RemoveNoteRef(other.notes, itemID)
            end
        end
    end
end

-- Makes sure every stored note has the shape the UI expects, so a damaged or hand-edited saved-variables file
-- cannot cause errors later. Entries that are not notes at all are moved to db.invalid rather than deleted.
local function SanitizeNotes(db)
    local invalid
    for itemID, note in pairs(db.notes) do
        if IsID(itemID) and type(note) == "table" then
            note.text = type(note.text) == "string" and note.text or ""
            note.created, note.updated = NumberOrNil(note.created), NumberOrNil(note.updated)
            note.char, note.name = StringOrNil(note.char), StringOrNil(note.name)
            note.quality = NumberOrNil(note.quality)
            if type(note.icon) ~= "number" and type(note.icon) ~= "string" then note.icon = nil end
            if type(note.loc) ~= "table" then
                note.loc = nil
            else
                local loc = note.loc
                loc.zone, loc.subzone = StringOrNil(loc.zone), StringOrNil(loc.subzone)
                loc.mapID, loc.x, loc.y = NumberOrNil(loc.mapID), NumberOrNil(loc.x), NumberOrNil(loc.y)
            end
            note.quests = CleanList(note.quests, ValidQuestRef)
            note.pins = CleanList(note.pins, ValidPinRef)
            note.items = CleanList(note.items, ValidItemRef)
            note.notes = CleanList(note.notes, ValidNoteRef)
        else
            invalid = invalid or {}
            invalid[#invalid + 1] = itemID
        end
    end
    if invalid then
        if type(db.invalid) ~= "table" then db.invalid = {} end
        for _, key in ipairs(invalid) do
            db.invalid[tostring(key)] = db.notes[key]
            db.notes[key] = nil
        end
    end
    -- Only once every note is known to be valid can references between them be checked.
    for itemID, note in pairs(db.notes) do
        CleanNoteRefs(db, itemID, note)
    end
    -- A reference stored on one side only (older data, or a hand-edited file) gains its other side.
    for itemID, note in pairs(db.notes) do
        MirrorNoteRefs(db, itemID, note, false)
    end
end

function ns.GetNote(itemID)
    return ns.db and ns.db.notes[itemID]
end

function ns.CacheItemInfo(itemID, note)
    local name, link, quality, icon = ns.ItemInfo(itemID)
    if name then note.name = name end
    if quality then note.quality = quality end
    if icon then note.icon = icon end
    return note.name, link, note.quality, note.icon
end

-- Creates or updates a note. Location, character and creation time are recorded once, when the note is created.
-- notes lists references to other items' notes, as { id = itemID } entries. Those go both ways: each note
-- listed gains a reference back to this one, and a note no longer listed loses its reference to this one.
function ns.SaveNote(itemID, text, quests, pins, items, notes)
    local note = ns.db.notes[itemID]
    local now = time()
    if not note then
        note = {
            created = now,
            loc = ns.CaptureLocation(),
            char = (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?"),
        }
        ns.db.notes[itemID] = note
    end
    note.text = text or ""
    note.updated = now
    note.quests = quests or note.quests or {}
    note.pins = pins or note.pins or {}
    note.items = items or note.items or {}
    note.notes = notes or note.notes or {}
    CleanNoteRefs(ns.db, itemID, note)
    MirrorNoteRefs(ns.db, itemID, note, true)
    ns.CacheItemInfo(itemID, note)
    FireChanged()
    return note
end

-- Deletes a note, and with it every reference other notes hold to it.
function ns.DeleteNote(itemID)
    if not ns.db.notes[itemID] then return end
    ns.db.notes[itemID] = nil
    for _, note in pairs(ns.db.notes) do
        RemoveNoteRef(note.notes, itemID)
    end
    FireChanged()
end

StaticPopupDialogs["ITEMNOTES_DELETE"] = {
    text = L["Delete the note for %s?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, itemID) ns.DeleteNote(itemID) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ns.ConfirmDelete(itemID)
    local note = ns.GetNote(itemID)
    if not note then return end
    StaticPopup_Show("ITEMNOTES_DELETE", ns.ItemName(itemID, note.name), nil, itemID)
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

-- Tooltips show only the note text. Location, time and references live in the Item Notes window.
local function AddNoteLines(tooltip, itemID)
    local note = ns.GetNote(itemID)
    if not note or not note.text or note.text == "" then return end
    tooltip:AddLine(" ")
    tooltip:AddLine(L["Item Note"], 1, 0.82, 0)
    tooltip:AddLine(note.text, 1, 1, 1, true)
end

local function ItemIDFromLink(link)
    return PublicString(link) and tonumber(link:match("item:(%d+)")) or nil
end

local function OnTooltipData(tooltip, data)
    if not ns.db or not tooltip or not tooltip.AddLine then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    local itemID = data and PublicNumber(data.id) and data.id
    if itemID then AddNoteLines(tooltip, itemID) end
end

local function OnTooltipSetItem(tooltip)
    if not ns.db or not tooltip.GetItem then return end
    local _, link = tooltip:GetItem()
    local itemID = ItemIDFromLink(link)
    if itemID then AddNoteLines(tooltip, itemID) end
end

if TooltipDataProcessor and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, OnTooltipData)
else
    for _, tooltip in ipairs({ GameTooltip, ItemRefTooltip, ShoppingTooltip1, ShoppingTooltip2 }) do
        if tooltip and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", OnTooltipSetItem)
        end
    end
end

-- Returns the item ID of whatever item GameTooltip is currently showing.
function ns.HoveredItem()
    local tooltip = GameTooltip
    if not tooltip or not tooltip:IsShown() then return nil end
    if TooltipUtil and TooltipUtil.GetDisplayedItem then
        local ok, _, link, itemID = pcall(TooltipUtil.GetDisplayedItem, tooltip)
        if ok then
            if PublicNumber(itemID) then return itemID end
            local fromLink = ItemIDFromLink(link)
            if fromLink then return fromLink end
        end
    end
    if tooltip.GetItem then
        local ok, _, link = pcall(tooltip.GetItem, tooltip)
        local fromLink = ok and ItemIDFromLink(link)
        if fromLink then return fromLink end
    end
    if tooltip.GetPrimaryTooltipData and Enum and Enum.TooltipDataType then
        local data = tooltip:GetPrimaryTooltipData()
        if data and data.type == Enum.TooltipDataType.Item and PublicNumber(data.id) then return data.id end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

function ItemNotes_EditHovered()
    if not ns.db then return end
    local itemID = ns.HoveredItem()
    if not itemID then
        ns.Print(L["Hover over an item first, then press the keybind."])
        return
    end
    ns.OpenEditor(itemID)
end

function ItemNotes_Toggle()
    if ns.db then ns.ToggleBrowser() end
end

function ItemNotes_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        ns.OpenOptions()
    else
        ItemNotes_Toggle()
    end
end

SLASH_ITEMNOTES1 = "/itemnotes"
SLASH_ITEMNOTES2 = "/inote"
SLASH_ITEMNOTES3 = "/inotes"
SlashCmdList.ITEMNOTES = function(message)
    local input = ns.Trim(message)
    local command = input:lower()
    if command == "options" or command == "config" or command == "settings" then
        ns.OpenOptions()
        return
    end
    -- "/inote <item link or ID>" opens the editor for that item. Only plain digits count as an ID.
    local idText = input:match("item:(%d+)") or input:match("^%d+$")
    if not idText then
        ItemNotes_Toggle()
        return
    end
    local itemID = tonumber(idText)
    if ns.ItemExists(itemID) then
        ns.OpenEditor(itemID)
    else
        ns.Print(L["There is no item with ID %s."]:format(idText))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- Fires once after a batch of bag changes. Clients without it get the per-bag event instead.
if not pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED") then events:RegisterEvent("BAG_UPDATE") end
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        if type(ItemNotesDB) ~= "table" then ItemNotesDB = {} end
        local db = ItemNotesDB
        if type(db.notes) ~= "table" then db.notes = {} end
        SanitizeNotes(db)
        -- Never held anything; dropped from the schema.
        db.settings = nil
        db.version = DB_VERSION
        ns.db = db
    elseif event == "GET_ITEM_INFO_RECEIVED" and ns.db and PublicNumber(arg1) then
        -- Item data arrived from the server: fill in the cached name/icon for notes that lacked it.
        local note = ns.db.notes[arg1]
        if note and not note.name then
            ns.CacheItemInfo(arg1, note)
            if note.name then FireChanged() end
        end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        -- The open windows show bag counts, so they refresh as if a note had changed.
        bagCounts, bagOfItem = nil, nil
        if ns.db then FireChanged() end
    end
end)
