-- Reward-per-minute ranking and confirmed-cycle learning through the actual
-- beta.13 loader, GMCP, mapper, NPC catalogue and Boty manager.
-- Run with cwd=chimera-main; only map/server/world rows are simulated.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local IDS={"907327356ecc2f87","a156000000000002","a156000000000003","a156000000000004",
    "a156000000000005","a156000000000006","200aff4d957642cd"}
local NAMES={"Glowna sala poczty w Krainie Zgromadzenia","Rozgalezienie traktu","Sklep Johana",
    "Ulica","Trakt nad rzeka","Sklep Olaffa","Poczta w Bissingen"}
local LINKS={[1]={wyjscie=2},[2]={poczta=1,n=3,e=4},[3]={s=2},[4]={w=2,n=5,e=7},[5]={s=4,n=6},[6]={s=5},[7]={w=4}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod"}
local WEIGHT={[3]=80}
local gateMode=false
local rooms={}
for index,id in ipairs(IDS) do
    local exits={}
    for command,to in pairs(LINKS[index]) do exits[LONG[command] or command]=IDS[to] end
    rooms[id]={id=id,name=NAMES[index],area="Test ETA",area_id="a156",terrain="trakt",indoors=true,exits=exits,hidden={}}
end
T.module("test.world.eta",function()
    return {name="world",setup=function()
        return {room=function(id) return rooms[id] end,terrains=function() return {} end,
            marks=function() return {} end,gates=function()
                if not gateMode then return {} end
                return {[IDS[2]]={command="uderz w brame",wait=2},[IDS[3]]={command="uderz w brame",wait=2}}
            end,version=function() return "test-eta" end,
            npcs=function() return {
                {name="Johan",short="wysoki starszy mezczyzna",title="Johan Kornwalz, kupiec, czlowiek",room=IDS[3]},
                {name="Olaff",short="sympatyczny pucolowaty mezczyzna",title="Olaff Meier Mlodszy, rymarz, czlowiek",room=IDS[6]},
                {name="Annibale",short="wysoki brodaty kapitan",title="Annibale Malacresta Lettore, kapitan, czlowiek",room=IDS[3]},
            } end}
    end}
end)
local function read(path) local f=assert(io.open(path,"rb"));local text=f:read("*a");f:close();return text end
local function prepare()
    for _,name in ipairs({"init","core","routes","new_routes","npc","travel","offices","scope","road","ferry","journey",
        "transport_data","inventory","memory","path","postal","checkpoint","escape","recovery","eta","karak_transport","city","city_data","planner","updater"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name..".lua",read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name..".lua"))
    end
    local area=M.empty_map("Test ETA")
    for index,id in ipairs(IDS) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,NAMES[index]);setRoomArea(index,area)
        setRoomCoordinates(index,index,0,0);setRoomWeight(index,WEIGHT[index] or 1)
    end
    for from,links in pairs(LINKS) do for command,to in pairs(links) do
        if LONG[command] then setExit(from,to,command) else addSpecialExit(from,to,command) end
    end end
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
        while at~=from do local step=previous[at];reversed[#reversed+1]={map=at,command=step.command};at=step.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for index=#reversed,1,-1 do local step=reversed[index]
            speedWalkDir[#speedWalkDir+1]=step.command;speedWalkPath[#speedWalkPath+1]=step.map
            speedWalkWeight[#speedWalkWeight+1]=WEIGHT[step.map] or 1
        end
        return true
    end
end
local function info(index)
    local room=rooms[IDS[index]]
    return {id=room.id,name=room.name,area=room.area,area_id=room.area_id,terrain=room.terrain,indoors=1,exits=room.exits}
end
local function entities(index)
    local values={{id="e1-me",name="Yarrim",kind="player",relation="self"}}
    if index==3 then values[#values+1]={id="e1-johan",name="Johan",kind="npc",relation="neutral"} end
    if index==6 then values[#values+1]={id="e1-olaff",name="Olaff",kind="npc",relation="neutral"} end
    return {room=IDS[index],entities=values}
end
local function start(settings)
    settings=settings or {};gateMode=settings.gates==true
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.eta","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local server={current=1,delay=0.1,gated=gateMode,gateOpen=false,gateOpens=0}
    local function snapshot(index)
        local packet=info(index);local exits={}
        for command,target in pairs(packet.exits) do exits[command]=target end
        if server.gated and not server.gateOpen then
            if index==2 then exits.polnoc=nil elseif index==3 then exits.poludnie=nil end
        end
        packet.exits=exits
        M.packet("Room.Info",packet);M.packet("Chimera.Room.Entities",entities(index));M.line(NAMES[index]..".")
    end
    local wire=send
    _G.send=function(command,...)
        local denied=M.denied
        raiseEvent("sysDataSendRequest",command)
        if M.denied~=denied then return end
        wire(command,...)
        if command=="uderz w brame" and server.gated then
            server.gateOpens=server.gateOpens+1
            tempTimer(2,function()
                server.gateOpen=true;M.line("Przy wtorze zgrzytow i trzaskow brama zostaje otwarta.")
            end)
            return
        end
        local to=(LINKS[server.current] or {})[command]
        if to then tempTimer(server.delay,function()
            local crossing=server.gated and ((server.current==2 and to==3) or (server.current==3 and to==2))
            if crossing then T.ok(server.gateOpen,"A timed cycle cannot cross before its gate acknowledgement") end
            server.current=to
            if crossing then server.gateOpen=false end
            snapshot(to)
        end) end
    end
    M.packet("Char.Info",{name="Yarrim",id="e1-me"});M.packet("Char.Vitals",{hp=100,fatigue=10,mana=100})
    snapshot(1)
    local C=record.api.engine
    C.config.autoBackpack=false;C.config.delay=0.15;C.config.tempoSource="courier";C.config.roam=false;C:save()
    C:captureSource()
    return app,app.loader.records.bots.api,C,record.api,server
end
local function nextSend(limit)
    local before=#M.sent
    for _=1,math.ceil((limit or 30)/0.05) do M.advance(0.05);if #M.sent>before then return M.sent[#M.sent] end end
    error("No next send: "..M.text())
end
local function diagnostic(C,number)
    for _,value in ipairs(C.offerDiagnostics or {}) do if value.number==number then return value end end
    error("Missing offer diagnostic "..number)
end
local JOHAN="1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x6]"
local OLAFF="2. Olaff Meier Mlodszy miejscowa 1.00 kg 9 srebrnych monet [x1]"
local POSTAL="1. Poczta w Bissingen miedzymiastowa 1.00 kg 1 zlota moneta [x1]"
local function rank(C,lines)
    local rows={};for _,text in ipairs(lines) do rows[#rows+1]=assert(C:parseOffer(text)) end
    return C:rank(rows)
end
local function board(lines)
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    for _,text in ipairs(lines) do M.line(text) end
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
end
local function launch(lines)
    M.input("/paczki start 1");T.eq("przeczytaj tablice",nextSend());board(lines)
end
local function beginNpc(C)
    launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());T.eq("n",nextSend())
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
end
local function finishNpc()
    M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(5)
end
local function samples(api,actor)
    T.ok(api.eta and api.eta.summary,"Native adapter must expose the per-character ETA model")
    return api.eta.summary(actor or "yarrim").samples
end

T.test("local board order stays independent of map cost and informational profitability",function()
    local app,bots,C,api=start()
    launch({OLAFF,JOHAN});T.eq("wybierz paczke 1",nextSend())
    local short,long=diagnostic(C,1),diagnostic(C,2)
    T.ok(short.cost>long.cost,"Fixture must make the short path more expensive in map weights")
    T.ok(short.eta.seconds<long.eta.seconds);T.ok(short.score>long.score)
    T.eq(9*60/short.eta.seconds,short.score,"The profitability unit is silver per minute for one parcel")
    T.eq("estimate",short.eta.method);T.eq(0,short.eta.samples)
    T.eq("local_first",C.config.strategy);T.eq(1,C.selected.number);T.eq(0,#app.errors,M.text())
end)

T.test("availability counts do not multiply the single-parcel reward or profitability",function()
    local app,bots,C=start()
    rank(C,{"1. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x1]",
        "2. Johan Kornwalz miejscowa 1.00 kg 9 srebrnych monet [x60]"})
    T.eq(diagnostic(C,1).score,diagnostic(C,2).score)
    T.eq(diagnostic(C,1).eta.seconds,diagnostic(C,2).eta.seconds);T.eq(0,#app.errors,M.text())
end)

T.test("a periodic ship captain includes waiting time even when his mapped walk matches a local recipient",function()
    local app,bots,C=start()
    rank(C,{JOHAN,"2. Annibale Malacresta Lettore miejscowa 1.00 kg 9 srebrnych monet [x1]"})
    local fixed,captain=diagnostic(C,1),diagnostic(C,2)
    T.eq(true,fixed.eligible);T.eq(true,captain.eligible)
    T.eq(fixed.cost,captain.cost,"Both recipients intentionally share the same room and map cost")
    T.ok(captain.eta.seconds>fixed.eta.seconds,"Waiting for an intermittent captain cannot count as zero seconds")
    T.ok(captain.score<fixed.score);T.eq("estimate",captain.eta.method);T.eq(0,#app.errors,M.text())
end)

T.test("live tempo changes recompute informational ETA without changing board order",function()
    local app,bots,C=start()
    local lines={JOHAN,"2. Olaff Meier Mlodszy miejscowa 1.00 kg 12 srebrnych monet [x1]"}
    M.input("/paczki tempo 0.15");local fast=rank(C,lines);local seconds=diagnostic(C,2).eta.seconds
    T.eq(1,fast[1].number)
    M.input("/paczki tempo 30");local slow=rank(C,lines)
    T.ok(diagnostic(C,2).eta.seconds>seconds);T.eq(1,slow[1].number)
    T.eq(0,#app.errors,M.text())
end)

T.test("legacy pay and light commands preserve the fixed local-first policy",function()
    local app,bots,C=start()
    local lines={"1. Johan Kornwalz miejscowa 0.50 kg 9 srebrnych monet [x1]",
        "2. Olaff Meier Mlodszy miejscowa 2.00 kg 12 srebrnych monet [x1]"}
    M.input("/paczki tryb zaplata");T.eq(1,rank(C,lines)[1].number);T.eq("local_first",C.config.strategy)
    M.input("/paczki tryb lekkie");T.eq(1,rank(C,lines)[1].number);T.eq("local_first",C.config.strategy)
    T.ok(diagnostic(C,1).eta.seconds>0);T.eq(0,#app.errors,M.text())
end)

T.test("oferty exposes ETA, silver per minute and the estimate source without sending a game command",function()
    local app,bots,C=start();rank(C,{JOHAN,OLAFF})
    local before=#M.sent;M.clear_output();M.input("/paczki oferty")
    T.eq(before,#M.sent);T.contains(M.text(),"ETA");T.contains(M.text(),"sr/min")
    T.contains(C.norm(M.text()),"szacun");T.eq(0,#app.errors,M.text())
end)

T.test("only a confirmed NPC delivery, reward and return teach one full cycle and survive plugin reload",function()
    local app,bots,C,api,server=start();server.delay=3;rank(C,{JOHAN});local prior=diagnostic(C,1).eta.seconds
    beginNpc(C);T.eq(0,samples(api));M.advance(3)
    M.line("Wrecasz paczke adresatowi.");T.eq(0,samples(api),"Handover alone is not a completed earning cycle")
    M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
    T.eq(0,samples(api),"NPC reward still requires the return to the issuing office")
    T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(4)
    T.eq(1,samples(api));T.eq(1,C.stats.delivered);T.eq(nil,bots.status());T.eq("stopped",C.mode)
    rank(C,{JOHAN});T.eq("learned",diagnostic(C,1).eta.method);T.eq(1,diagnostic(C,1).eta.samples)
    T.ok(diagnostic(C,1).eta.seconds>prior,"The real long recipient wait must affect the estimate")
    T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text())
    local replacement=app.loader.records.kurier_paczki.api;local current=replacement.engine;current:captureSource()
    rank(current,{JOHAN});T.eq(1,samples(replacement));T.eq("learned",diagnostic(current,1).eta.method)
    T.eq(0,#app.errors,M.text())
end)

T.test("a confirmed postal cycle learns on the destination office without inventing a return trip",function()
    local app,bots,C,api,server=start();rank(C,{POSTAL});local postalSeconds=diagnostic(C,1).eta.seconds
    launch({POSTAL});T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Bissingen.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend());T.eq("oddaj paczke",nextSend())
    M.advance(2);M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 1 zlota monete za trud.");M.advance(1)
    T.eq(7,server.current);T.eq(1,C.stats.delivered);T.eq(1,samples(api));T.eq(IDS[7],C.source.id)
    T.eq(nil,bots.status());T.ok(postalSeconds>0);T.eq(0,#app.errors,M.text())
end)

T.test("timing learned for one character does not change another character's estimate",function()
    local app,bots,C,api=start();beginNpc(C);M.advance(3);finishNpc();T.eq(1,samples(api))
    M.packet("Char.Info",{name="DrugaPostac",id="e1-other"});C:captureSource()
    rank(C,{JOHAN});T.eq("estimate",diagnostic(C,1).eta.method);T.eq(0,diagnostic(C,1).eta.samples)
    T.eq(0,samples(api,"drugapostac"));T.eq(1,samples(api,"yarrim"));T.eq(0,#app.errors,M.text())
end)

for _,kind in ipairs({"stop","manual","disconnect","reload"}) do
    T.test(kind.." interruption cannot turn late handover and reward into a timing sample",function()
        local app,bots,C,api=start();beginNpc(C)
        if kind=="stop" then M.input("/bot stop")
        elseif kind=="manual" then send("i")
        elseif kind=="disconnect" then M.packet("Core.Goodbye",{})
        else T.ok(app.loader:reload({"kurier_paczki"})~=false,M.text());api=app.loader.records.kurier_paczki.api end
        M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.");M.advance(5)
        T.eq(0,samples(api));T.eq(0,#app.errors,M.text())
    end)
end

T.test("changing tempo during a completed course does not learn a misleading delay decomposition",function()
    local app,bots,C,api=start();beginNpc(C);M.input("/paczki tempo 0.75");finishNpc()
    T.eq(1,C.stats.delivered);T.eq(0,samples(api));T.eq(0,#app.errors,M.text())
end)

T.test("rejected or physically unconfirmed parcel operations never teach timing",function()
    local app,bots,C,api=start();launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
    M.line("Nie ma juz takiej paczki.");M.advance(12)
    T.eq(0,samples(api));T.eq(0,C.stats.delivered);T.eq(0,#app.errors,M.text())
end)

T.test("automatic fatigue rest is part of the genuine completed-cycle time",function()
    local app,bots,C,api=start()
    launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.15)
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=85})
    T.eq("resting",C.mode);T.ok(bots.status());T.eq(0,samples(api))
    M.advance(30);M.packet("Char.Vitals",{hp=100,mana=100,fatigue=20})
    T.eq("n",nextSend());T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend());finishNpc()
    T.eq(1,C.stats.delivered);T.eq(1,samples(api));rank(C,{JOHAN})
    T.ok(diagnostic(C,1).eta.seconds>15,"Elapsed automatic regeneration must not disappear from profitability")
    T.eq(0,#app.errors,M.text())
end)

T.test("NPC emergency cadence does not teach a falsely faster ordinary walking model",function()
    local app,bots,C,api,server=start()
    launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.15)
    M.packet("Chimera.Room.Entities",{room=IDS[2],entities={{id="e1-me",name="Yarrim",kind="player",relation="self"},
        {id="e1-wolf",name="duzy szary wilk",kind="npc",relation="hostile"}}})
    local before=#M.sent
    M.packet("Chimera.Combat.State",{room=IDS[2],primary="e1-wolf",relations={{attacker="e1-wolf",defender="e1-me"}}})
    local nextCommand=#M.sent>before and M.sent[before+1] or nextSend()
    T.eq("n",nextCommand);M.advance(0.2)
    M.packet("Chimera.Combat.State",{room=IDS[3],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend());finishNpc()
    T.eq(1,C.stats.delivered);T.eq(0,samples(api));T.eq(0,#app.errors,M.text())
end)

T.test("starting the courier during an existing NPC fight cannot teach emergency cadence as an ordinary cycle",function()
    local app,bots,C,api,server=start()
    M.packet("Chimera.Room.Entities",{room=IDS[1],entities={{id="e1-me",name="Yarrim",kind="player",relation="self"},
        {id="e1-wolf",name="duzy szary wilk",kind="npc",relation="hostile"}}})
    M.packet("Chimera.Combat.State",{room=IDS[1],primary="e1-wolf",relations={{attacker="e1-wolf",defender="e1-me"}}})
    launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
    M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
    T.eq("wyjscie",nextSend());M.advance(0.5)
    T.eq(3,server.current);T.eq("recovering",C.mode);T.ok(bots.status())
    M.packet("Chimera.Combat.State",{room=IDS[3],primary="",relations={}})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10})
    T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend());finishNpc()
    T.eq(1,C.stats.delivered);T.eq(0,samples(api));T.eq(0,#app.errors,M.text())
end)

T.test("recipient export does not transfer another character's personal timing history",function()
    local app,bots,C,api=start();beginNpc(C);finishNpc();T.eq(1,samples(api))
    M.input("/paczki baza eksport")
    local exported=read(M.home.."/chimera_paczki_baza.json")
    T.contains(exported,"chimera_paczki_baza");T.not_contains(exported,"nonDelaySeconds")
    T.not_contains(exported,'"actors"');T.eq(0,#app.errors,M.text())
end)

T.test("learned gate cycles retain actual paced counts and do not mistake a tempo change for slower gate service",function()
    local app,bots,C,api,server=start({gates=true})
    local function cycle()
        launch({JOHAN});T.eq("wybierz paczke 1",nextSend())
        M.line("Bierzesz paczke przeznaczona dla: Johan Kornwalz.")
        T.eq("wyjscie",nextSend());T.eq("uderz w brame",nextSend());T.eq("n",nextSend())
        T.eq("przedstaw sie",nextSend());T.eq("oddaj paczke",nextSend())
        M.line("Wrecasz paczke adresatowi.");M.line("Adresat wrecza ci 9 srebrnych monet za trud.")
        T.eq("uderz w brame",nextSend());T.eq("s",nextSend());T.eq("poczta",nextSend());M.advance(3)
        T.eq("stopped",C.mode);T.eq(nil,bots.status());T.eq(1,server.current)
    end
    for _=1,3 do cycle() end
    T.eq(3,samples(api));T.eq(6,server.gateOpens)
    local function record()
        local records=api.eta.exportState().actors.yarrim;local found,count=nil,0
        for _,value in pairs(records) do found=value;count=count+1 end
        T.eq(1,count);return found
    end
    local before=record();T.eq(9,before.pacedUnits,"Two gate acknowledgements add two real paced crossing timers to the seven ordinary course timers")
    T.eq(1,before.minimumDelayUnits,"Introduction has one half-second minimum")
    M.input("/paczki tempo 1.15");rank(C,{JOHAN});local predicted=diagnostic(C,1).eta.seconds
    cycle();T.eq(4,samples(api));T.eq(8,server.gateOpens)
    local after=record();T.eq(before.pacedUnits,after.pacedUnits);T.eq(before.minimumDelayUnits,after.minimumDelayUnits)
    T.ok(math.abs(after.nonDelaySeconds-before.nonDelaySeconds)<0.15,
        "Changing only configured pace must not contaminate learned gate/ACK service time")
    rank(C,{JOHAN});T.ok(math.abs(diagnostic(C,1).eta.seconds-predicted)<0.15)
    T.eq(0,#app.errors,M.text())
end)

T.test("a different parcel weight does not inherit another weight's measured fatigue and handling time",function()
    local app,bots,C,api=start();beginNpc(C);finishNpc();T.eq(1,samples(api))
    rank(C,{JOHAN,"2. Johan Kornwalz miejscowa 2.00 kg 9 srebrnych monet [x1]"})
    T.eq("learned",diagnostic(C,1).eta.method);T.eq(1,diagnostic(C,1).eta.samples)
    T.eq("estimate",diagnostic(C,2).eta.method);T.eq(0,diagnostic(C,2).eta.samples)
    T.eq(0,#app.errors,M.text())
end)

T.test("a fifty-column offer panel wraps a long captain name and measured profitability without hanging or sending commands",function()
    local app,bots,C,api=start()
    for _=1,3 do beginNpc(C);finishNpc() end
    T.eq(3,samples(api))
    rank(C,{JOHAN,"2. Annibale Malacresta Lettore miejscowa 1.00 kg 9 srebrnych monet [x1]"})
    local originalColumns=_G.getColumnCount
    local ok,problem=xpcall(function()
        _G.getColumnCount=function() return 50 end
        local before=#M.sent;M.clear_output();M.input("/paczki oferty")
        T.eq(before,#M.sent,"Inspecting a narrow offer panel must remain read-only")
        local parts={}
        for line in M.text():gmatch("[^\n]+") do
            if line:sub(1,1)=="|" then
                T.ok(#line<=50,"A wrapped offer row exceeded the minimum console width")
                parts[#parts+1]=line:gsub("^|%s*",""):gsub("%s*|$","")
            end
        end
        local readable=C.norm(table.concat(parts," "))
        T.contains(readable,"annibale malacresta lettore")
        T.contains(readable,"eta");T.contains(readable,"sr/min")
        T.contains(readable,"3 pomiarow + szacunek");T.contains(readable,"pozycja rankingu")
        T.eq(0,#app.errors,M.text())
    end,debug.traceback)
    _G.getColumnCount=originalColumns
    if not ok then error(problem) end
end)

T.run()
