-- Nuln bank visits through the real native loader, Boty, mapper, GMCP and
-- bag groups. No live character or profile is used. The office -> street
-- -> bank links are the public Nuln route nw,nw (return se,se); the small
-- swordsmith fixture is shared with test_fryderik_native.lua.
-- Run from chimera-main or chimera-501:
--   texlua ../chimera-paczki-github/tests/test_update_bank_native.lua
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local SOURCE=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/[^/]+$"),"run using the test file path")
local AREA="0f095c768720281b"
local ACTOR="Testbank"
local IDS={"6f2c03461c2f1438","265a3d02827b17ca","5ab986b649487e08","d6b592db212d39b3",
    "87dcd1a37f7480b0","1541e76cdf150002","b2d3beef1dc1760d","1b91bfe5e44cd714"}
local NAMES={"Poczta","Ulica","Ulica Polnocna","Sklep miecznika","Ulica Polnocna","Ulica Polnocna",
    "Ulica","Centralny Bank Imperialny - Filia w Nuln"}
local LINKS={
    [1]={nw=2},[2]={se=1,s=6,e=3,nw=8},[3]={w=2,s=5,sw=6},[4]={e=5},
    [5]={n=3,w=4,s=6,e=7},[6]={n=5,ne=3,e=7},[7]={n=3,nw=2,w=5},[8]={se=2},
}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",sw="poludniowy-zachod",
    se="poludniowy-wschod",nw="polnocny-zachod"}
local OPEN="otworz swoj plecak"
local CLOSE="zamknij swoj plecak"
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local TAKE_COINS="wez monety z swojego plecaka"
local COIN_TAKE_ACK="Bierzesz wiele srebrnych monet z otwartego skorzanego plecaka."
local DENOM_ACK="Twoje pieniadze zostaly zdenominowane."
local COIN_STOW_ACK="Wkladasz trzy zlote monety i siedem srebrnych monet do otwartego skorzanego plecaka."
local WORLD={}
for index,id in ipairs(IDS) do
    local exits={};for command,to in pairs(LINKS[index]) do exits[LONG[command]]=IDS[to] end
    WORLD[id]={id=id,name=NAMES[index],area="Nuln",area_id=AREA,
        indoors=index==1 or index==4 or index==8,terrain=index~=1 and index~=4 and index~=8 and "miasto" or nil,exits=exits}
end
T.module("test.world.update_bank",function()
    return {name="world",setup=function()
        return {room=function(id) return WORLD[id] end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return "test-bank" end,npcs=function()
                return {{name="Fryderik",short="wysoki mocny mezczyzna",title="Fryderik z Nuln",room=IDS[4]}}
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
            local commands={};for command in pairs(LINKS[at] or {}) do commands[#commands+1]=command end;table.sort(commands)
            for _,command in ipairs(commands) do local target=LINKS[at][command]
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
local function info(index,wrongBankHash)
    local room=WORLD[IDS[index]]
    return {id=index==8 and wrongBankHash and "0000000000000008" or room.id,name=room.name,
        area=room.area,area_id=AREA,indoors=room.indoors and 1 or 0,exits=room.exits}
end
local function count(command)
    local n=0;for _,sent in ipairs(M.sent) do if sent==command then n=n+1 end end;return n
end
local function waitFor(predicate,limit,why)
    for _=1,math.ceil((limit or 60)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function quiet(seconds,message)
    local before=#M.sent;M.advance(seconds or 0.2);T.eq(before,#M.sent,message or "unexpected command without own acknowledgement")
end
local function start(options)
    options=options or {}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.update_bank","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local C,api=record.api.engine,record.api
    local s={current=1,moves={},commands={},pending=0,bagOpen=false,parcel=nil,pickups=0,boards=0,
        delivered=false,rewardStows=0,denominations=0,bankStows=0,bankStowAcknowledged=false,coinLocation="bag"}
    function s:entities()
        local rows={}
        if self.current==4 then rows={{id="test-fryderik",name="Fryderik",title="Fryderik z Nuln",kind="npc",relation="neutral"}} end
        M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities=rows})
    end
    function s:takeAck() self.coinLocation="hands";M.line(COIN_TAKE_ACK) end
    function s:denomAck() self.denominated=true;M.line(DENOM_ACK) end
    function s:stowAck()
        self.bankStowAcknowledged=true;self.coinLocation="bag";M.line(COIN_STOW_ACK)
    end
    local wire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command);if M.denied~=before then return end
        wire(command,...)
        s.commands[#s.commands+1]={command=command,room=s.current,at=M.now}
        local to=LINKS[s.current][command]
        if to then
            s.pending=s.pending+1;T.eq(1,s.pending,"overlapping ordinary movement")
            s.moves[#s.moves+1]={from=s.current,to=to,command=command,at=M.now}
            if s.current==8 then T.eq(true,s.bankStowAcknowledged,"leave bank before own coin-storage ACK") end
            tempTimer(0.1,function()
                s.pending=s.pending-1;s.current=to;M.packet("Room.Info",info(to,options.wrongBankHash));s:entities()
                M.line(NAMES[to]..".")
            end)
        elseif command=="zerknij" then tempTimer(0.05,function()
            M.line(NAMES[s.current]..".")
            if s.current==1 then M.line("Jest tutaj jedno widoczne wyjscie: polnocny-zachod.") end
        end)
        elseif command=="przeczytaj tablice" then
            T.eq(1,s.current,"read parcel board only after returning to Nuln office")
            s.boards=s.boards+1
            if s.denominations>0 then T.eq(true,s.bankStowAcknowledged,"board read before bank settlement") end
            tempTimer(0.05,function()
                M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
                if options.offer and not s.delivered then M.line("1. Fryderik Miecznik miejscowa 1.00 kg 9 srebrnych monet [x1]") end
                M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
            end)
        elseif command=="wybierz paczke 1" then
            s.pickups=s.pickups+1;T.eq(1,s.pickups,"unexpected second parcel")
            tempTimer(0.05,function() s.parcel="hands";M.line("Bierzesz paczke przeznaczona dla: Fryderik Miecznik.") end)
        elseif command=="przedstaw sie" then tempTimer(0.05,function()
            if s.current==4 then M.line("Fryderik przedstawia sie jako:");M.line("Fryderik z Nuln.");s:entities() end
        end)
        elseif command=="oddaj paczke" then
            T.eq(4,s.current,"parcel delivery must reach Fryderik");T.eq("hands",s.parcel)
            tempTimer(0.05,function()
                s.delivered=true;s.parcel="delivered";M.line("Wrecasz paczke adresatowi.")
                M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
            end)
        elseif command==OPEN then tempTimer(0.05,function() s.bagOpen=true;M.line("Otwierasz skorzany plecak.") end)
        elseif command==CLOSE then tempTimer(0.05,function() s.bagOpen=false;M.line("Zamykasz skorzany plecak.") end)
        elseif command==STOW or command==TAKE then
            T.eq(true,s.bagOpen);T.eq(command==STOW and "hands" or "bag",s.parcel)
            tempTimer(0.05,function()
                s.parcel=command==STOW and "bag" or "hands"
                M.line(command==STOW and "Wkladasz paczke do otwartego skorzanego plecaka." or "Bierzesz paczke z otwartego skorzanego plecaka.")
            end)
        elseif command==TAKE_COINS then
            T.eq(8,s.current,"money withdrawal must happen at confirmed bank")
            T.eq(true,s.bagOpen);T.eq("bag",s.coinLocation)
            if options.offer then T.eq(1,s.rewardStows,"finish parcel reward before going to bank");T.eq(nil,C.job) end
            if not options.holdTake then tempTimer(0.05,function() s:takeAck() end) end
        elseif command=="zdenominuj" then
            T.eq(8,s.current);T.eq(IDS[8],app.loader.records.mapper.api.chimera_id(app.loader.records.mapper.api.current_room()))
            T.eq("hands",s.coinLocation,"denomination before own withdrawal ACK")
            s.denominations=s.denominations+1
            if not options.holdDenom then tempTimer(0.05,function() s:denomAck() end) end
        elseif command==COINS then
            T.eq(true,s.bagOpen)
            if s.current==8 then
                T.eq(true,s.denominated,"coin storage before own denomination ACK");s.bankStows=s.bankStows+1
                if not options.holdStow then tempTimer(0.05,function() s:stowAck() end) end
            else
                T.eq(true,s.delivered,"unexpected non-bank coin movement");s.rewardStows=s.rewardStows+1
                tempTimer(0.05,function() M.line("Wkladasz 9 srebrnych monet do otwartego skorzanego plecaka.") end)
            end
        end
    end
    local gmcpWire=sendGMCP
    _G.sendGMCP=function(command,...)
        gmcpWire(command,...)
        if command:find("Core.Supports.Add",1,true) and command:find("Chimera.Room.Entities",1,true) then
            tempTimer(0.01,function() s:entities() end)
        end
    end
    C.config.autoBackpack=false;C.config.roam=false;C:save()
    M.packet("Char.Info",{name=ACTOR,id="native-bank-test-character"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10});M.packet("Room.Info",info(1));s:entities()
    M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak")
    T.eq(true,app.loader.records.bags.api.configured("inne"));T.eq(true,app.loader.records.bags.api.configured("monety"))
    return app,app.loader.records.bots.api,C,api,s
end
local function forceStart()
    local before=#M.sent;M.input("/paczki bank teraz");T.eq(before,#M.sent,"stopped bot must only queue a bank visit")
    M.input("/paczki start")
end
local function finished(s)
    return s.bankStowAcknowledged and s.current==1 and s.boards>0
end
local function bankMoves(s)
    local out={};for _,move in ipairs(s.moves) do out[#out+1]=move.command end;return table.concat(out,",")
end

T.test("bank teraz during a held parcel settles delivery and reward before one native bank visit",function()
    local app,bots,C,api,s=start({offer=true})
    M.input("/paczki start")
    waitFor(function() return C.job~=nil end,20,"Fryderik parcel pickup")
    T.eq(false,C.job.delivered);T.eq(0,s.denominations)
    M.input("/paczki bank teraz")
    T.ok(C.job,"bank request must retain held parcel");T.eq("fryderik miecznik",C.norm(C.job.name))
    waitFor(function() return finished(s) and s.boards>=2 end,90,"bank visit after settled Fryderik delivery")
    T.eq(1,s.pickups);T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver);T.eq(1,s.rewardStows)
    T.eq(1,s.denominations);T.eq(1,s.bankStows);T.eq(1,count(TAKE_COINS));T.eq(0,count("zwroc paczke"))
    T.eq(nil,C.job);T.eq(false,s.bagOpen);T.eq("running",C.mode);T.ok(bots.status())
    T.eq("nw",s.moves[#s.moves-3].command);T.eq("nw",s.moves[#s.moves-2].command)
    T.eq("se",s.moves[#s.moves-1].command);T.eq("se",s.moves[#s.moves].command)
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("queued idle visit reaches exact bank hash and returns to the exact Nuln office before reading offers",function()
    local app,bots,C,api,s=start()
    T.eq(1800,C.config.bankSeconds);T.eq(true,C.config.bankEnabled)
    forceStart();waitFor(function() return finished(s) end,30,"forced bank visit")
    T.eq("nw,nw,se,se",bankMoves(s));T.eq(1,s.denominations);T.eq(1,s.bankStows)
    T.eq(1,count(TAKE_COINS));T.eq(1,count(COINS));T.eq(0,s.pickups)
    T.eq(IDS[1],app.loader.records.mapper.api.chimera_id(app.loader.records.mapper.api.current_room()))
    T.eq(false,s.bagOpen);T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.test("Gror's withdrawal, denomination and storage replies cannot advance our bank operation",function()
    local app,bots,C,api,s=start({holdTake=true,holdDenom=true,holdStow=true})
    forceStart();waitFor(function() return count(TAKE_COINS)>0 end,20,"bank withdrawal")
    M.line("Gror bierze wiele srebrnych monet z otwartego skorzanego plecaka.");quiet()
    T.eq(0,s.denominations);s:takeAck()
    waitFor(function() return s.denominations==1 end,10,"own withdrawal unlocks denomination")
    M.line("Pieniadze Grora zostaly zdenominowane.")
    M.line("Gror mowi: Twoje pieniadze zostaly zdenominowane.");quiet();T.eq(0,s.bankStows)
    s:denomAck();waitFor(function() return s.bankStows==1 end,10,"own denomination unlocks storage")
    M.line("Gror wklada trzy zlote monety i siedem srebrnych monet do otwartego skorzanego plecaka.");quiet()
    T.eq(8,s.current);T.eq(0,s.boards);s:stowAck()
    waitFor(function() return finished(s) end,20,"own coin storage unlocks return to office")
    T.eq("nw,nw,se,se",bankMoves(s));T.eq(1,s.denominations);T.eq(1,s.bankStows)
    T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
for _,stage in ipairs({"take","denom","stow"}) do
    T.test("missing "..stage.." acknowledgement pauses without further money commands, travel or parcel selection",function()
        local options={[stage=="take" and "holdTake" or stage=="denom" and "holdDenom" or "holdStow"]=true}
        local app,bots,C,api,s=start(options)
        forceStart();waitFor(function()
            if stage=="take" then return count(TAKE_COINS)==1 end
            if stage=="denom" then return s.denominations==1 end
            return s.bankStows==1
        end,20,"unacknowledged "..stage)
        local before=#M.sent;M.advance(45)
        T.eq(before,#M.sent);T.eq(stage=="take" and 0 or 1,s.denominations)
        T.eq(stage=="stow" and 1 or 0,s.bankStows);T.eq(false,s.bankStowAcknowledged)
        T.eq(8,s.current);T.eq(0,s.boards);T.eq(0,s.pickups)
        T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    end)
end
T.test("native STOP during denomination prevents every command after a late own acknowledgement",function()
    local app,bots,C,api,s=start({holdDenom=true})
    forceStart();waitFor(function() return s.denominations==1 end,20,"denomination before STOP")
    M.input("/bot stop");local before=#M.sent;s:denomAck();M.advance(45)
    T.eq(before,#M.sent);T.eq(0,s.bankStows);T.eq(8,s.current);T.eq(0,s.boards)
    T.eq(nil,bots.status());T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(0,#app.errors,M.text())
end)
T.test("bank-looking text with an unconfirmed GMCP hash never authorizes money commands",function()
    local app,bots,C,api,s=start({wrongBankHash=true})
    forceStart();waitFor(function() return s.current==8 end,20,"arrive at bank-looking room")
    M.advance(45);T.eq(0,count(TAKE_COINS));T.eq(0,s.denominations);T.eq(0,s.bankStows)
    T.eq(0,s.boards);T.eq(0,#app.errors,M.text());M.input("/bot stop")
end)
T.run()
