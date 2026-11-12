-- Loading the saved notes: references, migrations and repairing damaged data (Core\Database.lua).

local wow = require("wow")

local EMPTY_CACHE = { items = {}, quality = {}, quests = {}, recipes = {}, spells = {}, npcs = {} }

describe("references", function()
    it("are built and taken apart", function()
        local ns = wow.new().ns
        assert.equal("item:12", ns.Ref("item", 12))
        assert.equal("macro:Heal", ns.Ref("macro", "Heal"))
        assert.equal("pin:1429:0.4124:0.6000", ns.PinRef({ mapID = 1429, x = 0.41237, y = 0.6 }))

        assert.same({ "quest", 456 }, { ns.ParseRef("quest:456") })
        assert.same({ "pin", 1429, 0.4124, 0.6 }, { ns.ParseRef("pin:1429:0.4124:0.6000") })
        -- A macro's name stays text, even one that is all digits.
        assert.same({ "macro", "123" }, { ns.ParseRef("macro:123") })
        assert.same({ "item" }, { ns.ParseRef("item:abc") })
        assert.same({}, { ns.ParseRef("nonsense") })
    end)
end)

describe("loading the saved notes", function()
    local game

    local function Version1()
        return {
            version = 1,
            settings = {},
            notes = {
                [100] = {
                    text = "pelt", name = "Wolf Pelt", quality = 1, icon = 134, created = 10, updated = 20,
                    char = "A - B",
                    items = { { id = 200, name = "Thick Pelt", quality = 2 } },
                    notes = { { id = 300 } },
                    quests = { { id = 400, title = "Wolves" } },
                    recipes = { { id = 500, name = "Leather Armor" } },
                    pins = { { mapID = 1429, x = 0.5, y = 0.25, name = "Elwynn Forest" } },
                },
                [300] = { text = "other", name = "Other" },
            },
        }
    end

    before_each(function()
        game = wow.new()
    end)

    it("starts an empty database on a first run", function()
        local db = game:login(nil)
        assert.same({ version = 2, notes = {}, cache = EMPTY_CACHE }, db)
        assert.equal(db, game.env.ItemNotesDB)
        assert.is_nil(game.ns.dbProblem)

        -- Saved data that is not a table counts as none.
        assert.same({ version = 2, notes = {}, cache = EMPTY_CACHE }, wow.new():login("junk"))
    end)

    it("keeps data of the current version, once the addon's own ADDON_LOADED fires", function()
        local saved = { version = 2, notes = { [100] = { text = "pelt", created = 10, updated = 20, char = "A - B" } } }
        game.env.ItemNotesDB = saved
        game:fire("ADDON_LOADED", "SomeOtherAddon")
        assert.is_nil(game.ns.db)

        assert.equal(saved, game:login(saved))
        assert.same({ text = "pelt", created = 10, updated = 20, char = "A - B" }, saved.notes[100])
    end)

    it("leaves data from a newer version alone and turns the addon off", function()
        local saved = { version = 3, notes = { [100] = { body = "new layout" } } }
        assert.is_nil(game:login(saved))
        assert.matches("newer version", game.ns.dbProblem)
        assert.equal(saved, game.env.ItemNotesDB)
        assert.same({ version = 3, notes = { [100] = { body = "new layout" } } }, saved)
        -- Said once, at login.
        assert.equal(1, #game.printed)
        assert.matches("newer version", game.printed[1])
    end)

    it("migrates version 1 on a copy", function()
        local saved = Version1()
        local db = game:login(saved)
        assert.same({
            version = 2,
            notes = {
                -- One list of references, in the order the old lists were shown.
                [100] = {
                    text = "pelt", created = 10, updated = 20, char = "A - B",
                    refs = { "item:200", "note:300", "quest:400", "recipe:500", "pin:1429:0.5000:0.2500" },
                },
                -- The referenced note has the reference back.
                [300] = { text = "other", refs = { "note:100" } },
            },
            cache = {
                items = { [100] = "Wolf Pelt", [200] = "Thick Pelt", [300] = "Other" },
                quality = { [100] = 1, [200] = 2 },
                quests = { [400] = "Wolves" },
                recipes = { [500] = "Leather Armor" },
                spells = {},
                npcs = {},
            },
        }, db)
        assert.same(Version1(), saved, "the saved table")
    end)

    it("takes data without a version for version 1, skipping what is damaged", function()
        local db = game:login({
            notes = {
                [100] = {
                    text = "", name = "Fresh",
                    items = { { id = "x" }, "junk", { id = 200 } },
                    quests = "none",
                    pins = { { mapID = 1429, x = 2, y = 0.5 }, { mapID = 1429, x = 0.1, y = 0.2 } },
                },
                [200] = { text = "", items = { { id = 100, name = "Stale" } } },
            },
        })
        assert.equal(2, db.version)
        assert.same({ "item:200", "pin:1429:0.1000:0.2000" }, db.notes[100].refs)
        assert.same({ "item:100" }, db.notes[200].refs)
        -- A note's own name for its item wins over a reference's.
        assert.equal("Fresh", db.cache.items[100])
    end)

    it("leaves data it cannot migrate alone and turns the addon off", function()
        -- There is no version 0, so no way from it to the current one.
        local saved = { version = 0, notes = { [100] = { text = "pelt" } } }
        assert.is_nil(game:login(saved))
        assert.matches("could not be updated", game.ns.dbProblem)
        assert.equal(saved, game.env.ItemNotesDB)
        assert.same({ version = 0, notes = { [100] = { text = "pelt" } } }, saved)
        assert.equal(1, #game.errors)
        assert.matches("no migration from data version 0", game.errors[1])
    end)
end)

describe("repairing saved notes", function()
    -- Logs in with the given notes and cache, saved in the current layout.
    local function Load(notes, cache)
        return wow.new():login({ version = 2, notes = notes, cache = cache })
    end

    it("sets aside entries that are not notes and clears damaged fields", function()
        local intact = {
            text = "ok", created = 10, updated = 20, char = "A - B",
            loc = { zone = "Elwynn Forest", mapID = 1429, x = 0.5, y = 0.25 },
        }
        local db = Load({
            [10] = intact,
            [20] = { text = 5, created = "yesterday", updated = 0 / 0, char = "", loc = "nowhere" },
            [30] = { text = "", loc = { zone = "", subzone = "Goldshire", mapID = 1429, x = 0.5, y = 2 } },
            abc = { text = "bad key" },
            [40] = "not a table",
            [1.5] = { text = "fraction" },
        })
        assert.same({
            [10] = {
                text = "ok", created = 10, updated = 20, char = "A - B",
                loc = { zone = "Elwynn Forest", mapID = 1429, x = 0.5, y = 0.25 },
            },
            [20] = { text = "" },
            [30] = { text = "", loc = { subzone = "Goldshire", mapID = 1429 } },
        }, db.notes)
        assert.same({ abc = { text = "bad key" }, ["40"] = "not a table", ["1.5"] = { text = "fraction" } }, db.invalid)

        assert.same({}, Load("gone").notes)
    end)

    it("cleans references and makes those between notes go both ways", function()
        local db = Load({
            [10] = {
                text = "",
                refs = {
                    "item:5", "item:005",                                       -- the same reference twice
                    "bogus", 42, "quest:0", "pet:5", "pin:1:1.5:0.25",          -- not references
                    "item:10", "note:10",                                       -- the note itself
                    "note:99",                                                  -- a note that does not exist
                    "pin:1:0.5:0.25", "macro:Heal", "note:20",
                },
            },
            [20] = { text = "", refs = { "spell:8" } },
            [30] = { text = "", refs = { "bogus" } },
        })
        assert.same({ "item:5", "pin:1:0.5000:0.2500", "macro:Heal", "note:20" }, db.notes[10].refs)
        assert.same({ "spell:8", "note:10" }, db.notes[20].refs)
        assert.is_nil(db.notes[30].refs)
    end)

    it("keeps only the cached names that notes still use", function()
        local db = Load(
            { [10] = { text = "", refs = { "item:5", "quest:6" } } },
            {
                items = { [10] = "Noted", [5] = "Referenced", [99] = "Deleted" },
                quality = { [10] = 2, [5] = "rare", [99] = 3 },
                quests = { [6] = "A Quest", [7] = "Removed" },
                recipes = "broken",
            }
        )
        assert.same({
            items = { [10] = "Noted", [5] = "Referenced" },
            quality = { [10] = 2 },
            quests = { [6] = "A Quest" },
            recipes = {},
            spells = {},
            npcs = {},
        }, db.cache)
    end)
end)
