-- Standalone: lua chimera-native/tests/test_npc.lua (no native test harness).
local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tests/test_city_budget%.lua$") or "."
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
    function ctx:emit(event,value) s.emit(event,value) end
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

local function cityFixture(settings)
    settings=settings or {}
    local starts,rounds=0,0
    local scope={name="Kreutzhofen",areaId="city-a"}
    local options={city={scope=function() return scope end,contains=function(_,map) return map==1 end,
        plan=function(_,from,to) if from==to then return {from=from,target=to,cost=0,steps={}} end end,
        rooms=function() return {1} end},
        runLocal=function() error("one-room patrol must never move") end,
        onSearchStart=function(route,area) starts=starts+1;if settings.onStart then settings.onStart(route,area) end end,
        onSearchWait=function() rounds=rounds+1 end}
    if settings.remaining~=nil then options.searchBudget=function() return settings.remaining end end
    if settings.throwBudget then options.searchBudget=function() error("budget failure") end end
    if settings.city then options.city=settings.city end
    if settings.runLocal then options.runLocal=settings.runLocal end
    local records={{id="bruno-id",name="Bruno",short="starszy mezczyzna",title="Bruno Rottel, kapitan patrolu",rooms={home=true}}}
    local s=setup(records,true,options)
    s.route=settings.route or {native=true,name="Bruno Rottel",npcId="bruno-id",npcName="Bruno",npcTitle="Bruno Rottel, kapitan patrolu",
        npcShort="starszy mezczyzna",rooms={1},roomIds={[1]="home"},commands={}}
    s.starts=function() return starts end;s.rounds=function() return rounds end
    return s
end

test("city budget expires despite completed rounds refreshing the inactivity watchdog",function()
    local s=cityFixture({remaining=65});local result,done=s.result()
    s.api.navigate(s.route,done);eq(1,s.starts());s.advance(64.9)
    eq(0,result.calls);assert(s.rounds()>=2,"fixture must finish and repeat rounds")
    s.advance(0.2);eq(1,result.calls);eq(false,result.ok);eq("limit czasu szukania adresata w miescie",result.reason)
    s.advance(600);eq(1,result.calls);eq(false,s.api.inProgress)
end)
test("default total city search is five minutes even with live room events",function()
    local s=cityFixture();local result,done=s.result();s.api.navigate(s.route,done)
    for _=1,29 do s.advance(10);s.emit("chimera.room.changed") end
    eq(0,result.calls);s.advance(10.1);eq(1,result.calls);eq(false,result.ok)
end)
test("expired resumed budget finishes once without walking or waiting",function()
    for _,remaining in ipairs({0,-1}) do
        local s=cityFixture({remaining=remaining});local result,done=s.result();s.api.navigate(s.route,done)
        eq(1,s.starts());eq(1,result.calls);eq(false,result.ok);eq(0,#s.actions)
        s.advance(600);eq(1,result.calls)
    end
end)
test("fresh recipient appearance cancels the hard search timer",function()
    local s=cityFixture({remaining=15});local result,done=s.result();s.api.navigate(s.route,done)
    s.advance(3);s.entities("Bruno Rottel")
    eq(1,result.calls);eq(true,result.ok);s.advance(600);eq(1,result.calls)
end)
test("STOP cancellation clears the hard timer and a new operation gets its own remaining budget",function()
    local settings={remaining=20};local s=cityFixture(settings);local first,done=s.result()
    local cancel=s.api.navigate(s.route,done);s.advance(4);cancel();eq(1,first.calls);eq(false,first.ok)
    settings.remaining=3
    local second,done2=s.result();s.api.navigate(s.route,done2);eq(2,s.starts())
    s.advance(3.1);eq(1,second.calls);eq("limit czasu szukania adresata w miescie",second.reason)
    s.advance(600);eq(1,first.calls);eq(1,second.calls)
end)
test("unusable budget getter fails closed rather than searching forever",function()
    local s=cityFixture({throwBudget=true});local result,done=s.result();s.api.navigate(s.route,done)
    eq(1,result.calls);eq(false,result.ok);s.advance(600);eq(1,result.calls)
end)
test("a closed patrol building is skipped until the operation ends and never refreshes its hard budget",function()
    local env
    local attempts={}
    local hashes={[1]="home",[2]="tower",[3]="stairs"}
    local scope={name="Kreutzhofen",areaId="city-a"}
    local settings={remaining=70,route={native=true,name="Bruno Rottel",npcId="bruno-id",npcName="Bruno",
        npcTitle="Bruno Rottel, kapitan patrolu",rooms={2},roomIds={[2]="tower"},commands={}},
        city={scope=function() return scope end,contains=function(_,map) return map>=1 and map<=3 end,
            rooms=function() return {1,2,3} end,
            plan=function(_,from,to)
                if from==to then return {from=from,fromId=hashes[from],target=to,targetId=hashes[to],cost=0,steps={}} end
                return {from=from,fromId=hashes[from],target=to,targetId=hashes[to],cost=1,
                    steps={{map=to,id=hashes[to],cmd="n",weight=1}}}
            end},
        runLocal=function(plan,done)
            local target=plan.target;attempts[target]=(attempts[target] or 0)+1
            if target==2 then
                env.emit("chimera.walk.stopped",{reason="lokal zamkniety do rana; krok nie zostal wykonany"})
                done({ok=false,reason="lokal zamkniety do rana; krok nie zostal wykonany"})
            else
                env.map=target;env.room.id=hashes[target];env.snapshot={room=hashes[target],entities={}}
                done({ok=true})
            end
            return function() end
        end}
    env=cityFixture(settings);local result,done=env.result();env.api.navigate(env.route,done)
    env.advance(69.9);eq(0,result.calls);eq(1,attempts[2]);assert((attempts[3] or 0)>=1)
    env.advance(0.2);eq(1,result.calls);eq(false,result.ok)
    eq("limit czasu szukania adresata w miescie",result.reason)
    eq(nil,env.route.cityClosed,"closed rooms must not become permanent recipient metadata")
    settings.remaining=8
    local nextResult,nextDone=env.result();env.api.navigate(env.route,nextDone);env.advance(8.1)
    eq(2,attempts[2],"new operation may retry the temporary closure");eq(1,nextResult.calls)
end)

local checkpoint=dofile(root.."/chimera_wtyczki/chimera_paczki/checkpoint.lua")
test("search elapsed and undelivered return intent survive character checkpoint reload",function()
    local stored
    local c=checkpoint(nil,{now=function() return 1000 end,save=function(value) stored=value;return true end})
    eq(true,c.put("Yarrim",{job={name="Bruno Rottel",searchElapsed=123.75,returningUndelivered=true}}))
    eq(true,c.put("Morrid",{job={name="Inny Adresat",searchElapsed=0,returningUndelivered=false}}))
    local restored=checkpoint(stored)
    eq(123.75,restored.get("Yarrim").job.searchElapsed);eq(true,restored.get("Yarrim").job.returningUndelivered)
    eq(0,restored.get("Morrid").job.searchElapsed);eq(false,restored.get("Morrid").job.returningUndelivered)
end)
test("checkpoint rejects malformed search state without replacing the valid course",function()
    local c=checkpoint(nil,{now=function() return 1000 end})
    eq(true,c.put("Yarrim",{job={name="Bruno Rottel",searchElapsed=7}}))
    for _,value in ipairs({-1,"10",math.huge,0/0,false}) do
        eq(false,c.put("Yarrim",{job={name="Bruno Rottel",searchElapsed=value}}))
        eq(7,c.get("Yarrim").job.searchElapsed)
    end
    eq(false,c.put("Yarrim",{job={name="Bruno Rottel",returningUndelivered="yes"}}))
    eq(true,c.put("OldProfile",{job={name="Old Adresat"}}))
    eq(nil,c.get("OldProfile").job.searchElapsed);eq(false,c.get("OldProfile").job.returningUndelivered)
end)
print("CITY_BUDGET: "..passed.." scenarios passed")
