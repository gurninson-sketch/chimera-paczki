-- Postal classification and per-offer diagnostics through actual native
-- loader, GMCP, Boty and production courier. Narrow world fixture copied
-- from test_native_map.lua, with the Nuln office added at runtime map room6.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local wallTime=os.time;local epoch=wallTime()
os.time=function(date) if date then return wallTime(date) end;return epoch+math.floor((M.now or 1000)-1000) end
local ROOT=arg[0]:gsub("\\","/"):match("^(.*)/tests/test_update_quota_native%.lua$") or ".."
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd","6f2c03461c2f1438"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta","Poczta"}
local LINKS={ [1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,e=5},[5]={w=4,e=6},[6]={w=5} }
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
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read(ROOT.."/chimera_wtyczki/chimera_paczki/"..name))
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
local function rows(lines)
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    for _,text in ipairs(lines) do M.line(text) end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
end
local function launch()
    M.input("/paczki limit 6,2")
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend())
end
local function diagnostic(C,number)
    for _,row in ipairs(C.offerDiagnostics or {}) do if row.number==number then return row end end
    error("missing diagnostic for offer "..number)
end
local function sourceId(source) return type(source)=="table" and source.id or source end
local REFUSAL="Urzednik zaglada do rejestru i kreci glowa: w ciagu ostatniej godziny wydal juz postaciom twojego konta 30 przesylek miejscowych. Kolejna bedzie za 2 minuty."
local LOCAL="1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x9]"
local INTERCITY="2. Poczta w Bissingen miedzymiastowa 1.00 kg 20 zlotych monet [x9]"
T.test("native pickup quota denial falls back to the other available kind without a false parcel or pause",function()
    local app,bots,C=start();launch();rows({LOCAL,INTERCITY})
    T.eq("wybierz paczke 2",nextSend());T.eq(true,C.awaitingPickup)
    M.line(REFUSAL:gsub("miejscowych","miedzymiastowych"))
    T.eq(false,C.awaitingPickup);T.eq(nil,C.job);T.eq(nil,next(C.rejected))
    T.eq("przeczytaj tablice",nextSend());rows({LOCAL,INTERCITY})
    T.eq("wybierz paczke 1",nextSend());T.eq("miejscowa",C.selected.kind)
    T.eq("quota",diagnostic(C,2).category);T.eq("running",C.mode)
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("native quota wait survives watchdog duration and reads a fresh board only at the deadline",function()
    local app,bots,C=start();launch();rows({LOCAL});T.eq("wybierz paczke 1",nextSend())
    M.line(REFUSAL);T.eq("przeczytaj tablice",nextSend());rows({LOCAL});M.advance(2)
    T.eq("waitingQuota",C.phase);T.eq("running",C.mode);T.ok(bots.status())
    local before=#M.sent;local seconds=C:pickupGate("miejscowa")
    M.advance(seconds-1);T.eq(before,#M.sent,table.concat(M.sent," | "));T.eq(nil,C.job);T.eq(false,C.awaitingPickup)
    M.advance(1.1);T.eq("przeczytaj tablice",M.sent[#M.sent]);T.eq(before+1,#M.sent)
    rows({LOCAL});T.eq("wybierz paczke 1",nextSend())
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.test("STOP late quota reply and actual loader reload preserve cooldown without restarting",function()
    local app,bots,C=start();launch();rows({LOCAL});T.eq("wybierz paczke 1",nextSend())
    M.input("/bot stop");M.line(REFUSAL);local before=#M.sent;M.advance(2)
    T.eq(false,C.awaitingPickup);T.eq(nil,bots.status());T.eq(before,#M.sent)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    C=app.loader.records.kurier_paczki.api.engine
    local delay=C:pickupGate("miejscowa");T.ok(delay>100 and delay<=122)
    M.advance(15);T.eq(before,#M.sent);T.eq(nil,bots.status())
    M.input("/paczki wznow");T.eq("przeczytaj tablice",nextSend());rows({LOCAL});M.advance(2)
    T.eq("waitingQuota",C.phase);M.input("/bot stop");before=#M.sent
    M.advance(150);T.eq(before,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("only own acknowledged native pickup counts once after duplicate text",function()
    local app,bots,C=start();launch();rows({LOCAL});T.eq("wybierz paczke 1",nextSend())
    M.line("Gror bierze paczke z tablicy.");local _,before=C:pickupGate("miejscowa");T.eq(0,before)
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    local _,after=C:pickupGate("miejscowa");T.eq(1,after)
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.run()
