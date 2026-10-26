-- Actual beta.13 loader, Context, Bus, GMCP, mapper, Boty and courier.
-- Geometry/pathfinding/server are deliberately synthetic: eight official
-- hashes exercise the verified gate/ferry protocol, not the real road length.
-- Run from chimera-main: texlua ../chimera-native/tests/test_gate_ferry_native.lua
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"6f2c03461c2f1438","2eee479b18b648c6","b9f87182bbcdc726","894039a1680ca034",
    "20016d960316ba51","060d3ff10fbd46b5","38e60eb65905fa7b","e202c7893bf8fb55"}
local NAMES={"Poczta","Szeroki gosciniec","Brama poludniowa","Brzeg rzeki","Brzeg rzeki",
    "Zaniedbany trakt","Zachodnia brama miasta","Poczta w Quenelles"}
local LINKS={[1]={nw=2},[2]={se=1,n=3},[3]={s=2,n=4},[4]={s=3},
    [5]={e=6},[6]={w=5,e=7},[7]={w=6,e=8},[8]={w=7}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",nw="polnocny-zachod",se="poludniowy-wschod"}
local BOAT="f000000000000001"
local worldRooms={}
for i,id in ipairs(IDS) do
    local exits={}
    for cmd,target in pairs(LINKS[i]) do exits[LONG[cmd]]=IDS[target] end
    worldRooms[id]={id=id,name=NAMES[i],area="Synthetic gate/ferry fixture",area_id="f000",indoors=true,exits=exits,hidden={}}
end
T.module("test.world.gateferry",function()
    return {name="world",setup=function()
        return {room=function(id)return worldRooms[id] end,terrains=function()return{}end,marks=function()return{}end,
            npcs=function()return{}end,version=function()return"test-gate-ferry"end,gates=function()return{
                [IDS[2]]={command="uderz w brame",wait=5},[IDS[3]]={command="uderz w brame",wait=5},
            }end}
    end}
end)
local function read(path)local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,file in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua","postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..file,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..file))
    end
    local area=M.empty_map("Synthetic gate/ferry fixture")
    for i,id in ipairs(IDS)do addRoom(i);setRoomIDbyHash(i,id);setRoomName(i,NAMES[i]);setRoomArea(i,area);setRoomCoordinates(i,i,0,0)end
    for from,links in pairs(LINKS)do for cmd,to in pairs(links)do setExit(from,to,cmd)end end
    -- Both riverbanks exist, but the Mudlet graph has NO edge across water.
    _G.getPath=function(from,to)
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        if from==to then return true end
        local queue,seen,prior={from},{[from]=true},{}
        local at=1
        while queue[at]do
            local room=queue[at];at=at+1
            for cmd,nextRoom in pairs(LINKS[room]or{})do if not seen[nextRoom]then
                seen[nextRoom]=true;prior[nextRoom]={from=room,cmd=cmd};queue[#queue+1]=nextRoom
            end end
        end
        if not seen[to]then return false end
        local reversed,cursor={},to
        while cursor~=from do local previous=prior[cursor];reversed[#reversed+1]={room=cursor,cmd=previous.cmd};cursor=previous.from end
        for i=#reversed,1,-1 do local step=reversed[i]
            speedWalkDir[#speedWalkDir+1]=step.cmd;speedWalkPath[#speedWalkPath+1]=step.room;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function board(name)
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    if name then M.line("1. "..name.." miedzymiastowa 2.00 kg 4 zlote, 5 srebrnych i 6 miedzianych monet [x1]")end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
end
local function start(origin,settings)
    settings=settings or {}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.gateferry","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events","chimera.numpad","chimera.bots"},nil,function()
            prepare()
            if settings.mapBoat then
                addRoom(9);setRoomIDbyHash(9,BOAT);setRoomName(9,"Na pokladzie promu");setRoomArea(9,1);setRoomCoordinates(9,9,0,0)
            end
        end)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=origin or 1,origin=origin or 1,bogenOpen=false,quenellesOpen=false,events={},deliveries=0,
        boardReads={},movement={},gateStrikes=0,boatEntries=0,boatLeaves=0}
    local function info(i)
        if i==0 then return{id=BOAT,name="Na pokladzie promu",area="Grismerie",area_id="f001",indoors=0,exits={}}end
        local room=worldRooms[IDS[i]];local exits={}
        for key,value in pairs(room.exits)do exits[key]=value end
        -- A closed Bogenhafen gate hides its crossing in live GMCP.
        if not server.bogenOpen then if i==2 then exits.polnoc=nil elseif i==3 then exits.poludnie=nil end end
        return{id=room.id,name=room.name,area=room.area,area_id=room.area_id,indoors=1,exits=exits}
    end
    local function snapshot(i)
        M.packet("Room.Info",info(i));M.packet("Chimera.Room.Entities",{room=i==0 and BOAT or IDS[i],entities={}})
        if i==0 then M.line("Na pokladzie promu.")
        else M.line(NAMES[i]..".")end
    end
    server.snapshot=snapshot
    local wire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command)
        if before~=M.denied then return end
        wire(command,...);server.events[#server.events+1]={cmd=command,at=M.now,current=server.current}
        if command=="zerknij"then tempTimer(0.02,function()
            M.line(NAMES[server.current]..".")
            if server.current==1 then M.line("Jest tutaj jedno widoczne wyjscie: polnocny-zachod.")end
        end);return end
        if command=="przeczytaj tablice"then
            server.boardReads[#server.boardReads+1]=server.current
            tempTimer(0.02,function()
                if server.current==server.origin and server.deliveries==0 then board(server.current==1 and "Poczta w Quenelles"or"Poczta w Nuln")
                else board()end
            end);return
        end
        if command=="wybierz paczke 1"then
            server.package=server.current==1 and 8 or 1
            tempTimer(0.02,function()M.line("Bierzesz paczke przeznaczona dla: "..(server.package==8 and"Poczta w Quenelles"or"Poczta w Nuln")..".")end);return
        end
        if command=="oddaj paczke"then
            tempTimer(0.02,function()
                if server.package==server.current then
                    server.deliveries=server.deliveries+1;server.package=nil
                    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
                    M.line("Urzednik wyplaca ci 4 zlote, 5 srebrnych i 6 miedzianych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.")end
            end);return
        end
        if command=="uderz w brame"then
            server.gateStrikes=server.gateStrikes+1
            if server.bogenOpen then tempTimer(0.02,function()M.line("Alez brama jest przeciez otwarta!")end)
            else tempTimer(settings.gateDelay or 2,function()
                server.bogenOpen=true;server.gateOpenedAt=M.now
                M.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.")
                -- Do not refresh same-room GMCP here: crossing must use its
                -- captured map step even while live exits are still stale.
            end)end
            return
        end
        if command=="uderz we wrota"then
            server.gateStrikes=server.gateStrikes+1
            tempTimer(1,function()server.quenellesOpen=true;M.line("Z glosnym trzaskiem wrota zostaja otwarte.")end);return
        end
        if command=="wsiadz na statek"or command=="wejdz na prom"then
            T.ok(server.current==4 or server.current==5,"boarding outside a known bank")
            server.boatFrom=server.current;server.boatTo=server.current==4 and 5 or 4;server.boatEntries=server.boatEntries+1
            tempTimer(settings.boardDelay or 0.05,function()
                server.current=0;M.line("Wskakujesz na poklad promu.");snapshot(0)
            end)
            tempTimer((settings.boardDelay or 0.05)+0.25,function()M.line("Prom powoli odbija od brzegu.")end)
            tempTimer((settings.boardDelay or 0.05)+(settings.sailDelay or 1.95),function()M.line("Prom powoli przybija do brzegu.")end)
            return
        end
        if command=="zejdz na brzeg"then
            T.eq(0,server.current);server.boatLeaves=server.boatLeaves+1
            tempTimer(settings.landDelay or 0.05,function()
                server.current=settings.wrongBank and server.boatFrom or server.boatTo
                M.line("Schodzisz z pokladu promu na brzeg.");snapshot(server.current)
            end);return
        end
        local to=(LINKS[server.current]or{})[command]
        if to then
            if (server.current==2 and to==3)or(server.current==3 and to==2)then
                if not server.bogenOpen then server.prematureGateMove=true;tempTimer(0.02,function()M.line("Nie widzisz zadnego wyjscia prowadzacego na polnoc.")end);return end
            end
            if (server.current==6 and to==7)or(server.current==7 and to==6)then
                if not server.quenellesOpen then tempTimer(0.02,function()M.line("Zelazne wrota sa zamkniete na zamek!")end);return end
            end
            server.movement[#server.movement+1]={from=server.current,to=to,at=M.now}
            tempTimer(0.05,function()server.current=to;snapshot(to)end)
        end
    end
    snapshot(server.current)
    local C=record.api.engine;C.config.roam=false
    -- Legacy route scenarios explicitly disable automatic backpack discovery.
    -- Dedicated inventory suites cover the production default separately.
    record.api.engine.config.autoBackpack=false;record.api.engine:save()
    return app,app.loader.records.bots.api,C,record.api.navigator,server
end
local function waitFor(check,seconds)
    for _=1,math.ceil((seconds or 30)/0.05)do if check()then return end;M.advance(0.05)end
    error("condition timeout:\n"..M.text().."\nSends:"..table.concat(M.sent," | "))
end
local function verify(app,bots,C,server,destination)
    T.eq(destination,server.current,M.text());T.eq(1,server.deliveries);T.eq(1,C.stats.delivered)
    T.eq(4,C.stats.gold);T.eq(5,C.stats.silver);T.eq(6,C.stats.copper)
    T.eq(nil,bots.status());T.eq("stopped",C.mode,M.text());T.eq(IDS[destination],C.source.id)
    T.eq(nil,C.job);T.eq(1,server.boatEntries);T.eq(1,server.boatLeaves)
    T.ok(not server.prematureGateMove,"a move was sent before gate opening acknowledgement")
    T.not_contains(M.text(),"Reczna komenda");T.not_contains(M.text(),"Brak potwierdzenia")
    T.eq(0,#app.errors,M.text())
end

T.test("Nuln to Quenelles owns delayed gate, hidden exit, ferry and locked wrota handshakes",function()
    local app,bots,C,nav,server=start(1)
    M.input("/paczki start 1")
    waitFor(function()return C.mode=="stopped"and C.stats.delivered==1 end)
    verify(app,bots,C,server,8)
    T.eq(2,server.gateStrikes,"one Bogenhafen opener and one Quenelles opener")
    local gateMove
    for _,step in ipairs(server.movement)do if step.from==2 and step.to==3 then gateMove=step end end
    T.ok(gateMove and gateMove.at>=server.gateOpenedAt,"crossing preceded the delayed acknowledgement")
    T.eq(false,nav.inProgress)
end)
T.test("postal chaining reads the destination board without returning to the old office",function()
    local app,bots,C,nav,server=start(1)
    M.input("/bot paczki")
    waitFor(function()return C.stats.delivered==1 and C.phase=="waiting"end)
    T.eq(8,server.current);T.eq(IDS[8],C.source.id);T.eq(8,server.boardReads[#server.boardReads])
    T.eq(1,server.boatEntries);T.eq(1,server.boatLeaves);T.ok(bots.status())
    T.eq(false,nav.inProgress);M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("Quenelles to Nuln uses the verified reverse ferry and destination office",function()
    local app,bots,C,nav,server=start(8)
    M.input("/paczki start 1")
    waitFor(function()return C.mode=="stopped"and C.stats.delivered==1 end)
    verify(app,bots,C,server,1)
    local boardCommand
    for _,event in ipairs(server.events)do if event.cmd=="wejdz na prom"then boardCommand=event end end
    T.ok(boardCommand,"reverse route did not use its verified boarding command");T.eq(false,nav.inProgress)
end)
T.test("STOP during gate wait rejects later opening responses without movement",function()
    local app,bots,C,nav,server=start(1,{gateDelay=4})
    M.input("/bot paczki")
    waitFor(function()return server.gateStrikes==1 end)
    T.eq(2,server.current);local sent=#M.sent
    M.input("/bot stop");M.advance(8)
    T.eq(sent,#M.sent);T.eq(2,server.current);T.eq(0,C.stats.delivered)
    T.eq(nil,bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("STOP aboard the ferry never sends a delayed disembark command",function()
    local app,bots,C,nav,server=start(1,{sailDelay=4})
    M.input("/bot paczki")
    waitFor(function()return server.current==0 end)
    local sent=#M.sent;M.input("/bot stop");M.advance(8)
    T.eq(sent,#M.sent);T.eq(0,server.boatLeaves);T.eq(0,C.stats.delivered)
    T.eq(nil,bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("wrong ferry bank cannot confirm a parcel delivery",function()
    local app,bots,C,nav,server=start(1,{wrongBank=true})
    M.input("/bot paczki")
    waitFor(function()return server.boatLeaves==1 end);M.advance(1)
    T.eq(0,server.deliveries);T.eq(0,C.stats.delivered);T.eq(4,server.current)
    T.eq(nil,bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("native plugin reload during gate wait removes owned listeners and future sends",function()
    local app,bots,C,nav,server=start(1,{gateDelay=4})
    M.input("/bot paczki");waitFor(function()return server.gateStrikes==1 end)
    local sent,aliases,triggers=#M.sent,M.count("aliases"),M.count("triggers")
    local result=app.loader:reload({"kurier_paczki"});T.ok(result~=false,M.text())
    M.advance(8)
    local fresh=app.loader.records.kurier_paczki.api.engine
    T.eq(sent,#M.sent);T.eq(2,server.current);T.eq("stopped",fresh.mode)
    T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(aliases,M.count("aliases"));T.eq(triggers,M.count("triggers"));T.eq(0,#app.errors,M.text())
end)
T.test("resume aboard a mapped ferry uses the remembered destination bank for planning",function()
    local app,bots,C,nav,server=start(1,{sailDelay=4,mapBoat=true})
    M.input("/bot paczki");waitFor(function()return server.current==0 end)
    M.advance(0.4) -- a verified departure has occurred; arrival is still pending
    T.eq(9,app.loader.records.mapper.api.current_room())
    M.input("/bot stop");T.eq(nil,bots.status());T.eq(0,server.boatLeaves)
    M.input("/paczki wznow")
    waitFor(function()return server.deliveries==1 end)
    T.eq(8,server.current);T.eq(1,server.boatEntries);T.eq(1,server.boatLeaves)
    T.eq(1,C.stats.delivered);T.not_contains(M.text(),"Nawigacja:")
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
local function vitals(fatigue)
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=fatigue})
end
T.test("fatigue before a delayed boarding packet waits for that packet before automatic recovery",function()
    local app,bots,C,nav,server=start(1,{boardDelay=2,mapBoat=true})
    vitals(10);M.input("/paczki start 1")
    waitFor(function()return server.boatEntries==1 end)
    vitals(85);T.eq("resting",C.mode);T.ok(bots.status());vitals(20)
    local before=#M.sent;M.advance(1.5)
    T.eq("resting",C.mode);T.ok(bots.status());T.eq(before,#M.sent,"low fatigue cannot resend pending boarding")
    waitFor(function()return C.stats.delivered==1 and C.mode=="stopped" end)
    verify(app,bots,C,server,8)
end)
T.test("fatigue after leaving the ferry waits for the exact delayed bank before automatic recovery",function()
    local app,bots,C,nav,server=start(1,{landDelay=2})
    vitals(10);M.input("/paczki start 1")
    waitFor(function()return server.boatLeaves==1 end)
    vitals(85);vitals(20);local before=#M.sent;M.advance(1.5)
    T.eq("resting",C.mode);T.ok(bots.status());T.eq(before,#M.sent,"low fatigue cannot repeat leaving or move before acknowledgement")
    waitFor(function()return C.stats.delivered==1 and C.mode=="stopped" end)
    verify(app,bots,C,server,8)
end)
T.test("a delayed wrong bank during rest stops native Boty and never resumes on fresh recovery",function()
    local app,bots,C,nav,server=start(1,{landDelay=2,wrongBank=true})
    vitals(10);M.input("/paczki start 1")
    waitFor(function()return server.boatLeaves==1 end)
    vitals(85);vitals(20);local before=#M.sent;M.advance(2.2)
    T.eq(4,server.current);T.eq(nil,bots.status());T.ok(C.mode=="paused"or C.mode=="stopped",M.text())
    vitals(20);M.advance(20)
    T.eq(before,#M.sent);T.eq(0,server.deliveries);T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("rest observes later ferry cycles and recovery never leaves at a stale or wrong-bank arrival",function()
    local app,bots,C,nav,server=start(1,{sailDelay=60,mapBoat=true})
    vitals(10);M.input("/paczki start 1")
    waitFor(function()return server.current==0 end);M.advance(0.4);vitals(85)
    M.line("Prom powoli przybija do brzegu.");M.line("Prom powoli odbija od brzegu.")
    T.eq(0,server.boatLeaves);vitals(20);M.advance(2)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,server.boatLeaves,"old arrival cannot authorize leaving")
    M.line("Prom powoli przybija do brzegu.");M.advance(0.5)
    T.eq(0,server.boatLeaves,"arrival back at departure bank cannot authorize leaving")
    M.line("Prom powoli odbija od brzegu.");M.line("Prom powoli przybija do brzegu.")
    waitFor(function()return C.stats.delivered==1 and C.mode=="stopped" end)
    verify(app,bots,C,server,8)
end)
T.run()
