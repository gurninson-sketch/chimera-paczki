-- Urban recipient search with real native GMCP, NPC, Boty, road, inventory,
-- checkpoints and courier core. All server/map data below are synthetic.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","c100000000000002","c100000000000003","c100000000000004",
    "c100000000000005","c100000000000006","c100000000000007","c100000000000008","c100000000000009"}
local CITY="c100000000000010"
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Polnocna czesc placu","Dawne stanowisko adresata",
    "Boczna ulica","Targ miejski","Alejka za targiem","Trakt poza miastem","Las za murem","Odlaczony port"}
local LINKS={
    [1]={e=2},[2]={w=1,s=3,n=4,e=5},[3]={n=2,e=6},[4]={s=2,e=7},
    [5]={w=2,n=6,e=8},[6]={s=5,w=3,statek=9},[7]={w=4},[8]={w=5},[9]={statek=6},
}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod"}
local worldRooms={}
local missingWorld=false
for index,id in ipairs(IDS) do
    local exits={}
    for command,to in pairs(LINKS[index]) do exits[LONG[command] or command]=IDS[to] end
    worldRooms[id]={id=id,name=NAMES[index],area=index==7 and "Trakt" or "Testowe Miasto",
        area_id=index==7 and "c200000000000010" or CITY,terrain=index==8 and "las" or "miasto",
        indoors=index==1,exits=exits,hidden={}}
end
T.module("test.world.city_courier",function()
    return {name="world",setup=function()
        return {room=function(id) return not missingWorld and worldRooms[id] or nil end,
            terrains=function() return {} end,marks=function() return {} end,gates=function() return {} end,
            version=function() return "city-fixture" end,npcs=function() return {
                {name="Torquato",short="wyniosly bialowlosy mezczyzna",title="Torquato di Assemani, dostojnik",room=IDS[3]},
                {name="Annibale",short="testowy kapitan",title="Annibale Malacresta Lettore, kapitan",room=IDS[4]},
            } end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua",
        "path.lua","postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Testowe Miasto")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area)
        setRoomCoordinates(index,index,0,0);setRoomWeight(index,1)
    end
    for from,links in pairs(LINKS) do
        for command,to in pairs(links) do
            if LONG[command] then setExit(from,to,command) else addSpecialExit(from,to,command) end
        end
    end
    _G.getPath=function(from,to)
        if from==to then speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true end
        local queue,seen,prior={from},{[from]=true},{}
        local head=1
        while queue[head] do
            local room=queue[head];head=head+1
            local commands={};for command in pairs(LINKS[room] or {}) do commands[#commands+1]=command end
            table.sort(commands)
            for _,command in ipairs(commands) do
                local target=LINKS[room][command]
                if not seen[target] then seen[target]=true;prior[target]={from=room,command=command};queue[#queue+1]=target end
            end
        end
        if not seen[to] then return false end
        local reverse,room={},to
        while room~=from do local p=prior[room];reverse[#reverse+1]={room=room,command=p.command};room=p.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for index=#reverse,1,-1 do
            speedWalkDir[#speedWalkDir+1]=reverse[index].command;speedWalkPath[#speedWalkPath+1]=reverse[index].room
            speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function roomInfo(index)
    local r=worldRooms[IDS[index]]
    return {id=r.id,name=r.name,area=r.area,area_id=r.area_id,terrain=r.terrain,indoors=r.indoors and 1 or 0,exits=r.exits}
end
local function count(command)
    local total=0;for _,sent in ipairs(M.sent) do if sent==command then total=total+1 end end;return total
end
local function untilTrue(predicate,limit,why)
    for _=1,math.ceil((limit or 30)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function start(options)
    options=options or {};missingWorld=options.missingWorld==true
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.city_courier","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=1,npcAt=options.npcAt,recipient=options.recipient or "Torquato",moves={},attempts={},pending=0,
        moveDelay=options.moveDelay or 0.1,reward=options.reward~=false,deny=options.deny or 0,holding=false}
    function server:entities()
        local rows={}
        if self.npcAt==self.current then
            rows[#rows+1]={id="city-target",kind="npc",name=self.descriptor and "wyniosly bialowlosy mezczyzna" or self.recipient,
                title=self.recipient=="Torquato" and "Torquato di Assemani, dostojnik" or "Annibale Malacresta Lettore, kapitan",relation="neutral"}
        end
        if self.decoyAt==self.current then
            rows[#rows+1]={id="city-decoy",kind=self.decoyKind or "npc",name="wyniosly bialowlosy mezczyzna",relation="neutral"}
        end
        M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities=rows})
    end
    local wire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command)
        if M.denied~=before then return end
        wire(command,...)
        local target=(LINKS[server.current] or {})[command]
        if target then
            server.pending=server.pending+1;T.eq(1,server.pending,"movement sent before the previous movement acknowledgement")
            local step={from=server.current,to=target,command=command,at=M.now};server.moves[#server.moves+1]=step
            if server.onMoveSent then server:onMoveSent(step) end
            tempTimer(server.moveDelay,function()
                server.pending=server.pending-1;server.current=target
                if server.onArrive then server:onArrive(target) end
                M.packet("Room.Info",roomInfo(target));server:entities()
                M.line(NAMES[target]..".")
            end)
        elseif command=="przedstaw sie" then
            if server.onIntroduce then server:onIntroduce() end
            if server.current==server.npcAt then
                tempTimer(0.05,function()
                    M.line(server.recipient.." przedstawia sie jako:")
                    M.line(server.recipient=="Torquato" and "Torquato di Assemani." or "Annibale Malacresta Lettore.")
                    server.descriptor=false;server:entities()
                end)
            end
        elseif command=="oddaj paczke" then
            server.attempts[#server.attempts+1]={room=server.current,at=M.now,descriptor=server.descriptor==true}
            tempTimer(0.05,function()
                if server.deny>0 then
                    server.deny=server.deny-1
                    if server.onDeny then server:onDeny() end
                    M.line("Adresat nie znajduje sie w tym miejscu.")
                    M.line("Musisz odnalezc Torquato di Assemani i wreczyc mu paczke osobiscie.")
                elseif server.current==server.npcAt then
                    server.holding=false;M.line("Wrecasz paczke adresatowi.")
                    if server.reward then M.line("Adresat wrecza ci 9 srebrnych monet za trud.") end
                else
                    M.line("Adresat nie znajduje sie w tym miejscu.")
                    M.line("Musisz odnalezc Torquato di Assemani i wreczyc mu paczke osobiscie.")
                end
            end)
        elseif command=="otworz swoj plecak" then tempTimer(0.05,function() M.line("Otwierasz skorzany plecak.") end)
        elseif command=="zamknij swoj plecak" then tempTimer(0.05,function() M.line("Zamykasz skorzany plecak.") end)
        elseif command=="wloz paczke do swojego plecaka" then tempTimer(0.05,function()
            M.line("Wkladasz paczke do otwartego skorzanego plecaka.");if server.onStow then server:onStow() end
        end)
        elseif command=="wez paczke z swojego plecaka" then tempTimer(0.05,function()
            M.line("Bierzesz paczke z otwartego skorzanego plecaka.");if server.onTake then server:onTake() end
        end)
        elseif command=="wloz monety do swojego plecaka" then tempTimer(0.05,function()
            M.line("Wkladasz dziewiec srebrnych monet do otwartego skorzanego plecaka.")
        end) end
    end
    local gmcpWire=sendGMCP
    _G.sendGMCP=function(command,...)
        gmcpWire(command,...)
        if command:find('Core.Supports.Add',1,true) and command:find('Chimera.Room.Entities',1,true) then
            tempTimer(0.01,function() server:entities() end)
        end
    end
    record.api.engine.config.autoBackpack=false;record.api.engine.config.refresh=30;record.api.engine:save()
    M.packet("Char.Info",{name="Morrid",id="city-courier"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    M.packet("Room.Info",roomInfo(1));server:entities()
    if options.bags then M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak") end
    return app,app.loader.records.bots.api,record.api.engine,record.api.navigator,server,record.api
end
local function begin(server,recipient)
    local name=recipient or "Torquato di Assemani"
    M.input("/paczki start 1")
    untilTrue(function() return count("przeczytaj tablice")>0 end,15,"board read")
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("1. "..name.." miejscowa 1.70 kg 9 srebrnych monet [x3]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    untilTrue(function() return count("wybierz paczke 1")>0 end,10,"parcel selection")
    server.holding=true;M.line("Bierzesz paczke przeznaczona dla: "..name..".")
end
local function finish(C,bots,app)
    untilTrue(function() return C.stats.delivered==1 end,100,"successful delivery")
    untilTrue(function() return bots.status()==nil end,100,"return to original post office")
    T.eq("stopped",C.mode,M.text());T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    T.eq(0,#app.errors,M.text())
end
local function cityOnly(server)
    for _,step in ipairs(server.moves) do
        T.ok(step.to<=6,"urban search left its confirmed city: "..tostring(step.to))
        T.ok(LONG[step.command],"urban search used a special transition: "..step.command)
    end
end
T.test("a missing known target is found on another mapped city street and only a confirmed gift counts",function()
    local app,bots,C,nav,s,api=start({npcAt=5,reward=false});begin(s)
    untilTrue(function() return #s.attempts==1 end,100,"find recipient beyond the catalogue location")
    T.eq(5,s.attempts[1].room);T.eq(0,C.stats.delivered);T.eq(false,C.job.delivered)
    M.advance(0.1);T.eq(true,C.job.delivered);T.eq(1,C.stats.delivered,"own handover acknowledgement confirms delivery")
    T.eq(true,C.awaitingReward);T.eq(0,C.stats.silver,"handover alone cannot fabricate payment")
    T.eq(0,api.memory.count(),"recipient learning must await both handover and reward")
    M.line("Adresat wrecza ci 9 srebrnych monet za trud.");finish(C,bots,app)
    cityOnly(s);T.eq(1,count("wybierz paczke 1"));T.eq(1,count("oddaj paczke"));T.eq(1,api.memory.count())
    T.eq(IDS[5],api.memory.find("Torquato di Assemani").roomHashes[1])
end)
T.test("a fresh named encounter on the way wins over the old confirmed delivery room",function()
    local app,bots,C,nav,s,api=start({npcAt=2})
    local npc=app.loader.records.npcs.api.find("Torquato")[1]
    T.ok(api.memory.remember({recipient="Torquato di Assemani",roomHash=IDS[3],map=3,verified=true,handover=true,reward=true,
        npc={npcId=npc.id,name=npc.name,short=npc.short,title=npc.title}}))
    begin(s);finish(C,bots,app)
    T.eq(2,s.attempts[1].room)
    for _,step in ipairs(s.moves) do T.ok(step.to~=3,"continued to stale delivery location after seeing the actual recipient") end
    T.eq(IDS[2],api.memory.find("Torquato di Assemani").roomHashes[1]);cityOnly(s)
end)
T.test("the last named observation in the city outranks a different last successful delivery",function()
    local app,bots,C,nav,s,api=start({npcAt=4})
    local npc=app.loader.records.npcs.api.find("Torquato")[1]
    T.ok(api.memory.remember({recipient="Torquato di Assemani",roomHash=IDS[3],map=3,verified=true,handover=true,reward=true,
        npc={npcId=npc.id,name=npc.name,short=npc.short,title=npc.title}}))
    s.current=4;M.packet("Room.Info",roomInfo(4));s:entities()
    s.current=1;M.packet("Room.Info",roomInfo(1));s:entities()
    begin(s);finish(C,bots,app)
    T.eq(4,s.attempts[1].room)
    for _,step in ipairs(s.moves) do T.ok(step.to~=3,"old success took priority over a newer named observation") end
    cityOnly(s)
end)
T.test("an unsuccessful city circuit stays autonomous past inactivity timeout within its search budget",function()
    local app,bots,C,nav,s=start();begin(s);M.advance(220)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#s.attempts);T.ok(nav.inProgress)
    T.ok(#s.moves>4,"city search did not inspect streets beyond old target");cityOnly(s)
    s.npcAt=s.current;s:entities();finish(C,bots,app)
    T.eq(1,count("oddaj paczke"));T.eq(1,count("wybierz paczke 1"))
end)
T.test("recipient departure during parcel withdrawal restarts owned search without a gift in the empty room",function()
    local app,bots,C,nav,s=start({npcAt=3,bags=true})
    local departed
    s.onTake=function(self)
        if not departed then departed=true;self.npcAt=5;self:entities() end
    end
    begin(s);finish(C,bots,app)
    T.ok(departed);T.eq(1,#s.attempts);T.eq(5,s.attempts[1].room)
    T.eq(1,count("wybierz paczke 1"));T.eq(1,count("wloz paczke do swojego plecaka"),"re-search must keep the withdrawn parcel")
    cityOnly(s)
end)
T.test("recipient departure during introduction cancels the delayed gift and resumes city search",function()
    local app,bots,C,nav,s=start({npcAt=3})
    local departed
    s.onIntroduce=function(self)
        if not departed then departed=true;self.npcAt=5;self:entities() end
    end
    begin(s);finish(C,bots,app)
    T.ok(departed);T.eq(1,#s.attempts);T.eq(5,s.attempts[1].room);cityOnly(s)
end)
T.test("two recipient-absent lines invalidate old presence and cause one new search rather than repeated gifts",function()
    local app,bots,C,nav,s=start({npcAt=3,deny=1})
    s.onDeny=function(self) self.npcAt=5 end -- Deliberately retain the old named GMCP row.
    begin(s);finish(C,bots,app)
    T.eq(2,#s.attempts);T.eq(3,s.attempts[1].room);T.eq(5,s.attempts[2].room)
    T.eq(1,count("wybierz paczke 1"));cityOnly(s)
end)
T.test("a lookalike descriptor away from the known destination does not authorize delivery",function()
    local app,bots,C,nav,s=start({npcAt=6});s.decoyAt=4;s.decoyKind="player"
    begin(s);finish(C,bots,app)
    T.eq(1,#s.attempts);T.eq(6,s.attempts[1].room);cityOnly(s)
end)
T.test("a recipient first seen as a descriptor is introduced and freshly identified before a city handover",function()
    local app,bots,C,nav,s=start({npcAt=3});s.descriptor=true
    begin(s);finish(C,bots,app)
    T.ok(count("przedstaw sie")>=1,"unknown recipient was never asked to introduce himself")
    T.eq(1,#s.attempts);T.eq(3,s.attempts[1].room)
    T.eq(false,s.attempts[1].descriptor,"descriptor alone authorized the gift before a fresh named entity appeared")
    cityOnly(s)
end)
T.test("a descriptor at a previously unknown city street can be probed but still needs fresh named identity before the gift",function()
    local app,bots,C,nav,s=start({npcAt=5});s.descriptor=true
    begin(s);finish(C,bots,app)
    T.ok(count("przedstaw sie")>=1,"city search never introduced the candidate on an unknown street")
    T.eq(1,#s.attempts);T.eq(5,s.attempts[1].room)
    T.eq(false,s.attempts[1].descriptor,"unidentified descriptor on a new street authorized the gift")
    cityOnly(s)
end)
T.test("city patrol movement honours ACK and the configured courier step delay",function()
    local app,bots,C,nav,s=start({npcAt=6,moveDelay=0.3});M.input("/paczki tempo 2")
    begin(s);finish(C,bots,app);cityOnly(s)
    T.eq(0,s.pending)
    for index=2,#s.moves do
        T.ok(s.moves[index].at-s.moves[index-1].at>=1.99,"city patrol ignored the configured two-second movement pace")
    end
end)
T.test("a named target in the room being left cannot authorize a handover before the transmitted step settles",function()
    local app,bots,C,nav,s=start({moveDelay=1})
    local observed
    s.onMoveSent=function(self,step)
        if not observed then observed=true;self.npcAt=step.from;self:entities() end
    end
    begin(s);untilTrue(function() return #s.moves==1 end,20,"first owned movement")
    local before=#M.sent;M.advance(0.4)
    T.eq(before,#M.sent,"recipient sighting started parcel actions while movement acknowledgement was pending")
    T.eq(1,s.pending);T.eq(0,#s.attempts);T.eq(0,count("przedstaw sie"))
    finish(C,bots,app);T.eq(1,s.attempts[1].room);T.eq(1,#s.attempts);cityOnly(s)
end)
T.test("an NPC attack during urban patrol continues the owned course and does not record a new hazard",function()
    local app,bots,C,nav,s=start({npcAt=6})
    local attacked
    s.onMoveSent=function(self)
        if not attacked and #self.moves>=3 then
            attacked=true
            app.bus:emit("chimera.attacked",{name="wielki uzbrojony ork",player=false})
        end
    end
    s.onArrive=function(self)
        if attacked then tempTimer(0.02,function()
            M.packet("Chimera.Combat.State",{room=IDS[self.current],primary="",relations={},covers={}})
            M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
        end) end
    end
    begin(s);finish(C,bots,app);T.ok(attacked,"fixture never reached an urban patrol leg")
    T.contains(M.text(),"Atak NPC: kontynuuje")
    T.not_contains(M.text(),"Omijam lokacje")
    local hazards=app.storage:get_state("kurier_paczki","niebezpieczne_lokacje")
    T.ok(not hazards or not hazards.rooms or next(hazards.rooms)==nil)
    cityOnly(s)
end)
T.test("an NPC attack interrupts the thirty-second city idle immediately even if the recipient appears in the attack room",function()
    local app,bots,C,nav,s=start();begin(s)
    untilTrue(function() return nav.phase()=="searching_city" end,100,"completed city round waiting interval")
    T.eq(0,s.pending)
    local beforeMoves,attackRoom=#s.moves,s.current
    app.bus:emit("chimera.attacked",{name="wielki uzbrojony ork",player=false})
    -- A simultaneous positive recipient row must not keep the courier in
    -- the attack room preparing a handover instead of taking its next step.
    s.npcAt=attackRoom;s:entities();M.advance(0.11)
    T.ok(#s.moves>beforeMoves,"NPC attack left the courier in the city idle interval")
    T.eq(attackRoom,s.moves[beforeMoves+1].from)
    T.eq(0,#s.attempts);T.eq(0,count("przedstaw sie"))
    T.eq("running",C.mode,M.text());T.ok(bots.status());cityOnly(s)
    M.input("/bot stop");M.advance(0.2)
    local after=#M.sent;M.advance(45);T.eq(after,#M.sent,"STOP after interrupted city idle left a live retry timer")
    T.eq(0,#app.errors,M.text())
end)
T.test("an NPC attack cancels the identity probe wait and takes an ordinary city step within a tenth of a second",function()
    local app,bots,C,nav,s=start({npcAt=3});s.descriptor=true
    s.onIntroduce=function(self) self.npcAt=nil end -- No name reply; retain cached descriptor during the probe wait.
    begin(s);untilTrue(function() return count("przedstaw sie")>=1 end,40,"identity probe")
    T.eq(0,s.pending)
    local beforeMoves,attackRoom=#s.moves,s.current
    app.bus:emit("chimera.attacked",{name="wielki uzbrojony ork",player=false});M.advance(0.11)
    T.ok(#s.moves>beforeMoves,"NPC attack waited for the identity probe timeout")
    T.eq(attackRoom,s.moves[beforeMoves+1].from);T.eq(0,#s.attempts)
    T.eq("running",C.mode,M.text());T.ok(bots.status());cityOnly(s)
    M.input("/bot stop");M.advance(0.2)
    local after=#M.sent;M.advance(45);T.eq(after,#M.sent,"STOP after interrupted city probe left a live callback")
    T.eq(0,#app.errors,M.text())
end)
T.test("manual STOP and disconnect cancel a city search with no late movement or handover",function()
    for _,kind in ipairs({"stop","disconnect"}) do
        local app,bots,C,nav,s=start();begin(s)
        untilTrue(function() return #s.moves>=3 end,30,"active patrol")
        -- Settle the currently transmitted step before checking for late sends.
        M.advance(0.4)
        if kind=="stop" then M.input("/bot stop") else M.packet("Core.Goodbye",{}) end
        local before=#M.sent;s.npcAt=s.current;s:entities();M.advance(80)
        T.eq(before,#M.sent,kind..": late autonomous command after cancellation")
        T.eq(0,C.stats.delivered);T.eq(nil,bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
    end
end)
T.test("periodic captain keeps waiting at the known berth instead of patrolling the city",function()
    local app,bots,C,nav,s=start({recipient="Annibale"});begin(s,"Annibale Malacresta Lettore")
    untilTrue(function() return C.phase=="waitingNpc" end,40,"captain stationary wait")
    local before=#s.moves;M.advance(240);T.eq(before,#s.moves);T.eq(4,s.current);T.eq(0,#s.attempts)
    s.npcAt=4;s:entities();finish(C,bots,app);T.eq(4,s.attempts[1].room)
end)
T.test("without authoritative city metadata the courier never broadens search to arbitrary streets",function()
    local app,bots,C,nav,s=start({missingWorld=true});begin(s);M.advance(20)
    for _,step in ipairs(s.moves) do T.ok(step.to==2 or step.to==3,"missing metadata caused unbounded city exploration") end
    T.eq(0,#s.attempts);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
