-- Owned execution of ordinary map edges. Gate commands and movement are sent
-- through the injected sender; the native walker is never started or patched.
local STEP_TIMEOUT, GATE_TIMEOUT, MAX_GATE_OPENS = 15, 30, 2
local DIRECTION = {
    n = "polnoc", s = "poludnie", e = "wschod", w = "zachod", u = "gora", d = "dol",
    ne = "polnocny-wschod", nw = "polnocny-zachod", se = "poludniowy-wschod", sw = "poludniowy-zachod",
}
local ASCII = { ["ą"]="a", ["ć"]="c", ["ę"]="e", ["ł"]="l", ["ń"]="n", ["ó"]="o", ["ś"]="s", ["ź"]="z", ["ż"]="z",
    ["Ą"]="a", ["Ć"]="c", ["Ę"]="e", ["Ł"]="l", ["Ń"]="n", ["Ó"]="o", ["Ś"]="s", ["Ź"]="z", ["Ż"]="z" }
local function norm(value)
    local text = tostring(value or ""):gsub("\27%[[%d;]*[mK]", ""):gsub(" ", " ")
    for accent, ascii in pairs(ASCII) do text = text:gsub(accent, ascii) end
    return (text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", ""))
end
local function direction(command)
    command = norm(command)
    if command == "up" then return "u" end
    if command == "down" then return "d" end
    for short, full in pairs(DIRECTION) do if command == full then return short end end
    return command
end
local function basic_block(command)
    local text = tostring(command or "")
    if text:find("[\r\n;]") or norm(text) == "" then return "nieobslugiwana komenda zlozona" end
    text = norm(text)
    -- Mapper labels are not game commands. Verified transport controllers
    -- own tickets, boarding and landing instead of sending these labels.
    if text=="statek" or text=="prom" then return "etykieta transportu wymaga osobnej obslugi przeprawy" end
    local verb = text:match("^(%S+)")
    -- A map edge is not proof that every character can execute it. These
    -- shortcuts depend on skills/conditions, unlike ordinary u/d road exits.
    if verb=="wespnij" or verb=="wspinaj" then
        return "skrot wymaga wspinaczki i umiejetnosci postaci"
    end
    local boarding = { wsiadz=true, wejdz=true, zejdz=true, wyjdz=true, wysiadz=true, usiadz=true, wjedz=true }
    if boarding[verb] then
        for _, vessel in ipairs({ "statek", "statku", "prom", "tratw", "dylizans", "powoz", "woz", "bark", "kryp", "brycz" }) do
            if text:find(vessel, 1, true) then return "trasa wymaga osobnej obslugi transportu" end
        end
    end
end

-- Stable Chimera hashes from the beta.13 world catalogue. Grey Mountain
-- paths belong to the broad Parravon/Drachenfels map areas, so banning an
-- area name alone does not protect the Montdidier junction. Keep the road
-- pass and settlements available; exclude the known wilderness shortcuts.
local KNOWN_DANGER = {}
for id in ([[
0d6f2b237c1f3083 14d69e031d8065fc 14dea5b7c1c6075c 1df74e387c7891b7
25957c9012379cb8 3248a18e9f0fae3c 37d85d254ec88021 39e34e97b483d93b
3c54401d92980f78 4377690791c7ba46 45e6e31b04ba8b23 46a03cdae0dd40cb
48711a86a84eb605 57439bc323dda644 61e2c0aea1b44712 625d3c592cedf315
67715a2ee5a62bc6 79b664e58d906422 7b55bb3b9f3000b9 7d3bc7cfe3b5eb94
8367275d7d2558a9 845f65acf3e61422 8590ab28d4a01346 8dffe0e8a9f94004
902e2f0979fbe53e 93dad93b5e34b67c 9584ca5556bb7ff5 97c1b2ed6270fe9d
9a62f5c9822e6020 9f44e4de4ca24273 a1e18dbdfcabee9c a4c2666ce85b384a
a53aa82844bb6f4f a73ae5ac0b2d8c53 adaf9107a9841bde b0c7c91670e28ffb
b424541fc01ede22 b42d1ce886dd5203 ba3234694a142481 bd48108c79f1cba1
c029a5d1a1c0a75c c39e540b2fe80559 c616f6243119f6d6 cae1692e8ced8a25
cded09b20b025599 d2a008e88f44ca54 d37fd227892f04f4 d53c968a91e66ad0
dc14b92dab96f7be dcaa83e766c7c5ca dd04c9d915053cdb e00e273bb9f6306b
e01de121b19a8aa0 e3402a9c9b8c4d61 e6726c04f601184e f02ebe0ea096d945
f41b13809ffee139 f58cded468515c2f fa1752687ed4240f fb77699c394aa45e
]]):gmatch("%S+") do KNOWN_DANGER[id]="Gory Szare" end
for id in ([[
018bc55aaafa81c3 051dd30fc18e6151 06d97d2855aa5903 07d4984a6d6346a5
0995b4ae50dd1591 0a3e4de59aa9883d 0b8443e4f1c18a5c 0e653ca2f844dec3
0eeaeafb6c42c793 0f9f3565ea13403d 13619b85a61bb235 1a262ff132e29d10
1ac71a4ada1b73f3 1e64e567735154e6 239c06fb51d0a879 2430d1b6c1dfd91b
2aba31489aeebd7c 2d20219179cd6bec 2d62c2f026dd9695 306fa6a2a4c5883b
313d450ab2484882 32ec780ec0c1a42a 34033cdc4b59b17f 34adbc979a693791
36fa93a894a23065 3abaa372ee6d8869 3b9f894d022724f5 43ccb39cfa01ca5d
47a50fdc6fe78076 486cd87c51a6f493 4acb136b62bd2289 4e84910902d9cc5a
5091905fd3e3fe52 510bc87a6460b287 5117c56fcabcfdac 5462dd79ce22903a
553b73922064480b 575be1869d44c21b 57fc8c5a6db21e8a 5de7597118cdae6b
5f863da898e51e9d 5fb808c02deca2d8 62105f0d12a0b410 66f93b495a9917dc
68515cfce7062d3b 69ff811b0082a763 6c5725331126c92b 6cd739f2552bc507
6f396f46bae97ea5 726ec2345feefdc2 7564c80b1b1caae6 78da7cc80d73fd99
7b7f9d6364c5249a 7e87125465878ad1 8126859c8b092f98 812dfb00e14a1b8f
820887cde76abeb5 822c364e4f5594c6 82584a736fe5cf02 8403bb1633b97053
84cba82dc8a74e23 850f8cbfda7158c4 887fbb2bdca89e79 88ed19f6c76c8905
8f9f15632e8cd773 91d86a1ac7951b12 929ac28424d586af 9639ecf5591ecd55
96e0118569861e5c 97b6c0122814d3b5 9cda0995d0b7e983 9e09f918bcad4f6b
a0076c73f5e9103d a0975ec4530976e2 a3d1b79958e27dc3 aaab69bf2224ed4c
ab20b001dc54f104 b0f7dccfdf1fd100 b22b8d5ceb4ec530 b2ad69822ae5b375
b3e26ef46790f231 b4183f1cab80169b b44b749f25cfbc22 b65aa0a00978a803
bbf88fbc92123cdf c2ee056350fbf7dc c372905b1fbef33c c3bd8effc05db0ed
c71168319d4693d8 c8f052e9691dccd4 ca6e6063f6b781bd cbb6dc9b30fb63c2
cbecb043547e3ff5 cc5d73bea4329188 d2d1b87baabef7c2 d3b03766e9252e2d
d416894584f9f132 d5b430e9d6016620 d8157c4c477fc50e d84341a18b0e40cd
d85858e87d3d58bc dd35320f8b76af96 dd585bc5e91dcfcb de17977e744bd0ee
dfdd5b4526c71eab e007ac0b353c89ec e02e3464083d8518 e22b204dfc79f8cf
e463f7fcb1539ff9 e469695009fa68c4 e7b91728c4c9f793 e82d094fcd68281e
ee916a52e7514fc0 eeafac41cae05e76 efca0303af355716 efdd0f93c76d9588
f2a22d22a93be2fe f3652ad35daff0ad f8a8ac439cf3ff39 f8f4359732e66949
fa07caa5893465ee fb319ccb07c0e6bf
]]):gmatch("%S+") do KNOWN_DANGER[id]="Las Loren" end

-- All 122 beta.13 Gory Czarne wilderness rooms have terrain="gory".
-- The separate Karak-Varn approach road, port and city remain available;
-- also exclude the westward wilderness entrance from the city gate.
for id in ([[
020f2afcbafceee5 03091252bf7fc100 037aa29d8073a9ed 041f7bcaac911290
060c0099679c8588 071ec370dec41b06 08a3507b685cb75c 0dbb4414fa42557f
16f5f25677957270 190dc8d33f4d4827 1988028df0a3bc20 1acbe0752e63a725
1f40cd5391a28136 2277e63524f6c528 25b64b02ca3320bc 2804fa919ecd9766
280ccf2a1114e82a 298a7490f607b218 29cc4c3efa8c970b 2b7a89d76b9611e8
2ee7bd0f619890d9 2f995039f2c8a5e2 33ff4fbe29147308 3420a3be80a5b0bc
35ad7d320677176e 362c594e631ccd59 380746ab2c91f025 3842f334945a046c
390a0415cf3bcab5 39a9b5233141229c 3bffed81e69224bc 3c297ffaca0b859a
3dba45366b5c121f 432c81fe6c96dc09 43a0f2543b0e9d03 47046c58917b900e
47654c10e1790e27 4940fe5aa7d02142 495c3d9694c1f420 4cbaa5f65f407a4c
4dbabda37eb7c2f4 4ef9a4a6193caac6 501e2907e5df6a0c 513beb5ffd476319
53445578ef97deca 53c95de7a27e5cc0 58801dab6c52d02d 5f38958910a87bab
5fc091fec53894c1 6073b9126c0b9f9d 628a989bad6596c3 637276970e4de783
72c9b0f7c1097d95 7375e2a9c4ab6363 74665ace10bf7fa9 7b3a460e787c3e53
7bd8f483ecc61856 803cd1a3a8e77a6d 82a45a61fd086f72 858b25ca756b0760
85e31e0e10468354 8723d6a98dada9ab 88a5a0336c68b7e0 8b525ddf62f8fc4e
91a3ea5f96509906 92e560f35040c0c1 93d05f843de0a015 942fab6765e19a19
9673241cbeb46ad9 97879fa8c8341a5e 980f35ef708fc40a 98a9ebdc8978a3dd
98b797509fde86ad 9a68d4b221c1628a 9c9e3bec564c7f3b a374ec4f327b0d48
a3cf6cf9192e4c4c a5735e2613911ec0 a7153099a65410ea aa36f65cb76e8ad3
b0bda52d93999a8d b39d7a5567081b25 b3a68da4d17902b9 b3aecb22952b6fcf
b7df07e07a809dff ba33c5a60bee0ca8 ba39260da27f2055 bbeb563d4cdbfe0a
c4968f26c8f4b416 c6a6528aeac283e4 c81c6cedb954626a c90af67c6f3c5e33
ca48445973a8fc07 cbc20e0f2323a087 cbc8032082e8717e cd4cf5a0cbab6102
cf297bdee0f3d475 d390afd577fe1140 d3d7bd74d9e8b048 d515783f6d2fe27e
d5dec9112183bf86 da222a14f7c4d219 da2ef82e51c0929c de10b4823adea8c0
e09100680dba803f e0ea7bd215fcf87e e4b404414d5a9243 e62869473b3fe757
eb3bc099a3197e5b ed4b5827678fb8c4 ef4001e2927be25b efcf1c0c4d124682
f2164999e7000147 f3e311cefe529125 f4035782d3094c16 f411a74278aaa9a2
f4886c79016e2fbe f68729f277549b79 fa23ab31f77b04c8 fae007423a33c4cd
fc11ec1bdc87352d fde1010ba76426fe 2bdb8424ecc77353
]]):gmatch("%S+") do KNOWN_DANGER[id]="dziki skrot przez Gory Czarne" end

return function(ctx, opts)
    local gmcp, mapper, locations = assert(opts.gmcp), assert(opts.mapper), opts.locations or {}
    local api, active, generation, disposed, drain, lastEdge = {}, nil, 0, false, nil, nil
    local trail,emergencyEdge={},nil
    local function cooperate()
        if type(opts.cooperate)=="function" then return opts.cooperate() end
        return false
    end
    local function planning()
        if type(opts.planning)=="function" then return opts.planning()==true end
        return cooperate()==true
    end
    local function planning_cache()
        if type(opts.planningCache)~="function" then return nil end
        local value=opts.planningCache()
        return type(value)=="table" and value or nil
    end
    local function clone(value)
        if type(value)~="table" then return value end
        local result={}
        for key,item in pairs(value) do
            cooperate()
            result[key]=clone(item)
        end
        return result
    end
    local function blocked(command)
        local reason = basic_block(command)
        if reason then return reason end
        if opts.blockCommand then
            local ok, rejected, why = pcall(opts.blockCommand, command)
            if not ok then return "nie udalo sie sprawdzic komendy trasy" end
            if rejected then return why or "komenda trasy jest wylaczona" end
        end
    end
    local function hash(map)
        local id = mapper.chimera_id(map)
        return type(id) == "string" and id ~= "" and id or nil
    end
    local function blocked_room(map)
        local known = KNOWN_DANGER[hash(map)]
        if known then return "wylaczony niebezpieczny skrot: "..known end
        local function inspect(fn, value)
            if type(fn)~="function" then return nil end
            local ok,result=pcall(fn,value)
            if not ok then return "nie udalo sie sprawdzic obszaru trasy" end
            local text=norm(result)
            if text:find("gorach szarych",1,true) or text:find("gor szarych",1,true) or
                text:find("gory szare",1,true) then return "wylaczony niebezpieczny skrot: Gory Szare" end
            if text=="las loren" then return "wylaczony niebezpieczny skrot: Las Loren" end
            if text=="gdzies w gorach czarnych" or text=="gdzies na granicy gor czarnych i gor kranca swiata" then
                return "wylaczony niebezpieczny skrot: dzikie Gory Czarne"
            end
        end
        local why=inspect(getRoomName,map)
        if why then return why end
        if type(getRoomArea)=="function" and type(getRoomAreaName)=="function" then
            local ok,area=pcall(getRoomArea,map)
            if not ok then return "nie udalo sie sprawdzic obszaru trasy" end
            if area then
                why=inspect(getRoomAreaName,area)
                if why then return why end
            end
        end
        if opts.blockRoom then
            local ok,rejected,reason=pcall(opts.blockRoom,map,hash(map))
            if not ok then return "nie udalo sie sprawdzic lokacji trasy" end
            if rejected then return reason or "lokacja trasy jest wylaczona" end
        end
    end
    local function forget_edges()
        trail,lastEdge,emergencyEdge={},nil,nil
    end
    local function copy_edge(edge)
        return {fromId=edge.fromId,fromMap=edge.fromMap,toId=edge.toId,toMap=edge.toMap}
    end
    local function remember_edge(edge)
        -- Only consecutive, verified edges may form a retreat trail. A new
        -- position cannot reconnect older history by merely sharing a hash.
        local previous=trail[#trail]
        if previous and (previous.toId~=edge.fromId or previous.toMap~=edge.fromMap) then trail={} end
        emergencyEdge=nil
        trail[#trail+1]=copy_edge(edge)
        if #trail>32 then table.remove(trail,1) end
        lastEdge=trail[#trail]
    end
    local function emergency_position(map,room,snapshot)
        local expected=emergencyEdge
        if not expected then return false end
        if map==expected.toMap and room.id==expected.toId then return true end
        if snapshot and room.id==expected.fromId and map~=expected.fromMap then return true end
        local live=gmcp.room() or {}
        if map==expected.fromMap and room.id==expected.fromId and
            mapper.current_room()==map and live.id==room.id and
            hash(expected.fromMap)==expected.fromId and hash(expected.toMap)==expected.toId then
            local newest=trail[#trail]
            if newest and newest.fromId==expected.fromId and newest.fromMap==expected.fromMap and
                newest.toId==expected.toId and newest.toMap==expected.toMap then
                table.remove(trail)
                emergencyEdge=nil
                lastEdge=trail[#trail]
                if lastEdge and (lastEdge.toId~=room.id or lastEdge.toMap~=map) then forget_edges() end
                return true
            end
        end
        forget_edges()
        return false
    end
    local function delay()
        local value = opts.delay
        if type(value) == "function" then value = value() end
        return math.max(0, math.min(30, tonumber(value) or 0.35))
    end
    local function step_delay(op)
        return op.combatTransit and 0.05 or delay()
    end

    local function native_plan(from, target)
        from, target = tonumber(from), tonumber(target)
        if not from or from <= 0 or not target or target <= 0 then return nil, "nieprawidlowy pokoj mapy" end
        local fromId, targetId = hash(from), hash(target)
        if not fromId or not targetId then return nil, "brak identyfikatora lokacji na mapie" end
        local plan = { from=from, target=target, fromId=fromId, targetId=targetId, cost=0,
            steps={}, commands={}, rooms={}, weights={} }
        if from == target then return plan end
        if type(getPath) ~= "function" then return nil, "brak planowania drogi na mapie" end
        local called, found = pcall(getPath, from, target)
        if not called or not found then return nil, "brak drogi na mapie" end
        local dirs, rooms, weights = speedWalkDir or {}, speedWalkPath or {}, speedWalkWeight or {}
        if #dirs == 0 or #dirs ~= #rooms then return nil, "niepelna trasa mapy" end
        for i, raw in ipairs(dirs) do
            cooperate()
            local command = (raw == "up" and "u") or (raw == "down" and "d") or tostring(raw)
            local reason = blocked(command)
            if reason then return nil, reason, true end
            local map = tonumber(rooms[i])
            local id = map and map > 0 and hash(map)
            if not id then return nil, "lokacja na trasie nie ma identyfikatora Chimery" end
            reason=blocked_room(map)
            if reason then return nil,reason,true end
            local weight = tonumber(weights[i]) or 0
            plan.steps[i] = { cmd=command, map=map, id=id, weight=weight }
            plan.commands[i], plan.rooms[i], plan.weights[i] = command, map, weight
            plan.cost = plan.cost + weight
        end
        if plan.rooms[#plan.rooms] ~= target then return nil, "trasa nie konczy sie w zadanym pokoju" end
        if plan.cost <= 0 then plan.cost = #plan.steps end
        return plan
    end
    local alternate
    local function constrained(from,target)
        if not alternate then
            local ok,create=pcall(require,"chimera_paczki.path")
            if not ok then return nil,"brak modulu bezpiecznego planowania" end
            alternate=create({hash=hash,blocked=blocked,blockedRoom=blocked_room,cooperate=cooperate})
        end
        return alternate.find(tonumber(from),tonumber(target))
    end
    function api.plan(from,target)
        cooperate()
        if planning() then
            -- A native getPath call cannot yield. Board quotations use our
            -- bounded graph search so the owner can service MUD events between
            -- small slices. Real navigation retains the native fast path.
            local cache=planning_cache()
            local fromMap,toMap=tonumber(from),tonumber(target)
            local fromId,toId=fromMap and hash(fromMap),toMap and hash(toMap)
            local key=fromId and toId and tostring(fromMap)..":"..fromId..">"..tostring(toMap)..":"..toId
            local saved=cache and cache.roadPlans and key and cache.roadPlans[key]
            if saved then return saved.plan and clone(saved.plan) or nil,saved.reason end
            local plan,reason=constrained(fromMap,toMap)
            if cache and key then
                cache.roadPlans=cache.roadPlans or {}
                cache.roadPlanCount=cache.roadPlanCount or 0
                cache.roadPlanSteps=cache.roadPlanSteps or 0
                local steps=plan and #plan.steps or 0
                if cache.roadPlanCount<256 and cache.roadPlanSteps+steps<=8192 then
                    cache.roadPlans[key]={plan=plan and clone(plan) or false,reason=reason}
                    cache.roadPlanCount=cache.roadPlanCount+1
                    cache.roadPlanSteps=cache.roadPlanSteps+steps
                end
            end
            return plan,reason
        end
        local plan,why,rejected=native_plan(from,target)
        if plan or not rejected then return plan,why end
        local alternative,problem=constrained(from,target)
        if alternative then
            alternative.detour=true;alternative.avoided=why
            return alternative
        end
        return nil,"brak dostepnej drogi omijajacej niedozwolone przejscie: "..tostring(problem or why)
    end

    local function alive(op)
        return not disposed and active == op and not op.finished and op.generation == generation
    end
    local function clear(op, key)
        local handle = op[key]
        op[key] = nil
        if handle then ctx:cancel(handle) end
    end
    local function clear_timers(op)
        clear(op, "stepTimer"); clear(op, "gateTimer"); clear(op, "delayTimer")
    end
    local function end_drain(reason, unexpected, replaced)
        local pending = drain
        if not pending then return end
        drain = nil
        clear(pending, "timer")
        if not replaced then
            ctx:emit("chimera.walk.stopped", { target=pending.id, map_room=pending.map, reason=reason })
        end
        if unexpected then
            ctx:emit("chimera.paczki.travel.unexpected", { reason=reason, room=unexpected,
                expected=pending.id, map_room=pending.map })
        end
        ctx:emit("chimera.paczki.travel.settled", { token=pending })
    end
    local function complete(op, ok, reason, keepStep)
        if active ~= op or op.finished or op.generation ~= generation then return end
        op.finished, active = true, nil
        clear_timers(op)
        local event = { target=op.plan.targetId, map_room=op.plan.target, reason=reason }
        local closing=type(ctx.isClosed)=="function" and ctx:isClosed()
        if keepStep and not closing and op.phase == "moving" and op.step then
            -- Cancelling cannot recall a step already accepted by the server.
            -- Keep only its exact acknowledgement classified as owned walking;
            -- never execute another step or call this operation again.
            drain = { id=op.step.id, map=op.step.map, fromId=op.fromId, fromMap=op.fromMap }
            local pending = drain
            pending.timer = ctx:timer(STEP_TIMEOUT, function()
                if drain == pending then end_drain("nie potwierdzono przerwanego kroku", gmcp.room() or {}) end
            end)
            ctx:emit("chimera.paczki.travel.pending", { token=pending })
        end
        -- Callbacks may synchronously cancel/start another operation.
        if not drain then ctx:emit(ok and "chimera.walk.arrived" or "chimera.walk.stopped", event) end
        op.done({ ok=ok, reason=reason })
    end
    local function send(op, command)
        if not alive(op) then return false end
        local token = op.token
        local reason = blocked(command)
        if reason then complete(op, false, reason); return false end
        local ok, result = pcall(opts.send, command)
        if alive(op) and op.token == token and (not ok or result == false) then
            complete(op, false, "nie udalo sie wyslac komendy drogi")
            return false
        end
        return alive(op)
    end
    local function current()
        return mapper.current_room(), gmcp.room() or {}
    end
    local function available(step, room)
        for _, target in pairs(room.exits or {}) do if target == step.id then return true end end
        return false
    end
    local function actual_command(step, room)
        local planned = direction(step.cmd)
        if (room.exits or {})[DIRECTION[planned] or step.cmd] == step.id then return step.cmd end
        local best
        for command, target in pairs(room.exits or {}) do
            if type(command)=="string" and target == step.id and not blocked(command) and (not best or command < best) then best = command end
        end
        return best or step.cmd
    end
    local function record(value)
        if type(value) == "string" then return { command=value } end
        return type(value) == "table" and value or nil
    end
    local function applies(value, step)
        if value.to then return value.to == step.id end
        return not value.direction or direction(value.direction) == direction(step.cmd)
    end
    local function native_gate(id)
        if not locations.gate then return nil end
        local cache=planning() and planning_cache()
        if not cache then return locations.gate(id) end
        cache.roadGates=cache.roadGates or {}
        if cache.roadGates[id]==nil then cache.roadGates[id]=locations.gate(id) or false end
        return cache.roadGates[id] or nil
    end
    local function gate_for(fromId, step)
        local edges = opts.gatesByEdge or opts.gates_by_edge or {}
        local edge = record((type(edges[fromId]) == "table" and edges[fromId][step.id]) or edges[fromId .. "|" .. step.id])
        if edge and edge.command then return edge end
        local explicit = record((opts.gates or {})[fromId])
        if explicit then return applies(explicit, step) and explicit.command and explicit or nil end
        local source = record(native_gate(fromId))
        local target = record((opts.gates or {})[step.id]) or record(native_gate(step.id))
        if source and source.command and target and applies(source, step) then return source end
    end

    -- Timing geometry is independent of map weights: a weight of forty is
    -- not forty seconds. Only the exact planned edges contribute steps and
    -- optional gate work; callers supply observed latency and current pace.
    function api.metrics(plan)
        if type(plan)~="table" or type(plan.steps)~="table" or type(plan.fromId)~="string" or
            type(plan.targetId)~="string" then return nil,"brak planu do oszacowania czasu" end
        local result={steps=0,delayUnits=0,gates=0,ferries=0,ferryKeys={}}
        local parts={"road",plan.fromId,plan.targetId}
        local previous=plan.fromId
        for _,step in ipairs(plan.steps) do
            cooperate()
            if type(step)~="table" or type(step.id)~="string" or type(step.cmd)~="string" then
                return nil,"niepelny plan do oszacowania czasu"
            end
            result.steps=result.steps+1
            parts[#parts+1]=step.cmd;parts[#parts+1]=step.id
            local gate=gate_for(previous,step)
            if gate then
                result.gates=result.gates+1
                parts[#parts+1]="gate:"..tostring(gate.command)
            end
            previous=step.id
        end
        result.delayUnits=math.max(0,result.steps-1);result.delays=result.delayUnits
        local first,second=2166136261,5381
        local text=table.concat(parts,"|")
        for index=1,#text do
            if index%128==0 then cooperate() end
            local byte=text:byte(index)
            first=(first*131+byte)%4294967296
            second=(second*65599+byte)%4294967291
        end
        result.signature="road1:"..string.format("%.0f",first)..":"..string.format("%.0f",second)
        return result
    end

    local start_step, move_step, open_gate, queue_crossing
    local function schedule(op, seconds, callback)
        clear(op, "delayTimer")
        local token = op.token
        op.delayTimer = ctx:timer(seconds, function()
            if not alive(op) or op.token ~= token then return end
            op.delayTimer = nil
            ctx:emit("chimera.paczki.timing.delay",{seconds=seconds})
            if not alive(op) or op.token~=token then return end
            callback()
        end)
    end
    move_step = function(op)
        if not alive(op) then return end
        local why=blocked_room(op.step.map)
        if why then complete(op,false,why);return end
        local map, room = current()
        if map ~= op.fromMap or room.id ~= op.fromId then
            complete(op, false, "lokacja zmienila sie przed krokiem")
            return
        end
        clear(op, "gateTimer"); clear(op, "delayTimer")
        op.command = actual_command(op.step, room)
        op.phase = "moving"
        local token = op.token
        op.stepTimer = ctx:timer(STEP_TIMEOUT, function()
            if not alive(op) or op.token ~= token or op.phase ~= "moving" then return end
            op.stepTimer = nil
            complete(op, false, "brak potwierdzenia kroku; ruch nie zostanie powtorzony")
        end)
        send(op, op.command)
    end
    queue_crossing = function(op)
        if not alive(op) then return end
        clear(op, "gateTimer")
        op.phase = "gate-step"
        -- A queued crossing can still be cancelled if the gate closes in the
        -- same server response. This delay is not an opening confirmation.
        schedule(op, math.max(0.05, step_delay(op)), function() move_step(op) end)
    end
    open_gate = function(op)
        if not alive(op) then return end
        if not op.gate or not op.gate.command then complete(op, false, "zamkniete przejscie bez znanej komendy otwarcia"); return end
        if op.gateOpens >= MAX_GATE_OPENS then complete(op, false, "brama pozostala zamknieta po dwoch probach"); return end
        clear_timers(op)
        op.gateOpens = op.gateOpens + 1
        op.phase = "gate"
        local token = op.token
        op.gateTimer = ctx:timer(GATE_TIMEOUT, function()
            if not alive(op) or op.token ~= token or op.phase ~= "gate" then return end
            op.gateTimer = nil
            complete(op, false, "brama nie potwierdzila otwarcia")
        end)
        if opts.say then opts.say("Otwieram brame i czekam na potwierdzenie.") end
        send(op, op.gate.command)
    end
    start_step = function(op)
        if not alive(op) then return end
        local step = op.plan.steps[op.index]
        if not step then complete(op, true); return end
        local map, room = current()
        if map ~= op.fromMap or room.id ~= op.fromId then complete(op, false, "lokacja nie zgadza sie z poczatkiem kroku"); return end
        local why=blocked_room(step.map)
        if why then complete(op,false,why);return end
        op.token = op.token + 1
        op.step, op.command, op.gateOpens, op.hmmFallback = step, actual_command(step, room), 0, false
        op.gate = gate_for(room.id, step)
        if op.gate and not available(step, room) then open_gate(op)
        else move_step(op) end
    end

    local function drain_room(map, room, snapshot)
        local pending = drain
        if not pending then return end
        room = room or gmcp.room() or {}
        if room.id == pending.fromId and map == pending.fromMap then return end
        -- room.info can precede the mapper's update; the following moved event
        -- must still verify the map number as well as the GMCP hash.
        if snapshot and room.id == pending.id and map ~= pending.map then return end
        if room.id == pending.id and map == pending.map then
            -- The issued step remains ours after cancellation. Capture its
            -- actual ACK before settled listeners evaluate emergency retreat.
            remember_edge({fromId=pending.fromId,fromMap=pending.fromMap,toId=pending.id,toMap=pending.map})
            end_drain("potwierdzono przerwany krok")
        else forget_edges();end_drain("nieoczekiwana lokacja po przerwanym kroku", room) end
    end
    local function moved(map, room)
        if drain then drain_room(map, room) end
        room = room or gmcp.room() or {}
        if emergencyEdge then emergency_position(map,room,false) end
        local op = active
        if not op or not alive(op) then
            if lastEdge and (map~=lastEdge.toMap or room.id~=lastEdge.toId) then forget_edges() end
            return
        end
        if map == op.fromMap and room.id == op.fromId then return end -- duplicate snapshot
        if op.phase ~= "moving" then forget_edges();complete(op, false, "lokacja zmienila sie bez oczekiwanego kroku"); return end
        local step = op.step
        if not step or map ~= step.map or room.id ~= step.id then forget_edges();complete(op, false, "nieoczekiwana lokacja po kroku"); return end
        remember_edge({fromId=op.fromId,fromMap=op.fromMap,toId=step.id,toMap=step.map})
        clear_timers(op)
        op.token = op.token + 1
        op.fromMap, op.fromId, op.index, op.phase = map, room.id, op.index + 1, "delay"
        if op.index > #op.plan.steps then complete(op, true)
        else schedule(op, step_delay(op), function() start_step(op) end) end
    end

    function api.run(plan, done)
        if disposed then done({ ok=false, reason="droga jest wylaczona" }); return function() end end
        if drain then
            end_drain("nowa nawigacja przed potwierdzeniem poprzedniego kroku")
            done({ ok=false, reason="poprzedni krok nie zostal jeszcze potwierdzony" })
            return function() end
        end
        local previousGeneration = generation
        if active then complete(active, false, "zastapiono nawigacje") end
        if disposed or generation ~= previousGeneration then done({ ok=false, reason="nawigacja zostala zastapiona" }); return function() end end
        if type(plan) ~= "table" or type(plan.steps) ~= "table" or
            type(plan.from) ~= "number" or plan.from <= 0 or type(plan.target) ~= "number" or plan.target <= 0 then
            done({ ok=false, reason="brak planu drogi" }); return function() end
        end
        local copy = { from=plan.from, target=plan.target, fromId=plan.fromId or hash(plan.from),
            targetId=plan.targetId or hash(plan.target), steps={} }
        for i, step in ipairs(plan.steps) do
            if type(step) ~= "table" or type(step.cmd) ~= "string" or type(step.map) ~= "number" or step.map <= 0 or
                type(step.id) ~= "string" or step.id == "" or hash(step.map) ~= step.id or blocked(step.cmd) then
                done({ ok=false, reason="nieprawidlowy krok planu drogi" }); return function() end
            end
            local why=blocked_room(step.map)
            if why then done({ok=false,reason=why});return function() end end
            copy.steps[i] = { cmd=step.cmd, map=step.map, id=step.id }
        end
        local map, room = current()
        if not copy.fromId or not copy.targetId or hash(copy.from) ~= copy.fromId or hash(copy.target) ~= copy.targetId or
            map ~= copy.from or room.id ~= copy.fromId then
            done({ ok=false, reason="plan zaczyna sie w innej lokacji" }); return function() end
        end
        if (#copy.steps == 0 and copy.from ~= copy.target) or
            (#copy.steps > 0 and (copy.steps[#copy.steps].map ~= copy.target or copy.steps[#copy.steps].id ~= copy.targetId)) then
            done({ ok=false, reason="plan konczy sie w innej lokacji" }); return function() end
        end
        generation = generation + 1
        local op = { generation=generation, plan=copy, done=done, index=1, token=0,
            fromMap=copy.from, fromId=copy.fromId, phase="starting" }
        active = op
        if plan.detour and opts.say then opts.say("Omijam wylaczony skrot. Ide dostepnym objazdem z mapy.") end
        ctx:emit("chimera.walk.started", { target=copy.targetId, map_room=copy.target })
        if alive(op) then start_step(op) end
        return function() if alive(op) then complete(op, false, "przerwane", true) end end
    end
    function api.phase() return active and active.phase or "idle" end
    function api.continueAfterAttack()
        local op=active
        if not op or not alive(op) then return false end
        op.combatTransit=true
        if op.phase=="delay" then
            clear(op,"delayTimer")
            start_step(op)
        elseif op.phase=="gate-step" then
            schedule(op,0.05,function() move_step(op) end)
        end
        -- An already issued movement or gate opener still needs its exact
        -- acknowledgement. Faster transit never duplicates an in-flight send.
        return true
    end
    function api.endCombatTransit()
        local op=active
        if not op or not alive(op) or not op.combatTransit then return false end
        op.combatTransit=nil
        if op.phase=="delay" then schedule(op,delay(),function() start_step(op) end)
        elseif op.phase=="gate-step" then schedule(op,math.max(0.05,delay()),function() move_step(op) end) end
        return true
    end
    function api.lastEdge()
        local map,room=current()
        if not lastEdge then return nil end
        if hash(lastEdge.fromMap)~=lastEdge.fromId or hash(lastEdge.toMap)~=lastEdge.toId then forget_edges();return nil end
        if map~=lastEdge.toMap or room.id~=lastEdge.toId then
            -- A fresh Room.Info may precede mapper.moved. The old edge is not
            -- valid at that instant, but its trail can survive until the exact
            -- outstanding forward/reverse acknowledgement is classified.
            if not emergencyEdge and not drain and not (active and active.phase=="moving") then forget_edges() end
            return nil
        end
        return copy_edge(lastEdge)
    end

    ctx:on("chimera.walk.started", function(event)
        -- A verified emergency reversal consumes one edge only after its ACK.
        -- Other walkers own their own history and cannot inherit this trail.
        if drain then end_drain("inne chodzenie zastapilo przerwany krok", nil, true) end
        if event and event.emergency==true and not active then
            local proof=api.lastEdge()
            if proof and event.target==proof.fromId and event.map_room==proof.fromMap then emergencyEdge=proof
            else forget_edges() end
        elseif not active then forget_edges() end
    end)
    ctx:on("chimera.walk.stopped",function(event)
        if event and event.emergency==true then forget_edges() end
    end)

    ctx:on("chimera.paczki.tempo.changed", function()
        local op = active
        if not op or not alive(op) then return end
        if op.phase == "delay" then schedule(op, step_delay(op), function() start_step(op) end)
        elseif op.phase == "gate-step" then schedule(op, math.max(0.05, step_delay(op)), function() move_step(op) end) end
    end)

    ctx:on("chimera.mapper.moved", moved)
    ctx:on("chimera.room.info", function(room)
        if emergencyEdge and room then emergency_position(mapper.current_room(),room,true)
        elseif lastEdge and room and room.id~=lastEdge.toId and
            not (drain and room.id==drain.id) and
            not (active and active.phase=="moving" and active.step and room.id==active.step.id) then forget_edges() end
        if drain then drain_room(mapper.current_room(), room, true) end
        local op = active
        if op and alive(op) and op.phase == "moving" and op.step and room and room.id == op.step.id and
            mapper.current_room() == op.step.map then moved(op.step.map, room) end
    end)
    ctx:on("chimera.mapper.lost", function()
        forget_edges()
        if drain then end_drain("utracono pozycje po przerwanym kroku", gmcp.room() or {}) end
        if active then complete(active, false, "utracono pozycje na mapie") end
    end)
    local function on_line(raw)
        local op = active
        if not op or not alive(op) then return end
        local text = norm(raw)
        local map, room = current()
        if map ~= op.fromMap or room.id ~= op.fromId then return end
        local opened = text:find("brama zostaje otwarta", 1, true) or text:find("wrota zostaja otwarte", 1, true) or
            text:find("alez brama jest przeciez otwarta", 1, true) or text:find("alez wrota sa przeciez otwarte", 1, true)
        local closed = text:find("brama zostaje zamknieta", 1, true) or text:find("wrota zostaja zamkniete", 1, true)
        if op.phase == "gate" then
            if opened then queue_crossing(op)
            elseif text == "hmm?" and not op.hmmFallback and available(op.step, room) then
                op.hmmFallback = true
                queue_crossing(op)
            end
        elseif op.phase == "gate-step" then
            if closed then clear(op, "delayTimer"); open_gate(op) end
        elseif op.phase == "moving" then
            -- A closing announcement does not prove that an in-flight move
            -- failed. Retry only a confirmed denial, never that announcement.
            local locked = text:find("wrota sa zamkniete", 1, true) or text:find("brama jest zamknieta", 1, true) or
                text:find("drzwi sa zamkniete", 1, true)
            local no_exit = text:find("nie widzisz zadnego wyjscia", 1, true)
            if text:find("nie posiadasz wystarczajacych umiejetnosci",1,true) or
                text:find("nie masz wystarczajacych umiejetnosci",1,true) then
                complete(op,false,"gra odmowila przejscia z powodu niewystarczajacych umiejetnosci")
            elseif locked or no_exit then
                if op.gate then open_gate(op)
                else complete(op, false, locked and "zamkniete przejscie bez znanej komendy otwarcia" or "mapa wskazuje niedostepne wyjscie") end
            elseif text:find("zmecz", 1, true) and text:find("nie mozesz isc", 1, true) then
                complete(op, false, "zmeczenie; krok nie zostal wykonany")
            end
        end
    end
    ctx:trigger("^", function(text) on_line(type(text) == "string" and text or rawget(_G, "line")) end)
    ctx:on("chimera.numpad.pressed", function() forget_edges();if active then complete(active, false, "przerwane klawiszem") end end)
    ctx:on("chimera.locations.key", function() forget_edges();if active then complete(active, false, "przerwane akcja lokacji") end end)
    ctx:on("chimera.step.manual",forget_edges)
    ctx:on("chimera.session.end", function()
        forget_edges()
        end_drain("rozlaczenie")
        if active then complete(active, false, "rozlaczenie") end
    end)
    ctx:on("chimera.paczki.actor.changed",function()
        forget_edges()
        end_drain("zmieniono postac")
        if active then complete(active,false,"zmieniono postac") end
    end)
    if ctx.cleanup then ctx:cleanup(function()
        disposed = true
        forget_edges()
        end_drain("przeladowanie kuriera")
        if active then complete(active, false, "przeladowanie kuriera") end
        generation = generation + 1
    end) end
    return api
end
