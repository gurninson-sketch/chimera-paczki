-- Ebino continuation through the real native loader, Boty, mapper, GMCP,
-- planner, parcel memory and bag groups. The Urbimo <-> Ebino corridor is
-- extracted from the pinned public world data; no intercity link is invented.
-- Run from chimera-main or chimera-501:
--   texlua ../chimera-paczki-github/tests/test_update_depots_native.lua
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local json=require("chimera.core.json")
local fs=require("lfs")
local SOURCE=assert(debug.getinfo(1,"S").source:sub(2):match("^(.*)/tests/[^/]+$"),"run using the test file path")
local URBIMO="0a647e20ca6f97f7"
local EBINO="d69d73a15fc1b87d"
local PLAZA="9a8f8bad52dd45f7"
local ACTOR="Testdepot"
local DIRECTIONS={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",nw="polnocny-zachod",
    se="poludniowy-wschod",sw="poludniowy-zachod",u="gora",d="dol"}
local SHORT={};for short,long in pairs(DIRECTIONS) do SHORT[long]=short end
local REVERSE={n="s",s="n",e="w",w="e",ne="sw",nw="se",se="nw",sw="ne",u="d",d="u"}
local OPEN="otworz swoj plecak"
local CLOSE="zamknij swoj plecak"
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local COIN_ACK="Wkladasz siedem srebrnych monet i trzy zlote monety do otwartego skorzanego plecaka."
local function read(path)
    local file=assert(io.open(path,"rb"));local body=file:read("*a");file:close();return body
end
local PUBLIC={}
for filename in fs.dir("data/world") do
    if filename:match("%.json$") then
        local area=assert(json.decode(read("data/world/"..filename)))
        for id,room in pairs(area.rooms or {}) do
            room.id=id;room.area=area.area;room.area_id=area.area_id;PUBLIC[id]=room
        end
    end
end
local function publicPath(from,target)
    local queue,head,seen,prior={from},1,{[from]=true},{}
    while queue[head] do
        local at=queue[head];head=head+1
        if at==target then break end
        local commands={};for long in pairs(PUBLIC[at].exits or {}) do if SHORT[long] then commands[#commands+1]=long end end
        table.sort(commands)
        for _,long in ipairs(commands) do
            local to=PUBLIC[at].exits[long]
            local back=PUBLIC[to] and PUBLIC[to].exits and PUBLIC[to].exits[DIRECTIONS[REVERSE[SHORT[long]]]]
            if back==at and not seen[to] then
                seen[to]=true;prior[to]={from=at,command=SHORT[long]};queue[#queue+1]=to
            end
        end
    end
    assert(seen[target],"public bidirectional corridor missing")
    local path,at={},target
    while at~=from do local step=prior[at];table.insert(path,1,{from=step.from,to=at,command=step.command});at=step.from end
    return path
end
local OUTWARD=publicPath(URBIMO,EBINO)
local INWARD=publicPath(EBINO,URBIMO)
local INCLUDED={[URBIMO]=true,[EBINO]=true}
for _,path in ipairs({OUTWARD,INWARD}) do for _,step in ipairs(path) do INCLUDED[step.from]=true;INCLUDED[step.to]=true end end
local IDS={URBIMO,EBINO}
local others={};for id in pairs(INCLUDED) do if id~=URBIMO and id~=EBINO then others[#others+1]=id end end;table.sort(others)
for _,id in ipairs(others) do IDS[#IDS+1]=id end
local INDEX={};for index,id in ipairs(IDS) do INDEX[id]=index end
local WORLD,LINKS={},{}
for index,id in ipairs(IDS) do
    local source=PUBLIC[id]
    local room={id=id,name=source.name,area=source.area,area_id=source.area_id,indoors=source.indoors,terrain=source.terrain,exits={}}
    local links={}
    for long,to in pairs(source.exits or {}) do
        if SHORT[long] and INCLUDED[to] then room.exits[long]=to;links[SHORT[long]]=INDEX[to] end
    end
    WORLD[id]=room;LINKS[index]=links
end
T.module("test.world.update_depots",function()
    return {name="world",setup=function()
        return {room=function(id) return WORLD[id] end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return "public-urbimo-ebino-corridor" end,npcs=function() return {} end}
    end}
end)
local function prepare()
    for _,name in ipairs({"init.lua","core.lua","routes.lua","new_routes.lua","npc.lua","travel.lua","offices.lua",
        "scope.lua","road.lua","ferry.lua","journey.lua","transport_data.lua","inventory.lua","memory.lua","path.lua",
        "postal.lua","checkpoint.lua","escape.lua","recovery.lua","eta.lua","karak_transport.lua","city.lua","city_data.lua","planner.lua","updater.lua"}) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read(SOURCE.."/chimera_wtyczki/chimera_paczki/"..name))
    end
    local areas={}
    for index,id in ipairs(IDS) do
        local room=WORLD[id]
        if not areas[room.area_id] then areas[room.area_id]=M.add_area(room.area) end
        addRoom(index);setRoomIDbyHash(index,id);setRoomName(index,room.name);setRoomArea(index,areas[room.area_id])
        setRoomCoordinates(index,index,0,0);setRoomWeight(index,1)
    end
    for from,links in pairs(LINKS) do for command,to in pairs(links) do setExit(from,to,command) end end
    _G.getPath=function(from,target)
        if from==target then speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true end
        local queue,head,seen,prior={from},1,{[from]=true},{}
        while queue[head] do
            local at=queue[head];head=head+1
            local commands={};for command in pairs(LINKS[at] or {}) do commands[#commands+1]=command end;table.sort(commands)
            for _,command in ipairs(commands) do
                local to=LINKS[at][command]
                if not seen[to] then seen[to]=true;prior[to]={from=at,command=command};queue[#queue+1]=to end
            end
        end
        if not seen[target] then return false end
        local reversed,at={},target
        while at~=from do local step=prior[at];reversed[#reversed+1]={room=at,command=step.command};at=step.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for index=#reversed,1,-1 do
            speedWalkDir[#speedWalkDir+1]=reversed[index].command
            speedWalkPath[#speedWalkPath+1]=reversed[index].room;speedWalkWeight[#speedWalkWeight+1]=1
        end
        return true
    end
end
local function info(index)
    local room=WORLD[IDS[index]]
    return {id=room.id,name=room.name,area=room.area,area_id=room.area_id,indoors=room.indoors and 1 or 0,exits=room.exits}
end
local function count(command)
    local total=0;for _,sent in ipairs(M.sent) do if sent==command then total=total+1 end end;return total
end
local function waitFor(predicate,seconds,why)
    for _=1,math.ceil((seconds or 90)/.05) do if predicate() then return end;M.advance(.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local function start(options)
    options=options or {}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.update_depots","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local api,C=record.api,record.api.engine
    local s={current=1,moves={},commands={},boardRooms={},pending=0,parcel=nil,bagOpen=false,
        pickups=0,delivered=false,coinStows=0,coinAcknowledged=false,nextCalls=0,officeResolves={},safeChecks={}}
    function s:entities() M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities={}}) end
    function s:coinAck() self.coinAcknowledged=true;M.line(COIN_ACK) end
    local originalNext=api.offices.next
    api.offices.next=function(source,...)
        s.nextCalls=s.nextCalls+1
        return originalNext(source,...)
    end
    local originalResolve=api.offices.resolve
    api.offices.resolve=function(query,...)
        s.officeResolves[#s.officeResolves+1]={query=query,from=IDS[s.current]}
        return originalResolve(query,...)
    end
    local originalCost=api.navigator.safeCost
    api.navigator.safeCost=function(from,to,...)
        if s.delivered then s.safeChecks[#s.safeChecks+1]={from=from,to=to} end
        return originalCost(from,to,...)
    end
    local wire=send
    _G.send=function(command,...)
        local denied=M.denied;raiseEvent("sysDataSendRequest",command);if M.denied~=denied then return end
        wire(command,...)
        s.commands[#s.commands+1]={command=command,id=IDS[s.current],at=M.now}
        local to=LINKS[s.current][command]
        if to then
            T.eq("running",C.mode,"movement must retain courier ownership")
            if IDS[s.current]==EBINO then
                T.eq(true,s.coinAcknowledged,"leave Ebino only after own reward-storage ACK")
                T.eq(false,s.bagOpen,"close own backpack before leaving Ebino")
            end
            s.pending=s.pending+1;T.eq(1,s.pending,"overlapping mapped movement")
            s.moves[#s.moves+1]={from=IDS[s.current],to=IDS[to],command=command}
            tempTimer(.02,function()
                s.pending=s.pending-1;s.current=to;M.packet("Room.Info",info(to));s:entities()
                M.line(WORLD[IDS[to]].name..".")
                if IDS[to]==EBINO then M.line("Nie otrzymales zadnych nowych listow.") end
            end)
        elseif command=="zerknij" then tempTimer(.02,function() M.line(WORLD[IDS[s.current]].name..".") end)
        elseif command=="przeczytaj tablice" then
            s.boardRooms[#s.boardRooms+1]=IDS[s.current]
            T.eq(URBIMO,IDS[s.current],"delivery-only Ebino must never receive a parcel-board request")
            tempTimer(.02,function()
                M.line("Przesylki dostepne dla Agente Postalle di Tilea:")
                if not s.delivered then M.line("4. Poczta w Ebino miedzymiastowa 6.00 kg 3 zlote i 7 srebrnych monet [x1]") end
                M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
            end)
        elseif command=="wybierz paczke 4" then
            T.eq(URBIMO,IDS[s.current]);s.pickups=s.pickups+1;T.eq(1,s.pickups,"unexpected additional pickup")
            tempTimer(.02,function() s.parcel="hands";M.line("Bierzesz paczke przeznaczona dla: Poczta w Ebino.") end)
        elseif command=="oddaj paczke" then
            T.eq(EBINO,IDS[s.current]);T.eq("hands",s.parcel)
            tempTimer(.02,function()
                s.delivered=true;s.parcel="delivered"
                M.line("Zostawiasz przesylke w okienku urzedu pocztowego.")
                M.line("Urzednik wyplaca ci 3 zlote i 7 srebrnych monet za trud.")
            end)
        elseif command==OPEN then tempTimer(.02,function() s.bagOpen=true;M.line("Otwierasz skorzany plecak.") end)
        elseif command==CLOSE then tempTimer(.02,function() s.bagOpen=false;M.line("Zamykasz skorzany plecak.") end)
        elseif command==STOW or command==TAKE then
            T.eq(true,s.bagOpen);T.eq(command==STOW and "hands" or "bag",s.parcel)
            tempTimer(.02,function()
                s.parcel=command==STOW and "bag" or "hands"
                M.line(command==STOW and "Wkladasz paczke do otwartego skorzanego plecaka." or "Bierzesz paczke z otwartego skorzanego plecaka.")
            end)
        elseif command==COINS then
            T.eq(EBINO,IDS[s.current]);T.eq(true,s.bagOpen);T.eq(true,s.delivered)
            s.coinStows=s.coinStows+1
            if not options.holdCoinAck then tempTimer(.02,function() s:coinAck() end) end
        else
            error("unexpected game command in postal continuation: "..tostring(command))
        end
    end
    local gmcpWire=sendGMCP
    _G.sendGMCP=function(command,...)
        gmcpWire(command,...)
        if command:find("Core.Supports.Add",1,true) and command:find("Chimera.Room.Entities",1,true) then
            tempTimer(.01,function() s:entities() end)
        end
    end
    C.config.autoBackpack=false;C:save()
    M.packet("Char.Info",{name=ACTOR,id="native-ebino-test-character"})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10});M.packet("Room.Info",info(1));s:entities()
    M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak")
    T.eq(true,app.loader.records.bags.api.configured("inne"));T.eq(true,app.loader.records.bags.api.configured("monety"))
    M.input("/paczki bank off");M.input("/paczki limit 6.1");M.input("/paczki tempo 0.15")
    T.eq(false,C.config.bankEnabled);T.eq(true,C.config.roam)
    return app,app.loader.records.bots.api,C,api,s
end
local function completed(s) return s.delivered and s.coinAcknowledged and #s.boardRooms==2 end
local function verifyCompleted(app,bots,C,api,s)
    T.eq(URBIMO,IDS[s.current]);T.eq(URBIMO,C.source.id);T.eq(nil,C.job)
    T.eq(1,s.pickups);T.eq(1,C.stats.delivered);T.eq(3,C.stats.gold);T.eq(7,C.stats.silver);T.eq(1,s.coinStows)
    T.eq(1,count("oddaj paczke"));T.eq(1,count(STOW));T.eq(1,count(TAKE));T.eq(1,count(COINS))
    T.eq(0,count("przedstaw sie"));T.eq(0,count("zwroc paczke"));T.eq(0,count("zdenominuj"))
    T.eq(0,s.nextCalls,"a verified issuing office avoids global next-office search")
    T.eq(1,#s.officeResolves);T.eq(URBIMO,s.officeResolves[1].query);T.eq(EBINO,s.officeResolves[1].from)
    T.eq(2,#s.safeChecks,"validate only the known issuing office in both directions")
    T.eq(INDEX[EBINO],s.safeChecks[1].from);T.eq(INDEX[URBIMO],s.safeChecks[1].to)
    T.eq(INDEX[URBIMO],s.safeChecks[2].from);T.eq(INDEX[EBINO],s.safeChecks[2].to)
    T.eq(2,#s.boardRooms);T.eq(URBIMO,s.boardRooms[1]);T.eq(URBIMO,s.boardRooms[2])
    T.eq(#OUTWARD+#INWARD,#s.moves,"follow the real public corridor in each direction")
    T.eq(EBINO,s.moves[#OUTWARD].to);T.eq(EBINO,s.moves[#OUTWARD+1].from)
    T.eq("ne",s.moves[#OUTWARD+1].command);T.eq(PLAZA,s.moves[#OUTWARD+1].to)
    T.eq(false,s.bagOpen);T.eq("running",C.mode);T.ok(bots.status(),M.text())
    T.eq(false,api.inventory.exportState().coinsUncertain)
    T.not_contains(M.text(),"Bot paczki zatrzymany");T.eq(0,#app.errors,M.text())
end

T.test("public Ebino identity and postal alias survive the real native resolver as delivery-only",function()
    T.eq("Ebinska placowka kurierska",PUBLIC[EBINO].name)
    T.eq(PLAZA,PUBLIC[EBINO].exits["polnocny-wschod"])
    T.eq(EBINO,PUBLIC[PLAZA].exits["poludniowy-zachod"])
    local app,bots,C,api,s=start()
    for _,label in ipairs({"Poczta w Ebino","Ebinska placowka kurierska","Urzad pocztowy w Ebino"}) do
        local route=assert(api.navigator.resolve(label),M.text())
        T.eq(true,route.postal);T.eq(EBINO,route.targetId);T.eq(EBINO,route.roomIds[INDEX[EBINO]])
    end
    T.eq(false,api.offices.canDispatch(EBINO))
    local found
    for _,record in ipairs(api.offices.catalogue()) do if record.id==EBINO then found=record end end
    T.ok(found);T.eq(true,found.deliveryOnly);T.eq("Ebino",found.city)
    T.eq(0,#app.errors,M.text())
end)
T.test("native Urbimo delivery to Ebino settles reward then returns to the issuing post and reads its board without STOP",function()
    local app,bots,C,api,s=start()
    M.input("/paczki start")
    waitFor(function() return completed(s) end,180,"full Urbimo -> Ebino -> issuing-office continuation")
    verifyCompleted(app,bots,C,api,s)
    M.input("/bot stop") -- Cleanup happens after the complete uninterrupted course.
end)
T.test("native Ebino continuation waits for our coin-storage acknowledgement rather than another courier's prose",function()
    local app,bots,C,api,s=start({holdCoinAck=true})
    M.input("/paczki start")
    waitFor(function() return s.coinStows==1 end,120,"Ebino reward-storage request")
    T.eq(EBINO,IDS[s.current]);T.eq(1,#s.boardRooms);T.eq(#OUTWARD,#s.moves)
    T.ok(C.job and C.job.delivered and C.job.coinsPending);T.eq(0,s.nextCalls)
    local before=#M.sent
    M.line("Gror wklada siedem srebrnych monet i trzy zlote monety do otwartego skorzanego plecaka.")
    M.advance(.2);T.eq(before,#M.sent);T.eq(EBINO,IDS[s.current]);T.eq(false,s.coinAcknowledged)
    s:coinAck()
    waitFor(function() return completed(s) end,120,"own storage ACK unlocks uninterrupted postal return")
    verifyCompleted(app,bots,C,api,s)
    M.input("/bot stop")
end)
T.run()
