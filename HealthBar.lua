-- Health bar for the player, with optional text: a green meter (Meter.lua).
local _, ns = ...

local Health = {}
ns.Health = Health

local function Read()
  return UnitHealth("player"), UnitHealthMax("player")
end

local meter = ns.Meter.New("Health", Read)

Health.Update = meter.Update
Health.SetMoverShown = meter.SetMoverShown
Health.Frame = meter.Frame

function Health.Apply(config)
  Health.config = config
  if not meter.Apply(config) then return end
  meter.SetColor(0.2, 0.9, 0.25)
  meter.Update()
end

ns.OnUnit("UNIT_HEALTH", "player", meter.Changed)
ns.OnUnit("UNIT_MAXHEALTH", "player", meter.Changed)
