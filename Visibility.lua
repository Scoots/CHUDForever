-- When bars and the power bar show: always, only in combat, or in combat or
-- with a target; when they don't, hidden or faded; optionally hidden while
-- mounted; and their opacity. Done with transparency only, never by hiding
-- frames: a bar can hold the game's aura widgets, which mustn't be hidden or
-- moved in combat.
--
-- Settings (on a bar's config, or the power bar's):
--   show        "always" or "combat" ("combatOrTarget", from older versions,
--               counts as "combat")
--   fadeAlpha   opacity while not shown: 0 hides, e.g. 0.3 fades
--   hideMounted hide while mounted
--   alpha       opacity while shown
local _, ns = ...
local issecret = ns.issecret

local Visibility = {}
ns.Visibility = Visibility

local inCombat = false

local function Readable(value, fallback)
  if issecret(value) or value == nil then return fallback end
  return value
end

local function ReadSetting(config, key, fallback)
  local value = config and config[key]
  if value == nil and ns.profile and ns.profile.visibilityDefaults and config ~= (ns.Power and ns.Power.config) then
    value = ns.profile.visibilityDefaults[key]
  end
  return Readable(value, fallback)
end

-- Opacity for something with these settings, right now.
function Visibility.Alpha(config)
  if ns.editMode then return 1 end
  local alpha = ReadSetting(config, "alpha", 1)
  local shown = true
  local show = ReadSetting(config, "show", "always")
  if show == "combat" or show == "combatOrTarget" then
    shown = inCombat
  end
  if shown and ReadSetting(config, "hideMounted", false) and IsMounted then
    shown = not Readable(IsMounted(), false)
  end
  if not shown then return alpha * ReadSetting(config, "fadeAlpha", 0) end
  return alpha
end

function Visibility.Update()
  for _, frame in ipairs(ns.Bar.Frames()) do
    if frame:IsShown() and frame.config then frame:SetAlpha(Visibility.Alpha(frame.config)) end
  end
  local power = ns.Power.Frame()
  if power and ns.Power.config then power:SetAlpha(Visibility.Alpha(ns.Power.config)) end
  local health = ns.Health and ns.Health.Frame and ns.Health.Frame()
  if health and ns.Health.config then health:SetAlpha(Visibility.Alpha(ns.Health.config)) end
  local cast = ns.Cast and ns.Cast.Frame()
  if cast and ns.Cast.config then cast:SetAlpha(Visibility.Alpha(ns.Cast.config)) end
  local swing = ns.Swing and ns.Swing.Frame and ns.Swing.Frame()
  if swing and ns.Swing.config then swing:SetAlpha(Visibility.Alpha(ns.Swing.config)) end
end

local function Later() ns.Schedule(Visibility.Update) end

ns.On("PLAYER_REGEN_DISABLED", function()
  inCombat = true
  Visibility.Update()
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  inCombat = false
  Visibility.Update()
end)
ns.On("PLAYER_ENTERING_WORLD", function()
  inCombat = Readable(UnitAffectingCombat("player"), false) == true
  Later()
end)
ns.On("PLAYER_MOUNT_DISPLAY_CHANGED", Later)
-- Mounting is an aura on Classic-style clients.
ns.OnUnit("UNIT_AURA", "player", Later)
