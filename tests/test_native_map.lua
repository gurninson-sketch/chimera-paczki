-- Integration through actual beta.13 loader, NPC catalogue, mapper and bot
-- manager, using the production courier journey/road controller. Only the
-- Mudlet/map/server and world rows are fake.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta"}
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
            npcs=function() return {
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
T.test("actual /npc lookup maps full postal name to native catalogue record",function()
    local app,bots,C,nav=start()
    M.input("/npc johan");T.contains(M.text(),"Johan")
    local route=nav.resolve("Johan Kornwalz",nav.source())
    T.ok(route);T.ok(route.npcId);T.eq(4,route.cost);T.eq(2,#route.rooms)
    M.clear_output();M.input("/paczki npc Johan Kornwalz")
    T.contains(M.text(),"NPC id ");T.contains(M.text(),"koszt drogi tam i z powrotem: 4")
    M.clear_output();M.input("/paczki poczty");T.contains(M.text(),"Bissingen")
    T.eq(nil,bots.status());T.eq("stopped",C.mode);T.eq(0,#app.errors,M.text())
end)
T.test("actual walker handles named exits, NPC entities and return to exact source office",function()
    local app,bots,C,nav=start()
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("running",C.mode,M.text())
    T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver);T.eq(IDS[1],C.source.id)
    T.eq(1,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
end)
T.test("/bot stop during stationary NPC entity wait cancels next-room search",function()
    local app,bots,C,nav=start(false)
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend());M.advance(0.2)
    T.eq(3,app.loader.records.mapper.api.current_room());T.eq(true,nav.inProgress)
    T.ok(C.externalNavigation);local count=#M.sent
    M.input("/bot stop");M.advance(200)
    T.eq(count,#M.sent,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(nil,next(C.timers));T.eq(0,C.stats.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("postal parcel limit ends at its destination office after mixed-coin receipt",function()
    local app,bots,C,nav=start()
    begin("1. Poczta w Bissingen miedzymiastowa 3.00 kg 3 zlote, 14 srebrnych i 9 miedzianych monet [x1]")
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Bissingen.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend())
    T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 3 zlote, 14 srebrnych i 9 miedzianych monet za trud.")
    local count=#M.sent;M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(14,C.stats.silver);T.eq(9,C.stats.copper)
    T.eq(count,#M.sent);T.eq(IDS[5],C.source.id)
    T.eq(5,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
end)
T.test("a different office named Poczta starts from its own GMCP hash",function()
    local app,bots,C,nav,server=start()
    server.current=5
    M.packet("Room.Info",info(5));M.packet("Chimera.Room.Entities",{room=IDS[5],entities={}})
    M.input("/paczki start 1")
    T.eq("przeczytaj tablice",nextSend());T.eq(IDS[5],C.source.id);T.eq(false,C.staticSource)
    T.eq("running",C.mode,M.text());T.not_contains(table.concat(M.sent,"|"),"zerknij")
    M.input("/bot stop");T.eq(nil,bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("descriptor-only Olaff reaches a server-verified delivery without manual takeover",function()
    local app,bots,C,nav=start(true,"Olaff")
    begin("1. Olaff Meier Mlodszy miejscowa 1.40 kg 8 srebrnych monet [x3]")
    M.line("Bierzesz paczke przeznaczona dla: Olaff Meier Mlodszy.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("running",C.mode,M.text())
    local command=nextSend()
    if command=="przedstaw sie" then command=nextSend() end
    T.eq("oddaj paczke",command);T.eq(0,C.stats.delivered)
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 8 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,C.stats.delivered);T.eq(8,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.test("manual Olaff handover in paused state reconciles the live adapter",function()
    local app,bots,C,nav=start()
    C.source=nav.source();C.staticSource=false
    C.job={name="Olaff Meier Mlodszy",route=nav.resolve("Olaff Meier Mlodszy",C.source),source=C.source,delivered=false}
    C.stats.delivered=6;C.stats.silver=60;C:pause("nie znaleziono adresata")
    send("oddaj paczke")
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 8 srebrnych monet za trud.")
    T.eq(true,C.job.delivered);T.eq(7,C.stats.delivered);T.eq(68,C.stats.silver)
    T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());T.eq(nil,C.job)
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("empty source office relocates to nearest reachable office and cooldown prevents bouncing",function()
    local app,bots,C,nav=start()
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend())
    C.rejected.stale=true;board()
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend())
    T.eq("przeczytaj tablice",nextSend())
    T.eq(IDS[5],C.source.id);T.eq(5,C.source.map);T.eq(nil,next(C.rejected))
    T.eq(nil,C.relocation);T.eq("running",C.mode,M.text());T.ok(bots.status())
    board();M.advance(1)
    T.eq("waiting",C.phase,M.text());local count=#M.sent
    M.advance(1);T.eq(count,#M.sent)
    T.eq("przeczytaj tablice",nextSend(35))
    T.eq(5,app.loader.records.mapper.api.current_room());T.eq(IDS[5],C.source.id)
    T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("poczty stop keeps an empty-office courier waiting locally",function()
    local app,bots,C=start()
    M.input("/paczki poczty stop");T.eq(false,C.config.roam)
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());board();M.advance(1)
    T.eq("waiting",C.phase);T.eq(1,app.loader.records.mapper.api.current_room())
    local count=#M.sent;M.advance(1);T.eq(count,#M.sent)
    T.eq(nil,C.relocation);T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("an existing parcel prevents relocation when an empty board is encountered",function()
    local app,bots,C,nav=start()
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend())
    -- Exercise the defensive planning gate with a parcel already in hand.
    C.job={name="Johan Kornwalz",route=nav.resolve("Johan Kornwalz",C.source),delivered=false,source=C.source}
    board();local count=#M.sent;M.advance(1)
    T.eq(nil,C.relocation);T.eq(count,#M.sent);T.eq(1,app.loader.records.mapper.api.current_room())
    T.eq("Johan Kornwalz",C.job.name);T.eq(0,#app.errors,M.text())
end)
T.test("STOP during office relocation cancels future steps and resume continues toward the new office",function()
    local app,bots,C,nav=start()
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());board()
    T.eq("wyjscie",nextSend());T.ok(C.relocation)
    T.eq(IDS[1],C.relocation.from.id);T.eq(IDS[5],C.relocation.to.id)
    local count=#M.sent;M.input("/bot stop");M.advance(1)
    T.eq(count,#M.sent);T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(2,app.loader.records.mapper.api.current_room());T.ok(C.relocation)
    M.input("/paczki wznow")
    -- Resume may send immediately; it must never return to the old office.
    T.eq("e",M.sent[#M.sent]);T.eq(count+1,#M.sent)
    T.eq("e",nextSend());T.eq("przeczytaj tablice",nextSend())
    T.eq(IDS[5],C.source.id);T.eq(5,app.loader.records.mapper.api.current_room())
    T.eq(nil,C.relocation);T.eq("running",C.mode,M.text());T.ok(bots.status())
    T.eq(0,#app.errors,M.text())
end)
T.test("completed parcel limit stops before automatic office relocation",function()
    local app,bots,C=start();begin(NPC_ROW);deliverNpcAndReturn();M.advance(1)
    local count=#M.sent;M.advance(61)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(nil,C.relocation)
    T.eq(1,app.loader.records.mapper.api.current_room());T.eq(count,#M.sent)
    T.not_contains(M.text(),"brak postepu");T.eq(0,#app.errors,M.text())
end)
T.test("completed native trips leave no stale sixty-second movement watchdogs",function()
    local app,bots,C=start();C.config.timeout=120
    begin(NPC_ROW,"/bot paczki");deliverNpcAndReturn();T.eq("przeczytaj tablice",nextSend())
    board(NPC_ROW);T.eq("wybierz paczke 1",nextSend());deliverNpcAndReturn()
    T.eq("przeczytaj tablice",nextSend());local count=#M.sent
    -- Only a leaked navigation watchdog can stop this run: the deliberate
    -- pending-board timeout is longer than the previous actions' watchdogs.
    M.advance(61)
    T.eq("running",C.mode,M.text());T.eq("board",C.phase);T.ok(bots.status())
    T.eq(2,C.stats.delivered);T.eq(count,#M.sent);T.not_contains(M.text(),"brak postepu")
    T.eq(0,#app.errors,M.text())
end)
T.test("fresh start at another recognized office discards a stale automatic Jaskare target",function()
    local app,bots,C,nav,server=start()
    C.source=nav.source();C.staticSource=false;C.stats.delivered=7;C.stats.gold=3;C.stats.silver=68
    C.relocation={from=C.source,to={id="2af1b52e73cf5416",map=999,name="Poczta w Jaskare",city="Jaskare"},manual=false}
    C:stop("poprzednia automatyczna zmiana poczty")
    position(server,5)
    T.eq("przeczytaj tablice",inputSend("/bot paczki"))
    T.eq(IDS[5],C.source.id);T.eq(5,C.source.map);T.eq(nil,C.relocation)
    T.eq(7,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(68,C.stats.silver)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("poczty stop cancels automatic relocation and removes its remembered target",function()
    local app,bots,C,nav=start()
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());board()
    T.eq("wyjscie",nextSend());M.advance(0.2);T.ok(C.relocation)
    T.eq(2,app.loader.records.mapper.api.current_room());local count=#M.sent
    M.input("/paczki poczty stop");M.advance(1)
    T.eq(false,C.config.roam);T.eq(nil,C.relocation);T.eq(count,#M.sent)
    T.eq(false,nav.inProgress);T.eq(2,app.loader.records.mapper.api.current_room())
    T.eq(0,#app.errors,M.text())
end)
T.test("explicit office selection starts from idle and overrides that office empty cooldown",function()
    local app,bots,C,nav=start()
    local offices=app.loader.records.kurier_paczki.api.offices
    offices.markEmpty({id=IDS[5]});T.ok(offices.remaining({id=IDS[5]})>0)
    C.stats.delivered=4;C.stats.silver=32
    T.eq("wyjscie",inputSend("/paczki poczta Bissingen"))
    T.ok(C.relocation and C.relocation.manual);T.ok(bots.status())
    T.eq("e",nextSend());T.eq("e",nextSend());T.eq("przeczytaj tablice",nextSend())
    T.eq(IDS[5],C.source.id);T.eq(nil,C.relocation);T.eq(5,app.loader.records.mapper.api.current_room())
    T.eq(4,C.stats.delivered);T.eq(32,C.stats.silver);T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("manual office retarget replaces a live automatic route without duplicate movement",function()
    local app,bots,C,nav=start()
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend());board()
    T.eq("wyjscie",nextSend());M.advance(0.2)
    T.eq(2,app.loader.records.mapper.api.current_room());T.ok(C.relocation)
    local before=#M.sent
    T.eq("poczta",inputSend("/paczki poczta Kraina Zgromadzenia"))
    T.ok(C.relocation and C.relocation.manual);T.eq(IDS[1],C.relocation.to.id)
    T.eq("przeczytaj tablice",nextSend());M.advance(1)
    T.eq(before+2,#M.sent,"old eastward route must not emit delayed steps")
    T.eq(IDS[1],C.source.id);T.eq(1,app.loader.records.mapper.api.current_room())
    T.eq(nil,C.relocation);T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(false,nav.inProgress)
    T.eq(0,#app.errors,M.text())
end)
T.test("poczty stop leaves a manually selected destination active",function()
    local app,bots,C,nav=start()
    T.eq("wyjscie",inputSend("/paczki poczta Bissingen"));M.advance(0.2)
    M.input("/paczki poczty stop")
    T.eq(false,C.config.roam);T.ok(C.relocation and C.relocation.manual)
    T.eq("e",nextSend());T.eq("e",nextSend());T.eq("przeczytaj tablice",nextSend())
    T.eq(IDS[5],C.source.id);T.eq(nil,C.relocation);T.eq("running",C.mode,M.text())
    T.ok(bots.status());T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.test("poczta tutaj adopts the current office without clearing delivery earnings",function()
    local app,bots,C,nav,server=start()
    C.source=nav.source();C.staticSource=false
    C.stats.delivered=7;C.stats.gold=2;C.stats.silver=68;C.stats.copper=3
    C.relocation={from=C.source,to={id="2af1b52e73cf5416",map=999,name="Poczta w Jaskare"},manual=false}
    C:stop("przerwane przejscie");position(server,5)
    T.eq("przeczytaj tablice",inputSend("/paczki poczta tutaj"))
    T.eq(IDS[5],C.source.id);T.eq(5,C.source.map);T.eq(nil,C.relocation)
    T.eq(7,C.stats.delivered);T.eq(2,C.stats.gold);T.eq(68,C.stats.silver);T.eq(3,C.stats.copper)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("a carried parcel prevents both current-office adoption and explicit destination changes",function()
    local app,bots,C,nav,server=start()
    C.source=nav.source();C.staticSource=false
    C.job={name="Johan Kornwalz",route=nav.resolve("Johan Kornwalz",C.source),source=C.source,delivered=false}
    C:pause("paczka w drodze");position(server,5)
    local count=#M.sent
    M.input("/paczki poczta tutaj");M.input("/paczki poczta Bissingen");M.advance(1)
    T.eq(count,#M.sent);T.eq(IDS[1],C.source.id);T.eq(IDS[1],C.job.source.id)
    T.eq("Johan Kornwalz",C.job.name);T.eq(false,C.job.delivered);T.eq(nil,C.relocation)
    T.eq(0,#app.errors,M.text())
end)
T.test("continuous postal delivery adopts its destination and reads that office board",function()
    local app,bots,C,nav=start()
    begin("1. Poczta w Bissingen miedzymiastowa 3.00 kg 3 zlote, 14 srebrnych i 9 miedzianych monet [x1]","/bot paczki")
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Bissingen.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend());T.eq("oddaj paczke",nextSend())
    local before=#M.sent
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 3 zlote, 14 srebrnych i 9 miedzianych monet za trud.")
    T.eq("przeczytaj tablice",nextSend());T.eq(before+1,#M.sent)
    T.eq(IDS[5],C.source.id);T.eq(5,app.loader.records.mapper.api.current_room());T.eq(nil,C.job)
    T.eq(1,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(14,C.stats.silver);T.eq(9,C.stats.copper)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(false,nav.inProgress)
    board(NPC_ROW);T.eq("wybierz paczke 1",nextSend())
    T.eq(IDS[5],C.source.id);T.eq("johan kornwalz",C.selected.name)
    T.eq(0,#app.errors,M.text())
end)
T.test("manual pickup after a paused stale relocation pins the issuing office and blocks a fresh empty-handed start",function()
    local app,bots,C,nav,server=start()
    C.source={id=IDS[5],map=5,name="Poczta",city="Bissingen",staticNuln=false};C.staticSource=false
    C.relocation={from=C.source,to={id="2af1b52e73cf5416",map=999,name="Poczta w Jaskare",city="Jaskare"},manual=false}
    C.stats.delivered=5;C.stats.silver=40;C:pause("stary cel Jaskare")
    position(server,1)
    send("wybierz paczke 6")
    T.eq(true,C.manualPickup);T.eq(true,C.awaitingPickup);T.eq(IDS[1],C.pendingManualSource.id)
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq(false,C.awaitingPickup);T.eq(false,C.manualPickup);T.eq(nil,C.pendingManualSource)
    T.eq(IDS[1],C.source.id);T.eq(IDS[1],C.job.source.id);T.eq(nil,C.relocation)
    T.eq("johan kornwalz",C.norm(C.job.name));T.eq(false,C.job.delivered)
    local count=#M.sent;M.input("/paczki start");M.advance(1)
    T.eq(count,#M.sent,"explicit fresh start must not leave with an unhandled parcel")
    T.eq(nil,bots.status());T.eq(IDS[1],C.source.id);T.eq(1,app.loader.records.mapper.api.current_room())
    T.eq(5,C.stats.delivered);T.eq(40,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.run()
