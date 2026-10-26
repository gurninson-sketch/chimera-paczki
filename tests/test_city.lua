-- Standalone city-boundary and ordinary-path tests; no live server required.
local script=(arg[0] or ""):gsub("\\","/")
local root=script:match("^(.*)/tests/test_city%.lua$") or "."
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/city.lua")
local passed,assertions=0,0
local function eq(expected,actual,why)
    assertions=assertions+1
    assert(expected==actual,(why or "value")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,fn)
    local ok,why=pcall(fn)
    if not ok then error(name..": "..tostring(why),0) end
    passed=passed+1
    print("OK "..name)
end
local function fixture(options)
    local s={hashes={},maps={},world={},exits={},weights={},exitWeights={},locks={},exitLocks={},blocked={}}
    for map=1,10 do
        local hash=string.format("%016x",map)
        s.hashes[map],s.maps[hash]=hash,map
        s.world[hash]={id=hash,name="Ulica "..map,area="Campogrotta",area_id="city-a",terrain="miasto"}
        s.weights[map]=10
    end
    s.world[s.hashes[4]].terrain="las"
    s.world[s.hashes[5]].area_id="city-b"
    s.world[s.hashes[5]].area="Inne miasto"
    s.world[s.hashes[6]]=nil
    s.world[s.hashes[9]].terrain="gory"
    s.world[s.hashes[10]].indoors=true
    s.exits={
        [1]={east=2,west=5,south=4,north=6,up=10},
        [2]={west=1,east=3}, [3]={west=2}, [4]={north=1},
        [5]={west=1,east=3}, [6]={south=1}, [7]={}, [8]={},
        [9]={}, [10]={down=1},
    }
    s.weights[5]=1
    _G.getRoomIDbyHash=function(hash) return s.maps[hash] or -1 end
    _G.getRoomExits=function(map)
        if s.throwExits==map then error("fixture exits failure") end
        return s.exits[map] or {}
    end
    _G.getRoomWeight=function(map) return s.weights[map] end
    _G.getExitWeights=function(map)
        if s.throwWeights==map then error("fixture weights failure") end
        return s.exitWeights[map] or {}
    end
    _G.roomLocked=function(map)
        if s.throwLock==map then error("fixture lock failure") end
        return s.locks[map]==true
    end
    _G.hasExitLock=function(map,command)
        if s.throwExitLock then error("fixture exit lock failure") end
        return s.exitLocks[tostring(map)..":"..command]==true
    end
    _G.getSpecialExitsSwap=function() error("city planner must never query special exits") end
    _G.getPath=function() error("city planner must never use global shortest route") end
    _G.speedWalkDir={"sentinel"}
    _G.speedWalkPath={99}
    local opts={world={room=function(hash)
        if s.throwWorld==hash then error("fixture world failure") end
        return s.world[hash]
    end},mapper={chimera_id=function(map) return s.hashes[map] end},blockRoom=function(map,hash)
        s.lastBlockHash=hash
        if s.throwBlock then error("fixture block failure") end
        return s.blocked[map]
    end}
    for key,value in pairs(options or {}) do opts[key]=value end
    s.api=create(opts)
    s.route={native=true,name="Torquato di Assemani",rooms={2,1},roomIds={[1]=s.hashes[1],[2]=s.hashes[2]}}
    s.scope=assert(s.api.scope(s.route))
    return s
end

test("scope uses the first priority-ordered verified city room",function()
    local s=fixture()
    eq("city-a",s.scope.areaId);eq(2,s.scope.anchorMap);eq(s.hashes[2],s.scope.anchorHash);eq("Campogrotta",s.scope.name)
end)
test("scope skips stale map hash and missing metadata",function()
    local s=fixture()
    s.route.rooms={6,3,1};s.route.roomIds[6]=s.hashes[6];s.route.roomIds[3]="wrong"
    eq(1,assert(s.api.scope(s.route)).anchorMap)
end)
test("scope does not invent a city from postal titles or area names",function()
    local s=fixture()
    s.route.postal=true
    eq(nil,s.api.scope(s.route))
    s.route.postal=false;s.route.rooms={4,6,9};s.route.roomIds[4]=s.hashes[4];s.route.roomIds[9]=s.hashes[9]
    eq(nil,s.api.scope(s.route))
end)
test("room enumeration follows only reachable ordinary city exits",function()
    local s=fixture()
    local rooms=assert(s.api.rooms(s.scope));local found={}
    for _,map in ipairs(rooms) do found[map]=true end
    eq(4,#rooms)
    for _,map in ipairs({1,2,3,10}) do eq(true,found[map]) end
    for _,map in ipairs({4,5,6,7,8,9}) do eq(nil,found[map]) end
end)
test("the cheap out-of-city shortcut cannot enter a local plan",function()
    local s=fixture()
    local plan=assert(s.api.plan(s.scope,1,3))
    eq(2,#plan.steps);eq(2,plan.steps[1].map);eq(3,plan.steps[2].map);eq(20,plan.cost)
    eq("sentinel",speedWalkDir[1]);eq(99,speedWalkPath[1])
end)
test("plans have the exact reply-driven road executor shape",function()
    local s=fixture();local p=assert(s.api.plan(s.scope,1,3))
    eq(1,p.from);eq(3,p.target);eq(s.hashes[1],p.fromId);eq(s.hashes[3],p.targetId)
    eq("e",p.steps[1].cmd);eq(s.hashes[2],p.steps[1].id);eq(10,p.steps[1].weight)
    eq("e",p.commands[2]);eq(3,p.rooms[2]);eq(10,p.weights[2])
end)
test("a zero-step plan remains within the validated city",function()
    local s=fixture();local p=assert(s.api.plan(s.scope,2,2))
    eq(0,#p.steps);eq(0,p.cost);eq(s.hashes[2],p.fromId)
    eq(nil,s.api.plan(s.scope,5,5))
end)
test("contains rejects other cities forests mountains and unknown rooms",function()
    local s=fixture()
    eq(true,s.api.contains(s.scope,1));eq(true,s.api.contains(s.scope,10))
    for _,map in ipairs({4,5,6,9}) do eq(false,s.api.contains(s.scope,map)) end
end)
test("room locks exclude search destinations and transit rooms",function()
    local s=fixture();s.locks[2]=true
    eq(false,s.api.contains(s.scope,2));eq(nil,s.api.plan(s.scope,1,3));eq(nil,s.api.rooms(s.scope))
end)
test("ordinary exit locks prevent traversal without trying specials",function()
    local s=fixture();s.exitLocks["1:e"]=true
    eq(nil,s.api.plan(s.scope,1,3))
end)
test("indoor and vertical city rooms remain eligible without guessing commands",function()
    local s=fixture();local p=assert(s.api.plan(s.scope,1,10))
    eq(1,#p.steps);eq("u",p.steps[1].cmd)
    local back=assert(s.api.plan(s.scope,10,1));eq("d",back.steps[1].cmd)
end)
test("an unmapped special-only room is not a reachable street",function()
    local s=fixture();s.exits[1].statek=8
    eq(nil,s.api.plan(s.scope,1,8))
end)
test("reverse map hash validation catches reused numeric map identifiers",function()
    local s=fixture();s.maps[s.hashes[3]]=7
    eq(false,s.api.contains(s.scope,3));eq(nil,s.api.plan(s.scope,1,3))
end)
test("world room identity contradictions fail closed",function()
    local s=fixture();s.world[s.hashes[3]].id=s.hashes[7]
    eq(false,s.api.contains(s.scope,3));eq(nil,s.api.plan(s.scope,1,3))
end)
test("forged or no-longer-city scopes are rejected",function()
    local s=fixture();local fake={areaId="city-b",anchorMap=2,anchorHash=s.hashes[2]}
    eq(false,s.api.contains(fake,5));eq(nil,s.api.rooms(fake))
    s.world[s.hashes[2]].terrain="gory"
    eq(false,s.api.contains(s.scope,1));eq(nil,s.api.plan(s.scope,1,3))
end)
test("hazard predicate filters rooms and receives their verified hashes",function()
    local s=fixture();s.blocked[3]="known hazard"
    eq(false,s.api.contains(s.scope,3));eq(nil,s.api.plan(s.scope,1,3));eq(s.hashes[3],s.lastBlockHash)
end)
test("throwing metadata lock and hazard providers do not authorize a route",function()
    local s=fixture();s.throwWorld=s.hashes[3];eq(false,s.api.contains(s.scope,3))
    s.throwWorld=nil;s.throwLock=3;eq(false,s.api.contains(s.scope,3))
    s.throwLock=nil;s.throwBlock=true;eq(nil,s.api.plan(s.scope,1,3))
end)
test("bounded enumeration returns no partial list",function()
    local s=fixture({maxNodes=2})
    local list,why=s.api.rooms(s.scope)
    eq(nil,list);eq(true,why:find("limit",1,true)~=nil)
    eq(nil,s.api.plan(s.scope,1,3))
end)
test("explicit exit weights can select a longer path inside the same city",function()
    local s=fixture()
    s.exits[1].up=10;s.exits[10].east=3
    s.exitWeights[1]={east=50,up=1};s.exitWeights[10]={east=1}
    local p=assert(s.api.plan(s.scope,1,3))
    eq(2,p.cost);eq(10,p.steps[1].map);eq("u",p.steps[1].cmd)
end)
test("invalid and nonfinite map weights cannot create a usable edge",function()
    local s=fixture();s.weights[2]=0/0
    eq(nil,s.api.plan(s.scope,1,3))
    s.weights[2]=10;s.exitWeights[1]={east=math.huge}
    eq(nil,s.api.plan(s.scope,1,3))
end)
test("read errors and unavailable map APIs fail without a global path fallback",function()
    local s=fixture();s.throwExits=1
    eq(nil,s.api.plan(s.scope,1,3))
    s.throwExits=nil;s.throwWeights=1;eq(nil,s.api.plan(s.scope,1,3))
    getRoomExits=nil;eq(nil,s.api.rooms(s.scope))
end)
test("returned plans and scopes do not change the map or route records",function()
    local s=fixture();local p=assert(s.api.plan(s.scope,1,3))
    p.steps[1].id="changed";p.commands[1]="statek"
    eq(s.hashes[2],assert(s.api.plan(s.scope,1,3)).steps[1].id)
    eq(2,s.route.rooms[1]);eq(s.hashes[1],s.route.roomIds[1]);eq(2,s.exits[1].east)
end)
test("an indoor starting point needs an ordinary connected urban witness",function()
    local s=fixture()
    for _,map in ipairs({7,8}) do s.world[s.hashes[map]].terrain=nil;s.world[s.hashes[map]].indoors=true end
    s.exits[8]={south=7};s.exits[7]={north=8,south=1};s.exits[1].north=7
    local scope=assert(s.api.scope({rooms={8},roomIds={[8]=s.hashes[8]}}))
    eq(8,scope.anchorMap);eq(1,scope.urbanMap);eq(s.hashes[1],scope.urbanHash)
    eq(true,s.api.contains(scope,7));eq(true,s.api.contains(scope,8))
    eq(2,#assert(s.api.plan(scope,8,1)).steps)
end)
test("an isolated room without terrain cannot establish a city",function()
    local s=fixture();s.world[s.hashes[8]].terrain=nil;s.world[s.hashes[8]].indoors=true
    eq(nil,s.api.scope({rooms={8},roomIds={[8]=s.hashes[8]}}))
    s.exits[8]={south=5};eq(nil,s.api.scope({rooms={8},roomIds={[8]=s.hashes[8]}}))
end)
test("an indoor city witness respects exit locks and explicit hazardous terrain",function()
    local s=fixture();s.world[s.hashes[8]].terrain=nil;s.world[s.hashes[8]].indoors=true;s.exits[8]={south=1}
    s.exitLocks["8:s"]=true
    eq(nil,s.api.scope({rooms={8},roomIds={[8]=s.hashes[8]}}))
    s.exitLocks["8:s"]=false;s.world[s.hashes[8]].terrain="gory"
    eq(nil,s.api.scope({rooms={8},roomIds={[8]=s.hashes[8]}}))
end)
test("unknown outdoor terrain stays outside a confirmed city search",function()
    local s=fixture();s.world[s.hashes[3]].terrain=nil;s.world[s.hashes[3]].indoors=false
    eq(false,s.api.contains(s.scope,3));eq(nil,s.api.plan(s.scope,1,3))
end)
test("the actual Campogrotta mayor hall and post office are searchable indoors",function()
    package.path=root.."/../chimera-main/src/?.lua;"..package.path
    local json=require("chimera.core.json")
    local file=assert(io.open(root.."/../chimera-main/data/world/fe3973d382c34894.json","rb"))
    local data=json.decode(file:read("*a"));file:close()
    local names={};for hash in pairs(data.rooms) do names[#names+1]=hash end;table.sort(names)
    local ids,maps={},{}
    for map,hash in ipairs(names) do ids[map]=hash;maps[hash]=map end
    local directions={polnoc="north",poludnie="south",wschod="east",zachod="west",
        ["polnocny-wschod"]="northeast",["polnocny-zachod"]="northwest",
        ["poludniowy-wschod"]="southeast",["poludniowy-zachod"]="southwest",gora="up",dol="down"}
    _G.getRoomIDbyHash=function(hash) return maps[hash] or -1 end
    _G.getRoomExits=function(map)
        local result={}
        for command,target in pairs(data.rooms[ids[map]].exits or {}) do
            if directions[command] and maps[target] then result[directions[command]]=maps[target] end
        end
        return result
    end
    _G.getRoomWeight=function() return 1 end
    _G.getExitWeights=function() return {} end
    _G.roomLocked=function() return false end
    _G.hasExitLock=function() return false end
    local planner=create({world={room=function(hash)
        local source=data.rooms[hash]
        if not source then return nil end
        return {id=hash,name=source.name,area=data.area,area_id=data.area_id,terrain=source.terrain,indoors=source.indoors}
    end},mapper={chimera_id=function(map) return ids[map] end}})
    local hall,post=maps["755fb333d9e85eb7"],maps["269ff0c7899bbd55"]
    local scope=assert(planner.scope({rooms={hall},roomIds={[hall]=ids[hall]}}))
    eq("fe3973d382c34894",scope.areaId);eq(hall,scope.anchorMap)
    eq(true,planner.contains(scope,post))
    eq(true,#assert(planner.plan(scope,hall,post)).steps>0)
    local knownIndoor=0
    for hash,row in pairs(data.rooms) do
        if row.terrain==nil and row.indoors==true then
            knownIndoor=knownIndoor+1;eq(true,planner.contains(scope,maps[hash]),row.name)
        end
    end
    eq(11,knownIndoor)
    eq(false,planner.contains(scope,maps["f753eddde69aa823"]),"outdoor bakery lacks city terrain")
end)

print(string.format("CITY: %d scenarios, %d assertions passed",passed,assertions))
