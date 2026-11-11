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
    "C_Container", "C_Item", "C_Map", "C_QuestLog", "C_SuperTrack", "C_Timer",
    "ChatFrameUtil", "Enum", "Settings", "TooltipDataProcessor", "TooltipUtil", "UiMapPoint",

    -- Functions
    "ChatEdit_InsertLink", "ChatFrame_OpenChat", "ClearCursor", "CreateFrame",
    "GameTooltip_Hide", "GetBindingKey", "GetBindingText", "GetContainerItemID", "GetContainerItemInfo",
    "GetContainerItemQuestInfo", "GetContainerNumSlots",
    "GetCursorInfo", "GetItemInfo", "GetItemInfoInstant", "GetMouseFoci", "GetMouseFocus",
    "GetNumQuestLeaderBoards", "GetNumQuestLogEntries", "GetQuestLogIndexByID", "GetQuestLogLeaderBoard",
    "GetQuestLogSpecialItemInfo", "GetQuestLogTitle",
    "GetRealmName", "GetRealZoneText", "GetSubZoneText", "HideUIPanel",
    "InCombatLockdown", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "IsBagOpen", "IsControlKeyDown", "IsMetaKeyDown", "IsModifiedClick", "IsShiftKeyDown",
    "OpenAllBags", "OpenBag", "OpenWorldMap", "QuestLog_SetSelection", "QuestMapFrame_OpenToQuestDetails",
    "SetItemSearch", "SetPortraitToTexture", "ShowUIPanel", "StaticPopup_Show", "UnitName",

    -- Frames and font objects
    "BagItemSearchBox", "ChatFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalLarge",
    "GameTooltip", "ItemRefTooltip", "NumberFontNormal", "ObjectiveTrackerFrame", "QuestLogFrame",
    "QuestObjectiveTracker", "SettingsPanel", "ShoppingTooltip1", "ShoppingTooltip2",
    "StackSplitFrame", "UIParent", "WatchFrame", "WorldFrame", "WorldMapFrame",

    -- Constants
    "ITEM_QUALITY_COLORS", "NO", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "YES",

    -- Other addons
    "QuestieLoader", "TomTom",
}
