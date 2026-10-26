-- Plans map legs around the explicitly supported Quenelles ferry.
-- Ordinary road steps and gates are owned by this courier, never by a
-- second native walker coroutine. All sends use the injected owned sender.
local NULN="6f2c03461c2f1438"
local QUENELLES="e202c7893bf8fb55"
local KARAK="c55c2924e506dd7f"
local BLUE,BLACK,DECK="891456eab7637380","2e1aa32a45a83107","be0c7fc1d5441e3a"
-- Stable known rooms on the Karak side, independent of profile area labels.
local KARAK_SIDE={}
for id in ([[
00f9334818f22a92 044ff5e377102885 058911d951a0cb4f 05aff11df7b7eb9a
05ce5aa00f5419cb 070a6e773603d61b 078cf2e4a39f50a7 0ddc16d3d857703d
0e2fe0e223975e4e 0e8a4bd197fe7e83 0f3e3ee4ac344203 10eb5db78d880676
127c6447a1ebaa97 12c9f1cbf8176cc6 155d0241f7df1c25 1577cb843d03504c
1a00c0da04e70b66 1b432b763ad80a95 1b9f7a44479603b4 1bc9dfd889066be3
1c7186902342a490 1dd35e9401e3ba88 1e79ccbef3981277 1e7aac3a75edcb34
1fee84919b368864 202182ac5992a3da 250d135597af8b4b 25ea18868d9939e8
27b020729e32f414 2a8544980b846502 2b013d99824929bf 2b2f729dee39bff4
2bdb8424ecc77353 2e1aa32a45a83107 2ea25b59b3c231f1 2f89d8d0a093a247
33c4702fa55e1d97 3de8d58adb6dbe9b 3e1c8aac2e49c5fe 3f65932172117e85
42fb04a4e98965f7 4327ee83dee6152a 4393ff636efa46cc 4482c69d9a555948
4483d7a9d101c104 4758550bd81f238f 47b02ac7b3a24c47 49568f4aab4c45c8
496d2e38b7f1ceed 4b3ae018621c2fb9 4c9111f8b1386266 4cb637caaf942827
4e5583067de404fc 4f816304d614dd16 4fa685e6b2c5290e 50fa821dd81c9348
52c010d37ff539cd 52ea0462915ef32c 54821b6cb5bd7915 54f16392509a2be3
556446608f36abc6 5582f512ea0bc0ce 58f6f01d1ba56d50 5a608ddbd5ea00cc
5c5caba39731ed29 5cdac7a4a6a727d6 5ce2410fdd9f30cc 6083390acde302e0
6a7333876fd3fae0 6cd519b0ce23f09b 6fe1bbba6571a046 721b28689b591a00
73cd37fe710a2882 74311f0cf055428c 74f60c7a6c3d9b1d 77342685caea53f0
779f2323820819d0 77c51727e7dc130c 7a01f96af6d08366 7a8ce22090b5fa4c
7b91286ea2be68b0 7bc66dc114d01519 7ca6546075d66c6d 7e9892bf82474dc6
7e9b088b65b296ac 80ff90e83f7fe474 84683966e5d4b388 8640576d51e7732f
88366542966c56f5 8ae08df4b9b69903 8b8fc41e12c9c179 8b9d8f1b3d137fe0
8dbcf5a2268ccd6b 91050a53da62216e 9186d3935b31b7e7 93d55492bc0cee3c
94c7f067a3b954bf 954cf0b46035b8ae 96ea511322bdbf66 99164377acb1ccad
9a1f55fee33d793d 9b26ba98859d536f 9ba281d190601194 9e2535027aae45c1
a11d7d26be103855 a2a9d2fac31b84e7 a327e3192cd88892 a50c5addc235f739
a5f55a847d71375e a79896f6310e34f5 a983992a5bad66cd aa97148936eb1876
ab33b307fe1cc496 ac717d3ae45fba1e ac7203e687892f67 afb1cf7a0fbd26dc
b55ea2097d28325b bc3108aa98a6cdd7 bcc80fb202cb7ed4 c2255d3aa644b3ad
c39ae21ea0b2b173 c55c2924e506dd7f c98445afa6993935 ceb3180f6fe6e8bc
cf1381e7c786a55c cf54c39416c91a26 d065a66849562c5e d200ea16745df7e8
d4b8378ad0063aab d4c5cec8df5213c9 d704fd15612dc350 d78f571c6ef20a44
d7afb2ff4389af02 d9ccbaef6af10a6b da89cde66a6b0ad7 dbeb53b80d0b0282
df092b1c7c16b3f7 dfde76e17af74ae7 e2882332bf711602 e28aabf65ad6e799
e2faf1fb75c3a702 e31aa9f0cd3c4c72 e48df652673a1789 e5595698f05e0a46
e63c646d316cf0e8 e77d6f89d1a705e8 e7d44a8c4093f83a e85d0702e1798b1a
ea7769bc34477ed8 eb28de2e9ae80ee6 ec5e233eab7c673a ef0e3dc38451e606
efe68cda8275d073 f2bbff85b2e03db2 f3c2bd060363c091 f47b8c5e51339152
f4c4163a101a582d f724044a61e3a779 f81c507c05f284c5 f8b9ea85a7690b72
f94e16cd1222f4ae faa8a792f7bfd8e5 fb19591a4cb82767 fbb4a1036d549aab
fcc367d41a2a8898 fd242ffb82afd1ca fd9f85cc27805e2b fecade69f60ab479
fee21e18166c3309
]]):gmatch("%S+") do KARAK_SIDE[id]=true end

return function(ctx,opts)
    local api={version="1.5.11"}
    local road=opts.road or require("chimera_paczki.road")(ctx,opts)
    local ferry=opts.ferry or require("chimera_paczki.ferry")(ctx,opts)
    local karak=opts.karakTransport
    if not karak and not opts.road then karak=require("chimera_paczki.karak_transport")(ctx,opts) end
    local active,sequence,disposed,intent=nil,0,false,nil
    local function cooperate()
        if type(opts.cooperate)=="function" then opts.cooperate() end
    end
    local function here() local r=opts.gmcp.room() or {};return opts.mapper.current_room(),r.id end
    local function hash(map) return map and opts.mapper.chimera_id(map) end
    local function valid(n) return type(n)=="number" and n>0 and n<math.huge end
    local function map(id)
        local n=type(getRoomIDbyHash)=="function" and getRoomIDbyHash(id)
        return valid(n) and n or nil
    end
    local function alive(op) return not disposed and active==op and not op.finished end
    local function boatState()
        local state=ferry.state and ferry.state()
        return state and state.aboard and state or nil
    end
    function api.originForCost()
        local state=boatState()
        return state and (state.toMap or map(state.toHash)) or nil
    end
    local function ferryPlan(from,to,link,upperBound)
        cooperate()
        local firstMap,lastMap=link.fromMap or map(link.fromHash),link.toMap or map(link.toHash)
        if not firstMap or not lastMap then return nil end
        local first=road.plan(from,firstMap)
        if not first then return nil end
        local crossing=link.cost or 40
        if type(upperBound)=="number" and type(crossing)=="number" and crossing>=0 and
            type(first.cost)=="number" and first.cost>=0 and first.cost+crossing>=upperBound then
            return nil
        end
        local last=road.plan(lastMap,to)
        if not last then return nil end
        local route={from=from,target=to,cost=first.cost+(link.cost or 40)+last.cost,link=link,legs={}}
        if #first.steps>0 then route.legs[#route.legs+1]={kind="road",plan=first} end
        local trip={};for k,v in pairs(link) do trip[k]=v end
        trip.fromMap,trip.toMap=firstMap,lastMap
        route.legs[#route.legs+1]={kind="ferry",link=trip}
        if #last.steps>0 then route.legs[#route.legs+1]={kind="road",plan=last} end
        return route
    end
    local function basePlan(from,to,ignoreBoat,ignoreIntent)
        cooperate()
        if not valid(to) then return nil,"nieprawidlowy cel mapy" end
        local state=not ignoreBoat and boatState()
        if state then
            local shore=state.toMap or map(state.toHash)
            local last=shore and road.plan(shore,to)
            if not last then return nil,"brak znanej drogi od docelowego brzegu" end
            local route={target=to,cost=(state.cost or 40)+last.cost,legs={{kind="resume",toMap=shore}}}
            if #last.steps>0 then route.legs[#route.legs+1]={kind="road",plan=last} end
            return route
        end
        if not valid(from) then return nil,"poza mapa" end
        if from==to then
            local zero,why=road.plan(from,to)
            return zero and {from=from,target=to,cost=0,legs={{kind="road",plan=zero}}} or nil,why
        end
        local origin,destination=hash(from),hash(to)
        local forced=(origin==NULN and destination==QUENELLES) or (origin==QUENELLES and destination==NULN)
        local forcedBank=forced and (origin==NULN and "894039a1680ca034" or "20016d960316ba51")
        local preferred=not ignoreIntent and intent and intent.target==to and intent.pending and intent.link and intent.link.transport~="karak_ship" and intent.link or nil
        if preferred then
            local route=ferryPlan(from,to,preferred)
            if route then return route end
        end
        local direct=road.plan(from,to)
        local best=direct and {from=from,target=to,cost=direct.cost,legs={{kind="road",plan=direct}}} or nil
        local ferryBest
        for _,link in ipairs(ferry.catalogue()) do
            cooperate()
            -- Nonnegative road legs cannot make a crossing cheaper than its
            -- own minimum cost. Short local jobs need no distant-bank search.
            -- Forced and remembered crossings retain their exact protocol.
            local crossing=link.cost or 40
            local bound=best and best.cost
            if ferryBest and (not bound or ferryBest.cost<bound) then bound=ferryBest.cost end
            local canImprove=not bound or type(crossing)~="number" or crossing<0 or crossing~=crossing or crossing>=math.huge or crossing<bound
            local candidate=(not forcedBank or link.fromHash==forcedBank) and (forced or canImprove) and
                ferryPlan(from,to,link,not forced and bound or nil)
            if candidate and (not ferryBest or candidate.cost<ferryBest.cost) then ferryBest=candidate end
        end
        -- The Nuln/Quenelles relation follows the confirmed river crossing.
        -- Do not substitute the untested land detour through Loren/Orcal.
        if forced then
            if ferryBest then return ferryBest end
            return nil,"brak kompletnej trasy do promu i od drugiego brzegu"
        end
        if ferryBest and (not best or ferryBest.cost<best.cost) then best=ferryBest end
        return best,best and nil or "brak kompletnej obslugiwanej drogi"
    end
    local function side(mapRoom) return KARAK_SIDE[hash(mapRoom)]==true end
    local function append(legs,route)
        for _,leg in ipairs(route.legs or {}) do cooperate();legs[#legs+1]=leg end
    end
    local function kahnPlan(from,to,link,resuming,ignoreBoat)
        cooperate()
        local first
        if not resuming then
            first=basePlan(from,link.fromMap,ignoreBoat==true,true)
            if not first then return nil end
        end
        local last=basePlan(link.toMap,to,true,true)
        if not last then return nil end
        local legs={}
        if first then append(legs,first) end
        legs[#legs+1]={kind=resuming and "karak_resume" or "karak_ship",link=link}
        append(legs,last)
        return {from=from,target=to,cost=(first and first.cost or 0)+(link.cost or 60)+last.cost,
            legs=legs,link=(first and first.link) or link}
    end
    function api.plan(from,to,ignoreBoat,ignoreIntent)
        cooperate()
        if not valid(to) then return nil,"nieprawidlowy cel mapy" end
        local links=karak and karak.catalogue() or {}
        if not ignoreBoat and (opts.gmcp.room() or {}).id==DECK then
            local best
            for _,link in ipairs(links) do
                cooperate()
                local candidate=kahnPlan(from,to,link,true)
                if candidate and (not best or candidate.cost<best.cost) then best=candidate end
            end
            return best,best and nil or "brak kompletnej trasy od brzegu Kahn-Gad do celu"
        end
        local across=valid(from) and side(from)~=side(to)
        local wantedBank=across and (side(from) and BLACK or BLUE) or nil
        local preferred=not ignoreIntent and intent and intent.target==to and intent.pending and intent.link or nil
        if preferred and preferred.transport=="karak_ship" then
            local candidate=kahnPlan(from,to,preferred,false,ignoreBoat)
            if candidate then return candidate end
        end
        local direct=not across and basePlan(from,to,ignoreBoat,ignoreIntent) or nil
        if direct then return direct end
        if not across and hash(from)~=DECK and not side(to) and not (not ignoreBoat and boatState()) then return nil,"brak kompletnej obslugiwanej drogi" end
        local best
        for _,link in ipairs(links) do
            cooperate()
            if not wantedBank or link.fromHash==wantedBank then
                local candidate=kahnPlan(from,to,link,false,ignoreBoat)
                if candidate and (not best or candidate.cost<best.cost) then best=candidate end
            end
        end
        return best,best and nil or "brak kompletnej trasy przez Kahn-Gad; nie wybieram gorskiego obejscia"
    end
    function api.cost(from,to)
        local route=api.plan(from,to,true,true)
        return route and route.cost or nil
    end
    function api.costFromCurrent(to)
        local from=here()
        local route=api.plan(from,to)
        return route and route.cost or nil
    end
    function api.metricsForPlan(route)
        if type(route)~="table" or type(route.legs)~="table" then return nil,"brak odcinkow trasy" end
        local result={steps=0,delayUnits=0,gates=0,ferries=0,ferryKeys={},fareCopper=0}
        local parts={"journey"}
        for _,leg in ipairs(route.legs) do
            cooperate()
            if leg.kind=="road" then
                local metrics,why
                if road.metrics then
                    metrics,why=road.metrics(leg.plan)
                    if not metrics then return nil,why or "niepelna geometria drogi" end
                end
                -- Pure injected road adapters may omit the timing API. They
                -- can still describe exact steps, without claiming gate data.
                if not road.metrics then
                    if type(leg.plan)~="table" or type(leg.plan.steps)~="table" then return nil,"brak geometrii drogi" end
                    metrics={steps=#leg.plan.steps,delayUnits=math.max(0,#leg.plan.steps-1),gates=0}
                    local stable={"road",tostring(leg.plan.fromId),tostring(leg.plan.targetId)}
                    for _,step in ipairs(leg.plan.steps) do cooperate();stable[#stable+1]=tostring(step.cmd);stable[#stable+1]=tostring(step.id) end
                    metrics.signature=table.concat(stable,"|")
                end
                result.steps=result.steps+metrics.steps
                result.delayUnits=result.delayUnits+metrics.delayUnits
                result.gates=result.gates+metrics.gates
                parts[#parts+1]=metrics.signature
            elseif leg.kind=="ferry" or leg.kind=="resume" or leg.kind=="karak_ship" or leg.kind=="karak_resume" then
                result.ferries=result.ferries+1
                local link=leg.link or {}
                local toHash=link.toHash or (leg.toMap and hash(leg.toMap))
                local fromHash=link.fromHash
                if not fromHash and toHash=="894039a1680ca034" then fromHash="20016d960316ba51"
                elseif not fromHash and toHash=="20016d960316ba51" then fromHash="894039a1680ca034" end
                if type(fromHash)~="string" or type(toHash)~="string" then return nil,"brak tozsamosci przeprawy" end
                local key=fromHash..">"..toHash
                result.ferryKeys[#result.ferryKeys+1]=key
                parts[#parts+1]=leg.kind..":"..key
                if leg.kind=="karak_ship" or leg.kind=="karak_resume" then result.fareUnknown=true end
            else return nil,"nieznany odcinek trasy" end
        end
        result.delays=result.delayUnits
        local first,second=2166136261,5381
        local text=table.concat(parts,"|")
        for index=1,#text do
            if index%128==0 then cooperate() end
            local byte=text:byte(index)
            first=(first*131+byte)%4294967296
            second=(second*65599+byte)%4294967291
        end
        result.signature="journey1:"..string.format("%.0f",first)..":"..string.format("%.0f",second)
        return result
    end
    function api.metrics(from,to,fromCurrent)
        local route,why
        if fromCurrent then route,why=api.plan(here(),to)
        else route,why=api.plan(from,to,true,true) end
        if not route then return nil,why end
        return api.metricsForPlan(route)
    end
    function api.quote(from,to,fromCurrent)
        local route,why
        if fromCurrent then route,why=api.plan(here(),to)
        else route,why=api.plan(from,to,true,true) end
        if not route then return nil,nil,why end
        return route.cost,api.metricsForPlan(route)
    end
    local function finish(op,result)
        if active~=op or op.finished then return end
        op.finished=true;active=nil
        local cancel=op.cancel;op.cancel=nil
        if cancel then cancel() end
        if result.ok then intent=nil end
        op.done(result)
    end
    function api.idz(target,done)
        if disposed then done({ok=false,reason="nawigacja wylaczona"});return function() end end
        local before=sequence
        if active then finish(active,{ok=false,reason="zastapiono nawigacje"}) end
        if disposed or before~=sequence then done({ok=false,reason="zastapiono nawigacje"});return function() end end
        local from=here()
        target=tonumber(target)
        local route,why=api.plan(from,target)
        if not route then done({ok=false,reason=why});return function() end end
        sequence=sequence+1
        local op={done=done,route=route,index=1,finished=false}
        active=op
        intent={target=target,link=route.link,pending=route.link~=nil}
        local advance
        advance=function()
            if not alive(op) then return end
            local leg=route.legs[op.index]
            if not leg then
                local current,currentId=here()
                if current~=target or currentId~=hash(target) then finish(op,{ok=false,reason="niezgodny cel podrozy"})
                else finish(op,{ok=true,map_room=target}) end
                return
            end
            local completed=false
            local legIndex=op.index
            local function returned(result)
                if completed or not alive(op) or op.index~=legIndex then return end
                completed=true
                op.cancel=nil
                if not result or not result.ok then finish(op,result or {ok=false,reason="brak wyniku podrozy"});return end
                if leg.kind~="road" then
                    intent.pending=false;intent.link=nil
                    for nextIndex=op.index+1,#route.legs do
                        local upcoming=route.legs[nextIndex]
                        if upcoming.kind~="road" and upcoming.link then intent.pending=true;intent.link=upcoming.link;break end
                    end
                end
                op.index=op.index+1
                advance()
            end
            local cancel
            op.phase=leg.kind=="road" and "road" or "ferry"
            ctx:emit("chimera.paczki.travel.activity",{phase=op.phase,timeout=op.phase=="road" and 180 or 360})
            if not alive(op) then return end
            if leg.kind=="road" then cancel=road.run(leg.plan,returned)
            elseif leg.kind=="resume" then cancel=ferry.resume(leg.toMap,returned)
            elseif leg.kind=="karak_ship" then cancel=karak.run(leg.link,returned)
            elseif leg.kind=="karak_resume" then cancel=karak.resume(leg.link,returned)
            else cancel=ferry.run(leg.link,returned) end
            if alive(op) and not completed then op.cancel=cancel
            elseif not completed and cancel then cancel() end
        end
        advance()
        return function() finish(op,{ok=false,reason="przerwane"}) end
    end
    -- Execute a city planner's confined ordinary-road plan through the same
    -- ACK-driven road engine. This bypasses global path selection and ferries.
    function api.runLocal(plan,done)
        if disposed or active then
            done({ok=false,reason=disposed and "nawigacja wylaczona" or "inna podroz trwa"})
            return function() end
        end
        sequence=sequence+1
        local op={done=done,finished=false,phase="road"}
        active=op;intent=nil
        local completed=false
        local cancel=road.run(plan,function(result)
            if completed or not alive(op) then return end
            completed=true;op.cancel=nil
            finish(op,result or {ok=false,reason="brak wyniku kroku w miescie"})
        end)
        if alive(op) and not completed then op.cancel=cancel end
        return function() finish(op,{ok=false,reason="przerwane"}) end
    end
    function api.phase() return active and active.phase or nil end
    function api.lastEdge() return road.lastEdge and road.lastEdge() or nil end
    function api.continueAfterAttack() return road.continueAfterAttack and road.continueAfterAttack() or false end
    function api.endCombatTransit() if road.endCombatTransit then road.endCombatTransit() end end
    function api.clearIntent() intent=nil end
    ctx:cleanup(function()
        disposed=true
        if active then finish(active,{ok=false,reason="przeladowanie kuriera"}) end
        intent=nil
    end)
    return api
end
