-- Confirmed parcel/coin transfers through configured containers, or one
-- backpack proved worn by the current character in our own inventory query.
-- Never invoke bags.put/take: those helpers send an entire batch unchecked.
local ACCENTS={ ["ą"]="a",["ć"]="c",["ę"]="e",["ł"]="l",["ń"]="n",["ó"]="o",["ś"]="s",["ź"]="z",["ż"]="z",
    ["Ą"]="a",["Ć"]="c",["Ę"]="e",["Ł"]="l",["Ń"]="n",["Ó"]="o",["Ś"]="s",["Ź"]="z",["Ż"]="z" }
local function norm(raw)
    local text=tostring(raw or ""):gsub("\27%[[%d;]*[mK]",""):gsub(" "," ")
    for accent,ascii in pairs(ACCENTS) do text=text:gsub(accent,ascii) end
    return (text:lower():gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""))
end
local function word(text,wanted)
    return (" "..text.." "):find("[^%w_]"..wanted.."[^%w_]")~=nil
end
local function last_word(text)
    local last
    for token in norm(text):gmatch("[%a%-]+") do last=token end
    return last
end
-- Opening commands use the accusative, while the server's already-open
-- reply names the container in the nominative. Accept only a complete
-- container phrase, never an actor's action, quoted speech or a negation.
local OPEN_HEADS={
    plecak={"plecak","y"},torbe={"torba","a"},worek={"worek","y"},
    sakiewke={"sakiewka","a"},mieszek={"mieszek","y"},sakwe={"sakwa","a"},wor={"wor","y"},
}
local function already_open(text,commands)
    local subject,state=text:match("^(.-) jest juz (otwart[aye])%.$")
    if not subject then subject,state=text:match("^(.-) juz jest (otwart[aye])%.$") end
    local head=commands.openWord
    local form=OPEN_HEADS[head]
    local ending=form and form[2] or (head and head:match("[oa]$") and (head:sub(-1)=="a" and "a" or "e") or "y")
    if text=="jest juz otwart"..ending.."." or text=="juz jest otwart"..ending.."." then return true end
    if not subject or not head or state~="otwart"..ending then return false end
    local words={}
    for token in subject:gmatch("%S+") do words[#words+1]=token end
    if words[#words]~=(form and form[1] or head) then return false end
    for i=1,#words-1 do
        local token=words[i]
        local own=token=="swoj" or token=="twoj" or token=="swoja" or token=="twoja" or token=="swoje" or token=="twoje"
        if token=="nie" or token=="cudzy" or token=="cudza" or token=="cudze" or
            not token:match("^[a-z%-]+$") or
            (not own and not token:match(ending=="y" and "[yi]$" or ending.."$")) then return false end
    end
    return true
end
local function copy_commands(value)
    if not value then return nil end
    local out={}
    for _,key in ipairs({"move","b","d","open","close","containerWord","openWord","name","detected"}) do out[key]=value[key] end
    return out
end
local function copy_container(value)
    if not value then return nil end
    local out={}
    for _,key in ipairs({"b","d","name","detected","open","close","containerWord","openWord"}) do out[key]=value[key] end
    return out
end
local function saved_text(value,required)
    if value==nil then return nil,not required end
    if type(value)~="string" or value=="" or #value>500 or value:find("[;|%z\1-\31\127]") then return nil,false end
    if norm(value)=="" then return nil,false end
    return value,true
end
local function saved_container(value)
    if type(value)~="table" then return nil end
    local out={}
    for _,key in ipairs({"b","d","name","open","close","containerWord","openWord"}) do
        local text,ok=saved_text(value[key],key=="d")
        if not ok then return nil end
        out[key]=text
    end
    if value.detected~=nil and type(value.detected)~="boolean" then return nil end
    out.detected=value.detected
    if out.open and (not out.b or norm(out.open)~="otworz "..norm(out.b)) then return nil end
    if out.close and (not out.b or norm(out.close)~="zamknij "..norm(out.b)) then return nil end
    if out.open then out.open="otworz "..out.b end
    if out.close then out.close="zamknij "..out.b end
    local containerWord,openWord=last_word(out.d),out.b and last_word(out.b)
    if not containerWord or (out.containerWord and out.containerWord~=containerWord) or
        (out.openWord and out.openWord~=openWord) then return nil end
    out.containerWord,out.openWord=containerWord,openWord
    if out.detected and (not out.b or not norm(out.b):match("^swoj ") or not norm(out.d):match("^swojego ") or
        openWord~="plecak" or containerWord~="plecaka") then return nil end
    return out
end

return function(ctx,bags,opts)
    opts=opts or {}
    if not bags and ctx.use then
        local ok,found=pcall(ctx.use,ctx,"bags")
        if ok then bags=found end
    end
    local sender=opts.send or function(command) return ctx:send(command) end
    local timeout=math.max(1,math.min(30,tonumber(opts.timeout) or 6))
    local openTimeout=tonumber(opts.openTimeout)
    if not openTimeout or openTimeout~=openTimeout or openTimeout<=0 or openTimeout>=math.huge then openTimeout=timeout end
    openTimeout=math.max(timeout,math.min(30,openTimeout))
    local settle=math.max(0.05,math.min(2,tonumber(opts.settle) or 0.25))
    local api={version="1.5.11"}
    local active,disposed,parcelState,parcelVersion,pending=nil,false,"unknown",0,nil
    local coinReceipt,coinWithdrawalReceipt,coinPending,coinsUncertain=0,0,nil,false
    local parcelContainer,detectedPack,lastReason
    local notices={}
    local function state_changed()
        if type(opts.onStateChanged)=="function" then pcall(opts.onStateChanged) end
    end
    local function alive(op) return not disposed and active==op and not op.finished end
    local function clear(op,key)
        local handle=op[key];op[key]=nil
        if handle then ctx:cancel(handle) end
    end
    local function result(op,ok,reason,extra)
        local out={ok=ok,reason=reason,moved=op.confirmed==true,uncertain=op.parcel and parcelState=="unknown" or false,
            state=parcelState}
        for key,value in pairs(extra or {}) do out[key]=value end
        return out
    end
    local function finish(op,ok,reason,extra)
        if active~=op or op.finished then return end
        local outstanding=op.parcel and pending or coinPending
        if outstanding and outstanding==op.transfer and op.buffer and not outstanding.consumed then outstanding.buffer=op.buffer end
        op.finished,active=true,nil
        lastReason=reason
        clear(op,"timer");clear(op,"settleTimer")
        -- pending survives cancellation only to recognize a late exact own
        -- transfer reply. Such a reply must never continue the operation.
        op.done(result(op,ok,reason,extra))
    end
    local function later(op,key,seconds,callback)
        clear(op,key)
        op[key]=ctx:timer(seconds,function()
            if not alive(op) then return end
            op[key]=nil;callback()
        end)
    end
    local function send(op,command)
        if not alive(op) then return false end
        local phase=op.phase
        local ok,sent=pcall(sender,command)
        if alive(op) and op.phase==phase and (not ok or sent==false) then
            finish(op,false,"nie udalo sie wyslac komendy pojemnika")
            return false
        end
        return alive(op)
    end
    local function configured(kind)
        return bags and type(bags.configured)=="function" and bags.configured(kind)==true
    end
    local function auto_detect()
        local value=opts.autoDetect
        if type(value)=="function" then
            local ok,enabled=pcall(value)
            return ok and enabled==true
        end
        return value==true
    end
    local function open_close()
        local value=opts.openClose
        if type(value)=="function" then
            local ok,enabled=pcall(value)
            return ok and enabled~=false
        end
        return value~=false
    end
    function api.configured(kind) return configured(kind or "inne") end
    function api.parcelState() return parcelState end
    function api.coinReceipt() return coinReceipt end
    function api.coinWithdrawalReceipt() return coinWithdrawalReceipt end
    function api.phase() return active and active.phase or "idle" end
    function api.status() return {phase=api.phase(),kind=active and active.kind,state=parcelState,active=active~=nil,
        detectedPack=detectedPack,parcelContainer=parcelContainer and parcelContainer.d,
        autoDetect=auto_detect(),reason=lastReason,coinsUncertain=coinsUncertain} end
    function api.exportState()
        return {state=parcelState,container=parcelState=="bag" and copy_container(parcelContainer) or nil,
            coinsUncertain=coinsUncertain}
    end
    function api.restoreState(snapshot)
        if disposed then return false,"obsluga pojemnikow wylaczona" end
        if active then return false,"trwa operacja pojemnika; nie mozna przywrocic stanu" end
        if type(snapshot)~="table" or not ({hands=true,bag=true,unknown=true})[snapshot.state] then
            return false,"nieprawidlowy zapis stanu paczki"
        end
        if snapshot.coinsUncertain~=nil and type(snapshot.coinsUncertain)~="boolean" then
            return false,"nieprawidlowy zapis stanu monet"
        end
        local container=snapshot.state=="bag" and saved_container(snapshot.container) or nil
        parcelVersion=parcelVersion+1
        pending,coinPending,coinReceipt=nil,nil,0
        parcelContainer,detectedPack,lastReason=container,nil,nil
        parcelState=snapshot.state=="bag" and (container and "bag" or "unknown") or snapshot.state
        coinsUncertain=snapshot.coinsUncertain==true
        -- Restoring belongs to the caller's atomic checkpoint recovery. Never
        -- send, call an operation callback or persist a half-restored job here.
        if snapshot.state=="bag" and not container then return false,"brak poprawnego zapisu pojemnika paczki" end
        return true
    end
    function api.setParcelState(state)
        if state~="hands" and state~="bag" and state~="unknown" then return false end
        parcelVersion=parcelVersion+1
        parcelState,pending,parcelContainer=state,nil,nil
        state_changed()
        if active and active.parcel then finish(active,false,"stan paczki zostal zmieniony przez potwierdzenie gry") end
        return true
    end
    function api.cancel()
        if active then finish(active,false,"przerwane") end
    end

    local function commands(kind,verb,item)
        if not bags or type(bags.commands)~="function" then return nil,"brak API pojemnikow Chimery" end
        local ok,list=pcall(bags.commands,verb,{[kind]={item}})
        if not ok or type(list)~="table" then return nil,"nie udalo sie odczytac konfiguracji pojemnika" end
        local found={}
        local prefix=verb.." "..item..(verb=="wloz" and " do " or " z ")
        for _,command in ipairs(list) do
            if type(command)~="string" or command:find("[\r\n;]") then return nil,"nieobslugiwana zlozona komenda pojemnika" end
            local text=norm(command)
            if text:sub(1,#prefix)==prefix then
                if found.move then return nil,"niejednoznaczna komenda przeniesienia" end
                found.move,found.d=command,text:sub(#prefix+1)
            elseif text:match("^otworz ") then found.open,found.b=command,text:sub(8)
            elseif text:match("^zamknij ") then found.close=command;found.b=found.b or text:sub(9)
            else return nil,"nieoczekiwana komenda API pojemnikow" end
        end
        if not found.move or not found.d or found.d=="" then return nil,"brak skonfigurowanej komendy przeniesienia" end
        found.containerWord,found.openWord=last_word(found.d),last_word(found.b)
        return found
    end
    local function own_transfer(record,text)
        if not record or record.consumed then return false end
        if record.verb=="wloz" then
            if not text:match("^wkladasz ") then return false end
        elseif not text:match("^bierzesz ") and not text:match("^wyjmujesz ") then return false end
        if record.parcel then
            if not word(text,"paczke") then return false end
        elseif not text:find("monet",1,true) then return false end
        local preposition=record.verb=="wloz" and " do " or " z "
        local at=text:find(preposition,1,true)
        if not at then return false end
        local destination=text:sub(at+#preposition)
        return not record.containerWord or word(destination,record.containerWord)
    end
    local function parcel_transfer(record)
        parcelState=record.verb=="wloz" and "bag" or "hands"
        parcelContainer=record.verb=="wloz" and copy_commands(record.commands) or nil
        state_changed()
    end
    local function receipt(transfer)
        local changed=not transfer.receipted or coinsUncertain
        if not transfer.receipted then
            transfer.receipted=true
            -- Only storage proves that delivery money has been put away.
            -- Withdrawing fare must not advance that settlement receipt.
            if transfer.verb=="wloz" then coinReceipt=coinReceipt+1
            elseif transfer.verb=="wez" then coinWithdrawalReceipt=coinWithdrawalReceipt+1 end
        end
        if coinPending==transfer then coinPending=nil end
        coinsUncertain=false
        if changed then state_changed() end
    end
    local close_after_move,move,open,prepare
    local function confirmed(op)
        if not alive(op) then return end
        op.confirmed=true
        clear(op,"timer")
        if op.parcel then close_after_move(op)
        else
            -- A coin command can produce one own reply per denomination.
            later(op,"settleTimer",settle,function() close_after_move(op) end)
        end
    end
    close_after_move=function(op)
        if not alive(op) then return end
        clear(op,"settleTimer")
        if not op.commands.close or not open_close() then finish(op,true);return end
        op.phase="close"
        later(op,"timer",timeout,function()
            finish(op,true,nil,{closeFailed=true,warning="przeniesienie potwierdzone; brak potwierdzenia zamkniecia"})
        end)
        send(op,op.commands.close)
    end
    move=function(op)
        if not alive(op) then return end
        op.phase,op.buffer,op.bufferLines="move",nil,0
        op.attempts=op.attempts+1
        local transfer={verb=op.verb,parcel=op.parcel,containerWord=op.commands.containerWord,
            version=parcelVersion,stateBefore=op.stateBefore,op=op,commands=copy_commands(op.commands)}
        op.transfer=transfer
        if op.parcel then parcelState,pending="unknown",transfer
        else coinPending,coinsUncertain=transfer,true end
        state_changed() -- checkpoint uncertainty before the command can leave
        if not alive(op) then return end
        later(op,"timer",timeout,function()
            finish(op,false,"brak potwierdzenia przeniesienia; nie powtarzam komendy")
        end)
        send(op,op.commands.move)
    end
    open=function(op)
        if not alive(op) then return end
        if not op.commands.open or not open_close() or op.attempts>=2 then
            finish(op,false,"pojemnik jest zamkniety; sprawdz /pojemniki otwieraj tak")
            return
        end
        clear(op,"timer")
        op.phase="open"
        later(op,"timer",timeout,function()
            if openTimeout<=timeout then finish(op,false,"brak potwierdzenia otwarcia pojemnika");return end
            -- Opening does not move the parcel or coins. Keep ownership of
            -- this exact request for a bounded delayed ACK; never resend it
            -- or start the transfer merely because the first timer elapsed.
            if not op.openWaitNotified then
                op.openWaitNotified=true
                if opts.say then pcall(opts.say,"Czekam na potwierdzenie otwarcia pojemnika; polecenie pozostaje bez ponawiania.") end
            end
            if not alive(op) or op.phase~="open" then return end
            later(op,"timer",openTimeout-timeout,function() finish(op,false,"brak potwierdzenia otwarcia pojemnika") end)
        end)
        send(op,op.commands.open)
    end
    prepare=function(op)
        if op.commands.open and open_close() then open(op) else move(op) end
    end
    local function closed(op)
        if not alive(op) or op.phase~="move" or op.confirmed then return end
        if op.transfer then op.transfer.consumed=true end
        if op.parcel then
            if pending==op.transfer then pending=nil end
            parcelState=op.stateBefore -- the server explicitly denied the move
        elseif coinPending==op.transfer then coinPending=nil;coinsUncertain=false end
        state_changed()
        open(op)
    end
    local function skip(op,reason,key)
        if not notices[key] then
            notices[key]=true
            if opts.say then opts.say(reason) end
        end
        finish(op,true,reason,{skipped=true})
    end
    local function container_commands(container,verb,item)
        local out=copy_commands(container)
        if out.detected then
            local enabled=open_close()
            out.open=enabled and "otworz "..out.b or nil
            out.close=enabled and "zamknij "..out.b or nil
        end
        if not open_close() then out.open,out.close=nil,nil end
        out.move=verb.." "..item..(verb=="wloz" and " do " or " z ")..out.d
        return out
    end
    local function collect_pack(op,text)
        local body=text:match("^nosisz na plecach (.+)")
        if body then op.packBuffer,op.packLines=body,1
        elseif op.packBuffer and not text:find("[:!?]") and op.packLines<4 then
            op.packBuffer,op.packLines=op.packBuffer.." "..text,op.packLines+1
        else op.packBuffer=nil;return end
        body=op.packBuffer
        if #body>1000 then op.packBuffer=nil;return end
        if not body:match("%.$") then return end
        op.packBuffer=nil
        body=body:gsub("%.$","")
        if last_word(body)~="plecak" or body:find("[;|%z\1-\31]") then return end
        -- bags.forms deliberately ignores adjectives when constructing MUD
        -- commands. It cannot validate prose: an unrelated actor/room line
        -- must not complete an unfinished first-person inventory fragment.
        local words={}
        for token in body:gmatch("%S+") do words[#words+1]=token end
        if words[#words]~="plecak" then return end
        for i=1,#words-1 do
            if not words[i]:match("^[a-z%-]+[yi]$") then return end
        end
        local ok,forms=pcall(bags.forms,body)
        if not ok or type(forms)~="table" or type(forms.b)~="string" or type(forms.d)~="string" then return end
        local b,d=norm(forms.b),norm(forms.d)
        if not b:match("^swoj ") or not d:match("^swojego ") or
            last_word(b)~="plecak" or last_word(d)~="plecaka" or (b..d):find("[;|\r\n]") then return end
        op.packCount=op.packCount+1
        op.pack={b=forms.b,d=forms.d,open="otworz "..forms.b,close="zamknij "..forms.b,
            containerWord="plecaka",openWord="plecak",name=forms.name or body,detected=true}
    end
    local function detect(op)
        op.phase,op.packCount="detect",0
        detectedPack=nil
        later(op,"timer",1.5,function()
            if not auto_detect() then
                skip(op,"Automatyczne wykrywanie plecaka zostalo wylaczone.","detect-disabled")
            elseif op.packCount==1 then
                detectedPack=op.pack.name
                op.commands=container_commands(op.pack,op.verb,op.item)
                prepare(op)
            elseif op.packCount>1 then
                skip(op,"Wykryto kilka noszonych plecakow; wybierz pojemnik w /pojemniki.","detect:"..op.kind)
            else
                skip(op,"Nie wykryto jednego noszonego plecaka w odpowiedzi na i; ustaw pojemnik w /pojemniki.","detect:"..op.kind)
            end
        end)
        send(op,"i")
    end
    local function start(kind,verb,item,done)
        if disposed then done({ok=false,reason="obsluga pojemnikow wylaczona",state=parcelState});return function() end end
        if active then done({ok=false,reason="trwa inna operacja pojemnika",state=parcelState});return function() end end
        -- A later operation owns its own replies. Never apply an obsolete
        -- cancelled coin transfer to a newer command's receipt.
        coinPending=nil
        lastReason=nil
        local parcel=kind=="inne"
        if parcel and ((verb=="wloz" and parcelState=="bag") or (verb=="wez" and parcelState=="hands")) then
            done({ok=true,skipped=true,state=parcelState});return function() end
        end
        local stored=parcel and verb=="wez" and parcelContainer
        local hasConfig=configured(kind)
        local automatic=auto_detect()
        if parcel and parcelState=="unknown" and (stored or hasConfig or automatic) then
            done({ok=false,uncertain=true,state=parcelState,reason="nie wiadomo, czy paczka jest w reku czy w pojemniku. Sprawdz pojemnik, wez paczke do rak i uzyj /paczki paczka <adresat>."})
            return function() end
        end
        local list,why
        -- Retrieval follows the container which actually accepted this parcel,
        -- even when the global loot settings changed during the trip.
        if stored then list=container_commands(stored,verb,item)
        elseif hasConfig then list,why=commands(kind,verb,item) end
        if (stored or hasConfig) and not list then done({ok=false,reason=why,state=parcelState});return function() end end
        local op={kind=kind,verb=verb,item=item,parcel=parcel,commands=list,done=done,stateBefore=parcelState,attempts=0}
        active=op
        if list then
            if not open_close() then list.open,list.close=nil,nil end
            prepare(op)
        elseif automatic and bags and type(bags.forms)=="function" then detect(op)
        else
            skip(op,"Aby chowac "..(parcel and "paczke" or "monety")..", ustaw pojemnik Chimery: /pojemniki "..kind.." plecak (lub wlasny pojemnik w /pojemniki).",kind)
        end
        return function() if active==op then finish(op,false,"przerwane") end end
    end
    function api.stowParcel(done) return start("inne","wloz","paczke",done) end
    function api.takeParcel(done) return start("inne","wez","paczke",done) end
    function api.stowCoins(done) return start("monety","wloz","monety",done) end
    function api.takeCoins(done) return start("monety","wez","monety",done) end

    local function on_line(raw)
        local text=norm(raw)
        local op=active
        -- Only an exact own reply from an outstanding transfer can update a
        -- cancelled parcel operation. It cannot invoke done or send anything.
        if pending and pending.version==parcelVersion and not (op and op.transfer==pending) then
            local late=pending
            if late.buffer then text=late.buffer.." "..text end
            if text:match("^wkladasz ") or text:match("^bierzesz ") or text:match("^wyjmujesz ") then
                if not text:match("[%.!]$") and #text<1000 then late.buffer=text
                else
                    late.buffer=nil
                    if own_transfer(late,text) then
                        late.consumed=true;pending=nil
                        parcel_transfer(late)
                    end
                end
            end
        end
        if coinPending and not (op and op.transfer==coinPending) then
            local late=coinPending
            local coinText=norm(raw)
            if late.buffer then coinText=late.buffer.." "..coinText end
            if (late.verb=="wloz" and coinText:match("^wkladasz ")) or
                (late.verb=="wez" and (coinText:match("^bierzesz ") or coinText:match("^wyjmujesz "))) then
                if not coinText:match("[%.!]$") and #coinText<1000 then late.buffer=coinText
                else
                    late.buffer=nil
                    if own_transfer(late,coinText) then
                        receipt(late)
                        late.consumed=true
                    end
                end
            end
        end
        op=active
        if not op or not alive(op) then return end
        if op.phase=="detect" then collect_pack(op,norm(raw));return end
        -- The late-reply parser may have joined a continuation; the live
        -- operation always gets its own original line and buffer instead.
        text=norm(raw)
        if op.buffer then text=op.buffer.." "..text end
        local relevant=text:match("^wkladasz ") or text:match("^bierzesz ") or text:match("^wyjmujesz ") or
            text:match("^nie jestes w stanie ")
        if relevant and not text:match("[%.!?]$") and #text<1000 and (op.bufferLines or 0)<6 then
            op.buffer,op.bufferLines=text,(op.bufferLines or 0)+1
            return
        end
        op.buffer,op.bufferLines=nil,0
        if op.phase=="move" and own_transfer(op.transfer,text) then
            if op.parcel then
                op.transfer.consumed=true
                if pending==op.transfer then pending=nil end
                parcel_transfer(op.transfer)
            else receipt(op.transfer) end
            confirmed(op)
        elseif op.phase=="move" and text:find("zamknietego pojemnika",1,true) and text:match("^nie jestes w stanie ") then
            closed(op)
        elseif op.phase=="open" then
            if (text:match("^otwierasz ") and (not op.commands.openWord or word(text,op.commands.openWord))) or already_open(text,op.commands) then
                clear(op,"timer");move(op)
            elseif text=="otworz co?" or text=="hmm?" then finish(op,false,"nie potwierdzono otwarcia skonfigurowanego pojemnika") end
        elseif op.phase=="close" then
            if text:match("^zamykasz ") and (not op.commands.openWord or word(text,op.commands.openWord)) then finish(op,true)
            elseif text=="zamknij co?" or text=="hmm?" then
                finish(op,true,nil,{closeFailed=true,warning="przeniesienie potwierdzone; pojemnik nie potwierdzil zamkniecia"})
            end
        elseif op.phase=="move" then
            if text=="wloz co do czego?" or text=="wez co z czego?" or text=="wloz co?" or text=="wez co?" or text=="hmm?" then
                if op.transfer then op.transfer.consumed=true end
                if op.parcel and pending==op.transfer then pending=nil;parcelState=op.stateBefore end
                if not op.parcel and coinPending==op.transfer then coinPending=nil;coinsUncertain=false end
                state_changed()
                finish(op,false,"gra nie rozpoznala komendy przeniesienia: "..text)
                return
            end
            local denied=text:match("^nie masz ") or text:match("^nie widzisz ") or text:match("^nie jestes w stanie ")
            local relevant=(op.parcel and text:find("pacz",1,true)) or (not op.parcel and text:find("monet",1,true)) or
                text:find("pojemnik",1,true) or (op.commands.containerWord and word(text,op.commands.containerWord))
            if denied and relevant then
                if op.transfer then op.transfer.consumed=true end
                if op.parcel and pending==op.transfer then pending=nil;parcelState=op.stateBefore end
                if not op.parcel and coinPending==op.transfer then coinPending=nil;coinsUncertain=false end
                state_changed()
                finish(op,false,"gra odmowila przeniesienia: "..text)
            end
        end
    end
    ctx:trigger("^",function(text) on_line(type(text)=="string" and text or rawget(_G,"line")) end)
    ctx:on("chimera.container.closed",function(event)
        local op=active
        if not op or not event then return end
        local action=norm(event.action)
        if (op.verb=="wloz" and action=="wlozyc") or
            (op.verb=="wez" and (action=="wziac" or action=="wyjac")) then closed(op) end
    end)
    ctx:on("chimera.session.end",function()
        coinPending,detectedPack=nil,nil
        if active then finish(active,false,"rozlaczenie") end
    end)
    ctx:on("chimera.paczki.actor.changed",function()
        pending,coinPending,parcelContainer,detectedPack=nil,nil,nil,nil
        coinsUncertain=false
        if active then finish(active,false,"zmieniono postac") end
    end)
    if ctx.cleanup then ctx:cleanup(function()
        disposed=true
        if active then finish(active,false,"przeladowanie kuriera") end
        -- Keep confirmed semantic state readable for a final checkpoint even
        -- after cleanup, while discarding every live acknowledgement token.
        pending,coinPending,detectedPack=nil,nil,nil
    end) end
    return api
end
