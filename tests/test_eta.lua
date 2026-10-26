-- Pure model regressions: seconds are derived from safe route metrics,
-- never from weighted path cost, and only completed confirmed cycles teach.
local create=dofile("chimera_wtyczki/chimera_paczki/eta.lua")
local tests,checks=0,0
local function check(value,message) checks=checks+1;assert(value,message or "check failed") end
local function eq(a,b,message) check(a==b,(message or "different values")..": "..tostring(a).." ~= "..tostring(b)) end
local function near(a,b,message) check(math.abs(a-b)<0.000001,(message or "not near")..": "..tostring(a).." ~= "..tostring(b)) end
local function test(name,fn) fn();tests=tests+1;print("PASS "..name) end
local function clone(value) if type(value)~="table" then return value end;local out={};for key,item in pairs(value) do out[key]=clone(item) end;return out end
local function query()
    return {actor="Yarrim",sourceId="907327356ecc2f87",recipient="Johan Kornwalz",postal=false,periodic=false,
        delay=1.5,timing={steps=20,delays=18,gates=0,ferries=0}}
end
local function proof()
    local q=query();q.seconds=100;q.delaySeconds=27
    q.verified=true;q.handover=true;q.reward=true;q.completed=true
    return q
end
local function setup(saved,defaults)
    local e={now=1000,saves=0}
    e.api=create(saved,{now=function() if e.clockError then error("clock failed") end;return e.now end,
        save=function(state) e.saves=e.saves+1;if e.fail=="throw" then error("save failed") end;if e.fail then return false end;e.saved=state end,
        defaults=defaults})
    return e.api,e
end

test("unknown route is a labelled seconds estimate, independent of weighted map cost",function()
    local m,e=setup();local q=query();q.route={cost=40};q.cost=1000000
    local eta=m.estimate(q)
    near(eta.seconds,42);eq(eta.method,"estimate");eq(eta.samples,0);eq(eta.confidence,"low")
    near(eta.breakdown.movement,7);near(eta.breakdown.pace,27);near(eta.breakdown.handling,8)
    q.cost=0;q.route.cost=1;near(m.estimate(q).seconds,42);eq(e.saves,0)
end)
test("explicit route components include gate ferry and intermittent recipient priors",function()
    local m=setup();local q=query();q.periodic=true;q.timing.gates=2;q.timing.ferries=1
    q.timing.ferryKeys={"east-west"}
    local eta=m.estimate(q);near(eta.seconds,315)
    near(eta.breakdown.gates,30);near(eta.breakdown.transport,180);near(eta.breakdown.npcWait,60)
    q.postal=true;q.periodic=false;near(m.estimate(q).seconds,255)
end)
test("actual supplied duration components override priors without pretending weights are time",function()
    local m=setup();local q=query();q.periodic=true;q.timing.ferries=1
    q.timing.transportSeconds=90;q.timing.npcWaitSeconds=120;q.timing.handlingSeconds=15
    near(m.estimate(q).seconds,259)
    q.timing.transportSeconds=0;q.timing.npcWaitSeconds=0;q.timing.handlingSeconds=0
    near(m.estimate(q).seconds,34)
end)
test("current configured pace changes only predicted paced time",function()
    local m=setup();local q=query();near(m.estimate(q).seconds,42)
    q.delay=3;near(m.estimate(q).seconds,69)
    q.delay=0;near(m.estimate(q).seconds,15)
    q.delay=60;near(m.estimate(q).seconds,1095)
end)
test("route metric aliases do not change identity or predictions",function()
    local m=setup();local q=proof();eq(m.remember(q),true)
    local eta=m.estimate(q);local alias=query();alias.metrics=alias.timing;alias.timing=nil
    alias.metrics.roadSteps=alias.metrics.steps;alias.metrics.steps=nil
    alias.metrics.delayUnits=alias.metrics.delays;alias.metrics.delays=nil
    eq(m.estimate(alias).samples,1);near(m.estimate(alias).seconds,eta.seconds)
    local nested=query();nested.route={timing=nested.timing};nested.timing=nil;eq(m.estimate(nested).samples,1)
    local flat=query();flat.steps=20;flat.delayUnits=18;flat.timing=nil;eq(m.estimate(flat).samples,1)
end)
test("first measurements blend the prior and three confirmed samples use measured time",function()
    local m=setup();local q=proof()
    eq(m.remember(q),true);local eta=m.estimate(q)
    eq(eta.method,"learned");eq(eta.samples,1);near(eta.learnedWeight,1/3);near(eta.seconds,42*2/3+100/3)
    eq(m.remember(q),true);eta=m.estimate(q);eq(eta.samples,2);near(eta.learnedWeight,2/3)
    eq(m.remember(q),true);eta=m.estimate(q);near(eta.seconds,100);near(eta.learnedWeight,1)
    eq(eta.confidence,"medium")
    eq(m.remember(q),true);eq(m.remember(q),true);eq(m.estimate(q).confidence,"high")
end)
test("confirmed sample non-delay EWMA includes actual travel and stationary waiting",function()
    local m=setup();local q=proof();eq(m.remember(q),true)
    q.seconds=190;eq(m.remember(q),true);eq(m.remember(q),true)
    -- Residual73 ->103 ->123, plus the same27 paced seconds.
    near(m.estimate(q).seconds,150)
    q.delay=2;near(m.estimate(q).seconds,159)
    q.delay=0;near(m.estimate(q).seconds,123)
end)
test("exact executed delay sum is removed before later pace changes",function()
    local m=setup();local q=proof();q.seconds=120;q.delaySeconds=50
    for _=1,3 do eq(m.remember(q),true) end
    near(m.estimate(q).seconds,97)
    q.delay=2;near(m.estimate(q).seconds,106)
end)
test("closed gate pacing is learned and re-added at the current tempo",function()
    local m=setup();local p=proof();p.timing={steps=3,delayUnits=2,gates=1,ferries=0}
    p.delay=1;p.pacedUnits=3;p.minimumDelayUnits=0;p.delaySeconds=3;p.seconds=20
    for _=1,3 do eq(m.remember(p),true) end
    near(m.estimate(p).seconds,20);near(m.estimate(p).pacedUnits,3)
    p.delay=60;near(m.estimate(p).seconds,197)
    local loaded=create(m.exportState());near(loaded.estimate(p).seconds,197)
end)
test("observed open gate units replace conservative prior gate delay without losing retiming",function()
    local m=setup();local p=proof();p.timing={steps=3,delayUnits=2,gates=1,ferries=0}
    p.delay=60;p.pacedUnits=2;p.minimumDelayUnits=0;p.delaySeconds=120;p.seconds=140
    -- The closed-gate prior would be180 paced seconds; actual open-gate
    -- timing remains valid even though elapsed140 is below that prior.
    for _=1,3 do eq(m.remember(p),true) end
    near(m.estimate(p).seconds,140);near(m.estimate(p).pacedUnits,2)
    p.delay=1;near(m.estimate(p).seconds,22)
end)
test("introduction floor counts are learned independently and survive changes below and above the floor",function()
    local m=setup();local p=proof();p.timing={steps=2,delayUnits=3,gates=0,ferries=0,minimumDelayUnits=1,minimumDelaySeconds=0.5}
    p.delay=0.15;p.pacedUnits=3;p.minimumDelayUnits=1;p.delaySeconds=0.8;p.seconds=10.8
    for _=1,3 do eq(m.remember(p),true) end
    near(m.estimate(p).seconds,10.8);near(m.estimate(p).minimumDelayUnits,1)
    p.delay=1;near(m.estimate(p).seconds,13)
    p.delay=0;near(m.estimate(p).seconds,10.5)
    local loaded=create(m.exportState());near(loaded.estimate(p).seconds,10.5)
end)
test("paced counts require actual whole timer firings and persisted EWMA counts stay allowlisted",function()
    local m,e=setup()
    for _,field in ipairs({"pacedUnits","minimumDelayUnits"}) do
        for _,value in ipairs({false,"1",-1,0.5,math.huge,0/0}) do
            local p=proof();p[field]=value;eq(m.remember(p),false)
        end
    end
    local p=proof();p.pacedUnits=0;p.minimumDelayUnits=1;eq(m.remember(p),false)
    p=proof();p.pacedUnits=19;p.minimumDelayUnits=0;p.seconds=110;p.delaySeconds=28.5
    eq(m.remember(p),true)
    p.pacedUnits=18;p.delaySeconds=27;eq(m.remember(p),true)
    local state=m.exportState();local _,record=next(state.actors.yarrim)
    near(record.pacedUnits,18+2/3);near(record.minimumDelayUnits,0)
    eq(create(state).estimate(query()).samples,2)
    record.minimumDelayUnits=record.pacedUnits+1;eq(create(state).estimate(query()).samples,0)
    eq(e.saves,2)
end)
test("actors source offices full recipient kind and periodic status remain separate",function()
    local m=setup();local p=proof();eq(m.remember(p),true)
    for _,change in ipairs({{actor="InnaPostac"},{sourceId="6f2c03461c2f1438"},{recipient="Johan Kornwalz Starszy"},{postal=true},{periodic=true}}) do
        local q=query();for field,value in pairs(change) do q[field]=value end
        eq(m.estimate(q).samples,0);eq(m.estimate(q).method,"estimate")
    end
    eq(m.summary("Yarrim").routes,1);eq(m.summary("Yarrim").samples,1)
    eq(m.summary("InnaPostac").routes,0);eq(m.count("Yarrim"),1)
end)
test("missing canonical actor or source permits only a prior without inventing learning identity",function()
    local m,e=setup();local q=query();q.actor=nil
    near(m.estimate(q).seconds,42);eq(m.estimate(q).samples,0);eq(m.estimate(q).method,"estimate")
    q.sourceId=nil;near(m.estimate(q).seconds,42);eq(e.saves,0)
    local p=proof();p.actor=nil;eq(m.remember(p),false);p=proof();p.sourceId=nil;eq(m.remember(p),false)
    eq(m.remember(proof()),true);eq(m.estimate(query()).samples,1);eq(m.estimate(q).samples,0)
    q.actor="Yarrim";eq(m.estimate(q).samples,0)
    q=query();q.actor=false;eq(m.estimate(q),nil);q=query();q.sourceId=123;eq(m.estimate(q),nil)
    eq(e.saves,1)
end)
test("canonical names normalize Polish case whitespace and trailing full stop without guessing",function()
    local m=setup();local p=proof();p.actor="  Żółw  ";p.recipient=" Jóhan   Żółw. ";p.sourceId="ABCDEF"
    eq(m.remember(p),true);p.actor="ZOLW";p.recipient="johan zolw";p.sourceId="abcdef"
    eq(m.estimate(p).samples,1);p.recipient="Johan";eq(m.estimate(p).samples,0)
end)
test("current safe route signatures isolate changed detours and ferry directions",function()
    local m=setup();local p=proof();p.timing.ferries=1;p.timing.ferryKeys={"east-west"};p.timing.signature="safe-a"
    eq(m.remember(p),true)
    for _,change in ipairs({{steps=21},{delays=19},{gates=1},{ferries=2},{ferryKeys={"west-east"}},{signature="safe-b"}}) do
        local q=clone(p);for field,value in pairs(change) do q.timing[field]=value end
        eq(m.estimate(q).samples,0)
    end
    p.delay=4;eq(m.estimate(p).samples,1,"pace alone keeps the same learned route signature")
end)
test("ferry key order is deterministic without losing repeated crossings",function()
    local m=setup();local p=proof();p.timing.ferries=3;p.timing.ferryKeys={"b","a","a"}
    eq(m.remember(p),true);p.timing.ferryKeys={"a","b","a"};eq(m.estimate(p).samples,1)
    p.timing.ferryKeys={"a","b"};eq(m.estimate(p).samples,0)
end)
test("all four actual completed-cycle evidence flags are mandatory",function()
    local m,e=setup()
    for _,field in ipairs({"verified","handover","reward","completed"}) do
        for _,value in ipairs({false,0,"true",{}}) do
            local p=proof();p[field]=value;eq(m.remember(p),false)
        end
        local p=proof();p[field]=nil;eq(m.remember(p),false)
    end
    eq(m.remember(nil),false);eq(e.saves,0);eq(m.summary("Yarrim").samples,0)
end)
test("elapsed and paced seconds must be finite positive and physically compatible",function()
    local m,e=setup()
    for _,value in ipairs({0,-1,0/0,math.huge,"100",false,604801}) do
        local p=proof();p.seconds=value;eq(m.remember(p),false)
    end
    for _,value in ipairs({-1,0/0,math.huge,"27",false,100,101}) do
        local p=proof();p.delaySeconds=value;eq(m.remember(p),false)
    end
    local p=proof();p.seconds=27;eq(m.remember(p),false)
    p=proof();p.seconds=28;p.delaySeconds=29;eq(m.remember(p),false)
    p=proof();p.delaySeconds=nil;eq(m.remember(p),true);eq(e.saves,1)
end)
test("unknown schemas malformed saved entries and executable or numeric map fields never become measurements",function()
    local m,e=setup();local p=proof();p.password="not-stored";p.map=444;p.callback=function() error("never") end
    p.timing.password="not-stored";eq(m.remember(p),true)
    local state=m.exportState();local actor=state.actors.yarrim
    local key,record=next(actor);eq(record.password,nil);eq(record.map,nil);eq(record.callback,nil);eq(record.timing.password,nil)
    local loaded=create(state);eq(loaded.estimate(query()).samples,1)
    state.schema=99;eq(create(state).estimate(query()).samples,0)
    state.schema=1;record.nonDelaySeconds=0;eq(create(state).estimate(query()).samples,0)
    record.nonDelaySeconds=73;record.samples=1.5;eq(create(state).estimate(query()).samples,0)
    record.samples=1;record.last=math.huge;eq(create(state).estimate(query()).samples,0)
    record.last=1000;actor["forged-key"]=actor[key];actor[key]=nil;eq(create(state).estimate(query()).samples,0)
    eq(e.saves,1)
end)
test("estimates reject malformed identity tempo metric and sparse transport inputs",function()
    local m,e=setup()
    for _,field in ipairs({"actor","sourceId","recipient"}) do
        for _,value in ipairs({"",42,false,{},"bad\nvalue"}) do local q=query();q[field]=value;eq(m.estimate(q),nil) end
    end
    for _,value in ipairs({-1,61,math.huge,0/0,"1.5",false}) do local q=query();q.delay=value;eq(m.estimate(q),nil) end
    for _,field in ipairs({"steps","delays","gates","ferries"}) do
        for _,value in ipairs({-1,0.5,math.huge,0/0,"1",false}) do local q=query();q.timing[field]=value;eq(m.estimate(q),nil) end
    end
    local q=query();q.timing.ferryKeys={[2]="b"};q.timing.ferries=2;eq(m.estimate(q),nil)
    q=query();q.timing.ferryKeys={"b"};eq(m.estimate(q),nil)
    q=query();q.timing.signature="bad\nvalue";eq(m.estimate(q),nil)
    q=query();q.timing.transportSeconds=-1;eq(m.estimate(q),nil)
    q=query();q.postal="true";eq(m.estimate(q),nil)
    eq(m.estimate({actor="Yarrim",sourceId="room",recipient="Johan",delay=1,route={cost=40}}),nil)
    eq(e.saves,0)
end)
test("failed save and failed clock leave every learned counter and estimate unchanged",function()
    local m,e=setup();eq(m.remember(proof()),true);local before=m.estimate(query()).seconds
    for _,failure in ipairs({true,"throw"}) do
        e.fail=failure;eq(m.remember(proof()),false);eq(m.summary("Yarrim").samples,1);near(m.estimate(query()).seconds,before)
    end
    e.fail=false;e.clockError=true;eq(m.remember(proof()),false);eq(m.summary("Yarrim").samples,1)
end)
test("persistence exported state input and returned breakdown do not alias live model data",function()
    local m,e=setup();local p=proof();eq(m.remember(p),true)
    p.timing.steps=1000;p.actor="mutated";eq(m.estimate(query()).samples,1)
    local actor=e.saved.actors.yarrim;local _,record=next(actor);record.samples=100;record.timing.steps=1000
    eq(m.estimate(query()).samples,1)
    local state=m.exportState();state.actors.yarrim={};eq(m.estimate(query()).samples,1)
    local eta=m.estimate(query());eta.breakdown.pace=0;eta.samples=100;eq(m.estimate(query()).samples,1)
    local loaded=create(m.exportState());eq(loaded.estimate(query()).samples,1)
end)
test("learned correction and a positive minimum keep breakdown totals honest",function()
    local m=setup();local q=proof();q.delay=0;q.delaySeconds=0;q.timing.steps=0;q.timing.delays=0;q.seconds=0.1
    for _=1,3 do eq(m.remember(q),true) end
    local eta=m.estimate(q);near(eta.seconds,1)
    local total=0;for _,seconds in pairs(eta.breakdown) do total=total+seconds end;near(total,eta.seconds)
    q.delay=10;q.timing.delays=1;q.seconds=11;q.delaySeconds=10
    for _=1,3 do eq(m.remember(q),true) end
    eta=m.estimate(q);near(eta.seconds,11)
    total=0;for _,seconds in pairs(eta.breakdown) do total=total+seconds end;near(total,eta.seconds)
end)
test("documented priors can be configured but invalid defaults never produce zero unknown time",function()
    local m=setup(nil,{ack=1,gate=2,ferry=3,handling=4,periodic=5})
    local q=query();q.periodic=true;q.timing.gates=2;q.timing.ferries=1;near(m.estimate(q).seconds,66)
    local broken=setup(nil,{ack=-1,gate=math.huge,ferry="3",handling=false,periodic=0/0})
    near(broken.estimate(query()).seconds,42)
end)
test("bounded route storage evicts only the oldest signatures and preserves the newest sample",function()
    local m,e=setup()
    for index=1,513 do local p=proof();p.recipient="Adresat "..index;e.now=1000+index;eq(m.remember(p),true) end
    eq(m.summary("Yarrim").routes,512);local q=query();q.recipient="Adresat 1";eq(m.estimate(q).samples,0)
    q.recipient="Adresat 513";eq(m.estimate(q).samples,1)
    eq(create(m.exportState()).summary("Yarrim").routes,512)
end)
test("bounded actors never mix timing learned by different characters",function()
    local m,e=setup()
    for index=1,33 do local p=proof();p.actor="Postac "..index;e.now=index;eq(m.remember(p),true) end
    local state=m.exportState();local n=0;for _ in pairs(state.actors) do n=n+1 end;eq(n,32)
    eq(m.summary("Postac 1").routes,0);eq(m.summary("Postac 33").samples,1)
    local q=query();q.actor="Postac 2";eq(m.estimate(q).samples,1);q.actor="Yarrim";eq(m.estimate(q).samples,0)
end)

print(string.format("PASS: %d ETA scenarios, %d assertions",tests,checks))
