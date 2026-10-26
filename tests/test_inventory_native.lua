-- Native inventory integration through the actual loader, Bags, GMCP,
-- events, Boty and production inventory/courier. Helpers copied from
-- test_native_map.lua; this is an independent suite.
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
T.test("native Bags transfers gate parcel movement, handover and reward return on own acknowledgements",function()
    local app,bots,C,nav=start();configure(app);pulse(10)
    local inventory=app.loader.records.kurier_paczki.api.inventory
    acceptAndStow();T.eq("inventory",C.phase);T.eq("unknown",inventory.parcelState())
    local count=#M.sent;M.advance(1);T.eq(count,#M.sent);T.eq(1,app.loader.records.mapper.api.current_room())
    M.line("Muskularny porywczy mezczyzna wklada pocztowa paczke do otwartego skorzanego plecaka.")
    M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
    T.eq(count,#M.sent);T.eq("inventory",C.phase)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    T.eq("bag",inventory.parcelState());T.eq(1,app.loader.records.mapper.api.current_room())
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("n",nextSend());opening(TAKE);T.eq("inventory",C.phase)
    count=#M.sent;M.advance(1);T.eq(count,#M.sent);T.eq(0,C.stats.delivered)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    T.eq("hands",inventory.parcelState())
    acknowledge("Zamykasz swoj plecak.","przedstaw sie")
    T.eq("oddaj paczke",nextSend());T.eq("running",C.mode,M.text());T.ok(bots.status())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    opening(COINS);T.eq(true,C.job.coinsPending);T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    count=#M.sent;M.advance(1);T.eq(count,#M.sent);T.eq(3,app.loader.records.mapper.api.current_room())
    M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
    T.eq(CLOSE,nextSend());T.eq(3,app.loader.records.mapper.api.current_room())
    acknowledge("Zamykasz swoj plecak.","s")
    T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,app.loader.records.mapper.api.current_room());T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    T.not_contains(M.text(),"Reczna komenda");T.eq(0,#app.errors,M.text())
    local transfers={}
    for _,command in ipairs(M.sent) do
        if command==OPEN or command==STOW or command==TAKE or command==COINS or command==CLOSE then transfers[#transfers+1]=command end
    end
    local expected={OPEN,STOW,CLOSE,OPEN,TAKE,CLOSE,OPEN,COINS,CLOSE}
    T.eq(#expected,#transfers)
    for index,command in ipairs(expected) do T.eq(command,transfers[index]) end
    -- Coins just closed the same worn pack. The next parcel must open it
    -- again rather than relying on the old inventory's 'otwarty' descriptor.
    acceptAndStow();T.eq("unknown",inventory.parcelState());T.eq(1,C.stats.delivered)
    local opens=0;for _,command in ipairs(M.sent) do if command==OPEN then opens=opens+1 end end
    T.eq(4,opens);M.input("/bot stop");T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("missing parcel storage acknowledgement pauses once and never repeats an uncertain transfer",function()
    local app,bots,C=start();configure(app);pulse(10);acceptAndStow()
    local inventory=app.loader.records.kurier_paczki.api.inventory
    local count=#M.sent;M.advance(7)
    T.eq(count,#M.sent);T.eq(nil,bots.status());T.eq("unknown",inventory.parcelState())
    T.ok(C.mode=="paused" or C.mode=="stopped");T.eq(false,C.job.delivered)
    M.advance(40);T.eq(count,#M.sent)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.")
    T.eq("bag",inventory.parcelState());T.eq(nil,bots.status())
    T.eq("wyjscie",inputSend("/paczki wznow"));T.eq("n",nextSend())
    opening(TAKE);T.eq("running",C.mode,M.text());T.eq(0,#app.errors,M.text())
end)
T.test("rest during packing remembers a late own storage acknowledgement without continuing cancelled sends",function()
    local app,bots,C,nav=start();configure(app);pulse(10)
    C.stats.delivered=3;C.stats.silver=24
    acceptAndStow();local inventory=app.loader.records.kurier_paczki.api.inventory
    pulse(85);T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq("unknown",inventory.parcelState())
    local count=#M.sent
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.")
    T.eq("bag",inventory.parcelState());M.advance(1);T.eq(count,#M.sent)
    T.eq("resting",C.mode);T.eq(false,nav.inProgress);T.eq(4,C.stopAt)
    pulse(20);T.eq("wyjscie",nextSend());T.eq("n",nextSend());opening(TAKE)
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(3,C.stats.delivered);T.eq(24,C.stats.silver)
    T.eq(4,C.stopAt);T.eq(IDS[1],C.source.id);T.eq(0,#app.errors,M.text())
end)
T.test("recovery before an outstanding packing reply does not guess the parcel location or resend storage",function()
    local app,bots,C=start();configure(app);pulse(10);acceptAndStow()
    local inventory=app.loader.records.kurier_paczki.api.inventory
    pulse(85);T.eq("resting",C.mode);local count=#M.sent
    pulse(20);M.advance(1)
    T.eq(count,#M.sent);T.eq("unknown",inventory.parcelState());T.eq(nil,bots.status())
    T.ok(C.mode=="paused" or C.mode=="stopped");T.eq(false,C.job.delivered)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.")
    T.eq("bag",inventory.parcelState());T.eq(count,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("rest or STOP after confirmed coin storage before close resumes without another coin transfer",function()
    for _,kind in ipairs({"rest","stop"}) do
        local app,bots,C,nav=start();configure(app);pulse(10);deliverToCoinStorage()
        local inventory=app.loader.records.kurier_paczki.api.inventory
        local receipt=inventory.coinReceipt()
        M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
        T.ok(inventory.coinReceipt()>receipt);T.eq(1,coinSends())
        -- The transfer is acknowledged, while the settle timer has not sent
        -- the container-close command or completed the courier operation.
        if kind=="rest" then pulse(85);T.eq("resting",C.mode);T.ok(bots.status())
        else M.input("/bot stop");T.eq(nil,bots.status()) end
        local count=#M.sent;M.advance(1);T.eq(count,#M.sent)
        T.eq(true,C.job.delivered);T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
        if kind=="rest" then pulse(20);T.eq("s",nextSend())
        else T.eq("s",inputSend("/paczki wznow")) end
        T.eq(1,coinSends(),"a confirmed coin transfer must not be repeated")
        T.eq("poczta",nextSend());M.advance(1)
        T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
        T.eq(1,coinSends());T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
        T.eq(1,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
    end
end)
T.test("STOP before coin acknowledgement accepts a late receipt and manual resume skips duplicate storage",function()
    local app,bots,C,nav=start();configure(app);pulse(10);deliverToCoinStorage()
    local inventory=app.loader.records.kurier_paczki.api.inventory
    local receipt=inventory.coinReceipt();T.eq(true,C.job.coinsPending)
    M.input("/bot stop");T.eq(nil,bots.status());local count=#M.sent
    M.advance(1);T.eq(count,#M.sent)
    acknowledge("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.")
    T.ok(inventory.coinReceipt()>receipt);T.eq(1,coinSends());M.advance(1);T.eq(count,#M.sent)
    T.eq("s",inputSend("/paczki wznow"));T.eq(1,coinSends())
    T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(false,nav.inProgress)
    T.eq(1,coinSends());T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    T.eq(1,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
end)
T.test("an already open backpack settles a postal reward and stores the next parcel without stopping or duplicate transfers",function()
    local app,bots,C,nav=start();configure(app);pulse(10)
    local source={map=5,id=IDS[5],name="Poczta w Bissingen",city="Bissingen"}
    local route,why=nav.resolve("Poczta w Krainie Zgromadzenia",source)
    T.ok(route,why);T.eq(true,route.postal)
    C.source=source;C.staticSource=false
    C.job={name=route.name,route=route,source=source,delivered=true,coinsPending=true}
    C.stats.delivered=1;C.stats.gold=3;C.stats.silver=13;C.stats.copper=7
    T.eq(OPEN,inputSend("/bot paczki"))
    local count=#M.sent
    M.line("Zwinna jaszczuroczleczka otwiera skorzany plecak.")
    M.line("Plocienna torba juz jest otwarta.")
    M.advance(0.1);T.eq(count,#M.sent);T.eq("open",app.loader.records.kurier_paczki.api.inventory.phase())
    M.line("Skorzany plecak juz jest otwarty.")
    T.eq(count+1,#M.sent);T.eq(COINS,M.sent[#M.sent]);T.eq(1,coinSends())
    M.line("Skorzany plecak juz jest otwarty.")
    T.eq(count+1,#M.sent,"duplicate opening replies must not repeat the transfer")
    acknowledge("Wkladasz 12 srebrnych monet i trzy zlote monety do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz skorzany plecak.","przeczytaj tablice")
    T.eq(nil,C.job);T.eq(IDS[1],C.source.id);T.eq("running",C.mode);T.ok(bots.status())
    T.eq(1,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(13,C.stats.silver);T.eq(7,C.stats.copper)
    board(NPC_ROW);T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    opening(STOW,nil,nil,"Skorzany plecak juz jest otwarty.")
    acknowledge("Wkladasz paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz skorzany plecak.","wyjscie")
    T.eq(1,coinSends());T.eq("running",C.mode);T.ok(bots.status())
    T.eq("bag",app.loader.records.kurier_paczki.api.inventory.parcelState())
    local puts=0;for _,command in ipairs(M.sent) do if command==STOW then puts=puts+1 end end
    T.eq(1,puts);T.not_contains(M.text(),"brak potwierdzenia otwarcia")
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("already open confirmation also unlocks parcel retrieval while another actor cannot",function()
    local app,bots,C,nav=start();configure(app);pulse(10)
    acceptAndStow()
    acknowledge("Wkladasz paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz skorzany plecak.","wyjscie")
    T.eq("n",nextSend());T.eq(OPEN,nextSend())
    local count=#M.sent
    M.line("Mloda dziewczyna otwiera swoj plecak.")
    M.line("Mloda dziewczyna mowi: Skorzany plecak juz jest otwarty.")
    M.advance(0.1);T.eq(count,#M.sent)
    M.line("Skorzany plecak juz jest otwarty.")
    T.eq(count+1,#M.sent);T.eq(TAKE,M.sent[#M.sent])
    acknowledge("Bierzesz paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz skorzany plecak.","przedstaw sie")
    T.eq("oddaj paczke",nextSend());T.eq("running",C.mode);T.ok(bots.status())
    T.eq("hands",app.loader.records.kurier_paczki.api.inventory.parcelState())
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("late already-open at seven seconds retains native ownership and starts one confirmed parcel transfer",function()
    local app,bots,C=start();configure(app);pulse(10)
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq(OPEN,nextSend())
    local inventory=app.loader.records.kurier_paczki.api.inventory
    local before=#M.sent;M.advance(7)
    T.eq(before,#M.sent,"opening grace must neither repeat open nor move the parcel")
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq("open",inventory.phase())
    T.eq("hands",inventory.parcelState());T.eq(1,app.loader.records.mapper.api.current_room())
    T.contains(M.text(),"Czekam na potwierdzenie otwarcia")
    M.line("Morrid mowi: Skorzany plecak juz jest otwarty.")
    T.eq(before,#M.sent)
    M.line("Skorzany plecak juz jest otwarty.")
    T.eq(before+1,#M.sent);T.eq(STOW,M.sent[#M.sent]);T.eq("unknown",inventory.parcelState())
    M.line("Skorzany plecak juz jest otwarty.");T.eq(before+1,#M.sent)
    acknowledge("Wkladasz paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz skorzany plecak.","wyjscie")
    local opens,puts=0,0
    for _,command in ipairs(M.sent) do
        if command==OPEN then opens=opens+1 elseif command==STOW then puts=puts+1 end
    end
    T.eq(1,opens);T.eq(1,puts);T.eq("bag",inventory.parcelState());T.eq("running",C.mode);T.ok(bots.status())
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("native STOP during opening grace prevents any transfer after a late already-open reply",function()
    local app,bots,C=start();configure(app);pulse(10)
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq(OPEN,nextSend());M.advance(7)
    local inventory=app.loader.records.kurier_paczki.api.inventory
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq("open",inventory.phase());T.eq("hands",inventory.parcelState())
    M.input("/bot stop");T.eq(nil,bots.status());local before=#M.sent
    M.line("Skorzany plecak juz jest otwarty.");M.line("Otwierasz skorzany plecak.");M.advance(40)
    T.eq(before,#M.sent,"cancelled opening must not put away or retrieve any item")
    T.eq("hands",inventory.parcelState());T.eq(1,app.loader.records.mapper.api.current_room());T.eq(false,C.job.delivered)
    T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
