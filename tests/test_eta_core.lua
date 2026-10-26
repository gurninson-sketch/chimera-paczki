-- Behavioral ETA ranking and successful-cycle hooks in the injected core.
-- Run from chimera-native: texlua tests/test_eta_core.lua
package.path="chimera_wtyczki/?.lua;"..package.path
local create=dofile("chimera_wtyczki/chimera_paczki/core.lua")
local data=dofile("chimera_wtyczki/chimera_paczki/routes.lua")
local cases,assertions=0,0
local function ok(value,message) assertions=assertions+1;assert(value,message or "check failed") end
local function eq(actual,expected,message)
    ok(actual==expected,(message or "different")..": "..tostring(actual).." ~= "..tostring(expected))
end
local function close(actual,expected,message) ok(math.abs(actual-expected)<0.000001,message) end
local function copy(value) local out={};for k,v in pairs(value) do out[k]=v end;return out end
local OFFICE={map=101,id="a000000000000101",name="Glowna sala poczty w Krainie Zgromadzenia"}
local function fresh(overrides)
    local e={time=100,timers={},nextId=0,sends={},logs={},routes={},navs={},events={},current=copy(OFFICE),etaCalls={}}
    local b
    local function event(kind,job,place)
        e.events[#e.events+1]={kind=kind,job=job,place=place,time=e.time,delivered=job and job.delivered,
            coinsPending=job and job.coinsPending,jobStillCurrent=job and b and b.job==job}
    end
    local api={
        send=function(command) e.sends[#e.sends+1]=command;event("send:"..command) end,
        say=function(message) e.logs[#e.logs+1]=message end,
        now=function() return e.time end,
        schedule=function(delay,fn) e.nextId=e.nextId+1;e.timers[e.nextId]={at=e.time+delay,fn=fn};return e.nextId end,
        cancel=function(id) e.timers[id]=nil end,
        position=function() return copy(e.current) end,
        source=function() return e.current.id==OFFICE.id and copy(e.current) or nil end,
        currentOffice=function() return e.current.name:lower():find("poczt",1,true) and copy(e.current) or nil end,
        resolveRoute=function(name) return e.routes[b.norm(name)] end,
        estimateTime=function(offer,route,source,delay)
            e.etaCalls[#e.etaCalls+1]={offer=offer,route=route,source=source,delay=delay}
            return {seconds=route.eta or 60,method="estimate",samples=0,confidence="low",breakdown={movement=route.eta or 60}}
        end,
        navigate=function(route,returning,done)
            local op={route=route,returning=returning,done=done};e.navs[#e.navs+1]=op
            return function() op.cancelled=true;done(false,"przerwane") end
        end,
        startTiming=function(offer,source) event("start",offer,source) end,
        pickupTiming=function(job) event("pickup",job) end,
        handoverTiming=function(job) event("handover",job) end,
        rewardTiming=function(job) event("reward",job) end,
        finishTiming=function(job,place) event("finish",job,place) end,
        cancelTiming=function(reason) event("cancel:"..tostring(reason)) end,
        timingDelay=function(seconds) e.delays=(e.delays or 0)+seconds end,
    }
    for key,value in pairs(overrides or {}) do api[key]=value end
    b=create(data,api);b.source=copy(OFFICE);b.staticSource=false;b.actor="testowicz";b.config.roam=false
    function e:route(name,cost,seconds,postal,map)
        local destination={map=map or 202,id="a000000000000"..tostring(map or 202),name=postal and name or "Sklep"}
        local route={native=true,name=name,cost=cost,commands={},eta=seconds,postal=postal,destination=destination,
            targetId=destination.id,roomIds={[destination.map]=destination.id}}
        self.routes[b.norm(name)]=route;return route
    end
    function e:tick()
        local chosen,when
        for id,timer in pairs(self.timers) do
            if not when or timer.at<when or (timer.at==when and id<chosen) then chosen,when=id,timer.at end
        end
        if not chosen then return false end
        local timer=self.timers[chosen];self.timers[chosen]=nil;self.time=timer.at;timer.fn();return true
    end
    function e:untilSend()
        local before=#self.sends
        for _=1,30 do if not self:tick() then return nil end;if #self.sends>before then return self.sends[#self.sends] end end
        error("too many callbacks")
    end
    function e:arrive(op)
        op=op or self.navs[#self.navs]
        self.current=copy(op.returning and op.route or op.route.destination)
        op.done(true)
    end
    function e:eventsOf(kind)
        local out={};for _,value in ipairs(self.events) do if value.kind==kind then out[#out+1]=value end end;return out
    end
    return b,e,api
end
local function offer(b,number,name,pay,kg,count,kind)
    return assert(b:parseOffer(number..". "..name.." "..(kind or "miejscowa").." "..(kg or 1).." kg "..pay.." [x"..(count or 1).."]"))
end
local function test(label,fn) fn();cases=cases+1;print("PASS "..label) end
local function selected(b,e,name,postal)
    e:route(name,20,60,postal)
    b.mode="running";b.phase="board";b.stopAt=1
    b.boardRows={offer(b,1,name,"9 srebrnych monet",1,1,postal and "miedzymiastowa" or "miejscowa")}
    b:choose();eq(e.sends[#e.sends],"wybierz paczke 1")
    b:onLine("Bierzesz paczke przeznaczona dla: "..name..".")
    ok(e:tick());eq(#e.navs,1)
    return b.job
end
local function atRecipient(b,e,postal)
    e:arrive()
    if not postal then eq(e:untilSend(),"przedstaw sie") end
    eq(e:untilSend(),"oddaj paczke")
end

test("rate ranks reward per actual estimated minute instead of weighted map cost",function()
    local b,e=fresh();e:route("Johan Kornwalz",1,300);e:route("Olaff Meier Mlodszy",100,60)
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","10 srebrnych monet"),offer(b,2,"Olaff Meier Mlodszy","8 srebrnych monet")})
    eq(ranked[1].number,2);close(ranked[1].score,8);close(ranked[2].score,2)
end)
test("gold silver and copper convert to a common silver-per-minute scale",function()
    local b,e=fresh();e:route("Johan Kornwalz",50,120)
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","1 zlota, 2 srebrne i 6 miedzianych monet")})
    eq(ranked[1].value,270);close(ranked[1].score,11.25)
    close(b.offerDiagnostics[1].silverPerMinute,11.25)
end)
test("offer availability never multiplies the reward of the single carried parcel",function()
    local b,e=fresh();e:route("Johan Kornwalz",2,60);e:route("Olaff Meier Mlodszy",2,60)
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","5 srebrnych monet",1,99),offer(b,2,"Olaff Meier Mlodszy","6 srebrnych monet",1,1)})
    eq(ranked[1].number,2);close(ranked[2].score,5)
end)
test("weight availability reward route rejection and parcel kind filter before ETA",function()
    local b,e=fresh();e:route("Johan Kornwalz",10,60);e:route("Olaff Meier Mlodszy",10,60)
    local rejected=offer(b,4,"Johan Kornwalz","7 srebrnych monet");b.rejected[b:offerKey(rejected)]=true
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","100 srebrnych monet",20),offer(b,2,"Johan Kornwalz","100 srebrnych monet",1,0),
        offer(b,3,"Johan Kornwalz","0 srebrnych monet"),rejected,offer(b,5,"Nieznany Tragarz","100 srebrnych monet"),
        offer(b,6,"Johan Kornwalz","100 srebrnych monet",1,1,"miedzymiastowa"),offer(b,7,"Olaff Meier Mlodszy","5 srebrnych monet")})
    eq(#ranked,1);eq(ranked[1].number,7);eq(#e.etaCalls,1)
    local expected={"weight","empty","pay","rejected","route","kind","eligible"}
    for i,category in ipairs(expected) do eq(b.offerDiagnostics[i].category,category) end
end)
test("missing zero negative nonfinite and malformed time never create an infinite winning offer",function()
    local invalid={false,0,-1,math.huge,0/0,"60",{}}
    for _,seconds in ipairs(invalid) do
        local b,e=fresh({estimateTime=function(o) if o.number==1 then return {seconds=seconds} end;return {seconds=60} end})
        e:route("Johan Kornwalz",1,1);e:route("Olaff Meier Mlodszy",100,60)
        local ranked=b:rank({offer(b,1,"Johan Kornwalz","99 zlotych monet"),offer(b,2,"Olaff Meier Mlodszy","5 srebrnych monet")})
        eq(#ranked,1);eq(ranked[1].number,2);eq(b.offerDiagnostics[1].category,"time");eq(b.offerDiagnostics[1].eligible,false)
    end
end)
test("estimator failure becomes a rejected-time diagnostic and does not crash the courier",function()
    local b,e=fresh({estimateTime=function() error("synthetic unavailable timing") end});e:route("Johan Kornwalz",1,1)
    b.mode="running";b.phase="board";b.boardRows={offer(b,1,"Johan Kornwalz","10 srebrnych monet")}
    b:choose();eq(b.mode,"running");eq(b.phase,"waiting");eq(#e.sends,0);eq(b.offerDiagnostics[1].category,"time")
end)
test("pay strategy retains total-price priority before the time-rate tie breaker",function()
    local b,e=fresh();e:route("Johan Kornwalz",1,600);e:route("Olaff Meier Mlodszy",100,60);b.config.strategy="pay"
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","10 srebrnych monet"),offer(b,2,"Olaff Meier Mlodszy","8 srebrnych monet")})
    eq(ranked[1].number,1)
end)
test("light strategy retains parcel-mass priority and uses time-rate only within the same mass",function()
    local b,e=fresh();e:route("Johan Kornwalz",1,600);e:route("Olaff Meier Mlodszy",100,60);b.config.strategy="light"
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","5 srebrnych monet",0.5),offer(b,2,"Olaff Meier Mlodszy","8 srebrnych monet",1)})
    eq(ranked[1].number,1)
    ranked=b:rank({offer(b,1,"Johan Kornwalz","5 srebrnych monet",1),offer(b,2,"Olaff Meier Mlodszy","8 srebrnych monet",1)})
    eq(ranked[1].number,2)
end)
test("exact rate ties retain stable mass then board-number ordering",function()
    local b,e=fresh();e:route("Johan Kornwalz",1,60);e:route("Olaff Meier Mlodszy",1,60)
    local ranked=b:rank({offer(b,2,"Johan Kornwalz","5 srebrnych monet",1),offer(b,1,"Olaff Meier Mlodszy","5 srebrnych monet",0.5)})
    eq(ranked[1].number,1)
    ranked=b:rank({offer(b,2,"Johan Kornwalz","5 srebrnych monet",1),offer(b,1,"Olaff Meier Mlodszy","5 srebrnych monet",1)})
    eq(ranked[1].number,1)
end)
test("current movement tempo is passed afresh and can change which parcel is preferred",function()
    local received={}
    local b,e=fresh({estimateTime=function(o,r,s,delay)
        received[#received+1]=delay;return {seconds=o.number==1 and 100*delay+10 or 100}
    end});e:route("Johan Kornwalz",1,1);e:route("Olaff Meier Mlodszy",100,1)
    b.config.tempoSource="courier";b.config.delay=0.2
    local rows={offer(b,1,"Johan Kornwalz","5 srebrnych monet"),offer(b,2,"Olaff Meier Mlodszy","5 srebrnych monet")}
    eq(b:rank(rows)[1].number,1);close(received[1],0.2)
    b.config.delay=2;eq(b:rank(rows)[1].number,2);close(received[3],2)
end)
test("offer diagnostics retain ETA confidence and sample evidence without sending commands",function()
    local b,e=fresh({estimateTime=function() return {seconds=125.5,method="learned",samples=4,confidence="medium"} end})
    e:route("Johan Kornwalz",99,1)
    local rows={offer(b,1,"Johan Kornwalz","5 srebrnych monet")};local count=rows[1].count
    b:rank(rows);local detail=b.offerDiagnostics[1]
    close(detail.etaSeconds,125.5);eq(detail.timeMethod,"learned");eq(detail.timeSamples,4);eq(detail.timeConfidence,"medium")
    eq(detail.rank,1);eq(detail.cost,99);eq(rows[1].count,count);eq(#e.sends,0)
end)
test("an old injected engine without an estimator retains its documented legacy ranking",function()
    local b,e,api=fresh();api.estimateTime=nil;e:route("Johan Kornwalz",1,300);e:route("Olaff Meier Mlodszy",100,60)
    local ranked=b:rank({offer(b,1,"Johan Kornwalz","10 srebrnych monet"),offer(b,2,"Olaff Meier Mlodszy","8 srebrnych monet")})
    eq(ranked[1].number,1)
end)
test("a successful NPC cycle records pickup handover reward and actual return in order",function()
    local b,e=fresh();local job=selected(b,e,"Johan Kornwalz")
    local start=e:eventsOf("start")[1];ok(start);eq(start.place.id,OFFICE.id)
    local startIndex,sendIndex
    for i,event in ipairs(e.events) do if event.kind=="start" then startIndex=i elseif event.kind=="send:wybierz paczke 1" then sendIndex=i end end
    ok(startIndex<sendIndex,"timing starts before the physical pickup command")
    eq(#e:eventsOf("pickup"),1);eq(#e:eventsOf("finish"),0)
    atRecipient(b,e)
    b:onLine("Wrecasz paczke adresatowi.");eq(#e:eventsOf("handover"),1);eq(#e:eventsOf("finish"),0)
    b:onLine("Adresat wrecza ci 9 srebrnych monet za trud.");eq(#e:eventsOf("reward"),1)
    ok(e:tick());eq(#e:eventsOf("finish"),0,"payment alone is not a complete NPC earning cycle")
    local returning=e.navs[#e.navs];eq(returning.returning,true)
    e:arrive(returning);ok(e:tick());local finished=e:eventsOf("finish")
    eq(#finished,1);eq(finished[1].job,job);eq(finished[1].place.id,OFFICE.id);eq(finished[1].jobStillCurrent,true)
    eq(finished[1].delivered,true);eq(finished[1].coinsPending,false);eq(b.job,nil);eq(b.mode,"stopped")
    local ordered={};for _,event in ipairs(e.events) do if event.kind=="start" or event.kind=="pickup" or event.kind=="handover" or event.kind=="reward" or event.kind=="finish" then ordered[#ordered+1]=event.kind end end
    eq(table.concat(ordered,","),"start,pickup,handover,reward,finish")
end)
test("a postal cycle finishes in the verified destination office after payment settlement",function()
    local b,e=fresh();local job=selected(b,e,"Poczta w Bissingen",true);atRecipient(b,e,true)
    b:onLine("Zostawiasz przesylke w okienku urzedu pocztowego.");eq(#e:eventsOf("finish"),0)
    b:onLine("Urzednik wyplaca ci 9 srebrnych monet za trud.");eq(#e:eventsOf("finish"),0)
    ok(e:tick());local finished=e:eventsOf("finish")
    eq(#finished,1);eq(finished[1].job,job);eq(finished[1].place.id,e.current.id);eq(finished[1].jobStillCurrent,true)
    eq(finished[1].coinsPending,false);eq(#e.navs,1);eq(b.source.id,e.current.id);eq(b.mode,"stopped")
end)
test("handover without the actual payout never finishes a timing sample",function()
    local b,e=fresh();selected(b,e,"Johan Kornwalz");atRecipient(b,e)
    b:onLine("Wrecasz paczke adresatowi.");eq(#e:eventsOf("handover"),1)
    ok(e:tick());eq(#e:eventsOf("reward"),0);eq(#e:eventsOf("finish"),0);eq(b.mode,"paused")
end)
test("a rejected pickup never supplies confirmed pickup or completed timing evidence",function()
    local b,e=fresh();e:route("Johan Kornwalz",20,60);b.mode="running";b.phase="board"
    b.boardRows={offer(b,1,"Johan Kornwalz","9 srebrnych monet")};b:choose()
    b:onLine("Nie ma juz tej paczki.")
    eq(#e:eventsOf("pickup"),0);eq(#e:eventsOf("handover"),0);eq(#e:eventsOf("reward"),0);eq(#e:eventsOf("finish"),0)
end)
test("only executed paced action callbacks contribute delay measurements",function()
    local b,e=fresh();b.mode="running"
    b:later("action",2,function() end);b:cancel("action");eq(e.delays,nil)
    b:later("action",3,function() end);ok(e:tick());close(e.delays,3)
    b:later("watchdog",4,function() end);ok(e:tick());close(e.delays,3)
    b:later("restResume",1.5,function() end);ok(e:tick());close(e.delays,4.5)
end)
test("a completed NPC cycle tags its one minimum introduction delay even above the floor",function()
    for _,tempo in ipairs({0.2,1.5}) do
        local markers={}
        local b,e=fresh({timingDelay=function(seconds,minimumUnits)
            markers[#markers+1]={seconds=seconds,minimumUnits=minimumUnits}
        end})
        b.config.tempoSource="courier";b.config.delay=tempo
        selected(b,e,"Johan Kornwalz");atRecipient(b,e)
        b:onLine("Wrecasz paczke adresatowi.")
        b:onLine("Adresat wrecza ci 9 srebrnych monet za trud.")
        ok(e:tick());e:arrive();ok(e:tick());eq(b.mode,"stopped")
        local introductionCount=0
        for _,marker in ipairs(markers) do
            if marker.minimumUnits==1 then
                introductionCount=introductionCount+1
                close(marker.seconds,math.max(tempo,0.5))
            else eq(marker.minimumUnits,0,"ordinary callbacks must not inherit the introduction floor") end
        end
        eq(introductionCount,1,"the full successful NPC cycle has exactly one introduction floor marker")
    end
end)
test("manual input pause disconnect and actor changes notify timing cancellation",function()
    for _,kind in ipairs({"manual","pause","disconnect","actor"}) do
        local b,e=fresh();selected(b,e,"Johan Kornwalz");local before=#e.events
        if kind=="manual" then b:onCommand("i") elseif kind=="pause" then b:pause("fixture pause")
        elseif kind=="disconnect" then b:disconnected() else b:identifyActor("NowaPostac") end
        local notified=false
        for i=before+1,#e.events do if e.events[i].kind:match("^cancel:") then notified=true end end
        ok(notified,"timing cancellation notification missing for "..kind);eq(#e:eventsOf("finish"),0)
    end
end)

print("ETA core: "..cases.." scenarios, "..assertions.." assertions passed")
