-- Portable recipient memory through the actual beta.13 loader and profile
-- storage. Each test profile owns its state; only the explicit JSON file is
-- transferred between profiles.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta"}
local LINKS={ [1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,e=5},[5]={w=4} }
local BASE_LINKS={}
for from,links in pairs(LINKS) do BASE_LINKS[from]={};for command,to in pairs(links) do BASE_LINKS[from][command]=to end end
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
    for id in pairs(LINKS) do LINKS[id]=nil end
    for from,links in pairs(BASE_LINKS) do LINKS[from]={};for command,to in pairs(links) do LINKS[from][command]=to end end
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

local FILE="chimera_paczki_baza.json"
local PERSON="Ferdynand Podrozny"
local POST="Poczta Eksportowa"
local function api(app) return app.loader.records.kurier_paczki.api end
local function memory(app) return assert(api(app).memory) end
local function json() return require("chimera.core.json") end
local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
local function seed(app,name,id,postal,npc)
    T.ok(memory(app).remember({recipient=name,roomHash=id,map=getRoomIDbyHash(id),verified=true,
        handover=true,reward=true,postal=postal==true,npc=npc}))
end
local function exportFixture()
    local app,bots,C,nav=start()
    seed(app,PERSON,IDS[3],false,{npcId="portable-ferdynand",name="Ferdynand",
        short="starszy podrozny mezczyzna",title="Ferdynand Podrozny, goniec"})
    seed(app,POST,IDS[5],true)
    C.actor="private-source-character"
    C.source=nav.source();C.job={name=PERSON,route=nav.resolve(PERSON,C.source),actor=C.actor,
        delivered=false,source=C.source,recipientConfirmed=true}
    C.stats.delivered=91;C.stats.gold=222;C.stopAt=100;C.config.maxKg=7.2;C:save();C:checkpoint()
    M.input("/paczki baza eksport")
    T.ok(M.file_exists(FILE),"export command must create a portable profile JSON file")
    local raw=read(getMudletHomeDir().."/"..FILE)
    return raw,app
end
local function noStateMutation(app,C,beforeSent,beforePackets)
    T.eq(nil,C.job);T.eq(0,C.stats.delivered);T.eq(0,C.stats.gold);T.eq(nil,C.stopAt)
    T.eq(0,api(app).checkpoint.count());T.eq(nil,app.loader.records.bots.api.status())
    T.eq(beforeSent,#M.sent);T.eq(beforePackets,#M.sent_gmcp);T.eq(0,#app.errors,M.text())
end

T.test("export contains only the learned recipient allowlist rather than source character run settings or earnings",function()
    local raw,app=exportFixture();local data=json().decode(raw)
    T.eq("chimera_paczki_baza",data.format);T.eq(1,data.version);T.eq(1,data.memory.schema)
    T.eq(2,count(data.memory.records));T.eq(2,memory(app).count())
    T.eq(nil,data.job);T.eq(nil,data.stats);T.eq(nil,data.actor);T.eq(nil,data.settings);T.eq(nil,data.config)
    T.eq(nil,data.checkpoint);T.eq(nil,data.biezacy_kurs);T.eq(nil,data.npcs)
    T.not_contains(raw,"private-source-character");T.not_contains(raw,'"map"');T.not_contains(raw,'"gold"')
    T.ok(data.memory.records["ferdynand podrozny"]);T.eq(true,data.memory.records["poczta eksportowa"].postal)
    T.eq("portable-ferdynand",data.memory.records["ferdynand podrozny"].npcId)
    T.eq("Ferdynand",data.memory.records["ferdynand podrozny"].name)
    T.eq("Ferdynand Podrozny, goniec",data.memory.records["ferdynand podrozny"].title)
    T.eq(IDS[3],data.memory.records["ferdynand podrozny"].roomHashes[1]);T.eq(0,#app.errors,M.text())
end)

T.test("copying the export into a different fresh profile imports only recipients and keeps local runtime defaults",function()
    local raw,source=exportFixture();local sourceHome=getMudletHomeDir();source:shutdown()
    local app,bots,C,nav=start();T.ok(sourceHome~=getMudletHomeDir())
    T.eq(0,memory(app).count());T.eq(true,C.config.autoBackpack);T.eq(3.2,C.config.maxKg)
    local beforeSent,beforePackets=#M.sent,#M.sent_gmcp
    M.write_file(FILE,raw);M.input("/paczki baza import")
    T.eq(2,memory(app).count());T.eq(IDS[3],memory(app).find(PERSON).roomHashes[1])
    T.eq("portable-ferdynand",memory(app).find(PERSON).npcId)
    T.eq("starszy podrozny mezczyzna",memory(app).find(PERSON).short)
    T.eq(true,memory(app).find(POST).postal);T.eq(3.2,C.config.maxKg);T.eq(true,C.config.autoBackpack)
    noStateMutation(app,C,beforeSent,beforePackets)
    local route=assert(nav.resolve(PERSON,nav.source()));T.eq(true,route.learned)
    T.eq(3,route.rooms[1]);T.eq(IDS[3],route.roomIds[3])
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    T.eq(2,memory(app).count());T.eq(nil,api(app).engine.job);T.eq(0,api(app).engine.stats.delivered)
    T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)

T.test("import merges existing local recipients idempotently and resolves portable hashes against another profile map numbers",function()
    local raw,source=exportFixture();source:shutdown()
    local app,bots,C,nav=start();seed(app,"Lokalny Adresat",IDS[4])
    M.map.rooms[103]=M.map.rooms[3];M.map.rooms[3]=nil;M.map.hashes[IDS[3]]=103
    for _,room in pairs(M.map.rooms) do
        for command,target in pairs(room.exits or {}) do if target==3 then room.exits[command]=103 end end
        for command,target in pairs(room.specials or {}) do if target==3 then room.specials[command]=103 end end
    end
    LINKS[103]=LINKS[3];LINKS[3]=nil
    for _,links in pairs(LINKS) do for command,target in pairs(links) do if target==3 then links[command]=103 end end end
    M.write_file(FILE,raw);local beforeSent,beforePackets=#M.sent,#M.sent_gmcp
    M.input("/paczki baza import");T.eq(3,memory(app).count());T.ok(memory(app).find("Lokalny Adresat"))
    local first=json().encode(memory(app).exportState())
    M.input("/paczki baza import");T.eq(3,memory(app).count())
    T.eq(first,json().encode(memory(app).exportState()),"copying the same file twice must not add delivery counts")
    local route=assert(nav.resolve(PERSON,nav.source()));T.eq(103,route.rooms[1]);T.eq(IDS[3],route.roomIds[103])
    T.eq(nil,route.roomIds[3]);noStateMutation(app,C,beforeSent,beforePackets)
    LINKS[3]=LINKS[103];LINKS[103]=nil
    for _,links in pairs(LINKS) do for command,target in pairs(links) do if target==103 then links[command]=3 end end end
end)

T.test("invalid JSON unsupported format and conflicting recipient kind never partially import or execute code",function()
    local raw,source=exportFixture();source:shutdown()
    local app,bots,C=start();seed(app,PERSON,IDS[4],true)
    local previous=json().encode(memory(app).exportState());local valid=json().decode(raw)
    local badFormat=json().decode(raw);badFormat.format="lua_program"
    local badVersion=json().decode(raw);badVersion.version=2
    local badSchema=json().decode(raw);badSchema.memory.schema=2
    local badRecord=json().decode(raw);badRecord.memory.records["broken"]={recipient="Broken",roomHashes={},count=1,last=0}
    local cases={"not JSON",'portable_import_executed = true; return {}',json().encode(badFormat),
        json().encode(badVersion),json().encode(badSchema),json().encode(badRecord),json().encode(valid)}
    local beforeSent,beforePackets=#M.sent,#M.sent_gmcp
    _G.portable_import_executed=nil
    for _,body in ipairs(cases) do
        M.write_file(FILE,body);M.input("/paczki baza import")
        T.eq(previous,json().encode(memory(app).exportState()));T.eq(1,memory(app).count())
        T.eq(nil,_G.portable_import_executed)
    end
    noStateMutation(app,C,beforeSent,beforePackets)
end)

T.test("an explicitly quoted JSON path with spaces can be imported without touching other files",function()
    local raw,source=exportFixture();source:shutdown()
    local app,bots,C=start();local path=M.write_file("baza z innego profilu.json",raw)
    local beforeSent,beforePackets=#M.sent,#M.sent_gmcp
    M.input('/paczki baza import "'..path..'"')
    T.eq(2,memory(app).count());T.eq(raw,read(path));T.eq(false,M.file_exists(FILE))
    noStateMutation(app,C,beforeSent,beforePackets)
end)

T.test("running resting and deferred GMCP startup refuse imports and exports until explicitly stopped",function()
    local raw,source=exportFixture();source:shutdown()
    for _,kind in ipairs({"running","resting","session_wait"}) do
        local app,bots,C=start();M.write_file(FILE,raw)
        if kind=="session_wait" then
            C:disconnected();M.packet("Core.Goodbye",{});M.input("/paczki wznow")
            T.eq(true,api(app).sessionWaiting())
        else
            M.input("/bot paczki");T.ok(bots.status())
            if kind=="resting" then C:rest("test portable import guard");T.eq("resting",C.mode) end
        end
        M.input("/paczki baza import");T.eq(0,memory(app).count())
        M.input("/paczki baza eksport");T.eq(raw,read(getMudletHomeDir().."/"..FILE))
        M.input("/paczki stop");T.eq(false,api(app).sessionWaiting());T.eq(nil,bots.status())
        M.input("/paczki baza import");T.eq(2,memory(app).count());T.eq(0,#app.errors,M.text())
    end
end)

T.run()
