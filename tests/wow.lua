-- A stand-in for the game client, enough of it to load the addon's Core files and call into them.
--
--   local game = wow.new()          a client with the addon loaded, as it is before ADDON_LOADED
--   local db = game:login(saved)    the addon's saved variables arrive and the player logs in
--   game.ns                         the addon's private table: every ns.* function
--   game.env                        the globals the addon sees; set game API on it that a test needs
--
-- Every game is separate: its own globals, its own copy of the addon, its own saved data. Only the game API
-- the Core files cannot load or save a note without is here. A test gives the rest itself, by setting it on
-- game.env: the addon looks for most of the API when it is used, so that works after loading too. What the
-- addon looks up while loading (the item API, the tooltip hooks) is set in the function given to wow.new,
-- which runs before the addon's files do.

local wow = {}

local ADDON_NAME = "ItemNotesForever"

local here = debug.getinfo(1, "S").source:sub(2):match("^(.*)[/\\][^/\\]*$") or "."
local ADDON_DIR = here .. "/../addon"

-- What of plain Lua the game gives an addon. Anything else (os, io, require) is nil to it, as in the game.
local LUA = {
    "error", "getmetatable", "ipairs", "math", "next", "pairs", "pcall", "rawequal", "rawget", "rawset", "select",
    "setmetatable", "string", "table", "tonumber", "tostring", "type", "unpack", "xpcall",
}

-- Returns the files the TOC loads from the Core folder, in its order.
local function CoreFiles()
    local files = {}
    for line in io.lines(ADDON_DIR .. "/" .. ADDON_NAME .. ".toc") do
        local file = line:match("^(Core\\[^\r\n]+%.lua)%s*$")
        if file then files[#files + 1] = (file:gsub("\\", "/")) end
    end
    return files
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local Frame = {}
Frame.__index = Frame

function Frame:RegisterEvent(event) self.events[event] = true end
function Frame:UnregisterEvent(event) self.events[event] = nil end
function Frame:SetScript(kind, handler) self.scripts[kind] = handler end

-- ---------------------------------------------------------------------------
-- The game
-- ---------------------------------------------------------------------------

local Game = {}
Game.__index = Game

-- Sends a game event to every frame that registered for it.
function Game:fire(event, ...)
    for _, frame in ipairs(self.frames) do
        local handler = frame.scripts.OnEvent
        if frame.events[event] and handler then handler(frame, event, ...) end
    end
end

-- Lets every C_Timer.After that is waiting run, as if its time had passed.
function Game:runTimers()
    local due = self.timers
    self.timers = {}
    for _, callback in ipairs(due) do callback() end
end

-- The saved variables arrive (saved is what ItemNotesDB held on disk, nil for a first run) and the player
-- logs in. Returns the loaded database, nil when the addon refused the data.
function Game:login(saved)
    self.env.ItemNotesDB = saved
    self:fire("ADDON_LOADED", self.addonName)
    self:fire("PLAYER_LOGIN")
    return self.ns.db
end

-- Types a slash command's arguments: game:slash("options") is "/inotes options".
function Game:slash(message)
    self.env.SlashCmdList.ITEMNOTES(message)
end

-- Returns a game with the addon's Core files loaded. setup, when given, is called with the game before they
-- load, to set what they look up while loading.
function wow.new(setup)
    local env = {}
    for _, name in ipairs(LUA) do env[name] = _G[name] end
    env._G = env

    local game = setmetatable({
        addonName = ADDON_NAME,
        env = env,
        ns = {},
        now = 1700000000,           -- what time() returns
        player = { "Thrall" },      -- what UnitName("player") returns
        realm = "Stormrage",
        zone = "Elwynn Forest",
        subzone = "Goldshire",
        -- The items the client knows: [itemID] = { name, quality, icon, classID, link }. loaded = false is an
        -- item whose data the server has not sent yet: it exists, but has no name.
        items = {},
        itemQueries = 0,            -- how often GetItemInfo was called
        printed = {},               -- every line the addon printed
        errors = {},                -- every error that reached the game's error handler
        timers = {},
        frames = {},
    }, Game)

    function env.print(...)
        local parts = {}
        for index = 1, select("#", ...) do parts[index] = tostring((select(index, ...))) end
        game.printed[#game.printed + 1] = table.concat(parts, " ")
    end

    function env.geterrorhandler()
        return function(problem)
            game.errors[#game.errors + 1] = problem
            return problem
        end
    end

    function env.time() return game.now end
    env.date = os.date

    function env.strtrim(text)
        return (text:gsub("^%s+", ""):gsub("%s+$", ""))
    end

    function env.wipe(list)
        for key in pairs(list) do list[key] = nil end
        return list
    end

    env.C_Timer = {
        After = function(_, callback) game.timers[#game.timers + 1] = callback end,
    }

    function env.CreateFrame()
        local frame = setmetatable({ events = {}, scripts = {} }, Frame)
        game.frames[#game.frames + 1] = frame
        return frame
    end

    env.StaticPopupDialogs, env.SlashCmdList = {}, {}
    env.YES, env.NO = "Yes", "No"

    function env.UnitName(unit)
        if unit == "player" then return unpack(game.player) end
    end
    function env.GetRealmName() return game.realm end
    function env.GetRealZoneText() return game.zone end
    function env.GetSubZoneText() return game.subzone end

    function env.GetItemInfo(itemID)
        game.itemQueries = game.itemQueries + 1
        local item = game.items[itemID]
        if not item or item.loaded == false then return nil end
        local link = item.link or ("|Hitem:%d::::::::|h[%s]|h"):format(itemID, item.name)
        return item.name, link, item.quality, nil, nil, nil, nil, nil, nil, item.icon
    end

    function env.GetItemInfoInstant(itemID)
        local item = game.items[itemID]
        if not item then return nil end
        return itemID, nil, nil, nil, item.icon, item.classID
    end

    if setup then setup(game) end

    for _, file in ipairs(CoreFiles()) do
        local chunk, problem = loadfile(ADDON_DIR .. "/" .. file)
        if not chunk then error(problem, 0) end
        setfenv(chunk, env)
        chunk(ADDON_NAME, game.ns)
    end
    return game
end

return wow
