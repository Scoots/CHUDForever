-- Cast bar: a cast fills it, a channel drains it, with the spell's name on
-- the left and the time left on the right. Interrupted casts flash red for a
-- moment. Built on the meter frame (Meter.lua), so it looks like the power
-- and health bars and has the same size, texture and visibility settings.
--
-- The cast's start and end times are used when they're readable. When the
-- client hides them, the bar is driven by the game's duration object (it
-- fills by itself) and the time text is left out; the name is handed on
-- either way (it may be secret, which the text widget accepts).
--
-- Settings (profile.cast): enabled, width, height, texture, showName,
-- showTime, castColor, channelColor (Glow.COLORS keys), hideGame (hide the
-- game's own cast bar).
local _, ns = ...
local issecret = ns.issecret

local Cast = {}
ns.Cast = Cast

local FLASH_TIME = 0.6 -- seconds an interrupted cast stays up, in red
local FAILED_COLOR = { 0.9, 0.15, 0.15 }

local frame
-- kind ("cast" / "channel"), castID (when readable), from, to (seconds, when
-- readable), flashUntil; stoppedAt and lastCastID, for an interrupt reported
-- just after the stop.
local state = {}

local function Config()
  return Cast.config
end

local function Color(key, fallback)
  local color = ns.Glow.Color(key or fallback)
  return color[3], color[4], color[5]
end

local function SetColor(r, g, b)
  frame.bar:SetStatusBarColor(r, g, b)
  frame.timer:SetStatusBarColor(r, g, b)
  frame.bg:SetVertexColor(r * 0.2, g * 0.2, b * 0.2, 0.9)
end

local function Create()
  frame = ns.Meter.BuildFrame("Cast", Config)
  frame.text:Hide() -- the meter's centered text; the cast bar has name and time instead

  -- Driven by the game when the times are secret.
  frame.timer = CreateFrame("StatusBar", nil, frame)
  frame.timer:SetAllPoints(frame.bar)
  frame.timer:SetFrameLevel(frame.bar:GetFrameLevel())
  frame.timer:Hide()

  local texts = CreateFrame("Frame", nil, frame)
  texts:SetAllPoints()
  texts:SetFrameLevel(frame.bar:GetFrameLevel() + 2)
  frame.name = texts:CreateFontString(nil, "OVERLAY")
  frame.name:SetPoint("LEFT", 4, 0)
  frame.name:SetPoint("RIGHT", -40, 0)
  frame.name:SetJustifyH("LEFT")
  frame.name:SetWordWrap(false)
  frame.time = texts:CreateFontString(nil, "OVERLAY")
  frame.time:SetPoint("RIGHT", -4, 0)
  for _, text in ipairs({ frame.name, frame.time }) do
    text:SetShadowColor(0, 0, 0, 1)
    text:SetShadowOffset(1, -1)
  end
end

-- The game's cast bar ---------------------------------------------------------------

local hooked = {}

local function HideGame(bar)
  if not (Cast.config and Cast.config.enabled and Cast.config.hideGame ~= false) then return end
  -- Only hidden, never moved; a protected one is only made see-through.
  if bar:IsProtected() then bar:SetAlpha(0) else bar:Hide() end
end

local function GameBars()
  local list = {}
  for _, name in ipairs({ "PlayerCastingBarFrame", "CastingBarFrame" }) do
    if _G[name] then list[#list + 1] = _G[name] end
  end
  return list
end

local function ApplyGameBar()
  local hide = Cast.config and Cast.config.enabled and Cast.config.hideGame ~= false
  for _, bar in ipairs(GameBars()) do
    if not hooked[bar] then
      hooked[bar] = true
      bar:HookScript("OnShow", HideGame)
    end
    if hide then
      if bar:IsShown() then HideGame(bar) end
    elseif bar:IsProtected() then
      bar:SetAlpha(1)
    end
  end
end

-- Casting ------------------------------------------------------------------------------

local function Stop()
  if state.kind then state.stoppedAt, state.lastCastID = GetTime(), state.castID end
  state.kind, state.castID, state.from, state.to = nil, nil, nil, nil
  frame.timer:Hide()
  if not ns.editMode and not (state.flashUntil and GetTime() < state.flashUntil) then frame:Hide() end
end

-- What you're casting or channeling now, from the client.
local function Read(kind)
  if kind == "channel" then
    local name, _, _, startMS, endMS = UnitChannelInfo("player")
    return name, startMS, endMS, nil
  end
  local name, _, _, startMS, endMS, _, castID = UnitCastingInfo("player")
  return name, startMS, endMS, castID
end

local function Start(kind)
  if not frame or not Cast.config or not Cast.config.enabled then return end
  local name, startMS, endMS, castID = Read(kind)
  if not issecret(name) and name == nil then return Stop() end
  local config = Cast.config
  if issecret(castID) then castID = nil end
  state.kind, state.castID, state.flashUntil = kind, castID, nil
  SetColor(Color(kind == "channel" and config.channelColor or config.castColor, kind == "channel" and "green" or "gold"))
  frame.name:SetText(config.showName ~= false and name or "")
  frame.time:SetText("")

  if ns.AllReadable(startMS, endMS) and startMS and endMS and endMS > startMS then
    state.from, state.to = startMS / 1000, endMS / 1000
    frame.timer:Hide()
    frame.bar:SetMinMaxValues(0, state.to - state.from)
    frame.bar:Show()
  else
    -- Secret: the game fills the timer bar from its own duration.
    state.from, state.to = nil, nil
    local get = kind == "channel" and UnitChannelDuration or UnitCastingDuration
    local duration = get and get("player")
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0)
    if duration then
      frame.timer:Show()
      local direction = kind == "channel" and Enum.StatusBarTimerDirection.RemainingTime
        or Enum.StatusBarTimerDirection.ElapsedTime
      ns.Try("cast bar timer", frame.timer.SetTimerDuration, frame.timer, duration,
        Enum.StatusBarInterpolation.Immediate, direction)
    end
  end
  frame:Show()
  Cast.Update()
end

-- Each frame while casting (readable times only): the fill and the time left.
function Cast.Update()
  if not frame or not state.from then return end
  local now = GetTime()
  local length = state.to - state.from
  local elapsed = math.max(0, math.min(length, now - state.from))
  frame.bar:SetValue(state.kind == "channel" and (length - elapsed) or elapsed)
  if Cast.config.showTime ~= false then
    ns.SetNumberText(frame.time, "%.1f", length - elapsed)
  else
    frame.time:SetText("")
  end
end

-- Interrupted: a moment in red, full, then gone.
local function Flash(text)
  if not frame then return end
  state.kind, state.castID, state.from, state.to = nil, nil, nil, nil
  state.flashUntil = GetTime() + FLASH_TIME
  frame.timer:Hide()
  frame.bar:SetMinMaxValues(0, 1)
  frame.bar:SetValue(1)
  SetColor(FAILED_COLOR[1], FAILED_COLOR[2], FAILED_COLOR[3])
  frame.time:SetText(text)
  frame:Show()
  local token = state.flashUntil
  C_Timer.After(FLASH_TIME, function()
    if state.flashUntil == token then
      state.flashUntil = nil
      if not state.kind then Stop() end
    end
  end)
end

-- Settings ------------------------------------------------------------------------------

function Cast.Apply(config)
  Cast.config = config
  ApplyGameBar()
  if not config or not config.enabled then
    if frame then frame:Hide() end
    return
  end
  if not frame then
    Create()
    frame:SetScript("OnUpdate", Cast.Update)
  end
  local height = ns.Meter.Layout(frame, config, 16)
  frame.timer:SetStatusBarTexture(ns.BarTexture(config.texture))
  local size = math.max(8, math.min(height - 3, 16))
  frame.name:SetFont(ns.Font(), size, "")
  frame.time:SetFont(ns.Font(), size, "")
  frame.time:SetShown(config.showTime ~= false)

  -- Casting now? Pick it up; else, in edit mode, a stand-in to place it by.
  local channel, cast = UnitChannelInfo("player"), UnitCastingInfo("player")
  if issecret(channel) or channel ~= nil then
    Start("channel")
  elseif issecret(cast) or cast ~= nil then
    Start("cast")
  elseif ns.editMode then
    SetColor(Color(config.castColor, "gold"))
    frame.timer:Hide()
    frame.bar:SetMinMaxValues(0, 1)
    frame.bar:SetValue(0.6)
    frame.name:SetText(config.showName ~= false and "Cast bar" or "")
    frame.time:SetText("1.2")
    frame:Show()
  else
    Stop()
  end
end

function Cast.SetMoverShown(shown)
  if frame and frame:IsShown() then frame.mover:SetShown(shown) end
end

function Cast.Frame()
  return frame
end

-- Events --------------------------------------------------------------------------------

local function On(event, fn) ns.OnUnit(event, "player", fn) end

On("UNIT_SPELLCAST_START", function() Start("cast") end)
On("UNIT_SPELLCAST_DELAYED", function() if state.kind == "cast" then Start("cast") end end)
On("UNIT_SPELLCAST_CHANNEL_START", function() Start("channel") end)
On("UNIT_SPELLCAST_CHANNEL_UPDATE", function() if state.kind == "channel" then Start("channel") end end)
On("UNIT_SPELLCAST_STOP", function() if frame and state.kind == "cast" then Stop() end end)
On("UNIT_SPELLCAST_CHANNEL_STOP", function() if frame and state.kind == "channel" then Stop() end end)
On("UNIT_SPELLCAST_INTERRUPTED", function(_, _, castID)
  -- Only the cast on the bar, or one that stopped a moment ago (the game may
  -- report the stop first). Its ID, when both are readable, must match.
  local current = state.kind == "cast"
  local justStopped = state.stoppedAt and GetTime() - state.stoppedAt < 0.3
  if not (current or justStopped) then return end
  local mine = current and state.castID or state.lastCastID
  if mine and not issecret(castID) and castID ~= mine then return end
  Flash("Interrupted")
end)
