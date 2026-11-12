-- Saving, changing and deleting notes, and what is remembered and announced along the way (Core\Database.lua).

local wow = require("wow")

describe("notes", function()
    local game, ns, changes

    local HERE = { zone = "Elwynn Forest", subzone = "Goldshire" }

    before_each(function()
        game = wow.new()
        ns = game.ns
        game:login(nil)
        -- Every change the addon announces, in order.
        changes = {}
        ns.OnChanged(function(what) changes[#changes + 1] = what end)
    end)

    it("record text, time, character and place when first saved", function()
        assert.is_nil(wow.new().ns.GetNote(100), "before the saved data has loaded")

        game.now = 1000
        game.items[100] = { name = "Wolf Pelt", quality = 1 }
        game.items[200] = { name = "Thick Pelt", quality = 2 }
        local note = ns.SaveNote(100, "pelt", { "item:200" })
        assert.same({
            text = "pelt", created = 1000, updated = 1000, char = "Thrall - Stormrage", loc = HERE,
            refs = { "item:200" },
        }, note)
        assert.equal(note, ns.GetNote(100))
        assert.same({ "notes" }, changes)
        -- The names of the items involved are remembered.
        assert.same({ [100] = "Wolf Pelt", [200] = "Thick Pelt" }, ns.db.cache.items)

        assert.equal("", ns.SaveNote(300).text)
    end)

    it("record the character's full name", function()
        game.player = { "Jaina", "Proudmoore" }
        assert.equal("Jaina Proudmoore - Stormrage", ns.SaveNote(1, "").char)

        -- Builds differ: without a surname from UnitName, GetUnitName has the two joined.
        game.player = { "Jaina" }
        game.env.GetUnitName = function() return "Jaina Proudmoore" end
        assert.equal("Jaina Proudmoore - Stormrage", ns.SaveNote(2, "").char)

        game.player, game.realm, game.env.GetUnitName = {}, nil, nil
        assert.equal("? - ?", ns.SaveNote(3, "").char)
    end)

    it("keep what was recorded when saved again", function()
        game.now = 1000
        ns.SaveNote(100, "pelt", { "item:5", "quest:6" })
        game.now, game.player, game.zone = 2000, { "Jaina" }, "Durotar"
        local note = ns.SaveNote(100, "skin of a wolf")
        -- Without a list of references, they stay.
        assert.same({
            text = "skin of a wolf", created = 1000, updated = 2000, char = "Thrall - Stormrage", loc = HERE,
            refs = { "item:5", "quest:6" },
        }, note)

        -- A list replaces them. It is cleaned as when loading, and copied.
        local list = { "quest:6", "quest:6", "bogus", "item:100", "spell:7" }
        ns.SaveNote(100, "", list)
        list[1] = "changed afterwards"
        assert.same({ "quest:6", "spell:7" }, note.refs)

        ns.SaveNote(100, "", {})
        assert.is_nil(note.refs)
    end)

    it("reference each other both ways", function()
        ns.SaveNote(100, "", { "item:9" })
        ns.SaveNote(200, "", { "note:100", "note:999" })
        assert.same({ "item:9", "note:200" }, ns.GetNote(100).refs)
        assert.same({ "note:100" }, ns.GetNote(200).refs, "a note that does not exist is not referenced")

        -- Saving again, with the reference or without a list, adds nothing.
        ns.SaveNote(200, "", { "item:5", "note:100" })
        ns.SaveNote(200, "new text")
        assert.same({ "item:9", "note:200" }, ns.GetNote(100).refs)

        -- Removed from one, it is removed from both.
        ns.SaveNote(100, "", { "item:9" })
        assert.same({ "item:5" }, ns.GetNote(200).refs)
    end)

    it("take the references other notes hold to them when deleted", function()
        ns.SaveNote(100, "", { "item:9" })
        ns.SaveNote(200, "")
        ns.SaveNote(300, "", { "note:100", "note:200" })
        changes = {}

        ns.DeleteNote(300)
        assert.is_nil(ns.GetNote(300))
        assert.same({ "item:9" }, ns.GetNote(100).refs)
        assert.is_nil(ns.GetNote(200).refs)

        -- Deleting what is not there announces nothing.
        ns.DeleteNote(300)
        assert.same({ "notes" }, changes)
    end)

    it("have a reference replaced or removed in all of them at once", function()
        local replaced = {}
        ns.OnRefReplaced(function(old, new) replaced[#replaced + 1] = { old, new } end)
        ns.SaveNote(100, "", { "item:5", "macro:Old", "quest:6" })
        ns.SaveNote(200, "", { "macro:Old", "macro:New" })
        ns.SaveNote(300, "", { "macro:Other" })
        changes = {}

        assert.equal(2, ns.ReplaceRef("macro:Old", "macro:New"))
        assert.same({ "item:5", "macro:New", "quest:6" }, ns.GetNote(100).refs, "in place")
        assert.same({ "macro:New" }, ns.GetNote(200).refs, "not held twice")

        assert.equal(1, ns.ReplaceRef("macro:Other", nil))
        assert.is_nil(ns.GetNote(300).refs)
        assert.truthy(ns.GetNote(300))

        -- A reference no note holds: nothing to announce, but listeners hear of it (unsaved edits may hold it).
        assert.equal(0, ns.ReplaceRef("macro:Unused", "macro:Renamed"))
        assert.same({ "notes", "notes" }, changes)
        assert.same({ { "macro:Old", "macro:New" }, { "macro:Other" }, { "macro:Unused", "macro:Renamed" } }, replaced)
    end)

    it("announce queued changes together", function()
        ns.QueueChanged("state")
        ns.QueueChanged("state")
        assert.same({}, changes)
        assert.equal(1, #game.timers)
        game:runTimers()
        assert.same({ "state" }, changes)

        -- A change to notes covers a change of state.
        ns.QueueChanged("state")
        ns.QueueChanged("notes")
        ns.QueueChanged("state")
        game:runTimers()
        assert.same({ "state", "notes" }, changes)
    end)

    it("remember names by kind and ID", function()
        ns.Remember("quests", 6, "A Quest")
        ns.Remember("quests", 6, "")
        ns.Remember("quests", 6, nil)
        assert.equal("A Quest", ns.CachedName("quests", 6))
        assert.is_nil(ns.CachedName("spells", 6))
    end)

    it("ask the client for an item's name once, and again only while it is missing", function()
        game.items[100] = { name = "Wolf Pelt", quality = 1 }
        game.items[200] = { name = "Thick Pelt", quality = 2, loaded = false }

        assert.same({ "Wolf Pelt", 1 }, { ns.ItemDisplay(100) })
        assert.same({ "Wolf Pelt", 1 }, { ns.ItemDisplay(100) })
        assert.equal(1, game.itemQueries)

        assert.same({}, { ns.ItemDisplay(200) })
        assert.same({}, { ns.ItemDisplay(200) })
        assert.equal(3, game.itemQueries)
    end)

    it("take in an item's name when its data arrives", function()
        game.items[100] = { name = "Wolf Pelt", quality = 1, loaded = false }
        game.items[200] = { name = "Thick Pelt", quality = 2 }
        ns.ItemDisplay(100)

        -- Only items that were asked about matter.
        game:fire("GET_ITEM_INFO_RECEIVED", 200)
        assert.is_nil(ns.db.cache.items[200])
        assert.equal(0, #game.timers)

        game.items[100].loaded = true
        game:fire("GET_ITEM_INFO_RECEIVED", 100)
        game:runTimers()
        assert.same({ "notes" }, changes)
        assert.same({ "Wolf Pelt", 1 }, { ns.ItemDisplay(100) })

        -- Data that changes nothing is not announced.
        game:fire("GET_ITEM_INFO_RECEIVED", 100)
        assert.equal(0, #game.timers)
    end)
end)
