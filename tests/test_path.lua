-- Pure Lua 5.1-compatible tests for the read-only constrained map fallback.
local create=dofile("chimera_wtyczki/chimera_paczki/path.lua")
local tests,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function clone(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out
end
local function same(a,b)
    if type(a)~=type(b) then return false end
    if type(a)~="table" then return a==b end
    for key,value in pairs(a) do if not same(value,b[key]) then return false end end
    for key in pairs(b) do if a[key]==nil then return false end end
    return true
end
local function setup(extra)
    local s={rooms={},hashes={},lockCalls={},specialCalls={},getPathCalls=0}
    function s.room(id,weight)
        s.rooms[id]={exits={},specials={},weight=weight or 1,weights={},locked=false,locks={},specialLocks={}}
        s.hashes[id]="room-"..id
        return s.rooms[id]
    end
    _G.getRoomExits=function(id) return s.rooms[id] and s.rooms[id].exits or {} end
    _G.getSpecialExitsSwap=function(id) return s.rooms[id] and s.rooms[id].specials or {} end
    _G.getRoomWeight=function(id) return s.rooms[id] and s.rooms[id].weight end
    _G.getExitWeights=function(id) return s.rooms[id] and s.rooms[id].weights or {} end
    _G.roomLocked=function(id) return not s.rooms[id] or s.rooms[id].locked==true end
    _G.hasExitLock=function(id,direction)
        s.lockCalls[#s.lockCalls+1]={from=id,direction=direction}
        return s.rooms[id].locks[direction]==true
    end
    _G.hasSpecialExitLock=function(from,to,command)
        s.specialCalls[#s.specialCalls+1]={from=from,to=to,command=command}
        return s.rooms[from].specialLocks[to.."|"..command]==true
    end
    _G.getPath=function() s.getPathCalls=s.getPathCalls+1;error("fallback must never call or mutate getPath") end
    _G.speedWalkDir={"wespnij sie na gore"};_G.speedWalkPath={999};_G.speedWalkWeight={1}
    local opts={hash=function(id) return s.hashes[id] end,blocked=function(command)
        if command:match("^wespnij") or command:match("^wspin") or command:match("^plyn") or command:match("^skacz") or
            command:match("^skocz") or command:find("statek",1,true) then return "unsupported" end
    end}
    for key,value in pairs(extra or {}) do opts[key]=value end
    s.opts=opts;s.api=create(opts)
    return s
end

test("longer ordinary weighted route bypasses a cheaper climbing shortcut",function()
    local s=setup();s.room(1).specials["wespnij sie na gore"]=4
    s.room(2,2);s.room(3,3);s.room(4,4)
    s.rooms[1].exits.east=2;s.rooms[2].exits.north=3;s.rooms[3].exits.up=4
    local p,why=s.api.find(1,4)
    eq(why,nil);eq(p.cost,9);eq(p.from,1);eq(p.target,4);eq(p.fromId,"room-1");eq(p.targetId,"room-4")
    eq(table.concat(p.commands," "),"e n u");eq(#p.steps,3)
    for i=1,3 do eq(p.steps[i].map,i+1);eq(p.steps[i].id,"room-"..(i+1));eq(p.steps[i].weight,i+1);eq(p.weights[i],i+1) end
    eq(s.getPathCalls,0)
end)
test("normal u and d and all ordinary direction aliases stay available",function()
    local s=setup();for i=1,6 do s.room(i) end
    s.rooms[1].exits.up=2;s.rooms[2].exits.down=3;s.rooms[3].exits["in"]=4
    s.rooms[4].exits.out=5;s.rooms[5].exits.northeast=6
    local p=s.api.find(1,6);eq(table.concat(p.commands," "),"u d in out ne");eq(p.cost,5)
    local seen={};for _,call in ipairs(s.lockCalls) do seen[call.direction]=true end
    check(seen.up);check(seen.down);check(seen["in"]);check(seen.out);check(seen.ne)
end)
test("positive exit weights override destination weights for ordinary and special exits",function()
    local s=setup();s.room(1);s.room(2,3);s.room(4,999)
    s.rooms[1].exits.east=4;s.rooms[1].weights.e=50
    s.rooms[1].exits.north=2;s.rooms[2].specials.wyjscie=4;s.rooms[2].weights.wyjscie=4
    local p=s.api.find(1,4);eq(p.cost,7);eq(table.concat(p.commands," "),"n wyjscie")
    eq(p.weights[1],3);eq(p.weights[2],4)
    eq(s.specialCalls[1].from,2);eq(s.specialCalls[1].to,4);eq(s.specialCalls[1].command,"wyjscie")
end)
test("zero exit weight inherits the destination room weight",function()
    local s=setup();s.room(1);s.room(2,5);s.room(3,7)
    s.rooms[1].specials.schody=2;s.rooms[1].weights.schody=0
    s.rooms[2].exits.up=3;s.rooms[2].weights.up=0
    local p=s.api.find(1,3);eq(p.cost,12);eq(p.weights[1],5);eq(p.weights[2],7)
end)
test("ordinary exit locks are respected without changing them",function()
    local s=setup();for i=1,4 do s.room(i) end
    s.rooms[1].exits.east=4;s.rooms[1].locks.e=true
    s.rooms[1].exits.north=2;s.rooms[2].exits.east=4
    local p=s.api.find(1,4);eq(table.concat(p.commands," "),"n e");eq(p.cost,2);eq(s.rooms[1].locks.e,true)
    s.rooms[1].locks.n=true;eq(s.api.find(1,4),nil)
end)
test("special exit locks use the exact from-to-command identity",function()
    local s=setup();s.room(1);s.room(2);s.room(4)
    s.rooms[1].specials.drzwi=4;s.rooms[1].specialLocks["4|drzwi"]=true
    s.rooms[1].exits.north=2;s.rooms[2].specials.wejscie=4
    local p=s.api.find(1,4);eq(table.concat(p.commands," "),"n wejscie")
    eq(s.specialCalls[1].from,1);eq(s.specialCalls[1].to,4);eq(s.specialCalls[1].command,"drzwi")
    eq(s.rooms[1].specialLocks["4|drzwi"],true)
end)
test("locked intermediate rooms and locked destinations cannot be used",function()
    local s=setup();s.room(1).exits.east=2;s.room(2).exits.east=3;s.room(3)
    s.rooms[2].locked=true;eq(s.api.find(1,3),nil)
    s.rooms[2].locked=false;s.rooms[3].locked=true;local p,why=s.api.find(1,3)
    eq(p,nil);check(why:find("zablokowany",1,true)~=nil)
    s.rooms[3].locked=false;s.rooms[1].locked=true;eq(s.api.find(1,3),nil)
    p=s.api.find(1,1);eq(p.cost,0);eq(#p.steps,0,"already being in a room needs no passage")
end)
test("missing optional lock APIs and exit weights retain legacy stub compatibility",function()
    local s=setup();s.room(1).exits.east=2;s.room(2,4)
    _G.roomLocked=nil;_G.hasExitLock=nil;_G.hasSpecialExitLock=nil;_G.getExitWeights=nil
    local p=s.api.find(1,2);eq(p.cost,4);eq(p.commands[1],"e")
end)
test("existing lock APIs that fail or return unknown cannot open a route",function()
    local s=setup();s.room(1).exits.east=2;s.room(2)
    _G.hasExitLock=function() return nil end;eq(s.api.find(1,2),nil)
    _G.hasExitLock=function() error("lock lookup failed") end;eq(s.api.find(1,2),nil)
    _G.roomLocked=function() return nil end;eq(s.api.find(1,2),nil)
end)
test("missing hashes and nonfinite or negative edge weights are excluded",function()
    local s=setup();s.room(1).exits.east=2;s.room(2).exits.east=3;s.room(3)
    s.hashes[2]=nil;eq(s.api.find(1,3),nil)
    s.hashes[2]="room-2"
    for _,weight in ipairs({math.huge,-1,0/0,"2"}) do s.rooms[2].weight=weight;eq(s.api.find(1,3),nil) end
    s.rooms[2].weight=1;s.rooms[1].weights.e=math.huge;eq(s.api.find(1,3),nil)
    s.rooms[1].weights.e=-1;eq(s.api.find(1,3),nil)
    s.rooms[1].weights.e=2;s.rooms[2].weight=math.huge
    eq(s.api.find(1,3).cost,3,"a valid explicit edge weight is the cost actually used")
    s.hashes[3]=nil;eq(s.api.find(1,3),nil)
end)
test("no alternative never produces a guessed direct route",function()
    local s=setup();s.room(1).specials["wespnij sie na gore"]=2;s.room(2)
    local p,why=s.api.find(1,2);eq(p,nil);check(type(why)=="string")
    s.rooms[1].specials={ ["wsiadz na statek"]=2 };eq(s.api.find(1,2),nil)
    s.rooms[1].specials={ ["plyn na polnoc"]=2 };eq(s.api.find(1,2),nil)
    s.rooms[1].specials={ ["skocz na druga strone"]=2 };eq(s.api.find(1,2),nil)
end)
test("transport shortcuts are skipped while an ordinary detour remains available",function()
    local s=setup();s.room(1).specials["wsiadz na statek"]=3;s.room(2,2);s.room(3,2)
    s.rooms[1].exits.north=2;s.rooms[2].specials.wyjscie=3
    local p=s.api.find(1,3);eq(p.cost,4);eq(table.concat(p.commands," "),"n wyjscie")
end)
test("zero-weight cycles and stale heap entries do not break weighted shortest paths",function()
    local s=setup();for i=1,4 do s.room(i,0) end
    s.rooms[1].exits.east=2;s.rooms[1].weights.e=100
    s.rooms[1].exits.north=3;s.rooms[1].weights.n=1
    s.rooms[3].exits.east=2;s.rooms[3].weights.e=1
    s.rooms[2].exits.north=4;s.rooms[2].weights.n=1
    s.rooms[3].exits.north=4;s.rooms[3].weights.n=30
    s.rooms[2].exits.west=1
    local p=s.api.find(1,4);eq(p.cost,3);eq(table.concat(p.commands," "),"n e n")
    s.rooms[1].weights={};s.rooms[2].weights={};s.rooms[3].weights={}
    p=s.api.find(1,4);eq(p.cost,0);check(#p.steps>0 and #p.steps<=3)
end)
test("search budgets fail explicitly before returning a partial plan",function()
    local s=setup({maxNodes=2});for i=1,4 do s.room(i) end
    s.rooms[1].exits.north=2;s.rooms[1].exits.east=3;s.rooms[2].exits.east=4
    local p,why=s.api.find(1,4);eq(p,nil);check(why:find("limit pokoi",1,true)~=nil)
    s=setup({maxEdges=1});for i=1,4 do s.room(i) end
    s.rooms[1].exits.north=2;s.rooms[1].exits.east=3;s.rooms[2].exits.east=4
    p,why=s.api.find(1,4);eq(p,nil);check(why:find("limit krawedzi",1,true)~=nil)
end)
test("query never mutates the live graph or existing speedWalk globals",function()
    local s=setup();s.room(1).specials["wespnij sie na gore"]=3;s.room(2,2);s.room(3,3)
    s.rooms[1].exits.east=2;s.rooms[2].exits.north=3;s.rooms[1].locks.w=true
    local original,dirs,path,weights=clone(s.rooms),speedWalkDir,speedWalkPath,speedWalkWeight
    local p=s.api.find(1,3);eq(p.cost,5);check(same(s.rooms,original))
    eq(speedWalkDir,dirs);eq(speedWalkPath,path);eq(speedWalkWeight,weights)
    eq(speedWalkDir[1],"wespnij sie na gore");eq(speedWalkPath[1],999);eq(speedWalkWeight[1],1);eq(s.getPathCalls,0)
    p.commands[1]="mutated";p.steps[1].map=999
    eq(s.api.find(1,3).commands[1],"e");check(same(s.rooms,original))
end)
test("API failures and invalid inputs return a reason without leaking exceptions",function()
    local s=setup();s.room(1).exits.east=2;s.room(2)
    eq(s.api.find(0,2),nil);eq(s.api.find(1,"2"),nil);eq(s.api.find(1,1.5),nil)
    _G.getExitWeights=function() error("map unavailable") end
    local p,why=s.api.find(1,2);eq(p,nil);check(why:find("wag wyjsc",1,true)~=nil)
    _G.getRoomExits=nil;p,why=s.api.find(1,2);eq(p,nil);check(why:find("API mapy",1,true)~=nil)
end)

test("blocked wilderness cannot be reintroduced through ordinary or special fallback edges",function()
    local s=setup({blockedRoom=function(id) return id==2 and "Gory Szare" or nil end})
    for i=1,5 do s.room(i) end
    s.rooms[1].exits.northwest=2;s.rooms[2].exits.north=5;s.rooms[1].specials.skrot=2
    s.rooms[1].exits.east=3;s.rooms[3].exits.up=4;s.rooms[4].exits.east=5
    local p,why=s.api.find(1,5);eq(why,nil);eq(table.concat(p.commands," "),"e u e");eq(p.cost,3)
    for _,step in ipairs(p.steps) do check(step.map~=2) end
    eq(s.rooms[1].exits.northwest,2);eq(s.rooms[1].specials.skrot,2)
end)
test("unsafe destination and a route with no wilderness-free alternative are refused",function()
    local s=setup({blockedRoom=function(id) return id==2 and "Gory Szare" or nil end})
    s.room(1).exits.north=2;s.room(2).exits.east=3;s.room(3)
    local p,why=s.api.find(1,2);eq(p,nil);check(why:find("niebezpieczny",1,true));eq(s.api.find(1,3),nil)
    eq(s.api.find(2,2).cost,0,"remaining still does not enter a dangerous room")
end)
test("a failing wilderness check cannot open a route",function()
    local s=setup({blockedRoom=function() error("missing metadata") end})
    s.room(1).exits.north=2;s.room(2);eq(s.api.find(1,2),nil)
end)

print(string.format("Constrained path: %d tests, %d assertions passed",tests,checks))
