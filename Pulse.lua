-- Ready pulse: when a cooldown on a button with the "Ready pulse" behavior
-- comes back, its icon fades in see-through above the HUD, then swells as it
-- fades away completely, like a pulse. Several at once play one after another.
--
-- Its size and opacity are the profile's (profile.pulse), shared by every bar.
-- It always shows in the same spot, so it isn't moved in edit mode.
local _, ns = ...

local Pulse = {}
ns.Pulse = Pulse

Pulse.DEFAULTS = { size = 240, alpha = 0.3 }
local X, Y = 0, 80 -- above the HUD, over the character
local FADE_IN, DURATION = 0.15, 0.8 -- seconds to reach its opacity, and in all
local START, GROW = 0.75, 0.5        -- size at the start (of the setting), and how much it swells
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

local function Next()
  local waiting = table.remove(queue, 1)
  if not waiting then
    playing = nil
    frame:Hide()
    return
  end
  playing = { time = 0, alpha = Setting("alpha"), key = waiting.key }
  frame.icon:SetTexture(waiting.texture)
  frame.icon:SetAlpha(0)
  frame.icon:SetSize(frame:GetWidth() * START, frame:GetWidth() * START)
  frame:Show()
end

local function Animate(_, elapsed)
  if not playing then return end
  playing.time = playing.time + elapsed
  local t = playing.time
  if t >= DURATION then
    Next()
    return
  end
  -- Swells quickly at first, then slows; fades in, then all the way out.
  local done = t / DURATION
  local swell = 1 - (1 - done) * (1 - done)
  local alpha
  if t < FADE_IN then
    alpha = playing.alpha * t / FADE_IN
  else
    alpha = playing.alpha * (1 - (t - FADE_IN) / (DURATION - FADE_IN))
  end
  frame.icon:SetAlpha(alpha)
  local size = frame:GetWidth() * (START + GROW * swell)
  frame.icon:SetSize(size, size)
end

local function Layout()
  local size = math.floor(Setting("size") * (ns.profile and ns.profile.scale or 1) + 0.5)
  frame:SetSize(size, size)
  frame:ClearAllPoints()
  frame:SetPoint("CENTER", UIParent, "CENTER", X, Y)
end

local function Create()
  frame = CreateFrame("Frame", nil, UIParent)
  frame:EnableMouse(false)
  frame:SetFrameStrata("HIGH")
  frame.icon = frame:CreateTexture(nil, "ARTWORK")
  frame.icon:SetPoint("CENTER")
  frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  frame:SetScript("OnUpdate", Animate)
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

-- After each build: the size from the profile.
function Pulse.Apply()
  if frame then Layout() end
end
