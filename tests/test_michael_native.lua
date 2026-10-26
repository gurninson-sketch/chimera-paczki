-- Regression of the two 2026-10-25 Michael delivery logs.
-- The board omits the Don honorific present in older confirmed introductions.
-- Evidence: 2026-10-25#10-21-38.txt6380-6381 and09-55-15.txt8056-8057.
-- The latest failures do not expose the stored title; this fixture replays
-- that observed title shape and the latest exact town-hall destination.
-- The descriptor is synthetic; the title, selected hashes and exits are sourced.
-- Selected hashes, room names and ordinary exits are from the public world
-- data in Chimera 5.0.1. The profile world API deliberately returns nil:
-- urban boundaries must come from the shipped public city metadata.
-- Run from either chimera-main or chimera-501.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local FULL="Michael Tommasino"
local TITLE="Don "..FULL..", Burmistrz Campogrotty, czlowiek"
local SHORT="elegancki starszy mezczyzna"
local AREA="fe3973d382c34894"
local IDS={"269ff0c7899bbd55","d297e64b2288c337","ef767d747f0a4d13","d6317d1918d8624b",
    "6a6fccbc8acdbdd6","06c7bfc0793a5a4b","32a0096f3c307d7f"}
local NAMES={"Poczta w Campogrotta","Polnocno-zachodnia czesc placu","Plac",
    "Glowny hal w ratuszu","Miasteczko Campogrotta","Poludniowo-zachodnia czesc placu","Poludniowo-wschodnia czesc placu"}
local LINKS={
    [1]={sw=2},[2]={ne=1,s=6,e=3,se=7},[3]={w=2,e=5,s=7,sw=6},
    [4]={w=5},[5]={w=3,e=4},[6]={n=2,ne=3,e=7},[7]={n=3,nw=2,w=6},
}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",sw="poludniowy-zachod",
    se="poludniowy-wschod",nw="polnocny-zachod"}
local catalogueMode="unique"
T.module("test.world.michael",function()
    return {name="world",setup=function()
        return {room=function() return nil end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return nil end,npcs=function()
                local rows={{name="Torquato",short="wyniosly bialowlosy mezczyzna",title="Torquato di Assemani",room=IDS[5]}}
                if catalogueMode~="none" then
                    local title=catalogueMode=="prefix" and "Don "..FULL.." Senior" or
                        (catalogueMode=="wrong" and "Don Michael Nowak, Burmistrz Campogrotty" or TITLE)
                    rows[#rows+1]={name="Michael",short=SHORT,title=title,room=IDS[4]}
                    if catalogueMode=="ambiguous" then rows[#rows+1]={name="Michael",short="stary siwy krasnolud",
                        title="Don "..FULL.." ze Starego Swiata",room=IDS[5]} end
                end
                return rows
            end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua",
        "postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
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
local function info(index)
    local exits={};for command,to in pairs(LINKS[index]) do exits[LONG[command]]=IDS[to] end
    return {id=IDS[index],name=NAMES[index],area="Campogrotta",area_id=AREA,
        indoors=(index==1 or index==4) and 1 or 0,exits=exits}
end
local function count(command)
    local n=0;for _,sent in ipairs(M.sent) do if sent==command then n=n+1 end end;return n
end
local function waitFor(predicate,limit,why)
    for _=1,math.ceil((limit or 60)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local OPEN="otworz swoj plecak"
local CLOSE="zamknij swoj plecak"
local function start(options)
    options=options or {};catalogueMode=options.catalogue or "unique"
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.michael","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local C,api=record.api.engine,record.api
    local server={current=1,known=options.known~=false,moves={},gifts={},pending=0,
        noIntroduction=options.noIntroduction==true,introductions={},fullProof=false,title=options.title or TITLE,
        bags=options.bags==true,parcel="hands",bagOpen=false,money=2,rewardStows=0,rewarded=false,rewardReplies=0}
    function server:entities()
        local rows={}
        if self.current==5 then rows[#rows+1]={id="camp-torquato",name="Torquato",kind="npc",relation="neutral"} end
        if self.current==4 then rows[#rows+1]={id="camp-michael",name=self.known and "Michael" or SHORT,
            title=options.liveTitle and self.title or nil,kind="npc",relation="neutral"} end
        M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities=rows})
    end
    local wire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command);if M.denied~=before then return end
        wire(command,...)
        local to=LINKS[server.current][command]
        if to then
            server.pending=server.pending+1;T.eq(1,server.pending,"overlapping ordinary movement")
            server.moves[#server.moves+1]={from=server.current,to=to,at=M.now,command=command}
            tempTimer(0.1,function()
                server.pending=server.pending-1;server.current=to;M.packet("Room.Info",info(to));server:entities();M.line(NAMES[to]..".")
            end)
        elseif command=="przedstaw sie" then
            server.introductions[#server.introductions+1]={room=server.current,at=M.now}
            if server.current==4 and not server.noIntroduction then
                tempTimer(0.05,function()
                    local prefix=server.known and "Michael" or "Elegancki starszy mezczyzna"
                    M.line(prefix.." przedstawia sie jako:");M.line(server.title..".")
                    server.known,server.fullProof=true,true;server:entities()
                end)
            elseif server.current==5 then
                tempTimer(0.05,function() M.line("Torquato przedstawia sie jako:");M.line("Torquato di Assemani.");server:entities() end)
            end
        elseif command=="oddaj paczke" then
            T.eq("hands",server.parcel,"a parcel still inside the backpack was gifted")
            server.gifts[#server.gifts+1]={room=server.current,known=server.known,fullProof=server.fullProof,at=M.now}
            tempTimer(0.05,function()
                if server.current==4 then
                    M.line("Wrecasz paczke adresatowi.");server.parcel="delivered";server.rewarded=true;server.money=server.money+10
                    server.rewardReplies=server.rewardReplies+1
                    M.line("Adresat wrecza ci 10 srebrnych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.");M.line("Musisz odnalezc "..FULL.." i wreczyc mu paczke osobiscie.") end
            end)
        elseif command==OPEN then tempTimer(0.05,function() server.bagOpen=true;M.line("Otwierasz skorzany plecak.") end)
        elseif command==CLOSE then tempTimer(0.05,function() server.bagOpen=false;M.line("Zamykasz skorzany plecak.") end)
        elseif command==STOW or command==TAKE then
            T.eq(true,server.bagOpen,"parcel movement must open the backpack")
            T.eq(command==STOW and "hands" or "bag",server.parcel)
            tempTimer(0.05,function()
                server.parcel=command==STOW and "bag" or "hands"
                M.line(command==STOW and "Wkladasz paczke do otwartego skorzanego plecaka." or "Bierzesz paczke z otwartego skorzanego plecaka.")
            end)
        elseif command==COINS then
            T.eq(true,server.bagOpen,"coin movement must open the backpack")
            T.ok(server.money>0,"fixture received a duplicate coin transfer")
            tempTimer(0.05,function()
                if server.rewarded then server.rewardStows=server.rewardStows+1 end
                M.line("Wkladasz "..server.money.." srebrnych monet do otwartego skorzanego plecaka.");server.money=0
            end)
        end
    end
    local gmcpWire=sendGMCP
    _G.sendGMCP=function(command,...)
        gmcpWire(command,...)
        if command:find("Core.Supports.Add",1,true) and command:find("Chimera.Room.Entities",1,true) then
            tempTimer(0.01,function() server:entities() end)
        end
    end
    C.config.autoBackpack=false;C:save()
    M.packet("Char.Info",{name=options.actor or "Yarrim",id="michael-courier-"..(options.actor or "Yarrim")})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10});M.packet("Room.Info",info(1));server:entities()
    if server.bags then M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak") end
    return app,app.loader.records.bots.api,C,api.navigator,server,api
end
local function importMemory(api,npcs,roomOnly)
    local npc=npcs.find("Michael")[1]
    T.ok(api.memory.remember({recipient=FULL,roomHash=IDS[4],map=4,verified=true,handover=true,reward=true,
        npc=not roomOnly and {npcId=npc.id,name=npc.name,short=npc.short,title=TITLE} or nil}))
    M.input('/paczki baza eksport "michael_delivery.json"');T.ok(api.memory.clear())
    M.input('/paczki baza import "michael_delivery.json"');T.eq(1,api.memory.count())
    local imported=api.memory.find(FULL);T.eq(IDS[4],imported.roomHashes[1])
    if roomOnly then T.eq(nil,imported.npcId) else T.eq(TITLE,imported.title) end
end
local function begin(server,C)
    C.stats.delivered=7;C.stats.silver=21
    M.input("/paczki start 1");waitFor(function() return count("przeczytaj tablice")>0 end,15,"read Campogrotta board")
    M.line("Przesylki dostepne dla Agente Postalle di Tilea:")
    M.line("1. "..FULL.." miejscowa 2.00 kg 10 srebrnych monet [x3]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return count("wybierz paczke 1")>0 end,15,"select Michael parcel")
    M.line("Bierzesz paczke przeznaczona dla: "..FULL..".")
end
local function finish(app,bots,C,server,api)
    waitFor(function() return C.stats.delivered==8 end,90,"Michael was present but the courier left the town hall")
    waitFor(function() return bots.status()==nil end,60,"return after limited course")
    T.eq(8,C.stats.delivered);T.eq(31,C.stats.silver);T.eq("stopped",C.mode);T.eq(1,count("wybierz paczke 1"))
    T.eq(1,#server.gifts);T.eq(4,server.gifts[1].room);T.eq(1,server.rewardReplies);T.eq(nil,C.job,"the completed course remained active")
    T.eq(IDS[1],C.source.id);T.eq(1,server.current)
    local firstSmithy,giftAt
    for _,move in ipairs(server.moves) do if move.to==4 and not firstSmithy then firstSmithy=move.at end end
    giftAt=server.gifts[1].at;T.ok(firstSmithy and giftAt>=firstSmithy)
    for _,move in ipairs(server.moves) do T.ok(not (move.from==4 and move.at<giftAt),"left the present recipient to patrol the city") end
    T.eq(0,#app.errors,M.text())
    if server.bags then
        T.eq(1,count(STOW));T.eq(1,count(TAKE));T.eq(1,server.rewardStows)
        T.eq(false,server.bagOpen);T.eq(0,server.money);T.eq("delivered",server.parcel)
        T.ok(not C.job or not C.job.coinsPending,"reward coins remain unsettled")
    end
    local learned=api.memory.find(FULL);T.eq("Michael",learned.name);T.ok(learned.npcId);T.eq(IDS[4],learned.roomHashes[1])
end
for _,actor in ipairs({"Yarrim","Morrid"}) do
    T.test(actor..": imported Michael identity with Don honorific delivers at the first town hall visit and settles backpack coins",function()
        local app,bots,C,nav,s,api=start({actor=actor,bags=true})
        importMemory(api,app.loader.records.npcs.api,false)
        local route=assert(nav.resolve(FULL,nav.current()))
        T.eq("city",nav.searchStatus(route).mode,"valid full title was treated as another recipient")
        begin(s,C);finish(app,bots,C,s,api)
    end)
    T.test(actor..": room-only import enriches from unique honorific catalogue title and delivers without profile world.db",function()
        local app,bots,C,nav,s,api=start({actor=actor})
        importMemory(api,app.loader.records.npcs.api,true)
        local route=assert(nav.resolve(FULL,nav.current()));T.eq(true,route.identityUpgraded)
        T.eq("Michael",route.npcName);T.eq("bundled",nav.searchStatus(route).metadataSource)
        begin(s,C);finish(app,bots,C,s,api)
    end)
    T.test(actor..": first meeting introduces Michael and binds the Don title before handover",function()
        local app,bots,C,nav,s,api=start({actor=actor,catalogue="none",known=false})
        importMemory(api,app.loader.records.npcs.api,true)
        begin(s,C);finish(app,bots,C,s,api)
        T.eq(true,s.gifts[1].fullProof);T.eq(true,s.gifts[1].known)
    end)
end
T.test("different surnames and Senior prefixes remain invalid for room-only Michael history",function()
    for _,mode in ipairs({"wrong","prefix"}) do
        local app,bots,C,nav,s,api=start({catalogue=mode,title=mode=="wrong" and "Don Michael Nowak, Burmistrz Campogrotty" or "Don "..FULL.." Senior"})
        importMemory(api,app.loader.records.npcs.api,true)
        local route=assert(nav.resolve(FULL,nav.current()));T.ok(not route.identityUpgraded,mode.." enriched Michael identity")
        begin(s,C);M.advance(100);T.eq(0,#s.gifts,mode.." authorized a gift")
        M.input("/bot stop");T.eq(0,#app.errors,M.text())
    end
end)
T.test("two distinct Michael identities carrying the Don honorific remain ambiguous",function()
    local app,bots,C,nav,s,api=start({catalogue="ambiguous",noIntroduction=true})
    importMemory(api,app.loader.records.npcs.api,true)
    local route=assert(nav.resolve(FULL,nav.current()));T.ok(not route.identityUpgraded)
    begin(s,C);M.advance(100);T.eq(0,#s.gifts,"two compatible titles authorized a guessed recipient")
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("a conflicting current entity title defeats even a stored legitimate Michael identity",function()
    local app,bots,C,nav,s,api=start({title="Don Michael Nowak, Burmistrz Campogrotty",liveTitle=true,noIntroduction=true})
    importMemory(api,app.loader.records.npcs.api,false)
    begin(s,C);M.advance(100);T.eq(0,#s.gifts,"foreign live title authorized stored first-name fallback")
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.run()
