-- Ready pulse: when a cooldown on a button with the "Ready pulse" behavior
-- comes back, its icon fades in big and see-through on the screen, then grows
-- as it fades away. Several at once play one after another.
--
-- Its size, opacity and place are the profile's (profile.pulse), shared by
-- every bar. In edit mode a stand-in shows where it goes, with a gear for its
-- size and opacity.
local _, ns = ...

local Pulse = {}
ns.Pulse = Pulse

Pulse.DEFAULTS = { size = 80, alpha = 0.5, x = 0, y = 120 }
local FADE_IN, HOLD, FADE_OUT = 0.15, 0.35, 0.6
local GROW = 0.25 -- how much bigger it gets while fading out
local QUEUE_MAX = 4
local STAND_IN = "Interface\\Icons\\INV_Misc_QuestionMark"

local frame
local playing -- { time, alpha } while a pulse plays
local queue = {} -- { key, texture } waiting their turn

-- A profile's pulse settings (the one in use if left out); missing ones are Pulse.DEFAULTS.
function Pulse.Config(profile)
  profile = profile or ns.profile
  if not profile then return {} end
  profile.pulse = profile.pulse or {}
  return profile.pulse
end

local function Setting(key)
  local value = Pulse.Config()[key]
  if value == nil then return Pulse.DEFAULTS[key] end
  return value
end

-- Between pulses: hidden, or the stand-in in edit mode.
local function Rest()
  playing = nil
  frame.icon:SetSize(frame:GetSize())
  if ns.editMode then
    frame.icon:SetTexture(STAND_IN)
    frame.icon:SetAlpha(Setting("alpha"))
    frame:Show()
  else
    frame:Hide()
  end
end

local function Next()
  local waiting = table.remove(queue, 1)
  if not waiting then
    Rest()
    return
  end
  playing = { time = 0, alpha = Setting("alpha"), key = waiting.key }
  frame.icon:SetTexture(waiting.texture)
  frame.icon:SetAlpha(0)
  frame:Show()
end

local function Animate(_, elapsed)
  if not playing then return end
  playing.time = playing.time + elapsed
  local t, alpha, grow = playing.time, playing.alpha, 0
  if t < FADE_IN then
    alpha = alpha * t / FADE_IN
  elseif t >= FADE_IN + HOLD + FADE_OUT then
    Next()
    return
  elseif t >= FADE_IN + HOLD then
    local out = (t - FADE_IN - HOLD) / FADE_OUT
    alpha, grow = alpha * (1 - out), GROW * out
  end
  frame.icon:SetAlpha(alpha)
  local size = frame:GetWidth() * (1 + grow)
  frame.icon:SetSize(size, size)
end

local function Layout()
  local size = math.floor(Setting("size") * (ns.profile and ns.profile.scale or 1) + 0.5)
  frame:SetSize(size, size)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", Setting("x"), Setting("y"))
  frame.mover:SetShown(ns.editMode)
end

local function Create()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:EnableMouse(false)
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("CENTER")
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame:SetScript("OnUpdate", Animate)
  ns.AttachMover(frame, function() return Pulse.Config() end, function() return "CENTER" end, {
    onGear = function(gear) ns.EditMenu.GearForPulse(gear) end,
  })
  frame.mover.SetLabel("Ready pulse")
  Layout()
  frame:Hide()
end

-- key: what's pulsing (a button), so it isn't queued twice.
local function Enqueue(key, texture)
  if playing and playing.key == key then return end
  for _, waiting in ipairs(queue) do
    if waiting.key == key then return end
  end
  if #queue >= QUEUE_MAX then return end
  if not frame then Create() end
  queue[#queue + 1] = { key = key, texture = texture }
  if not playing then Next() end
end

-- A button's cooldown just came back. The icon is the one it shows now
-- (handed over without being read, like everything on the button).
function Pulse.Play(btn)
  if ns.editMode or ns.Button.Gated(btn.entry) then return end
  Enqueue(btn, btn.icon:GetTexture())
end

-- A sample pulse, to see the size and opacity: the first pulsing button's icon, if any.
function Pulse.Test()
  local texture = STAND_IN
  for _, btn in ipairs(ns.activeButtons) do
    if btn.opts and btn.opts.pulse and btn.texture then
      texture = btn.texture
      break
    end
  end
  Enqueue("test", texture)
end

-- After each build: size and place from the profile, and the stand-in in edit mode.
function Pulse.Apply()
  if not frame then
    if not ns.editMode then return end -- built on the first pulse
    Create()
  end
  Layout()
  if not playing then Rest() end
end
