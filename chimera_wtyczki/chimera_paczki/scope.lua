-- Resource isolation for Chimera 5.0.0-beta.13. Its Context:cancel/forget
-- compare raw IDs across independent timer/event/trigger/bus ID domains.
-- This facade returns unique table leases and cancels exact registrations.
local unpack=unpack or table.unpack

return function(original)
    assert(type(original)=="table" and type(original.handles)=="table", "scope requires a Chimera Context")
    local facade,records,cleanupOrder={}, {}, {}
    local closed=false
    function facade:isClosed() return closed end

    local function remove_tracked(handle)
        for index=#original.handles,1,-1 do
            if original.handles[index]==handle then
                table.remove(original.handles,index)
                return true
            end
        end
        return false
    end

    local function retire(lease)
        local record=records[lease]
        if not record then return nil end
        records[lease]=nil;lease.active=false
        return record
    end

    local function cancel(lease)
        local record=retire(lease)
        if not record then return false end
        if record.handle then
            remove_tracked(record.handle)
            pcall(record.handle.kill)
        elseif record.kind=="timer" and record.raw~=nil then
            pcall(killTimer,record.raw)
        elseif record.kind=="cleanup" then
            record.callback()
        end
        return true
    end

    local function new_lease(kind)
        assert(not closed,"resource scope is closed")
        local lease={active=true,kind=kind}
        local record={kind=kind}
        records[lease]=record
        return lease,record
    end

    local function register(method,kind,args,callbackIndex)
        local callback=args[callbackIndex]
        assert(type(callback)=="function","resource callback must be a function")
        local lease,record=new_lease(kind)
        args[callbackIndex]=function(...)
            if closed or not lease.active or records[lease]~=record then return end
            return callback(...)
        end
        local before={}
        for _,handle in ipairs(original.handles) do before[handle]=true end
        local ok,raw=pcall(original[method],original,unpack(args,1,args.n))
        if not ok then retire(lease);error(raw,0) end
        for index=#original.handles,1,-1 do
            local handle=original.handles[index]
            if not before[handle] and handle.kind==kind and handle.id==raw then
                record.handle=handle
                return lease
            end
        end
        -- Fail closed if a future Context changes its registration contract.
        -- The wrapper is inactive even if the host keeps a queued callback.
        retire(lease)
        if kind=="bus" and original.app and original.app.bus then pcall(original.app.bus.off,original.app.bus,raw)
        elseif kind=="event" and type(killAnonymousEventHandler)=="function" then pcall(killAnonymousEventHandler,raw)
        elseif kind=="trigger" and type(killTrigger)=="function" then pcall(killTrigger,raw) end
        error("cannot capture the exact Chimera "..kind.." registration",0)
    end

    function facade:on(event,callback)
        local kind=type(event)=="string" and event:find("^chimera%.") and "bus" or "event"
        return register("on",kind,{event,callback,n=2},2)
    end
    function facade:make_trigger(kind,pattern,callback)
        return register("make_trigger","trigger",{kind,pattern,callback,n=3},3)
    end
    function facade:trigger(pattern,callback)
        return register("trigger","trigger",{pattern,callback,n=2},2)
    end
    function facade:trigger_substring(pattern,callback)
        return register("trigger_substring","trigger",{pattern,callback,n=2},2)
    end
    function facade:trigger_begin(pattern,callback)
        return register("trigger_begin","trigger",{pattern,callback,n=2},2)
    end
    function facade:trigger_exact(pattern,callback)
        return register("trigger_exact","trigger",{pattern,callback,n=2},2)
    end

    function facade:timer(seconds,callback,repeating)
        assert(type(callback)=="function","timer callback must be a function")
        local lease,record=new_lease("timer")
        local wrapped=original:wrap("timer",callback)
        local function fired(...)
            if closed or not lease.active or records[lease]~=record then return end
            if not repeating then retire(lease) end
            return wrapped(...)
        end
        local ok,raw
        if repeating then ok,raw=pcall(tempTimer,seconds,fired,true)
        else ok,raw=pcall(tempTimer,seconds,fired) end
        if not ok then retire(lease);error(raw,0) end
        record.raw=raw
        if not lease.active then pcall(killTimer,raw) end
        return lease
    end

    function facade:cancel(lease)
        if records[lease] then return cancel(lease) end
        -- Delegated command/cleanup registrations can return unique tables.
        -- Numeric raw IDs are intentionally not accepted: their domain is
        -- ambiguous and using original:cancel(number) would reintroduce it.
        if type(lease)=="table" then
            for index=#original.handles,1,-1 do
                local handle=original.handles[index]
                if handle.id==lease then
                    table.remove(original.handles,index)
                    pcall(handle.kill)
                    return true
                end
            end
        end
        return false
    end

    function facade:cleanup(callback)
        assert(type(callback)=="function","cleanup callback must be a function")
        local lease,record=new_lease("cleanup")
        record.callback=original:wrap("sprzatanie zakresu",callback)
        cleanupOrder[#cleanupOrder+1]=lease
        return lease
    end

    local function shutdown()
        if closed then return end
        closed=true
        -- Callbacks see a closed scope before cleanup can emit nested events.
        -- Run user cleanup in reverse registration order, once, then remove
        -- every remaining registration by object identity.
        for index=#cleanupOrder,1,-1 do
            local lease=cleanupOrder[index]
            if records[lease] then cancel(lease) end
        end
        cleanupOrder={}
        local leases={}
        for lease in pairs(records) do leases[#leases+1]=lease end
        for _,lease in ipairs(leases) do cancel(lease) end
    end

    -- Register first, so Context:dispose reaches this after its ordinary
    -- handles. Removing tracked registrations here cannot invalidate lower
    -- indices in the upstream reverse-index disposal loop.
    original:cleanup(shutdown)

    return setmetatable(facade,{
        __index=function(_,key)
            local value=original[key]
            if type(value)~="function" then return value end
            return function(first,...)
                if first==facade then return value(original,...) end
                return value(original,first,...)
            end
        end,
        __newindex=function(_,key,value) original[key]=value end,
    })
end
