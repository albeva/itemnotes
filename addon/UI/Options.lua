local _, ns = ...
local L = ns.L

-- Panel shown under Options > AddOns > Item Notes.
local canvas = CreateFrame("Frame")
canvas.name = ns.title
canvas:Hide()

local title = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText(ns.title)

local description = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
description:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
description:SetWidth(560)
description:SetJustifyH("LEFT")
description:SetText(L["Attach personal notes, quests and map locations to items. Notes are stored per item ID for your whole account and appear in item tooltips."])

local open = ns.CreateButton(canvas, L["Open Item Notes"], 160, function()
    -- The Settings window cannot be closed by addon code during combat; the notes window still opens.
    if SettingsPanel and SettingsPanel:IsShown() and not ns.InCombat() then HideUIPanel(SettingsPanel) end
    ItemNotes_Toggle()
end)
open:SetPoint("TOPLEFT", description, "BOTTOMLEFT", 0, -16)

local bindTitle = canvas:CreateFontString(nil, "OVERLAY", "GameFontNormal")
bindTitle:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -20)
bindTitle:SetText(L["Keybind"])

local bindText = canvas:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
bindText:SetPoint("TOPLEFT", bindTitle, "BOTTOMLEFT", 0, -6)
bindText:SetWidth(560)
bindText:SetJustifyH("LEFT")

local function Sync()
    if not ns.db then return end
    local key = GetBindingKey("ITEMNOTES_EDIT")
    local shown = key and (GetBindingText and GetBindingText(key) or key) or L["not set"]
    bindText:SetText(L["Add / edit note for hovered item"] .. ": |cffffd100" .. shown .. "|r\n"
        .. L["Change it under Options > Keybindings > AddOns > Item Notes. Hover over any item and press the key to add, edit or remove its note."])
end

canvas:SetScript("OnShow", Sync)
-- The Settings window reparents the canvas and calls OnRefresh each time it displays it.
canvas.OnRefresh = Sync

local category
if Settings and Settings.RegisterCanvasLayoutCategory then
    category = Settings.RegisterCanvasLayoutCategory(canvas, canvas.name)
    Settings.RegisterAddOnCategory(category)
elseif InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(canvas)
end

function ns.OpenOptions()
    -- Opening the Settings window from addon code is blocked during combat.
    if ns.InCombat() then
        ns.Print(L["Options cannot be opened in combat."])
        return
    end
    if Settings and Settings.OpenToCategory and category then
        Settings.OpenToCategory(category:GetID())
    elseif InterfaceOptionsFrame_OpenToCategory then
        -- Called twice on purpose: the first call only opens the window on older clients.
        InterfaceOptionsFrame_OpenToCategory(canvas)
        InterfaceOptionsFrame_OpenToCategory(canvas)
    end
end
