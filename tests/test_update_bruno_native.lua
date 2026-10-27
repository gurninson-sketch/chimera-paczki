-- Anonymous Bruno patrol: actual Kreutzhofen hashes/ordinary links and the
-- four descriptors observed with three successful handovers. No invented NPC
-- name, introduction, title or catalogue identity is supplied to the courier.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local ROOT=arg[0]:gsub("\\","/"):match("^(.*)/tests/test_update_bruno_native%.lua$") or ".."
local runtime=dofile(ROOT.."/chimera_wtyczki/chimera_paczki/updater.lua")
local json=require("chimera.core.json")
local AREA="b96cb35a938e6b50"
local FULL="Bruno Rottel"
local IDS={"315106e45b840273","83f87494c9beb403","fb5d7d9ec0051590","4fa405b9e7ecef09",
    "4679c95a3bd909d6","5f8910ee564c903e","a2330136a0374a0d"}
local SHORTS={"schludny orlonosy mezczyzna","podekscytowany orlonosy mezczyzna",
    "hardy czarnooki mezczyzna","niebieskooki starszy mezczyzna"}
local LINKS={[1]={n=2},[2]={s=1,n=3},[3]={s=2,ne=4},[4]={sw=3,se=5},
    [5]={nw=4,s=6},[6]={n=5,e=7},[7]={w=6}}
local LONG={n="polnoc",s="poludnie",e="wschod",w="zachod",ne="polnocny-wschod",
    sw="poludniowy-zachod",nw="polnocny-zachod",se="poludniowy-wschod"}
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local public=json.decode(read(ROOT.."/../chimera-501/data/world/"..AREA..".json"))
local mode,overrides
T.module("test.world.bruno_patrol",function()
    return {name="world",setup=function() return {
        room=function(id)
            if overrides and overrides[id]=="error" then error("world service unavailable") end
            if overrides and overrides[id] then return overrides[id] end
            if mode=="empty" then return nil end
            local row=public.rooms[id];if not row then return nil end
            local copy={};for k,v in pairs(row) do copy[k]=v end
            copy.id,copy.area_id,copy.area=id,AREA,public.area;return copy
        end,npcs=function() return {} end,terrains=function() return {} end,
        marks=function() return {} end,gates=function() return {} end,version=function() return "test" end,
    } end}
end)
local function prepare()
    for _,name in ipairs(runtime.files) do M.write_file("chimera_wtyczki/chimera_paczki/"..name,
        read(ROOT.."/chimera_wtyczki/chimera_paczki/"..name)) end
    local area=M.empty_map("Kreutzhofen")
    for i,id in ipairs(IDS) do addRoom(i);setRoomIDbyHash(i,id);setRoomName(i,public.rooms[id].name)
        setRoomArea(i,area);setRoomCoordinates(i,i,0,0) end
    for from,links in pairs(LINKS) do for cmd,to in pairs(links) do setExit(from,to,cmd) end end
    _G.getPath=function(from,to)
        local queue,seen,prev={from},{[from]=true},{};local head=1
        while queue[head] do
            local at=queue[head];head=head+1
            for cmd,target in pairs(LINKS[at] or {}) do if not seen[target] then
                seen[target]=true;prev[target]={from=at,cmd=cmd};queue[#queue+1]=target
            end end
        end
        if not seen[to] then return false end
        local rev,at={},to;while at~=from do local p=prev[at];rev[#rev+1]={map=at,cmd=p.cmd};at=p.from end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        for i=#rev,1,-1 do speedWalkDir[#speedWalkDir+1]=rev[i].cmd
            speedWalkPath[#speedWalkPath+1]=rev[i].map;speedWalkWeight[#speedWalkWeight+1]=1 end
        return true
    end
end
local function count(cmd) local n=0;for _,sent in ipairs(M.sent) do if sent==cmd then n=n+1 end end;return n end
local function waitFor(fn,seconds)
    for _=1,math.ceil((seconds or 30)/.05) do if fn() then return end;M.advance(.05) end
    T.ok(fn(),M.text())
end
local function start(opts)
    opts=opts or {};mode=opts.world or "full";overrides={}
    local app=T.start({"chimera.core.cli","chimera.gmcp","test.world.bruno_patrol","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local api=app.loader.records.kurier_paczki.api
    local s={current=1,at=opts.at or 6,moves={},attempts={},holding=false}
    function s:entities()
        local rows={}
        if self.current==self.at then for i,short in ipairs(SHORTS) do
            if self.missing~=i then rows[#rows+1]={id="patrol-"..i,name=short,
                kind=self.player==i and "player" or "npc",relation="neutral"} end
            if self.duplicate==i then rows[#rows+1]={id="duplicate",name=short,kind="npc",relation="neutral"} end
        end end
        M.packet("Chimera.Room.Entities",{room=IDS[self.current],entities=rows})
    end
    function s:position(i)
        self.current=i;local exits={};for cmd,to in pairs(LINKS[i]) do exits[LONG[cmd]]=IDS[to] end
        M.packet("Room.Info",{id=IDS[i],name=public.rooms[IDS[i]].name,area=public.area,area_id=AREA,
            indoors=public.rooms[IDS[i]].indoors and 1 or 0,exits=exits});self:entities()
    end
    local wire=send
    _G.send=function(cmd,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",cmd);if M.denied~=before then return end
        wire(cmd,...)
        local to=LINKS[s.current][cmd]
        if to then s.moves[#s.moves+1]={from=s.current,to=to};tempTimer(.1,function()
            s:position(to);M.line(public.rooms[IDS[to]].name..".") end)
        elseif cmd=="przedstaw sie" then
            tempTimer(.01,function() M.line("Przedstawiasz sie wszystkim.") end)
        elseif cmd=="oddaj paczke" then
            s.attempts[#s.attempts+1]=s.current
            tempTimer(.01,function()
                if s.current==s.at and not s.missing and not s.player and not s.duplicate and s.holding then
                    s.holding=false;M.line("Wrecasz paczke adresatowi.")
                    M.line("Adresat wrecza ci 15 srebrnych monet za trud.")
                else M.line("Adresat nie znajduje sie w tym miejscu.") end
            end)
        end
    end
    local gmcpWire=sendGMCP
    _G.sendGMCP=function(cmd,...)
        gmcpWire(cmd,...)
        if cmd:find("Core.Supports.Add",1,true) and cmd:find("Chimera.Room.Entities",1,true) then
            tempTimer(.01,function() s:entities() end)
        end
    end
    api.engine.config.autoBackpack=false;api.engine.config.maxKg=4;api.engine:save()
    M.packet("Char.Info",{name="Yarrim",id="patrol-test"});s:position(1)
    M.packet("Char.Vitals",{hp=100,mana=100,fatigue=0})
    T.ok(api.memory.remember({recipient=FULL,verified=true,handover=true,reward=true,
        roomHash=IDS[4],map=4,postal=false}))
    return app,api,s
end
local function begin(api,s)
    M.input("/paczki start 1");waitFor(function() return count("przeczytaj tablice")==1 end)
    M.line("Przesylki dostepne dla Kuriera Imperialnej Sluzby Pocztowej:")
    M.line("1. Bruno Rottel miejscowa 3.50 kg 15 srebrnych monet [x2]")
    M.line("Naraz mozna niesc tylko jedna przesylke; oferty sie wyczerpuja.")
    waitFor(function() return count("wybierz paczke 1")==1 end)
    s.holding=true;M.line("Bierzesz paczke przeznaczona dla: Bruno Rottel.")
end
T.test("anonymous patrol is found on another Kreutzhofen street without an introduction reply or fabricated identity",function()
    for _,worldMode in ipairs({"full","empty"}) do
        local app,api,s=start({world=worldMode});begin(api,s)
        waitFor(function() return api.engine.stats.delivered==1 end,100)
        waitFor(function() return app.loader.records.bots.api.status()==nil end,40)
        T.eq(6,s.attempts[1]);T.eq(1,#s.attempts);T.eq(1,s.current)
        T.eq(15,api.engine.stats.silver);T.eq(0,#app.errors,M.text())
        local learned=api.memory.find(FULL);T.eq(IDS[6],learned.roomHashes[1])
        T.eq(nil,learned.npcId);T.eq(nil,learned.name);T.eq(nil,learned.title)
    end
end)
T.test("partial duplicate and player patrol descriptions never authorize delivery",function()
    for _,kind in ipairs({"missing","duplicate","player"}) do
        local app,api,s=start();s[kind]=1;begin(api,s);M.advance(35)
        T.eq(0,#s.attempts,kind);T.eq(0,api.engine.stats.delivered)
        M.input("/bot stop");local before=#M.sent;s[kind]=nil;s:entities();M.advance(20)
        T.eq(before,#M.sent);T.eq(0,#app.errors,M.text())
    end
end)
T.test("patrol departure during introduction requires fresh presence before a handover",function()
    local app,api,s=start({at=4});begin(api,s)
    waitFor(function() return count("przedstaw sie")>=1 end,25)
    s.at=6;s:entities();M.advance(.6);T.eq(0,#s.attempts)
    waitFor(function() return api.engine.stats.delivered==1 end,100)
    T.eq(6,s.attempts[1]);T.eq(1,#s.attempts);T.eq(0,#app.errors,M.text())
end)
T.test("verified patrol corridor still rejects foreign areas forests and locked rooms",function()
    local app,api,s=start();s:position(4)
    local route=assert(api.navigator.resolve(FULL));s:entities();T.eq(false,api.navigator.deliveryReady(route))
    s.at=4;s:entities();T.eq(true,api.navigator.deliveryReady(route))
    local hash=IDS[4]
    overrides[hash]={id=hash,area_id="another-city",terrain="miasto",indoors=false}
    T.eq(false,api.navigator.deliveryReady(route));overrides[hash]={id=hash,area_id=AREA,terrain="las",indoors=false}
    T.eq(false,api.navigator.deliveryReady(route));overrides[hash]=nil
    overrides[hash]="error";T.eq(false,api.navigator.deliveryReady(route));overrides[hash]=nil
    local locked=roomLocked;_G.roomLocked=function(map) return map==4 or locked(map) end
    T.eq(false,api.navigator.deliveryReady(route));_G.roomLocked=locked
    T.eq(0,#app.errors,M.text())
end)
T.run()
