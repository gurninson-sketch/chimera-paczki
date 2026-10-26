-- Cooperative quotation planning; host calls are counted, not timed against
-- machine-dependent thresholds. Run from chimera-native with texlua.
package.path="chimera_wtyczki/?.lua;"..package.path
local createRoad=require("chimera_paczki.road")
local createPath=require("chimera_paczki.path")
local createJourney=require("chimera_paczki.journey")
local cases,checks=0,0
local function ok(value,why) checks=checks+1;assert(value,why or "condition failed") end
local function eq(wanted,actual,why) ok(wanted==actual,(why or "value")..": expected "..tostring(wanted)..", got "..tostring(actual)) end
local function test(name,fn) fn();cases=cases+1;print("PASS "..name) end
local function fixture(count)
    local s={rooms={},hashes={},names={},nativeCalls=0,reads=0,gateCalls=0,sends=0,checkpoints=0,
        yields=0,heartbeats=0,worker=nil,cache=nil,maxUnits=0,units=0}
    for i=1,count do
        s.rooms[i]={exits={},specials={},weight=1,weights={},locks={},specialLocks={}}
        s.hashes[i]="h"..i
        if i<count then s.rooms[i].exits.east=i+1 end
        if i>1 then s.rooms[i].exits.west=i-1 end
    end
    _G.getRoomExits=function(i) s.reads=s.reads+1;return s.rooms[i].exits end
    _G.getSpecialExitsSwap=function(i) return s.rooms[i].specials end
    _G.getRoomWeight=function(i) return s.rooms[i].weight end
    _G.getExitWeights=function(i) return s.rooms[i].weights end
    _G.roomLocked=function(i) return s.rooms[i].locked==true end
    _G.hasExitLock=function(i,direction) return s.rooms[i].locks[direction]==true end
    _G.hasSpecialExitLock=function(i,to,command) return s.rooms[i].specialLocks[to..":"..command]==true end
    _G.getRoomName=function(i) return s.names[i] or "Ulica" end
    _G.getRoomArea=function() return 1 end
    _G.getRoomAreaName=function() return "Miasto testowe" end
    _G.getPath=function(from,to)
        s.nativeCalls=s.nativeCalls+1
        if from==to then speedWalkDir={};speedWalkPath={};speedWalkWeight={}
        else speedWalkDir={"e"};speedWalkPath={to};speedWalkWeight={7} end
        return true
    end
    _G.speedWalkDir={"original"};_G.speedWalkPath={987};_G.speedWalkWeight={321}
    local ctx={}
    function ctx:on() return {} end
    function ctx:trigger() return {} end
    function ctx:cleanup() return {} end
    function ctx:emit() end
    local function managed() return s.worker~=nil and coroutine.running()==s.worker end
    local opts={
        gmcp={room=function() return {id=s.hashes[1]} end},
        mapper={current_room=function() return 1 end,chimera_id=function(i) return s.hashes[i] end},
        locations={gate=function() s.gateCalls=s.gateCalls+1;return nil end},
        send=function() s.sends=s.sends+1 end,
        planning=managed,planningCache=function() return managed() and s.cache or nil end,
        cooperate=function()
            if not managed() then return false end
            s.checkpoints=s.checkpoints+1;s.units=s.units+1
            if s.units>=128 then
                s.maxUnits=math.max(s.maxUnits,s.units);s.units=0;s.yields=s.yields+1
                coroutine.yield("planning")
            end
            return true
        end,
    }
    s.ctx,s.opts=ctx,opts;s.road=createRoad(ctx,opts)
    function s.run(fn)
        s.cache={};s.units=0;s.worker=coroutine.create(fn)
        local results
        while coroutine.status(s.worker)~="dead" do
            local values={coroutine.resume(s.worker)}
            ok(values[1],values[2])
            if coroutine.status(s.worker)=="dead" then results={values[2],values[3]}
            else eq("planning",values[2]);s.heartbeats=s.heartbeats+1 end
        end
        s.maxUnits=math.max(s.maxUnits,s.units);s.worker=nil;s.cache=nil
        return results[1],results[2]
    end
    return s
end

test("large quotations yield within bounded work and never enter native getPath",function()
    local s=fixture(2000)
    local plan=s.run(function() return s.road.plan(1,2000) end)
    eq(1999,#plan.steps);eq(1999,plan.cost);eq(0,s.nativeCalls)
    ok(s.heartbeats>50,"a large graph must give the event loop repeated turns")
    ok(s.maxUnits<=128);eq(s.yields,s.heartbeats);eq(0,s.sends)
    eq("original",speedWalkDir[1]);eq(987,speedWalkPath[1]);eq(321,speedWalkWeight[1])
end)

test("actual nonmanaged navigation retains the native preferred route",function()
    local s=fixture(6);local plan=s.road.plan(1,6)
    eq(1,s.nativeCalls);eq(1,#plan.steps);eq(7,plan.cost);eq(0,s.checkpoints)
end)

test("one planning task reuses successful pairs without exposing mutable cache plans",function()
    local s=fixture(20)
    s.run(function()
        local first=s.road.plan(1,20);local reads=s.reads
        first.steps[1].cmd="mutated";first.commands[1]="mutated";first.cost=987
        local second=s.road.plan(1,20)
        eq(reads,s.reads);eq("e",second.steps[1].cmd);eq("e",second.commands[1]);eq(19,second.cost)
        second.steps[1].map=987;eq(2,s.road.plan(1,20).steps[1].map)
    end)
end)

test("failed pairs are memoized only for the current planning task",function()
    local s=fixture(20);s.rooms[10].exits.east=nil
    s.run(function()
        local plan,why=s.road.plan(1,20);eq(nil,plan);ok(type(why)=="string")
        local reads=s.reads;eq(nil,s.road.plan(1,20));eq(reads,s.reads)
    end)
    s.rooms[10].exits.east=11
    eq(19,s.run(function() return s.road.plan(1,20) end).cost)
end)

test("new planning tasks observe changed weights locks and room hash identity",function()
    local s=fixture(5)
    eq(4,s.run(function() return s.road.plan(1,5) end).cost)
    s.rooms[3].weight=9
    eq(12,s.run(function() return s.road.plan(1,5) end).cost)
    s.rooms[2].locks.e=true
    eq(nil,s.run(function() return s.road.plan(1,5) end))
    s.rooms[2].locks.e=false
    s.run(function()
        local first=s.road.plan(1,5);eq("h5",first.targetId)
        s.hashes[5]="remapped";local second=s.road.plan(1,5);eq("remapped",second.targetId)
    end)
end)

test("temporary quotations are never reused by actual navigation",function()
    local s=fixture(20)
    eq(19,s.run(function() return s.road.plan(1,20) end).cost)
    local plan=s.road.plan(1,20);eq(7,plan.cost);eq(1,s.nativeCalls);eq(1,#plan.steps)
end)

test("unrelated callbacks while a worker is suspended use no worker cache or checkpoints",function()
    local s=fixture(200);s.cache={};s.worker=coroutine.create(function() return s.road.plan(1,200) end)
    local resumed,why=coroutine.resume(s.worker);ok(resumed,why);eq("suspended",coroutine.status(s.worker))
    local checksBefore=s.checkpoints
    local plan=s.road.plan(1,200);eq(1,s.nativeCalls);eq(7,plan.cost);eq(checksBefore,s.checkpoints)
    -- Drop the cancelled coroutine: no timers, commands or partial route escape.
    s.worker=nil;s.cache=nil;eq(0,s.sends)
end)

test("constrained quotations preserve hazards locks weights and unsupported-command filtering",function()
    local s=fixture(5)
    for _,room in pairs(s.rooms) do room.exits={} end
    s.rooms[1].exits.east=2;s.rooms[2].exits.east=3;s.rooms[3].exits.east=5
    s.names[3]="Gory Szare"
    s.rooms[1].specials["wespnij sie na gore"]=5
    s.rooms[1].exits.north=4;s.rooms[4].exits.east=5;s.rooms[4].weight=2;s.rooms[4].weights.e=7
    local plan=s.run(function() return s.road.plan(1,5) end)
    eq("n e",table.concat(plan.commands," "));eq(9,plan.cost)
    s.rooms[1].locks.n=true;eq(nil,s.run(function() return s.road.plan(1,5) end))
    eq(0,s.nativeCalls)
end)

test("a search checks each blocked destination once rather than once per incoming edge",function()
    local s=fixture(100);local blockedCalls={}
    local path=createPath({hash=s.opts.mapper.chimera_id,cooperate=s.opts.cooperate,
        blockedRoom=function(i) blockedCalls[i]=(blockedCalls[i] or 0)+1;return false end})
    local plan=s.run(function() return path.find(1,100) end);eq(99,plan.cost)
    for _,count in pairs(blockedCalls) do eq(1,count) end
end)

test("gate metadata SQL-style lookups are memoized inside one quote task only",function()
    local s=fixture(20)
    s.run(function()
        local plan=s.road.plan(1,20)
        local first=s.road.metrics(plan);eq(19,first.steps)
        local calls=s.gateCalls;eq(20,calls)
        eq(first.signature,s.road.metrics(plan).signature);eq(calls,s.gateCalls)
    end)
    s.road.metrics(s.road.plan(1,20));ok(s.gateCalls>20)
end)

local function journeyFixture()
    local s=fixture(5);s.hashes={ [1]="local-source",[2]="local-target",[3]="894039a1680ca034",[4]="20016d960316ba51",[5]="unused" }
    local map={};for i,id in pairs(s.hashes) do map[id]=i end
    _G.getRoomIDbyHash=function(id) return map[id] or -1 end
    s.plans={};s.costs={["1:2"]=4,["1:3"]=10,["4:2"]=12}
    local road={plan=function(from,to)
        s.plans[#s.plans+1]={from=from,to=to}
        local cost=from==to and 0 or s.costs[from..":"..to]
        if cost==nil then return nil,"unreachable" end
        return {from=from,target=to,fromId=s.hashes[from],targetId=s.hashes[to],cost=cost,
            steps=from==to and {} or {{cmd="e",id=s.hashes[to],map=to,weight=cost}}}
    end}
    local ferry={catalogue=function() return {{fromHash=s.hashes[3],toHash=s.hashes[4],cost=40},
        {fromHash=s.hashes[4],toHash=s.hashes[3],cost=40}} end,state=function() return nil end}
    s.opts.road,s.opts.ferry=road,ferry;s.journey=createJourney(s.ctx,s.opts)
    return s,map
end

test("a cheap complete local route prunes ferry-bank searches with a higher lower bound",function()
    local s=journeyFixture()
    local cost,metrics=s.run(function() return s.journey.quote(1,2) end)
    eq(4,cost);eq(0,metrics.ferries);eq(1,#s.plans);eq(1,s.plans[1].from);eq(2,s.plans[1].to)
end)

test("the Nuln Quenelles crossing remains forced even when a cheaper direct road exists",function()
    local s,map=journeyFixture()
    s.hashes[1]="6f2c03461c2f1438";s.hashes[2]="e202c7893bf8fb55"
    map[s.hashes[1]],map[s.hashes[2]]=1,2
    local plan=s.run(function() return s.journey.plan(1,2,true,true) end)
    eq(62,plan.cost);eq("ferry",plan.legs[2].kind)
    eq("894039a1680ca034",plan.legs[2].link.fromHash);eq("20016d960316ba51",plan.legs[2].link.toHash)
    eq(3,#s.plans)
end)

test("an already expensive first ferry leg prunes the remote landing-leg search",function()
    local s=journeyFixture();s.costs["1:2"]=100;s.costs["1:3"]=80
    local cost=s.run(function() return s.journey.quote(1,2) end)
    eq(100,cost)
    for _,query in ipairs(s.plans) do
        ok(not (query.from==4 and query.to==2),"an impossible-to-improve crossing searched the distant landing road")
    end
    eq(3,#s.plans)
end)

print(string.format("PLANNING_PATH: %d scenarios, %d assertions passed",cases,checks))
