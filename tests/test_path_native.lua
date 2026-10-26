-- Native constrained-route fallback and Campogrotta board integration.
-- Actual loader, mapper, NPC/Boty modules and production road/path planning;
-- the preferred getPath below deliberately chooses an unusable skill shortcut.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","269ff0c7899bbd55"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Pod skalna polka","Sklep","Skalny korytarz","Poczta w Campogrotta"}
local LINKS={ [1]={wyjscie=2,["wespnij sie na gore"]=5},[2]={poczta=1,n=3,e=4,["wspinaj sie na mur"]=5},[3]={s=2,e=5},[4]={w=2,u=5},[5]={d=4,w=3,["wespnij sie na gore"]=1,["wspinaj sie na mur"]=2} }
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",u="gora",d="dol"}
local locks,exitWeights
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
            npcs=function() return {
                {name="Matteo",short="sniady starszy mezczyzna",title="Matteo Tessitore, kupiec",room=IDS[5]},
                {name="Johan",short="wysoki starszy mezczyzna",title="Johan Kornwalz, kupiec, czlowiek",room=IDS[3]},
                {name="Johan",short="wysoki starszy mezczyzna",title="Johan Kornwalz, kupiec, czlowiek",room=IDS[4]},
                {name="Olaff",short="sympatyczny pucolowaty mezczyzna",title="Olaff Meier Mlodszy, rymarz, czlowiek",room=IDS[3]},
            } end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua","scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua","postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Test KZ")
    for i,id in ipairs(IDS) do addRoom(i);setRoomIDbyHash(i,id);setRoomName(i,NAMES[i]);setRoomArea(i,area);setRoomCoordinates(i,i,0,0) end
    for from,links in pairs(LINKS) do
        for cmd,to in pairs(links) do
            if LONG[cmd] then setExit(from,to,cmd) else addSpecialExit(from,to,cmd) end
        end
    end
    locks={rooms={},exits={},specials={}}
    exitWeights={[2]={e=4}}
    setRoomWeight(3,50)
    _G.roomLocked=function(id) return locks.rooms[id] or false end
    _G.hasExitLock=function(id,direction) return locks.exits[id..":"..direction] or false end
    _G.hasSpecialExitLock=function(from,to,command) return locks.specials[from..":"..to..":"..command] or false end
    _G.getExitWeights=function(id) return exitWeights[id] or {} end
    -- Fake the client choosing a cheap skill route. Product path.find must
    -- find the weighted live ordinary/named-exit bypass without changing it.
    _G.getPath=function(from,to)
        if ((from==1 or from==2) and to==5) or (from==5 and (to==1 or to==2)) then
            speedWalkDir={"wespnij sie na gore"};speedWalkPath={to};speedWalkWeight={1};return true
        end
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
local function start(showNpc,recipient)
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.courier","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=1,showNpc=showNpc~=false,recipient=recipient or "Johan"}
    local wire=send
    _G.send=function(command,...)
        local before=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=before then return end
        wire(command,...)
        local to=(LINKS[server.current] or {})[command]
        if to and server.skillDenialNext then
            server.skillDenialNext=false
            tempTimer(0.1,function()
                M.line("Starasz wspinac sie na gore, lecz nie posiadasz wystarczajacych umiejetnosci, by zrobic to w tych ")
                M.line("warunkach.")
            end)
            return
        end
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
                local visible=server.recipient=="Olaff" and "sympatyczny pucolowaty mezczyzna" or "Johan"
                rows={{id="e1-recipient",kind="npc",name=visible,relation="neutral"}}
            end
            M.packet("Chimera.Room.Entities",{room=IDS[to],entities=rows})
        end) end
    end
    M.packet("Room.Info",info(1));M.packet("Chimera.Room.Entities",{room=IDS[1],entities={}})
    -- Legacy route scenarios explicitly disable automatic backpack discovery.
    -- Dedicated inventory suites cover the production default separately.
    record.api.engine.config.autoBackpack=false;record.api.engine:save()
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
local POSTAL="1. Poczta w Campogrotta miedzymiastowa 3.00 kg 2 zlote monety [x1]"
local TILEAN="Przesylki dostepne dla Agente Postalle di Tilea:"
local function noClimb()
    for _,command in ipairs(M.sent) do
        T.ok(not command:match("^wespnij") and not command:match("^wspinaj"),"courier attempted a skill shortcut: "..command)
    end
end
local function header(row,footer)
    M.line(TILEAN);M.line(row)
    if footer then M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.") end
end
T.test("NPC ranking and office selection use the same weighted safe bypass before pickup",function()
    local app,bots,C,nav=start()
    local source=nav.source();local offices=app.loader.records.kurier_paczki.api.offices
    local route=assert(nav.resolve("Matteo Tessitore",source))
    T.eq(9,route.cost);T.eq(6,route.outboundCost);T.eq(3,route.returnCost)
    local targets=offices.candidates(source);T.eq(1,#targets);T.eq(IDS[5],targets[1].id)
    T.eq(6,targets[1].cost);T.eq(3,targets[1].returnCost);T.eq(9,targets[1].roundTripCost)
    T.eq(0,#M.sent,"route and cost queries must not issue movement or take a parcel")
    T.eq(50,getRoomWeight(3));T.eq(4,getExitWeights(2).e)
    T.eq(false,roomLocked(5));T.eq(false,hasExitLock(2,"e"));T.eq(false,hasSpecialExitLock(1,5,"wespnij sie na gore"))
    begin(POSTAL);T.eq(6,C.selected.route.cost);T.eq(9,C.selected.route.roundTripCost);T.eq("wybierz paczke 1",M.sent[#M.sent])
    noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("a postal delivery uses named exits and ordinary ascent then accepts the complete Tilean destination board",function()
    local app,bots,C,nav=start();begin(POSTAL,"/bot paczki")
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("u",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
    T.eq("przeczytaj tablice",nextSend());T.eq(IDS[5],C.source.id);T.eq(5,app.loader.records.mapper.api.current_room())
    header("1. Matteo Tessitore miejscowa 1.00 kg 6 srebrnych monet [x1]",true)
    T.eq("wybierz paczke 1",nextSend());T.eq("matteo tessitore",C.selected.name)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(1,C.stats.delivered);T.eq(2,C.stats.gold)
    noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("an already carried parcel resumes from the mountain on the ordinary bypass",function()
    local app,bots,C,nav,server=start()
    send("wybierz paczke 6");M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    T.ok(C.job and not C.job.delivered);position(server,2)
    T.eq("e",inputSend("/paczki wznow"));T.eq("u",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.");M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
    T.eq("przeczytaj tablice",nextSend());T.eq(IDS[5],C.source.id);T.eq(nil,C.job)
    T.eq("running",C.mode,M.text());T.ok(bots.status());noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("no mapped ordinary alternative means no parcel is picked up",function()
    local app,bots,C,nav=start()
    M.map.rooms[1].specials.wyjscie=nil
    T.eq(nil,nav.resolve("Matteo Tessitore",nav.source()))
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());local before=#M.sent
    board(POSTAL);M.advance(1)
    T.eq(before,#M.sent);T.eq(nil,C.job);T.eq("waiting",C.phase,M.text())
    T.eq(1,app.loader.records.mapper.api.current_room());T.ok(bots.status());noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("live exit special and room locks constrain fallback without changing any map weights or locks",function()
    local app,bots,C,nav=start();local source=nav.source()
    locks.exits["2:e"]=true
    local route=assert(nav.resolve("Matteo Tessitore",source))
    T.eq(55,route.cost,"locked light branch forces the heavier ordinary branch")
    T.eq(true,locks.exits["2:e"]);T.eq(50,getRoomWeight(3));T.eq(4,getExitWeights(2).e)
    T.eq(false,hasSpecialExitLock(1,5,"wespnij sie na gore"),"planner must not globally lock skill shortcuts")
    locks.specials["1:2:wyjscie"]=true
    T.eq(nil,nav.resolve("Matteo Tessitore",source));T.eq(true,locks.specials["1:2:wyjscie"])
    locks.specials["1:2:wyjscie"]=nil;locks.exits["2:e"]=nil;locks.rooms[5]=true
    T.eq(nil,nav.resolve("Matteo Tessitore",source));T.eq(true,roomLocked(5))
    T.eq(50,getRoomWeight(3));T.eq(4,getExitWeights(2).e);T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("a Tilean header and row without the full board footer never select a parcel",function()
    local app,bots,C,nav,server=start();position(server,5)
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());local before=#M.sent
    header("1. Matteo Tessitore miejscowa 1.00 kg 6 srebrnych monet [x1]",false)
    M.advance(1);T.eq(before,#M.sent);T.eq("board",C.phase)
    M.advance(10);T.eq(before,#M.sent);T.eq(nil,C.job);T.eq(nil,bots.status())
    T.ok(C.mode=="paused" or C.mode=="stopped");noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("an exact server skill denial stops a sent ordinary step immediately without retry",function()
    local app,bots,C,nav,server=start();begin(POSTAL)
    server.skillDenialNext=true;M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    T.eq("wyjscie",nextSend());M.advance(0.2)
    T.eq(nil,bots.status());T.ok(C.mode=="paused" or C.mode=="stopped",M.text())
    T.eq(false,C.job.delivered);T.eq(1,app.loader.records.mapper.api.current_room())
    local before=#M.sent;M.advance(30);T.eq(before,#M.sent);noClimb()
    T.eq(0,#app.errors,M.text())
end)
T.test("a reloaded courier recovers a held postal parcel from the mountain without another pickup or guessed NPC source",function()
    local app,bots,C,nav,server=start()
    send("wybierz paczke 6");M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    position(server,2);T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local api=app.loader.records.kurier_paczki.api;local fresh=api.engine
    T.eq("stopped",fresh.mode);T.eq(nil,fresh.job);T.eq(nil,fresh.source);T.eq(nil,bots.status())
    local before=#M.sent
    M.input("/paczki paczka Matteo Tessitore")
    T.eq(nil,fresh.job);T.eq(nil,fresh.source);T.eq(before,#M.sent)
    M.input("/paczki paczka Poczta w Campogrotta")
    T.ok(fresh.job and fresh.job.route.postal);T.eq(false,fresh.job.recipientConfirmed)
    T.eq(2,fresh.source.map);T.eq(IDS[2],fresh.source.id);T.eq(before,#M.sent)
    T.eq("e",inputSend("/paczki wznow"));T.eq("u",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.");M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
    T.eq("przeczytaj tablice",nextSend());T.eq(IDS[5],fresh.source.id);T.eq(nil,fresh.job)
    for index=before+1,#M.sent do T.ok(not M.sent[index]:match("^wybierz paczke"),"recovery must not take a second parcel") end
    T.eq(0,api.memory.count(),"explicit recovery alone does not prove the parcel's recipient for learning")
    T.eq(1,fresh.stats.delivered);T.eq(2,fresh.stats.gold);T.ok(bots.status());noClimb();T.eq(0,#app.errors,M.text())
end)
T.test("postal ranking excludes ordinary Grey Mountain directions before pickup and keeps the main road",function()
    local app,bots,C,nav=start()
    setRoomName(4,"Ścieżka w Górach Szarych")
    local route=assert(nav.resolve("Poczta w Campogrotta",nav.source()))
    T.eq(52,route.cost);T.eq(104,route.roundTripCost);T.eq(0,#M.sent)
    begin(POSTAL);T.eq(52,C.selected.route.cost)
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend());T.eq("e",nextSend());T.eq("oddaj paczke",nextSend())
    T.eq(5,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text());noClimb()
end)
T.test("no route avoiding Grey Mountains and Loren wilderness means no pickup or unsafe movement",function()
    local app,bots,C,nav=start()
    setRoomName(3,"Las Loren");setRoomName(4,"Gdzies w Gorach Szarych")
    T.eq(nil,nav.resolve("Poczta w Campogrotta",nav.source()))
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());local before=#M.sent
    board(POSTAL);M.advance(1)
    T.eq(before,#M.sent);T.eq(nil,C.job);T.eq("waiting",C.phase);T.eq(1,app.loader.records.mapper.api.current_room())
    T.eq(0,#app.errors,M.text());noClimb()
end)
T.test("live wilderness recheck stops a copied route at the safe junction",function()
    local app,bots,C,nav,server=start();begin(POSTAL)
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Campogrotta.")
    T.eq("wyjscie",nextSend());M.advance(0.2);T.eq(2,server.current)
    setRoomName(4,"Sciezka w Gorach Szarych")
    local before=#M.sent;M.advance(3)
    T.eq(before,#M.sent);T.eq(2,server.current);T.eq(nil,bots.status());T.eq(false,C.job.delivered)
    T.eq(0,#app.errors,M.text());noClimb()
end)
T.test("native timing geometry includes NPC return but postal cycles end at the destination office",function()
    local app,bots,C,nav=start();local source=nav.source()
    local npc=assert(nav.resolve("Matteo Tessitore",source));local postal=assert(nav.resolve("Poczta w Campogrotta",source))
    T.ok(npc.timing and postal.timing)
    T.eq(3,npc.timing.outbound.steps);T.eq(3,npc.timing.returning.steps)
    T.eq(6,npc.timing.cycle.steps);T.eq(4,npc.timing.cycle.delayUnits)
    T.eq(3,postal.timing.cycle.steps);T.eq(2,postal.timing.cycle.delayUnits)
    T.eq(IDS[5],npc.timing.targetId);T.eq(IDS[1],npc.timing.sourceId)
    T.eq(0,postal.timing.cycle.ferries);T.eq(0,postal.timing.cycle.fareCopper)
    T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("wandering NPC timing mirrors actual outbound candidate choice rather than roundtrip map weights",function()
    local app,bots,C,nav=start();local source=nav.source()
    exitWeights[2].e=1;exitWeights[2].n=2;exitWeights[4]={w=100};locks.exits["4:up"]=true
    local ordinary=getPath
    _G.getPath=function(from,to)
        local choices={
            ["1:3"]={{"wyjscie","n"},{2,3},{1,2}},["1:4"]={{"wyjscie","e"},{2,4},{1,1}},
            ["3:1"]={{"s","poczta"},{2,1},{1,1}},["4:1"]={{"w","poczta"},{2,1},{100,1}},
        }
        local quote=choices[from..":"..to]
        if not quote then return ordinary(from,to) end
        speedWalkDir,speedWalkPath,speedWalkWeight=quote[1],quote[2],quote[3];return true
    end
    local route=assert(nav.resolve("Johan Kornwalz",source))
    T.eq(3,route.rooms[1],"legacy roundtrip cost ordering remains unchanged")
    T.eq(IDS[4],route.timing.targetId,"actual navigator visits the cheapest outbound candidate first")
    T.eq(2,route.timing.candidateCount);T.eq(true,route.timing.uncertain)
    T.eq(4,route.timing.cycle.steps);T.eq(2,route.timing.cycle.delayUnits)
    T.eq(route.timing.cycle.signature,assert(nav.timing(route,source)).cycle.signature)
    T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("a fresh timing query fingerprints a safe changed path without altering the old snapshot",function()
    local app,bots,C,nav=start();local source=nav.source()
    local old=assert(nav.resolve("Poczta w Campogrotta",source))
    local signature=old.timing.cycle.signature
    setRoomName(4,"Sciezka w Gorach Szarych")
    local current=assert(nav.timing(old,source))
    T.ok(current.cycle.signature~=signature)
    T.eq(3,current.cycle.steps);T.eq(signature,old.timing.cycle.signature)
    T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.run()
