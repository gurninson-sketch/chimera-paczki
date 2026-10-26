-- Local replacement for the beta.13 idz action. Bus.emit snapshots handlers:
-- a room-progress callback can still run after a nested arrived event has
-- removed it. Every callback therefore checks the operation before doing work.
local STALL = 60

return function(ctx, walker)
    local api, active, generation, disposed = {}, nil, 0, false

    local function alive(op)
        return not disposed and active == op and not op.finished and op.generation == generation
    end

    local function clear(op, key)
        local handle = op[key]
        op[key] = nil
        if handle then ctx:cancel(handle) end
    end

    local function complete(op, result, stopReason)
        -- Cleanup can terminate an operation after marking the factory
        -- disposed. All event/timer callbacks separately require alive().
        if active ~= op or op.finished or op.generation ~= generation then return end
        -- Invalidate before stop(), which can synchronously emit stopped or
        -- before done(), which can immediately start another journey.
        op.finished, active = true, nil
        clear(op, "stall")
        clear(op, "progress")
        clear(op, "arrived")
        clear(op, "stopped")
        if stopReason then walker.stop(stopReason) end
        op.done(result)
    end

    function api.idz(destination, done)
        if disposed then
            done({ ok = false, reason = "nawigacja wylaczona" })
            return function() end
        end
        local previousGeneration = generation
        if active then complete(active, { ok = false, reason = "przerwane" }, "zastapiono nawigacje") end
        if disposed or generation ~= previousGeneration then
            done({ ok = false, reason = "nawigacja zostala zastapiona" })
            return function() end
        end
        generation = generation + 1
        local op = { generation = generation, done = done }
        active = op
        local function cancel()
            complete(op, { ok = false, reason = "przerwane" }, "bot zatrzymany")
        end
        local resolved, target, problem = pcall(walker.resolve, tostring(destination))
        if not resolved or type(target) ~= "number" or target <= 0 then
            complete(op, { ok = false, reason = resolved and (problem or "nieprawidlowy cel mapy") or tostring(target) })
            return cancel
        end
        if not alive(op) then return cancel end
        op.target = target

        local function watch()
            if not alive(op) then return end
            clear(op, "stall")
            if not alive(op) then return end
            op.stall = ctx:timer(STALL, function()
                if not alive(op) then return end
                op.stall = nil
                complete(op, { ok = false, reason = "brak postepu" }, "brak postepu")
            end)
        end
        op.arrived = ctx:on("chimera.walk.arrived", function(event)
            if not alive(op) then return end
            if event and event.map_room == op.target then complete(op, { ok = true }) end
        end)
        op.stopped = ctx:on("chimera.walk.stopped", function(event)
            if not alive(op) then return end
            complete(op, { ok = false, reason = event and event.reason or "przerwane" })
        end)
        op.progress = ctx:on("chimera.room.changed", watch)
        if not alive(op) then return cancel end
        local started, ok, why = pcall(walker.go, target)
        -- go() may finish synchronously (or emit arrived before returning).
        if not alive(op) then return cancel end
        if not started then
            complete(op, { ok = false, reason = tostring(ok) }, "blad nawigacji")
        elseif ok == "tutaj" then
            complete(op, { ok = true })
        elseif not ok then
            complete(op, { ok = false, reason = why or "nie udalo sie rozpoczac drogi" })
        else
            watch()
        end
        return cancel
    end

    if ctx.cleanup then ctx:cleanup(function()
        disposed = true
        if active then complete(active, { ok = false, reason = "przeladowanie kuriera" }, "przeladowanie kuriera") end
        generation = generation + 1
    end) end
    return api
end
