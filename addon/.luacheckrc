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
    "date", "time", "geterrorhandler", "issecretvalue", "strtrim", "wipe",

    -- Namespaces
    "C_Container", "C_Item", "C_Map", "C_QuestLog", "C_Spell", "C_SuperTrack", "C_Timer", "C_TradeSkillUI",
    "ChatFrameUtil", "Enum", "Settings", "TooltipDataProcessor", "TooltipUtil", "UiMapPoint",

    -- Functions
    "ChatEdit_InsertLink", "ChatFrame_OpenChat", "ClearCursor", "CreateFrame",
    "GameTooltip_Hide", "GetActionInfo", "GetActionText", "GetBindingKey", "GetBindingText",
    "GetContainerItemID", "GetContainerItemInfo", "GetContainerItemQuestInfo", "GetContainerNumSlots",
    "GetCursorInfo", "GetCursorPosition", "GetItemInfo", "GetItemInfoInstant", "GetMacroIndexByName", "GetMacroInfo",
    "GetMouseFoci", "GetMouseFocus", "GetNumMacros",
    "GetNumQuestLeaderBoards", "GetNumQuestLogEntries", "GetQuestLogIndexByID", "GetQuestLogLeaderBoard",
    "GetQuestLogSpecialItemInfo", "GetQuestLogTitle",
    "GetRealmName", "GetRealZoneText", "GetSpellInfo", "GetSubZoneText", "GetUnitName", "HideUIPanel",
    "InCombatLockdown", "InterfaceOptions_AddCategory", "InterfaceOptionsFrame_OpenToCategory",
    "IsAltKeyDown", "IsBagOpen", "IsControlKeyDown", "IsMetaKeyDown", "IsModifiedClick", "IsMouseButtonDown",
    "IsShiftKeyDown",
    "OpenAllBags", "OpenBag", "OpenWorldMap", "PickupMacro", "QuestLog_SetSelection", "QuestMapFrame_OpenToQuestDetails",
    "SetItemSearch", "SetPortraitToTexture", "ShowUIPanel", "StaticPopup_Show", "UnitGUID",
    "UnitName",

    -- Frames and font objects
    "BagItemSearchBox", "ChatFontNormal", "GameFontHighlight", "GameFontHighlightSmall", "GameFontNormalLarge",
    "GameTooltip", "ItemRefTooltip", "NumberFontNormal", "ObjectiveTrackerFrame", "ProfessionsRecipeTracker",
    "QuestLogFrame", "QuestObjectiveTracker", "SettingsPanel", "ShoppingTooltip1", "ShoppingTooltip2",
    "StackSplitFrame", "UIParent", "WatchFrame", "WorldFrame", "WorldMapFrame",

    -- Constants
    "ITEM_QUALITY_COLORS", "MAX_ACCOUNT_MACROS", "NO", "NUM_BAG_SLOTS", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "YES",

    -- Other addons
    "QuestieLoader", "TomTom",
}
