-- Pure Lua 5.1-compatible durable intent and character isolation tests.
local create=dofile("chimera_wtyczki/chimera_paczki/checkpoint.lua")
local tests,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function clone(value)
    if type(value)~="table" then return value end
    local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out
end
local function source()
    return {id="OFFICE-HASH",name="Poczta",city="Nuln",staticNuln=true,map=123}
end
local function state()
    return {source=source(),job={name="Rolph Ederson",recipientConfirmed=true,delivered=false,coinsPending=false,source=source()},
        flags={},stats={delivered=2,gold=1,silver=5,copper=3,started=900},stopAt=7,
        inventory={state="hands",coinsUncertain=false}}
end
local function setup(saved)
    local e={time=1000,saves=0}
    local api=create(saved,{now=function() if e.clockError then error("clock failed") end;return e.time end,
        save=function(snapshot)
            e.saves=e.saves+1
            if e.fail=="throw" then error("save failed") end
            if e.fail then return false end
            e.saved=snapshot
        end})
    return api,e
end

test("confirmed parcel intent is saved as stable hashes and metadata",function()
    local c,e=setup();eq(c.put("ActorA",state()),true);eq(c.count(),1);eq(e.saved.schema,1)
    local s=c.get("ACTORA")
    eq(s.source.id,"office-hash");eq(s.source.name,"Poczta");eq(s.source.city,"Nuln");eq(s.source.staticNuln,true)
    eq(s.source.map,nil);eq(s.job.source.map,nil);eq(s.job.name,"Rolph Ederson")
    eq(s.job.recipientConfirmed,true);eq(s.job.delivered,false);eq(s.job.coinsPending,false)
    eq(s.stats.delivered,2);eq(s.stats.gold,1);eq(s.stats.silver,5);eq(s.stats.copper,3);eq(s.stats.started,900)
    eq(s.stopAt,7);eq(s.savedAt,1000);eq(s.inventory.state,"hands")
end)
test("character B never overwrites the pending course of character A",function()
    local c,e=setup();local a,b=state(),state()
    b.job.name="Johan Kornwalz";b.source.id="second-office";b.stats.delivered=9
    eq(c.put("ActorA",a),true);e.time=1010;eq(c.put("ActorB",b),true);eq(c.count(),2)
    eq(c.get("actora").job.name,"Rolph Ederson");eq(c.get("actorb").job.name,"Johan Kornwalz")
    eq(c.get("actora").stats.delivered,2);eq(c.get("actorb").savedAt,1010)
    local restored=create(e.saved);eq(restored.count(),2)
    eq(restored.get("actora").job.name,"Rolph Ederson");eq(restored.get("actorb").source.id,"second-office")
    eq(c.forget("ActorB"),true);eq(c.count(),1);eq(c.get("ActorA").job.name,"Rolph Ederson")
end)
test("all uncertain transaction flags survive without turning into a success",function()
    local c,e=setup();local s={selectedName="Rolph Ederson",pendingManualSource=source(),flags={}}
    for _,field in ipairs({"awaitingPickup","awaitingDelivery","awaitingReturn","awaitingReward","manualPickup","manualDelivery"}) do s.flags[field]=true end
    eq(c.put("ActorA",s),true);local restored=create(e.saved).get("ActorA")
    for field in pairs(s.flags) do eq(restored.flags[field],true) end
    eq(restored.job,nil);eq(restored.selectedName,"Rolph Ederson");eq(restored.pendingManualSource.id,"office-hash")
    eq(restored.pendingManualSource.map,nil)
end)
test("delivered parcel with uncertain reward or coin storage keeps the reconciliation markers",function()
    local c=setup();local s=state();s.job.delivered=true;s.job.coinsPending=true;s.flags.awaitingReward=true
    s.inventory.coinsUncertain=true
    eq(c.put("ActorA",s),true);s=c.get("ActorA")
    eq(s.job.delivered,true);eq(s.job.coinsPending,true);eq(s.flags.awaitingReward,true);eq(s.inventory.coinsUncertain,true)
end)
test("manual relocation retains only the destination hash and manual intent",function()
    local c=setup();local s={relocation={to={id="OTHER-HASH",name="Urzad pocztowy",city="Varieno",map=456,staticNuln=false},manual=true,
        from=source(),route={commands={"n"}}},source=source()}
    eq(c.put("ActorA",s),true);s=c.get("ActorA")
    eq(s.relocation.to.id,"other-hash");eq(s.relocation.to.map,nil);eq(s.relocation.manual,true)
    eq(s.relocation.from,nil);eq(s.relocation.route,nil)
end)
test("confirmed bag location retains the validated container description",function()
    local c,e=setup();local s=state()
    s.inventory={state="bag",coinsUncertain=true,container={b="swoj plecak",d="swojego plecaka",name="skorzany plecak",detected=true,
        open="otworz swoj plecak",close="zamknij swoj plecak",containerWord="plecaka",openWord="plecak",move="take anything",map=123}}
    eq(c.put("ActorA",s),true);local bag=create(e.saved).get("ActorA").inventory
    eq(bag.state,"bag");eq(bag.coinsUncertain,true);eq(bag.container.d,"swojego plecaka")
    eq(bag.container.b,"swoj plecak");eq(bag.container.name,"skorzany plecak");eq(bag.container.detected,true)
    eq(bag.container.open,"otworz swoj plecak");eq(bag.container.close,"zamknij swoj plecak")
    eq(bag.container.move,nil);eq(bag.container.map,nil)
end)
test("d-only bag metadata is valid when automatic open and close are disabled",function()
    local c=setup();local s=state()
    s.inventory={state="bag",container={d="swojego plecaka",containerWord="plecaka"},coinsUncertain=false}
    eq(c.put("ActorA",s),true);s=c.get("ActorA")
    eq(s.inventory.container.d,"swojego plecaka");eq(s.inventory.container.b,nil);eq(s.inventory.container.open,nil)
    s.inventory={state="unknown",coinsUncertain=true};eq(c.put("ActorA",s),true)
    eq(c.get("ActorA").inventory.state,"unknown","never guess that a parcel is in hand")
    eq(c.get("ActorA").inventory.coinsUncertain,true)
end)
test("credentials, runtime callbacks and numeric map IDs are never serialized",function()
    local c,e=setup();local s=state();local cycle={};cycle.self=cycle
    s.account="account";s.login="login";s.password="password";s.actor="untrusted";s.mode="running";s.phase="outbound"
    s.node="home/n";s.timers={1,2};s.callback=function() end;s.cycle=cycle
    s.job.actor="player";s.job.route={native=true,target=50,commands={"n"},callback=function() end};s.job.coinReceipt=99
    s.source.password="secret";s.inventory.pending={command="send"};s.inventory.coinReceipt=77
    eq(c.put("ActorA",s),true);local stored=e.saved.actors.actora
    for _,field in ipairs({"account","login","password","actor","mode","phase","node","timers","callback","cycle"}) do eq(stored[field],nil) end
    eq(stored.job.actor,nil);eq(stored.job.route,nil);eq(stored.job.coinReceipt,nil)
    eq(stored.source.password,nil);eq(stored.inventory.pending,nil);eq(stored.inventory.coinReceipt,nil)
end)
test("put, get and persistence expose independent deep copies",function()
    local c,e=setup();local input=state();eq(c.put("ActorA",input),true)
    input.job.name="mutated";input.source.id="mutated"
    local output=c.get("ActorA");output.job.source.id="bad";output.flags.awaitingPickup=true;output.stats.gold=999
    e.saved.actors.actora.job.name="saved mutation"
    local again=c.get("ActorA")
    eq(again.job.name,"Rolph Ederson");eq(again.source.id,"office-hash");eq(again.job.source.id,"office-hash")
    eq(again.flags.awaitingPickup,false);eq(again.stats.gold,1)
end)
test("save failures keep each actor's previous checkpoint atomic",function()
    local c,e=setup();eq(c.put("ActorA",state()),true)
    for _,failure in ipairs({true,"throw"}) do
        e.fail=failure;local replacement=state();replacement.job.name="Johan Kornwalz"
        eq(c.put("ActorA",replacement),false);eq(c.get("ActorA").job.name,"Rolph Ederson")
        eq(c.put("ActorB",replacement),false);eq(c.get("ActorB"),nil);eq(c.count(),1)
        eq(c.forget("ActorA"),false);eq(c.count(),1)
    end
    e.fail=false;eq(c.forget("ActorA"),true);eq(c.count(),0);eq(next(e.saved.actors),nil)
end)
test("malformed recognized fields cannot erase uncertainty or replace a valid checkpoint",function()
    local c,e=setup();eq(c.put("ActorA",state()),true)
    local malformed={
        {source={map=123}}, {job={name=""}}, {job={name="Rolph",delivered="yes"}},
        {relocation={to={map=123}}}, {flags={awaitingPickup=1}}, {flags="unsafe"},
        {pendingManualSource={id=false}}, {selectedName=""}, {stopAt=-1},
        {inventory={state="maybe"}}, {inventory={state="unknown",coinsUncertain="yes"}},
        {inventory={state="hands",container={d="plecaka"}}}, {inventory={state="bag",container={name="plecak"}}},
        {inventory={state="bag",container={d="plecaka; wyrzuc paczke"}}},
        {inventory={state="bag",container={d="plecaka",open="otworz inny plecak"}}},
    }
    for _,invalid in ipairs(malformed) do
        local ok,why=c.put("ActorA",invalid);eq(ok,false);check(type(why)=="string")
        eq(c.get("ActorA").job.name,"Rolph Ederson")
    end
    eq(e.saves,1)
end)
test("only finite nonnegative counters, timestamps and integral limits are accepted",function()
    local c,e=setup()
    for _,bad in ipairs({-1,1.5,math.huge,0/0,"2",false}) do
        eq(c.put("ActorA",{stats={gold=bad}}),false)
        eq(c.put("ActorA",{stopAt=bad}),false)
    end
    eq(c.put("ActorA",{stats={delivered=0,gold=0,silver=0,copper=0,started=0},stopAt=0}),true)
    eq(c.get("ActorA").stats.gold,0);eq(c.get("ActorA").stopAt,0)
    eq(e.saves,1)
end)
test("unsupported schemas and malformed loaded actors are ignored",function()
    local c,e=setup();c.put("ActorA",state());local valid=clone(e.saved)
    valid.actors["ActorB"]=clone(valid.actors.actora)
    valid.actors.bad={flags={awaitingDelivery="false"}}
    valid.actors["witaj, actor. podaj haslo"]={}
    local loaded=create(valid);eq(loaded.count(),1);eq(loaded.get("ActorA").job.name,"Rolph Ederson")
    valid.actors.actora.job.name="mutated";eq(loaded.get("ActorA").job.name,"Rolph Ederson")
    valid.schema=2;eq(create(valid).count(),0)
    eq(create({actors={actora={}}}).count(),0);eq(create({schema=1,actors="invalid"}).count(),0)
    eq(create(nil).count(),0)
end)
test("GMCP canonical names are normalized without parsing login prompts or emails",function()
    local c=setup();eq(c.put(" ŻÓŁW ",{}),true);eq(c.get("zolw").savedAt~=nil,true);eq(c.count(),1)
    for _,bad in ipairs({"", " \n ", "Witaj, Actor. Podaj haslo do konta:", "account@example.com", "password: secret", 42, false}) do
        eq(c.put(bad,{}),false);eq(c.get(bad),nil)
    end
    eq(c.count(),1);eq(c.put(nil,{}),false);eq(c.put("ActorA",nil),false)
end)
test("forget is explicit, character-specific and independent of the clock",function()
    local c,e=setup();c.put("ActorA",state());c.put("ActorB",state())
    eq(c.put("ActorA",nil),false);eq(c.count(),2);eq(c.forget("missing"),false)
    e.clockError=true;eq(c.forget("ActorA"),true);eq(c.get("ActorA"),nil)
    eq(c.get("ActorB").job.name,"Rolph Ederson");eq(c.count(),1)
end)
test("bad clock results never commit a new snapshot",function()
    local c,e=setup();e.clockError=true;eq(c.put("ActorA",state()),false)
    e.clockError=false;e.time=-1;eq(c.put("ActorA",state()),false)
    e.time=math.huge;eq(c.put("ActorA",state()),false)
    e.time=0/0;eq(c.put("ActorA",state()),false)
    eq(c.count(),0);eq(e.saves,0)
end)

print(string.format("Durable checkpoint: %d tests, %d assertions passed",tests,checks))
