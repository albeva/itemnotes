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

-- Everything the search box looks through for a note, as one lower-case string. Built the first time a note
-- is searched and kept until notes change, so typing a search does not rebuild it for every key pressed.
-- Keyed by the note itself and weak, so a deleted note's text goes with it.
local searchText = setmetatable({}, { __mode = "k" })

-- Which cached names a kind of reference is found under. A note is named by its item.
local NAME_KIND = {
    item = "items", note = "items", quest = "quests", recipe = "recipes", spell = "spells", npc = "npcs",
}

local function SearchText(entry)
    local note = entry.note
    local text = searchText[note]
    if not text then
        local parts = { entry.name, note.text, ns.LocationText(note.loc), note.char or "", tostring(entry.id) }
        if note.refs then
            for _, ref in ipairs(note.refs) do
                local kind, id, x, y = ns.ParseRef(ref)
                if kind == "pin" then
                    parts[#parts + 1] = ns.PinLabel({ mapID = id, x = x, y = y })
                elseif kind == "macro" then
                    -- A macro's reference is its name.
                    parts[#parts + 1] = id
                else
                    parts[#parts + 1] = ns.CachedName(NAME_KIND[kind], id)
                end
            end
        end
        text = table.concat(parts, "\n"):lower()
        searchText[note] = text
    end
    return text
end

local function CompareEntries(a, b)
    if a.key ~= b.key then return a.key < b.key end
    local ta, tb = a.note.updated or 0, b.note.updated or 0
    if ta ~= tb then return ta > tb end
    return a.id < b.id
end

-- Returns the notes matching the search box, sorted, and the total number of notes.
local function BuildEntries()
    local filter = ns.Trim(browser.search:GetText()):lower()
    local entries, total = {}, 0
    for itemID, note in pairs(ns.db.notes) do
        total = total + 1
        local name, quality = ns.ItemName(itemID)
        local entry = { id = itemID, note = note, name = name, quality = quality }
        if filter == "" or SearchText(entry):find(filter, 1, true) then
            -- The sort key is built once per entry, not once per comparison. Sorting by time has none: every
            -- order ends with newest first.
            if sortMode == "name" then
                entry.key = name:lower()
            elseif sortMode == "zone" then
                entry.key = ns.LocationText(note.loc):lower()
            else
                entry.key = ""
            end
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

    local name, quality = ns.ItemName(selectedID)
    detail.icon.texture:SetTexture(ns.ItemIcon(selectedID))
    ns.SetIconCount(detail.icon, selectedID)
    detail.locate:UpdateForItem()
    detail.name:SetText(name)
    detail.name:SetTextColor(ns.QualityColor(quality))
    detail.meta:SetText(L["Item ID %d"]:format(selectedID))

    local text = note.text
    detail.noteText:SetText(text ~= "" and text or ("|cff8f949f" .. L["(no text)"] .. "|r"))
    detail.FitNote()
    -- Back to the top only when a different note is shown, not on every refresh of the same one.
    if detail.shownID ~= selectedID then
        detail.shownID = selectedID
        detail.noteScroll:ScrollTo(0)
    end

    local refs = ns.RefItems(note.refs)
    detail.refs:SetItems(refs)
    -- A note without references shows no references section at all.
    detail.refLabel:SetShown(#refs > 0)
    detail.refPanel:SetShown(#refs > 0)
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
    detail.locate = ns.CreateLocateButton(body, function() return selectedID end)
    detail.locate:SetPoint("LEFT", chatLink, "RIGHT", 4, 0)

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

    -- Shown only while the note has references.
    detail.refLabel = ns.Caption(body, L["References"])
    detail.refLabel:SetPoint("TOPLEFT", 12, -186)

    detail.refPanel, detail.refs = ns.CreateRefList(body)
    detail.refPanel:SetPoint("TOPLEFT", 12, -204)
    detail.refPanel:SetPoint("BOTTOMRIGHT", -12, 86)

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

-- Whether there is a window on screen to refresh. browser.detail is created last, so this is also false while
-- the window is being built.
local function IsOpen()
    return browser ~= nil and browser.detail ~= nil and browser:IsShown()
end

-- Rebuilds the list from the notes: which ones match the search, and in what order.
local function Refresh()
    if not IsOpen() then return end
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

-- Notes changed, or only the game around them. The list is rebuilt for the first; for the second (bag counts,
-- whether a quest can be opened) the same rows are drawn again.
local function OnChanged(what)
    if what == "state" then
        if IsOpen() then
            browser.list:Redraw()
            RefreshDetail()
        end
    else
        -- Stale whether or not the window is open to show it.
        wipe(searchText)
        Refresh()
    end
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

-- The kinds of reference in the order a row sums them up, with the wording for one and for several.
local REF_SUMMARY = {
    { "item", L["%d item"], L["%d items"] },
    { "note", L["%d note"], L["%d notes"] },
    { "quest", L["%d quest"], L["%d quests"] },
    { "recipe", L["%d recipe"], L["%d recipes"] },
    { "spell", L["%d spell"], L["%d spells"] },
    { "npc", L["%d NPC"], L["%d NPCs"] },
    { "macro", L["%d macro"], L["%d macros"] },
    { "pin", L["%d location"], L["%d locations"] },
}
-- Scratch tables for RefSummary, which runs for every row drawn.
local refCounts, refParts = {}, {}

-- Returns a note's references summed up by kind ("2 items, 1 quest"), or nil for a note without any.
local function RefSummary(refs)
    if not refs then return nil end
    wipe(refCounts)
    for _, ref in ipairs(refs) do
        local kind = ref:match("^%a+")
        if kind then refCounts[kind] = (refCounts[kind] or 0) + 1 end
    end
    wipe(refParts)
    for _, spec in ipairs(REF_SUMMARY) do
        local count = refCounts[spec[1]]
        if count then refParts[#refParts + 1] = Plural(count, spec[2], spec[3]) end
    end
    return refParts[1] and table.concat(refParts, ", ") or nil
end

local function UpdateRow(row, entry)
    local note = entry.note
    row.icon.texture:SetTexture(ns.ItemIcon(entry.id))
    ns.SetIconCount(row.icon, entry.id)
    row.name:SetText(entry.name)
    row.name:SetTextColor(ns.QualityColor(entry.quality))

    local text = note.text:gsub("%s+", " ")
    local summary = RefSummary(note.refs)
    if summary then text = "|cff66b8ff" .. summary .. "|r  " .. text end
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
        x = x and math.floor(x + 0.5),
        y = y and math.floor(y + 0.5),
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

    browser.detail = CreateDetail(browser)
    browser.detail:SetPoint("TOPLEFT", panel, "TOPRIGHT", 12, 32)
    browser.detail:SetPoint("BOTTOMRIGHT", -14, 14)

    browser:SetScript("OnShow", function()
        -- The saved size can be larger than the screen is now.
        ns.FitToScreen(browser)
        Refresh()
    end)
    browser:SetScript("OnHide", function() browser.search:ClearFocus() end)
    ns.OnChanged(OnChanged)
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
