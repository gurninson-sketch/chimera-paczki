-- Regression of an imported room-only Torquato delivery in Campogrotta.
-- Selected hashes, room names and ordinary exits are from the public world
-- data in Chimera 5.0.1. The profile world API deliberately returns nil:
-- urban boundaries must come from the shipped public city metadata.
-- Run from either chimera-main or chimera-501.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local FULL="Torquato di Assemani"
local SHORT="wyniosly bialowlosy mezczyzna"
local AREA="fe3973d382c34894"
local IDS={"269ff0c7899bbd55","d297e64b2288c337","06c7bfc0793a5a4b","b86129bbefdb9e71",
    "ff91072fd68491f6","ef767d747f0a4d13","32a0096f3c307d7f"}
local NAMES={"Poczta w Campogrotta","Polnocno-zachodnia czesc placu","Poludniowo-zachodnia czesc placu",
    "Kuznia","Niewielki sklepik","Plac","Poludniowo-wschodnia czesc placu"}
local LINKS={
    [1]={sw=2},[2]={ne=1,s=3,e=6,se=7},[3]={n=2,w=4,se=5,ne=6,e=7},
    [4]={e=3},[5]={nw=3},[6]={w=2,sw=3,s=7},[7]={n=6,nw=2,w=3},
}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",sw="poludniowy-zachod",
    se="poludniowy-wschod",nw="polnocny-zachod"}
local catalogueMode="unique"
T.module("test.world.torquato",function()
    return {name="world",setup=function()
        return {room=function() return nil end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return nil end,npcs=function()
                local rows={{name="Boreg",short="szeroki brodaty krasnolud",title="Boreg, kowal",room=IDS[4]}}
                if catalogueMode~="none" then
                    local title=catalogueMode=="prefix" and (FULL.." Senior, dostojnik") or (FULL..", dostojnik")
                    rows[#rows+1]={name="Torquato",short=SHORT,title=title,room=IDS[4]}
                    if catalogueMode=="ambiguous" then rows[#rows+1]={name="Torquato",short="wysoki siwy mezczyzna",
                        title=FULL..", drugi dostojnik",room=IDS[5]} end
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
        indoors=(index==1 or index==4 or index==5) and 1 or 0,exits=exits}
end
local function count(command)
    local n=0;for _,sent in ipairs(M.sent) do if sent==command then n=n+1 end end;return n
end
local function waitFor(predicate,limit,why)
    for _=1,math.ceil((limit or 60)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function start(options)
    options=options or {};catalogueMode=options.catalogue or "unique"
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.torquato","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local C,api=record.api.engine,record.api
    local server={current=1,npcAt=options.npcAt or 5,known=options.known~=false,moves={},gifts={},pending=0,
        noIntroduction=options.noIntroduction==true,introductions={},fullProof=false}
    function server:entities()
        local rows={}
        if self.current==4 then rows[#rows+1]={id="camp-boreg",name="Boreg",kind="npc",relation="neutral"} end
        if self.current==self.npcAt then rows[#rows+1]={id="camp-torquato",name=self.known and "Torquato" or SHORT,
            kind="npc",relation="neutral"} end
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
            if server.current==server.npcAt and not server.noIntroduction then
                tempTimer(0.05,function()
                    local prefix=server.known and "Torquato" or "Wyniosly bialowlosy mezczyzna"
                    M.line(prefix.." przedstawia sie jako:");M.line(FULL..".")
                    server.known,server.fullProof=true,true;server:entities()
                end)
            elseif server.current==4 then
                tempTimer(0.05,function() M.line("Boreg przedstawia sie jako:");M.line("Boreg, kowal.");server:entities() end)
            end
        elseif command=="oddaj paczke" then
            server.gifts[#server.gifts+1]={room=server.current,known=server.known,fullProof=server.fullProof,at=M.now}
            tempTimer(0.05,function()
                if server.current==server.npcAt then M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.");M.line("Musisz odnalezc "..FULL.." i wreczyc mu paczke osobiscie.") end
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
    M.packet("Char.Info",{name="Morrid",id="camp-courier"});M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    M.packet("Room.Info",info(1));server:entities()
    return app,app.loader.records.bots.api,C,api.navigator,server,api
end
local function importRoomOnly(api)
    T.ok(api.memory.remember({recipient=FULL,roomHash=IDS[4],map=4,verified=true,handover=true,reward=true}))
    local old=api.memory.find(FULL);T.eq(nil,old.npcId);T.eq(nil,old.name)
    M.input('/paczki baza eksport "torquato_room_only.json"')
    T.ok(api.memory.clear());T.eq(0,api.memory.count())
    M.input('/paczki baza import "torquato_room_only.json"')
    T.eq(1,api.memory.count());local imported=api.memory.find(FULL)
    T.eq(nil,imported.npcId);T.eq(nil,imported.name);T.eq(IDS[4],imported.roomHashes[1])
end
local function begin(server,C)
    C.stats.delivered=7;C.stats.silver=21
    M.input("/paczki start 1");waitFor(function() return count("przeczytaj tablice")>0 end,15,"read Campogrotta board")
    M.line("Przesylki dostepne dla Agente Postalle di Tilea:")
    M.line("1. "..FULL.." miejscowa 1.70 kg 9 srebrnych monet [x3]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return count("wybierz paczke 1")>0 end,15,"select imported recipient parcel")
    M.line("Bierzesz paczke przeznaczona dla: "..FULL..".")
end
local function finish(app,bots,C,server)
    waitFor(function() return C.stats.delivered==8 end,150,"autonomous Torquato delivery")
    waitFor(function() return bots.status()==nil end,60,"return after limited course")
    T.eq(8,C.stats.delivered);T.eq(30,C.stats.silver);T.eq("stopped",C.mode);T.eq(1,count("wybierz paczke 1"))
    T.eq(1,#server.gifts);T.eq(5,server.gifts[1].room,"Boreg at the old smithy cannot receive the target parcel")
    T.eq(IDS[1],C.source.id);T.eq(1,server.current);T.eq(0,#app.errors,M.text())
end
T.test("an exported room-only memory gains the unique current catalogue identity and finds Torquato beyond Boreg without world.db",function()
    local app,bots,C,nav,s,api=start();importRoomOnly(api)
    local route=assert(nav.resolve(FULL,nav.current()))
    T.ok(route.identityUpgraded,"room-only memory was not enriched from the exact current catalogue identity")
    T.ok(route.npcId);T.eq("Torquato",route.npcName)
    local status=nav.searchStatus(route);T.eq("city",status.mode,"public city metadata did not enable search")
    T.eq("bundled",status.metadataSource,"fixture accidentally relied on profile world.db")
    begin(s,C);finish(app,bots,C,s)
    local learned=api.memory.find(FULL);T.ok(learned.npcId);T.eq("Torquato",learned.name);T.eq(IDS[5],learned.roomHashes[1])
end)
T.test("an imported room-only address without a current NPC entry patrols and learns the exact identity through introduction",function()
    local app,bots,C,nav,s,api=start({catalogue="none",known=false});importRoomOnly(api)
    T.eq(0,#app.loader.records.npcs.api.find("Torquato"))
    begin(s,C);finish(app,bots,C,s)
    T.eq(true,s.gifts[1].fullProof,"a short or first name alone authorized a newly discovered recipient")
    T.eq(true,s.gifts[1].known)
    local records=app.loader.records.npcs.api.find("Torquato");T.eq(1,#records)
    T.eq(FULL,records[1].title)
    local learned=api.memory.find(FULL);T.ok(learned.npcId);T.eq("Torquato",learned.name)
end)
T.test("the installed version and public city fallback are visible in side-effect-free diagnostics",function()
    local app,bots,C,nav,s,api=start();importRoomOnly(api)
    M.input("/paczki paczka "..FULL)
    local before=#M.sent;M.clear_output();M.input("/paczki");M.input("/paczki diagnostyka")
    T.eq(before,#M.sent,"diagnostics sent game commands")
    T.contains(M.text(),"1.5.21");T.contains(M.text(),"Campogrotta");T.contains(M.text(),"bundled")
    T.eq("1.5.21",api.version);T.eq("1.5.21",C.version);T.eq(0,#app.errors,M.text())
end)
T.test("partial or conflicting stored identities are not rebound to a convenient current Torquato record",function()
    for _,kind in ipairs({"partial","conflict"}) do
        local app,bots,C,nav,s,api=start()
        local original=api.memory.find
        local npc=app.loader.records.npcs.api.find("Torquato")[1]
        if kind=="partial" then
            -- Defensive check for incomplete legacy providers; strict portable
            -- imports reject this shape before it reaches the navigator.
            api.memory.find=function() return {recipient=FULL,roomHashes={IDS[4]},count=1,last=1,npcId=npc.id} end
        else
            T.ok(api.memory.remember({recipient=FULL,roomHash=IDS[4],map=4,verified=true,handover=true,reward=true,
                npc={npcId="wrong-npc-id",name="Boreg",short="szeroki brodaty krasnolud",title="Boreg, kowal"}}))
            M.input('/paczki baza eksport "torquato_conflicting_identity.json"')
            T.ok(api.memory.clear());M.input('/paczki baza import "torquato_conflicting_identity.json"')
            T.eq("Boreg",api.memory.find(FULL).name)
        end
        local route=assert(nav.resolve(FULL,nav.current()))
        T.ok(not route.identityUpgraded,kind.." identity was automatically rebound")
        T.eq(false,nav.canSearchFor(route),kind.." imported identity enabled city patrol")
        api.memory.find=original;T.eq(0,#app.errors,M.text())
    end
end)
T.test("ambiguous full titles and the Torquato Senior prefix do not enrich room-only history",function()
    for _,mode in ipairs({"ambiguous","prefix"}) do
        local app,bots,C,nav,s,api=start({catalogue=mode});importRoomOnly(api)
        local route=assert(nav.resolve(FULL,nav.current()))
        T.ok(not route.identityUpgraded,mode.." title incorrectly upgraded the recipient")
        T.eq(nil,route.npcId);T.eq(nil,route.npcName)
        T.eq(0,#s.gifts);T.eq(0,#app.errors,M.text())
    end
end)
T.test("a newly searched room-only target cannot be gifted to using an unconfirmed first name",function()
    local app,bots,C,nav,s,api=start({catalogue="none",known=true,noIntroduction=true});importRoomOnly(api)
    begin(s,C);M.advance(180)
    T.eq(0,#s.gifts,"an unconfirmed Torquato first name authorized a city handover")
    T.eq(7,C.stats.delivered);T.eq(21,C.stats.silver)
    T.eq(nil,api.memory.find(FULL).npcId)
    M.input("/bot stop");local before=#M.sent;M.advance(45);T.eq(before,#M.sent)
    T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
