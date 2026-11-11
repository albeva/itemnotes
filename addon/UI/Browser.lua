local _, ns = ...
local L = ns.L

local browser
local selectedID
local sortMode = "recent"
local SORT_LABELS = { recent = L["Sort: Recent"], name = L["Sort: Name"], zone = L["Sort: Zone"] }
local SORT_NEXT = { recent = "name", name = "zone", zone = "recent" }
local MIN_WIDTH, MIN_HEIGHT = 760, 440
local ROW_HEIGHT = 46
local SEARCH_DELAY = 0.15

-- The list row under the mouse, if any.
local hoveredRow

-- Items whose data was already requested from the server this session, so a refresh does not ask again.
local requested = {}

local function Matches(entry, filter)
    if filter == "" then return true end
    local note = entry.note
    local haystack = { entry.name, note.text or "", ns.LocationText(note.loc), note.char or "", tostring(entry.id) }
    for _, quest in ipairs(note.quests) do haystack[#haystack + 1] = quest.title or "" end
    for _, pin in ipairs(note.pins) do haystack[#haystack + 1] = ns.PinLabel(pin) end
    for _, item in ipairs(note.items) do haystack[#haystack + 1] = item.name or "" end
    for _, ref in ipairs(note.notes) do
        local target = ns.GetNote(ref.id)
        haystack[#haystack + 1] = target and target.name or ""
    end
    return table.concat(haystack, "\n"):lower():find(filter, 1, true) ~= nil
end

local function CompareEntries(a, b)
    if sortMode == "name" and a.name ~= b.name then return a.name < b.name end
    if sortMode == "zone" and a.zone ~= b.zone then return a.zone < b.zone end
    local ta, tb = a.note.updated or 0, b.note.updated or 0
    if ta ~= tb then return ta > tb end
    return a.id < b.id
end

-- Returns the notes matching the search box, sorted, and the total number of notes.
local function BuildEntries()
    local filter = ns.Trim(browser.search:GetText()):lower()
    local byZone = sortMode == "zone"
    local entries, total = {}, 0
    for itemID, note in pairs(ns.db.notes) do
        total = total + 1
        if not note.name and not requested[itemID] then
            requested[itemID] = true
            ns.CacheItemInfo(itemID, note)
        end
        local entry = { id = itemID, note = note, name = ns.ItemName(itemID, note.name) }
        if Matches(entry, filter) then
            -- The sort key is built once per entry, not once per comparison.
            if byZone then entry.zone = ns.LocationText(note.loc) end
            entries[#entries + 1] = entry
        end
    end
    table.sort(entries, CompareEntries)
    return entries, total
end

-- ---------------------------------------------------------------------------
-- Detail pane (right side): the selected note in full, with its references
-- ---------------------------------------------------------------------------

local function RefreshDetail()
    local detail = browser.detail
    local note = selectedID and ns.GetNote(selectedID)
    detail.body:SetShown(note ~= nil)
    detail.placeholder:SetShown(note == nil)
    if not note then
        detail.shownID = nil
        return
    end

    detail.icon.texture:SetTexture(note.icon or select(4, ns.ItemInfo(selectedID)) or ns.FALLBACK_ICON)
    detail.name:SetText(ns.ItemName(selectedID, note.name))
    detail.name:SetTextColor(ns.QualityColor(note.quality))
    detail.meta:SetText(L["Item ID %d"]:format(selectedID))

    local text = note.text or ""
    detail.noteText:SetText(text ~= "" and text or ("|cff8f949f" .. L["(no text)"] .. "|r"))
    detail.FitNote()
    -- Back to the top only when a different note is shown, not on every refresh of the same one.
    if detail.shownID ~= selectedID then
        detail.shownID = selectedID
        detail.noteScroll:ScrollTo(0)
    end

    local refs = ns.RefItems(note.quests, note.pins, note.items, note.notes)
    detail.refs:SetItems(refs)
    detail.noRefs:SetShown(#refs == 0)
    detail.recorded:SetText(ns.RecordedText(note, true))
end

local function CreateDetail(parent)
    local detail = ns.CreatePanel(parent)
    detail.placeholder = ns.Text(detail, "normal", "muted")
    detail.placeholder:SetPoint("CENTER")
    detail.placeholder:SetText(L["Select a note to see it here."])

    local body = CreateFrame("Frame", nil, detail)
    body:SetAllPoints()
    detail.body = body

    detail.icon = ns.CreateIcon(body, 40)
    detail.icon:SetPoint("TOPLEFT", 12, -12)
    detail.icon:EnableMouse(true)
    detail.icon:SetScript("OnEnter", function(self)
        if selectedID then ns.ShowItemTooltip(self, selectedID) end
    end)
    detail.icon:SetScript("OnLeave", GameTooltip_Hide)

    detail.name = ns.Text(body, "large")
    detail.name:SetPoint("TOPLEFT", detail.icon, "TOPRIGHT", 10, -3)
    detail.name:SetPoint("RIGHT", -12, 0)
    detail.name:SetWordWrap(false)

    detail.meta = ns.Text(body, "small", "muted")
    detail.meta:SetPoint("TOPLEFT", detail.name, "BOTTOMLEFT", 0, -4)

    -- Link buttons get their own row so they never run past the pane edge when it is narrow.
    local wowhead = ns.CreateWowheadButton(body, function() return selectedID end)
    wowhead:SetPoint("TOPLEFT", 12, -60)
    local chatLink = ns.CreateChatLinkButton(body, function() return selectedID end)
    chatLink:SetPoint("LEFT", wowhead, "RIGHT", 4, 0)

    local noteLabel = ns.Caption(body, L["Note"])
    noteLabel:SetPoint("TOPLEFT", 12, -92)

    -- The note keeps a fixed, modest height (it scrolls); spare height goes to the references list.
    detail.noteScroll = ns.CreateScroll(body)
    detail.noteScroll:SetPoint("TOPLEFT", 12, -110)
    detail.noteScroll:SetPoint("TOPRIGHT", -30, -110)
    detail.noteScroll:SetHeight(64)
    detail.noteContent = CreateFrame("Frame", nil, detail.noteScroll)
    detail.noteContent:SetSize(1, 1)
    detail.noteScroll:SetScrollChild(detail.noteContent)
    detail.noteText = ns.Text(detail.noteContent, "normal")
    detail.noteText:SetPoint("TOPLEFT")
    detail.noteText:SetJustifyV("TOP")
    detail.noteText:SetSpacing(2)

    -- The note text wraps to the pane width, which changes when the window is resized.
    function detail.FitNote()
        local width = math.max(50, detail.noteScroll:GetWidth())
        detail.noteContent:SetWidth(width)
        detail.noteText:SetWidth(width)
        detail.noteContent:SetHeight(math.max(1, detail.noteText:GetStringHeight() + 4))
    end
    detail.noteScroll:HookScript("OnSizeChanged", detail.FitNote)

    local refLabel = ns.Caption(body, L["References"])
    refLabel:SetPoint("TOPLEFT", 12, -186)

    local refPanel
    refPanel, detail.refs = ns.CreateRefList(body)
    refPanel:SetPoint("TOPLEFT", 12, -204)
    refPanel:SetPoint("BOTTOMRIGHT", -12, 86)

    detail.noRefs = ns.Text(refPanel, "small", "muted")
    detail.noRefs:SetPoint("CENTER")
    detail.noRefs:SetText(L["No items, notes, quests or map locations attached."])

    detail.recorded = ns.Text(body, "small", "muted")
    detail.recorded:SetPoint("BOTTOMLEFT", 12, 44)
    detail.recorded:SetPoint("BOTTOMRIGHT", -12, 44)
    detail.recorded:SetJustifyV("BOTTOM")
    detail.recorded:SetSpacing(2)
    -- Never grow past the space reserved above the buttons, however narrow the pane gets.
    if detail.recorded.SetMaxLines then detail.recorded:SetMaxLines(3) end

    local edit = ns.CreateButton(body, L["Edit note"], 100, function()
        if selectedID then ns.OpenEditor(selectedID) end
    end)
    edit:SetPoint("BOTTOMRIGHT", -12, 12)

    local delete = ns.CreateButton(body, L["Delete note"], 100, function()
        if selectedID then ns.ConfirmDelete(selectedID) end
    end)
    delete:SetPoint("BOTTOMLEFT", 12, 12)

    return detail
end

-- ---------------------------------------------------------------------------
-- List (left side)
-- ---------------------------------------------------------------------------

local function Refresh()
    -- browser.detail is created last, so this also skips refreshes fired while the window is being built.
    if not browser or not browser.detail or not browser:IsShown() then return end
    if selectedID and not ns.GetNote(selectedID) then selectedID = nil end
    local entries, total = BuildEntries()
    browser.entries = entries
    browser.list:SetItems(entries)
    if total == 0 then
        browser.empty:SetText(L["No notes yet.\n\nHover over an item and press your\nItem Notes keybind, or drag an item here."])
    else
        browser.empty:SetText(L["No notes match your search."])
    end
    browser.empty:SetShown(#entries == 0)
    if #entries == total then
        browser.count:SetText((total == 1 and L["%d note"] or L["%d notes"]):format(total))
    else
        browser.count:SetText(L["%d of %d"]:format(#entries, total))
    end
    RefreshDetail()
end

-- Typing in the search box refreshes once the typing pauses, not on every keystroke.
local searchPending = false
local function OnSearchChanged()
    if searchPending then return end
    searchPending = true
    C_Timer.After(SEARCH_DELAY, function()
        searchPending = false
        Refresh()
    end)
end

-- Selecting a note changes no data: only the highlight and the detail pane need updating.
local function Select(itemID)
    selectedID = itemID
    browser.list:Redraw()
    RefreshDetail()
end

local function TakeCursorItem()
    local kind, itemID = GetCursorInfo()
    if kind == "item" and type(itemID) == "number" then
        ClearCursor()
        ns.OpenEditor(itemID)
        return true
    end
    return false
end

local function InitRow(row)
    ns.AddHighlight(row)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    row.selected = row:CreateTexture(nil, "BACKGROUND")
    row.selected:SetAllPoints()
    row.selected:SetColorTexture(1, 0.82, 0, 0.14)
    row.marker = row:CreateTexture(nil, "ARTWORK")
    row.marker:SetPoint("TOPLEFT")
    row.marker:SetPoint("BOTTOMLEFT")
    row.marker:SetWidth(2)
    row.marker:SetColorTexture(1, 0.82, 0, 1)

    row.icon = ns.CreateIcon(row, 32)
    row.icon:SetPoint("LEFT", 8, 0)

    row.when = ns.Text(row, "small", "muted")
    row.when:SetPoint("TOPRIGHT", -6, -7)
    row.when:SetJustifyH("RIGHT")

    row.name = ns.Text(row, "normal")
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -1)
    row.name:SetPoint("RIGHT", row.when, "LEFT", -8, 0)
    row.name:SetWordWrap(false)

    row.text = ns.Text(row, "small", "muted")
    row.text:SetPoint("BOTTOMLEFT", row.icon, "BOTTOMRIGHT", 8, 2)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetWordWrap(false)

    local divider = row:CreateTexture(nil, "BORDER")
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT")
    divider:SetPoint("BOTTOMRIGHT")
    divider:SetColorTexture(1, 1, 1, 0.05)

    row:SetScript("OnClick", function(self, button)
        local entry = self.item
        if not entry or TakeCursorItem() then return end
        if IsModifiedClick and IsModifiedClick("CHATLINK") then
            -- While the editor is open, a shift-click attaches this note to the note being edited instead.
            if not ns.IsEditorOpen() then
                local _, link = ns.ItemInfo(entry.id)
                if link then ns.InsertChatLink(link) end
            end
            return
        end
        if button == "RightButton" then ns.OpenEditor(entry.id) end
        Select(entry.id)
    end)
    row:SetScript("OnDoubleClick", function(self)
        if self.item then ns.OpenEditor(self.item.id) end
    end)
    row:SetScript("OnReceiveDrag", TakeCursorItem)
    row:SetScript("OnEnter", function(self)
        hoveredRow = self
        if self.item then ns.ShowItemTooltip(self, self.item.id, "ANCHOR_LEFT") end
    end)
    row:SetScript("OnLeave", function(self)
        if hoveredRow == self then hoveredRow = nil end
        GameTooltip_Hide()
    end)
end

local function Plural(count, one, many)
    return (count == 1 and one or many):format(count)
end

local function UpdateRow(row, entry)
    local note = entry.note
    row.icon.texture:SetTexture(note.icon or select(4, ns.ItemInfo(entry.id)) or ns.FALLBACK_ICON)
    row.name:SetText(entry.name)
    row.name:SetTextColor(ns.QualityColor(note.quality))

    local text = (note.text or ""):gsub("%s+", " ")
    local items, notes, quests, pins = #note.items, #note.notes, #note.quests, #note.pins
    if items + notes + quests + pins > 0 then
        local refs = {}
        if items > 0 then refs[#refs + 1] = Plural(items, L["%d item"], L["%d items"]) end
        if notes > 0 then refs[#refs + 1] = Plural(notes, L["%d note"], L["%d notes"]) end
        if quests > 0 then refs[#refs + 1] = Plural(quests, L["%d quest"], L["%d quests"]) end
        if pins > 0 then refs[#refs + 1] = Plural(pins, L["%d location"], L["%d locations"]) end
        text = "|cff66b8ff" .. table.concat(refs, ", ") .. "|r  " .. text
    end
    row.text:SetText(text)
    row.when:SetText(date("%Y-%m-%d", note.updated or note.created or 0))

    local isSelected = entry.id == selectedID
    row.selected:SetShown(isSelected)
    row.marker:SetShown(isSelected)
end

-- Remembers the window's size and position across sessions.
local function SaveLayout()
    local point, _, relativePoint, x, y = browser:GetPoint(1)
    ns.db.window = {
        width = math.floor(browser:GetWidth() + 0.5),
        height = math.floor(browser:GetHeight() + 0.5),
        point = point,
        relativePoint = relativePoint,
        x = x,
        y = y,
    }
end

local function RestoreLayout()
    local saved = ns.db.window
    if type(saved) ~= "table" then return end
    if type(saved.width) == "number" and type(saved.height) == "number" then
        browser:SetSize(math.max(MIN_WIDTH, saved.width), math.max(MIN_HEIGHT, saved.height))
    end
    if type(saved.point) == "string" and type(saved.relativePoint) == "string"
        and type(saved.x) == "number" and type(saved.y) == "number" then
        -- A bad anchor name in the saved data must not stop the window from opening.
        local placed = pcall(function()
            browser:ClearAllPoints()
            browser:SetPoint(saved.point, UIParent, saved.relativePoint, saved.x, saved.y)
        end)
        if not placed then
            browser:ClearAllPoints()
            browser:SetPoint("CENTER")
        end
    end
end

local function CreateBrowser()
    browser = ns.CreateWindow("ItemNotesBrowser", UIParent, 840, 540, ns.title, ns.ICON)
    browser:SetPoint("CENTER")
    table.insert(UISpecialFrames, "ItemNotesBrowser")

    -- Movable, and resizable from the bottom-right corner. The detail pane takes the extra width.
    RestoreLayout()
    ns.MakeResizable(browser, MIN_WIDTH, MIN_HEIGHT, SaveLayout)
    browser:HookScript("OnDragStop", SaveLayout)
    browser:SetScript("OnReceiveDrag", TakeCursorItem)
    browser:SetScript("OnMouseUp", TakeCursorItem)

    -- The portrait occupies the top-left corner, so the search box starts to its right.
    local searchLeft = browser.hasPortrait and 68 or 20
    browser.search = ns.CreateInput(browser, 160, L["Search"], true)
    browser.search:SetPoint("TOPLEFT", searchLeft, -34)
    browser.search:HookScript("OnTextChanged", OnSearchChanged)

    browser.sort = ns.CreateButton(browser, SORT_LABELS[sortMode], 104, function(self)
        sortMode = SORT_NEXT[sortMode]
        self:SetText(SORT_LABELS[sortMode])
        Refresh()
    end)

    local panel
    panel, browser.list = ns.CreatePanelList(browser, ROW_HEIGHT, InitRow, UpdateRow)
    panel:SetPoint("TOPLEFT", 14, -62)
    panel:SetPoint("BOTTOMLEFT", 14, 48)
    panel:SetWidth(368)

    -- The list takes a share of the window width, the detail pane the rest.
    local function LayoutSplit()
        local width = math.floor((browser:GetWidth() - 40) * 0.46)
        panel:SetWidth(math.max(320, math.min(520, width)))
    end
    browser:HookScript("OnSizeChanged", LayoutSplit)
    LayoutSplit()

    -- Sort button sits above the list's right edge; the search box fills the space up to it.
    browser.sort:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0, 7)
    browser.search:SetPoint("TOPRIGHT", browser.sort, "TOPLEFT", -10, -1)
    panel:EnableMouse(true)
    panel:SetScript("OnReceiveDrag", TakeCursorItem)
    panel:SetScript("OnMouseUp", TakeCursorItem)

    browser.empty = ns.Text(panel, "normal", "muted")
    browser.empty:SetPoint("CENTER")
    browser.empty:SetJustifyH("CENTER")

    local options = ns.CreateButton(browser, L["Options"], 90, function() ns.OpenOptions() end)
    options:SetPoint("BOTTOMLEFT", 14, 14)

    browser.count = ns.Text(browser, "small", "muted")
    browser.count:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -2, -23)
    browser.count:SetJustifyH("RIGHT")

    local hint = ns.Text(browser, "small", "muted")
    hint:SetPoint("LEFT", options, "RIGHT", 10, 0)
    hint:SetPoint("RIGHT", browser.count, "LEFT", -10, 0)
    hint:SetWordWrap(false)
    hint:SetText(L["Double-click to edit. Drag an item here to add a note."])

    browser.detail = CreateDetail(browser)
    browser.detail:SetPoint("TOPLEFT", panel, "TOPRIGHT", 12, 32)
    browser.detail:SetPoint("BOTTOMRIGHT", -14, 14)

    browser:SetScript("OnShow", Refresh)
    browser:SetScript("OnHide", function() browser.search:ClearFocus() end)
    ns.OnChanged(Refresh)
end

function ns.ToggleBrowser()
    if not ns.db then return end
    if not browser then
        CreateBrowser()
        browser:Hide()
    end
    browser:SetShown(not browser:IsShown())
end

-- The item ID of the note whose list row is under the mouse, if any.
function ns.HoveredNote()
    local row = hoveredRow
    if not (row and row.item and row:IsVisible() and row:IsMouseOver()) then return nil end
    return row.item.id
end

-- Scrolls the list just far enough to bring the selected note's row into view. Does nothing when the search
-- box filters that note out.
local function ScrollToSelected()
    local list = browser.list
    for index, entry in ipairs(browser.entries or {}) do
        if entry.id == selectedID then
            local top = (index - 1) * ROW_HEIGHT
            local offset, height = list:GetVerticalScroll() or 0, list:GetHeight() or 0
            if top < offset then
                list:SetVerticalScroll(top)
            elseif top + ROW_HEIGHT > offset + height then
                list:SetVerticalScroll(math.max(0, top + ROW_HEIGHT - height))
            end
            return
        end
    end
end

-- Opens the Item Notes window with the note for itemID selected.
function ns.ShowNote(itemID)
    if not ns.db or not ns.GetNote(itemID) then return end
    if not browser then
        CreateBrowser()
        browser:Hide()
    end
    selectedID = itemID
    if browser:IsShown() then
        browser.list:Redraw()
        RefreshDetail()
    else
        -- OnShow refreshes the list and the detail pane.
        browser:Show()
    end
    browser:Raise()
    ScrollToSelected()
end
