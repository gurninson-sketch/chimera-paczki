-- Kahn-Gad semantic recovery through actual native modules and saved profile data.
-- No live server/character or real credentials are used.
-- The synthetic map deliberately contains a bogus literal "statek" edge
-- and a cheap mountain return, while only the explicit ship joins the banks.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"6f2c03461c2f1438","a157000000000002","891456eab7637380","be0c7fc1d5441e3a",
    "2e1aa32a45a83107","c39ae21ea0b2b173","c55c2924e506dd7f","3de8d58adb6dbe9b","2bdb8424ecc77353"}
local NAMES={"Poczta","Trakt do przystani","Przystan u brzegu Blekitnej Wstegi","Poklad statku 'Kahn-Gad'",
    "Przystan w Gorach Czarnych","Przed brama Karak Varn","Poczta","Urzad pocztowy w Karak Varn","Sciezka w gory"}
local LINKS={[1]={nw=2},[2]={se=1,n=3,e=9},[3]={s=2,statek=5},[4]={},[5]={n=6},
    [6]={s=5,e=7,w=9},[7]={w=6,n=8},[8]={s=7},[9]={w=2,e=6}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",nw="polnocny-zachod",se="poludniowy-wschod"}
local worldRooms={}
for index,id in ipairs(IDS) do
    local exits={}
    for command,to in pairs(LINKS[index]) do if command~="statek" then exits[LONG[command] or command]=IDS[to] end end
    worldRooms[id]={id=id,name=NAMES[index],area=index>=5 and "Krolestwa Krasnoludow" or "Blekitna Wstega",
        area_id=index>=5 and "karak" or "blue",terrain=index==9 and "gory" or "trakt",indoors=index==1 or index==7 or index==8,
        exits=exits,hidden={}}
end
T.module("test.world.karak",function()
    return {name="world",setup=function()
        return {room=function(id) return worldRooms[id] end,terrains=function() return {} end,marks=function() return {} end,
            npcs=function() return {} end,gates=function() return {} end,version=function() return "karak-fixture" end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init","core","routes","new_routes","npc","travel","offices","scope","road","ferry","journey",
        "transport_data","inventory","memory","path","postal","checkpoint","escape","recovery","eta","karak_transport","city","city_data","planner","updater"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name..".lua",read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name..".lua"))
    end
    local area=M.empty_map("Karak crossing fixture")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area);setRoomCoordinates(index,index,0,0)
    end
    for from,links in pairs(LINKS) do for command,to in pairs(links) do
        if LONG[command] then setExit(from,to,command) else addSpecialExit(from,to,command) end
    end end
    _G.getPath=function(from,to)
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        if from==to then return true end
        local queue,seen,previous={from},{[from]=true},{}
        local head=1
        while queue[head] do
            local room=queue[head];head=head+1
            local ordered={}
            for command,target in pairs(LINKS[room] or {}) do ordered[#ordered+1]={command,target} end
            table.sort(ordered,function(a,b) return a[1]<b[1] end)
            for _,edge in ipairs(ordered) do if not seen[edge[2]] then
                seen[edge[2]]=true;previous[edge[2]]={from=room,cmd=edge[1]};queue[#queue+1]=edge[2]
            end end
        end
        if not seen[to] then return false end
        local reverse,room={},to
        while room~=from do local p=previous[room];reverse[#reverse+1]={room=room,cmd=p.cmd};room=p.from end
        for index=#reverse,1,-1 do
            local step=reverse[index]
            speedWalkDir[#speedWalkDir+1]=step.cmd;speedWalkPath[#speedWalkPath+1]=step.room;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function board(name)
    M.line("Przesylki dostepne dla Kuriera Krasnoludzkiej Sluzby Pocztowej:")
    if name then M.line("1. "..name.." miedzymiastowa 3.00 kg 5 zlotych, 11 srebrnych i 8 miedzianych monet [x3]") end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
end
local function start(origin,settings)
    origin=origin or 1;settings=settings or {}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.karak","chimera.mapper","chimera.terrain","chimera.locations",
        "chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events","chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=origin,origin=origin,deliveries=0,buys=0,entries=0,leaves=0,withdrawals=0,stores=0,
        bagOpen=settings.bagOpen==true,events={},movements={},boardReads={},offered=settings.offered~=false,
        actor=settings.actor or "Yarrim",settings=settings}
    local function info(index)
        local row=worldRooms[IDS[index]]
        return {id=row.id,name=row.name,area=row.area,area_id=row.area_id,terrain=row.terrain,indoors=row.indoors and 1 or 0,exits=row.exits}
    end
    local function snapshot(index)
        M.packet("Room.Info",info(index));M.packet("Chimera.Room.Entities",{room=IDS[index],entities={}})
        M.line(NAMES[index]..".")
    end
    server.snapshot=function(index) server.current=index;snapshot(index) end
    function server.ready() M.line("Statek dobija do brzegu i opuszcza trap.") end
    local wire=send
    _G.send=function(command,...)
        local denied=M.denied;raiseEvent("sysDataSendRequest",command)
        if denied~=M.denied then return end
        wire(command,...);server.events[#server.events+1]={cmd=command,at=M.now,room=server.current}
        if command=="zerknij" then
            tempTimer(0.02,function()
                M.line(NAMES[server.current]..".")
                if server.current==1 then M.line("Jest tutaj jedno widoczne wyjscie: polnocny-zachod.") end
            end);return
        end
        if command=="przeczytaj tablice" then
            server.boardReads[#server.boardReads+1]=server.current
            tempTimer(0.02,function()
                if server.current==8 then M.line("Przeczytaj co?")
                elseif server.current==server.origin and server.deliveries==0 and server.offered then
                    board(server.current==1 and (settings.label or "Urzad pocztowy Karak-Varn") or "Urzad pocztowy w Nuln")
                else board() end
            end);return
        end
        if command=="wybierz paczke 1" then
            server.package=server.current==1 and 7 or 1
            tempTimer(0.02,function() M.line("Bierzesz paczke przeznaczona dla: "..
                (server.package==7 and (settings.label or "Urzad pocztowy Karak-Varn") or "Urzad pocztowy w Nuln")..".") end);return
        end
        if command=="otworz swoj plecak" then
            tempTimer(0.02,function()
                local wasOpen=server.bagOpen
                server.bagOpen=true
                M.line(wasOpen and "Skorzany plecak juz jest otwarty." or "Otwierasz skorzany plecak.")
            end);return
        end
        if command=="zamknij swoj plecak" then
            if settings.holdClose and server.current==4 then return end
            tempTimer(0.02,function() server.bagOpen=false;M.line("Zamykasz skorzany plecak.") end);return
        end
        if command=="wez monety z swojego plecaka" then
            server.withdrawals=server.withdrawals+1
            T.ok(server.bagOpen,"cash withdrawal before own open confirmation")
            if not settings.silentWithdraw then tempTimer(settings.withdrawDelay or 0.02,function()
                server.cash=true;server.withdrawAt=M.now
                M.line("Bierzesz wiele zlotych monet i dziesiec srebrnych monet z otwartego skorzanego plecaka.")
            end) end
            return
        end
        if command=="wloz monety do swojego plecaka" then
            server.stores=server.stores+1
            T.ok(server.bagOpen,"coin storage before own open confirmation")
            if settings.holdStore and server.current==4 then return end
            if settings.strictCash and server.cash==false then
                tempTimer(0.02,function() M.line("Wloz co?") end);return
            end
            tempTimer(0.02,function() server.cash=false;M.line("Wkladasz wiele srebrnych monet i dziesiec miedzianych monet do otwartego skorzanego plecaka.") end);return
        end
        if command=="kup bilet" then
            T.ok(server.current==3 or server.current==5,"ticket purchase outside verified bank")
            T.ok(server.cash,"ticket purchase preceded owned cash withdrawal")
            server.buys=server.buys+1;server.boughtAt=M.now
            if settings.consumeAllCash then server.cash=false end
            tempTimer(0.02,function() M.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.") end);return
        end
        if command=="wsiadz na statek" then
            server.entries=server.entries+1;server.boatFrom=server.current;server.boatTo=server.current==3 and 5 or 3
            if settings.silentBoard then return end
            tempTimer(settings.boardDelay or 0.05,function()
                server.current=4;M.line("Wchodzisz po trapie na statek.");snapshot(4)
            end)
            if settings.predepartureArrival then tempTimer((settings.boardDelay or 0.05)+0.1,server.ready) end
            if not settings.manualSailing then
            tempTimer((settings.boardDelay or 0.05)+0.3,function() server.departedAt=M.now;M.line("Statek odbija od brzegu i podnosi trap.") end)
            tempTimer((settings.boardDelay or 0.05)+(settings.sailDelay or 1.3),function() server.arrivedAt=M.now;server.ready() end)
            end
            return
        end
        if command=="zejdz ze statku" then
            T.eq(4,server.current,"leaving without verified deck")
            server.leaves=server.leaves+1;server.leaveAt=M.now
            if settings.holdLanding then return end
            tempTimer(0.05,function()
                server.current=settings.wrongBank and server.boatFrom or server.boatTo
                M.line("Schodzisz po trapie ze statku na brzeg.");snapshot(server.current)
            end);return
        end
        if command=="oddaj paczke" then
            tempTimer(0.02,function()
                if server.current==server.package then
                    server.deliveries=server.deliveries+1;server.package=nil;server.cash=true
                    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
                    M.line("Urzednik wyplaca ci 5 zlotych, 11 srebrnych i 8 miedzianych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.") end
            end);return
        end
        local to=(LINKS[server.current] or {})[command]
        if to then
            T.ok(command~="statek","literal mapper marker must never be a MUD command")
            T.ok(to~=9,"courier entered the rejected mountain shortcut")
            server.movements[#server.movements+1]={from=server.current,to=to,cmd=command}
            tempTimer(0.05,function()
                server.current=to;snapshot(to)
                if (to==3 or to==5) and not settings.manualReady then tempTimer(settings.readyDelay or 0.2,server.ready) end
            end)
        end
    end
    M.packet("Char.Info",{name=server.actor,id="e157-self"});M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    snapshot(origin)
    M.input("/pojemniki monety plecak")
    local C=record.api.engine;C.config.autoBackpack=false;C.config.delay=0.2;C.config.tempoSource="courier";C.config.roam=false;C:save()
    return app,app.loader.records.bots.api,C,record.api,server
end
local function waitFor(check,seconds)
    for _=1,math.ceil((seconds or 30)/0.05) do if check() then return end;M.advance(0.05) end
    error("condition timed out:\n"..M.text().."\nSends: "..table.concat(M.sent," | "))
end
local function countCommand(command)
    local n=0;for _,value in ipairs(M.sent) do if value==command then n=n+1 end end;return n
end
local function complete(origin,settings)
    local app,bots,C,api,server=start(origin,settings)
    M.input("/paczki start 1")
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,45)
    local target=origin==1 and 7 or 1
    T.eq(target,server.current,M.text());T.eq(1,server.deliveries);T.eq(1,server.buys);T.eq(1,server.entries);T.eq(1,server.leaves)
    T.eq(IDS[target],C.source.id);T.eq(nil,C.job);T.eq(nil,bots.status());T.eq(1,C.stats.delivered)
    T.eq(5,C.stats.gold);T.eq(11,C.stats.silver);T.eq(8,C.stats.copper)
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(1,countCommand("oddaj paczke"));T.eq(0,countCommand("statek"))
    T.ok(server.withdrawAt and server.boughtAt>=server.withdrawAt,"purchase before own cash ACK")
    T.ok(server.leaveAt and server.arrivedAt and server.leaveAt>=server.arrivedAt,"leave before fresh destination arrival")
    for _,room in ipairs(server.boardReads) do T.ok(room~=8,"broken office queried") end
    T.eq(0,#app.errors,M.text())
    return app,bots,C,api,server
end


local function fresh(server)
    M.packet("Char.Info",{name=server.actor,id="e157-self"})
    server.snapshot(server.current)
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
end
local function aboardSettled(origin,settings)
    settings=settings or {};settings.manualSailing=true;settings.strictCash=true
    local app,bots,C,api,s=start(origin,settings)
    M.input("/paczki start 1")
    waitFor(function() return s.current==4 and s.stores==1 and not s.bagOpen and api.inventory.phase()=="idle" end)
    M.line("Statek odbija od brzegu i podnosi trap.")
    T.ok(api.transportState(s.actor).fareFinished);T.eq(1,s.buys);T.eq(1,s.entries)
    return app,bots,C,api,s
end
local function finishCrossing(app,bots,C,api,s,origin)
    T.eq(0,s.leaves,"no replay of a pre-disconnect arrival or leave")
    s.arrivedAt=M.now;s.ready()
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,40)
    T.eq(origin==1 and 7 or 1,s.current);T.eq(1,s.deliveries);T.eq(1,s.leaves)
    T.eq(1,countCommand("oddaj paczke"));T.eq(nil,C.job);T.eq(nil,bots.status())
    T.eq(nil,api.transportState(s.actor));T.eq(0,#app.errors,M.text())
end
for _,origin in ipairs({1,7}) do
 for _,reload in ipairs({false,true}) do
    T.test((origin==1 and "forward" or "reverse")..(reload and " reload" or " disconnect")..": settled fare is not stowed again and the held parcel completes",function()
        local app,bots,C,api,s=aboardSettled(origin,{actor=origin==1 and "Yarrim" or "Morrid"})
        M.packet("Core.Goodbye",{});T.eq(nil,bots.status());T.ok(api.transportState(s.actor).fareFinished)
        if reload then
            T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text());api=app.loader.records.kurier_paczki.api;C=api.engine
        end
        fresh(s);local stores=s.stores
        M.input("/paczki wznow");waitFor(function() return C.mode=="running" and bots.status() end,10)
        M.advance(.5);T.eq(stores,s.stores);T.eq(1,s.buys);T.eq(1,s.entries)
        finishCrossing(app,bots,C,api,s,origin)
        T.eq(stores+1,s.stores,"only the actual delivery reward needs another storage operation")
        T.eq(1,countCommand("wybierz paczke 1"))
    end)
 end
end
T.test("a confirmed fare receipt before close survives reload without another transfer",function()
    local app,bots,C,api,s=start(1,{manualSailing=true,holdClose=true,strictCash=true})
    M.input("/paczki start 1")
    waitFor(function() return s.current==4 and api.inventory.coinReceipt()>0 and api.inventory.phase()=="close" end)
    T.ok(api.transportState(s.actor).fareFinished,"own receipt must be persisted before the close callback")
    T.eq(false,api.inventory.status().coinsUncertain)
    M.packet("Core.Goodbye",{});T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    api=app.loader.records.kurier_paczki.api;C=api.engine;s.settings.holdClose=false;fresh(s)
    local stored=s.stores;M.input("/paczki wznow");waitFor(function() return C.mode=="running" and bots.status() end,10)
    M.advance(.5);T.eq(stored,s.stores);finishCrossing(app,bots,C,api,s,1)
end)
for _,cash in ipairs({false,true}) do
 T.test("old-client deck upgrade with "..(cash and "cash in hands" or "no cash").." defers optional housekeeping and completes",function()
    local app,bots,C,api,s=start(4,{manualSailing=true,strictCash=true,offered=false})
    local source={id=IDS[1],map=1,name="Poczta",city="Nuln",staticNuln=true}
    C.source=source;C.staticSource=true;C.stopAt=1
    C.job={name="Urzad pocztowy Karak-Varn",actor=C.actor,recipientConfirmed=true,source=source,delivered=false}
    C.mode="paused";api.inventory.setParcelState("hands");C:checkpoint()
    s.package=7;s.boatFrom=3;s.boatTo=5;s.cash=cash
    T.eq(nil,api.transportState(s.actor))
    M.input("/paczki wznow");waitFor(function() return C.mode=="running" and bots.status() end,10)
    M.advance(.5);T.eq(0,s.stores);T.eq(0,s.buys);T.eq(0,s.entries)
    finishCrossing(app,bots,C,api,s,1)
    T.eq(1,s.stores,"cash housekeeping occurs only with the owned delivery payout")
 end)
end
T.test("an uncertain fare transfer remains guarded after disconnect and reload",function()
    local app,bots,C,api,s=start(1,{manualSailing=true,holdStore=true})
    M.input("/paczki start 1")
    waitFor(function() return s.current==4 and s.stores==1 and api.inventory.status().coinsUncertain end)
    M.packet("Core.Goodbye",{});T.ok(api.transportState(s.actor).fareUncertain)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text());api=app.loader.records.kurier_paczki.api;C=api.engine;fresh(s)
    local before=#M.sent;M.input("/paczki wznow");M.advance(2)
    T.eq(before,#M.sent);T.eq(1,s.stores);T.eq(0,s.leaves);T.eq(nil,bots.status());T.ok(C.job and not C.job.delivered)
    T.eq(0,#app.errors,M.text())
end)
T.test("ticket consumes all fare cash: definite no-item reply defers housekeeping without stopping the cruise",function()
    local app,bots,C,api,s=start(1,{manualSailing=true,strictCash=true,consumeAllCash=true})
    M.input("/paczki start 1")
    waitFor(function() local p=api.transportState(s.actor);return p and p.fareDeferred end,30)
    T.eq("running",C.mode,M.text());T.eq(false,api.transportState(s.actor).fareFinished)
    M.line("Statek odbija od brzegu i podnosi trap.")
    finishCrossing(app,bots,C,api,s,1);T.eq(1,s.buys);T.eq(1,s.entries)
end)
T.test("a purchased ticket survives module reload before boarding without paying twice",function()
    local app,bots,C,api,s=start(1,{manualSailing=true,strictCash=true})
    M.input("/paczki start 1");waitFor(function() return s.buys==1 end)
    T.eq(0,s.entries);T.ok(api.transportState(s.actor).bought)
    M.input("/bot stop");T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    api=app.loader.records.kurier_paczki.api;C=api.engine;fresh(s)
    M.input("/paczki wznow");M.advance(.5);s.ready()
    waitFor(function() return s.current==4 and s.stores==1 and not s.bagOpen end)
    T.eq(1,s.buys);T.eq(1,s.entries);T.eq(1,s.withdrawals)
    M.line("Statek odbija od brzegu i podnosi trap.");finishCrossing(app,bots,C,api,s,1)
end)
T.test("reload while a sent landing has no ACK creates no closed-scope timer and waits for a fresh dock",function()
    local app,bots,C,api,s=aboardSettled(1,{holdLanding=true})
    s.ready();waitFor(function() return s.leaves==1 end)
    T.ok(api.transportState(s.actor).leaveSent);T.eq(4,s.current)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    T.eq(0,#app.errors,M.text());api=app.loader.records.kurier_paczki.api;C=api.engine;fresh(s)
    M.input("/paczki wznow");waitFor(function() return C.mode=="running" and bots.status() end,10)
    M.line("Schodzisz po trapie ze statku na brzeg.");M.advance(.5)
    T.eq(1,s.leaves);T.eq(0,s.deliveries);T.eq(4,s.current)
    s.settings.holdLanding=false;s.ready()
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,40)
    T.eq(2,s.leaves);T.eq(1,s.deliveries);T.eq(7,s.current);T.eq(1,s.buys);T.eq(0,#app.errors,M.text())
end)
T.test("a late own coin receipt after STOP updates the paused crossing and explicit resume does not stow twice",function()
    local app,bots,C,api,s=start(1,{manualSailing=true,holdStore=true,strictCash=true})
    M.input("/paczki start 1")
    waitFor(function() return s.current==4 and s.stores==1 and api.inventory.status().coinsUncertain end)
    M.input("/bot stop");local before=#M.sent
    s.cash=false;M.line("Wkladasz wiele srebrnych monet i dziesiec miedzianych monet do otwartego skorzanego plecaka.")
    T.eq(before,#M.sent);T.eq(false,api.inventory.status().coinsUncertain)
    T.ok(api.transportState(s.actor).fareFinished);T.eq(false,api.transportState(s.actor).fareUncertain)
    s.settings.holdStore=false;M.input("/paczki wznow");waitFor(function() return C.mode=="running" and bots.status() end,10)
    M.advance(.5);T.eq(1,s.stores)
    M.line("Statek odbija od brzegu i podnosi trap.");finishCrossing(app,bots,C,api,s,1)
    T.eq(2,s.stores);T.eq(1,s.buys);T.eq(1,s.entries)
end)
T.run()
