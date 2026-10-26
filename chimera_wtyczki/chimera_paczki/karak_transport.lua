-- Confirmed Kahn-Gad protocol on the Blekitna Wstega. The map label
-- "statek" is not a game command. Purchase is sent only once per crossing.
local BLUE,BLACK,DECK="891456eab7637380","2e1aa32a45a83107","be0c7fc1d5441e3a"
local BOARD,SAIL,LAND,HEARTBEAT=20,600,20,30
local function norm(value)
    local text=tostring(value or ""):lower():gsub("\27%[[%d;]*[mK]","")
    for a,b in pairs({["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z"}) do text=text:gsub(a,b) end
    return (text:gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""))
end
local function valid(value) return type(value)=="number" and value>0 and value<math.huge and value==math.floor(value) end
local function copy(value) local out={};for k,v in pairs(value or {}) do out[k]=v end;return out end

return function(ctx,opts)
    opts=opts or {}
    local gmcp,mapper=assert(opts.gmcp),assert(opts.mapper)
    local sender=assert(opts.send,"karak transport sender required")
    local api,active,remembered,drain,disposed,paidBank={version="1.5.12"},nil,nil,nil,false,nil
    local persist,load_persistent,clear_persistent
    local savedSignatures={}
    local function map_of(id)
        if type(getRoomIDbyHash)~="function" then return nil end
        local ok,map=pcall(getRoomIDbyHash,id)
        return ok and valid(map) and mapper.chimera_id(map)==id and map or nil
    end
    local function here() return gmcp.room() or {},mapper.current_room() end
    local function at(id,map)
        local room,current=here()
        return valid(map) and room.id==id and current==map and mapper.chimera_id(map)==id
    end
    local function aboard() local map=map_of(DECK);return map and at(DECK,map) or false end
    local function clean_link(link)
        if type(link)~="table" or not ((link.fromHash==BLUE and link.toHash==BLACK) or
            (link.fromHash==BLACK and link.toHash==BLUE)) then return nil,"niezweryfikowana przeprawa Kahn-Gad" end
        local out={fromHash=link.fromHash,toHash=link.toHash,deckHash=DECK,cost=60,transport="karak_ship"}
        out.fromMap,out.toMap,out.deckMap=map_of(out.fromHash),map_of(out.toHash),map_of(DECK)
        if not out.fromMap or not out.toMap or not out.deckMap then return nil,"brak obu przystani lub pokladu Kahn-Gad na mapie" end
        return out
    end
    function api.catalogue()
        local links={}
        for _,pair in ipairs({{BLUE,BLACK},{BLACK,BLUE}}) do
            local link=clean_link({fromHash=pair[1],toHash=pair[2]})
            if link then links[#links+1]=link end
        end
        return links
    end
    api.catalog=api.catalogue
    local function alive(op) return active==op and not disposed and not op.finished end
    local function clear(op,key)
        local timer=op[key];op[key]=nil
        if timer then ctx:cancel(timer) end
    end
    local function activity(op)
        if alive(op) then ctx:emit("chimera.paczki.travel.activity",{transport="karak_ship",phase=op.phase,
            timeout=360,target=op.link.toHash,map_room=op.link.toMap}) end
    end
    local function actor()
        local value=type(opts.actor)=="function" and opts.actor() or nil
        if type(value)=="string" and norm(value)~="" then return value end
    end
    local function same_actor(record)
        local current=actor()
        return current==nil and record.actor==nil or
            current~=nil and record.actor~=nil and norm(current)==norm(record.actor)
    end
    local function receipt()
        if type(opts.coinReceipt)~="function" then return nil end
        local ok,value=pcall(opts.coinReceipt)
        return ok and type(value)=="number" and value>=0 and value<math.huge and value or nil
    end
    local function uncertain_coins()
        if type(opts.coinsUncertain)~="function" then return false end
        local ok,value=pcall(opts.coinsUncertain)
        return not ok or value==true
    end
    local function fare_receipt(op)
        local current=same_actor(op) and receipt() or nil
        if op.farePending and current and op.fareReceiptBefore and current>op.fareReceiptBefore then op.fareReceiptConfirmed=true end
        return op.fareReceiptConfirmed==true
    end
    local function snapshot(op)
        local settled=op.fareFinished==true or fare_receipt(op)
        return {actor=op.actor,link=copy(op.link),aboard=op.aboard==true,departed=op.departed==true,arrived=op.arrived==true,
            currentToHash=op.currentToHash,currentToMap=op.currentToMap,leaveSent=op.leaveSent==true,
            landSeen=op.landSeen==true,boardSeen=op.boardSeen==true,fareFinished=settled,
            farePrepared=op.farePrepared==true,farePending=op.farePending==true and not settled,
            fareUncertain=not settled and (op.fareUncertain==true or op.farePending==true and uncertain_coins()),
            fareDeferred=op.fareDeferred==true,freshArrival=op.freshArrival==true,
            -- Runtime tokens remain only in a same-client paused snapshot;
            -- durable() deliberately excludes them from disk.
            fareReceiptBefore=op.fareReceiptBefore,fareReceiptConfirmed=op.fareReceiptConfirmed==true,
            bought=op.bought==true,boardSent=op.boardSent==true,deckHash=DECK,deckMap=op.link.deckMap,
            directionUnknown=op.directionUnknown==true,corrected=op.corrected==true}
    end
    local FLAGS={"aboard","boardSeen","boardSent","bought","farePrepared","fareFinished","farePending",
        "fareUncertain","fareDeferred","departed","arrived","leaveSent","landSeen","directionUnknown","corrected"}
    local function durable(record,who)
        if type(record)~="table" or type(who)~="string" or norm(who)=="" then return nil end
        local link=record.link or record
        if not ((link.fromHash==BLUE and link.toHash==BLACK) or (link.fromHash==BLACK and link.toHash==BLUE)) then return nil end
        local out={schema=1,transport="karak_ship",actor=who,fromHash=link.fromHash,toHash=link.toHash}
        for _,key in ipairs(FLAGS) do
            if record[key]~=nil and type(record[key])~="boolean" then return nil end
            out[key]=record[key]==true
        end
        if record.currentToHash~=nil and record.currentToHash~=BLUE and record.currentToHash~=BLACK then return nil end
        out.currentToHash=record.currentToHash
        if out.fareFinished and (out.farePending or out.fareUncertain) then return nil end
        return out
    end
    clear_persistent=function(who)
        if type(opts.saveTransport)~="function" or not who then return true end
        local ok,saved=pcall(opts.saveTransport,who,nil)
        if ok and saved~=false then savedSignatures[norm(who)]=nil;return true end
        return false
    end
    persist=function(op)
        if type(opts.saveTransport)~="function" then return true end
        local who=op.actor or actor()
        local record=durable(snapshot(op),who)
        if not record then return false end
        local parts={record.fromHash,record.toHash,tostring(record.currentToHash)}
        for _,key in ipairs(FLAGS) do parts[#parts+1]=key..":"..tostring(record[key]) end
        local signature=table.concat(parts,"|")
        if savedSignatures[norm(who)]==signature then return true end
        local ok,saved=pcall(opts.saveTransport,who,record)
        if ok and saved~=false then savedSignatures[norm(who)]=signature;return true end
        return false
    end
    load_persistent=function()
        if type(opts.loadTransport)~="function" then return nil end
        local who=actor()
        if not who then return nil end
        local ok,value=pcall(opts.loadTransport,who)
        if not ok or type(value)~="table" or value.schema~=1 or value.transport~="karak_ship" or norm(value.actor)~=norm(who) then return nil end
        local record=durable(value,who)
        if not record then return nil end
        local link=clean_link(record)
        if not link then return nil end
        record.link=link;record.currentToMap=record.currentToHash==BLUE and map_of(BLUE) or
            record.currentToHash==BLACK and map_of(BLACK) or nil
        return record
    end
    local function commit(op) return persist(op) end
    local function end_drain(reason,unexpected,replaced)
        local pending=drain
        if not pending then return end
        drain=nil;clear(pending,"timer")
        if not replaced then ctx:emit("chimera.walk.stopped",{target=pending.record.link.toHash,map_room=pending.record.link.toMap,
            transport="paczki_karak_ship",reason=reason}) end
        if unexpected then
            remembered=nil
            ctx:emit("chimera.paczki.travel.unexpected",{room=unexpected,reason=reason,
                expected=pending.record.link.toHash,map_room=pending.record.link.toMap})
        end
        ctx:emit("chimera.paczki.travel.settled",{token=pending})
    end
    local function finish(op,ok,reason,keep)
        if not alive(op) then return end
        if ok or op.forget then clear_persistent(op.actor or actor())
        elseif op.aboard or op.bought or op.farePrepared then persist(op)
        else clear_persistent(op.actor or actor()) end
        active=nil;op.finished=true
        for _,key in ipairs({"boardTimer","sailTimer","landTimer","commandTimer","beatTimer"}) do clear(op,key) end
        local cancel=op.cancelFare;op.cancelFare=nil
        if type(cancel)=="function" then cancel() end
        local scopeOpen=type(ctx.isClosed)~="function" or not ctx:isClosed()
        local pendingKind=keep and not op.offline and scopeOpen and ((op.leaveSent and "landing") or (op.boardSent and not op.aboard and "boarding"))
        remembered=keep and ((op.aboard and aboard()) or pendingKind) and snapshot(op) or nil
        if pendingKind and remembered then
            drain={kind=pendingKind,record=remembered}
            local pending=drain
            pending.timer=ctx:timer(LAND,function()
                if drain==pending then end_drain("brak potwierdzenia przerwanej komendy Kahn-Gad",gmcp.room() or {}) end
            end)
            ctx:emit("chimera.paczki.travel.pending",{token=pending})
        else
            ctx:emit(ok and "chimera.walk.arrived" or "chimera.walk.stopped",{target=op.link.toHash,map_room=op.link.toMap,
                transport="paczki_karak_ship",reason=reason})
        end
        op.done({ok=ok,reason=reason,transport="karak_ship",fromHash=op.link.fromHash,toHash=op.link.toHash,map_room=op.link.toMap})
    end
    local function later(op,key,delay,callback)
        clear(op,key)
        op[key]=ctx:timer(delay,function()
            if not alive(op) then return end
            op[key]=nil;callback()
        end)
    end
    local function send(op,command)
        if not alive(op) then return false end
        if not same_actor(op) then op.offline=true;finish(op,false,"zmieniono postac podczas przeprawy Kahn-Gad");return false end
        local ok,result=pcall(sender,command)
        if not ok or result==false then finish(op,false,"nie udalo sie wyslac komendy Kahn-Gad");return false end
        return alive(op)
    end
    local inspect,land,prepare
    local function heartbeat(op)
        if not alive(op) then return end
        activity(op)
        later(op,"beatTimer",HEARTBEAT,function()
            inspect(op)
            if alive(op) then heartbeat(op) end
        end)
    end
    local function inventory(op,method,callback)
        if not same_actor(op) then op.offline=true;finish(op,false,"zmieniono postac podczas monet Kahn-Gad");return end
        local action=opts[method]
        if type(action)~="function" then finish(op,false,"brak obslugi monet do biletu Kahn-Gad");return end
        local returned=false
        local ok,cancel=pcall(action,function(result)
            if returned or not alive(op) then return end
            returned=true;op.cancelFare=nil
            if not result or result.ok~=true then
                if method=="finishFare" and result and result.ok==false and not uncertain_coins() and not op.fareUncertain then
                    op.farePending=false;op.fareDeferred=true
                    if not commit(op) then finish(op,false,"nie zapisano odlozonego schowania monet Kahn-Gad");return end
                    if opts.say then pcall(opts.say,"Schowanie reszty po bilecie odkladam do rozliczenia paczki; rejs jest kontynuowany.") end
                    callback();return
                end
                op.fareUncertain=method=="finishFare" and (op.fareUncertain or uncertain_coins()) or nil
                finish(op,false,"monety Kahn-Gad: "..tostring(result and result.reason or "brak potwierdzenia"));return
            end
            if method=="finishFare" and result.skipped==true then op.fareDeferred=true end
            callback()
        end)
        if not ok then finish(op,false,"nie uruchomiono obslugi monet Kahn-Gad");return end
        if alive(op) and not returned then op.cancelFare=cancel
        elseif not returned and type(cancel)=="function" then cancel() end
    end
    local function settle_fare(op)
        if op.fareFinished or op.fareDeferred then if op.arrived then land(op) end;return end
        if op.fareUncertain or uncertain_coins() then finish(op,false,"schowanie monet Kahn-Gad nie zostalo potwierdzone; nie ponawiam przeniesienia",true);return end
        op.farePending=true;op.fareReceiptBefore=receipt();op.fareReceiptConfirmed=false
        if not commit(op) then finish(op,false,"nie zapisano etapu schowania monet Kahn-Gad",true);return end
        inventory(op,"finishFare",function()
            op.farePending=false
            if not op.fareDeferred then op.fareFinished=true end
            if not commit(op) then finish(op,false,"nie zapisano potwierdzenia monet Kahn-Gad",true);return end
            if op.arrived then land(op) end
        end)
    end
    local function confirmed_boarding(op)
        if not alive(op) or op.aboard or not op.boardSeen or not aboard() then return end
        op.aboard=true;op.phase="sailing";clear(op,"boardTimer");paidBank=nil
        later(op,"sailTimer",SAIL,function() finish(op,false,"brak potwierdzenia docelowego przybicia Kahn-Gad",true) end)
        activity(op)
        if not commit(op) then finish(op,false,"nie zapisano potwierdzenia wejscia Kahn-Gad",true);return end
        settle_fare(op)
    end
    land=function(op)
        if not alive(op) or not op.aboard or not (op.fareFinished or op.fareDeferred) or not op.departed or not op.arrived or
            (not op.directionUnknown and op.currentToHash~=op.link.toHash) or op.leaveSent then return end
        if not aboard() then inspect(op);return end
        op.phase="disembarking";op.leaveSent=true;clear(op,"sailTimer")
        later(op,"landTimer",LAND,function() finish(op,false,"brak potwierdzenia zejscia z Kahn-Gad",true) end)
        activity(op)
        if not commit(op) then finish(op,false,"nie zapisano etapu zejscia Kahn-Gad",true);return end
        send(op,"zejdz ze statku")
    end
    inspect=function(op)
        if not alive(op) then return end
        if not same_actor(op) then op.offline=true;finish(op,false,"zmieniono postac podczas przeprawy Kahn-Gad");return end
        if not op.aboard and op.boardSent and aboard() then confirmed_boarding(op) end
        if not alive(op) then return end
        local room,map=here()
        if op.leaveSent and op.landSeen and at(op.link.toHash,op.link.toMap) then finish(op,true);return end
        if op.leaveSent and op.landSeen and op.directionUnknown and at(op.link.fromHash,op.link.fromMap) then
            if op.corrected then finish(op,false,"nie potwierdzono kierunku Kahn-Gad po korekcie");return end
            clear(op,"sailTimer");clear(op,"landTimer")
            op.directionUnknown=false;op.corrected=true;op.aboard=false;op.boardSeen=false;op.boardSent=false
            op.bought=false;op.departed=false;op.arrived=false;op.leaveSent=false;op.landSeen=false
            op.farePrepared=false;op.fareFinished=false;op.fareDeferred=false;op.farePending=false;op.fareUncertain=false
            op.ready=true;op.preparing=false
            op.currentToHash,op.currentToMap=op.link.toHash,op.link.toMap
            op.phase="waiting"
            if not commit(op) then finish(op,false,"nie zapisano korekty brzegu Kahn-Gad");return end
            prepare(op);return
        end
        if op.aboard and room.id==DECK then
            if map==op.link.deckMap and op.arrived then land(op) end
            return
        end
        if not op.aboard and op.boardSent and room.id==DECK then return end
        if op.leaveSent then
            if room.id==op.link.toHash or (op.directionUnknown and room.id==op.link.fromHash) then return end
            if room.id and room.id~=DECK then finish(op,false,"Kahn-Gad opuszczony na innym brzegu");return end
        elseif op.aboard and room.id and room.id~=DECK then finish(op,false,"zmiana lokacji poza zejsciem z Kahn-Gad")
        elseif not op.aboard and room.id~=op.link.fromHash then finish(op,false,"zmiana przystani przed wejsciem na Kahn-Gad") end
    end
    local function buy_and_board(op)
        if not alive(op) or op.boardQueued or op.boardSent or (op.bought and not op.reuseTicket) or
            not op.ready or not at(op.link.fromHash,op.link.fromMap) then return end
        op.boardQueued=true;op.phase="boarding";activity(op)
        later(op,"boardTimer",BOARD,function() finish(op,false,"brak potwierdzenia wejscia na Kahn-Gad; zakupu nie powtarzam") end)
        if not op.bought then
            op.bought=true
            -- The receipt is ambiguous; retain the attempted purchase even
            -- after STOP or silence. A later run may board, never pay twice.
            paidBank={fromHash=op.link.fromHash,toHash=op.link.toHash,purchaseAttempted=true,actor=op.actor}
            if not commit(op) then finish(op,false,"nie zapisano proby zakupu biletu Kahn-Gad");return end
            if not send(op,"kup bilet") then return end
        end
        -- Ordered commands reproduce the supplied successful crossing. The
        -- seller's generic line about a buying person is not our receipt.
        later(op,"commandTimer",0.05,function()
            if not op.ready or not at(op.link.fromHash,op.link.fromMap) then
                finish(op,false,"statek odplynal po zakupie; nie powtarzam zakupu");return
            end
            op.boardSent=true
            if not commit(op) then finish(op,false,"nie zapisano proby wejscia Kahn-Gad");return end
            send(op,"wsiadz na statek")
        end)
    end
    prepare=function(op)
        if not alive(op) or not op.ready or op.preparing or op.bought then return end
        if not at(op.link.fromHash,op.link.fromMap) then finish(op,false,"brak potwierdzenia przystani Kahn-Gad");return end
        op.preparing=true;op.phase="preparingFare"
        inventory(op,"prepareFare",function()
            op.preparing=false;op.farePrepared=true
            if not commit(op) then finish(op,false,"nie zapisano potwierdzenia monet na bilet Kahn-Gad");return end
            if op.ready then buy_and_board(op) else op.phase="waiting";activity(op) end
        end)
    end
    local function departure(record)
        if record.arrived and not record.directionUnknown then
            record.currentToHash=record.currentToHash==record.link.toHash and record.link.fromHash or record.link.toHash
            record.currentToMap=record.currentToHash==record.link.toHash and record.link.toMap or record.link.fromMap
        end
        record.departed=true;record.arrived=false
    end
    local function on_line(raw)
        local text=norm(raw);local op=active;local record=op or remembered
        if not record then return end
        if not same_actor(record) then
            if op then op.offline=true;finish(op,false,"zmieniono postac podczas przeprawy Kahn-Gad") end
            return
        end
        if not op then
            if text=="wchodzisz po trapie na statek." and record.boardSent then record.boardSeen=true
            elseif text=="schodzisz po trapie ze statku na brzeg." and record.leaveSent then record.landSeen=true
            elseif aboard() then
                if text=="statek odbija od brzegu i podnosi trap." then departure(record)
                elseif text=="statek dobija do brzegu i opuszcza trap." and record.departed then record.arrived=true end
            end
            persist(record)
            return
        end
        if text=="statek dobija do brzegu i opuszcza trap." then
            if op.aboard then
                if op.freshArrival then op.departed=true;op.freshArrival=false end
                if op.departed then op.arrived=true;if commit(op) then land(op) else finish(op,false,"nie zapisano przybicia Kahn-Gad",true) end end
            elseif not op.bought or op.reuseTicket then
                op.ready=true;if op.farePrepared or op.reuseTicket then buy_and_board(op) else prepare(op) end
            end
        elseif text=="statek odbija od brzegu i podnosi trap." then
            if op.aboard or (op.boardSent and (op.boardSeen or aboard())) then departure(op) else op.ready=false end
        elseif text=="wchodzisz po trapie na statek." and op.boardSent then op.boardSeen=true;confirmed_boarding(op)
        elseif text=="schodzisz po trapie ze statku na brzeg." and op.leaveSent then op.landSeen=true;inspect(op)
        elseif text=="umierasz." then op.forget=true;finish(op,false,"smierc podczas przeprawy Kahn-Gad");return end
        if alive(op) and (op.aboard or op.bought or op.farePrepared) then persist(op) end
    end
    local function passive_position()
        local record=remembered
        if not record then
            local saved=load_persistent()
            local room,map=here()
            if saved and saved.aboard and room.id and room.id~=DECK and valid(map) and mapper.chimera_id(map)==room.id then
                clear_persistent(saved.actor)
            end
            return
        end
        local room=here()
        if drain then
            if drain.kind=="boarding" then
                if room.id==record.link.fromHash then return end
                if room.id==DECK then
                    if record.boardSeen and aboard() then record.aboard=true;paidBank=nil;end_drain("potwierdzono przerwane wejscie Kahn-Gad") end
                else end_drain("nieoczekiwana lokacja po wejsciu Kahn-Gad",room) end
            elseif room.id==DECK then return
            elseif (room.id==record.link.toHash or record.directionUnknown and room.id==record.link.fromHash) and record.landSeen then
                local map=room.id==record.link.toHash and record.link.toMap or record.link.fromMap
                if at(room.id,map) then remembered=nil;end_drain("potwierdzono przerwane zejscie Kahn-Gad") end
            elseif room.id~=record.link.toHash and not (record.directionUnknown and room.id==record.link.fromHash) then
                end_drain("nieoczekiwana lokacja po zejsciu Kahn-Gad",room)
            end
        elseif not aboard() then remembered=nil end
    end
    local function start(link,done,previous)
        if disposed then done({ok=false,reason="Kahn-Gad wylaczony"});return function() end end
        if active then done({ok=false,reason="trwa juz przeprawa Kahn-Gad"});return function() end end
        if drain then done({ok=false,reason="poprzednia komenda Kahn-Gad nie zostala potwierdzona"});return function() end end
        local known,why=clean_link(link)
        if not known then done({ok=false,reason=why});return function() end end
        if previous then
            if not aboard() then done({ok=false,reason="brak pokladu Kahn-Gad do wznowienia"});return function() end end
        elseif not at(known.fromHash,known.fromMap) then done({ok=false,reason="rejs Kahn-Gad rozpocznij na potwierdzonej przystani"});return function() end end
        local op={actor=actor(),link=known,done=done,phase="waiting",currentToHash=known.toHash,currentToMap=known.toMap}
        if not previous then
            local bank=load_persistent()
            if bank and not bank.aboard and bank.bought and
                (bank.fromHash~=known.fromHash or bank.toHash~=known.toHash) then
                done({ok=false,reason="nierozstrzygniety zakup biletu Kahn-Gad na innej przystani"});return function() end
            end
            if bank and not bank.aboard and bank.fromHash==known.fromHash and bank.toHash==known.toHash then
                if bank.fareUncertain or uncertain_coins() then done({ok=false,reason="monety Kahn-Gad nie zostaly potwierdzone"});return function() end end
                op.farePrepared=bank.farePrepared
                if bank.bought then paidBank={fromHash=known.fromHash,toHash=known.toHash,purchaseAttempted=true,actor=op.actor} end
            end
        end
        if paidBank and not same_actor(paidBank) then paidBank=nil end
        if not previous and paidBank then
            if paidBank.fromHash~=known.fromHash or paidBank.toHash~=known.toHash then
                done({ok=false,reason="nierozstrzygniety zakup biletu Kahn-Gad na innej przystani"});return function() end
            end
            op.bought=true;op.reuseTicket=true;op.farePrepared=true
        end
        if previous then for k,v in pairs(previous) do if k~="link" then op[k]=v end end end
        active=op;remembered=nil
        ctx:emit("chimera.walk.started",{target=known.toHash,map_room=known.toMap,transport="paczki_karak_ship"})
        if not alive(op) then return function() end end
        if previous then
            op.phase=op.leaveSent and "disembarking" or "sailing"
            if op.leaveSent then later(op,"landTimer",LAND,function() finish(op,false,"brak potwierdzenia wznowionego zejscia Kahn-Gad",true) end)
            else later(op,"sailTimer",SAIL,function() finish(op,false,"brak potwierdzenia przybicia Kahn-Gad",true) end) end
            activity(op)
            if not op.fareFinished and not op.fareDeferred then settle_fare(op)
            elseif op.arrived then land(op) end
            inspect(op)
        else activity(op) end
        if alive(op) then heartbeat(op) end
        return function() finish(op,false,"przerwano przeprawe Kahn-Gad",true) end
    end
    function api.run(link,done) return start(link,done) end
    function api.resumable(targetMap)
        return aboard() and (targetMap==map_of(BLUE) or targetMap==map_of(BLACK)) or false
    end
    function api.resume(target,done)
        local link,why
        if type(target)=="table" then link,why=clean_link(target)
        else for _,candidate in ipairs(api.catalogue()) do if candidate.toMap==target then link=candidate;break end end end
        if not link or not aboard() then done({ok=false,reason=why or "brak pokladu lub celu wznowienia Kahn-Gad"});return function() end end
        local previous=remembered
        if previous and not same_actor(previous) then previous=nil;remembered=nil end
        if not previous then
            previous=load_persistent()
            if previous then
                if previous.fareUncertain or uncertain_coins() then done({ok=false,reason="schowanie monet Kahn-Gad nie zostalo potwierdzone; nie ponawiam przeniesienia"});return function() end end
                previous.aboard=true;previous.boardSeen=true;previous.boardSent=true
                previous.directionUnknown=true;previous.departed=false;previous.arrived=false
                previous.leaveSent=false;previous.landSeen=false;previous.freshArrival=true
                previous.currentToHash=link.toHash;previous.currentToMap=link.toMap
                if previous.farePending and not previous.fareFinished then
                    -- A recovered process has no live transfer token. Never
                    -- retry optional housekeeping merely from a stale pending
                    -- marker, even when its inventory snapshot is not unknown.
                    previous.farePending=false;previous.fareDeferred=true
                end
            end
        end
        if drain then
            if drain.kind=="landing" and previous and previous.leaveSent then end_drain("wznowiono oczekiwanie na zejscie Kahn-Gad")
            else done({ok=false,reason="wejscie Kahn-Gad nie zostalo potwierdzone"});return function() end end
        end
        if not previous then
            if uncertain_coins() then done({ok=false,reason="przeniesienie monet nie zostalo potwierdzone; nie zgaduje stanu Kahn-Gad"});return function() end end
            -- A legacy client knows only that it is aboard. Optional coin
            -- housekeeping is deferred without inventing a settled receipt.
            previous={actor=actor(),aboard=true,boardSeen=true,boardSent=true,fareFinished=false,fareDeferred=true,
                directionUnknown=true,departed=false,arrived=false,freshArrival=type(opts.loadTransport)=="function"}
        end
        return start(link,done,previous)
    end
    function api.state()
        local record=active and active.aboard and active or remembered
        if record and not same_actor(record) then record=nil end
        if record and aboard() then
            local out=snapshot(record)
            out.fromHash,out.toHash=record.link.fromHash,record.link.toHash
            out.fromMap,out.toMap=record.link.fromMap,record.link.toMap
            out.boatHash=DECK;out.deckId=DECK;out.phase=active and active.phase or "paused"
            return out
        end
        if aboard() then return {aboard=true,deckHash=DECK,boatHash=DECK,deckId=DECK,deckMap=map_of(DECK),
            unknownDirection=true,phase="unidentifiedDirection",transport="karak_ship"} end
    end
    function api.status() return active and {phase=active.phase,aboard=active.aboard==true,bought=active.bought==true} or nil end
    function api.fareState() return paidBank and same_actor(paidBank) and copy(paidBank) or nil end
    function api.clearState(who)
        if active then return false end
        remembered=nil;paidBank=nil
        return clear_persistent(who or actor())
    end
    ctx:on("chimera.paczki.coins.stored",function(event)
        local record=active or remembered
        if not record or not record.farePending or type(event)~="table" or
            norm(event.actor)~=norm(record.actor) or type(event.receipt)~="number" or
            not record.fareReceiptBefore or event.receipt<=record.fareReceiptBefore then return end
        record.fareReceiptConfirmed=true
        if not active then
            record.fareFinished=true;record.farePending=false;record.fareUncertain=false
        end
        persist(record)
    end)
    ctx:trigger("^",function() on_line(line);if not active then passive_position() end end)
    for _,event in ipairs({"chimera.room.info","chimera.room.changed","chimera.mapper.moved"}) do
        ctx:on(event,function() if active then inspect(active) else passive_position() end end)
    end
    ctx:on("chimera.walk.started",function(event)
        if not active and (not event or event.transport~="paczki_karak_ship") then
            remembered=nil;if drain then end_drain("inne chodzenie zastapilo Kahn-Gad",nil,true) end
        end
    end)
    for _,event in ipairs({"chimera.session.end","sysDisconnectionEvent","chimera.paczki.actor.changed","chimera.mapper.lost","chimera.numpad.pressed"}) do
        ctx:on(event,function()
            if drain then end_drain("przerwano Kahn-Gad: "..event) end
            if active then
                active.offline=event=="chimera.session.end" or event=="sysDisconnectionEvent" or event=="chimera.paczki.actor.changed"
                finish(active,false,"przerwano Kahn-Gad: "..event,not active.offline)
            elseif remembered then persist(remembered) end
            remembered=nil
            if event=="chimera.session.end" or event=="sysDisconnectionEvent" or event=="chimera.paczki.actor.changed" then paidBank=nil end
        end)
    end
    ctx:cleanup(function()
        if drain then end_drain("przeladowanie Kahn-Gad") end
        if active then active.offline=true;finish(active,false,"przeladowanie Kahn-Gad")
        elseif remembered then persist(remembered) end
        disposed=true;remembered=nil;paidBank=nil
    end)
    return api
end
