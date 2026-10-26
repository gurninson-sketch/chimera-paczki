-- Pure composition tests: no Mudlet, native walker or live ferry is needed.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_journey%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/journey.lua")
local NULN,QUENELLES="6f2c03461c2f1438","e202c7893bf8fb55"
local SOUTH,NORTH="894039a1680ca034","20016d960316ba51"
local passed,failed=0,0
local function eq(expected,actual,why)
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,body)
    local ok,problem=pcall(body)
    if ok then passed=passed+1;print("OK "..name)
    else failed=failed+1;print("FAIL "..name..": "..tostring(problem)) end
end

local function setup()
    local s={map=1,id=NULN,hashes={[1]=NULN,[2]=SOUTH,[3]=NORTH,[4]=QUENELLES,[5]="ordinary",[6]="midpoint",[7]="other"},
        maps={},costs={},runs={},events={},cleanups={},planning={}}
    for map,id in pairs(s.hashes) do s.maps[id]=map end
    _G.getRoomIDbyHash=function(id) return s.maps[id] or -1 end
    function s.at(map,id) s.map,s.id=map,id or s.hashes[map] end
    function s.edge(from,to,value) s.costs[from..":"..to]=value end
    function s.result()
        local result={calls=0}
        return result,function(value) result.calls,result.value=result.calls+1,value end
    end
    function s.complete(record,ok)
        if ok then
            if record.kind=="road" then s.at(record.plan.target)
            else s.at(record.link and record.link.toMap or record.toMap);s.voyage=nil end
        end
        record.done({ok=ok,reason=not ok and "fake failure" or nil})
    end
    local ctx={}
    function ctx:emit(event,value)
        s.events[#s.events+1]={event=event,value=value}
        if s.onActivity then s.onActivity(event,value) end
    end
    function ctx:cleanup(callback) s.cleanups[#s.cleanups+1]=callback end
    function s.cleanup() for i=#s.cleanups,1,-1 do s.cleanups[i]() end end
    local function child(kind,payload,done)
        local record={kind=kind,done=done,cancelCalls=0}
        if kind=="road" then record.plan=payload
        elseif kind=="ferry" then record.link=payload
        else record.toMap=payload end
        s.runs[#s.runs+1]=record
        if s.onRun then s.onRun(record) end
        if s.synchronous then s.complete(record,true) end
        return function()
            record.cancelCalls=record.cancelCalls+1
            done({ok=false,reason="cancelled synchronously"})
        end
    end
    local road={}
    function road.plan(from,to)
        s.planning[#s.planning+1]={from=from,to=to}
        if not from or not to then return nil,"no position" end
        local value=from==to and 0 or s.costs[from..":"..to]
        if not value then return nil,"unreachable" end
        -- Each fake map query overwrites the same globals, as getPath does.
        _G.speedWalkDir={"road:"..from..":"..to}
        _G.speedWalkPath={to}
        _G.speedWalkWeight={value}
        local plan={from=from,target=to,cost=value,fromId=s.hashes[from],targetId=s.hashes[to],steps={}}
        if from~=to then
            plan.steps[1]={cmd=speedWalkDir[1],map=speedWalkPath[1],id=s.hashes[to],weight=speedWalkWeight[1]}
        end
        return plan
    end
    function road.run(plan,done) return child("road",plan,done) end
    local ferry={}
    function ferry.catalogue()
        if s.noFerry then return {} end
        return {{id="forward",fromHash=SOUTH,toHash=NORTH,cost=40},
            {id="reverse",fromHash=NORTH,toHash=SOUTH,cost=40}}
    end
    function ferry.state() return s.voyage end
    function ferry.run(link,done) return child("ferry",link,done) end
    function ferry.resume(toMap,done) return child("resume",toMap,done) end
    s.api=create(ctx,{road=road,ferry=ferry,gmcp={room=function() return {id=s.id} end},
        mapper={current_room=function() return s.map end,chimera_id=function(map) return s.hashes[map] end}})
    function s.standard()
        s.edge(1,4,213);s.edge(4,1,213)
        s.edge(1,2,10);s.edge(3,4,20)
        s.edge(4,3,20);s.edge(2,1,10)
    end
    return s
end

test("Nuln to Quenelles forces the correct ferry direction despite a 213-road alternative",function()
    local s=setup();s.standard()
    s.edge(1,3,1);s.edge(2,4,1) -- wrong-direction candidate would cost only 42
    local plan=assert(s.api.plan(1,4))
    eq(SOUTH,plan.link.fromHash);eq(NORTH,plan.link.toHash);eq(70,plan.cost)
    eq(3,#plan.legs);eq("road",plan.legs[1].kind);eq("ferry",plan.legs[2].kind)
    eq(2,plan.legs[1].plan.target);eq(3,plan.legs[3].plan.from)
end)

test("Quenelles to Nuln forces the verified reverse crossing",function()
    local s=setup();s.standard();s.at(4)
    s.edge(4,2,1);s.edge(3,1,1)
    local plan=assert(s.api.plan(4,1))
    eq(NORTH,plan.link.fromHash);eq(SOUTH,plan.link.toHash);eq(70,plan.cost)
end)

test("missing mapped bank or unreachable required leg cannot fall back to land pickup",function()
    for _,missing in ipairs({"south","north","first","last","ferry"}) do
        local s=setup();s.standard()
        if missing=="south" then s.maps[SOUTH]=nil
        elseif missing=="north" then s.maps[NORTH]=nil
        elseif missing=="first" then s.costs["1:2"]=nil
        elseif missing=="last" then s.costs["3:4"]=nil
        else s.noFerry=true end
        local plan,why=s.api.plan(1,4)
        eq(nil,plan,missing);assert(why and why~="")
        eq(nil,s.api.cost(1,4));eq(0,#s.runs)
    end
end)

test("outbound availability does not fabricate a hypothetical return leg",function()
    local s=setup();s.standard();s.costs["2:1"]=nil
    assert(s.api.plan(1,4));eq(nil,s.api.cost(4,1))
end)

test("ordinary destinations select the cheapest complete road or ferry composition",function()
    local s=setup();s.edge(1,5,8);s.edge(1,2,10);s.edge(3,5,20)
    local direct=assert(s.api.plan(1,5));eq(8,direct.cost);eq("road",direct.legs[1].kind);eq(nil,direct.link)
    s=setup();s.edge(5,6,100);s.edge(5,2,5);s.edge(3,6,7)
    local composed=assert(s.api.plan(5,6));eq(52,composed.cost);eq(SOUTH,composed.link.fromHash)
    s.edge(5,6,52);local tie=assert(s.api.plan(5,6));eq(nil,tie.link)
end)

test("hypothetical costs remain pure while aboard even when from is the landing bank",function()
    local s=setup();s.standard();s.edge(3,1,100)
    s.voyage={aboard=true,fromHash=SOUTH,toHash=NORTH,fromMap=2,toMap=3,cost=40}
    s.at(nil,"deck")
    eq(3,s.api.originForCost())
    eq(70,s.api.cost(4,1),"future reverse route from destination office")
    eq(50,s.api.cost(3,1),"future reverse route from landing bank")
    eq(0,s.api.cost(3,3),"future same-position cost")
    eq(60,s.api.costFromCurrent(4),"actual remaining voyage plus final road")
    eq(40,s.api.costFromCurrent(3),"actual voyage still required to reach landing bank")
end)

test("leg plans retain copied map commands after all later planning queries",function()
    local s=setup();s.standard()
    local plan=assert(s.api.plan(1,4))
    _G.speedWalkDir={"wrong"};_G.speedWalkPath={7};_G.speedWalkWeight={999}
    eq("road:1:2",plan.legs[1].plan.steps[1].cmd)
    eq(2,plan.legs[1].plan.steps[1].map)
    eq("road:3:4",plan.legs[3].plan.steps[1].cmd)
    eq(20,plan.legs[3].plan.steps[1].weight)
end)

test("same-position travel has zero cost and completes without a ferry",function()
    local s=setup()
    local plan=assert(s.api.plan(1,1));eq(0,plan.cost)
    s.synchronous=true
    local result,done=s.result();local cancel=s.api.idz(1,done)
    eq(true,result.value.ok);eq(1,result.calls)
    for _,run in ipairs(s.runs) do eq("road",run.kind) end
    cancel();eq(1,result.calls)
end)

test("composition executes road ferry road serially and validates the final location",function()
    local s=setup();s.standard()
    local result,done=s.result();s.api.idz(4,done)
    eq(1,#s.runs);eq("road",s.api.phase())
    s.complete(s.runs[1],true);eq(2,#s.runs);eq("ferry",s.runs[2].kind)
    s.complete(s.runs[2],true);eq(3,#s.runs);eq("road",s.runs[3].kind)
    s.complete(s.runs[3],true);eq(true,result.value.ok);eq(1,result.calls);eq(nil,s.api.phase())
end)

test("late callback from a finished leg cannot skip an active ferry or start later roads",function()
    local s=setup();s.standard()
    local result,done=s.result();local cancel=s.api.idz(4,done)
    local first=s.runs[1];s.complete(first,true)
    local boat=s.runs[2]
    first.done({ok=true});first.done({ok=false,reason="stale"})
    eq(2,#s.runs);eq(0,result.calls);eq("ferry",s.api.phase())
    cancel();eq(1,boat.cancelCalls);eq(false,result.value.ok);eq(1,result.calls)
end)

test("cancellation handles synchronous child cancellation and rejects stale later success",function()
    local s=setup();s.standard()
    local result,done=s.result();local cancel=s.api.idz(4,done)
    local first=s.runs[1];cancel();cancel();first.done({ok=true})
    eq(1,first.cancelCalls);eq(1,#s.runs);eq(false,result.value.ok);eq(1,result.calls)
end)

test("cancellation during a child's startup still cancels its returned handle",function()
    local s=setup();s.standard()
    s.onRun=function() s.cleanup() end
    local result,done=s.result();s.api.idz(4,done)
    eq(false,result.value.ok);eq(1,result.calls);eq(1,#s.runs);eq(1,s.runs[1].cancelCalls)
    s.runs[1].done({ok=true});eq(1,#s.runs)
end)

test("all-synchronous legs do not retain stale cancellation handles",function()
    local s=setup();s.standard();s.synchronous=true
    local result,done=s.result();local cancel=s.api.idz(4,done)
    eq(true,result.value.ok);eq(3,#s.runs);eq(1,result.calls)
    cancel()
    for _,run in ipairs(s.runs) do eq(0,run.cancelCalls) end
end)

test("pause after the first road but before ferry startup preserves the intended crossing",function()
    local s=setup();s.standard();s.edge(2,4,1)
    local result,done=s.result();local cancel=s.api.idz(4,done)
    s.onActivity=function(_,event) if event.phase=="ferry" then cancel() end end
    s.complete(s.runs[1],true)
    eq(false,result.value.ok);eq(1,#s.runs);eq(2,s.map)
    s.onActivity=nil
    eq(1,s.api.cost(2,4),"hypothetical planning ignores preserved intent")
    eq(60,s.api.costFromCurrent(4),"actual resume preserves intended crossing")
    local resumed,resumeDone=s.result();s.api.idz(4,resumeDone)
    eq("ferry",s.runs[2].kind);eq(SOUTH,s.runs[2].link.fromHash)
    s.complete(s.runs[2],true);s.complete(s.runs[3],true);eq(true,resumed.value.ok)
end)

test("successful ferry clears pending crossing before a stopped last road is resumed",function()
    local s=setup();s.standard();s.edge(3,2,1);s.edge(2,4,100)
    local result,done=s.result();local cancel=s.api.idz(4,done)
    s.complete(s.runs[1],true);s.complete(s.runs[2],true)
    eq(3,#s.runs);cancel();eq(false,result.value.ok)
    local resumed,resumeDone=s.result();s.api.idz(4,resumeDone)
    eq("road",s.runs[4].kind);eq(3,s.runs[4].plan.from);eq(4,s.runs[4].plan.target)
    s.complete(s.runs[4],true);eq(true,resumed.value.ok);eq(4,#s.runs)
end)

test("resume aboard only resumes the remembered voyage then takes the final road",function()
    local s=setup();s.standard()
    s.voyage={aboard=true,fromHash=SOUTH,toHash=NORTH,fromMap=2,toMap=3,cost=40};s.at(nil,"deck")
    local result,done=s.result();s.api.idz(4,done)
    eq("resume",s.runs[1].kind);eq(3,s.runs[1].toMap)
    s.complete(s.runs[1],true);eq("road",s.runs[2].kind);eq(3,s.runs[2].plan.from)
    s.complete(s.runs[2],true);eq(true,result.value.ok);eq(2,#s.runs)
end)

test("reaching the final room manually makes same-position resume zero despite old intent",function()
    local s=setup();s.standard();s.edge(4,2,5)
    local result,done=s.result();local cancel=s.api.idz(4,done);cancel()
    s.at(4)
    eq(0,s.api.cost(4,4))
    eq(0,s.api.costFromCurrent(4))
end)

test("a successful child result cannot hide a wrong final map hash",function()
    local s=setup();s.edge(1,5,8)
    local result,done=s.result();s.api.idz(5,done)
    s.at(5,"wrong_hash");s.runs[1].done({ok=true})
    eq(false,result.value.ok);eq(1,result.calls)
end)

test("reload rejects new journeys and every stale child callback",function()
    local s=setup();s.standard()
    local result,done=s.result();s.api.idz(4,done);s.cleanup()
    eq(false,result.value.ok);eq(1,s.runs[1].cancelCalls)
    s.runs[1].done({ok=true});eq(1,#s.runs)
    local rejected,nextDone=s.result();s.api.idz(4,nextDone);eq(false,rejected.value.ok);eq(1,#s.runs)
end)

test("explicit office adoption can discard an old uncompleted crossing intent",function()
    local s=setup();s.standard();local result,done=s.result()
    local cancel=s.api.idz(4,done);cancel()
    s.at(6);s.edge(6,2,10);s.edge(6,4,1)
    eq(70,s.api.costFromCurrent(4))
    s.api.clearIntent();eq(1,s.api.costFromCurrent(4))
end)
test("timing metrics distinguish ordinary steps and a real ferry from weighted route cost",function()
    local s=setup();s.standard()
    local value,metrics=s.api.quote(1,4,false)
    eq(70,value);eq(2,metrics.steps);eq(0,metrics.delayUnits);eq(1,metrics.ferries)
    eq(SOUTH..">"..NORTH,metrics.ferryKeys[1]);eq(0,metrics.fareCopper)
    eq(1,select("#",s.api.cost(1,4)),"legacy cost API returns exactly one value")
    eq(0,#s.runs);eq(0,#s.events)
end)
test("large ordinary route weights never become elapsed seconds or ferry counts",function()
    local s=setup();s.noFerry=true;s.edge(1,5,9000)
    local value,metrics=s.api.quote(1,5,false)
    eq(9000,value);eq(1,metrics.steps);eq(0,metrics.delayUnits);eq(0,metrics.ferries)
    local zero=assert(s.api.metrics(1,1,false))
    eq(0,zero.steps);eq(0,zero.delayUnits);eq(0,zero.ferries)
    eq(nil,s.api.metrics(1,7,false));eq(0,#s.runs)
end)
test("timing signatures remain stable across map number changes and separate ferry directions",function()
    local s=setup();s.standard()
    local forward=assert(s.api.metrics(1,4,false));local reverse=assert(s.api.metrics(4,1,false))
    assert(forward.signature~=reverse.signature)
    local a={legs={{kind="road",plan={fromId="a",targetId="b",from=1,target=2,steps={{cmd="n",id="b",map=2}}}}}}
    local b={legs={{kind="road",plan={fromId="a",targetId="b",from=101,target=202,steps={{cmd="n",id="b",map=202}}}}}}
    eq(assert(s.api.metricsForPlan(a)).signature,assert(s.api.metricsForPlan(b)).signature)
    eq(nil,s.api.metricsForPlan({legs={{kind="unknown"}}}))
end)
test("current timing honors a resumed ferry while hypothetical timing stays independent",function()
    local s=setup();s.standard();s.at(3);s.voyage={aboard=true,toHash=NORTH,toMap=3,cost=40}
    local actual=assert(s.api.metrics(3,4,true));local quote=assert(s.api.metrics(3,4,false))
    eq(1,actual.ferries);eq(SOUTH..">"..NORTH,actual.ferryKeys[1]);eq(0,quote.ferries)
    eq(1,actual.steps);eq(1,quote.steps);eq(0,#s.runs)
end)
print("JOURNEY "..passed.." passed, "..failed.." failed")
if failed>0 then error("journey regression failures: "..failed,0) end
