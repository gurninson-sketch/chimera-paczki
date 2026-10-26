-- Runtime enrichment of verified room-only courier memories.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_identity_upgrade%.lua$") or "."
package.path=root.."/chimera_wtyczki/?.lua;"..package.path
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/npc.lua")
local cases,assertions=0,0
local FULL="Torquato di Assemani"
local function eq(expected,actual,label)
    assertions=assertions+1
    assert(expected==actual,(label or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function ok(value,label) eq(true,not not value,label) end
local function test(name,body)
    local good,why=pcall(body)
    if not good then error(name..": "..tostring(why),0) end
    cases=cases+1;print("PASS "..name)
end
local function npc(id,title,name,short)
    return {id=id or "torquato",name=name or "Torquato",short=short or "wyniosly bialowlosy mezczyzna",
        title=title or FULL..", mezczyzna",rooms={street=true}}
end
local function memory(extra)
    local value={recipient=FULL,roomHashes={"forge"},count=3,last=10,postal=false}
    for k,v in pairs(extra or {}) do value[k]=v end
    return value
end
local function fixture(records,record,cityEnabled)
    local x={records=records or {},record=record or memory(),map=1,room={id="office",name="Poczta"},
        snapshot={room="office",entities={}},events={},timers={},clock=0,serial=0,probes={},done=0}
    local hashes={[1]="office",[2]="forge",[3]="street"}
    local maps={office=1,forge=2,street=3}
    _G.getRoomIDbyHash=function(hash) return maps[hash] or -1 end
    local ctx={}
    function ctx:on(name,fn) x.events[name]=x.events[name] or {};x.events[name][#x.events[name]+1]=fn end
    function ctx:emit(name,data) for _,fn in ipairs(x.events[name] or {}) do fn(data) end end
    function ctx:timer(seconds,fn) x.serial=x.serial+1;x.timers[x.serial]={at=x.clock+seconds,fn=fn};return x.serial end
    function ctx:cancel(handle) x.timers[handle]=nil end
    function ctx:cleanup(fn) x.cleanup=fn end
    function ctx:send(command) x.probes[#x.probes+1]=command;if x.onProbe then x.onProbe(command) end end
    local mapper={current_room=function() return x.map end,chimera_id=function(map) return hashes[map] end}
    local city={scope=function(route)
        if route.roomIds and #route.rooms>0 then return {areaId="campogrotta",name="Campogrotta",anchorMap=route.rooms[1]} end
        return nil,"brak mapy miasta"
    end,contains=function(_,map) return hashes[map]~=nil end,rooms=function() return {1,2,3} end,
    plan=function(_,from,to)
        if from==to then return {from=from,fromId=hashes[from],target=to,targetId=hashes[to],cost=0,steps={}} end
        return {from=from,fromId=hashes[from],target=to,targetId=hashes[to],cost=1,
            steps={{cmd="n",map=to,id=hashes[to],weight=1}}}
    end}
    local options={city=cityEnabled~=false and city or nil,runLocal=function() error("unexpected movement in identity fixture") end,
        memory={find=function() return x.record end},delay=function() return 0.5 end}
    local gmcp={room=function() return x.room end,entities=function() return x.snapshot end,refresh_entities=function() end}
    local catalogue={all=function() return x.records end,find=function(wanted)
        local out={}
        for _,row in ipairs(x.records) do if row.id==wanted or row.name:lower()==wanted:lower() then out[#out+1]=row end end
        return out
    end}
    local walker={cost=function(from,to) return math.abs(from-to)+1 end}
    x.api=create(ctx,{},gmcp,walker,mapper,catalogue,{},function(command) return ctx:send(command) end,
        function() error("unexpected legacy movement") end,options)
    function x:place(map)
        self.map=map;self.room={id=hashes[map],name=map==2 and "Kuznia" or "Ulica"}
        ctx:emit("chimera.room.changed",self.room)
    end
    function x:entities(name,kind,title)
        self.snapshot={room=self.room.id,entities=name and {{id="e-target",kind=kind or "npc",name=name,title=title}} or {}}
        ctx:emit("chimera.room.entities",self.snapshot)
    end
    function x:advance(seconds)
        local ending=self.clock+seconds
        while true do
            local chosen,at
            for id,row in pairs(self.timers) do if row.at<=ending and (not at or row.at<at) then chosen,at=id,row.at end end
            if not chosen then break end
            self.clock=at;local row=self.timers[chosen];self.timers[chosen]=nil;row.fn()
        end
        self.clock=ending
    end
    return x
end

test("a room-only memory is enriched from a unique exact full catalogue title without rewriting memory",function()
    local record=memory();local x=fixture({npc()},record)
    local route=assert(x.api.resolve(FULL))
    eq("torquato",route.npcId);eq("Torquato",route.npcName);eq(true,route.identityUpgraded)
    eq(true,route.roomOnlyIdentity);eq(nil,route.locationVerified);eq(2,#route.rooms)
    eq("city",x.api.searchStatus(route).mode);eq(true,x.api.searchStatus(route).identity)
    eq(nil,record.npcId);eq(nil,record.name);eq(1,#record.roomHashes);eq("forge",record.roomHashes[1]);eq(3,record.count)
end)
test("a full catalogue name can independently enrich a room-only memory",function()
    local x=fixture({npc("full",FULL,FULL)})
    local route=assert(x.api.resolve(FULL));eq("full",route.npcId);eq(true,route.identityUpgraded)
end)
test("a first name and empty or shortened title never enrich the full recipient",function()
    for _,title in ipairs({"","Torquato","Torquato, mezczyzna"}) do
        local x=fixture({npc("short",title)})
        local route=assert(x.api.resolve(FULL));eq(nil,route.npcId);eq(nil,route.identityUpgraded)
        eq("city",x.api.searchStatus(route).mode);eq(false,x.api.searchStatus(route).identity)
    end
end)
test("a longer surname prefix cannot enrich or authorize the room-only target",function()
    local x=fixture({npc("wrong",FULL.." Mlodszy, mezczyzna")})
    local route=assert(x.api.resolve(FULL));eq(nil,route.npcId)
    x:place(2);x:entities("Torquato","npc",FULL.." Mlodszy, mezczyzna")
    eq(false,x.api.deliveryReady(route))
end)
test("two exact full identities remain ambiguous without rebinding the remembered recipient",function()
    local x=fixture({npc("one"),npc("two",nil,nil,"inny bialowlosy mezczyzna")})
    local route=assert(x.api.resolve(FULL));eq(nil,route.npcId);eq(false,x.api.searchStatus(route).identity)
    ok(x.api.searchStatus(route).reason)
end)
test("every nonempty partial stored identity blocks automatic rebinding",function()
    for _,field in ipairs({"npcId","npcName","name","npcShort","short","npcTitle","title"}) do
        local x=fixture({npc()},memory({[field]="untrusted partial"}))
        local route=assert(x.api.resolve(FULL))
        eq(nil,route.npcId,field);eq(nil,route.roomOnlyIdentity,field);eq("known",x.api.searchStatus(route).mode,field)
    end
end)
test("a contradictory stored identity is not replaced by a different correct-looking catalogue record",function()
    local x=fixture({npc("wrong","Torquato Nowak, mezczyzna"),npc("right")},
        memory({npcId="wrong",name="Torquato",short="wyniosly bialowlosy mezczyzna",title="Torquato Nowak, mezczyzna"}))
    local route=assert(x.api.resolve(FULL));eq("wrong",route.npcId);eq(true,route.identityConflict)
    eq("known",x.api.searchStatus(route).mode);eq(false,x.api.searchStatus(route).identity)
end)
test("an unmatched complete foreign identity cannot unlock a city patrol for a different full recipient",function()
    local x=fixture({npc("right")},memory({npcId="foreign",name="Boreg",short="szeroki brodaty krasnolud",title="Boreg, kowal"}))
    local route=assert(x.api.resolve(FULL));eq("foreign",route.npcId);eq("Boreg",route.npcName)
    local status=x.api.searchStatus(route)
    eq("known",status.mode);eq(false,status.identity);eq(false,x.api.canSearchFor(route))
    ok(status.reason:find("nie potwierdza",1,true));eq(nil,route.identityUpgraded);eq(false,x.api.deliveryReady(route))
end)
test("an explicit foreign surname in an unmatched stored title defeats a matching first name",function()
    local x=fixture({npc("right")},memory({npcId="foreign",name="Torquato",short="wyniosly bialowlosy mezczyzna",
        title="Torquato Nowak, mezczyzna"}))
    local route=assert(x.api.resolve(FULL));eq("foreign",route.npcId);eq("Torquato",route.npcName)
    x:place(2);x:entities("Torquato")
    local status=x.api.searchStatus(route)
    eq("known",status.mode);eq(false,status.identity);eq(false,x.api.canSearchFor(route))
    ok(status.reason:find("nie potwierdza",1,true));eq(nil,route.identityUpgraded);eq(false,x.api.deliveryReady(route))
end)
test("a historical nickname remains eligible when its exact full title proves the recipient",function()
    local alias=npc("alias",FULL..", mezczyzna","Il Conte")
    local x=fixture({alias},memory({npcId="alias",name="Il Conte",short=alias.short,title=alias.title}))
    local route=assert(x.api.resolve(FULL));eq("alias",route.npcId);eq("Il Conte",route.npcName)
    eq("city",x.api.searchStatus(route).mode);eq(true,x.api.searchStatus(route).identity)
end)
test("an empty learned room history is not rescued by automatic identity enrichment",function()
    local x=fixture({npc()},memory({roomHashes={}}))
    eq(nil,x.api.resolve(FULL));eq(nil,x.record.npcId)
end)
test("a verified room-only recipient can patrol a city on a new profile with an empty catalogue",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL))
    eq(nil,route.npcId);eq(true,route.roomOnlyIdentity);eq("city",x.api.searchStatus(route).mode)
    eq(false,x.api.searchStatus(route).identity);eq(true,x.api.canSearchFor(route))
    x:place(2);x:entities("Torquato");eq(false,x.api.deliveryReady(route))
    x:entities("wyniosly bialowlosy mezczyzna");eq(false,x.api.deliveryReady(route))
end)
test("only an exact full NPC entity can authorize a room-only gift before catalogue enrichment",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL));x:place(2)
    x:entities(FULL,"player");eq(false,x.api.deliveryReady(route))
    x:entities(FULL,"npc");eq(true,x.api.deliveryReady(route));eq(nil,route.npcId)
    x:entities("Torquato","npc",FULL..", mezczyzna");eq(true,x.api.deliveryReady(route))
end)
test("a contradictory live full title defeats a known first name and a room-only full entity name",function()
    local x=fixture({npc()});local route=assert(x.api.resolve(FULL));x:place(2)
    for _,title in ipairs({"Torquato Nowak, mezczyzna",FULL.." Senior, mezczyzna"}) do
        x:entities("Torquato","npc",title);eq(false,x.api.deliveryReady(route))
    end
    x:entities("Torquato","npc",FULL..", mezczyzna");eq(true,x.api.deliveryReady(route))
    x:entities("Torquato","npc","Torquato, mezczyzna");eq(true,x.api.deliveryReady(route))
    x:entities("Torquato");eq(true,x.api.deliveryReady(route))
    x.snapshot.entities[#x.snapshot.entities+1]={name="Boreg",kind="npc",title="Boreg Nowak, kowal"}
    eq(true,x.api.deliveryReady(route),"another NPC's unrelated title must not disqualify the target")
    local unknown=fixture({});local roomOnly=assert(unknown.api.resolve(FULL));unknown:place(2)
    unknown:entities(FULL,"npc","Torquato Nowak, mezczyzna");eq(false,unknown.api.deliveryReady(roomOnly))
    unknown:entities(FULL,"npc","Torquato, mezczyzna");eq(false,unknown.api.deliveryReady(roomOnly))
    unknown:entities(FULL,"npc",FULL..", mezczyzna");eq(true,unknown.api.deliveryReady(roomOnly))
end)
test("catalogue identity learned after planning upgrades the existing route without a restart",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL));eq(nil,route.npcId)
    x.records[1]=npc()
    eq(true,x.api.canSearchFor(route))
    local status=x.api.searchStatus(route)
    eq("torquato",route.npcId);eq(true,status.upgraded);eq(true,status.identity);eq("city",status.mode)
    eq(2,#route.rooms);eq(nil,x.record.npcId)
end)
test("passive diagnostics report a newly available identity without modifying the active route",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL))
    local rooms,ids,scope=route.rooms,route.roomIds,route.cityScope
    local scopeArea=scope and scope.areaId
    local initialLocationVerified=route.locationVerified
    local initialSearchSeconds=route.searchSeconds
    local initialUpgradeReason=route.identityUpgradeReason
    x.records[1]=npc()
    local status=x.api.searchStatus(route)
    eq(true,status.identity);eq(true,status.upgraded);eq("torquato",status.npcId);eq(2,status.knownRooms)
    eq(nil,route.npcId);eq(nil,route.npcName);eq(initialLocationVerified,route.locationVerified)
    eq(rooms,route.rooms);eq(ids,route.roomIds);eq(scope,route.cityScope);eq(scopeArea,scope and scope.areaId)
    eq(1,#route.rooms);eq(nil,route.roomIds[3]);eq(initialSearchSeconds,route.searchSeconds)
    eq(initialUpgradeReason,route.identityUpgradeReason);eq(nil,route.identityUpgraded)
    eq(true,x.api.canSearchFor(route));eq("torquato",route.npcId);eq(2,#route.rooms);eq("street",route.roomIds[3])
end)
test("a recipient-absent freshness barrier survives dynamic identity enrichment",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL));x:place(2);x:entities(FULL)
    eq(true,x.api.deliveryReady(route));eq(true,x.api.recipientAbsent(route));eq(false,x.api.deliveryReady(route))
    x.records[1]=npc();eq(true,x.api.searchStatus(route).identity)
    eq(false,x.api.deliveryReady(route),"identity upgrade must not erase the old-packet barrier")
    x:entities("Torquato");eq(true,x.api.deliveryReady(route))
end)
test("a room-only patrol introduces an NPC once and requires the fresh full identification result",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL));x:place(2);x:entities("wyniosly bialowlosy mezczyzna")
    local completed=0
    local cancel=x.api.navigate(route,function(good) if good then completed=completed+1 end end)
    x:advance(1.5);eq(1,#x.probes);eq("przedstaw sie",x.probes[1]);eq(0,completed)
    x.records[1]=npc();x:entities("Torquato")
    eq(1,completed);eq("torquato",route.npcId);eq(1,#x.probes)
    x:advance(10);eq(1,completed);cancel();eq(1,completed)
end)
test("a fresh first name alone does not complete a room-only introduction probe",function()
    local x=fixture({});local route=assert(x.api.resolve(FULL));x:place(2);x:entities("Torquato")
    local completed=0
    local cancel=x.api.navigate(route,function(good) if good then completed=completed+1 end end)
    x:advance(1.5);eq(1,#x.probes);eq(0,completed)
    x:entities("Torquato");eq(0,completed);eq(false,x.api.deliveryReady(route));cancel()
end)
test("postal offices and the periodic captain never become a city patrol through enrichment",function()
    local x=fixture({npc()})
    for _,route in ipairs({{native=true,postal=true,name=FULL,roomOnlyIdentity=true,rooms={2},roomIds={[2]="forge"}},
        {native=true,name="Annibale Malacresta Lettore",roomOnlyIdentity=true,rooms={2},roomIds={[2]="forge"}}}) do
        eq("known",x.api.searchStatus(route).mode);eq(false,x.api.canSearchFor(route));eq(nil,route.npcId)
    end
end)
test("a passive search diagnostic never sends a command or rewrites memory",function()
    local x=fixture({npc()});local route=assert(x.api.resolve(FULL))
    for _=1,5 do local status=x.api.searchStatus(route);eq("Campogrotta",status.name);eq("campogrotta",status.area) end
    eq(0,#x.probes);eq(nil,x.record.npcId);eq(3,x.record.count)
end)
local BOREG="Boreg Khrazaksson"
local function boreg(title,id,name)
    return npc(id or "boreg",title or BOREG.." z Karak Izor, krasnolud",name or "Boreg","szeroki brodaty krasnolud")
end
local function boreg_memory(extra)
    local value=memory({recipient=BOREG})
    for key,item in pairs(extra or {}) do value[key]=item end
    return value
end
test("Boreg's stored full identity with an origin remains a city target and accepts a fresh named NPC",function()
    local row=boreg();local x=fixture({row},boreg_memory({npcId=row.id,name=row.name,short=row.short,title=row.title}))
    local route=assert(x.api.resolve(BOREG));eq("boreg",route.npcId)
    local status=x.api.searchStatus(route)
    eq("city",status.mode);eq(true,status.identity);eq(nil,route.cityIdentityConflict)
    x:place(2);eq(false,x.api.deliveryReady(route),"old room entities cannot authorize the delivery")
    x:entities("Boreg","npc",row.title);eq(true,x.api.deliveryReady(route))
end)
test("a room-only Boreg delivery is enriched by the full board addressee followed by a place of origin",function()
    for _,title in ipairs({BOREG.." z Karak Izor.","BOREG KHRAZAKSSON ZE STAREGO MIASTA, kowal"}) do
        local row=boreg(title);local record=boreg_memory();local x=fixture({row},record)
        local route=assert(x.api.resolve(BOREG))
        eq("boreg",route.npcId);eq(true,route.identityUpgraded);eq("city",x.api.searchStatus(route).mode)
        eq(nil,record.npcId);eq(3,record.count)
        x:place(2);x:entities("Boreg","npc",title);eq(true,x.api.deliveryReady(route))
    end
end)
test("a fresh full title with a locative suffix can identify a room-only address without guessing a first name",function()
    local x=fixture({},boreg_memory());local route=assert(x.api.resolve(BOREG));x:place(2)
    x:entities("Boreg");eq(false,x.api.deliveryReady(route))
    x:entities("Boreg","npc",BOREG.." z Karak Izor.");eq(true,x.api.deliveryReady(route));eq(nil,route.npcId)
    x:entities("Boreg","player",BOREG.." z Karak Izor.");eq(false,x.api.deliveryReady(route))
end)
test("an existing room-only route upgrades when an introduction later learns Boreg's title with an origin",function()
    local x=fixture({},boreg_memory());local route=assert(x.api.resolve(BOREG));eq(nil,route.npcId)
    x.records[1]=boreg();x:place(2);x:entities("Boreg","npc",x.records[1].title)
    eq(true,x.api.deliveryReady(route));eq("boreg",route.npcId);eq(true,route.identityUpgraded)
    eq(nil,x.record.npcId)
end)
test("a new catalogue route recognizes the board addressee before an origin without a learned delivery",function()
    local row=boreg();local x=fixture({row});x.record=nil
    local route=assert(x.api.resolve(BOREG));eq("boreg",route.npcId);eq(false,route.learned)
    x:place(2);x:entities("Boreg","npc",row.title);eq(true,x.api.deliveryReady(route))
end)
test("an arbitrary longer surname or malformed origin cannot enrich or authorize Boreg",function()
    for _,title in ipairs({BOREG.." Senior",BOREG.." Nowak",BOREG.."ski z Karak Izor",
        BOREG.." z",BOREG.." ze",BOREG.." z 123",BOREG.." z Karak;Izor","Pan "..BOREG.." z Karak Izor"}) do
        local x=fixture({boreg(title)},boreg_memory());local route=assert(x.api.resolve(BOREG))
        eq(nil,route.npcId,title);eq(nil,route.identityUpgraded,title)
        x:place(2);x:entities("Boreg","npc",title);eq(false,x.api.deliveryReady(route),title)
        x.record=nil;local fresh=x.api.resolve(BOREG)
        if fresh then eq(false,x.api.deliveryReady(fresh),"new catalogue: "..title) end
    end
end)
test("a fresh contradictory title still blocks a stored Boreg identity even when it adds a later origin",function()
    local row=boreg();local x=fixture({row},boreg_memory({npcId=row.id,name=row.name,short=row.short,title=row.title}))
    local route=assert(x.api.resolve(BOREG));x:place(2)
    for _,title in ipairs({BOREG.." Senior z Karak Izor",BOREG.." Nowak ze Starego Miasta","Boreg Nowak z Karak Izor"}) do
        x:entities("Boreg","npc",title);eq(false,x.api.deliveryReady(route),title)
    end
    x:entities("Boreg","npc",BOREG.." ze Starego Miasta");eq(true,x.api.deliveryReady(route))
end)
test("two different catalogue identities with the same board name and different origins remain ambiguous",function()
    local x=fixture({boreg(BOREG.." z Karak Izor","one"),boreg(BOREG.." ze Starego Miasta","two")},boreg_memory())
    local route=assert(x.api.resolve(BOREG));eq(nil,route.npcId);eq(nil,route.identityUpgraded)
    eq(false,x.api.searchStatus(route).identity)
    ok(route.identityUpgradeReason:find("kilku NPC",1,true))
    x.record=nil;local resolved,why=x.api.resolve(BOREG)
    eq(nil,resolved);ok(why:find("kilku NPC",1,true))
end)
test("an addressee containing its own origin is matched whole and is never shortened to the first name",function()
    local full="Bhorin z Karak-Varn"
    local row=npc("bhorin",full..", krasnolud","Bhorin","brodaty krasnolud")
    local x=fixture({row},memory({recipient=full}));local route=assert(x.api.resolve(full))
    eq("bhorin",route.npcId);eq(true,route.identityUpgraded)
    x:place(2);x:entities("Bhorin","npc",row.title);eq(true,x.api.deliveryReady(route))
    x:entities("Bhorin","npc","Bhorin z Karak Izor");eq(false,x.api.deliveryReady(route))
end)
test("a one-word addressee accepts an origin but never an arbitrary additional name",function()
    for _,title in ipairs({"Mario Nowak","Mario Senior","Marioo z Miragliano"}) do
        local x=fixture({npc("mario",title,"Mario")},memory({recipient="Mario"}))
        local route=assert(x.api.resolve("Mario"));eq(nil,route.npcId)
        x:place(2);x:entities("Mario","npc",title);eq(false,x.api.deliveryReady(route))
    end
    local row=npc("mario","Mario z Miragliano","Mario")
    local x=fixture({row},memory({recipient="Mario"}));local route=assert(x.api.resolve("Mario"))
    eq("mario",route.npcId);x:place(2);x:entities("Mario","npc",row.title);eq(true,x.api.deliveryReady(route))
end)
test("existing noncity catalogue and learned identity matching preserves a leading profession in the title",function()
    local full="Hans Bernauer"
    local row=npc("hans","Kupiec korzenny Hans Bernauer z Nuln","Hans","przysadzisty brodaty mezczyzna")
    local x=fixture({row},memory({recipient=full}),false);x.record=nil
    local route=assert(x.api.resolve(full));eq("hans",route.npcId);eq(false,route.learned)
    x.record=memory({recipient=full,npcId=row.id,name=row.name,short=row.short,title=row.title})
    local learned=assert(x.api.resolve(full));eq("hans",learned.npcId);eq(nil,learned.identityConflict)
    x:place(2);x:entities("kupiec","npc",row.title)
    eq(true,x.api.deliveryReady(learned))
    local evidence=x.api.deliveryEvidence(learned)
    ok(evidence and evidence.npc);eq("hans",evidence.npc.npcId)
end)

local MICHAEL="Michael Tommasino"
local function michael(title,id)
    return npc(id or "michael",title or "Don Michael Tommasino, Burmistrz Campogrotty, czlowiek","Michael","elegancki starszy mezczyzna")
end
test("Michael's confirmed Don honorific is compatible with a stored shorter postal addressee",function()
    local row=michael();local x=fixture({row},memory({recipient=MICHAEL,npcId=row.id,name=row.name,short=row.short,title=row.title}))
    local route=assert(x.api.resolve(MICHAEL));eq("city",x.api.searchStatus(route).mode);eq(true,x.api.searchStatus(route).identity)
    x:place(2);x:entities("Michael","npc",row.title);eq(true,x.api.deliveryReady(route));eq(nil,route.cityIdentityConflict)
end)
test("a room-only Michael history can learn the unique Don introduction without changing the address",function()
    local row=michael();local x=fixture({row},memory({recipient=MICHAEL}));local route=assert(x.api.resolve(MICHAEL))
    eq("michael",route.npcId);eq(true,route.identityUpgraded);eq(MICHAEL,route.name);eq(nil,x.record.npcId)
    x:place(2);x:entities("Michael","npc",row.title);eq(true,x.api.deliveryReady(route))
    local unknown=fixture({},memory({recipient=MICHAEL}));local unresolved=assert(unknown.api.resolve(MICHAEL));unknown:place(2)
    unknown:entities("Michael");eq(false,unknown.api.deliveryReady(unresolved))
    unknown:entities("Michael","npc",row.title);eq(true,unknown.api.deliveryReady(unresolved));eq(nil,unresolved.npcId)
end)
test("Don never permits a foreign surname Senior prefix arbitrary honorific or a guessed first name",function()
    for _,title in ipairs({"Don Michael Nowak","Don Michael Tommasino Senior","Don Michael Tommasinoski",
        "Pan Michael Tommasino","Don Don Michael Tommasino","Don Michael","Don Michael Tommasino z"}) do
        local x=fixture({michael(title)},memory({recipient=MICHAEL}));local route=assert(x.api.resolve(MICHAEL))
        eq(nil,route.identityUpgraded,title);eq(nil,route.npcId,title)
        x:place(2);x:entities("Michael","npc",title);eq(false,x.api.deliveryReady(route),title)
    end
    local row=michael();local x=fixture({row},memory({recipient=MICHAEL,npcId=row.id,name=row.name,short=row.short,title=row.title}))
    local route=assert(x.api.resolve(MICHAEL));x:place(2);x:entities("Michael","npc","Don Michael Nowak")
    eq(false,x.api.deliveryReady(route),"a conflicting current title cannot use the stored Don identity")
end)
test("two current Don identities with the same postal name remain ambiguous",function()
    local x=fixture({michael(nil,"one"),michael("Don Michael Tommasino z Miragliano","two")},memory({recipient=MICHAEL}))
    local route=assert(x.api.resolve(MICHAEL));eq(nil,route.identityUpgraded);eq(nil,route.npcId)
    x:place(2);x:entities("Michael");eq(false,x.api.deliveryReady(route))
end)

local FRYDERIK="Fryderik Miecznik"
local function fryderik(title,id)
    return npc(id or "fryderik",title or "Fryderik z Nuln","Fryderik","wysoki mocny mezczyzna")
end
test("the confirmed occupation alias keeps Fryderik's stored successful identity valid",function()
    local row=fryderik();local record=memory({recipient=FRYDERIK,npcId=row.id,name=row.name,short=row.short,title=row.title})
    local x=fixture({row},record);local route=assert(x.api.resolve(FRYDERIK))
    eq("fryderik",route.npcId);eq(nil,route.identityConflict);eq("city",x.api.searchStatus(route).mode)
    x:place(2);x:entities("Fryderik","npc",row.title);eq(true,x.api.deliveryReady(route))
    local proof=x.api.deliveryEvidence(route);ok(proof and proof.npc);eq("fryderik",proof.npc.npcId)
    eq(FRYDERIK,record.recipient);eq(row.title,record.title)
end)
test("the exact alias enriches room-only history with whitespace and comma role normalization",function()
    for _,title in ipairs({"Fryderik  z Nuln.","FRYDERIK Z NULN, miecznik, czlowiek"}) do
        local x=fixture({fryderik(title)},memory({recipient=FRYDERIK}));local route=assert(x.api.resolve(FRYDERIK))
        eq("fryderik",route.npcId);eq(true,route.identityUpgraded);eq(nil,x.record.npcId)
        x:place(2);x:entities("Fryderik","npc",title);eq(true,x.api.deliveryReady(route))
    end
end)
test("a new catalogue route recognizes the occupation alias without courier history",function()
    local x=fixture({fryderik()});x.record=nil
    local route=assert(x.api.resolve(FRYDERIK));eq("fryderik",route.npcId);eq(false,route.learned)
    x:place(2);x:entities("Fryderik","npc","Fryderik z Nuln");eq(true,x.api.deliveryReady(route))
end)
test("a room-only route binds the complete observed occupation alias after an introduction",function()
    local x=fixture({},memory({recipient=FRYDERIK}));local route=assert(x.api.resolve(FRYDERIK));x:place(2)
    x:entities("Fryderik");eq(false,x.api.deliveryReady(route));eq(nil,route.npcId)
    x.records[1]=fryderik();x:entities("Fryderik","npc","Fryderik  z Nuln.")
    eq(true,x.api.deliveryReady(route));eq("fryderik",route.npcId);eq(true,route.identityUpgraded)
end)
test("occupation aliases reject another origin surname Senior and an incomplete first name",function()
    for _,title in ipairs({"Fryderik z Altdorfu","Fryderik Nowak z Nuln","Fryderik z Nuln Senior",
        "Fryderik z Nulnski","Fryderik","Fryderik z","Pan Fryderik z Nuln"}) do
        local x=fixture({fryderik(title)},memory({recipient=FRYDERIK}));local route=assert(x.api.resolve(FRYDERIK))
        eq(nil,route.identityUpgraded,title);eq(nil,route.npcId,title)
        x:place(2);x:entities("Fryderik","npc",title);eq(false,x.api.deliveryReady(route),title)
    end
end)
test("a live foreign title cannot use a stored legitimate occupation alias",function()
    local row=fryderik();local x=fixture({row},memory({recipient=FRYDERIK,npcId=row.id,name=row.name,short=row.short,title=row.title}))
    local route=assert(x.api.resolve(FRYDERIK));x:place(2)
    x:entities("Fryderik","npc","Fryderik z Altdorfu");eq(false,x.api.deliveryReady(route))
    x:entities("Fryderik","npc","Fryderik z Nuln");eq(true,x.api.deliveryReady(route))
end)
test("two catalogue identities sharing the complete occupation alias remain ambiguous",function()
    local x=fixture({fryderik(nil,"one"),fryderik("Fryderik z Nuln, miecznik","two")},memory({recipient=FRYDERIK}))
    local route=assert(x.api.resolve(FRYDERIK));eq(nil,route.identityUpgraded);eq(nil,route.npcId)
    x:place(2);x:entities("Fryderik");eq(false,x.api.deliveryReady(route))
    x.record=nil;local fresh,why=x.api.resolve(FRYDERIK);eq(nil,fresh);ok(why:find("kilku NPC",1,true))
end)
test("the alias title never authorizes an unrelated complete postal addressee",function()
    for _,full in ipairs({"Fryderik Nowak","Fryderik Kowal","Johan Miecznik"}) do
        local x=fixture({fryderik()},memory({recipient=full}));local route=assert(x.api.resolve(full))
        eq(nil,route.identityUpgraded);x:place(2);x:entities("Fryderik","npc","Fryderik z Nuln");eq(false,x.api.deliveryReady(route))
    end
end)

print(string.format("IDENTITY_UPGRADE: %d scenarios, %d assertions passed",cases,assertions))
