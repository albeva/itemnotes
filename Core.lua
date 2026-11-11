local addonName, ns = ...

ns.title = "Item Notes"

BINDING_HEADER_ITEMNOTES = "Item Notes"
BINDING_NAME_ITEMNOTES_EDIT = "Add / edit note for hovered item"
BINDING_NAME_ITEMNOTES_TOGGLE = "Open Item Notes window"

local defaults = {}

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

ns.PublicNumber = PublicNumber

function ns.Print(message)
    print("|cffffd100" .. ns.title .. ":|r " .. tostring(message))
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
    if text == "" then text = ns.MapName(loc.mapID) or "Unknown" end
    if loc.x and loc.y then
        text = text .. string.format(" (%.1f, %.1f)", loc.x * 100, loc.y * 100)
    end
    return text
end

-- Where, when and by whom a note was recorded, one fact per line.
-- short drops the realm from the character name, for narrow panes.
function ns.RecordedText(note, short)
    local lines = { "Recorded in " .. ns.LocationText(note.loc) }
    local who = note.char
    if who and short then who = who:match("^(.-) %- ") or who end
    lines[2] = ns.FormatTime(note.created) .. (who and ("  by " .. who) or "")
    if note.updated and note.updated ~= note.created then
        lines[3] = "Edited " .. ns.FormatTime(note.updated)
    end
    return table.concat(lines, "\n")
end

-- Wowhead database for the Forever client. kind is "item" or "quest".
function ns.WowheadURL(kind, id)
    return "https://www.wowhead.com/forever/" .. kind .. "=" .. id
end

-- Returns a quality-coloured name and the plain name for an item reference.
function ns.ItemRefLabel(ref)
    local name, _, quality = ns.ItemInfo(ref.id)
    if name then ref.name = name end
    if quality then ref.quality = quality end
    local plain = ref.name or ("Item #" .. ref.id)
    local color = ref.quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[ref.quality]
    return ((color and color.hex) or "|cffffffff") .. plain .. "|r", plain
end

-- Puts the item's link into the chat input: into the open chat box if there is one, otherwise opens chat with it.
function ns.LinkInChat(itemID)
    local _, link = ns.ItemInfo(itemID)
    if not link then
        ns.Print("Item data is still loading. Try again in a moment.")
        return
    end
    local insert = (ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink
    local inserted = false
    if insert then
        local ok, result = pcall(insert, link)
        inserted = ok and result == true
    end
    if not inserted then
        local open = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
        if not (open and pcall(open, link)) then ns.Print(link) end
    end
end

-- Pins the item's tooltip on screen, like clicking an item link in chat.
function ns.ViewItem(itemID)
    local ok = pcall(function()
        ShowUIPanel(ItemRefTooltip)
        if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
        ItemRefTooltip:SetHyperlink("item:" .. itemID)
    end)
    if not ok then ns.Print("Could not show item " .. itemID .. ".") end
end

function ns.PinLabel(pin)
    local name = pin.name or ns.MapName(pin.mapID) or ("Map " .. tostring(pin.mapID))
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

function ns.QuestLogQuests()
    local quests = {}
    local count = (C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetNumQuestLogEntries())
        or (GetNumQuestLogEntries and GetNumQuestLogEntries()) or 0
    for index = 1, count do
        local title, isHeader, questID
        if C_QuestLog and C_QuestLog.GetInfo then
            local info = C_QuestLog.GetInfo(index)
            if info then title, isHeader, questID = info.title, info.isHeader, info.questID end
        elseif GetQuestLogTitle then
            local t, _, _, header, _, _, _, id = GetQuestLogTitle(index)
            title, isHeader, questID = t, header, id
        end
        if not isHeader and PublicNumber(questID) and questID > 0 and PublicString(title) then
            quests[#quests + 1] = { id = questID, title = title }
        end
    end
    table.sort(quests, function(a, b) return a.title < b.title end)
    return quests
end

function ns.QuestStatus(questID)
    local index
    if C_QuestLog and C_QuestLog.GetLogIndexForQuestID then
        index = C_QuestLog.GetLogIndexForQuestID(questID)
    elseif GetQuestLogIndexByID then
        index = GetQuestLogIndexByID(questID)
    end
    if index and index > 0 then return "in your quest log", index end
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(questID) then
        return "completed"
    end
    return "not in your quest log"
end

function ns.OpenQuest(quest)
    local status, index = ns.QuestStatus(quest.id)
    if index then
        local ok = pcall(function()
            if QuestMapFrame_OpenToQuestDetails then
                QuestMapFrame_OpenToQuestDetails(quest.id)
            elseif QuestLogFrame then
                ShowUIPanel(QuestLogFrame)
                if QuestLog_SetSelection then QuestLog_SetSelection(index) end
            else
                error("no quest log UI")
            end
        end)
        if ok then return end
    end
    ns.Print(string.format("%s (quest %d) is %s.", quest.title or "Quest", quest.id, status))
end

-- ---------------------------------------------------------------------------
-- Map pins
-- ---------------------------------------------------------------------------

function ns.OpenPin(pin)
    local label = ns.PinLabel(pin)
    pcall(function()
        if TomTom and TomTom.AddWaypoint then
            TomTom:AddWaypoint(pin.mapID, pin.x, pin.y, { title = pin.title or label, from = ns.title })
        elseif C_Map and C_Map.SetUserWaypoint and UiMapPoint
            and (not C_Map.CanSetUserWaypointOnMap or C_Map.CanSetUserWaypointOnMap(pin.mapID)) then
            C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x, pin.y))
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                C_SuperTrack.SetSuperTrackedUserWaypoint(true)
            end
        end
    end)
    local opened = pcall(function()
        if OpenWorldMap then
            OpenWorldMap(pin.mapID)
        else
            ShowUIPanel(WorldMapFrame)
            WorldMapFrame:SetMapID(pin.mapID)
        end
    end)
    if not opened then ns.Print("Location: " .. label) end
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
function ns.SaveNote(itemID, text, quests, pins, items)
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
    ns.CacheItemInfo(itemID, note)
    FireChanged()
    return note
end

function ns.DeleteNote(itemID)
    if ns.db.notes[itemID] then
        ns.db.notes[itemID] = nil
        FireChanged()
    end
end

StaticPopupDialogs["ITEMNOTES_DELETE"] = {
    text = "Delete the note for %s?",
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
    StaticPopup_Show("ITEMNOTES_DELETE", note.name or ("item " .. itemID), nil, itemID)
end

-- ---------------------------------------------------------------------------
-- Tooltip
-- ---------------------------------------------------------------------------

-- Tooltips show only the note text. Location, time and references live in the Item Notes window.
local function AddNoteLines(tooltip, itemID)
    local note = ns.GetNote(itemID)
    if not note or not note.text or note.text == "" then return end
    tooltip:AddLine(" ")
    tooltip:AddLine("Item Note", 1, 0.82, 0)
    tooltip:AddLine(note.text, 1, 1, 1, true)
end

local function ItemIDFromLink(link)
    return PublicString(link) and tonumber(link:match("item:(%d+)")) or nil
end

local function OnTooltipData(tooltip, data)
    if not ns.db or not tooltip or not tooltip.AddLine then return end
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
        ns.Print("Hover over an item first, then press the keybind.")
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
    -- "/inote <item link or ID>" opens the editor for that item.
    local itemID = tonumber(input:match("item:(%d+)")) or tonumber(input)
    if itemID and itemID > 0 then
        ns.OpenEditor(itemID)
    else
        ItemNotes_Toggle()
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        if type(ItemNotesDB) ~= "table" then ItemNotesDB = {} end
        local db = ItemNotesDB
        db.version = db.version or 1
        if type(db.notes) ~= "table" then db.notes = {} end
        if type(db.settings) ~= "table" then db.settings = {} end
        for key, value in pairs(defaults) do
            if db.settings[key] == nil then db.settings[key] = value end
        end
        ns.db = db
    elseif ns.db and PublicNumber(arg1) then
        -- Item data arrived from the server: fill in the cached name/icon for notes that lacked it.
        local note = ns.db.notes[arg1]
        if note and not note.name then
            ns.CacheItemInfo(arg1, note)
            if note.name then FireChanged() end
        end
    end
end)
