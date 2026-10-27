-- Actual Chimera loader, command bus, filesystem and shared-memory controller.
-- Network replies and game packets are synthetic; no live character is used.
package.path="tests/?.lua;"..package.path
local T=require("support.harness")
local M=T.M
local json=require("chimera.core.json")
local updater=dofile("../chimera-native/chimera_wtyczki/chimera_paczki/updater.lua")
local HOME="6f2c03461c2f1438"
local SHARED="https://raw.githubusercontent.com/gurninson-sketch/chimera-paczki/main/data/addresses.json"
local paths={}
local function read(path)
    local file=assert(io.open(path,"rb"));local body=file:read("*a");file:close();return body
end
local function prepare()
    paths={}
    _G.downloadFile=function(path,url) paths[url]=path;M.http[#M.http+1]=url;return true,url end
    _G.getMudletVersion=function() return "4.20.0" end
    for _,name in ipairs(updater.files) do
        M.write_file("chimera_wtyczki/chimera_paczki/"..name,read("../chimera-native/chimera_wtyczki/chimera_paczki/"..name))
    end
    local area=M.empty_map("Shared address fixture")
    addRoom(1);setRoomIDbyHash(1,HOME);setRoomName(1,"Poczta");setRoomArea(1,area);setRoomCoordinates(1,0,0,0)
end
local function start()
    local app=T.start({"chimera.core.cli","chimera.gmcp","chimera.world","chimera.mapper","chimera.terrain",
        "chimera.locations","chimera.walker","chimera.npcs","chimera.hints","chimera.bags","chimera.events",
        "chimera.numpad","chimera.bots"},nil,prepare)
    local record=app.loader.records.kurier_paczki
    T.eq("running",record.status,M.text());T.ok(record.api.sharedBase)
    M.packet("Char.Info",{id="base-test",name="Yarrim"})
    M.packet("Room.Info",{id=HOME,name="Poczta",area="Nuln",area_id="nuln",indoors=1,exits={}})
    M.packet("Char.Vitals",{hp=100,fatigue=0,mana=100})
    M.packet("Chimera.Combat.State",{room=HOME,primary="",relations={}})
    return app,record.api,app.loader.records.bots.api
end
local function package()
    return {format="chimera_paczki_baza",version=1,memory={schema=1,records={
        ["bruno rottel"]={recipient="Bruno Rottel",roomHashes={"315106e45b840273"},count=1,last=100,postal=false},
    }}}
end
local function complete(data)
    local body=type(data)=="string" and data or json.encode(data or package())
    local path=assert(paths[SHARED],"manual shared-base command did not begin a download")
    local file=assert(io.open(path,"wb"));assert(file:write(body));assert(file:close())
    raiseEvent("sysDownloadDone",path,#body,{url="https://raw.githubusercontent.com/redirected/data/addresses.json"})
    return path
end
local function seed(api)
    T.eq(true,api.memory.remember({verified=true,handover=true,reward=true,recipient="Local Recipient",roomHash=HOME,map=1}))
end

T.test("manual shared-base command merges actual memory and writes a recoverable allowlisted backup",function()
    local app,api=start();seed(api)
    local before=#M.sent
    M.input("/paczki baza aktualizuj");T.eq(SHARED,M.http[#M.http])
    local download=complete()
    T.eq(2,api.memory.count());T.ok(api.memory.find("Bruno Rottel"));T.ok(api.memory.find("Local Recipient"))
    T.eq(HOME,api.memory.find("Local Recipient").roomHashes[1])
    local status=api.sharedBase.status();T.eq(false,status.busy);T.eq(false,status.pending);T.ok(status.backup)
    local backup=json.decode(read(status.backup));T.eq("chimera_paczki_baza",backup.format)
    T.ok(backup.memory.records["local recipient"]);T.eq(nil,backup.memory.records["bruno rottel"])
    T.eq(nil,backup.actor);T.eq(nil,backup.job)
    T.eq(nil,lfs.attributes(download,"mode"));T.eq(before,#M.sent)
    M.input("/paczki baza status");T.contains(M.text(),"adresatow 2")
    T.eq(0,#app.errors,M.text())
end)
T.test("another bot can keep running while shared download waits and its stop permits merge",function()
    local app,api,bots=start();seed(api)
    bots.register("shared_review",function(bot) bot.czekaj(100) end)
    bots.start("shared_review");T.ok(bots.status())
    local before=#M.sent
    M.input("/paczki baza aktualizuj");complete()
    T.eq(true,api.sharedBase.status().pending);T.eq(1,api.memory.count());T.eq(nil,api.sharedBase.status().backup)
    T.ok(bots.status());T.eq(before,#M.sent)
    bots.stop("shared-base fixture complete");M.advance(16)
    T.eq(2,api.memory.count());T.eq(false,api.sharedBase.status().pending);T.eq(nil,bots.status())
    T.eq(before,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.test("uncertain courier handover defers the merge even when no bot owns the manager",function()
    local app,api,bots=start();seed(api)
    api.engine.awaitingDelivery=true
    M.input("/paczki baza aktualizuj");complete()
    T.eq(1,api.memory.count());T.eq(true,api.sharedBase.status().pending);T.eq(nil,bots.status())
    api.engine.awaitingDelivery=nil;M.advance(16)
    T.eq(2,api.memory.count());T.eq(false,api.sharedBase.status().pending);T.eq(0,#app.errors,M.text())
end)
T.test("shared sync command toggle persists and malformed response never changes memory",function()
    local app,api=start();seed(api)
    M.input("/paczki baza synchronizacja off");T.eq(false,api.sharedBase.status().enabled)
    M.input("/paczki baza aktualizuj");complete("not json")
    T.eq(1,api.memory.count());T.ok(api.sharedBase.status().reason);T.eq(nil,api.sharedBase.status().backup)
    M.input("/paczki baza aktualizuj");complete()
    T.eq(2,api.memory.count());M.input("/paczki baza synchronizacja on");T.eq(true,api.sharedBase.status().enabled)
    T.eq(0,#app.errors,M.text())
end)
T.test("the published sixty-three recipient catalogue imports intact and retains a profile's extra discovery",function()
    local app,api=start();seed(api)
    local catalogue=json.decode(read("../chimera-native/data/addresses.json"))
    local recipients,locations=0,0
    for _,record in pairs(catalogue.memory.records) do recipients=recipients+1;locations=locations+#record.roomHashes end
    T.eq(63,recipients);T.eq(69,locations)
    local before=#M.sent
    M.input("/paczki baza aktualizuj");complete(catalogue)
    T.eq(64,api.memory.count());T.ok(api.memory.find("Local Recipient"))
    for _,record in pairs(catalogue.memory.records) do
        local imported=api.memory.find(record.recipient)
        T.ok(imported,record.recipient);T.eq(#record.roomHashes,#imported.roomHashes)
        for index,hash in ipairs(record.roomHashes) do T.eq(hash,imported.roomHashes[index]) end
        T.eq(record.postal,imported.postal);T.eq(record.count,imported.count)
    end
    M.input("/paczki baza aktualizuj");complete(catalogue)
    T.eq(64,api.memory.count());T.eq(0,api.sharedBase.status().summary.added)
    T.eq(before,#M.sent);T.eq(0,#app.errors,M.text())
end)
T.run()
