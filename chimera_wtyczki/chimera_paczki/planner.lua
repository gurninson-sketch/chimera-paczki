-- Cooperative, cancellable CPU work. Only the executing worker can yield or
-- access its cache; unrelated game events never inherit a suspended worker.
return function(ctx, options)
    options=options or {}
    local clock=options.clock or os.clock
    local budget=options.budget or 0.005
    local quantum=options.quantum or 64
    local delay=options.delay or 0.001
    local unpackValues=table.unpack or unpack
    local jobs,threads={},setmetatable({},{__mode="k"})
    local disposed=false
    local stats={active=0,started=0,completed=0,cancelled=0,slices=0,yields=0,maxSliceMs=0}
    local api={version="1.5.11"}
    local function current()
        local thread=coroutine.running()
        return thread and threads[thread] or nil
    end
    function api.active() return current()~=nil end
    function api.cache() local job=current();return job and job.cache or nil end
    function api.status()
        local result={};for key,value in pairs(stats) do result[key]=value end;return result
    end
    function api.checkpoint()
        local job=current()
        if not job then return false end
        job.units=job.units+1
        if job.units>=quantum or clock()-job.startedAt>=budget then
            stats.yields=stats.yields+1
            coroutine.yield()
        end
        return true
    end
    function api.run(work,done,valid)
        assert(type(work)=="function" and type(done)=="function","planner callbacks required")
        if disposed then return function() end end
        local job={cache={},units=0,startedAt=clock()}
        job.thread=coroutine.create(work)
        threads[job.thread]=job;jobs[job]=true
        stats.active=stats.active+1;stats.started=stats.started+1
        local function release(cancelled)
            if not jobs[job] then return false end
            jobs[job]=nil;threads[job.thread]=nil
            if job.timer then ctx:cancel(job.timer);job.timer=nil end
            job.cache=nil;job.thread=nil
            stats.active=stats.active-1
            if cancelled then stats.cancelled=stats.cancelled+1 end
            return true
        end
        local function cancel() release(true) end
        job.cancel=cancel
        local function pack(...) return {n=select("#",...),...} end
        local resume
        resume=function()
            job.timer=nil
            if disposed or not jobs[job] then return end
            if valid then
                local good,accepted,reason=pcall(valid)
                if not good or not accepted then
                    release(true)
                    done(false,nil,good and (reason or "planowanie przerwane") or accepted)
                    return
                end
            end
            job.units=0;job.startedAt=clock();stats.slices=stats.slices+1
            local result=pack(coroutine.resume(job.thread))
            stats.maxSliceMs=math.max(stats.maxSliceMs,1000*math.max(0,clock()-job.startedAt))
            if not result[1] then
                release(false);done(false,nil,tostring(result[2]));return
            end
            if coroutine.status(job.thread)=="dead" then
                release(false);stats.completed=stats.completed+1
                done(true,unpackValues(result,2,result.n));return
            end
            job.timer=ctx:timer(delay,resume)
        end
        job.timer=ctx:timer(delay,resume)
        return cancel
    end
    function api.dispose()
        if disposed then return end
        disposed=true
        local pending={};for job in pairs(jobs) do pending[#pending+1]=job end
        for _,job in ipairs(pending) do job.cancel() end
    end
    ctx:cleanup(api.dispose)
    return api
end
