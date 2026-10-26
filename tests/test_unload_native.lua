-- Regression: native Context disposal closes the courier scope before
-- cancelling navigation. Pending ACK cancellation must not create new drain
-- timers in that closed scope. These synthetic fixtures retain a real held
-- postal job through actual module reload and delayed old server replies.
-- Run from either upstream checkout; no live character/server is used.
do
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
T.module("test.world.unloadkarak",function()
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
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.unloadkarak","chimera.mapper","chimera.terrain","chimera.locations",
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


T.test("reload during an unacknowledged road step retires the old sender and resumes from the late actual position",function()
    local app,bots,C,api,server=start(1)
    M.input("/paczki start 1")
    waitFor(function() return #server.movements==1 end)
    T.eq(1,server.current,"the first road ACK must still be outstanding")
    T.eq("nw",server.movements[1].cmd)
    local before=#M.sent
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local fresh=app.loader.records.kurier_paczki.api.engine
    M.advance(1)
    T.eq(before,#M.sent,"old movement ACK cannot restart an unloaded courier")
    T.eq(2,server.current);T.eq(nil,bots.status());T.ok(fresh.job and not fresh.job.delivered)
    T.eq("Urzad pocztowy Karak-Varn",fresh.job.name);T.eq(0,fresh.stats.delivered)
    T.eq(0,#app.errors,M.text());T.not_contains(M.text(),"resource scope is closed")
    M.input("/paczki wznow")
    waitFor(function() return fresh.mode=="stopped" and fresh.stats.delivered==1 end,40)
    T.eq(1,countCommand("nw"),"resumption must not replay the already acknowledged first road step")
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(1,server.deliveries)
    T.eq(7,server.current);T.eq(0,#app.errors,M.text())
end)
T.test("reload while Kahn-Gad landing is awaiting ACK preserves the parcel without creating a closed-scope drain",function()
    local app,bots,C,api,server=start(1)
    M.input("/paczki start 1")
    waitFor(function() return server.leaves==1 end)
    T.eq(4,server.current,"landing ACK has not yet arrived")
    local before=#M.sent
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local fresh=app.loader.records.kurier_paczki.api.engine
    M.advance(1)
    T.eq(before,#M.sent,"late old landing ACK cannot drive a fresh module")
    T.eq(5,server.current);T.eq(nil,bots.status());T.ok(fresh.job and not fresh.job.delivered)
    T.eq(0,fresh.stats.delivered);T.eq(0,#app.errors,M.text())
    T.not_contains(M.text(),"resource scope is closed")
    M.input("/paczki wznow")
    waitFor(function() return fresh.mode=="stopped" and fresh.stats.delivered==1 end,40)
    T.eq(1,server.buys);T.eq(1,server.entries);T.eq(1,server.leaves);T.eq(1,server.deliveries)
    T.eq(1,countCommand("wybierz paczke 1"));T.eq(7,server.current)
    T.eq(0,#app.errors,M.text())
end)
end
do
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
T.module("test.world.unloadferry",function()
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
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.unloadferry","chimera.mapper","chimera.terrain",
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


T.test("reload during ferry boarding cancels the old operation without a closed-scope drain or late disembark",function()
    local app,bots,C,nav,server=start(1,{boardDelay=2,sailDelay=20,mapBoat=true})
    M.packet("Char.Info",{name="Yarrim",id="e-unload-self"});M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    M.input("/paczki start 1")
    waitFor(function() return server.boatEntries==1 end)
    T.eq(4,server.current,"own boarding ACK has not arrived")
    local before=#M.sent
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local fresh=app.loader.records.kurier_paczki.api.engine
    M.advance(30)
    T.eq(before,#M.sent);T.eq(0,server.current);T.eq(1,server.boatEntries);T.eq(0,server.boatLeaves)
    T.eq(0,server.deliveries);T.eq(nil,bots.status());T.ok(fresh.job and not fresh.job.delivered)
    T.eq("Poczta w Quenelles",fresh.job.name);T.eq(0,fresh.stats.delivered)
    T.eq(0,#app.errors,M.text());T.not_contains(M.text(),"resource scope is closed")
end)
T.test("reload during ferry landing retains the held job and resumes from the confirmed bank without repeating the crossing",function()
    local app,bots,C,nav,server=start(1,{landDelay=2,mapBoat=true})
    M.packet("Char.Info",{name="Yarrim",id="e-unload-self"});M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    M.input("/paczki start 1")
    waitFor(function() return server.boatLeaves==1 end)
    T.eq(0,server.current,"own landing ACK must still be outstanding")
    local before=#M.sent
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local fresh=app.loader.records.kurier_paczki.api.engine
    M.advance(3)
    T.eq(before,#M.sent);T.eq(5,server.current);T.eq(nil,bots.status())
    T.ok(fresh.job and not fresh.job.delivered);T.eq(0,fresh.stats.delivered)
    T.eq(0,#app.errors,M.text());T.not_contains(M.text(),"resource scope is closed")
    M.input("/paczki wznow")
    waitFor(function() return fresh.mode=="stopped" and fresh.stats.delivered==1 end,40)
    T.eq(1,server.boatEntries);T.eq(1,server.boatLeaves);T.eq(1,server.deliveries);T.eq(8,server.current)
    local pickups=0;for _,sent in ipairs(M.sent) do if sent=="wybierz paczke 1" then pickups=pickups+1 end end
    T.eq(1,pickups);T.eq(0,#app.errors,M.text())
end)
end
require("support.harness").run()
