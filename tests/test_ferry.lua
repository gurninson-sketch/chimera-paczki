-- Standalone Lua 5.1-compatible protocol tests. Run from chimera-native.
local create=dofile("chimera_wtyczki/chimera_paczki/ferry.lua")
local SOUTH,NORTH="894039a1680ca034","20016d960316ba51"
local tests,checks=0,0
local function check(ok,why) checks=checks+1;assert(ok,why or "check failed") end
local function eq(expected,actual,why) check(expected==actual,(why or "value")..": "..tostring(expected).." ~= "..tostring(actual)) end
local function test(name,body) body();tests=tests+1;print("PASS "..name) end
local function setup(reverse)
    local s={time=0,next=0,events={},triggers={},timers={},archive={},sends={},emitted={},cleanups={},
        room={id=reverse and NORTH or SOUTH,name="Brzeg rzeki"},map=reverse and 2 or 1,maps={[SOUTH]=1,[NORTH]=2}}
    local ctx={}
    local function handle() s.next=s.next+1;return s.next end
    function ctx:on(event,fn) local h=handle();s.events[event]=s.events[event] or {};s.events[event][h]=fn;return h end
    function ctx:trigger(_,fn) local h=handle();s.triggers[h]=fn;return h end
    function ctx:timer(delay,fn) local h=handle();s.timers[h]={at=s.time+delay,fn=fn};s.archive[h]=fn;return h end
    function ctx:cancel(h)
        s.timers[h]=nil;s.triggers[h]=nil
        for _,handlers in pairs(s.events) do handlers[h]=nil end
    end
    function ctx:emit(event,data)
        s.emitted[#s.emitted+1]={event=event,data=data}
        s.emit(event,data)
    end
    function ctx:cleanup(fn) s.cleanups[#s.cleanups+1]=fn end
    function ctx:send() error("opts.send must be used") end
    function s.emit(event,...)
        local snapshot={}
        for h,fn in pairs(s.events[event] or {}) do snapshot[#snapshot+1]={h=h,fn=fn} end
        table.sort(snapshot,function(a,b) return a.h<b.h end)
        -- Match the native bus: removed callbacks can still be in this copy.
        for _,entry in ipairs(snapshot) do entry.fn(...) end
    end
    function s.line(text)
        _G.line=text
        local snapshot={}
        for h,fn in pairs(s.triggers) do snapshot[#snapshot+1]={h=h,fn=fn} end
        table.sort(snapshot,function(a,b) return a.h<b.h end)
        for _,entry in ipairs(snapshot) do entry.fn() end
    end
    function s.advance(seconds)
        local ending=s.time+seconds
        while true do
            local selected,at
            for h,timer in pairs(s.timers) do if timer.at<=ending and (not at or timer.at<at or (timer.at==at and h<selected)) then selected,at=h,timer.at end end
            if not selected then break end
            local timer=s.timers[selected];s.timers[selected]=nil;s.time=at;timer.fn()
        end
        s.time=ending
    end
    function s.position(id,map,name)
        s.room={id=id,name=name or "Brzeg rzeki"};s.map=map
        s.emit("chimera.room.info",s.room)
        s.emit("chimera.room.changed",s.room)
        s.emit("chimera.mapper.moved",map,s.room)
    end
    function s.deck(id) s.position(id or "deck-grismerie",nil,"Na pokladzie promu") end
    function s.result()
        local r={calls=0}
        return r,function(value) r.calls=r.calls+1;r.value=value end
    end
    function s.cleanup() for _,fn in ipairs(s.cleanups) do fn() end end
    function s.oldCallbacks() for _,fn in pairs(s.archive) do fn() end end
    function s.count(event)
        local count=0;for _,entry in ipairs(s.emitted) do if entry.event==event then count=count+1 end end;return count
    end
    _G.getRoomIDbyHash=function(hash) return s.maps[hash] or -1 end
    s.api=create(ctx,{gmcp={room=function() return s.room end},mapper={current_room=function() return s.map end},
        send=function(command) s.sends[#s.sends+1]=command;if s.sendHook then return s.sendHook(command) end end})
    s.link={fromHash=reverse and NORTH or SOUTH,toHash=reverse and SOUTH or NORTH,fromMap=reverse and 2 or 1,toMap=reverse and 1 or 2,cost=40}
    return s
end
local function aboard(s)
    s.line("Wskakujesz na poklad promu.");s.deck();s.line("Na pokladzie promu.")
end
local function dock(s)
    s.line("Prom powoli odbija od brzegu.");s.line("Prom powoli przybija do brzegu.")
end

test("catalogue contains only both verified Grismerie directions and independent records",function()
    local s=setup();local links=s.api.catalogue();eq(2,#links)
    eq(SOUTH,links[1].fromHash);eq(NORTH,links[1].toHash);eq(1,links[1].fromMap);eq(2,links[1].toMap);eq(40,links[1].cost)
    eq("wsiadz na statek",links[1].boardCommand);eq("wejdz na prom",links[2].boardCommand)
    links[1].fromHash="corrupted";eq(SOUTH,s.api.catalogue()[1].fromHash)
    s.maps[NORTH]=nil;eq(0,#s.api.catalogue())
end)
for _,reverse in ipairs({false,true}) do
    test((reverse and "north to south" or "south to north").." requires actual target GMCP hash and mapped room",function()
        local s=setup(reverse);local result,done=s.result();s.api.run(s.link,done)
        eq(reverse and "wejdz na prom" or "wsiadz na statek",s.sends[1]);eq(1,s.count("chimera.walk.started"))
        aboard(s);dock(s);eq("zejdz na brzeg",s.sends[2]);eq(0,result.calls)
        s.line("Prom powoli przybija do brzegu.");s.line("Prom powoli przybija do brzegu.");eq(2,#s.sends)
        s.line("Schodzisz z pokladu promu na brzeg.");eq(0,result.calls)
        s.position(s.link.toHash,nil);eq(0,result.calls,"hash alone is insufficient")
        s.position(s.link.toHash,s.link.toMap);eq(1,result.calls);eq(true,result.value.ok);eq(s.link.toMap,result.value.map_room)
        eq(1,s.count("chimera.walk.arrived"));eq(0,s.count("chimera.walk.stopped"));eq(nil,next(s.timers))
        s.oldCallbacks();s.line("Prom powoli przybija do brzegu.");eq(2,#s.sends);eq(1,result.calls)
    end)
end
test("GMCP boarding before text and destination packet before arrival lines are reconciled",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    s.deck();eq("sailing",s.api.status().phase)
    s.line("Wskakujesz na poklad promu.");s.position(NORTH,2);eq(0,r.calls)
    s.line("Prom powoli odbija od brzegu.");eq(1,r.calls);eq(true,r.value.ok);eq(1,#s.sends,"already ashore must not send another leave")
    local t=setup();local a,accept=t.result();t.api.run(t.link,accept)
    t.position(NORTH,2);eq(0,a.calls)
    t.line("Wskakujesz na poklad promu.");eq(0,a.calls)
    t.line("Prom powoli odbija od brzegu.");eq(true,a.value.ok);eq(1,#t.sends)
end)
test("arrival duplicates and departure-bank cache cannot trigger premature disembark",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    s.line("Wskakujesz na poklad promu.")
    s.line("Prom powoli przybija do brzegu.");eq(1,#s.sends)
    s.line("Prom powoli odbija od brzegu.");s.line("Prom powoli przybija do brzegu.")
    eq(1,#s.sends,"cached departure bank must not authorize leave")
    s.deck();eq(2,#s.sends);eq("zejdz na brzeg",s.sends[2])
    s.line("Prom powoli przybija do brzegu.");s.line("Na pokladzie promu.");eq(2,#s.sends)
    s.position(NORTH,2);eq(true,r.value.ok)
end)
test("absent vessel waits for docking and debounces duplicate dock lines",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    s.line("Nie ma tutaj promu.");eq("waiting",s.api.status().phase)
    s.advance(50);eq(1,#s.sends)
    for _=1,5 do s.line("Rzeczny prom przybija do brzegu.") end
    s.advance(0.49);eq(1,#s.sends);s.advance(0.01);eq(2,#s.sends)
    aboard(s);dock(s);s.position(NORTH,2);eq(true,r.value.ok)
    for _,command in ipairs(s.sends) do check(command~="kup bilet") end
end)
test("three unsuccessful boarding attempts end once without a fourth command",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    for attempt=1,3 do
        eq(attempt,#s.sends);s.line("Nie widzisz zadnego promu.")
        if attempt<3 then s.line("Rzeczny prom przybija do brzegu.");s.advance(0.5) end
    end
    eq(1,r.calls);eq(false,r.value.ok);eq(3,#s.sends);eq(nil,next(s.timers))
    s.advance(1000);s.line("Rzeczny prom przybija do brzegu.");s.oldCallbacks();eq(3,#s.sends);eq(1,r.calls)
end)
test("bank, sailing and disembark have bounded independent timeouts",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    s.advance(15);eq("waiting",s.api.status().phase);s.advance(285);eq(false,r.value.ok);eq(1,#s.sends)
    local t=setup();local a,accept=t.result();t.api.run(t.link,accept);aboard(t)
    t.line("Prom powoli odbija od brzegu.");t.advance(300);eq(false,a.value.ok);eq(1,#t.sends)
    local u=setup();local b,finish=u.result();u.api.run(u.link,finish);aboard(u);dock(u)
    u.line("Schodzisz z pokladu promu na brzeg.");u.advance(15);eq(false,b.value.ok);eq(2,#u.sends)
    eq(nil,next(s.timers));eq(nil,next(t.timers));eq(nil,next(u.timers))
    check(s.count("chimera.paczki.travel.activity")>=2);check(t.count("chimera.paczki.travel.activity")>=2)
end)
test("wrong bank, wrong map and server refusal never become successful crossings",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);aboard(s);dock(s)
    s.position(SOUTH,1);eq(false,r.value.ok);eq(0,s.count("chimera.walk.arrived"))
    local t=setup();local a,accept=t.result();t.api.run(t.link,accept);aboard(t);dock(t)
    t.position(NORTH,1);eq(0,a.calls);t.advance(15);eq(false,a.value.ok)
    local u=setup();local b,finish=u.result();u.api.run(u.link,finish);aboard(u);dock(u)
    u.line("Zejdz gdzie?");eq(false,b.value.ok);eq(2,#u.sends)
end)
for _,stage in ipairs({"boarding","waiting","sailing","disembarking"}) do
    test("cancel during "..stage.." invalidates every queued event and timer",function()
        local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done)
        if stage=="waiting" then s.line("Nie ma tutaj promu.");s.line("Rzeczny prom przybija do brzegu.") end
        if stage=="sailing" or stage=="disembarking" then aboard(s) end
        if stage=="disembarking" then dock(s) end
        local sent=#s.sends;cancel();cancel();eq(1,r.calls);eq(false,r.value.ok)
        if stage=="boarding" or stage=="disembarking" then eq(1,s.count("chimera.paczki.travel.pending"))
        else eq(nil,next(s.timers)) end
        s.oldCallbacks();s.advance(1000);eq(nil,next(s.timers))
        s.line("Wskakujesz na poklad promu.");s.line("Prom powoli odbija od brzegu.");s.line("Prom powoli przybija do brzegu.")
        s.position(NORTH,2);eq(sent,#s.sends);eq(1,r.calls)
    end)
end
test("reload and disconnect cancel without leaving a pending disembark command",function()
    for _,kind in ipairs({"reload","disconnect","key"}) do
        local s=setup();local r,done=s.result();s.api.run(s.link,done);aboard(s)
        if kind=="reload" then s.cleanup() elseif kind=="disconnect" then s.emit("chimera.session.end") else s.emit("chimera.numpad.pressed") end
        eq(false,r.value.ok);eq(1,r.calls);s.oldCallbacks();s.line("Prom powoli odbija od brzegu.");s.line("Prom powoli przybija do brzegu.")
        eq(1,#s.sends);eq(nil,next(s.timers))
    end
end)
test("cancel aboard can resume only the same boat and preserves crossing direction",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s)
    s.line("Prom powoli odbija od brzegu.");cancel();eq(false,first.value.ok)
    local state=s.api.state();eq("paused",state.phase);eq(SOUTH,state.fromHash);eq(NORTH,state.toHash)
    eq(1,state.fromMap);eq(2,state.toMap);eq("deck-grismerie",state.deckId);eq(true,state.departed);eq(false,state.arrived)
    state.toMap=999;state.link.toHash="corrupted";eq(2,s.api.state().toMap);eq(NORTH,s.api.state().link.toHash)
    eq(true,s.api.resumable(2));eq(false,s.api.resumable(1))
    local second,accept=s.result();s.api.resume(2,accept);eq(1,#s.sends,"resume must not board again")
    s.line("Prom powoli przybija do brzegu.");eq("zejdz na brzeg",s.sends[2]);s.position(NORTH,2)
    eq(true,second.value.ok);eq(nil,s.api.state());eq(1,second.calls)
end)
test("resume after a sent leave command waits for acknowledgement without repeating it",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s);dock(s);cancel()
    eq(true,s.api.state().leaveSent);local result,accept=s.result();s.api.resume(2,accept)
    s.line("Prom powoli przybija do brzegu.");eq(2,#s.sends)
    s.position(NORTH,2);eq(true,result.value.ok);eq(2,#s.sends)
end)
test("remembered voyage is hidden when GMCP no longer identifies the same boat",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s);cancel()
    s.deck("different-boat");eq(nil,s.api.state());eq(false,s.api.resumable(2))
    local r,accept=s.result();s.api.resume(2,accept);eq(false,r.value.ok);eq(1,#s.sends)
end)
test("paused voyage observes docking without sending until an explicit resume",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s)
    s.line("Prom powoli odbija od brzegu.");cancel()
    s.line("Prom powoli przybija do brzegu.")
    eq(1,#s.sends);eq(true,s.api.state().arrived)
    local result,accept=s.result();s.api.resume(2,accept)
    eq(2,#s.sends);eq("zejdz na brzeg",s.sends[2]);s.position(NORTH,2);eq(true,result.value.ok)
end)
test("paused departure invalidates an old arrival and tracks the actual ferry cycle",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s)
    s.line("Prom powoli odbija od brzegu.");cancel()
    s.line("Prom powoli przybija do brzegu.");s.line("Prom powoli odbija od brzegu.")
    local state=s.api.state();eq(false,state.arrived);eq(SOUTH,state.currentToHash);eq(NORTH,state.toHash)
    local result,accept=s.result();s.api.resume(2,accept);eq(1,#s.sends,"old arrival must not authorize leaving")
    s.line("Prom powoli przybija do brzegu.");eq(1,#s.sends,"wrong-bank arrival must not authorize leaving")
    s.line("Prom powoli odbija od brzegu.");s.line("Prom powoli przybija do brzegu.")
    eq("zejdz na brzeg",s.sends[2]);s.position(NORTH,2);eq(true,result.value.ok)
end)
test("cancelled boarding drains a delayed boat snapshot and preserves passive departure",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);cancel()
    eq(1,s.count("chimera.paczki.travel.pending"));eq(0,s.count("chimera.walk.stopped"))
    s.line("Wskakujesz na poklad promu.");s.line("Prom powoli odbija od brzegu.");s.advance(2);s.deck()
    eq(1,s.count("chimera.paczki.travel.settled"));eq(1,s.count("chimera.walk.stopped"));eq(true,s.api.state().departed)
    eq(1,#s.sends);s.line("Prom powoli przybija do brzegu.");eq(true,s.api.state().arrived);eq(1,#s.sends)
end)
test("cancelled landing accepts only the exact delayed bank and settles once",function()
    for _,correct in ipairs({true,false}) do
        local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);aboard(s);dock(s);cancel()
        eq(1,s.count("chimera.paczki.travel.pending"));eq(0,s.count("chimera.walk.stopped"));s.advance(2)
        s.position(correct and NORTH or SOUTH,correct and 2 or 1)
        eq(1,s.count("chimera.paczki.travel.settled"));eq(1,s.count("chimera.walk.stopped"))
        eq(correct and 0 or 1,s.count("chimera.paczki.travel.unexpected"));eq(nil,s.api.state());eq(2,#s.sends)
        s.advance(20);eq(1,s.count("chimera.paczki.travel.settled"));eq(2,#s.sends)
    end
end)
test("unconfirmed cancelled ferry command times out and reports an unsafe outcome",function()
    local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done);cancel();s.advance(15)
    eq(1,s.count("chimera.paczki.travel.pending"));eq(1,s.count("chimera.paczki.travel.settled"))
    eq(1,s.count("chimera.paczki.travel.unexpected"));eq(nil,s.api.state());eq(nil,next(s.timers));eq(1,#s.sends)
end)
test("another walker replaces a passive drain without receiving its old stopped event",function()
    for _,landing in ipairs({false,true}) do
        local s=setup();local first,done=s.result();local cancel=s.api.run(s.link,done)
        if landing then aboard(s);dock(s) end
        cancel();eq(1,s.count("chimera.paczki.travel.pending"));eq(0,s.count("chimera.walk.stopped"))
        s.emit("chimera.walk.started",{target="another-walker"})
        eq(1,s.count("chimera.paczki.travel.settled"));eq(0,s.count("chimera.walk.stopped"));eq(nil,next(s.timers))
        s.position(NORTH,2);s.oldCallbacks();s.advance(20)
        eq(0,s.count("chimera.walk.stopped"));eq(0,s.count("chimera.paczki.travel.unexpected"))
        eq(landing and 2 or 1,#s.sends)
    end
end)
test("unsupported link and incorrect starting bank send nothing",function()
    local s=setup();local r,done=s.result();s.api.run({fromHash=SOUTH,toHash="unknown",fromMap=1,toMap=3},done)
    eq(false,r.value.ok);eq(0,#s.sends);eq(0,s.count("chimera.walk.started"))
    s.position("wrong-bank",1);local a,accept=s.result();s.api.run(s.link,accept)
    eq(false,a.value.ok);eq(0,#s.sends);eq(nil,next(s.timers))
end)
test("send failure ends the operation and cleans all timers",function()
    local s=setup();s.sendHook=function() error("wire offline") end
    local r,done=s.result();s.api.run(s.link,done);eq(false,r.value.ok);eq(nil,next(s.timers));eq(1,r.calls)
end)
print(string.format("SUCCESS: %d ferry scenarios, %d assertions",tests,checks))
