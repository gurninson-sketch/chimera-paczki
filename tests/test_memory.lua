-- Pure Lua 5.1-compatible confirmed-delivery memory tests.
local create=dofile("chimera_wtyczki/chimera_paczki/memory.lua")
local tests,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function clone(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out
end
local function proof(name,room)
    return {recipient=name or "Rolph Ederson",roomHash=room or "room-a",map=10,
        verified=true,handover=true,reward=true}
end
local function setup(saved)
    local e={time=1000,saves=0}
    e.api=create(saved,{now=function() if e.clockError then error("clock failed") end;return e.time end,
        save=function(state)
            e.saves=e.saves+1
            if e.fail=="throw" then error("save failed") end
            if e.fail then return false end
            e.saved=state
        end})
    return e.api,e
end

test("all three exact success flags are required; observations never teach",function()
    local m,e=setup()
    for _,field in ipairs({"verified","handover","reward"}) do
        for _,value in ipairs({false,0,"true"}) do
            local evidence=proof();evidence[field]=value
            local ok,why=m.remember(evidence);eq(ok,false);check(type(why)=="string")
        end
        local evidence=proof();evidence[field]=nil;eq(m.remember(evidence),false)
    end
    eq(m.remember({recipient="Rolph Ederson",roomHash="room-a",map=10,seen=true}),false)
    eq(m.remember(nil),false);eq(m.remember("observation"),false)
    eq(m.count(),0);eq(e.saves,0)
end)
test("recipient, stable room hash and positive numeric map position are validated",function()
    local m,e=setup()
    for _,value in ipairs({0,-1,1.5,math.huge,0/0,"10",false,{}}) do
        local evidence=proof();evidence.map=value;eq(m.remember(evidence),false)
    end
    local evidence=proof();evidence.map=nil;eq(m.remember(evidence),false)
    for _,value in ipairs({"", " \n ",42,false,{}}) do
        evidence=proof();evidence.roomHash=value;eq(m.remember(evidence),false)
        evidence=proof();evidence.recipient=value;eq(m.remember(evidence),false)
    end
    evidence=proof();evidence.recipient="...";eq(m.remember(evidence),false)
    evidence=proof();evidence.postal="yes";eq(m.remember(evidence),false)
    eq(e.saves,0);eq(m.count(),0)
end)
test("successful room-only evidence stores only the allowlisted profile data",function()
    local m,e=setup();local evidence=proof()
    evidence.actor="player";evidence.account="account";evidence.password="secret"
    evidence.count=9999;evidence.last=1;evidence.mapId=123;evidence.character={name="player"}
    eq(m.remember(evidence),true);eq(m.count(),1);eq(e.saves,1);eq(e.saved.schema,1)
    local record=e.saved.records["rolph ederson"]
    eq(record.recipient,"Rolph Ederson");eq(record.count,1);eq(record.last,1000);eq(record.postal,false)
    eq(#record.roomHashes,1);eq(record.roomHashes[1],"room-a")
    for _,field in ipairs({"map","mapId","actor","account","password","character","npcId","name"}) do eq(record[field],nil) end
end)
test("exact full recipient matching folds Polish text, spacing and case without guessing",function()
    local m=setup();eq(m.remember(proof("  Jóhan   Żółw  ","ROOM-A")),true)
    local record=m.find("johan zolw");eq(record.recipient,"Jóhan Żółw");eq(record.roomHashes[1],"room-a")
    eq(m.find(" JÓHAN ŻÓŁW. ").count,1)
    eq(m.find("Johan"),nil);eq(m.find("Żółw"),nil);eq(m.find("Johan Zolw Starszy"),nil)
    eq(m.find(nil),nil);eq(m.find(42),nil)
end)
test("repeated deliveries count once per call and put the latest verified room first",function()
    local m,e=setup()
    eq(m.remember(proof()),true);e.time=1010;eq(m.remember(proof(nil,"room-b")),true)
    e.time=1020;eq(m.remember(proof(nil,"ROOM-A")),true)
    local record=m.find("Rolph Ederson")
    eq(record.count,3);eq(record.last,1020);eq(#record.roomHashes,2)
    eq(record.roomHashes[1],"room-a");eq(record.roomHashes[2],"room-b")
    local loaded=create(e.saved);eq(loaded.find("Rolph Ederson").count,3)
    eq(loaded.find("Rolph Ederson").roomHashes[1],"room-a")
end)
test("optional verified NPC identity is copied and updated without stale fields",function()
    local m,e=setup();local evidence=proof()
    evidence.npc={npcId="npc-1",name="Rolph",short="otyly mezczyzna",title="Rolph Ederson, kaplan",actor="player",map=5}
    eq(m.remember(evidence),true)
    evidence.npc.name="mutated";local record=m.find("Rolph Ederson")
    eq(record.npcId,"npc-1");eq(record.name,"Rolph");eq(record.short,"otyly mezczyzna");eq(record.title,"Rolph Ederson, kaplan")
    eq(record.actor,nil);eq(record.map,nil)
    eq(m.remember(proof(nil,"room-b")),true);eq(m.find("Rolph Ederson").npcId,"npc-1","room-only success retains an existing verified identity")
    evidence=proof();evidence.npc={npcId="npc-2",name="Rolph"}
    eq(m.remember(evidence),true);record=m.find("Rolph Ederson")
    eq(record.npcId,"npc-2");eq(record.short,nil);eq(record.title,nil);eq(record.count,3)
end)
test("malformed NPC identity and contradictory postal classification are rejected",function()
    local m,e=setup()
    for _,npc in ipairs({{},"npc",{npcId="npc-1"},{name="Rolph"},{npcId="npc-1",name="Rolph",short=10}}) do
        local evidence=proof();evidence.npc=npc;eq(m.remember(evidence),false)
    end
    local evidence=proof("Poczta w Nuln");evidence.postal=true
    eq(m.remember(evidence),true);eq(m.find("Poczta w Nuln").postal,true)
    evidence.npc={npcId="worker",name="Pracownik"};eq(m.remember(evidence),false)
    evidence.npc=nil;evidence.postal=false;eq(m.remember(evidence),false)
    eq(m.find("Poczta w Nuln").count,1);eq(e.saves,1)
end)
test("find, all and persistence receive independent copies",function()
    local m,e=setup();eq(m.remember(proof()),true)
    local record=m.find("Rolph Ederson");record.count=42;record.roomHashes[1]="wrong";record.recipient="wrong"
    local all=m.all();all[1].count=8;all[1].roomHashes[1]="wrong-again";all[2]={}
    e.saved.records["rolph ederson"].roomHashes[1]="saved-mutation"
    eq(m.find("Rolph Ederson").count,1);eq(m.find("Rolph Ederson").roomHashes[1],"room-a")
    eq(m.find("Rolph Ederson").recipient,"Rolph Ederson");eq(m.count(),1)
end)
test("all recipients are returned in a deterministic full-name order",function()
    local m=setup()
    eq(m.remember(proof("Żaneta Łącka")),true);eq(m.remember(proof("Berta Leibentropp")),true);eq(m.remember(proof("Athelstan Shergison")),true)
    local all=m.all();eq(#all,3)
    eq(all[1].recipient,"Athelstan Shergison");eq(all[2].recipient,"Berta Leibentropp");eq(all[3].recipient,"Żaneta Łącka")
end)
test("failed save leaves learning, forgetting and clearing atomic",function()
    local m,e=setup();eq(m.remember(proof()),true)
    for _,failure in ipairs({true,"throw"}) do
        e.fail=failure
        eq(m.remember(proof(nil,"room-b")),false);eq(m.find("Rolph Ederson").count,1)
        eq(m.find("Rolph Ederson").roomHashes[1],"room-a")
        eq(m.forget("Rolph Ederson"),false);eq(m.count(),1)
        eq(m.clear(),false);eq(m.count(),1)
    end
    e.fail=false;eq(m.forget("Rolph Ederson"),true);eq(m.count(),0)
    eq(next(e.saved.records),nil);eq(e.saved.schema,1)
end)
test("forget requires the full name; clear persists an empty schema",function()
    local m,e=setup();m.remember(proof());m.remember(proof("Jóhan Żółw"))
    eq(m.forget("Rolph"),false);eq(m.count(),2);eq(e.saves,2)
    eq(m.forget("johan zolw"),true);eq(m.count(),1);eq(m.find("Jóhan Żółw"),nil)
    eq(m.clear(),true);eq(m.count(),0);eq(#m.all(),0);eq(next(e.saved.records),nil)
    eq(m.clear(),true);eq(e.saved.schema,1)
end)
test("unsupported schemas and malformed saved records do not become learned recipients",function()
    local good={recipient="Rolph Ederson",roomHashes={"ROOM-A","room-a","room-b",0},count=2,last=900,
        postal=false,npcId="npc-1",name="Rolph",short="otyly",title="Rolph Ederson",map=123,actor="player"}
    local saved={schema=1,records={["rolph ederson"]=good,
        ["wrong key"]={recipient="Berta Leibentropp",roomHashes={"room-c"},count=1,last=900},
        ["empty rooms"]={recipient="Empty Rooms",roomHashes={},count=1,last=900},
        ["negative count"]={recipient="Negative Count",roomHashes={"room-c"},count=-1,last=900},
        ["fractional count"]={recipient="Fractional Count",roomHashes={"room-c"},count=1.5,last=900},
        ["bad last"]={recipient="Bad Last",roomHashes={"room-c"},count=1,last=math.huge},
        ["bad postal"]={recipient="Bad Postal",roomHashes={"room-c"},count=1,last=900,postal="yes"}}}
    local m=create(saved);eq(m.count(),1)
    local record=m.find("Rolph Ederson");eq(record.count,2);eq(#record.roomHashes,2);eq(record.roomHashes[1],"room-a")
    eq(record.npcId,"npc-1");eq(record.map,nil);eq(record.actor,nil)
    saved.records["rolph ederson"].roomHashes[1]="changed";eq(m.find("Rolph Ederson").roomHashes[1],"room-a")
    eq(create({schema=2,records={["rolph ederson"]=good}}).count(),0)
    eq(create({records={["rolph ederson"]=good}}).count(),0)
    eq(create("invalid").count(),0)
end)
test("malformed saved NPC identity is discarded without inventing named identity",function()
    local m=create({schema=1,records={["rolph ederson"]={recipient="Rolph Ederson",roomHashes={"room-a"},count=1,last=1000,
        npcId="npc-1",name="Rolph",title={actor="player"}}}})
    eq(m.count(),1);eq(m.find("Rolph Ederson").npcId,nil);eq(m.find("Rolph Ederson").name,nil)
end)
test("separate profile memories and exported snapshots never share live state",function()
    local first,e=setup();first.remember(proof())
    local second=create(e.saved);first.remember(proof(nil,"room-b"))
    eq(first.find("Rolph Ederson").count,2);eq(second.find("Rolph Ederson").count,1)
    second.clear();eq(second.count(),0);eq(first.count(),1)
end)
test("invalid clock results cannot teach or save",function()
    local m,e=setup();e.clockError=true;eq(m.remember(proof()),false);eq(e.saves,0)
    e.clockError=false;e.time=-1;eq(m.remember(proof()),false)
    e.time=math.huge;eq(m.remember(proof()),false);e.time=0/0;eq(m.remember(proof()),false)
    eq(m.count(),0);eq(e.saves,0)
end)
test("absurd saved counts cannot overflow the successful-delivery counter",function()
    local m=create({schema=1,records={["rolph ederson"]={recipient="Rolph Ederson",roomHashes={"room-a"},count=9007199254740990,last=1000}}})
    eq(m.count(),1);eq(m.remember(proof()),false);eq(m.find("Rolph Ederson").count,9007199254740990)
end)

test("portable export is an independent allowlisted snapshot of NPCs and post offices",function()
    local m,e=setup();local evidence=proof()
    evidence.npc={npcId="npc-1",name="Rolph",short="otyly",title="Rolph Ederson, kaplan"}
    evidence.actor="profile-owner";evidence.password="not-exported";eq(m.remember(evidence),true)
    evidence=proof("Poczta w Ebino","ebino-hash");evidence.postal=true;eq(m.remember(evidence),true)
    local snapshot=m.exportState();eq(snapshot.schema,1);eq(snapshot.records["poczta w ebino"].postal,true)
    local record=snapshot.records["rolph ederson"];eq(record.npcId,"npc-1");eq(record.roomHashes[1],"room-a")
    for _,field in ipairs({"map","mapId","actor","password","job","stats"}) do eq(record[field],nil);eq(snapshot[field],nil) end
    record.roomHashes[1]="mutated";record.name="Mutated";snapshot.records["new entry"]={}
    eq(m.find("Rolph Ederson").roomHashes[1],"room-a");eq(m.find("Rolph Ederson").name,"Rolph");eq(m.count(),2)
    eq(e.saves,2)
end)
test("portable import adds recipients without changing the source or existing local records",function()
    local source=setup();source.remember(proof())
    local postal=proof("Poczta w Ebino","ebino-hash");postal.postal=true;source.remember(postal)
    local target,e=setup();target.remember(proof("Berta Leibentropp","berta-hash"))
    local snapshot=source.exportState();snapshot.actor="unrelated";snapshot.records["rolph ederson"].map=999
    local ok,result=target.importState(snapshot);eq(ok,true);eq(result.added,2);eq(result.updated,0);eq(result.unchanged,0);eq(result.total,3)
    eq(target.find("Poczta w Ebino").postal,true);eq(target.find("Berta Leibentropp").roomHashes[1],"berta-hash")
    eq(target.find("Rolph Ederson").map,nil);eq(target.exportState().actor,nil);eq(source.count(),2)
    snapshot.records["rolph ederson"].roomHashes[1]="changed-after-import"
    eq(target.find("Rolph Ederson").roomHashes[1],"room-a");eq(e.saves,2)
end)
test("merge prioritizes newer room history uses maximum counters and keeps local NPC identity",function()
    local m,e=setup();local p=proof()
    p.npc={npcId="local-id",name="Rolph",short="local",title="Rolph Ederson"}
    m.remember(p);e.time=1010;m.remember(proof(nil,"room-b"))
    local source,sourceEnv=setup();sourceEnv.time=1100
    p=proof(nil,"room-c");p.npc={npcId="imported-id",name="Other Rolph",title="Imported title"}
    source.remember(p);sourceEnv.time=1200;source.remember(proof(nil,"room-b"));source.remember(proof(nil,"room-d"))
    local snapshot=source.exportState();local ok,summary=m.importState(snapshot)
    eq(ok,true);eq(summary.added,0);eq(summary.updated,1);eq(summary.total,1)
    local record=m.find("Rolph Ederson");eq(record.count,3);eq(record.last,1200)
    eq(table.concat(record.roomHashes,","),"room-d,room-b,room-c,room-a")
    eq(record.npcId,"local-id");eq(record.short,"local");eq(record.title,"Rolph Ederson")
    local saves=e.saves;ok,summary=m.importState(snapshot);eq(ok,true);eq(summary.updated,0);eq(summary.unchanged,1)
    eq(e.saves,saves,"repeated import must not rewrite unchanged memory");eq(m.find("Rolph Ederson").count,3)
    eq(table.concat(m.find("Rolph Ederson").roomHashes,","),"room-d,room-b,room-c,room-a")
end)
test("older imports retain local room priority and can fill a missing verified identity",function()
    local m,e=setup();m.remember(proof(nil,"local-room"));e.time=1500;m.remember(proof(nil,"new-local-room"))
    local source=setup();local p=proof(nil,"old-imported-room");p.npc={npcId="npc-1",name="Rolph",title="Rolph Ederson"}
    source.remember(p)
    local ok,result=m.importState(source.exportState());eq(ok,true);eq(result.updated,1)
    local record=m.find("Rolph Ederson");eq(record.count,2);eq(record.last,1500);eq(record.npcId,"npc-1")
    eq(table.concat(record.roomHashes,","),"new-local-room,local-room,old-imported-room")
end)
test("a malformed imported record rejects the whole batch without a partial save",function()
    local source=setup();source.remember(proof());source.remember(proof("Berta Leibentropp","room-b"))
    local good=source.exportState()
    local badValues={false,"bad",{schema=2,records=good.records},{records=good.records},{schema=1,records=false}}
    local mutations={
        function(r) r.count=0 end,function(r) r.count=1.5 end,function(r) r.last=math.huge end,
        function(r) r.last=0/0 end,function(r) r.postal="yes" end,function(r) r.recipient="Other Name" end,
        function(r) r.roomHashes={} end,function(r) r.roomHashes={"room-a",4} end,
        function(r) r.roomHashes={"room-a",""} end,function(r) r.roomHashes={[1]="room-a",[3]="room-c"} end,
        function(r) r.roomHashes={"room-a",other="room-c"} end,
        function(r) r.npcId="incomplete" end,function(r) r.name="incomplete" end,
        function(r) r.npcId="npc";r.name="Rolph";r.title={} end,
        function(r) r.postal=true;r.npcId="worker";r.name="Worker" end,
    }
    for _,mutate in ipairs(mutations) do local snapshot=clone(good);mutate(snapshot.records["rolph ederson"]);badValues[#badValues+1]=snapshot end
    local numericKey=clone(good);numericKey.records[1]=clone(good.records["rolph ederson"]);badValues[#badValues+1]=numericKey
    for _,snapshot in ipairs(badValues) do
        local m,e=setup();m.remember(proof("Local Recipient","local-room"));local saves=e.saves
        local ok,why=m.importState(snapshot);eq(ok,false);check(type(why)=="string")
        eq(m.count(),1);eq(m.find("Rolph Ederson"),nil);eq(m.find("Berta Leibentropp"),nil);eq(e.saves,saves)
    end
    local m,e=setup();eq(m.importState(nil),false);eq(e.saves,0)
end)
test("NPC versus postal conflict rejects all imported changes atomically",function()
    local m,e=setup();m.remember(proof("Poczta w Ebino","local-room"))
    local source=setup();source.remember(proof("New Recipient","new-room"))
    local postal=proof("Poczta w Ebino","postal-room");postal.postal=true;source.remember(postal)
    local saves=e.saves;local ok,why=m.importState(source.exportState());eq(ok,false);check(why:find("sprzeczny",1,true))
    eq(m.count(),1);eq(m.find("New Recipient"),nil);eq(m.find("Poczta w Ebino").postal,false);eq(e.saves,saves)
end)
test("failed portable import persistence retains both memories and allows a later retry",function()
    local source=setup();source.remember(proof())
    for _,failure in ipairs({true,"throw"}) do
        local m,e=setup();m.remember(proof("Local Recipient","local-room"));local prior=clone(e.saved)
        e.fail=failure;local ok,why=m.importState(source.exportState());eq(ok,false);check(type(why)=="string")
        eq(m.count(),1);eq(m.find("Rolph Ederson"),nil);eq(source.count(),1)
        eq(e.saved.records["local recipient"].roomHashes[1],prior.records["local recipient"].roomHashes[1])
        e.fail=false;local summary;ok,summary=m.importState(source.exportState());eq(ok,true);eq(summary.added,1);eq(summary.total,2)
    end
end)
test("empty import and same snapshot preserve state without writes and tolerate canonical deduplication",function()
    local m,e=setup();m.remember(proof())
    local saves=e.saves;local ok,summary=m.importState({schema=1,records={}})
    eq(ok,true);eq(summary.total,1);eq(summary.added,0);eq(summary.updated,0);eq(summary.unchanged,0);eq(e.saves,saves)
    local snapshot=m.exportState();snapshot.records["rolph ederson"].roomHashes={"ROOM-A","room-a"}
    ok,summary=m.importState(snapshot);eq(ok,true);eq(summary.unchanged,1);eq(e.saves,saves)
    eq(#m.find("Rolph Ederson").roomHashes,1)
end)

print(string.format("Confirmed memory: %d tests, %d assertions passed",tests,checks))
