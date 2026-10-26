-- Standalone: lua chimera-native/tests/test_npc.lua (no native test harness).
local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tests/test_npc%.lua$") or "."
package.path = root .. "/chimera_wtyczki/?.lua;" .. package.path
local create = dofile(root .. "/chimera_wtyczki/chimera_paczki/npc.lua")
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

local function setup(records, injectSender, options)
    local s = { time = 0, events = {}, timers = {}, actions = {}, cancellations = 0, refreshes = 0,
        probes = {}, injectedSends = 0,
        room = { id = "home", name = "Poczta", exits = { polnoc = "tower" } }, map = 1,
        snapshot = { room = "home", entities = {} }, maps = { home = 1, tower = 2, stairs = 3 }, blocked = {}, paths = {} }
    local ctx = {}
    function ctx:on(event, callback)
        self.nextHandle = (self.nextHandle or 0) + 1
        local handle = self.nextHandle
        s.events[event] = s.events[event] or {}
        s.events[event][handle] = callback
        return handle
    end
    function ctx:timer(delay, callback)
        self.nextHandle = (self.nextHandle or 0) + 1
        local handle = self.nextHandle
        s.timers[handle] = { at = s.time + delay, callback = callback }
        return handle
    end
    function ctx:cancel(handle)
        s.timers[handle] = nil
        for _, handlers in pairs(s.events) do handlers[handle] = nil end
    end
    function ctx:cleanup(callback) s.cleanup = callback end
    function ctx:send(command)
        s.probes[#s.probes + 1] = command
        if s.onProbe then return s.onProbe(command) end
    end
    function s.emit(event, value)
        local copy = {}
        for handle, callback in pairs(s.events[event] or {}) do copy[handle] = callback end
        for handle, callback in pairs(copy) do
            if s.events[event][handle] then callback(value) end
        end
    end
    function s.advance(seconds)
        local ending = s.time + seconds
        while true do
            local earliest, selected
            for handle, timer in pairs(s.timers) do
                if timer.at <= ending and (not earliest or timer.at < earliest or (timer.at == earliest and handle < selected)) then
                    earliest, selected = timer.at, handle
                end
            end
            if not selected then break end
            s.time = earliest
            local timer = s.timers[selected]
            s.timers[selected] = nil
            timer.callback()
        end
        s.time = ending
    end
    function s.arrive(map, id)
        local action = s.actions[#s.actions]
        s.map, s.room.id, s.room.name = map, id or (map == 2 and "tower" or "stairs"), "Swiatynia"
        s.snapshot = { room = s.room.id, entities = {} }
        action.done({ ok = true })
    end
    function s.entities(name, kind, room)
        s.snapshot = { room = room or s.room.id, entities = { { id = "e1-3", name = name, kind = kind or "npc" } } }
        s.emit("chimera.room.entities", s.snapshot)
    end
    _G.getRoomIDbyHash = function(id) return s.maps[id] or -1 end
    _G.speedWalkDir = {}
    local walker = { cost = function(from, to)
        _G.speedWalkDir = s.paths[from .. ":" .. to] or { "n" }
        if s.blocked[from .. ":" .. to] then return nil end
        return math.abs(to - from) * 2
    end }
    local mapper = { current_room = function() return s.map end, chimera_id = function(map)
        if s.evidenceHash then return s.evidenceHash end
        for id, number in pairs(s.maps) do if number == map then return id end end
    end }
    local gmcp = {
        room = function() return s.room end,
        entities = function() return s.snapshot end,
        refresh_entities = function() s.refreshes = s.refreshes + 1 end,
    }
    records = records or { { id = "0dfb3842", name = "Rolph", short = "przygarbiony otyly mezczyzna",
        title = "Rolph Ederson, Przelozony na Ksiegach", rooms = { tower = true, stairs = true } } }
    local npcs = {
        all = function() return records end,
        find = function(arg)
            local found = {}
            for _, npc in ipairs(records) do
                if arg:lower() == npc.id:lower() or arg:lower() == npc.name:lower() then found[#found + 1] = npc end
            end
            return found
        end,
    }
    local bots = { actions = { idz = function(map, done)
        local action = { map = map, done = done }
        s.actions[#s.actions + 1] = action
        if s.beforeActionReturns then s.beforeActionReturns() end
        if s.synchronous then done({ ok = true }) end
        return function()
            s.cancellations = s.cancellations + 1
            done({ ok = false, reason = "przerwane" })
        end
    end } }
    local locations = { gate = function() return s.gate end }
    s.api = create(ctx, bots, gmcp, walker, mapper, npcs, locations, injectSender and function(command)
        s.injectedSends = s.injectedSends + 1
        return ctx:send(command)
    end or nil, bots.actions.idz, options)
    function s.result()
        local result = { calls = 0 }
        return result, function(ok, why, detail)
            result.calls, result.ok, result.reason, result.detail = result.calls + 1, ok, why, detail
        end
    end
    return s
end

test("full postal title resolves short catalogue name and weighted round trip", function()
    local s = setup()
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq("0dfb3842", route.npcId)
    eq("Rolph", route.npcName)
    eq(2, route.rooms[1])
    eq("tower", route.roomIds[2])
    eq(4, route.cost)
    eq(2, route.outboundCost)
    eq(2, route.returnCost)
    eq(0, #route.commands)
end)

test("full title distinguishes duplicate names but arbitrary ambiguity is rejected", function()
    local s = setup({
        { id = "one", name = "Bjorn", title = "Bjorn Starszy porucznik", rooms = { tower = true } },
        { id = "two", name = "Bjorn", title = "Bjorn Tobarlsson, mezczyzna", rooms = { stairs = true } },
    })
    eq("two", assert(s.api.resolve("Bjorn Tobarlsson")).npcId)
    local route, why = s.api.resolve("Bjorn")
    eq(nil, route)
    assert(why:find("kilku", 1, true))
    eq(nil, s.api.resolve("Bjorn Nieznany"))
end)

test("unique first name fallback works without treating short as a name", function()
    local s = setup({ { id = "x", name = "Athelstan", title = "", short = "rudy niziolek", rooms = { tower = true } } })
    eq("x", assert(s.api.resolve("Athelstan Shergison")).npcId)
    eq(nil, s.api.resolve("rudy niziolek"))
end)

test("unique first name does not override a contradictory surname in title", function()
    local s = setup()
    local route, reason = s.api.resolve("Rolph Nowak")
    eq(nil, route)
    assert(reason:find("pelnego adresata", 1, true))
    eq("0dfb3842", assert(s.api.resolve("Rolph Ederson")).npcId)
end)

test("Polish diacritics in titles names and observed entities use the core normalization", function()
    local s = setup({ { id = "x", name = "Łukasz", title = "Łukasz Żółciński, gołębiarz",
        short = "siwobrody mężczyzna", rooms = { tower = true } } })
    local route = assert(s.api.resolve("lukasz zolcinski"))
    eq("x", route.npcId)
    eq("x", assert(s.api.resolve("LUKASZ")).npcId)
    local result, done = s.result()
    s.api.navigate(route, done)
    s.entities("ŁUKASZ")
    eq(true, result.ok)
end)

test("normalization collisions do not select an arbitrary accented name", function()
    local s = setup({
        { id = "one", name = "Lukasz", title = "", rooms = { tower = true } },
        { id = "two", name = "Łukasz", title = "", rooms = { stairs = true } },
    })
    eq(nil, s.api.resolve("Lukasz"))
end)

test("candidate without return route is discarded", function()
    local s = setup()
    s.blocked["2:1"] = true
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq(1, #route.rooms)
    eq(3, route.rooms[1])
    eq(8, route.cost)
    s.blocked["3:1"] = true
    eq(nil, s.api.resolve("Rolph Ederson"))
end)

test("transport and multi-command paths are rejected before pickup in either direction", function()
    for _,command in ipairs({ "wejdz na prom", "wsiadz na statek", "zejdz ze statku", "wejdz na tratwe",
        "wsiadz do dylizansu", "wejdz do powozu", "wsiadz do wozu", "n;s", "n\ns" }) do
        for _,direction in ipairs({ "1:2", "2:1" }) do
            local s = setup()
            s.paths[direction] = { "n", command }
            s.blocked["1:3"] = true
            eq(nil, s.api.resolve("Rolph Ederson"), command .. " " .. direction)
            eq(0, #s.actions)
        end
    end
end)

test("return refuses transport even when NPC was encountered away from candidate rooms", function()
    local s = setup()
    s.map, s.room.id = 2, "tower"
    s.paths["2:1"] = { "zejdz ze statku" }
    local result, done = s.result()
    s.api.returnTo({ map = 1, id = "home" }, done)
    eq(false, result.ok)
    eq(0, #s.actions)
    eq(nil, next(s.timers))
end)

test("moving NPC visits rooms and never accepts descriptor, player, or stale snapshot", function()
    local s = setup()
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    eq(true, s.api.inProgress)
    eq(2, s.actions[1].map)
    s.arrive(2)
    s.entities("przygarbiony otyly mezczyzna")
    s.entities("Rolph", "player")
    s.entities("Rolph", "npc", "home")
    eq(0, result.calls)
    s.advance(1.6)
    eq(2, #s.actions)
    eq(3, s.actions[2].map)
    s.arrive(3)
    s.entities("Rolph")
    eq(true, result.ok)
    eq(1, result.calls)
    eq(false, s.api.inProgress)
    eq(nil, next(s.timers))
end)

test("Olaff descriptor at exact known room gets one bounded introduction then candidate handover", function()
    local s = setup({ { id = "olaff", name = "Olaff", title = "Olaff Meier Mlodszy, kupiec",
        short = "sympatyczny pucolowaty mezczyzna", rooms = { tower = true } } }, true)
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Olaff Meier Mlodszy")), done)
    s.arrive(2)
    s.entities("sympatyczny pucolowaty mezczyzna")
    s.advance(1.6)
    eq(1, #s.probes)
    eq("przedstaw sie", s.probes[1])
    eq(1, s.injectedSends)
    eq(0, result.calls)
    s.advance(4.5)
    eq(true, result.ok)
    eq(true, result.detail.candidate)
    eq("tower", result.detail.id)
    eq(2, result.detail.map)
    eq("olaff", result.detail.npcId)
    eq(1, result.calls)
    eq(1, #s.probes)
    eq(nil, next(s.timers))
end)

test("descriptor in unrelated room never triggers early success or an introduction", function()
    local s = setup()
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.entities("przygarbiony otyly mezczyzna")
    s.advance(1)
    eq(0, result.calls)
    eq(0, #s.probes)
    s.arrive(2)
    s.advance(1.6)
    s.arrive(3)
    s.advance(1.6)
    eq(false, result.ok)
    eq(0, #s.probes)
end)

test("absent descriptor or mismatched snapshot cannot produce candidate success", function()
    for _,wrongRoom in ipairs({ false, true }) do
        local s = setup()
        local result, done = s.result()
        s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
        s.arrive(2)
        if wrongRoom then s.entities("przygarbiony otyly mezczyzna", "npc", "home") end
        s.advance(1.6)
        s.arrive(3)
        s.advance(1.6)
        eq(false, result.ok)
        eq(0, #s.probes)
    end
end)

test("probe waits can be stopped without later refreshes, movement or commands", function()
    local s = setup()
    local result, done = s.result()
    local cancel = s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.arrive(2)
    s.entities("przygarbiony otyly mezczyzna")
    s.advance(1.5)
    eq(1, #s.probes)
    local refreshes = s.refreshes
    cancel()
    s.advance(200)
    eq(false, result.ok)
    eq(1, result.calls)
    eq(1, #s.actions)
    eq(1, #s.probes)
    eq(refreshes, s.refreshes)
    eq(nil, next(s.timers))
end)

test("strong NPC identity after probe cancels remaining probe timers", function()
    local s = setup()
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.arrive(2)
    s.entities("przygarbiony otyly mezczyzna")
    s.advance(1.5)
    s.entities("Rolph")
    eq(true, result.ok)
    eq(nil, result.detail)
    eq(nil, next(s.timers))
    local refreshes = s.refreshes
    s.advance(200)
    eq(1, result.calls)
    eq(refreshes, s.refreshes)
end)

test("ambiguous descriptors or player lookalikes do not trigger a probe", function()
    for _,kind in ipairs({ "npc", "player" }) do
        local s = setup()
        local result, done = s.result()
        s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
        s.arrive(2)
        s.snapshot = { room = "tower", entities = {
            { id = "a", name = "przygarbiony otyly mezczyzna", kind = "npc" },
            { id = "b", name = "przygarbiony otyly mezczyzna", kind = kind },
        } }
        s.advance(1.6)
        eq(0, #s.probes)
        eq(0, result.calls)
    end
end)

test("failed owned probe send finishes immediately without scheduled commands", function()
    local s = setup(nil, true)
    s.onProbe = function() return false end
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.arrive(2)
    s.entities("przygarbiony otyly mezczyzna")
    s.advance(1.5)
    eq(false, result.ok)
    eq(1, result.calls)
    eq(1, #s.probes)
    eq(nil, next(s.timers))
end)

test("synchronous stop from owned probe send leaves no refresh or wait behind", function()
    local s = setup(nil, true)
    s.onProbe = function() s.emit("chimera.session.end"); return false end
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.arrive(2)
    s.entities("przygarbiony otyly mezczyzna")
    s.advance(1.5)
    local refreshes = s.refreshes
    s.advance(200)
    eq(false, result.ok)
    eq(1, result.calls)
    eq(1, #s.probes)
    eq(refreshes, s.refreshes)
    eq(nil, next(s.timers))
end)

test("NPC encountered en route cancels walker and completes once", function()
    local s = setup()
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.entities("Rolph")
    eq(true, result.ok)
    eq(1, s.cancellations)
    eq(1, result.calls)
    s.actions[1].done({ ok = true })
    s.advance(200)
    eq(1, result.calls)
    eq(1, #s.actions)
end)

test("stationary cancellation removes timer and cannot start delayed movement", function()
    local s = setup()
    local result, done = s.result()
    local cancel = s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    s.arrive(2)
    eq(false, s.api.permits("n"))
    cancel()
    eq(false, result.ok)
    eq(1, result.calls)
    eq(false, s.api.inProgress)
    eq(nil, next(s.timers))
    s.advance(200)
    eq(1, #s.actions)
    s.entities("Rolph")
    eq(1, result.calls)
end)

test("cancelling active movement ignores late action callbacks", function()
    local s = setup()
    local result, done = s.result()
    local cancel = s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    cancel()
    eq(1, s.cancellations)
    s.arrive(2)
    s.advance(200)
    eq(1, result.calls)
    eq(false, result.ok)
    eq(1, #s.actions)
end)

test("manual takeover permits only current exits, gate and walker status", function()
    local s = setup()
    local _, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    eq(true, s.api.permits("n"))
    eq(true, s.api.permits("polnoc"))
    eq(true, s.api.permits("stan"))
    eq(false, s.api.permits("s"))
    eq(false, s.api.permits("oddaj paczke"))
    eq(false, s.api.permits("zabij rolpha"))
    s.gate = { command = "zapukaj w brame" }
    eq(true, s.api.permits("zapukaj w brame"))
    s.emit("chimera.numpad.pressed", "n")
    eq(false, s.api.inProgress)
    eq(false, s.api.permits("n"))
    eq(1, s.cancellations)
end)

test("exact postal hashes resolve despite generic Bissingen room name", function()
    local s = setup()
    s.maps["200aff4d957642cd"] = 10
    local route = assert(s.api.resolve("Poczta w Bissingen"))
    eq(true, route.postal)
    eq("200aff4d957642cd", route.targetId)
    eq(18,route.cost);eq(36,route.roundTripCost)
    local result, done = s.result()
    s.api.navigate(route, done)
    s.arrive(10, "200aff4d957642cd")
    eq(true, result.ok)
    eq(1, result.calls)
    eq(nil, s.api.resolve("Poczta w Nieznanym Miescie"))
end)

test("source recognises KZ and excludes same source office", function()
    local s = setup()
    s.room.name = "Glowna sala poczty w Krainie Zgromadzenia."
    eq("home", assert(s.api.source()).id)
    s.room.name = "Swiatynia"
    eq(nil, s.api.source())
    s.maps["200aff4d957642cd"] = 10
    eq(nil, s.api.resolve("Poczta w Bissingen", { map = 10, id = "200aff4d957642cd" }))
end)

test("return verifies captured source hash instead of a generic title", function()
    local s = setup()
    s.map, s.room.id = 2, "tower"
    local result, done = s.result()
    s.api.returnTo({ map = 1, id = "home", name = "Poczta" }, done)
    s.arrive(1, "wrong_post_office")
    eq(false, result.ok)
    eq(1, result.calls)
    local good, success = s.result()
    s.api.returnTo({ map = 1, id = "home", name = "Poczta" }, success)
    s.arrive(1, "home")
    eq(true, good.ok)
end)

test("synchronous arrival is safe and needs no stale cancel handle", function()
    local s = setup()
    s.synchronous = true
    local result, done = s.result()
    s.api.returnTo({ map = 1, id = "home" }, done)
    eq(true, result.ok)
    eq(0, s.cancellations)
    eq(nil, next(s.timers))
end)

test("stopping during idz startup still cancels returned action", function()
    local s = setup()
    s.beforeActionReturns = function() s.emit("chimera.numpad.pressed", "n") end
    local result, done = s.result()
    s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
    eq(false, result.ok)
    eq(1, s.cancellations)
    eq(nil, next(s.timers))
end)

test("cleanup and session loss cancel active or stationary operations", function()
    for _,event in ipairs({ "cleanup", "chimera.session.end", "chimera.walk.stopped" }) do
        local s = setup()
        local result, done = s.result()
        s.api.navigate(assert(s.api.resolve("Rolph Ederson")), done)
        s.arrive(2)
        if event == "cleanup" then s.cleanup() else s.emit(event, { reason = "reczne przejecie" }) end
        s.advance(200)
        eq(false, result.ok)
        eq(1, result.calls)
        eq(1, #s.actions)
        eq(nil, next(s.timers))
    end
end)

test("new postal board labels resolve to the authoritative office hashes",function()
    local cases={
        {"Urzad pocztowy Nuln","6f2c03461c2f1438"},
        {"Urzad pocztowy miasta Urbimo","0a647e20ca6f97f7"},
        {"Urzad pocztowy w Campogrotta","269ff0c7899bbd55"},
        {"Poczta w Jouinard","e8337482d2ae8342"},
        {"Poczta w Varieno","78c41b4fab38b2b5"},
        {"Glowny urzad pocztowy Athkatli","a99c7f47e46ffcc8"},
        {"Poczta w Krainie Zgromadzenia","907327356ecc2f87"},
    }
    for i,pair in ipairs(cases) do
        local s=setup();s.maps[pair[2]]=i+10
        local route=assert(s.api.resolve(pair[1]))
        eq(true,route.postal);eq(pair[2],route.targetId);eq(i+10,route.rooms[1])
    end
end)
test("all newly observed postal labels use the shared exact office registry", function()
    local cases = {
        {"Urzad pocztowy w Nuln", "6f2c03461c2f1438"},
        {"Poczta wolnego miasta Nuln", "6f2c03461c2f1438"},
        {"Poczta w Urbimo", "0a647e20ca6f97f7"},
        {"Urzad pocztowy w Urbimo", "0a647e20ca6f97f7"},
        {"Urzad pocztowy w Varieno", "78c41b4fab38b2b5"},
        {"Poczta miasteczka Varieno", "78c41b4fab38b2b5"},
        {"Poczta w Karak Varn", "c55c2924e506dd7f"},
        {"Urzad pocztowy Karak-Varn", "c55c2924e506dd7f"},
        {"Poczta w Kreutzhoffen", "315106e45b840273"},
        {"Urzad pocztowy w Crimmor", "381bc4bb1fc81f0a"},
    }
    for _, pair in ipairs(cases) do
        local s = setup({}); s.maps[pair[2]] = 10
        local route = assert(s.api.resolve(pair[1]))
        eq(true, route.postal); eq(pair[2], route.targetId); eq(10, route.rooms[1])
        eq(18, route.cost); eq(36, route.roundTripCost)
    end
end)

test("known postal identity and kind cannot be overridden by conflicting memory", function()
    local calls = 0
    local s = setup({}, nil, { memory = { find = function(name)
        calls = calls + 1
        return { recipient = name, postal = false, npcId = "wrong", name = "Wrong NPC", roomHashes = { "stairs" } }
    end } })
    s.maps["6f2c03461c2f1438"] = 10
    local route = assert(s.api.resolve("Urzad pocztowy w Nuln"))
    eq(true, route.postal); eq(false, route.learned); eq(nil, route.npcId)
    eq("6f2c03461c2f1438", route.targetId); eq(1, #route.rooms); eq(10, route.rooms[1]); eq(0, calls)
    s.blocked["10:1"] = true
    eq(nil, s.api.resolve("Urzad pocztowy w Nuln")); eq(0, calls)
    s.blocked["10:1"] = nil; s.maps["6f2c03461c2f1438"] = nil
    eq(nil, s.api.resolve("Urzad pocztowy w Nuln")); eq(0, calls)
end)

test("postal aliases still require outbound return and a different source office", function()
    local s = setup({}); local id = "200aff4d957642cd"; s.maps[id] = 10
    s.blocked["1:10"] = true; eq(nil, s.api.resolve("Urzad pocztowy w Bissingen"))
    s.blocked["1:10"] = nil; s.blocked["10:1"] = true
    eq(nil, s.api.resolve("Urzad pocztowy w Bissingen"))
    s.blocked["10:1"] = nil
    eq(true, assert(s.api.resolve("Urzad pocztowy w Bissingen")).postal)
    eq(nil, s.api.resolve("Poczta w Bissingen", { map = 10, id = id }))
    eq(nil, s.api.resolve("Poczta w Nulnn")); eq(nil, s.api.resolve("Poczta w Nieznanym Miescie"))
end)
test("Karak parcel labels override stale learned locations at the broken old office",function()
    for _,label in ipairs({"Poczta w Karak Varn","Urzad pocztowy Karak-Varn","Poczta w Krolestwa Krasnoludow"}) do
        local reads=0
        local s=setup({},nil,{memory={find=function(name)
            reads=reads+1
            return {recipient=name,postal=true,roomHashes={"3de8d58adb6dbe9b"}}
        end}})
        s.maps["c55c2924e506dd7f"]=10;s.maps["3de8d58adb6dbe9b"]=11
        local route=assert(s.api.resolve(label),label)
        eq("c55c2924e506dd7f",route.targetId);eq(10,route.rooms[1]);eq(1,#route.rooms)
        eq(true,route.postal);eq(false,route.learned);eq(0,reads)
        s.maps["c55c2924e506dd7f"]=nil
        eq(nil,s.api.resolve(label),"missing working counter must never fall back to stale bad one")
    end
end)
test("long intercity movement extends the navigation limit while progress continues",function()
    local s=setup();local result,done=s.result()
    local cancel=s.api.navigate(assert(s.api.resolve("Rolph Ederson")),done)
    for i=1,3 do
        s.advance(170);eq(0,result.calls)
        s.room.id="progress"..i;s.map=i+10;s.snapshot={room=s.room.id,entities={}}
        s.emit("chimera.room.changed",{id=s.room.id})
    end
    eq(true,s.api.inProgress);cancel();eq(1,result.calls);eq(false,result.ok)
    s.advance(200);eq(1,result.calls);eq(nil,next(s.timers))
end)

local function memory(record)
    return { find = function(full)
        if full:lower() == record.recipient:lower() then return record end
    end }
end

test("learned full recipient disambiguates catalogue identity and prefers confirmed rooms", function()
    local record = { recipient = "Rolph Ederson", npcId = "right", name = "Rolph", short = "otyly mezczyzna",
        title = "Rolph Ederson, uczony", roomHashes = { "stairs" } }
    local s = setup({
        { id = "wrong", name = "Rolph", short = "rudy mezczyzna", title = "Rolph Ederson", rooms = { home = true } },
        { id = "right", name = "Rolph", short = "otyly mezczyzna", title = "Rolph, uczony", rooms = { tower = true } },
    }, nil, { memory = memory(record) })
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq(true, route.learned); eq("right", route.npcId); eq("Rolph Ederson, uczony", route.npcTitle)
    eq(3, route.rooms[1]); eq(2, route.rooms[2]); eq(2, #route.rooms)
    eq(8, route.cost); eq(true, route.learnedRooms[3]); eq(nil, route.learnedRooms[2])
    local result, done = s.result(); s.api.navigate(route, done)
    eq(3, s.actions[1].map)
    s.entities("Rolph"); eq(0, result.calls); eq(0, #s.probes)
    eq(nil, s.api.deliveryEvidence(route).npc)
    s.arrive(3); s.entities("Rolph")
    eq(nil, s.api.deliveryEvidence(route).npc)
    eq(true, result.ok)
    eq(true, result.detail.candidate); eq(true, result.detail.locationVerified)
    eq(0, #s.probes); eq(1, #s.actions)
    eq(1, #record.roomHashes); eq("stairs", record.roomHashes[1]); eq(nil, record.map)
end)

test("same catalogue ID with a contradictory full title cannot lend locations or identity", function()
    local record = { recipient = "Rolph Ederson", npcId = "samehash", name = "Rolph", short = "otyly mezczyzna",
        title = "Rolph Ederson, uczony", roomHashes = { "stairs" } }
    local s = setup({ { id = "samehash", name = "Rolph", short = "otyly mezczyzna", title = "Rolph Nowak, kupiec",
        rooms = { tower = true } } }, nil, { memory = memory(record) })
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq(true, route.identityConflict); eq(true, route.locationVerified)
    eq(1, #route.rooms); eq(3, route.rooms[1]); eq(nil, route.roomIds[2])
    local result, done = s.result(); s.api.navigate(route, done)
    s.entities("Rolph"); eq(0, result.calls); eq(nil, s.api.deliveryEvidence(route).npc)
    s.arrive(3, "stairs"); eq(true, result.ok); eq(true, result.detail.locationVerified)
    s.entities("Rolph Ederson"); eq(nil, s.api.deliveryEvidence(route).npc)
    record.roomHashes = {}
    eq(nil, s.api.resolve("Rolph Ederson"))
end)

test("full named identity resolves a learned short-name collision without descriptor guessing", function()
    local s = setup({
        { id = "one", name = "Rolph", short = "otyly mezczyzna", rooms = { tower = true } },
        { id = "two", name = "Rolph", short = "rudy mezczyzna", rooms = { stairs = true } },
    }, nil, { memory = memory({ recipient = "Rolph Ederson", npcId = "one", name = "Rolph",
        short = "otyly mezczyzna", roomHashes = { "tower" } }) })
    local route = assert(s.api.resolve("Rolph Ederson")); eq(true, route.ambiguousName)
    local result, done = s.result(); s.api.navigate(route, done)
    s.entities("Rolph Ederson"); eq(true, result.ok)
    eq("one", s.api.deliveryEvidence(route).npc.npcId)
end)

test("partial learned identity without ID or name stays room-only", function()
    local rows = {
        { id = "one", name = "Rolph", short = "otyly mezczyzna", rooms = { tower = true } },
        { id = "two", name = "Rolph", short = "rudy mezczyzna", rooms = { stairs = true } },
    }
    for _, identity in ipairs({ { name = "Rolph", short = "otyly mezczyzna" }, { npcId = "one" } }) do
        identity.recipient, identity.roomHashes = "Rolph Ederson", { "stairs" }
        local s = setup(rows, nil, { memory = memory(identity) })
        local route = assert(s.api.resolve("Rolph Ederson"))
        eq(nil, route.npcId); eq(nil, route.npcName); eq(true, route.locationVerified)
        eq(1, #route.rooms); eq(3, route.rooms[1])
    end
end)

test("learned identity never borrows rooms from a different descriptor or ID", function()
    local s = setup({ { id = "other", name = "Rolph", short = "rudy mezczyzna", rooms = { tower = true } } }, nil,
        { memory = memory({ recipient = "Rolph Ederson", npcId = "old", name = "Rolph", short = "otyly mezczyzna",
            roomHashes = { "stairs" } }) })
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq("old", route.npcId); eq(1, #route.rooms); eq(3, route.rooms[1])
    local byName = setup({ { id = "new", name = "Rolph", short = "rudy mezczyzna", rooms = { tower = true } } }, nil,
        { memory = memory({ recipient = "Rolph Ederson", name = "Rolph", roomHashes = { "stairs" } }) })
    eq(1, #assert(byName.api.resolve("Rolph Ederson")).rooms)
end)

test("portable learned hashes resolve new map numbers after reload without NPC catalogue", function()
    local record = { recipient = "Zygmunt Nowy", roomHashes = { "tower" } }
    local s = setup({}, nil, { memory = memory(record) })
    local route = assert(s.api.resolve("Zygmunt Nowy"))
    eq(2, route.rooms[1]); eq(true, route.locationVerified)
    s.maps.tower = 12
    local reloaded = assert(s.api.resolve("Zygmunt Nowy"))
    eq(12, reloaded.rooms[1]); eq("tower", reloaded.roomIds[12]); eq(nil, reloaded.roomIds[2])
    eq(44, reloaded.cost); eq(nil, record.map); eq("tower", record.roomHashes[1])
    eq(nil, s.api.resolve("Zygmunt Inny"))
end)

test("room-only memories reach only the exact verified candidate without descriptor probes", function()
    local s = setup({}, nil, { memory = memory({ recipient = "Zygmunt Nowy", roomHashes = { "tower" } }) })
    local route = assert(s.api.resolve("Zygmunt Nowy"))
    local result, done = s.result(); s.api.navigate(route, done)
    s.entities("Zygmunt Nowy"); eq(0, result.calls)
    s.arrive(2, "tower")
    eq(true, result.ok); eq(true, result.detail.candidate); eq(true, result.detail.locationVerified)
    eq("tower", result.detail.id); eq(0, #s.probes); eq(0, s.refreshes)
    s.advance(200); eq(1, result.calls); eq(1, #s.actions)
    local wrong, failed = s.result(); s.api.navigate(route, failed)
    s.arrive(2, "unrelated")
    eq(false, wrong.ok); eq(0, #s.probes)
end)

test("empty unmapped and unreachable learned locations never fall back to guessed recipients", function()
    for _, hashes in ipairs({ {}, { "unmapped" }, { "tower" } }) do
        local s = setup(nil, nil, { memory = memory({ recipient = "Rolph Ederson", roomHashes = hashes }) })
        s.blocked["2:1"] = true
        eq(nil, s.api.resolve("Rolph Ederson")); eq(0, #s.actions)
    end
    local s = setup({}, nil, { memory = memory({ recipient = "Zygmunt Nowy", roomHashes = { "tower" } }) })
    s.blocked["1:2"] = true
    eq(nil, s.api.resolve("Zygmunt Nowy"))
    s.blocked["1:2"] = nil; s.paths["2:1"] = { "wejdz na prom" }
    eq(nil, s.api.resolve("Zygmunt Nowy"))
end)

test("unreachable learned room may use only the same catalogue identity wandering room", function()
    local s = setup(nil, nil, { memory = memory({ recipient = "Rolph Ederson", npcId = "0dfb3842",
        name = "Rolph", short = "przygarbiony otyly mezczyzna", roomHashes = { "unmapped" } }) })
    local route = assert(s.api.resolve("Rolph Ederson"))
    eq(2, #route.rooms); eq(2, route.rooms[1]); eq(nil, route.learnedRooms[2])
end)

test("learned lookup refuses a record belonging to another full recipient", function()
    local s = setup(nil, nil, { memory = { find = function()
        return { recipient = "Rolph Nowak", name = "Rolph", roomHashes = { "tower" } }
    end } })
    local route, why = s.api.resolve("Rolph Ederson")
    eq(nil, route); assert(why:find("innego adresata", 1, true))
end)

test("learned postal destination keeps one-way cost and checks the chosen exact hash", function()
    local s = setup({}, nil, { memory = memory({ recipient = "Poczta w Nowym Miescie", postal = true,
        roomHashes = { "stairs", "tower" } }) })
    local route = assert(s.api.resolve("Poczta w Nowym Miescie"))
    eq(true, route.postal); eq(4, route.cost); eq(8, route.roundTripCost)
    local result, done = s.result(); s.api.navigate(route, done); eq(3, s.actions[1].map)
    s.arrive(3, "stairs"); eq(true, result.ok)
    s.map, s.room.id = 1, "home"
    local excluded = assert(s.api.resolve("Poczta w Nowym Miescie", { map = 3, id = "stairs" }))
    eq(1, #excluded.rooms); eq(2, excluded.rooms[1])
end)

test("delivery evidence requires mapped current hash and an unambiguous named NPC", function()
    local s = setup(); local route = assert(s.api.resolve("Rolph Ederson"))
    s.map, s.room.id = 2, "tower"; s.entities("Rolph")
    local evidence = assert(s.api.deliveryEvidence(route))
    eq(true, evidence.verified); eq("tower", evidence.roomHash); eq(2, evidence.map)
    eq("Rolph Ederson", evidence.recipient); eq("0dfb3842", evidence.npc.npcId)
    eq("Rolph", evidence.npc.name); eq("przygarbiony otyly mezczyzna", evidence.npc.short)
    eq(nil, evidence.handover); eq(nil, evidence.reward)
    s.entities("przygarbiony otyly mezczyzna"); eq(nil, s.api.deliveryEvidence(route).npc)
    s.entities("Rolph", "player"); eq(nil, s.api.deliveryEvidence(route).npc)
    s.entities("Rolph", "npc", "home"); eq(nil, s.api.deliveryEvidence(route).npc)
    s.snapshot = { room = "tower", entities = { { name = "Rolph", kind = "npc" }, { name = "Rolph", kind = "npc" } } }
    eq(nil, s.api.deliveryEvidence(route).npc)
    s.snapshot.entities[2].kind = "player"; eq(nil, s.api.deliveryEvidence(route).npc)
    s.evidenceHash = "different"; eq(false, s.api.deliveryEvidence(route).verified)
    s.map = nil; eq(nil, s.api.deliveryEvidence(route))
end)

test("handover evidence refreshes catalogue conflicts introduced after planning", function()
    local records = { { id = "one", name = "Rolph", short = "otyly mezczyzna", title = "Rolph Ederson, uczony",
        rooms = { tower = true } } }
    local s = setup(records)
    local route = assert(s.api.resolve("Rolph Ederson")); eq(nil, route.ambiguousName)
    s.map, s.room.id = 2, "tower"; s.entities("Rolph")
    eq("one", s.api.deliveryEvidence(route).npc.npcId)
    records[2] = { id = "two", name = "Rolph", short = "rudy mezczyzna", title = "Rolph Nowak, kupiec",
        rooms = { stairs = true } }
    local ambiguous = s.api.deliveryEvidence(route)
    eq(true, ambiguous.verified); eq("tower", ambiguous.roomHash); eq(nil, ambiguous.npc)
    eq(nil, route.ambiguousName)
    s.entities("Rolph Ederson"); eq("one", s.api.deliveryEvidence(route).npc.npcId)
    records[2] = nil; records[1].title = "Rolph Nowak, kupiec"
    local contradicted = s.api.deliveryEvidence(route)
    eq(true, contradicted.verified); eq(nil, contradicted.npc); eq(nil, route.identityConflict)
end)

test("room-only delivery evidence records a room and never invents an NPC from the route", function()
    local s = setup({}, nil, { memory = memory({ recipient = "Zygmunt Nowy", roomHashes = { "tower" } }) })
    local route = assert(s.api.resolve("Zygmunt Nowy"))
    s.map, s.room.id = 2, "tower"; s.entities("siwy mezczyzna")
    local proof = s.api.deliveryEvidence(route)
    eq(true, proof.verified); eq("tower", proof.roomHash); eq(nil, proof.npc)
    s.entities("Zygmunt Nowy"); eq(nil, s.api.deliveryEvidence(route).npc)
end)

test("postal and unknown named entities never invent persistent catalogue identity", function()
    local s = setup(); local route = assert(s.api.resolve("Rolph Ederson"))
    s.map, s.room.id = 2, "tower"; s.entities("Rolph")
    route.postal = true
    eq(nil, s.api.deliveryEvidence(route).npc)
    route.postal, route.npcId = false, nil
    eq(nil, s.api.deliveryEvidence(route).npc)
    route.npcId = 123
    eq(nil, s.api.deliveryEvidence(route).npc)
    route.npcId = " "
    eq(nil, s.api.deliveryEvidence(route).npc)
end)

test("learned room-only navigation remains cancellable without late success", function()
    local s = setup({}, nil, { memory = memory({ recipient = "Zygmunt Nowy", roomHashes = { "tower" } }) })
    local result, done = s.result(); local cancel = s.api.navigate(assert(s.api.resolve("Zygmunt Nowy")), done)
    cancel(); s.arrive(2, "tower"); s.advance(200)
    eq(false, result.ok); eq(1, result.calls); eq(0, #s.probes); eq(nil, next(s.timers))
end)
test("an imported postal alias cannot restore a disabled courier office", function()
    local s=setup({},nil,{memory=memory({recipient="Historyczna Poczta",postal=true,
        roomHashes={"3de8d58adb6dbe9b"}})})
    s.maps["3de8d58adb6dbe9b"]=10
    local route,why=s.api.resolve("Historyczna Poczta")
    eq(nil,route);assert(why);eq(0,#s.actions)
end)
print("PASS " .. passed .. " standalone NPC navigation tests")
