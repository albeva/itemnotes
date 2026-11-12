local addonName, ns = ...
local L = ns.L

ns.title = L["Item Notes"]
ns.FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
-- The addon's own icon (Media\icon.tga). Built from the folder name so it survives a renamed folder.
ns.ICON = "Interface\\AddOns\\" .. addonName .. "\\Media\\icon"

BINDING_HEADER_ITEMNOTES = ns.title
BINDING_NAME_ITEMNOTES_EDIT = L["Add / edit note for hovered item"]
BINDING_NAME_ITEMNOTES_TOGGLE = L["Open Item Notes window"]

local MAX_ID = 2147483647

-- Game API that moved between client versions, looked up once.
local GetItemInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetItemInfoInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant

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

-- Only the first argument is passed on: callers hand over gsub results, which carry a count.
function ns.Trim(text)
    return strtrim(text or "")
end

function ns.FormatTime(timestamp)
    return timestamp and date("%Y-%m-%d %H:%M", timestamp) or ""
end

-- Rounds a map coordinate (a fraction of the map's size) to what is worth storing: about a yard.
local function RoundCoord(value)
    return math.floor(value * 10000 + 0.5) / 10000
end

-- Returns name, link, quality, icon straight from the client. Any of them may be nil until the client has
-- the item's data; asking makes it request that data from the server.
function ns.ItemInfo(itemID)
    local name, link, quality, icon
    if GetItemInfo then
        local n, l, q, _, _, _, _, _, _, i = GetItemInfo(itemID)
        name, link, quality, icon = n, l, q, i
    end
    if not icon and GetItemInfoInstant then icon = select(5, GetItemInfoInstant(itemID)) end
    return name, link, quality, icon
end

-- Whether the client knows an item with this ID. Answers from the local item database, without a server request.
function ns.ItemExists(itemID)
    if not IsID(itemID) then return false end
    if not GetItemInfoInstant then return true end
    return GetItemInfoInstant(itemID) ~= nil
end

-- The item's icon, from the local item database.
function ns.ItemIcon(itemID)
    local icon = GetItemInfoInstant and select(5, GetItemInfoInstant(itemID))
    return icon or ns.FALLBACK_ICON
end

-- Returns the item's name, or a placeholder while it is not known, and its quality when that is known.
function ns.ItemName(itemID)
    local name, quality = ns.ItemDisplay(itemID)
    return name or L["Item #%d"]:format(itemID), quality
end

function ns.MapName(mapID)
    local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    return info and info.name or nil
end

function ns.CaptureLocation()
    local zone = GetRealZoneText and GetRealZoneText() or nil
    local subzone = GetSubZoneText and GetSubZoneText() or nil
    local loc = {
        zone = PublicString(zone) and zone ~= "" and zone or nil,
        subzone = PublicString(subzone) and subzone ~= "" and subzone or nil,
    }
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if IsID(mapID) then
        loc.mapID = mapID
        -- Position is unavailable inside instances.
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID, "player")
        if pos and not IsSecret(pos) then
            local x, y = pos:GetXY()
            if PublicNumber(x) and PublicNumber(y) then
                loc.x, loc.y = RoundCoord(x), RoundCoord(y)
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

-- Wowhead database for the Forever client. kind is "item", "quest", "spell" (a crafting recipe is a spell too)
-- or "npc".
function ns.WowheadURL(kind, id)
    return "https://www.wowhead.com/forever/" .. kind .. "=" .. id
end

-- Returns the item's name in its quality colour, and the plain name.
function ns.ColoredItemName(itemID)
    local plain, quality = ns.ItemName(itemID)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    return ((color and color.hex) or "|cffffffff") .. plain .. "|r", plain
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

-- Pins the tooltip of a link ("item:123", "spell:456") on screen, like clicking that link in chat. Returns
-- false when the client could not show it.
local function PinTooltip(link)
    return ns.Try(function()
        ShowUIPanel(ItemRefTooltip)
        if not ItemRefTooltip:IsShown() then ItemRefTooltip:SetOwner(UIParent, "ANCHOR_PRESERVE") end
        ItemRefTooltip:SetHyperlink(link)
    end)
end

function ns.ViewItem(itemID)
    if not PinTooltip("item:" .. itemID) then ns.Print(L["Could not show item %d."]:format(itemID)) end
end

-- ---------------------------------------------------------------------------
-- Bags
-- ---------------------------------------------------------------------------

-- What the carried bags (backpack, equipped bags, reagent bag) hold: how many of each item, and the first bag
-- and slot holding it. Built on first use and thrown away whenever the bags change.
local bagCounts, bagOfItem, slotOfItem

-- Returns false when this client has no bag API we know.
local function ScanBags()
    local numSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local slotInfo = C_Container and C_Container.GetContainerItemInfo
    if not numSlots or not (slotInfo or (GetContainerItemID and GetContainerItemInfo)) then return false end
    local counts, bags, slots = {}, {}, {}
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
                if not bags[itemID] then bags[itemID], slots[itemID] = bag, slot end
            end
        end
    end
    bagCounts, bagOfItem, slotOfItem = counts, bags, slots
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
    local name = ns.ItemDisplay(itemID)
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
    local name = ns.MapName(pin.mapID) or L["Map %s"]:format(tostring(pin.mapID))
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

-- The quest's title, or nil when it was never seen. The client only knows the title of a quest that is at
-- hand, so a title is remembered once seen, and the client is only asked for one that is not.
local function KnownQuestTitle(questID)
    local title = ns.CachedName("quests", questID)
    if not title then
        title = ns.QuestTitle(questID)
        ns.Remember("quests", questID, title)
    end
    return title
end

function ns.QuestLabel(questID)
    return KnownQuestTitle(questID) or L["Quest #%d"]:format(questID)
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

function ns.OpenQuest(questID)
    local status, index = ns.QuestStatus(questID)
    if index then
        local shown = false
        ns.Try(function() shown = ShowQuestInLog(questID, index) end)
        if shown then return end
    end
    ns.Print(L["%s (quest %d) is %s."]:format(KnownQuestTitle(questID) or L["Quest"], questID, status))
end

-- ---------------------------------------------------------------------------
-- Crafting recipes
-- ---------------------------------------------------------------------------

-- A recipe's ID is the ID of the spell that crafts it.
function ns.RecipeName(recipeID)
    local name
    if C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local info = C_TradeSkillUI.GetRecipeInfo(recipeID)
        name = info and info.name
    end
    return PublicString(name) and name ~= "" and name or ns.SpellName(recipeID)
end

-- Like a quest's title, a recipe's name is remembered once seen.
function ns.RecipeLabel(recipeID)
    local name = ns.CachedName("recipes", recipeID)
    if not name then
        name = ns.RecipeName(recipeID)
        ns.Remember("recipes", recipeID, name)
    end
    return name or L["Recipe #%d"]:format(recipeID)
end

-- Whether the crafting window can show the recipe: only for a character that has the recipe's profession.
function ns.CanOpenRecipe(recipeID)
    if not (C_TradeSkillUI and C_TradeSkillUI.OpenRecipe) then return false end
    if not C_TradeSkillUI.IsRecipeProfessionLearned then return true end
    return C_TradeSkillUI.IsRecipeProfessionLearned(recipeID) == true
end

-- Opens the crafting window at the recipe.
function ns.OpenRecipe(recipeID)
    if ns.CanOpenRecipe(recipeID) and ns.Try(function() C_TradeSkillUI.OpenRecipe(recipeID) end) then return end
    ns.Print(L["%s (recipe %d) needs a profession this character does not have."]
        :format(ns.RecipeLabel(recipeID), recipeID))
end

-- ---------------------------------------------------------------------------
-- Spells
-- ---------------------------------------------------------------------------

function ns.SpellName(spellID)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(spellID)
    elseif GetSpellInfo then
        name = GetSpellInfo(spellID)
    end
    return PublicString(name) and name ~= "" and name or nil
end

-- The client can always name a spell, but a search looks through remembered names only.
function ns.SpellLabel(spellID)
    local name = ns.CachedName("spells", spellID)
    if not name then
        name = ns.SpellName(spellID)
        ns.Remember("spells", spellID, name)
    end
    return name or L["Spell #%d"]:format(spellID)
end

-- Pins the spell's tooltip on screen, like clicking a spell link in chat.
function ns.ViewSpell(spellID)
    if not PinTooltip("spell:" .. spellID) then ns.Print(L["Could not show spell %d."]:format(spellID)) end
end

-- ---------------------------------------------------------------------------
-- NPCs
-- ---------------------------------------------------------------------------

-- The client cannot name an NPC by its ID: the name seen when the NPC was attached is all there is.
function ns.NPCLabel(npcID)
    return ns.CachedName("npcs", npcID) or L["NPC #%d"]:format(npcID)
end

-- Returns the NPC's ID from a unit's GUID, "Creature-0-<server>-<instance>-<zone>-<npcID>-<spawn>", or nil for
-- a GUID that is not an NPC's: a player's, a pet's.
local function NPCFromGUID(guid)
    if not PublicString(guid) then return nil end
    local unitType, id = guid:match("^(%a+)%-%d+%-%d+%-%d+%-%d+%-(%d+)%-%x+$")
    if unitType ~= "Creature" and unitType ~= "Vehicle" then return nil end
    id = tonumber(id)
    return IsID(id) and id or nil
end

-- Returns the ID and, when the client gives it, the name of the NPC under the mouse: in the world, or the one
-- a unit frame or a nameplate stands for.
function ns.HoveredNPC()
    if not UnitGUID then return nil end
    local npcID = NPCFromGUID(UnitGUID("mouseover"))
    if not npcID then return nil end
    local name = UnitName and UnitName("mouseover")
    return npcID, PublicString(name) and name ~= "" and name or nil
end

-- ---------------------------------------------------------------------------
-- Quests an item belongs to
-- ---------------------------------------------------------------------------

-- Item class of quest items (Enum.ItemClass.Questitem).
local QUEST_ITEM_CLASS = 12
-- Most quests attached from a quest database when none of the item's quests is in the quest log.
local MAX_DATABASE_QUESTS = 5

-- The quest the game ties to the item's bag slot: the one it starts, or the active one it belongs to.
local function BagItemQuest(itemID)
    if not bagCounts and not ScanBags() then return nil end
    local bag, slot = bagOfItem[itemID], slotOfItem[itemID]
    if not bag then return nil end
    local questID
    if C_Container and C_Container.GetContainerItemQuestInfo then
        local info = C_Container.GetContainerItemQuestInfo(bag, slot)
        questID = type(info) == "table" and info.questID or nil
    elseif GetContainerItemQuestInfo then
        questID = select(2, GetContainerItemQuestInfo(bag, slot))
    end
    return IsID(questID) and questID or nil
end

-- Calls fn(questID, logIndex) for every quest in the quest log.
local function ForEachLogQuest(fn)
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        for index = 1, C_QuestLog.GetNumQuestLogEntries() or 0 do
            local info = C_QuestLog.GetInfo(index)
            if info and not info.isHeader and not info.isHidden and IsID(info.questID) then
                fn(info.questID, index)
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        for index = 1, GetNumQuestLogEntries() or 0 do
            local _, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(index)
            if not isHeader and IsID(questID) then fn(questID, index) end
        end
    end
end

-- Returns the quest's objectives as a list of { text, type }.
local function QuestObjectives(questID, logIndex)
    if C_QuestLog and C_QuestLog.GetQuestObjectives then
        return C_QuestLog.GetQuestObjectives(questID) or {}
    end
    local objectives = {}
    if GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
        for index = 1, GetNumQuestLeaderBoards(logIndex) or 0 do
            local text, kind = GetQuestLogLeaderBoard(index, logIndex)
            objectives[index] = { text = text, type = kind }
        end
    end
    return objectives
end

-- Whether an objective's text ("Wolf Pelt: 3/8", "3/8 Wolf Pelt") is about exactly this item. Whatever is
-- left after taking out the name and the count must hold no more words, so "Wolf Pelt" does not match
-- "Thick Wolf Pelt: 0/5".
local function ObjectiveNamesItem(text, name)
    if not PublicString(text) then return false end
    local from, to = text:find(name, 1, true)
    if not from then return false end
    local rest = (text:sub(1, from - 1) .. text:sub(to + 1)):gsub("%d+%s*/%s*%d+", "")
    return not rest:find("%w")
end

-- Whether a quest in the log uses the item: as the item it gives the player to use, or as something to collect.
-- Objectives only carry the item's name, so collecting is matched by name; name is nil until the item is cached.
local function LogQuestUsesItem(questID, logIndex, itemID, name)
    if GetQuestLogSpecialItemInfo then
        local link = GetQuestLogSpecialItemInfo(logIndex)
        if PublicString(link) and tonumber(link:match("item:(%d+)")) == itemID then return true end
    end
    if not name then return false end
    for _, objective in ipairs(QuestObjectives(questID, logIndex)) do
        if objective.type == "item" and ObjectiveNamesItem(objective.text, name) then return true end
    end
    return false
end

-- Asks Questie's database, when Questie is loaded, which quests the item starts or is needed for.
-- Returns a list of quest IDs and a function giving a quest's name. Third-party API: any failure means no answer.
local function QuestieQuests(itemID)
    local quests, questieDB = {}, nil
    pcall(function()
        local module = QuestieLoader:ImportModule("QuestieDB")
        if type(module.QueryItemSingle) ~= "function" then return end
        questieDB = module
        local starts = module.QueryItemSingle(itemID, "startQuest")
        if IsID(starts) then quests[#quests + 1] = starts end
        local related = module.QueryItemSingle(itemID, "relatedQuests")
        if type(related) == "table" then
            for _, questID in ipairs(related) do
                if IsID(questID) then quests[#quests + 1] = questID end
            end
        end
    end)
    local function Title(questID)
        local ok, title = pcall(function() return questieDB.QueryQuestSingle(questID, "name") end)
        return ok and type(title) == "string" and title ~= "" and title or nil
    end
    return quests, Title
end

-- Returns the IDs of the quests an item belongs to, ready to attach to a note. The game cannot look up quests
-- by item, so this gathers what is known: the quest tied to the item in the bags, quests in the quest log
-- that use or collect it, and Questie's database when that addon is loaded. A quest that is not in the log
-- can only come from Questie, and is only offered for a quest item none of whose quests is in the log.
function ns.QuestsForItem(itemID)
    local found, seen = {}, {}
    local function Add(questID, title)
        if not IsID(questID) or seen[questID] then return end
        seen[questID] = true
        found[#found + 1] = questID
        -- The title is only at hand now, so it is remembered now.
        ns.Remember("quests", questID, ns.QuestTitle(questID) or title)
    end

    ns.Try(function() Add(BagItemQuest(itemID)) end)
    ns.Try(function()
        local name = ns.ItemInfo(itemID)
        ForEachLogQuest(function(questID, logIndex)
            if LogQuestUsesItem(questID, logIndex, itemID, name) then Add(questID) end
        end)
    end)

    local known, Title = QuestieQuests(itemID)
    for _, questID in ipairs(known) do
        if select(2, ns.QuestStatus(questID)) then Add(questID, Title(questID)) end
    end
    if #found == 0 then
        if GetItemInfoInstant and select(6, GetItemInfoInstant(itemID)) == QUEST_ITEM_CLASS then
            for index = 1, math.min(#known, MAX_DATABASE_QUESTS) do
                Add(known[index], Title(known[index]))
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- Map pins
-- ---------------------------------------------------------------------------

-- Adds a TomTom waypoint for the pin. Returns false when TomTom is not loaded or its call fails.
local function AddTomTomWaypoint(pin, title)
    if type(TomTom) ~= "table" or type(TomTom.AddWaypoint) ~= "function" then return false end
    -- Third-party API: its failures must not stop the map from opening.
    return (pcall(function()
        if TomTom.WaypointExists and TomTom:WaypointExists(pin.mapID, pin.x, pin.y, title) then return end
        TomTom:AddWaypoint(pin.mapID, pin.x, pin.y, { title = title, from = ns.title })
    end))
end

-- Places the Blizzard map pin (the one ctrl-click on the world map sets) and tracks it.
local function SetUserWaypoint(pin)
    if not (C_Map and C_Map.SetUserWaypoint and UiMapPoint) then return end
    ns.Try(function()
        if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(pin.mapID) then return end
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(pin.mapID, pin.x, pin.y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    end)
end

function ns.OpenPin(pin)
    local label = ns.PinLabel(pin)
    -- TomTom takes the waypoint when it is installed; otherwise it goes to the Blizzard map pin.
    if not AddTomTomWaypoint(pin, label) then SetUserWaypoint(pin) end
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
    if not (IsID(point.uiMapID) and PublicNumber(x) and PublicNumber(y)) then return nil end
    return { mapID = point.uiMapID, x = RoundCoord(x), y = RoundCoord(y) }
end

-- Returns a pin for where the player stands, or nil where the game gives no position (inside instances).
function ns.GetPlayerPin()
    local loc = ns.CaptureLocation()
    if not (loc.mapID and loc.x) then return nil end
    return { mapID = loc.mapID, x = loc.x, y = loc.y }
end

-- ---------------------------------------------------------------------------
-- Deleting a note
-- ---------------------------------------------------------------------------

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
    if not ns.GetNote(itemID) then return end
    StaticPopup_Show("ITEMNOTES_DELETE", (ns.ItemName(itemID)), nil, itemID)
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

-- Returns the spell ID of whatever spell GameTooltip is currently showing: a spell in the spellbook, on an
-- action bar, a buff.
function ns.HoveredSpell()
    local tooltip = GameTooltip
    if not tooltip or not tooltip:IsShown() then return nil end
    if tooltip.GetSpell then
        -- Returns name, spellID; older clients return name, rank, spellID.
        local ok, _, second, third = pcall(tooltip.GetSpell, tooltip)
        if ok then
            if IsID(third) then return third end
            if IsID(second) then return second end
        end
    end
    if tooltip.GetPrimaryTooltipData and Enum and Enum.TooltipDataType then
        local data = tooltip:GetPrimaryTooltipData()
        if data and data.type == Enum.TooltipDataType.Spell and IsID(data.id) then return data.id end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Entry points
-- ---------------------------------------------------------------------------

-- Whether the saved notes are loaded. When they could not be, says why: the addon is off for the session.
local function Ready()
    if ns.db then return true end
    if ns.dbProblem then ns.Print(ns.dbProblem) end
    return false
end

function ItemNotes_EditHovered()
    if not Ready() then return end
    local itemID = ns.HoveredItem()
    if not itemID then
        ns.Print(L["Hover over an item first, then press the keybind."])
        return
    end
    ns.OpenEditor(itemID)
end

function ItemNotes_Toggle()
    if Ready() then ns.ToggleBrowser() end
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
    if not Ready() then return end
    if ns.ItemExists(itemID) then
        ns.OpenEditor(itemID)
    else
        ns.Print(L["There is no item with ID %s."]:format(idText))
    end
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- Fires once after a batch of bag changes. Clients without it get the per-bag event instead.
if not pcall(events.RegisterEvent, events, "BAG_UPDATE_DELAYED") then events:RegisterEvent("BAG_UPDATE") end
-- A quest entering or leaving the quest log, or a profession learned or dropped: what decides whether a
-- reference can be opened. Not every client has all of these.
local OPENABLE_EVENTS = {
    QUEST_ACCEPTED = true, QUEST_REMOVED = true, QUEST_TURNED_IN = true, SKILL_LINES_CHANGED = true,
}
for event in pairs(OPENABLE_EVENTS) do pcall(events.RegisterEvent, events, event) end
events:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= addonName then return end
        self:UnregisterEvent("ADDON_LOADED")
        ns.LoadDatabase()
    elseif event == "PLAYER_LOGIN" then
        -- The chat frame is ready by now. The same is said again whenever the addon is asked to do something.
        if ns.dbProblem then ns.Print(ns.dbProblem) end
    elseif not ns.db then
        return
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        -- Item data arrived from the server: a name that was missing may be known now.
        if PublicNumber(arg1) then ns.ItemInfoReceived(arg1) end
    elseif event == "BAG_UPDATE_DELAYED" or event == "BAG_UPDATE" then
        -- The open windows show bag counts.
        bagCounts, bagOfItem, slotOfItem = nil, nil, nil
        ns.QueueChanged("state")
    elseif OPENABLE_EVENTS[event] then
        -- Reference lists show whether a quest or a recipe can be opened.
        ns.QueueChanged("state")
    end
end)
