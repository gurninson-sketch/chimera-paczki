-- Integration through actual beta.13 loader, NPC catalogue, mapper and bot
-- manager, using the production courier journey/road controller. Only the
-- Mudlet/map/server and world rows are fake.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta"}
local LINKS={ [1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,e=5},[5]={w=4} }
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

-- Speed contracts use the same production loader/controller fixture as the map
-- integration tests. The fake server confirms each movement after 0.1 s.
local function close(expected,actual,message)
    T.ok(math.abs(expected-actual)<0.001,(message or "time mismatch")..": expected "..expected..", got "..actual)
end
local function walkerDelay(app,seconds)
    local ok,why=app.config:set("walker","opoznienie",seconds)
    T.ok(ok,why)
end
local function noSendFor(seconds,message)
    local count=#M.sent
    M.advance(seconds)
    T.eq(count,#M.sent,message or "unexpected early send")
end
local function recordSends()
    local records,wire={},send
    _G.send=function(command,...)
        local before=#M.sent
        wire(command,...)
        if #M.sent>before then records[#records+1]={command=command,at=M.now} end
    end
    return records
end
local function stopAndCheck(app,bots,C)
    M.input("/bot stop")
    T.eq(nil,bots.status());T.eq("stopped",C.mode)
    T.eq(0,#app.errors,M.text())
end

T.test("walker delay is inherited for the first action and every road acknowledgement",function()
    local app,bots,C,nav,server=start()
    walkerDelay(app,2)
    T.eq("walker",C.config.tempoSource);close(2,C:delay())
    local sends=recordSends();local began=M.now
    M.input("/paczki start 1")
    noSendFor(1.99,"first board action must inherit the 2-second walker delay")
    M.advance(0.02)
    T.eq("przeczytaj tablice",M.sent[#M.sent]);close(began+2,sends[1].at)
    board(NPC_ROW)
    noSendFor(1.99,"board selection must inherit the walker delay")
    M.advance(0.02);T.eq("wybierz paczke 1",M.sent[#M.sent])
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    if M.sent[#M.sent]~="wyjscie" then T.eq("wyjscie",nextSend(5)) end
    local first=sends[#sends].at
    T.eq("wyjscie",sends[#sends].command)
    local secondAt=first+2.1
    noSendFor(secondAt-M.now-0.01,"second movement must wait 2 seconds after the 0.1-second acknowledgement")
    M.advance(0.02)
    T.eq("n",M.sent[#M.sent]);close(secondAt,sends[#sends].at)
    stopAndCheck(app,bots,C)
end)

T.test("explicit comma tempo and opoznienie alias override a slower walker",function()
    local app,bots,C=start()
    walkerDelay(app,10)
    M.input("/paczki tempo 1,5")
    T.eq("courier",C.config.tempoSource);close(1.5,C.config.delay);close(1.5,C:delay())
    local sends=recordSends();local began=M.now
    M.input("/paczki start 1")
    noSendFor(1.49);M.advance(0.02)
    T.eq("przeczytaj tablice",M.sent[#M.sent]);close(began+1.5,sends[1].at)
    M.input("/paczki opoznienie 1,75")
    close(1.75,C:delay());T.eq("courier",C.config.tempoSource)
    walkerDelay(app,20);close(1.75,C:delay(),"walker changes must not replace explicit courier tempo")
    stopAndCheck(app,bots,C)
end)

T.test("live tempo change cancels the old between-step send and restarts its delay",function()
    local app,bots,C,nav,server=start()
    M.input("/paczki tempo 1")
    local sends=recordSends()
    begin(NPC_ROW)
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    if M.sent[#M.sent]~="wyjscie" then T.eq("wyjscie",nextSend(5)) end
    M.advance(0.2);T.eq(2,server.current)
    local changed=M.now;local count=#M.sent
    M.input("/paczki tempo 3")
    T.eq("running",C.mode,M.text());close(3,C:delay())
    noSendFor(2.99,"the superseded 1-second timer must not send during the new 3-second wait")
    M.advance(0.02)
    T.eq(count+1,#M.sent);T.eq("n",M.sent[#M.sent]);close(changed+3,sends[#sends].at)
    stopAndCheck(app,bots,C)
end)

T.test("explicit tempo survives an actual courier loader reload",function()
    local app,bots,C=start()
    walkerDelay(app,10)
    M.input("/paczki tempo 2,75")
    local old=C
    local ok=app.loader:reload({"kurier_paczki"})
    T.ok(ok~=false,M.text())
    C=app.loader.records.kurier_paczki.api.engine
    T.ok(C~=old);T.eq("courier",C.config.tempoSource)
    close(2.75,C.config.delay);close(2.75,C:delay())
    T.eq(nil,bots.status());T.eq("stopped",C.mode);T.eq(0,#app.errors,M.text())
end)

T.test("tempo chodzik restores inheritance and follows later walker changes",function()
    local app,bots,C=start()
    walkerDelay(app,2)
    M.input("/paczki tempo 1,5");close(1.5,C:delay())
    M.input("/paczki tempo chodzik")
    T.eq("walker",C.config.tempoSource);close(2,C:delay())
    walkerDelay(app,3.25);close(3.25,C:delay())
    local sends=recordSends();local began=M.now
    M.input("/paczki start 1")
    noSendFor(3.24);M.advance(0.02)
    T.eq("przeczytaj tablice",M.sent[#M.sent]);close(began+3.25,sends[1].at)
    stopAndCheck(app,bots,C)
end)

T.test("panel names the effective tempo and whether it comes from walker or courier",function()
    local app,bots,C=start()
    walkerDelay(app,2)
    M.clear_output();M.input("/paczki")
    T.contains(M.text(),"Opoznienie kroku");T.contains(M.text(),"2.00 s")
    T.contains(M.text(),"ustawienia chodzika")
    M.input("/paczki tempo 1,5")
    M.clear_output();M.input("/paczki")
    T.contains(M.text(),"1.50 s");T.contains(M.text(),"wlasne tempo paczek")
    T.eq(nil,bots.status());T.eq("stopped",C.mode);T.eq(0,#app.errors,M.text())
end)
T.run()
