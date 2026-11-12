-- Runs the addon's unit tests, outside the game:
--
--   luajit tests/run.lua                      every tests/*_spec.lua
--   luajit tests/run.lua tests/notes_spec.lua only the files named
--   luajit tests/run.lua -v                   also lists every test by name
--
-- Needs nothing but a Lua 5.1 interpreter (the game's Lua) or LuaJIT. A spec file is written the way busted
-- specs are, with the small part of that this file provides: describe, it, before_each, and assert with
-- equal, same, is_nil, is_true, is_false, truthy and matches. Each takes a note as its last argument, to say
-- which of a test's assertions failed.
--
-- A test covers one behaviour and asserts everything about it: keep them few, and not overlapping.

local dir = (arg and arg[0] or ""):match("^(.*)[/\\][^/\\]*$") or "."
package.path = dir .. "/?.lua;" .. package.path

-- ---------------------------------------------------------------------------
-- Assertions
-- ---------------------------------------------------------------------------

-- Returns the value as it would be written in Lua, with a table's keys in a fixed order.
local function Show(value, depth)
    if type(value) == "string" then return ("%q"):format(value) end
    if type(value) ~= "table" then return tostring(value) end
    depth = depth or 0
    if depth > 5 then return "{...}" end
    local keys = {}
    for key in pairs(value) do keys[#keys + 1] = key end
    table.sort(keys, function(a, b)
        if type(a) == type(b) and (type(a) == "number" or type(a) == "string") then return a < b end
        return tostring(a) < tostring(b)
    end)
    local parts = {}
    for index, key in ipairs(keys) do
        parts[index] = "[" .. Show(key, depth + 1) .. "] = " .. Show(value[key], depth + 1)
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

-- Whether two values are equal, or are tables holding equal values under the same keys.
local function Same(a, b)
    if a == b then return true end
    if type(a) ~= "table" or type(b) ~= "table" then return false end
    for key, value in pairs(a) do
        if not Same(value, b[key]) then return false end
    end
    for key in pairs(b) do
        if a[key] == nil then return false end
    end
    return true
end

-- Raises a failure at the line of the spec that made the assertion.
local function Fail(message, note)
    error((note and (tostring(note) .. ": ") or "") .. message, 3)
end

local check = {}

function check.equal(expected, actual, note)
    if expected ~= actual then Fail("expected " .. Show(expected) .. ", got " .. Show(actual), note) end
end

function check.same(expected, actual, note)
    if not Same(expected, actual) then Fail("expected " .. Show(expected) .. ", got " .. Show(actual), note) end
end

function check.is_nil(value, note)
    if value ~= nil then Fail("expected nil, got " .. Show(value), note) end
end

function check.is_true(value, note)
    if value ~= true then Fail("expected true, got " .. Show(value), note) end
end

function check.is_false(value, note)
    if value ~= false then Fail("expected false, got " .. Show(value), note) end
end

function check.truthy(value, note)
    if not value then Fail("expected a value, got " .. Show(value), note) end
end

function check.matches(pattern, text, note)
    if type(text) ~= "string" or not text:find(pattern) then
        Fail("expected text matching " .. Show(pattern) .. ", got " .. Show(text), note)
    end
end

-- Plain assert(value, message) keeps working.
setmetatable(check, {
    __call = function(_, value, message, ...)
        if not value then error(message or "assertion failed!", 2) end
        return value, message, ...
    end,
})

-- ---------------------------------------------------------------------------
-- Specs
-- ---------------------------------------------------------------------------

-- The group being described. A group holds its tests and inner groups in the order they were written.
local current

local function NewGroup(name, parent)
    return { name = name, parent = parent, items = {}, before = {} }
end

local function Describe(name, body)
    local group = NewGroup(name, current)
    current.items[#current.items + 1] = group
    current = group
    body()
    current = group.parent
end

local function It(name, body)
    current.items[#current.items + 1] = { name = name, test = body }
end

-- Runs before every test of the group it is written in, inner groups included.
local function BeforeEach(body)
    current.before[#current.before + 1] = body
end

_G.assert, _G.describe, _G.it, _G.before_each = check, Describe, It, BeforeEach

-- ---------------------------------------------------------------------------
-- Running
-- ---------------------------------------------------------------------------

local verbose = false
local total, failures = 0, {}

-- The error with where it happened, without the lines that are this file's or the interpreter's own.
local function Trace(problem)
    local lines = {}
    for line in debug.traceback(tostring(problem), 2):gmatch("[^\n]+") do
        if not (line:find("run.lua:", 1, true) or line:find("[C]:", 1, true) or line:find("stack traceback:", 1, true)) then
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, "\n")
end

local function RunGroup(group, title, setups)
    local own = {}
    for index = 1, #setups do own[index] = setups[index] end
    for _, setup in ipairs(group.before) do own[#own + 1] = setup end
    for _, item in ipairs(group.items) do
        local name = title ~= "" and (title .. " " .. item.name) or item.name
        if item.test then
            total = total + 1
            local ok, problem = xpcall(function()
                for _, setup in ipairs(own) do setup() end
                item.test()
            end, Trace)
            if verbose then print((ok and "  ok    " or "  FAIL  ") .. name) end
            if not ok then failures[#failures + 1] = { name = name, problem = problem } end
        else
            RunGroup(item, name, own)
        end
    end
end

local function RunFile(path)
    current = NewGroup("")
    local root = current
    if verbose then print(path) end
    local chunk, problem = loadfile(path)
    local ok = chunk ~= nil
    if ok then ok, problem = xpcall(chunk, Trace) end
    if not ok then
        total = total + 1
        failures[#failures + 1] = { name = path, problem = problem }
        return
    end
    RunGroup(root, "", {})
end

-- Returns every spec file beside this one, in alphabetical order.
local function FindSpecs()
    local windows = package.config:sub(1, 1) == "\\"
    local command = windows and ('dir /b "%s\\*_spec.lua" 2>nul'):format((dir:gsub("/", "\\")))
        or ('ls "%s"/*_spec.lua 2>/dev/null'):format(dir)
    local specs = {}
    local listing = io.popen(command)
    if listing then
        for line in listing:lines() do
            local name = line:match("([^/\\]+_spec%.lua)%s*$")
            if name then specs[#specs + 1] = dir .. "/" .. name end
        end
        listing:close()
    end
    table.sort(specs)
    return specs
end

local specs = {}
for _, argument in ipairs(arg or {}) do
    if argument == "-v" or argument == "--verbose" then
        verbose = true
    else
        specs[#specs + 1] = argument
    end
end
if #specs == 0 then specs = FindSpecs() end

for _, path in ipairs(specs) do RunFile(path) end

for _, failure in ipairs(failures) do
    print("FAIL  " .. failure.name)
    print("      " .. failure.problem:gsub("\n", "\n      "))
end
print(("%d tests in %d %s, %d failed"):format(total, #specs, #specs == 1 and "file" or "files", #failures))
-- No tests at all is a failure too: a wrong folder must not pass.
os.exit((#failures == 0 and total > 0) and 0 or 1)
