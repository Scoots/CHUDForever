-- Modules: the settings window's way of building a button. A module is one
-- feature (Cooldown, Proc glow, Range tint, Sound...) and owns a group of the
-- flat option keys in ns.BUTTON_DEFAULTS. Nothing new is saved: a module is
-- on when its keys make the effect show, off when they're at their off values.
-- A button starts from its bar's modules and can switch one off, change it or
-- add one of its own; the bar's page sets what every button starts with.
--
-- Pure logic, no frames: the cards' contents come from each module's draw(h,
-- ctx), where h holds the settings window's widget helpers. Checked by
-- tools/test_modules.lua.
--
-- ctx = { layer = "button" | "bar", barKind, entryKind = "spell" | "item" |
--         "slot" | "aura" (button layer), entry, bar, profile, name }
local _, ns = ...

local Plugins = {}
ns.Plugins = Plugins
ns.Modules = Plugins -- compatibility alias during internal rename

local Modules = Plugins

Modules.GROUPS = { { "show", "SHOW" }, { "highlight", "HIGHLIGHT" }, { "alert", "ALERT" }, { "track", "TRACK" } }

-- Layers -------------------------------------------------------------------------------------

-- A button's options: the built-in defaults, then the profile's, the bar's and
-- the button's own (each optional), as Bar.Options merges them.
function Modules.Merge(profile, bar, entry)
  local opts = {}
  for key, value in pairs(ns.BUTTON_DEFAULTS) do opts[key] = value end
  local layers = { profile and profile.buttonDefaults, bar and bar.buttonDefaults, entry }
  for index = 1, 3 do
    local layer = layers[index]
    if layer then
      for key in pairs(ns.BUTTON_DEFAULTS) do
        if layer[key] ~= nil then opts[key] = layer[key] end
      end
    end
  end
  return opts
end

-- The options in effect where ctx is: a button's, or what the bar gives its buttons.
function Modules.Opts(ctx)
  return Modules.Merge(ctx.profile, ctx.bar, ctx.layer == "button" and ctx.entry or nil)
end

-- The table a layer's own values live in: the button's entry, or the bar's defaults.
function Modules.Layer(ctx)
  if ctx.layer == "button" then return ctx.entry end
  ctx.bar.buttonDefaults = ctx.bar.buttonDefaults or {}
  return ctx.bar.buttonDefaults
end

-- set(key, value) for a layer. A value equal to what the layer would inherit
-- isn't kept, so a button that matches its bar again follows it again. Keys
-- that aren't options (a shared cooldown's members) go on the entry as given.
function Modules.Setter(ctx)
  local layer = Modules.Layer(ctx)
  local inherited
  if ctx.layer == "button" then
    inherited = Modules.Merge(ctx.profile, ctx.bar, nil)
  else
    inherited = Modules.Merge(ctx.profile, nil, nil)
  end
  return function(key, value)
    if ns.BUTTON_DEFAULTS[key] == nil then
      layer[key] = value
    elseif value == inherited[key] or (key == "alerts" and ns.Alerts.Equal(value, inherited[key])) then
      layer[key] = nil
    else
      layer[key] = value
    end
  end
end

-- Contexts ------------------------------------------------------------------------------------

local function FirstID(value)
  if type(value) == "table" then return value[1] end
  return value
end

function Modules.Context(profile, bar, entry)
  local ctx = { profile = profile, bar = bar, entry = entry, barKind = ns.Bar.Type(bar) }
  if not entry then
    ctx.layer = "bar"
    return ctx
  end
  ctx.layer = "button"
  if entry.slot then
    ctx.entryKind = "slot"
  elseif entry.item then
    ctx.entryKind = "item"
  elseif entry.aura or ctx.barKind ~= "cooldowns" then
    ctx.entryKind = "aura"
  else
    ctx.entryKind = "spell"
  end
  local id = FirstID(entry.aura) or FirstID(entry.spell)
  if type(id) == "number" and C_Spell then
    local name = C_Spell.GetSpellName(id)
    if not (ns.issecret and ns.issecret(name)) then ctx.name = name end
  end
  return ctx
end

-- Which buttons a module is for -----------------------------------------------------------------

-- A cooldown on a cooldown bar: a spell, an item or a trinket slot (or the bar's defaults for them).
local function CooldownButton(ctx)
  return ctx.barKind == "cooldowns" and (ctx.layer == "bar" or ctx.entryKind ~= "aura")
end

-- A spell's cooldown on a cooldown bar (or the bar's defaults for them).
local function SpellButton(ctx)
  return ctx.barKind == "cooldowns" and (ctx.layer == "bar" or ctx.entryKind == "spell")
end

-- A plain on/off module over one key.
local function Switch(key)
  return function(opts) return opts[key] == true end,
    function(set) set(key, true) end,
    function(set) set(key, false) end
end

local ANIMATION = { { "swipe", "Clock" }, { "wipe", "Wipe" }, { "none", "None" } }
local VISIBILITY = { { "always", "Always" }, { "cooldown", "On cooldown" }, { "ready", "When ready" } }

local function Label(list, key)
  for _, item in ipairs(list) do
    if item[1] == key then return item[2] end
  end
  return tostring(key)
end

-- Modules -------------------------------------------------------------------------------------

local LIST = {}
Modules.LIST = LIST
local byID = {}

local function Add(module)
  LIST[#LIST + 1] = module
  byID[module.id] = module
end

function Modules.Get(id) return byID[id] end

-- Cooldown -------------------------------------------------------------------------------------
Add({
  id = "cooldown", group = "show", title = "Cooldown", blurb = "Clock, wipe or number on the icon",
  keys = { "cooldown", "numbers", "desaturate", "gcd", "visibility" },
  applies = CooldownButton,
  isOn = function(opts) return opts.cooldown ~= "none" or opts.numbers == true or opts.desaturate == true end,
  enable = function(set)
    set("cooldown", "swipe")
    set("numbers", true)
    set("desaturate", true)
  end,
  disable = function(set)
    set("cooldown", "none")
    set("numbers", false)
    set("desaturate", false)
    set("gcd", false)
  end,
  summary = function(opts)
    local parts = { Label(ANIMATION, opts.cooldown) }
    if opts.numbers then parts[#parts + 1] = "number" end
    if opts.desaturate then parts[#parts + 1] = "gray" end
    if opts.gcd then parts[#parts + 1] = "GCD swipe" end
    if opts.visibility ~= "always" then parts[#parts + 1] = Label(VISIBILITY, opts.visibility):lower() end
    return table.concat(parts, " · ")
  end,
  draw = function(h, ctx)
    local spells = ctx.layer == "bar" or ctx.entryKind == "spell"
    local looks = { ANIMATION[1] }
    if spells then looks[#looks + 1] = ANIMATION[2] end
    looks[#looks + 1] = ANIMATION[3]
    h.Choice("Animation", looks, "cooldown")
    h.Choice("Show", VISIBILITY, "visibility")
    local checks = { { "Countdown number", "numbers" }, { "Gray on cooldown", "desaturate" } }
    if spells then checks[#checks + 1] = { "GCD swipe", "gcd" } end
    h.Checks(checks)
  end,
})

-- Mana cost ----------------------------------------------------------------------------------
do
  local isOn, enable, disable = Switch("manaCost")
  Add({
    id = "manaCost", group = "show", title = "Mana cost", blurb = "Cost in the corner of the icon",
    keys = { "manaCost" }, applies = SpellButton, isOn = isOn, enable = enable, disable = disable,
    summary = function() return "Cost in the corner of the icon" end,
  })
end

-- Shared cooldown ------------------------------------------------------------------------------
-- The button's own (never the bar's): which spells or items share its cooldown.
Add({
  id = "group", group = "show", title = "Shared cooldown",
  blurb = "One button for spells that share a cooldown (shocks, traps, potions)",
  keys = { "group", "groupIcon" }, own = true,
  applies = function(ctx)
    return ctx.layer == "button" and ctx.barKind == "cooldowns" and (ctx.entryKind == "spell" or ctx.entryKind == "item")
  end,
  isOn = function(_, ctx) return ns.Groups.IsGroup(ctx.entry) end,
  enable = function(set, ctx)
    -- Starts with the rest of a family the game has, if it's in one.
    local family = ctx.entry.spell and ns.Groups.FamilyOf(FirstID(ctx.entry.spell))
    local members = family and ns.Groups.Missing(ctx.entry, family) or {}
    set("group", #members > 0 and members or {})
  end,
  disable = function(set)
    set("group", nil)
    set("groupIcon", nil)
  end,
  summary = function(_, ctx)
    local count = #ns.Groups.Members(ctx.entry)
    if count < 2 then return "Shift- or Alt-drop a spell on the button to add one" end
    return ("%d share it · icon: %s"):format(count, ctx.entry.groupIcon == "first" and "its own" or "last used")
  end,
  draw = function(h, ctx) h.GroupMembers() end,
})

-- Proc glow -----------------------------------------------------------------------------------
do
  local isOn, enable, disable = Switch("procGlow")
  Add({
    id = "procGlow", group = "highlight", title = "Proc glow", blurb = "A glow while the game highlights the spell",
    keys = { "procGlow", "procStyle", "procColor" }, applies = SpellButton, isOn = isOn, enable = enable, disable = disable,
    summary = function(opts)
      local looks = { border = "Pulsing border", ants = "Marching ants", both = "Border and ants" }
      return ("%s, %s, while it's highlighted"):format(looks[opts.procStyle] or "Pulsing border",
        tostring(opts.procColor or "gold"))
    end,
    draw = function(h)
      h.Choice("Look", { { "border", "Border" }, { "ants", "Ants" }, { "both", "Both" } }, "procStyle")
      h.Pick("Color", ns.Glow.COLORS, "procColor")
    end,
  })
end

-- Icon swap ---------------------------------------------------------------------------------------
-- The button's own: another spell's icon while that spell is highlighted
-- (Frostbolt showing Ice Lance on a proc).
Add({
  id = "swap", group = "highlight", title = "Icon swap", blurb = "Show another spell's icon while it procs",
  keys = { "swap" }, own = true,
  applies = function(ctx) return ctx.layer == "button" and ctx.barKind == "cooldowns" and ctx.entryKind == "spell" end,
  isOn = function(_, ctx) return ctx.entry.swap ~= nil end,
  enable = function() end, -- set by Shift-dropping the other spell on the button
  disable = function(set) set("swap", nil) end,
  summary = function(_, ctx)
    local name = C_Spell and C_Spell.GetSpellName(FirstID(ctx.entry.swap))
    if name and not (ns.issecret and ns.issecret(name)) then return "Shows " .. name .. " while it procs" end
    return "Shift-drop a spell on the button in edit mode"
  end,
  draw = function(h) h.SwapInfo() end,
})

-- Usable glow ---------------------------------------------------------------------------------
Add({
  id = "usableGlow", group = "highlight", title = "Usable glow",
  blurb = "Glow whenever it can be cast (Overpower, Execute...)",
  keys = { "reactive" }, applies = SpellButton,
  isOn = function(opts, ctx)
    if opts.reactive == true then return true end
    if opts.reactive ~= "auto" then return false end
    if ctx.layer == "bar" then return true end
    local reactive = ns.Button and ns.Button.REACTIVE
    return reactive ~= nil and reactive[ctx.name or ""] == true
  end,
  enable = function(set, ctx) set("reactive", ctx.layer == "bar" and "auto" or true) end,
  disable = function(set) set("reactive", false) end,
  summary = function(opts, ctx)
    if opts.reactive == "auto" and ctx.layer == "bar" then return "Reactive abilities (Overpower, Execute...)" end
    return "Glows whenever it can be cast"
  end,
  draw = function(h, ctx)
    if ctx.layer == "bar" then
      h.Choice("For", { { "auto", "Reactive abilities" }, { true, "Every spell" } }, "reactive")
    end
  end,
})

-- Range tint ----------------------------------------------------------------------------------
do
  local isOn, enable, disable = Switch("rangeTint")
  Add({
    id = "rangeTint", group = "highlight", title = "Range tint", blurb = "Red when the target is out of range",
    keys = { "rangeTint" }, applies = CooldownButton, isOn = isOn, enable = enable, disable = disable,
    summary = function() return "Red when out of range" end,
    draw = function(h) h.RangeInfo() end,
  })
end

-- Mana tint -----------------------------------------------------------------------------------
Add({
  id = "manaTint", group = "highlight", title = "Mana tint", blurb = "Blue while you can't afford it",
  keys = { "manaTint", "usableTint" }, applies = SpellButton,
  isOn = function(opts) return opts.manaTint == true end,
  enable = function(set) set("manaTint", true) end,
  disable = function(set) set("manaTint", false) end,
  summary = function(opts)
    if opts.usableTint then return "Blue without mana, dim when unusable" end
    return "Blue without mana"
  end,
  draw = function(h)
    h.Checks({ { "Blue without mana", "manaTint" }, { "Dim when unusable", "usableTint" } })
  end,
})

-- Ready-early glow ------------------------------------------------------------------------------
do
  local isOn, enable, disable = Switch("earlyReady")
  Add({
    id = "earlyReady", group = "alert", title = "Ready-early glow", blurb = "Alert and pop when a reset skips the cooldown",
    keys = { "earlyReady" }, applies = SpellButton, isOn = isOn, enable = enable, disable = disable,
    summary = function() return "Alert and pop when a reset skips the cooldown" end,
    draw = function(h) h.Note("For a sound or a flash too, add an alert \"When it's ready early\" in Alerts.") end,
  })
end

-- Alerts --------------------------------------------------------------------------------------
-- Like the game's "Add Alert": a trigger (applied, removed, ready, ready
-- early, used) and a sound or a visual. Which triggers fit is Alerts.Triggers.
Add({
  id = "alerts", group = "alert", title = "Alerts", blurb = "A sound or a flash when it's applied, removed, ready or used",
  keys = { "alerts" },
  applies = function() return true end,
  isOn = function(opts) return #ns.Alerts.List(opts) > 0 end,
  enable = function() end, -- the card just opens: add the first alert there
  disable = function(set) set("alerts", {}) end,
  summary = function(opts)
    local list = ns.Alerts.List(opts)
    if #list == 0 then return "Add a sound or a visual for a trigger" end
    local parts = {}
    for index, alert in ipairs(list) do
      if index > 2 then
        parts[#parts + 1] = "..."
        break
      end
      parts[#parts + 1] = ns.Alerts.Describe(alert)
    end
    return (#list == 1 and "1 alert: " or (#list .. " alerts: ")) .. table.concat(parts, ", ")
  end,
  draw = function(h) h.Alerts() end,
})

-- Target debuff --------------------------------------------------------------------------------
-- On, or "auto": on for spells that leave a debuff, which then set
-- themselves up by whether they have a cooldown (Debuff.lua).
local function LeavesDebuff(ctx)
  local debuff = ns.Debuff
  return ctx.entry ~= nil and debuff ~= nil and debuff.EntryLeavesDebuff ~= nil and debuff.EntryLeavesDebuff(ctx.entry)
end

Add({
  id = "targetDebuff", group = "track", title = "Target debuff", blurb = "Time left on your debuff, on the icon",
  keys = { "targetDebuff", "debuffGray" }, applies = SpellButton,
  isOn = function(opts, ctx)
    if opts.targetDebuff == true then return true end
    if opts.targetDebuff ~= "auto" then return false end
    return ctx.layer == "bar" or LeavesDebuff(ctx)
  end,
  enable = function(set, ctx) set("targetDebuff", ctx.layer == "bar" and "auto" or true) end,
  disable = function(set) set("targetDebuff", false) end,
  summary = function(opts, ctx)
    if opts.targetDebuff == "auto" then
      if ctx.layer == "bar" then return "Auto: spells that leave a debuff show it" end
      return "Auto: my " .. (ctx.name or "debuff") .. " on target"
    end
    if ctx.name then return "My " .. ctx.name .. " debuff on target" end
    return "My debuff on target"
  end,
  draw = function(h, ctx)
    h.Choice("When", { { "auto", "Auto" }, { true, "Always" } }, "targetDebuff")
    if h.Opt("targetDebuff") == true then
      h.Checks({ { "Gray until it's on the target", "debuffGray" } })
    else
      h.Note("Auto: a spell that leaves a debuff shows it. Without a cooldown (Corruption) it's gray until the debuff is on the target; with one (Flame Shock) it stays in color, with the cooldown as a spinner and the debuff's time left as the number.")
    end
    if ctx.layer == "button" and ns.Groups.IsGroup(ctx.entry) then
      h.Note("A shared cooldown: shows whichever member's debuff is on the target, the one ending first if there are several.")
    end
  end,
})

-- Aura (fixed: an aura button is always one) -------------------------------------------------------
Add({
  id = "aura", group = "show", title = "Aura", blurb = "Whose aura, when it shows, its glow and timer",
  keys = { "show", "unit", "auraGlow", "timerRed", "auraTimer" }, fixed = true,
  applies = function(ctx)
    if ctx.layer == "button" then
      return ctx.entryKind == "aura" and (ctx.barKind == "cooldowns" or ctx.barKind == "alerts")
    end
    return ctx.barKind == "buffs" or ctx.barKind == "debuffs" or ctx.barKind == "alerts"
  end,
  isOn = function() return true end,
  enable = function() end, disable = function() end,
  summary = function(opts, ctx)
    local parts = {}
    if ctx.layer == "button" then
      parts[1] = opts.unit == "target" and "My debuff on target" or "My buff"
      parts[2] = Label({ { "active", "while up" }, { "missing", "when missing" }, { "always", "always" } }, opts.show)
    end
    if opts.auraGlow then parts[#parts + 1] = "glow" end
    if (opts.timerRed or 0) > 0 then parts[#parts + 1] = "red under " .. opts.timerRed .. "s" end
    return table.concat(parts, " · ")
  end,
  draw = function(h, ctx)
    if ctx.layer == "button" then
      if not (ctx.barKind == "cooldowns" and ctx.entry.spell) then
        h.Choice("Whose", { { "player", "My buff" }, { "target", "My debuff on target" } }, "unit")
      end
      h.Choice("Show", { { "active", "While up" }, { "missing", "When missing" }, { "always", "Always" } }, "show")
    end
    h.Choice("Time left", { { "spinner", "Spinner" }, { "number", "Number" }, { "both", "Both" } }, "auraTimer")
    h.Checks({ { "Rotating border while it's up", "auraGlow" } })
    h.Stepper("Time red under", "timerRed", 1, 0, 15)
  end,
})

-- Charges (fixed: a charge bar's button is always one) ---------------------------------------------
Add({
  id = "charges", group = "show", title = "Charges", blurb = "Segments, orbs or gems for stacks",
  keys = { "pips", "chargeLook", "chargeOrb", "chargeGem", "chargeGap", "numbers" }, fixed = true,
  applies = function(ctx) return ctx.barKind == "charges" end,
  isOn = function() return true end,
  enable = function() end, disable = function() end,
  summary = function(opts)
    local looks = { { "bar", "Segments" }, { "orbs", "Orbs" }, { "gems", "Gems" }, { "icon", "Spell icon" } }
    return ("%s · %d charges"):format(Label(looks, opts.chargeLook), opts.pips or 3)
  end,
  draw = function(h, ctx)
    if ctx.layer == "bar" then h.ChargeLook() end
    h.Stepper("Most charges", "pips", 1, 1, 20)
    if ctx.layer == "bar" then
      h.Stepper("Gap", "chargeGap", 1, 0, 20)
      h.Checks({ { "Show the number of charges", "numbers" } })
    end
  end,
})

-- Using them -------------------------------------------------------------------------------------

-- The modules for where ctx is, in order.
function Modules.ForContext(ctx)
  local list = {}
  for _, module in ipairs(LIST) do
    if module.applies(ctx) then list[#list + 1] = module end
  end
  return list
end

function Modules.IsOn(module, opts, ctx)
  return module.isOn(opts, ctx) == true
end

-- Whether a layer (a button's entry, or a bar's defaults) sets any of a module's keys itself.
function Modules.IsOwn(module, layer)
  if not layer then return false end
  for _, key in ipairs(module.keys) do
    if layer[key] ~= nil then return true end
  end
  return false
end

-- Clears a layer's own values for a module, so it follows the layer above again.
function Modules.Reset(module, layer)
  if not layer then return end
  for _, key in ipairs(module.keys) do layer[key] = nil end
end

-- How many of a bar's buttons set a module's keys themselves.
function Modules.Differing(module, bar)
  local count = 0
  for _, entry in ipairs(bar.buttons or {}) do
    if Modules.IsOwn(module, entry) then count = count + 1 end
  end
  return count
end

-- How a button differs from its bar, in a line: "Adds Ready-early glow, Sound · Range tint off".
function Modules.DiffSummary(profile, bar, entry)
  local ctx = Modules.Context(profile, bar, entry)
  local barCtx = Modules.Context(profile, bar, nil)
  local mine, theirs = Modules.Opts(ctx), Modules.Opts(barCtx)
  local adds, offs, changes = {}, {}, {}
  for _, module in ipairs(Modules.ForContext(ctx)) do
    if not module.own and not module.fixed and Modules.IsOwn(module, entry) then
      local on, barOn = Modules.IsOn(module, mine, ctx), Modules.IsOn(module, theirs, barCtx)
      if on and not barOn then
        adds[#adds + 1] = module.title
      elseif barOn and not on then
        offs[#offs + 1] = module.title .. " off"
      else
        changes[#changes + 1] = module.title
      end
    elseif module.fixed and Modules.IsOwn(module, entry) then
      changes[#changes + 1] = module.title
    end
  end
  local parts = {}
  if #adds > 0 then parts[#parts + 1] = "Adds " .. table.concat(adds, ", ") end
  if #offs > 0 then parts[#parts + 1] = table.concat(offs, ", ") end
  if #changes > 0 then parts[#parts + 1] = "Changes " .. table.concat(changes, ", ") end
  return table.concat(parts, " · ")
end

-- Presets ---------------------------------------------------------------------------------------
-- Quick starts for a button: modules to switch on, with values to set.
Modules.PRESETS = {
  { name = "Proc ability", modules = { procGlow = {}, usableGlow = {}, rangeTint = {}, manaTint = {} } },
  { name = "Interrupt", modules = { cooldown = {}, rangeTint = {},
    alerts = { alerts = { { when = "ready", kind = "visual", visual = "flash:white" } } } } },
  { name = "Defensive cooldown", modules = { cooldown = { visibility = "cooldown" },
    alerts = { watchAura = true, alerts = { { when = "ready", kind = "sound", sound = "say:name" } } } } },
  { name = "Debuff to keep up", modules = { targetDebuff = {},
    alerts = { alerts = { { when = "removed", kind = "sound", sound = "say:name" } } } } },
}

local function Copy(value)
  if type(value) ~= "table" then return value end
  local copy = {}
  for key, inner in pairs(value) do copy[key] = Copy(inner) end
  return copy
end

-- Applies a preset: each module that applies here is switched on and given
-- the preset's values (copies: the button gets its own). Returns the IDs of
-- the modules it touched.
function Modules.ApplyPreset(preset, ctx, set)
  local touched = {}
  for _, module in ipairs(LIST) do
    local values = preset.modules[module.id]
    if values and module.applies(ctx) then
      module.enable(set, ctx)
      for key, value in pairs(values) do set(key, Copy(value)) end
      touched[#touched + 1] = module.id
    end
  end
  return touched
end
