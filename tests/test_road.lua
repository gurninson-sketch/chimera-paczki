-- texlua chimera-native/tests/test_road.lua; no native walker is involved.
local script = arg[0]:gsub("\\", "/")
local root = script:match("^(.*)/tests/test_road%.lua$") or "."
local upstream = root .. "/../chimera-main"
package.path = root .. "/chimera_wtyczki/?.lua;" .. upstream .. "/src/?.lua;" .. upstream .. "/src/?/init.lua;" .. package.path
local Bus = require("chimera.core.bus")
local create = dofile(root .. "/chimera_wtyczki/chimera_paczki/road.lua")
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

local function setup()
    local s = { names={},areas={},areaNames={},now=0, map=1, hashes={ [1]="h1", [2]="h2", [3]="h3", [4]="h4" },
        room={ id="h1", name="Droga", exits={ polnoc="h2" } }, timers={}, triggers={}, cleanups={}, errors={},
        sent={}, events={}, nativeGates={}, gates={}, gatesByEdge={}, sequence=0, ownSend=false, manualStops=0,
        path={ dirs={"n"}, rooms={2}, weights={2} } }
    local bus = Bus.new(function(_, _, problem) s.errors[#s.errors+1]=problem end)
    bus.mirror = false
    local ctx = {}
    function ctx:on(event, callback) return { bus=bus:on(event,callback) } end
    function ctx:emit(event, value)
        s.events[#s.events+1]={event=event,value=value}
        bus:emit(event,value)
    end
    function ctx:timer(seconds, callback)
        s.sequence=s.sequence+1
        local handle={ order=s.sequence }
        s.timers[handle]={at=s.now+seconds,callback=callback}
        return handle
    end
    function ctx:trigger(_,callback)
        local handle={}
        s.triggers[handle]=callback
        return handle
    end
    function ctx:cancel(handle)
        if handle.bus then bus:off(handle.bus) end
        s.timers[handle],s.triggers[handle]=nil,nil
    end
    function ctx:cleanup(callback) s.cleanups[#s.cleanups+1]=callback end
    function ctx:send() error("road must use the injected owned sender") end
    function s.emit(event,...)
        bus:emit(event,...)
        eq(0,#s.errors,table.concat(s.errors,"\n"))
    end
    function s.on(event,callback) return ctx:on(event,callback) end
    function s.line(text)
        for _,callback in pairs(s.triggers) do callback(text) end
        eq(0,#s.errors,table.concat(s.errors,"\n"))
    end
    function s.advance(seconds)
        local ending=s.now+seconds
        while true do
            local selected,earliest
            for handle,timer in pairs(s.timers) do
                if timer.at<=ending and (not earliest or timer.at<earliest or
                    (timer.at==earliest and handle.order<selected.order)) then selected,earliest=handle,timer.at end
            end
            if not selected then break end
            s.now=earliest
            local timer=s.timers[selected]
            s.timers[selected]=nil
            timer.callback()
        end
        s.now=ending
        eq(0,#s.errors,table.concat(s.errors,"\n"))
    end
    function s.cleanup() for i=#s.cleanups,1,-1 do s.cleanups[i]() end end
    function s.result()
        local result={calls=0}
        return result,function(value) result.calls,result.value=result.calls+1,value end
    end
    function s.commands()
        local list={}
        for _,entry in ipairs(s.sent) do list[#list+1]=entry.command end
        return table.concat(list,"|")
    end
    function s.count(event)
        local n=0
        for _,entry in ipairs(s.events) do if entry.event==event then n=n+1 end end
        return n
    end
    -- Simulate the real GMCP -> room.changed -> mapper.moved nesting with the
    -- real upstream Bus; Room.Info arrives before the mapper has moved.
    ctx:on("chimera.room.changed",function()
        for map,id in pairs(s.hashes) do if id==s.room.id then s.map=map; s.emit("chimera.mapper.moved",map,s.room);return end end
        s.emit("chimera.mapper.lost")
    end)
    ctx:on("chimera.walk.started",function() s.walking=true end)
    ctx:on("chimera.walk.arrived",function() s.walking=false end)
    ctx:on("chimera.walk.stopped",function() s.walking=false end)
    function s.arrive(map,exits)
        s.room={id=s.hashes[map],name="Droga "..map,exits=exits or {wschod="h3"}}
        s.emit("chimera.room.info",s.room)
        s.lastHow=s.walking and "chodzik" or "przeniesienie"
        s.emit("chimera.room.changed",{id=s.room.id,how=s.lastHow})
    end
    _G.getRoomName=function(map) return s.names[map] end
    _G.getRoomArea=function(map) return s.areas[map] end
    _G.getRoomAreaName=function(area) return s.areaNames[area] end
    _G.getPath=function(from,target)
        if s.noPath then return false end
        _G.speedWalkDir,_G.speedWalkPath,_G.speedWalkWeight=s.path.dirs,s.path.rooms,s.path.weights
        return true
    end
    local opts={
        gmcp={room=function() return s.room end},
        mapper={current_room=function() return s.map end,chimera_id=function(map) return s.hashes[map] end},
        locations={gate=function(id) return s.nativeGates[id] end},
        gates=s.gates,gatesByEdge=s.gatesByEdge,delay=function() return s.delay or 0.1 end,
        send=function(command)
            local previous=s.ownSend
            s.ownSend=true -- the injected C:sendCommand ownership scope
            if not s.ownSend then s.manualStops=s.manualStops+1 end
            s.sent[#s.sent+1]={command=command,at=s.now}
            if s.onSend then s.onSend(command) end
            s.ownSend=previous
            return not s.failSend
        end,
        blockCommand=function(command) return s.block and s.block(command) or false end,
        blockRoom=function(map,id) if s.roomBlock then return s.roomBlock(map,id) end return false end,
    }
    s.api=create(ctx,opts)
    function s.start(target)
        local result,done=s.result()
        local plan=assert(s.api.plan(1,target or 2))
        s.cancel=s.api.run(plan,done)
        return result,plan
    end
    return s
end

test("plan snapshots route globals, costs and hashes",function()
    local s=setup()
    s.path={dirs={"n","up"},rooms={2,3},weights={2,7}}
    local plan=assert(s.api.plan(1,3))
    eq(9,plan.cost);eq("u",plan.steps[2].cmd);eq("h3",plan.steps[2].id)
    s.path.dirs[1]="kill";s.path.rooms[1]=4;s.path.weights[1]=900
    eq("n",plan.steps[1].cmd);eq(2,plan.steps[1].map);eq(2,plan.weights[1])
    eq("n",plan.commands[1]);eq(2,plan.rooms[1])
end)

test("plan rejects incomplete paths, missing hashes, transport and multiple commands",function()
    for _,command in ipairs({"wejdz na prom","zejdz ze statku","wsiadz do dylizansu","n;s","n\ns"}) do
        local s=setup();s.path.dirs={command}
        eq(nil,s.api.plan(1,2),command)
    end
    local s=setup();s.hashes[2]=nil;eq(nil,s.api.plan(1,2))
    s=setup();s.path.rooms={2,3};eq(nil,s.api.plan(1,2))
    s=setup();s.noPath=true;eq(nil,s.api.plan(1,2))
    s=setup();s.block=function(cmd) return cmd=="n" end;eq(nil,s.api.plan(1,2))
end)

test("same-room plan completes synchronously without sending",function()
    local s=setup();local plan=assert(s.api.plan(1,1));eq(0,#plan.steps);eq(0,plan.cost)
    local result,done=s.result();local cancel=s.api.run(plan,done)
    eq(true,result.value.ok);eq(0,#s.sent);eq(1,s.count("chimera.walk.started"));eq(1,s.count("chimera.walk.arrived"))
    cancel();eq(1,result.calls);eq("idle",s.api.phase())
end)

test("ordinary owned steps wait for expected map and hash and preserve walker classification",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={2,2}}
    local result,plan=s.start(3);eq("n",s.commands());eq("moving",s.api.phase())
    s.arrive(2);eq("chodzik",s.lastHow);eq(0,result.calls);eq("n",s.commands())
    plan.steps[2].cmd="kill" -- run also keeps its own copy
    s.advance(0.1);eq("n|e",s.commands());s.arrive(3)
    eq(true,result.value.ok);eq(1,result.calls);eq(0,s.manualStops);eq(nil,next(s.timers))
    s.advance(100);eq("n|e",s.commands());eq(1,s.count("chimera.walk.arrived"))
end)

test("named GMCP exit is selected by the planned target hash",function()
    local s=setup();s.path.dirs={"nw"};s.room.exits={polana="h2",polnocny_zachod="h4"}
    local result=s.start();eq("polana",s.commands());s.arrive(2);eq(true,result.value.ok)
end)

test("named GMCP aliases never replace a safe path with climbing or boarding",function()
    for _,unsafe in ipairs({"wespnij sie na gore","wejdz na prom"}) do
        local s=setup();s.path.dirs={"nw"}
        s.room.exits={[unsafe]="h2",["zejdz po schodach"]="h2"}
        local result=s.start();eq("zejdz po schodach",s.commands())
        s.arrive(2);eq(true,result.value.ok);eq(0,s.manualStops)
    end
end)

test("missing unmarked exit uses exactly the copied map command",function()
    local s=setup();s.room.exits={poludnie="h4"}
    local result=s.start();eq("n",s.commands());s.arrive(2);eq(true,result.value.ok);eq(0,s.manualStops)
end)

test("delayed gate opening waits for acknowledgement before one owned direction",function()
    local s=setup();s.room.exits={poludnie="h4",zachod="h3"}
    s.nativeGates.h1={command="uderz w brame"};s.nativeGates.h2={command="uderz w brame"}
    local result=s.start();eq("uderz w brame",s.commands());eq("gate",s.api.phase())
    s.advance(0.1);s.line("Uderzasz w brame.");s.line("Gdzies z gory slyszysz krzyk: Czekac tam!")
    s.line("Otwierasz swoj plecak.");s.advance(5)
    eq("uderz w brame",s.commands());eq(0,result.calls)
    s.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.")
    eq("gate-step",s.api.phase());eq("uderz w brame",s.commands())
    s.advance(0.1);eq("uderz w brame|n",s.commands());eq(0,s.manualStops)
    s.arrive(2);eq(true,result.value.ok);eq(nil,next(s.timers))
end)

test("already-open acknowledgement can arrive synchronously during owned send",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    s.onSend=function(command) if command=="uderz w brame" then s.line("Alez brama jest przeciez otwarta!") end end
    local result=s.start();s.advance(0.1);eq("uderz w brame|n",s.commands())
    s.line("Alez brama jest przeciez otwarta!");s.advance(0.1);eq("uderz w brame|n",s.commands())
    s.arrive(2);eq(true,result.value.ok)
end)

test("ordinary marked street takes available exit without a meaningless opener",function()
    local s=setup();s.nativeGates.h1={command="uderz w brame"};s.nativeGates.h2={command="uderz w brame"}
    local result=s.start();eq("n",s.commands());s.line("Hmm?");s.arrive(2)
    eq(true,result.value.ok);eq("n",s.commands())
end)

test("closed wrota despite a visible exit opens and retries only after confirmation",function()
    local s=setup();s.path.dirs={"w"};s.room.exits={zachod="h2"}
    s.gates.h1={command="uderz we wrota",direction="w",to="h2"}
    local result=s.start();eq("w",s.commands())
    s.line("Zelazne wrota sa zamkniete na zamek!");eq("w|uderz we wrota",s.commands())
    s.advance(4);eq("w|uderz we wrota",s.commands())
    s.line("Z glosnym trzaskiem wrota zostaja otwarte.");s.advance(0.1)
    eq("w|uderz we wrota|w",s.commands());s.arrive(2);eq(true,result.value.ok)
end)

test("gate closing cancels queued direction and permits only one bounded reopening",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start()
    s.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.")
    s.line("Przy wtorze zgrzytow i trzaskow brama zostaje zamknieta.")
    eq("uderz w brame|uderz w brame",s.commands());s.advance(0.1)
    eq("uderz w brame|uderz w brame",s.commands())
    s.line("Alez brama jest przeciez otwarta!");s.advance(0.1)
    eq("uderz w brame|uderz w brame|n",s.commands());s.arrive(2);eq(true,result.value.ok)
end)

test("confirmed closed denials cannot create an infinite gate retry loop",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start()
    for _=1,2 do
        s.line("Alez brama jest przeciez otwarta!");s.advance(0.1)
        s.line("Nie widzisz zadnego wyjscia prowadzacego na polnoc.")
    end
    eq(false,result.value.ok);eq("uderz w brame|n|uderz w brame|n",s.commands());eq(nil,next(s.timers))
end)

test("closing announcement cannot repeat an unconfirmed in-flight move",function()
    local s=setup();s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start();eq("n",s.commands())
    s.line("Przy wtorze zgrzytow i trzaskow brama zostaje zamknieta.")
    s.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.")
    s.advance(1);eq("n",s.commands());eq(0,result.calls)
    s.arrive(2);eq(true,result.value.ok);eq("n",s.commands())
end)

test("opened gate may reveal a named exit instead of the stale map direction",function()
    local s=setup();s.path.dirs={"nw"};s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start();s.room.exits={polana="h2"}
    s.line("Alez brama jest przeciez otwarta!");s.advance(0.1)
    eq("uderz w brame|polana",s.commands());s.arrive(2);eq(true,result.value.ok)
end)

test("Hmm opener can fall back once only if the intended exit becomes available",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start();s.room.exits={polnoc="h2"};s.line("Hmm?");s.advance(0.1)
    eq("uderz w brame|n",s.commands());s.arrive(2);eq(true,result.value.ok)
end)

test("STOP during gate wait or queued crossing prevents every late command",function()
    for _,opened in ipairs({false,true}) do
        local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
        local result=s.start()
        if opened then s.line("Alez brama jest przeciez otwarta!") end
        s.cancel();s.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.");s.advance(100)
        eq(false,result.value.ok);eq(1,result.calls);eq("uderz w brame",s.commands());eq(nil,next(s.timers))
        eq(1,s.count("chimera.walk.stopped"))
    end
end)

test("gate timeout never substitutes elapsed time for an opening acknowledgement",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz w brame",to="h2"}
    local result=s.start();s.advance(29.9);eq(0,result.calls);s.advance(0.1)
    eq(false,result.value.ok);eq("uderz w brame",s.commands());eq(nil,next(s.timers))
end)

test("a silent step times out after fifteen seconds without repeating movement",function()
    local s=setup();local result=s.start();s.advance(14.9);eq(0,result.calls);s.advance(0.1)
    eq(false,result.value.ok);eq("n",s.commands());s.advance(100);eq("n",s.commands());eq(1,result.calls)
end)

test("unexpected target or lost mapper cancels the rest of a route",function()
    for _,lost in ipairs({false,true}) do
        local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={2,2}}
        local result=s.start(3)
        if lost then s.emit("chimera.mapper.lost") else s.arrive(4) end
        s.advance(100);eq(false,result.value.ok);eq("n",s.commands());eq(nil,next(s.timers))
    end
end)

test("room information alone cannot acknowledge an expected hash with the old map position",function()
    local s=setup();local result=s.start()
    s.room={id="h2",exits={}};s.emit("chimera.room.info",s.room)
    eq(0,result.calls);eq("moving",s.api.phase())
    s.emit("chimera.room.changed",{id="h2"});eq(true,result.value.ok)
end)

test("specific gate edges do not apply to a different neighbouring route",function()
    local s=setup();s.room.exits={};s.gates.h1={command="uderz we wrota",to="h4",direction="w"}
    local result=s.start();eq("n",s.commands());s.arrive(2);eq(true,result.value.ok)
    s=setup();s.room.exits={};s.gatesByEdge.h1={h2={command="uderz we wrota"}}
    result=s.start();eq("uderz we wrota",s.commands());s.line("Alez wrota sa przeciez otwarte!");s.advance(0.1)
    s.arrive(2);eq(true,result.value.ok)
end)

test("reload and synchronous send cancellation leave no active timers",function()
    for _,duringSend in ipairs({false,true}) do
        local s=setup()
        if duringSend then s.onSend=function() s.cleanup() end end
        local result=s.start()
        if not duringSend then s.cleanup() end
        s.advance(100);eq(false,result.value.ok);eq(1,result.calls);eq("n",s.commands());eq(nil,next(s.timers))
    end
end)

test("failed sender and malformed run plans do not leave delayed work",function()
    local s=setup();s.failSend=true;local result=s.start();eq(false,result.value.ok);eq(nil,next(s.timers))
    s=setup();local bad,done=s.result();s.api.run({steps={}},done);eq(false,bad.value.ok);eq(0,#s.sent)
end)

test("ordinary directions cannot enter Grey Mountain paths hidden in broad map areas",function()
    local s=setup();s.names[2]="Ścieżka w Górach Szarych";s.areas[2]=7;s.areaNames[7]="Parravon";s.path.dirs={"nw"}
    eq(nil,s.api.plan(1,2));eq(0,#s.sent)
    s=setup();s.hashes[2]="b424541fc01ede22";s.names[2]="Renamed room";eq(nil,s.api.plan(1,2));eq(0,#s.sent)
    s=setup();s.names[2]="Las Loren";eq(nil,s.api.plan(1,2));eq(0,#s.sent)
    s=setup();s.areas[2]=7;s.areaNames[7]="Góry Szare";eq(nil,s.api.plan(1,2))
end)
test("Montdidier road and settlements retain ordinary vertical and road exits",function()
    local s=setup();s.names[2]="Przelecz Montdidiera";s.areas[2]=7;s.areaNames[7]="Trakt Kreutzhofen - Bretonia"
    s.names[3]="Poczta w Jouinard";s.path={dirs={"e","up"},rooms={2,3},weights={1,1}}
    local plan=assert(s.api.plan(1,3));eq("u",plan.steps[2].cmd);eq(2,plan.cost)
end)
test("cached route is rejected before any send after wilderness metadata changes",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local plan=assert(s.api.plan(1,3));s.names[3]="Gdzies w Gorach Szarych"
    local result,done=s.result();s.api.run(plan,done);eq(false,result.value.ok);eq(0,#s.sent);eq(nil,next(s.timers))
end)
test("wilderness is rechecked before a delayed next step and gate crossing",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local result=s.start(3);s.arrive(2);s.names[3]="Sciezka w Gorach Szarych";s.advance(1)
    eq("n",s.commands());eq(false,result.value.ok);eq(1,result.calls)
    s=setup();s.room.exits={};s.gates.h1={command="uderz we wrota"};result=s.start()
    eq("uderz we wrota",s.commands());s.line("Alez wrota sa przeciez otwarte!");s.names[2]="Las Loren";s.advance(1)
    eq("uderz we wrota",s.commands());eq(false,result.value.ok);eq(1,result.calls)
end)
test("last edge proof requires exact owned map and hash ACK and stays only at its destination",function()
    local s=setup();local result=s.start();eq(nil,s.api.lastEdge());s.arrive(2)
    eq(true,result.value.ok);local proof=assert(s.api.lastEdge());eq("h1",proof.fromId);eq(1,proof.fromMap);eq("h2",proof.toId);eq(2,proof.toMap)
    proof.fromId="changed";eq("h1",s.api.lastEdge().fromId);s.cancel();eq("h1",s.api.lastEdge().fromId)
    s.arrive(3);eq(nil,s.api.lastEdge());s.arrive(2);eq(nil,s.api.lastEdge())
end)
test("cancelled pending step captures proof only at exact drained ACK before settled callbacks",function()
    local s=setup();local result=s.start();s.cancel();eq(nil,s.api.lastEdge())
    local observed
    -- A separate listener has the same synchronous ordering used by the
    -- emergency adapter on travel.settled.
    s.on("chimera.paczki.travel.settled",function() observed=s.api.lastEdge() end)
    s.arrive(2);eq(false,result.value.ok);local proof=assert(s.api.lastEdge())
    eq("h1",proof.fromId);eq(1,proof.fromMap);eq("h2",proof.toId);eq(2,proof.toMap)
    assert(observed);eq("h2",observed.toId);eq("h1",observed.fromId)
    s=setup();s.start();s.cancel();s.arrive(3);eq(nil,s.api.lastEdge())
end)
test("stale mapper mismatches cannot supply escape proof",function()
    local s
    s=setup();s.start();s.room={id="h2",exits={}};s.emit("chimera.room.info",s.room)
    eq(nil,s.api.lastEdge());s.map=2;s.emit("chimera.mapper.moved",2,s.room);assert(s.api.lastEdge())
    s.hashes[1]="remapped";eq(nil,s.api.lastEdge())
end)
test("disconnect actor change and reload invalidate proof without resurrection",function()
    for _,event in ipairs({"chimera.session.end","chimera.paczki.actor.changed","chimera.mapper.lost"}) do
        local s=setup();s.start();s.arrive(2);assert(s.api.lastEdge());s.emit(event)
        eq(nil,s.api.lastEdge());s.arrive(2);eq(nil,s.api.lastEdge())
    end
    local s=setup();s.start();s.arrive(2);assert(s.api.lastEdge());s.cleanup();eq(nil,s.api.lastEdge())
end)

test("newly attacked stable room is avoided in both directions by a fresh fallback plan",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local graph={[1]={north=2,east=4},[2]={south=1,east=3},[3]={west=2,south=4},[4]={west=1,north=3}}
    _G.getRoomExits=function(map) return graph[map] or {} end
    _G.getSpecialExitsSwap=function() return {} end
    _G.getRoomWeight=function() return 1 end
    _G.getExitWeights=function() return {} end
    _G.roomLocked=function() return false end
    _G.hasExitLock=function() return false end
    _G.hasSpecialExitLock=function() return false end
    local hazards={}
    s.roomBlock=function(map,id) return hazards[id]==true,"miejsce poprzedniego ataku" end
    local first=assert(s.api.plan(1,3));eq("n",first.steps[1].cmd)
    hazards.h2=true
    local plan=assert(s.api.plan(1,3));eq(true,plan.detour);eq("e",plan.steps[1].cmd);eq(4,plan.steps[1].map);eq(3,plan.steps[2].map)
    s.path={dirs={"w","s"},rooms={2,1},weights={1,1}}
    plan=assert(s.api.plan(3,1));eq("s",plan.steps[1].cmd);eq(4,plan.steps[1].map);eq(1,plan.steps[2].map)
    local result,done=s.result();s.api.run(first,done);eq(false,result.value.ok);eq(0,#s.sent)
    -- Existing location identities and map locks remain unchanged.
    eq("h2",s.hashes[2]);eq(2,graph[1].north);eq(false,roomLocked(2))
end)
test("dynamic attacked-room check fails closed and applies again immediately before a step",function()
    local s=setup();s.roomBlock=function() error("unavailable hazard database") end
    eq(nil,s.api.plan(1,2));eq(0,#s.sent)
    s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local result=s.start(3);s.arrive(2)
    s.roomBlock=function(map,id) return id=="h3","miejsce poprzedniego ataku" end
    s.advance(1);eq(false,result.value.ok);eq("n",s.commands())
end)

test("two verified emergency reverse ACKs expose the preceding confirmed trail edge",function()
    local s=setup();s.path={dirs={"n","e","s"},rooms={2,3,4},weights={1,1,1}}
    local result=s.start(4);s.arrive(2);s.advance(0.1);s.arrive(3);s.advance(0.1);s.arrive(4)
    eq(true,result.value.ok);eq("h3",s.api.lastEdge().fromId);eq("n|e|s",s.commands())
    s.emit("chimera.walk.started",{emergency=true,target="h3",map_room=3});s.arrive(3)
    local proof=assert(s.api.lastEdge());eq("h2",proof.fromId);eq("h3",proof.toId)
    s.emit("chimera.walk.started",{emergency=true,target="h2",map_room=2});s.arrive(2)
    proof=assert(s.api.lastEdge());eq("h1",proof.fromId);eq("h2",proof.toId)
    s.emit("chimera.walk.started",{emergency=true,target="h1",map_room=1});s.arrive(1)
    eq(nil,s.api.lastEdge());eq("n|e|s",s.commands(),"history never invents or sends a reverse command")
end)
test("unexpected reverse and another walker cannot resurrect the retreat trail",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    s.start(3);s.arrive(2);s.advance(0.1);s.arrive(3)
    s.emit("chimera.walk.started",{emergency=true,target="h2",map_room=2});s.arrive(4);eq(nil,s.api.lastEdge())
    s.arrive(2);eq(nil,s.api.lastEdge())
    s=setup();s.start();s.arrive(2);s.emit("chimera.walk.started",{target="h1",map_room=1})
    eq(nil,s.api.lastEdge());s.arrive(1);s.arrive(2);eq(nil,s.api.lastEdge())
end)
test("trail retains at most the latest thirty-two confirmed edges",function()
    local s=setup();local dirs,rooms,weights={},{},{}
    for map=1,35 do s.hashes[map]="h"..map end
    for map=2,35 do dirs[#dirs+1]="n";rooms[#rooms+1]=map;weights[#weights+1]=1 end
    s.path={dirs=dirs,rooms=rooms,weights=weights};s.start(35)
    for map=2,35 do s.arrive(map);s.advance(0.1) end
    for map=34,3,-1 do
        local proof=assert(s.api.lastEdge());eq(map,proof.fromMap)
        s.emit("chimera.walk.started",{emergency=true,target="h"..map,map_room=map});s.arrive(map)
    end
    eq(nil,s.api.lastEdge(),"older edges are discarded rather than recreated")
end)
test("combat transit exits a delayed step immediately without duplicating a pending command",function()
    local s=setup();s.delay=3;s.path={dirs={"n","e","s"},rooms={2,3,4},weights={1,1,1}}
    local result=s.start(4);s.arrive(2);eq("n",s.commands())
    eq(true,s.api.continueAfterAttack());eq("n|e",s.commands());eq(true,s.api.continueAfterAttack());eq("n|e",s.commands())
    s.arrive(3);s.advance(0.049);eq("n|e",s.commands());s.advance(0.001);eq("n|e|s",s.commands())
    s.arrive(4);eq(true,result.value.ok);eq(false,s.api.continueAfterAttack());eq(false,s.api.endCombatTransit())
end)
test("combat transit awaits in-flight ACK and fresh combat clear restores normal tempo",function()
    local s=setup();s.delay=3;s.path={dirs={"n","e","s"},rooms={2,3,4},weights={1,1,1}}
    local result=s.start(4);eq(true,s.api.continueAfterAttack());s.advance(0.2);eq("n",s.commands())
    s.arrive(2);eq(true,s.api.endCombatTransit());s.advance(0.1);eq("n",s.commands())
    s.advance(2.9);eq("n|e",s.commands());s.arrive(3);s.advance(2.99);eq("n|e",s.commands())
    s.advance(0.01);eq("n|e|s",s.commands());s.arrive(4);eq(true,result.value.ok)
end)

test("timing geometry counts exact steps and gate edges rather than map weights",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={9000,7000}}
    s.gatesByEdge["h1|h2"]={command="uderz we wrota"}
    s.gates.h2={command="otworz brame",direction="s"}
    local plan=assert(s.api.plan(1,3));local metrics=assert(s.api.metrics(plan))
    eq(16000,plan.cost);eq(2,metrics.steps);eq(1,metrics.delayUnits);eq(1,metrics.delays)
    eq(1,metrics.gates);eq(0,metrics.ferries);eq(0,#metrics.ferryKeys)
    eq(0,#s.sent);eq(0,#s.events)
end)
test("timing signatures use stable room hashes and commands rather than profile map numbers",function()
    local s=setup();local plan=assert(s.api.plan(1,2));local metrics=assert(s.api.metrics(plan))
    plan.from=101;plan.target=102;plan.steps[1].map=102
    eq(metrics.signature,assert(s.api.metrics(plan)).signature)
    plan.steps[1].cmd="e";assert(metrics.signature~=assert(s.api.metrics(plan)).signature)
    local zero=assert(s.api.metrics(assert(s.api.plan(1,1))))
    eq(0,zero.steps);eq(0,zero.delayUnits);eq(0,zero.gates)
    eq(nil,s.api.metrics({steps={{}},fromId="h1",targetId="h2"}))
end)
test("executed timing delay excludes cancelled timers and reports only actually elapsed valid steps",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    s.start(3);s.arrive(2);s.cancel();s.advance(1)
    eq(0,s.count("chimera.paczki.timing.delay"))
    s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    s.start(3);s.arrive(2);s.advance(0.1)
    eq(1,s.count("chimera.paczki.timing.delay"));eq("n|e",s.commands())
    for _,event in ipairs(s.events) do
        if event.event=="chimera.paczki.timing.delay" then eq(0.1,event.value.seconds) end
    end
    s.arrive(3);s.advance(10);eq(1,s.count("chimera.paczki.timing.delay"))
end)
test("bare statek and prom mapper labels cannot become ordinary movement commands",function()
    _G.getRoomExits=function() return {} end
    _G.getSpecialExitsSwap=function(map) return map==1 and {statek=2,prom=2} or {} end
    _G.getRoomWeight=function() return 1 end
    for _,command in ipairs({"statek","STATEK"," prom "}) do
        local s=setup();s.path.dirs={command}
        eq(nil,s.api.plan(1,2),command);eq(0,#s.sent)
        local result,done=s.result()
        s.api.run({from=1,target=2,fromId="h1",targetId="h2",steps={{cmd=command,map=2,id="h2"}}},done)
        eq(false,result.value.ok);eq(0,#s.sent);eq(nil,next(s.timers))
    end
end)
test("Karak west entrance and Black Mountain wilderness hashes reject ordinary directional shortcuts",function()
    for _,id in ipairs({"2bdb8424ecc77353","4ef9a4a6193caac6","16f5f25677957270","7375e2a9c4ab6363"}) do
        local s=setup();s.hashes[2]=id;s.names[2]="Renamed room";s.path.dirs={"w"}
        s.areas[2]=9;s.areaNames[9]="Karak Varn"
        eq(nil,s.api.plan(1,2),id);eq(0,#s.sent)
    end
    local s=setup();s.names[2]="Gdzieś w Górach Czarnych"
    eq(nil,s.api.plan(1,2));eq(0,#s.sent)
end)
test("Black Mountain approach road port and city preserve ordinary movement including stairs",function()
    local s=setup();s.hashes[2]="8640576d51e7732f";s.hashes[3]="2e1aa32a45a83107"
    s.hashes[4]="c55c2924e506dd7f"
    s.names[2]="Trakt w Gorach Czarnych";s.names[3]="Przystan w Gorach Czarnych";s.names[4]="Poczta"
    s.areas[2]=9;s.areas[3]=9;s.areas[4]=9;s.areaNames[9]="Gory Czarne"
    s.path={dirs={"s","up","w"},rooms={2,3,4},weights={1,1,1}}
    local plan=assert(s.api.plan(1,4));eq(3,#plan.steps);eq("u",plan.steps[2].cmd);eq(3,plan.cost)
    eq(0,#s.sent)
end)
test("a cached or delayed Black Mountain step is rejected before entry",function()
    local s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local plan=assert(s.api.plan(1,3));s.names[3]="Gdzies w Gorach Czarnych"
    local result,done=s.result();s.api.run(plan,done);eq(false,result.value.ok);eq(0,#s.sent)
    s=setup();s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    result=s.start(3);s.arrive(2);s.names[3]="Gdzies na granicy Gor Czarnych i Gor Kranca Swiata"
    s.advance(1);eq(false,result.value.ok);eq("n",s.commands());eq(1,result.calls)
end)
test("fallback Dijkstra cannot reintroduce the Karak mountain entrance",function()
    local s=setup();s.hashes[2]="2bdb8424ecc77353";s.hashes[3]="c55c2924e506dd7f";s.hashes[4]="8640576d51e7732f"
    s.path={dirs={"n","e"},rooms={2,3},weights={1,1}}
    local graph={[1]={north=2,east=4},[2]={east=3},[4]={north=3}}
    _G.getRoomExits=function(map) return graph[map] or {} end
    _G.getSpecialExitsSwap=function() return {} end
    _G.getRoomWeight=function() return 1 end
    local plan=assert(s.api.plan(1,3));eq(true,plan.detour);eq(4,plan.steps[1].map);eq("e",plan.steps[1].cmd)
    eq(3,plan.steps[2].map);eq(2,graph[1].north);eq(0,#s.sent)
end)
print("PASS "..passed.." owned road tests")
