-- Rest integration with real beta.13 loader, GMCP, events, walker settings,
-- bot manager and the production courier navigation. Fixture helpers copied
-- from test_native_map.lua; its tests are independent and are not loaded here.
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
        if to and server.rejectNext then
            server.rejectNext=false
            tempTimer(0.1,function() M.line("Jestes tak zmeczony, ze nie mozesz isc.") end)
            return
        end
        if to and server.silentNext then server.silentNext=false;return end
        if to and server.detourNext then to=server.detourNext;server.detourNext=nil end
        if to then tempTimer(server.moveDelay or 0.1,function()
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
local function vitals(fatigue,hp)
    local packet={hp=hp or 100,mana=100}
    if fatigue~=nil then packet.fatigue=fatigue end
    M.packet("Char.Vitals",packet)
end
local function onlyStan(from)
    for index=from+1,#M.sent do T.eq("stan",M.sent[index],"rest may only poll vitals") end
end
local function restingAtOffice()
    local app,bots,C,nav,server=start()
    vitals(10)
    M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend())
    vitals(85);T.eq("resting",C.mode,M.text());T.ok(bots.status(),M.text())
    return app,bots,C,nav,server
end
T.test("high fatigue at start retains Boty and polls stan every ten seconds until fresh recovery",function()
    local app,bots,C=start()
    C.stats.delivered=2;C.stats.silver=18
    vitals(85);local before=#M.sent
    M.input("/paczki start 1")
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq(3,C.stopAt)
    T.eq(before,#M.sent,"fatigued start must not read a board or move")
    M.advance(9.9);T.eq(before,#M.sent)
    M.advance(0.2);T.eq(before+1,#M.sent);T.eq("stan",M.sent[#M.sent]);T.eq("resting",C.mode)
    M.advance(10);T.eq(before+2,#M.sent);T.eq("stan",M.sent[#M.sent]);T.ok(bots.status())
    vitals(nil);M.advance(0.5);T.eq("resting",C.mode,"a partial vitals packet cannot recover fatigue")
    vitals(21);M.advance(0.5);T.eq("resting",C.mode,"recovered event above walker start is insufficient")
    vitals(20);T.eq("przeczytaj tablice",nextSend());T.eq("running",C.mode);T.ok(bots.status())
    T.eq(3,C.stopAt);T.eq(2,C.stats.delivered);T.eq(18,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.test("rest cancels the outstanding board watchdog and own stan polls never count as manual takeover",function()
    local app,bots,C=restingAtOffice();local before=#M.sent
    M.advance(30.1);onlyStan(before);T.eq(before+3,#M.sent)
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.not_contains(M.text(),"Brak potwierdzenia")
    T.not_contains(M.text(),"Reczna komenda");T.eq(0,#app.errors,M.text())
end)
T.test("fatigue stop uses the lower walker or automation threshold and resumes at walker start",function()
    for _,pair in ipairs({{60,90},{90,55}}) do
        local app,bots,C=start()
        T.ok(app.config:set("walker","zmeczenie_stop",pair[1]))
        T.ok(app.config:set("events","prog_zmeczenie",pair[2]))
        T.ok(app.config:set("walker","zmeczenie_start",10))
        local threshold=math.min(pair[1],pair[2])
        vitals(threshold-1);M.input("/bot paczki");T.eq("przeczytaj tablice",nextSend())
        T.eq("running",C.mode);vitals(threshold);T.eq("resting",C.mode,M.text());T.ok(bots.status())
        vitals(11);M.advance(0.5);T.eq("resting",C.mode)
        vitals(10);T.eq("przeczytaj tablice",nextSend());T.eq("running",C.mode);T.ok(bots.status())
        T.eq(0,#app.errors,M.text())
    end
end)
T.test("rest with a parcel preserves its source, statistics and limit then resumes from the acknowledged map room",function()
    local app,bots,C,nav=start();vitals(10)
    C.stats.delivered=3;C.stats.silver=27
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85);M.advance(0.2)
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq(false,nav.inProgress)
    T.eq(2,app.loader.records.mapper.api.current_room());T.eq(IDS[1],C.source.id)
    T.eq(IDS[1],C.job.source.id);T.eq("johan kornwalz",C.norm(C.job.name));T.eq(false,C.job.delivered)
    T.eq(4,C.stopAt);T.eq(3,C.stats.delivered);T.eq(27,C.stats.silver)
    local before=#M.sent;M.advance(10);onlyStan(before);T.eq("resting",C.mode)
    vitals(20);T.eq("n",nextSend());T.eq("running",C.mode,M.text())
    -- A repeated good packet must not launch a second navigation.
    local count=#M.sent;vitals(20);M.advance(0.05);T.eq(count,#M.sent)
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(1)
    T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status());T.eq(4,C.stats.delivered);T.eq(36,C.stats.silver)
    T.eq(4,C.stopAt);T.eq(1,app.loader.records.mapper.api.current_room());T.eq(0,#app.errors,M.text())
end)
T.test("rest during relocation preserves the selected office and resumes its remaining route",function()
    local app,bots,C,nav=start();vitals(10)
    M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend());board()
    T.eq("wyjscie",nextSend());vitals(85);M.advance(0.2)
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq(false,nav.inProgress)
    T.ok(C.relocation);T.eq(IDS[1],C.relocation.from.id);T.eq(IDS[5],C.relocation.to.id)
    T.eq(1,C.stopAt);local before=#M.sent;M.advance(10);onlyStan(before)
    vitals(20);T.eq("e",nextSend());T.eq("e",nextSend());T.eq("przeczytaj tablice",nextSend())
    T.eq("running",C.mode);T.eq(IDS[5],C.source.id);T.eq(nil,C.relocation);T.eq(1,C.stopAt)
    T.eq(0,C.stats.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("a server fatigue rejection rests without retrying the refused move before fresh recovery",function()
    local app,bots,C,nav,server=start();vitals(10)
    begin(NPC_ROW);server.rejectNext=true;M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.2)
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq(1,app.loader.records.mapper.api.current_room())
    local before=#M.sent;M.advance(30.1);onlyStan(before)
    T.eq("resting",C.mode,"cached pre-rejection fatigue=10 must not auto-resume")
    T.eq(false,nav.inProgress);T.eq(false,C.job.delivered)
    vitals(20);T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("running",C.mode,M.text());T.eq(0,#app.errors,M.text())
end)
T.test("unconfirmed parcel operation prevents automatic retry after rest",function()
    local app,bots,C=start();vitals(10);begin(NPC_ROW)
    T.eq(true,C.awaitingPickup);vitals(85);T.eq("resting",C.mode);T.ok(bots.status())
    local before=#M.sent;vitals(20);M.advance(1)
    T.eq(before,#M.sent);T.eq(true,C.awaitingPickup);T.eq(nil,bots.status())
    T.ok(C.mode=="paused" or C.mode=="stopped");T.contains(M.text(),"wynik operacji z paczka nie zostal potwierdzony")
    T.eq(0,#app.errors,M.text())
end)
for _,kind in ipairs({"stop","manual","hp","combat","teleport","disconnect","reload","key"}) do
    T.test(kind.." interrupts rest permanently until another explicit start",function()
        local app,bots,C=restingAtOffice()
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="manual" then send("i")
        elseif kind=="hp" then vitals(85,20)
        elseif kind=="combat" then app.bus:emit("chimera.fight.started",{room=IDS[1],enemies={"ork"}})
        elseif kind=="teleport" then M.packet("Room.Info",{id="ff00000000000001",name="Gdzie indziej",exits={}})
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        elseif kind=="key" then app.bus:emit("chimera.numpad.pressed","n")
        else T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text()) end
        local after=#M.sent
        vitals(20);M.advance(35)
        T.eq(after,#M.sent,"fresh recovery must not restart a user/safety-stopped courier")
        T.eq(nil,bots.status());T.ok(C.mode~="resting" and C.mode~="running",M.text());T.eq(nil,next(C.timers))
        if kind=="reload" then T.eq("stopped",app.loader.records.kurier_paczki.api.engine.mode) end
        T.eq(0,#app.errors,M.text())
    end)
end
T.test("a two-second acknowledgement of the cancelled in-flight step preserves rest and native Boty",function()
    local app,bots,C,nav,server=start();vitals(10)
    begin(NPC_ROW);server.moveDelay=2
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85)
    T.eq("resting",C.mode);T.ok(bots.status());local before=#M.sent
    M.advance(2.1)
    T.eq(before,#M.sent,"draining an acknowledged step cannot send another one")
    T.eq(2,app.loader.records.mapper.api.current_room())
    T.eq("resting",C.mode,M.text());T.ok(bots.status());T.eq(false,nav.inProgress)
    T.eq(false,C.job.delivered);T.eq(IDS[1],C.job.source.id)
    server.moveDelay=0.1;vitals(20);T.eq("n",nextSend())
    T.eq("running",C.mode,M.text());T.eq(0,#app.errors,M.text())
end)
T.test("a delayed acknowledgement at the wrong map room cancels rest and prevents automatic recovery",function()
    local app,bots,C,nav,server=start();vitals(10)
    begin(NPC_ROW);server.moveDelay=2;server.detourNext=4
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85);T.eq("resting",C.mode)
    local before=#M.sent;M.advance(2.1)
    T.eq(4,app.loader.records.mapper.api.current_room());T.eq(nil,bots.status())
    T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(false,nav.inProgress)
    vitals(20);M.advance(35)
    T.eq(before,#M.sent);T.eq(nil,next(C.timers));T.eq(false,C.job.delivered)
    T.eq(0,#app.errors,M.text())
end)
T.test("fresh recovery before a two-second step acknowledgement waits and resumes only after the exact acknowledgement",function()
    local app,bots,C,nav,server=start();vitals(10)
    begin(NPC_ROW);server.moveDelay=2
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85);vitals(20);server.moveDelay=0.1
    local before=#M.sent;M.advance(1.5)
    T.eq(before,#M.sent,"fresh recovery cannot repeat an unacknowledged step")
    T.eq(1,app.loader.records.mapper.api.current_room());T.eq("resting",C.mode,M.text());T.ok(bots.status())
    T.eq("n",nextSend());T.eq(2,app.loader.records.mapper.api.current_room())
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(false,C.job.delivered)
    T.eq(0,#app.errors,M.text())
end)
T.test("an unacknowledged in-flight step times out after fifteen seconds despite fresh low fatigue",function()
    local app,bots,C,nav,server=start();vitals(10)
    begin(NPC_ROW);server.silentNext=true
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85);vitals(20)
    local before=#M.sent;M.advance(14.9)
    onlyStan(before);T.eq("resting",C.mode,M.text());T.ok(bots.status())
    T.eq(1,app.loader.records.mapper.api.current_room())
    M.advance(0.2)
    T.ok(C.mode=="paused" or C.mode=="stopped",M.text());T.eq(nil,bots.status())
    T.eq(false,nav.inProgress);T.eq(false,C.job.delivered)
    local count=#M.sent;vitals(20);M.advance(25)
    T.eq(count,#M.sent);T.eq(nil,next(C.timers));T.eq(0,#app.errors,M.text())
end)
T.test("GMCP-only character change during rest clears the old parcel and prevents automatic recovery",function()
    local app,bots,C,nav=start();vitals(10)
    M.packet("Char.Info",{name="PostacPierwsza",id="e1-first"})
    C.stats.delivered=3;C.stats.silver=27
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());vitals(85);M.advance(0.2)
    T.eq("resting",C.mode,M.text());T.ok(C.job);T.ok(bots.status())
    M.packet("Char.Info",{name="PostacDruga",id="e1-second"})
    T.eq("postacdruga",C.actor);T.eq(nil,C.job);T.eq(nil,C.source);T.eq(nil,C.relocation)
    T.eq(0,C.stats.delivered);T.eq(0,C.stats.silver);T.eq(nil,bots.status())
    T.ok(C.mode=="paused" or C.mode=="stopped",M.text())
    local before=#M.sent;vitals(20);M.advance(35)
    T.eq(before,#M.sent);T.eq(nil,next(C.timers));T.eq(false,nav.inProgress);T.eq(0,#app.errors,M.text())
end)
T.run()
