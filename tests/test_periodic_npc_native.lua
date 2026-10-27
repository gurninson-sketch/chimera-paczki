-- Periodic captain integration with actual native GMCP, NPC catalogue,
-- Boty and durable courier checkpoints. Geometry and the NPC catalogue row
-- are synthetic; Annibale full name and the Urbimo port hash are verified
-- separately and this fixture does not assert the captain is always there.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local ROOT=arg[0]:gsub("\\","/"):match("^(.*)/tests/test_periodic_npc_native%.lua$") or ".."
local noCatalogue=false
local IDS={"907327356ecc2f87","a000000000000002","945da22478958071","a000000000000004","200aff4d957642cd"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Na kamiennym molo","Skrzyzowanie","Poczta"}
local LINKS={ [1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,e=5},[5]={w=4} }
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod"}
local worldRooms={}
for i,id in ipairs(IDS) do
    local exits={}
    for cmd,target in pairs(LINKS[i]) do exits[LONG[cmd] or cmd]=IDS[target] end
    worldRooms[id]={id=id,name=NAMES[i],area="Test KZ",area_id="a000",indoors=true,exits=exits,hidden={}}
end
T.module("test.world.courier",function()
    return {name="world",setup=function()
        return {room=function(id) return worldRooms[id] end,terrains=function() return {} end,
            marks=function() return {} end,gates=function() return {} end,version=function() return "test-courier" end,
            npcs=function() if noCatalogue then return {} end;return {
                {name="Annibale",short="testowy kapitan",title="Annibale Malacresta Lettore, testowy kapitan",room=IDS[3]},
            } end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua","scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua","postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read(ROOT.."/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Test KZ")
    for i,id in ipairs(IDS) do addRoom(i);setRoomIDbyHash(i,id);setRoomName(i,NAMES[i]);setRoomArea(i,area);setRoomCoordinates(i,i,0,0) end
    for from,links in pairs(LINKS) do
        for cmd,to in pairs(links) do
            if LONG[cmd] then setExit(from,to,cmd) else addSpecialExit(from,to,cmd) end
        end
    end
    -- Mudlet owns path computation; mirror it with BFS on the tiny fixture.
    _G.getPath=function(from,to)
        if from==to then speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true end
        local queue,seen,prior={from},{[from]=true},{}
        local head=1
        while queue[head] do
            local id=queue[head];head=head+1
            for cmd,target in pairs(LINKS[id] or {}) do if not seen[target] then
                seen[target]=true;prior[target]={from=id,cmd=cmd};queue[#queue+1]=target
            end end
        end
        if not seen[to] then return false end
        local rev,id={},to
        while id~=from do local p=prior[id];rev[#rev+1]={room=id,cmd=p.cmd};id=p.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for i=#rev,1,-1 do
            speedWalkDir[#speedWalkDir+1]=rev[i].cmd;speedWalkPath[#speedWalkPath+1]=rev[i].room;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function info(i)
    local r=worldRooms[IDS[i]]
    return {id=r.id,name=r.name,area=r.area,area_id=r.area_id,indoors=1,exits=r.exits}
end
local function start(showNpc,recipient,roomOnly)
    noCatalogue=roomOnly==true
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.courier","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=1,showNpc=showNpc==true,recipient=recipient or "Annibale"}
    local wire=send
    _G.send=function(command,...)
        local before=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=before then return end
        wire(command,...)
        local to=(LINKS[server.current] or {})[command]
        if to then tempTimer(0.1,function()
            server.current=to
            M.packet("Room.Info",info(to))
            -- GMCP precedes the visible description, as it can in Mudlet.
            tempTimer(0.05,function()
                M.line(NAMES[to]..".")
                if to==3 then M.line("Jest tutaj jedno widoczne wyjscie: poludnie.") end
            end)
            local rows={}
            if to==3 and server.showNpc then
                local visible=server.recipient=="Olaff" and "sympatyczny pucolowaty mezczyzna" or "Annibale"
                rows={{id="e1-recipient",kind="npc",name=visible,relation="neutral"}}
            end
            M.packet("Chimera.Room.Entities",{room=IDS[to],entities=rows})
        end) end
    end
    M.packet("Room.Info",info(1));M.packet("Chimera.Room.Entities",{room=IDS[1],entities={}})
    -- Legacy route scenarios explicitly disable automatic backpack discovery.
    -- Dedicated inventory suites cover the production default separately.
    record.api.engine.config.autoBackpack=false;record.api.engine:save()
    M.packet("Char.Info",{name="Testowicz",id="e1-courier"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    if roomOnly then T.ok(record.api.memory.remember({recipient="Annibale Malacresta Lettore",roomHash=IDS[3],map=3,verified=true,handover=true,reward=true,postal=false})) end
    return app,app.loader.records.bots.api,record.api.engine,record.api.navigator,server
end
local function nextSend(limit)
    local before=#M.sent
    for _=1,math.ceil((limit or 12)/0.05) do M.advance(0.05);if #M.sent>before then return M.sent[#M.sent] end end
    error("no next send: "..M.text())
end
local function inputSend(command)
    local before=#M.sent
    M.input(command)
    if #M.sent>before then return M.sent[before+1] end
    return nextSend()
end
local function position(server,index)
    server.current=index
    M.packet("Room.Info",info(index));M.packet("Chimera.Room.Entities",{room=IDS[index],entities={}})
end
local function board(row)
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    if row then M.line(row) end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
end
local function begin(row,command)
    M.input(command or "/paczki start 1")
    T.eq("przeczytaj tablice",nextSend())
    board(row)
    T.eq("wybierz paczke 1",nextSend())
end
local NPC_ROW="1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x1]"
local function deliverNpcAndReturn()
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend())
end
local CAPTAIN="Annibale Malacresta Lettore"
local ROW="1. "..CAPTAIN.." miejscowa 1.70 kg 9 srebrnych monet [x3]"
local MOVES={n=true,s=true,e=true,w=true,u=true,d=true,ne=true,nw=true,se=true,sw=true,poczta=true,wyjscie=true}
local function captain(count)
    local list={}
    for index=1,(count or 1) do list[#list+1]={id="e1-captain-"..index,name="Annibale",kind="npc",relation="neutral"} end
    M.packet("Chimera.Room.Entities",{room=IDS[3],entities=list})
end
local function pulse(fatigue,hp) M.packet("Char.Vitals",{hp=hp or 100,mana=100,fatigue=fatigue or 10}) end
local function countCommand(command)
    local count=0;for _,sent in ipairs(M.sent) do if sent==command then count=count+1 end end;return count
end
local function noJourneyOrHandoverSince(before)
    for index=before+1,#M.sent do
        T.ok(not MOVES[M.sent[index]],"waiting captain caused movement: "..M.sent[index])
        T.ok(M.sent[index]~="oddaj paczke" and M.sent[index]~="przedstaw sie","an absent captain caused a handover attempt")
    end
end
local function waitAtDock(C)
    begin(ROW);M.line("Bierzesz paczke przeznaczona dla: "..CAPTAIN..".")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend());M.advance(2)
    T.eq(3,getRoomIDbyHash(IDS[3]));T.eq(IDS[3],gmcp.Room.Info.id)
    T.eq("waitingNpc",C.phase,M.text());T.eq(false,C.job.delivered)
end
local function finishDelivery(C,bots)
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status())
end
T.test("an absent periodic captain waits beyond normal timeouts at the fixed jetty and hands over only on fresh named arrival",function()
    local app,bots,C,nav=start();waitAtDock(C)
    T.eq(true,C.job.route.periodic);local before=#M.sent
    M.advance(400);noJourneyOrHandoverSince(before)
    T.eq(3,app.loader.records.mapper.api.current_room());T.eq("waitingNpc",C.phase)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,C.stats.delivered)
    captain();captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    T.eq(1,countCommand("oddaj paczke"));T.eq(0,C.stats.delivered)
    finishDelivery(C,bots);T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    T.eq(1,countCommand("oddaj paczke"));T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("a captain who vanishes during introduction returns the job to waiting without issuing oddaj",function()
    local app,bots,C,nav=start();waitAtDock(C)
    captain();T.eq("przedstaw sie",nextSend());captain(0)
    local before=#M.sent;M.advance(2)
    noJourneyOrHandoverSince(before);T.eq(0,countCommand("oddaj paczke"))
    T.eq("waitingNpc",C.phase,M.text());T.ok(bots.status());T.eq(false,C.job.delivered)
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    finishDelivery(C,bots);T.eq(1,C.stats.delivered);T.eq(1,countCommand("oddaj paczke"));T.eq(0,#app.errors,M.text())
end)
T.test("an explicit recipient-absent reply invalidates cached presence and waits for a new arrival before retrying",function()
    local app,bots,C,nav=start();waitAtDock(C)
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    -- Keep the old named GMCP snapshot deliberately: the server's denial
    -- must invalidate it rather than immediately retrying against it.
    M.line("Adresat nie znajduje sie w tym miejscu.")
    M.line("Musisz odnalezc "..CAPTAIN.." i wreczyc mu paczke osobiscie.")
    local before=#M.sent;M.advance(2);noJourneyOrHandoverSince(before)
    T.eq("waitingNpc",C.phase,M.text());T.ok(bots.status());T.eq(false,C.awaitingDelivery)
    T.eq(false,C.job.delivered);T.eq(0,C.stats.delivered);T.eq(1,countCommand("oddaj paczke"))
    captain(0);M.advance(200);noJourneyOrHandoverSince(before);T.eq("waitingNpc",C.phase)
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    T.eq(2,countCommand("oddaj paczke"));finishDelivery(C,bots)
    T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.test("ambiguous named captain entities cannot authorize a handover",function()
    local app,bots,C,nav=start();waitAtDock(C)
    captain(2);local before=#M.sent;M.advance(2)
    noJourneyOrHandoverSince(before);T.eq("waitingNpc",C.phase,M.text());T.ok(bots.status())
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    finishDelivery(C,bots);T.eq(1,C.stats.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("manual stop rest and safety interruptions cancel the stationary waiter without late handover commands",function()
    for _,kind in ipairs({"stop","rest","hp","combat","teleport","disconnect","reload"}) do
        local app,bots,C,nav,server=start();waitAtDock(C)
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="rest" then pulse(85)
        elseif kind=="hp" then pulse(10,20)
        elseif kind=="combat" then app.bus:emit("chimera.fight.started",{room=IDS[3],enemies={"ork"}})
        elseif kind=="teleport" then position(server,4)
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        else T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text());C=app.loader.records.kurier_paczki.api.engine;nav=app.loader.records.kurier_paczki.api.navigator end
        local before=#M.sent
        position(server,3);captain();M.advance(2)
        noJourneyOrHandoverSince(before)
        if kind=="hp" or kind=="combat" then
            for index=before+1,#M.sent do T.eq("stan",M.sent[index],"safety recovery may only poll fresh vitals") end
        else T.eq(before,#M.sent,kind..": "..M.text()) end
        T.eq(0,C.stats.delivered);T.eq(false,nav.inProgress)
        if kind=="rest" then T.eq("resting",C.mode,M.text());T.ok(bots.status())
        elseif kind=="hp" or kind=="combat" then T.eq("recovering",C.mode,M.text());T.ok(bots.status())
        else T.eq(nil,bots.status());T.ok(C.mode=="paused" or C.mode=="stopped",M.text()) end
        T.eq(0,#app.errors,kind..": "..M.text())
    end
end)
T.test("a saved captain job reconnects and resumes waiting at the jetty without manual parcel reconstruction",function()
    local app,bots,C,nav,server=start();C.stats.delivered=2;C.stats.silver=18;waitAtDock(C)
    M.packet("Core.Goodbye",{})
    local saved=assert(app.loader.records.kurier_paczki.api.checkpoint.get("Testowicz"))
    T.eq("annibale malacresta lettore",C.norm(saved.job.name));T.eq(false,saved.flags.awaitingDelivery)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    C=app.loader.records.kurier_paczki.api.engine;nav=app.loader.records.kurier_paczki.api.navigator
    local before=#M.sent;M.line("Witaj, Testowiczu. Podaj haslo...")
    M.packet("Char.Info",{name="Testowicz",id="e1-courier"});position(server,3);captain(0);pulse(10)
    T.ok(C.job);T.eq(2,C.stats.delivered);T.eq(3,C.stopAt);T.eq(nil,bots.status())
    M.input("/paczki wznow");M.advance(240)
    noJourneyOrHandoverSince(before);T.eq("waitingNpc",C.phase,M.text());T.ok(bots.status())
    T.eq(IDS[1],C.source.id);T.eq(2,C.stats.delivered);T.eq(3,C.stopAt)
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    finishDelivery(C,bots);T.eq(3,C.stats.delivered);T.eq(27,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
local function anonymousCaptain(kind,room)
    M.packet("Chimera.Room.Entities",{room=room or IDS[3],entities={
        {id="new-captain",name="wysoki kruczowlosy mezczyzna",kind=kind or "npc",relation="neutral"}}})
end
T.test("room-only shared Annibale address introduces an anonymous captain at the jetty and waits for verified identity",function()
    local app,bots,C,nav=start(false,nil,true);waitAtDock(C)
    T.eq(true,C.job.route.roomOnlyIdentity);T.eq(nil,C.job.route.npcId)
    local before=#M.sent;M.advance(20);noJourneyOrHandoverSince(before)
    anonymousCaptain("player");M.advance(.2);T.eq(0,countCommand("przedstaw sie"))
    anonymousCaptain("npc",IDS[2]);M.advance(.2);T.eq(0,countCommand("przedstaw sie"))
    anonymousCaptain();T.eq(1,countCommand("przedstaw sie"))
    anonymousCaptain();M.advance(2);T.eq(0,countCommand("oddaj paczke"));T.eq(1,countCommand("przedstaw sie"))
    M.line("Wysoki kruczowlosy mezczyzna przedstawia sie jako:")
    M.line("Annibale Malacresta Lettore, kapitan, czlowiek.")
    captain();T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    finishDelivery(C,bots);T.eq(1,C.stats.delivered);T.eq(1,countCommand("oddaj paczke"));T.eq(0,#app.errors,M.text())
end)
T.test("a room-only captain probe cancels on STOP and cannot give to an unrelated NPC",function()
    local app,bots,C,nav=start(false,nil,true);waitAtDock(C)
    anonymousCaptain();T.eq(1,countCommand("przedstaw sie"))
    M.line("Wysoki kruczowlosy mezczyzna przedstawia sie jako:")
    M.line("Antonio Inny, marynarz, czlowiek.")
    M.packet("Chimera.Room.Entities",{room=IDS[3],entities={{id="other",name="Antonio",kind="npc",relation="neutral"}}})
    M.advance(15);T.eq(0,countCommand("oddaj paczke"));T.eq("waitingNpc",C.phase)
    M.input("/bot stop");local before=#M.sent;captain();M.advance(20)
    T.eq(before,#M.sent);T.eq(0,C.stats.delivered);T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("room-only berth probes a newly arriving captain even when other NPCs remain, without flooding introductions",function()
    local app,bots,C,nav=start(false,nil,true);waitAtDock(C)
    local other={id="dock-worker",name="stary marynarz",kind="npc",relation="neutral"}
    M.packet("Chimera.Room.Entities",{room=IDS[3],entities={other}})
    T.eq(1,countCommand("przedstaw sie"))
    local newcomer={id="new-captain",name="wysoki kruczowlosy mezczyzna",kind="npc",relation="neutral"}
    for _=1,10 do M.packet("Chimera.Room.Entities",{room=IDS[3],entities={other,newcomer}}) end
    M.advance(5);T.eq(1,countCommand("przedstaw sie"));T.eq(0,countCommand("oddaj paczke"))
    M.advance(16);T.eq(2,countCommand("przedstaw sie"));T.eq(0,countCommand("oddaj paczke"))
    M.advance(30);T.eq(2,countCommand("przedstaw sie"))
    M.input("/bot stop");local before=#M.sent;captain();M.advance(20)
    T.eq(before,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.run()
