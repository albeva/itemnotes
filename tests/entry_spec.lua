-- Where the game calls into the addon: tooltips, the keybinds, the slash command and game events (Core\Core.lua).

local wow = require("wow")

local ENUM = { TooltipDataType = { Item = 0, Spell = 1 } }
local LINK = "|cffffffff|Hitem:100::::::::70:::::|h[Wolf Pelt]|h|r"

-- A tooltip that keeps the lines added to it. fields are added to it, or replace what it has.
local function Tooltip(fields)
    local tooltip = { lines = {}, shown = true }
    function tooltip:AddLine(text) self.lines[#self.lines + 1] = text end
    function tooltip:IsShown() return self.shown end
    for key, value in pairs(fields or {}) do tooltip[key] = value end
    return tooltip
end

describe("item tooltips", function()
    it("show the note's text, on a client with tooltip data", function()
        local hook
        local game = wow.new(function(early)
            early.env.Enum = ENUM
            early.env.TooltipDataProcessor = { AddTooltipPostCall = function(_, callback) hook = callback end }
        end)

        -- Shows the tooltip of an item and returns the lines the addon added.
        local function Show(data, tooltip)
            tooltip = tooltip or Tooltip()
            hook(tooltip, data)
            return tooltip.lines
        end

        assert.same({}, Show({ id = 100 }), "before the saved notes have loaded")
        game:login(nil)
        game.ns.SaveNote(100, "Sells well")
        game.ns.SaveNote(200, "", { "quest:6" })

        assert.same({ " ", "Item Note", "Sells well" }, Show({ id = 100 }))
        assert.same({}, Show({ id = 200 }), "a note without text")
        assert.same({}, Show({ id = 300 }), "an item without a note")
        assert.same({}, Show(nil), "no tooltip data")
        assert.same({}, Show({ id = 100 }, Tooltip({ IsForbidden = function() return true end })))
    end)

    it("show the note's text, on a client with tooltip scripts", function()
        local hook
        local tooltip = Tooltip({
            HasScript = function(_, script) return script == "OnTooltipSetItem" end,
            HookScript = function(_, _, handler) hook = handler end,
            GetItem = function() return "Wolf Pelt", LINK end,
        })
        local game = wow.new(function(early) early.env.GameTooltip = tooltip end)
        game:login(nil)

        hook(tooltip)
        assert.same({}, tooltip.lines, "an item without a note")
        game.ns.SaveNote(100, "Sells well")
        hook(tooltip)
        assert.same({ " ", "Item Note", "Sells well" }, tooltip.lines)
    end)
end)

describe("entry points", function()
    local game, ns, opened

    before_each(function()
        game = wow.new()
        ns = game.ns
        game.items[100] = { name = "Wolf Pelt" }
        -- Stands in for the windows (UI\*.lua), which are not loaded.
        opened = {}
        ns.editorOpen = false
        function ns.OpenOptions() opened[#opened + 1] = "options" end
        function ns.ToggleBrowser() opened[#opened + 1] = "browser" end
        function ns.OpenEditor(itemID) opened[#opened + 1] = "editor " .. itemID end
        function ns.AttachHovered() opened[#opened + 1] = "attach" end
        function ns.IsEditorOpen() return ns.editorOpen end
    end)

    it("find the item or spell the tooltip shows", function()
        assert.is_nil(ns.HoveredItem(), "without a tooltip")
        assert.is_nil(ns.HoveredSpell(), "without a tooltip")
        game.env.Enum = ENUM

        game.env.GameTooltip = Tooltip({ GetItem = function() return "Wolf Pelt", LINK end })
        assert.equal(100, ns.HoveredItem(), "from the tooltip's link")
        assert.is_nil(ns.HoveredSpell())
        game.env.GameTooltip.shown = false
        assert.is_nil(ns.HoveredItem(), "a hidden tooltip")

        game.env.GameTooltip = Tooltip({ GetPrimaryTooltipData = function() return { type = ENUM.TooltipDataType.Item, id = 400 } end })
        assert.equal(400, ns.HoveredItem(), "from the tooltip's data")
        assert.is_nil(ns.HoveredSpell())
        game.env.TooltipUtil = { GetDisplayedItem = function() return "Wolf Pelt", LINK, 500 end }
        assert.equal(500, ns.HoveredItem(), "from the tooltip utility")

        -- A tooltip names its spell as name, ID; an older one as name, rank, ID.
        game.env.GameTooltip = Tooltip({ GetSpell = function() return "Fireball", 133 end })
        assert.equal(133, ns.HoveredSpell())
        game.env.GameTooltip = Tooltip({ GetSpell = function() return "Fireball", "Rank 2", 143 end })
        assert.equal(143, ns.HoveredSpell())
    end)

    it("run the slash command", function()
        game:login(nil)
        game:slash("")
        game:slash("  OPTIONS ")
        game:slash(" 100 ")
        game:slash(LINK)
        game:slash("wolf 100")
        assert.same({ "browser", "options", "editor 100", "editor 100", "browser" }, opened)

        game:slash("999")
        assert.equal(5, #opened)
        assert.matches("There is no item with ID 999%.$", game.printed[1])
    end)

    it("run the keybinds and the addon compartment", function()
        game:login(nil)
        game.env.ItemNotes_EditHovered()
        assert.same({}, opened)
        assert.matches("Hover over an item first", game.printed[1])

        game.env.GameTooltip = Tooltip({ GetItem = function() return "Wolf Pelt", LINK end })
        game.env.ItemNotes_EditHovered()
        -- While a note is being edited, the key attaches what the mouse is over instead.
        ns.editorOpen = true
        game.env.ItemNotes_EditHovered()
        game.env.ItemNotes_Toggle()
        game.env.ItemNotes_OnAddonCompartmentClick(nil, "LeftButton")
        game.env.ItemNotes_OnAddonCompartmentClick(nil, "RightButton")
        assert.same({ "editor 100", "attach", "browser", "browser", "options" }, opened)
    end)

    it("say why instead of opening anything while the saved notes could not be used", function()
        game:login({ version = 3, notes = {} })
        game.printed = {}

        game:slash("")
        game:slash("100")
        game.env.ItemNotes_Toggle()
        game.env.ItemNotes_EditHovered()
        assert.same({}, opened)
        assert.equal(4, #game.printed)
        for _, line in ipairs(game.printed) do assert.matches("newer version", line) end

        -- The options still open.
        game:slash("options")
        assert.same({ "options" }, opened)
    end)

    it("ask before deleting a note", function()
        game:login(nil)
        local asked
        game.env.StaticPopup_Show = function(...) asked = { ... } end

        ns.ConfirmDelete(100)
        assert.is_nil(asked, "without a note")

        ns.SaveNote(100, "pelt")
        ns.ConfirmDelete(100)
        assert.same({ "ITEMNOTES_DELETE", "Wolf Pelt", nil, 100 }, asked)
        assert.truthy(ns.GetNote(100))

        game.env.StaticPopupDialogs.ITEMNOTES_DELETE.OnAccept(nil, 100)
        assert.is_nil(ns.GetNote(100))
    end)

    it("announce a change of state on game events, once the saved notes have loaded", function()
        local changes = {}
        ns.OnChanged(function(what) changes[#changes + 1] = what end)
        local events = { "BAG_UPDATE_DELAYED", "QUEST_ACCEPTED", "QUEST_REMOVED", "SKILL_LINES_CHANGED", "UPDATE_MACROS" }

        for _, event in ipairs(events) do game:fire(event) end
        assert.equal(0, #game.timers, "before loading")

        game:login(nil)
        for _, event in ipairs(events) do
            game:fire(event)
            game:runTimers()
        end
        assert.same({ "state", "state", "state", "state", "state" }, changes)
    end)
end)
