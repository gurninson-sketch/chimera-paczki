-- Standalone owned Kahn-Gad transport tests. Run from chimera-native.
local create=dofile("chimera_wtyczki/chimera_paczki/karak_transport.lua")
local BLUE,BLACK,DECK="891456eab7637380","2e1aa32a45a83107","be0c7fc1d5441e3a"
local tests,checks,failures=0,0,0
local function check(value,why) checks=checks+1;assert(value,why or "check failed") end
local function eq(expected,value,why) check(expected==value,(why or "value")..": "..tostring(expected).." ~= "..tostring(value)) end
local function test(name,fn)
    tests=tests+1;local ok,why=pcall(fn)
    if ok then print("PASS "..name) else failures=failures+1;print("FAIL "..name..": "..tostring(why)) end
end
local function setup(reverse,overrides)
    local s={time=0,next=0,events={},triggers={},timers={},archive={},sends={},emitted={},cleanups={},maps={[BLUE]=1,[BLACK]=2,[DECK]=3},
        room={id=reverse and BLACK or BLUE,name="Przystan"},map=reverse and 2 or 1,prepared=0,stored=0,cancelled=0}
    local ctx={}
    local function id() s.next=s.next+1;return s.next end
    function ctx:on(name,fn) local h=id();s.events[name]=s.events[name] or {};s.events[name][h]=fn;return h end
    function ctx:trigger(_,fn) local h=id();s.triggers[h]=fn;return h end
    function ctx:timer(delay,fn) local h=id();s.timers[h]={at=s.time+delay,fn=fn};s.archive[h]=fn;return h end
    function ctx:cancel(h) s.timers[h]=nil end
    function ctx:cleanup(fn) s.cleanups[#s.cleanups+1]=fn end
    function ctx:emit(name,data) s.emitted[#s.emitted+1]={name=name,data=data};s.emit(name,data) end
    function s.emit(name,...)
        local list={};for h,fn in pairs(s.events[name] or {}) do list[#list+1]={h=h,fn=fn} end
        table.sort(list,function(a,b) return a.h<b.h end);for _,entry in ipairs(list) do entry.fn(...) end
    end
    function s.line(text)
        _G.line=text;local list={};for h,fn in pairs(s.triggers) do list[#list+1]={h=h,fn=fn} end
        table.sort(list,function(a,b) return a.h<b.h end);for _,entry in ipairs(list) do entry.fn() end
    end
    function s.advance(seconds)
        local ending=s.time+seconds;local budget=10000
        while true do
            local selected,at
            for h,t in pairs(s.timers) do if t.at<=ending and (not at or t.at<at or t.at==at and h<selected) then selected,at=h,t.at end end
            if not selected then break end
            budget=budget-1;assert(budget>0,"timer runaway")
            local t=s.timers[selected];s.timers[selected]=nil;s.time=at;t.fn()
        end
        s.time=ending
    end
    function s.position(hash,map,title)
        s.room={id=hash,name=title or (hash==DECK and "Poklad statku 'Kahn-Gad'" or "Przystan")};s.map=map
        s.emit("chimera.room.info",s.room);s.emit("chimera.mapper.moved",map,s.room);s.emit("chimera.room.changed",s.room)
    end
    function s.deck() s.position(DECK,3,"Poklad statku 'Kahn-Gad'") end
    function s.result() local r={calls=0};return r,function(value) r.calls=r.calls+1;r.value=value end end
    function s.cleanup() for _,fn in ipairs(s.cleanups) do fn() end end
    function s.oldCallbacks() local list={};for _,fn in pairs(s.archive) do list[#list+1]=fn end;for _,fn in ipairs(list) do fn() end end
    function s.count(name) local n=0;for _,e in ipairs(s.emitted) do if e.name==name then n=n+1 end end;return n end
    function s.commands(command) local n=0;for _,cmd in ipairs(s.sends) do if cmd==command then n=n+1 end end;return n end
    _G.getRoomIDbyHash=function(hash) return s.maps[hash] or -1 end
    local opts={gmcp={room=function() return s.room end,connected=function() return true end},
        mapper={current_room=function() return s.map end,chimera_id=function(map) for hash,number in pairs(s.maps) do if number==map then return hash end end end},
        send=function(command) s.sends[#s.sends+1]=command;if s.sendHook then return s.sendHook(command) end end,
        prepareFare=function(done) s.prepared=s.prepared+1;if s.holdPrepare then s.prepareDone=done else done({ok=true}) end;return function() s.cancelled=s.cancelled+1 end end,
        finishFare=function(done) s.stored=s.stored+1;if s.holdStore then s.storeDone=done else done({ok=true}) end;return function() s.cancelled=s.cancelled+1 end end}
    for key,value in pairs(overrides or {}) do opts[key]=value end
    s.api=create(ctx,opts);s.link={fromHash=reverse and BLACK or BLUE,toHash=reverse and BLUE or BLACK,fromMap=reverse and 2 or 1,toMap=reverse and 1 or 2}
    return s
end
local READY="Statek dobija do brzegu i opuszcza trap."
local DEPART="Statek odbija od brzegu i podnosi trap."
local ENTER="Wchodzisz po trapie na statek."
local LEAVE="Schodzisz po trapie ze statku na brzeg."
local function ready(s) s.line(READY);s.advance(.05) end
local function board(s,gmcpFirst) if gmcpFirst then s.deck();s.line(ENTER) else s.line(ENTER);s.deck() end end
local function dock(s) s.line(DEPART);s.line(READY) end
local function arrive(s,gmcpFirst)
    if gmcpFirst then s.position(s.link.toHash,s.link.toMap);s.line(LEAVE) else s.line(LEAVE);s.position(s.link.toHash,s.link.toMap) end
end

test("catalogue exposes only two verified directions and defensive links",function()
    local s=setup();local links=s.api.catalogue();eq(2,#links);eq(BLUE,links[1].fromHash);eq(BLACK,links[1].toHash)
    eq(DECK,links[1].deckHash);eq(3,links[1].deckMap);eq("karak_ship",links[1].transport)
    links[1].fromHash="wrong";eq(BLUE,s.api.catalogue()[1].fromHash);s.maps[DECK]=nil;eq(0,#s.api.catalogue())
end)
for _,reverse in ipairs({false,true}) do
    test((reverse and "black-to-blue" or "blue-to-black").." requires own entry landing and exact mapped shore",function()
        local s=setup(reverse);local r,done=s.result();s.api.run(s.link,done)
        eq(0,#s.sends);ready(s);eq("kup bilet",s.sends[1]);eq("wsiadz na statek",s.sends[2]);eq(1,s.prepared)
        board(s);eq(1,s.stored);dock(s);eq("zejdz ze statku",s.sends[3]);eq(0,r.calls)
        arrive(s);eq(1,r.calls);eq(true,r.value.ok);eq(s.link.toHash,r.value.toHash);eq(1,s.count("chimera.walk.arrived"))
        s.oldCallbacks();s.line(READY);eq(3,#s.sends);eq(1,r.calls);eq(nil,next(s.timers))
    end)
end
test("mapped-bank waiting is indefinite with no spending and periodic activity",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);s.advance(1801)
    eq(0,r.calls);eq(0,#s.sends);check(s.count("chimera.paczki.travel.activity")>=10)
    ready(s);board(s);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("fare must confirm before the sole buy and boarding command",function()
    local s=setup();s.holdPrepare=true;local r,done=s.result();s.api.run(s.link,done);s.line(READY)
    eq(1,s.prepared);eq(0,#s.sends);s.advance(10);eq(0,#s.sends)
    s.prepareDone({ok=true});eq("kup bilet",s.sends[1]);eq(1,#s.sends);s.advance(.05);eq("wsiadz na statek",s.sends[2])
    board(s);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("failed fare aborts without spending or boarding",function()
    local s=setup(nil,{prepareFare=function(done) done({ok=false,reason="brak potwierdzenia monet"});return function() end end})
    local r,done=s.result();s.api.run(s.link,done);s.line(READY);eq(false,r.value.ok);eq(0,#s.sends);eq(1,r.calls)
end)
test("foreign ticket seller line never confirms own boarding",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s)
    s.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.")
    s.line("Inny wedrowiec wchodzi po trapie na statek.");eq(0,s.stored);eq(0,r.calls)
    s.advance(21);eq(false,r.value.ok);eq(1,s.commands("kup bilet"));eq(1,s.commands("wsiadz na statek"))
end)
test("duplicate arrival lines never buy or board twice",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done)
    for _=1,8 do s.line(READY) end;s.advance(.2)
    eq(1,s.commands("kup bilet"));eq(1,s.commands("wsiadz na statek"));eq(1,s.prepared)
    board(s);dock(s);for _=1,5 do s.line(READY) end;eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,r.value.ok)
end)
test("deck GMCP before own entry text waits without assuming boarding",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);s.deck()
    eq(0,r.calls);eq(0,s.stored);s.line(ENTER);eq(1,s.stored);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("own entry text before mapped deck cannot alone confirm boarding",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);s.line(ENTER)
    eq(0,s.stored);eq(0,r.calls);s.deck();eq(1,s.stored);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("landing requires both own text and mapped target in either order",function()
    for _,gmcpFirst in ipairs({false,true}) do
        local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s)
        if gmcpFirst then s.position(BLACK,2) else s.line(LEAVE) end
        eq(0,r.calls);if gmcpFirst then s.line(LEAVE) else s.position(BLACK,2) end;eq(true,r.value.ok)
    end
end)
test("wrong map at target hash never completes crossing",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s);s.line(LEAVE)
    s.position(BLACK,1);eq(0,r.calls);s.advance(21);eq(false,r.value.ok)
end)
test("arrival without departure cannot authorize premature leave",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);board(s)
    s.line(READY);s.line(READY);eq(0,s.commands("zejdz ze statku"));eq(0,r.calls)
    dock(s);eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,r.value.ok)
end)
test("coin storage must complete before disembarking",function()
    local s=setup();s.holdStore=true;local r,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s)
    eq(0,s.commands("zejdz ze statku"));s.storeDone({ok=true});eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,r.value.ok)
end)
test("missed target docking during storage waits rather than leaving wrong side",function()
    local s=setup();s.holdStore=true;local r,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s)
    s.line(DEPART);s.storeDone({ok=true});s.line(READY);eq(0,s.commands("zejdz ze statku"))
    s.line(DEPART);s.line(READY);eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,r.value.ok)
end)
test("departure during fare preparation waits for another arrival without spending",function()
    local s=setup();s.holdPrepare=true;local r,done=s.result();s.api.run(s.link,done);s.line(READY);s.line(DEPART)
    s.prepareDone({ok=true});eq(0,#s.sends);s.advance(100);eq(0,#s.sends);ready(s)
    eq(1,s.commands("kup bilet"));eq(1,s.prepared);board(s);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("silent boarding never repeats possibly paid purchase",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);s.advance(1000)
    eq(1,r.calls);eq(false,r.value.ok);s.line(READY);s.oldCallbacks();eq(1,s.commands("kup bilet"));eq(1,s.commands("wsiadz na statek"))
end)
test("wrong shore on known voyage is not success",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s);s.line(LEAVE);s.position(BLUE,1)
    eq(false,r.value.ok);eq(0,s.count("chimera.walk.arrived"))
end)
test("unknown link or stale map cannot charge",function()
    local s=setup();local r,done=s.result();s.api.run({fromHash=BLUE,toHash="unknown"},done);eq(false,r.value.ok);eq(0,#s.sends)
    s.maps[BLUE]=nil;local a,accept=s.result();s.api.run(s.link,accept);eq(false,a.value.ok);eq(0,#s.sends)
end)
for _,kind in ipairs({"stop","disconnect","key","actor","lost","reload"}) do
    test(kind.." cancels queued commands and stale callbacks",function()
        local s=setup();s.holdPrepare=true;local r,done=s.result();local cancel=s.api.run(s.link,done);s.line(READY)
        if kind=="stop" then cancel()
        elseif kind=="disconnect" then s.emit("chimera.session.end")
        elseif kind=="key" then s.emit("chimera.numpad.pressed","n")
        elseif kind=="actor" then s.emit("chimera.paczki.actor.changed")
        elseif kind=="lost" then s.emit("chimera.mapper.lost") else s.cleanup() end
        eq(1,r.calls);eq(false,r.value.ok);eq(1,s.cancelled)
        s.prepareDone({ok=true});s.oldCallbacks();s.advance(1000);s.line(READY);eq(0,#s.sends);eq(1,r.calls)
    end)
end
test("stop after buy before queued boarding prevents the queued send",function()
    local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done);s.line(READY);eq(1,s.commands("kup bilet"));cancel()
    s.advance(.1);s.oldCallbacks();eq(0,s.commands("wsiadz na statek"));eq(1,r.calls)
end)
test("paused voyage resumes without buying again and preserves direction",function()
    local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done);ready(s);board(s);s.line(DEPART);cancel()
    eq(false,r.value.ok);check(s.api.resumable(2));local state=s.api.state();eq(BLACK,state.toHash)
    state.link.toHash="corrupt";eq(BLACK,s.api.state().link.toHash)
    local resumed,accept=s.result();s.api.resume(2,accept);s.line(READY);eq(1,s.commands("zejdz ze statku"));arrive(s)
    eq(true,resumed.value.ok);eq(1,s.commands("kup bilet"))
end)
test("resume adopts sent landing without another leave command",function()
    local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done);ready(s);board(s);dock(s);cancel()
    local resumed,accept=s.result();s.api.resume(2,accept);s.line(READY);eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,resumed.value.ok)
end)
test("late boarding after stop settles exact pending deck proof without sends",function()
    local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done);ready(s);cancel()
    check(s.count("chimera.paczki.travel.pending")>=1,"sent boarding must remain pending")
    local before=#s.sends;board(s);eq(before,#s.sends);eq(1,s.count("chimera.paczki.travel.settled"));eq(1,r.calls)
end)
test("fresh mapped-deck resume waits for departure and arrival then validates shore",function()
    local s=setup();s.deck();local state=s.api.state();eq(true,state.aboard);eq(true,state.unknownDirection);eq(DECK,state.deckHash)
    local r,done=s.result();s.api.resume(s.link,done)
    eq(0,#s.sends);eq(0,r.calls);s.line(READY);eq(0,s.commands("zejdz ze statku"));s.line(DEPART);s.line(READY)
    eq(1,s.commands("zejdz ze statku"));arrive(s);eq(true,r.value.ok);eq(0,s.commands("kup bilet"))
end)
test("unknown-direction fresh resume at source automatically crosses once to target",function()
    local s=setup();s.deck();local r,done=s.result();s.api.resume(s.link,done);s.line(DEPART);s.line(READY)
    s.line(LEAVE);s.position(BLUE,1);eq(0,r.calls);ready(s);eq(1,s.commands("kup bilet"));board(s);dock(s);arrive(s);eq(true,r.value.ok)
end)
test("purchase sender failure stops once without boarding",function()
    local s=setup();s.sendHook=function() return false end;local r,done=s.result();s.api.run(s.link,done);s.line(READY)
    eq(false,r.value.ok);s.advance(1);eq(0,s.commands("wsiadz na statek"));eq(1,r.calls)
end)
test("stop after buying retains the ticket attempt and the next run only boards",function()
    local s=setup();local r,done=s.result();local cancel=s.api.run(s.link,done)
    s.line(READY);eq(1,s.commands("kup bilet"));eq(0,s.commands("wsiadz na statek"))
    cancel();eq(false,r.value.ok);s.advance(1)
    local state=s.api.fareState();eq(BLUE,state.fromHash);eq(BLACK,state.toHash);eq(true,state.purchaseAttempted)
    state.fromHash="corrupt";eq(BLUE,s.api.fareState().fromHash)
    local nextResult,nextDone=s.result();s.api.run(s.link,nextDone)
    s.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.")
    eq(0,s.commands("wsiadz na statek"));ready(s)
    eq(1,s.commands("kup bilet"));eq(1,s.commands("wsiadz na statek"))
    board(s);eq(nil,s.api.fareState());dock(s);arrive(s);eq(true,nextResult.value.ok)
end)
test("silent boarding timeout retains a possibly paid ticket instead of buying again",function()
    local s=setup();local r,done=s.result();s.api.run(s.link,done);ready(s);s.advance(21)
    eq(false,r.value.ok);eq(1,s.commands("kup bilet"));check(s.api.fareState())
    local nextResult,nextDone=s.result();s.api.run(s.link,nextDone);ready(s)
    eq(1,s.commands("kup bilet"));eq(2,s.commands("wsiadz na statek"))
    board(s);dock(s);arrive(s);eq(true,nextResult.value.ok);eq(1,s.commands("kup bilet"))
end)
print(string.format("Kahn-Gad transport: %d scenarios, %d assertions, %d failures",tests,checks,failures))
if failures>0 then os.exit(1) end
