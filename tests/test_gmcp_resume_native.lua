-- Recovery after a full native App restart: the persistent profile survives,
-- while every module Context and normalized GMCP state starts empty.
-- No raw GMCP cache is replayed. Fresh packets drive deferred user intent.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","200aff4d957642cd","0a647e20ca6f97f7"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Ulica","Sklep","Skrzyzowanie","Poczta","Urzad pocztowy Urbimo"}
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
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local CLOSE="zamknij swoj plecak"
local OPEN="otworz swoj plecak"
local function opening(expected,firstCommand,openCommand,reply)
    T.eq(openCommand or OPEN,firstCommand or nextSend())
    local before=#M.sent;M.advance(0.1)
    T.eq(before,#M.sent,"transfer must wait for its own opening acknowledgement")
    M.line(reply or "Otwierasz swoj plecak.")
    T.eq(before+1,#M.sent);T.eq(expected,M.sent[#M.sent])
end
local function configure(app)
    M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak")
    T.eq(true,app.loader.records.bags.api.configured("inne"))
    T.eq(true,app.loader.records.bags.api.configured("monety"))
end
local function pulse(fatigue) M.packet("Char.Vitals",{hp=100,mana=100,fatigue=fatigue}) end
local function acceptAndStow()
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    opening(STOW)
end
local function acknowledge(text,expected)
    local before=#M.sent;M.line(text)
    if expected then
        if #M.sent==before then T.eq(expected,nextSend()) else T.eq(before+1,#M.sent);T.eq(expected,M.sent[#M.sent]) end
    else T.eq(before,#M.sent) end
end
local function deliverToCoinStorage()
    acceptAndStow()
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("n",nextSend());opening(TAKE)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","przedstaw sie")
    T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    opening(COINS)
end
local function coinSends()
    local count=0
    for _,command in ipairs(M.sent) do if command==COINS then count=count+1 end end
    return count
end
local ACTOR="Testowicz"
local function character(name)
    M.packet("Char.Info",{id=name==ACTOR and "e1-test" or "e1-other",name=name})
end
local function checkpoint(app) return assert(app.loader.records.kurier_paczki.api.checkpoint,"adapter checkpoint API missing") end
local function current(app) return app.loader.records.kurier_paczki.api.engine end
local function canonicalStart(C)
    character(ACTOR);pulse(10)
    C.stats.delivered=2;C.stats.gold=1;C.stats.silver=18;C.stats.copper=3
end
local function disconnect() M.packet("Core.Goodbye",{}) end
local function reconnect(server,index,name)
    character(name or ACTOR);position(server,index);pulse(10)
end
local function reload(app)
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    return current(app)
end
local function heldNpcAtStreet(C)
    begin(NPC_ROW);M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.2)
    T.eq(2,C.stopAt-1);T.eq(2,C.stats.delivered)
end
local function urbimoReward()
    begin("1. Urzad pocztowy Urbimo miedzymiastowa 3.00 kg 2 zlote monety [x1]")
    M.line("Bierzesz paczke przeznaczona dla: Urzad pocztowy Urbimo.")
    opening(STOW)
    acknowledge("Wkladasz pocztowa paczke do otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","wyjscie")
    T.eq("e",nextSend());T.eq("e",nextSend());T.eq("e",nextSend());opening(TAKE)
    acknowledge("Bierzesz pocztowa paczke z otwartego skorzanego plecaka.",CLOSE)
    acknowledge("Zamykasz swoj plecak.","oddaj paczke")
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
end

local function fullRestart(app)
    local env={};for key,value in pairs(app.env) do env[key]=value end
    app:shutdown()
    _G.chimera=nil
    for name in pairs(package.loaded) do if name:find("^chimera") then package.loaded[name]=nil end end
    local fresh=require("chimera.boot").start(env)
    _G.chimera={app=fresh,restart=function() fresh:shutdown() end}
    M.advance(0)
    T.ok(fresh.loader.records.kurier_paczki and fresh.loader.records.kurier_paczki.status=="running",M.text())
    return fresh,current(fresh),fresh.loader.records.bots.api
end
local function preparedRestart()
    local app,bots,C,nav,server=start();canonicalStart(C);heldNpcAtStreet(C)
    local saved=assert(checkpoint(app).get(ACTOR));T.ok(saved.job)
    app,C,bots=fullRestart(app)
    -- Mudlet's raw cache is deliberately still populated from the old App.
    T.ok(gmcp.Char.Info and gmcp.Char.Info.name==ACTOR)
    local api=app.loader.records.gmcp.api
    T.eq(nil,api.char());T.eq(nil,api.room());T.eq(nil,api.entities())
    T.eq(nil,C.actor);T.eq(nil,C.job);T.ok(checkpoint(app).get(ACTOR).job)
    return app,bots,C,server
end
local function requestedFreshPackets(before)
    local char,room=false,false
    for index=before+1,#M.sent_gmcp do
        local command=M.sent_gmcp[index]
        if command:match('^Core.Supports.Add ') then
            char=char or command:find('Char 2',1,true)~=nil
            room=room or command:find('Room 1',1,true)~=nil
        end
    end
    T.ok(char,"explicit courier intent must request fresh Char 2")
    T.ok(room,"explicit courier intent must request fresh Room 1")
end
local function waiting(app) return app.loader.records.kurier_paczki.api.sessionWaiting() end
local function countCommand(command,first)
    local count=0;for index=first or 1,#M.sent do if M.sent[index]==command then count=count+1 end end;return count
end

T.test("full restart waits without replaying raw identity and resumes the held course once in either fresh packet order",function()
    for _,order in ipairs({"character_first","room_first"}) do
        local app,bots,C,server=preparedRestart();local sent=#M.sent;local packets=#M.sent_gmcp
        M.input(order=="character_first" and "/paczki wznow" or "/bot paczki")
        M.advance(0.2);T.eq(sent,#M.sent);T.eq(nil,bots.status());T.eq(true,waiting(app))
        requestedFreshPackets(packets)
        T.eq(nil,C.actor);T.eq(nil,C.job);T.ok(checkpoint(app).get(ACTOR).job)
        if order=="character_first" then character(ACTOR) else position(server,2) end
        M.advance(0.2);T.eq(sent,#M.sent);T.eq(nil,bots.status())
        if order=="character_first" then position(server,2) else character(ACTOR) end
        T.eq("n",nextSend());T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(false,waiting(app))
        T.eq("testowicz",C.actor);T.ok(C.job);T.eq("johan kornwalz",C.norm(C.job.name))
        T.eq(2,C.stats.delivered);T.eq(3,C.stopAt);T.eq(IDS[1],C.source.id)
        -- Repeated server metadata is not a second user launch.
        character(ACTOR);M.packet("Room.Info",info(2));M.advance(0.05)
        T.eq(1,countCommand("n",sent+1));T.eq(0,countCommand("wybierz paczke 1",sent+1))
        M.input("/bot stop");T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
    end
end)

T.test("missing fresh data retains the checkpoint and sends no game command while refresh requests stay bounded",function()
    local app,bots,C,server=preparedRestart();local sent=#M.sent;local packets=#M.sent_gmcp
    M.input("/paczki wznow");M.advance(30)
    T.eq(sent,#M.sent);T.eq(nil,bots.status());T.eq(nil,C.actor)
    T.ok(checkpoint(app).get(ACTOR).job);requestedFreshPackets(packets)
    T.ok(#M.sent_gmcp-packets<=6,"waiting must not flood GMCP requests");T.eq(true,waiting(app))
    -- Delayed but valid packets still satisfy the original explicit request.
    character(ACTOR);position(server,2);T.eq("n",nextSend())
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)

T.test("STOP manual input safety events another bot and reload cancel deferred launch before late metadata arrives",function()
    for _,kind in ipairs({"bot_stop","courier_stop","manual","combat","hp","numpad","other_bot","disconnect","reload"}) do
        local app,bots,C,server=preparedRestart();local initialPackets=#M.sent_gmcp
        M.input("/paczki wznow");M.advance(0.1);requestedFreshPackets(initialPackets)
        T.eq(nil,bots.status());T.eq(true,waiting(app))
        if kind=="bot_stop" then M.input("/bot stop")
        elseif kind=="courier_stop" then M.input("/paczki stop")
        elseif kind=="manual" then send("i")
        elseif kind=="combat" then M.packet("Chimera.Combat.State",{primary="e1-enemy",relations={}})
        elseif kind=="hp" then app.bus:emit("chimera.char.low",{what="hp",value=10})
        elseif kind=="numpad" then app.bus:emit("chimera.numpad.pressed","n")
        elseif kind=="other_bot" then bots.register("inny",function(b) b.czekaj(50) end);bots.start("inny");T.ok(bots.status())
        elseif kind=="disconnect" then raiseEvent("sysDisconnectionEvent")
        else app,C,bots=fullRestart(app) end
        local sent=#M.sent;local packets=#M.sent_gmcp;T.eq(false,waiting(app),"pending cancellation: "..kind)
        character(ACTOR);position(server,2);M.advance(15)
        T.eq(sent,#M.sent,"cancelled "..kind.." must not launch on late metadata")
        T.eq(nil,bots.status());T.ok(checkpoint(app).get(ACTOR).job)
        T.eq(packets,#M.sent_gmcp,"cancelled wait must not retain request timers")
        T.eq(0,#app.errors,M.text())
    end
end)

T.test("a bounded metadata timeout retains the course but requires a new explicit launch after late packets",function()
    local app,bots,C,server=preparedRestart();local sent=#M.sent;local packets=#M.sent_gmcp
    M.input("/paczki wznow");M.advance(61)
    T.eq(false,waiting(app));T.eq(sent,#M.sent);T.eq(nil,bots.status())
    T.ok(checkpoint(app).get(ACTOR).job);requestedFreshPackets(packets)
    T.ok(#M.sent_gmcp-packets<=6,"one timed-out request has at most three refresh attempts")
    character(ACTOR);position(server,2);M.advance(2)
    T.eq(sent,#M.sent);T.eq(nil,bots.status());T.ok(C.job)
    T.eq("n",inputSend("/paczki wznow"));M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)

T.test("a different fresh canonical character never adopts the previous character parcel",function()
    local app,bots,C,server=preparedRestart();local sent=#M.sent;local packets=#M.sent_gmcp
    M.input("/paczki wznow");M.advance(0.1);requestedFreshPackets(packets);character("NowyBohater");position(server,1);M.advance(2)
    T.eq("nowybohater",C.actor);T.eq(nil,C.job);T.eq(0,C.stats.delivered)
    T.ok(checkpoint(app).get(ACTOR).job)
    T.eq(0,countCommand("n",sent+1));T.eq(0,countCommand("oddaj paczke",sent+1))
    M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)

T.test("a completed postal delivery can settle at the recognized office reached manually after restart",function()
    local app,bots,C,nav,server=start();canonicalStart(C)
    begin("1. Urzad pocztowy Urbimo miedzymiastowa 3.00 kg 2 zlote monety [x1]")
    M.line("Bierzesz paczke przeznaczona dla: Urzad pocztowy Urbimo.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend());T.eq("e",nextSend())
    T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.");M.line("Urzednik wyplaca ci 2 zlote monety za trud.")
    M.input("/bot stop");T.ok(C.job and C.job.delivered)
    -- Real player travel after delivery: the pending job remains delivered,
    -- but the actual next working office is the newly visited KZ post office.
    position(server,1);app,C,bots=fullRestart(app)
    local sent=#M.sent;M.input("/paczki wznow");character(ACTOR);position(server,1);M.advance(2)
    T.eq(sent,#M.sent,"a completed one-parcel limit requires no second handover or trip back to Urbimo")
    T.eq(nil,C.job);T.eq(IDS[1],C.source.id);T.eq(3,C.stats.delivered);T.eq(3,C.stats.gold)
    T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
T.run()
