-- Tests for Modules.lua, Alerts.lua and Groups.lua's pure parts, in plain Lua 5.1.
-- Run from the addon folder:  lua tools/test_modules.lua
-- The game isn't needed: its few functions used here are stubbed.

local failures, passed = 0, 0

local function check(condition, message)
  if condition then
    passed = passed + 1
  else
    failures = failures + 1
    print("FAIL: " .. message)
  end
end

local function equal(actual, expected, message)
  check(actual == expected, ("%s (expected %s, got %s)"):format(message, tostring(expected), tostring(actual)))
end

-- Stubs ------------------------------------------------------------------------------------------

local SPELLS = {
  [17364] = "Stormstrike", [8042] = "Earth Shock", [8050] = "Flame Shock", [8056] = "Frost Shock",
  [10412] = "Earth Shock", [7384] = "Overpower", [13795] = "Immolation Trap", [13813] = "Explosive Trap",
}
C_Spell = {
  GetSpellName = function(id) return SPELLS[id] end,
  GetSpellTexture = function(id) return "icon" .. tostring(id) end,
}
C_Item = { GetItemCount = function(id) return id == 2 and 5 or 0 end, GetItemSpell = function() return nil end }

local ns = {}
ns.issecret = function() return false end
ns.Bar = { Type = function(config) return config.type or "cooldowns" end }
ns.Button = { REACTIVE = { Overpower = true }, ItemIcon = function(id) return "item" .. id end }
local known = { [17364] = true, [8042] = true, [8050] = true, [7384] = true }
ns.ResolveSpell = function(spell)
  local list = type(spell) == "table" and spell or { spell }
  for _, id in ipairs(list) do
    if known[id] then return id, SPELLS[id] end
  end
end
ns.Sounds = {
  Fallback = function(event) return event == "Added" and "Buff up" or "Buff gone" end,
  Label = function(key) return tostring(key) end,
}
ns.Aura = {
  SpellIDs = function(entry)
    local ids = {}
    for _, field in ipairs({ "spell", "aura" }) do
      local value = entry[field]
      if type(value) == "table" then
        for _, id in ipairs(value) do ids[id] = true end
      elseif value then
        ids[value] = true
      end
    end
    return ids
  end,
}

assert(loadfile("Defaults.lua"))("CHUDForever", ns)
assert(loadfile("Groups.lua"))("CHUDForever", ns)
assert(loadfile("Alerts.lua"))("CHUDForever", ns)
assert(loadfile("Modules.lua"))("CHUDForever", ns)
local Modules, Groups, Alerts = ns.Modules, ns.Groups, ns.Alerts

local function Module(id) return Modules.Get(id) end

local function Fixture()
  local profile = { buttonDefaults = {} }
  local bar = { type = "cooldowns", buttonDefaults = { gcd = true }, buttons = {
    { spell = 17364 }, { spell = 7384 }, { item = 1 }, { slot = 13 }, { aura = { 324 } },
  } }
  profile.bars = { bar }
  return profile, bar
end

-- Layer merge ---------------------------------------------------------------------------------------
do
  local profile, bar = Fixture()
  profile.buttonDefaults.numbers = false
  bar.buttonDefaults.numbers = true
  local entry = bar.buttons[1]
  entry.desaturate = false
  local opts = Modules.Merge(profile, bar, entry)
  equal(opts.numbers, true, "bar overrides profile")
  equal(opts.desaturate, false, "button overrides bar")
  equal(opts.gcd, true, "bar default applies")
  equal(opts.cooldown, "swipe", "built-in default applies")
  equal(Modules.Merge(profile, nil, nil).numbers, false, "profile layer alone")
end

-- Contexts ------------------------------------------------------------------------------------------
do
  local profile, bar = Fixture()
  equal(Modules.Context(profile, bar, bar.buttons[1]).entryKind, "spell", "spell entry")
  equal(Modules.Context(profile, bar, bar.buttons[3]).entryKind, "item", "item entry")
  equal(Modules.Context(profile, bar, bar.buttons[4]).entryKind, "slot", "slot entry")
  equal(Modules.Context(profile, bar, bar.buttons[5]).entryKind, "aura", "aura entry")
  equal(Modules.Context(profile, bar, nil).layer, "bar", "bar layer")
  equal(Modules.Context(profile, bar, bar.buttons[1]).name, "Stormstrike", "spell name")
  local charges = { type = "charges", buttons = { { spell = 324 } } }
  equal(Modules.Context(profile, charges, charges.buttons[1]).entryKind, "aura", "charge bar entry counts as an aura")
end

-- Applicability ---------------------------------------------------------------------------------------
local function ids(list)
  local set = {}
  for _, module in ipairs(list) do set[module.id] = true end
  return set
end

do
  local profile, bar = Fixture()
  local spell = ids(Modules.ForContext(Modules.Context(profile, bar, bar.buttons[1])))
  for _, id in ipairs({ "cooldown", "manaCost", "group", "swap", "procGlow", "usableGlow", "rangeTint", "manaTint",
    "earlyReady", "alerts", "targetDebuff" }) do
    check(spell[id], "spell button offers " .. id)
  end
  check(not spell.aura and not spell.charges, "spell button: no aura or charges module")

  local item = ids(Modules.ForContext(Modules.Context(profile, bar, bar.buttons[3])))
  check(item.cooldown and item.rangeTint and item.group and item.alerts, "item button: cooldown, range tint, shared cooldown, alerts")
  for _, id in ipairs({ "manaCost", "procGlow", "usableGlow", "manaTint", "earlyReady", "targetDebuff", "swap" }) do
    check(not item[id], "item button doesn't offer " .. id)
  end

  local slot = ids(Modules.ForContext(Modules.Context(profile, bar, bar.buttons[4])))
  check(slot.cooldown and slot.rangeTint and not slot.group, "trinket slot: cooldown and range tint, no group")

  local aura = ids(Modules.ForContext(Modules.Context(profile, bar, bar.buttons[5])))
  check(aura.aura and aura.alerts and not aura.cooldown, "aura on a cooldown bar: aura and alerts only")

  local buffs = { type = "buffs", buttons = { { aura = { 1 } } } }
  local buff = ids(Modules.ForContext(Modules.Context(profile, buffs, buffs.buttons[1])))
  check(buff.alerts and not buff.aura and not buff.cooldown, "buffs bar button: alerts only")
  local buffsBar = ids(Modules.ForContext(Modules.Context(profile, buffs, nil)))
  check(buffsBar.aura and buffsBar.alerts, "buffs bar page: aura look and alerts")

  local charges = { type = "charges", buttons = { { spell = 324 } } }
  local charge = ids(Modules.ForContext(Modules.Context(profile, charges, charges.buttons[1])))
  check(charge.charges and charge.alerts and not charge.cooldown, "charges button: charges and alerts")

  local barPage = ids(Modules.ForContext(Modules.Context(profile, bar, nil)))
  check(barPage.cooldown and barPage.procGlow and not barPage.group, "cooldown bar page: no shared cooldown")
end

-- On/off and round trips ----------------------------------------------------------------------------------
do
  local profile, bar = Fixture()
  local entry = bar.buttons[1]
  local ctx = Modules.Context(profile, bar, entry)
  for _, module in ipairs(Modules.ForContext(ctx)) do
    if not module.fixed and not module.own and module.id ~= "alerts" then
      local set = Modules.Setter(ctx)
      module.disable(set, ctx)
      check(not Modules.IsOn(module, Modules.Opts(ctx), ctx), module.id .. " is off after disable")
      module.enable(Modules.Setter(ctx), ctx)
      check(Modules.IsOn(module, Modules.Opts(ctx), ctx), module.id .. " is on after enable")
    end
  end
  -- Defaults put back by enable aren't kept on the button.
  local fresh = { spell = 17364 }
  bar.buttons[#bar.buttons + 1] = fresh
  local freshCtx = Modules.Context(profile, bar, fresh)
  Module("procGlow").enable(Modules.Setter(freshCtx), freshCtx)
  equal(fresh.procGlow, nil, "enabling what the bar already has keeps nothing")
  Module("procGlow").disable(Modules.Setter(freshCtx), freshCtx)
  equal(fresh.procGlow, false, "switching off one button keeps it on that button")
  Module("procGlow").enable(Modules.Setter(freshCtx), freshCtx)
  equal(fresh.procGlow, nil, "switching it back on follows the bar again")
end

-- Usable glow: auto counts for reactive abilities only -----------------------------------------------
do
  local profile, bar = Fixture()
  local module = Module("usableGlow")
  local storm = Modules.Context(profile, bar, bar.buttons[1])
  local overpower = Modules.Context(profile, bar, bar.buttons[2])
  check(not Modules.IsOn(module, Modules.Opts(storm), storm), "auto: Stormstrike doesn't glow")
  check(Modules.IsOn(module, Modules.Opts(overpower), overpower), "auto: Overpower glows")
  check(Modules.IsOn(module, Modules.Opts(Modules.Context(profile, bar, nil)), Modules.Context(profile, bar, nil)),
    "auto on the bar page counts as on")
  module.enable(Modules.Setter(storm), storm)
  equal(bar.buttons[1].reactive, true, "enabling on a button sets true")
end

-- Alerts --------------------------------------------------------------------------------------------------
local function whens(rows)
  local list = {}
  for _, row in ipairs(rows) do list[#list + 1] = row.when end
  return table.concat(list, ",")
end

do
  local profile, bar = Fixture()
  local entry = bar.buttons[1]
  local ctx = Modules.Context(profile, bar, entry)
  local alerts = Module("alerts")
  check(not Modules.IsOn(alerts, Modules.Opts(ctx), ctx), "no alerts by default")
  equal(whens(Alerts.Triggers(ctx, Modules.Opts(ctx))), "ready,readyEarly,cast", "a cooldown: ready, ready early, used")
  entry.targetDebuff = true
  local rows = Alerts.Triggers(ctx, Modules.Opts(ctx))
  equal(whens(rows), "ready,readyEarly,cast,applied,removed", "target debuff adds applied and removed")
  equal(rows[4].visual, true, "the debuff's button can show a visual when it's applied")
  equal(rows[5].visual, false, "nothing can show when it's removed")
  entry.watchAura = true
  rows = Alerts.Triggers(ctx, Modules.Opts(ctx))
  equal(rows[4].visual, false, "an own buff has no aura button for a visual")

  local item = Modules.Context(profile, bar, bar.buttons[3])
  equal(whens(Alerts.Triggers(item, Modules.Opts(item))), "ready,cast", "an item: ready and used")
  local charges = { type = "charges", buttons = { { spell = 324 } } }
  local chargeCtx = Modules.Context(profile, charges, charges.buttons[1])
  equal(whens(Alerts.Triggers(chargeCtx, Modules.Opts(chargeCtx))), "applied,removed", "charges: come back, run out")
  local buffs = { type = "buffs", buttons = { { aura = { 1 } } } }
  local buffCtx = Modules.Context(profile, buffs, buffs.buttons[1])
  equal(whens(Alerts.Triggers(buffCtx, Modules.Opts(buffCtx))), "applied,removed", "a buff: applied, removed")

  -- Setting a list equal to the bar's keeps nothing on the button.
  bar.buttonDefaults.alerts = { { when = "ready", kind = "sound", sound = "drop" } }
  local set = Modules.Setter(ctx)
  set("alerts", Alerts.Copy(bar.buttonDefaults.alerts))
  equal(entry.alerts, nil, "a copy of the bar's alerts follows the bar")
  local mine = Alerts.Copy(bar.buttonDefaults.alerts)
  mine[#mine + 1] = { when = "cast", kind = "visual", visual = "flash:red" }
  Modules.Setter(ctx)("alerts", mine)
  equal(#entry.alerts, 2, "a different list is the button's own")
  check(Modules.IsOn(alerts, Modules.Opts(ctx), ctx), "alerts on")
  equal(Alerts.VisualFor(Modules.Opts(ctx), "cast")[3], "flash", "the visual for a trigger")
  alerts.disable(Modules.Setter(ctx), ctx)
  equal(#entry.alerts, 0, "switched off: an empty list of its own")
  check(not Modules.IsOn(alerts, Modules.Opts(ctx), ctx), "alerts off")
end

-- Old sound settings become alerts ---------------------------------------------------------------------------
do
  local layer = { soundStart = "drop", soundEnd = "none", earlySound = "say:Ready" }
  Alerts.MigrateLayer(layer)
  equal(#layer.alerts, 2, "two sounds became two alerts")
  equal(layer.alerts[1].when, "applied", "soundStart: applied")
  equal(layer.alerts[2].when, "readyEarly", "earlySound: ready early")
  equal(layer.soundStart, nil, "old keys cleared")
  local off = { soundEnd = "none" }
  Alerts.MigrateLayer(off)
  equal(#off.alerts, 0, "an explicit none stays explicit")
  local untouched = {}
  Alerts.MigrateLayer(untouched)
  equal(untouched.alerts, nil, "a layer without sounds keeps following the one above")
end

-- Own, reset, differing -----------------------------------------------------------------------------------
do
  local profile, bar = Fixture()
  local module = Module("rangeTint")
  bar.buttons[1].rangeTint = false
  bar.buttons[2].rangeTint = false
  check(Modules.IsOwn(module, bar.buttons[1]), "own key counts")
  check(not Modules.IsOwn(module, bar.buttons[3]), "no own key")
  equal(Modules.Differing(module, bar), 2, "two buttons differ")
  Modules.Reset(module, bar.buttons[1])
  equal(bar.buttons[1].rangeTint, nil, "reset clears the own key")
  equal(Modules.Differing(module, bar), 1, "one left")
  -- Changing the bar doesn't touch the buttons.
  local barCtx = Modules.Context(profile, bar, nil)
  module.disable(Modules.Setter(barCtx), barCtx)
  equal(bar.buttonDefaults.rangeTint, false, "bar default written")
  equal(bar.buttons[2].rangeTint, false, "button's own value kept")
  check(Modules.DiffSummary(profile, bar, bar.buttons[1]) == "", "a button matching its bar has no summary")
end

-- Shared cooldowns ----------------------------------------------------------------------------------------
do
  local entry = { spell = 8056, targetDebuff = true }
  check(not Groups.IsGroup(entry), "no group yet")
  equal(Groups.ResolveSpell(entry), nil, "Frost Shock alone isn't known")
  local family = Groups.FamilyOf(8056)
  equal(family and family.name, "Shocks", "Frost Shock is a shock")
  for _, id in ipairs(Groups.Missing(entry, family)) do Groups.Add(entry, { spell = id }) end
  check(Groups.IsGroup(entry), "group made")
  equal(#Groups.Members(entry), 3, "three shocks")
  equal(Groups.ResolveSpell(entry), 8042, "falls back to a known shock")
  equal(Groups.Add(entry, { item = 5 }), nil, "an item can't join a spell's group")
  Groups.Remove(entry, 8042)
  equal(#Groups.Members(entry), 2, "one taken out")
  Groups.Remove(entry, 8050)
  check(entry.group == nil, "an empty group is dropped")
  local debuffs = Groups.DebuffIDs({ spell = 8042, group = { 8050 } }, 8042)
  check(debuffs[10447], "a shock group watches every rank of Flame Shock")
  local potions = { item = 1, group = { 2 } }
  equal(Groups.ResolveItem(potions), 2, "an item group tracks the one you carry")
  -- Migration: an old shock button with Target debuff becomes a group.
  local db = { profiles = { p = { bars = { { buttons = { { spell = 8056, targetDebuff = true }, { spell = 17364, targetDebuff = true } } } } } } }
  Groups.Migrate(db)
  local buttons = db.profiles.p.bars[1].buttons
  check(Groups.IsGroup(buttons[1]), "old shock button migrated")
  check(not Groups.IsGroup(buttons[2]), "other spells left alone")
end

-- Presets -------------------------------------------------------------------------------------------------
do
  local profile, bar = Fixture()
  bar.buttonDefaults.procGlow = false
  local entry = bar.buttons[1]
  local ctx = Modules.Context(profile, bar, entry)
  local touched = Modules.ApplyPreset(Modules.PRESETS[1], ctx, Modules.Setter(ctx))
  equal(#touched, 4, "proc ability preset touches four modules")
  local debuffPreset = Modules.PRESETS[4]
  local other = bar.buttons[2]
  local otherCtx = Modules.Context(profile, bar, other)
  Modules.ApplyPreset(debuffPreset, otherCtx, Modules.Setter(otherCtx))
  equal(other.targetDebuff, true, "debuff preset switches target debuff on")
  equal(other.alerts and other.alerts[1].when, "removed", "and adds an alert for when it's removed")
  equal(entry.procGlow, true, "proc glow switched on for the button")
  local item = bar.buttons[3]
  local itemCtx = Modules.Context(profile, bar, item)
  local itemTouched = Modules.ApplyPreset(Modules.PRESETS[1], itemCtx, Modules.Setter(itemCtx))
  equal(#itemTouched, 1, "on an item only range tint applies")
end

print(("%d passed, %d failed"):format(passed, failures))
if failures > 0 then os.exit(1) end
