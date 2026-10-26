-- Cooperative offer planning through actual Chimera loader/Context/GMCP/Boty.
-- A large synthetic mapped street chain forces an ordinary constrained search;
-- the fake C getPath would instead choose an unusable climbing shortcut.
-- No wall-clock speed assumptions: fairness is checked by native timer events.
-- Run from either chimera-main or chimera-501.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local COUNT=180
local FULL="Johan Kornwalz"
local IDS,NAMES={},{}
for index=1,COUNT do
    IDS[index]=index==1 and "907327356ecc2f87" or string.format("e11100000000%04x",index)
    NAMES[index]=index==1 and "Glowna sala poczty w Krainie Zgromadzenia" or (index==COUNT and "Sklep" or "Ulica")
end
local function links(index)
    local exits={}
    if index<COUNT then exits.e=index+1 end
    if index>1 then exits.w=index-1 end
    return exits
end
local world={}
for index=1,COUNT do
    local exits={}
    for command,to in pairs(links(index)) do exits[command=="e" and "wschod" or "zachod"]=IDS[to] end
    world[IDS[index]]={id=IDS[index],name=NAMES[index],area="Test KZ",area_id="test-plan",
        terrain="miasto",indoors=index==1 or index==COUNT,exits=exits,hidden={}}
end
T.module("test.world.planning",function()
    return {name="world",setup=function()
        return {room=function(id) return world[id] end,terrains=function() return {} end,
            marks=function() return {} end,gates=function() return {} end,version=function() return "test-planning" end,
            npcs=function() return {{name="Johan",short="wysoki starszy mezczyzna",
                title=FULL..", kupiec, czlowiek",room=IDS[COUNT]}} end}
    end}
end)
local counters,locks
local function read(path) local file=assert(io.open(path,"rb"));local data=file:read("*a");file:close();return data end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua",
        "postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
    end
    counters={native=0,exits=0,resolves=0};locks={}
    local area=M.empty_map("Test KZ")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area)
        setRoomCoordinates(index,index,0,0);setRoomWeight(index,1)
    end
    for index=1,COUNT do for command,to in pairs(links(index)) do setExit(index,to,command) end end
    addSpecialExit(1,COUNT,"wespnij sie na gore")
    local getExits=getRoomExits
    _G.getRoomExits=function(index) counters.exits=counters.exits+1;return getExits(index) end
    _G.roomLocked=function(index) return locks[index]==true end
    _G.getPath=function(from,to)
        counters.native=counters.native+1
        if from==to then speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true end
        if from==1 and to==COUNT then
            speedWalkDir={"wespnij sie na gore"};speedWalkPath={COUNT};speedWalkWeight={1};return true
        end
        if not IDS[from] or not IDS[to] then return false end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        local step=to>from and 1 or -1
        for at=from+step,to,step do
            speedWalkDir[#speedWalkDir+1]=step==1 and "e" or "w"
            speedWalkPath[#speedWalkPath+1]=at;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function info(index)
    local row=world[IDS[index]]
    return {id=row.id,name=row.name,area=row.area,area_id=row.area_id,terrain=row.terrain,indoors=row.indoors and 1 or 0,exits=row.exits}
end
local function count(command)
    local total=0;for _,sent in ipairs(M.sent) do if sent==command then total=total+1 end end;return total
end
local function pickups()
    local total=0;for _,sent in ipairs(M.sent) do if sent:match("^wybierz paczke %d+$") then total=total+1 end end;return total
end
local function waitFor(predicate,limit,why,step)
    step=step or 0.001
    for _=1,math.ceil((limit or 15)/step) do if predicate() then return end;M.advance(step) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function start()
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.planning","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local api=record.api
    T.ok(api.planner and api.planner.status,"cooperative planner diagnostics are unavailable")
    local nav=api.navigator
    local resolve=api.engine.resolveRoute
    api.engine.resolveRoute=function(self,...) counters.resolves=counters.resolves+1;return resolve(self,...) end
    local wire=send
    _G.send=function(command,...)
        local before=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=before then return end
        return wire(command,...)
    end
    M.packet("Char.Info",{id="e1-yarrim",name="Yarrim"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    M.packet("Room.Info",info(1));M.packet("Chimera.Room.Entities",{room=IDS[1],entities={}})
    api.engine.config.autoBackpack=false;api.engine.config.roam=false;api.engine:save()
    return app,app.loader.records.bots.api,api.engine,nav,api
end
local function beginRanking(C)
    M.input("/paczki start 1")
    waitFor(function() return count("przeczytaj tablice")>0 end,15,"read the offer board")
    counters.native,counters.exits,counters.resolves=0,0,0
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    for number=1,7 do
        M.line(number..". "..FULL.." miejscowa 1.00 kg "..(9+number).." srebrnych monet [x3]")
    end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return C.phase=="ranking" and counters.exits>0 and pickups()==0 end,15,
        "a long route search did not yield during ranking")
end
local function noLateSelection(app,api,before,kind)
    M.advance(2)
    T.eq(before,pickups(),"cancelled "..tostring(kind).." planning selected a parcel later")
    T.eq(0,api.planner.status().active,"cancelled planning retained an active worker")
    local reads=counters.exits;M.advance(2);T.eq(reads,counters.exits,"cancelled worker retained continuation timers")
    T.eq(0,#app.errors,M.text())
end
T.test("long offer ranking yields to native timers and fresh packets before one best-value pickup",function()
    local app,bots,C,nav,api=start()
    local heartbeats=0
    local function beat()
        if C.phase=="ranking" then
            T.eq(0,pickups(),"pickup preceded completion of all offers")
            heartbeats=heartbeats+1
            -- This event runs on the main event loop, outside the suspended
            -- worker. It must not inherit the worker's cache/yield context.
            T.eq(false,api.planner.active())
            T.eq(nil,api.planner.cache())
            M.packet("Char.Vitals",{hp=100,mana=100,fatigue=11})
        end
        if pickups()==0 then tempTimer(0.001,beat) end
    end
    tempTimer(0.001,beat)
    beginRanking(C)
    waitFor(function() return pickups()>0 end,15,"finish cooperative offer ranking")
    T.ok(heartbeats>=2,"native timer events were starved by ranking")
    T.eq(1,pickups());T.eq(1,count("wybierz paczke 7"));T.eq(0,counters.native,"ranking invoked monolithic C getPath")
    T.eq(1,counters.resolves,"duplicate addressees were resolved more than once")
    T.eq(2*(COUNT-1),C.selected.route.cost);T.eq("johan kornwalz",C.selected.name)
    T.ok(counters.exits<COUNT*5,"duplicate offers repeated the whole route search")
    T.ok(api.planner.status().yields>=2)
    local workerStarts=api.planner.status().started
    M.line("Bierzesz paczke przeznaczona dla: "..FULL..".")
    T.ok(C.job and C.job.route,"owned pickup lost its evaluated route")
    T.eq(1,counters.resolves,"own pickup synchronously resolved the evaluated addressee again")
    T.eq(workerStarts,api.planner.status().started,"own pickup restarted the already evaluated offer work")
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("STOP manual input disconnect actor change and reload cancel a suspended rank worker",function()
    for _,kind in ipairs({"stop","courier_stop","manual","disconnect","actor","numpad","other_bot","reload"}) do
        local app,bots,C,nav,api=start();beginRanking(C)
        local before=pickups()
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="courier_stop" then M.input("/paczki stop")
        elseif kind=="manual" then send("i")
        elseif kind=="disconnect" then raiseEvent("sysDisconnectionEvent")
        elseif kind=="actor" then M.packet("Char.Info",{id="e1-morrid",name="Morrid"})
        elseif kind=="numpad" then app.bus:emit("chimera.numpad.pressed","n")
        elseif kind=="other_bot" then
            bots.register("inny",function(b) b.czekaj(50) end)
            bots.stop("Inny bot przejmuje sterowanie")
            bots.start("inny");T.contains(bots.status(),"inny")
        else T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text()) end
        noLateSelection(app,api,before,kind)
        if kind=="reload" then
            local fresh=app.loader.records.kurier_paczki.api
            T.eq(0,fresh.planner.status().active);T.eq(nil,fresh.engine.selected)
        end
    end
end)
T.test("changed source or current position prevents a stale suspended ranking from taking a parcel",function()
    for _,kind in ipairs({"source","position"}) do
        local app,bots,C,nav,api=start();beginRanking(C)
        if kind=="source" then C.source={id=IDS[2],map=2,name=NAMES[2],staticNuln=false}
        else M.packet("Room.Info",info(2));M.packet("Chimera.Room.Entities",{room=IDS[2],entities={}}) end
        noLateSelection(app,api,0)
    end
end)
T.test("a weight-limit change during ranking cannot pick an offer evaluated under the old limit",function()
    local app,bots,C,nav,api=start();beginRanking(C)
    C.config.maxKg=0.5
    M.advance(2)
    T.eq(0,pickups());T.eq(nil,C.job);T.eq(0,api.planner.status().active)
    T.eq(0,#app.errors,M.text())
    M.input("/bot stop")
end)
T.test("another courier taking an offer during ranking invalidates the board before any pickup",function()
    local app,bots,C,nav,api=start();beginRanking(C)
    T.eq(1,count("przeczytaj tablice"));T.eq(0,pickups())
    M.line("Rudy brodaty mezczyzna bierze paczke z tablicy.")
    T.eq(true,C.boardStale,"a foreign pickup during ranking did not invalidate the offer snapshot")
    waitFor(function() return count("przeczytaj tablice")==2 end,15,"reread a changed offer board")
    T.eq(0,pickups(),"the old numbering was used before rereading")
    T.eq("board",C.phase);T.eq(false,C.boardStale)
    M.advance(0.1);T.eq(0,pickups())
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("2. "..FULL.." miejscowa 1.00 kg 12 srebrnych monet [x2]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return pickups()>0 end,15,"rank the fresh board")
    T.eq(1,pickups());T.eq(1,count("wybierz paczke 2"));T.eq(0,count("wybierz paczke 7"))
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("disabling automatic office changes while an empty-board route is being planned keeps the courier here",function()
    local app,bots,C,nav,api=start()
    local destination="269ff0c7899bbd55"
    setRoomIDbyHash(COUNT,destination)
    setRoomName(COUNT,"Poczta w Campogrotta")
    local candidates=api.offices.candidates(nav.source())
    T.eq(1,#candidates,"fixture must have a reachable alternative working office")
    T.eq(destination,candidates[1].id);T.eq(COUNT,candidates[1].map)
    C.config.roam=true
    M.input("/paczki start 1")
    waitFor(function() return count("przeczytaj tablice")>0 end,15,"read empty source board")
    counters.exits=0
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return C.phase=="ranking" and counters.exits>0 end,15,"cooperative next-office quote")
    T.eq(0,pickups());local sent=#M.sent
    M.input("/paczki poczty stop")
    T.eq(false,C.config.roam)
    waitFor(function() return C.phase=="waiting" end,15,"re-evaluate empty offers after disabling roaming")
    T.eq(sent,#M.sent,"cancelled empty-board planning started a relocation")
    T.eq(nil,C.relocation);T.eq(IDS[1],C.source.id);T.eq(1,nav.current().map)
    T.eq(0,api.planner.status().active);T.eq(0,pickups())
    M.advance(2);T.eq(sent,#M.sent);T.eq(0,#app.errors,M.text())
    M.input("/bot stop")
end)
T.test("a later planning job re-reads live room locks and map identity instead of reusing quote caches",function()
    local app,bots,C,nav,api=start()
    local function quote()
        local finished,route,problem=false,nil,nil
        api.planner.run(function() return nav.resolve(FULL,nav.source()) end,function(ok,result,why)
            T.eq(true,ok);finished=true;route,problem=result,why
        end)
        waitFor(function() return finished end,15,"complete standalone quote")
        T.eq(0,api.planner.status().active)
        return route,problem
    end
    local first=assert(quote());T.eq(2*(COUNT-1),first.cost)
    local reads=counters.exits
    locks[COUNT-1]=true
    T.eq(nil,quote(),"a previous worker's unlocked route survived a fresh lock")
    T.ok(counters.exits>reads,"a new job did not examine the live graph")
    locks[COUNT-1]=nil
    local second=assert(quote());T.eq(first.cost,second.cost)
    setRoomIDbyHash(COUNT,"e111ffffffffffff")
    T.eq(nil,quote(),"a changed target hash reused an earlier map identity")
    T.eq(0,counters.native);T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.run()
