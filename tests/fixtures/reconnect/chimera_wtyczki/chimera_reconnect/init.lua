-- Independent native Chimera plugin. Credentials remain owned by Mudlet.
package.loaded["chimera_reconnect.core"] = nil
local create = require("chimera_reconnect.core")

return {
    name = "paczki_reconnect",
    title = "Paczki / Reconnect",
    section = "boty",
    version = "1.0.0",
    description = "Ponowne polaczenie i wznowienie aktywnego kuriera tej samej postaci",
    deps = { "kurier_paczki", "bots", "gmcp", "mapper" },
    related = { "kurier_paczki", "bots", "gmcp" },

    setup = function(original)
        -- beta.13 Context IDs overlap between timers, events and the bus.
        -- Use the exact-resource facade already shipped with Paczki 1.5.7.
        local ctx = require("chimera_paczki.scope")(original)
        local paczki, bots = ctx:use("kurier_paczki"), ctx:use("bots")
        local gmcp_api, mapper = ctx:use("gmcp"), ctx:use("mapper")
        local engine = assert(paczki.engine, "Wymagany bot Chimera Paczki 1.5.7 lub nowszy")
        local observedConnected = gmcp_api.connected()
        local controller
        local function courierStatus(status)
            return type(status) == "string" and (status == "Bot paczki" or status:match("^Bot paczki:" ) ~= nil)
        end
        local function validVitals(vitals)
            local hp, fatigue = type(vitals) == "table" and tonumber(vitals.hp), type(vitals) == "table" and tonumber(vitals.fatigue)
            return type(hp) == "number" and hp == hp and hp >= 0 and hp <= 100 and
                type(fatigue) == "number" and fatigue == fatigue and fatigue >= 0 and fatigue <= 100
        end
        local function connection()
            if type(getConnectionInfo) == "function" then
                local ok, _, _, connected = pcall(getConnectionInfo)
                if ok and type(connected) == "boolean" then return connected end
            end
            return observedConnected == true
        end
        local function isReady(actor)
            local character, room, vitals = gmcp_api.char(), gmcp_api.room(), gmcp_api.vitals()
            if not connection() or not gmcp_api.connected() or bots.status() or
                not character or engine.norm(character.name) ~= actor or engine.actor ~= actor or
                not room or type(room.id) ~= "string" or not validVitals(vitals) then return false end
            local map = mapper.current_room()
            return type(map) == "number" and map > 0 and mapper.chimera_id(map) == room.id
        end
        controller = create({
            schedule = function(seconds, callback) return ctx:timer(seconds, callback) end,
            cancel = function(handle) return ctx:cancel(handle) end,
            connection = connection,
            reconnect = function()
                assert(type(reconnect) == "function", "Mudlet nie udostepnia reconnect()")
                -- Preserve this profile's host, port, TLS and proxy settings.
                return reconnect()
            end,
            isReady = isReady,
            launch = function()
                -- The public command reacquires Boty ownership and validates
                -- the saved course, physical-operation uncertainty and limit.
                if not ctx.app.commands:dispatch("/paczki wznow") then return false end
                local status = bots.status()
                return courierStatus(status) and
                    (engine.mode == "running" or engine.mode == "resting" or engine.mode == "recovering")
            end,
            request = function()
                if connection() and type(sendGMCP) == "function" then
                    pcall(sendGMCP, 'Core.Supports.Remove ["Char","Room"]')
                    pcall(sendGMCP, 'Core.Supports.Add ["Char 2","Room 1"]')
                end
            end,
            say = function(message) ctx.log.info(message) end,
            save = function(value) ctx:save("ustawienia", value) end,
            now = function() return type(getEpoch) == "function" and getEpoch() or os.time() end,
        }, ctx:saved("ustawienia", {}))

        -- A normal dependent listener runs AFTER Paczki has paused itself.
        -- A bus tap captures only its active intent before those listeners;
        -- the canonical GMCP cache has already been cleared at this point.
        local bus = ctx.app.bus
        local tap = bus:tap(ctx:wrap("zapis wznowienia po rozlaczeniu", function(event)
            if event ~= "chimera.session.end" then return end
            local status = bots.status()
            local mode = engine.mode
            controller:sessionLost({ actor = engine.actor,
                active = courierStatus(status) and
                    (mode == "running" or mode == "resting" or mode == "recovering") })
        end))
        ctx:cleanup(function() bus:untap(tap) end)

        ctx:on("sysDisconnectionEvent", function()
            observedConnected = false
            controller:disconnected()
        end)
        ctx:on("sysConnectionEvent", function()
            observedConnected = true
            controller:connected()
        end)
        ctx:on("chimera.session.start", function()
            observedConnected = true
            controller:check()
        end)
        ctx:on("chimera.char.info", function(character)
            if type(character) == "table" and type(character.name) == "string" and character.name ~= "" then
                controller:charInfo(engine.norm(character.name))
            end
        end)
        ctx:on("chimera.room.info", function(room)
            if type(room) == "table" and type(room.id) == "string" and room.id ~= "" then controller:roomInfo() end
        end)
        ctx:on("chimera.char.vitals", function(vitals)
            if validVitals(vitals) then controller:vitals() end
        end)
        ctx:on("chimera.bots.changed", function(status)
            if status then controller:botStarted() end
        end)
        ctx:on("chimera.numpad.pressed", function() controller:manual("Reczny ruch anulowal automatyczne wznowienie.") end)
        ctx:on("chimera.step.manual", function() controller:manual("Reczny ruch anulowal automatyczne wznowienie.") end)
        ctx:on("sysDataSendRequest", function()
            -- Mudlet's own auto-login can send name/password before Char.Info.
            -- Never inspect, retain or print that input. In-world input after
            -- authentication is an explicit takeover of the pending course.
            local state = controller:status()
            if state.pendingActor and state.freshChar then
                controller:manual("Reczna komenda anulowala automatyczne wznowienie.")
            end
        end)

        -- Slash commands do not generate sysDataSendRequest. Observe only
        -- control commands, leaving panel queries/configuration untouched.
        for _, entry in ipairs(ctx.app.commands.entries) do
            if (entry.name == "bot" or entry.name == "paczki") and not entry.custom then
                local target, previous = entry, entry.fn
                local wrapped = function(arg)
                    local action = engine.norm(arg or ""):match("^(%S+)")
                    if (target.name == "bot" and action) or
                        (target.name == "paczki" and ({stop=true,pauza=true,pause=true,reset=true,
                            start=true,wznow=true,resume=true,poczta=true,ucz=true,paczka=true})[action or ""]) or
                        (target.name == "paczki" and engine.norm(arg or "") == "poczty stop") then
                        controller:manual("Komenda sterowania anulowala automatyczne wznowienie.")
                    end
                    return previous(arg)
                end
                target.fn = wrapped
                ctx:cleanup(function() if target.fn == wrapped then target.fn = previous end end)
            end
        end

        local function panel()
            local state = controller:status()
            local network = ({connected="polaczony",waiting="czekam na probe",connecting="laczenie",idle="bez proby"})[state.network] or state.network
            ctx:report("Paczki / Reconnect 1.0.0", {
                {"Automat", state.enabled and "WLACZONY" or "WYLACZONY"},
                {"Polaczenie", network or "brak danych"},
                {"Wznowienie", state.pendingActor or "brak oczekujacego kursu"},
                {"Swieze GMCP", string.format("postac: %s; lokacja: %s; stan: %s",
                    state.freshChar and "tak" or "nie", state.freshRoom and "tak" or "nie", state.freshVitals and "tak" or "nie")},
                {"Proby", tostring(state.attempts or 0)},
                {"Sterowanie", {{text="[wlacz]",link="/paczki_net on",hint="Wlacz reconnect i wznowienie aktywnych paczek"},
                    {text="  "},{text="[wylacz]",link="/paczki_net off",hint="Anuluj kolejne proby i oczekujace wznowienie"}}},
                {"Informacja", state.lastReason or ""},
            })
        end
        local function command(arg)
            local action = engine.norm(arg or "")
            if action == "on" or action == "wlacz" then
                controller:setEnabled(true)
                ctx.log.info("Reconnect paczek wlaczony. Wylaczenie: /knet off lub /paczki_net off.")
            elseif action == "off" or action == "wylacz" then
                controller:setEnabled(false)
                ctx.log.info("Reconnect paczek wylaczony; proby i oczekujace wznowienie anulowane.")
            elseif action == "" or action == "status" or action == "stan" then panel()
            else ctx.log.info("/knet on | off | status; rowniez /paczki_net on | off | status") end
        end
        ctx:command{"paczki_net", args="[on|off|status]", help="Reconnect i wznowienie paczek: on wlacza, off anuluje", fn=command}
        if not ctx.app.commands.by_name.knet then
            ctx:command{"knet", args="[on|off|status]", help="Automatyczny reconnect paczek; on/off/status", fn=command}
        else
            ctx.log.warn("/knet nalezy do innego modulu. Tutaj uzywaj /paczki_net; wylacz stary automat reconnect.")
        end
        ctx:cleanup(function() controller:shutdown() end)
        -- Saved preference survives reload. Pending courses deliberately do
        -- not survive shutdown/reload or a fresh process as active intent.
        controller:setEnabled(controller:status().enabled)
        return { controller=controller, version="1.0.0", panel=panel }
    end,
}
