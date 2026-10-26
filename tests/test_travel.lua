-- Run from any directory with texlua path/to/chimera-native/tests/test_travel.lua.
-- Uses the real upstream Bus and Actions to reproduce the original timer leak.
local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tests/test_travel%.lua$") or "."
local upstream = root .. "/../chimera-main"
package.path = upstream .. "/src/?.lua;" .. upstream .. "/src/?/init.lua;" .. package.path
local Bus = require("chimera.core.bus")
local Actions = require("chimera.bots.actions")
local create = dofile(root .. "/chimera_wtyczki/chimera_paczki/travel.lua")
local passed = 0
local function eq(expected, actual, why)
    assert(expected == actual, (why or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, body)
    local ok, problem = pcall(body)
    if not ok then error(name .. ": " .. tostring(problem), 0) end
    passed = passed + 1
    print("OK " .. name)
end

local function setup(useOld)
    local s = { now = 0, timers = {}, handles = {}, cleanups = {}, stops = {}, errors = {}, map = 1, sequence = 0 }
    local bus = Bus.new(function(_, _, problem) s.errors[#s.errors + 1] = problem end)
    bus.mirror = false
    s.bus = bus
    local ctx = {}
    function ctx:on(event, callback)
        local handle = { bus = bus:on(event, callback) }
        s.handles[handle] = true
        return handle
    end
    function ctx:timer(delay, callback)
        s.sequence = s.sequence + 1
        local handle = { order = s.sequence }
        s.timers[handle] = { at = s.now + delay, callback = callback }
        s.handles[handle] = true
        return handle
    end
    function ctx:cancel(handle)
        if handle.bus then bus:off(handle.bus) end
        s.timers[handle], s.handles[handle] = nil, nil
    end
    function ctx:cleanup(callback) s.cleanups[#s.cleanups + 1] = callback end
    function s.advance(delay)
        local ending = s.now + delay
        while true do
            local selected, earliest
            for handle, timer in pairs(s.timers) do
                if timer.at <= ending and (not earliest or timer.at < earliest or
                    (timer.at == earliest and handle.order < selected.order)) then
                    selected, earliest = handle, timer.at
                end
            end
            if not selected then break end
            s.now = earliest
            local timer = s.timers[selected]
            s.timers[selected], s.handles[selected] = nil, nil
            timer.callback()
        end
        s.now = ending
        eq(0, #s.errors, table.concat(s.errors, "\n"))
    end
    function s.cleanup()
        for i = #s.cleanups, 1, -1 do s.cleanups[i]() end
    end
    function s.result()
        local result = { calls = 0 }
        return result, function(value) result.calls, result.value, result.at = result.calls + 1, value, s.now end
    end
    function s.progress(map)
        s.map = map
        bus:emit("chimera.room.changed", { map = map })
        eq(0, #s.errors, table.concat(s.errors, "\n"))
    end
    function s.timerCount()
        local n = 0
        for _ in pairs(s.timers) do n = n + 1 end
        return n
    end
    local walker = {
        resolve = function(arg)
            if s.badResolve then return nil, "nieznany cel" end
            return tonumber(arg)
        end,
        go = function(target)
            if s.goFailure then return nil, s.goFailure end
            if s.map == target then return "tutaj" end
            s.target = target
            if s.duringGo then s.duringGo(target) end
            return true
        end,
        stop = function(reason)
            if not s.target then return end
            s.stops[#s.stops + 1] = { reason = reason, at = s.now }
            s.target = nil
            bus:emit("chimera.walk.stopped", { reason = reason })
        end,
    }
    s.walker = walker
    -- The mapper subscribes first. Its nested moved/arrived event finishes
    -- the action before the same room.changed snapshot reaches progress.
    ctx:on("chimera.room.changed", function(room)
        if room.map == s.target then
            s.target = nil
            bus:emit("chimera.walk.arrived", { map_room = room.map })
        end
    end)
    s.api = useOld and Actions.new(ctx, { walker = walker }) or create(ctx, walker)
    return s
end

test("upstream action really rearms after nested arrival with the actual Bus", function()
    local s = setup(true)
    local result, done = s.result()
    s.api.idz(2, done)
    s.advance(1)
    s.progress(2)
    eq(true, result.value.ok)
    eq(1, result.calls)
    eq(1, s.timerCount(), "orphan timer exists after action has finished")
    local nextResult, nextDone = s.result()
    s.advance(9)
    s.api.idz(3, nextDone)
    for _,delay in ipairs({ 10, 20, 20 }) do s.advance(delay); s.progress(4) end
    eq(60, s.now)
    s.advance(1)
    eq(false, nextResult.value.ok)
    eq("brak postepu", nextResult.value.reason)
    eq(61, s.stops[1].at, "old timer stopped new journey one second after progress")
end)

test("local action cannot rearm from the old room-event snapshot", function()
    local s = setup()
    local first, done = s.result()
    s.api.idz(2, done)
    s.advance(1)
    s.progress(2)
    eq(true, first.value.ok)
    eq(0, s.timerCount())
    local second, nextDone = s.result()
    s.advance(9)
    s.api.idz(3, nextDone)
    for _,delay in ipairs({ 10, 20, 20 }) do s.advance(delay); s.progress(4) end
    s.advance(1)
    eq(61, s.now)
    eq(0, #s.stops)
    eq(0, second.calls)
    eq(1, s.timerCount())
    s.progress(3)
    eq(true, second.value.ok)
    eq(0, s.timerCount())
    s.advance(120)
    eq(0, #s.stops)
    eq(1, first.calls)
    eq(1, second.calls)
end)

test("a genuinely stalled walk still stops once after sixty seconds", function()
    local s = setup()
    local result, done = s.result()
    s.api.idz(2, done)
    s.advance(59)
    eq(0, result.calls)
    s.advance(1)
    eq(false, result.value.ok)
    eq("brak postepu", result.value.reason)
    eq(60, s.stops[1].at)
    eq(1, result.calls)
    eq(0, s.timerCount())
    s.advance(120)
    eq(1, #s.stops)
end)

test("real progress resets only the current operation's timer", function()
    local s = setup()
    local result, done = s.result()
    s.api.idz(2, done)
    s.advance(50)
    s.progress(3)
    s.advance(59)
    eq(0, result.calls)
    eq(1, s.timerCount())
    s.advance(1)
    eq(110, result.at)
    eq(false, result.value.ok)
    eq(1, #s.stops)
end)

test("already-here and inline-arrival completions are synchronous and leave no timers", function()
    for _,inline in ipairs({ false, true }) do
        local s = setup()
        if inline then s.duringGo = function(target) s.progress(target) end end
        local result, done = s.result()
        local cancel = s.api.idz(inline and 2 or 1, done)
        eq(true, result.value.ok)
        eq(1, result.calls)
        eq(0, s.timerCount())
        cancel()
        s.advance(120)
        eq(0, #s.stops)
        eq(1, result.calls)
    end
end)

test("a completed cancellation closure cannot stop the next journey", function()
    local s = setup()
    local first, done = s.result()
    local oldCancel = s.api.idz(2, done)
    s.progress(2)
    local second, nextDone = s.result()
    s.api.idz(3, nextDone)
    oldCancel()
    eq(0, #s.stops)
    eq(0, second.calls)
    s.progress(3)
    eq(true, second.value.ok)
    eq(0, s.timerCount())
    eq(1, first.calls)
end)

test("cancel stops active walk exactly once and ignores later events", function()
    local s = setup()
    local result, done = s.result()
    local cancel = s.api.idz(2, done)
    cancel(); cancel()
    eq(false, result.value.ok)
    eq("przerwane", result.value.reason)
    eq(1, #s.stops)
    eq(1, result.calls)
    s.bus:emit("chimera.walk.arrived", { map_room = 2 })
    s.progress(2)
    s.advance(120)
    eq(1, #s.stops)
    eq(1, result.calls)
    eq(0, s.timerCount())
end)

test("external stopped event and failed start leave no progress watcher", function()
    for _,failure in ipairs({ "stopped", "resolve", "go" }) do
        local s = setup()
        if failure == "resolve" then s.badResolve = true end
        if failure == "go" then s.goFailure = "brak drogi" end
        local result, done = s.result()
        s.api.idz(2, done)
        if failure == "stopped" then s.walker.stop("reczne zatrzymanie") end
        eq(false, result.value.ok)
        s.progress(3)
        s.advance(120)
        eq(1, result.calls)
        eq(0, s.timerCount())
    end
end)

test("reload cancels active travel and rejects future starts", function()
    local s = setup()
    local result, done = s.result()
    s.api.idz(2, done)
    s.cleanup()
    eq(false, result.value.ok)
    eq(1, #s.stops)
    eq(0, s.timerCount())
    s.progress(2)
    s.advance(120)
    local rejected, nextDone = s.result()
    s.api.idz(3, nextDone)
    eq(false, rejected.value.ok)
    eq(0, s.timerCount())
    eq(1, result.calls)
end)

test("reload cannot restart travel from a cancellation callback", function()
    local s = setup()
    local restarted, nextDone = s.result()
    local calls = 0
    s.api.idz(2, function()
        calls = calls + 1
        s.api.idz(3, nextDone)
    end)
    s.cleanup()
    eq(1, calls)
    eq(false, restarted.value.ok)
    eq(nil, s.target)
    eq(0, s.timerCount())
    s.advance(120)
    eq(1, #s.stops)
end)

test("reentrant replacement cannot orphan a newer journey", function()
    local s = setup()
    local nested, nestedDone = s.result()
    s.api.idz(2, function() s.api.idz(4, nestedDone) end)
    local outer, outerDone = s.result()
    s.api.idz(3, outerDone)
    eq(false, outer.value.ok)
    eq(4, s.target)
    eq(1, s.timerCount())
    s.progress(4)
    eq(true, nested.value.ok)
    eq(0, s.timerCount())
    s.advance(120)
    eq(1, #s.stops)
end)

print("PASS " .. passed .. " travel tests with real upstream Bus")
