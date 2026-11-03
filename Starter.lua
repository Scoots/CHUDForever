-- Starting layouts built from your action bars, for specs without a built-in
-- layout (and on request, from the Profiles page). The spells on your bars,
-- hidden ones included, are the ones you use. The bars are the same as a
-- default profile's (Defaults.lua), but Rotation and Cooldowns hold everything
-- from your action bars, so there's no Utility, Traps or Taunts bar:
--   My Active Buffs: every buff you cast on yourself, while up
--   Rotation:     spells with a cooldown of 12 seconds or less, and damage fillers
--   Cooldowns:    spells with a longer one
--   Items:        trinkets and consumables, while on cooldown
--   The class's own: shields, totems, a charge bar, weapon enchants, missing buffs
-- Other spells without a cooldown (buffs, heals) are left out; drop them on a
-- bar if you want them.
local _, ns = ...
local issecret = ns.issecret

local Starter = {}
ns.Starter = Starter

local NUM_SLOTS = 180

-- Auto-attacks: harmful, no cooldown, but not a filler.
local AUTO = { 6603, 75, 5019, 2764, 3018 } -- Attack, Auto Shot, Shoot (wand), Throw, Shoot (bow)

local function IsAuto(spellID)
  local name = ns.SpellName(spellID)
  return name ~= nil and ns.NameSet(AUTO)[name] == true
end

local BaseCooldown, Harmful = ns.BaseCooldown, ns.IsHarmful

-- The spells on your action bars, in bar order, once each (by name).
local function ActionBarSpells()
  local spells, seen = {}, {}
  for slot = 1, NUM_SLOTS do
    local ok, actionType, id = pcall(GetActionInfo, slot)
    if ok and not issecret(actionType) and actionType == "spell" and not issecret(id) and type(id) == "number" then
      local name = C_Spell.GetSpellName(id)
      if name and not issecret(name) and not seen[name] then
        seen[name] = true
        spells[#spells + 1] = id
      end
    end
  end
  return spells
end

function Starter.Build()
  local _, class = UnitClass("player")
  local rotation, long = {}, {}
  local candidates = {}
  for _, spellID in ipairs(ActionBarSpells()) do
    local cooldown = BaseCooldown(spellID)
    if cooldown and cooldown > 1.5 then
      candidates[#candidates + 1] = { spell = spellID }
    elseif Harmful(spellID) and not IsAuto(spellID) then
      rotation[#rotation + 1] = { spell = spellID } -- a filler
    end
  end
  ns.SortByCooldown(candidates, rotation, long, long)

  local bars = ns.StandardBars(rotation, long)
  ns.AddClassBars(bars, class, -219) -- no Utility bar here: the totems go right under Cooldowns
  local profile = ns.DefaultMeters()
  profile.bars = bars
  return profile
end

-- How many spells it found, for a chat message.
function Starter.Describe(profile)
  local counts = {}
  for _, bar in ipairs(profile.bars) do
    if #bar.buttons > 0 then counts[#counts + 1] = ("%s %d"):format(bar.name, #bar.buttons) end
  end
  return table.concat(counts, ", ")
end
