-- Regression of the Urbimo board race in 2026-10-27#11-57-19.txt:
-- Giacomo is selected, Gror changes the board, and our own pickup ACK names
-- Crimmor. Real loader/GMCP/Boty/bag groups handle the parcel and return ACK.
-- Public Urbimo/post/street/Giacomo hashes; the street-to-shop shortcut is
-- synthetic and used only to quote the local offer, never as a game route.
-- Run from chimera-main or chimera-501:
--   texlua ../chimera-paczki-github/tests/test_update_pickup_native.lua
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local SOURCE=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/[^/]+$"),"run using the test file path")
local ACTOR="Testpickup"
local FULL="Giacomo Giandolimento"
local UNEXPECTED="Urzad pocztowy w Crimmor"
local AREA="76c7e10797bf83b1"
local IDS={"0a647e20ca6f97f7","950764e860f20ab8","7d5dbfe647ec219b"}
local NAMES={"Urzad pocztowy Urbimo","Ulica nad brzegiem zatoki","U Giacomo"}
local LINKS={[1]={w=2},[2]={e=1,n=3},[3]={s=2}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod"}
local RETURN_ACK="Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta."
local WORLD={}
for index,id in ipairs(IDS) do
    local exits={};for command,to in pairs(LINKS[index]) do exits[LONG[command]]=IDS[to] end
    WORLD[id]={id=id,name=NAMES[index],area="Urbimo",area_id=AREA,
        indoors=index~=2,terrain=index==2 and "miasto" or nil,exits=exits}
end
T.module("test.world.update_pickup",function()
    return {name="world",setup=function()
        return {room=function(id) return WORLD[id] end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return "test-pickup" end,npcs=function()
                return {{name="Giacomo",short="testowy kupiec",title=FULL,room=IDS[3]}}
            end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua",
        "postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read(SOURCE.."/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Dowolna nazwa obszaru profilu")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area)
        setRoomCoordinates(index,index,0,0);setRoomWeight(index,1)
    end
    for from,links in pairs(LINKS) do for command,to in pairs(links) do setExit(from,to,command) end end
    _G.getPath=function(from,to)
        if from==to then speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true end
        local queue,seen,prior={from},{[from]=true},{}
        local head=1
        while queue[head] do
            local at=queue[head];head=head+1
            for command,target in pairs(LINKS[at] or {}) do
                if not seen[target] then seen[target]=true;prior[target]={from=at,command=command};queue[#queue+1]=target end
            end
        end
        if not seen[to] then return false end
        local reverse,at={},to
        while at~=from do local p=prior[at];reverse[#reverse+1]={room=at,command=p.command};at=p.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for index=#reverse,1,-1 do speedWalkDir[#speedWalkDir+1]=reverse[index].command
            speedWalkPath[#speedWalkPath+1]=reverse[index].room;speedWalkWeight[#speedWalkWeight+1]=1 end
        return true
    end
end
local function info(index)
    local room=WORLD[IDS[index]]
    return {id=room.id,name=room.name,area=room.area,area_id=AREA,indoors=room.indoors and 1 or 0,exits=room.exits}
end
local function count(command)
    local n=0;for _,sent in ipairs(M.sent) do if sent==command then n=n+1 end end;return n
end
local function waitFor(predicate,limit,why)
    for _=1,math.ceil((limit or 20)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function start(options)
    options=options or {}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.update_pickup","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local C,api=record.api.engine,record.api
    local s={current=1,boards=0,pickups=0,returns=0,moves=0,unexpectedResolves=0,parcel=nil,returned=false}
    function s:entities() M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities={}}) end
    function s:pickup()
        self.parcel="hands"
        M.line("Gror bierze paczke z tablicy.")
        M.line("Bierzesz paczke przeznaczona dla: "..UNEXPECTED..".")
    end
    function s:returnAck() self.parcel="returned";self.returned=true;M.line(RETURN_ACK) end
    local resolve=C.resolveRoute
    C.resolveRoute=function(self,name)
        if self.norm(name)==self.norm(UNEXPECTED) then
            s.unexpectedResolves=s.unexpectedResolves+1
            if options.knownUnexpected then
                -- A known destination must still be rejected when it differs
                -- from the selected offer. This answer must never be used.
                return {name=UNEXPECTED,native=true,postal=true,targetId="381bc4bb1fc81f0a",target=4,
                    sourceId=IDS[1],cost=1,commands={},roomIds={[4]="381bc4bb1fc81f0a"}}
            end
        end
        return resolve(self,name)
    end
    local wire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command);if M.denied~=before then return end
        wire(command,...)
        if LINKS[s.current][command] then
            s.moves=s.moves+1;error("a stale pickup must return at its issuing office without any movement: "..command)
        elseif command=="zerknij" then tempTimer(0.05,function()
            M.line(NAMES[1]..".");M.line("Jest tutaj jedno widoczne wyjscie: zachod.")
        end)
        elseif command=="przeczytaj tablice" then
            T.eq(1,s.current);s.boards=s.boards+1
            if s.boards>1 then T.eq(true,s.returned,"read a new board before own return ACK") end
            tempTimer(0.05,function()
                M.line("Przesylki dostepne dla Agente Postalle di Tilea:")
                M.line("1. "..FULL.." miejscowa 0.50 kg 5 srebrnych monet [x1]")
                M.line("2. "..UNEXPECTED.." miedzykrainowa 16.50 kg 19 zlotych i 4 srebrne monety [x5]")
                M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
            end)
        elseif command=="wybierz paczke 1" then s.pickups=s.pickups+1
        elseif command=="zwroc paczke" then
            T.eq(1,s.current);T.eq("hands",s.parcel,"return the actual parcel held at the issuing office")
            s.returns=s.returns+1
        elseif command:find("paczke",1,true) then error("unexpected parcel action after stale pickup: "..command)
        end
    end
    C.config.autoBackpack=false;C.config.roam=false;C.config.bankEnabled=false;C:save()
    M.packet("Char.Info",{name=ACTOR,id="native-pickup-test-character"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10});M.packet("Room.Info",info(1));s:entities()
    M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak")
    T.eq(true,app.loader.records.bags.api.configured("inne"))
    C.stats.delivered=7;C.stats.silver=21
    return app,app.loader.records.bots.api,C,api,s
end
local function beginRace(C,s)
    M.input("/paczki start")
    waitFor(function() return s.pickups==1 end,20,"select the local Giacomo offer")
    T.eq("giacomo giandolimento",C.selected.name);T.eq(true,C.awaitingPickup)
    s:pickup()
    waitFor(function() return s.returns==1 end,20,"return mismatched Crimmor pickup")
    T.ok(C.job and C.job.returningUndelivered);T.eq("pickupChanged",C.job.returnReason)
    T.eq(true,C.awaitingReturn);T.eq(0,s.moves);T.eq(0,s.unexpectedResolves)
end
local function checkSettled(app,C,s)
    T.eq(nil,C.job);T.eq(false,C.awaitingReturn);T.eq(0,s.moves);T.eq(0,s.unexpectedResolves)
    T.eq(7,C.stats.delivered);T.eq(21,C.stats.silver);T.eq(0,C.stats.gold);T.eq(0,C.stats.copper)
    T.eq(nil,C.unavailableRecipients[C:recipientKey(FULL)])
    T.eq(nil,C.unavailableRecipients[C:recipientKey(UNEXPECTED)])
    T.eq(0,count("wloz paczke do swojego plecaka"));T.eq(0,count("wez paczke z swojego plecaka"))
    local saved=assert(app.loader.records.kurier_paczki.api.checkpoint.get(ACTOR))
    T.eq(nil,saved.job);T.eq(false,saved.flags.awaitingReturn);T.eq(0,#app.errors,M.text())
end

T.test("Urbimo board race ignores Gror return replies and refreshes only after our exact return acknowledgement",function()
    local app,bots,C,api,s=start();beginRace(C,s)
    local before=#M.sent
    M.line("Gror oddaje przesylke z powrotem do urzedu. Nikt mu za nia nie zaplaci -- droga nie zostala przebyta.")
    M.line("Gror mowi: "..RETURN_ACK);M.advance(0.2)
    T.eq(before,#M.sent);T.eq(true,C.awaitingReturn);T.ok(C.job);T.eq(1,s.boards)
    s:returnAck();waitFor(function() return s.pickups==2 end,20,"fresh board can select Giacomo again without recipient cooldown")
    T.eq(2,s.boards);T.eq(1,s.returns);T.eq("giacomo giandolimento",C.selected.name)
    checkSettled(app,C,s);T.eq("running",C.mode);T.ok(bots.status());M.input("/bot stop")
end)
T.test("a known unexpected Crimmor destination is returned without resolving or navigating its route",function()
    local app,bots,C,api,s=start({knownUnexpected=true});beginRace(C,s)
    s:returnAck();waitFor(function() return s.pickups==2 end,20,"new local offer after known mismatched pickup")
    T.eq(1,s.returns);T.eq(2,s.boards);checkSettled(app,C,s);M.input("/bot stop")
end)
T.test("native STOP after zwroc paczke accepts a late own return ACK without restarting or reading another board",function()
    local app,bots,C,api,s=start();beginRace(C,s)
    M.input("/bot stop");local before=#M.sent
    s:returnAck();M.advance(15)
    T.eq(before,#M.sent);T.eq(1,s.boards);T.eq(1,s.pickups);T.eq(1,s.returns)
    checkSettled(app,C,s);T.eq("stopped",C.mode);T.eq(nil,bots.status())
end)
T.test("STOP before pickup ACK preserves the late mismatched parcel for return and resume never resolves known Crimmor",function()
    local app,bots,C,api,s=start({knownUnexpected=true})
    M.input("/paczki start")
    waitFor(function() return s.pickups==1 end,20,"Giacomo selected before STOP")
    T.eq("giacomo giandolimento",C.selected.name);T.eq(true,C.awaitingPickup)
    M.input("/bot stop");local before=#M.sent
    s:pickup();M.advance(1)
    T.eq(before,#M.sent,"late pickup acknowledgement must not restart the courier")
    T.eq("stopped",C.mode);T.eq(nil,bots.status());T.eq(false,C.awaitingPickup)
    T.ok(C.job and C.job.returningUndelivered);T.eq("pickupChanged",C.job.returnReason)
    T.eq(C.norm(UNEXPECTED),C.norm(C.job.name));T.eq(IDS[1],C.job.source.id)
    T.eq(0,s.unexpectedResolves);T.eq(0,s.moves);T.eq(0,s.returns);T.eq(1,s.boards)
    local saved=assert(api.checkpoint.get(ACTOR))
    T.eq(true,saved.job.returningUndelivered);T.eq("pickupChanged",saved.job.returnReason)
    T.eq(false,saved.flags.awaitingPickup)
    M.input("/paczki wznow")
    waitFor(function() return s.returns==1 end,20,"resume returns the late mismatched parcel at verified Urbimo")
    T.eq(0,s.unexpectedResolves);T.eq(0,s.moves);T.eq(true,C.awaitingReturn);T.eq(1,s.boards)
    s:returnAck();waitFor(function() return s.pickups==2 end,20,"fresh Giacomo board after returning late pickup")
    checkSettled(app,C,s);T.eq("running",C.mode);T.ok(bots.status());M.input("/bot stop")
end)
T.run()
