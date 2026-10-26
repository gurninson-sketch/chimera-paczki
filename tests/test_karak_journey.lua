-- Pure composition of both independent transport services; no real game/map.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_karak_journey%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/journey.lua")
local Q,NORTH,SOUTH="e202c7893bf8fb55","20016d960316ba51","894039a1680ca034"
local BLUE,BLACK,KARAK="891456eab7637380","2e1aa32a45a83107","c55c2924e506dd7f"
local DECK,GATE="be0c7fc1d5441e3a","c39ae21ea0b2b173"
local passed,failed,checks=0,0,0
local function eq(expected,actual,why)
    checks=checks+1
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function ok(value,why) checks=checks+1;assert(value,why or "condition") end
local function test(name,body)
    local success,problem=pcall(body)
    if success then passed=passed+1;print("OK "..name)
    else failed=failed+1;print("FAIL "..name..": "..tostring(problem)) end
end
local function setup()
    local s={map=1,id=Q,hashes={[1]=Q,[2]=NORTH,[3]=SOUTH,[4]=BLUE,[5]=BLACK,[6]=KARAK,[7]=DECK,[8]=GATE},
        maps={},costs={},runs={},events={},cleanups={},plans={}}
    for map,id in pairs(s.hashes) do s.maps[id]=map end
    _G.getRoomIDbyHash=function(id) return s.maps[id] or -1 end
    function s.at(map,id) s.map,s.id=map,id or s.hashes[map] end
    function s.edge(from,to,cost) s.costs[from..":"..to]=cost end
    function s.standard()
        s.edge(1,2,10);s.edge(2,1,10)
        s.edge(3,4,20);s.edge(4,3,20)
        s.edge(5,6,30);s.edge(6,5,30)
        s.edge(6,8,2);s.edge(8,6,2);s.edge(8,5,31);s.edge(5,8,31)
    end
    local ctx={}
    function ctx:emit(event,value)
        s.events[#s.events+1]={event=event,value=value}
        if s.onEvent then s.onEvent(event,value) end
    end
    function ctx:cleanup(fn) s.cleanups[#s.cleanups+1]=fn end
    function s.result()
        local result={calls=0}
        return result,function(value) result.calls=result.calls+1;result.value=value end
    end
    function s.complete(record,success)
        if success then
            if record.kind=="road" then s.at(record.plan.target)
            else s.at(record.link and record.link.toMap or record.toMap);s.voyage=nil;s.kahnVoyage=nil end
        end
        record.done({ok=success,reason=not success and "synthetic refusal" or nil})
    end
    local function child(kind,payload,done)
        if kind=="road" and #payload.steps==0 then
            s.at(payload.target);done({ok=true});return function() end
        end
        local record={kind=kind,done=done,cancelCalls=0}
        if kind=="road" then record.plan=payload
        elseif type(payload)=="table" then record.link=payload
        else record.toMap=payload end
        s.runs[#s.runs+1]=record
        if s.onRun then s.onRun(record) end
        return function() record.cancelCalls=record.cancelCalls+1;done({ok=false,reason="cancelled"}) end
    end
    local road={}
    function road.plan(from,to)
        s.plans[#s.plans+1]={from=from,to=to}
        if not from or not to then return nil,"off map" end
        local cost=from==to and 0 or s.costs[from..":"..to]
        if cost==nil then return nil,"no safe road" end
        local plan={from=from,target=to,fromId=s.hashes[from],targetId=s.hashes[to],cost=cost,steps={}}
        if from~=to then plan.steps[1]={cmd="road:"..from..":"..to,map=to,id=s.hashes[to],weight=cost} end
        return plan
    end
    function road.run(plan,done) return child("road",plan,done) end
    local ferry={}
    function ferry.catalogue()
        if s.noFerry or not s.maps[NORTH] or not s.maps[SOUTH] then return {} end
        return {{fromHash=NORTH,toHash=SOUTH,cost=40,transport="ferry"},
            {fromHash=SOUTH,toHash=NORTH,cost=40,transport="ferry"}}
    end
    function ferry.run(link,done) return child("ferry",link,done) end
    function ferry.resume(toMap,done) return child("ferry_resume",toMap,done) end
    function ferry.state() return s.voyage end
    local kahn={}
    function kahn.catalogue()
        if s.noKahn or not s.maps[BLUE] or not s.maps[BLACK] or not s.maps[DECK] then return {} end
        return {{fromHash=BLUE,toHash=BLACK,fromMap=s.maps[BLUE],toMap=s.maps[BLACK],deckMap=s.maps[DECK],cost=60,transport="karak_ship"},
            {fromHash=BLACK,toHash=BLUE,fromMap=s.maps[BLACK],toMap=s.maps[BLUE],deckMap=s.maps[DECK],cost=60,transport="karak_ship"}}
    end
    function kahn.run(link,done) return child("karak_ship",link,done) end
    function kahn.resume(link,done) return child("karak_resume",link,done) end
    function kahn.state() return s.kahnVoyage end
    s.api=create(ctx,{road=road,ferry=ferry,karakTransport=kahn,
        gmcp={room=function() return {id=s.id} end},mapper={current_room=function() return s.map end,
            chimera_id=function(map) return s.hashes[map] end}})
    return s
end
local function kinds(plan)
    local out={};for _,leg in ipairs(plan.legs) do out[#out+1]=leg.kind end
    return table.concat(out,",")
end

test("Quenelles to Karak composes Grismerie and Kahn-Gad with separate road legs",function()
    local s=setup();s.standard();local plan=assert(s.api.plan(1,6))
    eq(160,plan.cost);eq("road,ferry,road,karak_ship,road",kinds(plan))
    eq(NORTH,plan.legs[2].link.fromHash);eq(SOUTH,plan.legs[2].link.toHash)
    eq(BLUE,plan.legs[4].link.fromHash);eq(BLACK,plan.legs[4].link.toHash)
end)
test("Karak return uses both ships in the reverse order and never a cheap land alternative",function()
    local s=setup();s.standard();s.at(6);s.edge(6,1,1)
    local plan=assert(s.api.plan(6,1))
    eq(160,plan.cost);eq("road,karak_ship,road,ferry,road",kinds(plan))
    eq(BLACK,plan.legs[2].link.fromHash);eq(BLUE,plan.legs[2].link.toHash)
    eq(SOUTH,plan.legs[4].link.fromHash);eq(NORTH,plan.legs[4].link.toHash)
end)
test("missing ship bank deck or service rejects Karak instead of a cheap direct mountain pickup",function()
    for _,missing in ipairs({BLUE,BLACK,DECK,"kahn","ferry","road"}) do
        local s=setup();s.standard();s.edge(1,6,1)
        if missing=="kahn" then s.noKahn=true
        elseif missing=="ferry" then s.noFerry=true
        elseif missing=="road" then s.costs["5:6"]=nil
        else s.maps[missing]=nil end
        local plan,why=s.api.plan(1,6)
        eq(nil,plan,missing);ok(type(why)=="string" and #why>0);eq(0,#s.runs)
    end
end)
test("same Karak side destinations use their ordinary city road with no ticket or ship",function()
    local s=setup();s.standard();s.at(8)
    local plan=assert(s.api.plan(8,6));eq(2,plan.cost);eq("road",kinds(plan));eq(nil,plan.link)
    eq(0,s.api.cost(6,6));eq(0,#s.runs)
end)
test("two transport metrics use real crossings not cost weights and flag the unknown ticket fare",function()
    local s=setup();s.standard();local metrics=assert(s.api.metrics(1,6))
    eq(3,metrics.steps);eq(2,metrics.ferries);eq(0,metrics.delayUnits)
    eq(NORTH..">"..SOUTH,metrics.ferryKeys[1]);eq(BLUE..">"..BLACK,metrics.ferryKeys[2])
    eq(true,metrics.fareUnknown);eq(0,metrics.fareCopper)
    s.edge(1,2,9999);local expensive=assert(s.api.metrics(1,6));eq(3,expensive.steps);eq(2,expensive.ferries)
    eq(metrics.signature,expensive.signature,"map weight must not change path identity")
end)
test("fresh Kahn-Gad deck plans resume toward only the reachable requested shore",function()
    local s=setup();s.standard();s.at(7)
    local toKarak=assert(s.api.plan(7,6));eq("karak_resume,road",kinds(toKarak))
    eq(BLACK,toKarak.legs[1].link.toHash);eq(90,toKarak.cost)
    local toQuenelles=assert(s.api.plan(7,1));eq("karak_resume,road,ferry,road",kinds(toQuenelles))
    eq(BLUE,toQuenelles.legs[1].link.toHash);eq(130,toQuenelles.cost)
    local result,done=s.result();s.api.idz(6,done);eq("karak_resume",s.runs[1].kind)
    s.complete(s.runs[1],true);s.complete(s.runs[2],true);eq(true,result.value.ok);eq(1,result.calls)
end)
test("a current unmapped Grismerie deck resumes its voyage before reaching Kahn-Gad",function()
    local s=setup();s.standard();s.at(nil,"grismerie-deck")
    s.voyage={aboard=true,fromHash=NORTH,toHash=SOUTH,fromMap=2,toMap=3,cost=40}
    local plan=assert(s.api.plan(nil,6))
    eq("resume,road,karak_ship,road",kinds(plan));eq(150,plan.cost)
    local metric=assert(s.api.metricsForPlan(plan));eq(2,metric.ferries)
    local result,done=s.result();s.api.idz(6,done);eq("ferry_resume",s.runs[1].kind)
    for index=1,4 do s.complete(s.runs[index],true) end
    eq(true,result.value.ok);eq(1,result.calls);eq(6,s.map)
end)
test("hypothetical return cost remains independent of the current Grismerie voyage",function()
    local s=setup();s.standard();s.at(nil,"grismerie-deck")
    s.voyage={aboard=true,fromHash=NORTH,toHash=SOUTH,fromMap=2,toMap=3,cost=40}
    eq(160,s.api.cost(6,1));eq(0,s.api.cost(6,6));eq(0,#s.runs)
end)
test("stopping before Kahn-Gad retains the second crossing rather than replaying Grismerie",function()
    local s=setup();s.standard();local result,done=s.result();local cancel=s.api.idz(6,done)
    s.complete(s.runs[1],true);s.complete(s.runs[2],true)
    eq(3,s.map);eq("road",s.runs[3].kind)
    s.onEvent=function(_,event) if event.phase=="ferry" and s.map==4 then cancel() end end
    s.complete(s.runs[3],true);eq(false,result.value.ok);eq(3,#s.runs)
    s.onEvent=nil
    local resumed,resumeDone=s.result();s.api.idz(6,resumeDone)
    eq("karak_ship",s.runs[4].kind);eq(BLUE,s.runs[4].link.fromHash)
    s.complete(s.runs[4],true);s.complete(s.runs[5],true)
    eq(true,resumed.value.ok);eq(1,resumed.calls)
end)
test("late first transport callback cannot skip an active second ship or complete twice",function()
    local s=setup();s.standard();local result,done=s.result();s.api.idz(6,done)
    local firstBoat
    for index=1,3 do if s.runs[index].kind=="ferry" then firstBoat=s.runs[index] end;s.complete(s.runs[index],true) end
    eq("karak_ship",s.runs[4].kind);firstBoat.done({ok=true});firstBoat.done({ok=false})
    eq(4,#s.runs);eq(0,result.calls)
    s.complete(s.runs[4],true);s.complete(s.runs[5],true);firstBoat.done({ok=true})
    eq(1,result.calls);eq(true,result.value.ok);eq(5,#s.runs)
end)
test("a return paused before Grismerie retains that second crossing even if a cheaper road appears",function()
    local s=setup();s.standard();s.at(6)
    local result,done=s.result();local cancel=s.api.idz(1,done)
    s.complete(s.runs[1],true);eq("karak_ship",s.runs[2].kind);s.complete(s.runs[2],true)
    s.onEvent=function(_,event) if event.phase=="ferry" and s.map==3 then cancel() end end
    s.complete(s.runs[3],true);eq(false,result.value.ok);eq(3,#s.runs)
    s.edge(3,1,1);s.onEvent=nil
    local resumed,resumeDone=s.result();s.api.idz(1,resumeDone)
    eq("ferry",s.runs[4].kind);eq(SOUTH,s.runs[4].link.fromHash)
    s.complete(s.runs[4],true);s.complete(s.runs[5],true)
    eq(true,resumed.value.ok);eq(1,resumed.calls);eq(1,s.map)
end)
test("cancellation during Kahn-Gad owns exactly one cancel and no later road send",function()
    local s=setup();s.standard();local result,done=s.result();local cancel=s.api.idz(6,done)
    for index=1,3 do s.complete(s.runs[index],true) end
    local ship=s.runs[4];cancel();cancel();ship.done({ok=true})
    eq(1,ship.cancelCalls);eq(1,result.calls);eq(false,result.value.ok);eq(4,#s.runs)
end)

print(string.format("KARAK_JOURNEY: %d scenarios, %d assertions, %d failures",passed+failed,checks,failed))
if failed>0 then os.exit(1) end
