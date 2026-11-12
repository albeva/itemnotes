local _, ns = ...
local L = ns.L

-- Thin wrappers around Blizzard's own frame templates, so the addon looks like the rest of the game UI.
-- Each wrapper falls back to an older template when the client does not have the newer one.

local COLORS = {
    text = { 1, 1, 1 },
    muted = { 0.62, 0.62, 0.62 },
    title = { 1, 0.82, 0 },
}
ns.colors = COLORS

ns.fonts = {
    small = GameFontHighlightSmall,
    normal = GameFontHighlight,
    large = GameFontNormalLarge,
    edit = ChatFontNormal,
}

-- Creates a frame from the first template this client knows.
local function CreateFromTemplates(frameType, name, parent, ...)
    for index = 1, select("#", ...) do
        local template = select(index, ...)
        local ok, frame = pcall(CreateFrame, frameType, name, parent, template)
        if ok and frame then return frame, template end
    end
    return CreateFrame(frameType, name, parent), nil
end

function ns.Text(parent, size, color)
    local text = parent:CreateFontString(nil, "OVERLAY")
    text:SetFontObject(ns.fonts[size or "normal"])
    text:SetTextColor(unpack(COLORS[color or "text"]))
    text:SetJustifyH("LEFT")
    return text
end

-- Gold section heading, as used throughout the default UI.
function ns.Caption(parent, label)
    local text = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetJustifyH("LEFT")
    text:SetText(label)
    return text
end

function ns.AddHighlight(button)
    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)
end

function ns.MakeMovable(frame)
    frame:SetMovable(true)
    -- The game would otherwise record where each dragged window ends up in its own layout cache, for good.
    -- The one window whose place is remembered keeps it in the saved notes instead.
    if frame.SetDontSavePosition then frame:SetDontSavePosition(true) end
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
end

-- Shows button.tooltipTitle / button.tooltipText on hover.
local function AddTooltip(button)
    button:HookScript("OnEnter", function(self)
        if not self.tooltipTitle then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(self.tooltipTitle, 1, 1, 1, true)
        if self.tooltipText then GameTooltip:AddLine(self.tooltipText, 0.7, 0.7, 0.7, true) end
        GameTooltip:Show()
    end)
    button:HookScript("OnLeave", GameTooltip_Hide)
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

-- Standard red panel button. Set button.tooltipTitle / button.tooltipText for a hover tooltip.
function ns.CreateButton(parent, text, width, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 22)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    AddTooltip(button)
    return button
end

-- Small standard close/remove button.
function ns.CreateRemoveButton(parent, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelCloseButton")
    button:SetSize(22, 22)
    button:SetScript("OnClick", onClick)
    AddTooltip(button)
    return button
end

-- ---------------------------------------------------------------------------
-- Windows and panels
-- ---------------------------------------------------------------------------

function ns.SetWindowTitle(frame, text)
    if frame.SetTitle then
        frame:SetTitle(text)
    else
        local title = frame.TitleText or (frame.TitleContainer and frame.TitleContainer.TitleText)
        if title then title:SetText(text) end
    end
end

function ns.SetWindowPortrait(frame, texture)
    if not frame.hasPortrait then return end
    -- The portrait API differs between template versions; a missing portrait is only cosmetic.
    pcall(function()
        if frame.SetPortraitToAsset then
            frame:SetPortraitToAsset(texture)
        elseif frame.portrait and SetPortraitToTexture then
            SetPortraitToTexture(frame.portrait, texture)
        end
    end)
end

-- The standard Blizzard window frame. With a portrait (like the map) when one is given, otherwise the plain
-- variant used by smaller windows. frame.hasPortrait tells callers whether the top-left corner is occupied.
function ns.CreateWindow(name, parent, width, height, title, portrait)
    local frame, template = CreateFromTemplates("Frame", name, parent, "PortraitFrameTemplate", "BasicFrameTemplateWithInset")
    local isPortraitFrame = template == "PortraitFrameTemplate"
    frame.hasPortrait = isPortraitFrame and portrait ~= nil
    if isPortraitFrame and not portrait then
        -- Same thing ButtonFrameTemplate_HidePortrait does. Cosmetic, so a template without these is fine.
        pcall(function()
            frame:SetBorder("ButtonFrameTemplateNoPortrait")
            frame:SetPortraitShown(false)
        end)
    end
    frame:SetSize(width, height)
    frame:SetToplevel(true)
    ns.MakeMovable(frame)
    ns.SetWindowTitle(frame, title)
    ns.SetWindowPortrait(frame, portrait)
    -- Lets callers write frame.title:SetText(...) whatever the template calls its title.
    frame.title = { SetText = function(_, text) ns.SetWindowTitle(frame, text) end }
    -- The stock close handler goes through HideUIPanel, which is blocked in combat.
    local close = frame.CloseButton
    if close then close:SetScript("OnClick", function() frame:Hide() end) end
    return frame
end

-- Shrinks a window that is larger than the screen. Windows are clamped to the screen, which keeps every edge
-- of one that fits inside it; one that does not fit would hang over an edge wherever it is put.
function ns.FitToScreen(frame)
    local maxWidth, maxHeight = UIParent:GetSize()
    local width, height = frame:GetSize()
    if width > maxWidth or height > maxHeight then
        frame:SetSize(math.min(width, maxWidth), math.min(height, maxHeight))
    end
end

local function IsFinite(value)
    return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

-- Adds the standard resize grip to the bottom-right corner. onResized(width, height) fires when the drag ends.
-- The drag is tracked here instead of being handed to the game's own sizing: the window's size is always its
-- size when the grip was pressed plus the distance the mouse has moved since, so it cannot jump. It stays
-- between minWidth/minHeight and the room between its top-left corner and the screen's edges.
function ns.MakeResizable(frame, minWidth, minHeight, onResized)
    local grip = CreateFrame("Button", nil, frame)
    -- Set while the grip is held: where the mouse and the window's size started, and how large it may get.
    local drag

    -- The mouse position in the window's own units, or nil when the game reports nothing usable.
    local function CursorPosition()
        local x, y = GetCursorPosition()
        local scale = frame:GetEffectiveScale()
        if not (IsFinite(x) and IsFinite(y) and IsFinite(scale)) or scale <= 0 then return nil end
        return x / scale, y / scale
    end

    local function StopDrag()
        if not drag then return end
        drag = nil
        grip:SetScript("OnUpdate", nil)
        if onResized then onResized(frame:GetSize()) end
    end

    local function UpdateDrag()
        -- A release the grip never heard about (the button let go outside the game window, say).
        if not IsMouseButtonDown("LeftButton") then
            StopDrag()
            return
        end
        local x, y = CursorPosition()
        -- Nothing to do until the mouse has actually moved.
        if not x or (x == drag.lastX and y == drag.lastY) then return end
        drag.lastX, drag.lastY = x, y
        -- Screen coordinates grow upwards: moving the mouse down makes the window taller.
        local width = Clamp(drag.width + (x - drag.startX), minWidth, drag.maxWidth)
        local height = Clamp(drag.height + (drag.startY - y), minHeight, drag.maxHeight)
        frame:SetSize(math.floor(width + 0.5), math.floor(height + 0.5))
    end

    local function StartDrag()
        if drag or not grip:IsMouseOver() then return end
        local x, y = CursorPosition()
        local left, top = frame:GetLeft(), frame:GetTop()
        local width, height = frame:GetSize()
        if not x or not (IsFinite(left) and IsFinite(top) and IsFinite(width) and IsFinite(height)) then return end

        -- Hold the top-left corner in place, so a size change moves only the right and bottom edges.
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)

        -- What is left of the screen to the right of and below that corner, in the window's units.
        local toFrameUnits = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
        drag = {
            startX = x, startY = y, lastX = x, lastY = y,
            width = width, height = height,
            maxWidth = math.max(minWidth, UIParent:GetWidth() * toFrameUnits - left),
            maxHeight = math.max(minHeight, top),
        }
        grip:SetScript("OnUpdate", UpdateDrag)
    end

    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then StartDrag() end
    end)
    grip:SetScript("OnMouseUp", StopDrag)
    -- The window can close mid-drag (Escape): the drag ends with it.
    grip:SetScript("OnHide", StopDrag)
    return grip
end

-- Dark recessed panel, as behind the quest log list.
function ns.CreatePanel(parent)
    local panel, template = CreateFromTemplates("Frame", nil, parent, "InsetFrameTemplate")
    if not template then
        local background = panel:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0, 0, 0, 0.4)
    end
    return panel
end

function ns.CreateIcon(parent, size)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    local border = frame:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0, 0, 0, 1)
    frame.texture = frame:CreateTexture(nil, "ARTWORK")
    frame.texture:SetPoint("TOPLEFT", 1, -1)
    frame.texture:SetPoint("BOTTOMRIGHT", -1, 1)
    frame.texture:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    frame.count = frame:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    frame.count:SetPoint("BOTTOMRIGHT", -2, 2)
    return frame
end

-- Shows how many of the item are in the bags in the icon's corner, as bag slots do. Nothing when there are none.
function ns.SetIconCount(icon, itemID)
    local count = itemID and ns.BagCount(itemID)
    icon.count:SetText(count and count > 0 and count or "")
end

-- ---------------------------------------------------------------------------
-- Text input
-- ---------------------------------------------------------------------------

-- Single-line input: the standard search box when isSearch is set, otherwise the standard input box.
function ns.CreateInput(parent, width, placeholder, isSearch)
    local edit = CreateFromTemplates("EditBox", nil, parent, isSearch and "SearchBoxTemplate" or "InputBoxTemplate", "InputBoxTemplate")
    edit:SetSize(width, 20)
    edit:SetAutoFocus(false)
    if placeholder and placeholder ~= "" and edit.Instructions then
        edit.Instructions:SetText(placeholder)
    end
    if not isSearch then
        edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    end
    return edit
end

-- ---------------------------------------------------------------------------
-- Scrolling
-- ---------------------------------------------------------------------------

-- Standard scroll frame. Its scrollbar sits just outside the right edge; leave about 20px for it.
function ns.CreateScroll(parent)
    local scroll = CreateFromTemplates("ScrollFrame", nil, parent, "ScrollFrameTemplate", "UIPanelScrollFrameTemplate")
    local bar = scroll.ScrollBar
    if bar and bar.SetHideIfUnscrollable then pcall(bar.SetHideIfUnscrollable, bar, true) end
    function scroll:ScrollTo(offset)
        local range = math.max(0, self:GetVerticalScrollRange() or 0)
        self:SetVerticalScroll(math.max(0, math.min(range, offset)))
    end
    return scroll
end

-- A scrolling list that only keeps frames for the rows currently in view: the number of row frames depends on
-- the list's height, not on how many items it holds. Rows are re-filled as the list scrolls.
--   initRow(row)             builds a row's regions once
--   updateRow(row, item, i)  fills a row from an item
--   list:SetItems(items)     shows a new set of items
--   list:Redraw()            re-fills the visible rows from the current items
function ns.CreateScrollList(parent, rowHeight, initRow, updateRow)
    local scroll = ns.CreateScroll(parent)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    scroll:SetScrollChild(content)

    local rows, items = {}, {}
    local rendering = false

    local function Render()
        -- Clamping the scroll position below fires OnVerticalScroll, which would re-enter.
        if rendering then return end

        local height = scroll:GetHeight() or 0
        local offset = scroll:GetVerticalScroll() or 0
        local maxOffset = math.max(0, #items * rowHeight - height)
        if offset > maxOffset then
            offset = maxOffset
            rendering = true
            scroll:SetVerticalScroll(offset)
            rendering = false
        end

        local first = math.floor(offset / rowHeight) + 1
        local visible = math.ceil(height / rowHeight) + 1
        for slot = 1, visible do
            local index = first + slot - 1
            local item = items[index]
            local row = rows[slot]
            if item then
                if not row then
                    row = CreateFrame("Button", nil, content)
                    row:SetHeight(rowHeight)
                    initRow(row)
                    rows[slot] = row
                end
                if row.index ~= index then
                    row.index = index
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", 0, -(index - 1) * rowHeight)
                    row:SetPoint("TOPRIGHT", 0, -(index - 1) * rowHeight)
                end
                row.item = item
                updateRow(row, item, index)
                row:Show()
            elseif row then
                row.item = nil
                row:Hide()
            end
        end
        for slot = visible + 1, #rows do
            rows[slot].item = nil
            rows[slot]:Hide()
        end
    end

    function scroll:SetItems(newItems)
        items = newItems
        content:SetWidth(math.max(1, self:GetWidth()))
        content:SetHeight(math.max(1, #items * rowHeight))
        Render()
    end

    function scroll:Redraw()
        Render()
    end

    scroll:HookScript("OnSizeChanged", function(self, width)
        content:SetWidth(math.max(1, width or self:GetWidth()))
        Render()
    end)
    scroll:HookScript("OnVerticalScroll", Render)

    return scroll
end

-- A panel with a scrolling list inside it. Returns the panel (for anchoring) and the list.
function ns.CreatePanelList(parent, rowHeight, initRow, updateRow)
    local panel = ns.CreatePanel(parent)
    local list = ns.CreateScrollList(panel, rowHeight, initRow, updateRow)
    list:SetPoint("TOPLEFT", 5, -5)

    -- Rows use the full panel width; room for the scrollbar is only made when the list overflows.
    local itemCount, scrollable = 0, nil
    local function Layout()
        local needsBar = itemCount * rowHeight > list:GetHeight() + 0.5
        if needsBar == scrollable then return end
        scrollable = needsBar
        list:SetPoint("BOTTOMRIGHT", needsBar and -24 or -5, 5)
        if list.ScrollBar then list.ScrollBar:SetShown(needsBar) end
    end

    local setItems = list.SetItems
    function list:SetItems(items)
        itemCount = #items
        Layout()
        setItems(self, items)
    end
    list:HookScript("OnSizeChanged", Layout)
    Layout()
    return panel, list
end

-- ---------------------------------------------------------------------------
-- Reference list (items, other notes, quests, recipes and map pins attached to a note)
-- ---------------------------------------------------------------------------

-- Which Wowhead page a kind of reference has. Notes and map pins have none.
local WOWHEAD_KIND = { item = "item", quest = "quest", recipe = "spell" }

-- Returns one row per reference in refs, a note's list of references (or nil for none), in the same order.
-- A row has the reference's kind, its value (an ID, or for a map pin { mapID, x, y }) and its place in refs.
function ns.RefItems(refs)
    local rows = {}
    if refs then
        for index, ref in ipairs(refs) do
            local kind, id, x, y = ns.ParseRef(ref)
            rows[index] = { kind = kind, value = kind == "pin" and { mapID = id, x = x, y = y } or id, index = index }
        end
    end
    return rows
end

function ns.OpenRef(item)
    if item.kind == "quest" then
        ns.OpenQuest(item.value)
    elseif item.kind == "recipe" then
        ns.OpenRecipe(item.value)
    elseif item.kind == "item" then
        ns.ViewItem(item.value)
    elseif item.kind == "note" then
        ns.ShowNote(item.value)
    else
        ns.OpenPin(item.value)
    end
end

-- A small window holding a URL, selected and ready for Ctrl+C. The game cannot open a web browser itself.
local copyWindow
function ns.ShowCopy(url, title)
    if not copyWindow then
        copyWindow = ns.CreateWindow("ItemNotesCopyWindow", UIParent, 460, 100, L["Wowhead link"])
        copyWindow:SetPoint("CENTER", 0, 120)
        copyWindow:SetFrameStrata("FULLSCREEN_DIALOG")
        table.insert(UISpecialFrames, "ItemNotesCopyWindow")

        local edit = ns.CreateInput(copyWindow, 424, "")
        edit:SetPoint("TOPLEFT", 20, -36)
        copyWindow.edit = edit
        -- Keep the URL intact whatever is typed, and close once it has been copied.
        edit:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(copyWindow.url or "")
                self:HighlightText()
            end
        end)
        edit:SetScript("OnKeyDown", function(_, key)
            -- Ctrl+C on Windows, Cmd+C on macOS.
            if key == "C" and (IsControlKeyDown() or (IsMetaKeyDown and IsMetaKeyDown())) then
                C_Timer.After(0.15, function() copyWindow:Hide() end)
            end
        end)
        edit:SetScript("OnEscapePressed", function() copyWindow:Hide() end)
        edit:SetScript("OnEnterPressed", function() copyWindow:Hide() end)
        edit:SetScript("OnMouseUp", function(self) self:HighlightText() end)

        local hint = ns.Text(copyWindow, "small", "muted")
        hint:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", -4, -10)
        hint:SetText(L["Press Ctrl+C (Cmd+C on Mac) to copy, then paste it into your web browser."])
    end
    copyWindow.url = url
    copyWindow.title:SetText(title or L["Wowhead link"])
    copyWindow.edit:SetText(url)
    copyWindow:Show()
    copyWindow:Raise()
    copyWindow.edit:SetFocus()
    copyWindow.edit:HighlightText()
end

-- A "Wowhead" button for an item. getItemID() returns the item it currently refers to.
function ns.CreateWowheadButton(parent, getItemID)
    local button = ns.CreateButton(parent, L["Wowhead"], 84, function()
        local itemID = getItemID()
        if itemID then ns.ShowCopy(ns.WowheadURL("item", itemID), L["Wowhead link"]) end
    end)
    button:SetHeight(20)
    button.tooltipTitle = L["Copy this item's Wowhead link"]
    return button
end

-- A "Link in Chat" button for an item. getItemID() returns the item it currently refers to.
function ns.CreateChatLinkButton(parent, getItemID)
    local button = ns.CreateButton(parent, L["Link in Chat"], 100, function()
        local itemID = getItemID()
        if itemID then ns.LinkInChat(itemID) end
    end)
    button:SetHeight(20)
    button.tooltipTitle = L["Put this item's link into chat"]
    button.tooltipText = L["Uses the open chat box, or opens one."]
    return button
end

-- A "Locate" button for an item. getItemID() returns the item it currently refers to. Call
-- button:UpdateForItem() when that item or the bags change: the button hides while the bags hold none of it.
function ns.CreateLocateButton(parent, getItemID)
    local button = ns.CreateButton(parent, L["Locate"], 70, function()
        local itemID = getItemID()
        if itemID then ns.LocateItem(itemID) end
    end)
    button:SetHeight(20)
    button.tooltipTitle = L["Find this item in your bags"]
    button.tooltipText = L["Opens your bags and searches them for this item."]
    function button:UpdateForItem()
        local itemID = getItemID()
        -- An unknown count (no bag API) keeps the button.
        self:SetShown(itemID ~= nil and ns.BagCount(itemID) ~= 0)
    end
    return button
end

-- Returns a reference as a row shows it (its kind in colour, then its name) and its plain name.
local function RefText(item)
    local kind, value = item.kind, item.value
    if kind == "item" then
        local label, plain = ns.ColoredItemName(value)
        local count = ns.BagCount(value)
        if count and count > 0 then label = label .. "  |cffffffffx" .. count .. "|r" end
        return "|cffc8a2ff" .. L["Item"] .. "|r  " .. label, plain
    elseif kind == "note" then
        local label, plain = ns.ColoredItemName(value)
        local note = ns.GetNote(value)
        local excerpt = note and ns.Trim(note.text:gsub("%s+", " ")) or ""
        if excerpt ~= "" then label = label .. "  |cff9e9e9e" .. excerpt .. "|r" end
        return "|cff7fd77f" .. L["Note"] .. "|r  " .. label, plain
    elseif kind == "quest" then
        local label = ns.QuestLabel(value)
        return "|cffffe066" .. L["Quest"] .. "|r  " .. label, label
    elseif kind == "recipe" then
        local label = ns.RecipeLabel(value)
        return "|cffff9d5c" .. L["Recipe"] .. "|r  " .. label, label
    end
    local label = ns.PinLabel(value)
    return "|cff66b8ff" .. L["Map"] .. "|r  " .. label, label
end

-- Sets a row's open button up for its reference: what it says, its tooltip and whether it can be pressed.
-- plain is the reference's plain name.
local function UpdateOpenButton(open, item, plain)
    local kind, value = item.kind, item.value
    -- Rows are reused: only a quest or a recipe that cannot be opened turns the button off.
    local canOpen = true
    if kind == "item" then
        open:SetText(L["View"])
        open.tooltipTitle = L["View item: %s"]:format(plain)
        open.tooltipText = L["Pins the item tooltip on screen."]
    elseif kind == "note" then
        open:SetText(L["Open"])
        open.tooltipTitle = L["Open note: %s"]:format(plain)
        open.tooltipText = L["Shows the note in the Item Notes window."]
    elseif kind == "quest" then
        -- Only a quest in the quest log has a page to open.
        local status, logIndex = ns.QuestStatus(value)
        canOpen = logIndex ~= nil
        open:SetText(L["Open"])
        open.tooltipTitle = canOpen and L["Open quest: %s"]:format(plain) or L["This quest is not in your quest log"]
        open.tooltipText = L["Quest ID %d - %s"]:format(value, status)
    elseif kind == "recipe" then
        -- Only a character with the recipe's profession has a crafting window to open it in.
        canOpen = ns.CanOpenRecipe(value)
        open:SetText(L["Open"])
        open.tooltipTitle = canOpen and L["Open recipe: %s"]:format(plain)
            or L["This character does not have the profession for this recipe"]
        open.tooltipText = canOpen and L["Opens the crafting window at this recipe."] or nil
    else
        open:SetText(L["Show"])
        open.tooltipTitle = L["Show on map: %s"]:format(plain)
        open.tooltipText = L["Opens the world map there and sets a waypoint."]
    end
    open:SetEnabled(canOpen)
end

-- A list of a note's references, one per row. It comes in two forms:
--   for reading (no onRemove): each row has buttons to open the reference in game and, for items, quests and
--     recipes, to copy its Wowhead link
--   for editing (onRemove(item) given): each row has a remove button and nothing else
-- Pass onDrop() to accept dragged items. Double-clicking a row opens its reference in either form.
function ns.CreateRefList(parent, onRemove, onDrop)
    return ns.CreatePanelList(parent, 24, function(row)
        ns.AddHighlight(row)
        if onDrop then
            row:SetScript("OnReceiveDrag", onDrop)
            row:SetScript("OnClick", onDrop)
        end
        row:SetScript("OnEnter", function(self)
            local item = self.item
            if not item then return end
            if item.kind == "item" or item.kind == "note" then
                -- For a note reference the item tooltip also carries the referenced note's text.
                ns.ShowItemTooltip(self, item.value, "ANCHOR_LEFT")
            else
                -- Full text, in case the row is too narrow to show it all.
                local label = item.kind == "quest" and ns.QuestLabel(item.value)
                    or item.kind == "recipe" and ns.RecipeLabel(item.value)
                    or ns.PinLabel(item.value)
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
                GameTooltip:AddLine(label, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        row:SetScript("OnLeave", GameTooltip_Hide)
        row:SetScript("OnDoubleClick", function(self)
            if self.item then ns.OpenRef(self.item) end
        end)

        if onRemove then
            row.remove = ns.CreateRemoveButton(row, function()
                if row.item then onRemove(row.item) end
            end)
            row.remove:SetPoint("RIGHT", -2, 0)
            row.remove.tooltipTitle = L["Remove this reference"]
        else
            row.open = ns.CreateButton(row, "", 58, function()
                if row.item then ns.OpenRef(row.item) end
            end)
            row.open:SetHeight(20)
            row.open:SetPoint("RIGHT", -2, 0)
            -- A disabled button still explains itself on hover.
            if row.open.SetMotionScriptsWhileDisabled then row.open:SetMotionScriptsWhileDisabled(true) end
            row.link = ns.CreateButton(row, L["Wowhead"], 78, function()
                local item = row.item
                local kind = item and WOWHEAD_KIND[item.kind]
                if kind then ns.ShowCopy(ns.WowheadURL(kind, item.value), L["Wowhead link"]) end
            end)
            row.link:SetHeight(20)
            row.link:SetPoint("RIGHT", row.open, "LEFT", -2, 0)
            row.link.tooltipTitle = L["Copy Wowhead link"]
        end

        row.text = ns.Text(row, "normal")
        row.text:SetPoint("LEFT", 6, 0)
        row.text:SetPoint("RIGHT", row.remove or row.link, "LEFT", -8, 0)
        row.text:SetWordWrap(false)
    end, function(row, item)
        local text, plain = RefText(item)
        row.text:SetText(text)
        if row.open then
            local hasLink = WOWHEAD_KIND[item.kind] ~= nil
            row.link:SetShown(hasLink)
            -- Without the Wowhead button the text runs up to the open button.
            row.text:SetPoint("RIGHT", hasLink and row.link or row.open, "LEFT", -8, 0)
            UpdateOpenButton(row.open, item, plain)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------

function ns.QualityColor(quality)
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

function ns.ShowItemTooltip(owner, itemID, anchor)
    GameTooltip:SetOwner(owner, anchor or "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:" .. itemID)
    GameTooltip:Show()
end
