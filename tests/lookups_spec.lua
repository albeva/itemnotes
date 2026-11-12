-- What a note can reference: quests, recipes, spells, NPCs and macros (Core\Core.lua).

local wow = require("wow")

describe("quests", function()
    local game, ns, log, objectives

    -- Gives the client a quest log. log is a list of what C_QuestLog.GetInfo returns; objectives is
    -- [questID] = what C_QuestLog.GetQuestObjectives returns.
    local function UseQuestLog()
        local function Find(questID)
            for index, info in ipairs(log) do
                if info.questID == questID then return index, info end
            end
        end
        game.env.C_QuestLog = {
            GetNumQuestLogEntries = function() return #log end,
            GetInfo = function(index) return log[index] end,
            GetQuestObjectives = function(questID) return objectives[questID] end,
            GetLogIndexForQuestID = function(questID) return (Find(questID)) end,
            GetTitleForQuestID = function(questID)
                local _, info = Find(questID)
                return info and info.title
            end,
            IsQuestFlaggedCompleted = function(questID) return questID == 5 end,
        }
    end

    -- Gives the client Questie's database: the quest the item starts, the quests it is needed for.
    local function UseQuestie(starts, related)
        local database = {
            QueryItemSingle = function(_, field)
                if field == "startQuest" then return starts end
                if field == "relatedQuests" then return related end
            end,
            QueryQuestSingle = function(questID) return "Questie's Quest " .. questID end,
        }
        game.env.QuestieLoader = { ImportModule = function() return database end }
    end

    before_each(function()
        game = wow.new()
        ns = game.ns
        game.items[100] = { name = "Wolf Pelt", classID = 7 }
        game:login(nil)
        log = {
            { isHeader = true, title = "Elwynn Forest" },
            { questID = 6, title = "Wolves at the Door" },
            { questID = 7, title = "Thick Hides" },
        }
        objectives = {}
        UseQuestLog()
    end)

    it("have a title that is remembered once seen, and a status", function()
        assert.equal("Wolves at the Door", ns.QuestTitle(6))
        assert.is_nil(ns.QuestTitle(8))

        assert.equal("Wolves at the Door", ns.QuestLabel(6))
        assert.equal("Quest #8", ns.QuestLabel(8))

        assert.same({ "in your quest log", 2 }, { ns.QuestStatus(6) })
        assert.same({ "completed" }, { ns.QuestStatus(5) })
        assert.same({ "not in your quest log" }, { ns.QuestStatus(8) })

        -- The quest leaves the log: the client forgets its title, the addon does not.
        table.remove(log, 2)
        assert.is_nil(ns.QuestTitle(6))
        assert.equal("Wolves at the Door", ns.QuestLabel(6))
    end)

    it("are found for an item from its bag slot", function()
        assert.same({}, ns.QuestsForItem(100), "without a bag API")

        local asked
        game.env.C_Container = {
            GetContainerNumSlots = function(bag) return bag == 1 and 2 or 0 end,
            GetContainerItemInfo = function(_, slot) return slot == 2 and { itemID = 100, stackCount = 1 } or nil end,
            GetContainerItemQuestInfo = function(bag, slot)
                asked = { bag, slot }
                return { questID = 6 }
            end,
        }
        assert.same({ 6 }, ns.QuestsForItem(100))
        assert.same({ 1, 2 }, asked)
        assert.same({}, ns.QuestsForItem(200), "an item that is not in the bags")
        assert.same({}, game.errors)
    end)

    it("are found for an item from the quest log's objectives", function()
        objectives[6] = { { text = "Speak to the innkeeper", type = "event" }, { text = "Wolf Pelt: 3/8", type = "item" } }
        objectives[7] = { { text = "3/8 Wolf Pelt", type = "item" } }
        assert.same({ 6, 7 }, ns.QuestsForItem(100))

        -- Another item whose name holds this one's, and an objective that is not an item.
        objectives[6] = { { text = "Thick Wolf Pelt: 0/5", type = "item" } }
        objectives[7] = { { text = "Wolf Pelt: 3/8", type = "monster" } }
        assert.same({}, ns.QuestsForItem(100))

        -- The item a quest gives the player to use is matched by ID, so even before its name is known.
        game.items[100].loaded = false
        game.env.GetQuestLogSpecialItemInfo = function(logIndex)
            return logIndex == 3 and "|cffffffff|Hitem:100::::::::|h[Wolf Pelt]|h|r" or nil
        end
        assert.same({ 7 }, ns.QuestsForItem(100))
    end)

    it("are found for an item in Questie's database", function()
        -- Of the quests Questie knows, those in the quest log.
        UseQuestie(8, { 7, 9 })
        assert.same({ 7 }, ns.QuestsForItem(100))
        assert.equal("Thick Hides", ns.CachedName("quests", 7))

        -- None of them in the log: nothing for an ordinary item, the first five for a quest item.
        UseQuestie(8, { 9, 10, 11, 12, 13, 14 })
        assert.same({}, ns.QuestsForItem(100))
        game.items[100].classID = 12
        assert.same({ 8, 9, 10, 11, 12 }, ns.QuestsForItem(100))
        assert.equal("Questie's Quest 8", ns.CachedName("quests", 8))

        game.env.QuestieLoader = { ImportModule = function() error("Questie is broken") end }
        assert.same({}, ns.QuestsForItem(100))
        assert.same({}, game.errors)
    end)
end)

describe("recipes, spells and NPCs", function()
    local game, ns

    before_each(function()
        game = wow.new()
        ns = game.ns
        game:login(nil)
    end)

    it("have names that are remembered once seen", function()
        game.env.C_TradeSkillUI = {
            GetRecipeInfo = function(recipeID) return recipeID == 7 and { name = "Light Leather Armor" } or nil end,
        }
        game.env.C_Spell = {
            GetSpellName = function(spellID) return ({ [8] = "Skinning", [133] = "Fireball" })[spellID] end,
        }
        assert.equal("Light Leather Armor", ns.RecipeLabel(7))
        assert.equal("Skinning", ns.RecipeLabel(8), "a recipe is a spell too")
        assert.equal("Recipe #9", ns.RecipeLabel(9))
        assert.equal("Fireball", ns.SpellLabel(133))
        assert.equal("Spell #134", ns.SpellLabel(134))

        game.env.C_TradeSkillUI, game.env.C_Spell = nil, nil
        assert.equal("Light Leather Armor", ns.RecipeLabel(7))
        assert.equal("Fireball", ns.SpellLabel(133))

        -- The client cannot name an NPC by its ID: the name seen when it was attached is all there is.
        assert.equal("NPC #448", ns.NPCLabel(448))
        ns.Remember("npcs", 448, "Hogger")
        assert.equal("Hogger", ns.NPCLabel(448))
    end)

    it("open a recipe only for a character that has its profession", function()
        assert.is_false(ns.CanOpenRecipe(7), "without a crafting API")
        game.env.C_TradeSkillUI = {
            OpenRecipe = function() end,
            IsRecipeProfessionLearned = function(recipeID) return recipeID == 7 end,
        }
        assert.is_true(ns.CanOpenRecipe(7))
        assert.is_false(ns.CanOpenRecipe(9))
    end)

    it("take an NPC's ID from the unit under the mouse", function()
        local guid = "Creature-0-1465-0-2105-448-000043F59F"
        game.env.UnitGUID = function(unit) return unit == "mouseover" and guid or nil end
        game.env.UnitName = function(unit) return unit == "mouseover" and "Hogger" or nil end
        assert.same({ 448, "Hogger" }, { ns.HoveredNPC() })

        guid = "Vehicle-0-1465-0-2105-9999-000043F59F"
        assert.equal(9999, (ns.HoveredNPC()))

        for _, other in ipairs({ "Player-1465-0A1B2C3D", "Pet-0-1465-0-2105-448-000043F59F", "Creature-448", "" }) do
            guid = other
            assert.is_nil(ns.HoveredNPC(), other)
        end
        guid = nil
        assert.is_nil(ns.HoveredNPC(), "nothing under the mouse")
    end)
end)

describe("macros", function()
    local game, ns, account, character

    -- A character's own macros are numbered after the last place an account-wide one can have.
    local CHARACTER_FIRST = 121

    -- Gives the client macros, by name: account-wide ones, then the character's own.
    local function UseMacros(accountNames, characterNames)
        account, character = accountNames, characterNames or {}
        game.env.GetNumMacros = function() return #account, #character end
        game.env.GetMacroInfo = function(index)
            local name = index < CHARACTER_FIRST and account[index] or character[index - CHARACTER_FIRST + 1]
            if name then return name, "icon", "/cast " .. name end
        end
        game.env.GetMacroIndexByName = function(name)
            for index, other in ipairs(account) do
                if other == name then return index end
            end
            for index, other in ipairs(character) do
                if other == name then return CHARACTER_FIRST + index - 1 end
            end
            return 0
        end
    end

    -- Logs in with the macros given, and two notes that reference the macros Heal and Tank.
    local function Start(accountNames, characterNames)
        game = wow.new()
        ns = game.ns
        UseMacros(accountNames, characterNames)
        game:login(nil)
        ns.SaveNote(100, "", { "item:5", "macro:Heal" })
        ns.SaveNote(200, "", { "macro:Tank" })
    end

    local function Changed(accountNames, characterNames)
        UseMacros(accountNames, characterNames)
        game:fire("UPDATE_MACROS")
    end

    it("are found by name", function()
        Start({ "Heal", "Tank" }, { "Mount" })
        assert.equal("Tank", ns.MacroName(2))
        assert.equal("Mount", ns.MacroName(121))
        assert.is_nil(ns.MacroName(3))

        assert.same({ 1, "/cast Heal" }, { ns.FindMacro("Heal") })
        assert.same({ 121, "/cast Mount" }, { ns.FindMacro("Mount") })
        assert.is_nil(ns.FindMacro("Missing"))

        -- An action bar slot holds a macro, something else, or a macro this character does not have.
        local slots = { { "macro", "Heal" }, { "spell", "Fireball" }, { "macro", "Missing" } }
        game.env.GetActionInfo = function(slot) return slots[slot] and slots[slot][1] end
        game.env.GetActionText = function(slot) return slots[slot] and slots[slot][2] end
        assert.same({ "Heal" }, { ns.ActionMacro(1), ns.ActionMacro(2), ns.ActionMacro(3), ns.ActionMacro(4) })
    end)

    it("take a note's reference along when renamed, and with them when deleted", function()
        Start({ "Heal", "Tank" }, { "Mount" })

        Changed({ "Mend", "Tank" }, { "Mount" })
        assert.same({ "item:5", "macro:Mend" }, ns.GetNote(100).refs)
        assert.matches("The macro Heal is now named Mend", game.printed[1])

        Changed({ "Mend" }, { "Mount" })
        assert.is_nil(ns.GetNote(200).refs)
        assert.matches("The macro Tank was deleted", game.printed[2])

        -- A macro no note references: nothing changes, nothing is said.
        Changed({ "Mend" }, { "Ride" })
        assert.same({ "item:5", "macro:Mend" }, ns.GetNote(100).refs)
        assert.equal(2, #game.printed)
    end)

    it("cost no reference when what changed is not a single macro", function()
        -- Macros arrive or are replaced wholesale when logging in and when syncing with the server.
        local cases = {
            { "one added", { "Heal" }, { "Heal", "Tank" } },
            { "all gone", { "Heal", "Tank" }, {} },
            { "several renamed", { "Heal", "Tank" }, { "Mend", "Guard" } },
            { "two given one new name", { "Heal", "Tank" }, { "Both", "Both" } },
            { "one of two by the same name deleted", { "Heal", "Heal" }, { "Heal" } },
        }
        for _, case in ipairs(cases) do
            local label, before, after = case[1], case[2], case[3]
            Start(before)
            Changed(after)
            assert.same({ "item:5", "macro:Heal" }, ns.GetNote(100).refs, label)
            assert.same({ "macro:Tank" }, ns.GetNote(200).refs, label)
            assert.same({}, game.printed, label)
        end
    end)
end)
