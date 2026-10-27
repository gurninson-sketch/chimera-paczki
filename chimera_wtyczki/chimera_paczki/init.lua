-- Chimera 5.0.0-beta.13: native plugin for the Boty registry.
-- No changes to Chimera or Kozobot are required.
package.loaded["chimera_paczki.core"] = nil
package.loaded["chimera_paczki.routes"] = nil
package.loaded["chimera_paczki.npc"] = nil
package.loaded["chimera_paczki.new_routes"] = nil
package.loaded["chimera_paczki.travel"] = nil
package.loaded["chimera_paczki.offices"] = nil
for _,module in ipairs({"scope","road","ferry","journey","transport_data","inventory","memory","path","postal","checkpoint","escape","recovery","eta","karak_transport","city","city_data","planner","updater"}) do package.loaded["chimera_paczki."..module]=nil end
local create = require("chimera_paczki.core")
local data = require("chimera_paczki.routes")
local createNavigator = require("chimera_paczki.npc")
local createOffices = require("chimera_paczki.offices")
local json = require("chimera.core.json")
local postal = require("chimera_paczki.postal")

return {
    name = "kurier_paczki",
    title = "Paczki",
    section = "boty",
    version = "1.5.19",
    related = { "bots", "walker", "automation", "npcs" },
    description = "Kurier: wybor paczek, baza /npc, doreczenia i powrot do urzedu nadania",
    deps = { "bots", "gmcp", "walker", "mapper", "npcs", "locations", "bags", "world" },

    setup = function(ctx)
        ctx=require("chimera_paczki.scope")(ctx)
        local bots = ctx:use("bots")
        local gmcp_api = ctx:use("gmcp")
        local walker = ctx:use("walker")
        local mapper = ctx:use("mapper")
        local bags=ctx:use("bags")
        local walkerSettings=ctx.app.config:view("walker")
        local eventSettings=ctx.app.config:view("events")
        local planner=require("chimera_paczki.planner")(ctx)
        local C, combatRetreat, beginRecovery, npcTransit, npcAttackRoom, npcAttackMarker, resumeNpcCourse
        local avoidedRooms={}
        local savedHazards=ctx:saved("niebezpieczne_lokacje",{})
        for id,value in pairs(type(savedHazards)=="table" and type(savedHazards.rooms)=="table" and savedHazards.rooms or {}) do
            if type(id)=="string" and #id==16 and id:match("^[0-9a-f]+$") and value==true then avoidedRooms[id]=true end
        end
        local function markHazard()
            local room=gmcp_api.room() or {};local map=mapper.current_room()
            if type(room.id)~="string" or #room.id~=16 or not room.id:match("^[0-9a-f]+$") or
                type(map)~="number" or mapper.chimera_id(map)~=room.id or avoidedRooms[room.id] then return end
            avoidedRooms[room.id]=true
            local rooms={};for id in pairs(avoidedRooms) do rooms[id]=true end
            local ok=pcall(ctx.save,ctx,"niebezpieczne_lokacje",{schema=1,rooms=rooms})
            ctx.log.warn("Omijam lokacje, w ktorej zaatakowano kuriera: "..tostring(room.name or room.id)..".")
            if not ok then ctx.log.warn("Nie zapisano blokady zagrozenia na kolejne uruchomienie profilu.") end
        end
        local pendingTravel={}
        local checkpoint=require("chimera_paczki.checkpoint")(ctx:saved("biezacy_kurs",{}),{
            save=function(state) ctx:save("biezacy_kurs",state) end,
            now=function() return os.time() end,
        })
        local memory=require("chimera_paczki.memory")(ctx:saved("sprawdzeni_adresaci",{}),{
            save=function(state) ctx:save("sprawdzeni_adresaci",state) end,
            now=function() return os.time() end,
        })
        local function timingClock()
            if type(getEpoch)=="function" then
                local ok,value=pcall(getEpoch)
                if ok and type(value)=="number" and value>=0 and value<math.huge then return value end
            end
            return os.time()
        end
        local eta=require("chimera_paczki.eta")(ctx:saved("czasy_kursow",{}),{
            save=function(state) return ctx:save("czasy_kursow",state) end,now=timingClock,
        })
        local courseTiming
        local function cancelTiming() courseTiming=nil end
        local function timingDelay(seconds,minimumUnits)
            if courseTiming and type(seconds)=="number" and seconds>=0 and seconds<math.huge then
                courseTiming.delaySeconds=courseTiming.delaySeconds+seconds
                courseTiming.pacedUnits=courseTiming.pacedUnits+1
                courseTiming.minimumDelayUnits=courseTiming.minimumDelayUnits+(tonumber(minimumUnits) or 0)
            end
        end
        -- Transport intent is independent of a parcel's source and of the
        -- runtime socket. Only canonical GMCP actors can address this store.
        local transportSaved=ctx:saved("transport_kahn_gad",{})
        local transportActors={}
        local transportFlags={"aboard","boardSeen","boardSent","bought","farePrepared","fareFinished",
            "farePending","fareUncertain","fareDeferred","departed","arrived","leaveSent","landSeen","directionUnknown","corrected"}
        local function transportKey(value)
            if type(value)~="string" or #value>80 then return nil end
            local key=C and C.norm(value) or value:lower()
            if key=="" or key:find("[%s@:;%z\1-\31\127]") then return nil end
            return key
        end
        local function transportRecord(value,key)
            if type(value)~="table" or value.schema~=1 or value.transport~="karak_ship" or transportKey(value.actor)~=key then return nil end
            local blue,black="891456eab7637380","2e1aa32a45a83107"
            if not ((value.fromHash==blue and value.toHash==black) or (value.fromHash==black and value.toHash==blue)) then return nil end
            if value.currentToHash~=nil and value.currentToHash~=blue and value.currentToHash~=black then return nil end
            local clean={schema=1,transport="karak_ship",actor=key,fromHash=value.fromHash,toHash=value.toHash,currentToHash=value.currentToHash}
            for _,field in ipairs(transportFlags) do
                if value[field]~=nil and type(value[field])~="boolean" then return nil end
                clean[field]=value[field]==true
            end
            return clean
        end
        if type(transportSaved)=="table" and transportSaved.schema==1 and type(transportSaved.actors)=="table" then
            local count=0
            for name,value in pairs(transportSaved.actors) do
                local key=transportKey(name)
                local clean=key and transportRecord(value,key)
                if clean and count<32 then transportActors[key]=clean;count=count+1 end
            end
        end
        local function loadTransport(actor)
            local key=transportKey(actor)
            return key and transportRecord(transportActors[key],key) or nil
        end
        local function saveTransport(actor,state)
            local key=transportKey(actor)
            if not key then return false end
            local clean=state and transportRecord(state,key)
            if state~=nil and not clean then return false end
            local candidate,count={},0
            for name,record in pairs(transportActors) do
                if name~=key then candidate[name]=transportRecord(record,name);count=count+1 end
            end
            if clean and count>=32 then return false end
            candidate[key]=clean
            local good,result=pcall(ctx.save,ctx,"transport_kahn_gad",{schema=1,actors=candidate})
            if not good or result==false then return false end
            transportActors=candidate
            return true
        end
        local inventory
        local fareCashReady,seenWithdrawals,seenCoinStores=false,0,0
        inventory=require("chimera_paczki.inventory")(ctx,bags,{
            openTimeout=30,
            send=function(command) return C:sendCommand(command) end,
            say=function(message) ctx.log.info(message) end,
            autoDetect=function() return C and C.config.autoBackpack~=false end,
            openClose=function() return ctx.app.config:view("bags").otwieraj~=false end,
            onStateChanged=function()
                if inventory then
                    local taken=inventory.coinWithdrawalReceipt and inventory.coinWithdrawalReceipt() or 0
                    local stored=inventory.coinReceipt()
                    if taken>seenWithdrawals then
                        fareCashReady=C and (C.mode=="running" or C.mode=="resting" or C.mode=="recovering") or false
                    end
                    local advanced=stored>seenCoinStores
                    seenWithdrawals,seenCoinStores=taken,stored
                    if advanced then
                        fareCashReady=false
                        local character=gmcp_api.char()
                        ctx:emit("chimera.paczki.coins.stored",{receipt=stored,actor=character and C and C.norm(character.name) or nil})
                    end
                end
                if C then C:checkpoint();C:tryResumeRest() end
            end,
        })
        local navigator
        navigator = createNavigator(ctx,bots,gmcp_api,walker,mapper,ctx:use("npcs"),ctx:use("locations"),function(command)
            return C:sendCommand(command)
        end,nil,{memory=memory,world=ctx:use("world"),cooperate=planner.checkpoint,planning=planner.active,planningCache=planner.cache,delay=function() return C and C:delay() or 0.5 end,say=function(message) ctx.log.info(message) end,
            blockRoom=function(_,id) return avoidedRooms[id]==true,"zapamietane miejsce ataku na kuriera" end,
            prepareFare=function(done)
                if fareCashReady then done({ok=true,skipped=true});return function() end end
                return inventory.takeCoins(done)
            end,
            finishFare=function(done) return inventory.stowCoins(done) end,
            actor=function() local character=gmcp_api.char();return character and C and C.norm(character.name) or nil end,
            loadTransport=loadTransport,saveTransport=saveTransport,
            coinReceipt=inventory.coinReceipt,
            coinsUncertain=function() return inventory.exportState().coinsUncertain==true end,
            onCombat=function(kind,state) if combatRetreat then combatRetreat(kind,state) end end,
            onRoadArrival=function()
                if npcTransit and beginRecovery then
                    navigator.endCombatTransit()
                    npcTransit=false
                    beginRecovery(npcAttackMarker)
                    return true
                end
                return false
            end,
            onSearchStart=function(route) if C then C:startRecipientSearch(route) end end,
            searchBudget=function() return C and C:searchRemaining() or 300 end,
            onSearchWait=function(route,scope)
                if C and C.mode=="running" then
                    C.phase="searchingCity"
                    C.lastPause="Szukam "..route.name.." w miescie "..tostring(scope and scope.name or "adresata")..". Po obchodzie sprawdze ponownie."
                    ctx.log.info(C.lastPause)
                end
            end,
            onWait=function(route)
                if C and C.mode=="running" then
                    C.phase="waitingNpc"
                    C.lastPause="Czekam na "..route.name.." w jego znanej lokacji. Doreczenie wznowi sie po pojawieniu adresata."
                end
            end})
        local function textSignature(commands)
            local sum=7
            for byte in table.concat(commands,"|"):gmatch(".") do sum=(sum*67+byte:byte())%4294967291 end
            return "text:"..#commands..":"..string.format("%.0f",sum)
        end
        local function timingQuery(offer,route,source,delay)
            if type(route)~="table" then return nil end
            local snapshot=route.timing
            if route.native and not snapshot then snapshot=navigator.timing(route,source) end
            local cycle=snapshot and snapshot.cycle
            local metrics
            if cycle then
                metrics={steps=cycle.steps,delayUnits=cycle.delayUnits or cycle.delays,
                    gates=cycle.gates,ferries=cycle.ferries,ferryKeys={},signature=cycle.signature,
                    handlingSeconds=8,minimumDelayUnits=route.postal and 0 or 1,minimumDelaySeconds=0.5}
                for _,key in ipairs(cycle.ferryKeys or {}) do metrics.ferryKeys[#metrics.ferryKeys+1]=key end
                metrics.delayUnits=metrics.delayUnits+(route.postal and 3 or 5)
            elseif not route.native and type(route.commands)=="table" then
                local steps=2*#route.commands
                metrics={steps=steps,delayUnits=steps+3,gates=0,ferries=0,ferryKeys={},
                    signature=textSignature(route.commands),handlingSeconds=8,minimumDelayUnits=1,minimumDelaySeconds=0.5}
            else return nil end
            local searchSeconds=type(route.searchSeconds)=="number" and route.searchSeconds or 0
            if searchSeconds>0 and searchSeconds<math.huge then
                metrics.handlingSeconds=(metrics.handlingSeconds or 8)+searchSeconds
                metrics.signature=(metrics.signature or "").."|citysearch1"
            end
            if type(offer.kg)=="number" and offer.kg>=0 and offer.kg<math.huge then
                metrics.signature=(metrics.signature or "")..string.format("|kg:%.2f",offer.kg)
            end
            local origin=source and source.id or (C and C.staticSource~=false and "6f2c03461c2f1438" or nil)
            return {actor=C and C.actor,sourceId=origin,recipient=offer.name or route.name,
                postal=route.postal==true,periodic=navigator.isPeriodic(route),timing=metrics,delay=delay,
                uncertain=snapshot and snapshot.uncertain==true or false,parcelKg=offer.kg,
                fareUnknown=cycle and cycle.fareUnknown==true or false,searchSeconds=searchSeconds}
        end
        local function estimateTime(offer,route,source,delay)
            local query=timingQuery(offer,route,source,delay)
            if not query then return nil end
            local estimate=eta.estimate(query)
            if estimate and query.uncertain then estimate.confidence="low";estimate.uncertain=true end
            if estimate and query.fareUnknown then estimate.fareUnknown=true end
            if estimate and query.searchSeconds>0 then estimate.searchSeconds=query.searchSeconds;estimate.uncertain=true;estimate.confidence="low" end
            return estimate
        end
        local function validTimingJob(job)
            local t=courseTiming
            return t and t.actor==C.actor and type(job)=="table" and t.job==job and
                C.norm(job.name)==C.norm(t.recipient) and job.recipientConfirmed==true and
                job.source and job.source.id==t.sourceId and t.delay==C:delay()
        end
        local function startTiming(offer,source)
            cancelTiming()
            if npcTransit or not C.actor or not source or not source.id or not offer.eta then return end
            local here=navigator.current()
            if here.id~=source.id or here.map~=source.map or mapper.chimera_id(here.map)~=here.id then return end
            local query=timingQuery(offer,offer.route,source,C:delay())
            if not query or not query.actor then return end
            query.started=timingClock();query.delaySeconds=0;query.pacedUnits=0;query.minimumDelayUnits=0
            courseTiming=query
        end
        local function pickupTiming(job)
            local t=courseTiming
            if not t or t.actor~=C.actor or C.norm(job.name)~=C.norm(t.recipient) or
                not job.recipientConfirmed or not job.source or job.source.id~=t.sourceId then cancelTiming();return end
            local query=timingQuery({name=job.name,kg=t.parcelKg},job.route,job.source,C:delay())
            local estimate=query and eta.estimate(query)
            local original=eta.estimate(t)
            if not estimate or not original or estimate.signature~=original.signature then cancelTiming();return end
            t.job=job;t.pickup=true
        end
        local function handoverTiming(job)
            if not validTimingJob(job) or not courseTiming.pickup then cancelTiming();return end
            local proof=navigator.deliveryEvidence(job.route)
            if not proof or proof.verified~=true then cancelTiming();return end
            courseTiming.handover=true;courseTiming.verified=true;courseTiming.destinationId=proof.roomHash
        end
        local function rewardTiming(job)
            if not validTimingJob(job) or not courseTiming.handover then cancelTiming();return end
            courseTiming.reward=true
        end
        local function finishTiming(job,place)
            if not validTimingJob(job) then cancelTiming();return end
            local t=courseTiming
            if not t.pickup or not t.handover or not t.reward or not job.delivered or job.coinsPending or
                C.awaitingPickup or C.awaitingDelivery or C.awaitingReturn or C.awaitingReward then cancelTiming();return end
            local here=navigator.current()
            local expected=t.postal and t.destinationId or t.sourceId
            if not place or place.id~=expected or here.id~=expected or here.map~=place.map or mapper.chimera_id(here.map)~=expected then cancelTiming();return end
            t.seconds=timingClock()-t.started;t.completed=true
            -- Only the strict evidence allowlist is stored by the model.
            local ok,why=eta.remember(t)
            cancelTiming()
            if not ok then ctx.log.warn("Nie zapisano pomiaru czasu kursu: "..tostring(why)) end
        end
        local offices = createOffices(ctx,navigator,{planning=planner.active,
            loadCapabilities=function() return ctx:saved("mozliwosci_poczt",{}) end,
            saveCapabilities=function(snapshot) return ctx:save("mozliwosci_poczt",snapshot) end,
        })
        local owned, finishing, disposed = false, false, false
        local queued, runToken = nil, 0
        local launch, waitSession, cancelSession, checkSession
        local sessionWait, sessionTimer, sessionRetry, sessionDeadline
        local emergency, recovery, emergencyLease, emergencyActor, recoveryMark, automaticHandoff, attackRoom
        local function ownCombat(state)
            if type(state)~="table" then return false end
            local room=gmcp_api.room() or {}
            if state.room and state.room~=room.id then return false end
            if type(state.primary)=="string" and state.primary~="" then return true end
            local character=gmcp_api.char() or {}
            for _,relation in ipairs(type(state.relations)=="table" and state.relations or {}) do
                if character.id and (relation.attacker==character.id or relation.defender==character.id) then return true end
            end
            return false
        end
        local function npcAttack(kind,state)
            if kind=="attack" and type(state)=="table" and state.player==false then return true end
            local combat=kind=="state" and state or gmcp_api.combat()
            local snapshot=gmcp_api.entities() or {};local room=gmcp_api.room() or {}
            if kind=="text" and state and state.name and snapshot.room==room.id then
                local found
                for _,entity in ipairs(snapshot.entities or {}) do
                    if C.norm(entity.name)==C.norm(state.name) then
                        if found or entity.kind~="npc" then return false end
                        found=entity
                    end
                end
                if found then return true end
            end
            if type(combat)~="table" or snapshot.room~=room.id then return false end
            local char=gmcp_api.char() or {};local enemies={}
            if type(combat.primary)=="string" and combat.primary~="" then enemies[combat.primary]=true end
            for _,relation in ipairs(combat.relations or {}) do
                if relation.defender==char.id and relation.attacker then enemies[relation.attacker]=true end
                if relation.attacker==char.id and relation.defender then enemies[relation.defender]=true end
            end
            local found=false
            for id in pairs(enemies) do
                local match
                for _,entity in ipairs(snapshot.entities or {}) do if entity.id==id then match=entity;break end end
                if not match or match.kind~="npc" then return false end
                found=true
            end
            return found
        end
        local function cancelEmergency(reason)
            npcTransit=false
            navigator.endCombatTransit()
            if not emergencyLease then return end
            emergencyLease,emergencyActor=nil,nil
            if emergency then emergency.cancel(reason or "Odwrót anulowany.") end
            if recovery then recovery.cancel(reason) end
        end
        local function sessionReady(expected)
            local character=gmcp_api.char()
            if not expected or not character or C.norm(character.name)~=C.norm(expected) then
                return false,"Czekam na aktualne dane postaci GMCP."
            end
            local room=gmcp_api.room();local map=mapper.current_room()
            if not gmcp_api.connected() or not room or not room.id or type(map)~="number" or map<=0 or mapper.chimera_id(map)~=room.id then
                return false,"Czekam na aktualna pozycje GMCP na mapie."
            end
            return true
        end
        local function active()
            return C and (C.mode == "running" or C.mode == "learning" or C.mode == "resting" or C.mode=="recovering")
        end
        local function currentOffice()
            local source=navigator.current()
            if not source or type(source.map)~="number" or source.map<=0 or not source.id then return end
            if postal.disabled(source.id) then return end
            for _,known in ipairs(offices.catalogue()) do
                if source.id==known.id then
                    source.name=known.name;source.city=known.city;source.staticNuln=known.staticNuln==true
                    return source
                end
            end
            local name=C.norm(source.name):gsub("%.$", "")
            if name=="poczta" or name:match("^poczta ") or name:match("^urzad pocztowy") or name:match("^glowny urzad pocztowy") or name:match("^glowna sala poczty") then
                source.staticNuln=source.id=="6f2c03461c2f1438";return source
            end
        end
        C = create(data, {
            send = function(command)
                if disposed or not owned then error("Bot paczki nie ma sterowania") end
                ctx:send(command)
            end,
            say = function(message)
                ctx.log.info((message:gsub("/kurier", "/paczki")))
            end,
            schedule = function(seconds, callback) return ctx:timer(seconds, callback) end,
            cancel = function(id) ctx:cancel(id) end,
            now = function() return os.time() end,
            stepDelay=function(delay,source)
                return source=="walker" and (tonumber(walkerSettings.opoznienie) or 0.5) or delay
            end,
            tempoChanged=function() cancelTiming();ctx:emit("chimera.paczki.tempo.changed") end,
            estimateTime=estimateTime,startTiming=startTiming,pickupTiming=pickupTiming,
            handoverTiming=handoverTiming,rewardTiming=rewardTiming,finishTiming=finishTiming,
            cancelTiming=cancelTiming,timingDelay=timingDelay,
            travelPending=function() return next(pendingTravel)~=nil end,
            actorChanged=function() fareCashReady=false;ctx:emit("chimera.paczki.actor.changed") end,
            combatStarted=function(evidence) if combatRetreat then combatRetreat("text",evidence) end end,
            lowHealth=function() if beginRecovery then beginRecovery() end end,
            combatTransit=function() return npcTransit==true end,
            vitals = gmcp_api.vitals,
            restLimits = function()
                return {stop=math.min(tonumber(walkerSettings.zmeczenie_stop) or 80,tonumber(eventSettings.prog_zmeczenie) or 80),
                    start=tonumber(walkerSettings.zmeczenie_start) or 20,hp=tonumber(eventSettings.prog_hp) or 30}
            end,
            inventory=function(action,done) return inventory[action](done) end,
            bankPlace=function(kind)
                local id=kind=="bank" and "1b91bfe5e44cd714" or kind=="office" and "6f2c03461c2f1438" or
                    kind=="street" and "265a3d02827b17ca" or nil
                if not id then return end
                local map=getRoomIDbyHash(id)
                if type(map)~="number" or map<=0 or map~=math.floor(map) or mapper.chimera_id(map)~=id then return end
                return {id=id,map=map,name=kind=="bank" and "Bank w Nuln" or "Poczta w Nuln",city="Nuln",staticNuln=kind=="office"}
            end,
            bankExchange=inventory.denominate,
            parcelState=inventory.setParcelState,
            coinReceipt=function() return inventory.coinReceipt() end,
            inventoryState=inventory.exportState,
            restoreInventory=inventory.restoreState,
            saveRun=checkpoint.put,
            loadRun=checkpoint.get,
            forgetRun=checkpoint.forget,
            actor=function() local character=gmcp_api.char();return character and character.name end,
            sessionReady=sessionReady,
            restorePlace=function(place)
                local map=place and getRoomIDbyHash(place.id)
                if type(map)~="number" or map<=0 or map~=math.floor(map) or mapper.chimera_id(map)~=place.id then return end
                return {id=place.id,map=map,name=place.name,city=place.city,staticNuln=place.staticNuln}
            end,
            save = function(state) ctx:save("ustawienia_i_trasy", state) end,
            position = navigator.current,
            source = currentOffice,
            currentOffice = currentOffice,
            resolveOffice = function(query) return offices.resolve(query) end,
            canDispatch=offices.canDispatch,markNoDispatch=offices.markNoDispatch,
            clearTravelIntent = navigator.clearIntent,
            resolveRoute = navigator.resolve,
            planWork=planner.run,cooperate=planner.checkpoint,planning=planner.active,
            deliveryEvidence=navigator.deliveryEvidence,
            deliveryReady=navigator.deliveryReady,
            canWaitFor=navigator.canWaitFor,
            canSearchFor=navigator.canSearchFor,
            recipientAbsent=navigator.recipientAbsent,
            learnDelivery=memory.remember,
            nextOffice = function(source)
                offices.markEmpty(source)
                return offices.next(source)
            end,
            officeWorking = offices.clear,
            resetOffices = offices.clearAll,
            navigate = function(route,returning,done)
                if returning then return navigator.returnTo(route,done) end
                return navigator.navigate(route,done)
            end,
        }, ctx:saved("ustawienia_i_trasy", {}))
        C.needsResumeValidation=checkpoint.count()>0
        local knownChar=gmcp_api.char()
        if knownChar and knownChar.name then C:identifyActor(knownChar.name,true) end
        local function workingKarak()
            local office=postal.resolve("Poczta w Karak Varn")
            local map=office and getRoomIDbyHash(office.id)
            if type(map)=="number" and map>0 and mapper.chimera_id(map)==office.id then
                office.map=map;return office
            end
        end
        local function repairOfficeChoice(command)
            local ready=not C.job or (C.job.delivered and not C.job.coinsPending and
                not C.awaitingPickup and not C.awaitingDelivery and not C.awaitingReturn and not C.awaitingReward)
            local office=workingKarak()
            if not ready or not office then return command end
            if C.relocation and C.relocation.to and postal.disabled(C.relocation.to.id) then
                C.relocation.to=office;C:checkpoint()
            end
            local here=navigator.current()
            local action=C.norm(command):match("^(%S+)")
            if C.source and postal.disabled(C.source.id) and (action=="wznow" or action=="resume") and not C.relocation then
                ctx.log.info("Zapisana placowka nie obsluguje paczek. Wznawiam prace w dzialajacej poczcie Karak Varn.")
                return "poczta Karak Varn"
            end
            if here and postal.disabled(here.id) and (action=="start" or action=="wznow" or action=="resume") then
                ctx.log.info("Ta placowka Karak Varn nie obsluguje paczek. Przechodze do dzialajacej poczty.")
                return "poczta Karak Varn"
            end
            return command
        end

        -- Retain native cancellation: /bot stop, the numpad, low HP and a
        -- teleport all end the manager's run before any further courier send.
        local rawPause, rawStop = C.pause, C.stop
        function C:pause(reason,quiet)
            if cancelSession then cancelSession(nil) end
            if automaticHandoff then rawPause(self,reason,true);return end
            cancelEmergency(reason)
            rawPause(self, reason,quiet)
            if owned and not finishing then bots.stop(reason or "kurier wstrzymany") end
        end
        function C:stop(reason)
            cancelEmergency(reason)
            finishing = true
            rawStop(self, reason)
            finishing = false
            if owned then ctx:emit("chimera.paczki.zakonczono", { token = runToken }) end
        end
        ctx:on("chimera.bots.changed", function(status)
            if sessionWait and status and not status:match("^Bot paczki[: ]") then
                cancelSession("Inny bot przejal sterowanie; oczekiwanie na GMCP anulowane.")
            end
            if owned and (not status or not status:match("^Bot paczki[: ]")) then
                cancelEmergency("Sterowanie kuriera zakonczone.")
                owned = false
                if active() or C.phase=="escaping" or next(C.timers) then C:stop("Zatrzymano przez glowny modul Boty.") end
            end
        end)

        local function endEmergency(result)
            if not emergencyLease then return end
            if result.ok then
                ctx.log.warn("Potwierdzono krok odwrotu. Regeneruje sily i wyznacze objazd miejsca ataku.")
                beginRecovery(recoveryMark)
                return
            end
            emergencyLease,emergencyActor=nil,nil
            local reason=result.ok and "Potwierdzono krok odwrotu. Kurs zachowany i wstrzymany; sprawdz sytuacje przed wznowieniem." or
                ("Nie potwierdzono odwrotu: "..tostring(result.reason or "brak danych")..". Przejmij sterowanie postacia; kurs pozostaje zapisany.")
            C.lastPause=reason;C.phase="idle"
            ctx.log.warn(reason)
            if owned then bots.stop(reason) end
        end
        emergency=require("chimera_paczki.escape")(ctx,{
            gmcp=gmcp_api,mapper=mapper,
            allow=function() return not disposed and owned and emergencyLease and C.actor==emergencyActor end,
            send=function(command)
                if not owned or not emergencyLease or disposed then return false end
                C.ownSend=true
                local ok,problem=pcall(ctx.send,ctx,command)
                C.ownSend=false
                if not ok then error(problem) end
            end,
            say=function(message) ctx.log.warn(message) end,
            onDone=endEmergency,
        })
        recovery=require("chimera_paczki.recovery")(ctx,{
            gmcp=gmcp_api,mapper=mapper,
            allow=function() return not disposed and owned and emergencyLease and C.actor==emergencyActor end,
            limits=function() return {hp=math.max(80,(tonumber(eventSettings.prog_hp) or 30)+10),
                start=tonumber(walkerSettings.zmeczenie_start) or 20} end,
            send=function(command)
                if not owned or not emergencyLease or disposed then return false end
                C.ownSend=true;local ok,problem=pcall(ctx.send,ctx,command);C.ownSend=false
                if not ok then error(problem) end
            end,
            refreshCombat=function()
                if type(sendGMCP)=="function" then
                    pcall(sendGMCP,'Core.Supports.Remove ["Chimera.Combat"]')
                    pcall(sendGMCP,'Core.Supports.Add ["Chimera.Combat 2"]')
                end
            end,
            onReady=function()
                if not owned or not emergencyLease or not sessionReady(C.actor) then return false end
                automaticHandoff=true
                C.mode="paused";C.phase="idle"
                local ok,why=pcall(C.command,C,"wznow")
                automaticHandoff=nil
                if not owned or C.mode=="stopped" then
                    emergencyLease,emergencyActor=nil,nil
                    return true
                end
                if ok and (C.mode=="running" or C.mode=="resting" or C.mode=="learning") then
                    emergencyLease,emergencyActor=nil,nil
                    ctx.log.info("Sily odzyskane i walka zakonczona. Kontynuuje zapisany kurs wyznaczona droga.")
                    return true
                end
                C.mode="recovering";C.phase="recovering"
                C.lastPause=ok and (C.lastPause or "Czekam na dostepna droge omijajaca zagrozenie.") or tostring(why)
                ctx.log.warn("Kurs zachowany; automatyczna kolejna proba za 30 s: "..C.lastPause)
                return false
            end,
            onFailure=function(reason) if emergencyLease then C:pause(reason) end end,
        })
        beginRecovery=function(marker)
            if disposed or not owned then return end
            if recovery.active() then return end
            if npcTransit and (gmcp_api.room() or {}).id==npcAttackRoom then return end
            if not emergencyLease then
                emergencyLease,emergencyActor=true,C.actor
                marker=marker or recovery.mark()
                rawPause(C,"Odzyskuje sily przed kontynuacja kursu.",true)
            end
            if next(pendingTravel) then
                recoveryMark=marker or recoveryMark
                C.mode="recovering";C.phase="settlingRecovery"
                C.lastPause="Czekam na potwierdzenie juz wyslanego kroku; potem automatycznie odzyskam sily i dokoncze kurs."
                return
            end
            C.mode="recovering";C.phase="recovering"
            C.lastPause="Odzyskuje sily; po koncu walki i odzyskaniu sil sam kontynuuje zapisany kurs."
            ctx.log.info(C.lastPause)
            local ok,why=recovery.start(marker or recoveryMark)
            if not ok and emergencyLease then C:pause("Nie uruchomiono regeneracji: "..tostring(why)) end
        end
        local function attemptRetreat()
            if not emergencyLease or emergency.active() or recovery.active() or next(pendingTravel) then return end
            local edge=navigator.lastEdge()
            if attackRoom and edge and edge.fromId==attackRoom and edge.toId~=attackRoom and not avoidedRooms[edge.toId] then
                ctx.log.warn("Potwierdzono odejscie z miejsca ataku juz wyslanym krokiem. Regeneruje sily w osiagnietej lokacji.")
                beginRecovery(recoveryMark)
                return
            end
            local ok,why=emergency.start(edge)
            if not ok and emergencyLease then endEmergency({ok=false,reason=why}) end
        end
        resumeNpcCourse=function()
            if recovery.active() then recovery.cancel("Kontynuuje trase po ataku NPC.") end
            if next(pendingTravel) then
                emergencyLease,emergencyActor=true,C.actor
                C.mode="recovering";C.phase="settlingNpcTransit"
                return
            end
            emergencyLease,emergencyActor=nil,nil
            if C.mode=="running" then return end
            automaticHandoff=true;C.mode="paused";C.phase="idle";C:command("wznow");automaticHandoff=nil
        end
        combatRetreat=function(kind,state)
            if kind=="state" and not ownCombat(state) then
                if npcTransit and type(state)=="table" and type(state.primary)=="string" and
                    type(state.relations)=="table" and state.room==(gmcp_api.room() or {}).id then
                    navigator.endCombatTransit();npcTransit=false
                    local vitals=gmcp_api.vitals() or {};local stop,_,hp=C:restLimits()
                    if (tonumber(vitals.hp) and tonumber(vitals.hp)<hp) or
                        (tonumber(vitals.fatigue) and tonumber(vitals.fatigue)>=stop) then beginRecovery(npcAttackMarker) end
                end
                return
            end
            if kind=="fight" and state and state.room and (gmcp_api.room() or {}).id~=state.room then return end
            local combat=gmcp_api.combat()
            if kind=="fight" and type(combat)=="table" and combat.room and combat.room~=(gmcp_api.room() or {}).id then return end
            cancelSession("Walka anulowala oczekiwanie na GMCP.")
            cancelTiming()
            if owned and active() and npcAttack(kind,state) then
                if not npcTransit then
                    npcTransit=true;npcAttackRoom=(gmcp_api.room() or {}).id;npcAttackMarker=recovery.mark()
                    ctx.log.warn("Atak NPC: kontynuuje zaplanowana trase. Nie zapisuje lokacji jako zagrozenia.")
                end
                if C.mode=="resting" or C.mode=="recovering" then resumeNpcCourse() end
                if navigator.continueAfterAttack() then return end
                -- A parcel or gate action may still be settling. Keep the
                -- owned course; the next ordinary road leg starts normally.
                return
            end
            if emergency.active() or not owned or not active() then return end
            if recovery.active() then recovery.cancel("Nowy atak podczas regeneracji.") end
            markHazard()
            attackRoom=(gmcp_api.room() or {}).id
            recoveryMark=recovery.mark()
            emergencyLease,emergencyActor=true,C.actor
            -- Cancel all forward, inventory and delivery callbacks while
            -- retaining Boty ownership for this one verified reverse step.
            rawPause(C,"Atak gracza lub nierozpoznanego przeciwnika: probuje odwrotu do ostatniej potwierdzonej lokacji.",true)
            C.phase="escaping"
            ctx.log.warn(C.lastPause)
            attemptRetreat()
        end

        bots.register("paczki", function(b)
            runToken = runToken + 1
            local thisRun = runToken
            local requested = queued
            queued = nil
            if C.needsResumeValidation and not sessionReady(C.actor) then
                waitSession(requested or "__default")
                b.stop("Oczekiwanie na GMCP; kurier wznowi sie po otrzymaniu danych")
                return
            end
            local command = repairOfficeChoice(requested or (C.job and "wznow" or "start"))
            owned = true
            -- A courier uses verified single steps, so it must start with
            -- the separate Chimera walker at rest.
            walker.stop("uruchomiono kuriera")
            if ownCombat(gmcp_api.combat()) then
                if npcAttack("state",gmcp_api.combat()) then
                    npcTransit=true;npcAttackRoom=(gmcp_api.room() or {}).id;npcAttackMarker=recovery.mark()
                    ctx.log.warn("Atak NPC: kontynuuje zaplanowana trase.")
                else C:pause("Walka trwa; kurier nie ruszy.");return end
            end
            C:command(command)
            if not active() then
                if owned then owned = false; b.stop((C.lastPause or "Sprawdz ustawienia i stan paczki."):gsub("/kurier","/paczki")) end
                return
            end
            -- The manager owns the coroutine and can cancel this wait. The
            -- transport remains the already log-tested, reply-driven engine.
            while active() do
                local ok, result = b.czekaj_na("chimera.paczki.zakonczono", function(event)
                    return event.token == thisRun
                end, 3600)
                if not ok and result and result.reason ~= "limit czasu" then return end
            end
        end, { opis = "Paczki: wybor, /npc, doreczenie i powrot. Ustawienia: /paczki",
            -- These two guards are handled below so a verified emergency
            -- reverse step runs before the manager releases ownership.
            bezpieczniki={atak_gracza=false,niskie_hp=false} })

        ctx:trigger("^", function() C:onLine(line) end)
        ctx:on("sysDataSendRequest", function(_, command)
            if not C.ownSend then fareCashReady=false end
            if emergencyLease and not C.ownSend then C:pause("Reczna komenda przerwala odwrót.") end
            if sessionWait then cancelSession("Reczna komenda anulowala oczekiwanie na GMCP.") end
            C:onCommand(command)
        end)
        ctx:on("chimera.session.end", function() fareCashReady=false;cancelSession(nil);C:disconnected() end)
        ctx:on("sysDisconnectionEvent",function()
            cancelSession("Rozlaczenie anulowalo oczekiwanie na GMCP.")
            if emergencyLease then C:pause("Rozlaczenie przerwalo odwrót.") end
        end)
        ctx:on("chimera.numpad.pressed",function()
            cancelSession("Klawisz ruchu anulowal oczekiwanie na GMCP.")
            if emergencyLease then C:pause("Klawisz ruchu przerwal odwrót.") end
        end)
        ctx:on("chimera.fight.started",function(state) combatRetreat("fight",state) end)
        ctx:on("chimera.attacked",function(state) combatRetreat("attack",state) end)
        ctx:on("chimera.paczki.travel.unexpected",function()
            if active() or emergencyLease then C:pause("Zmiana lokacji nie potwierdza ostatniego kroku; kurier zatrzymany.") end
        end)
        ctx:on("chimera.paczki.travel.pending",function(event) pendingTravel[event.token]=true end)
        ctx:on("chimera.paczki.travel.settled",function(event)
            pendingTravel[event.token]=nil
            if C.phase=="settlingNpcTransit" and not next(pendingTravel) then resumeNpcCourse()
            elseif emergencyLease and C.phase=="settlingRecovery" and not next(pendingTravel) then beginRecovery(recoveryMark)
            else attemptRetreat() end
            C:tryResumeRest()
        end)
        ctx:on("chimera.char.low", function(state)
            if state.what=="hp" then cancelSession("Niskie HP; oczekiwanie na GMCP anulowane.") end
            if emergencyLease then return end
            if active() then
                if state.what == "hp" and ownCombat(gmcp_api.combat()) then combatRetreat("state",gmcp_api.combat())
                elseif state.what == "hp" then beginRecovery()
                elseif state.what == "zmeczenie" then C:rest("Prog Automatyzacji: zmeczenie.") end
            end
        end)
        ctx:on("chimera.char.vitals",function(vitals) C:onVitals(vitals) end)
        ctx:on("chimera.char.info",function(character)
            if sessionWait and sessionWait.actor and type(character)=="table" and character.name and
                C.norm(character.name)~=sessionWait.actor then
                cancelSession("Zmieniono postac; oczekiwanie na wznowienie anulowane.")
            end
            if type(character)=="table" and character.name then C:identifyActor(character.name,true) end
            if sessionWait then
                C.phase="waitingGMCP"
                C.lastPause="Czekam na komplet danych GMCP; kurier wznowi sie automatycznie. /paczki stop anuluje oczekiwanie."
            end
            checkSession()
        end)
        ctx:on("chimera.room.info",function() checkSession() end)
        ctx:on("chimera.combat.state",function(state)
            combatRetreat("state",state)
        end)
        ctx:on("chimera.paczki.timing.delay",function(event)
            if type(event)=="table" then timingDelay(event.seconds) end
        end)

        cancelSession=function(reason)
            if not sessionWait then return false end
            sessionWait=nil
            for _,handle in ipairs({sessionTimer or false,sessionRetry or false,sessionDeadline or false}) do
                if handle then ctx:cancel(handle) end
            end
            sessionTimer,sessionRetry,sessionDeadline=nil,nil,nil
            if C.phase=="waitingGMCP" then C.phase="idle" end
            if reason then C.lastPause=reason;ctx.log.info(reason) end
            return true
        end
        checkSession=function()
            if not sessionWait or sessionTimer then return end
            local waiting=sessionWait
            -- Mapper and native teleport guards must finish processing the
            -- first Room.Info before Boty acquires this run.
            sessionTimer=ctx:timer(0.05,function()
                sessionTimer=nil
                if disposed or sessionWait~=waiting or not sessionReady(C.actor) then return end
                if bots.status() then cancelSession("Inny bot dziala; oczekiwanie anulowane.");return end
                local command=waiting.command
                cancelSession(nil);C.lastPause=nil
                if command=="__default" then command=C.job and "wznow" or "start" end
                launch(command)
            end)
        end
        waitSession=function(command)
            cancelSession(nil)
            local waiting={command=command,actor=C.actor,attempts=0}
            sessionWait=waiting;C.mode="paused";C.phase="waitingGMCP"
            C.lastPause="Odswiezam dane GMCP. Po ich otrzymaniu kurier wznowi sie automatycznie. /paczki stop anuluje oczekiwanie."
            ctx.log.info(C.lastPause)
            sessionDeadline=ctx:timer(60,function()
                if sessionWait==waiting then
                    cancelSession("Serwer nie potwierdzil danych GMCP przez 60 s. Kurs pozostaje zapisany; sprawdz polaczenie i ponow /paczki wznow.")
                end
            end)
            local function request()
                if disposed or sessionWait~=waiting then return end
                sessionRetry=nil;waiting.attempts=waiting.attempts+1
                -- Re-negotiate existing protocol modules; never replay the
                -- raw Mudlet cache or synthesize character/room events.
                if type(sendGMCP)=="function" then
                    pcall(sendGMCP,'Core.Supports.Remove ["Char","Room"]')
                    if sessionWait~=waiting then return end
                    pcall(sendGMCP,'Core.Supports.Add ["Char 2","Room 1"]')
                end
                if sessionWait~=waiting then return end
                checkSession()
                if waiting.attempts<3 then sessionRetry=ctx:timer(10,request) end
            end
            request()
        end
        launch=function(command)
            if bots.status() then
                ctx.log.warn("Dziala juz bot. Najpierw /bot stop.")
                return
            end
            if C.needsResumeValidation and not sessionReady(C.actor) then waitSession(command);return end
            cancelSession(nil)
            queued = command
            bots.start("paczki")
            queued = nil
        end
        local function stop()
            cancelSession("Oczekiwanie na GMCP zatrzymane recznie; kurs zachowany.")
            if owned then bots.stop("przerwane przez gracza")
            elseif active() then C:stop("Zatrzymano recznie.") end
        end
        -- beta.13 emits no command-bus event for /bot stop when no bot owns
        -- the manager. Observe that command reversibly while pending outside
        -- Boty, preserving its original handler and every other command.
        for _,entry in ipairs(ctx.app.commands.entries or {}) do
            if entry.name=="bot" and not entry.custom then
                local original=entry.fn
                local wrapped=function(arg)
                    if arg=="stop" then cancelSession("Oczekiwanie na GMCP zatrzymane recznie; kurs zachowany.") end
                    return original(arg)
                end
                entry.fn=wrapped
                ctx:cleanup(function() if entry.fn==wrapped then entry.fn=original end end)
                break
            end
        end
        local originalBotsStop=bots.stop
        local wrappedBotsStop=function(reason)
            cancelSession("Oczekiwanie na GMCP anulowane przez STOP.")
            return originalBotsStop(reason)
        end
        bots.stop=wrappedBotsStop
        ctx:cleanup(function() if bots.stop==wrappedBotsStop then bots.stop=originalBotsStop end end)
        local function basePath(arg)
            local path=tostring(arg or ""):gsub("^%s+",""):gsub("%s+$","")
            if path:sub(1,1)=='"' and path:sub(-1)=='"' or path:sub(1,1)=="'" and path:sub(-1)=="'" then
                path=path:sub(2,-2)
            end
            if path=="" then path="chimera_paczki_baza.json" end
            if path:find("[%z\1-\31]") then return nil,"Nieprawidlowa sciezka pliku bazy." end
            if path:sub(1,1)~="/" and path:sub(1,1)~="\\" and not path:match("^%a:[/\\]") then
                path=getMudletHomeDir().."/"..path
            end
            return path
        end
        local function transferBase(option,arg)
            if active() or owned or sessionWait then
                ctx.log.warn("Najpierw /paczki stop; eksport i import wykonuj przy zatrzymanym kurierze.");return
            end
            local path,why=basePath(arg)
            if not path then ctx.log.warn(why);return end
            if option=="eksport" then
                local ok,encoded=pcall(json.encode,{format="chimera_paczki_baza",version=1,memory=memory.exportState()},true)
                if not ok then ctx.log.warn("Nie udalo sie przygotowac eksportu bazy.");return end
                local file=io.open(path,"wb")
                if not file then ctx.log.warn("Nie mozna zapisac pliku bazy: "..path);return end
                local wrote=file:write(encoded.."\n");local closed=file:close()
                if not wrote or not closed then ctx.log.warn("Nie udalo sie zapisac calego pliku bazy: "..path);return end
                ctx.log.info("Wyeksportowano "..memory.count().." adresatow do: "..path)
                ctx.log.info("Plik zawiera nauczonych adresatow i ich lokalizacje; bez kursu, statystyk i danych postaci.")
            else
                local file=io.open(path,"rb")
                if not file then ctx.log.warn("Nie mozna odczytac pliku bazy: "..path);return end
                local content=file:read(4*1024*1024+1);file:close()
                if not content or #content>4*1024*1024 then ctx.log.warn("Plik bazy jest pusty lub przekracza 4 MiB.");return end
                local decoded,package=pcall(json.decode,content)
                if not decoded or type(package)~="table" or package.format~="chimera_paczki_baza" or package.version~=1 then
                    ctx.log.warn("Nieprawidlowy plik JSON bazy kuriera; nic nie zaimportowano.");return
                end
                local ok,summary=memory.importState(package.memory)
                if not ok then ctx.log.warn("Nie zaimportowano bazy: "..tostring(summary));return end
                if C.offerDiagnostics then C.offerDiagnostics=nil end
                ctx.log.info("Baza zaimportowana: dodano "..summary.added..", uzupelniono "..summary.updated..
                    ", bez zmian "..summary.unchanged.."; razem "..summary.total.." adresatow.")
            end
        end
        local function cell(text, command, color, hint)
            return { text = text, color = color or "CadetBlue", link = command, hint = hint or command }
        end
        local function searchStatus(route)
            if navigator.searchStatus then return navigator.searchStatus(route) end
            return {mode="known",reason="Wczytany modul NPC nie udostepnia diagnostyki; podmien caly folder Paczek."}
        end
        local function diagnostics()
            local route=C.job and C.job.route
            local problem
            if not route and C.job then route,problem=navigator.resolve(C.job.name,C.source) end
            local state=searchStatus(route)
            local planning=planner.status()
            local crossing=loadTransport(C.actor)
            local banks={["891456eab7637380"]="przystan Blekitnej Wstegi",["2e1aa32a45a83107"]="przystan w Gorach Czarnych"}
            local crossingText=crossing and ((banks[crossing.fromHash] or "przystan").." -> "..(banks[crossing.toHash] or "przystan")) or "brak zapisu przeprawy"
            local fareText=not crossing and "brak zapisu" or crossing.fareUncertain and "wynik przeniesienia niepotwierdzony" or
                crossing.fareDeferred and "schowanie odlozone do rozliczenia paczki" or crossing.fareFinished and "obsluga reszty zakonczona" or
                crossing.farePending and "oczekiwanie na potwierdzenie" or "etap przed rozliczeniem reszty"
            local rows={
                {"Wersja Paczek","1.5.19; silnik "..tostring(C.version).."; NPC "..tostring(navigator.version)},
                {"Stan",C.mode.." / "..C.phase},
                {"Planowanie",tostring(planning.active).." aktywne; "..tostring(planning.slices).." porcji; "..tostring(planning.yields).." oddan sterowania"},
                {"Porcja CPU",string.format("maks. %.2f ms od zaladowania",planning.maxSliceMs)},
                {"Adresat",C.job and C.job.name or "brak aktywnej paczki"},
                {"Wyszukiwanie",state.mode=="city" and "obchod miasta" or "znane miejsca"},
                {"Przyczyna",state.reason or problem or ""},
                {"Tozsamosc NPC",state.identity and "potwierdzona w katalogu" or "wymaga rozpoznania pelnego adresata"},
                {"Nazwa NPC",route and route.npcName or "brak"},
                {"Tytul NPC",route and route.npcTitle or "brak"},
                {"Kahn-Gad",crossingText},
                {"Reszta za bilet",fareText},
                {"Miasto",state.name or state.area or "nie ustalono"},
                {"Dane miasta",state.metadataSource or "nie ustalono"},
                {"Znane miejsca",tostring(state.knownRooms or (route and #route.rooms) or 0)},
            }
            ctx:report("Paczki / Diagnostyka 1.5.19",rows)
        end
        -- Update checks may run during a course. The code swap itself needs
        -- fresh, positively clear server state and zero outstanding ownership.
        local updateSeen,updateWalk,lastUpdateRefresh={},false,nil
        for _,entry in ipairs({{"chimera.char.info","char"},{"chimera.char.vitals","vitals"},
            {"chimera.room.info","room"},{"chimera.combat.state","combat"}}) do
            local key=entry[2]
            ctx:on(entry[1],function() updateSeen[key]=timingClock() end)
        end
        ctx:on("chimera.session.end",function() updateSeen={};updateWalk=false end)
        ctx:on("chimera.paczki.actor.changed",function() updateSeen={} end)
        ctx:on("chimera.walk.started",function() updateWalk=true end)
        ctx:on("chimera.walk.arrived",function() updateWalk=false end)
        ctx:on("chimera.walk.stopped",function() updateWalk=false end)
        local reloadSources
        local updater=require("chimera_paczki.updater").create(ctx,{
            version="1.5.19",now=timingClock,
            safe=function()
                if disposed or owned or bots.status() or updateWalk or sessionWait or emergencyLease or
                    next(pendingTravel) or C.pending or C.walking or C.mode=="running" or C.mode=="resting" or
                    C.mode=="recovering" or C.mode=="learning" or inventory.status().active or planner.status().active>0 then
                    return false,"czekam na zakonczenie pracy i potwierdzenie komend"
                end
                local reconnect=ctx.app.loader.records.paczki_reconnect
                if reconnect and reconnect.status=="running" then
                    local controller=reconnect.api and reconnect.api.controller
                    local ok,state=pcall(function() return controller:status() end)
                    if not ok or type(state)~="table" or state.pendingActor then
                        return false,"oczekuje automatyczne wznowienie po polaczeniu"
                    end
                end
                if not sessionReady(C.actor) then return false,"czekam na aktualna postac i pozycje GMCP" end
                local now=timingClock()
                local fresh=true
                for _,key in ipairs({"char","vitals","room","combat"}) do
                    if not updateSeen[key] or now-updateSeen[key]>120 or now<updateSeen[key] then fresh=false end
                end
                if not fresh then
                    if type(sendGMCP)=="function" and (not lastUpdateRefresh or now-lastUpdateRefresh>=60) then
                        lastUpdateRefresh=now
                        pcall(sendGMCP,'Core.Supports.Remove ["Char","Room","Chimera.Combat"]')
                        pcall(sendGMCP,'Core.Supports.Add ["Char 2","Room 1","Chimera.Combat 2"]')
                    end
                    return false,"czekam na swieze dane postaci, lokacji i walki GMCP"
                end
                local combat,room,vitals=gmcp_api.combat(),gmcp_api.room(),gmcp_api.vitals()
                if type(combat)~="table" or combat.room~=room.id or type(combat.primary)~="string" or
                    type(combat.relations)~="table" or next(combat.relations)~=nil or ownCombat(combat) or not vitals or
                    type(vitals.hp)~="number" or vitals.hp<=0 or vitals.hp>100 then
                    return false,"walka lub niepotwierdzony stan postaci; aktualizacja czeka"
                end
                return true
            end,
            reload=function(expected)
                local loader=ctx.app.loader
                if not reloadSources then
                    reloadSources={}
                    local names={"kurier_paczki"}
                    for _,name in ipairs(loader:dependents("kurier_paczki")) do names[#names+1]=name end
                    for _,name in ipairs(names) do
                        local record=loader.records[name]
                        if record and record.status=="running" then reloadSources[#reloadSources+1]=record.source end
                    end
                end
                -- A valid-syntax init may fail at runtime and be renamed to
                -- ?chimera_paczki by Loader:add. Resolve sources again for
                -- rollback, rather than assuming the old module name exists.
                local names={}
                for _,source in ipairs(reloadSources) do
                    local name=loader:by_source(source)
                    if name then names[#names+1]=name end
                end
                loader:reload(names)
                local record=loader.records.kurier_paczki
                if not record or record.status~="running" or not record.api or record.api.version~=expected or
                    not record.api.updater or record.api.updater.version~=expected then return false end
                for _,source in ipairs(reloadSources) do
                    local name=loader:by_source(source)
                    if not name or not loader.records[name] or loader.records[name].status~="running" then return false end
                end
                return true
            end,
        })
        local sharedBase=memory.createSharedSync(ctx,{
            safe=function()
                return not disposed and not active() and not owned and not sessionWait and not bots.status() and
                    not emergencyLease and not next(pendingTravel) and not C.pending and not C.walking and
                    not C.awaitingPickup and not C.awaitingDelivery and not C.awaitingReturn and not C.awaitingReward and
                    not inventory.status().active and planner.status().active==0
            end,
        })
        local function panel()
            local bagStatus=inventory.status()
            local detected=bagStatus.detectedPack
            if type(detected)=="table" then detected=detected.name end
            local search=searchStatus(C.job and C.job.route)
            ctx:table("Boty / Paczki 1.5.19", { { max = 18 }, { color = "gray" } }, {
                { "Sterowanie", { cell("[start]", "/bot paczki", "green"), cell("  [1 paczka]", "/paczki start 1", "green"),
                    cell("  [stop]", "/paczki stop", "orange"), cell("  [wznow]", "/paczki wznow") } },
                { "Stan", C.mode .. " / " .. C.phase },
                { "Aktualizacje", {cell("[sprawdz i aktualizuj]","/paczki aktualizuj"),
                    cell(updater.status().enabled and "  [auto: on]" or "  [auto: off]","/paczki aktualizacje status")} },
                { "Informacja", C.lastPause or "" },
                { "Opoznienie kroku", {{text=string.format("%.2f s (%s)  ",C:delay(),C.config.tempoSource=="walker" and "ustawienia chodzika" or "wlasne tempo paczek"),color="white"},
                    cell("[wolniej]",string.format("/paczki tempo %.2f",math.min(60,C:delay()+0.25))),
                    cell("  [szybciej]",string.format("/paczki tempo %.2f",math.max(0.15,C:delay()-0.25))),
                    cell("  [z chodzika]","/paczki tempo chodzik")} },
                { "Doreczono", tostring(C.stats.delivered) },
                { "Zarobek", string.format("%d zlotych, %d srebrnych, %d miedzianych", C.stats.gold, C.stats.silver, C.stats.copper) },
                { "Paczka", C.job and (C.job.name .. (C.job.delivered and " (oddana)" or " (w drodze)")) or "brak" },
                { "Limit szukania", tostring(C.config.searchSeconds/60).." min; adresat pomijany przez "..tostring(C.config.recipientCooldown/60).." min po zwrocie" },
                { "Wyszukiwanie NPC", { {text=(search.mode=="city" and "miasto: "..tostring(search.name or search.area or "") or tostring(search.reason or "znane miejsca")).."  "},cell("[diagnostyka]","/paczki diagnostyka") } },
                { divider = true },
                { "Maksymalna waga", { cell("[-]", string.format("/paczki limit %.1f", math.max(0.1,C.config.maxKg-0.5))),
                    { text=string.format("  %.1f kg  ",C.config.maxKg), color="white" },
                    cell("[+]", string.format("/paczki limit %.1f", math.min(100,C.config.maxKg+0.5))) } },
                { "Wybor", "Miejscowe -> miedzymiastowe poczta/poczta; w grupie numer tablicy" },
                { "Ocena ofert", {cell("[przyczyny i ranking]","/paczki oferty")} },
                { "Pomiary czasu", tostring(eta.summary(C.actor).samples).." ukonczonych kursow; "..
                    tostring(eta.summary(C.actor).routes).." wariantow trasy tej postaci" },
                { "Plecak", {cell(C.config.autoBackpack and "[wykrywanie auto]" or "[wlacz wykrywanie]","/paczki plecak auto"),
                    cell("  [wylacz wykrywanie]","/paczki plecak stop"),cell("  [pojemniki]","/pojemniki")} },
                { "Pojemniki Chimery", "paczka: "..(bags.configured("inne") and "ustawiony" or "nieprzypisany").."; monety: "..(bags.configured("monety") and "ustawiony" or "nieprzypisany") },
                { "Wykryty plecak", detected or "jeszcze nie wykryto" },
                { "Odswiezanie", tostring(C.config.refresh) .. " s przy braku ofert" },
                { "Zmiana poczty", {cell(C.config.roam and "[auto]" or "[wlacz auto]","/paczki poczty auto"),cell("  [wylacz auto]","/paczki poczty stop")} },
                { "Kolejna poczta", C.relocation and C.relocation.to.name or "" },
                { "Trasy / pomoc", { cell("[trasy]", "/paczki trasy"), cell("  [pomoc]", "/paczki pomoc"),cell("  [odswiez panel]", "/paczki") } },
                { "Adresaci", "10 tras Nuln + baza /npc i mapa profilu" },
                { "Sprawdz /npc", "/paczki npc Imie Nazwisko" },
                { "Baza kuriera", {cell(tostring(memory.count()).." adresatow — [pokaz]","/paczki baza")} },
                { "Przenoszenie bazy", {cell("[eksport]","/paczki baza eksport"),cell("  [import pliku]","/paczki baza import"),cell("  [pobierz wspolna]","/paczki baza aktualizuj")} },
                { "Automatyczna nauka", {cell(C.config.autoLearn and "[wlaczona]" or "[wlacz]","/paczki nauka auto"),cell("  [wylacz]","/paczki nauka stop")} },
                { "Najblizsze poczty", {cell("[lista]","/paczki poczty")} },
                { "Wybor reczny", {cell("[pracuj tutaj]","/paczki poczta tutaj"),{text="  /paczki poczta <miasto>",color="gray"}} },
            })
        end
        ctx:command{ "paczki", args="[komenda]", order=1,
            help="Panel kuriera; start [liczba], stop, wznow, status, diagnostyka, baza, nauka auto/stop, ucz <adresat>",
            fn=function(input)
                if not input or input=="" or input=="panel" then panel(); return end
                local action=C.norm(input:match("^(%S+)") or "")
                if action=="aktualizuj" then updater.check(false)
                elseif action=="autoaktualizacja" then
                    local setting=C.norm(input:match("^%S+%s+(.+)$") or "")
                    if setting=="on" or setting=="off" then updater.setEnabled(setting=="on")
                    else updater.show() end
                elseif action=="aktualizacje" then updater.show()
                elseif action=="start" or action=="wznow" or action=="resume" or action=="ucz" then
                    launch(input)
                elseif action=="poczta" then
                    local here=navigator.current()
                    if here and postal.disabled(here.id) and C.norm(input):match("^poczta%s+tutaj$") then input="poczta Karak Varn" end
                    if owned then C:command(input) else launch(input) end
                elseif action=="stop" or action=="pauza" then stop()
                elseif action=="reset" then stop(); C:command(input)
                elseif action=="diagnostyka" then diagnostics()
                elseif action=="oferty" then
                    if not C.offerDiagnostics then ctx.log.info("Brak zapisanej oceny pelnej tablicy. Uruchom kuriera na poczcie.");return end
                    local source=C.offersSource or {}
                    local place=source.city or source.name or "urzad nadania"
                    local mode=({local_first="miejscowe -> miedzymiastowe poczta/poczta"})[C.offersStrategy] or tostring(C.offersStrategy or "")
                    local rows={{"#","Rodzaj / adresat / kg / ocena (ETA informacyjnie)"},{divider=true}}
                    for _,offer in ipairs(C.offerDiagnostics) do
                        local method=offer.timeMethod=="learned" and (tostring(offer.timeSamples or 0).." pomiarow + szacunek") or "szacunek"
                        if offer.eta and offer.eta.uncertain then method=method.."; kilka lokacji NPC" end
                        if offer.eta and offer.eta.fareUnknown then method=method.."; przed kosztem biletu" end
                        if offer.eta and offer.eta.searchSeconds then method=method.."; rezerwa szukania adresata" end
                        local description=tostring(offer.kind).."; "..offer.name.."; "..(offer.kg and string.format("%.2f kg",offer.kg) or "? kg")
                        if offer.etaSeconds then
                            description=description..string.format("; ETA ~%.1f min; %.2f sr/min; %s; pozycja rankingu %s; koszt drogi %s",
                                offer.etaSeconds/60,offer.silverPerMinute,method,tostring(offer.rank or "?"),tostring(offer.cost or "?"))
                        else description=description.."; "..(offer.reason or "") end
                        rows[#rows+1]={{{text=tostring(offer.number),color=offer.eligible and "green" or "orange"}},description}
                    end
                    ctx:table("Paczki / Ostatnia ocena ofert — "..place.."; limit "..tostring(C.offersLimit).." kg; "..mode,
                        {{max=4},{max=90}},rows)
                    ctx.log.info("Najpierw miejscowe, potem miedzymiastowe poczta -> poczta; miedzydomenowe wylaczone. W grupie: numer tablicy. ETA i sr/min nie decyduja o wyborze.")
                    ctx.log.info("To ocena ostatniej pelnej tablicy; tempo, oferty i pomiary mogly sie od tego czasu zmienic.")
                elseif action=="baza" then
                    local option=C.norm(input:match("^%S+%s+(%S+)") or "")
                    if option=="aktualizuj" then sharedBase.check(false)
                    elseif option=="status" then sharedBase.show()
                    elseif option=="synchronizacja" then
                        local toggle=C.norm(input:match("^%S+%s+%S+%s+(%S+)") or "")
                        if toggle=="on" or toggle=="off" then sharedBase.setEnabled(toggle=="on")
                        else ctx.log.info("/paczki baza synchronizacja on|off");sharedBase.show() end
                    elseif option=="eksport" or option=="import" then
                        transferBase(option,input:match("^%S+%s+%S+%s+(.+)$"))
                    elseif option=="usun" then
                        local name=input:match("^%S+%s+%S+%s+(.+)$")
                        if not name then ctx.log.info("/paczki baza usun <pelny adresat>");return end
                        local ok,why=memory.forget(name)
                        if ok then ctx.log.info("Usunieto adresata z bazy kuriera: "..name..".")
                        else ctx.log.warn(why or "Nie ma takiego adresata w bazie kuriera.") end
                    elseif option~="" then ctx.log.info("/paczki baza | baza aktualizuj | baza status | baza synchronizacja on|off | baza eksport [plik] | baza import [plik] | baza usun <pelny adresat>")
                    else
                        local rows={}
                        for _,record in ipairs(memory.all()) do
                            rows[#rows+1]={record.recipient,record.postal and "poczta" or (record.name or "potwierdzona lokalizacja"),
                                tostring(#record.roomHashes).." lokacji",tostring(record.count).." doreczen"}
                        end
                        if #rows==0 then ctx.log.info("Baza kuriera jest pusta. Potwierdzone doreczenia beda zapisywane automatycznie.")
                        else ctx:table("Paczki / Zapamietani adresaci",{{max=50},{max=30},{color="gray"},{color="gray"}},rows) end
                    end
                elseif action=="poczty" and not input:match("%s+%S") then
                    local candidates,why=offices.candidates(navigator.current())
                    if #candidates==0 then ctx.log.info(why or "Brak innej osiagalnej poczty."); return end
                    local rows={}
                    for _,office in ipairs(candidates) do rows[#rows+1]={office.name.." ("..office.city..")",tostring(office.cost)} end
                    ctx:table("Paczki / Najblizsze poczty — koszt drogi",{{max=65},{color="gray"}},rows)
                elseif action=="npc" then
                    local name=input:match("^%S+%s+(.+)$")
                    if not name then ctx.log.info("Sprawdz adresata: /paczki npc Imie Nazwisko; baza: /npc"); return end
                    local route,why=navigator.resolve(name,C.source or navigator.current())
                    if route then ctx.log.info("Adresat: "..route.name.."; "..(route.postal and "urzad" or ("NPC id "..tostring(route.npcId)))..(route.postal and "; koszt drogi do urzedu: " or "; koszt drogi tam i z powrotem: ")..tostring(route.cost)..".")
                    else ctx.log.warn(tostring(why or "Brak jednoznacznego adresata i drogi w bazie /npc.")) end
                else C:command(input) end
            end }
        ctx:cleanup(function()
            cancelTiming()
            cancelSession(nil)
            C:checkpoint()
            disposed = true
            if owned then bots.stop("przeladowanie kuriera") end
            C:clearTimers(); C.pending=nil; C.mode="stopped"
            bots.unregister("paczki")
        end)
        return { engine=C, panel=panel, stop=stop, navigator=navigator, offices=offices, inventory=inventory, memory=memory, checkpoint=checkpoint,eta=eta,
            planner=planner,updater=updater,sharedBase=sharedBase,transportState=loadTransport,sessionWaiting=function() return sessionWait~=nil end, version="1.5.19" }
    end,
}
