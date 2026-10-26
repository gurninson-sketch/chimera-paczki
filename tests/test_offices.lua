-- Standalone Lua 5.1-compatible tests.
local script=arg[0]:gsub("\\","/")
local root=script:match("^(.*)/tests/test_offices%.lua$") or "."
package.path=root.."/chimera_wtyczki/?.lua;"..package.path
local create=dofile(root.."/chimera_wtyczki/chimera_paczki/offices.lua")
local tests,checks=0,0
local function check(ok,message) checks=checks+1;assert(ok,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local NULN="6f2c03461c2f1438"
local KZ="907327356ecc2f87"
local BISSINGEN="200aff4d957642cd"
local UBERSREIK="54fa7e4634a30c23"
local function fresh(config)
    local e={time=1000,maps={[NULN]=1,[KZ]=2,[BISSINGEN]=3,[UBERSREIK]=4},costs={},calls={},
        current={map=1,id=NULN,name="Poczta"}}
    _G.getRoomIDbyHash=function(id) return e.maps[id] end
    local navigator={
        current=function() return e.current end,
        safeCost=function(from,to)
            e.calls[#e.calls+1]={from=from,to=to}
            return e.costs[from..":"..to]
        end,
        cost=function() error("safeCost must take precedence over unfiltered cost") end,
    }
    local ctx={send=function() error("selector must never send commands") end,
        timer=function() error("selector must never create timers") end}
    local api=create(ctx,navigator,config,function() return e.time end)
    function e:path(from,to,outward,back)
        self.costs[from..":"..to]=outward;self.costs[to..":"..from]=back
    end
    return api,e,navigator
end

test("catalogue has only exact office rooms and returns independent copies",function()
    local o,e=fresh();local catalogue=o.catalogue();eq(#catalogue,24)
    local seen={}
    for _,room in ipairs(catalogue) do
        check(type(room.id)=="string" and #room.id==16);check(not seen[room.id]);seen[room.id]=true
        check(not room.name:find("Przedsionek",1,true));check(not room.name:find("Przed ",1,true));check(not room.name:find("Plac ",1,true))
        check(room.city~=nil)
    end
    check(seen[NULN]);check(seen[KZ]);check(seen[BISSINGEN])
    catalogue[1].name="corrupted";eq(o.catalog()[1].name,"Poczta")
end)
test("nearest safe one-way office wins even when its round trip is longer",function()
    local o,e=fresh();e:path(1,2,10,100);e:path(1,3,12,1)
    local candidates,why=o.candidates(e.current)
    eq(why,nil);eq(#candidates,2);eq(candidates[1].id,KZ);eq(candidates[2].id,BISSINGEN)
    eq(candidates[1].cost,10);eq(candidates[1].returnCost,100);eq(candidates[1].roundTripCost,110)
    eq(candidates[1].staticNuln,false);eq(candidates[1].name,"Glowna sala poczty w Krainie Zgromadzenia")
    eq(o.next().id,KZ);eq(e.current.id,NULN,"candidate selection cannot move or change the source")
end)
test("unmapped offices and invalid map IDs never become destinations",function()
    local o,e=fresh();e:path(1,2,5,5);e:path(1,3,2,2)
    e.maps[KZ]=-1;e.maps[BISSINGEN]="3";e.maps[UBERSREIK]=0
    local choices,reason=o.candidates();eq(#choices,0);check(reason~=nil);eq(#e.calls,0)
    e.maps[KZ]=2.5;eq(o.next(),nil)
    e.maps[KZ]=2;eq(o.next().id,KZ)
end)
test("each candidate requires both safe outbound and safe return paths",function()
    local o,e=fresh();e:path(1,2,10,nil);e:path(1,3,nil,4);e:path(1,4,7,8)
    local candidates=o.candidates();eq(#candidates,1);eq(candidates[1].id,UBERSREIK)
    e.costs["4:1"]=math.huge;eq(o.next(),nil)
    e.costs["4:1"]=-1;eq(o.next(),nil)
    e.costs["4:1"]=0/0;eq(o.next(),nil)
    e.costs["4:1"]=0;eq(o.next().id,UBERSREIK,"zero safe cost is valid")
end)
test("current office and visited hashes or map IDs are excluded",function()
    local o,e=fresh();e:path(1,2,10,10);e:path(1,3,12,12)
    e.maps[UBERSREIK]=1
    local candidates=o.candidates(nil,{[KZ]=true,[3]=true});eq(#candidates,0)
    candidates=o.candidates(nil,{[KZ]=true});eq(#candidates,1);eq(candidates[1].id,BISSINGEN)
    candidates=o.candidates(nil,{[3]=true});eq(#candidates,1);eq(candidates[1].id,KZ)
end)
test("empty-office cooldown prevents ping-pong and expires after 600 seconds",function()
    local o,e=fresh();e:path(1,2,10,10);e:path(1,3,12,12);e:path(2,3,4,4)
    check(o.markEmpty(e.current));eq(o.remaining(NULN),600)
    e.current={map=2,id=KZ,name="Glowna sala poczty w Krainie Zgromadzenia"}
    check(o.markEmpty(e.current));eq(o.next().id,BISSINGEN)
    e.current={map=3,id=BISSINGEN,name="Poczta"};check(o.markEmpty(e.current))
    eq(o.next(),nil,"recent empty offices cannot lead straight back to the previous office")
    e.time=1599;eq(o.remaining(KZ),1);eq(o.next(),nil)
    e.time=1600;eq(o.remaining(KZ),0);eq(o.next().id,KZ)
end)
test("clear one source and clearAll reset only their intended cooldown state",function()
    local o,e=fresh();e:path(1,2,10,10);e:path(1,3,12,12)
    o.markEmpty(KZ);o.markEmpty(BISSINGEN);eq(o.next(),nil)
    o.clear(KZ);eq(o.remaining(KZ),0);eq(o.remaining(BISSINGEN),600);eq(o.next().id,KZ)
    o.markEmpty(KZ);o.clearAll();eq(o.remaining(KZ),0);eq(o.remaining(BISSINGEN),0)
    o.markEmpty(KZ);o.clear();eq(o.remaining(KZ),0)
end)
test("cooldown and optional relocation limit obey the live configuration",function()
    local config={officeCooldown=60,maxOfficeCost=11};local o,e=fresh(config)
    e:path(1,2,10,100);e:path(1,3,12,1)
    local candidates=o.candidates();eq(#candidates,1);eq(candidates[1].id,KZ)
    o.markEmpty(KZ);eq(o.remaining(KZ),60);eq(o.next(),nil)
    config.maxOfficeCost=12;eq(o.next().id,BISSINGEN)
    config.officeCooldown=120;o.markEmpty(BISSINGEN);eq(o.remaining(BISSINGEN),120)
    e.time=1060;eq(o.next().id,KZ)
end)
test("unknown position or unavailable safe routing produces a reason without movement",function()
    local o,e,navigator=fresh();e.current={map=0,id=NULN,name="Poczta"}
    local choices,reason=o.candidates();eq(#choices,0);check(reason~=nil);eq(#e.calls,0)
    e.current={map=1,id="",name="Poczta"};eq(o.next(),nil)
    e.current={map=1,id=NULN,name="Poczta"};navigator.safeCost=nil;navigator.cost=nil
    choices,reason=o.candidates();eq(#choices,0);check(reason~=nil);eq(#e.calls,0)
    eq(o.markEmpty({}),false)
end)
test("cost alias and exceptions are handled without leaking partial candidates",function()
    local o,e,navigator=fresh();e:path(1,2,10,10)
    navigator.cost=navigator.safeCost;navigator.safeCost=nil
    eq(o.next().id,KZ)
    navigator.cost=function() error("map unavailable") end
    eq(o.next(),nil)
    _G.getRoomIDbyHash=function() error("map disappeared") end
    eq(o.next(),nil)
end)
test("selection is deterministic for equal costs and does not share result records",function()
    local o,e=fresh();e:path(1,2,10,10);e:path(1,3,10,10)
    local first=o.next();eq(first.id,BISSINGEN,"equal costs sort by stable room hash")
    first.name="corrupted";first.id="wrong"
    local again=o.next();eq(again.id,BISSINGEN);eq(again.name,"Poczta")
    e.current={map=2,id=KZ,name="Glowna sala poczty w Krainie Zgromadzenia"}
    local nuln=o.next();eq(nuln.id,NULN);eq(nuln.staticNuln,true)
end)
test("manual city choice uses the actual position instead of the old issuing office",function()
    local o,e=fresh();e:path(1,3,5,5);e:path(4,3,30,31)
    local oldSource=e.current
    e.current={map=4,id=UBERSREIK,name="Poczta Ubersreik"}
    local route,reason=o.resolve(" BISSINGEN ",oldSource)
    eq(reason,nil);eq(route.id,BISSINGEN);eq(route.map,3);eq(route.city,"Bissingen")
    eq(route.cost,30);eq(route.returnCost,31);eq(route.roundTripCost,61)
    eq(route.staticNuln,false);eq(e.calls[1].from,4);eq(e.calls[1].to,3)
    eq(e.current.id,UBERSREIK);eq(oldSource.id,NULN)
end)
test("explicit city and full names ignore empty cooldown without clearing it",function()
    local o,e=fresh({maxOfficeCost=1});e:path(1,2,10,11)
    o.markEmpty(KZ);eq(o.remaining(KZ),600);eq(o.next(),nil)
    local route=o.resolve("kraina zgromadzenia");eq(route.id,KZ);eq(route.cost,10)
    route=o.resolve(" GŁÓWNA  SALA POCZTY W KRAINIE ZGROMADZENIA. ")
    eq(route.id,KZ);eq(o.remaining(KZ),600);eq(o.next(),nil)
end)
test("generic office names are ambiguous even if only one is mapped",function()
    local o,e=fresh();e.maps[KZ]=nil;e.maps[BISSINGEN]=nil;e.maps[UBERSREIK]=nil
    local route,reason=o.resolve("Poczta")
    eq(route,nil);check(reason:find("niejednoznaczna",1,true)~=nil);check(reason:find("Nuln",1,true)~=nil)
    eq(#e.calls,0)
    route,reason=o.resolve("Urząd pocztowy")
    eq(route,nil);check(reason:find("niejednoznaczna",1,true)~=nil);eq(#e.calls,0)
end)
test("manual selection supports an exact folded full name and stable room hash",function()
    local o,e=fresh();e:path(1,4,9,10)
    local route=o.resolve("Poczta Ubersreik");eq(route.id,UBERSREIK)
    route=o.resolve(UBERSREIK:upper());eq(route.id,UBERSREIK);eq(route.name,"Poczta Ubersreik")
    route.name="corrupted";eq(o.resolve("Ubersreik").name,"Poczta Ubersreik")
end)
test("unmapped and one-way manual destinations return a reason",function()
    local o,e=fresh();e:path(1,2,10,nil)
    local route,reason=o.resolve("Kraina Zgromadzenia")
    eq(route,nil);check(reason~=nil)
    e:path(1,2,nil,10);eq(o.resolve("Kraina Zgromadzenia"),nil)
    e.maps[KZ]=nil;route,reason=o.resolve("Kraina Zgromadzenia")
    eq(route,nil);check(reason:find("mapie",1,true)~=nil)
    e.maps[KZ]=-2;eq(o.resolve("Kraina Zgromadzenia"),nil)
end)
test("manual choice of the current office succeeds with zero cost",function()
    local o,e=fresh();o.markEmpty(NULN)
    local route,reason=o.resolve("Nuln")
    eq(reason,nil);eq(route.id,NULN);eq(route.map,1);eq(route.staticNuln,true)
    eq(route.cost,0);eq(route.returnCost,0);eq(#e.calls,0);eq(o.remaining(NULN),600)
    e.current={map=3,id=BISSINGEN,name="Poczta"}
    route=o.resolve("Bissingen");eq(route.id,BISSINGEN);eq(route.cost,0);eq(route.staticNuln,false)
end)
test("manual lookup cannot fall back to a stale source when current position is unavailable",function()
    local o,e,navigator=fresh();e:path(1,2,10,10);local oldSource=e.current
    navigator.current=function() return nil end
    local route,reason=o.resolve("Kraina Zgromadzenia",oldSource)
    eq(route,nil);check(reason:find("aktualnej pozycji",1,true)~=nil);eq(#e.calls,0)
    navigator.current=function() error("mapper unavailable") end
    eq(o.resolve("Kraina Zgromadzenia",oldSource),nil)
    navigator.current=nil
    route=o.resolve("Kraina Zgromadzenia",oldSource);eq(route.id,KZ)
end)
test("manual lookup rejects inconsistent hashes, unknown names and empty input",function()
    local o,e=fresh()
    eq(o.resolve(""),nil);eq(o.resolve(nil),nil);eq(o.resolve("Nieznane Miasto"),nil)
    e.maps[BISSINGEN]=1;eq(o.resolve("Bissingen"),nil,"different hashes cannot be the same current map room")
    e.maps[NULN]=99;eq(o.resolve("Nuln"),nil,"same current hash cannot point to another map room")
end)
test("manual office choice shares the ten newly observed postal aliases",function()
    local cases={
        {"Urzad pocztowy w Nuln",NULN},{"Poczta wolnego miasta Nuln",NULN},
        {"Poczta w Urbimo","0a647e20ca6f97f7"},{"Urzad pocztowy w Urbimo","0a647e20ca6f97f7"},
        {"Urzad pocztowy w Varieno","78c41b4fab38b2b5"},{"Poczta miasteczka Varieno","78c41b4fab38b2b5"},
        {"Poczta w Karak Varn","c55c2924e506dd7f"},{"Urzad pocztowy Karak-Varn","c55c2924e506dd7f"},
        {"Poczta w Kreutzhoffen","315106e45b840273"},{"Urzad pocztowy w Crimmor","381bc4bb1fc81f0a"},
    }
    for _,pair in ipairs(cases) do
        local o,e=fresh();e.current={map=2,id=KZ,name="Glowna sala poczty w Krainie Zgromadzenia"}
        e.maps[pair[2]]=10;e:path(2,10,5,6)
        local office=assert(o.resolve(pair[1]));eq(office.id,pair[2]);eq(office.map,10)
        eq(office.cost,5);eq(office.returnCost,6)
        e.costs["10:2"]=nil;eq(o.resolve(pair[1]),nil)
    end
end)

test("Karak Varn has one working choice and the broken nearby office is never an automatic destination",function()
    local o,e=fresh();local working,broken="c55c2924e506dd7f","3de8d58adb6dbe9b"
    e.maps[working]=10;e.maps[broken]=11;e:path(1,10,5,5);e:path(1,11,1,1)
    local candidates=o.candidates();eq(1,#candidates);eq(working,candidates[1].id)
    eq("Karak Varn",candidates[1].city);eq(nil,o.resolve(broken))
    for _,label in ipairs({"Karak Varn","Karak-Varn","Krolestwa Krasnoludow","Krolestwach Krasnoludow",
        "Urzad pocztowy Karak-Varn"}) do eq(working,assert(o.resolve(label),label).id) end
    e.current={map=10,id=working,name="Poczta"};e:path(10,11,1,1)
    local nextOffice=assert(o.next())
    check(nextOffice.id~=broken,"empty working counter cannot redirect to the broken legacy room")
    eq(NULN,nextOffice.id,"the next genuinely working office remains available")
end)

print(string.format("Office selector: %d tests, %d assertions passed",tests,checks))
