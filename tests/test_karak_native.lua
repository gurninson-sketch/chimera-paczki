-- Karak Varn courier integration through actual beta.13 native modules.
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
        bagOpen=settings.bagOpen==true,events={},movements={},boardReads={},offered=settings.offered~=false}
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
            tempTimer(0.02,function() server.cash=false;M.line("Wkladasz wiele srebrnych monet i dziesiec miedzianych monet do otwartego skorzanego plecaka.") end);return
        end
        if command=="kup bilet" then
            T.ok(server.current==3 or server.current==5,"ticket purchase outside verified bank")
            T.ok(server.cash,"ticket purchase preceded owned cash withdrawal")
            server.buys=server.buys+1;server.boughtAt=M.now
            tempTimer(0.02,function() M.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.") end);return
        end
        if command=="wsiadz na statek" then
            server.entries=server.entries+1;server.boatFrom=server.current;server.boatTo=server.current==3 and 5 or 3
            if settings.silentBoard then return end
            tempTimer(settings.boardDelay or 0.05,function()
                server.current=4;M.line("Wchodzisz po trapie na statek.");snapshot(4)
            end)
            if settings.predepartureArrival then tempTimer((settings.boardDelay or 0.05)+0.1,server.ready) end
            tempTimer((settings.boardDelay or 0.05)+0.3,function() server.departedAt=M.now;M.line("Statek odbija od brzegu i podnosi trap.") end)
            tempTimer((settings.boardDelay or 0.05)+(settings.sailDelay or 1.3),function() server.arrivedAt=M.now;server.ready() end)
            return
        end
        if command=="zejdz ze statku" then
            T.eq(4,server.current,"leaving without verified deck")
            server.leaves=server.leaves+1;server.leaveAt=M.now
            tempTimer(0.05,function()
                server.current=settings.wrongBank and server.boatFrom or server.boatTo
                M.line("Schodzisz po trapie ze statku na brzeg.");snapshot(server.current)
            end);return
        end
        if command=="oddaj paczke" then
            tempTimer(0.02,function()
                if server.current==server.package then
                    server.deliveries=server.deliveries+1;server.package=nil
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
    M.packet("Char.Info",{name="Yarrim",id="e157-self"});M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
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

T.test("Karak-Varn alias is delivered through the paid ship to the working post office without manual commands",function()
    local app,bots,C,api,server=complete(1)
    T.ok(server.stores>=2,"remaining fare cash and delivered payout must both return to the pack")
end)
T.test("reverse course leaves Karak by the same ship rather than the cheaper mountain return",function() complete(7) end)
T.test("Poczta w Karak Varn alias and an already open coin pack use the same working destination",function()
    complete(1,{label="Poczta w Karak Varn",bagOpen=true})
end)
T.test("ship geometry and ETA are present before taking the parcel",function()
    local app,bots,C,api,server=start(1,{manualReady=true})
    M.input("/paczki start 1");waitFor(function() return C.selected~=nil end)
    T.ok(C.selected.eta);T.ok(C.selected.eta.breakdown.transport>0)
    T.eq(1,C.selected.route.timing.cycle.ferries);T.eq(1,#C.selected.route.timing.cycle.ferryKeys)
    T.eq(IDS[7],C.selected.route.targetId);T.eq(0,server.buys)
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("foreign cash and ticket messages cannot authorize purchase before own withdrawal confirmation",function()
    local app,bots,C,api,server=start(1,{silentWithdraw=true})
    M.input("/bot paczki");waitFor(function() return server.withdrawals==1 end)
    M.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.")
    M.line("Zwinna tajemnicza jaszczuroczleczka bierze monety z otwartego skorzanego plecaka.")
    M.advance(0.5);T.eq(0,server.buys);T.eq(0,server.entries)
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("arrival before departure cannot authorize leaving the vessel at the starting bank",function()
    complete(1,{predepartureArrival=true,sailDelay=2})
end)
for _,kind in ipairs({"stop","disconnect","reload","manual"}) do
    T.test(kind.." while waiting for the vessel cancels later readiness and all fare commands",function()
        local app,bots,C,api,server=start(1,{manualReady=true})
        M.input("/bot paczki");waitFor(function() return server.current==3 end)
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        elseif kind=="reload" then T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
        else send("i") end
        local before=#M.sent;server.ready();M.advance(2)
        T.eq(before,#M.sent);T.eq(0,server.buys);T.eq(0,server.entries);T.eq(0,server.deliveries)
        T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    end)
end
T.test("STOP after a ticket command never permits delayed boarding or a second purchase",function()
    local app,bots,C,api,server=start(1,{silentBoard=true})
    M.input("/bot paczki");waitFor(function() return server.buys==1 end)
    M.input("/bot stop");local before=#M.sent
    M.line("Ciemnowlosy przyjacielski mezczyzna podaje bilet kupujacej osobie.");server.ready();M.advance(2)
    T.eq(before,#M.sent);T.eq(1,server.buys);T.eq(0,server.leaves);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("the broken historical office cannot be selected with pracuj tutaj or read a parcel board",function()
    local app,bots,C,api,server=start(8,{offered=false})
    M.input("/paczki poczta tutaj");M.advance(2)
    for _,room in ipairs(server.boardReads) do T.ok(room~=8,"disabled branch treated as a courier office") end
    T.eq(0,countCommand("oddaj paczke"));T.eq(0,server.deliveries);T.eq(0,#app.errors,M.text())
    M.input("/bot stop")
end)
T.test("starting in the broken historical office moves work to the real Karak office",function()
    local app,bots,C,api,server=start(8,{offered=false})
    M.input("/bot paczki")
    waitFor(function() return server.current==7 and C.phase=="waiting" end)
    T.eq(IDS[7],C.source.id);T.ok(bots.status());T.eq(0,server.buys)
    T.eq(0,countCommand("wybierz paczke 1"));T.eq(0,countCommand("oddaj paczke"))
    for _,room in ipairs(server.boardReads) do T.eq(7,room,"disabled office was queried before relocating") end
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("a saved unresolved Karak parcel at the old office resumes to the working recipient without a second pickup",function()
    local app,bots,C,api,server=start(8,{offered=false})
    local source={id=IDS[1],map=1,name="Poczta",city="Nuln",staticNuln=true}
    C.source=source;C.staticSource=true;C.stopAt=1
    C.job={name="Urzad pocztowy Karak-Varn",actor=C.actor,recipientConfirmed=true,source=source,delivered=false}
    api.inventory.setParcelState("hands")
    C.mode="paused";C:checkpoint();server.package=7
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    api=app.loader.records.kurier_paczki.api;C=api.engine
    M.input("/paczki wznow")
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end)
    T.eq(7,server.current);T.eq(1,server.deliveries);T.eq(IDS[7],C.source.id)
    T.eq(0,countCommand("wybierz paczke 1"));T.eq(1,countCommand("oddaj paczke"))
    T.eq(0,server.buys);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("automatic fatigue recovery aboard resumes the same crossing without buying another ticket",function()
    local app,bots,C,api,server=start(1,{sailDelay=4})
    M.input("/paczki start 1")
    waitFor(function() return server.current==4 and server.stores>=1 and not server.bagOpen and api.inventory.phase()=="idle" end)
    M.packet("Char.Vitals",{hp=100,fatigue=85,mana=100})
    T.eq("resting",C.mode);T.ok(bots.status());T.ok(C.job and not C.job.delivered)
    M.packet("Char.Vitals",{hp=100,fatigue=20,mana=100})
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,40)
    T.eq(7,server.current);T.eq(1,server.buys);T.eq(1,server.entries);T.eq(1,server.leaves)
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(1,server.deliveries);T.eq(0,#app.errors,M.text())
end)
T.test("STOP after purchase before queued boarding resumes the same crossing without another purchase",function()
    local app,bots,C,api,server=start(1)
    M.input("/paczki start 1")
    waitFor(function() return server.buys==1 end)
    T.eq(0,server.entries,"fixture must stop strictly before the queued boarding command")
    M.input("/bot stop")
    local count=#M.sent;M.advance(0.2)
    T.eq(count,#M.sent);T.eq(0,server.entries);T.ok(C.job and not C.job.delivered)
    M.input("/paczki wznow")
    -- The old docking event predates STOP. A renewed service arrival,
    -- observed after the owned transport has resumed, permits boarding.
    M.advance(0.5);T.eq(1,server.buys);T.eq(0,server.entries)
    server.ready()
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,40)
    T.eq(7,server.current);T.eq(1,server.buys);T.eq(1,server.entries);T.eq(1,server.leaves)
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(1,countCommand("oddaj paczke"))
    T.eq(0,#app.errors,M.text())
end)
for _,origin in ipairs({2,7}) do
    T.test("an empty saved disabled source resumes work at the real office from current room "..origin,function()
        local app,bots,C,api,server=start(origin,{offered=false})
        C.source={id=IDS[8],map=8,name=NAMES[8],city="Karak Varn",staticNuln=false}
        C.staticSource=false;C.job=nil;C.relocation=nil;C.mode="paused";C:checkpoint()
        T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
        api=app.loader.records.kurier_paczki.api;C=api.engine
        M.input("/paczki wznow")
        waitFor(function() return server.current==7 and C.phase=="waiting" end,40)
        T.eq(IDS[7],C.source.id);T.eq(nil,C.job);T.ok(bots.status())
        T.eq(0,countCommand("wybierz paczke 1"));T.eq(0,countCommand("oddaj paczke"))
        for _,room in ipairs(server.boardReads) do T.eq(7,room,"old saved source sent a board query to the disabled branch") end
        T.eq(0,#app.errors,M.text());M.input("/bot stop")
    end)
end
T.test("fresh recovery cannot repeat an unresolved fare withdrawal and an exact late own ACK releases the saved course",function()
    local settings={silentWithdraw=true}
    local app,bots,C,api,server=start(1,settings)
    M.input("/paczki start 1")
    waitFor(function() return server.withdrawals==1 end)
    T.eq(true,api.inventory.status().coinsUncertain)
    M.packet("Char.Vitals",{hp=100,fatigue=85,mana=100})
    T.eq("resting",C.mode);T.ok(bots.status())
    M.packet("Char.Vitals",{hp=100,fatigue=20,mana=100})
    local before=#M.sent;M.advance(1)
    T.eq(before,#M.sent,"healthy vitals cannot retry an uncertain withdrawal")
    T.eq(1,server.withdrawals);T.eq(0,server.buys);T.eq(0,server.entries)
    settings.silentWithdraw=false;server.cash=true;server.withdrawAt=M.now
    M.line("Bierzesz wiele zlotych monet i dziesiec srebrnych monet z otwartego skorzanego plecaka.")
    T.eq(false,api.inventory.status().coinsUncertain)
    M.advance(0.5);server.ready()
    waitFor(function() return C.mode=="stopped" and C.stats.delivered==1 end,40)
    T.eq(7,server.current);T.eq(1,server.buys);T.eq(1,server.entries);T.eq(1,server.leaves)
    T.eq(1,server.withdrawals,"the exact late receipt already proves the fare cash is in hands")
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(1,server.deliveries);T.eq(0,#app.errors,M.text())
end)
T.run()
