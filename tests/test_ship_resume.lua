-- Actor-scoped semantic recovery of Kahn-Gad after disconnect/reload.
-- Run from chimera-native; all server replies and map calls are simulated.
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


local oldSetup=setup
local function clone(record) if type(record)~="table" then return record end;local out={};for k,v in pairs(record) do out[k]=clone(v) end;return out end
local function fixture(reverse,store,overrides)
    store=store or {actors={},actor="Yarrim",receipt=0,writes=0}
    local options={actor=function() return store.actor end,coinReceipt=function() return store.receipt end,
        coinsUncertain=function() return store.uncertain==true end,
        loadTransport=function(who) return clone(store.actors[who:lower()]) end,
        saveTransport=function(who,value) store.writes=store.writes+1;store.actors[who:lower()]=clone(value);return true end}
    for k,v in pairs(overrides or {}) do options[k]=v end
    local s=oldSetup(reverse,options);s.store=store
    return s,store
end
local function saved(store) return store.actors[store.actor:lower()] end
local function live(reverse,store,overrides)
    local s,data=fixture(reverse,store,overrides);local r,done=s.result();s.api.run(s.link,done)
    ready(s);board(s);s.line(DEPART)
    return s,data,r
end
local function recovered(reverse,store)
    local s=fixture(reverse,store);s.deck();local r,done=s.result();s.api.resume(s.link,done)
    return s,r
end
for _,reverse in ipairs({false,true}) do
 test((reverse and "reverse" or "forward").." confirmed fare survives disconnect and fresh client without restorage",function()
    local s,store=live(reverse)
    eq(true,saved(store).fareFinished);eq(1,s.stored)
    s.emit("chimera.session.end");eq(nil,s.api.status());eq(true,saved(store).fareFinished)
    local next,result=recovered(reverse,store)
    eq(0,next.stored);eq(0,#next.sends);eq(false,next.api.state().arrived)
    next.line(READY);eq(1,next.commands("zejdz ze statku"));arrive(next)
    eq(true,result.value.ok);eq(0,next.commands("kup bilet"));eq(0,next.commands("wsiadz na statek"));eq(nil,saved(store))
 end)
 test((reverse and "reverse" or "forward").." reload keeps settled fare and waits for a fresh docking event",function()
    local s,store=live(reverse);s.line(READY);eq(1,s.commands("zejdz ze statku"));eq(true,saved(store).leaveSent)
    s.cleanup()
    local next,result=recovered(reverse,store)
    eq(0,#next.sends);eq(0,next.stored)
    next.line(LEAVE);eq(0,#next.sends);eq(0,result.calls)
    next.advance(5);eq(0,#next.sends)
    next.line(READY);eq(1,next.commands("zejdz ze statku"));arrive(next);eq(true,result.value.ok)
 end)
end
test("a manual stop before disconnect preserves settlement without automatically restarting",function()
    local s,store=fixture();local result,done=s.result();local cancel=s.api.run(s.link,done);ready(s);board(s);s.line(DEPART)
    cancel();eq(1,result.calls);eq(false,result.value.ok);eq(true,saved(store).fareFinished)
    s.emit("chimera.session.end");s.advance(30);eq(nil,s.api.status());eq(0,s.commands("zejdz ze statku"))
    local next,r=recovered(false,store);eq(0,#next.sends);eq(0,next.stored);next.line(READY);arrive(next);eq(true,r.value.ok)
end)
test("the receipt before the container close is durable but never causes reentrant landing",function()
    local s,store=fixture();s.holdStore=true;local result,done=s.result();s.api.run(s.link,done);ready(s);board(s);dock(s)
    eq(true,saved(store).farePending);eq(false,saved(store).fareFinished);eq(0,s.commands("zejdz ze statku"))
    store.receipt=1;s.emit("chimera.paczki.coins.stored",{actor="Yarrim",receipt=1})
    eq(true,saved(store).fareFinished);eq(false,saved(store).farePending);eq(0,s.commands("zejdz ze statku"))
    s.emit("chimera.session.end")
    local next,r=recovered(false,store);eq(0,next.stored);next.line(READY);arrive(next);eq(true,r.value.ok)
end)
test("a foreign actor or obsolete receipt cannot settle the pending fare",function()
    local s,store=fixture();s.holdStore=true;s.api.run(s.link,function() end);ready(s);board(s)
    s.emit("chimera.paczki.coins.stored",{actor="Morrid",receipt=5});eq(false,saved(store).fareFinished)
    s.emit("chimera.paczki.coins.stored",{actor="Yarrim",receipt=0});eq(false,saved(store).fareFinished)
end)
test("a transfer that remains uncertain is never restowed after reconnect",function()
    local s,store=fixture();s.holdStore=true;s.api.run(s.link,function() end);ready(s);board(s)
    store.uncertain=true;s.emit("chimera.session.end");eq(true,saved(store).fareUncertain)
    local next,r=recovered(false,store);eq(1,r.calls);eq(false,r.value.ok);eq(0,next.stored);eq(0,#next.sends)
end)
test("a recovered pending settlement is deferred without repeating an optional transfer",function()
    local s,store=fixture();s.holdStore=true;s.api.run(s.link,function() end);ready(s);board(s)
    s.emit("chimera.session.end");eq(false,saved(store).fareUncertain);eq(true,saved(store).farePending)
    local next,r=recovered(false,store);eq(0,next.stored);eq(false,next.api.state().fareFinished);eq(true,next.api.state().fareDeferred)
    next.line(READY);arrive(next);eq(true,r.value.ok)
end)
test("legacy deck upgrade defers optional cash housekeeping without a false storage receipt",function()
    local s,store=fixture();s.deck();local r,done=s.result();s.api.resume(s.link,done)
    eq(0,s.stored);eq(0,#s.sends);eq(false,s.api.state().fareFinished);eq(true,s.api.state().fareDeferred)
    s.line(READY);arrive(s);eq(true,r.value.ok);eq(0,s.stored)
end)
test("legacy deck with an uncertain physical transfer remains guarded",function()
    local store={actors={},actor="Yarrim",receipt=0,writes=0,uncertain=true}
    local s,r=recovered(false,store);eq(false,r.value.ok);eq(0,s.stored);eq(0,#s.sends)
end)
test("a definite optional storage refusal is deferred while the ship continues",function()
    local s,store=live(false,nil,{finishFare=function(done) done({ok=false,reason="gra nie rozpoznala komendy przeniesienia: wloz co?"}) end})
    eq(false,s.api.state().fareFinished);eq(true,s.api.state().fareDeferred)
    s.line(READY);arrive(s);eq(nil,s.api.status());eq(nil,saved(store))
end)
test("an uncertain optional storage failure cannot be deferred",function()
    local store={actors={},actor="Yarrim",receipt=0,writes=0,uncertain=false}
    local s=fixture(false,store,{finishFare=function(done) store.uncertain=true;done({ok=false,reason="timeout"}) end})
    local r,done=s.result();s.api.run(s.link,done);ready(s);board(s)
    eq(false,r.value.ok);eq(true,saved(store).fareUncertain);eq(false,saved(store).fareDeferred)
end)
test("a possibly purchased ticket on the exact bank is boarded without buying twice after a new client",function()
    local s,store=fixture();s.api.run(s.link,function() end);s.line(READY);eq(1,s.commands("kup bilet"));eq(0,s.commands("wsiadz na statek"))
    s.emit("chimera.session.end");eq(true,saved(store).bought)
    local next=fixture(false,store);local r,done=next.result();next.api.run(next.link,done);ready(next)
    eq(0,next.prepared);eq(0,next.commands("kup bilet"));eq(1,next.commands("wsiadz na statek"))
    board(next);dock(next);arrive(next);eq(true,r.value.ok)
end)
test("confirmed cash prepared before purchase is not withdrawn again after reconnect",function()
    local s,store=fixture();s.holdPrepare=true;s.api.run(s.link,function() end);s.line(READY);s.line(DEPART);s.prepareDone({ok=true})
    eq(true,saved(store).farePrepared);eq(false,saved(store).bought);eq(0,#s.sends)
    s.emit("chimera.session.end")
    local next=fixture(false,store);next.api.run(next.link,function() end);ready(next)
    eq(0,next.prepared);eq(1,next.commands("kup bilet"));eq(1,next.commands("wsiadz na statek"))
end)
test("another character never inherits the settled fare of the first character",function()
    local s,store=live();s.emit("chimera.session.end");eq(true,store.actors.yarrim.fareFinished)
    store.actor="Morrid"
    local next,r=recovered(false,store);eq(false,next.api.state().fareFinished);eq(true,next.api.state().fareDeferred)
    eq(0,next.stored);next.line(READY);arrive(next);eq(true,r.value.ok);eq(true,store.actors.yarrim.fareFinished)
end)
test("offline direction is verified at the first shore and corrected only once",function()
    local s,store=live();s.emit("chimera.session.end")
    local next,r=recovered(false,store);next.line(READY);eq(1,next.commands("zejdz ze statku"))
    next.line(LEAVE);next.position(BLUE,1);next.advance(.05)
    eq(1,next.commands("kup bilet"));eq(1,next.commands("wsiadz na statek"))
    board(next);dock(next);eq(2,next.commands("zejdz ze statku"));arrive(next);eq(true,r.value.ok)
end)
test("failed persistence prevents spending and a ticket command",function()
    local s=fixture(false,nil,{saveTransport=function() return false end})
    local r,done=s.result();s.api.run(s.link,done);s.line(READY)
    eq(1,r.calls);eq(false,r.value.ok);eq(0,#s.sends)
end)
test("unrelated lines do not repeatedly write identical transport snapshots",function()
    local s,store=live();local writes=store.writes
    for _=1,100 do s.line("Fala przelewa sie po pokladzie.") end
    eq(writes,store.writes)
end)
test("persistent transport records contain only semantic fields and stable shore hashes",function()
    local s,store=live();local record=saved(store)
    eq(1,record.schema);eq("karak_ship",record.transport);eq(BLUE,record.fromHash);eq(BLACK,record.toHash)
    eq(nil,record.link);eq(nil,record.deckMap);eq(nil,record.fromMap);eq(nil,record.toMap);eq(nil,record.timer)
    local allow={schema=true,transport=true,actor=true,fromHash=true,toHash=true,currentToHash=true}
    for _,key in ipairs({"aboard","boardSeen","boardSent","bought","farePrepared","fareFinished","farePending","fareUncertain","fareDeferred","departed","arrived","leaveSent","landSeen","directionUnknown","corrected"}) do allow[key]=true end
    for key in pairs(record) do check(allow[key],"unexpected saved key: "..key) end
end)
test("late own receipt after STOP settles the paused token without sending and then resumes",function()
    local s,store=fixture();s.holdStore=true;local r,done=s.result();local cancel=s.api.run(s.link,done)
    ready(s);board(s);store.uncertain=true;cancel();eq(true,s.api.state().fareUncertain)
    local before=#s.sends;store.uncertain=false;store.receipt=1
    s.emit("chimera.paczki.coins.stored",{actor="Yarrim",receipt=1})
    eq(before,#s.sends);eq(true,s.api.state().fareFinished);eq(false,s.api.state().fareUncertain)
    local resumed,callback=s.result();s.api.resume(s.link,callback);eq(1,s.stored)
    dock(s);arrive(s);eq(true,resumed.value.ok)
end)
test("a saved ticket attempt on the opposite bank prevents a new purchase",function()
    local s,store=fixture();s.api.run(s.link,function() end);s.line(READY);s.emit("chimera.session.end")
    local next=fixture(true,store);local r,done=next.result();next.api.run(next.link,done);ready(next)
    eq(1,r.calls);eq(false,r.value.ok);eq(0,next.commands("kup bilet"));eq(0,next.prepared)
end)
test("runtime actor changes without a bus event do not reuse another actor ticket",function()
    local s,store=fixture();local r,done=s.result();local cancel=s.api.run(s.link,done);s.line(READY);cancel()
    eq(1,s.commands("kup bilet"));store.actor="Morrid"
    local nextResult,callback=s.result();s.api.run(s.link,callback);ready(s)
    eq(2,s.commands("kup bilet"));eq(2,s.prepared);eq("Morrid",s.api.fareState().actor)
end)
test("runtime actor changes without a bus event cannot inherit a settled remembered voyage",function()
    local s,store=fixture();local cancel=s.api.run(s.link,function() end);ready(s);board(s);s.line(DEPART);cancel()
    eq(true,s.api.state().fareFinished);store.actor="Morrid";eq(nil,s.api.state().fareFinished)
    local r,callback=s.result();s.api.resume(s.link,callback)
    eq(false,s.api.state().fareFinished);eq(true,s.api.state().fareDeferred);eq(1,s.stored)
end)
test("skipped optional storage is deferred and never recorded as a monetary receipt",function()
    local s,store=live(false,nil,{finishFare=function(done) done({ok=true,skipped=true,moved=false}) end})
    eq(false,s.api.state().fareFinished);eq(true,s.api.state().fareDeferred)
    eq(false,saved(store).fareFinished);eq(true,saved(store).fareDeferred)
    s.line(READY);arrive(s);eq(nil,saved(store))
end)
print(string.format("SHIP_RESUME: %d scenarios, %d assertions, %d failures",tests,checks,failures))
if failures>0 then os.exit(1) end
