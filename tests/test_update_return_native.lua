-- Real native loader/map/GMCP, synthetic absent patrol captain and parcel server.
-- The mapped Kreutzhofen streets and Soll bridge are the public fixture used
-- by the Nikolaus regression; Bruno's presence is deliberately always false.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local FULL="Bruno Rottel"
local TITLE="Bruno Rottel"
local SHORT="brodaty mocny mezczyzna"
local AREA="b96cb35a938e6b50"
local IDS={"315106e45b840273","83f87494c9beb403","fb5d7d9ec0051590","4fa405b9e7ecef09",
    "abb5b13c11bd6ecd","a7b930856f41329a","82c677584bf720ed","f584363395490d91",
    "bef84ee575c215db","4d572cb0fdc78834"}
local NAMES={"Poczta miasta Kreutzhofen","Uliczka Kreutzhofen","Uliczka nadrzeczna","Poludniowa strona mostu",
    "Most na rzece Soll","Polnocna strona mostu","Uliczka Kreutzhofen","Uliczka Kreutzhofen",
    "Uliczka Kreutzhofen","Warsztat ciesielski"}
local LINKS={
    [1]={n=2},[2]={s=1,n=3},[3]={s=2,ne=4},[4]={sw=3,n=5},[5]={s=4,n=6},
    [6]={s=5,n=7},[7]={s=6,e=8},[8]={w=7,e=9},[9]={w=8,n=10},[10]={s=9},
}
local worldMode=false
local WORLD={}
for index,id in ipairs(IDS) do
    local urban=index==2 or index==3 or index==7 or index==8 or index==9
    WORLD[id]={id=id,name=NAMES[index],area="Kreutzhofen",area_id=AREA,
        indoors=index==1 or index==10,terrain=urban and "miasto" or nil}
end
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",sw="poludniowy-zachod",
    se="poludniowy-wschod",nw="polnocny-zachod"}
local catalogueMode="unique"
T.module("test.world.update_return",function()
    return {name="world",setup=function()
        return {room=function(id) return worldMode and WORLD[id] or nil end,terrains=function() return {} end,marks=function() return {} end,
            gates=function() return {} end,version=function() return nil end,npcs=function()
                local rows={}
                if catalogueMode~="none" then
                    local title=catalogueMode=="prefix" and "Nikolaus Schmidt Senior" or
                        (catalogueMode=="wrong" and "Nikolaus Nowak" or TITLE)
                    rows[#rows+1]={name="Bruno",short=SHORT,title=title,room=IDS[10]}
                    rows[#rows+1]={name="Nikolaus",short="niski ciemnowlosy mezczyzna",title="Nikolaus Schmidt",room=IDS[10]}
                    if catalogueMode=="ambiguous" then rows[#rows+1]={name="Nikolaus",short="stary siwy krasnolud",
                        title="Nikolaus Schmidt, drugi miecznik",room=IDS[9]} end
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
    return {id=IDS[index],name=NAMES[index],area="Kreutzhofen",area_id=AREA,
        indoors=(index==1 or index==10) and 1 or 0,exits=exits}
end
local function count(command)
    local n=0;for _,sent in ipairs(M.sent) do if sent==command then n=n+1 end end;return n
end
local function waitFor(predicate,limit,why)
    for _=1,math.ceil((limit or 60)/0.05) do if predicate() then return end;M.advance(0.05) end
    T.ok(predicate(),(why or "condition timed out").."\n"..M.text())
end
local STOW="wloz paczke do swojego plecaka"
local TAKE="wez paczke z swojego plecaka"
local COINS="wloz monety do swojego plecaka"
local OPEN="otworz swoj plecak"
local CLOSE="zamknij swoj plecak"
local function start(options)
    options=options or {};catalogueMode=options.catalogue or "unique";worldMode=options.world==true
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.update_return","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.ok(record and record.status=="running",M.text())
    local C,api=record.api.engine,record.api
    local server={current=1,known=options.known~=false,moves={},gifts={},pending=0,
        noIntroduction=options.noIntroduction==true,introductions={},fullProof=false,title=options.title or TITLE,
        absent=true,returned=false,bags=options.bags==true,parcel="hands",bagOpen=false,money=2,rewardStows=0,rewarded=false,rewardReplies=0}
    function server:entities()
        local rows={}
        if self.current==10 and not self.absent then rows[#rows+1]={id="test-bruno",name=self.known and "Bruno" or SHORT,
            title=options.liveTitle and self.title or nil,kind="npc",relation="neutral"} end
        if self.current==10 then rows[#rows+1]={id="test-nikolaus",name="Nikolaus",title="Nikolaus Schmidt",kind="npc",relation="neutral"} end
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
        elseif command=="zerknij" then
            tempTimer(0.05,function()
                M.line("Poczta.");M.line("Jest tutaj jedno widoczne wyjscie: polnocny-zachod.")
            end)
        elseif command=="przedstaw sie" then
            server.introductions[#server.introductions+1]={room=server.current,at=M.now}
            if server.current==10 and not server.noIntroduction and not server.absent then
                tempTimer(0.05,function()
                    local prefix=server.known and "Bruno" or "Brodaty mocny mezczyzna"
                    M.line(prefix.." przedstawia sie jako:");M.line(server.title..".")
                    server.known,server.fullProof=true,true;server:entities()
                end)
            elseif server.current==10 then
                tempTimer(0.05,function() M.line("Nikolaus przedstawia sie jako:");M.line("Nikolaus Schmidt.");server:entities() end)
            end
        elseif command=="przeczytaj tablice" and server.returned then
            tempTimer(0.05,function()
                M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
                M.line("1. Bruno Rottel miejscowa 1.00 kg 99 srebrnych monet [x3]")
                M.line("2. Nikolaus Schmidt miejscowa 1.00 kg 1 srebrna moneta [x1]")
                M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
            end)
        elseif command=="zwroc paczke" then
            T.eq(1,server.current,"return at issuing office only");T.eq("hands",server.parcel,"extract parcel before return")
            if options.stopBeforeAck then tempTimer(0.01,function() M.input("/bot stop") end) end
            tempTimer(0.05,function()
                server.parcel="returned";server.returned=true
                M.line("Oddajesz przesylke z powrotem do urzedu. Nikt ci za nia nie zaplaci -- droga nie zostala przebyta.")
            end)
        elseif command=="oddaj paczke" then
            T.eq("hands",server.parcel,"a parcel still inside the backpack was gifted")
            server.gifts[#server.gifts+1]={room=server.current,known=server.known,fullProof=server.fullProof,at=M.now}
            tempTimer(0.05,function()
                if server.current==10 and not server.absent then
                    M.line("Wrecasz paczke adresatowi.");server.parcel="delivered";server.rewarded=true;server.money=server.money+13
                    server.rewardReplies=server.rewardReplies+1
                    M.line("Adresat wrecza ci 13 srebrnych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.");M.line("Musisz odnalezc "..FULL.." i wreczyc mu paczke osobiscie.") end
            end)
        elseif command==OPEN then tempTimer(0.05,function() server.bagOpen=true;M.line("Otwierasz skorzany plecak.") end)
        elseif command==CLOSE then tempTimer(0.05,function() server.bagOpen=false;M.line("Zamykasz skorzany plecak.") end)
        elseif command==STOW or command==TAKE then
            T.eq(true,server.bagOpen,"parcel movement must open the backpack")
            T.eq(command==STOW and "hands" or "bag",server.parcel)
            tempTimer(0.05,function()
                server.parcel=command==STOW and "bag" or "hands"
                M.line(command==STOW and "Wkladasz paczke do otwartego skorzanego plecaka." or "Bierzesz paczke z otwartego skorzanego plecaka.")
            end)
        elseif command==COINS then
            T.eq(true,server.bagOpen,"coin movement must open the backpack")
            T.ok(server.money>0,"fixture received a duplicate coin transfer")
            tempTimer(0.05,function()
                if server.rewarded then server.rewardStows=server.rewardStows+1 end
                M.line("Wkladasz "..server.money.." srebrnych monet do otwartego skorzanego plecaka.");server.money=0
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
    M.packet("Char.Info",{name=options.actor or "Yarrim",id="nikolaus-courier-"..(options.actor or "Yarrim")})
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=10});M.packet("Room.Info",info(1));server:entities()
    if server.bags then M.input("/pojemniki inne plecak");M.input("/pojemniki monety plecak") end
    return app,app.loader.records.bots.api,C,api.navigator,server,api
end

local function beginBruno(C)
    C.config.searchSeconds=2;C.config.recipientCooldown=1800;C:save()
    C.stats.delivered=7;C.stats.silver=21
    M.input("/bot paczki")
    waitFor(function() return count("przeczytaj tablice")>0 end,15,"initial board")
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("1. Bruno Rottel miejscowa 1.70 kg 9 srebrnych monet [x3]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return count("wybierz paczke 1")>0 end,15,"Bruno selected")
    M.line("Bierzesz paczke przeznaczona dla: Bruno Rottel.")
end
T.test("absent Bruno times out, returns actual backpack parcel and chooses another local despite available Bruno",function()
    local app,bots,C,nav,s,api=start({bags=true})
    beginBruno(C)
    waitFor(function() return count("wybierz paczke 2")>0 end,90,"new delivery after confirmed return")
    T.eq(1,count("zwroc paczke"));T.eq(1,count("wybierz paczke 1"));T.eq(1,count("wybierz paczke 2"))
    T.eq(1,count(STOW));T.eq(1,count(TAKE));T.eq("returned",s.parcel);T.eq(false,s.bagOpen)
    T.eq(1,s.current);T.eq(nil,C.job);T.eq(7,C.stats.delivered);T.eq(21,C.stats.silver)
    T.eq("nikolaus schmidt",C.selected.name);T.eq(false,C.awaitingReturn)
    T.eq(false,C.offerDiagnostics[1].eligible);T.ok(C.offerDiagnostics[1].reason~="")
    T.eq(0,#s.gifts,"absence must not produce blind handover attempts");T.eq(0,#app.errors,M.text())
end)
T.test("native STOP before return ACK clears the parcel on late ACK without restarting",function()
    local app,bots,C,nav,s,api=start({bags=true,stopBeforeAck=true})
    beginBruno(C)
    waitFor(function() return s.returned end,90,"late return acknowledgement")
    M.advance(1)
    T.eq(1,count("zwroc paczke"));T.eq(nil,C.job);T.eq(false,C.awaitingReturn)
    T.eq(0,count("wybierz paczke 2"));T.eq(1,count("przeczytaj tablice"));T.eq("stopped",C.mode)
    T.eq(nil,bots.status());T.eq(7,C.stats.delivered);T.eq(21,C.stats.silver);T.eq(0,#app.errors,M.text())
end)
T.run()
