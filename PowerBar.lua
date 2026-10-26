-- Power bar for the current power type (mana, rage or energy), with optional
-- text: a meter (Meter.lua) in the power type's color. Mana is secret in
-- combat on this client, so the bar and text are fed the values without the
-- addon reading them.
local _, ns = ...
local issecret = ns.issecret

local Power = {}
ns.Power = Power

local powerType = 0

-- Softer than the game's default power colors.
local COLORS = {
  MANA = { 0.25, 0.52, 1 },
  RAGE = { 0.88, 0.22, 0.22 },
  ENERGY = { 1, 0.8, 0.25 },
  FOCUS = { 1, 0.55, 0.25 },
}

local function Read()
  return UnitPower("player", powerType), UnitPowerMax("player", powerType)
end

-- With secret values, the client's own percent function.
local function SecretPercent()
  if UnitPowerPercent and CurveConstants and CurveConstants.ScaleTo100 then
    return UnitPowerPercent("player", powerType, false, CurveConstants.ScaleTo100), true
  end
  return nil, false
end

local meter = ns.Meter.New("Power", Read, SecretPercent)

-- Keeps the last readable power type if the client hides it.
local function ReadPowerType()
  local current, token = UnitPowerType("player")
  if issecret(current) or issecret(token) or current == nil then return end
  powerType = current
  local r, g, b = 0.25, 0.52, 1
  local color = COLORS[token] or (PowerBarColor and (PowerBarColor[token] or PowerBarColor[current]))
  if color then r, g, b = color[1] or color.r, color[2] or color.g, color[3] or color.b end
  meter.SetColor(r, g, b)
end

Power.Update = meter.Update
Power.SetMoverShown = meter.SetMoverShown
Power.Frame = meter.Frame

function Power.Apply(config)
  Power.config = config
  if not meter.Apply(config) then return end
  ReadPowerType()
  meter.Update()
end

local function PowerTypeChanged()
  ReadPowerType()
  meter.Changed()
end

ns.OnUnit("UNIT_POWER_FREQUENT", "player", meter.Changed)
ns.OnUnit("UNIT_POWER_UPDATE", "player", meter.Changed)
ns.OnUnit("UNIT_MAXPOWER", "player", meter.Changed)
ns.OnUnit("UNIT_DISPLAYPOWER", "player", PowerTypeChanged)
ns.On("UPDATE_SHAPESHIFT_FORM", PowerTypeChanged)

-- For the 5-second rule spark (FiveSecond.lua).
function Power.Bar()
  local frame = meter.Frame()
  if frame and frame:IsShown() then return frame.bar end
end

function Power.IsMana()
  return powerType == 0
end
