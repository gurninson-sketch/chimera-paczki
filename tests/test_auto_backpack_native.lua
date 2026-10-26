-- Automatic worn-backpack detection with the actual native Bags, GMCP,
-- loader, Boty and production inventory/courier. This independent suite
-- copies the narrow synthetic-world helpers from test_inventory_native.lua.
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
    local server={current=1,showNpc=showNpc~=false,recipient=recipient or "Johan",probes=0,
        inventoryLines={"Masz na sobie krotka dziurawa kolczuge.","Nosisz na plecach otwarty skorzany plecak.","Masz przy sobie pocztowa paczke."}}

    local wire=send
    _G.send=function(command,...)
        local before=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=before then return end
        wire(command,...)
        if command=="i" then
            server.probes=server.probes+1
            local reply=server.inventoryLines
            if reply then tempTimer(server.inventoryDelay or 0.1,function()
                for _,text in ipairs(reply) do M.line(text) end
            end) end
            return
        end
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
    T.eq(true,record.api.engine.config.autoBackpack,"automatic backpack discovery is enabled in a fresh profile")
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
local function unconfigured(app)
    T.eq(false,app.loader.records.bags.api.configured("inne"))
    T.eq(false,app.loader.records.bags.api.configured("monety"))
end
local function acceptAndProbe()
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("i",nextSend())
end
local function noPut()
    for _,command in ipairs(M.sent) do T.ok(not command:match("^wloz "),"unconfirmed backpack caused "..command) end
end
T.test("an unconfigured character uses only the worn backpack from its own inventory and keeps global Bags unchanged",function()
    local app,bots,C,nav,server=start();pulse(10);unconfigured(app)
    local inventory=app.loader.records.kurier_paczki.api.inventory
    acceptAndProbe();T.eq("inventory",C.phase);T.eq("detect",inventory.phase())
    local before=#M.sent;M.advance(0.2);T.eq(before,#M.sent,"inventory capture must finish before choosing a backpack")
    opening(STOW);unconfigured(app);T.eq(1,server.probes)
    T.ok(inventory.status().detectedPack)
    before=#M.sent;M.advance(0.5);T.eq(before,#M.sent);T.eq(1,app.loader.records.mapper.api.current_room())
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    T.contains(inventory.status().parcelContainer,"plecaka")
    acknowledge("Zamykasz swoj plecak.","wyjscie");T.eq("n",nextSend());opening(TAKE)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","przedstaw sie");T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    local command=nextSend();if command=="i" then command=nextSend() end
    opening(COINS,command);unconfigured(app)
    M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
    T.eq(CLOSE,nextSend());acknowledge("Zamykasz swoj plecak.","s")
    T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver);unconfigured(app)
    T.not_contains(M.text(),"Reczna komenda");T.eq(0,#app.errors,M.text())
end)
T.test("a backpack mentioned by another actor or lying on the ground is never selected",function()
    for _,reply in ipairs({
        {"Brodaty mezczyzna nosi na plecach otwarty skorzany plecak.","Ktos mowi: Nosisz na plecach otwarty skorzany plecak."},
        {"Na ziemi lezy otwarty skorzany plecak.","Masz przy sobie pocztowa paczke."},
    }) do
        local app,bots,C,nav,server=start();pulse(10);server.inventoryLines=reply
        acceptAndProbe();T.eq("wyjscie",nextSend());noPut();unconfigured(app)
        T.eq(nil,app.loader.records.kurier_paczki.api.inventory.status().detectedPack)
        T.eq(1,server.probes);T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
    end
end)
T.test("no worn backpack or multiple worn backpacks skip storage without guessing a destination",function()
    for index,reply in ipairs({
        {"Masz na sobie krotka dziurawa kolczuge.","Masz przy sobie pocztowa paczke."},
        {"Nosisz na plecach otwarty skorzany plecak.","Nosisz na plecach zamkniety parciany plecak."},
    }) do
        local app,bots,C,nav,server=start();pulse(10);server.inventoryLines=reply
        acceptAndProbe();T.eq("wyjscie",nextSend());noPut();unconfigured(app)
        T.eq(nil,app.loader.records.kurier_paczki.api.inventory.status().detectedPack)
        T.eq(1,server.probes);T.eq("running",C.mode,M.text());T.ok(bots.status())
        T.contains(M.text(),index==1 and "Nie wykryto jednego noszonego plecaka" or "Wykryto kilka noszonych plecakow")
        T.eq(0,#app.errors,M.text())
    end
end)
T.test("bounded wrapped own inventory replies can identify the worn backpack",function()
    local app,bots,C,nav,server=start();pulse(10)
    server.inventoryLines={"Nosisz na plecach otwarty skorzany","plecak.","Masz przy sobie pocztowa paczke."}
    acceptAndProbe();opening(STOW);T.eq(1,server.probes);unconfigured(app)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("STOP or disconnect during inventory capture cancels the timeout and ignores late own replies",function()
    for _,kind in ipairs({"stop","disconnect"}) do
        local app,bots,C,nav,server=start();pulse(10);server.inventoryDelay=2
        acceptAndProbe()
        if kind=="stop" then M.input("/bot stop") else M.packet("Core.Goodbye",{}) end
        local before=#M.sent;M.advance(35)
        T.eq(before,#M.sent);T.eq(nil,bots.status());T.eq(false,nav.inProgress)
        T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(nil,next(C.timers))
        T.eq(nil,app.loader.records.kurier_paczki.api.inventory.status().detectedPack)
        noPut();unconfigured(app);T.eq(0,#app.errors,M.text())
    end
end)
T.test("rest cancels an unfinished capture and a fresh recovery starts a new owned probe",function()
    local app,bots,C,nav,server=start();pulse(10);server.inventoryDelay=2
    acceptAndProbe();pulse(85);T.eq("resting",C.mode);T.ok(bots.status())
    local before=#M.sent;M.advance(2.1)
    T.eq(before,#M.sent);noPut();unconfigured(app)
    T.eq(nil,app.loader.records.kurier_paczki.api.inventory.status().detectedPack)
    server.inventoryDelay=0.1;pulse(20)
    T.eq("i",nextSend());T.eq(2,server.probes);opening(STOW)
    T.eq("running",C.mode,M.text());T.ok(bots.status());unconfigured(app);T.eq(0,#app.errors,M.text())
end)
T.test("explicitly configured containers take precedence and never issue an automatic inventory query",function()
    local app,bots,C,nav,server=start();pulse(10)
    M.input("/pojemniki inne torba");M.input("/pojemniki monety torba")
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    opening("wloz paczke do swojej torby",nil,"otworz swoja torbe","Otwierasz swoja torbe.");T.eq(0,server.probes)
    acknowledge("Wkladasz pocztowa paczke do otwartej skorzanej torby.","zamknij swoja torbe")
    acknowledge("Zamykasz swoja torbe.","wyjscie")
    T.eq(true,app.loader.records.bags.api.configured("inne"));T.eq(true,app.loader.records.bags.api.configured("monety"))
    T.eq(0,server.probes);T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("an unanswered automatic inventory query times out once and safely continues without a guessed put",function()
    local app,bots,C,nav,server=start();pulse(10);server.inventoryLines=false
    acceptAndProbe();T.eq("wyjscie",nextSend());T.eq(1,server.probes);noPut();unconfigured(app)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
