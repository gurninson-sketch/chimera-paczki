-- Automatic recipient learning through the actual beta.13 loader, profile
-- storage, GMCP, NPC catalogue and production courier. This independent suite
-- copies the narrow synthetic-world helpers from test_native_map.lua.
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
local UNKNOWN="Ferdynand Kowalski"
local function memory(app) return assert(app.loader.records.kurier_paczki.api.memory,"adapter must expose memory") end
local function manualPickup(server,name)
    position(server,1)
    send("wybierz paczke 6")
    M.line("Bierzesz paczke przeznaczona dla: "..name..".")
end
local function manualHandover(server,name,index)
    manualPickup(server,name)
    position(server,index or 3)
    send("oddaj paczke")
    M.line("Wrecasz paczke adresatowi.")
end
local function manualDelivery(server,name,index)
    manualHandover(server,name,index)
    M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
end
local function hasLink(command)
    for _,link in ipairs(M.links) do if tostring(link.code):find(command,1,true) then return true end end
    return false
end
T.test("unknown manual delivery learns only after the actual reward and survives a silent reload",function()
    local app,bots,C,nav,server=start()
    T.eq(0,memory(app).count());manualHandover(server,UNKNOWN)
    T.eq(nil,C.job.route,"recipient must be absent from the NPC catalogue and bundled routes")
    T.eq(0,memory(app).count());M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(1,memory(app).count());local found=memory(app).find(UNKNOWN)
    T.ok(found);T.eq(C.norm(UNKNOWN),C.norm(found.recipient));T.eq(1,found.count);T.eq(IDS[3],found.roomHashes[1])
    T.eq(nil,found.map,"persistent memory contains hashes rather than this profile's map numbers")
    local saved=app.loader.records.kurier_paczki.ctx:saved("sprawdzeni_adresaci",{})
    T.eq(1,saved.schema);T.ok(saved.records);T.ok(next(saved.records))
    position(server,1);local before=#M.sent
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local api=app.loader.records.kurier_paczki.api
    T.eq("stopped",api.engine.mode);T.eq(nil,bots.status());M.advance(1);T.eq(before,#M.sent)
    T.eq(1,api.memory.count());T.eq(1,api.memory.find(UNKNOWN).count)
    local route=assert(api.navigator.resolve(UNKNOWN,{id=IDS[1],map=1,name=NAMES[1]}))
    T.eq(true,route.learned);T.eq(true,route.locationVerified);T.eq(IDS[3],route.roomIds[3])
    begin("1. "..UNKNOWN.." miejscowa 1.00 kg 12 srebrnych monet [x1]")
    M.line("Bierzesz paczke przeznaczona dla: "..UNKNOWN..".")
    T.eq(true,api.engine.job.route.learned)
    T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    T.eq(1,api.memory.find(UNKNOWN).count,"arrival and introduction are not a learned success")
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(2,api.memory.find(UNKNOWN).count)
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",api.engine.mode);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("partial, failed and unrelated responses never teach a recipient",function()
    for _,kind in ipairs({"handover-only","reward-only","failed","coin-move","room-only"}) do
        local app,bots,C,nav,server=start();manualPickup(server,UNKNOWN);position(server,3)
        if kind=="handover-only" then send("oddaj paczke");M.line("Wrecasz paczke adresatowi.")
        elseif kind=="reward-only" then send("oddaj paczke");M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
        elseif kind=="failed" then
            send("oddaj paczke");M.line("Adresat nie znajduje sie w tym miejscu.")
            M.line("Musisz odnalezc "..UNKNOWN.." i wreczyc mu paczke osobiscie.")
        elseif kind=="coin-move" then
            send("oddaj paczke");M.line("Wkladasz 12 srebrnych monet do otwartego skorzanego plecaka.")
        end
        M.advance(1);T.eq(0,memory(app).count(),kind);T.eq(nil,memory(app).find(UNKNOWN),kind)
        T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    end
end)
T.test("duplicate handover and reward lines count one learned success",function()
    local app,bots,C,nav,server=start();manualDelivery(server,UNKNOWN)
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(1,memory(app).count());T.eq(1,memory(app).find(UNKNOWN).count)
    T.eq(1,C.stats.delivered);T.eq(12,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.test("the learned room is captured at handover even if the reward arrives in another room",function()
    local app,bots,C,nav,server=start();manualHandover(server,UNKNOWN,3)
    position(server,4);M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    local found=assert(memory(app).find(UNKNOWN))
    T.eq(1,found.count);T.eq(1,#found.roomHashes);T.eq(IDS[3],found.roomHashes[1])
    T.eq(4,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
end)
T.test("learned hashes resolve against changed runtime map numbers after reload",function()
    local app,bots,C,nav,server=start();manualDelivery(server,UNKNOWN);position(server,1)
    M.map.rooms[33]=M.map.rooms[3];M.map.rooms[3]=nil;M.map.hashes[IDS[3]]=33
    for _,room in pairs(M.map.rooms) do
        for command,target in pairs(room.exits or {}) do if target==3 then room.exits[command]=33 end end
        for command,target in pairs(room.specials or {}) do if target==3 then room.specials[command]=33 end end
    end
    LINKS[33]=LINKS[3];LINKS[3]=nil
    for _,links in pairs(LINKS) do for command,target in pairs(links) do if target==3 then links[command]=33 end end end
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local api=app.loader.records.kurier_paczki.api
    local route=assert(api.navigator.resolve(UNKNOWN,{id=IDS[1],map=1,name=NAMES[1]}))
    T.eq(true,route.learned);T.eq(33,route.rooms[1]);T.eq(IDS[3],route.roomIds[33]);T.eq(nil,route.roomIds[3])
    T.eq(IDS[3],api.memory.find(UNKNOWN).roomHashes[1]);T.eq(nil,api.memory.find(UNKNOWN).map)
    T.eq("stopped",api.engine.mode);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    -- Restore this suite's shared logical fixture for the following tests.
    LINKS[3]=LINKS[33];LINKS[33]=nil
    for _,links in pairs(LINKS) do for command,target in pairs(links) do if target==33 then links[command]=3 end end end
end)
T.test("full names with the same first name remain separate and removing one persists",function()
    local app,bots,C,nav,server=start()
    manualDelivery(server,UNKNOWN,3);manualDelivery(server,"Ferdynand Nowak",4)
    T.eq(2,memory(app).count());T.eq(IDS[3],memory(app).find(UNKNOWN).roomHashes[1])
    T.eq(IDS[4],memory(app).find("Ferdynand Nowak").roomHashes[1]);T.eq(nil,memory(app).find("Ferdynand"))
    M.clear_output();M.input("/paczki baza")
    T.contains(C.norm(M.text()),C.norm(UNKNOWN));T.contains(C.norm(M.text()),"ferdynand nowak")
    M.input("/paczki baza usun "..UNKNOWN)
    T.eq(nil,memory(app).find(UNKNOWN));T.eq(1,memory(app).count());T.ok(memory(app).find("Ferdynand Nowak"))
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    T.eq(nil,memory(app).find(UNKNOWN));T.eq(1,memory(app).count());T.ok(memory(app).find("Ferdynand Nowak"))
    T.eq(0,#app.errors,M.text())
end)
T.test("learning can be disabled and reenabled while resetting statistics preserves confirmed recipients",function()
    local app,bots,C,nav,server=start()
    M.input("/paczki nauka stop");manualDelivery(server,UNKNOWN)
    T.eq(0,memory(app).count());T.eq(1,C.stats.delivered)
    M.input("/paczki nauka auto");manualDelivery(server,UNKNOWN)
    T.eq(1,memory(app).count());T.eq(1,memory(app).find(UNKNOWN).count);T.eq(2,C.stats.delivered)
    M.clear_output();M.input("/paczki baza");T.contains(C.norm(M.text()),C.norm(UNKNOWN))
    M.clear_output();M.input("/paczki")
    T.ok(hasLink("/paczki baza"),M.text())
    T.ok(hasLink("/paczki nauka stop") or hasLink("/paczki nauka auto"),M.text())
    M.input("/paczki reset")
    T.eq(0,C.stats.delivered);T.eq(0,C.stats.silver);T.eq(1,memory(app).count());T.ok(memory(app).find(UNKNOWN))
    T.eq(0,#app.errors,M.text())
end)
T.test("a separately initialized profile does not inherit another profile's learned recipients",function()
    local app,bots,C,nav,server=start();manualDelivery(server,UNKNOWN);T.eq(1,memory(app).count())
    local other,otherBots,otherCore=start()
    T.eq(0,memory(other).count());T.eq(nil,memory(other).find(UNKNOWN))
    T.eq("stopped",otherCore.mode);T.eq(nil,otherBots.status());T.eq(0,#other.errors,M.text())
end)
T.test("manual assignment without a real pickup cannot teach an assumed recipient",function()
    local app,bots,C,nav,server=start()
    M.input("/paczki paczka Johan Kornwalz")
    T.ok(C.job);T.ok(not C.job.recipientConfirmed)
    position(server,3);send("oddaj paczke")
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(0,memory(app).count());T.eq(nil,memory(app).find("Johan Kornwalz"))
    T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("handover and reward outside the map cannot create an unverified location record",function()
    local app,bots,C,nav,server=start();manualPickup(server,UNKNOWN)
    T.ok(app.config:set("mapper","rysowanie",false))
    M.packet("Room.Info",{id="ff00000000000123",name="Nieznana lokacja",exits={}})
    T.eq(nil,app.loader.records.mapper.api.current_room())
    send("oddaj paczke");M.line("Wrecasz paczke adresatowi.")
    M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(0,memory(app).count());T.eq(nil,memory(app).find(UNKNOWN));T.eq(0,#app.errors,M.text())
end)
for _,kind in ipairs({"disconnect","actor","reload","reset","stop"}) do
    T.test("late reward after "..kind.." learns only from valid same-session handover proof",function()
        local app,bots,C,nav,server=start();manualHandover(server,UNKNOWN,3)
        if kind=="disconnect" then M.packet("Core.Goodbye",{})
        elseif kind=="actor" then M.packet("Char.Info",{name="NowyGracz"})
        elseif kind=="reload" then T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
        elseif kind=="reset" then M.input("/paczki reset")
        else M.input("/paczki stop") end
        local before=#M.sent
        M.line("Adresat wrecza ci 12 srebrnych monet za trud.");M.advance(2)
        -- STOP can preserve the actual handover awaiting its payment. A new
        -- session, character, engine or explicitly reset job cannot adopt it.
        T.eq(kind=="stop" and 1 or 0,memory(app).count(),M.text())
        if kind=="stop" then
            T.eq(1,memory(app).find(UNKNOWN).count)
            T.eq(IDS[3],memory(app).find(UNKNOWN).roomHashes[1])
        end
        T.eq(before,#M.sent,"a late confirmation cannot restart movement")
        T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    end)
end
T.test("failed handover followed by an unrelated reward never teaches a recipient",function()
    local app,bots,C,nav,server=start();manualPickup(server,UNKNOWN);position(server,3)
    send("oddaj paczke");M.line("Adresat nie znajduje sie w tym miejscu.")
    M.line("Adresat wrecza ci 12 srebrnych monet za trud.")
    T.eq(0,memory(app).count());T.eq(nil,memory(app).find(UNKNOWN))
    T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
