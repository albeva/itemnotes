local _, ns = ...
local L = ns.L

local editor

-- Unsaved edits from an editor that was closed without Save or Cancel (Escape, the close button).
-- They come back the next time the same item is opened, so a stray Escape never loses typing.
local draft
-- Set by Save, Cancel and Delete: the editor is closing on purpose, so nothing is kept as a draft.
local closing = false

local function CopyList(list)
    local copy = {}
    for index, entry in ipairs(list or {}) do
        local item = {}
        for key, value in pairs(entry) do item[key] = value end
        copy[index] = item
    end
    return copy
end

-- Line breaks (from notes written with the earlier multi-line editor) become spaces in the single-line box.
local function SingleLine(text)
    return ns.Trim((text or ""):gsub("%s*\n%s*", " "))
end

local function IsDirty()
    return editor.refsChanged or ns.Trim(editor.edit:GetText()) ~= editor.originalText
end

-- ---------------------------------------------------------------------------
-- References (items, other notes, quests and map pins) being edited
-- ---------------------------------------------------------------------------

local function RefreshRefs()
    -- A referenced note can be deleted while the editor is open, or while a draft waits: drop it here too.
    for index = #editor.notes, 1, -1 do
        if not ns.GetNote(editor.notes[index].id) then table.remove(editor.notes, index) end
    end
    local items = ns.RefItems(editor.quests, editor.pins, editor.items, editor.notes)
    editor.refs:SetItems(items)
    editor.noRefs:SetShown(#items == 0)
end

-- The count on the item's icon and the Locate button follow what is in the bags.
local function RefreshBagInfo()
    ns.SetIconCount(editor.icon, editor.itemID)
    editor.locate:UpdateForItem()
end

local function RefsChanged()
    editor.refsChanged = true
    RefreshRefs()
end

local function RemoveRef(item)
    local lists = { quest = editor.quests, pin = editor.pins, item = editor.items, note = editor.notes }
    table.remove(lists[item.kind], item.index)
    RefsChanged()
end

-- Returns the position of the reference to itemID's note in a list of note references, or nil.
local function FindNoteRef(list, itemID)
    for index, ref in ipairs(list) do
        if ref.id == itemID then return index end
    end
    return nil
end

-- Attaches another item's note. Only an existing note can be referenced, and never the one being edited.
-- Saving makes the reference two-way: the other note then lists this one too.
local function AddNote(itemID)
    if itemID == editor.itemID or not ns.GetNote(itemID) then return end
    if FindNoteRef(editor.notes, itemID) then return end
    editor.notes[#editor.notes + 1] = { id = itemID }
    RefsChanged()
end

local function AddItem(itemID)
    if itemID == editor.itemID then return end
    for _, item in ipairs(editor.items) do
        if item.id == itemID then return end
    end
    local name, _, quality = ns.ItemInfo(itemID)
    editor.items[#editor.items + 1] = { id = itemID, name = name, quality = quality }
    RefsChanged()
end

-- Attaches the item currently held on the cursor (dragged from a bag, for example).
local function TakeCursorItem()
    local kind, itemID = GetCursorInfo()
    if kind == "item" and type(itemID) == "number" then
        ClearCursor()
        AddItem(itemID)
    end
end

local function AddQuest(questID)
    for _, quest in ipairs(editor.quests) do
        if quest.id == questID then return end
    end
    editor.quests[#editor.quests + 1] = { id = questID, title = ns.QuestTitle(questID) }
    RefsChanged()
end

local function AddPin(pin, problem)
    if not pin then
        ns.Print(problem)
        return
    end
    for _, existing in ipairs(editor.pins) do
        if existing.mapID == pin.mapID and math.abs(existing.x - pin.x) < 0.002 and math.abs(existing.y - pin.y) < 0.002 then
            return
        end
    end
    editor.pins[#editor.pins + 1] = pin
    RefsChanged()
end

-- ---------------------------------------------------------------------------
-- Shift-click a quest (tracker, quest log, Questie tracker) to attach it
-- ---------------------------------------------------------------------------

local function ValidQuestID(value, mustBeInLog)
    if not ns.IsID(value) then return false end
    local _, logIndex = ns.QuestStatus(value)
    if logIndex then return true end
    return not mustBeInLog and ns.QuestTitle(value) ~= nil
end

-- Walks up from the frame under the mouse looking for something that carries a quest ID.
local function QuestIDUnderMouse()
    local focus
    if GetMouseFoci then
        local foci = GetMouseFoci()
        focus = foci and foci[1]
    elseif GetMouseFocus then
        focus = GetMouseFocus()
    end
    local chain, inTracker = {}, false
    while focus and #chain < 8 do
        if focus == editor or focus == WorldFrame or focus == UIParent then break end
        if focus.IsForbidden and focus:IsForbidden() then break end
        chain[#chain + 1] = focus
        if focus == ObjectiveTrackerFrame or focus == QuestObjectiveTracker or focus == WatchFrame
            or focus.parentModule ~= nil then
            inTracker = true
        end
        focus = focus.GetParent and focus:GetParent() or nil
    end
    for _, frame in ipairs(chain) do
        -- Quest log entries and map quest pins.
        if ValidQuestID(frame.questID) then return frame.questID end
        -- Questie tracker lines.
        local questie = frame.Quest
        if type(questie) == "table" and ValidQuestID(questie.Id) then return questie.Id end
        -- Classic-style quest log buttons.
        if ns.PublicNumber(frame.questLogIndex) and C_QuestLog and C_QuestLog.GetQuestIDForLogIndex then
            local questID = C_QuestLog.GetQuestIDForLogIndex(frame.questLogIndex)
            if ValidQuestID(questID) then return questID end
        end
        -- Objective tracker blocks keep the quest ID in .id; only trust it for quests in the log.
        if inTracker and ValidQuestID(frame.id, true) then return frame.id end
    end
    return nil
end

local function IsWatched(questID)
    if C_QuestLog and C_QuestLog.GetQuestWatchType then
        return C_QuestLog.GetQuestWatchType(questID) ~= nil
    end
    return nil
end

-- Blizzard's own shift-click toggles quest tracking when no chat box is open. Put the tracking state back.
local function RestoreWatch(questID, wasWatched)
    if wasWatched == nil or IsWatched(questID) == wasWatched then return end
    ns.Try(function()
        if wasWatched then
            C_QuestLog.AddQuestWatch(questID)
        else
            C_QuestLog.RemoveQuestWatch(questID)
        end
    end)
end

-- Blizzard's own shift-click on a stack opens the split-stack prompt. The click was meant for us: close it.
local function HideStackSplit()
    if StackSplitFrame and StackSplitFrame:IsShown() then StackSplitFrame:Hide() end
end

local pendingQuest, pendingWatched
local pendingItem = false

local function OnGlobalMouse(_, event, button)
    if event == "GLOBAL_MOUSE_DOWN" then
        pendingQuest, pendingItem = nil, false
        if button ~= "LeftButton" or not IsShiftKeyDown() then return end
        local ok, questID = pcall(QuestIDUnderMouse)
        if ok and questID then
            pendingQuest, pendingWatched = questID, IsWatched(questID)
            AddQuest(questID)
        elseif not editor:IsMouseOver() then
            -- A note in the Item Notes window is attached as a note, not as its bare item.
            local noteID = ns.HoveredNote()
            if noteID then
                AddNote(noteID)
                return
            end
            -- Not a quest: attach whatever item the mouse is hovering (bag slot, quest reward, list row...).
            local itemID = ns.HoveredItem()
            if itemID then
                AddItem(itemID)
                pendingItem = true
            end
        end
    elseif event == "GLOBAL_MOUSE_UP" then
        -- Mouse released: the clicked frame's own handler has run by the next frame. Undo its side effects.
        if pendingQuest then
            local questID, wasWatched = pendingQuest, pendingWatched
            pendingQuest = nil
            C_Timer.After(0.05, function() RestoreWatch(questID, wasWatched) end)
        end
        if pendingItem then
            pendingItem = false
            C_Timer.After(0.05, HideStackSplit)
        end
    end
end

-- ---------------------------------------------------------------------------
-- Editor window
-- ---------------------------------------------------------------------------

-- Hides the editor on purpose (Save, Cancel, Delete), discarding whatever was being edited.
local function Close()
    closing = true
    editor:Hide()
end

local function Save()
    local itemID = editor.itemID
    local text = ns.Trim(editor.edit:GetText())
    if text == "" and #editor.quests == 0 and #editor.pins == 0 and #editor.items == 0 and #editor.notes == 0 then
        -- Nothing left to keep: an emptied note is removed.
        ns.DeleteNote(itemID)
    else
        ns.SaveNote(itemID, text, editor.quests, editor.pins, editor.items, editor.notes)
        if draft then
            -- Unsaved edits wait for another item. References go both ways, so a link to that item made or
            -- removed here must show in them too, or saving them later would undo it.
            local index = FindNoteRef(draft.notes, itemID)
            if FindNoteRef(editor.notes, draft.itemID) then
                if not index then draft.notes[#draft.notes + 1] = { id = itemID } end
            elseif index then
                table.remove(draft.notes, index)
            end
        end
    end
    Close()
end

StaticPopupDialogs["ITEMNOTES_DISCARD"] = {
    text = L["Discard your unsaved changes to the note for %s?"],
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, itemID) ns.OpenEditor(itemID, true) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function CreateEditor()
    editor = ns.CreateWindow("ItemNotesEditor", UIParent, 440, 350, L["Item Note"])
    editor:SetPoint("CENTER", 0, 40)
    editor:SetFrameStrata("DIALOG")
    table.insert(UISpecialFrames, "ItemNotesEditor")

    -- Item header
    editor.icon = ns.CreateIcon(editor, 40)
    editor.icon:SetPoint("TOPLEFT", 14, -30)
    editor.icon:EnableMouse(true)
    editor.icon:SetScript("OnEnter", function(self) ns.ShowItemTooltip(self, editor.itemID) end)
    editor.icon:SetScript("OnLeave", GameTooltip_Hide)

    editor.name = ns.Text(editor, "large")
    editor.name:SetPoint("TOPLEFT", editor.icon, "TOPRIGHT", 10, -3)
    editor.name:SetPoint("RIGHT", -14, 0)
    editor.name:SetWordWrap(false)

    editor.meta = ns.Text(editor, "small", "muted")
    editor.meta:SetPoint("TOPLEFT", editor.name, "BOTTOMLEFT", 0, -4)

    local wowhead = ns.CreateWowheadButton(editor, function() return editor.itemID end)
    wowhead:SetPoint("LEFT", editor.meta, "RIGHT", 10, 0)
    local chatLink = ns.CreateChatLinkButton(editor, function() return editor.itemID end)
    chatLink:SetPoint("LEFT", wowhead, "RIGHT", 4, 0)
    editor.locate = ns.CreateLocateButton(editor, function() return editor.itemID end)
    editor.locate:SetPoint("LEFT", chatLink, "RIGHT", 4, 0)

    -- Dropping an item anywhere on the window attaches it as a reference.
    editor:SetScript("OnReceiveDrag", TakeCursorItem)
    editor:SetScript("OnMouseUp", TakeCursorItem)

    -- Note text: the standard single-line input box. Enter saves.
    local noteLabel = ns.Caption(editor, L["Note"])
    noteLabel:SetPoint("TOPLEFT", 14, -78)
    local hint = ns.Text(editor, "small", "muted")
    hint:SetPoint("TOPRIGHT", -14, -79)
    hint:SetText(L["Enter saves"])

    local edit = ns.CreateInput(editor, 404, "")
    edit:SetPoint("TOPLEFT", 20, -93)
    edit:SetMaxLetters(500)
    edit:SetScript("OnEnterPressed", Save)
    editor.edit = edit

    -- References
    local refLabel = ns.Caption(editor, L["References"])
    refLabel:SetPoint("TOPLEFT", 14, -121)

    local refHint = ns.Text(editor, "small", "muted")
    refHint:SetPoint("TOPRIGHT", -14, -122)
    refHint:SetText(L["Shift-click a quest, item or note to attach it"])

    local refPanel
    refPanel, editor.refs = ns.CreateRefList(editor, RemoveRef, TakeCursorItem)
    refPanel:SetPoint("TOPLEFT", 14, -136)
    refPanel:SetSize(412, 96)
    refPanel:EnableMouse(true)
    refPanel:SetScript("OnReceiveDrag", TakeCursorItem)
    refPanel:SetScript("OnMouseUp", TakeCursorItem)

    editor.noRefs = ns.Text(refPanel, "small", "muted")
    editor.noRefs:SetPoint("CENTER")
    editor.noRefs:SetJustifyH("CENTER")
    editor.noRefs:SetText(L["No items, notes, quests or map locations attached.\nShift-click a quest or an item anywhere in the game, or a note\nin the Item Notes window. Or drag an item onto this window."])

    -- Quests, items and notes are attached by shift-click. Only map locations need buttons.
    local addHere = ns.CreateButton(editor, L["Add My Location"], 140, function()
        local loc = ns.CaptureLocation()
        local pin = loc.mapID and loc.x and { mapID = loc.mapID, x = loc.x, y = loc.y, name = ns.MapName(loc.mapID) }
        AddPin(pin, L["Your position is not available here (instances have no map coordinates)."])
    end)
    addHere:SetPoint("TOPLEFT", 14, -238)
    addHere.tooltipTitle = L["Attach where you are standing right now."]

    local addWaypoint = ns.CreateButton(editor, L["Add Map Pin"], 120, function()
        AddPin(ns.GetUserWaypointPin(), L["No map pin set. Ctrl-click the world map to place one, then try again."])
    end)
    addWaypoint:SetPoint("LEFT", addHere, "RIGHT", 6, 0)
    addWaypoint:SetShown(C_Map ~= nil and C_Map.GetUserWaypoint ~= nil)
    addWaypoint.tooltipTitle = L["Attach your current world map pin."]
    addWaypoint.tooltipText = L["Ctrl-click the world map to place a pin first."]

    editor.recorded = ns.Text(editor, "small", "muted")
    editor.recorded:SetPoint("TOPLEFT", 14, -266)
    editor.recorded:SetPoint("RIGHT", -14, 0)
    editor.recorded:SetJustifyV("TOP")
    editor.recorded:SetSpacing(2)

    -- Bottom buttons
    local save = ns.CreateButton(editor, L["Save"], 100, Save)
    save:SetPoint("BOTTOMRIGHT", -14, 10)

    local cancel = ns.CreateButton(editor, L["Cancel"], 90, Close)
    cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)

    editor.delete = ns.CreateButton(editor, L["Delete note"], 100, function()
        local itemID = editor.itemID
        Close()
        ns.ConfirmDelete(itemID)
    end)
    editor.delete:SetPoint("BOTTOMLEFT", 14, 10)

    -- Watch mouse clicks only while the editor is open.
    editor:SetScript("OnEvent", OnGlobalMouse)
    editor:SetScript("OnShow", function(self)
        -- Not every client has these events; without them shift-click attaching is simply unavailable.
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_DOWN")
        pcall(self.RegisterEvent, self, "GLOBAL_MOUSE_UP")
    end)
    editor:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        pendingQuest, pendingItem = nil, false
        if not closing and IsDirty() then
            draft = {
                itemID = editor.itemID,
                text = edit:GetText(),
                quests = editor.quests,
                pins = editor.pins,
                items = editor.items,
                notes = editor.notes,
            }
            ns.Print(L["Unsaved changes kept. Open the note again to continue editing."])
        end
        closing = false
        edit:ClearFocus()
    end)

    -- Notes change behind the open editor (a delete from the Item Notes window), and so do the bags: keep its
    -- references and bag counts current.
    ns.OnChanged(function()
        if editor:IsShown() then
            RefreshRefs()
            RefreshBagInfo()
        end
    end)
end

function ns.IsEditorOpen()
    return editor ~= nil and editor:IsShown()
end

-- Opens the editor for an item. If it is already editing another item with unsaved changes, asks before
-- replacing them; force skips that question.
function ns.OpenEditor(itemID, force)
    if not ns.db then return end
    if not editor then
        CreateEditor()
        -- Frames are created shown. Nothing is being edited yet, so there is no draft to keep.
        Close()
    end
    if editor:IsShown() and not force then
        if editor.itemID == itemID then
            editor:Raise()
            editor.edit:SetFocus()
            return
        end
        if IsDirty() then
            StaticPopup_Show("ITEMNOTES_DISCARD", editor.name:GetText(), nil, itemID)
            return
        end
    end

    local note = ns.GetNote(itemID)
    local name, _, quality, icon = ns.ItemInfo(itemID)
    name = name or (note and note.name)
    quality = quality or (note and note.quality)
    icon = icon or (note and note.icon)

    editor.itemID = itemID
    -- A new note starts with the item's quests already attached. They are its starting point, not an edit:
    -- closing the editor untouched keeps nothing, and removing one is an edit like any other.
    editor.quests = note and CopyList(note.quests) or ns.QuestsForItem(itemID)
    editor.pins = CopyList(note and note.pins)
    editor.items = CopyList(note and note.items)
    editor.notes = CopyList(note and note.notes)
    editor.refsChanged = false
    editor.originalText = SingleLine(note and note.text)
    editor.title:SetText(note and L["Edit Item Note"] or L["New Item Note"])
    editor.icon.texture:SetTexture(icon or ns.FALLBACK_ICON)
    editor.name:SetText(ns.ItemName(itemID, name))
    editor.name:SetTextColor(ns.QualityColor(quality))
    editor.meta:SetText(L["Item ID %d"]:format(itemID))
    editor.edit:SetText(editor.originalText)
    editor.delete:SetShown(note ~= nil)
    editor.recorded:SetText(note and ns.RecordedText(note)
        or L["Your location and the time are recorded when you save."])

    if draft and draft.itemID == itemID then
        editor.quests, editor.pins, editor.items, editor.notes = draft.quests, draft.pins, draft.items, draft.notes
        editor.refsChanged = true
        editor.edit:SetText(draft.text)
        draft = nil
    end

    RefreshRefs()
    RefreshBagInfo()
    editor:Show()
    editor:Raise()
    editor.edit:SetFocus()
    editor.edit:SetCursorPosition(editor.edit:GetNumLetters())
end
