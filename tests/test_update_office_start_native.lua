-- Campogrotta after a full /przeladuj with no saved parcel: fresh metadata,
-- not the raw Mudlet cache or a room title, must supply the native origin.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local POST="269ff0c7899bbd55"
local SQUARE="d297e64b2288c337"
local NAME="Poczta w Campogrotta"
local ACTOR="OfficeTest"
local ROOT=arg[0]:gsub("\\","/"):match("^(.*)/tests/test_update_office_start_native%.lua$") or ".."
local runtime=dofile(ROOT.."/chimera_wtyczki/chimera_paczki/updater.lua")
local function read(path) local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return s end
local function prepare()
    for _,name in ipairs(runtime.files) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read(ROOT.."/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Campogrotta")
    for index,id in ipairs({POST,SQUARE}) do
        addRoom(index);setRoomIDbyHash(index,id);setRoomArea(index,area);setRoomCoordinates(index,index,0,0)
        setRoomName(index,index==1 and NAME or "Polnocno-zachodnia czesc placu")
    end
    setExit(1,2,"sw");setExit(2,1,"ne")
    _G.getPath=function(from,to)
        if from~=to then return false end
        speedWalkDir={};speedWalkPath={};speedWalkWeight={};return true
    end
end
local function character() M.packet("Char.Info",{name=ACTOR,id="office-test"}) end
local function room(id)
    M.packet("Room.Info",{id=id or POST,name=NAME,area="Campogrotta",area_id="fe3973d382c34894",
        indoors=1,exits={["poludniowy-zachod"]=SQUARE}})
end
local function wire()
    local sendWire=send
    _G.send=function(command,...)
        local before=M.denied;raiseEvent("sysDataSendRequest",command);if M.denied~=before then return end
        sendWire(command,...)
        if command=="zerknij" then tempTimer(.01,function()
            M.line(NAME..".");M.line("Jest tutaj jedno widoczne wyjscie: poludniowy-zachod.")
        end) end
    end
end
local function api(app) return app.loader.records.kurier_paczki.api end
local function start()
    local app=T.start({"chimera.core.cli","chimera.gmcp","chimera.world","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    wire();character();room();M.packet("Char.Vitals",{hp=100,mana=100,fatigue=0})
    api(app).engine:command("reset")
    return app
end
local function restart(app)
    local env={};for key,value in pairs(app.env) do env[key]=value end
    app:shutdown();_G.chimera=nil
    for name in pairs(package.loaded) do if name:find("^chimera") then package.loaded[name]=nil end end
    local fresh=require("chimera.boot").start(env)
    _G.chimera={app=fresh,restart=function() fresh:shutdown() end};M.advance(0)
    T.eq("running",fresh.loader.records.kurier_paczki.status,M.text())
    T.eq(nil,fresh.loader.records.gmcp.api.room());T.eq(nil,fresh.loader.records.gmcp.api.char())
    T.eq(0,api(fresh).checkpoint.count());T.eq(false,api(fresh).engine.needsResumeValidation)
    return fresh
end
local function count(command)
    local n=0;for _,value in ipairs(M.sent) do if value==command then n=n+1 end end;return n
end
local function waitFor(predicate,seconds)
    for _=1,math.ceil((seconds or 10)/.05) do if predicate() then return end;M.advance(.05) end
    T.ok(predicate(),M.text())
end
local function checkRefresh(before)
    local found=false
    for index=before+1,#M.sent_gmcp do
        local s=M.sent_gmcp[index]
        found=found or s:match('^Core.Supports.Add ') and s:find("Char 2",1,true) and s:find("Room 1",1,true)
    end
    T.ok(found,"fresh office launch must request Char and Room metadata")
end
T.test("fresh Campogrotta start after full reload requests position and reads its own board once",function()
    for _,command in ipairs({"/bot paczki","/paczki start 1","/paczki wznow","/paczki poczta tutaj"}) do
        local app=restart(start());local before=#M.sent_gmcp
        M.input(command);waitFor(function() return api(app).sessionWaiting() end)
        checkRefresh(before);T.eq(0,count("przeczytaj tablice"));T.eq(nil,app.loader.records.bots.api.status())
        T.not_contains(M.text(),"Ta lokacja nie nalezy do znanych tras")
        -- Room-first must not launch with the stale raw Char.Info cache.
        room();M.advance(.2);T.eq(0,count("przeczytaj tablice"))
        character();waitFor(function() return count("przeczytaj tablice")==1 end)
        T.eq(POST,api(app).engine.source.id);T.eq(1,api(app).engine.source.map)
        T.eq("board",api(app).engine.phase);T.eq("running",api(app).engine.mode)
        if command=="/paczki start 1" then T.eq(1,api(app).engine.stopAt) end
        room();character();M.advance(.2);T.eq(1,count("przeczytaj tablice"))
        M.input("/bot stop");T.eq(0,#app.errors,M.text())
    end
end)
T.test("STOP cancels the fresh-office wait before any late metadata can restart the courier",function()
    local app=restart(start());M.input("/paczki poczta tutaj")
    waitFor(function() return api(app).sessionWaiting() end)
    M.input("/bot stop");T.eq(false,api(app).sessionWaiting())
    local sent=#M.sent;room();character();M.advance(1)
    T.eq(sent,#M.sent);T.eq(nil,app.loader.records.bots.api.status());T.eq(0,#app.errors,M.text())
end)
T.test("an unmapped fresh hash cannot be replaced with the Campogrotta room title",function()
    local app=restart(start());M.input("/paczki poczta tutaj")
    waitFor(function() return api(app).sessionWaiting() end)
    T.eq(true,app.config:set("mapper","rysowanie",false))
    character();room("aaaaaaaaaaaaaabb");M.advance(61)
    T.eq(0,count("przeczytaj tablice"));T.eq(nil,app.loader.records.bots.api.status())
    T.eq(false,api(app).sessionWaiting());M.input("/paczki diagnostyka")
    T.contains(M.text(),"aaaaaaaaaaaaaabb");T.contains(M.text(),"nie ma na mapie profilu")
    T.eq(0,#app.errors,M.text())
end)
T.test("a mismatched mapper position cannot adopt the office until current metadata agrees",function()
    local app=start();local mapper=app.loader.records.mapper.api;local current=mapper.current_room
    mapper.current_room=function() return 2 end
    M.input("/paczki poczta tutaj");waitFor(function() return api(app).sessionWaiting() end)
    T.eq(0,count("przeczytaj tablice"))
    M.input("/paczki diagnostyka");T.contains(M.text(),"Czekam na zgodna pozycje mapy i GMCP")
    mapper.current_room=current;room();character()
    waitFor(function() return count("przeczytaj tablice")==1 end)
    T.eq(POST,api(app).engine.source.id);M.input("/bot stop");T.eq(0,#app.errors,M.text())
end)
T.run()
