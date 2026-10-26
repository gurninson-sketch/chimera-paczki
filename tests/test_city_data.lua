-- Public fallback metadata tests, including actual Campogrotta without world.db.
local script=(arg[0] or ""):gsub("\\","/")
local root=script:match("^(.*)/tests/test_city_data%.lua$") or "."
package.path=root.."/chimera_wtyczki/?.lua;"..root.."/../chimera-main/src/?.lua;"..package.path
local data=require("chimera_paczki.city_data")
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/city.lua")
local json=require("chimera.core.json")
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
local function load(path)
    local file=assert(io.open(path,"rb"));local body=file:read("*a");file:close()
    return json.decode(body)
end
local CITY="fe3973d382c34894"
local HALL="755fb333d9e85eb7"
local POST="269ff0c7899bbd55"
local FORGE="b86129bbefdb9e71"
local SHOP="ff91072fd68491f6"
local BAKERY="f753eddde69aa823"
local UNKNOWN="00000000000000ff"
local AREA_IDS={"052674af116ac2e6","0c70f2167e2c74e2","0f095c768720281b",
    "23d0d595ee4fcc8d","30e665204659df05","39d40f5504ec7fa7","4e203aefad89b03b",
    "56f68103bafb1946","56fd26cb768fdf83","76c7e10797bf83b1","79e3f5f1a804e304",
    "8c49134bba75ff43","ab4f5f7889d23391","b96cb35a938e6b50","ba3ed3b47ecafd6e",
    "d5befad697ca3ddd","d7c30a089031f5e0","d8d738b548619ef5","dc340302666dd1ac",
    "f5febaeda5ea2f68","fe3973d382c34894"}
local camp=load(root.."/../chimera-501/data/world/"..CITY..".json")
local function fixture(worldMode)
    local s={ids={},maps={},overrides={},locks={},exitLocks={}}
    local names={};for hash in pairs(camp.rooms) do names[#names+1]=hash end;table.sort(names)
    for map,hash in ipairs(names) do s.ids[map]=hash;s.maps[hash]=map end
    local directions={polnoc="north",poludnie="south",wschod="east",zachod="west",
        ["polnocny-wschod"]="northeast",["polnocny-zachod"]="northwest",
        ["poludniowy-wschod"]="southeast",["poludniowy-zachod"]="southwest",gora="up",dol="down"}
    _G.getRoomIDbyHash=function(hash) return s.maps[hash] or -1 end
    _G.getRoomExits=function(map)
        local out={}
        for command,target in pairs((camp.rooms[s.ids[map]] or {}).exits or {}) do
            if directions[command] and s.maps[target] then out[directions[command]]=s.maps[target] end
        end
        if s.extra and s.extra[map] then for command,target in pairs(s.extra[map]) do out[command]=target end end
        return out
    end
    _G.getRoomWeight=function() return 1 end
    _G.getExitWeights=function() return {} end
    _G.roomLocked=function(map) return s.locks[map]==true end
    _G.hasExitLock=function(map,command) return s.exitLocks[map..":"..command]==true end
    _G.getSpecialExitsSwap=function() error("no special exit inspection") end
    _G.getRoomUserData=function() error("profile area metadata must not be used") end
    _G.getRoomArea=function() error("profile numeric area must not be used") end
    _G.getRoomEnv=function() error("profile colour must not be used") end
    _G.getCustomEnvColorTable=function() error("profile colours must not be used") end
    local world
    if worldMode~="missing" then
        world={room=function(hash)
            if s.throw==hash then error("world service read error") end
            if s.overrides[hash]~=nil then return s.overrides[hash] end
            if worldMode=="full" then
                local row=camp.rooms[hash]
                if row then return {id=hash,area_id=CITY,area=camp.area,terrain=row.terrain,indoors=row.indoors} end
            end
            return nil
        end}
    end
    s.api=create({world=world,mapper={chimera_id=function(map) return s.ids[map] end}})
    function s.route(hash)
        local map=s.maps[hash]
        return {native=true,name="Torquato di Assemani",rooms={map},roomIds={[map]=hash}}
    end
    s.scope=assert(s.api.scope(s.route(HALL)))
    return s
end

test("registry provenance names exact public release and commit",function()
    local info=data.info()
    eq("1.5.9",info.version);eq("5.0.1",info.tag)
    eq("4f7cb4922310adc65c929e63f837dfd542d94a0e",info.commit)
    eq(21,info.areas);eq(2127,info.rooms)
end)
test("lookup returns only fresh allowlisted public room metadata",function()
    local room=assert(data.room(POST))
    eq(POST,room.id);eq(CITY,room.area_id);eq("Campogrotta",room.area);eq(nil,room.terrain);eq(true,room.indoors)
    local fields={id=true,area_id=true,area=true,terrain=true,indoors=true}
    for key in pairs(room) do eq(true,fields[key],key) end
    room.area_id="forged";room.terrain="gory";room.character="secret"
    eq(CITY,data.room(POST).area_id);eq(nil,data.room(POST).terrain);eq(nil,data.room(POST).character)
    local info=data.info();info.rooms=0;eq(2127,data.info().rooms)
end)
test("hash lookup does not guess names or accept unknown and excluded hashes",function()
    eq(nil,data.room("Poczta w Campogrotta"));eq(nil,data.room(UNKNOWN));eq(nil,data.room(nil))
    eq(nil,data.room(POST:upper()));eq(nil,data.room(BAKERY));eq(nil,data.room({id=POST}))
end)
test("empty world service uses bundled city metadata",function()
    local s=fixture("empty")
    eq("bundled",s.scope.metadataSource);eq(CITY,s.scope.areaId);eq(s.maps[HALL],s.scope.anchorMap)
    eq(true,s.api.contains(s.scope,s.maps[POST]))
end)
test("missing world service also permits the same confirmed city",function()
    local s=fixture("missing")
    eq("bundled",s.scope.metadataSource)
    eq(true,#assert(s.api.plan(s.scope,s.maps[HALL],s.maps[POST])).steps>0)
end)
test("actual empty-world Campogrotta enumeration includes all 55 eligible rooms",function()
    local s=fixture("empty");local list=assert(s.api.rooms(s.scope));local found={}
    for _,map in ipairs(list) do found[s.ids[map]]=true end
    eq(55,#list);eq(true,found[HALL]);eq(true,found[POST]);eq(true,found[FORGE]);eq(true,found[SHOP]);eq(nil,found[BAKERY])
end)
test("Kuznia to Niewielki sklepik is planned entirely within Campogrotta",function()
    local s=fixture("empty");local plan=assert(s.api.plan(s.scope,s.maps[FORGE],s.maps[SHOP]))
    eq(2,#plan.steps);eq("e",plan.steps[1].cmd);eq("se",plan.steps[2].cmd)
    for _,step in ipairs(plan.steps) do eq(CITY,data.room(step.id).area_id) end
    eq(SHOP,plan.targetId)
end)
test("all current world records remain preferred over the public fallback",function()
    local s=fixture("full")
    eq("world",s.scope.metadataSource)
    eq(55,#assert(s.api.rooms(s.scope)))
end)
test("a current world forest or mountain overrides a bundled eligible room",function()
    local s=fixture("empty")
    s.overrides[SHOP]={id=SHOP,area_id=CITY,area="Campogrotta",terrain="las",indoors=false}
    eq(false,s.api.contains(s.scope,s.maps[SHOP]));eq(nil,s.api.plan(s.scope,s.maps[FORGE],s.maps[SHOP]))
    s.overrides[SHOP].terrain="gory";eq(false,s.api.contains(s.scope,s.maps[SHOP]))
end)
test("current wrong identity or city area is rejected without fallback",function()
    local s=fixture("empty")
    s.overrides[SHOP]={id=POST,area_id=CITY,terrain="miasto",indoors=true}
    eq(false,s.api.contains(s.scope,s.maps[SHOP]))
    s.overrides[SHOP]={id=SHOP,area_id="another-area",terrain="miasto",indoors=true}
    eq(false,s.api.contains(s.scope,s.maps[SHOP]));eq(nil,s.api.plan(s.scope,s.maps[FORGE],s.maps[SHOP]))
end)
test("a malformed explicit world record and world read errors fail closed",function()
    local s=fixture("empty");s.overrides[SHOP]=false
    eq(false,s.api.contains(s.scope,s.maps[SHOP]))
    s.overrides[SHOP]=nil;s.throw=SHOP
    eq(false,s.api.contains(s.scope,s.maps[SHOP]));eq(nil,s.api.plan(s.scope,s.maps[FORGE],s.maps[SHOP]))
end)
test("mixed current indoor anchor and bundled urban witness are diagnosed",function()
    local s=fixture("empty")
    s.overrides[HALL]={id=HALL,area_id=CITY,area="Campogrotta",indoors=true}
    local scope=assert(s.api.scope(s.route(HALL)))
    eq("mixed",scope.metadataSource);eq(CITY,scope.areaId)
end)
test("profile colours user data and numeric areas cannot enlarge the city",function()
    local s=fixture("empty")
    local otherHash="00000000000000aa"
    s.ids[57]=otherHash;s.maps[otherHash]=57
    s.extra={[s.maps[FORGE]]={west=57}}
    eq(false,s.api.contains(s.scope,57));eq(nil,s.api.plan(s.scope,s.maps[FORGE],57))
    eq(55,#assert(s.api.rooms(s.scope)))
end)
test("fallback still rejects locked exits rooms and stale map hash bindings",function()
    local s=fixture("empty");s.locks[s.maps[SHOP]]=true
    eq(false,s.api.contains(s.scope,s.maps[SHOP]));eq(nil,s.api.plan(s.scope,s.maps[FORGE],s.maps[SHOP]))
    s.locks[s.maps[SHOP]]=false;s.maps[SHOP]=999
    eq(false,s.api.contains(s.scope,assert((function()for map,hash in pairs(s.ids)do if hash==SHOP then return map end end end)())))
end)
test("public registry exactly matches all eligible release 5.0.1 hashes",function()
    local areas,count=0,0
    for _,areaId in ipairs(AREA_IDS) do
        local area=load(root.."/../chimera-501/data/world/"..areaId..".json");local urban=false
        for _,row in pairs(area.rooms) do if row.terrain=="miasto" then urban=true;break end end
        if urban then
            areas=areas+1
            for hash,row in pairs(area.rooms) do
                local expected=row.terrain=="miasto" or (row.terrain==nil and row.indoors==true)
                local actual=data.room(hash)
                if expected then
                    count=count+1;assert(actual,hash)
                    eq(area.area_id,actual.area_id);eq(area.area,actual.area);eq(row.terrain,actual.terrain);eq(row.indoors==true,actual.indoors)
                else eq(nil,actual,hash) end
            end
        end
    end
    eq(21,areas);eq(2127,count)
end)
test("the same public fallback metadata is valid on beta.13",function()
    local count=0
    for _,areaId in ipairs(AREA_IDS) do
        local area=load(root.."/../chimera-main/data/world/"..areaId..".json");local urban=false
        for _,row in pairs(area.rooms) do if row.terrain=="miasto" then urban=true;break end end
        if urban then for hash,row in pairs(area.rooms) do
            if row.terrain=="miasto" or (row.terrain==nil and row.indoors==true) then
                local actual=assert(data.room(hash));count=count+1
                eq(area.area_id,actual.area_id);eq(row.terrain,actual.terrain);eq(row.indoors==true,actual.indoors)
            end
        end end
    end
    eq(2127,count)
end)

print(string.format("CITY_DATA: %d scenarios, %d assertions passed",passed,assertions))
