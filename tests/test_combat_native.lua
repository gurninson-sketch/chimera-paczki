-- Combat regression with the real beta.13 GMCP, team, Boty and courier.
-- The fixture deliberately uses an ordinary road; hazardous-area rejection
-- has its own tests. Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a000000000000002","a000000000000003","a000000000000004","a000000000000005","a000000000000006"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Rozgalezienie traktu","Trakt przy lesie","Sklep","Objazd przy rzece","Droga do sklepu"}
local LINKS={[1]={n=2},[2]={s=1,n=3,e=5},[3]={s=2,e=4},[4]={w=3,s=6},[5]={w=2,e=6},[6]={w=5,n=4}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod"}
local ME,ENEMY="e1-me","e1-enemy"
local enemyName,enemyKind="Napastnik","player"
local worldRooms={}
for index,id in ipairs(IDS) do
    local exits={}
    for command,to in pairs(LINKS[index]) do exits[LONG[command]]=IDS[to] end
    worldRooms[id]={id=id,name=NAMES[index],area="Test KZ",area_id="a000",terrain="trakt",indoors=false,exits=exits,hidden={}}
end
T.module("test.world.combat",function()
    return {name="world",setup=function()
        return {room=function(id) return worldRooms[id] end,terrains=function() return {} end,
            marks=function() return {} end,gates=function() return {} end,version=function() return "test-combat" end,
            npcs=function() return {{name="Johan",short="wysoki starszy mezczyzna",title="Johan Kornwalz, kupiec, czlowiek",room=IDS[4]}} end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local text=f:read("*a");f:close();return text end
local function prepare()
    for _,name in ipairs({"init","core","routes","new_routes","npc","travel","offices","scope","road","ferry","journey","transport_data","inventory","memory","path","postal","checkpoint","escape","recovery","eta","karak_transport","city","city_data","planner","updater"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name..".lua",read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name..".lua"))
    end
    local area=M.empty_map("Test KZ")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area);setRoomCoordinates(index,index,0,0)
    end
    for from,links in pairs(LINKS) do for command,to in pairs(links) do setExit(from,to,command) end end
    _G.getPath=function(from,to)
        local queue,seen,previous={from},{[from]=true},{}
        local head=1
        while queue[head] do
            local at=queue[head];head=head+1
            for command,target in pairs(LINKS[at] or {}) do if not seen[target] then
                seen[target]=true;previous[target]={from=at,command=command};queue[#queue+1]=target
            end end
        end
        if not seen[to] then return false end
        local reversed,at={},to
        while at~=from do local p=previous[at];reversed[#reversed+1]={map=at,command=p.command};at=p.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for index=#reversed,1,-1 do
            local edge=reversed[index]
            speedWalkDir[#speedWalkDir+1]=edge.command;speedWalkPath[#speedWalkPath+1]=edge.map;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function info(index)
    local room=worldRooms[IDS[index]]
    return {id=room.id,name=room.name,area=room.area,area_id=room.area_id,terrain=room.terrain,indoors=0,exits=room.exits}
end
local function entities(index)
    local rows={{id=ME,name="Yarrim",kind="player",relation="self"},
        {id=ENEMY,name=enemyName,kind=enemyKind,relation="hostile"}}
    if index==4 then rows[#rows+1]={id="e1-johan",name="Johan",kind="npc",relation="neutral"} end
    return {room=IDS[index],entities=rows}
end
local function start(animal)
    enemyName=animal==true and "duza brazowa niedzwiedzica" or (animal=="npc" and "wielki uzbrojony ork" or "Napastnik")
    enemyKind=animal and "npc" or "player"
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.combat","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.team","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=1,delay=0.1}
    local wire=send
    _G.send=function(command,...)
        local denied=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=denied then return end
        wire(command,...)
        local to=(LINKS[server.current] or {})[command]
        if to and not server.silent then tempTimer(server.delay,function()
            server.current=to
            M.packet("Room.Info",info(to));M.packet("Chimera.Room.Entities",entities(to))
            M.line(NAMES[to]..".")
        end) end
    end
    M.packet("Char.Info",{name="Yarrim",id=ME})
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    M.packet("Room.Info",info(1));M.packet("Chimera.Room.Entities",entities(1))
    local C=record.api.engine
    C.config.autoBackpack=false;C.config.delay=1.5;C.config.tempoSource="courier";C:save()
    return app,app.loader.records.bots.api,C,record.api.navigator,server
end
local function nextSend()
    local before=#M.sent
    for _=1,300 do M.advance(0.05);if #M.sent>before then return M.sent[#M.sent] end end
    error("no next send: "..M.text())
end
local function sendSince(before)
    if #M.sent>before then return M.sent[before+1] end
    return nextSend()
end
local function moving(animal)
    local app,bots,C,nav,server=start(animal)
    M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend())
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x1]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("n",nextSend());M.advance(0.15)
    T.eq("n",nextSend());M.advance(0.15)
    T.eq(3,server.current);T.eq("running",C.mode);T.ok(bots.status());T.ok(C.job)
    return app,bots,C,nav,server
end
local function fight(index,relations,primary)
    M.packet("Chimera.Combat.State",{room=IDS[index or 3],primary=primary or ENEMY,
        relations=relations or {{attacker=ENEMY,defender=ME}},covers={}})
end
local function assertNoFurtherSend(before)
    M.advance(35)
    T.eq(before,#M.sent,"combat-stopped parcel may not continue navigation, delivery, board polling or rest")
end
local function assertRecoveryPolls(before,C,bots)
    M.advance(35)
    for index=before+1,#M.sent do T.eq("stan",M.sent[index],"recovery may only poll fresh vitals while combat or health remains uncertain") end
    T.eq("recovering",C.mode);T.ok(bots.status())
end
T.test("a player attack sends the exact verified retreat immediately while Boty retains ownership",function()
    local app,bots,C,nav,server=moving();server.delay=2
    local before=#M.sent;fight()
    T.eq(before+1,#M.sent,"retreat must be immediate in the combat callback")
    T.eq("s",M.sent[#M.sent]);T.ok(bots.status(),"Boty owns the emergency step until acknowledgement")
    T.ok(C.mode~="running" and C.mode~="resting");T.eq(false,nav.inProgress)
    T.eq(false,C.job.delivered);T.eq(IDS[1],C.job.source.id)
    M.advance(1.9);T.eq(3,server.current);T.ok(bots.status())
    M.advance(0.2);T.eq(2,server.current);T.ok(bots.status());T.eq("recovering",C.mode)
    T.contains(M.text(),"Potwierdzono krok odwrotu","arrival must confirm a successful retreat rather than merely abort it")
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[2],primary="",relations={},covers={}})
    M.advance(1.1)
    assertRecoveryPolls(after,C,bots);T.eq(false,C.job.delivered);T.eq(0,C.stats.delivered)
    T.eq(0,#app.errors,M.text())
end)
T.test("duplicate nested fight and Combat.State packets cannot send a second retreat",function()
    local app,bots,C,nav,server=moving();server.silent=true
    local before=#M.sent;fight();fight();app.bus:emit("chimera.fight.started",{room=IDS[3],attacked=true,enemies={ENEMY}})
    T.eq(before+1,#M.sent);T.eq("s",M.sent[#M.sent])
    M.advance(0.2);fight();T.eq(before+1,#M.sent)
    M.advance(35);T.eq(before+1,#M.sent);T.eq(nil,bots.status());T.eq(0,#app.errors,M.text())
end)
for _,kind in ipairs({"stop","manual","key","disconnect","reload","actor","other"}) do
    T.test(kind.." cancels an emergency without later repeating or resuming parcel work",function()
        local app,bots,C,nav,server=moving();server.silent=true
        fight();T.eq("s",M.sent[#M.sent]);T.ok(bots.status())
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="manual" then send("i")
        elseif kind=="key" then app.bus:emit("chimera.numpad.pressed","e")
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        elseif kind=="reload" then T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
        elseif kind=="actor" then M.packet("Char.Info",{name="InnaPostac",id="e2-other"})
        else
            -- Force the manager transition exactly as another bot starts
            -- after stopping the courier; no actual new game command needed.
            bots.stop("inny bot przejal sterowanie")
            bots.register("inne",function(b) b.czekaj(5) end,{opis="fixture"});bots.start("inne")
        end
        local before=#M.sent
        M.line("Nie mozesz sie teraz wycofac.")
        M.packet("Chimera.Combat.State",{room=IDS[3],primary="",relations={}})
        assertNoFurtherSend(before)
        if kind~="other" then T.eq(nil,bots.status()) end
        T.eq(0,#app.errors,M.text())
    end)
end
T.test("an unrelated third-party fight does not stop the courier or send an escape",function()
    local app,bots,C,nav,server=moving();local before=#M.sent
    fight(3,{{attacker="e9-stranger",defender="e8-stranger"}},"")
    T.eq(before,#M.sent);T.eq("running",C.mode);T.ok(bots.status())
    T.eq("e",nextSend());T.eq(0,#app.errors,M.text())
end)
T.test("fight with no owned movement proof pauses instead of guessing a direction",function()
    local app,bots,C=start();M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend())
    local before=#M.sent;fight(1)
    T.eq(before,#M.sent);T.eq(nil,bots.status());T.ok(C.mode~="running")
    assertNoFurtherSend(before);T.eq(0,#app.errors,M.text())
end)
T.test("an unavailable reverse exit never falls back to a guessed inverse direction",function()
    local app,bots,C,nav,server=moving()
    local packet=info(3);packet.exits={wschod=IDS[4]};M.packet("Room.Info",packet)
    local before=#M.sent;fight()
    T.eq(before,#M.sent);T.eq(nil,bots.status());assertNoFurtherSend(before);T.eq(0,#app.errors,M.text())
end)
T.test("native low HP guard preserves the already sent lifesaving retreat and cancels forward work",function()
    local app,bots,C,nav,server=moving();server.delay=2
    fight();T.eq("s",M.sent[#M.sent]);local before=#M.sent
    M.packet("Char.Vitals",{hp=10,fatigue=10,mana=100})
    T.ok(bots.status(),"low HP cannot revoke the pending emergency step")
    T.eq("escaping",C.phase);T.eq(before,#M.sent)
    M.advance(2.1);T.eq(2,server.current);T.ok(bots.status());T.eq("recovering",C.mode)
    T.contains(M.text(),"Potwierdzono krok odwrotu")
    assertRecoveryPolls(before,C,bots);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("an acknowledged forward step away from the attacker becomes evacuation instead of reversing into danger",function()
    local app,bots,C,nav,server=moving();server.delay=2
    T.eq("e",nextSend());local before=#M.sent
    fight();T.eq(before,#M.sent,"cannot send a reverse while the forward move is still in flight")
    T.ok(bots.status());T.eq(3,server.current)
    M.advance(1.9);T.eq(before,#M.sent);T.eq(3,server.current)
    M.advance(0.2);T.eq(4,server.current);T.eq(before+1,#M.sent,M.text())
    T.eq("stan",M.sent[#M.sent],"already evacuated from the attacker; never reverse into the attack room")
    T.ok(bots.status());T.eq("recovering",C.mode)
    M.advance(2.1);T.eq(4,server.current);T.ok(bots.status());T.eq("recovering",C.mode)
    assertRecoveryPolls(before+1,C,bots);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("combat during a silent unacknowledged step never guesses its destination or repeats movement",function()
    local app,bots,C,nav,server=moving();server.silent=true
    T.eq("e",nextSend());local before=#M.sent
    fight();T.eq(before,#M.sent);T.ok(bots.status())
    M.advance(16);T.eq(before,#M.sent);T.eq(3,server.current);T.eq(nil,bots.status())
    assertNoFurtherSend(before);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("a stale combat packet for a previous room cannot send an escape or interrupt the current journey",function()
    local app,bots,C,nav,server=moving();local before=#M.sent
    fight(2)
    T.eq(before,#M.sent);T.eq("running",C.mode);T.ok(bots.status())
    T.eq("e",nextSend());T.eq(0,#app.errors,M.text())
end)
T.test("native attacked event sends a verified retreat before releasing courier ownership",function()
    local app,bots,C,nav,server=moving();server.delay=2
    local before=#M.sent
    app.bus:emit("chimera.attacked",{name=enemyName,player=true})
    T.eq(before+1,#M.sent);T.eq("s",M.sent[#M.sent]);T.ok(bots.status())
    M.advance(2.1);T.eq(2,server.current);T.ok(bots.status());T.eq("recovering",C.mode)
    T.contains(M.text(),"Potwierdzono krok odwrotu")
    assertRecoveryPolls(before+1,C,bots);T.eq(0,#app.errors,M.text())
end)
T.test("death text cancels an outstanding emergency and empty combat packets cannot restart work",function()
    local app,bots,C,nav,server=moving();server.silent=true
    fight();T.eq("s",M.sent[#M.sent]);T.ok(bots.status())
    local before=#M.sent;M.line("Umierasz.")
    T.eq(nil,bots.status());T.ok(C.mode~="running")
    M.packet("Chimera.Combat.State",{room=IDS[3],primary="",relations={}})
    assertNoFurtherSend(before);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("low HP outside combat recovers automatically without inventing an escape",function()
    local app,bots,C,nav,server=moving();local before=#M.sent
    M.packet("Char.Vitals",{hp=10,fatigue=10,mana=100})
    for index=before+1,#M.sent do T.eq("stan",M.sent[index]) end
    T.ok(bots.status());T.eq("recovering",C.mode)
    assertRecoveryPolls(before,C,bots);T.eq(false,C.job.delivered)
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[3],primary="",relations={}})
    M.packet("Char.Vitals",{hp=80,fatigue=20,mana=100})
    T.eq("e",sendSince(after));T.eq("running",C.mode);T.eq(0,#app.errors,M.text())
end)
T.test("after a verified retreat fresh recovery automatically delivers the same parcel over the safe detour",function()
    local app,bots,C,nav,server=moving()
    local job=C.job;local pickupCount=0
    for _,command in ipairs(M.sent) do if command:match("^wybierz paczke") then pickupCount=pickupCount+1 end end
    T.eq(1,pickupCount)
    fight();T.eq("s",M.sent[#M.sent]);M.advance(0.15)
    T.eq(2,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
    local before=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[2],primary="",relations={}})
    M.packet("Char.Vitals",{hp=79,fatigue=20,mana=100});M.advance(1.1)
    for index=before+1,#M.sent do T.eq("stan",M.sent[index]) end
    T.eq("recovering",C.mode,"HP below 80% cannot restart the parcel")
    M.packet("Char.Vitals",{hp=80,fatigue=21,mana=100});M.advance(0.2)
    T.eq("recovering",C.mode,"fatigue above the walker resume limit cannot restart the parcel")
    before=#M.sent
    M.packet("Char.Vitals",{hp=80,fatigue=20,mana=100})
    T.eq("e",sendSince(before));T.eq("running",C.mode,M.text());T.eq(job,C.job)
    T.eq("e",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("w",nextSend());T.eq("w",nextSend());T.eq("s",nextSend())
    M.advance(2);T.eq(1,server.current);T.eq("stopped",C.mode,M.text());T.eq(nil,bots.status())
    T.eq(1,C.stats.delivered);T.eq(9,C.stats.silver)
    pickupCount=0
    for _,command in ipairs(M.sent) do if command:match("^wybierz paczke") then pickupCount=pickupCount+1 end end
    T.eq(1,pickupCount,"recovery must continue the held parcel rather than picking up another one")
    T.eq(0,#app.errors,M.text())
end)
for _,kind in ipairs({"stop","manual","key","disconnect","reload","actor","other"}) do
    T.test(kind.." cancels automatic recovery and fresh healthy packets cannot restart it",function()
        local app,bots,C,nav,server=moving()
        fight();M.advance(0.15);T.eq(2,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="manual" then send("i")
        elseif kind=="key" then app.bus:emit("chimera.numpad.pressed","e")
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        elseif kind=="reload" then T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
        elseif kind=="actor" then M.packet("Char.Info",{name="InnaPostac",id="e2-other"})
        else
            bots.stop("inny bot przejal sterowanie")
            bots.register("inne",function(b) b.czekaj(5) end,{opis="fixture"});bots.start("inne")
        end
        local before=#M.sent
        M.packet("Chimera.Combat.State",{room=IDS[2],primary="",relations={}})
        M.packet("Char.Vitals",{hp=100,fatigue=0,mana=100})
        assertNoFurtherSend(before)
        if kind~="other" then T.eq(nil,bots.status()) end
        T.eq(0,#app.errors,M.text())
    end)
end
T.test("a fresh attack after low HP recovery still sends the verified escape instead of remaining stationary",function()
    local app,bots,C,nav,server=moving()
    M.packet("Char.Vitals",{hp=10,fatigue=10,mana=100})
    T.eq("recovering",C.mode);T.ok(bots.status())
    local before=#M.sent;fight()
    T.eq(before+1,#M.sent);T.eq("s",M.sent[#M.sent]);T.eq("escaping",C.phase)
    M.advance(0.15);T.eq(2,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
    before=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[2],primary="",relations={}})
    M.packet("Char.Vitals",{hp=80,fatigue=20,mana=100})
    T.eq("e",sendSince(before));T.eq("running",C.mode);T.eq(0,#app.errors,M.text())
end)
T.test("low HP waits for an in-flight step acknowledgement before anchoring stationary recovery",function()
    local app,bots,C,nav,server=moving();server.delay=2
    T.eq("e",nextSend());local before=#M.sent
    M.packet("Char.Vitals",{hp=10,fatigue=10,mana=100})
    T.eq(before,#M.sent);T.eq("recovering",C.mode);T.eq("settlingRecovery",C.phase);T.ok(bots.status())
    M.advance(1.9);T.eq(3,server.current);T.eq(before,#M.sent)
    M.advance(0.2);T.eq(4,server.current);T.eq("recovering",C.mode);T.eq("recovering",C.phase)
    T.ok(bots.status());T.eq("stan",M.sent[#M.sent])
    assertRecoveryPolls(before,C,bots);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("an attacker chasing the first retreat causes another verified retreat along the owned path history",function()
    local app,bots,C,nav,server=moving()
    fight();T.eq("s",M.sent[#M.sent]);M.advance(0.15)
    T.eq(2,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
    local before=#M.sent;fight(2)
    T.eq(before+1,#M.sent,M.text());T.eq("s",M.sent[#M.sent],"second retreat goes to previously visited source, never back to attacker room3")
    M.advance(0.15);T.eq(1,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
    assertRecoveryPolls(#M.sent,C,bots);T.eq(false,C.job.delivered);T.eq(0,#app.errors,M.text())
end)
T.test("an animal attack immediately continues forward and the same parcel completes without memorizing that location as dangerous",function()
    local app,bots,C,nav,server=moving(true)
    local before=#M.sent;fight()
    T.eq(before+1,#M.sent,"animal attack must immediately advance along the planned route")
    T.eq("e",M.sent[#M.sent],"continue toward the recipient; never reverse to the previous room")
    T.ok(bots.status());T.eq(false,C.job.delivered)
    M.advance(0.15);T.eq(4,server.current)
    for index=before+1,#M.sent do
        T.ok(M.sent[index]~="oddaj paczke" and M.sent[index]~="przedstaw sie","handover waits for fresh combat clearance")
    end
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("w",nextSend(),"ordinary return route remains available through the animal location")
    T.eq("s",nextSend());T.eq("s",nextSend());M.advance(2)
    T.eq(1,server.current);T.eq("stopped",C.mode);T.eq(nil,bots.status());T.eq(1,C.stats.delivered)
    local pickups=0
    for _,command in ipairs(M.sent) do if command:match("^wybierz paczke") then pickups=pickups+1 end end
    T.eq(1,pickups);T.eq(0,#app.errors,M.text())
end)
T.test("an animal attack during an already sent forward step does not issue another movement or a retreat",function()
    local app,bots,C,nav,server=moving(true);server.delay=2
    T.eq("e",nextSend());local before=#M.sent
    fight();T.eq(before,#M.sent,"already sent step continues without a second command")
    M.advance(1.9);T.eq(3,server.current);T.eq(before,#M.sent)
    M.advance(0.2);T.eq(4,server.current);T.ok(bots.status())
    for index=before+1,#M.sent do T.ok(M.sent[index]~="w" and M.sent[index]~="s","no retreat toward the animal") end
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend());T.eq(0,#app.errors,M.text())
end)
T.test("the native attacked event classifies a known animal before any combat GMCP packet",function()
    local app,bots,C,nav,server=moving(true);local before=#M.sent
    app.bus:emit("chimera.attacked",{name="duza brazowa niedzwiedzica",player=false})
    T.eq(before+1,#M.sent);T.eq("e",M.sent[#M.sent]);T.ok(bots.status())
    M.input("/bot stop");local after=#M.sent;assertNoFurtherSend(after);T.eq(0,#app.errors,M.text())
end)
T.test("a player whose name contains an animal word does not activate the animal passage behavior",function()
    local app,bots,C,nav,server=moving(true)
    M.packet("Chimera.Room.Entities",{room=IDS[3],entities={{id=ME,name="Yarrim",kind="player",relation="self"},
        {id=ENEMY,name="Wilk",kind="player",relation="hostile"}}})
    local before=#M.sent;fight()
    T.eq(before+1,#M.sent);T.eq("s",M.sent[#M.sent],"player identity cannot be treated as wildlife")
    M.input("/bot stop");local after=#M.sent;assertNoFurtherSend(after);T.eq(0,#app.errors,M.text())
end)
T.test("an armed NPC continues the same planned road just like an animal",function()
    local app,bots,C,nav,server=moving("npc");local before=#M.sent
    fight();T.eq(before+1,#M.sent);T.eq("e",M.sent[#M.sent]);T.ok(bots.status())
    M.advance(0.15);T.eq(4,server.current);T.eq(false,C.job.delivered)
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend())
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("w",nextSend());T.eq("s",nextSend());T.eq("s",nextSend());M.advance(2)
    T.eq("stopped",C.mode);T.eq(1,C.stats.delivered);T.eq(0,#app.errors,M.text())
end)
for _,text in ipairs({"Wielki uzbrojony ork koncentruje sie na walce z toba.",
    "Wielki uzbrojony ork atakuje cie nie dajac ci chwili wytchnienia!"}) do
    T.test("a current named NPC attack line before combat GMCP still continues forward: "..text,function()
        local app,bots,C,nav,server=moving("npc");local before=#M.sent
        -- Notifications are intentionally absent. The addon itself receives
        -- this line before Chimera.Combat.State arrives.
        M.line(text)
        T.eq(before+1,#M.sent,M.text());T.eq("e",M.sent[#M.sent],"raw NPC attack must not fall into unknown/player retreat")
        T.ok(bots.status());M.input("/bot stop");local after=#M.sent;assertNoFurtherSend(after);T.eq(0,#app.errors,M.text())
    end)
end
T.test("an official extended animal attack line before combat GMCP continues forward",function()
    local app,bots,C,nav,server=moving(true);local before=#M.sent
    M.line("Duza brazowa niedzwiedzica atakuje cie nie dajac ci czasu na skontrowanie swojego ataku!")
    T.eq(before+1,#M.sent,M.text());T.eq("e",M.sent[#M.sent]);T.ok(bots.status())
    M.input("/bot stop");local after=#M.sent;assertNoFurtherSend(after);T.eq(0,#app.errors,M.text())
end)
T.test("an NPC attack after low HP during an in-flight step keeps that step and resumes without retreat",function()
    local app,bots,C,nav,server=moving("npc");server.delay=2
    T.eq("e",nextSend());local before=#M.sent
    M.packet("Char.Vitals",{hp=10,fatigue=10,mana=100});T.eq("settlingRecovery",C.phase)
    fight();T.eq(before,#M.sent);T.eq("settlingNpcTransit",C.phase);T.ok(bots.status())
    M.advance(1.9);T.eq(3,server.current);T.eq(before,#M.sent)
    M.advance(0.3);T.eq(4,server.current);T.ok(bots.status())
    for index=before+1,#M.sent do T.ok(M.sent[index]~="w" and M.sent[index]~="s","NPC attack never retreats") end
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=80,fatigue=20,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend());T.eq(0,#app.errors,M.text())
end)
T.test("an NPC attack during fatigue rest resumes the forward route instead of leaving the character stationary",function()
    local app,bots,C,nav,server=moving("npc")
    M.packet("Char.Vitals",{hp=100,fatigue=85,mana=100});T.eq("resting",C.mode);T.ok(bots.status())
    local before=#M.sent;fight();T.eq(before+1,#M.sent);T.eq("e",M.sent[#M.sent])
    M.advance(0.15);T.eq(4,server.current);T.ok(bots.status())
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,fatigue=20,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend());T.eq(0,#app.errors,M.text())
end)
T.test("an NPC attack continues all remaining road steps without stopping after the first room",function()
    local app,bots,C,nav,server=start("npc")
    M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend())
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x1]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    T.eq("wybierz paczke 1",nextSend());M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("n",nextSend());M.advance(0.15);T.eq(2,server.current)
    local before=#M.sent;fight(2)
    T.eq(before+1,#M.sent);T.eq("n",M.sent[#M.sent])
    M.advance(0.35);T.eq(4,server.current,M.text());T.ok(bots.status())
    T.eq("n",M.sent[before+1]);T.eq("e",M.sent[before+2])
    local after=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[4],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    T.eq("przedstaw sie",sendSince(after));T.eq("oddaj paczke",nextSend());T.eq(0,#app.errors,M.text())
end)
T.run()
