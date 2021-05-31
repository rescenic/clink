-- Copyright (c) 2021 Christopher Antos
-- License: http://opensource.org/licenses/MIT

--------------------------------------------------------------------------------
clink = clink or {}
local _coroutines = {}
local _after_coroutines = {}
local _coroutines_resumable = false
local _coroutine_infinite = nil

--------------------------------------------------------------------------------
local function clear_coroutines()
    _coroutines = {}
    _after_coroutines = {}
    _coroutines_resumable = false
    _coroutine_infinite = nil
end
clink.onbeginedit(clear_coroutines)

--------------------------------------------------------------------------------
local function after_coroutines()
    for _,func in pairs(_after_coroutines) do
        func()
    end
end

--------------------------------------------------------------------------------
local function next_entry_target(entry, now)
    if not entry.lastclock then
        return 0
    else
        -- Throttle any coroutine that's been running for 5 or more seconds and
        -- wants to run more frequently than every 5 seconds.  They still get to
        -- run, but only once every 5 seconds.
        local interval = entry.interval
        if interval < 5 and now and entry.firstclock and now - entry.firstclock > 5 then
            interval = 5
        end
        return entry.lastclock + interval
    end
end

--------------------------------------------------------------------------------
function clink._after_coroutines(func)
    if type(func) ~= "function" then
        error("bad argument #1 (function expected)")
    end
    _after_coroutines[func] = func
end

--------------------------------------------------------------------------------
function clink._has_coroutines()
    return _coroutines_resumable
end

--------------------------------------------------------------------------------
function clink._wait_duration()
    if _coroutines_resumable then
        local target
        local now = os.clock()
        for _,entry in pairs(_coroutines) do
            local this_target = next_entry_target(entry, now)
            if _coroutine_infinite == entry.coroutine then
                -- Yield until output is ready; don't influence the timeout.
            elseif not target or target > this_target then
                target = this_target
            end
        end
        if target then
            return target - now
        end
    end
end

--------------------------------------------------------------------------------
function clink._resume_coroutines()
    if _coroutines_resumable then
        _coroutines_resumable = false
        local remove = {}
        for _,entry in pairs(_coroutines) do
            if coroutine.status(entry.coroutine) == "dead" then
                table.insert(remove, _)
            else
                _coroutines_resumable = true
                local now = os.clock()
                if next_entry_target(entry, now) < now then
                    entry.firstclock = now
                    if coroutine.resume(entry.coroutine, true--[[async]]) then
                        -- Use live clock so the interval excludes the execution
                        -- time of the coroutine.
                        entry.lastclock = os.clock()
                    else
                        table.insert(remove, _)
                    end
                end
            end
        end
        for _,c in ipairs(remove) do
            clink.removecoroutine(c)
        end
        after_coroutines()
    end
end

--------------------------------------------------------------------------------
function clink.addcoroutine(coroutine, interval)
    if type(coroutine) ~= "thread" then
        error("bad argument #1 (coroutine expected)")
    end
    if interval ~= nil and type(interval) ~= "number" then
        error("bad argument #2 (number or nil expected)")
    end
    _coroutines[coroutine] = { coroutine=coroutine, interval=interval or 0 }
    _coroutines_resumable = true
end

--------------------------------------------------------------------------------
function clink.removecoroutine(coroutine)
    if type(coroutine) == "thread" then
        _coroutines[coroutine] = nil
    elseif coroutine ~= nil then
        error("bad argument #1 (coroutine expected)")
    end
end

--------------------------------------------------------------------------------
--- -name:  io.popenyield
--- -arg:   command:string
--- -arg:   [mode:string]
--- -ret:   file
--- -show:  local file = io.popenyield("git status")
--- -show:
--- -show:  while (true) do
--- -show:  &nbsp; local line = file:read("*line")
--- -show:  &nbsp; if not line then
--- -show:  &nbsp;   break
--- -show:  &nbsp; end
--- -show:  &nbsp; do_things_with(line)
--- -show:  end
--- -show:  file:close()
--- Runs <code>command</code> and returns a read file handle for reading output
--- from the command.  However, it yields until the command has closed the read
--- file handle and the output is ready to be read without blocking.
---
--- It is the same as <code>io.popen</code> except that it only supports read
--- mode, and it yields until the command has finished.
---
--- The <span class="arg">mode</span> cannot contain <code>"w"</code>, but can
--- contain <code>"r"</code> (read mode) and/or either <code>"t"</code> for text
--- mode (the default if omitted) or <code>"b"</code> for binary mode.
---
--- <strong>Note:</strong> if the <code>prompt.async</code> setting is disabled
--- then this turns into a call to `io.popen` instead.
function io.popenyield(command, mode)
    -- This outer wrapper is implemented in Lua so that it can yield.
    if settings.get("prompt.async") then
-- TODO("COROUTINES: ideally avoid having lots of outstanding old commands still running; yield until earlier one(s) complete?")
        local file, yieldguard = io.popenyield_internal(command, mode)
        if file and yieldguard then
            _coroutine_infinite = coroutine.running()
            while not yieldguard:ready() do
                coroutine.yield()
            end
            _coroutine_infinite = nil
        end
        return file
    else
        return io.popen(command, mode)
    end
end