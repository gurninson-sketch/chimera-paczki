-- Profile-local reconnect controller. No credentials or executable course state.
-- All effects are injected; kept compatible with Mudlet's Lua 5.1 runtime.
return function(opts, saved)
    opts = opts or {}
    local C = {}
    local enabled = type(saved)=="table" and saved.schema==1 and saved.enabled==true or false
    local disposed = false
    local pendingActor
    local freshChar, freshRoom, freshVitals = false, false, false
    local attempts = 0
    local lastReason
    local timers, serial = {}, 0
    local connectedAt, lastRequest, lastWarning
    local observedConnected = false

    local function clock()
        if type(opts.now)=="function" then
            local ok, value = pcall(opts.now)
            if ok and type(value)=="number" then return value end
        end
        return os.time()
    end
    local function say(text)
        if type(opts.say)=="function" then pcall(opts.say, text) end
    end
    local function connection()
        if type(opts.connection)~="function" then return false end
        local ok, result = pcall(opts.connection)
        return ok and result==true
    end
    local function norm(name)
        if type(name)~="string" then return nil end
        name = name:gsub("^%s+", ""):gsub("%s+$", ""):lower()
        return name~="" and name or nil
    end
    local function cancel(key)
        local timer = timers[key]
        timers[key] = nil
        if timer and timer.id and type(opts.cancel)=="function" then pcall(opts.cancel, timer.id) end
    end
    local function schedule(key, delay, callback)
        cancel(key)
        if disposed then return end
        serial = serial+1
        local timer = {serial=serial}
        timers[key] = timer
        timer.id = opts.schedule(delay, function()
            -- A cancelled callback can already be queued in the event loop.
            if disposed or timers[key]~=timer then return end
            timers[key] = nil
            callback()
        end)
    end
    local function clearFresh()
        freshChar, freshRoom, freshVitals = false, false, false
        lastRequest, lastWarning, connectedAt = nil, nil, nil
    end
    local function clearLease(reason)
        pendingActor = nil
        clearFresh()
        cancel("poll")
        cancel("launch")
        if reason then lastReason=reason end
    end
    local function ready()
        if disposed or not enabled or not pendingActor or not freshChar or not freshRoom or not freshVitals or not connection() then
            return false
        end
        if type(opts.isReady)~="function" then return false end
        local ok, result = pcall(opts.isReady, pendingActor)
        return ok and result==true and not disposed and enabled and pendingActor~=nil
    end
    local function stopNetwork()
        cancel("network")
        cancel("watchdog")
    end
    local function backoff()
        return math.min(60, 6 * 2^math.min(math.max(attempts-1,0),4))
    end
    local ensureNetwork, poll, check
    local function markConnected()
        if not observedConnected then
            clearFresh()
            connectedAt=clock()
        end
        observedConnected=true
        stopNetwork()
        attempts=0
    end
    local function livePacket()
        if not connection() then
            -- Queued packets from a dead socket cannot prime a new session.
            clearFresh()
            cancel("launch")
            observedConnected=false
            return false
        end
        -- Observe the connection BEFORE recording this packet, preserving a
        -- valid first packet that precedes the queued sysConnectionEvent.
        markConnected()
        return true
    end
    local function attempt()
        if disposed or not enabled then return end
        if connection() then markConnected();check();return end
        observedConnected=false
        attempts=attempts+1
        local ok, result = pcall(opts.reconnect)
        -- Native auto-reconnect may have won while reconnect() was running.
        if disposed or not enabled then return end
        if connection() then markConnected();check();return end
        -- Some clients synchronously raise a failure/disconnect inside the
        -- reconnect call; that callback already owns the next retry timer.
        if timers.network or timers.watchdog then return end
        if not ok or result==false then
            lastReason="Nie udalo sie polaczyc; ponowie probe."
            ensureNetwork(backoff())
            return
        end
        schedule("watchdog", 30, function()
            if not enabled then return end
            if connection() then markConnected();check()
            else ensureNetwork(backoff()) end
        end)
    end
    ensureNetwork = function(delay)
        if disposed or not enabled or timers.network or timers.watchdog then return end
        if connection() then markConnected();return end
        observedConnected=false
        schedule("network", delay or (attempts>0 and backoff() or 3), attempt)
    end
    poll = function()
        if disposed or not enabled or not pendingActor or timers.poll then return end
        schedule("poll", 1, function() check() end)
    end
    check = function()
        if disposed or not enabled then return end
        local connected = connection()
        if connected then markConnected()
        else
            observedConnected=false
            connectedAt=nil
            ensureNetwork()
        end
        if not pendingActor then return end
        if connected then
            local now = clock()
            connectedAt=connectedAt or now
            if not lastRequest or now-lastRequest>=15 then
                lastRequest=now
                if type(opts.request)=="function" then pcall(opts.request) end
                -- Requests can synchronously dispatch fresh packets or STOP.
                if disposed or not enabled or not pendingActor then return end
            end
            if now-connectedAt>=30 and (not lastWarning or now-lastWarning>=60) then
                lastWarning=now
                say("Polaczenie jest aktywne. Czekam na zalogowanie i aktualne dane postaci; automatyczne logowanie ustaw w profilu Mudleta.")
            end
            if ready() and not timers.launch then
                local actor=pendingActor
                schedule("launch", 0.05, function()
                    if pendingActor~=actor or not ready() then poll();return end
                    -- Consume before dispatch: bot events and late callbacks
                    -- can never cause the same loss to launch twice.
                    clearLease()
                    local ok, result = pcall(opts.launch)
                    if ok and result==true then
                        lastReason="Wznowiono bota paczkowego po ponownym polaczeniu."
                    else
                        lastReason="Paczki nie wznowily pracy. Zachowuje decyzje bota; sprawdz /paczki."
                    end
                    say(lastReason)
                end)
            end
        end
        poll()
    end

    function C:setEnabled(value)
        if disposed then return false end
        enabled=value==true
        if type(opts.save)=="function" then pcall(opts.save, {schema=1,enabled=enabled}) end
        if not enabled then
            stopNetwork()
            clearLease("Automatyczne laczenie i wznawianie wylaczone.")
        else check() end
        return enabled
    end
    function C:sessionLost(snapshot)
        if disposed then return end
        snapshot=type(snapshot)=="table" and snapshot or {}
        local actor=norm(snapshot.actor)
        if enabled and snapshot.active==true and actor then
            pendingActor=actor
            lastReason="Polaczenie przerwane; kurs wznowi sie po zalogowaniu tej samej postaci."
        end
        -- Duplicate loss notifications preserve the existing lease, but never
        -- preserve freshness from a preceding connection.
        clearFresh()
        cancel("launch")
        observedConnected=false
        if enabled then ensureNetwork();poll() end
    end
    function C:disconnected()
        if disposed then return end
        clearFresh()
        cancel("launch")
        observedConnected=false
        if timers.watchdog then
            cancel("watchdog")
            ensureNetwork(backoff())
        else ensureNetwork() end
        poll()
    end
    function C:connected()
        if disposed then return end
        markConnected()
        if enabled then check() end
    end
    function C:charInfo(name)
        if disposed or not enabled or not pendingActor then return end
        if not livePacket() then return end
        local actor=norm(name)
        if not actor then return end
        if actor~=pendingActor then
            clearLease("Zalogowano inna postac; automatyczne wznowienie anulowane.")
            say(lastReason)
            return
        end
        freshChar=true
        check()
    end
    function C:roomInfo()
        if disposed or not enabled or not pendingActor then return end
        if not livePacket() then return end
        freshRoom=true
        check()
    end
    function C:vitals()
        if disposed or not enabled or not pendingActor then return end
        if not livePacket() then return end
        freshVitals=true
        check()
    end
    function C:manual(reason)
        if disposed then return end
        clearLease(reason or "Reczna komenda anulowala automatyczne wznowienie.")
    end
    function C:botStarted()
        self:manual("Bot zostal uruchomiony; automatyczne wznowienie anulowane.")
    end
    function C:check() check() end
    function C:shutdown()
        if disposed then return end
        disposed=true
        stopNetwork()
        clearLease("Wtyczka zatrzymana.")
    end
    function C:status()
        local network=connection() and "connected" or
            (enabled and not disposed and timers.watchdog and "connecting") or
            (enabled and not disposed and timers.network and "waiting") or "idle"
        return {enabled=enabled,pendingActor=pendingActor,attempts=attempts,network=network,
            freshChar=freshChar,freshRoom=freshRoom,freshVitals=freshVitals,lastReason=lastReason}
    end
    return C
end
