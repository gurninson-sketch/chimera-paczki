-- Postal classification and per-offer diagnostics through actual native
-- loader, GMCP, Boty and production courier. Narrow world fixture copied
-- from test_native_map.lua, with the Nuln office added at runtime map room6.
-- Run with cwd=chimera-main.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
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
T.test("known Nuln5kg is selected at limit6.2 while unknown NPC and Bissingen8 or12kg are explained",function()
    local app,bots,C,nav=start();launch()
    rows({"1. Nieznany Tragarz miejscowa 0.50 kg 18 zlotych monet [x1]",
        "2. Poczta w Bissingen miedzymiastowa 8.00 kg 5 zlotych monet [x1]",
        "3. Poczta wolnego miasta Nuln miedzymiastowa 5.00 kg 2 zlote monety [x1]",
        "4. Poczta w Bissingen miedzymiastowa 12.00 kg 8 zlotych monet [x1]"})
    T.eq("wybierz paczke 3",nextSend());T.eq(6.2,C.config.maxKg);T.eq(3,C.selected.number)
    T.eq(true,C.selected.route.postal);T.eq(IDS[6],C.selected.route.targetId)
    T.eq(4,#C.offerDiagnostics);T.eq(6.2,C.offersLimit);T.eq("local_first",C.offersStrategy);T.eq(IDS[1],sourceId(C.offersSource))
    T.eq(false,diagnostic(C,1).eligible);T.eq("route",diagnostic(C,1).category)
    for _,number in ipairs({2,4}) do
        local row=diagnostic(C,number);T.eq(false,row.eligible);T.eq("weight",row.category)
        T.ok(row.kg>6.2);T.contains(row.reason,"6.2")
    end
    local chosen=diagnostic(C,3);T.eq(true,chosen.eligible);T.eq("eligible",chosen.category)
    T.eq(5,chosen.kg);T.eq(4,chosen.cost);T.ok(chosen.score>0);T.contains(chosen.reason,"rankingu 1")
    T.eq(0,#app.errors,M.text())
end)
T.test("exact Nuln postal label variants share the known destination without an NPC catalogue entry",function()
    for _,name in ipairs({"Poczta wolnego miasta Nuln","Urzad pocztowy w Nuln"}) do
        local app,bots,C,nav=start();launch()
        rows({"7. "..name.." miedzymiastowa 5.00 kg 2 zlote monety [x1]"})
        T.eq("wybierz paczke 7",nextSend());T.eq(true,C.selected.route.postal)
        T.eq(IDS[6],C.selected.route.targetId);T.eq(true,diagnostic(C,7).eligible)
        T.eq(6.2,C.config.maxKg);T.eq(0,#app.errors,M.text())
    end
end)
T.test("a mapped6kg KZ postal offer is eligible below the unchanged6.2kg limit",function()
    local app,bots,C,nav,server=start();position(server,5);launch()
    rows({"4. Poczta w Krainie Zgromadzenia miedzymiastowa 6.00 kg 3 zlote monety [x1]"})
    T.eq("wybierz paczke 4",nextSend());T.eq(6.2,C.config.maxKg)
    T.eq(true,C.selected.route.postal);T.eq(IDS[1],C.selected.route.targetId)
    T.eq(true,diagnostic(C,4).eligible);T.eq(6,diagnostic(C,4).kg);T.eq(3,diagnostic(C,4).cost)
    T.eq(IDS[5],sourceId(C.offersSource));T.eq(0,#app.errors,M.text())
end)
T.test("unknown and misspelled postal cities fail instead of matching a similar known office",function()
    local app,bots,C,nav=start();M.input("/paczki poczty stop");launch()
    rows({"1. Poczta w Nulnn miedzymiastowa 5.00 kg 2 zlote monety [x1]",
        "2. Poczta w NieznanymMiescie miedzymiastowa 1.00 kg 9 zlotych monet [x1]"})
    local before=#M.sent;M.advance(1)
    T.eq(before,#M.sent);T.eq(nil,C.job);T.eq("waiting",C.phase)
    for number=1,2 do
        T.eq(false,diagnostic(C,number).eligible);T.eq("route",diagnostic(C,number).category)
        T.ok(diagnostic(C,number).reason~="")
    end
    T.eq(6.2,C.config.maxKg);T.eq(0,#app.errors,M.text())
end)
T.test("a recognized postal office with no path has a route reason and is not picked up",function()
    local app,bots,C,nav=start();M.input("/paczki poczty stop")
    LINKS[5].e=nil;M.map.rooms[5].exits.east=nil
    launch();rows({"1. Urzad pocztowy w Nuln miedzymiastowa 5.00 kg 2 zlote monety [x1]"})
    local before=#M.sent;M.advance(1)
    LINKS[5].e=6
    T.eq(before,#M.sent);T.eq(false,diagnostic(C,1).eligible);T.eq("route",diagnostic(C,1).category)
    T.contains(diagnostic(C,1).reason,"drog");T.eq("waiting",C.phase);T.eq(nil,C.job)
    T.eq(0,#app.errors,M.text())
end)
T.test("oferty shows the last source limit strategy per-row reasons and eligible ranking without issuing a command",function()
    local app,bots,C,nav=start();launch()
    rows({"1. Poczta wolnego miasta Nuln miedzymiastowa 5.00 kg 2 zlote monety [x1]",
        "2. Poczta w Bissingen miedzymiastowa 6.00 kg 1 zlota moneta [x1]",
        "3. Poczta w Bissingen miedzymiastowa 8.00 kg 5 zlotych monet [x1]"})
    T.eq("wybierz paczke 1",nextSend());T.eq(true,diagnostic(C,1).eligible);T.eq(true,diagnostic(C,2).eligible)
    T.ok(diagnostic(C,1).score>diagnostic(C,2).score)
    T.contains(diagnostic(C,1).reason,"rankingu 1");T.contains(diagnostic(C,2).reason,"rankingu 2")
    local before=#M.sent;M.clear_output();M.input("/paczki oferty")
    T.eq(before,#M.sent);T.contains(C.norm(M.text()),"nuln");T.contains(C.norm(M.text()),"bissingen")
    T.contains(M.text(),"6.2");T.contains(C.norm(M.text()),"waga");T.contains(C.norm(M.text()),"rankingu")
    T.eq(6.2,C.offersLimit);T.eq("local_first",C.offersStrategy);T.eq(IDS[1],sourceId(C.offersSource))
    T.eq("running",C.mode,M.text());T.ok(bots.status());T.eq(0,#app.errors,M.text())
end)
T.test("zero eligible offers log weight and route reasons before automatic movement to another office",function()
    local app,bots,C,nav=start();launch()
    rows({"1. Poczta w Bissingen miedzymiastowa 8.00 kg 5 zlotych monet [x1]",
        "2. Nieznany Tragarz miejscowa 0.50 kg 18 zlotych monet [x1]"})
    T.eq("wyjscie",nextSend());T.ok(C.relocation);T.eq(IDS[5],C.relocation.to.id)
    local text=M.text();local evaluation=text:find("Ocena ofert:",1,true);local movement=text:find("Przechodze",1,true)
    T.ok(evaluation and movement and evaluation<movement,text)
    T.contains(C.norm(text),"waga");T.contains(C.norm(text),"trasa");T.contains(text,"/paczki oferty")
    T.eq(false,diagnostic(C,1).eligible);T.eq("weight",diagnostic(C,1).category)
    T.eq(false,diagnostic(C,2).eligible);T.eq("route",diagnostic(C,2).category)
    T.eq(6.2,C.config.maxKg);T.eq(IDS[1],sourceId(C.offersSource));T.eq(0,#app.errors,M.text())
end)

T.test("a cheap heavy local parcel beats a rich light intercity offer and both domain spellings are excluded",function()
    local app,bots,C=start();launch()
    rows({"1. Poczta w Bissingen miedzymiastowa 0.10 kg 20 zlotych monet [x1]",
        "2. Poczta wolnego miasta Nuln miedzykrainowa 0.10 kg 90 zlotych monet [x1]",
        "3. Poczta wolnego miasta Nuln miedzydomenowa 0.10 kg 90 zlotych monet [x1]",
        "8. Johan Kornwalz miejscowa 6.00 kg 1 miedziana moneta [x1]"})
    T.eq("wybierz paczke 8",nextSend());T.eq("miejscowa",C.selected.kind)
    T.eq("deferred",diagnostic(C,1).category)
    T.eq(false,diagnostic(C,2).eligible);T.eq(false,diagnostic(C,3).eligible)
    T.eq(0,#app.errors,M.text())
end)
T.test("two complete local deliveries exhaust the live board before selecting an intercity parcel",function()
    local app,bots,C=start();launch()
    local intercity="1. Poczta w Bissingen miedzymiastowa 0.10 kg 20 zlotych monet [x1]"
    for count=2,1,-1 do
        rows({intercity,"7. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x"..count.."]"})
        T.eq("wybierz paczke 7",nextSend());T.eq("miejscowa",C.selected.kind)
        T.eq("deferred",diagnostic(C,1).category)
        deliverNpcAndReturn()
        T.eq(3-count,C.stats.delivered)
        T.eq("przeczytaj tablice",nextSend())
    end
    rows({intercity,"7. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x0]"})
    T.eq("wybierz paczke 1",nextSend());T.eq("miedzymiastowa",C.selected.kind)
    T.eq(true,C.selected.route.postal);T.eq(IDS[5],C.selected.route.targetId)
    T.eq("empty",diagnostic(C,7).category);T.eq(2,C.stats.delivered)
    M.line("Bierzesz paczke przeznaczona dla: Poczta w Bissingen.")
    T.eq("wyjscie",nextSend());T.eq("e",nextSend());T.eq("e",nextSend())
    T.eq("oddaj paczke",nextSend())
    M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
    M.line("Urzednik wyplaca ci 20 zlotych monet za trud.")
    T.eq("przeczytaj tablice",nextSend());T.eq(IDS[5],sourceId(C.source));T.eq(3,C.stats.delivered)
    rows({"1. Poczta wolnego miasta Nuln miedzymiastowa 0.10 kg 20 zlotych monet [x1]",
        "7. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x1]"})
    T.eq("wybierz paczke 7",nextSend());T.eq("miejscowa",C.selected.kind)
    T.eq("deferred",diagnostic(C,1).category)
    T.eq(0,#app.errors,M.text())
end)
T.test("local availability avoids route calculations for deferred and excluded parcel types",function()
    local app,bots,C=start();C:captureSource()
    local original=C.resolveRoute
    local consulted={}
    C.resolveRoute=function(self,name)
        consulted[C.norm(name)]=(consulted[C.norm(name)] or 0)+1
        return original(self,name)
    end
    local ranked=C:rank({assert(C:parseOffer("1. Poczta w Bissingen miedzymiastowa 1.00 kg 20 zlotych monet [x1]")),
        assert(C:parseOffer("2. Poczta wolnego miasta Nuln miedzydomenowa 1.00 kg 90 zlotych monet [x1]")),
        assert(C:parseOffer("3. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x1]"))})
    T.eq(3,ranked[1].number);T.eq(1,consulted["johan kornwalz"])
    T.eq(nil,consulted["poczta w bissingen"]);T.eq(nil,consulted["poczta wolnego miasta nuln"])
    T.eq("deferred",diagnostic(C,1).category);T.eq(0,#app.errors,M.text())
end)
T.test("local exhaustion unlocks only office-to-office intercity parcels on the next board",function()
    local app,bots,C=start();C:captureSource()
    local localOffer=assert(C:parseOffer("9. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x2]"))
    local intercity=assert(C:parseOffer("1. Poczta w Bissingen miedzymiastowa 0.10 kg 20 zlotych monet [x1]"))
    local domain=assert(C:parseOffer("2. Poczta wolnego miasta Nuln miedzykrainowa 0.10 kg 90 zlotych monet [x1]"))
    for count=2,1,-1 do
        localOffer.count=count
        local ranked=C:rank({intercity,domain,localOffer})
        T.eq(9,ranked[1].number);T.eq("deferred",diagnostic(C,1).category)
    end
    localOffer.count=0
    local ranked=C:rank({intercity,domain,localOffer})
    T.eq(1,#ranked);T.eq(1,ranked[1].number);T.eq(true,ranked[1].route.postal)
    T.eq("empty",diagnostic(C,9).category);T.eq(false,diagnostic(C,2).eligible)
    T.eq(0,#app.errors,M.text())
end)
T.test("unknown local recipients are skipped without displacing another available local",function()
    local app,bots,C=start();launch()
    rows({"1. Nieznany Tragarz miejscowa 0.10 kg 10 zlotych monet [x1]",
        "2. Poczta w Bissingen miedzymiastowa 0.10 kg 20 zlotych monet [x1]",
        "7. Johan Kornwalz miejscowa 1.00 kg 1 miedziana moneta [x1]"})
    T.eq("wybierz paczke 7",nextSend());T.eq("route",diagnostic(C,1).category)
    T.eq("deferred",diagnostic(C,2).category);T.eq(0,#app.errors,M.text())
end)
T.test("a failed local route allows a real intercity office but never an intercity NPC",function()
    local app,bots,C=start();C:captureSource()
    local ranked=C:rank({assert(C:parseOffer("1. Nieznany Tragarz miejscowa 1.00 kg 10 zlotych monet [x1]")),
        assert(C:parseOffer("2. Johan Kornwalz miedzymiastowa 1.00 kg 20 zlotych monet [x1]")),
        assert(C:parseOffer("3. Poczta w Bissingen miedzymiastowa 1.00 kg 1 miedziana moneta [x1]"))})
    T.eq(1,#ranked);T.eq(3,ranked[1].number);T.eq(true,ranked[1].route.postal)
    T.eq(false,diagnostic(C,2).eligible);T.eq(0,#app.errors,M.text())
end)

T.run()
