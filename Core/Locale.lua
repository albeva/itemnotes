local _, ns = ...

-- Strings are keyed by their English text, so anything without a translation falls back to English.
-- To add a language, assign translations after this table is created, for example:
--   if GetLocale() == "deDE" then L["Item Notes"] = "Gegenstandsnotizen" end
local L = setmetatable({}, {
    __index = function(_, key) return key end,
})

ns.L = L
