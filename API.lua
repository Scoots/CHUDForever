-- Wrappers around the client's combat APIs.
--
-- WoW Forever runs on the Midnight engine: in combat many values are
-- "secret". They can be handed to widgets (SetValue, SetAlpha, SetCooldown...)
-- but never compared, tested or calculated with. Everything here checks
-- issecretvalue before looking at a value, and anything that decides how a
-- button looks in combat goes through duration objects and curves, which the
-- game evaluates for us.
local _, ns = ...

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

-- Runs fn in protected mode. The first failure for each label is printed,
-- so gaps in the beta client's API show up in chat instead of breaking the
-- addon.
local reported = {}
ns.problems = {} -- the first failure of each label, for /chud report
function ns.Try(label, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok and not reported[label] then
    reported[label] = true
    ns.problems[#ns.problems + 1] = label .. ": " .. tostring(err)
    ns.Print(label .. " failed: " .. tostring(err))
  end
  return ok
end

-- The addon's version, from its .toc.
function ns.Version()
  local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
  local ok, version = pcall(get, ns.name, "Version")
  if ok and version and not issecret(version) then return version end
  return "?"
end

-- Shared helpers --------------------------------------------------------------

ns.WHITE = "Interface\\Buttons\\WHITE8x8"
ns.GEAR = "Interface\\Buttons\\UI-OptionsButton"

-- True when none of the values are secret.
function ns.AllReadable(...)
  for i = 1, select("#", ...) do
    if issecret((select(i, ...))) then return false end
  end
  return true
end

-- A spell's name, or nil when it's unknown or secret.
function ns.SpellName(spellID)
  if issecret(spellID) or type(spellID) ~= "number" then return end
  local name = C_Spell.GetSpellName(spellID)
  if name and not issecret(name) then return name end
end

-- The names of a list of spell IDs (any rank matches by name), as a set.
-- Built once per list.
local nameSets = {}
function ns.NameSet(ids)
  local set = nameSets[ids]
  if not set then
    set = {}
    for _, id in ipairs(ids) do
      local name = ns.SpellName(id)
      if name then set[name] = true end
    end
    nameSets[ids] = set
  end
  return set
end

-- A spell's base cooldown in seconds, or nil when it can't be read.
function ns.BaseCooldown(spellID)
  if not GetSpellBaseCooldown or type(spellID) ~= "number" then return end
  local ok, ms = pcall(GetSpellBaseCooldown, spellID)
  if ok and not issecret(ms) and type(ms) == "number" then return ms / 1000 end
end

-- Whether a spell is cast on enemies.
function ns.IsHarmful(spellID)
  local ok, harmful
  if C_Spell.IsSpellHarmful then
    ok, harmful = pcall(C_Spell.IsSpellHarmful, spellID)
  elseif IsHarmfulSpell then
    ok, harmful = pcall(IsHarmfulSpell, ns.SpellName(spellID) or "")
  end
  return ok == true and not issecret(harmful) and (harmful == true or harmful == 1)
end

-- Curves --------------------------------------------------------------------
-- Evaluated by the game against a duration object's remaining time, so they
-- work while the remaining time itself is secret.

local function StepCurve(atZero, afterZero)
  if not (C_CurveUtil and C_CurveUtil.CreateCurve) then return end
  local curve = C_CurveUtil.CreateCurve()
  curve:AddPoint(0, atZero)
  curve:AddPoint(0.001, afterZero)
  return curve
end

ns.curveRunning = StepCurve(0, 1) -- 1 while time remains, 0 once it has run out
ns.curveDone = StepCurve(1, 0)    -- the reverse

-- Returns the curve's value for the duration's remaining time (possibly a
-- secret number), or fallback when there is no duration or curve support.
function ns.Evaluate(duration, curve, fallback)
  if duration == nil or curve == nil then return fallback end
  return duration:EvaluateRemainingDuration(curve)
end

-- Cooldowns -----------------------------------------------------------------

-- Forever reports the global cooldown on this Classic reference spell (the
-- retail one, 61304, never starts).
ns.GCD_SPELL = 29515

-- The spell's own cooldown, without the GCD.
function ns.SpellCooldown(spellID)
  return C_Spell.GetSpellCooldownDuration(spellID, true)
end

function ns.GCDCooldown()
  local ok, duration = pcall(C_Spell.GetSpellCooldownDuration, ns.GCD_SPELL)
  if ok then return duration end
end

-- Spells --------------------------------------------------------------------

-- The client has several "do you know this spell" functions that disagree
-- about talents, passives and lower ranks. A yes from any of them counts.
local knownChecks = {
  { name = "C_SpellBook.IsSpellKnown", func = C_SpellBook and C_SpellBook.IsSpellKnown },
  { name = "C_SpellBook.IsSpellInSpellBook", func = C_SpellBook and C_SpellBook.IsSpellInSpellBook },
  { name = "IsPlayerSpell", func = IsPlayerSpell },
  { name = "IsSpellKnownOrOverridesKnown", func = IsSpellKnownOrOverridesKnown },
  { name = "IsSpellKnown", func = IsSpellKnown },
}

-- Your pet's spells: the modern spellbook's pet bank, or the older isPet flag.
local function PetKnows(spellID)
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet
  if bank and C_SpellBook and C_SpellBook.IsSpellKnown then
    local ok, known = pcall(C_SpellBook.IsSpellKnown, spellID, bank)
    if ok and not issecret(known) and known then return true end
  end
  if IsSpellKnown then
    local ok, known = pcall(IsSpellKnown, spellID, true)
    if ok and not issecret(known) and (known == true or known == 1) then return true end
  end
  return false
end

function ns.IsSpellKnown(spellID)
  for _, check in ipairs(knownChecks) do
    if check.func then
      local ok, known = pcall(check.func, spellID)
      if ok and not issecret(known) and (known == true or known == 1) then return true end
    end
  end
  return PetKnows(spellID)
end

-- What each check says about a spell, for /chud debug spec.
function ns.DescribeSpellKnown(spellID)
  local parts = {}
  for _, check in ipairs(knownChecks) do
    local name, func = check.name, check.func
    if not func then
      parts[#parts + 1] = name .. "=missing"
    else
      local ok, known = pcall(func, spellID)
      if not ok then
        parts[#parts + 1] = name .. "=error"
      elseif issecret(known) then
        parts[#parts + 1] = name .. "=secret"
      else
        parts[#parts + 1] = name .. "=" .. tostring(known)
      end
    end
  end
  return table.concat(parts, ", ")
end

-- Classic spells have one ID per rank. Looking the spell up by name gives the
-- rank the player actually has.
local function HighestRank(spellID)
  local name = C_Spell.GetSpellName(spellID)
  if not name or issecret(name) then return spellID, nil end
  local info = C_Spell.GetSpellInfo(name)
  if info and not issecret(info.spellID) and info.spellID and ns.IsSpellKnown(info.spellID) then
    return info.spellID, name
  end
  return spellID, name
end

-- spell is an ID or a list of alternative IDs; the first one the player
-- knows wins. Returns the spell ID to track and its name, or nil.
function ns.ResolveSpell(spell)
  local list = type(spell) == "table" and spell or { spell }
  for _, id in ipairs(list) do
    local resolved, name = HighestRank(id)
    if ns.IsSpellKnown(resolved) then return resolved, name end
    if resolved ~= id and ns.IsSpellKnown(id) then return id, name end
  end
end

local function ReadManaCost(spellID)
  local costs = C_Spell.GetSpellPowerCost(spellID)
  if issecret(costs) or not costs then return end
  for _, cost in ipairs(costs) do
    if not issecret(cost.type) and cost.type == Enum.PowerType.Mana then
      if issecret(cost.cost) then return end
      return cost.cost
    end
  end
end

-- Mana cost, when the client lets us read it. Returns nil otherwise.
function ns.ManaCost(spellID)
  if not C_Spell.GetSpellPowerCost then return end
  local ok, cost = pcall(ReadManaCost, spellID)
  if ok then return cost end
end

-- Text -------------------------------------------------------------------------

-- Sets formatted text from values that may be secret. Readable values are
-- formatted normally; secret ones are handed to the widget, and if this
-- client won't format them, the raw value is shown instead.
function ns.SetNumberText(fontString, format, ...)
  local anySecret = false
  for i = 1, select("#", ...) do
    if issecret((select(i, ...))) then anySecret = true end
  end
  if not anySecret then
    fontString:SetFormattedText(format, ...)
  elseif not ns.Try("formatted secret text", fontString.SetFormattedText, fontString, format, ...) then
    ns.Try("secret text", fontString.SetText, fontString, (...))
  end
end

-- Fonts and bar textures (the profile's choice) -------------------------------------

ns.FONTS = {
  { "default", "Game default", STANDARD_TEXT_FONT },
  { "friz", "Friz Quadrata", "Fonts\\FRIZQT__.TTF" },
  { "arial", "Arial Narrow", "Fonts\\ARIALN.TTF" },
  { "morpheus", "Morpheus", "Fonts\\MORPHEUS.TTF" },
  { "skurri", "Skurri", "Fonts\\SKURRI.TTF" },
}

ns.TEXTURES = {
  { "flat", "Flat", "Interface\\Buttons\\WHITE8x8" },
  { "blizzard", "Blizzard", "Interface\\TargetingFrame\\UI-StatusBar" },
  { "raid", "Raid frames", "Interface\\RaidFrame\\Raid-Bar-Hp-Fill" },
  { "skills", "Skill bar", "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar" },
}

local function Find(list, key)
  for _, item in ipairs(list) do
    if item[1] == key then return item end
  end
  return list[1]
end

function ns.Font()
  return Find(ns.FONTS, ns.profile and ns.profile.font)[3]
end

-- key: a bar's own texture; left out (or nil), the HUD's.
function ns.BarTexture(key)
  return Find(ns.TEXTURES, key or (ns.profile and ns.profile.barTexture))[3]
end

function ns.ListLabel(list, key)
  return Find(list, key)[2]
end

-- The item of a { key, label, ... } list with this key, else its first item.
ns.Find = Find

-- "Name-Realm" for this character (where its saved settings go), or nil if
-- it can't be read yet.
function ns.CharacterKey()
  local name, realm = UnitName("player"), GetRealmName()
  if issecret(name) or issecret(realm) or not name then return end
  return name .. "-" .. (realm or "")
end

-- Timer text (aura and debuff time left) -----------------------------------------
-- How the game writes it: whole seconds rounded up (tenths under 3 seconds,
-- minutes past one), white, and red under `red` seconds (0: never red).
-- Whatever this client doesn't support is left out.

local timerOptions = {}

function ns.TimerOptions(red)
  red = red or 0
  if timerOptions[red] then return timerOptions[red] end
  local options = {}
  if C_StringUtil and C_StringUtil.CreateNumericRuleFormatter and Enum.NumericRuleFormatRounding then
    local ok, formatter = pcall(function()
      local up = Enum.NumericRuleFormatRounding.Up
      local rules = C_StringUtil.CreateNumericRuleFormatter()
      rules:SetBreakpoints({
        { threshold = 0, format = "" },
        { threshold = 0.000001, format = "%.1f" },
        { threshold = 3, format = "%d", step = 1, rounding = up },
        { threshold = 60, format = "%d:%02d", step = 1, rounding = up, components = { { div = 60 }, { mod = 60 } } },
      })
      return rules
    end)
    if ok then options.textFormatter = formatter end
  end
  if red > 0 and C_CurveUtil and C_CurveUtil.CreateColorCurve and CreateColor and Enum.LuaCurveType
      and Enum.DurationTextBindingProperty then
    local ok, curve = pcall(function()
      local colors = C_CurveUtil.CreateColorCurve()
      colors:SetType(Enum.LuaCurveType.Step)
      colors:AddPoint(0, CreateColor(1, 0.25, 0.25, 1))
      colors:AddPoint(red, CreateColor(1, 1, 1, 1))
      return colors
    end)
    if ok then
      options.textColor = { curve = curve, property = Enum.DurationTextBindingProperty.RemainingDuration }
    end
  end
  timerOptions[red] = options
  return options
end

-- Binds an aura button's time text with as many of the options as the client accepts.
function ns.BindTimer(button, text, red)
  local options = ns.TimerOptions(red)
  if pcall(button.SetDurationText, button, text, options) then return end
  if pcall(button.SetDurationText, button, text, { textFormatter = options.textFormatter }) then return end
  ns.Try("aura timer text", button.SetDurationText, button, text)
end
