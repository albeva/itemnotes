-- Helpers, items, locations and bags (Core\Core.lua).

local wow = require("wow")

-- A map position as the game hands it out: an object with GetXY.
local function Position(x, y)
    return { GetXY = function() return x, y end }
end

describe("core", function()
    local game, ns

    -- Gives the client a world map: the player stands on map 1429 at the position given, nil inside an instance.
    local function UseMap(position)
        game.env.C_Map = {
            GetBestMapForUnit = function() return 1429 end,
            GetPlayerMapPosition = function() return position end,
            GetMapInfo = function(mapID) return mapID == 1429 and { name = "Elwynn Forest" } or nil end,
        }
    end

    before_each(function()
        game = wow.new()
        ns = game.ns
        game.items[100] = { name = "Wolf Pelt", quality = 1, icon = 134, link = "|Hitem:100|h[Wolf Pelt]|h" }
        game.items[200] = { name = "Thick Pelt", quality = 2, icon = 135, loaded = false }
        game:login(nil)
    end)

    it("IsID accepts only positive whole numbers that fit an ID", function()
        for _, value in ipairs({ 1, 19019, 2147483647 }) do
            assert.is_true(ns.IsID(value), tostring(value))
        end
        for _, value in ipairs({ 0, -1, 1.5, 2147483648, 0 / 0, "12", true }) do
            assert.is_false(ns.IsID(value), tostring(value))
        end
        assert.is_false(ns.IsID(nil))

        game.env.issecretvalue = function(value) return value == 42 end
        assert.is_false(ns.IsID(42), "a value the game keeps secret")
    end)

    it("tidies and formats text", function()
        assert.equal("a b", ns.Trim("  a b \n"))
        assert.equal("", ns.Trim(nil))
        assert.matches("^%d%d%d%d%-%d%d%-%d%d %d%d:%d%d$", ns.FormatTime(1700000000))
        assert.equal("", ns.FormatTime(nil))
        assert.equal("https://www.wowhead.com/forever/item=100", ns.WowheadURL("item", 100))
        ns.Print("hello")
        assert.same({ "|cffffd100Item Notes:|r hello" }, game.printed)
    end)

    it("Try hands an error to the game's error handler instead of raising it", function()
        assert.is_true(ns.Try(function() end))
        assert.same({}, game.errors)
        assert.is_false(ns.Try(function() error("broken") end))
        assert.equal(1, #game.errors)
        assert.matches("broken", game.errors[1])
    end)

    it("knows items as far as the client does", function()
        assert.same({ "Wolf Pelt", "|Hitem:100|h[Wolf Pelt]|h", 1, 134 }, { ns.ItemInfo(100) })
        assert.same({ nil, nil, nil, 135 }, { ns.ItemInfo(200) }, "an item whose data has not arrived")
        assert.same({}, { ns.ItemInfo(999) }, "an item that does not exist")

        assert.is_true(ns.ItemExists(200))
        assert.is_false(ns.ItemExists(999))
        assert.is_false(ns.ItemExists("100"))

        assert.equal(134, ns.ItemIcon(100))
        assert.equal(ns.FALLBACK_ICON, ns.ItemIcon(999))

        assert.same({ "Wolf Pelt", 1 }, { ns.ItemName(100) })
        assert.same({ "Item #200" }, { ns.ItemName(200) })

        game.env.ITEM_QUALITY_COLORS = { [1] = { hex = "|cffabcdef" } }
        assert.same({ "|cffabcdefWolf Pelt|r", "Wolf Pelt" }, { ns.ColoredItemName(100) })
        assert.same({ "|cffffffffItem #200|r", "Item #200" }, { ns.ColoredItemName(200) })
    end)

    it("captures where the player is", function()
        assert.same({ zone = "Elwynn Forest", subzone = "Goldshire" }, ns.CaptureLocation(), "without a map API")
        assert.is_nil(ns.GetPlayerPin())

        -- The position is rounded to four decimals.
        UseMap(Position(0.123456, 0.98768))
        assert.same(
            { zone = "Elwynn Forest", subzone = "Goldshire", mapID = 1429, x = 0.1235, y = 0.9877 },
            ns.CaptureLocation()
        )
        assert.same({ mapID = 1429, x = 0.1235, y = 0.9877 }, ns.GetPlayerPin())

        -- Inside an instance the game gives no position, and may give no zone.
        UseMap(nil)
        game.zone, game.subzone = "", nil
        assert.same({ mapID = 1429 }, ns.CaptureLocation())
        assert.is_nil(ns.GetPlayerPin())

        game.env.C_Map.GetUserWaypoint = function() return { uiMapID = 1429, position = Position(0.33333, 0.66666) } end
        assert.same({ mapID = 1429, x = 0.3333, y = 0.6667 }, ns.GetUserWaypointPin())
    end)

    it("writes a location as text", function()
        UseMap(nil)
        assert.equal("", ns.LocationText(nil))
        assert.equal("Elwynn Forest - Goldshire", ns.LocationText({ zone = "Elwynn Forest", subzone = "Goldshire" }))
        assert.equal("Stormwind", ns.LocationText({ zone = "Stormwind", subzone = "Stormwind" }))
        assert.equal("Goldshire", ns.LocationText({ subzone = "Goldshire" }))
        assert.equal("Elwynn Forest", ns.LocationText({ mapID = 1429 }), "the map's name, without a zone")
        assert.equal("Unknown", ns.LocationText({ mapID = 5 }))
        assert.equal("Elwynn Forest (41.2, 60.0)", ns.LocationText({ zone = "Elwynn Forest", x = 0.4124, y = 0.6 }))

        assert.equal("Elwynn Forest (50.0, 25.5)", ns.PinLabel({ mapID = 1429, x = 0.5, y = 0.255 }))
        assert.equal("Map 5 (50.0, 25.5)", ns.PinLabel({ mapID = 5, x = 0.5, y = 0.255 }))
    end)

    it("writes where, when and by whom a note was recorded", function()
        local note = { created = 1700000000, updated = 1700000000, char = "Thrall - Stormrage", loc = { zone = "Durotar" } }
        local when = ns.FormatTime(1700000000)
        assert.equal("Recorded in Durotar\n" .. when .. "  by Thrall - Stormrage", ns.RecordedText(note))
        assert.equal("Recorded in Durotar\n" .. when .. "  by Thrall", ns.RecordedText(note, true), "short")

        note.updated = 1700086400
        assert.equal(
            "Recorded in Durotar\n" .. when .. "  by Thrall - Stormrage\nEdited " .. ns.FormatTime(1700086400),
            ns.RecordedText(note)
        )
    end)

    it("counts what the bags hold, and again only after they changed", function()
        assert.is_nil(ns.BagCount(100), "without a bag API")

        local bags = {
            [0] = { { itemID = 100, stackCount = 3 }, false, { itemID = 200 } },
            [2] = { { itemID = 100, stackCount = 5 } },
        }
        game.env.C_Container = {
            GetContainerNumSlots = function(bag) return bags[bag] and #bags[bag] or 0 end,
            GetContainerItemInfo = function(bag, slot) return bags[bag][slot] or nil end,
        }
        -- The count across bags, and the first bag holding the item.
        assert.same({ 8, 0 }, { ns.BagCount(100) })
        assert.same({ 1, 0 }, { ns.BagCount(200) }, "an item without a stack size")
        assert.same({ 0 }, { ns.BagCount(999) })

        local changes = {}
        ns.OnChanged(function(what) changes[#changes + 1] = what end)
        bags[0][1].stackCount = 1
        assert.equal(8, (ns.BagCount(100)))
        game:fire("BAG_UPDATE_DELAYED")
        assert.equal(6, (ns.BagCount(100)))
        game:runTimers()
        assert.same({ "state" }, changes)
    end)
end)
