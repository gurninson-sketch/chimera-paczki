-- Independent native integration checks for GitHub update rollback and state.
-- Real Context/Loader/Paczki/optional Reconnect, synthetic HTTP and GMCP only.
-- Run from either pristine upstream checkout. No live character is involved.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local json=require("chimera.core.json")
local updater=dofile("../chimera-native/chimera_wtyczki/chimera_paczki/updater.lua")
local HOME="6f2c03461c2f1438"
local VERSION="1.5.14"
local NEXT="1.5.15"
local REPO="https://github.com/gurninson-sketch/chimera-paczki"
local function read(path)
    local file=assert(io.open(path,"rb"));local body=file:read("*a");file:close();return body
end
local sources={}
for _,name in ipairs(updater.files) do sources[name]=read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name) end
local network={connected=true}
local function prepare()
    for name,source in pairs(sources) do M.write_file("chimera_wtyczki/chimera_paczki/"..name,source) end
    for _,name in ipairs({"init.lua","core.lua"}) do
        M.write_file("chimera_wtyczki/chimera_reconnect/"..name,read("../chimera-reconnect/chimera_wtyczki/chimera_reconnect/"..name))
    end
    _G.getConnectionInfo=function() return "fixture.invalid",4000,network.connected end
    _G.getMudletVersion=function() return "4.20.0" end
    _G.reconnect=function() error("native update must not reconnect the game") end
    local area=M.empty_map("Updater fixture")
    addRoom(1);setRoomIDbyHash(1,HOME);setRoomName(1,"Poczta");setRoomArea(1,area);setRoomCoordinates(1,0,0,0)
end
local function ready(combat)
    M.packet("Char.Info",{id="review-character",name="Yarrim"})
    M.packet("Room.Info",{id=HOME,name="Poczta",area="Nuln",area_id="nuln",indoors=1,exits={}})
    M.packet("Char.Vitals",{hp=100,fatigue=0,mana=100})
    if combat~=false then M.packet("Chimera.Combat.State",{room=HOME,primary="",relations={}}) end
end
local function start(combat)
    network.connected=true
    local app=T.start({"chimera.core.cli","chimera.gmcp","chimera.world","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    T.eq("running",app.loader.records.kurier_paczki.status,M.text())
    T.eq("running",app.loader.records.paczki_reconnect.status,M.text())
    ready(combat)
    local api=app.loader.records.kurier_paczki.api
    T.eq(VERSION,api.version)
    T.ok(api.updater,"native updater is exposed")
    return app,api
end
local function quote(value) return "'"..value:gsub("'","'\\''").."'" end
local function sha(body)
    local path=M.write_file("review-runtime.json",body)
    local process=assert(io.popen("sha256sum "..quote(path)))
    local value=assert(process:read("*l")):match("^(%x+)")
    process:close();T.eq(64,#value);return value
end
local function release(mutate)
    local files={}
    for name,source in pairs(sources) do files[name]=source end
    files["init.lua"]=files["init.lua"]:gsub("1%.5%.14",NEXT)
    files["updater.lua"]=files["updater.lua"]:gsub("1%.5%.14",NEXT)
    if mutate then mutate(files) end
    local body=json.encode({schema=1,version=NEXT,files=files})
    return body,{schema=1,version=NEXT,bundle={url=REPO.."/releases/download/v"..NEXT.."/chimera-paczki-runtime.json",bytes=#body,sha256=sha(body)}}
end
local function download(api,mutate,automatic)
    local body,manifest=release(mutate)
    T.eq(true,api.updater.check(automatic==true))
    T.eq(updater.manifestUrl,M.http[#M.http])
    raiseEvent("sysGetHttpDone",updater.manifestUrl,json.encode(manifest))
    T.eq(manifest.bundle.url,M.http[#M.http])
    raiseEvent("sysGetHttpDone",manifest.bundle.url,body)
    M.advance(2)
end
local function expectOriginal(app)
    local record=app.loader.records.kurier_paczki
    T.ok(record,"original module record must be restored, including require-time failures")
    T.eq("running",record.status,M.text())
    T.eq(VERSION,record.api.version,M.text())
    T.eq("running",app.loader.records.paczki_reconnect.status,M.text())
    T.ok(app.loader.records.paczki_reconnect.api.controller)
    T.eq(nil,app.loader.records.bots.api.status())
    return record.api
end
T.test("native successful update reloads reconnect and preserves learned records, settings and profile files",function()
    local app,api=start()
    local previousReconnect=app.loader.records.paczki_reconnect.api
    T.eq(true,api.memory.remember({verified=true,handover=true,reward=true,recipient="Review Recipient",roomHash=HOME,map=1}))
    api.engine.config.maxKg=4.25;api.engine:save()
    M.write_file("chimera_paczki_baza.json",'{"independent-profile-file":true}')
    download(api)
    local fresh=app.loader.records.kurier_paczki
    T.eq("running",fresh.status,M.text());T.eq(NEXT,fresh.api.version,M.text())
    T.eq(NEXT,fresh.api.updater.version)
    T.eq(1,fresh.api.memory.count());T.ok(fresh.api.memory.find("Review Recipient"))
    T.eq(4.25,fresh.api.engine.config.maxKg)
    T.eq('{"independent-profile-file":true}',read(M.home.."/chimera_paczki_baza.json"))
    T.eq("running",app.loader.records.paczki_reconnect.status)
    T.ok(previousReconnect~=app.loader.records.paczki_reconnect.api,"dependent must acquire the fresh courier API")
    T.eq(nil,app.loader.records.bots.api.status());T.eq(0,#M.sent)
    T.eq(0,#app.errors,M.text())
end)
T.test("native top-level require failure restores the original module and reconnect dependency",function()
    local app,api=start()
    download(api,function(files) files["init.lua"]="error('review init runtime failure')\n" end)
    expectOriginal(app)
    T.eq(sources["init.lua"],read(M.home.."/chimera_wtyczki/chimera_paczki/init.lua"))
    T.eq(0,#M.sent)
end)
T.test("native setup failure restores the original module and reconnect dependency",function()
    local app,api=start()
    download(api,function(files)
        files["init.lua"]="return {name='kurier_paczki',version='"..NEXT.."',setup=function() error('review setup failure') end}\n"
    end)
    expectOriginal(app)
    T.eq(0,#M.sent)
end)
T.test("native other bot ownership defers update; its natural stop permits the queued update",function()
    local app,api=start()
    local bots=app.loader.records.bots.api
    bots.register("review",function(bot) bot.czekaj(100) end)
    bots.start("review")
    download(api)
    T.eq(VERSION,app.loader.records.kurier_paczki.api.version)
    T.ok(bots.status());T.eq(NEXT,api.updater.status().pending)
    bots.stop("review fixture complete")
    M.advance(16)
    T.eq(NEXT,app.loader.records.kurier_paczki.api.version,M.text())
    T.eq(nil,bots.status());T.eq(0,#M.sent)
end)
T.test("native unknown combat defers until a current room clear-combat packet arrives",function()
    local app,api=start(false)
    download(api)
    T.eq(VERSION,app.loader.records.kurier_paczki.api.version)
    T.eq(NEXT,api.updater.status().pending)
    M.packet("Chimera.Combat.State",{room=HOME,primary="",relations={}})
    M.advance(16)
    T.eq(NEXT,app.loader.records.kurier_paczki.api.version,M.text())
    T.eq(0,#M.sent)
end)
T.test("native queued stage mutation is detected before the live folder is replaced",function()
    local app,api=start(false)
    _G.PACZKI_REVIEW_UNVERIFIED=nil
    download(api,function(files)
        files["core.lua"]="_G.PACZKI_REVIEW_UNVERIFIED=true\n"..files["core.lua"]
    end)
    T.eq(nil,_G.PACZKI_REVIEW_UNVERIFIED,"syntax validation must not execute chunks")
    T.eq(NEXT,api.updater.status().pending)
    local root=M.home.."/chimera_paczki_updates"
    local stage
    for name in lfs.dir(root) do if name:match("^v1%.5%.15%-%d") then stage=root.."/"..name end end
    T.ok(stage,"queued release stage exists outside plugin discovery")
    local file=assert(io.open(stage.."/core.lua","ab"));file:write("\n-- edited after download\n");file:close()
    M.packet("Chimera.Combat.State",{room=HOME,primary="",relations={}})
    M.advance(16)
    expectOriginal(app)
    T.eq(nil,api.updater.status().pending)
    T.contains(api.updater.status().reason,"zmieniono przygotowany plik")
    T.eq(nil,_G.PACZKI_REVIEW_UNVERIFIED)
    T.eq(sources["core.lua"],read(M.home.."/chimera_wtyczki/chimera_paczki/core.lua"))
    T.eq(0,#app.errors,M.text())
end)
T.test("native automatic OFF ignores a bundle response already in flight",function()
    local app,api=start()
    local body,manifest=release()
    T.eq(true,api.updater.check(true))
    raiseEvent("sysGetHttpDone",updater.manifestUrl,json.encode(manifest))
    T.eq(manifest.bundle.url,M.http[#M.http])
    T.eq(true,api.updater.setEnabled(false))
    raiseEvent("sysGetHttpDone",manifest.bundle.url,body)
    M.advance(35)
    expectOriginal(app)
    local state=api.updater.status()
    T.eq(false,state.enabled);T.eq(false,state.busy);T.eq(nil,state.pending)
    T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("native reconnect resume ownership survives an update waiting for idle",function()
    local app,api=start()
    local controller=app.loader.records.paczki_reconnect.api.controller
    T.eq(true,controller:setEnabled(true))
    -- An active loss lease is independent of Boty and the courier's own
    -- GMCP resume wait. Keep its authentication packets pending so the
    -- optional reconnect controller owns a future resume with no running bot.
    controller:sessionLost({actor=api.engine.actor,active=true})
    T.eq("yarrim",controller:status().pendingActor)
    T.eq(nil,app.loader.records.bots.api.status())
    download(api)
    T.eq(VERSION,app.loader.records.kurier_paczki.api.version)
    T.eq(NEXT,api.updater.status().pending)
    T.eq(controller,app.loader.records.paczki_reconnect.api.controller)
    T.eq("yarrim",controller:status().pendingActor,"update must not discard the reconnect resume lease")
    controller:manual("fixture explicitly releases the pending course")
    M.advance(16)
    T.eq(NEXT,app.loader.records.kurier_paczki.api.version,M.text())
    T.eq(0,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.run()
