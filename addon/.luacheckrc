std = "lua51"
max_line_length = false

-- Globals this addon defines.
globals = {
    "ItemNotesDB",
    "ItemNotes_EditHovered",
    "ItemNotes_Toggle",
    "ItemNotes_OnAddonCompartmentClick",
    "BINDING_HEADER_ITEMNOTES",
    "BINDING_NAME_ITEMNOTES_EDIT",
    "BINDING_NAME_ITEMNOTES_TOGGLE",
    "SLASH_ITEMNOTES1",
    "SLASH_ITEMNOTES2",
    "SLASH_ITEMNOTES3",
    "SlashCmdList",
    "StaticPopupDialogs",
    "UISpecialFrames",
}

-- Game API the addon reads.
read_globals = {
    -- Lua extensions
    "date", "time", "geterrorhandler", "issecretvalue",

    -- Namespaces
    "C_Item", "C_Map", "C_QuestLog", "C_SuperTrack", "C_Timer",
    "ChatFrameUtil", "Enum", "Settings", "TooltipDataProcessor", "TooltipUtil", "UiMapPoint",

    -- Functions
    "ChatEdit_InsertLink", "ChatFrame_OpenChat", "ClearCursor", "CreateFrame",
    "GameTooltip_Hide", "GetBindingKey", "GetBindingText", "GetCursorInfo",
    "GetItemInfo", "GetItemInfoInstant", "GetMouseFoci", "GetMouseFocus",
    "GetQuestLogIndexByID",
    "GetRealmName", "GetRealZoneText", "GetSubZoneText", "HideUIPanel",
    "InCombatLockdown", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "IsControlKeyDown", "IsMetaKeyDown", "IsModifiedClick", "IsShiftKeyDown",
    "OpenWorldMap", "QuestLog_SetSelection", "QuestMapFrame_OpenToQuestDetails",
    "SetPortraitToTexture", "ShowUIPanel", "StaticPopup_Show", "UnitName",

    -- Frames and font objects
    "ChatFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalLarge",
    "GameTooltip", "ItemRefTooltip", "ObjectiveTrackerFrame", "QuestLogFrame",
    "QuestObjectiveTracker", "SettingsPanel", "ShoppingTooltip1", "ShoppingTooltip2",
    "StackSplitFrame", "UIParent", "WatchFrame", "WorldFrame", "WorldMapFrame",

    -- Constants
    "ITEM_QUALITY_COLORS", "NO", "YES",

    -- Other addons
    "TomTom",
}
