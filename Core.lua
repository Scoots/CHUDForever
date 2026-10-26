-- Namespace, event dispatch and per-frame update batching.
local ADDON, ns = ...

ns.name = ADDON

function ns.Print(...)
  print("|cff33ccffCombatHUD|r:", ...)
end

-- Runs fn, reporting an error the usual way without stopping the caller: one
-- failing handler mustn't keep the others for the same event from running.
local Call = securecallfunction or function(fn, ...) return xpcall(fn, geterrorhandler(), ...) end

-- Events ------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

local function IsValidEvent(event)
  if C_EventUtils and C_EventUtils.IsEventValid then
    return C_EventUtils.IsEventValid(event)
  end
  return true
end

-- Registers fn for event. Events this client doesn't have are skipped
-- instead of raising an error.
function ns.On(event, fn)
  if not handlers[event] then
    if not IsValidEvent(event) or not pcall(eventFrame.RegisterEvent, eventFrame, event) then return end
    handlers[event] = {}
  end
  table.insert(handlers[event], fn)
end

-- Same as ns.On, but only for one unit (e.g. "player"). Each unit has its
-- own frame, so the same event can be watched on several units.
local unitFrames = {} -- unit -> { frame, handlers = event -> list }

function ns.OnUnit(event, unit, fn)
  local watch = unitFrames[unit]
  if not watch then
    watch = { frame = CreateFrame("Frame"), handlers = {} }
    watch.frame:SetScript("OnEvent", function(_, firedEvent, ...)
      local list = watch.handlers[firedEvent]
      if not list then return end
      for i = 1, #list do Call(list[i], firedEvent, ...) end
    end)
    unitFrames[unit] = watch
  end
  if not watch.handlers[event] then
    if not IsValidEvent(event) or not pcall(watch.frame.RegisterUnitEvent, watch.frame, event, unit) then return end
    watch.handlers[event] = {}
  end
  table.insert(watch.handlers[event], fn)
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do Call(list[i], event, ...) end
end)

-- Batching ----------------------------------------------------------------
-- Several events often arrive in the same frame (a cast fires cooldown,
-- usable and power events together). Scheduled jobs run once, on the next
-- frame, however many times they were requested.

local queued, running = {}, {}
local runner = CreateFrame("Frame")
runner:Hide()
runner:SetScript("OnUpdate", function(self)
  self:Hide()
  queued, running = running, queued
  for fn in pairs(running) do
    running[fn] = nil
    Call(fn)
  end
end)

function ns.Schedule(fn)
  queued[fn] = true
  runner:Show()
end

-- Lightweight object pools for frames and other reusable tables.
-- create: function() -> object
-- reset: function(object) to clear state before pooling
-- retired: optional hidden parent frame; auto-created when omitted
function ns.CreatePool(create, reset, retired)
  local pool = {}
  if retired == nil then
    retired = CreateFrame("Frame")
    retired:Hide()
  end
  return {
    Acquire = function(parent, ...)
      local object = table.remove(pool)
      if not object then object = create(...) end
      if parent and object and object.SetParent then object:SetParent(parent) end
      return object
    end,
    Release = function(object)
      if not object then return end
      if reset then reset(object) end
      if retired and object.SetParent then object:SetParent(retired) end
      table.insert(pool, object)
    end,
    Size = function()
      return #pool
    end,
  }
end
