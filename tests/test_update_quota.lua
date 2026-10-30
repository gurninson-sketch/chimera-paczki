-- Account-wide postal refusal observed in the 2026-10-30 Mudlet wire log.
-- Other replies below are synthetic variants; no live server is contacted.
local ROOT=(arg[0] or ""):gsub("\\","/"):match("^(.*)/tests/test_update_quota%.lua$") or "."
package.path=ROOT.."/chimera_wtyczki/?.lua;"..package.path
local create=dofile(ROOT.."/chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile(ROOT.."/chimera_wtyczki/chimera_paczki/routes.lua")
local passed=0
local function eq(a,b) assert(a==b,"expected "..tostring(a)..", got "..tostring(b)) end
local function test(name,fn) fn();passed=passed+1;print("PASS "..name) end
local REFUSAL="Urzednik zaglada do rejestru i kreci glowa: w ciagu ostatniej godziny wydal juz postaciom twojego konta 30 przesylek miejscowych. Kolejna bedzie za 2 minuty."
local HOME={id="a000000000000001",map=1,name="Poczta"}
local function fixture(saved)
    local s={time=10000,timers={},serial=0,sent={},logs={},resolves={},roams=0}
    local api={now=function() return s.time end,send=function(cmd) s.sent[#s.sent+1]=cmd end,
        schedule=function(seconds,fn) s.serial=s.serial+1;s.timers[s.serial]={at=s.time+seconds,fn=fn};return s.serial end,
        cancel=function(id) s.timers[id]=nil end,say=function(text) s.logs[#s.logs+1]=text end,
        save=function(state) s.saved=state end,position=function() return HOME end,
        nextOffice=function() s.roams=s.roams+1 end,
        resolveRoute=function(name)
            s.resolves[#s.resolves+1]=name
            return {name=name,native=true,postal=name:find("Poczta",1,true)~=nil or name:find("poczta",1,true)~=nil,cost=1,commands={}}
        end}
    local C=create(data,api,saved);C.actor="yarrim";C.source=HOME;C.mode="running";C.config.maxKg=20
    function s:advance(seconds)
        local target=self.time+seconds
        while true do local chosen,at
            for id,t in pairs(self.timers) do if t.at<=target and (not at or t.at<at) then chosen,at=id,t.at end end
            if not chosen then break end
            self.time=at;local fn=self.timers[chosen].fn;self.timers[chosen]=nil;fn()
        end
        self.time=target
    end
    function s:offer(kind,n)
        return assert(C:parseOffer((n or 1)..". "..(kind=="miejscowa" and "Bruno Rottel" or "Poczta w Nuln").." "..kind.." 1.00 kg 7 srebrnych monet [x9]"))
    end
    return C,s,api
end
test("intercity beats a lower board-number local and defers local route calculation",function()
    local C,s=fixture();local ranked=C:rank({s:offer("miejscowa",1),s:offer("miedzymiastowa",9)})
    eq(1,#ranked);eq(9,ranked[1].number);eq(1,#s.resolves);eq("poczta w nuln",s.resolves[1])
    eq("intercity_first",C.config.strategy)
end)
test("the exact account quota reply clears pickup uncertainty without rejecting an offer or a post office",function()
    local C,s=fixture();C.boardRows={s:offer("miejscowa")};C:choose();eq(true,C.awaitingPickup)
    C:onLine(REFUSAL);eq(false,C.awaitingPickup);eq(nil,C.job);eq(nil,next(C.rejected))
    eq(122,C:pickupGate("miejscowa"));eq(0,C:pickupGate("miedzymiastowa"));eq(0,s.roams)
    C:pause("stop");s:advance(130);eq(1,#s.sent)
end)
test("all blocked offers wait once at the current post until the server deadline, without roaming or polling",function()
    local C,s=fixture();C.awaitingPickup=true;C:onLine(REFUSAL);C:clearTimers()
    C.boardRows={s:offer("miejscowa")};C:choose();eq("waitingQuota",C.phase);eq(0,s.roams);eq(0,#s.sent)
    s:advance(121);eq(0,#s.sent);s:advance(1);eq("przeczytaj tablice",s.sent[1]);eq(1,#s.sent)
end)
test("blocked intercity falls back to local and a blocked local leaves intercity available",function()
    local C,s=fixture();C.awaitingPickup=true
    C:onLine(REFUSAL:gsub("miejscowych","miedzymiastowych"));C:clearTimers()
    eq("miejscowa",C:rank({s:offer("miejscowa",2),s:offer("miedzymiastowa",1)})[1].kind)
    C:pickupLimitState().classes={};C.awaitingPickup=true;C:onLine(REFUSAL);C:clearTimers()
    eq("miedzymiastowa",C:rank({s:offer("miejscowa",1),s:offer("miedzymiastowa",2)})[1].kind)
end)
test("thirty acknowledged issuances use a rolling hour and returned parcels do not refund a slot",function()
    local C,s=fixture();local o=s:offer("miejscowa");C.boardRows={o}
    for i=1,30 do C:preparePickupLimit(o);C:recordPickupLimit(o.name);s.time=s.time+1 end
    local seconds,count=C:pickupGate("miejscowa");eq(30,count);eq(3571,seconds)
    eq(0,C:pickupGate("miedzymiastowa"));s.time=13601
    local remaining,used=C:pickupGate("miejscowa");eq(0,remaining);eq(28,used)
end)
test("STOP reload and reset preserve server cooldowns while actors have separate local ledgers",function()
    local C,s=fixture();C.awaitingPickup=true;C:onLine(REFUSAL);C:command("reset")
    local copy=fixture(s.saved);eq(122,copy:pickupGate("miejscowa"))
    copy:identifyActor("Gror");eq(0,copy:pickupGate("miejscowa"))
    copy:identifyActor("Yarrim");eq(122,copy:pickupGate("miejscowa"))
end)
test("a late quota reply after STOP saves the deadline but never resumes the courier",function()
    local C,s=fixture();C.awaitingPickup=true;C:pause("STOP");C:onLine(REFUSAL)
    eq("paused",C.mode);eq(false,C.awaitingPickup);eq(122,C:pickupGate("miejscowa"));s:advance(200);eq(0,#s.sent)
end)
test("generic parcel wait seconds blocks every type and does not poll the board",function()
    local C,s=fixture();C.awaitingPickup=true
    C:onLine("Musisz jeszcze poczekac 15 sekund, zanim wybierzesz kolejna paczke.");C:clearTimers()
    eq(17,C:pickupGate("miejscowa"));eq(17,C:pickupGate("miedzymiastowa"))
    C:readBoard();eq("waitingQuota",C.phase);s:advance(16);eq(0,#s.sent)
    s:advance(1);eq("przeczytaj tablice",s.sent[1])
end)
test("dialogue and unrelated waits cannot cancel an uncertain pickup",function()
    local C=fixture();C.awaitingPickup=true
    C:onLine("Gror mowi: "..REFUSAL);eq(true,C.awaitingPickup)
    C:onLine("Musisz odczekac 30 sekund przed walka.");eq(true,C.awaitingPickup)
    eq(0,C:pickupGate("miejscowa"));C:pause("STOP")
end)
test("unknown refusal duration uses a bounded fallback and all three quota types remain independent",function()
    local C,s=fixture();C.awaitingPickup=true
    C:onLine(REFUSAL:gsub("miejscowych","miedzykrainowych"):gsub("2 minuty","chwile"));C:clearTimers()
    eq(62,C:pickupGate("miedzykrainowa"));eq(0,C:pickupGate("miedzymiastowa"));eq(0,C:pickupGate("miejscowa"))
    local ranked=C:rank({s:offer("miedzykrainowa")});eq(0,#ranked)
end)
test("pending kind survives reload and only an own pickup ACK counts once",function()
    local C,s=fixture();local o=s:offer("miejscowa");C.boardRows={o};C:preparePickupLimit(o)
    local copy=fixture(s.saved);copy.mode="paused";copy.awaitingPickup=true
    copy:onLine("Gror bierze paczke z tablicy.");local _,n=copy:pickupGate("miejscowa");eq(0,n)
    copy:onLine("Bierzesz paczke przeznaczona dla: Bruno Rottel.")
    copy:onLine("Bierzesz paczke przeznaczona dla: Bruno Rottel.")
    local _,count=copy:pickupGate("miejscowa");eq(1,count)
end)
print("Passed "..passed.." postal quota scenarios")
