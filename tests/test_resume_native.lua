-- Durable courier resume through the actual native loader, profile storage,
-- GMCP, Bags and Boty. Helpers copied from test_inventory_native.lua; each
-- scenario uses a new profile, with real plugin reload inside that profile.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd","0a647e20ca6f97f7"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta","Urzad pocztowy Urbimo"}
local LINKS={ [1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,e=5},[5]={w=4,e=6},[6]={w=5} }
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
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local CLOSE="zamknij swoj plecak"
local OPEN="otworz swoj plecak"
local function opening(expected,firstCommand,openCommand,reply)
    T.eq(openCommand or OPEN,firstCommand or nextSend())
    local before=#M.sent;M.advance(0.1)
    T.eq(before,#M.sent,"transfer must wait for its own opening acknowledgement")
    M.line(reply or "Otwierasz swoj plecak.")
    T.eq(before+1,#M.sent);T.eq(expected,M.sent[#M.sent])
end
local function configure(app)
    M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak")
    T.eq(true,app.loader.records.bags.api.configured("inne"))
    T.eq(true,app.loader.records.bags.api.configured("monety"))
end
local function pulse(fatigue) M.packet("Char.Vitals",{hp=100,mana=100,fatigue=fatigue}) end
local function acceptAndStow()
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    opening(STOW)
end
local function acknowledge(text,expected)
    local before=#M.sent;M.line(text)
    if expected then
        if #M.sent==before then T.eq(expected,nextSend()) else T.eq(before+1,#M.sent);T.eq(expected,M.sent[#M.sent]) end
    else T.eq(before,#M.sent) end
end
local function deliverToCoinStorage()
    acceptAndStow()
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("n",nextSend());opening(TAKE)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","przedstaw sie")
    T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    opening(COINS)
end
local function coinSends()
    local count=0
    for _,command in ipairs(M.sent) do if command==COINS then count=count+1 end end
    return count
end
local ACTOR="Testowicz"
local function character(name)
    M.packet("Char.Info",{id=name==ACTOR and "e1-test" or "e1-other",name=name})
end
local function checkpoint(app) return assert(app.loader.records.kurier_paczki.api.checkpoint,"adapter checkpoint API missing") end
local function current(app) return app.loader.records.kurier_paczki.api.engine end
local function canonicalStart(C)
    character(ACTOR);pulse(10)
    C.stats.delivered=2;C.stats.gold=1;C.stats.silver=18;C.stats.copper=3
end
local function disconnect() M.packet("Core.Goodbye",{}) end
local function reconnect(server,index,name)
    character(name or ACTOR);position(server,index);pulse(10)
end
local function reload(app)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    return current(app)
end
local function heldNpcAtStreet(C)
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.2)
    T.eq(2,C.stopAt-1);T.eq(2,C.stats.delivered)
end
local function urbimoReward()
    begin("1. Urzad pocztowy Urbimo miedzymiastowa 3.00 kg 2 zlote monety [x1]")
    M.line("Bierzesz paczke przeznaczona dla: Urzad pocztowy Urbimo.")
    opening(STOW)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("e",nextSend());T.eq("e",nextSend());T.eq("e",nextSend());opening(TAKE)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","oddaj paczke")
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
end
T.test("disconnect preserves the canonical actor course despite a vocative welcome and resumes from the new current room",function()
    local app,bots,C,nav,server=start();canonicalStart(C);heldNpcAtStreet(C)
    local started=C.stats.started;disconnect()
    T.eq(nil,bots.status());T.ok(C.job);T.eq("testowicz",C.actor)
    local saved=assert(checkpoint(app).get(ACTOR));T.eq("johan kornwalz",C.norm(saved.job.name))
    T.eq(IDS[1],saved.source.id);T.eq(nil,saved.source.map);T.eq(3,saved.stopAt)
    T.eq(2,saved.stats.delivered);T.eq(18,saved.stats.silver)
    local before=#M.sent
    M.line("Witaj, Testowiczu. Podaj haslo...")
    T.eq("testowicz",C.actor);T.ok(C.job);T.eq(2,C.stats.delivered)
    M.input("/paczki wznow");M.advance(1);T.eq(before,#M.sent,"resume without fresh identity and room must wait")
    character(ACTOR);M.advance(1)
    T.eq(before,#M.sent,"fresh identity without a mapped room is insufficient")
    position(server,4);pulse(10)
    T.eq("w",nextSend());T.eq("n",nextSend())
    T.eq(IDS[1],C.source.id);T.eq(3,C.stopAt);T.eq(started,C.stats.started)
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(3,C.stats.delivered)
    T.eq(1,C.stats.gold);T.eq(27,C.stats.silver);T.eq(3,C.stats.copper);T.eq(0,#app.errors,M.text())
end)
T.test("plugin reload restores a held course without starting and resolves the saved source hash to its new map number",function()
    local app,bots,C,nav,server=start();canonicalStart(C);heldNpcAtStreet(C)
    M.input("/bot stop")
    local saved=assert(checkpoint(app).get(ACTOR));T.eq(nil,saved.source.map)
    local original={}
    for from,links in pairs(LINKS) do original[from]={};for command,to in pairs(links) do original[from][command]=to end end
    local ok,why=pcall(function()
    M.map.rooms[11]=M.map.rooms[1];M.map.rooms[1]=nil;M.map.hashes[IDS[1]]=11
    M.map.rooms[2].specials.poczta=11
    LINKS[11]=LINKS[1];LINKS[1]=nil;LINKS[2].poczta=11
    local fresh=reload(app);local before=#M.sent
    T.ok(fresh.job);T.eq("johan kornwalz",fresh.norm(fresh.job.name));T.eq(nil,bots.status())
    M.advance(1);T.eq(before,#M.sent);T.eq(2,fresh.stats.delivered);T.eq(3,fresh.stopAt)
    T.eq("n",inputSend("/paczki wznow"));T.eq(11,fresh.source.map);T.eq(IDS[1],fresh.source.id)
    T.eq(11,fresh.job.source.map);T.eq(true,fresh.job.recipientConfirmed)
    M.input("/bot stop")
    T.eq(0,#app.errors,M.text())
    end)
    LINKS=original
    if not ok then error(why,0) end
end)
T.test("switching canonical characters isolates courses and switching back restores the original actor",function()
    local app,bots,C,nav,server=start();canonicalStart(C);heldNpcAtStreet(C);disconnect()
    reconnect(server,1,"NowyBohater")
    T.eq("nowybohater",C.actor);T.eq(nil,C.job);T.eq(0,C.stats.delivered);T.eq(nil,bots.status())
    local old=assert(checkpoint(app).get(ACTOR));T.eq("johan kornwalz",C.norm(old.job.name));T.eq(2,old.stats.delivered)
    local before=#M.sent;reconnect(server,2,ACTOR)
    T.eq("testowicz",C.actor);T.ok(C.job);T.eq(2,C.stats.delivered);T.eq(3,C.stopAt)
    T.eq(before,#M.sent);T.eq(nil,bots.status())
    T.eq("n",inputSend("/paczki wznow"));T.eq("running",C.mode,M.text());T.eq(0,#app.errors,M.text())
end)
T.test("unknown pickup or handover results remain guarded after disconnect and plugin reload",function()
    for _,stage in ipairs({"pickup","delivery"}) do
        local app,bots,C,nav,server=start();canonicalStart(C);begin(NPC_ROW)
        local location=1
        if stage=="delivery" then
            M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
            T.eq("wyjscie",nextSend());T.eq("n",nextSend())
            T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend());location=3
        end
        disconnect();reload(app);reconnect(server,location)
        local fresh=current(app);local before=#M.sent
        T.eq(true,stage=="pickup" and fresh.awaitingPickup or fresh.awaitingDelivery)
        M.input("/paczki wznow");M.advance(2)
        T.eq(before,#M.sent);T.eq(nil,bots.status());T.ok(checkpoint(app).get(ACTOR))
        T.eq(true,stage=="pickup" and fresh.awaitingPickup or fresh.awaitingDelivery)
        T.eq(0,#app.errors,M.text())
    end
end)
T.test("a confirmed backpack snapshot survives reload and resumes without putting the parcel away again",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app)
    acceptAndStow();acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie");M.advance(0.2)
    disconnect();local saved=assert(checkpoint(app).get(ACTOR))
    T.eq("bag",saved.inventory.state);T.contains(saved.inventory.container.d,"plecaka")
    reload(app);reconnect(server,2)
    local fresh=current(app);local inv=app.loader.records.kurier_paczki.api.inventory
    T.eq("bag",inv.parcelState());T.contains(inv.exportState().container.d,"plecaka")
    -- The parcel belongs to the confirmed old container, even if the player
    -- changes the default destination for future parcels before resuming.
    M.input("/pojemniki inne torba")
    local before=#M.sent;T.eq("n",inputSend("/paczki wznow"));opening(TAKE)
    for index=before+1,#M.sent do T.ok(M.sent[index]~=STOW,"resume must not put the same parcel away again") end
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","przedstaw sie")
    T.eq("running",fresh.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("a confirmed coin receipt before close survives reload without another coin transfer",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app);deliverToCoinStorage()
    M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
    disconnect();local saved=assert(checkpoint(app).get(ACTOR))
    T.eq(true,saved.job.delivered);T.eq(false,saved.job.coinsPending);T.eq(false,saved.inventory.coinsUncertain)
    reload(app);reconnect(server,3)
    local fresh=current(app);T.eq(1,coinSends())
    T.eq("s",inputSend("/paczki wznow"));T.eq("poczta",nextSend());M.advance(1)
    T.eq(1,coinSends());T.eq("stopped",fresh.mode,M.text());T.eq(nil,bots.status())
    T.eq(3,fresh.stats.delivered);T.eq(27,fresh.stats.silver);T.eq(3,fresh.stopAt);T.eq(0,#app.errors,M.text())
end)
T.test("a held Urbimo postal course survives disconnect and continues from its current map room",function()
    local app,bots,C,nav,server=start();canonicalStart(C)
    begin("1. Urzad pocztowy Urbimo miedzymiastowa 3.00 kg 2 zlote monety [x1]")
    M.line("Bierzesz paczke przeznaczona dla: Urzad pocztowy Urbimo.")
    T.eq("wyjscie",nextSend());M.advance(0.2);disconnect()
    M.line("Witaj, Testowiczu. Podaj haslo...");reconnect(server,4)
    T.eq("e",inputSend("/paczki wznow"));T.eq("e",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.");M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
    M.advance(1);T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(IDS[6],C.source.id)
    T.eq(3,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(18,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.test("explicit reset forgets the current actor checkpoint and reload cannot resurrect that parcel",function()
    local app,bots,C,nav,server=start();canonicalStart(C);heldNpcAtStreet(C)
    M.input("/bot stop");T.ok(checkpoint(app).get(ACTOR))
    M.input("/paczki reset");T.eq(nil,checkpoint(app).get(ACTOR));T.eq(nil,C.job);T.eq(0,C.stats.delivered)
    local fresh=reload(app);T.eq(nil,fresh.job);T.eq(0,fresh.stats.delivered);T.eq(nil,checkpoint(app).get(ACTOR))
    local before=#M.sent;M.advance(2);T.eq(before,#M.sent);T.eq(nil,bots.status())
    T.eq(0,#app.errors,M.text())
end)
T.test("a delivered postal course with coin storage not yet started resumes settlement at its destination",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app);urbimoReward()
    T.eq(true,C.job.delivered);T.eq(true,C.job.coinsPending);T.eq(0,coinSends())
    disconnect();local saved=assert(checkpoint(app).get(ACTOR))
    T.eq(true,saved.job.coinsPending);T.eq(false,saved.inventory.coinsUncertain)
    reload(app);reconnect(server,6);local fresh=current(app);local before=#M.sent
    opening(COINS,inputSend("/paczki wznow"))
    M.line("Wkladasz 2 zlote monety do otwartego skorzanego plecaka.")
    T.eq(CLOSE,nextSend());acknowledge("Zamykasz swoj plecak.");M.advance(1.5)
    T.eq(before+3,#M.sent,"settled postal delivery must send only open, coin transfer and close")
    T.eq("stopped",fresh.mode,M.text());T.eq(nil,bots.status());T.eq(IDS[6],fresh.source.id)
    T.eq(6,app.loader.records.mapper.api.current_room());T.eq(nil,fresh.job)
    T.eq(3,fresh.stats.delivered);T.eq(3,fresh.stats.gold);T.eq(0,#app.errors,M.text())
end)
T.test("a delivered postal course with a confirmed coin receipt reloads at its destination without restorage or return",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app);urbimoReward()
    opening(COINS);M.line("Wkladasz 2 zlote monety do otwartego skorzanego plecaka.")
    disconnect();local saved=assert(checkpoint(app).get(ACTOR))
    T.eq(false,saved.job.coinsPending);T.eq(false,saved.inventory.coinsUncertain)
    reload(app);reconnect(server,6);local fresh=current(app);local before=#M.sent
    M.input("/paczki wznow");M.advance(1.5)
    T.eq(before,#M.sent);T.eq(1,coinSends())
    T.eq("stopped",fresh.mode,M.text());T.eq(nil,bots.status());T.eq(IDS[6],fresh.source.id)
    T.eq(6,app.loader.records.mapper.api.current_room());T.eq(nil,fresh.job)
    T.eq(3,fresh.stats.delivered);T.eq(3,fresh.stats.gold);T.eq(0,#app.errors,M.text())
end)
T.test("same-client disconnect with an unacknowledged coin transfer refuses resume without duplicating storage",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app);deliverToCoinStorage()
    local inventory=app.loader.records.kurier_paczki.api.inventory
    T.eq(true,C.job.coinsPending);T.eq(true,inventory.exportState().coinsUncertain);T.eq(1,coinSends())
    disconnect();reconnect(server,3)
    local before=#M.sent;M.input("/paczki wznow");M.advance(2)
    T.eq(before,#M.sent);T.eq(1,coinSends());T.eq(nil,bots.status())
    T.ok(C.job and C.job.delivered);T.eq(true,C.job.coinsPending)
    T.eq(true,inventory.exportState().coinsUncertain)
    T.eq(3,C.stats.delivered);T.eq(27,C.stats.silver)
    T.ok(checkpoint(app).get(ACTOR).job);T.eq(0,#app.errors,M.text())
end)
T.test("reload with an unknown parcel transfer refuses resume while retaining the actual picked-up job",function()
    local app,bots,C,nav,server=start();canonicalStart(C);configure(app);acceptAndStow()
    T.eq("unknown",app.loader.records.kurier_paczki.api.inventory.parcelState())
    disconnect();local saved=assert(checkpoint(app).get(ACTOR))
    T.eq("unknown",saved.inventory.state);T.eq(true,saved.job.recipientConfirmed)
    reload(app);reconnect(server,1)
    local fresh=current(app);local before=#M.sent
    M.input("/paczki wznow");M.advance(2)
    T.eq(before,#M.sent);T.eq(nil,bots.status());T.ok(fresh.job)
    T.eq("johan kornwalz",fresh.norm(fresh.job.name));T.eq(false,fresh.job.delivered)
    T.eq(IDS[1],fresh.source.id);T.eq(3,fresh.stopAt);T.eq(2,fresh.stats.delivered)
    T.eq("unknown",app.loader.records.kurier_paczki.api.inventory.parcelState())
    T.ok(checkpoint(app).get(ACTOR).job);T.eq(0,#app.errors,M.text())
end)
T.test("an automatic office relocation checkpoint resumes toward its destination from the fresh current room",function()
    local app,bots,C,nav,server=start();canonicalStart(C)
    M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend());board()
    T.eq("wyjscie",nextSend());M.advance(0.2);T.ok(C.relocation)
    T.eq(IDS[5],C.relocation.to.id);disconnect()
    local saved=assert(checkpoint(app).get(ACTOR));T.ok(saved.relocation)
    T.eq(IDS[5],saved.relocation.to.id);T.eq(nil,saved.relocation.to.map);T.eq(false,saved.relocation.manual)
    reload(app);reconnect(server,4)
    local fresh=current(app);T.ok(fresh.relocation);T.eq(nil,bots.status())
    local before=#M.sent;T.eq("e",inputSend("/paczki wznow"));T.eq("przeczytaj tablice",nextSend())
    T.eq(before+2,#M.sent,"fresh room4 needs one east step and no replay of the old route")
    T.eq(IDS[5],fresh.source.id);T.eq(5,app.loader.records.mapper.api.current_room())
    T.eq(nil,fresh.relocation);T.eq(nil,fresh.job);T.eq(3,fresh.stopAt);T.eq(2,fresh.stats.delivered)
    T.eq("running",fresh.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("a restored delivered postal course with no resolvable route preserves both pending and confirmed coin states without returning home",function()
    for _,pendingCoins in ipairs({true,false}) do
        local app,bots,C,nav,server=start();canonicalStart(C);configure(app);urbimoReward()
        if not pendingCoins then
            opening(COINS);M.line("Wkladasz 2 zlote monety do otwartego skorzanego plecaka.")
        end
        disconnect();local saved=assert(checkpoint(app).get(ACTOR))
        T.eq(true,saved.job.delivered);T.eq(pendingCoins,saved.job.coinsPending)
        reload(app);reconnect(server,6)
        -- Keep both known office hashes on the map, but remove the only
        -- directed return edge required by the resolver's safe-route check.
        -- The destination name remains canonical and the current room valid.
        local oldReturn=LINKS[2].poczta
        LINKS[2].poczta=nil;M.map.rooms[2].specials.poczta=nil
        local ok,why=pcall(function()
            local api=app.loader.records.kurier_paczki.api;local fresh=api.engine
            T.eq(nil,api.navigator.resolve("Urzad pocztowy Urbimo",{id=IDS[1],map=1,name=NAMES[1]}))
            local before=#M.sent;M.input("/paczki wznow");M.advance(2)
            T.eq(before,#M.sent,"unresolved completed postal course must send neither coins nor movement")
            T.eq(nil,bots.status());T.ok(fresh.mode=="paused" or fresh.mode=="stopped",M.text())
            T.ok(fresh.job and fresh.job.delivered);T.eq(pendingCoins,fresh.job.coinsPending)
            T.eq(IDS[1],fresh.source.id);T.eq(6,app.loader.records.mapper.api.current_room())
            T.eq(3,fresh.stats.delivered);T.eq(3,fresh.stats.gold);T.eq(3,fresh.stopAt)
            T.ok(checkpoint(app).get(ACTOR).job);T.contains(M.text(),"nie rozpoznano jej celu")
            T.eq(0,#app.errors,M.text())
        end)
        LINKS[2].poczta=oldReturn
        if not ok then error(why,0) end
    end
end)
T.run()
