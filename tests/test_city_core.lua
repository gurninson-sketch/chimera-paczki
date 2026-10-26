-- Core ownership and physical-operation tests for city recipient recovery.
-- Run from chimera-native: texlua tests/test_city_core.lua
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local cases,assertions=0,0
local function ok(value,message) assertions=assertions+1;assert(value,message or "assertion failed") end
local function eq(actual,expected,message)
    ok(actual==expected,(message or "different values")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function fixture(settings)
    settings=settings or {}
    local e={time=0,timers={},sequence=0,sends={},logs={},navs={},inventory={},saves={},ready=settings.ready==true,
        travel=false,absences=0,parcel="hands"}
    local b
    local route={native=true,name=settings.captain and "Annibale Malacresta Lettore" or "Torquato di Assemani",
        city=settings.city~=false,periodic=settings.captain==true,rooms={2},roomIds={[2]="recipient"},commands={}}
    local source={map=1,id="source",name="Poczta w Campogrotta",staticNuln=false}
    local api={
        now=function() return e.time end,
        say=function(message) e.logs[#e.logs+1]=message end,
        send=function(command) e.sends[#e.sends+1]=command end,
        schedule=function(delay,fn) e.sequence=e.sequence+1;e.timers[e.sequence]={at=e.time+delay,fn=fn};return e.sequence end,
        cancel=function(id) e.timers[id]=nil end,
        saveRun=function(actor,state) e.saves[#e.saves+1]={actor=actor,state=state};return true end,
        inventoryState=function() return {state=e.parcel,coinsUncertain=e.coinsUncertain==true} end,
        canSearchFor=function(r) return r.city and not r.periodic and not r.postal end,
        canWaitFor=function(r) return r.periodic end,
        recipientAbsent=function(r) e.absences=e.absences+1;e.ready=false;e.absentRoute=r end,
        deliveryReady=function() return e.ready end,
        travelPending=function() return e.travel end,
        navigate=function(r,returning,done)
            local nav={route=r,returning=returning,done=done};e.navs[#e.navs+1]=nav
            if e.syncNav then done(true) end
            return function() nav.cancelled=true;done(false,"przerwane") end
        end,
        inventory=function(action,done)
            local inv={action=action,done=done};e.inventory[#e.inventory+1]=inv
            if e.syncInventory then done({ok=true}) end
            return function() inv.cancelled=true;done({ok=false,reason="przerwane"}) end
        end,
        position=function() return {map=2,id="recipient",name="Plac"} end,
    }
    b=create(data,api)
    b.actor="yarrim";b.mode="running";b.phase="delivery";b.source=source;b.staticSource=false
    b.stopAt=7;b.stats.delivered=3
    b.job={name=route.name,route=route,source=source,actor="yarrim",recipientConfirmed=true,delivered=false}
    b.awaitingDelivery=true
    function e:advance(seconds)
        local ending=self.time+seconds
        for _=1,10000 do
            local chosen,at
            for id,timer in pairs(self.timers) do
                if timer.at<=ending and (not at or timer.at<at or (timer.at==at and id<chosen)) then chosen,at=id,timer.at end
            end
            if not chosen then self.time=ending;return end
            local timer=self.timers[chosen];self.timers[chosen]=nil;self.time=at;timer.fn()
        end
        error("unbounded synchronous callback loop")
    end
    function e:navDone(result,index) self.navs[index or #self.navs].done(result~=false,result==false and "fixture failure" or nil) end
    function e:inventoryDone(result,index) self.inventory[index or #self.inventory].done(result or {ok=true}) end
    function e:count(command)
        local count=0;for _,sent in ipairs(self.sends) do if sent==command then count=count+1 end end;return count
    end
    function e:allLogs() return table.concat(self.logs,"\n") end
    return b,e,route,source,api
end

test("definite city absence begins owned search and preserves course",function()
    local b,e,route,source=fixture()
    local job=b.job
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(b.mode,"running");eq(b.phase,"outbound");eq(#e.navs,1);eq(e.navs[1].route,route)
    eq(e.navs[1].returning,nil);eq(e.absences,1);eq(b.job,job);eq(b.source,source)
    eq(b.job.source,source);eq(b.stopAt,7);eq(b.stats.delivered,3);eq(b.job.delivered,false)
    eq(b.awaitingDelivery,false);eq(e.parcel,"hands");eq(#e.inventory,0);eq(#e.sends,0)
    ok(e:allLogs():find("Szukam go",1,true));ok(#e.saves>0)
end)
test("trailing second absence line cannot launch a duplicate search",function()
    local b,e=fixture()
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    b:onLine("Musisz odnalezc Torquato di Assemani i wreczyc mu paczke osobiscie.")
    eq(#e.navs,1);eq(e.absences,1);eq(b.mode,"running");eq(#e.sends,0)
end)
test("full recipient absence reply alone starts search",function()
    local b,e=fixture()
    b:onLine("Musisz odnalezc Torquato di Assemani i wreczyc mu paczke osobiscie.")
    eq(#e.navs,1);eq(e.absences,1);eq(b.awaitingDelivery,false)
end)
test("periodic captain retains stationary wait and original explanation",function()
    local b,e=fixture({captain=true})
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(#e.navs,1);eq(b.mode,"running");eq(e.absences,1)
    ok(e:allLogs():find("Czekam na jego powrot w tej lokacji.",1,true))
    ok(not e:allLogs():find("miasta",1,true))
end)
test("ordinary noncity route still stops after definite absence",function()
    local b,e=fixture({city=false})
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(b.mode,"paused");eq(#e.navs,0);eq(e.absences,0);eq(b.awaitingDelivery,false)
end)
test("postal recipient does not become a roaming NPC",function()
    local b,e,route=fixture();route.postal=true
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(b.mode,"paused");eq(#e.navs,0);eq(e.absences,0)
end)
test("missing search hook keeps the existing nonperiodic refusal",function()
    local b,e,_,_,api=fixture();api.canSearchFor=nil
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(b.mode,"paused");eq(#e.navs,0)
end)
test("truthy nonboolean search eligibility cannot authorize city movement",function()
    local b,e,_,_,api=fixture();api.canSearchFor=function() return "yes" end
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(b.mode,"paused");eq(#e.navs,0)
end)
test("missing physical parcel response is not treated as absent recipient",function()
    for _,reply in ipairs({"Nie masz paczki.","Nie niesiesz zadnej paczki.","Nie widzisz takiej przesylki."}) do
        local b,e=fixture();b:onLine(reply)
        eq(b.mode,"paused");eq(#e.navs,0);eq(e.absences,0);eq(b.stats.delivered,3)
    end
end)
test("unknown handover timeout preserves uncertainty and does not search",function()
    local b,e=fixture();b:watch("doreczenie paczki");e:advance(11)
    eq(b.mode,"paused");eq(b.awaitingDelivery,true);eq(#e.navs,0);eq(b.job.delivered,false)
end)
test("recipient check before withdrawal searches without inventory commands",function()
    local b,e=fixture();b.awaitingDelivery=false;b:deliver()
    eq(b.mode,"running");eq(#e.navs,1);eq(#e.inventory,0);eq(#e.sends,0)
end)
test("departure while withdrawing searches after transfer ACK without stowing again",function()
    local b,e=fixture({ready=true});b.awaitingDelivery=false;b:deliver()
    eq(#e.inventory,1);eq(e.inventory[1].action,"takeParcel")
    e.ready=false;e:inventoryDone()
    eq(#e.navs,1);eq(#e.inventory,1);eq(#e.sends,0);eq(b.mode,"running")
end)
test("unconfirmed withdrawal still stops instead of searching",function()
    local b,e=fixture({ready=true});b.awaitingDelivery=false;b:deliver()
    e.ready=false;e:inventoryDone({ok=false,reason="no transfer confirmation"})
    eq(b.mode,"paused");eq(#e.navs,0);eq(#e.sends,0)
end)
test("departure during introduction delay cancels the pending gift",function()
    local b,e=fixture({ready=true});b.awaitingDelivery=false;b:handoverParcel()
    eq(e:count("przedstaw sie"),1)
    e.ready=false;e:advance(0.6)
    eq(e:count("oddaj paczke"),0);eq(#e.navs,1);eq(b.mode,"running")
end)
test("fresh successful search rechecks presence before a single gift",function()
    local b,e=fixture();b:onLine("Adresat nie znajduje sie w tym miejscu.")
    e.ready=true;e:navDone();e:advance(b:delay())
    eq(#e.inventory,1);eq(e.inventory[1].action,"takeParcel")
    e:inventoryDone();eq(e:count("przedstaw sie"),1)
    e:advance(0.6);eq(e:count("oddaj paczke"),1);eq(b.awaitingDelivery,true)
    eq(b.stats.delivered,3);eq(b.job.delivered,false)
    b:onLine("Wrecasz paczke adresatowi.")
    eq(b.stats.delivered,4);eq(b.job.delivered,true);eq(b.awaitingReward,true)
    b:onLine("Adresat wrecza ci 6 srebrnych monet za trud.")
    eq(b.stats.silver,6);eq(b.awaitingReward,false);eq(b.job.coinsPending,true)
end)
test("synchronous search result yields before rechecking an absent recipient",function()
    local b,e=fixture();e.syncNav=true
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(#e.navs,1);eq(b.mode,"running");eq(#e.sends,0)
    e:advance(b:delay());eq(#e.navs,2);eq(#e.sends,0)
    b:stop("fixture stop");e:advance(100);eq(#e.navs,2)
end)
test("search waits for an outstanding owned movement ACK",function()
    local b,e=fixture();e.travel=true
    b:onLine("Adresat nie znajduje sie w tym miejscu.")
    eq(#e.navs,0);eq(b.phase,"searchingCity");eq(e.absences,1)
    e:advance(0.31);eq(#e.navs,0);eq(#e.sends,0);eq(e.absences,1)
    e.travel=false;e:advance(0.1)
    eq(#e.navs,1);eq(b.mode,"running");eq(e.absences,1)
end)
test("STOP cancels movement-settlement retry and late navigation completion",function()
    local b,e=fixture();e.travel=true
    b:onLine("Adresat nie znajduje sie w tym miejscu.");b:stop("manual stop")
    e.travel=false;e:advance(50)
    eq(b.mode,"stopped");eq(#e.navs,0);eq(#e.sends,0)
    local c,x=fixture();c:onLine("Adresat nie znajduje sie w tym miejscu.")
    c:stop("manual stop");x.ready=true;x:navDone();x:advance(50)
    eq(c.mode,"stopped");eq(#x.inventory,0);eq(#x.sends,0);ok(x.navs[1].cancelled)
end)
test("definite absence cancels only handover watchdog while search owns waiting",function()
    local b,e=fixture();b:watch("doreczenie paczki")
    b:onLine("Adresat nie znajduje sie w tym miejscu.");e:advance(100)
    eq(b.mode,"running");eq(#e.navs,1);eq(b.awaitingDelivery,false)
end)
test("navigator failure remains a real pause and cannot fabricate delivery",function()
    local b,e=fixture();b:onLine("Adresat nie znajduje sie w tym miejscu.")
    e:navDone(false);e:advance(5)
    eq(b.mode,"paused");eq(b.job.delivered,false);eq(b.stats.delivered,3);eq(#e.sends,0)
end)
test("city wait explanation is cleared after a verified search arrival",function()
    local b,e=fixture();b:onLine("Adresat nie znajduje sie w tym miejscu.")
    b.phase="searchingCity";b.lastPause="Szukam adresata w granicach miasta."
    e.ready=true;e:navDone();e:advance(b:delay())
    eq(b.lastPause,nil);eq(#e.inventory,1)
end)

print("CITY_CORE: "..cases.." scenarios, "..assertions.." assertions passed")
